#!/usr/bin/env python3
"""Verdict on one multi-peer session directory written by tools/net/run_session.sh.

    python3 tools/net/check_session.py <session dir> [--strict] [--quiet]

Reads scenario.json, exit.txt and peer<N>.log (peer0 is the host). Prints one VERDICT line and
every failure with the log line it came from, writes verdict.json. Exit 0 PASS, 1 FAIL, 2 unreadable.

A FAIL is any of: a peer that exited non-zero or was killed by the watchdog; a peer with no "END ok";
an engine or script error not on tools/net/error_allowlist.json; host and client disagreeing on the
rules, the event sequence, the state (scene, phase, round, guard, outcome, participants) or where a
body is; a client that never bound a match the host launched; a local body left unsimulated while
running or a ghost; a power, emote, ragdoll or cat one machine drew and another never did; a valid
key press the host never acted on; an expectation of the scenario that did not happen.
--strict also fails on allowlisted errors of class "known" (tracked game defects).
"""

from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
NL = re.compile(r"^NL w=(\d+) t=([\d.]+) (\w+) ?(.*)$")
ERROR_HEAD = re.compile(r"^(SCRIPT ERROR|USER SCRIPT ERROR|USER ERROR|ERROR): ?(.*)$")
WARNING_HEAD = re.compile(r"^(USER WARNING|WARNING): ?(.*)$")
CRASH = re.compile(r"handle_crash|Program crashed|Segmentation fault|signal 11|Dumping the backtrace|previously freed")
KV = re.compile(r"(\w[\w-]*)=(\S+)")

STATE_KEYS = ("kind", "epoch", "phase", "round", "guard", "outcome", "n")
EVENT_KINDS = {
    "match_started": ("n",),
    "race_started": (),
    "brawl_started": (),
    "round_started": ("round", "guard"),
    "round_resolved": ("round", "outcome"),
    "match_won": ("seat",),
}
# Seconds: how far apart two machines may see the same thing on a clean localhost wire.
SLACK = 1.0
FROZEN_GRACE = 6.0
POSITION_TOLERANCE = 2.5
POSITION_WINDOW = 0.75
SUSTAIN_SAMPLES = 3
PRESS_WINDOW = 1.5
WORLD_HIDDEN_GRACE = 8.0
STUCK_SECONDS = 15.0
STUCK_METRES = 1.0
SILENT_GUARD_SECONDS = 30.0
STALL_RECOVERY = 3.0
ABILITY_NAMES = {1: "bubble shield", 2: "hologram", 3: "armor lock", 4: "active camo", 5: "cat grenade"}


class Line:
    __slots__ = ("no", "w", "t", "tag", "rest", "kv")

    def __init__(self, no: int, w: int, t: float, tag: str, rest: str):
        self.no = no
        self.w = w / 1000.0
        self.t = t
        self.tag = tag
        self.rest = rest
        self.kv = dict(KV.findall(rest))


class Peer:
    def __init__(self, index: int, path: Path):
        self.index = index
        self.path = path
        self.name = "host" if index == 0 else f"client{index}"
        self.lines: list[Line] = []
        self.errors: list[tuple[int, str, str]] = []  # (line no, head kind, text)
        self.warnings: list[tuple[int, str]] = []
        self.crashes: list[tuple[int, str]] = []
        self.raw_count = 0
        self._session_end: float | None = None
        self.parse()

    def parse(self) -> None:
        at_pending = False
        with self.path.open(errors="replace") as handle:
            for no, raw in enumerate(handle, 1):
                self.raw_count = no
                text = raw.rstrip("\n")
                m = NL.match(text)
                if m:
                    self.lines.append(Line(no, int(m.group(1)), float(m.group(2)), m.group(3), m.group(4)))
                    continue
                e = ERROR_HEAD.match(text)
                if e:
                    self.errors.append((no, e.group(1), e.group(2)))
                    at_pending = True
                    continue
                if at_pending and text.lstrip().startswith("at: "):
                    # The engine's own "at: function (file:line)": what tells two null-node errors apart.
                    no0, kind0, text0 = self.errors[-1]
                    self.errors[-1] = (no0, kind0, f"{text0} @ {text.strip()[4:].split(' (')[0]}")
                at_pending = False
                wm = WARNING_HEAD.match(text)
                if wm:
                    self.warnings.append((no, wm.group(2)))
                    continue
                if CRASH.search(text):
                    self.crashes.append((no, text.strip()))

    def tagged(self, tag: str) -> list[Line]:
        """Lines of one kind, up to the moment this machine's session ended: after it, it mirrors nobody."""
        return [line for line in self.lines if line.tag == tag and line.w <= self.session_end]

    def tagged_all(self, tag: str) -> list[Line]:
        return [line for line in self.lines if line.tag == tag]

    @property
    def session_end(self) -> float:
        if self._session_end is None:
            ended = next((l.w for l in self.lines if l.tag == "SESSION"), None)
            self._session_end = ended if ended is not None and self.index != 0 else float("inf")
        return self._session_end

    def ref(self, line: Line | int, text: str = "") -> str:
        if isinstance(line, Line):
            return f"{self.path.name}:{line.no}: t={line.t:.2f} {line.tag} {line.rest}"[:400]
        return f"{self.path.name}:{line}: {text}"[:400]

    @property
    def first_w(self) -> float:
        return self.lines[0].w if self.lines else 0.0

    @property
    def last_w(self) -> float:
        return self.lines[-1].w if self.lines else 0.0

    def end_line(self) -> Line | None:
        ends = self.tagged_all("END")
        return ends[-1] if ends else None


class Verdict:
    def __init__(self) -> None:
        self.failures: list[dict] = []
        self.warnings: list[dict] = []
        self.known: list[dict] = []

    def fail(self, check: str, peer: str, message: str, ref: str = "") -> None:
        self.failures.append({"check": check, "peer": peer, "message": message, "ref": ref})

    def warn(self, check: str, peer: str, message: str, ref: str = "") -> None:
        self.warnings.append({"check": check, "peer": peer, "message": message, "ref": ref})


# --- Helpers -------------------------------------------------------------------


def state_of(kv: dict) -> tuple:
    return tuple(kv.get(k, "?") for k in STATE_KEYS)


def state_text(state: tuple) -> str:
    return " ".join(f"{k}={v}" for k, v in zip(STATE_KEYS, state))


def parse_bodies(rest: str) -> dict[str, dict]:
    """The bodies of one POS line: seat -> {role, pos, v, sim, vis, fl, pw}."""
    bodies: dict[str, dict] = {}
    if " | " not in rest:
        return bodies
    for part in rest.split(" | ")[1:]:
        fields = part.split(":")
        if len(fields) < 8:
            continue
        try:
            x, y, z = (float(v) for v in fields[2].split(","))
        except ValueError:
            continue
        bodies[fields[0]] = {
            "role": fields[1],
            "pos": (x, y, z),
            "v": float(fields[3][1:]),
            "sim": fields[4] == "sim1",
            "vis": fields[5] == "vis1",
            "floor": fields[6] == "fl1",
            "pw": int(fields[7][2:]),
        }
    return bodies


def seg_distance(p: tuple, a: tuple, b: tuple) -> float:
    ab = [b[i] - a[i] for i in range(3)]
    ap = [p[i] - a[i] for i in range(3)]
    denom = sum(c * c for c in ab)
    t = 0.0 if denom <= 1e-9 else max(0.0, min(1.0, sum(ap[i] * ab[i] for i in range(3)) / denom))
    return sum((ap[i] - ab[i] * t) ** 2 for i in range(3)) ** 0.5


def intervals(peer: Peer, tag: str, value_of) -> dict[str, list[tuple[str, float, float, Line]]]:
    """Per seat, the stretches a watched value held: (value, start, end, line)."""
    out: dict[str, list] = defaultdict(list)
    open_: dict[str, tuple[str, float, Line]] = {}
    for line in peer.lines:
        if line.tag in ("SCENE", "END", "SESSION"):
            for seat, (value, start, first) in open_.items():
                out[seat].append((value, start, line.w, first))
            open_.clear()
            continue
        if line.tag != tag:
            continue
        seat = line.kv.get("seat", "all")
        value = value_of(line)
        if seat in open_:
            old, start, first = open_[seat]
            out[seat].append((old, start, line.w, first))
        open_[seat] = (value, line.w, line)
    for seat, (value, start, first) in open_.items():
        out[seat].append((value, start, peer.last_w, first))
    return out


def load_allowlist() -> list[dict]:
    path = HERE / "error_allowlist.json"
    entries = json.loads(path.read_text()) if path.exists() else []
    for entry in entries:
        entry["_re"] = re.compile(entry["pattern"])
    return entries


# --- Checks --------------------------------------------------------------------


def check_exits(session: Path, peers: list[Peer], scenario: dict, v: Verdict) -> set[int]:
    """Exit codes and END lines. Returns the peers that were killed or quit on purpose."""
    gone: set[int] = set()
    exits: dict[int, int] = {}
    text = (session / "exit.txt").read_text() if (session / "exit.txt").exists() else ""
    for raw in text.splitlines():
        m = re.match(r"peer(\d+) exit=(-?\d+)", raw)
        if m:
            exits[int(m.group(1))] = int(m.group(2))
        if raw.startswith("watchdog killed"):
            v.fail("exit", "session", f"the watchdog had to kill the session ({raw})")
        m = re.match(r"killed peer(\d+)", raw)
        if m:
            gone.add(int(m.group(1)))
    expect = scenario.get("expect", {})
    for peer in peers:
        end = peer.end_line()
        quit_line = next((l for l in peer.lines if l.tag == "QUIT"), None)
        if quit_line is not None:
            gone.add(peer.index)
        if peer.index in gone and quit_line is None:
            continue
        if quit_line is not None and "mode=drop" in quit_line.rest:
            continue
        code = exits.get(peer.index)
        if code is None:
            v.fail("exit", peer.name, "no exit code recorded")
        elif code != 0:
            v.fail("exit", peer.name, f"exited {code}", peer.ref(end) if end else "")
        if end is None:
            v.fail("end", peer.name, "no END line: the process died or was killed before finishing",
                   peer.ref(peer.lines[-1]) if peer.lines else "")
        elif not end.rest.startswith("ok"):
            v.fail("end", peer.name, f"ended {end.rest.split(' lobby=')[0]}", peer.ref(end))
        elif "reason=host-lost" in end.rest and not expect.get("host_lost"):
            v.fail("end", peer.name, "lost the host in a scenario where the host does not quit", peer.ref(end))
    return gone


def check_errors(peers: list[Peer], v: Verdict, strict: bool) -> None:
    allow = load_allowlist()
    for peer in peers:
        grouped: dict[str, list[int]] = defaultdict(list)
        for no, kind, text in peer.errors:
            grouped[f"{kind}: {text}"].append(no)
        per_id: dict[str, list] = defaultdict(lambda: [0, None, ""])
        for message, numbers in grouped.items():
            entry = next((a for a in allow if a["_re"].search(message)), None)
            if entry is not None and entry.get("class") == "known" and "max" in entry:
                tally = per_id[entry["id"]]
                tally[0] += len(numbers)
                tally[1] = entry
                tally[2] = tally[2] or peer.ref(numbers[0], message)
            ref = peer.ref(numbers[0], message)
            if entry is None:
                v.fail("error", peer.name, f"{message[:240]} (x{len(numbers)})", ref)
            elif entry.get("class") == "known":
                item = {"check": "known-error", "peer": peer.name, "id": entry.get("id", "?"),
                        "message": f"{message[:200]} (x{len(numbers)})", "ref": ref}
                v.known.append(item)
                if strict:
                    v.fail("known-error", peer.name, item["message"], ref)
        for known_id, (count, entry, ref) in per_id.items():
            if not strict and count > int(entry["max"]):
                v.fail("error-flood", peer.name, f"{count} errors of known family [{known_id}], past its ceiling of {entry['max']}", ref)
        for no, text in peer.crashes:
            v.fail("crash", peer.name, text[:240], peer.ref(no, text))


def check_rules(host: Peer, clients: list[Peer], v: Verdict) -> None:
    def rules_by_epoch(peer: Peer) -> dict[str, Line]:
        return {l.kv.get("epoch", "?"): l for l in peer.tagged("MATCH") if l.rest.startswith("rules kind=match")}

    host_rules = rules_by_epoch(host)
    for client in clients:
        for epoch, line in rules_by_epoch(client).items():
            theirs = host_rules.get(epoch)
            if theirs is None:
                v.fail("rules", client.name, f"bound a match at epoch {epoch} the host never bound", client.ref(line))
                continue
            for key, value in theirs.kv.items():
                if line.kv.get(key) != value:
                    v.fail("rules", client.name,
                           f"rules differ from the host's at epoch {epoch}: {key}={line.kv.get(key)} here, {value} on the host",
                           client.ref(line))


def bound_times(peer: Peer, kind: str = "match") -> dict[str, float]:
    return {l.kv.get("epoch", "?"): l.w for l in peer.tagged("MATCH") if l.rest.startswith(f"bound kind={kind}")}


def check_bound(host: Peer, clients: list[Peer], gone: set[int], v: Verdict) -> None:
    host_launch = [l for l in host.tagged("LOBBY") if "phase=LAUNCHING" in l.rest]
    for client in clients:
        mine = bound_times(client)
        for launch in host_launch:
            epoch = launch.kv.get("epoch", "?")
            if epoch in mine:
                continue
            if client.last_w < launch.w + 14.0 and (client.index in gone or client.end_line() is not None):
                continue
            v.fail("bound", client.name, f"never bound the match the host launched at epoch {epoch}", host.ref(launch))
        if client.index in gone:
            continue
        hubs = len([l for l in client.tagged("SCENE") if "kind=hub" in l.rest])
        host_hubs = len([l for l in host.tagged("SCENE") if "kind=hub" in l.rest])
        if hubs != host_hubs:
            v.fail("bound", client.name, f"stood in the hub {hubs} time(s), the host {host_hubs}")


def events_of(peer: Peer) -> dict[str, list[tuple[tuple, Line]]]:
    by_epoch: dict[str, list] = defaultdict(list)
    for line in peer.tagged("EV"):
        kind = line.rest.split(" ", 1)[0]
        if kind not in EVENT_KINDS or line.kv.get("kind", "match") != "match":
            continue
        key = (kind,) + tuple(line.kv.get(k, "?") for k in EVENT_KINDS[kind])
        by_epoch[line.kv.get("epoch", "?")].append((key, line))
    return by_epoch


def check_events(host: Peer, clients: list[Peer], v: Verdict, slack: float) -> None:
    host_events = events_of(host)
    for client in clients:
        bound = bound_times(client)
        for epoch, mine in events_of(client).items():
            theirs = host_events.get(epoch, [])
            start = bound.get(epoch, client.first_w)
            # The burst a machine replays as it binds may stand in for events it was not there for.
            kept = [(k, l) for k, l in mine if l.w > start + 0.05]
            keys = [k for k, _ in kept]
            host_keys = [k for k, _ in theirs]
            scene_end = next((l.w for l in client.lines if l.tag in ("SCENE", "END", "QUIT") and l.w > start), client.last_w)
            required = {i for i, (_, l) in enumerate(theirs) if start + slack < l.w < scene_end - slack}
            ok = False
            for offset in range(0, len(host_keys) - len(keys) + 1):
                if host_keys[offset:offset + len(keys)] == keys and required <= set(range(offset, offset + len(keys))):
                    ok = True
                    break
            if ok:
                continue
            # Name the first place the two sequences part.
            tail = host_keys[-len(keys):] if keys else []
            where = next((i for i, (a, b) in enumerate(zip(keys, tail)) if a != b), min(len(keys), len(tail)))
            got = kept[where][1] if where < len(kept) else None
            want = [k for i, k in enumerate(host_keys) if i in required]
            v.fail("events", client.name,
                   f"event sequence at epoch {epoch} is not the host's: here {[' '.join(k) for k in keys][:12]}, "
                   f"host {[' '.join(k) for k in host_keys][:12]} (host events it had to see: {len(want)})",
                   client.ref(got) if got else "")
    return


def host_state_timeline(host: Peer) -> list[tuple[float, tuple]]:
    return [(l.w, state_of(l.kv)) for l in host.tagged("STATE")]


def states_in_window(timeline: list[tuple[float, tuple]], lo: float, hi: float) -> set[tuple]:
    found: set[tuple] = set()
    current = None
    for w, state in timeline:
        if w <= lo:
            current = state
        elif w <= hi:
            found.add(state)
        else:
            break
    if current is not None:
        found.add(current)
    return found


def check_state(host: Peer, clients: list[Peer], scenario: dict, v: Verdict, slack: float, quiet) -> None:
    timeline = host_state_timeline(host)
    split_ok = scenario.get("expect", {}).get("scene_split", False)
    for client in clients:
        run: list[tuple[Line, tuple, set]] = []
        reported: set[tuple] = set()
        for line in client.tagged("POS"):
            if line.w > host.last_w - slack:
                break
            mine = state_of(line.kv)
            theirs = states_in_window(timeline, line.w - slack, line.w + slack)
            agree = mine in theirs or not theirs or quiet(line.w)
            if not agree and split_ok and all(mine[0] != t[0] for t in theirs):
                agree = True
            if agree:
                run = []
                continue
            run.append((line, mine, theirs))
            if len(run) == SUSTAIN_SAMPLES and mine not in reported:
                reported.add(mine)
                first = run[0][0]
                v.fail("state", client.name,
                       f"disagrees with the host for {SUSTAIN_SAMPLES} samples: here [{state_text(mine)}], "
                       f"host [{'] or ['.join(state_text(t) for t in sorted(theirs))}]", client.ref(first)[:300])


def check_frozen(peers: list[Peer], v: Verdict) -> None:
    for peer in peers:
        state: tuple = ()
        paused = False
        since: Line | None = None
        reported = False
        for line in peer.lines:
            if line.w > peer.session_end:
                break
            if line.tag == "POS":
                state = state_of(line.kv)
                paused = line.kv.get("paused") == "1"
            if line.tag == "SCENE":
                since = None
                reported = False
            if line.tag != "LOCAL" or not state:
                continue
            live = (state[0] == "match" and state[2] in ("RACE", "ROUND") and state[5] == "IN_PROGRESS" and not paused)
            frozen = (live and line.kv.get("role") in ("RUNNING", "GHOST", "HUNTING") and line.kv.get("sim") == "0"
                      and float(line.kv.get("hold", "0")) <= 0.0)
            if not frozen:
                since = None
                reported = False
                continue
            if since is None:
                since = line
            if not reported and line.w - since.w >= FROZEN_GRACE:
                reported = True
                v.fail("frozen", peer.name,
                       f"own body ({line.kv.get('seat')}, {line.kv.get('role')}) not simulated for {line.w - since.w:.0f} s "
                       f"in a live {state[2]} (settle={line.kv.get('settle')})", peer.ref(since))


def check_positions(host: Peer, clients: list[Peer], scenario: dict, v: Verdict, lag: float, quiet) -> dict:
    host_pos = [(l.w, state_of(l.kv), parse_bodies(l.rest), l) for l in host.tagged("POS")]
    stats = {"samples": 0, "max": 0.0}
    window = POSITION_WINDOW + lag
    tolerance = float(scenario.get("position_tolerance", POSITION_TOLERANCE))
    for client in clients:
        runs: dict[str, list] = defaultdict(list)
        role_runs: dict[str, list] = defaultdict(list)
        reported: set[str] = set()
        hidden_since: Line | None = None
        hidden_reported = False
        cursor = 0
        for line in client.tagged("POS"):
            mine_state = state_of(line.kv)
            while cursor < len(host_pos) and host_pos[cursor][0] < line.w - window:
                cursor += 1
            near = []
            i = cursor
            while i < len(host_pos) and host_pos[i][0] <= line.w + window:
                near.append(host_pos[i])
                i += 1
            near = [h for h in near if h[1][0] == mine_state[0] and h[1][1] == mine_state[1]]
            # A client whose world is still covered draws nothing; that is its own check.
            if line.kv.get("3d") == "0":
                live = any(h[1][2] in ("RACE", "ROUND", "BRAWL", "HUB") for h in near)
                if live and hidden_since is None:
                    hidden_since = line
                if live and hidden_since is not None and not hidden_reported and line.w - hidden_since.w > WORLD_HIDDEN_GRACE:
                    hidden_reported = True
                    v.fail("world-hidden", client.name,
                           f"3D world still covered {line.w - hidden_since.w:.0f} s into a live scene", client.ref(hidden_since)[:300])
                continue
            hidden_since = None
            if len(near) < 2 or quiet(line.w):
                continue
            mine_bodies = parse_bodies(line.rest)
            host_seats = set.intersection(*(set(h[2]) for h in near))
            for seat in host_seats:
                roles = {h[2][seat]["role"] for h in near}
                body = mine_bodies.get(seat)
                problem = ""
                if body is None:
                    problem = "has no body here"
                elif body["role"] not in roles:
                    problem = f"is {body['role']} here and {'/'.join(sorted(roles))} on the host"
                elif not body["vis"] and all(h[2][seat]["vis"] for h in near):
                    problem = "is hidden here and shown on the host"
                key = f"{seat}:{problem.split(' here')[0]}"
                if not problem:
                    for k in [k for k in role_runs if k.startswith(seat + ":")]:
                        role_runs[k] = []
                    continue
                role_runs[key].append(line)
                if len(role_runs[key]) == SUSTAIN_SAMPLES * 2 and key not in reported:
                    reported.add(key)
                    v.fail("body-state", client.name, f"body {seat} {problem}, for {SUSTAIN_SAMPLES}+ s "
                           f"(state {state_text(mine_state)})", client.ref(role_runs[key][0])[:260])
            for seat, body in mine_bodies.items():
                track = [h[2][seat]["pos"] for h in near if seat in h[2]]
                if len(track) < 2 or not body["vis"]:
                    runs[seat] = []
                    continue
                distance = min(seg_distance(body["pos"], track[k], track[k + 1]) for k in range(len(track) - 1))
                stats["samples"] += 1
                stats["max"] = max(stats["max"], distance)
                if distance <= tolerance:
                    runs[seat] = []
                    continue
                runs[seat].append((line, distance))
                if len(runs[seat]) == SUSTAIN_SAMPLES and seat not in reported:
                    reported.add(seat)
                    first, _ = runs[seat][0]
                    worst = max(d for _, d in runs[seat])
                    v.fail("position", client.name,
                           f"body {seat} ({body['role']}) drawn {worst:.1f} m from where the host has it, "
                           f"for {SUSTAIN_SAMPLES}+ samples (state {state_text(mine_state)})", client.ref(first)[:260])
    return stats


def check_world(peers: list[Peer], v: Verdict) -> None:
    """Bodies that left the world, and living bodies that stopped moving (host only)."""
    for peer in peers:
        fell: set[str] = set()
        for line in peer.tagged("POS"):
            for seat, body in parse_bodies(line.rest).items():
                floor = -60.0 if line.kv.get("kind") == "hub" else -200.0
                if body["pos"][1] < floor and seat not in fell:
                    fell.add(seat)
                    v.fail("out-of-world", peer.name, f"body {seat} at y={body['pos'][1]:.0f}", peer.ref(line)[:260])
    host = peers[0]
    still: dict[str, tuple[Line, tuple]] = {}
    warned: set[str] = set()
    for line in host.tagged("POS"):
        live = line.kv.get("kind") == "match" and line.kv.get("phase") in ("RACE", "ROUND") and line.kv.get("outcome") == "IN_PROGRESS"
        bodies = parse_bodies(line.rest) if live else {}
        for seat in list(still):
            if seat not in bodies:
                del still[seat]
        for seat, body in bodies.items():
            if body["role"] != "RUNNING" or not body["sim"]:
                still.pop(seat, None)
                continue
            anchor = still.get(seat)
            if anchor is None or seg_distance(body["pos"], anchor[1], anchor[1]) > STUCK_METRES:
                still[seat] = (line, body["pos"])
                continue
            key = f"{seat}@{anchor[0].no}"
            if line.w - anchor[0].w >= STUCK_SECONDS and key not in warned:
                warned.add(key)
                v.warn("stuck", "host", f"running body {seat} within {STUCK_METRES:.0f} m of one spot for "
                       f"{STUCK_SECONDS:.0f}+ s at ({anchor[1][0]:.1f}, {anchor[1][1]:.1f}, {anchor[1][2]:.1f})", host.ref(anchor[0])[:200])


def check_presentation(host: Peer, clients: list[Peer], v: Verdict, lag: float, quiet) -> None:
    watched = [
        ("POWER", "power", lambda l: l.kv.get("ability", "0"), 0.4),
        ("EMOTE", "emote", lambda l: ("alt" if l.kv.get("alt") == "1" else "on") if l.kv.get("on") == "1" else "0", 0.4),
        ("RAG", "ragdoll", lambda l: l.kv.get("active", "0"), 0.4),
        ("CATS", "cat drawn", lambda l: "1" if l.kv.get("drawn", "0") != "0" else "0", 0.4),
    ]
    slack = SLACK + lag
    for tag, label, value_of, least in watched:
        theirs = intervals(host, tag, value_of)
        for client in clients:
            bound = sorted(bound_times(client).values()) + sorted(bound_times(client, "hub").values())
            mine = intervals(client, tag, value_of)

            def had(side: dict, seat: str, value: str, lo: float, hi: float) -> bool:
                """A stretch of the same value on the other machine that starts and ends when this one does."""
                end_slack = slack * (3.0 if tag == "RAG" else 2.0)
                return any(val == value and abs(start - (lo + slack)) <= slack and abs(end - (hi - slack)) <= end_slack
                           for val, start, end, _ in side.get(seat, []))

            def present(start: float, end: float) -> bool:
                return any(b < start for b in bound) and min(client.last_w, client.session_end) > end + slack

            for seat, spans in theirs.items():
                for value, start, end, line in spans:
                    if value == "0" or end - start < least or not present(start, end) or quiet(start) or quiet(end):
                        continue
                    if end >= host.last_w - 0.1:
                        continue  # cut short by the end of the host's log, not by the game
                    if not had(mine, seat, value, start - slack, end + slack):
                        v.fail("presentation", client.name,
                               f"never drew {label}={value} for {seat} over the stretch the host had it ({end - start:.1f} s)", host.ref(line))
            for seat, spans in mine.items():
                for value, start, end, line in spans:
                    if value == "0" or end - start < 1.5 or start > host.last_w - slack - 1.5 or quiet(start) or quiet(end):
                        continue
                    if end > host.last_w - slack:
                        # Still up when the host's log ends: the host must have it up at the end too, from the same start.
                        if any(val == value and abs(a - start) <= slack and b >= host.last_w - 2.0 * slack
                               for val, a, b, _ in theirs.get(seat, [])):
                            continue
                        v.fail("presentation", client.name,
                               f"drew {label}={value} for {seat} from t+{start - client.first_w:.0f} s to the end, which the host never had",
                               client.ref(line))
                        continue
                    if not had(theirs, seat, value, start - slack, end + slack):
                        v.fail("presentation", client.name,
                               f"drew {label}={value} for {seat} for {end - start:.1f} s, a stretch the host never had", client.ref(line))


def check_presses(host: Peer, peers: list[Peer], v: Verdict, lag: float, quiet, scenario: dict) -> dict:
    stats: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    powers = host.tagged("POWER")
    emotes = host.tagged("EMOTE")
    cats = host.tagged("CATHOST")
    rules = [l for l in host.tagged("MATCH") if l.rest.startswith("rules")]
    window = PRESS_WINDOW + 2.0 * lag
    valid_by_peer: dict[int, int] = defaultdict(int)
    for peer in peers:
        releases = peer.tagged("RELEASE")
        for press in peer.tagged("PRESS"):
            key = press.kv.get("key", "?")
            seat = press.kv.get("seat")
            note = press.kv.get("note", "")
            if press.kv.get("valid") != "1" and not note.startswith(("role-", "no-cat", "no-picked")):
                # The key was held back for a moment the body could use it, and none came.
                v.fail("press", peer.name, f"key {key} could never be used as {seat}: {note} for the whole wait", peer.ref(press))
            if press.kv.get("valid") != "1":
                continue
            valid_by_peer[peer.index] += 1
            if key in ("f", "j") or press.w > host.last_w - window or quiet(press.w):
                continue
            lo, hi = press.w - 0.3, press.w + window
            ok = True
            what = ""
            if key in "12345q":
                ability = key
                if key == "q":
                    current = [l for l in rules if l.w <= press.w]
                    ability = current[-1].kv.get("ability", "0") if current else "0"
                what = f"power {ability} ({ABILITY_NAMES.get(int(ability), '?')})"
                on = next((l for l in powers if l.kv.get("seat") == seat and l.kv.get("ability") == ability and lo <= l.w <= hi), None)
                ok = on is not None
                if ok and key == "3":
                    release = next((r for r in releases if r.kv.get("key") == "3" and r.w >= press.w), None)
                    off = next((l for l in powers if l.kv.get("seat") == seat and l.w > on.w), None)
                    held = (release.w - press.w) if release else 0.0
                    ran = (off.w - on.w) if off else host.last_w - on.w
                    if held >= 1.0 and ran < min(held, 5.0) - 0.6:
                        v.fail("press", peer.name, f"armor lock held {held:.1f} s ran only {ran:.1f} s on the host", host.ref(on))
            elif key in "bn":
                what = "emote" + (" (alt)" if key == "n" else "")
                want_alt = "1" if key == "n" else "0"
                ok = any(l.kv.get("seat") == seat and l.kv.get("on") == "1" and l.kv.get("alt") == want_alt and lo <= l.w <= hi for l in emotes)
            elif key == "e":
                what = "cook the cat"
                ok = any(l.kv.get("seat") == seat and l.kv.get("cooking") == "1" and lo <= l.w <= hi for l in cats)
            stats[key][0] += 1
            if ok:
                stats[key][1] += 1
            else:
                v.fail("press", peer.name, f"pressed {key} ({what}) as {seat} and the host never ran it within {window:.1f} s", peer.ref(press))
    for index, least in scenario.get("expect", {}).get("valid_presses", {}).items():
        if valid_by_peer[int(index)] < int(least):
            v.fail("press", peers[int(index)].name if int(index) < len(peers) else f"peer{index}",
                   f"{valid_by_peer[int(index)]} usable key press(es), {least} expected: the scenario tested nothing here")
    return {k: {"pressed": a, "ran": b} for k, (a, b) in stats.items()}


def check_role_powers(host: Peer, v: Verdict) -> None:
    """A runner power running on the guard or on a ghost: allowed by the code today, unruled (POWERS X4)."""
    role: dict[str, str] = {}
    seen: set[tuple] = set()
    for line in host.lines:
        if line.tag == "ROLE":
            role[line.kv.get("seat", "?")] = line.kv.get("role", "?")
        elif line.tag == "POWER" and line.kv.get("ability", "0") != "0":
            seat = line.kv.get("seat", "?")
            key = (seat, role.get(seat), line.kv.get("ability"))
            if role.get(seat) in ("TOWER", "GHOST", "HUNTING") and key not in seen:
                seen.add(key)
                v.warn("role-power", "host", f"{seat} ran power {line.kv.get('ability')} while {role.get(seat)}", host.ref(line))


def check_roster(host: Peer, v: Verdict) -> None:
    launches = [l for l in host.tagged("LOBBY") if "phase=LAUNCHING" in l.rest]
    seen: set[str] = set()
    for launch in launches:
        rosters = [l for l in host.tagged("ROSTER") if l.w <= launch.w]
        if not rosters:
            continue
        for seat in re.findall(r"seat (\d+): HUMAN  \(peer", rosters[-1].rest):
            if seat not in seen:
                seen.add(seat)
                v.fail("roster", "host", f"human in seat {seat} has no name on the host at launch", host.ref(rosters[-1])[:260])


def check_guard(host: Peer, v: Verdict, scenario: dict) -> dict:
    shots = host.tagged("RIFLE")
    fired = [l for l in shots if l.rest.startswith("fired")]
    hits = [l for l in shots if l.rest.startswith("hit seat=s")]
    rounds = [l for l in host.tagged("EV") if l.rest.startswith("round_started")]
    ends = [l for l in host.lines if l.tag in ("SCENE", "END") or (l.tag == "EV" and l.rest.startswith(("round_resolved", "match_won", "round_started")))]
    for start in rounds:
        end = next((l.w for l in ends if l.w > start.w), host.last_w)
        if end - start.w < SILENT_GUARD_SECONDS:
            continue
        if not any(start.w <= f.w <= end for f in fired):
            message = f"round {start.kv.get('round')} ran {end - start.w:.0f} s under guard {start.kv.get('guard')} with no shot fired"
            if scenario.get("expect", {}).get("guard_fires"):
                v.fail("guard-silent", "host", message, host.ref(start))
            else:
                v.warn("guard-silent", "host", message, host.ref(start))
    return {"shots": len(fired), "hits": len(hits)}


def check_expect(host: Peer, peers: list[Peer], gone: set[int], scenario: dict, v: Verdict) -> None:
    expect = scenario.get("expect", {})
    host_text = [f"{l.tag} {l.rest}" for l in host.lines]
    for pattern in expect.get("host", []):
        if not any(re.search(pattern, t) for t in host_text):
            v.fail("expect", "host", f"expected line never logged: /{pattern}/")
    for pattern in expect.get("all", []):
        for peer in peers:
            if peer.index in gone:
                continue
            if not any(re.search(pattern, f"{l.tag} {l.rest}") for l in peer.lines):
                v.fail("expect", peer.name, f"expected line never logged: /{pattern}/")
    for pattern in expect.get("clients", []):
        for peer in peers[1:]:
            if peer.index in gone:
                continue
            if not any(re.search(pattern, f"{l.tag} {l.rest}") for l in peer.lines):
                v.fail("expect", peer.name, f"expected line never logged: /{pattern}/")
    host_end = next((l.w for l in host.lines if l.tag in ("END", "QUIT")), host.last_w)
    for peer in peers[1:]:
        own_end = next((l.w for l in peer.lines if l.tag in ("END", "QUIT")), float("inf"))
        if peer.index in gone or expect.get("host_lost") or peer.session_end >= min(host_end - 1.0, own_end - 0.05):
            continue
        ended = next(l for l in peer.lines if l.tag == "SESSION")
        v.fail("dropped", peer.name, f"its session ended {host_end - peer.session_end:.0f} s before the host left", peer.ref(ended))
    for pattern in expect.get("never", []):
        for peer in peers:
            hit = next((l for l in peer.lines if l.w < min(peer.session_end, host_end) and re.search(pattern, f"{l.tag} {l.rest}")), None)
            if hit is not None:
                v.fail("expect", peer.name, f"line that must not appear: /{pattern}/", peer.ref(hit))
    if "matches" in expect:
        done = len([t for t in host_text if t.startswith(("FLOW match_done", "EV match_won"))])
        flows = len([t for t in host_text if t.startswith("FLOW match_done")])
        count = flows if flows else done
        if count < int(expect["matches"]):
            v.fail("expect", "host", f"{count} match(es) completed, {expect['matches']} expected")
    if expect.get("natural_win"):
        forced = next((l for l in host.lines if l.tag in ("CEILING", "WIN")), None)
        if forced is not None:
            v.fail("expect", "host", "the match did not end on its own inside the ceiling", host.ref(forced))
    if expect.get("host_lost"):
        for peer in peers[1:]:
            if peer.index in gone:
                continue
            lost = next((l for l in peer.lines if l.tag == "NET" and "host_lost" in l.rest), None)
            ended = next((l for l in peer.lines if l.tag == "SESSION"), None)
            if ended is None:
                v.fail("expect", peer.name, "the host quit and this client's session never ended")
            scenes = [l for l in peer.lines if l.tag == "SCENE" and "kind=none" not in l.rest and (ended is None or l.w < ended.w)]
            in_match = bool(scenes) and "kind=match" in scenes[-1].rest
            if lost is None and in_match and expect.get("host_lost") == "in-match":
                v.fail("expect", peer.name, "the host quit mid-match and NetMatch.host_lost never fired here",
                       peer.ref(ended) if ended else "")
            shown = any(l.tag == "RESULT" and "showing=1" in l.rest and lost is not None and l.w >= lost.w - 0.1 for l in peer.lines)
            if lost is not None and in_match and not shown:
                v.fail("expect", peer.name, "host lost and the result screen never came up to say so", peer.ref(lost))
    for seat in expect.get("seat_to_bot", []):
        if not any(re.search(rf"SEAT seat=s{seat} occupancy=BOT", t) for t in host_text):
            v.fail("expect", "host", f"seat {seat} never turned bot after its peer left")
            continue
        turned = next(l for l in host.lines if l.tag == "SEAT" and f"seat=s{seat} occupancy=BOT" in l.rest)
        track = [parse_bodies(l.rest).get(f"s{seat}") for l in host.tagged("POS") if l.w > turned.w and l.kv.get("phase") in ("RACE", "ROUND")]
        track = [b for b in track if b is not None]
        moved = any(seg_distance(b["pos"], track[0]["pos"], track[0]["pos"]) > 3.0 for b in track[1:]) if track else False
        acted = moved or any(b["role"] == "TOWER" for b in track)
        if len(track) >= 10 and not acted:
            v.fail("expect", "host", f"seat {seat} turned bot and its body never moved again (no brain)", host.ref(turned))
        elif len(track) < 10:
            v.warn("expect", "host", f"seat {seat} turned bot too late to tell whether its body plays on ({len(track)} samples)")


def summarise(host: Peer, peers: list[Peer]) -> dict:
    events = [l.rest.split(" ", 1)[0] for l in host.tagged("EV")]
    won = [l for l in host.tagged("EV") if l.rest.startswith("match_won")]
    forced_at = [l.w for l in host.lines if l.tag in ("WIN", "CEILING")]
    natural = [l for l in won if not any(0.0 <= l.w - f <= 0.3 for f in forced_at)]
    roles_at_win = []
    for line in natural:
        seat = line.kv.get("seat")
        guard = next((l.kv.get("guard") for l in reversed(host.tagged("STATE")) if l.w < line.w), None)
        roles_at_win.append("guard" if seat == guard else "prisoner")
    bounds = sorted(bound_times(host).values())
    durations = []
    for line in natural:
        start = max((b for b in bounds if b <= line.w), default=None)
        if start is not None:
            durations.append(round(line.w - start, 1))
    rules = next((l for l in host.tagged("MATCH") if l.rest.startswith("rules kind=match")), None)
    return {
        "peers": len(peers),
        "maps": [l.kv.get("map") for l in host.tagged("MATCH") if l.rest.startswith("rules kind=match")],
        "prisoners": int(rules.kv.get("prisoners", 0)) if rules else 0,
        "matches_won": len(won),
        "forced_wins": len(forced_at),
        "natural_wins": len(natural),
        "guard_wins": roles_at_win.count("guard"),
        "prisoner_wins": roles_at_win.count("prisoner"),
        "match_seconds": durations,
        "rounds_started": events.count("round_started"),
        "ghosted": events.count("ghosted"),
        "ghost_caught": events.count("ghost_caught"),
        "shoves": events.count("shoved"),
        "finishers": events.count("finisher"),
        "hitches_over_1s": sum(1 for p in peers for l in p.tagged("HITCH") if int(l.kv.get("ms", 0)) >= 1000),
        "wall_seconds": round(host.last_w - host.first_w, 1),
        "engine_warnings": sum(len(p.warnings) for p in peers),
    }


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    strict = "--strict" in sys.argv
    quiet = "--quiet" in sys.argv
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    session = Path(args[0])
    logs = sorted(session.glob("peer*.log"), key=lambda p: int(re.sub(r"\D", "", p.stem)))
    if not logs or not (session / "scenario.json").exists():
        print(f"check_session: {session} has no peer logs or no scenario.json", file=sys.stderr)
        return 2
    scenario = json.loads((session / "scenario.json").read_text())
    peers = [Peer(int(re.sub(r"\D", "", p.stem)), p) for p in logs]
    host, clients = peers[0], peers[1:]
    v = Verdict()
    if len(peers) != int(scenario.get("peers", len(peers))):
        v.fail("exit", "session", f"{len(peers)} peer logs for a scenario of {scenario.get('peers')} peers")
    if not host.lines:
        v.fail("end", "host", "the host logged nothing")

    def arg(name: str, default: float) -> float:
        values = [float(d.get(name, default)) for d in (scenario.get("common", {}), scenario.get("host", {}), scenario.get("client", {}))]
        values += [float(d.get(name, default)) for d in scenario.get("peer", {}).values()]
        return max(values)

    lag = arg("delay-ms", 0.0) / 1000.0 * 2.0 + (0.4 if arg("loss", 0.0) > 0.0 else 0.0)
    slack = SLACK + lag
    stalls: list[tuple[float, float]] = []
    for peer in peers:
        starts = [l.w for l in peer.lines if l.tag == "STALL" and l.rest.startswith("ms=")]
        overs = [l.w for l in peer.lines if l.tag == "STALL" and l.rest.startswith("over")]
        stalls += [(a - 0.5, b + STALL_RECOVERY) for a, b in zip(starts, overs)]

    def in_stall(w: float) -> bool:
        """Inside a deliberate stall or the seconds a machine needs to catch up after one."""
        return any(a <= w <= b for a, b in stalls)

    gone = check_exits(session, peers, scenario, v)
    check_errors(peers, v, strict)
    stats: dict = {}
    if host.lines:
        check_rules(host, clients, v)
        check_bound(host, clients, gone, v)
        check_events(host, clients, v, slack)
        check_state(host, clients, scenario, v, slack, in_stall)
        check_frozen(peers, v)
        stats["position"] = check_positions(host, clients, scenario, v, lag, in_stall)
        check_world(peers, v)
        check_presentation(host, clients, v, lag, in_stall)
        stats["presses"] = check_presses(host, peers, v, lag, in_stall, scenario)
        check_roster(host, v)
        check_role_powers(host, v)
        stats["rifle"] = check_guard(host, v, scenario)
        check_expect(host, peers, gone, scenario, v)
        stats.update(summarise(host, peers))
    verdict = "FAIL" if v.failures else "PASS"
    report = {"name": scenario.get("name", session.name), "verdict": verdict, "failures": v.failures,
              "warnings": v.warnings, "known": v.known, "stats": stats, "session": str(session)}
    (session / "verdict.json").write_text(json.dumps(report, indent=1))
    checks = sorted({f["check"] for f in v.failures})
    print(f"VERDICT {verdict} scenario={report['name']} peers={len(peers)} fails={len(v.failures)} "
          f"warns={len(v.warnings)} known={len(v.known)}" + (f" checks={','.join(checks)}" if checks else ""))
    if not quiet:
        for f in v.failures:
            print(f"  FAIL [{f['check']}] {f['peer']}: {f['message']}")
            if f["ref"]:
                print(f"       {f['ref']}")
        for w in v.warnings:
            print(f"  WARN [{w['check']}] {w['peer']}: {w['message']}")
        for k in v.known:
            print(f"  KNOWN [{k['id']}] {k['peer']}: {k['message']}")
    return 1 if v.failures else 0


if __name__ == "__main__":
    sys.exit(main())
