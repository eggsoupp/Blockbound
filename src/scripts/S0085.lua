-- One mixer for overlapping casts. Undo our previous transform before the camera
-- controller runs, then layer the current impulse after it. Never lock player aim.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Plan = require(script.Parent.Parent.AnnihilationPlan)
local CameraFX = {}
local casts = {}
local bound = false
local previousCamera, previousBase, previousApplied

local function restore()
	if previousCamera and previousCamera == workspace.CurrentCamera and previousCamera.CFrame == previousApplied then
		previousCamera.CFrame = previousBase
	end
	previousCamera, previousBase, previousApplied = nil,nil,nil
end

function CameraFX.start(origin, startedAt, scope, caster)
	local cast = {position=origin.Position, startedAt=startedAt, isCaster=caster~=nil and caster==Players.LocalPlayer}
	casts[cast] = true
	local camera = workspace.CurrentCamera
	local tint = scope:add(Instance.new("ColorCorrectionEffect"))
	tint.Name = "AnnihilationImpactGrade"
	tint.Parent = camera
	local blur = scope:add(Instance.new("BlurEffect"))
	blur.Name = "AnnihilationImpactBlur"
	blur.Size = 0
	blur.Parent = camera
	cast.tint, cast.blur = tint, blur
	scope:add(function()
		casts[cast] = nil
		if next(casts) == nil and bound then
			RunService:UnbindFromRenderStep("AnnihilationCameraBefore")
			RunService:UnbindFromRenderStep("AnnihilationCameraAfter")
			restore()
			bound = false
		end
	end)
	if bound then return end
	bound = true
	RunService:BindToRenderStep("AnnihilationCameraBefore",Enum.RenderPriority.Camera.Value-1,restore)
	RunService:BindToRenderStep("AnnihilationCameraAfter",Enum.RenderPriority.Last.Value+10,function()
		local current = workspace.CurrentCamera
		if not current then return end
		local now = workspace:GetServerTimeNow()
		local shake, punch = 0,0
		for entry in pairs(casts) do
			local elapsed = now-entry.startedAt
			local age = elapsed-Plan.hitAt()
			local distance = (current.CFrame.Position-entry.position).Magnitude
			local nearby = math.clamp(1-distance/400,0,1)
			if entry.isCaster then nearby=1 end
			local power = Plan.beamSample(elapsed)
			local impact = if age >= 0 then math.exp(-age*9) else 0
			local tailAge = elapsed-Plan.fadeAt()
			local release = if tailAge >= 0 then math.exp(-tailAge*12)*.45 else 0
			shake += nearby*(power*1.9+impact*2.8+release*1.2+Plan.impactPulse(elapsed)*.9)
			punch += nearby*impact
			entry.tint.Brightness = nearby*impact*.22
			entry.tint.Contrast = nearby*power*.14
			entry.tint.Saturation = nearby*power*.1
			entry.blur.Size = nearby*(impact*5+release*2)
		end
		shake = math.min(shake,4.5)
		punch = math.min(punch,1)
		-- Epoch-sized inputs lose their fractions inside noise and can become all zero.
		local t=now%256
		-- Broad oscillations remain readable across frames; noise adds the rough edge.
		local x = math.noise(t*17,11.3,0)*.8 + math.sin(t*43)*.65
		local y = math.noise(0,t*19,7.1)*.8 + math.sin(t*53+1.1)*.6
		local z = math.noise(4.7,0,t*13)*.8 + math.sin(t*31)*.3
		local offset = CFrame.new(x*shake,y*shake,z*shake*.3)
			* CFrame.Angles(y*shake*.045+punch*.035,x*shake*.038,z*shake*.055)
		previousCamera, previousBase = current,current.CFrame
		previousApplied = current.CFrame*offset
		current.CFrame = previousApplied
	end)
end

return CameraFX
