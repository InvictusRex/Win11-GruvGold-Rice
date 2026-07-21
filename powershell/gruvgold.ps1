# GruvGold shell: prompt, input colours and the fastfetch greeting.
# Dot-sourced from the PowerShell 5 and 7 profiles (see apply.ps1). Plain
# PowerShell rather than oh-my-posh: that cost ~400 ms at startup plus a
# process spawn on every prompt.

#    <blank line after the previous command's output>
#    [invictus@TheKingslayer] C:\Users\TheKi
#    >
# No leading spaces: the Terminal profile's left padding indents the prompt
# and native command output alike.
function prompt {
    $ok  = $?
    $e   = [char]27
    $loc = $executionContext.SessionState.Path.CurrentLocation
    $path = if ($loc.Provider.Name -eq 'FileSystem') { $loc.ProviderPath } else { $loc.Path }
    $Host.UI.RawUI.WindowTitle = '[invictus] ' + ($path -replace ('^' + [regex]::Escape($HOME) + '(?=\\|$)'), '~')
    $arrow = if ($ok) { '>' } else { "$e[31m>$e[39m" }

    # Exactly one blank line above the prompt. Errors and tables already end
    # in blank lines, so reuse those rather than adding another.
    $gap = "`n"
    try {
        $raw = $Host.UI.RawUI
        $y = $raw.CursorPosition.Y
        $w = $raw.BufferSize.Width - 1
        $bg = $raw.BackgroundColor
        $top = $y
        # Blank = only spaces on the default background (fastfetch's colour
        # palette is spaces on coloured backgrounds).
        while ($top -gt 0 -and -not ($raw.GetBufferContents([Management.Automation.Host.Rectangle]::new(0, $top - 1, $w, $top - 1)) |
                Where-Object { $_.Character -ne ' ' -or $_.BackgroundColor -ne $bg } | Select-Object -First 1)) { $top-- }
        if ($top -lt $y) {
            # Blank lines already there: sit right after the first one, or at
            # the very top when everything above is blank (after cls).
            $row = if ($top -eq 0) { 0 } else { $top + 1 }
            $raw.CursorPosition = [Management.Automation.Host.Coordinates]::new(0, $row)
            $gap = ''
        } elseif ($y -eq 0) { $gap = '' }
    } catch {}

    "$gap[$e[32minvictus@$([System.Net.Dns]::GetHostName())$e[39m] $path`n$arrow "
}

if ($env:WT_SESSION) {
    # Typed text in the terminal's own off-white instead of per-token colours.
    $fg = "$([char]27)[39m"
    Set-PSReadLineOption -Colors @{
        Default = $fg; Command = $fg; Parameter = $fg; Operator = $fg; Variable = $fg
        String  = $fg; Number  = $fg; Type      = $fg; Member   = $fg; Keyword  = $fg
    }
    Remove-Variable fg

    # Once per tab; the env var is inherited, so nested shells skip it.
    if (-not $env:GRUVGOLD_GREETED -and (Get-Command fastfetch -CommandType Application -ErrorAction SilentlyContinue)) {
        $env:GRUVGOLD_GREETED = 1
        fastfetch
    }
}
