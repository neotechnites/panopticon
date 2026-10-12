"""A brief's tagged script tables (`## script <tag>`): read, copy to a new tag, repoint a shot's cut.

    versions.py last <brief>                      # the newest tag ('' when only a plain ## script)
    versions.py has <brief> <tag>                 # exit 0 when ## script <tag> exists
    versions.py new <brief> <tag>                 # append ## script <tag>, a copy of the newest table
    versions.py cut <brief> <tag> <NN>            # the cut shot NN plays in <tag> (03, 03_v2) or ''
    versions.py repoint <brief> <tag> <NN> <name> # in <tag> only: cuts/NN*.mp4 -> cuts/<name>.mp4
    versions.py shots <brief>                     # "<id> <refilm tags>" per filmed shot entry
"""
import re
import sys


def sections(lines):
    """(tag, start, end) per ## script section; tag '' for the plain one; end is exclusive."""
    out, cur = [], None
    for i, line in enumerate(lines):
        if line.startswith("## "):
            if cur:
                out.append((cur[0], cur[1], i))
                cur = None
            m = re.match(r"^## script(?:\s+(\S+))?\s*$", line)
            if m:
                cur = (m.group(1) or "", i)
    if cur:
        out.append((cur[0], cur[1], len(lines)))
    return out


def cut_re(nn):
    return re.compile(r"cuts/%s(?:_[A-Za-z0-9_.-]+?)?\.mp4" % re.escape(nn))


def find(secs, tag):
    for s in secs:
        if s[0] == tag:
            return s
    sys.exit("versions: no ## script %s" % tag)


def main():
    cmd, path = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    secs = sections(lines)
    if cmd == "last":
        print(secs[-1][0] if secs else "")
    elif cmd == "has":
        sys.exit(0 if any(s[0] == sys.argv[3] for s in secs) else 1)
    elif cmd == "new":
        tag = sys.argv[3]
        if not secs:
            sys.exit("versions: the brief has no ## script table to copy")
        if any(s[0] == tag for s in secs):
            sys.exit("versions: ## script %s already exists" % tag)
        _, a, b = secs[-1]
        body = lines[a + 1:b]
        while body and not body[-1].strip():
            body.pop()
        while lines and not lines[-1].strip():
            lines.pop()
        lines += ["", "## script %s" % tag] + body + [""]
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        print("## script %s: copy of %s" % (tag, secs[-1][0] or "## script"))
    elif cmd == "cut":
        _, a, b = find(secs, sys.argv[3])
        rx = cut_re(sys.argv[4])
        for line in lines[a:b]:
            m = rx.search(line) if line.startswith("|") else None
            if m:
                print(m.group(0)[5:-4])
                return
        print("")
    elif cmd == "repoint":
        _, a, b = find(secs, sys.argv[3])
        rx, name = cut_re(sys.argv[4]), sys.argv[5]
        for i in range(a, b):
            if lines[i].startswith("|"):
                lines[i] = rx.sub("cuts/%s.mp4" % name, lines[i])
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
    elif cmd == "shots":
        cur, fields = None, {}
        for line in lines + ["## end"]:
            if line.startswith("## "):
                if cur and (fields.get("capture") or fields.get("still")):
                    print(cur, " ".join(re.split(r"[\s,]+", fields.get("refilm", "").strip())))
                m = re.match(r"^## (\d+[a-z]*)\s*$", line)
                cur, fields = (m.group(1) if m else None), {}
                continue
            m = re.match(r"^([a-z_]+):\s*(.*)$", line)
            if cur and m:
                fields[m.group(1)] = re.split(r"\s+#\s", m.group(2))[0]
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
