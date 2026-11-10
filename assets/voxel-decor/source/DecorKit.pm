package DecorKit;
# Voxel kit for Blockbound's placeable decor, on top of the enemy rigs'
# VoxLib (assets/voxel-enemies/source).
#
# A piece is built in its grid cell's own frame, in voxels of 0.25 studs:
# a 4-stud cell is 16 voxels a side. x and z run -8..7, y runs 0..15 per
# cell (0..31 for a two-cell piece), and the FRONT is +Z: the side that
# turns to face whoever places it. Voxel i spans [i, i+1) * 0.25 studs.
#
# One voxel is one pixel of the game's 16x16 block textures, so a surface
# painted with tex('oak_plank') reads exactly like an oak plank block. The
# textures come from assets/item-icons/source/icons.txt (read out of Studio
# for the item atlas): `texture` lines and their `retex` recolours.
#
# Textured voxels are resolved after the piece is built, by which faces they
# show: a voxel seen from the front or back samples (x, y), one seen from a
# side samples (z, y), one seen only from above or below samples (x, z). So
# a plank texture runs the right way on every face.
#
# Metadata (hinge, seats, flames, glows, rungs, surface) is in studs, in the
# same cell frame, and is written to src/.../Building/DecorShapes.lua.

use strict;
use warnings;
use POSIX qw(floor);
use Exporter 'import';
use VoxLib;

our @EXPORT = qw(
	piece tex retex solid glow pal
	hinge seat flame glowlight rungs surface collide note cells
	v2s
);

my %TEX;		# key -> { pal => [[r,g,b]...], idx => [256] }
my %REG;		# colour name -> 1 (registered in the current piece)

my @PIECES;		# finished pieces, in declaration order
my $CUR;		# metadata of the piece being built

sub v2s { return $_[0] * 0.25 }

# ---------------------------------------------------------------- textures

sub hex2rgb { my $h = shift; return [ map { hex(substr($h, $_ * 2, 2)) } 0 .. 2 ] }

sub load_textures {
	my ($path) = @_;
	open my $fh, '<', $path or die "$path: $!";
	my @retex;
	while (<$fh>) {
		if (/^texture\s+(\w+)\s+([0-9a-f,]+)\s+(\d{256})/) {
			$TEX{$1} = { pal => [ map { hex2rgb($_) } split /,/, $2 ], idx => [ split //, $3 ] };
		} elsif (/^retex\s+(\w+)\s+(\w+)((?:\s+[0-9a-f]{6}=[0-9a-f]{6})*)\s*$/) {
			push @retex, [ $1, $2, $3 ];
		}
	}
	close $fh;
	for (@retex) {
		my ($new, $base, $swaps) = @$_;
		my %map = $swaps =~ /([0-9a-f]{6})=([0-9a-f]{6})/g;
		retex_hex($new, $base, \%map);
	}
}

sub retex_hex {
	my ($new, $base, $map) = @_;
	my $b = $TEX{$base} or die "retex $new: no base texture $base\n";
	my @pal = map {
		my $h = sprintf('%02x%02x%02x', @$_);
		$map->{$h} ? hex2rgb($map->{$h}) : [@$_];
	} @{ $b->{pal} };
	$TEX{$new} = { pal => \@pal, idx => $b->{idx} };
}

# A new texture from an existing pattern with a new palette: retex(name,
# base, 'rrggbb', 'rrggbb', ...) gives palette slots in order.
sub retex {
	my ($new, $base, @hex) = @_;
	my $b = $TEX{$base} or die "retex $new: no base texture $base\n";
	my @pal = map { $hex[$_] ? hex2rgb($hex[$_]) : [ @{ $b->{pal}[$_] } ] } 0 .. $#{ $b->{pal} };
	$TEX{$new} = { pal => \@pal, idx => $b->{idx} };
}

# Marks a texture as glowing (Neon in Roblox, emissive in MagicaVoxel).
sub glowtex { $TEX{$_}{glow} = 1 for @_ }

# Palette slot of a texture at (u, v), v counted down from the top row.
sub sample {
	my ($key, $u, $v) = @_;
	my $t = $TEX{$key} or die "no texture $key\n";
	return $t->{idx}[ ($v % 16) * 16 + ($u % 16) ];
}

sub texkey { my ($name, $mul) = @_; return defined $mul && $mul != 1 ? sprintf('%s~%03d', $name, $mul * 100) : $name }

# Registers a texture's palette as colours in the current piece and returns
# a colour picker for VoxLib shapes. mul darkens (<1) or lightens (>1).
sub tex {
	my ($name, $mul) = @_;
	my $t = $TEX{$name} or die "no texture $name\n";
	my $key = texkey($name, $mul);
	for my $i (0 .. $#{ $t->{pal} }) {
		my $cn = "$key.$i";
		next if $REG{$cn};
		my @c = map { my $q = int($_ * ($mul // 1) + 0.5); $q > 255 ? 255 : $q } @{ $t->{pal}[$i] };
		color($cn, @c, $t->{glow} ? (glow => 1) : ());
		$REG{$cn} = 1;
	}
	# Provisional: front-face mapping; finish() resolves by exposure.
	return sub { my ($x, $y, $z) = @_; return "$key." . sample($name, $x, 15 - $y) };
}

sub solid {
	my ($name, $r, $g, $b) = @_;
	unless ($REG{$name}) { color($name, $r, $g, $b); $REG{$name} = 1; }
	return $name;
}
sub glow {
	my ($name, $r, $g, $b) = @_;
	unless ($REG{$name}) { color($name, $r, $g, $b, glow => 1); $REG{$name} = 1; }
	return $name;
}
# Two or three solid shades scattered like a block texture: pal(name,
# 'rrggbb', 'rrggbb', ...) -> picker. Small pixel clusters, the way the
# game's own textures speckle.
sub pal {
	my ($name, @hex) = @_;
	my @names;
	for my $i (0 .. $#hex) {
		my $c = hex2rgb($hex[$i]);
		push @names, solid("$name$i", @$c);
	}
	return sub {
		my ($x, $y, $z) = @_;
		my $n = VoxLib::noise($x, $y, $z, length $name);
		my $m = VoxLib::cellnoise($x, $y, $z, 2, 11);
		return $names[0] if $n < 0.62;
		return $names[1] if @names < 3 || $m < 0.6;
		return $names[2];
	};
}

# ---------------------------------------------------------------- metadata

sub hinge { $CUR->{hinge} = [ @_ ] }
sub seat { my ($x, $y, $z, $w, $d) = @_; $CUR->{seat} = { at => [ $x, $y, $z ], size => [ $w, 0.4, $d ] } }
sub flame { my ($x, $y, $z, $size, $range) = @_; push @{ $CUR->{flames} }, { at => [ $x, $y, $z ], size => $size, range => $range } }
sub glowlight { my ($x, $y, $z, $range, $hex) = @_; push @{ $CUR->{glows} }, { at => [ $x, $y, $z ], range => $range, color => hex2rgb($hex) } }
sub rungs { push @{ $CUR->{rungs} }, [ @_ ] }		# x, y, z, w, h, d (studs, centre + size)
sub surface { $CUR->{surface} = shift }
sub collide { $CUR->{collide} = shift }			# 'box' (default) | 'none'
sub note { $CUR->{note} = shift }
# Footprint in grid cells: w across (+X), h up, d back (-Z). Default 1x1x1.
sub cells { $CUR->{cells} = [ @_ ] }

# ---------------------------------------------------------------- pieces

# piece(Id, sub { ... }): builds one piece. Parts: 'Body', and 'Leaf' for
# the part of a door that swings.
sub piece {
	my ($id, $body) = @_;
	%REG = ();
	$CUR = { id => $id, cells => [ 1, 1, 1 ], flames => [], glows => [], rungs => [] };
	model($id, voxel => 0.25, desc => '');
	part('Body', undef, [ 0, 0, 0 ], 'Body');
	$body->();
	my $m = finish();
	# Rounded shapes resting on the floor (a dome, a heap) are drawn whole and
	# cut off at floor level here.
	for my $k (keys %{ $m->{grid} }) {
		my (undef, $y) = split /,/, $k;
		delete $m->{grid}{$k} if $y < 0;
	}
	resolve($m);
	$m->{meta} = $CUR;
	push @PIECES, $m;
	return $m;
}

sub pieces { return @PIECES }

# Re-samples every textured voxel by the faces it shows.
sub resolve {
	my ($m) = @_;
	my $g = $m->{grid};
	my %cidx = %{ $m->{cidx} };
	my %byName;
	for my $i (0 .. $#{ $m->{colors} }) { $byName{ $m->{colors}[$i][0] } = $i + 1 }
	my @set;
	while (my ($k, $v) = each %$g) {
		my $cn = $m->{colors}[ $v->[1] - 1 ][0];
		next unless $cn =~ /^([\w~]+)\.(\d+)$/;
		my $key = $1;
		my ($name) = $key =~ /^(\w+)/;
		next unless $TEX{$name};
		my ($x, $y, $z) = split /,/, $k;
		my $open = sub { !exists $g->{ ($x + $_[0]) . ',' . ($y + $_[1]) . ',' . ($z + $_[2]) } };
		my ($u, $vv);
		if ($open->(0, 0, 1) || $open->(0, 0, -1)) { ($u, $vv) = ($x, 15 - $y) }
		elsif ($open->(1, 0, 0) || $open->(-1, 0, 0)) { ($u, $vv) = ($z, 15 - $y) }
		elsif ($open->(0, 1, 0) || $open->(0, -1, 0)) { ($u, $vv) = ($x, $z) }
		else { next }
		my $slot = sample($name, $u, $vv);
		my $i = $byName{"$key.$slot"};
		push @set, [ $k, $i ] if $i;
	}
	$g->{ $_->[0] }[1] = $_->[1] for @set;
}

1;
