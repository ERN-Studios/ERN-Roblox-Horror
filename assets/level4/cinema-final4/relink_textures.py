"""Optional authoring helper: run inside one of this bundle's two native scenes.

Uses the read-only audit's exact texture bindings. Does not save the scene.
"""
from pathlib import Path
import hashlib, json
import bpy

ROOT = Path(__file__).resolve().parent
records = json.loads((ROOT / "native-audit.json").read_text())["files"]
opened = Path(bpy.data.filepath).resolve()
record = next((row for row in records if opened == (ROOT / row["file"]).resolve()), None)
assert record, "Open this bundle's Cinema_Final4.blend or Cinema_Templates.blend first"
for row in record["images"]:
    if row["packed"]:
        continue
    path = ROOT / row["bundledMatches"][0]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == row["originalFileSha256"]
    image = bpy.data.images[row["name"]]
    image.filepath = str(path)
    image.reload()
print("Cinema source texture paths relinked; native file has not been saved")
