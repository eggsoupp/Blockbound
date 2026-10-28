from pathlib import Path
from PIL import Image
from collections import Counter
ROOT = Path(__file__).parent
FILES = {'sword':'e94ad0c6-9bca-402a-bcc5-e4e3b3066ef7','pickaxe':'1f3c6b3d-dc66-4f86-8b30-6bcadcf94d96','axe':'725098e6-80a5-477b-8cf3-1d3cb2c6dc0c'}
for name,uid in FILES.items():
    im=Image.open(Path('C:/Users/Elias/AppData/Local/Temp')/f'codex-clipboard-{uid}.png').convert('RGBA')
    print(name,im.size,Counter(im.getdata()).most_common(20))
    n=64 if name=='sword' else 16
    out=Image.new('RGBA',(n,n)); colors=[]
    for y in range(n):
        row=''
        for x in range(n):
            c=im.getpixel((int((x+.5)*im.width/n),int((y+.5)*im.height/n)))
            if c[3]==0 or max(c[:3])<5: c=(0,0,0,0)
            out.putpixel((x,y),c)
            if c[3]:
                if c not in colors:colors.append(c)
                row+=chr(65+colors.index(c))
            else:row+='.'
        if n==16: print(row)
    print('grid palette',colors)
    out.save(ROOT/f'{name}-source-pixels.png')
    out.resize((640,640),Image.Resampling.NEAREST).save(ROOT/f'{name}-source-large.png')
