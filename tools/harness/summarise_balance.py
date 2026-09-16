#!/usr/bin/env python3
"""Summarise bot-harness sweep runs as one markdown table.

    python3 tools/harness/summarise_balance.py RUNDIR [RUNDIR ...]

Each RUNDIR is a harness run directory: a ``sweep.json`` naming the arms, and
the ``match_<variant>_NN.json`` files those arms produced.  One row per arm, in
the order the sweep lists them, runs in the order given on the command line.

Where each column comes from
----------------------------
Most of it is already summed in ``sweep.json`` and is read from there rather
than recomputed, so this tool and the harness can never disagree:
``matches``, ``resolved``, ``rounds_median``, ``seconds_median``, ``hit_rate``,
``runner_round_win_rate`` and the ``guard_by_state`` buckets.

Four columns are NOT in ``sweep.json`` and are aggregated here from the arm's
per-match files, all on one pass over them:

``guard blind %``     ``stall.guard_blind_fraction`` meaned over the arm's
                      matches.  It is already a fraction of one match's round
                      time, so the matches average evenly.
``first shot (s)``    every entry of every match's top-level
                      ``first_shot_seconds``, pooled and meaned -- one number
                      per round, so pooling weights every round equally where
                      averaging each match's own mean would weight a one-round
                      match like a twelve-round one.  ``-`` when the arm fired
                      in no round at all.
``hazard deaths``     ``hazard_deaths`` summed over the arm's matches.
``clean-run rate %``  ``clean_runs.clean`` and ``clean_runs.lives`` summed over
                      the arm, then divided.  Summing the two counts and taking
                      one ratio weights every life equally; averaging each
                      match's own ``clean_rate`` would weight a three-life match
                      the same as a fifty-life one.

A match file is assigned to an arm by its own ``variant`` field, never by
slicing its filename, because one variant name can be a prefix of another.

The ``guard hit%`` columns show ``hits/shots (pct%)``, and ``-`` when the guard
never fired at a target in that state: an unfired rifle has no hit rate, and
printing ``0.0%`` there would read as a miss that never happened.

After the table, one line per arm gives the hazard deaths by cause, summed from
each match's ``guard.deaths_by_cause`` and ``guard.race_deaths_by_cause`` with
``SHOT`` left out -- a shot is the rifle working, not a hazard.

A RUNDIR with no ``sweep.json`` is an unfinished run, not a broken tool: it is
named on stderr and skipped, so a wildcard over a runs folder still summarises
the runs that did finish.  Exit status is 0 when every RUNDIR was read, 1 when
one was skipped, and 2 when nothing could be summarised at all.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

SCHEMA_SWEEP = "panopticon.bot_sweep.v1"
SCHEMA_MATCH = "panopticon.bot_match.v1"

# The by_state buckets, in the order the table shows them.
STATES = ("running", "strafing", "airborne", "cover")

HEADERS = (
    "variant",
    "matches",
    "resolved %",
    "rounds/match (median)",
    "median match length (s)",
    "guard blind %",
    "first shot (s)",
    "hazard deaths",
    "clean-run rate %",
    "guard hit rate %",
    "runner round win %",
    "guard hit% running",
    "strafing",
    "airborne",
    "cover",
)

DASH = "-"


def die(message: str) -> None:
    sys.stderr.write("summarise_balance: %s\n" % message)
    raise SystemExit(2)


def load_json(path: Path) -> dict:
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as exc:
        die("cannot read %s: %s" % (path, exc))
    if not isinstance(data, dict):
        die("%s is not a JSON object" % path)
    return data


def one_decimal(value: float) -> str:
    return "%.1f" % value


def mean(values: list) -> float:
    return sum(values) / len(values)


def rate(numerator: float, denominator: float) -> str:
    """A percentage to one decimal, or ``-`` when nothing was counted."""
    if denominator <= 0:
        return DASH
    return one_decimal(100.0 * numerator / denominator)


def by_state_cell(bucket: dict) -> str:
    shots = int(bucket.get("shots", 0) or 0)
    hits = int(bucket.get("hits", 0) or 0)
    if shots == 0:
        return DASH
    return "%d/%d (%s%%)" % (hits, shots, rate(hits, shots))


def new_tally() -> dict:
    return {
        "hazard_deaths": 0,
        "clean": 0,
        "lives": 0,
        "blind": [],
        "first_shot": [],
        "causes": {},
        "files": 0,
    }


def match_files(run_dir: Path) -> list[Path]:
    return sorted(run_dir.glob("match_*.json"))


def collect_matches(run_dir: Path) -> dict:
    """Per-arm totals of the fields sweep.json does not carry."""
    totals: dict[str, dict] = {}
    for path in match_files(run_dir):
        match = load_json(path)
        schema = match.get("schema", "")
        if schema != SCHEMA_MATCH:
            die("%s has schema %r, expected %r" % (path, schema, SCHEMA_MATCH))
        variant = match.get("variant", "")
        arm = totals.setdefault(variant, new_tally())
        arm["files"] += 1
        arm["hazard_deaths"] += int(match.get("hazard_deaths", 0) or 0)
        stall = match.get("stall") or {}
        if "guard_blind_fraction" in stall:
            arm["blind"].append(float(stall["guard_blind_fraction"] or 0.0))
        arm["first_shot"].extend(
            float(seconds) for seconds in (match.get("first_shot_seconds") or [])
        )
        clean_runs = match.get("clean_runs") or {}
        arm["clean"] += int(clean_runs.get("clean", 0) or 0)
        arm["lives"] += int(clean_runs.get("lives", 0) or 0)
        guard = match.get("guard") or {}
        for field in ("deaths_by_cause", "race_deaths_by_cause"):
            for cause, count in (guard.get(field) or {}).items():
                if cause == "SHOT":
                    continue
                arm["causes"][cause] = arm["causes"].get(cause, 0) + int(count or 0)
    return totals


def row_for(arm: dict, tallied: dict) -> list[str]:
    matches = int(arm.get("matches", 0) or 0)
    resolved = int(arm.get("resolved", 0) or 0)
    states = arm.get("guard_by_state") or {}
    row = [
        str(arm.get("variant", "")),
        str(matches),
        rate(resolved, matches),
        one_decimal(float(arm.get("rounds_median", 0.0) or 0.0)),
        one_decimal(float(arm.get("seconds_median", 0.0) or 0.0)),
        rate(mean(tallied["blind"]), 1.0) if tallied["blind"] else DASH,
        "%.2f" % mean(tallied["first_shot"]) if tallied["first_shot"] else DASH,
        str(tallied["hazard_deaths"]),
        rate(tallied["clean"], tallied["lives"]),
        rate(float(arm.get("hit_rate", 0.0) or 0.0), 1.0),
        rate(float(arm.get("runner_round_win_rate", 0.0) or 0.0), 1.0),
    ]
    row.extend(by_state_cell(states.get(state) or {}) for state in STATES)
    return row


def render(rows: list[list[str]]) -> str:
    widths = [len(header) for header in HEADERS]
    for row in rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))

    def line(cells) -> str:
        padded = (cell.ljust(widths[index]) for index, cell in enumerate(cells))
        return "| %s |" % " | ".join(padded)

    out = [line(HEADERS), "| %s |" % " | ".join("-" * width for width in widths)]
    out.extend(line(row) for row in rows)
    return "\n".join(out)


def main(argv: list[str]) -> int:
    run_dirs = argv[1:]
    if not run_dirs:
        sys.stderr.write(__doc__.strip().splitlines()[2].strip() + "\n")
        return 2

    rows: list[list[str]] = []
    cause_lines: list[str] = []
    skipped = 0
    empty = new_tally()

    for name in run_dirs:
        run_dir = Path(name)
        if not run_dir.is_dir():
            die("%s is not a directory" % run_dir)
        sweep_path = run_dir / "sweep.json"
        if not sweep_path.is_file():
            sys.stderr.write(
                "summarise_balance: skipping %s: no sweep.json (unfinished run)\n"
                % run_dir
            )
            skipped += 1
            continue
        sweep = load_json(sweep_path)
        schema = sweep.get("schema", "")
        if schema != SCHEMA_SWEEP:
            die("%s has schema %r, expected %r" % (sweep_path, schema, SCHEMA_SWEEP))
        tallies = collect_matches(run_dir)
        for arm in sweep.get("variants") or []:
            variant = str(arm.get("variant", ""))
            tallied = tallies.get(variant, empty)
            rows.append(row_for(arm, tallied))
            causes = tallied["causes"]
            rendered = ", ".join(
                "%s: %d" % (cause, causes[cause]) for cause in sorted(causes)
            )
            cause_lines.append(
                "%s: hazard deaths by cause {%s}" % (variant, rendered)
            )

    if not rows:
        die("no sweep arms found in %d director%s"
            % (len(run_dirs), "y" if len(run_dirs) == 1 else "ies"))

    print(render(rows))
    print()
    for cause_line in cause_lines:
        print(cause_line)
    return 1 if skipped else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
