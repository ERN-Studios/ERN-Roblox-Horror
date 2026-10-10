"""Exercise the exact reused native probe's owned late-claim/release guards."""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
ART = Path(__file__).resolve().parent
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


def main():
    destination = ART / "ownership-gates-v1.json"
    assert not destination.exists(), "Immutable ownership receipt exists"
    metadata = json.loads((ART / "proposal-v1/proposal.json").read_bytes())
    template = (ART / "proposal-v1/native-template.luau").read_bytes()
    assert SHA(template) == metadata["nativeTemplateSHA256"]
    helper = ROOT / "tools/cleanup_20261009/prepare_latch_mode_probe_v2.py"
    spec = importlib.util.spec_from_file_location("reviewed_actual_lease_extractor", helper)
    helper_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper_module)
    program = helper_module.ownership_fixture(template.decode("utf8"))
    luau = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe")
    compiler = luau.with_name("luau-compile.exe")
    compiles = []
    with tempfile.TemporaryDirectory(prefix="preview-lease-") as directory:
        path = Path(directory) / "actual-lease.luau"
        path.write_bytes(program.encode())
        for opt in (0, 1):
            result = subprocess.run([str(compiler), "--binary", "-g0", f"-O{opt}", str(path)], capture_output=True, timeout=30)
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            compiles.append({"optimization": opt, "pass": True})
        result = subprocess.run([str(luau), str(path)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0 and result.stdout == "OWNERSHIP_CHECKS=20\n", result.stdout + result.stderr
    assert (ART / "proposal-v1/native-template.luau").read_bytes() == template
    receipt = {"pass": True, "ownershipCases": 8, "ownershipChecks": 20, "stdout": result.stdout,
               "compile": compiles, "programSHA256": SHA(program.encode()), "templateSHA256": SHA(template),
               "toolSHA256": SHA(Path(__file__).read_bytes()), "extractorPath": helper.relative_to(ROOT).as_posix(), "extractorSHA256": SHA(helper.read_bytes()),
               "nativeCalls": 0, "productionWrites": 0, "manifestWrites": 0}
    with destination.open("xb") as output:
        output.write((json.dumps(receipt, indent=2) + "\n").encode())
    print(json.dumps({"pass": True, "ownershipCases": 8, "ownershipChecks": 20, "nativeCalls": 0}))


if __name__ == "__main__":
    main()
