#Requires -Version 5.1
<#
    uninstall.ps1 - Full reversal of the rice.

    Written before install.ps1 on purpose: the exit exists before the entrance.

    By default this restores your desktop but LEAVES the applications installed
    (they are harmless when not running). Pass -RemovePackages to winget-uninstall
    them too - anything that was already on the machine before backup.ps1 ran is
    never touched, per <backup>\<stamp>\preinstalled.json.

    Backups are read from %LOCALAPPDATA%\GruvGoldRice-backup (see backup.ps1)
    and left in place afterwards.

    Usage:
      .\uninstall.ps1                    # stop + remove configs + restore settings
      .\uninstall.ps1 -RemovePackages    # the above, plus uninstall the apps
      .\uninstall.ps1 -From 20260926-120000  # restore from a specific backup
#>

[CmdletBinding()]
param(
    [string]$From,
    [switch]$RemovePackages
)

$ErrorActionPreference = 'Continue'
$backups = "$env:LOCALAPPDATA\GruvGoldRice-backup"   # written by backup.ps1

function Say($msg, $colour = 'Gray') { Write-Host "  $msg" -ForegroundColor $colour }

# ---------------------------------------------------------------- locate backup
$latestFile = Join-Path $backups 'LATEST'
if (-not $From -and (Test-Path $latestFile)) { $From = (Get-Content $latestFile -Raw).Trim() }
$src = if ($From) { Join-Path $backups $From } else { $null }

if ($src -and (Test-Path $src)) {
    Write-Host "`nRestoring from $src" -ForegroundColor Cyan
} else {
    Write-Host "`nNo backup found - will stop processes and unlink configs," -ForegroundColor Yellow
    Write-Host "but cannot restore your original wallpaper/taskbar settings.`n" -ForegroundColor Yellow
    $src = $null
}

# ---------------------------------------------------------------- 1. stop processes
Write-Host "`n[1/5] Stopping rice processes" -ForegroundColor Yellow

# komorebi must be stopped via its CLI so it restores window positions and
# removes the WS_EX_LAYERED styles it applied. Killing it leaves windows stranded.
if (Get-Command komorebic -ErrorAction SilentlyContinue) {
    & komorebic stop --whkd 2>&1 | Out-Null
    Say 'komorebic stop --whkd' 'Green'
}

foreach ($p in 'yasb', 'komorebi', 'whkd', 'masir', 'Flow.Launcher', 'Rainmeter', 'Nexus', 'AutoHotkey64', 'AutoHotkey', 'Everything') {
    $proc = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($proc) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue; Say "stopped $p" 'Green' }
}

# ---------------------------------------------------------------- 2. autostart
Write-Host "`n[2/5] Removing autostart entries" -ForegroundColor Yellow
$startup = [Environment]::GetFolderPath('Startup')
foreach ($lnk in Get-ChildItem $startup -Filter '*.lnk' -ErrorAction SilentlyContinue) {
    if ($lnk.BaseName -match 'yasb|komorebi|GruvGold|desktop-type|Flow Launcher|Rainmeter|Nexus') {
        Remove-Item $lnk.FullName -Force
        Say "removed $($lnk.Name)" 'Green'
    }
}
foreach ($name in 'yasb', 'komorebi', 'GruvGoldRice', 'Nexus') {
    $run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (Get-ItemProperty $run -Name $name -ErrorAction SilentlyContinue) {
        Remove-ItemProperty $run -Name $name -Force
        Say "removed Run\$name" 'Green'
    }
}

# ---------------------------------------------------------------- 3. our config files
Write-Host "`n[3/5] Removing rice configs" -ForegroundColor Yellow
$ourPaths = @(
    "$env:USERPROFILE\.config\yasb"
    "$env:USERPROFILE\komorebi.json"
    "$env:USERPROFILE\.config\komorebi"
    "$env:USERPROFILE\.config\whkdrc"
    "$env:APPDATA\FlowLauncher\Themes\GruvGold.xaml"
    "$env:APPDATA\FlowLauncher\Plugins\ExamMode"
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\GruvGold"
    "$env:USERPROFILE\Documents\Rainmeter\Skins\GruvGold"
    "$env:LOCALAPPDATA\GruvGoldRice"
    "$env:USERPROFILE\.config\fastfetch"
    "$env:USERPROFILE\.config\powershell"
)
foreach ($p in $ourPaths) {
    if (Test-Path $p) {
        # Remove-Item on a symlinked directory deletes the link, not the target,
        # only when -Recurse is absent. Use the .NET call to be certain.
        $item = Get-Item $p -Force
        if ($item.LinkType) {
            $item.Delete()
            Say "unlinked $p" 'Green'
        } else {
            Remove-Item $p -Recurse -Force
            Say "removed  $p" 'Green'
        }
    }
}
[Environment]::SetEnvironmentVariable('GRUVGOLD_NAME', $null, 'User')

# The profiles dot-source the gruvgold.ps1 just removed; without a backup to
# restore them from (step 4), every new shell would print an error.
foreach ($p in "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
               "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1") {
    $text = Get-Content $p -Raw -ErrorAction SilentlyContinue
    if ($text -match '# --- GruvGold (shell|exam mode) ---') {
        $text = $text -replace '(?m)\r?\n?^# --- GruvGold (shell|exam mode) ---\r?\n[^\r\n]*', ''
        [IO.File]::WriteAllText($p, $text.TrimEnd() + "`r`n", (New-Object System.Text.UTF8Encoding $true))
        Say "removed GruvGold lines from $(Split-Path $p -Leaf)" 'Green'
    }
}

# ---------------------------------------------------------------- 4. restore settings
Write-Host "`n[4/5] Restoring Windows settings" -ForegroundColor Yellow
if ($src) {
    foreach ($reg in Get-ChildItem $src -Filter '*.reg' -ErrorAction SilentlyContinue) {
        $null = & reg.exe import $reg.FullName 2>&1
        if ($LASTEXITCODE -eq 0) { Say "imported $($reg.Name)" 'Green' }
        else { Say "failed   $($reg.Name)" 'Red' }
    }

    # Restore backed-up config files to their original homes.
    $restore = @{
        'PowerShell5-profile.ps1' = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
        'PowerShell7-profile.ps1' = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
        'komorebi.json'           = "$env:USERPROFILE\komorebi.json"
        'whkdrc'                  = "$env:USERPROFILE\.config\whkdrc"
    }
    foreach ($name in $restore.Keys) {
        $f = Join-Path $src $name
        if (Test-Path $f) {
            New-Item -ItemType Directory -Path (Split-Path $restore[$name]) -Force | Out-Null
            Copy-Item $f $restore[$name] -Force
            Say "restored $name" 'Green'
        }
    }

    $state = Get-Content (Join-Path $src 'state.json') -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json

    # A .reg import re-adds values, but it never DELETES a value that we created
    # where none existed before. On a stock Windows 11 the taskbar keys are often
    # absent entirely (the defaults are implicit), so remove any we introduced.
    $advKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    foreach ($v in 'TaskbarAl', 'TaskbarGlomLevel') {
        $wasAbsent = $null -eq $state.$v -or '' -eq [string]$state.$v
        $existsNow = $null -ne (Get-ItemProperty $advKey -Name $v -ErrorAction SilentlyContinue)
        if ($wasAbsent -and $existsNow) {
            Remove-ItemProperty $advKey -Name $v -Force -ErrorAction SilentlyContinue
            Say "removed $v (absent before the rice)" 'Green'
        }
    }

    # Re-apply the wallpaper through the API so it takes effect without a logout.
    if ($state -and $state.wallpaper -and (Test-Path $state.wallpaper)) {
        Add-Type @'
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@ -ErrorAction SilentlyContinue
        [Wallpaper]::SystemParametersInfo(20, 0, $state.wallpaper, 3) | Out-Null
        Say "restored wallpaper" 'Green'
    }
} else {
    Say 'no backup to restore from - skipping' 'DarkYellow'
}

# ---------------------------------------------------------------- 5. packages
Write-Host "`n[5/5] Packages" -ForegroundColor Yellow
if ($RemovePackages) {
    $ours = @('AmN.yasb','LGUG2Z.komorebi','LGUG2Z.whkd','LGUG2Z.masir','Flow-Launcher.Flow-Launcher',
              'Rainmeter.Rainmeter','WinStep.Nexus','AutoHotkey.AutoHotkey',
              'JanDeDobbeleer.OhMyPosh','aristocratos.btop4win','voidtools.Everything','Fastfetch-cli.Fastfetch','RamenSoftware.Windhawk')
    # Microsoft.PowerShell is deliberately absent - too generally useful to rip out.

    $pre = @()
    $preFile = if ($src) { Join-Path $src 'preinstalled.json' } else { $null }
    if ($preFile -and (Test-Path $preFile)) {
        $pre = @(Get-Content $preFile -Raw | ConvertFrom-Json)
    }

    foreach ($id in $ours) {
        if ($pre -contains $id) { Say "kept     $id (was installed before the rice)" 'Cyan'; continue }
        $null = winget uninstall --id $id --exact --silent --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0) { Say "removed  $id" 'Green' } else { Say "skipped  $id" 'DarkGray' }
    }
} else {
    Say 'left installed (pass -RemovePackages to uninstall them)' 'DarkGray'
    Say 'Windhawk keeps running its Taskbar Styler: the taskbar stays reduced to the tray pill until you disable that mod in Windhawk.' 'DarkYellow'
    # Restoring Program Files needs admin, so this only says how.
    if (Test-Path "$env:ProgramFiles\YASB\lib\library.zip.gruvgold-backup") {
        Say 'YASB keeps the rice''s patches (harmless with a stock config). To restore stock YASB, in an ADMIN PowerShell run:' 'DarkYellow'
        Say "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path (Split-Path $PSScriptRoot -Parent) 'yasb\patch-yasb.ps1')`" -Restore" 'DarkYellow'
    }
}

# ---------------------------------------------------------------- finish
Write-Host "`nRestarting Explorer to apply taskbar changes..." -ForegroundColor Yellow
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }

Write-Host "`nDone. Desktop is back to stock Windows.`n" -ForegroundColor Green
