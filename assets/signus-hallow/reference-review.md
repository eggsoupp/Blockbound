# Signus reference pass — 19 October 2026

Implemented in `SignusMoves`, `SignusChoreography`, and the existing Signus server/client modules. Effects use textures and flipbooks from the supplied Studio packs, with ParticleEmitters and textured Beams on invisible hosts. Visible travelling blocks represent removed terrain cells.

## Reference mapping

| Move | Reference | Preserved sequence | Adaptation |
| --- | --- | --- | --- |
| Umbral Maelstrom | `x-downloader.com_OsibbR.mp4` | Purple coiling rings contract, lift into upright crescents, then expand with vertical energy spikes and a fade. | Added an advance warning and up to 28 real terrain blocks orbiting and landing around the crater. Timing is lengthened for a boss encounter. |
| Eclipse Judgment | `2026-10-10 19-05-47.mp4` + `0503 (1).mp4` | Hand charge, launched orb, compression at the target, tall energy column with elevated orbit rings, fade. | Combined the similar column attacks into one move; blue becomes purple. Up to 32 blocks lift and land around the impact. |
| Worldrend | `Desktop_2024.06.30_-_18.57.58.02_1.mp4` | Charged sphere, sustained horizontal energy stream, textured fire/wisps along its length, distinct endpoint, ground torn up along its path. | Purple replaces orange. Aim locks for a dodge window instead of reproducing the video's later sweeping beam. Terrain cover can shorten the beam. |
| Totality | Original extension of the spiral reference | Raised casting pose, orbiting blocks, expanding purple rings, eclipse overhead and stronger aura. | Phase transition; no damage. Up to 28 blocks are moved. |
| Lunge / Veil Step | Existing Signus movement | Existing procedural poses and movement retained; particle and beam presentation. | These are retained movement tools, not additional adaptations of the four clips. |

## Visual review

Reviewed in Play mode with actual client LocalScripts. The final beam, projectile/column, spiral contraction and eruption, transformation, eclipse, aura, and retained movement were inspected in the running viewport. The spiral was revised after review to lift its crescents above the orbiting blocks and use thicker textured eruption streaks. The flat smoke layer was replaced with the supplied smoke flipbook. Eclipse color correction was softened so nighttime terrain is not crushed to black.

The effects follow the references' choreography and silhouettes; they are not exact copies of the original assets. The beam's fixed aim and the added physical block motion are intentional differences.

## Runtime checks

- All six active move handlers completed: spiral, lance, beam, totality, lunge, step.
- Observed peak travelling blocks: spiral 28, lance 32, beam 9 simultaneously, totality 28. Counts can be lower when terrain is protected, previously displaced, wet, or lacks safe landing cells.
- Terrain reservations and chunk pins returned to zero after each completed move.
- Mid-flight death cancellation was tested after 32 cells had been lifted: all 32 source cells restored; zero travelling actors, reservations, or pins remained.
- Earlier transaction checks covered successful deposit, duplicate source reservation rejection, rollback, and repeated completion.
- Client visual tag removal destroyed the mounted effect; re-adding the tag mounted it again.
- Distance culling disabled all aura emitters/beams beyond range and restored 21 enabled layers when the camera returned.
- Repeated casts left visible craters and displaced blocks. Subsequent beams were blocked by the resulting terrain.
- Final Rojo project build passed; `git diff --check` reported no whitespace errors.

Damage and terrain decisions remain server-owned. Completed displacements persist through the existing terrain edit system; cancellation restores blocks still in flight. This pass was tested with one Studio client, not a many-player performance test or a published multiplayer session.

## Save scope

Source files are stored in the Blockbound project and synchronized to the open Studio place. `build/signus/reference-check.rbxlx` is a code build check, not a replacement for the authored place containing the asset packs. Saving or publishing the authored place is a separate operation.
