-- Extracted from the supplied Studio VFX packs; provenance beside each template.
return {
 -- Supplied Big.Tornado-01.Main.Windspin1.
 Spiral={Texture="rbxassetid://16669803246",FlipbookLayout=Enum.ParticleFlipbookLayout.None,Rotation=NumberRange.new(-180,180),RotSpeed=NumberRange.new(250)},
 -- Supplied Anime.Wind-02.Main.Wind1.
 SpiralSmoke={Texture="rbxassetid://12685367098",FlipbookLayout=Enum.ParticleFlipbookLayout.None,Rotation=NumberRange.new(-180,180),RotSpeed=NumberRange.new(-60,60)},
 -- Supplied Fire-VFX.Fire-01.Main.Fire-02 / Big.Ball-01.Main.Fire1.
 FlameJet={Texture="rbxassetid://13818306392",FlipbookLayout=Enum.ParticleFlipbookLayout.Grid4x4,FlipbookMode=Enum.ParticleFlipbookMode.OneShot,Rotation=NumberRange.new(-180,180)},
 -- Supplied Anime.Charge-01.Main.Energy1.
 EnergyGather={Texture="rbxassetid://15041986621",FlipbookLayout=Enum.ParticleFlipbookLayout.Grid4x4,FlipbookMode=Enum.ParticleFlipbookMode.OneShot,Rotation=NumberRange.new(-180,180)},
 -- Supplied Anime.Lighting-03.Main.Lighting1.
 Electric={Texture="rbxassetid://16951505034",FlipbookLayout=Enum.ParticleFlipbookLayout.Grid2x2,FlipbookMode=Enum.ParticleFlipbookMode.OneShot,Rotation=NumberRange.new(-180,180)},
 -- Supplied Big.Tornado-01.Main.Impact1.
 GroundPulse={Texture="rbxassetid://16957275379",FlipbookLayout=Enum.ParticleFlipbookLayout.None,Rotation=NumberRange.new(-180,180)},
 -- Supplied Big.Ball-01.Main.Circle.
 CoreRing={Texture="rbxassetid://17063107542",FlipbookLayout=Enum.ParticleFlipbookLayout.None},
 -- Supplied Beams.Lava-01.Main.Beam.
 JetBeam={Texture="rbxassetid://12781828706"},
 -- Workspace.Anime.Charge-01.Main.Core1; circular alpha silhouette.
 Core = {
  Texture = "rbxassetid://1084982817",
  FlipbookLayout = Enum.ParticleFlipbookLayout.None,
  FlipbookMode = Enum.ParticleFlipbookMode.Loop,
  FlipbookFramerate = NumberRange.new(1,1),
  FlipbookStartRandom = false,
  Rotation = NumberRange.new(0,0),
  RotSpeed = NumberRange.new(0,0),
  Orientation = Enum.ParticleOrientation.FacingCamera,
  EmissionDirection = Enum.NormalId.Top,
  LightEmission = 1,
  LightInfluence = 0,
 },
 -- Workspace.Yona VFX Pack.Explosion-VFX.Blast-Explosion-03.Main.blackfire2
 DarkFire = {
  Texture = "rbxassetid://11025877566",
  FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
  FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
  FlipbookFramerate = NumberRange.new(1,1),
  FlipbookStartRandom = false,
  Rotation = NumberRange.new(-360,360),
  RotSpeed = NumberRange.new(-10,10),
  Orientation = Enum.ParticleOrientation.FacingCamera,
  EmissionDirection = Enum.NormalId.Top,
  LightEmission = 0,
  LightInfluence = 0,
 },
 -- Workspace.vfx pack.f.Attachment.crescentblack(4
 Crescent = {
  Texture = "rbxassetid://11948622097",
  FlipbookLayout = Enum.ParticleFlipbookLayout.None,
  FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
  FlipbookFramerate = NumberRange.new(1,1),
  FlipbookStartRandom = false,
  Rotation = NumberRange.new(-360,360),
  RotSpeed = NumberRange.new(-360,360),
  Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
  EmissionDirection = Enum.NormalId.Top,
  LightEmission = 0,
  LightInfluence = 0,
 },
 -- Workspace.Anime.Slashes-01.Cracks.SlashesCrack
 Crack = {
  Texture = "rbxassetid://11155927496",
  FlipbookLayout = Enum.ParticleFlipbookLayout.None,
  FlipbookMode = Enum.ParticleFlipbookMode.Loop,
  FlipbookFramerate = NumberRange.new(1,1),
  FlipbookStartRandom = false,
  Rotation = NumberRange.new(-360,360),
  RotSpeed = NumberRange.new(0,0),
  Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
  EmissionDirection = Enum.NormalId.Top,
  LightEmission = 0,
  LightInfluence = 0,
 },
 -- Workspace.Anime.Slash-01.Main.Slash1
 Slash = {
  Texture = "rbxassetid://16939611858",
  FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
  FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
  FlipbookFramerate = NumberRange.new(1,1),
  FlipbookStartRandom = false,
  Rotation = NumberRange.new(180,180),
  RotSpeed = NumberRange.new(0,0),
  Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
  EmissionDirection = Enum.NormalId.Top,
  LightEmission = 1,
  LightInfluence = 0,
 },
 -- Workspace.Model.Part.Black
 Void = {
  Texture = "rbxassetid://14457094589",
  FlipbookLayout = Enum.ParticleFlipbookLayout.None,
  FlipbookMode = Enum.ParticleFlipbookMode.Loop,
  FlipbookFramerate = NumberRange.new(1,1),
  FlipbookStartRandom = false,
  Rotation = NumberRange.new(-180,180),
  RotSpeed = NumberRange.new(100,100),
  Orientation = Enum.ParticleOrientation.FacingCamera,
  EmissionDirection = Enum.NormalId.Top,
  LightEmission = 0,
  LightInfluence = 0,
 },
 -- Workspace.Model.Part.Aura
 Aura = {
  Texture = "rbxassetid://14447188478",
  FlipbookLayout = Enum.ParticleFlipbookLayout.None,
  FlipbookMode = Enum.ParticleFlipbookMode.Loop,
  FlipbookFramerate = NumberRange.new(1,1),
  FlipbookStartRandom = false,
  Rotation = NumberRange.new(-10,10),
  RotSpeed = NumberRange.new(100,100),
  Orientation = Enum.ParticleOrientation.FacingCamera,
  EmissionDirection = Enum.NormalId.Top,
  LightEmission = 0,
  LightInfluence = 0,
 },
 -- Workspace.Model.Part.Circle
 Corona = {
  Texture = "rbxassetid://14425843511",
  FlipbookLayout = Enum.ParticleFlipbookLayout.None,
  FlipbookMode = Enum.ParticleFlipbookMode.Loop,
  FlipbookFramerate = NumberRange.new(1,1),
  FlipbookStartRandom = false,
  Rotation = NumberRange.new(0,0),
  RotSpeed = NumberRange.new(0,0),
  Orientation = Enum.ParticleOrientation.FacingCamera,
  EmissionDirection = Enum.NormalId.Top,
  LightEmission = 0,
  LightInfluence = 1,
 },
 -- Workspace.Model.Part.Black Swirl
 Swirl = {
  Texture = "rbxassetid://14477910720",
  FlipbookLayout = Enum.ParticleFlipbookLayout.None,
  FlipbookMode = Enum.ParticleFlipbookMode.Loop,
  FlipbookFramerate = NumberRange.new(1,1),
  FlipbookStartRandom = false,
  Rotation = NumberRange.new(-180,180),
  RotSpeed = NumberRange.new(360,360),
  Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
  EmissionDirection = Enum.NormalId.Top,
  LightEmission = 0,
  LightInfluence = 0,
 },
 -- Workspace.Auras.RNG-Aura-02.HumanoidRootPart.Right.Star
 Star = {
  Texture = "rbxassetid://14006783533",
  FlipbookLayout = Enum.ParticleFlipbookLayout.None,
  FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
  FlipbookFramerate = NumberRange.new(1,1),
  FlipbookStartRandom = false,
  Rotation = NumberRange.new(0,0),
  RotSpeed = NumberRange.new(0,0),
  Orientation = Enum.ParticleOrientation.FacingCamera,
  EmissionDirection = Enum.NormalId.Top,
  LightEmission = 1,
  LightInfluence = 0,
 },
 Beam = {Texture="rbxassetid://12781812529"}, -- Auras.RNG-Aura-01
 Lightning = {Texture="rbxassetid://12781800668"}, -- Auras.RNG-Aura-02
}
