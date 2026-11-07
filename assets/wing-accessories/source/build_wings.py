"""Build seven original BlockBound wing accessories from the item descriptions.

No inventory sprites are inputs. Python 3 + NumPy + Pillow. Geometry coordinates
are voxel centres: X lateral, Y rearward, Z up. GLB uses (X,Z,-Y)*0.0625.
Each named VOX object is one rigid bone-weighted piece in the companion GLB.
"""
from pathlib import Path
import io, itertools, json, math, re, struct, zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
SCALE = .0625
RGB = [(37,32,40),(70,55,51),(117,85,53),(168,118,54),(220,170,78),(255,220,137)]
THEMES = {
    'Angel': [(102,117,145),(151,166,190),(200,212,225),(229,234,239),(255,249,224),(225,183,91)],
    'Bat': [(31,24,45),(52,36,66),(77,49,88),(107,66,112),(155,111,155),(195,157,168)],
    'Demon': [(31,26,34),(65,26,41),(114,29,47),(170,42,55),(224,76,67),(242,178,123)],
    'Fairy': [(62,65,128),(102,102,183),(141,137,220),(181,193,241),(213,248,244),(110,224,208)],
    'Flame': [(91,27,42),(155,37,37),(213,57,28),(246,116,29),(255,183,46),(255,236,142)],
    'Frost': [(32,74,111),(44,117,160),(75,166,197),(134,214,230),(207,245,249),(245,255,255)],
    'Leaf': [(29,65,45),(39,101,50),(64,139,53),(103,172,61),(171,203,82),(229,221,133)],
}
BASE = {}
for theme, cols in THEMES.items():
    BASE[theme] = len(RGB) + 1
    RGB.extend(cols)


def i32(*v): return struct.pack('<'+'i'*len(v), *map(int,v))
def string(v):
    b=str(v).encode('utf8'); return i32(len(b))+b
def dic(v): return i32(len(v))+b''.join(string(k)+string(x) for k,x in v.items())
def chunk(tag, data): return tag.encode()+i32(len(data),0)+data
def xyz_glb(v): return np.asarray(v)[..., [0,2,1]] * [1,1,-1] * SCALE


class Wing:
    def __init__(self, theme):
        self.theme=theme; self.parts={}; self.bones={}; self.c=BASE[theme]
    def part(self,name,parent,pivot,role):
        self.parts[name]={}
        self.bones[name]={'parent':parent,'pivot':list(pivot),'role':role}
        return name
    def put(self,name,p,c): self.parts[name][tuple(int(round(a)) for a in p)] = int(c)
    def ell(self,name,center,radii,col):
        c=np.asarray(center); r=np.asarray(radii)
        lo=np.floor(c-r).astype(int); hi=np.ceil(c+r).astype(int)
        pts=np.indices(tuple(hi-lo+1)).reshape(3,-1).T+lo
        pts=pts[np.sum(((pts-c)/r)**2,axis=1)<=1.04]
        for p in pts: self.put(name,p,col)
    def tube(self,name,points,radii,col):
        for a,b,ra,rb in zip(points,points[1:],radii,radii[1:]):
            a=np.asarray(a); b=np.asarray(b)
            for t in np.linspace(0,1,max(2,int(np.linalg.norm(b-a)*1.4))):
                self.ell(name,a*(1-t)+b*t,[max(.72,ra*(1-t)+rb*t)]*3,col)
    def sheet(self,name,poly,depth,thickness,col,edge=None):
        # Rasterize the actual XZ polygon; thickness/bow produce a true 3D volume.
        poly=np.asarray(poly,float)
        lo=np.floor(poly.min(0)).astype(int);hi=np.ceil(poly.max(0)).astype(int)
        xx,zz=np.meshgrid(np.arange(lo[0],hi[0]+1),np.arange(lo[1],hi[1]+1),indexing='ij')
        inside=np.zeros(xx.shape,bool); dist=np.full(xx.shape,1e6)
        for a,b in zip(poly,np.roll(poly,-1,axis=0)):
            inside ^= ((a[1]>zz)!=(b[1]>zz)) & (xx<(b[0]-a[0])*(zz-a[1])/(b[1]-a[1]+1e-12)+a[0])
            ab=b-a; t=np.clip(((xx-a[0])*ab[0]+(zz-a[1])*ab[1])/(ab@ab+1e-12),0,1)
            dist=np.minimum(dist,np.hypot(xx-a[0]-ab[0]*t,zz-a[1]-ab[1]*t))
        for x,z,d in zip(xx[inside],zz[inside],dist[inside]):
            y=depth(x,z) if callable(depth) else depth
            th=thickness(x,z) if callable(thickness) else thickness
            c=col(x,z,d) if callable(col) else col
            if edge is not None and d<1.0:c=edge
            for yy in range(round(y-th/2),round(y+th/2)+1):self.put(name,(x,yy,z),c)
    def blade(self,name,a,b,width,colors,leaf=False,crystal=False):
        # Convex feather/leaf/crystal with a central ridge and a curved depth profile.
        a=np.asarray(a,float);b=np.asarray(b,float);v=b-a;L=np.linalg.norm(v);n=np.array([-v[1],v[0]])/L
        if crystal:
            poly=[a-n*width*.42,a+v*.74-n*width*.5,b,a+v*.70+n*width*.5,a+n*width*.42]
        else:
            poly=[a,a+v*.19-n*width*.7,a+v*.53-n*width*.55,b,a+v*.63+n*width*.56,a+v*.25+n*width*.7]
        def project(x,z):return np.clip((np.array([x,z])-a)@v/L**2,0,1)
        def depth(x,z):return 4+3*math.sin(project(x,z)*math.pi)+.045*abs(x)
        def color(x,z,d):
            t=project(x,z);side=(np.array([x,z])-a)@n
            if crystal:return colors[2] if side>0 else colors[0 if t<.7 else 1]
            return colors[0] if side<-.8 else colors[1 if t<.82 else 2]
        self.sheet(name,poly,depth,lambda x,z: max(1.4,3.8*(1-project(x,z))),color)
        mid=a+v*.80
        self.tube(name,[(a[0],depth(*a)+2,a[1]),(mid[0],depth(*mid)+1,mid[1])],[.9,.72],colors[2])
        if leaf:
            for t in [.27,.44,.61]:
                center=a+v*t
                for sign in [-1,1]:
                    end=a+v*(t+.14)+n*sign*width*.40
                    self.tube(name,[(center[0],depth(*center)+2,center[1]),(end[0],depth(*end)+1,end[1])],[.75,.72],colors[2])
    def mirror(self):
        for name in list(self.parts):
            if not name.startswith('R_'):continue
            left=name.replace('R_','L_',1)
            self.parts[left]={(-x,y,z):c for (x,y,z),c in self.parts[name].items()}
            b=dict(self.bones[name]);b['pivot']=[-b['pivot'][0],*b['pivot'][1:]]
            if b['parent'].startswith('R_'):b['parent']=b['parent'].replace('R_','L_',1)
            self.bones[left]=b
    def frame(self):
        f=self.part('Frame',None,(0,0,0),'Attach to upper back; fixed wearable frame')
        self.sheet(f,[(-6,-11),(6,-11),(8,-5),(7,9),(4,13),(-4,13),(-7,9),(-8,-5)],-1,4,2,3)
        self.sheet(f,[(-3,-9),(3,-9),(4,8),(0,11),(-4,8)],2,2,self.c,4)
        self.ell(f,(0,4,3),(3,2,4),self.c+4)
        for s in [-1,1]:
            self.tube(f,[(s*5,0,-7),(s*8,0,-2),(s*8,0,5)],[2,2,2],3)
            for z in [-8,9]:self.ell(f,(s*5,3,z),(1,1,1),6)
    def arm(self,elbow=(25,4,22),style=None):
        name=self.part('R_Arm','Frame',(7,0,5),'Shoulder flap / sweep')
        self.tube(name,[(7,0,5),(16,2,14),elbow],[3,3.5,2.6],self.c if style is None else style)
        self.tube(name,[(8,3,6),(16,5,15),(elbow[0],elbow[1]+2,elbow[2])],[1.1,1.1,1],self.c+4 if self.theme in ['Angel','Frost'] else self.c+2)
        fan=self.part('R_Fan','R_Arm',elbow,'Elbow fold / feather fan')
        self.ell(fan,elbow,(3.4,3.3,3.4),self.c+2)
        return fan
    def finish(self):
        self.mirror()
        # Later pieces own exact voxel overlaps. Faces remain closed at every hinge.
        occupied=set()
        for name in reversed(list(self.parts)):
            self.parts[name]={p:c for p,c in self.parts[name].items() if p not in occupied}
            occupied.update(self.parts[name])
        # Carving overlapping coverts can leave tiny disconnected tips. Remove
        # those islands so no loose geometry floats away when a bone is posed.
        steps=[p for p in itertools.product((-1,0,1),repeat=3) if p!=(0,0,0)]
        for name,vox in self.parts.items():
            todo=set(vox);groups=[]
            while todo:
                stack=[todo.pop()];group=set(stack)
                while stack:
                    x,y,z=stack.pop()
                    for dx,dy,dz in steps:
                        p=(x+dx,y+dy,z+dz)
                        if p in todo:todo.remove(p);group.add(p);stack.append(p)
                groups.append(group)
            keep=max(groups,key=len)
            self.parts[name]={p:c for p,c in vox.items() if p in keep}
        assert all(self.parts.values())


def angel(w):
    w.arm((27,4,24),w.c+1)
    w.blade('R_Fan',(14,13),(40,32),7,[w.c+1,w.c+2,w.c+4])
    for i,(a,b,width) in enumerate([
        ((29,26),(69,44),5),((31,24),(70,30),6),((30,20),(67,15),6),
        ((27,16),(60,0),6),((24,12),(52,-13),6),((20,8),(42,-22),5.5),
        ((16,6),(31,-26),5),((12,6),(22,-22),4.5)]):
        n=w.part(f'R_Feather{i+1:02}','R_Fan',(*a[:1],4,a[1]),'Primary feather splay / trailing follow-through')
        w.blade(n,a,b,width,[w.c+1,w.c+3,w.c+4])
    # A raised, overlapping covert row covers the structural hinge.
    for a,b in [((11,7),(18,16)),((16,13),(25,23)),((22,20),(34,29)),((28,25),(42,31))]:
        w.blade('R_Arm',a,b,4,[w.c+2,w.c+3,w.c+4])


def membrane(w,demon=False):
    elbow=(28,3,29) if demon else (25,3,24)
    w.arm(elbow,w.c)
    if demon:
        outline=[(13,1),(28,29),(43,45),(57,42),(74,29),(65,25),(60,18),(58,8),
                 (66,-5),(53,0),(44,-1),(40,-9),(40,-23),(31,-14),(24,-11),(19,-15),(16,-25)]
        tips=[(74,29),(66,-5),(40,-23),(16,-25)]
    else:
        outline=[(12,1),(25,24),(39,31),(51,29),(68,17),(59,14),(52,8),(50,-2),
                 (52,-14),(43,-8),(36,-6),(30,-10),(27,-23),(22,-14),(17,-10),(12,-14)]
        tips=[(68,17),(52,-14),(27,-23),(12,-14)]
    def depth(x,z):return 3+.10*(x-15)+2*math.sin(x*.08+z*.06)
    def color(x,z,d):return w.c+1 if d<2 else w.c+2+(1 if ((x+z)//12)%3==0 else 0)
    w.sheet('R_Fan',outline,depth,2.2,color,w.c)
    ex,ey,ez=elbow
    for k,(x,z) in enumerate(tips):
        w.tube('R_Fan',[(ex,ey+2,ez),((ex+x)*.5,depth((ex+x)/2,(ez+z)/2)+1,(ez+z)/2+3),(x,depth(x,z),z)],[1.8,1.3,.75],w.c if demon else w.c+3)
    for a,b in zip(outline,outline[1:]+outline[:1]):
        w.tube('R_Fan',[(a[0],depth(*a),a[1]),(b[0],depth(*b),b[1])],[.85,.85],w.c)
    # Articulated hooked thumb/claw on the leading edge.
    n=w.part('R_Claw','R_Fan',elbow,'Leading claw accent')
    pts=[elbow,(ex+1,3,ez+10),(ex+6,3,ez+15),(ex+10,3,ez+11)]
    w.tube(n,pts,[2.4,2.1,1.5,.75],w.c+5)
    if demon:
        for k in range(3):
            x=34+k*8;z=39+(2 if k==1 else 0)
            w.tube('R_Fan',[(x,5,z),(x+1,5,z+8),(x+5,5,z+5)],[2,1,.75],w.c+5)
        # Three separate trailing thorns allow secondary motion.
        for i,((x,z),(tx,tz)) in enumerate(zip(tips[1:],[(70,-12),(40,-32),(14,-33)])):
            n=w.part(f'R_Thorn{i+1}','R_Fan',(x,depth(x,z),z),'Trailing thorn follow-through')
            w.tube(n,[(x,depth(x,z),z),(tx,depth(x,z),tz)],[1.8,.75],w.c+5)


def fairy(w):
    # Four independent insect lobes, not a bird fan.
    for key,poly,pivot in [
        ('Upper',[(8,5),(15,27),(30,49),(43,53),(52,45),(51,31),(40,15),(24,5)],(7,1,5)),
        ('Lower',[(8,1),(24,2),(42,-4),(48,-14),(43,-25),(32,-30),(19,-21),(10,-9)],(7,2,0))]:
        n=w.part('R_'+key,'Frame',pivot,'Independent butterfly lobe flap')
        def depth(x,z):return 4+.05*x+1.7*math.sin(z*.06)
        def col(x,z,d):return w.c+1 if d<2.5 else w.c+2+(1 if x>30 else 0)
        w.sheet(n,poly,depth,2.5,col,w.c)
        for a,b in zip(poly,poly[1:]+poly[:1]):w.tube(n,[(a[0],depth(*a)+1,a[1]),(b[0],depth(*b)+1,b[1])],[1,1],w.c+5)
        ends=[(30,46),(47,42),(40,18)] if key=='Upper' else [(40,-10),(37,-24),(22,-21)]
        for x,z in ends:
            w.tube(n,[pivot,((x+10)/2,depth(x,z)+1,(z+3)/2),(x,depth(x,z)+1,z)],[.9,.8,.75],w.c+4)
        # Opaque opal cells read reliably as voxels in both renderers.
        cx,cz=(35,32) if key=='Upper' else (31,-13)
        w.sheet(n,[(cx-6,cz),(cx,cz+7),(cx+6,cz),(cx,cz-7)],depth(cx,cz)+2,1,w.c+5,w.c+4)
        for x,z in [(cx-8,cz-7),(cx+6,cz+8)]:w.ell(n,(x,depth(x,z)+2,z),(1.4,1,1.4),w.c+4)
    for s in [-1,1]:w.tube('Frame',[(s*3,2,9),(s*6,3,16),(s*4,4,20)],[1,.9,.75],5)


def flame(w):
    w.arm((25,4,18),w.c+1)
    w.sheet('R_Fan',[(12,4),(25,20),(48,18),(54,2),(38,-14),(16,-12)],5,5,w.c+1,w.c)
    plumes=[((29,19),(59,52),7),((35,16),(71,36),8),((38,10),(70,15),8),
            ((34,3),(62,-7),8),((27,-3),(48,-25),7),((19,-4),(30,-30),6)]
    for i,(a,b,width) in enumerate(plumes):
        n=w.part(f'R_Plume{i+1:02}','R_Fan',(a[0],5,a[1]),'Solid flame-shaped plume / secondary sway')
        a=np.array(a,float);b=np.array(b,float);v=b-a;nn=np.array([-v[1],v[0]])/np.linalg.norm(v)
        poly=[a-nn*width*.6,a+v*.38-nn*width*.8,a+v*.67-nn*width*.4,b,
              a+v*.69+nn*width*.8,a+v*.48+nn*width*.35,a+v*.25+nn*width*.7,a]
        w.sheet(n,poly,lambda x,z:7+.045*x,3.5,w.c+2,w.c+1)
        inner=[a,a+v*.32-nn*width*.35,a+v*.79,a+v*.46+nn*width*.3]
        w.sheet(n,inner,lambda x,z:10+.045*x,1.5,w.c+4,w.c+3)
        w.tube(n,[(a[0],12,a[1]),(*(a+v*.43)[:1],12,(a+v*.43)[1])],[1.4,.75],w.c+5)


def frost(w):
    w.arm((24,4,22),w.c+1)
    w.blade('R_Fan',(13,8),(38,30),7,[w.c+1,w.c+3,w.c+5],crystal=True)
    for i,(a,b,width) in enumerate([
        ((27,24),(59,48),8),((30,20),(69,29),9),((29,15),(65,8),9),
        ((25,10),(55,-14),9),((19,5),(39,-28),8),((13,4),(22,-26),7)]):
        n=w.part(f'R_Crystal{i+1:02}','R_Fan',(a[0],5,a[1]),'Rigid ice crystal / spread')
        w.blade(n,a,b,width,[w.c+1,w.c+3,w.c+5],crystal=True)
    for a,b in [((13,10),(12,24)),((18,17),(20,34)),((26,23),(32,39))]:
        w.blade('R_Arm',a,b,4,[w.c+1,w.c+3,w.c+4],crystal=True)


def leaf(w):
    w.arm((22,4,20),3)
    w.tube('R_Fan',[(18,4,13),(31,5,22),(46,6,34)],[2.4,1.8,.75],w.c)
    for i,(a,b,width) in enumerate([
        ((37,30),(56,49),8),((34,26),(68,28),10),((29,21),(64,7),10),
        ((24,16),(51,-11),10),((18,10),(36,-26),9),((13,6),(20,-25),7),
        ((26,23),(26,43),7),((17,13),(12,31),6)]):
        n=w.part(f'R_Leaf{i+1:02}','R_Fan',(a[0],5,a[1]),'Leaf fan / subtle rustle')
        w.blade(n,a,b,width,[w.c+1,w.c+2+(i%2),w.c+4],leaf=True)
    for z in [-6,0,6]:w.ell('Frame',(0,5,z),(2.8,1.5,2.1),w.c+2)


def save_vox(path,parts):
    data=b''; records=[]
    for name,vox in parts.items():
        pts=np.array(list(vox));lo=pts.min(0);size=pts.max(0)-lo+1
        assert np.all(size<=256)
        raw=np.array([(*tuple(p-lo),vox[tuple(p)]) for p in pts],np.uint8).tobytes()
        data+=chunk('SIZE',i32(*size))+chunk('XYZI',i32(len(pts))+raw)
        records.append((name,lo,size))
    data+=chunk('RGBA',b''.join(bytes((*c,255)) for c in RGB)+bytes((256-len(RGB))*4))
    # Lift the scene above the MagicaVoxel ground without changing model pivots.
    data+=chunk('nTRN',i32(0)+dic({'_name':path.stem})+i32(1,-1,-1,1)+dic({'_t':'0 0 40'}))
    data+=chunk('nGRP',i32(1)+dic({})+i32(len(records))+i32(*[2+i*2 for i in range(len(records))]))
    for i,(name,lo,size) in enumerate(records):
        data+=chunk('nTRN',i32(2+i*2)+dic({'_name':name})+i32(3+i*2,-1,i,1)+dic({'_t':' '.join(map(str,lo+size//2))}))
        data+=chunk('nSHP',i32(3+i*2)+dic({})+i32(1,i)+dic({}))
        data+=chunk('LAYR',i32(i)+dic({'_name':name})+i32(-1))
    path.write_bytes(b'VOX '+i32(150)+b'MAIN'+i32(0,len(data))+data)


def greedy(mask):
    m=mask.copy();out=[]
    for u in range(m.shape[0]):
        v=0
        while v<m.shape[1]:
            c=int(m[u,v])
            if not c:v+=1;continue
            dv=1
            while v+dv<m.shape[1] and m[u,v+dv]==c:dv+=1
            du=1
            while u+du<m.shape[0] and np.all(m[u+du,v:v+dv]==c):du+=1
            m[u:u+du,v:v+dv]=0;out.append((u,v,du,dv,c));v+=dv
    return out


def mesh(vox):
    pts=np.array(list(vox));lo=pts.min(0);shape=pts.max(0)-lo+1
    a=np.zeros(shape,np.uint8)
    for p,c in vox.items():a[tuple(np.array(p)-lo)]=c
    quads=[];colors=[];normals=[];surface=0
    for ax in range(3):
        u,v=[i for i in range(3) if i!=ax]
        for sign in [-1,1]:
            pad=np.pad(a>0,1);sl=[slice(1,-1)]*3;sl[ax]=slice(2,None) if sign>0 else slice(None,-2)
            exposed=np.where((a>0)&~pad[tuple(sl)],a,0)
            surface+=np.count_nonzero(exposed)
            for plane in range(shape[ax]):
                mask=np.take(exposed,plane,axis=ax)
                if not mask.any():continue
                for uu,vv,du,dv,c in greedy(mask):
                    p=np.zeros((4,3));p[:,ax]=plane+sign*.5;p[:,u]=np.array([uu,uu+du,uu+du,uu])-.5;p[:,v]=np.array([vv,vv,vv+dv,vv+dv])-.5
                    n=np.eye(3)[ax]*sign
                    if np.dot(np.cross(p[1]-p[0],p[2]-p[0]),n)<0:p=p[::-1]
                    quads.append(p+lo);colors.append(c);normals.append(n)
    return np.asarray(quads),np.asarray(colors),np.asarray(normals),int(surface)


def write_glb(w,meshes):
    blob=bytearray();views=[];accessors=[]
    def view(raw,target=None):
        while len(blob)%4:blob.append(0)
        d={'buffer':0,'byteOffset':len(blob),'byteLength':len(raw)}
        if target:d['target']=target
        views.append(d);blob.extend(raw);return len(views)-1
    def acc(a,typ,ctype=5126,target=None,bounds=False):
        a=np.asarray(a,dtype={5126:'<f4',5123:'<u2',5125:'<u4'}[ctype])
        d={'bufferView':view(a.tobytes(),target),'componentType':ctype,'count':len(a),'type':typ}
        if bounds:d.update(min=np.atleast_1d(a.min(0)).tolist(),max=np.atleast_1d(a.max(0)).tolist())
        accessors.append(d);return len(accessors)-1
    names=list(w.parts);ids={n:i for i,n in enumerate(names)}
    nodes=[];gmeshes=[];ibm=[];report={}
    for name in names:
        b=w.bones[name];p=xyz_glb(b['pivot']);parent=b['parent']
        delta=p if parent is None else p-xyz_glb(w.bones[parent]['pivot'])
        nodes.append({'name':name,'translation':delta.tolist(),'extras':{'role':b['role']}})
        mat=np.eye(4);mat[:3,3]=-p;ibm.append(mat.T.reshape(16))
    for i,name in enumerate(names):
        par=w.bones[name]['parent']
        if par is not None:nodes[ids[par]].setdefault('children',[]).append(i)
    for name in names:
        q,c,n,surface=meshes[name];num=len(q)*4
        pos=xyz_glb(q).reshape(-1,3)
        normals=np.repeat(n[:,[0,2,1]]*[1,1,-1],4,axis=0)
        uv=np.repeat(np.stack(((c-.5)/64,np.full(len(c),.5)),axis=1),4,axis=0)
        joints=np.zeros((num,4),np.uint16);joints[:,0]=ids[name]
        weights=np.zeros((num,4));weights[:,0]=1
        inds=(np.arange(len(q))[:,None]*4+np.array([0,1,2,0,2,3])).ravel()
        prim={'attributes':{'POSITION':acc(pos,'VEC3',target=34962,bounds=True),'NORMAL':acc(normals,'VEC3',target=34962),
            'TEXCOORD_0':acc(uv,'VEC2',target=34962),'JOINTS_0':acc(joints,'VEC4',5123,34962),'WEIGHTS_0':acc(weights,'VEC4',target=34962)},
            'indices':acc(inds,'SCALAR',5125 if num>65535 else 5123,34963),'material':0}
        gmeshes.append({'name':name+'_Mesh','primitives':[prim]})
        nodes.append({'name':name+'_Mesh','mesh':len(gmeshes)-1,'skin':0})
        report[name]={'voxels':len(w.parts[name]),'triangles':len(inds)//3,'surface_voxel_faces':surface}
    palette=Image.new('RGB',(1024,16));draw=ImageDraw.Draw(palette)
    for i,c in enumerate(RGB):draw.rectangle((i*16,0,i*16+15,15),fill=c)
    buf=io.BytesIO();palette.save(buf,format='PNG');imgview=view(buf.getvalue())
    ibacc=acc(ibm,'MAT4')
    # Two editable sanity-check clips: cyclic flap and a conservative fold.
    animations=[]
    for clip in ['Flap','Fold']:
        times=np.linspace(0,1.2,25) if clip=='Flap' else np.array([0,.8])
        ta=acc(times,'SCALAR',bounds=True);samplers=[];channels=[]
        for i,name in enumerate(names):
            if name=='Frame':continue
            side=1 if name.startswith('R_') else -1
            major=name.endswith(('Arm','Upper','Lower'));fan=name.endswith('Fan')
            if clip=='Flap':
                angles=np.sin(times/1.2*2*np.pi-(0 if major else .35 if fan else .6))*(28 if major else 10 if fan else 4)
                if name.endswith('Lower'):angles*=.75
            else:angles=np.array([0,38 if major else 22 if fan else 3])
            # Y-up rotation swings wings backward; second axis adds a slight lift.
            axis=np.array([0,1,.18 if major else 0]);axis=axis/np.linalg.norm(axis)
            half=np.radians(angles*side)*.5
            quat=np.concatenate((np.sin(half)[:,None]*axis,np.cos(half)[:,None]),axis=1)
            samplers.append({'input':ta,'output':acc(quat,'VEC4'),'interpolation':'LINEAR'})
            channels.append({'sampler':len(samplers)-1,'target':{'node':i,'path':'rotation'}})
        animations.append({'name':clip,'samplers':samplers,'channels':channels})
    doc={'asset':{'version':'2.0','generator':'BlockBound wing-accessories/build_wings.py'},'scene':0,
        'scenes':[{'name':w.theme+'Wings','nodes':[0]+list(range(len(names),len(nodes)))}],
        'nodes':nodes,'meshes':gmeshes,'skins':[{'name':w.theme+'WingRig','skeleton':0,'joints':list(range(len(names))),'inverseBindMatrices':ibacc}],
        'animations':animations,'materials':[{'name':w.theme+'Palette','pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicFactor':0,'roughnessFactor':.82}}],
        'textures':[{'source':0,'sampler':0}],'images':[{'bufferView':imgview,'mimeType':'image/png'}],
        'samplers':[{'magFilter':9728,'minFilter':9728,'wrapS':33071,'wrapT':33071}],
        'buffers':[{'byteLength':len(blob)}],'bufferViews':views,'accessors':accessors,
        'extras':{'source':w.theme+'Wings.vox','voxel_size':SCALE,'rig_type':'Rigid skin: one bone per named voxel object'}}
    raw=json.dumps(doc,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);blob+=b'\0'*((-len(blob))%4)
    glb=b'glTF'+struct.pack('<II',2,12+8+len(raw)+8+len(blob))+struct.pack('<I4s',len(raw),b'JSON')+raw+struct.pack('<I4s',len(blob),b'BIN\0')+blob
    (ROOT/'rigged'/f'{w.theme}Wings.glb').write_bytes(glb)
    return report


def font(size,bold=False):
    return ImageFont.truetype('C:/Windows/Fonts/'+('segoeuib.ttf' if bold else 'segoeui.ttf'),size)


def render(meshes,size=(1000,720),view='hero',bounds=None,labels=None):
    right=np.array([1,0,0]) if view=='front' else np.array([.95,-.312,0])
    up=np.array([0.,0.,1.]) if view=='front' else np.array([.065,.199,.978]);up/=np.linalg.norm(up)
    depth=np.cross(right,up)
    # Look from positive Y to see the sculpted outer face; invert cross-product.
    depth=-depth
    quads=np.concatenate([m[0] for m in meshes.values()]);cols=np.concatenate([m[1] for m in meshes.values()])
    normals=np.cross(quads[:,1]-quads[:,0],quads[:,2]-quads[:,0]);normals/=np.linalg.norm(normals,axis=1)[:,None]
    visible=normals@depth>1e-5;quads=quads[visible];cols=cols[visible];normals=normals[visible]
    xy=np.stack((quads@right,-quads@up),axis=2)
    lo=xy.reshape(-1,2).min(0);hi=xy.reshape(-1,2).max(0)
    if bounds is not None:lo,hi=map(np.array,bounds)
    scale=min((size[0]-70)/(hi[0]-lo[0]),(size[1]-75)/(hi[1]-lo[1]));off=np.array(size)/2-(lo+hi)/2*scale
    xy=xy*scale+off
    image=Image.new('RGB',size,(19,25,37));d=ImageDraw.Draw(image)
    light=np.array([-.3,.65,.7]);light/=np.linalg.norm(light)
    order=np.argsort(quads.mean(1)@depth)
    for i in order:
        shade=.67+.33*max(0,normals[i]@light)
        rgb=tuple(int(v*shade) for v in RGB[cols[i]-1])
        d.polygon([tuple(v) for v in xy[i]],fill=rgb)
    return image


def main():
    for p in ['rigged','previews','parts']: (ROOT/p).mkdir(exist_ok=True)
    definitions=(REPO/'src/ReplicatedStorage/ItemDefinitions.lua').read_text(encoding='utf8')
    expected=set(re.findall(r'ItemDefinitions\.(\w+Wings) = \{',definitions))
    assert expected=={n+'Wings' for n in THEMES},expected
    manifest={'source':'src/ReplicatedStorage/ItemDefinitions.lua','design_reference':'Accessory names and descriptions only; no UI images',
        'axes_vox':'X lateral, +Y rearward, +Z up. Integer coordinates are voxel centres.',
        'axes_glb':'(X,Z,-Y) * 0.0625. +Y up; forward +Z. Each voxel is 0.0625 units.',
        'vox_scene_translation':[0,0,40],
        'attachment':'Frame origin (0,0,0) goes at upper-back centre. Rotate as needed for target character convention.',
        'models':{}}
    builders={'Angel':angel,'Bat':lambda w:membrane(w),'Demon':lambda w:membrane(w,True),'Fairy':fairy,'Flame':flame,'Frost':frost,'Leaf':leaf}
    gallery={};thumbs=[]
    for idx,(theme,builder) in enumerate(builders.items()):
        w=Wing(theme);w.frame();builder(w);w.finish()
        save_vox(ROOT/f'{theme}Wings.vox',w.parts)
        pdir=ROOT/'parts'/f'{theme}Wings';pdir.mkdir(exist_ok=True)
        for name,vox in w.parts.items():save_vox(pdir/f'{name}.vox',{name:vox})
        meshes={n:mesh(v) for n,v in w.parts.items()}
        report=write_glb(w,meshes)
        pts=np.array([p for v in w.parts.values() for p in v]);dims=pts.max(0)-pts.min(0)+1
        manifest['models'][theme+'Wings']={'size_voxels':dims.tolist(),'size_units':(dims*SCALE).tolist(),'joints':w.bones,'parts':report}
        render(meshes).save(ROOT/'previews'/f'{theme}Wings.png')
        render(meshes,view='front').save(ROOT/'previews'/f'{theme}Wings_front.png')
        thumb=render(meshes,(760,470));d=ImageDraw.Draw(thumb)
        d.text((28,20),theme.upper()+' WINGS',font=font(25,True),fill=(239,235,219))
        d.text((28,432),f'{len(w.parts)} articulated pieces  /  {dims[0]} x {dims[1]} x {dims[2]} voxels',font=font(16),fill=(154,171,190))
        thumbs.append(thumb)
        offset=np.array([(idx%3)*170,(idx//3)*130,0])
        for n,v in w.parts.items():gallery[theme+' / '+n]={tuple(np.array(p)+offset):c for p,c in v.items()}
        print(theme,json.dumps({'parts':len(w.parts),'voxels':int(len(pts)),'triangles':sum(r['triangles'] for r in report.values())}),flush=True)
    save_vox(ROOT/'AllWings.vox',gallery)
    contact=Image.new('RGB',(1540,2040),(12,17,27));d=ImageDraw.Draw(contact)
    d.text((30,24),'BLOCKBOUND / WING ATELIER',font=font(35,True),fill=(244,237,213))
    d.text((30,76),'Seven wearable voxel accessories  |  Separate pieces + weighted rigs',font=font(21),fill=(156,178,196))
    for i,im in enumerate(thumbs):contact.paste(im,(10+(i%2)*770,125+(i//2)*475))
    d.text((800,1605),'READY TO POSE',font=font(26,True),fill=(237,218,169))
    for k,s in enumerate(['Native MagicaVoxel scenes','Named left / right components','Shoulder and secondary joints','Rigid weighted GLB exports','Flap + Fold test clips']):
        d.text((800,1655+k*37),s,font=font(21),fill=(164,184,202))
    contact.save(ROOT/'previews'/'AllWings.png')
    (ROOT/'rigging.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')


if __name__=='__main__':main()
