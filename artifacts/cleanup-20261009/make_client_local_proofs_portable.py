"""Copy reviewed immutable inputs byte for byte; never touch production sources.

The proposal manifest's path metadata may be updated. Original checkpoint
inputs and prepared test receipts are read-only and checked after copying.
"""
from pathlib import Path
import hashlib
import json
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts/cleanup-20261009"
PROOFS = OUT / "client-local-proofs"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    manifest_path = OUT / "remaining-clients-proposals.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf8"))
    receipts = [OUT / name for name in [
        "client-local-existing-gates.json", "client-local-authoring-gate.json",
        "client-local-negative-controls.json", "client-local-T09-paired.json",
    ]]
    receipt_hashes = {path.name: digest(path.read_bytes()) for path in receipts}
    originals = {}
    copies = {}
    PROOFS.mkdir(exist_ok=True)
    # Prevent autocrlf from changing these byte-identical evidence inputs.
    attributes = PROOFS / ".gitattributes"
    expected_attributes = b"*.lua -text\n"
    if attributes.exists():
        # Root may suppress historical whitespace diagnostics without changing
        # these original evidence bytes. Preserve that reviewed configuration.
        directives = [line.strip() for line in attributes.read_text(encoding="utf8").splitlines()
                      if line.strip() and not line.lstrip().startswith("#")]
        assert directives in [["*.lua -text"], ["*.lua -text -whitespace"]]
    else:
        attributes.write_bytes(expected_attributes)
    for group in ["proposals", "installUnits"]:
        for index, row in enumerate(manifest[group]):
            for phase in ["before", "candidate"]:
                checkpoint = row.get(f"{phase}CheckpointPath", row[f"{phase}Path"])
                source = ROOT / checkpoint
                raw = source.read_bytes()
                source_hash = digest(raw.replace(b"\r\n", b"\n"))
                assert source_hash == row[f"{phase}Sha256"], (checkpoint, "changed proof input")
                byte_hash = digest(raw)
                portable = PROOFS / f"{byte_hash}.lua"
                if portable.exists():
                    assert portable.read_bytes() == raw, "portable input differs from immutable checkpoint"
                else:
                    portable.write_bytes(raw)
                originals[checkpoint] = byte_hash
                relative = portable.relative_to(ROOT).as_posix()
                row[f"{phase}CheckpointPath"] = checkpoint
                row[f"{phase}PortablePath"] = relative
                row[f"{phase}Path"] = relative
                row[f"{phase}ByteSha256"] = byte_hash
                entry = copies.setdefault(relative, {
                    "portablePath": relative, "byteSha256": byte_hash,
                    "sourceLfSha256": source_hash, "bytes": len(raw), "roles": [],
                })
                entry["roles"].append({
                    "group": group, "index": index, "file": row["file"],
                    "phase": phase, "checkpointPath": checkpoint,
                })
    for checkpoint, expected in originals.items():
        assert digest((ROOT / checkpoint).read_bytes()) == expected, "original checkpoint changed"
    for path in receipts:
        assert digest(path.read_bytes()) == receipt_hashes[path.name], "prepared receipt changed"
    index = {
        "productionWrites": False, "studioCalls": False,
        "byteIdenticalCopies": True, "originalCheckpointsUnchanged": True,
        "preparedReceiptsUnchanged": receipt_hashes,
        "uniquePortableInputs": len(copies), "portableBytes": sum(item["bytes"] for item in copies.values()),
        "copies": list(copies.values()),
        "note": "Source equality identifies reusable proof bytes, never native object/backup equivalence.",
    }
    manifest["portableProofIndex"] = "artifacts/cleanup-20261009/client-local-proofs/index.json"
    manifest["proofInputsPortable"] = True
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf8")
    (PROOFS / "index.json").write_text(json.dumps(index, indent=2) + "\n", encoding="utf8")
    print(json.dumps({key: value for key, value in index.items() if key != "copies"}, indent=2))


if __name__ == "__main__":
    main()
