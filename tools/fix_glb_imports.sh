#!/usr/bin/env bash
# Force every glb import to keep its textures embedded, guarantee the mipmap
# post-import hook, and remove any PNGs Godot extracted.
cd "$(dirname "$0")/.." || exit 1
HOOK='res://tools/import/mipmap_textures.gd'
for f in */models/*.glb.import maps/*/models/*.glb.import; do
  [ -f "$f" ] || continue
  if grep -q '^gltf/embedded_image_handling=' "$f"; then
    sed -i.bak 's/^gltf\/embedded_image_handling=.*/gltf\/embedded_image_handling=3/' "$f" && rm -f "$f.bak"
  else
    sed -i.bak 's/^\[params\]$/[params]\ngltf\/embedded_image_handling=3/' "$f" && rm -f "$f.bak"
  fi
  # Same shape, for the post-import hook: set it when blank or already ours,
  # leave a foreign script alone and say so, insert the line when missing.
  if grep -q '^import_script/path=' "$f"; then
    cur=$(sed -n 's|^import_script/path=||p' "$f" | head -1 | tr -d '\r"')
    if [ -z "$cur" ] || [ "$cur" = "$HOOK" ]; then
      sed -i.bak "s|^import_script/path=[^[:cntrl:]]*|import_script/path=\"$HOOK\"|" "$f" && rm -f "$f.bak"
    else
      echo "WARNING: $f keeps its own import_script $cur" >&2
    fi
  else
    sed -i.bak "s|^\[params\]\$|[params]\\
import_script/path=\"$HOOK\"|" "$f" && rm -f "$f.bak"
  fi
done
rm -f */models/*_albedo.png* */models/*_emissive.png* maps/*/models/*_albedo.png* maps/*/models/*_emissive.png*
