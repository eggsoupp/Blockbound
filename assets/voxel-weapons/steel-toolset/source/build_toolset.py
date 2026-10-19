"""Build three solid, editable MagicaVoxel props and render exported geometry.

Python 3 + numpy + Pillow. Run from any directory. +Z up, Y thickness.
"""
from pathlib import Path
import json
import zipfile
import numpy as np
from PIL import Image, ImageDraw
import voxel_utils as io

ROOT = Path(__file__).resolve().parents[1]
# Slots 1-16 preserve the project's existing wood/linen palette.
PALETTE = [
    ('Wood deep shadow', '#51351e'), ('Wood shadow', '#664322'),
    ('Wood dark edge', '#79522b'), ('Wood edge', '#896035'),
    ('Wood brown', '#997243'), ('Wood ochre', '#aa8250'),
    ('Wood warm', '#b7925d'), ('Wood tan', '#c3a36e'),
    ('Wood face', '#cdb480'), ('Wood light', '#d8bf8b'),
    ('Wood highlight', '#e1cc9b'), ('Linen shadow', '#8e8879'),
    ('Linen shade', '#a59e8d'), ('Linen base', '#bcb4a2'),
    ('Linen light', '#cec6b4'), ('Linen highlight', '#dfd6c2'),
    ('Steel deepest', '#363440'), ('Steel shadow', '#55535f'),
    ('Steel dark', '#72717b'), ('Steel body', '#94959a'),
    ('Steel light', '#b2b6b6'), ('Steel edge', '#cdd2ce'),
    ('Steel glint', '#e5e7d6'), ('Steel warm reflection', '#bcbda3'),
    ('Leather deep', '#4b2b22'), ('Leather shade', '#70412c'),
    ('Leather body', '#945333'), ('Leather light', '#b56c40'),
]
io.RGB = np.array([tuple(bytes.fromhex(h[1:])) for _, h in PALETTE], np.uint8)


class Sculpt:
    def __init__(self):
        self.v = {}

    def put(self, x, y, z, c):
        self.v[int(x), int(y), int(z)] = c

    def column(self, x, z, depth, c, side=None):
        for y in range(-depth, depth + 1):
            self.put(x, y, z, c if abs(y) == depth else (side or c))

    def shaft(self, z0, z1):
        """Plain 2 x 2 wooden handle, with just two wood colors."""
        for z in range(z0, z1 + 1):
            for x in (-1, 0):
                for y in (-1, 0):
                    self.put(x, y, z, 6 if x == -1 else 4)

    def array(self):
        lo = np.min(list(self.v), axis=0)
        hi = np.max(list(self.v), axis=0)
        a = np.zeros(tuple(hi-lo+1), np.uint8)
        for p, c in self.v.items():
            a[tuple(np.array(p)-lo)] = c
        return a, (-lo).tolist()


def sword():
    s = Sculpt()
    # Small unadorned metal pommel and plain leather grip.
    for z in (0, 1):
        for x in (-1, 0, 1):
            s.column(x, z, 1, 20, 18)
    for z in range(2, 8):
        for x in (-1, 0, 1):
            s.column(x, z, 1 if x == 0 else 0, 27 if z != 4 else 26, 26)
    # Short crossguard with one upward step at each end.
    for x in range(-6, 7):
        bottom = 8 + int(abs(x) >= 5)
        for z in (bottom, bottom+1):
            s.column(x, z, 1 if abs(x) <= 2 else 0, 20 if z == bottom else 22, 18)
    # Simple five-voxel-wide steel blade, tapering to a small point.
    for z in range(10, 32):
        w = 2 if z < 29 else 1 if z < 31 else 0
        for x in range(-w, w+1):
            edge = abs(x) == w
            s.column(x, z, 0 if edge else 1, 22 if edge else 20, 18)
    return s.array()


def pickaxe():
    s = Sculpt()
    s.shaft(0, 22)
    # Tiny metal end cap, same footprint as the handle.
    for x in (-1, 0):
        for y in (-1, 0):
            s.put(x, y, 0, 20)
    # Compact double-ended pick, broad at the eye and thin at the points.
    for x in range(-9, 10):
        u = abs(x)
        top = 22 - max(0, (u-2)//2)
        for z in range(top-1, top+1):
            s.column(x, z, 1 if u <= 4 else 0, 22 if z == top else 20, 18)
    for x in (-1, 0, 1):
        for z in range(20, 24):
            s.column(x, z, 1, 22 if z == 23 else 20, 18)
    return s.array()


def axe():
    s = Sculpt()
    s.shaft(0, 21)
    # Plain socket and compact single bit, with a shallow beard.
    profile = {
        -2:(19,22), -1:(19,22), 0:(19,22), 1:(19,22),
        2:(19,22), 3:(18,23), 4:(17,23), 5:(16,23),
        6:(16,23), 7:(17,23), 8:(18,22), 9:(20,21),
    }
    for x, (low, high) in profile.items():
        for z in range(low, high+1):
            right = max(xx for xx,(l,h) in profile.items() if l <= z <= h)
            edge = right-x
            s.column(x, z, 0 if edge == 0 else 1, 22 if edge == 0 else 20, 18)
    return s.array()


def palette_files():
    data = {'name':'Blockbound - Wood, Linen, Steel and Leather',
            'indexing':'0 is empty. RGBA entry 0 maps to voxel color index 1.',
            'compatibility':'Indices 1-16 preserve the existing wooden sword palette.',
            'colors':[{'index':i+1,'name':name,'hex':h} for i,(name,h) in enumerate(PALETTE)]}
    (ROOT/'shared_palette.json').write_text(json.dumps(data, indent=2)+'\n')
    gpl = ['GIMP Palette', 'Name: Blockbound shared tool palette', 'Columns: 7', '#']
    for i, ((name,h), rgb) in enumerate(zip(PALETTE, io.RGB)):
        gpl.append(f'{rgb[0]:3} {rgb[1]:3} {rgb[2]:3}\t{i+1:02} {name}')
    (ROOT/'shared_palette.gpl').write_text('\n'.join(gpl)+'\n')
    im = Image.new('RGB',(1120,240),'#1b2028')
    d = ImageDraw.Draw(im)
    for i,(_,h) in enumerate(PALETTE):
        x,y = (i%14)*80, (i//14)*120
        d.rectangle((x+6,y+6,x+73,y+80),fill=h)
        d.text((x+12,y+88),f'{i+1:02d}  {h[1:]}',font=io.font(11),fill='#d3d5d9')
    im.save(ROOT/'shared_palette.png')


def previews(models):
    pre = ROOT/'previews'
    pre.mkdir(exist_ok=True)
    overview = Image.new('RGB',(1800,1080),'#1b2028')
    d = ImageDraw.Draw(overview)
    d.text((64,34),'BLOCKBOUND / BEGINNER TOOLSET',font=io.font(36,True),fill='#e5e7df')
    d.text((66,86),'Small voxel models  /  simple shapes  /  one shared indexed palette',font=io.font(20),fill='#a1aab7')
    for i,(name,a,report) in enumerate(models):
        title = name.replace('_',' ').upper()
        scale = min(23, 760/a.shape[2], 510/a.shape[0])
        hero = io.render(a,(560,800),az=-74,el=10,scale=scale)
        hero.save(pre/f'{name}_transparent.png')
        overview.paste(hero,(20+i*600,140),hero)
        d.text((65+i*600,951),title,font=io.font(25,True),fill='#e5e7df')
        d.text((65+i*600,995),' x '.join(map(str,a.shape))+f' grid  /  {report["voxels"]} voxels',font=io.font(19),fill='#a1aab7')
        sheet = Image.new('RGB',(1600,1080),'#1b2028')
        sd = ImageDraw.Draw(sheet)
        sd.text((52,28),title,font=io.font(32,True),fill='#e5e7df')
        views = [('FRONT',-90,0),('THREE QUARTER',-55,15),('BACK',90,0),('SIDE',0,0)]
        for j,(label,az,el) in enumerate(views):
            scale2 = min(23,810/a.shape[2],350/a.shape[0])
            im = io.render(a,(380,850),az=az,el=el,scale=scale2)
            sheet.paste(im,(10+j*400,125),im)
            sd.text((36+j*400,98),label,font=io.font(18,True),fill='#a1aab7')
        sd.text((52,1014),f'{report["voxels"]:,} solid voxels  /  +Z up  /  Y depth  /  previews rendered from exported VOX',font=io.font(18),fill='#a1aab7')
        sheet.save(pre/f'{name}_views.png')
    overview.save(pre/'steel_toolset.png')


def main():
    ROOT.mkdir(exist_ok=True)
    models=[]
    for name, builder in [('steel_sword',sword),('steel_pickaxe',pickaxe),('steel_axe',axe)]:
        a, origin = builder()
        path = ROOT/f'{name}.vox'
        io.export_vox(path,a)
        restored, report = io.validate(path,a)
        report['design_origin_xyz'] = origin
        report['grip_anchor_xyz'] = [origin[0],origin[1],origin[2]+(4 if name=='steel_sword' else 8)]
        assert report['voxels'] <= 350 and max(a.shape) <= 32
        models.append((name,restored,report))
    assert len({r['rgba_sha256'] for _,_,r in models}) == 1
    palette_files()
    previews(models)
    (ROOT/'validation.json').write_text(json.dumps({'identical_palettes':True,'models':[r for _,_,r in models]},indent=2)+'\n')
    (ROOT/'README.md').write_text('''# Blockbound beginner steel toolset

Three small, simple 3D voxel models based on the supplied sword, pickaxe and axe references. These replace the previous detailed models at the same filenames. Each model contains fewer than 350 occupied voxels, is at most 32 voxels tall and is only 3 voxels thick.

- **steel_sword.vox**: simple tapered blade, short crossguard, plain leather grip and small metal pommel.
- **steel_pickaxe.vox**: stepped double-ended steel head, plain socket and a 2 x 2 wooden shaft.
- **steel_axe.vox**: compact single cutting bit, shallow beard and a 2 x 2 wooden handle.

All files are MagicaVoxel VOX version 150 with one editable voxel volume per file. The models are upright: +Z toward the head/tip, X across the head, Y thickness. The axe cutting edge faces +X. Import scale is left to the game. The diagonal poses in the references are normalized to upright local coordinates.

## Shared palette

All three VOX files embed an identical complete 256-entry RGBA chunk. Slots 1-28 are named colors; slot 0 is empty. The 16 existing wood/linen colors remain in their original slots, with steel and leather appended. `shared_palette.json`, `.gpl` and `.png` are included. Each model uses the relevant subset. The earlier wooden sword files are untouched.

## Previews and validation

`previews/steel_toolset.png` shows the set. Each model also has a transparent preview and front, angled, rear and side views. All previews are rendered from the geometry decoded from the exported VOX files; directional light slightly shades the palette colors in previews.

`validation.json` records dimensions, voxel counts, palette hashes and grip anchors in voxel coordinates. Every file passes binary round-trip, chunk size, bounds, unique coordinate, palette index and six-neighbor connectivity checks. Each is one connected solid with no background, watermark, ground plane or stand.

To rebuild: install Python 3, NumPy and Pillow, then run `python source/build_toolset.py`. The source is self-contained within this folder.
''',encoding='utf-8')
    with zipfile.ZipFile(ROOT/'steel_toolset.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for p in sorted(ROOT.rglob('*')):
            if p.is_file() and p.suffix != '.zip' and '__pycache__' not in p.parts:
                archive.write(p,p.relative_to(ROOT))
    print(json.dumps([r for _,_,r in models],indent=2))


if __name__ == '__main__':
    main()
