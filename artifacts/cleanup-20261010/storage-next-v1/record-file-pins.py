"""Freeze this review's compact deliverables; no Studio or shared index writes."""
from pathlib import Path
import hashlib
import json

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
sha = lambda raw: hashlib.sha256(raw).hexdigest()
assert not (OUT / "original.rbxmx").exists() and not (OUT / "roundtrip.rbxmx").exists()
pinned_archives = {
    "artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1/native.rbxm": (2739764, "139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca"),
    "artifacts/cleanup-serverstorage-20261009/external-storage-reopen-v1/roundtrip.rbxm": (2739764, "dbfb34d6dc742c50c4b743fd7a5fc0e374599f3b8c81ea1e8f5d6baa455eb121"),
    "artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1/facts.json": (41912358, "b6b86b7871bab31d8fdebd9afa5cf3367426fad4e6a5eaef9038e4e8b1434f33"),
    "artifacts/cleanup-serverstorage-20261009/external-storage-reopen-v1/reopen-result.txt": (None, "03f29e1308f87adc045104700356a2865dc728adaca0faa04b3389a888ccfb82"),
}
verified = []
for path, (count, digest) in pinned_archives.items():
    raw = (ROOT / path).read_bytes()
    if count is None:
        # SHA pins the complete historical result; length is recorded from bytes.
        assert sha(raw) == digest
    else:
        assert (len(raw), sha(raw)) == (count, digest)
    verified.append({"path": path, "bytes": len(raw), "sha256": digest})
files = []
for path in sorted(OUT.iterdir()):
    assert path.is_file(), "Unexpected scratch directory in curated review"
    assert path.suffix != ".rbxmx", "Large regenerated XML must not enter commit"
    raw = path.read_bytes()
    files.append({"path": path.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": sha(raw)})
report = {"schema": "storage-next-compact-review-pins-v1", "nativeCalls": 0, "nativeWrites": 0,
    "indexWrites": 0, "commitWrites": 0, "restorationCertified": False, "normalizationApplied": False,
    "files": files, "unchangedHistoricalInputs": verified,
    "candidate": "artifacts/cleanup-20261010/storage-next-v1/restoration-supplement-probe-v2.luau",
    "candidateExecuted": False, "candidateStatus": "Prepared; new setter fault gate and pinned receiver remain pending before native execution",
    "scope": "Only NEW files under this review directory; concurrent working sources and manifest intentionally excluded. File-pins output itself is the sole additional review file."}
target = OUT / "file-pins.json"
assert not target.exists()
with target.open("xb") as stream:
    stream.write((json.dumps(report, indent=2) + "\n").encode())
print(json.dumps({"pass": True, "files": len(files), "bytes": sum(r["bytes"] for r in files), "nativeCalls": 0, "candidateExecuted": False}))
