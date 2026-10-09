"""Prepare or verify only LE-34's two comment candidates and compiler behaviour.

Writes proposal/evidence files under artifacts/cleanup-20261009/le34-comments
and compiler inputs inside an automatically removed OS TemporaryDirectory.
Never writes authoritative sources, manifest, Studio or commits. Reuses C08's
official-bytecode parser; line-preserving edits also require raw-byte equality.
--verify-installed reconstructs old comments only in memory, verifies current
manifest/candidate hashes and writes a separate installed receipt. It preserves
every original proposal receipt and before/candidate file byte-for-byte.
"""
import argparse
import difflib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SHA = lambda value: hashlib.sha256(value).hexdigest()
SPECS = [
    {
        "key": "LayoutGenerator",
        "file": "ServerScriptService/Level 3 Systems/Level 3 Layout Generator.ModuleScript.lua",
        "line": 26,
        "old": "-- The district sizing is structural: ROOMS_PER_DISTRICT is the 2x4 room grid.",
        "new": "-- The district sizing is structural: ROOMS_PER_DISTRICT is the 2x5 room grid.",
        "semanticControlBefore": "local GRID_COLUMNS = 5",
        "semanticControlAfter": "local GRID_COLUMNS = 4",
    },
    {
        "key": "PuzzleManager",
        "file": "ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua",
        "line": 1548,
        "old": "\t-- exact one-box-per-player contract if the first spacing target is too strict.",
        "new": "\t-- exact ceil(n / 2) box count if the first spacing target is too strict.",
        "semanticControlBefore": "local boxCount = math.ceil(n / 2)",
        "semanticControlAfter": "local boxCount = math.ceil(n / 3)",
    },
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", default=os.environ.get("LUAU_COMPILE_BIN") or shutil.which("luau-compile"))
    parser.add_argument("--verify-installed", action="store_true", help="Verify current installed sources; preserve proposal files and save installed-compiler-check.json")
    args = parser.parse_args()
    if not args.compiler:
        parser.error("Set LUAU_COMPILE_BIN or --compiler to Luau0.737 luau-compile")
    verifier_spec = importlib.util.spec_from_file_location("c08_bytecode", Path(__file__).with_name("verify_C08.py"))
    verifier = importlib.util.module_from_spec(verifier_spec)
    verifier_spec.loader.exec_module(verifier)
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    entries = {entry["file"]: entry for entry in manifest["items"]}
    assert manifest["placeId"] == 131311258779917
    assert manifest["universeId"] == 10559217407
    output = Path(__file__).with_name("le34-comments")
    output.mkdir(exist_ok=True)
    preserved = {}
    originals = {}
    if args.verify_installed:
        original_receipt = output / "candidate-manifest.json"
        preserved[original_receipt] = original_receipt.read_bytes()
        proposal = json.loads(preserved[original_receipt])
        assert proposal["finding"] == "LE-34" and proposal["passed"] is True
        originals = {item["file"]: item for item in proposal["files"]}
        assert set(originals) == {item["file"] for item in SPECS}
        for item in originals.values():
            for key in ("beforeFile", "candidateFile"):
                evidence = ROOT / item[key]
                preserved[evidence] = evidence.read_bytes()
    result = {"finding": "LE-34", "mode": "installed verification" if args.verify_installed else "proposal preparation",
              "status": "installed source compiler identity verified; native receipts/commits owned by root" if args.verify_installed else "proposal only; awaits fresh native Source/editor CAS and root review",
              "productionMutations": 0, "studioCalls": 0, "runtimeFeatureRemovals": 0, "files": []}
    captured = {}
    with tempfile.TemporaryDirectory(prefix="le34-verify-") as folder:
        probe = Path(folder) / "source.luau"
        for spec in SPECS:
            path = ROOT / spec["file"]
            current_raw = path.read_bytes()
            captured[path] = current_raw
            current = current_raw.replace(b"\r\n", b"\n")
            old, new = spec["old"].encode(), spec["new"].encode()
            assert old.lstrip().startswith(b"-- ") and new.lstrip().startswith(b"-- ")
            assert b"\n" not in old and b"\n" not in new
            entry = entries[spec["file"]]
            assert entry["status"] == "synced" and entry["sourceEditorMatches"] is True
            assert SHA(current) == entry["sha256"], "Current file/manifest SHA mismatch"
            if args.verify_installed:
                original = originals[spec["file"]]
                assert current.count(new) == 1 and current.count(old) == 0, "Installed comment is not unique/exact"
                assert current.splitlines()[spec["line"] - 1] == new, "Installed anchor moved; reread"
                after_raw = current_raw
                before_raw = after_raw.replace(new, old, 1)
                assert SHA(before_raw) == original["beforeSha256Raw"]
                assert SHA(after_raw) == original["candidateSha256Raw"]
                assert SHA(before_raw.replace(b"\r\n", b"\n")) == original["beforeSha256Lf"]
                assert SHA(current) == original["candidateSha256Lf"]
                assert before_raw == preserved[ROOT / original["beforeFile"]]
                assert after_raw == preserved[ROOT / original["candidateFile"]]
                for key in ("studioPath", "className", "properties", "attributes"):
                    assert entry.get(key) == original.get(key), f"Installed metadata drift: {key}"
            else:
                before_raw = current_raw
                after_raw = before_raw.replace(old, new, 1)
            before = before_raw.replace(b"\r\n", b"\n")
            assert before.count(old) == 1, spec["file"]
            assert before.splitlines()[spec["line"] - 1] == old, "Baseline anchor moved; reread"
            after = after_raw.replace(b"\r\n", b"\n")
            assert after.count(b"\n") == before.count(b"\n")
            before_lines, after_lines = before.splitlines(), after.splitlines()
            assert len(before_lines) == len(after_lines)
            assert [i for i, pair in enumerate(zip(before_lines, after_lines)) if pair[0] != pair[1]] == [spec["line"] - 1]
            semantic_before = spec["semanticControlBefore"].encode()
            assert before.count(semantic_before) == 1
            semantic_mutant = before.replace(semantic_before, spec["semanticControlAfter"].encode(), 1)
            gates = []
            for optimization in (0, 1):
                binaries, dumps = {}, {}
                for label, body in (("before", before), ("candidate", after), ("semanticMutant", semantic_mutant)):
                    probe.write_bytes(body)
                    options = ["-g0", f"-O{optimization}", str(probe)]
                    binaries[label] = subprocess.run([args.compiler, "--binary", *options], check=True, capture_output=True, timeout=30).stdout
                    dumps[label] = subprocess.run([args.compiler, "--text", "--dump-constants", *options], check=True, capture_output=True, timeout=30).stdout
                assert binaries["before"] == binaries["candidate"], "Raw bytecode changed"
                assert dumps["before"] == dumps["candidate"], "Instruction/constant/upvalue dump changed"
                bytecode, metadata = verifier.canonical(binaries["before"])
                candidate_bytecode, candidate_metadata = verifier.canonical(binaries["candidate"])
                assert bytecode == candidate_bytecode and metadata == candidate_metadata
                mutant_bytecode, _ = verifier.canonical(binaries["semanticMutant"])
                assert bytecode != mutant_bytecode and dumps["before"] != dumps["semanticMutant"], "Verifier failed independent semantic negative control"
                gates.append({"optimization": optimization, "debug": 0, "functions": len(metadata),
                              "rawBytecodeIdentical": True, "rawBytecodeSHA256": SHA(binaries["before"]),
                              "rawBytecodeBytes": len(binaries["before"]), "canonicalBytecodeSHA256": SHA(bytecode),
                              "canonicalBytecodeIdentical": True, "protoMetadataIdentical": True,
                              "textWithConstantsIdentical": True, "textSHA256": SHA(dumps["before"]),
                              "semanticNegativeControlRejected": True})
            before_file = output / f"{spec['key']}.before.luau"
            candidate_file = output / f"{spec['key']}.candidate.luau"
            if not args.verify_installed:
                before_file.write_bytes(before_raw)
                candidate_file.write_bytes(after_raw)
            result["files"].append({"file": spec["file"], "studioPath": entry["studioPath"],
                "className": entry["className"], "properties": entry.get("properties"), "attributes": entry.get("attributes"),
                "beforeFile": before_file.relative_to(ROOT).as_posix(), "candidateFile": candidate_file.relative_to(ROOT).as_posix(),
                "beforeSha256Raw": SHA(before_raw), "candidateSha256Raw": SHA(after_raw),
                "beforeSha256Lf": SHA(before), "candidateSha256Lf": SHA(after),
                "beforeBytes": len(before_raw), "candidateBytes": len(after_raw), "line": spec["line"],
                "beforeComment": spec["old"], "candidateComment": spec["new"],
                "diff": "".join(difflib.unified_diff(before.decode().splitlines(keepends=True), after.decode().splitlines(keepends=True),
                    fromfile=spec["file"], tofile=spec["file"], n=2)), "results": gates})
    assert manifest_path.read_bytes() == manifest_bytes, "Manifest changed during preparation; reconcile"
    assert all(path.read_bytes() == data for path, data in captured.items()), "Source changed during preparation; reconcile"
    assert all(path.read_bytes() == data for path, data in preserved.items()), "Original proposal evidence changed"
    result["passed"] = True
    if args.verify_installed:
        result["originalProposalEvidenceUnchanged"] = True
        result["originalProposalEvidenceSHA256"] = {path.relative_to(ROOT).as_posix(): SHA(data) for path, data in preserved.items()}
        result["currentManifestSHA256"] = SHA(manifest_bytes)
    receipt = output / ("installed-compiler-check.json" if args.verify_installed else "candidate-manifest.json")
    receipt.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("LE-34 PASS: two exact comment-line substitutions; O0/O1 raw bytecode, all instructions/constants/upvalues and proto metadata identical.")
    print("Four independent semantic mutant checks rejected. Canonical files, manifest and Studio unchanged.")
    if args.verify_installed:
        print("Installed current sources match manifest and exact original proposal; all five proposal evidence files unchanged.")
    print(receipt.relative_to(ROOT).as_posix())


if __name__ == "__main__":
    main()
