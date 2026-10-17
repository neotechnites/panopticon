"""Film every take a plan asks for on the PC and grow the tape pool.

    python -m sv3.capture plan.json --pool DIR [--dry]

plan.json (sv3/plan.py): {"matches": [{"id", "map", "opening", "players", "seed", "seconds",
"seats": ["guard", "runner:1"], "old", "kill", "cam", "seat_intent", "reuse"}]}. sync.sh runs
once; per take: lib.sh pc_lock_take (lease 3x the expected seconds), pc_rough at 810x1440 real
time (utvideo, white sync frames), then the logs come to the Mac pool; the video stays on the PC.
Run 1 of a match records the tape (--record), every further seat replays it (--tape).
A match may carry "run_clip_args": those exact run_clip flags are used instead (today's smoke
against the pre-WP1 recorder); the seat still names the files.
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CONTENT = os.path.dirname(HERE)
LIB = os.path.join(CONTENT, "lib.sh")
PC_POOL = "C:/Users/ddd/Desktop/panopticon-renders/content/_tapes"
LOAD_S, GATE_S = 9.0, 25.0          # Godot load; sync detection, rename, pull
CAPTURE_MAX_S = 25 * 60             # design 7.7: a plan over 25 min of capture is refused
SIZE = "810x1440"


def seat_file(seat):
    return seat.replace(":", "_")


def pc_host():
    return os.environ.get("PC_HOST", "ddd@100.114.41.16"), os.path.expanduser(os.environ.get("PC_KEY", "~/.ssh/panopticon_pc_ed25519"))


def match_key(m):
    return "%s_%s_%s" % (m["map"], m.get("opening", "seat"), m["seed"])


def run_clip_args(m, seat, first, tape_pc, log_pc):
    """The recorder's flags for one seat of a match (design 1 and 7)."""
    if m.get("run_clip_args"):
        if "--write-movie" in m["run_clip_args"] or "--fixed-fps" in m["run_clip_args"]:
            raise SystemExit("capture refuses: a take is filmed in real time, never Movie Maker (run_clip_args)")
        return m["run_clip_args"]                  # verbatim: the pre-WP1 recorder rejects --log
    a = ["--match", "--map=%s" % m["map"], "--bots=%d" % int(m.get("players", 4)), "--seed=%d" % int(m["seed"]),
         "--opening=%s" % m.get("opening", "seat"), "--seat=%s" % seat, "--seconds=%s" % m.get("seconds", 45),
         "--shimmer=0", "--hud=%s" % ("crosshair" if seat == "guard" else "none"), "--sync=90"]
    if m.get("old"):
        a.append("--old=1")
    for k in ("kill", "cam", "look"):
        if m.get(k):
            a.append("--%s=%s" % (k, m[k]))
    if m.get("seat_intent"):
        a.append("--seat-intent=%s" % m["seat_intent"])
    if m.get("intent"):                     # the plan's scripted players: body=step,step;body=...
        a.append("--intent=%s" % m["intent"])
    a.append(("--record=%s" if first else "--tape=%s") % tape_pc)
    return " ".join(a) + " --log=%s" % log_pc


def take(m, seat, first, pool_mac, dry):
    key = match_key(m)
    sf = seat_file(seat)
    pc_dir = "%s/%s" % (PC_POOL, key)
    tape_pc = "%s/tape.json" % pc_dir
    log_pc = "%s/%s" % (pc_dir, sf)                       # --log dir; its files are renamed <seat>.* after
    raw = "%s\\%s.mkv" % (pc_dir.replace("/", "\\"), sf)
    glog = "%s\\%s.log" % (pc_dir.replace("/", "\\"), sf)
    args = run_clip_args(m, seat, first, tape_pc, log_pc)
    seconds = float(m.get("seconds", 45))
    expected = int(LOAD_S + seconds + GATE_S)
    what = "sv3 take %s %s" % (key, sf)
    print("take %s/%s: run_clip %s" % (key, sf, args), flush=True)
    if dry:
        return
    pc_win = pc_dir.replace("/", "\\")
    script = r"""
set -euo pipefail
source "$LIB"
SIZE="$SIZE"
pc_lock_take "$WHAT" "$EXPECTED"
pc <<EOF
New-Item -ItemType Directory -Force -Path '%(dir)s' | Out-Null
EOF
t0=$(now_ms)
pc_rough "--script res://tools/capture/run_clip.gd -- $ARGS" '%(glog)s' '%(raw)s' | sed 's/^/  | /'
echo "  godot+record $(since "$t0")"
pc <<EOF
\$d = '%(dir)s\%(sf)s'
if (Test-Path \$d) {
}
Get-ChildItem '%(dir)s' -File | ForEach-Object { \$_.Name + ' ' + \$_.Length }
# A take the recorder refused still records a screen: its refusal lines and the length decide, not the sync frame.
\$bad = Select-String -Path '%(glog)s' -Pattern '^Unknown |Harness: |is filmed with --pov|^No such ' | Select-Object -First 2
if (\$bad) { Write-Output ('TAKE FAILED: Godot said: ' + ((\$bad | ForEach-Object Line) -join ' | ')); exit 4 }
\$ci = [Globalization.CultureInfo]::InvariantCulture
\$dur = [double]::Parse((ffprobe -v error -show_entries format=duration -of csv=p=0 '%(raw)s'), \$ci)
\$t0 = [double]::Parse((Get-Content '%(raw)s.sync' -Raw).Trim(), \$ci)
if ((\$dur - \$t0) -lt (%(seconds).2f - 0.5)) { Write-Output ('TAKE FAILED: ' + (\$dur - \$t0).ToString('0.00', \$ci) + ' s recorded after t=0, the take asked for %(seconds).2f'); exit 4 }
Write-Output ('take length ' + (\$dur - \$t0).ToString('0.00', \$ci) + ' s after t=0')
EOF
""" % {"dir": pc_win, "sf": sf, "glog": glog, "raw": raw, "seconds": seconds}
    env = dict(os.environ, LIB=LIB, SIZE=SIZE, WHAT=what, EXPECTED=str(expected), ARGS=args)
    t0 = time.time()
    try:
        r = subprocess.run(["bash", "-c", script], env=env, timeout=expected * 3 + 90)
    except subprocess.TimeoutExpired:
        raise SystemExit("capture: take %s/%s ran past %d s; the PC runner stops its own Godot at 600 s; log %s"
                         % (key, sf, expected * 3 + 90, glog))
    if r.returncode != 0:
        raise SystemExit("capture: take %s/%s failed (exit %d); Godot log %s" % (key, sf, r.returncode, glog))
    t_rec = time.time() - t0
    # The logs come to the Mac; the video stays on the PC (the edl names the PC path).
    t0 = time.time()
    mac_dir = os.path.join(pool_mac, key)
    os.makedirs(mac_dir, exist_ok=True)
    host, keyfile = pc_host()
    # The recorder writes <log dir>/{events.jsonl,vis.jsonl,take.json}; they land here as <seat>.<file>.
    want = ["%s.events.jsonl" % sf, "%s.vis.jsonl" % sf, "%s.take.json" % sf, "%s.mkv.sync" % sf, "%s.log" % sf, "tape.json"]
    remote = {"%s.%s" % (sf, f): "%s/%s" % (sf, f) for f in ("events.jsonl", "vis.jsonl", "take.json")}
    got = []
    for name in want:
        try:
            r = subprocess.run(["scp", "-q", "-i", keyfile, "%s:%s/%s" % (host, pc_dir, remote.get(name, name)), os.path.join(mac_dir, name)],
                               capture_output=True, text=True, timeout=120)
        except subprocess.TimeoutExpired:
            raise SystemExit("capture: pulling %s/%s hung for 120 s" % (key, name))
        if r.returncode == 0:
            got.append(name)
    if "%s.mkv.sync" % sf not in got:
        raise SystemExit("capture: take %s/%s has no .sync (no white frames found); Godot log %s" % (key, sf, glog))
    missing = [n for n in want if n not in got]
    with open(os.path.join(mac_dir, "%s.pc.json" % sf), "w", encoding="utf-8") as f:
        json.dump({"video": raw, "pool": pc_win, "seat": seat, "args": args, "size": SIZE,
                   "sync": open(os.path.join(mac_dir, "%s.mkv.sync" % sf)).read().strip(), "missing": missing}, f, indent=1)
    print("take %s/%s: record %.0f s, pull %.0f s%s" % (key, sf, t_rec, time.time() - t0,
                                                     ("; not written by the recorder: " + ", ".join(missing)) if missing else ""), flush=True)


def main(argv):
    if len(argv) < 3 or argv[1] != "--pool" and "--pool" not in argv:
        raise SystemExit(__doc__)
    plan_path = argv[0]
    pool = os.path.expanduser(argv[argv.index("--pool") + 1])
    dry = "--dry" in argv
    with open(plan_path, encoding="utf-8") as f:
        plan = json.load(f)
    matches = plan["matches"] if isinstance(plan, dict) else plan
    todo = [m for m in matches if m.get("seats") and not m.get("reuse")]
    if not todo:
        print("capture: nothing to film (every line reuses the pool)")
        return 0
    budget = sum((LOAD_S + float(m.get("seconds", 45)) + GATE_S) for m in todo for _ in m["seats"])
    print("capture: %d take(s), about %.1f min" % (sum(len(m["seats"]) for m in todo), budget / 60.0), flush=True)
    if budget > CAPTURE_MAX_S:
        raise SystemExit("capture refuses: %.1f min of capture is over the 25 min cap (design 7.7); shorten the plan" % (budget / 60.0))
    if dry:
        for m in todo:
            for i, seat in enumerate(m["seats"]):
                take(m, seat, i == 0, pool, True)
        return 0
    t_all = time.time()
    t0 = time.time()
    r = subprocess.run(["bash", os.path.join(CONTENT, "sync.sh")])
    if r.returncode != 0:
        raise SystemExit("capture: sync.sh failed (exit %d)" % r.returncode)
    print("sync: %.0f s" % (time.time() - t0), flush=True)
    for m in todo:
        for i, seat in enumerate(m["seats"]):
            t0 = time.time()
            take(m, seat, i == 0, pool, False)
            print("take %s/%s: %.0f s wall" % (match_key(m), seat_file(seat), time.time() - t0), flush=True)
    print("capture: %d take(s) in %.0f s" % (sum(len(m["seats"]) for m in todo), time.time() - t_all))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
