#Requires -Version 5.1
<#
    apply.ps1 - Put the configs in this repo into their live locations and set
    the Windows-side options the rice depends on.

    Run backup.ps1 first, then install.ps1, then this.

    Everything here is reversible by uninstall.ps1. Nothing patches a system
    file, replaces the shell, or injects into a process.

    Everything is copied, never linked: the clone is only the source. Editing
    it changes nothing until this is re-run, and the rice keeps working if the
    clone is moved or deleted.
    Scripts the rice runs later (autostart, exam mode) and the theme images
    are installed to %LOCALAPPDATA%\GruvGoldRice for the same reason.

    Parameters:
      -SkipSettings   only deploy config files, change no Windows settings
      -SkipConfigs    only change Windows settings
      -Name <name>    name shown in the prompt and fastfetch title (default: your
                      Windows user name). Remembered for later runs.
#>

[CmdletBinding()]
param(
    [switch]$SkipSettings,
    [switch]$SkipConfigs,
    [string]$Name
)

$ErrorActionPreference = 'Continue'
$repo = Split-Path $PSScriptRoot -Parent   # scripts/ lives one level below the repo root
$cfg  = $repo   # component configs live in top-level folders (yasb/, komorebi/, ...)
$live = "$env:LOCALAPPDATA\GruvGoldRice"   # installed scripts and theme images

function Say($msg, $colour = 'Gray') { Write-Host "  $msg" -ForegroundColor $colour }
function Head($msg) { Write-Host "`n$msg" -ForegroundColor Yellow }

# Copy a file or directory from the repo to its live location.
function Deploy($source, $target) {
    if (-not (Test-Path $source)) { Say "MISSING source: $source" 'Red'; return }

    $parent = Split-Path $target -Parent
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    if (Test-Path $target) {
        # Older versions symlinked into the repo; delete such a link itself,
        # never recurse through it into the repo.
        $existing = Get-Item $target -Force
        if ($existing.LinkType -eq 'SymbolicLink') { $existing.Delete() }
        else { Remove-Item $target -Recurse -Force }
    }

    Copy-Item $source $target -Recurse -Force
    Say "copied  $(Split-Path $target -Leaf)" 'Green'
}

Write-Host "`nApplying GruvGold" -ForegroundColor Cyan

# ================================================================= configs
if (-not $SkipConfigs) {

    Head '[1/11] YASB'
    Deploy (Join-Path $cfg 'yasb\config.yaml') "$env:USERPROFILE\.config\yasb\config.yaml"
    Deploy (Join-Path $cfg 'yasb\styles.css') "$env:USERPROFILE\.config\yasb\styles.css"
    # The power menu's profile picture needs an absolute path.
    Deploy (Join-Path $repo 'theme\profile.png') "$live\theme\profile.png"
    $yasbCfg = "$env:USERPROFILE\.config\yasb\config.yaml"
    $yaml = (Get-Content $yasbCfg -Raw -Encoding UTF8) -replace '(?m)^(\s*profile_image_path:)[^\r\n]*', ('$1 "' + ($live -replace '\\', '/') + '/theme/profile.png"')
    [IO.File]::WriteAllText($yasbCfg, $yaml, (New-Object System.Text.UTF8Encoding $false))

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
                # nothing matches, via the "Search Google" row.
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
            $keepKeywords = @('*', 'sc:', 'maps:', 'translate:', 'gmail:', 'youtube:')

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

            # "exam: on" / "exam: off" launcher shortcut (flow-launcher/plugins/ExamMode).
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
                "$live\scripts\exam-mode.ps1" | Set-Content (Join-Path $examDir 'examscript.txt') -Encoding utf8 -NoNewline
                Say "installed exam: launcher shortcut" 'Green'
                # "btop" launcher entry (flow-launcher/plugins/Btop): opens btop4win in a new terminal.
                $btopDir = "$env:APPDATA\FlowLauncher\Plugins\Btop"
                $btopBin = (Get-Command btop4win -ErrorAction SilentlyContinue | Select-Object -First 1).Source
                if ($btopBin) {
                    New-Item -ItemType Directory -Path $btopDir -Force | Out-Null
                    Copy-Item (Join-Path $cfg 'flow-launcher\plugins\Btop\*') $btopDir -Force
                    Set-Content (Join-Path $btopDir 'btoppath.txt') $btopBin -Encoding utf8 -NoNewline
                    Say "installed btop launcher entry" 'Green'
                } else { Say "btop4win not found - skipped the btop launcher entry" 'DarkYellow' }
            } else { Say "no Python found - skipped the exam: launcher shortcut" 'DarkYellow' }
            $fs | ConvertTo-Json -Depth 32 | Set-Content $flowMainSettings -Encoding utf8

            $ws = Get-Content $webSearchSettings -Raw | ConvertFrom-Json
            # Keywords end in a colon (re-runs: sources may already carry it).
            foreach ($src in $ws.SearchSources) { if ($src.ActionKeyword -notin '*', '' -and -not $src.ActionKeyword.EndsWith(':')) { $src.ActionKeyword += ':' } }
            $ws.SearchSources = @($ws.SearchSources | Where-Object { $keepKeywords -contains $_.ActionKeyword })

            # Google Scholar shares the plain Google icon by default - give it its own.
            $customIconsDir = "$env:APPDATA\FlowLauncher\Settings\Plugins\Flow.Launcher.Plugin.WebSearch\CustomIcons"
            Deploy (Join-Path $cfg 'flow-launcher\icons\google_scholar.png') (Join-Path $customIconsDir 'google_scholar.png')
            $scholar = $ws.SearchSources | Where-Object { $_.ActionKeyword -eq 'sc:' }
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
    # cleanup step above.

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
                # Left only, ~one 11pt cell: the prompt and all command output
                # sit one column off the window edge.
                padding      = '9, 0, 0, 0'
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

            # -NoLogo: no "Windows PowerShell / Copyright" banner and no "Loading
            # personal and system profiles took ..." line before the greeting.
            # GUIDs are Terminal's fixed ids for its generated PowerShell profiles.
            # pwsh by bare name: the Store install's real path carries its version.
            foreach ($prof in @($json.profiles.list)) {
                $cmd = switch ($prof.guid) {
                    '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}' { '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo' }
                    '{574e775e-4f2a-5b96-ac1e-a2962a402336}' { 'pwsh.exe -NoLogo' }
                }
                if ($cmd) { $prof | Add-Member commandline $cmd -Force }
            }

            $json | ConvertTo-Json -Depth 32 | Set-Content $wt -Encoding utf8
            Say "patched settings.json (scheme, opacity, font, tab row theme, -NoLogo)" 'Green'
        } catch {
            Say "could not patch Terminal settings.json: $($_.Exception.Message)" 'DarkYellow'
        }
    } else { Say "Windows Terminal settings.json not found - open Terminal once first" 'DarkYellow' }

    Head '[8/11] PowerShell prompt + fastfetch greeting'
    Deploy (Join-Path $cfg 'powershell\gruvgold.ps1') "$env:USERPROFILE\.config\powershell\gruvgold.ps1"
    Deploy (Join-Path $cfg 'fastfetch') "$env:USERPROFILE\.config\fastfetch"

    # -Name sticks: GRUVGOLD_NAME feeds the prompt and later runs of this script.
    if ($Name) {
        [Environment]::SetEnvironmentVariable('GRUVGOLD_NAME', $Name, 'User')
        $env:GRUVGOLD_NAME = $Name
    } else { $Name = [Environment]::GetEnvironmentVariable('GRUVGOLD_NAME', 'User') }

    # fastfetch reads no environment variables, so the name and this machine's
    # local drives are baked into its copy.
    $ffCfg = "$env:USERPROFILE\.config\fastfetch\config.jsonc"
    $disks = @((Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3').DeviceID | ForEach-Object { "`"$_\\`"" }) -join ', '
    $ff = (Get-Content $ffCfg -Raw -Encoding UTF8) -replace '"folders":\s*\[[^\]]*\]', "`"folders`": [$disks]"
    if ($Name) { $ff = $ff.Replace('{user-name}', $Name) }
    [IO.File]::WriteAllText($ffCfg, $ff, (New-Object System.Text.UTF8Encoding $false))
    Say "fastfetch: name $(if ($Name) { $Name } else { $env:USERNAME }), drives $disks" 'Green'

    # Append to the profile rather than overwrite it, and only once. Earlier
    # versions added an oh-my-posh block, a greeting block and an exam: block;
    # all are superseded by gruvgold.ps1, so strip them.
    $marker = '# --- GruvGold shell ---'
    $init   = @"
$marker
. "`$env:USERPROFILE\.config\powershell\gruvgold.ps1"
"@
    foreach ($p in @(
        "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
        "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    )) {
        New-Item -ItemType Directory -Path (Split-Path $p) -Force | Out-Null
        if (-not (Test-Path $p)) { New-Item -ItemType File -Path $p -Force | Out-Null }
        $text = Get-Content $p -Raw -ErrorAction SilentlyContinue
        if ($text -match '# --- GruvGold (prompt|greeting|exam mode) ---') {
            # prompt/greeting: marker through closing brace; exam mode: marker + one line.
            $text = $text -replace '(?ms)\r?\n?^# --- GruvGold (prompt|greeting) ---\r?\n.*?^\}[^\r\n]*', '' `
                          -replace '(?m)\r?\n?^# --- GruvGold exam mode ---\r?\n[^\r\n]*', ''
            # UTF-8 with BOM: the one encoding both PowerShell 5.1 and 7 read correctly.
            [IO.File]::WriteAllText($p, $text.TrimEnd() + "`r`n", (New-Object System.Text.UTF8Encoding $true))
            Say "removed old oh-my-posh/greeting/exam blocks from $(Split-Path $p -Leaf)" 'Green'
        }
        if ($text -match [regex]::Escape($marker)) {
            Say "shell already in $(Split-Path $p -Leaf)" 'DarkGray'
        } else {
            Add-Content $p "`n$init"
            Say "added shell to $(Split-Path $p -Leaf)" 'Green'
        }
    }

    Head '[9/11] btop theme and config'
    Deploy (Join-Path $cfg 'btop\gruvgold.theme') "$env:USERPROFILE\.config\btop\themes\gruvgold.theme"
    # btop4win also looks next to its own binary.
    $btopExe = (Get-Command btop4win, btop -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ($btopExe) {
        $btopThemes = Join-Path (Split-Path $btopExe) 'themes'
        New-Item -ItemType Directory -Path $btopThemes -Force | Out-Null
        Copy-Item (Join-Path $cfg 'btop\gruvgold.theme') (Join-Path $btopThemes 'gruvgold.theme') -Force
        Say "copied theme beside btop binary" 'Green'
        # btop rewrites its config on exit, so this is the full file, not a patch.
        Deploy (Join-Path $cfg 'btop\btop.conf') (Join-Path (Split-Path $btopExe) 'btop.conf')
    }

    Head '[10/11] Rainmeter skins'
    Deploy (Join-Path $cfg 'rainmeter\Skins\GruvGold') "$env:USERPROFILE\Documents\Rainmeter\Skins\GruvGold"

    Head '[11/11] AutoHotkey + rice scripts'
    Deploy (Join-Path $cfg 'ahk\desktop-type-to-launch.ahk') "$live\desktop-type-to-launch.ahk"
    # Invoked per keypress by whkdrc for Win+Up / Win+Down / Win+Left / Win+Right, not run resident.
    Deploy (Join-Path $cfg 'ahk\snap-half.ahk') "$live\snap-half.ahk"
    # Invoked per keypress by whkdrc for Win+D, not run resident.
    Deploy (Join-Path $cfg 'ahk\toggle-desktop.ahk') "$live\toggle-desktop.ahk"
    # Run later by the autostart shortcut, exam: and the Flow ExamMode plugin.
    # exam-mode.ps1 finds start.ps1 through scripts\, as it does in the repo.
    Deploy (Join-Path $PSScriptRoot 'start.ps1')     "$live\scripts\start.ps1"
    Deploy (Join-Path $PSScriptRoot 'exam-mode.ps1') "$live\scripts\exam-mode.ps1"
}

# ================================================================= settings
if (-not $SkipSettings) {

    Head 'Windows settings'

    # ---- wallpaper -------------------------------------------------------
    # From the installed copy: the lock screen reads the file by path.
    $wall = "$live\theme\wallpaper.png"
    Deploy (Join-Path $repo 'theme\wallpaper.png') $wall
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
    # taskbar buttons. TranslucentTB then removes the background.
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
        # The HKLM policy is ignored on Home; the per-user WinRT call works everywhere without admin.
        # The projection only exists in Windows PowerShell 5.1, so it always runs there.
        $lockScript = @'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime]
$ext = [System.WindowsRuntimeSystemExtensions].GetMethods()
$op = ($ext | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$act = ($ext | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and -not $_.IsGenericMethod })[0]
$file = $op.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @([Windows.Storage.StorageFile]::GetFileFromPathAsync($env:GG_WALL))).Result
$act.Invoke($null, @([Windows.System.UserProfile.LockScreen]::SetImageFileAsync($file))).Wait()
'@
        $env:GG_WALL = $wall
        powershell.exe -NoProfile -Command $lockScript
        if ($LASTEXITCODE -eq 0) { Say "lock screen image set" 'Green' }
        else { Say "lock screen: could not set image - set it in Settings > Personalization > Lock screen" 'DarkYellow' }
    }

    Head 'Restarting Explorer to apply taskbar changes'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Say "done" 'Green'
}

Write-Host "`nApplied. Start the stack with:  .\scripts\start.ps1`n" -ForegroundColor Green
exit 0
