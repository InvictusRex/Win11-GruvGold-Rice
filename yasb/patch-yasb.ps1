#Requires -Version 5.1
<#
    patch-yasb.ps1 - Put the rice's YASB patches into the installed YASB.

    YASB ships its Python code compiled inside lib\library.zip. Every file under
    patches\ is a complete replacement for the module at the same path in that
    zip: patches\core\utils\utilities.py replaces core/utils/utilities.pyc. The
    .py goes in and the .pyc comes out - YASB's zip importer compiles the source
    when it loads it, so no Python install is needed.

    The patches are whole modules taken from YASB 2.0.7, so any other version is
    refused (install.ps1 pins 2.0.7). What they add:
      wifi            Wi-Fi on/off switch in the menu header; slashed icon instead of
                      a clipped "N/A" when there is no internet or the radio is off
                      (wifi_off_icon); username + password for WPA2/WPA3-Enterprise
                      networks; connects time out instead of hanging; hover tooltip
      utilities       popups stay open when a shell flyout (quick settings) is open
                      as they are clicked open; short scrolling labels are centred
      media           the audio visualizer embedded in the media pill (visualizer:)
      control_center  profile_image_path, slider row labels, settings button beside
                      the name instead of a power button, centred power buttons
      power_menu      profile_image_path, sharp ringed circular avatar, centred buttons

    Needs an ADMIN PowerShell (YASB lives in Program Files), except -Check.
    YASB is stopped while the zip is rewritten; start it again afterwards with
    scripts\start.ps1 - starting it from this elevated shell would run it as admin.

    library.zip is backed up once, before the first patch, as
    library.zip.gruvgold-backup next to it.

    Usage:
      .\patch-yasb.ps1            # apply (re-run after editing a patch)
      .\patch-yasb.ps1 -Check     # exit 0 if every patch is already in place
      .\patch-yasb.ps1 -Restore   # put the stock library.zip back
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
$version = '2.0.7'   # the release the patched modules were taken from
$yasbDir = "$env:ProgramFiles\YASB"
$lib     = "$yasbDir\lib\library.zip"
$backup  = "$lib.gruvgold-backup"
$patches = (Resolve-Path (Join-Path $PSScriptRoot 'patches')).Path

function Say($msg, $colour = 'Gray') { Write-Host "  $msg" -ForegroundColor $colour }

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

# patches\core\utils\utilities.py -> core/utils/utilities
$modules = foreach ($file in Get-ChildItem $patches -Recurse -Filter '*.py') {
    [pscustomobject]@{
        File   = $file.FullName
        Module = $file.FullName.Substring($patches.Length + 1).Replace('\', '/') -replace '\.py$'
    }
}

if (-not (Test-Path $lib)) { Say "YASB not found at $yasbDir - run install.ps1" 'Red'; exit 1 }

if ($Check) {
    $zip = [IO.Compression.ZipFile]::OpenRead($lib)
    try {
        foreach ($m in $modules) {
            $entry = $zip.GetEntry("$($m.Module).py")
            if (-not $entry) { exit 1 }
            $reader = New-Object IO.BinaryReader $entry.Open()
            try { $inZip = $reader.ReadBytes([int]$entry.Length) } finally { $reader.Close() }
            $inRepo = [IO.File]::ReadAllBytes($m.File)
            if ([Convert]::ToBase64String($inZip) -ne [Convert]::ToBase64String($inRepo)) { exit 1 }
        }
    } finally { $zip.Dispose() }
    exit 0
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Say 'run this from an ADMIN PowerShell - YASB lives in Program Files' 'Red'; exit 1 }

if (Get-Process yasb -ErrorAction SilentlyContinue) {
    Stop-Process -Name yasb -Force
    Start-Sleep -Milliseconds 800
    Say 'stopped YASB' 'DarkGray'
}

if ($Restore) {
    if (-not (Test-Path $backup)) { Say 'no backup found - YASB was not patched by this script' 'DarkYellow'; exit 0 }
    Move-Item $backup $lib -Force
    Say 'restored the stock library.zip' 'Green'
    exit 0
}

$installed = (Get-Item "$yasbDir\yasb.exe").VersionInfo.ProductVersion
if ($installed -ne $version) {
    Say "YASB $installed is installed; these patches are YASB $version modules. Install that version first:" 'Red'
    Say "  winget install --id AmN.yasb --exact --version $version --force" 'Red'
    exit 1
}

if (-not (Test-Path $backup)) {
    Copy-Item $lib $backup
    Say "backed up library.zip -> $(Split-Path $backup -Leaf)" 'DarkGray'
}

$zip = [IO.Compression.ZipFile]::Open($lib, [IO.Compression.ZipArchiveMode]::Update)
try {
    # Check every module first, so a bad patch path leaves the zip untouched.
    foreach ($m in $modules) {
        if (-not ($zip.GetEntry("$($m.Module).pyc") -or $zip.GetEntry("$($m.Module).py"))) {
            throw "$($m.Module) is not a module of YASB $version"
        }
    }
    foreach ($m in $modules) {
        foreach ($name in "$($m.Module).pyc", "$($m.Module).py") {
            $old = $zip.GetEntry($name)
            if ($old) { $old.Delete() }
        }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $m.File, "$($m.Module).py") | Out-Null
        Say "patched $($m.Module)" 'Green'
    }
} finally { $zip.Dispose() }

Say 'done - start YASB again with scripts\start.ps1 (not from this admin shell)' 'Cyan'
