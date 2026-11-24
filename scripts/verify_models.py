import hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'models/translation'
m=json.loads((root/'manifest.json').read_text())
for item in m['files']:
 p=root/item['file']
 assert p.stat().st_size==item['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==item['sha256'],p
print('全部翻译模型文件与本地下载清单一致。此检查不替代上游签名验证。')

import importlib.util,importlib.metadata
pkg=Path(importlib.util.find_spec('rapidocr_onnxruntime').origin).parent
ocr=json.loads((root.parent/'ocr-manifest.json').read_text())
assert importlib.metadata.version('rapidocr_onnxruntime')=='1.4.4'
for item in ocr['models']:
 p=pkg/item['file']
 assert hashlib.sha256(p.read_bytes()).hexdigest()==item['sha256'],p
print('OCR 包版本及三个权重文件校验通过。')
