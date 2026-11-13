# Village materials on top of ../../voxel-decor/source/materials.pl: the
# merchant's purple-black cloth, the starlight glows, plaster and roof tile.
# All from block-texture patterns, so they speckle like the world.
use strict; use warnings;
use DecorKit;

# The merchant's palette
# (The game's lighting lifts and saturates colours a lot: these read
# purple-black in Studio at noon.)
DecorKit::retex(mystic     => 'snow', '1c1424', '231a2e');
DecorKit::retex(void       => 'snow', '0c0a0e', '121014');
DecorKit::retex(violet     => 'snow', '3e2a5c', '4a336c');
DecorKit::retex(midnight   => 'snow', '1d2340', '252c4e');
DecorKit::retex(starglow   => 'snow', '7c54c8', '9472dc');
DecorKit::retex(stargold   => 'snow', 'd8a440', 'e6bc5c');
DecorKit::retex(eyeglow    => 'snow', 'cbb8ff', 'e0d4ff');
DecorKit::retex(runeglow   => 'snow', '3e94c4', '5aa8d4');

# Village
DecorKit::retex(plaster    => 'snow', 'e4d8bc', 'ede4cc');
DecorKit::retex(roof_tile  => 'stone', '9c4a32', 'b25a3c');
DecorKit::retex(moss       => 'grass_top', '4f7a30', '5f8c3a', '466e2a');
DecorKit::retex(window_lit => 'snow', 'c47e2c', 'd4943e');
DecorKit::retex(gravel     => 'stone', '8a8478', '9d968a');
# Plain (unlit) glass and potion colours for wares that should not glow.
DecorKit::retex(glass_vio  => 'snow', '8e6cc4', 'a688d4');
DecorKit::retex(glass_grn  => 'snow', '58b04c', '6cc25e');
DecorKit::retex(glass_blu  => 'snow', '4c8cc4', '62a2d6');
DecorKit::retex(potion_dim => 'snow', '48a83c', '5cbc4e');
DecorKit::glowtex(qw(potion_dim starglow stargold eyeglow runeglow window_lit));

1;
