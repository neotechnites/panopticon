#!/usr/bin/env bash
#
# scene_refs -- does anything in the game reference this model yet?
#
#   tools/modelling/lib/scene_refs.sh <name>
#
# Exit 0 and print the referencing files when it is referenced, exit 1 and
# print nothing when it is not. Nothing else decides this: the gate a model
# has to clear is derived from this answer, and a judgement call ("it's only a
# prop") is exactly the thing that gets a shipped model past the suite.
#
# It looks for both spellings a scene can use:
#   * the path            res://assets/models/<name>.glb
#   * the resource uid    uid://xxxxxxxxxxxxx   (read out of <name>.glb.import)
# A .tscn saved by the editor carries the uid, not the path, so grepping for
# the filename alone quietly answers "no" for a model that half the map uses.
#
# Searched: scenes/, scripts/, resources/ and project.godot. NOT tools/ and NOT
# tests/ -- a render harness or a fixture referencing a model is not the game
# depending on it.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
NAME="${1:-}"
[ -n "$NAME" ] || { echo "usage: scene_refs.sh <name>" >&2; exit 2; }

PATTERNS=("assets/models/${NAME}.glb")

IMPORT="$REPO/assets/models/${NAME}.glb.import"
if [ -f "$IMPORT" ]; then
  UID_LINE="$(grep -m1 -oE 'uid://[a-z0-9]+' "$IMPORT" || true)"
  [ -n "${UID_LINE:-}" ] && PATTERNS+=("$UID_LINE")
fi

DIRS=()
for d in scenes scripts resources; do
  [ -d "$REPO/$d" ] && DIRS+=("$REPO/$d")
done
[ -f "$REPO/project.godot" ] && DIRS+=("$REPO/project.godot")

HITS=""
if [ "${#DIRS[@]}" -gt 0 ]; then
  for p in "${PATTERNS[@]}"; do
    FOUND="$(grep -rlF -- "$p" "${DIRS[@]}" 2>/dev/null || true)"
    [ -n "$FOUND" ] && HITS="$HITS$FOUND"$'\n'
  done
fi

HITS="$(printf '%s' "$HITS" | sed '/^$/d' | sort -u)"
if [ -n "$HITS" ]; then
  printf '%s\n' "$HITS" | sed "s|^$REPO/||"
  exit 0
fi
exit 1
