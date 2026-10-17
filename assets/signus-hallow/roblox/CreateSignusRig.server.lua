--[[
	CreateSignusRig

	Turns the imported Signus GLB into a Motor6D rig that BlockBound's
	EnemyService and Studio's Animation Editor can both drive.

	HOW TO RUN
	  1. Import signus_hallowed_eclipse.glb (see README.md in this folder).
	  2. Select the imported Model in the Explorer, and nothing else.
	  3. Paste this whole file into View > Command Bar and press Enter.
	It checks everything before it changes anything, and running it again
	rebuilds the joints in place rather than adding a second set.

	WHAT IT MAKES

	  Signus                  Model, PrimaryPart = RootPart, ArticulatedRig = true
	    RootPart              invisible, anchored, at the scene origin (Core pivot)
	    AnimationController
	      Animator
	    Core                  CoreJoint         RootPart -> Core
	    Hood                  HoodJoint         Core -> Hood
	    LeftSleeve            LeftSleeveJoint   Core -> LeftSleeve
	    RightSleeve           RightSleeveJoint  Core -> RightSleeve
	    CoreLower             CoreLowerWeld     Core -> CoreLower (rigid, no track)

	CoreLower is the bottom of the Core. Roblox will not import a mesh of 20,000
	triangles or more and the Core's exact surface needs about 29,000, so the
	export stores it as two meshes. It is welded, not jointed, so it moves with
	the Core and the Animation Editor still shows exactly four tracks.

	WHERE THE JOINTS HINGE

	Roblox centres every MeshPart on its own bounding box, whatever origin the
	file gave it, and nothing documents the importer keeping the original
	origin as a PivotOffset. So the hinges come from the export itself: the
	anatomical pivots below, placed relative to RootPart. Each joint's C0 and
	C1 are both worked out from the parts' current CFrames, so the artwork does
	not move. C1 is not the identity: it is where the pivot sits inside Part1.

	Set HINGE_AT_PART_CENTRE to true for C1 = CFrame.identity instead. Every
	part then turns about its bounding-box centre - the middle of a sleeve
	rather than its shoulder.
]]

local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local HINGE_AT_PART_CENTRE = false

local MODEL_NAME = "Signus"
local ROOT_NAME = "RootPart"
local ROOT_SIZE = Vector3.new(1, 1, 1)

--[[
	From export_report.json: each mesh's bounding-box centre, size and pivot,
	in studs, Roblox axes, relative to the Core pivot (the scene origin).
	The Core and CoreLower share the Core's pivot.
]]
local EXPORT = {
	Core = {
		center = Vector3.new(0, 2.75, -0.125),
		size = Vector3.new(12.5, 8.5, 6),
		pivot = Vector3.new(0, 0, 0),
	},
	CoreLower = {
		center = Vector3.new(0, -5.3125, 0.1875),
		size = Vector3.new(8.5, 7.625, 5.875),
		pivot = Vector3.new(0, 0, 0),
	},
	Hood = {
		center = Vector3.new(0, 5.875, -0.4375),
		size = Vector3.new(5.25, 6.5, 4.375),
		pivot = Vector3.new(0, 3.5, -0.375),
	},
	LeftSleeve = {
		center = Vector3.new(-4, -0.75, -0.5625),
		size = Vector3.new(3.5, 6, 3.375),
		pivot = Vector3.new(-3.375, 1.75, -0.25),
	},
	RightSleeve = {
		center = Vector3.new(4, -0.75, -0.5625),
		size = Vector3.new(3.5, 6, 3.375),
		pivot = Vector3.new(3.375, 1.75, -0.25),
	},
}

local VISIBLE = { "Core", "CoreLower", "Hood", "LeftSleeve", "RightSleeve" }

local MOTORS = {
	{ name = "CoreJoint", part0 = ROOT_NAME, part1 = "Core" },
	{ name = "HoodJoint", part0 = "Core", part1 = "Hood" },
	{ name = "LeftSleeveJoint", part0 = "Core", part1 = "LeftSleeve" },
	{ name = "RightSleeveJoint", part0 = "Core", part1 = "RightSleeve" },
}

local WELDS = {
	{ name = "CoreLowerWeld", part0 = "Core", part1 = "CoreLower" },
}

-- How far an imported part may be from where the export put it, in studs at
-- import scale. Generous next to float noise, tiny next to any real mistake
-- such as a 180 degree turn or a mirrored axis.
local POSITION_TOLERANCE = 0.05
local SIZE_TOLERANCE = 0.03

local failures = 0

local function say(text)
	print("[SignusRig] " .. text)
end

local function check(ok, text)
	if ok then
		print("[SignusRig]   OK    " .. text)
	else
		failures += 1
		warn("[SignusRig]   FAIL  " .. text)
	end
	return ok
end

local function vec(v)
	return string.format("(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
end

local function sameRotation(a, b)
	return a.LookVector:Dot(b.LookVector) > 0.9999 and a.UpVector:Dot(b.UpVector) > 0.9999
end

local function run()
	-- -----------------------------------------------------------------------
	-- Read-only checks. Nothing is changed unless every one of these passes.
	-- -----------------------------------------------------------------------
	local selected = Selection:Get()
	if #selected ~= 1 or not selected[1]:IsA("Model") then
		warn("[SignusRig] Select exactly one Model (the imported Signus) and run this again.")
		return
	end
	local model = selected[1]
	say(string.format("Checking %s", model:GetFullName()))

	local byName = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			byName[descendant.Name] = byName[descendant.Name] or {}
			table.insert(byName[descendant.Name], descendant)
		end
	end

	local parts = {}
	for _, name in ipairs(VISIBLE) do
		local matches = byName[name] or {}
		if check(#matches == 1, string.format("one part named %s (found %d)", name, #matches)) then
			local part = matches[1]
			if check(part:IsA("MeshPart"), string.format("%s is a MeshPart (it is a %s)", name, part.ClassName)) then
				parts[name] = part
			end
		end
	end
	if failures > 0 then
		warn("[SignusRig] Stopped before changing anything. Import the GLB again and select its Model.")
		return
	end

	-- The model may have been scaled since import; anything uniform is fine.
	local scale = parts.Core.Size.X / EXPORT.Core.size.X
	say(string.format("Scale %.4f of the exported size", scale))

	--[[
		The scene origin, worked out from the Core, whose placement in the file
		is known. Studio's importer can bake a half turn into the meshes while
		leaving every part's rotation at zero (glTF's front is +Z, Roblox's is
		-Z). So both ways round are tried, and RootPart is turned to whichever
		fits: its -Z is then always the side the face is on.
	]]
	local core = parts.Core
	local function rootFor(turn)
		return CFrame.new(core.Position) * turn * CFrame.new(-EXPORT.Core.center * scale)
	end
	local function fits(rootCFrame)
		for _, name in ipairs(VISIBLE) do
			local offset = rootCFrame:PointToObjectSpace(parts[name].Position)
			if (offset - EXPORT[name].center * scale).Magnitude > POSITION_TOLERANCE * scale then
				return false
			end
		end
		return true
	end
	local coreTurn = core.CFrame.Rotation
	local rootCFrame = rootFor(coreTurn)
	if not fits(rootCFrame) then
		local halfTurn = rootFor(coreTurn * CFrame.Angles(0, math.pi, 0))
		if fits(halfTurn) then
			rootCFrame = halfTurn
			say("The importer turned the model 180 degrees; RootPart is turned to match, so it faces the hood's front.")
		end
	end

	for _, name in ipairs(VISIBLE) do
		local part = parts[name]
		local expected = EXPORT[name]
		local sizeError = (part.Size - expected.size * scale).Magnitude
		check(sizeError <= SIZE_TOLERANCE * scale,
			string.format("%s size %s matches the export", name, vec(part.Size)))
		local offset = rootCFrame:PointToObjectSpace(part.Position)
		check((offset - expected.center * scale).Magnitude <= POSITION_TOLERANCE * scale,
			string.format("%s sits at %s from the origin (export %s)", name, vec(offset), vec(expected.center * scale)))
		check(sameRotation(part.CFrame, core.CFrame), string.format("%s is turned the same way as Core", name))
	end
	if failures > 0 then
		warn("[SignusRig] Stopped before changing anything. The parts are not laid out the way the "
			.. "export placed them: re-import with World Forward = Front, World Up = Top and Scale "
			.. "Unit = Stud (README.md), and do not move parts individually before rigging.")
		return
	end

	local existingRoot = model:FindFirstChild(ROOT_NAME)
	if existingRoot and not existingRoot:IsA("BasePart") then
		check(false, string.format("%s is a %s; rename or remove it", ROOT_NAME, existingRoot.ClassName))
		return
	end

	-- -----------------------------------------------------------------------
	-- Build. Recorded as one undo step where Studio allows it.
	-- -----------------------------------------------------------------------
	local recording = nil
	local began, id = pcall(function()
		return ChangeHistoryService:TryBeginRecording("Create Signus rig")
	end)
	if began then
		recording = id
	end

	local rest = {}
	local built, buildError = pcall(function()
		-- Old joints of ours go first, so a second run rebuilds rather than doubles.
		local ours = {}
		for _, spec in ipairs(MOTORS) do
			ours[spec.name] = true
		end
		for _, spec in ipairs(WELDS) do
			ours[spec.name] = true
		end
		for _, descendant in ipairs(model:GetDescendants()) do
			if (descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint")) and ours[descendant.Name] then
				descendant:Destroy()
			end
		end

		-- Held still while the joints are made, and exactly where they were.
		for _, name in ipairs(VISIBLE) do
			local part = parts[name]
			rest[name] = part.CFrame
			part.Anchored = true
		end

		model.Name = MODEL_NAME

		local root = existingRoot or Instance.new("Part")
		root.Name = ROOT_NAME
		root.Size = ROOT_SIZE
		root.Transparency = 1
		root.CanCollide = false
		root.CanTouch = false
		root.CanQuery = false
		root.CastShadow = false
		root.Anchored = true
		-- The highest there is. An anchored part is the root anyway; this keeps
		-- it so if somebody unanchors it to test physics.
		root.RootPriority = 127
		root.CFrame = rootCFrame
		root.PivotOffset = CFrame.identity
		root.Parent = model
		model.PrimaryPart = root
		parts[ROOT_NAME] = root

		local controller = model:FindFirstChildOfClass("AnimationController")
		if not controller then
			controller = Instance.new("AnimationController")
			controller.Name = "AnimationController"
			controller.Parent = model
		end
		if not controller:FindFirstChildOfClass("Animator") then
			local animator = Instance.new("Animator")
			animator.Parent = controller
		end

		local function hinge(name)
			if HINGE_AT_PART_CENTRE then
				return parts[name].CFrame
			end
			return rootCFrame * CFrame.new(EXPORT[name].pivot * scale)
		end

		for _, spec in ipairs(MOTORS) do
			local part0, part1 = parts[spec.part0], parts[spec.part1]
			local at = hinge(spec.part1)
			local motor = Instance.new("Motor6D")
			motor.Name = spec.name
			-- Part0.CFrame * C0 == Part1.CFrame * C1 == the hinge, so nothing moves.
			motor.C0 = part0.CFrame:ToObjectSpace(at)
			motor.C1 = part1.CFrame:ToObjectSpace(at)
			motor.Part0 = part0
			motor.Part1 = part1
			motor.Parent = part1
		end

		for _, spec in ipairs(WELDS) do
			local part0, part1 = parts[spec.part0], parts[spec.part1]
			local weld = Instance.new("Weld")
			weld.Name = spec.name
			weld.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
			weld.C1 = CFrame.identity
			weld.Part0 = part0
			weld.Part1 = part1
			weld.Parent = part1
		end

		for _, name in ipairs(VISIBLE) do
			local part = parts[name]
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = true
			part.Massless = true
			part.Anchored = false
		end

		model:SetAttribute("ArticulatedRig", true)
	end)

	if not built then
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
		end
		warn("[SignusRig] Building the rig failed and was undone: " .. tostring(buildError))
		return
	end
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	-- -----------------------------------------------------------------------
	-- What was built.
	-- -----------------------------------------------------------------------
	say("Built:")
	local root = parts[ROOT_NAME]
	check(model.Name == MODEL_NAME, "Model is named " .. MODEL_NAME)
	check(model.PrimaryPart == root, "PrimaryPart is " .. ROOT_NAME)
	check(model:GetAttribute("ArticulatedRig") == true, "ArticulatedRig attribute is true")
	check(root.Anchored and root.Transparency == 1 and not root.CanCollide and not root.CanTouch
		and not root.CanQuery and root.RootPriority == 127,
		string.format("%s anchored, invisible, no collision/touch/query, RootPriority 127", ROOT_NAME))

	local controllers, animators = 0, 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("AnimationController") then
			controllers += 1
		elseif descendant:IsA("Animator") then
			animators += 1
		end
	end
	check(controllers == 1 and animators == 1,
		string.format("one AnimationController and one Animator (found %d and %d)", controllers, animators))

	local motorCount = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			motorCount += 1
		end
	end
	check(motorCount == #MOTORS, string.format("%d Motor6Ds, no duplicates (found %d)", #MOTORS, motorCount))

	for _, spec in ipairs(MOTORS) do
		local motor = parts[spec.part1]:FindFirstChild(spec.name)
		local hingeAt = motor and (motor.Part0.CFrame * motor.C0).Position
		check(motor ~= nil and motor.Part0 == parts[spec.part0] and motor.Part1 == parts[spec.part1],
			string.format("%s: %s -> %s, hinge at %s from the origin", spec.name, spec.part0, spec.part1,
				hingeAt and vec(rootCFrame:PointToObjectSpace(hingeAt)) or "?"))
	end

	for _, name in ipairs(VISIBLE) do
		local part = parts[name]
		local moved = (part.Position - rest[name].Position).Magnitude
		check(not part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery
			and part.CastShadow and part.Massless and moved < 1e-3,
			string.format("%s unanchored, massless, no collision/touch/query, casts shadow, did not move", name))
	end

	if model:IsDescendantOf(workspace) then
		for _, name in ipairs(VISIBLE) do
			check(parts[name].AssemblyRootPart == root,
				string.format("%s is in %s's assembly", name, ROOT_NAME))
		end

		-- Moved the way EnemyService moves it, then by the root alone, then back.
		local function offsets()
			local out = {}
			for _, name in ipairs(VISIBLE) do
				out[name] = root.CFrame:ToObjectSpace(parts[name].CFrame)
			end
			return out
		end
		local function together(before)
			local after = offsets()
			for _, name in ipairs(VISIBLE) do
				local delta = before[name]:ToObjectSpace(after[name])
				if delta.Position.Magnitude > 1e-3 or not sameRotation(delta, CFrame.identity) then
					return false
				end
			end
			return true
		end
		local before = offsets()
		model:PivotTo(rootCFrame * CFrame.new(0, 20, 0) * CFrame.Angles(0, math.rad(90), 0))
		check(together(before), "all parts stay assembled through Model:PivotTo")
		root.CFrame = root.CFrame * CFrame.new(6, 0, 0)
		check(together(before), "all parts follow when only RootPart moves")

		-- Back by the root; anything the joints did not bring along goes back by hand.
		root.CFrame = rootCFrame
		for _, name in ipairs(VISIBLE) do
			if (parts[name].Position - rest[name].Position).Magnitude > 1e-3 then
				parts[name].CFrame = rest[name]
			end
		end
		local home = true
		for _, name in ipairs(VISIBLE) do
			home = home and (parts[name].Position - rest[name].Position).Magnitude < 1e-3
		end
		check(home, "put back exactly where it was")
	else
		say("Not in Workspace, so the assembly and PivotTo checks were skipped. Parent it to Workspace and run again to see them.")
	end

	if failures == 0 then
		say("Signus rig ready. Animation Editor tracks: Core, Hood, LeftSleeve, RightSleeve.")
		say("Next: Avatar > Animation Editor with Signus selected, or move it to ReplicatedStorage.EnemyAssets.")
	else
		warn(string.format("[SignusRig] Rig built, but %d check(s) failed - see above.", failures))
	end
end

run()
