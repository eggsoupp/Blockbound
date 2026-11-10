# Ashen Lich: a hovering skeletal sorcerer-king. Tattered robe skirt, bare
# ribcage around a soul fire, high collar, bone crown, spiked pauldrons and a
# caged soul-gem staff in the right hand.
use strict; use warnings;
use VoxLib;
use POSIX qw(floor);

model('AshenLich', voxel => 0.2, desc => 'Hovering skeletal sorcerer-king with a soul-fire ribcage and gem staff');

color(robeDark => 38, 30, 46);
color(robeMid => 64, 48, 78);
color(robeIn => 20, 16, 26);
color(gold => 204, 166, 72);
color(goldDark => 138, 102, 42);
color(bone => 224, 216, 194);
color(boneShade => 170, 160, 136);
color(claw => 68, 58, 70);
color(soul => 130, 248, 255, glow => 1);
color(soulDeep => 40, 168, 232, glow => 1);
color(gem => 190, 96, 255, glow => 1);
color(wood => 66, 48, 40);
color(metal => 76, 74, 90);
color(metalDark => 46, 44, 58);

# ---- Robe: frustum skirt, pointed tatters at the hem, gold trim, folds.
part('Robe', undef, [ 0, 20, 0 ], 'Root body: floating robe skirt');
my $hem = sub { my $a = atan2($_[1], $_[0]); 2 + 5 * abs(sin(5 * $a)) };
my $robeColour = sub {
	my ($x, $y, $z) = @_;
	my $h = $hem->($x, $z);
	return 'gold' if $y < $h + 1.6;
	return 'gold' if $y >= 32;	# waist sash
	my $a = atan2($z, $x);
	return sin($a * 7 + $y * 0.08) > 0.3 ? 'robeMid' : 'robeDark';
};
for my $y (2 .. 34) {
	my $f = ($y - 2) / 32;
	my ($rx, $rz) = (13 - 6.2 * $f, 11 - 5 * $f);
	for my $x (-14 .. 14) {
		for my $z (-12 .. 12) {
			my $d = ($x / $rx)**2 + ($z / $rz)**2;
			next if $d > 1;
			next if $y < $hem->($x, $z);
			VoxLib::setv($x, $y, $z, $d < 0.55 ? 'robeIn' : $robeColour);
		}
	}
}
# sash buckle
box(-1, 32, -7, 1, 34, -7, 'goldDark');

# ---- Torso: spine, ribs around a soul fire, collar bones, mantle, collar,
# spiked pauldrons.
part('Torso', 'Robe', [ 0, 34, 0 ], 'Waist bend / chest');
cap([ 0, 33, 3 ], [ 0, 52, 3 ], 1.3, 1.2, 'bone');
ell(0, 42, -1, 5, 5, 3.6, 'soulDeep');
ell(0, 42, -1, 3.4, 3.6, 2.6, 'soul');
for my $ry (36, 39, 42, 45) {
	my $rx = 7.6 - abs($ry - 42) * 0.32;
	my $rz = 5.4 - abs($ry - 42) * 0.2;
	for my $y ($ry, $ry + 1) {
		for my $x (-9 .. 9) {
			for my $z (-8 .. 6) {
				my $d = ($x / $rx)**2 + (($z + 1) / $rz)**2;
				VoxLib::setv($x, $y, $z, $y == $ry ? 'bone' : 'boneShade') if $d >= 0.62 && $d <= 1.0;
			}
		}
	}
}
box(0, 36, -7, 0, 47, -6, 'bone');	# sternum
mirror(sub { cap([ 0, 48, -3 ], [ $S * 9, 49, -1 ], 1, 0.9, 'bone') });
# mantle: a shell down the back and over the shoulders
for my $y (34 .. 50) {
	for my $x (-10 .. 10) {
		for my $z (0 .. 8) {
			my $d = ($x / 9.5)**2 + (($z + 1) / 6.5)**2;
			VoxLib::setv($x, $y, $z, (sin($x * 0.9) > 0.4 ? 'robeMid' : 'robeDark')) if $d >= 0.66 && $d <= 1.05;
		}
	}
}
mirror(sub { ell($S * 7, 49, 0.5, 5, 2.6, 5, 'robeMid') });
# high collar behind the head
for my $y (48 .. 59) {
	my $r = 6.4 + ($y - 48) * 0.5;
	for my $x (-13 .. 13) {
		for my $z (-4 .. 13) {
			my $d = sqrt($x * $x + ($z - 0.5)**2);
			next if $d > $r || $d < $r - 1.7 || $z < 0.5 - ($y - 48) * 0.1;
			VoxLib::setv($x, $y, $z, $y >= 58 ? 'gold' : ($d > $r - 0.9 ? 'robeMid' : 'robeIn'));
		}
	}
}
mirror(sub {
	ell($S * 10.5, 49.5, 0, 4.6, 3, 4.6, sub { $_[1] >= 51 ? 'metal' : 'metalDark' });
	ell($S * 10.5, 47, 0, 4.9, 0.8, 4.9, 'gold');
	cap([ $S * 10.5, 51, 0.5 ], [ $S * 13.5, 59, 1.5 ], 1.5, 0.45, 'bone');
	cap([ $S * 12, 50, -2 ], [ $S * 17, 55, -3 ], 1.1, 0.4, 'boneShade');
});

# ---- Head: neck, skull, sockets with soul eyes, teeth, crown.
part('Head', 'Torso', [ 0, 51, 0.5 ], 'Neck');
cap([ 0, 49, 1.5 ], [ 0, 53.5, 0.5 ], 1.3, 1.2, 'boneShade');
ell(0, 57, -1, 5, 5.2, 5.4, sub { $_[1] <= 54 ? 'boneShade' : 'bone' });
cap([ -3.5, 59.2, -5.3 ], [ 3.5, 59.2, -5.3 ], 0.9, 0.9, 'bone');
cutting(sub {
	both(sub { my $s = shift; ell($s * 2, 57, -6, 1.5, 1.4, 2.2) });
	box(0, 54, -7, 0, 55, -4);
});
both(sub { my $s = shift; box($s * 2, 57, -5, $s * 2, 57, -4, 'soul') });
box(0, 54, -4, 0, 55, -4, 'robeIn');
box($_, 52, -4, $_, 53, -4, 'bone') for (-3, -1, 1, 3);
cyl('y', 0, -1, 5.7, 61, 62, sub { $_[1] == 61 ? 'goldDark' : 'gold' }, inner => 4.3);
for my $k (0 .. 6) {
	my $a = (-90 + ($k - 3) * 38) * 3.14159265 / 180;
	my $h = 8.5 - abs($k - 3) * 1.3;
	cap([ 5.2 * cos($a), 62, -1 + 5.2 * sin($a) ], [ 6 * cos($a), 62 + $h, -1 + 6 * sin($a) ], 1, 0.4, 'gold');
}
ell(0, 62, -6.6, 1, 1, 0.8, 'gem');

part('Jaw', 'Head', [ 0, 53, 1 ], 'Jaw hinge');
masked(sub { $_[1] <= 51 }, sub { ell(0, 51, -1.4, 3.7, 2.4, 3.8, sub { $_[1] <= 49 ? 'boneShade' : 'bone' }) });
box($_, 52, -4, $_, 52, -4, 'bone') for (-2, 0, 2);

# ---- Arms: skeletal, in bell sleeves; claws. Right hand holds the staff.
mirror(sub {
	part(side('UpperArm'), 'Torso', [ $S * 10, 47, 0 ], 'Shoulder');
	cap([ $S * 10, 47, 0 ], [ $S * 14, 38, -1 ], 1.4, 1.2, 'bone');
	cap([ $S * 10.5, 48, 0 ], [ $S * 14.6, 37, -1.2 ], 3.1, 4.6,
		sub { $_[1] <= 38 ? 'gold' : (sin($_[0] * 1.3 + $_[2]) > 0.2 ? 'robeMid' : 'robeDark') }, flat => 1);
	cutting(sub { cap([ $S * 13.9, 40, -1 ], [ $S * 14.7, 36, -1.3 ], 2.6, 3.6, '', flat => 1) });

	part(side('LowerArm'), side('UpperArm'), [ $S * 14, 38, -1 ], 'Elbow; hand and claws ride this part');
	cap([ $S * 13.5, 38, -1 ], [ $S * 13.5, 33, -8 ], 0.8, 0.7, 'bone');
	cap([ $S * 14.6, 38, -1 ], [ $S * 14.6, 33, -8 ], 0.8, 0.7, 'boneShade');
	ell($S * 14, 32.5, -9.3, 1.9, 1.3, 1.9, 'bone');
	for my $f (0 .. 3) {
		my $bx = $S * (14 + ($f - 1.5) * 1.15);
		chain([ [ $bx, 32.6, -10.6 ], [ $bx, 31.6, -12.4 ], [ $bx, 29.6, -12.8 ] ], [ 0.65, 0.6, 0.5 ],
			sub { $_[1] <= 30 ? 'claw' : 'bone' });
	}
	cap([ $S * 12.4, 32.4, -8.6 ], [ $S * 11.4, 31, -11 ], 0.6, 0.5, 'bone');	# thumb
});

# ---- Staff: shaft, gold bands, ferrule, caged soul gem.
part('Staff', 'RightLowerArm', [ 14, 32.5, -10 ], 'Grip in the right hand');
cyl('y', 14, -10, 1.0, 5, 63, 'wood');
cyl('y', 14, -10, 1.6, $_, $_, 'gold') for (14, 31, 34, 50);
cap([ 14, 5, -10 ], [ 14, 1, -10 ], 1, 0.3, 'gold');
for my $d ([ 1, 0 ], [ -1, 0 ], [ 0, 1 ], [ 0, -1 ]) {
	chain([ [ 14, 62, -10 ], [ 14 + 3.2 * $d->[0], 66, -10 + 3.2 * $d->[1] ], [ 14 + 2.8 * $d->[0], 71, -10 + 2.8 * $d->[1] ], [ 14 + 0.8 * $d->[0], 74, -10 + 0.8 * $d->[1] ] ],
		[ 0.8, 0.7, 0.65, 0.6 ], 'gold');
}
ell(14, 68.5, -10, 2.1, 3.1, 2.1, 'gem');
cyl('y', 14, -10, 1.8, 62, 63, 'goldDark');
cap([ 14, 74, -10 ], [ 14, 77.5, -10 ], 0.9, 0.3, 'gold');

finish();
