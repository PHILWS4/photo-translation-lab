"""Prepare pinned native OCR dependencies, models and vocabulary for Xcode.
Run with this project's .venv Python. No packages or credentials are installed globally.
"""
import argparse,hashlib,json,shutil,subprocess,sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--cache-dir',type=Path,default=ROOT/'.ios-cache')
p.add_argument('--github-mirror',default='',help='Optional transport prefix, e.g. https://ghfast.top; upstream SHA256 remains mandatory')
a=p.parse_args();a.cache_dir.mkdir(parents=True,exist_ok=True)
ARTIFACTS=[
 ('opencv-4.12.0-ios-framework.zip','https://github.com/opencv/opencv/releases/download/4.12.0/opencv-4.12.0-ios-framework.zip','86b42c9f141cd9169b91be2fc380b0e556a88a95c98ccc8e7aef8349ab74cf70','opencv'),
 ('onnxruntime-c-1.24.2.zip','https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip','f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54','onnxruntime'),
]

def sha(path):
 with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

provenance=[]
for name,upstream,digest,folder in ARTIFACTS:
 archive=a.cache_dir/name
 transport=(a.github_mirror.rstrip('/')+'/'+upstream) if a.github_mirror and upstream.startswith('https://github.com/') else upstream
 if not archive.exists() or sha(archive)!=digest:
  partial=archive.with_suffix(archive.suffix+'.part')
  print('Downloading',name,flush=True)
  subprocess.run(['curl','--fail','--location','--continue-at','-','--retry','2','--retry-delay','15','--connect-timeout','15',transport,'--output',str(partial)],check=True)
  if sha(partial)!=digest:raise SystemExit(f'Checksum mismatch: {partial}; not extracted')
  partial.replace(archive)
 target=ROOT/'ios/Vendor'/folder;target.mkdir(parents=True,exist_ok=True)
 # ditto preserves framework symlinks; ZipFile.extractall does not.
 subprocess.run(['/usr/bin/ditto','-x','-k',str(archive),str(target)],check=True)
 provenance.append({'file':name,'upstream':upstream,'transport':transport,'sha256':digest})

import rapidocr_onnxruntime
import onnxruntime as ort
source=Path(rapidocr_onnxruntime.__file__).parent/'models';target=ROOT/'ios/Models';target.mkdir(exist_ok=True)
manifest=json.loads((ROOT/'models/ocr-manifest.json').read_text())
for model in manifest['models']:
 src=source/Path(model['file']).name
 if sha(src)!=model['sha256']:raise SystemExit(f'OCR model mismatch: {src.name}')
 shutil.copyfile(src,target/src.name)
options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
session=ort.InferenceSession(str(target/'ch_PP-OCRv4_rec_infer.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
characters=['blank']+session.get_modelmeta().custom_metadata_map['character'].splitlines()+[' ']
assert len(characters)==6625
(target/'characters.json').write_text(json.dumps(characters,ensure_ascii=False))
shutil.copyfile(ROOT/'models/ocr-manifest.json',target/'ocr-manifest.json')
identity={'models_manifest_sha256':sha(target/'ocr-manifest.json'),'characters_sha256':sha(target/'characters.json'),'native_port':'rapidocr-1.4.4-cpp-v1','runtime':'onnxruntime-1.24.2','opencv':'4.12.0','archives':provenance}
(target/'native-ocr-manifest.json').write_text(json.dumps(identity,ensure_ascii=False,indent=2)+'\n')
print('Ready: three hash-verified OCR models, 6625 dictionary tokens, ONNX Runtime 1.24.2 and OpenCV 4.12.0.')
