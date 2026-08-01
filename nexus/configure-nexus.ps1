#Requires -Version 5.1
<#
    configure-nexus.ps1 - write the GruvGold dock settings into Nexus' registry key.

    Nexus rewrites its settings on exit, so it is stopped first (force: nothing it would
    flush is something this script does not set) and started again afterwards.

    Pins resolve each app's exe at run time, so re-run this after a Store app updates
    (its install folder carries the version number).
#>
$ErrorActionPreference = 'Stop'
$exe = "${env:ProgramFiles(x86)}\Winstep\Nexus.exe"
$root = 'HKCU:\Software\WinSTEP2000\NeXuS'
$docks = "$root\Docks"
$assets = "$env:LOCALAPPDATA\GruvGoldRice\nexus"
$gold = '#D5AC45'

if (-not (Test-Path $docks)) { throw 'Start Nexus once so it creates its settings, then re-run.' }

Stop-Process -Name Nexus -Force -ErrorAction SilentlyContinue
Start-Sleep 2

try {
function Set-Reg($path, $name, $value) { Set-ItemProperty $path -Name $name -Value ([string]$value) }

# Nexus registers its own login entry; start.ps1 -Autostart launches it in order instead.
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name Nexus -ErrorAction SilentlyContinue

# ---- logo + settings --------------------------------------------------------
New-Item -ItemType Directory -Force "$assets\pins" | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'logo.png') "$assets\logo.png" -Force

# Global: no sounds, no animation speed-up/fx, show the dock the instant the edge is hit and
# hide it the instant the pointer leaves (AutoHideDelay 0).
# SubNoBoing is what actually removes the overshoot of the slide animation (DockAutoHideNoBoing1
# alone does not). EdgeBufferZone 6 + UseEntireEdge make the whole bottom edge a 6px-tall trigger,
# wider than Explorer's own 2px one, so desktop-type-to-launch.ahk can keep the native taskbar (tray pill)
# out of everything but the bottom-right corner.
foreach ($kv in @{ DisableAllSounds = 'True'; DisableAllVoices = 'True'; AnimationSpeed = 25
                   FxSpan00 = 0; FxTime00 = 0; AutoPopUpDelay = 0; HideTaskbar = 'False'; GenAutoRun = 'False'
                   AutoHideDelay = 0; SubNoBoing = 'True'; DisableAnimations = 'False'
                   EdgeBufferZone = 6; UseEntireEdge = 'True' }.GetEnumerator()) {
    Set-Reg $root $kv.Key $kv.Value
}

# Dock 1: bottom edge (orientation 3), auto-hide without the "boing", running apps shown,
# and none of Nexus' macOS effects (zoom, bounce, delete/attention animations).
foreach ($kv in @{ DockOrientation1 = 3; DockAutoHide1 = 'True'; DockAutoHideNoBoing1 = 'True'
                   DockAutoHideMode1 = 1; DockSubNoBoing1 = 'True'; DockGetFocusOnActivation1 = 'False'
                   DockShowTasklist1 = 'False'; DockManualTheme1 = 'True'; DockIconSize1 = 35
                   DockFxEffect1 = 0; DockIconBounce1 = 0; DockIconSpacing1 = 10
                   DockAttentionFx1 = 0; DockDeleteFx1 = 0; DockEdgeOffset1 = 10
                   DockUserControlIcon1 = "$assets\logo.png" }.GetEnumerator()) {
    Set-Reg $docks $kv.Key $kv.Value
}

# ---- pin icons ----------------------------------------------------------------
# Gruvbox-dark recolour of each app icon, alpha untouched. Done in C# because
# a per-pixel PowerShell loop over 256x256 icons is slow.
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.IO; using System.Runtime.InteropServices;
public static class PinIcon {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern uint PrivateExtractIcons(string file, int index, int cx, int cy, IntPtr[] icons, int[] ids, uint n, uint flags);

    public static Bitmap FromExe(string path) {
        var h = new IntPtr[1]; var id = new int[1];
        if (PrivateExtractIcons(path, 0, 256, 256, h, id, 1, 0) < 1) throw new Exception("no icon in " + path);
        using (var ico = Icon.FromHandle(h[0])) return new Bitmap(ico.ToBitmap());
    }

    public static byte[] ToPinIco(Bitmap src) {
        // Sizing is relative to logo.png, whose four panes span 184px of its 256px canvas. The
        // Source logos carry their own transparent padding, so crop to the visible pixels first,
        // then fit that into 200px (the logo's panes are 184px - a touch bigger reads better).
        int x0 = src.Width, y0 = src.Height, x1 = -1, y1 = -1;
        for (int y = 0; y < src.Height; y++) for (int x = 0; x < src.Width; x++)
            if (src.GetPixel(x, y).A > 16) { x0 = Math.Min(x0, x); y0 = Math.Min(y0, y); x1 = Math.Max(x1, x); y1 = Math.Max(y1, y); }
        if (x1 < 0) { x0 = 0; y0 = 0; x1 = src.Width - 1; y1 = src.Height - 1; }
        int cw = x1 - x0 + 1, ch = y1 - y0 + 1; double k = 200.0 / Math.Max(cw, ch);
        int dw = (int)(cw * k), dh = (int)(ch * k);
        var glyph = new Bitmap(256, 256, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(glyph)) {
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g.DrawImage(src, new Rectangle((256 - dw) / 2, (256 - dh) / 2, dw, dh), x0, y0, cw, ch, GraphicsUnit.Pixel);
        }
        var d = glyph.LockBits(new Rectangle(0, 0, 256, 256), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        var px = new byte[d.Stride * 256]; Marshal.Copy(d.Scan0, px, 0, px.Length);
        // Gruvbox-dark grade, keeping each app recognisable: coloured pixels snap to the nearest
        // gruvbox bright hue family, greys/whites ride a bg0 -> fg1 ramp (cream whites, warm greys).
        double[] ramp0 = { 0x28, 0x28, 0x28 }, ramp1 = { 0xeb, 0xdb, 0xb2 };
        // hue upper bound (deg) -> gruvbox bright colour: red, orange, yellow, green (the 90-160 band: WhatsApp/Spotify greens, kept saturated), blue, purple, back to red
        double[] hueMax = { 15, 35, 50, 90, 160, 260, 330, 361 };
        double[][] pal = {
            new double[] { 0xfb, 0x49, 0x34 }, new double[] { 0xfe, 0x80, 0x19 }, new double[] { 0xfa, 0xbd, 0x2f }, new double[] { 0xb8, 0xbb, 0x26 },
            new double[] { 0x8f, 0xc8, 0x5e }, new double[] { 0x83, 0xa5, 0x98 }, new double[] { 0xd3, 0x86, 0x9b }, new double[] { 0xfb, 0x49, 0x34 } };
        for (int i = 0; i < px.Length; i += 4) {
            double B = px[i], G = px[i + 1], R = px[i + 2];   // BGRA
            double mx = Math.Max(R, Math.Max(G, B)), mn = Math.Min(R, Math.Min(G, B)), dl = mx - mn;
            double v = mx / 255.0, sat = mx == 0 ? 0 : dl / mx, l = (0.299 * R + 0.587 * G + 0.114 * B) / 255.0, h = 0;
            if (dl > 0) { h = mx == R ? 60 * (((G - B) / dl) % 6) : mx == G ? 60 * ((B - R) / dl + 2) : 60 * ((R - G) / dl + 4); if (h < 0) h += 360; }
            int k2 = 0; while (h >= hueMax[k2]) k2++;
            double c = Math.Max(0, Math.Min(1, (sat - 0.12) / 0.45)), br = 0.45 + 0.55 * v;
            for (int ch2 = 0; ch2 < 3; ch2++) {
                double grey = ramp0[ch2] + (ramp1[ch2] - ramp0[ch2]) * l, col = pal[k2][ch2] * br;
                px[i + 2 - ch2] = (byte)(grey + (col - grey) * c);
            }
        }
        Marshal.Copy(px, 0, d.Scan0, px.Length); glyph.UnlockBits(d);
        // Tile: gruvbox bg0 rounded square with a bg1 hairline border.
        var b = new Bitmap(256, 256, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(b)) {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            var p = new System.Drawing.Drawing2D.GraphicsPath(); int r = 48, o = 22, w = 233;   // r = corner diameter
            p.AddArc(o, o, r, r, 180, 90); p.AddArc(w - r, o, r, r, 270, 90); p.AddArc(w - r, w - r, r, r, 0, 90); p.AddArc(o, w - r, r, r, 90, 90); p.CloseFigure();
            using (var fill = new SolidBrush(Color.FromArgb(0x1d, 0x20, 0x21))) g.FillPath(fill, p);   // bg0_h
            using (var pen = new Pen(Color.FromArgb(0x3c, 0x38, 0x36), 2)) g.DrawPath(pen, p);          // bg1

            g.DrawImage(glyph, 0, 0);
        }
        var ms = new MemoryStream(); b.Save(ms, ImageFormat.Png); var png = ms.ToArray();
        // An ICO can hold a PNG as-is: 6-byte header + one 16-byte entry (0 = 256px).
        var ico = new MemoryStream(); var bw = new BinaryWriter(ico);
        bw.Write((short)0); bw.Write((short)1); bw.Write((short)1);
        bw.Write((byte)0); bw.Write((byte)0); bw.Write((byte)0); bw.Write((byte)0);
        bw.Write((short)1); bw.Write((short)32); bw.Write(png.Length); bw.Write(22); bw.Write(png);
        return ico.ToArray();
    }
}
'@

# Resolve a pin to (exe, source bitmap). Store apps: exe from the package manifest, icon
# from the package's 256px logo (their exes often carry no usable icon).
function Resolve-Pin($spec, $exeName) {
    if ($spec -notmatch '!') { return @{ Exe = $spec; Bmp = [PinIcon]::FromExe($spec) } }
    $pkg = Get-AppxPackage | Where-Object { $_.PackageFamilyName -eq $spec.Split('!')[0] } | Select-Object -First 1
    $app = ([xml](Get-Content "$($pkg.InstallLocation)\AppxManifest.xml")).Package.Applications.Application |
        Where-Object Id -eq $spec.Split('!')[1]
    $stem = Join-Path $pkg.InstallLocation ([IO.Path]::ChangeExtension($app.VisualElements.Square44x44Logo, $null).TrimEnd('.'))
    $png = "$stem.targetsize-256.png", "$stem.targetsize-256_altform-unplated.png", "$stem.scale-400.png" |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exeName) { $exeName = $app.Executable }
    $exe = if ([IO.Path]::IsPathRooted($exeName)) { $exeName } else { Join-Path $pkg.InstallLocation $exeName }
    @{ Exe = $exe; Bmp = New-Object System.Drawing.Bitmap $png }
}

# Pinned apps: name, exe path or AUMID, optional exe override when the manifest's exe is only
# a launcher stub (Spotify). The pin points at the package exe so Nexus can match the running
# window to it and launch the app. Spotify is the exception: its manifest exe (a migrator)
# is not the exe that runs, and Windows refuses to start Spotify.exe from inside WindowsApps,
# so it pins the app-execution alias instead. That launches, but a running Spotify then
# shows no indicator dot on its icon.
$pinSpecs = @(
    @('Terminal',      'Microsoft.WindowsTerminal_8wekyb3d8bbwe!App'),
    @('Claude',        'Claude_pzs8sxrjxfjjc!Claude'),
    @('Obsidian',      "$env:LOCALAPPDATA\Programs\Obsidian\Obsidian.exe"),
    @('PredatorSense', 'ULICTekInc.PredatorSenseforNotebook_nt9dgb7efx6bt!PredatorSense'),
    @('File Explorer', "$env:windir\explorer.exe"),
    @('Spotify',       'SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify', "$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe"),
    @('WhatsApp',      '5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App')
)
$items = foreach ($p in $pinSpecs) {
    $r = Resolve-Pin $p[1] $p[2]
    $icoPath = "$assets\pins\$($p[0]).ico"
    [IO.File]::WriteAllBytes($icoPath, [PinIcon]::ToPinIco($r.Bmp))
    , @($p[0], $r.Exe, $icoPath)
}

$old = (Get-ItemProperty $docks).PSObject.Properties.Name | Where-Object { $_ -match '^1(Label|Path|Type|Icon\w*)\d+$' }
foreach ($n in $old) { Remove-ItemProperty $docks -Name $n }
for ($i = 0; $i -lt $items.Count; $i++) {
    Set-Reg $docks "1Label$i" $items[$i][0]
    Set-Reg $docks "1Path$i"  $items[$i][1]
    Set-Reg $docks "1Type$i"  1
    Set-Reg $docks "1IconPath$i" $items[$i][2]
}
Set-Reg $docks 'DockNoItems1' ($items.Count - 1)
}
finally { Start-Process $exe }   # a failure above must not leave the dock dead
