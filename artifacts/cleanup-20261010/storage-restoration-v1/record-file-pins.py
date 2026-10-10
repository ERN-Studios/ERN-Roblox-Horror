"""Freeze top-level preparation/proofs and unchanged historical inputs only."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sha = lambda raw: hashlib.sha256(raw).hexdigest()
historical = [
    ROOT / "artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1/native.rbxm",
    ROOT / "artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1/facts.json",
    ROOT / "artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1/capture-completion.json",
    ROOT / "artifacts/cleanup-serverstorage-20261009/external-storage-reopen-v1/roundtrip.rbxm",
    ROOT / "artifacts/cleanup-serverstorage-20261009/external-storage-reopen-v1/reopen-result.txt",
]
def row(path):
    assert path.is_file() and not path.is_symlink()
    raw = path.read_bytes()
    return {"path": path.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": sha(raw)}
files = sorted(p for p in HERE.iterdir() if p.is_file() and p.name != "file-pins.json")
report = {"schema": "storage-restoration-immutable-preparation-pins-v1", "nativeCallsByStorageAgent": 0,
    "sourceWrites": 0, "manifestWrites": 0, "indexWrites": 0, "commitWrites": 0,
    "nativeSetterRecoveryExecuted": False, "normalizationApplied": False, "restorationCertified": False,
    "scope": "Top-level immutable candidates/preparation/offline evidence plus Root's independent native readonly math receipt. New native execution subdirectories excluded.",
    "files": [row(p) for p in files], "historicalInputs": [row(p) for p in historical]}
assert report["historicalInputs"][0]["sha256"] == "139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca"
with (HERE / "file-pins.json").open("xb") as stream:
    stream.write((json.dumps(report, indent=2) + "\n").encode())
print(json.dumps({"files": len(files), "bytes": sum(r["bytes"] for r in report["files"]), "historicalInputs": len(historical)}))
