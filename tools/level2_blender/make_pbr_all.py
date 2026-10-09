"""Level 2 kit: every PBR set in pbr_spec.json -> G:/Blender/Level2_Pool/textures/pbr (reuses Level 4's make_pbr).
  python tools/level2_blender/make_pbr_all.py [name ...]"""
import json, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "level4_blender"))
from make_pbr import make_pbr

OUT = r"G:\Blender\Level2_Pool\textures\pbr"
spec = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "pbr_spec.json")))
only = set(sys.argv[1:])
for name, s in spec.items():
    if name.startswith("_") or "derived" in spec[name] or (only and name not in only):
        continue
    s = {k: v for k, v in s.items() if k not in ("src", "tile_m", "metal", "saturation")}
    src = spec[name]["src"]
    if spec[name].get("saturation", 1) != 1:          # owner 2026-10-03: more vivid colours
        hsv = np.asarray(Image.open(src).convert("RGB").convert("HSV"), np.float64)
        hsv[..., 1] = np.clip(hsv[..., 1] * spec[name]["saturation"], 0, 255)
        src = os.path.join(OUT, "_" + name + "_saturated.png")
        Image.fromarray(hsv.round().astype(np.uint8), "HSV").convert("RGB").save(src)
    make_pbr(src, OUT, name=name, **s)
    if "metal" in spec[name]:
        Image.fromarray(np.full((64, 64), round(spec[name]["metal"] * 255), np.uint8)).save(os.path.join(OUT, name + "_metal.png"))
    print(name, "ok")
