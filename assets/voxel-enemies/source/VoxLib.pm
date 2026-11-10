package VoxLib;
# Small voxel modelling kit for the Blockbound enemy rigs.
#
# Designs are written in Roblox axes, in voxel units: +X is the creature's
# right, +Y up, front = -Z, floor at y = 0. Voxel i is centred on i.
# Every voxel belongs to the current rig part; parts are declared with their
# parent and pivot (the joint position, also in voxel units).
#
# Outputs (see write_all): a MagicaVoxel scene (.vox, one named object per
# part), box data for the Studio builder (.lua), a preview sheet (.png) and
# the joint table.

use strict;
use warnings;
use POSIX qw(floor ceil);
use Compress::Zlib;
use Exporter 'import';

our @EXPORT = qw(
	model color part use_part mirror both side
	box ell cap chain prism cyl
	painting cutting masked
	noise cellnoise tone
	outline translate_all finish
	$S $SIDE
);

our ($S, $SIDE) = (1, 'Right');
our $MODE = 'put';	# put | paint | cut
our $MASK;			# optional coderef (x, y, z) -> keep?

my %M;

# ---------------------------------------------------------------- model

sub model {
	my ($name, %o) = @_;
	%M = (
		name => $name, voxel => $o{voxel} // 0.2, desc => $o{desc} // '',
		grid => {}, colors => [], cidx => {}, glow => {},
		parts => [], joints => {}, part => undef,
	);
}

sub color {
	my ($n, $r, $g, $b, %o) = @_;
	push @{ $M{colors} }, [ $n, $r, $g, $b ];
	$M{cidx}{$n} = scalar @{ $M{colors} };
	$M{glow}{$n} = 1 if $o{glow};
}

sub part {
	my ($n, $parent, $pivot, $role) = @_;
	unless ($M{joints}{$n}) {
		die "parent $parent of $n not declared\n" if defined $parent && !$M{joints}{$parent};
		push @{ $M{parts} }, $n;
		$M{joints}{$n} = { parent => $parent, pivot => [ @$pivot ], role => $role // '' };
	}
	$M{part} = $n;
}

sub use_part { $M{part} = shift }

# Runs the block for the right side ($S = 1) then the left ($S = -1).
sub mirror {
	my ($block) = @_;
	# Assign, don't `local`: the designs see $S through an exported alias,
	# and `local` would swap in a scalar they can't see.
	my ($os, $oside) = ($S, $SIDE);
	for my $s (1, -1) {
		$S = $s;
		$SIDE = $s > 0 ? 'Right' : 'Left';
		$block->();
	}
	($S, $SIDE) = ($os, $oside);
}
sub both { my ($block) = @_; $block->(1); $block->(-1); }
sub side { return $SIDE . $_[0] }

sub painting { my ($b) = @_; local $MODE = 'paint'; $b->(); }
sub cutting { my ($b) = @_; local $MODE = 'cut'; $b->(); }
sub masked { my ($m, $b) = @_; local $MASK = $m; $b->(); }

sub setv {
	my ($x, $y, $z, $c) = @_;
	return if $MASK && !$MASK->($x, $y, $z);
	my $k = "$x,$y,$z";
	if ($MODE eq 'cut') {
		my $v = $M{grid}{$k};
		delete $M{grid}{$k} if $v && $v->[0] eq $M{part};
		return;
	}
	if ($MODE eq 'paint') {
		my $v = $M{grid}{$k};
		return unless $v && $v->[0] eq $M{part};
	}
	my $name = ref $c eq 'CODE' ? $c->($x, $y, $z) : $c;
	return unless defined $name;
	my $i = $M{cidx}{$name} // die "unknown colour '$name' in $M{name}\n";
	die "no part selected\n" unless $M{part};
	$M{grid}{$k} = [ $M{part}, $i ];
}

# ---------------------------------------------------------------- shapes

sub box {
	my ($x0, $y0, $z0, $x1, $y1, $z1, $c) = @_;
	($x0, $x1) = ($x1, $x0) if $x0 > $x1;
	($y0, $y1) = ($y1, $y0) if $y0 > $y1;
	($z0, $z1) = ($z1, $z0) if $z0 > $z1;
	for my $x (ceil($x0 - 1e-9) .. floor($x1 + 1e-9)) {
		for my $y (ceil($y0 - 1e-9) .. floor($y1 + 1e-9)) {
			for my $z (ceil($z0 - 1e-9) .. floor($z1 + 1e-9)) { setv($x, $y, $z, $c) }
		}
	}
}

sub ell {
	my ($cx, $cy, $cz, $rx, $ry, $rz, $c) = @_;
	for my $x (floor($cx - $rx) .. ceil($cx + $rx)) {
		my $dx = ($x - $cx) / $rx;
		for my $y (floor($cy - $ry) .. ceil($cy + $ry)) {
			my $dy = ($y - $cy) / $ry;
			for my $z (floor($cz - $rz) .. ceil($cz + $rz)) {
				my $dz = ($z - $cz) / $rz;
				setv($x, $y, $z, $c) if $dx * $dx + $dy * $dy + $dz * $dz <= 1;
			}
		}
	}
}

# Tapered capsule from a (radius ra) to b (radius rb). flat => 1 cuts the
# round ends off.
sub cap {
	my ($a, $b, $ra, $rb, $c, %o) = @_;
	my @ab = map { $b->[$_] - $a->[$_] } 0 .. 2;
	my $len2 = $ab[0]**2 + $ab[1]**2 + $ab[2]**2 || 1e-9;
	my $rm = ($ra > $rb ? $ra : $rb) + 1;
	my @lo = map { floor(($a->[$_] < $b->[$_] ? $a->[$_] : $b->[$_]) - $rm) } 0 .. 2;
	my @hi = map { ceil(($a->[$_] > $b->[$_] ? $a->[$_] : $b->[$_]) + $rm) } 0 .. 2;
	for my $x ($lo[0] .. $hi[0]) {
		for my $y ($lo[1] .. $hi[1]) {
			for my $z ($lo[2] .. $hi[2]) {
				my @ap = ($x - $a->[0], $y - $a->[1], $z - $a->[2]);
				my $t = ($ap[0] * $ab[0] + $ap[1] * $ab[1] + $ap[2] * $ab[2]) / $len2;
				next if $o{flat} && ($t < 0 || $t > 1);
				$t = 0 if $t < 0;
				$t = 1 if $t > 1;
				my $r = $ra + ($rb - $ra) * $t;
				$r = 0.55 if $r < 0.55;
				my $d2 = ($ap[0] - $ab[0] * $t)**2 + ($ap[1] - $ab[1] * $t)**2 + ($ap[2] - $ab[2] * $t)**2;
				setv($x, $y, $z, $c) if $d2 <= ($r + 0.1)**2;
			}
		}
	}
}

# A run of capsules through points; radii per point (or one radius).
sub chain {
	my ($pts, $r, $c) = @_;
	my @r = ref $r ? @$r : ($r) x @$pts;
	cap($pts->[$_], $pts->[$_ + 1], $r[$_], $r[$_ + 1], $c) for 0 .. $#$pts - 1;
}

# 2D polygon extruded along an axis. Points are (x,y) for axis z, (x,z) for
# axis y and (z,y) for axis x.
sub prism {
	my ($axis, $pts, $lo, $hi, $c) = @_;
	my ($umin, $umax, $vmin, $vmax) = (1e9, -1e9, 1e9, -1e9);
	for (@$pts) {
		$umin = $_->[0] if $_->[0] < $umin; $umax = $_->[0] if $_->[0] > $umax;
		$vmin = $_->[1] if $_->[1] < $vmin; $vmax = $_->[1] if $_->[1] > $vmax;
	}
	($lo, $hi) = ($hi, $lo) if $lo > $hi;
	for my $u (floor($umin) .. ceil($umax)) {
		for my $v (floor($vmin) .. ceil($vmax)) {
			next unless inside($pts, $u, $v);
			for my $w (ceil($lo - 1e-9) .. floor($hi + 1e-9)) {
				if ($axis eq 'z') { setv($u, $v, $w, $c) }
				elsif ($axis eq 'y') { setv($u, $w, $v, $c) }
				else { setv($w, $v, $u, $c) }
			}
		}
	}
}

sub inside {
	my ($p, $x, $y) = @_;
	my $in = 0;
	for (my $i = 0, my $j = $#$p; $i <= $#$p; $j = $i++) {
		my ($xi, $yi, $xj, $yj) = ($p->[$i][0], $p->[$i][1], $p->[$j][0], $p->[$j][1]);
		$in = !$in if (($yi > $y) != ($yj > $y)) && ($x < ($xj - $xi) * ($y - $yi) / ($yj - $yi) + $xi);
	}
	return $in;
}

# Cylinder (or tube with inner => r) along an axis; (cu, cv) as in prism.
sub cyl {
	my ($axis, $cu, $cv, $r, $lo, $hi, $c, %o) = @_;
	my $in = $o{inner} // -1;
	($lo, $hi) = ($hi, $lo) if $lo > $hi;
	for my $u (floor($cu - $r) .. ceil($cu + $r)) {
		for my $v (floor($cv - $r) .. ceil($cv + $r)) {
			my $d = sqrt(($u - $cu)**2 + ($v - $cv)**2);
			next if $d > $r + 0.05 || $d < $in;
			for my $w (ceil($lo - 1e-9) .. floor($hi + 1e-9)) {
				if ($axis eq 'z') { setv($u, $v, $w, $c) }
				elsif ($axis eq 'y') { setv($u, $w, $v, $c) }
				else { setv($w, $v, $u, $c) }
			}
		}
	}
}

# ---------------------------------------------------------------- colour

sub noise {
	use integer;
	my ($x, $y, $z, $s) = @_;
	my $h = ($x * 73856093) ^ ($y * 19349663) ^ ($z * 83492791) ^ (($s // 0) * 40503);
	$h = ($h ^ ($h >> 13)) * 1274126177;
	$h = $h ^ ($h >> 16);
	no integer;
	return ($h & 0xffff) / 65536;
}
sub cellnoise {
	my ($x, $y, $z, $cell, $s) = @_;
	return noise(floor($x / $cell), floor($y / $cell), floor($z / $cell), $s);
}
# Colour picker: base, with alt in (chance) of cells of size cell.
sub tone {
	my ($base, $alt, $chance, $cell, $seed) = @_;
	return sub { cellnoise($_[0], $_[1], $_[2], $cell // 2, $seed // 7) < $chance ? $alt : $base };
}

# Recolours the voxels of a part that have an empty neighbour along the
# given axes (thin plates: the rim).
sub outline {
	my ($part, $colour, @axes) = @_;
	my %dirs = (x => [ [ 1, 0, 0 ], [ -1, 0, 0 ] ], y => [ [ 0, 1, 0 ], [ 0, -1, 0 ] ], z => [ [ 0, 0, 1 ], [ 0, 0, -1 ] ]);
	my @d = map { @{ $dirs{$_} } } @axes;
	my $i = $M{cidx}{$colour} // die "unknown colour $colour\n";
	my @hit;
	while (my ($k, $v) = each %{ $M{grid} }) {
		next unless $v->[0] eq $part;
		my ($x, $y, $z) = split /,/, $k;
		for (@d) {
			my $n = $M{grid}{ ($x + $_->[0]) . ',' . ($y + $_->[1]) . ',' . ($z + $_->[2]) };
			if (!$n || $n->[0] ne $part) { push @hit, $k; last }
		}
	}
	$M{grid}{$_}[1] = $i for @hit;
}

sub translate_all {
	my ($dx, $dy, $dz) = @_;
	my %g;
	while (my ($k, $v) = each %{ $M{grid} }) {
		my ($x, $y, $z) = split /,/, $k;
		$g{ ($x + $dx) . ',' . ($y + $dy) . ',' . ($z + $dz) } = $v;
	}
	$M{grid} = \%g;
	for (values %{ $M{joints} }) { $_->{pivot}[0] += $dx; $_->{pivot}[1] += $dy; $_->{pivot}[2] += $dz; }
}

sub finish { my %copy = %M; return \%copy; }

1;
