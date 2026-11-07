# BlockBound wing accessories

Seven original 3D voxel wing pairs based on the accessory names and written
descriptions in `src/ReplicatedStorage/ItemDefinitions.lua`. Inventory icons and
UI art were not design references. The local `blockbound.rbxlx` contains no
named wing accessory models. These assets are new interpretations of the items.

## Open and edit

Open any of the seven `*Wings.vox` files using MagicaVoxel's top-right folder
button. `AllWings.vox` is a gallery containing all seven sets. In world mode,
each wing piece has a named object and layer. Tab enters voxel editing for a
selected object. Individual pieces are also supplied under `parts/<ItemName>/`.

The files preserve separate left and right wings, a central wearable frame,
and secondary pieces. All pieces have real volume and authored front/back depth.

| Item / native file | Pieces / joints | Design | Item flight bonus |
| --- | ---: | --- | ---: |
| `AngelWings.vox` | 21 | Ivory layered feathers, warm metal frame | 20 s |
| `BatWings.vox` | 7 | Plum membranes, scalloped edges, thumb hooks | 13 s |
| `DemonWings.vox` | 13 | Crimson membranes, dark ribs, horn hooks and thorns | 19 s |
| `FairyWings.vox` | 5 | Four independent lavender/turquoise insect lobes | 14 s |
| `FlameWings.vox` | 17 | Red-orange solid flame plumes with golden cores | 18 s |
| `FrostWings.vox` | 17 | Faceted blue-white crystal fans | 15 s |
| `LeafWings.vox` | 21 | Layered veined leaves on branching supports | 12 s |

The flame shapes are solid accessory geometry, not runtime fire VFX.

## Animate

Use the matching file in `rigged/` in a glTF-compatible animation application,
for example import it into Blender as glTF 2.0. These GLBs contain actual joint
hierarchies, inverse bind matrices, and skin weights. Each mesh is weighted 100%
to one joint, so moving it preserves the crisp voxel surface. Every file includes
an editable 1.2-second `Flap` loop and a short `Fold` pose test.

- `Frame`: attach to the upper back; keep fixed relative to the torso.
- `L_Arm`, `R_Arm`: shoulder flap/sweep.
- `L_Fan`, `R_Fan`: elbow fold and fan movement.
- `Feather##`, `Plume##`, `Crystal##`, `Leaf##`: independent secondary motion.
- `Claw`, `Thorn#`: secondary joints on bat/demon wings.
- Fairy wings use `L_Upper`, `R_Upper`, `L_Lower`, `R_Lower` directly under Frame.

The `.vox` scenes contain editable pieces; the skeletons and animation clips
are in the `.glb` files. The clips are rig checks and starting points, not final
gameplay animations. Extreme joint rotations can open gaps between rigid pieces;
use the supplied conservative poses as a starting range.

`rigging.json` records every piece, parent, anatomical pivot, dimensions, voxel
count, and triangle count. Preserve these names when transferring a rig.

## Scale and coordinates

Pairs span approximately 105–149 voxels. Source axes are X lateral, +Y rearward,
+Z up. Pivots are measured in voxel-centre coordinates relative to Frame's
origin `(0,0,0)`. For convenient viewing, the VOX scene root is lifted 40 voxels
along Z; add `(0,0,40)` to a listed pivot to locate it in the MagicaVoxel world.
This scene lift is deliberately absent from the animation export.

GLB coordinates are `(source X, source Z, -source Y) * 0.0625`: Y up, forward +Z.
The resulting span is about 6.6–9.3 model units. Scale the whole rig uniformly to
your character. For a target whose forward direction is -Z, turn the entire rig
180 degrees around Y before attaching. Do not rotate only the meshes or apply
different scales to individual bones. `L_` and `R_` designate negative/positive
source X respectively; rename sides if your destination convention differs.

These are authoring assets. They have not been uploaded or connected to Roblox's
equipment or flight scripts. Importer behavior in Roblox/Blender has not been
tested in those applications. Bone names, texture, transforms and skinning are
contained in each GLB; no external textures are required.

## Review and validation

- `previews/AllWings.png`: all seven designs, rendered from the voxel geometry.
- `previews/Flap_Rig_Preview.gif`: animation decoded from the saved GLB files.
- `previews/*_rig_check.png`: rest, flap and fold poses decoded from each GLB.
- `previews/*_front.png`: straight rear views of the accessory's outer face.
- `validation.json`: binary structure, geometry, skinning and animation checks.

The validation reader checks VOX bounds and scene references, assembled positions
against individual part files, no detached voxel islands, GLB index ranges and
normals, surface area, rest-pose agreement, normalized rigid weights, fixed root,
loop continuity and length preservation during animation. MagicaVoxel is used
to inspect native file loading separately from these checks.

## Reproduce

Python 3 with NumPy and Pillow:

```text
python source/build_wings.py
python source/validate_wings.py
```

The builder regenerates the authored designs and overwrites their outputs.
Back up hand-edited VOX files before rebuilding. GLBs are exported snapshots;
later manual VOX edits do not automatically update the corresponding skin/mesh.

Format references: [MagicaVoxel VOX](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt),
[VOX scene extensions](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox-extension.txt),
[glTF 2.0](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html).
