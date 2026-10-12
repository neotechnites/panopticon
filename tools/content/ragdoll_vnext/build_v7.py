"""ragdoll_short_rough_v7 on the PC: v6 kept, L3 picture re-timed so L4's new line lands "Ragdolls" on the tower hit, comment card, optional L8."""
import json, os, subprocess
R = r"C:\Users\ddd\Desktop\panopticon-renders\content\ragdoll_short"
W = os.path.join(R, "v7work"); os.makedirs(W, exist_ok=True)
V6 = os.path.join(R, "ragdoll_short_rough_v6.mp4")
def run(c): subprocess.run(c, check=True, creationflags=0x00004000)
FF = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-threads", "4"]
ENC = ["-c:v", "libx264", "-crf", "14", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-r", "60", "-an"]
# Measured: v6 cuts 6.633 (zoom-out), 14.65 (tower), 18.95 (L5); v6's zoom-out at 12.5 s = 03 at 13.0; 04 hit frame 3.0 s;
# v6 ends on v6_07_s1 at 35.6 s, continued from the matching take v6_07_s1b at 35.65 s.
L4_AT, HIT = 12.72, 3.0
w4 = json.load(open(os.path.join(W, "l4.json"))); w3 = json.load(open(os.path.join(W, "l3.json"))); w8 = json.load(open(os.path.join(W, "l8.json")))
rag = L4_AT + [w for w in w4 if w[2] == "Ragdolls"][0][0]
this = L4_AT + [w for w in w4 if w[2] == "this"][0][0]
t04 = rag - HIT
z_len = t04 - 6.633
parts = [(V6, 0.0, 6.633), (os.path.join(R, "03_old_hell_zoomout.mp4"), 15.45 - z_len, z_len),
         (os.path.join(R, "04_tower_runner_shot_momentum.mp4"), 0.0, HIT + 1.77), (V6, 18.95, 35.238 - 18.95)]
t = 0.0; starts = []
for p in parts: starts.append(t); t += p[2]
c_at = starts[3]
L8_AT = t + 0.1
l8_pic = L8_AT + w8[-1][1] + 0.35 - t
# s1b cuts away at 37.12 s; the rest of L8 rides 07_finale_real's own guard flight (6.0 s on).
s1b = min(1.45, l8_pic)
parts.append((os.path.join(R, "v6_07_s1b.mp4"), 35.65, s1b))
if l8_pic > s1b: parts.append((os.path.join(R, "07_finale_real.mp4"), 6.0, l8_pic - s1b))
total = t + l8_pic
lst = os.path.join(W, "parts.txt")
with open(lst, "w") as fh:
    for k, (src, cin, ln) in enumerate(parts):
        out = os.path.join(W, "p%d.mp4" % k)
        run(FF + ["-ss", "%.3f" % cin, "-t", "%.3f" % ln, "-i", src, "-vf", "scale=1080:1920,fps=60"] + ENC + [out])
        fh.write("file '%s'\n" % out.replace("\\", "/"))
pic = os.path.join(W, "picture.mp4")
run(FF + ["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", pic])
# captions: v6's look (white Impact, the spoken word yellow), 3-word chunks, at 0.72 of the height
def ts(x): return "%d:%02d:%05.2f" % (x // 3600, (x % 3600) // 60, x % 60)
ev = []
def words_at(words, at, scale=None):
    out = []
    for a, b, s in words:
        if scale: a, b = scale(a), scale(b)
        out.append((at + a, at + b, s))
    return out
s3 = lambda x: 6.83 - 6.72 + (x - 0.107) * (12.48 - 6.83) / (5.43 - 0.107) + 0.107
lines = [words_at(w3, 6.72, s3), words_at(w4, L4_AT), words_at(w8, L8_AT)]
for line in lines:
    for i in range(0, len(line), 3):
        ch = line[i:i + 3]
        nxt = line[i + 3][0] if i + 3 < len(line) else ch[-1][1] + 0.3
        for j, (a, b, s) in enumerate(ch):
            end = ch[j + 1][0] if j + 1 < len(ch) else nxt
            txt = " ".join(("{\\c&H00FFFF&}%s{\\c&HFFFFFF&}" % x[2] if k == j else x[2]) for k, x in enumerate(ch))
            ev.append((a, end, txt.upper().replace("\\C&H", "\\c&H")))
ass = os.path.join(W, "v7.ass")
card_end = rag + 0.6
with open(ass, "w", encoding="utf-8") as fh:
    fh.write("[Script Info]\nScriptType: v4.00+\nPlayResX: 1080\nPlayResY: 1920\n\n[V4+ Styles]\n"
             "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
             "Style: Cap,Impact,76,&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,5,2,5,40,40,0,1\n"
             "Style: Card,Arial,44,&H00202020,&H00202020,&H00FFFFFF,&H00000000,1,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1\n"
             "Style: Ph,Arial,30,&H000000D0,&H000000D0,&H00FFFFFF,&H00000000,1,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1\n\n"
             "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
    for a, b, s in ev:
        fh.write("Dialogue: 0,%s,%s,Cap,,0,0,0,,{\\pos(540,1382)}%s\n" % (ts(a), ts(b), s))
    box = "{\\pos(0,0)\\p1\\bord0\\shad0\\1c&HFFFFFF&\\1a&H10&}m 70 250 l 1010 250 l 1010 470 l 70 470{\\p0}"
    for layer, style, body in [(1, "Card", box), (2, "Card", "{\\pos(110,280)}@commenter{\\b0\\1c&H808080&\\fs32}  - 1 week ago"),
                               (2, "Card", "{\\pos(110,350)}try ragdolls"), (2, "Ph", "{\\pos(110,420)}PLACEHOLDER: Ryan to supply the real handle + comment")]:
        fh.write("Dialogue: %d,%s,%s,%s,,0,0,0,,%s\n" % (layer, ts(this), ts(card_end), style, body))
# audio: v6's own voice where the line is v6's, the new L4 and L8 at v6's level
aud = os.path.join(W, "audio.wav")
fc = ("[0:a]atrim=0:12.6,asetpts=PTS-STARTPTS[a];"
      "[0:a]atrim=18.95:35.238,asetpts=PTS-STARTPTS,adelay=%d|%d[c];"
      "[1:a]aresample=48000,loudnorm=I=-14:TP=-1.5,adelay=%d|%d[d];"
      "[2:a]aresample=48000,loudnorm=I=-14:TP=-1.5,adelay=%d|%d[e];"
      "[a][c][d][e]amix=inputs=4:normalize=0,apad[o]") % (c_at * 1000, c_at * 1000, L4_AT * 1000, L4_AT * 1000, L8_AT * 1000, L8_AT * 1000)
run(FF + ["-i", V6, "-i", os.path.join(W, "l4.mp3"), "-i", os.path.join(W, "l8.mp3"), "-filter_complex", fc, "-map", "[o]", "-t", "%.3f" % total, "-ar", "48000", aud])
final = os.path.join(R, "ragdoll_short_rough_v7.mp4")
os.chdir(W)
run(FF + ["-i", pic, "-i", aud, "-vf", "ass=v7.ass", "-map", "0:v", "-map", "1:a", "-t", "%.3f" % total, "-c:v", "libx264", "-crf", "16", "-preset", "medium",
          "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", final])
print("done %.2f s; ragdolls %.2f, card %.2f-%.2f, L8 at %.2f, C at %.2f, zoom in %.2f" % (total, rag, this, card_end, L8_AT, c_at, 15.45 - z_len))
