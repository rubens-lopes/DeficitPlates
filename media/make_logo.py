# Draws media/logo.png (400x400): a green healing cross over a nameplate bar
# that is partly empty. Standard library only. Run from the repo root.
import struct
import zlib

SIZE = 400
BG = (24, 26, 30)
GREEN = (40, 200, 90)
EMPTY = (70, 74, 82)
BLACK = (0, 0, 0)


def pixel(x, y):
    c = SIZE // 2
    cy = 170
    if (abs(x - c) < 40 and abs(y - cy) < 120) or (abs(y - cy) < 40 and abs(x - c) < 120):
        return GREEN
    if 306 <= y < 344 and 56 <= x < 344:
        if y < 310 or y >= 340 or x < 60 or x >= 340:
            return BLACK
        return GREEN if x < 250 else EMPTY
    return BG


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


rows = b"".join(
    b"\x00" + bytes(v for x in range(SIZE) for v in pixel(x, y)) for y in range(SIZE)
)
png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(rows, 9))
    + chunk(b"IEND", b"")
)
with open("media/logo.png", "wb") as f:
    f.write(png)
