-- The four reference spells use intact SoulShroud assemblies, cloned by PackAssembly.
-- No texture reconstruction, visible carriers, audio, global grade or camera takeover.
local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Plan=require(script.Parent.Parent.ReferencePlan)
local StarterPlan=require(script.Parent.Parent.StarterPlan)
local Pack=require(script.Parent.PackAssembly)
local Kit=require(script.Parent.AbilityKit)
local ImpactFX=require(script.Parent.ImpactFX)
local Remotes=require(RS.Shared.Net.Remotes)
local Sources=RS:WaitForChild("ReferenceAbilitySources",10)
local VFX={}
local receivers,pending={},{}
local listening,preloaded,live=false,false,0
local VIOLET={deep=Color3.fromRGB(33,8,94),main=Color3.fromRGB(132,80,255),hot=Color3.fromRGB(233,225,255)}
local CELESTIAL={deep=Color3.fromRGB(10,55,160),main=Color3.fromRGB(25,175,255),hot=Color3.fromRGB(135,230,255)}
local WRAITH={deep=Color3.fromRGB(12,12,68),main=Color3.fromRGB(45,113,255),hot=Color3.fromRGB(208,243,255)}
local FIREBALL={deep=Color3.fromRGB(110,3,3),main=Color3.fromRGB(255,24,20),hot=Color3.fromRGB(255,90,85)}
local TINTS={VioletTempest=VIOLET,CelestialLance=CELESTIAL,WraithfireOrb=WRAITH,RiftMaelstrom=VIOLET,Fireball=FIREBALL}

function VFX.preload()
	Pack.preload()
	if not preloaded and Sources then
		preloaded=true
		task.spawn(function() pcall(function() game:GetService("ContentProvider"):PreloadAsync({Sources}) end) end)
	end
	if listening or not RunService:IsClient() then return end
	listening=true
	Remotes.wait("AbilityImpact").OnClientEvent:Connect(function(packet)
		if type(packet)~="table" or (not Plan[packet.ability] and packet.ability~="Fireball") or type(packet.id)~="string" then return end
		local receive=receivers[packet.id]
		if receive then receive(packet);return end
		-- Handles a cancellation arriving before its cast on the other remote.
		local now=workspace:GetServerTimeNow()
		for id,events in pairs(pending) do if now-events[1].startedAt>6 then pending[id]=nil end end
		local count=0;for _ in pairs(pending) do count+=1 end
		if count<32 then pending[packet.id]=pending[packet.id] or {};table.insert(pending[packet.id],packet) end
	end)
end
function VFX.duration() return Plan.duration() end

function VFX.play(payload,scope,fireballImpact)
	local starter=payload.ability=="Fireball"
	local T=if starter then StarterPlan.Fireball else Plan[payload.ability]
	if not T or type(payload.id)~="string" or typeof(payload.origin)~="CFrame" or type(payload.startedAt)~="number" then return false end
	local duration=if starter then StarterPlan.duration() else T.duration
	local age=workspace:GetServerTimeNow()-payload.startedAt
	if age>duration or live>=8 then return false end
	if payload.target and typeof(payload.target)~="Vector3" then return false end
	if payload.centre and (typeof(payload.centre)~="Vector3" or typeof(payload.normal)~="Vector3") then return false end
	VFX.preload()
	live+=1;scope:add(function() live-=1;receivers[payload.id]=nil;pending[payload.id]=nil end)
	local folder=scope:add(Instance.new("Folder"));folder.Name=payload.ability;folder.Parent=workspace
	folder:SetAttribute("ReferenceAbility",true)
	local tint=TINTS[payload.ability]
	local distance=(workspace.CurrentCamera.CFrame.Position-payload.origin.Position).Magnitude
	local density=if distance>150 then .5 else 1
	local function make(name,frame,scale,budget,extra)
		local opts={template=Sources and Sources:FindFirstChild(name),cframe=frame,scale=scale,tint=tint,budget=(budget or 150)*density,brightness=2.4}
		for key,value in pairs(extra or {}) do opts[key]=value end
		return Pack.mount(scope,folder,name,opts)
	end
	local function burst(name,frame,scale,strength)
		local effect=make(name,frame,scale,450)
		effect:burst((strength or 1)*density)
		return effect
	end
	local character=payload.caster and payload.caster.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if payload.caster and (not humanoid or humanoid.Health<=0) then scope:destroy();return false end
	if humanoid then
		scope:add(humanoid.Died:Connect(function() scope:destroy() end))
		scope:add(payload.caster.CharacterRemoving:Connect(function() scope:destroy() end))
		local tool=character:FindFirstChildOfClass("Tool")
		if tool then scope:add(tool.Unequipped:Connect(function() scope:destroy() end)) end
	end
	scope:delay(math.max(0,duration-age),function() scope:destroy() end)
	local signal,update

	if starter or payload.ability=="CelestialLance" or payload.ability=="WraithfireOrb" then
		local celestial=payload.ability=="CelestialLance"
		local base=if celestial then .7 else 1.8
		local origin=payload.origin.Position+(if starter then Vector3.zero else Vector3.yAxis*.8)
		local target=payload.target or origin+(payload.direction or payload.origin.LookVector)*T.range
		local delta=target-origin
		local direction=if delta.Magnitude>.1 then delta.Unit else payload.origin.LookVector
		local frame=CFrame.lookAt(origin,origin+direction)
		local core=make(if celestial then "RefImpact1" else "RefFire1",frame,base*.25,if celestial then 170 else 220,{locked=true})
		-- Preserve every authored layer; narrow the travel core's wide emission speeds.
		for _,entry in ipairs(core.emitters) do
			entry.v.Speed=NumberRange.new(entry.v.Speed.Min*.22,entry.v.Speed.Max*.22)
		end
		local halo=make("RefPortal",frame,if celestial then .34 else .5,45,{locked=true})
		local tail=make(if celestial then "RefKi2" else "RefKi1",frame,if celestial then .085 else .06,45)
		tail:taper(.025)
		local ribbons={}
		if celestial then
			for i=1,3 do
				ribbons[i]=make("RefKi2",frame,.075,30)
				ribbons[i]:taper(.015);ribbons[i]:beamsOn(true)
				for _,beam in ipairs(ribbons[i].beams) do beam.CurveSize0=3;beam.CurveSize1=-3 end
			end
		end
		local wisps={}
		if not celestial then
			for i=1,2 do
				wisps[i]=make("RefFire1",frame,.5,45,{locked=true})
				wisps[i]:stream(true)
			end
		end
		core:stream(true);halo:stream(true)
		local released,releasePosition,releaseAt,stopped=false,origin,0,false
		local light=Kit.light(Kit.host(folder,"CoreLight",frame),tint.main,16)
		light.Brightness=.6
		local function stopBody()
			core:clear();halo:clear();tail:clear();light.Enabled=false
			for _,effect in ipairs(wisps) do effect:clear() end
			for _,effect in ipairs(ribbons) do effect:clear() end
		end
		local function detonate(packet)
			local point,normal=packet.position,packet.normal or -direction
			if starter then
				if fireballImpact then fireballImpact(scope,folder,point,normal) end
				return
			end
			local hitFrame=CFrame.lookAt(point+normal*.2,point+normal*2)
			if celestial then
				burst("RefImpact12",hitFrame,1.9,1.2)
				burst("RefImpact37",hitFrame,1.4,.9)
				burst("RefImpact1",hitFrame,.85,.55)
				local cross=make("RefKi2",hitFrame,.08,60)
				cross:stretch(point+Vector3.xAxis*10,point-Vector3.xAxis*10);cross:beamsOn(true)
				scope:delay(.1,function() cross:beamsOn(false) end)
			else
				burst("RefImpact41",hitFrame,1.4,1.1)
				burst("RefImpact45",hitFrame,1.15,.8)
				burst("RefImpact36",CFrame.new(point),1.7,.7)
				local fire=make("RefFire1",CFrame.new(point+Vector3.yAxis*.5),2,180)
				fire:burst(.8);fire:stream(true)
				scope:delay(.4,function() fire:stream(false) end)
			end
			local glow=Kit.light(Kit.host(folder,"ImpactLight",hitFrame),tint.main,25)
			glow.Brightness=1.5;scope:tween(glow,TweenInfo.new(.4),{Brightness=0})
			ImpactFX.shake(point,if celestial then .35 else .65,.2,65)
		end
		signal=function(packet)
			if packet.event=="release" and not stopped then
				released=true;releasePosition=packet.position;releaseAt=packet.startedAt;direction=packet.direction
				core:rescale(base);halo:stream(false);tail:beamsOn(true)
				burst("RefImpact12",CFrame.lookAt(packet.position,packet.position+direction),if celestial then .7 else .9,.55)
			elseif (packet.event=="hit" or packet.event=="expire") and not stopped then
				stopped=true;stopBody()
				if packet.event=="hit" and workspace:GetServerTimeNow()-packet.startedAt<.4 then detonate(packet) end
				scope:delay(if starter then 2.2 else 1.65,function() scope:destroy() end)
			end
		end
		update=function(elapsed)
			if stopped then return end
			-- Starter Fireball keeps its existing server clock and locked launch origin.
			if starter and not released and elapsed>=T.windup then
				signal({event="release",position=origin,direction=direction,startedAt=payload.startedAt+T.windup})
			end
			local position
			if released then
				local travelled=math.clamp((workspace:GetServerTimeNow()-releaseAt)*T.speed,0,T.range)
				position=releasePosition+direction*travelled
				tail:stretch(position,position-direction*math.min(travelled,if celestial then 24 else 15))
			else
				local root=character and character:FindFirstChild("HumanoidRootPart")
				local at=if root and not starter then root.Position+Vector3.yAxis*.8 else origin
				local toward=target-at;direction=if toward.Magnitude>.1 then toward.Unit else direction
				position=at+direction*2
				local charge=math.clamp(elapsed/T.windup,0,1)
				core:rescale(base*(.25+.75*charge))
			end
			local cf=CFrame.lookAt(position,position+direction)
			core:place(cf);halo:place(cf*CFrame.Angles(0,0,elapsed*3))
			light.Parent.CFrame=cf
			for i,effect in ipairs(ribbons) do
				effect:stretch(position,position-direction*(if released then 23 else 5+13*math.clamp(elapsed/T.windup,0,1)))
				for _,part in ipairs(effect.model:GetChildren()) do
					if part:IsA("BasePart") then part.CFrame*=CFrame.Angles(0,0,i*math.pi*2/3+elapsed*.4) end
				end
			end
			for i,effect in ipairs(wisps) do
				local angle=elapsed*4+i*math.pi
				effect:place(cf*CFrame.new(math.cos(angle)*1.5,math.sin(angle)*1.5,1))
			end
		end
	else
		if not payload.centre then scope:destroy();return false end
		local centre,normal=payload.centre,payload.normal
		local floorFrame=CFrame.new(centre+normal*.25)
		local portalFrame=floorFrame*CFrame.Angles(-math.pi/2,0,0)
		local vortex=payload.ability=="RiftMaelstrom"
		local warning=make("RefImpact36",floorFrame,if vortex then 1.4 else 1.2,20)
		warning:burst(.45)
		local rim=make("RefPortal",portalFrame,if vortex then 2.4 else 2.2,if vortex then 140 else 85)
		rim:stream(true)
		local halo=make("RefLightning",floorFrame,if vortex then 1.5 else 1.3,35)
		halo:stream(true)
		local moving={}
		if vortex then
			-- Stacked authored portals twist into an open, readable funnel.
			for i=1,3 do
				moving[i]=make("RefPortal",portalFrame,1.05+i*.2,95)
			end
		end
		local ended=false
		local function stop()
			ended=true;rim:stream(false);halo:stream(false);halo:beamsOn(false)
			for _,effect in ipairs(moving) do effect:stream(false) end
		end
		local function strike(packet)
			local final=packet.index==#T.strikes
			local size=if final then 1.7 else 1.1
			local bolt=make("RefThunder",floorFrame,if final then 4.5 else 3.2,180,{brightness=7})
			bolt:only("Lightning"):bright(2.3):narrow("Lightning",if final then 13 else 8)
				:anchor("Lightning",centre+Vector3.yAxis*(if final then 10 else 8))
			bolt:burst(.8);bolt:stream(true)
			scope:delay(.095,function() bolt:stream(false) end)
			burst("RefImpact12",floorFrame,size,1)
			burst("RefImpact37",floorFrame,size,.8)
			burst("RefImpact36",floorFrame,size,.7)
			if final then stop();ImpactFX.shake(centre,.85,.25,70) end
		end
		signal=function(packet)
			if workspace:GetServerTimeNow()-packet.startedAt>.4 then return end
			if packet.event=="strike" then strike(packet)
			elseif packet.event=="pulse" then
				burst("RefImpact36",floorFrame,1.15,.45)
				burst("RefImpact20",CFrame.new(centre+Vector3.yAxis*2),.5,.35)
			elseif packet.event=="collapse" then
				stop()
				burst("RefImpact45",CFrame.new(centre+Vector3.yAxis*2),2.3,1)
				burst("RefImpact12",floorFrame,2.4,1.1)
				burst("RefImpact37",floorFrame,2,.8)
				burst("RefImpact36",floorFrame,2.1,.9)
				ImpactFX.shake(centre,.9,.3,75)
			end
		end
		update=function(elapsed)
			if ended then return end
			halo:place(floorFrame*CFrame.Angles(0,elapsed*2.5,0))
			if vortex then
				local rise=Kit.smooth((elapsed-T.windup)/.4)
				for i,effect in ipairs(moving) do
					effect:stream(elapsed>=T.windup)
					effect:place(floorFrame*CFrame.new(0,i*2.6*rise,0)*CFrame.Angles(0,elapsed*(2+i*.7),0)*CFrame.Angles(-math.pi/2,0,0))
				end
			end
		end
	end
	receivers[payload.id]=function(packet)
		if scope:isDead() then return end
		if packet.cancelled or packet.event=="cancel" then scope:destroy();return end
		if starter and not packet.event then packet=table.clone(packet);packet.event="hit" end
		if typeof(packet.position)=="Vector3" and type(packet.startedAt)=="number" then signal(packet) end
	end
	local queued=pending[payload.id];pending[payload.id]=nil
	if queued then for _,packet in ipairs(queued) do if scope:isDead() then break end;receivers[payload.id](packet) end end
	if scope:isDead() then return false end
	update(age)
	scope:add(RunService.Heartbeat:Connect(function() update(workspace:GetServerTimeNow()-payload.startedAt) end))
	return true
end
return VFX
