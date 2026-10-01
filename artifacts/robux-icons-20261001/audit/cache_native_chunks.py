"""Materialize an already-captured native backup when iCloud offloads its chunks."""
import concurrent.futures
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "native-before"
DESTINATION = Path("/private/tmp/robux-icons-native-before-20261001")
DESTINATION.mkdir(exist_ok=True)
files = [ROOT / "metadata.json", ROOT / "service-property-schema.json"]
files += sorted(ROOT.glob("native-part-*.bin"))
files += sorted(ROOT.glob("script-part-*.jsonpart"))

def copy(path):
    data = path.read_bytes()
    destination = DESTINATION / path.name
    if destination.exists():
        assert destination.read_bytes() == data, "Unexpected cache conflict " + path.name
    else:
        destination.write_bytes(data)
    return {"file": path.name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(copy, files))
(DESTINATION / "cache-receipt.json").write_text(json.dumps({"source": str(ROOT), "cache": str(DESTINATION), "chunkCount": len(files), "files": results}, indent=2))
print(json.dumps({"cachedFiles": len(files), "cache": str(DESTINATION)}))
