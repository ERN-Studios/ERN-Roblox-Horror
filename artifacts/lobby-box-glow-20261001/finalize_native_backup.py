#!/usr/bin/env python3
"""Preserve a verified native capture and compact completeness receipts locally.

No Studio connection, reconstruction upload, git staging, or publication.
Run only after assemble_native_backup.py and pack_native_backup.luau pass.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--phase", choices=("before", "after"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scope-report", type=Path)
    args = parser.parse_args()
    source, target = args.input, args.output
    metadata = json.loads((source / "metadata.json").read_bytes())
    verification = json.loads((source / "native-place-verification.json").read_bytes())
    assert metadata["placeId"] == 131311258779917 and metadata["universeId"] == 10559217407
    assert not metadata["editorConflicts"] and not metadata["skipped"]
    assert not verification["sourceErrors"] and not verification["rootErrors"]
    assert verification["reopenedDescendants"] == verification["descendants"]
    assert verification["descendants"] == (metadata["expectedDescendants"] + len(metadata["services"])
                                              - len(verification["intentionallyOmitted"]))
    packed = Path(verification["output"])
    assert packed.is_file()
    target.mkdir(parents=True, exist_ok=True)
    native_name = args.phase.title() + "LobbyBoxGlow-AuthoritativeStudio.rbxl"
    records = []
    for file in sorted(source.iterdir()):
        if not file.is_file():
            continue
        output = target / (native_name if file == packed else file.name)
        if output.exists():
            assert output.read_bytes() == file.read_bytes(), "Refusing to overwrite different bytes: " + str(output)
        else:
            shutil.copyfile(file, output)
        records.append({"file": output.name, "bytes": output.stat().st_size, "sha256": digest(output)})
    scope = json.loads(args.scope_report.read_bytes()) if args.scope_report else None
    receipt = {
        "schema": "lobby-box-glow-native-completeness/1", "phase": args.phase,
        "authority": "Complete authoritative current Studio Edit capture. Verification only reconstructed local copies; no Studio world was restored or uploaded.",
        "placeId": metadata["placeId"], "universeId": metadata["universeId"],
        "capturedAt": metadata["capturedAt"], "observedPlaceVersion": metadata["placeVersion"],
        "nativePlace": native_name, "nativePlaceBytes": (target / native_name).stat().st_size,
        "nativePlaceSHA256": digest(target / native_name),
        "rawNativeSHA256": digest(target / "all-service-children.rbxm"),
        "scriptsJsonSHA256": digest(target / "scripts.json"),
        "sourceCount": metadata["scriptCount"], "sourceEditorConflicts": len(metadata["editorConflicts"]),
        "skippedRoots": len(metadata["skipped"]), "rootCount": metadata["rootCount"],
        "serviceCount": len(metadata["services"]), "nativeContentInstances": metadata["expectedDescendants"],
        "packedDescendants": verification["descendants"], "reopenedDescendants": verification["reopenedDescendants"],
        "unsupportedServicePropertyAssignments": len(verification["propertyErrors"]),
        "unreadableLiveServiceProperties": len(verification["limitations"]),
        "intentionallyOmitted": verification["intentionallyOmitted"],
        "sourceErrors": verification["sourceErrors"], "rootErrors": verification["rootErrors"],
        "scopeVerificationPassed": scope.get("passed") if scope else None,
        "localCaptureDirectory": str(source), "receiverStopped": True,
        "limitations": "Raw native child bytes and live service metadata are retained. The local place reconstruction has the property limitations and non-archivable engine omissions listed in native-place-verification.json. The reconstructed local place is never a deployment source."}
    (target / "native-completeness-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    (target / "cache-receipt.json").write_text(json.dumps({"inputDirectory": str(source),
        "fileCount": len(records), "files": records}, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
