#Requires AutoHotkey v2.0
#SingleInstance Force
;
; desktop-type-to-launch.ahk
;
; Start typing while the desktop has focus and Flow Launcher opens, pre-filled
; with what you typed.
;
; The hotkeys are registered under a HotIf criterion, so a-z and 0-9 are only
; intercepted when the foreground window is the desktop itself. Everywhere else
; they are ordinary keys and AutoHotkey never sees them. Win+D, Win+E and the
; rest are untouched.
;
; Trade-off: this overrides Explorer's native "jump to the desktop icon starting
; with that letter". Ctrl+Alt+D suspends the script if you want that back.
;

FLOW_EXE     := "ahk_exe Flow.Launcher.exe"
FLOW_HOTKEY  := "!{Space}"          ; Flow Launcher's default open hotkey
WAIT_SECONDS := 1.5

; ---------------------------------------------------------------- criterion
DesktopFocused(*) {
    ; Show Desktop (Win+D) leaves NOTHING focused - WinExist("A") returns 0, not
    ; Progman. Previously that fell into the catch below and returned false, so
    ; typing straight after Win+D did nothing until you clicked the wallpaper.
    hwnd := WinExist("A")
    if (!hwnd)
        return true

    try {
        cls := WinGetClass(hwnd)
        ; Progman owns the desktop normally; WorkerW takes over when a wallpaper
        ; slideshow or web content is active. Both mean "the desktop is focused".
        return (cls = "Progman" || cls = "WorkerW")
    } catch {
        return true                  ; nothing we can identify - treat as desktop
    }
}

; ---------------------------------------------------------------- hotkeys
; The $ prefix stops our own Send from re-triggering these hotkeys.
HotIf DesktopFocused
Loop 26
    Hotkey "$" Chr(96 + A_Index), OpenLauncher      ; a-z
Loop 10
    Hotkey "$" Chr(47 + A_Index), OpenLauncher      ; 0-9
HotIf

OpenLauncher(hotkeyName) {
    char := SubStr(hotkeyName, -1)

    if !ProcessExist("Flow.Launcher.exe") {
        TrayTip "Flow Launcher is not running", "desktop-type-to-launch", 0x2
        return
    }

    ; If it is somehow already up, just type into it.
    if !WinActive(FLOW_EXE) {
        Send FLOW_HOTKEY
        if !WinWaitActive(FLOW_EXE, , WAIT_SECONDS)
            return                   ; launcher did not come up; swallow the key
    }
    SendText char
}

; ---------------------------------------------------------------- Windows key
; Tapping Win alone opens the launcher instead of the Start menu, while every
; Win+<key> combination keeps working.
;
; How: `~` passes the Win key through to Windows, so combos are untouched. On
; Win-down we also send vkE8 - an unassigned virtual key. Windows only opens the
; Start menu when Win is pressed and released with nothing in between, so that
; harmless extra keystroke is enough to suppress it. On Win-up, if vkE8 really
; was the last key seen, nothing else was pressed and it was a solo tap.
;
; The Start menu itself is still reachable with Ctrl+Esc.

~LWin::Send "{Blind}{vkE8}"
~RWin::Send "{Blind}{vkE8}"

; A_PriorKey tracks what the keyboard hook saw, and AHK's own Send does not
; update it - so after a solo tap it still reads "LWin", whereas after Win+E it
; reads "e". That is exactly the distinction we need.
~LWin Up:: {
    if (A_PriorKey = "LWin")
        WinKeyTapped()
}
~RWin Up:: {
    if (A_PriorKey = "RWin")
        WinKeyTapped()
}

WinKeyTapped() {
    ; Windows 11 does not always honour the neutralising keystroke above - Start
    ; or the Search flyout can still appear. If one did, dismiss it first, then
    ; show the launcher. Escape is only sent when one of those two is actually
    ; foreground, so it can never leak into another app.
    Sleep 90
    if WinActive("ahk_exe StartMenuExperienceHost.exe") || WinActive("ahk_exe SearchHost.exe") {
        Send "{Escape}"
        Sleep 120
    }
    ToggleLauncher()
}

ToggleLauncher() {
    if !ProcessExist("Flow.Launcher.exe") {
        TrayTip "Flow Launcher is not running", "desktop-type-to-launch", 0x2
        return
    }
    if WinActive(FLOW_EXE) {
        Send "{Escape}"          ; second tap closes it again
        return
    }
    Send FLOW_HOTKEY
}

; ---------------------------------------------------------------- Win + up/down
; Deliberately NOT handled here. The `~LWin` neutraliser above breaks AHK's own
; `#Up` / `#Down` modifier matching (verified: they stop firing entirely, and
; matching on GetKeyState instead does not help). whkd hooks the keyboard
; independently and is unaffected, so whkdrc binds Win+Up/Down to snap-half.ahk.

; ---------------------------------------------------------------- shortcuts
; Space & Enter, held together, opens PowerShell. `&` makes Space a custom
; prefix key for this combo; the leading `~` is required to also pass Space
; through as a normal keystroke everywhere else - without it AHK swallows
; every space bar press globally, since Space then has no other hotkey.
; Launched through Terminal (not powershell.exe directly) so it gets the
; Terminal profile: -NoLogo, home as start dir, and the fastfetch greeting.
~Space & Enter::Run "wt.exe", EnvGet("USERPROFILE")

; ---------------------------------------------------------------- escape hatch
^!d:: {
    Suspend -1
    state := A_IsSuspended ? "suspended - desktop letter-jump and Win key are back"
                           : "active - typing on the desktop opens Flow Launcher"
    TrayTip "desktop-type-to-launch", state, 0x1
}

TrayTip "desktop-type-to-launch", "Running. Win opens the launcher; Ctrl+Alt+D toggles.", 0x1

; ---------------------------------------------------------------- btop
; btop4win only quits on q; Ctrl+C reaches it as a plain key and is ignored.
; Windows Terminal titles the window "btop4win++" while it runs.
#HotIf WinActive("btop4win++ ahk_exe WindowsTerminal.exe")
^c::Send "q"
#HotIf
