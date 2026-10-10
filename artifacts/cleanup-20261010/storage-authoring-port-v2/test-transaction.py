"""Compile actual source and replay the unchanged transaction core with explicit fakes."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
LUAU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe")
LUNE = Path("C:/Users/mikke/AppData/Local/Temp/codex-lune-0.10.5/lune.exe")
sha = lambda raw: hashlib.sha256(raw).hexdigest()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--receipt", type=Path, required=True)
args = parser.parse_args()
target = args.receipt.resolve()
assert target.is_relative_to(ROOT / "artifacts/cleanup-20261010") and target.parent.is_dir() and not target.exists()
inputs = {name: (HERE / name).read_bytes() for name in ("transaction-core.luau", "transaction-faults.luau", "native-trial.luau", "trial-source.luau")}
receipt = {"schema": "retired-authoring-controlled-absence-offline-v1", "passed": False,
           "nativeCalls": 0, "inputs": [{"path": (HERE / k).relative_to(ROOT).as_posix(), "bytes": len(v), "sha256": sha(v)} for k, v in inputs.items()],
           "limits": "Actual core with fake scheduling/Parent/service guards. Compile is not native selector/absence/rollback/reference proof or deletion approval."}
try:
    with tempfile.TemporaryDirectory(prefix="mongotv-s04-transaction-") as temporary:
        temp = Path(temporary)
        (temp / "actual-core.luau").write_bytes(inputs["transaction-core.luau"] + b"\nreturn T\n")
        (temp / "fixture.luau").write_bytes(inputs["transaction-faults.luau"])
        compiles = []
        paths = [HERE / "trial-source.luau", temp / "actual-core.luau", temp / "fixture.luau"]
        for label, path in (("bake", ROOT / "ServerScriptService/LobbyReimaginedPreview/RuntimeBake.ModuleScript.lua"),
                            ("renderer", ROOT / "ServerScriptService/Level 1 Systems/BlenderRoomRenderer.ModuleScript.lua")):
            body = path.read_bytes().replace(b"\r\n", b"\n")
            wrapped = b"return function(game,script,workspace,Instance,require,task,coroutine,spawn,delay,wait,shared,_G)\n" + body + b"\nend"
            staged = temp / (label + ".luau")
            staged.write_bytes(wrapped)
            paths.append(staged)
            receipt[label + "WholeSourceFactory"] = {"sourceSHA256": sha(body), "sourceBytes": len(body), "factorySHA256": sha(wrapped)}
        for path in paths:
            compile_result = subprocess.run([str(LUAU), str(path)], capture_output=True, text=True, timeout=30)
            compiles.append({"unit": path.name, "exitCode": compile_result.returncode, "stderr": compile_result.stderr[:3000]})
            assert compile_result.returncode == 0, compiles[-1]
        receipt["compileUnits"] = compiles
        replay = subprocess.run([str(LUNE), "run", str(temp / "fixture.luau")], capture_output=True, text=True, timeout=60)
        receipt["fixtureExitCode"] = replay.returncode
        receipt["fixtureStderr"] = replay.stderr[:8000]
        assert replay.returncode == 0, replay.stderr
        receipt["replay"] = json.loads(replay.stdout)
        assert receipt["replay"]["passed"] and receipt["replay"]["cases"] == 51
        receipt["passed"] = True
except BaseException as error:
    receipt["error"] = str(error)
    raise
finally:
    for name, raw in inputs.items():
        assert (HERE / name).read_bytes() == raw, "Frozen candidate changed during replay"
    with target.open("xb") as stream:
        stream.write((json.dumps(receipt, ensure_ascii=False, indent=2) + "\n").encode())
print(json.dumps({"passed": True, "receipt": str(target), "sha256": sha(target.read_bytes()), "cases": receipt["replay"]["cases"], "checks": receipt["replay"]["checks"]}))
