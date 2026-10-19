-- Shared particle/beam construction. Every texture comes from the supplied packs.
local Content=game:GetService("ContentProvider")
local Pack=require(script.Parent.SignusParticles)
local Base=require(script.Parent.CataclysmParticles)
local Starter=require(script.Parent.StarterParticles)
local FX={Pack=Pack}
FX.Colors={
 plum=Color3.fromRGB(34,8,59),violet=Color3.fromRGB(145,38,245),
 orchid=Color3.fromRGB(206,90,255),pearl=Color3.fromRGB(243,215,255),
 teal=Color3.fromRGB(172,103,255),gold=Color3.fromRGB(224,164,255),
 black=Color3.new(0,0,0),
}
local loaded=false
function FX.preload()
 if loaded then return end
 loaded=true
 task.spawn(function()
  local assets={}
  for _,library in ipairs({Pack,Base,Starter}) do
   for _,data in pairs(library) do table.insert(assets,data.Texture) end
  end
  local sound=Instance.new("Sound");sound.SoundId="rbxassetid://5540424854";table.insert(assets,sound)
  pcall(function() Content:PreloadAsync(assets,function(id,status)
   if status~=Enum.AssetFetchStatus.Success then warn("[SignusVFX] Asset unavailable: "..id) end
  end) end)
  sound:Destroy()
 end)
end
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
 local data=Pack[kind] or Base[kind] or Starter[kind]
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
function FX.beam(parent,from,to,width,color,texture)
 local a=FX.attachment(parent,CFrame.new(from));local b=FX.attachment(parent,CFrame.new(to))
 local beam=Instance.new("Beam");beam.Name="SignusEnergy";beam.Attachment0=a;beam.Attachment1=b
 beam.Texture=texture or Pack.Beam.Texture;beam.TextureSpeed=2.5;beam.TextureLength=5
 beam.FaceCamera=true;beam.Segments=12;beam.Width0=width;beam.Width1=width*.7
 beam.LightEmission=.85;beam.LightInfluence=0;beam.Color=ColorSequence.new(color)
 beam.Transparency=NumberSequence.new(.15);beam.Parent=parent
 return beam,a,b
end
function FX.sound(parent,volume,pitch)
 local sound=Instance.new("Sound");sound.SoundId="rbxassetid://5540424854"
 sound.Volume=volume;sound.PlaybackSpeed=pitch or 1;sound.RollOffMinDistance=15;sound.RollOffMaxDistance=180
 sound.Parent=parent;sound:Play()
 return sound
end
return FX

