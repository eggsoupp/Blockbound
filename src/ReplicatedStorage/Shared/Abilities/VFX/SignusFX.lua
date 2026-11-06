local CombatAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.CombatAudio)
-- Shared particle/beam construction. Every texture comes from the supplied packs.
local Pack=require(script.Parent.SignusParticles)
local FX={Pack=Pack}
FX.Colors={
 plum=Color3.fromRGB(34,8,59),violet=Color3.fromRGB(145,38,245),
 orchid=Color3.fromRGB(206,90,255),pearl=Color3.fromRGB(243,215,255),
 teal=Color3.fromRGB(172,103,255),gold=Color3.fromRGB(224,164,255),
 black=Color3.new(0,0,0),
}
function FX.host(scope,position,name)
 local part=scope:add(Instance.new("Part"))
 part.Name=name or "SignusParticleHost";part.Size=Vector3.one*.1;part.Transparency=1
 part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.CastShadow=false
 part.CFrame=CFrame.new(position);part.Parent=workspace
 return part
end
function FX.attachment(parent,cf)
 local a=Instance.new("Attachment");a.CFrame=cf or CFrame.identity;a.Parent=parent;return a
end
function FX.emitter(kind,parent,props)
 local data=Pack[kind]
 assert(data,"Unknown Signus particle "..kind)
 local e=Instance.new("ParticleEmitter");e.Name="Signus_"..kind
 e.Enabled=false;e.Rate=0;e.Lifetime=NumberRange.new(.5);e.Speed=NumberRange.new(0)
 e.LightEmission=.6;e.LightInfluence=0;e.Brightness=1;e.SpreadAngle=Vector2.zero
 e.Color=ColorSequence.new(FX.Colors.orchid);e.Transparency=NumberSequence.new(0,1)
 e.FlipbookLayout=data.FlipbookLayout or Enum.ParticleFlipbookLayout.None
 for k,v in pairs(data) do e[k]=v end
 e.Drag=0;e.Acceleration=Vector3.zero;e.TimeScale=1
 for k,v in pairs(props or {}) do e[k]=v end
 e.Parent=parent
 return e
end
function FX.burst(kind,parent,count,props)
 local e=FX.emitter(kind,parent,props);e:Emit(count);return e
end
local function ns(a,b) return NumberSequence.new(a,b or a) end
local function kp(t,v) return NumberSequenceKeypoint.new(t,v) end
local function merge(base,props) for k,v in pairs(props or {}) do base[k]=v end;return base end
-- Fades in, holds, fades out, so a slow stream of long particles crossfades
-- into one steady image.
FX.Hold=NumberSequence.new({kp(0,1),kp(.2,0),kp(.75,0),kp(1,1)})
-- A steady magic circle (or any flat sheet) on `parent`, whose Front is the
-- circle's normal. Copies crossfade at random turns, so a symmetric circle
-- reads as one turning slowly.
function FX.circle(parent,kind,size,color,props)
 return FX.emitter(kind,parent,merge({Enabled=true,Rate=1.7,Lifetime=NumberRange.new(1.2),Speed=NumberRange.new(.01),
  EmissionDirection=Enum.NormalId.Front,SpreadAngle=Vector2.zero,LockedToPart=true,
  Orientation=Enum.ParticleOrientation.VelocityPerpendicular,Size=ns(size),Color=ColorSequence.new(color),
  LightEmission=1,Brightness=2,Transparency=FX.Hold,Rotation=NumberRange.new(-180,180),RotSpeed=NumberRange.new(30)},props))
end
function FX.beam(parent,from,to,width,color,texture)
 local a=FX.attachment(parent,CFrame.new(from));local b=FX.attachment(parent,CFrame.new(to))
 local beam=Instance.new("Beam");beam.Name="SignusEnergy";beam.Attachment0=a;beam.Attachment1=b
 beam.Texture=texture or Pack.Beam.Texture;beam.TextureSpeed=2.5;beam.TextureLength=5
 beam.FaceCamera=true;beam.Segments=12;beam.Width0=width;beam.Width1=width*.7
 beam.LightEmission=.85;beam.LightInfluence=0;beam.Color=ColorSequence.new(color)
 beam.Transparency=NumberSequence.new(.15);beam.Parent=parent
 return beam,a,b
end
-- Verified library sources also cover persistent boss sound callers.
FX.Sounds={boom=CombatAudio.ids.boom_deep2,roar=CombatAudio.ids.electric_hum,
 blast=CombatAudio.ids.blast_short,thunder=CombatAudio.ids.lightning_close,wind=CombatAudio.ids.plasma_trail}
function FX.sound(parent,volume,pitch,id,looped)
 return CombatAudio.play(id or FX.Sounds.boom,parent,volume,pitch,looped,{throttle=if looped then 0 else .055})
end
FX.setSoundVolume=CombatAudio.setVolume
return FX

