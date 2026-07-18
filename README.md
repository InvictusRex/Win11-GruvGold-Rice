# GruvGold — a Windows 11 rice

Gruvbox Dark on a pure-black base with a gold accent, matching the Obsidian theme in
`references/obsidian_rice.png`.

**Nothing here modifies Windows.** No theme-signature patching, no `explorer.exe`
replacement, no DLL injection, no system files touched. Every component is a userspace
application drawing on top of the normal shell, so `explorer.exe` keeps owning the tray,
toasts, jump lists and file dialogs. Worst-case reversal is stopping six processes.

---

## Palette

Sampled from `references/obsidian_rice.png` rather than eyeballed. `palette.json` is the
single source of truth.

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

Font: **JetBrainsMono NF**. The bar uses a single 15px size everywhere; per-widget font
sizes are deliberately not used.

---

## Components

| What | Tool | Config |
|---|---|---|
| Top bar | YASB | `config/yasb/` |
| Bottom bar, tray, notifications | native Windows taskbar + TranslucentTB | Settings + TTB |
| Desktop clock + audio visualiser | Rainmeter | `config/rainmeter/` |
| Launcher | Flow Launcher | `config/flow-launcher/GruvGold.xaml` |
| Type-on-desktop → launcher, Win key | AutoHotkey v2 | `config/ahk/desktop-type-to-launch.ahk` |
| Win+Up/Down half-screen snapping | AutoHotkey v2, called by whkd | `config/ahk/snap-half.ahk` |
| Tiling, gold borders, gaps | komorebi + whkd | `config/komorebi/` |
| Terminal | Windows Terminal + a plain PowerShell prompt + fastfetch | `config/terminal/`, `config/powershell/`, `config/fastfetch/` |
| System monitor | btop4win | `config/btop/` |

The bottom bar is the stock Windows taskbar with TranslucentTB making its background
fully transparent, so only the centred buttons and tray float over the wallpaper.

---

## Scripts

Run in this order on a fresh machine:

```powershell
.\backup.ps1      # restore point + registry/config backup   (run elevated for the restore point)
.\install.ps1     # winget installs, idempotent
.\apply.ps1       # deploy configs + Windows settings
.\start.ps1       # bring the stack up
.\start.ps1 -Autostart   # ...and register it to start at login
```

Other switches:

```powershell
.\start.ps1 -Stop          # stop everything
.\start.ps1 -Restart
.\start.ps1 -NoTiling      # everything except komorebi
.\apply.ps1 -SkipSettings  # redeploy configs only
.\uninstall.ps1            # full reversal
.\uninstall.ps1 -RemovePackages   # ...and uninstall the apps
```

---

## Keybindings (komorebi via whkd)

Mod is **Alt**. `Win + arrow` is also bound, since Aero Snap is turned off in favor of
komorebi.

| Key | Action |
|---|---|
| `Alt + h/j/k/l` | focus left/down/up/right |
| `Alt + Shift + h/j/k/l` | move window |
| `Alt + Shift + Enter` | promote to primary |
| `Alt + q` | close |
| `Alt + v` | toggle float |
| `Alt + f` | toggle monocle |
| `Alt + 1..5` | focus workspace |
| `Win + ←/→` | focus window left/right |
| `Win + ↑` | top half / maximise on repeat |
| `Win + ↓` | bottom half / minimise on repeat |
| **`Win`** (tapped alone) | opens Flow Launcher instead of Start menu |

---

## Notable custom work

- **Palette pipeline** — colors sampled directly from the reference screenshot rather
  than eyeballed, then propagated to every component config from one `palette.json`.
- **Win-key remap** — a solo `Win` tap opens Flow Launcher instead of Start, while every
  `Win+<key>` combo (E, R, L, arrows) still passes through untouched.
- **Half-screen snapping via whkd + AHK**, replacing Aero Snap, because Windows' own
  Win+arrow fights komorebi's tiling otherwise.
- **Gold focus border** — the Windows accent border is disabled (it silently resets on
  sign-in) in favor of a single border drawn by komorebi.
- **YASB right-region workaround** at 150% display scaling — an upstream bug anchors
  that region off-screen at physical-pixel coordinates, so its widgets live in `center`
  instead.
