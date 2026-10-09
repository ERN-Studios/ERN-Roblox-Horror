"""Contact sheet for one Luna action (system Python; drives headless Blender, then composes with PIL).

    python tools/luna/anim/sheet.py <file.blend> <action> <out.png> [step:N | f1,f2,...] [views=side,front]
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

BLENDER = r"D:\Blender\blender.exe"
HERE = Path(__file__).resolve().parent


def sheet(blend, action, out, spec="step:4", views="side"):
    with tempfile.TemporaryDirectory() as tmp:
        prefix = str(Path(tmp) / "f")
        run = subprocess.run([BLENDER, "-b", blend, "-P", str(HERE / "render_clip.py"), "--", prefix, action, spec, views],
                             capture_output=True, text=True, encoding="utf-8", errors="replace")
        frames = [line[6:].strip() for line in run.stdout.splitlines() if line.startswith("FRAME ")]
        if not frames:
            raise SystemExit(run.stdout[-3000:] + run.stderr[-3000:])
        vlist = views.split(",")
        cols = 8 if len(vlist) == 1 else len(vlist) * (4 // len(vlist) or 1)
        tiles = [Image.open(f).convert("RGB") for f in frames]
        w, h = tiles[0].size
        rows = (len(tiles) + cols - 1) // cols
        img = Image.new("RGB", (cols * w, rows * h + 28), (30, 30, 34))
        d = ImageDraw.Draw(img)
        d.text((8, 6), f"{action}  ({Path(blend).name})", fill=(255, 255, 255))
        for i, (t, f) in enumerate(zip(tiles, frames)):
            x, y = (i % cols) * w, (i // cols) * h + 28
            img.paste(t, (x, y))
            d.text((x + 6, y + 4), Path(f).stem.split("_", 1)[1], fill=(255, 230, 120))
        img.save(out)
        print(out)


if __name__ == "__main__":
    a = sys.argv[1:]
    sheet(a[0], a[1], a[2], a[3] if len(a) > 3 else "step:4", a[4] if len(a) > 4 else "side")
