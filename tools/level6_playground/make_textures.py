"""Procedural texture overlays for the Level 6 playground (pure Python, no imaging libraries).

    python3 tools/level6_playground/make_textures.py

Writes RGBA PNGs to artifacts/level6-playground-20261002/textures/. They are tinted in Studio through
Texture.Color3, so the colour channels are near-white and the alpha carries the pattern.
"""
import math, random, struct, zlib
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / 'artifacts' / 'level6-playground-20261002' / 'textures'
rng = random.Random(6)


def write_png(path, size, pixel):
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            row.extend(int(max(0, min(255, round(c)))) for c in pixel(x, y))
        rows.append(bytes(row))
    raw = b''.join(rows)

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    path.write_bytes(png)


def value_noise(seed, cells):
    r = random.Random(seed)
    grid = [[r.random() for _ in range(cells + 1)] for _ in range(cells + 1)]
    for i in range(cells + 1):                      # wrap so the texture tiles
        grid[i][cells] = grid[i][0]
        grid[cells][i] = grid[0][i]

    def sample(u, v):
        x, y = u * cells, v * cells
        x0, y0 = int(x) % cells, int(y) % cells
        fx, fy = x - int(x), y - int(y)
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = grid[y0][x0] * (1 - fx) + grid[y0][x0 + 1] * fx
        b = grid[y0 + 1][x0] * (1 - fx) + grid[y0 + 1][x0 + 1] * fx
        return a * (1 - fy) + b * fy
    return sample


def net(size=256, cells=8, cord=0.11):
    """Knotted safety net: cords on a square grid, a fatter knot at every crossing."""
    step = size / cells

    def px(x, y):
        fx, fy = (x % step) / step, (y % step) / step
        dx, dy = min(fx, 1 - fx), min(fy, 1 - fy)
        on = dx < cord / 2 or dy < cord / 2
        knot = dx < cord and dy < cord
        if knot or on:
            shade = 235 if knot else 215 + 25 * math.sin(fx * 40 + fy * 40)
            return (shade, shade, shade, 255)
        return (255, 255, 255, 0)
    return px


def foam_seams(size=256):
    """Puzzle-mat interlock: dark seam with rounded teeth round the edge, faint scuffs inside."""
    teeth = 6
    scuff = value_noise(11, 8)

    def edge_offset(t):
        phase = (t * teeth) % 1.0
        return 0.035 if 0.25 < phase < 0.75 else -0.035

    def px(x, y):
        u, v = x / size, y / size
        d_left = u - edge_offset(v)
        d_bottom = v - edge_offset(u)
        d = min(d_left, d_bottom, 1 - u + edge_offset(v), 1 - v + edge_offset(u))
        if d < 0.012:
            return (20, 20, 25, 200)
        if d < 0.022:
            return (255, 255, 255, 60)
        n = scuff(u, v)
        alpha = max(0, (n - 0.55) * 260)
        return (35, 30, 30, min(alpha, 70))
    return px


def grime(size=256):
    """Blotchy dirt for walls and counters; dark, mostly transparent."""
    big, small = value_noise(21, 6), value_noise(22, 24)

    def px(x, y):
        u, v = x / size, y / size
        n = 0.65 * big(u, v) + 0.35 * small(u, v)
        drip = max(0.0, 1 - v * 1.6) * 0.25 * small(u * 3 % 1, 0.1)
        alpha = max(0, (n - 0.48) * 330) + drip * 255
        return (25, 20, 15, min(alpha, 150))
    return px


def padding(size=256):
    """Vinyl cushion seams and stitched straps, for posts, mats and padded panels."""
    def px(x, y):
        u, v = x / size, y / size
        seam = min(v % 0.25, 0.25 - v % 0.25) / 0.25
        if seam < 0.035:
            return (15, 15, 15, 170)
        stitch = seam < 0.08 and (int(u * 48) % 2 == 0)
        if stitch:
            return (240, 240, 240, 110)
        sheen = 0.5 + 0.5 * math.cos((v % 0.25) / 0.25 * math.pi * 2)
        return (255, 255, 255, 25 * sheen)
    return px


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (('net', net()), ('net_coarse', net(cells=4, cord=0.16)), ('foam_seams', foam_seams()), ('grime', grime()), ('padding', padding())):
        write_png(OUT / f'{name}.png', 256, fn)
        print('wrote', name)


if __name__ == '__main__':
    main()
