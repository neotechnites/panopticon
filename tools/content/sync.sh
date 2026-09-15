#!/usr/bin/env bash
# Put this branch on the PC's scratch worktree (C:\dev\verify) and import it.
# Never touches C:\dev\panopticon.
#
#   tools/content/sync.sh [branch]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
BRANCH="${1:-$(git -C "${REPO_DIR}" branch --show-current)}"
T0=$(now_ms)
git -C "${REPO_DIR}" push -q pc "${BRANCH}:refs/heads/content-incoming" -f
pc <<PS
\$ErrorActionPreference = 'Stop'
\$m = git -C C:/dev/verify status --porcelain | Where-Object { \$_ -notmatch '^\?\?' }
if (\$m) { Write-Output 'verify worktree has tracked edits; stashing them'; git -C C:/dev/verify stash -q }
# Scratch worktree: untracked generated files (.uid/.import/extracted png) may block a checkout.
git -C C:/dev/verify clean -fq
git -C C:/dev/verify checkout -q -B ${PC_BRANCH} content-incoming
cmd /c "${PC_GODOT} --headless --import --path ${PC_PROJECT} > C:\dev\content_import.txt 2>&1"
\$e = (Select-String -Path C:\dev\content_import.txt -Pattern 'ERROR' | Measure-Object -Line).Lines
Write-Output ('verify at ' + (git -C C:/dev/verify log --oneline -1) + ' | import errors: ' + \$e)
PS
echo "sync: $(since "$T0")"
