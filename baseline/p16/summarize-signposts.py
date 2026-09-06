#!/usr/bin/env python3
"""Summarize sanitized, single-process MusicPlayback events from xctrace exports.

Input: JSON array of {time_ns,type,id,name,category}. Output: JSON to stdout.
Only complete intervals containing PreparedItemHit and first TrackPlaying count.
This measures MainActor callbacks, never acoustic output or physical click latency.
Do not combine different recordings before pairing intervals.
"""
import json
import math
import statistics
import sys


def summarize(events):
    active = None
    samples = []
    excluded = []
    other_complete = []
    for event in sorted(events, key=lambda value: value["time_ns"]):
        # Historical exports sometimes omit category after filtering by process.
        if event.get("category") not in (None, "MusicPlayback"):
            continue
        name, kind = event["name"], event["type"]
        if name == "TrackTransition" and kind == "Begin":
            if active:
                excluded.append({**active, "reason": "superseded_or_incomplete"})
            active = {"id": event["id"], "begin_ns": event["time_ns"]}
        elif active and name == "PreparedItemHit" and kind == "Event":
            active.setdefault("hit_ns", event["time_ns"])
        elif active and name == "TrackPlaying" and kind == "Event":
            active.setdefault("playing_ns", event["time_ns"])
        elif active and name == "TrackTransition" and kind == "End" and event["id"] == active["id"]:
            if "hit_ns" in active and "playing_ns" in active and active["hit_ns"] <= active["playing_ns"]:
                samples.append({**active,
                    "transition_ms": (active["playing_ns"] - active["begin_ns"]) / 1e6,
                    "begin_to_hit_ms": (active["hit_ns"] - active["begin_ns"]) / 1e6,
                    "hit_to_playing_ms": (active["playing_ns"] - active["hit_ns"]) / 1e6})
            else:
                reason = "no_prepared_hit_observed" if "hit_ns" not in active else "no_valid_playing"
                excluded.append({**active, "end_ns": event["time_ns"], "reason": reason})
                if "playing_ns" in active:
                    other_complete.append({**active, "prepared_hit_observed": "hit_ns" in active,
                        "transition_ms": (active["playing_ns"] - active["begin_ns"]) / 1e6})
            active = None
    if active:
        excluded.append({**active, "reason": "incomplete_at_end"})
    values = sorted(sample["transition_ms"] for sample in samples)
    return {"samples": samples, "excluded": excluded,
            "other_complete_transitions": other_complete, "statistics": stats(values)}


def stats(values):
    values = sorted(values)
    return {"samples": len(values), "p50_ms": statistics.median(values) if values else None,
            **{f"p{q}_ms": values[math.ceil(len(values) * q / 100) - 1] if values else None
               for q in (90, 95, 99)},
            "max_ms": max(values) if values else None,
            "method": "p50=median; p90/p95/p99=nearest-rank"}


if __name__ == "__main__":
    with open(sys.argv[1]) as source:
        print(json.dumps(summarize(json.load(source)), indent=2))
