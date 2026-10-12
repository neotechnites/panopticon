#!/usr/bin/env bash
# A new version of a short: ## script <newtag> is a copy of the newest table; edit only Ryan's noted rows.
# Unchanged rows hit assemble's segment cache and stay frame-identical.
#
#   tools/content/version.sh <project> <newtag>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
BRIEF=$(brief_path "${1:?usage: tools/content/version.sh <project> <newtag>}")
python3 "${CONTENT_DIR}/versions.py" new "${BRIEF}" "${2:?usage: tools/content/version.sh <project> <newtag>}"
