"""Freeze only owned frontier artifacts + immutable external input pins."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
INVENTORY = HERE.with_name("animation-cache-inventory-v1")
SHA = lambda b: hashlib.sha256(b).hexdigest()
target = HERE / "frontier-frozen-pins-v1.json"
assert not target.exists()
port = json.loads((HERE / "frontier-offline-attempt-v1.json").read_bytes())
driver = json.loads((HERE / "frontier-driver-offline-v1.json").read_bytes())
assert port["passed"] and port["replay"]["cases"] == 11 and port["replay"]["checks"] == 78833
assert driver["passed"] and driver["cases"] == 21 and driver["checks"] == 51
paths = [p for p in HERE.iterdir() if p.is_file()]
prep = json.loads((HERE / "frontier-preparation.json").read_bytes())
paths.extend(ROOT / pin["path"] for pin in prep["inputs"])
paths.extend((INVENTORY / "run-root-inventory.py", INVENTORY / "offline-fixtures.luau"))
pins = []
for path in sorted(set(paths)):
    raw = path.read_bytes()
    pins.append({"path": path.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)})
value = {"schema": "mongotv-animation-archive-readonly-frontier-pins-v2", "nativeExecuted": False,
         "productionWrites": 0, "deletionApproved": False, "files": pins, "fileCount": len(pins),
         "totalBytes": sum(row["bytes"] for row in pins)}
with target.open("xb") as stream:
    stream.write((json.dumps(value, indent=2) + "\n").encode())
print(json.dumps({"frozenPinsBytes": len(target.read_bytes()), "frozenPinsSHA256": SHA(target.read_bytes()),
                  "fileCount": len(pins), "totalBytes": value["totalBytes"],
                  "executables": [row for row in pins if row["path"].endswith(("frontier-source.luau", "run-root-frontier.py"))]}))
