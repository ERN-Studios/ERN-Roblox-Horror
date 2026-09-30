"""Assemble and verify the read-only native Studio snapshot chunks."""

import hashlib
import json
import sys
from pathlib import Path


ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent / "native-backup"
meta = json.loads((ROOT / "metadata.json").read_text())


def write_or_verify(path: Path, data: bytes) -> None:
    if path.exists():
        assert path.read_bytes() == data, f"Existing backup differs: {path}"
    else:
        path.write_bytes(data)


native = b"".join(
    (ROOT / f"native-part-{index:05d}.bin").read_bytes()
    for index in range(meta["nativeParts"])
)
assert len(native) == meta["nativeBytes"]
write_or_verify(ROOT / "all-service-children.rbxm", native)

script_json = b"".join(
    (ROOT / f"script-part-{index:05d}.jsonpart").read_bytes()
    for index in range(meta["scriptJsonParts"])
)
scripts = json.loads(script_json)
assert len(scripts) == meta["scriptCount"]
assert all(item["editorMatch"] for item in scripts), "Unresolved Source/editor conflict"
write_or_verify(ROOT / "scripts.json", script_json)

manifest = {
    "schema": "studio-level3-source-manifest/1",
    "placeId": meta["placeId"],
    "universeId": meta["universeId"],
    "placeVersion": meta["placeVersion"],
    "sourceCount": len(scripts),
    "scripts": [
        {
            "path": item["path"],
            "class": item["class"],
            "sourceBytes": len(item["source"].encode()),
            "sourceSha256": hashlib.sha256(item["source"].encode()).hexdigest(),
            "editorMatch": item["editorMatch"],
        }
        for item in scripts
    ],
}
(ROOT / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
file_hashes = {
    "all-service-children.rbxm": hashlib.sha256(native).hexdigest(),
    "scripts.json": hashlib.sha256(script_json).hexdigest(),
}
for place in sorted(ROOT.glob("*.rbxl")):
    file_hashes[place.name] = hashlib.sha256(place.read_bytes()).hexdigest()
(ROOT / "backup-file-hashes.json").write_text(json.dumps(file_hashes, indent=2) + "\n")
print(f"Native backup assembled: {len(native)} bytes, {len(scripts)} parity-checked scripts")
