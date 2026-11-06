# Ability and boss audio assignments

Source library: `C:\Users\Elias\Downloads\SFX (2)\SFX.zip`, also present inside `Downloads\SFX (2).zip`. The earlier extraction and inventory in `assets/audio/` contain 804 decoded OGG files.

Selected 58 additional ability/boss candidates. A normal Studio client loaded 50 successfully; the eight unavailable candidates are retained only in the review records and are not assigned. The game references the original Roblox asset IDs recorded in the filenames. No additional uploads or changes to the original downloads were needed. The combat bank combines these 50 clips with the 11 existing group-owned ability clips.

## Player assignments

| Ability | Main stages and sounds |
| --- | --- |
| Fireball | Magic poof, thruster launch, fire impact |
| Wind Burst | Breathy pressure burst |
| Water Blade | Air swing, water impact |
| Echo Step | Magic warp |
| Block Wall | Heavy earth/metal landing |
| Violet Tempest | Magic cast, lightning cracks and deep strike body |
| Celestial Lance | Electric charge, plasma launch, energy impact |
| Blighted Fireball (`WraithfireOrb`) | Dark cast, thruster launch, flame and synth impact |
| Rift Maelstrom | Suction, portal pulses, reverse portal and deep collapse |
| Cataclysm | Short charge, falling whoosh, deep boom and bass impact |
| Dawnbreaker | Energy sword, heavy hit |
| Deluge | Gathering bubbles, water impact and deep body |
| Skyfall Volley | Charge/draw, arrow impacts, heavy final whoosh |
| Sumi Whirl | Sword swing, plasma cut, heavy hit |
| Blossom Road | Air poof, chiming blooms, sparkle finale |
| Helios Lance | Power-up charge and flame blast |
| Abyss Gate | Warp call, deep boom and synth impact |
| Azure Comet | Airy plasma movement, short blast and ice debris |
| Thunderhead | Electric gathering, close lightning and shock accents |
| Tidecaller | Water gathering/impacts and air launches |
| Serpent Flare | Airy plasma movement, distinct flame strikes and finale |
| Astral Verdict | Chiming stars, sword movement, energy and blade impact |

## Boss assignments

- **Signus:** casting, Worldrend charge/fire/contacts, spell impacts, blade breaks, lunges, Black Sun, Totality, crown, movement and death. Struck blade breaks use a different glass clip from terrain collisions. The sustained Worldrend loop follows its existing choreography and respects the SFX setting.
- **Blightborer:** underground rumble, eruption, dive, furrow warning/travel, spit, splash, sinkhole warning/collapse, segment burst, brood and death.
- **Slime Emperor:** each of the seven attack/phase announcements, body slam, coronation impact, rain impacts and death.
- **All Seeing Eye:** all six attack announcements, committed dash, gaze beam, falling rock and tear impacts, transformation and death.

Player projectile contacts follow the existing authoritative `AbilityImpact` packets. Boss presentation uses `BossEffect`; audio-only messages add cues to Slime Emperor and All Seeing Eye without requiring visual modules for them. Existing damage, cooldowns and attack decisions are unchanged.

## Playback

`CombatSoundBank.lua` records verified IDs, measured-level gain adjustments, durations and short excerpts for long sources. `CombatAudio.lua` handles spatial distance, a 40-voice limit, nearby-repeat throttling, live SFX volume updates and cleanup. Impact hosts are invisible and independent of visual teardown; sustained loops follow their carriers and scopes. `CombatCues.lua` contains reference-spell and boss stage assignments. Existing authored VFX timelines retain their sound timing through `AbilityKit`.

## Validation

- 28 changed scripts compiled successfully in Studio.
- All 22 active ability VFX modules loaded in a normal client; all four boss modules loaded on the server.
- All 61 combat-bank clips loaded, entered playback, advanced their playheads and used invisible spatial hosts.
- Client checks passed for detached impact tails, clipped playback cleanup, spatial throttling, cancellation, live mute/unmute, the 40-voice cap and complete cleanup.
- Seven representative ability presentations and ten boss cues produced sound through the normal game remotes. The actual client presentation was visually inspected.
- Targeted sustained-beam checks are recorded in `client-beam-results.json`.
- `git diff --check` passed. The full Rojo build was blocked by an existing access-denied error on `assets/vfx-library/AbilityVFXLibrary.rbxm`; direct Studio compilation and runtime checks covered the modified scripts.

These checks establish technical playback and event wiring. No subjective listening review was performed. Existing unrelated tool and VFX texture warnings were observed. The experience was not published as part of this work.

`selected.json` records source filenames and IDs. `client-load-results.json`, `client-integration-results.json` and `client-remote-results.json` contain the verification records. `studio-before-sync.json` preserves the previous Studio sources; `sources.json` records the applied sources. Temporary test LocalScripts were removed and Studio was returned to Edit mode.
