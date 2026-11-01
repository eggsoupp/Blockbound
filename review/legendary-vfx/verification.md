# Legendary reference abilities — verified 31 October 2026

Rebuilt the four existing clip-based abilities as Legendary abilities in **BlockBound, place 127569658424596**. The separate **SoulShroud Ultimate VFX Pack V1.9.rbxl** supplied the complete authored sources and was not edited. Cataclysm and other ability definitions were preserved.

## Latest: additional huge library explosions

Copied five more complete authored assemblies into `LegendaryExplosionSources.rbxm`: Pack #3 **#64**, Pack #1 **#14**, **#102**, **#131**, and Alternate Effects **#27**. Their 71 emitters, 4 beams, 16 attachments, host construction and embedded textures/flipbooks are preserved. Included sources contain no scripts, Trails or external attachment dependencies. Property fingerprints match the originals; runtime clones adapt scale, colour, speed, emission and lifetime. The mesh in #27 is an invisible, noncollidable host, verified in the running client.

- Celestial: Azure Shock, Arc Burst and Mint Rings, enlarged into a layered cyan detonation.
- Blighted: Blue Detonation, Arc Burst and Azure Shock around its existing flame eruption.
- Tempest: Violet Crown, Arc Burst and Azure Shock, producing a wider violet eruption and expanding outer rings.
- Rift: Violet Crown, Mint Rings, Blue Detonation and Azure Shock in successive collapse stages.

All four expanded impacts were inspected live through MCP in ordinary client scripts and the normal gameplay camera. Three moving overlapping casts averaged **16.71 ms**, p95 **18.59 ms**, peak **45.57 ms** across 384 active frames. Cleanup left zero effects, visible hosts, sounds or broken beams. Post-strike cancellation and the local Rojo build passed. The square-fragment candidate #69 was discarded after visual inspection. Test scripts were removed, play stopped, and the captured loadout (VioletTempest, AstralVerdict, WraithfireOrb) was restored and verified. See [giant-library-validation.json](./giant-library-validation.json) for the latest measurements and exact source mapping. No mobile or separate observer client was tested.

| Reference | Ability | Result |
|---|---|---|
| 20:40 | Celestial Lance | Mint/cyan star charge, six curved ribbons, thicker lance, six impact rays, broad starburst and delayed expanding rings |
| 20:44 | Blighted Fireball (saved ID WraithfireOrb) | Blue-black flame orb, three orbiting wisps, travel tail, large central flame eruption and outer fires |
| 20:28 | Violet Tempest | Ground ring and five vertical lead-in beams, three strikes, branching lightning and radial eruption |
| 20:49 | Rift Maelstrom | Indigo ground rift, six rising rings, five curved arcs, two churning interior layers, four pulses, collapse and delayed radial bursts |

Ranges, windups, damage, mana and cooldowns are tuned in AbilityConfig and ReferencePlan. Ground-targeted projectiles lift their centres above the surface and detonate at the selected destination, while respecting earlier collisions. Existing server authority and damage services are used. The new LegendaryVFX module uses the existing PackAssembly and AbilityScope helpers. No new VFX framework, sound, visible Part/MeshPart VFX, or texture-ID reconstruction was added.

## Complete source assemblies

**23 complete assemblies are used**, from 26 imported candidates. See [assemblies.json](./assemblies.json) for exact original Studio paths, per-ability usage, classes and counts. The latest five roots are in `assets/vfx-library/LegendaryExplosionSources.rbxm`; earlier imports remain in `LegendaryAbilitySources.rbxm` and `ReferenceAbilitySources.rbxm`. The earlier layer lists below are supplemented by the five-source mapping above.

- **CelestialLance:** RefImpact1, RefPortal, LegendBlast, RefKi2, RefImpact12, RefImpact37, RefImpact45, LegendLines, LegendCloudRipples.
- **WraithfireOrb:** RefFire1, RefPortal, RefFire9, RefKi1, RefImpact12, RefImpact41, RefImpact45, RefImpact36, RefImpact1, LegendLines, LegendCloudRipples.
- **VioletTempest:** RefPortal, RefImpact36, RefLightning, RefKi2, RefThunder, RefImpact12, RefImpact37, RefImpact1, RefImpact45, LegendStylizedWind, LegendWindSwirls, LegendLines, LegendCloudRipples.
- **RiftMaelstrom:** RefPortal, RefImpact36, RefLightning, LegendWindSwirls, RefKi2, LegendStylizedWind, RefImpact45, RefImpact1, RefImpact12, RefImpact37, LegendLines, LegendCloudRipples.

All 21 imported roots match their library source properties, including emitter sequences, embedded textures and flipbooks, part transforms, attachment transforms, beam links and attributes. Only the pre-existing SourceAssembly provenance attribute was excluded from comparison. Selected sources contain no scripts, no external attachment dependencies, and no Trails. Every authored descendant is retained in the saved imports. Runtime clones adapt host orientation, scale, color, velocity, emission and timing. Complete unused candidates remain available; they are identified by an empty usedBy list.

## Amplification revision

All four now use larger layered impacts, denser authored streak emission, complete cloud-ripple shockwaves and timed secondary bursts. Celestial has a fuller charge, six ribbons and radial beam spokes. Tempest adds five peripheral lightning forks and a stronger central eruption. Rift has six rising bands, five sweeping arcs and two sustained interior assemblies. Blighted retains its flame body, adding seven outer fires and wider impact layers. Three or more active casts reduce opacity on newly mounted particle layers to limit stacked glare. This revision changes only LegendaryVFX in gameplay code; damage and timing remain unchanged. See [amplification-validation.json](./amplification-validation.json).

## Checks performed

- Ordinary running LocalScripts, real RequestAbility casts and normal Custom gameplay camera. Inspected charge, release, travel, terrain impact, decay, Tempest eruption, and Rift sustain/collapse. Iterated on host orientation, burst velocities, color/density and central fire eruption.
- Some peak captures held particle time at +0.12 seconds for inspection; additional live captures checked motion and decay. The screenshots are visible in the chat.
- Ordinary server scripts registered held test enemies. Tempest dealt 14+14+46; Lance 72 direct / 32.4 splash; Orb 68 direct / 30.6 splash; Rift 10+10+10+10+42. Outside targets were untouched; direct projectile victims did not also receive splash damage.
- Final amplified revision: three overlapping casts while the caster moved **8.27 studs**, visually inspected through MCP. 386 active-effect frame samples: mean **16.71 ms**, p95 **18.56 ms**, peak **49.26 ms** in this Studio session. Peak enabled emitters: 315. These are local measurements, not device guarantees.
- Overlap and cancellation returned to zero effects. Actual tool unequip during charge changed active effects from 1 to 0 on the next Heartbeat, with no delayed release effect.
- Amplified Tempest cancellation at 1.21 seconds, immediately after the main strike, also returned to zero effects with no delayed aftershock remaining.
- Zero visible VFX hosts, sounds, broken beam links, or remaining effects in final checks. No LegendaryVFX or ReferenceAbilities runtime errors.
- Final local Rojo build and source-sync verification completed. Cataclysm files and the prior ReferenceVFX match pre-task hashes; every ability definition after the four edited entries is unchanged.
- Temporary QA scripts removed from the edit place; playtest stopped. All four final Studio sources and editor buffers match local files after newline normalization. Nothing published.

## Limits and remaining issues

The amplification pass restored and verified its starting loadout (VioletTempest, AstralVerdict, CelestialLance), disabled test god mode, restored relocated trees, removed temporary scripts, and stopped play. Studio source and editor buffer both match the final local module.

No separate observer client, mobile/low-end device, or continuous exported gameplay recording was tested. Existing unrelated tool/animation/terrain startup warnings remain. The reference geometry/debris is interpreted using the owned particle and beam assemblies to satisfy the no-visible-geometry constraint. Exact original meshes and textures from the videos were not recreated.

The post-restart white capture problem cleared after a second playtest restart; final visual and performance checks were made with the world rendering normally.
