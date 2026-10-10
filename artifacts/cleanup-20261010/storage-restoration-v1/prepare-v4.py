"""Preserve V3 and fix only its proven lexical supplemental-variable bug."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
sha = lambda raw: hashlib.sha256(raw).hexdigest()
base = (HERE / "restoration-probe-v3.luau").read_bytes()
assert (len(base), sha(base)) == (29158, "c1c7406188bad76db369140bed57addc26d4302564f0c2161ce8441859cec629")
source = base.decode()
replacements = {
    'local KEY="__MongoTVExternalStorageSupplement20261010V3"': 'local KEY="__MongoTVExternalStorageSupplement20261010V4"',
    'local SCHEMA="external-held-storage-native-restoration-supplement-v3"': 'local SCHEMA="external-held-storage-native-restoration-supplement-v4"',
    '-- RESTORE SUPPLEMENT CONTRACT BEGIN: extract this exact helper offline.': 'local supplement -- Forward declaration: the helper must capture this local, never a global.\n-- RESTORE SUPPLEMENT CONTRACT BEGIN: extract this exact helper offline.',
    'local context,originalSnapshot,supplement': 'local context,originalSnapshot',
}
for old, new in replacements.items():
    assert source.count(old) == 1
    source = source.replace(old, new)
candidate = source.encode()
assert source.count("local supplement") == 2  # forward declaration plus supplemental HTTP bytes
assert source.index("local supplement --") < source.index("local function restoreFourCFrames")
assert "local context,originalSnapshot,supplement" not in source
with (HERE / "restoration-probe-v4.luau").open("xb") as stream:
    stream.write(candidate)
receipt = {"schema": "storage-restoration-lexical-fix-preparation-v4", "nativeCalls": 0,
    "nativeWrites": 0, "candidateExecutedNative": False, "restorationCertified": False,
    "normalizationApplied": False, "base": {"path": "restoration-probe-v3.luau", "bytes": len(base), "sha256": sha(base)},
    "candidate": {"path": "restoration-probe-v4.luau", "bytes": len(candidate), "sha256": sha(candidate)},
    "change": "Forward-declare local supplement before restoreFourCFrames; remove the later shadowing declaration. Version/key changes only otherwise.",
    "historicalV3Preserved": True}
with (HERE / "preparation-v4.json").open("xb") as stream:
    stream.write((json.dumps(receipt, indent=2) + "\n").encode())
print(json.dumps(receipt["candidate"]))
