"""content editor: a plan.json editor row -> takes/<line>/take.avi of the Godot editor, from a scrubbed throwaway copy.

The copy is built per take, scrubbed by SCRUB, listed, and refused before filming if any banned
token or agent file survives (decision 362). It is deleted afterwards.
"""
from __future__ import annotations

import json
import os
import tempfile
import time
from pathlib import Path

try:
    from . import pclock
    from .capture import FPS, HERE, PC_CONTENT, PC_GODOT, PC_TOOLS, PC_WORKTREES, VERSION, gate, take_size
    from .pclock import pc, pc_pull, pc_push
except ImportError:
    from cp import pclock  # type: ignore
    from cp.capture import FPS, HERE, PC_CONTENT, PC_GODOT, PC_TOOLS, PC_WORKTREES, VERSION, gate, take_size  # type: ignore
    from cp.pclock import pc, pc_pull, pc_push  # type: ignore

# Removed from the copy before the editor opens: tooling, docs, agent files, tests, CI.
SCRUB = ["tools", "tests", "docs", "addons", ".claude", ".github", ".agents"]
SCRUB_GLOBS = ["*.md", "*.blend", "*.blend1", "*.txt", "*.sh", "*.py", "*.ps1", ".gitignore", ".gitattributes"]
# A path containing any of these may never reach the editor's screen (G12's token list, for file names).
BANNED = ["CLAUDE", "claude", ".md", "agent", "AI", "tools/", "addons/", ".claude", "ddd", "white" + "head",
          "ryan", "Ryan", "stack" + "integrated", "DESKTOP-", "100.114."]
SETTLE_S = 20.0   # the editor opens, scans and lays out before the take starts


def scrub_script(copy: str, sha: str) -> str:
    rm = ", ".join(f"'{copy}\\{p.replace('/', chr(92))}'" for p in SCRUB)
    globs = ", ".join(f"'{g}'" for g in SCRUB_GLOBS)
    banned = ", ".join("'" + b.replace("'", "''") + "'" for b in BANNED)
    return f"""
$ErrorActionPreference = 'Stop'
$c = '{copy}'
if (Test-Path $c) {{ git -C C:/dev/verify worktree remove --force $c 2>&1 | Out-Null; Remove-Item -Recurse -Force $c -EA SilentlyContinue }}
git -C C:/dev/verify worktree add --detach $c {sha} 2>&1 | Out-Null
Remove-Item -Recurse -Force {rm} -EA SilentlyContinue
Get-ChildItem $c -Recurse -Force -Include {globs} -File | Where-Object {{ $_.FullName -notlike "$c\\.git*" }} | Remove-Item -Force
# The copy forgets its plugins (they live in addons/) and keeps the imported cache, not the editor's layout or history.
$pg = Get-Content "$c\\project.godot"
$out = @(); $skip = $false
foreach ($l in $pg) {{ if ($l -match '^\\[editor_plugins\\]') {{ $skip = $true; continue }}; if ($skip -and $l -match '^\\[') {{ $skip = $false }}; if (-not $skip) {{ $out += $l }} }}
Set-Content "$c\\project.godot" $out
if (Test-Path C:\\dev\\verify\\.godot\\imported) {{ robocopy C:\\dev\\verify\\.godot\\imported "$c\\.godot\\imported" /E /NFL /NDL /NJH /NJS /NP | Out-Null }}
cmd /c "{PC_GODOT} --headless --import --path $c > $c\\..\\cp_editor_import.txt 2>&1"
Remove-Item -Recurse -Force "$c\\.godot\\editor" -EA SilentlyContinue
# The scrub check: every path the editor could list, against the banned tokens.
$bad = Get-ChildItem $c -Recurse -Force | Where-Object {{ $_.FullName -notlike "$c\\.godot*" -and $_.FullName -notlike "$c\\.git*" }} |
  ForEach-Object {{ $_.FullName.Substring($c.Length).Replace('\\', '/') }} | Where-Object {{ $p = $_ + $(if ((Get-Item -LiteralPath ($c + $_)).PSIsContainer) {{ '/' }} else {{ '' }}); ({banned} | Where-Object {{ $p.Contains($_) }}).Count -gt 0 }}
if ($bad) {{ Write-Output ('SCRUB FAILED: ' + (($bad | Select-Object -First 8) -join ', ')) }} else {{ Write-Output 'SCRUB OK' }}
"""


EDITOR_PS = r"""
param([string]$Job)
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$j = Get-Content $Job -Raw | ConvertFrom-Json
$ErrorActionPreference = 'Continue'   # ffmpeg talks on stderr; PowerShell 5 would stop on it
$res = [ordered]@{ ok = $false; error = '' }
function Done { $res | ConvertTo-Json -Depth 5 | Set-Content -Path $j.result -Encoding UTF8; exit 0 }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace CP -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);
'@
[CP.Win]::SetProcessDPIAware() | Out-Null
[CP.Win]::SetThreadExecutionState([uint32]2147483651) | Out-Null
[CP.Win]::mouse_event(1, 1, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 200; [CP.Win]::mouse_event(1, -1, 0, 0, [UIntPtr]::Zero)
$w = [int]$j.w; $h = [int]$j.h
$screen = [System.Windows.Forms.Screen]::AllScreens | Where-Object { if ($j.mode -eq 'final') { $_.Bounds.Width -eq $w -and $_.Bounds.Height -eq $h -and -not $_.Primary } else { $_.Primary } } | Select-Object -First 1
if (-not $screen) { $res.error = "no $($j.mode) screen"; Done }
$b = $screen.Bounds
$idx = -1
for ($i = 0; $i -lt 6 -and $idx -lt 0; $i++) {
  $p = & ffmpeg -hide_banner -f lavfi -i "ddagrab=output_idx=${i}:framerate=5" -frames:v 1 -f null - 2>&1 | Out-String
  if ($p -match "Video: .*?d3d11.*?(\d{3,5})x(\d{3,5})" -and [int]$Matches[1] -eq $b.Width -and [int]$Matches[2] -eq $b.Height) { $idx = $i }
}
if ($idx -lt 0) { $res.error = 'no ddagrab output for the screen'; Done }
$g = Start-Process -FilePath $j.godot -ArgumentList "-e --path $($j.project) --resolution ${w}x${h} --position $($b.X),$($b.Y) $($j.scene)" -RedirectStandardOutput $j.log -RedirectStandardError "$($j.log).err" -PassThru -WindowStyle Normal
$deadline = (Get-Date).AddSeconds(120)
do { Start-Sleep -Milliseconds 200; $g.Refresh() } until (($g.MainWindowHandle -ne 0) -or $g.HasExited -or ((Get-Date) -gt $deadline))
try { $g.PriorityClass = 'BelowNormal' } catch {}
Start-Sleep -Seconds ([double]$j.settle)
# Recording starts after the editor is up and stops before it closes: no desktop at either end.
& ffmpeg -hide_banner -loglevel error -y -threads 4 -f lavfi -i "ddagrab=output_idx=${idx}:framerate=$($j.fps):video_size=${w}x${h}:offset_x=0:offset_y=0:draw_mouse=0" -t $j.seconds -vf hwdownload,format=bgra,format=gbrp -c:v utvideo $j.take 2>&1 | Out-Null
if (-not $g.HasExited) { Stop-Process -Id $g.Id -Force }
[CP.Win]::SetThreadExecutionState([uint32]2147483648) | Out-Null
if (-not (Test-Path $j.take)) { $res.error = 'ffmpeg wrote nothing'; Done }
$pr = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height:format=duration,size -of json $j.take | ConvertFrom-Json
$res.w = [int]$pr.streams[0].width; $res.h = [int]$pr.streams[0].height
$res.duration = [double]::Parse($pr.format.duration, $inv); $res.bytes = [long]$pr.format.size
$res.black = (& ffmpeg -hide_banner -nostats -i $j.take -an -vf 'blackdetect=d=0.5:pix_th=0.10' -f null - 2>&1 | Select-String 'black_start' | Measure-Object).Count
$mg = & ffmpeg -hide_banner -nostats -i $j.take -an -vf 'fps=10,scale=180:-2,format=rgb24,colorkey=0xFF00FF:0.12:0,alphaextract,negate,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-' -f null - 2>$null | Select-String 'YAVG=([0-9.]+)' | ForEach-Object { [double]::Parse($_.Matches[0].Groups[1].Value, $inv) }
$res.magenta_max = if ($mg) { ($mg | Measure-Object -Maximum).Maximum / 255.0 } else { -1 }
$res.ok = $true
Done
"""


def capture_editor(plan: dict, row: dict, mode: str, local_dir: Path) -> dict:
    name, line = plan["name"], row["id"]
    e = row.get("editor") or {}
    w, h, size_note = take_size(plan.get("kind", "short"), mode)
    seconds = float(e.get("seconds", row.get("min_seconds") if isinstance(row.get("min_seconds"), (int, float)) else 6.0)) + 1.0
    sha = pc(f"(git -C C:/dev/verify rev-parse '{e.get('ref', 'main')}^{{commit}}').Trim()").strip()
    copy = f"{PC_WORKTREES}\\cp_editor_{sha[:10]}"
    pc_dir = f"{PC_CONTENT}\\{name}\\takes\\{line}"
    local_dir.mkdir(parents=True, exist_ok=True)
    scrub = pc(scrub_script(copy, sha), timeout=1800)
    take = {"line": line, "path": f"{pc_dir}\\take.avi", "w": w, "h": h, "fps": FPS, "commit": sha, "t0": 0.0,
            "t1": seconds, "args": [e.get("scene", "")], "mode": mode, "size_note": size_note, "source": "editor",
            "editor": e, "dock": e.get("dock", "default (not scoped)"), "events": [], "clip_events": [], "gates": {}}
    if "SCRUB OK" not in scrub:
        take["gates"]["G12"] = gate(False, scrub.strip().splitlines()[-1] if scrub.strip() else "scrub unchecked")
        (local_dir / "take.json").write_text(json.dumps(take, indent=1))
        return take
    take["gates"]["G12"] = gate(True, "scrubbed copy listed clean before filming")
    pc(f"New-Item -ItemType Directory -Force -Path '{pc_dir}', '{PC_TOOLS}' | Out-Null")
    with tempfile.NamedTemporaryFile("w", suffix=".ps1", delete=False) as f:
        f.write(EDITOR_PS)
    pc_push(f.name, f"{PC_TOOLS}\\editor.ps1")
    os.unlink(f.name)
    job = {"mode": mode, "w": w, "h": h, "fps": FPS, "godot": PC_GODOT, "project": copy,
           "scene": e.get("scene", ""), "seconds": seconds, "settle": SETTLE_S,
           "take": f"{pc_dir}\\take.avi", "log": f"{pc_dir}\\editor.log", "result": f"{pc_dir}\\result.json"}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(job, f)
    pc_push(f.name, f"{pc_dir}\\job.json")
    os.unlink(f.name)
    task = f"cp_editor_{os.getpid()}_{int(time.time())}"
    with pclock.lease("screen", f"{name}/{line} editor", seconds + SETTLE_S + 60):
        pc(f"""
$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File {PC_TOOLS}\\editor.ps1 -Job "{pc_dir}\\job.json"'
$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
Register-ScheduledTask -TaskName '{task}' -Action $a -Principal $p -Force | Out-Null
Start-ScheduledTask -TaskName '{task}'; Start-Sleep -Seconds 2
while ((Get-ScheduledTask -TaskName '{task}').State -eq 'Running') {{ Start-Sleep -Seconds 1 }}
Unregister-ScheduledTask -TaskName '{task}' -Confirm:$false
""", timeout=seconds + 900)
    res = json.loads(pc(f"Get-Content '{pc_dir}\\result.json' -Raw", check=False).strip().lstrip("\ufeff") or '{"ok": false}')
    pc(f"git -C C:/dev/verify worktree remove --force '{copy}'; Remove-Item -Recurse -Force '{copy}' -EA SilentlyContinue",
       check=False)
    ok = res.get("ok") and (res.get("w"), res.get("h")) == (w, h) and res.get("magenta_max", 1) < 0.005
    take["gates"]["G3"] = gate(bool(ok), f"editor {res.get('w')}x{res.get('h')}, recorded only while it was up"
                               if ok else f"editor take: {res.get('error') or res}")
    rate = res.get("bytes", 0) / max(res.get("duration", 0.01), 0.01)
    take["gates"]["G4"] = gate(res.get("ok", False) and rate >= 1e6 and not res.get("black"),
                               f"{rate / 1e6:.1f} MB/s, black {res.get('black')} (an editor is still by nature: motion not gated)")
    take["measure"] = res
    (local_dir / "take.json").write_text(json.dumps(take, indent=1))
    (local_dir / "take.avi.prov.json").write_text(json.dumps(
        {"inputs": [], "encoder": "utvideo", "lossless": True, "tool": "cp.editor", "version": VERSION, "commit": sha}))
    pc_push(str(local_dir / "take.json"), f"{pc_dir}\\take.json")
    return take
