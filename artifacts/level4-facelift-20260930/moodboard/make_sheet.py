# Assembles the Codex moodboard into one comparison sheet: one row per direction (hero | carpet | wall).
import glob, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = {"A": "Cosmic Confetti", "B": "Memphis Pastel 80s", "C": "Deco Revival 1987",
         "D": "Backrooms Mono-Yellow", "E": "Popcorn & Reels", "F": "Synthwave Grid"}
H = 360
rows = []
for k, title in NAMES.items():
    tiles = []
    for part, w in (("hero", 640), ("carpet", H), ("wall", H)):
        p = os.path.join(HERE, "mb_%s_%s.png" % (k, part))
        im = Image.open(p).convert("RGB").resize((w, H)) if os.path.exists(p) else Image.new("RGB", (w, H), (40, 40, 40))
        tiles.append(im)
    row = Image.new("RGB", (sum(t.width for t in tiles) + 20, H + 44), (16, 14, 14))
    x = 0
    for t in tiles:
        row.paste(t, (x, 44)); x += t.width + 10
    ImageDraw.Draw(row).text((8, 8), "%s  %s" % (k, title), fill=(240, 230, 200), font=ImageFont.truetype("arial.ttf", 28))
    rows.append(row)
sheet = Image.new("RGB", (rows[0].width, sum(r.height for r in rows)), (16, 14, 14))
y = 0
for r in rows:
    sheet.paste(r, (0, y)); y += r.height
sheet.save(os.path.join(HERE, "moodboard_sheet.jpg"), quality=88)
print(sheet.size)
