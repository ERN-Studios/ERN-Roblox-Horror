"""Read-only S06 preflight; write NEW private checkpoints/proposals, never retire.

The native full-object archive/reload and owner approval remain independent
gates. This tool does not call Studio, require Luau, remove files, or replace
the working manifest. The resulting manifest proposals omit exactly12 sources
already outside the authoritative DataModel according to the pinned evidence.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
REVISION = "9ccb7ee748bc7a75df7de00ede28dd570be4ed9d"
COMBINED = ROOT / ".git/mongotv-cleanup-20261009/s05-sound-before/manifest-head-scoped-S03-S05-for-commit.json"
COMBINED_SHA = "c9c459e06000f292bd3083d104138fa8edc1112bdf4913a52d0b113c49458ab3"
EVIDENCE = ROOT / "artifacts/cleanup-serverstorage-20261009/external-storage-observation.json"
COMPILER = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe")
SCOPE = (
    ("PoolSlideContextDiagnosticBackup_0710", "Level 2 Pool Slide Controller"),
    ("PoolSlideContextDiagnosticBackup_0710", "Level 2 Pool Slide Navigator"),
    ("PoolSlideContextDiagnosticBackup_MP6_1609Z", "Controller"),
    ("PoolSlideContextDiagnosticBackup_MP6_1609Z", "Navigator"),
    ("PoolSlideContextDiagnosticBackup_MP7_1624Z", "Controller"),
    ("PoolSlideContextDiagnosticBackup_MP7_1624Z", "Navigator"),
    ("PoolSlideContextDiagnosticBackup_MP8_1633Z", "Controller"),
    ("PoolSlideContextDiagnosticBackup_MP8_1633Z", "Navigator"),
    ("PoolSlideContextDiagnosticBackup_MP8_1633Z", "NavigatorBeforeBudgetFix"),
    ("PoolSlideContextDiagnosticBackup_MP9_1640Z", "Controller"),
    ("PoolSlideContextDiagnosticBackup_MP9_1640Z", "Navigator"),
    ("TEMP_PipeEntityAnimations_20260909", "PreviewControls"),
)
PATHS = {f"ServerStorage.{folder}.{name}" for folder, name in SCOPE}
FILES = {f"ServerStorage/{folder}/{name}.ModuleScript.lua" for folder, name in SCOPE}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encode(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf8")


def validate(manifest_raw, evidence_raw, sources, head_sources):
    manifest, evidence = json.loads(manifest_raw), json.loads(evidence_raw)
    rows = {r["studioPath"]: r for r in manifest["items"]}
    assert len(rows) == len(manifest["items"]), "Duplicate manifest identity"
    assert evidence["schema"] == "external-storage-observation-v1"
    assert (evidence["placeId"], evidence["universeId"]) == (131311258779917, 10559217407)
    assert evidence["rootNativeWrites"] == 0 and not evidence["storagePortExists"]
    held = {r["pathBefore"]: r for r in evidence["heldOutOfGameSources"]}
    assert len(evidence["heldOutOfGameSources"]) == len(held) == 12 and set(held) == PATHS, "Native held-source allowlist changed"
    roots = {r["name"]: r for r in evidence["heldRemovedRoots"]}
    assert len(evidence["heldRemovedRoots"]) == len(roots) == 23, "Expected full23 externally removed roots"
    assert set(sources) == FILES == set(head_sources), "Source allowlist changed"
    records = []
    for studio_path in sorted(PATHS):
        row, native = rows[studio_path], held[studio_path]
        folder = row["segments"][1]
        assert row["segments"] == studio_path.split(".")
        expected_file = "/".join(row["segments"]) + ".ModuleScript.lua"
        assert row["file"] == expected_file and expected_file in FILES
        assert row["className"] == native["class"] == "ModuleScript"
        assert row["sourceEditorMatches"] is True
        assert row["properties"] == {"Archivable": True, "LinkedSource": ""}
        assert row["attributes"] == [] and not row.get("studioTrailingNewline", False)
        assert native["editorReadable"] and native["editorMatchesSource"] and native["sourceMatchesCapture"]
        assert roots[folder]["currentParent"] == "nil" and not roots[folder]["sameNameLive"]
        raw = sources[expected_file]
        canonical = raw.replace(b"\r\n", b"\n")
        assert canonical == head_sources[expected_file].replace(b"\r\n", b"\n"), "Concurrent selected local source edit"
        assert sha(canonical) == row["sha256"] == native["sourceSHA256"], "Mirror/native Source digest mismatch"
        assert len(canonical) == row["bytes"] == native["sourceBytes"], "Mirror/native Source length mismatch"
        records.append({"file": expected_file, "studioPath": studio_path, "className": "ModuleScript",
                        "rawBytes": len(raw), "rawSHA256": sha(raw),
                        "canonicalBytes": len(canonical), "canonicalSHA256": sha(canonical),
                        "properties": row["properties"], "attributes": row["attributes"]})
    return records


def proposal(manifest_raw):
    manifest = json.loads(manifest_raw)
    assert encode(manifest) == manifest_raw, "Preserve existing formatting; unexpected manifest serialization"
    before = {r["studioPath"]: r for r in manifest["items"]}
    assert len(before) == len(manifest["items"]) and PATHS <= before.keys()
    after = copy.deepcopy(manifest)
    after["items"] = [r for r in after["items"] if r["studioPath"] not in PATHS]
    after["counts"]["scripts"] = sum(r["className"] in ("Script", "LocalScript", "ModuleScript") for r in after["items"])
    after["counts"]["remoteEvents"] = sum(r["className"] == "RemoteEvent" for r in after["items"])
    after["counts"]["total"] = len(after["items"])
    remaining = {r["studioPath"]: r for r in after["items"]}
    assert remaining == {p: r for p, r in before.items() if p not in PATHS}
    # Same encoder/indentation means every surviving row's literal stays exact.
    assert all(encode(row) == encode(before[path]) for path, row in remaining.items())
    for key in manifest.keys() - {"items", "counts"}:
        assert after[key] == manifest[key], "Unrelated top-level metadata changed"
    for key in manifest["counts"].keys() - {"scripts", "remoteEvents", "total"}:
        assert after["counts"][key] == manifest["counts"][key], "Historical sync counters changed"
    return encode(after)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True, help="NEW private directory under this repo's .git")
    parser.add_argument("--receipt", type=Path, required=True, help="NEW safe JSON proof")
    args = parser.parse_args()
    checkpoint = args.checkpoint.resolve()
    assert checkpoint.is_relative_to((ROOT / ".git/mongotv-cleanup-20261009").resolve())
    assert not checkpoint.exists() and not args.receipt.exists(), "Refuse checkpoint/receipt overwrite"
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip()
    assert revision == REVISION, "HEAD changed; re-review current scoped manifest before preparing"
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest_raw, evidence_raw, combined_raw = manifest_path.read_bytes(), EVIDENCE.read_bytes(), COMBINED.read_bytes()
    assert sha(combined_raw) == COMBINED_SHA, "Combined S03/S05 proposal changed"
    sources = {}
    for file in sorted(FILES):
        path = ROOT / file
        assert path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(ROOT / "ServerStorage")
        sources[file] = path.read_bytes()
    head_sources = {file: subprocess.check_output(["git", "show", f"{revision}:{file}"], cwd=ROOT) for file in FILES}
    records = validate(manifest_raw, evidence_raw, sources, head_sources)
    assert validate(combined_raw, evidence_raw, sources, head_sources) == records
    working_proposal, scoped_proposal = proposal(manifest_raw), proposal(combined_raw)
    assert json.loads(working_proposal)["counts"]["scripts"] == 210
    assert json.loads(scoped_proposal)["counts"]["total"] == 225
    protected_path = ROOT / "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"
    protected_raw = protected_path.read_bytes()

    def guard():
        assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip() == revision
        assert manifest_path.read_bytes() == manifest_raw and EVIDENCE.read_bytes() == evidence_raw and COMBINED.read_bytes() == combined_raw
        assert all((ROOT / file).read_bytes() == raw for file, raw in sources.items()), "Concurrent selected source change"
        assert protected_path.read_bytes() == protected_raw, "Concurrent protected RoundUI change"

    guard()
    checkpoint.mkdir(parents=True)
    checkpoint_inputs = {"manifest-working-before.json": manifest_raw, "manifest-head-combined-before.json": combined_raw,
                         "native-observation-before.json": evidence_raw, "manifest-working-S06-proposal.json": working_proposal,
                         "manifest-head-S03-S05-S06-proposal.json": scoped_proposal}
    for name, raw in checkpoint_inputs.items():
        with (checkpoint / name).open("xb") as stream:
            assert stream.write(raw) == len(raw)
        assert (checkpoint / name).read_bytes() == raw
    compile_passes = 0
    for file, raw in sources.items():
        destination = checkpoint / "sources" / file
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("xb") as stream:
            assert stream.write(raw) == len(raw)
        assert destination.read_bytes() == raw
        for optimization in ("-O0", "-O1"):
            subprocess.run([str(COMPILER), "--binary", optimization, str(destination)], stdout=subprocess.DEVNULL, check=True)
            compile_passes += 1
    guard()
    receipt = {"schema": "external-mirror-retirement-preflight-v1", "batch": "S06", "atUtc": datetime.now(timezone.utc).isoformat(),
               "status": "afventer fuldt native23-objektarkiv/reload og afgrænset batchgodkendelse",
               "repoMutations": 0, "nativeMutations": 0, "sourceRequires": 0, "headRevision": revision,
               "nativeEvidenceFile": EVIDENCE.relative_to(ROOT).as_posix(), "nativeEvidenceSHA256": sha(evidence_raw),
               "records": records, "rawSourceBytes": sum(r["rawBytes"] for r in records),
               "canonicalSourceBytes": sum(r["canonicalBytes"] for r in records), "compilePassesO0O1": compile_passes,
               "compilerSHA256": sha(COMPILER.read_bytes()), "manifestWorkingSHA256": sha(manifest_raw),
               "helperSHA256": sha(Path(__file__).read_bytes()),
               "combinedManifestBeforeSHA256": sha(combined_raw), "workingProposalSHA256": sha(working_proposal),
               "scopedProposalSHA256": sha(scoped_proposal), "proposalCounts": json.loads(scoped_proposal)["counts"],
               "preservedSurvivingRows": 225, "protectedRoundUIBytesUnchanged": True,
               "scope": "Downstream proposal only. Source equality is not full-object rollback. Concurrent new native sources need their own fresh export; no final parity or gameplay pass."}
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    with args.receipt.open("xb") as stream:
        stream.write(encode(receipt))
    print(json.dumps({k: receipt[k] for k in ("batch", "repoMutations", "records", "compilePassesO0O1", "proposalCounts")}, indent=2))


if __name__ == "__main__":
    main()
