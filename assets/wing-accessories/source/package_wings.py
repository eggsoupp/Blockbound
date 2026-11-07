"""Package the verified authoring assets, omitting caches and previous archives."""
from pathlib import Path
import hashlib, json, re, xml.etree.ElementTree as ET, zipfile

root=Path(__file__).resolve().parents[1]
repo=root.parents[1]
defs=repo/'src/ReplicatedStorage/ItemDefinitions.lua'
text=defs.read_text(encoding='utf8')
items=[]
for m in re.finditer(r'ItemDefinitions\.(\w+Wings) = \{',text):
    block=text[m.start():text.find('\n}',m.start())+2]
    items.append({'id':m[1],'line':text[:m.start()].count('\n')+1,
                  'description':re.search(r'description = "([^"]+)"',block)[1]})
place=ET.parse(repo/'blockbound.rbxlx').getroot()
matches=[]
for item in place.iter('Item'):
    name=item.findtext('./Properties/string[@name="Name"]') or ''
    if 'wing' in name.lower():matches.append({'name':name,'class':item.attrib.get('class')})
(root/'source-review.json').write_text(json.dumps({'item_source':str(defs.relative_to(repo)),
    'items':items,'place':'blockbound.rbxlx','place_instances_with_wing_in_name':matches,
    'reference_policy':'No UI sprites/images used. Original models from item names and descriptions.',
    'native_inspection':'AngelWings and the complete seven-set AllWings scene loaded in MagicaVoxel 0.99.7.2.'},indent=2))
validation=json.loads((root/'validation.json').read_text());assert validation['status']=='passed'
entries=[]
for p in sorted(root.rglob('*')):
    if not p.is_file() or p.suffix=='.zip' or '__pycache__' in p.parts or p.name=='SHA256SUMS.txt':continue
    entries.append((p,hashlib.sha256(p.read_bytes()).hexdigest()))
(root/'SHA256SUMS.txt').write_text('\n'.join(f'{h}  {p.relative_to(root).as_posix()}' for p,h in entries)+'\n')
archive=root/'Blockbound_Wing_Accessories.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p,_ in entries:z.write(p,Path('Blockbound_Wing_Accessories')/p.relative_to(root))
    z.write(root/'SHA256SUMS.txt','Blockbound_Wing_Accessories/SHA256SUMS.txt')
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'files':len(entries)+1,'wing_items':len(items),'place_wing_instances':matches},indent=2))
