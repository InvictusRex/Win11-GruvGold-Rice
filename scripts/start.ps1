#Requires -Version 5.1
<#
    start.ps1 - Bring the rice up (or down).

      .\start.ps1              start everything that is not already running
      .\start.ps1 -Stop        stop everything
      .\start.ps1 -Restart     stop, then start
      .\start.ps1 -Autostart   also register everything to start at login
      .\start.ps1 -NoTiling    start everything except komorebi

    Idempotent: a component already running is left alone.
#>

[CmdletBinding()]
param(
    [switch]$Stop,
    [switch]$Restart,
    [switch]$Autostart,
    [switch]$NoTiling,
    # Only meant for the autostart shortcut below. Windows fires every Startup-folder
    # item at once, before Explorer's shell and the network stack have settled - that
    # burst is what made YASB's wifi widget render its raw "{ethernet_icon}" template
    # and left a stray Explorer window holding focus (and the bar's centre pill) for
    # several seconds. A few seconds' head start avoids the pile-up.
    [int]$Delay = 0
)

if ($Delay -gt 0) { Start-Sleep -Seconds $Delay }

$ErrorActionPreference = 'Continue'
$repo = Split-Path $PSScriptRoot -Parent   # scripts/ lives one level below the repo root

function Say($msg, $colour = 'Gray') { Write-Host "  $msg" -ForegroundColor $colour }

# A shell opened before the installers ran holds a stale PATH, and every process
# we launch inherits it - which is how YASB ends up unable to find komorebic.
# Rebuild PATH from the registry so children get the real one.
$env:Path = (
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User')
) -join ';'

# Resolve a binary from PATH, falling back to its known install location.
# Right after winget installs, PATH in an existing shell is stale.
function Find-Exe($name, [string[]]$fallbacks) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($f in $fallbacks) {
        $expanded = [Environment]::ExpandEnvironmentVariables($f)
        if (Test-Path $expanded) { return $expanded }
        # glob (Flow Launcher installs under a versioned app-x.y.z folder)
        $hit = Get-Item $expanded -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

$bin = @{
    # yasb.exe is the bar; yasbc.exe is the CLI, which just prints help and exits.
    # Resolve the real binary by path first so a yasbc on PATH cannot win.
    yasb        = Find-Exe '___nonexistent___' @('%ProgramFiles%\YASB\yasb.exe', '%LOCALAPPDATA%\Programs\YASB\yasb.exe')
    komorebic   = Find-Exe 'komorebic' @('%ProgramFiles%\komorebi\bin\komorebic.exe', '%LOCALAPPDATA%\Microsoft\WinGet\Links\komorebic.exe')
    flow        = Find-Exe 'Flow.Launcher' @('%LOCALAPPDATA%\FlowLauncher\Flow.Launcher.exe', '%LOCALAPPDATA%\FlowLauncher\app-*\Flow.Launcher.exe')
    rainmeter   = Find-Exe 'Rainmeter' @('%ProgramFiles%\Rainmeter\Rainmeter.exe')
    # TranslucentTB ships from the Store as an MSIX; its execution alias is
    # ttb.exe inside a package-family folder, not TranslucentTB.exe.
    ttb         = Find-Exe 'ttb' @('%LOCALAPPDATA%\Microsoft\WindowsApps\28017CharlesMilette.TranslucentTB_v826wp6bftszj\ttb.exe', '%LOCALAPPDATA%\Microsoft\WindowsApps\ttb.exe')
    ahk         = Find-Exe 'AutoHotkey64' @('%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe', '%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe', '%ProgramFiles%\AutoHotkey\AutoHotkey64.exe')
    masir       = Find-Exe 'masir' @('%ProgramFiles%\masir\bin\masir.exe')
    everything  = Find-Exe 'Everything' @('%ProgramFiles%\Everything\Everything.exe', '%ProgramFiles(x86)%\Everything\Everything.exe')
}

$ahkScript = "$env:LOCALAPPDATA\GruvGoldRice\desktop-type-to-launch.ahk"

# ================================================================= stop
if ($Stop -or $Restart) {
    Write-Host "`nStopping" -ForegroundColor Yellow

    # komorebi must go down via its CLI so it untiles windows and clears the
    # extended styles it set. Killing the process strands your windows.
    if ($bin.komorebic -and (Get-Process komorebi -ErrorAction SilentlyContinue)) {
        & $bin.komorebic stop --whkd 2>&1 | Out-Null
        Say 'komorebi stopped cleanly' 'Green'
    }
    foreach ($p in 'yasb', 'whkd', 'Flow.Launcher', 'Rainmeter', 'TranslucentTB', 'AutoHotkey64', 'masir', 'Everything') {
        $proc = Get-Process -Name $p -ErrorAction SilentlyContinue
        if ($proc) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue; Say "stopped $p" 'Green' }
    }
    if (-not $Restart) { Write-Host "" ; exit 0 }
    Start-Sleep -Seconds 1
}

# ================================================================= start
Write-Host "`nStarting" -ForegroundColor Yellow

function Launch($label, $exe, $argList, $procName) {
    if (-not $exe) { Say "$label - binary not found, skipped" 'Red'; return }
    if ($procName -and (Get-Process -Name $procName -ErrorAction SilentlyContinue)) {
        Say "$label already running" 'DarkGray'; return
    }
    try {
        if ($argList) { Start-Process -FilePath $exe -ArgumentList $argList -WindowStyle Hidden }
        else          { Start-Process -FilePath $exe -WindowStyle Hidden }
        Say "$label started" 'Green'
    } catch { Say "$label failed: $($_.Exception.Message)" 'Red' }
}

# Everything also runs as a session-0 Windows service, which Flow Launcher's IPC
# cannot reach - only count the instance in this user's session as "already running".
$mySession = (Get-Process -Id $PID).SessionId
if (Get-Process Everything -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $mySession }) {
    Say 'Everything already running' 'DarkGray'
} else {
    Launch 'Everything' $bin.everything '-startup' $null
}
Launch 'TranslucentTB'  $bin.ttb       $null                     'TranslucentTB'
Launch 'YASB'           $bin.yasb      $null                     'yasb'
Launch 'Flow Launcher'  $bin.flow      $null                     'Flow.Launcher'
Launch 'Rainmeter'      $bin.rainmeter $null                     'Rainmeter'

if (Test-Path $ahkScript) {
    Launch 'desktop hook' $bin.ahk "`"$ahkScript`"" 'AutoHotkey64'
} else { Say "desktop hook - script not deployed, run apply.ps1" 'DarkYellow' }

if (-not $NoTiling) {
    if ($bin.komorebic) {
        if (Get-Process komorebi -ErrorAction SilentlyContinue) { Say 'komorebi already running' 'DarkGray' }
        else {
            # --config is required: komorebic does NOT pick up ~/komorebi.json on its
            # own, and without it you silently get default borders and no rules.
            & $bin.komorebic start --whkd --config "$env:USERPROFILE\komorebi.json" 2>&1 | Out-Null
            Start-Sleep -Seconds 3
            if (Get-Process komorebi -ErrorAction SilentlyContinue) {
                Say 'komorebi started' 'Green'

                # komorebi 0.1.41 does not pick up border_colours from komorebi.json,
                # so set them over the CLI once it is up. border-implementation must be
                # Komorebi, otherwise it defers to the Windows accent colour and every
                # border-colour call is silently ignored.
                & $bin.komorebic border-implementation komorebi 2>&1 | Out-Null
                & $bin.komorebic border --enable                  2>&1 | Out-Null
                & $bin.komorebic border-width 1                   2>&1 | Out-Null
                & $bin.komorebic border-offset -1                 2>&1 | Out-Null
                & $bin.komorebic border-colour 131 165 152 -w single    2>&1 | Out-Null   # #83A598 muted blue-grey
                & $bin.komorebic border-colour 250 189 47  -w stack     2>&1 | Out-Null   # #FABD2F
                & $bin.komorebic border-colour 254 128 25  -w monocle   2>&1 | Out-Null   # #FE8019
                & $bin.komorebic border-colour 131 165 152 -w floating  2>&1 | Out-Null   # #83A598
                & $bin.komorebic border-colour 40  36  33  -w unfocused 2>&1 | Out-Null   # #282421
                Say 'borders set to the GruvGold palette' 'Green'

                # mouse_follows_focus defaults to true and warps the cursor to the
                # newly focused window on every focus change (Alt+Tab, cycle-stack,
                # any focus keybind). Setting it false in komorebi.json alone hasn't
                # proven reliable for other fields on this build, so it's set here too.
                & $bin.komorebic mouse-follows-focus disable 2>&1 | Out-Null

                # Every window-owning process gets an invisible IME helper window
                # (class MSCTFIME UI / IME). If komorebi tiles one of these before an
                # app has fully closed, it's left with a full-screen accent border
                # and nothing visibly behind it. Excluding the classes fixes this for
                # every app, not just the launchers below.
                & $bin.komorebic ignore-rule class "MSCTFIME UI" 2>&1 | Out-Null
                & $bin.komorebic ignore-rule class "IME" 2>&1 | Out-Null

                # Game launchers (32-bit, WOW64) don't get excluded reliably via the
                # ignore_rules in komorebi.json - same class of bug as border_colours
                # above, just for a different field. Applying the equivalent rule
                # over the CLI at startup works instead; -path (not -exe) because the
                # exe-name match also silently failed to apply for these specifically.
                & $bin.komorebic ignore-rule path "C:\Program Files (x86)\GOG Galaxy\GalaxyClient.exe" 2>&1 | Out-Null
                & $bin.komorebic ignore-rule path "C:\Program Files (x86)\Steam\Steam.exe" 2>&1 | Out-Null
                & $bin.komorebic ignore-rule path "C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe" 2>&1 | Out-Null
                & $bin.komorebic ignore-rule path "C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe" 2>&1 | Out-Null
                & $bin.komorebic ignore-rule path "E:\Riot Games\Riot Client\RiotClientServices.exe" 2>&1 | Out-Null
                & $bin.komorebic ignore-rule path "$env:USERPROFILE\AppData\Roaming\.minecraft\TLauncher.exe" 2>&1 | Out-Null
                & $bin.komorebic ignore-rule path "$env:LOCALAPPDATA\Programs\Paradox Interactive\launcher\bootstrapper-v2.exe" 2>&1 | Out-Null
                & $bin.komorebic retile 2>&1 | Out-Null   # release any of the above already open at startup
                Say 'game launchers excluded from tiling' 'Green'

                # masir replaces komorebi's own deprecated focus-follows-mouse -
                # hover a tiled window to focus it. It reads komorebi's own
                # known-hwnds file, so it must start after komorebi is up.
                Launch 'masir (hover-to-focus)' $bin.masir $null 'masir'
            }
            else { Say 'komorebi failed to start - run "komorebic start --whkd" to see why' 'Red' }
        }
    } else { Say 'komorebic not found, skipped' 'Red' }
} else { Say 'komorebi skipped (-NoTiling)' 'DarkGray' }

# Rainmeter loads its skins from its own config; activate ours explicitly so a
# fresh install shows them without the user touching the Rainmeter UI.
if ($bin.rainmeter) {
    Start-Sleep -Milliseconds 800
    & $bin.rainmeter '!ActivateConfig' 'GruvGold\Clock' 'Clock.ini' 2>&1 | Out-Null
    & $bin.rainmeter '!ActivateConfig' 'GruvGold\Visualizer' 'Visualizer.ini' 2>&1 | Out-Null
    Say 'Rainmeter skins activated' 'Green'
}

# ================================================================= autostart
# One shortcut that re-runs this script, not one shortcut per app. Six
# independent Startup entries all launch at once with no ordering and no
# wait for Explorer/network to settle - that burst was the actual cause of
# the slow-to-paint bar, the stray focused Explorer window, and the wifi
# widget showing its raw template. Re-running start.ps1 keeps the ordering
# and sleeps already coded above (TranslucentTB -> YASB -> ... -> komorebi).
if ($Autostart) {
    Write-Host "`nRegistering autostart" -ForegroundColor Yellow
    $startup = [Environment]::GetFolderPath('Startup')
    $shell   = New-Object -ComObject WScript.Shell
    $pwsh    = (Get-Command powershell.exe).Source

    # The copy apply.ps1 installed, not this file: the repo clone may move.
    $installed = "$env:LOCALAPPDATA\GruvGoldRice\scripts\start.ps1"
    if (-not (Test-Path $installed)) { Say 'start.ps1 not installed yet - run apply.ps1 first' 'Red'; exit 1 }

    Get-ChildItem (Join-Path $startup 'GruvGold - *.lnk') -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $args = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installed`" -Delay 5"
    if ($NoTiling) { $args += ' -NoTiling' }

    $lnk = $shell.CreateShortcut((Join-Path $startup 'GruvGold - Startup.lnk'))
    $lnk.TargetPath = $pwsh
    $lnk.Arguments  = $args
    $lnk.WindowStyle = 7          # minimised
    $lnk.Save()
    Say 'GruvGold - Startup.lnk' 'Green'
    Say 'uninstall.ps1 removes this' 'DarkGray'
}

Write-Host ""
exit 0
