
param([string]$dir, [string]$out, [string]$filter = '.')
. "$PSScriptRoot\vox.ps1"
Add-Type -AssemblyName System.Drawing

$files = Get-ChildItem $dir -Filter *.vox | Where-Object { $_.Name -ne '- all.vox' -and $_.Name -match $filter } | Sort-Object Name
$tile = 150; $cols = 4
$rows = [math]::Ceiling($files.Count / $cols)
$bmp = New-Object System.Drawing.Bitmap ($cols * $tile * 2), ($rows * ($tile + 16))
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(70, 70, 70))
$font = New-Object System.Drawing.Font 'Arial', 9
$k = 0
$info = @()
foreach ($f in $files) {
    $v = Read-Vox $f.FullName
    $pal = $v.palette
    $col = $k % $cols; $row = [math]::Floor($k / $cols)
    $ox = $col * $tile * 2; $oy = $row * ($tile + 16)
    $total = 0
    foreach ($mdl in $v.models) { $total += $mdl.count }
    $mdl = $v.models[0]
    $sx = $mdl.size[0]; $sy = $mdl.size[1]; $sz = $mdl.size[2]
    $info += "{0}: models={1} size={2}x{3}x{4} voxels={5}" -f $f.BaseName, $v.models.Count, $sx, $sy, $sz, $total
    $scale = [math]::Floor(($tile - 6) / [math]::Max([math]::Max($sx, $sy), $sz))
    if ($scale -lt 1) { $scale = 1 }
    # front: look along +Y (min y wins); side: look along -X (max x wins)
    $front = @{}; $side = @{}
    $vx = $mdl.vox
    for ($i = 0; $i -lt $mdl.count; $i++) {
        $x = $vx[$i * 4]; $y = $vx[$i * 4 + 1]; $z = $vx[$i * 4 + 2]; $ci = $vx[$i * 4 + 3]
        $kf = $x * 1000 + $z
        if (-not $front.ContainsKey($kf) -or $front[$kf][0] -gt $y) { $front[$kf] = @($y, $ci) }
        $ks = $y * 1000 + $z
        if (-not $side.ContainsKey($ks) -or $side[$ks][0] -lt $x) { $side[$ks] = @($x, $ci) }
    }
    foreach ($e in $front.GetEnumerator()) {
        $x = [math]::Floor($e.Key / 1000); $z = $e.Key % 1000
        $ci = $e.Value[1] - 1; $sh = 1 - 0.5 * $e.Value[0] / [math]::Max($sy, 1)
        $c = [System.Drawing.Color]::FromArgb([int]($pal[$ci * 4] * $sh), [int]($pal[$ci * 4 + 1] * $sh), [int]($pal[$ci * 4 + 2] * $sh))
        $g.FillRectangle((New-Object System.Drawing.SolidBrush $c), $ox + 3 + $x * $scale, $oy + 3 + $z * $scale, $scale, $scale)
    }
    foreach ($e in $side.GetEnumerator()) {
        $y = [math]::Floor($e.Key / 1000); $z = $e.Key % 1000
        $ci = $e.Value[1] - 1; $sh = 0.5 + 0.5 * $e.Value[0] / [math]::Max($sx, 1)
        $c = [System.Drawing.Color]::FromArgb([int]($pal[$ci * 4] * $sh), [int]($pal[$ci * 4 + 1] * $sh), [int]($pal[$ci * 4 + 2] * $sh))
        $g.FillRectangle((New-Object System.Drawing.SolidBrush $c), $ox + $tile + 3 + $y * $scale, $oy + 3 + $z * $scale, $scale, $scale)
    }
    $g.DrawString($f.BaseName, $font, [System.Drawing.Brushes]::White, $ox + 3, $oy + $tile)
    $k++
}
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$info
