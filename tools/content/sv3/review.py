"""Claude (opus, via sv3.llm) reviews the final mp4 line by line: frames at 4 fps per edl window tiled into contact sheets
(timestamp in each frame's filename; the grid legend is in the prompt) against the line's NOTE verbatim. Any `no` fails.

    python -m sv3.review final.mp4 edl.json shots.json --out review.json      (exit 1 on a failing line, with the model's words)
"""
import argparse
import glob
import json
import math
import os
import shutil
import subprocess
import sys

from sv3 import llm

DEFECTS = ["slowed_motion", "wrong_pov", "standing_still", "body_transparent", "event_not_visible", "camera_not_a_player",
           "same_as_earlier_version", "text_overlap", "desktop", "frozen_frame", "wrong_map", "beat_off_word", "sped_up"]
FPS = 4
COLS, ROWS = 4, 6                      # one sheet = 24 frames = 6 s of picture
CELL_W = 270
SCHEMA = {"type": "object", "properties": {
    "sheets_read": {"type": "array", "items": {"type": "string"}},
    "seen": {"type": "string"},
    "matches_note": {"type": "string", "enum": ["yes", "partly", "no"]},
    "defects": {"type": "array", "items": {"type": "string", "enum": DEFECTS}},
    "why": {"type": "string"}},
    "required": ["sheets_read", "seen", "matches_note", "defects", "why"], "additionalProperties": False}


def duration(video):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", video],
                       capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def extract(video, start, length, out_dir):
    """Frames at FPS in [start, start+length) named by their time in the cut, then sheets of COLS x ROWS; returns (frames, sheets)."""
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", "%.3f" % start, "-t", "%.3f" % length, "-i", video,
                    "-vf", "fps=%d,scale=%d:-2" % (FPS, CELL_W), "-q:v", "3", os.path.join(out_dir, "f%04d.jpg")], check=True)
    frames = []
    for i, f in enumerate(sorted(glob.glob(os.path.join(out_dir, "f*.jpg")))):
        t = start + i / FPS
        name = os.path.join(out_dir, "t%07.2fs.jpg" % t)
        os.rename(f, name)
        frames.append((round(t, 2), name))
    if not frames:
        return frames, []
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", "1", "-pattern_type", "glob",
                    "-i", os.path.join(out_dir, "t*.jpg"), "-vf", "tile=%dx%d" % (COLS, ROWS), "-vsync", "0", "-q:v", "3",
                    os.path.join(out_dir, "sheet%02d.jpg")], check=True)
    sheets = sorted(glob.glob(os.path.join(out_dir, "sheet*.jpg")))
    if len(sheets) != math.ceil(len(frames) / (COLS * ROWS)):
        raise SystemExit("%s: %d frames but %d sheets" % (out_dir, len(frames), len(sheets)))
    return frames, sheets


def legend(frames, sheets):
    per = COLS * ROWS
    out = []
    for k, sh in enumerate(sheets):
        cells = frames[k * per:(k + 1) * per]
        out.append("%s: %d x %d grid, row-major, %d frames, cell times (s in the cut): %s%s" % (
            os.path.basename(sh), COLS, ROWS, len(cells), ", ".join("%.2f" % t for t, _ in cells),
            "; remaining cells are empty (black)" if len(cells) < per else ""))
    return "\n".join(out)


def review_line(entry, sheets, frames):
    prompt = ("You are a strict editor reviewing ONE shot of a vertical gameplay short. The contact sheets below are every frame of\n"
              "this shot at %d fps (the picture is real-time 1x; consecutive cells are 1/%d s apart), where it sits in the cut\n"
              "(seconds), the player seat it was recorded from, and the creator's NOTE verbatim. Answer `matches_note`\n"
              "yes|partly|no (does the picture show exactly what the NOTE asks, from that seat's own eyes? partly = the subject is\n"
              "there but a requirement of the NOTE is not met) and list defects from this closed set: %s.\n"
              "Any slow motion, freeze (identical consecutive cells) or speed-up is a defect. A runner standing still is a defect.\n"
              "A camera that is not a player's eyes (tracking shot, orbit) on a pov line is camera_not_a_player. A hit body that\n"
              "turns transparent or vanishes is body_transparent. If a sheet is unreadable or missing, answer matches_note \"no\"\n"
              "and say so in `why`; never guess what you did not see. `sheets_read` = the basenames of the sheets you actually read.\n"
              "`seen` = what is on screen, in order. `why` = one line.\n\nSHOT:\n%s\n\nSHEETS:\n%s"
              % (FPS, FPS, ", ".join(DEFECTS), json.dumps(entry, indent=1, ensure_ascii=False), legend(frames, sheets)))
    return llm.ask_json(prompt, SCHEMA, images=sheets, model="opus")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("edl")
    ap.add_argument("shots")
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", help="where the frames go (default <video dir>/review_frames)")
    a = ap.parse_args(argv)
    edl, shots = json.load(open(a.edl)), json.load(open(a.shots))
    frames_root = a.frames or os.path.join(os.path.dirname(os.path.abspath(a.video)), "review_frames")
    total = duration(a.video)
    out = {"video": os.path.abspath(a.video), "duration_s": total, "shots": [], "overall_defects": []}
    if not edl:
        out["overall_defects"].append("edl is empty: nothing to review")
    t = 0.0
    for e in edl:
        s = next((x for x in shots if x["id"] == e["id"]), {})
        entry = {"id": e["id"], "line": e.get("line"), "cut_start": round(t, 2), "cut_end": round(t + e["len"], 2),
                 "seat": e.get("seat"), "NOTE": s.get("note", "")}
        start = t
        t += e["len"]
        rec = dict(entry, seen="", matches_note="no", defects=[], why="", sheets=[], frames=0)
        if not s:
            rec["why"] = "edl entry %s has no shot in shots.json" % e["id"]
        elif not s.get("note"):
            rec["why"] = "shot %s has an empty note: nothing to judge against" % e["id"]
        elif t > total + 0.05:
            rec["why"] = "window %.2f-%.2f runs past the video (%.2f s)" % (start, t, total)
        else:
            frames, sheets = extract(a.video, start, e["len"], os.path.join(frames_root, e["id"]))
            rec["sheets"], rec["frames"] = [os.path.relpath(x, frames_root) for x in sheets], len(frames)
            if not sheets:
                rec["why"] = "no frames came out of the window %.2f-%.2f" % (start, t)
            else:
                v = review_line(entry, sheets, frames)
                rec.update(seen=v["seen"], matches_note=v["matches_note"], defects=v["defects"], why=v["why"])
                want = {os.path.basename(x) for x in sheets}
                got = {os.path.basename(x) for x in v["sheets_read"]}
                if got != want:
                    rec["matches_note"] = "no"
                    rec["why"] = "reviewer read %s of %s; %s" % (sorted(got), sorted(want), v["why"])
        out["shots"].append(rec)
        print("%-4s %-6s %s -- %s" % (rec["id"], rec["matches_note"], rec["defects"], rec["why"]))
    missing = [x["id"] for x in shots if x["id"] not in {e["id"] for e in edl}]
    if missing:
        out["overall_defects"].append("shots without an edl entry (not in the cut, not reviewed): %s" % missing)
    failed = [r for r in out["shots"] if r["matches_note"] == "no" or r["defects"]]
    out["pass"] = bool(out["shots"]) and not failed and not out["overall_defects"]
    json.dump(out, open(a.out, "w"), indent=1, ensure_ascii=False)
    for d in out["overall_defects"]:
        print("overall: " + d)
    print("REVIEW %s -> %s" % ("PASS" if out["pass"] else "FAILED", a.out))
    return 0 if out["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
