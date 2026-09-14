#!/usr/bin/env bash
# Run the PANOPTICON suite headless and print one line of verdict.
#
#   tools/test.sh                # the whole suite
#   tools/test.sh traps          # only test files whose path contains "traps"
#
# Exit code is the runner's: 0 all green, 1 a test failed, 2 the run was broken
# (a file that would not load, a timeout, or an engine error during the run).
# Never opens a window -- headless is the only mode this repo runs on the Mac.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$(command -v godot || true)}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "test.sh: no godot on PATH; set GODOT=/path/to/godot" >&2
  exit 2
fi

# Global class names (class_name) live in .godot/, which is gitignored, so a
# branch that adds one arrives with a cache that does not know it and every
# script referencing the new type fails to parse. One headless editor pass
# rebuilds the cache; it costs ~3 s against a suite that costs over a minute.
"$GODOT" --headless --editor --quit >/dev/null 2>&1

LOG="$(mktemp -t panopticon-tests)"
trap 'rm -f "$LOG"' EXIT

if [ $# -gt 0 ]; then
  "$GODOT" --headless --path . --script res://tools/run_tests.gd -- "--only=$1" >"$LOG" 2>&1
else
  "$GODOT" --headless --path . --script res://tools/run_tests.gd >"$LOG" 2>&1
fi
STATUS=$?

# The runner's own summary is the one line worth keeping; everything else is
# only interesting when something went wrong, so it is printed only then.
SUMMARY="$(grep -E '^(PASS|FAIL)  [0-9]+ tests,' "$LOG" | tail -1)"
if [ -z "$SUMMARY" ]; then
  cat "$LOG"
  echo "BROKEN  the suite produced no summary (exit $STATUS)"
  exit 2
fi

if [ "$STATUS" -ne 0 ]; then
  cat "$LOG"
fi
echo "$SUMMARY  (exit $STATUS)"
exit $STATUS
