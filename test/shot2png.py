#!/usr/bin/env python3
"""shot2png.py SHOT.BIN out.png: VERA 640x240 4bpp bitmap (vid.p8 Sunset palette; no sprites) -> PNG, 2x vertical."""
import struct, sys, zlib
LO = [0x13,0xed,0x48,0xdd,0x8f,0xb4,0x6e,0xd4,0x93,0x52,0x9b,0x26,0x59,0xfa,0xcf,0xbf]
HI = [0x2,0xf,0xf,0x4,0x9,0x4,0x3,0xf,0xf,0xa,0xf,0x3,0x6,0xb,0x8,0xc]
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
