#!/usr/bin/env python3
"""What the test wire really did in one session, measured from the wire probe's records.

    python3 tools/net/wire_stats.py <session dir>

Every peer sends a small unreliable probe stream (session_probe.gd) through the same conditioned wire as
the game, and writes peerN.wire: "me <id>", "s <to> <seq> <sent_ms>", "r <from> <seq> <sent_ms> <recv_ms>".
Per directed path this measures loss and its runs, duplication, reordering (RFC 4737) and one-way delay,
and check() holds each against the conditions the scenario asked for. Samples whose flight overlaps a
hitch or a deliberate freeze on either end are left out of the delay figures: those are the machine,
not the wire.
"""

from __future__ import annotations

import math
import re
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from scenario_args import peer_options  # noqa: E402

# The frame clock a delay measured above the transport carries: the sender releases a packet on the poll
# nearest its due time (half a 60 Hz frame either way), the receiver reads it on its next poll. The
# median may sit up to this much late on a loaded machine; the release alone spreads the quartiles by this.
QUANT_MS = 30.0
QUANT_IQR_MS = 9.0
# Relative tolerance on a measured rate or spread; a third of the asked value must fall outside it.
RATE_BAND = 0.4
# Below this many samples a statistic is not judged.
MIN_SAMPLES = 150
FREEZE_FORM = re.compile(r"^(match|hub|any)(\d*)@([\d.]+)\+(\d+)$")
CONDITION_KEYS = ("loss", "delay-ms", "jitter-ms", "burst-ms", "dup", "reorder")


class PeerWire:
    def __init__(self, index: int, path: Path):
        self.index = index
        self.ids: list[int] = []
        self.sends: dict[int, list[tuple[int, float]]] = {}
        self.arrivals: dict[int, list[tuple[int, float, float]]] = {}
        for raw in path.read_text(errors="replace").splitlines():
            part = raw.split()
            try:
                if part[0] == "me":
                    self.ids.append(int(part[1]))
                elif part[0] == "s":
                    self.sends.setdefault(int(part[1]), []).append((int(part[2]), float(part[3])))
                elif part[0] == "r":
                    self.arrivals.setdefault(int(part[1]), []).append((int(part[2]), float(part[3]), float(part[4])))
            except (IndexError, ValueError):
                continue  # a line cut short by a killed process


def load(session: Path) -> dict[int, PeerWire]:
    wires = {}
    for path in session.glob("peer*.wire"):
        index = int(re.sub(r"\D", "", path.stem))
        wires[index] = PeerWire(index, path)
    return wires


def quiet_windows(lines) -> list[tuple[float, float]]:
    """Wall-clock windows (ms) in which this machine was not running: hitches and freezes."""
    windows = []
    stall_start = None
    for line in lines:
        if line.tag == "HITCH":
            ms = float(line.kv.get("ms", 0))
            windows.append((line.w * 1000.0 - ms, line.w * 1000.0))
        elif line.tag == "STALL" and line.rest.startswith("ms="):
            stall_start = line.w * 1000.0
        elif line.tag == "STALL" and line.rest.startswith("over") and stall_start is not None:
            windows.append((stall_start, line.w * 1000.0))
            stall_start = None
    return windows


def _quantile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    return ordered[min(int(q * (len(ordered) - 1)), len(ordered) - 1)] if ordered else float("nan")


def measure(sends: list[tuple[int, float]], arrivals: list[tuple[int, float, float]],
            quiet: list[tuple[float, float]]) -> dict | None:
    """One path's figures. Loss is counted between the first and last sequence that arrived."""
    first: dict[int, tuple[float, float]] = {}
    order: list[int] = []
    for seq, sent, recv in arrivals:
        if seq not in first:
            first[seq] = (sent, recv)
            order.append(seq)
    if not first:
        return None
    lo, hi = min(first), max(first)
    window = sorted({seq for seq, _ in sends if lo <= seq <= hi})
    lost = [seq for seq in window if seq not in first]
    runs = []
    for i, seq in enumerate(lost):
        if i > 0 and seq == lost[i - 1] + 1:
            runs[-1] += 1
        else:
            runs.append(1)
    reordered, extents, highest, got = 0, [], -1, set()
    for seq in order:
        if seq < highest:
            reordered += 1
            extents.append(sum(1 for later in range(seq + 1, highest + 1) if later in got))
        highest = max(highest, seq)
        got.add(seq)
    delays = [recv - sent for sent, recv in first.values()
              if not any(a < recv and b > sent for a, b in quiet)]
    sent_times = sorted(t for _, t in sends)
    spacing = statistics.median([b - a for a, b in zip(sent_times, sent_times[1:])]) if len(sent_times) > 2 else float("nan")
    recv_times = sorted(recv for _, _, recv in arrivals)
    gaps = [(b - a, a) for a, b in zip(recv_times, recv_times[1:])]
    gap, gap_at = max(gaps) if gaps else (0.0, 0.0)
    return {
        "heard": recv_times,
        "sent": len(window), "unique": len(first), "lost": len(lost),
        "loss": len(lost) / len(window) if window else 0.0,
        "run_mean": statistics.mean(runs) if runs else 0.0, "runs": len(runs),
        "dup": (len(arrivals) - len(first)) / len(first), "reorder": reordered / len(first),
        "extent": statistics.mean(extents) if extents else 0.0,
        "delays": len(delays), "excluded": len(first) - len(delays),
        "mean": statistics.mean(delays) if delays else float("nan"),
        "sd": statistics.stdev(delays) if len(delays) > 1 else float("nan"),
        "p05": _quantile(delays, 0.05), "p50": _quantile(delays, 0.5), "p95": _quantile(delays, 0.95),
        "iqr": _quantile(delays, 0.75) - _quantile(delays, 0.25),
        "max": max(delays) if delays else float("nan"), "spacing": spacing, "gap_max": gap, "gap_at": gap_at,
    }


def paths(session: Path, logs: dict[int, list]) -> dict[tuple[int, int], dict]:
    """(sender index, receiver index) -> figures, for every path the probe ran on."""
    wires = load(session)
    owner = {pid: w.index for w in wires.values() for pid in w.ids}
    out = {}
    for receiver in wires.values():
        for from_id, arrivals in receiver.arrivals.items():
            sender = wires.get(owner.get(from_id, -1))
            if sender is None:
                continue
            sends = [s for to in set(receiver.ids) for s in sender.sends.get(to, [])]
            quiet = quiet_windows(logs.get(sender.index, [])) + quiet_windows(logs.get(receiver.index, []))
            figures = measure(sends, arrivals, quiet)
            if figures is not None:
                out[(sender.index, receiver.index)] = figures
    return out


# --- What the scenario asked for ------------------------------------------------

def _num(opts: dict, key: str, default: float = 0.0) -> float:
    try:
        return float(opts.get(key, default))
    except (TypeError, ValueError):
        return default


def conditioned(opts: dict) -> bool:
    return any(_num(opts, k) > 0.0 for k in CONDITION_KEYS)


def expected_loss(opts: dict) -> float:
    """Stationary loss of the configured link: Bernoulli, or Gilbert-Elliott's two-state mix."""
    good, burst, gap = _num(opts, "loss"), _num(opts, "burst-ms"), _num(opts, "burst-gap-ms")
    if burst <= 0.0 or gap <= 0.0:
        return good
    bad_share = burst / (burst + gap)
    return bad_share * _num(opts, "burst-loss", 1.0) + (1.0 - bad_share) * good


def expected_run(opts: dict, spacing: float) -> float:
    """Mean run of consecutive lost probes [spacing] ms apart: geometric, from the link's persistence."""
    burst, gap = _num(opts, "burst-ms"), _num(opts, "burst-gap-ms")
    if burst <= 0.0 or gap <= 0.0 or _num(opts, "burst-loss", 1.0) < 1.0 or _num(opts, "loss") > 0.0:
        return 1.0 / max(1.0 - expected_loss(opts), 1e-6)
    to_bad, to_good = 1.0 / gap, 1.0 / burst
    share = to_bad / (to_bad + to_good)
    stay = share + (1.0 - share) * math.exp(-(to_bad + to_good) * spacing)
    return 1.0 / max(1.0 - stay, 1e-6)


def jitter_iqr(opts: dict) -> float:
    """Interquartile range of the configured jitter: robust to the few held-back or hitched packets."""
    spread = _num(opts, "jitter-ms")
    return 1.349 * spread if opts.get("jitter-dist", "uniform") == "normal" else spread


def one_way_extra_ms(opts: dict) -> float:
    """The latest a packet can reasonably be on this line beyond a clean one: the base delay, the
    jitter's reach, a hold-back, and the 99th percentile of a bad spell."""
    spread = _num(opts, "jitter-ms")
    reach = spread if opts.get("jitter-dist", "uniform") != "normal" else 3.0 * spread
    held = _num(opts, "reorder-ms") if _num(opts, "reorder") > 0.0 else 0.0
    spell = math.log(100.0) * _num(opts, "burst-ms") if _num(opts, "burst-gap-ms") > 0.0 else 0.0
    return _num(opts, "delay-ms") + reach + held + spell


def freezes(opts: dict) -> list[int]:
    """Milliseconds of every freeze this peer was told to make."""
    out = [int(m.group(4)) for spec in str(opts.get("freeze", "")).split(",") if (m := FREEZE_FORM.match(spec.strip()))]
    if _num(opts, "stall-at") > 0.0:
        out.append(int(_num(opts, "stall-ms")))
    return out


# --- The verdict ------------------------------------------------------------------

def check_path(opts: dict, m: dict) -> list[str]:
    """What on one conditioned path does not match the conditions asked for."""
    bad = []
    n = m["sent"]
    if n < MIN_SAMPLES:
        return [f"only {n} probes crossed it, too few to measure the wire"]
    loss = expected_loss(opts)
    dup = _num(opts, "dup")
    if dup == 0.0:
        run = expected_run(opts, m["spacing"])
        sigma = math.sqrt(max(loss * (1.0 - loss), 1e-9) * run / n)
        allowed = max(RATE_BAND * loss, 3.0 * sigma, 0.01)
        if abs(m["loss"] - loss) > allowed:
            bad.append(f"lost {m['loss']:.3f} of probes, asked {loss:.3f} (+-{allowed:.3f})")
        if loss > 0.0 and m["runs"] >= 20 and abs(m["run_mean"] - run) > RATE_BAND * run:
            bad.append(f"losses came in runs of {m['run_mean']:.2f}, the link makes {run:.2f} at {m['spacing']:.0f} ms")
    if loss == 0.0 or dup > 0.0:
        want = dup * (1.0 - loss)
        allowed = max(RATE_BAND * want, 3.0 * math.sqrt(max(want, 1e-9) / n), 0.005)
        if abs(m["dup"] - want) > allowed:
            bad.append(f"duplicated {m['dup']:.3f} of probes, asked {want:.3f} (+-{allowed:.3f})")
    reorder, held = _num(opts, "reorder"), _num(opts, "reorder-ms")
    free = str(opts.get("jitter-reorders", "false")).lower() in ("true", "1", "yes", "on")
    spread = _num(opts, "jitter-ms")
    if reorder > 0.0 and held >= 1.5 * m["spacing"] and spread == 0.0:
        allowed = max(RATE_BAND * reorder, 3.0 * math.sqrt(reorder / n))
        if abs(m["reorder"] - reorder) > allowed:
            bad.append(f"reordered {m['reorder']:.3f} of probes, asked {reorder:.3f} held {held:.0f} ms (+-{allowed:.3f})")
    elif reorder > 0.0 and held > m["spacing"] and m["reorder"] == 0.0:
        bad.append(f"asked to hold back {reorder:.3f} by {held:.0f} ms, and nothing arrived out of order")
    elif reorder == 0.0 and not free and m["reorder"] > 0.002:
        bad.append(f"an in-order line reordered {m['reorder']:.3f} of probes")
    if m["delays"] < MIN_SAMPLES:
        return bad
    base = _num(opts, "delay-ms")
    iqr = jitter_iqr(opts)
    # Jitter drawn afresh per packet and kept in order is lifted by the packet ahead: only bounds hold.
    coupled = spread > 0.0 and not free and _num(opts, "jitter-tau-ms") < 100.0
    excess = math.sqrt(max(m["iqr"] ** 2 - QUANT_IQR_MS ** 2, 0.0))
    low = base - (0.75 if coupled else 0.4) * iqr - 5.0
    high = base + (1.0 if coupled else 0.4) * iqr + QUANT_MS
    if not low <= m["p50"] <= high:
        bad.append(f"median one-way delay {m['p50']:.1f} ms, asked {base:.0f} ms (allowed {low:.0f}..{high:.0f})")
    if spread > 0.0 and not coupled and not (1.0 - RATE_BAND) * iqr <= excess <= (1.0 + RATE_BAND) * iqr + 3.0:
        bad.append(f"delay interquartile range {excess:.1f} ms beyond the frame clock, asked {iqr:.1f} ms")
    elif coupled and excess < 0.25 * iqr:
        bad.append(f"delay interquartile range {excess:.1f} ms: the jitter asked ({spread:.0f} ms) is not on the wire")
    elif spread == 0.0 and excess > 15.0:
        bad.append(f"delay interquartile range {excess:.1f} ms on a line asked for no jitter")
    return bad


def check(session: Path, scenario: dict, logs: dict[int, list]) -> tuple[list[tuple[str, str]], dict]:
    """(peer label, message) for every way the wire did not do what the scenario asked, and the figures."""
    peers = int(scenario.get("peers", 0))
    if not any(k in scenario for k in ("common", "host", "client", "peer")):
        return [], {}
    measured = paths(session, logs)
    failures = []
    for (sender, receiver), m in sorted(measured.items()):
        opts = peer_options(scenario, sender)
        if conditioned(opts):
            for message in check_path(opts, m):
                failures.append((_label(sender), f"wire to {_label(receiver)}: {message}"))
    for index in range(peers):
        opts = peer_options(scenario, index)
        wanted = freezes(opts)
        if not wanted:
            continue
        lines = logs.get(index, [])
        stalls = [l for l in lines if l.tag == "STALL" and l.rest.startswith("ms=")]
        made = [int(l.kv.get("ms", -1)) for l in stalls]
        for ms in wanted:
            if ms in made:
                made.remove(ms)
            else:
                failures.append((_label(index), f"asked to freeze {ms} ms, and never did"))
        for a, b in quiet_windows(lines):
            length = b - a
            if not any(abs(length - ms) < 250.0 for ms in wanted):
                continue
            for (sender, receiver), m in measured.items():
                around = [t for t in m["heard"] if a - 2000.0 <= t <= b + 2000.0] if sender == index else []
                silent = max((y - x for x, y in zip(around, around[1:]) if x <= b and y >= a), default=0.0)
                if around and silent < 0.9 * length:
                    failures.append((_label(index), f"froze {length:.0f} ms, yet {_label(receiver)} kept hearing it "
                                                    f"(longest silence {silent:.0f} ms)"))
    figures = {f"{_label(s)}->{_label(r)}": {k: (round(v, 4) if isinstance(v, float) else v)
                                             for k, v in m.items() if k != "heard"}
               for (s, r), m in sorted(measured.items())}
    return failures, figures


def _label(index: int) -> str:
    return "host" if index == 0 else f"client{index}"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    session = Path(sys.argv[1])
    from check_session import Peer  # noqa: E402  (the log parser lives there)
    logs = {int(re.sub(r"\D", "", p.stem)): Peer(int(re.sub(r"\D", "", p.stem)), p).lines for p in session.glob("peer*.log")}
    for (s, r), m in sorted(paths(session, logs).items()):
        print(f"{_label(s)}->{_label(r)}: sent {m['sent']} lost {m['loss']:.3f} (runs {m['runs']} mean {m['run_mean']:.2f}) "
              f"dup {m['dup']:.3f} reorder {m['reorder']:.3f} (extent {m['extent']:.2f}) | delay n={m['delays']} "
              f"(-{m['excluded']} in hitches) mean {m['mean']:.1f} sd {m['sd']:.1f} iqr {m['iqr']:.1f} p05 {m['p05']:.1f} p50 {m['p50']:.1f} "
              f"p95 {m['p95']:.1f} max {m['max']:.1f} | spacing {m['spacing']:.1f} longest silence {m['gap_max']:.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
