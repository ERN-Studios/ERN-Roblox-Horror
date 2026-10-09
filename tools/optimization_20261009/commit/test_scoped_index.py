"""Offline scope/CAS tests. No real Git staging/commit or Studio access."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("scoped", Path(__file__).with_name("prepare_scoped_index.py"))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
checks = 0


def check(condition):
    global checks
    assert condition
    checks += 1


def rejects(callback):
    try:
        callback()
    except AssertionError:
        check(True)
    else:
        raise AssertionError("Expected bounded guard rejection")


paths = ["ReplicatedFirst.Lobby Loading Screen", "ServerScriptService.GameManager", "ServerScriptService.Level 4 Systems.Level 4 Light Director",
    "StarterPlayer.StarterPlayerScripts.Level 2 Sound Controller", "StarterPlayer.StarterPlayerScripts.Level 6 Playground Client",
    "ReplicatedStorage.SceneEffectBudget", "StarterPlayer.StarterPlayerScripts.SceneEffectBudgetClient",
    "StarterPlayer.StarterPlayerScripts.SpectateController"]
pins = []
items = []
for n, path in enumerate(paths):
    segments = path.split(".")
    cls = "ModuleScript" if n in {2, 5} else "Script" if n == 1 else "LocalScript"
    file = "/".join(segments[:-1]) + "/" + segments[-1] + "." + cls + ".lua"
    pin = {"path": path, "segments": segments, "class": cls, "expectedRepositoryPath": file, "rawBytes": 15 + n, "rawSourceSha256": str(n) * 64}
    pins.append(pin)
    items.append({"studioPath": path, "segments": segments, "className": cls, "file": file, "bytes": pin["rawBytes"], "sha256": pin["rawSourceSha256"],
        "status": "synced", "sourceEditorMatches": True, "properties": {"Disabled": False}, "attributes": [], "concurrentNote": "working-only"})
head_items = copy.deepcopy(items[:5] + [items[7]])
for row in head_items:
    row.update(bytes=3, sha256="old", status="old", sourceEditorMatches=False, studioTrailingNewline=True, concurrentNote="HEAD-owner-note")
unrelated = {"studioPath": "StarterPlayer.StarterPlayerScripts.RoundUI", "className": "LocalScript", "sha256": "head-roundui", "properties": {"owner": "HEAD"}}
base = {"placeId": 131311258779917, "universeId": 10559217407, "capturedAtUtc": "HEAD-time", "topLevelOwnerField": {"preserve": True},
    "items": head_items + [unrelated], "counts": {"scripts": 7, "total": 7, "studioTrailingNewline": 6, "remoteEvents": 17, "created": 20, "updated": 3}}
working = copy.deepcopy(base)
working["capturedAtUtc"] = "working-other-time"
working["items"] = copy.deepcopy(items) + [{"studioPath": unrelated["studioPath"], "className": "LocalScript", "sha256": "dirty-unrelated", "properties": {"owner": "WORKING"}}]
working["items"].append({"studioPath": "unrelated-new-instance", "className": "ModuleScript", "sha256": "foreign"})
before = copy.deepcopy(base)
dirty_before = copy.deepcopy(working)
proposed, changes = helper.scoped_global(base, working, pins)
check(base == before and working == dirty_before)
check(proposed["capturedAtUtc"] == "HEAD-time" and proposed["topLevelOwnerField"] == base["topLevelOwnerField"])
check(proposed["items"][-3] == unrelated)
check(not any(row["studioPath"] == "unrelated-new-instance" for row in proposed["items"]))
check(len(changes) == 8 and sum(row["action"] == "add-reviewed-source" for row in changes) == 2)
check(proposed["counts"] == {"scripts": 9, "total": 9, "studioTrailingNewline": 0, "remoteEvents": 17, "created": 20, "updated": 3})
check(proposed["items"][5]["sha256"] == pins[7]["rawSourceSha256"] and proposed["items"][5]["concurrentNote"] == "HEAD-owner-note")
for n, row in enumerate(proposed["items"][:5]):
    check(row["sha256"] == pins[n]["rawSourceSha256"] and row["concurrentNote"] == "HEAD-owner-note" and "studioTrailingNewline" not in row)
for modify in (lambda x: x["items"][0].update(sha256="foreign"), lambda x: x["items"][0].update(bytes=999),
    lambda x: x["items"][0].update(className="Script"), lambda x: x["items"][0].update(sourceEditorMatches=False),
    lambda x: x["items"].append(copy.deepcopy(x["items"][0])), lambda x: x.update(placeId=42)):
    bad = copy.deepcopy(working)
    modify(bad)
    rejects(lambda: helper.scoped_global(base, bad, pins))
bad_head = copy.deepcopy(base)
bad_head["items"] = bad_head["items"][1:]
rejects(lambda: helper.scoped_global(bad_head, working, pins))
for path in ("/outside", "a/../b", "a\\b", "a\nb", "a\x00b"):
    rejects(lambda path=path: helper.safe_relative(path))
check(helper.excluded("tools/optimization_20261009/__pycache__/test.pyc"))
check(not helper.excluded("tools/optimization_20261009/geometry/install/manifest/page-000001.json"))
check(helper.normalized(b"a\r\nb\n") == b"a\nb\n")
check(helper.normalized(b"a\rb\n") != b"a\nb\n")
helper.scan_credentials("fixture", b"print('safe code')")
check(True)
rejects(lambda: helper.scan_credentials("fixture", b"gh" + b"p_" + b"A" * 36))
metadata, diff = helper.diff_review("page.json", None, json.dumps({"rows": ["a" * 300_000]}).encode())
check(metadata["largeLedgerCountHashOnly"] and metadata["topLevelArrayCounts"] == {"rows": 1} and len(diff) < 1000)
metadata, diff = helper.diff_review("script.py", b"old\n", b"new\n")
check(not metadata["largeLedgerCountHashOnly"] and "+new" in diff and metadata["addedLines"] == 1)
with patch.object(helper, "head", return_value="different"):
    rejects(lambda: helper.validate_plan({"headCommit": "pinned"}))
with patch.object(helper, "head", return_value="pinned"), patch.object(helper, "normal_index_pin", return_value={"sha": "changed"}):
    rejects(lambda: helper.validate_plan({"headCommit": "pinned", "normalIndex": {"sha": "before"}}))
with patch.object(helper.subprocess, "run") as run:
    run.return_value.returncode = 0
    run.return_value.stdout = b"test"
    helper.git("ls-files")
    kwargs = run.call_args.kwargs
    check("GIT_INDEX_FILE" not in kwargs["env"] and kwargs["env"]["GIT_OPTIONAL_LOCKS"] == "0")
    helper.git("read-tree", "pinned", index=Path("explicit-mock-index"))
    check(run.call_args.kwargs["env"]["GIT_INDEX_FILE"] == "explicit-mock-index")
native_hash = "a" * 64
records = [{"path": "capture.luau", "rawSha256": native_hash}, {"path": "new-tool.py", "rawSha256": native_hash}]
with patch.object(helper, "native_source_hashes", return_value={native_hash}):
    findings = helper.whitespace_findings(b"capture.luau:12: trailing whitespace.\n", records)
    check(findings[0]["classification"] == "pinned-native-source-preservation")
    tool_findings = helper.whitespace_findings(b"new-tool.py:12: trailing whitespace.\n", records)
    check(tool_findings[0]["classification"] == "requires-tool-code-review")
waiver = {"headCommit": "pinned", "reason": "Preserve exact authoritative captured source bytes", "approvedFindings": [
    {key: findings[0][key] for key in ("path", "line", "kind", "rawSha256", "pinnedNativeSourceSha256")}]}
check(helper.validate_waiver(waiver, {"headCommit": "pinned"}, findings))
rejects(lambda: helper.validate_waiver(waiver, {"headCommit": "other"}, findings))
rejects(lambda: helper.validate_waiver(waiver, {"headCommit": "pinned"}, tool_findings))
bad_waiver = copy.deepcopy(waiver)
bad_waiver["approvedFindings"][0]["line"] = 13
rejects(lambda: helper.validate_waiver(bad_waiver, {"headCommit": "pinned"}, findings))
print(json.dumps({"offlineChecks": checks, "passed": True, "realGitStaged": False, "gitCommitted": False, "studioMutation": False}))
