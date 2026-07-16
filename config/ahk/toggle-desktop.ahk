#Requires AutoHotkey v2.0
#SingleInstance Ignore
; AHK v2 sleeps 100ms after every window call by default; with a dozen windows that
; is over a second, long enough for the run to be cut short after the first
; (focused) window.
SetWinDelay -1
DetectHiddenWindows True   ; see first-press loop; also needed to restore cloaked windows
;
; toggle-desktop.ahk
;
; Windows 11 24H2 broke Win+D for anything using SHAppBarMessage / always-on-top
; app bars (upstream, not fixable from config - see amnweb/yasb#62, #549, #748):
; the native "show desktop" now minimises the YASB bar along with everything
; else, and on a second press it does not reliably come back, especially with
; komorebi's workspace switching in the mix. There is no window flag that
; makes an app opt out of it - it is baked into explorer's ToggleDesktop.
;
; Fix: never let Windows do it. whkd hooks Win+D independently of the shell (same
; trick already used for Win+Up/Down/Left/Right in snap-half.ahk) and this script
; reimplements "show desktop" itself - minimise every ordinary top-level window,
; remember which ones. Same rule as the native key: if any ordinary window is
; open, minimise them all (adding to the remembered set); only when nothing is
; open does it restore the remembered ones. It never touches the
; bar/widgets because they are excluded by process name, so there is nothing for
; the bug to hide.
;
; State (the hwnds we minimised) is kept in a temp file so it survives between
; the one-shot invocations whkd makes per keypress.

stateFile := A_Temp . "\gruvgold-desktop.txt"
lastFile  := A_Temp . "\gruvgold-desktop-last.txt"

EXCLUDE := ["yasb.exe", "Rainmeter.exe", "TranslucentTB.exe", "komorebi.exe", "AutoHotkey64.exe", "TextInputHost.exe"]
EXCLUDE_CLASS := ["Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd"]

; Same guard as snap-half.ahk: A_TickCount resets on reboot, so only treat a
; small NON-NEGATIVE diff as "too soon after the last press".
if FileExist(lastFile) {
    try {
        diff := A_TickCount - Integer(Trim(FileRead(lastFile)))
        if (diff >= 0 && diff < 400)
            ExitApp
    }
}
try FileDelete lastFile
try FileAppend String(A_TickCount), lastFile

; ---------------------------------------------------------------- collect open windows
; komorebi hides windows with DWM "shell" cloaking, and AHK's default window list
; skips cloaked windows - so most of a tiled desktop was invisible to this loop and
; only the focused window got minimised. Enumerate hidden windows too and filter
; to real, visible, top-level app windows ourselves.
open := []
for hwnd in WinGetList() {
    try {
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            continue
        if (WinGetExStyle(hwnd) & 0x80)        ; WS_EX_TOOLWINDOW
            continue
        if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")   ; GW_OWNER: dialogs/popups
            continue
        DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "uint*", &cloak := 0, "uint", 4)
        if (cloak & 5)                         ; cloaked by the app itself (suspended UWP frames)
            continue
        if (WinGetMinMax(hwnd) = -1)           ; already minimised - leave it alone
            continue
        proc := WinGetProcessName(hwnd)
        skip := false
        for name in EXCLUDE {
            if (proc = name) {
                skip := true
                break
            }
        }
        if skip
            continue
        cls := WinGetClass(hwnd)
        for name in EXCLUDE_CLASS {
            if (cls = name) {
                skip := true
                break
            }
        }
        if skip
            continue
        if (WinGetTitle(hwnd) = "")            ; helper/tool windows, not real app windows
            continue
        open.Push(hwnd)
    }
}

; ---------------------------------------------------------------- windows open: show desktop
if (open.Length) {
    for hwnd in open {
        try {
            WinMinimize hwnd
            FileAppend hwnd . "`n", stateFile
        }
    }
    ; Like the native key, hand focus to the desktop. Otherwise komorebi focuses
    ; the next window in line and that un-minimises it again.
    try WinActivate "ahk_class Progman"
    ExitApp
}

; ---------------------------------------------------------------- desktop already clear: restore
if FileExist(stateFile) {
    for hwnd in StrSplit(Trim(FileRead(stateFile)), "`n") {
        if hwnd
            try WinRestore Integer(hwnd)
    }
    try FileDelete stateFile
}
ExitApp
