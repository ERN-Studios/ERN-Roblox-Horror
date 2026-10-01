#!/usr/bin/env python3
"""Verify and export the scoped Level 6 entity/decor change from native Studio captures.

Local only. Never connects to Studio, rewrites game state, stages Git files, or
infers publication. Native root comparisons reuse the existing Lune extractor;
the source mirror always comes from the fresh native-after capture, not candidates.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TASK = ROOT / "artifacts/level6-entity-decor-20261001"
HERE = Path(__file__).resolve().parent
PLACE_ID = 131311258779917
UNIVERSE_ID = 10559217407
EXPECTED_ROOT = "ServerScriptService.Level 6 Systems"
EXPECTED_BEFORE_SCRIPTS = 203
EXPECTED_AFTER_SCRIPTS = 205
LEVEL3 = re.compile(r"(?:level[ _]?3|l3_)", re.IGNORECASE)


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha_file(path):
    return sha_bytes(path.read_bytes())


def read_json(path):
    return json.loads(path.read_text())


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def source_hash(row):
    return sha_bytes(row["source"].encode()) if row else None


def run_helper(command, timeout=240):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError("Local native helper failed: " + (result.stderr or result.stdout)[-1800:])
    return result.stdout


def prepare_capture(backup, lune):
    """Optionally assemble/pack a completed receiver capture with existing helpers."""
    run_helper(["python3", str(HERE / "assemble_native_backup.py"), str(backup)])
    run_helper([str(lune), "run", str(HERE / "pack_native_backup.luau"), str(backup)])


def capture_records(backup, blockers):
    metadata = read_json(backup / "metadata.json")
    entries = read_json(backup / "scripts.json")
    assert metadata["placeId"] == PLACE_ID and metadata["universeId"] == UNIVERSE_ID
    assert metadata["scriptCount"] == len(entries)
    mapped = {row["path"]: row for row in entries}
    assert len(mapped) == len(entries), "Duplicate native script paths"
    conflicts = [row["path"] for row in entries if row.get("editorMatch") is not True
                 or row.get("editorSource") or row.get("editorError")]
    if conflicts or metadata.get("editorConflicts"):
        blockers.append({"kind": "source-editor-conflict", "capture": backup.name,
                         "paths": sorted(set(conflicts + metadata.get("editorConflicts", [])))})
    if metadata.get("skipped"):
        blockers.append({"kind": "skipped-native-roots", "capture": backup.name,
                         "roots": metadata["skipped"]})
    return metadata, mapped


def extract_roots(backup, lune, temporary, phase):
    run_helper([str(lune), "run", str(HERE / "extract_native_revision_snapshot.luau"),
                str(backup), str(temporary), phase])
    return read_json(temporary / f"{phase}-native-snapshot.json")


def mirror_sources(task, scope, after, blockers):
    output = task / "verified-studio-mirror"
    records = []
    for expected in scope:
        row = after.get(expected["path"])
        if row is None or source_hash(row) != expected["afterSHA256"]:
            continue  # Do not create a misleading verified mirror after a source mismatch.
        if row.get("editorMatch") is not True or row.get("editorSource") or row.get("editorError"):
            continue
        data = row["source"].encode()
        tokens = row["path"].split(".")
        target = output.joinpath(*tokens[:-1], tokens[-1] + "." + row["class"] + ".luau")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        records.append({
            "studioPath": row["path"], "class": row["class"],
            "sourceSHA256": sha_bytes(data), "sourceBytes": len(data),
            "sourceEditorParity": True,
            "assetURIs": sorted(set(re.findall(r"rbxassetid://\d+", row["source"]))),
            "repositoryFile": str(target.relative_to(ROOT)),
        })
    if len(records) != 7:
        blockers.append({"kind": "incomplete-scoped-mirror", "expected": 7, "actual": len(records)})
    manifest = {
        "schema": "verified-studio-scoped-mirror/1", "placeId": PLACE_ID,
        "universeId": UNIVERSE_ID, "studioSourceIsAuthoritative": True,
        "capturedScriptsSHA256": sha_file(task / "native-after/scripts.json"),
        "scopedManifestSHA256": sha_file(task / "scoped-script-manifest.json"),
        "verifiedScripts": len(records), "scripts": records,
    }
    write_json(output / "manifest.json", manifest)
    return manifest


def copy_review_records(task):
    """Keep small reviewed evidence eligible for a scoped commit, excluding candidate copies."""
    source = task / "candidates/entity"
    destination = task / "verification/entity-reference"
    destination.mkdir(parents=True, exist_ok=True)
    for name in ("configuration-parity.json", "animation-references.json", "claude-review-receipt.json"):
        if (source / name).is_file():
            shutil.copyfile(source / name, destination / name)


def service_changes(before, after):
    # Reuse the prior read-only verifier's metadata comparison. Its hardcoded
    # task constants are not used by this pure helper.
    spec = importlib.util.spec_from_file_location("level6_native_helpers", HERE / "verify_revision_native_after.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.service_changes(before, after)


def reviewed_exceptions(path, before_dir, after_dir):
    if path is None:
        return {"scripts": [], "nativeRoots": [], "services": []}
    record = read_json(path)
    assert record["schema"] == "level6-preserved-concurrent-studio-differences/1"
    assert record["reviewed"] is True and record.get("reviewAuthority")
    assert record["beforeRawNativeSHA256"] == sha_file(before_dir / "all-service-children.rbxm")
    assert record["afterRawNativeSHA256"] == sha_file(after_dir / "all-service-children.rbxm")
    # These acknowledgements bind exact captured hashes/values. They must never
    # become a broad authorization to ignore a level or restore old contents.
    assert all(not LEVEL3.search(row["path"]) and not row["path"].startswith(EXPECTED_ROOT)
               for row in record["scripts"] + record["nativeRoots"])
    return record


def split_acknowledged(changes, accepted):
    acknowledged, unreviewed = [], []
    for change in changes:
        (acknowledged if change in accepted else unreviewed).append(change)
    # A stale/overbroad acknowledgement is also a mismatch, not a blanket allow.
    missing = [row for row in accepted if row not in changes]
    return acknowledged, unreviewed, missing


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", type=Path, default=TASK)
    parser.add_argument("--lune", type=Path, default=Path("/private/tmp/level6-lune-20261001/lune"))
    parser.add_argument("--prepare-native", action="store_true",
                        help="Assemble completed before/after receiver captures and reconstruct native places")
    parser.add_argument("--acknowledged-concurrent", type=Path,
                        help="Exact reviewed concurrent script/root/service delta bound to these raw capture hashes")
    args = parser.parse_args()
    if args.acknowledged_concurrent:
        args.acknowledged_concurrent = args.acknowledged_concurrent.resolve()
    task = args.task.resolve()
    before_dir, after_dir = task / "native-before", task / "native-after"
    scope_file = task / "scoped-script-manifest.json"
    scope = read_json(scope_file)
    if isinstance(scope, dict):
        scope = scope["scripts"]
    assert len(scope) == 7 and len({row["path"] for row in scope}) == 7
    assert sum(row.get("new") is True for row in scope) == 2
    assert all(row["path"].startswith(EXPECTED_ROOT + ".") for row in scope)
    if args.prepare_native:
        prepare_capture(before_dir, args.lune)
        prepare_capture(after_dir, args.lune)
    acknowledged = reviewed_exceptions(args.acknowledged_concurrent, before_dir, after_dir)
    blockers = []
    before_metadata, before = capture_records(before_dir, blockers)
    after_metadata, after = capture_records(after_dir, blockers)
    if len(before) != EXPECTED_BEFORE_SCRIPTS or len(after) != EXPECTED_AFTER_SCRIPTS:
        blockers.append({"kind": "unexpected-script-count", "expectedBefore": EXPECTED_BEFORE_SCRIPTS,
                         "actualBefore": len(before), "expectedAfter": EXPECTED_AFTER_SCRIPTS,
                         "actualAfter": len(after)})
    scoped = {row["path"]: row for row in scope}
    scoped_results = []
    for path, expected in scoped.items():
        old, new = before.get(path), after.get(path)
        checks = {
            "beforeSourceMatchesManifest": source_hash(old) == expected["beforeSHA256"],
            "afterSourceMatchesManifest": source_hash(new) == expected["afterSHA256"],
            "beforeAbsentExactlyWhenNew": (old is None) == expected.get("new", False),
            "afterExpectedClass": new is not None and new["class"] == expected.get("class", "ModuleScript"),
            "beforeExpectedClass": old is None or old["class"] == expected.get("class", "ModuleScript"),
            "afterEditorParity": new is not None and new.get("editorMatch") is True,
        }
        record = {"path": path, "checks": checks, "beforeSHA256": source_hash(old),
                  "afterSHA256": source_hash(new), "kind": "added" if old is None else "modified"}
        scoped_results.append(record)
        if not all(checks.values()):
            blockers.append({"kind": "scoped-source-mismatch", **record})
    unrelated_changes, level3_changes, unchanged_scripts = [], [], []
    level3_paths = []
    for path in sorted(set(before) | set(after)):
        if LEVEL3.search(path):
            level3_paths.append(path)
        if path in scoped:
            continue
        old, new = before.get(path), after.get(path)
        if old and new and old["class"] == new["class"] and source_hash(old) == source_hash(new):
            unchanged_scripts.append(path)
            continue
        change = {"path": path, "beforeSHA256": source_hash(old), "afterSHA256": source_hash(new),
                  "beforeClass": old["class"] if old else None, "afterClass": new["class"] if new else None,
                  "kind": "added" if old is None else "removed" if new is None else "changed"}
        (level3_changes if LEVEL3.search(path) else unrelated_changes).append(change)
    if level3_changes:
        blockers.append({"kind": "original-level3-source-changed", "changes": level3_changes})
    acknowledged_scripts, unreviewed_scripts, stale_scripts = split_acknowledged(unrelated_changes, acknowledged["scripts"])
    if unreviewed_scripts or stale_scripts:
        blockers.append({"kind": "unrelated-source-change-requires-review", "changes": unreviewed_scripts,
                         "acknowledgementsNotFound": stale_scripts})
    root_records, root_changes, level3_roots = [], [], []
    with tempfile.TemporaryDirectory(prefix="l6-entity-native-verify-") as directory:
        temporary = Path(directory)
        native_before = extract_roots(before_dir, args.lune, temporary, "before")
        native_after = extract_roots(after_dir, args.lune, temporary, "after")
        assert native_before["serializedScriptCount"] == len(before)
        assert native_after["serializedScriptCount"] == len(after)
        old_roots, new_roots = native_before["rootRecords"], native_after["rootRecords"]
        for path in sorted(set(old_roots) | set(new_roots)):
            old, new = old_roots.get(path), new_roots.get(path)
            record = {"path": path, "beforeClass": old["class"] if old else None,
                      "afterClass": new["class"] if new else None,
                      "beforeBytes": old["bytes"] if old else None,
                      "afterBytes": new["bytes"] if new else None,
                      "beforeSHA256": sha_file(temporary / old["file"]) if old else None,
                      "afterSHA256": sha_file(temporary / new["file"]) if new else None}
            unchanged = record["beforeSHA256"] == record["afterSHA256"] and record["beforeClass"] == record["afterClass"]
            record["unchanged"] = unchanged
            root_records.append(record)
            if LEVEL3.search(path):
                level3_roots.append(record)
                if not unchanged:
                    blockers.append({"kind": "original-level3-native-root-changed", **record})
            if not unchanged:
                root_changes.append(record)
        assert level3_roots, "No original Level 3 native roots were audited"
        changed_paths = {row["path"] for row in root_changes}
        if EXPECTED_ROOT not in changed_paths:
            blockers.append({"kind": "expected-level6-native-root-did-not-change"})
        others = [row for row in root_changes if row["path"] != EXPECTED_ROOT]
        acknowledged_roots, unreviewed_roots, stale_roots = split_acknowledged(others, acknowledged["nativeRoots"])
        if unreviewed_roots or stale_roots:
            blockers.append({"kind": "unrelated-native-root-change-requires-review", "changes": unreviewed_roots,
                             "acknowledgementsNotFound": stale_roots})
    native_places = []
    for backup, filename, expected_count in (
        (before_dir, "BeforeLevel6-AuthoritativeStudio.rbxl", len(before)),
        (after_dir, "AfterLevel6-AuthoritativeStudio.rbxl", len(after)),
    ):
        place = backup / filename
        packed = read_json(backup / "native-place-verification.json")
        assert place.is_file() and packed["nativePlaceBytes"] == place.stat().st_size
        assert packed["scriptCount"] == expected_count
        if packed["rootErrors"] or packed["sourceErrors"]:
            blockers.append({"kind": "native-place-reconstruction-error", "capture": backup.name,
                             "rootErrors": packed["rootErrors"], "sourceErrors": packed["sourceErrors"]})
        native_places.append({
            "phase": backup.name, "file": str(place.relative_to(ROOT)),
            "bytes": place.stat().st_size, "sha256": sha_file(place),
            "sourceErrors": len(packed["sourceErrors"]), "rootErrors": len(packed["rootErrors"]),
            "propertyAssignmentLimitations": len(packed["propertyErrors"]),
            "unreadableLivePropertyLimitations": len(packed["limitations"]),
            "reopenedDescendants": packed["reopenedDescendants"],
        })
    if native_places[-1]["bytes"] >= 100 * 1024 * 1024:
        blockers.append({"kind": "native-place-over-100MiB", "bytes": native_places[-1]["bytes"]})
    metadata_changes = service_changes(before_metadata, after_metadata)
    acknowledged_services, unreviewed_services, stale_services = split_acknowledged(metadata_changes, acknowledged["services"])
    if unreviewed_services or stale_services:
        blockers.append({"kind": "service-property-change-requires-review", "changes": unreviewed_services,
                         "acknowledgementsNotFound": stale_services})
    if args.acknowledged_concurrent:
        before_services = {row["class"]: row for row in before_metadata["services"]}
        after_services = {row["class"]: row for row in after_metadata["services"]}
        for expected in acknowledged["servicePropertyValues"]:
            assert before_services[expected["service"]]["properties"][expected["property"]] == expected["before"]
            assert after_services[expected["service"]]["properties"][expected["property"]] == expected["after"]
    mirror = mirror_sources(task, scope, after, blockers)
    copy_review_records(task)
    result = {
        "schema": "level6-entity-decor-native-verification/1", "placeId": PLACE_ID,
        "universeId": UNIVERSE_ID, "beforeObservedPlaceVersion": before_metadata["placeVersion"],
        "afterObservedPlaceVersion": after_metadata["placeVersion"],
        "studioIsAuthoritative": True, "scriptSourceEditorParity": not any(
            row["kind"] == "source-editor-conflict" for row in blockers),
        "beforeScriptCount": len(before), "afterScriptCount": len(after),
        "scopedScriptCount": len(scoped_results), "scopedScripts": scoped_results,
        "unrelatedScriptsUnchangedCount": len(unchanged_scripts), "otherScriptChanges": unrelated_changes,
        "originalLevel3ScriptPaths": sorted(level3_paths), "originalLevel3ScriptChanges": level3_changes,
        "originalLevel3NativeRoots": level3_roots, "allNativeRootCount": len(root_records),
        "allNativeRootRecords": root_records, "changedNativeRoots": root_changes,
        "serviceMetadataChanges": metadata_changes, "fullNativePlaces": native_places,
        "preservedConcurrentDifferences": {
            "acknowledgement": str(args.acknowledged_concurrent.relative_to(ROOT)) if args.acknowledged_concurrent else None,
            "reviewAuthority": acknowledged.get("reviewAuthority"),
            "scripts": acknowledged_scripts, "nativeRoots": acknowledged_roots,
            "services": acknowledged_services,
            "servicePropertyValues": acknowledged.get("servicePropertyValues", []),
            "unrelatedGameplayVerified": False,
        },
        "beforeRawNativeSHA256": sha_file(before_dir / "all-service-children.rbxm"),
        "afterRawNativeSHA256": sha_file(after_dir / "all-service-children.rbxm"),
        "beforeScriptsCaptureSHA256": sha_file(before_dir / "scripts.json"),
        "afterScriptsCaptureSHA256": sha_file(after_dir / "scripts.json"),
        "verifiedMirrorManifest": str((task / "verified-studio-mirror/manifest.json").relative_to(ROOT)),
        "verifiedMirrorManifestSHA256": sha_file(task / "verified-studio-mirror/manifest.json"),
        "verifiedMirrorScripts": mirror["verifiedScripts"],
        "blockers": blockers, "passed": not blockers,
        "limitations": [
            "Native per-root bytes are produced by the same Lune deserialize/reserialize method for both captures.",
            "The original jointly serialized raw .rbxm plus live service metadata are retained for recovery.",
            "Reconstructed .rbxl files retain recorded property-assignment/unreadable-property limitations; full service-property parity is not claimed.",
            "This local verifier does not establish gameplay, performance, multiplayer behavior, asset permissions or successful publication.",
        ],
    }
    output = task / "verification/native-after-verification.json"
    write_json(output, result)
    print(json.dumps({"passed": result["passed"], "scripts": [len(before), len(after)],
                      "verifiedMirrorScripts": mirror["verifiedScripts"],
                      "originalLevel3NativeRoots": len(level3_roots),
                      "unchangedUnrelatedScripts": len(unchanged_scripts),
                      "changedNativeRootPaths": [row["path"] for row in root_changes],
                      "blockerCount": len(blockers), "output": str(output.relative_to(ROOT))}, indent=2))
    if blockers:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
