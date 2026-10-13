#!/usr/bin/env bash
# Put this branch on a PC scratch checkout and import it: PC_PROJECT (C:\dev\verify, or a short's
# own C:\dev\worktrees\content_<project> via lib.sh pc_use_project, made here on first use).
# Never touches C:\dev\panopticon's checkout. Takes no PC lock: only capture and assemble do.
#
#   tools/content/sync.sh [branch]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
BRANCH="${1:-$(git -C "${REPO_DIR}" branch --show-current)}"
TREE=$(ff "${PC_PROJECT}")
T0=$(now_ms)
git -C "${REPO_DIR}" push -q pc "${BRANCH}:refs/heads/${PC_INCOMING}" -f
pc <<PS
\$ErrorActionPreference = 'Stop'
if (-not (Test-Path '${TREE}/.git')) {
  New-Item -ItemType Directory -Force -Path (Split-Path '${PC_PROJECT}') | Out-Null
  git -C C:/dev/verify worktree add -q -f --detach '${TREE}' ${PC_INCOMING}
  Write-Output 'new checkout ${PC_PROJECT}'
}
\$m = git -C ${TREE} status --porcelain | Where-Object { \$_ -notmatch '^\?\?' }
if (\$m) { Write-Output 'scratch checkout has tracked edits; stashing them'; git -C ${TREE} stash -q }
# Scratch checkout: untracked generated files (.uid/.import/extracted png) may block a checkout.
git -C ${TREE} clean -fq
git -C ${TREE} checkout -q -B ${PC_BRANCH} ${PC_INCOMING}
$(pc_import_ps)
\$e = (Select-String -Path '${PC_PROJECT}.import.txt' -Pattern 'ERROR' | Measure-Object -Line).Lines
Write-Output ('${PC_PROJECT} at ' + (git -C ${TREE} log --oneline -1) + ' | import errors: ' + \$e)
PS
echo "sync: $(since "$T0")"
