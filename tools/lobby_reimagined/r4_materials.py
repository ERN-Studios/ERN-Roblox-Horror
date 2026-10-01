"""Prepare the lobby R4 PBR textures without touching Studio or Blender.

Download and verify CC0 scans from Poly Haven, then make deliberately restrained
1024px runtime maps.  Height is retained for Blender bump editing; Roblox uses
the separately supplied OpenGL tangent-space normal map.  This does not upload
assets or change existing files outside the R4 texture directory.

Run with a Python environment containing numpy and Pillow:
    python tools/lobby_reimagined/r4_materials.py
"""
from __future__ import annotations

import argparse
import base64
import concurrent.futures
import hashlib
import json
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "assets/models/lobby-reimagined-r4-20261001/textures"
AGENT = "BackroomsLobbyMaterialPreparation/1.0"
SIZE = 1024
SOURCES = {
    "concrete_wall_008": {
        "authors": {"Charlotte Baglioni": "Photography", "Dario Barresi": "Processing"},
        "widthMeters": 2.7,
    },
    "clean_asphalt": {"authors": {"Dimitrios Savva": "All"}, "widthMeters": 2.1},
    "concrete_pavement": {"authors": {"Charlotte Baglioni": "All"}, "widthMeters": 1.8},
}
MAP_TYPES = {"color": "Diffuse", "normal": "nor_gl", "height": "Displacement", "roughness": "Rough"}
MATERIALS = {
    "tunnel_concrete": {
        "source": "concrete_wall_008", "targetColor": [163, 160, 152],
        "colorContrast": 0.72, "sourceChroma": 0.50, "normalStrength": 0.70,
        "roughnessMinimum": 0.71, "roughnessMaximum": 0.95,
        "tileStuds": 12, "baseMaterial": "Concrete",
        "use": "Rounded tunnel lining and concrete wall panels",
    },
    "asphalt_road": {
        "source": "clean_asphalt", "targetColor": [62, 64, 63],
        "colorContrast": 0.66, "sourceChroma": 0.18, "normalStrength": 0.65,
        "roughnessMinimum": 0.73, "roughnessMaximum": 0.94,
        "tileStuds": 14, "baseMaterial": "Asphalt",
        "use": "Central roadway, unpainted charcoal asphalt",
    },
    "sidewalk_concrete": {
        "source": "concrete_pavement", "targetColor": [158, 156, 149],
        "colorContrast": 0.78, "sourceChroma": 0.45, "normalStrength": 0.65,
        "roughnessMinimum": 0.72, "roughnessMaximum": 0.94,
        "tileStuds": 8, "baseMaterial": "Concrete",
        "use": "Aged concrete sidewalk slabs and raised DJ stage steps",
    },
    "curb_concrete": {
        "source": "concrete_wall_008", "targetColor": [171, 168, 162],
        "colorContrast": 0.53, "sourceChroma": 0.35, "normalStrength": 0.45,
        "roughnessMinimum": 0.75, "roughnessMaximum": 0.96,
        "tileStuds": 8, "baseMaterial": "Concrete",
        "use": "Sidewalk curb edges and restrained concrete trim",
    },
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def source_pack(out: Path, slug: str) -> dict:
    """Retain exact source PNGs plus API receipts, verifying upstream MD5s."""
    directory = out / "source" / slug
    directory.mkdir(parents=True, exist_ok=True)
    api_path = directory / "files-api.json"
    if not api_path.exists():
        api_path.write_bytes(fetch(f"https://api.polyhaven.com/files/{slug}"))
    api = json.loads(api_path.read_text())
    result = {"slug": slug, "url": f"https://polyhaven.com/a/{slug}", "license": "CC0-1.0",
              "licenseUrl": "https://polyhaven.com/license", **SOURCES[slug], "maps": {}}
    for role, upstream_key in MAP_TYPES.items():
        item = api[upstream_key]["1k"]["png"]
        path = directory / item["url"].rsplit("/", 1)[-1]
        if not path.exists():
            path.write_bytes(fetch(item["url"]))
        data = path.read_bytes()
        if hashlib.md5(data).hexdigest() != item["md5"]:
            raise ValueError(f"Upstream source hash mismatch: {path}")
        with Image.open(path) as image:
            dimensions = list(image.size)
            mode = image.mode
        result["maps"][role] = {"path": str(path.relative_to(out)), "url": item["url"],
                               "upstreamMD5": item["md5"], "sha256": sha256(path),
                               "bytes": len(data), "dimensions": dimensions, "mode": mode}
    return result


def color_map(image: Image.Image, material: dict) -> Image.Image:
    rgb = np.asarray(image.convert("RGB"), dtype=np.float32)
    luminance = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    median = float(np.median(luminance))
    detail = (luminance - median) * material["colorContrast"]
    chroma = rgb - luminance[..., None]
    chroma -= np.median(chroma, axis=(0, 1))
    # Keep photographed aggregate and pores while removing excessive yellow cast.
    mapped = np.asarray(material["targetColor"], dtype=np.float32) + detail[..., None]
    mapped += chroma * material["sourceChroma"]
    return Image.fromarray(np.clip(np.rint(mapped), 0, 255).astype(np.uint8))


def normal_map(image: Image.Image, strength: float) -> Image.Image:
    # The upstream normal is explicitly OpenGL; no G-channel inversion.
    normal = np.asarray(image.convert("RGB"), dtype=np.float32) / 127.5 - 1
    normal[..., :2] *= strength
    normal[..., 2] = np.maximum(normal[..., 2], 0.05)
    normal /= np.maximum(np.linalg.norm(normal, axis=-1, keepdims=True), 1e-6)
    return Image.fromarray(np.clip(np.rint((normal + 1) * 127.5), 0, 255).astype(np.uint8))


def roughness_map(image: Image.Image, material: dict) -> Image.Image:
    if image.mode in ("I", "I;16", "I;16L", "I;16B"):
        raw = np.asarray(image, dtype=np.float32) / 65535
    else:
        raw = np.asarray(image.convert("L"), dtype=np.float32) / 255
    # Remain dry/matte, with genuine scanned pore/aggregate roughness variation.
    lo, hi = np.quantile(raw, [.02, .98])
    raw = np.clip((raw - lo) / max(float(hi - lo), 1e-5), 0, 1)
    low, high = material["roughnessMinimum"], material["roughnessMaximum"]
    mapped = low + raw * (high - low)
    return Image.fromarray(np.clip(np.rint(mapped * 255), 0, 255).astype(np.uint8))


def seam_metrics(array: np.ndarray) -> dict:
    data = array.astype(np.float32)
    horizontal_seam = np.abs(data[:, 0] - data[:, -1]).mean()
    vertical_seam = np.abs(data[0] - data[-1]).mean()
    horizontal_inner = np.abs(data[:, 1:] - data[:, :-1]).mean()
    vertical_inner = np.abs(data[1:] - data[:-1]).mean()
    return {"horizontalEdgeMeanDifference": round(float(horizontal_seam), 4),
            "verticalEdgeMeanDifference": round(float(vertical_seam), 4),
            "horizontalInteriorMeanDifference": round(float(horizontal_inner), 4),
            "verticalInteriorMeanDifference": round(float(vertical_inner), 4)}


def save_material(out: Path, key: str, material: dict, source: dict) -> dict:
    maps = {}
    for role in MAP_TYPES:
        path = out / source["maps"][role]["path"]
        with Image.open(path) as opened:
            image = opened.copy()
        if image.size != (SIZE, SIZE):
            image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        if role == "color": image = color_map(image, material)
        elif role == "normal": image = normal_map(image, material["normalStrength"])
        elif role == "roughness": image = roughness_map(image, material)
        # Height PNG retains the original 16-bit scan data, not RGB luma guessing.
        target = out / f"{key}_{role}.png"
        image.save(target, optimize=True)
        array = np.asarray(image)
        maps[role] = {"file": target.name, "sha256": sha256(target), "bytes": target.stat().st_size,
                      "dimensions": list(image.size), "mode": image.mode,
                      "minimum": int(array.min()), "maximum": int(array.max()),
                      "standardDeviation": round(float(array.std()), 5),
                      "seams": seam_metrics(array),
                      "colorSpace": "sRGB" if role == "color" else "Non-Color"}
        if role == "normal":
            maps[role]["convention"] = "OpenGL tangent space (+Y), normalized; source GL map"
        if role == "height":
            maps[role]["purpose"] = "Blender optional bump editing; Roblox consumes normal map"
    return {"key": key, "materialVariantName": f"LobbyR4_{key}", **material,
            "metalness": 0, "maps": maps,
            "roblox": {"BaseMaterial": material["baseMaterial"], "StudsPerTile": material["tileStuds"],
                       "MaterialPattern": "Regular", "ColorMap": maps["color"]["file"],
                       "NormalMap": maps["normal"]["file"], "RoughnessMap": maps["roughness"]["file"],
                       "MetalnessMap": "leave blank (dielectric)", "applyScope": "R4 lobby only; no global overrides"},
            "blender": {"ColorSpace": "sRGB", "NormalColorSpace": "Non-Color",
                        "RoughnessColorSpace": "Non-Color", "HeightColorSpace": "Non-Color",
                        "normalNodeStrength": 1.0, "heightBumpOptional": True,
                        "heightBumpDistanceStuds": 0.015, "avoidDoubleBump": True}}


def font(size: int) -> ImageFont.ImageFont:
    for name in ["/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Helvetica.ttc"]:
        if Path(name).exists(): return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def swatch_board(out: Path, results: dict) -> None:
    tile, gap, header, footer = 290, 20, 86, 58
    board = Image.new("RGB", (4 * (tile + gap) + gap, header + 4 * (tile + footer)), (21, 24, 23))
    draw = ImageDraw.Draw(board)
    draw.text((22, 13), "LOBBY R4  /  REAL PBR MAPS", font=font(27), fill=(224, 230, 219))
    draw.text((22, 52), "CC0 scans, 1024px runtime maps. Color / OpenGL normal / height / roughness", font=font(17), fill=(162, 181, 171))
    for row, (key, item) in enumerate(results.items()):
        for col, role in enumerate(MAP_TYPES):
            x, y = gap + col * (tile + gap), header + row * (tile + footer)
            with Image.open(out / item["maps"][role]["file"]) as image:
                if role == "height":
                    data = np.asarray(image).astype(np.float32)
                    lo, hi = np.quantile(data, [.005, .995])
                    image = Image.fromarray(np.clip((data - lo) / max(hi - lo, 1) * 255, 0, 255).astype(np.uint8))
                image = image.convert("RGB").resize((tile, tile), Image.Resampling.LANCZOS)
                board.paste(image, (x, y))
            draw.text((x, y + tile + 6), key.replace("_", " "), font=font(17), fill=(223, 230, 219))
            label = "height (display normalized)" if role == "height" else role
            draw.text((x, y + tile + 29), label, font=font(15), fill=(154, 176, 167))
    board.save(out / "material-map-preview.jpg", quality=94)
    # A tiled diffuse preview makes repeating cracks or unwanted color casts clear.
    for key, item in results.items():
        with Image.open(out / item["maps"]["color"]["file"]) as image:
            tile_image = image.resize((512, 512), Image.Resampling.LANCZOS).convert("RGB")
        tiled = Image.new("RGB", (1024, 1024))
        for y in (0, 512):
            for x in (0, 512): tiled.paste(tile_image, (x, y))
        tiled.save(out / f"{key}_tiled-preview.jpg", quality=94)


def validate_pack(out: Path) -> dict:
    manifest = json.loads((out / "manifest.json").read_text())
    checks = []
    for key, item in manifest["materials"].items():
        for role, record in item["maps"].items():
            path = out / record["file"]
            with Image.open(path) as image:
                array = np.asarray(image)
                if image.size != (SIZE, SIZE): raise ValueError(f"Invalid dimensions: {path}")
            if sha256(path) != record["sha256"]: raise ValueError(f"Output hash mismatch: {path}")
            if float(array.std()) <= 0: raise ValueError(f"Constant map: {path}")
            checks.append({"material": key, "map": role, "size1024": True,
                           "exactHash": True, "nonconstant": True})
        with Image.open(out / item["maps"]["normal"]["file"]) as image:
            normal_bytes = np.asarray(image, dtype=np.float32)
        normal = normal_bytes / 127.5 - 1
        normal_error = float(np.abs(np.linalg.norm(normal, axis=2) - 1).mean())
        xy_std = np.std(normal_bytes[..., :2], axis=(0, 1)).tolist()
        if normal_error >= .01 or min(xy_std) <= .15:
            raise ValueError(f"Invalid or flat normal map: {key}")
        checks.append({"material": key, "normalConvention": "OpenGL",
                       "meanNormalLengthError": normal_error, "normalXYStandardDeviation": xy_std})
        with Image.open(out / item["maps"]["height"]["file"]) as image:
            height = np.asarray(image)
        with Image.open(out / manifest["sources"][item["source"]]["maps"]["height"]["path"]) as image:
            source_height = np.asarray(image)
        if height.dtype != np.uint16 or not np.array_equal(height, source_height):
            raise ValueError(f"Height must retain the exact genuine 16-bit scan: {key}")
        with Image.open(out / item["maps"]["color"]["file"]) as image:
            median = np.median(np.asarray(image), axis=(0, 1)).tolist()
        checks.append({"material": key, "medianColor": median, "height16Bit": True,
                       "heightExactSource": True, "tileStuds": item["tileStuds"]})
    source_count = 0
    for source in manifest["sources"].values():
        for record in source["maps"].values():
            path = out / record["path"]
            if hashlib.md5(path.read_bytes()).hexdigest() != record["upstreamMD5"]:
                raise ValueError(f"Source hash mismatch: {path}")
            if sha256(path) != record["sha256"]: raise ValueError(f"Source SHA mismatch: {path}")
            source_count += 1
    receipt = {"verifiedFiles": 16, "sourceMapsMD5Verified": source_count, "checks": checks,
               "studioChecked": False, "uploaded": False}
    (out / "verification.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return receipt


def runtime_pixels(out: Path) -> dict:
    """Exact PNG bytes → top-down RGBA8, with no gamma/color transformation."""
    manifest = json.loads((out / "manifest.json").read_text())
    rows = []
    for material_key in ("tunnel_concrete", "asphalt_road", "sidewalk_concrete"):
        item = manifest["materials"][material_key]
        for role in ("color", "normal", "roughness"):
            source = out / item["maps"][role]["file"]
            with Image.open(source) as image:
                assert image.size == (SIZE, SIZE)
                # Pillow converts L to equal RGB channels and fills opaque alpha.
                # Its PNG reader/convert operation does not apply an sRGB transform.
                rgba = image.convert("RGBA")
                raw = rgba.tobytes()
                source_array = np.asarray(image.convert("RGB"))
            array = np.frombuffer(raw, dtype=np.uint8).reshape(SIZE, SIZE, 4)
            assert len(raw) == SIZE * SIZE * 4 and np.all(array[..., 3] == 255)
            assert np.array_equal(array[..., :3], source_array)
            if role == "roughness":
                assert np.array_equal(array[..., 0], array[..., 1]) and np.array_equal(array[..., 0], array[..., 2])
            encoded = base64.b64encode(raw)
            target = out / f"{material_key}_{role}.rgba.b64"
            target.write_bytes(encoded)
            assert base64.b64decode(target.read_bytes(), validate=True) == raw
            rows.append({"key": f"{material_key}__{role}", "materialKey": material_key, "role": role,
                         "file": target.name, "width": SIZE, "height": SIZE,
                         "pixelFormat": "RGBA8", "rowOrder": "top-down", "alpha": 255,
                         "rgbaBytes": len(raw), "rgbaSHA256": hashlib.sha256(raw).hexdigest(),
                         "base64Bytes": len(encoded), "base64SHA256": hashlib.sha256(encoded).hexdigest(),
                         "sourcePNG": source.name, "sourcePNGSHA256": sha256(source),
                         "colorTransformApplied": False})
    result = {"schema": "lobby-r4-exact-png-runtime-rgba-v1", "images": rows,
              "imageCount": len(rows), "rowOrder": "top-down", "pixelFormat": "RGBA8",
              "conversion": "Pillow PNG decode/convert RGBA; no gamma transform; L roughness replicated RGB",
              "scope": "Three architecture material families; optional curb family is not encoded",
              "verification": "Every alpha opaque; every RGB byte equals decoded source PNG; every base64 decoded and byte-compared"}
    (out / "runtime-pixels.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--runtime-pixels", action="store_true")
    args = parser.parse_args()
    out = args.output.resolve()
    if args.runtime_pixels:
        validate_pack(out)
        result = runtime_pixels(out)
        print(json.dumps({"runtimeImageCount": result["imageCount"], "rowOrder": result["rowOrder"],
                          "RGBABytesPerImage": SIZE * SIZE * 4, "passed": True}))
        return
    if args.verify_only:
        receipt = validate_pack(out)
        print(json.dumps({"verifiedFiles": receipt["verifiedFiles"],
                          "verifiedSourceFiles": receipt["sourceMapsMD5Verified"], "passed": True}))
        return
    out.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        source_results = list(pool.map(lambda slug: source_pack(out, slug), SOURCES))
    sources = {item["slug"]: item for item in source_results}
    materials = {key: save_material(out, key, value, sources[value["source"]]) for key, value in MATERIALS.items()}
    swatch_board(out, materials)
    manifest = {"schemaVersion": 1, "revision": "Lobby R4 2026-10-01",
                "runtimeResolution": SIZE, "sourceLicense": "CC0-1.0", "sources": sources,
                "materials": materials,
                "technicalReferences": ["https://create.roblox.com/docs/reference/engine/classes/MaterialVariant",
                                        "https://create.roblox.com/docs/art/modeling/surface-appearance"],
                "pipelineNotes": [
                    "Export real UVs and tangent information for MeshPart normal maps.",
                    "Split architecture chunks by material; do not reuse the prop atlas as their ColorMap.",
                    "Tunnel UV.u = circumference arclength / 12 studs; UV.v = distance along tunnel / 12 studs.",
                    "Keep tunnel UVs and tangents continuous across shell sections; smooth radial normals.",
                    "Road and sidewalk UVs follow continuous world distance, with matching tile scales.",
                    "For SurfaceAppearance, UVs set tiling; StudsPerTile belongs to MaterialVariant.",
                    "Assign scoped material variants to R4 parts only, never override global Concrete/Asphalt.",
                    "PNG files are material assets only. Upload IDs and Studio rendering must be verified separately.",
                ]}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    validate_pack(out)
    print(json.dumps({"output": str(out), "materials": list(materials), "sourceHashesVerified": True,
                      "runtimeMaps": len(materials) * 3, "retainedHeightMaps": len(materials),
                      "manifestSHA256": sha256(out / "manifest.json")}, indent=2))


if __name__ == "__main__":
    main()
