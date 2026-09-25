"""Show the final square assets at the shop's actual 78px and 104px sizes."""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
SKINS = (
    "baseline-yellow",
    "pool-service",
    "suburb-survey",
    "blacksite-director",
    "static-wraith",
    "false-sun",
)
TILE = (148, 170)
sheet = Image.new("RGB", (TILE[0] * len(SKINS), TILE[1] * 2), "#0c1519")
draw = ImageDraw.Draw(sheet)
for column, skin in enumerate(SKINS):
    art = Image.open(ROOT / (skin + "-standing-card-v1.png")).convert("RGBA")
    for row, size in enumerate((104, 78)):
        x = column * TILE[0] + (TILE[0] - size) // 2
        y = row * TILE[1] + 16
        thumb = art.resize((size, size), Image.Resampling.LANCZOS)
        sheet.paste(thumb, (x, y), thumb)
        draw.text((column * TILE[0] + 8, row * TILE[1] + 135),
                  skin.replace("-", " "), fill="#d7d8d0")
        draw.text((column * TILE[0] + 8, row * TILE[1] + 151),
                  f"{size} px", fill="#8caaa7")
sheet.save(ROOT / "standing-card-preview-sheet.jpg", quality=93)
