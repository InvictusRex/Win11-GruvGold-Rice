#Requires AutoHotkey v2.0
#SingleInstance Ignore
;
; snap-half.ahk <top|bottom|left|right>
;
; Win+Up    -> top half of the work area,    press again -> maximised
; Win+Down  -> bottom half of the work area, press again -> minimised
; Win+Left  -> left half of the work area,   press again -> back to tiled
; Win+Right -> right half of the work area,  press again -> back to tiled
;
; Invoked per keypress from whkdrc rather than living in the resident script,
; because the resident script's Win-key handler (which turns a solo Win tap into
; the launcher) sends a neutralising keystroke on Win-down, and that breaks
; AutoHotkey's own `#Up` / `#Down` modifier matching. whkd uses an independent
; hook and is unaffected, so the binding lives there and calls this.
;
; State has to outlive the process, so the last gesture is kept in a temp file
; as "<hwnd>|<top|bottom>". A different window resets it.
;
; A tiled window is floated first, otherwise komorebi snaps it straight back to
; its tile and the window visibly jitters. The second press floats it back.

which := "top"
if (A_Args.Length >= 1 && (A_Args[1] = "bottom" || A_Args[1] = "left" || A_Args[1] = "right"))
    which := A_Args[1]

KOMOREBIC_EXE := "C:\Program Files\komorebi\bin\komorebic-no-console.exe"
stateFile     := A_Temp . "\gruvgold-snap.txt"
lastFile      := A_Temp . "\gruvgold-snap-last.txt"

; whkd fires again while the key auto-repeats, and a single held press was
; observed invoking this three times - which walks straight through
; half -> maximise -> half. Ignore anything that arrives too soon after the
; previous run so one press is one state change.
;
; A_TickCount resets on every reboot, so a stale file left over from a prior
; boot can hold a value HIGHER than the current tick count. That makes the
; diff negative - which is also "< 400" - and the guard then blocks every
; press forever, not just rapid repeats. Only treat it as a repeat when the
; diff is actually a small non-negative number.
if FileExist(lastFile) {
    try {
        diff := A_TickCount - Integer(Trim(FileRead(lastFile)))
        if (diff >= 0 && diff < 400)
            ExitApp
    }
}
try FileDelete lastFile
try FileAppend String(A_TickCount), lastFile

Komorebic(args) {
    global KOMOREBIC_EXE
    if FileExist(KOMOREBIC_EXE)
        RunWait Format('"{1}" {2}', KOMOREBIC_EXE, args), , "Hide"
}

hwnd := WinExist("A")
if (!hwnd)
    ExitApp
cls := WinGetClass("A")
if (cls = "Progman" || cls = "WorkerW")      ; ignore the desktop itself
    ExitApp

; ---------------------------------------------------------------- prior state
prev := ""
if FileExist(stateFile) {
    parts := StrSplit(Trim(FileRead(stateFile)), "|")
    if (parts.Length = 2 && parts[1] = String(hwnd))
        prev := parts[2]
}

ClearState() {
    global stateFile
    try FileDelete stateFile
}

; ---------------------------------------------------------------- second press
if (prev = which) {
    ClearState()
    if (which = "top") {
        ; A plain resize to the full work area, not native SW_MAXIMIZE - native
        ; maximize adds Windows' own invisible resize-border padding, which
        ; shows up as a thin dark sliver at the top on windows with custom
        ; chrome. Staying floated and just filling the work area avoids it.
        MonitorGetWorkArea(MonitorGetPrimary(), &ml, &mt, &mr, &mb)
        try WinMove ml, mt, mr - ml, mb - mt, hwnd
    } else if (which = "bottom") {
        Komorebic("toggle-float")             ; hand it back to komorebi
        Sleep 80
        try WinMinimize hwnd
    } else {
        Komorebic("toggle-float")             ; left/right: back to komorebi's tiling
    }
    ExitApp
}

; ---------------------------------------------------------------- first press
; Floating is what stops komorebi re-tiling the window - but komorebi also
; *centres* a window at the moment it becomes floating, and that centring lands
; after the call returns. Moving too soon just gets overwritten, so wait for it
; to settle and then move (twice, to be sure we had the last word).
if (prev = "")
    Komorebic("toggle-float")
Sleep 400

; MonitorGetWorkArea already excludes the YASB app bar and the taskbar.
MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
if (which = "left" || which = "right") {
    w := (r - l) // 2
    h := b - t
    x := (which = "left") ? l : l + w
    y := t
} else {
    w := r - l
    h := (b - t) // 2
    x := l
    y := (which = "top") ? t : t + h
}

try WinRestore hwnd                          ; a maximised window will not move
try WinMove x, y, w, h, hwnd
Sleep 150
try WinMove x, y, w, h, hwnd

ClearState()
FileAppend String(hwnd) "|" which, stateFile
ExitApp
