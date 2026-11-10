# Voxel enemy rigs

Ten original enemies modelled in code, each split into rig parts with joint
pivots. Nothing here is wired into EnemyService yet: these are the models and
rigs only.

| Rig | Size (studs) | Parts | Look |
|---|---|---:|---|
| `AshenLich` | 7.4 x 15.6 x 5.2 | 9 | Hovering skeletal sorcerer-king. Tattered robe, soul-fire ribcage, bone crown, high collar, caged soul-gem staff |
| `BrassSentinel` | 11.4 x 14.6 x 4.8 | 13 | Clockwork colossus. Furnace core behind a grille, cyclops lens, smokestacks, spinning back gear, hammer fist, tower shield |
| `MantisReaver` | 9.0 x 12.0 x 14.6 | 18 | Upright jade mantis. Raised bone-edged scythes, red compound eyes, folded wings, four walking legs |
| `MoonmothMatriarch` | 17.3 x 12.1 x 4.7 | 11 | Hovering moth queen. Fur mane, feathered antennae, four eyespot wings, glowing tails |
| `Sporeking` | 9.4 x 13.2 x 7.4 | 10 | Mushroom titan. Glowing-spotted cap, mycelium veil, ember eyes, root-knuckled arms that reach the ground |
| `RimewyrmDrake` | 20.6 x 13.2 x 19.0 | 15 | Frost wyvern on its hind legs. Ice-crystal spines, swept horns, frost-lit jaw, two-part membrane wings, crystal tail fan |
| `AbyssalKraken` | 12.6 x 15.4 x 8.4 | 15 | Hovering deep-sea kraken. Tall mantle with lure spots and fins, slit-pupil gold eyes, beak, six two-part tentacles (front pair raised) |
| `Shardstinger` | 9.4 x 13.0 x 16.6 | 24 | Giant slate scorpion with amethyst crystals on its back. Pincers with a moving finger, six two-part legs, five-joint tail and glowing stinger |
| `Gloomrider` | 5.6 x 18.0 x 13.6 | 19 | Horned death knight on a skeletal warhorse with ghost fire in its ribs, mane and tail. Rune lance, kite shield, tattered cape |
| `TempestDjinn` | 10.0 x 15.8 x 5.6 | 12 | Four-armed storm spirit. Gold bands, crimson sash, lightning topknot, storm orb in one hand, body ending in a two-part cloud vortex |

`previews/<Name>.png` shows each rig from the front 3/4, side and back 3/4.
The last panel colours each part separately and marks every pivot with a
cross.

## Files

- `vox/<Name>.vox`: MagicaVoxel scene. Each rig part is a named object, so
  you can select one in world mode and press Tab to edit it. Glow colours
  carry an emissive material.
- `roblox/data/<Name>.lua`: greedy-merged boxes per part, plus pivots and
  parents.
- `roblox/BuildEnemyRigs.lua`: Studio (Edit) builder. It makes one union per
  part, a Motor6D at each pivot, an invisible HumanoidRootPart, and an
  AnimationController with an Animator.
- `rigging.json`: every part with its parent, pivot (voxels, Roblox axes),
  voxel count and the role of its joint.
- `source/`: `VoxLib.pm` (modelling kit), `VoxOut.pm` (writers and preview
  renderer), `designs/<Name>.pl` (one file per creature), `build.pl`.

## Rig layout in Roblox

The built rigs are in `ReplicatedStorage.EnemyRigs`. These are place assets,
so save the place to keep them.

```
<Name>                    Model, PrimaryPart = HumanoidRootPart, pivot = floor centre
  AnimationController
    Animator
  HumanoidRootPart        anchored, invisible
  <Part>                  union per part, unanchored, massless
    <Part>  Motor6D       Part0 = parent part ("Root" for the first part -> HRP)
```

- **Axes:** +X is the creature's right, +Y is up, and the front faces -Z.
- **Joints:** each Motor6D's C0 and C1 are axis-aligned at the pivot.
  `Transform` rotates the part about the joint in model axes, and the rest
  pose has every Transform at identity.
- **Animation Editor:** the rigs open in it directly.
- **Joint info:** each Motor6D has a `Role` attribute that says what the
  joint is for.
- **Model attributes:** `ArticulatedRig = true` and `VoxelSize`.

## In the game

All ten are live enemies. Each spawns rarely (`spawnWeight` 0.12, alone) in
one biome and fights with three or four signature moves.

| Enemy | Biome | Health | Moves |
|---|---|---:|---|
| Ashen Lich | Corruption | 320 | soul bolts, grave rise, soul nova, claw |
| Brass Sentinel | Desert | 420 | hammer quake, shield bash, furnace |
| Mantis Reaver | Plains | 300 | cross slash (bleed), pounce, whirl |
| Moonmoth Matriarch | Hallow | 280 | moonbeam, gale, eyespot dazzle |
| Sporeking | Swamp | 380 | smash, spore cloud, spore mortar |
| Rimewyrm Drake | Snow | 450 | bite, frost breath, tail sweep, winter gust |
| Abyssal Kraken | Swamp | 400 | tentacle slam, grab and bite, ink burst |
| Shardstinger | Hallow | 340 | pinch, venom sting, shard eruption |
| Gloomrider | Crimson | 380 | lance charge, lance sweep, rearing stomp |
| Tempest Djinn | Desert | 360 | storm orb, stormcall, flurry, cyclone |

How it fits together:

- **Models:** `ReplicatedStorage.EnemyAssets.<Name>` are copies of the
  `EnemyRigs` rigs at scale 0.68, with `HumanoidRootPart` renamed `RootPart`.
  Other systems use `HumanoidRootPart` to find players. These are place
  assets, so save the place.
- **Animation:** `Shared/Enemies/VoxelRigs/<Name>.lua` holds each creature's
  procedural idle and walk layer and its keyframed attack clips.
  `VoxelRigs/Player.lua` is the clip player. `CreatureRigs` registers the rigs,
  and `CreatureFX` drives them on the client from the `Pose` attribute.
- **Behaviour:** `ServerScriptService/Creatures/<Name>.lua` is a list of moves
  built on `Creatures/VoxelMoves.lua`. It picks moves by range and cooldown and
  fires damage on the clip's own marks, so a hit lands on the frame of the
  blow. It also handles hit shapes, knockback, slows, damage over time,
  zones and projectiles.
- **Effects:** `VoxelRigs/Effects.lua`, drawn by
  `StarterPlayerScripts/VoxelRigFX.client.lua`. They are built from the pack
  assemblies (AbilityVFXLibrary, WeaponShotLibrary, WishVFXLibrary and the
  Signus libraries), tinted per creature. Ground telegraphs are the pack's
  magic-circle emitters.
- **QA:**
  - Set `ForceMove = "<move>"` on a spawned enemy (Server context) to make it
    use that move next tick.
  - `workspace:SetAttribute("VoxelDebug", true)` logs each move and hit.
- **Config and loot:** `EnemyConfig` (definitions and `Order`) and
  `EnemyDrops`.

## Rebuilding

The repo has no Python, so the scripts use Perl (Git Bash ships it):

```bash
cd assets/voxel-enemies/source
perl build.pl                      # all designs
perl build.pl Sporeking --scale 6  # one design, bigger preview
```

To get rigs into Studio:

1. `rojo build ../roblox/import.project.json -o <Studio>/content/enemyrigs.rbxm`
2. In an Edit execute, load it with `game:GetObjects("rbxasset://enemyrigs.rbxm")[1]`.
3. Run `require(folder.BuildEnemyRigs)(require(folder.Data.<Name>), { parent = ReplicatedStorage.EnemyRigs })`.

Rebuilding overwrites the `.vox` files, so back up any hand edits made in
MagicaVoxel first.
