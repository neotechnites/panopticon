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
_KNOWN_EXT = {"KHR_materials_specular", "KHR_materials_emissive_strength", "KHR_materials_unlit",
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


def read_png(path):
    """(w, h, rows): an 8-bit PNG decoded to top-first rows of (r, g, b) 0..255."""
    with open(path, "rb") as fh:
        data = fh.read()
    i, idat, plte = 8, b"", None
    while i < len(data):
        n, tag = struct.unpack(">I4s", data[i:i + 8])
        body = data[i + 8:i + 8 + n]
        if tag == b"IHDR":
            w, h, depth, ctype, _c, _f, inter = struct.unpack(">IIBBBBB", body)
        elif tag == b"PLTE":
            plte = [tuple(body[k:k + 3]) for k in range(0, n, 3)]
        elif tag == b"IDAT":
            idat += body
        i += 12 + n
    if depth != 8 or inter:
        raise RuntimeError("%s: only 8-bit, non-interlaced PNGs are read" % path)
    bpp = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw, stride, prev, rows, o = zlib.decompress(idat), w * bpp, bytearray(w * bpp), [], 0
    for _y in range(h):
        ft, line = raw[o], bytearray(raw[o + 1:o + 1 + stride])
        o += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b, c = prev[x], prev[x - bpp] if x >= bpp else 0
            if ft == 1:
                line[x] = (line[x] + a) & 255
            elif ft == 2:
                line[x] = (line[x] + b) & 255
            elif ft == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        if ctype == 3:
            rows.append([plte[v] for v in line])
        elif ctype in (0, 4):
            rows.append([(line[k],) * 3 for k in range(0, stride, bpp)])
        else:
            rows.append([tuple(line[k:k + 3]) for k in range(0, stride, bpp)])
    return w, h, rows


def png_size(path):
    with open(path, "rb") as fh:
        head = fh.read(24)
    return struct.unpack(">II", head[16:24])


def png_mean(path):
    """Linear mean (r, g, b) over every texel."""
    lin = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in (k / 255.0 for k in range(256))]
    w, h, rows = read_png(path)
    acc = [0.0, 0.0, 0.0]
    for row in rows:
        for px in row:
            for ch in range(3):
                acc[ch] += lin[px[ch]]
    return tuple(a / (w * h) for a in acc)


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
