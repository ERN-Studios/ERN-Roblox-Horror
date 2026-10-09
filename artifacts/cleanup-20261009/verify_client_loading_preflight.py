"""Prove the stale Loading proposal generator rejects before artifact writes."""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts/cleanup-20261009"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = json.loads((OUT / "remaining-clients-proposals.json").read_text(encoding="utf8"))
    index = json.loads((OUT / "client-local-proofs/index.json").read_text(encoding="utf8"))
    row = next(item for item in manifest["proposals"] if item["candidate"] == "C04" and item["file"] == "ReplicatedFirst/Lobby Loading Screen.LocalScript.lua")
    spec = importlib.util.spec_from_file_location("prepare_clients", OUT / "prepare_client_locals.py")
    prepare = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(prepare)
    before = (ROOT / row["beforePortablePath"]).read_text(encoding="utf8")
    current = (ROOT / row["file"]).read_text(encoding="utf8")
    prepare.preflight_loading_helper(before)
    rejection_rows = []
    for name, source in [
        ("current_active_caller", current),
        ("new_call", before + "\nlocal selected = announced()\n"),
        ("new_alias", before + "\nlocal resolver = announced\n"),
        ("duplicate_definition", before + prepare.ANNOUNCED_DEFINITION),
        ("changed_definition", before.replace('local function announced()', 'local function renamed()', 1)),
    ]:
        try:
            prepare.preflight_loading_helper(source)
        except AssertionError as error:
            rejection_rows.append({"case": name, "rejected": True, "reason": str(error)})
        else:
            raise AssertionError("Unsafe helper closure accepted: " + name)
    # Snapshot every prepared checkpoint input, portable blob and original raw
    # receipt plus manifest. The actual CLI must reject before even mkdir/write.
    targets = [OUT / "remaining-clients-proposals.json"]
    targets += [ROOT / item["portablePath"] for item in index["copies"]]
    targets += [OUT / name for name in index["preparedReceiptsUnchanged"]]
    targets += list(prepare.TEMP.rglob("*"))
    targets = sorted(set(path for path in targets if path.is_file()))
    snapshot = {str(path): sha(path) for path in targets}
    checkpoint_listing = sorted(str(path) for path in prepare.TEMP.rglob("*"))
    source_hashes = {file: sha(ROOT / file) for file in [row["file"], "StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua"]}
    run = subprocess.run([sys.executable, str(OUT / "prepare_client_locals.py"), "--compiler", manifest["compiler"]], capture_output=True, text=True, timeout=30)
    assert run.returncode != 0 and "announced has outside-definition references" in run.stderr, "Actual CLI did not reject active helper before preparation"
    assert snapshot == {str(path): sha(path) for path in targets}, "Prepared artifact overwritten during rejected CLI"
    assert checkpoint_listing == sorted(str(path) for path in prepare.TEMP.rglob("*")), "Rejected CLI created a checkpoint artifact"
    for file, expected in source_hashes.items():
        assert sha(ROOT / file) == expected, "Concurrent source changed during no-write gate: " + file
    for file, expected in index["preparedReceiptsUnchanged"].items():
        assert sha(OUT / file) == expected, "Historical raw receipt changed"
    receipt = {"productionWrites": False, "studioCalls": False, "historicalUncalledDefinitionAccepted": True,
               "unsafeClosuresRejected": rejection_rows, "actualCliExitCode": run.returncode,
               "actualCliStdout": run.stdout, "actualCliStderr": run.stderr,
               "preparedFilesChecked": len(targets), "noPreparedArtifactWrites": True,
               "checkpointInventoryUnchanged": True, "canonicalSourcesUnchanged": True,
               "rawReceiptsUnchanged": True}
    (OUT / "client-loading-preflight-gate.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    print(json.dumps({key: value for key, value in receipt.items() if key not in ["actualCliStdout", "actualCliStderr"]}, indent=2))


if __name__ == "__main__":
    main()
