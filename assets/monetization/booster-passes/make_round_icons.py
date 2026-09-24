"""Crop the generated booster art to Roblox's circular Game Pass safe area."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent
ART = {
    "2x": "source-2x.png",
    "3x": "source-3x.png",
    "5x": "source-5x.png",
}

def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    thumbs = []
    for tier, name in ART.items():
        icon = Image.open(OUT / name).convert("RGBA").resize((512, 512), Image.Resampling.LANCZOS)
        mask = Image.new("L", (512, 512), 0)
        ImageDraw.Draw(mask).ellipse((5, 5, 506, 506), fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(1.25))
        icon.putalpha(mask)
        icon.save(OUT / f"earned-tokens-{tier}-round.png", optimize=True)
        thumb = icon.resize((128, 128), Image.Resampling.LANCZOS)
        thumbs.append(thumb)
    sheet = Image.new("RGBA", (384, 128), (28, 32, 38, 255))
    for index, thumb in enumerate(thumbs):
        sheet.alpha_composite(thumb, (128 * index, 0))
    sheet.convert("RGB").save(OUT / "booster-icons-128-preview.jpg", quality=95)

if __name__ == "__main__":
    main()
