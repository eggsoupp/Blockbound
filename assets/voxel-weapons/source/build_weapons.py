"""Deterministic wooden sword sculpt, MagicaVoxel export, and geometry previews.

Run with Python 3, numpy and Pillow. All assets use the same indexed palette.
The sword is upright: +Z toward the tip, X across the guard, Y thickness.
"""
from pathlib import Path
from collections import deque
import hashlib
import json
import math
import struct
import zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PALETTE = [
    ('Charcoal outline', '#20201e'), ('Charcoal bevel', '#292720'),
    ('Wood deepest', '#633723'), ('Wood dark red', '#793e29'),
    ('Wood russet', '#88492e'), ('Wood shade', '#945332'),
    ('Wood brown', '#9f5d34'), ('Wood orange', '#aa683a'),
    ('Wood warm', '#b37440'), ('Wood highlight', '#bd8249'),
    ('Wood ochre', '#986434'), ('Wood muted', '#805330'),
    ('Wood side', '#70452b'), ('Wood light edge', '#ae7542'),
    ('Wood amber', '#a16b36'), ('Wood light grain', '#b47b45'),
]
RGB = np.array([tuple(bytes.fromhex(h[1:])) for _, h in PALETTE], dtype=np.uint8)
SHAPE = (25, 7, 62)


def sculpt():
    """Solid low-resolution sword with a charcoal rim and recessed diamond groove."""
    a = np.zeros(SHAPE, np.uint8)
    silhouette = np.zeros((SHAPE[0], SHAPE[2]), bool)
    part = np.zeros_like(silhouette, np.uint8)
    for ix in range(SHAPE[0]):
        x = ix - 12
        for z in range(SHAPE[2]):
            # Short, squared wooden grip with a clipped pommel.
            if z <= 19 and abs(x) <= (2 if z == 0 else 3):
                silhouette[ix, z] = True
                part[ix, z] = 1
            # Simple crossguard, whose ends sweep very slightly toward the blade.
            guard_z = 17 + max(0, (abs(x) - 5) // 3)
            if abs(x) <= 12 and abs(z - guard_z) <= (1 if abs(x) == 12 else 2):
                silhouette[ix, z] = True
                part[ix, z] = 2
            # Long, narrow blade with a clipped blunt tip, as in the new reference.
            if 19 <= z <= 61:
                width = 5 if z <= 58 else 5 - (z - 58)
                if abs(x) <= width:
                    silhouette[ix, z] = True
                    part[ix, z] = 3
    # A one-voxel charcoal perimeter reads like the reference's black pixel edging.
    padded = np.pad(silhouette, 1)
    interior = silhouette.copy()
    for dx, dz in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        interior &= padded[1+dx:1+dx+SHAPE[0], 1+dz:1+dz+SHAPE[2]]
    for ix, z in np.argwhere(silhouette):
        x = ix - 12
        rim = not interior[ix, z]
        kind = part[ix, z]
        depth = 1 if rim else (3 if kind == 2 else 2)
        # Dark diamond cells reproduce the diagonal pixel seam along the blade.
        groove = kind == 3 and 22 <= z <= 54 and abs(x - 1) + abs((z - 22) % 4 - 2) <= 1
        if groove:
            depth = 1
        for yy in range(3-depth, 4+depth):
            if rim or groove:
                color = 1
            elif kind == 3:
                color = 8 if x < 1 else 6 if x == 1 else 5
                if x >= 2 and (z // 4) % 2 == 0:
                    color = 7
                if z >= 56:
                    color = 8 if x <= 2 else 5
            elif kind == 2:
                color = 8 if z >= 18 else 6
                if x > 7:
                    color = 5
                if x < -7 and z >= 20:
                    color = 9
                if abs(x) <= 2 and z in (17, 18):
                    color = 5
            else:
                color = 8 if x < 1 else 5
                if z <= 2:
                    color = 5
                if 5 <= z <= 10 and x <= 0:
                    color = 7
            if abs(yy - 3) < depth and not rim and not groove:
                color = 13
            a[ix, yy, z] = color
    return a


def chunk(tag, body=b'', children=b''):
    return tag + struct.pack('<II', len(body), len(children)) + body + children


def export_vox(path, a):
    xyz = np.argwhere(a)
    records = np.column_stack((xyz, a[tuple(xyz.T)])).astype(np.uint8)
    rgba = b''.join(bytes(c) + b'\xff' for c in RGB)
    rgba += bytes((0, 0, 0, 255)) * (256 - len(RGB))
    data = chunk(b'SIZE', struct.pack('<3i', *a.shape))
    data += chunk(b'XYZI', struct.pack('<I', len(records)) + records.tobytes())
    data += chunk(b'RGBA', rgba)
    path.write_bytes(b'VOX ' + struct.pack('<I', 150) + chunk(b'MAIN', children=data))


def validate(path, original):
    raw = path.read_bytes()
    assert raw[:8] == b'VOX ' + struct.pack('<I', 150)
    assert raw[8:12] == b'MAIN'
    assert struct.unpack_from('<II', raw, 12) == (0, len(raw) - 20)
    pos = 20
    tags = []
    while pos < len(raw):
        tag = raw[pos:pos+4]
        n, child = struct.unpack_from('<II', raw, pos+4)
        assert child == 0
        body = raw[pos+12:pos+12+n]
        assert len(body) == n
        tags.append(tag)
        if tag == b'SIZE':
            dims = struct.unpack('<3i', body)
        elif tag == b'XYZI':
            count = struct.unpack_from('<I', body)[0]
            q = np.frombuffer(body[4:], np.uint8).reshape(-1, 4)
            assert count == len(q) == len(np.unique(q[:, :3], axis=0))
            assert (q[:, :3] < dims).all()
            assert (q[:, 3] >= 1).all() and (q[:, 3] <= len(RGB)).all()
            restored = np.zeros(dims, np.uint8)
            restored[tuple(q[:, :3].T)] = q[:, 3]
        elif tag == b'RGBA':
            assert len(body) == 1024
            assert body[:len(RGB)*4] == b''.join(bytes(c)+b'\xff' for c in RGB)
            palette_hash = hashlib.sha256(body).hexdigest()
        pos += 12 + n
    assert pos == len(raw)
    assert tags == [b'SIZE', b'XYZI', b'RGBA']
    assert np.array_equal(restored, original)
    # No loose voxels: the hilt, blade, perimeter and recessed groove are connected.
    remaining = set(map(tuple, np.argwhere(restored)))
    components = []
    while remaining:
        start = remaining.pop()
        queue = deque([start])
        size = 0
        while queue:
            p = queue.popleft()
            size += 1
            for axis in range(3):
                for sign in (-1, 1):
                    neighbor = list(p)
                    neighbor[axis] += sign
                    neighbor = tuple(neighbor)
                    if neighbor in remaining:
                        remaining.remove(neighbor)
                        queue.append(neighbor)
        components.append(size)
    assert len(components) == 1
    return restored, {'file': path.name, 'format': 'MagicaVoxel VOX 150',
        'dimensions_xyz': list(dims), 'voxels': int(count), 'connected_components': len(components),
        'roundtrip_identical': True, 'rgba_sha256': palette_hash,
        'used_palette_indices': [int(v) for v in np.unique(q[:, 3])]}


def render(a, size, az=-70, el=12, roll=0, scale=9):
    az, el, roll = map(math.radians, (az, el, roll))
    view = np.array([math.cos(az)*math.cos(el), math.sin(az)*math.cos(el), math.sin(el)])
    right = np.array([-math.sin(az), math.cos(az), 0])
    up = np.cross(view, right)
    center = np.array(a.shape) / 2
    faces = []
    pad = np.pad(a, 1)
    rotation = np.array([[math.cos(roll), math.sin(roll)], [-math.sin(roll), math.cos(roll)]])
    for axis in range(3):
        if abs(view[axis]) < 1e-6:
            continue
        sign = 1 if view[axis] > 0 else -1
        sl = [slice(1, -1)] * 3
        sl[axis] = slice(2, None) if sign > 0 else slice(None, -2)
        points = np.argwhere((a > 0) & (pad[tuple(sl)] == 0))
        others = [j for j in range(3) if j != axis]
        corners = np.zeros((4, 3))
        corners[:, axis] = 1 if sign > 0 else 0
        corners[:, others[0]] = [0, 1, 1, 0]
        corners[:, others[1]] = [0, 0, 1, 1]
        verts = points[:, None, :] + corners - center
        uv = np.stack((verts @ right, -verts @ up), axis=-1) @ rotation
        uv = uv * scale + np.array(size)/2
        depths = (points + corners.mean(0) - center) @ view
        cols = np.clip(RGB.astype(float) * [.76, 1.0, 1.08][axis], 0, 255).astype(np.uint8)
        for i, p in enumerate(points):
            faces.append((depths[i], uv[i], tuple(cols[a[tuple(p)]-1])+(255,)))
    out = Image.new('RGBA', size)
    draw = ImageDraw.Draw(out)
    for _, poly, color in sorted(faces, key=lambda f: f[0]):
        draw.polygon([tuple(v) for v in np.rint(poly).astype(int)], fill=color)
    return out


def font(size, bold=False):
    try:
        return ImageFont.truetype('C:/Windows/Fonts/' + ('segoeuib.ttf' if bold else 'segoeui.ttf'), size)
    except OSError:
        return ImageFont.load_default()


def previews(a):
    pre = ROOT / 'previews'
    pre.mkdir(exist_ok=True)
    # These are rendered from the exported voxel geometry, not concept art.
    hero = render(a, (800, 800), az=-76, el=8, roll=42, scale=11)
    hero.save(pre / 'wooden_sword_transparent.png')
    backdrop = Image.new('RGBA', hero.size, '#ece9e1')
    backdrop.alpha_composite(hero)
    backdrop.convert('RGB').save(pre / 'wooden_sword.png')
    sheet = Image.new('RGB', (1600, 1000), '#ece9e1')
    d = ImageDraw.Draw(sheet)
    d.text((54, 30), 'WOODEN SWORD', font=font(36, True), fill='#32291f')
    d.text((55, 83), 'Solid voxel sculpt  /  shared charcoal + warm wood palette', font=font(20), fill='#6a6256')
    views = [('REFERENCE POSE', -76, 8, 42, 9.3), ('FRONT', -90, 0, 0, 10),
             ('BACK / DEPTH', 65, 12, 0, 10)]
    for i, (name, az, el, roll, scale) in enumerate(views):
        im = render(a, (510, 690), az, el, roll, scale)
        sheet.paste(im, (25 + 520*i, 138), im)
        d.text((50 + 520*i, 124), name, font=font(17, True), fill='#6a6256')
    for i, (name, h) in enumerate(PALETTE):
        x = 55 + i*91
        d.rectangle((x, 864, x+77, 909), fill=h)
        d.text((x, 918), f'{i+1:02d}', font=font(15), fill='#6a6256')
    d.text((55, 959), '25 x 7 x 62 voxels  |  +Z tip  |  X crossguard  |  Y thickness', font=font(17), fill='#6a6256')
    sheet.save(pre / 'wooden_sword_views.png')


def main():
    ROOT.mkdir(exist_ok=True)
    a = sculpt()
    out = ROOT / 'wooden_sword.vox'
    export_vox(out, a)
    restored, report = validate(out, a)
    previews(restored)
    palette = {'name': 'Blockbound Weapons - Charcoal and Warm Wood',
               'indexing': 'VOX index 0 is empty; first RGBA entry maps to index 1. Keep indices stable for future models.',
               'colors': [{'index': i+1, 'name': n, 'hex': h} for i, (n, h) in enumerate(PALETTE)]}
    (ROOT / 'shared_palette.json').write_text(json.dumps(palette, indent=2)+'\n')
    gpl = ['GIMP Palette', 'Name: Blockbound Weapons - Charcoal and Warm Wood', 'Columns: 8', '#']
    for i, ((name, _), rgb) in enumerate(zip(PALETTE, RGB)):
        gpl.append(f'{rgb[0]:3} {rgb[1]:3} {rgb[2]:3}\t{i+1:02} {name}')
    (ROOT / 'shared_palette.gpl').write_text('\n'.join(gpl)+'\n')
    swatch = Image.new('RGB', (512, 64))
    d = ImageDraw.Draw(swatch)
    for i, (_, h) in enumerate(PALETTE):
        d.rectangle((i*32, 0, i*32+31, 63), fill=h)
    swatch.save(ROOT / 'shared_palette.png')
    (ROOT / 'validation.json').write_text(json.dumps(report, indent=2)+'\n')
    (ROOT / 'README.md').write_text('''# Wooden sword\n\nReplacement based on the latest pixel-art sword reference: a narrow orange-brown wooden blade, charcoal perimeter, dark recessed diamond seam, short squared grip, and simple wooden crossguard. Solid depth with beveled perimeter and the same detail on front and back. This replaces the previous pale blade and linen-bound design.\n\n- `wooden_sword.vox`: MagicaVoxel v150, one editable model, 25 x 7 x 62 grid.\n- `shared_palette.json`, `.gpl`, `.png`: the same 16-color charcoal/wood palette embedded in the model; keep indices stable for additional weapons. Index 0 is empty.\n- `previews/`: front, rear, angled views, and a transparent render from the exported geometry.\n- `source/build_weapons.py`: reproducible generation and validation; Python, NumPy, Pillow.\n- `validation.json`: binary round-trip, bounds, color-index, uniqueness, and connectivity checks.\n\nOrientation: +Z toward the tip, X across the guard, Y depth. The asset is upright; the diagonal pose appears only in previews. Grid grip center approximately (12, 3, 8); ground/pommel begins at z=0. Choose world scale in your importer.\n\nOpen the VOX file directly in MagicaVoxel or another compatible editor. All voxels are opaque; there is no base, background, or display stand in the model.\n''')
    with zipfile.ZipFile(ROOT / 'wooden_sword_pack.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        for p in sorted(ROOT.rglob('*')):
            if p.is_file() and p.suffix != '.zip' and '__pycache__' not in p.parts:
                z.write(p, p.relative_to(ROOT))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
