"""Read-only raw-byte verification; does not invoke preparation or Studio."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
pins = json.loads((HERE / "file-pins.json").read_bytes())
for row in pins["files"] + pins["historicalInputs"]:
    path = (ROOT / row["path"]).resolve()
    assert path.is_relative_to(ROOT) and path.is_file() and not path.is_symlink()
    raw = path.read_bytes()
    assert (len(raw), hashlib.sha256(raw).hexdigest()) == (row["bytes"], row["sha256"]), "Frozen raw-byte input changed: " + row["path"]
print(json.dumps({"pass": True, "files": len(pins["files"]), "historicalInputs": len(pins["historicalInputs"]), "nativeCalls": 0}))
