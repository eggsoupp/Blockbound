# Reference tools — review only

These three editable models were traced from the supplied references, opened and visually checked in MagicaVoxel 0.99.7.2, and saved through MagicaVoxel. Nothing has been published or copied into the project's assets folder.

| File | Canvas X × Y × Z | Occupied voxels |
| --- | --- | --- |
| pickaxe.vox | 15 × 2 × 16 | 170 |
| sword.vox | 26 × 2 × 26 | 372 |
| axe.vox | 16 × 2 × 16 | 120 |

X follows image horizontal, Z follows image vertical, and Y is thickness. All three use one voxel per recovered reference pixel and two solid layers along Y. View from negative Y with Z up to match the reference. Identical color indices and geometry are mirrored across the thickness midpoint. No bevels, texture maps, decorative additions, or extra geometry were added.

The axe's 16 × 16 grid and ten source colors are exact. The sword has been remade from the replacement reference supplied on 26 October 2026. Its 26 × 26 occupied grid is sampled at source-cell centers; the white sticker outline and empty image margins are excluded. Its six source color bands are mapped to existing axe wood colors: #281E0B, #372910, #493615, #594319, #6B511F, and #866526. Every color actually used on the sword is already used on the axe, and three are also used on the pickaxe. The previous sword's orange, red-brown, and neutral-black swatches are no longer used by any sword voxel. The 18-entry shared palette table is preserved byte-for-byte across all models, including its unused entries.

The photographed pickaxe uses an inferred 48-image-pixel grid; the frame and cast/extrusion shadows are omitted, and lighting variation is consolidated into eight source-sampled swatches. Three close brown swatches are reused from the axe palette. The pickaxe is an interpretation of the photographed front face, rather than an exact recovery of the unavailable original sprite. The pickaxe and axe models are unchanged by the sword revision.

Each *-preview.png shows a matching front view and a modest angled view rendered from the delivered VOX data. The *-front.png files are transparent, nearest-neighbor front projections. set-preview.png uses the same voxel scale for all three models. reference-comparison.png places each original above the corresponding front projection.

Validation after native saves confirms valid chunk boundaries, voxel bounds, unique voxel coordinates, one face-connected solid per tool, full two-layer depth, identical mirrored front/back colors, exact agreement with the pixel traces, and byte-identical RGBA palettes across the three files. The sword's used colors are also checked against the colors actually used by the axe. See validation.json for counts and results.

build_models.py and pixel-traces.json preserve the reconstruction process. Running build_models.py without --verify-only regenerates minimal VOX files and replaces MagicaVoxel's saved camera/scene metadata. Add --sword-only to regenerate only the revised sword. Running with --verify-only checks and renders the existing files without rewriting their VOX data. The reconstruction script references the original attachments in the local temporary directory.

The binary writer follows the [official MagicaVoxel VOX format](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt).

Awaiting approval before any assets-folder placement.
