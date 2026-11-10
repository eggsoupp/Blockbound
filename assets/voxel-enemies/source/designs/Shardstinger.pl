# Shardstinger: a giant scorpion of slate shell with amethyst crystals
# growing from its back. Huge crushing pincers with a moving finger, six
# walking legs and a five-joint tail ending in a glowing crystal stinger.
use strict; use warnings;
use VoxLib;

model('Shardstinger', voxel => 0.2, desc => 'Giant crystal-backed scorpion with crushing pincers and a glowing stinger');

color(shell => 96, 88, 118);
color(shellDark => 58, 52, 76);
color(shellLight => 144, 132, 168);
color(under => 128, 112, 106);
color(crystal => 164, 100, 246);
color(crystalLight => 222, 186, 255);
color(crystalGlow => 206, 128, 255, glow => 1);
color(eye => 255, 72, 132, glow => 1);
color(claw => 26, 22, 32);

# Plated shell: a dark seam every few voxels along the given axis value.
sub plated {
	my ($seam) = @_;
	return sub {
		my ($x, $y, $z) = @_;
		return 'shellDark' if $seam->($x, $y, $z);
		return VoxLib::cellnoise($x, $y, $z, 2, 4) < 0.18 ? 'shellLight' : 'shell';
	};
}
sub crystal {
	my ($base, $tip, $r) = @_;
	cap($base, $tip, $r, 0.4, sub {
		my ($x, $y, $z) = @_;
		my $t = ($y - $base->[1]) / (($tip->[1] - $base->[1]) || 1);
		return 'crystalGlow' if $t > 0.75;
		return VoxLib::noise($x, $y, $z, 2) < 0.25 ? 'crystalLight' : 'crystal';
	});
}

# ---- Body (root): head shield and segmented back, crystal crop, eyes.
part('Body', undef, [ 0, 14, 4 ], 'Root body');
masked(sub { $_[1] >= 8 }, sub {
	ell(0, 13, 4, 10, 6.5, 15, plated(sub { $_[2] >= -4 && ($_[2] + 100) % 5 == 0 }));
	ell(0, 13, -8, 8.5, 5.5, 6, plated(sub { 0 }));
});
painting(sub { box(-11, 8, -15, 11, 10, 20, 'under') });
for my $c ([ 0, 17, 4, 0, 34, 9, 3.4 ], [ 4, 17, 2, 10, 30, 4, 2.6 ], [ -4, 17, 3, -11, 28, 7, 2.6 ], [ 2, 16, 10, 6, 28, 17, 2.3 ],
	[ -3, 16, 11, -7, 26, 17, 2.1 ], [ 5, 15, -2, 11, 24, -3, 1.9 ], [ -1, 17, -1, -2, 28, -2, 2.1 ], [ -6, 15, -4, -10, 22, -7, 1.6 ]) {
	crystal([ @$c[ 0 .. 2 ] ], [ @$c[ 3 .. 5 ] ], $c->[6]);
}
both(sub {
	my $s = shift;
	ell($s * 2, 18, -9, 1, 1, 1, 'eye');
	ell($s * 4.5, 17, -11, 0.7, 0.7, 0.7, 'eye');
	ell($s * 6, 15.5, -12, 0.6, 0.6, 0.6, 'eye');
	cap([ $s * 1.6, 11, -14 ], [ $s * 1.2, 9, -17 ], 1.2, 0.6, 'claw');	# mouthparts
});

# ---- Tail: five segments rising over the back, stinger at the end.
my @tail = ([ 0, 16, 17 ], [ 0, 24, 27 ], [ 0, 35, 32 ], [ 0, 47, 30 ], [ 0, 55, 23 ], [ 0, 57, 15 ]);
my @tr = (4.8, 4.3, 3.9, 3.5, 3.2);
for my $i (0 .. 4) {
	my ($a, $b) = @tail[ $i, $i + 1 ];
	part($i < 4 ? 'Tail' . ($i + 1) : 'Stinger', $i ? ($i < 5 ? 'Tail' . $i : undef) : 'Body', $a,
		$i < 4 ? 'Tail segment ' . ($i + 1) . ': curl' : 'Stinger strike');
	if ($i < 4) {
		my @m = map { ($a->[$_] + $b->[$_]) / 2 } 0 .. 2;
		cap($a, $b, $tr[$i] * 0.8, $tr[$i] * 0.75, 'shellDark');
		ell(@m, $tr[$i], $tr[$i], $tr[$i] * 1.15, plated(sub { 0 }));
		crystal([ $m[0], $m[1] + $tr[$i] - 1, $m[2] ], [ $m[0], $m[1] + $tr[$i] + 6 - $i, $m[2] + 2 ], 1.9 - $i * 0.2) if $i < 3;
	} else {
		ell(0, 57, 17, 4.2, 4, 4.6, plated(sub { 0 }));
		painting(sub { ell(0, 57, 17, 4.2, 4, 4.6, sub { $_[1] <= 55 ? 'crystal' : undef }) });
		cap([ 0, 56, 14 ], [ 0, 52, 8 ], 2.2, 1.2, 'crystalLight');
		cap([ 0, 52, 8 ], [ 0, 47.5, 6.5 ], 1.2, 0.4, 'crystalGlow');
		crystal([ 1, 60, 18 ], [ 3, 64, 20 ], 1);
		crystal([ -1, 60, 19 ], [ -2, 63, 22 ], 0.9);
	}
}

# ---- Pincers: arm, heavy claw with the fixed finger, moving finger.
mirror(sub {
	part(side('Arm'), 'Body', [ $S * 7, 12, -11 ], 'Arm: swing / raise');
	chain([ [ $S * 7, 12, -11 ], [ $S * 14, 15, -17 ], [ $S * 14, 15, -26 ] ], [ 2.6, 2.6, 2.4 ], plated(sub { 0 }));
	ell($S * 14, 15, -17, 3, 3, 3, 'shellDark');	# elbow knuckle

	part(side('Claw'), side('Arm'), [ $S * 14, 15, -26 ], 'Wrist');
	ell($S * 14.5, 15, -31, 5.2, 4.6, 6, plated(sub { 0 }));
	cap([ $S * 13.5, 17, -35 ], [ $S * 12, 16, -45 ], 2.6, 0.6, plated(sub { 0 }));
	cap([ $S * 12, 16, -45 ], [ $S * 11, 15, -47 ], 0.6, 0.4, 'claw');
	for my $z (-41, -38, -35) { cap([ $S * 12.6, 15, $z ], [ $S * 12.6, 13.5, $z - 0.5 ], 0.7, 0.4, 'crystalLight') }	# teeth
	crystal([ $S * 16, 18, -30 ], [ $S * 19, 26, -27 ], 2);
	crystal([ $S * 13, 18.5, -29 ], [ $S * 12, 24, -26 ], 1.5);

	part(side('ClawFinger'), side('Claw'), [ $S * 15, 13, -35 ], 'Pincer snap');
	cap([ $S * 15, 13, -35 ], [ $S * 14, 13, -44 ], 2.1, 0.6, 'shellDark');
	cap([ $S * 14, 13, -44 ], [ $S * 13, 14, -46 ], 0.6, 0.4, 'claw');
});

# ---- Legs: three per side, thigh up to the knee, then down to the tip.
mirror(sub {
	for my $l ([ 'Front', -3, -4, -9 ], [ 'Mid', 3, 2, 3 ], [ 'Hind', 9, 12, 16 ]) {
		my ($n, $z, $zk, $zf) = @$l;
		my $hip = [ $S * 8, 11, $z ];
		my $knee = [ $S * 17, 19, $zk ];
		part(side($n . 'Leg'), 'Body', $hip, "$n leg: hip");
		cap($hip, $knee, 2, 1.7, plated(sub { 0 }));
		part(side($n . 'Foot'), side($n . 'Leg'), $knee, "$n leg: knee");
		ell(@$knee, 2, 2, 2, 'shellDark');
		cap($knee, [ $S * 22, 3, $zf ], 1.7, 1, plated(sub { $_[1] == 11 }));
		cap([ $S * 22, 3, $zf ], [ $S * 23, 0, $zf ], 0.9, 0.5, 'claw');
	}
});

finish();
