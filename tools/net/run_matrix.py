#!/usr/bin/env python3
"""Run scenarios through tools/net/run_session.sh, several at once, and print one line each.

    python3 tools/net/run_matrix.py --out <dir> [--filter REGEX] [--tag TAG] [--jobs N] [--repeat N] [--strict] [--recheck]

Writes <dir>/<scenario>[.rN]/ (logs, verdict.json), <dir>/matrix.json and <dir>/matrix.md.
Exit 0 every scenario PASS, 1 any FAIL, 2 nothing ran.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent


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
    with ThreadPoolExecutor(max_workers=max(args.jobs, 1)) as pool:
        reports = list(pool.map(lambda item: run_one(item[0], item[1], args.strict, args.recheck), work))
    counts = {v: sum(1 for r in reports if r["verdict"] == v) for v in ("PASS", "FAIL", "BROKEN")}
    (out / "matrix.json").write_text(json.dumps({"counts": counts, "reports": reports}, indent=1))
    lines = [f"# Net matrix: {counts['PASS']} PASS, {counts['FAIL']} FAIL, {counts['BROKEN']} BROKEN of {len(reports)}", ""]
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
    print(f"MATRIX pass={counts['PASS']} fail={counts['FAIL']} broken={counts['BROKEN']} total={len(reports)} report={out / 'matrix.md'}")
    return 0 if counts["FAIL"] == 0 and counts["BROKEN"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
