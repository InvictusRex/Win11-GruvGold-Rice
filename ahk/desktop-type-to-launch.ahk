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
        ; Closing Flow Launcher hands focus to a Rainmeter skin window (they sit
        ; on the desktop), so that counts as the desktop too.
        return (cls = "Progman" || cls = "WorkerW" || cls = "RainmeterMeterWindow")
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

; ---------------------------------------------------------------- bottom edge
; Two auto-hide bars share the bottom edge: the Nexus dock (apps) and the native taskbar,
; which Windhawk reduces to the tray pill. Explorer reveals the taskbar from the whole edge,
; so the pill used to pop up wherever the pointer touched the bottom.
; Explorer reacts only to the last 2 pixel rows; Nexus (EdgeBufferZone=6, see
; configure-nexus.ps1) reacts from 6 rows up. So outside the bottom-right corner the pointer
; is held just short of Explorer's rows (the dock still triggers) and only inside the corner
; may it reach the edge itself (the pill shows). Nexus triggers there too, so both bars appear
; in the corner - the dock cannot be kept out without also losing its trigger elsewhere.
; The pointer is moved from a low-level mouse hook: Windows applies the clamp before any
; program sees the unclamped position.
TRAY_CORNER_W := 300    ; width of the corner that reaches the edge, physical px
EDGE_HELD_ROWS := 3     ; rows above the screen edge the pointer cannot enter elsewhere

BottomEdgeHook(nCode, wParam, lParam) {
    if (nCode = 0 && wParam = 0x200 && !A_IsSuspended) {     ; WM_MOUSEMOVE
        x := NumGet(lParam, 0, "Int"), y := NumGet(lParam, 4, "Int")
        limit := A_ScreenHeight - 1 - EDGE_HELD_ROWS
        if (y > limit && x >= 0 && x < A_ScreenWidth - TRAY_CORNER_W) {
            DllCall("SetCursorPos", "Int", x, "Int", limit)
            return 1                                         ; swallow the unclamped move
        }
    }
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

; ---------------------------------------------------------------- dock focus
; Nexus takes the foreground when the dock pops up and only gives it back after the hide
; slide has finished, about 0.3s after the pointer left - so typing goes nowhere in between.
; Hand it back the moment the pointer is off the dock: to the window under the pointer, or
; the last window that was in use if the pointer is over the desktop, a bar or the dock.
DockFocusBack() {
    static prev := 0, dock := "NxDock ahk_class ThunderRT5Form"
    hwnd := WinExist("A")
    if !WinActive(dock) {
        if hwnd
            prev := hwnd
        return
    }
    WinGetPos &x, &y, &w, &h, dock
    MouseGetPos &mx, &my, &under
    if (mx >= x && mx < x + w && my >= y && my < y + h)
        return
    target := under
    try {
        cls := WinGetClass(target)
        if (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd" || cls = "ThunderRT5Form"
            || cls = "RainmeterMeterWindow" || WinGetProcessName(target) = "yasb.exe")
            target := prev
    } catch
        target := prev
    if (target && WinExist(target))
        WinActivate target
}
SetTimer DockFocusBack, 15

; Nexus normally lifts the dock over other windows when the pointer bumps the very edge,
; which the clamp above prevents - the dock would then reveal behind the active window.
; Keep it topmost instead (no activation, so it never takes focus). It is transparent
; while hidden, so being topmost all the time costs nothing visible.
DockOnTop() {
    DetectHiddenWindows true
    if (hwnd := WinExist("NxDock ahk_class ThunderRT5Form")) && !(WinGetExStyle(hwnd) & 0x8)
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
}
SetTimer DockOnTop, 250

; Kept in globals so the callback and hook handle are not freed.
BottomEdgeCb := CallbackCreate(BottomEdgeHook, "Fast", 3)
BottomEdgeHookHandle := DllCall("SetWindowsHookEx", "Int", 14, "Ptr", BottomEdgeCb
                                , "Ptr", DllCall("GetModuleHandle", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
