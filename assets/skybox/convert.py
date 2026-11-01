"""Convert purchased Unity cubemap strips into Roblox Sky face images."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent.parent / 'build/skybox/python'))
import OpenEXR

# Unity horizontal cubemap order: +X, -X, +Y, -Y, +Z, -Z.
FACES = ['Rt', 'Lf', 'Up', 'Dn', 'Bk', 'Ft']
source = ROOT / 'original/Voxel_skybox_full/Textures'
previews = []
for path in sorted(source.glob('*.exr')):
    if path.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n':
        # Several purchased files are PNGs with an incorrect EXR extension.
        rgb = np.asarray(Image.open(path).convert('RGB'))
    else:
        pixels = OpenEXR.File(str(path)).channels()['RGB'].pixels.astype(np.float32)
        # One stop of exposure reduction preserves bright authored cloud detail.
        linear = np.clip(pixels * 0.5, 0, 1)
        srgb = np.where(linear <= 0.0031308, linear*12.92, 1.055*linear**(1/2.4)-0.055)
        rgb = (np.clip(srgb, 0, 1)*255 + 0.5).astype(np.uint8)
    h, w, _ = rgb.shape
    assert w == 6*h, (path, rgb.shape)
    output = ROOT / 'converted' / path.stem
    output.mkdir(parents=True, exist_ok=True)
    for i, face in enumerate(FACES):
        Image.fromarray(rgb[:,i*h:(i+1)*h]).save(output / f'{face}.png')
    strip = Image.fromarray(rgb).resize((1200,200))
    tile = Image.new('RGB', (1200,225), '#202020')
    tile.paste(strip,(0,25))
    ImageDraw.Draw(tile).text((8,6),path.stem,fill='white')
    previews.append(tile)
    print(path.stem, flush=True)
sheet=Image.new('RGB',(1200,225*len(previews)))
for i, preview in enumerate(previews): sheet.paste(preview,(0,225*i))
sheet.save(ROOT / 'all-skies-preview.jpg')
