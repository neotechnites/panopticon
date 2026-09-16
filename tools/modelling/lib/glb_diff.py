"""glb_diff -- WHERE two .glb files disagree, not just that they do.

``model parity`` builds one script on both boxes and compares the bytes. When
they differ the only question worth asking immediately is *what* differs, and
the answer decides what you do next:

  * geometry bufferViews  -- the models are not the same model. A build script
    branched on a floating-point comparison and arm64 and x86-64 landed on
    opposite sides of it (a ``sorted(key=...)`` tie, a ``>`` on a dot product).
    Build that model on the PC.
  * image bufferViews     -- a painted texture rounded a handful of texels
    differently. The shape is identical.
  * the JSON chunk        -- different exporter, i.e. different Blender.

Usage::

    python3 glb_diff.py a.glb b.glb
"""

import json
import struct
import sys


def _chunks(data):
    """(json dict, offset of the BIN chunk's first byte)."""
    if data[:4] != b"glTF":
        raise SystemExit("glb_diff: %r is not a .glb" % data[:4])
    length, _kind = struct.unpack_from("<II", data, 12)
    return json.loads(data[20:20 + length]), 20 + length + 8


def main(argv):
    if len(argv) != 3:
        raise SystemExit("usage: glb_diff.py a.glb b.glb")
    a = open(argv[1], "rb").read()
    b = open(argv[2], "rb").read()
    if len(a) != len(b):
        print("DIFF sizes differ: %d vs %d bytes" % (len(a), len(b)))
    gltf, bin_off = _chunks(a)

    image_views = {img["bufferView"] for img in gltf.get("images", [])
                   if "bufferView" in img}
    spans = []
    for i, bv in enumerate(gltf.get("bufferViews", [])):
        start = bin_off + bv.get("byteOffset", 0)
        spans.append((start, start + bv["byteLength"], i in image_views))

    differing = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
    in_json = sum(1 for i in differing if i < bin_off)
    in_image = in_geom = 0
    for i in differing:
        for lo, hi, is_image in spans:
            if lo <= i < hi:
                if is_image:
                    in_image += 1
                else:
                    in_geom += 1
                break

    print("DIFF %d of %d bytes: json/header=%d geometry=%d image=%d"
          % (len(differing), len(a), in_json, in_geom, in_image))
    if in_geom:
        print("DIFF the GEOMETRY differs -- these are not the same model.")
    elif in_image:
        print("DIFF only painted texels differ -- the shape is identical.")
    return 1 if differing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
