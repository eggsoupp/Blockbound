# Village floor: one 4x4-stud tile per terrain block, laid on top of the
# grass. Flagstone plaza (0.5 studs thick) and packed dirt path (0.25),
# plus path edges that fray into the grass on their +X side (turn the tile
# to face the grass) and an outer corner with grass on +X and +Z.
#
# Grout and edges sit on the tile's -X / -Z rows, so tiles laid side by side
# show one grout line between them in any rotation.
use strict; use warnings;
use VoxLib; use DecorKit; use VillageKit;

sub flagstones {
	my ($mossy) = @_;
	my $grout = tex('gravel', 0.6);
	my $moss = tex('moss');
	box(-8, 0, -8, 7, 1, 7, $grout);
	my @slabs = (
		[ -7, -7, -1, -3, 1.0 ],
		[ 1, -7, 7, -1, 0.9 ],
		[ -7, -1, -4, 7, 0.94 ],
		[ -2, 1, 7, 7, 1.04 ],
		[ -3, -1, -1, -1, 0.97 ],
	);
	for my $s (@slabs) {
		my ($x0, $z0, $x1, $z1, $mul) = @$s;
		# The game's light lifts stone a lot: these read as grey slabs at noon.
		my $t = tex('stone', $mul * 0.76);
		box($x0, 0, $z0, $x1, 1, $z1, $t);
	}
	# Worn corners: a few slab corners dropped to the grout layer.
	cutting(sub { box(-7, 1, -7, -7, 1, -7, 'x'); box(7, 1, 7, 7, 1, 7, 'x'); box(1, 1, -1, 1, 1, -1, 'x') });
	return unless $mossy;
	for my $x (-8 .. 7) {
		for my $z (-8 .. 7) {
			next unless ragged($x, 7, $z, 21) < 0.33;
			# Moss creeps along the grout lines and into slab edges.
			box($x, 1, $z, $x, 1, $z, $moss) if $x == -8 || $z == -8 || $x == 0 || $z == -2 || $z == 0 || $x == -3;
		}
	}
}

asset('PlazaTile', sub { flagstones(0) });
asset('PlazaTileMoss', sub { flagstones(1) });

sub dirt_picker {
	my $dirt = tex('dirt', 0.95);
	my $gravel = tex('gravel');
	return sub { ragged($_[0], 0, $_[2], 3) < 0.13 ? $gravel->(@_) : $dirt->(@_) };
}

asset('PathTile', sub { box(-8, 0, -8, 7, 0, 7, dirt_picker()) });

# Grass on the +X side, a ragged boundary and a few tall tufts.
sub grass_side {
	my ($inGrass) = @_;
	my $grass = tex('grass_top');
	my $tuft = tex('grass_top', 0.85);
	my $dirt = dirt_picker();
	for my $x (-8 .. 7) {
		for my $z (-8 .. 7) {
			my $g = $inGrass->($x, $z);
			box($x, 0, $z, $x, 0, $z, $g ? $grass : $dirt);
			box($x, 1, $z, $x, 1, $z, $tuft) if $g && ragged($x, 9, $z, 13) < 0.09;
		}
	}
}

my $edge = sub { my ($v) = @_; return 2 + int(ragged(0, 3, $v, 4) * 3.99) - 1 };
asset('PathEdge', sub {
	grass_side(sub { my ($x, $z) = @_; return $x > $edge->($z) });
});
asset('PathCorner', sub {
	grass_side(sub { my ($x, $z) = @_; return $x > $edge->($z) || $z > $edge->($x + 40) });
});
1;
