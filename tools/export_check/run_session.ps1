# Runs one multi-peer session of an exported build on this PC from a JSON config and writes
# <out>\result.txt then <out>\done. Each peer gets its own APPDATA, so no real settings are read.
# A release template takes no --script, so the exe and pck are copied to <harness> beside an
# override.cfg that names the driver as an autoload; the pck bytes are the shipped ones.
# Config: { exe, harness, driver, out, headless, timeout, stagger, peers: [ { name, args: [..] } ] }
param([Parameter(Mandatory = $true)][string]$Config)
$ErrorActionPreference = 'Continue'
$c = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
$out = $c.out
New-Item -ItemType Directory -Force -Path $out | Out-Null
Remove-Item -LiteralPath (Join-Path $out 'done'), (Join-Path $out 'result.txt') -ErrorAction SilentlyContinue
$src = Split-Path -Parent $c.exe
New-Item -ItemType Directory -Force -Path $c.harness | Out-Null
foreach ($f in Get-ChildItem -LiteralPath $src -File) {
    $to = Join-Path $c.harness $f.Name
    if (-not (Test-Path -LiteralPath $to) -or (Get-Item -LiteralPath $to).Length -ne $f.Length -or (Get-Item -LiteralPath $to).LastWriteTimeUtc -ne $f.LastWriteTimeUtc) { Copy-Item -LiteralPath $f.FullName -Destination $to -Force }
}
$driverUrl = $c.driver -replace '\\', '/'
"[autoload]`n`nExportDriver=`"*$driverUrl`"`n" | Set-Content -LiteralPath (Join-Path $c.harness 'override.cfg') -Encoding Ascii
$exe = Join-Path $c.harness (Split-Path -Leaf $c.exe)
$realAppData = $env:APPDATA
$started = Get-Date
$procs = @()
$slot = 0
foreach ($peer in $c.peers) {
    $data = Join-Path $out ($peer.name + '_appdata')
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    $env:APPDATA = $data
    $argList = @()
    if ($c.headless) { $argList += '--headless' }
    else {
        $x = 20 + 660 * ($slot % 2); $y = 40 + 400 * [math]::Floor($slot / 2)
        $argList += @('--windowed', '--resolution', '640x360', '--position', "$x,$y")
    }
    $argList += '--'
    if (-not $c.headless) { $argList += @('--width=640', '--height=360') }
    $argList += $peer.args
    $p = Start-Process -FilePath $exe -ArgumentList $argList -PassThru `
        -RedirectStandardOutput (Join-Path $out ($peer.name + '.log')) `
        -RedirectStandardError (Join-Path $out ($peer.name + '.err'))
    $null = $p.Handle
    $procs += [pscustomobject]@{ Name = $peer.name; Proc = $p }
    $slot++
    # The host is given time to reach its hub before anybody joins.
    Start-Sleep -Milliseconds $(if ($slot -eq 1) { [int]$c.stagger * 4 } else { [int]$c.stagger })
}
$env:APPDATA = $realAppData
$deadline = $started.AddSeconds([int]$c.timeout)
while ((Get-Date) -lt $deadline -and ($procs | Where-Object { -not $_.Proc.HasExited })) { Start-Sleep -Milliseconds 500 }
$lines = @()
foreach ($e in $procs) {
    $hung = -not $e.Proc.HasExited
    if ($hung) { Stop-Process -Id $e.Proc.Id -Force -ErrorAction SilentlyContinue; $e.Proc.WaitForExit(5000) | Out-Null }
    $log = Join-Path $out ($e.Name + '.log')
    $end = (Select-String -LiteralPath $log -Pattern '^DRV .* END ' -ErrorAction SilentlyContinue | Select-Object -Last 1).Line
    $lines += ('{0} pid={1} exit={2} hung={3} end=[{4}]' -f $e.Name, $e.Proc.Id, $e.Proc.ExitCode, $hung, $end)
}
$events = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $started } -MaxEvents 200 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'panopticon\.exe' }
foreach ($ev in $events) { $lines += ('EVENT {0} id={1} {2}' -f $ev.TimeCreated.ToString('s'), $ev.Id, (($ev.Message -split "`r?`n" | Select-Object -First 8) -join ' | ')) }
$lines | Set-Content -LiteralPath (Join-Path $out 'result.txt')
'1' | Set-Content -LiteralPath (Join-Path $out 'done')
$lines
