from pathlib import Path
import json
root=Path(r'C:\Users\Elias\Downloads\LihFolk Vault V1 Lite')
base=root/'LihFolk Vault V1'
notes=base/'Blockbound'
notes.mkdir(exist_ok=True)
vfx='''# Blockbound VFX — mandatory preferences and proven workflow

## User requirements
- Source VFX directly from the user's supplied asset place and existing imported packs. Do not create your own textures, generate flipbooks, invent texture IDs, or reconstruct an authored effect from a few copied texture IDs. If an asset is missing, identify it and ask before creating a replacement.
- Use ParticleEmitters, Beams, Trails and the pack's authored textures/flipbooks. No visible Parts/MeshParts for flashes, warning circles, shockwaves, speed streaks or cosmetic debris. Invisible noncollidable hosts are fine. Explicitly requested physical objects, such as a dirt-and-stone meteor, may use blocks; this is a narrow exception.
- Inspect the actual asset place and preview candidates. Names and static texture thumbnails alone do not establish how an effect looks in motion. Preserve the source place.

## Import and composition
- Known source: SoulShroud Ultimate VFX Pack V1.9.rbxl. Locate the currently connected source place; do not assume it is the gameplay place. Recorded gameplay place: BlockBound, 127569658424596.
- Clone/import complete authored assemblies with emitters, attachment transforms, beam endpoints, sequences, attributes and flipbook settings intact. Check external attachment dependencies and embedded scripts before use. Keep cosmetic hosts invisible and noncollidable.
- Existing imports: assets/vfx-library/ReferenceAbilitySources.rbxm, LegendaryAbilitySources.rbxm, LegendaryExplosionSources.rbxm. Use their manifests and review/legendary-vfx/assemblies.json for exact source mapping; do not guess paths.
- Reuse src/ReplicatedStorage/Shared/Abilities/VFX/PackAssembly.lua and Abilities/AbilityScope.lua. Adapt runtime clones for scale, tint, orientation, speed, emission and timing. Do not alter master templates or build a new framework for each effect.
- Establish silhouette, palette, gameplay scale and timing first. Give anticipation, release, impact and decay distinct roles where appropriate. Layer authored effects deliberately; adding brightness and particle count alone does not improve quality.
- Known examples: Celestial Lance uses cyan charge/ribbons and layered impact; Blighted Fireball uses flame body, orbiting wisps and tail; Violet Tempest uses lead-in beams, strikes and radial eruption; Rift Maelstrom uses rising rings, curved arcs, pulses and collapse. Saved Blighted Fireball key remains WraithfireOrb.

## Runtime and acceptance
- Test in an ordinary running LocalScript through real RequestAbility/gameplay events or a client harness. Direct MCP execution can fail to render otherwise working particles; do not diagnose missing assets from that alone.
- Inspect multiple moments at the normal gameplay camera: charge, travel, impact, decay; also movement and overlapping casts. Screenshots verify composition, not continuous motion. Iterate visibly before declaring success.
- Server owns hit resolution, damage and cooldowns; client renders cosmetics. Prevent direct plus splash double damage. Retain existing ability balance unless the task asks to change it.
- Cancellation must stop delayed releases/aftershocks and clear effects on unequip, death and character replacement. Validate no broken beams, visible hosts, lingering folders, tasks or connections. Restore test loadouts/environment and remove QA scripts.
- Do not add sound automatically. Prior reference/fireball passes intentionally used no sounds; follow the current request.
- Prior three-cast Studio samples were about 16.7 ms/frame, with brief larger peaks. These are historical local observations, not a mobile or current performance guarantee. Separate observer clients and low-end devices were not verified in those passes.

Evidence: Blockbound AGENTS.md; BLOCKBOUND-VFX-METHOD.md; review/reference-abilities.md; review/legendary-vfx/verification.md; review/fireball-revision.md. This note's explicit user restriction on new textures overrides the older method's optional custom-asset section.
'''
animation='''# Blockbound animations — proven integration lessons

## Asset selection
- Use the purchased 125+ Animations & Weapons Pack.rbxl and verified published inventory. Source creator/group: saile stone studios, 275555347. Files: assets/animations/125-pack/inventory.json, published-animations.json, AnimationIds.luau, pickaxe-right-arm.json.
- Inspect actual poses, moving joints, markers, rig compatibility and playback. Never trust a clip's label alone: LightAxe's labelled Idle was a gait and visibly moved the legs.
- Latest recorded correction: Sword/Axe idle 89807765848542, walk 105304620701106, run 116843864841470. This supersedes the older locomotion note saying LightAxe has no walk. Recheck current source before editing mappings.
- Weapon mappings recorded for attack integration: HeavySword -> Blade, Lance -> Glaive, Sword -> LightAxe. Glaive lacked locomotion; Rapier gaits were the recorded fallback. Preserve distinct source variants and existing working gaits.

## Layering and movement
- Pickaxe locomotion uses normal unarmed legs plus right-arm carry overlays. Only RightUpperArm, RightLowerArm and RightHand have nonzero weights in the adapted clips. Avoid whole-body tool clips overriding leg motion.
- Recorded overlays: walk 134569109224529, run 133950607844393; mining swing 87021460185064, 0.7 seconds, at Action2 over the Action carry overlay. Unarmed walk/run were 913402848/913376220. Consult the manifest for other clips rather than inventing IDs.
- Movement detection must consider grounded state, input, velocity and measured displacement. Nonzero MoveDirection while blocked should not animate walking. Stop grounded overlays when airborne.
- Equip/unequip, stopping, sprint release/cancel, death and character replacement must stop or replace stale tracks. Serialize asynchronous asset-loading callbacks so an old equip cannot start playback later. Handle sprint release before menu/camera early returns.

## Combat timing
- Use all five published light-attack steps where configured. Derive contact, swing audio and recovery from actual Hit, Swing and Reset markers; scale animation and the server timeline together with attack speed.
- Server validates equipped tool, living state, cooldown and class, then selects combo, targets and damage. Client input is intent, not trusted animation IDs/damage/targets. Warm tracks before attacks so loading does not consume windup.
- Recorded integration sampled contact at 30 Hz for up to 0.12 animation seconds after Hit, ending before Reset. Damage once per enemy per swing, with a shared target cap. Unequip cancels pending hits; swapping preserves recovery. Treat these as existing behavior, not universal tuning defaults.

## Verify in Play
- Nonzero AnimationTrack.Length proves loading, not a correct pose. Visually inspect idle, walk, sprint, stop, equip transitions and the attack contact pose in the running client.
- Check tool and unarmed profiles, blocked movement, airborne transitions, release while sprint is held, interrupted swings and respawn. Confirm ownership/access when an asset fails to load.
- Existing implementation: src/ReplicatedStorage/Shared/Combat/WeaponAnimations.lua and Shared/Tools/LocomotionAnimations.lua, LocomotionProfiles.lua, SwingAnimations.lua, ToolAnimation.lua. Inspect current sources before changes.

Evidence: review/animation-idle-pickaxe-fix.md (latest correction); review/weapon-animation-validation.md; review/locomotion-fixes.md (older); assets/animations/125-pack/README.md. IDs and tests are historical project records, not newly verified playback.
'''
(notes/'VFX.md').write_text(vfx,encoding='utf-8')
(notes/'Animations.md').write_text(animation,encoding='utf-8')
addition='''\n## Blockbound priorities
For VFX work, read LihFolk Vault V1/Blockbound/VFX.md (or Blockbound/VFX.md from the content folder). Use the supplied asset place's complete authored effects. Never create new textures/flipbooks or substitute visible geometry without explicit user authorization.
For animation work, read the corresponding Blockbound/Animations.md. Inspect real poses and markers; prefer the latest project corrections over older generic notes.
Load only the relevant one of these notes, on demand. Source project: C:/Users/Elias/Documents/Blockbound. Current project code and explicit user requests take precedence over historical records.
'''
for folder in (root,base):
    for name in ('CLAUDE.md','AGENTS.md'):
        p=folder/name
        content=p.read_text(encoding='utf-8')
        if '## Blockbound priorities' not in content:
            p.write_text(content+addition,encoding='utf-8')
print(json.dumps({str(p):p.stat().st_size for p in notes.glob('*.md')},indent=2))
