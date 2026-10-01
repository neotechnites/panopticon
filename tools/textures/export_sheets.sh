#!/usr/bin/env bash
# Exports every textures/*.aseprite sheet's slices to <slice>.png beside it (Mac Aseprite CLI).
set -e
cd "$(dirname "$0")/../.."
A="$HOME/Library/Application Support/Steam/steamapps/common/Aseprite/Aseprite.app/Contents/MacOS/aseprite"
for s in $(git ls-files '*/textures/*.aseprite'; git ls-files --others --exclude-standard '*/textures/*.aseprite'); do
  "$A" -b "$s" --split-slices --save-as "$(dirname "$s")/{slice}.png" >/dev/null
done
