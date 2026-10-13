#!/usr/bin/env bash
# A new version of a short: ## script <newtag> is a copy of the table Ryan watched (--from); edit only his noted rows.
# Unchanged rows hit assemble's segment cache and stay frame-identical.
#
#   tools/content/version.sh <project> <newtag> --from <tag>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
USAGE="usage: tools/content/version.sh <project> <newtag> --from <tag Ryan watched>"
BRIEF=$(brief_path "${1:?${USAGE}}")
NEW="${2:?${USAGE}}"
[ "${3:-}" = --from ] && [ -n "${4:-}" ] || die "version.sh refuses: --from <tag> is required (the version Ryan watched and gave notes on)"
NAME=$(basename "${BRIEF}" .md)
LEDGER="${CONTENT_DIR}/projects/${NAME}.notes.md"
[ -f "${LEDGER}" ] || die "no notes recorded for ${NAME}"
NOTES=$(mktemp)
python3 "${CONTENT_DIR}/versions.py" ledger "${LEDGER}" "$4" > "${NOTES}" || { rm -f "${NOTES}"; exit 2; }
python3 "${CONTENT_DIR}/versions.py" new "${BRIEF}" "${NEW}" "$4" "${NOTES}"
rm -f "${NOTES}"
