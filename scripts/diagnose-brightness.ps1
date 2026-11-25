<#
.SYNOPSIS
    Read-only diagnosis for "brightness slider moves but the screen does not change".

.DESCRIPTION
    Prints seven checks in the order they should be read. Nothing is modified:
    no setting is changed, no driver is installed, no value is written.

      [1] Brightness interface     - can Windows see a brightness control at all?
      [2] Display adapters         - which GPU and driver version are in use?
      [3] Problem devices          - is anything reporting an error?
      [4] Monitors                 - which panel is Windows talking to?
      [5] OEM extension drivers    - is the OEM adaptation package installed?
      [6] Driver install history   - what changed recently? (Intel DSA, if present)
      [7] Windows Update drivers   - is a matching extension available?

    Read the "WHAT THIS MEANS" line under each section before moving on.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\diagnose-brightness.ps1
#>

$ErrorActionPreference = 'SilentlyContinue'

function Write-Section([string]$Title) {
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Write-Hint([string]$Text) {
    Write-Host ("    -> {0}" -f $Text) -ForegroundColor DarkGray
}

Write-Host "READ-ONLY DIAGNOSIS. Nothing will be changed by this script." -ForegroundColor Green

Write-Section '1. Brightness interface'
$monitors = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness
if ($monitors) {
    foreach ($item in $monitors) {
        Write-Host ("  Monitor : {0}" -f $item.InstanceName)
        Write-Host ("  Current : {0}%" -f $item.CurrentBrightness)
        Write-Host ("  Levels  : {0}" -f $item.Levels)
    }
    Write-Hint 'Interface exists. Continue with step 2 (write a value).'
} else {
    Write-Host "  WmiMonitorBrightness is not available." -ForegroundColor Red
    Write-Hint 'The display driver exposes no brightness interface.'
    Write-Hint 'Check Device Manager > Display adapters, then reinstall the GPU driver.'
}

Write-Section '2. Display adapters'
Get-CimInstance Win32_VideoController | ForEach-Object {
    Write-Host ("  {0}" -f $_.Name)
    Write-Host ("    Driver : {0}  ({1})" -f $_.DriverVersion, $_.DriverDate)
    Write-Host ("    PNP ID : {0}" -f $_.PNPDeviceID)
}
Write-Hint 'If this says "Microsoft Basic Display Adapter", the real GPU driver is missing.'

Write-Section '3. Problem devices'
$bad = Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' }
if ($bad) {
    foreach ($d in $bad) {
        Write-Host ("  {0} | {1} | {2}" -f $d.Status, $d.Class, $d.FriendlyName)
    }
    Write-Hint 'A device with an error code may explain the missing brightness control.'
} else {
    Write-Host "  None."
    Write-Hint 'No hardware errors. The fault is likely a software/configuration gap.'
}

Write-Section '4. Monitors (including disconnected ones)'
Get-PnpDevice -Class Monitor | ForEach-Object {
    $last = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_LastArrivalDate').Data
    Write-Host ("  {0} | {1} | last arrival: {2}" -f $_.Status, $_.FriendlyName, $last)
}
Write-Hint 'If an external monitor is connected, unplug it and retry before going further.'

Write-Section '5. OEM extension drivers'
$raw = pnputil /enum-drivers | Out-String
$blocks = $raw -split "(?m)^\s*$"
$found = @()
foreach ($blk in $blocks) {
    if ($blk -notmatch 'Class Name:\s*Extension') { continue }
    if ($blk -notmatch 'Intel|AMD|NVIDIA') { continue }
    $pub  = [regex]::Match($blk, 'Published Name:\s*(\S+)').Groups[1].Value
    $orig = [regex]::Match($blk, 'Original Name:\s*(\S+)').Groups[1].Value
    $ver  = [regex]::Match($blk, 'Driver Version:\s*(.+)').Groups[1].Value.Trim()
    $found += [pscustomobject]@{ Published = $pub; Original = $orig; Version = $ver }
    Write-Host ("  {0} | {1} | {2}" -f $pub, $orig, $ver)
}
if ($found.Count -eq 0) {
    Write-Host "  No vendor display extension driver found." -ForegroundColor Yellow
    Write-Hint 'This is a likely cause. Check section 7 for a matching update.'
} else {
    Write-Hint 'An extension driver is present. If brightness still fails, see the README fallback list.'
}

Write-Section '6. Driver install history (Intel DSA, if installed)'
$hist = 'C:\ProgramData\Intel\DSA\Data\install-history.json'
if (Test-Path $hist) {
    try {
        $json = Get-Content $hist -Raw | ConvertFrom-Json
        $json | Where-Object { $_.Name -match 'Graphics' } | Select-Object -First 8 | ForEach-Object {
            Write-Host ("  {0}  {1}  {2}" -f $_.Timestamp, $_.Version, $_.Status)
        }
        Write-Hint 'Compare the newest entry with when the problem started.'
    } catch {
        Write-Host ("  Could not read install history: {0}" -f $_.Exception.Message)
    }
} else {
    Write-Host "  Not found (Intel DSA is not installed, or this is not an Intel system)."
}

Write-Section '7. Driver updates offered by Windows Update'
try {
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result   = $searcher.Search("IsInstalled=0 and Type='Driver'")
    if ($result.Updates.Count -eq 0) {
        Write-Host "  None."
        Write-Hint 'Nothing to reinstall from here. Use the OEM driver package instead.'
    } else {
        foreach ($u in $result.Updates) {
            $badge = 'other'
            if ($u.DriverClass -eq 'Extension') { $badge = 'EXTENSION' }
            Write-Host ("  [{0}] {1}" -f $badge, $u.Title)
            Write-Host ("        HWID: {0}" -f $u.DriverHardwareID)
        }
        Write-Hint 'Install the Extension entry whose HWID matches your GPU PNP ID.'
        Write-Hint 'Run scripts\fix-install-extension.ps1 from an elevated window to do that.'
    }
} catch {
    Write-Host ("  Search failed: {0}" -f $_.Exception.Message)
}

Write-Host ""
Write-Host "Done. Nothing was changed." -ForegroundColor Green
Write-Host "Next: run verify-brightness.ps1 to test whether the panel responds." -ForegroundColor Green
