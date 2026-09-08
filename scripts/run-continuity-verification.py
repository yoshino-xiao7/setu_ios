#!/usr/bin/env python3
"""Run deterministic simulator audio fixtures against an existing build-for-testing artifact.
No production service, credentials, device installation, or repository mutation is used.
"""
import argparse
import copy
import hashlib
import json
import plistlib
import shutil
import subprocess
import sys
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--xctestrun', required=True, type=Path)
parser.add_argument('--device', required=True)
parser.add_argument('--source', required=True, type=Path)
parser.add_argument('--duration', required=True, type=float)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--mode', choices=['routes', 'pcm', 'both'], default='both')
parser.add_argument('--full', action='store_true')
parser.add_argument('--mime', default='audio/mpeg')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
server_config = args.output / 'server.json'
server_config.unlink(missing_ok=True)
(args.output / 'fixture-manifest.json').write_text(json.dumps({
    'sourceSHA256': hashlib.sha256(args.source.read_bytes()).hexdigest(), 'duration': args.duration,
    'mime': args.mime, 'physicalOutputVerified': False}, indent=2))
server = subprocess.Popen([sys.executable, str(Path(__file__).with_name('serve-music-continuity.py')),
    str(args.source.resolve()), '--mime', args.mime, '--bytes-per-second', '8388608', '--config', str(server_config)])
try:
    deadline = time.monotonic() + 10
    while not server_config.exists():
        if server.poll() is not None or time.monotonic() >= deadline:
            raise RuntimeError('Fixture server failed to start')
        time.sleep(0.05)
    config = json.loads(server_config.read_text())
    original = plistlib.loads(args.xctestrun.read_bytes())
    def expand(value):
        if isinstance(value, str): return value.replace('__TESTROOT__', str(args.xctestrun.resolve().parent))
        if isinstance(value, list): return [expand(v) for v in value]
        if isinstance(value, dict): return {k: expand(v) for k, v in value.items()}
        return value
    plan = expand(copy.deepcopy(original))
    for key, target in plan.items():
        if key.startswith('__') or not isinstance(target, dict): continue
        target.setdefault('EnvironmentVariables', {}).update({
            'SETU_CONTINUITY_URL': config['url'], 'SETU_CONTINUITY_INPUT': str(args.source.resolve()),
            'SETU_CONTINUITY_DURATION': str(args.duration), 'SETU_CONTINUITY_FULL': '1' if args.full else '0'})
        target['DefaultTestExecutionTimeAllowance'] = 900
    run_file = args.output / 'fixture.xctestrun'
    run_file.write_bytes(plistlib.dumps(plan))
    cases = []
    if args.mode in ('routes', 'both'):
        cases.append(('routes', 'SetuIOSAppTests/MusicPlaybackControllerTests/testControlledSourceRoutes'))
    if args.mode in ('pcm', 'both'):
        cases.append(('pcm', 'SetuVLCIntegrationTests/VLCIndependentPlaybackTests/testAVPlayerCapturesSeekPCMForIndependentAlignment'))
    statuses = {}
    for name, case in cases:
        print(f'Running {name}: {args.source.name}', flush=True)
        with (args.output / f'{name}.log').open('w') as log:
            result = subprocess.run(['xcodebuild', 'test-without-building', '-xctestrun', str(run_file),
                '-destination', f'platform=iOS Simulator,id={args.device}', '-only-testing:' + case,
                '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never'], stdout=log, stderr=subprocess.STDOUT)
        statuses[name] = result.returncode
        container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.device,
            'icu.yukiryou.setuios', 'data'], text=True).strip()) / 'Documents'
        for pattern in ('av-continuity-*', 'continuity-routes.json'):
            for file in container.glob(pattern):
                if file.is_file(): shutil.copy2(file, args.output / file.name)
        required = args.output / ('continuity-routes.json' if name == 'routes' else 'av-continuity-pcm.json')
        if not required.exists(): statuses[name] = statuses[name] or 2
        print(f'{name} exit={statuses[name]}; evidence={args.output}', flush=True)
    (args.output / 'test-status.json').write_text(json.dumps(statuses, indent=2))
    raise SystemExit(0 if all(code == 0 for code in statuses.values()) else 1)
finally:
    server.terminate()
    try: server.wait(timeout=5)
    except subprocess.TimeoutExpired: server.kill(); server.wait()
