# Purchased animation pack

Source: `125+ Animations & Weapons Pack.rbxl`.

Creator: **saile stone studios**, Roblox group **275555347**.

The source contains 128 KeyframeSequences across eight categories:

| Category | Clips |
| --- | ---: |
| Blade | 16 |
| Glaive | 10 |
| Grimoire | 14 |
| LightAxe | 17 |
| MediumAxe | 15 |
| Pickaxe | 17 |
| Rapier | 23 |
| Shield | 16 |

## Naming

`SSS_<WeaponCategory>_<Action>[_<SequenceNumber>][_VariantNN]`

Examples: `SSS_Blade_AttackLight_01`, `SSS_Rapier_DashForward_P`, `SSS_Shield_BlockHit_03`.

Light attack numbering follows the source combo numbering. M2 and Heavy become AttackHeavy. Weapon prefixes are removed from action names when the category already supplies them. The source's P suffix is retained because its meaning is unspecified. Distinct source clips are retained even when their names match: Medium Axe contains two `m1_2` sequences, so the second receives `_Variant02`.

Timing, poses, markers, priorities, and loop settings are uploaded from the original sequences. Publishing names do not alter the source names.

`inventory.json` records the full source inventory. `published-animations.json` and `published-animations.csv` record the published asset IDs and ownership verification. `AnimationIds.luau` provides a Lua lookup table for later integration.
