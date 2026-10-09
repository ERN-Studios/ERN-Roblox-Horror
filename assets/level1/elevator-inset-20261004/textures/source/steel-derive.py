"""Derive elevator-only clean satin steel PBR maps from the unchanged Imagegen source."""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[5]
OUT = HERE.parent
sys.path.insert(0, str(ROOT / "tools" / "level4_blender"))
from make_pbr import make_pbr

source = HERE / "steel-imagegen.png"
a = np.asarray(Image.open(source).convert("RGB"), dtype=np.float64)
source_mean = a.mean((0, 1))
target_rgb = np.array([187.0, 189.0, 191.0])
a = (a - source_mean) * 0.6 + target_rgb

# Matched opposite borders with a cosine feather preserve the generated interior.
# Both sides receive the same adjustment and exact first/last samples match.
for axis in (0, 1):
    band = min(64, a.shape[axis] // 8)
    b = np.moveaxis(a, axis, 0)
    for i in range(band):
        t = 0.5 * (1.0 + np.cos(np.pi * i / (band - 1)))
        left, right = b[i].copy(), b[-1-i].copy()
        mean = (left + right) * 0.5
        b[i] = left * (1-t) + mean * t
        b[-1-i] = right * (1-t) + mean * t
    a = np.moveaxis(b, 0, axis)
tiled_source = HERE / "steel-neutral-tiled.png"
Image.fromarray(np.floor(np.clip(a, 0, 255) + 0.5).astype(np.uint8)).save(tiled_source)

maps = make_pbr(str(tiled_source), str(OUT), name="steel", size=1024,
               strength=0.6, rough_base=0.38, rough_var=0.012,
               rough_min=0.35, rough_max=0.41,
               delight=True, highpass=32.0, blur=0.75, convention="opengl")
metal = OUT / "steel_metal.png"
Image.new("RGB", (1024, 1024), (204, 204, 204)).save(metal)
maps["metal"] = str(metal)

def record(path):
    p = Path(path)
    im = np.asarray(Image.open(p), dtype=np.float64)
    if im.ndim == 2:
        im = im[..., None]
    return {
        "path": p.relative_to(ROOT).as_posix(),
        "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
        "size": list(Image.open(p).size),
        "mode": Image.open(p).mode,
        "mean_channels": im.mean((0, 1)).round(5).tolist(),
        "min_channels": im.min((0, 1)).tolist(),
        "max_channels": im.max((0, 1)).tolist(),
        "border_mean_absolute_delta_xy": [
            round(float(np.abs(im[:, 0] - im[:, -1]).mean()), 5),
            round(float(np.abs(im[0] - im[-1]).mean()), 5)
        ]
    }

receipt = {
    "intent": "Elevator-only light cool gray clean brushed stainless steel",
    "source": record(source),
    "generated_source_preserved_unchanged": True,
    "normalized_intermediate": record(tiled_source),
    "derivation": {
        "script": str(Path(__file__).relative_to(ROOT).as_posix()),
        "pbr_tool": "tools/level4_blender/make_pbr.py",
        "target_rgb": target_rgb.tolist(),
        "grain_contrast_scale": 0.6,
        "edge_matching": "symmetric cosine feather 64 source pixels on both axes",
        "normal_convention": "OpenGL +Y (Roblox/Blender)",
        "normal_strength": 0.6,
        "roughness_base": 0.38,
        "roughness_variation": 0.012,
        "metalness": 0.8,
        "notes": "Micrograin normal is deliberately weak; generated high-contrast height is diagnostic only and must not be connected as displacement."
    },
    "maps": {kind: record(path) for kind, path in maps.items()},
    "uploads": [],
    "studio_changes": [],
}
(HERE / "steel-pbr.receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
print(json.dumps(receipt, indent=2))

