"""Offline guards for the receipt-only final native source reader.

Native calls and receipt writes are intercepted. Only this result is retained;
compiler fixtures are temporary local test files, never Studio probe objects.
"""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("source_reader_under_test", HERE / "check_eight_sources.py")
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

    expected, manifest_hash, sid = tool.load_expected()
    check(len(expected) == 8 and sid == tool.AUTHORITATIVE_STUDIO, "Eight current exact candidates in original Edit")
    protected = [tool.ROOT / row["expectedRepositoryPath"] for row in expected] + [tool.ROOT / "studio-sync-manifest.json", tool.MANIFEST]
    before = {path: tool.sha(path.read_bytes()) for path in protected}
    pins = [{**row["identity"], "segments": row["segments"], "class": row["class"],
        "rawBytes": row["rawBytes"], "sourceSha256": row["sha256"], "editorParity": True,
        "reviewedCandidateMatches": True, "properties": row["properties"], "attributes": row["attributes"]} for row in expected]
    good = {"complete": True, "readOnly": True, "verifiedUtc": "synthetic", "pins": pins}
    check(tool.validate_result(copy.deepcopy(good), expected) == good, "Complete exact native response accepted")
    for field, value in (("complete", False), ("readOnly", False)):
        wrong = copy.deepcopy(good); wrong[field] = value
        reject(lambda wrong=wrong: tool.validate_result(wrong, expected), "Incomplete/mutating native response accepted")
    for field, value in (("class", "Folder"), ("segments", ["Wrong"]), ("rawBytes", 0),
            ("sourceSha256", "0" * 64), ("editorParity", False), ("reviewedCandidateMatches", False)):
        wrong = copy.deepcopy(good); wrong["pins"][-1][field] = value
        reject(lambda wrong=wrong: tool.validate_result(wrong, expected), "Wrong eighth pin field accepted: " + field)
    for field in tool.IDENTITY_FIELDS:
        wrong = copy.deepcopy(good); wrong["pins"][-1][field] = "drift"
        reject(lambda wrong=wrong: tool.validate_result(wrong, expected), "Identity drift accepted: " + field)
    for altered in (pins[:-1], pins + [pins[0]], [pins[0]] * 8, list(reversed(pins))):
        wrong = copy.deepcopy(good); wrong["pins"] = copy.deepcopy(altered)
        reject(lambda wrong=wrong: tool.validate_result(wrong, expected), "Missing/duplicate/reordered native pins accepted")
    for field in ("Archivable", "LinkedSource", "Disabled", "RunContext"):
        wrong = copy.deepcopy(good); wrong["pins"][-1]["properties"][field] = "drift"
        reject(lambda wrong=wrong: tool.validate_result(wrong, expected), "Property drift accepted: " + field)
    for attributes in ({"UnexpectedAttribute": True}, {"Unsupported": {}}, None):
        wrong = copy.deepcopy(good); wrong["pins"][-1]["attributes"] = attributes
        reject(lambda wrong=wrong: tool.validate_result(wrong, expected), "Attribute drift/unsupported value accepted")
    check(tool.primitive_map([]) == {}, "Native empty maps normalize consistently")
    for value in ([1], {"x": float("nan")}, {"x": float("inf")}, {"x": []}):
        reject(lambda value=value: tool.primitive_map(value), "Invalid primitive map accepted")

    real_read = Path.read_bytes
    manifest = json.loads(tool.MANIFEST.read_bytes())
    def load_with(changed, capture_sid=None, changed_raw=None):
        def read(path):
            if path == tool.MANIFEST:
                return json.dumps(changed).encode()
            if capture_sid is not None and path == HERE / "baseline-capture.json":
                capture = json.loads(real_read(path)); capture["studioId"] = capture_sid
                return json.dumps(capture).encode()
            if changed_raw is not None and path == (tool.ROOT / manifest["scripts"][-1]["rawFile"]).resolve():
                return changed_raw
            return real_read(path)
        with patch.object(Path, "read_bytes", read):
            return tool.load_expected()
    for field, value in (("complete", False), ("readOnly", False), ("datamodel", "Server"),
            ("placeId", 1), ("universeId", 1), ("historicalSevenManifestSha256", "0" * 64)):
        wrong = copy.deepcopy(manifest); wrong[field] = value
        reject(lambda wrong=wrong: load_with(wrong), "Malformed capture accepted: " + field)
    for field, value in (("class", "Script"), ("sourceSha256", "0" * 64), ("rawBytes", 0),
            ("editorParity", False), ("rawUtf8Verified", False), ("reviewedCandidateMatches", False),
            ("rawFile", "../outside-scope.lua"), ("instanceId", ""), ("name", "Wrong"),
            ("parentPath", "Wrong"), ("properties", {"Archivable": True})):
        wrong = copy.deepcopy(manifest); wrong["scripts"][-1][field] = value
        reject(lambda wrong=wrong: load_with(wrong), "Malformed capture row accepted: " + field)
    wrong = copy.deepcopy(manifest); wrong["scripts"][-1] = copy.deepcopy(wrong["scripts"][0])
    reject(lambda: load_with(wrong), "Duplicate candidate path accepted")
    reject(lambda: load_with(manifest, capture_sid="test-copy"), "Wrong Studio connection accepted")
    reject(lambda: load_with(manifest, changed_raw=b"changed"), "Changed raw captured bytes accepted")

    output = tool.TASK / "runtime/source-check-mocked-only.json"
    check(not output.exists(), "Test receipt path is fresh")
    writes = []
    clients = []
    class Client:
        def __init__(self, _):
            self.initialized = False; self.closed = False; self.calls = []
            clients.append(self)
        def initialize(self):
            self.initialized = True
        def call(self, name, arguments):
            self.calls.append((name, arguments))
            check(name == "execute_luau" and arguments["studio_id"] == sid and arguments["datamodel_type"] == "Edit", "Pinned read-only Edit call")
            check(arguments["code"] == tool.make_code(expected), "Only exact source-read code called")
            return json.dumps(good)
        def close(self):
            self.closed = True
    def write(path, raw):
        check(path == output, "Only task-runtime receipt written")
        writes.append(json.loads(raw))
        return len(raw)
    with patch.object(tool, "StudioMcpClient", Client), patch.object(tool, "find_mcp_batch", lambda: "mock"), \
            patch.object(Path, "write_bytes", write), patch.object(Path, "mkdir", lambda *a, **k: None), \
            patch.object(sys, "argv", ["reader", "--receipt", output.relative_to(tool.ROOT).as_posix()]):
        tool.main()
    check(len(clients) == 1 and clients[0].initialized and clients[0].closed and len(clients[0].calls) == 2, "Two reads with guaranteed client cleanup")
    check(writes[-1]["complete"] and writes[-1]["allEightExactSourceEditorIdentityPropertiesAttributes"], "Success receipt covers all eight pins twice")
    check(all(writes[-1][field] is False for field in ("studioMutation", "nativeBackup", "probeCreated", "runtimeMirrorsWritten", "globalManifestWritten", "gitStaged")), "No unclaimed side effects")
    check(before == {path: tool.sha(path.read_bytes()) for path in protected}, "Raw export, all runtime mirrors and global manifest preserved")
    class BadClient(Client):
        def call(self, name, arguments):
            self.calls.append((name, arguments))
            wrong = copy.deepcopy(good)
            wrong["pins"][-1]["properties"]["Disabled"] = True
            return json.dumps(wrong)
    with patch.object(tool, "StudioMcpClient", BadClient), patch.object(tool, "find_mcp_batch", lambda: "mock"), \
            patch.object(Path, "write_bytes", write), patch.object(Path, "mkdir", lambda *a, **k: None), \
            patch.object(sys, "argv", ["reader", "--receipt", output.relative_to(tool.ROOT).as_posix()]):
        reject(tool.main, "Native property drift was accepted in main")
    check(clients[-1].closed and len(clients[-1].calls) == 1, "Rejected native drift still closes client before a second read")
    check(writes[-1]["complete"] is False and writes[-1]["error"].startswith("AssertionError"), "Rejected drift records an incomplete failure receipt")

    compiler = Path(os.environ.get("LUAU_COMPILER", "G:/Roblox/MongoTV/_local/optimization-20261009/luau-0.741/luau-compile.exe"))
    assert compiler.is_file(), "Official Luau compiler required"
    temp_parent = tool.ROOT / "_local/optimization-20261009/source-check-tests"
    temp_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="compile-", dir=temp_parent) as temporary:
        temporary_path = Path(temporary).resolve()
        assert temporary_path.is_relative_to(temp_parent.resolve())
        fixture = temporary_path / "native-read-only-check.luau"
        compile_rows = copy.deepcopy(expected)
        for row in compile_rows:
            row["source"] = "-- Syntax-only payload placeholder; actual source bytes compiled separately"
        fixture.write_text(tool.make_code(compile_rows), encoding="utf-8", newline="\n")
        for path in [fixture] + [tool.ROOT / row["expectedRepositoryPath"] for row in expected]:
            result = subprocess.run([str(compiler), str(path)], capture_output=True, text=True)
            check(result.returncode == 0, "Official Luau compile failed: " + str(path) + "\n" + result.stderr)
    check(before == {path: tool.sha(path.read_bytes()) for path in protected}, "Compiler verification preserves all protected files")
    result = {"totalChecks": checks, "offlineGuardChecks": checks - 9, "officialLuauCompileChecks": 9,
        "helperSha256": tool.sha((HERE / "check_eight_sources.py").read_bytes()),
        "manifestSha256": manifest_hash, "authoritativeStudioId": sid, "compiledCurrentRuntimeSources": 8,
        "nativeReadCodeCompiled": True, "studioConnected": False, "allSimulatedWritesIntercepted": True,
        "runtimeAndGlobalPreserved": True, "backupCreated": False}
    (HERE / "check-eight-test-result.json").write_bytes((json.dumps(result, indent=2) + "\n").encode())
    print(str(checks) + " checks passed, including nine official Luau compilations")


if __name__ == "__main__":
    main()
