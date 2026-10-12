# capture.ps1 <jobs.txt> <outdir> : real-time portrait takes for ragdoll_vnext, one Godot run per job line.
# Job: name|project dir|godot args|seconds. Godot borderless 810x1440 at 0,0 (the PC screen is 1440 tall), ddagrab -> utvideo.
param([string]$Jobs, [string]$Out)
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$log = "$Out\capture.log"
Add-Type -Namespace Win32 -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
'@
[Win32.Win]::mouse_event(0x0001, 1, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300
[Win32.Win]::mouse_event(0x0001, -1, 0, 0, [UIntPtr]::Zero); Start-Sleep -Seconds 4
foreach ($line in Get-Content $Jobs) {
  if ($line.Trim() -eq '' -or $line.StartsWith('#')) { continue }
  $f = $line.Split('|'); $name = $f[0].Trim(); $proj = $f[1].Trim(); $gargs = $f[2].Trim()
  $avi = "$Out\$name.avi"; $glog = "$Out\$name.log"
  if (Test-Path $avi) { Remove-Item $avi }
  "== $name $(Get-Date)" | Out-File $log -Append
  [Win32.Win]::mouse_event(0x0001, 1, 0, 0, [UIntPtr]::Zero)
  Set-Content -Path "$proj\override.cfg" -Value @('[display]','window/size/viewport_width=810','window/size/viewport_height=1440','window/size/borderless=true','window/size/always_on_top=true')
  $g = New-Object System.Diagnostics.ProcessStartInfo 'cmd.exe', "/c C:\tools\godot\godot.exe --path $proj --audio-driver Dummy --fixed-fps 60 --max-fps 60 --resolution 810x1440 --position 0,0 $gargs > $glog 2>&1"
  $g.UseShellExecute = $false; $g.CreateNoWindow = $true
  $gp = [System.Diagnostics.Process]::Start($g)
  $deadline = (Get-Date).AddSeconds(120)
  do {
    Start-Sleep -Milliseconds 50
    $kid = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($gp.Id)" | Where-Object Name -like 'godot*' | Select-Object -First 1
    $kp = if ($kid) { Get-Process -Id $kid.ProcessId -ErrorAction SilentlyContinue } else { $null }
    $win = if ($kp) { $kp.MainWindowHandle } else { 0 }
  } until (($win -ne 0) -or $gp.HasExited -or ((Get-Date) -gt $deadline))
  try { $kp.PriorityClass = 'Normal' } catch {}
  $ff = New-Object System.Diagnostics.ProcessStartInfo 'cmd.exe', "/c ffmpeg -hide_banner -loglevel error -y -threads 4 -f lavfi -i ddagrab=output_idx=0:framerate=60:video_size=810x1440:offset_x=0:offset_y=0:draw_mouse=0 -vf hwdownload,format=bgra,format=gbrp -c:v utvideo $avi 2> $avi.err"
  $ff.UseShellExecute = $false; $ff.CreateNoWindow = $true; $ff.RedirectStandardInput = $true
  $fp = [System.Diagnostics.Process]::Start($ff)
  try { $fp.PriorityClass = 'BelowNormal' } catch {}
  # The saved settings resize the window once after boot; hold it at the take's size.
  while (-not $gp.HasExited) {
    if ($win -ne 0) { [Win32.Win]::SetWindowPos($win, [IntPtr](-1), 0, 0, 810, 1440, 0x0040) | Out-Null }
    Start-Sleep -Milliseconds 100
  }
  $fp.StandardInput.Write('q'); $fp.StandardInput.Close()
  if (-not $fp.WaitForExit(30000)) { Stop-Process -Id $fp.Id -Force }
  Remove-Item "$proj\override.cfg" -ErrorAction SilentlyContinue
  "== $name done $(Get-Date) $((Get-Item $avi -ErrorAction SilentlyContinue).Length)" | Out-File $log -Append
}
"done $(Get-Date)" | Out-File $log -Append
