"""Make lightweight, transparent Level 2 wall decals from reviewed ImageGen art."""

from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parent
SOURCES = {
    "maintenance": "source-maintenance-decal.png",
    "visitor-traces": "source-visitor-traces-decal.png",
}


def main() -> None:
    preview = Image.new("RGB", (1024, 1050), "#b9b8aa")
    for index, (name, filename) in enumerate(SOURCES.items()):
        decal = Image.open(ROOT / filename).convert("RGBA")
        decal = ImageOps.fit(decal, (1024, 512), method=Image.Resampling.LANCZOS)
        decal.save(ROOT / f"decal-{name}-v1.png", optimize=True)
        preview.paste(decal, (0, index * 538), decal)
    preview.save(ROOT / "decal-tile-preview.jpg", quality=90)


if __name__ == "__main__":
    main()
