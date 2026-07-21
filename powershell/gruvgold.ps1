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
    "`n[$e[32minvictus@$([System.Net.Dns]::GetHostName())$e[39m] $path`n$arrow "
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
