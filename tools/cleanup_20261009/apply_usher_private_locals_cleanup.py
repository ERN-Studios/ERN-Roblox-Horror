"""Root-only pure private-helper native CAS, verified export, installed contract and rollback.

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
import types

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
TARGET_FILE = "ServerScriptService/Level 4 Systems/Level 4 Usher Controller.ModuleScript.lua"
MANIFEST = "studio-sync-manifest.json"
ART = "artifacts/cleanup-20261009/usher-private-locals-native-v1"
DEST = ART + "/usher-source-install-v1"
CHECKPOINT = ".git/mongotv-cleanup-20261009/usher-source-install-v1"
STUDIO = "1b603e69-7ae1-4572-b210-d5bf05c684ff"
spec = importlib.util.spec_from_file_location("usher_prepare", Path(__file__).with_name("prepare_usher_private_locals_probe.py"))
helpers = importlib.util.module_from_spec(spec);spec.loader.exec_module(helpers)
sha = helpers.sha
encoded = helpers.encoded
save = helpers.save
lf = helpers.lf


def item(manifest):
    rows = [row for row in manifest["items"] if row.get("file") == TARGET_FILE]
    assert len(rows) == 1, "Exact one Usher manifest row"
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
    temporary = path.with_name(path.name + ".mongotv-usher-private-locals-cas.tmp")
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
    newer=json.loads((root / ART / "proposal-v1/proposal.json").read_bytes())
    row=json.loads((root / "artifacts/cleanup-20261009/usher-locals/candidate-manifest.json").read_bytes())
    assert row["file"]==TARGET_FILE
    before=(root / row["beforeFile"]).read_bytes();after=(root / row["candidateFile"]).read_bytes()
    assert newer["pass"] and sha(before)==newer["beforeSHA256"]==helpers.BEFORE and sha(after)==newer["candidateSHA256"]==helpers.AFTER
    body=before.decode()
    for a,b in helpers.load_port().EDITS:
        assert body.count(a)==1
        body=body.replace(a,b,1)
    assert body.encode()==after and sha(lf((root / TARGET_FILE).read_bytes()))==sha(before)
    target=newer["originals"][0]
    assert target["studioPath"]=="ServerScriptService.Level 4 Systems.Level 4 Usher Controller"
    assert target["instanceId"]=="1_42775" and target["parentId"]=="1_15624" and target["sourceSHA256"]==sha(before)
    old={"beforeFile":row["beforeFile"],"candidateFile":row["candidateFile"],"originals":[target]}
    request={"nativeScriptCount":newer["nativeScriptCount"],"beforeSHA256":sha(before),"afterSHA256":sha(after),
             "targetProperties":target["properties"],"targetAttributes":target["attributes"],"targetTags":target["tags"]}
    assert request["nativeScriptCount"]==212 and len(before)-len(after)==86
    template=Path(__file__).with_name("usher_private_locals_source_cas.luau").read_text(encoding="utf8")
    return before,after,old,newer,request,template


def native_code(template, request, operation, rows=None, **extra):
    value = {**request, "operation": operation}
    if rows is not None: value["rows"] = rows
    value.update(extra)
    return template.replace("__REQUEST__", helpers.lua_literal(json.dumps(value, ensure_ascii=False)))


def validate_native(data, before, after, expected_hash, request, baseline=None):
    assert data["pass"] and data["operation"] in ("capture", "observe")
    summary = data["target"]
    assert summary["sourceEditorMatches"] and summary["sourceSHA256"] == summary["editorSHA256"] == expected_hash, "Native target Source/editor ambiguous"
    source = before if expected_hash == sha(before) else after
    assert sha(source) == expected_hash and summary["bytes"] == summary["editorBytes"] == len(source), "Native Source/editor byte counts changed"
    rows = data["rows"]
    assert len(rows) == request["nativeScriptCount"] and len({row["instanceId"] for row in rows}) == len(rows)
    target = next(row for row in rows if row["studioPath"] == "ServerScriptService.Level 4 Systems.Level 4 Usher Controller")
    assert target["instanceId"] == "1_42775" and target["parentId"] == "1_15624" and target["className"] == "ModuleScript"
    assert target["properties"] == request["targetProperties"] and target["attributes"] == request["targetAttributes"] and target["tags"] == request["targetTags"]
    assert target["sha256"] == expected_hash and target["bytes"] == len(source)
    assert all(summary[key] == target[key] for key in ("segments", "studioPath", "instanceId", "parentId", "className", "properties", "attributes", "tags"))
    if baseline is not None:
        prior = {row["instanceId"]: row for row in baseline}
        assert set(prior) == {row["instanceId"] for row in rows}, "Concurrent original identities changed"
        for row in rows:
            old = copy.deepcopy(prior[row["instanceId"]])
            if row["instanceId"] == "1_42775": old["sha256"] = expected_hash;old["bytes"] = len(source)
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


def bounded_source_reader(client, studio, segments):
    # Run the actual established read helper with an isolated globals dictionary.
    # No global tool setting, Source, staging buffer or compile probe is changed.
    sys.path.insert(0, str(ROOT / "tools"))
    import push_repo_to_studio as actual
    namespace = {**actual.read_studio_source.__globals__, "READ_CHUNK_LINES": 64}
    reader = types.FunctionType(actual.read_studio_source.__code__, namespace)
    class BoundedClient:
        def call(self, name, args):
            response = client.call(name, args)
            assert len(response.encode()) <= 8000, "Source read response exceeds bounded transport contract"
            return response
    return reader(BoundedClient(), studio, segments)


def apply(root=ROOT, client_factory=None, git_reader=git, source_reader=None):
    before, after, old, newer, request, template = scope(root)
    destination = root / DEST;checkpoint = root / CHECKPOINT
    assert not destination.exists() and not checkpoint.exists(), "Preserve immutable prior attempt"
    receipt_before = json.loads((root / ART / "usher-native-before-result.json").read_bytes())
    assert receipt_before["pass"] and receipt_before["originalsUnchanged"] and receipt_before["ownedLeaseReleased"]
    assert receipt_before["nativeInputSHA256"] == newer["nativeCodeHashes"]["before"]
    assert receipt_before["originalSourceCoverage"] == 212 and receipt_before["remainingProbes"] == 0
    assert receipt_before["contract"]["checksPerVersion"]==68 and receipt_before["contract"]["pairedChecks"]==136 and receipt_before["contract"]["reentryChecks"]==136
    assert receipt_before["probesCreated"]==receipt_before["probesDestroyed"]==4
    source_raw = (root / TARGET_FILE).read_bytes();manifest_raw = (root / MANIFEST).read_bytes()
    revision = git_reader(root, "rev-parse", "HEAD").decode().strip()
    head_manifest = git_reader(root, "show", "HEAD:" + MANIFEST)
    assert item(json.loads(head_manifest))["sha256"] == sha(before)
    assert (root / TARGET_FILE).read_bytes() == source_raw and (root / MANIFEST).read_bytes() == manifest_raw
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
    if source_reader is None:
        source_reader = bounded_source_reader
    client = client_factory();result = {"schema": "mongotv-usher-source-install-v1", "pass": False, "publishedByThisBatch": False,
        "file": TARGET_FILE, "bytesRemoved": 86, "headAtStart": revision, "productionNativeWritesRequested": 0,
        "rollback": {}, "limits": "Actual local-source contract, not full gameplay/multiplayer/streaming/assets/performance. File CAS is checked immediately before atomic replacement."}
    native_before = None;primary = None;source_written = False;manifest_written = False
    def call(operation, rows=None):
        code = native_code(template, request, operation, rows)
        save(checkpoint / (operation + ".luau"), code.encode())
        return json.loads(client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": code}))
    serial = 0
    def small_target(label):
        code = native_code(template, request, "target")
        save(checkpoint / (label + ".luau"), code.encode())
        response = client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": code})
        assert len(response.encode()) <= 20000, "Target response exceeds bounded transport contract"
        value = json.loads(response)
        assert value["pass"] and value["operation"] == "target"
        target = value["target"]
        assert target["instanceId"] == "1_42775" and target["parentId"] == "1_15624" and target["className"] == "ModuleScript"
        assert target["properties"] == request["targetProperties"] and target["attributes"] == request["targetAttributes"] and target["tags"] == request["targetTags"]
        assert target["sourceEditorMatches"] and target["sourceSHA256"] == target["editorSHA256"] and target["bytes"] == target["editorBytes"]
        return value
    def collect(operation, expected_hash):
        nonlocal serial
        serial += 1
        rows = [];catalog = None;target = None
        for first in range(1, 213, 20):
            code = native_code(template, request, operation, pageFirst=first, pageCount=20, expectedTargetSHA256=expected_hash)
            save(checkpoint / (f"snapshot-{serial}-{first:03}.luau"), code.encode())
            response = client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": code})
            assert len(response.encode()) <= 20000, "Metadata page exceeds bounded transport contract"
            page = json.loads(response)
            assert page["pass"] and page["operation"] == operation and page["totalRows"] == 212
            assert page["pageFirst"] == first and page["pageCount"] == 20
            assert len(page["rows"]) == min(20, 213-first)
            if catalog is None: catalog = page["catalogSHA256"];target = page["target"]
            assert page["catalogSHA256"] == catalog and page["target"] == target, "Native Source/metadata catalog changed between pages"
            save(checkpoint / (f"snapshot-{serial}-{first:03}.json"), encoded(page))
            rows.extend(page["rows"])
        assert len(rows) == len({row["instanceId"] for row in rows}) == 212
        # A final bounded target read confirms identity/Source/editor after the page series.
        final = small_target(f"snapshot-{serial}-target-final")
        assert final["target"] == target, "Target changed after metadata pages"
        return {"pass": True, "operation": operation, "target": target, "rows": rows, "catalogSHA256": catalog}
    def export_source(label, expected_hash, rows):
        start = small_target(label + "-before")
        assert start["target"]["sourceSHA256"] == expected_hash
        body = source_reader(client, STUDIO, ["ServerScriptService", "Level 4 Systems", "Level 4 Usher Controller"]).encode()
        end = small_target(label + "-after")
        assert start["target"] == end["target"] and sha(body) == expected_hash and len(body) == end["target"]["bytes"], "Chunked native Source export drift/truncation"
        # Recheck the complete originals/census after the final yielding chunk.
        code = native_code(template, request, "verify", rows, expectedTargetSHA256=expected_hash)
        save(checkpoint / (label + "-originals-final.luau"), code.encode())
        verified = json.loads(client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": code}))
        assert verified["pass"] and verified["operation"] == "verify" and verified["sourceSHA256"] == expected_hash and verified["originalSourceCoverage"] == 212
        return body
    try:
        client.initialize()
        assert "Current Studio Mode: Edit" in client.call("get_studio_state", {"studio_id": STUDIO}), "Preserve owner's mode"
        native_before = collect("capture", sha(before))
        _, rows_before = validate_native(native_before, before, after, sha(before), request)
        save(checkpoint / "native-before.json", encoded(native_before))
        native_before_source = export_source("native-before-source", sha(before), rows_before)
        assert native_before_source == before, "Exact native before Source differs from reviewed source"
        save(checkpoint / "native-target-source.before.bin", native_before_source)
        save(checkpoint / "native-target-editor.before.bin", native_before_source)
        result["beforeParity"] = mirror_parity(root, manifest_raw, rows_before)
        result["consoleBefore"] = console(client, STUDIO)
        assert git_reader(root, "rev-parse", "HEAD").decode().strip() == revision, "Concurrent HEAD change before native CAS"
        assert (root / TARGET_FILE).read_bytes() == source_raw and (root / MANIFEST).read_bytes() == manifest_raw, "Concurrent local change before native CAS"
        result["productionNativeWritesRequested"] = 1
        result["nativeApply"] = call("apply", rows_before)
        assert result["nativeApply"]["pass"] and result["nativeApply"]["sourceSHA256"] == sha(after)
        observed = collect("observe", sha(after))
        _, rows_after = validate_native(observed, before, after, sha(after), request, rows_before)
        native_export = export_source("native-after-source", sha(after), rows_after)
        assert native_export == after
        save(checkpoint / "native-after.json", encoded(observed))
        atomic_cas(root / TARGET_FILE, source_raw, native_export);source_written = True
        atomic_cas(root / MANIFEST, manifest_raw, proposed_manifest);manifest_written = True
        installed_code = (root / ART / "proposal-v1/native-installed.luau").read_bytes()
        assert sha(installed_code) == newer["nativeCodeHashes"]["installed"]
        replay = json.loads(client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": installed_code.decode()}))
        save(destination / "native-installed-result.json", encoded({**replay, "nativeInputSHA256": sha(installed_code)}))
        assert replay["pass"] and replay["originalsUnchanged"] and replay["ownedLeaseReleased"] and replay["remainingProbes"] == 0
        assert replay["contract"]["checksPerVersion"] == 68 and replay["contract"]["pairedChecks"] == 136 and replay["contract"]["reentryChecks"] == 136
        # A distinct observation after installed replay prevents crediting a stale native export.
        final = collect("observe", sha(after))
        _, final_rows = validate_native(final, before, after, sha(after), request, rows_before)
        result["afterParity"] = mirror_parity(root, (root / MANIFEST).read_bytes(), final_rows)
        assert (root / TARGET_FILE).read_bytes() == native_export and (root / MANIFEST).read_bytes() == proposed_manifest
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
                actual = small_target("rollback-observe")
                actual_hash = actual["target"]["sourceSHA256"]
                if actual_hash == sha(after):
                    current = collect("observe", sha(after))
                    _, current_rows = validate_native(current, before, after, sha(after), request)
                    assert export_source("rollback-candidate-source", sha(after), current_rows) == after
                    code = native_code(template, request, "rollback", current_rows)
                    save(checkpoint / "rollback.luau", code.encode())
                    rollback_result = json.loads(client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": code}))
                    assert rollback_result["pass"] and rollback_result["sourceSHA256"] == sha(before)
                    result["rollback"]["native"] = "exact own candidate reversed; fresh other originals preserved"
                elif actual_hash == sha(before): result["rollback"]["native"] = "already exact before; no restore write"
                else: result["rollback"]["native"] = "foreign Source preserved; manual reconciliation required"
            except BaseException as recovery:
                result["rollback"]["native"] = "unknown outcome/blocked recovery; no forced restore: " + str(recovery)
        for kind, written, path, previous, candidate in (
            ("source", source_written, root / TARGET_FILE, source_raw, after),
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
    with tempfile.TemporaryDirectory(prefix="mongotv-usher-private-locals-cas-compile-") as directory:
        for operation in ("capture", "observe", "target", "verify", "apply", "rollback"):
            code = native_code(template, request, operation, rows if operation in ("apply", "rollback", "verify") else None,
                               pageFirst=1, pageCount=20, expectedTargetSHA256=sha(before))
            path = Path(directory) / (operation + ".luau");path.write_bytes(code.encode())
            for optimization in ("-O0", "-O1"):
                run = subprocess.run([str(helpers.COMPILER), "--binary", optimization, str(path)], capture_output=True, timeout=15)
                assert run.returncode == 0, run.stderr.decode(errors="replace")
                compiles.append({"operation": operation, "optimization": optimization, "sourceSHA256": sha(code.encode()), "pass": True})
    proof = {"pass": True, "schema": "mongotv-usher-source-cas-offline-proposal-v1", "bytesRemoved": 86, "scope": TARGET_FILE,
             "beforeSHA256": sha(before), "afterSHA256": sha(after), "compileChecks": compiles, "nativeCalls": 0,
             "productionWrites": 0, "manifestWrites": 0, "templateSHA256": sha(template.encode()), "status": "pending independent wrapper/negative review and fresh usher-native-before"}
    destination = ROOT / ART / "usher-source-proposal-v1"
    if (destination / ".gitattributes").exists(): assert (destination / ".gitattributes").read_bytes() == b"* -text\n"
    else: save(destination / ".gitattributes", b"* -text\n")
    save(destination / "proposal.json", encoded(proof))
    print(json.dumps({"pass": True, "compileChecks": len(compiles), "nativeCalls": 0, "status": proof["status"]}))


def main():
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.apply:
        result = apply();print(json.dumps({key: result.get(key) for key in ("pass", "bytesRemoved", "installedContractPassed", "afterSourceSHA256")}))
    else: prepare()


if __name__ == "__main__": main()
