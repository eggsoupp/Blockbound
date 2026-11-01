# Locomotion fixes

Updated Studio BlockBound (127569658424596) and repository sources.

- ToolWalk now explicitly resolves unarmed, sword, heavy sword, lance,
  pickaxe and axe profiles from published assets.
- Empty hands use the available basic R15 idle/walk/run; no weapon-arm
  adaptation is required. Pickaxe uses its published pack's three gaits.
- LightAxe has no walk: its run is slowed at walking speed. Glaive has no
  locomotion: lance uses the published Rapier idle/walk/run as a fallback.
- Movement requires ground contact, input, velocity, and measured displacement.
- Equip, unequip, airborne states and character replacement stop the old track.
- Asset-loading callbacks are serialized to avoid overlapping stale plays.
- Sprint input handles release/cancel before menu/camera guards and exposes
  Sprinting for the animation controller. Removed the unused inaccessible
  sprint animation (10862419793).

Validation in a normal running client:

- All 18 profile slots loaded with nonzero animation lengths.
- Unarmed walk at 16 studs/s; unarmed run at 25 studs/s.
- SwordRun -> UnarmedRun on unequip while moving.
- Stopping with sprint held -> UnarmedIdle.
- Blocked motion (anchored root, nonzero MoveDirection, sprint held) -> idle.
- Sword and pickaxe stationary states select their published idle tracks.
- Airborne state stops the grounded overlay.
- Visually inspected the unarmed idle and group-owned sky in the running client.
- Rojo full-project build succeeded. Temporary QA platform, scripts and tools
  were limited to play mode and removed by stopping the test.

The existing attack combos and their hit-marker timing were retained.
