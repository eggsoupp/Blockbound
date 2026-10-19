local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Content=game:GetService("ContentProvider")
local Plan=require(script.Parent.Parent.StarterPlan)
local Library=require(script.Parent.StarterParticles)
local Base=require(script.Parent.CataclysmParticles)
local Remotes=require(RS.Shared.Net.Remotes)
local VFX={}
local shots={}
local listening,preloaded=false,false
local FIRE=Color3.fromRGB(255,123,34)
local GOLD=Color3.fromRGB(255,221,142)
local WATER=Color3.fromRGB(59,184,255)
local FOAM=Color3.fromRGB(191,246,255)
local WIND=Color3.fromRGB(211,255,235)
local ECHO=Color3.fromRGB(133,194,255)
local EARTH=Color3.fromRGB(145,111,73)
local function ns(a,b) return NumberSequence.new(a,b) end
local function host(parent,name,position,direction)
	local p=Instance.new("Part")
	p.Name=name;p.Size=Vector3.one*.1;p.Transparency=1
	p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
	p.CFrame=if direction then CFrame.lookAt(position,position+direction) else CFrame.new(position)
	p.Parent=parent
	return p
end
local function emitter(kind,parent,props)
	local data=Library[kind] or Base[kind]
	local p=Instance.new("ParticleEmitter")
	p.Name=kind;p.Texture=data.Texture;p.FlipbookLayout=data.FlipbookLayout
	for key,value in pairs(data) do p[key]=value end
	p.Enabled=false;p.Rate=0;p.TimeScale=1;p.ZOffset=0
	for key,value in pairs(props or {}) do p[key]=value end
	p.Parent=parent
	return p
end
local function burst(kind,parent,count,props)
	local p=emitter(kind,parent,props);p:Emit(count);return p
end
local function sound(parent,id,volume,pitch)
	local s=Instance.new("Sound")
	s.SoundId=id;s.Volume=volume;s.PlaybackSpeed=pitch or 1
	s.RollOffMinDistance=6;s.RollOffMaxDistance=100;s.Parent=parent;s:Play()
end
local function attach(parent,position)
	local a=Instance.new("Attachment");a.Position=position or Vector3.zero;a.Parent=parent;return a
end
local function ring(parent,color,from,to,lifetime)
	return burst("PressureRing",parent,1,{
		Color=ColorSequence.new(color),Size=ns(from,to),Lifetime=NumberRange.new(lifetime),
		Speed=NumberRange.new(.001),SpreadAngle=Vector2.zero,Drag=0,Squash=NumberSequence.new(0),
		EmissionDirection=Enum.NormalId.Front,Orientation=Enum.ParticleOrientation.VelocityPerpendicular,
		Transparency=ns(.15,1),LightEmission=.7,Brightness=1.2,
	})
end
function VFX.preload()
	if not listening and RunService:IsRunning() and RunService:IsClient() then
		listening=true
		Remotes.wait("AbilityImpact").OnClientEvent:Connect(function(payload)
			if type(payload)=="table" and type(payload.id)=="string" and typeof(payload.position)=="Vector3" then
				local receive=shots[payload.id];if receive then receive(payload) end
			end
		end)
	end
	if preloaded then return end
	preloaded=true
	task.spawn(function()
		local assets={}
		for _,data in pairs(Library) do table.insert(assets,data.Texture) end
		for _,kind in ipairs({"Flame","FireballA","Smoke","Embers","Flash","PressureRing","Rock","Streaks"}) do table.insert(assets,Base[kind].Texture) end
		local sounds={}
		for _,id in ipairs({"rbxassetid://12222208","rbxassetid://5540424854","rbxasset://sounds/impact_water.mp3"}) do
			local s=Instance.new("Sound");s.SoundId=id;table.insert(sounds,s);table.insert(assets,s)
		end
		pcall(function() Content:PreloadAsync(assets,function(asset,status)
			if status~=Enum.AssetFetchStatus.Success then warn("[StarterVFX] Asset unavailable: "..asset) end
		end) end)
		for _,s in ipairs(sounds) do s:Destroy() end
	end)
end
function VFX.duration() return Plan.duration() end

local function impact(folder,kind,point,direction)
	local p=host(folder,"Impact",point,direction)
	if kind=="Fireball" then
		burst("FireballA",p,5,{Size=ns(3,9),Lifetime=NumberRange.new(.35,.55),Speed=NumberRange.new(3,10),SpreadAngle=Vector2.new(150,150),Brightness=.8,Color=ColorSequence.new(GOLD,FIRE)})
		burst("Flash",p,1,{Size=ns(12,0),Lifetime=NumberRange.new(.12),Transparency=ns(.1,1),Color=ColorSequence.new(GOLD)})
		burst("Embers",p,28,{Size=ns(.35,0),Lifetime=NumberRange.new(.25,.65),Speed=NumberRange.new(15,35),Drag=2,Acceleration=Vector3.new(0,-25,0),Color=ColorSequence.new(GOLD,FIRE),LightEmission=1})
		burst("Smoke",p,5,{Size=ns(2,6),Lifetime=NumberRange.new(.5,.9),Speed=NumberRange.new(3,8),Color=ColorSequence.new(Color3.fromRGB(83,72,63)),Transparency=ns(.5,1)})
		sound(p,"rbxassetid://5540424854",.3,1.7)
	else
		burst("WaterSplash",p,8,{Size=ns(4,9),Lifetime=NumberRange.new(.3,.65),Speed=NumberRange.new(8,22),SpreadAngle=Vector2.new(95,95),Color=ColorSequence.new(FOAM,WATER),Brightness=1.3,LightEmission=.45,Acceleration=Vector3.new(0,-20,0)})
		burst("Embers",p,20,{Size=ns(.3,0),Lifetime=NumberRange.new(.35,.65),Speed=NumberRange.new(15,28),Drag=1,Acceleration=Vector3.new(0,-35,0),Color=ColorSequence.new(FOAM,WATER),LightEmission=.6})
		ring(p,FOAM,2,12,.3)
		sound(p,"rbxasset://sounds/impact_water.mp3",.45,1.4)
	end
end

local function projectile(payload,scope,folder,age)
	local tuning=Plan[payload.ability]
	local origin=payload.origin.Position
	local direction=payload.direction
	local p=host(folder,"Projectile",origin,direction)
	local isFire=payload.ability=="Fireball"
	local color=if isFire then GOLD else FOAM
	local charge=burst("Flash",p,1,{Size=ns(.5,if isFire then 5 else 7),Lifetime=NumberRange.new(tuning.windup),Transparency=ns(.4,1),Color=ColorSequence.new(color),Brightness=1})
	local moving={}
	if isFire then
		table.insert(moving,emitter("Flame",p,{Rate=45,Size=ns(4.2,1.5),Lifetime=NumberRange.new(.18,.28),Speed=NumberRange.new(0,2),Drag=0,Color=ColorSequence.new(GOLD,FIRE),LightEmission=.8,Brightness=1.2,LockedToPart=true}))
		table.insert(moving,emitter("FireballA",p,{Rate=18,Size=ns(3.5,2),Lifetime=NumberRange.new(.22,.35),Speed=NumberRange.new(0,2),Color=ColorSequence.new(GOLD,FIRE),Brightness=.7,LockedToPart=false}))
		table.insert(moving,emitter("Embers",p,{Rate=30,Size=ns(.22,0),Lifetime=NumberRange.new(.2,.45),Speed=NumberRange.new(2,7),Color=ColorSequence.new(GOLD,FIRE),LightEmission=1}))
		local light=Instance.new("PointLight");light.Color=FIRE;light.Brightness=1;light.Range=12;light.Parent=p
	else
		-- Authored animated water crescent, with a second foam edge and a wet wake.
		table.insert(moving,emitter("WaterCrescent",p,{Rate=5,Size=NumberSequence.new(7),Squash=NumberSequence.new(-.65),Lifetime=NumberRange.new(.24),Speed=NumberRange.new(.001),Rotation=NumberRange.new(-12),LockedToPart=true,Color=ColorSequence.new(WATER,FOAM),LightEmission=.5,Brightness=1.1,Transparency=ns(.05,.4)}))
		table.insert(moving,emitter("WaterSlash",p,{Rate=5,Size=NumberSequence.new(6),Squash=NumberSequence.new(-.65),Lifetime=NumberRange.new(.24),Speed=NumberRange.new(.001),Rotation=NumberRange.new(-12),LockedToPart=true,Color=ColorSequence.new(FOAM),LightEmission=.6,Brightness=1.2,Transparency=ns(.25,1)}))
		table.insert(moving,emitter("WaterTrail",p,{Rate=24,Size=ns(1.7,.5),Lifetime=NumberRange.new(.15,.27),Speed=NumberRange.new(0,2),Color=ColorSequence.new(WATER,FOAM),LightEmission=.4,Brightness=1,Transparency=ns(.4,1)}))
	end
	local stopped,launched=false,false
	local function stop(packet)
		if stopped then return end
		stopped=true;p.Position=packet.position
		for _,e in ipairs(moving) do e.Enabled=false;if e.LockedToPart then e:Clear() end end
		charge:Clear()
		for _,d in ipairs(p:GetChildren()) do if d:IsA("Light") then d.Enabled=false end end
		if not packet.cancelled then impact(folder,payload.ability,packet.position,packet.normal or -direction) end
	end
	if payload.id then shots[payload.id]=stop;scope:add(function() shots[payload.id]=nil end) end
	local function update()
		if stopped then return end
		local elapsed=workspace:GetServerTimeNow()-payload.startedAt
		local travel=math.clamp((elapsed-tuning.windup)*tuning.speed,0,tuning.range)
		p.CFrame=CFrame.lookAt(origin+direction*travel,origin+direction*(travel+1))
		if elapsed>=tuning.windup and not launched then
			launched=true
			for _,e in ipairs(moving) do e.Enabled=true;e:Emit(if isFire then 2 else 1) end
			sound(p,"rbxassetid://12222208",.3,if isFire then 1.2 else 1.5)
		end
		if elapsed>tuning.windup+tuning.range/tuning.speed+.3 then stop({position=p.Position}) end
		local caster=payload.caster
		if caster and (not caster.Character or not caster.Character:FindFirstChildOfClass("Humanoid") or caster.Character:FindFirstChildOfClass("Humanoid").Health<=0) then stop({position=p.Position,cancelled=true}) end
	end
	update();scope:add(RunService.Heartbeat:Connect(update))
end

local function wind(payload,scope,folder,at)
	local origin=payload.origin.Position
	local direction=payload.direction
	local root=host(folder,"WindGather",origin+direction*2,direction)
	burst("Wind",root,1,{Size=ns(4,1),Lifetime=NumberRange.new(.16),Speed=NumberRange.new(.001),SpreadAngle=Vector2.zero,EmissionDirection=Enum.NormalId.Front,Color=ColorSequence.new(WIND),Transparency=ns(.7,.2)})
	at(Plan.WindBurst.windup,function()
		sound(root,"rbxassetid://12222208",.5,.8)
		-- Fixed emitter stations and widening arcs read as a short shove, not a ball.
		for i=1,3 do
			local p=host(folder,"WindFan",origin+direction*(2+i*3),direction)
			ring(p,WIND,2+i,8+i*4,.3+i*.025)
			burst("Wind",p,2,{Size=ns(3+i,10+i*4),Lifetime=NumberRange.new(.35,.45),Speed=NumberRange.new(.01),SpreadAngle=Vector2.zero,EmissionDirection=Enum.NormalId.Front,Color=ColorSequence.new(WIND),LightEmission=.55,Brightness=1.4,Transparency=ns(.18,1),RotSpeed=NumberRange.new(-55,55)})
		end
		burst("WindMist",root,8,{Size=ns(3,7),Lifetime=NumberRange.new(.25,.5),Speed=NumberRange.new(15,30),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.new(25,55),Color=ColorSequence.new(WIND),Transparency=ns(.65,1),LightEmission=.2})
		burst("Streaks",root,20,{Size=ns(1.3,0),Lifetime=NumberRange.new(.12,.3),Speed=NumberRange.new(35,55),EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.new(15,45),Color=ColorSequence.new(WIND),LockedToPart=false,Brightness=1.5})
	end)
end

local function echo(payload,scope,folder,at)
	local from=host(folder,"Departure",payload.origin.Position,payload.direction)
	local to=host(folder,"Arrival",payload.destination,payload.direction)
	local a,b=attach(from),attach(to)
	local beam=Instance.new("Beam")
	beam.Name="EchoRibbon";beam.Attachment0=a;beam.Attachment1=b;beam.FaceCamera=true
	beam.Texture=Library.Slash.Texture;beam.TextureSpeed=2;beam.TextureLength=7
	beam.Width0=2.4;beam.Width1=.3;beam.Color=ColorSequence.new(ECHO,FOAM);beam.LightEmission=.8
	beam.Transparency=NumberSequence.new(.2);beam.Parent=from
	burst("Echo",from,2,{Size=ns(7,12),Lifetime=NumberRange.new(.3),Speed=NumberRange.new(.001),Color=ColorSequence.new(ECHO),LightEmission=.6,Brightness=1.3})
	ring(from,ECHO,2,9,.3)
	for i=1,5 do
		local p=host(folder,"EchoTrace",payload.origin.Position:Lerp(payload.destination,i/6),payload.direction)
		burst("WindMist",p,1,{Size=ns(3,5),Lifetime=NumberRange.new(.18+i*.025),Speed=NumberRange.new(.001),Color=ColorSequence.new(ECHO),Transparency=ns(.55,1),LightEmission=.6})
	end
	at(.08,function()
		burst("Echo",to,2,{Size=ns(4,10),Lifetime=NumberRange.new(.35),Speed=NumberRange.new(.001),Color=ColorSequence.new(FOAM,ECHO),LightEmission=.7})
		ring(to,FOAM,2,9,.35)
		burst("Embers",to,16,{Size=ns(.25,0),Lifetime=NumberRange.new(.3,.6),Speed=NumberRange.new(5,15),Color=ColorSequence.new(FOAM,ECHO),LightEmission=1})
	end)
	sound(from,"rbxassetid://12222208",.35,1.8)
	scope:add(RunService.Heartbeat:Connect(function()
		beam.Transparency=NumberSequence.new(math.clamp(.2+(workspace:GetServerTimeNow()-payload.startedAt)/.35,0,1))
	end))
end

local function wall(payload,scope,folder,at)
	local movers={}
	for i,r in ipairs(payload.blocks or {}) do
		local p=host(folder,"EarthWake",r.from)
		local smoke=emitter("Smoke",p,{Rate=12,Size=ns(1.3,3),Lifetime=NumberRange.new(.25,.5),Speed=NumberRange.new(1,3),Color=ColorSequence.new(EARTH),LightEmission=.05,Transparency=ns(.6,1)})
		smoke.Enabled=true
		burst("Rock",p,5,{Size=ns(.3,0),Lifetime=NumberRange.new(.25,.45),Speed=NumberRange.new(5,12),Color=ColorSequence.new(EARTH),Acceleration=Vector3.new(0,-25,0)})
		table.insert(movers,{host=p,smoke=smoke,record=r,index=i})
	end
	scope:add(RunService.Heartbeat:Connect(function()
		local alpha=(workspace:GetServerTimeNow()-payload.startedAt)/Plan.BlockWall.travel
		for _,v in ipairs(movers) do
			v.host.Position=Plan.wallPosition(v.record.from,v.record.to,alpha,v.index)
			if alpha>=1 then v.smoke.Enabled=false end
		end
	end))
	at(Plan.BlockWall.travel,function()
		for _,v in ipairs(movers) do
			burst("Smoke",v.host,3,{Size=ns(2,4),Lifetime=NumberRange.new(.35,.6),Speed=NumberRange.new(3,8),Color=ColorSequence.new(EARTH),Transparency=ns(.5,1),LightEmission=.1})
		end
		if movers[1] then sound(movers[1].host,"rbxassetid://5540424854",.15,1.1) end
	end)
end

function VFX.play(payload,scope)
	if typeof(payload.origin)~="CFrame" or type(payload.startedAt)~="number" then return false end
	local age=workspace:GetServerTimeNow()-payload.startedAt
	if age>=Plan.duration() then return false end
	VFX.preload()
	local folder=scope:add(Instance.new("Folder"));folder.Name=payload.ability.."VFX";folder.Parent=workspace
	local function at(t,callback)
		if age>t+.3 then return end
		scope:delay(math.max(0,t-age),callback)
	end
	if payload.ability=="Fireball" or payload.ability=="WaterBlade" then projectile(payload,scope,folder,age)
	elseif payload.ability=="WindBurst" then wind(payload,scope,folder,at)
	elseif payload.ability=="EchoStep" then echo(payload,scope,folder,at)
	elseif payload.ability=="BlockWall" then wall(payload,scope,folder,at)
	else return false end
	scope:delay(math.max(0,Plan.duration()-age),function() scope:destroy() end)
	return true
end
return VFX
