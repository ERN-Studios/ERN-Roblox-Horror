"""Build reproducible PBR maps for the Level 6 Blender revision.

The six archived color images are copied unchanged. All new height fields are
authored from periodic physical surface detail, independent of printed colors.
"""

from __future__ import annotations

import hashlib
import io
import json
import os
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "artifacts/level6-textures-20260930/reference-textures"
TASK = ROOT / "artifacts/level6-blender-revision-20260930"
OUT = TASK / "materials"
N = 1024
SEED = 60930

ARCHIVED = {
    "carpet_default": ("party-carpet.png", 28, 0.015, "carpet"),
    "carpet_neon": ("party-carpet-neon-v1.png", 22, 0.015, "carpet"),
    "carpet_red": ("party-carpet-red-v1.png", 30, 0.015, "carpet"),
    "carpet_city": ("city-play-carpet.png", 52, 0.015, "carpet"),
    "wallpaper": ("pastel-wallpaper.png", 18, 0.006, "paper"),
    "orange_wall": ("orange-wall-worn-v1.png", 22, 0.012, "plaster"),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def smoothstep(lo: float, hi: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def periodic_noise(rng: np.random.Generator, cells: int | tuple[int, int]) -> np.ndarray:
    """Smooth, exactly periodic value noise on the square UV torus."""
    cy, cx = (cells, cells) if isinstance(cells, int) else cells
    lattice = rng.standard_normal((cy, cx)).astype(np.float32)
    py = np.arange(N, dtype=np.float32) * (cy / N)
    px = np.arange(N, dtype=np.float32) * (cx / N)
    iy = np.floor(py).astype(np.int32)
    ix = np.floor(px).astype(np.int32)
    ty = py - iy
    tx = px - ix
    ty = ty * ty * (3.0 - 2.0 * ty)
    tx = tx * tx * (3.0 - 2.0 * tx)
    y0 = iy % cy
    y1 = (iy + 1) % cy
    x0 = ix % cx
    x1 = (ix + 1) % cx
    a = lattice[y0[:, None], x0[None, :]]
    b = lattice[y0[:, None], x1[None, :]]
    c = lattice[y1[:, None], x0[None, :]]
    d = lattice[y1[:, None], x1[None, :]]
    top = a + (b - a) * tx[None, :]
    bottom = c + (d - c) * tx[None, :]
    field = top + (bottom - top) * ty[:, None]
    return field.astype(np.float32)


def fine_surface(rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    broad = periodic_noise(rng, 32)
    mid = periodic_noise(rng, 128)
    fine = periodic_noise(rng, 384)
    return broad, 0.28 * broad + 0.38 * mid + 0.34 * fine


def carpet_maps(rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    broad, fibers = fine_surface(rng)
    strands = 0.5 * periodic_noise(rng, (512, 128)) + 0.5 * periodic_noise(rng, (128, 512))
    # Tuft clumps and minute pile texture only: printed designs never enter height.
    height = np.clip(0.50 + 0.060 * fibers + 0.105 * strands + 0.010 * broad, 0, 1)
    roughness = np.clip(0.945 + 0.022 * broad + 0.010 * strands, 0.86, 1)
    return height, roughness


def paper_maps(rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    broad, grain = fine_surface(rng)
    height = np.clip(0.50 + 0.072 * grain, 0, 1)
    roughness = np.clip(0.905 + 0.020 * broad + 0.012 * grain, 0.82, 0.98)
    return height, roughness


def plaster_maps(rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    broad, grit = fine_surface(rng)
    mottling = periodic_noise(rng, 12)
    height = np.clip(0.50 + 0.075 * grit + 0.023 * mottling, 0, 1)
    roughness = np.clip(0.875 + 0.025 * broad + 0.020 * mottling, 0.78, 0.98)
    return height, roughness


def diamondplate_maps(rng: np.random.Generator) -> dict[str, np.ndarray]:
    yy, xx = np.indices((N, N), dtype=np.float32)
    count = 32  # 32 tread cells across 8 studs: a 0.25-stud physical pitch.
    cell = N / count
    ix = np.floor(xx / cell).astype(np.int16)
    iy = np.floor(yy / cell).astype(np.int16)
    u = ((xx + 0.5) / cell) % 1.0 - 0.5
    v = ((yy + 0.5) / cell) % 1.0 - 0.5
    handed = np.where((ix + iy) % 2 == 0, 1.0, -1.0)
    along = (u + handed * v) * 0.70710678
    across = (v - handed * u) * 0.70710678
    # A rounded, raised diagonal lozenge, with a worn crown but no mesh displacement.
    end = np.maximum(np.abs(along) - 0.245, 0.0)
    distance = np.hypot(end, across)
    tread = 1.0 - smoothstep(0.063, 0.115, distance)
    broad = periodic_noise(rng, 14)
    grain = periodic_noise(rng, 256)
    scuffs = periodic_noise(rng, 128)
    bare = tread * smoothstep(-0.30, 0.65, scuffs + 0.35 * broad)
    height = np.clip(0.25 + 0.65 * tread + 0.014 * grain + 0.012 * broad, 0, 1)
    base = np.stack(
        (68.5 + 14.0 * tread, 69.5 + 13.0 * tread, 64.5 + 13.0 * tread),
        axis=-1,
    )
    # Faint scratches and exposed steel stay near the Exit's RGB (70, 71, 66).
    color = np.clip(base + (2.2 * broad + 1.6 * grain)[..., None] + 3.0 * bare[..., None], 0, 255)
    roughness = np.clip(0.76 - 0.16 * bare + 0.035 * broad + 0.018 * grain, 0.48, 0.91)
    metalness = np.clip(0.06 + 0.85 * bare, 0, 1)
    return {"color": color, "height": height, "roughness": roughness, "metalness": metalness}


def kitchen_maps(rng: np.random.Generator) -> dict[str, np.ndarray]:
    yy, xx = np.indices((N, N), dtype=np.float32)
    count = 8  # One worn 0.28-metre ceramic tile per stud, 8 studs per repeat.
    cell = N / count
    ix = np.floor(xx / cell).astype(np.int16)
    iy = np.floor(yy / cell).astype(np.int16)
    u = ((xx + 0.5) / cell) % 1.0
    v = ((yy + 0.5) / cell) % 1.0
    edge_px = np.minimum.reduce((u, 1 - u, v, 1 - v)) * cell
    tile = smoothstep(2.1, 5.8, edge_px)
    center = np.clip(edge_px / (cell * 0.5), 0, 1)
    ivory = ((ix + iy) % 2 == 0)[..., None]
    ivory_rgb = np.array([183.0, 174.0, 149.0], dtype=np.float32)
    sage_rgb = np.array([120.0, 133.0, 111.0], dtype=np.float32)
    grout_rgb = np.array([103.0, 101.0, 87.0], dtype=np.float32)
    broad = periodic_noise(rng, 32)
    small = periodic_noise(rng, 256)
    fleck = periodic_noise(rng, 512)
    worn = 2.5 * broad + 1.0 * small + 0.7 * fleck
    stains = smoothstep(0.45, 1.15, periodic_noise(rng, 64)) * 7.0
    edge_dirt = (1.0 - smoothstep(3.0, 15.0, edge_px)) * (2.0 + 1.5 * broad)
    ceramic = np.where(ivory, ivory_rgb, sage_rgb) + (worn - stains - edge_dirt)[..., None]
    color = np.clip(ceramic * tile[..., None] + grout_rgb * (1 - tile[..., None]), 0, 255)
    height = np.clip(0.13 + 0.51 * tile + 0.023 * center * tile + 0.012 * small * tile, 0, 1)
    roughness = np.clip(0.985 * (1 - tile) + (0.79 + 0.026 * broad + 0.015 * small) * tile, 0.70, 1)
    return {"color": color, "height": height, "roughness": roughness}


def normal_opengl(height: np.ndarray, distance_studs: float, repeat_studs: float) -> np.ndarray:
    scale = distance_studs * N / repeat_studs
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * (0.5 * scale)
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * (0.5 * scale)
    # Pixel rows run downward, while UV +Y and OpenGL's green tangent run upward.
    normal = np.stack((-dx, dy, np.ones_like(dx)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    return normal


def save_map(path: Path, array: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.uint8(np.rint(np.clip(array, 0, 1) * 255.0))
    stream = io.BytesIO()
    Image.fromarray(data, "RGB" if data.ndim == 3 else "L").save(stream, format="PNG", optimize=True)
    replace_bytes(path, stream.getvalue())


def replace_bytes(path: Path, contents: bytes) -> None:
    """Copy a complete temporary file over an existing generated output."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.stem}-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(contents)
        subprocess.run(["cp", "-f", temporary, str(path)], check=True)
    finally:
        subprocess.run(["rm", "-f", temporary], check=True)


def relative(path: Path) -> str:
    return path.relative_to(TASK).as_posix()


def seam_metrics(array: np.ndarray) -> dict[str, float]:
    data = array.astype(np.float32)
    across = float(np.abs(data[:, 0] - data[:, -1]).mean())
    down = float(np.abs(data[0] - data[-1]).mean())
    interior = float(
        (np.abs(data[:, 1:] - data[:, :-1]).mean() + np.abs(data[1:] - data[:-1]).mean()) / 2
    )
    return {
        "horizontalWrapMeanAbs": round(across, 5),
        "verticalWrapMeanAbs": round(down, 5),
        "interiorAdjacentMeanAbs": round(interior, 5),
        "worstWrapToInteriorRatio": round(max(across, down) / max(interior, 1e-8), 4),
    }


def add_material(
    manifest: dict,
    name: str,
    repeat: float,
    bump: float,
    arrays: dict[str, np.ndarray],
    source_path: Path | None = None,
) -> None:
    folder = OUT / name
    folder.mkdir(parents=True, exist_ok=True)
    record: dict = {
        "physicalRepeatStuds": repeat,
        "bumpDistanceStuds": bump,
        "mapResolution": [N, N],
        "maps": {},
        "sha256": {},
        "seamValidation": {},
    }
    if source_path is not None:
        original = folder / "source-color-original.png"
        if not original.exists() or sha256(original) != sha256(source_path):
            replace_bytes(original, source_path.read_bytes())
        if sha256(original) != sha256(source_path):
            raise AssertionError(f"Archived color changed: {source_path.name}")
        record["sourceColor"] = relative(original)
        record["sha256"]["sourceColor"] = sha256(original)
        im = Image.open(original).convert("RGB")
        arrays["color"] = np.asarray(im.resize((N, N), Image.Resampling.LANCZOS), dtype=np.float32) / 255.0
        record["colorDerivative"] = "Lanczos 1024px resize of unchanged source; no recoloring"

    height = arrays["height"].astype(np.float32)
    tangent = normal_opengl(height, bump, repeat)
    if float(np.max(np.abs(np.linalg.norm(tangent, axis=-1) - 1))) > 1e-5:
        raise AssertionError(f"Unnormalized generated normals: {name}")
    arrays["normalOpenGL"] = tangent * 0.5 + 0.5

    for key, value in arrays.items():
        filename = {
            "color": "color-1024.png",
            "height": "height-1024.png",
            "normalOpenGL": "normal-opengl-1024.png",
            "roughness": "roughness-1024.png",
            "metalness": "metalness-1024.png",
        }[key]
        output = folder / filename
        save_map(output, value if key != "color" else value / 255.0 if float(value.max()) > 1 else value)
        record["maps"][key] = relative(output)
        record["sha256"][key] = sha256(output)
        if key != "color":
            metrics = seam_metrics(value)
            if metrics["worstWrapToInteriorRatio"] > 1.8:
                raise AssertionError(f"Visible {key} wrap risk on {name}: {metrics}")
            record["seamValidation"][key] = metrics

    height_range = float(np.percentile(height, 99) - np.percentile(height, 1))
    rough_range = float(np.percentile(arrays["roughness"], 99) - np.percentile(arrays["roughness"], 1))
    if height_range < 0.025 or rough_range < 0.006:
        raise AssertionError(f"Surface maps too flat on {name}: {height_range}, {rough_range}")
    record["heightP01ToP99"] = round(height_range, 5)
    record["roughnessP01ToP99"] = round(rough_range, 5)
    encoded_normal = np.asarray(Image.open(folder / "normal-opengl-1024.png"), dtype=np.float32) / 255.0 * 2 - 1
    record["encodedNormalMaxUnitLengthError"] = round(
        float(np.max(np.abs(np.linalg.norm(encoded_normal, axis=-1) - 1))), 6
    )
    if record["encodedNormalMaxUnitLengthError"] > 0.012:
        raise AssertionError(f"Quantized normal too far from unit length: {name}")
    manifest["materials"][name] = record


def make_contact_sheet(names: list[str]) -> Path:
    kinds = ("color", "height", "normal-opengl", "roughness")
    sheet = Image.new("RGB", (4 * 256, len(names) * 285), (238, 234, 226))
    draw = ImageDraw.Draw(sheet)
    for row, name in enumerate(names):
        for col, kind in enumerate(kinds):
            tile = Image.open(OUT / name / f"{kind}-1024.png").convert("RGB")
            sheet.paste(tile.resize((256, 256), Image.Resampling.LANCZOS), (col * 256, row * 285))
            draw.text((col * 256 + 6, row * 285 + 259), f"{name} / {kind}", fill=(20, 20, 20))
    stream = io.BytesIO()
    sheet.save(stream, format="JPEG", quality=88)
    path = OUT / "material-contact-sheet.jpg"
    replace_bytes(path, stream.getvalue())
    return path


def main() -> None:
    reference = json.loads((SOURCE / "reference-manifest.json").read_text())
    archived_hashes = {r.get("file"): r.get("sha256") for r in reference["records"]}
    manifest = {
        "schemaVersion": 1,
        "generator": "tools/level6_build/revision_materials.py",
        "seed": SEED,
        "normalConvention": "+Y OpenGL tangent space (image rows run down; green points toward increasing UV V)",
        "heightInterpretation": "Grayscale zero=low, one=high; bumpDistanceStuds is the full physical height span in Roblox studs",
        "seamInterpretation": "Generated data maps use periodic fields and wrapped central differences; archived color seams are inherited from their untouched source images",
        "liveStudioParityClaim": False,
        "materials": {},
    }
    for index, (name, (filename, repeat, bump, kind)) in enumerate(ARCHIVED.items()):
        path = SOURCE / filename
        if sha256(path) != archived_hashes[filename]:
            raise AssertionError(f"Source archive hash mismatch: {filename}")
        rng = np.random.default_rng(SEED + index)
        height, roughness = {"carpet": carpet_maps, "paper": paper_maps, "plaster": plaster_maps}[kind](rng)
        add_material(manifest, name, repeat, bump, {"height": height, "roughness": roughness}, path)

    add_material(manifest, "diamondplate", 8, 0.011, diamondplate_maps(np.random.default_rng(SEED + 100)))
    add_material(manifest, "kitchen_tile", 8, 0.018, kitchen_maps(np.random.default_rng(SEED + 101)))
    contact = make_contact_sheet(list(manifest["materials"]))
    manifest["contactSheet"] = relative(contact)
    manifest["contactSheetSha256"] = sha256(contact)
    replace_bytes(OUT / "material-manifest.json", (json.dumps(manifest, indent=2) + "\n").encode())
    print(f"Built {len(manifest['materials'])} PBR materials in {OUT}")


if __name__ == "__main__":
    main()
