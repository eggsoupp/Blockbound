# BlockBound: notes for agents

Read `README.md` (Rojo layout, the 200-local limit) and `AGENTS.md` (VFX
authoring rules) first. This file says where new code goes.

## Extend the owning module, do not grow the big scripts

Large scripts are coordinators. When you add behaviour, find the module that
already owns that job and extend it. Do not append new sections to the
coordinator. Make a new module only when the job has no owner yet. It must be
one cohesive responsibility, not "the next 500 lines".

### Terrain (server)

`ServerScriptService/TerrainManager.lua` is the public API and wiring only:
Init, delegation and stats. Every caller still uses `TerrainManager:X()`.
The work lives in `ServerScriptService/Terrain/`:

| Module | Owns |
| --- | --- |
| `GeneratedColumns` | column source (BiomeMap / IslandShape), caves on/off, generated-column cache |
| `ChunkData` | loaded chunks + residency state (generating, wanted, pending unload, pins, reservations, player chunks); cell queries; edit primitives; structure writer |
| `BlockParts` | block templates, face-variant templates, part pools, `partRect`, part counters |
| `FaceCulling` | which faces of a drawn Part show images |
| `ChunkMesher` | visible blocks -> merged Parts, layer plans, flushes, visible-block counter |
| `ColumnVisibility` | which blocks of a column are drawn; post-edit and chunk-border refresh |
| `EditZones` | per-block drawing around recent edits |
| `TerrainWater` | water as Terrain voxels |
| `ChunkQueue` | generation queue, priorities, re-ordering by player heading |
| `GenerationBudget` | shared adaptive frame budget, slices, urgency |
| `ChunkBuilder` | building and unloading one chunk |
| `ChunkStreaming` | view distances, active sets, unload grace, pump, Heartbeat work, buried-player rescue |
| `BlockEdits` | click resolution, inspect / break / place |
| `TerrainExcavation` | craters, boss bites, block walls, boss displacement |
| `OreDepletion` | harvested ore cells (regrown rock does not carry its ore again); `data.oreGone` |
| `ChunkRegeneration` | abandoned open-world chunks back to as generated; inactivity timers; reset listeners |

`ReplicatedStorage/Shared/Terrain/WorldZones.lua` says which columns are the
protected spawn or the starter area (`TerrainConfig.SpawnZones`). Anything
that changes terrain must go through `BlockEdits.removeResolvedBlock` or pass
`BlockEdits.CheckBuildZone`, which enforce it. Islands have no zones and never
regenerate.

`ReplicatedStorage/Shared/Terrain/TerrainGrid.lua` holds the coordinate
helpers and the chunk-key packing. The packing is part of the save format
through ChunkEdits, so never change it. CaveMap and StructureRegistry use it
too.

The underground is planned in `ReplicatedStorage/Shared/Terrain`, as pure
functions of the seed:

| Module | Owns |
| --- | --- |
| `CaveConfig` / `CaveMap` | where caves are and their shape (four categories: Small, Network, Large, Colossal); a chunk's carve record of air intervals |
| `CaveDecorConfig` / `CaveDecor` | biome cave decorations: cells left solid on cave floors and ceilings (`record.decor`), registered as blocks |
| `OreConfig` / `OreRegistry` | ore at a block: `blockAt` for sealed rock, `exposedBlockAt` for rock lining a generated cave |
| `BiomeConfig` `stoneBlock` | each biome's own stone, used below the soil and for bare rock |

`ChunkBuilder.applyCaves` is the only place these reach chunk data: it carves
the record, writes exposed ore and decorations as overrides, and skips
anything `OreDepletion` remembers as harvested. A cave costs Parts by how
many layers its walls cross (layers never merge with each other), so keep
new cave shapes low and level; see `CaveConfig.DensityMultiplier`.

To add a new public terrain call, write it in the owning module and add
one line to TerrainManager: `TerrainManager.X = Module.X`, or a short wrapper.

### Enemies (server)

`EnemyService` spawns, moves, damages and kills enemies. What a hit looks
like (name plate, flash, damage number, death burst) is in `EnemyFeedback`.
Per-creature behaviour goes in `Creatures/` (CreatureKit, VoxelMoves) or
`Bosses/`, never in EnemyService.

## Dependency rules

- Dependencies point one way. Terrain modules form a DAG, roughly:
  OreDepletion -> GeneratedColumns -> ChunkData -> BlockParts / FaceCulling -> ChunkMesher
  -> ColumnVisibility -> EditZones -> ChunkQueue -> GenerationBudget ->
  ChunkBuilder -> ChunkStreaming / ChunkRegeneration, plus BlockEdits ->
  TerrainExcavation.
  Never require upward. If two modules both need some state, it belongs in
  the lower module (usually ChunkData), not in a cycle.
- Shared tables (`ChunkData.chunks`, `.generating`, `.usage`...) keep their
  identity for the whole server life, so other modules may hold them in
  locals. Never reassign them. Clear them with `table.clear`.
- Mutable counters that other modules read are exposed as getters
  (`ChunkQueue.count()`, `ChunkMesher.visibleBlocks()`). Mutating
  another module's private number is not allowed.

## Performance rules (measured, keep them)

- **Luau inlines only `local function`s from the same script.** Calling a
  tiny helper across modules in a per-block loop cost about 10%
  (`Terrain.columnVisibility` went from 2.37 to 2.61 us per call). For that
  reason `ChunkData`, `FaceCulling`, `ColumnVisibility` and `ChunkMesher`
  keep their own copies of `chunkKey` / `isChunkInBounds` / `normalizeCell`
  / `cellOf`, identical to TerrainGrid. Do the same for any new per-block
  path, and keep the copies identical.
- Localise module functions at the top of a module
  (`local isPresentInData = ChunkData.isPresentInData`). Never call
  `Module.fn` in a hot loop.
- Do not add allocations, closures or string keys in per-cell or per-block
  code. The terrain comments explain each existing cache, pool and
  schedule. Read them before changing one.
- Chunk containers must stay Models, not Folders. See ChunkBuilder.

## Checks

- After any change to `default.project.json`, run
  `C:/Users/Elias/Documents/Rojo/rojo.exe build default.project.json -o <scratch>.rbxlx`.
  A new module needs an entry there.
- There is no local Luau compiler. Compile and behaviour checks run in
  Studio. Sync with the rbxm route: rojo build a small project, copy the
  `.rbxm` into Studio's `content` folder, `game:GetObjects`, then
  `ScriptEditorService:UpdateSourceAsync`.
- Terrain equivalence test: pin `TerrainConfig.WorldSeed` in the Studio
  copy only (never commit it). Run `/tp desert`, then `PivotTo` the
  character to a fixed spot. Hash every chunk's parts (name, position,
  size, face set) and models (name, pivot). Dig fixed cells with
  TestPickaxe via `RequestMineBlock`, then hash again after the 30 s edit
  zone closes. Compare per-chunk hashes, never totals from different spots.
- Caves: `/bbcaves` runs CaveAudit (determinism, chunk borders, cover,
  spawn, decorations, connectivity, counts per category). `/tp cave
  <small|network|large|colossal> inside` puts you in the nearest one.
- Performance: `/bbprof on` ... `/bbprof`. Compare `Terrain.columnVisibility`
  per call, `chunkCpuMs`, `gen.*` and `chunkUnloadMs` on identical
  sequences. Studio runs differ by about 3%.

## Still oversized (candidates, refactor the same way)

`ItemDefinitions` and `EnemyConfig` are data tables, so leave them as they
are. These are logic scripts that would benefit:
`Bosses/SlimeEmperor` (3.1k lines), `Bosses/Blightborer`, `Bosses/AllSeeingEye`,
`CreatureFX.client`, `CraftingClient.client`, `UI/AbilityPanel`,
`EnemyService` (movement and spawning). EnemyService movement runs per enemy
per frame, so the inlining rule above applies to it.
