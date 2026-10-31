# Manual installation

This is the whole GruvGold setup done by hand, step by step, without running `install.ps1`,
`apply.ps1` or `start.ps1`. It ends in the same place as the [scripted install](README.md#installation).
Every step only copies a file or changes a setting you can see, so you can stop at any point and keep
just the parts you like.

Conventions:

- `~` is your user folder (`%USERPROFILE%`, e.g. `C:\Users\you`).
- "The repo" is your clone of this repository; paths like `yasb/config.yaml` are inside it.
- "Copy" means a plain file copy. Create any destination folder that does not exist yet.

> [!IMPORTANT]
> **Night Light.** GruvGold was tuned with Windows Night Light on at its default strength (48). It
> looks colder without it. This guide uses **`theme/wallpaper-warm.png`**, the wallpaper with Night
> Light's tint baked in, so the rice looks as intended either way. If you keep Night Light on, use
> `theme/wallpaper.png` instead, or the wallpaper gets tinted twice. Night Light itself is in
> Settings → System → Display → Night light.

Before you start, note down anything you may want back: your wallpaper, your PowerShell profiles
(`~\Documents\PowerShell\` and `~\Documents\WindowsPowerShell\`) and Windows Terminal's
`settings.json`.

---

## 1. Install the apps

Install each with winget (one line per app), or from the linked site:

```powershell
winget install --id Microsoft.PowerShell --exact --source winget
winget install --id AmN.yasb --version 2.0.7 --exact --source winget   # 2.0.7 exactly, see step 3
winget install --id WinStep.Nexus --exact --source winget
winget install --id Flow-Launcher.Flow-Launcher --exact --source winget
winget install --id voidtools.Everything --exact --source winget
winget install --id AutoHotkey.AutoHotkey --exact --source winget
winget install --id Rainmeter.Rainmeter --exact --source winget
winget install --id aristocratos.btop4win --exact --source winget
winget install --id Fastfetch-cli.Fastfetch --exact --source winget
winget install --id LGUG2Z.komorebi --exact --source winget
winget install --id LGUG2Z.whkd --exact --source winget
winget install --id LGUG2Z.masir --exact --source winget
winget install --id RamenSoftware.Windhawk --exact --source winget
winget install --id DEVCOM.JetBrainsMonoNerdFont --exact --source winget   # the font, asks for admin
```

Then open **Flow Launcher, Rainmeter, Everything and Windows Terminal once each**, so they create
their settings files, and open a new PowerShell window so the new commands are on `PATH`.

---

## 2. Wallpaper and Windows settings

| Setting | Where | Value |
|---|---|---|
| Wallpaper | copy `theme/wallpaper-warm.png` to `%LOCALAPPDATA%\GruvGoldRice\theme\`, then Settings → Personalization → Background | that file, *Fill* |
| Lock screen | Settings → Personalization → Lock screen | the same file |
| Dark mode | Settings → Personalization → Colors → Choose your mode | Dark |
| Accent border | Settings → Personalization → Colors | *Show accent colour on title bars and window borders* **off** (komorebi draws the border) |
| Snapping | Settings → System → Multitasking → Snap windows | on |
| Taskbar | Settings → Personalization → Taskbar → Taskbar behaviours | alignment *Center*, *Automatically hide the taskbar* on |
| Touchpad | Settings → Bluetooth & devices → Touchpad → Advanced gestures → three-finger swipe down | *Custom shortcut*: <kbd>Win</kbd>+<kbd>D</kbd> |

Turn off Windows' own <kbd>Win</kbd>+<kbd>D</kbd> so it does not race the rice's version: in
`regedit`, open `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced`,
create the string value `DisabledHotkeys` (or edit it if present) and add the letter `D` to it. It
applies after you restart Explorer (Task Manager → Windows Explorer → Restart).

---

## 3. Top bar (YASB)

1. Copy `yasb/config.yaml` and `yasb/styles.css` to `~\.config\yasb\`.
2. Copy `theme/profile.png` to `%LOCALAPPDATA%\GruvGoldRice\theme\profile.png`. In the copied
   `config.yaml`, set **both** `profile_image_path:` lines to that file's full path with forward
   slashes, e.g. `"C:/Users/you/AppData/Local/GruvGoldRice/theme/profile.png"`.
3. **Patch YASB.** The config uses options that only the rice's patched YASB modules understand, and
   the patches are whole modules from YASB **2.0.7**, so this needs exactly that version. YASB keeps
   its Python code compiled inside `C:\Program Files\YASB\lib\library.zip`:
   1. Quit YASB (tray icon → Exit).
   2. Copy `library.zip` to `library.zip.gruvgold-backup` next to it (needs admin), so you can undo.
   3. Open `library.zip` with an archive tool that can edit zips in place (7-Zip, run as admin).
   4. For every `.py` file under `yasb/patches/`, put it into the zip at the same path, and delete
      the `.pyc` file of the same name there. For example `yasb/patches/core/utils/utilities.py`
      goes in as `core/utils/utilities.py`, and `core/utils/utilities.pyc` is removed. YASB compiles
      the `.py` itself when it loads, so no Python install is needed.

   Undo by putting the backup back as `library.zip`. A YASB update replaces the zip and drops the
   patches, so stay on 2.0.7.

---

## 4. Tiling (komorebi, whkd, masir)

1. Copy `komorebi/komorebi.json` to `~\komorebi.json`.
2. Copy `komorebi/whkdrc` to `~\.config\whkdrc`.
3. Download the community rules for apps that misbehave when tiled to
   `~\.config\komorebi\applications.json`:
   `https://raw.githubusercontent.com/LGUG2Z/komorebi-application-specific-configuration/master/applications.json`

komorebi is started, and its borders set, in [step 13](#13-start-everything).

---

## 5. Launcher (Flow Launcher + Everything)

Quit Flow Launcher (tray icon → Exit) before editing its files; it rewrites them on exit.

1. Copy `flow-launcher/GruvGold.xaml` to `%APPDATA%\FlowLauncher\Themes\`.
2. In Flow's settings (open Flow, type `settings`):
   - **Appearance**: theme *GruvGold*.
   - **General**: search window width *1000*, maximum results *8*, window position *centre* on the
     *focused* screen, Pinyin search off.
   - **Plugins → Explorer**: index search engine *Everything*, path enumeration *Everything*, content
     search engine *Windows Index* (Everything's content search hangs Flow).
   - **Plugins → Browser Bookmarks**: disable.
   - **Plugins → Web Searches**: delete every search except Google (the `*` fallback), Google
     Scholar, Maps, Translate, Gmail and YouTube, and give those the keywords `sc:`, `maps:`,
     `translate:`, `gmail:` and `youtube:`. For Scholar's icon, copy
     `flow-launcher/icons/google_scholar.png` to
     `%APPDATA%\FlowLauncher\Settings\Plugins\Flow.Launcher.Plugin.WebSearch\CustomIcons\` and pick it.
   - **Plugins → Program**: *hide duplicated Windows apps* on.
   - **Plugins → Plugin Indicator**: enabled, action keywords `?` and `*`.
   - **Plugin Store / General**: automatic plugin updates off.
3. **Everything exclusions** (Everything → Tools → Options → Indexes → Exclude): tick *Enable
   exclude list* and add the folders `%USERPROFILE%\AppData` and `%USERPROFILE%\.*`, plus the names
   of the dotfiles in your user folder (`.gitconfig` and the like) as excluded files.
4. **Optional plugins** (need Python 3 from python.org; set its `python.exe` under Flow settings →
   General → Python path):
   - `exam:`: copy `flow-launcher/plugins/ExamMode\*` to `%APPDATA%\FlowLauncher\Plugins\ExamMode\`,
     and create `examscript.txt` there containing the full path of
     `%LOCALAPPDATA%\GruvGoldRice\scripts\exam-mode.ps1` (no newline).
   - `btop`: copy `flow-launcher/plugins/Btop\*` to `%APPDATA%\FlowLauncher\Plugins\Btop\`, and create
     `btoppath.txt` there containing the full path of `btop4win.exe` (`(Get-Command btop4win).Source`).
5. **Optional: the fixed home list.** The ordered list with its own icons that the launcher shows on an
   empty query comes from a patched copy of Flow's built-in *Plugin Indicator*:
   1. Copy `flow-launcher/icons/home/*` to
      `%APPDATA%\FlowLauncher\Settings\Plugins\Flow.Launcher.Plugin.PluginIndicator\Icons\`.
   2. Write that folder's `Settings.json` with a `HomeEntries` list (title, subtitle, icon path,
      keyword or URL for each row) and a `KeywordIcons` map. `$homeEntries` in `scripts/apply.ps1`
      has the exact entries, and the classes in `flow-launcher/plugin-indicator-patch/Settings.cs`
      define the format.
   3. Build the plugin: clone [Flow.Launcher](https://github.com/Flow-Launcher/Flow.Launcher) at the
      tag of your installed version, replace the files in `Plugins/Flow.Launcher.Plugin.PluginIndicator/`
      with the two in `flow-launcher/plugin-indicator-patch/`, build that project with the .NET SDK
      (`dotnet build -c Release`), and copy the resulting `Flow.Launcher.Plugin.PluginIndicator.dll`
      over the one in `%LOCALAPPDATA%\FlowLauncher\app-<version>\Plugins\Flow.Launcher.Plugin.PluginIndicator\`.
      A Flow update replaces that folder, so redo this after updating.

   Without this, Flow shows its stock home list; everything else works the same.

---

## 6. Terminal

1. Copy `terminal/gruvgold.json` to
   `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\GruvGold\gruvgold.json` (adds the colour scheme).
2. Open Terminal's `settings.json` (Settings → *Open JSON file*) and merge in:

   ```jsonc
   {
     "theme": "GruvGold",
     "useAcrylicInTabRow": true,
     "compatibility.enableUnfocusedAcrylic": true,
     "themes": [
       {
         "name": "GruvGold",
         "tab": { "background": "terminalBackground", "unfocusedBackground": "#00000000" },
         "tabRow": { "background": "#00000000", "unfocusedBackground": "#00000000" },
         "window": { "applicationTheme": "dark" }
       }
     ],
     "profiles": {
       "defaults": {
         "colorScheme": "GruvGold",
         "useAcrylic": false,
         "opacity": 80,
         "font": { "face": "JetBrainsMono NF", "size": 11 },
         "padding": "9, 0, 0, 0",
         "scrollbarState": "hidden"
       }
     }
   }
   ```

3. In the same file, add ` -NoLogo` to the end of the `commandline` of the *Windows PowerShell* and
   *PowerShell* profiles, so no banner prints before the greeting.

---

## 7. PowerShell prompt and fastfetch

1. Copy `powershell/gruvgold.ps1` to `~\.config\powershell\gruvgold.ps1`.
2. Add these two lines to the end of **both** profiles,
   `~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` (PowerShell 7) and
   `~\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` (Windows PowerShell). Save them as
   UTF-8 *with* BOM, which both versions read correctly:

   ```powershell
   # --- GruvGold shell ---
   . "$env:USERPROFILE\.config\powershell\gruvgold.ps1"
   ```

3. Copy the `fastfetch` folder to `~\.config\fastfetch`. In the copied `config.jsonc`:
   - replace `{user-name}` in the title line with the name you want shown (optional);
   - set the disk module's `"folders"` to your local drives, e.g. `["C:\\", "D:\\"]`.
4. To use the same name in the prompt, set it as a user environment variable:
   `[Environment]::SetEnvironmentVariable('GRUVGOLD_NAME', 'yourname', 'User')`.
5. Optional: turn off PowerShell 7's update notice with
   `[Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'Off', 'User')`.

---

## 8. btop

Find btop's folder with `Split-Path (Get-Command btop4win).Source`, then:

1. Copy `btop/gruvgold.theme` to `~\.config\btop\themes\` **and** to the `themes` folder next to
   `btop4win.exe`.
2. Copy `btop/btop.conf` next to `btop4win.exe`. btop rewrites this file when it exits, so copy it
   while btop is closed.

---

## 9. Desktop clock (Rainmeter)

1. Copy `rainmeter/Skins/GruvGold` to `~\Documents\Rainmeter\Skins\GruvGold`.
2. Right-click Rainmeter's tray icon → Skins → GruvGold → Clock → `Clock.ini` to load it.
3. Quit Rainmeter, open `%APPDATA%\Rainmeter\Rainmeter.ini` (keep it UTF-16) and set:

   ```ini
   [Rainmeter]
   CheckUpdates=0

   [GruvGold\Clock]
   Active=1
   WindowX=50%
   WindowY=83.125%
   AnchorX=50%
   AnchorY=0
   ```

   That centres the clock near the bottom, clear of the dock. Start Rainmeter again.

---

## 10. Dock (Nexus)

Nexus keeps its settings in `HKEY_CURRENT_USER\Software\WinSTEP2000\NeXuS`, and everything below can
be set from its own Preferences window (right-click the dock):

- **Position**: bottom edge, centred, docked and locked; auto-hide on, without the bounce; edge
  offset 10.
- **Icons**: size 35, spacing 10; no zoom, bounce, attention or delete effects; icons locked so they
  cannot be dragged off.
- **Behaviour**: show only pinned apps (no task list), auto-hide and pop-up delays 0, no sounds or
  voices.
- **Dock logo**: `nexus/logo.png` as the dock's control icon.
- **Pins**: drag your apps on. Pin desktop apps by their `.exe`. Pin Store apps (Terminal, Spotify,
  WhatsApp, …) by the path `shell:AppsFolder\<AUMID>`, where the AUMID comes from `Get-StartApps` in
  PowerShell (e.g. `shell:AppsFolder\Microsoft.WindowsTerminal_8wekyb3d8bbwe!App`). A Store app's
  `.exe` lives in a versioned folder that every update renames, and Windows often refuses to launch
  it directly, so an exe pin breaks.
- Nexus adds itself to *Run* at login; remove that (Task Manager → Startup apps → Nexus → Disable),
  since [step 13](#13-start-everything) starts it.

The gruvbox-graded pin icons in the screenshots are generated by `nexus/configure-nexus.ps1`. You can
run just that one script (from Windows PowerShell 5.1) to get the exact dock, or keep the apps' own
icons.

---

## 11. Explorer and the tray pill (Windhawk)

Follow [Windhawk in the README](README.md#windhawk). The Taskbar Styler settings can also be entered
in the mod's own settings page instead of running `windhawk/apply-taskbar-styler.ps1`: the script
lists each target and its styles, and sets *click through taskbar* on and XAML diagnostics handling
to *block*.

---

## 12. AutoHotkey and the rice scripts

1. Copy `ahk/desktop-type-to-launch.ahk`, `ahk/snap-half.ahk` and `ahk/toggle-desktop.ahk` to
   `%LOCALAPPDATA%\GruvGoldRice\`. `whkdrc` calls the last two by that path.
2. Optional, for `exam:` and autostart: copy `scripts/start.ps1` and `scripts/exam-mode.ps1` to
   `%LOCALAPPDATA%\GruvGoldRice\scripts\`.
3. For `exam: on` / `exam: off` in every shell, add to both PowerShell profiles:

   ```powershell
   function exam: { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\GruvGoldRice\scripts\exam-mode.ps1" $(if ("$args" -eq 'off') { '-Off' }) }
   ```

---

## 13. Start everything

Start the apps in this order: Everything (`Everything.exe -startup`), Nexus, YASB, Flow Launcher,
Rainmeter, then the desktop hook:

```powershell
& "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe" "$env:LOCALAPPDATA\GruvGoldRice\desktop-type-to-launch.ahk"
```

Then komorebi with whkd. `--config` is required; komorebi does not read `~\komorebi.json` on its own:

```powershell
komorebic start --whkd --config "$env:USERPROFILE\komorebi.json"
```

Once it is up, set the borders and focus behaviour over its CLI (this komorebi version does not
reliably take them from `komorebi.json`), then start masir for hover-to-focus:

```powershell
komorebic border-implementation komorebi
komorebic border --enable
komorebic border-width 1
komorebic border-offset -1
komorebic border-colour 131 165 152 -w single     # #83A598
komorebic border-colour 250 189 47  -w stack      # #FABD2F
komorebic border-colour 254 128 25  -w monocle    # #FE8019
komorebic border-colour 131 165 152 -w floating   # #83A598
komorebic border-colour 40  36  33  -w unfocused  # #282421
komorebic mouse-follows-focus disable
komorebic ignore-rule class "MSCTFIME UI"
komorebic ignore-rule class "IME"
masir
```

`scripts/start.ps1` also adds ignore rules for common game launchers (Steam, Epic, GOG, Ubisoft,
Riot, TLauncher, Paradox); add `komorebic ignore-rule path "<launcher.exe>"` for any you use.

**At every login**: put the commands above in a script and add a shortcut to it in your Startup
folder (<kbd>Win</kbd>+<kbd>R</kbd> → `shell:startup`). A few seconds' delay before it runs avoids a
half-drawn bar while Windows is still starting.

---

## Undoing it

Everything above is a copied file or a setting, so undo it the same way: quit the apps
(`komorebic stop --whkd` first, so komorebi releases your windows), delete the copied files and
folders, remove the GruvGold lines from your PowerShell profiles, put your wallpaper, Terminal
settings and the YASB `library.zip` backup back, and change the Windows settings in step 2 back.
Uninstall the apps from Settings → Apps.
