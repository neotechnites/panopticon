param([string]$Dir)
$jobs = @{ 's1_zoom'=@(7.5,1.5); 's2_scope'=@(10,1.5); 's3_wave'=@(8,1.5); 's4_dial'=@(10,1.5); 's5_orbit'=@(6.5,1.5); 's6_runner'=@(8,1.5) }
foreach ($name in $jobs.Keys) {
  $secs = $jobs[$name][0]; $in = $jobs[$name][1]; $raw = "$Dir\takes\$name.avi"
  $d = ffmpeg -hide_banner -nostats -threads 4 -i $raw -an -vf 'crop=800:600:0:0,negate,blackdetect=d=0.1:pix_th=0.05:pic_th=0.98' -f null - 2>&1 | Select-String 'black_end:([0-9.]+)' | Select-Object -Last 1
  $t0 = [double]::Parse($d.Matches[0].Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
  $dur = [double](ffprobe -v error -show_entries format=duration -of csv=p=0 $raw)
  $ss = ($t0 + $in).ToString([Globalization.CultureInfo]::InvariantCulture)
  $len = ($secs - $in - 0.25).ToString([Globalization.CultureInfo]::InvariantCulture)
  Start-Process -FilePath 'ffmpeg.exe' -ArgumentList "-hide_banner -loglevel error -y -ss $ss -i $raw -t $len -threads 4 -vf scale=1080:1920:flags=lanczos,fps=60 -c:v libx264 -preset veryfast -crf 14 -pix_fmt yuv420p -an $Dir\cuts\$name.mp4" -PassThru -NoNewWindow -Wait | Out-Null
  ffmpeg -hide_banner -loglevel error -y -i $Dir\cuts\$name.mp4 -vf 'fps=2,scale=120:214,tile=14x1' -frames:v 1 $Dir\frames\$name.png
  Write-Output "$name t0 $t0 rec $dur end-of-game $($t0+$secs)"
}
ffmpeg -hide_banner -loglevel error -y -i $Dir\frames\s1_zoom.png -i $Dir\frames\s2_scope.png -i $Dir\frames\s3_wave.png -i $Dir\frames\s4_dial.png -i $Dir\frames\s5_orbit.png -i $Dir\frames\s6_runner.png -filter_complex vstack=inputs=6 $Dir\frames\sheet.png
