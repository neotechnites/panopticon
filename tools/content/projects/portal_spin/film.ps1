# film.ps1 <jobs.txt> <project dir> : real-time portrait takes in the console session (ddagrab, 810x1440 of the
# 1440 px screen), each trimmed from its sync frames + in to its last game frame and scaled to cuts\<name>.mp4.
# Job line: name|godot project|run_clip args|seconds|in
param([string]$Jobs, [string]$Dir)
$log = "$Dir\notes\film.log"
"start $(Get-Date)" | Out-File $log -Append
Add-Type -Namespace Win32 -Name Wake -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);'
[Win32.Wake]::mouse_event(0x0001, 1, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300
[Win32.Wake]::mouse_event(0x0001, -1, 0, 0, [UIntPtr]::Zero); Start-Sleep -Seconds 2
New-Item -ItemType Directory -Force -Path "$Dir\takes", "$Dir\cuts" | Out-Null
foreach ($line in Get-Content $Jobs) {
  if ($line.Trim() -eq '' -or $line.StartsWith('#')) { continue }
  $f = $line.Split('|'); $name = $f[0].Trim(); $proj = $f[1].Trim(); $uargs = $f[2].Trim(); $secs = [double]$f[3]; $in = [double]$f[4]
  $raw = "$Dir\takes\$name.avi"
  "== $name $(Get-Date)" | Out-File $log -Append
  Set-Content -Path "$proj\override.cfg" -Value @('[display]','window/size/viewport_width=810','window/size/viewport_height=1440','window/size/borderless=true','window/size/always_on_top=true')
  $g = Start-Process -FilePath 'C:\tools\godot\godot.exe' -ArgumentList "--path $proj --audio-driver Dummy --fixed-fps 60 --max-fps 60 --resolution 810x1440 --position 0,0 --script res://tools/capture/run_clip.gd -- $uargs --seconds=$secs --sync=90" -RedirectStandardOutput "$Dir\takes\$name.log" -RedirectStandardError "$Dir\takes\$name.err.log" -PassThru -WindowStyle Normal
  $deadline = (Get-Date).AddSeconds(90)
  do { Start-Sleep -Milliseconds 50; $g.Refresh() } until (($g.MainWindowHandle -ne 0) -or $g.HasExited -or ((Get-Date) -gt $deadline))
  try { $g.PriorityClass = 'BelowNormal' } catch {}
  $fi = New-Object System.Diagnostics.ProcessStartInfo 'ffmpeg.exe', "-hide_banner -loglevel error -y -threads 4 -f lavfi -i ddagrab=output_idx=0:framerate=60:video_size=810x1440:offset_x=0:offset_y=0:draw_mouse=0 -vf hwdownload,format=bgra,format=gbrp -c:v utvideo $raw"
  $fi.UseShellExecute = $false; $fi.CreateNoWindow = $true; $fi.RedirectStandardInput = $true
  $fp = [System.Diagnostics.Process]::Start($fi)
  if (-not $g.WaitForExit(300000)) { Stop-Process -Id $g.Id -Force }
  $fp.StandardInput.Write('q'); $fp.StandardInput.Close()
  if (-not $fp.WaitForExit(30000)) { Stop-Process -Id $fp.Id -Force }
  Remove-Item "$proj\override.cfg" -ErrorAction SilentlyContinue
  $d = ffmpeg -hide_banner -nostats -threads 4 -i $raw -an -vf 'crop=800:600:0:0,negate,blackdetect=d=0.1:pix_th=0.05:pic_th=0.98' -f null - 2>&1 | Select-String 'black_end:([0-9.]+)' | Select-Object -Last 1
  if (-not $d) { "   no sync frames" | Out-File $log -Append; continue }
  $t0 = [double]::Parse($d.Matches[0].Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
  # The take's last game frame is t0 + seconds; stop 0.25 s short of it so no desktop follows.
  $ss = ($t0 + $in).ToString([Globalization.CultureInfo]::InvariantCulture)
  $len = ($secs - $in - 0.25).ToString([Globalization.CultureInfo]::InvariantCulture)
  $p = Start-Process -FilePath 'ffmpeg.exe' -ArgumentList "-hide_banner -loglevel error -y -ss $ss -i $raw -t $len -threads 4 -vf scale=1080:1920:flags=lanczos,fps=60 -c:v libx264 -preset veryfast -crf 14 -pix_fmt yuv420p -an $Dir\cuts\$name.mp4" -PassThru -NoNewWindow -Wait
  "   t0 $t0 cut $ss +$len -> cuts\$name.mp4 $((Get-Item "$Dir\cuts\$name.mp4" -ErrorAction SilentlyContinue).Length)" | Out-File $log -Append
  Get-Content "$Dir\takes\$name.log" | Where-Object { $_ -match '^(\[stage\]|\[event\]|SCRIPT ERROR|ERROR)' } | Select-Object -Last 8 | Out-File $log -Append
}
"done $(Get-Date)" | Out-File $log -Append
