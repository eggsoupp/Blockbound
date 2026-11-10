# Gloomrider: a horned death knight riding a skeletal warhorse. The steed
# wears iron barding over a ribcage full of pale ghost fire, with a flaming
# mane and tail. The rider carries a tall rune lance and a kite shield.
use strict; use warnings;
use VoxLib;

model('Gloomrider', voxel => 0.2, desc => 'Horned death knight on a ghost-fire skeletal warhorse, with rune lance and kite shield');

color(bone => 224, 216, 192);
color(boneDark => 164, 152, 128);
color(barding => 58, 60, 74);
color(bardingLight => 98, 102, 120);
color(trim => 150, 112, 214);
color(armor => 46, 46, 60);
color(armorLight => 92, 92, 112);
color(cape => 92, 34, 72);
color(capeDark => 56, 20, 46);
color(leather => 84, 56, 42);
color(ghost => 150, 255, 176, glow => 1);
color(ghostDeep => 60, 214, 140, glow => 1);

my $flame = sub { VoxLib::noise($_[0], $_[1], $_[2], 9) < 0.45 ? 'ghostDeep' : 'ghost' };
my $plates = sub {
	my ($x, $y, $z) = @_;
	return 'trim' if $y % 6 == 0;
	return VoxLib::cellnoise($x, $y, $z, 3, 5) < 0.2 ? 'bardingLight' : 'barding';
};
# Flame tongue: a tapered capsule from $a leaning up.
sub tongue { my ($a, $b, $r) = @_; cap($a, $b, $r, 0.4, $flame) }

# ---- Steed (root): ribcage with ghost fire, barding, chest plate,
# saddle. The rider's legs and stirrups belong here too.
part('Steed', undef, [ 0, 30, 0 ], 'Root body: gallop bob');
ell(0, 29, 2, 4.5, 4.5, 12, $flame);
for my $z (-8, -5, -2, 1, 4, 7, 10) {
	cyl('z', 0, 29, 7.2, $z, $z + 1, sub { $_[1] > 25 ? 'bone' : 'boneDark' }, inner => 5.8);
}
box(-1, 27, -10, 1, 22, 12, 'boneDark');	# sternum
masked(sub { $_[1] >= 31 }, sub { ell(0, 30, 2, 8.2, 8, 18, $plates) });
ell(0, 31, -12, 7.5, 7.5, 6, $plates);
ell(0, 31, 14, 7.5, 7, 6.5, $plates);
masked(sub { $_[1] >= 23 && abs($_[0]) >= 6 }, sub { ell(0, 30, 2, 8.5, 9, 17, 'barding') });
painting(sub { box(-9, 23, -20, 9, 24, 20, 'trim') });
box(-4, 38, -4, 4, 39, 5, 'leather');
box(-4, 40, 3, 4, 42, 5, 'leather');	# cantle
mirror(sub {	# rider legs, iron greaves, stirrups
	chain([ [ $S * 4, 41, 0 ], [ $S * 9, 37, -4 ], [ $S * 9.5, 28, -2 ] ], [ 2.6, 2.4, 2.2 ], 'armor');
	ell($S * 9, 37, -5, 2.4, 2.4, 2.4, 'armorLight');
	box($S * 8, 25, -6, $S * 11, 27, 0, 'armor');
	box($S * 8, 24, -5, $S * 11, 24, -1, 'armorLight');
});

# ---- Neck: armoured crinet, ghost-fire mane.
part('SteedNeck', 'Steed', [ 0, 35, -14 ], 'Neck');
chain([ [ 0, 34, -14 ], [ 0, 44, -20 ], [ 0, 50, -22 ] ], [ 4.4, 3.4, 3 ], 'boneDark');
masked(sub { $_[2] >= -21 + (50 - $_[1]) * 0.4 || $_[1] < 40 }, sub {
	chain([ [ 0, 34, -14 ], [ 0, 44, -20 ], [ 0, 50, -22 ] ], [ 4.8, 3.9, 3.4 ], $plates);
});
for my $k (0 .. 6) {
	my $y = 36 + $k * 2.2;
	my $z = -14 - $k * 1.1 + 3.6;
	tongue([ 0, $y, $z ], [ 0, $y + 4 + $k % 2 * 2, $z + 5 ], 1.6);
}

# ---- Head: bone skull under a spiked chanfron, burning eye sockets.
part('SteedHead', 'SteedNeck', [ 0, 50, -22 ], 'Head toss');
cap([ 0, 52, -23 ], [ 0, 47, -34 ], 3.6, 2.3, 'bone');
cap([ 0, 54, -24 ], [ 0, 49, -32 ], 2.4, 1.6, 'barding');
painting(sub { box(-3, 49, -36, 3, 49, -24, 'trim') });
cap([ 0, 54, -26 ], [ 0, 58, -32 ], 1.2, 0.3, 'armorLight');	# brow spike
both(sub {
	my $s = shift;
	ell($s * 3, 51.5, -27, 1.1, 1.1, 1.1, 'ghost');
	cap([ $s * 2, 55, -22 ], [ $s * 2.5, 58, -21 ], 1, 0.4, 'bone');	# ears
	box($s * 1, 46, -34, $s * 2, 46, -30, 'boneDark');	# teeth line
});

# ---- Legs: bone upper and lower legs, iron-shod hooves, fire at the
# fetlocks.
mirror(sub {
	for my $l ([ 'Fore', -12, -13, -12 ], [ 'Hind', 14, 18, 15 ]) {
		my ($n, $z, $zk, $zh) = @$l;
		part(side($n . 'leg'), 'Steed', [ $S * 5, 26, $z ], "$n leg: shoulder/hip");
		cap([ $S * 5, 26, $z ], [ $S * 5, 14, $zk ], 2.6, 1.8, 'bone');
		ell($S * 5, 14, $zk, 2.1, 2.1, 2.1, 'boneDark');
		part(side($n . 'hoof'), side($n . 'leg'), [ $S * 5, 14, $zk ], "$n leg: knee/hock");
		cap([ $S * 5, 14, $zk ], [ $S * 5, 4, $zh ], 1.7, 1.5, 'bone');
		cyl('y', $S * 5, $zh - 0.5, 2.4, 0, 3, 'armor');
		tongue([ $S * 5, 5, $zh ], [ $S * 5, 9, $zh + 3 ], 1.8);
	}
});

# ---- Tail: a streaming ghost flame.
part('SteedTail', 'Steed', [ 0, 33, 19 ], 'Tail sway');
chain([ [ 0, 33, 19 ], [ 0, 30, 25 ], [ 0, 22, 29 ], [ 0, 13, 30 ] ], [ 2.4, 2.6, 2, 0.6 ], $flame);

# ---- Rider: armoured torso, tattered cape.
part('RiderTorso', 'Steed', [ 0, 41, 0 ], 'Rider waist: lean / twist');
ell(0, 43, 0, 5, 3, 4, 'armor');
cap([ 0, 45, 0 ], [ 0, 53, 0 ], 5.2, 6.6, sub {
	my ($x, $y, $z) = @_;
	return 'trim' if $y == 46 || ($z < -4 && abs($x) <= 1 && $y > 47);
	return $y > 50 && $z < -2 ? 'armorLight' : 'armor';
});
prism('x', [ [ 4, 56 ], [ 7, 56 ], [ 15, 38 ], [ 19, 30 ], [ 9, 30 ], [ 4, 44 ] ], -6, 6, sub {
	my ($x, $y, $z) = @_;
	return VoxLib::noise($x, 0, 0, 3) < 0.35 ? 'capeDark' : 'cape';
});
cutting(sub {	# tattered hem
	for my $x (-6 .. 6) { my $n = int(VoxLib::noise($x, 1, 1, 8) * 6); box($x, 30, 9, $x, 30 + $n, 20) }
});

# ---- Head: horned great helm, ghost-lit visor, flame plume.
part('RiderHead', 'RiderTorso', [ 0, 56, 0 ], 'Neck');
ell(0, 60, 0, 4.2, 4.8, 4.2, 'armor');
painting(sub { box(-3, 60, -5, 3, 60, -3, 'ghost') });
painting(sub { box(0, 57, -5, 0, 59, -3, 'ghost') });
painting(sub { box(-5, 63, -5, 5, 63, 5, 'trim') });
both(sub {
	my $s = shift;
	chain([ [ $s * 3, 62, 0 ], [ $s * 7, 65, 1 ], [ $s * 8.5, 71, -1 ], [ $s * 7.5, 74, -3 ] ], [ 1.5, 1.1, 0.7, 0.4 ], sub { $_[1] > 69 ? 'bone' : 'boneDark' });
});
tongue([ 0, 64, 1 ], [ 0, 70, 6 ], 1.8);
tongue([ 0, 64, 3 ], [ 0, 67, 10 ], 1.4);

# ---- Arms: spiked pauldrons, gauntlets.
mirror(sub {
	part(side('UpperArm'), 'RiderTorso', [ $S * 7, 53, 0 ], 'Shoulder');
	cap([ $S * 8, 53, 0 ], [ $S * 9, 46, -2 ], 2.3, 2.1, 'armor');
	ell($S * 8.5, 54.5, 0, 4, 3.4, 4, sub { $_[1] == 54 ? 'trim' : 'armorLight' });
	cap([ $S * 10, 57, 0 ], [ $S * 12, 61, 1 ], 1.2, 0.3, 'boneDark');

	part(side('Forearm'), side('UpperArm'), [ $S * 9, 46, -2 ], 'Elbow');
	cap([ $S * 9, 46, -2 ], [ $S * 9, 43, -8 ], 2.1, 2.5, 'armor');
	ell($S * 9, 42.5, -9, 2, 2, 2, 'armorLight');
});
use_part('LeftForearm');	# kite shield on the outside of the left arm
prism('x', [ [ -14, 52 ], [ 2, 52 ], [ 3, 45 ], [ -5, 31 ], [ -15, 45 ] ], -13, -13, 'trim');
prism('x', [ [ -13, 51 ], [ 1, 51 ], [ 2, 45 ], [ -5, 33 ], [ -14, 45 ] ], -14, -12, sub { $_[1] > 47 ? 'armorLight' : 'armor' });
ell(-14.5, 45, -6, 1.2, 2.6, 2.6, 'ghost');
box(-13, 44, -8, -10, 46, -4, 'leather');

# ---- Lance: held upright in the right fist, tilted forward.
part('Lance', 'RightForearm', [ 9, 42.5, -9 ], 'Lance grip: lower to charge');
my @dir = (0, 8 / sqrt(73), -3 / sqrt(73));
my $at = sub { my $t = shift; [ 9, 42.5 + $dir[1] * $t, -9 + $dir[2] * $t ] };
cap($at->(-9), $at->(4), 1.1, 1.1, 'leather');
cap($at->(4), $at->(9), 1.2, 3.2, 'armorLight', flat => 1);
cap($at->(9), $at->(50), 2.4, 0.4, sub {
	my ($x, $y) = @_;
	return q(ghost) if $y % 9 == 0 && $y < 84;
	return 'armor';
});
my $p = $at->(42);
prism('x', [ [ $p->[2], $p->[1] ], [ $p->[2] + 11, $p->[1] - 1 ], [ $p->[2] + 8, $p->[1] - 3 ], [ $p->[2] + 10, $p->[1] - 6 ], [ $p->[2] + 1.5, $p->[1] - 5 ] ], 9, 9, 'cape');

finish();
