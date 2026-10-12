"""ragdoll_vnext rough cut on the PC: edge-tts per line, the ragdoll_short clips, gif on L2, placeholder card on L4, burned captions."""
import json, os, re, subprocess, sys
SRC = r"C:\Users\ddd\Desktop\panopticon-renders\content\ragdoll_short"
OUT = r"C:\Users\ddd\Desktop\panopticon-renders\content\shorts\ragdoll_vnext"
W = os.path.join(OUT, "work"); V = os.path.join(OUT, "voice"); F = os.path.join(OUT, "final")
for d in (W, V, F): os.makedirs(d, exist_ok=True)
GIF = os.path.join(OUT, "external", "scared.gif")
LINES = [  # id, text (None = no voice), clips [(file, in)], min slot seconds
    ("l1", "The death animation in my game was really bad.", [("01_old_death_sniper_hell.mp4", 6.5)], 5.0),
    ("l2", None, [("02_old_death_grey.mp4", 1.7)], 1.8),
    ("l3", "Yeaeeeeeeeh I needed something better, but if my art didnt make it clear, I'm a programmer, not an animator", [("03_old_hell_zoomout.mp4", 0.0)], 0),
    ("l4", "Luckily my solution actually came from you guys, in an earlier short when i asked for suggestions, this guy gave me the exact solution to my problem. Ragdolls", [("04_tower_runner_shot_momentum.mp4", 0.0)], 0),
    ("l5", "these are pretty janky, but im keeping it that way, because it doesnt effect gameplay, and i think makes it more entertaining", [("05_hits_a.mp4", 0.0), ("05_freakout_mild.mp4", 0.0)], 0),
    ("l6", "Once i had this, i wanted to use it more. Now when you shove someone, they also ragdoll.", [("06a_melee4.mp4", 0.0), ("06c_faceshove_runner_pov.mp4", 0.0)], 0),
    ("l7", "And when you reach the tower, you can shove the guard out, and watch them go flying into the pit.", [("07_finale_runner_pov_cinematic.mp4", 0.0), ("07_finale_real.mp4", 0.0)], 0),
    ("l8", "Let me know what else I should add in the comments", None, 0),  # OPTIONAL: rides on the L7 picture
]
PAD = 0.25
LP = ["-threads", "4"]
def run(cmd): subprocess.run(cmd, check=True, creationflags=0x00004000)  # below normal
def dur(p): return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p]).decode().strip())

# 1. voice
words = {}
for lid, text, _, _ in LINES:
    if not text: continue
    mp3 = os.path.join(V, lid + ".mp3"); srt = os.path.join(V, lid + ".srt")
    if not os.path.exists(mp3):
        run(["edge-tts", "--voice", "en-US-AndrewNeural", "--rate=+5%", "--text", text, "--write-media", mp3, "--write-subtitles", srt])
    cues = [] if os.path.exists(srt) else [(0.0, dur(mp3), text)]
    for block in ([] if not os.path.exists(srt) else open(srt, encoding="utf-8").read().strip().split("\n\n")):
        ls = block.strip().splitlines()
        if len(ls) < 3: continue
        a, b = [sum(float(x) * m for x, m in zip(re.split("[:,.]", t.strip())[:3], (3600, 60, 1))) + int(re.split("[:,.]", t.strip())[3]) / 1000 for t in ls[1].split("-->")]
        cues.append((a, b, " ".join(ls[2:])))
    words[lid] = (dur(mp3), cues)

# 2. slots: L7 carries L8 on its picture
slots, t = [], 0.0
for lid, text, clips, minimum in LINES:
    vlen = words[lid][0] if text else 0.0
    slot = max(vlen + PAD, minimum)
    slots.append((lid, t, slot, clips)); t += slot
total = t
# merge l7+l8 picture
pic = []
for lid, start, slot, clips in slots:
    if lid == "l8": pic[-1] = (pic[-1][0], pic[-1][1], pic[-1][2] + slot, pic[-1][3]); continue
    pic.append((lid, start, slot, clips))
# l4 picture shorter than its line: the zoom-out carries on first
segs = []
for lid, start, slot, clips in pic:
    need, parts = slot, []
    if lid == "l4":
        c4 = dur(os.path.join(SRC, clips[0][0]))
        if c4 < slot:
            parts.append(("03_old_hell_zoomout.mp4", dur(os.path.join(SRC, "03_old_hell_zoomout.mp4")) - (slot - c4) - 0.05, slot - c4))
            need = c4
    for name, cin in clips:
        if need <= 0.01: break
        have = dur(os.path.join(SRC, name)) - cin - 0.05
        take = min(have, need)
        parts.append((name, cin, take)); need -= take
    if need > 0.01:
        name, cin, take = parts[-1]
        print("WARN %s short by %.2f s" % (lid, need))
    segs.append((lid, parts))
# 3. picture
lst = os.path.join(W, "parts.txt"); k = 0
with open(lst, "w") as fh:
    for lid, parts in segs:
        for name, cin, take in parts:
            out = os.path.join(W, "p%02d.mp4" % k); k += 1
            vf = "scale=1080:1920:flags=lanczos,fps=60,format=yuv420p"
            inputs = ["-ss", "%.3f" % cin, "-t", "%.3f" % take, "-i", os.path.join(SRC, name)]
            if lid == "l2" and os.path.exists(GIF):
                inputs += ["-ignore_loop", "0", "-i", GIF]
                vf = ("[0:v]scale=1080:1920,fps=60[b];[1:v]scale=760:-1,format=rgba,fade=t=in:st=0:d=%.2f:alpha=1[g];"
                      "[b][g]overlay=(W-w)/2:H*0.30:shortest=1,format=yuv420p" % (take * 0.9))
                run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"] + LP + inputs + ["-filter_complex", vf, "-t", "%.3f" % take, "-an", "-c:v", "libx264", "-crf", "14", "-preset", "veryfast", out])
            else:
                run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"] + LP + inputs + ["-vf", vf, "-an", "-c:v", "libx264", "-crf", "14", "-preset", "veryfast", out])
            fh.write("file '%s'\n" % out.replace("\\", "/"))
pic_mp4 = os.path.join(W, "picture.mp4")
run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", pic_mp4])

# 4. captions (2-3 word chunks at 0.72 of the height; a chunk ends where the next begins) and the L4 card
def ts(x): return "%d:%02d:%05.2f" % (x // 3600, (x % 3600) // 60, x % 60)
ev, card = [], None
starts = {lid: s for lid, s, _, _ in slots}
for lid, (vlen, cues) in words.items():
    for a, b, text in cues:
        ws = text.split(); n = max(1, len(ws))
        chunks = [ws[i:i + 3] for i in range(0, n, 3)]
        for j, ch in enumerate(chunks):
            ca = a + (b - a) * (j * 3) / n; cb = a + (b - a) * min(n, (j + 1) * 3) / n
            ev.append((starts[lid] + ca, starts[lid] + cb, " ".join(ch)))
        if lid == "l4" and "this guy" in text.lower() and card is None:
            idx = [w.lower().strip(",.") for w in ws].index("this")
            card = starts[lid] + a + (b - a) * idx / n
ev.sort()
ev = [(a, min(b, ev[i + 1][0]) if i + 1 < len(ev) else b, s) for i, (a, b, s) in enumerate(ev)]
ass = os.path.join(W, "captions.ass")
with open(ass, "w", encoding="utf-8") as fh:
    fh.write("[Script Info]\nScriptType: v4.00+\nPlayResX: 1080\nPlayResY: 1920\n\n[V4+ Styles]\n"
             "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
             "Style: Cap,Impact,72,&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,5,2,5,40,40,0,1\n"
             "Style: Card,Arial,44,&H00202020,&H00202020,&H00FFFFFF,&H00000000,1,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1\n"
             "Style: Ph,Arial,30,&H000000D0,&H000000D0,&H00FFFFFF,&H00000000,1,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1\n\n"
             "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
    for a, b, s in ev:
        fh.write("Dialogue: 0,%s,%s,Cap,,0,0,0,,{\\pos(540,1382)}%s\n" % (ts(a), ts(b), s.upper()))
    l4_end = starts["l5"]
    if card:
        box = "{\\pos(0,0)\\p1\\bord0\\shad0\\1c&HFFFFFF&\\1a&H10&}m 70 250 l 1010 250 l 1010 470 l 70 470{\\p0}"
        fh.write("Dialogue: 1,%s,%s,Card,,0,0,0,,%s\n" % (ts(card), ts(l4_end), box))
        fh.write("Dialogue: 2,%s,%s,Card,,0,0,0,,{\\pos(110,280)\\b1}@commenter{\\b0\\1c&H808080&\\fs32}  - 1 week ago\n" % (ts(card), ts(l4_end)))
        fh.write("Dialogue: 2,%s,%s,Card,,0,0,0,,{\\pos(110,350)}try ragdolls\n" % (ts(card), ts(l4_end)))
        fh.write("Dialogue: 2,%s,%s,Ph,,0,0,0,,{\\pos(110,420)}PLACEHOLDER: Ryan to supply the real handle + comment\n" % (ts(card), ts(l4_end)))

# 5. voice track and mux
vin, filt = [], []
for i, (lid, (vlen, _)) in enumerate(words.items()):
    vin += ["-i", os.path.join(V, lid + ".mp3")]
    filt.append("[%d:a]aresample=48000,adelay=%d|%d[a%d]" % (i, int(starts[lid] * 1000), int(starts[lid] * 1000), i))
mix = ";".join(filt) + ";" + "".join("[a%d]" % i for i in range(len(words))) + "amix=inputs=%d:normalize=0,apad,loudnorm=I=-14:TP=-1.5[a]" % len(words)
voice = os.path.join(W, "voice.wav")
run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"] + vin + ["-filter_complex", mix, "-map", "[a]", "-t", "%.3f" % total, "-ar", "48000", voice])
final = os.path.join(F, "ragdoll_vnext_v1.mp4")
os.chdir(W)
run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"] + LP + ["-i", pic_mp4, "-i", voice, "-vf", "ass=captions.ass", "-map", "0:v", "-map", "1:a", "-t", "%.3f" % total,
     "-c:v", "libx264", "-crf", "16", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", final])
json.dump({"slots": slots, "segs": segs, "card": card, "total": total}, open(os.path.join(W, "timing.json"), "w"), indent=1)
print("done", final, "%.2f s" % total, "card at", card)
for lid, parts in segs: print(lid, parts)
