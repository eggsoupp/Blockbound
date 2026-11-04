# Downloaded sound review

Source: `Downloads/SFX (2).zip` → nested `SFX.zip`. Extracted 804 OGG files.

`inventory.json` records source paths, durations, sample rates, channel counts, peak/RMS levels, clipping fractions, and hashes. `selected.json` maps 29 proposed game sound keys to source filenames and prepared upload copies in `publish/`.

## Selection

- UI: hover, click, tab/select, inventory open, close, denied, notification, crafting confirmation, loot pickup.
- Abilities: charge, ice break, heavy ground impact, lightning burst, magic cast, magic glow, magic poof, portal, shield on/off, whoosh.
- Ambience: fire, night, light rain, heavy rain, sea, snow, thunderstorm, waterfall, wind.

Excluded the `Explosion HD` candidate because approximately 1.1% of decoded samples were clipped. Excluded gunfire, spoken kill announcements, alarms, vehicle sounds, and recognizable game-named clips from this initial shortlist on suitability grounds.

## Preparation and verification

All 804 source files decoded successfully. Selected files were level-adjusted with a peak ceiling and exported as lossless 16-bit FLAC for Roblox import. Original downloads remain intact. `prepare.py` regenerates the inventory and upload files. Sample peaks and RMS are technical checks, not perceptual loudness measurements.

No subjective listening review was completed: the current assistant session cannot receive audio input. Audition montages in this directory are optional review aids, not evidence that the assistant heard them.

## Upload state

Uploaded all 29 selected files privately under `saile stone studios` (group 275555347), after the user confirmed re-upload rights and accepted group-member access. No Creator Store distribution was enabled. The displayed upload fee was zero Robux. `published.json` records all new IDs, verified against group inventory. Marketplace product metadata for all 29 returned the correct group creator, Audio type, `IsForSale=false`, and `IsPublicDomain=false`.

## Integration and client checks

The source project and open Studio edit place contain the integration. This work did not publish a new live game version.

- UI mappings retain existing keys; hover, click, tab, panels, crafting and loot pickup use the group audio. Tool swings also use the imported whoosh.
- Starter, Astral, Blossom, Comet and Thunder VFX use selected imported effects. All eleven ability clips are available through `SoundConfig` keys and `DownloadedSounds` for further authored use.
- `Ambience` starts from `SoundHandler`: quiet wind by day, natural night ambience, snow and coast beds, and weather-driven rain/storm beds. Outdoor beds are suppressed under cover and crossfade between states. There is no new weather generator.
- Spatial loops can be attached to BaseParts/Attachments tagged `BlockboundAmbience`, with `AmbienceKey` set to `fire`, `sea`, etc. Fire spatial playback and tag-removal cleanup were checked in a normal client LocalScript.
- The SFX volume control mutes and pauses ambient playback. This was verified from an actual running client script, as was the rain fallback.
- Imported positional charge sounds now survive the old four-second cleanup limit.

`client-load-results.json`: all UI and ability uploads plus seven ambience uploads loaded successfully (27/29 total). Light rain (`106908818229091`) and waterfall (`109920952255959`) returned `Asset is not approved for the requester` on repeated client checks. Their files and IDs are retained, but light rain currently uses the approved heavy-rain asset at a quieter level, and waterfall spatial playback is disabled. Do not re-upload to work around moderation; review their status through Roblox.

`client-integration-results.json` records passing rain playback, SFX mute/pause, spatial fire playback and spatial cleanup checks. Eleven changed script sources passed Studio Luau compilation. Temporary test LocalScripts were removed, and Studio was returned to Edit mode. Existing unrelated texture and tool warnings were observed and left outside this audio task.

`integrate.py` was a one-time source migration; do not rerun it on the integrated project. Edit the runtime modules directly. `make_sync.py` generates an exact source sync for the changed-files list; it validates all scripts before writing any source.
