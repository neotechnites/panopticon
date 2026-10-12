r"""A Resolve timeline from a render: builds\<stamp>\<tag>.fcpxml with every file hard-linked beside it.

    python -m cp.timeline <project dir> [--tag NAME] [--mac /Users/name/Movies/<project>]

V1: lines\L#.mkv back to back from edl.json (one clip per script line). A1: each line's
voice wav at its line's start. One marker per line ("L4 Luckily my solution actually").
Music lanes from plan.json `music_beds` [{path, start_line, end_line, offset_s, alts}]:
the main bed on lane -2 at -18 dB, ducked 12 dB over keep-audio lines; alts muted on
-3/-4. Every referenced file is hard-linked into builds\<stamp>\media\ under a new name,
so each import brings new paths and Resolve never shows "media offline" (decision 363).
A build folder is never reused. Validates V1 coverage and that each wav sits inside its line.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import xml.dom.minidom
from xml.sax.saxutils import quoteattr

FPS = 60
TB = FPS * 100
BED_DB, DUCK_DB, DUCK_RELEASE_S = -18, 12, 0.3


def rt(frames):
    return "%d/%ds" % (frames * 100, TB)


def f(sec):
    return int(round(sec * FPS))


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                          "stream=codec_type,sample_rate,channels:format=duration", "-of", "json", path],
                         capture_output=True, text=True, check=True).stdout
    d = json.loads(out)
    a = next((s for s in d.get("streams", []) if s["codec_type"] == "audio"), None)
    return {"dur": float(d["format"]["duration"]), "rate": int(a["sample_rate"]) if a else None,
            "ch": int(a["channels"]) if a else None}


def url(path):
    p = path.replace("\\", "/")
    return "file:///" + p.lstrip("/") if not p.startswith("/") else "file://" + p


def build(project, tag=None, mac=None):
    project = os.path.abspath(project)
    with open(os.path.join(project, "edl.json"), encoding="utf-8") as fh:
        edl = json.load(fh)
    with open(os.path.join(project, "plan.json"), encoding="utf-8") as fh:
        plan = json.load(fh)
    tag = tag or plan["name"]
    stamp = time.strftime("%Y%m%d_%H%M%S")
    out_dir = os.path.join(project, "builds", stamp)
    while os.path.exists(out_dir):
        stamp += "b"
        out_dir = os.path.join(project, "builds", stamp)
    media = os.path.join(out_dir, "media")
    os.makedirs(media)
    linked = {}

    def link(path):
        if path not in linked:
            dst = os.path.join(media, "%03d_%s" % (len(linked) + 1, os.path.basename(path)))
            try:
                os.link(path, dst)
            except OSError:
                shutil.copy2(path, dst)
            linked[path] = dst
        return linked[path]

    W, H = edl["w"], edl["h"]
    keep = {ln["id"] for ln in plan["lines"] if "keep-audio" in (ln.get("flags") or [])}
    assets, spine, problems = [], [], []
    by_id, starts = {}, {}
    pos, aid = 0, 0
    for ln in edl["lines"]:
        clip = link(os.path.join(project, ln["clip"]))
        frames = f(ln["dur"])
        if f(ln["start"]) != pos:
            problems.append("%s starts at frame %d, V1 is at %d" % (ln["id"], f(ln["start"]), pos))
        aid += 1
        vid = "v%d" % aid
        assets.append('    <asset id="%s" name=%s src=%s start="0s" duration="%s" hasVideo="1" hasAudio="0" '
                      'format="r_fmt" videoSources="1" />' % (vid, quoteattr(os.path.basename(clip)),
                                                               quoteattr(url(clip)), rt(frames)))
        inner = []
        if ln.get("wav"):
            wav = link(os.path.join(project, ln["wav"]))
            pw = probe(wav)
            wf = min(frames, int(pw["dur"] * FPS) + 1)
            if pw["dur"] > ln["dur"] + 1e-3:
                problems.append("%s wav %.3f s is longer than its line %.3f s" % (ln["id"], pw["dur"], ln["dur"]))
            aid += 1
            wid = "a%d" % aid
            assets.append('    <asset id="%s" name=%s src=%s start="0s" duration="%s" hasVideo="0" hasAudio="1" '
                          'audioSources="1" audioChannels="%d" audioRate="%d" />' % (
                              wid, quoteattr(os.path.basename(wav)), quoteattr(url(wav)),
                              rt(int(pw["dur"] * FPS) + 1), pw["ch"], pw["rate"]))
            inner.append('              <asset-clip ref="%s" lane="-1" offset="0/%ds" name=%s start="0s" '
                         'duration="%s" />' % (wid, TB, quoteattr(ln["id"] + " voice"), rt(wf)))
        text = next((x.get("text", "") for x in plan["lines"] if x["id"] == ln["id"]), "")
        inner.append('              <marker start="0/%ds" duration="100/%ds" value=%s />' % (
            TB, TB, quoteattr(("%s %s" % (ln["id"], " ".join(text.split()[:4]))).strip())))
        entry = {"id": ln["id"], "ref": vid, "offset": pos, "frames": frames, "inner": inner}
        by_id[ln["id"]] = entry
        starts[pos] = ln["id"]
        spine.append(entry)
        pos += frames
    total = pos
    if abs(total - f(edl["total"])) > 1:
        problems.append("V1 covers %d frames, edl says %d" % (total, f(edl["total"])))

    line_pos = {e["id"]: (e["offset"], e["frames"]) for e in spine}
    for bed in plan.get("music_beds") or []:
        s0 = line_pos[bed["start_line"]][0]
        s1 = sum(line_pos[bed["end_line"]])
        ducks = [(line_pos[k][0] - s0, sum(line_pos[k]) - s0) for k in keep if k in line_pos
                 and s0 <= line_pos[k][0] < s1]
        for path, lane, muted in [(bed["path"], -2, False)] + [(p, l, True) for p, l in zip(bed.get("alts", []),
                                                                                             (-3, -4))]:
            src = path if os.path.isabs(path) else os.path.join(project, path)
            if not os.path.exists(src):
                problems.append("music %s missing" % path)
                continue
            m = link(src)
            pm = probe(m)
            off = f(float(bed.get("offset_s", 0)))
            length = min(s1 - s0, int(pm["dur"] * FPS) - off)
            aid += 1
            mid = "m%d" % aid
            assets.append('    <asset id="%s" name=%s src=%s start="0s" duration="%s" hasVideo="0" hasAudio="1" '
                          'audioSources="1" audioChannels="%d" audioRate="%d" />' % (
                              mid, quoteattr(os.path.basename(m)), quoteattr(url(m)), rt(int(pm["dur"] * FPS)),
                              pm["ch"], pm["rate"]))
            name = ("ALT: " if muted else "") + os.path.splitext(os.path.basename(path))[0]
            head = '              <asset-clip ref="%s" lane="%d" offset="0/%ds" name=%s start="%s" duration="%s"%s>' % (
                mid, lane, TB, quoteattr(name), rt(off), rt(length), ' enabled="0"' if muted else "")
            if muted:
                body = ""
            elif not ducks:
                body = '\n                <adjust-volume amount="%ddB" />' % BED_DB
            else:
                kfs = []
                for d0, d1 in sorted(ducks):
                    kfs += [(off + d0, BED_DB), (off + d1, BED_DB - DUCK_DB), (off + d1 + f(DUCK_RELEASE_S), BED_DB)]
                body = ("\n                <adjust-volume>\n                  <param name=\"amount\">\n"
                        "                    <keyframeAnimation>\n" +
                        "\n".join('                      <keyframe time="%s" value="%ddB" />' % (rt(t), v)
                                  for t, v in kfs) +
                        "\n                    </keyframeAnimation>\n                  </param>\n"
                        "                </adjust-volume>")
            by_id[starts[s0]]["inner"].append(head + body + "\n              </asset-clip>")
    if problems:
        raise SystemExit("timeline: %d problem(s), nothing written\n  " % len(problems) + "\n  ".join(problems))

    clips = "\n".join('            <asset-clip ref="%s" offset="%s" name=%s start="0/%ds" duration="%s">\n%s\n'
                      '            </asset-clip>' % (e["ref"], rt(e["offset"]), quoteattr(e["id"]), TB,
                                                     rt(e["frames"]), "\n".join(e["inner"])) for e in spine)
    name = "%s %s" % (tag, stamp)
    doc = "\n".join([
        '<?xml version="1.0" encoding="UTF-8"?>', "<!DOCTYPE fcpxml>", '<fcpxml version="1.9">', "  <resources>",
        '    <format id="r_fmt" name="FFVideoFormat%dx%dp60" frameDuration="100/%ds" width="%d" height="%d" />'
        % (W, H, TB, W, H),
        *assets, "  </resources>", "  <library>", "    <event name=%s>" % quoteattr(name),
        "      <project name=%s>" % quoteattr(name),
        '        <sequence format="r_fmt" duration="%s" tcStart="0s" tcFormat="NDF" audioLayout="stereo" '
        'audioRate="48k">' % rt(total), "          <spine>", clips, "          </spine>", "        </sequence>",
        "      </project>", "    </event>", "  </library>", "</fcpxml>", ""])
    xml.dom.minidom.parseString(doc.encode("utf-8"))
    out = os.path.join(out_dir, "%s_%s.fcpxml" % (tag, stamp))
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(doc)
    print("timeline: %s  V1 %d clips, %d media files, %.2f s" % (out, len(spine), len(linked), total / FPS))
    if mac:
        mac_doc = doc
        for dst in linked.values():
            mac_doc = mac_doc.replace(quoteattr(url(dst)), quoteattr("file://%s/%s/media/%s" % (
                mac.rstrip("/"), stamp, os.path.basename(dst))))
        out_mac = out.replace(".fcpxml", "_mac.fcpxml")
        with open(out_mac, "w", encoding="utf-8") as fh:
            fh.write(mac_doc)
        print("timeline: %s (copy builds/%s/ to %s/%s/)" % (out_mac, stamp, mac, stamp))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--tag")
    ap.add_argument("--mac")
    a = ap.parse_args()
    build(a.project, a.tag, a.mac)
    return 0


if __name__ == "__main__":
    sys.exit(main())
