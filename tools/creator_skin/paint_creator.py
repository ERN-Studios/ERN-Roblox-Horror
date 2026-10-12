"""Paint the creator skin's fabric onto the game's own hazmat suit, by position on the body.

    /usr/local/bin/python3 tools/creator_skin/paint_creator.py <suit_mesh.npz> <baseline-yellow.png> <out dir>

Run by build_creator_skin.py. Every skin is the same suit with another colour map on the same UVs
(assets/hazmat/README.md). This one is the owner's pick of 2026-10-11, "7 GOLD + CAMCORDER": a black suit with a gold
sash from the left shoulder to the right hip, front and back, and gold lenses. Nothing is generated: the suit's own
baseline map says where fabric is (it is the yellow), keeps every fold, strap, buckle and seam, and each texel is
recoloured by WHERE IT SITS ON THE BODY, read off the mesh through its UVs. So the sash is one straight band round the
body however the UV islands lie. Model space: metres, z up, the suit faces -y, its left is +x, 1.7 tall, T-pose.
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

N = 2048
SASH_TOP, SASH_HIP, SASH_WIDTH = (0.205, 1.31), (-0.275, 0.80), 0.135      # (x, z) on the front; metres
GOLD, BLACK = np.array([212, 168, 62.0]), np.array([21, 21, 23.0])     # in play 33 read as grey beside the suit's own black gear
LENS_X, LENS_Z, LENS_R = 0.062, 1.508, 0.047


def position_map(tri_pos, tri_uv):
    """World position of every texel that a triangle covers (NaN elsewhere)."""
    pos = np.full((N, N, 3), np.nan, np.float32)
    px = np.stack([tri_uv[..., 0] * N, (1 - tri_uv[..., 1]) * N], -1)       # column, row
    for p, q in zip(px, tri_pos):
        lo = np.floor(p.min(0) - 1).astype(int).clip(0, N - 1)
        hi = np.ceil(p.max(0) + 1).astype(int).clip(0, N - 1)
        xs, ys = np.meshgrid(np.arange(lo[0], hi[0] + 1) + 0.5, np.arange(lo[1], hi[1] + 1) + 0.5)
        d = (p[1, 1] - p[2, 1]) * (p[0, 0] - p[2, 0]) + (p[2, 0] - p[1, 0]) * (p[0, 1] - p[2, 1])
        if abs(d) < 1e-9:
            continue
        a = ((p[1, 1] - p[2, 1]) * (xs - p[2, 0]) + (p[2, 0] - p[1, 0]) * (ys - p[2, 1])) / d
        b = ((p[2, 1] - p[0, 1]) * (xs - p[2, 0]) + (p[0, 0] - p[2, 0]) * (ys - p[2, 1])) / d
        c = 1 - a - b
        inside = (a >= -0.02) & (b >= -0.02) & (c >= -0.02)                 # a hair over the edge: no unpainted seams
        if inside.any():
            block = pos[lo[1]:hi[1] + 1, lo[0]:hi[0] + 1]
            block[inside] = (a[..., None] * q[0] + b[..., None] * q[1] + c[..., None] * q[2])[inside]
    return pos


def blur(a, n):
    for _ in range(n):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5
    return a


def main():
    mesh, base_path, out = np.load(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    base = np.asarray(Image.open(base_path).convert('RGB').resize((N, N), Image.LANCZOS)).astype(np.float32)
    pos = position_map(mesh['tri_pos'], mesh['tri_uv'])
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    on_body = ~np.isnan(x)
    r, g, b = base[..., 0], base[..., 1], base[..., 2]
    yellow = (r > 55) & (g > 45) & (r - b > 26) & (g - b > 12)                # the baseline suit's yellow, its shaded folds too
    fabric = on_body & yellow
    lum = (0.299 * r + 0.587 * g + 0.114 * b)
    shade = np.clip(lum / max(np.median(lum[fabric]), 1), 0.5, 1.25)          # the cloth's own folds and seams
    rng = np.random.default_rng(1012)
    grain = blur(rng.standard_normal((N, N)), 2)
    grain /= grain.std()

    out_rgb = base.copy()
    cloth = yellow                                                             # and the sheet's padding round every island: no yellow may bleed in at a seam
    out_rgb[cloth] = (BLACK * shade[..., None] * (1 + 0.05 * grain[..., None]))[cloth]

    # the sash: a band about the line from the left shoulder to the right hip, the same on the front and the back
    top, hip = np.array(SASH_TOP), np.array(SASH_HIP)
    along = (hip - top) / np.linalg.norm(hip - top)
    across = np.array([along[1], -along[0]])
    off = (np.nan_to_num(x) - top[0]) * across[0] + (np.nan_to_num(z) - top[1]) * across[1]
    run = (np.nan_to_num(x) - top[0]) * along[0] + (np.nan_to_num(z) - top[1]) * along[1]
    torso = (z > 0.60) & (z < 1.335) & (np.abs(x) < np.where(z > 1.16, 0.262, 0.40))      # not the arms, not the hood
    sash = fabric & torso & (np.abs(off) < SASH_WIDTH / 2) & (run > -0.02)
    weave = 1 + 0.16 * grain + 0.05 * np.sin(run * 260)                        # a cloth-of-gold glint along the band
    out_rgb[sash] = (GOLD * shade[..., None] * weave[..., None])[sash]
    edge = fabric & torso & (np.abs(np.abs(off) - SASH_WIDTH / 2) < 0.006) & (run > -0.02)
    out_rgb[edge] = (GOLD * 0.55 * shade[..., None])[edge]                     # a stitched hem

    # the lenses: two gold mirrors, brighter toward the upper left as a lit glass is
    for side in (-1, 1):
        d = np.hypot(np.nan_to_num(x) - side * LENS_X, np.nan_to_num(z) - LENS_Z)
        lens = on_body & (y < -0.19) & (d < LENS_R)
        glow = 0.72 + 0.55 * np.clip(1 - np.hypot(np.nan_to_num(x) - side * LENS_X + 0.016, np.nan_to_num(z) - LENS_Z - 0.016) / LENS_R, 0, 1) ** 1.6
        out_rgb[lens] = (np.array([236, 184, 52.0]) * glow[..., None])[lens]

    out.mkdir(parents=True, exist_ok=True)
    image = Image.fromarray(np.uint8(np.clip(out_rgb, 0, 255) + 0.5))
    image.save(out / 'creator_gold_2048.png')
    image.resize((1024, 1024), Image.LANCZOS).save(out / 'creator_gold.png')

    # a look without a renderer: every texel dropped where it sits, seen from the front and from the back
    for name, facing in (('front', -1), ('back', 1)):
        view = np.zeros((1100, 1100, 3), np.uint8)
        depth = np.full((1100, 1100), np.inf)
        pick = on_body & (np.nan_to_num(y) * facing > -0.02)
        u = ((np.nan_to_num(x)[pick] * -facing + 0.85) / 1.7 * 1099).astype(int).clip(0, 1099)
        v = ((1.72 - z[pick]) / 1.74 * 1099).astype(int).clip(0, 1099)
        far = -y[pick] * facing
        order = np.argsort(far)
        view[v[order], u[order]] = np.uint8(np.clip(out_rgb[pick][order], 0, 255))
        Image.fromarray(view).save(out / f'splat_{name}.png')
    print(f'PAINTED fabric {fabric.mean():.3f} sash {sash.mean():.4f} of the sheet; texels on the body {on_body.mean():.3f}')


if __name__ == '__main__':
    main()
