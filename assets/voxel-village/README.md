# Spawn village

The open world's spawn village. Every model is a MagicaVoxel `.vox` file
built in code, using the decor kit's voxel of 0.25 studs.

- The floors, the merchant's stall, the notice board and the gates use the
  block-texture patterns.
- The shrine and the market use freer hand-picked palettes (`pal`), a shade
  darker than they look in the source, because the game's light lifts colours
  a long way.
- The Starfall Merchant keeps a purple-black and gold palette.

| Asset | What it is |
| --- | --- |
| `Merchant` | Rigged: Body (robe, root at the hips) → Torso → Head; RightArm → Staff → Lantern; LeftArm → Orb; Body → Runes |
| `MerchantStall` | Counter, shelves, canopy, lanterns and the eye sign; anchor `MerchantSpot` |
| `StarfallShrine` | The wishing star where players wish for aspects. Symmetrical all round: an indigo dais with a gold constellation circle, four candle obelisks (`Flames`, the only Neon), an octagonal pedestal with violet rune bands and an offering bowl, a five-pointed `Star` inside two equal gold `Rings`, and four crystal `Shards`; the last three are moved by the client. Anchor `WishSpot` is where the prompt goes; SpawnHub adds sparkles from the VFX pack |
| `TradeBoothTeal`, `TradeBoothCrimson` | Trading stations (not rigged). A plank deck with a low table (balance scale, ledger, coins) between two floor cushions, a shingled roof, lanterns, and balance-scale signs. Anchors `PadA` / `PadB` (±3 studs on Z, cushion top) are where SpawnHub puts the Seats |
| `MarketArch` | Over the road into the market: a plain, slightly crooked wooden stand with the TRADING sign hung high and off-centre, readable from both sides |
| `PlazaTile`, `PlazaTileMoss` | Floor: flagstone tile, 4×4 studs, 0.5 thick |
| `PathTile`, `PathEdge`, `PathCorner` | Floor: dirt path, plus edges that fray into grass on +X (and +Z for the corner) |
| `NoticeBoard`, `VillageGate` | Dressing; a gate marks each road out of the village |

The two cottages and the two market stalls were taken out of the village.
Their designs are in `source/unused/`, which is not built.

The village also places decor pieces (`Shared.Building.DecorModels`): the
2×2 `Well`, lamps, a campfire, and three `TrainingDummy`s. SpawnHub registers
the dummies with `EnemyService.adopt`, so they take hits like enemies.

## Files

- `vox/<Name>.vox`: one named object per part. Open it in MagicaVoxel.
- `previews/<Name>.png`: two front 3/4 views and a back 3/4 view. Rigs also get a parts view with the pivots marked. `previews/_sheet.png` shows every asset.
- `roblox/data/<Name>.lua`: greedy-merged boxes, plus per-part parent, pivot and collision, lights and anchors.
- `roblox/BuildVillage.lua`: the Studio (Edit) builder.
- `source/`:
  - `VillageKit.pm`: on top of `../voxel-decor/source/DecorKit.pm`.
  - `materials.pl`: the village and merchant colours.
  - `designs/*.pl`: the models.
  - `build.pl`

## Conventions

- **Axes:** these are Roblox's axes, unlike the decor, which faces +Z. +X is right, +Y is up, the front is -Z, and the origin is the middle of the floor. SpawnHub turns each model with `CFrame.lookAt`.
- **Pivots:** a rig pivot is given in voxel index space. `BuildVillage` places it at `(p + 0.5) * 0.25` studs.
- **Collision per part:** `hitbox(Part, 'box' | 'precise' | 'none')`.
  - Glow unions never collide.
  - Rig parts never collide.
- **Neon is for lamps only.** `neon(Part)` in a design marks a part whose glowing boxes are lamps (lanterns, candle flames, the merchant's eyes); only those become Neon. Glowing boxes in other parts are built as ordinary colour. SpawnHub keeps Neon only on decor lamps. The PointLights carry the lighting. The game also lifts dark cloth a lot, which is why the merchant's purple is nearly black in the source.

## Rebuilding

```
perl source/build.pl              # everything, plus the sheet
perl source/build.pl Merchant     # one asset
```

Then load the models into Studio (Edit). This is the same route as the decor:

1. Find the running Studio's content folder: `Get-Process RobloxStudioBeta | Select Path`.
2. `rojo build roblox/import.project.json -o <that folder>/content/villageimportN.rbxm`.
   Use a new N each time, because Studio caches `rbxasset://` files.
3. In an Edit execute:
   - `local f = game:GetObjects("rbxasset://villageimportN.rbxm")[1]`
   - then, for each asset, `require(f.BuildVillage)(require(f.Data.<Name>), { parent = ServerStorage.VillageAssets })`

`ServerStorage.VillageAssets` is a place asset. Save the place to keep it.
Only the world place needs it, because islands have no village.

## In game

- `ServerScriptService.SpawnHub` lays out the village:
  - It uses the floor plan, SpawnServer calls it, and it builds `workspace.StarfallHub`.
  - A missing asset gets a plain stand-in box and a warning.
- `GeneratedColumns` levels the ground under the village (`TerrainConfig.SpawnZones.VillageFlatBlocks` / `VillageBlendBlocks`).
- `Trade/TradeStations` binds the pads.
- `ShopClient` opens the Aspect Shop from the merchant's `StarfallShop` prompt.
- `VillageAmbience.client` animates the merchant's idle and the waystone star.
