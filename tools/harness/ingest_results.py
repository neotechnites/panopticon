#!/usr/bin/env python3
"""Write bot-harness results into PANOPTICON's own sqlite database.

    python3 tools/harness/ingest_results.py \
        --build-tag bot-harness-smoke \
        tools/harness/runs/<run id>/sweep.json

One row per sweep ARM, in the existing ``playtests`` table, with ``kind`` fixed
at ``'BOT'``.  The table is read, never altered: if its columns are not the ones
this tool knows how to fill, it refuses rather than migrating somebody else's
schema out from under them.

What lands in each column
-------------------------
``played_on``      the date the matches were recorded, from the result file.
``kind``           always ``BOT``.  A harness row is never a human session.
``build_tag``      ``<tag>:<variant>`` so the arms of one sweep are separable in
                   a table with no variant column.  ``--no-variant-suffix``
                   turns that off.
``guards``         1.  PANOPTICON has exactly one tower.
``prisoners``      ``prisoner_count`` from the rules the arm actually played.
``matches``        every match run, INCLUDING unresolved ones.
``guard_wins``     matches won from the tower.
``prisoner_wins``  matches won by a runner.  Zero under the shipped rules, and
                   read from the files rather than assumed, so it stops being
                   zero on its own the day a runner win condition ships.
``seconds_median`` median SIMULATED duration of the RESOLVED matches.  An
                   unresolved match sits at the tick ceiling by construction and
                   would drag the number towards the ceiling rather than towards
                   the truth.
``verdict``        empty unless ``--verdict`` is passed.  A run that settled
                   nothing must say so; an invented verdict is worse than none,
                   because the next decision would rest on it.
``footage_path``   the result file the row was computed from.

``guard_wins + prisoner_wins`` is deliberately allowed to come out below
``matches``.  The difference is the unresolved matches, and it is meant to be
visible in the row rather than smoothed away.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import statistics
import sys
from pathlib import Path

DEFAULT_DB = Path(
    "/Users/ryanwhitehead/Documents/senate/domains/panopticon/data/panopticon.db"
)

TABLE = "playtests"

# The columns this tool fills, in the order the INSERT names them.  Checked
# against the live table before anything is written.
REQUIRED_COLUMNS = (
    "played_on",
    "kind",
    "build_tag",
    "guards",
    "prisoners",
    "matches",
    "guard_wins",
    "prisoner_wins",
    "seconds_median",
    "verdict",
    "footage_path",
)

MATCH_SCHEMA = "panopticon.bot_match.v1"
SWEEP_SCHEMA = "panopticon.bot_sweep.v1"


class IngestError(RuntimeError):
    pass


# --- Reading the harness's output --------------------------------------------


def load_documents(paths: list[Path]) -> list[dict]:
    """Every JSON file named, plus every file inside a directory named."""
    documents: list[dict] = []
    for path in paths:
        if path.is_dir():
            children = sorted(path.glob("*.json"))
            if not children:
                raise IngestError(f"{path} contains no .json files")
            documents.extend(load_documents(children))
            continue
        if not path.is_file():
            raise IngestError(f"{path} does not exist")
        with path.open() as handle:
            document = json.load(handle)
        document["_source"] = str(path.resolve())
        documents.append(document)
    return documents


def arms_from(documents: list[dict]) -> list[dict]:
    """Fold the documents into one summary per variant.

    A sweep file already carries its arms.  Loose per-match files are grouped by
    their ``variant`` field, so pointing this tool at a run directory and at its
    sweep.json produce the same rows -- except that the sweep file would then be
    counted twice, which is why a directory containing one is read as the sweep
    alone.
    """
    sweeps = [d for d in documents if d.get("schema") == SWEEP_SCHEMA]
    matches = [d for d in documents if d.get("schema") == MATCH_SCHEMA]
    unknown = [d for d in documents if d.get("schema") not in (SWEEP_SCHEMA, MATCH_SCHEMA)]
    if unknown:
        raise IngestError(
            f"{unknown[0].get('_source')} is not a harness result "
            f"(schema {unknown[0].get('schema')!r})"
        )

    arms: list[dict] = []
    for sweep in sweeps:
        recorded = str(sweep.get("recorded_at", ""))[:10]
        for arm in sweep.get("variants", []):
            arms.append(
                {
                    "variant": arm.get("variant", "?"),
                    "played_on": recorded,
                    "prisoners": int(arm.get("rules", {}).get("prisoner_count", 0)),
                    "matches": int(arm.get("matches", 0)),
                    "resolved": int(arm.get("resolved", 0)),
                    "unresolved": int(arm.get("unresolved", 0)),
                    "guard_wins": int(arm.get("tower_wins", 0)),
                    "prisoner_wins": int(arm.get("runner_wins", 0)),
                    "seconds_median": float(arm.get("seconds_median", 0.0)),
                    "source": sweep["_source"],
                }
            )

    if sweeps:
        # A run directory holds both the sweep and the matches it summarises.
        # The sweep is the authority; ingesting both would double every row.
        matches = []

    grouped: dict[str, list[dict]] = {}
    for match in matches:
        grouped.setdefault(str(match.get("variant", "?")), []).append(match)

    for variant, group in grouped.items():
        resolved = [m for m in group if m.get("status") == "RESOLVED"]
        seconds = [float(m["duration"]["simulated_seconds"]) for m in resolved]
        roles = [m.get("outcome", {}).get("winner_role", "") for m in resolved]
        arms.append(
            {
                "variant": variant,
                "played_on": str(group[0].get("recorded_at", ""))[:10],
                "prisoners": int(group[0].get("rules", {}).get("prisoner_count", 0)),
                "matches": len(group),
                "resolved": len(resolved),
                "unresolved": len(group) - len(resolved),
                "guard_wins": sum(1 for r in roles if r == "TOWER"),
                "prisoner_wins": sum(1 for r in roles if r == "RUNNER"),
                "seconds_median": statistics.median(seconds) if seconds else 0.0,
                "source": str(Path(group[0]["_source"]).parent.resolve()),
            }
        )

    if not arms:
        raise IngestError("no harness results found in the paths given")
    return arms


# --- Writing them ------------------------------------------------------------


def check_schema(connection: sqlite3.Connection) -> None:
    """Refuse to write into a table that is not the one documented above."""
    rows = connection.execute(f"PRAGMA table_info({TABLE})").fetchall()
    if not rows:
        raise IngestError(
            f"the database has no {TABLE} table; this tool creates nothing and "
            f"alters nothing"
        )
    present = {row[1] for row in rows}
    missing = [column for column in REQUIRED_COLUMNS if column not in present]
    if missing:
        raise IngestError(
            f"{TABLE} is missing the column(s) {', '.join(missing)}; "
            f"refusing to write rather than migrate a schema this tool does not own"
        )


def insert(connection: sqlite3.Connection, arm: dict, build_tag: str, verdict: str) -> int:
    columns = ", ".join(REQUIRED_COLUMNS)
    placeholders = ", ".join("?" for _ in REQUIRED_COLUMNS)
    cursor = connection.execute(
        f"INSERT INTO {TABLE} ({columns}) VALUES ({placeholders})",
        (
            arm["played_on"],
            "BOT",
            build_tag,
            1,
            arm["prisoners"],
            arm["matches"],
            arm["guard_wins"],
            arm["prisoner_wins"],
            round(arm["seconds_median"], 3),
            verdict,
            arm["source"],
        ),
    )
    return int(cursor.lastrowid)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("results", nargs="+", type=Path,
                        help="sweep.json, match_*.json, or a run directory")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--build-tag", required=True,
                        help="identifies the build these matches were run against")
    parser.add_argument("--verdict", default="",
                        help="what this run SETTLED; leave empty if it settled nothing")
    parser.add_argument("--no-variant-suffix", action="store_true",
                        help="do not append :<variant> to the build tag")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the rows that would be written and stop")
    arguments = parser.parse_args(argv)

    try:
        arms = arms_from(load_documents(arguments.results))
    except IngestError as error:
        print(f"ingest: {error}", file=sys.stderr)
        return 2

    if not arguments.db.exists():
        print(f"ingest: no database at {arguments.db}", file=sys.stderr)
        return 2

    connection = sqlite3.connect(arguments.db)
    connection.row_factory = sqlite3.Row
    try:
        check_schema(connection)
    except IngestError as error:
        print(f"ingest: {error}", file=sys.stderr)
        connection.close()
        return 2

    written: list[int] = []
    for arm in arms:
        tag = arguments.build_tag
        if not arguments.no_variant_suffix:
            tag = f"{tag}:{arm['variant']}"
        if arm["unresolved"]:
            print(
                f"ingest: {arm['variant']}: {arm['unresolved']} of {arm['matches']} "
                f"matches were UNRESOLVED; guard_wins + prisoner_wins will not "
                f"add up to matches, which is the honest picture",
                file=sys.stderr,
            )
        if arguments.dry_run:
            print(f"would write {tag}: {arm}")
            continue
        written.append(insert(connection, arm, tag, arguments.verdict))

    if arguments.dry_run:
        connection.close()
        return 0

    connection.commit()

    # Read every row back out of the database rather than reprinting what was
    # sent to it.  A row that was rejected by a CHECK, or coerced by a column
    # type, must show up here as what it actually became.
    print(f"{len(written)} row(s) written to {arguments.db}")
    marks = ", ".join("?" for _ in written)
    for row in connection.execute(
        f"SELECT * FROM {TABLE} WHERE id IN ({marks}) ORDER BY id", written
    ):
        print("  " + json.dumps(dict(row)))
    connection.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
