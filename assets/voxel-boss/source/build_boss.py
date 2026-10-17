"""Riftmaw: hand-directed integer-voxel sculpt, VOX exporter and hard-pixel renderer.
Run with Python, NumPy and Pillow. No meshes, textures or antialiasing are used.
"""
from pathlib import Path
import math
import struct
import json
import hashlib
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1]
PRE = OUT / 'previews'
PALETTE = [
    (19, 17, 35),    # 1 deepest chitin / outline
    (30, 27, 52),    # 2 joint
    (42, 34, 69),    # 3 shell shadow
    (57, 43, 89),    # 4 dark violet
    (76, 54, 111),   # 5 violet
    (99, 68, 133),   # 6 amethyst
    (126, 88, 155),  # 7 plates
    (158, 119, 178), # 8 lavender bevel
    (191, 158, 199), # 9 edge glint
    (55, 35, 55),    # 10 belly shadow
    (87, 52, 73),    # 11 belly seam
    (125, 77, 99),   # 12 belly
    (159, 104, 123), # 13 belly highlight
    (193, 139, 151), # 14 belly bevel
    (23, 12, 25),    # 15 throat
    (65, 24, 43),    # 16 inner mouth
    (108, 35, 57),   # 17 gums
    (159, 53, 71),   # 18 lip highlight
    (95, 84, 56),    # 19 horn shadow
    (145, 132, 84),  # 20 horn
    (195, 182, 123), # 21 ivory shade
    (235, 221, 164), # 22 ivory
    (255, 243, 198), # 23 tooth tip
    (64, 73, 43),    # 24 venom outline
    (110, 129, 47),  # 25 moss
    (168, 190, 66),  # 26 acid green
    (218, 231, 107), # 27 bright acid
    (242, 244, 163), # 28 pinpoint
]
C = 31.5

def grid(h):
    return np.zeros((64,64,h), dtype=np.uint8)

def coords(a):
    return np.indices(a.shape, dtype=float)

def connection():
    x,y = np.indices((64,64), dtype=float)
    r = ((x-C)/14.5)**2 + ((y-C)/12.5)**2
    return np.where(r<=1, np.where(r>.77, 5, 3), 0).astype(np.uint8)

def tube(a, points, radii, colors, facet=False):
    """Voxelize connected tapered curves; all results are whole opaque unit cubes."""
    x,y,z = coords(a)
    for i in range(len(points)-1):
        p = np.array(points[i],float)
        v = np.array(points[i+1],float)-p
        t = np.clip(((x-p[0])*v[0]+(y-p[1])*v[1]+(z-p[2])*v[2])/np.dot(v,v),0,1)
        r = radii[i]*(1-t)+radii[i+1]*t
        dx,dy,dz = x-p[0]-t*v[0], y-p[1]-t*v[1], z-p[2]-t*v[2]
        d = dx*dx+dy*dy+dz*dz
        mask=d<=np.maximum(r,.55)**2
        shade=np.where(dx+dy < -r*.25, colors[-1], np.where(dx+dy > r*.4,colors[0],colors[len(colors)//2]))
        a[mask]=shade[mask]

def body():
    a=grid(56)
    x,y,z=coords(a)
    dx,dy=x-C,y-C
    rr=np.sqrt((dx/14.5)**2+(dy/12.5)**2)
    a[rr<=1]=3
    a[(rr<=1)&(rr>.82)]=5
    theta=np.arctan2(dy/12.5,dx/14.5)
    # Two long overlapping shield courses form one cohesive 56-voxel segment.
    # Details remain unit-cube sized instead of stretching the old voxel raster.
    for base,height in [(3,27),(28,25)]:
        for n in range(8):
            ang=n*math.pi/4
            ad=np.abs((theta-ang+math.pi)%(2*math.pi)-math.pi)
            tangent=ad/(math.pi/8*.91)
            tip=base+np.floor(tangent*6)
            active=(tangent<=1)&(z>=tip)&(z<=base+height-1)
            bulge=np.interp(z-base,[0,5,10,18,height-1],[1.10,1.38,1.36,1.22,1.04])
            bulge-=.10*tangent
            mask=active&(rr<=bulge)
            shade=np.where(z<=tip+1,8,np.where(z<=tip+4,7,np.where(tangent>.73,4,np.where(tangent<.23,7,6))))
            shade=np.where((tangent<.11)&(z>tip+8),5,shade)
            a[mask]=shade[mask]
            edge=mask&(rr>bulge-.07)&(z<=tip+1)&(tangent<.55)
            a[edge]=9
    # Ten belly scutes preserve the pixel scale and visual cadence of the end pieces.
    for lo in range(3,53,5):
        hi=lo+3
        w=9-(z-lo)*.3
        ym=17-np.where(z==lo,0,1)
        mask=(z>=lo)&(z<=hi)&(np.abs(dx)<=w)&(y>=ym)&(y<=25)
        a[mask]=12
        a[mask&(z==lo)]=14
        a[mask&(z==hi)]=11
        a[mask&(np.abs(dx)<5)&(z==lo+1)]=13
    # Two pairs of swept barbs and dorsal keels follow the longer shield courses.
    for side in [-1,1]:
        for base in [5,30]:
            tube(a,[(C+side*15,32,base+11),(C+side*20,33,base+5),
                    (C+side*22,33,base)], [3,1.8,.55],[4,6,8])
    for base in [5,30]:
        tube(a,[(C,45,base+14),(C,48,base+7),(C,50,base+1)],[3,2,.55],[4,7,9])
    # Side ocelli from the sprite reference. A recessed dark slit in an olive ring.
    for side in [-1,1]:
        for yy in range(26,38):
            for zz in range(34,47):
                d=((yy-31.5)/5.2)**2+((zz-40)/5.8)**2
                if d>1: continue
                hits=np.flatnonzero(a[:,yy,zz])
                if len(hits)==0: continue
                xx=hits[-1] if side==1 else hits[0]
                col=24 if d>.77 else (26 if d>.31 else 1)
                if d<.77 and d>.31 and yy<31: col=27
                a[xx,yy,zz]=col
                # One raised voxel makes the rim catch the light.
                if .31<d<.77: a[xx+side,yy,zz]=col
    # Identical cap footprint and palette at both ends: no holes or stepped join.
    a[:,:,0]=connection()
    a[:,:,55]=connection()
    # Mirror the negative-X half exactly, including all colour and bevel details.
    a[32:,:,:]=a[31::-1,:,:]
    return a

def head():
    a=grid(56)
    x,y,z=coords(a)
    dx,dy=x-C,y-C
    theta=np.arctan2(dy/20,dx/22)
    # Entirely axial anatomy: the throat, jaw and tooth crown open along +Z.
    # The body socket stays at Z=0. No side-facing mouth or transverse skull.
    rx=np.interp(z,[0,2,10,21,34,43,55],[14.5,14.5,18,21,22,22,21])
    ry=np.interp(z,[0,2,10,21,34,43,55],[12.5,12.5,16,19,20,20,19])
    radial=np.sqrt((dx/rx)**2+(dy/ry)**2)
    lip=40+np.floor(2*np.cos(4*theta))
    solid=(radial<=1)&(z<=lip)
    a[solid]=5
    a[solid&(radial<.86)]=4
    # Three rows of pointed overlapping shields, using the body's plate language.
    for base,height in [(3,13),(14,14),(26,16)]:
        for n in range(8):
            ang=n*math.pi/4
            ad=np.abs((theta-ang+math.pi)%(2*math.pi)-math.pi)
            w=ad/(math.pi/8*.93)
            low=base+np.floor(w*3)
            bulge=1+.12*np.sin(np.clip((z-low)/height,0,1)*math.pi)-.055*w
            plate=(w<=1)&(z>=low)&(z<base+height)&(radial<=bulge)&(radial>.80)
            shade=np.where(z<=low+1,8,np.where(z<=low+3,7,np.where(w>.76,4,6)))
            a[plate]=shade[plate]
            a[plate&(z<=low+1)&(w<.38)&(radial>bulge-.055)]=9
    # Raised jaw lip, divided into eight chitin plates rather than a flat disk.
    jaw_r=np.sqrt((dx/22.5)**2+(dy/20.5)**2)
    rim=(jaw_r<=1)&(jaw_r>.77)&(z>=lip-4)&(z<=lip)
    a[rim]=7
    a[rim&(z==lip)]=8
    phase=(theta+math.pi)*8/(2*math.pi)%1
    a[rim&(phase<.10)]=4
    a[rim&(z==lip)&(phase>.78)]=9
    # A real axial cavity tapers down into the neck. Its dark floor is at Z=15.
    mouth_r=np.sqrt((dx/17.3)**2+(dy/15.4)**2)
    floor=15+18*np.clip(mouth_r,0,1)**1.6
    cavity=(mouth_r<1)&(z>=floor)
    a[cavity]=0
    lining=(mouth_r<1)&(z<floor)&(z>=floor-2)
    a[lining]=16
    a[lining&(mouth_r<.4)]=15
    gum=(mouth_r>=.92)&(mouth_r<=1.1)&(z>=lip-6)&(z<=lip)
    a[gum]=17
    a[gum&(z>=lip-1)]=18
    # Red muscular ribs run lengthwise down into the hollow throat.
    for k in range(8):
        ang=k*math.pi/4
        cs,sn=math.cos(ang),math.sin(ang)
        tube(a,[(C+cs*16.5,C+sn*14.6,36),(C+cs*12,C+sn*10.7,27),
                (C+cs*6,C+sn*5.3,19)], [1.15,1,.55],[16,17,18])
    # Twelve long hooks point along the worm axis, then curve inward at the tips.
    for k in range(12):
        ang=2*math.pi*k/12
        cs,sn=math.cos(ang),math.sin(ang)
        tall=3 if k%3==0 else (1 if k%2==0 else 0)
        tube(a,[(C+cs*18.4,C+sn*16.5,38),
                (C+cs*18,C+sn*16,44+tall),
                (C+cs*14.5,C+sn*12.8,49+tall),
                (C+cs*10.6,C+sn*9.3,50+tall)],
             [2.5,2,1.2,.55],[20,22,23])
    # Six smaller inner teeth make the maw dense without closing the opening.
    for k in range(6):
        ang=(k+.5)*math.pi/3
        cs,sn=math.cos(ang),math.sin(ang)
        tube(a,[(C+cs*15.8,C+sn*14,33),(C+cs*13,C+sn*11.5,38),
                (C+cs*10.5,C+sn*9.2,40)], [1.7,1.1,.55],[19,21,22])
    # Side swept armour barbs integrate the neck with the existing body silhouette.
    for side in [-1,1]:
        for zz,span in [(12,18),(24,21),(35,22)]:
            tube(a,[(C+side*(span-2),34,zz+3),
                    (C+side*(span+3),36,zz),(C+side*(span+5),37,zz-5)],
                 [3,1.8,.55],[4,7,8])
    # Four long outer mandible horns frame the axial opening.
    for k in range(4):
        ang=math.pi/4+k*math.pi/2
        cs,sn=math.cos(ang),math.sin(ang)
        tube(a,[(C+cs*21,C+sn*19,34),(C+cs*25,C+sn*23,42),
                (C+cs*25.5,C+sn*23.5,47)], [3.4,2.5,1.7],[4,7,8])
        tube(a,[(C+cs*25.5,C+sn*23.5,46),(C+cs*24,C+sn*22,51),
                (C+cs*20.5,C+sn*18.5,55)], [1.8,1.2,.55],[19,21,23])
    # Ventral neck scutes connect to the rose underside of the unchanged body.
    for lo in [2,6,10,14,18,22]:
        hi=lo+3
        yr=31.5-(12.5+min(lo,21)*.30)
        mask=(z>=lo)&(z<=hi)&(np.abs(dx)<=9)&(y>=yr-1)&(y<=yr+4)
        a[mask]=12
        a[mask&(z==lo)]=14
        a[mask&(z==hi)]=11
    # Small side sensory markings, echoing the repeatable segment's ocelli.
    for side in [-1,1]:
        for yy in range(25,34):
            for zz in range(25,32):
                d=abs((yy-29)/4)+abs((zz-28)/3)
                if d>1: continue
                hits=np.flatnonzero(a[:,yy,zz])
                if len(hits):
                    xx=hits[-1] if side==1 else hits[0]
                    a[xx,yy,zz]=26 if d>.4 else 1
                    if .4<d<.8 and yy<=29: a[xx,yy,zz]=27
    a[:,:,0]=connection()
    a[:,:,1]=connection()
    return a

def tail():
    a=grid(56)
    x,y,z=coords(a)
    # The stem curves rearward as it narrows; its socket is still centred.
    for zz in range(16,55):
        t=(54-zz)/38
        cy=C+7*t*t
        rx=14.5*(1-.80*t)
        ry=12.5*(1-.80*t)
        dx,dy=x[:,:,zz]-C,y[:,:,zz]-cy
        rr=np.sqrt((dx/rx)**2+(dy/ry)**2)
        a[:,:,zz][rr<=1]=5
        th=np.arctan2(dy/ry,dx/rx)
        # Four diminishing armoured rings, matching the body's pointed plates.
        phase=(54-zz)%10
        for n in range(8):
            ad=np.abs((th-n*math.pi/4+math.pi)%(2*math.pi)-math.pi)
            w=ad/(math.pi/8*.92)
            bulge=1+.30*math.sin(phase/10*math.pi)-w*.08
            mask=(w<=1)&(rr<=bulge)&(phase<=8-np.floor(w*2))
            shade=np.where(phase>=6-np.floor(w*2),8,np.where(w>.76,4,6))
            a[:,:,zz][mask]=shade[mask]
        # Ventral dusty-rose banded belly tapers along with the tail.
        mask=(np.abs(dx)<rx*.56)&(dy>=-ry-1)&(dy<=-ry+3)
        a[:,:,zz][mask]=14 if phase==7 else (11 if phase==0 else 12)
    for side in [-1,1]:
        for zz,span in [(44,15),(33,12),(23,8)]:
            tube(a,[(C+side*(span-3),34,zz+3),(C+side*span,36,zz-1),(C+side*(span+1),38,zz-5)], [2.7,1.7,.55],[4,7,8])
    # Continuous hooked ivory stinger: broad socket, narrow point curling forward.
    tube(a,[(C,38,20),(C,40,14),(C,40,8),(C,36,3),(C,30,1),(C,24,4)],
         [3.7,4,3.4,2.6,1.6,.55],[19,21,23])
    # Olive venom groove is voxel inlay, without bloom or transparency.
    tube(a,[(C-2.8,37,18),(C-3,38,13),(C-2.5,38,9)], [1,.9,.55],[24,25,26])
    a[:,:,54]=connection()
    a[:,:,55]=connection()
    return a

def chunk(name,data,children=b''):
    return name+struct.pack('<II',len(data),len(children))+data+children

def write_vox(path,a):
    xyz=np.argwhere(a)
    records=np.column_stack((xyz,a[a>0])).astype(np.uint8).tobytes()
    palette=b''.join(bytes((*c,255)) for c in PALETTE)
    palette+=bytes((0,0,0,255))*(256-len(PALETTE))
    children=chunk(b'SIZE',struct.pack('<III',*a.shape))
    children+=chunk(b'XYZI',struct.pack('<I',len(xyz))+records)
    children+=chunk(b'RGBA',palette)
    path.write_bytes(b'VOX '+struct.pack('<I',150)+chunk(b'MAIN',b'',children))

def read_vox(path):
    b=path.read_bytes()
    assert b[:4]==b'VOX ' and struct.unpack_from('<I',b,4)[0] in (150,200)
    assert b[8:12]==b'MAIN'
    assert struct.unpack_from('<II',b,12)==(0,len(b)-20)
    pos=20
    chunks={}
    model_count=0
    while pos<len(b):
        tag=b[pos:pos+4]
        n,ch=struct.unpack_from('<II',b,pos+4)
        assert ch==0 and pos+12+n<=len(b)
        chunks[tag]=b[pos+12:pos+12+n]
        if tag==b'SIZE': model_count+=1
        pos+=12+n
    assert model_count==1 and {b'SIZE',b'XYZI',b'RGBA'}<=set(chunks)
    shape=struct.unpack('<III',chunks[b'SIZE'])
    a=np.zeros(shape,dtype=np.uint8)
    n=struct.unpack_from('<I',chunks[b'XYZI'])[0]
    q=np.frombuffer(chunks[b'XYZI'][4:],np.uint8).reshape(-1,4)
    assert n==len(q) and len(np.unique(q[:,:3],axis=0))==n
    assert (q[:,:3]<shape).all() and (q[:,3]>0).all() and (q[:,3]<=len(PALETTE)).all()
    a[tuple(q[:,:3].T)]=q[:,3]
    assert len(chunks[b'RGBA'])==1024
    return a,chunks[b'RGBA']

def components(a):
    occupied=set(map(tuple,np.argwhere(a>0)))
    sizes=[]
    while occupied:
        p=occupied.pop(); todo=[p]; size=0
        while todo:
            x,y,z=todo.pop(); size+=1
            for p in [(x+1,y,z),(x-1,y,z),(x,y+1,z),(x,y-1,z),(x,y,z+1),(x,y,z-1)]:
                if p in occupied: occupied.remove(p); todo.append(p)
        sizes.append(size)
    return sorted(sizes,reverse=True)

def keep_connected(a):
    # Remove isolated single-voxel raster tangencies; never export floating chips.
    occ=a>0
    start=tuple(np.argwhere(occ)[len(np.argwhere(occ))//2])
    visited=np.zeros(a.shape,bool); visited[start]=True; todo=[start]
    while todo:
        x,y,z=todo.pop()
        for xx,yy,zz in [(x+1,y,z),(x-1,y,z),(x,y+1,z),(x,y-1,z),(x,y,z+1),(x,y,z-1)]:
            if 0<=xx<a.shape[0] and 0<=yy<a.shape[1] and 0<=zz<a.shape[2] and occ[xx,yy,zz] and not visited[xx,yy,zz]:
                visited[xx,yy,zz]=True; todo.append((xx,yy,zz))
    lost=int(np.count_nonzero(occ&~visited)); a[~visited]=0
    return lost

def render(a,az=-60,el=24,size=(420,500),scale=None):
    """Orthographic exposed cube faces, rasterized at native resolution, no AA."""
    az,el=math.radians(az),math.radians(el)
    view=np.array([math.cos(az)*math.cos(el),math.sin(az)*math.cos(el),math.sin(el)])
    right=np.array([-math.sin(az),math.cos(az),0])
    up=np.cross(view,right)
    xyz=np.argwhere(a>0)
    # Always center by actual occupied bounds so empty model padding isn't displayed.
    center=(xyz.min(0)+xyz.max(0)+1)/2
    bound=np.array([[xx,yy,zz] for xx in [xyz[:,0].min(),xyz[:,0].max()+1]
                   for yy in [xyz[:,1].min(),xyz[:,1].max()+1]
                   for zz in [xyz[:,2].min(),xyz[:,2].max()+1]])-center
    ext=np.array([np.ptp(bound@right),np.ptp(bound@up)])
    if scale is None: scale=min((size[0]-24)/ext[0],(size[1]-24)/ext[1])
    faces=[]
    for axis in range(3):
        sign=1 if view[axis]>0 else -1
        if abs(view[axis])<1e-8: continue
        pad=np.pad(a,1)
        sl=[slice(1,-1)]*3
        sl[axis]=slice(2,None) if sign==1 else slice(None,-2)
        mask=(a>0)&(pad[tuple(sl)]==0)
        p=np.argwhere(mask)
        other=[j for j in range(3) if j!=axis]
        corners=np.zeros((4,3)); corners[:,axis]=1 if sign==1 else 0
        corners[:,other[0]]=[0,1,1,0];corners[:,other[1]]=[0,0,1,1]
        verts=p[:,None,:]+corners[None,:,:]-center
        uv=np.stack((verts@right,-verts@up),axis=-1)*scale+np.array(size)/2
        depth=(p+corners.mean(0)-center)@view
        shade=[.86,.72,1.08][axis]
        # Discrete face colors only; no smooth lighting, AO, blur or glossy material.
        cols=np.clip(np.array(PALETTE,dtype=float)*shade,0,255).astype(np.uint8)
        for i in range(len(p)):
            col=tuple(cols[a[tuple(p[i])]-1])
            faces.append((depth[i],uv[i],col))
    faces.sort(key=lambda f:f[0])
    im=Image.new('RGB',size,(18,22,33));d=ImageDraw.Draw(im)
    for _,poly,col in faces:
        d.polygon([tuple(v) for v in np.rint(poly).astype(int)],fill=col)
    return im

def font(sz,bold=False):
    names=['C:/Windows/Fonts/consolab.ttf' if bold else 'C:/Windows/Fonts/consola.ttf']
    for name in names:
        if Path(name).exists():return ImageFont.truetype(name,sz)
    return ImageFont.load_default()

def assembly(parts,n=3):
    tail_h=parts['tail'].shape[2]; pitch=parts['body_segment'].shape[2]
    a=np.zeros((64,64,tail_h+pitch*n+parts['head'].shape[2]),np.uint8)
    a[:,:,:tail_h]=parts['tail']
    for i in range(n): a[:,:,tail_h+pitch*i:tail_h+pitch*(i+1)]=parts['body_segment']
    a[:,:,tail_h+pitch*n:]=parts['head']
    return a

def previews(parts):
    PRE.mkdir(exist_ok=True)
    # Art is deliberately rendered at 1/2 resolution and enlarged nearest-neighbour.
    angles=[(-90,8,'FRONT'),(-45,22,'THREE-QUARTER'),(0,9,'SIDE'),(60,25,'REAR')]
    sheet=Image.new('RGB',(1440,1140),(18,22,33));d=ImageDraw.Draw(sheet)
    d.text((36,22),'RIFTMAW / MODULAR VOXEL BOSS',font=font(29,True),fill=(235,221,164))
    d.text((36,64),'WHOLE CUBES  /  28 SHARED COLOURS  /  NO SMOOTHING',font=font(17),fill=(158,166,187))
    for row,(key,label) in enumerate([('head','01  HEAD'),('body_segment','02  BODY / REPEAT x N'),('tail','03  TAIL')]):
        top=110+row*336
        d.line((28,top-6,1412,top-6),fill=(48,48,68),width=2)
        d.text((36,top),label,font=font(20,True),fill=(191,158,199))
        part_angles=[(-90,90,'AXIAL / INTO MOUTH'),(-45,42,'THREE-QUARTER'),(0,0,'SIDE / BODY AXIS'),(60,25,'REAR')] if key=='head' else angles
        for col,(az,el,name) in enumerate(part_angles):
            im=render(parts[key],az,el,(172,136))
            sheet.paste(im.resize((344,272),Image.Resampling.NEAREST),(24+col*352,top+28))
            d.text((36+col*352,top+303),name,font=font(15),fill=(144,154,178))
    sheet.save(PRE/'parts_multiview.png')
    full=assembly(parts)
    hero=Image.new('RGB',(1440,1100),(18,22,33));d=ImageDraw.Draw(hero)
    d.text((40,26),'RIFTMAW',font=font(40,True),fill=(235,221,164))
    d.text((42,78),'ARMOURED BURROWER / HEAD + 3 BODY SEGMENTS + TAIL',font=font(18),fill=(158,166,187))
    for col,(az,el,name) in enumerate([(-65,34,'AXIAL MAW / THREE-QUARTER'),(-90,0,'SIDE / LENGTHWISE ALIGNMENT'),(60,28,'BACK / PLATE DETAIL')]):
        im=render(full,az,el,(224,448))
        hero.paste(im.resize((448,896),Image.Resampling.NEAREST),(32+col*468,130))
        d.text((40+col*468,1040),name,font=font(17),fill=(191,158,199))
    hero.save(PRE/'assembled_multiview.png')
    render(parts['head'],-65,43,(360,360)).resize((720,720),Image.Resampling.NEAREST).save(PRE/'head_detail.png')
    head_sheet=Image.new('RGB',(1440,630),(18,22,33));hd=ImageDraw.Draw(head_sheet)
    hd.text((36,22),'RIFTMAW / AXIAL HEAD',font=font(30,True),fill=(235,221,164))
    hd.text((36,66),'MOUTH OPENS ALONG +Z / SAME AXIS AS THE BODY',font=font(18),fill=(158,166,187))
    for col,(az,el,label) in enumerate([(-90,90,'INTO THE MOUTH / +Z'),(-55,43,'THREE-QUARTER'),(0,0,'SIDE / BODY CONNECTS BELOW')]):
        im=render(parts['head'],az,el,(228,238))
        head_sheet.paste(im.resize((456,476),Image.Resampling.NEAREST),(24+col*472,105))
        hd.text((36+col*472,598),label,font=font(17),fill=(191,158,199))
    head_sheet.save(PRE/'head_multiview.png')
    body_sheet=Image.new('RGB',(1440,650),(18,22,33));bd=ImageDraw.Draw(body_sheet)
    bd.text((36,22),'RIFTMAW / LONG BODY SEGMENT',font=font(30,True),fill=(235,221,164))
    bd.text((36,66),'56 VOXELS TALL / MIRRORED ON X / MATCHING END CONNECTIONS',font=font(18),fill=(158,166,187))
    for col,(az,el,label) in enumerate(angles):
        im=render(parts['body_segment'],az,el,(172,240))
        body_sheet.paste(im.resize((344,480),Image.Resampling.NEAREST),(24+col*352,110))
        bd.text((36+col*352,608),label,font=font(17),fill=(191,158,199))
    body_sheet.save(PRE/'body_multiview.png')
    proportions=Image.new('RGB',(1440,730),(18,22,33));pd=ImageDraw.Draw(proportions)
    pd.text((36,22),'RIFTMAW / MATCHED PART HEIGHTS',font=font(30,True),fill=(235,221,164))
    pd.text((36,66),'HEAD / BODY / TAIL AT THE SAME SCALE',font=font(18),fill=(158,166,187))
    for col,(name,label) in enumerate([('head','HEAD / 56 VOXELS'),('body_segment','BODY / 56 VOXELS'),('tail','TAIL / 56 VOXELS')]):
        im=render(parts[name],-65,22,(228,280),scale=3)
        proportions.paste(im.resize((456,560),Image.Resampling.NEAREST),(24+col*472,105))
        pd.text((36+col*472,680),label,font=font(19),fill=(191,158,199))
    proportions.save(PRE/'part_proportions.png')
    # Close section: body seams remain visible and can be inspected at voxel scale.
    stack=np.concatenate([parts['body_segment']]*3,axis=2)
    render(stack,-52,18,(280,320)).resize((560,640),Image.Resampling.NEAREST).save(PRE/'body_repeat_detail.png')
    sw=Image.new('RGB',(896,160),(18,22,33));d=ImageDraw.Draw(sw)
    for i,c in enumerate(PALETTE):
        xx=(i%14)*64;yy=(i//14)*80
        d.rectangle((xx+4,yy+4,xx+59,yy+55),fill=c)
        d.text((xx+15,yy+59),str(i+1).zfill(2),font=font(14),fill=(191,198,213))
    sw.save(PRE/'shared_palette.png')

def main():
    # The saved head and tail are authoritative, including the user's editor changes.
    # This entry point rebuilds ONLY the body; it never rewrites either end piece.
    preserved={name:(OUT/(name+'.vox')).read_bytes() for name in ['head','tail']}
    parts={'head':read_vox(OUT/'head.vox')[0],'body_segment':body(),
           'tail':read_vox(OUT/'tail.vox')[0]}
    report={'body_format':'MagicaVoxel VOX 150','palette_colors':len(PALETTE),'parts':{}}
    pal=None
    for name,a in parts.items():
        removed=keep_connected(a) if name=='body_segment' else 0
        path=OUT/(name+'.vox')
        if name=='body_segment': write_vox(path,a)
        decoded,palette=read_vox(path)
        assert np.array_equal(decoded,a),'VOX round-trip changed voxel data'
        if pal is not None: assert pal[:len(PALETTE)*4]==palette[:len(PALETTE)*4]
        pal=palette
        comp=components(decoded)
        assert len(comp)==1, (name,comp)
        xyz=np.argwhere(a)
        report['parts'][name]={'canvas':list(a.shape),'occupied_min':xyz.min(0).tolist(),
            'occupied_max':xyz.max(0).tolist(),'voxels':int(np.count_nonzero(a)),
            'connected_components':len(comp),'raster_fragments_removed':removed,
            'vox_round_trip':'PASS','bytes':path.stat().st_size,
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    b=parts['body_segment']
    assert np.array_equal(b,b[::-1,:,:]),'Body must be exactly X-symmetric in shape and colour'
    assert np.array_equal(b[:,:,0],b[:,:,-1])
    assert np.array_equal(parts['head'][:,:,0],b[:,:,-1])
    assert np.array_equal(parts['tail'][:,:,-1],b[:,:,0])
    # The mouth's central airway is open toward +Z, parallel to the repeat axis.
    assert not np.any(parts['head'][30:34,30:34,16:])
    assert np.all(parts['head'][30:34,30:34,0:14]>0)
    assert len(components(assembly(parts)))==1
    report['head_orientation']={'mouth_direction':'+Z','body_axis':'+Z',
        'central_airway_open_to_positive_z':True}
    report['joints']={'identical_geometry_and_color':True,'contact_voxels':int(np.count_nonzero(connection())),
        'body_pitch':56,'socket_center_xy':[32,32],'assembled_components':1}
    report['body_x_symmetry']={'geometry':True,'colors':True}
    for name,before in preserved.items():
        assert (OUT/(name+'.vox')).read_bytes()==before, name+' must remain byte-for-byte unchanged'
    report['preserved_files']={name:{'byte_identical':True,'sha256':hashlib.sha256(data).hexdigest()}
                               for name,data in preserved.items()}
    (OUT/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    (OUT/'palette.json').write_text(json.dumps({str(i+1):'#%02X%02X%02X'%c for i,c in enumerate(PALETTE)},indent=2)+'\n')
    print(json.dumps(report,indent=2),flush=True)
    previews(parts)
    print('Preview sheets complete.',flush=True)

if __name__=='__main__':main()
