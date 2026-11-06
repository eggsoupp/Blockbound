# Combat audio audit (2026-11-06)

Every combat clip was measured from the decoded pack (`assets/audio/downloaded`, 804 files): leading silence, attack time to peak, tail length, loudness of the loudest 100 ms, and how its energy splits across sub/low/mid/high bands. Nobody listened; these numbers stand in for listening and are what each choice below rests on.

## What was wrong

- **Impacts landing late.** Several clips start with dead air, and a fresh Sound also spends about 0.3 s loading the first time its asset plays in a session, even after preloading.
  - Thruster Blast 5/9/14/17 (Fireball, Helios and Serpent impacts): 155–180 ms of silence.
  - Synth Blast (Signus spell impacts, Abyss): 190 ms.
  - Rocket Punch bass drop (Cataclysm): 250 ms.
  - Air Suction: 320 ms.
  - Ice Chunk (Comet): 205 ms.
- **Swells used as hits.**
  - Deep boom #2 takes 415 ms to peak. It was used for Signus's spell impacts, Totality, the Rift Maelstrom collapse and Abyss.
  - The bass drop takes 645 ms. The magic warp takes 620 ms.
- **Wrong or very quiet clips.**
  - The Slime Emperor's body slam, the Deluge splash and the Tidecaller water were a water *footstep* at −39 dB, boosted 3×.
  - The energy sword swing was −25 dB.
  - The bird-chirp blooms were −27 dB.
- **One clip per impact.** No transient + body + low end + debris, so hits had no snap and no weight at the same time.
- **Silence where it matters most.**
  - A weapon connecting with an enemy played nothing.
  - A kill played nothing.
  - Being hurt played nothing.
  - Creatures used the engine's `hit.wav` at pitches from 0.3 to 3 for 25 different moves.
- **No mixing.** Nothing ducked the music under a heavy hit. At 40 voices, new sounds were dropped while old tails rang on.

## What changed

- `CombatSoundBank` was regenerated from the measurements.
  - `gain` brings every clip's loudest 100 ms to about −17 dB.
  - `start` skips leading silence.
  - 50 new clips were added; 14 earlier candidates were swapped out because they are private assets (below).
- `CombatRecipes` (new) holds 51 layered impacts:
  - melee by weapon class, kill, and hurt;
  - impacts by material: light, heavy, explosion, fire, lightning, water, ice, blade, energy, grand, slam, debris, dark;
  - whooshes, casts and charges;
  - Signus, the other bosses, and creatures.

  Each layer has its own volume, pitch, delay and random pitch variance. Outcomes are kept apart by spectrum: a weapon hit is a dry mid crack, a kill adds a bright sparkle and a body falling, being hurt is a dull low thump, spells are bigger and wetter, and boss cues bigger again.
- `CombatAudio` changes:
  - It plays recipe names wherever it took a bank key.
  - It skips each clip's leading silence.
  - It keeps one loaded template of every clip in `SoundService.CombatAudioTemplates`, so every play is a clone that starts on its frame.
  - At 48 voices it steals the oldest one-shot instead of dropping the new sound.
  - Heavy recipes duck the music through `Music.duck`.
- **Call sites:**
  - Ability modules: Abyss, Astral, Blossom, Comet, Dawnbreaker, Deluge, Helios, Serpent, Skyfall, Sumi, Thunder, Tide, the starter abilities and Cataclysm.
  - Cue tables: the reference abilities and the four bosses in `CombatCues`.
  - Each of the 25 creature moves in `CreatureFX`, now played through CombatAudio.
  - Weapon swings per class (WeaponClient), weapon hits and kills (TargetFeedback), and being hurt (HealthClient).

## Verified in a running client

- All 107 distinct bank clips load as templates.
- 34 boss cues sent from the server produced 106 layers, every one loaded and already about 80 ms into its clip 80 ms after the cue.
- Hit, kill and hurt confirms play through the real client scripts.
- The Black Sun ducks the music to 0.53 for about 0.55 s and then lets it back over 0.8 s.

## Private assets (do not use)

ContentProvider's PreloadAsync reports "Success" for these, but the experience has no permission to play them: a Sound never reaches `IsLoaded`, and the output reads "The experience doesn't have access permission". Check new IDs with a Sound reaching `IsLoaded`, not with PreloadAsync.

- 14161581974, 14161582080, 14161582194, 14161582737, 14161582933, 14161583034 (bullet impacts)
- 77088118337834, 76881754710917 (ragdoll hits)
- 117173295385522, 124306736580115 (impact strings)
- 126175381632815 (AxeHit)
- 125963425455297 (explosion)
- 135768348032616 (orb collect)
- 84683157850061 (plasma charge)
- 1489924400 (bullet hit)

## Not done

- **No listening review.** Levels and choices come from measurements.
- **Weapon swing sounds** were not heard through an actual swing, because the test character couldn't keep a borrowed sword equipped. The hit and kill confirms were driven through the real scripts.
- **Mining, UI and ambience sounds** are unchanged.
