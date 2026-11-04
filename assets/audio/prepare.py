import sys,json,hashlib,math
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'.music-tools'))
import soundfile as sf
import numpy as np
root=Path(__file__).parent
# Source IDs identify downloads only; new group-owned IDs are recorded after upload.
selection={
'ui_hover':'10066936758','ui_click':'88442833509532','ui_tab':'10128760939',
'ui_open':'127877437691780','ui_close':'6698737249','ui_denied':'1388726556',
'ui_notify':'6044781309','craft_success':'3785105076','loot_pickup':'4612375802',
'ability_charge':'113313795928049','ability_magic_cast':'182765513','ability_magic_glow':'9116395085',
'ability_lightning':'9116278972','ability_shield_on':'814168787','ability_shield_off':'814169516',
'ability_portal':'4604281976','ability_impact_heavy':'74149238738530',
'ability_ice_break':'113464341514942',
'ability_magic_poof':'9116406375','ability_whoosh':'9120742716',
'ambience_rain_light':'7127218501','ambience_rain_heavy':'16665524404',
'ambience_wind':'9113286969','ambience_night':'179507208',
'ambience_sea':'898059911','ambience_snow':'336392497',
'ambience_fire':'9082326368','ambience_waterfall':'9120549564','ambience_thunderstorm':'85853358822578',
}
out=root/'publish';out.mkdir(exist_ok=True)
inventory=[]
for p in (root/'downloaded').rglob('*.ogg'):
 try:
  x,sr=sf.read(p,always_2d=True); peak=float(np.max(np.abs(x))); rms=float(np.sqrt(np.mean(x*x)))
  item=dict(source=str(p.relative_to(root)),duration=round(len(x)/sr,4),rate=sr,channels=x.shape[1],peak=round(peak,5),rms_db=round(20*math.log10(max(rms,1e-10)),2),clipping_fraction=round(float(np.mean(np.abs(x)>=.999)),5),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),status='not_selected')
  for key,ident in selection.items():
   if p.stem.endswith('_'+ident):
    item.update(key=key,source_id=ident,status='prepared_not_uploaded')
    # Preserve full ambient loops; normalize only downward to leave headroom.
    target_db=-26 if key.startswith('ambience') else -22
    gain=min(10,10**(target_db/20)/max(rms,1e-10),.89/max(peak,1e-10));x=x*gain
    dest=out/('BB_'+key+'.flac');sf.write(dest,x,sr,format='FLAC',subtype='PCM_16')
    item.update(upload_file=str(dest.resolve()),gain_db=round(20*math.log10(gain),2))
  inventory.append(item)
 except Exception as e: inventory.append(dict(source=str(p),status='decode_failed',error=str(e)))
(root/'inventory.json').write_text(json.dumps(inventory,indent=2))
selected=[i for i in inventory if 'key' in i]
(root/'selected.json').write_text(json.dumps(selected,indent=2))
for i in selected:print(i['key'],i['duration'],i['rms_db'],i['clipping_fraction'])
print('Decoded',len(inventory),'files; selected',len(selected))
