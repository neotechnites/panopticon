"""Read a content brief (tools/content/projects/<name>.md).

Shared by the PC-side scripts (voice.py, assemble.py, dailies.py) and by the
Mac (python3) for the same answers. No dependencies beyond the stdlib.

A brief is: a title line, header `key: value` lines, then `## n` shot entries
and, optionally, a `## script` section -- header lines then a pipe table:

    ## script
    voice: en-US-AndrewNeural +5%
    music: voice/windmill_isle_day.mp3
    music_db: -18
    | line | clip | in | len | fit | speed | text |
    | l0 | final/f10_lava_parkour.mp4 | | | line | | I added this to my game. |

`## script <tag>` is an alternate cut's own table: assemble.py uses it for that tag.
Everything after a `#` outside the table is a comment. Table cells are
stripped; an empty cell is "".
"""
import re
import sys


def parse(path):
    head, shots, script, scripts = {}, [], None, {}
    table = None
    section = "head"
    current = None
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    for raw in lines:
        line = raw.rstrip()
        if line.startswith("# ") and "title" not in head and section == "head":
            head["title"] = line[2:].strip()
            continue
        m = re.match(r"^## (\d+)([a-z]*)\s*$", line)
        if m:
            current = {"n": int(m.group(1)) if not m.group(2) else m.group(1) + m.group(2)}
            shots.append(current)
            section = "shot"
            continue
        m = re.match(r"^## script(?:\s+(\S+))?\s*$", line)
        if m:
            table = {"head": {}, "rows": []}
            if m.group(1):
                scripts[m.group(1)] = table
            else:
                script = table
            section = "script"
            continue
        if line.startswith("## "):
            section = "other"
            continue
        if section == "script" and line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not cells or set(cells[0]) <= set("-: ") and len(cells) > 1 and all(set(c) <= set("-: ") for c in cells):
                continue
            if cells[0].lower() == "line":
                table["columns"] = [c.lower() for c in cells]
                continue
            cols = table.get("columns") or ["line", "clip", "in", "len", "fit", "speed", "text"]
            row = {k: "" for k in cols}
            for k, v in zip(cols, cells):
                row[k] = v
            table["rows"].append(row)
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if m:
            key, value = m.group(1), m.group(2)
            # A trailing "# comment" is dropped; the said: line keeps everything.
            if key != "said" and key != "text":
                value = re.split(r"\s+#\s", value)[0].strip()
            target = head if section == "head" else current if section == "shot" else table["head"] if section == "script" else None
            if target is not None:
                target[key] = value
    return {"head": head, "shots": shots, "script": script, "scripts": scripts}


def voice_rows(script):
    """Rows that carry a voice line (text and not a beat)."""
    return [r for r in table["rows"] if r.get("text") and not r.get("fit", "").startswith("beat")]


if __name__ == "__main__":
    import json
    print(json.dumps(parse(sys.argv[1]), indent=1))
