"""Prepare an exact task review; root may explicitly stage a separate index.

Default never stages, commits, writes Git objects, changes Studio, changes the
working manifest, or touches the normal index. Scratch review artifacts and the
explicit --stage index live in ignored _local, outside the versioned allowlist.
HEAD drift or any reviewed file/index drift requires a new default preparation.
"""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import difflib
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
TASK = "tools/optimization_20261009"
GLOBAL = "studio-sync-manifest.json"
EXPORT = TASK + "/loading/install/compatibility/spectate-bootstrap/verified-export-eight/manifest.json"
OWNED_SOURCE_PATHS = {
    "ReplicatedFirst.Lobby Loading Screen", "ServerScriptService.GameManager",
    "ServerScriptService.Level 4 Systems.Level 4 Light Director",
    "StarterPlayer.StarterPlayerScripts.Level 2 Sound Controller",
    "StarterPlayer.StarterPlayerScripts.Level 6 Playground Client",
    "ReplicatedStorage.SceneEffectBudget", "StarterPlayer.StarterPlayerScripts.SceneEffectBudgetClient",
    "StarterPlayer.StarterPlayerScripts.SpectateController",
}
SCRATCH = ROOT / "_local/optimization-20261009/commit-review"
SOURCE_FIELDS = {"bytes", "sha256", "status", "sourceEditorMatches", "studioTrailingNewline"}
WHITESPACE_POLICY = "core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol"
SECRET_PATTERNS = {
    "private-key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "aws-access-key": re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "github-token": re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b"),
    "openai-key": re.compile(rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{40,}\b"),
    "roblox-cookie": re.compile(rb"_\|WARNING:-DO-NOT-SHARE-THIS[!-~]{40,}"),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def normalized(raw):
    return raw.replace(b"\r\n", b"\n")


def git(*args, index=None, data=None, accepted=(0,)):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    env.pop("GIT_INDEX_FILE", None)
    if index is not None:
        env["GIT_INDEX_FILE"] = str(index)
    result = subprocess.run(["git", *args], cwd=ROOT, env=env, input=data, capture_output=True)
    if result.returncode not in accepted:
        raise RuntimeError("git " + " ".join(args[:3]) + " failed: " + result.stderr.decode("utf-8", "replace"))
    return result.stdout


def git_index():
    path = Path(git("rev-parse", "--git-path", "index").decode().strip())
    return path if path.is_absolute() else ROOT / path


def normal_index_pin():
    path = git_index()
    return {"path": str(path.resolve()), "exists": path.exists(),
            "rawSha256": sha(path.read_bytes()) if path.exists() else None,
            "entriesSha256": sha(git("ls-files", "--stage", "-z"))}


def head():
    return git("rev-parse", "HEAD").decode().strip()


def head_blob(commit, path):
    result = subprocess.run(["git", "show", commit + ":" + path], cwd=ROOT,
        env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"), capture_output=True)
    if result.returncode == 0:
        return result.stdout
    exists = git("ls-tree", "-z", commit, "--", path)
    assert not exists, "Cannot read an existing HEAD blob: " + path
    return None


def safe_relative(path):
    parsed = PurePosixPath(path)
    assert not parsed.is_absolute() and ".." not in parsed.parts and "\\" not in path
    assert path and "\x00" not in path and "\n" not in path and "\r" not in path
    return parsed


def excluded(path):
    parsed = safe_relative(path)
    return any(part in {"__pycache__", ".cache", ".pytest_cache"} for part in parsed.parts) or parsed.suffix in {".pyc", ".pyo"}


def task_changes():
    tracked = git("diff", "--name-only", "-z", "HEAD", "--", TASK)
    untracked = git("ls-files", "--others", "--exclude-standard", "-z", "--", TASK)
    paths = sorted({part.decode("utf-8") for part in (tracked + untracked).split(b"\0") if part})
    return [path for path in paths if not excluded(path)], [path for path in paths if excluded(path)]


def json_bytes(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def verified_rows():
    capture = json.loads((ROOT / EXPORT).read_bytes())
    assert capture["complete"] and capture["placeId"] == 131311258779917 and capture["universeId"] == 10559217407
    rows = capture["scripts"]
    assert len(rows) == len(OWNED_SOURCE_PATHS) and {row["path"] for row in rows} == OWNED_SOURCE_PATHS
    assert len({row["expectedRepositoryPath"] for row in rows}) == len(rows)
    for row in rows:
        assert row["editorParity"] and row["reviewedCandidateMatches"] and row["rawUtf8Verified"]
        assert row["rawSourceSha256"] == row["reviewedCandidateSha256"]
        expected = PurePosixPath(*row["segments"][:-1]) / (row["segments"][-1] + "." + row["class"] + ".lua")
        assert expected.as_posix() == row["expectedRepositoryPath"]
        source = (ROOT / row["rawFile"]).read_bytes()
        mirror = (ROOT / row["expectedRepositoryPath"]).read_bytes()
        assert len(source) == row["rawBytes"] and sha(source) == row["rawSourceSha256"]
        assert mirror == source, "Runtime mirror not exact verified native source: " + expected.as_posix()
    return rows


def scoped_global(head_manifest, working_manifest, rows):
    """Merge only eight owned source fields/new rows into the pinned HEAD blob."""
    assert head_manifest["placeId"] == working_manifest["placeId"] == 131311258779917
    assert head_manifest["universeId"] == working_manifest["universeId"] == 10559217407
    proposed = copy.deepcopy(head_manifest)
    targets = {row["path"]: row for row in rows}
    assert len(targets) == len(OWNED_SOURCE_PATHS) and set(targets) == OWNED_SOURCE_PATHS
    originals = {row["studioPath"]: row for row in head_manifest["items"] if row["studioPath"] in targets}
    assert len(originals) == sum(row["studioPath"] in targets for row in head_manifest["items"])
    current = {row["studioPath"]: row for row in working_manifest["items"] if row["studioPath"] in targets}
    assert len(current) == len(targets) and sum(row["studioPath"] in targets for row in working_manifest["items"]) == len(targets)
    changed = []
    for path, pin in targets.items():
        live = current[path]
        assert live["segments"] == pin["segments"] and live["className"] == pin["class"] and live["file"] == pin["expectedRepositoryPath"]
        assert live["bytes"] == pin["rawBytes"] and live["sha256"] == pin["rawSourceSha256"]
        assert live["status"] == "synced" and live["sourceEditorMatches"] is True
        item = next((row for row in proposed["items"] if row["studioPath"] == path), None)
        if item is None:
            assert path in {"ReplicatedStorage.SceneEffectBudget", "StarterPlayer.StarterPlayerScripts.SceneEffectBudgetClient"}, "Unexpected missing existing source row"
            item = copy.deepcopy(live)
            proposed["items"].append(item)
            action = "add-reviewed-source"
        else:
            assert item["segments"] == pin["segments"] and item["className"] == pin["class"] and item["file"] == pin["expectedRepositoryPath"]
            action = "refresh-owned-source-fields"
        item.update(bytes=pin["rawBytes"], sha256=pin["rawSourceSha256"], status="synced", sourceEditorMatches=True)
        item.pop("studioTrailingNewline", None)
        changed.append({"path": path, "action": action, "beforeSha256": originals.get(path, {}).get("sha256"), "afterSha256": pin["rawSourceSha256"]})
    proposed["counts"]["scripts"] = sum(row["className"] in {"Script", "LocalScript", "ModuleScript"} for row in proposed["items"])
    proposed["counts"]["total"] = len(proposed["items"])
    proposed["counts"]["studioTrailingNewline"] = sum(row.get("studioTrailingNewline") is True for row in proposed["items"])
    assert [row for row in proposed["items"] if row["studioPath"] not in targets] == [row for row in head_manifest["items"] if row["studioPath"] not in targets]
    for key in head_manifest:
        if key not in {"items", "counts"}:
            assert proposed[key] == head_manifest[key]
    for path, old in originals.items():
        new = next(row for row in proposed["items"] if row["studioPath"] == path)
        assert {key: value for key, value in new.items() if key not in SOURCE_FIELDS} == {key: value for key, value in old.items() if key not in SOURCE_FIELDS}
    assert {key: value for key, value in proposed["counts"].items() if key not in {"scripts", "total", "studioTrailingNewline"}} == {key: value for key, value in head_manifest["counts"].items() if key not in {"scripts", "total", "studioTrailingNewline"}}
    return proposed, changed


def scan_credentials(path, raw):
    for label, pattern in SECRET_PATTERNS.items():
        assert not pattern.search(raw), "Possible credential (value withheld): " + label + " in " + path


def native_source_hashes():
    """Only recorded source hashes classify preservation; never tool code."""
    keys = {"source_sha256", "sourceSha256", "beforeSha256", "afterSha256", "rawSourceSha256", "reviewedCandidateSha256"}
    result = set()
    def collect(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in keys and isinstance(item, str) and re.fullmatch("[0-9a-f]{64}", item):
                    result.add(item)
                collect(item)
        elif isinstance(value, list):
            for item in value:
                collect(item)
    for path in (ROOT / TASK).rglob("*.json"):
        if not excluded(path.relative_to(ROOT).as_posix()):
            collect(json.loads(path.read_bytes()))
    return result


def whitespace_findings(raw, files):
    records = {row["path"]: row for row in files}
    pins = native_source_hashes()
    found = []
    for line in raw.decode("utf-8", "replace").splitlines():
        match = re.match(r"^(.+?):(\d+): (.+)$", line)
        if match:
            path, number, kind = match.groups()
            row = records.get(path, {})
            raw_hash = row.get("rawSha256")
            preserve = path.endswith((".lua", ".luau")) and raw_hash in pins
            found.append({"path": path, "line": int(number), "kind": kind, "rawSha256": raw_hash,
                "classification": "pinned-native-source-preservation" if preserve else "requires-tool-code-review",
                "pinnedNativeSourceSha256": raw_hash if preserve else None})
    return found


def validate_waiver(waiver, plan, findings):
    assert waiver["headCommit"] == plan["headCommit"]
    assert findings and all(row["classification"] == "pinned-native-source-preservation" for row in findings), "No waiver for new tool code or unproven native captures"
    expected = sorted(({key: row[key] for key in ("path", "line", "kind", "rawSha256", "pinnedNativeSourceSha256")} for row in findings), key=lambda row: (row["path"], row["line"], row["kind"]))
    assert sorted(waiver["approvedFindings"], key=lambda row: (row["path"], row["line"], row["kind"])) == expected, "Waiver must approve the exact hash-pinned native findings"
    assert waiver.get("reason"), "Root's preservation waiver requires a recorded reason"
    return True


def fingerprint(path):
    full = ROOT / safe_relative(path)
    assert not full.is_symlink(), "Symlink outside exact task ownership: " + path
    if not full.exists():
        return {"path": path, "deleted": True, "bytes": 0, "rawSha256": None}
    assert full.is_file()
    raw = full.read_bytes()
    scan_credentials(path, raw)
    return {"path": path, "deleted": False, "bytes": len(raw), "rawSha256": sha(raw), "lfSha256": sha(normalized(raw))}


def diff_review(path, before, after):
    # Large JSON pages are asset/identity ledgers, not executable code. Retain
    # their exact bytes/hash/count in the review without expanding all records.
    large_ledger = path.endswith(".json") and max(len(before or b""), len(after or b"")) > 256_000
    metadata = {"path": path, "beforeBytes": len(before or b""), "afterBytes": len(after or b""),
        "beforeSha256": sha(before) if before is not None else None,
        "afterSha256": sha(after) if after is not None else None,
        "beforeLines": len((before or b"").splitlines()), "afterLines": len((after or b"").splitlines()),
        "largeLedgerCountHashOnly": large_ledger}
    if large_ledger:
        try:
            value = json.loads(after or before)
            metadata["jsonTopLevelKeys"] = sorted(value) if isinstance(value, dict) else None
            metadata["topLevelArrayCounts"] = {key: len(item) for key, item in value.items() if isinstance(item, list)} if isinstance(value, dict) else {"items": len(value)}
        except (ValueError, TypeError):
            raise AssertionError("Large ledger is not valid JSON: " + path)
        return metadata, "\n# Ledger: " + path + "\n# " + json.dumps(metadata) + "\n"
    old_lines = normalized(before or b"").decode("utf-8").splitlines(keepends=True)
    new_lines = normalized(after or b"").decode("utf-8").splitlines(keepends=True)
    diff = "".join(difflib.unified_diff(old_lines, new_lines, fromfile="a/" + path, tofile="b/" + path, n=3))
    metadata["addedLines"] = sum(line.startswith("+") and not line.startswith("+++") for line in diff.splitlines())
    metadata["removedLines"] = sum(line.startswith("-") and not line.startswith("---") for line in diff.splitlines())
    return metadata, diff


def prepare():
    initial_index = normal_index_pin()
    commit = head()
    remote = git("rev-parse", "refs/remotes/origin/main").decode().strip()
    rows = verified_rows()
    task_paths, skipped = task_changes()
    paths = sorted(set(task_paths + [row["expectedRepositoryPath"] for row in rows]))
    assert all(path.startswith(TASK + "/") or path in {row["expectedRepositoryPath"] for row in rows} for path in paths)
    working_raw = (ROOT / GLOBAL).read_bytes()
    head_raw = head_blob(commit, GLOBAL)
    scoped, targets = scoped_global(json.loads(head_raw), json.loads(working_raw), rows)
    scoped_raw = json_bytes(scoped)
    records = [fingerprint(path) for path in paths]
    reviews = []
    diffs = []
    actual = []
    for record in records:
        path = record["path"]
        before = head_blob(commit, path)
        after = None if record["deleted"] else (ROOT / path).read_bytes()
        # Git's text conversion is checked again from the actual staged blob.
        if before is not None and after is not None and normalized(before) == normalized(after):
            continue
        if before is None and after is None:
            continue
        metadata, diff = diff_review(path, before, after)
        reviews.append(metadata)
        diffs.append(diff)
        actual.append(path)
    global_metadata, global_diff = diff_review(GLOBAL, head_raw, scoped_raw)
    global_metadata["largeLedgerCountHashOnly"] = False
    # Global source changes are small: show the precise eight-row diff even
    # when the whole historical manifest exceeds the ledger size threshold.
    global_diff = "".join(difflib.unified_diff(normalized(head_raw).decode().splitlines(keepends=True), scoped_raw.decode().splitlines(keepends=True), fromfile="a/" + GLOBAL, tofile="b/" + GLOBAL, n=3))
    reviews.append(global_metadata)
    diffs.append(global_diff)
    if normalized(head_raw) != normalized(scoped_raw):
        actual.append(GLOBAL)
    assert head() == commit and normal_index_pin() == initial_index, "Concurrent HEAD/index changed during preparation; rerun default"
    assert (ROOT / GLOBAL).read_bytes() == working_raw
    assert [fingerprint(path) for path in paths] == records, "Concurrent reviewed file changed; rerun default"
    run = SCRATCH / (dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:8])
    run.mkdir(parents=True)
    scoped_file = run / "scoped-studio-sync-manifest.json"
    scoped_file.write_bytes(scoped_raw)
    plan = {"formatVersion": 1, "preparedUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "headCommit": commit, "observedOriginMain": remote, "normalIndex": initial_index,
        "verifiedExportManifestSha256": sha((ROOT / EXPORT).read_bytes()),
        "workingGlobalManifestSha256": sha(working_raw), "headGlobalManifestSha256": sha(head_raw),
        "scopedGlobalManifestSha256": sha(scoped_raw), "scopedGlobalFile": str(scoped_file),
        "targets": targets, "sources": [{key: row[key] for key in ("path", "segments", "class", "instanceId", "parentId", "rawBytes", "rawSourceSha256", "rawFile", "expectedRepositoryPath")} for row in rows],
        "files": records, "expectedChangedPaths": sorted(actual), "excludedCachePaths": skipped,
        "preservedHeadNonTargetGlobalRowsAndMetadata": True, "workingGlobalFileUntouched": True,
        "normalIndexUntouched": True, "studioMutation": False, "nativeBackup": False,
        "gitObjectsWritten": False, "gitStaged": False, "gitCommitted": False,
        "reviewSummaryFile": str(run / "review-summary.json"), "exactDiffFile": str(run / "review.diff")}
    (run / "plan.json").write_bytes(json_bytes(plan))
    (run / "review-summary.json").write_bytes(json_bytes({"headCommit": commit, "files": reviews,
        "fileCount": len(actual), "taskFileCount": len(task_paths), "taskBytes": sum(record["bytes"] for record in records if record["path"].startswith(TASK + "/")),
        "largeLedgerFiles": sum(item["largeLedgerCountHashOnly"] for item in reviews), "credentialScan": "high-confidence-patterns-pass", "targets": targets}))
    (run / "review.diff").write_text("\n".join(diffs), encoding="utf-8", newline="\n")
    print(json.dumps({"prepared": True, "plan": str(run / "plan.json"), "reviewSummary": str(run / "review-summary.json"), "exactDiff": str(run / "review.diff"),
        "headCommit": commit, "changedFiles": len(actual), "taskFiles": len(task_paths), "rawTaskBytes": sum(record["bytes"] for record in records if record["path"].startswith(TASK + "/")),
        "largeLedgerFiles": sum(item["largeLedgerCountHashOnly"] for item in reviews), "normalIndexUntouched": True, "gitStaged": False}))


def validate_plan(plan):
    assert head() == plan["headCommit"], "HEAD changed; root must reprepare/review default against fresh HEAD"
    assert normal_index_pin() == plan["normalIndex"], "Normal index changed; preserve it and reprepare"
    assert sha((ROOT / EXPORT).read_bytes()) == plan["verifiedExportManifestSha256"]
    assert sha((ROOT / GLOBAL).read_bytes()) == plan["workingGlobalManifestSha256"], "Concurrent working manifest changed; reprepare"
    assert [fingerprint(row["path"]) for row in plan["files"]] == plan["files"], "Reviewed file changed; reprepare/review"
    current, skipped = task_changes()
    assert skipped == plan["excludedCachePaths"]
    assert set(current) == {row["path"] for row in plan["files"] if row["path"].startswith(TASK + "/")}, "Task allowlist changed; reprepare/review"
    rows = verified_rows()
    scoped_raw = Path(plan["scopedGlobalFile"]).read_bytes()
    assert sha(scoped_raw) == plan["scopedGlobalManifestSha256"]
    reconstructed, targets = scoped_global(json.loads(head_blob(plan["headCommit"], GLOBAL)), json.loads((ROOT / GLOBAL).read_bytes()), rows)
    assert json_bytes(reconstructed) == scoped_raw and targets == plan["targets"]


def stage(plan_path, waiver_path=None):
    plan_path = plan_path.resolve()
    assert plan_path.is_relative_to(SCRATCH.resolve()) and plan_path.name == "plan.json"
    plan = json.loads(plan_path.read_bytes())
    validate_plan(plan)
    index = plan_path.parent / "reviewed.index"
    receipt_file = plan_path.parent / "stage-receipt.json"
    assert not index.exists() and not receipt_file.exists(), "Keep prior staged review; prepare a fresh plan"
    receipt = {"headCommit": plan["headCommit"], "indexFile": str(index), "normalIndex": plan["normalIndex"],
        "complete": False, "normalIndexUntouched": False, "workingGlobalFileUntouched": False,
        "studioMutation": False, "nativeBackup": False, "gitCommitted": False}
    try:
        git("read-tree", plan["headCommit"], index=index)
        non_global = [path for path in plan["expectedChangedPaths"] if path != GLOBAL]
        if non_global:
            pathspec = plan_path.parent / "exact-pathspec.nul"
            pathspec.write_bytes(b"".join((":(literal)" + path).encode("utf-8") + b"\0" for path in non_global))
            git("add", "--pathspec-from-file=" + str(pathspec), "--pathspec-file-nul", index=index)
        validate_plan(plan)
        scoped_raw = Path(plan["scopedGlobalFile"]).read_bytes()
        object_id = git("hash-object", "-w", "--stdin", data=scoped_raw).decode().strip()
        git("update-index", "--add", "--cacheinfo", "100644," + object_id + "," + GLOBAL, index=index)
        changed = sorted(part.decode("utf-8") for part in git("diff", "--cached", "--name-only", "-z", plan["headCommit"], index=index).split(b"\0") if part)
        assert changed == plan["expectedChangedPaths"], "Isolated index paths differ from exact reviewed allowlist"
        staged_files = []
        for record in plan["files"]:
            if record["path"] not in changed:
                continue
            if record["deleted"]:
                assert not git("ls-files", "--stage", "-z", "--", record["path"], index=index)
                staged_files.append({"path": record["path"], "deleted": True})
                continue
            staged_raw = git("show", ":" + record["path"], index=index)
            assert sha(normalized(staged_raw)) == record["lfSha256"], "Staged file differs from reviewed bytes after CRLF normalization: " + record["path"]
            if record["path"].startswith(TASK + "/"):
                assert sha(staged_raw) == record["rawSha256"], "Task evidence must preserve exact raw bytes (-text attributes): " + record["path"]
            scan_credentials(record["path"], staged_raw)
            staged_files.append({"path": record["path"], "deleted": False, "stagedRawSha256": sha(staged_raw), "stagedLfSha256": sha(normalized(staged_raw))})
        receipt["stagedFiles"] = staged_files
        sources = []
        for row in plan["sources"]:
            raw = git("show", ":" + row["expectedRepositoryPath"], index=index)
            expected = (ROOT / row["rawFile"]).read_bytes()
            assert normalized(raw) == normalized(expected) and sha(normalized(raw)) == sha(normalized(expected)), "Staged source differs from native after CRLF normalization"
            sources.append({"path": row["expectedRepositoryPath"], "nativeRawSha256": row["rawSourceSha256"], "stagedRawSha256": sha(raw), "stagedLfSha256": sha(normalized(raw)), "crlfNormalizationOnly": raw != expected})
        assert git("show", ":" + GLOBAL, index=index) == scoped_raw
        # Record the standard check honestly. Exact historical native captures
        # must never be rewritten just to hide inherited whitespace warnings.
        env = dict(os.environ, GIT_OPTIONAL_LOCKS="0", GIT_INDEX_FILE=str(index))
        check = subprocess.run(["git", "-c", WHITESPACE_POLICY, "diff", "--cached", "--check", plan["headCommit"]], cwd=ROOT, env=env, capture_output=True)
        (plan_path.parent / "diff-check.txt").write_bytes(check.stdout + check.stderr)
        receipt["diffCheckExitCode"] = check.returncode
        receipt["diffCheckFile"] = str(plan_path.parent / "diff-check.txt")
        receipt["diffCheckPassed"] = check.returncode == 0
        receipt["whitespacePolicy"] = WHITESPACE_POLICY
        findings = whitespace_findings(check.stdout + check.stderr, plan["files"])
        (plan_path.parent / "whitespace-findings.json").write_bytes(json_bytes(findings))
        receipt["whitespaceFindingsFile"] = str(plan_path.parent / "whitespace-findings.json")
        receipt["whitespaceFindings"] = findings
        receipt["reviewedNativePreservationWaiver"] = False
        if check.returncode != 0 and waiver_path is not None:
            waiver_raw = waiver_path.resolve().read_bytes()
            validate_waiver(json.loads(waiver_raw), plan, findings)
            receipt["reviewedNativePreservationWaiver"] = True
            receipt["waiverFile"] = str(waiver_path.resolve())
            receipt["waiverSha256"] = sha(waiver_raw)
        receipt["stagedSources"] = sources
        receipt["globalBlobId"] = object_id
        receipt["changedPaths"] = changed
        receipt["treeId"] = git("write-tree", index=index).decode().strip()
        receipt["isolatedIndexSha256"] = sha(index.read_bytes())
        refresh = []
        for path in changed:
            entries = git("ls-files", "--stage", "-z", "--", path, index=index)
            if entries:
                assert len(entries.split(b"\0")) == 2 and b" 0\t" in entries
                refresh.append(entries)
            else:
                refresh.append(b"0 " + b"0" * len(object_id) + b"\t" + path.encode("utf-8") + b"\0")
        refresh_file = plan_path.parent / "normal-index-after-commit.nul"
        refresh_file.write_bytes(b"".join(refresh))
        receipt["normalIndexRefreshFile"] = str(refresh_file)
        receipt["normalIndexRefreshSha256"] = sha(refresh_file.read_bytes())
        receipt["normalIndexRefreshApplied"] = False
        (plan_path.parent / "staged-stat.txt").write_bytes(git("diff", "--cached", "--stat", plan["headCommit"], index=index))
        (plan_path.parent / "staged-numstat.txt").write_bytes(git("diff", "--cached", "--numstat", plan["headCommit"], index=index))
        validate_plan(plan)
        receipt["normalIndexUntouched"] = normal_index_pin() == plan["normalIndex"]
        receipt["workingGlobalFileUntouched"] = sha((ROOT / GLOBAL).read_bytes()) == plan["workingGlobalManifestSha256"]
        assert receipt["normalIndexUntouched"] and receipt["workingGlobalFileUntouched"]
        assert check.returncode == 0 or receipt["reviewedNativePreservationWaiver"], "Staged diff --check has findings; root must inspect classified whitespace-findings.json; preserve raw native captures and fix tool code"
        receipt["complete"] = True
        print(json.dumps({"stagedSeparateIndex": True, "indexFile": str(index), "receipt": str(receipt_file), "treeId": receipt["treeId"], "files": len(changed), "diffCheckPassed": check.returncode == 0, "reviewedNativePreservationWaiver": receipt["reviewedNativePreservationWaiver"], "normalIndexUntouched": True, "gitCommitted": False}))
    except Exception as error:
        receipt["error"] = type(error).__name__ + ": " + str(error)
        receipt["normalIndexUntouched"] = normal_index_pin() == plan["normalIndex"]
        receipt["workingGlobalFileUntouched"] = sha((ROOT / GLOBAL).read_bytes()) == plan["workingGlobalManifestSha256"]
        raise
    finally:
        receipt_file.write_bytes(json_bytes(receipt))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", action="store_true", help="Root only: stage exactly the reviewed plan in a separate index; never commit")
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--reviewed-whitespace-waiver", type=Path, help="Root only: exact reviewed native-source findings, never tool code")
    args = parser.parse_args()
    if args.stage:
        assert args.plan is not None, "--stage requires the exact reviewed --plan"
        stage(args.plan, args.reviewed_whitespace_waiver)
    else:
        assert args.plan is None, "Default prepares a fresh immutable review directory"
        assert args.reviewed_whitespace_waiver is None
        prepare()


if __name__ == "__main__":
    main()
