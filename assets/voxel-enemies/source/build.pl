#!/usr/bin/perl
# Builds every design in designs/ (or the names given):
#   ../vox/<Name>.vox          MagicaVoxel scene, one named object per rig part
#   ../roblox/data/<Name>.lua  box data for ../roblox/BuildEnemyRigs.lua
#   ../previews/<Name>.png     front 3/4, side, back 3/4, parts + pivots
#   ../rigging.json            parts, parents, pivots, sizes
# Usage: perl build.pl [Name ...] [--scale N]
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use VoxOut;

my $root = "$FindBin::Bin/..";
my $scale = 4;
my @want;
while (@ARGV) {
	my $a = shift;
	if ($a eq '--scale') { $scale = shift } else { push @want, $a }
}
mkdir "$root/$_" for qw(vox roblox roblox/data previews);
my @files = @want ? map { "$FindBin::Bin/designs/$_.pl" } @want : sort glob("$FindBin::Bin/designs/*.pl");

my %rig;
if (-e "$root/rigging.json") {
	# keep entries of designs not rebuilt this run (one model per line)
	open my $fh, '<', "$root/rigging.json"; local $/; my $txt = <$fh>; close $fh;
	while ($txt =~ /^  "(\w+)": (\{.*\}),?$/mg) { $rig{$1} = $2 }
}

for my $file (@files) {
	my $m = do $file;
	die "$file: $@ $!" unless $m;
	my $name = $m->{name};
	my $parts = VoxOut::write_vox($m, "$root/vox/$name.vox");
	my $boxes = VoxOut::write_lua($m, "$root/roblox/data/$name.lua");
	VoxOut::write_preview($m, "$root/previews/$name.png", $scale);
	my $by = VoxOut::parts_of($m);
	my $count = scalar keys %{ $m->{grid} };
	my @j;
	for my $p (@{ $m->{parts} }) {
		my $jt = $m->{joints}{$p};
		my $n = scalar @{ $by->{$p} || [] };
		warn "  ! $name.$p has no voxels\n" unless $n;
		push @j, sprintf '"%s": {"parent": %s, "pivot": [%s], "voxels": %d, "role": "%s"}', $p,
			defined $jt->{parent} ? "\"$jt->{parent}\"" : 'null', join(', ', map { 0 + sprintf('%.2f', $_) } @{ $jt->{pivot} }), $n, $jt->{role};
	}
	my ($lo, $hi) = VoxOut::bounds([ map { [ split /,/ ] } keys %{ $m->{grid} } ]);
	my @size = map { $hi->[$_] - $lo->[$_] + 1 } 0 .. 2;
	$rig{$name} = sprintf '{"voxel_studs": %s, "size_voxels": [%s], "voxels": %d, "boxes": %d, "description": "%s", "parts": {%s}}',
		$m->{voxel}, join(', ', @size), $count, $boxes, $m->{desc}, join(', ', @j);
	printf "%-20s %6d voxels  %2d parts  %5d boxes  size %s (%.1f x %.1f x %.1f studs)\n", $name, $count, $parts, $boxes,
		join('x', @size), map { $_ * $m->{voxel} } @size;
}

open my $out, '>', "$root/rigging.json" or die $!;
print $out "{\n" . join(",\n", map { "  \"$_\": $rig{$_}" } sort keys %rig) . "\n}\n";
close $out;
