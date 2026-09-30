# Level 4 cinema: turns the Codex (GPT-6 Sol) texture renders into game textures.
#   <name>.png    1024 px colour map, edge-blended so it tiles
#   <name>_n.png  neutral luminance detail map (mean 0.75) that Blender/Roblox tint with the Studio colour
import glob, os, sys
import numpy as np
from PIL import Image

SRC = r"G:\Roblox\MongoTV\artifacts\level4-blender-20260930\refs"
OUT = r"G:\Blender\Level4_Cinema\textures"
os.makedirs(OUT, exist_ok=True)


def seamless(a):
    h, w = a.shape[:2]
    rolled = np.roll(np.roll(a, h // 2, 0), w // 2, 1)
    y = np.abs(np.linspace(-1, 1, h))[:, None]
    x = np.abs(np.linspace(-1, 1, w))[None, :]
    wgt = np.clip(1 - np.maximum(x, y), 0, 1) ** 0.6       # 1 in the centre, 0 at every edge
    return a * wgt[..., None] + rolled * (1 - wgt[..., None])


def sources(prefix):          # the committed JPEGs (the PNG originals live outside the repo)
    return sorted(p for p in glob.glob(os.path.join(SRC, prefix + "*.*")) if p.lower().endswith((".png", ".jpg")))


for path in sources("tex_"):
    name = os.path.splitext(os.path.basename(path))[0]
    if "." in name:
        continue
    im = Image.open(path).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    a = seamless(np.asarray(im, dtype=np.float64) / 255.0)
    Image.fromarray((a * 255).clip(0, 255).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))
    lum = a @ np.array([0.299, 0.587, 0.114])
    n = np.clip(lum / max(lum.mean(), 1e-3) * 0.75, 0, 1)
    Image.fromarray((np.stack([n] * 3, -1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_n.png"))
    print(name)
for path in sources("art_"):
    name = os.path.splitext(os.path.basename(path))[0]
    im = Image.open(path).convert("RGB")
    im.thumbnail((1024, 1024), Image.LANCZOS)
    im.save(os.path.join(OUT, name + ".png"))
    print(name)
