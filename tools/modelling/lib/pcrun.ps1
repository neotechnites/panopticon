<#
  pcrun.ps1 -- run a batch file ON THE PC and stream back its log.

  Two modes, and the difference is the whole reason this file exists.

  -Direct   Run it right here in the SSH session. Fine for anything that never
            touches a GPU: Cycles on CPU, godot --headless.

  (default) Push it into the LOGGED-ON CONSOLE SESSION with a scheduled task
            created /it (interactive). A Windows OpenSSH session has no GPU and
            no desktop context, so Blender's EEVEE dies there with
            EXCEPTION_ACCESS_VIOLATION every single time. In the console
            session it finds the RX 6600 XT and renders in seconds instead of
            minutes. /it is the flag that matters.

  The batch file is expected to write "<stem>.log" and, last of all, "<stem>.done"
  containing its exit code. The done-file is the completion signal: a scheduled
  task returns immediately and its own exit status tells you nothing about the
  process it started.

  Usage:
     powershell -File pcrun.ps1 -Bat C:\Users\ddd\panopticon-modelling\build.bat
     powershell -File pcrun.ps1 -Bat ...\verify.bat -Direct -TimeoutSec 300
#>
param(
    [Parameter(Mandatory = $true)][string]$Bat,
    [int]$TimeoutSec = 900,
    [switch]$Direct,
    [string]$TaskName = "PanopticonModelling"
)

$ErrorActionPreference = "Continue"
$stem = [System.IO.Path]::ChangeExtension($Bat, $null).TrimEnd('.')
$log  = "$stem.log"
$done = "$stem.done"

Remove-Item -LiteralPath $log, $done -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $Bat)) {
    Write-Output "PCRUN ERROR: no such batch file: $Bat"
    exit 90
}

$started = Get-Date

if ($Direct) {
    & cmd.exe /c "`"$Bat`"" | Out-Null
} else {
    schtasks /create /tn $TaskName /tr "`"$Bat`"" /sc once /st 23:59 /ru $env:USERNAME /it /f | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "PCRUN ERROR: schtasks /create failed ($LASTEXITCODE)."
        Write-Output "PCRUN ERROR: no interactive console session? check 'query session'."
        exit 91
    }
    schtasks /run /tn $TaskName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        schtasks /delete /tn $TaskName /f | Out-Null
        Write-Output "PCRUN ERROR: schtasks /run failed ($LASTEXITCODE)."
        exit 92
    }
}

$deadline = $started.AddSeconds($TimeoutSec)
while (-not (Test-Path -LiteralPath $done)) {
    if ((Get-Date) -gt $deadline) {
        if (-not $Direct) { schtasks /end /tn $TaskName 2>&1 | Out-Null
                            schtasks /delete /tn $TaskName /f 2>&1 | Out-Null }
        Write-Output "PCRUN TIMEOUT after ${TimeoutSec}s"
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
        exit 93
    }
    Start-Sleep -Milliseconds 500
}

if (-not $Direct) { schtasks /delete /tn $TaskName /f 2>&1 | Out-Null }

$rc = (Get-Content -LiteralPath $done -Raw).Trim()
$elapsed = [int]((Get-Date) - $started).TotalMilliseconds

if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
Write-Output "PCRUN RC=$rc ELAPSED_MS=$elapsed"

if ($rc -eq "0") { exit 0 } else { exit 1 }
