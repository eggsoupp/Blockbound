# The cave decorations of CaveDecorConfig, one cave() per type, one model
# per height it can grow to. Coordinates are cell-centred (see CaveKit):
# dx, dz from -7.5 to 7.5, y from 0 up; $TOP is the highest row.
use strict; use warnings;
use POSIX qw(floor);
use VoxLib;
use DecorKit;
use CaveKit;

# ---------------------------------------------------------------- palettes
# Recoloured block textures, so every piece speckles like the blocks round
# it. Base patterns: stone (streaks), snow (drifts), sand (grains), dirt.

DecorKit::retex(limestone      => 'stone', 'a29d93', 'b7b2a7');
DecorKit::retex(limestone_dark => 'stone', '8d8981', 'a09c93');
DecorKit::retex(cave_cap       => 'snow',  'b88b5c', 'c99d6d');
DecorKit::retex(cave_gill      => 'snow',  '8a6644', '9c7650');
DecorKit::retex(cave_stem      => 'snow',  'dcd0b4', 'e8dec6');
DecorKit::retex(glow_cap       => 'snow',  '2c7f78', '35958a');
DecorKit::retex(glow_stem      => 'snow',  'bcd8cc', 'cde6da');
DecorKit::retex(root           => 'dirt',  '6a4628', '58391f', '7a5432');
DecorKit::retex(moss           => 'grass_top', '3f5f2a', '4f7432', '466a2e');
DecorKit::retex(spore          => 'sand',  '70833a', '85983f', '5c6c2f');
DecorKit::retex(spore_rib      => 'sand',  '5c6c2f', '667838', '4f5d28');
DecorKit::retex(spore_tip      => 'snow',  'c4cf7a', 'd6df98');
DecorKit::retex(sandstone_dark => 'sandstone', 'c4ab62', 'c2a346');
DecorKit::retex(ice            => 'snow',  'a8d8f2', 'c2e6f7');
DecorKit::retex(ice_deep       => 'snow',  '84b6de', '9ac6e8');
DecorKit::retex(frost          => 'snow',  '8edcee', 'aeeaf6');
DecorKit::retex(amethyst_rock  => 'snow',  '8446c4', '9a5cdc');
DecorKit::retex(lilac          => 'snow',  'c09ae6', 'd4b6f2');
DecorKit::retex(pearl          => 'snow',  'f0d6e6', 'f9e6f0');
DecorKit::retex(pearl_shade    => 'snow',  'e0c0d6', 'e9cee0');
DecorKit::retex(corrupt_flesh  => 'snow',  '5a3276', '6c3e8c');
DecorKit::retex(corrupt_bulb   => 'snow',  '8a52b4', '9c62c6');
DecorKit::retex(corrupt_shard  => 'stone', '2c1f3e', '3b2a52');
DecorKit::retex(crimson_flesh  => 'dirt',  'a42c36', 'bc3c46', '86222c');
DecorKit::retex(crimson_vein   => 'dirt',  '5e141a', '6c181e', '501016');
DecorKit::retex(crimson_light  => 'snow',  'c44e58', 'd2646c');
DecorKit::retex(crimson_crystal=> 'snow',  '9a1c26', 'b42c36');

# The few glowing colours. Tips and gills only: never a whole piece.
sub neon_teal   { glow(neon_teal   => 40, 178, 156) }
sub neon_frost  { glow(neon_frost  => 60, 176, 222) }
sub neon_violet { glow(neon_violet => 138, 70, 214) }
sub neon_purple { glow(neon_purple => 118, 50, 190) }
sub neon_red    { glow(neon_red    => 206, 34, 48) }

sub hyp { return sqrt($_[0] * $_[0] + $_[1] * $_[1]) }

# Ribs round a vertical axis: true on eight evenly spaced meridians.
sub rib { my ($dx, $dz, $width) = @_; return cos(8 * atan2($dz, $dx)) > 1 - $width }

# A crystal: a prism of radius r up to `shoulder`, then a point at `top`.
sub crystal {
	my (%o) = @_;
	my ($r, $shoulder, $top) = @o{qw(r shoulder top)};
	my $shape = $o{shape} // 'oct';
	field($o{y0} // 0, $top, sub {
		my ($dx, $y, $dz) = @_;
		my $rr = $y <= $shoulder ? $r : 0.75 + ($r - 0.75) * ($top - $y) / ($top - $shoulder);
		return metric($shape, $dx, $dz) <= $rr + 1e-6;
	}, $o{c});
}

# Same, hanging: prism from `base` down to `shoulder`, point at `tip`.
sub hanging_crystal {
	my (%o) = @_;
	my ($r, $base, $shoulder, $tip) = @o{qw(r base shoulder tip)};
	my $shape = $o{shape} // 'diamond';
	my ($ox, $oz) = ($o{ox} // 0, $o{oz} // 0);
	field($tip, $base, sub {
		my ($dx, $y, $dz) = @_;
		my $rr = $y >= $shoulder ? $r : 0.75 + ($r - 0.75) * ($y - $tip) / ($shoulder - $tip);
		return metric($shape, $dx - $ox, $dz - $oz) <= $rr + 1e-6;
	}, $o{c});
}

# A low rubble mound for crystals to grow out of.
sub mound { my ($c, $r, $h) = @_; dome(cy => -0.5, r => $r, ry => $h + 0.5, c => $c) }

# Where a hanging piece meets the ceiling: a knob of rock that flares out
# into the ceiling over a few rows, so it reads as grown out of it.
sub ceiling_knob {
	my ($TOP, $c, $r0, $r1, $rows) = @_;
	cone(y0 => $TOP, y1 => $TOP - $rows, r0 => $r0, r1 => $r1, pow => 0.6, c => $c);
}

# Roots or veins running out across the ceiling from a hub in the middle:
# eight lines, two voxels wide, in the top row.
sub ceiling_veins {
	my ($TOP, $c, $hub) = @_;
	field($TOP, $TOP, sub {
		my ($dx, $dz) = (abs $_[0], abs $_[2]);
		return 0 if hyp($dx, $dz) > 7.4;
		return $dx <= 1 || $dz <= 1 || abs($dx - $dz) <= 1;
	}, $c);
	cone(y0 => $TOP, y1 => $TOP - 2, r0 => $hub, r1 => $hub - 0.8, c => $c);
}

# A strand through cell-centred points, radius per point.
sub strand {
	my ($pts, $r, $c) = @_;
	chain([ map { P(@$_) } @$pts ], $r, $c);
}

# The same strand on each of four orbit points: pts are given for the
# direction (1, 0) or (1, 1) and turned to the others.
sub strands4 {
	my ($dirs, $pts, $r, $c) = @_;
	for my $d (@$dirs) {
		my ($ux, $uz) = @$d;
		strand([ map { [ $_->[0] * $ux, $_->[1], $_->[0] * $uz ] } @$pts ], $r, $c);
	}
}

# ======================================================== Plains: limestone

cave('Stalagmite', biome => 'Plains', anchor => 'floor', talls => [ 1, 2 ], body => sub {
	my ($t, $H) = @_;
	my $c = tex('limestone');
	my $top = $H - ($t == 1 ? 3 : 4);
	cone(y0 => 0, y1 => $top, r0 => 5.6, r1 => 0.75, pow => 1.5, c => $c);
	cone(y0 => 0, y1 => 2, r0 => 7.2, r1 => 5.8, c => $c);
	for my $p (orbit_axis(5)) {
		cone(y0 => 0, y1 => 4 + 2 * $t, r0 => 1.6, r1 => 0.75, pow => 1.2, ox => $p->[0], oz => $p->[1], c => $c);
	}
	# Lighter drip rings, the way calcite builds up in layers.
	painting(sub {
		field(3, $top, sub { $_[1] % 5 == 0 }, tex('limestone', 1.1));
	});
});

cave('Stalactite', biome => 'Plains', anchor => 'ceiling', talls => [ 1, 2 ], body => sub {
	my ($t, $H, $TOP) = @_;
	my $c = tex('limestone_dark');
	cone(y0 => $TOP, y1 => ($t == 1 ? 2 : 3), r0 => 5.4, r1 => 0.75, pow => 1.4, c => $c);
	ceiling_knob($TOP, $c, 7.0, 5.0, 3);
	for my $p (orbit_diag(4)) {
		cone(y0 => $TOP, y1 => $TOP - 5 - 3 * $t, r0 => 1.7, r1 => 0.75, pow => 1.2, ox => $p->[0], oz => $p->[1], c => $c);
	}
	painting(sub {
		field(2, $TOP - 3, sub { ($TOP - $_[1]) % 5 == 0 }, tex('limestone_dark', 1.1));
	});
});

cave('CaveMushroom', biome => 'Plains', anchor => 'floor', talls => [1], body => sub {
	my $stem = tex('cave_stem');
	cone(y0 => 0, y1 => 9, r0 => 2.4, r1 => 1.8, c => $stem);
	cone(y0 => 0, y1 => 1, r0 => 3.2, r1 => 2.6, c => $stem);
	field(8, 14, sub {
		my ($dx, $y, $dz) = @_;
		my $d = hyp($dx, $dz) / 7.2;
		my $v = ($y - 8.4) / 5.6;
		return $d * $d + $v * $v <= 1;
	}, tex('cave_cap'));
	# Gills on the underside, round the stem.
	field(8, 8, sub { my $d = hyp($_[0], $_[2]); $d > 1.8 && $d <= 6.2 }, tex('cave_gill'));
	# A paler rim.
	painting(sub { field(9, 9, sub { hyp($_[0], $_[2]) > 5.6 }, tex('cave_cap', 1.12)) });
});

# ============================================================ Swamp: damp

cave('GlowingMushroom', biome => 'Swamp', anchor => 'floor', talls => [1], sym => 'quad', body => sub {
	my $stem = tex('glow_stem');
	my $cap = tex('glow_cap');
	# The tall one in the middle...
	cone(y0 => 0, y1 => 10, r0 => 1.9, r1 => 1.5, c => $stem);
	dome(cy => 9.6, r => 5, ry => 4, c => $cap);
	cutting(sub { field(5, 9, sub { 1 }, 'x') });
	cone(y0 => 0, y1 => 10, r0 => 1.9, r1 => 1.5, c => $stem);
	field(9, 9, sub { my $d = hyp($_[0], $_[2]); $d > 1.5 && $d <= 4.6 }, neon_teal());
	# ...and a short one either side of it.
	for my $s (1, -1) {
		my $ox = 5 * $s;
		cone(y0 => 0, y1 => 5, r0 => 1.2, r1 => 0.9, ox => $ox, c => $stem);
		field(5, 7, sub {
			my ($dx, $y, $dz) = @_;
			my $d = hyp($dx - $ox, $dz) / 2.5;
			my $v = ($y - 5) / 2.4;
			return $d * $d + $v * $v <= 1;
		}, $cap);
		field(5, 5, sub { my $d = hyp($_[0] - $ox, $_[2]); $d > 0.9 && $d <= 2.2 }, neon_teal());
	}
});

cave('HangingRoots', biome => 'Swamp', anchor => 'ceiling', talls => [ 1, 2, 3 ], body => sub {
	my ($t, $H, $TOP) = @_;
	my $bark = tex('root');
	# Roots creeping across the ceiling, mossy where they reach the rock.
	ceiling_veins($TOP, $bark, 2.6);
	painting(sub { field($TOP, $TOP, sub { hyp($_[0], $_[2]) > 5.8 }, tex('moss')) });

	# The main root, almost the full height, with rootlets drooping off it.
	cone(y0 => $TOP - 1, y1 => 2, r0 => 1.9, r1 => 0.75, pow => 0.7, c => $bark);
	for my $k (1 .. $t) {
		my $y = $TOP - 7 - ($k - 1) * 14;
		strands4([ orbit_diag(1) ], [ [ 0, $y ], [ 1.8, $y - 2 ], [ 2.6, $y - 5 ] ], [ 0.7, 0.6, 0.55 ], $bark);
	}
	# Four on the diagonals that splay out as they hang, half as long; four
	# on the axes, shorter still.
	my $mid = $TOP - int(0.3 * $H);
	my $end = $TOP - int(0.55 * $H);
	strands4([ orbit_diag(1) ], [ [ 2.2, $TOP ], [ 3.4, $mid ], [ 3.9, $end ] ], [ 1.3, 1.0, 0.6 ], $bark);
	strands4([ orbit_axis(1) ], [ [ 3.5, $TOP ], [ 5.4, $TOP - int(0.18 * $H) ], [ 5.8, $TOP - int(0.32 * $H) ] ], [ 1.0, 0.8, 0.55 ], $bark);
});

cave('SporePod', biome => 'Swamp', anchor => 'floor', talls => [1], body => sub {
	my $base = tex('spore');
	my $ribc = tex('spore_rib');
	cone(y0 => 0, y1 => 4, r0 => 2.6, r1 => 1.7, c => $ribc);
	field(2, 14, sub {
		my ($dx, $y, $dz) = @_;
		my $r = 5.3 * (1 + 0.07 * cos(8 * atan2($dz, $dx)));
		my $d = hyp($dx, $dz) / $r;
		my $v = ($y - 8.2) / 6.2;
		return $d * $d + $v * $v <= 1;
	}, sub {
		my ($x, $y, $z) = @_;
		return rib($x + 0.5, $z + 0.5, 0.25) ? $ribc->(@_) : $base->(@_);
	});
	# A pale mouth at the top that the spores puff out of.
	cutting(sub { field(13, 14, sub { hyp($_[0], $_[2]) <= 1.6 }, 'x') });
	painting(sub { field(12, 14, sub { hyp($_[0], $_[2]) <= 3.0 }, tex('spore_tip')) });
});

# ========================================================= Desert: sandstone

# Courses of sandstone: the top row of every five juts out a little.
sub sandstone_profile {
	my ($y, $span, $r0) = @_;
	my $t = $y / $span;
	my $r = 0.75 + ($r0 - 0.75) * (1 - $t)**1.15;
	$r += 0.8 if $y % 5 == 4 && $t < 0.8;
	return $r;
}

cave('SandstoneSpire', biome => 'Desert', anchor => 'floor', talls => [ 1, 2, 3 ], body => sub {
	my ($t, $H) = @_;
	my $top = $H - 2;
	field(0, $top, sub {
		my ($dx, $y, $dz) = @_;
		return metric('oct', $dx, $dz) <= sandstone_profile($y, $top, 6.0);
	}, tex('sandstone'));
	field(0, 1, sub { metric('oct', $_[0], $_[2]) <= 7.0 }, tex('sandstone'));
});

cave('SandstoneStalactite', biome => 'Desert', anchor => 'ceiling', talls => [ 1, 2 ], body => sub {
	my ($t, $H, $TOP) = @_;
	my $span = $TOP - 2;
	field(2, $TOP, sub {
		my ($dx, $y, $dz) = @_;
		return metric('oct', $dx, $dz) <= sandstone_profile($TOP - $y, $span, 5.6);
	}, tex('sandstone_dark'));
	field($TOP - 1, $TOP, sub { metric('oct', $_[0], $_[2]) <= 7.0 }, tex('sandstone_dark'));
});

cave('FossilBones', biome => 'Desert', anchor => 'floor', talls => [1], sym => 'x', body => sub {
	dome(cy => -2, r => 7.4, ry => 4.2, c => tex('sand'));
	my $bone = tex('bone');
	# A ribcage half sunk in the sand: arches across the spine, smaller
	# towards the tail (-Z), the spine along their tops.
	my @ribs = ([ -1, 6.0, 5.6 ], [ -4, 5.4, 5.0 ], [ -7, 4.4, 4.0 ]);
	for my $rib (@ribs) {
		my ($z, $rx, $ry) = @$rib;
		my @pts;
		for my $i (0 .. 12) {
			my $a = 3.14159265 * $i / 12;
			push @pts, [ $rx * cos($a) - 0.5, $ry * sin($a), $z ];
		}
		chain(\@pts, 0.6, $bone);
	}
	box(-1, $ribs[0][2], -7, 0, $ribs[0][2], 0, $bone);
	box(-1, $ribs[0][2] + 1, $_, 0, $ribs[0][2] + 1, $_, $bone) for (-6, -3, 0);
	# The skull at the +Z end, resting on the sand, with dark eye sockets.
	dome(cy => 2.6, r => 2.5, ry => 2.2, oz => 4.6, c => $bone);
	box(-2, 1, 6, 1, 2, 7, $bone);
	cutting(sub { box($_, 3, 6, $_, 3, 7, "x") for (-2, 1) });
});

# ================================================================ Snow: ice

cave('Icicle', biome => 'Snow', anchor => 'ceiling', talls => [ 1, 2, 3 ], parts => { Ice => 0.25 }, body => sub {
	my ($t, $H, $TOP) = @_;
	part('Ice', 'Body', [ 0, 0, 0 ], 'Ice');
	my $ice = tex('ice');
	# A thin sheet of ice on the ceiling that the icicles drip from.
	field($TOP, $TOP, sub { hyp($_[0], $_[2]) <= 6.8 }, $ice);
	ceiling_knob($TOP, $ice, 5.2, 3.0, 2);
	cone(y0 => $TOP, y1 => 2, r0 => 2.8, r1 => 0.75, pow => 1.1, c => $ice);
	for my $p (orbit_diag(4.5)) {
		cone(y0 => $TOP, y1 => $TOP - int(0.55 * $H), r0 => 1.6, r1 => 0.75, ox => $p->[0], oz => $p->[1], c => $ice);
	}
	for my $p (orbit_axis(6)) {
		cone(y0 => $TOP, y1 => $TOP - int(0.3 * $H), r0 => 1.2, r1 => 0.75, ox => $p->[0], oz => $p->[1], c => $ice);
	}
});

cave('IceMound', biome => 'Snow', anchor => 'floor', talls => [ 1, 2 ], parts => { Ice => 0.15 }, body => sub {
	my ($t, $H) = @_;
	part('Ice', 'Body', [ 0, 0, 0 ], 'Ice');
	my $ice = tex('ice_deep');
	# Frozen flowstone: flattened tiers of ice, each narrower than the one it
	# spilled over, with the lip of every tier a paler ice.
	my @r = $t == 1 ? (7.2, 5.4, 3.6, 2.0) : (7.2, 6.0, 4.9, 3.9, 3.0, 2.2, 1.4);
	my $step = $t == 1 ? 3.6 : 4.2;
	for my $i (0 .. $#r) {
		dome(cy => $i * $step, r => $r[$i], ry => $step * 1.25, c => $ice);
	}
	painting(sub {
		for my $i (0 .. $#r) {
			my ($cy, $r) = ($i * $step, $r[$i]);
			field($cy - 1, $cy, sub { hyp($_[0], $_[2]) > $r - 1.4 }, tex('ice'));
		}
	});
});

cave('FrostCrystal', biome => 'Snow', anchor => 'floor', talls => [1], body => sub {
	mound(tex('stone'), 6.8, 2.4);
	my $c = tex('frost');
	crystal(r => 2.4, shoulder => 9, top => 13, c => $c);
	for my $p (orbit_diag(1)) {
		cap(P(@$p[0], 1, $p->[1]), P(5 * $p->[0], 9, 5 * $p->[1]), 1.4, 0.7, $c);
	}
	painting(sub {
		field(13, 13, sub { 1 }, neon_frost());
		dome(cy => 9.5, r => 0.9, ry => 0.9, ox => 5 * $_->[0], oz => 5 * $_->[1], c => neon_frost()) for orbit_diag(1);
	});
});

# ============================================================ Hallow: crystal

cave('AmethystCrystal', biome => 'Hallow', anchor => 'floor', talls => [ 1, 2 ], body => sub {
	my ($t, $H) = @_;
	mound(tex('hallowed_stone'), 6.8, 2.4);
	my $c = tex('amethyst_rock');
	my $top = $t == 1 ? 13 : 28;
	crystal(r => 3.2, shoulder => $top - 4, top => $top, shape => 'diamond', c => $c);
	my $lean = $t == 1 ? 8 : 15;
	for my $p (orbit_axis(1)) {
		cap(P(2 * $p->[0], 1, 2 * $p->[1]), P(6 * $p->[0], $lean, 6 * $p->[1]), 1.5, 0.7, $c);
	}
	painting(sub {
		field($top, $top, sub { 1 }, neon_violet());
		dome(cy => $lean + 0.5, r => 0.9, ry => 0.9, ox => 6 * $_->[0], oz => 6 * $_->[1], c => neon_violet()) for orbit_axis(1);
	});
});

cave('AmethystStalactite', biome => 'Hallow', anchor => 'ceiling', talls => [ 1, 2, 3 ], parts => { Glass => 0.25 }, body => sub {
	my ($t, $H, $TOP) = @_;
	ceiling_knob($TOP, tex('hallowed_stone'), 6.6, 4.2, 2);
	part('Glass', 'Body', [ 0, 0, 0 ], 'Glass');
	my $c = tex('lilac');
	hanging_crystal(r => 2.8, base => $TOP - 2, shoulder => int($H * 0.45), tip => 2, c => $c);
	for my $p (orbit_diag(4)) {
		my $tip = $TOP - int(0.5 * $H);
		hanging_crystal(r => 1.7, base => $TOP - 2, shoulder => $tip + 4, tip => $tip, ox => $p->[0], oz => $p->[1], c => $c);
	}
});

cave('PearlGrowth', biome => 'Hallow', anchor => 'floor', talls => [ 1, 2 ], body => sub {
	my ($t, $H) = @_;
	my $pearl = tex('pearl');
	# A column of pearls, each a little smaller than the one beneath.
	my @r = $t == 1 ? (3.7, 3.0, 2.2) : (4.2, 3.7, 3.2, 2.7, 2.2);
	my $y = $r[0] - 0.3;
	my @centres;
	for my $i (0 .. $#r) {
		dome(cy => $y, r => $r[$i], ry => $r[$i], c => $pearl);
		push @centres, [ $y, $r[$i] ];
		$y += 0.78 * ($r[$i] + ($r[ $i + 1 ] // 0)) if $i < $#r;
	}
	dome(cy => 1.4, r => 1.9, ry => 1.9, ox => 5.2 * $_->[0], oz => 5.2 * $_->[1], c => $pearl) for orbit_axis(1);
	dome(cy => 0.8, r => 1.3, ry => 1.3, ox => 4.6 * $_->[0], oz => 4.6 * $_->[1], c => $pearl) for orbit_diag(1);
	# A soft shade on the lower part of each pearl, so the joints read.
	painting(sub {
		for (@centres) {
			my ($cy, $r) = @$_;
			field($cy - $r, $cy - 0.45 * $r, sub { 1 }, tex('pearl_shade'));
		}
	});
});

# ======================================================= Corruption: twisted

cave('CorruptedGrowth', biome => 'Corruption', anchor => 'floor', talls => [ 1, 2, 3 ], body => sub {
	my ($t, $H) = @_;
	my $slate = tex('corrupted_stone', 0.55);
	my $spike = tex('corrupted_stone', 0.72);
	my $top = $H - 2;
	my $profile = sub { 0.75 + 3.45 * (1 - $_[0] / $top)**1.3 };
	field(0, $top, sub { metric('oct', $_[0], $_[2]) <= $profile->($_[1]) }, $slate);
	field(0, 1, sub { metric('oct', $_[0], $_[2]) <= 5.6 }, $slate);
	# Thorns, alternately on the axes and the diagonals, angled upward.
	my $k = 0;
	for (my $y = 3; $y < $top - 4; $y += 6, $k++) {
		my $r = $profile->($y);
		my @dirs = $k % 2 ? orbit_diag(1 / sqrt(2)) : orbit_axis(1);
		my $reach = $r + 3.2;
		$reach = 6.4 if $reach > 6.4;
		for my $p (@dirs) {
			cap(P($p->[0] * $r * 0.5, $y, $p->[1] * $r * 0.5), P($p->[0] * $reach, $y + 3, $p->[1] * $reach), 1.0, 0.55, $spike);
		}
	}
});

cave('CorruptedTendril', biome => 'Corruption', anchor => 'ceiling', talls => [ 1, 2, 3 ], body => sub {
	my ($t, $H, $TOP) = @_;
	my $flesh = tex('corrupt_flesh');
	my $bulb = tex('corrupt_bulb');
	ceiling_veins($TOP, $flesh, 3.0);
	# Thick in the middle, swelling into knots every seven rows, ending in a bulb.
	field(4, $TOP, sub {
		my ($dx, $y, $dz) = @_;
		my $r = 1.0 + 1.2 * (($y - 4) / ($TOP - 4)) + (($TOP - $y) % 7 == 3 ? 0.7 : 0);
		return hyp($dx, $dz) <= $r;
	}, $flesh);
	dome(cy => 4, r => 2.2, ry => 2.6, c => $bulb);
	# Four more on the diagonals, curling outward, each with a bulb.
	my $end = $TOP - int(0.5 * $H);
	my $mid = $TOP - int(0.25 * $H);
	strands4([ orbit_diag(1) ], [ [ 2.0, $TOP ], [ 3.6, $mid ], [ 4.4, $end ] ], [ 1.4, 1.1, 0.8 ], $flesh);
	dome(cy => $end, r => 1.5, ry => 1.7, ox => 4.4 * $_->[0], oz => 4.4 * $_->[1], c => $bulb) for orbit_diag(1);
});

cave('CorruptedShardCluster', biome => 'Corruption', anchor => 'floor', talls => [1], body => sub {
	mound(tex('corrupted_stone', 0.7), 6.8, 2.6);
	my $c = tex('corrupt_shard');
	crystal(r => 2.6, shoulder => 8, top => 13, shape => 'diamond', c => $c);
	for my $p (orbit_diag(1)) {
		cap(P(1.5 * $p->[0], 1, 1.5 * $p->[1]), P(5.3 * $p->[0], 10, 5.3 * $p->[1]), 1.6, 0.6, $c);
	}
	for my $p (orbit_axis(1)) {
		cap(P(2 * $p->[0], 1, 2 * $p->[1]), P(6.3 * $p->[0], 5, 6.3 * $p->[1]), 1.1, 0.5, $c);
	}
	painting(sub {
		field(13, 13, sub { 1 }, neon_purple());
		dome(cy => 10.5, r => 0.9, ry => 0.9, ox => 5.3 * $_->[0], oz => 5.3 * $_->[1], c => neon_purple()) for orbit_diag(1);
	});
});

# ============================================================ Crimson: flesh

cave('CrimsonPolyp', biome => 'Crimson', anchor => 'floor', talls => [ 1, 2 ], body => sub {
	my ($t, $H) = @_;
	my $flesh = tex('crimson_flesh');
	my $vein = tex('crimson_vein');
	my $headY = $H - 5.5;
	cone(y0 => 0, y1 => 1, r0 => 4.0, r1 => 3.3, c => $flesh);
	cone(y0 => 0, y1 => $headY - 3, r0 => 2.6, r1 => 2.0, c => $flesh);
	dome(cy => 10, r => 3.2, ry => 2.8, c => $flesh) if $t == 2;
	field($headY - 4.4, $headY + 4.4, sub {
		my ($dx, $y, $dz) = @_;
		my $d = hyp($dx, $dz) / 5.2;
		my $v = ($y - $headY) / 4.4;
		return $d * $d + $v * $v <= 1;
	}, sub {
		my ($x, $y, $z) = @_;
		return rib($x + 0.5, $z + 0.5, 0.2) ? $vein->(@_) : $flesh->(@_);
	});
	# An open mouth on top, rimmed in paler flesh.
	cutting(sub { field($headY + 2, $headY + 5, sub { hyp($_[0], $_[2]) <= 1.8 }, 'x') });
	painting(sub { field($headY + 1, $headY + 5, sub { hyp($_[0], $_[2]) <= 3.0 }, tex('crimson_light')) });
});

cave('CrimsonTendril', biome => 'Crimson', anchor => 'ceiling', talls => [ 1, 2, 3 ], body => sub {
	my ($t, $H, $TOP) = @_;
	my $flesh = tex('crimson_flesh');
	my $drip = tex('crimson_light');
	ceiling_veins($TOP, tex('crimson_vein'), 3.2);
	cone(y0 => $TOP, y1 => 3, r0 => 2.4, r1 => 1.2, pow => 0.8, c => $flesh);
	dome(cy => 2.6, r => 1.8, ry => 2.2, c => $drip);
	# Four on the axes, hanging straight then hooking out, each with a drip.
	my $end = $TOP - int(0.48 * $H);
	strands4([ orbit_axis(1) ], [ [ 2.5, $TOP ], [ 4.2, $TOP - 4 ], [ 5.0, $end + 3 ], [ 5.4, $end ] ], [ 1.5, 1.3, 1.0, 0.8 ], $flesh);
	dome(cy => $end, r => 1.2, ry => 1.5, ox => 5.4 * $_->[0], oz => 5.4 * $_->[1], c => $drip) for orbit_axis(1);
	painting(sub { field(4, $TOP - 3, sub { ($TOP - $_[1]) % 6 == 0 }, tex('crimson_vein')) });
});

cave('CrimsonShardCluster', biome => 'Crimson', anchor => 'floor', talls => [1], body => sub {
	mound(tex('crimson_stone'), 6.8, 2.6);
	my $c = tex('crimson_crystal');
	crystal(r => 2.2, shoulder => 8, top => 13, c => $c);
	for my $p (orbit_axis(1)) {
		cap(P(1.5 * $p->[0], 1, 1.5 * $p->[1]), P(5.5 * $p->[0], 9, 5.5 * $p->[1]), 1.5, 0.6, $c);
	}
	for my $p (orbit_diag(1)) {
		cap(P(1.5 * $p->[0], 1, 1.5 * $p->[1]), P(4.5 * $p->[0], 5, 4.5 * $p->[1]), 1.0, 0.5, $c);
	}
	painting(sub {
		field(13, 13, sub { 1 }, neon_red());
		dome(cy => 9.5, r => 0.9, ry => 0.9, ox => 5.5 * $_->[0], oz => 5.5 * $_->[1], c => neon_red()) for orbit_axis(1);
	});
});

1;
