#!/usr/bin/env python3
"""Generate the app icon/logo PNGs (pure stdlib, no Pillow on this box)."""

import struct
import zlib

# 5x7 digits, 7x7 arrow pointing right.
GLYPHS = {
    "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "0": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    ">": ["......#", ".....##", "....###", "#######", "....###", ".....##", "......#"],
}
TOP = (30, 136, 229)      # #1E88E5
BOTTOM = (13, 71, 161)    # #0D47A1
INK = (255, 255, 255)


def png_chunk(tag: bytes, payload: bytes) -> bytes:
    body = tag + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_png(path: str, width: int, height: int, rows: list[bytes]) -> None:
    raw = b"".join(b"\x00" + row for row in rows)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(raw, 9))
        + png_chunk(b"IEND", b"")
    )
    with open(path, "wb") as handle:
        handle.write(png)


def rounded(x: int, y: int, width: int, height: int, radius: int) -> bool:
    corners = ((radius, radius), (width - 1 - radius, radius),
               (radius, height - 1 - radius), (width - 1 - radius, height - 1 - radius))
    for cx, cy in corners:
        if (x < radius or x > width - 1 - radius) and (y < radius or y > height - 1 - radius):
            if (x - cx) ** 2 + (y - cy) ** 2 > radius ** 2:
                return False
    return True


def draw(path: str, width: int, height: int, glyphs: list[tuple[str, int]],
         gap: int, radius: int) -> None:
    art_w = sum(len(GLYPHS[name][0]) * scale for name, scale in glyphs) + gap * (len(glyphs) - 1)
    art_h = max(len(GLYPHS[name]) * scale for name, scale in glyphs)
    left = (width - art_w) // 2

    # Per-pixel lookup: walk the glyphs, each centred vertically on its own.
    origin_x = left
    spans = []
    for name, scale in glyphs:
        rows = GLYPHS[name]
        spans.append((origin_x, (height - len(rows) * scale) // 2, scale, rows))
        origin_x += len(rows[0]) * scale + gap

    def ink(x: int, y: int) -> bool:
        for span_x, span_y, scale, rows in spans:
            if not (span_x <= x < span_x + len(rows[0]) * scale and span_y <= y < span_y + len(rows) * scale):
                continue
            row = (y - span_y) // scale
            column = (x - span_x) // scale
            return rows[row][column] == "#"
        return False

    out = []
    for y in range(height):
        mix = y / max(height - 1, 1)
        background = tuple(round(a + (b - a) * mix) for a, b in zip(TOP, BOTTOM))
        row = bytearray()
        for x in range(width):
            if radius and not rounded(x, y, width, height, radius):
                row += bytes((0, 0, 0, 0))
                continue
            colour = INK if ink(x, y) else background
            row += bytes((*colour, 255))
        out.append(bytes(row))

    write_png(path, width, height, out)
    print(f"wrote {path} ({width}x{height})")


draw("port_redirect/icon.png", 128, 128, [(">", 5), ("8", 7), ("0", 7)], gap=8, radius=20)
draw("port_redirect/logo.png", 250, 100, [(">", 7), ("8", 10), ("0", 10)], gap=12, radius=12)