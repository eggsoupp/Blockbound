# The Starfall Merchant: a tall hooded wanderer in purple-black robes, eyes
# glowing out of the hood's shadow, a veil over the rest. A crooked staff
# with a star lantern in the right hand, a floating star orb over the left,
# three rune stones circling him.
#
# Rig (pivots in voxel index space; Body is the root, at the hips):
#   Body (robe) -> Torso -> Head
#                        -> RightArm -> Staff -> Lantern
#                        -> LeftArm  -> Orb
#               -> Runes (orbit)
use strict; use warnings;
use VoxLib; use DecorKit; use VillageKit;

my $m = asset('Merchant', sub {
	my $robe = tex('mystic');
	my $void = tex('void');
	my $vio = tex('violet');
	my $gold = tex('gold');
	my $dgold = tex('gold', 0.72);
	my $thread = solid(thread => 214, 176, 92);
	my $leather = tex('leather', 0.75);
	my $ebony = tex('ebony');
	my $iron = tex('iron_dark');
	my $star = tex('starglow');
	my $eye = tex('eyeglow');
	my $sgold = tex('stargold');
	my $stone = tex('stone', 0.8);

	# ------------------------------------------------------------ Body: robe
	for my $y (0 .. 13) {
		disc(0, 0, 7.4 - $y * 0.21, 5.8 - $y * 0.14, $y, $y, $robe);
	}
	painting(sub {
		# Hem: dark gold band under a gold line.
		box(-9, 0, -9, 8, 0, 8, $dgold);
		box(-9, 1, -9, 8, 1, 8, $gold);
		# Front opening: violet underrobe edged in gold.
		box(-2, 2, -9, 1, 13, -1, $vio);
		box(-3, 2, -9, -3, 13, -1, $gold);
		box(2, 2, -9, 2, 13, -1, $gold);
		# Embroidered stars, sparse.
		box(-9, 3, -9, 8, 11, 8, sub { ragged($_[0], $_[1], $_[2], 9) < 0.035 ? $thread : undef });
		# Belt.
		box(-9, 12, -9, 8, 13, 8, $leather);
	});
	# Tattered hem: notches cut out of the bottom rim.
	cutting(sub {
		for my $x (-8 .. 7) {
			for my $z (-7 .. 6) {
				next unless ragged($x, 0, $z, 3) < 0.22;
				box($x, 0, $z, $x, ragged($x, 1, $z, 4) < 0.5 ? 0 : 1, $z, 'x');
			}
		}
	});
	# Buckle, pouches, vials.
	box(-2, 12, -6, 1, 13, -5, $gold);
	box(-1, 12, -6, 0, 13, -6, $star);
	box(4, 8, -2, 6, 11, 1, $leather);
	box(4, 11, -2, 6, 11, 1, tex('leather', 0.6));
	box(5, 9, -3, 5, 9, -3, $gold);
	box(-7, 8, -1, -5, 11, 2, $leather);
	for my $v ([ -5, -3 ], [ -3, -4 ]) {
		my ($x, $z) = @$v;
		box($x, 8, $z, $x, 10, $z, $star);
		box($x, 11, $z, $x, 11, $z, $gold);
	}

	# ------------------------------------------------------------ Torso
	part('Torso', 'Body', [ -0.5, 14, -0.5 ]);
	for my $y (14 .. 21) {
		disc(0, 0, 4.6 + ($y - 14) * 0.12, 3.5, $y, $y, $robe);
	}
	painting(sub {
		# V neck: violet, gold edged.
		for my $y (15 .. 21) {
			my $w = int(($y - 14) / 2);
			box(-1 - $w, $y, -9, $w, $y, -1, $vio);
			box(-2 - $w, $y, -9, -2 - $w, $y, -1, $gold);
			box(1 + $w, $y, -9, 1 + $w, $y, -1, $gold);
		}
	});
	# Amulet on a chain.
	for my $y (17 .. 20) { box(-3 + int((20 - $y) / 2), $y, -5, -3 + int((20 - $y) / 2), $y, -5, $gold); box(2 - int((20 - $y) / 2), $y, -5, 2 - int((20 - $y) / 2), $y, -5, $gold) }
	box(-2, 15, -5, 1, 17, -5, $gold);
	box(-1, 15, -6, 0, 16, -6, $star);
	# Mantle over the shoulders, tattered at the back.
	for my $y (18 .. 22) {
		disc(0, 0.5, 7.4 - ($y - 18) * 0.55, 5 - ($y - 18) * 0.25, $y, $y, $void);
	}
	painting(sub { box(-9, 18, -9, 8, 18, 8, $gold) });
	cutting(sub {
		for my $x (-8 .. 7) { box($x, 18, 1, $x, 18, 6, 'x') if ragged($x, 18, 0, 6) < 0.35 }
	});
	# High collar behind the head.
	box(-4, 21, 2, 3, 24, 3, $void);
	box(-4, 25, 2, 3, 25, 3, $gold);

	# ------------------------------------------------------------ Head: hood
	part('Head', 'Torso', [ -0.5, 22, -0.5 ]);
	# Just the eyes and the brow rune: a little Neon on the merchant.
	neon('Head');
	ell(-0.5, 26.5, 0, 4.6, 4.6, 4.8, $robe);
	cutting(sub { box(-3, 23, -7, 2, 28, -2, 'x') });
	# Shadow inside the hood; a veil over the lower face.
	box(-3, 23, -2, 2, 28, -1, $void);
	box(-3, 23, -3, 2, 25, -3, $vio);
	box(-3, 25, -3, 2, 25, -3, $gold);
	# The eyes.
	box(-3, 27, -2, -2, 27, -2, $eye);
	box(1, 27, -2, 2, 27, -2, $eye);
	# Brim: the hood edge overhangs the face, trimmed in gold.
	box(-4, 29, -6, 3, 29, -4, $robe);
	box(-4, 29, -6, 3, 29, -6, $gold);
	box(-4, 23, -5, -4, 28, -4, $robe);
	box(3, 23, -5, 3, 28, -4, $robe);
	# A star rune on the brow.
	box(-1, 30, -5, 0, 31, -5, $star);
	# The long hood tip, drooping back, with a gold charm.
	cap([ -0.5, 30, 1 ], [ -0.5, 33, 4 ], 2.3, 1.6, $robe);
	cap([ -0.5, 33, 4 ], [ -0.5, 32, 8 ], 1.6, 0.9, $robe);
	box(-1, 30, 9, 0, 31, 9, $gold);

	# ------------------------------------------------------------ Right arm + staff
	part('RightArm', 'Torso', [ 5.5, 20.5, -0.5 ]);
	cap([ 5.5, 20, -0.5 ], [ 7.5, 14, -2 ], 2.0, 3.0, $robe);
	cap([ 7.4, 13.8, -2 ], [ 7.6, 13, -2.2 ], 2.6, 2.6, $dgold);
	ell(7.5, 12, -2.5, 1.5, 1.4, 1.5, $void);

	part('Staff', 'RightArm', [ 7.5, 12, -2.5 ]);
	cyl('y', 7.5, -2.5, 1.1, 0, 38, $ebony);
	for my $k ([ 9, 6 ], [ 6, 17 ], [ 9, 29 ]) { box($k->[0], $k->[1], -3, $k->[0], $k->[1] + 1, -3, $ebony) }
	for my $y (24, 34) { cyl('y', 7.5, -2.5, 1.6, $y, $y + 1, $gold) }
	box(7, 25, -4, 8, 25, -4, $star);
	chain([ [ 7.5, 38, -2.5 ], [ 9, 41, -2.5 ], [ 12, 42, -2.5 ], [ 14.5, 40, -2.5 ] ], [ 1.1, 1.1, 1.0, 0.9 ], $ebony);

	# Hangs off the crook, out to his right, so it never hides the face.
	part('Lantern', 'Staff', [ 14.5, 39.5, -2.5 ]);
	neon('Lantern');
	box(14, 35, -3, 14, 38, -3, $iron);
	box(12, 34, -5, 17, 34, 0, $iron);
	box(13, 35, -4, 16, 35, -1, $iron);
	box(12, 28, -5, 17, 28, 0, $iron);
	box(13, 27, -4, 16, 27, -1, $iron);
	for my $x (12, 17) { for my $z (-5, 0) { box($x, 29, $z, $x, 33, $z, $iron) } }
	box(13, 29, -4, 16, 33, -1, $star);
	box(14, 30, -5, 15, 32, -5, $sgold);
	box(14, 30, 0, 15, 32, 0, $sgold);
	glowlight(3.75, 7.8, -0.5, 12, 'b48cff');

	# ------------------------------------------------------------ Left arm + orb
	part('LeftArm', 'Torso', [ -6.5, 20.5, -0.5 ]);
	chain([ [ -6.5, 20, -0.5 ], [ -8, 15.5, -1.5 ], [ -6, 13, -5.5 ] ], [ 2.0, 2.4, 3.0 ], $robe);
	cap([ -6.1, 13.1, -5.6 ], [ -5.8, 12.9, -6.3 ], 2.6, 2.6, $dgold);
	ell(-5.5, 12.8, -7, 1.5, 1.2, 1.6, $void);
	box(-7, 13, -8, -7, 13, -8, $gold);

	part('Orb', 'LeftArm', [ -5.5, 16.5, -7.5 ]);
	ell(-5.5, 16.5, -7.5, 1.9, 1.9, 1.9, $star);
	box(-6, 16, -10, -5, 17, -10, $eye);
	for my $s ([ -9, 18, -8 ], [ -3, 15, -6 ], [ -5, 20, -9 ], [ -7, 14, -10 ]) { box(@$s, @$s, $sgold) }
	glowlight(-1.25, 4.2, -1.75, 8, 'c8a8ff');

	# ------------------------------------------------------------ Runes
	part('Runes', 'Body', [ -0.5, 24, -0.5 ]);
	for my $deg (100, 220, 340) {
		my $a = $deg * 3.14159265 / 180;
		my ($cx, $cz) = (-0.5 + 11 * cos($a), -0.5 + 11 * sin($a));
		my ($x, $z) = (int($cx + ($cx < 0 ? -0.5 : 0.5)), int($cz + ($cz < 0 ? -0.5 : 0.5)));
		box($x - 1, 23, $z - 1, $x + 1, 26, $z + 1, $stone);
		box($x - 1, 26, $z - 1, $x, 26, $z, $stone);
		box($x, 24, $z - 2, $x, 25, $z + 2, $star);
		box($x - 2, 24, $z, $x + 2, 25, $z, $star);
	}
});
$m->{joints}{Body}{pivot} = [ -0.5, 12, -0.5 ];
1;
