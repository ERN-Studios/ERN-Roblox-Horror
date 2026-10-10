"""Record the failed exact Lune constructor boundary without changing values."""
from pathlib import Path
import hashlib
import json
import subprocess

HERE = Path(__file__).resolve().parent
LUNE = Path("C:/Users/mikke/AppData/Local/Temp/codex-lune-0.10.5/lune.exe")
sha = lambda raw: hashlib.sha256(raw).hexdigest()
script = HERE / "lune-constructor-boundary.luau"
supplement = HERE / "restore-supplement.json"
result = subprocess.run([str(LUNE), "run", str(script), str(supplement)], capture_output=True, timeout=20)
assert result.returncode == 0, result.stderr.decode(errors="replace")
value = json.loads(result.stdout)
assert value["exact"] is False and value["changedComponents"] == 21
assert value["nativeCalls"] == 0 and value["normalizationApplied"] is False
receipt = {"schema": "storage-lune-constructor-boundary-receipt-v1", "exactConstructorPassed": False,
    "nativeCalls": 0, "normalizationApplied": False, "exitCode": result.returncode,
    "scriptSHA256": sha(script.read_bytes()), "supplementSHA256": sha(supplement.read_bytes()),
    "stdoutSHA256": sha(result.stdout), "result": value,
    "scope": "Lune 0.10.5 double/GetComponents exact boundary failed 21 components. Root's actual native readonly constructor result is separate; no epsilon or transport-data normalization accepted."}
with (HERE / "lune-constructor-boundary-result-v1.json").open("xb") as stream:
    stream.write((json.dumps(receipt, indent=2) + "\n").encode())
print(json.dumps({"exactConstructorPassed": False, "changedComponents": 21, "nativeCalls": 0}))
