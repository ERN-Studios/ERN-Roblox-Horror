"""Correct only scoped path mapping in the unexecuted V1 candidate."""
from pathlib import Path
import hashlib
import json

OUT = Path(__file__).resolve().parent
source_path = OUT / "restoration-supplement-probe.luau"
raw = source_path.read_bytes()
sha = lambda value: hashlib.sha256(value).hexdigest()
assert (len(raw), sha(raw)) == (26444, "ac01f995b30b883c21ca982b071cd518fed722120e2498ff38341595cb5b27f1")
source = raw.decode()
before = ''' local originalsByPath,copiesByPath={},{}
 for original,row in rows do
  check(not originalsByPath[row.path],"ambiguous original path") originalsByPath[row.path]=original
 end
 for copy,row in snapshot.rows do
  check(not copiesByPath[row.path],"ambiguous owned-copy path") copiesByPath[row.path]=copy
 end'''
after = ''' local originalsByPath,copiesByPath,wantedPaths={},{},{}
 for _,spec in supplement.rows do
  check(type(spec.path)=="string" and not wantedPaths[spec.path],"duplicate/invalid supplemental path") wantedPaths[spec.path]=true
 end
 -- Historical animation forests legitimately repeat Keyframe/Pose names.
 -- Require uniqueness only for the four pinned targets; do not address or
 -- rewrite any unrelated same-name siblings.
 for original,row in rows do if wantedPaths[row.path] then
  check(not originalsByPath[row.path],"ambiguous supplemental original path") originalsByPath[row.path]=original
 end end
 for copy,row in snapshot.rows do if wantedPaths[row.path] then
  check(not copiesByPath[row.path],"ambiguous supplemental owned-copy path") copiesByPath[row.path]=copy
 end end'''
assert source.count(before) == 1
source = source.replace(before, after)
assert source.count("  copy.CFrame=wanted") == 1
source = source.replace("  copy.CFrame=wanted", "  report.testOwnedCFrameSetAttempts=(report.testOwnedCFrameSetAttempts or 0)+1\n  copy.CFrame=wanted")
source = source.replace('local KEY="__MongoTVExternalStorageSupplement20261010"', 'local KEY="__MongoTVExternalStorageSupplement20261010V2"')
source = source.replace('local SCHEMA="external-held-storage-native-restoration-supplement-v1"', 'local SCHEMA="external-held-storage-native-restoration-supplement-v2"')
candidate = source.encode()
assert source_path.read_bytes() == raw
with (OUT / "restoration-supplement-probe-v2.luau").open("xb") as stream:
    stream.write(candidate)
receipt = {"schema": "s06-restoration-supplement-preparation-v2", "nativeCalls": 0, "nativeWrites": 0,
    "candidateExecuted": False, "restorationCertified": False, "normalizationApplied": False,
    "beforeCandidate": {"path": source_path.name, "bytes": len(raw), "sha256": sha(raw)},
    "candidate": {"path": "restoration-supplement-probe-v2.luau", "bytes": len(candidate), "sha256": sha(candidate)},
    "preservedSupplement": {"path": "restore-supplement.json", "bytes": len((OUT / "restore-supplement.json").read_bytes()), "sha256": sha((OUT / "restore-supplement.json").read_bytes())},
    "reason": "V1 would reject 276 legitimate duplicate historical Keyframe/Pose paths before any setter. V2 validates uniqueness only for the four pinned Bone targets and separately records setter attempts for commit-then-throw diagnostics. V1 is preserved unexecuted, not certified.",
    "scope": "New candidate only. All guarded original/source/native SHA/reopen/cleanup and exact-component requirements retained."}
with (OUT / "supplement-preparation-v2.json").open("xb") as stream:
    stream.write((json.dumps(receipt, indent=2) + "\n").encode())
print(json.dumps({"pass": True, "candidateBytes": len(candidate), "candidateSHA256": sha(candidate), "nativeCalls": 0}))
