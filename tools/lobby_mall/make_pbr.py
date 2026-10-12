"""Normal and roughness maps for the mall lobby's surfaces, derived from the build's colour maps.

    /usr/local/bin/python3 tools/lobby_mall/make_pbr.py

build_mall.py writes a flat normal map and one grey roughness value for every surface (measured 2026-10-12: all 44
maps have zero variation), which is plastic with a picture on it. This writes real ones to
`artifacts/lobby-mall-20261011/build/textures_pbr/<key>_{normal,roughness}.png` (its own folder, so a rebuild does not
overwrite them; not in git, this script rewrites them exactly, seed 611); upload_textures.py prefers them. Height is the colour map's own pattern (grout, grain, holes, seams
sit lower where they are darker) plus a fibre or grain noise; everything wraps, so the maps tile.
The tile floors are not here: floor_tiles.py draws their three maps together and build_mall.py writes them.
"""
import json
from pathlib import Path
import numpy as np
from PIL import Image

BUILD = Path(__file__).resolve().parents[2] / 'artifacts' / 'lobby-mall-20261011' / 'build'
OUT = BUILD / 'textures_pbr'
#        pattern depth, noise depth, noise size (px), roughness base, roughness swing with brightness
RULES = {
    'plaster':         (0.20, 0.55, 2, 0.86,  0.00),
    'oak':             (1.30, 0.25, 1, 0.50, -0.18),
    'ceiling':         (2.20, 0.50, 1, 0.94,  0.00),
    'damask':          (0.90, 0.35, 1, 0.80, -0.10),
    'beige_carpet':    (0.30, 1.60, 1, 0.98,  0.00),
    'stand_carpet':    (0.60, 1.60, 1, 0.98,  0.00),
    'triangle_carpet': (0.50, 1.60, 1, 0.98,  0.00),
    'road_carpet':     (0.40, 1.50, 1, 0.98,  0.00),
    'stage_carpet':    (0.30, 1.70, 1, 0.98,  0.00),
    'small_tile':      (2.60, 0.05, 1, 0.14, -1.60),   # glazed tile, matt grout
    'pegboard':        (2.40, 0.30, 1, 0.72,  0.00),
    'puzzle_mat':      (1.80, 0.70, 2, 0.82,  0.00),
    'black_ceiling':   (1.50, 0.50, 1, 0.92,  0.00),
    'brass':           (0.30, 0.30, 3, 0.34,  0.20),
    'hazard':          (0.10, 0.40, 2, 0.58,  0.00),
}


def blur(a, n):
    for _ in range(n):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5
    return a


def main():
    OUT.mkdir(exist_ok=True)
    # the ceiling's colour map has one stain on every 2 x 2 tiles: down a 480-stud hall that is polka dots.
    # The clean quarter, four times.
    tiles = Image.open(BUILD / 'textures' / 'ceiling.png').convert('RGB')
    w, h = tiles.size
    quarter, clean = tiles.crop((0, 0, w // 2, h // 2)), Image.new('RGB', (w, h))
    for at in ((0, 0), (w // 2, 0), (0, h // 2), (w // 2, h // 2)):
        clean.paste(quarter, at)
    clean.save(OUT / 'ceiling_colour.png')
    # The sheen of a ceiling panel on the polished floor: a soft white blob with its own alpha. Roblox draws no
    # reflection of a lamp in a floor here, however smooth the roughness map makes it (seen in play 2026-10-12), so
    # the importer lays this under every lit panel.
    yy, xx = np.mgrid[:128, :128]
    falloff = np.exp(-(((xx - 63.5) / 44) ** 2 + ((yy - 63.5) / 44) ** 2) * 2.2)
    falloff[np.hypot(xx - 63.5, yy - 63.5) > 63] = 0
    blob = np.dstack([np.full((128, 128, 3), 255.0), falloff * 255])
    Image.fromarray(np.uint8(blob + 0.5), 'RGBA').save(OUT / 'sheen.png')
    materials = json.loads((BUILD / 'mall.json').read_text())['materials']
    rng = np.random.default_rng(611)
    for key, (pattern, grain, size, base, swing) in RULES.items():
        rgb = np.asarray(Image.open(BUILD / materials[key]['colour_map']).convert('RGB')).astype(np.float64) / 255
        lum = rgb @ np.array([0.299, 0.587, 0.114])
        spread = max(lum.std(), 1e-4)
        shape = np.clip((lum - lum.mean()) / (4 * spread), -1, 1)          # the picture's own pattern, -1..1
        noise = blur(rng.standard_normal(lum.shape), size)
        noise /= max(noise.std(), 1e-6) * 3
        height = blur(shape, 1) * pattern + noise * grain
        dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) / 2
        dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) / 2
        n = np.dstack((-dx * 2.2, dy * 2.2, np.ones_like(dx)))            # green up, as Roblox reads normal maps
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        Image.fromarray(np.uint8(np.clip(n * 0.5 + 0.5, 0, 1) * 255 + 0.5)).save(OUT / f'{key}_normal.png')
        rough = np.clip(base + swing * shape * 0.5 + noise * 0.03, 0.04, 1)
        Image.fromarray(np.uint8(rough * 255 + 0.5)).convert('RGB').save(OUT / f'{key}_roughness.png')
        print(f'{key:16s} normal tilt up to {np.degrees(np.arccos(n[..., 2].min())):4.1f} deg, roughness {rough.min():.2f}..{rough.max():.2f}')


if __name__ == '__main__':
    main()
