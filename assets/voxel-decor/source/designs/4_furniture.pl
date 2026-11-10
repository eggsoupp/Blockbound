# Ladder, fences and indoor furniture.
use strict; use warnings;
use VoxLib; use DecorKit;

piece('Ladder', sub {
	my $dark = tex('oak_plank', 0.62);
	my $oak = tex('oak_plank');
	for my $x (-6, 4) { box($x, 0, -8, $x + 1, 15, -7, $dark) }
	for my $y (1, 4, 7, 10, 13) { box(-4, $y, -8, 3, $y, -7, $oak) }
	# Climbing needs gapped solid rungs; the model itself is not solid.
	collide('none');
	for my $y (1, 4, 7, 10, 13) { rungs(0, ($y + 0.5) * 0.25, -1.75, 3, 0.25, 0.5) }
	rungs(-1.375, 2, -1.75, 0.5, 4, 0.5);
	rungs(1.375, 2, -1.75, 0.5, 4, 0.5);
});

piece('WoodFence', sub {
	my $dark = tex('oak_plank', 0.62);
	my $oak = tex('oak_plank');
	box(-2, 0, -2, 1, 13, 1, $dark);
	box(-2, 14, -2, 1, 14, 1, $oak);
	for my $y (4, 10) { box(-8, $y, -1, 7, $y + 1, 0, $oak) }
});

piece('IronFence', sub {
	my $iron = tex('iron_dark');
	box(-8, 0, -1, 7, 0, 0, $iron);
	box(-8, 13, -1, 7, 13, 0, $iron);
	box(-8, 6, -1, 7, 6, 0, $iron);
	for my $x (-7, -4, -1, 2, 5) {
		box($x, 1, -1, $x, 14, -1, $iron);
		box($x, 15, -1, $x, 15, -1, tex('gold'));
	}
});

piece('WoodenTable', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-8, 10, -8, 7, 11, 7, $oak);
	box(-7, 9, -7, 6, 9, 6, $dark);
	for my $x (-7, 5) { for my $z (-7, 5) { box($x, 0, $z, $x + 1, 8, $z + 1, $dark) } }
	surface(3);
});

piece('Bookshelf', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-8, 0, -8, 7, 15, -7, $dark);
	box(-8, 0, -6, -7, 15, 0, $oak);
	box(6, 0, -6, 7, 15, 0, $oak);
	for my $y (0, 5, 10, 15) { box(-6, $y, -6, 5, $y, 0, $oak) }
	my @b = (tex('red_cloth'), tex('blue_cloth'), tex('green_cloth'), tex('leather'), tex('paper'));
	my $n = 0;
	for my $y (1, 6, 11) {
		my $x = -6;
		while ($x <= 5) {
			$n++;
			my $w = 1 + ($n * 7) % 2;
			my $h = 2 + ($n * 5) % 3;
			last if $x + $w - 1 > 5;
			box($x, $y, -6, $x + $w - 1, $y + $h, -1 - ($n % 2), $b[ $n % @b ]);
			$x += $w + (($n * 3) % 5 == 0 ? 1 : 0);
		}
	}
});

piece('Barrel', sub {
	my $oak = tex('oak_plank');
	for my $y (0 .. 15) {
		my $r = 6.6 + 1.0 * sin(($y / 15) * 3.1416);
		cyl('y', -0.5, -0.5, $r, $y, $y, $oak);
	}
	my $iron = tex('iron_dark');
	for my $y (2, 13) { cyl('y', -0.5, -0.5, 7.4, $y, $y, $iron, inner => 6.4) }
	cyl('y', -0.5, -0.5, 5.6, 15, 15, tex('oak_plank', 0.75));
});

# A full-block crate: a frame of dark boards and a brace on each side face.
sub crate_box {
	my ($body, $edge, $brace) = @_;
	box(-8, 0, -8, 7, 15, 7, $body);
	for my $a (-8, 7) {
		for my $b (-8, 7) { box($a, 0, $b, $a, 15, $b, $edge) }
		for my $y (0, 15) { box(-8, $y, $a, 7, $y, $a, $edge); box($a, $y, -8, $a, $y, 7, $edge) }
	}
	return unless $brace;
	for my $i (1 .. 14) {
		box(-8 + $i, $i, 7, -8 + $i, $i, 7, $edge); box(-8 + $i, $i, -8, -8 + $i, $i, -8, $edge);
		box(-8, $i, -8 + $i, -8, $i, -8 + $i, $edge); box(7, $i, -8 + $i, 7, $i, -8 + $i, $edge);
	}
}

piece('SupplyCrate', sub {
	crate_box(tex('oak_plank'), tex('oak_plank', 0.62), 1);
});

piece('IronCrate', sub {
	my $dark = tex('iron_dark');
	crate_box(tex('iron'), $dark, 0);
	for my $z (-8, 7) { box(-8, 7, $z, 7, 8, $z, $dark) }
	box(-2, 5, 7, 1, 9, 7, tex('gold'));
	box(-1, 6, 7, 0, 7, 7, $dark);
});

piece('Wardrobe', sub {
	cells(1, 2, 1);
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-7, 0, -8, 6, 29, 3, $oak);
	box(-8, 29, -8, 7, 30, 4, $dark);
	box(-8, 0, -8, 7, 1, 4, $dark);
	box(0, 2, 4, 0, 28, 4, $dark);				# split between the doors
	for my $x (-7, 6) { box($x, 2, 4, $x, 28, 4, $dark) }
	for my $x (-5, 2) { box($x, 4, 4, $x + 2, 13, 4, $dark); box($x, 17, 4, $x + 2, 26, 4, $dark) }
	for my $x (-2, 2) { box($x, 14, 5, $x, 16, 5, tex('gold')) }
});

piece('Dresser', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-8, 0, -6, 7, 12, 3, $oak);
	box(-8, 13, -7, 7, 13, 4, $dark);
	for my $y (1, 5, 9) {
		box(-7, $y, 4, 6, $y + 2, 4, $dark);
		box(-1, $y + 1, 5, 0, $y + 1, 5, tex('gold'));
	}
	surface(3.5);
});

piece('Nightstand', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-5, 0, -5, 4, 9, 4, $oak);
	box(-6, 10, -6, 5, 10, 5, $dark);
	box(-4, 5, 5, 3, 8, 5, $dark);
	box(-1, 6, 6, 0, 6, 6, tex('gold'));
	surface(2.75);
});

piece('Desk', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-8, 10, -6, 7, 11, 5, $oak);
	box(-8, 0, -6, -6, 9, 5, $dark);			# leg panel
	box(3, 0, -6, 7, 9, 5, $oak);				# drawers
	for my $y (1, 5) { box(3, $y, 6, 7, $y + 2, 6, $dark); box(5, $y + 1, 7, 5, $y + 1, 7, tex('gold')) }
	box(-5, 8, -6, 2, 9, -6, $dark);
	# Open book and a quill on top.
	box(-4, 12, -2, 1, 12, 1, tex('paper'));
	box(-4, 12, -2, -4, 12, 1, tex('leather')); box(1, 12, -2, 1, 12, 1, tex('leather'));
	box(4, 12, -3, 4, 15, -3, solid(quill => 236, 232, 222));
	surface(3);
});

piece('GrandfatherClock', sub {
	cells(1, 2, 1);
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-5, 0, -4, 4, 2, 3, $dark);
	box(-4, 3, -3, 3, 19, 2, $oak);
	box(-5, 20, -4, 4, 29, 3, $oak);
	box(-6, 30, -5, 5, 31, 4, $dark);
	# Pendulum window and the face.
	box(-2, 6, 3, 1, 17, 3, solid(clockShadow => 30, 24, 20));
	box(-1, 9, 3, 0, 15, 3, tex('gold'));
	box(-2, 7, 3, 1, 8, 3, tex('gold'));
	box(-3, 21, 4, 2, 28, 4, tex('paper'));
	box(-1, 24, 5, -1, 27, 5, solid(hand => 30, 28, 30));
	box(-1, 24, 5, 1, 24, 5, solid(hand => 30, 28, 30));
	for my $p ([ -2, 27 ], [ 1, 27 ], [ -3, 24 ], [ 2, 24 ], [ -2, 21 ], [ 1, 21 ]) { box($p->[0], $p->[1], 5, $p->[0], $p->[1], 5, tex('gold')) }
});

piece('PotionShelf', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-8, 0, -8, 7, 15, -7, $dark);
	for my $x (-8, 6) { box($x, 0, -6, $x + 1, 15, -2, $oak) }
	for my $y (0, 7, 14) { box(-6, $y, -6, 5, $y, -2, $oak) }
	my @liquid = (glow(potRed => 230, 60, 70), glow(potBlue => 80, 140, 255), glow(potGreen => 90, 220, 110), glow(potPurple => 190, 100, 240));
	my $glass = solid(bottleGlass => 200, 226, 232);
	my $cork = solid(cork => 150, 110, 70);
	my $n = 0;
	for my $y (1, 8) {
		for my $x (-5, -2, 1, 4) {
			my $h = 2 + ($n % 3 == 0 ? 2 : 1);
			box($x - 1, $y, -5, $x, $y + $h - 1, -4, $liquid[ $n % 4 ]);
			box($x - 1, $y + $h, -5, $x, $y + $h, -4, $glass);
			box($x - 1, $y + $h + 1, -5, $x - 1, $y + $h + 1, -5, $cork);
			$n++;
		}
	}
});

piece('Globe', sub {
	my $oak = tex('oak_plank', 0.62);
	box(-3, 0, -3, 2, 0, 2, $oak);
	box(-1, 1, -1, 0, 4, 0, $oak);
	box(-4, 5, -2, 3, 5, 1, tex('gold'));
	my $sea = tex('blue_cloth');
	my $land = tex('grass_top');
	ell(-0.5, 10, -0.5, 4.6, 4.6, 4.6, sub {
		my ($x, $y, $z) = @_;
		return VoxLib::cellnoise($x, $y, $z, 3, 21) < 0.38 ? $land->(@_) : $sea->(@_);
	});
	for my $y (5 .. 15) { my $d = 5.6; my $a = ($y - 10) / $d; next if abs($a) > 1; my $x = int(-0.5 + sqrt(1 - $a * $a) * $d); box($x, $y, -1, $x, $y, 0, tex('gold')) }
});

1;
