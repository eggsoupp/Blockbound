import math, struct, json, pathlib, zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT=pathlib.Path(__file__).parent
PAL=[(19,17,39),(28,24,57),(39,31,77),(48,37,96),(61,46,119),(78,56,143),(101,70,166),(129,93,187), (129,78,35),(174,110,46),(211,151,68),(245,192,98),(255,222,144),(255,239,189), (15,66,137),(18,108,194),(25,163,238),(71,214,255),(176,245,255), (24,87,163),(28,127,197),(30,103,72),(53,142,75),(99,166,68),(180,188,116),(222,237,239), (93,34,18),(137,46,18),(181,65,20),(222,92,24),(248,132,39),(255,174,72), (96,67,140),(129,96,173),(167,135,199),(210,178,213),(222,195,153),(245,218,171), (83,80,96),(119,114,128),(161,153,163)]
parts={}; joints=[]
def noise(x,y,z): return ((x*73856093)^(y*19349663)^(z*83492791))%101
def skin(x,y,z):
    n=noise(x,y,z)
    if n<3:return 16+n%3
    return 1+((x//3+y//3+z//2)%4 if n>15 else 5)
def gold(x,y,z):return 9+noise(x//2,y//2,z//2)%5
def put(name,p,c):parts.setdefault(name,{})[tuple(map(int,p))]=int(c)
def ell(name,center,radii,color=skin):
    c=np.array(center); r=np.array(radii)
    lo=np.floor(c-r).astype(int);hi=np.ceil(c+r).astype(int)
    grid=np.indices(tuple(hi-lo+1)).reshape(3,-1).T+lo
    grid=grid[np.sum(((grid-c)/r)**2,axis=1)<=1]
    dest=parts.setdefault(name,{})
    for p in grid:
      x,y,z=map(int,p);dest[x,y,z]=int(color(x,y,z) if callable(color) else color)
def tube(name,points,radii,color=skin):
    for a,b,ra,rb in zip(points,points[1:],radii,radii[1:]):
      a=np.array(a); b=np.array(b); steps=max(1,int(np.linalg.norm(b-a)*1.3))
      for t in np.linspace(0,1,steps+1):
       p=a*(1-t)+b*t; r=ra*(1-t)+rb*t
       ell(name,p,(max(.6,r),)*3,color)
def tri(name,a,b,c):
    a,b,c=map(np.array,(a,b,c)); steps=int(max(np.linalg.norm(a-b),np.linalg.norm(a-c))*1.8)
    for i in range(steps+1):
      for j in range(steps+1-i):
       p=np.rint(a+(b-a)*i/steps+(c-a)*j/steps).astype(int); x,y,z=p
       n=noise(x,y,z); col=15+n%4 if n<9 else 3+int((math.sin(x*.17+z*.13)+1)*2)
       for dy in [0,1]:put(name,(x,y+dy,z),col)
def joint(name,parent,p):joints.append(dict(part=name,parent=parent,pivot=list(p)))

# Z up, dragon faces -Y. The articulated silhouette is authored in a spread-wing pose.
ell('pelvis',(0,6,55),(19,15,23)); joint('pelvis',None,(0,6,55))
ell('chest',(0,2,87),(23,17,32));joint('chest','pelvis',(0,4,73))
for z in range(67,112):
 w=int(13-abs(z-87)*.16)
 for x in range(-w,w+1):
  y=-int(16*math.sqrt(max(0,1-(x/24)**2)))
  put('chest',(x,y,z),gold(x,y,z) if (z//5)%3==0 or abs(x)>w-2 else 15+(x+z)%3)
tube('neck_lower',[(0,3,108),(0,7,127),(0,4,138)],[14,12,10]);joint('neck_lower','chest',(0,3,111))
tube('neck_upper',[(0,4,135),(0,-2,149),(0,-9,155)],[10,9,8]);joint('neck_upper','neck_lower',(0,4,135))
ell('head',(0,-13,157),(12,17,11));ell('head',(0,-29,153),(8,12,6));joint('head','neck_upper',(0,-9,155))
ell('jaw',(0,-26,146),(8,14,3));joint('jaw','head',(0,-13,147))
for s in [-1,1]:
 ell('head',(s*10,-22,160),(2,6,3),18);ell('head',(s*11,-23,160),(1,3,2),19)
 tube('head',[(s*7,-29,149),(s*7,-33,142)],[2,0.6],gold)
 for k in range(3):
  tube('head',[(s*(7+k*2),-8+k*5,163),(s*(13+k*4),2+k*7,178+k*3),(s*(15+k*5),-1+k*7,190+k*3)],[3.5,2,0.6],gold)
 for k in range(6):
  tube('neck_upper',[(s*8,4,145-k*3),(s*(17+k),10+k*2,151-k*3),(s*(23+k),17+k*2,152-k*3)],[3,2,.6],skin)
 for seg,(a,b,rad) in enumerate([((s*19,2,99),(s*37,-2,92),9),((s*37,-2,92),(s*51,-14,109),6)]):
  nm=('upper_arm_' if seg==0 else 'forearm_')+str(s);tube(nm,[a,b],[rad,rad*.7]);joint(nm,'chest' if seg==0 else 'upper_arm_'+str(s),a)
 nm='hand_'+str(s);ell(nm,(s*53,-16,113),(8,6,6));joint(nm,'forearm_'+str(s),(s*51,-14,109))
 for k in range(4):
  x=s*(47+k*4)
  tube(nm,[(x,-18,115),(x+s*3,-24,114),(x+s*3,-27,106)],[2.7,2,0.7],gold)
 # Folded digitigrade rear legs, separated at knee and ankle.
 for nm,parent,a,b,r in [('thigh','pelvis',(s*13,7,57),(s*27,2,37),10),('shin','thigh',(s*27,2,37),(s*24,14,20),6),('foot','shin',(s*24,14,20),(s*24,-2,13),5)]:
  name=nm+'_'+str(s);tube(name,[a,b],[r,r*.65]);joint(name,parent if parent=='pelvis' else parent+'_'+str(s),a)
 for k in range(3):tube('foot_'+str(s),[(s*24+(k-1)*4,-1,13),(s*24+(k-1)*5,-10,11)],[2.5,.6],gold)
 # Separate wing root and fan: solid membranes, structural fingers, gold leading edges.
 root='wing_root_'+str(s);fan='wing_fan_'+str(s)
 tube(root,[(s*17,12,104),(s*38,15,130),(s*54,12,165)],[6,4,3]);joint(root,'chest',(s*17,12,104));joint(fan,root,(s*54,12,165))
 a=(s*54,12,165); tips=[(s*112,18,125),(s*116,15,63),(s*95,13,79),(s*78,12,85),(s*59,11,93),(s*32,11,103)]
 for b,c in zip(tips,tips[1:]):tri(fan,a,b,c)
 for k,t in enumerate(tips):
  mid=((a[0]+t[0])*.5,12,(a[2]+t[2])*.5+5)
  tube(fan,[a,mid,t],[2.8,2,0.6],gold if k<2 else skin)
 tube(fan,[a,(s*82,16,153),tips[0]],[3,2.5,.6],gold)
 for b,c in zip(tips,tips[1:]):tube(fan,[b,c],[1,1],lambda x,y,z:6+noise(x,y,z)%3)

# Sweeping, individually segmented coil.
path=[(0,13,55),(-14,22,39),(-38,18,25),(-63,4,19),(-72,-17,15),(-61,-36,12),(-35,-46,10),(0,-49,9),(35,-43,10),(58,-29,14),(65,-9,19),(54,3,24),(39,-1,28)]
for i in range(len(path)-1):
 nm=f'tail_{i+1:02}';r=max(2,14-i*.95);tube(nm,path[i:i+2],[r,max(1,r-1.2)]);joint(nm,'pelvis' if i==0 else f'tail_{i:02}',path[i])
 for t in np.linspace(0,1,15):
  p=np.array(path[i])*(1-t)+np.array(path[i+1])*t;p[2]+=r*.85
  ell(nm,p,(1.7,1.7,1.4),gold)
for z in range(65,142,8):tube('chest' if z<112 else 'neck_lower',[(0,17 if z<112 else 14,z),(0,24 if z<112 else 22,z+9)],[3,.7],gold)

def i32(*v):return struct.pack('<'+'i'*len(v),*v)
def string(s):b=str(s).encode();return i32(len(b))+b
def dic(d):return i32(len(d))+b''.join(string(k)+string(v) for k,v in d.items())
def chunk(n,b):return n.encode()+i32(len(b),0)+b
def save(path,models):
 data=b''; info=[]
 for name,vox in models.items():
  pts=np.array(list(vox));lo=pts.min(0);hi=pts.max(0);size=hi-lo+1
  assert max(size)<=256
  data+=chunk('SIZE',i32(*size));raw=b''.join(bytes((*map(int,p-lo),vox[tuple(p)])) for p in pts)
  data+=chunk('XYZI',i32(len(pts))+raw);info.append((name,lo,size))
 data+=chunk('RGBA',b''.join(bytes((*c,255)) for c in PAL)+bytes(4*(256-len(PAL))))
 data+=chunk('nTRN',i32(0)+dic({'_name':path.stem})+i32(1,-1,-1,1)+dic({}))
 data+=chunk('nGRP',i32(1)+dic({})+i32(len(info))+i32(*[2+2*k for k in range(len(info))]))
 for k,(name,lo,size) in enumerate(info):
  tr=lo+size//2
  data+=chunk('nTRN',i32(2+2*k)+dic({'_name':name})+i32(3+2*k,-1,k,1)+dic({'_t':' '.join(map(str,tr))}))
  data+=chunk('nSHP',i32(3+2*k)+dic({})+i32(1,k)+dic({}))
  data+=chunk('LAYR',i32(k)+dic({'_name':name})+i32(-1))
 for idx in range(16,20):data+=chunk('MATL',i32(idx)+dic({'_type':'_emit','_emit':'0.6','_flux':'1'}))
 path.write_bytes(b'VOX '+i32(150)+b'MAIN'+i32(0,len(data))+data)

dragon=parts;save(OUT/'cosmic_dragon.vox',dragon)
(OUT/'parts').mkdir(exist_ok=True)
for name,vox in dragon.items():save(OUT/'parts'/f'{name}.vox',{name:vox})
planets={}
for kind,r in [('earth',22),('ember',18),('ringed',25)]:
 parts={}
 def col(x,y,z):
  n=noise(x//2,y//2,z//2)
  if kind=='earth':
   f=math.sin(x*.19+y*.1)+math.cos(y*.23-z*.13)+math.sin(z*.23+x*.13)
   return 26 if abs(z)>19 or (n<13 and z>5) else (22+n%4 if f>.65 else 20+n%2)
  if kind=='ember':return 27+int((math.sin(x*.32+z*.27)+math.cos(y*.34-z*.22)+2)*1.2)%6
  return 33+(z//4)%6
 ell('planet',(0,0,0),(r,r,r),col)
 if kind=='ringed':
  for x in range(-43,44):
   for y in range(-43,44):
    rho=math.hypot(x,y)
    if 31<rho<43 and not 36<rho<38:
     z=round(x*.24+y*.12)
     put('rings',(x,y,z),37 if int(rho)%3 else 34)
 save(OUT/f'planet_{kind}.vox',parts);planets[kind]=parts

# Software surface renderer: orthographic voxel faces, without requiring a VOX editor.
def render(models,path,size=1500):
 vox={p:c for model in models.values() for p,c in model.items()}
 right=np.array([.94,.342,0]); up=np.array([-.12,.33,.936]);depth=np.cross(right,up)
 pts=np.array(list(vox)); screen=np.stack((pts@right,-pts@up),1);lo=screen.min(0);hi=screen.max(0)
 scale=(size-100)/max(hi-lo);offset=np.array([size/2,size/2])-(lo+hi)/2*scale
 im=Image.new('RGB',(size,size),(12,15,28));d=ImageDraw.Draw(im)
 faces=[]
 for p,c in vox.items():
  p=np.array(p)
  for axis in range(3):
   sign=1 if depth[axis]>0 else -1;n=np.eye(3,dtype=int)[axis]*sign
   if tuple(p+n) in vox:continue
   a=np.eye(3)[(axis+1)%3]*.5;b=np.eye(3)[(axis+2)%3]*.5;center=p+n*.5
   corners=[center-a-b,center+a-b,center+a+b,center-a+b]
   poly=[tuple(np.array([q@right,-q@up])*scale+offset) for q in corners]
   shade=[.78,.62,1.0][axis];rgb=tuple(int(v*shade) for v in PAL[c-1])
   faces.append((center@depth,poly,rgb))
 for _,poly,rgb in sorted(faces,key=lambda f:f[0]):d.polygon(poly,fill=rgb)
 im.save(path)
render(dragon,OUT/'dragon_preview.png')
for name,model in planets.items():render(model,OUT/f'{name}_preview.png',650)
manifest={'axes':'X lateral, Y depth (front = -Y), Z up','units':'one voxel','joints':joints,'counts':{n:len(v) for n,v in dragon.items()},'note':'Pivots use assembled world voxel coordinates. VOX contains named rigid pieces, not bones or skin weights.'}
(OUT/'rigging.json').write_text(json.dumps(manifest,indent=2))
print(json.dumps({'dragon_parts':len(dragon),'dragon_voxels':sum(map(len,dragon.values())),'files':[p.name for p in OUT.glob('*.vox')]},indent=2))
