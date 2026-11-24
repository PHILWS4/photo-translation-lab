import json
from pathlib import Path
from lab.client import Client
from lab.core import ROOT
c=Client();c.engines.warmup()
expected={'S0':[('P','client'),('O','client'),('C','client'),('T','client')],'S1':[('P','client'),('O','server'),('C','server'),('T','server')],'S2':[('P','client'),('O','client'),('C','client'),('T','server')],'S3':[('P','server'),('O','server'),('C','server'),('T','server')]}
report=[]
try:
 for sample in ['hello','menu']:
  outputs=[]
  for mode,stages in expected.items():
   r=c.run(ROOT/f'data/samples/{sample}.png',mode)
   assert r['status']=='SUCCESS',r
   assert [(s['stage'],s['location']) for s in r['trace']]==stages,r
   assert r['translations'] and all(x['text'] for x in r['translations'])
   assert (r['upload_body_bytes']==0)==(mode=='S0')
   outputs.append(r['translations']);report.append(r);print(sample,mode,r['duration_ms'],r['translations'],flush=True)
  assert all(o==outputs[0] for o in outputs),'端云译文不一致'
 for mode in expected:
  r=c.run(ROOT/'data/samples/blank.png',mode);assert r['status']=='NO_TEXT',r
  report.append(r)
 (ROOT/'results/smoke_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
finally:c.close()
print('四种真实执行路径、两张样例译文一致性和空白输入检查全部通过。')
