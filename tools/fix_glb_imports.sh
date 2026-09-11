#!/usr/bin/env bash
# Force every glb import to keep its textures embedded and remove any PNGs Godot extracted.
cd "$(dirname "$0")/.." || exit 1
for f in assets/models/*.glb.import; do
  [ -f "$f" ] || continue
  if grep -q '^gltf/embedded_image_handling=' "$f"; then
    sed -i.bak 's/^gltf\/embedded_image_handling=.*/gltf\/embedded_image_handling=3/' "$f" && rm -f "$f.bak"
  else
    sed -i.bak 's/^\[params\]$/[params]\ngltf\/embedded_image_handling=3/' "$f" && rm -f "$f.bak"
  fi
done
rm -f assets/models/*_albedo.png assets/models/*_albedo.png.import assets/models/*_emissive.png assets/models/*_emissive.png.import
