"""Build an offline Level 6 atlas candidate from historical Level 3 assets.

This script writes only to this task's candidate directory. It never publishes
assets, changes Studio, or replaces the authored atlas / source .blend.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
TASK = HERE.parent
ROOT = TASK.parents[1]
ORIGINAL_ATLAS = ROOT / "assets/level6-worn-party/textures/WornParty_Atlas.png"
ORIGINAL_RUNTIME_ATLAS = ROOT / "assets/level6-worn-party/textures/WornParty_Atlas1024.png"
ORIGINAL_LAYOUT = ROOT / "assets/level6-worn-party/textures/atlas-layout.json"
REFERENCES = TASK / "reference-textures"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def srgb_to_linear(values: np.ndarray) -> np.ndarray:
    values = values / 255.0
    return np.where(values <= .04045, values / 12.92, ((values + .055) / 1.055) ** 2.4)


def linear_to_srgb(values: np.ndarray) -> np.ndarray:
    values = np.clip(values, 0, 1)
    result = np.where(values <= .0031308, values * 12.92, 1.055 * values ** (1 / 2.4) - .055)
    return np.rint(np.clip(result * 255, 0, 255)).astype(np.uint8)


def baked_overlay(path: Path, tint: list[int], opacity: float) -> Image.Image:
    """Approximate native Texture over its wall base in linear-light RGB.

    Material roughness, reflectance, lighting and native rendering are not baked.
    Texture.Color3 is assumed white. Live parity must be verified separately.
    """
    image = Image.open(path).convert("RGBA")
    array = np.asarray(image, dtype=np.float64)
    alpha = array[:, :, 3:4] / 255 * opacity
    foreground = srgb_to_linear(array[:, :, :3])
    background = srgb_to_linear(np.asarray(tint, dtype=np.float64))
    return Image.fromarray(linear_to_srgb(foreground * alpha + background * (1 - alpha)), "RGB")


def red_tinted_wear(path: Path, tint: list[int], opacity: float) -> Image.Image:
    """Preserve the red theme while reusing only the orange image's wear.

    This is deliberately an art-direction approximation, not an exact native
    Level3 opacity composite. A live native A/B must decide the final tint.
    """
    array = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    linear = srgb_to_linear(array)
    luminance = linear @ np.asarray([.2126, .7152, .0722])
    wear = np.clip(luminance / max(float(np.median(luminance)), .00001), .5, 1.5)
    base = srgb_to_linear(np.asarray(tint, dtype=np.float64))
    composite = base * ((1 - opacity) + opacity * wear[:, :, None])
    return Image.fromarray(linear_to_srgb(composite), "RGB")


def guarded_cell(image: Image.Image) -> Image.Image:
    """Match the original cell's four-pixel edge extension and UV rectangle."""
    image = image.convert("RGB").resize((504, 504), Image.Resampling.LANCZOS)
    cell = Image.new("RGB", (512, 512))
    cell.paste(image, (4, 4))
    cell.paste(image.crop((0, 0, 1, 504)).resize((4, 504)), (0, 4))
    cell.paste(image.crop((503, 0, 504, 504)).resize((4, 504)), (508, 4))
    cell.paste(cell.crop((0, 4, 512, 5)).resize((512, 4)), (0, 0))
    cell.paste(cell.crop((0, 507, 512, 508)).resize((512, 4)), (0, 508))
    return cell


def build(palette_file: Path) -> None:
    recommendations = json.loads(palette_file.read_text())
    palette = recommendations["palette"]
    source_atlas = Image.open(ORIGINAL_ATLAS).convert("RGB")
    assert source_atlas.size == (2048, 2048)
    layout = json.loads(ORIGINAL_LAYOUT.read_text())
    atlas = source_atlas.copy()
    records = []

    changes = {
        0: ("pastel-wallpaper.png", [220, 213, 187], .92, "PastelWallpaperTexture", 18),
        1: ("orange-wall-worn-v1.png", [183, 78, 35], .72, "OrangeWallTexture", 22),
        2: ("orange-wall-worn-v1.png", [145, 58, 48], .72, "OrangeWallTexture over red wall", 22),
        5: ("city-play-carpet.png", None, 1, "CityPlayCarpetTexture", 52),
        6: ("party-carpet-neon-v1.png", None, 1, "PartyCarpetNeonTexture", 22),
        7: ("party-carpet-red-v1.png", None, 1, "PartyCarpetRedTexture", 30),
    }
    for cell, (filename, tint, opacity, slot, repeat) in changes.items():
        path = REFERENCES / filename
        if cell == 2:
            image = red_tinted_wear(path, tint, opacity)
        else:
            image = baked_overlay(path, tint, opacity) if tint else Image.open(path).convert("RGB")
        atlas.paste(guarded_cell(image), ((cell % 4) * 512, (cell // 4) * 512))
        records.append({"cell": cell, "slot": slot, "sourceFile": str(path.relative_to(ROOT)),
                        "sourceSha256": sha256(path), "wallBaseRGB": tint,
                        "overlayOpacity": opacity, "nativeStudsPerTile": repeat,
                        "operation": "red-tinted normalized linear luminance wear; approximate native A/B pending" if cell == 2 else ("linear-light opacity approximation" if tint else "source pixels, resized only"),
                        "blenderRepeatMatchesNative": False})

    # Keep the original per-pixel wear residual within each palette swatch.
    # Neutral metals/paper/rubber and the unused wall swatches remain untouched.
    palette_rect = (1536, 1536, 2048, 2048)
    palette_pixels = np.asarray(atlas.crop(palette_rect), dtype=np.float64).copy()
    original_palette = np.asarray(source_atlas.crop(palette_rect), dtype=np.float64)
    swatch_records = []
    for key, color in palette.items():
        if key not in layout["mapping"] or layout["mapping"][key]["cell"] != 15:
            raise ValueError(f"Palette key is not a palette-cell material: {key}")
        index = list(layout["colors"]).index(key)
        # Original author used 85px swatches followed by 504/512 rescaling+4px inset.
        x0 = int(round(4 + (index % 6) * 85 * 504 / 512))
        y0 = int(round(4 + (index // 6) * 85 * 504 / 512))
        x1 = int(round(4 + min((index % 6 + 1) * 85, 512) * 504 / 512))
        y1 = int(round(4 + min((index // 6 + 1) * 85, 512) * 504 / 512))
        residual = original_palette[y0:y1, x0:x1] - np.asarray(layout["colors"][key])
        palette_pixels[y0:y1, x0:x1] = np.clip(np.asarray(color) + residual, 0, 255)
        swatch_records.append({"material": key, "fromRGB": layout["colors"][key],
                               "toRGB": color, "rect": [x0, y0, x1, y1],
                               "wearResidualPreserved": True})
        layout["colors"][key] = color
    atlas.paste(Image.fromarray(np.rint(palette_pixels).astype(np.uint8), "RGB"), (1536, 1536))

    output = HERE / "textures/WornParty_Level3Reference_Atlas.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output, optimize=True)
    # Preserve the original layout file byte-for-byte. Color metadata lives in
    # the separate manifest; runtime UV windows must not silently move.
    (HERE / "textures/atlas-layout.json").write_bytes(ORIGINAL_LAYOUT.read_bytes())
    layout["colors"].update(beige_wall=[220, 213, 187], orange_wall=[183, 78, 35], red_wall=[145, 58, 48])
    (HERE / "textures/candidate-material-colors.json").write_text(json.dumps(layout["colors"], indent=2) + "\n")
    # Resize selected cells separately onto the verified authored 1024 atlas.
    # Whole-atlas filtering would change neighboring neutral boundary pixels.
    runtime_image = Image.open(ORIGINAL_RUNTIME_ATLAS).convert("RGBA")
    assert runtime_image.size == (1024, 1024)
    for cell in sorted(set(changes) | {15}):
        rect = ((cell % 4) * 512, (cell // 4) * 512, (cell % 4 + 1) * 512, (cell // 4 + 1) * 512)
        runtime_image.paste(atlas.crop(rect).resize((256, 256), Image.Resampling.LANCZOS).convert("RGBA"), ((cell % 4) * 256, (cell // 4) * 256))
    runtime_image.save(HERE / "textures/WornParty_Level3Reference_Atlas1024.png", optimize=True)
    rgba = runtime_image.tobytes()
    (HERE / "atlas-rgba.b64").write_text(base64.b64encode(rgba).decode("ascii"))
    pixel_metadata = {"width": 1024, "height": 1024, "channels": 4,
                      "format": "RGBA8", "bytes": len(rgba),
                      "sha256": hashlib.sha256(rgba).hexdigest(),
                      "originalPngSha256": sha256(HERE / "textures/WornParty_Level3Reference_Atlas1024.png"),
                      "installedInStudio": False, "atlasLayoutSha256": sha256(ORIGINAL_LAYOUT)}
    (HERE / "atlas-pixels.json").write_text(json.dumps(pixel_metadata, indent=2) + "\n")

    unchanged = sorted(set(range(16)) - set(changes) - {15})
    for cell in unchanged:
        rect = ((cell % 4) * 512, (cell // 4) * 512, (cell % 4 + 1) * 512, (cell // 4 + 1) * 512)
        assert np.array_equal(np.asarray(atlas.crop(rect)), np.asarray(source_atlas.crop(rect)))
        rect1024 = ((cell % 4) * 256, (cell // 4) * 256, (cell % 4 + 1) * 256, (cell // 4 + 1) * 256)
        assert np.array_equal(np.asarray(runtime_image.crop(rect1024)), np.asarray(Image.open(ORIGINAL_RUNTIME_ATLAS).convert("RGBA").crop(rect1024)))
    original_mapping = json.loads(ORIGINAL_LAYOUT.read_text())["mapping"]
    assert layout["mapping"] == original_mapping
    manifest = {
        "schema": "level6-offline-atlas-candidate-v1",
        "installedInStudio": False, "liveStudioReferenceVerified": False,
        "originalAtlasSha256": sha256(ORIGINAL_ATLAS), "candidateAtlasSha256": sha256(output),
        "dimensions": [2048, 2048], "geometryChanged": False,
        "uvMappingChanged": False, "unchangedCellsByteEquivalent": unchanged,
        "runtime1024UnchangedCellsByteEquivalent": unchanged,
        "atlasLayoutByteIdentical": sha256(HERE / "textures/atlas-layout.json") == sha256(ORIGINAL_LAYOUT),
        "runtimePixelMetadata": pixel_metadata,
        "cellChanges": records, "paletteChanges": swatch_records,
        "paletteRecommendationFile": str(palette_file.relative_to(ROOT)),
        "paletteRecommendationSha256": sha256(palette_file),
        "limitations": [
            "Current Studio unavailable during preparation: reference remains historically verified.",
            "Source images are resized to 504px content cells with the same edge guards.",
            "Wall opacity is an approximate linear-light bake, not a Roblox material/rendering parity guarantee.",
            "Red cell2 reuses normalized luminance wear tinted red; it is a hue-preserving art approximation requiring native A/B, not an exact Level3 orange-over-red composite.",
            "Existing Blender face UVs retain their original repeat; runtime native floors require separate fixed-repeat configuration.",
            "Tile-versus-carpet room classification is not changed by this atlas; runtime and authored scene routing must be handled separately.",
            "No mesh reimport, image upload, publication, or original authored-file overwrite was performed.",
        ],
    }
    (HERE / "atlas-candidate-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    # Unlit pixel comparison, distinct from a gameplay/lighting verification.
    sheet = Image.new("RGB", (1920, 830), (23, 23, 24))
    draw = ImageDraw.Draw(sheet)
    draw.text((22, 16), "LEVEL 6 OFFLINE CANDIDATE | historical Level 3 source pixels | not installed in Studio", fill=(245, 238, 221))
    labels = [(0, "Wallpaper"), (1, "Orange plaster"), (2, "Red plaster"),
              (5, "City carpet"), (6, "Neon carpet"), (7, "Red carpet")]
    for n, (cell, label) in enumerate(labels):
        x = (n % 3) * 640 + 16
        y = (n // 3) * 370 + 56
        rect = ((cell % 4) * 512, (cell // 4) * 512, (cell % 4 + 1) * 512, (cell // 4 + 1) * 512)
        draw.text((x, y), label + " | old / candidate", fill=(238, 227, 196))
        sheet.paste(source_atlas.crop(rect).resize((300, 300)), (x, y + 24))
        sheet.paste(atlas.crop(rect).resize((300, 300)), (x + 312, y + 24))
    draw.text((22, 796), "Unlit texture comparison. Native texture scale, current live state, and Roblox material behavior require separate verification.", fill=(180, 180, 180))
    sheet.save(HERE / "texture-comparison.jpg", quality=94)
    print(json.dumps({"atlas": str(output), "changedCells": sorted(changes), "unchangedCells": unchanged}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--palette", required=True, type=Path)
    args = parser.parse_args()
    build(args.palette.resolve())
