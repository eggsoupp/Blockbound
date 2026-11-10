# Voxel decor

83 placeable furniture and prop pieces, modelled as MagicaVoxel `.vox`
files. Each voxel is 0.25 studs, so a 4-stud block is 16 voxels across, and
one voxel is one pixel of the game's 16×16 block textures. Wood, stone,
cobblestone and stone bricks reuse the block textures pixel for pixel. Metal,
cloth, straw, leather, pumpkin, crystal and the rest are those same patterns
with new palettes, so everything speckles the way the blocks do.

## Files

- `vox/<Id>.vox`: the model. Open it in MagicaVoxel. A door's swinging half is
  a separate object named `Leaf`. A window's panes are `Glass`.
- `previews/<Id>.png`: front 3/4 and back 3/4. `previews/_sheet.png` shows
  every piece.
- `roblox/data/<Id>.lua`: greedy-merged boxes for the Studio builder.
- `roblox/BuildDecor.lua`: the Studio (Edit) builder. Each part becomes one
  union, and every box keeps its colour. Glowing colours go in a separate Neon
  union (`BodyGlow`), so a light can dim it when it's put out.
- `source/`:
  - `DecorKit.pm`: the kit, built on `../voxel-enemies/source/VoxLib.pm`.
  - `materials.pl`: the recoloured textures.
  - `designs/*.pl`: the pieces.
  - `build.pl`: writes everything above, plus
    `src/ReplicatedStorage/Shared/Building/DecorShapes.lua`.

## Conventions

- **Footprint:** every piece fills whole 4-stud grid cells. `cells(w, h, d)` in a
  design sets the footprint (1x1x1 by default): w across to the right, h up, d
  back from the placed cell, so a sofa is 2x1x1, a door 1x2x1 and a tent
  2x1x2. The build refuses any model that pokes outside its footprint, and the
  game reserves exactly those cells. Domes resting on the floor are trimmed
  at floor level automatically.
- **Cell frame:** x and z run from -8 to 7 and y from 0 to 15 per cell (0 to 31
  for a two-cell piece). The front is +Z, the side that turns to face whoever
  places it.
- **Texture sampling:** `tex('oak_plank')` paints with a block texture.
  Textured voxels are re-sampled by the faces they show, so the grain runs the
  right way on every face.
- **Metadata:** the hinge, seat, flames, lights, ladder rungs and a top
  surface are declared in studs in the design, and end up in `DecorShapes`.

## Rebuilding

```
perl source/build.pl            # everything (also the sheet and DecorShapes)
perl source/build.pl Barrel     # one piece
```

Then load the models into Studio:

1. `rojo build roblox/import.project.json -o <Studio>/content/decorimport.rbxm`
2. In an Edit execute, load it with
   `game:GetObjects("rbxasset://decorimport.rbxm")[1]`.
3. Call `require(folder.BuildDecor)(require(folder.Data.<Id>), { parent = ReplicatedStorage.TerrainAssets.Decor })`
   for each piece.

`TerrainAssets.Decor` is a place asset. Save the place to keep it, and copy
the folder into the island place.

## In the game

The pieces are listed in `Shared.Building.DecorCatalog`, which sets their
names, kinds, recipes and heights. `Shared.Building.DecorModels` clones the
voxel model and adds the code-side parts: the hinge, an invisible Seat, flame
emitters, lights and rungs. `ServerScriptService.DecorServer` makes doors
swing, lights go out and back on, and seats seat you.
