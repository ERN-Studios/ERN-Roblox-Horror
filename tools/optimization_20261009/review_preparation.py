"""Inspect only this task's staged bytes; preserve the shared unrelated index."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
prefix = "tools/optimization_20261009/"
def git(*args):
    return subprocess.check_output(["git", *args], cwd=root)
paths = git("diff", "--cached", "--name-only", "-z", "--", prefix).decode().split("\0")
rows = []
for path in filter(None, paths):
    assert path.startswith(prefix)
    if path == prefix + "staged-review.json":
        continue  # A review receipt cannot include its own recursive content hash.
    raw = git("show", ":" + path)
    assert raw == (root / path).read_bytes(), "Unstaged/concurrent task change: " + path
    rows.append({"path": path, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
manifest = json.loads(git("show", ":" + prefix + "proposed-source-manifest.json"))
for row in manifest["scripts"]:
    for key in ("before", "after"):
        raw = git("show", ":" + row[key + "File"]) if row[key + "File"] else b""
        assert len(raw) == row[key + "Bytes"] and hashlib.sha256(raw).hexdigest() == row[key + "Sha256"]
effects = prefix + "effects/"
baseline = git("show", ":" + effects + "Level4LightDirector.baseline.lua").decode()
for replacement in json.loads(git("show", ":" + effects + "Level4LightDirector.replacements.json"))["replacements"]:
    assert baseline.count(replacement["old"]) == 1
    baseline = baseline.replace(replacement["old"], replacement["new"], 1)
assert baseline.encode() == git("show", ":" + effects + "Level4LightDirector.proposed.lua")
spectate = prefix + "loading/spectate/"
before = git("show", ":" + spectate + "GameManager.before.luau")
old = git("show", ":" + spectate + "spectate.before.luau")
new = git("show", ":" + spectate + "spectate.proposed.luau")
assert before.count(old) == 1 and before.replace(old, new, 1) == git("show", ":" + spectate + "GameManager.proposed.luau")
verification = json.loads(git("show", ":" + effects + "verification.json"))
for row in verification["Files"]:
    raw = git("show", ":" + effects + row["File"])
    assert len(raw) == row["Bytes"] and hashlib.sha256(raw).hexdigest().upper() == row["SHA256"]
subprocess.run(["git", "diff", "--cached", "--check", "--", prefix], cwd=root, check=True)
receipt = {
    "status": "Reviewed preparation only; owner Play preserved; no Studio writes or publish",
    "exactStagedBytesMatch": True, "sourceManifestPinsMatch": True,
    "lightDirectorScopedReplacementsMatch": True, "spectateScopedReplacementMatches": True,
    "whitespaceCheck": "passed; unified diff context markers excluded via attribute",
    "offlineContracts": {"loading": 51, "spectateFocus": 51, "geometry": 36, "effects": 36, "archive": 12},
    "nativeContractsExecuted": False, "gameplayVerified": False, "performanceMeasured": False,
    "files": rows,
}
(root / prefix / "staged-review.json").write_bytes((json.dumps(receipt, indent=2) + "\n").encode())
print("Reviewed", len(rows), "exact staged task files; source pins and scoped replacements match.")
