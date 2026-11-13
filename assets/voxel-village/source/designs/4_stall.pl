# The merchant's stall: a dark oak booth under a purple-black striped
# canopy, a draped counter crowded with potions and a crystal ball, shelves
# of jars behind, star lanterns and an eye sign on top. The merchant stands
# at the MerchantSpot anchor, behind the counter.
use strict; use warnings;
use VoxLib; use DecorKit; use VillageKit;

asset('MerchantStall', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.55);
	my $mid = tex('oak_plank', 0.75);
	my $robe = tex('mystic');
	my $void = tex('void');
	my $vio = tex('violet');
	my $gold = tex('gold');
	my $star = tex('starglow');
	my $sgold = tex('stargold');
	my $rune = tex('runeglow');
	my $potion = tex('potion_dim');
	my $iron = tex('iron_dark');
	my $clay = tex('clay');
	my $paper = tex('paper');
	my $red = tex('red_cloth');
	my $blue = tex('blue_cloth');
	my $cob = tex('cobblestone');
	my $herb = tex('moss');
	my $straw = tex('straw');

	# ------------------------------------------------------------ counter
	box(-22, 0, -16, 21, 11, -11, $dark);
	box(-23, 12, -17, 22, 12, -10, $oak);
	# Drape over the front, gold fringe, an eye emblem.
	box(-21, 3, -17, 20, 11, -17, $robe);
	for my $x (-21 .. 20) { box($x, 2, -17, $x, 2, -17, $gold) if $x % 2 == 0 }
	box(-21, 11, -18, 20, 11, -18, $gold);
	box(-4, 6, -18, 3, 6, -18, $gold);
	box(-3, 5, -18, 2, 5, -18, $gold);
	box(-3, 7, -18, 2, 7, -18, $gold);
	box(-5, 6, -18, -5, 6, -18, $gold);
	box(4, 6, -18, 4, 6, -18, $gold);
	box(-1, 5, -18, 0, 7, -18, $star);

	# ------------------------------------------------------------ shelves
	part('Shelves', undef, [ 0, 0, 0 ]);
	box(-22, 0, 15, 21, 36, 16, $mid);
	box(-22, 0, 11, -21, 36, 16, $dark);
	box(20, 0, 11, 21, 36, 16, $dark);
	for my $y (9, 19, 29) { box(-21, $y, 11, 20, $y, 14, $oak) }
	# Jars, pots and bottles along the shelves.
	# Mostly plain glass; one lit jar in a few, so the shelves don't glare.
	my @jar = (tex('glass_vio'), tex('glass_grn'), $star, $clay, tex('glass_blu'), $clay, tex('glass_grn'), tex('glass_vio'));
	for my $row (0 .. 2) {
		my $y = 10 + $row * 10;
		my $i = $row * 3;
		for (my $x = -19; $x <= 16; $x += 5) {
			my $c = $jar[ $i++ % @jar ];
			my $h = 3 + ($x + $row) % 3;
			box($x, $y, 12, $x + 2, $y + $h - 1, 13, $c);
			box($x + 1, $y + $h, 12, $x + 1, $y + $h, 13, $c == $clay ? $clay : solid(cork => 156, 112, 66));
		}
	}
	# A few books on the top shelf's end.
	box(14, 30, 12, 14, 34, 14, $red); box(15, 30, 12, 15, 33, 14, $blue); box(16, 30, 12, 16, 34, 14, tex('green_cloth'));

	# ------------------------------------------------------------ wares
	part('Wares', undef, [ 0, 0, 0 ]);
	hitbox('Wares', 'none');
	# Crystal ball on a gold stand.
	box(-15, 13, -15, -12, 13, -12, $gold);
	box(-14, 14, -14, -13, 14, -13, $gold);
	ell(-13.5, 17, -13.5, 2.4, 2.4, 2.4, $star);
	# Potions.
	for my $p ([ -7, -14, $potion ], [ -4, -12, $rune ], [ 9, -14, $star ]) {
		my ($x, $z, $c) = @$p;
		box($x, 13, $z, $x + 1, 15, $z + 1, $c);
		box($x, 16, $z, $x, 16, $z, $c);
		box($x, 17, $z, $x, 17, $z, solid(cork => 156, 112, 66));
	}
	# A spread scroll and a coin pile.
	box(1, 13, -15, 6, 13, -12, $paper);
	box(1, 13, -16, 6, 13, -16, $straw); box(1, 13, -11, 6, 13, -11, $straw);
	box(2, 14, -14, 4, 14, -14, $void); box(3, 14, -13, 5, 14, -13, $void);
	box(14, 13, -14, 17, 13, -12, $gold); box(15, 14, -13, 16, 14, -13, $gold);

	# ------------------------------------------------------------ frame
	part('Frame', undef, [ 0, 0, 0 ]);
	hitbox('Frame', 'precise');
	for my $x (-25, 22) {
		box($x, 0, -17, $x + 2, 40, -15, $dark);
		box($x, 0, 15, $x + 2, 45, 17, $dark);
		box($x - 1, 0, -18, $x + 3, 1, -14, $cob);
		box($x - 1, 0, 14, $x + 3, 1, 18, $cob);
		box($x, 38, -15, $x + 2, 39, 15, $dark);
	}

	# ------------------------------------------------------------ canopy
	part('Canopy', undef, [ 0, 0, 0 ]);
	hitbox('Canopy', 'box');
	for my $z (-21 .. 18) {
		my $y = 41 + int(($z + 21) * 6 / 39);
		my $c = (int(($z + 21) / 4) % 2) ? $void : $robe;
		box(-27, $y, $z, 26, $y, $z, $c);
		box(-27, $y, $z, -27, $y, $z, $gold);
		box(26, $y, $z, 26, $y, $z, $gold);
	}
	# Valance with gold tassels.
	for my $x (-27 .. 26) {
		my $len = (($x + 27) % 4 < 2) ? 4 : 2;
		box($x, 41 - $len, -21, $x, 40, -21, (int(($x + 27) / 4) % 2) ? $void : $robe);
		box($x, 40 - $len, -21, $x, 40 - $len, -21, $gold) if $len == 4 && ($x + 27) % 4 == 0;
	}
	box(-27, 41, -22, 26, 41, -22, $gold);

	# ------------------------------------------------------------ hanging lanterns and herbs
	part('Hangings', undef, [ 0, 0, 0 ]);
	hitbox('Hangings', 'none');
	neon('Hangings');
	for my $x (-18, 17) {
		box($x, 37, -14, $x, 41, -14, $iron);
		box($x - 2, 31, -16, $x + 2, 31, -12, $iron);
		box($x - 2, 36, -16, $x + 2, 36, -12, $iron);
		box($x - 1, 32, -15, $x + 1, 35, -13, $star);
		box($x - 2, 32, -16, $x - 2, 35, -16, $iron); box($x + 2, 32, -12, $x + 2, 35, -12, $iron);
		box($x + 2, 32, -16, $x + 2, 35, -16, $iron); box($x - 2, 32, -12, $x - 2, 35, -12, $iron);
	}
	glowlight(-4.25, 8.5, -3.5, 12, 'b48cff');
	glowlight(4.5, 8.5, -3.5, 12, 'b48cff');
	for my $x (-9, -2, 6) {
		box($x, 37, -8, $x, 42, -8, $straw);
		box($x - 1, 33, -9, $x + 1, 36, -7, $herb);
	}
	# A string of little gold stars.
	for my $x (-20 .. 19) {
		my $y = 38 - int(abs($x) / 7);
		box($x, $y, -19, $x, $y, -19, $gold) if $x % 3 == 0;
		box($x, $y - 1, -19, $x, $y - 1, -19, $sgold) if $x % 6 == 0;
	}

	# ------------------------------------------------------------ sign
	part('Sign', undef, [ 0, 0, 0 ]);
	hitbox('Sign', 'none');
	box(-12, 42, -21, -11, 47, -20, $dark);
	box(10, 42, -21, 11, 47, -20, $dark);
	box(-14, 47, -21, 13, 56, -20, $dark);
	box(-13, 48, -22, 12, 55, -22, $vio);
	# An eye under a crescent moon.
	for my $x (-7 .. 6) {
		my $h = int(2.6 - abs($x + 0.5) / 3);
		box($x, 51 - $h, -23, $x, 51 - $h, -23, $gold);
		box($x, 51 + $h, -23, $x, 51 + $h, -23, $gold);
	}
	box(-1, 50, -23, 0, 52, -23, $star);
	box(-2, 51, -23, 1, 51, -23, $star);
	box(-1, 51, -23, 0, 51, -23, tex('eyeglow'));
	box(8, 53, -23, 10, 53, -23, $sgold); box(9, 54, -23, 10, 54, -23, $sgold); box(10, 52, -23, 10, 52, -23, $sgold);
	box(-12, 49, -23, -12, 49, -23, $sgold); box(-10, 53, -23, -10, 53, -23, $sgold);

	anchor('MerchantSpot', 0, 0, 0.5);
});
1;
