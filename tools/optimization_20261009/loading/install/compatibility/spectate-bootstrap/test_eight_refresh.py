"""Read-only input checks and in-memory guards for the scoped eight-source refresh.

All simulated writes/native calls are mocks. Only this test's result JSON is written.
"""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("eight_refresh_under_test", HERE / "refresh_eight_sources.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def main():
    checks = 0

    def check(condition, message):
        nonlocal checks
        assert condition, message
        checks += 1

    def reject(callback, message):
        nonlocal checks
        try:
            callback()
        except (AssertionError, KeyError, ValueError):
            checks += 1
        else:
            raise AssertionError(message)

    helper_hash = tool.sha((HERE / "refresh_eight_sources.py").read_bytes())
    rows, seven_raw, proposal_raw, old_gm = tool.inputs()
    pinned_studio = json.loads(seven_raw)["studioId"]
    bootstrap_capture = json.loads((HERE / "baseline-capture.json").read_bytes())
    check(pinned_studio == bootstrap_capture["studioId"] == "1b603e69-7ae1-4572-b210-d5bf05c684ff", "immutable export and fresh proposal capture pin the same authoritative Studio")
    current = json.loads(tool.GLOBAL.read_bytes())
    check(len(rows) == 8 and len({tuple(row["segments"]) for row in rows}) == 8, "exact eight input sources")
    check(len([row for row in rows if row["update"]]) == 2, "only two mirror replacements")
    check(old_gm["rawSourceSha256"] == "15771bdabc9fd070d6714a4386a5babe7354b3377c8e5c8f207d718c46ab804c", "immutable seven-source GM baseline")
    pins = [{**row["identity"], "segments": row["segments"], "class": row["class"],
        "rawBytes": len(row["source"].encode()), "sourceSha256": row["sha256"],
        "editorParity": True, "reviewedCandidateMatches": True,
        "properties": {"NativeObserved": True}, "attributes": {"NativeObserved": "read-only"}} for row in rows]
    targets = {pin["path"] for pin in pins}
    enriched = copy.deepcopy(current)
    enriched["concurrentOwnerMetadata"] = {"preserve": [1, {"nested": True}]}
    enriched["counts"]["concurrentCounter"] = 4711
    for item in enriched["items"]:
        if item["studioPath"] in targets:
            item["properties"]["OwnerConcurrentProperty"] = "keep"
            item["attributes"] = {"OwnerConcurrentAttribute": "keep"}
            item["concurrentOwnerNote"] = {"keep": item["studioPath"]}
            item["studioTrailingNewline"] = True
        else:
            item["concurrentForeignWork"] = {"keep": item["studioPath"]}
    immutable = copy.deepcopy(enriched)
    proposed, changes = tool.source_fields(enriched, pins)
    check(enriched == immutable, "source_fields never mutates caller data")
    check(len(changes) == 8, "exact eight source records")
    check([item for item in proposed["items"] if item["studioPath"] not in targets] ==
          [item for item in enriched["items"] if item["studioPath"] not in targets], "all foreign rows preserved")
    check({key: value for key, value in proposed.items() if key not in {"items", "counts"}} ==
          {key: value for key, value in enriched.items() if key not in {"items", "counts"}}, "all top-level metadata preserved")
    check({key: value for key, value in proposed["counts"].items() if key not in {"scripts", "total", "studioTrailingNewline"}} ==
          {key: value for key, value in enriched["counts"].items() if key not in {"scripts", "total", "studioTrailingNewline"}}, "operation totals and foreign count fields preserved")
    source_keys = {"bytes", "sha256", "status", "sourceEditorMatches", "studioTrailingNewline"}
    for pin in pins:
        before = next(item for item in enriched["items"] if item["studioPath"] == pin["path"])
        after = next(item for item in proposed["items"] if item["studioPath"] == pin["path"])
        check({key: value for key, value in before.items() if key not in source_keys} ==
              {key: value for key, value in after.items() if key not in source_keys}, "target properties/attributes/notes preserved")
        check(after["bytes"] == pin["rawBytes"] and after["sha256"] == pin["sourceSha256"] and
              after["status"] == "synced" and after["sourceEditorMatches"] is True and "studioTrailingNewline" not in after,
              "exact target source fields updated")
    check(proposed["counts"]["total"] == len(proposed["items"]), "total cardinality recomputed")
    check(tool.source_fields(proposed, pins)[0] == proposed, "source refresh is idempotent")
    reject(lambda: tool.source_fields(enriched, pins + [copy.deepcopy(pins[0])]), "nine pins with duplicate accepted")
    reject(lambda: tool.source_fields(enriched, pins[:-1]), "missing eighth pin accepted")
    for field, value in (("class", "Folder"), ("path", "ServerScriptService.Foreign"), ("segments", ["Wrong", "Path"])):
        wrong = copy.deepcopy(pins); wrong[0][field] = value
        reject(lambda wrong=wrong: tool.source_fields(enriched, wrong), "mismatched native pin accepted")
    duplicate = copy.deepcopy(enriched)
    duplicate["items"].append(copy.deepcopy(next(item for item in duplicate["items"] if item["studioPath"] in targets)))
    reject(lambda: tool.source_fields(duplicate, pins), "duplicate global target accepted")
    missing = copy.deepcopy(enriched); missing["items"] = [item for item in missing["items"] if item["studioPath"] != pins[-1]["path"]]
    reject(lambda: tool.source_fields(missing, pins), "missing global target accepted")
    for field in ("segments", "className", "file"):
        wrong = copy.deepcopy(enriched)
        item = next(item for item in wrong["items"] if item["studioPath"] == pins[0]["path"])
        item[field] = ["Wrong"] if field == "segments" else "wrong"
        reject(lambda wrong=wrong: tool.source_fields(wrong, pins), "wrong global source identity accepted")
    for field in ("placeId", "universeId"):
        wrong = copy.deepcopy(enriched); wrong[field] = 0
        reject(lambda wrong=wrong: tool.source_fields(wrong, pins), "wrong experience manifest accepted")

    native = {"complete": True, "readOnly": True, "pins": copy.deepcopy(pins)}
    check(tool.validate_native(native, rows) is native, "valid native packet returns exact packet")
    for field in ("complete", "readOnly"):
        wrong = copy.deepcopy(native); wrong[field] = False
        reject(lambda wrong=wrong: tool.validate_native(wrong, rows), "incomplete/non-read-only native packet accepted")
    for altered in (pins[:-1], pins + [pins[0]], [pins[0]] + pins[:-1], list(reversed(pins))):
        reject(lambda altered=altered: tool.validate_native({**native, "pins": altered}, rows), "wrong native cardinality/order accepted")
    for field, value in (("path", "Wrong.Path"), ("name", "Wrong"), ("instanceId", "wrong-id"), ("parentId", "wrong-parent"),
            ("parentPath", "Wrong.Parent"), ("parentClass", "WrongClass"), ("class", "Folder"),
            ("segments", ["Wrong"]), ("sourceSha256", "0" * 64), ("rawBytes", 0),
            ("editorParity", False), ("reviewedCandidateMatches", False)):
        wrong = copy.deepcopy(native); wrong["pins"][0][field] = value
        reject(lambda wrong=wrong: tool.validate_native(wrong, rows), "native identity/source/editor mismatch accepted")

    original_read, original_exists, original_file, original_symlink = Path.read_bytes, Path.exists, Path.is_file, Path.is_symlink
    overrides = {}

    def read(path):
        return overrides[path] if path in overrides else original_read(path)

    with patch.object(Path, "read_bytes", read), patch.object(Path, "write_bytes", side_effect=AssertionError("unexpected real helper write")):
        proposal = json.loads(proposal_raw)
        duplicate_proposal = copy.deepcopy(proposal); duplicate_proposal["scripts"].append(copy.deepcopy(proposal["scripts"][0]))
        overrides[tool.HERE / "source-install-manifest.json"] = tool.encoded(duplicate_proposal)
        reject(tool.inputs, "duplicate proposal source accepted")
        overrides.clear()
        missing_proposal = copy.deepcopy(proposal); missing_proposal["scripts"].pop()
        overrides[tool.HERE / "source-install-manifest.json"] = tool.encoded(missing_proposal)
        reject(tool.inputs, "missing proposal source accepted")
        overrides.clear()
        for row in rows:
            if not row["update"]:
                mirror = tool.ROOT / row["repositoryPath"]
                overrides[mirror] = row["source"].encode() + b"-- synthetic foreign edit\n"
                reject(tool.inputs, "one of six unchanged mirrors accepted unexpected source")
                overrides.clear()
                overrides[mirror] = row["source"].encode().replace(b"\n", b"\r\n")
                reject(tool.inputs, "unchanged native mirror accepted CRLF rather than exact bytes")
                overrides.clear()
        for row in rows:
            if not row["update"]:
                continue
            copy_row = row["copyRow"]; destination = copy_row["destination"]
            expected_before = "15771bdabc9fd070d6714a4386a5babe7354b3377c8e5c8f207d718c46ab804c" if row["segments"][-1] == "GameManager" else "e6c3cbf75efd01ca5363e68baafc2b6aad9beae23bec415a399f23d49240ddc9"
            check(tool.sha(copy_row["nativeBefore"]) == expected_before, "reviewed old GM/Spectate baseline pinned")
            for raw, state in ((copy_row["nativeBefore"], "exact-native-before"),
                    (copy_row["nativeBefore"].replace(b"\n", b"\r\n"), "native-before-with-CRLF-only"),
                    (copy_row["raw"], "already-exact-native-after"),
                    (copy_row["raw"].replace(b"\n", b"\r\n"), "native-after-with-CRLF-only")):
                overrides[destination] = raw
                before, record = tool.local_snapshot(copy_row)
                check(before == raw and record["acceptedLocalState"] == state, "guard accepts only exact reviewed before/after with CRLF-only normalization")
                overrides.clear()
            overrides[destination] = copy_row["nativeBefore"] + b"-- synthetic foreign edit\n"
            reject(lambda copy_row=copy_row: tool.local_snapshot(copy_row), "foreign local source accepted")
            overrides.clear()

    # Default and rejected apply exercise only mocked receipt writes/native transport.
    fake_receipt = HERE / "test-eight-refresh.synthetic-receipt.json"
    writes = []
    def write(path, raw):
        assert path == fake_receipt, "helper wrote outside simulated receipt before native guards"
        writes.append((path, bytes(raw)))
        return len(raw)
    def exists(path):
        return False if path == fake_receipt else original_exists(path)
    with patch.object(Path, "write_bytes", write), patch.object(Path, "exists", exists), patch.object(tool, "inputs", return_value=(rows, seven_raw, proposal_raw, old_gm)), \
            patch.object(tool, "StudioMcpClient", side_effect=AssertionError("default attempted Studio connection")), \
            patch.object(sys, "argv", ["refresh", "--receipt", fake_receipt.name]), contextlib.redirect_stdout(io.StringIO()):
        tool.main()
    receipt = json.loads(writes[-1][1])
    check(receipt["complete"] and receipt["globalShapePreflightPassed"] and not receipt["apply"], "default executes full local preflight")
    check(all(not receipt[key] for key in ("studioMutation", "nativeBackup", "gitStaged", "gitCommitted")), "default never connects/mutates/stages/backs up")

    writes.clear()
    wrong_global = copy.deepcopy(current)
    next(item for item in wrong_global["items"] if item["studioPath"] == pins[0]["path"])["className"] = "Folder"
    overrides[tool.GLOBAL] = tool.encoded(wrong_global)
    with patch.object(Path, "read_bytes", read), patch.object(Path, "write_bytes", write), patch.object(Path, "exists", exists), \
            patch.object(tool, "inputs", return_value=(rows, seven_raw, proposal_raw, old_gm)), \
            patch.object(sys, "argv", ["refresh", "--apply", "--receipt", fake_receipt.name]):
        reject(tool.main, "bad global shape reached mutation phase")
    overrides.clear()
    check(writes == [], "global shape rejected before export/mirror/global or receipt write")

    class FakeNative:
        def __init__(self): self.Calls = []
        def initialize(self): pass
        def close(self): self.Closed = True
        def call(self, *args):
            self.Calls.append(args)
            return json.dumps({**native, "pins": pins[:-1]})
    client = FakeNative(); writes.clear()
    with patch.object(Path, "write_bytes", write), patch.object(Path, "exists", exists), \
            patch.object(tool, "inputs", return_value=(rows, seven_raw, proposal_raw, old_gm)), \
            patch.object(tool, "StudioMcpClient", return_value=client), patch.object(tool, "find_mcp_batch", return_value="mock"), \
            patch.object(tool, "select_studio", side_effect=AssertionError("name-based Studio selection forbidden")), \
            patch.object(sys, "argv", ["refresh", "--apply", "--receipt", fake_receipt.name]):
        reject(tool.main, "truncated native response reached copy/export phase")
    check(client.Closed and json.loads(writes[-1][1])["complete"] is False, "failed native cardinality closes mocked client and leaves incomplete receipt")
    check(all(path == fake_receipt for path, _ in writes), "native cardinality fails before any export/mirror/global write")
    check(len(client.Calls) == 1 and client.Calls[0][0] == "execute_luau" and
          client.Calls[0][1]["studio_id"] == pinned_studio and client.Calls[0][1]["datamodel_type"] == "Edit",
          "native source verification targets the immutable original Edit Studio ID")

    wrong_capture = copy.deepcopy(bootstrap_capture); wrong_capture["studioId"] = "another-test-copy"
    overrides[HERE / "baseline-capture.json"] = tool.encoded(wrong_capture)
    client = FakeNative(); writes.clear()
    with patch.object(Path, "read_bytes", read), patch.object(Path, "write_bytes", write), patch.object(Path, "exists", exists), \
            patch.object(tool, "inputs", return_value=(rows, seven_raw, proposal_raw, old_gm)), \
            patch.object(tool, "StudioMcpClient", return_value=client), patch.object(tool, "find_mcp_batch", return_value="mock"), \
            patch.object(tool, "select_studio", side_effect=AssertionError("name-based Studio selection forbidden")), \
            patch.object(sys, "argv", ["refresh", "--apply", "--receipt", fake_receipt.name]):
        reject(tool.main, "cross-baseline Studio mismatch accepted")
    overrides.clear()
    check(client.Closed and client.Calls == [], "cross-baseline connection mismatch rejects before any native Studio call")
    check(all(path == fake_receipt for path, _ in writes) and json.loads(writes[-1][1])["complete"] is False,
          "cross-baseline mismatch cannot write exports/mirrors/global")
    check(tool.sha((HERE / "refresh_eight_sources.py").read_bytes()) == helper_hash, "helper remained unchanged during tests")
    result = {"offlineGuardChecks": checks, "helperSha256": helper_hash,
        "historicalSevenManifestSha256": hashlib.sha256(seven_raw).hexdigest(),
        "reviewedProposalManifestSha256": hashlib.sha256(proposal_raw).hexdigest(),
        "authoritativeStudioId": pinned_studio, "crossBaselineStudioGuardPassed": True,
        "globalAndRuntimeWrites": False, "studioConnected": False, "backupCreated": False,
        "allSimulatedWritesIntercepted": True, "initial99ContractReceiptUntouched": True}
    (HERE / "eight-refresh-test-result.json").write_bytes(tool.encoded(result))
    print(f"{checks} eight-source preservation/guard checks passed; real mirrors/global/Studio untouched.")


if __name__ == "__main__":
    main()
