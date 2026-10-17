# Signus — Roblox import, rig and animations

| File | What it is |
| --- | --- |
| `signus_hallowed_eclipse.glb` | The model: five meshes, one embedded opaque palette texture |
| `signus_palette.png` | The same 512 × 16 texture, one 16 px cell per palette colour |
| `export_report.json` | Triangle counts, bounds, pivots and the checks below |
| `previews/` | Renders of the GLB, and `glb_vs_vox_multiview.png` beside the original previews |
| `CreateSignusRig.server.lua` | Studio Command Bar script that builds the Motor6D rig |

Rebuild everything here from the `.vox` with `python ../source/export_roblox_glb.py`
(Python 3, NumPy and Pillow, like `build_signus.py`). It refuses to run if the
`.vox` no longer matches `../validation.json`.

## The export

Scale 0.125 studs per voxel. Roblox (X, Y, Z) = Source (−X, Z, Y): up is +Y and
the front faces −Z. The scene origin is the Core pivot, source (0, 0, 80).
Overall size **12.5 × 18.25 × 6.25 studs**.

| Mesh | Triangles | Pivot (studs from origin) | Moves as |
| --- | ---: | --- | --- |
| Core | 14,552 | (0, 0, 0) | Core |
| CoreLower | 14,714 | (0, 0, 0) | Core (welded) |
| Hood | 6,926 | (0, 3.5, −0.375) | Hood |
| LeftSleeve (source "04 Right Crescent Sleeve") | 4,424 | (−3.375, 1.75, −0.25) | LeftSleeve |
| RightSleeve (source "03 Left Crescent Sleeve") | 4,424 | (3.375, 1.75, −0.25) | RightSleeve |
| **Total** | **45,040** | | |

Every exposed voxel face is kept, merged into rectangles per plane and per
colour. Normals are flat, edges hard, and nothing is bevelled or smoothed. Each
quad samples only the middle of its palette cell, so Roblox's texture filtering
and compression can't blend in a neighbouring colour. There is no transparency,
lighting, floor or background. The eyes' subtle emission in the `.vox` is not
exported, because Roblox MeshParts have no emissive channel. The eye colours
themselves are kept.

The exporter reads the GLB back and checks it before writing the report:

- Every mesh is under 20,000 triangles.
- Each mesh covers exactly the faces its voxels expose, each face in its own palette colour.
- Each triangle's winding agrees with its normal. Each object's surface is closed, faces outward, and encloses exactly its voxel volume.
- The pivots and overall size match the numbers above.
- Front is −Z: the eyes face −Z and the chest jewel is on the −Z side.

### Three things that differ from the brief

**The Core is two meshes.** Roblox won't import a mesh of 20,000 triangles or
more. The Core's exact surface needs about 29,000, and no exact merge got it
under 24,000: its curved folds are voxel staircases, and each stair step costs
two triangles. So it's split at source z = 68 into **Core** and **CoreLower**.
They share the Core's pivot, and the faces between them are inside the solid,
so nothing shows at the seam. The rig welds CoreLower to Core. There are still
four moving components and four Animation Editor tracks.

**The conversion is Source (−X, Z, Y), not (X, Z, Y), and the sleeve names
swap.** A plain Y/Z swap also gives +Y up and the front on −Z, but it is a
reflection: every asymmetric detail, such as the lower rear thorn and the tilt
of the cowl, would land on the other side. Negating X makes it a rotation, so
the model looks exactly as it does in the previews. `glb_vs_vox_multiview.png`
shows it, and `export_report.json` measures it: each GLB view matches the voxel
render to within 0.34 % of pixels, all at silhouette edges. Roblox names sides
from the creature's own point of view: −X is its left, as with an R6 "Left
Arm". The source names its sleeves from the viewer's side. So the source's
"04 Right Crescent Sleeve" sits at −X and is **LeftSleeve**, and "03 Left
Crescent Sleeve" is **RightSleeve**. The pivots are exactly the ones in the brief.

**The joints hinge at the anatomical pivots, so C1 is not the identity.**
Roblox centres every MeshPart on its own bounding box, and the importer isn't
documented to keep the file's origins as a PivotOffset. With
`C1 = CFrame.identity`, each part would turn about its middle: a sleeve would
spin about mid-sleeve rather than its shoulder. The rig script therefore
derives both C0 and C1 from the parts' current CFrames, with the hinge at the
pivot. Nothing moves when the rig is built. To get the brief's literal
`C1 = CFrame.identity`, set `HINGE_AT_PART_CENTRE = true` at the top of the script.

## Importing into Studio

1. **Home › Import 3D**, pick `signus_hallowed_eclipse.glb`.
2. In the importer:
   - **File Transform**: World Forward = **Front**, World Up = **Top**.
   - **File Geometry**: Scale Unit = **Stud**. If a **Merge Meshes** option is offered, leave it **off**.
   - Insert in Workspace. The importer's Anchored setting doesn't matter: the rig script sets anchoring.
3. Import. You should get one Model holding five MeshParts: Core, CoreLower,
   Hood, LeftSleeve and RightSleeve. They share one texture.

## Building the rig

1. Select the imported Model, and nothing else.
2. Paste all of `CreateSignusRig.server.lua` into **View › Command Bar** and press Enter.

The script checks everything before changing anything. If a part is missing,
isn't a MeshPart, is the wrong size, or isn't where the export placed it (a
wrong forward axis, a mirrored axis, the wrong unit), it stops and says so.
It then builds:

- the Model renamed to **Signus**, with attribute `ArticulatedRig = true`;
- **RootPart**: a 1-stud invisible part at the scene origin. It is anchored, has CanCollide, CanTouch and CanQuery off, RootPriority 127, and is the Model's PrimaryPart;
- **AnimationController › Animator**;
- the Motor6Ds **CoreJoint** (RootPart → Core), **HoodJoint**, **LeftSleeveJoint** and **RightSleeveJoint** (Core → each), plus the Weld **CoreLowerWeld** (Core → CoreLower);
- every MeshPart unanchored and massless, with CanCollide, CanTouch and CanQuery off and CastShadow on.

It prints an `OK`/`FAIL` line for each result. When the model is in Workspace,
it also moves the model with `Model:PivotTo`, then moves the RootPart alone,
checks the parts stay assembled both times, and puts the model back. Running
it again rebuilds the joints in place: nothing is duplicated, and the
RootPart, AnimationController and Animator are reused. It is one undo step.

Then move **Signus** into `ReplicatedStorage.EnemyAssets`, the folder
EnemyService clones enemies from. There is no `Signus` entry in
`EnemyConfig.Definitions` yet, so nothing spawns it until its definition and
boss behaviour exist.

## How BlockBound drives it

`EnemyService.prepareModel` anchors every part of an ordinary enemy, exactly as
before. For a model with `ArticulatedRig = true`, it anchors only the
PrimaryPart (or a part called RootPart) and leaves the jointed parts
unanchored, so the Motor6Ds can pose them. CanTouch is still turned off, and
CanCollide still follows `EnemyConfig.Collides`. No Humanoid is involved.
Movement is still `Model:PivotTo`, which moves the root; the joints carry the
rest.

`ServerScriptService.EnemyAnimator` plays the animations on the server, so they
replicate. It only uses `Animator:LoadAnimation`. A boss behaviour uses it like this:

```lua
local EnemyAnimator = require(ServerScriptService:WaitForChild("EnemyAnimator"))

function Signus.start(entry)
	local animator, reason = EnemyAnimator.new(entry.model, EnemyConfig.Animations.Signus)
	if not animator then
		warn("[Signus] no animations: " .. reason)
	end
	entry.animator = animator
	if animator then
		animator:play("Hover")
	end
end

function Signus.finish(entry, reason)
	if entry.animator then
		entry.animator:destroy() -- stops and destroys every track
		entry.animator = nil
	end
end
```

Tracks are **Hover** (looped, Idle), **Lunge** and **Cast** (Action), **Hurt**
(Action2) and **Death** (Action4). Animations only set Motor6D transforms, and
the RootPart is never a joint's Part1, so no animation can move it. Put a bob
or lean on the Core track; where the boss is stays with its AI and `PivotTo`.
EnemyService destroys the model right after `finish`, so a Death animation has
to start before the killing blow if it's going to be seen.

## Making and publishing the animations

1. With **Signus** in Workspace, open **Avatar › Animation Editor** and click
   Signus. Its tracks are Core, Hood, LeftSleeve and RightSleeve.
2. Make one animation per move: Hover, Lunge, Cast, Hurt, Death. Set looping
   and priority as in the list above, matching what EnemyAnimator sets.
3. **Publish to Roblox**, with the creator set to **the group that owns the
   game**. An animation owned by anyone else won't play in it.
4. Paste each ID into `src/ReplicatedStorage/Shared/Enemies/EnemyConfig.lua`,
   replacing the placeholders in `EnemyConfig.Animations.Signus`:

```lua
EnemyConfig.Animations = {
	Signus = {
		Hover = "PUBLISH_SIGNUS_HOVER_AND_PASTE_ID", -- e.g. 1234567890 or "rbxassetid://1234567890"
		...
```

A placeholder is skipped with one warning, so the boss still works without that move.

## Checking it in Studio

These need Studio and haven't been run yet:

- [ ] The rig script prints only `OK` lines, including the two PivotTo / RootPart assembly checks.
- [ ] The Animation Editor lists Core, Hood, LeftSleeve and RightSleeve, and the sleeves and hood turn about their shoulders and neck.
- [ ] In a play test, with enemies spawned, this snippet (run in the Command Bar on the **server**) shows every ordinary enemy fully anchored, and Signus (once it has a definition) anchored only at `RootPart`:

```lua
for _, m in ipairs(workspace.Enemies:GetChildren()) do
	local anchored, total = {}, 0
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			total += 1
			if p.Anchored then table.insert(anchored, p.Name) end
		end
	end
	print(m.Name, m:GetAttribute("ArticulatedRig") and "rig" or "plain", #anchored .. "/" .. total .. " anchored", #anchored < 4 and table.concat(anchored, ", ") or "")
end
```
