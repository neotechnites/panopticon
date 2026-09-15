r"""External footage through yt-dlp, credited as it lands.

Runs ON THE PC (tools/content/fetch.sh pushes it):

    python fetch.py <project dir> <url> <name> [--from T --to T] [--find WORD] [--cc-search QUERY]

  --find WORD      captions only (manual and auto, English) into external\src\,
                   then every cue containing WORD with its timestamp: the way
                   to find "a little after 6:50" without scrubbing the video.
  --from T --to T  only that section (mm:ss or seconds) at up to 1080p mp4:
                   external\src\<name>_<id>.mp4, and the cut re-encoded to
                   external\<name>.mp4 (libx264 crf 18, aac) so it concatenates
                   cleanly. Without them, the whole video lands in src\ and
                   nothing is cut.
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

YTDLP = [sys.executable, "-m", "yt_dlp"]


def hms(seconds):
    m, s = divmod(float(seconds), 60)
    return "%d:%04.1f" % (int(m), s)


def to_seconds(t):
    if ":" in str(t):
        parts = [float(p) for p in str(t).split(":")]
        return sum(p * 60 ** i for i, p in enumerate(reversed(parts)))
    return float(t)


def info(url):
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
    args = YTDLP + ["--no-warnings", "-f", "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080][ext=mp4]/b",
                    "--merge-output-format", "mp4", "-o", target]
    if t_from is not None:
        args += ["--download-sections", "*%s-%s" % (t_from, t_to), "--force-keyframes-at-cuts"]
    args.append(url)
    t0 = time.time()
    r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0 or not os.path.exists(target):
        raise SystemExit("download failed:\n" + r.stderr[-1500:])
    got = time.time() - t0
    cut = None
    seconds = None
    if t_from is not None:
        cut = os.path.join(ext, name + ".mp4")
        subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error", "-i", target, "-c:v", "libx264",
                        "-preset", "fast", "-crf", "18", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", cut], check=True)
        seconds = to_seconds(t_to) - to_seconds(t_from)
    entry = []
    head = "## %s.mp4  (%s)" % (name, ("%.1f s" % seconds) if seconds is not None else "full video in src\\")
    entry.append(head)
    entry.append("- URL: %s" % meta["url"])
    entry.append("- Title: %s  |  Uploader: %s  |  Upload date: %s" % (meta["title"], meta["uploader"], meta["upload_date"]))
    entry.append("- Licence: %s" % meta["license"])
    if t_from is not None:
        entry.append("- In %s, out %s of the source (%s s long); cut re-encoded libx264 crf 18 / aac." % (
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
            f.write("# External footage sources (%s)\n\nNothing here has been uploaded anywhere. Cuts are ffmpeg re-encodes of\n"
                    "local yt-dlp downloads; src\\ holds the full downloads and can be deleted.\n" % os.path.basename(project))
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
