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
					local opacity=if name=="LegendWindSwirls" then .55 else .32
					for _,k in ipairs(e.v.Transparency.Keypoints) do table.insert(keys,NumberSequenceKeypoint.new(k.Time,1-(1-k.Value)*opacity,k.Envelope*opacity)) end
					e.v.Transparency=NumberSequence.new(keys)
				end
			end
		end
		-- Simultaneous detonations keep their full silhouettes, with less stacked glare.
		if live>=3 then
			for _,e in ipairs(effect.emitters) do
				local keys={}
				for _,k in ipairs(e.v.Transparency.Keypoints) do
					table.insert(keys,NumberSequenceKeypoint.new(k.Time,1-(1-k.Value)*.65,k.Envelope*.65))
				end
				e.v.Transparency=NumberSequence.new(keys)
			end
		end
		return effect
	end
	local function burst(name,frame,scale,strength,life)
		local effect=make(name,frame,scale,650)
		-- Scale the silhouette without firing the authored fragments far outside
		-- the hit area. Preserve the authored sequences and flipbook animation.
		for _,e in ipairs(effect.emitters) do
			e.spray=e.v.Orientation==Enum.ParticleOrientation.VelocityParallel and e.v.Speed.Max>12*scale
			e.v.Speed=NumberRange.new(e.v.Speed.Min*.38,e.v.Speed.Max*.38)
			e.v.Acceleration*=.2
			e.v.Lifetime=NumberRange.new(e.v.Lifetime.Min*(life or 1.35),e.v.Lifetime.Max*(life or 1.35))
		end
		scope:spawn(function()
			RunService.RenderStepped:Wait()
			if not scope:isDead() then
				effect:burst((strength or 1)*density)
				-- Authored streak layers need enough individual rays to describe the blast.
				-- Keep the broad glow/ring layers sparse so the centre stays readable.
				for _,e in ipairs(effect.emitters) do
					if e.spray then e.v:Emit(math.ceil(math.clamp(e.rate*.12,8,24)*(strength or 1)*density)) end
				end
			end
		end)
		return effect
	end
	local function stopAfter(effect,seconds)
		scope:delay(seconds,function() effect:stream(false);effect:beamsOn(false) end)
	end
	local function pressure(frame,scale)
		-- Complete cloud-ripple construction: a fast expanding ring and a softer wake.
		local wave=burst("LegendCloudRipples",frame,scale,.7,.26)
		for _,e in ipairs(wave.emitters) do
			e.v.Speed=NumberRange.new(e.v.Speed.Min*.22,e.v.Speed.Max*.22)
			local keys={}
			for _,k in ipairs(e.v.Transparency.Keypoints) do
				table.insert(keys,NumberSequenceKeypoint.new(k.Time,1-(1-k.Value)*.58,k.Envelope*.58))
			end
			e.v.Transparency=NumberSequence.new(keys)
		end
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
		local base=if celestial then 1.9 else 2.8
		local core=make(if celestial then "RefImpact1" else "RefFire1",frame,base*.35,if celestial then 190 else 250,{locked=true,tint=if celestial then mint else tint})
		for _,e in ipairs(core.emitters) do e.v.Speed=NumberRange.new(e.v.Speed.Min*.16,e.v.Speed.Max*.16) end
		local halo=make("RefPortal",frame,if celestial then .9 else 1,140,{locked=true})
		local corona=if celestial then make("LegendLines",frame,1.4,140,{locked=true,tint=mint}) else nil
		local crown=if orb then make("RefFire9",frame,1.8,80,{locked=true}) else nil
		local tail=make(if celestial then "LegendBlast" else "RefKi1",frame,if celestial then .42 else .13,115,{faceCamera=true})
		tail:taper(.015)
		local ribbons,wisps={},{}
		if celestial then
			for i=1,6 do
				local e=make("RefKi2",frame,.13,28,{faceCamera=true})
				e:taper(.015);e:beamsOn(true);ribbons[i]=e
			end
		else
			for i=1,3 do
				wisps[i]=make("RefFire1",frame,.7,65,{locked=true})
				wisps[i]:stream(true)
			end
		end
		core:stream(true);halo:stream(true)
		if corona then corona:stream(true) end
		if crown then crown:stream(true) end
		local released,stopped,releasePosition,releaseAt,lastScale=false,false,origin,0,-1
		local light=Kit.light(Kit.host(folder,"CoreLight",frame),tint.main,22);light.Brightness=.8
		local function stopBody()
			core:clear();halo:clear();tail:clear();light.Enabled=false
			if corona then corona:clear() end
			if crown then crown:clear() end
			for _,e in ipairs(ribbons) do e:clear() end
			for _,e in ipairs(wisps) do e:clear() end
		end
		local function impact(packet)
			local p,n=packet.position,packet.normal or -direction
			-- Impact12 emits along local Back, so its +Z axis faces off the surface.
			local cf=CFrame.lookAt(p+n*.3,p-n*2)
			local surface=cf*CFrame.Angles(math.pi/2,0,0)
			if celestial then
				burst("RefImpact12",cf,6.5,1.65)
				burst("RefImpact37",surface,4.4,1.25)
				burst("LegendLines",surface,4.2,1.6)
				local globe=make("RefImpact1",cf,4.2,320,{locked=true,tint=mint})
				globe:burst(.85);globe:stream(true);stopAfter(globe,.22)
				local rings=make("RefPortal",cf,2.8,145)
				rings:burst(.9);rings:stream(true);stopAfter(rings,.45)
				local lance=make("LegendBlast",cf,.95,130,{faceCamera=true})
				lance:stretch(p,p-direction*math.min((p-releasePosition).Magnitude,64))
				lance:beamsOn(true);lance:burst(.6);stopAfter(lance,.22)
				for i=1,6 do
					local a=i*math.pi/3
					local radial=surface.RightVector*math.cos(a)+surface.ZVector*math.sin(a)
					local ray=make("RefKi2",cf,.16,18,{faceCamera=true})
					ray:taper(.01);ray:stretch(p+n*2,p+radial*27+n*5);ray:beamsOn(true)
					stopAfter(ray,.2)
				end
				scope:delay(.1,function() pressure(surface,6);burst("RefImpact45",surface,3.6,1.2) end)
				scope:delay(.28,function()
					burst("RefImpact12",cf,8,.65);burst("LegendLines",surface,3.2,1)
				end)
			else
				burst("RefImpact41",cf,5.2,1.6)
				burst("RefImpact45",surface,3.8,1.3)
				burst("RefImpact36",surface,8.5,1)
				burst("RefImpact1",CFrame.new(p+Vector3.yAxis*4),3.2,1.2)
				burst("LegendLines",surface,3.5,1.2)
				scope:delay(.12,function() pressure(surface,6.5) end)
				scope:delay(.32,function() burst("RefImpact41",cf,3.7,.8);burst("RefImpact36",surface,11,.65) end)
				local flame=make("RefFire1",CFrame.new(p+Vector3.yAxis*2),6.5,400)
				flame:burst(1.2);flame:stream(true);stopAfter(flame,.85)
				local crown=make("RefFire9",CFrame.new(p+Vector3.yAxis*9),4,110)
				crown:stream(true);stopAfter(crown,.6)
				for i=1,7 do
					local angle=i*math.pi*2/7
					local at=p+Vector3.new(math.cos(angle)*14,1,math.sin(angle)*14)
					scope:delay(.08+i*.025,function()
						local fire=make("RefFire1",CFrame.new(at),3.2,90)
						fire:burst(.7);fire:stream(true);stopAfter(fire,.55)
					end)
				end
			end
			flash(p,2.8);ImpactFX.shake(p,if celestial then .9 else 1.1,.3,125)
		end
		signal=function(packet)
			if packet.event=="release" and not stopped and typeof(packet.direction)=="Vector3" then
				released=true;releasePosition=packet.position;releaseAt=packet.startedAt;direction=packet.direction
				core:rescale(base);tail:beamsOn(true);tail:stream(true)
				local muzzle=CFrame.lookAt(packet.position,packet.position+direction)
				burst("RefImpact12",muzzle,if celestial then 3.3 else 2.5,1.2)
				burst("LegendLines",muzzle*CFrame.Angles(-math.pi/2,0,0),if celestial then 2.2 else 1.6,1)
			elseif (packet.event=="hit" or packet.event=="expire") and not stopped then
				stopped=true;stopBody()
				if packet.event=="hit" and workspace:GetServerTimeNow()-packet.startedAt<.5 then impact(packet) end
				scope:delay(2.8,function() scope:destroy() end)
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
			if corona then corona:place(cf) end
			if crown then crown:place(cf*CFrame.Angles(0,0,-elapsed)) end
			light.Parent.CFrame=cf
			for i,e in ipairs(ribbons) do
				local length=if released then 48 else 11+27*charge
				-- Both ends of the authored beam share one frame: attachments keep their
				-- construction while the four ribbons bow toward the intended target.
				e:stretch(position,position+direction*(if released then -length else length))
				for _,part in ipairs(e.model:GetChildren()) do
					if part:IsA("BasePart") then part.CFrame*=CFrame.Angles(0,0,i*math.pi/3+elapsed*.6) end
				end
				for _,b in ipairs(e.beams) do b.CurveSize0=if released then 7 else 13*charge;b.CurveSize1=-b.CurveSize0 end
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
		local rim=make("RefPortal",portal,if vortex then 3.35 else 3.15,155)
		local ground=make("RefImpact36",floor,if vortex then 9 else 8.5,45)
		local halo=make("RefLightning",floor,1.9,85)
		rim:stream(true);ground:burst(.65);halo:stream(true)
		burst("LegendLines",floor,2.7,.8)
		local rings,swirls,arcs,pillars,turbulence={},{},{},{},{}
		if vortex then
			for i=1,6 do
				rings[i]=make("RefPortal",portal,.85+i*.44,120)
				swirls[i]=make("LegendWindSwirls",floor,1.4+i*.36,85)
				for _,e in ipairs(swirls[i].emitters) do e.v.Speed=NumberRange.new(e.v.Speed.Min*.3,e.v.Speed.Max*.3) end
			end
			for i=1,5 do arcs[i]=make("RefKi2",floor,.32,30,{faceCamera=true});arcs[i]:taper(.06) end
			for i=1,2 do
				local e=make("RefImpact45",floor,if i==1 then 2.7 else 2.3,210,{tint={deep=indigo.deep,main=indigo.main,hot=indigo.main:Lerp(indigo.hot,.35)}})
				for _,layer in ipairs(e.emitters) do
					layer.v.Speed=NumberRange.new(layer.v.Speed.Min*.22,layer.v.Speed.Max*.22)
					layer.v.Acceleration*=.15
				end
				turbulence[i]=e
			end
		else
			for i=1,5 do
				local angle=i*math.pi*2/5
				local p=centre+(right*math.cos(angle)+back*math.sin(angle))*12
				local e=make("RefKi2",floor,.045,20,{faceCamera=true})
				e:stretch(p,p+up*48);e:beamsOn(true);pillars[i]=e
				scope:delay(.12+i*.065,function() burst("RefImpact37",CFrame.new(p),1.2,.6,.7) end)
			end
			local whirl=make("LegendWindSwirls",floor*CFrame.new(0,5,0),2.8,140)
			whirl:stream(true);table.insert(swirls,whirl)
		end
		local ended=false
		local function stop()
			ended=true;rim:stream(false);ground:stream(false);halo:stream(false)
			for _,e in ipairs(rings) do e:stream(false) end
			for _,e in ipairs(swirls) do e:stream(false) end
			for _,e in ipairs(arcs) do e:beamsOn(false) end
			for _,e in ipairs(pillars) do e:beamsOn(false) end
			for _,e in ipairs(turbulence) do e:stream(false) end
		end
		local function strike(packet)
			local final=packet.index==#T.strikes
			local bolt=make("RefThunder",floor,if final then 10 else 6.3,320,{brightness=6})
			bolt:only("Lightning"):bright(3):narrow("Lightning",if final then 34 else 23)
				:anchor("Lightning",centre+up*(if final then 31 else 21))
			bolt:burst(1.3);bolt:stream(true);stopAfter(bolt,if final then .22 else .11)
			burst("RefImpact12",portal,if final then 7.2 else 3.8,if final then 1.7 else .9)
			burst("RefImpact37",floor,if final then 5 else 2.8,1.2)
			if final then
				burst("RefImpact1",floor*CFrame.new(0,5,0),3.8,1.3)
				local branches=make("RefLightning",floor*CFrame.new(0,5,0),2.4,110)
				branches:burst(1);branches:stream(true);stopAfter(branches,.22)
				burst("RefImpact45",floor,4.2,1.4)
				burst("LegendStylizedWind",floor,1.3,.8)
				burst("RefImpact36",floor,10.5,1.1)
				burst("LegendLines",floor,4.5,1.5)
				for i=1,5 do
					local a=i*math.pi*2/5
					local at=centre+(right*math.cos(a)+back*math.sin(a))*16
					scope:delay(.04+i*.022,function()
						local fork=make("RefThunder",CFrame.new(at),4.5,95,{brightness=5})
						fork:only("Lightning"):bright(3):narrow("Lightning",7):anchor("Lightning",at+up*17)
						fork:stream(true);stopAfter(fork,.13)
						burst("RefImpact37",CFrame.new(at),1.8,.65)
					end)
				end
				scope:delay(.12,function() pressure(floor,7) end)
				scope:delay(.34,function() burst("RefImpact12",portal,9,.7);burst("LegendLines",floor,3.6,1) end)
				stop();flash(centre,3.1);ImpactFX.shake(centre,1.25,.32,135)
			end
		end
		signal=function(packet)
			if workspace:GetServerTimeNow()-packet.startedAt>.5 then return end
			if packet.event=="strike" then strike(packet)
			elseif packet.event=="pulse" then
				burst("RefImpact36",floor,8,.65)
				burst("LegendStylizedWind",floor*CFrame.new(0,5,0),.95,.55)
				burst("RefImpact45",floor*CFrame.new(0,13,0),2.3,.75)
				burst("LegendLines",floor*CFrame.new(0,10,0),2.4,.9)
				if packet.index==1 or packet.index==3 then pressure(floor,5) end
				if packet.index==1 then flash(centre,1.1) end
			elseif packet.event=="collapse" then
				stop()
				burst("RefImpact1",floor*CFrame.new(0,8,0),4.8,1.5)
				local shell=make("RefPortal",portal+up*8,3.7,150)
				shell:burst(.9);shell:stream(true);stopAfter(shell,.2)
				burst("RefImpact45",floor*CFrame.new(0,12,0),4.8,1.5)
				burst("RefImpact12",portal,7,1.6)
				burst("RefImpact37",floor,5.5,1.3)
				burst("RefImpact36",floor,11,1.2)
				burst("LegendLines",floor*CFrame.new(0,8,0),4.8,1.5)
				scope:delay(.1,function() pressure(floor,7.5);burst("LegendStylizedWind",floor,1.5,.9) end)
				scope:delay(.3,function()
					burst("RefImpact12",portal,9,.8)
					burst("RefImpact45",floor*CFrame.new(0,5,0),3.2,.8)
				end)
				flash(centre,3);ImpactFX.shake(centre,1.2,.35,135)
			end
		end
		update=function(elapsed)
			if ended then return end
			halo:place(floor*CFrame.Angles(0,elapsed*2,0))
			if vortex then
				local rise=Kit.smooth((elapsed-T.windup)/.5)
				local collapse=1-.7*Kit.smooth((elapsed-(T.collapse-.3))/.3)
				for i,e in ipairs(turbulence) do
					e:stream(elapsed>=T.windup)
					e:place(floor*CFrame.new(0,(i*12-6)*rise*collapse,0)*CFrame.Angles(0,-elapsed*(2+i),0))
				end
				for i,e in ipairs(rings) do
					local on=elapsed>=T.windup
					e:stream(on);swirls[i]:stream(on)
					local h=(i*5.8-2)*rise*collapse
					local angle=elapsed*(1.2+i*.45)
					e:place(floor*CFrame.new(math.cos(angle)*1.2,h,math.sin(angle)*1.2)*CFrame.Angles(0,angle,0)*CFrame.Angles(-math.pi/2,0,0))
					swirls[i]:place(floor*CFrame.new(0,h,0)*CFrame.Angles(0,-angle,0))
				end
				for i,e in ipairs(arcs) do
					local a=elapsed*2.6+i*math.pi*2/5
					local radial=right*math.cos(a)+back*math.sin(a)
					e:beamsOn(elapsed>=T.windup)
					e:stretch(centre+radial*5+up*2,centre-radial*19+up*36*rise*collapse)
					for _,b in ipairs(e.beams) do b.CurveSize0=24;b.CurveSize1=-16 end
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
