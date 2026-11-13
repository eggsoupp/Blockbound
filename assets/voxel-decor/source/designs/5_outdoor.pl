# Yard, farm and garden pieces.
use strict; use warnings;
use VoxLib; use DecorKit;

piece('FlowerPot', sub {
	my $clay = tex('clay');
	box(-3, 0, -3, 2, 4, 2, $clay);
	box(-4, 5, -4, 3, 5, 3, tex('clay', 0.8));
	box(-3, 5, -3, 2, 5, 2, tex('dirt'));
	my $stem = solid(stem => 56, 112, 46);
	my $leaf = tex('grass_top');
	my $red = solid(petal => 210, 48, 52);
	my $mid = solid(petalMid => 246, 206, 70);
	for my $f ([ -1, 0, 10 ], [ -3, 1, 8 ], [ 1, -2, 9 ], [ 2, 2, 7 ]) {
		my ($x, $z, $h) = @$f;
		box($x, 6, $z, $x, $h, $z, $stem);
		box($x - 1, $h + 1, $z, $x + 1, $h + 1, $z, $red);
		box($x, $h + 1, $z - 1, $x, $h + 1, $z + 1, $red);
		box($x, $h + 1, $z, $x, $h + 1, $z, $mid);
	}
	box(-3, 6, -1, -2, 7, 0, $leaf); box(1, 6, 0, 2, 7, 1, $leaf);
});

piece('Rug', sub {
	my $red = tex('red_cloth');
	box(-8, 0, -8, 7, 0, 7, $red);
	box(-7, 0, -7, 6, 0, 6, tex('red_cloth', 0.7));
	box(-6, 0, -6, 5, 0, 5, $red);
	box(-4, 0, -4, 3, 0, 3, tex('gold'));
	box(-3, 0, -3, 2, 0, 2, tex('red_cloth', 0.7));
	box(-1, 0, -1, 0, 0, 0, tex('gold'));
	for my $x (-7 .. 6) { next if $x % 2; box($x, 0, -8, $x, 0, -8, tex('gold')); box($x, 0, 7, $x, 0, 7, tex('gold')) }
});

piece('Banner', sub {
	my $dark = tex('oak_plank', 0.62);
	box(-3, 0, -7, 2, 0, -4, $dark);
	box(-1, 1, -7, 0, 15, -6, $dark);
	box(-6, 14, -6, 5, 14, -5, tex('oak_plank'));
	my $blue = tex('blue_cloth');
	box(-5, 3, -4, 4, 13, -4, $blue);
	for my $x (-5, 3) { box($x, 1, -4, $x + 1, 2, -4, $blue) }
	box(-5, 12, -4, 4, 13, -4, tex('blue_cloth', 0.7));
	my $gold = tex('gold');
	for my $d (0 .. 3) { box(-0.5 - $d, 8 - $d, -3, -0.5 + $d, 8 - $d, -3, $gold); box(-0.5 - $d, 2 + $d, -3, -0.5 + $d, 2 + $d, -3, $gold) if $d < 3 }
	box(-1, 6, -3, 0, 7, -3, tex('blue_cloth', 0.7));
});

piece('Scarecrow', sub {
	my $bark = tex('bark');
	box(-1, 0, -1, 0, 11, 0, $bark);
	box(-7, 9, -1, 6, 9, 0, $bark);
	my $sack = tex('sack');
	box(-3, 5, -2, 2, 10, 1, $sack);
	box(-6, 9, -2, -3, 10, 1, tex('blue_cloth')); box(2, 9, -2, 5, 10, 1, tex('blue_cloth'));
	my $straw = tex('straw');
	box(-8, 8, -1, -7, 10, 0, $straw); box(6, 8, -1, 7, 10, 0, $straw);
	box(-3, 4, -2, 2, 4, 1, $straw);
	box(-2, 11, -2, 1, 13, 1, $sack);
	my $coal = solid(face => 34, 30, 30);
	box(-2, 12, 2, -2, 12, 2, $coal); box(1, 12, 2, 1, 12, 2, $coal);
	box(-1, 11, 2, 0, 11, 2, $coal);
	box(-4, 14, -4, 3, 14, 3, $straw);
	box(-2, 15, -2, 1, 15, 1, tex('straw', 0.8));
});

# 2x2 cells, 2 high: a round cobblestone well with a brick rim, a roller
# and bucket on two posts, and a little gabled roof.
piece('Well', sub {
	cells(2, 2, 2);
	my ($cx, $cz) = (7.5, -8.5);
	my $cob = tex('cobblestone');
	my $bricks = tex('stone_bricks');
	my $dark = tex('oak_plank', 0.6);
	my $bark = tex('bark');
	my $iron = tex('iron_dark');
	my $rope = solid(rope => 150, 116, 70);

	# Water deep in the shaft, the round wall, the brick rim.
	cyl('y', $cx, $cz, 8, 0, 3, tex('water', 0.7));
	cyl('y', $cx, $cz, 8, 4, 4, tex('water'));
	cyl('y', $cx, $cz, 12.5, 0, 8, $cob, inner => 8.5);
	cyl('y', $cx, $cz, 13.2, 9, 10, $bricks, inner => 8.2);
	# Moss at the foot of the wall.
	painting(sub { cyl('y', $cx, $cz, 12.5, 0, 1, sub { VoxLib::noise(@_, 4) < 0.45 ? tex('grass_top', 0.8)->(@_) : undef }, inner => 11) });

	# Posts, roller, crank, rope and bucket.
	for my $x (-3, 17) {
		box($x, 9, $cz - 1.5, $x + 1, 24, $cz + 1.5, $dark);
	}
	cyl('x', $cz, 21, 1.5, -2, 17, $bark);
	box(19, 21, -10, 19, 21, -10, $iron);
	box(19, 18, -10, 19, 21, -10, $iron);
	box(20, 18, -10, 21, 18, -10, $iron);
	box(7, 13, -9, 7, 20, -9, $rope);
	cyl('y', $cx, $cz, 2.2, 9, 12, tex('oak_plank', 0.85));
	cyl('y', $cx, $cz, 2.4, 10, 10, $iron);
	box(6, 13, -9, 9, 13, -9, $iron);

	# The roof, gabled along X.
	my $roof = tex('oak_plank', 0.5);
	for my $z (-24 .. 7) {
		my $d = abs($z - $cz);
		my $y = 31 - int($d * 0.55);
		box(-6, $y - 1, $z, 21, $y, $z, ($y % 3) ? $roof : tex('oak_plank', 0.42));
	}
	box(-6, 31, $cz - 1, 21, 31, $cz + 1, $dark);
});

piece('WeaponRack', sub {
	my $dark = tex('oak_plank', 0.62);
	my $oak = tex('oak_plank');
	box(-7, 0, -8, 6, 1, -3, $dark);
	for my $x (-7, 5) { box($x, 2, -8, $x + 1, 14, -7, $dark) }
	box(-7, 13, -8, 6, 14, -6, $oak);
	box(-7, 5, -8, 6, 5, -6, $oak);
	my $iron = tex('iron');
	my $grip = tex('leather');
	for my $s ([ -4, $iron ], [ 0, tex('gold') ], [ 3, $iron ]) {
		my ($x, $blade) = @$s;
		box($x, 2, -5, $x, 10, -5, $blade);
		box($x - 1, 11, -5, $x + 1, 11, -5, tex('iron_dark'));
		box($x, 12, -5, $x, 14, -5, $grip);
		box($x, 15, -5, $x, 15, -5, tex('iron_dark'));
	}
});

piece('HayBale', sub {
	my $straw = tex('straw');
	box(-8, 0, -6, 7, 9, 5, $straw);
	my $twine = solid(twine => 120, 84, 46);
	for my $x (-4, 3) {
		box($x, 10, -6, $x, 10, 5, $twine);
		box($x, 0, 6, $x, 10, 6, $twine);
		box($x, 0, -7, $x, 10, -7, $twine);
	}
	surface(2.5);
});

piece('FirewoodPile', sub {
	my $bark = tex('bark');
	my $end = tex('oak_plank', 0.85);
	my @rows = ([ 0, -6, -2, 2, 6 ], [ 3, -4, 0, 4 ], [ 6, -2, 2 ]);
	for my $r (@rows) {
		my ($y, @xs) = @$r;
		for my $x (@xs) {
			cyl('z', $x, $y + 1.5, 1.7, -6, 5, $bark);
			cyl('z', $x, $y + 1.5, 1.2, 6, 6, $end);
			cyl('z', $x, $y + 1.5, 1.2, -7, -7, $end);
		}
	}
	box(-8, 0, -1, -8, 7, 0, tex('oak_plank', 0.62)); box(7, 0, -1, 7, 7, 0, tex('oak_plank', 0.62));
});

piece('TrainingDummy', sub {
	my $bark = tex('bark');
	box(-4, 0, -4, 3, 1, 3, tex('oak_plank', 0.62));
	box(-1, 2, -1, 0, 8, 0, $bark);
	my $sack = tex('sack');
	box(-3, 7, -2, 2, 12, 1, $sack);
	box(-7, 11, -1, 6, 11, 0, $bark);
	box(-7, 10, -1, -6, 12, 0, $sack); box(5, 10, -1, 6, 12, 0, $sack);
	box(-2, 13, -2, 1, 15, 1, $sack);
	my $red = tex('red_cloth');
	box(-1, 9, 2, 0, 10, 2, $red);
	box(-2, 9, 2, -2, 10, 2, solid(ring => 230, 220, 200)); box(1, 9, 2, 1, 10, 2, solid(ring => 230, 220, 200));
	box(-3, 7, -2, 2, 7, 1, tex('leather'));
});

piece('ArcheryTarget', sub {
	my $dark = tex('oak_plank', 0.62);
	for my $x (-6, 5) { cap([ $x, 0, -4 ], [ $x, 13, -2 ], 0.6, 0.6, $dark) }
	cap([ 0, 0, -8 ], [ 0, 11, -3 ], 0.6, 0.6, $dark);
	my @rings = (tex('straw'), tex('wool'), tex('red_cloth'), tex('wool'), tex('red_cloth'), tex('gold'));
	for my $r (0 .. 5) {
		cyl('z', -0.5, 8, 6.4 - $r * 1.1, -2, -1, $rings[$r]);
	}
	box(-1, 7, 0, 0, 8, 0, tex('gold'));
	box(-1, 8, 0, -1, 8, 4, tex('oak_plank')); box(-1, 8, 5, -1, 8, 5, solid(fletch => 220, 60, 60));
});

piece('WaterTrough', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-8, 1, -4, 7, 6, 3, $oak);
	cutting(sub { box(-7, 2, -3, 6, 6, 2, 'x') });
	box(-7, 2, -3, 6, 4, 2, tex('water'));
	for my $x (-7, 5) { box($x, 0, -4, $x + 1, 0, 3, $dark) }
	for my $x (-8, 7) { box($x, 1, -4, $x, 6, 3, $dark) }
	for my $z (-4, 3) { box(-8, 3, $z, 7, 3, $z, tex('iron_dark')) }
});

piece('Fountain', sub {
	my $brick = tex('stone_bricks');
	my $stone = tex('stone');
	cyl('y', -0.5, -0.5, 8, 0, 3, $brick);
	cutting(sub { cyl('y', -0.5, -0.5, 6.8, 2, 3, 'x') });
	cyl('y', -0.5, -0.5, 6.8, 2, 2, tex('water'));
	cyl('y', -0.5, -0.5, 1.6, 3, 8, $stone);
	cyl('y', -0.5, -0.5, 4, 9, 9, $brick);
	cutting(sub { cyl('y', -0.5, -0.5, 3, 9, 9, 'x') });
	cyl('y', -0.5, -0.5, 3, 9, 9, tex('water'));
	cyl('y', -0.5, -0.5, 1, 10, 12, $stone);
	box(-1, 13, -1, 0, 13, 0, tex('water'));
	note('Water spray is left to a particle effect if wanted');
});

piece('Gravestone', sub {
	my $stone = tex('stone');
	box(-6, 0, -3, 5, 1, 2, tex('cobblestone'));
	box(-5, 2, -2, 4, 11, 1, $stone);
	box(-4, 12, -2, 3, 12, 1, $stone);
	box(-3, 13, -2, 2, 13, 1, $stone);
	my $cut = tex('stone', 0.6);
	box(-1, 5, 2, 0, 11, 2, $cut);
	box(-3, 9, 2, 2, 9, 2, $cut);
	box(-4, 2, 2, -2, 2, 2, tex('grass_top')); box(2, 2, 2, 3, 3, 2, tex('grass_top'));
});

piece('Signpost', sub {
	my $dark = tex('oak_plank', 0.62);
	my $oak = tex('oak_plank');
	box(-1, 0, -1, 0, 14, 0, $dark);
	box(-7, 10, 1, 5, 13, 1, $oak);
	box(6, 11, 1, 6, 12, 1, $oak);
	box(-6, 5, -2, 6, 7, -2, $oak);
	box(-7, 6, -2, -7, 6, -2, $oak);
	my $ink = solid(ink => 60, 40, 24);
	box(-5, 12, 2, 2, 12, 2, $ink); box(-5, 11, 2, 0, 11, 2, $ink);
});

1;
