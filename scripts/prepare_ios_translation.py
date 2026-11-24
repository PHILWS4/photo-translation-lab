"""Build pinned SentencePiece for an arm64 iPhone and copy hash-verified MT assets.
Mac only. First install requirements-ios-build.txt and download_models.py assets.
No downloads or compilation occur inside the app.
"""
import hashlib
import json
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.2.1'
URL = 'https://files.pythonhosted.org/packages/15/15/2e7a025fc62d764b151ae6d0f2a92f8081755ebe8d4a64099accc6f77ba6/sentencepiece-0.2.1.tar.gz'
SHA = '8138cec27c2f2282f4a34d9a016e3374cd40e5c6e9cb335063db66a0a3b71fad'

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def main():
    if sys.platform != 'darwin':
        raise SystemExit('iOS dependencies must be built on a Mac with Xcode.')
    import cmake
    binary = str(Path(cmake.CMAKE_BIN_DIR) / 'cmake')
    cache = ROOT / '.ios-cache'
    cache.mkdir(exist_ok=True)
    archive = cache / f'sentencepiece-{VERSION}.tar.gz'
    if not archive.exists() or sha(archive) != SHA:
        partial = archive.with_suffix('.part')
        subprocess.run(['curl', '--fail', '--location', '--retry', '2', '--connect-timeout', '15', '--max-time', '300', URL, '-o', str(partial)], check=True)
        if sha(partial) != SHA:
            raise SystemExit('SentencePiece archive checksum mismatch; not extracted.')
        partial.replace(archive)
    source = cache / 'spm-source' / f'sentencepiece-{VERSION}' / 'sentencepiece'
    # Re-extract the verified source; no local source patches.
    with tarfile.open(archive) as tar:
        tar.extractall(cache / 'spm-source', filter='data')
    build = cache / f'sentencepiece-{VERSION}-iphoneos'
    subprocess.run([binary, '-S', str(source), '-B', str(build), '-G', 'Unix Makefiles',
                    f'-DCMAKE_PROJECT_sentencepiece_INCLUDE={ROOT / "scripts/cmake/ios_helpers.cmake"}',
                    '-DCMAKE_SYSTEM_NAME=iOS', '-DCMAKE_OSX_SYSROOT=iphoneos', '-DCMAKE_OSX_ARCHITECTURES=arm64',
                    '-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0', '-DCMAKE_BUILD_TYPE=Release',
                    '-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY', '-DSPM_ENABLE_SHARED=OFF',
                    '-DSPM_BUILD_TEST=OFF', '-DSPM_ENABLE_TCMALLOC=OFF', '-DSPM_DISABLE_EMBEDDED_DATA=ON'], check=True)
    subprocess.run([binary, '--build', str(build), '--target', 'sentencepiece-static', '--parallel', '4'], check=True)
    vendor = ROOT / 'ios/Vendor/sentencepiece'
    (vendor / 'include').mkdir(parents=True, exist_ok=True)
    shutil.copyfile(build / 'src/libsentencepiece.a', vendor / 'libsentencepiece.a')
    shutil.copyfile(source / 'src/sentencepiece_processor.h', vendor / 'include/sentencepiece_processor.h')
    for name, path in [('SentencePiece.txt', source / 'LICENSE'),
                       ('SentencePiece-Protobuf.txt', source / 'third_party/protobuf-lite/LICENSE'),
                       ('SentencePiece-Abseil.txt', source / 'third_party/absl/LICENSE'),
                       ('SentencePiece-Darts.txt', source / 'third_party/darts_clone/LICENSE')]:
        shutil.copyfile(path, ROOT / 'ios/Licenses' / name)
    origin = ROOT / 'models/translation'
    target = ROOT / 'ios/Models/translation'
    checksums = json.loads((origin / 'checksums.json').read_text())
    files = []
    for name, digest in checksums.items():
        src = origin / name
        if not src.is_file() or sha(src) != digest:
            raise SystemExit(f'Missing or modified reference translation asset: {name}')
        dest = target / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)
        files.append({'file': name, 'sha256': digest})
    manifest = {'translation': 'Xenova/opus-mt-en-zh@046f55aec303cdee3e0318604406d4df20f1e8ea',
                'reference_manifest_sha256': sha(origin / 'manifest.json'), 'files': files,
                'sentencepiece': VERSION, 'reference_sentencepiece': '0.2.3',
                'normalization': 'sentencepiece-no-moses', 'source_archive': URL, 'source_sha256': SHA,
                'translation_execution': 'cpu-unfused-deterministic-v1', 'decoding': 'greedy-no-cache-128-v1', 'max_input_tokens': 256,
                'max_new_tokens': 128, 'provider': 'CPU', 'intra_threads': 2, 'inter_threads': 1}
    (target / 'native-translation-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Ready: arm64 iPhone SentencePiece library and verified local translation assets.')

if __name__ == '__main__':
    main()
