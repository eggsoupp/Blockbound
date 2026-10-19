"""Small hollow MagicaVoxel chests; no external dependencies except Pillow for previews."""
from pathlib import Path
import struct, json, zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
PALETTE = [
 (125,73,35), (153,91,43), (101,55,29), (69,43,29),
 (79,88,97), (123,134,141), (220,165,65), (255,211,101),
 (69,39,106), (94,53,137), (46,27,72), (29,20,47),
 (28,198,185), (125,255,230), (41,44,53), (55,59,70),
 (29,31,39), (18,20,26), (139,148,167), (192,202,217),
 (130,57,110), (205,105,174),
]

def make(kind, opened):
    body = {}; lid = {}
    wood, light, dark, inside, metal, edge, gem, shine = {
      'basic':(1,2,3,4,5,6,7,8),
      'mythical':(9,10,11,12,7,8,13,14),
      'blackish':(15,16,17,18,19,20,21,22),
    }[kind]
    def box(target,x0,x1,y0,y1,z0,z1,c):
        for x in range(x0,x1+1):
            for y in range(y0,y1+1):
                for z in range(z0,z1+1): target[x,y,z]=c
    # Four short corner feet, hollow wooden box, and a visible inner floor.
    for x in (1,20):
        for y in (1,12): box(body,x,x+2,y,y+2,0,1,metal)
    box(body,0,23,0,15,2,2,dark)
    box(body,1,22,1,14,3,3,inside)
    for z in range(3,11):
        c = dark if z in (5,8) else (light if z in (4,7,10) else wood)
        box(body,0,23,0,0,z,z,c); box(body,0,23,15,15,z,z,c)
        box(body,0,0,1,14,z,z,c); box(body,23,23,1,14,z,z,c)
    # Reinforcing bands line up across the body and curved lid.
    for x in (3,4,19,20):
        for y in (0,15): box(body,x,x,y,y,2,10,metal)
    for y in (0,15): box(body,0,23,y,y,10,10,metal if kind!='basic' else dark)
    for x in (0,23): box(body,x,x,0,15,10,10,metal if kind!='basic' else dark)
    # Metal corner caps and rivets, kept deliberately oversized.
    for x in (0,23):
        for y in (0,15): box(body,x,x,y,y,2,4,metal)
    for x in (3,20):
        for z in (3,9): body[x,-1,z]=edge
    # Barrel cap is a shell, not a solid stack of hidden cubes.
    heights = [12,13,14,15,16,16,17,17,17,17,16,16,15,14,13,12]
    for x in range(24):
        for y,top in enumerate(heights):
            for z in range(11,top+1):
                if z==top or x in (0,23) or y in (0,15):
                    c = dark if y in (3,7,11) else (light if y%3==1 else wood)
                    if x in (3,4,19,20): c=metal
                    if kind!='basic' and x in (0,23): c=metal
                    lid[x,y,z]=c
    # Front clasp in two parts; the upper half follows the lid when opened.
    box(body,10,13,-1,-1,7,10,metal if kind=='basic' else gem)
    box(lid,10,13,-1,-1,11,12,metal)
    body[11,-2,8]=inside; body[12,-2,8]=inside
    if kind!='basic':
        # Stepped gemstone diamond and angular decorative inlay on front.
        for x,z in [(11,7),(12,7),(10,6),(11,6),(12,6),(13,6),(11,5),(12,5)]:
            body[x,-1,z]=gem
        body[11,-2,6]=shine
        for side in (1,-1):
            for i in range(4): body[11+side*(4+i),-1,6+(i%2)]=metal
        for x in range(9,15):
            for y in range(5,11):
                if abs(x-11.5)+abs(y-7.5)<=3:
                    lid[x,y,heights[y]+1]=gem
        lid[11,7,19]=shine; lid[12,8,19]=shine
    if kind=='mythical':
        # Four modest gold crown points make the silhouette distinct.
        for x in (1,22):
            for y in (3,12):
                box(lid,x,x,y,y,heights[y]+1,heights[y]+2,metal)
                lid[x,y,heights[y]+3]=edge
    # Two chunky hinges at the rear.
    for x in (5,17): box(body,x,x+1,16,16,9,11,metal)
    for (x,y,z),c in lid.items():
        p=(x,15+(z-11),11+(15-y)) if opened else (x,y,z)
        body[p]=c
    # Keep matching horizontal origins across both states.
    return {(x,y+2,z):c for (x,y,z),c in body.items()}

def chunk(name,data): return name+struct.pack('<II',len(data),0)+data
def write_vox(path,v):
    size=tuple(max(p[i] for p in v)+1 for i in range(3))
    data=chunk(b'SIZE',struct.pack('<III',*size))
    data+=chunk(b'XYZI',struct.pack('<I',len(v))+b''.join(bytes((*p,c)) for p,c in sorted(v.items())))
    colors=PALETTE+[(0,0,0)]*(256-len(PALETTE))
    data+=chunk(b'RGBA',b''.join(bytes((*c,255)) for c in colors))
    path.write_bytes(b'VOX '+struct.pack('<I',150)+b'MAIN'+struct.pack('<II',0,len(data))+data)
    # Independently read the binary structure back and validate bounds and counts.
    raw=path.read_bytes(); pos=20; parsed={}
    assert raw[:8]==b'VOX \x96\x00\x00\x00'
    while pos<len(raw):
        tag,n,children=struct.unpack_from('<4sII',raw,pos); pos+=12
        parsed[tag]=raw[pos:pos+n]; pos+=n+children
    dims=struct.unpack('<III',parsed[b'SIZE']); count=struct.unpack_from('<I',parsed[b'XYZI'])[0]
    records=list(struct.iter_unpack('BBBB',parsed[b'XYZI'][4:]))
    assert count==len(v)==len(records) and len({r[:3] for r in records})==count
    assert all(all(r[i]<dims[i] for i in range(3)) and 1<=r[3]<=len(PALETTE) for r in records)
    return {'file':path.name,'dimensions':dims,'voxel_count':count,'validated':True}

def preview(v):
    im=Image.new('RGB',(640,560),(23,27,35)); d=ImageDraw.Draw(im)
    scale=10
    def proj(p):
        x,y,z=p; return ((x+y)*.866*scale,(x-y)*.5*scale-z*scale)
    coords=[proj(p) for p in v]; minx=min(p[0] for p in coords); maxx=max(p[0] for p in coords)
    miny=min(p[1] for p in coords); maxy=max(p[1] for p in coords)
    ox=320-(minx+maxx)/2; oy=280-(miny+maxy)/2
    faces=[((1,0,0),[(1,0,0),(1,1,0),(1,1,1),(1,0,1)],.78),
           ((0,-1,0),[(0,0,0),(1,0,0),(1,0,1),(0,0,1)],.94),
           ((0,0,1),[(0,0,1),(1,0,1),(1,1,1),(0,1,1)],1.12)]
    for (x,y,z),c in sorted(v.items(),key=lambda a:a[0][0]-a[0][1]+a[0][2]):
        for normal,vertices,shade in faces:
            if (x+normal[0],y+normal[1],z+normal[2]) in v: continue
            points=[proj((x+a,y+b,z+k)) for a,b,k in vertices]
            points=[(round(a+ox),round(b+oy)) for a,b in points]
            color=tuple(min(255,round(a*shade)) for a in PALETTE[c-1])
            d.polygon(points,fill=color)
    return im

if __name__=='__main__':
    info=[]; sheet=Image.new('RGB',(1280,1830),(23,27,35)); draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype('C:/Windows/Fonts/seguisb.ttf',26)
    small=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',18)
    for row,kind in enumerate(('basic','mythical','blackish')):
        for col,opened in enumerate((False,True)):
            name=kind+('_open' if opened else '_closed'); v=make(kind,opened)
            item=write_vox(ROOT/(name+'.vox'),v); info.append(item)
            pic=preview(v); pic.save(ROOT/(name+'.png'))
            sheet.paste(pic,(col*640,row*610))
            label=kind.capitalize()+' / '+('Open' if opened else 'Closed')
            draw.text((col*640+28,row*610+553),label,font=font,fill=(231,234,240))
            draw.text((col*640+28,row*610+586),f"{len(v):,} voxels | "+' x '.join(map(str,item['dimensions'])),font=small,fill=(151,163,181))
    sheet.save(ROOT/'chest_preview.png')
    (ROOT/'validation.json').write_text(json.dumps(info,indent=2))
    (ROOT/'README.md').write_text('# Low-resolution voxel chests\n\nSix MagicaVoxel VOX v150 models, one model per file. Basic: wood and iron; mythical: purple, gold and teal; blackish: charcoal, silver and muted magenta.\n\nEach chest is 24 voxels wide. Bodies and barrel lids are hollow shells to keep voxel counts low. Open variants have a matching lid rotated 90 degrees around the rear hinge. Z is up; the front faces negative Y. A shared palette is embedded in every file.\n\nThe PNGs are orthographic previews generated directly from the voxel data. Run build_chests.py with Python and Pillow to rebuild. Binary structure, bounds, palette indices and counts are checked during generation.\n')
    with zipfile.ZipFile(ROOT/'Blockbound_Chests.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for p in ROOT.iterdir():
            if p.suffix in ('.vox','.png','.json','.md','.py'): archive.write(p,p.name)
    print(json.dumps(info,indent=2))


