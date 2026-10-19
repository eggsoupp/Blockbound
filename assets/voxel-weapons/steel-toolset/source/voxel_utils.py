"""MagicaVoxel binary IO, validation and orthographic geometry renderer."""
import struct
import hashlib
import math
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFont
RGB = None

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
    # No loose voxels: all pieces, including raised bindings, share a solid component.
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
