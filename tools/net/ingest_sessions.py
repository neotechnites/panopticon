#!/usr/bin/env python3
"""Write one `playtests` row per multi-peer session into the pod database.

    python3 tools/net/ingest_sessions.py --build-tag <tag> <matrix dir | session dir> ... [--db PATH] [--dry-run]

A session is a directory holding verdict.json (tools/net/check_session.py writes it); a matrix
directory is read one level down. kind is BOT: scripted peers are not people. The table is read
before it is written and never altered. Win columns count matches that ended on their own.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import sqlite3
import statistics
import sys
from pathlib import Path

DEFAULT_DB = Path(os.environ.get(
    "PANOPTICON_POD_DB", os.path.expanduser("~/Documents/senate/domains/panopticon/data/panopticon.db")))
TABLE = "playtests"
COLUMNS = ("played_on", "kind", "build_tag", "guards", "prisoners", "matches", "guard_wins", "prisoner_wins",
           "seconds_median", "verdict", "footage_path")


def sessions_in(paths: list[Path]) -> list[Path]:
    found: list[Path] = []
    for path in paths:
        if (path / "verdict.json").exists():
            found.append(path)
        else:
            found.extend(sorted(p.parent for p in path.glob("*/verdict.json")))
    return found


def row_for(session: Path, build_tag: str) -> tuple:
    report = json.loads((session / "verdict.json").read_text())
    stats = report.get("stats", {})
    checks = sorted({f["check"] for f in report["failures"]})
    maps = ",".join(m or "?" for m in stats.get("maps", []))
    verdict = f"net harness {report['verdict']}: {stats.get('peers', '?')} peers, maps {maps or 'none'}, " \
              f"{stats.get('rounds_started', 0)} rounds, {stats.get('natural_wins', 0)} won, {stats.get('forced_wins', 0)} forced"
    if report["failures"]:
        first = report["failures"][0]
        verdict += f"; {len(report['failures'])} failure(s) [{', '.join(checks)}]; first: {first['peer']}: {first['message']}"
    seconds = stats.get("match_seconds", [])
    played = datetime.date.fromtimestamp((session / "verdict.json").stat().st_mtime).isoformat()
    return (played, "BOT", f"{build_tag}:net:{session.name}", 1, int(stats.get("prisoners", 0)),
            len(stats.get("maps", [])), int(stats.get("guard_wins", 0)), int(stats.get("prisoner_wins", 0)),
            float(statistics.median(seconds)) if seconds else 0.0, verdict[:600], str(session.resolve()))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--build-tag", required=True)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    sessions = sessions_in(args.paths)
    if not sessions:
        print("ingest_sessions: no verdict.json under the paths given", file=sys.stderr)
        return 2
    rows = [row_for(session, args.build_tag) for session in sessions]
    if args.dry_run:
        for row in rows:
            print(" | ".join(str(v) for v in row))
        print(f"ingest_sessions: {len(rows)} row(s), not written (--dry-run)")
        return 0
    if not args.db.exists():
        print(f"ingest_sessions: no database at {args.db}", file=sys.stderr)
        return 2
    connection = sqlite3.connect(args.db, timeout=30)
    try:
        present = {r[1] for r in connection.execute(f"PRAGMA table_info({TABLE})")}
        missing = [c for c in COLUMNS if c not in present]
        if missing:
            print(f"ingest_sessions: {TABLE} lacks {', '.join(missing)}; nothing written", file=sys.stderr)
            return 2
        with connection:
            connection.executemany(
                f"INSERT INTO {TABLE} ({', '.join(COLUMNS)}) VALUES ({', '.join('?' for _ in COLUMNS)})", rows)
    finally:
        connection.close()
    print(f"ingest_sessions: {len(rows)} row(s) written to {args.db}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
