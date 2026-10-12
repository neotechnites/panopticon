# install_virtual_monitor.ps1 : the capture-only virtual monitor for `content capture --mode final`.
# NOT RUN: installing a display driver on the PC needs Ryan's OK first. Run once, elevated, in the console session.
#
#   powershell -ExecutionPolicy Bypass -File install_virtual_monitor.ps1 [-Uninstall]
#
# Adds one IddCx virtual display (VirtualDrivers/Virtual-Display-Driver, signed) offering 1080x1920 and
# 1920x1080, extended to the right of the main screen, taskbar on the main screen only, wallpaper solid
# #FF00FF on it alone (G3's desktop detector). capture.ps1 finds it by its size; nothing else changes.
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$Version = '24.12.24'                  # pinned release of Virtual-Display-Driver
$Zip = "https://github.com/VirtualDrivers/Virtual-Display-Driver/releases/download/$Version/Signed-Driver-v$Version-x64.zip"
$Nefcon = 'https://github.com/nefarius/nefcon/releases/download/v1.10.0/nefcon_v1.10.0.zip'
$Root = 'C:\VirtualDisplayDriver'
$HwId = 'Root\MttVDD'
$DisplayClass = '{4d36e968-e325-11ce-bfc1-08002be10318}'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'run elevated: a driver install needs admin' }
New-Item -ItemType Directory -Force -Path $Root | Out-Null
if (-not (Test-Path "$Root\nefconw.exe")) {
  Invoke-WebRequest $Nefcon -OutFile "$Root\nefcon.zip"; Expand-Archive "$Root\nefcon.zip" "$Root\nefcon" -Force
  Copy-Item (Get-ChildItem "$Root\nefcon" -Recurse -Filter nefconw.exe | Where-Object FullName -like '*x64*' | Select-Object -First 1).FullName "$Root\nefconw.exe"
}
if ($Uninstall) {
  & "$Root\nefconw.exe" --remove-device-node --hardware-id $HwId --class-guid $DisplayClass
  Write-Output 'virtual monitor removed'; exit 0
}

# The driver reads its monitors and modes from here: one monitor, the two capture sizes only.
@"
<?xml version='1.0' encoding='utf-8'?>
<vdd_settings>
  <monitors><count>1</count></monitors>
  <gpu><friendlyname>default</friendlyname></gpu>
  <global><g_refresh_rate>60</g_refresh_rate></global>
  <resolutions>
    <resolution><width>1080</width><height>1920</height><refresh_rate>60</refresh_rate></resolution>
    <resolution><width>1920</width><height>1080</height><refresh_rate>60</refresh_rate></resolution>
  </resolutions>
  <options><HDRPlus>false</HDRPlus><SDR10bit>false</SDR10bit><CustomEdid>false</CustomEdid></options>
</vdd_settings>
"@ | Set-Content "$Root\vdd_settings.xml" -Encoding UTF8

Invoke-WebRequest $Zip -OutFile "$Root\vdd.zip"; Expand-Archive "$Root\vdd.zip" "$Root\vdd" -Force
$inf = (Get-ChildItem "$Root\vdd" -Recurse -Filter MttVDD.inf | Select-Object -First 1).FullName
$cat = Get-ChildItem "$Root\vdd" -Recurse -Filter *.cer | Select-Object -First 1
if ($cat) { Import-Certificate -FilePath $cat.FullName -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null }
& "$Root\nefconw.exe" --create-device-node --hardware-id $HwId --class-name Display --class-guid $DisplayClass
& "$Root\nefconw.exe" --install-driver --inf-path $inf
Start-Sleep -Seconds 5

# Taskbar on the main screen only.
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name MMTaskbarEnabled -Value 0

Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDesktopWallpaper {
  void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
  [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
  [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint monitorIndex);
  uint GetMonitorDevicePathCount();
  void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID, out RECT rect);
}
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")] public class DesktopWallpaperClass { }
'@
# Solid magenta on the virtual monitor alone; the main screen keeps its wallpaper.
$bmp = New-Object System.Drawing.Bitmap 64, 64
$gfx = [System.Drawing.Graphics]::FromImage($bmp); $gfx.Clear([System.Drawing.Color]::FromArgb(255, 0, 255)); $gfx.Dispose()
$bmp.Save("$Root\magenta.bmp", [System.Drawing.Imaging.ImageFormat]::Bmp)
$dw = [IDesktopWallpaper](New-Object DesktopWallpaperClass)
$main = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
for ($i = 0; $i -lt $dw.GetMonitorDevicePathCount(); $i++) {
  $id = $dw.GetMonitorDevicePathAt($i); $r = New-Object RECT; $dw.GetMonitorRECT($id, [ref]$r)
  if ($r.Left -ne $main.X -or $r.Top -ne $main.Y) { if ($id -match 'MttVDD|VDD') { $dw.SetWallpaper($id, "$Root\magenta.bmp") } }
}

[System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.DeviceName) $($_.Bounds) primary=$($_.Primary)" }
Write-Output 'virtual monitor installed: capture --mode final picks it by size (1080x1920 or 1920x1080)'
