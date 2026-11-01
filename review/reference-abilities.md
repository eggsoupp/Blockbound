# Four new reference abilities

Implemented in BlockBound, place ID **127569658424596**. Sources came from the separate **SoulShroud Ultimate VFX Pack V1.9.rbxl** place. The source place was left intact. Fireball, Azure Comet, Cataclysm, their plans and VFX, and all existing ability definitions were preserved.

| Clip | New ability | Gameplay |
| --- | --- | --- |
| 20:28 | Violet Tempest | Ground anticipation followed by three violet lightning strikes |
| 20:40 | Celestial Lance | Cyan star core, curved charge ribbons, fast projectile and sharp impact |
| 20:44 | Wraithfire Orb | Blue flame orb, orbiting wisps, directional tail and flame detonation |
| 20:49 | Rift Maelstrom | Ground rift, rising vortex rings, four pull/damage pulses and collapse |

Available through the existing `/add` and `/scroll` commands using the names above. Existing loadout keys, mana, cooldown checks and damage services are reused. The new server module resolves hits and emits release/impact/cancellation packets; the new client module draws complete assembly clones through the existing PackAssembly and AbilityScope helpers. PackAssembly gained one optional template argument; existing callers retain their previous behavior. No VFX framework, sounds, visible effect Parts, MeshParts, or copied texture-ID emitters were introduced.

## Complete assemblies actually used

All paths below are in the original library's Workspace. Every selected root was serialized natively with its descendants and dependencies. No selected assembly contains a script or an external attachment dependency. There are no Trails in these selected sources. Their ParticleEmitters, Attachments, Beams, embedded texture/flipbook configuration, and lights remain in the imported templates. Runtime clones adapt color, scale, emission, orientation and timing; hosts stay invisible and pack lights stay disabled.

- `SoulShroud VFX Packs.SoulShroud VFX Pack #2.Spellcasting + Small Impact VFX.SoulShroud Fire VFX.SS FIre VFX 1`
- `SoulShroud VFX Packs.SoulShroud VFX Pack #2.Spellcasting + Small Impact VFX.Soul Shroud Elementals.Lightning Surge`
- `SoulShroud VFX Packs.SoulShroud VFX Pack #2.Spellcasting + Small Impact VFX.Portals.2`
- `SoulShroud VFX Packs.Ki (気) Blasts.Ki (気) Blast 1`
- `SoulShroud VFX Packs.Ki (気) Blasts.Ki (気) Blast 2`
- `SoulShroud VFX Packs.SoulShroud Impact VFX.BZ1 Impact VFX #1`
- `SoulShroud VFX Packs.SoulShroud Impact VFX.BZ1 Impact VFX #12`
- `SoulShroud VFX Packs.SoulShroud Impact VFX.BZ1 Impact VFX #20`
- `SoulShroud VFX Packs.SoulShroud Impact VFX.BZ1 Impact VFX #36`
- `SoulShroud VFX Packs.SoulShroud Impact VFX.BZ1 Impact VFX #37`
- `SoulShroud VFX Packs.SoulShroud Impact VFX.BZ1 Impact VFX #41`
- `SoulShroud VFX Packs.SoulShroud Impact VFX.BZ1 Impact VFX #45`
- `Weather VFX.Weather I.Stylized Thunder / Lightning ` (source name includes a trailing space)

Three additional complete candidates remain in the imported source folder from visual evaluation: Flame Core, SS FIre VFX 9 and Impact #10. They are not used by the final spells. The native model and the full 16-root manifest are in `assets/vfx-library/ReferenceAbilitySources.rbxm` and `ReferenceAbilitySources.sources.json`, mapped separately in Rojo. All 16 imported assemblies matched their source instance counts and critical emitter, flipbook, attachment, part and beam properties. Original library assets were not rewritten.

## Verification

- Real RequestAbility casts and server damage against registered, held Ghost targets. Celestial direct/splash: **36 / 16.2**; Wraithfire: **32 / 14.4**; Tempest: **10 + 10 + 28**; Maelstrom: **7 + 7 + 7 + 7 + 28**. Direct targets did not also receive splash.
- Visual iteration through ordinary running LocalScripts, sampled across charge, release, impact and decay using the normal third-person camera. Tested terrain obstruction, a moving caster, and three overlapping casts. Trees were temporarily moved in the running test server to obtain a clear test area, then restored. Test loadouts were restored.
- Movement test traveled **7.2 studs** during a cast. Three overlapping effects returned to **zero**. Explicit cancellation, actual Tool unequip, death and character reset cleared the effects. A separately instrumented reset test confirmed one active effect before reset and **zero on the first Heartbeat after CharacterRemoving**, before the lifetime backstop.
- No visible VFX hosts or sounds were found. Final smoke test after the source-root integration found **zero broken beam links** and zero remaining effect folders. No Reference-module runtime errors were logged.
- In this Studio client, three overlapping casts averaged approximately **16.7 ms/frame**, with sampled brief peaks around **41 ms**. This is a local observation, not a cross-device performance guarantee.
- Rojo build passed. Existing ability definitions compare unchanged after removing only the four added entries. Cataclysm files, StarterVFX and CometVFX match their pre-task hashes.

No separate remote observer client, mobile/low-end hardware, or continuous exported gameplay recording was verified. Existing unrelated startup asset/animation warnings remain. Temporary QA scripts were removed from the edit DataModel. Nothing was published.
