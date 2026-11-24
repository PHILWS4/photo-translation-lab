"""Check the built app, not just source: Xcode must not rewrite experiment input."""
import argparse
import hashlib
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('app_bundle', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
original = (root / 'data/samples/hello.png').read_bytes()
packaged = (args.app_bundle / 'hello-sample.bin').read_bytes()
if original != packaged:
    raise SystemExit('FAIL: packaged sample differs from original; do not use it for partition comparison')
print('PASS: app-bundle sample is byte-identical to original PNG; SHA256=' + hashlib.sha256(packaged).hexdigest())
