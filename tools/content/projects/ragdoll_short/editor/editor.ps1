# editor.ps1 -Job <json>: a scrubbed throwaway copy of the short's PC checkout (decision 362: no CLAUDE.md, no *.md,
# no tools/, addons/, tests/, docs/, agent folders), the death scene and the framing autoload put in, the Godot editor
# opened on it in the console session (scheduled task), the whole screen recorded (ddagrab, utvideo) while the Death
# clip is triggered by res://go.on. Job: {src, copy, kit, scene, take, seconds, go_at, log}. Result: <take>.json.
param([string]$Job)
$ErrorActionPreference = 'Continue'
$inv = [Globalization.CultureInfo]::InvariantCulture
$j = Get-Content $Job -Raw | ConvertFrom-Json
$c = $j.copy; $src = $j.src; $kit = $j.kit
$res = [ordered]@{ ok = $false; error = '' }
function Done { $res | ConvertTo-Json -Depth 5 | Set-Content -Path "$($j.take).json" -Encoding UTF8; exit 0 }

# --- the copy, scrubbed -------------------------------------------------------------------
$sha = (git -C $src rev-parse HEAD).Trim()
$res.commit = $sha
if (Test-Path $c) { git -C C:/dev/verify worktree remove --force $c 2>&1 | Out-Null; Remove-Item -Recurse -Force $c -EA SilentlyContinue }
git -C C:/dev/verify worktree add --detach $c $sha 2>&1 | Out-Null
if (-not (Test-Path "$c\project.godot")) { $res.error = 'the copy was not created'; Done }
foreach ($d in 'tools', 'tests', 'docs', 'addons', '.claude', '.github', '.agents', '.codex') { Remove-Item -Recurse -Force "$c\$d" -EA SilentlyContinue }
Get-ChildItem $c -Recurse -Force -Include '*.md', '*.blend', '*.blend1', '*.txt', '*.sh', '*.py', '*.ps1', '.gitignore', '.gitattributes', 'override.cfg', 'AGENTS*' -File |
  Where-Object { $_.FullName -notlike "$c\.git*" } | Remove-Item -Force
# No plugins (they lived in addons/), the game's autoloads kept, the framing autoload added, the editor's own AA on.
$pg = Get-Content "$c\project.godot"; $out = @(); $skip = $false
foreach ($l in $pg) {
  if ($l -match '^\[editor_plugins\]') { $skip = $true; continue }
  if ($skip -and $l -match '^\[') { $skip = $false }
  if ($skip) { continue }
  $out += $l
  if ($l -match '^\[autoload\]') { $out += ''; $out += 'Framing="*res://frame.gd"' }
  if ($l -match '^\[rendering\]') { $out += ''; $out += 'anti_aliasing/quality/msaa_3d=2' }
}
Set-Content "$c\project.godot" $out
if (Test-Path "$src\.godot\imported") { robocopy "$src\.godot\imported" "$c\.godot\imported" /E /NFL /NDL /NJH /NJS /NP | Out-Null }
$gen = git -C $src ls-files -o -i --exclude-standard | Where-Object { $_ -match '\.(res|tres|material|mesh)$' -and $_ -notmatch '^(\.godot|tools|tests|docs|addons|build|export)/' }
foreach ($f in $gen) { $d = Join-Path $c $f; New-Item -ItemType Directory -Force (Split-Path $d) | Out-Null; Copy-Item (Join-Path $src $f) $d -Force }
cmd /c "C:\tools\godot\godot.exe --headless --import --path $c > $c\.godot\scrub_import.txt 2>&1"
Remove-Item -Recurse -Force "$c\.godot\editor" -EA SilentlyContinue
# The viewport as v14 showed it: no grid, no origin lines, no gizmos (the editor state file for this one scene).
New-Item -ItemType Directory -Force "$c\.godot\editor" | Out-Null
@('[editor_states]', '$selected_nodes=Array[NodePath]([])', '3D={', '"fov": 40.0,', '"show_grid": false,', '"show_origin": false,',
  '"viewports": [{', '"gizmos": false,', '"grid": false,', '"information": false,', '"transform_gizmo": false,', '"use_environment": true', '}]', '}') |
  Set-Content -Path "$c\.godot\editor\death_editor.tscn-editstate-dfbd398731c96bedbc0b0bd7fb2d5281.cfg" -Encoding ASCII
Copy-Item "$kit\frame.gd" "$c\frame.gd" -Force
Copy-Item "$kit\death_editor.tscn" "$c\characters\death_editor.tscn" -Force
Remove-Item "$c\go.on", "$c\ready.json" -EA SilentlyContinue
$all = Get-ChildItem $c -Recurse -Force | Where-Object { $_.FullName -notlike "$c\.godot*" -and $_.FullName -notlike "$c\.git*" } |
  ForEach-Object { $_.FullName.Substring($c.Length + 1).Replace('\', '/') + $(if ($_.PSIsContainer) { '/' } else { '' }) }
$banned = @('CLAUDE', 'claude', '.md', 'agent', 'AI', 'tools/', 'addons/', '.claude', 'ddd', ('white' + 'head'), 'ryan', 'Ryan', ('stack' + 'integrated'), 'DESKTOP-', '100.114.')
$bad = $all | Where-Object { $p = '/' + $_; ($banned | Where-Object { $p.Contains($_) }).Count -gt 0 }
$all | Set-Content -Path "$($j.take).listing.txt"
if ($bad) { $res.error = 'SCRUB FAILED: ' + (($bad | Select-Object -First 8) -join ', '); Done }
$res.scrub = "SCRUB OK ($($all.Count) paths)"

# --- the take, in the console session ----------------------------------------------------
$runner = "$($j.take).runner.ps1"
$ready = "$c\ready.json"
@"
`$ErrorActionPreference = 'Continue'
Add-Type -Namespace CP -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e); [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
[CP.Win]::SetProcessDPIAware() | Out-Null
[CP.Win]::SetThreadExecutionState([uint32]2147483651) | Out-Null
[CP.Win]::mouse_event(1, 1, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 200; [CP.Win]::mouse_event(1, -1, 0, 0, [UIntPtr]::Zero)
`$r = [ordered]@{ ok = `$false; error = '' }
`$idx = -1
for (`$i = 0; `$i -lt 6 -and `$idx -lt 0; `$i++) {
  `$p = & ffmpeg -hide_banner -f lavfi -i "ddagrab=output_idx=`${i}:framerate=5" -frames:v 1 -f null - 2>&1 | Out-String
  if (`$p -match "Video: .*?d3d11.*?(\d{3,5})x(\d{3,5})") { `$idx = `$i; `$r.screen = `$Matches[1] + 'x' + `$Matches[2] }
}
if (`$idx -lt 0) { `$r.error = 'no ddagrab output'; `$r | ConvertTo-Json | Set-Content '$($j.take).run.json'; exit 0 }
`$g = Start-Process -FilePath 'C:\tools\godot\godot.exe' -ArgumentList '-e --path $c --position 0,0 $($j.scene)' -RedirectStandardOutput '$($j.log)' -RedirectStandardError '$($j.log).err' -PassThru -WindowStyle Normal
Set-Content -Path '$($j.take).pid' -Value `$g.Id
Start-Sleep -Seconds 2
try { `$g.PriorityClass = 'BelowNormal' } catch {}
`$deadline = (Get-Date).AddSeconds(240)
while (-not (Test-Path '$ready') -and -not `$g.HasExited -and (Get-Date) -lt `$deadline) { Start-Sleep -Milliseconds 250 }
if (-not (Test-Path '$ready')) { `$r.error = `$(if (`$g.HasExited) { 'editor exited before framing' } else { 'editor never framed' }); if (-not `$g.HasExited) { Stop-Process -Id `$g.Id -Force }; `$r | ConvertTo-Json | Set-Content '$($j.take).run.json'; exit 0 }
Start-Sleep -Seconds 1
`$fi = New-Object System.Diagnostics.ProcessStartInfo 'cmd.exe', ('/c ffmpeg -hide_banner -loglevel error -y -threads 4 -f lavfi -i ddagrab=output_idx=' + `$idx + ':framerate=60:draw_mouse=0 -t $($j.seconds) -vf hwdownload,format=bgra,format=gbrp -c:v utvideo $($j.take) 2> $($j.take).err')
`$fi.UseShellExecute = `$false; `$fi.CreateNoWindow = `$true
`$t0 = Get-Date
try { `$fp = [System.Diagnostics.Process]::Start(`$fi) } catch { `$r.error = 'ffmpeg start: ' + `$_.Exception.Message; `$r | ConvertTo-Json | Set-Content '$($j.take).run.json'; Stop-Process -Id `$g.Id -Force; exit 0 }
try { `$fp.PriorityClass = 'BelowNormal' } catch {}
Start-Sleep -Milliseconds ([int](1000 * $($j.go_at)))
New-Item -ItemType File -Path '$c\go.on' -Force | Out-Null
`$r.go_at_wall = ((Get-Date) - `$t0).TotalSeconds
if (-not `$fp.WaitForExit([int](1000 * ($($j.seconds) + 60)))) { Stop-Process -Id `$fp.Id -Force }
`$r.ffmpeg_err = (Get-Content '$($j.take).err' -Raw -EA SilentlyContinue)
if (-not `$g.HasExited) { Stop-Process -Id `$g.Id -Force }
`$r.ok = `$true
`$r | ConvertTo-Json | Set-Content '$($j.take).run.json'
"@ | Set-Content -Path $runner -Encoding ASCII
Remove-Item "$($j.take).run.json" -EA SilentlyContinue
$task = 'panopticon_editor_take'
try {
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $runner"
  $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
  Register-ScheduledTask -TaskName $task -Action $a -Principal $p -Force | Out-Null
  Start-ScheduledTask -TaskName $task
  Start-Sleep -Seconds 2
  while ((Get-ScheduledTask -TaskName $task).State -eq 'Running') { Start-Sleep -Seconds 1 }
} finally {
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -EA SilentlyContinue
  $id = Get-Content "$($j.take).pid" -EA SilentlyContinue
  if ($id) { Get-Process -Id ([int]$id) -EA SilentlyContinue | Where-Object { $_.ProcessName -like 'godot*' } | Stop-Process -Force -EA SilentlyContinue }
}
$run = Get-Content "$($j.take).run.json" -Raw -EA SilentlyContinue | ConvertFrom-Json
if (-not $run) { $res.error = 'no run result'; Done }
$res.run = $run
if (-not $run.ok) { $res.error = $run.error; Done }
$res.framing = Get-Content $ready -Raw | ConvertFrom-Json
$pr = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height:format=duration -of json $j.take | ConvertFrom-Json
$res.w = [int]$pr.streams[0].width; $res.h = [int]$pr.streams[0].height; $res.duration = [double]::Parse($pr.format.duration, $inv)
$res.ok = $true
Done
