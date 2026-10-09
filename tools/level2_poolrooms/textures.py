"""Poolrooms tile textures: crop the Codex sources grout-centre to grout-centre (8 x 8 tiles, seamless), make
1024 px PBR sets with Level 4's make_pbr, write G:/Blender/Level2_Poolrooms/textures/pbr/<set>_*.png.
  python tools/level2_poolrooms/textures.py"""
import os, sys
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "level4_blender"))
from make_pbr import make_pbr

SRC = "G:/Roblox/_local/l2rework/imagegen/"
OUT = "G:/Blender/Level2_Poolrooms/textures/pbr"
# set: (source, crop x0, x1, y0, y1 at grout centres measured with a grout-profile scan, make_pbr options)
SETS = {
    "pr_tile":  ("pr_tile_wall.png", 124.5, 1128.5, 126.5, 1129.0, dict(strength=6, rough_base=.16, rough_var=.40)),
    "pr_aqua":  ("pr_tile_floor.png", 125.5, 1127.5, 125.5, 1127.5, dict(strength=6, rough_base=.14, rough_var=.38)),
    "pr_worn":  ("pr_tile_cracked.png", 126.0, 1126.0, 130.0, 1126.0, dict(strength=6, rough_base=.30, rough_var=.35)),
}
os.makedirs(OUT, exist_ok=True)
for name, (src, x0, x1, y0, y1, opts) in SETS.items():
    path = os.path.join(OUT, "_" + name + "_src.png")
    Image.open(SRC + src).convert("RGB").crop((x0, y0, x1, y1)).resize((1024, 1024), Image.LANCZOS).save(path)
    make_pbr(path, OUT, name=name, size=1024, **opts)
    print(name, "ok")
