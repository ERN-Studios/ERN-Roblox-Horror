"""S12: record native Enabled aliases in the downstream manifest only.

Default invocation is an offline proposal. --apply is parent-owned, brackets the
metadata transaction with the frozen read-only native reader, and never writes
Source, native properties/objects, switches mode, requires code or publishes.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import os
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from studio_source_contract import canonical_bytes
from retire_absent_codex_mirrors import prepare_manifest_temp

REFERENCE = ROOT / "artifacts/cleanup-serverstorage-20261009/final-parity-v2/after-S06-v4"
READER = REFERENCE / "parity-reader.py"
READER_SHA = "fcad91d8cdc4f32723393d995ae2ef4540fcf689bc661b6e792de75be9bf9a3d"
DEST = ROOT / "artifacts/cleanup-serverstorage-20261009/S12-enabled-metadata-v1"
CHECKPOINT = ROOT / ".git/mongotv-cleanup-20261009/s12-enabled-metadata-before-v1"
SOURCE_CLASSES = {"Script", "LocalScript", "ModuleScript"}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encode(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf8")


def save(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        assert stream.write(raw) == len(raw)
    assert path.read_bytes() == raw


def snapshot(directory, expected_gaps):
    report = json.loads((directory / "result.json").read_bytes())
    assert report["complete"] and report["sourceAndRecordedPropertyParity"] and report["declaredManifestCountsMatchActual"]
    assert report["nativeWrites"] == report["repositorySourceWrites"] == report["manifestWrites"] == report["modeSwitches"] == 0
    assert report["nativeSourceEditorConflictCount"] == 0 and report["manifestPropertyCoverageGapCount"] == expected_gaps
    assert report["studioId"] == "1b603e69-7ae1-4572-b210-d5bf05c684ff" and report["repoSnapshotStable"] is True
    assert not report["nativeScriptPropertyReadErrors"]
    assert all(not report[k] for k in ("mismatches", "missingNative", "extraNative", "extraWorkingFiles"))
    assert report["counts"]["nativeScripts"] == report["counts"]["actualManifestScripts"] == 212
    assert report["counts"]["nativeRemotes"] == report["counts"]["actualManifestRemotes"] == 15
    begin, end = report["nativeBegin"], report["nativeEnd"]
    assert begin["catalogSHA256"] == end["catalogSHA256"] and begin["rowCount"] == end["rowCount"] == 227
    assert begin["datamodel"] == end["datamodel"] == "Edit"
    assert (begin["placeId"], begin["universeId"]) == (end["placeId"], end["universeId"]) == (131311258779917, 10559217407)
    assert begin["sceneCount"] == end["sceneCount"] and begin["serverStorageRootCount"] == end["serverStorageRootCount"]
    rows = []
    pages = sorted(directory.glob("native-page-*.json"))
    assert [p.name for p in pages] == [f"native-page-{i:02}.json" for i in range(10)]
    for path in pages:
        page = json.loads(path.read_bytes())
        assert all(page["meta"][key] == begin[key] for key in ("catalogSHA256", "rowCount", "placeId", "universeId", "sceneCount", "serverStorageRootCount", "datamodel"))
        assert not page["meta"]["conflicts"] and page["meta"]["sourceEditorConflictCount"] == 0
        rows.extend(page["rows"])
    assert len(rows) == 227 and len({tuple(r["segments"]) for r in rows}) == 227
    for row in rows:
        if row["className"] in SOURCE_CLASSES:
            assert row["sourceReadable"] and row["editorReadable"] and row["sourceEditorMatches"] and row["readStable"]
    return rows, report


def proposal(raw, rows, verify_source=True):
    before = json.loads(raw)
    assert encode(before) == raw, "Unreviewed manifest formatting"
    native = {tuple(r["segments"]): r for r in rows}
    assert len(native) == len(rows) == len(before["items"]) == 227
    assert len({tuple(r["segments"]) for r in before["items"]}) == 227
    after, changes = copy.deepcopy(before), []
    for entry in after["items"]:
        row = native[tuple(entry["segments"])]
        assert row["className"] == entry["className"]
        if entry["className"] in SOURCE_CLASSES and verify_source:
            accepted = {row["sourceSHA256"]}
            if entry.get("studioTrailingNewline"):
                accepted.add(row.get("minusOneTrailingLFSHA256"))
            assert entry["sha256"] in accepted and entry["sourceEditorMatches"] is True
        for key, value in entry.get("properties", {}).items():
            assert key in row["properties"] and row["properties"][key] == value, "Recorded property drift"
        if "Enabled" not in row["properties"]:
            assert entry["className"] == "ModuleScript" or entry["className"] == "RemoteEvent"
            continue
        assert entry["className"] in ("Script", "LocalScript")
        enabled, disabled = row["properties"]["Enabled"], row["properties"]["Disabled"]
        assert type(enabled) is bool and type(disabled) is bool and enabled is not disabled
        assert type(entry["properties"]["Disabled"]) is bool and entry["properties"]["Disabled"] == disabled
        if "Enabled" in entry["properties"]:
            assert type(entry["properties"]["Enabled"]) is bool and entry["properties"]["Enabled"] == enabled
            continue
        entry["properties"]["Enabled"] = enabled
        changes.append({"studioPath": entry["studioPath"], "file": entry["file"], "className": entry["className"], "Enabled": enabled})
    assert len(changes) == 96
    assert after["counts"] == before["counts"] and len(after["items"]) == 227
    return encode(after), changes


def source_fingerprints(root, raw):
    found = {}
    for row in json.loads(raw)["items"]:
        if row["className"] not in SOURCE_CLASSES:
            continue
        path = root / row["file"]
        assert path.resolve().is_relative_to(root.resolve()) and not path.is_symlink()
        assert path.name.endswith("." + row["className"] + ".lua")
        data = path.read_bytes()
        canonical = canonical_bytes(data.decode("utf8"))
        assert sha(canonical) == row["sha256"] and len(canonical) == row["bytes"]
        assert row["sourceEditorMatches"] is True
        found[row["file"]] = sha(data)
    assert len(found) == 212
    return found


def rollback(current_raw, before_raw, proposed_raw):
    current, before, proposed = map(json.loads, (current_raw, before_raw, proposed_raw))
    assert encode(current) == current_raw, "Actor formatting preserved; manual rollback needed"
    before_rows = {r["studioPath"]: r for r in before["items"]}
    ours = {r["studioPath"]: r for r in proposed["items"]}
    assert len({r["studioPath"] for r in current["items"]}) == len(current["items"])
    conflicts = []
    for row in current["items"]:
        path = row["studioPath"]
        if path not in before_rows or "Enabled" in before_rows[path].get("properties", {}):
            continue
        if ours[path] == before_rows[path]:
            continue
        if row == ours[path]:
            row["properties"].pop("Enabled")
        elif row != before_rows[path]:
            conflicts.append(path)
    return encode(current), conflicts


def run_diagnostic(directory, expected_gaps):
    directory.mkdir(parents=True)
    reader = READER.read_bytes()
    assert sha(reader) == READER_SHA
    save(directory / "parity-reader.py", reader)
    subprocess.run([sys.executable, "-B", str(directory / "parity-reader.py")], cwd=ROOT, check=True)
    return snapshot(directory, expected_gaps)


def main(apply=False):
    manifest = ROOT / "studio-sync-manifest.json"
    if not apply:
        rows, _ = snapshot(REFERENCE, 96)
        proposed, changes = proposal(manifest.read_bytes(), rows)
        return {"scope": "offline proposal only", "EnabledFields": len(changes), "proposedSHA256": sha(proposed), "canonicalWrites": 0, "nativeCalls": 0}
    assert not CHECKPOINT.exists() and not DEST.exists(), "Refuse evidence/checkpoint overwrite"
    before = manifest.read_bytes()
    sources = source_fingerprints(ROOT, before)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT)
    head_raw = subprocess.check_output(["git", "show", "HEAD:studio-sync-manifest.json"], cwd=ROOT)
    reader_raw = READER.read_bytes()
    assert sha(reader_raw) == READER_SHA
    rows, native_before = run_diagnostic(DEST / "native-before", 96)
    proposed, changes = proposal(before, rows)
    scoped, head_changes = proposal(head_raw, rows, verify_source=False)
    assert head_changes == changes
    save(CHECKPOINT / "manifest-working-before.json", before)
    save(CHECKPOINT / "manifest-head-before.json", head_raw)
    save(CHECKPOINT / "manifest-working-proposed.json", proposed)
    save(CHECKPOINT / "manifest-head-scoped-for-commit.json", scoped)

    def inputs_guard():
        assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT) == head, "Actor HEAD changed"
        assert subprocess.check_output(["git", "show", "HEAD:studio-sync-manifest.json"], cwd=ROOT) == head_raw
        assert READER.read_bytes() == reader_raw
        assert source_fingerprints(ROOT, before) == sources, "Actor Source changed"

    temporary, committed = None, False
    try:
        inputs_guard()
        assert manifest.read_bytes() == before, "Actor working manifest changed"
        temporary = prepare_manifest_temp(manifest, proposed)
        inputs_guard()
        assert manifest.read_bytes() == before
        os.replace(temporary, manifest)
        temporary, committed = None, True
        assert manifest.read_bytes() == proposed
        _, native_after = run_diagnostic(DEST / "native-after", 0)
        inputs_guard()
        assert manifest.read_bytes() == proposed
        for key in ("catalogSHA256", "sceneCount", "serverStorageRootCount", "rowCount"):
            assert native_before["nativeBegin"][key] == native_after["nativeEnd"][key], "Native metadata changed"
        receipt = {"schema": "s12-enabled-manifest-metadata-v1", "pass": True, "EnabledFieldsAdded": 96,
                   "changes": changes, "manifestBeforeSHA256": sha(before), "manifestAfterSHA256": sha(proposed),
                   "scopedCommitManifestSHA256": sha(scoped), "headRevision": head.decode().strip(),
                   "countsUnchanged": json.loads(before)["counts"], "sourcesUnchanged": len(sources),
                   "nativeBefore": native_before, "nativeAfter": native_after,
                   "sourceWrites": 0, "nativeWrites": 0, "modeSwitches": 0, "published": False,
                   "scope": "96 downstream Enabled Boolean aliases only; Source/class/other properties/rows/top metadata preserved. No full assets/gameplay/continuous scene-epoch certificate."}
        save(DEST / "receipt.json", encode(receipt))
        return receipt
    except BaseException as error:
        conflicts = []
        if committed:
            recovery = None
            try:
                current = manifest.read_bytes()
                restored, conflicts = rollback(current, before, proposed)
                recovery = prepare_manifest_temp(manifest, restored)
                assert manifest.read_bytes() == current, "Actor manifest changed during rollback"
                os.replace(recovery, manifest)
                recovery = None
            except BaseException as problem:
                error.add_note("Scoped metadata rollback pending: " + str(problem))
            finally:
                if recovery is not None:
                    try: recovery.unlink(missing_ok=True)
                    except BaseException as problem: error.add_note("Rollback temporary cleanup: " + str(problem))
        try:
            save(DEST / "rollback.json", encode({"pass": False, "primaryError": str(error) or type(error).__name__, "primaryErrorType": type(error).__name__, "manifestCommittedBeforeRollback": committed,
                  "preservedActorRows": conflicts, "notes": getattr(error, "__notes__", [])}))
        except BaseException as problem:
            error.add_note("Rollback receipt write: " + str(problem))
        raise
    finally:
        if temporary is not None:
            primary = sys.exc_info()[1]
            try: temporary.unlink(missing_ok=True)
            except BaseException as problem:
                if primary is None: raise
                primary.add_note("Owned manifest temporary cleanup: " + str(problem))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Parent-reviewed actual metadata transaction; read-only native diagnostics bracket it.")
    result = main(parser.parse_args().apply)
    print(json.dumps({k: result[k] for k in result if k not in ("changes", "nativeBefore", "nativeAfter")}))
