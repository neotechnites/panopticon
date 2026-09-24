"""glb_textures -- a .glb's images as PNGs in each home's textures/, no bpy.
`python3 glb_textures.py embed <in> <out> <repo> <home>` re-embeds a copy for a scratch import."""

import glob
import json
import os
import posixpath
import struct
import sys
import zlib

# Chunks a plain PNG needs; the rest (gAMA, cHRM, iCCP, eXIf...) are colour hints we drop.
_KEEP = (b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND")
_KNOWN_EXT = {"KHR_materials_specular", "KHR_materials_emissive_strength",
              "KHR_texture_transform", "OMI_physics_body", "OMI_physics_shape"}


def find(root, stem):
    """Repo-relative path of <home>/textures/<stem>.png anywhere under root, or None."""
    for pat in ("*/textures/%s.png", "maps/*/textures/%s.png"):
        hits = sorted(glob.glob(os.path.join(root, pat % stem)))
        if hits:
            return os.path.relpath(hits[0], root).replace(os.sep, "/")
    return None


def plain_png(data):
    """The same pixels with only the critical chunks: no gamma or profile to reinterpret."""
    out, i = [data[:8]], 8
    while i < len(data):
        n, tag = struct.unpack(">I4s", data[i:i + 8])
        if tag in _KEEP:
            out.append(data[i:i + 12 + n])
        i += 12 + n
    return b"".join(out)


def write_png(path, w, h, rows, alpha):
    """rows: top-first lists of 0..255 ints, RGB or RGBA."""
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6 if alpha else 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(png)


def read(path):
    with open(path, "rb") as fh:
        data = fh.read()
    jlen = struct.unpack("<I", data[12:16])[0]
    js = json.loads(data[20:20 + jlen])
    rest = data[20 + jlen:]
    binary = rest[8:8 + struct.unpack("<I", rest[:4])[0]] if rest else b""
    return js, binary


def write(path, js, binary):
    body = json.dumps(js, separators=(",", ":")).encode("utf-8")
    body += b" " * ((4 - len(body) % 4) % 4)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    out = struct.pack("<I", len(body)) + b"JSON" + body
    if binary:
        out += struct.pack("<I", len(binary)) + b"BIN\x00" + binary
    with open(path, "wb") as fh:
        fh.write(b"glTF" + struct.pack("<II", 2, 12 + len(out)) + out)


def image_bytes(js, binary, im):
    bv = js["bufferViews"][im["bufferView"]]
    o = bv.get("byteOffset", 0)
    return binary[o:o + bv["byteLength"]]


def _repack(js, binary, drop):
    """Remove the bufferViews in `drop`, re-pack the rest, renumber every reference."""
    unknown = set(js.get("extensionsUsed", [])) - _KNOWN_EXT
    if unknown:
        raise RuntimeError("glb_textures: cannot renumber bufferViews under %s" % sorted(unknown))
    remap, views, parts, off = {}, [], [], 0
    for i, bv in enumerate(js.get("bufferViews", [])):
        if i in drop:
            continue
        o = bv.get("byteOffset", 0)
        chunk = binary[o:o + bv["byteLength"]]
        pad = (4 - off % 4) % 4
        parts.append(b"\x00" * pad)
        off += pad
        bv["byteOffset"] = off
        parts.append(chunk)
        off += len(chunk)
        remap[i] = len(views)
        views.append(bv)
    js["bufferViews"] = views
    for acc in js.get("accessors", []):
        if "bufferView" in acc:
            acc["bufferView"] = remap[acc["bufferView"]]
        sparse = acc.get("sparse")
        if sparse:
            for key in ("indices", "values"):
                sparse[key]["bufferView"] = remap[sparse[key]["bufferView"]]
    for im in js.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = remap[im["bufferView"]]
    binary = b"".join(parts)
    if js.get("buffers"):
        js["buffers"][0]["byteLength"] = len(binary)
    return binary


def externalize(path, uri_of):
    """Point each embedded image at uri_of(name, png bytes) (None keeps it embedded)
    and drop its bytes. Returns {name: uri} for what moved."""
    js, binary = read(path)
    drop, moved = set(), {}
    for im in js.get("images", []):
        if "bufferView" not in im:
            continue
        uri = uri_of(im.get("name", ""), image_bytes(js, binary, im))
        if uri is None:
            continue
        drop.add(im.pop("bufferView"))
        im.pop("mimeType", None)
        im["uri"] = uri
        moved[im.get("name", "")] = uri
    if drop:
        write(path, js, _repack(js, binary, drop))
    return moved


def embed(src, dst, root, home):
    """A self-contained copy of src (its uris read from root) for a scratch import check."""
    js, binary = read(src)
    base = posixpath.join(home, "models")
    views = js.setdefault("bufferViews", [])
    for im in js.get("images", []):
        uri = im.get("uri")
        if not uri or uri.startswith("data:"):
            continue
        with open(os.path.join(root, posixpath.normpath(posixpath.join(base, uri))), "rb") as fh:
            data = fh.read()
        binary += b"\x00" * ((4 - len(binary) % 4) % 4)
        views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
        binary += data
        del im["uri"]
        im["bufferView"] = len(views) - 1
        im["mimeType"] = "image/png"
    if js.get("buffers"):
        js["buffers"][0]["byteLength"] = len(binary)
    else:
        js["buffers"] = [{"byteLength": len(binary)}]
    write(dst, js, binary)


if __name__ == "__main__" and len(sys.argv) == 6 and sys.argv[1] == "embed":
    embed(*sys.argv[2:])
