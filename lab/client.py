import argparse,hashlib,json,time,uuid,random,platform
from datetime import datetime, timezone
from pathlib import Path
import httpx
from .core import Engines,ROOT,PipelineError,preprocess,organize,run_image,measured,fingerprint
MODES=['S0','S1','S2','S3']
class Client:
 def __init__(self,url='http://127.0.0.1:8765',timeout=120):
  self.url=url.rstrip('/');self.http=httpx.Client(timeout=timeout,trust_env=False);self.engines=Engines()
 def close(self):self.http.close()
 def run(self,path,mode):
  if mode not in MODES:raise ValueError('未知方案')
  data=Path(path).read_bytes();task=str(uuid.uuid4());trace=[];up=down=0;request_ms=0;remote=None;started=time.perf_counter()
  try:
   if mode=='S0':result=run_image(self.engines,data,'P','client');trace=result['trace']
   else:
    payload=data;local={}
    if mode in ['S1','S2']:
     with measured(trace,'P','client'):payload=preprocess(data)
    if mode=='S2':
     with measured(trace,'O','client'):blocks=self.engines.recognize(payload)
     with measured(trace,'C','client'):segments=organize(blocks)
     local={'blocks':blocks,'segments':segments}
     if not segments:
      result={**local,'status':'NO_TEXT','translations':[],'trace':[]};remote=None
     else:
      req=self.http.build_request('POST',self.url+'/v1/translate',json={'task_id':task,'segments':[{'segment_id':s['segment_id'],'text':s['text']} for s in segments]})
      remote=req
    else:remote=self.http.build_request('POST',self.url+'/v1/image',files={'file':('image.png',payload,'application/octet-stream')},data={'task_id':task,'start':'O' if mode=='S1' else 'P'})
    if remote is not None:
     up=len(remote.read());t=time.perf_counter();response=self.http.send(remote);request_ms=(time.perf_counter()-t)*1000;down=len(response.content);response.raise_for_status();result=response.json()
     if result['task_id']!=task:raise PipelineError('服务器返回 task_id 不匹配')
     if result['model']!=fingerprint():raise PipelineError('端云模型或流水线配置不一致')
     result.update(local)
    trace+=result.get('trace',[])
   record={'task_id':task,'mode':mode,'status':result['status'],'input_sha256':hashlib.sha256(data).hexdigest(),'input_bytes':len(data),'duration_ms':round((time.perf_counter()-started)*1000,3),'trace':trace,'request_ms':request_ms,'upload_body_bytes':up,'download_body_bytes':down,'queue_wait_ms':result.get('queue_wait_ms',0),'model':fingerprint(),'host':platform.platform(),'execution_environment':'desktop-loopback-not-mobile','error':None}
   output={**record,'blocks':result.get('blocks',[]),'segments':result.get('segments',[]),'translations':result.get('translations',[])}
  except Exception as e:
   record={'task_id':task,'mode':mode,'status':'ERROR','duration_ms':(time.perf_counter()-started)*1000,'trace':trace,'request_ms':request_ms,'upload_body_bytes':up,'download_body_bytes':down,'error':str(e),'execution_environment':'desktop-loopback-not-mobile'};output=record
  record['recorded_at_utc']=datetime.now(timezone.utc).isoformat()
  output['recorded_at_utc']=record['recorded_at_utc']
  # Do not persist original text in measurement logs.
  (ROOT/'results').mkdir(exist_ok=True)
  with (ROOT/'results/runs.jsonl').open('a') as f:f.write(json.dumps(record,ensure_ascii=False)+'\n')
  return output

def main():
 ap=argparse.ArgumentParser();ap.add_argument('image');ap.add_argument('--mode',choices=MODES+['all'],default='all');ap.add_argument('--server',default='http://127.0.0.1:8765');ap.add_argument('--repeat',type=int,default=1);ap.add_argument('--seed',type=int,default=42);args=ap.parse_args()
 if not 1<=args.repeat<=100:ap.error('repeat 需为 1 到 100')
 client=Client(args.server)
 print('正在预加载客户端模型（不计入单次处理时间）…',flush=True)
 client.engines.warmup();rng=random.Random(args.seed);failed=False
 try:
  for _ in range(args.repeat):
   modes=MODES.copy() if args.mode=='all' else [args.mode];rng.shuffle(modes)
   for mode in modes:
    result=client.run(args.image,mode);print(json.dumps(result,ensure_ascii=False,indent=2),flush=True);failed|=result['status']=='ERROR'
 finally:client.close()
 raise SystemExit(1 if failed else 0)
if __name__=='__main__':main()
