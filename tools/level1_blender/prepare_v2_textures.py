"""Keep the original wallpaper pixels; derive detail maps and shared prop finishes."""
from pathlib import Path
import hashlib, importlib.util, json, shutil, tempfile
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OLD = ROOT / "assets/level1/blender"
OUT = ROOT / "assets/level1/blender-v2/textures"
path = ROOT / "tools/level4_blender/make_pbr.py"
spec = importlib.util.spec_from_file_location("existing_pbr", path)
pbr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pbr)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = OUT / "source/original-wallpaper.png"
    assert source.is_file(), "Extract original Studio wallpaper first; no replacement pattern is allowed"
    published = {}
    receipt_path = OUT / "published.json"
    previous = json.loads(receipt_path.read_text()) if receipt_path.is_file() else {}
    old_published = json.loads((OLD / "textures/published.json").read_text())
    for stem in ("carpet", "ceiling"):
        for channel in ("albedo", "normal", "rough", "height"):
            name = stem + "_" + channel + ".png"
            shutil.copy2(OLD / "textures" / name, OUT / name)
            if name in old_published:
                receipt = old_published[name]
                assert receipt["sha256"] == sha(OUT / name)
                published[name] = receipt
    # The ColorMap remains the owner's exact existing asset, including its original pattern.
    shutil.copy2(source, OUT / "wallpaper_albedo.png")
    published["wallpaper_albedo.png"] = {"assetId": "rbxassetid://87947439437597",
         "sourceAssetId": 87947439437597, "sha256": sha(source), "file": "wallpaper_albedo.png"}
    with tempfile.TemporaryDirectory(prefix="level1-pbr-") as temporary:
        details = pbr.make_pbr(str(source), temporary, "wallpaper", size=1024,
                              strength=2.2, rough_base=.88, rough_var=.07, highpass=48)
        for channel in ("normal", "rough", "height"):
            shutil.copy2(details[channel], OUT / ("wallpaper_" + channel + ".png"))
        # One deterministic brushed/grained finish shared by the Blender-authored mechanical props.
        rng = np.random.default_rng(1039373905)
        n = 512
        grain = rng.normal(0, .012, (n, n))
        broad = pbr.blur(rng.normal(0, 1, (n, n)), 6)
        broad /= max(broad.std(), 1e-6)
        wear = np.clip((broad - 1.7) * .15, 0, .22)
        tone = np.clip(.58 + grain - wear, 0, 1)
        raw = Path(temporary) / "grain.png"
        Image.fromarray(np.repeat((tone * 255).astype(np.uint8)[..., None], 3, axis=2)).save(raw)
        maps = pbr.make_pbr(str(raw), temporary, "prop", size=n, strength=2.5,
                            rough_base=.62, rough_var=.10, highpass=32)
        for channel in ("normal", "rough"):
            shutil.copy2(maps[channel], OUT / ("prop_" + channel + ".png"))
        colors = {"steel": (105, 107, 95), "cream": (205, 199, 168), "ochre": (189, 151, 48),
                  "olive": (89, 101, 70), "red": (144, 39, 26), "copper": (175, 119, 62),
                  "porcelain": (225, 218, 187)}
        for name, rgb in colors.items():
            factor = np.clip(1 + grain * 2 - wear, .55, 1.10)
            array = np.clip(factor[..., None] * np.array(rgb), 0, 255).astype(np.uint8)
            Image.fromarray(array).save(OUT / ("prop_" + name + "_albedo.png"))
        Image.new("L", (n, n), 255).save(OUT / "prop_metal.png")
        Image.fromarray((np.clip(wear * 4, 0, 1) * 255).astype(np.uint8)).save(OUT / "prop_paintmetal.png")
    # A repeat derivation may reuse completed uploads only when the exact pixels
    # still match. Never discard the receipts for unchanged mechanical maps.
    for name, receipt in previous.items():
        file = OUT / name
        if file.is_file() and receipt.get("sha256") == sha(file):
            published[name] = receipt
    receipt_path.write_text(json.dumps(published, indent=2), encoding="utf-8")
    record = {"wallpaperSourceAsset": 87947439437597, "wallpaperSourceSha256": sha(source),
              "albedoPixelsUntouched": sha(source) == sha(OUT / "wallpaper_albedo.png"),
              "wallpaperTint": [255, 235, 150], "normalStrength": 2.2, "roughBase": .88,
              "unchangedCarpetCeiling": sorted(name for name in published if name.startswith(("carpet_", "ceiling_"))),
              "propFinish": "Deterministic Blender mechanical-kit grain; shared normal/rough maps"}
    (OUT / "derivation.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print("V2_TEXTURES=" + json.dumps(record))


if __name__ == "__main__":
    main()
