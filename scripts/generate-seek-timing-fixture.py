"""Regenerate synthetic MP3 seek markers with Python 3 and lameenc==1.8.4.

The fixture contains generated tones/noise, not music recordings. Variable frame
sizes without a seek index expose approximate time-to-byte-offset lookup.
"""
from pathlib import Path
import array
import math
import random

import lameenc

SAMPLE_RATE = 44_100
output = Path(__file__).resolve().parents[1] / "Tests/SetuIOSAppTests/Fixtures/seek-markers-vbr.mp3"
rng = random.Random(7)
encoder = lameenc.Encoder()
encoder.set_channels(1)
encoder.set_in_sample_rate(SAMPLE_RATE)
encoder.set_quality(2)
encoder.set_vbr(lameenc.VBR_MTRH)
encoder.set_vbr_quality(2)

with output.open("wb") as stream:
    for second in range(40):
        frequency = 200 + 40 * (second // 5)
        samples = array.array("h", (
            int(13_000 * math.sin(2 * math.pi * frequency * (index / SAMPLE_RATE))
                + (rng.uniform(-7_000, 7_000) if second < 10 or second >= 30 else 0))
            for index in range(SAMPLE_RATE)
        ))
        stream.write(encoder.encode(samples.tobytes()))
    stream.write(encoder.flush())
