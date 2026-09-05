"""Check exported xcresult metrics; execution success alone is not M-9 acceptance."""
import json
import sys

raw = json.load(open(sys.argv[1]))
metrics = [m for case in raw for run in case.get('testRuns', []) for m in run.get('metrics', [])]
values = {m['identifier'].split('Scroll_DraggingAndDeceleration.')[-1]: m['measurements'] for m in metrics}
hitches = values.get('animation.hitch.number', [])
frames = values.get('animation.frame.count', [])
result = 'FAIL' if any(x > 0 for x in hitches) else ('UNVERIFIED' if not hitches or not frames or any(x <= 0 for x in frames) else 'PASS')
print(json.dumps({'result': result, 'metrics': values}, indent=2))
sys.exit(0 if result == 'PASS' else 1)
