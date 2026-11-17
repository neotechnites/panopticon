#!/usr/bin/env bash
# The armor-lock matrix against an exported Windows build on the PC: host + 1, 2 and 3 clients,
# hub -> hell -> marble, clients on key 3 held, tapped, after 2, after 4, in the air, under fire and shoved.
#
#   EXE='C:\...\panopticon.exe' tools/export_check/armor_lock_matrix.sh <headless|windowed> <out dir> [only]
#
# One line per session on stdout: name, each peer's exit code and END line, then what its logs hold.
set -uo pipefail
MODE="${1:?headless|windowed}"; OUT_ROOT="${2:?out dir}"; ONLY="${3:-}"
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
MAPS="${MAPS:-bentham_ring,marble}"
SECONDS_PER_MAP="${SECONDS_PER_MAP:-70}"
LOOPS="${LOOPS:-1}"
LIMIT=$(( (SECONDS_PER_MAP + 45) * LOOPS * 2 + 60 ))

HOLD='3h6;w1;3h2;w0.5;3h0.5;w1'
TAP='3t;w0.4;3t;w0.1;3t;w1.2;3t;w2'
P23='2t;w0.3;3h2;w1.5;2t;w0.1;3t;w5.5;3t;w1'
P43='4t;w0.3;3h2;w1.5;4t;w0.1;3t;w5.5;3t;w1'
AIR='j;w0.15;3h1.5;w1;j;w0.3;3t;w1.5'
MIX='1t;w0.3;3h1;w5;5t;w0.3;3h1;e;w1;s;3t;w2;b;3h1;n;3t;w1'
ALL="$HOLD;$TAP;$P23;$P43;$AIR;$MIX"

COMMON="--zap=true --maps=$MAPS --loops=$LOOPS --match-seconds=$SECONDS_PER_MAP --hub-seconds=8 --limit=$LIMIT"
keys() { echo "--act=keys --program=$1 --phase=${2:-0} $COMMON"; }
AIM="--act=aim $COMMON"

run() {  # name, then the peer groups split by --
  local name="$1"; shift
  [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || return 0
  local out="$OUT_ROOT/$name"
  rm -rf "$out"
  # shellcheck disable=SC2068
  OUT="$out" "$HERE/tools/pc_export_session.sh" "${MODE:0:1}_$name" "$MODE" $((LIMIT + 30)) $@ > "$out.result" 2>&1
  local verdict; verdict="$(tr '\n' ' ' < "$out.result")"
  local held=0 flung=0 errors=0 hits=0 shoves=0 locked_shoves=0
  if ls "$out"/*.log >/dev/null 2>&1; then
    held=$(cat "$out"/c*.log | grep -c 'POWER seat=.* shown=3' || true)
    flung=$(cat "$out"/*.log | grep -c ' FLUNG ' || true)
    hits=$(grep -c 'RIFLE hit=[0-9]* shown=3' "$out/host.log" || true)
    locked_shoves=$(grep -c 'SHOVE try at locked=true' "$out/host.log" || true)
    shoves=$(grep -c 'EV shoved' "$out/host.log" || true)
    errors=$(cat "$out"/*.err "$out"/*.log | grep -c 'SCRIPT ERROR\|CrashHandler\|Program crashed' || true)
  fi
  echo "$name | $verdict| armor_shown=$held shot_while_locked=$hits shoves=$shoves shoved_while_locked=$locked_shoves flung=$flung script_errors=$errors"
}

# Seats: host 0, clients 1.., bots after. --guard is a seat; -1 opens with the race.
run p2_host_guard   --humans=2 --prisoners=3 --guard=0 $AIM -- $(keys "$ALL")
run p2_bot_guard    --humans=2 --prisoners=3 --guard=2 --act=shove $COMMON -- $(keys "$ALL")
run p2_race         --humans=2 --prisoners=3 --guard=-1 --act=shove $COMMON -- $(keys "$ALL")
run p3_host_guard   --humans=3 --prisoners=3 --guard=0 $AIM -- $(keys "$HOLD;$TAP;$AIR") -- $(keys "$P23;$P43;$MIX" 1.3)
run p3_client_guard --humans=3 --prisoners=3 --guard=1 --act=shove $COMMON -- $AIM -- $(keys "$ALL")
run p3_bot_guard    --humans=3 --prisoners=3 --guard=3 --act=shove $COMMON -- $(keys "$ALL") -- $(keys "$ALL" 2.1)
run p4_host_guard   --humans=4 --prisoners=3 --guard=0 $AIM -- $(keys "$HOLD;$AIR") -- $(keys "$TAP;$P23" 0.7) -- $(keys "$P43;$MIX" 1.9)
run p4_client_guard --humans=4 --prisoners=3 --guard=1 --act=shove $COMMON -- $AIM -- $(keys "$ALL") -- $(keys "$ALL" 3.3)
run p4_bot_guard    --humans=4 --prisoners=4 --guard=4 --act=shove $COMMON -- $(keys "$HOLD;$TAP;$AIR") -- $(keys "$P23;$P43" 1.1) -- $(keys "$MIX;$ALL" 2.3)
