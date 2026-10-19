# Wooden sword

Replacement based on the latest pixel-art sword reference: a narrow orange-brown wooden blade, charcoal perimeter, dark recessed diamond seam, short squared grip, and simple wooden crossguard. Solid depth with beveled perimeter and the same detail on front and back. This replaces the previous pale blade and linen-bound design.

- `wooden_sword.vox`: MagicaVoxel v150, one editable model, 25 x 7 x 62 grid.
- `shared_palette.json`, `.gpl`, `.png`: the same 16-color charcoal/wood palette embedded in the model; keep indices stable for additional weapons. Index 0 is empty.
- `previews/`: front, rear, angled views, and a transparent render from the exported geometry.
- `source/build_weapons.py`: reproducible generation and validation; Python, NumPy, Pillow.
- `validation.json`: binary round-trip, bounds, color-index, uniqueness, and connectivity checks.

Orientation: +Z toward the tip, X across the guard, Y depth. The asset is upright; the diagonal pose appears only in previews. Grid grip center approximately (12, 3, 8); ground/pommel begins at z=0. Choose world scale in your importer.

Open the VOX file directly in MagicaVoxel or another compatible editor. All voxels are opaque; there is no base, background, or display stand in the model.
