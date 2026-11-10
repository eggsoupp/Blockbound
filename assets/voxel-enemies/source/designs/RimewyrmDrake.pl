# Rimewyrm Drake: a frost wyvern standing on its hind legs. Steel-blue
# scales over a pale belly, ice crystals down the spine and tail, swept
# horns, a frost glow in the mouth and half-spread membrane wings.
use strict; use warnings;
use VoxLib;

model('RimewyrmDrake', voxel => 0.2, desc => 'Frost wyvern with ice-crystal spines, membrane wings and a frost-lit maw');

color(scale => 62, 96, 146);
color(scaleDark => 36, 56, 96);
color(scaleLight => 104, 146, 196);
color(belly => 176, 210, 230);
color(membrane => 112, 164, 210);
color(membraneDark => 72, 112, 162);
color(membraneEdge => 214, 238, 252);
color(ice => 182, 236, 255);
color(iceGlow => 120, 226, 255, glow => 1);
color(horn => 226, 230, 238);
color(hornDark => 150, 160, 178);
color(eye => 170, 252, 255, glow => 1);
color(tooth => 242, 246, 250);
color(claw => 40, 46, 62);

my $scales = sub {
	my ($x, $y, $z) = @_;
	return 'belly' if $y < 25 || ($z < -8 && $y < 30);
	return VoxLib::cellnoise($x, $y, $z, 2, 3) < 0.25 ? 'scaleDark' : (VoxLib::cellnoise($x, $y, $z, 3, 9) < 0.12 ? 'scaleLight' : 'scale');
};
my $hide = sub { my ($x, $y, $z) = @_; return VoxLib::cellnoise($x, $y, $z, 2, 3) < 0.25 ? q(scaleDark) : q(scale); };
my $tailScales = sub {
	my ($x, $y, $z) = @_;
	return q(belly) if $y < 30 - ($z - 14) * 11 / 36 - 2.5;
	return $hide->(@_);
};
my $neckScales = sub {
	my ($x, $y, $z) = @_;
	return 'belly' if $z < -17 + ($y - 36) * -0.5 && abs($x) < 3;
	return VoxLib::cellnoise($x, $y, $z, 2, 4) < 0.25 ? 'scaleDark' : 'scale';
};
sub spine {
	my ($at, $len, $lean) = @_;
	cap($at, [ $at->[0], $at->[1] + $len, $at->[2] + $lean ], 1.5, 0.35, sub { $_[1] > $at->[1] + $len * 0.6 ? 'iceGlow' : 'ice' });
}

# ---- Body (root): chest and barrel, ice spines along the back.
part('Body', undef, [ 0, 30, 2 ], 'Root body');
ell(0, 30, 3, 9, 8.5, 13, $scales);
ell(0, 32, -6, 8, 8.5, 7.5, $scales);
for my $z (-8, -3, 2, 7, 12) {
	my $t = ($z - 3) / 13;
	spine([ 0, 30 + 8.5 * sqrt(1 - $t * $t) - 1, $z ], 5 - abs($t) * 2, 2);
}

# ---- Neck: long S-curve, belly plates in front, small spines behind.
part('Neck', 'Body', [ 0, 36, -9 ], 'Neck raise / sway');
chain([ [ 0, 36, -9 ], [ 0, 44, -15 ], [ 0, 51, -18 ], [ 0, 56, -20 ] ], [ 5.2, 4.2, 3.7, 3.4 ], $neckScales);
spine([ 0, 44, -11 ], 3, 2);
spine([ 0, 51, -15 ], 2.5, 2);

# ---- Head: wedge skull, glowing eyes, swept horns, upper teeth.
part('Head', 'Neck', [ 0, 56, -20 ], 'Head turn / nod');
masked(sub { $_[1] >= 57 }, sub {
	ell(0, 60, -23, 4.6, 4, 5.5, 'scale');
	cap([ 0, 59.5, -26 ], [ 0, 58.5, -35 ], 3.2, 2.3, sub { $_[1] >= 61 ? 'scaleDark' : 'scale' });
});
both(sub {
	my $s = shift;
	ell($s * 3.6, 61, -26, 1.2, 1, 1.2, 'eye');
	cap([ $s * 2.6, 62.5, -27.5 ], [ $s * 3.6, 62.5, -24 ], 0.9, 0.9, 'scaleDark');	# brow ridge
	chain([ [ $s * 3, 62, -21 ], [ $s * 5, 64.5, -15 ], [ $s * 6, 64, -9 ], [ $s * 5.5, 62, -5 ] ], [ 1.4, 1.1, 0.7, 0.4 ],
		sub { $_[2] > -12 ? 'horn' : 'hornDark' });
	cap([ $s * 4, 59, -20 ], [ $s * 6.5, 58, -16 ], 0.9, 0.4, 'hornDark');	# cheek spike
	box($s * 2, 57, -34, $s * 2, 57, -34, 'tooth');
	box($s * 2.4, 57, -30, $s * 2.4, 57, -30, 'tooth');
	box($s * 2.8, 57, -27, $s * 2.8, 57, -27, 'tooth');
	cap([ $s * 1, 61, -35 ], [ $s * 1, 61, -35 ], 0.5, 0.5, 'scaleDark');	# nostril
});
cap([ 0, 62, -31 ], [ 0, 64, -29 ], 0.8, 0.4, 'horn');	# snout horn

# ---- Jaw: lower jaw, lower teeth, frost glow on the tongue.
part('Jaw', 'Head', [ 0, 57, -21 ], 'Jaw open');
masked(sub { $_[1] <= 56 }, sub {
	cap([ 0, 56, -22 ], [ 0, 55.5, -34 ], 2.8, 1.8, sub { $_[1] <= 54 ? 'belly' : 'scale' });
});
both(sub {
	my $s = shift;
	box($s * 1.8, 56, $_, $s * 1.8, 56, $_, 'tooth') for (-32, -29, -26);
});
painting(sub { box(-1, 56, -33, 1, 56, -23, 'iceGlow') });

# ---- Wings: arm bone to the wrist, then the outer fingers and membrane.
mirror(sub {
	part(side('Wing'), 'Body', [ $S * 7, 38, -6 ], 'Wing shoulder: fold / beat');
	masked(sub { abs($_[0]) >= 9 }, sub {
		prism('z', [ map { [ $S * $_->[0], $_->[1] ] } [ 7, 38 ], [ 24, 50 ], [ 27, 24 ], [ 10, 25 ] ], -1, 0, sub {
			my ($x, $y) = @_;
			return abs($x) < 15 ? q(membraneDark) : q(membrane);
		});
	});
	chain([ [ $S * 7, 38, -6 ], [ $S * 15, 46, -4 ], [ $S * 24, 50, -1 ] ], [ 2.6, 2, 1.6 ], 'scale');
	VoxLib::outline(side('Wing'), 'membraneEdge', 'y');
	cap([ $S * 24, 50, -1 ], [ $S * 25, 54, -3 ], 1, 0.4, 'claw');	# thumb claw

	part(side('WingTip'), side('Wing'), [ $S * 24, 50, -1 ], 'Wing wrist: spread / fold');
	prism('z', [ map { [ $S * $_->[0], $_->[1] ] } [ 24, 50 ], [ 48, 44 ], [ 44, 37 ], [ 42, 30 ], [ 36, 27 ], [ 32, 22 ], [ 28, 24 ], [ 26, 26 ] ], 0, 1, sub {
		my ($x, $y) = @_;
		return q(membrane);
	});
	VoxLib::outline(side('WingTip'), 'membraneEdge', 'x', 'y');
	for my $f ([ 48, 44 ], [ 42, 30 ], [ 32, 22 ]) {
		cap([ $S * 24, 50, -0.5 ], [ $S * $f->[0], $f->[1], 0.5 ], 1.3, 0.6, 'scaleDark');
	}
	cap([ $S * 48, 44, 0.5 ], [ $S * 51, 45, 1 ], 0.6, 0.3, 'claw');
});

# ---- Legs: heavy thighs, backward-bent shins, three-toed clawed feet.
mirror(sub {
	part(side('Thigh'), 'Body', [ $S * 7, 26, 7 ], 'Hip');
	cap([ $S * 8, 26, 7 ], [ $S * 10, 15, 2 ], 5, 3.4, $hide);
	ell($S * 9.5, 22, 6, 4.6, 6, 5.5, $hide);

	part(side('Shin'), side('Thigh'), [ $S * 10, 15, 2 ], 'Knee; the foot rides this part');
	cap([ $S * 10, 15, 2 ], [ $S * 10, 5, 8 ], 3, 2.2, 'scale');
	cap([ $S * 10, 5, 8 ], [ $S * 10, 2, 5 ], 2.2, 2, 'scaleDark');
	for my $dx (-2.4, 0, 2.4) {
		cap([ $S * 10 + $dx, 1.5, 6 ], [ $S * 10 + $dx * 1.3, 1, -1 ], 1.3, 1, 'scale');
		cap([ $S * 10 + $dx * 1.3, 1, -1 ], [ $S * 10 + $dx * 1.35, 0, -3 ], 0.8, 0.4, 'claw');
	}
	cap([ $S * 10, 2, 9 ], [ $S * 10, 0, 12 ], 0.8, 0.4, 'claw');	# dewclaw
});

# ---- Tail: three segments, crystal fan at the tip.
part('Tail1', 'Body', [ 0, 30, 14 ], 'Tail base swing');
cap([ 0, 30, 14 ], [ 0, 27, 27 ], 6, 4.6, $tailScales);
spine([ 0, 35, 18 ], 3.5, 2);
spine([ 0, 32, 24 ], 3, 2);

part('Tail2', 'Tail1', [ 0, 27, 27 ], 'Tail swing');
cap([ 0, 27, 27 ], [ 0, 22, 39 ], 4.6, 3.2, $tailScales);
spine([ 0, 30.5, 31 ], 2.6, 2);
spine([ 0, 28, 36 ], 2.2, 2);

part('Tail3', 'Tail2', [ 0, 22, 39 ], 'Tail tip whip');
cap([ 0, 22, 39 ], [ 0, 19, 50 ], 3.2, 1.6, $tailScales);
prism('x', [ [ 47, 20 ], [ 52, 28 ], [ 57, 24 ], [ 58, 19 ], [ 56, 13 ], [ 51, 14 ] ], -1, 1, sub {
	my (undef, $y, $z) = @_;
	return ($z > 53 || $y > 25) ? 'iceGlow' : 'ice';
});
painting(sub { box(-1, 18, 48, 1, 21, 52, 'ice') });

finish();
