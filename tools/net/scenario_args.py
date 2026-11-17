#!/usr/bin/env python3
"""Expand a scenario file into the shell the launcher evals: runner, limit, one argv per peer, kills.

    python3 tools/net/scenario_args.py tools/net/scenarios/<name>.json <port>
"""

from __future__ import annotations

import json
import shlex
import socket
import sys
from pathlib import Path

RUNNERS = {"hub", "match"}
# The options that change the wire (tools/net/net_conditions.gd) and the ones that freeze a machine.
WIRE_KEYS = ("loss", "delay-ms", "jitter-ms", "burst-ms", "dup", "reorder")
FREEZE_KEYS = ("freeze", "stall-at")


def _positive(value: object) -> bool:
    try:
        return float(value) > 0.0
    except (TypeError, ValueError):
        return bool(value)


def conditioned(opts: dict) -> bool:
    """Whether these options do anything to the wire."""
    return any(_positive(opts.get(k, 0)) for k in WIRE_KEYS)


def watched(scenario: dict) -> bool:
    """Whether any peer's wire is conditioned or any peer freezes: then the wire probe runs."""
    every = [peer_options(scenario, i) for i in range(int(scenario.get("peers", 0)))]
    return any(conditioned(o) or any(_positive(o.get(k, 0)) for k in FREEZE_KEYS) for o in every)


def applied(opts: dict) -> dict:
    """The conditions the relay really applies: --break=wire-off and wire-weak as session_probe.gd does."""
    kind = opts.get("break", "")
    if kind == "wire-off":
        return {}
    if kind == "wire-weak":
        return {k: (float(v) / 3.0 if k in ("loss", "jitter-ms", "dup", "reorder", "burst-ms") else v) for k, v in opts.items()}
    return opts


def socket_layer(scenario: dict) -> bool:
    """Conditions applied to datagrams below ENet by tools/net/wire_relay.gd, not above it by LossyPeer."""
    return any(peer_options(scenario, i).get("wire-layer", "peer") == "socket" for i in range(int(scenario["peers"])))


def flag(key: str, value: object) -> str:
    if isinstance(value, bool):
        value = "true" if value else "false"
    return f"--{key}={value}"


def peer_options(scenario: dict, index: int) -> dict:
    """The options peer [index] runs with: common, then host or client, then its own."""
    merged: dict = {}
    merged.update(scenario.get("common", {}))
    merged.update(scenario.get("host" if index == 0 else "client", {}))
    merged.update(scenario.get("peer", {}).get(str(index), {}))
    return merged


def peer_args(scenario: dict, index: int, port: int) -> list[str]:
    merged = peer_options(scenario, index)
    # The probe only where the wire is the subject: everywhere else it would be traffic the scenario never had.
    merged.setdefault("wire-probe-hz", 20 if watched(scenario) else 0)
    merged.setdefault("name", "Host" if index == 0 else f"C{index}")
    merged["role"] = "server" if index == 0 else "client"
    merged["port"] = port
    if index == 0:
        merged.setdefault("humans", int(scenario["peers"]))
    return [flag(k, v) for k, v in merged.items()]


def free_port() -> int:
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return port


def load(path: Path) -> dict:
    scenario = json.loads(path.read_text())
    for key in ("name", "runner", "peers", "limit"):
        if key not in scenario:
            raise SystemExit(f"{path}: scenario has no '{key}'")
    if scenario["runner"] not in RUNNERS:
        raise SystemExit(f"{path}: runner must be one of {sorted(RUNNERS)}")
    if not 1 <= int(scenario["peers"]) <= 8:
        raise SystemExit(f"{path}: peers must be 1..8")
    return scenario


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    scenario = load(Path(sys.argv[1]))
    port = int(sys.argv[2])
    relay_ports = [free_port() for _ in range(int(scenario["peers"]) - 1)] if socket_layer(scenario) else []
    out = [
        f"RUNNER={shlex.quote(scenario['runner'])}",
        f"LIMIT={int(scenario['limit'])}",
        f"NPEERS={int(scenario['peers'])}",
        f"NAME={shlex.quote(scenario['name'])}",
    ]
    for index in range(int(scenario["peers"])):
        target = relay_ports[index - 1] if relay_ports and index > 0 else port
        quoted = " ".join(shlex.quote(a) for a in peer_args(scenario, index, target))
        out.append(f"PEER_ARGS_{index}=({quoted})")
    relay = ""
    if relay_ports:
        host = peer_options(scenario, 0)
        relay = json.dumps({"host_port": port, "limit": int(scenario["limit"]) + 30, "links": [
            {"port": p, "up": applied(peer_options(scenario, i + 1)), "down": applied(host),
             "up_seed": 11 + 4 * i, "down_seed": 7 + 4 * i}
            for i, p in enumerate(relay_ports)]})
    out.append(f"RELAY_JSON={shlex.quote(relay)}")
    kills = []
    for kill in scenario.get("kill", []):
        kills.append(shlex.quote(f"{int(kill['peer'])}|{float(kill.get('after', 0))}|{kill['when']}"))
    out.append(f"KILLS=({' '.join(kills)})")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
