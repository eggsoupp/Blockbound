# Blockbound beginner steel toolset

Three small, simple 3D voxel models based on the supplied sword, pickaxe and axe references. These replace the previous detailed models at the same filenames. Each model contains fewer than 350 occupied voxels, is at most 32 voxels tall and is only 3 voxels thick.

- **steel_sword.vox**: simple tapered blade, short crossguard, plain leather grip and small metal pommel.
- **steel_pickaxe.vox**: stepped double-ended steel head, plain socket and a 2 x 2 wooden shaft.
- **steel_axe.vox**: compact single cutting bit, shallow beard and a 2 x 2 wooden handle.

All files are MagicaVoxel VOX version 150 with one editable voxel volume per file. The models are upright: +Z toward the head/tip, X across the head, Y thickness. The axe cutting edge faces +X. Import scale is left to the game. The diagonal poses in the references are normalized to upright local coordinates.

## Shared palette

All three VOX files embed an identical complete 256-entry RGBA chunk. Slots 1-28 are named colors; slot 0 is empty. The 16 existing wood/linen colors remain in their original slots, with steel and leather appended. `shared_palette.json`, `.gpl` and `.png` are included. Each model uses the relevant subset. The earlier wooden sword files are untouched.

## Previews and validation

`previews/steel_toolset.png` shows the set. Each model also has a transparent preview and front, angled, rear and side views. All previews are rendered from the geometry decoded from the exported VOX files; directional light slightly shades the palette colors in previews.

`validation.json` records dimensions, voxel counts, palette hashes and grip anchors in voxel coordinates. Every file passes binary round-trip, chunk size, bounds, unique coordinate, palette index and six-neighbor connectivity checks. Each is one connected solid with no background, watermark, ground plane or stand.

To rebuild: install Python 3, NumPy and Pillow, then run `python source/build_toolset.py`. The source is self-contained within this folder.
