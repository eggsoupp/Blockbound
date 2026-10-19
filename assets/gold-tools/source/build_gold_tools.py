"""Build three solid MagicaVoxel props from the supplied visual references.
Run: python source/build_gold_tools.py  (requires numpy and Pillow).
"""
from pathlib import Path
import json
import zipfile
import numpy as np
from PIL import Image, ImageDraw
import geometry_io as io

ROOT = Path(__file__).resolve().parents[1]
PALETTE = [
    ('Burgundy outline', '#46051f'), ('Umber deep', '#46250d'),
    ('Umber', '#713b15'), ('Burnished red', '#9c4229'),
    ('Copper', '#af5510'), ('Gold shadow', '#956b09'),
    ('Gold ochre', '#cf7c0b'), ('Gold amber', '#e39c0d'),
    ('Gold', '#f5bf22'), ('Gold bright', '#ffe32b'),
    ('Gold light', '#fff35b'), ('Gold glint', '#fff2ab'),
    ('Leather dark', '#54251c'), ('Leather', '#80351e'),
    ('Leather light', '#aa522a'), ('Amethyst shadow', '#67116e'),
    ('Amethyst', '#af13c7'), ('Amethyst light', '#e46ef3'),
    ('Steel shadow', '#303744'), ('Steel', '#586474'),
    ('Steel light', '#8c9cac'), ('Steel glint', '#c3d0d5'),
    ('Old gold shadow', '#6d590e'), ('Old gold', '#a18b24'),
]
RGB = np.array([tuple(bytes.fromhex(h[1:])) for _, h in PALETTE], np.uint8)
io.RGB = RGB

# Construction coordinates: handle at X=0, Y=0; +Z points to the head.
OX, OY = 40, 8
SHAPE = (81, 17, 76)

def put(a, x, y, z, c):
    a[x + OX, y + OY, z] = c

def mask(poly):
    im = Image.new('1', (SHAPE[0], SHAPE[2]))
    ImageDraw.Draw(im).polygon([(x + OX, z) for x,z in poly], fill=1)
    return np.asarray(im, dtype=bool).T.copy()

def boundary_distance(m):
    d = np.zeros(m.shape, np.uint8)
    cur = m.copy()
    while cur.any():
        d[cur] += 1
        p = np.pad(cur, 1)
        cur = cur & p[:-2,1:-1] & p[2:,1:-1] & p[1:-1,:-2] & p[1:-1,2:]
    return d

def plate(a, poly, depth, color):
    m = mask(poly)
    d = boundary_distance(m)
    for ix,z in np.argwhere(m):
        x = int(ix) - OX
        edge = int(d[ix,z])
        thick = min(depth, edge)
        for y in range(-thick, thick+1):
            put(a, x,y,int(z),color(x,y,int(z),edge,thick))

def box(a, xmin,xmax, ymin,ymax, zmin,zmax, color):
    for x in range(xmin,xmax+1):
        for y in range(ymin,ymax+1):
            for z in range(zmin,zmax+1):
                put(a,x,y,z,color(x,y,z) if callable(color) else color)

def shaft(a, top, kind):
    for z in range(top+1):
        w = 3 if kind == 'axe' else 2
        for x in range(-w,w+1):
            for y in range(-3,4):
                if abs(x)==w and abs(y)==3:
                    continue
                if kind == 'axe':
                    c = 4 if x > 0 else 7 if x < -1 else 5
                    # The reference has a gold-inlaid handle with warm red facets.
                    if z % 12 in (6,7,8):
                        c = 8 if abs(y) >= 2 else 5
                else:
                    c = 2 if abs(x)==w else 3
                    if abs(y)==3:
                        c = 5 if x <= 0 else 3
                    if z % 9 == 0:
                        c = 2
                put(a,x,y,z,c)
    # Solid gold pommel with dark bevels, matching both tool references.
    plate(a,[(-4,0),(4,0),(5,2),(5,5),(3,7),(-3,7),(-5,5),(-5,2)],4,
          lambda x,y,z,e,t: 1 if e==1 else 10 if x<0 and abs(y)==t else 8)

def trim(a):
    q=np.argwhere(a)
    lo=q.min(0); hi=q.max(0)+1
    return a[tuple(slice(int(l),int(h)) for l,h in zip(lo,hi))].copy(), [int(OX-lo[0]),int(OY-lo[1]),10-int(lo[2])]

def axe():
    a=np.zeros(SHAPE,np.uint8)
    shaft(a,60,'axe')
    # Short rear spur, stepped and hooked like the reference.
    plate(a,[(-4,54),(-11,58),(-18,57),(-19,52),(-16,48),(-13,50),(-8,48),(-4,45)],3,
          lambda x,y,z,e,t: 1 if e==1 else 8 if z>52 else 4 if x<-12 else 7)
    # Broad forward blade. The outer right edge is thin; its center is thick.
    poly=[(-3,56),(-2,63),(4,67),(17,67),(25,64),(30,58),(33,49),
          (33,40),(30,35),(27,37),(25,43),(18,44),(10,48),(4,49),(-3,47)]
    def gold(x,y,z,e,t):
        if e==1:
            return 10 if x>=29 else 8 if z>=65 else 1
        if x>=28 or (z>=64 and x>=5):
            return 11 if e<=3 else 10
        if x>=25:
            return 9
        if e==2:
            return 5 if x<8 else 7
        if (x//6+z//6)%5==0:
            return 8
        return 8 if x<=12 else 7 if z<55 else 9
    plate(a,poly,4,gold)
    # Reinforced eye, gold collar and inset purple jewel on both sides.
    box(a,-4,4,-4,4,48,58,lambda x,y,z: 1 if abs(x)==4 else 4 if abs(y)==4 else 5)
    box(a,-4,4,-4,4,48,49,8)
    box(a,-4,4,-4,4,57,58,8)
    for sign in (-1,1):
        box(a,-3,3,sign*5,sign*5,50,56,7)
        box(a,-2,2,sign*6,sign*6,51,55,16)
        box(a,-1,1,sign*7,sign*7,52,54,17)
        put(a,-1,sign*7,54,18)
    return trim(a)

def pickaxe():
    a=np.zeros(SHAPE,np.uint8)
    shaft(a,59,'pickaxe')
    # Asymmetric crescent head: a long left beak and a hooked right tine.
    poly=[(-27,57),(-26,62),(-20,65),(-10,65),(-5,63),(5,63),(14,61),
          (20,57),(24,50),(27,39),(26,35),(23,36),(21,43),(18,50),
          (12,55),(4,57),(-5,58),(-13,60),(-21,60)]
    def gold(x,y,z,e,t):
        if e==1:
            return 1 if (z<59 and x<16) else 5
        if x<-17:
            return 11 if z<=61 else 8
        if x>=21:
            return 11 if z<41 else 10 if x>23 else 8
        if e==2:
            return 7
        return 10 if z>=61 else 9 if x<5 else 8
    plate(a,poly,3,gold)
    box(a,-4,4,-4,4,55,64,lambda x,y,z: 2 if abs(x)==4 or z==64 else 3)
    box(a,-3,3,-4,4,55,56,8)
    for sign in (-1,1):
        box(a,-2,2,sign*5,sign*5,58,62,5)
        box(a,-1,1,sign*5,sign*5,59,61,8)
    return trim(a)

def sword():
    a=np.zeros(SHAPE,np.uint8)
    # Dark hilt, faceted pommel, raised steel collars.
    for z in range(0,20):
        w=3 if z<5 else 2
        for x in range(-w,w+1):
            for y in range(-3,4):
                if abs(x)==w and abs(y)==3:
                    continue
                c=19 if z<5 or z>16 else 13
                if z<4 and abs(y)>=2: c=20 if x>=0 else 21
                if 5<=z<=16 and z%4==1: c=20
                put(a,x,y,z,c)
    # Thin edges and a raised central ridge make a diamond blade section.
    poly=[(-3,19),(-5,23),(-5,53),(-4,58),(-2,63),(0,67),(2,63),(4,58),(5,53),(5,23),(3,19)]
    def gold(x,y,z,e,t):
        if e==1: return 11 if x<0 else 23
        if e==2: return 10 if x<0 else 24
        if x<=-2: return 10 if z<57 else 11
        if x<=0: return 9 if abs(y)>=t else 7
        return 6 if x>2 else 8
    plate(a,poly,3,gold)
    # Swept steel quillons retain the cool gray hilt of the sword reference.
    plate(a,[(-12,16),(-11,20),(-9,22),(-5,21),(-2,20),(2,20),(5,21),
             (9,22),(11,20),(12,16),(10,15),(7,18),(3,17),(-3,17),(-7,18),(-10,15)],3,
          lambda x,y,z,e,t: 19 if e==1 else 21 if z>=19 and x<3 else 20)
    box(a,-3,3,-4,4,18,22,lambda x,y,z: 20 if abs(x)==3 else 21)
    for sign in (-1,1):
        box(a,-1,1,sign*5,sign*5,19,21,11)
    return trim(a)

def previews(models):
    pre=ROOT/'previews'; pre.mkdir(exist_ok=True)
    sheet=Image.new('RGB',(1600,1060),'#191d27'); d=ImageDraw.Draw(sheet)
    d.text((50,30),'GOLD TOOLSET',font=io.font(36,True),fill='#fff0b1')
    d.text((52,82),'AXE  /  PICKAXE  /  SWORD     -     One shared 24-color palette',font=io.font(20),fill='#aeb5c6')
    for i,(name,a) in enumerate(models.items()):
        hero=io.render(a,(740,840),az=-70,el=12,roll=0,scale=10)
        hero.save(pre/f'{name}_transparent.png')
        tile=io.render(a,(510,715),az=-70,el=12,roll=0,scale=8.5)
        sheet.paste(tile,(20+525*i,135),tile)
        d.text((55+525*i,136),name.replace('_',' ').upper(),font=io.font(22,True),fill='#f3df9c')
        d.text((55+525*i,850),' x '.join(map(str,a.shape))+' voxels',font=io.font(18),fill='#aeb5c6')
        # Front and back are rendered independently from the exported geometry.
        views=Image.new('RGB',(1500,930),'#191d27'); vd=ImageDraw.Draw(views)
        vd.text((40,22),name.replace('_',' ').upper(),font=io.font(30,True),fill='#fff0b1')
        for j,(label,az,el) in enumerate([('FRONT',-90,0),('BACK',90,0),('DEPTH',-38,14)]):
            projected_width=abs(np.sin(np.radians(az)))*a.shape[0]+abs(np.cos(np.radians(az)))*a.shape[1]
            v=io.render(a,(490,790),az=az,el=el,scale=min(9.5,450/projected_width))
            views.paste(v,(j*500,95),v)
            vd.text((40+j*500,80),label,font=io.font(17),fill='#aeb5c6')
        views.save(pre/f'{name}_views.png')
    for i,(_,h) in enumerate(PALETTE):
        x=52+i*62
        d.rectangle((x,925,x+51,969),fill=h)
        d.text((x,977),str(i+1).zfill(2),font=io.font(13),fill='#aeb5c6')
    d.text((52,1020),'Actual VOX geometry  |  Upright +Z  |  Sculpted bevels and raised fittings',font=io.font(17),fill='#aeb5c6')
    sheet.save(pre/'gold_toolset.png')

def main():
    ROOT.mkdir(exist_ok=True)
    models={}; reports=[]
    for name,fn in [('gold_axe',axe),('gold_pickaxe',pickaxe),('gold_sword',sword)]:
        a,grip=fn()
        p=ROOT/f'{name}.vox'
        io.export_vox(p,a)
        restored,report=io.validate(p,a)
        report['grip_center_xyz']=grip
        models[name]=restored; reports.append(report)
    assert len({r['rgba_sha256'] for r in reports})==1
    (ROOT/'validation.json').write_text(json.dumps(reports,indent=2)+'\n')
    previews(models)
    (ROOT/'shared_palette.json').write_text(json.dumps({'name':'Blockbound Gold Tools',
        'indexing':'0 = empty; palette entry 1 maps to VOX index 1',
        'colors':[{'index':i+1,'name':n,'hex':h} for i,(n,h) in enumerate(PALETTE)]},indent=2)+'\n')
    gpl=['GIMP Palette','Name: Blockbound Gold Tools','Columns: 8','#']
    for i,((name,_),c) in enumerate(zip(PALETTE,RGB)):
        gpl.append(f'{c[0]:3} {c[1]:3} {c[2]:3}\t{i+1:02} {name}')
    (ROOT/'shared_palette.gpl').write_text('\n'.join(gpl)+'\n')
    sw=Image.new('RGB',(768,64)); sd=ImageDraw.Draw(sw)
    for i,(_,h) in enumerate(PALETTE): sd.rectangle((i*32,0,i*32+31,63),fill=h)
    sw.save(ROOT/'shared_palette.png')
    lines=['# Gold toolset','', 'Three solid voxel props based on the supplied axe, pickaxe, and sword references.',
        'All three embed a byte-identical 24-color palette with stable indices. The palette includes warm gold, burgundy, brown, amethyst, and cool steel.',
        '', '| File | Grid X x Y x Z | Grip center X,Y,Z |','|---|---|---|']
    for r in reports: lines.append(f"| {r['file']} | {' x '.join(map(str,r['dimensions_xyz']))} | {r['grip_center_xyz']} |")
    lines += ['', 'MagicaVoxel VOX version 150, one model per file. +Z points toward the head/tip; X runs across the head; Y is thickness. Models are upright for attachment and editing. Set game/world scale in the importer.',
        '', 'The axe retains its broad gold blade, short rear spur, red/gold shaft, and raised purple eye. The pickaxe has a brown handle, gold pommel, and asymmetric curved gold head. The sword has a gold blade with a sculpted central ridge and a cool steel guard/hilt.',
        '', 'previews/ contains renders of the exported geometry, including front/back/depth views. shared_palette.json, .gpl, and .png provide the common palette. validation.json records binary round-trip, bounds, palette, uniqueness, and 6-neighbor connectivity checks.',
        '', 'Rebuild with Python 3, NumPy, and Pillow: python source/build_gold_tools.py. Source files are self-contained. No background, display stand, or reference-image UI is included in the models.']
    (ROOT/'README.md').write_text('\n'.join(lines)+'\n')
    with zipfile.ZipFile(ROOT/'gold_toolset.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(ROOT.rglob('*')):
            if p.is_file() and p.suffix!='.zip' and '__pycache__' not in p.parts: z.write(p,p.relative_to(ROOT))
    print(json.dumps(reports,indent=2))

if __name__=='__main__': main()
