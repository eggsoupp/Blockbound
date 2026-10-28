# Blockbound - Homeward themes

Current exports: melody, adventure1, adventure2, adventure3, allseeingeye, each as WAV and MIDI.
Exploration tracks remain revision 2. Allseeingeye is revision 5, an electronic boss arrangement.

Allseeingeye: 69.7 seconds, with the drop at 10.435 seconds and 186 BPM thereafter.
The piano intro has the same notes and timing, reduced 4.5 dB from revision 4.
The section after the drop is raised 2 dB RMS relative to revision 4, with gentle peak control.
The guitars are replaced by a wide custom electronic lead, a lower synth layer, pulsing chords
and a flowing synth figure. Piano countermelody, minor harmony, bass and chopped breaks remain.
There are no metallic/glass effects. Power comes from layered music and dynamic contrast.

Broad inspiration: Universal Collapse by DM DOKURO, https://dmdokuro.bandcamp.com/track/universal-collapse
The original Homeward melody and newly written countermelody are retained; no reference recording or transcription is used.

Audio: 44.1 kHz, 16-bit stereo WAV. MIDI has separate named parts and tempo/section markers.
The custom synth instruments use General MIDI proxies; synthesis and drum edits are baked into WAV.
Use compose_allseeingeye_v5.py to rebuild this boss. Earlier exports are in previous_v1 through previous_v4.
The current ZIP includes all current audio and MIDI files. validation.json records the volume and export checks.
Sample source: existing GeneralUser GS by S. Christian Collins; license in .music-tools/GeneralUser-LICENSE.txt.

## Night and cave (compose_night_cave.py)

Two more exploration pieces on the Homeward melody, rendered with the same engine and soundfont.
Rebuild with the bundled Python: `python -I compose_night_cave.py`. Checks are in validation_night_cave.json.

| File | Name | Duration | Description |
|---|---|---:|---|
| night | Under the Stars | 111.2 s | 72 BPM. Music box and celesta over warm pads and slow harp, leaning on E minor; the theme appears once, an octave up, between long quiet passages. Soft wide night reverb. |
| cave | Echoes Below | 109.5 s | 64 BPM. Low piano carries the theme under cello and contrabass drones and a faint choir; sparse kalimba "drips" fall and echo. Long dark cave reverb with a dotted-quarter echo. |

Both fade in from silence and end on a fully decayed tail, so they sit in the game's gaps between tracks.
In game: Shared.Audio.Music plays night after dark above ground, and cave whenever the player is under solid rock; set their ids in Music.Tracks after uploading.

## Boss themes (compose_bosses.py)

Built like Allseeingeye: a quiet 16-beat intro on the Homeward hook, a sudden drop with a tempo change,
then 32 whole bars that the game loops (drop to end). Each states the full theme at least once.
Rebuild with the bundled Python: `python -I compose_bosses.py`. Checks are in validation_bosses.json.

| File | Boss | Name | Tempo | Drop / loop end | Description |
|---|---|---|---|---|---|
| slimeemperor | Slime Emperor | Royal Jelly | 100 -> 152 | 9.600 / 60.126 s | Courtly marimba intro, then a bouncing brass march: tuba leaping octaves, marimba, pizzicato, timpani, kit. |
| signus | Signus | Hallowed Eclipse | 76 -> 168 | 12.632 / 58.346 s | Voices sing the hook over organ; choir and synth lead carry the theme at half speed over harpsichord, organ, strings and orchestral drums, with a Totality bridge. |
| blightborer | The Blightborer | Devourer Below | 66 -> 138 | 14.545 / 70.198 s | Low rumble and deep piano, then chugging synthesized grit chords in E Phrygian, double kick, a gritty theme lead and a half-time breakdown. |

Post-drop loudness is -14.5 dBFS RMS (Allseeingeye -13.9), each drop about 10 dB above its intro, peaks about -1 dBFS.
Grit, lead, bass and drone voices are synthesized in the script; everything else is GeneralUser GS.
