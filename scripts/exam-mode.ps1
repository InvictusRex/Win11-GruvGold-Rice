#Requires -Version 5.1
<#
    exam-mode.ps1 - Fully stop the rice before a proctored test, and disable
    autostart so a reboot mid-exam-window doesn't silently bring it back.

    AutoHotkey and Rainmeter are commonly blocklisted by name in proctoring
    software; komorebi/whkd (global keyboard hook + window-forcing WM) and
    masir (global mouse hook) are exactly the shape of thing behavioural
    anti-cheat checks look for even when not named explicitly.

      .\scripts\exam-mode.ps1          stop everything, disable autostart
      .\scripts\exam-mode.ps1 -Off     restore autostart, bring the rice back

    Idempotent either way.
#>

[CmdletBinding()]
param(
    [switch]$Off
)

$ErrorActionPreference = 'Continue'
$repo     = Split-Path $PSScriptRoot -Parent
$pwsh     = (Get-Command powershell.exe).Source
$startup  = [Environment]::GetFolderPath('Startup')
$lnk      = Join-Path $startup 'GruvGold - Startup.lnk'
$disabled = Join-Path $startup 'GruvGold - Startup.lnk.examdisabled'

function Say($msg, $colour = 'Gray') { Write-Host "  $msg" -ForegroundColor $colour }

# start.ps1 calls `exit`, which would kill this script's own session if invoked
# with `&` in-process - run it as a real child process instead. -Stop is waited
# on since the "still running" check right after depends on it being done; the
# plain restart on the way out is fire-and-forget (observed to hang indefinitely
# under -Wait here, and nothing downstream needs to block on it anyway).
function Invoke-Start([string]$argLine, [switch]$Wait) {
    $p = @{ FilePath = $pwsh; ArgumentList = "-ExecutionPolicy Bypass -File `"$repo\scripts\start.ps1`" $argLine"; WindowStyle = 'Hidden' }
    if ($Wait) { Start-Process @p -Wait } else { Start-Process @p }
}

if ($Off) {
    Write-Host "`nLeaving exam mode" -ForegroundColor Yellow

    if (Test-Path $disabled) {
        Move-Item $disabled $lnk -Force
        Say 'autostart re-enabled' 'Green'
    } else {
        Say 'autostart was not disabled by exam mode - left as-is' 'DarkGray'
    }

    Invoke-Start ''
    Say 'rice restarting now' 'Green'
    Write-Host ""
    exit 0
}

Write-Host "`nEntering exam mode" -ForegroundColor Yellow

Invoke-Start '-Stop' -Wait
Say 'rice stopped (komorebi restored your windows cleanly)' 'Green'

if (Test-Path $lnk) {
    Move-Item $lnk $disabled -Force
    Say 'autostart disabled - will not come back on reboot or re-login' 'Green'
} elseif (Test-Path $disabled) {
    Say 'autostart already disabled' 'DarkGray'
} else {
    Say 'no autostart shortcut found - nothing to disable' 'DarkGray'
}

Write-Host "`nChecking nothing is still running" -ForegroundColor Yellow
Start-Sleep -Seconds 2   # some processes (Flow Launcher) take a moment to fully exit
$watch   = 'yasb', 'komorebi', 'whkd', 'masir', 'Flow.Launcher', 'Rainmeter', 'TranslucentTB', 'AutoHotkey64', 'Everything'
# Session 0 is the Everything Windows service, which a non-elevated shell cannot
# stop; it draws no window and has no hooks, so it is not what a proctor looks for.
$stillUp = $watch | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne 0 } }
if ($stillUp) {
    Say "still running: $($stillUp -join ', ') - close these yourself before your test" 'Red'
} else {
    Say 'all clear - nothing from the rice is running' 'Green'
}

Write-Host "`nRun '.\scripts\exam-mode.ps1 -Off' afterwards to bring the rice back.`n" -ForegroundColor Cyan
