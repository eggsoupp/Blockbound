# Animation correction — 2026-11-01

The LightAxe asset labelled Idle (105304620701106) contains a gait: its left thigh swings from -0.46 to +0.93 radians. Sword used it at rest and fell back to the Run clip for walking. Corrected Sword and Axe to idle 89807765848542, walk 105304620701106, run 116843864841470.

Published four new pickaxe clips under group 275555347, recorded in assets/animations/125-pack/pickaxe-right-arm.json. Only RightUpperArm, RightLowerArm and RightHand have nonzero weights. ToolWalk plays unarmed locomotion plus a right-arm carry overlay. Mining uses the right-arm-only swing at Action2, above the Action carry overlay. Original assets remain unchanged.

Running-client validation:
- Sword idle uses 89807765848542; screenshot shows planted legs.
- W: SwordWalk, speed 16, clip 105304620701106.
- Shift+W: SwordRun, speed 25, clip 116843864841470.
- Release: SwordIdle.
- Pickaxe walk: normal 913402848 plus right-arm 134569109224529, speed 16.
- Pickaxe sprint: normal 913376220 plus right-arm 133950607844393, speed 25; visually inspected.
- Release: PickaxeIdle, speed approximately 0.002, normal idle plus right-arm idle; visually inspected.
- Mouse-held mining loads 87021460185064 at Action2, length 0.7 seconds.
- Downloaded all four published clips and verified only the three right-arm joints have nonzero weights; MarketplaceService confirms group ownership for each.

Sources synced into Studio Edit. Test floor and tools were play-session-only and removed by stopping Play. Game publication was not performed.
