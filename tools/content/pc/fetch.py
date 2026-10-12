r"""External footage through yt-dlp, credited as it lands.

Runs ON THE PC (tools/content/fetch.sh pushes it):

    python fetch.py <project dir> <url> <name> [--from T --to T] [--find WORD] [--cc-search QUERY]

  --find WORD      captions only (manual and auto, English) into external\src\,
                   then every cue containing WORD with its timestamp: the way
                   to find "a little after 6:50" without scrubbing the video.
  --from T --to T  the whole video at up to 1080p into external\src\<name>_<id>.mp4,
                   then that section cut frame-exact and LOSSLESS to
                   external\<name>.mkv (utvideo + pcm, no second lossy encode).
                   Without them, the whole video lands in src\ and nothing is cut.

yt-dlp must be 2026.08.19 or newer (Homebrew's 2026.01.29 gets HTTP 403): the
python in ~/.venvs/content when present, else this interpreter, or $CP_YTDLP (a python with yt_dlp, or a
yt-dlp executable). An older one stops the fetch; nothing falls back.
  --cc-search Q    the first 15 search results whose licence says Creative
                   Commons, printed, nothing downloaded.

Every download appends an entry to external\SOURCES.md: name, URL, title,
uploader, upload date, licence ("Standard YouTube licence (NOT Creative
Commons)" when YouTube reports none), in/out, and a credit line ready to paste.
"""
import glob
import json
import os
import re
import subprocess
import sys
import time

MIN_YTDLP = "2026.08.19"
TOOL_VERSION = "2"


def _ytdlp():
    exe = os.environ.get("CP_YTDLP")
    if not exe:
        venv = os.path.expanduser("~/.venvs/content/bin/python")
        exe = venv if os.path.exists(venv) else sys.executable
    cmd = [exe, "-m", "yt_dlp"] if os.path.basename(exe).lower().startswith("python") else [exe]
    ver = subprocess.run(cmd + ["--version"], capture_output=True, text=True).stdout.strip()
    norm = lambda v: tuple(int(x) for x in re.findall(r"\d+", v)[:3])
    if not ver or norm(ver) < norm(MIN_YTDLP):
        raise SystemExit("fetch: yt-dlp %s via %s is older than %s (2026.01.29 gets HTTP 403); "
                         "set CP_YTDLP to a current one" % (ver or "missing", exe, MIN_YTDLP))
    return cmd


YTDLP = None


def hms(seconds):
    m, s = divmod(float(seconds), 60)
    return "%d:%04.1f" % (int(m), s)


def to_seconds(t):
    if ":" in str(t):
        parts = [float(p) for p in str(t).split(":")]
        return sum(p * 60 ** i for i, p in enumerate(reversed(parts)))
    return float(t)


def info(url):
    global YTDLP
    YTDLP = YTDLP or _ytdlp()
    out = subprocess.run(YTDLP + ["--skip-download", "--no-warnings", "--print",
                                  "%(id)s\t%(title)s\t%(uploader)s\t%(upload_date)s\t%(license)s\t%(duration)s\t%(webpage_url)s", url],
                         capture_output=True, text=True, encoding="utf-8")
    if out.returncode != 0:
        raise SystemExit("yt-dlp could not read %s\n%s" % (url, out.stderr[-1500:]))
    fields = out.stdout.strip().splitlines()[-1].split("\t")
    keys = ["id", "title", "uploader", "upload_date", "license", "duration", "url"]
    d = dict(zip(keys, fields))
    lic = d.get("license", "")
    if not lic or lic == "NA":
        lic = "Standard YouTube licence (NOT Creative Commons)"
    d["license"] = lic
    date = d.get("upload_date", "")
    if re.match(r"^\d{8}$", date):
        d["upload_date"] = "%s-%s-%s" % (date[:4], date[4:6], date[6:])
    return d


def cc_search(query):
    global YTDLP
    YTDLP = YTDLP or _ytdlp()
    out = subprocess.run(YTDLP + ["--skip-download", "--no-warnings", "--flat-playlist", "--match-filter",
                                  "license~='(?i)creative commons'", "--print",
                                  "%(id)s  %(duration)s s  %(uploader)s  |  %(title)s  |  %(license)s",
                                  "ytsearch15:%s" % query], capture_output=True, text=True, encoding="utf-8")
    lines = [l for l in out.stdout.splitlines() if l.strip()]
    print("cc-search %r: %d Creative Commons result(s) of 15" % (query, len(lines)))
    for l in lines:
        print("  " + l)
    if out.returncode != 0 and not lines:
        print(out.stderr[-800:])


def _prov(out, src, meta):
    """<out>.prov.json: the download is the source; the cut adds no lossy encode."""
    import hashlib
    def sha(p):
        h = hashlib.sha1()
        with open(p, "rb") as f:
            for b in iter(lambda: f.read(1 << 22), b""):
                h.update(b)
        return h.hexdigest()
    with open(out + ".prov.json", "w", encoding="utf-8") as f:
        json.dump({"inputs": [sha(src)], "input_paths": [os.path.abspath(src)], "encoder": "utvideo yuv420p + pcm_s24le",
                   "lossless": True, "tool": "fetch.py", "version": TOOL_VERSION, "sha1": sha(out),
                   "url": meta.get("url"), "license": meta.get("license")}, f, indent=1)


def find_word(project, url, word):
    src = os.path.join(project, "external", "src")
    os.makedirs(src, exist_ok=True)
    meta = info(url)
    stem = os.path.join(src, "cc_%s" % meta["id"])
    if not glob.glob(stem + "*.vtt"):
        r = subprocess.run(YTDLP + ["--skip-download", "--no-warnings", "--write-subs", "--write-auto-subs", "--sub-lang", "en",
                                    "--sub-format", "vtt", "-o", stem, url], capture_output=True, text=True, encoding="utf-8")
        if r.returncode != 0:
            raise SystemExit("captions failed:\n" + r.stderr[-1500:])
    files = glob.glob(stem + "*.vtt")
    if not files:
        print("no English captions on %s" % url)
        return
    hits = 0
    seen = set()
    for path in files:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        cue_time = None
        for line in text.splitlines():
            m = re.match(r"^(\d\d:\d\d:\d\d\.\d{3}) --> ", line)
            if m:
                cue_time = m.group(1)
                continue
            clean = re.sub(r"<[^>]+>", "", line).strip()
            if cue_time and clean and re.search(r"\b%s\b" % re.escape(word), clean, re.I):
                # Auto captions roll the same text through consecutive cues.
                if clean in seen:
                    continue
                seen.add(clean)
                hits += 1
                print("  %s  %s" % (cue_time[3:11], clean))
    print("find %r in %s (%s): %d cue(s); captions in %s" % (word, meta["id"], meta["title"], hits, src))


def download(project, url, name, t_from, t_to):
    ext = os.path.join(project, "external")
    src = os.path.join(ext, "src")
    os.makedirs(src, exist_ok=True)
    meta = info(url)
    target = os.path.join(src, "%s_%s.mp4" % (name, meta["id"]))
    # The whole stream, never --download-sections: forcing keyframes at the cuts re-encodes it.
    args = YTDLP + ["--no-warnings", "-f", "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080][ext=mp4]/b",
                    "--merge-output-format", "mp4", "-o", target, url]
    t0 = time.time()
    if not os.path.exists(target):
        r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8")
        if r.returncode != 0 or not os.path.exists(target):
            raise SystemExit("download failed:\n" + r.stderr[-1500:])
    got = time.time() - t0
    cut = None
    seconds = None
    if t_from is not None:
        cut = os.path.join(ext, name + ".mkv")
        seconds = to_seconds(t_to) - to_seconds(t_from)
        subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error", "-ss", "%.4f" % to_seconds(t_from),
                        "-i", target, "-t", "%.4f" % seconds, "-c:v", "utvideo", "-pix_fmt", "yuv420p",
                        "-c:a", "pcm_s24le", cut], check=True)
        _prov(cut, target, meta)
    entry = []
    head = "## %s.mkv  (%s)" % (name, ("%.1f s" % seconds) if seconds is not None else "full video in src\\")
    entry.append(head)
    entry.append("- URL: %s" % meta["url"])
    entry.append("- Title: %s  |  Uploader: %s  |  Upload date: %s" % (meta["title"], meta["uploader"], meta["upload_date"]))
    entry.append("- Licence: %s" % meta["license"])
    if t_from is not None:
        entry.append("- In %s, out %s of the source (%s s long); cut lossless (utvideo / pcm)." % (
            hms(to_seconds(t_from)), hms(to_seconds(t_to)), meta.get("duration", "?")))
    else:
        entry.append("- Whole video at src\\%s; nothing cut yet." % os.path.basename(target))
    cc = "creative commons" in meta["license"].lower() and not meta["license"].startswith("Standard")
    entry.append('- Credit line: "Clip: %s, \'%s\' (%s)%s."' % (
        meta["uploader"], meta["title"], meta["url"].replace("https://www.", ""), ", CC BY" if cc else ". Used for commentary"))
    entry.append("- Fetched %s by tools/content/fetch.sh." % time.strftime("%Y-%m-%d"))
    sources = os.path.join(ext, "SOURCES.md")
    if not os.path.exists(sources):
        with open(sources, "w", encoding="utf-8") as f:
            f.write("# External footage sources (%s)\n\nNothing here has been uploaded anywhere. Cuts are lossless ffmpeg cuts of\n"
                    "local yt-dlp downloads; src\\ holds the full downloads.\n" % os.path.basename(project))
    with open(sources, "a", encoding="utf-8") as f:
        f.write("\n" + "\n".join(entry) + "\n")
    print("\n".join(entry))
    print("fetched in %.0f s: %s%s" % (got, target, (" -> " + cut) if cut else ""))


def main():
    argv = sys.argv[1:]
    project, url, name = argv[0], argv[1], argv[2]
    rest = argv[3:]
    opts = {}
    i = 0
    while i < len(rest):
        if rest[i] in ("--from", "--to", "--find", "--cc-search"):
            opts[rest[i][2:]] = rest[i + 1]
            i += 2
        else:
            raise SystemExit("unknown option %s" % rest[i])
    if "cc-search" in opts:
        cc_search(opts["cc-search"])
        return 0
    if "find" in opts:
        find_word(project, url, opts["find"])
        return 0
    if ("from" in opts) != ("to" in opts):
        raise SystemExit("--from and --to go together")
    download(project, url, name, opts.get("from"), opts.get("to"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
