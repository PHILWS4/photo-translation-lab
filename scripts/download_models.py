"""Download a pinned ONNX translation model. No downloads during inference."""
import concurrent.futures,hashlib,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REV='046f55aec303cdee3e0318604406d4df20f1e8ea'
FILES=['config.json','generation_config.json','source.spm','target.spm','vocab.json','tokenizer_config.json','special_tokens_map.json','onnx/encoder_model_quantized.onnx','onnx/decoder_model_quantized.onnx']
CHECKSUMS_PATH=ROOT/'models/translation/checksums.json'
CHECKSUMS=json.loads(CHECKSUMS_PATH.read_text()) if CHECKSUMS_PATH.exists() else {}
ENDPOINT=os.environ.get('MODEL_ENDPOINT','https://huggingface.co').rstrip('/')
def get(name):
 p=ROOT/'models/translation'/name;p.parent.mkdir(parents=True,exist_ok=True)
 url=f'{ENDPOINT}/Xenova/opus-mt-en-zh/resolve/{REV}/{name}'
 if not p.exists():
  tmp=p.with_suffix(p.suffix+'.part')
  subprocess.run(['curl','--fail','-L','--retry','3','--connect-timeout','20','--max-time','900','-sS',url,'-o',str(tmp)],check=True)
  if name in CHECKSUMS and hashlib.sha256(tmp.read_bytes()).hexdigest()!=CHECKSUMS[name]:
   raise ValueError(f'校验失败，未安装下载文件: {name}')
  tmp.replace(p)
 item={'file':name,'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
 if name in CHECKSUMS and item['sha256']!=CHECKSUMS[name]:raise ValueError(f'现有文件已改变: {name}')
 print(name,item['size'],flush=True);return item
if __name__=='__main__':
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex: records=list(ex.map(get,FILES))
 (ROOT/'models/translation/manifest.json').write_text(json.dumps({'repository':'Xenova/opus-mt-en-zh','revision':REV,'download_endpoint':ENDPOINT,'files':records},indent=2))
