-- Bounded mixer: two impact frames and a decaying kick, without taking aim away.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Plan = require(script.Parent.Parent.CataclysmPlan)
local CameraFX = {}
local casts = {}
local bound = false
local previousCamera, previousBase, previousApplied

local function restore()
	if previousCamera and previousCamera == workspace.CurrentCamera and previousCamera.CFrame == previousApplied then
		previousCamera.CFrame = previousBase
	end
	previousCamera, previousBase, previousApplied = nil, nil, nil
end

function CameraFX.start(centre, startedAt, scope)
	if not RunService:IsClient() then return end
	local entry = { centre = centre, startedAt = startedAt }
	local tint = scope:add(Instance.new("ColorCorrectionEffect"))
	tint.Name = "CataclysmImpactFrames"
	tint.Parent = workspace.CurrentCamera
	entry.tint = tint
	casts[entry] = true
	scope:add(function()
		casts[entry] = nil
		if not next(casts) and bound then
			RunService:UnbindFromRenderStep("CataclysmCameraBefore")
			RunService:UnbindFromRenderStep("CataclysmCameraAfter")
			restore()
			bound = false
		end
	end)
	if bound then return end
	bound = true
	RunService:BindToRenderStep("CataclysmCameraBefore", Enum.RenderPriority.Camera.Value - 2, restore)
	RunService:BindToRenderStep("CataclysmCameraAfter", Enum.RenderPriority.Last.Value + 11, function()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local now = workspace:GetServerTimeNow()
		local shake, punch = 0, 0
		local player = Players.LocalPlayer
		local reduced = player and player:GetAttribute("ReducedMotion") == true
		for cast in pairs(casts) do
			local age = now - cast.startedAt - Plan.hitAt()
			local near = math.clamp(1 - (camera.CFrame.Position - cast.centre).Magnitude / 240, 0, 1)
			local hit = if age >= 0 then math.exp(-age * 3.8) else 0
			local approach = if age > -0.6 and age < 0 then (1 + age / 0.6) * 0.12 else 0
			shake += near * (hit * 2.2 + approach)
			punch += near * hit
			local brightness, contrast, saturation = 0, 0, 0
			if not reduced and near > 0.05 then
				-- A warm-white contact frame, then a dark desaturated silhouette.
				if age >= 0 and age < 0.045 then brightness, contrast, saturation = 0.52, 0.65, -0.8
				elseif age >= 0.065 and age < 0.115 then brightness, contrast, saturation = -0.24, 1, -1
				elseif age >= 0.115 then brightness, contrast = hit * 0.06, hit * 0.12 end
			end
			cast.tint.Brightness = brightness * near
			cast.tint.Contrast = contrast * near
			cast.tint.Saturation = saturation * near
		end
		shake = if reduced then 0 else math.min(shake, 2.8)
		punch = if reduced then 0 else math.min(punch, 1)
		local t = now % 256
		local x = math.noise(t * 19, 3.1) + math.sin(t * 47) * 0.35
		local y = math.noise(4.7, t * 23) + math.sin(t * 59) * 0.35
		local z = math.noise(t * 13, 9.7)
		local offset = CFrame.new(x * shake, y * shake, z * shake * 0.3)
			* CFrame.Angles(y * shake * 0.025 + punch * 0.025, x * shake * 0.02, z * shake * 0.035)
		previousCamera, previousBase = camera, camera.CFrame
		previousApplied = camera.CFrame * offset
		camera.CFrame = previousApplied
	end)
end

return CameraFX
