<#
.SYNOPSIS
    Test whether the panel follows brightness writes, then restore the original value.

.DESCRIPTION
    WHAT THIS SCRIPT DOES
      - Reads your current brightness and remembers it.
      - Sets 90%, 10% and 60%, waiting three seconds between each step.
      - Restores your original brightness when it finishes.

    WATCH THE SCREEN WHILE IT RUNS.
      Screen changes      -> brightness control works end to end.
      Screen never changes -> the value reaches the driver but not the panel.

    It changes only the current brightness. No setting, driver or registry
    value is modified, and the original value is put back at the end.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verify-brightness.ps1
#>

$ErrorActionPreference = 'Stop'

$methods = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods
if (-not $methods) {
    Write-Host "No brightness interface found on this display." -ForegroundColor Red
    Write-Host "Run diagnose-brightness.ps1 first." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$original = (Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness).CurrentBrightness

Write-Host "This will change your screen brightness for about 10 seconds." -ForegroundColor Yellow
Write-Host ("Current brightness: {0}%. It will be restored at the end." -f $original) -ForegroundColor Yellow
Write-Host "Watch the screen while it runs."
$null = Read-Host "Press Enter to start, or close the window to cancel"

try {
    foreach ($value in 90, 10, 60) {
        Invoke-CimMethod -InputObject $methods -MethodName WmiSetBrightness `
            -Arguments @{Timeout = 1; Brightness = $value} | Out-Null
        $now = (Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness).CurrentBrightness
        Write-Host ("  set {0,3}%  ->  recorded {1,3}%" -f $value, $now)
        Start-Sleep -Seconds 3
    }
} finally {
    Invoke-CimMethod -InputObject $methods -MethodName WmiSetBrightness `
        -Arguments @{Timeout = 1; Brightness = $original} | Out-Null
    Write-Host ("  restored {0}%" -f $original) -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Did the screen change?" -ForegroundColor Cyan
Write-Host "  Yes -> brightness works. The problem is elsewhere; see the README fallback list."
Write-Host "  No  -> values reach the driver but not the panel." -ForegroundColor Yellow
Write-Host "         Run fix-install-extension.ps1 from an elevated PowerShell."
Read-Host "Press Enter to exit"
