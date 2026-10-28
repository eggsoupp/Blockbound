
# Exports a creature .vox as greedy-merged coloured boxes in Roblox axes (X = x, Y = up, Z = y),
# with the palette swatch removed and optional downsampling.
param([string]$path, [int]$factor = 1, [string]$out)
. "$PSScriptRoot\vox.ps1"

$v = Read-Vox $path
$m = $v.models[0]
$sx = $m.size[0]; $sy = $m.size[1]; $sz = $m.size[2]
$pal = $v.palette
$vx = $m.vox
$total = $sx * $sy * $sz
$grid = New-Object 'int[]' $total   # 0 empty, else colour index
for ($i = 0; $i -lt $m.count; $i++) {
    $grid[($vx[$i*4] * $sy + $vx[$i*4+1]) * $sz + $vx[$i*4+2]] = $vx[$i*4+3]
}

# Connected components (6-neighbour); drop the flat swatch lying on the bottom layer.
$label = New-Object 'int[]' $total
$comps = @()
$queue = New-Object 'System.Collections.Generic.Queue[int]'
$next = 0
for ($s = 0; $s -lt $total; $s++) {
    if ($grid[$s] -eq 0 -or $label[$s] -ne 0) { continue }
    $next++
    $label[$s] = $next; $queue.Enqueue($s)
    $count = 0; $zmin = 9999; $zmax = -1
    while ($queue.Count -gt 0) {
        $c = $queue.Dequeue(); $count++
        $z = $c % $sz; $y = [math]::Floor($c / $sz) % $sy; $x = [math]::Floor($c / ($sz * $sy))
        if ($z -lt $zmin) { $zmin = $z }; if ($z -gt $zmax) { $zmax = $z }
        foreach ($d in @(@(1,0,0),@(-1,0,0),@(0,1,0),@(0,-1,0),@(0,0,1),@(0,0,-1))) {
            $nx = $x + $d[0]; $ny = $y + $d[1]; $nz = $z + $d[2]
            if ($nx -lt 0 -or $ny -lt 0 -or $nz -lt 0 -or $nx -ge $sx -or $ny -ge $sy -or $nz -ge $sz) { continue }
            $n = ($nx * $sy + $ny) * $sz + $nz
            if ($grid[$n] -ne 0 -and $label[$n] -eq 0) { $label[$n] = $next; $queue.Enqueue($n) }
        }
    }
    $comps += ,@($next, $count, $zmin, $zmax)
}
$drop = @{}
foreach ($c in $comps) {
    if ($c[2] -ge $sz - 2 -and $c[3] - $c[2] -le 1) { $drop[$c[0]] = $true }
}
$removed = 0
for ($s = 0; $s -lt $total; $s++) { if ($grid[$s] -ne 0 -and $drop[$label[$s]]) { $grid[$s] = 0; $removed++ } }

# Downsample: a cell is solid when a quarter of it is, coloured by its most common colour.
if ($factor -gt 1) {
    $dx = [math]::Ceiling($sx / $factor); $dy = [math]::Ceiling($sy / $factor); $dz = [math]::Ceiling($sz / $factor)
    $g2 = New-Object 'int[]' ($dx * $dy * $dz)
    $need = [math]::Max(1, [math]::Floor($factor * $factor * $factor / 4))
    for ($x = 0; $x -lt $dx; $x++) { for ($y = 0; $y -lt $dy; $y++) { for ($z = 0; $z -lt $dz; $z++) {
        $hist = @{}; $filled = 0
        for ($a = 0; $a -lt $factor; $a++) { for ($b = 0; $b -lt $factor; $b++) { for ($c = 0; $c -lt $factor; $c++) {
            $px = $x * $factor + $a; $py = $y * $factor + $b; $pz = $z * $factor + $c
            if ($px -ge $sx -or $py -ge $sy -or $pz -ge $sz) { continue }
            $col = $grid[($px * $sy + $py) * $sz + $pz]
            if ($col -ne 0) { $filled++; $hist[$col] = 1 + [int]$hist[$col] }
        } } }
        if ($filled -ge $need) {
            $best = 0; $bc = 0
            foreach ($e in $hist.GetEnumerator()) { if ($e.Value -gt $bc) { $bc = $e.Value; $best = $e.Key } }
            $g2[($x * $dy + $y) * $dz + $z] = $best
        }
    } } }
    $grid = $g2; $sx = $dx; $sy = $dy; $sz = $dz; $total = $sx * $sy * $sz
}

function At($x, $y, $z) {
    if ($x -lt 0 -or $y -lt 0 -or $z -lt 0 -or $x -ge $sx -or $y -ge $sy -or $z -ge $sz) { return 0 }
    return $grid[($x * $sy + $y) * $sz + $z]
}

# Hidden voxels can be swallowed by a box of any colour.
$hidden = New-Object 'bool[]' $total
for ($x = 0; $x -lt $sx; $x++) { for ($y = 0; $y -lt $sy; $y++) { for ($z = 0; $z -lt $sz; $z++) {
    $i = ($x * $sy + $y) * $sz + $z
    if ($grid[$i] -ne 0 -and (At ($x+1) $y $z) -and (At ($x-1) $y $z) -and (At $x ($y+1) $z) -and (At $x ($y-1) $z) -and (At $x $y ($z+1)) -and (At $x $y ($z-1))) { $hidden[$i] = $true }
} } }

$done = New-Object 'bool[]' $total
function Fits($x0, $x1, $y0, $y1, $z0, $z1, $col) {
    for ($x = $x0; $x -le $x1; $x++) { for ($y = $y0; $y -le $y1; $y++) { for ($z = $z0; $z -le $z1; $z++) {
        $i = ($x * $sy + $y) * $sz + $z
        if ($hidden[$i]) { continue }
        if ($grid[$i] -ne $col -or $done[$i]) { return $false }
    } } }
    return $true
}

$boxes = New-Object System.Collections.Generic.List[string]
$used = @{}
for ($x = 0; $x -lt $sx; $x++) { for ($y = 0; $y -lt $sy; $y++) { for ($z = 0; $z -lt $sz; $z++) {
    $i = ($x * $sy + $y) * $sz + $z
    if ($grid[$i] -eq 0 -or $hidden[$i] -or $done[$i]) { continue }
    $col = $grid[$i]
    $x1 = $x; $y1 = $y; $z1 = $z
    while ($z1 + 1 -lt $sz -and (Fits $x $x $y $y ($z1+1) ($z1+1) $col)) { $z1++ }
    while ($y1 + 1 -lt $sy -and (Fits $x $x ($y1+1) ($y1+1) $z $z1 $col)) { $y1++ }
    while ($x1 + 1 -lt $sx -and (Fits ($x1+1) ($x1+1) $y $y1 $z $z1 $col)) { $x1++ }
    for ($a = $x; $a -le $x1; $a++) { for ($b = $y; $b -le $y1; $b++) { for ($c = $z; $c -le $z1; $c++) {
        $done[($a * $sy + $b) * $sz + $c] = $true
    } } }
    if (-not $used.ContainsKey($col)) { $used[$col] = $used.Count + 1 }
    # Roblox: X = x, Y = height (vox z counts down), Z = y.
    $boxes.Add(("{0},{1},{2},{3},{4},{5},{6}" -f $x, ($sz - 1 - $z1), $y, ($x1 - $x + 1), ($z1 - $z + 1), ($y1 - $y + 1), $used[$col]))
} } }

$cols = @()
foreach ($e in ($used.GetEnumerator() | Sort-Object Value)) {
    $k = $e.Key - 1
    $cols += "{0},{1},{2}" -f $pal[$k*4], $pal[$k*4+1], $pal[$k*4+2]
}
$name = [System.IO.Path]::GetFileNameWithoutExtension($path)
$text = "return {name=`"$name`",dims={$sx,$sz,$sy},colors=`"" + ($cols -join ';') + "`",boxes=`"" + ($boxes -join ';') + "`"}"
if ($out) { [System.IO.File]::WriteAllText($out, $text) }
"{0}: f={1} dims={2}x{3}x{4} swatch={5} boxes={6} colors={7} bytes={8}" -f $name, $factor, $sx, $sz, $sy, $removed, $boxes.Count, $cols.Count, $text.Length
