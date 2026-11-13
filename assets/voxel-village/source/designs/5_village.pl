# The rest of the village: the Starfall waystone in the middle of the plaza,
# two cottages, a notice board and the gate that marks each road out.
use strict; use warnings;
use VoxLib; use DecorKit; use VillageKit;

# ---------------------------------------------------------------- notice board

asset('NoticeBoard', sub {
	my $bark = tex('bark');
	my $oak = tex('oak_plank');
	my $dark = tex('oak_plank', 0.55);
	my $paper = tex('paper', 0.78);
	my $ink = solid(ink => 48, 40, 36);
	my $red = tex('red_cloth');
	my $pin = solid(pin => 200, 60, 50);

	for my $x (-12, 10) { box($x, 0, -1, $x + 1, 30, 0, $bark) }
	box(-11, 9, -1, 10, 27, 0, $oak);
	box(-11, 9, -2, 10, 9, -2, $dark); box(-11, 27, -2, 10, 27, -2, $dark);
	box(-11, 9, -2, -11, 27, -2, $dark); box(10, 9, -2, 10, 27, -2, $dark);
	# Little roof.
	for my $z (-4 .. 3) {
		my $y = 31 + (3 - int(abs($z + 0.5)));
		box(-14, $y, $z, 13, $y, $z, $dark);
	}
	# Pinned notes with scribbles.
	my @notes = ([ -9, 13, -3, 24 ], [ -1, 16, 4, 25 ], [ 5, 11, 8, 19 ], [ -2, 11, 3, 14 ]);
	for my $n (@notes) {
		my ($x0, $y0, $x1, $y1) = @$n;
		box($x0, $y0, -2, $x1, $y1, -2, $paper);
		for (my $y = $y1 - 2; $y > $y0; $y -= 2) {
			my $len = int(ragged($x0, $y, 0, 5) * ($x1 - $x0 - 1));
			box($x0 + 1, $y, -3, $x0 + 1 + $len, $y, -3, $ink) if $len > 0;
		}
		box(int(($x0 + $x1) / 2), $y1, -3, int(($x0 + $x1) / 2), $y1, -3, $pin);
	}
	# A red "wanted" poster.
	box(-9, 11, -2, -5, 12, -2, $red);
	box(-9, 11, -3, -9, 11, -3, $pin);
});

# ---------------------------------------------------------------- gate

# Marks a road leaving the village: two posts on stone footings, a beam with
# upturned ends, a hanging sign with a star, two lanterns. The road runs
# along Z between the posts (8 studs apart inside).
asset('VillageGate', sub {
	my $bark = tex('bark');
	my $dark = tex('oak_plank', 0.55);
	my $oak = tex('oak_plank');
	my $cob = tex('cobblestone');
	my $iron = tex('iron_dark');
	my $lit = tex('window_lit');
	my $sgold = tex('stargold');
	my $rope = solid(rope => 150, 116, 70);

	part('PostLeft', undef, [ 0, 0, 0 ]);
	box(-23, 0, -3, -18, 5, 2, $cob);
	box(-22, 6, -2, -19, 47, 1, $bark);
	part('PostRight', undef, [ 0, 0, 0 ]);
	box(17, 0, -3, 22, 5, 2, $cob);
	box(18, 6, -2, 21, 47, 1, $bark);

	part('Beam', undef, [ 0, 0, 0 ]);
	box(-26, 46, -2, 25, 48, 1, $dark);
	box(-28, 48, -2, -26, 49, 1, $dark); box(25, 48, -2, 27, 49, 1, $dark);
	box(-29, 50, -2, -28, 50, 1, $dark); box(27, 50, -2, 28, 50, 1, $dark);
	box(-18, 40, -1, 17, 41, 0, $dark);
	for my $x (-12, 11) {
		box($x, 37, -1, $x, 45, -1, $iron);
		box($x - 2, 30, -3, $x + 2, 30, 1, $iron);
		box($x - 2, 36, -3, $x + 2, 36, 1, $iron);
		box($x - 1, 31, -2, $x + 1, 35, 0, $lit);
		for my $c ([ -2, -3 ], [ 2, -3 ], [ -2, 1 ], [ 2, 1 ]) { box($x + $c->[0], 31, $c->[1], $x + $c->[0], 35, $c->[1], $iron) }
	}
	glowlight(-2.875, 8.3, -0.125, 12, 'f4c46a');
	glowlight(3.0, 8.3, -0.125, 12, 'f4c46a');
	hitbox('Beam', 'none');
	hitbox('BeamGlow', 'none');
	neon('Beam');

	part('Sign', undef, [ 0, 0, 0 ]);
	hitbox('Sign', 'none');
	box(-5, 35, -1, -5, 39, -1, $rope); box(4, 35, -1, 4, 39, -1, $rope);
	box(-7, 28, -2, 6, 35, 1, $oak);
	box(-7, 28, -2, 6, 28, 1, $dark); box(-7, 35, -2, 6, 35, 1, $dark);
	for my $f (-3, 2) {
		box(-1, 30, $f, 0, 33, $f, $sgold);
		box(-2, 31, $f, 1, 32, $f, $sgold);
		box(-3, 31, $f, -3, 31, $f, $sgold); box(2, 32, $f, 2, 32, $f, $sgold);
	}
});
1;
