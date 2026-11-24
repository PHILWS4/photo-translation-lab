from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
font=next((Path(p) for p in ['/System/Library/Fonts/Supplemental/Arial.ttf','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'] if Path(p).exists()),None)
f=ImageFont.truetype(str(font),42) if font else ImageFont.load_default(size=42)
for name,lines in [('hello',['Hello world.','Welcome to our school.']),('menu',['Fresh coffee and hot tea.','Please pay at the counter.'])]:
 im=Image.new('RGB',(1000,320),'white');dr=ImageDraw.Draw(im)
 for i,s in enumerate(lines):dr.text((45,55+95*i),s,font=f,fill='black')
 im.save(ROOT/f'data/samples/{name}.png');(ROOT/f'data/samples/{name}.txt').write_text('\n'.join(lines))
Image.new('RGB',(500,200),'white').save(ROOT/'data/samples/blank.png')
