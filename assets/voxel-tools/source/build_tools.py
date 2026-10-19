"""Reference-directed Blockbound tools. Python + NumPy + Pillow; no external assets.
Solid voxel sculpting, VOX 150 export, independent readback and geometry previews.
"""
from pathlib import Path
from collections import deque
import struct, json, hashlib, zipfile, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SHAPE = (32, 8, 40)
X,Y,Z = np.indices(SHAPE, dtype=float)
X += .5; X -= 16
Y += .5; Y -= 4
Z += .5
PALETTE = [
    ('Iron deep', '#353635'), ('Iron shadow', '#4c4e4c'),
    ('Steel dark', '#626561'), ('Steel body', '#81847f'),
    ('Steel light', '#9b9f98'), ('Honed edge', '#b9bdb5'),
    ('Edge glint', '#d5d8cd'), ('Steel wear', '#71756f'),
    ('Wood deep', '#503019'), ('Wood shadow', '#754521'),
    ('Wood warm', '#9d632d'), ('Wood body', '#b58445'),
    ('Wood light', '#c99a58'), ('End grain', '#d5ae6b'),
    ('Leather deep', '#3b2417'), ('Leather shadow', '#623a20'),
    ('Leather body', '#885026'), ('Leather edge', '#ac7036'),
    ('Brass dark', '#78602b'), ('Brass body', '#a28740'),
    ('Brass light', '#c3a657'), ('Recess', '#282a27'),
]
RGB = np.array([tuple(bytes.fromhex(h[1:])) for _,h in PALETTE],dtype=np.uint8)

def blank(): return np.zeros(SHAPE,np.uint8)

def polygon_field(points):
    """Inside test and Euclidean distance to the perimeter in the X/Z plane."""
    inside=np.zeros(SHAPE,dtype=bool); distance=np.full(SHAPE,1e6)
    for i,p in enumerate(points):
        q=points[(i+1)%len(points)]; px,pz=p; qx,qz=q
        inside ^= ((pz>Z)!=(qz>Z)) & (X < (qx-px)*(Z-pz)/(qz-pz+1e-12)+px)
        dx,dz=qx-px,qz-pz
        t=np.clip(((X-px)*dx+(Z-pz)*dz)/(dx*dx+dz*dz),0,1)
        distance=np.minimum(distance,np.hypot(X-px-t*dx,Z-pz-t*dz))
    return inside,distance

def box(a,x0,x1,y0,y1,z0,z1,c):
    a[(X>=x0)&(X<x1)&(Y>=y0)&(Y<y1)&(Z>=z0)&(Z<z1)]=c


def handle(a,top):
    # A two-voxel square shaft with a slightly wider wooden butt.
    box(a,-1,1,-1,1,1,top,12)
    box(a,-2,2,-1,1,1,4,12)
    a[(a==12)&(X>.1)]=11


def plate(a,points,half=1):
    inside,dist=polygon_field(points)
    mask=inside&(abs(Y)<half)
    color=np.where(dist<.9,5,np.where(X>1,3,4))
    a[mask]=color[mask]
    return inside,dist


def axe():
    a=blank(); handle(a,29)
    # Broad simple cutting blade and short square poll, without decoration.
    points=[(-5,20),(-5,27),(-1,27),(2,26),(5,29),(8,29),
            (10,27),(10,21),(8,18),(5,18),(2,21),(-1,21)]
    inside,dist=plate(a,points)
    # Only the socket is four voxels thick; cutting edge remains two.
    box(a,-2,2,-2,2,23,27,4)
    box(a,-1,1,-1,1,27,30,12)
    a[inside&(X>=8)&(a>0)]=6
    return a


def pickaxe():
    a=blank(); handle(a,29)
    plate(a,[(-11,21),(-10,25),(-7,27),(-3,28),(3,28),(7,27),
             (10,24),(11,20),(9,22),(6,24),(2,25),(-2,25),(-6,25),(-9,23)])
    # Square off the tiny tip steps so they connect through voxel faces.
    box(a,-10,-9,-1,1,22,23,5)
    box(a,9,10,-1,1,21,22,5)
    box(a,-2,2,-2,2,25,28,11)
    box(a,-1,1,-2,2,25,28,12)
    box(a,-1,1,-1,1,28,30,12)
    return a


def sword():
    a=blank()
    # Plain leather grip and compact iron pommel.
    box(a,-1,1,-1,1,3,12,17)
    box(a,-1,1,-1,1,5,6,16)
    box(a,-1,1,-1,1,9,10,16)
    box(a,-2,2,-1,1,1,4,4)
    # A short, broad iron blade with a two-voxel edge and thicker central spine.
    inside,dist=plate(a,[(-3,13),(3,13),(3,32),(1,36),(0,37),(-1,36),(-3,32)])
    ridge=inside&(abs(X)<1)&(abs(Y)<2)&(Z<33)
    a[ridge]=4
    a[inside&(abs(X)>2)&(a>0)]=6
    # Modest crossguard retains the reference's brown centre and iron ends.
    box(a,-6,6,-1,1,11,13,11)
    box(a,-7,-5,-1,1,11,14,4)
    box(a,5,7,-1,1,11,14,4)
    box(a,-2,2,-2,2,11,14,4)
    return a


def components(a):
    remaining=set(map(tuple,np.argwhere(a))); sizes=[]
    while remaining:
        q=deque([remaining.pop()]); n=0
        while q:
            x,y,z=q.popleft(); n+=1
            for p in ((x-1,y,z),(x+1,y,z),(x,y-1,z),(x,y+1,z),(x,y,z-1),(x,y,z+1)):
                if p in remaining: remaining.remove(p); q.append(p)
        sizes.append(n)
    return sorted(sizes,reverse=True)

def chunk(tag, data=b'', children=b''):
    return tag+struct.pack('<II',len(data),len(children))+data+children

def palette_bytes():
    return b''.join(bytes(c)+b'\xff' for c in RGB)+bytes([0,0,0,255])*(256-len(RGB))

def export(path,a):
    xyz=np.argwhere(a); rows=np.column_stack((xyz,a[tuple(xyz.T)])).astype(np.uint8)
    children=chunk(b'SIZE',struct.pack('<3i',*a.shape))
    children+=chunk(b'XYZI',struct.pack('<I',len(rows))+rows.tobytes())
    children+=chunk(b'RGBA',palette_bytes())
    path.write_bytes(b'VOX '+struct.pack('<I',150)+chunk(b'MAIN',children=children))

def readback(path):
    b=path.read_bytes(); assert b[:8]==b'VOX '+struct.pack('<I',150)
    assert b[8:12]==b'MAIN' and struct.unpack_from('<II',b,12)==(0,len(b)-20)
    pos=20; a=None; palette=None
    while pos<len(b):
        tag=b[pos:pos+4]; n,ch=struct.unpack_from('<II',b,pos+4)
        assert ch==0 and pos+12+n<=len(b)
        data=b[pos+12:pos+12+n]; pos+=12+n
        if tag==b'SIZE':
            dims=struct.unpack('<3I',data); assert dims==SHAPE
        elif tag==b'XYZI':
            count=struct.unpack_from('<I',data)[0]
            rows=np.frombuffer(data[4:],np.uint8).reshape(-1,4)
            assert len(rows)==count==len(np.unique(rows[:,:3],axis=0))
            assert (rows[:,:3]<dims).all() and (rows[:,3]>0).all() and (rows[:,3]<=len(RGB)).all()
            a=np.zeros(dims,np.uint8); a[tuple(rows[:,:3].T)]=rows[:,3]
        elif tag==b'RGBA': palette=data
    assert pos==len(b) and palette==palette_bytes() and a is not None
    return a,palette

def font(size,bold=False):
    return ImageFont.truetype('C:/Windows/Fonts/'+('segoeuib.ttf' if bold else 'segoeui.ttf'),size)

def render(a,size=(480,690),az=-68,el=12,scale=15):
    az,el=math.radians(az),math.radians(el)
    view=np.array([math.cos(az)*math.cos(el),math.sin(az)*math.cos(el),math.sin(el)])
    right=np.array([-math.sin(az),math.cos(az),0]); up=np.cross(view,right)
    center=np.array([16,4,20]); faces=[]; pad=np.pad(a,1)
    for axis in range(3):
        if abs(view[axis])<1e-6: continue
        sign=1 if view[axis]>0 else -1
        sl=[slice(1,-1)]*3; sl[axis]=slice(2,None) if sign>0 else slice(None,-2)
        p=np.argwhere((a>0)&(pad[tuple(sl)]==0))
        others=[j for j in range(3) if j!=axis]
        corners=np.zeros((4,3)); corners[:,axis]=1 if sign>0 else 0
        corners[:,others[0]]=[0,1,1,0]; corners[:,others[1]]=[0,0,1,1]
        verts=p[:,None,:]+corners-center
        uv=np.stack((verts@right,-verts@up),axis=-1)*scale+np.array(size)/2
        depth=(p+corners.mean(0)-center)@view
        cols=np.clip(RGB.astype(float)*[.78,.97,1.10][axis],0,255).astype(np.uint8)
        for i in range(len(p)):
            faces.append((depth[i],uv[i],tuple(cols[a[tuple(p[i])]-1])+(255,)))
    faces.sort(key=lambda f:f[0]); im=Image.new('RGBA',size); d=ImageDraw.Draw(im)
    for _,poly,c in faces: d.polygon([tuple(v) for v in np.rint(poly).astype(int)],fill=c)
    return im

def previews(models):
    pre=ROOT/'previews'; pre.mkdir(exist_ok=True)
    bg=(23,29,32); white=(232,233,218); muted=(154,166,166); accent=(207,167,99)
    sheet=Image.new('RGB',(1560,1000),bg); d=ImageDraw.Draw(sheet)
    d.text((52,32),'BLOCKBOUND  /  BEGINNER EQUIPMENT',font=font(18,True),fill=accent)
    d.text((49,65),'Simple starter tools',font=font(40,True),fill=white)
    d.text((52,121),'Small solid voxel models. The same shared palette.',font=font(19),fill=muted)
    for i,(name,a) in enumerate(models.items()):
        left=30+i*510
        d.rounded_rectangle((left,170,left+490,910),radius=12,fill=(30,37,40))
        im=render(a); sheet.paste(im,(left+5,168),im); im.save(pre/(name+'.png'))
        d.text((left+25,845),name.upper(),font=font(25,True),fill=white)
        d.text((left+25,882),f'{np.count_nonzero(a):,} voxels',font=font(15),fill=muted)
        views=Image.new('RGB',(1600,780),bg); vd=ImageDraw.Draw(views)
        vd.text((35,20),name.upper()+' / GEOMETRY VIEWS',font=font(23,True),fill=white)
        for j,(az,label) in enumerate([(-90,'FRONT'),(0,'SIDE'),(90,'BACK'),(-52,'THREE-QUARTER')]):
            v=render(a,(400,660),az=az,el=0 if j<3 else 16,scale=15)
            views.paste(v,(j*400,60),v)
            vd.text((j*400+25,740),label,font=font(17,True),fill=muted)
        views.save(pre/(name+'_views.png'))
    for i,(_,h) in enumerate(PALETTE):
        x=52+i*39; d.rectangle((x,939,x+29,960),fill=h)
    d.text((960,937),'Rendered from the exported .vox files',font=font(17),fill=muted)
    sheet.save(pre/'tools_lineup.png')
    pal=Image.new('RGB',(880,310),bg); d=ImageDraw.Draw(pal)
    for i,(name,h) in enumerate(PALETTE):
        col,row=i%6,i//6; x=col*145+10; y=row*76+8
        d.rectangle((x,y,x+125,y+36),fill=h)
        d.text((x,y+38),f'{i+1:02} {name}',font=font(12),fill=white)
    pal.save(pre/'shared_palette.png')

def main():
    ROOT.mkdir(parents=True,exist_ok=True)
    models={'axe':axe(),'pickaxe':pickaxe(),'sword':sword()}; decoded={}; palettes=[]
    stats={'format':'MagicaVoxel VOX 150','canvas':SHAPE,'up_axis':'+Z',
           'raw_base_pivot':[16,4,0],'files':{}}
    for name,a in models.items():
        parts=components(a); assert len(parts)==1,(name,parts)
        path=ROOT/(name+'.vox'); export(path,a); b,pal=readback(path)
        assert np.array_equal(a,b); decoded[name]=b; palettes.append(pal)
        xyz=np.argwhere(b)
        stats['files'][path.name]={'voxels':len(xyz),'occupied_min':xyz.min(0).tolist(),
            'occupied_max_exclusive':(xyz.max(0)+1).tolist(),'occupied_size':(np.ptp(xyz,axis=0)+1).tolist(),
            'face_connected_components':len(parts),'binary_roundtrip':'passed',
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    assert all(p==palettes[0] for p in palettes)
    stats['identical_RGBA_chunks']=True
    (ROOT/'validation.json').write_text(json.dumps(stats,indent=2)+'\n')
    (ROOT/'palette.json').write_text(json.dumps([{'index':i+1,'name':n,'hex':h} for i,(n,h) in enumerate(PALETTE)],indent=2)+'\n')
    # GIMP-compatible palette for convenient reuse in other art tools.
    (ROOT/'shared_palette.gpl').write_text('GIMP Palette\nName: Blockbound Iron Oak Leather\nColumns: 6\n#\n'+
        '\n'.join(f'{r:3} {g:3} {b:3} {name}' for (r,g,b),(name,_) in zip(RGB,PALETTE))+'\n')
    previews(decoded)
    paths=sorted(ROOT.glob('*.vox'))+list(ROOT.glob('*.json'))+list(ROOT.glob('*.gpl'))+[ROOT/'README.md',Path(__file__).resolve()]+sorted((ROOT/'previews').glob('*.png'))
    with zipfile.ZipFile(ROOT/'Blockbound_Tools.zip','w',zipfile.ZIP_DEFLATED) as z:
        for path in paths: z.write(path,path.relative_to(ROOT))
    with zipfile.ZipFile(ROOT/'Blockbound_Tools.zip') as z: assert z.testzip() is None
    print(json.dumps(stats,indent=2))

if __name__=='__main__': main()
