"""Freeze compact public capture inputs after local evidence; no Studio/HTTP/index."""
from pathlib import Path
import hashlib
import json
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHA = lambda raw: hashlib.sha256(raw).hexdigest()
LUAU = "C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe"
ACTIVE_PY = ("raw_binary_refs.py", "receiver.py", "run-root-capture.py", "test-offline.py",
             "test-native-suffix.py", "observe-native-archive.py", "prepare-capture.py", "freeze-capture.py")


def save(path, value):
    with path.open("xb") as stream: stream.write((json.dumps(value, indent=2) + "\n").encode())


def main():
    target = HERE / "frozen-pins-v1.json"
    assert not target.exists() and not (HERE / "final-compile-v2.json").exists()
    for name in ("offline-tests-v3.json", "native-suffix-attempt-v2.json", "actual-native-archive-parser-observation-v3.json"):
        assert json.loads((HERE / name).read_bytes())["passed"] is True
    preparation = json.loads((HERE / "preparation-v1.json").read_bytes())
    for pin in preparation["inputs"]:
        raw = (ROOT / pin["path"]).read_bytes()
        assert len(raw) == pin["bytes"] and SHA(raw) == pin["sha256"]
    source = (HERE / "capture-source-template.luau").read_bytes()
    assert len(source) == preparation["sourceTemplate"]["bytes"] and SHA(source) == preparation["sourceTemplate"]["sha256"]
    result = subprocess.run([LUAU, str(HERE / "capture-source-template.luau")], stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    python_pins = []
    for name in ACTIVE_PY:
        raw = (HERE / name).read_bytes()
        compile(raw.decode("utf-8-sig"), name, "exec")
        python_pins.append({"path": (HERE / name).relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)})
    save(HERE / "final-compile-v2.json", {"schema": "retired-authoring-capture-final-compile-v2", "passed": True,
         "nativeCalls": 0, "receiverStarted": False, "templateSHA256": SHA(source), "templateBytes": len(source),
         "pythonUnits": len(python_pins), "pythonInputs": python_pins, "limits": "Syntax only; native/HTTP/raw current109 validation pending."})
    paths = [path for path in HERE.iterdir() if path.is_file() and path != target]
    external = ("AGENTS.md", "tools/cleanup_20261009/retired_authoring_archive_common.luau",
                "tools/sync_from_studio.py", "artifacts/cleanup-20261010/storage-restoration-v1/receiver.py",
                "artifacts/cleanup-20261010/storage-authoring-port-v2/native-run-v1/root-completion.json",
                "artifacts/cleanup-20261010/storage-authoring-port-v2/after-parity-v1/result.json",
                "artifacts/cleanup-20261010/storage-authoring-port-v2/after-parity-v1/native-begin.json",
                "artifacts/cleanup-20261010/storage-authoring-port-v2/after-parity-v1/native-end.json")
    paths.extend(ROOT / name for name in external)
    paths.extend(ROOT / ("artifacts/cleanup-20261010/storage-authoring-port-v2/after-parity-v1/native-page-%02d.json" % page)
                 for page in range(10))
    pins = []
    for path in sorted(set(paths), key=lambda path: path.relative_to(ROOT).as_posix()):
        assert path.resolve().is_relative_to(ROOT) and not path.is_symlink()
        raw = path.read_bytes()
        assert len(raw) <= 1000000, "Compact public file bound"
        assert b"request.private" not in path.name.encode() and b"root-api.private" not in path.name.encode()
        pins.append({"path": path.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)})
    evidence = [{"path": name, "bytes": len((ROOT / name).read_bytes()), "sha256": SHA((ROOT / name).read_bytes()),
                 "alreadyPreservedRawNotPublicCuration": True} for name in
                ("artifacts/cleanup-serverstorage-20261009/diagnostic-archive-before-v4/references.rbxm",
                 "artifacts/cleanup-serverstorage-20261009/retired-authoring-archive-v3/native.rbxm")]
    save(target, {"schema": "retired-authoring-raw-reference-capture-frozen-pins-v1", "nativeCalls": 0,
                  "receiverStarted": False, "deletionApproved": False, "pins": pins,
                  "preservedExistingRawEvidence": evidence, "sourceTemplateSHA256": SHA(source),
                  "limits": "Local immutable preparation only; Root native/API/HTTP/raw currentfields + remaining nonserialized holders pending."})
    print(json.dumps({"frozenPins": len(pins), "frozenPinsSHA256": SHA(target.read_bytes()), "templateSHA256": SHA(source),
                      "pythonUnits": len(python_pins), "nativeCalls": 0, "receiverStarted": False}))


if __name__ == "__main__": main()
