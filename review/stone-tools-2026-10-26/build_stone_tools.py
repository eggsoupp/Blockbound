"""Build the stone review set in Python. No application or asset publishing required."""
from pathlib import Path
from collections import Counter
import json, struct, math, shutil, zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).parent
SIZE=(24,3,24)
PALETTE=[(24,24,24),(40,40,40),(73,73,73),(95,95,95),(108,108,108),
         (127,127,127),(137,137,137),(154,154,154),(182,182,182),
         (40,30,11),(73,54,21),(104,78,30),(137,103,39)]
FILES={'sword':'e94ad0c6-9bca-402a-bcc5-e4e3b3066ef7',
       'pickaxe':'1f3c6b3d-dc66-4f86-8b30-6bcadcf94d96',
       'axe':'725098e6-80a5-477b-8cf3-1d3cb2c6dc0c'}
BG=(230,229,222); INK=(36,40,43)
def font(n):return ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',n)
def nearest(c,options):return min(options,key=lambda p:sum((p[i]-c[i])**2 for i in range(3)))
def source(name):return Image.open(ROOT/'references'/f'{name}.png').convert('RGBA')
def sample_source(name,n):
    im=source(name); out=Image.new('RGBA',(n,n))
    for r in range(n):
        for x in range(n):
            px,py=int((x+.5)*im.width/n),int((r+.5)*im.height/n)
            c=im.getpixel((px,py))
            if c[3]<128:continue
            if max(c[:3])-min(c[:3])<15:c=nearest(c,PALETTE[:9])
            elif name=='sword':
                # Match the three sword wood bands to the common axe/pickaxe timber.
                c=PALETTE[9 if c[0]<65 else 10 if c[0]<95 else 11]
            else:c=nearest(c,PALETTE[9:])
            out.putpixel((x,r),(*c,255))
    return out
def trace(name):
    grid={}
    if name=='sword':
        im=sample_source(name,24)
        for r in range(24):
            for x in range(24):
                c=im.getpixel((x,r))
                if c[3]:grid[x,r]=PALETTE.index(c[:3])+1
    else:
        im=sample_source(name,16)
        # Retain all original source cells; translate the head and extend only the shaft.
        for r in range(16):
            for x in range(16):
                c=im.getpixel((x,r))
                if c[3]:grid[x+6,r+1]=PALETTE.index(c[:3])+1
        # Continue the original diagonal, three-cell wood pattern for four steps.
        oldbottom=15
        # Replace the old butt cap with a continuing shaft, then restore a cap at the end.
        x0=6 if name=='pickaxe' else 7
        for p in list(grid):
            if p[1]>=oldbottom:del grid[p]
        for k in range(5):
            r=oldbottom+k; x=x0-k
            for dx,c in enumerate([11,13 if k%2==0 else 12,10]):grid[x+dx,r]=c
        for dx in range(2):grid[x0-4+dx,oldbottom+5]=10
    return grid

def detail_cells(name,g):
    # Extra depth uses existing silhouette colors, mirrored around Y=1.
    # No new front-view marks and no thickening of the blade perimeter or shaft.
    cells=set()
    if name=='sword':
        cells={(x,r) for (x,r),c in g.items() if c in (5,6,7,8,9) and
               ((12<=r<=19 and x<r-5) or (17<=r<=20 and 9<=x<=12))}
    elif name=='pickaxe':
        cells={(x+6,r+1) for x,r in [(9,3),(10,3),(11,3),(9,4),(10,4),(11,4),(9,5),(10,5),(9,6)]}
    else:
        cells={(x+6,r+1) for x,r in [(9,4),(10,4),(9,5),(10,5),(9,6),(10,6),(9,7)]}
    return cells & set(g)

def chunk(tag,data=b'',children=b''):
    return tag+struct.pack('<II',len(data),len(children))+data+children
def write_vox(name,g):
    relief=detail_cells(name,g)
    vox={(x,1,23-r):c for (x,r),c in g.items()}
    for x,r in relief:
        for y in (0,2):vox[x,y,23-r]=g[x,r]
    rgba=b''.join(bytes((*c,255)) for c in PALETTE)+bytes((0,0,0,255))*(256-len(PALETTE))
    body=chunk(b'SIZE',struct.pack('<III',*SIZE))+chunk(b'XYZI',struct.pack('<I',len(vox))+b''.join(bytes((*p,c)) for p,c in sorted(vox.items())))+chunk(b'RGBA',rgba)
    (ROOT/f'stone_{name}.vox').write_bytes(b'VOX '+struct.pack('<I',150)+chunk(b'MAIN',children=body))

def read_vox(path):
    data=path.read_bytes();assert data[:8]==b'VOX '+struct.pack('<I',150)
    chunks={}
    def scan(start,end):
        while start<end:
            tag=data[start:start+4];n,m=struct.unpack_from('<II',data,start+4)
            stop=start+12+n;assert stop+m<=end
            chunks[tag]=data[start+12:stop]
            if m:scan(stop,stop+m)
            start=stop+m
        assert start==end
    scan(8,len(data));size=struct.unpack('<III',chunks[b'SIZE'])
    raw=chunks[b'XYZI'];count=struct.unpack_from('<I',raw)[0];assert len(raw)==4+count*4
    v=[tuple(raw[i:i+4]) for i in range(4,len(raw),4)]
    points={p[:3]:p[3] for p in v};assert len(v)==len(points)
    rgba=chunks[b'RGBA'];assert len(rgba)==1024
    return size,points,[tuple(rgba[i:i+3]) for i in range(0,1024,4)],rgba

def validate(name,g):
    size,p,colors,rgba=read_vox(ROOT/f'stone_{name}.vox');assert size==SIZE
    assert all(0<=q[i]<size[i] for q in p for i in range(3))
    assert all(1<=c<=len(PALETTE) for c in p.values())
    assert all(p.get((x,2-y,z))==c for (x,y,z),c in p.items())
    front={(x,23-z):c for (x,y,z),c in p.items()};assert front==g
    assert all((x,1,z) in p for x,y,z in p)
    todo=set(p);components=[]
    while todo:
        q=[todo.pop()];n=0
        while q:
            x,y,z=q.pop();n+=1
            for nb in [(x-1,y,z),(x+1,y,z),(x,y-1,z),(x,y+1,z),(x,y,z-1),(x,y,z+1)]:
                if nb in todo:todo.remove(nb);q.append(nb)
        components.append(n)
    assert len(components)==1,(name,components)
    assert all([y for y in range(3) if (x,y,z) in p] in ([1],[0,1,2]) for x,_,z in p)
    if name!='sword':
        original=sample_source(name,16)
        for r in range(14):
            for x in range(16):
                c=original.getpixel((x,r));expected=PALETTE.index(c[:3])+1 if c[3] else 0
                assert g.get((x+6,r+1),0)==expected
    return {'canvas_xyz':size,'voxels':len(p),'center_layer_voxels':len(g),
            'raised_cells_per_side':(len(p)-len(g))//2,'face_connected_components':len(components),
            'mirrored_thickness':True,'front_projection_matches_design':True,'solid_depth_columns':True,
            'source_head_pixels_preserved':name!='sword',
            'occupied_xyz':[max(q[i] for q in p)-min(q[i] for q in p)+1 for i in range(3)]}

def front(name):
    _,points,colors,_=read_vox(ROOT/f'stone_{name}.vox');im=Image.new('RGBA',(24,24))
    for (x,y,z),c in points.items():im.putpixel((x,23-z),(*colors[c-1],255))
    return im

def render(name,scale=20):
    _,points,colors,_=read_vox(ROOT/f'stone_{name}.vox')
    # Flat palette only. Orthographic camera, no texture, gradients, or added bevels.
    def proj(p):
        x,y,z=p;return ((x*.94+y*.62)*scale,(-z+x*.14-y*.26)*scale)
    faces=[]
    for (x,y,z),c in points.items():
        for normal,cs in [((0,-1,0),[(x,y,z),(x+1,y,z),(x+1,y,z+1),(x,y,z+1)]),
                          ((1,0,0),[(x+1,y,z),(x+1,y+1,z),(x+1,y+1,z+1),(x+1,y,z+1)]),
                          ((0,0,1),[(x,y,z+1),(x+1,y,z+1),(x+1,y+1,z+1),(x,y+1,z+1)])]:
            if tuple((x,y,z)[i]+normal[i] for i in range(3)) not in points:
                faces.append((sum(p[0]-.94/.62*p[1]+(.14+.26*.94/.62)*p[2] for p in cs)/4,[proj(p) for p in cs],colors[c-1]))
    ps=[p for _,cs,_ in faces for p in cs];x0=min(x for x,y in ps);y0=min(y for x,y in ps)
    w=math.ceil(max(x for x,y in ps)-x0)+4;h=math.ceil(max(y for x,y in ps)-y0)+4
    im=Image.new('RGBA',(w*3,h*3));d=ImageDraw.Draw(im)
    for _,cs,c in sorted(faces):d.polygon([((x-x0+2)*3,(y-y0+2)*3) for x,y in cs],fill=(*c,255))
    return im.resize((w,h),Image.Resampling.LANCZOS)

def paste_center(panel,im,cx,cy):panel.paste(im,(int(cx-im.width/2),int(cy-im.height/2)),im)
def previews():
    board=Image.new('RGB',(1440,730),BG);d=ImageDraw.Draw(board)
    d.text((30,22),'STONE TOOLS  /  REVIEW',font=font(29),fill=INK)
    d.text((30,65),'Shared 24 x 3 x 24 grid  |  Center-layer body + mirrored raised details  |  Flat shared palette',font=font(18),fill=INK)
    compare=Image.new('RGB',(1440,1000),BG);cd=ImageDraw.Draw(compare)
    cd.text((30,20),'SOURCE REFERENCE / MODEL FRONT',font=font(28),fill=INK)
    for i,name in enumerate(FILES):
        f=front(name);f.resize((576,576),Image.Resampling.NEAREST).save(ROOT/f'stone_{name}_front.png')
        iso=render(name,21);iso.save(ROOT/f'stone_{name}_angled.png')
        panel=Image.new('RGB',(1100,680),BG);pd=ImageDraw.Draw(panel)
        pd.text((30,22),'STONE '+name.upper(),font=font(30),fill=INK)
        pd.text((30,65),'24 x 3 x 24 voxels | 1-voxel body | 3 voxels at raised details',font=font(19),fill=INK)
        paste_center(panel,f.resize((480,480),Image.Resampling.NEAREST),275,355)
        paste_center(panel,iso,815,355)
        pd.text((180,625),'Matching front view',font=font(21),fill=INK)
        pd.text((740,625),'Angled view',font=font(21),fill=INK)
        panel.save(ROOT/f'stone_{name}_preview.png')
        d.text((i*480+30,119),name.upper(),font=font(25),fill=INK)
        paste_center(board,render(name,20),i*480+240,395)
        d.text((i*480+30,656),'24 x 3 x 24  /  Same voxel scale',font=font(19),fill=INK)
        src=source(name);ratio=min(430/src.width,420/src.height)
        src=src.resize((round(src.width*ratio),round(src.height*ratio)),Image.Resampling.NEAREST)
        paste_center(compare,src,i*480+240,280)
        cd.text((i*480+30,510),name.upper(),font=font(23),fill=INK)
        paste_center(compare,f.resize((432,432),Image.Resampling.NEAREST),i*480+240,765)
    board.save(ROOT/'stone_tools_preview.png');compare.save(ROOT/'reference_comparison.png')

def main():
    (ROOT/'references').mkdir(exist_ok=True)
    for name,uid in FILES.items():
        dest=ROOT/'references'/f'{name}.png'
        if not dest.exists():shutil.copyfile(Path('C:/Users/Elias/AppData/Local/Temp')/f'codex-clipboard-{uid}.png',dest)
    grids={name:trace(name) for name in FILES}
    for name,g in grids.items():write_vox(name,g)
    report={name:validate(name,g) for name,g in grids.items()}
    palettes=[read_vox(ROOT/f'stone_{name}.vox')[3] for name in FILES]
    assert all(p==palettes[0] for p in palettes)
    report['shared_palette_byte_identical']=True
    (ROOT/'validation.json').write_text(json.dumps(report,indent=2))
    (ROOT/'shared_palette.json').write_text(json.dumps(PALETTE,indent=2))
    (ROOT/'design_grids.json').write_text(json.dumps({name:[[g.get((x,r),0) for x in range(24)] for r in range(24)] for name,g in grids.items()},indent=2))
    sw=Image.new('RGB',(len(PALETTE)*48,48));sd=ImageDraw.Draw(sw)
    for i,c in enumerate(PALETTE):sd.rectangle((i*48,0,i*48+47,47),fill=c)
    sw.save(ROOT/'shared_palette.png');previews();print(json.dumps(report,indent=2))
if __name__=='__main__':main()
