"""Freeze only this owned artifact package. No Studio/production/index calls."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHA = lambda b: hashlib.sha256(b).hexdigest()
target = HERE / "frozen-pins-v1.json"
assert not target.exists()
offline = json.loads((HERE / "offline-final-v1.json").read_bytes())
assert offline["passed"] is True and offline["replay"]["cases"] == 56 and offline["replay"]["checks"] == 366487
assert offline["driverPort"]["cases"] == 27 and offline["driverPort"]["passed"] is True
names = [".gitattributes", "collector.luau", "run-root-inventory.py", "offline-fixtures.luau",
         "driver-fixtures.py", "test-offline.py", "REVIEW.md", "freeze.py", "offline-attempt-v1.json",
         "offline-attempt-v2.json", "offline-final-v1.json"]
pins = []
for name in names:
    path = HERE / name
    raw = path.read_bytes()
    pins.append({"path": path.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)})
payload = {"schema": "mongotv-animation-cache-readonly-frozen-pins-v1", "nativeExecuted": False,
           "productionWrites": 0, "nativeInstanceSourcePropertyWritesRequested": 0, "deletionApproved": False,
           "files": pins, "fileCount": len(pins), "totalBytes": sum(row["bytes"] for row in pins)}
with target.open("xb") as stream:
    stream.write((json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode())
print(json.dumps({"frozenPinsBytes": len(target.read_bytes()), "frozenPinsSHA256": SHA(target.read_bytes()),
                  "fileCount": len(pins), "totalBytes": payload["totalBytes"],
                  "codePins": [row for row in pins if row["path"].endswith(("collector.luau", "run-root-inventory.py", "test-offline.py"))]}))
