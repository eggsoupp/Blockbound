"""Blockbound biome trees: deterministic solid voxel sculpt, VOX export and previews.

Requires Python, NumPy and Pillow. Run this file to regenerate this asset pack.
All geometry consists of opaque unit cubes. +Z is up; ground is z=0.
"""
from pathlib import Path
from collections import deque
import math
import struct
import json
import hashlib
import zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SHAPE = (80, 80, 112)
X, Y, Z = np.indices(SHAPE, dtype=np.float32)
X -= 39.5
Y -= 39.5
Z += .5
PALETTE = [
    ('Bark shadow', '#38271f'), ('Bark umber', '#543a29'),
    ('Bark brown', '#735037'), ('Bark ochre', '#926746'),
    ('Bark cut', '#b38a59'), ('Bark highlight', '#c5a36d'),
    ('Pine deep', '#163e32'), ('Pine shade', '#20553b'),
    ('Pine green', '#2f7143'), ('Pine fern', '#46934b'),
    ('Pine leaf', '#66ac53'), ('Pine lime', '#8dc561'),
    ('Pine light', '#b2d47c'),
    ('Corrupt bark deep', '#231d30'), ('Corrupt bark', '#382c48'),
    ('Corrupt bark light', '#51405d'), ('Corrupt grain', '#715374'),
    ('Violet deep', '#302044'), ('Violet shade', '#493060'),
    ('Violet plum', '#654181'), ('Violet', '#8556a6'),
    ('Violet orchid', '#a370c2'), ('Violet light', '#c396da'),
    ('Violet tip', '#dfb8ec'), ('Rift accent', '#d7b5fc'),
    ('Crimson bark deep', '#321d26'), ('Crimson bark', '#502733'),
    ('Crimson bark light', '#723b43'), ('Crimson grain', '#975354'),
    ('Crimson deep', '#501c33'), ('Crimson shade', '#792239'),
    ('Crimson wine', '#a12d41'), ('Crimson red', '#c63e4c'),
    ('Crimson coral', '#e25c5a'), ('Crimson light', '#f57c6d'),
    ('Crimson tip', '#ffa389'),
]
RGB = np.array([tuple(bytes.fromhex(h[1:])) for _, h in PALETTE], dtype=np.uint8)


def blank():
    return np.zeros(SHAPE, dtype=np.uint8)


def tube(a, points, radii, colors):
    """Solid, tapered wood with long blocky grain, not random per-voxel noise."""
    for k in range(len(points)-1):
        p = np.asarray(points[k], float)
        v = np.asarray(points[k+1], float)-p
        t = np.clip(((X-p[0])*v[0]+(Y-p[1])*v[1]+(Z-p[2])*v[2]) / max(v@v, .01), 0, 1)
        r = radii[k]*(1-t)+radii[k+1]*t
        dx, dy, dz = X-p[0]-t*v[0], Y-p[1]-t*v[1], Z-p[2]-t*v[2]
        mask = dx*dx+dy*dy+dz*dz <= np.maximum(r, .85)**2
        grain = (np.floor((X+2)/2)*13+np.floor(Y/2)*7+np.floor(Z/9)*3).astype(int)%11
        shade = np.where(grain<2, colors[0], np.where(grain>8, colors[-1], colors[1]))
        a[mask] = shade[mask]


def roots(a, colors, tilt=0, seed=1):
    rng = np.random.default_rng(seed)
    for i in range(6):
        th = i*math.tau/6+.18
        length = rng.uniform(10, 15)
        tip = (math.cos(th)*length, math.sin(th)*length, .6)
        middle = (math.cos(th)*6+tilt, math.sin(th)*6, 3)
        tube(a, [(tilt, 0, 9), middle, tip], [4, 2.6, 1.1], colors)


def foliage(a, center, radii, first, seed=0, step=2):
    """Squared leaf pillows, stepped every 2 voxels, with large colour patches."""
    cx, cy, cz = center
    rx, ry, rz = radii
    qx = np.floor(X/step)*step+step/2
    qy = np.floor(Y/step)*step+step/2
    qz = np.floor(Z/step)*step+step/2
    u, v, w = (qx-cx)/rx, (qy-cy)/ry, (qz-cz)/rz
    # Squared forms echo the blocky reference without looking like smooth spheres.
    power = 2.65
    field = abs(u)**power+abs(v)**power+abs(w)**power
    mask = field <= 1
    patch = (np.floor((X+seed)/5)*17 + np.floor((Y-seed)/5)*29 + np.floor(Z/5)*13).astype(int)%17
    shade = np.where(w<-.44, 1, np.where(w<.12, 2, np.where(w<.63, 3, 4)))
    shade += np.where(patch<3, -1, np.where(patch>13, 1, 0))
    shade = np.clip(shade, 0, 5)
    a[mask] = (first+shade[mask]).astype(np.uint8)


def leaf_ring(a, center, radius, lobes, lobe_size, first, seed, phase=0):
    rng = np.random.default_rng(seed)
    for i in range(lobes):
        angle = i*math.tau/lobes+phase
        cx = center[0]+math.cos(angle)*radius
        cy = center[1]+math.sin(angle)*radius
        cz = center[2]+rng.uniform(-2, 2)
        rr = tuple(v*rng.uniform(.92, 1.08) for v in lobe_size)
        foliage(a, (cx, cy, cz), rr, first, seed+i)


def sprigs(a, first, seed, count=145):
    """Attached cube-shaped leaf shoots interrupt the large canopy surfaces."""
    rng = np.random.default_rng(seed)
    occ = np.pad(a>0,1); candidates=[]
    for axis,sign in [(0,-1),(0,1),(1,-1),(1,1),(2,1)]:
        sl=[slice(1,-1)]*3;sl[axis]=slice(2,None) if sign>0 else slice(None,-2)
        positions=np.argwhere((a>0)&~occ[tuple(sl)])
        candidates.extend((tuple(p),axis,sign) for p in positions)
    used=[]
    for idx in rng.permutation(len(candidates)):
        p,axis,sign=candidates[idx];p=np.array(p)
        if any(np.sum((p-q)**2)<36 for q in used):
            continue
        width=int(rng.integers(3,6));lo=p-width//2;hi=lo+width
        if sign>0:lo[axis]=p[axis]-1;hi[axis]=p[axis]+width-1
        else:lo[axis]=p[axis]-width+2;hi[axis]=p[axis]+2
        lo=np.maximum(lo,0);hi=np.minimum(hi,SHAPE)
        color=int(np.clip(int(a[tuple(p)])+rng.integers(0,2),first+1,first+5))
        a[tuple(slice(l,h) for l,h in zip(lo,hi))]=color
        used.append(p)
        if len(used)>=count:break


def normal():
    wood, leaf = blank(), blank()
    tube(wood, [(0,0,2),(0,0,24),(-1,0,46),(0,0,72),(0,0,91)], [5.4,4.6,3.7,2.4,1], [1,3,4])
    roots(wood, [1,3,4])
    # Four overlapping whorls. Their central foliage remains connected around wood.
    for j, (height, radius, width, thick, count) in enumerate([
            (42,15,14,10,7), (57,12,12,10,6), (71,9,10,10,5), (84,5,8,9,4)]):
        foliage(leaf, (0,0,height+3), (radius+5,radius+5,thick+4), 7, j)
        leaf_ring(leaf, (0,0,height), radius, count, (width,width*.88,thick), 7, 10+j, j*.8)
        for i in range(count):
            th = i*math.tau/count+j*.8
            tube(wood, [(0,0,height-12),(math.cos(th)*radius*.65, math.sin(th)*radius*.65,height-3),
                        (math.cos(th)*(radius+4), math.sin(th)*(radius+4),height)], [2.5,1.7,.9], [1,3,4])
    foliage(leaf, (0,0,94), (5,5,8), 7, 18)
    # Three small stepped peak blocks make the evergreen's pointed crown.
    leaf[(abs(X)<2)&(abs(Y)<2)&(Z>=98)&(Z<104)] = 12
    sprigs(leaf,7,125,165)
    leaf[wood>0] = 0
    return wood, leaf


def corruption():
    wood, leaf = blank(), blank()
    colors = [14,15,17]
    roots(wood, colors, seed=5)
    tube(wood, [(0,0,2),(-3,1,18),(-6,1,34),(-3,0,48),(4,1,64),(7,1,86)],
         [6,5.3,4.9,4.2,3.2,1.3], colors)
    # Large crooked forks: bare hooks break out from the purple leaf mass.
    branches = [
        ([(-5,0,30),(-16,-1,43),(-22,-2,60),(-16,-1,77)], [3.5,3,2.3,1]),
        ([(-2,1,46),(13,1,52),(24,1,65),(24,1,81),(18,1,88)], [3.5,3,2.3,1.5,.85]),
        ([(3,1,58),(0,15,66),(-5,22,78)], [3,2.2,1]),
        ([(-6,0,33),(-12,-12,42),(-22,-15,48),(-29,-15,57),(-27,-15,63)], [2.4,2,1.7,1.2,.85]),
    ]
    for pts, rr in branches:
        tube(wood, pts, rr, colors)
    for i, (c,r) in enumerate([
        ((-16,0,68),(14,13,13)), ((-8,9,78),(17,14,12)),
        ((7,2,88),(15,14,13)), ((18,0,73),(12,14,11)),
        ((2,-10,72),(15,13,13)), ((-3,18,74),(11,10,11)),
        ((-19,1,57),(10,10,8)), ((2,0,60),(13,12,10)),
    ]):
        foliage(leaf,c,r,18,30+i)
    # Narrow purple hanging needles stay attached to their canopy.
    for p,h in [((-23,2,62),11),((-12,-8,63),9),((12,-14,69),13),((22,6,69),9)]:
        tube(leaf, [p,(p[0]-1,p[1],p[2]-h)], [2.2,.85], [18,19,20])
    sprigs(leaf,18,126,135)
    # Sparse longitudinal violet bark seams.
    seam = (wood>0)&(Y<-2)&(Z>14)&(Z<51)&(((np.floor(X)+np.floor(Z/8)).astype(int)%11)==0)
    wood[seam] = 20
    out = leaf.copy(); out[wood>0] = wood[wood>0]
    return out


def crimson():
    wood, leaf = blank(), blank()
    colors = [26,27,29]
    roots(wood, colors, seed=8)
    tube(wood, [(0,0,2),(2,0,18),(1,0,32),(-2,0,44),(-7,1,61),(-8,1,78)],
         [6,5.5,5,4.2,3,1.2], colors)
    branches = [
        ([(1,0,29),(11,0,42),(19,1,59),(21,1,72)], [4,3.4,2.5,1.2]),
        ([(-2,0,42),(-15,-1,49),(-25,0,60),(-26,0,72)], [3.4,2.7,1.8,.9]),
        ([(0,0,36),(1,-13,48),(6,-20,65)], [3,2.5,1]),
        ([(-5,0,50),(-2,13,59),(3,21,71)], [3,2.1,.9]),
        ([(11,0,42),(21,-7,44),(28,-8,52)], [2,1.5,.9]),
    ]
    for pts, rr in branches:
        tube(wood, pts, rr, colors)
    # Broad, scalloped blood-red crown. Lower side lobes make it droop.
    for i,(c,r) in enumerate([
        ((-8,0,78),(18,16,13)), ((9,1,79),(18,16,13)),
        ((-22,0,68),(13,14,13)), ((23,0,68),(12,14,12)),
        ((-11,-14,68),(15,13,12)), ((12,-15,68),(15,13,13)),
        ((-12,14,70),(15,13,12)), ((13,15,70),(15,13,12)),
        ((0,0,68),(20,18,13)), ((-1,-1,88),(12,12,9)),
    ]):
        foliage(leaf,c,r,30,70+i)
    for i,(x,y,z) in enumerate([(-27,-4,61),(-15,-23,61),(15,-24,61),(28,3,62),(10,23,62)]):
        foliage(leaf,(x,y,z-4),(3.5,4,7),30,90+i)
    sprigs(leaf,30,127,155)
    # Short dark thorns at the branch forks, integral to the wood.
    for pts in [[(1,-3,22),(8,-4,27)], [(-2,-3,37),(-9,-4,40)], [(15,0,47),(20,0,56)]]:
        tube(wood,pts,[1.8,.85],colors)
    seam = (wood>0)&(Y<-3)&(Z>8)&(Z<47)&(((np.floor(X/2)-np.floor(Z/9)).astype(int)%7)==0)
    wood[seam] = 29
    out = leaf.copy(); out[wood>0] = wood[wood>0]
    return out


def components(a):
    remaining = set(map(tuple, np.argwhere(a)))
    result = []
    while remaining:
        start = remaining.pop(); q = deque([start]); part = [start]
        while q:
            x,y,z = q.popleft()
            for p in ((x-1,y,z),(x+1,y,z),(x,y-1,z),(x,y+1,z),(x,y,z-1),(x,y,z+1)):
                if p in remaining:
                    remaining.remove(p); q.append(p); part.append(p)
        result.append(part)
    return sorted(result, key=len, reverse=True)


def clean(a):
    pieces = components(a)
    # Remove only insignificant diagonal fringe voxels from voxelized tips.
    small = sum(map(len,pieces[1:]))
    assert small < max(100, np.count_nonzero(a)*.003), [len(p) for p in pieces]
    for part in pieces[1:]:
        a[tuple(np.array(part).T)] = 0
    return a


def chunk(tag, data=b'', children=b''):
    return tag+struct.pack('<II',len(data),len(children))+data+children


def dictionary(items):
    b = struct.pack('<i',len(items))
    for k,v in items.items():
        for s in (k,str(v)):
            raw = s.encode(); b += struct.pack('<i',len(raw))+raw
    return b


def export(path, models):
    data = b''
    for name,a in models.items():
        xyz = np.argwhere(a)
        records = np.column_stack((xyz,a[tuple(xyz.T)])).astype(np.uint8)
        data += chunk(b'SIZE',struct.pack('<3i',*SHAPE))
        data += chunk(b'XYZI',struct.pack('<i',len(records))+records.tobytes())
    data += chunk(b'RGBA',b''.join(bytes(c)+b'\xff' for c in RGB)+bytes([0,0,0,255])*(256-len(RGB)))
    # Center X/Y about the trunk, lift all objects half the canvas height.
    data += chunk(b'nTRN',struct.pack('<i',0)+dictionary({'_name':path.stem})+
                  struct.pack('<4i',1,-1,-1,1)+dictionary({'_t':'0 0 56','_r':'4'}))
    data += chunk(b'nGRP',struct.pack('<i',1)+dictionary({})+struct.pack('<i',len(models))+
                  b''.join(struct.pack('<i',2+2*i) for i in range(len(models))))
    for i,name in enumerate(models):
        data += chunk(b'nTRN',struct.pack('<i',2+2*i)+dictionary({'_name':name})+
                      struct.pack('<4i',3+2*i,-1,i,1)+dictionary({'_t':'0 0 0','_r':'4'}))
        data += chunk(b'nSHP',struct.pack('<i',3+2*i)+dictionary({})+struct.pack('<2i',1,i)+dictionary({}))
        data += chunk(b'LAYR',struct.pack('<i',i)+dictionary({'_name':name,'_hidden':'0'})+struct.pack('<i',-1))
    path.write_bytes(b'VOX '+struct.pack('<i',150)+chunk(b'MAIN',children=data))


def read_vox(path):
    raw = path.read_bytes()
    assert raw[:8] == b'VOX '+struct.pack('<i',150)
    assert raw[8:12] == b'MAIN' and struct.unpack_from('<II',raw,12)==(0,len(raw)-20)
    models, nodes, layers = [], {}, {}
    palette = None; pos = 20
    def rd(b,o):
        count = struct.unpack_from('<i',b,o)[0]; o += 4; d = {}
        for _ in range(count):
            pair = []
            for _ in range(2):
                n = struct.unpack_from('<i',b,o)[0]; o += 4
                pair.append(b[o:o+n].decode()); o += n
            d[pair[0]] = pair[1]
        return d,o
    while pos < len(raw):
        tag = raw[pos:pos+4]; n,ch = struct.unpack_from('<II',raw,pos+4)
        assert ch==0 and pos+12+n <= len(raw)
        b = raw[pos+12:pos+12+n]; pos += 12+n
        if tag == b'SIZE':
            dims = struct.unpack('<3i',b); assert dims == SHAPE
        elif tag == b'XYZI':
            count = struct.unpack_from('<i',b)[0]
            q = np.frombuffer(b[4:],np.uint8).reshape(-1,4)
            assert count==len(q)==len(np.unique(q[:,:3],axis=0))
            assert (q[:,:3]<dims).all() and (q[:,3]>0).all() and (q[:,3]<=len(RGB)).all()
            a = np.zeros(dims,np.uint8); a[tuple(q[:,:3].T)] = q[:,3]; models.append(a)
        elif tag == b'RGBA':
            assert n==1024
            palette = np.frombuffer(b,np.uint8).reshape(256,4)
        elif tag in (b'nTRN',b'nGRP',b'nSHP'):
            ident = struct.unpack_from('<i',b)[0]; attrs,o = rd(b,4)
            assert ident not in nodes
            node = {'type':tag.decode(),'attrs':attrs}
            if tag==b'nTRN':
                child,res,layer,nf = struct.unpack_from('<4i',b,o); o+=16
                frame,o=rd(b,o)
                assert res==-1 and nf==1 and frame['_r']=='4'
                node.update(child=child,layer=layer,frame=frame)
            elif tag==b'nGRP':
                count=struct.unpack_from('<i',b,o)[0];o+=4
                node['children']=struct.unpack_from('<'+'i'*count,b,o);o+=4*count
            else:
                count,model=struct.unpack_from('<2i',b,o);o+=8
                assert count==1
                _,o=rd(b,o); node['model']=model
            assert o==len(b);nodes[ident]=node
        elif tag==b'LAYR':
            ident=struct.unpack_from('<i',b)[0];attrs,o=rd(b,4)
            assert struct.unpack_from('<i',b,o)[0]==-1 and o+4==len(b)
            layers[ident]=attrs
    assert pos==len(raw) and np.array_equal(palette[:len(RGB),:3],RGB) and (palette[:,3]==255).all()
    assert nodes[0]['child']==1 and nodes[0]['frame']['_t']=='0 0 56'
    children=nodes[1]['children'];assert len(children)==len(models)
    names=[]
    for i,ch in enumerate(children):
        tr=nodes[ch];sh=nodes[tr['child']]
        assert sh['model']==i and tr['frame']['_t']=='0 0 0' and tr['layer']==i
        assert layers[i]['_name']==tr['attrs']['_name']
        names.append(tr['attrs']['_name'])
    return dict(zip(names,models))


def font(size, bold=False):
    try:
        return ImageFont.truetype('C:/Windows/Fonts/'+('segoeuib.ttf' if bold else 'segoeui.ttf'),size)
    except OSError:
        return ImageFont.load_default(size=size)


def render(a, size=(540,690), az=-60, el=18, scale=5.3, center=(40,40,53)):
    az,el=math.radians(az),math.radians(el)
    view=np.array([math.cos(az)*math.cos(el),math.sin(az)*math.cos(el),math.sin(el)])
    right=np.array([-math.sin(az),math.cos(az),0]);up=np.cross(view,right)
    center=np.asarray(center); faces=[];pad=np.pad(a,1)
    for axis in range(3):
        if abs(view[axis])<1e-6:continue
        sign=1 if view[axis]>0 else -1
        sl=[slice(1,-1)]*3;sl[axis]=slice(2,None) if sign>0 else slice(None,-2)
        p=np.argwhere((a>0)&(pad[tuple(sl)]==0))
        others=[j for j in range(3) if j!=axis]
        corners=np.zeros((4,3));corners[:,axis]=1 if sign>0 else 0
        corners[:,others[0]]=[0,1,1,0];corners[:,others[1]]=[0,0,1,1]
        verts=p[:,None,:]+corners-center
        uv=np.stack((verts@right,-verts@up),axis=-1)*scale+np.array(size)/2
        depths=(p+corners.mean(0)-center)@view
        cols=np.clip(RGB.astype(float)*[.78,.93,1.12][axis],0,255).astype(np.uint8)
        for i in range(len(p)):
            faces.append((depths[i],uv[i],tuple(cols[a[tuple(p[i])]-1])+(255,)))
    faces.sort(key=lambda f:f[0])
    im=Image.new('RGBA',size);d=ImageDraw.Draw(im)
    for _,poly,col in faces:
        d.polygon([tuple(v) for v in np.rint(poly).astype(int)], fill=col)
    return im


def previews(trees,wood,leaf):
    pre=ROOT/'previews';pre.mkdir(exist_ok=True)
    bg=(20,27,30); muted=(142,158,160); light=(235,239,229)
    sheet=Image.new('RGB',(1800,990),bg);d=ImageDraw.Draw(sheet)
    d.text((65,40),'BLOCKBOUND  /  BIOME COLLECTION',font=font(19,True),fill=muted)
    d.text((62,75),'Three worlds. Three trees.',font=font(44,True),fill=light)
    d.text((65,137),'Voxel models  /  solid colour  /  shared scale',font=font(20),fill=muted)
    names=['NORMAL','CORRUPTION','CRIMSON']; hues=[(141,197,97),(195,150,218),(245,124,109)]
    subtitles=['Layered evergreen · separate leaves + trunk','Crooked branches · violet canopy','Forked trunk · scarlet crown']
    for i,(key,a) in enumerate(trees.items()):
        px=i*575+42
        d.rounded_rectangle((px,195,px+558,932),radius=18,fill=(26,34,37))
        d.ellipse((px+133,787,px+425,824),fill=(18,25,27))
        im=render(a)
        sheet.paste(im,(px+9,178),im)
        im.save(pre/(key+'.png'))
        d.text((px+30,840),names[i],font=font(27,True),fill=hues[i])
        d.text((px+30,880),subtitles[i],font=font(18),fill=muted)
    d.text((65,955),'Actual exported voxel geometry. Preview lighting is not baked into the assets.',font=font(17),fill=muted)
    sheet.save(pre/'tree_lineup.png')
    # Four equally scaled views for each model.
    for i,(key,a) in enumerate(trees.items()):
        sheet=Image.new('RGB',(1600,700),bg);d=ImageDraw.Draw(sheet)
        d.text((38,24),names[i]+' / FOUR VIEWS',font=font(25,True),fill=hues[i])
        for j,(az,label) in enumerate([(-90,'FRONT'),(0,'SIDE'),(90,'BACK'),(-45,'THREE-QUARTER')]):
            im=render(a,(400,590),az=az,el=12 if j<3 else 22,scale=4.8)
            sheet.paste(im,(400*j,65),im)
            d.text((400*j+28,655),label,font=font(16,True),fill=muted)
        sheet.save(pre/(key+'_views.png'))
    sheet=Image.new('RGB',(1600,820),bg);d=ImageDraw.Draw(sheet)
    d.text((45,27),'NORMAL / TWO SEPARATE MODELS',font=font(29,True),fill=light)
    d.text((45,72),'Identical canvases and transforms. Place both parts at the same origin.',font=font(20),fill=muted)
    for i,(a,label) in enumerate([(wood,'01 / TRUNK + BRANCHES'),(leaf,'02 / LEAVES'),(trees['normal_tree'],'ASSEMBLED')]):
        im=render(a,(530,600),scale=4.8)
        sheet.paste(im,(i*530,125),im)
        d.text((i*530+40,749),label,font=font(22,True),fill=(141,197,97))
    sheet.save(pre/'normal_parts.png')


def package():
    paths = sorted(ROOT.glob('*.vox')) + [ROOT/'README.md', ROOT/'validation.json']
    paths += sorted((ROOT/'previews').glob('*.png')) + [Path(__file__).resolve()]
    with zipfile.ZipFile(ROOT/'Blockbound_Trees.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for p in paths:
            archive.write(p,p.relative_to(ROOT))
    with zipfile.ZipFile(ROOT/'Blockbound_Trees.zip') as archive:
        assert archive.testzip() is None
        assert len(archive.namelist())==len(paths)


def main():
    ROOT.mkdir(parents=True,exist_ok=True)
    wood,leaf=normal();clean(wood);clean(leaf)
    green=leaf.copy();green[wood>0]=wood[wood>0]
    purple=clean(corruption());red=clean(crimson())
    trees={'normal_tree':green,'corruption_tree':purple,'crimson_tree':red}
    files={
        'normal_tree.vox':{'Trunk and branches':wood,'Leaves':leaf},
        'normal_trunk.vox':{'Trunk and branches':wood},
        'normal_leaves.vox':{'Leaves':leaf},
        'corruption_tree.vox':{'Corruption tree':purple},
        'crimson_tree.vox':{'Crimson tree':red},
    }
    assert not np.any((wood>0)&(leaf>0))
    for name,a in trees.items():
        assert len(components(a))==1, name
    validation={'format':'MagicaVoxel VOX 150 with named scene nodes',
                'canvas':SHAPE,'up_axis':'+Z','local_ground_pivot':[40,40,0],
                'scene_ground_pivot':[0,0,0],'normal_parts_overlap_voxels':0,
                'normal_parts_transforms_identical':True,'files':{}}
    for filename,models in files.items():
        path=ROOT/filename;export(path,models);decoded=read_vox(path)
        assert list(decoded)==list(models)
        stats={}
        for name,a in models.items():
            assert np.array_equal(decoded[name],a)
            xyz=np.argwhere(a); parts=components(a);assert len(parts)==1
            stats[name]={'voxels':len(xyz),'occupied_min':xyz.min(0).tolist(),
                         'occupied_max_exclusive':(xyz.max(0)+1).tolist(),
                         'occupied_size':(np.ptp(xyz,axis=0)+1).tolist(),'connected_components':len(parts)}
        validation['files'][filename]={'models':stats,'binary_roundtrip':'passed',
            'scene_graph':'passed','palette':'passed','sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    (ROOT/'validation.json').write_text(json.dumps(validation,indent=2)+'\n')
    previews(trees,wood,leaf)
    package()
    print(json.dumps(validation,indent=2))


if __name__=='__main__':
    main()
