# Responsive placement and collection feedback

Placement audio now plays synchronously in InputBegan, before RequestPlaceBlock:FireServer. The server acknowledgement no longer plays audio, preventing delayed duplicate taps. Valid placement feedback is local 2D audio without distance attenuation. Hard/soft placement and refusal instances are created and preloaded during startup.

Hard placement output is now 1.53 at full SFX volume, versus 0.54 previously before distance attenuation. Soft placement uses a different group-owned impact (Magic Poofs Thumpy Wheezy Exhale), starting 40 ms into the file to skip its quiet lead-in, with a 190 ms source excerpt. Its effective output is 1.71 versus 0.468 previously. Neither placement key is throttled. Clip timers are versioned so an earlier play cannot stop a later one.

The old 1.57-second pickup sound is replaced by a short excerpt of the group's UI select/pluck clip, mixed at 1.17 and throttled to coalesce pickup batches. The neon flying cube, broad trail and expanding catch flash were removed. The new visual is a thin 140 ms Trail on an invisible host, with at most six active trails and no catch flash. Inventory authority and grant behavior remain on the server.

Normal client script verification confirmed all three sounds were preloaded, playback was active when Sounds.play returned (about 1.2 ms for that call in the measured run), the soft sound started at 40 ms and stopped after its excerpt, and pickup hosts were invisible and cleaned up. Server-triggered previews ran in the actual client and were inspected via a gameplay screen capture. No old Drop/catch shell instances were observed. This is an engine playback check, not a hardware audio-latency measurement or a subjective listening review.

All four synced scripts passed Studio Luau compilation. Temporary test scripts and preview instances were removed by restarting Play. No new live game version was published.
