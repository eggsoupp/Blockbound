"""Reference pixel sampling, solid extrusion, VOX serialization and review renders."""
from pathlib import Path
from collections import Counter, deque
import struct, json, math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).parent
TEMP = Path('C:/Users/Elias/AppData/Local/Temp')
SOURCES = {
    'pickaxe': TEMP/'codex-clipboard-35bb91a2-ed9d-4a03-a0ca-c89be5b8022f.png',
    'sword': TEMP/'codex-clipboard-c7b09096-a79b-45bc-b922-88bfa417e52d.png',
    'axe': TEMP/'codex-clipboard-1d4ddedf-fdfa-4c4f-9f6a-4cefc605bb61.png',
}
THICKNESS = 2
FONT = 'C:/Windows/Fonts/segoeui.ttf'
def font(n): return ImageFont.truetype(FONT,n)
def sample(im,x,y):
    return Counter(im.crop((int(x)-3,int(y)-3,int(x)+4,int(y)+4)).get_flattened_data()).most_common(1)[0][0]
def nearest(c,colors): return min(colors,key=lambda q:sum((c[k]-q[k])**2 for k in range(3)))

# All entries come from the source art. The first ten are the exact axe palette.
PALETTE = [(55,41,16),(134,101,38),(107,81,31),(117,88,33),(73,54,21),
           (104,78,30),(32,24,10),(89,67,25),(40,30,11),(137,103,39),
           (30,30,30),(166,97,55),(136,68,47),
           (25,18,7),(81,60,21),(105,74,28),(109,94,60),(90,79,53)]
PICK_COLORS = [PALETTE[i] for i in (0,7,8,13,14,15,16,17)]

def trace(name):
    im=Image.open(SOURCES[name]).convert('RGBA')
    if name=='sword':
        # 17.65 image pixels per source pixel. Remove the white sticker border.
        # Preserve the six source color bands, using only existing axe wood colors.
        source_colors=[(29,30,32),(57,24,41),(93,37,40),(129,71,34),(184,114,29),(234,194,106)]
        target_indices=[9,1,5,8,3,2]
        grid=[]
        for y in range(34):
            row=[]
            for x in range(34):
                c=sample(im,(x+.5)*im.width/34,(y+.5)*im.height/34)
                row.append(0 if min(c[:3])>160 else target_indices[source_colors.index(nearest(c,source_colors))])
            grid.append(row)
        occupied=[(x,y) for y,row in enumerate(grid) for x,c in enumerate(row) if c]
        x0,x1=min(p[0] for p in occupied),max(p[0] for p in occupied)
        y0,y1=min(p[1] for p in occupied),max(p[1] for p in occupied)
        return [row[x0:x1+1] for row in grid[y0:y1+1]]
    n=24 if name=='sword' else 16
    w=15 if name=='pickaxe' else n
    # Recover front-facing cells only: do not copy item-frame scenery or extrusion shadow.
    occupied=[range(2,6),range(1,8),list(range(1,10))+[12,13],range(5,14),
              range(7,13),range(8,13),range(8,14),range(7,15),
              [6,7,8,11,12,13,14],[5,6,7,12,13],range(4,7),range(3,6),
              range(2,5),range(1,4),range(0,3),range(0,2)]
    grid=[]
    for y in range(n):
        row=[]
        for x in range(w):
            if name=='pickaxe':
                c=sample(im,307+(x+.5)*48,262+(y+.5)*48)
                c=nearest(c,PICK_COLORS) if x in occupied[y] else None
            else:
                c=sample(im,(x+.5)*im.width/n,(y+.5)*im.height/n)
                if c[3]==0 or (name=='sword' and min(c[:3])>210): c=None
                else: c=nearest(c, PALETTE[10:13]) if name=='sword' else c[:3]
            row.append(0 if c is None else PALETTE.index(c)+1)
        grid.append(row)
    return grid

def chunk(tag,data=b'',children=b''):
    return tag+struct.pack('<II',len(data),len(children))+data+children

def write_vox(name,g):
    h,w=len(g),len(g[0])
    vox=[(x,y,h-1-r,c) for r,row in enumerate(g) for x,c in enumerate(row) if c for y in range(THICKNESS)]
    rgba=read_vox(ROOT/'pickaxe.vox')[3] if name=='sword' and (ROOT/'pickaxe.vox').exists() else b''.join(bytes((*c,255)) for c in PALETTE)+bytes((0,0,0,255))*(256-len(PALETTE))
    children=chunk(b'SIZE',struct.pack('<III',w,THICKNESS,h))+chunk(b'XYZI',struct.pack('<I',len(vox))+b''.join(bytes(v) for v in vox))+chunk(b'RGBA',rgba)
    (ROOT/f'{name}.vox').write_bytes(b'VOX '+struct.pack('<I',150)+chunk(b'MAIN',children=children))

def read_vox(path):
    b=path.read_bytes()
    assert b[:4]==b'VOX ' and struct.unpack_from('<I',b,4)[0] in (150,200)
    chunks={}
    def scan(start,end):
        while start<end:
            tag=b[start:start+4]; n,m=struct.unpack_from('<II',b,start+4)
            data=b[start+12:start+12+n]; assert len(data)==n
            chunks.setdefault(tag,[]).append(data)
            if m: scan(start+12+n,start+12+n+m)
            start+=12+n+m
        assert start==end
    scan(8,len(b))
    size=struct.unpack('<III',chunks[b'SIZE'][0]); raw=chunks[b'XYZI'][0]
    count=struct.unpack_from('<I',raw)[0]; assert len(raw)==4+count*4
    vox=[tuple(raw[i:i+4]) for i in range(4,len(raw),4)]
    rgba=chunks[b'RGBA'][0]; assert len(rgba)==1024
    colors=[tuple(rgba[i:i+3]) for i in range(0,1024,4)]
    return size,vox,colors,rgba

def validate(name,g):
    size,vox,colors,rgba=read_vox(ROOT/f'{name}.vox')
    points={(x,y,z):c for x,y,z,c in vox}
    assert len(points)==len(vox)
    assert all(0<=p[k]<size[k] for p in points for k in range(3))
    assert all(points[(x,size[1]-1-y,z)]==c for (x,y,z),c in points.items())
    assert size[1]==THICKNESS
    for r,row in enumerate(g):
        for x,c in enumerate(row):
            for y in range(THICKNESS):
                actual=points.get((x,y,len(g)-1-r),0)
                assert bool(actual)==bool(c)
                if c: assert colors[actual-1]==PALETTE[c-1]
    todo=set(points); components=[]
    while todo:
        q=[todo.pop()]; n=0
        while q:
            p=q.pop(); n+=1
            for axis in range(3):
                for d in [-1,1]:
                    nb=list(p); nb[axis]+=d; nb=tuple(nb)
                    if nb in todo: todo.remove(nb); q.append(nb)
        components.append(n)
    assert len(components)==1,components
    return {'size_xyz':size,'voxel_count':len(vox),'connected_components':len(components),
            'front_back_symmetry':True,'front_projection_matches_trace':True,'solid_depth':THICKNESS}

def front_image(name):
    size,vox,colors,_=read_vox(ROOT/f'{name}.vox')
    im=Image.new('RGBA',(size[0],size[2]))
    for x,y,z,c in vox:
        if y==0: im.putpixel((x,size[2]-1-z),(*colors[c-1],255))
    return im

def model_render(name,scale=19):
    size,vox,colors,_=read_vox(ROOT/f'{name}.vox')
    points={(x,y,z):c for x,y,z,c in vox}
    # Orthographic view, looking at the reference-facing (-Y) side, with a modest turn.
    def proj(p):
        x,y,z=p
        return ((x*.96+y*.55)*scale,(-z+x*.13-y*.29)*scale)
    faces=[]
    for (x,y,z),c in points.items():
        for normal,corners in [((0,-1,0),[(x,y,z),(x+1,y,z),(x+1,y,z+1),(x,y,z+1)]),
                               ((1,0,0),[(x+1,y,z),(x+1,y+1,z),(x+1,y+1,z+1),(x+1,y,z+1)]),
                               ((0,0,1),[(x,y,z+1),(x+1,y,z+1),(x+1,y+1,z+1),(x,y+1,z+1)])]:
            if (x+normal[0],y+normal[1],z+normal[2]) not in points:
                faces.append((sum(p[0]-.7*p[1]+p[2]*.4 for p in corners)/4,[proj(p) for p in corners],colors[c-1]))
    allpts=[p for _,ps,_ in faces for p in ps]
    mnx=min(p[0] for p in allpts); mny=min(p[1] for p in allpts)
    w=math.ceil(max(p[0] for p in allpts)-mnx)+6; h=math.ceil(max(p[1] for p in allpts)-mny)+6
    im=Image.new('RGBA',(w*3,h*3)); d=ImageDraw.Draw(im)
    for _,ps,c in sorted(faces,key=lambda f:f[0]):
        d.polygon([((x-mnx+3)*3,(y-mny+3)*3) for x,y in ps],fill=(*c,255))
    return im.resize((w,h),Image.Resampling.LANCZOS)

def previews():
    board=Image.new('RGB',(1440,780),(237,235,226)); d=ImageDraw.Draw(board)
    d.text((36,22),'REFERENCE TOOL SET',font=font(28),fill=(38,40,40))
    d.text((36,61),'One voxel per source pixel  /  two-voxel solid depth  /  shared palette',font=font(18),fill=(83,82,77))
    comparison=Image.new('RGB',(1440,1030),(237,235,226)); cd=ImageDraw.Draw(comparison)
    cd.text((30,20),'REFERENCE  /  MATCHING FRONT VIEW',font=font(28),fill=(38,40,40))
    for i,name in enumerate(['pickaxe','sword','axe']):
        front=front_image(name)
        front.resize((front.width*24,front.height*24),Image.Resampling.NEAREST).save(ROOT/f'{name}-front.png')
        panel=Image.new('RGB',(680,660),(237,235,226)); pd=ImageDraw.Draw(panel)
        pd.text((24,18),name.upper(),font=font(27),fill=(38,40,40))
        pd.text((24,59),f'{front.width} x 2 x {front.height} voxel canvas',font=font(17),fill=(83,82,77))
        panel_scale=min(14,280//front.width,350//front.height)
        a=front.resize((front.width*panel_scale,front.height*panel_scale),Image.Resampling.NEAREST)
        b=model_render(name,panel_scale)
        panel.paste(a,(int(165-a.width/2),135+int((350-a.height)/2)),a)
        panel.paste(b,(int(490-b.width/2),135+int((350-b.height)/2)),b)
        pd.text((95,540),'Matching front',font=font(19),fill=(60,60,56))
        pd.text((423,540),'Depth view',font=font(19),fill=(60,60,56))
        panel.save(ROOT/f'{name}-preview.png')
        bx=i*480
        d.text((bx+30,112),name.upper(),font=font(25),fill=(38,40,40))
        b=model_render(name,17)
        board.paste(b,(int(bx+240-b.width/2),174+int((425-b.height)/2)),b)
        thumb=front.resize((front.width*5,front.height*5),Image.Resampling.NEAREST)
        board.paste(thumb,(bx+50,620),thumb)
        d.text((bx+190,632),f'{front.width} x 2 x {front.height}',font=font(21),fill=(38,40,40))
        d.text((bx+190,670),'Front + depth view',font=font(16),fill=(83,82,77))
        src=Image.open(SOURCES[name]).convert('RGBA')
        src.thumbnail((420,420),Image.Resampling.NEAREST)
        comparison.paste(src,(bx+int((480-src.width)/2),90),src)
        cd.text((bx+30,525),name.upper()+'  /  VOX FRONT',font=font(20),fill=(38,40,40))
        f=front.resize((front.width*17,front.height*17),Image.Resampling.NEAREST)
        comparison.paste(f,(bx+int((480-f.width)/2),580),f)
    board.save(ROOT/'set-preview.png'); comparison.save(ROOT/'reference-comparison.png')

def main():
    import sys
    grids={name:trace(name) for name in SOURCES}
    if '--verify-only' not in sys.argv:
        for name,g in grids.items():
            if '--sword-only' not in sys.argv or name=='sword': write_vox(name,g)
    report={name:validate(name,g) for name,g in grids.items()}
    palettes=[read_vox(ROOT/f'{name}.vox')[3] for name in grids]
    assert all(p==palettes[0] for p in palettes)
    report['shared_palette_identical']=True
    used={name:{colors[v[3]-1] for v in vox} for name in grids for _,vox,colors,_ in [read_vox(ROOT/f'{name}.vox')]}
    assert used['sword'] <= used['axe']
    report['sword_uses_only_existing_axe_wood_colors']=True
    report['sword_used_colors_rgb']=sorted(used['sword'])
    (ROOT/'validation.json').write_text(json.dumps(report,indent=2))
    (ROOT/'pixel-traces.json').write_text(json.dumps({'palette_rgb':PALETTE,'grids':grids},indent=2))
    swatches=Image.new('RGBA',(256,1)); swatches.putdata([(*c,255) for c in PALETTE]+[(0,0,0,255)]*(256-len(PALETTE)))
    swatches.save(ROOT/'shared-palette.png')
    previews()
    print(json.dumps(report,indent=2))
if __name__=='__main__': main()
