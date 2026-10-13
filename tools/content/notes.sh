#!/usr/bin/env bash
# Append one entry to a project's notes ledger; Ryan's notes verbatim on stdin.
#
#   tools/content/notes.sh <project> <tag> <delivered file name> < notes.txt
set -euo pipefail
source "$(dirname "$0")/lib.sh"
USAGE="usage: tools/content/notes.sh <project> <tag> <delivered file name>  (notes on stdin)"
P="${1:?${USAGE}}"; TAG="${2:?${USAGE}}"; FILE="${3:?${USAGE}}"
L="${CONTENT_DIR}/projects/${P}.notes.md"
{ [ -s "${L}" ] && echo; printf '## %s | %s | %s\n' "${TAG}" "${FILE}" "$(date '+%Y-%m-%d %H:%M')"; cat; } >> "${L}"
