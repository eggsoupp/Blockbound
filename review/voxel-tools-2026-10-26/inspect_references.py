from PIL import Image
from collections import Counter
from pathlib import Path
p=Path('C:/Users/Elias/AppData/Local/Temp')
for name,fn,n in [('axe','codex-clipboard-1d4ddedf-fdfa-4c4f-9f6a-4cefc605bb61.png',16),('sword','codex-clipboard-5bd6b459-01ee-4438-8ae3-3fadaf1fe540.png',24),('pickaxe','codex-clipboard-35bb91a2-ed9d-4a03-a0ca-c89be5b8022f.png',16)]:
 im=Image.open(p/fn).convert('RGBA'); colors=[]; rows=[]
 for y in range(n):
  row=[]
  for x in range(n if name!='pickaxe' else 15):
   if name=='pickaxe': cx,cy=307+(x+.5)*48,262+(y+.5)*48
   else: cx,cy=(x+.5)*im.width/n,(y+.5)*im.height/n
   c=Counter(im.crop((int(cx)-3,int(cy)-3,int(cx)+4,int(cy)+4)).getdata()).most_common(1)[0][0]
   if c[3]==0 or (name=='sword' and min(c[:3])>210) or (name=='pickaxe' and c[0]>c[1]*1.35 and c[0]>95): row.append(None)
   else:
    if name=='sword':
     opts=[(30,30,30,255),(166,97,55,255),(136,68,47,255)]
     c=min(opts,key=lambda q:sum((q[k]-c[k])**2 for k in range(3)))
    if c not in colors: colors.append(c)
    row.append(colors.index(c))
  rows.append(row)
 print(name,'COLORS', list(enumerate(colors)))
 for row in rows: print(' '.join('.' if c is None else str(c) for c in row))
