-- Only animate cells the server actually removed. These are local visual copies;
-- terrain persistence and item rewards have already been handled by the server.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local Remotes=require(Shared.Net.Remotes)
local ItemModels=require(Shared.UI.ItemModels)
local Scope=require(Shared.Abilities.AbilityScope)
local active=0
local LIFETIME=2.25

Remotes.wait("AbilityTerrain").OnClientEvent:Connect(function(payload)
	if type(payload)~="table" or type(payload.blocks)~="table" or typeof(payload.centre)~="Vector3" then return end
	if active>=3 then return end
	local start=payload.startedAt
	if type(start)~="number" or workspace:GetServerTimeNow()-start>=LIFETIME then return end
	active+=1
	local scope=Scope.new()
	scope:add(function() active-=1 end)
	local folder=scope:add(Instance.new("Folder"))
	folder.Name="AnnihilationMinedBlocks"
	folder.Parent=workspace
	local pieces={}
	for i,entry in ipairs(payload.blocks) do
		if i>64 then break end
		if typeof(entry.position)~="Vector3" then continue end
		local source=ItemModels.find(entry.block)
		if source and not source:IsA("BasePart") then source=source:FindFirstChildWhichIsA("BasePart",true) end
		local part=if source then source:Clone() else Instance.new("Part")
		if not source then part.Color=Color3.fromRGB(116,103,81);part.Material=Enum.Material.Slate end
		for _,child in ipairs(part:GetChildren()) do
			if not child:IsA("Decal") and not child:IsA("SurfaceAppearance") then child:Destroy() end
		end
		part.Name="Fractured_"..tostring(entry.block)
		part.Anchored=true
		part.CanCollide=false
		part.CanTouch=false
		part.CanQuery=false
		part.CastShadow=true
		part.Transparency=0
		part.Size=Vector3.new(3.8,3.8,3.8)
		part.CFrame=CFrame.new(entry.position)
		part.Parent=folder
		local delta=entry.position-payload.centre
		local angle=if math.abs(delta.X)+math.abs(delta.Z)>.01 then math.atan2(delta.Z,delta.X) else i*2.4
		local speed=22+(i%7)*3
		table.insert(pieces,{part=part,position=entry.position,velocity=Vector3.new(math.cos(angle)*speed,65+(i%5)*8,math.sin(angle)*speed),spin=Vector3.new(i%5+1,i%7+2,i%3+1)})
	end
	local function update()
		local age=math.max(0,workspace:GetServerTimeNow()-start)
		if age>=LIFETIME then scope:destroy();return end
		local fade=math.clamp((age-1.25)/(LIFETIME-1.25),0,1)
		for _,piece in ipairs(pieces) do
			local pos=piece.position+piece.velocity*age+Vector3.new(0,-65*age*age,0)
			piece.part.CFrame=CFrame.new(pos)*CFrame.Angles(piece.spin.X*age,piece.spin.Y*age,piece.spin.Z*age)
			piece.part.Size=Vector3.new(3.8,3.8,3.8)*(1-.85*fade)
			piece.part.Transparency=fade
		end
	end
	update()
	if not scope:isDead() then scope:add(RunService.Heartbeat:Connect(update)) end
	task.delay(LIFETIME+.25,function() scope:destroy() end)
end)

return true
