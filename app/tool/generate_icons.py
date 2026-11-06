#!/usr/bin/env python3
"""Draws Chapter's app icon and writes every size Android, iOS and the stores need.

Standard library only. Run from `app/`:  python tool/generate_icons.py

The mark is an open book on the app's accent colour. Replace it with a designer's
artwork when you have one: keep the same file names and nothing else changes.
"""
import json
import os
import struct
import zlib

ACCENT = (0x9A, 0x3B, 0x2E)
PAGE = (0xFA, 0xF7, 0xF2)
SHADE = (0xE2, 0xDA, 0xCD)
RIBBON = (0xE0, 0xA4, 0x58)
MASTER = 1024


def inside(poly, x, y):
    hit = False
    j = len(poly) - 1
    for i, (xi, yi) in enumerate(poly):
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


# In a 0–1 square; everything stays inside the adaptive icon's safe zone.
LEFT = [(0.50, 0.36), (0.44, 0.33), (0.34, 0.31), (0.25, 0.32), (0.25, 0.68), (0.34, 0.67), (0.44, 0.69), (0.50, 0.72)]
RIGHT = [(1 - x, y) for x, y in LEFT]
GUTTER = [(0.49, 0.36), (0.51, 0.36), (0.51, 0.72), (0.49, 0.72)]
MARK = [(0.60, 0.30), (0.67, 0.30), (0.67, 0.50), (0.635, 0.465), (0.60, 0.50)]


def colour_at(x, y, background):
    if inside(MARK, x, y):
        return RIBBON
    if inside(GUTTER, x, y):
        return SHADE
    if inside(LEFT, x, y) or inside(RIGHT, x, y):
        return PAGE
    return background


def render(size, background=ACCENT, transparent=False, samples=2):
    """Returns rows of RGBA tuples, antialiased by supersampling."""
    rows = []
    n = samples * samples
    for py in range(size):
        row = []
        for px in range(size):
            r = g = b = a = 0
            for sy in range(samples):
                for sx in range(samples):
                    x = (px + (sx + 0.5) / samples) / size
                    y = (py + (sy + 0.5) / samples) / size
                    c = colour_at(x, y, None if transparent else background)
                    if c is not None:
                        r += c[0]
                        g += c[1]
                        b += c[2]
                        a += 1
            row.append(
                (r // a, g // a, b // a, a * 255 // n) if a else (0, 0, 0, 0)
            )
        rows.append(row)
    return rows


def write_png(path, rows, alpha=True):
    height = len(rows)
    width = len(rows[0])
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for p in row:
            raw.extend(p if alpha else p[:3])

    def chunk(tag, data):
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))

    colour_type = 6 if alpha else 2
    png = (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, colour_type, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
        + chunk(b'IEND', b'')
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(png)


def feature_graphic(width=1024, height=500):
    """Play's feature graphic: the mark centred on the accent colour."""
    mark = render(height, samples=1)
    rows = []
    offset = (width - height) // 2
    for y in range(height):
        row = [(*ACCENT, 255)] * width
        row[offset:offset + height] = mark[y]
        rows.append(row)
    return rows


def main():
    res = 'android/app/src/main/res'
    for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        write_png(f'{res}/mipmap-{density}/ic_launcher.png', render(size))
    # Adaptive icon: transparent foreground over a colour background (API 26+).
    for density, size in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}.items():
        write_png(f'{res}/mipmap-{density}/ic_launcher_foreground.png', render(size, transparent=True))

    # iOS: square, no alpha. Sizes come from the project's own Contents.json.
    icon_dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    with open(f'{icon_dir}/Contents.json', encoding='utf8') as f:
        contents = json.load(f)
    done = {}
    for image in contents['images']:
        name = image.get('filename')
        if not name:
            continue
        points = float(image['size'].split('x')[0])
        size = round(points * int(image['scale'].rstrip('x')))
        if size not in done:
            done[size] = render(size)
        write_png(f'{icon_dir}/{name}', done[size], alpha=False)

    # Store assets, kept with the listing drafts.
    write_png('../docs/store/assets/icon-512.png', render(512), alpha=True)
    write_png('../docs/store/assets/feature-graphic-1024x500.png', feature_graphic(), alpha=False)


if __name__ == '__main__':
    main()
