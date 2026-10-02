"""Prove reuse of the fresh Studio checkpoint or retain its fresh capture.

This only reads export files and writes a local checkpoint. It never contacts
Studio. A native forest is reused only if the fresh entire-forest SHA, source
hash/class/editor receipts, root mapping, and saved service settings all agree.
"""
from __future__ import annotations
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

TASK = Path(__file__).resolve().parent
DEST = Path("/private/tmp/lobby-endfix-after-20261002")
PREVIOUS = Path("/private/tmp/lobby-endfix-before-20261002")
ROOT = TASK.parents[1]
EXPECTED_BEFORE_NATIVE_SHA = "95ce4ceacd09ef5b31759031d4c1dfe9fb2fe3eed60f1afe30d51cdf02635294"


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path): return json.loads(path.read_text())


def main():
    metadata = read(DEST / "metadata.json")
    old = read(PREVIOUS / "metadata.json")
    assert old["nativeSHA256"] == EXPECTED_BEFORE_NATIVE_SHA
    assert sha(PREVIOUS / "all-service-children.rbxm") == EXPECTED_BEFORE_NATIVE_SHA
    assert read(PREVIOUS / "checkpoint-install-gate.json")["verified"] is True
    sources = read(DEST / "scripts.json")
    previous_sources = read(PREVIOUS / "scripts.json")
    checks = []
    def check(value, label):
        checks.append({"passed": bool(value), "description": label})
        return bool(value)
    assert metadata["placeId"] == old["placeId"] == 131311258779917
    assert metadata["universeId"] == old["universeId"] == 10559217407
    assert len(sources) == metadata["scriptCount"] and all(row["editorMatch"] for row in sources)
    assert not metadata["editorConflicts"] and not metadata["skipped"]
    forest_hash_match = check(metadata["nativeSHA256"] == sha(PREVIOUS / "all-service-children.rbxm"),
                              "Fresh full native forest SHA256 equals previous checkpoint")
    forest_size_match = check(metadata["nativeBytes"] == old["nativeBytes"], "Fresh native byte length retained")
    forest_roots_match = check(metadata["roots"] == old["roots"], "Every native root path/class/order/descendant count retained")
    def index(rows):
        return {row["path"]: {"class": row["class"], "source": hashlib.sha256(row["source"].encode()).hexdigest(),
                              "editorMatch": row["editorMatch"]} for row in rows}
    check(index(sources) == index(previous_sources), "Every exact Source/class/editor receipt retained")
    for key in ["services", "collisionGroups", "collisionMatrix", "materialOverrides"]:
        check(metadata[key] == old[key], f"Fresh complete {key} receipt unchanged")
    reuse = all(row["passed"] for row in checks)
    # An unchanged freshly hashed native forest can provide its exact bytes even
    # if top-level service settings changed. Reconstruct a new native place from
    # the new settings in that case; never reuse the previous complete place.
    forest_reused = forest_hash_match and forest_size_match and forest_roots_match
    if forest_reused:
        shutil.copy2(PREVIOUS / "all-service-children.rbxm", DEST / "all-service-children.rbxm")
        for path in PREVIOUS.glob("native-part-*.bin"): shutil.copy2(path, DEST / path.name)
    else:
        chunks = [DEST / f"native-part-{index:05d}.bin" for index in range(metadata["nativeParts"])]
        if not all(path.exists() for path in chunks):
            (DEST / "checkpoint-reuse-proof.json").write_text(json.dumps({"reused": False, "checks": checks,
                "completeFreshNativeRequired": True}, indent=2) + "\n")
            raise RuntimeError("Fresh proof differs; full new native capture is required before a checkpoint can be claimed")
    # Store the exact transmitted metadata before adding local chunk bookkeeping.
    received_path = DEST / "metadata.received.json"
    if not received_path.exists():
        shutil.copy2(DEST / "metadata.json", received_path)
    received = read(received_path)
    assert all(metadata[key] == value for key, value in received.items()), "Transferred metadata changed"
    assert set(metadata) - set(received) <= {"scriptJsonParts"}, "Unexpected local metadata bookkeeping"
    metadata = dict(received)
    script_bytes = (DEST / "scripts.json").read_bytes()
    chunk_size = 750000
    metadata["scriptJsonParts"] = (len(script_bytes) + chunk_size - 1) // chunk_size
    for index in range(metadata["scriptJsonParts"]):
        (DEST / f"script-part-{index:05d}.jsonpart").write_bytes(script_bytes[index*chunk_size:(index+1)*chunk_size])
    (DEST / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    shutil.copy2(PREVIOUS / "service-property-schema.json", DEST / "service-property-schema.json")
    subprocess.run(["python3", str(ROOT / "tools/level6_build/import/assemble_native_backup.py"), str(DEST)], check=True)
    proof = {"schema": "lobby-r4-fresh-checkpoint-proof-v1", "reused": reuse, "checks": checks,
             "nativeForestReusedWithFreshHash": forest_reused,
             "freshCapturedAt": metadata["capturedAt"], "previousCapturedAt": old["capturedAt"],
             "nativeSHA256": metadata["nativeSHA256"], "nativeBytes": metadata["nativeBytes"],
             "sourceCount": len(sources), "editorConflicts": 0, "studioWritesPerformed": False,
             "nativeReconstructionNeeded": not reuse}
    if reuse:
        previous_place = PREVIOUS / "BeforeLobbyEndFix-AuthoritativeStudio.rbxl"
        new_place = DEST / "AfterLobbyEndFix-AuthoritativeStudio.rbxl"
        shutil.copy2(previous_place, new_place)
        report = read(PREVIOUS / "native-place-verification.json")
        report.update({"output": str(new_place), "nativePlaceSha256": sha(new_place),
                       "reusedWithFreshProof": True, "freshCapturedAt": metadata["capturedAt"],
                       "previousCheckpoint": str(PREVIOUS)})
        (DEST / "native-place-verification.json").write_text(json.dumps(report, indent=2) + "\n")
        proof["nativePlaceSHA256"] = sha(new_place)
        proof["nativePlaceBytes"] = new_place.stat().st_size
    (DEST / "checkpoint-reuse-proof.json").write_text(json.dumps(proof, indent=2) + "\n")
    print(json.dumps({"reused": reuse, "nativeBytes": metadata["nativeBytes"], "sourceCount": len(sources),
                      "freshCapturedAt": metadata["capturedAt"], "checksPassed": all(row["passed"] for row in checks)}))


if __name__ == "__main__": main()
