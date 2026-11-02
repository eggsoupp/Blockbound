# Cosmic dragon voxel assets

An original voxel interpretation of the supplied cosmic dragon reference. Dark indigo armor, gold horns and trim, cyan star flecks, spread membranous wings, grasping hands, and a segmented curling tail. The reference's lighting, background nebulae, and orbit light trails are not baked into the geometry.

## Files

- `cosmic_dragon.vox`: assembled dragon with named model objects and layers.
- `planet_earth.vox`: ocean, green land masses, ice and cloud details.
- `planet_ember.vox`: orange rocky planet.
- `planet_ringed.vox`: purple and cream banded globe plus independently movable rings.
- `parts/`: each dragon section as its own VOX file, retaining its assembled position.
- `rigging.json`: suggested parent relationships and pivot coordinates for the dragon.
- `*_preview.png`: orthographic geometry previews.
- `build_models.py`: reproducible source generator.

## Rigging

VOX stores voxel models and scene transforms; it does not store a skinned animation rig. The dragon is prepared for rigid voxel articulation with separate named sections. Import while preserving model objects, then create bones or object constraints using `rigging.json`. Keep a consistent voxel scale across all objects. If your importer flattens multi-model VOX scenes, import the individual `parts/` files while preserving their scene translations.

Coordinates use Z up, X left/right, and -Y forward. Pivot coordinates are in the assembled voxel space, not local bounding-box coordinates. Model positions follow the MagicaVoxel convention: local coordinates centered at `floor(SIZE/2)`, plus the `_t` scene translation. Planet pivots are at world (0, 0, 0); rings rotate about the same center.

Each side uses suffix `-1` or `1` for the X side. Wings separate at shoulder and fan hinge; the jaw separates from the skull; the neck has two joints; arms and legs separate at major joints; the tail has twelve segments. Small overlaps at joints conceal gaps in the authored pose. Extreme poses may need joint adjustments or voxel edits. Soft deformation requires mesh conversion and skin weights later.

The dragon is roughly 240 voxels across. Planet diameters are 44, 36, and 50 voxels; ring span is 86 voxels. Cyan palette entries carry emission metadata, whose appearance depends on the renderer.

Format references: https://github.com/ephtracy/voxel-model
