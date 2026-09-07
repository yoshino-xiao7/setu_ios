#!/usr/bin/env python3
"""Compare AVPlayer PCM with independent sequential decoding. Test-only numpy/scipy/soundfile.
This establishes decoded content position, never physical speaker/UI synchronization.
"""
import argparse
import json
import math
import runpy
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly


def mono44100(samples, rate):
    if samples.ndim == 2:
        samples = samples.mean(axis=1)
    divisor = math.gcd(int(rate), 44100)
    return resample_poly(samples, 44100 // divisor, int(rate) // divisor) if rate != 44100 else samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('captures', type=Path)
    args = parser.parse_args()
    locate = runpy.run_path(str(Path(__file__).with_name('align-music-probe-pcm.py')))['locate']
    reference, rate = sf.read(args.reference, always_2d=True)
    reference = mono44100(reference, rate)
    # AVPlayer's tap includes decoder pre-roll before media time zero. Keep its
    # negative position explicit rather than trimming the recording or hiding error.
    pre_roll_frames = math.ceil(0.5 * 44100 / 4) * 4
    pre_roll = pre_roll_frames / 44100
    reference = np.r_[np.zeros(pre_roll_frames), reference]
    events = json.loads((args.captures / 'av-continuity-pcm.json').read_text())
    results = []
    for event in events:
        captured = np.fromfile(args.captures / event['file'], dtype='<f4').astype(float)
        normalized = mono44100(captured, event['sampleRate'])
        sample = normalized[:44100]
        if len(sample) < 22050 or not np.all(np.isfinite(sample)) or np.std(sample) < 1e-12:
            results.append({**event, 'status': 'inconclusive', 'reason': 'insufficient, silent or invalid capture'})
            continue
        position, confidence, alternative = locate(reference, sample)
        position -= pre_roll
        error = position * 1000 - event['targetMs']
        determined = confidence >= 0.8 and confidence - alternative >= 0.05
        continuation_error = None
        if len(normalized) >= 88200 and np.std(normalized[44100:88200]) >= 1e-12:
            tail, tail_confidence, tail_alternative = locate(reference, normalized[44100:88200])
            continuation_error = ((tail - pre_roll) - position - 1) * 1000
            determined = determined and tail_confidence >= 0.8 and tail_confidence - tail_alternative >= 0.05
        projection_error = event['reportedMs'] - (position + len(captured) / event['sampleRate']) * 1000
        passed = abs(error) <= 200 and continuation_error is not None and abs(continuation_error) <= 50 and abs(projection_error) <= 500
        results.append({**event, 'decodedMs': position * 1000, 'errorMs': error,
                        'correlation': confidence, 'alternativeCorrelation': alternative,
                        'continuityErrorMs': continuation_error, 'decodedBufferProjectionErrorMs': projection_error,
                        'status': ('pass' if passed else 'fail') if determined else 'inconclusive'})
    report = {'physicalOutputVerified': False, 'referencePreRollSeconds': pre_roll, 'results': results}
    print(json.dumps(report, indent=2))
    return 0 if results and all(row['status'] == 'pass' for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
