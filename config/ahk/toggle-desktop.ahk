#Requires AutoHotkey v2.0
#SingleInstance Ignore
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
; remember which ones, restore them on the second press. It never touches the
; bar/widgets because they are excluded by process name, so there is nothing for
; the bug to hide.
;
; State (the hwnds we minimised) is kept in a temp file so it survives between
; the one-shot invocations whkd makes per keypress.

stateFile := A_Temp . "\gruvgold-desktop.txt"
lastFile  := A_Temp . "\gruvgold-desktop-last.txt"

EXCLUDE := ["yasb.exe", "Rainmeter.exe", "TranslucentTB.exe", "komorebi.exe", "AutoHotkey64.exe"]
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

; ---------------------------------------------------------------- second press
if FileExist(stateFile) {
    for hwnd in StrSplit(Trim(FileRead(stateFile)), "`n") {
        if hwnd
            try WinRestore Integer(hwnd)
    }
    try FileDelete stateFile
    ExitApp
}

; ---------------------------------------------------------------- first press
minimised := ""
for hwnd in WinGetList() {
    try {
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
        WinMinimize hwnd
        minimised .= hwnd . "`n"
    }
}
if (minimised != "")
    FileAppend minimised, stateFile
ExitApp
