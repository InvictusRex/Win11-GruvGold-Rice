#Requires -Version 5.1
<#
    apply.ps1 - Put the configs in this repo into their live locations and set
    the Windows-side options the rice depends on.

    Run backup.ps1 first, then install.ps1, then this.

    Everything here is reversible by uninstall.ps1. Nothing patches a system
    file, replaces the shell, or injects into a process.

    Config deployment uses a symlink when Developer Mode is on (so editing the
    repo edits the live config), and falls back to a plain copy otherwise.

    Parameters:
      -SkipSettings   only deploy config files, change no Windows settings
      -SkipConfigs    only change Windows settings
#>

[CmdletBinding()]
param(
    [switch]$SkipSettings,
    [switch]$SkipConfigs
)

$ErrorActionPreference = 'Continue'
$repo = $PSScriptRoot
$cfg  = Join-Path $repo 'config'

function Say($msg, $colour = 'Gray') { Write-Host "  $msg" -ForegroundColor $colour }
function Head($msg) { Write-Host "`n$msg" -ForegroundColor Yellow }

$script:DevMode = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1

# Deploy a file or directory from the repo to its live location.
# Symlink if we can (edits in the repo go live immediately), copy if we cannot.
function Deploy($source, $target) {
    if (-not (Test-Path $source)) { Say "MISSING source: $source" 'Red'; return }

    $parent = Split-Path $target -Parent
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    if (Test-Path $target) {
        $existing = Get-Item $target -Force
        if ($existing.LinkType -eq 'SymbolicLink') { $existing.Delete() }
        else { Remove-Item $target -Recurse -Force }
    }

    $name = Split-Path $target -Leaf
    if ($script:DevMode) {
        try {
            New-Item -ItemType SymbolicLink -Path $target -Target $source -ErrorAction Stop | Out-Null
            Say "linked  $name" 'Green'
            return
        } catch {
            # fall through to copy
        }
    }
    Copy-Item $source $target -Recurse -Force
    Say "copied  $name" 'Green'
}

Write-Host "`nApplying GruvGold" -ForegroundColor Cyan
Say ("config deployment: " + $(if ($script:DevMode) { 'symlink (Developer Mode on)' } else { 'copy (Developer Mode off)' })) 'DarkGray'

# ================================================================= configs
if (-not $SkipConfigs) {

    Head '[1/11] YASB'
    Deploy (Join-Path $cfg 'yasb\config.yaml') "$env:USERPROFILE\.config\yasb\config.yaml"
    Deploy (Join-Path $cfg 'yasb\styles.css') "$env:USERPROFILE\.config\yasb\styles.css"

    # Without a settings.json TranslucentTB treats every launch as a first run and
    # pops its welcome dialog at boot. Only seed it - never overwrite the user's own.
    $ttbSettings = "$env:LOCALAPPDATA\Packages\28017CharlesMilette.TranslucentTB_v826wp6bftszj\RoamingState\settings.json"
    if (-not (Test-Path $ttbSettings)) {
        New-Item -ItemType Directory -Path (Split-Path $ttbSettings) -Force | Out-Null
        Copy-Item (Join-Path $cfg 'translucenttb\settings.json') $ttbSettings
    }

    Head '[2/11] komorebi + whkd'
    Deploy (Join-Path $cfg 'komorebi\komorebi.json') "$env:USERPROFILE\komorebi.json"
    Deploy (Join-Path $cfg 'komorebi\whkdrc')       "$env:USERPROFILE\.config\whkdrc"

    # applications.json is the upstream community rule set for apps that
    # misbehave when tiled. Fetched rather than vendored so it stays current.
    $appsDir  = "$env:USERPROFILE\.config\komorebi"
    $appsFile = Join-Path $appsDir 'applications.json'
    New-Item -ItemType Directory -Path $appsDir -Force | Out-Null
    if (-not (Test-Path $appsFile)) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 `
                -Uri 'https://raw.githubusercontent.com/LGUG2Z/komorebi-application-specific-configuration/master/applications.json' `
                -OutFile $appsFile
            Say "fetched applications.json" 'Green'
        } catch {
            Say "could not fetch applications.json - komorebi still works without it" 'DarkYellow'
            '[]' | Set-Content $appsFile -Encoding utf8
        }
    } else { Say "applications.json already present" 'DarkGray' }

    Head '[3/11] Flow Launcher theme'
    $flowThemes = "$env:APPDATA\FlowLauncher\Themes"
    if (Test-Path $flowThemes) {
        Deploy (Join-Path $cfg 'flow-launcher\GruvGold.xaml') (Join-Path $flowThemes 'GruvGold.xaml')

        # Select the theme and enable the Google fallback. Flow Launcher rewrites
        # Settings.json on exit, so it has to be closed while we edit it.
        $flowSettings = "$env:APPDATA\FlowLauncher\Settings\Settings.json"
        if (Test-Path $flowSettings) {
            $wasRunning = [bool](Get-Process Flow.Launcher -ErrorAction SilentlyContinue)
            if ($wasRunning) { Get-Process Flow.Launcher | Stop-Process -Force; Start-Sleep -Seconds 3 }
            try {
                $fs = Get-Content $flowSettings -Raw | ConvertFrom-Json
                $fs | Add-Member Theme 'GruvGold' -Force
                # Typing on the desktop should fall through to a web search when
                # nothing matches - the "Search Google" row in reference_1.
                $fs | Add-Member ShouldUsePinyin $false -Force
                # WindowSize is in LOGICAL pixels and 'Center' centres correctly, so
                # leave the alignment alone and just widen it. 1000 of the 1707px
                # logical desktop is a bit under 60%, close to the reference shot.
                # (Beware when measuring with AutoHotkey: it reports PHYSICAL pixels,
                # so at 150% a correct 1000px window reads back as 1500.)
                $fs | Add-Member WindowSize 1000 -Force
                $fs | Add-Member MaxResultsToShow 8 -Force
                $fs | Add-Member SearchWindowAlign 'Center' -Force
                # 'Cursor' makes it follow the mouse between monitors; 'Focus' keeps
                # it on the screen holding the focused window.
                $fs | Add-Member SearchWindowScreen 'Focus' -Force
                $fs | Add-Member WindowLeft 0 -Force   # force a recompute on next show
                $fs | ConvertTo-Json -Depth 32 | Set-Content $flowSettings -Encoding utf8
                Say "theme selected (GruvGold)" 'Green'
            } catch {
                Say "could not set theme: $($_.Exception.Message)" 'DarkYellow'
            }
            if ($wasRunning) {
                $flowExe = Get-Item "$env:LOCALAPPDATA\FlowLauncher\Flow.Launcher.exe" -ErrorAction SilentlyContinue
                if ($flowExe) { Start-Process $flowExe.FullName }
            }
        }
    } else {
        Say "Flow Launcher has not created its data folder yet - run it once, then re-run apply.ps1" 'DarkYellow'
    }

    Head '[4/11] Everything search backend'
    $everythingExe = @('%ProgramFiles%\Everything\Everything.exe', '%ProgramFiles(x86)%\Everything\Everything.exe') |
        ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    $explorerSettings = "$env:APPDATA\FlowLauncher\Settings\Plugins\Flow.Launcher.Plugin.Explorer\Settings.json"
    if (-not $everythingExe) {
        Say "Everything.exe not found - run install.ps1 first" 'DarkYellow'
    } elseif (-not (Test-Path $explorerSettings)) {
        Say "Explorer plugin has not created its settings yet - run Flow Launcher once, then re-run apply.ps1" 'DarkYellow'
    } else {
        $wasRunning = [bool](Get-Process Flow.Launcher -ErrorAction SilentlyContinue)
        if ($wasRunning) { Get-Process Flow.Launcher | Stop-Process -Force; Start-Sleep -Seconds 3 }
        try {
            $es = Get-Content $explorerSettings -Raw | ConvertFrom-Json
            # 1 = Everything for both engines - instant, and covers every drive via
            # the NTFS MFT with no folder-by-folder setup. ContentSearchEngine stays
            # 0 (Windows Index): tried Everything's content: function here and it
            # reproducibly hung the whole engine (not just the slow-unscoped-query
            # case voidtools documents - even a 3-file parent: scope hung), so it is
            # NOT enabled. doc: content search is therefore still on Windows Index,
            # which works but is its own separate known-flaky thing - see README.
            $es | Add-Member IndexSearchEngine 1 -Force
            $es | Add-Member PathEnumerationEngine 1 -Force
            $es | Add-Member ContentSearchEngine 0 -Force
            $es | Add-Member EnableEverythingContentSearch $false -Force
            $es | Add-Member EverythingInstalledPath $everythingExe -Force
            $es | ConvertTo-Json -Depth 32 | Set-Content $explorerSettings -Encoding utf8
            Say "Explorer plugin now searches via Everything (filenames and paths)" 'Green'
        } catch {
            Say "could not set Explorer engine: $($_.Exception.Message)" 'DarkYellow'
        }
        if ($wasRunning) {
            $flowExe = Get-Item "$env:LOCALAPPDATA\FlowLauncher\Flow.Launcher.exe" -ErrorAction SilentlyContinue
            if ($flowExe) { Start-Process $flowExe.FullName }
        }
        # NOT doing per-folder exclusion (e.g. D:\config) here: Everything.ini's
        # exclude_folders does not reliably apply to NTFS-indexed volumes - voidtools'
        # own docs call this "in development", and it was confirmed flaky against this
        # NTFS-indexed D:\ (worked once, then a forced -reindex un-excluded it again).
        # The NTFS tab only supports excluding a whole volume, not a subfolder.
    }

    Head '[5/11] Flow Launcher plugin cleanup'
    $flowMainSettings = "$env:APPDATA\FlowLauncher\Settings\Settings.json"
    $webSearchSettings = "$env:APPDATA\FlowLauncher\Settings\Plugins\Flow.Launcher.Plugin.WebSearch\Settings.json"
    if (-not (Test-Path $flowMainSettings) -or -not (Test-Path $webSearchSettings)) {
        Say "Flow Launcher plugin settings not created yet - run Flow Launcher once, then re-run apply.ps1" 'DarkYellow'
    } else {
        $wasRunning = [bool](Get-Process Flow.Launcher -ErrorAction SilentlyContinue)
        if ($wasRunning) { Get-Process Flow.Launcher | Stop-Process -Force; Start-Sleep -Seconds 3 }
        try {
            # Web Searches - keep only Google (the "*" fallback), Scholar, Maps,
            # Translate, Gmail and YouTube; drop the rest of the default list.
            $keepKeywords = @('*', 'sc', 'maps', 'translate', 'gmail', 'youtube')

            # Browser Bookmarks (the "b" keyword) - not wanted. Also mirror the
            # trimmed Web Searches keyword list into the main Settings.json: the
            # "?" keyword-indicator (and query routing) reads PluginSettings.Plugins
            # [id].ActionKeywords here, a separate cached copy of the per-site
            # keywords that does NOT auto-sync from the plugin's own SearchSources
            # list below - editing only that file left the indicator listing every
            # removed keyword as still active.
            $fs = Get-Content $flowMainSettings -Raw | ConvertFrom-Json
            $bookmarkPlugin = $fs.PluginSettings.Plugins.PSObject.Properties.Value |
                Where-Object { $_.Name -eq 'Browser Bookmarks' }
            if ($bookmarkPlugin) { $bookmarkPlugin.Disabled = $true }
            $webSearchPlugin = $fs.PluginSettings.Plugins.PSObject.Properties.Value |
                Where-Object { $_.Name -eq 'Web Searches' }
            if ($webSearchPlugin) { $webSearchPlugin.ActionKeywords = $keepKeywords }
            # AutoUpdates is already off; AutoUpdatePlugins would silently redownload
            # built-in plugins (including our hand-patched PluginIndicator) and undo
            # the local rebuild - off, and only ever updated by hand.
            $fs | Add-Member AutoUpdatePlugins $false -Force

            # "exam: on" / "exam: off" launcher shortcut (config/flow-launcher/plugins/ExamMode).
            # Python plugin, so point Flow at an installed Python - left empty it prompts
            # to download its own embedded one.
            $py = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
                Sort-Object { [version](($_.Directory.Name -replace 'Python(\d)(\d+)', '$1.$2')) } -Descending |
                Select-Object -First 1
            if ($py) {
                $fs.PluginSettings.PythonExecutablePath = $py.FullName
                $examDir = "$env:APPDATA\FlowLauncher\Plugins\ExamMode"
                New-Item -ItemType Directory -Path $examDir -Force | Out-Null
                Copy-Item (Join-Path $cfg 'flow-launcher\plugins\ExamMode\*') $examDir -Force
                Join-Path $repo 'exam-mode.ps1' | Set-Content (Join-Path $examDir 'examscript.txt') -Encoding utf8 -NoNewline
                Say "installed exam: on/off launcher shortcut" 'Green'
            } else { Say "no Python found - skipped the exam: launcher shortcut" 'DarkYellow' }
            $fs | ConvertTo-Json -Depth 32 | Set-Content $flowMainSettings -Encoding utf8

            $ws = Get-Content $webSearchSettings -Raw | ConvertFrom-Json
            $ws.SearchSources = @($ws.SearchSources | Where-Object { $keepKeywords -contains $_.ActionKeyword })

            # Google Scholar shares the plain Google icon by default - give it its own.
            $customIconsDir = "$env:APPDATA\FlowLauncher\Settings\Plugins\Flow.Launcher.Plugin.WebSearch\CustomIcons"
            Deploy (Join-Path $cfg 'flow-launcher\icons\google_scholar.png') (Join-Path $customIconsDir 'google_scholar.png')
            $scholar = $ws.SearchSources | Where-Object { $_.ActionKeyword -eq 'sc' }
            if ($scholar) {
                $scholar.Icon = 'google_scholar.png'
                $scholar.CustomIcon = $true
            }

            $ws | ConvertTo-Json -Depth 32 | Set-Content $webSearchSettings -Encoding utf8
            Say "disabled Browser Bookmarks; Web Searches trimmed to sc/maps/translate/gmail/youtube (+ Google default)" 'Green'
        } catch {
            Say "could not patch plugin settings: $($_.Exception.Message)" 'DarkYellow'
        }
        if ($wasRunning) {
            $flowExe = Get-Item "$env:LOCALAPPDATA\FlowLauncher\Flow.Launcher.exe" -ErrorAction SilentlyContinue
            if ($flowExe) { Start-Process $flowExe.FullName }
        }
    }

    Head '[6/11] Stop auto-updates'
    # Nothing here downloads or installs anything on its own - only turns off each
    # tool's own background update-check/auto-update, so nothing changes unless
    # install.ps1/apply.ps1 is re-run by hand or you update a tool yourself.
    #
    # Already off by default, nothing to do: Everything (check_for_updates_on_startup
    # /beta_updates are 0 out of the box), komorebi/whkd/masir/AutoHotkey/btop4win
    # (no built-in updater), TranslucentTB (no built-in updater).
    # Flow Launcher's AutoUpdates/AutoUpdatePlugins are handled in the plugin
    # cleanup step above. oh-my-posh's upgrade.notice/auto are set in its own
    # theme file (config/ohmyposh/gruvgold.omp.json).

    $rainmeterIni = "$env:APPDATA\Rainmeter\Rainmeter.ini"
    if (Test-Path $rainmeterIni) {
        $lines = Get-Content $rainmeterIni -Encoding Unicode
        if ($lines -match '^\s*CheckUpdates\s*=') {
            $lines = $lines -replace '^\s*CheckUpdates\s*=.*$', 'CheckUpdates=0'
        } else {
            # Insert right after the [Rainmeter] header, where Rainmeter itself puts it.
            $lines = $lines | ForEach-Object {
                $_
                if ($_ -match '^\[Rainmeter\]\s*$') { 'CheckUpdates=0' }
            }
        }
        $lines | Set-Content $rainmeterIni -Encoding Unicode
        Say "Rainmeter: CheckUpdates=0" 'Green'
    } else {
        Say "Rainmeter.ini not found yet - run Rainmeter once, then re-run apply.ps1" 'DarkYellow'
    }

    # PowerShell 7's own "a new version is available" background check.
    [Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'Off', 'User')
    $env:POWERSHELL_UPDATECHECK = 'Off'
    Say "PowerShell: POWERSHELL_UPDATECHECK=Off" 'Green'

    Head '[7/11] Windows Terminal scheme'
    # Delivered as a fragment: it ADDS the scheme without rewriting settings.json.
    $frag = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\GruvGold"
    New-Item -ItemType Directory -Path $frag -Force | Out-Null
    Deploy (Join-Path $cfg 'terminal\gruvgold.json') (Join-Path $frag 'gruvgold.json')

    # A fragment cannot set profiles.defaults, so opacity/acrylic/font/scheme are
    # a surgical merge into settings.json. backup.ps1 already copied the original.
    $wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path $wt) {
        try {
            $json = Get-Content $wt -Raw | ConvertFrom-Json
            if (-not $json.profiles) { $json | Add-Member profiles ([pscustomobject]@{}) -Force }
            if (-not $json.profiles.defaults) { $json.profiles | Add-Member defaults ([pscustomobject]@{}) -Force }
            $d = $json.profiles.defaults
            foreach ($kv in @{
                colorScheme  = 'GruvGold'
                # Plain opacity, not acrylic: on this machine the acrylic body
                # falls back to solid black even with transparency effects on.
                useAcrylic   = $false
                # Low enough that the wallpaper shows through, high enough that
                # text on pure black keeps its contrast.
                opacity      = 80
                # The installed family is "JetBrainsMono NF", not "...Nerd Font".
                font         = [pscustomobject]@{ face = 'JetBrainsMono NF'; size = 11 }
                padding      = '0'
scrollbarState = 'hidden'
            }.GetEnumerator()) {
                $d | Add-Member $kv.Key $kv.Value -Force
            }

            # Tab row: frosted acrylic instead of the stock grey; tabs take the
            # terminal's own background. Themes cannot live in a fragment either.
            $theme = [pscustomobject]@{
                name   = 'GruvGold'
                tab    = [pscustomobject]@{ background = 'terminalBackground'; unfocusedBackground = '#00000000' }
                tabRow = [pscustomobject]@{ background = '#00000000'; unfocusedBackground = '#00000000' }
                window = [pscustomobject]@{ applicationTheme = 'dark' }
            }
            $json | Add-Member themes (@(@($json.themes) | Where-Object { $_ -and $_.name -ne 'GruvGold' }) + $theme) -Force
            foreach ($kv in @{
                theme                                = 'GruvGold'
                useAcrylicInTabRow                   = $true
                # Acrylic otherwise drops to solid colour whenever the window is
                # unfocused, which under komorebi is most of the time.
                'compatibility.enableUnfocusedAcrylic' = $true
            }.GetEnumerator()) {
                $json | Add-Member $kv.Key $kv.Value -Force
            }

            $json | ConvertTo-Json -Depth 32 | Set-Content $wt -Encoding utf8
            Say "patched settings.json (scheme, opacity, font, tab row theme)" 'Green'
        } catch {
            Say "could not patch Terminal settings.json: $($_.Exception.Message)" 'DarkYellow'
        }
    } else { Say "Windows Terminal settings.json not found - open Terminal once first" 'DarkYellow' }

    Head '[8/11] oh-my-posh prompt'
    Deploy (Join-Path $cfg 'ohmyposh\gruvgold.omp.json') "$env:USERPROFILE\.config\ohmyposh\gruvgold.omp.json"
    Deploy (Join-Path $cfg 'fastfetch') "$env:USERPROFILE\.config\fastfetch"

    # Append to the profile rather than overwrite it, and only once.
    $marker = '# --- GruvGold prompt ---'
    $init   = @"
$marker
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "`$env:USERPROFILE\.config\ohmyposh\gruvgold.omp.json" | Invoke-Expression
}
"@
    foreach ($p in @(
        "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
        "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    )) {
        New-Item -ItemType Directory -Path (Split-Path $p) -Force | Out-Null
        if (-not (Test-Path $p)) { New-Item -ItemType File -Path $p -Force | Out-Null }
        if ((Get-Content $p -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($marker)) {
            Say "prompt already in $(Split-Path $p -Leaf)" 'DarkGray'
        } else {
            Add-Content $p "`n$init"
            Say "added prompt to $(Split-Path $p -Leaf)" 'Green'
        }
    }

    # "exam: on" / "exam: off" from any PowerShell, whatever the working directory.
    # The repo path is baked in at apply time.
    $examMarker = '# --- GruvGold exam mode ---'
    $examFn = @"
$examMarker
function exam: { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$repo\exam-mode.ps1" `$(if ("`$args" -eq 'off') { '-Off' }) }
"@
    foreach ($p in @(
        "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
        "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    )) {
        if (-not ((Get-Content $p -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($examMarker))) {
            Add-Content $p "`n$examFn"
            Say "added exam: function to $(Split-Path $p -Leaf)" 'Green'
        }
    }

    Head '[9/11] btop theme'
    Deploy (Join-Path $cfg 'btop\gruvgold.theme') "$env:USERPROFILE\.config\btop\themes\gruvgold.theme"
    # btop4win also looks next to its own binary.
    $btopExe = (Get-Command btop4win, btop -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ($btopExe) {
        $btopThemes = Join-Path (Split-Path $btopExe) 'themes'
        New-Item -ItemType Directory -Path $btopThemes -Force | Out-Null
        Copy-Item (Join-Path $cfg 'btop\gruvgold.theme') (Join-Path $btopThemes 'gruvgold.theme') -Force
        Say "copied theme beside btop binary" 'Green'
    }

    Head '[10/11] Rainmeter skins'
    Deploy (Join-Path $cfg 'rainmeter\Skins\GruvGold') "$env:USERPROFILE\Documents\Rainmeter\Skins\GruvGold"

    Head '[11/11] AutoHotkey scripts'
    Deploy (Join-Path $cfg 'ahk\desktop-type-to-launch.ahk') "$env:LOCALAPPDATA\GruvGoldRice\desktop-type-to-launch.ahk"
    # Invoked per keypress by whkdrc for Win+Up / Win+Down / Win+Left / Win+Right, not run resident.
    Deploy (Join-Path $cfg 'ahk\snap-half.ahk') "$env:LOCALAPPDATA\GruvGoldRice\snap-half.ahk"
    # Invoked per keypress by whkdrc for Win+D, not run resident.
    Deploy (Join-Path $cfg 'ahk\toggle-desktop.ahk') "$env:LOCALAPPDATA\GruvGoldRice\toggle-desktop.ahk"
}

# ================================================================= settings
if (-not $SkipSettings) {

    Head 'Windows settings'

    # ---- wallpaper -------------------------------------------------------
    $wall = Join-Path $repo 'references\wallpaper.png'
    if (Test-Path $wall) {
        Add-Type @'
using System.Runtime.InteropServices;
public class GruvWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@ -ErrorAction SilentlyContinue
        Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'  # fill
        Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name TileWallpaper  -Value '0'
        [GruvWallpaper]::SystemParametersInfo(20, 0, $wall, 3) | Out-Null   # SPI_SETDESKWALLPAPER
        Say "wallpaper set" 'Green'
    } else { Say "wallpaper.png not found" 'Red' }

    # ---- dark mode + gold accent ----------------------------------------
    $pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-ItemProperty $pers -Name AppsUseLightTheme    -Value 0 -Type DWord
    Set-ItemProperty $pers -Name SystemUsesLightTheme -Value 0 -Type DWord
    Say "dark mode on" 'Green'

    # Windows regenerates DWM\AccentColor from AccentPalette at every sign-in, so
    # writing the gold value here does not survive a reboot - it came back as
    # #0078D7. Rather than fight that, turn the Windows accent border OFF entirely
    # and let komorebi draw the focus ring (start.ps1 sets it to the gold palette).
    # That is also the behaviour you want from a tiling WM: one focus indicator.
    $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
    New-ItemProperty $dwm -Name ColorPrevalence -Value 0 -PropertyType DWord -Force | Out-Null
    Say "Windows accent border off - komorebi owns the focus ring" 'Green'

    # ---- window snapping -------------------------------------------------
    # whkdrc intercepts Win+arrow itself (see snap-half.ahk) before Windows ever
    # sees the keypress, so Aero Snap's own keyboard handling never gets a
    # chance to race komorebi there. Left on, this only re-enables mouse-drag
    # snapping (drag to the top for the Snap Layouts flyout, drag to an edge)
    # for windows komorebi isn't actively tiling at that moment.
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WindowArrangementActive -Value '1' -Force
    Say "Aero Snap (drag-to-edge/top) re-enabled; Win+arrow stays komorebi's" 'Green'

    # ---- taskbar ---------------------------------------------------------
    # Centred, with labels always shown: this is what produces the labelled
    # buttons in reference_2.png. TranslucentTB then removes the background.
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    New-ItemProperty $adv -Name TaskbarAl          -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty $adv -Name TaskbarGlomLevel   -Value 2 -PropertyType DWord -Force | Out-Null
    New-ItemProperty $adv -Name MMTaskbarGlomLevel -Value 2 -PropertyType DWord -Force | Out-Null
    Say "taskbar centred, labels always shown" 'Green'
    # Explorer still runs its own Win+D alongside the whkd binding and hides the windows
    # before toggle-desktop.ahk can enumerate them. Needs an Explorer restart to apply.
    $hot = (Get-ItemProperty $adv -Name DisabledHotkeys -ErrorAction SilentlyContinue).DisabledHotkeys
    if ($hot -notmatch "D") { New-ItemProperty $adv -Name DisabledHotkeys -Value "$hot`D" -PropertyType String -Force | Out-Null }

    # ---- lock screen -----------------------------------------------------
    if (Test-Path $wall) {
        $lockKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
        try {
            New-Item -Path $lockKey -Force -ErrorAction Stop | Out-Null
            New-ItemProperty $lockKey -Name LockScreenImage -Value $wall -PropertyType String -Force -ErrorAction Stop | Out-Null
            Say "lock screen image set" 'Green'
        } catch {
            Say "lock screen needs an admin shell - set it in Settings > Personalization > Lock screen" 'DarkYellow'
        }
    }

    Head 'Restarting Explorer to apply taskbar changes'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Say "done" 'Green'
}

Write-Host "`nApplied. Start the stack with:  .\start.ps1`n" -ForegroundColor Green
exit 0
