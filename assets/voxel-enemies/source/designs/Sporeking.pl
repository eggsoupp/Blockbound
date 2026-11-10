# Sporeking: a hulking mushroom titan. Glowing-spotted crimson cap with gills
# and a mycelium veil, ember eyes in the shade beneath, a ringed stalk body
# with moss and shelf fungi, long root-knuckled arms and stump legs.
use strict; use warnings;
use VoxLib;

model('Sporeking', voxel => 0.2, desc => 'Hulking mushroom titan with a glowing-spotted cap and root-knuckled arms');

color(capRed => 168, 38, 58);
color(capDeep => 104, 22, 46);
color(capLight => 214, 78, 88);
color(spot => 196, 255, 140, glow => 1);
color(gill => 232, 204, 172);
color(gillShade => 186, 148, 126);
color(stalk => 222, 212, 184);
color(stalkShade => 178, 160, 132);
color(bark => 108, 78, 58);
color(barkDark => 70, 50, 40);
color(moss => 72, 120, 52);
color(mossLight => 114, 160, 62);
color(eye => 255, 232, 120, glow => 1);
color(mouth => 40, 26, 30);
color(mycel => 238, 240, 228);
color(root => 92, 66, 50);

my $stalkTone = sub {
	my ($x, $y, $z) = @_;
	return 'bark' if $y < 19;
	return sin(atan2($z, $x) * 9) > 0.55 ? 'stalkShade' : 'stalk';
};
my $mossy = tone('moss', 'mossLight', 0.35, 2, 11);

# ---- Stalk (root): barrel trunk, annulus ring with ragged drape, moss,
# shelf fungi on the back.
part('Stalk', undef, [ 0, 22, 0 ], 'Root body');
cap([ 0, 17, 0 ], [ 0, 44, 0 ], 9.5, 8, $stalkTone, flat => 1);
ell(0, 30, 0, 10.5, 12, 9.5, $stalkTone);
cyl('y', 0, 0, 12.5, 38, 39, 'gill', inner => 7.5);
for my $k (0 .. 17) {
	my $a = $k * 3.14159265 / 9;
	my $drop = 2 + VoxLib::noise($k, 5, 2, 9) * 4;
	cap([ 11.6 * cos($a), 38, 11.6 * sin($a) ], [ 12.2 * cos($a), 38 - $drop, 12.2 * sin($a) ], 1, 0.6, $k % 2 ? 'gill' : 'gillShade');
}
for my $shelf ([ 4, 26 ], [ -3.5, 31 ], [ 2.5, 35 ]) {
	my ($sx, $sy) = @$shelf;
	masked(sub { $_[2] >= 8 }, sub { ell($sx, $sy, 8.5, 4, 1.3, 4.5, sub { $_[1] < $sy ? 'gill' : 'capLight' }) });
}

# ---- Head: shaded face block, ember eyes, slit mouth, the great cap.
part('Head', 'Stalk', [ 0, 40, 0 ], 'Neck: the face and cap nod and turn');
cap([ 0, 40, -0.5 ], [ 0, 51, -0.5 ], 8.6, 7.8, sub { $_[1] >= 48 ? 'stalkShade' : $stalkTone->(@_) }, flat => 1);
cutting(sub {
	both(sub { my $s = shift; ell($s * 3, 44.5, -9.5, 2.2, 1.7, 2) });
	box(-3, 41, -10, 3, 42, -8);
});
both(sub { my $s = shift; box($s * 2, 44, -8, $s * 4, 45, -8, q{eye}) });
box(-3, 41, -7, 3, 42, -7, 'mouth');
box($_, 42, -8, $_, 42, -8, 'gill') for (-3, -1, 1, 3);
box($_, 41, -8, $_, 41, -8, 'gill') for (-2, 0, 2);

my $top = sub { my $n = shift; 52 + 13 * sqrt(1 - $n) };
my $bot = sub { my $n = shift; 53 - 2.5 * $n };
for my $x (-21 .. 21) {
	for my $z (-19 .. 19) {
		my $n = ($x / 20.5)**2 + ($z / 18.5)**2;
		next if $n > 1;
		my ($yb, $yt) = ($bot->($n), $top->($n));
		for my $y (int($yb + 0.5) .. int($yt + 0.5)) {
			my $c;
			if ($y < $yb + 1.2) { $c = sin(atan2($z, $x) * 24) > 0 ? 'gill' : 'gillShade' }
			elsif ($n > 0.72 && $y < 55) { $c = 'capDeep' }
			elsif ($y > 62) { $c = 'capLight' }
			else { $c = 'capRed' }
			VoxLib::setv($x, $y, $z, $c);
		}
	}
}
painting(sub {
	for my $s ([ 90, 0.15 ], [ 210, 0.45 ], [ 330, 0.5 ], [ 30, 0.75 ], [ 150, 0.72 ], [ 270, 0.66 ], [ 0, 0.92 ], [ 120, 0.95 ], [ 240, 0.9 ], [ 300, 0.95 ], [ 60, 0.45 ]) {
		my ($deg, $rf) = @$s;
		my $a = $deg * 3.14159265 / 180;
		my ($x, $z) = (20.5 * $rf * cos($a), 18.5 * $rf * sin($a));
		ell($x, $top->($rf * $rf), $z, 2.4, 2.4, 2.4, 'spot');
	}
});
for my $k (0 .. 7, 10, 11) {
	my $a = ($k * 30 + 15) * 3.14159265 / 180;
	my $len = 4 + VoxLib::noise($k, 2, 7, 4) * 5;
	cap([ 19 * cos($a), 49, 17 * sin($a) ], [ 19.3 * cos($a), 49 - $len, 17.3 * sin($a) ], 0.6, 0.55, 'mycel');
}

# ---- Arms: long, reaching the ground; bark forearms, root knuckles, little
# mushrooms growing out of them.
mirror(sub {
	part(side('UpperArm'), 'Stalk', [ $S * 10, 41, 0 ], 'Shoulder');
	ell($S * 10, 41, 0, 4, 4, 4, 'stalk');
	cap([ $S * 10, 41, 0 ], [ $S * 15, 27, -1 ], 3.8, 3.2, $stalkTone);
	ell($S * 10.5, 44, 0, 3.6, 1.6, 3.6, $mossy);

	part(side('Forearm'), side('UpperArm'), [ $S * 15, 27, -1 ], 'Elbow; fist rides this part');
	cap([ $S * 15, 27, -1 ], [ $S * 16.5, 13, -3 ], 3.2, 4.2, tone('bark', 'barkDark', 0.3, 2, 13));
	ell($S * 16.5, 10, -3.5, 4.8, 4, 4.8, 'root');
	for my $k (-1 .. 1) {
		chain([ [ $S * (16.5 + $k * 2.4), 8, -6 ], [ $S * (16.8 + $k * 2.8), 4, -7.5 ], [ $S * (17 + $k * 3), 1, -6.5 ] ], [ 1.1, 0.9, 0.6 ], 'root');
	}
	cap([ $S * 18.5, 20, -2 ], [ $S * 21.5, 21.5, -2 ], 0.8, 0.7, 'stalk');
	ell($S * 22, 22.5, -2, 2.2, 1.2, 2.2, 'capRed');
	box($S * 22, 23, -2, $S * 22, 23, -2, 'spot');
	cap([ $S * 18.5, 16, 0.5 ], [ $S * 20.5, 17, 1.5 ], 0.7, 0.6, 'stalk');
	ell($S * 21, 17.8, 1.8, 1.6, 0.9, 1.6, 'capRed');
});

# ---- Legs: stump thighs and shins, root-splayed feet.
mirror(sub {
	part(side('Thigh'), 'Stalk', [ $S * 5, 18, 0 ], 'Hip');
	cap([ $S * 5, 18, 0 ], [ $S * 6, 9, -1 ], 4.6, 4.2, 'bark');

	part(side('Shin'), side('Thigh'), [ $S * 6, 9, -1 ], 'Knee; foot rides this part');
	cap([ $S * 6, 9, -1 ], [ $S * 6, 4, -1 ], 4.2, 4.4, 'barkDark');
	ell($S * 6, 2.2, -2, 5, 2.4, 6, 'root');
	for my $k (-1 .. 1) { cap([ $S * (6 + $k * 2.6), 1, -6 ], [ $S * (6 + $k * 4), 0, -10 ], 1.2, 0.6, 'root') }
});

finish();
