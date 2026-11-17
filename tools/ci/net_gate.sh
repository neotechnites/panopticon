#!/usr/bin/env bash
# The multi-peer gate: the scenarios tagged "smoke" (the whole hub -> hell -> hub -> marble -> hub
# flow at 2 peers, and every power key at 3). Exit 0 all PASS, 1 any FAIL. Full matrix: run_matrix.py.
#
#   bash tools/ci/net_gate.sh [out dir]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-${TMPDIR:-/tmp}/panopticon-net/gate-$(date +%Y%m%dT%H%M%S)}"
exec python3 "$ROOT/tools/net/run_matrix.py" --out "$OUT" --tag smoke --jobs 2
