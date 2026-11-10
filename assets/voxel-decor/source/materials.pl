# Materials with no block of their own, made from the game's block textures
# with new palettes, so they speckle the same way: metal from the stone
# streaks, cloth and wax from the snow drifts, straw and gold from sand,
# leather from dirt, pumpkin rind from the sandstone bands.
use strict; use warnings;
use DecorKit;

# Woods: oak_plank and birch_plank come straight from the blocks. Darker oak
# is tex('oak_plank', 0.65).

# Metals
DecorKit::retex(iron       => 'stone', '6f747d', '8e949d');
DecorKit::retex(iron_dark  => 'stone', '3d4047', '50545c');
DecorKit::retex(gold       => 'sand',  'e2b23c', 'f6d36a', 'b08128');
DecorKit::retex(copper     => 'sand',  'b8693a', 'd88a52', '8c4c2a');

# Cloth, wool, wax, paper
DecorKit::retex(wool       => 'snow', 'e6e2d6', 'f3f0e6');
DecorKit::retex(red_cloth  => 'snow', 'a42e2d', 'b73b38');
DecorKit::retex(blue_cloth => 'snow', '2f4f9c', '3a5eb0');
DecorKit::retex(green_cloth=> 'snow', '3d7a3a', '4a8c45');
DecorKit::retex(wax        => 'snow', 'eee3c4', 'f7efd6');
DecorKit::retex(paper      => 'snow', 'e8dcb8', 'f2e8c8');

# Organic
DecorKit::retex(leather    => 'dirt', '7a4a2a', '5e3a22', '94603a');
DecorKit::retex(straw      => 'sand', 'd5b356', 'e9cf78', 'ad8c3c');
DecorKit::retex(sack       => 'sand', 'c8aa78', 'd9be8e', 'a88c5e');
DecorKit::retex(pumpkin    => 'sandstone', 'e07a1e', 'c4621a');
DecorKit::retex(mushroom   => 'snow', 'b8362c', 'cc4636');
DecorKit::retex(bark       => 'oak_plank', '6e4c2a', '5a3c20', '43301a');
DecorKit::retex(clay       => 'dirt', 'b0603c', '94502f', 'c4744a');
DecorKit::retex(water      => 'snow', '3a78c8', '4a8ad8');
DecorKit::retex(coal_bed   => 'stone', '2b282a', '3c3638');

# Curios
DecorKit::retex(frog       => 'grass_top', '3f7f2e', '5aa842', '4b9438');
DecorKit::retex(melon_rind => 'grass_top', '245f20', '3f9a36', '2f7a2a');
DecorKit::retex(melon      => 'snow', 'e04848', 'f06a5e');
DecorKit::retex(cloud      => 'snow', 'eef2f8', 'ffffff');
DecorKit::retex(bone       => 'snow', 'd8d0b4', 'e8e2cc');
DecorKit::retex(duck       => 'sand', 'f5cc28', 'ffe25a', 'd8a818');
DecorKit::retex(fur        => 'dirt', '8a5a34', '6e4628', 'a26c40');
DecorKit::retex(cat        => 'dirt', 'e08a3a', 'c86e24', 'f0a454');
DecorKit::retex(fish       => 'sand', 'f07a20', 'ff9a40', 'd05a10');
DecorKit::retex(ivory      => 'snow', 'efece2', 'faf8f0');
DecorKit::retex(ebony      => 'stone', '1e1c22', '2c2a30');
DecorKit::retex(porcelain  => 'snow', 'e8ecf0', 'f6f8fa');
DecorKit::retex(canvas     => 'sand', 'd2bf96', 'e2d4ae', 'b49e74');
DecorKit::retex(honey      => 'sand', 'e2981e', 'f4bc3c', 'b8740e');
DecorKit::retex(snow_ball  => 'snow');
DecorKit::retex(brass      => 'sand', 'c8963a', 'e6b85a', '9a6e24');

# Glowing
DecorKit::retex(crystal    => 'snow', '6fd0ff', 'a8e8ff');
DecorKit::retex(shroom_glow=> 'snow', '4fe0c8', '86f2dc');
DecorKit::retex(ember      => 'sand', 'f07a24', 'ffb048', 'c8481c');
DecorKit::retex(amethyst   => 'snow', 'a060f0', 'd0a0ff');
DecorKit::retex(potion     => 'snow', '6ae85a', 'a8ff8e');
DecorKit::retex(lava       => 'sand', 'ff6a1e', 'ffa040', 'e04010');
DecorKit::retex(mirror     => 'snow', 'a8d4f0', 'd8eeff');
DecorKit::retex(firefly    => 'snow', 'd8ff60', 'f4ff9a');
DecorKit::glowtex(qw(crystal shroom_glow ember amethyst potion lava firefly));

1;
