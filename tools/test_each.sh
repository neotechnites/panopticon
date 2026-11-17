#!/usr/bin/env bash
# Run every test file in its own process and print the ones that do not pass alone.
#
#   tools/test_each.sh           # every tests/test_*.gd, one Godot per file
#   tools/test_each.sh hub       # only files whose path contains "hub"
#
# The gate (tools/test.sh) runs the files in one process, in name order, so a test that
# leans on something an earlier file left behind passes there and fails here. Exit 0 when
# every file passes alone, 1 otherwise. Headless only; each run gets its own user://.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$(command -v godot || true)}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "test_each.sh: no godot on PATH; set GODOT=/path/to/godot" >&2
  exit 2
fi

LOG="$(mktemp -t panopticon-each)"
trap 'rm -f "$LOG"' EXIT

FILES=0
BAD=0
for FILE in tests/test_*.gd; do
  if [ $# -gt 0 ] && [[ "$FILE" != *"$1"* ]]; then
    continue
  fi
  FILES=$((FILES + 1))
  "$GODOT" --headless --path . --script res://tools/run_tests.gd -- "--only=$FILE" >"$LOG" 2>&1
  STATUS=$?
  if [ "$STATUS" -ne 0 ]; then
    BAD=$((BAD + 1))
    SUMMARY="$(grep -E '^(PASS|FAIL)  [0-9]+ tests,' "$LOG" | tail -1)"
    echo "ALONE  $FILE  exit $STATUS  ${SUMMARY:-no summary}"
    grep -E '^  FAIL  ' "$LOG" | sed -E 's/^ +/    /'
    # Only the errors that failed the run: the shutdown accounting above them is not a verdict.
    awk '/engine error line\(s\) during the run/{on=1; next} on && /^    /' "$LOG" | sort | uniq -c | sed -E 's/^ +/    /'
  fi
done

echo "EACH  $FILES files, $BAD failed alone"
[ "$BAD" -eq 0 ]
