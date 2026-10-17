"""Signus / Hallowed Eclipse. Integer voxel sculpture and MagicaVoxel scene.

Requires only NumPy and Pillow. The preview is rendered from the exported voxels.
World: +Z up, -Y forward. No external meshes, images, or texture projection.
"""
from pathlib import Path
import struct, json, math, hashlib
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PRE = ROOT / 'previews'
SHAPE = (120, 96, 160)
BIAS = np.array([60, 48, 0])
X, Y, Z = np.meshgrid(np.arange(120, dtype=np.float32)-59.5,
                     np.arange(96, dtype=np.float32)-47.5,
                     np.arange(160, dtype=np.float32)+.5, indexing='ij')
PALETTE = [
    ('Void',           '#100e20'),  # 1
    ('Ink',            '#20172f'),  # 2
    ('Black plum',     '#30203e'),  # 3
    ('Midnight',       '#2b203f'),  # 4
    ('Deep violet',    '#422d58'),  # 5
    ('Royal plum',     '#59396a'),  # 6
    ('Amethyst',       '#755080'),  # 7
    ('Dusty orchid',   '#946798'),  # 8
    ('Lavender',       '#af87ba'),  # 9
    ('Lilac silver',   '#d0b2d8'),  # 10
    ('Pearl',          '#eee0f1'),  # 11
    ('Aubergine',      '#48233f'),  # 12
    ('Wine',           '#652b54'),  # 13
    ('Mulberry',       '#873b6d'),  # 14
    ('Rose magenta',   '#ad4c88'),  # 15
    ('Orchid pink',    '#d16bab'),  # 16
    ('Bright pink',    '#f395d4'),  # 17
    ('Spectral pink',  '#ffd3f2'),  # 18
    ('Luminous pearl', '#fff0fc'),  # 19
    ('Opal violet',    '#976fe3'),  # 20
    ('Opal blue',      '#91b4e9'),  # 21
    ('Opal mint',      '#b5e4d9'),  # 22
    ('Opal gold',      '#f1d8ad'),  # 23
    ('Opal coral',     '#e5a0ba'),  # 24
]
RGB = np.array([tuple(bytes.fromhex(h[1:])) for _, h in PALETTE], dtype=np.uint8)
ROOT_PIVOT = np.array([0,0,80])
PIVOTS = {
    '01 Core and Thorn Mantle': np.array([0,0,80]),
    '02 Hood and Visage': np.array([0,-3,108]),
    '03 Left Crescent Sleeve': np.array([-27,-2,94]),
    '04 Right Crescent Sleeve': np.array([27,-2,94]),
}

def blank(): return np.zeros(SHAPE, dtype=np.uint8)

def loft(a, rows, base=5, power=2.0, decorate=None):
    """Solid sculpted vertical loft: z, center x/y, half width/depth."""
    rows=np.array(rows, float)
    zz=Z[0,0,:]
    cx,cy,rx,ry=[np.interp(zz, rows[:,0], rows[:,i])[None,None,:] for i in range(1,5)]
    u=(X-cx)/np.maximum(rx,.5); v=(Y-cy)/np.maximum(ry,.5)
    r=np.abs(u)**power+np.abs(v)**power
    m=(Z>=rows[0,0])&(Z<=rows[-1,0])&(r<=1)
    a[m]=base
    if decorate: decorate(a,m,u,v,r)
    return m

def tube(a, pts, widths, colors, aspect=(1,1,1)):
    """Locally evaluated solid taper. Colors are bands across its cross section."""
    pts=np.array(pts,float); asp=np.array(aspect,float)
    for j in range(len(pts)-1):
        p,q=pts[j],pts[j+1]
        rad=max(widths[j:j+2])*asp+2
        low=np.maximum(np.floor(np.minimum(p,q)-rad+BIAS).astype(int),0)
        high=np.minimum(np.ceil(np.maximum(p,q)+rad+BIAS).astype(int),SHAPE)
        sl=tuple(slice(l,h) for l,h in zip(low,high))
        xx,yy,zz=X[sl],Y[sl],Z[sl]
        d=(q-p)/asp
        dx,dy,dz=(xx-p[0])/asp[0],(yy-p[1])/asp[1],(zz-p[2])/asp[2]
        t=np.clip((dx*d[0]+dy*d[1]+dz*d[2])/max(np.dot(d,d),1e-6),0,1)
        rr=widths[j]*(1-t)+widths[j+1]*t
        ex,ey,ez=dx-t*d[0],dy-t*d[1],dz-t*d[2]
        dist=ex*ex+ey*ey+ez*ez
        m=dist<=np.maximum(rr,.65)**2
        target=a[sl]
        if len(colors)==1: target[m]=colors[0]
        else:
            c=np.where(ey < -rr*.35,colors[-1],np.where(ex>rr*.45,colors[0],colors[len(colors)//2]))
            target[m]=c[m]

def front_inlay(a, xz, width, color, offset=0, depth=2):
    """Follow the actual front surface with an integral, opaque raised seam."""
    xx,zz=np.meshgrid(np.arange(SHAPE[0])-59.5,np.arange(SHAPE[2])+.5,indexing='ij')
    footprint=np.zeros((SHAPE[0],SHAPE[2]),bool)
    for (x0,z0),(x1,z1) in zip(xz[:-1],xz[1:]):
        dx,dz=x1-x0,z1-z0
        t=np.clip(((xx-x0)*dx+(zz-z0)*dz)/max(dx*dx+dz*dz,1e-6),0,1)
        footprint|=(xx-x0-t*dx)**2+(zz-z0-t*dz)**2<=width*width
    for ix,iz in np.argwhere(footprint):
        hits=np.flatnonzero(a[ix,:,iz])
        if len(hits):
            iy=max(0,int(hits[0])+offset)
            a[ix,max(0,iy-1):iy+depth,iz]=color

def build_core():
    a=blank()
    # The lower body is a group of three thick, curved stone-like folds, with
    # open negative space between the tips. All join the same torso.
    def lower(a,m,u,v,r):
        a[m&(np.abs(u)>.72)]=3
        a[m&(v<-.35)&(np.abs(u)<.72)]=5
        a[m&(v<-.5)&(u>.22)&(u<.58)]=6
        a[m&(v>.6)&(np.abs(u)<.48)]=5
    loft(a,[(7,-7,24,1.5,2),(15,-2,23,5,5),(28,6,17,10,8),
            (43,3,10,14,11),(59,0,3,17,14),(75,0,1,18,15)],4,1.45,lower)
    def left_fold(a,m,u,v,r):
        a[m&(v<-.3)]=5
        a[m&(v<-.5)&(u<-.25)]=6
        a[m&(u<-.8)]=4
        a[m&(v>.3)&(u<-.4)]=5
    loft(a,[(18,-28,17,1.4,2),(26,-29,14,5,7),(40,-24,6,9,12),
            (56,-17,1,12,14),(73,-11,1,12,15),(83,-8,1,12,14)],4,1.4,left_fold)
    def right_fold(a,m,u,v,r):
        a[m&(v<-.35)]=5
        a[m&(v<-.55)&(u>.15)]=6
        a[m&(u>.8)]=3
    loft(a,[(24,28,19,1.5,2),(34,28,13,6,8),(49,21,4,10,12),
            (65,14,0,13,14),(82,9,0,14,15)],4,1.4,right_fold)
    # Ribbed breast and waist, deliberately narrower than the massive mantle.
    def torso(a,m,u,v,r):
        a[m&(v<-.35)]=5
        a[m&(v<-.55)&(np.abs(u)<.5)]=6
        a[m&(v<-.65)&(np.abs(u)<.16)]=4
        a[m&(v>.55)&(np.abs(u)<.55)]=6
    loft(a,[(59,0,2,16,13),(69,0,0,17,14),(81,0,0,22,16),
            (94,0,2,28,18),(102,0,3,23,16),(110,0,3,13,11)],4,2,torso)
    # A solid elliptical cowl: angular lowered front, raised side shoulders,
    # with two distinct wrapped courses instead of a flat extruded collar.
    theta=np.arctan2(Y-2,X)
    radial=np.sqrt((X/37)**2+((Y-2)/23)**2)
    bottom=88+8*np.abs(X)/37+np.maximum(Y,0)*.17+X*.07
    top=110-10*np.abs(X)/37+np.maximum(Y,0)*.06+X*.07
    m=(radial<=1)&(Z>=bottom)&(Z<=top)
    a[m]=5
    a[m&(radial>.80)]=6
    a[m&(Z<bottom+3)]=3
    a[m&(Z>=bottom+3)&(Z<bottom+5)]=8
    a[m&(Z>=bottom+5)&(Z<bottom+8)]=14
    a[m&(Z>top-3)]=5
    a[m&(Y<0)&(Z>=bottom+8)&(Z<bottom+11)]=7
    # The high rear collar cups the hood and is visible on every side.
    collar_top=103+12*np.clip(Y/12,0,1)-4*np.abs(X)/37
    rear=(radial<=.84)&(radial>=.53)&(Y>0)&(Z>=103)&(Z<collar_top)
    a[rear]=5
    a[rear&(radial>.76)]=7
    # Broad diagonal overlapping wraps on the chest.
    for z0,slope,c in [(83,.26,6),(88,-.24,7)]:
        ysurf=-15.8*np.sqrt(np.clip(1-(X/27)**2,0,1))
        center=z0+slope*X
        wrap=(np.abs(X)<25)&(np.abs(Z-center)<3.3)&(Y>=ysurf-2)&(Y<=ysurf+3)
        a[wrap]=c
        a[wrap&(Z<center-1.7)]=4
        a[wrap&(Z>center+1.7)]=8
    # Pointed breast tab and opalescent lunar clasp. Only this small jewel uses
    # cyan, mint and warm hues; it remains subordinate to the violet silhouette.
    tab=(np.abs(X)<np.interp(Z,[66,73,86],[.5,8,10]))&(Z>66)&(Z<87)&(Y>=-19)&(Y<=-14)
    a[tab]=3
    a[tab&(np.abs(X)<2)&(Z<78)]=7
    cres=np.sqrt((X/6.2)**2+((Z-84)/6.2)**2)
    cut=np.sqrt((X/5.2)**2+((Z-86)/5.2)**2)
    m=(cres<=1)&(cut>=1)&(Z<87)&(Y>=-21)&(Y<=-17)
    a[m]=9
    a[m&(Y< -20)]=10
    gem=(np.abs(X)/2.6+np.abs(Z-84)/4<1)&(Y>=-22)&(Y<=-18)
    a[gem]=20
    a[gem&(X<0)&(Z>84)]=21
    a[gem&(X>=0)&(Z>84)]=22
    a[gem&(X<0)&(Z<=84)]=24
    a[gem&(X>=0)&(Z<=84)]=23
    a[gem&(np.abs(X)<1)&(np.abs(Z-84)<2)&(Y<-21)]=19
    # Integral fold seams on the lower sculpt. Wide details survive gameplay.
    front_inlay(a,[(-10,70),(-17,58),(-24,42),(-28,28)],1.15,7)
    front_inlay(a,[(11,71),(18,58),(23,47),(27,35)],1.15,7)
    front_inlay(a,[(1,62),(6,46),(10,33),(5,22)],1.2,7)
    # Dark thorn crown grows from the rear mantle. Four solid swept horns,
    # attached to the body, rather than floating particle or attack effects.
    for s in (-1,1):
        height=0 if s==1 else -7
        tube(a,[(s*22,14,101),(s*32,18,111),(s*39,23,123+height),(s*40,24,132+height),
                (s*36,23,136+height)], [5.5,4.5,2.7,1.6,.8],[2,3,5])
        tube(a,[(s*27,17,104),(s*37,20,109),(s*46,24,116+height*.5),(s*50,24,121+height*.5)],
             [4,3.2,1.8,.7],[2,3,4])
        # Sparse inner orchid edge, stopping before the sharp dark tip.
        tube(a,[(s*27,11,107),(s*33,15,115+height*.5),(s*37,19,124+height)], [1.3,1,.7],[6])
    # An intentionally modeled dorsal keel and two large folded reliefs.
    tube(a,[(0,17,103),(0,22,88),(0,19,72),(3,21,52),(9,23,32)],
         [3,3.5,3,2.6,1],[4,6,7])
    for s in (-1,1):
        tube(a,[(s*23,15,98),(s*18,21,89),(s*11,20,79),(s*8,18,68)],
             [2,2.2,1.8,.9],[6,7,8])
    front_inlay(a[:,::-1,:],[(-5,89),(0,95),(5,89),(0,81),(-5,89)],.9,8)
    return a

def build_hood():
    a=blank()
    # A real deep hood, narrowing to a backward-curved peak in three dimensions.
    def hood_color(a,m,u,v,r):
        a[m&(np.abs(u)>.70)]=5
        a[m&(v>.15)&(np.abs(u)<.76)]=6
        a[m&(v>.5)&(np.abs(u)<.35)]=7
    loft(a,[(104,0,0,14,12),(111,0,-1,19,16),(124,0,-1,20,18),
            (136,0,0,16,16),(144,2,4,11,12),(150,7,9,6,7),
            (153,12,14,1.2,1.5)],5,1.85,hood_color)
    # Gothic opening: point at 141, broad temples, tapered lower jaw.
    w=np.interp(Z,[113,118,126,132,137,141,142],[2,9,12.5,12,7,1,0])
    arch=(Z>=113)&(Z<=141)&(np.abs(X)<=w)
    # Recessed face is sculpted into the hood with a dark solid rear surface.
    face_y=-7-2*(1-(X/15)**2)
    cavity=arch&(Y<face_y)
    a[cavity]=0
    lining=arch&(Y>=face_y)&(Y<face_y+3)
    a[lining]=1
    # A thick stepped, rosy inner opening lip and lavender outer bevel.
    inner=(Z>=113)&(Z<=142)&(np.abs(X)>w)&(np.abs(X)<=w+2.3)&(Y<-8)&(a>0)
    a[inner]=14
    bevel=(Z>=115)&(Z<=143)&(np.abs(X)>w+2.3)&(np.abs(X)<w+3.7)&(Y<-9)&(a>0)
    a[bevel]=9
    a[bevel&(Z>133)]=10
    # Firm tapered hood lappets frame the open void; each is part of the hood.
    for s in (-1,1):
        tube(a,[(s*16,-9,119),(s*17,-11,109),(s*12,-14,102)],
             [4,3.7,1.1],[3,5,6],aspect=(1,.7,1))
    # Eyes are sparse spectral cuts rather than an expressive humanoid mask.
    # They sit on the recessed face; the large dark gap is preserved.
    for s in (-1,1):
        ax=s*X
        eye=(ax>=3)&(ax<=9)&(np.abs(Z-(127+(ax-3)*.20))<=1.15)&(Y>=-10)&(Y<=-7)
        a[eye]=16
        a[eye&(ax<5)&(Y<-9)]=18
    # A thick diagonal lower wrap conceals the chin; the two eyes are the focal
    # marks. There is deliberately no mouth expression, teeth, or facial skin.
    tube(a,[(-16,-9,109),(-7,-14,111),(3,-16,113),(14,-12,117)],
         [3.1,3.3,3,2.5],[3,5,7],aspect=(1,.8,1))
    # Dorsal seam follows the hood's actual surface, not a sprite extrusion.
    for zz in range(112,148):
        for xx in range(59,62):
            hits=np.flatnonzero(a[xx,:,zz])
            if len(hits): a[xx,hits[-1],zz]=8
    return a

def build_sleeve(s):
    a=blank()
    def col(a,m,u,v,r):
        a[m&(v<-.25)]=5
        a[m&(v<-.5)&(u*s>.15)]=6
        a[m&(u*s>.72)]=4
        a[m&(v>.5)]=5
    # Self-supporting, tapered crescent lobes, intentionally no fingers or chains.
    rows=[(50,s*35,6,1.3,2),(56,s*39,3,4.5,6),(66,s*38,-1,8,10),
          (78,s*34,-2,10,12),(88,s*31,0,11,12),(98,s*27,2,9,10)]
    loft(a,rows,4,1.45,col)
    # Solid hooked sleeve cuff around a dark recess.
    tube(a,[(s*30,-5,90),(s*37,-8,80),(s*41,-7,69),(s*40,-5,61)],
         [2.7,2.7,2.2,.9],[8,14,15])
    front_inlay(a,[(s*29,91),(s*33,83),(s*36,73),(s*37,65)],1.1,9)
    # One bold inlaid diamond on each sleeve, backed by solid geometry.
    for xx in range(SHAPE[0]):
        for zz in range(69,80):
            if abs((xx-59.5)-s*35)/3+abs(zz+.5-74)/5>1:continue
            hits=np.flatnonzero(a[xx,:,zz])
            if len(hits):
                yy=hits[0]
                a[xx,yy:yy+2,zz]=14 if abs(zz+.5-74)>2 else 16
    return a

def components(a, clean=False):
    occ=a>0; seen=np.zeros(a.shape,bool); sizes=[]; groups=[]
    for start in np.argwhere(occ):
        key=tuple(start)
        if seen[key]:continue
        q=[key];seen[key]=True; group=[]
        while q:
            p=q.pop();group.append(p)
            for axis in range(3):
                for d in (-1,1):
                    n=list(p);n[axis]+=d
                    if n[axis]<0 or n[axis]>=a.shape[axis]:continue
                    n=tuple(n)
                    if occ[n] and not seen[n]:seen[n]=True;q.append(n)
        sizes.append(len(group));groups.append(group)
    if clean and len(sizes)>1:
        largest=int(np.argmax(sizes))
        for i,g in enumerate(groups):
            if i!=largest:
                assert len(g)<100, ('unexpected disconnected designed feature',len(g))
                a[tuple(np.array(g).T)]=0
    return sorted(sizes,reverse=True)

def fill_enclosed_air(a):
    # Flood external empty space. Any fully enclosed accidental bubble is filled
    # with the core material, preventing invisible internal surface geometry.
    empty=a==0; seen=np.zeros(a.shape,bool)
    frontier=np.zeros(a.shape,bool)
    for ax in range(3):
        for val in (0,-1):
            sl=[slice(None)]*3;sl[ax]=val
            frontier[tuple(sl)]=empty[tuple(sl)]
    seen|=frontier
    while frontier.any():
        nb=np.zeros(a.shape,bool)
        for ax in range(3):
            s0=[slice(None)]*3;s1=[slice(None)]*3
            s0[ax]=slice(0,-1);s1[ax]=slice(1,None)
            nb[tuple(s0)]|=frontier[tuple(s1)]
            nb[tuple(s1)]|=frontier[tuple(s0)]
        frontier=nb&empty&~seen;seen|=frontier
    enclosed=empty&~seen
    a[enclosed]=4
    return int(enclosed.sum())

def chunk(tag, content=b'', children=b''):
    return tag+struct.pack('<II',len(content),len(children))+content+children

def dictionary(d):
    b=struct.pack('<i',len(d))
    for k,v in d.items():
        for val in (k,str(v)):
            q=val.encode('utf8');b+=struct.pack('<i',len(q))+q
    return b

def write_vox(parts,path):
    data=b'';model_info=[]
    for name,a in parts.items():
        xyz=np.argwhere(a)
        occupied_lo=xyz.min(0);occupied_hi=xyz.max(0)+1
        # Give the actual model-center pivots useful anatomical positions.
        # Empty canvas padding has no XYZI storage or runtime geometry cost.
        pivot=PIVOTS[name]+BIAS
        half=np.maximum(pivot-occupied_lo,occupied_hi-pivot)
        dims=2*half;lo=pivot-half
        assert (dims<=256).all()
        local=xyz-lo
        colors=a[tuple(xyz.T)]
        records=np.column_stack([local,colors]).astype(np.uint8)
        data+=chunk(b'SIZE',struct.pack('<3i',*dims))
        data+=chunk(b'XYZI',struct.pack('<I',len(records))+records.tobytes())
        # MagicaVoxel rotates each object about the center of its SIZE bounds.
        t=PIVOTS[name]-ROOT_PIVOT
        model_info.append({'name':name,'size':dims.tolist(),'translation':t.tolist(),
                           'pivot_world':PIVOTS[name].tolist(),
                           'min_world':(occupied_lo-BIAS).tolist(),'voxel_count':len(xyz)})
    data+=chunk(b'RGBA',b''.join(bytes(c)+b'\xff' for c in RGB)+bytes([0,0,0,255])*(256-len(RGB)))
    data+=chunk(b'nTRN',struct.pack('<i',0)+dictionary({'_name':'Signus - Hallowed Eclipse'})+
                struct.pack('<4i',1,-1,-1,1)+dictionary({'_t':'0 0 80','_r':'4'}))
    data+=chunk(b'nGRP',struct.pack('<i',1)+dictionary({})+struct.pack('<i',len(parts))+
                b''.join(struct.pack('<i',2+i*2) for i in range(len(parts))))
    for i,info in enumerate(model_info):
        trn=2+i*2;shp=trn+1
        data+=chunk(b'nTRN',struct.pack('<i',trn)+dictionary({'_name':info['name']})+
                    struct.pack('<4i',shp,-1,0,1)+dictionary({'_t':' '.join(map(str,info['translation'])),'_r':'4'}))
        data+=chunk(b'nSHP',struct.pack('<i',shp)+dictionary({})+struct.pack('<2i',1,i)+dictionary({}))
    data+=chunk(b'LAYR',struct.pack('<i',0)+dictionary({'_name':'Boss components','_hidden':'0'})+struct.pack('<i',-1))
    for idx in (17,18,19):
        data+=chunk(b'MATL',struct.pack('<i',idx)+dictionary({'_type':'_emit','_weight':'0.20','_emit':'0.20','_flux':'0','_ldr':'0.20','_alpha':'1'}))
    data+=chunk(b'NOTE',struct.pack('<i',len(PALETTE))+b''.join(struct.pack('<i',len(n.encode()))+n.encode() for n,_ in PALETTE))
    path.write_bytes(b'VOX '+struct.pack('<i',150)+chunk(b'MAIN',children=data))
    return model_info

def read_vox(path):
    raw=path.read_bytes();assert raw[:4]==b'VOX ' and struct.unpack_from('<i',raw,4)[0]==150
    assert raw[8:12]==b'MAIN';assert struct.unpack_from('<i',raw,12)[0]==0
    assert struct.unpack_from('<i',raw,16)[0]+20==len(raw)
    pos=20;models=[];nodes={};palette=None;dims=None
    def rd_dict(b,o):
        count=struct.unpack_from('<i',b,o)[0];o+=4;d={}
        for _ in range(count):
            vals=[]
            for _ in range(2):
                n=struct.unpack_from('<i',b,o)[0];o+=4
                vals.append(b[o:o+n].decode());o+=n
            d[vals[0]]=vals[1]
        return d,o
    while pos<len(raw):
        tag=raw[pos:pos+4];n,ch=struct.unpack_from('<II',raw,pos+4)
        assert ch==0 and pos+12+n<=len(raw)
        b=raw[pos+12:pos+12+n];pos+=12+n
        if tag==b'SIZE':dims=struct.unpack('<3i',b)
        elif tag==b'XYZI':
            count=struct.unpack_from('<i',b)[0]
            q=np.frombuffer(b[4:],np.uint8).reshape(-1,4)
            assert len(q)==count and len(np.unique(q[:,:3],axis=0))==count
            assert (q[:,:3]<dims).all() and (q[:,3]>0).all() and (q[:,3]<=len(RGB)).all()
            models.append((dims,q.copy()))
        elif tag==b'RGBA':
            assert len(b)==1024;palette=np.frombuffer(b,np.uint8).reshape(256,4)
        elif tag in (b'nTRN',b'nGRP',b'nSHP'):
            ident=struct.unpack_from('<i',b)[0];attrs,o=rd_dict(b,4)
            assert ident not in nodes
            node={'type':tag.decode(),'attrs':attrs}
            if tag==b'nTRN':
                child,res,layer,frames=struct.unpack_from('<4i',b,o);o+=16
                assert res==-1 and frames==1
                frame,o=rd_dict(b,o);node.update(child=child,frame=frame)
            elif tag==b'nGRP':
                count=struct.unpack_from('<i',b,o)[0];o+=4
                node['children']=struct.unpack_from('<'+'i'*count,b,o);o+=count*4
            else:
                count,mid=struct.unpack_from('<2i',b,o);o+=8
                assert count==1
                mattrs,o=rd_dict(b,o);node['model']=mid
            assert o==len(b);nodes[ident]=node
    assert np.array_equal(palette[:len(RGB),:3],RGB) and (palette[:,3]==255).all()
    parts={}
    assert nodes[0]['child']==1
    root_t=np.array(list(map(int,nodes[0]['frame']['_t'].split())))
    assert nodes[0]['frame']['_r']=='4'
    for child in nodes[1]['children']:
        tr=nodes[child];sh=nodes[tr['child']]
        dims,q=models[sh['model']]
        assert tr['frame']['_r']=='4'
        t=np.array(list(map(int,tr['frame']['_t'].split())))
        xyz=q[:,:3].astype(int)-np.array(dims)//2+t+root_t+BIAS
        assert (xyz>=0).all() and (xyz<SHAPE).all()
        a=blank();a[tuple(xyz.T)]=q[:,3]
        parts[tr['attrs']['_name']]=a
    assert len(parts)==len(models)==4
    return parts

def merge(parts):
    a=blank()
    for p in parts.values():a[p>0]=p[p>0]
    return a

def surface_faces(a):
    occ=np.pad(a>0,1)
    total=0
    for axis in range(3):
        for direction in (-1,1):
            sl=[slice(1,-1)]*3
            sl[axis]=slice(2,None) if direction>0 else slice(None,-2)
            total+=np.count_nonzero((a>0)&~occ[tuple(sl)])
    return int(total)

def render(a,az=-65,el=14,size=(650,850),scale=None,bg=(27,25,39)):
    """Orthographic unit cube faces; lighting is preview-only, never in VOX."""
    az,el=math.radians(az),math.radians(el)
    view=np.array([math.cos(az)*math.cos(el),math.sin(az)*math.cos(el),math.sin(el)])
    right=np.array([-math.sin(az),math.cos(az),0]);up=np.cross(view,right)
    xyz=np.argwhere(a);center=(xyz.min(0)+xyz.max(0)+1)/2
    bounds=np.array([[x,y,z] for x in (xyz[:,0].min(),xyz[:,0].max()+1)
                   for y in (xyz[:,1].min(),xyz[:,1].max()+1)
                   for z in (xyz[:,2].min(),xyz[:,2].max()+1)])-center
    ext=np.array([np.ptp(bounds@right),np.ptp(bounds@up)])
    if scale is None:scale=min((size[0]-40)/ext[0],(size[1]-40)/ext[1])
    faces=[];pad=np.pad(a,1)
    for axis in range(3):
        if abs(view[axis])<1e-8:continue
        sign=1 if view[axis]>0 else -1
        sl=[slice(1,-1)]*3;sl[axis]=slice(2,None) if sign>0 else slice(None,-2)
        p=np.argwhere((a>0)&(pad[tuple(sl)]==0))
        others=[j for j in range(3) if j!=axis]
        corners=np.zeros((4,3));corners[:,axis]=1 if sign>0 else 0
        corners[:,others[0]]=[0,1,1,0];corners[:,others[1]]=[0,0,1,1]
        verts=p[:,None,:]+corners-center
        uv=np.stack((verts@right,-verts@up),axis=-1)*scale+np.array(size)/2
        depths=(p+corners.mean(0)-center)@view
        # Neutral three-value inspection light, no glow/bloom or cast shadows.
        shade=[.82,.95,1.13][axis]
        cols=np.clip(RGB.astype(float)*shade,0,255).astype(np.uint8)
        for i in range(len(p)):
            ci=a[tuple(p[i])]-1
            color=tuple(RGB[ci] if ci in (16,17,18) else cols[ci])
            faces.append((depths[i],uv[i],color))
    faces.sort(key=lambda f:f[0])
    im=Image.new('RGB',size,bg);d=ImageDraw.Draw(im)
    for _,poly,col in faces:d.polygon([tuple(v) for v in np.rint(poly).astype(int)],fill=col)
    return im

def font(n,bold=False):
    return ImageFont.truetype('C:/Windows/Fonts/'+('segoeuib.ttf' if bold else 'segoeui.ttf'),n)

def previews(parts):
    a=merge(parts)
    render(a,-65,13,(900,1100)).save(PRE/'signus_hero.png')
    sheet=Image.new('RGB',(1800,1000),(27,25,39));d=ImageDraw.Draw(sheet)
    d.text((38,25),'SIGNUS / HALLOWED ECLIPSE',font=font(30,True),fill=(238,224,241))
    d.text((40,70),'VOXEL SCULPTURE     /     FOUR RIGID COMPONENTS     /     +Z UP, -Y FORWARD',font=font(16),fill=(175,158,190))
    for i,(az,el,label) in enumerate([(-90,0,'FRONT'),(-55,12,'THREE QUARTER'),(0,0,'SIDE'),(70,15,'REAR')]):
        im=render(a,az,el,(440,800),scale=4.5)
        sheet.paste(im,(20+i*445,125));d.text((40+i*445,942),label,font=font(18,True),fill=(208,178,216))
    sheet.save(PRE/'signus_multiview.png')
    # Small gameplay-distance check using the actual exported face and silhouette.
    thumb=render(a,-90,0,(128,180))
    thumb.resize((512,720),Image.Resampling.NEAREST).save(PRE/'signus_gameplay_scale.png')

def main():
    parts={'01 Core and Thorn Mantle':build_core(),'02 Hood and Visage':build_hood(),
           '03 Left Crescent Sleeve':build_sleeve(-1),'04 Right Crescent Sleeve':build_sleeve(1)}
    report={'title':'Signus - Hallowed Eclipse','up':'+Z','forward':'-Y','palette_colors':len(RGB),'parts':{}}
    # Center occupied horizontal bounds, retaining identical assembled alignment.
    coords=np.argwhere(merge(parts));center_xy=(coords.min(0)[:2]+coords.max(0)[:2]+1)//2
    shift=BIAS[:2]-center_xy
    for name,a in parts.items():
        parts[name]=np.roll(a,tuple(shift),axis=(0,1))
    # Resolve intersections by ownership. No duplicated voxels between objects.
    # The hood and sleeves retain their geometry; concealed torso voxels are cut.
    occupied=np.zeros(SHAPE,bool)
    for name in reversed(list(parts)):
        a=parts[name];overlap=(a>0)&occupied
        a[overlap]=0
        comp=components(a,clean=True)
        filled=fill_enclosed_air(a)
        occupied|=a>0
        report['parts'][name]={'intersecting_voxels_removed':int(overlap.sum()),
                             'raster_fragments_removed':sum(comp[1:]),'enclosed_air_filled':filled}
    combined=merge(parts);solid=combined.copy()
    sealed=fill_enclosed_air(solid)
    parts['01 Core and Thorn Mantle'][(combined==0)&(solid>0)]=4
    report['assembly_enclosed_air_filled']=sealed
    path=ROOT/'signus_hallowed_eclipse.vox'
    info=write_vox(parts,path)
    decoded=read_vox(path)
    for inf in info:
        name=inf['name'];a=parts[name]
        assert np.array_equal(a,decoded[name]),'Scene transform or voxel data round-trip failed'
        comp=components(decoded[name]);assert len(comp)==1,(name,comp)
        report['parts'][name].update(inf,connected_components=1,exposed_unit_faces=surface_faces(a))
    full=merge(decoded);xyz=np.argwhere(full)
    assert sum(np.count_nonzero(p) for p in decoded.values())==np.count_nonzero(full)
    assert len(components(full))==1
    assert fill_enclosed_air(full.copy())==0
    assert np.array_equal((xyz.min(0)+xyz.max(0)+1)[:2],2*BIAS[:2])
    report.update(format='MagicaVoxel VOX 150 with named scene graph',
                  occupied_dimensions=(xyz.max(0)-xyz.min(0)+1).tolist(),
                  world_min=(xyz.min(0)-BIAS).tolist(),world_max_exclusive=(xyz.max(0)+1-BIAS).tolist(),
                  voxel_count=int(np.count_nonzero(full)),all_palette_alpha=255,
                  duplicate_occupied_positions=0,round_trip='PASS',
                  centered_horizontal_bounds=True,root_pivot_world=ROOT_PIVOT.tolist(),
                  assembled_connected_components=1,enclosed_empty_cells=0,
                  assembled_exposed_unit_faces=surface_faces(full),
                  bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (ROOT/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2),flush=True)
    previews(decoded)
    print('All previews rendered from decoded VOX scene.',flush=True)

if __name__=='__main__':main()
