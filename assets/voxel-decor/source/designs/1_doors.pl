# Doors, gates and windows. A door's swinging half is the part 'Leaf'; its
# hinge is on the left edge seen from the front (-X).
use strict; use warnings;
use VoxLib; use DecorKit;

piece('WoodenDoor', sub {
	cells(1, 2, 1);
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	my $iron = tex('iron_dark');
	part('Leaf', 'Body', [ -7, 16, 0 ], 'Swing');
	box(-7, 0, -2, 7, 31, 1, $oak);
	# Framing boards round the edge and a Z brace, front and back.
	for my $z (-3, 2) {
		box(-7, 1, $z, 7, 3, $z, $dark);
		box(-7, 28, $z, 7, 30, $z, $dark);
		box(-7, 14, $z, 7, 16, $z, $dark);
		for my $y (4 .. 13) { my $x = -6 + int(($y - 4) * 12 / 9); box($x - 1, $y, $z, $x + 1, $y, $z, $dark) }
		for my $y (17 .. 27) { my $x = -6 + int(($y - 17) * 12 / 10); box($x - 1, $y, $z, $x + 1, $y, $z, $dark) }
	}
	# Ring handle on both faces.
	for my $z (-4, 3) { box(4, 13, $z, 5, 17, $z, $iron) }
	box(4, 15, -3, 5, 15, 2, $iron);
	hinge(-1.75, 4, 0);
});

piece('IronDoor', sub {
	cells(1, 2, 1);
	my $iron = tex('iron');
	my $dark = tex('iron_dark');
	part('Leaf', 'Body', [ -7, 16, 0 ], 'Swing');
	box(-7, 0, -2, 7, 31, 1, $iron);
	# Raised panels and rivets.
	for my $z (-3, 2) {
		box(-7, 0, $z, 7, 1, $z, $dark);
		box(-7, 30, $z, 7, 31, $z, $dark);
		box(-7, 0, $z, -6, 31, $z, $dark);
		box(6, 0, $z, 7, 31, $z, $dark);
		box(-7, 14, $z, 7, 15, $z, $dark);
		for my $y (3, 12, 18) { for my $x (-4, 4) { box($x, $y, $z, $x, $y, $z, $dark) } }
		box(3, 13, $z, 4, 16, $z + ($z > 0 ? 1 : -1), $dark);
	}
	# Barred window.
	cutting(sub { box(-4, 21, -2, 4, 27, 1, 'x') });
	box(-4, 21, 0, 4, 27, 0, solid(shadow => 22, 22, 26));
	for my $x (-3, -1, 1, 3) { box($x, 21, -1, $x, 27, 0, $dark) }
	hinge(-1.75, 4, 0);
});

piece('FenceGate', sub {
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.62);
	box(-8, 0, -1, -7, 13, 0, $dark);
	box(6, 0, -1, 7, 13, 0, $dark);
	box(-8, 14, -1, -7, 14, 0, $oak);
	box(6, 14, -1, 7, 14, 0, $oak);
	part('Leaf', 'Body', [ -6, 7, 0 ], 'Swing');
	box(-6, 3, -1, 5, 4, 0, $oak);
	box(-6, 10, -1, 5, 11, 0, $oak);
	for my $x (-6, -2, 2, 5) { box($x, 1, -1, $x, 12, 0, $oak) }
	for my $i (0 .. 9) { my $x = -5 + $i; my $y = 4 + int($i * 6 / 9); box($x, $y, 1, $x, $y + 1, 1, $dark) }
	hinge(-1.5, 1.75, 0);
});

piece('Window', sub {
	my $dark = tex('oak_plank', 0.62);
	box(-8, 0, -1, 7, 15, 0, $dark);
	cutting(sub { box(-6, 2, -1, 5, 13, 0, 'x') });
	box(-8, 0, 1, 7, 1, 2, tex('oak_plank'));		# sill
	# Panes (part 'Glass' is built see-through), then the cross over them.
	my $hi = solid(glassHi => 220, 240, 255);
	my $lo = solid(glass => 160, 206, 236);
	part('Glass', 'Body', [ 0, 0, 0 ], 'Glass');
	box(-6, 2, -1, 5, 13, -1, sub { ($_[0] + $_[1]) % 7 == 0 ? $hi : $lo });
	use_part('Body');
	box(-1, 2, -1, 0, 13, 0, $dark);			# mullion
	box(-6, 7, -1, 5, 8, 0, $dark);				# transom
});

1;
