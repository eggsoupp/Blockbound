# Stone tools — review batch

The three editable MagicaVoxel-format `.vox` files were built and rendered with Python. MagicaVoxel was not used. This batch is staged in `review/stone-tools-2026-10-26`; nothing has been published to `assets`.

## Files

- `stone_sword.vox`
- `stone_pickaxe.vox`
- `stone_axe.vox`
- `stone_*_preview.png`: matching front and angled views for each tool.
- `stone_tools_preview.png`: all tools at the same voxel scale.
- `reference_comparison.png`: supplied images above exported model front views.
- `build_stone_tools.py`, `design_grids.json`, `shared_palette.json`, and `validation.json`: reproducible source, design, palette, and checks.

## Shared construction

All three files use a **24 × 3 × 24** voxel canvas (X, Y, Z), identical palette order, and equal-sized voxels. Z is up. The reference silhouette lies in X/Z and retains the lower-left to upper-right orientation. Y is thickness: the complete solid silhouette occupies Y=1, with matching detail cells on Y=0 and Y=2. There is no hollow space between layers. Handles are centered in depth. One voxel is the same unit across all three files; no Roblox stud scale is baked into VOX.

## Reference interpretation

The axe and pickaxe retain their original 16-pixel source-grid head silhouettes and color placement. Their handles continue approximately five diagonal voxel steps beyond the original butt, using the existing shaft width and wood pattern. The pickaxe keeps its unequal ends; the axe keeps its single stone cutting head.

The sword reference has about a 64-pixel grid. It is sampled down to 24 pixels to match this batch's low-resolution style. Its broad stone blade, guard, pommel, bindings, and hanging tie are retained in simplified form. Small markings and the separate narrow tie ends merge or disappear at this resolution. No extra markings are added.

All colors come from the supplied reference palettes. Near-identical stone and timber colors are unified. The sword's reddish wood is mapped to the ochre-brown timber used by the axe and pickaxe to meet the requested common color scheme. Its light gray bindings remain gray. The shared palette contains 13 flat colors; no material textures, generated shades, gradients, or geometric bevels are included.

Raised cells follow existing binding/attachment colors without changing the front silhouette. The blade faces and most handle cells remain one voxel thick.

## Verification

Each exported file was reopened by the Python VOX parser. Checks cover chunk sizes, palette indices, canvas bounds, duplicate voxels, a single face-connected component, solid depth columns, identical RGBA palettes, exact front/back symmetry across Y=1, and exact front projection against the authored grid. The axe and pickaxe heads additionally match their normalized source pixels cell for cell. Front and angled renders were visually compared with the supplied images. Model dimensions are identical; occupied silhouettes retain their different proportions.

Rebuild with Python and Pillow: `python build_stone_tools.py`. The `references` directory contains the supplied images so the builder does not depend on temporary attachment paths after the first run.
