#Requires -Version 5.1
<#
    apply-taskbar-styler.ps1 - configure Windhawk's "Windows 11 Taskbar Styler" so the native
    taskbar shows only the system tray, as a GruvGold pill. The taskbar buttons are Nexus' job.

    Windhawk keeps mod settings under HKLM, so run this from an elevated PowerShell. It does
    not elevate itself: a script that relaunches itself with no guard can fork-loop.
    Install the mod from Windhawk's window first; this script only sets its settings.
#>
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an elevated (Administrator) PowerShell.'
}
$pill = 'Background:=<SolidColorBrush Color="#D10D0C09"/>'          # bg_alt at 82%, like the YASB pills
$stroke = 'BorderBrush:=<SolidColorBrush Color="#FF282421"/>'      # palette border

$styles = @(
    @('Taskbar.TaskbarFrame > Grid#RootGrid > Taskbar.TaskbarBackground > Grid > Rectangle#BackgroundFill', 'Fill=Transparent'),
    @('Rectangle#BackgroundStroke', 'Visibility=Collapsed'),
    # every taskbar button (Start, search, task view, apps) - Nexus replaces them
    @('Microsoft.UI.Xaml.Controls.ItemsRepeater#TaskbarFrameRepeater', 'Visibility=Collapsed'),
    @('StackPanel#SystemTrayFrameGrid, Grid#SystemTrayFrameGrid', $pill, $stroke, 'BorderThickness=1',
      'CornerRadius=15', 'Padding=10,0,10,0', 'Margin=0,6,10,10'),
    # date/time hidden from the pill; the bell next to it still opens the notification centre and calendar
    @('SystemTray.OmniButton#NotificationCenterButton > Grid > ContentPresenter > ItemsPresenter > StackPanel > ContentPresenter[1] > SystemTray.IconView#SystemTrayIcon', 'Visibility=Collapsed'),
    # keyboard language / input indicator
    @('SystemTray.LanguageTextIconContent', 'Visibility=Collapsed')
)

# Names contain '[' - a wildcard to the *-ItemProperty cmdlets - so use the registry API.
$mod = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Windhawk\Engine\Mods\windows-11-taskbar-styler', $true)
if (-not $mod) { throw 'Install "Windows 11 Taskbar Styler" in Windhawk first.' }
$key = $mod.OpenSubKey('Settings', $true)

foreach ($n in $key.GetValueNames() | Where-Object { $_.StartsWith('controlStyles[') }) { $key.DeleteValue($n) }
for ($i = 0; $i -lt $styles.Count; $i++) {
    $key.SetValue("controlStyles[$i].target", $styles[$i][0], 'String')
    for ($j = 1; $j -lt $styles[$i].Count; $j++) {
        $key.SetValue("controlStyles[$i].styles[$($j - 1)]", $styles[$i][$j], 'String')
    }
}
$key.SetValue('clickThroughTaskbar', 1, 'DWord')               # empty bar area must not eat clicks
$key.SetValue('xamlDiagnosticsHandling', 'block', 'String')    # no other XAML consumer (TranslucentTB crashed on it)
# The mod reloads when this changes (it lives on the mod key, not Settings); the UI writes the unix time.
$mod.SetValue('SettingsChangeTime', [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds(), 'DWord')
