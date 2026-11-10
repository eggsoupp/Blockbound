# Abyssal Kraken: a hovering deep-sea horror. A tall violet mantle with
# glowing lure spots and fins, slit-pupil golden eyes, a hooked beak, two
# front tentacles raised to grab and four more that reach the ground.
use strict; use warnings;
use VoxLib;

model('AbyssalKraken', voxel => 0.2, desc => 'Hovering deep-sea kraken with lure spots, golden eyes and six tentacles');

color(skin => 118, 74, 170);
color(skinDark => 74, 42, 120);
color(skinLight => 168, 120, 214);
color(belly => 168, 134, 190);
color(sucker => 222, 178, 210);
color(lumen => 90, 255, 226, glow => 1);
color(eye => 255, 192, 64, glow => 1);
color(pupil => 18, 10, 22);
color(beak => 34, 28, 40);
color(fin => 150, 104, 204);

my $PI = 3.14159265;
my $mottled = sub {
	my ($x, $y, $z) = @_;
	return q(skinLight) if $z < -6 && abs($x) < 8 && $y > 46 && (int(abs($x)) % 4 == 1);
	return 'lumen' if VoxLib::noise($x, $y, $z, 11) < 0.025;
	return VoxLib::cellnoise($x, $y, $z, 3, 2) < 0.3 ? 'skinDark' : 'skin';
};
# Point at angle $deg from the front (towards +X on the right), radius $r.
sub around { my ($deg, $r, $y) = @_; my $a = $deg * $PI / 180; return [ $S * $r * sin($a), $y, -$r * cos($a) ] }

# ---- Mantle (root): tall hood leaning back, lure spots, two fins.
part('Mantle', undef, [ 0, 44, 0 ], 'Root body: hover bob / pulse');
cap([ 0, 48, 1 ], [ 0, 62, 6 ], 10.5, 9, $mottled);
cap([ 0, 62, 6 ], [ 0, 74, 13 ], 9, 3.5, $mottled);
for my $k (0 .. 9) {
	my $y = 50 + $k * 2.4;
	my $z = 1 + ($y - 48) * 0.45;
	my $r = $y < 62 ? 10.5 - ($y - 48) * 0.1 : 9 - ($y - 62) * 0.45;
	both(sub { my $s = shift; ell($s * $r * 0.75, $y, $z - $r * 0.62, 0.9, 0.9, 0.9, 'lumen') if $k % 2 == 0 });
}
both(sub {
	my $s = shift;
	prism('x', [ [ 8, 64 ], [ 16, 78 ], [ 18, 70 ], [ 14, 62 ] ], $s * 6, $s * 7, 'fin');
	prism('x', [ [ 10, 66 ], [ 15, 75 ], [ 16, 70 ], [ 13, 64 ] ], $s * 8, $s * 8, 'fin');
});

# ---- Head: eye bulbs with slit pupils, frilled brow.
part('Head', 'Mantle', [ 0, 40, -1 ], 'Head tilt');
ell(0, 38, -1, 10, 7.5, 9, $mottled);
both(sub {
	my $s = shift;
	ell($s * 8, 40, -5, 3.6, 4.2, 3.6, 'eye');
	painting(sub { box($s * 5, 39.5, -10, $s * 11, 40.5, -6, q(pupil)) });
	painting(sub { masked(sub { abs($_[0]) <= 6.5 || $_[1] >= 43.5 }, sub { ell($s * 8, 40, -5, 3.6, 4.2, 3.6, q(skinDark)) }) });
	ell($s * 7, 44.5, -5, 4, 1.4, 3, 'skinDark');	# heavy brow
});
painting(sub { box(-11, 31, -11, 11, 33, 9, 'belly') });

# ---- Beak: hooked, hidden under the head among the tentacle roots.
part('Beak', 'Head', [ 0, 31, -3 ], 'Beak snap');
cap([ 0, 32, -3 ], [ 0, 27, -5 ], 2.6, 0.9, 'beak');
cap([ 0, 27, -5 ], [ 0, 26, -3.5 ], 0.9, 0.5, 'beak');

# ---- Tentacles: upper and lower halves. Suckers on the inner side,
# lure spots near the tips.
sub tentacle {
	my ($name, $pts, $radii, $role) = @_;
	part(side($name), 'Head', $pts->[0], $role . ' (root)');
	chain([ @$pts[ 0 .. 2 ] ], [ @$radii[ 0 .. 2 ] ], $mottled);
	part(side($name . 'Tip'), side($name), $pts->[2], $role . ' (tip curl)');
	chain([ @$pts[ 2 .. $#$pts ] ], [ @$radii[ 2 .. $#$radii ] ], sub {
		my ($x, $y, $z) = @_;
		return 'lumen' if VoxLib::noise($x, $y, $z, 5) < 0.05;
		return VoxLib::cellnoise($x, $y, $z, 2, 8) < 0.3 ? 'skinDark' : 'skin';
	});
	ell(@{ $pts->[-1] }, 1.2, 1.2, 1.2, 'lumen');
}
mirror(sub {
	# Front pair: raised to grab, curling inwards at the tips.
	tentacle('FrontTentacle',
		[ around(45, 5, 32), around(60, 11, 31), around(62, 16, 39), around(56, 19, 49), around(44, 18, 57), around(30, 15, 60) ],
		[ 4.2, 3.6, 3, 2.3, 1.6, 0.9 ], 'Front grabbing tentacle');
	# Side pair: down and out to the floor, tips curled up.
	tentacle('SideTentacle',
		[ around(90, 6, 31), around(92, 14, 21), around(95, 21, 10), around(98, 26, 3), around(104, 31, 3), around(112, 32, 8) ],
		[ 4.4, 3.8, 3.1, 2.4, 1.6, 0.9 ], 'Side tentacle');
	# Back pair: trailing behind, curling sideways.
	tentacle('BackTentacle',
		[ around(145, 6, 31), around(150, 13, 21), around(155, 20, 11), around(158, 25, 3), around(150, 30, 3), around(138, 31, 7) ],
		[ 4.4, 3.8, 3.1, 2.4, 1.6, 0.9 ], 'Back tentacle');
});
# Suckers: pale studs on the underside of every tentacle.
for my $p (grep { /Tentacle/ } @{ VoxLib::finish()->{parts} }) {
	use_part($p);
	painting(sub {
		my $g = VoxLib::finish()->{grid};
		for my $k (keys %$g) {
			next unless $g->{$k}[0] eq $p;
			my ($x, $y, $z) = split /,/, $k;
			next if $g->{ "$x," . ($y - 1) . ",$z" };
			VoxLib::setv($x, $y, $z, 'sucker') if VoxLib::noise($x, $y, $z, 21) < 0.45;
		}
	});
}

finish();
