"""Film one pill-era seat (commit 00f0661d) on the PC through the sv3 capture path.

    python -m sv3.pill --seat=guard|runner:K --seed=S --seconds=T --log=DIR --pool DIR [--keep] [--check]

A scrubbed worktree of the pill build is made at C:\\dev\\worktrees\\pill_<seed> (decision 362: no
CLAUDE.md, no root *.md, no addons/, no tools/ but tools/capture/pill_match.gd), pill_match.gd runs
through lib.sh pc_rough (real time, 810x1440, white sync frames, utvideo) under one pc_lock_take,
and <seat>.events.jsonl / .vis.jsonl / .take.json / .mkv.sync / .pc.json land in <pool>/pill_seat_<seed>/
(take.json too, so sv3.search reads the pool unchanged). --log DIR gets a copy. The worktree is
removed after the take unless --keep. --check compares the pool's guard and runner logs of that seed.
"""
import json
import os
import subprocess
import sys
import time

from sv3.capture import GATE_S, LOAD_S, PC_POOL, SIZE, pc_host, seat_file

HERE = os.path.dirname(os.path.abspath(__file__))
CONTENT = os.path.dirname(HERE)
LIB = os.path.join(CONTENT, "lib.sh")
REPO = os.path.dirname(os.path.dirname(CONTENT))
PILL_COMMIT = "00f0661d"
PILL_SCRIPT = os.path.normpath(os.path.join(CONTENT, "..", "capture", "pill_match.gd"))
PC_BASE = "C:/dev/verify"            # the scratch repo the worktree hangs off; never C:/dev/panopticon's checkout


def arg(argv, name, default=None):
    for a in argv:
        if a.startswith("--%s=" % name):
            return a.split("=", 1)[1]
    return default


def pc_worktree(seed):
    return "C:/dev/worktrees/pill_%d" % seed


def make_worktree(seed):
    """Push the pill commit to the PC and check out a scrubbed worktree of it (decision 362)."""
    wt = pc_worktree(seed)
    r = subprocess.run(["git", "-C", REPO, "push", "-q", "pc", "%s:refs/heads/pill-incoming" % PILL_COMMIT, "-f"])
    if r.returncode != 0:
        raise SystemExit("pill: pushing %s to the PC failed" % PILL_COMMIT)
    script = r"""
set -euo pipefail
source "$LIB"
pc <<EOF
\$ErrorActionPreference = 'Stop'
if (Test-Path '%(wt)s') { git -C %(base)s worktree remove --force '%(wt)s' 2>\$null; if (Test-Path '%(wt)s') { Remove-Item -Recurse -Force '%(wt)s' } }
git -C %(base)s worktree prune
New-Item -ItemType Directory -Force -Path (Split-Path '%(wt)s') | Out-Null
git -C %(base)s worktree add -q -f --detach '%(wt)s' %(commit)s
Get-ChildItem '%(wt)s' -File -Filter '*.md' | Remove-Item -Force
Remove-Item -LiteralPath '%(wt)s/CLAUDE.md', '%(wt)s/addons', '%(wt)s/tools' -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path '%(wt)s/tools/capture' | Out-Null
Write-Output ('pill worktree ' + (git -C '%(wt)s' log --oneline -1))
EOF
pc_push "$SCRIPT" '%(wt)s/tools/capture/pill_match.gd'
pc <<EOF
\$left = Get-ChildItem '%(wt)s' -Recurse -File -Include 'CLAUDE.md','*.md' | Where-Object { \$_.FullName -notlike '*\.git\*' } | Select-Object -First 5
if (\$left) { Write-Output ('scrub left markdown: ' + ((\$left | ForEach-Object FullName) -join ' ')) }
cmd /c "C:\tools\godot\godot.exe --headless --import --path %(wtw)s > %(wtw)s.import.txt 2>&1"
\$e = (Select-String -Path '%(wtw)s.import.txt' -Pattern 'ERROR' | Measure-Object -Line).Lines
Write-Output ('imported; import errors: ' + \$e)
EOF
""" % {"base": PC_BASE, "wt": wt, "wtw": wt.replace("/", "\\"), "commit": PILL_COMMIT}
    env = dict(os.environ, LIB=LIB, SCRIPT=PILL_SCRIPT)
    r = subprocess.run(["bash", "-c", script], env=env, timeout=900)
    if r.returncode != 0:
        raise SystemExit("pill: making the PC worktree failed (exit %d)" % r.returncode)
    return wt


def remove_worktree(seed):
    script = r"""
source "$LIB"
pc <<EOF
git -C %(base)s worktree remove --force '%(wt)s' 2>\$null
if (Test-Path '%(wt)s') { Remove-Item -Recurse -Force '%(wt)s' }
Remove-Item '%(wt)s.import.txt' -ErrorAction SilentlyContinue
git -C %(base)s worktree prune
Write-Output 'pill worktree removed'
EOF
""" % {"base": PC_BASE, "wt": pc_worktree(seed)}
    subprocess.run(["bash", "-c", script], env=dict(os.environ, LIB=LIB), timeout=300)


def take(seat, seed, seconds, wt, pool_mac, log_mac):
    key = "pill_seat_%d" % seed
    sf = seat_file(seat)
    pc_dir = "%s/%s" % (PC_POOL, key)
    pc_win = pc_dir.replace("/", "\\")
    log_pc = "%s/%s" % (pc_dir, sf)
    raw = "%s\\%s.mkv" % (pc_win, sf)
    glog = "%s\\%s.log" % (pc_win, sf)
    args = "--seat=%s --seed=%d --seconds=%s --opening=seat --sync=90 --log=%s" % (seat, seed, seconds, log_pc)
    expected = int(LOAD_S + seconds + GATE_S)
    print("take %s/%s: pill_match %s" % (key, sf, args), flush=True)
    script = r"""
set -euo pipefail
source "$LIB"
SIZE="$SIZE"
PC_PROJECT='%(wt)s'
pc_lock_take "$WHAT" "$EXPECTED"
pc <<EOF
New-Item -ItemType Directory -Force -Path '%(dir)s' | Out-Null
Remove-Item -LiteralPath '%(dir)s\%(sf)s' -Recurse -Force -ErrorAction SilentlyContinue
EOF
t0=$(now_ms)
pc_rough "--script res://tools/capture/pill_match.gd -- $ARGS" '%(glog)s' '%(raw)s' | sed 's/^/  | /'
echo "  godot+record $(since "$t0")"
pc <<EOF
\$bad = Select-String -Path '%(glog)s' -Pattern '^pill_match|SCRIPT ERROR|^Unknown ' | Select-Object -First 2
if (\$bad) { Write-Output ('TAKE FAILED: Godot said: ' + ((\$bad | ForEach-Object Line) -join ' | ')); exit 4 }
\$ci = [Globalization.CultureInfo]::InvariantCulture
\$dur = [double]::Parse((ffprobe -v error -show_entries format=duration -of csv=p=0 '%(raw)s'), \$ci)
\$t0 = [double]::Parse((Get-Content '%(raw)s.sync' -Raw).Trim(), \$ci)
if ((\$dur - \$t0) -lt (%(seconds).2f - 0.5)) { Write-Output ('TAKE FAILED: ' + (\$dur - \$t0).ToString('0.00', \$ci) + ' s recorded after t=0, the take asked for %(seconds).2f'); exit 4 }
Write-Output ('take length ' + (\$dur - \$t0).ToString('0.00', \$ci) + ' s after t=0')
EOF
""" % {"wt": wt.replace("/", "\\"), "dir": pc_win, "sf": sf, "glog": glog, "raw": raw, "seconds": float(seconds)}
    env = dict(os.environ, LIB=LIB, SIZE=SIZE, WHAT="sv3 pill take %s %s" % (key, sf), EXPECTED=str(expected), ARGS=args)
    t_rec = time.time()
    try:
        r = subprocess.run(["bash", "-c", script], env=env, timeout=expected * 3 + 90)
    except subprocess.TimeoutExpired:
        raise SystemExit("pill: take %s/%s ran past %d s; Godot log %s" % (key, sf, expected * 3 + 90, glog))
    if r.returncode != 0:
        raise SystemExit("pill: take %s/%s failed (exit %d); Godot log %s" % (key, sf, r.returncode, glog))
    t_rec = time.time() - t_rec
    mac_dir = os.path.join(pool_mac, key)
    os.makedirs(mac_dir, exist_ok=True)
    host, keyfile = pc_host()
    want = ["%s.events.jsonl" % sf, "%s.vis.jsonl" % sf, "%s.take.json" % sf, "%s.mkv.sync" % sf, "%s.log" % sf]
    remote = {"%s.%s" % (sf, f): "%s/%s" % (sf, f) for f in ("events.jsonl", "vis.jsonl", "take.json")}
    got = []
    for name in want:
        r = subprocess.run(["scp", "-q", "-i", keyfile, "%s:%s/%s" % (host, pc_dir, remote.get(name, name)), os.path.join(mac_dir, name)],
                           capture_output=True, text=True, timeout=120)
        if r.returncode == 0:
            got.append(name)
    if "%s.mkv.sync" % sf not in got:
        raise SystemExit("pill: take %s/%s has no .sync (no white frames found); Godot log %s" % (key, sf, glog))
    missing = [n for n in want if n not in got]
    sync = open(os.path.join(mac_dir, "%s.mkv.sync" % sf)).read().strip()
    with open(os.path.join(mac_dir, "%s.pc.json" % sf), "w", encoding="utf-8") as f:
        json.dump({"video": raw, "pool": pc_win, "seat": seat, "args": args, "size": SIZE, "commit": PILL_COMMIT,
                   "sync": sync, "missing": missing}, f, indent=1)
    # sv3.predicates reads one take.json per tape dir (and the seat's own <seat>.take.json stays beside it).
    tk = os.path.join(mac_dir, "%s.take.json" % sf)
    if os.path.isfile(tk):
        t = json.load(open(tk))
        t["files"] = dict(t.get("files") or {}, **{sf: raw})
        json.dump(t, open(tk, "w"), indent=1)
        shared = os.path.join(mac_dir, "take.json")
        all_files = (json.load(open(shared)).get("files") if os.path.isfile(shared) else {}) or {}
        all_files[sf] = raw
        json.dump(dict(t, files=all_files), open(shared, "w"), indent=1)
    if log_mac:
        os.makedirs(log_mac, exist_ok=True)
        for name in got + ["%s.pc.json" % sf]:
            subprocess.run(["cp", os.path.join(mac_dir, name), os.path.join(log_mac, name)])
    counts = {}
    for line in open(os.path.join(mac_dir, "%s.events.jsonl" % sf)) if "%s.events.jsonl" % sf in got else []:
        e = json.loads(line)
        counts[e["ev"]] = counts.get(e["ev"], 0) + 1
    print("take %s/%s: record %.0f s; events %s%s" % (key, sf, t_rec, json.dumps(counts, sort_keys=True),
                                                   ("; not written: " + ", ".join(missing)) if missing else ""), flush=True)
    return mac_dir


def check(pool_mac, seed):
    """Do the guard and runner logs of one seed describe one match? Same events in order, t within 0.05 s."""
    d = os.path.join(pool_mac, "pill_seat_%d" % seed)
    logs = {}
    for f in sorted(os.listdir(d)):
        if f.endswith(".events.jsonl"):
            logs[f[:-len(".events.jsonl")]] = [json.loads(l) for l in open(os.path.join(d, f)) if l.strip()]
    if len(logs) < 2:
        print("check: only %s in %s" % (list(logs), d))
        return 1
    names = sorted(logs)
    a, b = logs[names[0]], logs[names[1]]
    strip = lambda e: {k: v for k, v in e.items() if k != "t"}
    diverge = None
    for i, (x, y) in enumerate(zip(a, b)):
        if strip(x) != strip(y) or abs(x["t"] - y["t"]) > 0.05:
            diverge = (i, x, y)
            break
    if diverge is None and len(a) != len(b):
        diverge = (min(len(a), len(b)), a[len(b):len(b) + 1], b[len(a):len(a) + 1])
    for n in names:
        c = {}
        for e in logs[n]:
            c[e["ev"]] = c.get(e["ev"], 0) + 1
        print("%s: %d events %s" % (n, len(logs[n]), json.dumps(c, sort_keys=True)))
    if diverge:
        print("DIVERGE at event %d: %s vs %s" % diverge)
        return 2
    print("AGREE: %d events, same order, t within 0.05 s" % len(a))
    return 0


def main(argv):
    if "--pool" not in argv:
        raise SystemExit(__doc__)
    pool = os.path.expanduser(argv[argv.index("--pool") + 1])
    seed = int(arg(argv, "seed", "1"))
    if "--check" in argv:
        return check(pool, seed)
    seat = arg(argv, "seat", "guard")
    seconds = float(arg(argv, "seconds", "30"))
    log = arg(argv, "log")
    if seat != "guard" and not seat.startswith("runner:"):
        raise SystemExit("pill: --seat must be guard or runner:K")
    t0 = time.time()
    wt = make_worktree(seed)
    print("worktree: %.0f s" % (time.time() - t0), flush=True)
    try:
        take(seat, seed, seconds, wt, pool, os.path.expanduser(log) if log else None)
    finally:
        if "--keep" not in argv:
            remove_worktree(seed)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
