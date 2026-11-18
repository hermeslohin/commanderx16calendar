#!/usr/bin/env python3
"""shot2png.py SHOT.BIN out.png: VERA 640x240 4bpp bitmap (vid.p8 palette) -> PNG, 2x vertical."""
import struct, sys, zlib
LO = [0x00,0xff,0x00,0xfe,0x4c,0xc5,0x0a,0xe7,0x85,0x40,0x77,0x33,0x77,0xf6,0x8f,0xbb]
HI = [0x0,0xf,0x8,0xa,0xc,0x0,0x0,0xe,0xd,0x6,0xf,0x3,0x7,0x8,0x0,0xb]
pal = [((h & 15) * 17, (l >> 4) * 17, (l & 15) * 17) for l, h in zip(LO, HI)]
data = open(sys.argv[1], "rb").read()[:76800]
rows = []
for y in range(240):
    line = bytearray([0])
    for b in data[y*320:(y+1)*320]:
        line += bytes(pal[b >> 4]) + bytes(pal[b & 15])
    rows += [bytes(line)] * 2
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 640, 480, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")
open(sys.argv[2], "wb").write(png)
