#!/usr/bin/env python3
"""Summarize one P16 cohort from anonymous signposts; never pool historical samples.

Usage: python3 summarize-playback.py output.json recording-events.json [...]
Pair each recording independently using the unchanged legacy boundary and a
completed, explicitly classified user-next interval. Historical cohorts are excluded.
"""
import json
import math
from pathlib import Path
import runpy
import statistics
import sys

HERE = Path(__file__).resolve().parent
legacy_summarize = runpy.run_path(str(HERE.parent / "summarize-signposts.py"))["summarize"]


def stats(values):
    values = sorted(values)
    return {"samples": len(values), "min_ms": min(values) if values else None,
            "p50_ms": statistics.median(values) if values else None,
            "p90_ms": values[math.ceil(len(values) * .90) - 1] if values else None,
            "p95_ms": values[math.ceil(len(values) * .95) - 1] if values else None,
            "max_ms": max(values) if values else None}


def first(events, name, value=None):
    return next((e["time_ns"] for e in events if e["name"] == name
                 and (value is None or e.get("value") == value)), None)


def delta(a, b):
    return None if a is None or b is None else (b - a) / 1e6


samples, excluded, all_events, windows = [], [], [], []
output = Path(sys.argv[1])
assert len(set(map(str, map(Path.resolve, map(Path, sys.argv[2:]))))) == len(sys.argv[2:]), "Duplicate recording input"
for source in sys.argv[2:]:
    path = Path(source)
    events = json.loads(path.read_text())
    window = path.stem
    diag = [e for e in events if e["category"] == "MusicPlaybackP01"]
    all_events.extend({**e, "recording": window} for e in diag)
    legacy = legacy_summarize(events)
    legacy_intervals = legacy["samples"] + legacy["other_complete_transitions"]
    windows.append({"recording": window, "events": len(events), "diagnostic_events": len(diag),
                    "legacy_excluded": legacy["excluded"]})
    active = {}
    for event in sorted(diag, key=lambda e: e["time_ns"]):
        identity = event["id"]
        if event["name"] == "PlaybackSegments" and event["type"] == "Begin":
            assert identity not in active, "Duplicate active diagnostic ID"
            active[identity] = [event]
        elif identity in active:
            active[identity].append(event)
            if event["name"] == "PlaybackSegments" and event["type"] == "End":
                trace = active.pop(identity)
                request = first(trace, "NextTrackRequested", 1)
                begin = first(trace, "TransitionStarted")
                playing = first(trace, "TrackPlaying")
                hit, miss = first(trace, "PreparedHit"), first(trace, "PreparedMiss")
                if request is None or playing is None or (hit is None) == (miss is None):
                    excluded.append({"recording": window, "id": identity,
                                     "reason": "not_completed_user_next_with_one_explicit_lookup_result",
                                     "event_names": [e["name"] for e in trace]})
                    continue
                assert begin is not None
                matches = [x for x in legacy_intervals if request <= x["begin_ns"] <= begin
                           and x["playing_ns"] <= playing and x["playing_ns"] >= begin]
                assert len(matches) == 1, "Legacy interval must match exactly once; no estimated pooled sample"
                old = matches[0]
                kind = "prepared_hit" if hit is not None else "prepared_miss"
                assert ("hit_ns" in old) == (kind == "prepared_hit"), "New/legacy classification mismatch"
                lookup = hit if hit is not None else miss
                ready = first(trace, "PlayerReady")
                install_end = first(trace, "ReplaceCurrentItemEnd", 1)
                measurements = {
                    "transition_to_lookup_result": delta(begin, lookup),
                    "lookup_result_to_playing": delta(lookup, playing),
                    "request_to_queue_resolved": delta(request, first(trace, "QueueResolved")),
                    "queue_lookup": delta(first(trace, "QueueLookupStarted"), first(trace, "QueueResolved")),
                    "prepared_lookup": delta(first(trace, "PreparedLookupStarted"), lookup),
                    "lookup_result_to_source_ready": delta(lookup, first(trace, "PlaybackSourceReady")),
                    "source_resolve_await": delta(first(trace, "PlaybackSourceResolveStarted"), first(trace, "PlaybackSourceReady")),
                    "item_create_or_reuse": delta(first(trace, "PlayerItemCreationStarted"), first(trace, "PlayerItemReady")),
                    "clear_old_item": delta(first(trace, "ReplaceCurrentItemBegin", 0), first(trace, "ReplaceCurrentItemEnd", 0)),
                    "install_new_item": delta(first(trace, "ReplaceCurrentItemBegin", 1), install_end),
                    "session_activation_task": delta(first(trace, "SessionActivateBegin"), first(trace, "SessionActivateEnd")),
                    "request_to_player_ready": delta(request, ready),
                    # Signed: readiness may precede installation for a prepared item.
                    "first_ready_relative_to_install_end": delta(install_end, ready),
                    "install_end_to_playing": delta(install_end, playing),
                    "ready_to_playing": delta(ready, playing),
                    "request_to_playing": delta(request, playing),
                }
                samples.append({"recording": window, "id": identity, "kind": kind,
                    "legacy_id": old["id"], "legacy_transition_ms": old["transition_ms"],
                    "legacy_begin_to_hit_ms": old.get("begin_to_hit_ms"),
                    "legacy_hit_to_playing_ms": old.get("hit_to_playing_ms"),
                    "request_ns": request, "transition_ns": begin, "playing_ns": playing,
                    "item_reused": first(trace, "PlayerItemReady", 1) is not None,
                    "session_already_ready": first(trace, "SessionGate", 1) is not None,
                    "waiting_states": sorted({e["name"] for e in trace if e["name"].startswith("Waiting")}),
                    "segments_ms": measurements, "events": trace})
    excluded.extend({"recording": window, "id": identity, "reason": "incomplete_at_recording_end",
                     "event_names": [e["name"] for e in trace]} for identity, trace in active.items())

hits = [s for s in samples if s["kind"] == "prepared_hit"]
misses = [s for s in samples if s["kind"] == "prepared_miss"]
cohorts = {kind: {
    "transition": stats([s["legacy_transition_ms"] for s in rows]),
    "segments": {key: stats([s["segments_ms"][key] for s in rows
                              if s["segments_ms"][key] is not None])
                 for key in (rows[0]["segments_ms"] if rows else [])}}
    for kind, rows in (("prepared_hit", hits), ("prepared_miss", misses))}
result = {
    "phase": "P16", "sample_count": len(hits), "minimum_samples": 20,
    "sample_gate": len(hits) >= 20,
    "percentiles": "P50 median; P90/P95 nearest rank; milliseconds",
    "boundary": "TrackTransition begin to first TrackPlaying callback; not acoustic output",
    "historical_samples_included": False,
    "cohorts": cohorts, "windows": windows,
    "samples": [{k: v for k, v in s.items() if k != "events"} for s in samples],
    "excluded": excluded}
transition = cohorts["prepared_hit"]["transition"]
result["latency_gate"] = bool(hits) and transition["p50_ms"] < 200 and transition["p90_ms"] < 400
output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
print(json.dumps({k: result[k] for k in ("sample_count", "sample_gate", "latency_gate", "cohorts")}, indent=2))
sys.exit(0 if result["sample_gate"] and result["latency_gate"] else 1)
