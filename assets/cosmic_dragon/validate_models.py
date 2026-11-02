import pathlib,struct,json,zipfile
root=pathlib.Path(__file__).parent
results=[]
for path in list(root.glob('*.vox'))+list((root/'parts').glob('*.vox')):
 b=path.read_bytes();assert b[:4]==b'VOX ';assert b[8:12]==b'MAIN'
 assert struct.unpack_from('<i',b,16)[0]==len(b)-20
 pos=20;models=0;count=0;size=None
 while pos<len(b):
  name=b[pos:pos+4];n,children=struct.unpack_from('<ii',b,pos+4);v=b[pos+12:pos+12+n]
  assert children==0 and len(v)==n
  if name==b'SIZE':size=struct.unpack('<iii',v);assert all(0<s<=256 for s in size)
  if name==b'XYZI':
   q=struct.unpack_from('<i',v)[0];assert len(v)==4+4*q
   points=[tuple(v[j:j+4]) for j in range(4,len(v),4)]
   assert len(set(p[:3] for p in points))==q
   assert all(all(p[k]<size[k] for k in range(3)) and 0<p[3]<=41 for p in points)
   count+=q;models+=1
  pos+=12+n
 assert pos==len(b)
 results.append({'file':str(path.relative_to(root)),'models':models,'voxels':count})
(root/'validation.json').write_text(json.dumps(results,indent=2))
with zipfile.ZipFile(root/'cosmic_dragon_voxel_pack.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in root.rglob('*'):
  if p.is_file() and p.suffix!='.zip':z.write(p,p.relative_to(root))
print(f'Validated {len(results)} VOX files. Packaged ZIP.')
