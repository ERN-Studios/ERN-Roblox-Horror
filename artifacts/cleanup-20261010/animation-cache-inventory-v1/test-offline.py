"""Offline actual collector/driver ports only. Never calls Studio or production."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
LUAU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe")
LUNE = Path("C:/Users/mikke/AppData/Local/Temp/codex-lune-0.10.5/lune.exe")
SHA = lambda b: hashlib.sha256(b).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    output = args.receipt.resolve()
    assert output.is_relative_to(ROOT / "artifacts/cleanup-20261010") and output.parent.is_dir() and not output.exists()
    files = [HERE / "collector.luau", HERE / "offline-fixtures.luau", Path(__file__).resolve(), HERE / "run-root-inventory.py", HERE / "driver-fixtures.py"]
    raws = {p: p.read_bytes() for p in files}
    collector = raws[files[0]].decode().replace("\r\n", "\n")
    fixture = raws[files[1]].decode().replace("\r\n", "\n")
    assert fixture.count("__COLLECTOR__") == 1
    assembled = fixture.replace("__COLLECTOR__", collector).encode()
    receipt = {"schema": "mongotv-animation-cache-actual-offline-port-v1", "passed": False,
               "nativeCalls": 0, "productionWrites": 0,
               "inputs": [{"path": p.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)} for p, raw in raws.items()],
               "assembledFixtureSHA256": SHA(assembled), "assembledFixtureBytes": len(assembled),
               "limits": "Actual source replay uses synthetic game/Source/editor/metadata/task/shared/Encoding/JSON boundaries. No actual native cache, assets, scheduling, serialization, reference or deletion certificate; no gameplay/MP/streaming/performance pass."}
    try:
        with tempfile.TemporaryDirectory(prefix="mongotv-animation-cache-offline-") as folder:
            path = Path(folder) / "actual-collector-fixture.luau"
            path.write_bytes(assembled)
            compiled = subprocess.run([str(LUAU), str(path)], capture_output=True, text=True, timeout=30)
            receipt["compile"] = {"exitCode": compiled.returncode, "stderr": compiled.stderr[:8000]}
            assert compiled.returncode == 0, compiled.stderr
            replay = subprocess.run([str(LUNE), "run", str(path)], capture_output=True, text=True, timeout=180)
            receipt["exitCode"] = replay.returncode
            receipt["stderr"] = replay.stderr[:12000]
            receipt["stdout"] = replay.stdout[:50000]
            assert replay.returncode == 0, replay.stderr
            proof = json.loads(replay.stdout)
            assert proof["passed"] is True and proof["nativeCalls"] == 0 and proof["productionWrites"] == 0
            assert proof["cases"] >= 54 and all(row["nativeWrites"] == 0 for row in proof["results"])
            receipt["replay"] = proof
            del receipt["stdout"]
            spec = importlib.util.spec_from_file_location("cache_driver_offline_fixtures", HERE / "driver-fixtures.py")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            receipt["driverPort"] = module.run_tests()
            assert receipt["driverPort"]["passed"] is True and receipt["driverPort"]["cases"] == 27
            receipt["passed"] = True
    except BaseException as error:
        receipt["error"] = str(error)
        raise
    finally:
        for path, raw in raws.items():
            assert path.read_bytes() == raw, "Artifact changed during actual replay"
        with output.open("xb") as stream:
            stream.write((json.dumps(receipt, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({"passed": receipt["passed"], "cases": receipt["replay"]["cases"], "checks": receipt["replay"]["checks"],
                      "receiptSHA256": SHA(output.read_bytes()), "nativeCalls": 0}))


if __name__ == "__main__":
    main()
