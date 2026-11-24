import io
import pytest
from PIL import Image
from lab.core import decode,preprocess,PipelineError,organize
from lab.server import app
from fastapi.testclient import TestClient

def test_invalid_image():
 with pytest.raises(PipelineError):decode(b'not an image')
def test_preprocess_orientation_and_size():
 im=Image.new('RGB',(2000,1000));ex=im.getexif();ex[274]=6;b=io.BytesIO();im.save(b,format='JPEG',exif=ex)
 out=decode(preprocess(b.getvalue()));assert out.size==(800,1600)
def test_traceable_segments():
 assert organize([{'block_id':'a','text':'  Hello  '}])==[{'segment_id':'0','source_block_ids':['a'],'text':'Hello'}]
def test_api_rejects_wrong_languages_and_stage():
 with TestClient(app) as c:
  assert c.post('/v1/translate',json={'task_id':'x','source_lang':'zh','segments':[{'segment_id':'1','text':'Hi'}]}).status_code==422
  assert c.post('/v1/image',data={'task_id':'x','start':'T'},files={'file':('bad',b'x')}).status_code==422
  assert c.post('/v1/image',data={'task_id':'x','start':'P'},files={'file':('bad',b'x')}).status_code==422
