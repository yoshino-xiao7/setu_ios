"""Build the indexed counterpart of the synthetic VBR seek fixture (no dependencies)."""
from pathlib import Path
import struct
root = Path(__file__).resolve().parents[1] / "Tests/SetuIOSAppTests/Fixtures"
data = bytearray((root / "seek-markers-vbr.mp3").read_bytes())
offsets = []
position = 0
bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
while position < len(data):
    header = int.from_bytes(data[position:position + 4], "big")
    assert header >> 21 == 0x7ff and (header >> 19) & 3 == 3
    rate = [44100, 48000, 32000][(header >> 10) & 3]
    size = 144000 * bitrates[(header >> 12) & 15] // rate + ((header >> 9) & 1)
    offsets.append(position)
    position += size
assert position == len(data)
# The first frame becomes a metadata frame; all following synthetic audio is retained.
xing = 4 + 17
index = b"Xing" + struct.pack(">III", 7, len(offsets) - 1, len(data))
toc = bytes([0] + [min(255, offsets[min(len(offsets) - 1, 1 + (len(offsets) - 1) * i // 100)] * 256 // len(data)) for i in range(1, 100)])
data[xing:xing + len(index) + len(toc)] = index + toc
(root / "seek-markers-indexed.mp3").write_bytes(data)
