#!/usr/bin/env python3
"""원본 Rust 시험 이름·순서와 Swift @Test 문구를 정적으로 대조한다. 빌드·시험은 실행하지 않는다."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--strict', action='store_true')
args = parser.parse_args()
project = Path(__file__).resolve().parent.parent
upstream = Path(os.environ.get('DJLINK_EXPORT_UPSTREAM_DIR', str(Path(os.environ.get('UPSTREAM_DIR', str(Path.home() / 'src/upstream'))) / 'rbxport')))
manifest = json.loads((project / 'docs/export-test-map.json').read_text())
errors = []
try:
    revision = subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != manifest['commit']:
        errors.append(f'원본 커밋 불일치: {revision}')
except (OSError, subprocess.CalledProcessError):
    errors.append(f'원본 체크아웃을 읽을 수 없음: {upstream}')
counts = {}
seen = set()
for item in manifest['tests']:
    source = upstream / 'crates' / item['source']
    target = project / 'Tests' / item['swift']
    try:
        original = re.findall(r'#\[(?:tokio::)?test\](?:\s*#\[[^\]]*\])*\s*(?:async\s+)?fn\s+(\w+)', source.read_text())
        translated = re.findall(r'@Test\s*\(\s*"([^"\n]+)"', target.read_text())
    except OSError as error:
        errors.append(str(error))
        continue
    if original != translated:
        errors.append(f'시험 이름/순서 불일치: {item["source"]} ({len(original)} → {len(translated)})')
    counts[item['group']] = counts.get(item['group'], 0) + len(original)
    seen.add(target.resolve())
    print(f'{"일치" if original == translated else "불일치"}: {item["source"]}: {len(original)} → {len(translated)}')
regression_count = 0
for item in manifest.get('regressions', []):
    target = project / 'Tests' / item['swift']
    try:
        names = re.findall(r'@Test\s*\(\s*"([^"\n]+)"', target.read_text())
    except OSError as error:
        errors.append(str(error))
        continue
    if names != item['names']:
        errors.append(f'자체 회귀 시험 목록 불일치: {item["swift"]}')
    regression_count += len(names)
    seen.add(target.resolve())
for target in (project / 'Tests').glob('DJLinkExport*Tests/*.swift'):
    if re.search(r'@Test\(', target.read_text()) and target.resolve() not in seen:
        errors.append(f'대응표에 없는 시험 파일: {target.relative_to(project)}')
print('정적 시험 대응 합계:', ', '.join(f'{group}={count}' for group, count in counts.items()))
print('별도 실기 회귀:', regression_count)
for error in errors:
    print('오류:', error, file=sys.stderr)
if errors and args.strict:
    sys.exit(1)
