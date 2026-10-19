"""Low-resolution livingwood sword. Python 3 + NumPy + Pillow."""
from pathlib import Path
import json
import math
import numpy as np
from PIL import Image, ImageDraw
import voxel_utils as vu

ROOT = Path(__file__).resolve().parents[1]
COLORS = [
    ('Heartwood shadow', '#291f19'), ('Bark dark', '#453326'),
    ('Bark brown', '#604a35'), ('Wood muted', '#79644a'),
    ('Wood light', '#988363'), ('Fresh grain', '#b09a71'),
    ('Grain highlight', '#c5ad7e'), ('Hollow', '#14180d'),
    ('Leaf shadow', '#182e18'), ('Leaf dark', '#294522'),
    ('Leaf green', '#405d2a'), ('Leaf moss', '#607a36'),
    ('Leaf light', '#819548'), ('Vine', '#334c24'),
    ('Eye gold', '#d7dd20'), ('Eye core', '#f5ff55'),
]
vu.RGB = np.array([tuple(bytes.fromhex(h[1:])) for _, h in COLORS], np.uint8)
A = np.zeros((35, 17, 88), np.uint8)
CX, CY = 17, 8

def put(x, y, z, c):
    x, y, z = round(x)+CX, round(y)+CY, round(z)
    if 0 <= x < A.shape[0] and 0 <= y < A.shape[1] and 0 <= z < A.shape[2]:
        A[x,y,z] = c

def ellipsoid(x, y, z, rx, ry, rz, leaf=False):
    for xx in range(math.floor(x-rx), math.ceil(x+rx)+1):
        for yy in range(math.floor(y-ry), math.ceil(y+ry)+1):
            for zz in range(math.floor(z-rz), math.ceil(z+rz)+1):
                d = ((xx-x)/rx)**2+((yy-y)/ry)**2+((zz-z)/rz)**2
                if d <= 1:
                    if leaf:
                        # Broad patches read as a few large leaves, not speckled noise.
                        light = .42*(zz-z)/rz - .32*(yy-y)/ry - .22*(xx-x)/rx
                        c = 10 + int(light > -.23) + int(light > .08) + int(light > .40)
                        if abs(zz-z+.48*(xx-x)) < .55 and yy < y-ry*.55:
                            c = max(9,c-2)
                    else:
                        c = 2 if yy > y else 3 if xx > x else 5
                    put(xx,yy,zz,c)

def branch(points, radius=1.5, color=None):
    for p,q in zip(points,points[1:]):
        steps = int(np.linalg.norm(np.array(q)-p)*4)+1
        for t in np.linspace(0,1,steps):
            x,y,z = np.array(p)*(1-t)+np.array(q)*t
            if color:
                # Dense sampling + a small radius creates face-connected thin vines.
                for dx,dy,dz in [(0,0,0),(.35,0,0),(-.35,0,0),(0,0,.35),(0,0,-.35)]:
                    put(x+dx,y+dy,z+dz,color)
            else:
                ellipsoid(x,y,z,radius,radius,radius)

def build():
    # Crooked branch grip and hooked root pommel.
    branch([(-5,0,2),(-8,0,2),(-9,0,5),(-8,0,7),(-2,0,8),
            (0,0,12),(-1,0,17),(2,0,22),(1,0,30)],1.65)
    branch([(-7,-1,5),(-3,-1,6),(1,-1,11),(0,-1,16),(3,-1,22)],.8)
    branch([(-1,0,27),(-8,0,28),(-13,0,31)],1.7)
    branch([(0,0,28),(7,0,26),(12,0,28)],1.7)

    # Uneven blade silhouette: beveled slab sculpted into twisting bark ribbons.
    outline = [(-4,30),(-6,34),(-4,39),(-5,44),(-2,49),(-3,54),
               (-5,59),(-5,64),(-3,68),(-1,71),(-2,75),(0,79),
               (3,83),(5,87),(6,80),(8,76),(7,73),(9,69),
               (8,65),(9,61),(7,57),(5,54),(6,50),(4,47),
               (4,43),(6,39),(4,35),(5,31)]
    maskimg=Image.new('1',(35,88))
    ImageDraw.Draw(maskimg).polygon([(x+CX,z) for x,z in outline],fill=1)
    mask=np.array(maskimg).T
    for zz in range(30,88):
        xs=np.flatnonzero(mask[:,zz])
        if not len(xs): continue
        left,right=xs[0]-CX,xs[-1]-CX
        for xx in range(left,right+1):
            edge=min(xx-left,right-xx)
            depth=min(3,1+edge)
            # Sweeping diagonal striations have a wider light face and dark seam.
            phase=(xx - 3.0*math.sin((zz-31)/7.3) - .11*(zz-31))%6.5
            c=2 if edge==0 else 3 if phase<1.1 else 4 if phase<3.2 else 6 if phase<4.5 else 5
            if edge==1: c=min(c,4)
            if 3.2<phase<4.5 and edge>=2: depth+=1
            for yy in range(-depth,depth+1):
                put(xx,yy,zz,c if abs(yy)==depth else 3)

    # Long tapered knot opening; two tiny bright eyes sit below the bark lip.
    for zz in range(58,71):
        width=0 if zz in (58,70) else 1 if zz in (59,60,68,69) else 2
        center=round(.25*(zz-64))
        for xx in range(center-width,center+width+1):
            for yy in range(-5,6):
                if abs(yy)>1:
                    put(xx,yy,zz,0)
                else: put(xx,yy,zz,8)
    for side in (-1,1):
        put(-1,side,64,16)
        put(1,side,63,16)
        put(1,side,64,15)

    # Leaf guard, formed from individual thick overlapping lobes.
    leaves=[(-10,0,29,5,4,4),(-5,-2,30,5,4,4.5),
            (1,-2,28,5,4,5),(7,-1,27,4.5,4,5),
            (10,1,25,3,3,3.5),(-5,2,26,4,4,4),(3,3,26,5,3,4)]
    for args in leaves: ellipsoid(*args,leaf=True)
    # Small sprouting side shoots echo the woodland character.
    branch([(-3,1,39),(-8,1,42),(-9,1,45)],.9)
    ellipsoid(-9,0,44,3,2,2,leaf=True)
    branch([(4,1,36),(9,1,38)],1)
    ellipsoid(10,1,38,2.8,2,2.5,leaf=True)
    branch([(7,1,56),(11,1,55),(12,1,57)],.7)
    ellipsoid(11,1,55,2.3,1.8,2,leaf=True)
    # Hanging vines with intentional open loops.
    branch([(6,1,53),(9,1,50),(9,1,46),(7,1,45),(6,1,47),(6,1,49)],color=14)
    branch([(3,2,45),(5,2,44),(7,2,42),(7,2,40)],color=14)
    branch([(-7,1,26),(-8,1,22),(-6,1,20),(-4,1,22),(-4,1,25)],color=14)
    branch([(0,1,25),(2,1,21),(1,1,19)],color=14)
    # Crop the editable model to occupied bounds.
    pts=np.argwhere(A)
    low=pts.min(0); high=pts.max(0)+1
    return A[tuple(slice(a,b) for a,b in zip(low,high))].copy()

def previews(a):
    for name,az,el,roll,size,scale in [
        ('hero',-73,10,32,(1000,1100),11),
        ('front',-90,0,0,(460,1000),10),
        ('rear',90,0,0,(460,1000),10),
        ('side',0,0,0,(300,1000),10)]:
        im=vu.render(a,size,az=az,el=el,roll=roll,scale=scale)
        if name=='hero': im.save(ROOT/'previews'/'livingwood_sword_transparent.png')
        bg=Image.new('RGBA',size,'#202a25'); bg.alpha_composite(im)
        bg.convert('RGB').save(ROOT/'previews'/f'{name}.png')
    sheet=Image.new('RGB',(1220,1060),'#202a25')
    d=ImageDraw.Draw(sheet)
    x=0
    for label,w in [('front',460),('rear',460),('side',300)]:
        sheet.paste(Image.open(ROOT/'previews'/f'{label}.png'),(x,45))
        d.text((x+24,18),label.upper(),font=vu.font(20),fill='#c8d0bd')
        x+=w
    sheet.save(ROOT/'previews'/'views.png')

if __name__=='__main__':
    a=build()
    p=ROOT/'livingwood_sword.vox'
    vu.export_vox(p,a)
    a,report=vu.validate(p,a)
    (ROOT/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    (ROOT/'palette.json').write_text(json.dumps(COLORS,indent=2)+'\n')
    previews(a)
    print(json.dumps(report,indent=2))
