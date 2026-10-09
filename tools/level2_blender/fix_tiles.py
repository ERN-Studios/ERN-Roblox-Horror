"""Make the Codex texture sources truly seamless, then write 1024 px copies.

Grid textures (tiles, mosaic, glass block) are cropped from one grout centre to another a whole number of
tiles away, so the wrap lands on a grout line. Organic textures (concrete, terrazzo, steel) get a half-offset
heal: the image is blended with itself shifted by half, using a mask that hides the original edges.
  python tools/level2_blender/fix_tiles.py <src_dir> <out_dir>
  python tools/level2_blender/fix_tiles.py --selftest
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

# name: (x0, x1, y0, y1) grout-centre crop in source pixels (measured with a grout-profile scan), or "heal"
JOBS = {"tex_tile10_white": (108.5, 1145.5, 110.5, 1145.5), "tex_mosaic5_aqua": (51, 1197, 49, 1197.5),
        "tex_mosaic5_cobalt": (50, 1197, 50, 1197), "tex_glassblock": (216, 1052, 200, 1036),
        "tex_rubber_kids": None, "tex_concrete_paint": "heal", "tex_terrazzo_cream": "heal",
        "tex_steel_brushed": "heal"}
SIZE = 1024


def heal(a):
    h, w = a.shape[:2]
    shifted = np.roll(a, (h // 2, w // 2), (0, 1))
    y, x = np.mgrid[0:h, 0:w]
    # 0 at the original edges (where the seam was), 1 in the middle; the shifted copy has its seam in the middle.
    m = np.minimum(np.minimum(x, w - 1 - x) / (w * .25), np.minimum(y, h - 1 - y) / (h * .25)).clip(0, 1)[..., None]
    return a * m + shifted * (1 - m)


def fix(src, out):
    out.mkdir(parents=True, exist_ok=True)
    for name, job in JOBS.items():
        im = Image.open(src / (name + ".png")).convert("RGB")
        if job == "heal":
            im = Image.fromarray(heal(np.asarray(im, float)).round().astype(np.uint8))
        elif job:
            im = im.crop((job[0], job[2], job[1], job[3]))
        im.resize((SIZE, SIZE), Image.LANCZOS).save(out / (name + ".png"))
        print(name, "ok")


def selftest():
    a = np.random.default_rng(1).random((64, 64, 3))
    b = heal(a)
    assert np.allclose(b[0], np.roll(a, (32, 32), (0, 1))[0]), "edge rows must come from the shifted copy"
    assert np.allclose(b[32, 32], a[32, 32]), "centre must be the original"
    print("selftest ok")


if __name__ == "__main__":
    selftest() if sys.argv[1:] == ["--selftest"] else fix(Path(sys.argv[1]), Path(sys.argv[2]))
