"""Build four circle-safe Game Pass replacements without touching live passes."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent
ASSETS = ROOT.parents[1]
SIZE = 512


def circle_mask() -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE))
    ImageDraw.Draw(mask).ellipse((5, 5, 506, 506), fill=255)
    return mask.filter(ImageFilter.GaussianBlur(1.1))


def finish(image: Image.Image, output: str) -> Image.Image:
    image = image.convert("RGBA").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    alpha = Image.new("L", (SIZE, SIZE))
    alpha.paste(image.getchannel("A"))
    from PIL import ImageChops

    image.putalpha(ImageChops.multiply(alpha, circle_mask()))
    image.save(ROOT / output, optimize=True)
    return image


def hazmat_icon(source: Path, core: tuple, edge: tuple, halo: tuple, rim: tuple) -> Image.Image:
    base = Image.new("RGBA", (SIZE, SIZE))
    pixels = base.load()
    for y in range(SIZE):
        for x in range(SIZE):
            radial = min(1.0, ((x - 256) ** 2 + (y - 245) ** 2) ** 0.5 / 390)
            glow = max(0.0, 1 - (((x - 256) ** 2 + (y - 196) ** 2) ** 0.5 / 265)) ** 2
            color = tuple(
                round(core[c] * (1 - radial) + edge[c] * radial + halo[c] * glow * 0.34)
                for c in range(3)
            )
            pixels[x, y] = (*color, 255)
    rings = Image.new("RGBA", (SIZE, SIZE))
    draw = ImageDraw.Draw(rings)
    draw.ellipse((13, 13, 498, 498), outline=(*rim, 130), width=12)
    draw.ellipse((32, 32, 479, 479), outline=(*rim, 67), width=2)
    base = Image.alpha_composite(base, rings)
    suit = Image.open(source).convert("RGBA")
    # Use the precise original render. The mask is the subject; the T-pose
    # arms fall outside the close helmet portrait and the Roblox circle.
    suit = suit.crop((164, 28, 348, 212)).resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return Image.alpha_composite(base, suit)


def main() -> None:
    outputs = [
        finish(
            hazmat_icon(
                ASSETS / "hazmat/static-wraith-preview.png",
                (32, 26, 49), (9, 10, 20), (125, 103, 235), (119, 99, 214),
            ),
            "static-wraith-round-v2.png",
        ),
        finish(
            hazmat_icon(
                ASSETS / "hazmat/false-sun-preview.png",
                (70, 54, 37), (17, 14, 12), (250, 190, 92), (236, 184, 104),
            ),
            "false-sun-round-v2.png",
        ),
        finish(
            Image.open(ASSETS / "shop/box-entity-detector.png")
            .convert("RGBA")
            .crop((150, 80, 1104, 1034)),
            "entity-detector-round-v2.png",
        ),
        finish(
            Image.open(ROOT / "source-donation-20k.png"),
            "donation-20k-round-v2.png",
        ),
    ]
    sheet = Image.new("RGB", (128 * 4, 128), "#30363b")
    for i, icon in enumerate(outputs):
        thumb = icon.resize((128, 128), Image.Resampling.LANCZOS)
        sheet.paste(thumb, (128 * i, 0), thumb)
    sheet.save(ROOT / "all-four-128-preview.jpg", quality=95)


if __name__ == "__main__":
    main()
