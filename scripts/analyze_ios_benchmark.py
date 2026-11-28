"""Validate a device batch before summarizing. No failed/warmup timing is pooled into success latency."""
import argparse
import collections
import hashlib
import html
import json
import statistics
from pathlib import Path


def summarize(directory):
    directory = Path(directory)
    config = json.loads((directory / 'config.json').read_text())
    progress = json.loads((directory / 'progress.json').read_text())
    rows = [json.loads(line) for line in (directory / 'trials.jsonl').read_text().splitlines()]
    raw = [json.loads(line) for line in (directory / 'ios-runs.jsonl').read_text().splitlines()]
    metadata = json.loads((directory / 'metadata.json').read_text())
    if progress.get('state') != 'complete':
        raise ValueError('Batch is incomplete; do not present it as a completed experiment')
    samples = {s['id']: s['sha256'] for s in config['samples']}
    phase = config['phase']
    formal = [r for r in rows if r['phase'] == phase]
    warmup = [r for r in rows if r['phase'] == 'warmup']
    expected = {(s, m, n) for s in samples for m in ['S0', 'S1', 'S2', 'S3'] for n in range(1, config['repeats'] + 1)}
    found = [(r['sample_id'], r['mode'], r['repetition']) for r in formal]
    if len(found) != len(expected) or set(found) != expected:
        raise ValueError('Missing or duplicate sample/partition/repetition')
    expected_warmup = {(s, m, n) for s in samples for m in ['S0', 'S1', 'S2', 'S3'] for n in range(1, config['warmup_rounds'] + 1)}
    actual_warmup = [(r['sample_id'], r['mode'], r['repetition']) for r in warmup]
    if len(actual_warmup) != len(expected_warmup) or set(actual_warmup) != expected_warmup:
        raise ValueError('Missing or duplicate warmup records')
    if len(rows) != len(formal) + len(warmup):
        raise ValueError('Unexpected phase')
    if progress['completed'] != len(formal) or progress['total'] != len(expected):
        raise ValueError('Progress count mismatch')
    if len(raw) != len(rows) or any(r['measurement'] != m for r, m in zip(rows, raw)):
        raise ValueError('Trial measurements differ from original pipeline log')
    task_ids = set()
    for index, row in enumerate(rows, 1):
        m = row['measurement']
        if row['batch_id'] != config['batch_id'] or row['sequence'] != index:
            raise ValueError('Batch or sequence mismatch')
        if m['task_id'] in task_ids:
            raise ValueError('Duplicate task ID')
        task_ids.add(m['task_id'])
        if m['input_sha256'] != samples[row['sample_id']] or row['input_sha256'] != m['input_sha256'] or m['mode'] != row['mode']:
            raise ValueError('Input hash or partition mismatch')
        if not m['execution_environment'].startswith('ios-physical-device-') or m['status'] != row['outcome']:
            raise ValueError('Nonphysical device or inconsistent outcome')
        if row['before']['thermal_state'] != 0:
            raise ValueError('Trial started before thermal cooldown completed')
        if m['status'] == 'SUCCESS':
            for key in ['ocr_manifest_sha256', 'translation_manifest_sha256', 'translation_execution']:
                if m['model'][key] != metadata['server_model'][key]:
                    raise ValueError('Model identity changed')
            locations = {'S0': ['client'] * 4, 'S1': ['client'] + ['server'] * 3,
                         'S2': ['client'] * 3 + ['server'], 'S3': ['server'] * 4}[m['mode']]
            if [(s['stage'], s['location']) for s in m['trace']] != list(zip('POCT', locations)):
                raise ValueError('Incorrect stage allocation')
            if m['mode'] == 'S0' and any(m[x] != 0 for x in ['upload_body_bytes', 'download_body_bytes', 'request_ms', 'health_check_ms']):
                raise ValueError('S0 used a network operation')
    groups = []
    for sample in samples:
        for mode in ['S0', 'S1', 'S2', 'S3']:
            trials = [r for r in formal if r['sample_id'] == sample and r['mode'] == mode]
            success = [r for r in trials if r['outcome'] == 'SUCCESS']
            failed = [r for r in trials if r['outcome'] == 'ERROR']
            durations = [r['measurement']['duration_ms'] for r in success]
            group = {'sample_id': sample, 'mode': mode, 'attempts': len(trials), 'successes': len(success),
                     'errors': len(failed), 'no_text': sum(r['outcome'] == 'NO_TEXT' for r in trials),
                     'success_rate': len(success) / len(trials),
                     'mean_ms': statistics.mean(durations) if durations else None,
                     'median_ms': statistics.median(durations) if durations else None,
                     'sd_ms': statistics.stdev(durations) if len(durations) > 1 else None,
                     'min_ms': min(durations) if durations else None, 'max_ms': max(durations) if durations else None,
                     'failure_mean_ms': statistics.mean(r['measurement']['duration_ms'] for r in failed) if failed else None,
                     'mean_upload_body_bytes': statistics.mean(r['measurement']['upload_body_bytes'] for r in success) if success else None,
                     'mean_stage_ms': {stage: statistics.mean(next(s['duration_ms'] for s in r['measurement']['trace'] if s['stage'] == stage) for r in success) for stage in 'POCT'} if success else {},
                     'distinct_outputs': len({json.dumps([r['segments'], r['translations']], ensure_ascii=False) for r in success}),
                     'failed_reasons': dict(collections.Counter(r['error'] for r in failed))}
            groups.append(group)
    equality = {}
    for sample in samples:
        outputs = [r for r in formal if r['sample_id'] == sample and r['outcome'] == 'SUCCESS']
        equality[sample] = {'observed_modes': sorted({r['mode'] for r in outputs}),
            'distinct_ocr_outputs': len({json.dumps(r['segments']) for r in outputs}),
            'distinct_translation_outputs': len({json.dumps(r['translations']) for r in outputs})}
    return {'batch_id': config['batch_id'], 'phase': phase, 'formal_attempts': len(formal), 'warmup_attempts': len(warmup),
            'successes': sum(r['outcome'] == 'SUCCESS' for r in formal), 'errors': sum(r['outcome'] == 'ERROR' for r in formal),
            'groups': groups, 'output_consistency': equality,
            'thermal_transitions': dict(collections.Counter(f"{r['before']['thermal_state']}->{r['after']['thermal_state']}" for r in formal)),
            'low_power_trials': sum(r['before']['low_power_mode'] or r['after']['low_power_mode'] for r in formal),
            'nonforeground_trials': sum(r['before']['application_state'] != 0 or r['after']['application_state'] != 0 for r in formal),
            'battery_states': sorted({r[k]['battery_state'] for r in formal for k in ['before', 'after']}),
            'cooldown_seconds': sum(r['cooldown_seconds'] for r in rows),
            'metadata': metadata, 'finished_at': progress.get('finished_at'),
            'input_sha256': samples, 'raw_trials_sha256': hashlib.sha256((directory / 'trials.jsonl').read_bytes()).hexdigest(),
            'interpretation': 'SUCCESS means pipeline completion, not correct translation. Latency summaries exclude warmup, ERROR and NO_TEXT. S3 preprocessing may change OCR text and translation workload.'}


def render_html(summary):
    def number(value):
        return '—' if value is None else f'{value:,.1f}'
    rows = ''.join('<tr>' + ''.join(f'<td>{html.escape(str(v))}</td>' for v in [g['sample_id'], g['mode'],
        f"{g['successes']}/{g['attempts']}", number(g['mean_ms']), number(g['median_ms']), number(g['sd_ms']),
        number(g['mean_upload_body_bytes']), number(g['failure_mean_ms'])]) + '</tr>' for g in summary['groups'])
    return f'''<!doctype html><html lang="zh"><meta charset="utf-8"><title>真机实验结果</title>
<style>body{{font:16px/1.6 -apple-system,sans-serif;max-width:1100px;margin:40px auto;padding:0 20px;color:#172b4d}}table{{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}}th,td{{padding:9px;border-bottom:1px solid #dbe3ee;text-align:right}}th{{background:#edf3fa}}h1{{font-size:26px}}.note{{padding:16px;background:#fff4dc}}img{{width:100%}}</style>
<h1>iPhone 16 Pro 四种计算划分实验</h1><p>批次 {html.escape(summary['batch_id'])}。正式 {summary['formal_attempts']} 次，预热 {summary['warmup_attempts']} 次；返回结果 {summary['successes']} 次，错误 {summary['errors']} 次。</p>
<p class="note">成功仅表示流水线返回结果，不代表译文正确。失败与预热未计入成功耗时。图片 04 的生成上限失败保留；图片 05 的 S3 识别文本与其他方案有差异，耗时比较包含工作量差异。仅代表本设备、本局域网与这五张图片。</p>
<table><thead><tr><th>图片</th><th>方案</th><th>成功/次数</th><th>成功均值 ms</th><th>成功中位数 ms</th><th>样本标准差 ms</th><th>成功上传 body B</th><th>失败均值 ms</th></tr></thead><tbody>{rows}</tbody></table>
<p>01 禁止拍照；02 门禁告示；03 草坪告示；04 球场规则；05 酒店须知。</p>
<p>本次测量不含读图、模型准备、健康检查、日志、界面显示或轮次间隔；不含能耗测量。HTTP 请求体大小不等于链路总流量。</p></html>'''


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    summary = summarize(args.directory)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    (args.output / 'results.html').write_text(render_html(summary), encoding='utf-8')
    print(json.dumps({k: summary[k] for k in ['batch_id', 'formal_attempts', 'warmup_attempts', 'successes', 'errors']}, ensure_ascii=False))
