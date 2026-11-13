# NOT BUILT: the two cottages, taken out of the village on 2026-11-12. To bring
# one back, move this file into designs/ and place it in SpawnHub.
# ---------------------------------------------------------------- cottages

# Timber-framed plaster cottage on a cobblestone footing, door at the front
# (-Z), warm lit windows with flower boxes, a gable roof along X and a
# chimney. $roof is the roof texture, $side +1/-1 the chimney's side.
sub cottage {
	my ($id, $roofName, $side) = @_;
	asset($id, sub {
		my $cob = tex('cobblestone');
		my $plaster = tex('plaster');
		my $beam = tex('oak_plank', 0.5);
		my $door = tex('oak_plank', 0.85);
		my $lit = tex('window_lit');
		my $iron = tex('iron_dark');
		my $roof = tex($roofName);
		my $roofDark = tex($roofName, 0.75);
		my $bricks = tex('stone_bricks');
		my $leaf = tex('moss');
		my $petalR = solid(petalR => 214, 58, 62);
		my $petalY = solid(petalY => 246, 206, 70);
		my $petalB = solid(petalB => 120, 150, 236);

		# Footing and walls.
		box(-20, 0, -16, 19, 7, 15, $cob);
		box(-19, 8, -15, 18, 35, 14, $plaster);
		# Gables: triangles at the two ends, up under the ridge.
		for my $y (36 .. 52) {
			my $h = 52 - $y;
			box(-19, $y, -$h - 1, 18, $y, $h, $plaster);
		}
		# Timber frame painted on the faces.
		painting(sub {
			# Corner posts only, so the gable ends stay plaster.
			for my $xr ([ -20, -17 ], [ 16, 19 ]) {
				for my $zr ([ -16, -13 ], [ 12, 15 ]) { box($xr->[0], 8, $zr->[0], $xr->[1], 35, $zr->[1], $beam) }
			}
			# Gable timbers: a king post and the rafters' edge.
			box(-20, 36, -1, -19, 52, 0, $beam); box(18, 36, -1, 19, 52, 0, $beam);
			box(-20, 8, -16, 19, 8, 15, $beam);
			box(-20, 21, -16, 19, 22, 15, $beam);
			box(-20, 35, -16, 19, 35, 15, $beam);
			for my $x (-10, 9) { box($x, 8, -16, $x, 35, -15, $beam); box($x, 8, 14, $x, 35, 15, $beam) }
			for my $z (-6, 5) { box(-20, 8, $z, -19, 35, $z, $beam); box(18, 8, $z, 19, 35, $z, $beam) }
			# Braces in the upper panels.
			for my $i (0 .. 11) {
				box(-17 + $i, 23 + $i, -16, -17 + $i, 23 + $i, -15, $beam);
				box(16 - $i, 23 + $i, -16, 16 - $i, 23 + $i, -15, $beam);
				box(-17 + $i, 23 + $i, 14, -17 + $i, 23 + $i, 15, $beam);
				box(16 - $i, 23 + $i, 14, 16 - $i, 23 + $i, 15, $beam);
			}
		});
		# Door, frame, hinges, knob, step.
		box(-4, 1, -17, 3, 26, -16, $beam);
		box(-3, 1, -18, 2, 25, -17, $door);
		for my $x (-3, 0) { box($x, 1, -18, $x, 25, -18, tex('oak_plank', 0.7)) }
		box(-3, 6, -19, 0, 6, -19, $iron); box(-3, 20, -19, 0, 20, -19, $iron);
		box(1, 13, -19, 1, 13, -19, tex('gold'));
		box(-5, 0, -21, 4, 0, -17, $cob);
		# Windows: lit panes, oak frames and crosses, flower boxes.
		my $window = sub {
			my ($axis, $a0, $a1, $face, $out) = @_;
			my $w = sub { my ($u0, $y0, $u1, $y1, $c, $f) = @_; $axis eq 'z' ? box($u0, $y0, $f, $u1, $y1, $f, $c) : box($f, $y0, $u0, $f, $y1, $u1, $c) };
			$w->($a0 - 1, 13, $a1 + 1, 25, $beam, $face);
			$w->($a0, 14, $a1, 24, $lit, $face + $out);
			$w->(int(($a0 + $a1) / 2), 14, int(($a0 + $a1) / 2), 24, $beam, $face + $out);
			$w->($a0, 19, $a1, 19, $beam, $face + $out);
			$w->($a0 - 1, 11, $a1 + 1, 12, $beam, $face + $out);
			$w->($a0 - 1, 11, $a1 + 1, 12, $beam, $face + 2 * $out);
			for my $u ($a0 .. $a1) {
				my $c = ragged($u, 13, $face, 2) < 0.4 ? $leaf : (($petalR, $petalY, $petalB)[ $u % 3 ]);
				$w->($u, 13, $u, 13, $c, $face + 2 * $out);
				$w->($u, 14, $u, 14, $leaf, $face + 2 * $out) if ragged($u, 14, $face, 2) < 0.3;
			}
		};
		$window->('z', -15, -9, -16, -1);
		$window->('z', 8, 14, -16, -1);
		$window->('z', -4, 3, 15, 1);
		$window->('x', -4, 3, -20, -1);
		$window->('x', -4, 3, 19, 1);
		hitbox('BodyGlow', 'none');

		# Roof: gable along X, overhanging, ridge capped.
		part('Roof', undef, [ 0, 0, 0 ]);
		for my $z (-21 .. 20) {
			my $d = abs($z + 0.5);
			my $y = 34 + int(20.5 - $d);
			my $c = ($y % 3 == 0) ? $roofDark : $roof;
			box(-23, $y, $z, 22, $y + 1, $z, $c);
		}
		box(-23, 55, -1, 22, 55, 0, $roofDark);
		box(-23, 34, -21, 22, 34, -21, $roofDark);
		box(-23, 34, 20, 22, 34, 20, $roofDark);

		part('Chimney', undef, [ 0, 0, 0 ]);
		my $cx = $side > 0 ? 10 : -16;
		box($cx, 36, 4, $cx + 5, 62, 9, $bricks);
		box($cx - 1, 60, 3, $cx + 6, 61, 10, tex('stone_bricks', 0.8));
		box($cx + 1, 62, 5, $cx + 4, 62, 8, tex('coal_bed'));
	});
}

cottage('CottageThatch', 'straw', 1);
cottage('CottageTile', 'roof_tile', -1);
