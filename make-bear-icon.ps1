# Gera um .ico multi-tamanho de um urso dormindo
Add-Type -AssemblyName System.Drawing

function New-BearBitmap([int]$s) {
    $bmp = New-Object Drawing.Bitmap $s, $s
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([Drawing.Color]::Transparent)
    $u = $s / 256.0
    function Rc($x, $y, $w, $h) { New-Object Drawing.RectangleF ($x*$u), ($y*$u), ($w*$u), ($h*$u) }

    $fur    = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(139, 90, 55))
    $dark   = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(92, 57, 33))
    $muzzle = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(222, 184, 140))
    $inner  = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(205, 150, 110))
    $blush  = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(110, 240, 120, 120))
    $outline = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(70, 42, 24)), ([math]::Max(1, 6*$u))
    $line   = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(50, 30, 18)), ([math]::Max(1.2, 7*$u))
    $line.StartCap = 'Round'; $line.EndCap = 'Round'

    # orelhas
    foreach ($x in 38, 158) {
        $g.FillEllipse($fur, (Rc $x 52 62 62)); $g.DrawEllipse($outline, (Rc $x 52 62 62))
        $g.FillEllipse($inner, (Rc ($x+14) 66 34 34))
    }
    # cabeca
    $g.FillEllipse($fur, (Rc 30 72 196 172)); $g.DrawEllipse($outline, (Rc 30 72 196 172))
    # bochechas
    $g.FillEllipse($blush, (Rc 52 172 36 22)); $g.FillEllipse($blush, (Rc 168 172 36 22))
    # olhos fechados (arcos)
    $g.DrawArc($line, (Rc 68 138 42 26), 20, 140)
    $g.DrawArc($line, (Rc 146 138 42 26), 20, 140)
    # focinho
    $g.FillEllipse($muzzle, (Rc 90 168 76 60))
    $g.FillEllipse($dark, (Rc 112 176 32 22))
    $g.DrawArc($line, (Rc 114 196 14 14), 0, 150)
    $g.DrawArc($line, (Rc 128 196 14 14), 30, 150)

    # Zz (omitido no tamanho 16, fica ilegivel)
    if ($s -ge 24) {
        $zb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(90, 150, 255))
        $zo = New-Object Drawing.Pen ([Drawing.Color]::White), ([math]::Max(1, 5*$u))
        $zo.LineJoin = 'Round'
        foreach ($z in @(@(150, 0, 74), @(206, 34, 50))) {
            $path = New-Object Drawing.Drawing2D.GraphicsPath
            $path.AddString('Z', (New-Object Drawing.FontFamily 'Segoe UI Black'), 0, ($z[2]*$u), (New-Object Drawing.PointF ($z[0]*$u), ($z[1]*$u)), [Drawing.StringFormat]::GenericDefault)
            $g.DrawPath($zo, $path); $g.FillPath($zb, $path)
        }
    }
    $g.Dispose()
    return $bmp
}

$sizes = 16, 24, 32, 48, 64, 128, 256
$pngs = foreach ($s in $sizes) {
    $b = New-BearBitmap $s
    $ms = New-Object IO.MemoryStream
    $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
    , $ms.ToArray()
}

$out = $args[0]
$fs = [IO.File]::Create($out)
$w = New-Object IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $w.Write([byte]$d); $w.Write([byte]$d); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $w.Write($p) }
$w.Close()

# preview para conferencia
if ($args[1]) { $b = New-BearBitmap 256; $b.Save($args[1], [Drawing.Imaging.ImageFormat]::Png); $b.Dispose() }

