r"""Poster frames and a dailies page for a project, so Ryan can review every
take in a browser (through tools/content/serve.sh) and answer by clip id.

Runs ON THE PC (tools/content/dailies.sh pushes it):

    python dailies.py <project dir> <brief.md> [<out.html>]

Thumbs: one 360-wide jpg per mp4 in final\, cuts\ and external\ (top level
only), at final\thumbs\<name>.jpg, made only when missing or older than the
clip. The page (default final\index.html):

  1. the latest cut -- final\<title>.mp4 or the newest final\*.mp4 that has a
     cuts\<tag>_timing.txt -- with its timing table and the script lines;
  2. the external footage (landscape, 16/9) with the credit line from
     external\SOURCES.md;
  3. every shot in the brief with a file: line, in order: id, the said: line
     quoted, seconds, status;
  4. any other mp4 in final\ (takes made outside the brief), alphabetically.

Every <video> is preload="none" with a poster frame and a cache-busting
?v=<mtime> on its src, the three things Ryan asked for when the page kept
reloading every clip. One inline <style>, no fonts fetched, dark.
"""
import html
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brief as brief_mod  # noqa: E402


def dur(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out) if out else 0.0


def is_landscape(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip().split(",")
    return len(out) == 2 and int(out[0]) > int(out[1])


def make_thumbs(project):
    out = os.path.join(project, "final", "thumbs")
    os.makedirs(out, exist_ok=True)
    made = 0
    for sub in ("final", "cuts", "external"):
        folder = os.path.join(project, sub)
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            if not name.lower().endswith(".mp4"):
                continue
            src = os.path.join(folder, name)
            jpg = os.path.join(out, os.path.splitext(name)[0] + ".jpg")
            if os.path.exists(jpg) and os.path.getmtime(jpg) >= os.path.getmtime(src):
                continue
            at = min(1.5, max(dur(src) * 0.4, 0.0))
            subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error", "-ss", f"{at:.2f}", "-i", src,
                            "-frames:v", "1", "-vf", "scale=360:-2", "-q:v", "5", jpg])
            made += 1
    return made


def sources(project):
    """external\\SOURCES.md -> {file stem: {"title": ..., "credit": ...}}."""
    path = os.path.join(project, "external", "SOURCES.md")
    found = {}
    if not os.path.exists(path):
        return found
    current = None
    credit_open = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("## "):
                names = re.findall(r"([A-Za-z0-9_\-]+)\.mp4", line)
                current = {"title": line[3:].strip(), "credit": "", "notes": []}
                for n in names:
                    found[n] = current
                credit_open = False
                continue
            if current is None:
                continue
            m = re.match(r"^- Credit line:\s*(.*)$", line)
            if m:
                current["credit"] = m.group(1).strip()
                credit_open = True
                continue
            if credit_open and line.startswith("  ") and not line.startswith("- "):
                current["credit"] += " " + line.strip()
                continue
            credit_open = False
            if line.startswith("- "):
                current["notes"].append(line[2:].strip())
    return found


def video(src_rel, poster_rel, mtime, landscape=False):
    style = ' style="aspect-ratio:16/9"' if landscape else ""
    return ('<video controls preload="none" playsinline poster="%s"%s src="%s?v=%d"></video>'
            % (html.escape(poster_rel), style, html.escape(src_rel), int(mtime)))


def main():
    project, brief_path = sys.argv[1], sys.argv[2]
    out_html = sys.argv[3] if len(sys.argv) > 3 else os.path.join(project, "final", "index.html")
    parsed = brief_mod.parse(brief_path)
    title = parsed["head"].get("title", os.path.basename(project))
    made = make_thumbs(project)
    final = os.path.join(project, "final")
    cuts = os.path.join(project, "cuts")
    esc = html.escape

    def thumb(name):
        return "thumbs/%s.jpg" % os.path.splitext(name)[0]

    parts = []
    parts.append("<title>%s dailies</title>" % esc(title))
    parts.append("""<style>
:root{--bg:#141012;--panel:#1d1719;--ink:#efe6e2;--mute:#a4928c;--line:#3a2b2c;--acc:#ffb15c;--ok:#7fd48a}
body{background:var(--bg);color:var(--ink);font-family:system-ui,-apple-system,sans-serif;padding:0 16px;padding-block:20px 60px;max-width:1100px;margin:0 auto}
h1{font-size:2rem;text-transform:uppercase;letter-spacing:.02em;margin:0 0 4px}
h3{text-transform:uppercase;letter-spacing:.04em;font-size:1.1rem;margin:26px 0 12px;color:var(--mute)}
.sub{color:var(--mute);margin:0 0 22px;font-size:.95rem}
.cut{display:grid;grid-template-columns:minmax(200px,300px) 1fr;gap:20px;align-items:start;background:var(--panel);border:1px solid var(--line);padding:16px;margin-bottom:28px}
.cut video,.clip video{width:100%;aspect-ratio:9/16;background:#000;display:block}
pre{font-size:.72rem;line-height:1.35;overflow-x:auto;color:var(--mute);margin:0}
table{border-collapse:collapse;width:100%;font-size:.85rem;font-variant-numeric:tabular-nums}
td,th{padding:5px 8px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
th{color:var(--mute);font-weight:500;text-transform:uppercase;letter-spacing:.06em;font-size:.72rem}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:18px}
.grid.wide{grid-template-columns:repeat(auto-fill,minmax(300px,1fr))}
.clip{background:var(--panel);border:1px solid var(--line);padding:10px;display:flex;flex-direction:column;gap:8px}
.id{font-family:ui-monospace,Menlo,monospace;font-size:.78rem;color:var(--acc)}
.line{font-size:.86rem;line-height:1.4}
.line q{color:var(--mute);font-style:italic}
.desc{font-size:.8rem;color:var(--mute);line-height:1.4}
.meta{display:flex;justify-content:space-between;font-size:.72rem;color:var(--mute);font-family:ui-monospace,Menlo,monospace}
@media (max-width:560px){.cut{grid-template-columns:1fr}}
</style>""")
    parts.append("<h1>%s dailies</h1>" % esc(title))
    parts.append('<p class="sub">Every delivered take, in brief order, plus the latest cut. Answer by clip id. Built %s.</p>'
                 % time.strftime("%Y-%m-%d %H:%M"))

    # 1. The latest cut.
    latest = None
    candidates = []
    for name in os.listdir(final) if os.path.isdir(final) else []:
        if name.lower().endswith(".mp4"):
            tag = os.path.splitext(name)[0]
            if os.path.exists(os.path.join(cuts, tag + "_timing.txt")):
                candidates.append((os.path.getmtime(os.path.join(final, name)), name))
    if candidates:
        candidates.sort(reverse=True)
        latest = candidates[0][1]
        for _m, name in candidates:
            if os.path.splitext(name)[0] == title:
                latest = name
    if latest:
        tag = os.path.splitext(latest)[0]
        src = os.path.join(final, latest)
        with open(os.path.join(cuts, tag + "_timing.txt"), encoding="utf-8") as f:
            timing = f.read()
        rows = ""
        lines_path = os.path.join(cuts, tag + "_lines.json")
        script = parsed["script"]
        if script and os.path.exists(lines_path):
            with open(lines_path, encoding="utf-8") as f:
                starts = json.load(f)
            for r in script["rows"]:
                rows += "<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % (
                    esc("%.1f" % starts.get(r["line"], 0.0)), esc(r.get("text", "")), esc(r.get("clip", "")))
        parts.append('<h3>Latest cut</h3><div class="cut">%s<div><h2 style="margin:0 0 8px;font-size:1.1rem">%s</h2>'
                     '<div class="meta"><span>%.1f s</span><span>%s</span></div>'
                     % (video(latest, thumb(latest), os.path.getmtime(src)), esc(tag), dur(src),
                        time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(src)))))
        if rows:
            parts.append("<table><tr><th>Start</th><th>Line</th><th>Clip</th></tr>%s</table>" % rows)
        parts.append("<pre>%s</pre></div></div>" % esc(timing))

    # 2. External footage.
    ext = os.path.join(project, "external")
    ext_files = sorted(n for n in os.listdir(ext)) if os.path.isdir(ext) else []
    ext_files = [n for n in ext_files if n.lower().endswith(".mp4")]
    if ext_files:
        creds = sources(project)
        parts.append('<h3>External footage (landscape, see external/SOURCES.md)</h3><div class="grid wide">')
        for name in ext_files:
            stem = os.path.splitext(name)[0]
            src = os.path.join(ext, name)
            info = creds.get(stem, {})
            parts.append('<div class="clip"><div class="id">%s</div>%s<div class="desc">%s</div>'
                         '<div class="meta"><span>%.1f s</span><span>%s</span></div></div>'
                         % (esc(stem), video("../external/" + name, thumb(name), os.path.getmtime(src), landscape=True),
                            esc(info.get("credit") or info.get("title") or "no entry in SOURCES.md"), dur(src),
                            "credited" if info.get("credit") else "uncredited"))
        parts.append("</div>")

    # 3. The brief's shots, in order.
    covered = set()
    cards = []
    for shot in parsed["shots"]:
        file_name = shot.get("file", "")
        if not file_name:
            continue
        name = file_name + ".mp4"
        src = os.path.join(final, name)
        covered.add(name)
        if not os.path.exists(src):
            cards.append('<div class="clip"><div class="id">%s</div><div class="desc">not rendered yet: tools/content/shot.sh %s %d</div></div>'
                         % (esc(file_name), esc(title), shot["n"]))
            continue
        note = shot.get("note", "")
        cards.append('<div class="clip"><div class="id">%s</div>%s<div class="line"><q>%s</q></div>%s'
                     '<div class="meta"><span>%.1f s</span><span>shot %d</span></div></div>'
                     % (esc(file_name), video(name, thumb(name), os.path.getmtime(src)), esc(shot.get("said", "")),
                        ('<div class="desc">%s</div>' % esc(note)) if note else "", dur(src), shot["n"]))
    if cards:
        parts.append('<h3>Shots in brief order</h3><div class="grid">%s</div>' % "".join(cards))

    # 4. Everything else in final\.
    others = []
    for name in sorted(os.listdir(final)) if os.path.isdir(final) else []:
        if not name.lower().endswith(".mp4") or name in covered or name == latest:
            continue
        if os.path.splitext(name)[0] + "_timing.txt" in os.listdir(cuts):
            continue
        src = os.path.join(final, name)
        others.append('<div class="clip"><div class="id">%s</div>%s<div class="meta"><span>%.1f s</span><span>%s</span></div></div>'
                      % (esc(os.path.splitext(name)[0]), video(name, thumb(name), os.path.getmtime(src)), dur(src),
                         time.strftime("%m-%d %H:%M", time.localtime(os.path.getmtime(src)))))
    if others:
        parts.append('<h3>Other takes in final\\</h3><div class="grid">%s</div>' % "".join(others))
    alt = os.path.join(final, "alt")
    if os.path.isdir(alt):
        alts = [n for n in sorted(os.listdir(alt)) if n.lower().endswith(".mp4")]
        if alts:
            parts.append('<h3>Superseded (final\\alt)</h3><p class="desc">%s</p>' % esc(", ".join(alts)))

    with open(out_html, "w", encoding="utf-8") as f:
        f.write("\n".join(parts) + "\n")
    print("dailies: %d thumbs made, %d shots, %d external, %d other; %s" % (made, len(cards), len(ext_files), len(others), out_html))
    return 0


if __name__ == "__main__":
    sys.exit(main())
