"""Root-only one-field native CAS, verified export, installed contract and rollback.

Default is offline proposal/compile verification. --apply is separately reviewed
and executed by the parent. No publishing, pushing, mode switches or bulk sync.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import copy
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
PUZZLE = "ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua"
MANIFEST = "studio-sync-manifest.json"
ART = "artifacts/cleanup-20261009/pending-locals-native-v1"
DEST = ART + "/latch-source-install-v1"
CHECKPOINT = ".git/mongotv-cleanup-20261009/latch-source-install-v1"
STUDIO = "1b603e69-7ae1-4572-b210-d5bf05c684ff"
spec = importlib.util.spec_from_file_location("latch_prepare", Path(__file__).with_name("prepare_latch_mode_probe.py"))
helpers = importlib.util.module_from_spec(spec);spec.loader.exec_module(helpers)
sha = helpers.sha
encoded = helpers.encoded
save = helpers.save
lf = helpers.lf


def item(manifest):
    rows = [row for row in manifest["items"] if row.get("file") == PUZZLE]
    assert len(rows) == 1, "Exact one PuzzleManager manifest row"
    return rows[0]


def project(raw, before_hash, after_hash, size):
    data = json.loads(raw);row = item(data)
    assert row["sha256"] == before_hash, "Target manifest Source baseline changed"
    result = copy.deepcopy(data);target = item(result)
    target["sha256"] = after_hash;target["bytes"] = size
    assert all(target.get(key) == row.get(key) for key in set(row) | set(target) if key not in ("sha256", "bytes"))
    return encoded(result)


def restore_row(current_raw, before_raw, proposed_raw):
    current, before, proposed = map(json.loads, (current_raw, before_raw, proposed_raw))
    live, old, own = item(current), item(before), item(proposed)
    # Restore only owned Source fields; other developers' metadata remains intact.
    assert all(live.get(key) == own.get(key) for key in ("sha256", "bytes")), "Foreign target Source row preserved"
    restored = copy.deepcopy(current)
    for key in ("sha256", "bytes"): item(restored)[key] = old[key]
    return encoded(restored)


def atomic_cas(path, before, after):
    """Compare bytes immediately before atomic replace; no stale forced restore."""
    assert path.read_bytes() == before, "Concurrent file edit; preserve it"
    temporary = path.with_name(path.name + ".mongotv-latch-cas.tmp")
    save(temporary, after)
    try:
        assert path.read_bytes() == before, "Concurrent file edit before replace; preserve it"
        os.replace(temporary, path)
        assert path.read_bytes() == after, "Concurrent file edit after replace; preserve it"
    finally:
        if temporary.exists(): temporary.unlink()


def git(root, *args):
    run = subprocess.run(["git", *args], cwd=root, capture_output=True, check=True)
    return run.stdout


def scope(root=ROOT):
    old = json.loads((root / ART / "latch-only/proposal.json").read_bytes())
    newer = json.loads((root / ART / "latch-only-v2/proposal.json").read_bytes())
    assert newer["pass"] and newer["beforeSHA256"] == old["beforeSHA256"] and newer["candidateSHA256"] == old["candidateSHA256"]
    before = (root / old["beforeFile"]).read_bytes();after = (root / old["candidateFile"]).read_bytes()
    assert sha(before) == old["beforeSHA256"] and sha(after) == old["candidateSHA256"]
    assert before.count(b"boxesDone = 0, boxCount = boxCount, latchMode = true,") == 1
    assert before.replace(b"boxesDone = 0, boxCount = boxCount, latchMode = true,", b"boxesDone = 0, boxCount = boxCount,", 1) == after
    assert sha(lf((root / PUZZLE).read_bytes())) == sha(before)
    target = old["originals"][0]
    request = {"nativeScriptCount": 212, "beforeSHA256": sha(before), "afterSHA256": sha(after),
               "targetProperties": target["properties"], "targetAttributes": target["attributes"], "targetTags": target["tags"]}
    template = Path(__file__).with_name("latch_mode_source_cas.luau").read_text(encoding="utf8")
    return before, after, old, newer, request, template


def native_code(template, request, operation, rows=None):
    value = {**request, "operation": operation}
    if rows is not None: value["rows"] = rows
    return template.replace("__REQUEST__", helpers.lua_literal(json.dumps(value, ensure_ascii=False)))


def validate_native(data, before, after, expected_hash, request, baseline=None):
    assert data["pass"] and data["operation"] in ("capture", "observe")
    source = data["targetSource"].encode();editor = data["targetEditor"].encode()
    assert source == editor and sha(source) == expected_hash and source in (before, after), "Native target Source/editor ambiguous"
    rows = data["rows"]
    assert len(rows) == request["nativeScriptCount"] and len({row["instanceId"] for row in rows}) == len(rows)
    target = next(row for row in rows if row["studioPath"] == "ServerScriptService.Level 1 Systems.PuzzleManager")
    assert target["instanceId"] == "1_408347" and target["parentId"] == "1_15621" and target["className"] == "Script"
    assert target["properties"] == request["targetProperties"] and target["attributes"] == request["targetAttributes"] and target["tags"] == request["targetTags"]
    assert target["sha256"] == expected_hash and target["bytes"] == len(source)
    if baseline is not None:
        prior = {row["instanceId"]: row for row in baseline}
        assert set(prior) == {row["instanceId"] for row in rows}, "Concurrent original identities changed"
        for row in rows:
            old = copy.deepcopy(prior[row["instanceId"]])
            if row["instanceId"] == "1_408347": old["sha256"] = expected_hash;old["bytes"] = len(source)
            assert row == old, "Other authoritative Source/metadata changed"
    return source, rows


def mirror_parity(root, raw, rows):
    manifest = json.loads(raw)
    scripts = [row for row in manifest["items"] if row.get("file") and row["className"] in ("Script", "LocalScript", "ModuleScript")]
    assert len(scripts) == len(rows) == manifest["counts"]["scripts"] == 212
    native = {row["studioPath"]: row for row in rows}
    assert len(native) == 212 and {row["studioPath"] for row in scripts} == set(native)
    for row in scripts:
        raw_source = lf((root / row["file"]).read_bytes());live = native[row["studioPath"]]
        assert sha(raw_source) == row["sha256"] == live["sha256"] and len(raw_source) == row["bytes"] == live["bytes"]
        assert row["className"] == live["className"] and row["segments"] == live["segments"]
        assert all(live["properties"].get(key) == value for key, value in row.get("properties", {}).items())
        assert row.get("attributes", []) == live["attributes"]
    return {"pass": True, "scripts": 212, "manifestRemoteEvents": manifest["counts"]["remoteEvents"], "sourceEditorCoverage": len(rows),
            "scope": "Source/editor/class/path/recorded properties/attributes. No non-script asset, remote behavior, round or streaming certificate."}


def console(client, studio):
    # Read-only console snapshot; absence of this API result is a material gate failure.
    return client.call("get_console_output", {"studio_id": studio})


def apply(root=ROOT, client_factory=None, git_reader=git):
    before, after, old, newer, request, template = scope(root)
    destination = root / DEST;checkpoint = root / CHECKPOINT
    assert not destination.exists() and not checkpoint.exists(), "Preserve immutable prior attempt"
    receipt_before = json.loads((root / ART / "native-before-v2-result.json").read_bytes())
    assert receipt_before["pass"] and receipt_before["originalsUnchanged"] and receipt_before["ownedLeaseReleased"]
    assert receipt_before["nativeInputSHA256"] == newer["nativeCodeHashes"]["before"]
    assert receipt_before["originalSourceCoverage"] == 212 and receipt_before["remainingProbes"] == 0
    source_raw = (root / PUZZLE).read_bytes();manifest_raw = (root / MANIFEST).read_bytes()
    revision = git_reader(root, "rev-parse", "HEAD").decode().strip()
    head_manifest = git_reader(root, "show", "HEAD:" + MANIFEST)
    assert item(json.loads(head_manifest))["sha256"] == sha(before)
    assert (root / PUZZLE).read_bytes() == source_raw and (root / MANIFEST).read_bytes() == manifest_raw
    proposed_manifest = project(manifest_raw, sha(before), sha(after), len(after))
    scoped_head = project(head_manifest, sha(before), sha(after), len(after))
    save(checkpoint / "repo-source.before.bin", source_raw);save(checkpoint / "manifest.before.json", manifest_raw)
    save(checkpoint / "head-manifest.before.json", head_manifest);save(checkpoint / "head-manifest.scoped-after.json", scoped_head)
    save(checkpoint / "metadata.json", encoded({"head": revision, "workingManifestSHA256": sha(manifest_raw), "sourceSHA256Raw": sha(source_raw)}))
    save(destination / ".gitattributes", b"* -text\n")
    if client_factory is None:
        sys.path.insert(0, str(root / "tools"))
        from sync_from_studio import StudioMcpClient, find_mcp_batch
        client_factory = lambda: StudioMcpClient(find_mcp_batch())
    client = client_factory();result = {"schema": "mongotv-latch-source-install-v1", "pass": False, "publishedByThisBatch": False,
        "file": PUZZLE, "bytesRemoved": 18, "headAtStart": revision, "productionNativeWritesRequested": 0,
        "rollback": {}, "limits": "Actual local-source contract, not full gameplay/multiplayer/streaming/assets/performance. File CAS is checked immediately before atomic replacement."}
    native_before = None;primary = None;source_written = False;manifest_written = False
    def call(operation, rows=None):
        code = native_code(template, request, operation, rows)
        save(checkpoint / (operation + ".luau"), code.encode())
        return json.loads(client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": code}))
    try:
        client.initialize()
        assert "Current Studio Mode: Edit" in client.call("get_studio_state", {"studio_id": STUDIO}), "Preserve owner's mode"
        native_before = call("capture")
        _, rows_before = validate_native(native_before, before, after, sha(before), request)
        save(checkpoint / "native-before.json", encoded(native_before))
        result["beforeParity"] = mirror_parity(root, manifest_raw, rows_before)
        result["consoleBefore"] = console(client, STUDIO)
        assert git_reader(root, "rev-parse", "HEAD").decode().strip() == revision, "Concurrent HEAD change before native CAS"
        assert (root / PUZZLE).read_bytes() == source_raw and (root / MANIFEST).read_bytes() == manifest_raw, "Concurrent local change before native CAS"
        result["productionNativeWritesRequested"] = 1
        result["nativeApply"] = call("apply", rows_before)
        assert result["nativeApply"]["pass"] and result["nativeApply"]["sourceSHA256"] == sha(after)
        observed = call("observe")
        native_export, rows_after = validate_native(observed, before, after, sha(after), request, rows_before)
        save(checkpoint / "native-after.json", encoded(observed))
        atomic_cas(root / PUZZLE, source_raw, native_export);source_written = True
        atomic_cas(root / MANIFEST, manifest_raw, proposed_manifest);manifest_written = True
        installed_code = (root / ART / "latch-only-v2/native-installed.luau").read_bytes()
        assert sha(installed_code) == newer["nativeCodeHashes"]["installed"]
        replay = json.loads(client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": installed_code.decode()}))
        save(destination / "native-installed-result.json", encoded({**replay, "nativeInputSHA256": sha(installed_code)}))
        assert replay["pass"] and replay["originalsUnchanged"] and replay["ownedLeaseReleased"] and replay["remainingProbes"] == 0
        assert replay["contract"]["checksPerVersion"] == 47 and replay["contract"]["pairedChecks"] == 94 and replay["contract"]["reentryChecks"] == 94
        # A distinct observation after installed replay prevents crediting a stale native export.
        final_code = native_code(template, request, "observe")
        save(checkpoint / "final-observe.luau", final_code.encode())
        final = json.loads(client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": final_code}))
        _, final_rows = validate_native(final, before, after, sha(after), request, rows_before)
        result["afterParity"] = mirror_parity(root, (root / MANIFEST).read_bytes(), final_rows)
        assert (root / PUZZLE).read_bytes() == native_export and (root / MANIFEST).read_bytes() == proposed_manifest
        result["consoleAfter"] = console(client, STUDIO)
        assert result["consoleBefore"] == result["consoleAfter"], "Console changed; review before retaining batch"
        assert git_reader(root, "rev-parse", "HEAD").decode().strip() == revision, "Concurrent HEAD change during batch"
        result.update({"pass": True, "beforeSourceSHA256": sha(before), "afterSourceSHA256": sha(after), "other211SourceRowsPreserved": True,
                       "workingOtherManifestRowsPreserved": True, "scopedHeadManifestSHA256": sha(scoped_head), "installedContractPassed": True})
    except BaseException as error:
        primary = error;result["error"] = str(error)
        # Query actual outcome even when UpdateSourceAsync/MCP threw. Never infer it from local bytes.
        if native_before is not None and result["productionNativeWritesRequested"]:
            try:
                code = native_code(template, request, "observe")
                save(checkpoint / "rollback-observe.luau", code.encode())
                current = json.loads(client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": code}))
                body = current["targetSource"].encode()
                assert body == current["targetEditor"].encode()
                if sha(body) == sha(after):
                    _, current_rows = validate_native(current, before, after, sha(after), request)
                    code = native_code(template, request, "rollback", current_rows)
                    save(checkpoint / "rollback.luau", code.encode())
                    rollback_result = json.loads(client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": code}))
                    assert rollback_result["pass"] and rollback_result["sourceSHA256"] == sha(before)
                    result["rollback"]["native"] = "exact own candidate reversed; fresh other originals preserved"
                elif sha(body) == sha(before): result["rollback"]["native"] = "already exact before; no restore write"
                else: result["rollback"]["native"] = "foreign Source preserved; manual reconciliation required"
            except BaseException as recovery:
                result["rollback"]["native"] = "unknown outcome/blocked recovery; no forced restore: " + str(recovery)
        for kind, written, path, previous, candidate in (
            ("source", source_written, root / PUZZLE, source_raw, after),
            ("manifest", manifest_written, root / MANIFEST, manifest_raw, proposed_manifest),
        ):
            if not written: continue
            try:
                current = path.read_bytes()
                restored = previous if kind == "source" else restore_row(current, previous, candidate)
                if kind == "source": assert current == candidate, "Foreign Source bytes preserved"
                atomic_cas(path, current, restored)
                result["rollback"][kind] = "own file/fields restored; foreign metadata preserved"
            except BaseException as recovery: result["rollback"][kind] = "foreign/unknown file preserved: " + str(recovery)
    finally:
        try: client.close()
        except BaseException as cleanup:
            result["clientCleanupError"] = str(cleanup);result["pass"] = False
            if primary is None: primary = cleanup
        result["completedAtUtc"] = datetime.now(timezone.utc).isoformat()
        save(destination / "result.json", encoded(result))
    assert primary is None and result["pass"], "Scoped install failed; inspect result/rollback, no forced overwrite"
    return result


def prepare():
    before, after, old, newer, request, template = scope()
    rows = [{**row, "sha256": row["sourceSHA256"], "bytes": len(before) if index == 0 else 0} for index, row in enumerate(old["originals"])]
    compiles = []
    with tempfile.TemporaryDirectory(prefix="mongotv-latch-cas-compile-") as directory:
        for operation in ("capture", "observe", "apply", "rollback"):
            code = native_code(template, request, operation, rows if operation in ("apply", "rollback") else None)
            path = Path(directory) / (operation + ".luau");path.write_bytes(code.encode())
            for optimization in ("-O0", "-O1"):
                run = subprocess.run([str(helpers.COMPILER), "--binary", optimization, str(path)], capture_output=True, timeout=15)
                assert run.returncode == 0, run.stderr.decode(errors="replace")
                compiles.append({"operation": operation, "optimization": optimization, "sourceSHA256": sha(code.encode()), "pass": True})
    proof = {"pass": True, "schema": "mongotv-latch-source-cas-offline-proposal-v1", "bytesRemoved": 18, "scope": PUZZLE,
             "beforeSHA256": sha(before), "afterSHA256": sha(after), "compileChecks": compiles, "nativeCalls": 0,
             "productionWrites": 0, "manifestWrites": 0, "templateSHA256": sha(template.encode()), "status": "pending independent wrapper/negative review and fresh native-before-v2"}
    destination = ROOT / ART / "latch-source-proposal-v1"
    save(destination / ".gitattributes", b"* -text\n");save(destination / "proposal.json", encoded(proof))
    print(json.dumps({"pass": True, "compileChecks": len(compiles), "nativeCalls": 0, "status": proof["status"]}))


def main():
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.apply:
        result = apply();print(json.dumps({key: result.get(key) for key in ("pass", "bytesRemoved", "installedContractPassed", "afterSourceSHA256")}))
    else: prepare()


if __name__ == "__main__": main()
