# Lights. Flames are particle effects added in game (flame()), so the models
# carry only what burns: logs, wicks, coals, a lantern's cage.
use strict; use warnings;
use VoxLib; use DecorKit;

piece('Campfire', sub {
	my $stone = tex('cobblestone');
	my $stone2 = tex('stone');
	for my $i (0 .. 11) {
		my $a = $i / 12 * 6.2832;
		my ($x, $z) = (int(sin($a) * 5.6 + ($a > 3.14 ? -0.5 : 0.5)), int(cos($a) * 5.6));
		my $h = $i % 2 ? 1 : 2;
		box($x - 1, 0, $z - 1, $x, $h, $z, $i % 3 ? $stone : $stone2);
	}
	box(-3, 0, -3, 2, 0, 2, tex('coal_bed'));
	my $bark = tex('bark');
	cap([ -4, 1, -3 ], [ 3, 2, 2 ], 1.1, 1.1, $bark);
	cap([ 3, 1, -3 ], [ -4, 2, 2 ], 1.1, 1.1, $bark);
	cap([ -1, 3, -4 ], [ 0, 3, 4 ], 1.0, 1.0, $bark);
	box(-2, 1, -1, 1, 1, 0, tex('ember'));
	flame(0, 1.3, 0, 2.6, 22);
});

piece('StandingTorch', sub {
	box(-3, 0, -3, 2, 0, 2, tex('cobblestone'));
	box(-2, 1, -2, 1, 1, 1, tex('stone'));
	box(-1, 2, -1, 0, 12, 0, tex('bark'));
	box(-2, 13, -2, 1, 14, 1, tex('iron_dark'));
	box(-1, 15, -1, 0, 15, 0, tex('coal_bed'));
	flame(0, 4.15, 0, 1.4, 16);
});

# A lantern's cage at (cx, y0, cz), w voxels across.
sub lantern_cage {
	my ($y0, $big) = @_;
	my $iron = tex('iron_dark');
	my $glass = solid(lampGlass => 255, 214, 140);
	my ($r, $h) = $big ? (3, 6) : (2, 5);
	box(-$r - 1, $y0, -$r - 1, $r, $y0, $r, $iron);
	box(-$r, $y0 + 1, -$r, $r - 1, $y0 + $h, $r - 1, glow(lampGlow => 255, 196, 110));
	for my $x (-$r - 1, $r) { for my $z (-$r - 1, $r) { box($x, $y0 + 1, $z, $x, $y0 + $h, $z, $iron) } }
	box(-$r - 1, $y0 + $h + 1, -$r - 1, $r, $y0 + $h + 1, $r, $iron);
	box(-$r, $y0 + $h + 2, -$r, $r - 1, $y0 + $h + 2, $r - 1, $iron);
	box(-1, $y0 + $h + 3, -1, 0, $y0 + $h + 3, 0, $iron);
	box(-1, $y0 + $h + 4, -$r + 1, 0, $y0 + $h + 4, $r - 2, $iron);
	return ($y0 + 1 + $h / 2) * 0.25;
}

piece('Lantern', sub {
	my $mid = lantern_cage(0, 1);
	glowlight(0, $mid, 0, 14, 'ffaa5a');
});

piece('LampPost', sub {
	cells(1, 2, 1);
	box(-3, 0, -3, 2, 1, 2, tex('stone'));
	box(-2, 2, -2, 1, 3, 1, tex('iron_dark'));
	box(-1, 4, -1, 0, 19, 0, tex('iron_dark'));
	box(-2, 20, -2, 1, 20, 1, tex('iron_dark'));
	my $mid = lantern_cage(21, 1);
	glowlight(0, $mid, 0, 26, 'ffaa5a');
});

piece('Brazier', sub {
	my $iron = tex('iron_dark');
	for my $i (0 .. 2) {
		my $a = $i / 3 * 6.2832;
		my ($x, $z) = (int(sin($a) * 3.5), int(cos($a) * 3.5));
		cap([ $x * 1.3, 0, $z * 1.3 ], [ $x * 0.8, 8, $z * 0.8 ], 0.6, 0.6, $iron);
	}
	cyl('y', -0.5, -0.5, 5.5, 8, 9, $iron);
	cyl('y', -0.5, -0.5, 6.5, 10, 11, tex('iron'), inner => 4.5);
	cyl('y', -0.5, -0.5, 4.5, 10, 10, tex('coal_bed'));
	cyl('y', -0.5, -0.5, 3.5, 11, 11, tex('ember'));
	flame(0, 3.4, 0, 2.2, 20);
});

piece('Candle', sub {
	cyl('y', -0.5, -0.5, 4.5, 0, 0, tex('iron'));
	my $wax = tex('wax');
	my $wick = solid(wick => 40, 34, 30);
	for my $c ([ -2, -1, 6 ], [ 2, -1, 4 ], [ 0, 2, 3 ]) {
		my ($x, $z, $h) = @$c;
		box($x - 1, 1, $z - 1, $x, $h, $z, $wax);
		box($x - 1, $h + 1, $z - 1, $x - 1, $h + 1, $z - 1, $wick);
		flame(($x - 0.5) * 0.25, ($h + 2.2) * 0.25, ($z - 0.5) * 0.25, 0.55, $x == -2 ? 10 : undef);
	}
});

piece('StoneFireplace', sub {
	my $brick = tex('stone_bricks');
	box(-8, 0, -8, 7, 15, -4, $brick);			# back
	box(-8, 0, -3, -5, 11, 7, $brick);			# cheeks
	box(4, 0, -3, 7, 11, 7, $brick);
	box(-8, 12, -3, 7, 15, 7, $brick);			# lintel
	box(-8, 11, -3, 7, 12, 7, tex('oak_plank', 0.62));	# mantel
	box(-4, 0, -3, 3, 0, 7, tex('coal_bed'));
	my $bark = tex('bark');
	cap([ -3, 1, 1 ], [ 2, 1, 3 ], 1, 1, $bark);
	cap([ -3, 2, 3 ], [ 2, 2, 0 ], 1, 1, $bark);
	box(-2, 1, 1, 1, 1, 2, tex('ember'));
	flame(-0.1, 1.2, 0.5, 1.8, 20);
});

piece('JackOLantern', sub {
	my $pumpkin = tex('pumpkin');
	ell(-0.5, 5, -0.5, 6.4, 5.2, 6.4, $pumpkin);
	box(-1, 10, -1, 0, 12, 0, tex('bark'));
	# Carved face, lit from inside.
	my $lit = glow(pumpkinLit => 255, 186, 60);
	cutting(sub { ell(-0.5, 5, -0.5, 5.2, 4.2, 5.2, 'x') });
	box(-4, 3, -4, 3, 7, 3, $lit);
	cutting(sub {
		for my $x (-4, 3) { box($x - 1, 6, 4, $x, 7, 7, 'x'); box($x - ($x < 0 ? 0 : 1), 8, 4, $x - ($x < 0 ? 0 : 1), 8, 7, 'x') }
		box(-1, 5, 4, 0, 5, 7, 'x');
		box(-4, 2, 4, 3, 3, 7, 'x');
		box(-3, 4, 4, -3, 4, 7, 'x'); box(2, 4, 4, 2, 4, 7, 'x');
	});
	glowlight(0, 1.25, 0, 12, 'ffa040');
});

piece('StoneLantern', sub {
	my $stone = tex('stone');
	my $cob = tex('cobblestone');
	box(-5, 0, -5, 4, 1, 4, $cob);
	box(-2, 2, -2, 1, 6, 1, $stone);
	box(-4, 7, -4, 3, 7, 3, $cob);
	box(-3, 8, -3, 2, 11, 2, $stone);
	cutting(sub { box(-2, 9, -3, 1, 10, 2, 'x'); box(-3, 9, -2, 2, 10, 1, 'x') });
	box(-1, 9, -1, 0, 10, 0, glow(stoneLanternGlow => 255, 190, 110));
	box(-6, 12, -6, 5, 12, 5, $cob);
	box(-4, 13, -4, 3, 13, 3, $stone);
	box(-2, 14, -2, 1, 14, 1, $stone);
	box(-1, 15, -1, 0, 15, 0, $cob);
	flame(-0.12, 2.4, -0.12, 0.6, 14);
});

piece('CrystalLamp', sub {
	my $stone = tex('stone_bricks');
	box(-4, 0, -4, 3, 1, 3, $stone);
	box(-3, 2, -3, 2, 3, 2, tex('gold'));
	my $c = tex('crystal');
	cap([ -0.5, 3, -0.5 ], [ -0.5, 12, -0.5 ], 2.2, 0.6, $c);
	cap([ -2, 3, 1 ], [ -4, 8, 2 ], 1.3, 0.5, $c);
	cap([ 1, 3, -1 ], [ 3, 9, -2 ], 1.4, 0.5, $c);
	cap([ 1, 3, 2 ], [ 2, 6, 4 ], 1.0, 0.4, $c);
	glowlight(0, 1.8, 0, 18, '78d0ff');
});

piece('MushroomLamp', sub {
	my $stem = tex('wax');
	my $cap = tex('shroom_glow');
	box(-4, 0, -4, 3, 0, 3, tex('dirt'));
	cap([ -0.5, 1, -0.5 ], [ -0.5, 9, -0.5 ], 1.6, 1.3, $stem);
	ell(-0.5, 10, -0.5, 5.2, 2.6, 5.2, $cap);
	cutting(sub { box(-6, 7, -6, 5, 9, 5, 'x') });
	box(-4, 9, -4, 3, 9, 3, tex('mushroom'));
	cap([ 3, 1, 2 ], [ 3, 4, 2 ], 0.8, 0.8, $stem);
	ell(3, 5, 2, 2, 1.2, 2, $cap);
	cap([ -4, 1, 2 ], [ -4, 3, 2 ], 0.7, 0.7, $stem);
	ell(-4, 4, 2, 1.6, 1, 1.6, $cap);
	glowlight(0, 2.3, 0, 16, '5ee8d0');
});

1;
