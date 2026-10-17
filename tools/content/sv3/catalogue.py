"""Stage catalogue: stage .gd headers + approved `## n` entries -> stages.json, STAGES.md (`python -m sv3.catalogue`).
Exit 1 when an entry's --stage names no stage file."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONTENT = os.path.dirname(HERE)
STAGES_DIR = os.path.join(CONTENT, "..", "capture", "stages")
PROJECTS = ["haters_final", "haters", "shove", "ragdoll_short", "trailer_reveal"]
NOT_STAGES = {"stage", "lib", "guard_hand", "probe_ring"}
TICK_KINDS = ("hit", "shove", "out", "go")
FIELDS = ("said", "capture", "tape", "expect", "seconds", "in")
NUM = r"-?\d+(?:\.\d+)?"
LEAD = re.compile(r"^(%s(?:,%s)*)(?![\w.])" % (NUM, NUM))
IDENT = re.compile(r"^[a-z_][a-z0-9_]*$")


def map_name(raw):
    """--map= value -> hell|forest|marble."""
    raw = raw.lower()
    if "forest" in raw:
        return "forest"
    if "marble" in raw:
        return "marble"
    return "hell"


def value(text):
    """'0.3' -> 0.3, '4' -> 4, '162,151,140' stays a string."""
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(NUM, text):
        return float(text)
    return text


def header(path):
    """The comment block at the top of a stage file, '#'s stripped, one string per line."""
    lines = []
    with open(path) as f:
        for i, line in enumerate(f):
            s = line.strip()
            if s.startswith("#"):
                lines.append(s.lstrip("#").rstrip())
            elif i == 0 or not s:
                continue
            else:
                break
    return lines


def code_defaults(path):
    """option("name", literal) fallbacks in the stage's own code."""
    out = {}
    with open(path) as f:
        for name, lit in re.findall(r'option\("(\w+)",\s*([^)]+?)\)', f.read()):
            lit = lit.strip()
            if re.fullmatch(NUM, lit):
                out.setdefault(name, value(lit))
            elif re.fullmatch(r'"[^"]*"', lit):
                out.setdefault(name, value(lit[1:-1]))
    return out


def split_top(text, seps=",;"):
    """Split on separators outside parentheses."""
    parts, depth, cur = [], 0, ""
    for ch in text:
        depth += (ch == "(") - (ch == ")")
        if ch in seps and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return [p.strip() for p in parts if p.strip()]


def dials_text(lines):
    """The Dials paragraph: inline after 'Dials...:' to the sentence's end, or the indented block under it."""
    for i, line in enumerate(lines):
        m = re.search(r"Dials\b(?:\s*\(--set=\))?\s*(:|as\b)?\s*(.*)$", line)
        if not m or "Dials" not in line:
            continue
        if m.group(1) == "as":
            return "", [], re.findall(r"(\w+)'s", m.group(2))
        rest = m.group(2)
        if not rest.strip():
            block = []
            for nxt in lines[i + 1:]:
                if not nxt.strip():
                    break
                block.append(nxt)
            return "", block, []
        text = rest
        for nxt in lines[i + 1:]:
            if not nxt.strip() or re.search(r"\.\s+[A-Z]", text) or re.search(r"\.$", text.strip()):
                break
            text += " " + nxt.strip()
        depth, cut = 0, len(text)
        for j, ch in enumerate(text):
            depth += (ch == "(") - (ch == ")")
            if depth == 0 and ch == "." and (j + 1 == len(text) or (text[j + 1] == " " and text[j + 2:j + 3].isupper())):
                cut = j
                break
        return text[:cut], [], []
    return "", [], []


def paren_default(inner):
    """Default from a '(...)' note: its leading number(s), else its last number."""
    if inner is None:
        return None
    m = LEAD.match(inner.strip())
    if m:
        return value(m.group(1))
    nums = re.findall(NUM, inner)
    return value(nums[-1]) if nums else None


class Lazy(dict):
    """Each stage's dials on first use, so 'scope_hunt's' resolves whatever the order."""
    def __init__(self, make):
        super().__init__()
        self.make = make

    def get(self, key, default=None):
        return self[key]

    def __missing__(self, key):
        self[key] = {}
        self[key] = self.make(key)
        return self[key]


def parse_dials(stage, lines, code, all_dials):
    """{name: default} from the header, defaults falling back to the code's option() literals."""
    inline, block, inherit = dials_text(lines)
    out = {}
    pieces = []
    if block:
        for row in block:
            m = re.match(r"\s*([a-z_][a-z0-9_/]*)\s{2,}(.*)$", row)
            if m:
                inner = re.findall(r"\(([^()]*)\)", m.group(2))
                names, note = m.group(1).split("/"), inner[-1] if inner else None
                nums = re.findall(NUM, note or "")
                if len(names) > 1 and len(nums) >= len(names):
                    pieces.extend(([n], value(v)) for n, v in zip(names, nums[-len(names):]))
                else:
                    pieces.append((names, note))
    for piece in [q for p in split_top(inline) for q in re.split(r"(?<=\))(?::[^()]*?)?\s+and\s+", p)]:
        piece = re.sub(r"^(plus|and)\s+", "", piece)
        own = re.match(r"^(\w+)'s$", piece)
        if own:
            inherit.append(own.group(1))
            continue
        alias = re.match(r"^([\w/]+) as (\w+)", piece)
        if alias:
            inherit.append((alias.group(1).split("/"), alias.group(2)))
            continue
        m = re.match(r"^([^()]*?)\s*(?:\((.*)\))?\s*(?::.*)?$", piece)
        if not m:
            continue
        names = [n for chunk in re.split(r"\s+and\s+|/", m.group(1)) for n in [chunk.strip()]]
        named = [n for n in names if IDENT.match(n)]
        if not named:
            continue
        inner = m.group(2)
        pieces.extend(([n], inner) for n in named)
    for names, inner in pieces:
        for n in names:
            d = code.get(n) if n in code and code[n] != "" else (inner if not isinstance(inner, str) else None)
            if d is None and isinstance(inner, str):
                lead = LEAD.match(inner.strip())
                d = value(lead.group(1)) if lead else None
            if d is None:
                d = code.get(n)
            if d is None and isinstance(inner, str):
                d = paren_default(inner)
            out[n] = d
    for src in inherit:
        if isinstance(src, tuple):
            names, other = src
            base = all_dials.get(other, {})
            for n in names:
                out.setdefault(n, base.get(n, code.get(n)))
        else:
            for n, d in all_dials.get(src, {}).items():
                out.setdefault(n, d)
    return out


def ticks(expect):
    """Midpoint of each hit/shove/out/go clause's lo-hi; '+' spans ride the first timed clause's midpoint."""
    out = {k: None for k in TICK_KINDS}
    if not expect:
        return out
    anchor = None
    for clause in [c.strip() for c in expect.split(";") if c.strip()]:
        words = clause.split()
        m = re.match(r"^(\+?)(%s)-(%s)$" % (NUM, NUM), words[-1])
        if not m:
            continue
        mid = (float(m.group(2)) + float(m.group(3))) / 2.0
        t = (anchor or 0.0) + mid if m.group(1) else mid
        if anchor is None:
            anchor = t
        if words[0] in out and out[words[0]] is None:
            out[words[0]] = round(t, 3)
    return out


def entries(project):
    """Every `## n` entry of a project with its said/capture/tape/expect/seconds/in."""
    path = os.path.join(CONTENT, "projects", project + ".md")
    found, cur = [], None
    with open(path) as f:
        for line in f:
            head = re.match(r"^## (\S+)\s*$", line)
            if line.startswith("## "):
                cur = None
                if head and re.match(r"^\d+[a-z]*$", head.group(1)):
                    eid = head.group(1)
                    cur = {"project": project, "entry": int(eid) if eid.isdigit() else eid}
                    found.append(cur)
                continue
            m = re.match(r"^(\w+):\s?(.*?)\s*$", line)
            if cur is not None and m and m.group(1) in FIELDS and m.group(1) not in cur:
                cur[m.group(1)] = m.group(2)
    for e in found:
        for k in ("seconds", "in"):
            e[k] = value(e[k]) if k in e and re.fullmatch(NUM, e[k]) else e.get(k)
            if isinstance(e[k], int):
                e[k] = float(e[k])
        for k in FIELDS:
            e.setdefault(k, None)
        e["ticks"] = ticks(e["expect"])
    return found


def flag(text, name):
    m = re.search(r"--%s=(\S+?)(?=[\s\[]|$)" % name, text or "")
    return m.group(1) if m else None


def main():
    files = sorted(f[:-3] for f in os.listdir(STAGES_DIR) if f.endswith(".gd") and f[:-3] not in NOT_STAGES)
    approved, missing = {}, []
    for project in PROJECTS:
        for e in entries(project):
            stage = flag(e["capture"], "stage")
            if not stage:
                continue
            if stage not in files:
                missing.append("%s ## %s: --stage=%s" % (project, e["entry"], stage))
                continue
            approved.setdefault(stage, []).append({k: e[k] for k in ("project", "entry") + FIELDS + ("ticks",)})
    heads = {s: header(os.path.join(STAGES_DIR, s + ".gd")) for s in files}
    dials = Lazy(lambda s: parse_dials(s, heads[s], code_defaults(os.path.join(STAGES_DIR, s + ".gd")), dials)
                 if s in heads else {})
    stages = {}
    for s in files:
        text = " ".join(heads[s])
        caps = " ".join(e["capture"] or "" for e in approved.get(s, []))
        raw_map = flag(text, "map") or flag(caps, "map")
        if raw_map in (None, ")"):
            raw_map = "hell"
        with open(os.path.join(STAGES_DIR, s + ".gd")) as f:
            need = re.search(r'func needs_pov\(\)[^\n]*\n\s*return "(\w*)"', f.read())
        povs = [need.group(1)] if need and need.group(1) else \
            [p for p in ("guard", "runner") if re.search(r"--pov=%s\b" % p, text + " " + caps)]
        stages[s] = {"map": map_name(raw_map), "shot": flag(text, "shot") or flag(caps, "shot"), "povs": povs,
                     "dials": dials[s], "for_shorts": not s.startswith("trailer_"), "approved": approved.get(s, [])}
    doc = {"stages": stages, "uncatalogued": sorted(s for s in files if not approved.get(s))}
    with open(os.path.join(HERE, "stages.json"), "w") as f:
        json.dump(doc, f, indent=1)
        f.write("\n")
    rows = ["# Stages", "", "Written by `python -m sv3.catalogue` from the stage headers and approved entries; stages.json is the source.", "",
            "| stage | map | shot | povs | dials | approved entries | ticks | for_shorts |", "|---|---|---|---|---|---|---|---|"]
    for s in files:
        d = stages[s]
        dial = ", ".join("%s=%s" % (k, v) for k, v in d["dials"].items())
        ents = ", ".join("%s#%s" % (e["project"], e["entry"]) for e in d["approved"]) or "uncatalogued"
        tk = "; ".join(", ".join("%s %s" % (k, v) for k, v in e["ticks"].items() if v is not None) or "-" for e in d["approved"]) or "-"
        rows.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (s, d["map"], d["shot"] or "-", "/".join(d["povs"]) or "-",
                    dial.replace("|", "/") or "-", ents, tk, "yes" if d["for_shorts"] else "no"))
    with open(os.path.join(HERE, "STAGES.md"), "w") as f:
        f.write("\n".join(rows) + "\n")
    for m in missing:
        print("missing stage file: " + m, file=sys.stderr)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
