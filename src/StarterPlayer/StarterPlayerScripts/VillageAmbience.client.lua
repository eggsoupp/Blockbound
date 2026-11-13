--[[
	VillageAmbience

	The spawn village's motion, run on each client (nothing is replicated per
	frame): the Starfall Merchant's idle loop and the shrine's turning
	star and rings. Skipped while the camera is far from the village.

	The merchant is a Motor6D rig (assets/voxel-village, BuildVillage): every
	joint's C0/C1 is axis-aligned at its pivot, so a Transform turns that part
	about its joint in the rig's own axes (+X his right, +Y up, front -Z).
	Joints: Root (hips), Torso, Head, RightArm -> Staff -> Lantern,
	LeftArm -> Orb, Runes.

	The idle, one loop of a few seconds layered from slow sines so it never
	visibly repeats: he breathes and sways, the hood drifts as if he were
	looking round the plaza, the lantern swings on its crook, the orb bobs
	and turns over his palm, and the three rune stones circle him.
]]

local RunService = game:GetService("RunService")

local hub = workspace:WaitForChild("StarfallHub", 120)
if not hub then
	return
end

local FAR = 140

local function sine(t, period, phase)
	return math.sin((t / period + (phase or 0)) * math.pi * 2)
end

-- Merchant -------------------------------------------------------------------

local merchant = hub:WaitForChild("StarfallMerchant", 30)
local joints = {}
local merchantRoot
if merchant then
	merchantRoot = merchant:WaitForChild("HumanoidRootPart", 30)
	for _, name in { "Root", "Torso", "Head", "RightArm", "Staff", "Lantern", "LeftArm", "Orb", "Runes" } do
		local found = nil
		for _, d in merchant:GetDescendants() do
			if d:IsA("Motor6D") and d.Name == name then
				found = d
				break
			end
		end
		joints[name] = found
	end
end

local function pose(name, cf)
	local joint = joints[name]
	if joint then
		joint.Transform = cf
	end
end

local function animateMerchant(t)
	local breath = sine(t, 4.2)
	local sway = sine(t, 7.5, 0.2)
	pose("Root", CFrame.Angles(0, 0, 0.012 * sway))
	pose("Torso", CFrame.new(0, 0.035 * breath, 0) * CFrame.Angles(-0.02 * breath, 0.03 * sine(t, 9), 0.01 * sway))
	-- Looking round: a slow sweep with a pause-like ease at each end.
	local look = sine(t, 11, 0.1)
	look = look * math.abs(look) ^ 0.4
	pose("Head", CFrame.Angles(0.05 * sine(t, 6.3) - 0.03, 0.38 * look, 0.04 * sine(t, 8.1)))
	pose("RightArm", CFrame.Angles(0.025 * breath, 0, 0.015 * sway))
	pose("Staff", CFrame.identity)
	pose("Lantern", CFrame.Angles(0.11 * sine(t, 2.6), 0, 0.08 * sine(t, 3.4, 0.3)))
	pose("LeftArm", CFrame.Angles(0.06 * sine(t, 5.2, 0.4), 0, -0.02 * sway))
	pose("Orb", CFrame.new(0, 0.18 * sine(t, 2.4), 0) * CFrame.Angles(0.2 * sine(t, 5), t * 1.4, 0))
	pose("Runes", CFrame.new(0, 0.12 * sine(t, 3.1), 0) * CFrame.Angles(0, t * 0.55, 0.05 * sine(t, 6)))
end

-- Shrine star and rings ----------------------------------------------------------
-- Anchored parts moved locally: each part and its <Name>Glow companion move
-- together (lights ride along in their attachments). The star rocks to
-- either side of facing the plaza, so its five points stay readable; the
-- rings turn steadily round it.

local shrine = hub:WaitForChild("StarfallShrine", 30)

local function mover(name)
	local part = shrine and shrine:FindFirstChild(name)
	if not part then
		return nil
	end
	local glow = shrine:FindFirstChild(name .. "Glow")
	return {
		part = part,
		base = part.CFrame,
		glow = glow,
		glowOffset = glow and part.CFrame:ToObjectSpace(glow.CFrame),
	}
end

local star = mover("Star")
local rings = mover("Rings")
local shards = mover("Shards")

local function place(m, cf)
	m.part.CFrame = cf
	if m.glow then
		m.glow.CFrame = cf * m.glowOffset
	end
end

local function animateShrine(t)
	if star then
		place(star, star.base * CFrame.new(0, 0.3 * sine(t, 4), 0) * CFrame.Angles(0, 0.6 * sine(t, 12), 0.04 * sine(t, 7)))
	end
	if rings then
		-- About the star's centre, which is where the rings' pivot sits.
		local centre = star and star.base.Position or rings.base.Position
		local offset = CFrame.new(centre):ToObjectSpace(rings.base)
		place(rings, CFrame.new(centre) * CFrame.Angles(0.12 * sine(t, 15), -t * 0.35, 0) * offset)
	end
	if shards then
		-- The four crystals circle the bowl slowly, rising and falling together.
		place(shards, shards.base * CFrame.new(0, 0.25 * sine(t, 5), 0) * CFrame.Angles(0, t * 0.3, 0))
	end
end

RunService.PreSimulation:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera or not hub.Parent then
		return
	end
	local centre = hub:GetPivot().Position
	if (camera.CFrame.Position - centre).Magnitude > FAR then
		return
	end
	local t = workspace:GetServerTimeNow()
	if merchantRoot and merchantRoot.Parent then
		animateMerchant(t)
	end
	animateShrine(t)
end)
