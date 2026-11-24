"""Generate synthetic OCR inputs and Python reference outputs, never user photos."""
from pathlib import Path
import io,json,hashlib,platform
from PIL import Image,ImageDraw,ImageFont
from lab.core import Engines,preprocess,fingerprint
ROOT=Path(__file__).resolve().parents[1]; out=ROOT/'ios/Fixtures';out.mkdir(exist_ok=True)
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',32)
hello=Image.open(ROOT/'data/samples/hello.png').convert('RGB')
images={name:Image.open(ROOT/f'data/samples/{name}.png').convert('RGB') for name in ['hello','menu','blank']}
images['rotated90']=hello.rotate(90,expand=True)
images['upside_down']=hello.rotate(180,expand=True)
images['skewed']=hello.rotate(8,expand=True,fillcolor='white',resample=Image.Resampling.BICUBIC)
lines=['Local OCR runs on this phone.','Only text goes to the server.','The model stays the same.','Please open the blue door.','Room 205 is on the left.','Fresh coffee costs 12 dollars.','The library closes at seven.','Thank you for your help.']
im=Image.new('RGB',(950,620),'white');draw=ImageDraw.Draw(im)
for i,line in enumerate(lines):draw.text((25,20+i*70),line,font=font,fill='black')
images['eight_lines']=im
im=Image.new('RGB',(700,65),'white');ImageDraw.Draw(im).text((15,12),'One short line of English.',font=font,fill='black');images['wide_line']=im
engines=Engines();engines.load_ocr();cases=[]
for name,im in images.items():
 stream=io.BytesIO();im.save(stream,format='PNG');data=preprocess(stream.getvalue());(out/f'{name}.bin').write_bytes(data)
 blocks=engines.recognize(data)
 cases.append({'name':name,'input_sha256':hashlib.sha256(data).hexdigest(),'blocks':blocks})
 print(name,[b['text'] for b in blocks],flush=True)
(out/'reference.json').write_text(json.dumps({'reference_model':fingerprint(),'cases':cases},ensure_ascii=False,indent=2)+'\n')
