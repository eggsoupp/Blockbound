# SFX level and placement beside trees

- SFX output raised by 1.8x (about +5 dB), without changing music volume. Placement taps received an additional level lift and less severe treble filtering.
- Shared UI/material sounds, ability sound helpers, Signus, Cataclysm and creature sounds use the same gain and the player's SFX volume setting. Ambient background beds retain their quieter mix.
- Tree meshes were being rejected using their full part bounding boxes. `PlacementGeometry` retains the cheap bounds query for blocks and other solid objects, then uses `GetPartsInPart` only for tagged `TreePart` candidates. Actual trunk/canopy collision still blocks placement; empty space beside the trunk no longer does. Server support, reach and occupancy validation is unchanged.

Normal running client checks freed 16 falsely blocked sample cells beside a generated tree and retained 9 actually colliding cells. An ordinary solid block remained blocked. UI output matched the new gain; muting SFX produced zero volume for both shared and ability playback.

A normal running server Script successfully placed Stone at cell (-18, 53, 27), beside a tree inside the bounds that previously blocked the preview. This was a temporary Play-mode world edit with no inventory consumption. Play mode was restarted afterwards to remove test instances and that temporary block.

All nine synced sources passed Studio Luau compilation; project JSON and whitespace checks passed. Results are recorded in `sfx-tree-placement.json`. No new live experience version was published.
