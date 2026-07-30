# GruvGold — a Windows 11 rice

Gruvbox Dark on a pure-black base with a gold accent: a top bar, a floating transparent
taskbar, tiling with gold borders, a keyboard-driven launcher, a desktop clock with an
audio visualiser, and a translucent terminal that greets you with fastfetch.

**Nothing here modifies Windows itself.** No theme-signature patching, no `explorer.exe`
replacement, no system files touched, and no DLL injection apart from one scoped exception:
Windhawk, limited to `explorer.exe` (see [Windhawk](#windhawk-explorer-translucency)). Every component is a userspace
application drawing on top of the normal shell, so `explorer.exe` keeps owning the tray,
toasts, jump lists and file dialogs. The worst case to undo it is stopping a handful of
processes, and `uninstall.ps1` restores the settings it changed from a backup taken
first.

---

## Contents

- [Quick start](#quick-start)
- [Components](#components)
- [Palette](#palette)
- [Scripts](#scripts)
- [Where everything goes](#where-everything-goes)
- [Keybindings](#keybindings)
- [Terminal](#terminal)
- [Customising](#customising)
- [Repository layout](#repository-layout)
- [Windhawk](#windhawk-explorer-translucency)
- [Known issues and notes](#known-issues-and-notes)

---

## Quick start

Requirements: Windows 11 with `winget`, and Windows PowerShell 5.1 (built in). Python 3
from python.org is optional; it is only needed for the `exam:` Flow Launcher shortcut.

Clone the repo anywhere, then from the repo root:

```powershell
git clone https://github.com/InvictusRex/Win11-GruvGold-Rice.git
cd Win11-GruvGold-Rice
Set-ExecutionPolicy -Scope Process Bypass -Force   # allow the scripts for this session only

.\scripts\backup.ps1            # 1. snapshot what the rice will change (elevated shell also makes a restore point)
.\install.ps1 -IncludeFont      # 2. install the apps and the JetBrainsMono Nerd Font
#   now open Flow Launcher, Rainmeter and Windows Terminal once each, so they
#   create the settings files the next step edits, then open a NEW terminal
.\scripts\apply.ps1             # 3. deploy the configs and Windows settings
.\scripts\start.ps1 -Autostart  # 4. start everything, and again at every login
```

Every script is safe to re-run. `apply.ps1` reports anything it had to skip (usually an
app that has not been opened yet); open that app once and run it again.

**The clone is only the source.** `apply.ps1` *copies* each config to where its app reads
it, and installs the scripts the rice runs later (autostart, exam mode) plus the theme
images to `%LOCALAPPDATA%\GruvGoldRice`. Editing the clone changes nothing until you run
`apply.ps1` again, and the rice keeps working if the clone is moved or deleted.

---

## Components

| What | Tool | Config |
|---|---|---|
| Top bar | [YASB](https://github.com/amnweb/yasb) | `yasb/` |
| Bottom bar, tray, notifications | native Windows taskbar + [TranslucentTB](https://github.com/TranslucentTB/TranslucentTB) | `translucenttb/`, Windows settings |
| Desktop clock + audio visualiser | [Rainmeter](https://www.rainmeter.net/) | `rainmeter/` |
| Launcher | [Flow Launcher](https://www.flowlauncher.com/) + [Everything](https://www.voidtools.com/) for file search | `flow-launcher/` |
| Win key → launcher, type-on-desktop → launcher, Space+Enter → terminal | [AutoHotkey v2](https://www.autohotkey.com/) | `ahk/desktop-type-to-launch.ahk` |
| Win+arrow half-screen snapping, Win+D | AutoHotkey v2, called by whkd | `ahk/snap-half.ahk`, `ahk/toggle-desktop.ahk` |
| Tiling, gold borders, hotkeys | [komorebi](https://github.com/LGUG2Z/komorebi) + whkd, masir for hover-to-focus | `komorebi/` |
| Terminal | Windows Terminal + a plain PowerShell prompt + [fastfetch](https://github.com/fastfetch-cli/fastfetch) | `terminal/`, `powershell/`, `fastfetch/` |
| System monitor | [btop4win](https://github.com/aristocratos/btop4win), `btop` in PowerShell and Flow | `btop/`, `flow-launcher/plugins/Btop/` |
| Explorer translucency | [Windhawk](https://windhawk.net) mods, `explorer.exe` only | `windhawk/` |

The top bar holds the clock and network traffic on the left, the active window title in
the centre, and media, Wi-Fi, Bluetooth, battery, a control centre, the Recycle Bin and a
full-screen power menu on the right.

The bottom bar is the stock Windows taskbar, centred with labels, with TranslucentTB
making its background fully transparent, so only the buttons and tray float over the
wallpaper.

---

## Palette

`theme/palette.json` is the single source of truth. The colours were sampled from a
screenshot of an Obsidian theme rather than eyeballed (`cols.csv` holds the samples), then
copied into every component config.

| Token | Hex | Role |
|---|---|---|
| `bg` | `#000000` | base, bar background |
| `bg_alt` | `#0D0C09` | card / panel surface |
| `bg_elev` | `#16130D` | hover, selected row |
| `border` | `#282421` | hairlines |
| `fg` | `#FBF1C7` | primary text (gruvbox `fg0`) |
| `fg_dim` | `#BDAE93` | secondary text (gruvbox `fg3`) |
| `fg_muted` | `#7C6F64` | placeholder (gruvbox `gray`) |
| `gold` | `#D5AC45` | accent |
| `gold_dim` | `#D1A433` | accent pressed |

Font: **JetBrainsMono NF** (`install.ps1 -IncludeFont`). The bar uses a single 15px size
everywhere; per-widget font sizes are deliberately not used.

---

## Scripts

`install.ps1` is at the repo root; everything else is in `scripts/`. Run them from the
repo root. All of them are idempotent.

### `scripts/backup.ps1` — run first

Snapshots everything the rice will change, so `uninstall.ps1` can put it back. Each run
creates a new timestamped folder under `%LOCALAPPDATA%\GruvGoldRice-backup`, outside the
clone, so re-cloning or deleting the repo never loses it.

1. **System Restore point** named `pre-rice`, in an elevated shell only (skipped
   otherwise, or with `-SkipRestorePoint`). It lifts Windows' one-per-24h throttle for
   this call and puts the setting back.
2. **Registry exports** (`.reg`) of the keys the rice edits: Explorer `Advanced`, theme
   `Personalize`, `DWM`, `Control Panel\Desktop` and the accent key.
3. **Config files** the rice overwrites: both PowerShell profiles, Windows Terminal's
   `settings.json`, `komorebi.json`, `whkdrc`, and the YASB and Flow Launcher settings
   folders.
4. **Plain-text state** in `state.json`: wallpaper path, taskbar alignment and grouping,
   light/dark mode, accent settings. It also writes `preinstalled.json`, the list of the
   rice's packages that were already installed, which `uninstall.ps1 -RemovePackages`
   never removes.

### `install.ps1` — install the apps

Installs the packages with winget, skipping any already present, and prints a summary of
anything that failed (usually a declined elevation prompt; re-run in an admin shell).

| Package | Purpose |
|---|---|
| `Microsoft.PowerShell` | PowerShell 7 |
| `AmN.yasb` | top bar |
| `CharlesMilette.TranslucentTB` | transparent taskbar |
| `Flow-Launcher.Flow-Launcher` | launcher |
| `voidtools.Everything` | instant file search for Flow |
| `AutoHotkey.AutoHotkey` | Win key, desktop typing, snapping, Win+D |
| `Rainmeter.Rainmeter` | desktop clock and visualiser |
| `aristocratos.btop4win` | system monitor |
| `Fastfetch-cli.Fastfetch` | terminal greeting |
| `LGUG2Z.komorebi`, `LGUG2Z.whkd` | tiling window manager and its hotkey daemon |
| `LGUG2Z.masir` | focus-follows-mouse for komorebi |
| `RamenSoftware.Windhawk` | Explorer translucency (mods are installed by hand) |
| `DEVCOM.JetBrainsMonoNerdFont` | the font (only with `-IncludeFont`, machine-wide, prompts for elevation) |

It changes no settings and writes no configs; that is `apply.ps1`'s job. Open a new
terminal afterwards so the new commands are on `PATH`.

### `scripts/apply.ps1` — deploy configs and settings

```powershell
.\scripts\apply.ps1                  # configs + Windows settings
.\scripts\apply.ps1 -SkipSettings    # configs only (no registry, no Explorer restart)
.\scripts\apply.ps1 -SkipConfigs     # Windows settings only
.\scripts\apply.ps1 -Name invictus   # name shown in the prompt and fastfetch title
```

**Configs** (skipped with `-SkipConfigs`):

1. **YASB**: `config.yaml` and `styles.css`. The profile picture goes to
   `%LOCALAPPDATA%\GruvGoldRice\theme\profile.png`, and its absolute path is written into
   the deployed config. It also seeds TranslucentTB's `settings.json` if there is none, so
   TranslucentTB stops showing its first-run dialog at every boot. An existing one is
   never overwritten.
2. **komorebi + whkd**: `komorebi.json` and `whkdrc`. It also downloads the community
   `applications.json` rule set for apps that misbehave when tiled.
3. **Flow Launcher theme**: installs `GruvGold.xaml` and selects it. The window is 1000
   logical px wide and centred on the focused monitor, with up to 8 results.
4. **Everything backend**: switches Flow's file search and path search to Everything.
   Content search stays on the Windows index.
5. **Flow plugin cleanup**:
   - Web searches are trimmed to Google (the fallback), Scholar (`sc:`, with its own
     icon), Maps (`maps:`), Translate (`translate:`), Gmail (`gmail:`) and YouTube
     (`youtube:`). Keywords end in a colon.
   - The launcher's empty-query list is fixed to `>`, `doc:`, `game:`, `home`, `github`,
     `linkedin`, `exam:`, `gmail:`, `youtube:`, `translate:`, `maps:`, `sc:`, `btop`, in
     that order, with their own icons. Picking a keyword fills the query box;
     `home`, `github` and `linkedin` open the links and `btop` opens btop. Typing
     `home`, `github` or `btop` finds the same shortcut. This needs the patched Plugin
     Indicator, built from `flow-launcher/plugin-indicator-patch/`.
   - Browser Bookmarks is disabled, and plugin auto-updates are turned off.
   - If Python 3 is found, it installs the ExamMode plugin (`exam:` then `on`).
6. **Stop auto-updates**: turns off Rainmeter's update check and PowerShell 7's "new
   version available" notice.
7. **Windows Terminal**: adds the GruvGold colour scheme as a fragment, then patches
   `settings.json` (details in [Terminal](#terminal)).
8. **PowerShell + fastfetch**: deploys `gruvgold.ps1` and adds one dot-source line to the
   PowerShell 5 and 7 profiles, leaving the rest of your profile alone. It deploys the
   fastfetch config and writes this machine's local drives and your chosen name into it.
   Blocks added to the profiles by older versions of the rice are removed.
9. **btop theme and config**: the theme in `~\.config\btop\themes` and next to the btop binary,
   and the full `btop.conf` beside the binary (btop rewrites it on exit).
10. **Rainmeter skins**: the clock and the visualiser.
11. **AutoHotkey scripts and rice scripts**: the three `.ahk` files, plus `start.ps1` and
    `exam-mode.ps1`, go to `%LOCALAPPDATA%\GruvGoldRice`.

**Windows settings** (skipped with `-SkipSettings`):

- Wallpaper: `theme/wallpaper.png`, copied to `%LOCALAPPDATA%\GruvGoldRice\theme` and
  set to fill.
- Dark mode for apps and the system.
- The Windows accent-colour window border is turned off; komorebi draws the focus border
  instead.
- Aero Snap drag-to-edge stays on; Win+arrow belongs to whkd.
- Taskbar centred, with labels always shown and buttons never combined.
- Native Win+D is disabled, so it doesn't fight the rice's own Win+D.
- Lock screen image: set per user through the WinRT `LockScreen` API, so it needs no admin and
  works on Windows Home. The clock keeps Windows' font.
- Explorer is restarted so the taskbar changes apply.

### `scripts/start.ps1` — bring the rice up or down

```powershell
.\scripts\start.ps1              # start whatever is not already running
.\scripts\start.ps1 -Stop        # stop everything
.\scripts\start.ps1 -Restart     # stop, then start
.\scripts\start.ps1 -NoTiling    # everything except komorebi
.\scripts\start.ps1 -Autostart   # also start at every login
```

It starts things in this order: Everything, TranslucentTB, YASB, Flow Launcher, Rainmeter,
the AutoHotkey desktop hook, then komorebi with whkd. Anything already running is left
alone. Once komorebi is up it sets things over its CLI that this komorebi version does
not reliably take from `komorebi.json`:

- the palette's border colours;
- mouse-follows-focus turned off;
- ignore rules for the invisible IME helper windows and for common game launchers
  (Steam, Epic, GOG, Ubisoft, Riot, TLauncher, Paradox);
- starting masir for hover-to-focus.

Finally it activates the Rainmeter skins.

`-Stop` shuts komorebi down through its CLI, so your windows are un-tiled cleanly instead
of being stranded. `-Autostart` puts one `GruvGold - Startup.lnk` in your Startup folder.
It runs the installed copy of `start.ps1` with a 5-second delay, which avoids the
start-up race behind a half-drawn bar and a stray focused Explorer window.

### `scripts/exam-mode.ps1` and `scripts/disable.ps1` — turn the rice off

```powershell
.\scripts\exam-mode.ps1          # stop everything, disable autostart
.\scripts\exam-mode.ps1 -Off     # re-enable autostart and bring the rice back
```

Made for proctored tests. AutoHotkey and Rainmeter are commonly blocklisted by name, and
global keyboard/mouse hooks (whkd, masir) are what behavioural checks look for.

- Stops everything the rice runs.
- Disables autostart by renaming the Startup shortcut, so a reboot mid-exam doesn't bring
  the rice back.
- Asks Windhawk to exit, which unloads its Explorer mods. Windhawk normally runs elevated, so
  a non-elevated shell cannot reach it; it is then reported, and you quit it from the tray.
- Checks that nothing is left running and names anything that is. The Everything
  *service* is ignored: it runs in session 0, draws no window and has no hooks.

The same thing is available from anywhere as `exam: on` / `exam: off` in PowerShell;
Flow Launcher only offers `exam:` then `on`, since it cannot be reached once the rice
is stopped. `disable.ps1` is an identical copy under a more general
name.

### `scripts/uninstall.ps1` — full reversal

```powershell
.\scripts\uninstall.ps1                        # stop, remove configs, restore settings
.\scripts\uninstall.ps1 -RemovePackages        # ...and uninstall the apps
.\scripts\uninstall.ps1 -From 20260926-120000  # restore a specific backup instead of the latest
```

1. Stops every rice process, komorebi through its CLI.
2. Removes the autostart shortcut and any Run-key entries.
3. Deletes every deployed config listed under
   [Where everything goes](#where-everything-goes), and removes the GruvGold lines from
   both PowerShell profiles and the `GRUVGOLD_NAME` variable.
4. Restores from the backup: imports the `.reg` files, copies back the profiles,
   `komorebi.json` and `whkdrc`, deletes taskbar values that did not exist before, and
   puts your old wallpaper back.
5. With `-RemovePackages`, uninstalls the apps, except any that were installed before
   `backup.ps1` ran.

Backups are left in place afterwards; delete `%LOCALAPPDATA%\GruvGoldRice-backup` by hand
once you are sure.

---

## Where everything goes

| Deployed file(s) | Location |
|---|---|
| YASB `config.yaml`, `styles.css` | `~\.config\yasb\` |
| `komorebi.json` | `~\komorebi.json` |
| `whkdrc` | `~\.config\whkdrc` |
| komorebi `applications.json` (downloaded) | `~\.config\komorebi\` |
| Flow Launcher theme | `%APPDATA%\FlowLauncher\Themes\GruvGold.xaml` |
| Flow ExamMode plugin | `%APPDATA%\FlowLauncher\Plugins\ExamMode\` |
| Flow home list and icons | `%APPDATA%\FlowLauncher\Settings\Plugins\Flow.Launcher.Plugin.PluginIndicator\` |
| Terminal colour scheme | `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\GruvGold\` |
| Terminal defaults and tab-row theme | patched into Terminal's own `settings.json` |
| PowerShell prompt and greeting | `~\.config\powershell\gruvgold.ps1`, plus one line in each profile |
| fastfetch config and logo | `~\.config\fastfetch\` |
| btop theme and config | `~\.config\btop\themes\` and next to `btop4win.exe` |
| btop launcher plugin | `%APPDATA%\FlowLauncher\Plugins\Btop\` |
| Rainmeter skins | `~\Documents\Rainmeter\Skins\GruvGold\` |
| AutoHotkey scripts, `start.ps1`, `exam-mode.ps1`, wallpaper, profile picture | `%LOCALAPPDATA%\GruvGoldRice\` |
| TranslucentTB settings (only if none exist) | TranslucentTB's package `RoamingState` |
| Autostart shortcut | `shell:startup\GruvGold - Startup.lnk` |
| Backups | `%LOCALAPPDATA%\GruvGoldRice-backup\` |
| Prompt name (`-Name`) | user environment variable `GRUVGOLD_NAME` |

---

## Keybindings

### Launcher and desktop (AutoHotkey)

| Key | Action |
|---|---|
| **`Win`** tapped alone | opens Flow Launcher instead of the Start menu (tap again to close) |
| typing on the desktop | opens Flow Launcher with what you typed |
| hold `Space`, press `Enter` | opens Windows Terminal in your home folder |
| `Ctrl + Esc` | the real Start menu |
| `Ctrl + Alt + D` | suspends / resumes the above |
| `Ctrl + C` inside btop | quits btop (it only exits on `q` natively) |

Every other `Win + <key>` combination (E, R, L, …) still works as usual.

### Windows and tiling (komorebi via whkd)

The modifier is **Alt**, since Windows reserves most `Win` combinations.

| Key | Action |
|---|---|
| `Alt + h / j / k / l` | focus left / down / up / right |
| `Alt + Shift + h / j / k / l` | move window left / down / up / right |
| `Alt + Shift + Enter` | promote to the main tile |
| `Alt + [` / `Alt + ]` | cycle focus previous / next |
| `Alt + - / =` | shrink / grow horizontally |
| `Alt + Shift + - / =` | shrink / grow vertically |
| `Alt + q` | close window |
| `Alt + f` | toggle monocle (one window fills the workspace) |
| `Alt + Shift + f` | toggle maximise |
| `Alt + t`, `Win + j` | toggle tiling for the workspace |
| `Alt + ←/↓/↑/→` | stack onto the window in that direction |
| `Alt + Shift + u` | unstack |
| `Alt` + backtick | cycle through the stack |
| `Alt + Shift + b / c / r / v / t` | layout: BSP / columns / rows / vertical stack / ultrawide |
| `Alt + Shift + x / y` | flip the layout horizontally / vertically |
| `Alt + 1..5` | switch to workspace 1–5 |
| `Alt + Shift + 1..5` | move window to workspace 1–5 |
| `Win + Shift + ← / →` | move window left / right |
| `Alt + Shift + q` | reload the komorebi config |
| `Alt + Shift + Esc` | stop komorebi and whkd |

### Snapping and Show Desktop (whkd → AutoHotkey)

| Key | First press | Second press |
|---|---|---|
| `Win + ↑` | top half | fills the screen |
| `Win + ↓` | bottom half | minimise |
| `Win + ←` / `Win + →` | left / right half | back into the tiling |
| `Win + D` | minimise all windows (the bar and widgets stay) | restore them |

---

## Terminal

`apply.ps1` changes these Windows Terminal defaults and nothing else in your profiles:

- the GruvGold colour scheme;
- 80% opacity, no acrylic;
- JetBrainsMono NF at 11pt, one character of left padding, hidden scrollbar;
- a transparent tab row, with tabs in the terminal's own background colour.

It also starts Terminal's Windows PowerShell and PowerShell 7 profiles with `-NoLogo`, so
no banner or "Loading personal and system profiles" line appears.

The prompt (`powershell/gruvgold.ps1`) is plain PowerShell rather than oh-my-posh. That
saves about 400 ms at startup and a process spawn on every prompt.

```
[name@HOST] C:\Users\you
> _
```

- **Prompt:** the path is shown in full, and the `>` turns red after a failed command.
  There is always exactly one blank line between the previous output and the next prompt,
  however that output ended.
- **Typed text** stays in the terminal's off-white instead of per-token colours.
- **fastfetch** greets you once per Terminal tab, with a braille dragon logo; nested shells
  don't repeat it.
- **`exam: on` / `exam: off`** is available in every shell.

---

## Customising

- **Name in the prompt and fastfetch.** Run `.\scripts\apply.ps1 -Name <name>`. The default
  is your Windows user name, and the choice is remembered in `GRUVGOLD_NAME`.
- **Anything else.** Edit the file in the clone, then run `.\scripts\apply.ps1
  -SkipSettings` to redeploy. Run `.\scripts\start.ps1 -Restart` if a running app needs to
  reload.
- **Colours** live in `theme/palette.json`. The component configs carry their own copies
  of the values (YASB `styles.css`, `GruvGold.xaml`, the Terminal fragment, btop, the
  Rainmeter skins, komorebi borders in `start.ps1`), so change them there too.
- **Wallpaper and profile picture.** Replace `theme/wallpaper.png` or `theme/profile.png`
  and re-run `apply.ps1`.
- **Keybindings** are in `komorebi/whkdrc` and `ahk/desktop-type-to-launch.ahk`.

---

## Repository layout

```
install.ps1              winget installs
scripts/                 backup, apply, start, exam-mode (+ disable), uninstall
theme/                   palette.json, wallpaper.png, profile.png
ahk/                     Win key / desktop typing / Space+Enter, snapping, Win+D
btop/                    btop theme and config
fastfetch/               fastfetch config and the dragon logo
flow-launcher/           theme, icons, ExamMode and Btop plugins, Plugin Indicator patch
komorebi/                komorebi.json, whkdrc
powershell/              prompt, input colours, greeting, exam:, btop alias
rainmeter/               clock and visualiser skins
terminal/                Windows Terminal colour scheme fragment
translucenttb/           seed settings for TranslucentTB
windhawk/                settings and patches for the Explorer mods
yasb/                    bar config and styles
cols.csv                 colour samples behind the palette
```

---

## Windhawk (Explorer translucency)

Windhawk hooks only `explorer.exe`; it patches no system file, so uninstalling it is a full
revert. Mods can only be installed from its window, so `apply.ps1` does not do it. Once,
after `install.ps1`:

1. In Windhawk's settings leave "inject into games" and "critical processes" **off** (the
   defaults) and turn off mod auto-update.
2. Install **Translucent Windows**. In its Advanced tab set the custom process inclusion list
   to `explorer.exe` and tick *use only custom lists*; without that it still loads into every
   process. Apply `windhawk/translucent-windows.patch` in the mod's editor and compile (it
   swaps the blur for a flat see-through tint, so Explorer matches the 80%-opaque terminal),
   then enter the values from `windhawk/translucent-windows.json`.
3. Install **Windows 11 File Explorer Styler**: theme `Translucent Explorer11`, translucent
   background effect `None`, plus the control styles in `windhawk/file-explorer-styler.json`.
4. Install **Explorer Font Changer**, apply `windhawk/explorer-font-changer.patch` (adds a
   *Font size scale* setting), compile, and use `windhawk/explorer-font-changer.json`.
5. Restart Explorer.

A hook that stops matching after a Windows update simply does not load; nothing breaks. If
Explorer misbehaves, quit Windhawk from the tray, run `windhawk.exe -safe-mode`, or uninstall
it from Settings → Apps. Mods that Windhawk compiles are not part of this repository.

---
## Known issues and notes

- **Win+D is reimplemented.** On Windows 11 24H2 the native Show Desktop minimises
  always-on-top app bars like YASB and does not reliably bring them back (upstream,
  amnweb/yasb#62). `toggle-desktop.ahk` minimises ordinary windows itself and never
  touches the bar or widgets.
- **komorebi reads some settings unreliably.** It ignores border colours from
  `komorebi.json` and does not reliably apply ignore rules to 32-bit game launchers.
  `start.ps1` sets both over the CLI, so re-run `start.ps1 -Restart` rather than only
  reloading the komorebi config if borders look wrong.
- **Accent colour.** Windows regenerates the accent colour at every sign-in, so the rice
  turns the Windows accent border off rather than fighting it. The gold focus border comes
  from komorebi.
- **`Alt + Shift + R` is bound twice** in `whkdrc`: to the rows layout and to `retile`
  (which clears a phantom full-screen border left by some game launchers). Only one of
  them fires; give one a different key if you need both.
- **Flow Launcher content search** stays on the Windows index. Everything's content
  search was tried, and it reproducibly hung Flow's search engine.
- **Desktop typing** replaces Explorer's "jump to the icon starting with that letter".
  `Ctrl+Alt+D` turns it off.
- **Display scaling.** YASB sizes are logical pixels and were tuned at 150%.
  `yasb/launch-yasb.cmd`, a launcher that disables Qt's high-DPI scaling, is an older
  workaround that `start.ps1` no longer uses.
- **fastfetch disks** are listed explicitly (filled in by `apply.ps1`), because automatic
  detection also probes mapped network drives and stalls for 20 s or more when one is
  disconnected. Re-run `apply.ps1` after adding a drive.
