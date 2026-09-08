"""Synthetic 40s chirp for measuring decoded seek error; requires lameenc==1.8.4.
Frequency = 500 + 250*t Hz, so audio frequency independently identifies media time.
"""
import array
import math
from pathlib import Path
import random
import lameenc
rate = 44100
rng = random.Random(7)
encoder = lameenc.Encoder()
encoder.set_channels(1)
encoder.set_in_sample_rate(rate)
encoder.set_quality(2)
encoder.set_vbr(lameenc.VBR_MTRH)
encoder.set_vbr_quality(2)
path = Path(__file__).resolve().parents[1] / 'Tests/SetuIOSAppTests/Fixtures/seek-chirp-vbr.mp3'
with path.open('wb') as output:
    for second in range(40):
        values = array.array('h')
        for index in range(rate):
            time = second + index / rate
            value = 14000 * math.sin(2 * math.pi * (500 * time + 125 * time * time))
            if second < 10 or second >= 30:
                value += rng.uniform(-6000, 6000)
            values.append(int(value))
        output.write(encoder.encode(values.tobytes()))
    output.write(encoder.flush())
