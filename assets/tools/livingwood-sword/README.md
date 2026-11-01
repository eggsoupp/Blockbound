# Livingwood sword

Low-resolution 3D interpretation of the supplied wooden fantasy sword: twisting bark blade, recessed yellow eyes, layered leaf guard, hanging vines, and a crooked root handle.

- `livingwood_sword.vox`: editable MagicaVoxel v150 model, 29 × 13 × 87 grid, 5,269 occupied voxels.
- `previews/hero.png`: angled render of the actual exported geometry.
- `previews/views.png`: front, rear, and side views.
- `previews/livingwood_sword_transparent.png`: transparent geometry render.
- `source/build_sword.py` and `source/voxel_utils.py`: reproducible generator, exporter, validator, and renderer; requires Python, NumPy, and Pillow.
- `validation.json`: successful binary round-trip, bounds, unique coordinates, palette, and single-component connectivity checks.

Orientation: +Z points toward the blade tip, X spans the guard, and Y is thickness. The model is upright; only the preview is posed diagonally. Eyes use bright palette colors; bloom/emission can be assigned in your renderer. All geometry belongs to one connected editable model, with no display stand or background voxels.

Rebuild with `python source/build_sword.py` from this folder.
