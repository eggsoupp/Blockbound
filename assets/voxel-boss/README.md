# Riftmaw — modular voxel boss

Three separate, single-model MagicaVoxel `.vox` assets. Every visible element is
made of opaque, integer-grid unit cubes, including the teeth, horns, eyes,
armour edges and curved stinger. There are no smooth meshes, image textures,
translucent materials or baked lighting. All three files carry the same 28-colour
palette, at identical palette indices.

The design combines the illustrated worm's recessed tooth-lined maw, overlapping
violet armour, rose belly and ivory stinger with the pixel reference's dark shell
and acid-green ring markings. The reference sheets' written game rules were not
treated as instructions.

## Files and scale

| File | Model canvas (X × Y × Z) | Occupied dimensions | Voxels |
| --- | --- | --- | ---: |
| `head.vox` | 64 × 64 × 56 | 56 × 44 × 56 | 42,150 |
| `body_segment.vox` | 64 × 64 × 56 | 46 × 36 × 56 | 44,934 |
| `tail.vox` | 64 × 64 × 56 | 34 × 30 × 56 | 13,874 |

Use one consistent voxel scale for all three parts. The unused X/Y canvas space
is intentional: it keeps each part's connection axis aligned. Preserve it when
importing, or use the explicit sockets below if your importer trims or recentres
models.

## Assembly

The model axis is **Z**, with the head above the body and tail. The mouth opens
toward **+Z**, along the worm's length. The belly faces **−Y**. X is left/right.
Coordinates below are model-space boundary
coordinates: voxel `(x, y, z)` occupies `[x, x+1] × [y, y+1] × [z, z+1]`.

| Part | Socket | Position |
| --- | --- | --- |
| Head | Bottom | `(32, 32, 0)` |
| Body | Top | `(32, 32, 56)` |
| Body | Bottom | `(32, 32, 0)` |
| Tail | Top | `(32, 32, 56)` |

Every joint has the same solid elliptical cross-section: 564 contacting voxels,
with matching colours on both mating faces. Body copies repeat at exactly
**56 voxels**. Place flush, without an extra gap or overlap.

For `N` body segments, using the head's original model origin as `(0, 0, 0)`:

```text
head origin    = (0, 0, 0)
body[i] origin = (0, 0, -56 * (i + 1))       # i = 0 ... N-1
tail origin    = (0, 0, -56 * N - 56)
```

The total straight assembly length is `112 + 56 * N` voxels. The supplied preview
uses three body copies, for a total length of 280 voxels. `assembly.json` records
the sockets and these exact preview placements. If rotating pieces along a path,
rotate about their sockets and align the mating socket positions. Exact flush
matching is verified for straight, equally oriented placement; rigid cubes cannot
form a perfectly sealed arbitrary bend without overlap or a flexible joint.

Keep nearest-neighbour sampling and disable mesh smoothing in any downstream
conversion to preserve the game's pixel/voxel style.

## Preview and refinement

- `previews/parts_multiview.png`: four views of each asset, including the head's axial view.
- `previews/head_multiview.png`: axial mouth, three-quarter and side views of the rebuilt head.
- `previews/assembled_multiview.png`: three full-boss views with three repeated segments.
- `previews/body_multiview.png`: four views of the longer, X-symmetric body segment.
- `previews/part_proportions.png`: head, body and tail displayed at the same scale.
- `previews/head_detail.png`: close view of the sculpted mouth and crown.
- `previews/body_repeat_detail.png`: three stacked copies, showing the seams.
- `previews/shared_palette.png`: the shared swatches.

Previews are orthographic renders of exposed voxel cube faces. They use discrete
face shading, with no antialiasing, bloom or smooth normals; display enlargement
uses nearest-neighbour pixels. Preview lighting is not baked into the files.

The head has a lengthwise throat, a flared armoured jaw, twelve long forward-curving
fangs, six inner teeth and four outer mandible horns. Its mouth opens along +Z,
parallel to the body axis.

The body was extended from 16 to 56 voxels tall, matching the head and tail. Two
courses of elongated armour plates and ten belly scutes retain the existing style
without stretching individual cubes. Geometry and palette indices are mirrored
exactly across X=32. The connector faces are unchanged. The saved head (including
the user's MagicaVoxel edits) and tail were loaded for previews without rewriting
either file; before/after byte comparisons and SHA-256 hashes verify preservation.
Four body views, equal-scale part views and a three-segment assembly were inspected.

## Validation and editable source

`validation.json` records binary round-trip, bounds, palette, connectivity and
joint checks. Each asset is a single 6-connected voxel component; the assembled
boss is also one connected component. All four mating faces match in geometry
and colour. The `.vox` files were parsed back and checked against the source
voxel grids without loss.

The body and tail use standard VOX 150 `MAIN`, `SIZE`, `XYZI` and `RGBA` chunks described
in the [official MagicaVoxel file-format specification](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt).
The user's saved head is VOX 200 with its original scene, material and editor
metadata preserved. Validation was performed programmatically; the assistant has
not opened the files in the MagicaVoxel desktop application in this session.

`source/build_boss.py` contains the editable voxel sculpt, exporter, validator and
pixel preview renderer. It requires Python, NumPy and Pillow. Its current entry
point rebuilds **only the body**, reads the saved head and tail as authoritative,
and updates validation and previews. It never rewrites the head or tail files.
