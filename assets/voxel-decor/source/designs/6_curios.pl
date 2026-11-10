# Curios: odd, fun pieces for players to come across. Every one fits its
# footprint exactly (cells(w, h, d) = 4-stud grid cells).
use strict; use warnings;
use VoxLib; use DecorKit;
use POSIX qw(floor);

# Picker that keeps `c` in a fraction of 2-voxel cells and leaves the rest.
sub spots { my ($c, $chance, $seed) = @_; return sub { VoxLib::cellnoise($_[0], $_[1], $_[2], 2, $seed // 5) < $chance ? (ref $c eq 'CODE' ? $c->(@_) : $c) : undef } }

# ----------------------------------------------------------------- seats

piece('MushroomChair', sub {
	my $stem = tex('wax');
	my $cap = tex('mushroom');
	my $spot = tex('wool');
	cyl('y', -0.5, -0.5, 3, 0, 7, $stem);
	cyl('y', -0.5, -0.5, 4, 0, 0, $stem);
	cyl('y', -0.5, -0.5, 7.6, 8, 9, $cap);
	cyl('y', -0.5, -0.5, 6.4, 10, 10, $cap);
	painting(sub { cyl('y', -0.5, -0.5, 7.6, 8, 10, spots($spot, 0.22, 3)) });
	# A small mushroom grows up behind as the backrest.
	cap([ -0.5, 10, -6 ], [ -0.5, 13, -6 ], 1.2, 1.0, $stem);
	ell(-0.5, 14, -6, 5.4, 1.8, 1.8, $cap);
	painting(sub { ell(-0.5, 14, -6, 5.4, 1.8, 1.8, spots($spot, 0.25, 9)) });
	seat(0, 2.75, 0.3, 2.6, 2.4);
	surface(2.75);
});

piece('FrogStool', sub {
	my $frog = tex('frog');
	ell(-0.5, 4, -0.5, 7.6, 5, 7.4, $frog);
	cutting(sub { box(-8, 8, -8, 7, 15, 7, 'x') });
	box(-6, 7, -6, 5, 7, 5, tex('frog', 1.15));		# lighter back = the seat
	for my $x (-4, 3) {
		ell($x, 8.5, 4, 2, 2, 2, $frog);
		box($x - ($x < 0 ? 0 : 1), 8, 6, $x - ($x < 0 ? 0 : 1) + 1, 9, 6, tex('wool'));
		box($x - ($x < 0 ? 0 : 1) + ($x < 0 ? 1 : 0), 9, 7, $x - ($x < 0 ? 0 : 1) + ($x < 0 ? 1 : 0), 9, 7, solid(pupil => 20, 20, 24));
		box($x - 2, 0, 4, $x + 2, 1, 7, tex('frog', 0.85));	# front feet
	}
	box(-4, 4, 7, 3, 4, 7, tex('frog', 0.6));			# mouth
	seat(0, 2, 0, 2.6, 2.6);
	surface(2);
});

piece('PumpkinSeat', sub {
	my $pumpkin = tex('pumpkin');
	ell(-0.5, 4.5, -0.5, 7.6, 5.5, 7.6, $pumpkin);
	cutting(sub { box(-8, 9, -8, 7, 15, 7, 'x') });
	cyl('y', -0.5, -0.5, 6, 8, 8, tex('pumpkin', 1.2));
	# Leafy curl at the back and a short stem.
	box(-1, 9, -6, 0, 11, -5, tex('bark'));
	box(-3, 9, -5, -2, 9, -2, tex('frog'));
	seat(0, 2.25, 0, 2.8, 2.8);
	surface(2.25);
});

piece('CloudCushion', sub {
	my $cloud = tex('cloud');
	ell(-0.5, 4, -0.5, 7.5, 4, 6.8, $cloud);
	ell(-4, 7, -3, 4, 3.5, 4.5, $cloud);
	ell(3, 7, -3, 4, 3.5, 4.5, $cloud);
	ell(-0.5, 9, -5.5, 5.5, 4.5, 2.4, $cloud);
	ell(-5, 3, 3, 2.6, 3, 3.5, $cloud);
	ell(4, 3, 3, 2.6, 3, 3.5, $cloud);
	seat(0, 2, 0.6, 2.6, 2.4);
});

piece('Hammock', sub {
	cells(2, 1, 1);
	my $bark = tex('bark');
	for my $x (-8, 22) { box($x, 0, -1, $x + 1, 15, 0, $bark); box($x - ($x < 0 ? 0 : 0), 15, -2, $x + 1, 15, 1, $bark) }
	my @stripe = (tex('red_cloth'), tex('wool'), tex('blue_cloth'));
	for my $x (-4 .. 19) {
		my $t = ($x - 7.5) / 12.5;
		my $y = floor(5 + 4 * $t * $t + 0.5);
		box($x, $y, -4, $x, $y, 3, $stripe[ floor(($x + 4) / 3) % 3 ]);
		box($x, $y + 1, -4, $x, $y + 1, -4, $stripe[ floor(($x + 4) / 3) % 3 ]);
		box($x, $y + 1, 3, $x, $y + 1, 3, $stripe[ floor(($x + 4) / 3) % 3 ]);
	}
	my $rope = tex('straw', 0.8);
	cap([ -6, 13, -0.5 ], [ -4, 9, -0.5 ], 0.5, 0.5, $rope);
	cap([ 21, 13, -0.5 ], [ 19, 9, -0.5 ], 0.5, 0.5, $rope);
	seat(2, 1.6, 0, 4, 1.8);
});

piece('MelonStool', sub {
	my $rind = tex('melon_rind');
	cyl('y', -0.5, -0.5, 7.6, 0, 7, $rind);
	cyl('y', -0.5, -0.5, 7.6, 8, 8, tex('wool'));
	cyl('y', -0.5, -0.5, 6.8, 8, 8, tex('melon'));
	painting(sub { cyl('y', -0.5, -0.5, 6, 8, 8, spots(solid(seed => 30, 26, 24), 0.12, 13)) });
	seat(0, 2.25, 0, 2.8, 2.8);
	surface(2.25);
});

# ----------------------------------------------------------------- lights

piece('Cauldron', sub {
	my $iron = tex('iron_dark');
	ell(-0.5, 7, -0.5, 7.6, 7, 7.6, $iron);
	cutting(sub { box(-8, 12, -8, 7, 15, 7, 'x'); cyl('y', -0.5, -0.5, 6, 9, 11, 'x') });
	cyl('y', -0.5, -0.5, 6, 9, 9, tex('potion'));
	cyl('y', -0.5, -0.5, 7.6, 11, 11, tex('iron'), inner => 6);
	for my $b ([ -2, 1 ], [ 2, -2 ], [ 0, 3 ]) { box($b->[0], 10, $b->[1], $b->[0], 10, $b->[1], tex('potion', 1.1)) }
	for my $a (0 .. 2) { my $t = $a * 2.094; box(floor(sin($t) * 5), 0, floor(cos($t) * 5), floor(sin($t) * 5), 1, floor(cos($t) * 5), $iron) }
	glowlight(0, 2.6, 0, 16, '7aff6a');
});

piece('CrystalCluster', sub {
	my $rock = tex('stone');
	ell(-0.5, 0, -0.5, 7.6, 3, 7.6, $rock);
	my $c = tex('amethyst');
	cap([ -0.5, 1, -0.5 ], [ 0, 15, -1 ], 2.6, 0.8, $c);
	cap([ -3, 1, 2 ], [ -6.5, 11, 4 ], 1.8, 0.6, $c);
	cap([ 2, 1, -3 ], [ 6, 12, -6 ], 1.8, 0.6, $c);
	cap([ 3, 1, 3 ], [ 6, 8, 6 ], 1.4, 0.5, $c);
	cap([ -3, 1, -3 ], [ -6, 9, -7 ], 1.4, 0.5, $c);
	glowlight(0, 2, 0, 18, 'b070ff');
});

piece('FairyLantern', sub {
	my $lid = tex('oak_plank', 0.62);
	cyl('y', -0.5, -0.5, 6.4, 0, 0, $lid);
	cyl('y', -0.5, -0.5, 7.4, 12, 13, $lid);
	cyl('y', -0.5, -0.5, 3, 14, 14, $lid);
	box(-1, 15, -4, 0, 15, 3, tex('bark'));
	my $fly = tex('firefly');
	for my $f ([ -3, 3, 1 ], [ 2, 5, -2 ], [ -1, 8, 3 ], [ 3, 9, 2 ], [ -4, 7, -3 ], [ 0, 4, -4 ], [ 1, 10, 0 ], [ -2, 6, 0 ]) {
		box(@$f, @$f, $fly);
	}
	part('Glass', 'Body', [ 0, 0, 0 ], 'Glass');
	cyl('y', -0.5, -0.5, 6.4, 1, 11, solid(jar => 190, 226, 236), inner => 5.4);
	use_part('Body');
	glowlight(0, 1.6, 0, 14, 'd8ff60');
});

piece('SkullCandle', sub {
	my $bone = tex('bone');
	ell(-0.5, 5, -0.5, 6.5, 5, 7, $bone);
	box(-4, 0, 2, 3, 2, 6, $bone);					# jaw
	my $dark = solid(socket => 24, 20, 22);
	for my $x (-4, 1) { box($x, 5, 5, $x + 2, 7, 7, $dark) }
	box(-1, 3, 6, 0, 4, 7, $dark);
	for my $x (-3 .. 2) { box($x, 2, 7, $x, 2, 7, $x % 2 ? $bone : $dark) }
	my $wax = tex('wax');
	cyl('y', -0.5, -0.5, 1.6, 10, 13, $wax);
	box(-3, 10, 0, -2, 10, 1, $wax); box(1, 9, -2, 2, 10, -1, $wax);
	box(-1, 14, -1, -1, 14, -1, solid(wick => 40, 34, 30));
	flame(-0.12, 3.95, -0.12, 0.7, 12);
});

piece('LavaLamp', sub {
	my $metal = tex('brass');
	cyl('y', -0.5, -0.5, 5, 0, 1, $metal);
	cyl('y', -0.5, -0.5, 4, 2, 3, $metal);
	cyl('y', -0.5, -0.5, 3, 13, 14, $metal);
	box(-1, 15, -1, 0, 15, 0, $metal);
	my $lava = tex('lava');
	ell(-0.5, 6, -0.5, 2.4, 2, 2.4, $lava);
	ell(0, 10, -1, 1.6, 1.8, 1.6, $lava);
	ell(-1, 12, 0, 1.2, 1, 1.2, $lava);
	part('Glass', 'Body', [ 0, 0, 0 ], 'Glass');
	cyl('y', -0.5, -0.5, 3.6, 4, 12, solid(lampLiquid => 240, 120, 170), inner => 2.6);
	use_part('Body');
	glowlight(0, 2.2, 0, 14, 'ff7a2a');
});

piece('GlowShroom', sub {
	cells(1, 2, 1);
	my $stem = tex('wax');
	cap([ -0.5, 0, -0.5 ], [ 0, 20, 0.5 ], 3, 2.2, $stem);
	cyl('y', -0.5, -0.5, 4, 0, 1, $stem);
	my $cap = tex('mushroom');
	ell(-0.5, 23, -0.5, 7.6, 8, 7.6, $cap);
	cutting(sub { box(-8, 15, -8, 7, 19, 7, 'x') });
	cyl('y', -0.5, -0.5, 7, 20, 20, tex('wax', 0.85));		# gills
	painting(sub { ell(-0.5, 23, -0.5, 7.6, 8, 7.6, spots(tex('shroom_glow'), 0.2, 17)) });
	cyl('y', -0.5, -0.5, 2.2, 20, 20, $stem);
	glowlight(0, 5.5, 0, 22, '4fe0c8');
});

# ----------------------------------------------------------------- furniture

piece('MushroomTable', sub {
	my $stem = tex('wax');
	cyl('y', -0.5, -0.5, 4.5, 0, 1, $stem);
	cyl('y', -0.5, -0.5, 3, 2, 10, $stem);
	cyl('y', -0.5, -0.5, 7.6, 11, 11, tex('wax', 0.85));
	cyl('y', -0.5, -0.5, 7.6, 12, 12, tex('mushroom'));
	painting(sub { cyl('y', -0.5, -0.5, 7.6, 12, 12, spots(tex('wool'), 0.2, 7)) });
	surface(3.25);
});

piece('CatBed', sub {
	my $bed = tex('red_cloth');
	cyl('y', -0.5, -0.5, 7.6, 0, 4, $bed, inner => 5.4);
	cyl('y', -0.5, -0.5, 5.6, 0, 1, tex('wool'));
	my $cat = tex('cat');
	ell(-0.5, 3.5, 0, 4.4, 2.2, 3.2, $cat);
	ell(2.5, 4, 2.5, 2.2, 2, 2, $cat);
	box(1, 6, 2, 1, 6, 2, $cat); box(4, 6, 2, 4, 6, 2, $cat);	# ears
	my $shut = solid(catEye => 60, 40, 30);
	box(1, 4, 4, 1, 4, 4, $shut); box(3, 4, 4, 3, 4, 4, $shut);
	cap([ -4, 2, 2 ], [ -1, 2, 4 ], 0.8, 0.8, tex('cat', 0.85));	# tail round the front
	painting(sub { ell(-0.5, 3.5, 0, 4.4, 2.2, 3.2, sub { $_[0] % 3 == 0 ? tex('cat', 0.8)->(@_) : undef }) });
});

piece('Fishbowl', sub {
	my $wood = tex('oak_plank', 0.62);
	box(-5, 0, -5, 4, 0, 4, $wood);
	for my $x (-5, 4) { for my $z (-5, 4) { box($x, 1, $z, $x, 4, $z, $wood) } }
	box(-5, 5, -5, 4, 5, 4, tex('oak_plank'));
	cyl('y', -0.5, -0.5, 5.8, 6, 10, tex('water'));
	cyl('y', -0.5, -0.5, 4, 6, 6, tex('sand'));
	my $fish = tex('fish');
	box(-2, 9, 0, 0, 9, 0, $fish); box(1, 9, 0, 1, 9, 0, tex('fish', 0.8)); box(-2, 9, 1, -2, 9, 1, solid(fishEye => 20, 20, 20));
	box(-3, 7, 0, -3, 8, 0, tex('frog'));
	part('Glass', 'Body', [ 0, 0, 0 ], 'Glass');
	ell(-0.5, 10, -0.5, 7.6, 5.8, 7.6, solid(bowlGlass => 196, 228, 240));
	cutting(sub { ell(-0.5, 10, -0.5, 6.6, 4.8, 6.6, 'x'); box(-8, 14, -8, 7, 15, 7, 'x') });
	cutting(sub { box(-8, 0, -8, 7, 5, 7, 'x') });
	use_part('Body');
});

piece('Piano', sub {
	cells(2, 1, 1);
	my $ebony = tex('ebony');
	box(-8, 0, -8, 23, 15, -2, $ebony);			# upright body
	box(-8, 15, -8, 23, 15, -1, tex('ebony', 1.4));
	for my $x (-8, 22) { box($x, 0, -1, $x + 1, 7, 5, $ebony) }		# cheeks
	box(-6, 6, -1, 21, 7, 4, $ebony);				# key bed
	box(-6, 8, -1, 21, 8, 4, tex('ivory'));			# white keys
	for my $x (-6 .. 21) { box($x, 8, 4, $x, 8, 4, solid(keyGap => 120, 118, 110)) if $x % 2 == 0 }
	for my $x (-5 .. 20) { my $k = ($x + 6) % 7; next if $k == 2 || $k == 6; box($x, 9, -1, $x, 9, 1, $ebony) }
	box(0, 10, -2, 15, 13, -2, tex('paper'));			# music
	box(4, 1, -1, 5, 1, 1, tex('gold')); box(10, 1, -1, 11, 1, 1, tex('gold'));
	surface(4);
});

piece('Aquarium', sub {
	cells(2, 1, 1);
	my $wood = tex('oak_plank', 0.62);
	box(-8, 0, -6, 23, 5, 5, $wood);
	box(-7, 1, 6, 22, 4, 6, tex('oak_plank'));
	box(-7, 6, -5, 22, 6, 4, tex('sand'));
	box(-7, 7, -5, 22, 14, 4, tex('water'));
	cutting(sub { box(-7, 7, -5, 22, 14, 4, 'x') });		# water is a skin, fish swim in it
	box(-7, 7, -5, 22, 14, -5, tex('water'));
	for my $s ([ -4, 3 ], [ 5, 5 ], [ 16, 4 ], [ 19, 2 ]) { box($s->[0], 7, -3, $s->[0], 7 + $s->[1], -3, tex('frog')) }
	box(8, 7, -2, 11, 8, 1, tex('cobblestone'));
	for my $f ([ -2, 11, 0, 'fish' ], [ 12, 9, 1, 'blue_cloth' ], [ 17, 12, -1, 'fish' ]) {
		my ($x, $y, $z, $t) = @$f;
		box($x, $y, $z, $x + 2, $y, $z, tex($t)); box($x + 3, $y, $z, $x + 3, $y + 1, $z, tex($t, 0.8));
	}
	part('Glass', 'Body', [ 0, 0, 0 ], 'Glass');
	box(-8, 6, -6, 23, 15, 5, solid(tankGlass => 196, 228, 240));
	cutting(sub { box(-7, 7, -5, 22, 15, 4, 'x') });
	use_part('Body');
	box(-8, 15, -6, 23, 15, -6, $wood); box(-8, 15, 5, 23, 15, 5, $wood);
});

piece('Easel', sub {
	my $wood = tex('oak_plank');
	cap([ -6, 0, 2 ], [ -2, 15, -1 ], 0.6, 0.6, $wood);
	cap([ 5, 0, 2 ], [ 1, 15, -1 ], 0.6, 0.6, $wood);
	cap([ -0.5, 0, -8 ], [ -0.5, 13, -2 ], 0.6, 0.6, $wood);
	box(-7, 4, 1, 6, 4, 2, $wood);
	# The painting: sky, sun, hills, a lake.
	box(-7, 5, 0, 6, 14, 0, tex('blue_cloth', 1.4));
	box(2, 11, 0, 4, 13, 0, tex('gold'));
	for my $x (-7 .. 6) { my $h = 7 + floor(2 * sin($x * 0.6) + 0.5); box($x, 5, 0, $x, $h, 0, tex('grass_top')) }
	box(-4, 5, 0, 1, 6, 0, tex('water'));
	box(-7, 15, 0, 6, 15, 0, tex('oak_plank', 0.62)); box(-7, 4, 0, 6, 4, 0, tex('oak_plank', 0.62));
});

piece('MagicMirror', sub {
	cells(1, 2, 1);
	my $gold = tex('gold');
	box(-6, 0, -3, 5, 1, 2, tex('oak_plank', 0.62));
	box(-1, 2, -1, 0, 4, 0, $gold);
	for my $y (5 .. 31) {
		my $t = ($y - 18) / 13.5;
		my $hw = floor(7.6 * sqrt(1 - $t * $t) + 0.5);
		next if $hw < 1;
		box(-$hw, $y, -1, $hw - 1, $y, 0, $gold);
		box(-$hw + 2, $y, 1, $hw - 3, $y, 1, tex('mirror')) if $hw > 3 && $y > 6 && $y < 30;
	}
	glowlight(0, 4.5, 0.5, 10, 'a8d4f0');
});

piece('Telescope', sub {
	my $brass = tex('brass');
	my $leg = tex('oak_plank', 0.62);
	cap([ -6, 0, 5 ], [ -0.5, 8, -0.5 ], 0.6, 0.6, $leg);
	cap([ 6, 0, 5 ], [ -0.5, 8, -0.5 ], 0.6, 0.6, $leg);
	cap([ -0.5, 0, -7 ], [ -0.5, 8, -0.5 ], 0.6, 0.6, $leg);
	cap([ -0.5, 9, 5 ], [ -0.5, 13, -5.5 ], 1.1, 2.0, $brass);
	cap([ -0.5, 8.5, 6.4 ], [ -0.5, 9, 5 ], 0.6, 0.6, tex('iron_dark'));
	box(-1, 13, -8, 0, 14, -8, tex('mirror'));
	box(-1, 8, -1, 0, 9, 0, tex('iron_dark'));
});

piece('Bathtub', sub {
	cells(2, 1, 1);
	my $tub = tex('porcelain');
	for my $x (-6 .. 21) {
		my $t = ($x - 7.5) / 14;
		my $hz = floor(7.5 * sqrt(1 - $t ** 8) + 0.5);
		box($x, 2, -$hz, $x, 10, $hz - 1, $tub);
	}
	cutting(sub { for my $x (-5 .. 20) { my $t = ($x - 7.5) / 13; my $hz = floor(6.4 * sqrt(1 - $t ** 8) + 0.5); box($x, 4, -$hz, $x, 10, $hz - 1, 'x') if $hz > 0 } });
	for my $x (-4 .. 19) { my $t = ($x - 7.5) / 13; my $hz = floor(6.4 * sqrt(1 - $t ** 8) + 0.5); box($x, 7, -$hz, $x, 7, $hz - 1, tex('water')) if $hz > 0 }
	my $gold = tex('gold');
	for my $x (-4, 18) { for my $z (-5, 4) { box($x, 0, $z, $x + 1, 1, $z, $gold) } }
	box(-8, 10, -1, -7, 13, 0, $gold); box(-7, 13, -1, -5, 13, 0, $gold);
	box(-8, 10, 2, -8, 11, 2, $gold); box(-8, 10, -3, -8, 11, -3, $gold);
	ell(10, 8, 0, 2.2, 1.6, 2, tex('cloud'));			# bubbles
	ell(3, 8, -2, 1.8, 1.4, 1.8, tex('cloud'));
	box(14, 8, 1, 15, 9, 2, tex('duck'));
});

# ----------------------------------------------------------------- curios

piece('TreasurePile', sub {
	my $gold = tex('gold');
	ell(-0.5, 0, -0.5, 7.6, 7, 7.6, $gold);
	ell(3, 0, 3, 4.6, 4, 4.6, tex('gold', 1.15));
	painting(sub { ell(-0.5, 0, -0.5, 7.6, 7, 7.6, spots(tex('gold', 1.25), 0.25, 31)) });
	my @gems = (glow(ruby => 230, 40, 70), glow(emerald => 60, 220, 120), glow(sapphire => 70, 120, 255));
	for my $g ([ -3, 6, 2, 0 ], [ 3, 5, -3, 1 ], [ 5, 3, 3, 2 ], [ -5, 3, -4, 1 ], [ 0, 4, 6, 0 ]) {
		box($g->[0], $g->[1], $g->[2], $g->[0], $g->[1], $g->[2], $gems[ $g->[3] ]);
	}
	# A crown on top, a goblet by the side.
	cyl('y', -0.5, -0.5, 2.8, 7, 8, $gold, inner => 1.8);
	for my $a (0 .. 4) { my $t = $a * 1.2566; box(floor(-0.5 + sin($t) * 2.4 + 0.5), 9, floor(-0.5 + cos($t) * 2.4 + 0.5), floor(-0.5 + sin($t) * 2.4 + 0.5), 10, floor(-0.5 + cos($t) * 2.4 + 0.5), $gold) }
	box(-1, 8, 2, -1, 8, 2, $gems[0]);
	box(-7, 0, 4, -6, 0, 5, $gold); box(-7, 1, 4, -6, 3, 5, $gold); cyl('y', -6.5, 4.5, 1.6, 4, 5, $gold);
});

piece('DragonSkull', sub {
	cells(2, 1, 2);
	my $bone = tex('bone');
	# Laid out across two cells wide and two deep, snout toward the front.
	ell(7.5, 6, -14, 7.8, 6, 8, $bone);			# cranium
	cap([ 7.5, 4, -8 ], [ 7.5, 3.5, 3.5 ], 5, 3.4, $bone);	# snout
	cap([ 7.5, 1, -8 ], [ 7.5, 1, 4 ], 4, 2.6, tex('bone', 0.85));	# jaw
	for my $s (-1, 1) {
		cap([ 7.5 + $s * 5, 9, -16 ], [ 7.5 + $s * 12, 13, -22 ], 1.8, 0.6, tex('ebony'));	# horns
		cap([ 7.5 + $s * 12, 13, -22 ], [ 7.5 + $s * 15, 15, -17 ], 0.8, 0.5, tex('ebony'));
		box(floor(7.5 + $s * 4.5) - 1, 7, -9, floor(7.5 + $s * 4.5) + 1, 9, -8, solid(eyeHole => 20, 14, 16));
		box(floor(7.5 + $s * 4.5), 8, -9, floor(7.5 + $s * 4.5), 8, -9, glow(eyeFire => 255, 60, 40));
		for my $z (-4, -1, 2, 5) { box(floor(7.5 + $s * 2.5), 1, $z, floor(7.5 + $s * 2.5), 2, $z, tex('ivory')) }
	}
	# Neck vertebrae trailing off behind.
	for my $z (-23, -21, -19) { box(6, 0, $z, 9, 2, $z, tex('bone', 0.9)) }
});

piece('SnowmanStatue', sub {
	cells(1, 2, 1);
	my $snow = tex('snow_ball');
	ell(-0.5, 7, -0.5, 7.6, 7.2, 7.6, $snow);
	ell(-0.5, 17.5, -0.5, 5.6, 5, 5.6, $snow);
	ell(-0.5, 25.5, -0.5, 4.2, 4, 4.2, $snow);
	my $coal = solid(coalButton => 34, 30, 32);
	for my $y (15, 18, 21) { box(-1, $y, 5, 0, $y, 5, $coal) }
	box(-3, 26, 3, -2, 27, 4, $coal); box(1, 26, 3, 2, 27, 4, $coal);
	cap([ -0.5, 25, 3.5 ], [ -0.5, 24.5, 7 ], 0.8, 0.4, tex('pumpkin'));
	box(-5, 21, -5, 4, 22, 4, tex('red_cloth'));
	box(2, 17, 4, 4, 21, 5, tex('red_cloth'));
	cap([ -5, 18, -0.5 ], [ -8, 23, -0.5 ], 0.6, 0.6, tex('bark'));
	cap([ 4, 18, -0.5 ], [ 7, 23, -0.5 ], 0.6, 0.6, tex('bark'));
	cyl('y', -0.5, -0.5, 4.4, 29, 29, tex('ebony'));
	cyl('y', -0.5, -0.5, 3, 30, 31, tex('ebony'));
});

piece('Beehive', sub {
	my $stand = tex('oak_plank', 0.62);
	for my $x (-6, 5) { for my $z (-6, 5) { box($x, 0, $z, $x, 2, $z, $stand) } }
	box(-7, 3, -7, 6, 3, 6, tex('oak_plank'));
	my $straw = tex('straw');
	for my $y (4 .. 15) {
		my $r = 7.4 * sqrt(1 - (($y - 4) / 12.2) ** 2);
		cyl('y', -0.5, -0.5, $r, $y, $y, $y % 2 ? $straw : tex('straw', 0.8));
	}
	box(-1, 4, 6, 0, 6, 7, solid(hiveDoor => 40, 26, 14));
	box(2, 7, 6, 3, 9, 7, tex('honey'));
	box(3, 4, 7, 3, 6, 7, tex('honey'));
});

piece('Tent', sub {
	cells(2, 1, 2);
	my $canvas = tex('canvas');
	# An A-frame two cells wide and two deep, walls two voxels thick so the
	# slope has no gaps, open at the front.
	my $half = sub { 16 * (1 - $_[0] / 15) };
	for my $y (0 .. 14) {
		my $hw = $half->($y);
		box(7.5 - $hw + 0.5, $y, -24, 7.5 + $hw - 0.5, $y, 7, $canvas);
	}
	cutting(sub {
		for my $y (0 .. 13) {
			my $hw = $half->($y) - 2.5;
			box(7.5 - $hw + 0.5, $y, -22, 7.5 + $hw - 0.5, $y, 7, 'x') if $hw >= 1;
		}
	});
	# The open front shows a dark inside.
	my $dark = solid(tentDark => 46, 36, 28);
	for my $y (0 .. 12) {
		my $hw = $half->($y) - 2.5;
		box(7.5 - $hw + 0.5, $y, -22, 7.5 + $hw - 0.5, $y, -22, $dark) if $hw >= 1;
	}
	box(-5, 0, -21, 20, 0, 3, tex('red_cloth', 0.7));		# a blanket on the floor
	box(7, 15, -24, 8, 15, 7, tex('bark'));				# ridge
	box(-8, 0, -24, -8, 1, -24, tex('bark')); box(23, 0, -24, 23, 1, -24, tex('bark'));
	box(-8, 0, 7, -8, 1, 7, tex('bark')); box(23, 0, 7, 23, 1, 7, tex('bark'));
});

piece('ArmorStand', sub {
	cells(1, 2, 1);
	my $wood = tex('oak_plank', 0.62);
	my $iron = tex('iron');
	my $dark = tex('iron_dark');
	box(-6, 0, -6, 5, 1, 5, $wood);
	box(-1, 2, -1, 0, 8, 0, $wood);
	for my $x (-3, 2) { box($x - 1, 2, -2, $x + 1, 11, 1, $iron) }		# greaves
	box(-4, 12, -2, 3, 14, 1, $dark);						# belt
	box(-5, 15, -3, 4, 22, 2, $iron);						# breastplate
	box(-1, 16, 3, 0, 21, 3, tex('gold'));
	for my $x (-8, 6) { box($x, 19, -3, $x + 1, 22, 2, $dark); box($x, 13, -2, $x + 1, 18, 1, $iron) }	# pauldrons, arms
	box(-3, 23, -3, 2, 28, 2, $iron);						# helm
	box(-2, 25, 3, 1, 25, 3, $dark);						# visor slit
	box(-1, 29, -3, 0, 31, 2, tex('red_cloth'));			# plume
	box(6, 2, 2, 7, 12, 3, tex('blue_cloth'));				# shield on the right
	box(6, 5, 3, 7, 8, 4, tex('gold'));
});

piece('TotemPole', sub {
	cells(1, 2, 1);
	my $wood = tex('oak_plank');
	box(-5, 0, -5, 4, 25, 4, $wood);
	my @paint = (tex('red_cloth'), tex('blue_cloth'), tex('green_cloth'));
	for my $i (0 .. 2) {
		my $y = 2 + $i * 8;
		my $p = $paint[$i];
		box(-5, $y + 6, 5, 4, $y + 6, 5, $p);			# brow
		box(-4, $y + 4, 5, -2, $y + 5, 6, tex('wool')); box(1, $y + 4, 5, 3, $y + 5, 6, tex('wool'));
		box(-3, $y + 4, 6, -3, $y + 4, 7, solid(pupilT => 20, 20, 24)); box(2, $y + 4, 6, 2, $y + 4, 7, solid(pupilT => 20, 20, 24));
		box(-1, $y + 1, 5, 0, $y + 3, 7, $p);			# nose / beak
		box(-3, $y, 5, 2, $y, 6, tex('gold'));			# mouth
	}
	# Spread wings and a head at the top.
	box(-8, 22, -2, 7, 24, 1, $paint[1]);
	box(-8, 25, -1, -6, 26, 0, $paint[1]); box(5, 25, -1, 7, 26, 0, $paint[1]);
	box(-3, 26, -3, 2, 30, 2, $wood);
	box(-1, 27, 3, 0, 28, 6, tex('gold'));
	box(-3, 31, -2, 2, 31, 1, $paint[0]);
});

piece('GiantRubberDuck', sub {
	my $duck = tex('duck');
	ell(-0.5, 5, -2, 7.6, 5, 6, $duck);
	ell(-0.5, 11, 3, 4.4, 4.2, 4, $duck);
	cap([ -0.5, 7, -6 ], [ -0.5, 10, -6.4 ], 2, 1, $duck);		# tail
	box(-3, 9, 7, 2, 10, 7, tex('pumpkin'));				# beak
	my $eye = solid(duckEye => 20, 20, 24);
	box(-4, 12, 5, -3, 13, 6, $eye); box(2, 12, 5, 3, 13, 6, $eye);
	box(-3, 13, 6, -3, 13, 6, tex('wool')); box(3, 13, 6, 3, 13, 6, tex('wool'));
	for my $x (-8, 7) { ell($x - ($x < 0 ? -1 : 1), 6, -2, 1.5, 2.6, 4, tex('duck', 0.9)) }
});

piece('TeddyBear', sub {
	my $fur = tex('fur');
	my $light = tex('fur', 1.3);
	ell(-0.5, 5, -1, 5, 5, 4.4, $fur);					# body
	ell(-0.5, 4.5, 2, 3, 3.5, 1.6, $light);				# tummy
	ell(-0.5, 11.5, 0, 4.4, 3.8, 3.8, $fur);				# head
	for my $x (-4, 3) { ell($x, 14.4, -0.5, 1.8, 1.2, 1, $fur); box($x, 14, 0, $x, 14, 0, $light) }	# ears
	ell(-0.5, 10.5, 3.5, 1.8, 1.4, 1.2, $light);				# muzzle
	box(-1, 11, 5, 0, 11, 5, solid(bearNose => 30, 22, 20));
	box(-3, 12, 3, -3, 12, 3, solid(bearEye => 20, 20, 24)); box(2, 12, 3, 2, 12, 3, solid(bearEye => 20, 20, 24));
	for my $x (-6, 5) { ell($x, 6, 1, 1.6, 3, 1.6, $fur) }			# arms
	for my $x (-4, 3) { ell($x, 1.5, 4, 2, 1.6, 3, $fur); box($x - 1, 1, 7, $x + 1, 2, 7, $light) }	# legs
	box(-3, 8, 3, 2, 8, 4, tex('red_cloth'));				# bow
	box(-1, 8, 5, 0, 8, 5, tex('red_cloth', 0.75));
});

1;
