#!/usr/bin/env python3
"""The phase gate over two matrix runs: the phase's base and the branch, each run_matrix.py --repeat 3.

    python3 tools/net/matrix_gate.py --base <dir> --branch <dir> [--base-commit SHA] [--branch-commit SHA]
        [--expect-fixed NAME,...] [--known-fail NAME,...] [--out FILE]

A scenario is PASS only at 3/3. The gate holds when:
- no scenario PASS on the base fails any branch run (a regression);
- every scenario the base ran, the branch ran;
- every --expect-fixed scenario is PASS on the branch;
- every scenario only the branch has is PASS, or named in --known-fail (a baseline failure, stated);
- both runs come from clean trees, at the commits given, and each is the first complete attempt at its
  commit in the clone's matrix ledger (an attempt can be rechecked, never rerun to green).
Scenarios FLAKY on the base are listed and not gated: each needs its own cause found.
Exit 0 when the gate holds, 1 when it does not, 2 when the inputs cannot be judged.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from run_matrix import ledger_path  # noqa: E402

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


def provenance_problems(label: str, directory: str, matrix: dict, commit: str) -> list[str]:
    """What makes this run not the honest first attempt at the code it claims to be."""
    problems = []
    ran = matrix.get("provenance", {})
    if int(ran.get("dirty", 1)) != 0:
        problems.append(f"{label} ran on a tree with {ran.get('dirty')} uncommitted change(s)")
    if commit and not str(ran.get("commit", "")).startswith(commit):
        problems.append(f"{label} ran at {str(ran.get('commit', '?'))[:10]}, not {commit[:10]}")
    ledger = ledger_path()
    if ledger is None or not ledger.exists():
        return problems + [f"no matrix ledger to show {label} is the first attempt"]
    attempts = [json.loads(line) for line in ledger.read_text().splitlines() if line.strip()]
    complete = [a for a in attempts if a["commit"] == ran.get("commit") and not a["recheck"]
                and int(a["repeat"]) >= REPEAT and not a["filter"] and not a["tag"] and int(a["dirty"]) == 0]
    if complete and complete[0]["out"] != str(Path(directory).resolve()):
        problems.append(f"{label} is not the first full attempt at {str(ran.get('commit'))[:10]}: "
                        f"that was {complete[0]['out']} ({complete[0]['classes']})")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--base-commit", default="")
    parser.add_argument("--branch-commit", default="")
    parser.add_argument("--expect-fixed", default="")
    parser.add_argument("--known-fail", default="")
    parser.add_argument("--out", default="")
    args = parser.parse_args()
    try:
        base, branch = load(args.base), load(args.branch)
    except SystemExit as stop:
        print(stop, file=sys.stderr)
        return 2
    b_cls, n_cls = base["scenarios"], branch["scenarios"]
    expected = [n for n in args.expect_fixed.split(",") if n]
    known = {n for n in args.known_fail.split(",") if n}
    regressions = sorted(n for n, c in b_cls.items() if c["class"] == "PASS" and n in n_cls and n_cls[n]["class"] != "PASS")
    missing = sorted(n for n in b_cls if n not in n_cls)
    unfixed = sorted(n for n in expected if n_cls.get(n, {}).get("class") != "PASS")
    new = sorted(n for n in n_cls if n not in b_cls)
    new_failing = sorted(n for n in new if n_cls[n]["class"] != "PASS" and n not in known)
    flaky = sorted(n for n, c in b_cls.items() if c["class"] == "FLAKY")
    worse = sorted(n for n in flaky if n in n_cls and n_cls[n]["passes"] < b_cls[n]["passes"])
    fixed = sorted(n for n, c in b_cls.items() if c["class"] != "PASS" and n_cls.get(n, {}).get("class") == "PASS")
    problems = provenance_problems("base", args.base, base, args.base_commit) + \
        provenance_problems("branch", args.branch, branch, args.branch_commit)
    ok = not regressions and not missing and not unfixed and not new_failing and not problems

    def tally(cls: dict, name: str) -> str:
        c = cls.get(name)
        return f"{c['class']} {c['passes']}/{c['runs']}" if c else "absent"

    lines = [f"# Matrix gate: {'HOLDS' if ok else 'BROKEN'}", "",
             f"Base {base['provenance'].get('commit', '?')[:10]}: {base['classes']}. "
             f"Branch {branch['provenance'].get('commit', '?')[:10]}: {branch['classes']}.", ""]
    lines.append(f"## Provenance problems: {len(problems)}")
    lines += [f"- {p}" for p in problems]
    lines.append("")
    for title, names in (("Regressions (base PASS 3/3, branch not)", regressions),
                         ("Missing on the branch", missing),
                         ("Expected fixes not at 3/3", unfixed),
                         ("New on the branch and not PASS (not on --known-fail)", new_failing),
                         ("Fixed (base not PASS, branch PASS)", fixed),
                         ("Flaky on the base (not gated; each needs its cause found)", flaky),
                         ("Flaky on the base and worse on the branch", worse),
                         ("New on the branch", new)):
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
