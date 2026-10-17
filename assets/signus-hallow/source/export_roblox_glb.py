"""Signus / Hallowed Eclipse -> Roblox GLB.

Reads ../signus_hallowed_eclipse.vox through build_signus.read_vox, so the voxels
meshed here are exactly the ones the previews were rendered from, and writes:

  ../roblox/signus_hallowed_eclipse.glb   Core, CoreLower, Hood, LeftSleeve, RightSleeve
  ../roblox/signus_palette.png            the palette texture (also embedded in the GLB)
  ../roblox/export_report.json            triangle counts, bounds, pivots, checks
  ../roblox/previews/*.png                renders of the GLB beside the originals

FOUR RIGID COMPONENTS, FIVE MESHES. Roblox refuses a mesh of 20,000 triangles or
more, and the Core's exact voxel surface needs about 29,000 (no exact merge found
here got it under 24,000). So the Core is stored as two meshes split at source
z = 68: Core (above) and CoreLower (below), both with the Core's pivot. The rig
welds CoreLower to Core, so it is still one animated component. Faces between the
two halves are inside the solid and are not exported.

Geometry: every exposed face, greedy-merged per plane and per palette colour into
rectangles. Flat normals, no shared vertices across faces, no bevel or smoothing.
Hood and sleeves are each a closed volume, so faces where they touch the Core are
kept: they show when the hood or a sleeve turns.

Colour: one 512x16 opaque palette texture, a 16 px cell per palette entry. Every
quad samples only the middle 4 px of its cell, so bilinear filtering, mipmaps and
block compression in Roblox cannot pull in a neighbouring colour.

Axes: Roblox (X, Y, Z) = Source (-X, Z, Y) * 0.125 studs, relative to the Core
pivot (0, 0, 80). Up +Z -> +Y, forward -Y -> -Z. It is a rotation, not a
mirror: the model looks exactly as it does in MagicaVoxel and the previews. A
plain Y/Z swap would also put +Y up and the front on -Z, but it is a reflection
and flips every asymmetric detail to the other side.

Sleeve names follow Roblox, where a model's own left is -X. The source names its
sleeves from the viewer's side, so "04 Right Crescent Sleeve" lands at -X and
becomes LeftSleeve, and "03 Left Crescent Sleeve" becomes RightSleeve.

Each node's translation is its anatomical pivot; its mesh is stored relative to
that pivot.

Requires Python 3, NumPy and Pillow, like build_signus.py.
"""
from pathlib import Path
import hashlib, io, json, math, struct, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = ROOT / 'roblox'
PRE = OUT / 'previews'
sys.path.insert(0, str(HERE))
import build_signus as bs  # noqa: E402

GLB_PATH = OUT / 'signus_hallowed_eclipse.glb'
STUDS = 0.125
MAX_TRIANGLES = 20000
EXPECTED_SIZE = (12.5, 18.25, 6.25)
CORE = '01 Core and Thorn Mantle'
CORE_SPLIT_Z = 68  # source z (a voxel boundary) where Core and CoreLower meet
MESHES = [  # Roblox name, source object, which of its voxels ('upper'/'lower' of the split)
    ('Core', CORE, 'upper'),
    ('CoreLower', CORE, 'lower'),
    ('Hood', '02 Hood and Visage', None),
    ('LeftSleeve', '04 Right Crescent Sleeve', None),  # at -X: the creature's own left
    ('RightSleeve', '03 Left Crescent Sleeve', None),
]
# The pivots the rig expects, relative to the Core pivot, in studs.
EXPECTED_PIVOTS = {
    'Core': (0, 0, 0),
    'CoreLower': (0, 0, 0),
    'Hood': (0, 3.5, -0.375),
    'LeftSleeve': (-3.375, 1.75, -0.25),
    'RightSleeve': (3.375, 1.75, -0.25),
}
ORIGIN = np.array([60, 48, 0])        # grid index of source (0, 0, 0)
ROOT_PIVOT = np.array(bs.ROOT_PIVOT)  # source (0, 0, 80)
EYE_COLORS = (17, 18, 19)             # unshaded in the previews

# Palette texture: one row of 32 cells, so a V flip in any importer is harmless.
CELL, SLOTS = 16, 32
TEX_W, TEX_H = CELL * SLOTS, CELL
UV_HALF = 2  # pixels either side of a cell's centre that a quad may sample


def to_roblox(v):
    """Source-axis vector(s) -> Roblox axes. A proper rotation, and its own inverse."""
    v = np.asarray(v)
    return v[..., [0, 2, 1]] * np.array([-1, 1, 1])


def voxels_for(a, half):
    """The voxels of `a` that one mesh owns."""
    if half is None:
        return a
    z = np.arange(a.shape[2])[None, None, :]
    keep = z >= CORE_SPLIT_Z if half == 'upper' else z < CORE_SPLIT_Z
    return np.where(keep, a, 0)


def palette_png():
    img = np.zeros((TEX_H, TEX_W, 3), np.uint8)
    for i, rgb in enumerate(bs.RGB):
        img[:, i * CELL:(i + 1) * CELL] = rgb
    path = OUT / 'signus_palette.png'
    Image.fromarray(img, 'RGB').save(path, optimize=True)
    return path.read_bytes()


def cell_uv(color):
    cx, cy = (color - 1) * CELL + CELL / 2, CELL / 2
    return [((cx + du * UV_HALF) / TEX_W, (cy + dv * UV_HALF) / TEX_H)
            for du, dv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]


def color_of_uv(u):
    return np.floor(np.asarray(u) * TEX_W / CELL).astype(int) + 1


# ---------------------------------------------------------------------------
# Greedy meshing
# ---------------------------------------------------------------------------

def greedy(mask):
    """Rectangles (row, col, height, width, colour) exactly tiling a 2D colour mask."""
    m = mask.tolist()
    rows, cols = len(m), len(m[0])
    quads = []
    for y in range(rows):
        row = m[y]
        x = 0
        while x < cols:
            c = row[x]
            if not c:
                x += 1
                continue
            w = 1
            while x + w < cols and row[x + w] == c:
                w += 1
            seg = row[x:x + w]
            h = 1
            while y + h < rows and m[y + h][x:x + w] == seg:
                h += 1
            for yy in range(y, y + h):
                m[yy][x:x + w] = [0] * w
            quads.append((y, x, h, w, c))
            x += w
    return quads


def best_greedy(mask):
    """Greedy in both scan orders; keep whichever needs fewer rectangles."""
    a = greedy(mask)
    b = [(x, y, w, h, c) for y, x, h, w, c in greedy(np.ascontiguousarray(mask.T))]
    return a if len(a) <= len(b) else b


def exposed(a, axis, d, owned=None):
    """Colour of every face of `a` pointing along +-axis into empty space.

    `owned` limits the result to faces of those voxels; exposure is still judged
    against the whole of `a`, so a split leaves no faces between its halves.
    """
    solid = a > 0
    pad = np.pad(solid, 1)
    sl = [slice(1, -1)] * 3
    sl[axis] = slice(2, None) if d > 0 else slice(None, -2)
    face = solid & ~pad[tuple(sl)]
    if owned is not None:
        face &= owned > 0
    return np.where(face, a, 0)


def mesh_part(a, owned):
    """Quads in grid index space: (axis, dir, plane, u0, v0, du, dv, colour)."""
    quads = []
    occupied = np.argwhere(owned)
    lo, hi = occupied.min(0), occupied.max(0) + 1
    for axis in range(3):
        u_ax, v_ax = [i for i in range(3) if i != axis]
        for d in (1, -1):
            faces = exposed(a, axis, d, owned)
            for c in range(lo[axis], hi[axis]):
                mask = np.take(faces, c, axis=axis)[lo[u_ax]:hi[u_ax], lo[v_ax]:hi[v_ax]]
                if not mask.any():
                    continue
                plane = c + (1 if d > 0 else 0)
                for u, v, du, dv, col in best_greedy(mask):
                    quads.append((axis, d, plane, lo[u_ax] + u, lo[v_ax] + v, du, dv, col))
    return quads


def build_mesh(quads, pivot):
    """Vertex arrays in Roblox axes, studs, relative to `pivot` (source coords)."""
    n = len(quads)
    pos = np.zeros((n, 4, 3), np.float64)
    nrm = np.zeros((n, 4, 3), np.float32)
    uv = np.zeros((n, 4, 2), np.float32)
    for q, (axis, d, plane, u0, v0, du, dv, col) in enumerate(quads):
        u_ax, v_ax = [i for i in range(3) if i != axis]
        corners = np.zeros((4, 3))
        corners[:, axis] = plane
        corners[:, u_ax] = [u0, u0 + du, u0 + du, u0]
        corners[:, v_ax] = [v0, v0, v0 + dv, v0 + dv]
        normal = np.zeros(3)
        normal[axis] = d
        # Counter-clockwise seen from outside. A rotation keeps that, so no flip after.
        if np.dot(np.cross(corners[1] - corners[0], corners[2] - corners[0]), normal) < 0:
            corners = corners[::-1]
        pos[q] = to_roblox(corners - ORIGIN - pivot) * STUDS
        nrm[q] = to_roblox(normal)
        uv[q] = cell_uv(col)
    idx = (np.arange(n)[:, None] * 4 + np.array([0, 1, 2, 0, 2, 3])).ravel()
    return pos.reshape(-1, 3).astype(np.float32), nrm.reshape(-1, 3), uv.reshape(-1, 2), idx


# ---------------------------------------------------------------------------
# GLB
# ---------------------------------------------------------------------------

FLOAT, U16, U32 = 5126, 5123, 5125
ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963


def write_glb(path, meshes, png):
    blob = bytearray()
    views, accessors = [], []

    def view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)})
        if target:
            views[-1]['target'] = target
        blob.extend(data)
        return len(views) - 1

    def accessor(arr, kind, ctype, target, bounds=False):
        acc = {'bufferView': view(arr.tobytes(), target), 'componentType': ctype,
               'count': int(arr.shape[0]), 'type': kind}
        if bounds:
            acc['min'] = arr.min(0).tolist()
            acc['max'] = arr.max(0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    gltf_meshes, nodes = [], []
    for name, translation, (pos, nrm, uv, idx) in meshes:
        big = pos.shape[0] > 65535
        prim = {
            'attributes': {
                'POSITION': accessor(pos, 'VEC3', FLOAT, ARRAY_BUFFER, True),
                'NORMAL': accessor(nrm, 'VEC3', FLOAT, ARRAY_BUFFER),
                'TEXCOORD_0': accessor(uv, 'VEC2', FLOAT, ARRAY_BUFFER),
            },
            'indices': accessor(idx.astype(np.uint32 if big else np.uint16), 'SCALAR',
                                U32 if big else U16, ELEMENT_ARRAY_BUFFER),
            'material': 0,
            'mode': 4,
        }
        gltf_meshes.append({'name': name, 'primitives': [prim]})
        nodes.append({'name': name, 'mesh': len(gltf_meshes) - 1,
                      'translation': [float(t) for t in translation]})

    image_view = view(png)
    doc = {
        'asset': {'version': '2.0', 'generator': 'BlockBound export_roblox_glb.py'},
        'scene': 0,
        'scenes': [{'name': 'Signus', 'nodes': list(range(len(nodes)))}],
        'nodes': nodes,
        'meshes': gltf_meshes,
        'materials': [{
            'name': 'SignusPalette',
            'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                                     'baseColorFactor': [1, 1, 1, 1],
                                     'metallicFactor': 0.0, 'roughnessFactor': 1.0},
            'alphaMode': 'OPAQUE',
            'doubleSided': False,
        }],
        'textures': [{'sampler': 0, 'source': 0}],
        'samplers': [{'magFilter': 9728, 'minFilter': 9728, 'wrapS': 33071, 'wrapT': 33071}],
        'images': [{'name': 'SignusPalette', 'bufferView': image_view, 'mimeType': 'image/png'}],
        'accessors': accessors,
        'bufferViews': views,
        'buffers': [{'byteLength': len(blob)}],
    }
    js = json.dumps(doc, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    blob.extend(b'\0' * (-len(blob) % 4))
    total = 12 + 8 + len(js) + 8 + len(blob)
    path.write_bytes(struct.pack('<4sII', b'glTF', 2, total)
                     + struct.pack('<I4s', len(js), b'JSON') + js
                     + struct.pack('<I4s', len(blob), b'BIN\0') + bytes(blob))


def read_glb(path):
    raw = path.read_bytes()
    magic, version, total = struct.unpack_from('<4sII', raw)
    assert magic == b'glTF' and version == 2 and total == len(raw)
    jlen, jtype = struct.unpack_from('<I4s', raw, 12)
    assert jtype == b'JSON'
    doc = json.loads(raw[20:20 + jlen])
    blen, btype = struct.unpack_from('<I4s', raw, 20 + jlen)
    assert btype == b'BIN\0'
    blob = raw[28 + jlen:28 + jlen + blen]
    dtypes = {FLOAT: np.float32, U16: np.uint16, U32: np.uint32}
    widths = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}

    def data(i):
        acc = doc['accessors'][i]
        bv = doc['bufferViews'][acc['bufferView']]
        arr = np.frombuffer(blob, dtypes[acc['componentType']], acc['count'] * widths[acc['type']],
                            bv['byteOffset'])
        return arr.reshape(acc['count'], -1) if widths[acc['type']] > 1 else arr

    bv = doc['bufferViews'][doc['images'][0]['bufferView']]
    png = blob[bv['byteOffset']:bv['byteOffset'] + bv['byteLength']]
    meshes = {}
    for node in doc['nodes']:
        prim = doc['meshes'][node['mesh']]['primitives'][0]
        meshes[node['name']] = {
            'translation': np.array(node.get('translation', [0, 0, 0])),
            'pos': data(prim['attributes']['POSITION']).astype(np.float64),
            'nrm': data(prim['attributes']['NORMAL']).astype(np.float64),
            'uv': data(prim['attributes']['TEXCOORD_0']).astype(np.float64),
            'idx': data(prim['indices']).astype(np.int64),
        }
    return doc, meshes, png


# ---------------------------------------------------------------------------
# Verification against the voxels
# ---------------------------------------------------------------------------

def verify(doc, glb, png, decoded):
    """Every check the export report lists; raises on the first failure."""
    checks = {}
    tex = np.array(Image.open(io.BytesIO(png)))
    assert tex.ndim == 3 and tex.shape[2] == 3, 'palette texture must be opaque RGB'
    assert doc['materials'][0]['alphaMode'] == 'OPAQUE' and len(doc['materials']) == 1
    checks['opaque_rgb_palette_texture'] = True
    assert [n['name'] for n in doc['nodes']] == [m for m, _, _ in MESHES]
    assert all(m['name'] == n['name'] for m, n in zip(doc['meshes'], doc['nodes']))
    assert all(len(m['primitives']) == 1 for m in doc['meshes'])
    checks['meshes_named_and_one_primitive_each'] = True

    volume = {src: 0.0 for _, src, _ in MESHES}
    world_lo, world_hi = np.full(3, np.inf), np.full(3, -np.inf)
    for name, src, half in MESHES:
        p = glb[name]
        tri = p['idx'].reshape(-1, 3)
        assert len(tri) < MAX_TRIANGLES, (name, len(tri))
        v = p['pos'][tri]
        n = p['nrm'][tri]
        assert np.allclose(n[:, 0], n[:, 1]) and np.allclose(n[:, 0], n[:, 2])
        geo = np.cross(v[:, 1] - v[:, 0], v[:, 2] - v[:, 0])
        assert (np.abs(geo).sum(1) > 0).all(), 'degenerate triangle'
        assert (np.einsum('ij,ij->i', geo, n[:, 0]) > 0).all(), (name, 'winding disagrees with normal')
        volume[src] += np.einsum('ij,ij->i', v[:, 0], np.cross(v[:, 1], v[:, 2])).sum() / 6

        # Rebuild every unit face (and its colour) the quads cover, back in source
        # grid space, and require exactly the faces this mesh's voxels expose.
        pivot = bs.PIVOTS[src]
        quads = p['idx'].reshape(-1, 6)[:, [0, 1, 2, 5]]
        grid = to_roblox(p['pos'][quads] / STUDS) + pivot + ORIGIN  # the conversion is its own inverse
        corners = np.rint(grid).astype(int)
        assert np.allclose(grid, corners), 'vertex off the voxel lattice'
        normals = to_roblox(p['nrm'][quads[:, 0]]).round().astype(int)
        uvs = p['uv'][quads]
        cols = color_of_uv(uvs[:, :, 0].mean(1))
        assert (color_of_uv(uvs[:, :, 0]) == cols[:, None]).all(), 'quad straddles two palette cells'
        px = np.floor(uvs * [TEX_W, TEX_H]).astype(int)
        assert (tex[px[..., 1], px[..., 0]] == bs.RGB[cols - 1][:, None]).all(), 'wrong palette texel'
        got = {}
        for c4, nn, col in zip(corners, normals, cols):
            axis = int(np.flatnonzero(nn)[0])
            d = int(nn[axis])
            lo, hi = c4.min(0), c4.max(0)
            assert lo[axis] == hi[axis], 'quad not axis aligned'
            layer = lo[axis] - 1 if d > 0 else lo[axis]
            rng = [range(lo[i], hi[i]) if i != axis else [layer] for i in range(3)]
            for i in rng[0]:
                for j in rng[1]:
                    for k in rng[2]:
                        key = (axis, d, i, j, k)
                        assert key not in got, (name, 'overlapping quads', key)
                        got[key] = int(col)
        a = decoded[src]
        owned = voxels_for(a, half)
        want = {}
        for axis in range(3):
            for d in (1, -1):
                f = exposed(a, axis, d, owned)
                for (i, j, k) in np.argwhere(f):
                    want[(axis, d, i, j, k)] = int(f[i, j, k])
        assert got == want, (name, 'surface or colours differ from the voxels', len(got), len(want))
        world = p['pos'] + p['translation']
        world_lo = np.minimum(world_lo, world.min(0))
        world_hi = np.maximum(world_hi, world.max(0))
        assert np.allclose(p['translation'], EXPECTED_PIVOTS[name]), (name, p['translation'])
    # Divergence theorem: outward-facing, closed and gap free gives the exact voxel
    # volume. Core and CoreLower are only closed together, so this is per object.
    for src, vol in volume.items():
        expect = np.count_nonzero(decoded[src]) * STUDS ** 3
        assert math.isclose(vol, expect, rel_tol=1e-9), (src, vol, expect)
    size = world_hi - world_lo
    assert np.allclose(size, EXPECTED_SIZE), size
    checks.update(triangles_below_20000_per_mesh=True, normals_match_winding=True,
                  closed_outward_volume_matches_voxels=True,
                  surface_and_colours_match_voxels_exactly=True,
                  pivots_match_spec=True, dimensions_match_spec=True)

    # Front is -Z: the eyes face -Z, the chest jewel is on the -Z side and the
    # dorsal keel colour sits mostly on +Z.
    hood = glb['Hood']
    eye_z = hood['nrm'][np.isin(color_of_uv(hood['uv'][:, 0]), [16, 18])][:, 2]
    assert (eye_z < 0).sum() > 4 * (eye_z > 0).sum(), 'eyes do not face -Z'
    core = glb['Core']
    jewel = np.isin(color_of_uv(core['uv'][:, 0]), [20, 21, 22, 23, 24])
    assert (core['pos'] + core['translation'])[jewel][:, 2].max() < 0, 'chest jewel is not on the front'
    checks['front_is_negative_z'] = True
    return checks, world_lo, world_hi


# ---------------------------------------------------------------------------
# Renders
# ---------------------------------------------------------------------------

BG = (27, 25, 39)


def raster(tris, colors, size):
    """Z-buffered orthographic fill. tris: (n, 3, 3) screen x, y, depth (bigger = nearer)."""
    w, h = size
    img = np.empty((h, w, 3), np.uint8)
    img[:] = BG
    zbuf = np.full((h, w), -np.inf)
    for t, col in zip(tris, colors):
        x0, y0 = np.floor(t[:, :2].min(0)).astype(int)
        x1, y1 = np.ceil(t[:, :2].max(0)).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, w - 1), min(y1, h - 1)
        if x1 < x0 or y1 < y0:
            continue
        px, py = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(y0, y1 + 1) + .5)
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = t
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
        l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
        l3 = 1 - l1 - l2
        inside = (l1 >= -1e-9) & (l2 >= -1e-9) & (l3 >= -1e-9)
        z = l1 * az + l2 * bz + l3 * cz
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        win = inside & (z > sub)
        sub[win] = z[win]
        img[y0:y1 + 1, x0:x1 + 1][win] = col
    return img


def camera(view, up_axis):
    """Right-handed orthographic camera: `view` points from the model to the eye."""
    view = view / np.linalg.norm(view)
    look = -view
    right = np.cross(look, up_axis)
    right /= np.linalg.norm(right)
    return view, right, np.cross(right, look)


def view_direction(az, el):
    az, el = math.radians(az), math.radians(el)
    return np.array([math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)])


def shade(color, source_axis):
    """build_signus.render's inspection light, so the renders are comparable."""
    if color in EYE_COLORS:
        return tuple(int(c) for c in bs.RGB[color - 1])
    s = [.82, .95, 1.13][source_axis]
    return tuple(np.clip(bs.RGB[color - 1].astype(float) * s, 0, 255).astype(np.uint8).tolist())


def project(points, center, view, right, up, scale, size):
    p = points - center
    return np.stack([p @ right * scale + size[0] / 2, -(p @ up) * scale + size[1] / 2, p @ view], -1)


def render_glb(glb, az, el, size, scale):
    """The GLB as Roblox shows it: right-handed, +Y up, the preview's camera swapped too."""
    view, right, up = camera(to_roblox(view_direction(az, el)), np.array([0., 1, 0]))
    allpos = np.concatenate([(p['pos'] + p['translation']) / STUDS for p in glb.values()])
    center = (allpos.min(0) + allpos.max(0)) / 2
    tris, cols = [], []
    for p in glb.values():
        pos = (p['pos'] + p['translation']) / STUDS
        tri = p['idx'].reshape(-1, 3)
        normal = p['nrm'][tri[:, 0]]
        facing = normal @ view > 1e-6
        tri = tri[facing]
        axis = np.abs(to_roblox(normal[facing])).argmax(1)  # back to the source axis for shading
        tris.append(project(pos[tri], center, view, right, up, scale, size))
        cols += [shade(c, a) for c, a in zip(color_of_uv(p['uv'][tri[:, 0], 0]), axis)]
    return raster(np.concatenate(tris), cols, size)


def render_voxels(a, az, el, size, scale):
    """The decoded .vox in its own right-handed Z-up space, unit faces, same raster."""
    view, right, up = camera(view_direction(az, el), np.array([0., 0, 1]))
    xyz = np.argwhere(a)
    center = (xyz.min(0) + xyz.max(0) + 1) / 2
    tris, cols = [], []
    for axis in range(3):
        for d in (1, -1):
            if np.eye(3)[axis] @ view * d <= 1e-6:
                continue
            f = exposed(a, axis, d)
            cells = np.argwhere(f)
            u_ax, v_ax = [i for i in range(3) if i != axis]
            corners = np.zeros((4, 3))
            corners[:, axis] = 1 if d > 0 else 0
            corners[:, u_ax] = [0, 1, 1, 0]
            corners[:, v_ax] = [0, 0, 1, 1]
            quad = cells[:, None, :] + corners
            for tri_ix in ([0, 1, 2], [0, 2, 3]):
                tris.append(project(quad[:, tri_ix].astype(float), center, view, right, up, scale, size))
                cols += [shade(int(f[tuple(c)]), axis) for c in cells]
    return raster(np.concatenate(tris), cols, size)


def font(n, bold=False):
    try:
        return bs.font(n, bold)
    except OSError:
        return ImageFont.load_default()


VIEWS = [(-90, 0, 'FRONT'), (-55, 12, 'THREE QUARTER'), (0, 0, 'SIDE'), (70, 15, 'REAR')]


def previews(glb, decoded):
    """GLB renders beside the existing previews, plus a pixel comparison with the voxels."""
    PRE.mkdir(parents=True, exist_ok=True)
    merged = bs.merge(decoded)
    original = Image.open(ROOT / 'previews' / 'signus_multiview.png').convert('RGB')
    size, scale = (440, 800), 4.5
    sheet = Image.new('RGB', (1800, 2010), BG)
    d = ImageDraw.Draw(sheet)
    d.text((38, 25), 'SIGNUS / ROBLOX GLB CHECK', font=font(30, True), fill=(238, 224, 241))
    d.text((40, 70), 'TOP: EXISTING PREVIEW (VOX)     /     BOTTOM: EXPORTED GLB AS ROBLOX SHOWS IT, '
                     '+Y UP, FRONT -Z', font=font(16), fill=(175, 158, 190))
    comparison = {}
    for i, (az, el, label) in enumerate(VIEWS):
        glb_img = render_glb(glb, az, el, size, scale)
        vox_img = render_voxels(merged, az, el, size, scale)
        Image.fromarray(glb_img).save(PRE / f'glb_{label.lower().replace(" ", "_")}.png')
        comparison[label] = {
            'pixels_differing_from_vox_render_percent':
                round(float((glb_img != vox_img).any(2).mean() * 100), 3),
            'pixels_differing_from_mirrored_vox_render_percent':
                round(float((glb_img != vox_img[:, ::-1]).any(2).mean() * 100), 3),
        }
        sheet.paste(original.crop((20 + i * 445, 125, 20 + i * 445 + 440, 925)), (20 + i * 445, 125))
        sheet.paste(Image.fromarray(glb_img), (20 + i * 445, 1110))
        d.text((40 + i * 445, 942), label + '  (VOX PREVIEW)', font=font(18, True), fill=(208, 178, 216))
        d.text((40 + i * 445, 1927), label + '  (GLB IN ROBLOX)', font=font(18, True), fill=(208, 178, 216))
    sheet.save(PRE / 'glb_vs_vox_multiview.png')
    return comparison


# ---------------------------------------------------------------------------

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    vox = ROOT / 'signus_hallowed_eclipse.vox'
    validation = json.loads((ROOT / 'validation.json').read_text())
    digest = hashlib.sha256(vox.read_bytes()).hexdigest()
    assert digest == validation['sha256'], 'the .vox no longer matches validation.json'
    decoded = bs.read_vox(vox)

    png = palette_png()
    meshes, report = [], {}
    for name, src, half in MESHES:
        a = decoded[src]
        owned = voxels_for(a, half)
        pivot = bs.PIVOTS[src]
        quads = mesh_part(a, owned)
        pos, nrm, uv, idx = build_mesh(quads, pivot)
        translation = to_roblox(pivot - ROOT_PIVOT) * STUDS
        meshes.append((name, translation, (pos, nrm, uv, idx)))
        lo, hi = pos.min(0) + translation, pos.max(0) + translation
        report[name] = {
            'source_object': src,
            'source_voxels': 'all' if half is None else
                             f'z {">=" if half == "upper" else "<"} {CORE_SPLIT_Z}',
            'triangles': int(len(idx) // 3),
            'vertices': int(len(pos)),
            'quads': len(quads),
            'unit_faces_merged': int(sum(q[5] * q[6] for q in quads)),
            'voxels': int(np.count_nonzero(owned)),
            'colours': sorted({int(q[-1]) for q in quads}),
            'pivot_source': [int(v) for v in pivot],
            'pivot_studs_from_core': [float(v) for v in translation],
            'bounds_min_studs_from_core': [float(v) for v in lo],
            'bounds_max_studs_from_core': [float(v) for v in hi],
            'size_studs': [float(v) for v in hi - lo],
            # Roblox centres a MeshPart on its bounds; the rig finds pivots from this.
            'bounds_center_studs_from_core': [float(v) for v in (lo + hi) / 2],
        }
    write_glb(GLB_PATH, meshes, png)

    doc, glb, png_back = read_glb(GLB_PATH)
    checks, lo, hi = verify(doc, glb, png_back, decoded)
    comparison = previews(glb, decoded)

    out = {
        'glb': GLB_PATH.name,
        'bytes': GLB_PATH.stat().st_size,
        'sha256': hashlib.sha256(GLB_PATH.read_bytes()).hexdigest(),
        'source_vox_sha256': digest,
        'axes': 'Roblox (X, Y, Z) = Source (-X, Z, Y) * 0.125; +Y up, front -Z; origin = Core pivot',
        'handedness_note': 'A rotation, not a mirror: the GLB matches the MagicaVoxel previews. '
                           'Sleeves are named for the creature\'s own side as Roblox does (-X is '
                           'left), so source "04 Right Crescent Sleeve" is LeftSleeve.',
        'core_split_note': f'The Core needs over 20,000 triangles as one exact mesh, so it is '
                           f'stored as Core (source z >= {CORE_SPLIT_Z}) and CoreLower (z < '
                           f'{CORE_SPLIT_Z}), welded together by the rig.',
        'studs_per_voxel': STUDS,
        'size_studs': [float(v) for v in hi - lo],
        'bounds_min_studs_from_core': [float(v) for v in lo],
        'bounds_max_studs_from_core': [float(v) for v in hi],
        'triangle_limit_per_mesh': MAX_TRIANGLES,
        'total_triangles': sum(p['triangles'] for p in report.values()),
        'palette_texture': {'file': 'signus_palette.png', 'size': [TEX_W, TEX_H], 'cell_px': CELL,
                            'sampled_px_each_side_of_centre': UV_HALF, 'mode': 'RGB, no alpha',
                            'filter': 'NEAREST'},
        'meshes': report,
        'checks': checks,
        'render_comparison': comparison,
    }
    (OUT / 'export_report.json').write_text(json.dumps(out, indent=2) + '\n')
    print(json.dumps(out, indent=2), flush=True)


if __name__ == '__main__':
    main()
