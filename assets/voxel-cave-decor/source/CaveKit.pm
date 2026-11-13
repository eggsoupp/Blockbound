package CaveKit;
# Voxel kit for the cave decorations, on top of the decor kit (DecorKit:
# block-texture colours, re-sampled by exposed face) and the enemy rigs'
# VoxLib (shapes).
#
# A decoration is one block wide and 1-3 blocks tall, so a model is
# 16 x 16*tall x 16 voxels of 0.25 studs: x and z run -8..7, y runs
# 0..16*tall-1. The cell's middle is the line between voxels -1 and 0, so in
# CELL-CENTRED coordinates (dx = x + 0.5, dz = z + 0.5) every voxel centre
# is a half integer from -7.5 to 7.5, and a shape written with |dx| and |dz|
# is symmetric by construction. cave() mirrors the finished model anyway and
# reports any voxel that had no mirror image.
#
# A model taller than one block is cut into one-block segments in the game
# (Icicle3_1 is the bottom block of a three-block icicle), so a tall piece is
# drawn as one continuous shape across its cells.

use strict;
use warnings;
use POSIX qw(floor ceil);
use Exporter 'import';
use VoxLib;
use DecorKit;
use VoxOut;

our @EXPORT = qw(cave models P field cone dome metric orbit_axis orbit_diag);

my @MODELS;

sub models { return @MODELS }

# Cell-centred (dx, y, dz) -> voxel index coordinates for VoxLib shapes.
sub P { return [ $_[0] - 0.5, $_[1], $_[2] - 0.5 ] }

# Four points round the middle: on the axes, or on the diagonals.
sub orbit_axis { my $d = shift; return ([ $d, 0 ], [ -$d, 0 ], [ 0, $d ], [ 0, -$d ]) }
sub orbit_diag { my $d = shift; return ([ $d, $d ], [ -$d, $d ], [ $d, -$d ], [ -$d, -$d ]) }

# Distance from the middle in one of four cross-sections, all symmetric
# under the eight mirrors of a square.
sub metric {
	my ($shape, $dx, $dz) = @_;
	$dx = abs $dx;
	$dz = abs $dz;
	return sqrt($dx * $dx + $dz * $dz) if $shape eq 'round';
	my $max = $dx > $dz ? $dx : $dz;
	return $max if $shape eq 'square';
	return $dx + $dz if $shape eq 'diamond';
	if ($shape eq 'oct') {
		my $cut = ($dx + $dz) / 1.3;
		return $max > $cut ? $max : $cut;
	}
	die "unknown cross-section $shape\n";
}

# Every voxel of rows y0..y1 for which $test->(dx, y, dz) is true.
sub field {
	my ($y0, $y1, $test, $c) = @_;
	($y0, $y1) = ($y1, $y0) if $y0 > $y1;
	for my $y (ceil($y0 - 1e-9) .. floor($y1 + 1e-9)) {
		for my $x (-8 .. 7) {
			for my $z (-8 .. 7) {
				VoxLib::setv($x, $y, $z, $c) if $test->($x + 0.5, $y, $z + 0.5);
			}
		}
	}
}

# A tapered column from y0 (radius r0) to y1 (radius r1); y1 below y0 for
# one that hangs. pow > 1 thins quickly near y0, < 1 stays thick longer.
# ox / oz move it off the middle (use the orbit_* points to keep symmetry).
sub cone {
	my (%o) = @_;
	my ($y0, $y1, $r0, $r1) = @o{qw(y0 y1 r0 r1)};
	my $shape = $o{shape} // 'round';
	my $pow = $o{pow} // 1;
	my ($ox, $oz) = ($o{ox} // 0, $o{oz} // 0);
	field($y0, $y1, sub {
		my ($dx, $y, $dz) = @_;
		my $t = $y1 == $y0 ? 0 : ($y - $y0) / ($y1 - $y0);
		my $r = $r1 + ($r0 - $r1) * (1 - $t)**$pow;
		return metric($shape, $dx - $ox, $dz - $oz) <= $r + 1e-6;
	}, $o{c});
}

# Ellipsoid centred at (ox, cy, oz), radius r across and ry up.
sub dome {
	my (%o) = @_;
	my ($cy, $r, $ry) = @o{qw(cy r ry)};
	my ($ox, $oz) = ($o{ox} // 0, $o{oz} // 0);
	my $shape = $o{shape} // 'round';
	field($cy - $ry, $cy + $ry, sub {
		my ($dx, $y, $dz) = @_;
		my $d = metric($shape, $dx - $ox, $dz - $oz) / $r;
		my $v = ($y - $cy) / $ry;
		return $d * $d + $v * $v <= 1 + 1e-6;
	}, $o{c});
}

# ---------------------------------------------------------------- symmetry

# Images of (x, z) in voxel index coordinates. 'd4' = all eight mirrors of
# the square, 'quad' = across x and across z, 'x' = across x only.
sub images {
	my ($sym, $x, $z) = @_;
	my ($a, $b) = ($x + 0.5, $z + 0.5);
	my @p = ([ $a, $b ], [ -$a, $b ]);
	push @p, [ $a, -$b ], [ -$a, -$b ] if $sym eq 'quad' || $sym eq 'd4';
	push @p, [ $b, $a ], [ -$b, $a ], [ $b, -$a ], [ -$b, -$a ] if $sym eq 'd4';
	return map { [ $_->[0] - 0.5, $_->[1] - 0.5 ] } @p;
}

sub symmetrize {
	my ($m, $sym) = @_;
	return 0 if $sym eq 'none';
	my $g = $m->{grid};
	my @add;
	while (my ($k, $v) = each %$g) {
		my ($x, $y, $z) = split /,/, $k;
		for my $p (images($sym, $x, $z)) {
			my $key = "$p->[0],$y,$p->[1]";
			push @add, [ $key, $v ] unless exists $g->{$key};
		}
	}
	my %seen;
	for (@add) {
		next if $seen{ $_->[0] }++;
		$g->{ $_->[0] } = [ @{ $_->[1] } ];
	}
	return scalar keys %seen;
}

# ---------------------------------------------------------------- pieces

# cave(Block, anchor => 'floor'|'ceiling', talls => [1, 2], sym => 'd4',
#      parts => { Ice => 0.25 }, body => sub { my ($tall, $H, $TOP) = @_ })
# Builds one model per height. Parts other than Body are see-through by the
# given amount.
sub cave {
	my ($block, %o) = @_;
	my $anchor = $o{anchor} or die "$block: no anchor\n";
	my $sym = $o{sym} // 'd4';
	for my $tall (@{ $o{talls} }) {
		my $H = 16 * $tall;
		my $TOP = $H - 1;
		my $id = $tall == 1 ? $block : "$block$tall";
		my $m = DecorKit::piece($id, sub { $o{body}->($tall, $H, $TOP) });
		for my $k (keys %{ $m->{grid} }) {
			my (undef, $y) = split /,/, $k;
			delete $m->{grid}{$k} if $y > $TOP;
		}
		my $added = symmetrize($m, $sym);
		DecorKit::resolve($m);

		my ($lo, $hi) = VoxOut::bounds([ map { [ split /,/ ] } keys %{ $m->{grid} } ]);
		die sprintf("%s spans x %d..%d z %d..%d, the cell is -8..7\n", $id, $lo->[0], $hi->[0], $lo->[2], $hi->[2])
			if $lo->[0] < -8 || $hi->[0] > 7 || $lo->[2] < -8 || $hi->[2] > 7;
		die "$id does not touch the floor\n" if $anchor eq 'floor' && $lo->[1] != 0;
		die "$id does not touch the ceiling\n" if $anchor eq 'ceiling' && $hi->[1] != $TOP;

		push @MODELS, {
			block => $block, id => $id, tall => $tall, anchor => $anchor, sym => $sym,
			parts => $o{parts} || {}, m => $m, mirrored => $added, biome => $o{biome} // '',
		};
	}
}

1;
