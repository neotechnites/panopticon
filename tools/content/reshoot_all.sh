#!/usr/bin/env bash
# Reshoot every shot of a project from its tapes and cut it again: sync, shot.sh per
# entry in brief order, assemble.sh, dailies.sh, and the cut copied to the Mac.
#
#   tools/content/reshoot_all.sh <project> [first-id]
#
# The brief's header tag: names the cut (final\<tag>.mp4). first-id resumes from that shot.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/reshoot_all.sh <project> [first-id]}"
FROM="${2:-}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
TAG=$(brief_head "${BRIEF}" tag "${NAME}")
HERE="$(dirname "$0")"
T0=$(now_ms)
"${HERE}/sync.sh"
STARTED=$([ -z "${FROM}" ] && echo 1 || echo 0)
for id in $(grep '^## [0-9]' "${BRIEF}" | awk '{print $2}'); do
  [ "${id}" = "${FROM}" ] && STARTED=1
  [ "${STARTED}" = 1 ] || continue
  [ -n "$(brief_field "${BRIEF}" "${id}" capture)" ] || continue
  "${HERE}/shot.sh" "${NAME}" "${id}"
done
"${HERE}/assemble.sh" "${NAME}" --tag "${TAG}"
"${HERE}/dailies.sh" "${NAME}"
mkdir -p "${HOME}/Desktop/panopticon-renders/${NAME}"
pc_pull "$(ff "$(project_dir "${NAME}")")/final/${TAG}.mp4" "${HOME}/Desktop/panopticon-renders/${NAME}/${TAG}.mp4"
echo "reshoot_all ${NAME}: ${TAG}.mp4 in $(since "$T0")"
