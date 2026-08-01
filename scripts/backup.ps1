#Requires -Version 5.1
<#
    backup.ps1 - Run this FIRST, before any other script in this repo.

    Captures everything the rice will change so uninstall.ps1 can put it back:
      1. A System Restore point (best effort - see notes below).
      2. The registry values we are about to modify.
      3. Existing config files we might overwrite.
      4. The current wallpaper path and taskbar settings, as plain text.

    Safe to run repeatedly; each run lands in its own timestamped folder under
    %LOCALAPPDATA%\GruvGoldRice-backup. That is outside the repo clone, so
    deleting or re-cloning the repo never loses it, and outside the rice's own
    folder, which uninstall.ps1 deletes.
#>

[CmdletBinding()]
param(
    [switch]$SkipRestorePoint
)

$ErrorActionPreference = 'Stop'
$root  = "$env:LOCALAPPDATA\GruvGoldRice-backup"
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dest  = Join-Path $root $stamp
New-Item -ItemType Directory -Path $dest -Force | Out-Null

function Say($msg, $colour = 'Gray') { Write-Host "  $msg" -ForegroundColor $colour }
Write-Host "`nBacking up to $dest" -ForegroundColor Cyan

# ---------------------------------------------------------------- 1. restore point
# System Protection is off by default on many Windows 11 installs, and Windows
# throttles restore points to one per 24h. Neither is fatal - we report and move on,
# because the registry/config backups below are what uninstall.ps1 actually uses.
if (-not $SkipRestorePoint) {
    Write-Host "`n[1/4] System Restore point" -ForegroundColor Yellow
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Say "skipped - needs an elevated shell. Re-run as admin for this step." 'DarkYellow'
    }
    else {
        try {
            $drive = $env:SystemDrive
            Enable-ComputerRestore -Drive "$drive\" -ErrorAction SilentlyContinue

            # Lift the 24h throttle just for this call, then put it back.
            $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
            $prior = (Get-ItemProperty $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
            New-ItemProperty $srKey -Name SystemRestorePointCreationFrequency -Value 0 -PropertyType DWord -Force | Out-Null

            Checkpoint-Computer -Description 'pre-rice' -RestorePointType 'MODIFY_SETTINGS'
            Say "created restore point 'pre-rice'" 'Green'

            if ($null -ne $prior) {
                Set-ItemProperty $srKey -Name SystemRestorePointCreationFrequency -Value $prior
            } else {
                Remove-ItemProperty $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
            }
        }
        catch {
            Say "could not create one: $($_.Exception.Message)" 'DarkYellow'
            Say "Not fatal. The registry backup below is what uninstall.ps1 relies on." 'DarkYellow'
        }
    }
}

# ---------------------------------------------------------------- 2. registry
Write-Host "`n[2/4] Registry keys" -ForegroundColor Yellow
$keys = @(
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    'HKCU\Software\Microsoft\Windows\DWM'
    'HKCU\Software\WinSTEP2000'
    'HKCU\Control Panel\Desktop'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
)
foreach ($k in $keys) {
    $safe = ($k -replace '[\\\s]', '_')
    $out  = Join-Path $dest "$safe.reg"
    $null = & reg.exe export $k $out /y 2>&1
    if ($LASTEXITCODE -eq 0) { Say "exported $k" 'Green' }
    else { Say "skipped $k (absent)" 'DarkGray' }
}

# ---------------------------------------------------------------- 3. config files
Write-Host "`n[3/4] Existing config files" -ForegroundColor Yellow
$wtLocal = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$files = [ordered]@{
    'PowerShell5-profile.ps1' = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    'PowerShell7-profile.ps1' = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
    'WindowsTerminal.json'    = $wtLocal
    'komorebi.json'           = "$env:USERPROFILE\komorebi.json"
    'whkdrc'                  = "$env:USERPROFILE\.config\whkdrc"
}
foreach ($name in $files.Keys) {
    $src = $files[$name]
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $dest $name) -Force
        Say "copied $name" 'Green'
    } else { Say "absent  $name" 'DarkGray' }
}

# whole-directory configs
$dirs = [ordered]@{
    'yasb'        = "$env:USERPROFILE\.config\yasb"
    'flowlauncher'= "$env:APPDATA\FlowLauncher\Settings"
}
foreach ($name in $dirs.Keys) {
    if (Test-Path $dirs[$name]) {
        Copy-Item $dirs[$name] (Join-Path $dest $name) -Recurse -Force
        Say "copied $name\" 'Green'
    } else { Say "absent  $name\" 'DarkGray' }
}

# ---------------------------------------------------------------- 4. plain-text state
Write-Host "`n[4/4] Current desktop state" -ForegroundColor Yellow
$adv  = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -ErrorAction SilentlyContinue
$pers = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
$dwm  = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\DWM' -ErrorAction SilentlyContinue
$desk = Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue

$state = [ordered]@{
    capturedAt           = (Get-Date).ToString('o')
    windows              = (Get-CimInstance Win32_OperatingSystem).Caption
    build                = (Get-CimInstance Win32_OperatingSystem).Version
    wallpaper            = $desk.Wallpaper
    wallpaperStyle       = $desk.WallpaperStyle
    # Keyed by their real registry value names so uninstall.ps1 needs no translation.
    TaskbarAl            = $adv.TaskbarAl          # 0 = left, 1 = centre
    TaskbarGlomLevel     = $adv.TaskbarGlomLevel   # 0 = always combine .. 2 = never
    appsUseLightTheme    = $pers.AppsUseLightTheme
    systemUsesLightTheme = $pers.SystemUsesLightTheme
    colorPrevalence      = $dwm.ColorPrevalence    # accent on title bars
    accentColor          = $dwm.AccentColor
    runningProcesses     = @(Get-Process | Where-Object { $_.Name -match 'yasb|komorebi|whkd|Flow|Rainmeter|Nexus|AutoHotkey' } | Select-Object -ExpandProperty Name -Unique)
}
$state | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dest 'state.json') -Encoding utf8
$state.GetEnumerator() | ForEach-Object { Say ("{0,-22} {1}" -f $_.Key, $_.Value) }

# Record which of our packages were ALREADY installed, so uninstall.ps1 never
# removes something the user had before the rice.
$ours = @('AmN.yasb','LGUG2Z.komorebi','LGUG2Z.whkd','LGUG2Z.masir','Flow-Launcher.Flow-Launcher',
          'Rainmeter.Rainmeter','WinStep.Nexus','AutoHotkey.AutoHotkey',
          'JanDeDobbeleer.OhMyPosh','Microsoft.PowerShell','aristocratos.btop4win',
          'voidtools.Everything','Fastfetch-cli.Fastfetch')
$installed = @()
foreach ($id in $ours) {
    $r = winget list --id $id --exact --accept-source-agreements 2>&1 | Out-String
    if ($r -notmatch 'No installed package') { $installed += $id }
}
ConvertTo-Json @($installed) | Set-Content (Join-Path $dest 'preinstalled.json') -Encoding utf8
Say "pre-existing packages: $(if ($installed) { $installed -join ', ' } else { 'none' })" 'Cyan'

# Point uninstall.ps1 at the newest backup.
Set-Content (Join-Path $root 'LATEST') $stamp -Encoding utf8

Write-Host "`nDone. $dest`n" -ForegroundColor Green
exit 0   # winget list sets a non-zero code for "not installed"; that is not our failure
