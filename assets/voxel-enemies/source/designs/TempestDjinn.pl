# Tempest Djinn: a four-armed storm spirit. Blue-skinned, gold-banded
# muscle above the waist, a crimson sash, and below it a twisting storm
# cloud that narrows to a point above the ground. Lightning topknot, cloud
# beard, glowing eyes, a crackling orb in the upper right hand.
use strict; use warnings;
use VoxLib;

model('TempestDjinn', voxel => 0.2, desc => 'Four-armed storm djinn rising from a lightning-shot cloud vortex');

color(skin => 70, 126, 204);
color(skinDark => 42, 84, 156);
color(skinLight => 120, 170, 232);
color(gold => 238, 188, 72);
color(goldDark => 176, 124, 42);
color(sash => 160, 40, 64);
color(sashDark => 110, 24, 44);
color(cloud => 206, 216, 236);
color(cloudDark => 118, 130, 164);
color(cloudDeep => 74, 82, 116);
color(spark => 176, 232, 255, glow => 1);
color(eye => 255, 250, 206, glow => 1);

my $PI = 3.14159265;
my $muscle = sub {
	my ($x, $y, $z) = @_;
	return 'skinLight' if $z < -5 && VoxLib::cellnoise($x, $y, $z, 3, 1) < 0.15;
	return 'skin';
};
# Storm cloud: swirling bands by angle and height, the odd spark.
my $storm = sub {
	my ($x, $y, $z) = @_;
	return 'spark' if VoxLib::noise($x, $y, $z, 4) < 0.02;
	my $a = atan2($z, $x) / (2 * $PI);
	my $band = ($a * 3 + $y / 9) - int($a * 3 + $y / 9 + 10) + 10;
	return $band < 0.33 ? 'cloud' : ($band < 0.7 ? 'cloudDark' : 'cloudDeep');
};
# A twisting vortex from y0 down to y1, radius r0 to r1, drifting back.
sub vortex {
	my ($y0, $y1, $r0, $r1, $z0, $z1) = @_;
	for (my $y = $y0; $y >= $y1; $y -= 1.5) {
		my $t = ($y0 - $y) / ($y0 - $y1);
		my $r = $r0 + ($r1 - $r0) * $t;
		my $z = $z0 + ($z1 - $z0) * $t * $t;
		ell(0, $y, $z, $r, 1.6, $r, $storm);
		my $a = $y * 0.35;	# helical ridge
		ell($r * 0.95 * cos($a), $y, $z + $r * 0.95 * sin($a), 1.6, 1.8, 1.6, 'cloud');
	}
}

# ---- Torso (root): chest, abs, gold collar, sash.
part('Torso', undef, [ 0, 46, 0 ], 'Root body: hover drift');
ell(0, 54, 0, 9.5, 7.5, 6, $muscle);
cap([ 0, 45, 0 ], [ 0, 51, 0 ], 6, 7.5, $muscle);
painting(sub {
	box(-1, 44, -8, 1, 58, -5, 'skinDark');	# centre line
	box(-6, 52, -9, 6, 52, -5, 'skinDark');	# under the pecs
	box(-4, 48, -9, 4, 48, -5, 'skinDark');
});
cyl('y', 0, 0, 5.4, 59, 60, 'gold', inner => 3.5);
cyl('y', 0, 0, 7, 42, 44, sub { $_[1] == 43 ? 'sashDark' : 'sash' });
ell(0, 43, -7, 1.8, 1.8, 1, 'gold');	# sash knot
cap([ 1, 42, -7 ], [ 3, 34, -7 ], 1.2, 0.8, 'sash');

# ---- Vortex: the storm below the sash.
part('Vortex', 'Torso', [ 0, 42, 0 ], 'Vortex sway');
vortex(41, 24, 7.5, 4.4, 0, 3);

part('VortexTip', 'Vortex', [ 0, 24, 3 ], 'Vortex tip whip');
vortex(23, 4, 4.2, 0.8, 3, 9);
ell(0, 3, 9, 1.2, 1.2, 1.2, 'spark');
chain([ [ 1, 14, 6 ], [ 3, 10, 7 ], [ 1, 7, 8 ], [ 2, 3, 9 ] ], 0.55, 'spark');

# ---- Head: bald, pointed ears, cloud beard, lightning topknot, circlet.
part('Head', 'Torso', [ 0, 60, 0 ], 'Neck');
ell(0, 65, -0.5, 4.6, 5.2, 4.6, 'skin');
both(sub {
	my $s = shift;
	box($s * 1, 66, -5, $s * 3, 66, -5, 'eye');
	box($s * 1, 67, -5, $s * 3.5, 68, -4, 'skinDark');	# brows
	cap([ $s * 4.4, 66, 0 ], [ $s * 7, 68.5, 1.5 ], 1.2, 0.4, 'skin');	# ears
	ell($s * 4.6, 64, 0, 0.7, 0.7, 0.7, 'gold');	# earrings
});
painting(sub { box(-5, 68, -5, 5, 68, 4, 'gold') });
ell(0, 68, -5, 0.8, 0.8, 0.6, 'spark');	# circlet gem
masked(sub { $_[1] <= 63 && $_[2] <= -1 }, sub { ell(0, 62, -2.5, 4.4, 4, 3.6, $storm) });
cap([ 0, 60, -5 ], [ 0, 55, -7 ], 1.8, 0.6, 'cloud');	# beard point
chain([ [ 0, 69, 1 ], [ 1, 73, 3 ], [ -1, 76, 5 ], [ 1, 80, 8 ] ], [ 1.9, 1.4, 1, 0.5 ], 'spark');
cyl('y', 0, 1, 1.6, 69, 70, 'gold');

# ---- Upper arms: the big pair, gold armbands and bracers.
mirror(sub {
	part(side('UpperArm'), 'Torso', [ $S * 10, 57, 0 ], 'Upper shoulder');
	ell($S * 10.5, 57, 0, 4.2, 4.2, 4.2, $muscle);
	cap([ $S * 11, 56, 0 ], [ $S * 17, 49, -2 ], 3.6, 3.1, $muscle);
	painting(sub { ell($S * 14.5, 52, -1.2, 4, 1.2, 4, 'gold') });

	part(side('Forearm'), side('UpperArm'), [ $S * 17, 49, -2 ], 'Upper elbow');
	cap([ $S * 17, 49, -2 ], [ $S * 20, 43, -8 ], 3, 2.8, $muscle);
	cap([ $S * 19, 45, -6 ], [ $S * 20, 43.5, -8 ], 3.3, 3.3, 'gold');
	ell($S * 20.5, 41.5, -10, 3, 3, 3, 'skin');
});
use_part('RightForearm');
ell(21, 41, -15, 2.6, 2.6, 2.6, 'spark');	# storm orb in the right hand
for my $k (0 .. 5) {
	my $a = $k * $PI / 3;
	cap([ 21, 41, -15 ], [ 21 + 4.5 * cos($a), 41 + 4.5 * sin($a), -15 + ($k % 2 ? 1 : -1) ], 0.55, 0.5, 'spark');
}

# ---- Lower arms: the smaller pair under the ribs.
mirror(sub {
	part(side('LowerArm'), 'Torso', [ $S * 7.5, 49, 0 ], 'Lower shoulder');
	cap([ $S * 7.5, 49, 0 ], [ $S * 13, 42, 2 ], 2.6, 2.3, $muscle);

	part(side('LowerForearm'), side('LowerArm'), [ $S * 13, 42, 2 ], 'Lower elbow');
	cap([ $S * 13, 42, 2 ], [ $S * 12, 37, -4 ], 2.2, 2.2, $muscle);
	cyl('y', $S * 12.3, -3, 2.6, 37.5, 38.5, 'goldDark');
	ell($S * 12, 35.5, -5.5, 2.3, 2.3, 2.3, 'skin');
});

finish();
