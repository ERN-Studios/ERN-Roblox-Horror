"""Assemble matched offline Blender study images without altering source images."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sheet = Image.new("RGB", (1240, 1360), (23, 23, 24))
draw = ImageDraw.Draw(sheet)
draw.text((16, 16), "OFFLINE BLENDER STUDIES | historical Level3 source assets | not installed in Studio", fill=(242, 233, 213))
draw.text((16, 42), "Original authored atlas", fill=(191, 185, 176))
draw.text((636, 42), "Candidate atlas + Opus5.5/max palette", fill=(191, 185, 176))
records = []
for index, label in enumerate(["City Play / wallpaper", "Orange party / neon carpet", "Red party / red carpet"], start=1):
    y = 76 + (index - 1) * 420
    draw.text((16, y), label, fill=(244, 230, 184))
    for suffix, x in [("before", 16), ("candidate", 636)]:
        path = HERE / "previews" / f"{index:02d}-{suffix}.png"
        image = Image.open(path).convert("RGB")
        assert image.size == (960, 640)
        sheet.paste(image.resize((600, 400), Image.Resampling.LANCZOS), (x, y + 18))
        records.append({"path": str(path.relative_to(HERE)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "dimensions": list(image.size)})
draw.text((16, 1340), "Same Blender light/exposure. Existing UV repeat preserved; native fixed-repeat floors and live A/B are separate checks.", fill=(182, 182, 182))
sheet.save(HERE / "blender-study-comparison.jpg", quality=95)
(HERE / "preview-records.json").write_text(json.dumps({"installedInStudio": False, "renderingContext": "Blender5.2 existing AgX studies; not Roblox screenshots", "records": records}, indent=2) + "\n")
print("Wrote", HERE / "blender-study-comparison.jpg")
