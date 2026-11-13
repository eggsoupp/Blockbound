# The Starfall Shrine: the village's wishing star. Symmetrical all round: a
# three-tier indigo dais engraved with a gold constellation circle, four
# candle obelisks on the diagonals, an octagonal moonstone pedestal with
# violet rune bands and an offering bowl, and above it a five-pointed star
# turning inside two equal gold rings, with four crystal shards circling
# below. SpawnHub puts the "Make a Wish" prompt at the WishSpot anchor (it
# opens the Starfall banner) and the sparkle fields from the VFX pack.
#
# Parts: Body (dais, pedestal, bowl, obelisks), Flames (the candle flames,
# the only Neon), Star, Rings, Shards (the last three move on the client).
use strict; use warnings;
use VoxLib; use DecorKit; use VillageKit;

sub floor_ { my $v = shift; return POSIX::floor($v) }

# A five-pointed star outline, points (x, y) around (cx, cy).
sub star_points {
	my ($cx, $cy, $ro, $ri) = @_;
	my @p;
	for my $i (0 .. 9) {
		my $a = 3.14159265 / 2 + $i * 3.14159265 / 5;
		my $r = $i % 2 ? $ri : $ro;
		push @p, [ $cx + $r * cos($a), $cy + $r * sin($a) ];
	}
	return \@p;
}

# Runs a block for each of the four quarter turns about the centre, handing
# it a function that turns (x, z) offsets into that quarter. The centre is
# the shared corner of voxels -1 and 0, so a turn is (x, z) -> (-1 - z, x).
sub fourfold {
	my ($block) = @_;
	for my $q (0 .. 3) {
		my $turn = sub {
			my ($x, $z) = @_;
			for (1 .. $q) { ($x, $z) = (-1 - $z, $x) }
			return ($x, $z);
		};
		$block->($turn);
	}
}

asset('StarfallShrine', sub {
	my $deep = pal('deep', '2f3150', '35385a', '2a2c48');
	my $indigo = pal('indigo', '44476e', '4b4e78', '3e4166');
	my $moon = pal('moon', '9196aa', '9ca1b5', '868b9f');
	my $moonDark = pal('moonD', '6c7084', '74798d', '64687b');
	my $gold = pal('gold', 'd9a63c', 'e6b84f', 'c49230');
	my $rune = solid(rune => 150, 110, 230);
	my $runeSoft = solid(runeSoft => 110, 84, 180);
	my $wax = solid(wax => 240, 230, 204);
	my $flame = glow(flame => 255, 170, 70);
	my $coin = solid(coin => 246, 200, 80);
	my $crystal = solid(crystal => 176, 150, 255);
	my $crystalPale = solid(crystalPale => 214, 200, 255);

	# ------------------------------------------------------------ dais
	disc(0, 0, 22, 22, 0, 1, $deep);
	disc(0, 0, 17.5, 17.5, 2, 3, $indigo);
	disc(0, 0, 12.5, 12.5, 4, 5, $moon);
	# Engraved constellation circle on the top tier, with eight rays across
	# the middle tier.
	ring(0, 0, 9.6, 10.6, 5, 5, $gold);
	ring(0, 0, 15.6, 16.4, 3, 3, $gold);
	fourfold(sub {
		my ($t) = @_;
		# A ray on the axis and one on the diagonal, per quarter.
		for my $r (11 .. 15) {
			my ($x, $z) = $t->(-1, -$r - 1);
			box($x, 3, $z, $x, 3, $z, $gold);
			my ($dx, $dz) = $t->(int(-$r * 0.707) - 1, int(-$r * 0.707) - 1);
			box($dx, 3, $dz, $dx, 3, $dz, $gold);
		}
		# A four-point star glyph at the end of each axis ray.
		my @glyph = ([ 0, 0 ], [ -1, 0 ], [ 1, 0 ], [ 0, -1 ], [ 0, 1 ]);
		for my $g (@glyph) {
			my ($x, $z) = $t->(-1 + $g->[0], -19 + $g->[1]);
			box($x, 1, $z, $x, 1, $z, $gold);
		}
	});

	# ------------------------------------------------------------ pedestal and bowl
	my @oct = map { my $a = $_ * 3.14159265 / 4 + 3.14159265 / 8; [ 4.8 * cos($a), 4.8 * sin($a) ] } 0 .. 7;
	prism('y', \@oct, 6, 19, $moon);
	for my $y (8, 17) { cyl('y', -0.5, -0.5, 5.2, $y, $y, $gold) }
	# Violet rune band between the gold rings, the same on every face.
	painting(sub {
		for my $y (11 .. 14) {
			box(-6, $y, -6, 5, $y, 5, sub {
				my ($x, $yy, $z) = @_;
				my $u = ($x + $z + 32) % 4;
				return ($yy == 11 || $yy == 14) ? $runeSoft : ($u == 0 ? $rune : undef);
			});
		}
	});
	disc(0, 0, 6.5, 6.5, 20, 20, $moonDark);
	for my $y (21 .. 26) {
		my $r = 5 + ($y - 21) * 0.65;
		ring(0, 0, $r - 1.6, $r, $y, $y, $y == 26 ? $gold : $moon);
	}
	disc(0, 0, 4.5, 4.5, 21, 21, $moonDark);
	# Offering coins, one per quarter, and a crystal heart in the middle.
	fourfold(sub {
		my ($t) = @_;
		my ($x, $z) = $t->(-3, -3);
		box($x, 22, $z, $x, 22, $z, $coin);
	});
	box(-1, 22, -1, 0, 23, 0, $crystal);

	# ------------------------------------------------------------ candle obelisks
	part('Flames', undef, [ 0, 0, 0 ]);
	hitbox('Flames', 'none');
	neon('Flames');
	use_part('Body');
	fourfold(sub {
		my ($t) = @_;
		# On the diagonal, 15 voxels out: cells (-12..-10) square.
		my @cells;
		for my $dx (-1 .. 1) { for my $dz (-1 .. 1) { push @cells, [ $t->(-12 + $dx, -12 + $dz) ] } }
		my ($cx, $cz) = $t->(-12, -12);
		for my $c (@cells) { box($c->[0], 4, $c->[1], $c->[0], 12, $c->[1], $moonDark) }
		for my $dx (-2 .. 2) { for my $dz (-2 .. 2) { my ($x, $z) = $t->(-12 + $dx, -12 + $dz); box($x, 13, $z, $x, 13, $z, $gold) } }
		box($cx, 9, $cz, $cx, 10, $cz, $rune);
		box($cx, 14, $cz, $cx, 16, $cz, $wax);
		use_part('Flames');
		box($cx, 17, $cz, $cx, 17, $cz, $flame);
		use_part('Body');
		glowlight(($cx + 0.5) * 0.25, 4.5, ($cz + 0.5) * 0.25, 7, 'ffb860');
	});
	anchor('WishSpot', 0, 0, -4.5);

	# ------------------------------------------------------------ the star
	part('Star', undef, [ -0.5, 37, -0.5 ]);
	hitbox('Star', 'none');
	my $core = solid(starCore => 255, 238, 176);
	my $edge = solid(starEdge => 242, 186, 74);
	prism('z', star_points(-0.5, 37, 10.5, 4.4), -2, 1, $edge);
	prism('z', star_points(-0.5, 37, 8, 3.4), -3, 2, $core);
	prism('z', star_points(-0.5, 37, 4.5, 2), -4, 3, $core);
	glowlight(0, 9.4, 0, 22, 'ffd890');
	glowlight(0, 2.5, 0, 16, 'a58cff');

	# ------------------------------------------------------------ rings
	# Two equal rings round the star's centre, one across, one front to back,
	# each with four identical beads at its quarters.
	part('Rings', undef, [ -0.5, 37, -0.5 ]);
	hitbox('Rings', 'none');
	my %done;
	my $R = 14;
	for my $t (0 .. 719) {
		my $a = $t * 3.14159265 / 360;
		my ($u, $v) = (floor_(-0.5 + $R * cos($a) + 0.5), floor_(37 + $R * sin($a) + 0.5));
		box($u, $v, -1, $u, $v, 0, $gold) unless $done{"a$u,$v"}++;
		box(-1, $v, $u, 0, $v, $u, $gold) unless $done{"b$u,$v"}++;
	}
	for my $b ([ $R, 0 ], [ -$R - 1, 0 ], [ 0, $R ], [ 0, -$R ]) {
		my ($u, $v) = @$b;
		my $x = $u == 0 ? -1 : $u;
		box($x, 36 + $v, -1, $x + 1, 37 + $v, 0, $crystalPale);
		box(-1, 36 + $v, $x, 0, 37 + $v, $x + 1, $crystalPale) if $u != 0;
	}

	# ------------------------------------------------------------ shards
	part('Shards', undef, [ -0.5, 27, -0.5 ]);
	hitbox('Shards', 'none');
	fourfold(sub {
		my ($t) = @_;
		my ($x, $z) = $t->(-1, -12);
		# A small double-pointed crystal, standing upright.
		box($x, 24, $z, $x + 0, 30, $z, $crystal);
		my ($x2, $z2) = $t->(-2, -12);
		box($x2, 25, $z2, $x2, 29, $z2, $crystal);
		my ($x3, $z3) = $t->(-1, -13);
		box($x3, 25, $z3, $x3, 29, $z3, $crystalPale);
		my ($x4, $z4) = $t->(0, -12);
		box($x4, 26, $z4, $x4, 28, $z4, $crystalPale);
	});
});
1;
