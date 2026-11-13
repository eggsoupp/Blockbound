package VillageKit;
# Spawn-village assets on top of the decor kit (../voxel-decor/source) and
# the enemy rigs' VoxLib (../voxel-enemies/source).
#
# Same voxel as the decor: 0.25 studs, one pixel of the 16x16 block
# textures, so tex('cobblestone') reads exactly like the block. Unlike decor
# pieces these are not placeable, so there is no cell footprint.
#
# Axes: Roblox's. +X right, +Y up, FRONT = -Z (the way a Roblox model looks),
# origin = middle of the floor. Voxel i spans [i, i+1) * 0.25 studs.
#
# Per-asset extras, in studs in the same frame:
#   hitbox(Part, 'box' | 'precise' | 'none')   collision of one union
#   neon(Part, ...)                             its glow is a lamp: Neon
#   anchor(Name, x, y, z)                       named point for code (pads,
#                                               where the merchant stands...)
# Lights come from DecorKit's glowlight / flame.

use strict;
use warnings;
use Exporter 'import';
use VoxLib;
use DecorKit;

our @EXPORT = qw(asset hitbox neon anchor disc ring ragged);

my %EXTRA;
my $ID;

sub asset {
	my ($id, $body) = @_;
	$ID = $id;
	$EXTRA{$id} = { collide => {}, anchors => [] };
	my $m = DecorKit::piece($id, $body);
	$m->{extra} = $EXTRA{$id};
	return $m;
}

sub hitbox { my ($part, $mode) = @_; $EXTRA{$ID}{collide}{$part} = $mode }
# Parts whose glowing boxes are lamps: only these are Neon in Roblox. Glowing
# boxes in any other part are built as ordinary colour.
sub neon { $EXTRA{$ID}{neon}{$_} = 1 for @_ }
sub anchor { my ($name, $x, $y, $z) = @_; push @{ $EXTRA{$ID}{anchors} }, [ $name, $x, $y, $z ] }

# Flat elliptical slab: centre (cx, cz), radii rx / rz, rows y0..y1.
sub disc {
	my ($cx, $cz, $rx, $rz, $y0, $y1, $c) = @_;
	for my $x (int($cx - $rx - 1) .. int($cx + $rx + 1)) {
		for my $z (int($cz - $rz - 1) .. int($cz + $rz + 1)) {
			my $dx = ($x + 0.5 - $cx) / $rx;
			my $dz = ($z + 0.5 - $cz) / $rz;
			next if $dx * $dx + $dz * $dz > 1;
			box($x, $y0, $z, $x, $y1, $z, $c);
		}
	}
}

# Ring between radii r0 and r1 (circle), rows y0..y1.
sub ring {
	my ($cx, $cz, $r0, $r1, $y0, $y1, $c) = @_;
	for my $x (int($cx - $r1 - 1) .. int($cx + $r1 + 1)) {
		for my $z (int($cz - $r1 - 1) .. int($cz + $r1 + 1)) {
			my $d = sqrt(($x + 0.5 - $cx)**2 + ($z + 0.5 - $cz)**2);
			next if $d > $r1 || $d < $r0;
			box($x, $y0, $z, $x, $y1, $z, $c);
		}
	}
}

# Deterministic 0..1 noise for ragged edges.
sub ragged { return VoxLib::noise($_[0], $_[1], $_[2], $_[3] // 5) }

1;
