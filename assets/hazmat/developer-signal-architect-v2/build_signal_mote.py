"""Draw a tiny, transparent signal-square particle for the cosmetic halo."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


HERE = Path(__file__).resolve().parent
SIZE = 128
BASE = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
GLOW = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(GLOW)
draw.rounded_rectangle((41, 41, 86, 86), radius=4, fill=(16, 234, 249, 115))
GLOW = GLOW.filter(ImageFilter.GaussianBlur(16))
BASE = Image.alpha_composite(BASE, GLOW)
draw = ImageDraw.Draw(BASE)
draw.rounded_rectangle((49, 49, 78, 78), radius=2, fill=(2, 26, 44, 205))
draw.rounded_rectangle((49, 49, 78, 78), radius=2, outline=(76, 251, 255, 245), width=4)
draw.rectangle((57, 57, 70, 70), fill=(84, 240, 255, 95))
BASE.save(HERE / "ascendant-signal-mote.png")
