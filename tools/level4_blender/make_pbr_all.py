# Level 4 facelift: every slot's PBR set from pbr_spec.json -> G:\Blender\Level4_Cinema\textures\pbr
# (make_pbr.py does albedo/normal/rough; the spec's "metal" value becomes a constant metalness map).
#   python make_pbr_all.py                 all sets
#   python make_pbr_all.py name [name ...] only these sets (e.g. wallpaper_synth board_weathered)
import json, os, sys
import numpy as np
from PIL import Image
from make_pbr import make_pbr

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = r"G:\Blender\Level4_Cinema\textures\pbr"
os.makedirs(OUT, exist_ok=True)
spec = json.load(open(os.path.join(HERE, "pbr_spec.json")))
only = set(sys.argv[1:])
unknown = only - set(spec)
if unknown:
    sys.exit("not in pbr_spec.json: " + ", ".join(sorted(unknown)))
for name, s in spec.items():
    if name.startswith("_") or (only and name not in only):
        continue
    s = dict(s)
    src = os.path.normpath(os.path.join(HERE, s.pop("src")))
    metal = s.pop("metal", None)
    paths = make_pbr(src, OUT, name=name, **s)
    if metal is not None:
        Image.fromarray(np.full((64, 64), int(round(metal * 255)), np.uint8)).save(os.path.join(OUT, name + "_metal.png"))
    print(name, sorted(paths))
