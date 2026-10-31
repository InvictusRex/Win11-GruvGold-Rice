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

$windhawk = (Get-Command windhawk.exe -ErrorAction SilentlyContinue).Source, "$env:ProgramFiles\Windhawk\windhawk.exe" | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

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

# Windhawk runs as a LocalSystem service that relaunches its elevated tray on every
# boot, so stopping or re-enabling it needs admin: one UAC prompt for just that step.
function Invoke-Elevated([string]$cmd, [string]$done, [switch]$Wait) {
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $p = @{ FilePath = $pwsh; ArgumentList = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"; Verb = 'RunAs'; WindowStyle = 'Hidden'; ErrorAction = 'Stop' }
    try {
        if ($Wait) { Start-Process @p -Wait } else { Start-Process @p }
        Say $done 'Green'
    } catch { Say 'UAC prompt declined - Windhawk left as-is' 'Red' }
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
    $svc = Get-Service Windhawk -ErrorAction SilentlyContinue
    if ($svc -and ($svc.StartType -eq 'Disabled' -or $svc.Status -ne 'Running')) {
        # Starting the service mid-session may not bring the tray up on its own, so launch it if missing.
        Invoke-Elevated "Set-Service Windhawk -StartupType Automatic; Start-Service Windhawk; Start-Sleep 2; if (-not (Get-Process windhawk -EA 0 | ? SessionId -ne 0)) { & '$windhawk' -tray-only }" 'Windhawk re-enabled and restarting'
    }
    Write-Host ""
    exit 0
}

Write-Host "`nEntering exam mode" -ForegroundColor Yellow

Invoke-Start '-Stop' -Wait
Say 'rice stopped (komorebi restored your windows cleanly)' 'Green'

# Windhawk injects into explorer.exe; -exit unloads its mods. Proctoring tools flag injection.
# Disabling the service is what keeps it from coming back on reboot.
if (Get-Service Windhawk -ErrorAction SilentlyContinue) {
    Invoke-Elevated "& '$windhawk' -exit -wait; Set-Service Windhawk -StartupType Disabled; Stop-Service Windhawk -Force -EA 0; Get-Process windhawk -EA 0 | Stop-Process -Force" 'Windhawk stopped and its service disabled' -Wait
}

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
$watch   = 'yasb', 'komorebi', 'whkd', 'masir', 'Flow.Launcher', 'Rainmeter', 'Nexus', 'AutoHotkey64', 'Everything', 'windhawk'
# Session 0 is the Everything Windows service, which a non-elevated shell cannot
# stop; it draws no window and has no hooks, so it is not what a proctor looks for.
$stillUp = $watch | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne 0 } }
if ($stillUp) {
    Say "still running: $($stillUp -join ', ') - close these yourself before your test" 'Red'
} else {
    Say 'all clear - nothing from the rice is running' 'Green'
}

Write-Host "`nRun '.\scripts\exam-mode.ps1 -Off' afterwards to bring the rice back.`n" -ForegroundColor Cyan
