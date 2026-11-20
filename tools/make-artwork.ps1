# Generates every icon / splash / launch image for Windows, Android and iOS
# from ONE logo definition (two fanned playing cards on green felt), into res\.
#   .\tools\make-artwork.ps1
# Change the colours or the card geometry below and run it again to restyle
# all platforms at once. Solitaire.dproj and the deployproj point at res\.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$inv  = [Globalization.CultureInfo]::InvariantCulture

# ---------- the logo, in a 108 x 108 box (Android's adaptive-icon grid) ----------
$FeltTop = '#25804A'; $Felt = '#1B6B3A'; $FeltBottom = '#124A28'
$CardFace = '#FDFDF8'; $Red = '#D12B2B'; $Black = '#1E1E1E'
$Cards = @(
    @{ X = 25; Y = 29; W = 33; H = 47; R = 4.2; Rot = -13; Suit = 'heart'; SuitSize = 18; SX = -4.5; SY = -2; Color = $Red },
    @{ X = 47; Y = 30; W = 35; H = 50; R = 4.4; Rot = 9;   Suit = 'spade'; SuitSize = 24; SX = 0; SY = 0; Color = $Black }
)
# suit outlines in a 0..1 box: M = move, C = cubic bezier (3 points), L = line
$Suits = @{
    heart = @(@('M',0.5,0.95), @('C',0.10,0.65,0,0.42,0,0.28), @('C',0,0.10,0.13,0.02,0.26,0.02),
              @('C',0.38,0.02,0.46,0.10,0.5,0.20), @('C',0.54,0.10,0.62,0.02,0.74,0.02),
              @('C',0.87,0.02,1,0.10,1,0.28), @('C',1,0.42,0.90,0.65,0.5,0.95))
    spade = @(@('M',0.5,0.02), @('C',0.90,0.32,1,0.50,1,0.62), @('C',1,0.76,0.90,0.84,0.78,0.84),
              @('C',0.68,0.84,0.60,0.80,0.55,0.72), @('C',0.56,0.85,0.60,0.93,0.68,0.98), @('L',0.32,0.98),
              @('C',0.40,0.93,0.44,0.85,0.45,0.72), @('C',0.40,0.80,0.32,0.84,0.22,0.84),
              @('C',0.10,0.84,0,0.76,0,0.62), @('C',0,0.50,0.10,0.32,0.5,0.02))
}

function Col([string]$hex, [int]$alpha = 255) {
    $c = [Drawing.ColorTranslator]::FromHtml($hex); [Drawing.Color]::FromArgb($alpha, $c.R, $c.G, $c.B)
}
function N([double]$v) { [Math]::Round($v, 2).ToString($inv) }

# ---------- raster drawing (GDI+) ----------
function New-RoundRectPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return ,$p
}
function New-SuitPath([string]$suit, [single]$x, [single]$y, [single]$s) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $cx = 0.0; $cy = 0.0
    foreach ($c in $Suits[$suit]) {
        if ($c[0] -eq 'M') { $cx = $x + $c[1] * $s; $cy = $y + $c[2] * $s }
        elseif ($c[0] -eq 'L') {
            $nx = $x + $c[1] * $s; $ny = $y + $c[2] * $s
            $p.AddLine([single]$cx, [single]$cy, [single]$nx, [single]$ny); $cx = $nx; $cy = $ny
        } else {
            $nx = $x + $c[5] * $s; $ny = $y + $c[6] * $s
            $p.AddBezier([single]$cx, [single]$cy, [single]($x + $c[1] * $s), [single]($y + $c[2] * $s),
                         [single]($x + $c[3] * $s), [single]($y + $c[4] * $s), [single]$nx, [single]$ny)
            $cx = $nx; $cy = $ny
        }
    }
    $p.CloseFigure()
    return ,$p
}

# Draws the two cards. (ox, oy) = where the 108-box starts, k = pixels per unit.
function Draw-Logo($g, [single]$ox, [single]$oy, [single]$k) {
    foreach ($c in $Cards) {
        $state = $g.Save()
        $cx = $ox + ($c.X + $c.W / 2) * $k; $cy = $oy + ($c.Y + $c.H / 2) * $k
        $g.TranslateTransform($cx, $cy); $g.RotateTransform($c.Rot)
        $w = $c.W * $k; $h = $c.H * $k; $r = $c.R * $k
        # soft shadow, then the card, a hairline edge, and its suit
        $sh = New-RoundRectPath (-$w / 2 + 1.2 * $k) (-$h / 2 + 1.8 * $k) $w $h $r
        $b = New-Object Drawing.SolidBrush (Col '#000000' 70); $g.FillPath($b, $sh); $b.Dispose(); $sh.Dispose()
        $card = New-RoundRectPath (-$w / 2) (-$h / 2) $w $h $r
        $b = New-Object Drawing.SolidBrush (Col $CardFace); $g.FillPath($b, $card); $b.Dispose()
        $pen = New-Object Drawing.Pen (Col '#000000' 70), ([single][Math]::Max(1.0, 0.5 * $k)); $g.DrawPath($pen, $card); $pen.Dispose(); $card.Dispose()
        $s = $c.SuitSize * $k
        $sp = New-SuitPath $c.Suit (-$s / 2 + $c.SX * $k) (-$s / 2 + $c.SY * $k) $s
        $b = New-Object Drawing.SolidBrush (Col $c.Color); $g.FillPath($b, $sp); $b.Dispose(); $sp.Dispose()
        $g.Restore($state)
    }
}

function New-Canvas([int]$w, [int]$h) {
    $bmp = New-Object Drawing.Bitmap $w, $h, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.InterpolationMode = 'HighQualityBicubic'
    $g.Clear([Drawing.Color]::Transparent)
    return $bmp, $g
}
function Fill-Felt($g, $path, [single]$top, [single]$bottom) {
    $b = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.PointF 0, $top), (New-Object Drawing.PointF 0, $bottom), (Col $FeltTop), (Col $FeltBottom)
    $g.FillPath($b, $path); $b.Dispose()
}

# A felt tile with the logo. Corner = corner radius as a fraction of the size
# (0 = square and opaque, as iOS wants). Zoom enlarges the cards inside the tile.
function New-Tile([int]$size, [double]$corner, [double]$zoom = 1.3) {
    $bmp, $g = New-Canvas $size $size
    $tile = New-RoundRectPath 0 0 $size $size ([single]([Math]::Max(0.01, $size * $corner)))
    if ($corner -le 0) { $tile.Dispose(); $tile = New-Object Drawing.Drawing2D.GraphicsPath; $tile.AddRectangle((New-Object Drawing.RectangleF -1, -1, ($size + 2), ($size + 2))) }
    Fill-Felt $g $tile 0 $size
    $g.SetClip($tile)
    $k = $size / 108.0 * $zoom
    # the cards' own centre in the 108 box is about (53.5, 54.5)
    Draw-Logo $g ([single]($size / 2 - 53.5 * $k)) ([single]($size / 2 - 54.5 * $k)) ([single]$k)
    $g.Dispose(); $tile.Dispose()
    return ,$bmp
}
function Save-Png($bmp, [string]$rel, [switch]$Opaque) {
    $path = Join-Path $root $rel
    New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
    if ($Opaque) {
        # iOS rejects app icons with an alpha channel
        $flat = New-Object Drawing.Bitmap $bmp.Width, $bmp.Height, ([Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $g = [Drawing.Graphics]::FromImage($flat); $g.Clear((Col $Felt)); $g.DrawImage($bmp, 0, 0, $bmp.Width, $bmp.Height); $g.Dispose()
        $flat.Save($path, [Drawing.Imaging.ImageFormat]::Png); $flat.Dispose()
    } else { $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png) }
    $bmp.Dispose()
    $script:made++
}
$made = 0

# ---------- Windows: one .ico holding every size ----------
$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$pngs = foreach ($s in $sizes) {
    $bmp = New-Tile $s 0.2 $(if ($s -le 24) { 1.5 } else { 1.3 })
    $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); , $ms.ToArray()
}
New-Item -ItemType Directory -Force (Join-Path $root 'res\win') | Out-Null
$fs = [IO.File]::Create((Join-Path $root 'res\win\Solitaire.ico')); $bw = New-Object IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $bw.Write([byte]($sizes[$i] % 256)); $bw.Write([byte]($sizes[$i] % 256)); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Dispose(); $fs.Dispose(); $made++
Save-Png (New-Tile 512 0.2) 'res\win\Solitaire_512.png'      # for store pages, shortcuts, the installer

# ---------- Android ----------
foreach ($s in 36, 48, 72, 96, 144, 192) { Save-Png (New-Tile $s 0.22) "res\android\ic_launcher_$s.png" }
foreach ($wh in @(426, 320), @(470, 320), @(640, 480), @(960, 720)) {
    # bitmap splash for Android versions that do not use the vector one: just the
    # cards on a transparent background, so they sit on the felt window colour
    # (Android_BackgroundColor) with no visible edge
    $bmp, $g = New-Canvas $wh[0] $wh[1]
    $k = $wh[1] * 0.9 / 108.0
    Draw-Logo $g ([single]($wh[0] / 2 - 53.5 * $k)) ([single]($wh[1] / 2 - 54.5 * $k)) ([single]$k)
    $g.Dispose()
    Save-Png $bmp "res\android\splash_$($wh[0])x$($wh[1]).png"
}

# vector versions for the adaptive icon and the splash screen
function Svg-RoundRect($c) {
    $w = $c.W - 2 * $c.R; $h = $c.H - 2 * $c.R; $r = N $c.R
    "M$(N ($c.X + $c.R)),$(N $c.Y) h$(N $w) a$r,$r 0 0 1 $r,$r v$(N $h) a$r,$r 0 0 1 -$r,$r h-$(N $w) a$r,$r 0 0 1 -$r,-$r v-$(N $h) a$r,$r 0 0 1 $r,-$r z"
}
function Svg-Suit($c) {
    $s = $c.SuitSize; $x = $c.X + $c.W / 2 - $s / 2 + $c.SX; $y = $c.Y + $c.H / 2 - $s / 2 + $c.SY
    $out = foreach ($p in $Suits[$c.Suit]) {
        if ($p[0] -eq 'C') { "C$(N ($x + $p[1] * $s)),$(N ($y + $p[2] * $s)) $(N ($x + $p[3] * $s)),$(N ($y + $p[4] * $s)) $(N ($x + $p[5] * $s)),$(N ($y + $p[6] * $s))" }
        else { "$($p[0])$(N ($x + $p[1] * $s)),$(N ($y + $p[2] * $s))" }
    }
    ($out -join ' ') + ' Z'
}
function Vector-Cards([bool]$mono) {
    $lines = foreach ($c in $Cards) {
        $pivot = "android:pivotX=`"$(N ($c.X + $c.W / 2))`" android:pivotY=`"$(N ($c.Y + $c.H / 2))`" android:rotation=`"$($c.Rot)`""
        if ($mono) {
            # one colour only: the suit is cut out of the card
            "        <group $pivot>`n            <path android:pathData=`"$(Svg-RoundRect $c) $(Svg-Suit $c)`" android:fillColor=`"#FFFFFFFF`" android:fillType=`"evenOdd`"/>`n        </group>"
        } else {
            "        <group $pivot>`n            <path android:pathData=`"$(Svg-RoundRect $c)`" android:fillColor=`"#FFFDFDF8`" android:strokeColor=`"#40000000`" android:strokeWidth=`"0.5`"/>`n            <path android:pathData=`"$(Svg-Suit $c)`" android:fillColor=`"#FF$($c.Color.Substring(1))`"/>`n        </group>"
        }
    }
    $lines -join "`n"
}
function Save-Vector([string]$rel, [int]$dp, [double]$scale, [bool]$mono, [string]$backdrop = '') {
    $body = Vector-Cards $mono
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<!-- generated by tools\make-artwork.ps1 -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="${dp}dp"
    android:height="${dp}dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
$backdrop    <group android:pivotX="53.5" android:pivotY="54.5" android:scaleX="$(N $scale)" android:scaleY="$(N $scale)" android:translateX="0.5" android:translateY="-0.5">
$body
    </group>
</vector>
"@
    $path = Join-Path $root $rel
    New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, $xml.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
    $script:made++
}
# adaptive icon: the launcher masks the 108 box to a circle/squircle about 66 wide,
# so the cards (about 60 across) are drawn a little smaller than natural size
Save-Vector 'res\android\adaptive_foreground.xml' 108 0.9 $false
Save-Vector 'res\android\adaptive_monochrome.xml' 108 0.9 $true
$bg = @"
<?xml version="1.0" encoding="utf-8"?>
<!-- generated by tools\make-artwork.ps1 -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:pathData="M0,0h108v108h-108z">
        <aapt:attr xmlns:aapt="http://schemas.android.com/aapt" name="android:fillColor">
            <gradient android:type="linear" android:startX="54" android:startY="0" android:endX="54" android:endY="108"
                android:startColor="#FF$($FeltTop.Substring(1))" android:endColor="#FF$($FeltBottom.Substring(1))"/>
        </aapt:attr>
    </path>
</vector>
"@
[IO.File]::WriteAllText((Join-Path $root 'res\android\adaptive_background.xml'), $bg.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false))); $made++
# splash: the window background is the felt colour (Android_BackgroundColor), the cards sit in the middle.
# Android 12+ crops the icon to a circle two thirds of its size, hence the smaller cards in the v31 files.
Save-Vector 'res\android\splash.xml' 160 1.5 $false
Save-Vector 'res\android\splash_dark.xml' 160 1.5 $false
Save-Vector 'res\android\splash_v31.xml' 288 0.92 $false
Save-Vector 'res\android\splash_v31_dark.xml' 288 0.92 $false

# ---------- iOS ----------
$ios = @{ AppIcon_120 = 120; AppIcon_180 = 180; AppIcon_1024 = 1024; Spotlight_80 = 80; Spotlight_120 = 120
          Setting_58 = 58; Setting_87 = 87; Notification_40 = 40; Notification_60 = 60
          iPadIcon_152 = 152; iPadIcon_167 = 167; iPadSpotlight_80 = 80; iPadSetting_58 = 58; iPadNotification_40 = 40 }
foreach ($name in $ios.Keys) { Save-Png (New-Tile $ios[$name] 0) "res\ios\$name.png" -Opaque }   # square, no alpha: iOS rounds them
foreach ($l in @('Launch_2x', 230, 384), @('Launch_3x', 344, 576), @('iPadLaunch_2x', 415, 694)) {
    # launch image: just the cards on a transparent background; the launch screen
    # itself is the felt colour (iOS_BackgroundColor in the project), light and dark alike
    foreach ($dark in '', 'Dark') {
        $bmp, $g = New-Canvas $l[1] $l[2]
        $k = $l[1] * 0.95 / 66.0      # the two cards together are about 62 units wide
        Draw-Logo $g ([single]($l[1] / 2 - 53.5 * $k)) ([single]($l[2] / 2 - 54.5 * $k)) ([single]$k)
        $g.Dispose()
        Save-Png $bmp ("res\ios\" + $l[0].Replace('Launch', "Launch$dark") + '.png')
    }
}

"$made artwork files written under $(Join-Path $root 'res')"
