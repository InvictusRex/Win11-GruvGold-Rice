#Requires -Version 5.1
<#
    install.ps1 - Install the packages the rice needs.

    Idempotent: anything already present is skipped, so re-running is cheap and safe.
    This script only INSTALLS. It changes no settings and writes no configs -
    that is apply.ps1's job, so the two concerns stay separately reversible.

    Run backup.ps1 first.
#>

[CmdletBinding()]
param(
    [switch]$IncludeFont
)

$ErrorActionPreference = 'Continue'

# Ordered so that a partial run still leaves a usable desktop.
$packages = [ordered]@{
    'Microsoft.PowerShell'          = 'PowerShell 7'
    'AmN.yasb'                      = 'YASB status bar'
    'CharlesMilette.TranslucentTB'  = 'TranslucentTB'
    'Flow-Launcher.Flow-Launcher'   = 'Flow Launcher'
    'voidtools.Everything'          = 'Everything (file index for Flow)'
    'AutoHotkey.AutoHotkey'         = 'AutoHotkey v2'
    'Rainmeter.Rainmeter'           = 'Rainmeter'
    'JanDeDobbeleer.OhMyPosh'       = 'oh-my-posh'
    'aristocratos.btop4win'         = 'btop4win'
    'LGUG2Z.komorebi'               = 'komorebi tiling WM'
    'LGUG2Z.whkd'                   = 'whkd hotkey daemon'
    'LGUG2Z.masir'                  = 'masir (focus-follows-mouse for komorebi)'
}

if ($IncludeFont) {
    # Nerd Font for the glyphs YASB, oh-my-posh and btop need.
    # Separate flag because font installs are machine-scope and prompt for elevation.
    $packages['DEVCOM.JetBrainsMonoNerdFont'] = 'JetBrainsMono Nerd Font'
}

Write-Host "`nInstalling $($packages.Count) packages`n" -ForegroundColor Cyan

$installed = 0; $skipped = 0; $failed = @()

foreach ($id in $packages.Keys) {
    $label = '{0,-34}' -f $packages[$id]

    $check = winget list --id $id --exact --accept-source-agreements 2>&1 | Out-String
    if ($check -notmatch 'No installed package') {
        Write-Host "  $label already present" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    Write-Host "  $label installing..." -ForegroundColor Yellow -NoNewline
    $log = winget install --id $id --exact --silent `
                          --accept-package-agreements --accept-source-agreements `
                          --disable-interactivity 2>&1 | Out-String

    $verify = winget list --id $id --exact --accept-source-agreements 2>&1 | Out-String
    if ($verify -notmatch 'No installed package') {
        Write-Host "`r  $label installed        " -ForegroundColor Green
        $installed++
    } else {
        Write-Host "`r  $label FAILED           " -ForegroundColor Red
        $failed += [pscustomobject]@{ Id = $id; Log = ($log -split "`n" | Select-Object -Last 6) -join ' ' }
    }
}

Write-Host "`n  $installed installed, $skipped already present, $($failed.Count) failed" -ForegroundColor Cyan

if ($failed) {
    Write-Host "`nFailures:" -ForegroundColor Red
    foreach ($f in $failed) {
        Write-Host "  $($f.Id)" -ForegroundColor Red
        Write-Host "    $($f.Log.Trim())" -ForegroundColor DarkGray
    }
    Write-Host "`n  Most winget failures here are an elevation prompt being declined." -ForegroundColor Yellow
    Write-Host "  Re-run this script in an admin shell to retry just the failed ones.`n" -ForegroundColor Yellow
}

# komorebi and whkd put their binaries on PATH via the installer; the current
# shell will not see them until it is restarted. Surface that rather than
# letting apply.ps1 fail confusingly later.
$needsNewShell = @()
foreach ($exe in 'komorebic', 'whkd', 'yasbc', 'oh-my-posh') {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { $needsNewShell += $exe }
}
if ($needsNewShell) {
    Write-Host "  Not yet on PATH in this shell: $($needsNewShell -join ', ')" -ForegroundColor DarkYellow
    Write-Host "  That is expected right after install - open a new terminal before apply.ps1.`n" -ForegroundColor DarkYellow
}

exit 0
