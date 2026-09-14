#!/usr/bin/env bash
# Run the PANOPTICON gate headless and print one line of verdict.
#
#   tools/test.sh                # class cache, unit suite, hot-path and i18n audits
#   tools/test.sh traps          # only test files whose path contains "traps"
#
# Four things run, in this order: a class-cache pass, the unit suite (which
# contains the perf and bandwidth budgets in tests/test_budgets.gd), the
# hot-path audit and the i18n audit. Everything runs even after something fails,
# so one run reports every problem rather than the first one.
#
# Exit code: 0 all green, 1 a test failed or an audit found a hit,
# 2 the run was broken (a file that would not load, a timeout, or an engine
# error during the run). Never opens a window -- headless is the only mode this
# repo runs on the Mac.
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
AUDIT_LOG="$(mktemp -t panopticon-hotpaths)"
I18N_LOG="$(mktemp -t panopticon-i18n)"
trap 'rm -f "$LOG" "$AUDIT_LOG" "$I18N_LOG"' EXIT

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

# The budgets print what they measured on every run, pass or fail. That is the
# whole point of having them: a number drifting towards its gate is visible
# weeks before it trips, which a green tick alone would never show.
grep -E 'BUDGET ' "$LOG" | sed -E 's/^ +/  /'

"$GODOT" --headless --path . --script res://tools/audit_hotpaths.gd >"$AUDIT_LOG" 2>&1
AUDIT_STATUS=$?
AUDIT="$(grep -E '^(CLEAN|DIRTY)  ' "$AUDIT_LOG" | tail -1)"
if [ "$AUDIT_STATUS" -ne 0 ] || [ -z "$AUDIT" ]; then
  cat "$AUDIT_LOG"
fi
if [ -z "$AUDIT" ]; then
  AUDIT="BROKEN  the hot-path audit produced no summary (exit $AUDIT_STATUS)"
  AUDIT_STATUS=2
fi

"$GODOT" --headless --path . --script res://tools/audit_i18n.gd >"$I18N_LOG" 2>&1
I18N_STATUS=$?
I18N="$(grep -E '^(CLEAN|DIRTY)  ' "$I18N_LOG" | tail -1)"
if [ "$I18N_STATUS" -ne 0 ] || [ -z "$I18N" ]; then
  cat "$I18N_LOG"
fi
if [ -z "$I18N" ]; then
  I18N="BROKEN  the i18n audit produced no summary (exit $I18N_STATUS)"
  I18N_STATUS=2
fi

echo "$SUMMARY  |  hot paths: $AUDIT  |  i18n: $I18N  (exit $STATUS/$AUDIT_STATUS/$I18N_STATUS)"
[ "$STATUS" -ne 0 ] && exit "$STATUS"
[ "$AUDIT_STATUS" -ne 0 ] && exit "$AUDIT_STATUS"
exit "$I18N_STATUS"
