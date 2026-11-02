local ImportedAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.DownloadedSounds)
local Sounds = require(game:GetService("ReplicatedStorage").Shared.Audio.Sounds)
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Content=game:GetService("ContentProvider")
local Plan=require(script.Parent.Parent.StarterPlan)
local Library=require(script.Parent.StarterParticles)
local Base=require(script.Parent.CataclysmParticles)
local Pack=require(script.Parent.PackAssembly)
local ImpactFX=require(script.Parent.ImpactFX)
local ReferenceVFX=require(script.Parent.ReferenceVFX)
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
	s.SoundId=id;s.Volume=Sounds.volume(volume);s.PlaybackSpeed=pitch or 1
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
	ReferenceVFX.preload()
	if not listening and RunService:IsRunning() and RunService:IsClient() then
		listening=true
		Remotes.wait("AbilityImpact").OnClientEvent:Connect(function(payload)
			if type(payload)=="table" and type(payload.id)=="string" and typeof(payload.position)=="Vector3" then
				local receive=shots[payload.id];if receive then receive(payload) end
			end
		end)
	end
	Pack.preload()
	if preloaded then return end
	preloaded=true
	task.spawn(function()
		local assets={}
		for _,data in pairs(Library) do table.insert(assets,data.Texture) end
		for _,kind in ipairs({"Flame","FireballA","Smoke","Embers","Flash","PressureRing","Rock","Streaks"}) do table.insert(assets,Base[kind].Texture) end
		local sounds={}
		for _,id in ipairs({ImportedAudio.ability_whoosh,ImportedAudio.ability_impact_heavy,"rbxasset://sounds/impact_water.mp3"}) do
			local s=Instance.new("Sound");s.SoundId=id;table.insert(sounds,s);table.insert(assets,s)
		end
		pcall(function() Content:PreloadAsync(assets,function(asset,status)
			if status~=Enum.AssetFetchStatus.Success then warn("[StarterVFX] Asset unavailable: "..asset) end
		end) end)
		for _,s in ipairs(sounds) do s:Destroy() end
	end)
end
function VFX.duration() return Plan.duration() end

-- Fireball shares Blighted Fireball's particle body in ReferenceVFX;
-- its original authored explosion and tint remain here.
local MUZZLE=3.5
local Shots={
	Fireball={
		tint={deep=Color3.fromRGB(150,12,3),main=Color3.fromRGB(255,58,8),hot=Color3.fromRGB(255,142,44)},
	},
	WaterBlade={
		tint={deep=Color3.fromRGB(8,74,190),main=WATER,hot=FOAM},
		body={"CrescentSlash",1,90},bodyPart="Crescent Slash",meshTint={deep=Color3.fromRGB(6,58,170),main=Color3.fromRGB(16,112,235),hot=FOAM},
		-- The arc cuts forward, tipped up and rolled so its face stays to the camera;
		-- lying flat it turns edge-on from behind the caster.
		lie=CFrame.Angles(math.rad(58),0,math.rad(-16))*CFrame.fromMatrix(Vector3.zero,Vector3.yAxis,-Vector3.xAxis,Vector3.zAxis),
		glow={"Droplets69",.55,40},tail={"KiBlast2",.09},length=15,
		muzzle={"SlashImpact1",1.2,1},light=WATER,launch=1.5,
	},
}

local function fireBlast(scope,folder,point,direction,tint,silent)
	local frame=CFrame.lookAt(point,point+direction)
	local function mount(name,scale,budget,extra)
		local options={cframe=frame,scale=scale,budget=budget,tint=extra or tint,brightness=1.6}
		return Pack.mount(scope,folder,name,options)
	end
	local p=host(folder,"Impact",point,direction)
	local light=Instance.new("PointLight");light.Color=FIRE;light.Brightness=2.5;light.Range=32;light.Shadows=false;light.Parent=p
	scope:tween(light,TweenInfo.new(.7,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Brightness=0})
	-- First beat: flame spikes inside a swirling rim of fire.
	mount("Impact45",1.1):burst(1)
	mount("Impact1",1.4):burst(.9)
	mount("FireVFX5",.95):burst(.45)
	if not silent then sound(p,ImportedAudio.ability_impact_heavy,.6,1.25) end
	ImpactFX.shake(point,1.4,.4,70);ImpactFX.punch(point,4,.35,70)
	-- Second beat: the fireball itself rolls out, then breaks into embers and smoke.
	scope:delay(.17,function()
		mount("Impact41",2.2):burst(1)
		mount("FireVFX8",1.8):burst(1)
		mount("Impact20",1.15):burst(1)
		Pack.mount(scope,folder,"Rocks",{cframe=CFrame.new(point),scale=.5,tint=tint,brightness=2}):burst(1)
		if not silent then sound(p,ImportedAudio.ability_impact_heavy,.5,.8) end
	end)
	local smoke=Color3.fromRGB(22,14,14)
	scope:delay(.34,function()
		Pack.mount(scope,folder,"SmokePuff",{cframe=frame,scale=2.2,tint={deep=smoke,main=smoke,hot=Color3.fromRGB(60,34,28)}}):burst(1.4)
		local linger=mount("FireVFX6",2.4,120)
		linger:stream(true)
		scope:delay(.45,function() linger:stream(false) end)
	end)
end

local function waterSplash(scope,folder,point,direction,tint)
	local frame=CFrame.lookAt(point,point+direction)
	local p=host(folder,"Impact",point,direction)
	local function mount(name,scale,budget)
		return Pack.mount(scope,folder,name,{cframe=frame,scale=scale,budget=budget,tint=tint,brightness=2})
	end
	mount("SlashImpact1",2.6):burst(1)
	mount("SlashImpact3",2.2):burst(1)
	mount("Impact36",2.4):burst(1)
	mount("Droplets69",.8):burst(1)
	local splash=Pack.mount(scope,folder,"IceSplash",{cframe=CFrame.new(point),scale=.16,tint=tint,brightness=2,visible=true})
	splash:burst(1)
	splash:grow(scope,.3,.45)
	local drops=mount("Droplets69",.55,36)
	drops:stream(true)
	scope:delay(.3,function() drops:stream(false) end)
	sound(p,"rbxasset://sounds/impact_water.mp3",.6,1.3)
	ImpactFX.shake(point,.9,.3,60);ImpactFX.punch(point,2,.3,60)
end

local function projectile(payload,scope,folder,age)
	local tuning=Plan[payload.ability]
	local shot=Shots[payload.ability]
	local origin=payload.origin.Position
	local direction=payload.direction
	local frame=CFrame.lookAt(origin,origin+direction)
	local p=host(folder,"Projectile",origin,direction)
	local function part(entry,extra)
		local options={cframe=frame,scale=entry[2],budget=entry[3],tint=shot.tint,brightness=2}
		for key,value in pairs(extra or {}) do options[key]=value end
		return Pack.mount(scope,folder,entry[1],options)
	end
	local body=part(shot.body,{visible=true,locked=true,meshTint=shot.meshTint})
	if shot.bodyPart then body:alignPart(shot.bodyPart,shot.lie) end
	if shot.head then body:trailBeams(shot.head) end
	if shot.slim then body:slim(shot.slim) end
	local glow,tail=part(shot.glow),part(shot.tail)
	tail:taper(.2)
	-- The body gathers at the muzzle through the windup, small, then swells.
	body:rescale(shot.body[2]*.35)
	body:stream(true)
	local function place(at)
		local to=CFrame.lookAt(at,at+direction)
		body:place(to)
		glow:place(to)
	end
	place(origin+direction*MUZZLE)
	local light=Instance.new("PointLight");light.Color=shot.light;light.Brightness=2;light.Range=18;light.Parent=p
	local stopped,launched=false,false
	local function stop(packet)
		if stopped then return end
		stopped=true;p.Position=packet.position
		body:clear();body:fade(0);glow:stream(false);tail:clear()
		light.Enabled=false
		if not packet.cancelled then
			local normal=packet.normal or -direction
			waterSplash(scope,folder,packet.position,normal,shot.tint)
		end
		-- The shot is over: its server cast may still be open, its visuals need not be.
		scope:delay(2.2,function() scope:destroy() end)
	end
	if payload.id then shots[payload.id]=stop;scope:add(function() shots[payload.id]=nil end) end
	local function update()
		if stopped then return end
		local elapsed=workspace:GetServerTimeNow()-payload.startedAt
		local travel=math.clamp((elapsed-tuning.windup)*tuning.speed,0,tuning.range)
		local at=origin+direction*(travel+math.min(MUZZLE,tuning.range-travel))
		p.CFrame=CFrame.lookAt(at,at+direction)
		if not launched then body:rescale(shot.body[2]*(.35+.65*math.clamp(elapsed/tuning.windup,0,1))) end
		place(at)
		if elapsed>=tuning.windup and not launched then
			launched=true
			body:rescale(shot.body[2])
			glow:stream(true);tail:beamsOn(true);body:beamsOn(true)
			Pack.mount(scope,folder,shot.muzzle[1],{cframe=frame,scale=shot.muzzle[2],tint=shot.tint,brightness=2}):burst(shot.muzzle[3])
			sound(p,ImportedAudio.ability_whoosh,.3,shot.launch)
		end
		if launched then tail:stretch(at,at-direction*math.min(travel,shot.length)) end
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
		sound(root,ImportedAudio.ability_whoosh,.5,.8)
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
	sound(from,ImportedAudio.ability_whoosh,.35,1.8)
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
		if movers[1] then sound(movers[1].host,ImportedAudio.ability_impact_heavy,.15,1.1) end
	end)
end

function VFX.play(payload,scope)
	if typeof(payload.origin)~="CFrame" or type(payload.startedAt)~="number" then return false end
	local age=workspace:GetServerTimeNow()-payload.startedAt
	if age>=Plan.duration() then return false end
	VFX.preload()
	if payload.ability=="Fireball" then
		return ReferenceVFX.play(payload,scope,function(impactScope,impactFolder,point,normal)
			fireBlast(impactScope,impactFolder,point,normal,Shots.Fireball.tint,true)
		end)
	end
	local folder=scope:add(Instance.new("Folder"));folder.Name=payload.ability.."VFX";folder.Parent=workspace
	local function at(t,callback)
		if age>t+.3 then return end
		scope:delay(math.max(0,t-age),callback)
	end
	if payload.ability=="WaterBlade" then projectile(payload,scope,folder,age)
	elseif payload.ability=="WindBurst" then wind(payload,scope,folder,at)
	elseif payload.ability=="EchoStep" then echo(payload,scope,folder,at)
	elseif payload.ability=="BlockWall" then wall(payload,scope,folder,at)
	else return false end
	scope:delay(math.max(0,Plan.duration()-age),function() scope:destroy() end)
	return true
end
return VFX
