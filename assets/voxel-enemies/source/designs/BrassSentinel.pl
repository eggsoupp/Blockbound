# Brass Sentinel: a boiler-chested clockwork colossus. Furnace core behind a
# grille, cyclops lens, twin smokestacks, a spinning back gear, a piston
# hammer fist on the right and a gear-crest tower shield on the left.
use strict; use warnings;
use VoxLib;

model('BrassSentinel', voxel => 0.2, desc => 'Clockwork colossus with a furnace core, hammer fist and tower shield');

color(brass => 192, 142, 62);
color(brassDark => 128, 88, 40);
color(brassLight => 236, 196, 108);
color(iron => 72, 74, 84);
color(ironDark => 40, 42, 52);
color(core => 255, 138, 40, glow => 1);
color(coreHot => 255, 224, 130, glow => 1);
color(lens => 100, 226, 255, glow => 1);

# ---- Pelvis (root): hip block, belt, gear buckle, front plates.
part('Pelvis', undef, [ 0, 30, 0 ], 'Root body');
box(-7, 26, -4, 7, 32, 4, 'iron');
box(-8, 31, -5, 8, 32, 5, 'brassDark');
cyl('z', 0, 29, 2.6, -6, -5, 'brass');
cyl('z', 0, 29, 1, -7, -7, 'core');
both(sub { my $s = shift; box($s * 2, 23, -6, $s * 7, 30, -5, sub { $_[1] == 23 ? 'brassDark' : 'brass' }) });

# ---- Torso: boiler barrel, grille over the furnace core, smokestacks.
part('Torso', 'Pelvis', [ 0, 33, 0 ], 'Waist twist / lean');
masked(sub { $_[1] >= 33 && $_[1] <= 55 }, sub {
	ell(0, 44, 0, 12, 12, 9, sub {
		my ($x, $y) = @_;
		return 'brassLight' if $y == 52 && $x % 3 == 0;
		return 'brassDark' if $y == 36 || $y == 37 || $y == 52 || $y == 53;
		return 'brass';
	});
});
cutting(sub { box(-4, 38, -10, 4, 48, -5) });
ell(0, 43, -4.5, 4.5, 5, 2.5, 'core');
ell(0, 43, -5.5, 2.5, 3, 1.5, 'coreHot');
box($_, 38, -8, $_, 48, -8, 'ironDark') for (-4, -2, 0, 2, 4);
box(-5, 37, -8, 5, 37, -7, 'brassLight');
box(-5, 49, -8, 5, 49, -7, 'brassLight');
box(-5, 37, -8, -5, 49, -7, 'brassLight');
box(5, 37, -8, 5, 49, -7, 'brassLight');
cyl('y', 0, -1, 4, 54, 56, 'ironDark');
both(sub {
	my $s = shift;
	cyl('y', $s * 8, 7, 2, 46, 64, 'iron');
	cyl('y', $s * 8, 7, 2.6, 63, 64, 'brassDark');
	cyl('y', $s * 8, 7, 2.6, 56, 56, 'brassDark');
});
cutting(sub { both(sub { my $s = shift; cyl('y', $s * 8, 7, 1, 62, 64) }) });
both(sub { my $s = shift; cyl('y', $s * 8, 7, 1, 61, 61, 'ironDark') });

# ---- Back gear: spins about Z.
part('BackGear', 'Torso', [ 0, 42, 10.5 ], 'Spins about its axle (Z)');
cyl('z', 0, 42, 7.5, 10, 11, 'brass');
for my $k (0 .. 11) {
	my $a = $k * 3.14159265 / 6;
	cap([ 7 * cos($a), 42 + 7 * sin($a), 10.5 ], [ 9 * cos($a), 42 + 9 * sin($a), 10.5 ], 1.1, 1, 'brassDark', flat => 1);
}
cutting(sub { for my $k (0 .. 3) { my $a = $k * 3.14159265 / 2 + 0.785; cyl('z', 4.4 * cos($a), 42 + 4.4 * sin($a), 1.7, 10, 11) } });
cyl('z', 0, 42, 2.5, 11, 12, 'iron');
cyl('z', 0, 42, 1, 12, 12, 'core');

# ---- Head: dome, cyclops lens, brow plate, ear bolts, antenna.
part('Head', 'Torso', [ 0, 55, -1 ], 'Neck');
masked(sub { $_[1] >= 56 }, sub { ell(0, 60.5, -1.5, 5, 5, 5, sub { $_[1] <= 58 ? 'iron' : 'brass' }) });
cyl('z', 0, 60.5, 2.6, -7, -6, 'brassLight');
cyl('z', 0, 60.5, 1.7, -8, -6, 'lens');
box(-4, 63, -7, 4, 64, -5, 'ironDark');
both(sub { my $s = shift; cyl('x', -1.5, 60.5, 1.5, $s * 5, $s * 6, 'brassDark') });
cap([ 2, 64, -1 ], [ 3, 70, 0 ], 0.6, 0.5, 'iron');
ell(3, 71, 0, 1, 1, 1, 'core');

# ---- Arms: domed pauldrons, iron upper arms with pistons.
mirror(sub {
	part(side('UpperArm'), 'Torso', [ $S * 13, 51, 0 ], 'Shoulder');
	cap([ $S * 15, 51, 0 ], [ $S * 17, 39, 0 ], 3.2, 3, 'iron');
	ell($S * 15, 53, 0, 6, 5, 6, sub { $_[1] <= 50 ? 'brassDark' : ($_[1] == 55 && $_[2] % 3 == 0 ? 'brassLight' : 'brass') });
	cap([ $S * 19.5, 48, 2.5 ], [ $S * 19.5, 40, 2.5 ], 0.7, 0.7, 'brassLight');
});

part('RightForearm', 'RightUpperArm', [ 17, 39, 0 ], 'Elbow; the hammer fist rides this part');
ell(17, 39, 0, 3.4, 3.4, 3.4, 'ironDark');
cap([ 17, 38, 0 ], [ 17, 28, -2 ], 4, 5, sub { $_[1] == 34 || $_[1] == 31 ? 'ironDark' : 'brass' });
ell(17, 23, -2, 6, 5, 6, 'iron');
cyl('z', 17 + ($_ - 1.5) * 2.6, 24.5, 1, -8.5, -7, 'brassLight') for 0 .. 3;
cyl('x', -2, 23, 2, 22, 24, 'brassDark');

part('LeftForearm', 'LeftUpperArm', [ -17, 39, 0 ], 'Elbow');
ell(-17, 39, 0, 3.4, 3.4, 3.4, 'ironDark');
cap([ -17, 38, 0 ], [ -17, 29, -2 ], 3.5, 4, sub { $_[1] == 34 ? 'ironDark' : 'brass' });
ell(-17, 26.5, -2.5, 3, 3, 3, 'iron');

part('Shield', 'LeftForearm', [ -17, 31, -3 ], 'Shield brace on the forearm');
box(-19, 28, -7, -17, 33, -3, 'ironDark');
cyl('z', -21, 30, 11, -9, -8, sub { (($_[0] + 21)**2 + ($_[1] - 30)**2) > 90 ? 'brassDark' : 'iron' });
cyl('z', -21, 30, 6.2, -10, -10, 'brass', inner => 5);
ell(-21, 30, -9.5, 3.5, 3.5, 1.5, 'brass');
cyl('z', -21, 30, 1.2, -11, -11, 'core');

# ---- Legs: thigh plate, knee cap, heavy boots.
mirror(sub {
	part(side('Thigh'), 'Pelvis', [ $S * 5, 27, 0 ], 'Hip');
	cap([ $S * 5, 27, 0 ], [ $S * 6, 16, -1 ], 3.6, 3, 'iron');
	masked(sub { $_[2] <= -1 }, sub { ell($S * 6, 22, -1, 4.2, 5, 4.2, 'brass') });

	part(side('Shin'), side('Thigh'), [ $S * 6, 16, -1 ], 'Knee; boot rides this part');
	ell($S * 6, 16, -3, 2.6, 2.6, 2.6, 'brassLight');
	cap([ $S * 6, 16, -1 ], [ $S * 6, 5, 0 ], 3, 3.6, sub { $_[1] == 9 ? 'brassDark' : 'brass' });
	box($S * 6 - 4, 0, -9, $S * 6 + 4, 4, 4, 'iron');
	box($S * 6 - 4, 0, -10, $S * 6 + 4, 3, -8, 'brassDark');
});

finish();
