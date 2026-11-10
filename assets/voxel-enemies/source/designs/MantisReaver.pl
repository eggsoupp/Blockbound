# Mantis Reaver: an upright jade mantis with raised bone-edged scythes, red
# compound eyes, folded wings over a segmented abdomen and four walking legs.
use strict; use warnings;
use VoxLib;
use POSIX qw(floor);

model('MantisReaver', voxel => 0.2, desc => 'Upright jade mantis with twin raised scythes and four walking legs');

color(chitinDark => 22, 58, 48);
color(chitin => 40, 108, 78);
color(chitinLight => 92, 170, 102);
color(belly => 178, 188, 118);
color(blade => 156, 168, 150);
color(bladeDark => 96, 108, 98);
color(bladeEdge => 238, 238, 218);
color(eye => 255, 64, 56, glow => 1);
color(eyeCore => 255, 196, 120, glow => 1);
color(mandible => 44, 30, 32);
color(wing => 152, 208, 178);
color(wingVein => 70, 128, 104);

my $banded = sub { floor($_[1] / 3) % 3 == 0 ? 'chitinDark' : 'chitin' };

# ---- Thorax (root): where the walking legs meet.
part('Thorax', undef, [ 0, 22, 6 ], 'Root body');
ell(0, 22, 6, 6, 6, 9, sub { $_[1] >= 27 ? q{chitinLight} : ($_[1] <= 18 ? 'belly' : 'chitin') });

# ---- Abdomen: seven rising segments and a pointed tip.
part('Abdomen', 'Thorax', [ 0, 22, 13 ], 'Abdomen sway');
for my $k (0 .. 6) {
	my ($cy, $cz) = (22.5 + $k * 0.9, 14 + $k * 4.2);
	my ($rx, $ry) = (8 - abs($k - 2) * 0.65, 6.2 - abs($k - 2) * 0.5);
	ell(0, $cy, $cz, $rx, $ry, 2.9, sub { $_[1] < $cy - $ry * 0.35 ? 'belly' : ($k % 2 ? 'chitinDark' : 'chitin') });
}
cap([ 0, 28, 41 ], [ 0, 30, 46 ], 2, 0.5, 'chitinDark');

# ---- Wings folded over the abdomen (separate so they can flare).
mirror(sub {
	part(side('Wing'), 'Thorax', [ $S * 2, 30.5, 8 ], 'Wing flare / buzz');
	my @poly = map { [ $S * $_->[0], $_->[1] ] } ([ 1, 8 ], [ 5, 12 ], [ 8, 20 ], [ 8.5, 30 ], [ 7, 38 ], [ 4, 43 ], [ 1, 41 ], [ 0.6, 20 ]);
	for my $x (-10 .. 10) {
		for my $z (6 .. 45) {
			next unless VoxLib::inside(\@poly, $x, $z);
			my $y = floor(31 + ($z - 8) * 0.085);
			my $c = ($z % 6 == 0 || abs($x) == 4) ? 'wingVein' : 'wing';
			VoxLib::setv($x, $_, $z, $c) for ($y, $y + 1);
		}
	}
	VoxLib::outline(side('Wing'), 'wingVein', 'x', 'z');
});

# ---- Chest (prothorax): the long neck that rears up and forward.
part('Chest', 'Thorax', [ 0, 24, 0 ], 'Rear up / lean');
cap([ 0, 24, 1 ], [ 0, 40, -9 ], 4.2, 3.4, tone('chitin', 'chitinDark', 0.2, 2, 3));
cap([ 0, 25.7, 3.7 ], [ 0, 41.7, -6.3 ], 1, 0.8, 'chitinLight');

# ---- Head: wide triangle, compound eyes, mandibles, crest, antennae.
part('Head', 'Chest', [ 0, 42, -10 ], 'Neck');
ell(0, 45, -13, 6.2, 4, 3.5, sub { $_[2] <= -15 ? 'chitinLight' : 'chitin' });
both(sub {
	my $s = shift;
	ell($s * 5.6, 46.5, -13, 2.4, 3, 2.6, 'eye');
	ell($s * 6.1, 46.8, -14.8, 0.9, 1.2, 0.7, 'eyeCore');
	chain([ [ $s * 1.6, 42.5, -15 ], [ $s * 1.9, 40.5, -16.5 ], [ $s * 0.7, 39.4, -16.8 ] ], [ 1, 0.8, 0.6 ], 'mandible');
	chain([ [ $s * 1.6, 48.5, -14.5 ], [ $s * 3.5, 54, -17 ], [ $s * 7, 58, -21 ], [ $s * 11, 59, -26 ] ], [ 0.7, 0.6, 0.55, 0.5 ], 'chitinDark');
});
ell(0, 41.8, -14, 2, 1.5, 1.5, 'mandible');
cap([ 0, 48, -12 ], [ 0, 52, -9 ], 1.2, 0.4, 'chitinDark');

# ---- Raptorial arms: raised femur, then the scythe hanging forward.
mirror(sub {
	part(side('Arm'), 'Chest', [ $S * 3.6, 37, -7 ], 'Shoulder');
	ell($S * 3.8, 37, -7, 2.2, 2.5, 2.2, 'chitinDark');
	cap([ $S * 3.6, 37, -7 ], [ $S * 7, 46, -17 ], 1.9, 1.5, $banded);
	for my $t (0.3, 0.5, 0.7) {
		my @p = ($S * (3.6 + 3.4 * $t), 37 + 9 * $t, -7 - 10 * $t);
		cap(\@p, [ $p[0], $p[1] - 1.6, $p[2] - 1.6 ], 0.6, 0.4, 'chitinDark');
	}

	part(side('Scythe'), side('Arm'), [ $S * 7, 46, -17 ], 'Elbow: scythe swing');
	cap([ $S * 7, 46, -17 ], [ $S * 7, 41, -20 ], 1.9, 1.5, 'chitin');
	my @outer = ([ -16, 47 ], [ -19, 45.5 ], [ -22.5, 41 ], [ -24.6, 35 ], [ -25.6, 29 ], [ -25.2, 24 ]);
	my @inner = ([ -23.6, 27.5 ], [ -22.4, 33 ], [ -20.4, 38 ], [ -18, 41.6 ], [ -16, 43.5 ]);
	prism('x', [ @outer, @inner ], $S * 6, $S * 8, sub { $_[2] <= -22 ? 'blade' : 'bladeDark' });
	painting(sub { chain([ map { [ $S * 7, $_->[1], $_->[0] ] } @inner, [ -25.2, 24 ] ], 1.0, 'bladeEdge') });
	painting(sub { chain([ map { [ $S * 7, $_->[1], $_->[0] ] } @outer[ 2 .. 5 ] ], 0.7, 'bladeEdge') });
});

# ---- Walking legs: thigh up and out to a high knee, shin down to the foot.
mirror(sub {
	for my $leg ([ 'Fore', [ 4, 19, 2 ], [ 13, 27, -3 ], [ 19, 0, -7 ], [ 20, 0, -9.5 ] ],
		[ 'Hind', [ 4, 19, 10 ], [ 14, 27, 15 ], [ 21, 0, 22 ], [ 22, 0, 24.5 ] ]) {
		my ($n, $hip, $knee, $foot, $toe) = @$leg;
		my @h = ($S * $hip->[0], @$hip[ 1, 2 ]);
		my @k = ($S * $knee->[0], @$knee[ 1, 2 ]);
		my @f = ($S * $foot->[0], @$foot[ 1, 2 ]);
		my @t = ($S * $toe->[0], @$toe[ 1, 2 ]);
		part(side($n . 'Thigh'), 'Thorax', \@h, 'Hip');
		cap(\@h, \@k, 1.9, 1.5, $banded);
		part(side($n . 'Shin'), side($n . 'Thigh'), \@k, 'Knee');
		ell(@k, 1.7, 1.7, 1.7, 'chitinDark');
		cap(\@k, \@f, 1.4, 0.8, $banded);
		cap(\@f, \@t, 0.7, 0.5, 'chitinDark');
	}
});

finish();
