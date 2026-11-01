-- Gameplay for the four reference spells. Only this server module resolves hits.
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Plan = require(RS.Shared.Abilities.ReferencePlan)
local Enemies = require(SSS.EnemyService)
local Combat = require(SSS.CombatService)
local EnemyConfig = require(RS.Shared.Enemies.EnemyConfig)
local Ability = {}
function Ability.duration() return Plan.duration() end

local function rayParams(character)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.RespectCanCollide = true
	local exclude = {character}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclude, player.Character) end
	end
	local enemies = workspace:FindFirstChild(EnemyConfig.WorldFolder)
	if enemies then table.insert(exclude, enemies) end
	p.FilterDescendantsInstances = exclude
	return p
end

local function area(context, centre, radius, amount, pull, params, excludeModel, excludePlayer)
	local function inside(at)
		local delta = at-centre
		return Vector3.new(delta.X,0,delta.Z).Magnitude <= radius and math.abs(delta.Y) <= 9
			and workspace:Raycast(centre+Vector3.yAxis*1.5,at-centre,params) == nil
	end
	Enemies.forEachNear(centre,radius+8,function(model,at)
		if model==excludeModel or not inside(at) then return end
		context.damage(model,amount)
		local delta = (centre-at)*Vector3.new(1,0,1)
		if pull and delta.Magnitude > 2 then Enemies.knockback(model,delta.Unit,pull,2) end
	end)
	for _,player in ipairs(Players:GetPlayers()) do
		local root = player ~= context.player and player ~= excludePlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local humanoid = root and player.Character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and inside(root.Position) then
			Combat.applyDamage(player,amount,context.abilityName)
			local delta = (centre-root.Position)*Vector3.new(1,0,1)
			if pull and delta.Magnitude > 2 then root:ApplyImpulse(delta.Unit*pull*root.AssemblyMass) end
		end
	end
end

function Ability.cast(context)
	local name,scope = context.abilityName,context.scope
	local T = Plan[name]
	if not T then return false end
	local id,started = Http:GenerateGUID(false),workspace:GetServerTimeNow()
	local params = rayParams(context.character)
	local function signal(event,position,extra)
		local packet = {id=id,event=event,position=position,startedAt=workspace:GetServerTimeNow()}
		for key,value in pairs(extra or {}) do packet[key]=value end
		context.impact(packet)
	end
	-- The same scope cancels damage, delayed releases and all observers' visuals.
	scope:add(function() signal("cancel",context.root.Position,{cancelled=true}) end)
	local tool = context.character:FindFirstChildOfClass("Tool")
	if tool then scope:add(tool.Unequipped:Connect(function() scope:destroy() end)) end

	if name == "CelestialLance" or name == "WraithfireOrb" then
		context.broadcast({id=id,origin=context.origin,target=context.target,startedAt=started})
		scope:delay(T.windup,function()
			if context.humanoid.Health <= 0 then return end
			local position = context.root.Position+Vector3.yAxis*.8
			-- A ground cursor aims the projectile's centre above the surface. A
			-- large legendary orb must not scrape the floor beside its caster.
			local ground = workspace:Raycast(context.target+Vector3.yAxis*2,-Vector3.yAxis*5,params)
			local groundTarget = ground and math.abs(context.target.Y-ground.Position.Y)<2
			local destination = if groundTarget then ground.Position+Vector3.yAxis*(T.radius+.9) else context.target
			local delta = destination-position
			local direction = if delta.Magnitude > .1 then delta.Unit else context.root.CFrame.LookVector
			local travelLimit = math.min(T.range,math.max(delta.Magnitude,.1))
			local released,travelled,finished = workspace:GetServerTimeNow(),0,false
			signal("release",position,{direction=direction})
			local connection
			local function finish(point,normal,model,player,confirmed)
				if finished then return end
				finished=true;connection:Disconnect()
				if confirmed then
					if model then context.damage(model,T.damage) elseif player then Combat.applyDamage(player,T.damage,name) end
					-- The direct target is excluded from the splash so it is never hit twice.
					area(context,point,T.splash,T.damage*.45,nil,params,model,player)
				end
				signal(if confirmed then "hit" else "expire",point,{normal=normal or -direction,direction=direction})
			end
			connection=scope:add(RunService.Heartbeat:Connect(function()
				local expected=math.min(travelLimit,(workspace:GetServerTimeNow()-released)*T.speed)
				local distance=expected-travelled
				if distance<=0 or finished then return end
				local step=direction*distance
				local world=workspace:Spherecast(position,T.radius,step,params)
				local best=if world then world.Distance/distance else 1
				local victim,playerVictim
				local function test(at,radius,model,player)
					local t=math.clamp((at-position):Dot(step)/step:Dot(step),0,1)
					if t<=best and (position+step*t-at).Magnitude<=T.radius+radius then best=t;victim=model;playerVictim=player end
				end
				Enemies.forEachNear(position+step*.5,distance*.5+10,function(model,at)
					test(at,math.clamp(model:GetExtentsSize().Magnitude*.25,1.5,6),model,nil)
				end)
				for _,player in ipairs(Players:GetPlayers()) do
					local root=player~=context.player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					local humanoid=root and player.Character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health>0 then test(root.Position,2,nil,player) end
				end
				if victim or playerVictim then finish(position+step*best,-direction,victim,playerVictim,true)
				elseif world then finish(world.Position,world.Normal,nil,nil,true)
				else
					position+=step;travelled=expected
					if travelled>=travelLimit then
						finish(if groundTarget then ground.Position else position,if groundTarget then ground.Normal else -direction,nil,nil,true)
					end
				end
			end))
		end)
	else
		local ground=workspace:Raycast(context.target+Vector3.yAxis*10,-Vector3.yAxis*30,params)
		local centre,normal=if ground then ground.Position else context.target,if ground then ground.Normal else Vector3.yAxis
		context.broadcast({id=id,origin=context.origin,centre=centre,normal=normal,startedAt=started})
		if name == "VioletTempest" then
			for i,at in ipairs(T.strikes) do scope:delay(at,function()
				area(context,centre,T.radius,T.damage[i],nil,params)
				signal("strike",centre,{normal=normal,index=i})
			end) end
		else
			for i,at in ipairs(T.ticks) do scope:delay(at,function()
				area(context,centre,T.radius,T.damage,12,params)
				signal("pulse",centre,{normal=normal,index=i})
			end) end
			scope:delay(T.collapse,function()
				area(context,centre,T.radius,T.finalDamage,nil,params)
				signal("collapse",centre,{normal=normal})
			end)
		end
	end
	return true
end
return Ability
