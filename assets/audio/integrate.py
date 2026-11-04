import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
audio=ROOT/'src/ReplicatedStorage/Shared/Audio'
assets=json.loads((Path(__file__).parent/'published.json').read_text())
ids={i['name'][3:]:'rbxassetid://'+i['assetId'] for i in assets}
assert len(ids)==29
bank='-- Private group uploads: saile stone studios (275555347). See assets/audio/published.json.\nreturn {\n'+''.join(f'\t{key} = "{value}",\n' for key,value in sorted(ids.items()))+'}\n'
(audio/'DownloadedSounds.lua').write_text(bank)
p=audio/'SoundConfig.lua';s=p.read_text()
start=s.index('--[[\n');end=s.index('local SoundConfig = {}')
s='-- Sound routing for Blockbound. Imported audio is owned by saile stone studios.\n-- Legacy built-ins remain for material sounds not covered by the download.\n\n'+s[end:]
insert='''-- Curated group-owned imports. Keep the existing gameplay keys so every UI
-- consumer picks up the new assets without changing its event handlers.
local Imported = require(script.Parent:WaitForChild("DownloadedSounds"))
local imports = {
    ["ui.hover"] = {"ui_hover", .12, .05},
    ["ui.click"] = {"ui_click", .4},
    ["ui.tab"] = {"ui_tab", .25},
    ["ui.open"] = {"ui_open", .32},
    ["ui.close"] = {"ui_close", .28},
    ["ui.denied"] = {"ui_denied", .3, .12},
    ["ui.notify"] = {"ui_notify", .3},
    ["craft.success"] = {"craft_success", .4},
    ["craft.fail"] = {"ui_denied", .3},
    ["loot.pickup"] = {"loot_pickup", .3, .08},
    ["tool.swing"] = {"ability_whoosh", .2, .08},
    ["ability.sacredrain.portal"] = {"ability_portal", .45},
    ["ability.sacredrain.impact"] = {"ability_impact_heavy", .55},
    ["ability.eclipse.charge"] = {"ability_charge", .5},
    ["ability.eclipse.burst"] = {"ability_impact_heavy", .8},
    ["ability.eclipse.aftershock"] = {"ability_impact_heavy", .4},
}
for key, entry in pairs(imports) do
    SoundConfig.Sounds[key] = {id = Imported[entry[1]], volume = entry[2], throttle = entry[3],
        pitch = 1, pitchVary = .025, range = if string.sub(key, 1, 8) == "ability." then 300 else 90}
end
for key, id in pairs(Imported) do
    if string.sub(key, 1, 8) == "ability_" then
        SoundConfig.Sounds["ability." .. string.sub(key, 9)] = {id = id, volume = .45, pitch = 1, range = 180}
    end
end

'''
s=s.replace('SoundConfig.DefaultGroup = "stone"',insert+'SoundConfig.DefaultGroup = "stone"')
p.write_text(s)
# Replace selected event-specific sounds only. Water splashes retain their water source.
vfx=ROOT/'src/ReplicatedStorage/Shared/Abilities/VFX'
changed=[]
for file,mapping in {
 'AstralVFX.lua':{'SOUND_CHIME':'ability_magic_glow','SOUND_SWISH':'ability_whoosh','SOUND_BOOM':'ability_impact_heavy'},
 'BlossomVFX.lua':{'SOUND_GUST':'ability_magic_cast','SOUND_BLOOM':'ability_magic_glow','SOUND_FINALE':'ability_magic_poof'},
 'ThunderVFX.lua':{'SOUND_RUMBLE':'ability_charge','SOUND_BOOM':'ability_lightning','SOUND_HIT':'ability_impact_heavy'},
 'CometVFX.lua':{'SOUND_SWISH':'ability_whoosh','SOUND_BOOM':'ability_impact_heavy','SOUND_HIT':'ability_ice_break'},
}.items():
 p=vfx/file;s=p.read_text();s='local ImportedAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.DownloadedSounds)\n'+s
 for const,key in mapping.items():s=re.sub(r'local '+const+r' = "[^"]+"','local '+const+' = ImportedAudio.'+key,s)
 p.write_text(s);changed.append(str(p.relative_to(ROOT)))
p=vfx/'StarterVFX.lua';s=p.read_text();s='local ImportedAudio = require(game:GetService("ReplicatedStorage").Shared.Audio.DownloadedSounds)\n'+s
s=s.replace('"rbxassetid://12222208"','ImportedAudio.ability_whoosh').replace('"rbxassetid://5540424854"','ImportedAudio.ability_impact_heavy');p.write_text(s);changed.append(str(p.relative_to(ROOT)))
p=ROOT/'src/StarterPlayer/StarterPlayerScripts/DropFlight.client.lua';s=p.read_text();s=s.replace('Sounds.play("ui.click")','Sounds.play("loot.pickup")');p.write_text(s);changed.append(str(p.relative_to(ROOT)))
p=ROOT/'src/StarterPlayer/StarterPlayerScripts/SoundHandler.client.lua';s=p.read_text();s+='\nlocal Ambience = require(ReplicatedStorage.Shared.Audio:WaitForChild("Ambience"))\nAmbience.start()\n';p.write_text(s)
p=ROOT/'default.project.json';s=p.read_text();needle='          "Music": {\n            "$path": "src/ReplicatedStorage/Shared/Audio/Music.lua"\n          }';assert needle in s
s=s.replace(needle,needle+',\n          "DownloadedSounds": {\n            "$path": "src/ReplicatedStorage/Shared/Audio/DownloadedSounds.lua"\n          },\n          "Ambience": {\n            "$path": "src/ReplicatedStorage/Shared/Audio/Ambience.lua"\n          }');p.write_text(s)
changed+=['src/ReplicatedStorage/Shared/Audio/DownloadedSounds.lua','src/ReplicatedStorage/Shared/Audio/SoundConfig.lua','src/ReplicatedStorage/Shared/Audio/Ambience.lua','src/StarterPlayer/StarterPlayerScripts/SoundHandler.client.lua']
(Path(__file__).parent/'changed-files.json').write_text(json.dumps(changed,indent=2))
print('Integrated',len(ids),'assets;',len(changed),'script files')
