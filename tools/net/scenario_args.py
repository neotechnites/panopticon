#!/usr/bin/env python3
"""Expand a scenario file into the shell the launcher evals: runner, limit, one argv per peer, kills.

    python3 tools/net/scenario_args.py tools/net/scenarios/<name>.json <port>
"""

from __future__ import annotations

import json
import shlex
import sys
from pathlib import Path

RUNNERS = {"hub", "match"}


def flag(key: str, value: object) -> str:
    if isinstance(value, bool):
        value = "true" if value else "false"
    return f"--{key}={value}"


def peer_args(scenario: dict, index: int, port: int) -> list[str]:
    merged: dict = {}
    merged.update(scenario.get("common", {}))
    merged.update(scenario.get("host" if index == 0 else "client", {}))
    merged.update(scenario.get("peer", {}).get(str(index), {}))
    merged.setdefault("name", "Host" if index == 0 else f"C{index}")
    merged["role"] = "server" if index == 0 else "client"
    merged["port"] = port
    if index == 0:
        merged.setdefault("humans", int(scenario["peers"]))
    return [flag(k, v) for k, v in merged.items()]


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
    out = [
        f"RUNNER={shlex.quote(scenario['runner'])}",
        f"LIMIT={int(scenario['limit'])}",
        f"NPEERS={int(scenario['peers'])}",
        f"NAME={shlex.quote(scenario['name'])}",
    ]
    for index in range(int(scenario["peers"])):
        quoted = " ".join(shlex.quote(a) for a in peer_args(scenario, index, port))
        out.append(f"PEER_ARGS_{index}=({quoted})")
    kills = []
    for kill in scenario.get("kill", []):
        kills.append(shlex.quote(f"{int(kill['peer'])}|{float(kill.get('after', 0))}|{kill['when']}"))
    out.append(f"KILLS=({' '.join(kills)})")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
