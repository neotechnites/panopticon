"""Deliver a passed cut: PC content\\<kind>\\<name>\\final\\<name>_vN.mp4 and the Mac copy, never overwriting.
Also fetches a PC final to the Mac work dir for review. Writes deliver.json for G15."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

from . import preflight

PC = preflight.PC
PC_CONTENT = r"C:\Users\ddd\Desktop\panopticon-renders\content"
MAC_CONTENT = os.path.expanduser("~/Desktop/panopticon-renders/content")
KIND_DIR = {"short": "shorts", "devlog": "devlogs", "trailer": "trailers"}


def is_pc(p):
    return bool(re.match(r"^[A-Za-z]:\\", p or ""))


def scp_path(p):
    return f"{PC}:{p.replace(chr(92), '/')}"


def mac_dir(kind, name):
    return os.path.join(MAC_CONTENT, KIND_DIR[kind], name)


def pc_dir(kind, name):
    return f"{PC_CONTENT}\\{KIND_DIR[kind]}\\{name}\\final"


def sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def fetch_final(src, kind, name):
    """A local copy of the final for review/OCR: PC paths are pulled into the Mac work dir."""
    if not is_pc(src):
        return src
    work = os.path.join(mac_dir(kind, name), "work")
    os.makedirs(work, exist_ok=True)
    dst = os.path.join(work, src.split("\\")[-1])
    subprocess.run(["scp", "-q", scp_path(src), dst], check=True)
    return dst


def _pc_versions(d, name, ext):
    rc, out = preflight.ssh(f'Get-ChildItem "{d}" -Filter "{name}_v*.{ext}" -ErrorAction SilentlyContinue | '
                            'ForEach-Object Name')
    return out.splitlines() if rc == 0 else []


def _ver(names, name, ext):
    return {int(m.group(1)) for n in names for m in [re.fullmatch(rf"{re.escape(name)}_v(\d+)\.{ext}", n.strip())] if m}


def deliver(ctx_dir, src, kind, name, tag=None, fcpxml=None, concat=False, log=print):
    """Copies `src` (PC or local) to both ends as <name>_vN; returns the deliver.json dict."""
    ext = "fcpxml" if kind == "devlog" and not concat else "mp4"
    item = fcpxml if ext == "fcpxml" else src
    if not item:
        raise SystemExit(f"deliver: nothing to deliver ({'fcpxml' if ext == 'fcpxml' else 'final mp4'} missing)")
    md, pd = mac_dir(kind, name), pc_dir(kind, name)
    os.makedirs(md, exist_ok=True)
    taken = _ver(os.listdir(md), name, ext) | _ver(_pc_versions(pd, name, ext), name, ext)
    if tag:
        n = int(tag.lstrip("v"))
        same_file = is_pc(item) and item.lower() == f"{pd}\\{name}_v{n}.{ext}".lower()
        if n in taken and not same_file:
            raise SystemExit(f"deliver: {name}_v{n}.{ext} already exists; Resolve may have seen it (363). Use a new tag.")
    else:
        n = max(taken | {0}) + 1
    fname = f"{name}_v{n}.{ext}"
    pc_dst, mac_dst = f"{pd}\\{fname}", os.path.join(md, fname)
    if os.path.exists(mac_dst):
        raise SystemExit(f"deliver: refusing to overwrite {mac_dst}")
    preflight.ssh(f'New-Item -ItemType Directory -Force "{pd}" | Out-Null')
    if is_pc(item):
        if item.lower() != pc_dst.lower():
            rc, out = preflight.ssh(f'if (Test-Path "{pc_dst}") {{ "EXISTS" }} else {{ Copy-Item "{item}" "{pc_dst}"; "ok" }}',
                                    timeout=300)
            if not out.endswith("ok"):
                raise SystemExit(f"deliver: PC copy failed: {out[-120:]}")
        subprocess.run(["scp", "-q", scp_path(pc_dst), mac_dst], check=True)
    else:
        rc, out = preflight.ssh(f'Test-Path "{pc_dst}"')
        if out.strip() == "True":
            raise SystemExit(f"deliver: refusing to overwrite {pc_dst}")
        subprocess.run(["scp", "-q", item, scp_path(pc_dst)], check=True)
        subprocess.run(["cp", item, mac_dst], check=True)
    rc, out = preflight.ssh(f'(Get-Item "{pc_dst}").Length')
    d = {"tag": f"v{n}", "pc": pc_dst, "mac": mac_dst, "size": int(out.strip()) if out.strip().isdigit() else None,
         "sha1": sha1(mac_dst), "overwrote": None, "kind": kind,
         "fcpxml": pc_dst if ext == "fcpxml" else None, "mp4": pc_dst if ext == "mp4" else None,
         "concat_asked": bool(concat)}
    with open(os.path.join(ctx_dir, "deliver.json"), "w") as f:
        json.dump(d, f, indent=1)
    with open(mac_dst + ".prov.json", "w") as f:
        json.dump({"inputs": [d["sha1"]], "input_paths": [item], "encoder": "copy", "lossless": True,
                   "tool": "cp.deliver", "version": "1"}, f, indent=1)
    log(f"delivered {fname}: Mac {mac_dst}  PC {pc_dst}")
    return d


def main(argv=None):
    ap = argparse.ArgumentParser(prog="content deliver")
    ap.add_argument("dir", help="build dir (deliver.json is written here)")
    ap.add_argument("src", help="final mp4, local or PC path")
    ap.add_argument("--kind", default="short", choices=list(KIND_DIR))
    ap.add_argument("--name", required=True)
    ap.add_argument("--tag")
    ap.add_argument("--fcpxml")
    a = ap.parse_args(argv)
    deliver(a.dir, a.src, a.kind, a.name, a.tag, a.fcpxml)
    return 0


if __name__ == "__main__":
    sys.exit(main())
