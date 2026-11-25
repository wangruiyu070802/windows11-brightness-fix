<#
.SYNOPSIS
    Reinstall the OEM graphics extension driver offered by Windows Update.

.DESCRIPTION
    WHAT THIS SCRIPT DOES
      1. Finds your Intel display adapter and its hardware ID.
      2. Searches Windows Update for a driver update of class "Extension"
         whose hardware ID matches that adapter.
      3. Shows you exactly what it found and asks before doing anything.
      4. Downloads and installs that single package.
      5. Prints how to remove it again.

    It installs one driver package and nothing else. Your files are not touched.
    Requires an elevated PowerShell window.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\fix-install-extension.ps1
#>

$ErrorActionPreference = 'Stop'

function Test-Elevated {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Elevated)) {
    Write-Host "This script must run from an elevated PowerShell window." -ForegroundColor Red
    Write-Host "Right-click Start > Terminal (Admin), then run it again." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "This script installs a driver package from Windows Update." -ForegroundColor Yellow
Write-Host "It will show you what it found and ask before installing." -ForegroundColor Yellow
Write-Host ""

$adapters = Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -match 'VEN_8086' }
if (-not $adapters) {
    Write-Host "No Intel display adapter found." -ForegroundColor Red
    Write-Host "This script targets Intel graphics. See the README for other vendors." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Display adapter(s):" -ForegroundColor Cyan
foreach ($a in $adapters) {
    Write-Host ("  {0}" -f $a.Name)
    Write-Host ("    {0}" -f $a.PNPDeviceID)
}

Write-Host ""
Write-Host "Searching Windows Update for driver updates..."
$session  = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$result   = $searcher.Search("IsInstalled=0 and Type='Driver'")

$target = $null
foreach ($u in $result.Updates) {
    if ($u.DriverClass -ne 'Extension') { continue }
    $hwid = ([string]$u.DriverHardwareID).ToLower()
    if (-not $hwid) { continue }
    foreach ($a in $adapters) {
        $adapterId = ([string]$a.PNPDeviceID).ToLower()
        if ($adapterId.StartsWith($hwid)) { $target = $u }
    }
}

if (-not $target) {
    Write-Host ""
    Write-Host "No matching Extension driver update was offered." -ForegroundColor Yellow
    Write-Host "Driver updates that are available:" -ForegroundColor Yellow
    if ($result.Updates.Count -eq 0) {
        Write-Host "  None."
    } else {
        foreach ($u in $result.Updates) {
            Write-Host ("  [{0}] {1}" -f $u.DriverClass, $u.Title)
            Write-Host ("        HWID: {0}" -f $u.DriverHardwareID)
        }
    }
    Write-Host ""
    Write-Host "Try Settings > Windows Update > Advanced options > Optional updates," -ForegroundColor Yellow
    Write-Host "or install the OEM graphics driver from your laptop vendor." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "Package found:" -ForegroundColor Green
Write-Host ("  Title : {0}" -f $target.Title)
Write-Host ("  Class : {0}" -f $target.DriverClass)
Write-Host ("  HWID  : {0}" -f $target.DriverHardwareID)
Write-Host ""
Write-Host "This will install one driver package from Windows Update." -ForegroundColor Yellow
Write-Host "It can be removed later with pnputil (instructions are printed at the end)." -ForegroundColor Yellow
$answer = Read-Host "Type Y to install, anything else to cancel"
if ($answer -notmatch '^[Yy]') {
    Write-Host "Cancelled. Nothing was changed." -ForegroundColor DarkGray
    Read-Host "Press Enter to exit"
    exit 0
}

$collection = New-Object -ComObject Microsoft.Update.UpdateColl
$collection.Add($target) | Out-Null

Write-Host "Downloading..." -ForegroundColor Cyan
$downloader = $session.CreateUpdateDownloader()
$downloader.Updates = $collection
$download = $downloader.Download()
Write-Host ("  Download result: {0}  (2 = success)" -f $download.ResultCode)

Write-Host "Installing..." -ForegroundColor Cyan
$installer = $session.CreateUpdateInstaller()
$installer.Updates = $collection
$install = $installer.Install()
Write-Host ("  Install result : {0}  (2 = success)" -f $install.ResultCode)
Write-Host ("  Reboot needed  : {0}" -f $install.RebootRequired)

Write-Host ""
if ($install.ResultCode -eq 2) {
    Write-Host "Installed. Test the brightness slider. Reboot if it still does nothing." -ForegroundColor Green
} else {
    Write-Host "Install did not report success. Check Windows Update history." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "To remove it later, run these two commands from an elevated window:" -ForegroundColor DarkGray
Write-Host "  pnputil /enum-drivers | Select-String -Pattern 'iigd_ext' -Context 0,6" -ForegroundColor DarkGray
Write-Host "  pnputil /delete-driver oemNN.inf /uninstall" -ForegroundColor DarkGray
Write-Host "(replace oemNN.inf with the Published Name shown by the first command)" -ForegroundColor DarkGray
Read-Host "Press Enter to exit"
