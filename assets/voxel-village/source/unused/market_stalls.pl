# NOT BUILT: the market stalls, taken out of the village on 2026-11-12. They
# rely on mpal/hex3 from designs/4_market.pl.

# ---------------------------------------------------------------- market stalls

# A trestle table under a striped canopy, crates behind. $goods draws what
# is for sale on the table; $hang what hangs under the canopy.
sub stall {
	my ($id, $stripe, $goods, $hang) = @_;
	asset($id, sub {
		my $dark = mpal('wood', '5a3a22', '634127', '52341e');
		my $mid = mpal('mid', '8a5a34', '94633a', '7e5230');
		my $top = mpal('top', 'c8925a', 'd29c63', 'bd8752');
		my $st = mpal('stripe', @$stripe);
		my $cream = mpal('cream', 'e8dcc0', 'efe5cc', 'ddd0b2');
		my $gold = solid(gold => 236, 190, 70);

		# Table.
		box(-14, 0, -8, 13, 9, -3, $mid);
		painting(sub { box(-13, 2, -9, 12, 9, -8, $st) });
		for my $x (-13 .. 12) { box($x, 1, -9, $x, 1, -9, $gold) if $x % 3 == 0 }
		box(-15, 10, -9, 14, 10, -2, $top);
		# Crates behind.
		for my $c ([ -13, 2, 6 ], [ -5, 3, 4 ], [ 5, 2, 7 ]) {
			my ($x, $z, $h) = @$c;
			box($x, 0, $z, $x + 6, $h, $z + 5, $mid);
			box($x, $h, $z, $x + 6, $h, $z + 5, $dark);
		}
		part('Frame', undef, [ 0, 0, 0 ]);
		hitbox('Frame', 'precise');
		for my $x (-16, 14) {
			box($x, 0, -11, $x + 1, 34, -10, $dark);
			box($x, 0, 8, $x + 1, 38, 9, $dark);
		}
		box(-16, 30, -11, 15, 30, -10, $dark);
		part('Canopy', undef, [ 0, 0, 0 ]);
		hitbox('Canopy', 'none');
		for my $z (-13 .. 10) {
			my $y = 35 + int(($z + 13) * 4 / 23);
			for my $x (-18 .. 17) { box($x, $y, $z, $x, $y, $z, (int(($x + 18) / 4) % 2) ? $st : $cream) }
		}
		for my $x (-18 .. 17) {
			my $len = (($x + 18) % 4 < 2) ? 3 : 1;
			box($x, 35 - $len, -13, $x, 34, -13, (int(($x + 18) / 4) % 2) ? $st : $cream);
		}
		part('Goods', undef, [ 0, 0, 0 ]);
		hitbox('Goods', 'none');
		$goods->();
		$hang->() if $hang;
	});
}

stall('MarketStallProduce', [ 'b83a32', 'c64840', 'a8322c' ], sub {
	my $crate = mpal('crate', '8a5a34', '94633a', '7e5230');
	my $apple = mpal('apple', 'c8302c', 'd8443a', 'a82622');
	my $carrot = mpal('carrot', 'e07a24', 'ee8c34', 'c8661c');
	my $cabbage = mpal('cabbage', '6aa83c', '7cba48', '5a9432');
	my $leaf = solid(leaf => 70, 130, 50);
	my $pumpkin = mpal('pumpkin', 'e0862a', 'ec9838', 'c8701e');
	my $melon = mpal('melon', '3c8a34', '2f7a2a', '5aa848');
	# Three open crates on the table, heaped with produce.
	for my $c ([ -13, $apple ], [ -5, $carrot ], [ 3, $cabbage ]) {
		my ($x, $fill) = @$c;
		box($x, 11, -8, $x + 6, 13, -3, $crate);
		box($x + 1, 13, -7, $x + 5, 13, -4, $fill);
		ell($x + 3, 14, -5.5, 2.8, 1.4, 2, $fill);
	}
	box(-11, 15, -6, -11, 15, -6, $leaf); box(5, 16, -5, 6, 16, -5, $leaf);
	# A pumpkin and a melon at the end of the table.
	ell(11, 12.5, -6, 2.5, 2.2, 2.5, $pumpkin);
	box(11, 15, -6, 11, 15, -6, $leaf);
	ell(11, 2.5, -12, 3, 2.5, 2.5, $melon);
	ell(-12, 2, -12, 2.5, 2, 2.5, $pumpkin);
}, sub {
	# Onion strings hanging from the canopy beam.
	my $onion = solid(onion => 200, 150, 80);
	my $twine = solid(twine => 150, 116, 70);
	for my $x (-10, -2, 6) {
		box($x, 25, -10, $x, 29, -10, $twine);
		for my $y (21 .. 24) { box($x - ($y % 2), $y, -10, $x + 1 - ($y % 2), $y, -10, $onion) }
	}
});

stall('MarketStallCloth', [ '2f5aa8', '3a68b8', '284e94' ], sub {
	my @bolt = ([ 'a83a4a', 'b84858' ], [ 'e0b040', 'ecc050' ], [ '3a8a5a', '48986a' ], [ '6a4aa8', '7858b8' ], [ 'e8dcc0', 'f2e8d0' ]);
	my $i = 0;
	# Bolts of cloth lying along X, stacked two high.
	for my $row ([ 11, -7 ], [ 11, -4 ], [ 14, -6 ]) {
		my ($y, $z) = @$row;
		for my $x0 (-14, -4, 6) {
			my $c = mpal("bolt$i", @{ $bolt[ $i % @bolt ] });
			$i++;
			cyl('x', $z, $y + 1, 1.6, $x0, $x0 + 7, $c);
		}
	}
}, sub {
	# Drapes hanging behind the table.
	my @drape = ('a83a4a', 'e0b040', '3a8a5a', '6a4aa8');
	for my $k (0 .. 3) {
		my $c = solid("drape$k", hex3($drape[$k]));
		my $x = -13 + $k * 7;
		box($x, 14, 7, $x + 4, 33, 7, $c);
		box($x, 33, 6, $x + 4, 33, 8, solid(pole => 90, 58, 34));
	}
});
