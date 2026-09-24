"""Normalize the three imagegen proposals and preview Roblox's circle crop.

The source PNGs were generated with the built-in imagegen tool. This script is
only deterministic sizing/alpha normalization and does not upload anything.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
PROPOSED = ROOT / "proposed"
ITEMS = [
    ("Expedition Pack", 3713829859, "expedition-pack"),
    ("Donate 5,000", 3713115025, "donation-5k"),
    ("Donate 10,000", 3713115125, "donation-10k"),
]


def font(size: int):
    path = Path("C:/Windows/Fonts/arial.ttf")
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default()


def circular_thumbnail(image: Image.Image) -> Image.Image:
    thumb = image.resize((128, 128), Image.Resampling.LANCZOS)
    mask = Image.new("L", (128, 128), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, 127, 127), fill=255)
    alpha = Image.new("L", (128, 128), 0)
    alpha.paste(thumb.getchannel("A"), (0, 0), mask)
    thumb.putalpha(alpha)
    return thumb


def main() -> None:
    sheet = Image.new("RGB", (3 * 300 + 20, 242), "#171e22")
    draw = ImageDraw.Draw(sheet)
    for index, (name, pid, slug) in enumerate(ITEMS):
        source = Image.open(PROPOSED / f"source-{slug}.png").convert("RGBA")
        final = source.resize((512, 512), Image.Resampling.LANCZOS)
        pixels = final.load()
        for y in range(512):
            for x in range(512):
                r, g, b, a = pixels[x, y]
                if a < 5:
                    pixels[x, y] = (r, g, b, 0)
        final_path = PROPOSED / f"{slug}-round-512.png"
        final.save(final_path, optimize=True)
        preview = circular_thumbnail(final)
        preview.save(PROPOSED / f"{slug}-circle-128.png")
        x = 10 + index * 300
        draw.rounded_rectangle((x, 10, x + 280, 231), radius=12, fill="#273237")
        draw.text((x + 10, 18), name, font=font(17), fill="white")
        draw.text((x + 10, 40), str(pid), font=font(13), fill="#a9b7ba")
        for dx, file in ((8, ROOT / "live-thumbnails" / f"{pid}-circle-128.png"), (148, PROPOSED / f"{slug}-circle-128.png")):
            art = Image.open(file).convert("RGBA")
            bg = Image.new("RGBA", (128, 128), "#34444a")
            bg.alpha_composite(art)
            sheet.paste(bg.convert("RGB"), (x + dx, 63))
        draw.text((x + 45, 199), "live", font=font(13), fill="#a9b7ba")
        draw.text((x + 181, 199), "proposed", font=font(13), fill="#a9b7ba")
    sheet.save(ROOT / "three-proposed-before-after-128.png")
    print("Prepared three 512px circular-safe proposals and a 128px preview sheet")


if __name__ == "__main__":
    main()
