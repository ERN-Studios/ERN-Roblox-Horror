#!/usr/bin/env python3
"""Build Vesper Cathedral's original 4 x 4 texture atlas with no dependencies.

Indices are column + 4 * row_from_bottom, matching Blender UV coordinates.
Each 256 px tile has an extruded 12 px border; map faces inside safe_uv.
Run: python3 tools/build_cathedral_palette.py
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import random
import struct
import zlib


SEED = 28092026
SIZE = 1024
TILE = 256
PADDING = 12
CORE = TILE - 2 * PADDING
OUT = Path(__file__).resolve().parents[1] / "assets/maps/vesper-cathedral/textures"
PALETTE = [
    ("warm_limestone", (163, 145, 117), 0.83),
    ("pale_edge_stone", (205, 188, 153), 0.83),
    ("aged_stone", (93, 91, 78), 0.88),
    ("flagstone_floor", (142, 130, 110), 0.86),
    ("teal_slate", (32, 66, 66), 0.68),
    ("walnut_wood", (65, 43, 31), 0.80),
    ("antique_gold", (170, 125, 52), 0.35),
    ("wine_fabric", (83, 21, 32), 0.92),
    ("cyan_glass", (33, 151, 176), 0.20),
    ("amber_glass", (232, 147, 38), 0.20),
    ("ruby_glass", (155, 40, 58), 0.20),
    ("blue_glass", (44, 83, 167), 0.20),
    ("dark_iron", (29, 33, 34), 0.50),
    ("courtyard_grass", (71, 87, 54), 0.96),
    ("candle_wax", (224, 204, 158), 0.50),
    ("dark_basalt", (58, 63, 60), 0.89),
]


def clamp(value, low=0, high=255):
    return max(low, min(high, value))


def noise_lattice(rng, step):
    count = math.ceil(CORE / step) + 2
    return step, [[rng.uniform(-1.0, 1.0) for _ in range(count)] for _ in range(count)]


def smooth_noise(lattice, x, y):
    step, values = lattice
    a, b = x / step, y / step
    ix, iy = int(a), int(b)
    fx, fy = a - ix, b - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    upper = values[iy][ix] * (1 - fx) + values[iy][ix + 1] * fx
    lower = values[iy + 1][ix] * (1 - fx) + values[iy + 1][ix + 1] * fx
    return upper * (1 - fy) + lower * fy


def write_png(path, pixels, channels):
    """Small RGB/grayscale PNG encoder; deterministic, lossless, no metadata."""
    height, width = len(pixels), len(pixels[0]) // channels
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    raw = b"".join(b"\0" + bytes(row) for row in pixels)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2 if channels == 3 else 0, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def build_tile(index):
    _, color, roughness = PALETTE[index]
    rng = random.Random(SEED + index * 997)
    lattices = [noise_lattice(rng, step) for step in (63, 23, 7, 2)]
    pixels, rough = [], []
    for y in range(CORE):
        pixel_row, rough_row = [], []
        for x in range(CORE):
            large, medium, fine, grain = [smooth_noise(lattice, x, y) for lattice in lattices]
            speckle = rng.uniform(-1, 1)
            tint = (0.0, 0.0, 0.0)
            variation = 4.5 * large + 2.2 * medium + 1.6 * fine + 0.7 * grain
            if index in (0, 1, 2, 3, 15):
                # Soft clouded mineral variation with tiny worn inclusions.
                variation += -3.4 if grain < -0.68 else (2.3 if grain > 0.75 else 0)
                variation += speckle * 0.6
                tint = (medium * 1.0, medium * 0.5, -medium * 0.6)
                if index == 3:
                    # Worn flagstone joints are narrow and restrained.
                    row = y // 77
                    sx = (x + (row % 2) * 57) % 116
                    sy = y % 77
                    joint = min(sx, 116 - sx, sy, 77 - sy)
                    variation -= 5.0 * max(0, 1 - joint / 1.7)
                if index == 15:
                    variation *= 0.65
            elif index == 4:
                # Suggest staggered small slate courses without painted black seams.
                row = y // 58
                sx, sy = (x + row % 2 * 29) % 58, y % 58
                variation = 3 * large + 2 * medium + fine
                variation += 2.0 * math.sin(sy / 58 * math.pi)
                variation -= 3.0 * max(0, 1 - min(sx, 58 - sx) / 1.4)
                variation -= 4.0 * max(0, 1 - sy / 2.0)
                tint = (-0.2 * large, 1.5 * large, 1.2 * large)
            elif index == 5:
                wave = x * 0.32 + 2 * math.sin(y * 0.028) + large * 1.5
                variation = 3 * large + 2 * math.sin(wave) + 0.8 * math.sin(wave * 3.7) + grain * 0.8
                tint = (medium * 1.5, 0, -medium * 0.5)
            elif index == 6:
                variation = 3.0 * large + 1.7 * medium + 0.35 * math.sin(y * 1.7)
                # Rare patina gives antique brass a quiet hand-worked finish.
                patina = max(0, -large - 0.36) * 8
                tint = (-patina, patina * 0.1, patina * 0.4)
            elif index == 7:
                weave = 0.7 * math.sin(x * math.pi) + 0.8 * math.cos(y * math.pi)
                variation = 2.6 * large + medium + weave + grain * 0.5
            elif index in (8, 9, 10, 11):
                # Hand-blown jewel glass: swirls, no fixed lead pattern.
                variation = 6 * large + 2.5 * medium + 0.55 * fine
                variation += 1.8 * math.sin(x * 0.053 + y * 0.017 + medium * 3)
            elif index == 12:
                variation = 1.6 * large + medium + grain * 0.5
            elif index == 13:
                blades = math.sin(x * 1.9 + 0.3 * y) * math.sin(y * 0.16)
                variation = 4.5 * large + 2 * medium + 2 * fine + blades * 1.2
                tint = (-medium * 1.1, medium * 1.5, -medium * 0.4)
            elif index == 14:
                variation = 2 * large + medium * 0.7 + fine * 0.25
            pixel_row.extend(round(clamp(channel + variation + tint[i])) for i, channel in enumerate(color))
            rough_row.append(round(clamp(roughness * 255 + medium * 2.4 + grain * 1.3)))
        pixels.append(pixel_row)
        rough.append(rough_row)
    return pixels, rough


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    pixels = [bytearray(SIZE * 3) for _ in range(SIZE)]
    roughness_pixels = [bytearray(SIZE) for _ in range(SIZE)]
    tiles = []
    for index, (name, color, roughness) in enumerate(PALETTE):
        core_rgb, core_rough = build_tile(index)
        column, row_bottom = index % 4, index // 4
        origin_x, origin_y = column * TILE, (3 - row_bottom) * TILE
        for y in range(TILE):
            core_y = clamp(y - PADDING, 0, CORE - 1)
            for x in range(TILE):
                core_x = clamp(x - PADDING, 0, CORE - 1)
                target = (origin_x + x) * 3
                source = core_x * 3
                pixels[origin_y + y][target:target + 3] = bytes(core_rgb[core_y][source:source + 3])
                roughness_pixels[origin_y + y][origin_x + x] = core_rough[core_y][core_x]
        tiles.append({
            "index": index, "name": name, "base_rgb_srgb": color,
            "roughness": roughness, "column": column, "row_from_bottom": row_bottom,
            "pixel_rect_top_left": [origin_x, origin_y, TILE, TILE],
            "safe_uv": {
                "min": [(column * TILE + PADDING + 0.5) / SIZE, (row_bottom * TILE + PADDING + 0.5) / SIZE],
                "max": [((column + 1) * TILE - PADDING - 0.5) / SIZE, ((row_bottom + 1) * TILE - PADDING - 0.5) / SIZE],
            },
        })
    color_path = OUT / "VesperCathedral_BaseColor.png"
    rough_path = OUT / "VesperCathedral_Roughness.png"
    write_png(color_path, pixels, 3)
    write_png(rough_path, roughness_pixels, 1)
    metadata = {
        "name": "Vesper Cathedral original material atlas",
        "version": 1, "generator": "tools/build_cathedral_palette.py", "seed": SEED,
        "copyright": "Original procedural textures created for the Vesper Cathedral project, 2026. No third-party image inputs.",
        "size": [SIZE, SIZE], "grid": [4, 4], "tile_size": TILE,
        "padding_pixels": PADDING,
        "index_convention": "index = column + 4 * row_from_bottom; Blender UV origin at bottom left",
        "sampling": "Map individual faces within safe_uv; padding is extruded, not blank. Atlas must not repeat outside its tiles.",
        "base_color_space": "sRGB", "roughness_color_space": "Non-Color / linear",
        "normal_map": None,
        "files": {
            color_path.name: {"sha256": hashlib.sha256(color_path.read_bytes()).hexdigest(), "channels": "RGB"},
            rough_path.name: {"sha256": hashlib.sha256(rough_path.read_bytes()).hexdigest(), "channels": "grayscale"},
        },
        "tiles": tiles,
    }
    (OUT / "atlas.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"output": str(OUT), "files": metadata["files"]}, indent=2))


if __name__ == "__main__":
    main()
