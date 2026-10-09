"""Derive the 'bands' PBR set: tile_white with its 10 tile rows tinted W C C W Y Y W B B W (coral, sun yellow,
lagoon blue), reusing tile_white's normal/rough maps. Mapped by explicit mesh UVs (v 0..1 = one band block).
  python tools/level2_blender/make_bands.py"""
import shutil
import numpy as np
from PIL import Image
PBR = "G:/Blender/Level2_Pool/textures/pbr/"
ROWS = "WCCWYYWBBW"
TINT = {"W": (255, 255, 255), "C": (250, 92, 66), "Y": (255, 196, 28), "B": (22, 138, 222)}  # kit.PALETTE bands

a = np.asarray(Image.open(PBR + "tile_white_albedo.png").convert("RGB"), float)
h = a.shape[0]
out = a.copy()
for i, k in enumerate(ROWS):           # image row 0 is the TOP; v=1 is the top in Roblox/Blender UV space
    out[i * h // 10:(i + 1) * h // 10] *= np.array(TINT[k]) / 255
Image.fromarray(out.clip(0, 255).round().astype(np.uint8)).save(PBR + "bands_albedo.png")
for kind in ("normal", "rough", "height"):
    shutil.copy(PBR + f"tile_white_{kind}.png", PBR + f"bands_{kind}.png")
assert Image.open(PBR + "bands_albedo.png").size == (1024, 1024)
print("bands ok")
