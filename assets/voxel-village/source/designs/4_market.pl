# The trading square: covered trade booths where two players sit across a
# low table to trade, and the wooden TRADING stand over the road in.
#
# TradeBooth*: the trading station (not rigged). A plank deck under a
# shingled roof on four posts; a low table across the middle with a brass
# scale, a ledger, coin stacks and a gem box; a floor cushion either side of
# it (PadA at -Z, PadB at +Z, 3 studs out: SpawnHub seats them, and sitting
# on both starts a trade, see TradeStations), a lantern over each cushion and
# the balance-scale sign on the gables and the ridge crest.
use strict; use warnings;
use VoxLib; use DecorKit; use VillageKit;

sub hex3 { my $h = shift; return map { hex(substr($h, $_ * 2, 2)) } 0 .. 2 }

# The market's palette, a shade darker than written: the game's midday light
# lifts these colours a long way (crimson read as pink).
sub mpal { my ($name, @hex) = @_; return pal($name, map { my @c = hex3($_); sprintf('%02x%02x%02x', map { int($_ * 0.8) } @c) } @hex) }

# Planks along Z with seams every 4 voxels, two shades and a little speckle.
sub planks {
	my ($name, $a, $b, $seam) = @_;
	my $pa = mpal("${name}A", @$a);
	my $pb = mpal("${name}B", @$b);
	my $s = solid("${name}Seam", hex3($seam));
	return sub {
		my ($x, $y, $z) = @_;
		my $u = ($x + 64) % 8;
		return $s if $u == 7;
		return $u < 4 ? $pa->(@_) : $pb->(@_);
	};
}

# A balance scale, the trading sign: (u, y) grid, 11 wide x 6 high, drawn
# by the callback.
my @ICON = (
	'.....#.....',
	'###########',
	'.#...#...#.',
	'###..#..###',
	'.....#.....',
	'....###....',
);
sub icon {
	my ($put) = @_;
	for my $r (0 .. $#ICON) {
		my @c = split //, $ICON[$r];
		for my $i (0 .. $#c) { $put->($i, -$r) if $c[$i] eq '#' }
	}
}

sub booth {
	my ($id, $cloth, $clothDark) = @_;
	asset($id, sub {
		my $deck = planks('deck', [ 'b0794a', 'b98352', 'a56f42' ], [ 'a26c40', 'ab7647', '96633a' ], '5e3d22');
		my $dark = mpal('wood', '5a3a22', '634127', '52341e');
		my $light = mpal('top', 'c8925a', 'd29c63', 'bd8752');
		my $brass = mpal('brass', 'c99a3e', 'd8aa4c', 'b98a34');
		my $gold = solid(gold => 236, 190, 70);
		my $cl = mpal('cloth', @$cloth);
		my $cd = mpal('clothD', @$clothDark);
		my $paper = solid(paper => 226, 214, 184);
		my $ink = solid(ink => 60, 48, 40);
		my $leather = solid(leather => 120, 70, 40);
		my $gemA = glow(gemA => 90, 170, 220);
		my $gemB = glow(gemB => 170, 110, 220);
		my $gemC = glow(gemC => 90, 200, 120);
		my $warm = glow(warm => 240, 170, 80);
		my $iron = solid(iron => 52, 50, 56);

		# ------------------------------------------------------------ deck and cushions
		box(-18, 0, -25, 17, 1, 24, $deck);
		box(-18, 0, -25, 17, 0, -25, $dark); box(-18, 0, 24, 17, 0, 24, $dark);
		# A floor cushion each side of the low table: sitting on one is being
		# ready to trade (SpawnHub puts a Seat on each, at PadA / PadB).
		for my $s (-1, 1) {
			my $cz = 12 * $s;
			my ($z0, $z1) = ($cz - 5, $cz + 4);
			box(-5, 2, $z0, 4, 3, $z1, $cd);
			box(-4, 4, $z0 + 1, 3, 4, $z1 - 1, $cl);
			cutting(sub { for my $c ([ -5, $z0 ], [ 4, $z0 ], [ -5, $z1 ], [ 4, $z1 ]) { box($c->[0], 3, $c->[1], $c->[0], 3, $c->[1], 'x') } });
			# Piping round the top, a button in the middle, a tassel at each corner.
			painting(sub { box(-5, 3, $z0, 4, 3, $z1, sub { ($_[0] == -5 || $_[0] == 4 || $_[2] == $z0 || $_[2] == $z1) ? $gold : undef }) });
			box(-1, 5, $cz - 1, 0, 5, $cz, $gold);
			for my $c ([ -6, $z0 - 1 ], [ 5, $z0 - 1 ], [ -6, $z1 + 1 ], [ 5, $z1 + 1 ]) {
				box($c->[0], 2, $c->[1], $c->[0], 2, $c->[1], $gold);
			}
		}
		anchor('PadA', 0, 1.25, -3);
		anchor('PadB', 0, 1.25, 3);

		# ------------------------------------------------------------ the low table
		part('Counter', undef, [ 0, 0, 0 ]);
		for my $x (-14, 12) { for my $z (-5, 3) { box($x, 2, $z, $x + 1, 7, $z + 1, $dark) } }
		box(-15, 8, -5, 14, 8, 4, $light);
		box(-15, 7, -5, 14, 7, 4, $dark);
		# A cloth over the middle, hanging down towards each trader.
		box(-5, 9, -6, 4, 9, 5, $cl);
		box(-5, 5, -6, 4, 8, -6, $cl); box(-5, 5, 5, 4, 8, 5, $cl);
		box(-5, 5, -6, 4, 5, -6, $gold); box(-5, 5, 5, 4, 5, 5, $gold);

		# ------------------------------------------------------------ wares on the table
		part('Wares', undef, [ 0, 0, 0 ]);
		hitbox('Wares', 'none');
		# The scale: post, a beam pointing at each trader, two pans.
		disc(0, 0, 2.2, 2.2, 10, 10, $brass);
		cyl('y', -0.5, -0.5, 1.0, 11, 20, $brass);
		box(-1, 20, -8, 0, 20, 7, $brass);
		box(-1, 21, -1, 0, 21, 0, $gold);
		for my $z (-7, 6) {
			box(-1, 15, $z, -1, 19, $z, $iron); box(0, 15, $z, 0, 19, $z, $iron);
			disc(0, $z + 0.5, 2.4, 2.4, 14, 14, $brass);
			ring(0, $z + 0.5, 1.8, 2.5, 15, 15, $brass);
		}
		box(-1, 15, -8, 0, 15, -8, $gemA);
		box(0, 15, 6, 0, 16, 7, $gold);
		# An open ledger with a quill and ink.
		box(-12, 9, -3, -6, 9, 2, $leather);
		box(-11, 10, -3, -9, 10, 2, $paper); box(-8, 10, -3, -6, 10, 2, $paper);
		for my $z (-2, 0, 2) { box(-11, 11, $z, -10, 11, $z, $ink); box(-8, 11, $z, -7, 11, $z, $ink) }
		box(-14, 9, 0, -13, 10, 1, $ink);
		box(-13, 11, 1, -13, 14, 1, $paper);
		# Coin stacks and a little box of gems.
		for my $c ([ 6, -3, 3 ], [ 8, -2, 5 ], [ 6, 0, 2 ], [ 8, 1, 4 ]) {
			my ($x, $z, $h) = @$c;
			box($x, 9, $z, $x + 1, 8 + $h, $z, $gold);
		}
		box(10, 9, -3, 13, 11, 1, $dark);
		box(11, 12, -2, 11, 12, -2, $gemA); box(12, 12, -1, 12, 12, -1, $gemB); box(11, 12, 0, 11, 12, 0, $gemC);
		box(12, 12, -3, 12, 12, -3, $gold);

		# ------------------------------------------------------------ posts
		part('Posts', undef, [ 0, 0, 0 ]);
		hitbox('Posts', 'precise');
		for my $x (-17, 15) {
			for my $z (-24, 22) {
				box($x, 2, $z, $x + 1, 44, $z + 1, $dark);
				box($x - 1, 43, $z - 1, $x + 2, 44, $z + 2, $brass);
			}
		}
		box(-17, 42, -24, 16, 43, -23, $dark);
		box(-17, 42, 22, 16, 43, 23, $dark);

		# ------------------------------------------------------------ roof
		part('Roof', undef, [ 0, 0, 0 ]);
		for my $x (-22 .. 21) {
			my $d = abs($x + 0.5);
			my $y = 55 - int($d * 0.45);
			box($x, $y - 1, -27, $x, $y, 26, ($y % 3 == 0) ? $cd : $cl);
		}
		box(-1, 56, -27, 0, 56, 26, $gold);
		# Gable boards with the balance-scale sign, both ends.
		for my $z (-26, 25) {
			for my $y (45 .. 54) {
				my $w = int((55 - $y) / 0.45) - 2;
				$w = 18 if $w > 18;
				box(-$w - 1, $y, $z, $w, $y, $z, $dark) if $w > 0;
			}
			my $face = $z < 0 ? $z - 1 : $z + 1;
			icon(sub { my ($u, $v) = @_; box($u - 6, 51 + $v, $face, $u - 6, 51 + $v, $face, $gold) });
		}
		# Valance along both long eaves.
		for my $s (-1, 1) {
			my $x = $s < 0 ? -22 : 21;
			for my $z (-27 .. 26) {
				my $len = (($z + 27) % 4 < 2) ? 3 : 1;
				box($x, 45 - $len, $z, $x, 44, $z, (int(($z + 27) / 4) % 2) ? $cl : $cd);
				box($x, 44 - $len, $z, $x, 44 - $len, $z, $gold) if $len == 3 && ($z + 27) % 4 == 0;
			}
		}

		# ------------------------------------------------------------ crest and lanterns
		part('Crest', undef, [ 0, 0, 0 ]);
		hitbox('Crest', 'none');
		neon('Crest');
		box(-1, 57, -1, 0, 58, 0, $dark);
		box(-1, 59, -9, 0, 67, 8, $dark);
		box(-1, 59, -9, 0, 59, 8, $gold); box(-1, 67, -9, 0, 67, 8, $gold);
		for my $xf (-2, 1) {
			icon(sub { my ($u, $v) = @_; box($xf, 66 + $v, $u - 5, $xf, 66 + $v, $u - 5, $gold) });
		}
		for my $s (-1, 1) {
			my $z = 12 * $s;
			box(-1, 41, $z, -1, 49, $z, $iron);
			box(-3, 35, $z - 2, 1, 35, $z + 2, $iron);
			box(-3, 40, $z - 2, 1, 40, $z + 2, $iron);
			box(-2, 36, $z - 1, 0, 39, $z + 1, $warm);
			for my $c ([ -3, -2 ], [ 1, -2 ], [ -3, 2 ], [ 1, 2 ]) { box($c->[0], 36, $z + $c->[1], $c->[0], 39, $z + $c->[1], $iron) }
			glowlight(-0.25, 9.6, ($z + 0.5) * 0.25, 13, 'f0b060');
		}
	});
}

booth('TradeBoothTeal', [ '2c7a7b', '348a8b', '286f70' ], [ '215c5e', '27696b', '1d5254' ]);
booth('TradeBoothCrimson', [ '9b2d30', 'ab3838', '8e282b' ], [ '74222a', '822730', '6a1e26' ]);

# ---------------------------------------------------------------- arch

# Over the road into the trading square: a plain wooden stand, put up by
# villagers rather than built to a plan. Two log posts of different heights,
# a beam that runs long past the left post with a knee brace on that side
# only, and the TRADING sign hung high in the middle on two ropes. A
# barrel and a coil of rope at the foot of the right post.
asset('MarketArch', sub {
	my $bark = mpal('bark', '6e4c2a', '5e4024', '7a5630');
	my $wood = mpal('wood', '5a3a22', '634127', '52341e');
	my $sign = mpal('sign', 'c8925a', 'd29c63', 'bd8752');
	my $stone = mpal('stone', '8a8478', '958f83', '7e786c');
	my $rope = solid(rope => 150, 116, 70);
	my $iron = solid(iron => 52, 50, 56);

	part('PostLeft', undef, [ 0, 0, 0 ]);
	box(-27, 0, -3, -22, 3, 2, $stone);
	box(-24, 3, -4, -22, 4, -3, $stone);
	box(-26, 4, -2, -23, 52, 1, $bark);
	part('PostRight', undef, [ 0, 0, 0 ]);
	box(21, 0, -2, 26, 2, 1, $stone);
	box(22, 3, -1, 25, 46, 0, $bark);

	part('Beam', undef, [ 0, 0, 0 ]);
	hitbox('Beam', 'none');
	# Runs from well past the left post to just over the right one.
	box(-31, 47, -2, 27, 49, 1, $wood);
	box(-31, 50, -1, -30, 50, 0, $wood);
	# Knee brace on the left only.
	for my $i (0 .. 7) { box(-22 + $i, 39 + $i, -1, -21 + $i, 39 + $i, 0, $wood) }
	# Iron pins where the beam sits on the posts.
	box(-25, 48, -3, -24, 48, -3, $iron); box(23, 48, -3, 24, 48, -3, $iron);

	part('Sign', undef, [ 0, 0, 0 ]);
	hitbox('Sign', 'none');
	# Centred between the posts (both are 24 voxels from the road's middle),
	# hung close under the beam.
	my ($x0, $x1) = (-16, 15);
	box($x0 + 3, 43, -1, $x0 + 3, 46, -1, $rope);
	box($x1 - 3, 43, -1, $x1 - 3, 46, -1, $rope);
	box($x0, 33, -2, $x1, 42, 1, $sign);
	box($x0, 33, -2, $x1, 33, 1, $wood); box($x0, 42, -2, $x1, 42, 1, $wood);
	box($x0, 33, -2, $x0, 42, 1, $wood); box($x1, 33, -2, $x1, 42, 1, $wood);
	# A nail head at each corner, and a missing plank chip at one.
	for my $c ([ $x0 + 1, 41 ], [ $x1 - 1, 41 ], [ $x0 + 1, 34 ], [ $x1 - 1, 34 ]) {
		box($c->[0], $c->[1], -3, $c->[0], $c->[1], -3, $iron);
		box($c->[0], $c->[1], 2, $c->[0], $c->[1], 2, $iron);
	}
	cutting(sub { box($x1, 33, -2, $x1, 34, 1, 'x') });
	my $red = solid(letter => 196, 40, 34);
	my @font = (
		[ '###', '.#.', '.#.', '.#.', '.#.' ],		# T
		[ '##.', '#.#', '##.', '#.#', '#.#' ],		# R
		[ '.#.', '#.#', '###', '#.#', '#.#' ],		# A
		[ '##.', '#.#', '#.#', '#.#', '##.' ],		# D
		[ '###', '.#.', '.#.', '.#.', '###' ],		# I
		[ '#..#', '##.#', '#.##', '#..#', '#..#' ],	# N
		[ '.##', '#..', '#.#', '#.#', '.##' ],		# G
	);
	# The text's first column from each side: 28 wide in a 30-wide face.
	my ($front, $back) = ($x1 - 2, $x0 + 2);
	my $u = 0;
	for my $glyph (@font) {
		for my $r (0 .. 4) {
			my @c = split //, $glyph->[$r];
			for my $i (0 .. $#c) {
				next unless $c[$i] eq '#';
				my $y = 40 - $r;
				# Front (-Z): the reader's right is -X. Back (+Z): it is +X.
				box($front - ($u + $i), $y, -3, $front - ($u + $i), $y, -3, $red);
				box($back + $u + $i, $y, 2, $back + $u + $i, $y, 2, $red);
			}
		}
		$u += length($glyph->[0]) + 1;
	}

	# What has piled up at the right post.
	part('Clutter', undef, [ 0, 0, 0 ]);
	cyl('y', 29.5, 4.5, 3.2, 0, 10, $wood);
	cyl('y', 29.5, 4.5, 3.4, 2, 2, $iron);
	cyl('y', 29.5, 4.5, 3.4, 8, 8, $iron);
	cyl('y', 29.5, 4.5, 2.8, 11, 11, mpal('lid', '7e5230', '8a5a34', '74492a'));
	for my $y (0 .. 2) { ring(25, -7, 1.5, 3.2, $y, $y, $rope) }
});
1;
