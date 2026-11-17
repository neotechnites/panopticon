#!/usr/bin/env python3
"""Run scenarios through tools/net/run_session.sh, several at once, and print one line each.

    python3 tools/net/run_matrix.py --out <dir> [--filter REGEX] [--tag TAG] [--jobs N] [--repeat N] [--strict] [--recheck]

Writes <dir>/<scenario>[.rN]/ (logs, verdict.json), <dir>/matrix.json and <dir>/matrix.md. With --repeat N
every scenario is classed over its N runs: PASS (N/N), FLAKY (some) or FAIL (none); the phase gate is
--repeat 3 on the base and on the branch, compared by tools/net/matrix_gate.py.
Exit 0 every scenario PASS, 1 any FAIL or FLAKY, 2 nothing ran.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


def provenance() -> dict:
    """Which code ran: the commit, whether the tree had changes, and how loaded the machine was."""
    def git(*args: str) -> str:
        done = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
        return done.stdout.strip() if done.returncode == 0 else ""
    return {"commit": git("rev-parse", "HEAD"), "dirty": len([l for l in git("status", "--porcelain").splitlines() if l]),
            "load": list(os.getloadavg()), "at": time.strftime("%Y-%m-%dT%H:%M:%S")}


def checker_hash() -> str:
    """Which verdict code judged the logs: a recheck under another checker is not the same result."""
    digest = hashlib.sha256()
    for name in ("check_session.py", "wire_stats.py", "scenario_args.py", "error_allowlist.json"):
        digest.update((HERE / name).read_bytes())
    return digest.hexdigest()[:16]


def ledger_path() -> Path | None:
    """One append-only file per clone, outside every worktree: each matrix attempt is written there."""
    done = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--git-common-dir"], capture_output=True, text=True)
    if done.returncode != 0:
        return None
    common = Path(done.stdout.strip())
    return (common if common.is_absolute() else ROOT / common) / "panopticon-matrix-ledger.jsonl"


def classify(reports: list[dict]) -> dict:
    """One scenario over its runs: PASS only when every run passed, FLAKY when some did, FAIL when none."""
    passes = sum(1 for r in reports if r["verdict"] == "PASS")
    checks: dict[str, int] = {}
    for report in reports:
        for check in {f["check"] for f in report["failures"]}:
            checks[check] = checks.get(check, 0) + 1
    verdict = "PASS" if passes == len(reports) else ("FAIL" if passes == 0 else "FLAKY")
    return {"class": verdict, "passes": passes, "runs": len(reports), "checks": checks,
            "broken": sum(1 for r in reports if r["verdict"] == "BROKEN")}


def run_one(path: Path, out: Path, strict: bool, recheck: bool = False) -> dict:
    started = time.time()
    command = ["bash", str(HERE / "run_session.sh"), "--scenario", str(path), "--out", str(out)]
    if recheck:
        # The logs stand; only the verdict is taken again (after a change to the checker or the allowlist).
        command = [sys.executable, str(HERE / "check_session.py"), str(out)]
    if strict:
        command.append("--strict")
    proc = subprocess.run(command, capture_output=True, text=True)
    (out / "check.txt").write_text(proc.stdout + proc.stderr) if out.exists() else None
    verdict_path = out / "verdict.json"
    if verdict_path.exists():
        report = json.loads(verdict_path.read_text())
    else:
        report = {"name": path.stem, "verdict": "BROKEN", "failures": [
            {"check": "launcher", "peer": "session", "message": (proc.stderr or proc.stdout).strip()[-300:], "ref": ""}],
            "warnings": [], "known": [], "stats": {}, "session": str(out)}
    report["launcher_exit"] = proc.returncode
    report["wall"] = round(time.time() - started, 1)
    checks = sorted({f["check"] for f in report["failures"]})
    print(f"{report['verdict']:6} {out.name:52} {report['wall']:6.0f}s fails={len(report['failures'])} "
          f"warns={len(report['warnings'])} known={len(report['known'])} {','.join(checks)}", flush=True)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True)
    parser.add_argument("--filter", default="")
    parser.add_argument("--tag", default="")
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--recheck", action="store_true", help="re-verdict the sessions already under --out; runs nothing")
    parser.add_argument("--scenarios", default=str(HERE / "scenarios"))
    args = parser.parse_args()
    out = Path(args.out)
    if (out / "matrix.json").exists() and not args.recheck:
        # Runs are never overwritten: a second attempt goes to a new directory and into the ledger.
        print(f"run_matrix: {out} already holds a matrix; use a new --out (or --recheck)", file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    chosen = []
    for path in sorted(Path(args.scenarios).glob("*.json")):
        scenario = json.loads(path.read_text())
        if args.filter and not re.search(args.filter, scenario["name"]):
            continue
        if args.tag and args.tag not in scenario.get("tags", []):
            continue
        chosen.append(path)
    if not chosen:
        print("run_matrix: no scenario matches", file=sys.stderr)
        return 2
    work = []
    for path in chosen:
        for n in range(args.repeat):
            target = out / (path.stem if args.repeat == 1 else f"{path.stem}.r{n + 1}")
            if not args.recheck or (target / "scenario.json").exists():
                work.append((path, target))
    print(f"run_matrix: {len(work)} run(s) of {len(chosen)} scenario(s), {args.jobs} at a time -> {out}", flush=True)
    started = provenance()
    started["checker"] = checker_hash()
    if args.recheck and (out / "matrix.json").exists():
        ran = json.loads((out / "matrix.json").read_text()).get("provenance", started)
        ran["rechecked"] = {"at": started["at"], "checker": started["checker"]}
        started = dict(ran, checker=started["checker"])
    with ThreadPoolExecutor(max_workers=max(args.jobs, 1)) as pool:
        reports = list(pool.map(lambda item: run_one(item[0], item[1], args.strict, args.recheck), work))
    counts = {v: sum(1 for r in reports if r["verdict"] == v) for v in ("PASS", "FAIL", "BROKEN")}
    by_name: dict[str, list[dict]] = {}
    for report in reports:
        by_name.setdefault(report["name"], []).append(report)
    classes = {name: classify(runs) for name, runs in sorted(by_name.items())}
    tally = {c: sum(1 for v in classes.values() if v["class"] == c) for c in ("PASS", "FLAKY", "FAIL")}
    (out / "matrix.json").write_text(json.dumps({
        "counts": counts, "classes": tally, "repeat": args.repeat, "jobs": args.jobs, "strict": args.strict,
        "provenance": started, "finished": provenance(), "scenarios": classes, "reports": reports}, indent=1))
    lines = [f"# Net matrix: {counts['PASS']} PASS, {counts['FAIL']} FAIL, {counts['BROKEN']} BROKEN of {len(reports)}", ""]
    if args.repeat > 1:
        lines += [f"Over {args.repeat} runs each: {tally['PASS']} PASS, {tally['FLAKY']} FLAKY, {tally['FAIL']} FAIL "
                  f"of {len(classes)} scenarios (commit {started['commit'][:10]}, dirty {started['dirty']}).", "",
                  "| scenario | class | passes | failing checks (runs) |", "|---|---|---|---|"]
        for name, c in sorted(classes.items(), key=lambda kv: (kv[1]["class"] == "PASS", kv[0])):
            failing = ", ".join(f"{k} {v}" for k, v in sorted(c["checks"].items()))
            lines.append(f"| {name} | {c['class']} | {c['passes']}/{c['runs']} | {failing} |")
        lines.append("")
    by_check: dict[str, int] = {}
    for report in reports:
        for check in {f["check"] for f in report["failures"]}:
            by_check[check] = by_check.get(check, 0) + 1
    lines.append("Scenarios failing per check: " + ", ".join(f"{k} {v}" for k, v in sorted(by_check.items(), key=lambda kv: -kv[1])))
    lines.append("")
    for report in sorted(reports, key=lambda r: (r["verdict"] == "PASS", r["name"])):
        lines.append(f"## {report['verdict']} {Path(report['session']).name}")
        for failure in report["failures"]:
            lines.append(f"- FAIL [{failure['check']}] {failure['peer']}: {failure['message']}")
            if failure["ref"]:
                lines.append(f"  - `{failure['ref']}`")
        for warning in report["warnings"]:
            lines.append(f"- WARN [{warning['check']}] {warning['peer']}: {warning['message']}")
        lines.append("")
    (out / "matrix.md").write_text("\n".join(lines))
    ledger = ledger_path()
    if ledger is not None:
        with ledger.open("a") as handle:
            handle.write(json.dumps({"out": str(out.resolve()), "commit": started["commit"], "dirty": started["dirty"],
                                     "checker": started["checker"], "recheck": args.recheck, "repeat": args.repeat,
                                     "filter": args.filter, "tag": args.tag, "at": started["at"],
                                     "classes": tally}) + "\n")
    print(f"MATRIX pass={counts['PASS']} fail={counts['FAIL']} broken={counts['BROKEN']} total={len(reports)} "
          f"scenarios pass={tally['PASS']} flaky={tally['FLAKY']} fail={tally['FAIL']} report={out / 'matrix.md'}")
    return 0 if tally["FLAKY"] == 0 and tally["FAIL"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
