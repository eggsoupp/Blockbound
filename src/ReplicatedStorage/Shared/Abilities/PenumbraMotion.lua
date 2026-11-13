--[[
	PenumbraMotion: the caster's own client carrying their body through
	Penumbra (PenumbraPlan.rootAt) - down into the ground, along under it and
	up out of it where they aimed; flying, held while the first burst takes
	them and moved to the second.

	The caster's client does this because it owns the character's physics:
	what it sets here is what the server and everyone else see. The server
	puts them at the landing itself if they are not there once the move is
	over (Abilities/Penumbra), so a client that never ran this still arrives.

	While it runs: the body passes through everything (Plan.GhostGroup), the
	Humanoid is PlatformStand so it does not try to stand or fall, and the
	camera follows an anchor that glides above ground from where they went
	down to where they come up, instead of diving underground with them.
	Everything is put back as it was when the move ends or the scope does.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Plan = require(script.Parent.PenumbraPlan)

local Motion = {}

local function ease(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- Where the camera looks while the body is under: above where it went down,
-- gliding to above where it comes up.
local function cameraAt(t, from, to)
	local u = ease((t - Plan.goneAt()) / (Plan.handsAt() - Plan.goneAt()))
	return from:Lerp(to, u)
end

function Motion.run(scope, payload, elapsed)
	local player = Players.LocalPlayer
	if payload.caster ~= player then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) then return end

	local from, to, air = payload.origin.Position, payload.destination, payload.air == true
	local heading = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local face = if heading.Magnitude > 0.1 then heading.Unit else payload.origin.LookVector

	local collide, platform, subject, anchor = {}, nil, nil, nil
	local active = false

	local function begin()
		active = true
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") then
				collide[d] = d.CollisionGroup
				d.CollisionGroup = Plan.GhostGroup
			end
		end
		platform = humanoid.PlatformStand
		humanoid.PlatformStand = true
		local camera = workspace.CurrentCamera
		if camera and camera.CameraSubject == humanoid then
			anchor = Instance.new("Part")
			anchor.Name = "PenumbraCamera"
			anchor.Size, anchor.Transparency = Vector3.one * 0.2, 1
			anchor.Anchored, anchor.CanCollide, anchor.CanTouch, anchor.CanQuery = true, false, false, false
			anchor.CFrame = CFrame.new(from)
			anchor.Parent = workspace
			subject = humanoid
			camera.CameraSubject = anchor
		end
	end

	local function finish()
		if not active then return end
		active = false
		for part, was in pairs(collide) do
			if part.Parent then part.CollisionGroup = was end
		end
		table.clear(collide)
		if humanoid.Parent then humanoid.PlatformStand = platform end
		local camera = workspace.CurrentCamera
		if subject and camera and camera.CameraSubject == anchor then camera.CameraSubject = subject end
		if anchor then anchor:Destroy() end
		anchor, subject = nil, nil
		if root.Parent then root.AssemblyLinearVelocity = Vector3.zero end
	end
	scope:add(finish)

	local connection
	connection = scope:add(RunService.PreSimulation:Connect(function()
		local t = elapsed()
		local at = Plan.rootAt(t, from, to, air)
		if not at or not root.Parent then
			if t >= Plan.departAt() then
				finish()
				connection:Disconnect()
			end
			return
		end
		if not active then begin() end
		root.CFrame = CFrame.lookAt(at, at + face)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if anchor then
			-- Head height, where the camera looks at a Humanoid.
			local look = if t < Plan.goneAt() then from elseif t < Plan.handsAt() then cameraAt(t, from, to) else to
			anchor.CFrame = CFrame.new(look + Vector3.new(0, 1.5, 0))
		end
	end))
end

return Motion
