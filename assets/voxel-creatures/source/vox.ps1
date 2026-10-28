
# Reader for Build-engine / Voxlap style dense .vox:
# int32 sx, sy, sz; sx*sy*sz palette indices (x outer, z inner, 255 = empty); 256*3 palette, 6-bit.
function Read-Vox([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    if ([System.Text.Encoding]::ASCII.GetString($b, 0, 4) -eq 'VOX ') { return Read-MagicaVox $b }
    $sx = [BitConverter]::ToInt32($b, 0); $sy = [BitConverter]::ToInt32($b, 4); $sz = [BitConverter]::ToInt32($b, 8)
    $n = $sx * $sy * $sz
    if (12 + $n + 768 -ne $b.Length) { throw "unexpected size: $path" }
    $palOff = 12 + $n
    $palette = New-Object 'int[]' 1024
    for ($i = 0; $i -lt 256; $i++) {
        $palette[$i * 4] = [math]::Min(255, $b[$palOff + $i * 3] * 4)
        $palette[$i * 4 + 1] = [math]::Min(255, $b[$palOff + $i * 3 + 1] * 4)
        $palette[$i * 4 + 2] = [math]::Min(255, $b[$palOff + $i * 3 + 2] * 4)
        $palette[$i * 4 + 3] = 255
    }
    $list = New-Object System.Collections.Generic.List[int]
    $o = 12
    for ($x = 0; $x -lt $sx; $x++) {
        for ($y = 0; $y -lt $sy; $y++) {
            for ($z = 0; $z -lt $sz; $z++) {
                $c = $b[$o]; $o++
                if ($c -ne 255) { $list.Add($x); $list.Add($y); $list.Add($z); $list.Add($c + 1) }
            }
        }
    }
    $vox = $list.ToArray()
    $models = @(@{ size = @($sx, $sy, $sz); vox = $vox; count = $vox.Length / 4 })
    return @{ models = $models; palette = $palette }
}

# MagicaVoxel files are z-up; converted to the dense format's convention (z down from the top).
function Read-MagicaVox($b) {
    $size = $null; $raw = $null; $count = 0; $palette = $null
    $p = 20
    while ($p + 12 -le $b.Length) {
        $id = [System.Text.Encoding]::ASCII.GetString($b, $p, 4)
        $n = [BitConverter]::ToInt32($b, $p + 4); $m = [BitConverter]::ToInt32($b, $p + 8)
        $c = $p + 12
        if ($id -eq 'SIZE' -and -not $size) { $size = @([BitConverter]::ToInt32($b, $c), [BitConverter]::ToInt32($b, $c + 4), [BitConverter]::ToInt32($b, $c + 8)) }
        if ($id -eq 'XYZI' -and -not $raw) { $count = [BitConverter]::ToInt32($b, $c); $raw = $c + 4 }
        if ($id -eq 'RGBA') {
            $palette = New-Object 'int[]' 1024
            # RGBA entry i is colour index i+1, the same index-1 lookup the dense reader uses.
            for ($i = 0; $i -lt 1024; $i++) { $palette[$i] = $b[$c + $i] }
        }
        $p = $c + $n + $m
    }
    $sz = $size[2]
    $vox = New-Object 'int[]' ($count * 4)
    for ($i = 0; $i -lt $count; $i++) {
        $o = $raw + $i * 4
        $vox[$i * 4] = $b[$o]; $vox[$i * 4 + 1] = $b[$o + 1]; $vox[$i * 4 + 2] = $sz - 1 - $b[$o + 2]; $vox[$i * 4 + 3] = $b[$o + 3]
    }
    return @{ models = @(@{ size = $size; vox = $vox; count = $count }); palette = $palette }
}
