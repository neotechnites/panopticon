# editor.ps1 : a scrubbed copy of the project, opened in the Godot editor on the hell map framed at the portal,
# recorded in real time (ddagrab, the whole 2560x1440 screen); the spin flips on 6 s into the recording.
$src = 'C:\dev\verify'; $dst = 'C:\dev\portal_editor'; $D = 'C:\Users\ddd\Desktop\panopticon-renders\content\portal_spin'
$log = "$D\notes\editor.log"
"start $(Get-Date)" | Out-File $log
Add-Type -Namespace Win32 -Name Wake -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);'
[Win32.Wake]::mouse_event(0x0001, 1, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300
[Win32.Wake]::mouse_event(0x0001, -1, 0, 0, [UIntPtr]::Zero)
if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
robocopy $src $dst /E /NFL /NDL /NJH /NJS /XD .git tools addons docs tests .claude towerlight /XF CLAUDE.md *.md AGENTS* override.cfg | Out-Null
Remove-Item "$dst\spin.on" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$dst\scenes" | Out-Null
Copy-Item "$D\scripts\ped\portal_spin.gd" "$dst\scenes\portal_spin.gd"
Copy-Item "$D\scripts\ped\portal_wave.gdshader" "$dst\maps\bentham_ring\materials\portal_wave.gdshader"
Copy-Item "$D\scripts\ped\bentham_ring.tscn" "$dst\maps\bentham_ring\bentham_ring.tscn"
New-Item -ItemType Directory -Force "$dst\.godot\editor" | Out-Null
Copy-Item "$D\scripts\ped\bentham_ring.tscn-editstate-0e8f147cac58fe868b261286ef4fbaee.cfg" "$dst\.godot\editor\"
$p = Get-Content "$dst\project.godot" | Where-Object { $_ -notmatch 'addons/' }
Set-Content "$dst\project.godot" $p
Get-ChildItem $dst -Name | Out-File $log -Append
$g = Start-Process -FilePath 'C:\tools\godot\godot.exe' -ArgumentList "--editor --path $dst res://maps/bentham_ring/bentham_ring.tscn" -RedirectStandardOutput "$D\takes\editor.log" -RedirectStandardError "$D\takes\editor.err.log" -PassThru
$deadline = (Get-Date).AddSeconds(60)
do { Start-Sleep -Milliseconds 200; $g.Refresh() } until (($g.MainWindowHandle -ne 0) -or $g.HasExited -or ((Get-Date) -gt $deadline))
Start-Sleep -Seconds 3
[Win32.Wake]::ShowWindow($g.MainWindowHandle, 3) | Out-Null
[Win32.Wake]::SetForegroundWindow($g.MainWindowHandle) | Out-Null
Start-Sleep -Seconds 30
try { $g.PriorityClass = 'BelowNormal' } catch {}
$raw = "$D\takes\editor.avi"
$fi = New-Object System.Diagnostics.ProcessStartInfo 'ffmpeg.exe', "-hide_banner -loglevel error -y -threads 4 -f lavfi -i ddagrab=output_idx=0:framerate=60:draw_mouse=0 -t 14 -vf hwdownload,format=bgra,format=gbrp -c:v utvideo $raw"
$fi.UseShellExecute = $false; $fi.CreateNoWindow = $true
$fp = [System.Diagnostics.Process]::Start($fi)
Start-Sleep -Seconds 6
New-Item -ItemType File "$dst\spin.on" | Out-Null
"spin on $(Get-Date -Format HH:mm:ss.fff)" | Out-File $log -Append
$fp.WaitForExit(40000) | Out-Null
Stop-Process -Id $g.Id -Force -ErrorAction SilentlyContinue
Get-Process | Where-Object { $_.ProcessName -like 'godot*' -and $_.Path -like '*godot*' } | Where-Object { $_.StartTime -gt (Get-Date).AddMinutes(-3) } | Stop-Process -Force -ErrorAction SilentlyContinue
"done $(Get-Date)" | Out-File $log -Append
