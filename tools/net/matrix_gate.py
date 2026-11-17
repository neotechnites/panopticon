#!/usr/bin/env python3
"""The phase gate over two matrix runs: the phase's base and the branch, each run_matrix.py --repeat 3.

    python3 tools/net/matrix_gate.py --base <dir> --branch <dir> [--expect-fixed NAME,...] [--out FILE]

A scenario is PASS only at 3/3. A regression is a scenario PASS on the base that fails any branch run.
Scenarios FLAKY on the base are listed and not gated: each needs its own cause found, never a rerun.
--expect-fixed names the scenarios the branch claims to fix: each must be PASS on the branch.
A scenario the base ran and the branch did not is a failure; one only the branch has is listed as new.
Exit 0 when the gate holds, 1 when it does not, 2 when the inputs cannot be judged.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPEAT = 3


def load(directory: str) -> dict:
    path = Path(directory) / "matrix.json"
    if not path.exists():
        raise SystemExit(f"matrix_gate: {path} does not exist")
    matrix = json.loads(path.read_text())
    if int(matrix.get("repeat", 1)) < REPEAT or "scenarios" not in matrix:
        raise SystemExit(f"matrix_gate: {path} is not a --repeat {REPEAT} run (repeat={matrix.get('repeat', 1)})")
    short = [n for n, c in matrix["scenarios"].items() if c["runs"] != int(matrix["repeat"])]
    if short:
        raise SystemExit(f"matrix_gate: {path} has scenarios with a different number of runs: {short[:5]}")
    return matrix


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--expect-fixed", default="")
    parser.add_argument("--out", default="")
    args = parser.parse_args()
    try:
        base, branch = load(args.base), load(args.branch)
    except SystemExit as stop:
        print(stop, file=sys.stderr)
        return 2
    b_cls, n_cls = base["scenarios"], branch["scenarios"]
    expected = [n for n in args.expect_fixed.split(",") if n]
    regressions = sorted(n for n, c in b_cls.items() if c["class"] == "PASS" and n in n_cls and n_cls[n]["class"] != "PASS")
    missing = sorted(n for n in b_cls if n not in n_cls)
    unfixed = sorted(n for n in expected if n_cls.get(n, {}).get("class") != "PASS")
    flaky = sorted(n for n, c in b_cls.items() if c["class"] == "FLAKY")
    fixed = sorted(n for n, c in b_cls.items() if c["class"] != "PASS" and n_cls.get(n, {}).get("class") == "PASS")
    new = sorted(n for n in n_cls if n not in b_cls)
    ok = not regressions and not missing and not unfixed

    def tally(cls: dict, name: str) -> str:
        c = cls.get(name)
        return f"{c['class']} {c['passes']}/{c['runs']}" if c else "absent"

    lines = [f"# Matrix gate: {'HOLDS' if ok else 'BROKEN'}", "",
             f"Base {base['provenance'].get('commit', '?')[:10]} (dirty {base['provenance'].get('dirty', '?')}): "
             f"{base['classes']}. Branch {branch['provenance'].get('commit', '?')[:10]} "
             f"(dirty {branch['provenance'].get('dirty', '?')}): {branch['classes']}.", ""]
    for title, names in (("Regressions (base PASS 3/3, branch not)", regressions),
                         ("Missing on the branch", missing),
                         ("Expected fixes not at 3/3", unfixed),
                         ("Fixed (base not PASS, branch PASS)", fixed),
                         ("Flaky on the base (not gated; each needs its cause found)", flaky),
                         ("New on the branch (no base)", new)):
        lines.append(f"## {title}: {len(names)}")
        lines += [f"- {n}: base {tally(b_cls, n)}, branch {tally(n_cls, n)}" for n in names]
        lines.append("")
    report = "\n".join(lines)
    print(report)
    if args.out:
        Path(args.out).write_text(report + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
