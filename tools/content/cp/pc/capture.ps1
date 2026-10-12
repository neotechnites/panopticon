# capture.ps1 <job.json> : one real-time take in the console session (cp/capture.py runs it as a task).
# Godot draws white head/tail markers; ffmpeg ddagrabs the window; the take is cut strictly between them.
param([string]$Job)
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$j = Get-Content $Job -Raw | ConvertFrom-Json
$res = [ordered]@{ ok = $false; error = ''; mode = $j.mode }
function Done { $res | ConvertTo-Json -Depth 6 | Set-Content -Path $j.result -Encoding UTF8; exit 0 }
function F([double]$x) { $x.ToString('0.######', $inv) }
trap { $res.error = "capture.ps1 line $($_.InvocationInfo.ScriptLineNumber): $_"; Remove-Item "$($j.project)\override.cfg" -EA SilentlyContinue; Done }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace CP -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);
'@
[CP.Win]::SetProcessDPIAware() | Out-Null
# Wake the display and hold it awake for the take (ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED).
[CP.Win]::SetThreadExecutionState([uint32]2147483651) | Out-Null
[CP.Win]::mouse_event(1, 1, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 200
[CP.Win]::mouse_event(1, -1, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 800

$w = [int]$j.w; $h = [int]$j.h; $fps = [int]$j.fps
if ($j.mode -eq 'final') {
  # The virtual monitor carries both capture sizes; switch it to this job's (portrait short, landscape devlog).
  Add-Type -Namespace CP -Name Disp -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)] public struct DEVMODE {
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
  public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
  public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
[DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
[DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr param);
'@
  $virt = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary -and (($_.Bounds.Width -eq 1080 -and $_.Bounds.Height -eq 1920) -or ($_.Bounds.Width -eq 1920 -and $_.Bounds.Height -eq 1080)) } | Select-Object -First 1
  if ($virt -and ($virt.Bounds.Width -ne $w -or $virt.Bounds.Height -ne $h)) {
    $dm = New-Object CP.Disp+DEVMODE; $dm.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($dm)
    [CP.Disp]::EnumDisplaySettings($virt.DeviceName, -1, [ref]$dm) | Out-Null
    $dm.dmPelsWidth = $w; $dm.dmPelsHeight = $h; $dm.dmFields = 0x180000
    $rc = [CP.Disp]::ChangeDisplaySettingsEx($virt.DeviceName, [ref]$dm, [IntPtr]::Zero, 1, [IntPtr]::Zero)
    $res.mode_switch = "$($virt.DeviceName) -> ${w}x${h}: $rc"; Start-Sleep -Seconds 2
  }
}
# rough: the main screen, as today. final: the capture-only virtual monitor at exactly w x h.
$screen = $null
foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
  if ($j.mode -eq 'final') { if ($s.Bounds.Width -eq $w -and $s.Bounds.Height -eq $h -and -not $s.Primary) { $screen = $s } }
  elseif ($s.Primary) { $screen = $s }
}
if (-not $screen) { $res.error = "no $($j.mode) screen for ${w}x${h} (final needs the virtual monitor: cp/pc/install_virtual_monitor.ps1)"; Done }
$b = $screen.Bounds
$res.screen = "$($screen.DeviceName) $($b.Width)x$($b.Height)+$($b.X)+$($b.Y)"
if ($w -gt $b.Width -or $h -gt $b.Height) { $res.error = "${w}x${h} does not fit $($res.screen); nothing is upscaled"; Done }

# ddagrab numbers its outputs itself: the one whose size is this screen's.
$idx = -1
for ($i = 0; $i -lt 6 -and $idx -lt 0; $i++) {
  $probe = & ffmpeg -hide_banner -f lavfi -i "ddagrab=output_idx=${i}:framerate=5" -frames:v 1 -f null - 2>&1 | Out-String
  if ($probe -match "Video: d3d11.*?(\d{3,5})x(\d{3,5})") {
    if ([int]$Matches[1] -eq $b.Width -and [int]$Matches[2] -eq $b.Height) { $idx = $i }
  }
}
if ($idx -lt 0) { $res.error = "no ddagrab output matches $($res.screen)"; Done }
$res.output_idx = $idx

$proj = $j.project
Set-Content -Path "$proj\override.cfg" -Value @('[display]', "window/size/viewport_width=$w", "window/size/viewport_height=$h", 'window/size/borderless=true', 'window/size/always_on_top=true')
$audio = if ($j.keep_audio) { '' } else { '--audio-driver Dummy ' }
$gargs = "--path $proj ${audio}--fixed-fps $fps --max-fps $fps --resolution ${w}x${h} --position $($b.X),$($b.Y) --script res://tools/capture/run_clip.gd -- $($j.args) --sync=$($j.sync_frames) --tail-marker=$($j.tail_frames)"
$res.godot_args = $gargs
$g = Start-Process -FilePath $j.godot -ArgumentList $gargs -RedirectStandardOutput $j.log -RedirectStandardError "$($j.log).err" -PassThru -WindowStyle Normal
$deadline = (Get-Date).AddSeconds(90)
do { Start-Sleep -Milliseconds 50; $g.Refresh() } until (($g.MainWindowHandle -ne 0) -or $g.HasExited -or ((Get-Date) -gt $deadline))
try { $g.PriorityClass = 'BelowNormal' } catch {}
$ox = 0; $oy = 0   # the window sits at the screen's own origin
$fi = New-Object System.Diagnostics.ProcessStartInfo 'ffmpeg.exe', "-hide_banner -loglevel error -y -threads 4 -f lavfi -i ddagrab=output_idx=${idx}:framerate=${fps}:video_size=${w}x${h}:offset_x=${ox}:offset_y=${oy}:draw_mouse=0 -vf hwdownload,format=bgra,format=gbrp -c:v utvideo `"$($j.raw)`""
$fi.UseShellExecute = $false; $fi.CreateNoWindow = $true; $fi.RedirectStandardInput = $true; $fi.RedirectStandardError = $true
$fp = [System.Diagnostics.Process]::Start($fi)
try { $fp.PriorityClass = 'BelowNormal' } catch {}
# Only the two processes started here are ever killed.
if (-not $g.WaitForExit([int](1000 * ([double]$j.seconds + 120)))) { Stop-Process -Id $g.Id -Force; $res.error = 'godot timed out' }
Start-Sleep -Milliseconds 300
$fp.StandardInput.Write('q'); $fp.StandardInput.Close()
if (-not $fp.WaitForExit(30000)) { Stop-Process -Id $fp.Id -Force }
$res.ffmpeg_err = $fp.StandardError.ReadToEnd()
Remove-Item "$proj\override.cfg" -ErrorAction SilentlyContinue
[CP.Win]::SetThreadExecutionState([uint32]2147483648) | Out-Null
$res.godot_exit = $g.ExitCode
if (-not (Test-Path $j.raw)) { $res.error = 'ffmpeg wrote nothing (display asleep?)'; Done }

# The markers, found on the window's top-left (inside the window at any size it booted at).
$cw = [Math]::Min($w, 800); $ch = [Math]::Min($h, 600)
$runs = @()
$bd = & ffmpeg -hide_banner -nostats -threads 4 -i $j.raw -an -vf "crop=${cw}:${ch}:0:0,negate,blackdetect=d=0.1:pix_th=0.05:pic_th=0.98" -f null - 2>&1 | Select-String 'black_start:([0-9.]+) black_end:([0-9.]+)'
foreach ($m in $bd) { $runs += , @([double]::Parse($m.Matches[0].Groups[1].Value, $inv), [double]::Parse($m.Matches[0].Groups[2].Value, $inv)) }
$res.white_runs = $runs
if ($runs.Count -lt 2) { $res.error = "markers: $($runs.Count) white run(s), need head and tail"; Done }
$t0 = $runs[0][1]; $t1 = $runs[$runs.Count - 1][0]
$res.t0 = $t0; $res.t1 = $t1
# The window fills the frame: the last head-marker frame and the first tail-marker frame are white edge to edge.
$step = 1.0 / $fps
foreach ($pair in @(@('head_full_white', ($t0 - 2 * $step)), @('tail_full_white', ($t1 + 2 * $step)))) {
  $y = & ffmpeg -hide_banner -nostats -ss (F $pair[1]) -i $j.raw -frames:v 1 -vf 'format=yuv444p,signalstats,metadata=print:key=lavfi.signalstats.YMIN:file=-' -f null - 2>$null | Select-String 'YMIN=([0-9.]+)'
  $res[$pair[0]] = if ($y) { [double]::Parse($y.Matches[0].Groups[1].Value, $inv) } else { -1 }
}

# The take: every frame strictly between the markers, lossless.
& ffmpeg -hide_banner -loglevel error -y -threads 4 -ss (F $t0) -i $j.raw -t (F ($t1 - $t0)) -an -c:v utvideo $j.take 2>&1 | Out-Null
$probe = & ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=width,height,codec_name,nb_read_frames:format=duration,size -of json $j.take | ConvertFrom-Json
$res.w = [int]$probe.streams[0].width; $res.h = [int]$probe.streams[0].height
$res.codec = $probe.streams[0].codec_name; $res.frames = [int]$probe.streams[0].nb_read_frames
$res.duration = [double]::Parse($probe.format.duration, $inv); $res.bytes = [long]$probe.format.size

# G3: wallpaper magenta share per frame (max), whole take. G4 and G6 inside the used window: black, frozen, motion, luma.
$win = @('-ss', (F $j.win_in), '-t', (F $j.win_len))
$mg = & ffmpeg -hide_banner -nostats -threads 4 -i $j.take -an -vf 'fps=10,scale=180:-2,format=rgb24,colorkey=0xFF00FF:0.12:0,alphaextract,negate,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-' -f null - 2>$null | Select-String 'YAVG=([0-9.]+)' | ForEach-Object { [double]::Parse($_.Matches[0].Groups[1].Value, $inv) }
$res.magenta_max = if ($mg) { ($mg | Measure-Object -Maximum).Maximum / 255.0 } else { -1 }
$res.black = (& ffmpeg -hide_banner -nostats -threads 4 @win -i $j.take -an -vf 'blackdetect=d=0.5:pix_th=0.10' -f null - 2>&1 | Select-String 'black_start' | Measure-Object).Count
$res.freeze = (& ffmpeg -hide_banner -nostats -threads 4 @win -i $j.take -an -vf 'freezedetect=n=-50dB:d=0.75' -f null - 2>&1 | Select-String 'freeze_duration' | Measure-Object).Count
$mo = & ffmpeg -hide_banner -nostats -threads 4 @win -i $j.take -an -vf "fps=10,scale=90:-2,format=gray,tblend=all_mode=difference,lutyuv=y='if(gt(val,24),255,0)',signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>$null | Select-String 'YAVG=([0-9.]+)' | ForEach-Object { [double]::Parse($_.Matches[0].Groups[1].Value, $inv) }
$res.motion = if ($mo) { ($mo | Measure-Object -Average).Average / 255.0 } else { 0 }
$lu = & ffmpeg -hide_banner -nostats -threads 4 @win -i $j.take -an -vf 'fps=2,scale=270:-2,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-' -f null - 2>$null | Select-String 'YAVG=([0-9.]+)' | ForEach-Object { [double]::Parse($_.Matches[0].Groups[1].Value, $inv) } | Sort-Object
$res.luma_median = if ($lu) { @($lu)[[int][Math]::Floor(@($lu).Count / 2)] } else { -1 }
if (-not $j.keep_raw) { Remove-Item $j.raw -ErrorAction SilentlyContinue }
$res.ok = $true
Done
