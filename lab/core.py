from __future__ import annotations
import hashlib,io,json,time
from pathlib import Path
from contextlib import contextmanager
import numpy as np
from PIL import Image,ImageOps
ROOT=Path(__file__).resolve().parents[1]
MAX_BYTES=12*1024*1024
Image.MAX_IMAGE_PIXELS=20_000_000
class PipelineError(ValueError): pass
@contextmanager
def measured(trace,stage,location):
 start=time.perf_counter()
 try:yield
 finally:trace.append({'stage':stage,'location':location,'duration_ms':round((time.perf_counter()-start)*1000,3)})
def decode(data):
 if not data or len(data)>MAX_BYTES:raise PipelineError('图片为空或超过 12 MiB')
 try:
  with Image.open(io.BytesIO(data)) as im:
   if im.width*im.height>20_000_000:raise PipelineError('图片超过 2000 万像素')
   im.load();return im.copy()
 except PipelineError:raise
 except Exception as exc:raise PipelineError('无效或不支持的图片') from exc
def preprocess(data):
 im=ImageOps.exif_transpose(decode(data)).convert('RGB');im.thumbnail((1600,1600))
 b=io.BytesIO();im.save(b,format='PNG');return b.getvalue()
class Engines:
 def __init__(self):self.ocr=None;self.tokenizer=None;self.encoder=None;self.decoder=None;self.initialized_ms={}
 def load_ocr(self):
  if self.ocr is None:
   start=time.perf_counter()
   from rapidocr_onnxruntime import RapidOCR
   self.ocr=RapidOCR(intra_op_num_threads=2,inter_op_num_threads=1)
   self.initialized_ms['ocr']=(time.perf_counter()-start)*1000
 def load_translation(self):
  if self.encoder is not None:return
  start=time.perf_counter()
  import onnxruntime as ort
  from transformers import MarianTokenizer
  path=ROOT/'models/translation'
  if not (path/'manifest.json').exists():raise PipelineError('翻译模型未准备，请运行 scripts/download_models.py')
  self.tokenizer=MarianTokenizer.from_pretrained(str(path),local_files_only=True)
  self.config=json.loads((path/'config.json').read_text())
  options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
  self.encoder=ort.InferenceSession(str(path/'onnx/encoder_model_quantized.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
  self.decoder=ort.InferenceSession(str(path/'onnx/decoder_model_quantized.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
  self.initialized_ms['translation']=(time.perf_counter()-start)*1000
 def recognize(self,data):
  self.load_ocr()
  # RapidOCR's ndarray contract is BGR, not Pillow RGB.
  arr=np.asarray(decode(data).convert('RGB'))[:,:,::-1].copy()
  result,_=self.ocr(arr)
  return [{'block_id':str(i),'text':r[1],'polygon':r[0],'confidence':float(r[2])} for i,r in enumerate(result or [])]
 def translate(self,segments):
  self.load_translation();out=[]
  for segment in segments:
   tokens=self.tokenizer(segment['text'],return_tensors='np',truncation=False)
   if tokens['input_ids'].shape[1]>256:raise PipelineError('单句超过 256 token，请缩短输入；不会静默截断')
   enc=self.encoder.run(None,{x.name:tokens[x.name].astype(np.int64) for x in self.encoder.get_inputs()})[0]
   ids=np.array([[self.config['decoder_start_token_id']]],dtype=np.int64);ended=False
   for _ in range(128):
    feed={'input_ids':ids,'encoder_hidden_states':enc,'encoder_attention_mask':tokens['attention_mask'].astype(np.int64)}
    pred=self.decoder.run(['logits'],{x.name:feed[x.name] for x in self.decoder.get_inputs()})[0][0,-1].copy()
    pred[self.config['pad_token_id']]=-np.inf
    nxt=int(np.argmax(pred));ids=np.concatenate([ids,[[nxt]]],axis=1)
    if nxt==self.config['eos_token_id']:ended=True;break
   if not ended:raise PipelineError('译文生成达到长度上限，未把截断文本当成成功结果')
   out.append({'segment_id':segment['segment_id'],'text':self.tokenizer.decode(ids[0,1:],skip_special_tokens=True)})
  return out
 def warmup(self):self.load_ocr();self.load_translation()
def organize(blocks):
 # First version supports ordinary single-column text. Keep OCR order and traceable line IDs.
 return [{'segment_id':str(i),'source_block_ids':[b['block_id']],'text':b['text'].strip()} for i,b in enumerate(blocks) if b['text'].strip()]
def run_image(engines,data,start,location):
 trace=[]
 if start=='P':
  with measured(trace,'P',location):data=preprocess(data)
 elif start!='O':raise PipelineError('起始阶段只能为 P 或 O')
 with measured(trace,'O',location):blocks=engines.recognize(data)
 with measured(trace,'C',location):segments=organize(blocks)
 with measured(trace,'T',location):translated=engines.translate(segments) if segments else []
 return {'status':'SUCCESS' if segments else 'NO_TEXT','blocks':blocks,'segments':segments,'translations':translated,'trace':trace}
def fingerprint():
 p=ROOT/'models/translation/manifest.json'
 ocr_manifest=ROOT/'models/ocr-manifest.json'
 return {'ocr':'rapidocr-onnxruntime-1.4.4','ocr_manifest_sha256':hashlib.sha256(ocr_manifest.read_bytes()).hexdigest(),'translation':'Xenova/opus-mt-en-zh@046f55a','translation_manifest_sha256':hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None,'preprocess':'exif-rgb-max1600-png-v1','decoding':'greedy-no-cache-128-v1'}
