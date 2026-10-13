#!/usr/bin/env bash
# Print the complete instructions for a shorts agent; the base comes from the notes ledger.
#
#   tools/content/agent_brief.sh <project> <newtag> [--head-reading FILE]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
USAGE="usage: tools/content/agent_brief.sh <project> <newtag> [--head-reading FILE]"
P="${1:?${USAGE}}"; NEW="${2:?${USAGE}}"; shift 2
HEAD=""
if [ "${1:-}" = "--head-reading" ]; then HEAD="${2:?${USAGE}}"; [ -f "${HEAD}" ] || { echo "no such file: ${HEAD}" >&2; exit 1; }; fi
L="${CONTENT_DIR}/projects/${P}.notes.md"
[ -s "${L}" ] || { echo "notes ledger missing or empty: ${L}" >&2; exit 1; }
N=$(grep -n '^## ' "${L}" | tail -1 | cut -d: -f1) || true
[ -n "${N}" ] || { echo "no ledger entry in ${L}" >&2; exit 1; }
IFS='|' read -r BTAG BFILE _ <<< "$(sed -n "${N}p" "${L}" | sed 's/^## //')"
BTAG=$(echo "${BTAG}" | xargs); BFILE=$(echo "${BFILE}" | xargs)
echo "Rules (binding): ~/Documents/senate/domains/panopticon/data/plan/shorts-common-v2.md"
echo
echo "Project: ${P}"
echo "Brief: tools/content/projects/${P}.md"
echo "Worktree/branch: ~/Documents/olympus/pano-${P}-${NEW} on branch content-${P}-${NEW}"
echo "New tag: ${NEW}"
echo "Base: ${BTAG} (${BFILE}), the last entry in tools/content/projects/${P}.notes.md"
echo
echo "RYAN'S NOTES (verbatim; these are the spec)"
sed -n "${N},\$p" "${L}"
if [ -n "${HEAD}" ]; then
  echo
  echo "HEAD'S READING (subordinate; where it differs from Ryan's words, Ryan's words win)"
  cat "${HEAD}"
fi
echo
echo "Change only what Ryan's notes name. Everything else stays frame-identical to the base. If a note can't be met, stop and report."
