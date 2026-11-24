"""Generate explicit synthetic MT/tokenizer reference fixtures; never alters image fixtures."""
import hashlib
import importlib.util
import json
from pathlib import Path
import numpy as np
from lab.core import Engines, ROOT

def main():
    if importlib.util.find_spec('sacremoses'):
        raise SystemExit('Reference must use the established no-Moses normalization; do not silently change it.')
    engine = Engines()
    engine.load_translation()
    images = json.loads((ROOT / 'ios/Fixtures/reference.json').read_text())['cases']
    texts = list(dict.fromkeys(b['text'].strip() for case in images for b in case['blocks'] if b['text'].strip()))
    texts += ["I can't find the train station.", 'The price is $12.50.', 'Please turn left at the next street.',
              'Keep this medicine away from children.', 'Open from 9:00 AM to 5:00 PM.']
    cases = []
    for text in texts:
        token = engine.tokenizer(text, return_tensors='np', truncation=False)
        hidden = engine.encoder.run(None, {x.name: token[x.name].astype(np.int64) for x in engine.encoder.get_inputs()})[0]
        ids = np.array([[engine.config['decoder_start_token_id']]], dtype=np.int64)
        for _ in range(128):
            feed = {'input_ids': ids, 'encoder_hidden_states': hidden, 'encoder_attention_mask': token['attention_mask'].astype(np.int64)}
            logits = engine.decoder.run(['logits'], {x.name: feed[x.name] for x in engine.decoder.get_inputs()})[0][0, -1].copy()
            logits[engine.config['pad_token_id']] = -np.inf
            nxt = int(np.argmax(logits)); ids = np.concatenate([ids, [[nxt]]], axis=1)
            if nxt == engine.config['eos_token_id']:
                break
        else:
            raise RuntimeError('Reference fixture exceeded generation limit')
        translated = engine.tokenizer.decode(ids[0, 1:], skip_special_tokens=True)
        assert engine.translate([{'segment_id':'0','text':text}])[0]['text'] == translated
        cases.append({'source': text, 'input_ids': token['input_ids'][0].tolist(), 'output_ids': ids[0, 1:].tolist(), 'text': translated})
    tokenizer_texts = ['', ' ', '\tHello\nworld.  ', 'café naïve résumé', '“Hello”—she said…',
                       'Hello\u00a0world', 'ＡＢＣ １２３', 'English 中文 😀', '<unk> Hello </s><pad>',
                       '>>zh<<Hello world.', 'A<unk>B', 'Hello\x00world', ' e\u0301 ',
                       'one two ' * 130] + texts
    tokenization = [{'source': text, 'ids': engine.tokenizer(text, truncation=False)['input_ids']} for text in tokenizer_texts]
    decode_ids = [[0, 1, 65000], [65000] + cases[0]['output_ids'] + [1,0]]
    decode_ids += [engine.tokenizer("hello . I 'm fine !")["input_ids"]]
    decoding = [{'ids': ids, 'text': engine.tokenizer.decode(ids, skip_special_tokens=True)} for ids in decode_ids]
    by_text = {case['source']: case['text'] for case in cases}
    image_cases = []
    for case in images:
        lines = [b['text'].strip() for b in case['blocks'] if b['text'].strip()]
        image_cases.append({'name':case['name'],'input_sha256':case['input_sha256'], 'segments':lines,
                            'translations':[by_text[text] for text in lines]})
    report = {'reference_environment':'mac-python-reference-not-mobile', 'translation_execution':'cpu-unfused-deterministic-v1', 'reference_sentencepiece':'0.2.3',
              'translation_manifest_sha256':hashlib.sha256((ROOT/'models/translation/manifest.json').read_bytes()).hexdigest(),
              'translation_cases':cases, 'tokenization_cases':tokenization, 'decoding_cases':decoding,
              'image_cases':image_cases}
    (ROOT/'ios/Fixtures/translation-reference.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(f'Reference: {len(cases)} translations, {len(tokenization)} tokenizer cases, {len(decoding)} decode cases, {len(image_cases)} images.')

if __name__ == '__main__':
    main()
