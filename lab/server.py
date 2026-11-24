from contextlib import asynccontextmanager
import json,time,threading
from typing import Literal
from fastapi import FastAPI,UploadFile,File,Form,HTTPException
from pydantic import BaseModel,Field,ConfigDict
from .core import Engines,PipelineError,MAX_BYTES,run_image,measured,fingerprint
engines=Engines();lock=threading.Lock()
@asynccontextmanager
async def lifespan(app):
 engines.warmup();yield
app=FastAPI(title='Photo Translation Lab',version='1.0.0',lifespan=lifespan)
class Segment(BaseModel):
 model_config=ConfigDict(extra='forbid')
 segment_id:str=Field(min_length=1,max_length=80)
 text:str=Field(min_length=1,max_length=1500)
class TranslationRequest(BaseModel):
 model_config=ConfigDict(extra='forbid')
 task_id:str=Field(min_length=1,max_length=80)
 source_lang:Literal['en']='en'
 target_lang:Literal['zh']='zh'
 segments:list[Segment]=Field(min_length=1,max_length=50)
@app.get('/health')
def health():return {'status':'ready','api_version':'1.0.0','model':fingerprint(),'startup_ms':engines.initialized_ms}
@app.post('/v1/image')
def image(file:UploadFile=File(...),task_id:str=Form(...),start:Literal['P','O']=Form(...)):
 data=file.file.read(MAX_BYTES+1)
 if len(data)>MAX_BYTES:raise HTTPException(413,'图片超过 12 MiB')
 entered=time.perf_counter()
 try:
  with lock:
   wait=(time.perf_counter()-entered)*1000
   result=run_image(engines,data,start,'server')
  return {**result,'task_id':task_id,'queue_wait_ms':wait,'model':fingerprint()}
 except PipelineError as e:raise HTTPException(422,str(e)) from e
@app.post('/v1/translate')
def translate(req:TranslationRequest):
 ids=[s.segment_id for s in req.segments]
 if len(ids)!=len(set(ids)):raise HTTPException(422,'segment_id 必须唯一')
 entered=time.perf_counter();trace=[]
 try:
  with lock:
   wait=(time.perf_counter()-entered)*1000
   with measured(trace,'T','server'):out=engines.translate([s.model_dump() for s in req.segments])
  return {'task_id':req.task_id,'status':'SUCCESS','translations':out,'trace':trace,'queue_wait_ms':wait,'model':fingerprint()}
 except PipelineError as e:raise HTTPException(422,str(e)) from e
