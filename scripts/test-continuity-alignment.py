#!/usr/bin/env python3
"""Ensure the audio measurement gate rejects drift, repeated audio and silent captures."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import numpy as np
import soundfile as sf

rate = 44100
rng = np.random.default_rng(20260907)
reference = rng.normal(0, 0.05, rate * 7).astype('float32')
with tempfile.TemporaryDirectory(prefix='continuity-alignment-') as temporary:
    folder = Path(temporary)
    sf.write(folder / 'reference.wav', reference, rate, subtype='FLOAT')
    cases = [
        ('aligned', reference[rate * 2:rate * 4], 4000, 'pass'),
        ('wrong_sound', reference[rate * 3:rate * 5], 4000, 'fail'),
        ('repeated_sound', np.tile(reference[rate * 2:rate * 3], 2), 4000, 'fail'),
        ('frozen_progress', reference[rate * 2:rate * 4], 2000, 'fail'),
        ('silence', np.zeros(rate * 2, dtype='float32'), 4000, 'inconclusive'),
    ]
    for name, capture, reported, expected in cases:
        capture.astype('<f4').tofile(folder / 'capture.f32')
        (folder / 'av-continuity-pcm.json').write_text(json.dumps([{
            'targetMs': 2000, 'reportedMs': reported, 'sampleRate': rate, 'file': 'capture.f32'}]))
        process = subprocess.run([sys.executable, str(Path(__file__).with_name('align-continuity-pcm.py')),
            str(folder / 'reference.wav'), str(folder)], capture_output=True, text=True)
        result = json.loads(process.stdout)['results'][0]
        assert result['status'] == expected, (name, result, process.stderr)
        assert process.returncode == (0 if expected == 'pass' else 1), (name, process.returncode)
        print(f'{name}: {expected}')
