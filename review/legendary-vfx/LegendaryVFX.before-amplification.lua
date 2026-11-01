-- Four reference abilities. Every visual layer is a complete purchased assembly.
-- Existing PackAssembly/AbilityScope own cloning and lifetime; no cosmetic geometry.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Plan = require(script.Parent.Parent.ReferencePlan)
local Pack = require(script.Parent.PackAssembly)
local Kit = require(script.Parent.AbilityKit)
local ImpactFX = require(script.Parent.ImpactFX)
local Remotes = require(RS.Shared.Net.Remotes)
local Sources = RS:WaitForChild("ReferenceAbilitySources")
local Added = RS:WaitForChild("LegendaryAbilitySources")
local VFX = {}
local receivers, pending = {}, {}
local listening, preloaded, live = false, false, 0
local violet = {deep=Color3.fromRGB(24,5,70),main=Color3.fromRGB(123,56,255),hot=Color3.fromRGB(237,222,255)}
local cyan = {deep=Color3.fromRGB(6,68,142),main=Color3.fromRGB(35,206,255),hot=Color3.fromRGB(203,255,239)}
local blue = {deep=Color3.fromRGB(5,6,38),main=Color3.fromRGB(46,109,255),hot=Color3.fromRGB(193,241,255)}
local indigo = {deep=Color3.fromRGB(13,5,65),main=Color3.fromRGB(70,38,255),hot=Color3.fromRGB(151,131,255)}
local mint = {deep=Color3.fromRGB(5,73,86),main=Color3.fromRGB(51,255,177),hot=Color3.fromRGB(218,255,244)}

function VFX.duration() return Plan.duration() end
function VFX.preload()
	if not preloaded then
		preloaded=true
		task.spawn(function() pcall(function() game:GetService("ContentProvider"):PreloadAsync({Sources,Added}) end) end)
	end
	if listening or not RunService:IsClient() then return end
	listening=true
	Remotes.wait("AbilityImpact").OnClientEvent:Connect(function(packet)
		if type(packet)~="table" or not Plan[packet.ability] or type(packet.id)~="string" then return end
		if receivers[packet.id] then receivers[packet.id](packet);return end
		local now=workspace:GetServerTimeNow()
		local n=0
		for id,events in pairs(pending) do
			if now-events[1].startedAt>8 then pending[id]=nil else n+=1 end
		end
		if n<32 and type(packet.startedAt)=="number" then
			pending[packet.id]=pending[packet.id] or {}
			if #pending[packet.id]<12 then table.insert(pending[packet.id],packet) end
		end
	end)
end

function VFX.play(payload,scope)
	local T=Plan[payload.ability]
	if not T or type(payload.id)~="string" or typeof(payload.origin)~="CFrame" or type(payload.startedAt)~="number" then return false end
	local age=workspace:GetServerTimeNow()-payload.startedAt
	if age>T.duration or live>=6 then return false end
	if payload.target and typeof(payload.target)~="Vector3" then return false end
	if payload.centre and (typeof(payload.centre)~="Vector3" or typeof(payload.normal)~="Vector3") then return false end
	VFX.preload()
	live+=1
	scope:add(function() live-=1;receivers[payload.id]=nil;pending[payload.id]=nil end)
	local folder=scope:add(Instance.new("Folder"));folder.Name=payload.ability;folder.Parent=workspace
	folder:SetAttribute("ReferenceAbility",true)
	folder:SetAttribute("LegendaryAbility",true)
	local celestial=payload.ability=="CelestialLance"
	local orb=payload.ability=="WraithfireOrb"
	local tint=if celestial then cyan elseif orb then blue elseif payload.ability=="RiftMaelstrom" then indigo else violet
	local distance=(workspace.CurrentCamera.CFrame.Position-payload.origin.Position).Magnitude
	local density=(if distance>180 then .45 else 1)*(if live>3 then .65 else 1)
	local function make(name,frame,scale,budget,options)
		local opts={template=Added:FindFirstChild(name) or Sources:FindFirstChild(name),cframe=frame,scale=scale,tint=tint,budget=(budget or 160)*density,brightness=3}
		assert(opts.template,"Missing purchased assembly "..name)
		for k,v in pairs(options or {}) do opts[k]=v end
		local effect=Pack.mount(scope,folder,name,opts)
		-- Single-host packs were displayed at arbitrary rotations in the library.
		-- Align the whole authored host, including every attachment, to this stage.
		if opts.template:IsA("BasePart") then
			effect:alignPart(opts.template.Name,CFrame.identity)
			effect:place(frame)
		end
		-- Keep the authored smoke, but reserve screen coverage for the energy silhouette.
		if (name=="RefPortal" and not orb) or name=="LegendWindSwirls" or name=="LegendStylizedWind" then
			for _,e in ipairs(effect.emitters) do
				local c=e.v.Color.Keypoints[1].Value
				if math.max(c.R,c.G,c.B)<.16 then
					local keys={}
					for _,k in ipairs(e.v.Transparency.Keypoints) do table.insert(keys,NumberSequenceKeypoint.new(k.Time,1-(1-k.Value)*.32,k.Envelope*.32)) end
					e.v.Transparency=NumberSequence.new(keys)
				end
			end
		end
		return effect
	end
	local function burst(name,frame,scale,strength)
		local effect=make(name,frame,scale,650)
		-- Scale the silhouette without firing the authored fragments far outside
		-- the hit area. Preserve the authored sequences and flipbook animation.
		for _,e in ipairs(effect.emitters) do
			e.v.Speed=NumberRange.new(e.v.Speed.Min*.28,e.v.Speed.Max*.28)
			e.v.Acceleration*=.2
			e.v.Lifetime=NumberRange.new(e.v.Lifetime.Min*1.35,e.v.Lifetime.Max*1.35)
		end
		scope:spawn(function()
			RunService.RenderStepped:Wait()
			if not scope:isDead() then effect:burst((strength or 1)*density) end
		end)
		return effect
	end
	local function stopAfter(effect,seconds)
		scope:delay(seconds,function() effect:stream(false);effect:beamsOn(false) end)
	end
	local function flash(point,strength)
		local light=Kit.light(Kit.host(folder,"ImpactLight",CFrame.new(point)),tint.main,45)
		light.Brightness=strength
		scope:tween(light,TweenInfo.new(.45),{Brightness=0})
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
	scope:delay(math.max(0,T.duration-age),function() scope:destroy() end)
	local signal,update
	if celestial or orb then
		local origin=payload.origin.Position+Vector3.yAxis*.8
		local target=payload.target or origin+payload.origin.LookVector*T.range
		local delta=target-origin
		local direction=if delta.Magnitude>.1 then delta.Unit else payload.origin.LookVector
		local frame=CFrame.lookAt(origin,origin+direction)
		local base=if celestial then 1.4 else 2.6
		local core=make(if celestial then "RefImpact1" else "RefFire1",frame,base*.35,if celestial then 190 else 250,{locked=true,tint=if celestial then mint else tint})
		for _,e in ipairs(core.emitters) do e.v.Speed=NumberRange.new(e.v.Speed.Min*.16,e.v.Speed.Max*.16) end
		local halo=make("RefPortal",frame,if celestial then .65 else .9,105,{locked=true})
		local crown=if orb then make("RefFire9",frame,1.8,80,{locked=true}) else nil
		local tail=make(if celestial then "LegendBlast" else "RefKi1",frame,if celestial then .3 else .11,80,{faceCamera=true})
		tail:taper(.015)
		local ribbons,wisps={},{}
		if celestial then
			for i=1,4 do
				local e=make("RefKi2",frame,.1,24,{faceCamera=true})
				e:taper(.015);e:beamsOn(true);ribbons[i]=e
			end
		else
			for i=1,3 do
				wisps[i]=make("RefFire1",frame,.7,65,{locked=true})
				wisps[i]:stream(true)
			end
		end
		core:stream(true);halo:stream(true)
		if crown then crown:stream(true) end
		local released,stopped,releasePosition,releaseAt,lastScale=false,false,origin,0,-1
		local light=Kit.light(Kit.host(folder,"CoreLight",frame),tint.main,22);light.Brightness=.8
		local function stopBody()
			core:clear();halo:clear();tail:clear();light.Enabled=false
			if crown then crown:clear() end
			for _,e in ipairs(ribbons) do e:clear() end
			for _,e in ipairs(wisps) do e:clear() end
		end
		local function impact(packet)
			local p,n=packet.position,packet.normal or -direction
			-- Impact12 emits along local Back, so its +Z axis faces off the surface.
			local cf=CFrame.lookAt(p+n*.3,p-n*2)
			if celestial then
				burst("RefImpact12",cf,4.7,1.3)
				burst("RefImpact37",cf,3.1,1)
				burst("LegendLines",cf,2.2,.7)
				local globe=make("RefImpact1",cf,3,240,{locked=true})
				globe:burst(.65);globe:stream(true);stopAfter(globe,.3)
				local rings=make("RefPortal",cf,2.05,100)
				rings:burst(.7);rings:stream(true);stopAfter(rings,.55)
				local lance=make("LegendBlast",cf,.65,90,{faceCamera=true})
				lance:stretch(p,p-direction*math.min((p-releasePosition).Magnitude,52))
				lance:beamsOn(true);lance:burst(.4);stopAfter(lance,.16)
			else
				burst("RefImpact41",cf,4.4,1.35)
				burst("RefImpact45",cf,2.9,1)
				burst("RefImpact36",CFrame.new(p),6.8,.85)
				burst("RefImpact1",CFrame.new(p+Vector3.yAxis*4),2.4,1.1)
				local flame=make("RefFire1",CFrame.new(p+Vector3.yAxis*2),6.5,400)
				flame:burst(1.2);flame:stream(true);stopAfter(flame,.85)
				local crown=make("RefFire9",CFrame.new(p+Vector3.yAxis*9),4,110)
				crown:stream(true);stopAfter(crown,.6)
				for i=1,5 do
					local angle=i*math.pi*2/5
					local at=p+Vector3.new(math.cos(angle)*11,1,math.sin(angle)*11)
					scope:delay(.08+i*.025,function()
						local fire=make("RefFire1",CFrame.new(at),3.2,90)
						fire:burst(.7);fire:stream(true);stopAfter(fire,.55)
					end)
				end
			end
			flash(p,2.2);ImpactFX.shake(p,if celestial then .65 else 1,.24,110)
		end
		signal=function(packet)
			if packet.event=="release" and not stopped and typeof(packet.direction)=="Vector3" then
				released=true;releasePosition=packet.position;releaseAt=packet.startedAt;direction=packet.direction
				core:rescale(base);tail:beamsOn(true);tail:stream(true)
				burst("RefImpact12",CFrame.lookAt(packet.position,packet.position+direction),if celestial then 2.3 else 2,1)
			elseif (packet.event=="hit" or packet.event=="expire") and not stopped then
				stopped=true;stopBody()
				if packet.event=="hit" and workspace:GetServerTimeNow()-packet.startedAt<.5 then impact(packet) end
				scope:delay(if orb then 2.8 else 2.2,function() scope:destroy() end)
			end
		end
		update=function(elapsed)
			if stopped then return end
			local position
			local charge=math.clamp(elapsed/T.windup,0,1)
			if released then
				local travelled=math.clamp((workspace:GetServerTimeNow()-releaseAt)*T.speed,0,T.range)
				position=releasePosition+direction*travelled
				tail:stretch(position,position-direction*math.min(travelled,if celestial then 46 else 28))
			else
				local root=character and character:FindFirstChild("HumanoidRootPart")
				local at=if root then root.Position+Vector3.yAxis*.8 else origin
				local toward=target-at;direction=if toward.Magnitude>.1 then toward.Unit else direction
				position=at+direction*5.5
				if elapsed-lastScale>.06 then core:rescale(base*(.35+.65*charge));lastScale=elapsed end
			end
			local cf=CFrame.lookAt(position,position+direction)
			core:place(cf);halo:place(cf*CFrame.Angles(0,0,elapsed*2))
			if crown then crown:place(cf*CFrame.Angles(0,0,-elapsed)) end
			light.Parent.CFrame=cf
			for i,e in ipairs(ribbons) do
				local length=if released then 38 else 9+22*charge
				-- Both ends of the authored beam share one frame: attachments keep their
				-- construction while the four ribbons bow toward the intended target.
				e:stretch(position,position+direction*(if released then -length else length))
				for _,part in ipairs(e.model:GetChildren()) do
					if part:IsA("BasePart") then part.CFrame*=CFrame.Angles(0,0,i*math.pi/2+elapsed*.6) end
				end
				for _,b in ipairs(e.beams) do b.CurveSize0=if released then 5 else 10*charge;b.CurveSize1=-b.CurveSize0 end
			end
			for i,e in ipairs(wisps) do
				local a=elapsed*3.2+i*math.pi*2/3
				e:place(cf*CFrame.new(math.cos(a)*4.2,math.sin(a)*4.2,1+math.sin(a*2)))
			end
		end
	else
		if not payload.centre then scope:destroy();return false end
		local centre,normal=payload.centre,payload.normal
		local up=if normal.Magnitude>.5 then normal.Unit else Vector3.yAxis
		local right=if math.abs(up:Dot(Vector3.xAxis))<.95 then Vector3.xAxis else Vector3.zAxis
		local back=right:Cross(up).Unit;right=up:Cross(back).Unit
		local floor=CFrame.fromMatrix(centre+up*.3,right,up,back)
		local portal=floor*CFrame.Angles(-math.pi/2,0,0)
		local vortex=payload.ability=="RiftMaelstrom"
		local rim=make("RefPortal",portal,if vortex then 2.8 else 2.65,110)
		local ground=make("RefImpact36",floor,if vortex then 7.5 else 7,30)
		local halo=make("RefLightning",floor,1.4,45)
		rim:stream(true);ground:burst(.65);halo:stream(true)
		local rings,swirls,arcs,pillars={},{},{},{}
		if vortex then
			for i=1,4 do
				rings[i]=make("RefPortal",portal,.75+i*.48,100)
				swirls[i]=make("LegendWindSwirls",floor,1.3+i*.45,65)
			end
			for i=1,3 do arcs[i]=make("RefKi2",floor,.26,25,{faceCamera=true});arcs[i]:taper(.1) end
		else
			for i=1,5 do
				local angle=i*math.pi*2/5
				local p=centre+(right*math.cos(angle)+back*math.sin(angle))*12
				local e=make("RefKi2",floor,.025,15,{faceCamera=true})
				e:stretch(p,p+up*38);e:beamsOn(true);pillars[i]=e
			end
		end
		local ended=false
		local function stop()
			ended=true;rim:stream(false);ground:stream(false);halo:stream(false)
			for _,e in ipairs(rings) do e:stream(false) end
			for _,e in ipairs(swirls) do e:stream(false) end
			for _,e in ipairs(arcs) do e:beamsOn(false) end
			for _,e in ipairs(pillars) do e:beamsOn(false) end
		end
		local function strike(packet)
			local final=packet.index==#T.strikes
			local bolt=make("RefThunder",floor,if final then 8 else 5,240,{brightness=6})
			bolt:only("Lightning"):bright(3):narrow("Lightning",if final then 27 else 19)
				:anchor("Lightning",centre+up*(if final then 24 else 17))
			bolt:burst(1.1);bolt:stream(true);stopAfter(bolt,if final then .16 else .09)
			burst("RefImpact12",portal,if final then 5.5 else 2.8,if final then 1.5 else .7)
			burst("RefImpact37",floor,if final then 3.8 else 2.2,1)
			if final then
				burst("RefImpact1",floor*CFrame.new(0,4,0),2.5,1.1)
				burst("RefImpact45",floor,2.7,.75)
				burst("LegendStylizedWind",floor,1,.65)
				burst("RefImpact36",floor,8.5,1)
				stop();flash(centre,2.8);ImpactFX.shake(centre,1.1,.28,125)
			end
		end
		signal=function(packet)
			if workspace:GetServerTimeNow()-packet.startedAt>.5 then return end
			if packet.event=="strike" then strike(packet)
			elseif packet.event=="pulse" then
				burst("RefImpact36",floor,6.5,.45)
				burst("LegendStylizedWind",floor*CFrame.new(0,3,0),.65,.35)
				burst("RefImpact45",floor*CFrame.new(0,8,0),1.6,.4)
				if packet.index==1 then flash(centre,1.1) end
			elseif packet.event=="collapse" then
				stop()
				burst("RefImpact1",floor*CFrame.new(0,5,0),3.2,1.25)
				burst("RefImpact45",floor*CFrame.new(0,8,0),3.2,1.1)
				burst("RefImpact12",portal,5.2,1.2)
				burst("RefImpact37",floor,4,1)
				burst("RefImpact36",floor,9,1)
				burst("LegendLines",floor*CFrame.new(0,6,0),3,.7)
				flash(centre,2.2);ImpactFX.shake(centre,1,.3,120)
			end
		end
		update=function(elapsed)
			if ended then return end
			halo:place(floor*CFrame.Angles(0,elapsed*2,0))
			if vortex then
				local rise=Kit.smooth((elapsed-T.windup)/.5)
				local collapse=1-.7*Kit.smooth((elapsed-(T.collapse-.3))/.3)
				for i,e in ipairs(rings) do
					local on=elapsed>=T.windup
					e:stream(on);swirls[i]:stream(on)
					local h=(i*5.5-2)*rise*collapse
					local angle=elapsed*(1.2+i*.45)
					e:place(floor*CFrame.new(math.cos(angle)*1.2,h,math.sin(angle)*1.2)*CFrame.Angles(0,angle,0)*CFrame.Angles(-math.pi/2,0,0))
					swirls[i]:place(floor*CFrame.new(0,h,0)*CFrame.Angles(0,-angle,0))
				end
				for i,e in ipairs(arcs) do
					local a=elapsed*2.6+i*math.pi*2/3
					local radial=right*math.cos(a)+back*math.sin(a)
					e:beamsOn(elapsed>=T.windup)
					e:stretch(centre+radial*4+up*2,centre-radial*15+up*25*rise*collapse)
					for _,b in ipairs(e.beams) do b.CurveSize0=18;b.CurveSize1=-12 end
				end
			end
		end
	end
	receivers[payload.id]=function(packet)
		if scope:isDead() then return end
		if packet.cancelled or packet.event=="cancel" then scope:destroy();return end
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
