# Controls and island switching verification

Updated the shared source and synced it through Rojo to both Studio places:

- World: `127569658424596`
- Island: `93541670199012`

All 301 scripts mapped by `default.project.json` matched the local source in each place after testing. Both places were returned to Edit mode; temporary runtime QA scripts were discarded with the play sessions.

## Behavior

- Removed the player crouch key binding, crouch speed/height changes, touch attribute handler, and mobile CROUCH button. Shift and mobile RUN remain.
- Selecting an owned island immediately requests travel to its reserved server. The currently loaded island is a no-op. The picker label and marker represent the loaded island, including after a failed switch.
- Closed hotbar mouse clicks and touch taps select equipment. Dragging requires the E inventory to be open. Closing the inventory cancels an outstanding drag.

## Verification

- Ran both places as actual clients: no CrouchAction or touch crouch button; C did not change HipHeight. Sprint reached 25 and returned to 16 in the Island client.
- Mouse clicks equipped WoodSword in both clients and Thunderveil in World, confirmed by the equipped-slot attribute, item label, and server equip request.
- Closed-hotbar drags produced zero swap requests and zero drag clones in both clients.
- E opened the inventory; dragging swapped Stone and Dirt through the server in both places without changing equipped selection. A second drag restored their original order before ending each test.
- The Island client's real IslandMenu request for its current island produced no travel feedback. Selecting the other island immediately produced the existing Studio teleport limitation message. The original active-island preference was restored.
- The isolated routing harness passed 11 checks: current-island no-op, routes to islands 1 and 2, duplicate selection suppression, retries after immediate and delayed teleport errors, World routing, locked/invalid islands, and switching after purchase. All persistence, marketplace and teleport calls in that harness are mocked.
- `git diff --check` passed for the five changed gameplay scripts.

Actual teleport arrival must be verified in a live Roblox server: Roblox Studio does not support teleports. No places were published by this task.
