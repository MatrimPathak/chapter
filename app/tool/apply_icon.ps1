# Writes every app icon size from tool/icon_source.png, the icon from the Stitch project.
# Run from app/ in Windows PowerShell:  powershell -File tool/apply_icon.ps1
# To change the icon, replace icon_source.png and run this again. File names stay the same.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Separates the Stitch artwork into the book (foreground) and its green ground (background).
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class ChapterIconLayers {
    public Bitmap Foreground, Monochrome, Background;
    public double CenterX, CenterY, Radius;

    static double Smooth(double a, double b, double x) {
        double t = Math.Max(0, Math.Min(1, (x - a) / (b - a)));
        return t * t * (3 - 2 * t);
    }

    static byte Clamp(double v) { return (byte)Math.Max(0, Math.Min(255, Math.Round(v))); }

    public static ChapterIconLayers Split(Bitmap master) {
        int n = master.Width;
        var rect = new Rectangle(0, 0, n, n);
        var src = master.Clone(rect, PixelFormat.Format32bppArgb);
        var data = src.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var p = new byte[n * n * 4];
        Marshal.Copy(data.Scan0, p, 0, p.Length);
        src.UnlockBits(data);
        src.Dispose();

        var fg = new byte[p.Length]; var mono = new byte[p.Length]; var alpha = new double[n * n];
        var grounds = new double[3];
        int minX = n, minY = n, maxX = 0, maxY = 0;
        for (int i = 0; i < n * n; i++) {
            // Red separates ivory and terracotta from the green ground and its shadows.
            alpha[i] = Smooth(66, 118, p[i * 4 + 2]);
            // The rim of the artwork catches light; only the middle holds the book.
            int ex = i % n, ey = i / n;
            if (ex < n * 0.10 || ex > n * 0.90 || ey < n * 0.10 || ey > n * 0.90) alpha[i] = 0;
            if (alpha[i] > 0.5) {
                int x = i % n, y = i / n;
                minX = Math.Min(minX, x); maxX = Math.Max(maxX, x);
                minY = Math.Min(minY, y); maxY = Math.Max(maxY, y);
            }
        }
        var layers = new ChapterIconLayers();
        layers.CenterX = (minX + maxX) / 2.0;
        layers.CenterY = (minY + maxY) / 2.0;

        // The ground is a smooth diagonal: read its two ends from clear corners.
        Color a = ReadAverage(p, n, (int)(n * 0.10), (int)(n * 0.10));
        Color b = ReadAverage(p, n, (int)(n * 0.90), (int)(n * 0.90));
        var bg = new byte[p.Length];
        double radius = 0;
        for (int i = 0; i < n * n; i++) {
            int x = i % n, y = i / n, o = i * 4;
            double t = (x + y) / (2.0 * (n - 1));
            double gb = a.B + (b.B - a.B) * t, gg = a.G + (b.G - a.G) * t, gr = a.R + (b.R - a.R) * t;
            bg[o] = Clamp(gb); bg[o + 1] = Clamp(gg); bg[o + 2] = Clamp(gr); bg[o + 3] = 255;

            double al = alpha[i];
            if (al <= 0) continue;
            // Take the green back out of soft edges so no fringe shows on other grounds.
            fg[o] = Clamp((p[o] - (1 - al) * gb) / al);
            fg[o + 1] = Clamp((p[o + 1] - (1 - al) * gg) / al);
            fg[o + 2] = Clamp((p[o + 2] - (1 - al) * gr) / al);
            fg[o + 3] = Clamp(al * 255);
            if (al > 0.5) {
                double dx = x - layers.CenterX, dy = y - layers.CenterY;
                radius = Math.Max(radius, Math.Sqrt(dx * dx + dy * dy));
            }
            // Themed icons are one colour, so the ribbon becomes a gap in the book.
            double ribbon = Math.Abs(x - layers.CenterX) < n * 0.075
                ? Smooth(45, 85, (double)p[o + 2] - p[o]) : 0;
            mono[o] = 255; mono[o + 1] = 255; mono[o + 2] = 255;
            mono[o + 3] = Clamp(al * (1 - ribbon) * 255);
        }
        layers.Radius = radius;
        layers.Foreground = Make(fg, n);
        layers.Monochrome = Make(mono, n);
        layers.Background = Make(bg, n);
        return layers;
    }

    static Color ReadAverage(byte[] p, int n, int cx, int cy) {
        int r = 0, g = 0, b = 0, c = 0;
        for (int y = cy - 8; y <= cy + 8; y++)
            for (int x = cx - 8; x <= cx + 8; x++) {
                int o = (y * n + x) * 4; b += p[o]; g += p[o + 1]; r += p[o + 2]; c++;
            }
        return Color.FromArgb(r / c, g / c, b / c);
    }

    static Bitmap Make(byte[] bytes, int n) {
        var bmp = new Bitmap(n, n, PixelFormat.Format32bppArgb);
        var d = bmp.LockBits(new Rectangle(0, 0, n, n), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(bytes, 0, d.Scan0, bytes.Length);
        bmp.UnlockBits(d);
        return bmp;
    }
}
'@

$app = Split-Path $PSScriptRoot -Parent
$src = [System.Drawing.Bitmap]::FromFile("$PSScriptRoot\icon_source.png")

# The source is a rounded icon on a pale page. Find its edges along the middle lines.
function IsIcon($c) { return $c.GetBrightness() -lt 0.35 }
$midX = [int]($src.Width / 2); $midY = [int]($src.Height / 2)
$left = 0; while (-not (IsIcon $src.GetPixel($left, $midY))) { $left++ }
$right = $src.Width - 1; while (-not (IsIcon $src.GetPixel($right, $midY))) { $right-- }
$top = 0; while (-not (IsIcon $src.GetPixel($midX, $top))) { $top++ }
$bottom = $src.Height - 1; while (-not (IsIcon $src.GetPixel($midX, $bottom))) { $bottom-- }
$side = [Math]::Min($right - $left, $bottom - $top)
$bg = $src.GetPixel($left + [int]($side * 0.06), $top + [int]($side * 0.5))

# Square master with the page corners painted over, so nothing pale shows at any mask.
$master = New-Object System.Drawing.Bitmap 1024, 1024
$g = [System.Drawing.Graphics]::FromImage($master)
$g.InterpolationMode = 'HighQualityBicubic'
$g.Clear($bg)
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$r = 460
$path.AddArc(0, 0, $r, $r, 180, 90); $path.AddArc(1024 - $r, 0, $r, $r, 270, 90)
$path.AddArc(1024 - $r, 1024 - $r, $r, $r, 0, 90); $path.AddArc(0, 1024 - $r, $r, $r, 90, 90)
$path.CloseFigure()
$g.SetClip($path)
$g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, 1024, 1024),
    (New-Object System.Drawing.Rectangle $left, $top, $side, $side), 'Pixel')
$g.Dispose()

function Save-Scaled($size, $file, $scale = 1.0) {
    # No alpha channel: App Store Connect rejects icons that have one.
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    $gr.InterpolationMode = 'HighQualityBicubic'; $gr.PixelOffsetMode = 'HighQuality'
    $gr.Clear($bg)
    $inner = [int]($size * $scale); $at = [int](($size - $inner) / 2)
    $gr.DrawImage($master, $at, $at, $inner, $inner)
    $gr.Dispose()
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$res = "$app\android\app\src\main\res"
foreach ($d in @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }.GetEnumerator()) {
    Save-Scaled $d.Value "$res\mipmap-$($d.Key)\ic_launcher.png"
}
# Adaptive icon layers, per the Material guidelines: a 108dp canvas, with the artwork
# kept inside the 66dp safe circle because launchers mask and move the layers.
$layers = [ChapterIconLayers]::Split($master)
$safe = 33.0 / 108.0
$scale = $safe * 1024.0 / $layers.Radius

function Save-Layer($size, $file, $layer, $fit) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    $gr.InterpolationMode = 'HighQualityBicubic'; $gr.PixelOffsetMode = 'HighQuality'
    $gr.Clear([System.Drawing.Color]::Transparent)
    if ($fit) {
        $inner = $size * $scale
        $gr.DrawImage($layer, [single](($size / 2.0) - ($layers.CenterX / 1024.0 * $inner)),
            [single](($size / 2.0) - ($layers.CenterY / 1024.0 * $inner)), [single]$inner, [single]$inner)
    } else {
        $gr.DrawImage($layer, 0, 0, $size, $size)
    }
    $gr.Dispose()
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

foreach ($d in @{ mdpi = 108; hdpi = 162; xhdpi = 216; xxhdpi = 324; xxxhdpi = 432 }.GetEnumerator()) {
    $dir = "$res\mipmap-$($d.Key)"
    Save-Layer $d.Value "$dir\ic_launcher_foreground.png" $layers.Foreground $true
    Save-Layer $d.Value "$dir\ic_launcher_monochrome.png" $layers.Monochrome $true
    Save-Layer $d.Value "$dir\ic_launcher_background.png" $layers.Background $false
}
$adaptive = @'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
'@
[IO.File]::WriteAllText("$res\mipmap-anydpi-v26\ic_launcher.xml", $adaptive.Replace("`r`n", "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
$hex = '#{0:X2}{1:X2}{2:X2}' -f $bg.R, $bg.G, $bg.B

$iosDir = "$app\ios\Runner\Assets.xcassets\AppIcon.appiconset"
foreach ($i in (Get-Content "$iosDir\Contents.json" -Raw | ConvertFrom-Json).images) {
    if (-not $i.filename) { continue }
    $px = [int]([double]($i.size -split 'x')[0] * [double]($i.scale -replace 'x', ''))
    Save-Scaled $px "$iosDir\$($i.filename)"
}

$store = "$app\..\docs\store\assets"
Save-Scaled 512 "$store\icon-512.png"

# Play's feature graphic: the icon and name on the icon's own green.
$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile("$app\assets\fonts\Newsreader_500.ttf")
$fonts.AddFontFile("$app\assets\fonts\Newsreader_400Italic.ttf")
$fg = New-Object System.Drawing.Bitmap 1024, 500
$gr = [System.Drawing.Graphics]::FromImage($fg)
$gr.InterpolationMode = 'HighQualityBicubic'; $gr.TextRenderingHint = 'AntiAlias'
$gr.Clear($bg)
$gr.DrawImage($master, 112, 110, 280, 280)
$ivory = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0xFC, 0xF9, 0xF8))
$gr.DrawString('Chapter', (New-Object System.Drawing.Font $fonts.Families[0], 72, 'Regular', 'Pixel'), $ivory, 430, 150)
$gr.DrawString('Your reading life, in one place.', (New-Object System.Drawing.Font $fonts.Families[0], 30, 'Italic', 'Pixel'), $ivory, 436, 250)
$gr.Dispose()
$fg.Save("$store\feature-graphic-1024x500.png", [System.Drawing.Imaging.ImageFormat]::Png)
$fg.Dispose()

$layers.Foreground.Dispose(); $layers.Monochrome.Dispose(); $layers.Background.Dispose()
$master.Dispose(); $src.Dispose()
"Icons written. Background $hex, icon found at $left,$top size $side."
