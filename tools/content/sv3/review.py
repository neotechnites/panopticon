"""Gemini 2.5-pro watches the final mp4 (fps=4) against each line's NOTE verbatim and its edl window; any `no` fails the line.

    python -m sv3.review final.mp4 edl.json shots.json --out review.json      (exit 1 on a failing line, with Gemini's words)
"""
import argparse
import json
import sys
import time

DEFECTS = ["slowed_motion", "wrong_pov", "standing_still", "body_transparent", "event_not_visible", "camera_not_a_player",
           "same_as_earlier_version", "text_overlap", "desktop", "frozen_frame", "wrong_map", "beat_off_word", "sped_up"]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("edl")
    ap.add_argument("shots")
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    from google import genai
    from google.genai import types
    edl, shots = json.load(open(a.edl)), json.load(open(a.shots))
    t = 0.0
    lines = []
    for e in edl:
        s = next((x for x in shots if x["id"] == e["id"]), {})
        lines.append({"id": e["id"], "line": e["line"], "cut_start": round(t, 2), "cut_end": round(t + e["len"], 2),
                      "seat": e.get("seat"), "NOTE": s.get("note", "")})
        t += e["len"]
    c = genai.Client(http_options=types.HttpOptions(timeout=900_000))
    f = c.files.upload(file=a.video)
    while f.state.name == "PROCESSING":
        time.sleep(2)
        f = c.files.get(name=f.name)
    prompt = ("You are a strict editor reviewing a vertical gameplay short. Each entry below is one shot: where it sits in the cut\n"
              "(seconds), the player seat it was recorded from, and the creator's NOTE verbatim. For EACH shot answer `meets_note`\n"
              "yes|no (does the picture show exactly what the NOTE asks, from that seat's own eyes?) and list defects from this closed\n"
              "set: %s. The picture is real-time (1x): any slow motion, freeze or speed-up is a defect. A runner standing still is a\n"
              "defect. A camera that is not a player's eyes (tracking shot, orbit) on a pov line is camera_not_a_player. A hit body\n"
              "that turns transparent or vanishes is body_transparent. Return JSON {\"shots\":[{\"id\",\"seen\":\"what is on screen\",\n"
              "\"meets_note\":\"yes|no\",\"defects\":[...],\"words\":\"one line\"}],\"overall_defects\":[...]}.\n\nSHOTS:\n%s"
              % (", ".join(DEFECTS), json.dumps(lines, indent=1, ensure_ascii=False)))
    r = c.models.generate_content(
        model="gemini-2.5-pro",
        contents=[types.Part(file_data=types.FileData(file_uri=f.uri, mime_type=f.mime_type), video_metadata=types.VideoMetadata(fps=4)), prompt],
        config=types.GenerateContentConfig(response_mime_type="application/json", temperature=0.0))
    out = json.loads(r.text)
    failed = [s for s in out.get("shots", []) if str(s.get("meets_note", "no")).lower() != "yes" or s.get("defects")]
    out["pass"] = not failed and not out.get("overall_defects")
    json.dump(out, open(a.out, "w"), indent=1, ensure_ascii=False)
    for s in out.get("shots", []):
        print("%-4s %s %s -- %s" % (s.get("id"), s.get("meets_note"), s.get("defects"), s.get("words")))
    for d in out.get("overall_defects", []):
        print("overall: " + d)
    print("REVIEW %s -> %s" % ("PASS" if out["pass"] else "FAILED", a.out))
    return 0 if out["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
