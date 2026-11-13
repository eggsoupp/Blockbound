--[[
	TrainingDummy (behaviour)

	Drives a Training Dummy that EnemyService.adopt registered: a placed decor
	piece (or one of the spawn village's) that takes hits like any enemy. It
	lives here because EnemyService loads every `behaviour` from this folder;
	it is not a boss.

	  - Rooted: it stands exactly where it was placed. Anything that shoves
	    enemies about (knockback, pulls) is undone on the next tick.
	  - Hit: a short wobble about its base, away from the blow.
	  - Never dies: a blow that would empty its health fills it again, and it
	    tops itself back up after a few seconds of quiet, so the bar always
	    shows a fresh sparring partner.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local EnemyFeedback = require(ServerScriptService:WaitForChild("EnemyFeedback"))

local TrainingDummy = {}

local WOBBLE_SECONDS = 0.55
local WOBBLE_ANGLE = math.rad(9)
local REFILL_AFTER = 4

-- Close enough to swing at; a row of dummies seen from afar is just clutter.
local PLATE_DISTANCE = 28

function TrainingDummy.start(entry)
	entry.home = entry.model:GetPivot()
	entry.lastStruck = 0
	local plate = entry.model:FindFirstChild("NamePlate", true)
	if plate and plate:IsA("BillboardGui") then
		plate.MaxDistance = PLATE_DISTANCE
	end
end

function TrainingDummy.step(entry, _dt, now)
	local model = entry.model
	local home = entry.home
	local wobbling = entry.wobbleUntil and now < entry.wobbleUntil

	if wobbling then
		local t = 1 - (entry.wobbleUntil - now) / WOBBLE_SECONDS
		local swing = math.sin(t * math.pi * 3) * (1 - t) * WOBBLE_ANGLE
		-- Tipped about the base, away from whoever hit it.
		model:PivotTo(home * CFrame.fromAxisAngle(entry.wobbleAxis, swing))
	elseif entry.wobbleUntil then
		entry.wobbleUntil = nil
		model:PivotTo(home)
	elseif (model:GetPivot().Position - home.Position).Magnitude > 0.05 then
		model:PivotTo(home)
	end

	if entry.health < entry.def.health and now - entry.lastStruck > REFILL_AFTER then
		entry.health = entry.def.health
		EnemyFeedback.refreshNamePlate(entry)
	end
end

function TrainingDummy.damaged(entry, _dealt, dealer)
	local now = os.clock()
	entry.lastStruck = now
	if entry.health <= 0 then
		entry.health = entry.def.health
		EnemyFeedback.refreshNamePlate(entry)
	end

	-- Axis to tip about: horizontal, across the line from the dealer.
	local from = nil
	if typeof(dealer) == "Instance" and dealer:IsA("Player") and dealer.Character then
		local root = dealer.Character:FindFirstChild("HumanoidRootPart")
		from = root and root.Position
	end
	local home = entry.home
	local away = if from then (home.Position - from) * Vector3.new(1, 0, 1) else home.LookVector
	if away.Magnitude < 0.01 then
		away = home.LookVector
	end
	-- In the model's own space, since the tilt is applied after `home`.
	local localAway = home:VectorToObjectSpace(away.Unit)
	entry.wobbleAxis = Vector3.yAxis:Cross(localAway).Unit
	entry.wobbleUntil = now + WOBBLE_SECONDS
end

-- Damage numbers at chest height rather than at its feet.
function TrainingDummy.impactPoint(entry)
	return entry.home.Position + Vector3.new(0, entry.height * 0.7, 0)
end

return TrainingDummy
