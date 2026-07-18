@echo off
REM ---------------------------------------------------------------------------
REM  Launch YASB with Qt's high-DPI scaling disabled.
REM
REM  WHY: at 150% display scaling YASB lays its bar out in PHYSICAL pixels while
REM  Qt paints with a 1.5 device-pixel ratio, so a bar's contents are drawn 1.5x
REM  wider than the window that owns them. Measured on this machine:
REM
REM      width 100%  -> window 0..2560 physical, contents painted across 3840
REM                     => `center` lands at 1280 logical, `right` is off-screen
REM      width  67%  -> contents painted across the full screen and look right,
REM                     but the WINDOW only reaches x=1715, so everything past
REM                     67% renders yet cannot be clicked (verified with
REM                     WindowFromPoint: the power icon returned explorer.exe)
REM
REM  Forcing the ratio to 1 makes layout and painting agree: the window spans the
REM  full 2560, all three regions land correctly, and every widget is clickable.
REM  The trade-off is that Qt no longer scales anything, so all sizes in
REM  config.yaml and styles.css are written in physical pixels.
REM ---------------------------------------------------------------------------

set QT_ENABLE_HIGHDPI_SCALING=0
set QT_AUTO_SCREEN_SCALE_FACTOR=0
set QT_SCALE_FACTOR=1

start "" "%ProgramFiles%\YASB\yasb.exe"
