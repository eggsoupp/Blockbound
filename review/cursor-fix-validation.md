# Cursor recovery validation — 2026-11-01

Changed MenuState to separate cursor ownership from movement locking, use a
transparent modal button, and enforce free cursor / visible icon after camera
updates while UI, text entry, the Roblox menu, lost window focus, or recovery
requires it. Closing UI releases ownership without restoring stale mouse state.
Inventory now requests its own cursor ownership and closes on respawn.
F8 releases capture until Shift or an unprocessed right mouse press.

Ran cursor-regression.client.luau as a temporary LocalScript in the running
BlockBound client. All five assertions passed:

- Gameplay camera retains capture when no UI owns the cursor.
- Settings defeats a LockCenter / hidden-icon write repeated every frame.
- Overlapping menu ownership survives one menu closing.
- Inventory cursor ownership works without a movement-locking menu.
- Emergency recovery defeats continuous re-locking.

Keyboard checks: E opened inventory with Default mouse behavior; Tab opened
with Default mouse behavior and Scriptable camera, then closed back to Custom.
F8 followed by Shift removed recovery's modal ownership. Shift's processed
input handling was corrected and retested during this check.

Native shift-lock capture did not engage in this Studio test session, so the
continuous LockCenter injection covers the capture conflict; native first-person
and shift-lock feel should also be smoke-tested in a published client.

git diff --check passed. Rojo build was attempted but failed reading the existing
assets/vfx-library/AbilityVFXLibrary.rbxm with Access is denied. Runtime testing
used the two changed sources copied into the connected Studio place. After
testing, stopped play mode (removing temporary test scripts) and verified both
edit-mode sources match the local files. No publishing was performed.
