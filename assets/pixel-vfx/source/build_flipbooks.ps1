# Repacks the pixel VFX sheets in sheets/ into Roblox flipbooks in flipbooks/.
#   powershell -ExecutionPolicy Bypass -File assets/pixel-vfx/source/build_flipbooks.ps1
#
# The sheets are N x N grids of 100 px frames with the art small in the middle
# of each. A ParticleEmitter flipbook must be a square texture split 2x2, 4x4
# or 8x8, so each sheet is cropped to the box every frame fits in, scaled up
# with nearest-neighbour (pixel art stays crisp) into 128 px cells, and
# resampled to exactly 64 frames so the animation spans the whole Grid8x8.
#
#   output name, sheet, columns in the sheet, cell size in the sheet
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

$books = @(
	@('fire_flame', '9', 8, 100),
	@('fire_ring',  '7', 8, 100),
	@('fire_burst', '6', 7, 100)
)

$OUT_CELL = 128
$OUT_GRID = 8
Add-Type -AssemblyName System.Drawing

function Get-Bounds($bmp, $rect) {
	$x0 = 99999; $y0 = 99999; $x1 = -1; $y1 = -1
	for ($y = $rect.Y; $y -lt $rect.Bottom; $y++) {
		for ($x = $rect.X; $x -lt $rect.Right; $x++) {
			if ($bmp.GetPixel($x, $y).A -gt 8) {
				if ($x -lt $x0) { $x0 = $x }; if ($x -gt $x1) { $x1 = $x }
				if ($y -lt $y0) { $y0 = $y }; if ($y -gt $y1) { $y1 = $y }
			}
		}
	}
	if ($x1 -lt 0) { return $null }
	return @(($x0 - $rect.X), ($y0 - $rect.Y), ($x1 - $rect.X), ($y1 - $rect.Y))
}

foreach ($book in $books) {
	$name, $sheet, $cols, $cell = $book
	$src = [System.Drawing.Bitmap]::FromFile((Join-Path $root "sheets/$sheet.png"))
	$rowsInSheet = [math]::Floor($src.Height / $cell)

	# Frames in reading order up to the last one with anything in it, and the
	# box (relative to a cell) that holds all of them.
	$frames = @(); $last = -1
	$ux0 = $cell; $uy0 = $cell; $ux1 = 0; $uy1 = 0
	for ($i = 0; $i -lt $cols * $rowsInSheet; $i++) {
		$rect = New-Object System.Drawing.Rectangle (($i % $cols) * $cell), ([math]::Floor($i / $cols) * $cell), $cell, $cell
		$frames += $rect
		$b = Get-Bounds $src $rect
		if ($b) {
			$last = $i
			if ($b[0] -lt $ux0) { $ux0 = $b[0] }; if ($b[1] -lt $uy0) { $uy0 = $b[1] }
			if ($b[2] -gt $ux1) { $ux1 = $b[2] }; if ($b[3] -gt $uy1) { $uy1 = $b[3] }
		}
	}
	$frames = $frames[0..$last]
	$side = [math]::Max($ux1 - $ux0 + 1, $uy1 - $uy0 + 1) + 2
	$cx = ($ux0 + $ux1 + 1) / 2; $cy = ($uy0 + $uy1 + 1) / 2
	$sx = [math]::Floor($cx - $side / 2); $sy = [math]::Floor($cy - $side / 2)

	$out = New-Object System.Drawing.Bitmap ($OUT_CELL * $OUT_GRID), ($OUT_CELL * $OUT_GRID), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$g = [System.Drawing.Graphics]::FromImage($out)
	$g.Clear([System.Drawing.Color]::Transparent)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
	$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
	$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
	$total = $OUT_GRID * $OUT_GRID
	for ($k = 0; $k -lt $total; $k++) {
		$f = $frames[[math]::Floor($k * $frames.Count / $total)]
		$from = New-Object System.Drawing.Rectangle ($f.X + $sx), ($f.Y + $sy), $side, $side
		$to = New-Object System.Drawing.Rectangle (($k % $OUT_GRID) * $OUT_CELL), ([math]::Floor($k / $OUT_GRID) * $OUT_CELL), $OUT_CELL, $OUT_CELL
		$g.DrawImage($src, $to, $from, [System.Drawing.GraphicsUnit]::Pixel)
	}
	$g.Dispose()
	$out.Save((Join-Path $root "flipbooks/$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
	"$name : $($frames.Count) frames, crop $side px"
}
