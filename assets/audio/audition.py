exec(open(__file__.replace('audition.py','prepare.py')).read().split('inventory=[]')[0])
selected=json.loads((root/'selected.json').read_text())
for group in ['ui','ability','ambience']:
 clips=[];order=[]
 for i in selected:
  if not (i['key'].startswith(group) or group=='ui' and i['key'].startswith(('craft','loot'))):continue
  x,sr=sf.read(i['upload_file'],always_2d=True);x=x.mean(axis=1)
  # Audition only: resample to 16k, comparable listening level, excerpts for ambience.
  if group=='ambience':x=x[int(sr*min(3,len(x)/sr/4)):][:sr*4]
  x=np.interp(np.arange(0,len(x),sr/16000),np.arange(len(x)),x)
  x*=min(20,.7/max(float(np.max(np.abs(x))),.001))
  clips.extend([x,np.zeros(6400)]);order.append(i['key'])
 sf.write(root/(group+'_audition.wav'),np.concatenate(clips),16000)
 print(group,order)
