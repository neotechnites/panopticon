#!/usr/bin/env bash
# One headless multi-peer session: a host and N clients on localhost, each with its own HOME and log,
# under a wall-clock watchdog, then the verdict. Exit 0 PASS, 1 FAIL, 2 could not run.
#
#   tools/net/run_session.sh --scenario tools/net/scenarios/<name>.json [--out DIR] [--strict] [--no-check]
#   tools/net/run_session.sh --runner hub|match --peers N [--limit S] [--out DIR] -- <host args> -- <client args>
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GODOT="${GODOT:-godot}"
SCENARIO=""; OUT=""; CHECK=1; STRICT=""; RUNNER=""; NPEERS=0; LIMIT=180; NAME="adhoc"
HOST_ARGS=(); CLIENT_ARGS=(); KILLS=(); ARMS=(); RELAY_JSON=""; RELAY_PID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --scenario) SCENARIO="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --strict) STRICT="--strict"; shift ;;
    --no-check) CHECK=0; shift ;;
    --runner) RUNNER="$2"; shift 2 ;;
    --peers) NPEERS="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --) shift; side=h
        for a in "$@"; do
          if [ "$a" = "--" ]; then side=c; continue; fi
          if [ $side = h ]; then HOST_ARGS+=("$a"); else CLIENT_ARGS+=("$a"); fi
        done
        break ;;
    *) echo "run_session: unknown option $1" >&2; exit 2 ;;
  esac
done

command -v "$GODOT" >/dev/null 2>&1 || { echo "run_session: no godot binary ($GODOT)" >&2; exit 2; }
PORT="$(python3 -c 'import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')" || exit 2

if [ -n "$SCENARIO" ]; then
  EXPANDED="$(python3 "$HERE/scenario_args.py" "$SCENARIO" "$PORT")" || exit 2
  eval "$EXPANDED"
else
  [ -n "$RUNNER" ] && [ "$NPEERS" -ge 1 ] || { echo "run_session: need --scenario, or --runner and --peers" >&2; exit 2; }
  PEER_ARGS_0=(--role=server --port="$PORT" --humans="$NPEERS" --name=Host ${HOST_ARGS[@]+"${HOST_ARGS[@]}"})
  for ((i = 1; i < NPEERS; i++)); do
    eval "PEER_ARGS_$i=(--role=client --port=$PORT --name=C$i \${CLIENT_ARGS[@]+\"\${CLIENT_ARGS[@]}\"})"
  done
fi

[ -n "$OUT" ] || OUT="${TMPDIR:-/tmp}/panopticon-net/$NAME-$(date +%Y%m%dT%H%M%S)-$$"
mkdir -p "$OUT" || exit 2
rm -f "$OUT/verdict.json" "$OUT"/peer*.log "$OUT"/peer*.wire
: > "$OUT/exit.txt"
if [ -n "$SCENARIO" ]; then cp "$SCENARIO" "$OUT/scenario.json"; else
  printf '{"name": "%s", "runner": "%s", "peers": %d, "limit": %d}\n' "$NAME" "$RUNNER" "$NPEERS" "$LIMIT" > "$OUT/scenario.json"
fi
if [ "$RUNNER" = match ]; then ENTRY=(--script res://tools/net/run_net_match.gd); else ENTRY=(res://tools/net/hub_session_runner.tscn); fi

# A socket-layer scenario puts a datagram relay between every client and the host (tools/net/wire_relay.gd).
if [ -n "$RELAY_JSON" ]; then
  printf '%s\n' "$RELAY_JSON" > "$OUT/wire.json"
  mkdir -p "$OUT/relay/home"
  HOME="$OUT/relay/home" "$GODOT" --headless --path "$ROOT" --script res://tools/net/wire_relay.gd -- \
    --config="$OUT/wire.json" --log="$OUT/relay.log" > "$OUT/relay.out" 2>&1 &
  RELAY_PID=$!
  for _ in $(seq 1 80); do
    grep -q "RELAY ready" "$OUT/relay.log" 2>/dev/null && break
    kill -0 "$RELAY_PID" 2>/dev/null || break
    sleep 0.25
  done
  grep -q "RELAY ready" "$OUT/relay.log" 2>/dev/null || { echo "run_session: the wire relay did not start" >&2; kill -KILL "$RELAY_PID" 2>/dev/null; exit 2; }
fi

PIDS=()
launch() {
  local i="$1"; shift
  mkdir -p "$OUT/peer$i/home"
  HOME="$OUT/peer$i/home" PANOPTICON_NET_ISOLATED=1 \
    "$GODOT" --headless --path "$ROOT" "${ENTRY[@]}" -- "$@" --wire-log="$OUT/peer$i.wire" > "$OUT/peer$i.log" 2>&1 &
  PIDS+=($!)
}

cleanup() {
  for p in ${PIDS[@]+"${PIDS[@]}"} $RELAY_PID; do kill -KILL "$p" 2>/dev/null; done
}
trap cleanup INT TERM

launch 0 "${PEER_ARGS_0[@]}"
# Clients join a host that is listening, not one still loading.
for _ in $(seq 1 120); do
  grep -q "HOST port=.* result=" "$OUT/peer0.log" 2>/dev/null && break
  kill -0 "${PIDS[0]}" 2>/dev/null || break
  sleep 0.25
done
for ((i = 1; i < NPEERS; i++)); do
  eval "launch $i \"\${PEER_ARGS_$i[@]}\""
  # Seats go by arrival: client i is seated before client i+1 starts, so peer N is seat N.
  for _ in $(seq 1 80); do
    grep -q "SEAT seat=s$i occupancy=HUMAN" "$OUT/peer0.log" 2>/dev/null && break
    kill -0 "${PIDS[$i]}" 2>/dev/null || break
    sleep 0.25
  done
done

# Wall-clock limit: macOS has no timeout(1). Kills only the peers this script started.
(
  waited=0
  while [ "$waited" -lt $((LIMIT + 20)) ]; do
    alive=0
    for p in "${PIDS[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
    [ "$alive" = 0 ] && exit 0
    sleep 1; waited=$((waited + 1))
  done
  echo "watchdog killed after=$((LIMIT + 20))" >> "$OUT/exit.txt"
  for p in "${PIDS[@]}"; do kill -TERM "$p" 2>/dev/null; done
  sleep 3
  for p in "${PIDS[@]}"; do kill -KILL "$p" 2>/dev/null; done
) &
WATCHDOG=$!

# Fault arm: hard-kill one peer some seconds after its log first shows a line.
for spec in ${KILLS[@]+"${KILLS[@]}"}; do
  (
    peer="${spec%%|*}"; rest="${spec#*|}"; after="${rest%%|*}"; pattern="${rest#*|}"
    while kill -0 "${PIDS[$peer]}" 2>/dev/null; do
      if grep -q -- "$pattern" "$OUT/peer$peer.log" 2>/dev/null; then
        sleep "$after"
        # Only a peer this arm really killed is excused its exit code.
        kill -KILL "${PIDS[$peer]}" 2>/dev/null && echo "killed peer$peer after=$after when=$pattern" >> "$OUT/exit.txt"
        exit 0
      fi
      sleep 0.25
    done
  ) &
  ARMS+=($!)
done

i=0
for p in "${PIDS[@]}"; do
  wait "$p"; echo "peer$i exit=$?" >> "$OUT/exit.txt"
  i=$((i + 1))
done
kill "$WATCHDOG" ${ARMS[@]+"${ARMS[@]}"} $RELAY_PID 2>/dev/null; wait "$WATCHDOG" ${ARMS[@]+"${ARMS[@]}"} $RELAY_PID 2>/dev/null
echo "out=$OUT"
[ "$CHECK" = 1 ] || exit 0
python3 "$HERE/check_session.py" "$OUT" $STRICT
