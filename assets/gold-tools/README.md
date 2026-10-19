# Gold toolset

Three solid voxel props based on the supplied axe, pickaxe, and sword references.
All three embed a byte-identical 24-color palette with stable indices. The palette includes warm gold, burgundy, brown, amethyst, and cool steel.

| File | Grid X x Y x Z | Grip center X,Y,Z |
|---|---|---|
| gold_axe.vox | 53 x 15 x 68 | [19, 7, 10] |
| gold_pickaxe.vox | 55 x 11 x 66 | [27, 5, 10] |
| gold_sword.vox | 25 x 11 x 68 | [12, 5, 10] |

MagicaVoxel VOX version 150, one model per file. +Z points toward the head/tip; X runs across the head; Y is thickness. Models are upright for attachment and editing. Set game/world scale in the importer.

The axe retains its broad gold blade, short rear spur, red/gold shaft, and raised purple eye. The pickaxe has a brown handle, gold pommel, and asymmetric curved gold head. The sword has a gold blade with a sculpted central ridge and a cool steel guard/hilt.

previews/ contains renders of the exported geometry, including front/back/depth views. shared_palette.json, .gpl, and .png provide the common palette. validation.json records binary round-trip, bounds, palette, uniqueness, and 6-neighbor connectivity checks.

Rebuild with Python 3, NumPy, and Pillow: python source/build_gold_tools.py. Source files are self-contained. No background, display stand, or reference-image UI is included in the models.
