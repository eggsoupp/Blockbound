# Moonmoth Matriarch: a hovering moth queen with a fur mane, feathered
# antennae, black moon eyes and four great wings: lilac forewings with gold
# eyespots, pale green hindwings trailing glowing tails.
use strict; use warnings;
use VoxLib;

model('MoonmothMatriarch', voxel => 0.18, desc => 'Hovering moth queen with four eyespot wings and feathered antennae');

color(fur => 238, 232, 218);
color(furShade => 196, 186, 170);
color(body => 72, 60, 94);
color(bodyLight => 112, 98, 142);
color(antenna => 214, 192, 140);
color(feather => 238, 214, 160);
color(eyeBlack => 22, 20, 32);
color(eyeGlow => 206, 242, 255, glow => 1);
color(wingDusk => 82, 70, 132);
color(wingBase => 154, 140, 196);
color(wingEdge => 232, 222, 255);
color(hindBase => 164, 212, 198);
color(hindDusk => 88, 132, 136);
color(spotGold => 242, 202, 92);
color(spotGlow => 160, 232, 255, glow => 1);
color(claw => 40, 34, 52);

my $furry = tone('fur', 'furShade', 0.3, 2, 5);

# ---- Thorax (root): body, fur mane, four dangling legs.
part('Thorax', undef, [ 0, 38, 0 ], 'Root body: hover bob');
ell(0, 38, 0, 6, 7, 6, 'bodyLight');
ell(0, 44, -0.5, 9, 4.5, 8, $furry);
for my $k (0 .. 11) {
	my $a = $k * 3.14159265 / 6;
	ell(8.4 * cos($a), 42.5 + VoxLib::noise($k, 1, 1, 3) * 2, -0.5 + 7.6 * sin($a), 2.4, 2.2, 2.4, $furry);
}
both(sub {
	my $s = shift;
	chain([ [ $s * 3, 32, -1 ], [ $s * 6, 26, -2 ], [ $s * 5, 19, 0 ] ], 0.8, 'body');
	chain([ [ $s * 3, 32, 2 ], [ $s * 7, 25, 3 ], [ $s * 6, 18, 5 ] ], 0.8, 'body');
});

# ---- Abdomen: hangs below, glowing tip.
part('Abdomen', 'Thorax', [ 0, 32, 2 ], 'Abdomen sway');
for my $k (0 .. 5) {
	ell(0, 30 - $k * 3.4, 3 + $k * 1.6, 5 - $k * 0.55, 2.2, 4.6 - $k * 0.5, $k % 2 ? 'body' : 'bodyLight');
}
ell(0, 11, 11.5, 1.6, 1.6, 1.6, 'spotGlow');

# ---- Head: furry, big black moon eyes, curled proboscis.
part('Head', 'Thorax', [ 0, 46, -3 ], 'Neck');
ell(0, 50, -5, 5, 4.5, 4.5, $furry);
both(sub {
	my $s = shift;
	ell($s * 4, 50, -8, 2.5, 3, 2.5, 'eyeBlack');
	ell($s * 4.6, 51.2, -10, 0.9, 0.9, 0.7, 'eyeGlow');
});
chain([ [ 0, 47, -9 ], [ 0, 45, -10 ], [ 0, 44.5, -8.5 ] ], 0.6, 'antenna');

# ---- Feathered antennae.
mirror(sub {
	part(side('Antenna'), 'Head', [ $S * 2, 54, -6 ], 'Antenna sweep');
	my @pts = ([ $S * 2, 54, -6 ], [ $S * 5, 59, -8 ], [ $S * 9, 63.5, -8 ], [ $S * 14, 65.5, -5 ]);
	chain(\@pts, 0.6, 'antenna');
	for my $i (0 .. $#pts - 1) {
		my ($a, $b) = @pts[ $i, $i + 1 ];
		my @d = map { $b->[$_] - $a->[$_] } 0 .. 2;
		my $l = sqrt($d[0]**2 + $d[1]**2);
		my @perp = ($d[1] / $l, -$d[0] / $l);
		for my $t (0.15, 0.4, 0.65, 0.9) {
			my @p = map { $a->[$_] + $d[$_] * $t } 0 .. 2;
			my $len = 3 - ($i + $t) * 0.6;
			for my $sg (1, -1) {
				cap(\@p, [ $p[0] + $perp[0] * $len * $sg, $p[1] + $perp[1] * $len * $sg, $p[2] + 0.6 ], 0.55, 0.5, 'feather');
			}
		}
	}
});

# ---- Wings: flat plates with eyespots, veins and pale rims.
sub wing {
	my ($name, $pivot, $z0, $pts, $spot, $base, $dusk, $veins) = @_;
	part($name, 'Thorax', $pivot, 'Wing beat (hinge at the body)');
	my @poly = map { [ $S * $_->[0], $_->[1] ] } @$pts;
	prism('z', \@poly, $z0, $z0 + 1, sub {
		my ($x, $y) = @_;
		my $ds = sqrt((abs($x) - $spot->[0])**2 + ($y - $spot->[1])**2);
		return 'spotGlow' if $ds < $spot->[2] * 0.45;
		return 'eyeBlack' if $ds < $spot->[2] * 0.72;
		return 'spotGold' if $ds < $spot->[2];
		return 'spotGlow' if $y < 12 && abs($x) > 20;	# glowing tail tips (hindwings)
		my $d = sqrt((abs($x) - abs($pivot->[0]))**2 + ($y - $pivot->[1])**2);
		return $d < 9 ? $dusk : $base;
	});
	painting(sub { chain([ $pivot, [ $S * $_->[0], $_->[1], $z0 ] ], 0.55, $dusk) for @$veins });
	VoxLib::outline($name, 'wingEdge', 'x', 'y');
}
mirror(sub {
	wing(side('Forewing'), [ $S * 5, 42, 3 ], 3,
		[ [ 5, 44 ], [ 12, 54 ], [ 22, 62 ], [ 34, 66 ], [ 44, 64 ], [ 48, 58 ], [ 46, 50 ], [ 38, 44 ], [ 26, 40 ], [ 14, 38 ], [ 6, 40 ] ],
		[ 31, 56, 4.4 ], 'wingBase', 'wingDusk', [ [ 20, 61 ], [ 40, 63 ], [ 46, 53 ], [ 34, 43 ] ]);
	wing(side('Hindwing'), [ $S * 5, 34, 5 ], 5,
		[ [ 5, 36 ], [ 16, 37 ], [ 28, 33 ], [ 34, 26 ], [ 34, 18 ], [ 30, 13 ], [ 26, 6 ], [ 23, 0 ], [ 21, 8 ], [ 17, 16 ], [ 10, 24 ], [ 5, 30 ] ],
		[ 25, 25, 3.4 ], 'hindBase', 'hindDusk', [ [ 30, 30 ], [ 32, 19 ], [ 24, 4 ] ]);
});

# ---- Arms: thin, clawed, held forward.
mirror(sub {
	part(side('Arm'), 'Thorax', [ $S * 5, 36, -3 ], 'Shoulder');
	chain([ [ $S * 5, 36, -3 ], [ $S * 9, 29, -6 ], [ $S * 8, 23, -10 ] ], [ 1.2, 1, 0.9 ], 'body');
	cap([ $S * 8, 23, -10 ], [ $S * 7, 21, -12 ], 0.6, 0.4, 'claw');
	cap([ $S * 8.5, 23, -10 ], [ $S * 9.6, 21, -12 ], 0.6, 0.4, 'claw');
});

translate_all(0, 8, 0);
finish();
