#!/usr/bin/env python3
"""Match VLC output against sequentially decoded PCM. Requires test-only numpy."""
import argparse
import json
from pathlib import Path
import numpy as np


def locate(reference, sample):
    # Identical low-pass averaging allows small decoder phase differences.
    def reduce(values):
        return values[:len(values)//4*4].reshape(-1, 4).mean(axis=1)
    reference, sample = reduce(reference), reduce(sample)
    sample = sample - sample.mean()
    size = len(sample)
    if len(reference) < size or np.dot(sample, sample) == 0:
        raise ValueError('Insufficient or silent capture')
    fft_size = 1 << (len(reference) + size - 2).bit_length()
    dot = np.fft.irfft(np.fft.rfft(reference, fft_size) * np.conj(np.fft.rfft(sample, fft_size)), fft_size)[:len(reference)-size+1]
    cumulative = np.r_[0., np.cumsum(reference)]
    squares = np.r_[0., np.cumsum(reference * reference)]
    energy = squares[size:] - squares[:-size] - (cumulative[size:] - cumulative[:-size])**2 / size
    scores = np.abs(dot) / np.sqrt(np.maximum(energy, 1e-12) * np.dot(sample, sample))
    best = int(scores.argmax())
    # Repeated identical passages make the location ambiguous, not a passing seek.
    remaining = scores.copy()
    radius = int(0.5 * 44100 / 4)
    remaining[max(0, best-radius):best+radius+1] = 0
    return best * 4 / 44100, float(scores[best]), float(remaining.max(initial=0))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    reference = np.fromfile(args.directory / 'music-probe-reference.pcm', dtype='<i2').astype(float)
    results = []
    for event in json.loads((args.directory / 'music-probe-pcm.json').read_text()):
        sample = np.fromfile(args.directory / event['file'], dtype='<i2').astype(float)
        actual, confidence, alternative = locate(reference, sample)
        error = actual * 1000 - int(event['targetMs'])
        determined = confidence >= 0.8 and confidence - alternative >= 0.05
        results.append({**event, 'decodedMs': actual * 1000, 'errorMs': error,
                        'correlation': confidence, 'alternativeCorrelation': alternative,
                        'status': ('pass' if abs(error) <= 200 else 'fail') if determined else 'inconclusive'})
    print(json.dumps(results, indent=2))
    raise SystemExit(0 if results and all(r['status'] == 'pass' for r in results) else 1)
