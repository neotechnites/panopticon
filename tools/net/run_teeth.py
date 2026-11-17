#!/usr/bin/env python3
"""Prove the verdict checker fails what it claims to: one clean control, then one deliberate break each.

    python3 tools/net/run_teeth.py --out <dir> [--jobs N] [--filter REGEX]

Every scenario in tools/net/teeth/ names the checks that must fail ("teeth") or must not ("clean").
Exit 0 when the control is clean and every break was caught by its own check, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run(path: Path, out: Path) -> tuple[str, bool, str]:
    scenario = json.loads(path.read_text())
    subprocess.run(["bash", str(HERE / "run_session.sh"), "--scenario", str(path), "--out", str(out)],
                   capture_output=True, text=True)
    verdict = out / "verdict.json"
    if not verdict.exists():
        return scenario["name"], False, "no verdict (launcher failed)"
    failed = {f["check"] for f in json.loads(verdict.read_text())["failures"]}
    missing = [c for c in scenario.get("teeth", []) if c not in failed]
    dirty = [c for c in scenario.get("clean", []) if c in failed]
    ok = not missing and not dirty
    detail = f"failed {sorted(failed) or 'nothing'}"
    if missing:
        detail += f"; NOT CAUGHT: {missing}"
    if dirty:
        detail += f"; control is dirty on: {dirty}"
    return scenario["name"], ok, detail


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--filter", default="", help="only the teeth whose file name matches")
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    paths = [p for p in sorted((HERE / "teeth").glob("*.json")) if re.search(args.filter, p.stem)]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda p: run(p, out / p.stem), paths))
    bad = 0
    for name, ok, detail in results:
        print(f"TEETH {'ok ' if ok else 'BAD'} {name}: {detail}")
        bad += 0 if ok else 1
    print(f"TEETH {len(results) - bad}/{len(results)} as required")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
