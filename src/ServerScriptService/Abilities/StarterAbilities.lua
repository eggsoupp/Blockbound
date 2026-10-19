local RS=game:GetService("ReplicatedStorage")
local SSS=game:GetService("ServerScriptService")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Http=game:GetService("HttpService")
local Plan=require(RS.Shared.Abilities.StarterPlan)
local Enemies=require(SSS.EnemyService)
local Combat=require(SSS.CombatService)
local Terrain=require(SSS.TerrainManager)
local Items=require(RS.Shared.UI.ItemModels)
local Ability={}

local function rayParams(character, ignoreCharacters)
	local p=RaycastParams.new()
	p.FilterType=Enum.RaycastFilterType.Exclude
	local exclude={character}
	if ignoreCharacters then for _,player in ipairs(Players:GetPlayers()) do if player.Character then table.insert(exclude,player.Character) end end end
	p.FilterDescendantsInstances=exclude
	p.RespectCanCollide=true
	return p
end

local function clearBox(cf,size,character)
	local p=OverlapParams.new()
	p.FilterType=Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances={character}
	p.RespectCanCollide=true
	return #workspace:GetPartBoundsInBox(cf,size,p)==0
end

local function echoDestination(context)
	local origin=context.origin.Position
	local forward=Plan.flat(context.origin.LookVector)
	local params=rayParams(context.character,false)
	local distance=Plan.EchoStep.range
	local hit=workspace:Blockcast(CFrame.new(origin),Vector3.new(3.2,4.8,3.2),forward*distance,params)
	if hit then distance=math.max(0,hit.Distance-.7) end
	-- Search backwards for supported, unoccupied ground; never pass through a wall.
	for step=distance,Plan.EchoStep.minimum,-1 do
		local candidate=origin+forward*step
		local ground=workspace:Raycast(candidate+Vector3.new(0,3,0),Vector3.new(0,-12,0),params)
		if ground and ground.Normal.Y>.65 then
			local root=context.character:FindFirstChild("HumanoidRootPart")
			local humanoid=context.character:FindFirstChildOfClass("Humanoid")
			local standing=if root and humanoid then humanoid.HipHeight+root.Size.Y*.5 else 3
			local destination=Vector3.new(candidate.X,ground.Position.Y+standing+.15,candidate.Z)
			if math.abs(destination.Y-origin.Y)<=6 and clearBox(CFrame.new(destination),Vector3.new(3.2,4.8,3.2),context.character) then
				-- Check the sloped root path as well, including overhead clearance.
				local path=workspace:Blockcast(CFrame.new(origin),Vector3.new(3.2,4.8,3.2),destination-origin,params)
				if not path then return destination,forward end
			end
		end
	end
end

function Ability.validate(context)
	local kind=context.abilityName
	if kind=="EchoStep" then
		local destination,forward=echoDestination(context)
		if not destination then return false,"Echo Step needs a clear path and a safe landing." end
		return true,nil,{destination=destination,direction=forward}
	elseif kind=="BlockWall" then
		local records,reason=Terrain:PlanBlockWall(context.origin.Position,context.origin.LookVector)
		if not records then return false,reason end
		for _,r in ipairs(records) do
			if not clearBox(CFrame.new(r.target.position),Vector3.one*3.8,context.character) then
				return false,"Something is occupying the wall's position."
			end
		end
		return true,nil,{records=records}
	end
	return true,nil,{}
end

local function visible(from,to,context)
	return workspace:Raycast(from,to-from,rayParams(context.character,true))==nil
end

local function damage(context,model,player,amount)
	if player then Combat.applyDamage(player,amount,context.abilityName)
	else context.damage(model,amount) end
end

local function projectile(context)
	local tuning=context.tuning
	local origin=context.origin.Position+Vector3.new(0,.8,0)
	local delta=context.target-origin
	local direction=if delta.Magnitude>.1 then delta.Unit else context.origin.LookVector
	local id=Http:GenerateGUID(false)
	local started=workspace:GetServerTimeNow()
	context.broadcast({id=id,origin=CFrame.lookAt(origin,origin+direction),direction=direction,startedAt=started})
	local position,travelled,finished=origin,0,false
	local params=rayParams(context.character,true)
	local function impact(point,model,player,normal)
		if finished then return end
		finished=true
		if model or player then damage(context,model,player,tuning.damage) end
		if tuning.splash>0 then
			Enemies.forEachNear(point,tuning.splash,function(other,at)
				if other~=model and visible(point,at,context) then context.damage(other,tuning.damage*.5) end
			end)
			for _,other in ipairs(Players:GetPlayers()) do
				local root=other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				if other~=context.player and other~=player and root and (root.Position-point).Magnitude<=tuning.splash and visible(point,root.Position,context) then
					Combat.applyDamage(other,tuning.damage*.5,context.abilityName)
				end
			end
		end
		context.impact({id=id,position=point,normal=normal or -direction,startedAt=workspace:GetServerTimeNow()})
	end
	context.scope:add(function()
		if not finished then finished=true;context.impact({id=id,position=position,cancelled=true,startedAt=workspace:GetServerTimeNow()}) end
	end)
	context.scope:add(RunService.Heartbeat:Connect(function()
		if finished then return end
		local elapsed=workspace:GetServerTimeNow()-started-tuning.windup
		if elapsed<0 then return end
		local expected=math.min(tuning.range,elapsed*tuning.speed)
		local distance=expected-travelled
		if distance<=0 then return end
		local step=direction*distance
		local world=workspace:Spherecast(position,tuning.radius,step,params)
		local best=if world then world.Distance/distance else 1
		local victim,playerVictim
		local function test(at,hitRadius,model,player)
			local t=math.clamp((at-position):Dot(step)/step:Dot(step),0,1)
			if t<=best and (position+step*t-at).Magnitude<=tuning.radius+hitRadius then best=t;victim=model;playerVictim=player end
		end
		Enemies.forEachNear(position+step*.5,distance*.5+10,function(model,at)
			test(at,math.clamp(model:GetExtentsSize().Magnitude*.25,1.5,6),model,nil)
		end)
		for _,player in ipairs(Players:GetPlayers()) do
			local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if player~=context.player and root and humanoid and humanoid.Health>0 then test(root.Position,2,nil,player) end
		end
		if victim or playerVictim then impact(position+step*best,victim,playerVictim)
		elseif world then impact(world.Position,Enemies.modelFor(world.Instance),nil,world.Normal)
		else position+=step;travelled=expected;if travelled>=tuning.range then impact(position) end end
	end))
end

local function wind(context)
	local direction=Plan.flat(context.origin.LookVector)
	context.broadcast({origin=context.origin,direction=direction,startedAt=workspace:GetServerTimeNow()})
	context.scope:delay(Plan.WindBurst.windup,function()
		local origin=context.origin.Position
		local function inside(at)
			local delta=at-origin
			return delta.Magnitude<=Plan.WindBurst.range and math.abs(delta.Y)<=7
				and (delta.Magnitude<1 or Plan.flat(delta):Dot(direction)>=math.cos(math.rad(Plan.WindBurst.halfAngle)))
				and visible(origin+Vector3.new(0,1,0),at,context)
		end
		Enemies.forEachNear(origin,Plan.WindBurst.range,function(model,at)
			if inside(at) then
				context.damage(model,Plan.WindBurst.damage)
				Enemies.knockback(model,Plan.flat(at-origin),Plan.WindBurst.push,Plan.WindBurst.lift)
			end
		end)
		for _,player in ipairs(Players:GetPlayers()) do
			local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if player~=context.player and root and inside(root.Position) then
				Combat.applyDamage(player,Plan.WindBurst.damage,context.abilityName)
				root:ApplyImpulse((direction*Plan.WindBurst.push+Vector3.new(0,Plan.WindBurst.lift,0))*root.AssemblyMass)
			end
		end
	end)
end

local function wall(context)
	local records=context.prepared.records
	local loan=Terrain:TakeBlockWall(records)
	if not loan then return false end -- no yield between validate and this transaction
	local committed=false
	context.scope:add(function() if not committed then Terrain:FinishBlockWall(loan,false) end end)
	local folder=context.scope:add(Instance.new("Folder"));folder.Name="BlockWallMovingBlocks";folder.Parent=workspace
	local pieces,packet={},{}
	for i,r in ipairs(records) do
		local template=Items.find(r.block)
		if template and not template:IsA("BasePart") then template=template:FindFirstChildWhichIsA("BasePart",true) end
		local part=if template then template:Clone() else Instance.new("Part")
		for _,child in ipairs(part:GetChildren()) do if not (child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance")) then child:Destroy() end end
		part.Name=r.block;part.Size=Vector3.one*4;part.Anchored=true
		part.CanCollide=false;part.CanQuery=false;part.CanTouch=false
		part.CFrame=CFrame.new(r.source.position);part.Parent=folder
		table.insert(pieces,part)
		table.insert(packet,{from=r.source.position,to=r.target.position,block=r.block})
	end
	local started=workspace:GetServerTimeNow()
	context.broadcast({origin=context.origin,startedAt=started,blocks=packet})
	local connection
	connection=context.scope:add(RunService.Heartbeat:Connect(function()
		local alpha=(workspace:GetServerTimeNow()-started)/Plan.BlockWall.travel
		for i,r in ipairs(packet) do
			pieces[i].CFrame=CFrame.new(Plan.wallPosition(r.from,r.to,alpha,i))*CFrame.Angles(0,math.sin(math.clamp(alpha,0,1)*math.pi)*.35,0)
		end
		if alpha>=1 then
			connection:Disconnect()
			local clear=true
			for _,r in ipairs(records) do if not clearBox(CFrame.new(r.target.position),Vector3.one*3.8,nil) then clear=false;break end end
			Terrain:FinishBlockWall(loan,clear)
			committed=true
			folder:Destroy()
		end
	end))
	return true
end

function Ability.duration() return Plan.duration() end
function Ability.cast(context)
	if context.abilityName=="Fireball" or context.abilityName=="WaterBlade" then projectile(context)
	elseif context.abilityName=="WindBurst" then wind(context)
	elseif context.abilityName=="EchoStep" then
		local destination=context.prepared.destination
		local forward=context.prepared.direction
		local from=context.root.Position
		local delta=destination-from
		context.character:PivotTo(context.character:GetPivot()+delta)
		context.root.AssemblyLinearVelocity=Vector3.zero
		context.broadcast({origin=CFrame.lookAt(from,from+forward),destination=destination,direction=forward,startedAt=workspace:GetServerTimeNow()})
	elseif context.abilityName=="BlockWall" then return wall(context)
	else return false end
	return true
end
return Ability
