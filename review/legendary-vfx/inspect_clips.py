import sys, pathlib, subprocess
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[2]/'build/legendary-tools/python-deps'))
import imageio_ffmpeg
from PIL import Image,ImageDraw
root=pathlib.Path('C:/Users/Elias/AppData/Local/Packages/Microsoft.ScreenSketch_8wekyb3d8bbwe/TempState/Recordings')
ff=imageio_ffmpeg.get_ffmpeg_exe()
out=pathlib.Path(__file__).parent
clips={'2040-51.6565865':[1.2,2.25,2.65,3.6], '2044-32.8193586':[3.5,5.8,6.7,7.6], '2028-54.6346444':[.65,.85,1.15,1.5], '2049-31.5167214':[1.2,1.7,2.6,3.3]}
for clip,times in clips.items():
    sheet=Image.new('RGB',(1000,600),'#10131a')
    for i,t in enumerate(times):
        png=out/f'{clip}-{i}.png'
        subprocess.run([ff,'-loglevel','error','-ss',str(t),'-i',str(root/f'20261030-{clip}.mp4'),'-frames:v','1','-y',str(png)],check=True)
        im=Image.open(png).convert('RGB'); im.thumbnail((490,270))
        x=(i%2)*500;y=(i//2)*300
        sheet.paste(im,(x+(500-im.width)//2,y+24))
        ImageDraw.Draw(sheet).text((x+8,y+5),f'{clip} / {t:.2f}s',fill='white')
    sheet.save(out/f'{clip}-detail.jpg')
