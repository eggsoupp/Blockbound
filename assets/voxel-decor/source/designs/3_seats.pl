# Seats. Each sets seat(x, y, z, w, d): where the invisible Seat goes, in
# studs, its top at the cushion. A seated player faces +Z (the front).
use strict; use warnings;
use VoxLib; use DecorKit;

sub legs4 {
	my ($x0, $x1, $z0, $z1, $h, $c, $t) = @_;
	$t //= 1;
	for my $x ($x0, $x1 - $t + 1) { for my $z ($z0, $z1 - $t + 1) { box($x, 0, $z, $x + $t - 1, $h, $z + $t - 1, $c) } }
}

piece('WoodenChair', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	legs4(-5, 4, -5, 4, 6, $dark, 2);
	box(-5, 7, -5, 4, 7, 4, $oak);
	box(-5, 8, -5, 4, 8, 4, $oak);
	for my $x (-5, 3) { box($x, 9, -5, $x + 1, 14, -4, $dark) }
	for my $y (10, 13) { box(-3, $y, -5, 2, $y, -5, $oak) }
	box(-5, 15, -5, 4, 15, -4, $dark);
	seat(0, 2.25, 0, 2.4, 2.4);
	surface(2.25);
});

piece('Stool', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	legs4(-4, 3, -4, 3, 5, $dark);
	box(-4, 2, -3, -4, 2, 2, $dark); box(3, 2, -3, 3, 2, 2, $dark);
	cyl('y', -0.5, -0.5, 4.6, 6, 7, $oak);
	seat(0, 2, 0, 2, 2);
	surface(2);
});

piece('WoodenBench', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	for my $x (-7, 5) { box($x, 0, -3, $x + 1, 5, 2, $dark) }
	box(-5, 2, -1, 4, 2, 0, $dark);
	box(-8, 6, -3, 7, 6, 2, $oak);
	seat(0, 1.75, 0, 3.6, 1.4);
	surface(1.75);
});

piece('Throne', sub {
	my $gold = tex('gold');
	my $red = tex('red_cloth');
	box(-7, 0, -7, 6, 1, 6, $gold);
	box(-6, 2, -6, 5, 6, 4, $red);
	box(-6, 7, -5, 5, 7, 5, $red);
	box(-7, 2, -7, 6, 13, -5, $gold);			# back
	box(-5, 4, -4, 4, 11, -4, $red);			# padded back
	for my $x (-7, 5) { box($x, 2, -4, $x + 1, 9, 5, $gold) }	# arms
	for my $x (-7, 5) { box($x, 14, -7, $x + 1, 15, -6, $gold) }
	box(-1, 12, -4, 0, 13, -4, glow(throneGem => 90, 200, 240));
	seat(0, 2, -0.2, 2.6, 2.4);
});

piece('Bed', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-8, 0, -8, 7, 3, 7, $oak);
	box(-7, 4, -7, 6, 5, 6, tex('wool'));
	box(-8, 4, -2, 7, 6, 7, tex('red_cloth'));
	box(-8, 6, -3, 7, 6, -3, tex('wool'));
	box(-5, 6, -7, 4, 7, -4, tex('wool'));
	box(-8, 0, -8, 7, 11, -8, $dark);			# headboard
	box(-8, 0, 7, 7, 5, 7, $dark);				# footboard
	seat(0, 1.6, -0.4, 1.6, 1.6);
});

piece('Armchair', sub {
	my $cloth = tex('green_cloth');
	my $dark = tex('oak_plank', 0.62);
	legs4(-6, 5, -6, 5, 1, $dark, 2);
	box(-6, 2, -6, 5, 6, 5, $cloth);
	box(-6, 7, -6, 5, 15, -3, $cloth);			# back
	for my $x (-6, 4) { box($x, 7, -3, $x + 1, 10, 5, $cloth) }	# arms
	box(-4, 7, -2, 3, 7, 5, tex('wool'));			# cushion
	seat(0, 2, 0.3, 2.4, 2.4);
});

piece('Sofa', sub {
	my $cloth = tex('red_cloth');
	my $dark = tex('oak_plank', 0.62);
	# Two cells wide: the placed cell and the one to its right.
	cells(2, 1, 1);
	legs4(-8, 23, -7, 6, 1, $dark, 2);
	box(-8, 2, -7, 23, 6, 6, $cloth);
	box(-8, 7, -7, 23, 15, -4, $cloth);
	for my $x (-8, 21) { box($x, 7, -3, $x + 2, 10, 6, $cloth) }
	for my $x (-5, 4, 13) { box($x, 7, -3, $x + 7, 7, 6, tex('wool')) }
	for my $x (-5, 4, 13) { box($x, 8, -3, $x + 7, 13, -3, tex('red_cloth', 0.85)) }
	seat(2, 2, 0.4, 5, 2);
});

piece('StoneBench', sub {
	my $stone = tex('stone_bricks');
	for my $x (-7, 4) { box($x, 0, -3, $x + 2, 4, 2, $stone) }
	box(-8, 5, -4, 7, 6, 3, tex('stone'));
	seat(0, 1.75, -0.1, 3.6, 1.8);
	surface(1.75);
});

piece('RockingChair', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	# Two curved runners.
	for my $x (-5, 4) {
		for my $z (-7 .. 6) { my $y = int(($z / 7)**2 * 2.2 + 0.2); box($x, $y, $z, $x, $y, $z, $dark) }
	}
	legs4(-5, 4, -4, 4, 6, $dark);
	box(-5, 7, -4, 4, 8, 4, $oak);
	for my $x (-5, 4) { box($x, 9, -5, $x, 15, -5, $dark) }
	for my $x (-3 .. 2) { box($x, 9, -5, $x, 14, -5, $x % 2 ? $oak : $dark) }
	box(-5, 15, -5, 4, 15, -5, $dark);
	for my $x (-5, 4) { box($x, 11, -4, $x, 11, 3, $oak) }
	seat(0, 2.25, 0, 2.4, 2.2);
});

1;
