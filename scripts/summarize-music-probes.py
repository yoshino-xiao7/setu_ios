#!/usr/bin/env python3
"""Summarize explicit probe observations; never call timestamps audio validation."""
import argparse
import json
from pathlib import Path


def summarize(events):
    first = lambda name: next((e for e in events if e.get('event') == name), None)
    click, load, source = first('click'), first('engineLoad'), first('source')
    playing = next((e for e in events if e.get('event') == 'playback' and e.get('state') == 'playing'), None)
    if not click:
        return {'status': 'not_started', 'events': events}
    difference = lambda end, start: int(end['elapsedMs']) - int(start['elapsedMs']) if end and start else None
    states = [e['state'] for e in events if e.get('event') == 'playback']
    stalls = sum(state == 'buffering' and previous != 'buffering' for previous, state in zip(['idle'] + states, states))
    return {
        'route': click['route'], 'source': source,
        'clickToPlayingMs': difference(playing, click),
        'loadToPlayingMs': difference(playing, load),
        'bufferingEntriesIncludingStartup': stalls,
        'failures': [e for e in events if e.get('event') in ('failed', 'searchFailed', 'searchSectionFailed')] + next(([e] for e in events if e.get('state') == 'failed'), []),
        'seekEvents': [e for e in events if e.get('event', '').startswith('seek')],
        'actualAudioAccuracyVerified': False,
        'status': 'observed_playing' if playing else 'no_playing_observation',
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+', type=Path)
    args = parser.parse_args()
    print(json.dumps([{'file': str(p), **summarize(json.loads(p.read_text()))} for p in args.files], ensure_ascii=False, indent=2))
