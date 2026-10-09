"""Isolate this task from other developers' staged changes.

stage ARTIFACT_LIST.json [--plan-dir PATH] prepares an alternate index and
review files, without changing HEAD, the real index, or working files.
commit PLAN.json --reviewed-plan-sha256 SHA --message-file FILE commits exactly
that reviewed tree, then refreshes only task entries in the real index.
No push, hooks, source synchronization, publication, or candidate copies.
"""
from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
TASK = "artifacts/stutter-assets-20261009"
MANIFEST = "studio-sync-manifest.json"
SOURCES = {
    "ReplicatedFirst/Lobby Loading Screen.LocalScript.lua": ("ReplicatedFirst.Lobby Loading Screen", "LocalScript"),
    "StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua": ("StarterPlayer.StarterPlayerScripts.Round Entry Client", "LocalScript"),
    "StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua": ("StarterPlayer.StarterPlayerScripts.Shop Display Client", "LocalScript"),
    "StarterPlayer/StarterPlayerScripts/Lobby DJ Client.LocalScript.lua": ("StarterPlayer.StarterPlayerScripts.Lobby DJ Client", "LocalScript"),
    "ServerScriptService/Level 1 Systems/BlenderRoomRenderer.ModuleScript.lua": ("ServerScriptService.Level 1 Systems.BlenderRoomRenderer", "ModuleScript"),
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encode(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def git(root, *args, index=None, data=None):
    env = os.environ.copy()
    env.pop("GIT_INDEX_FILE", None)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    if index is not None:
        env["GIT_INDEX_FILE"] = str(index)
    result = subprocess.run(["git", "-c", "commit.gpgSign=false", *args], cwd=root,
                            env=env, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(result.returncode == 0, "git " + " ".join(args) + ": " + result.stderr.decode(errors="replace"))
    return result.stdout


def head(root):
    return git(root, "rev-parse", "HEAD").decode().strip()


def head_ref(root):
    reference = git(root, "symbolic-ref", "HEAD").decode().strip()
    require(reference.startswith("refs/heads/"), "Requires an attached local branch")
    return reference


def require_head_ref(root, expected):
    require(head_ref(root) == expected, "HEAD branch changed since planning; rebuild and review the plan")


def entries(root, index=None):
    result = {}
    for record in git(root, "ls-files", "--stage", "-z", index=index).split(b"\0"):
        if not record:
            continue
        metadata, name = record.split(b"\t", 1)
        mode, oid, stage = metadata.decode().split()
        require(stage == "0", "Resolve unmerged index entries before planning/committing")
        result[name.decode("utf-8")] = [mode, oid]
    return result


def task_rows(manifest):
    rows = {}
    for rel, (native, class_name) in SOURCES.items():
        matches = [row for row in manifest["items"] if row.get("file") == rel]
        require(len(matches) == 1, "Expected one manifest entry for " + rel)
        row = matches[0]
        require(row.get("studioPath") == native and row.get("className") == class_name,
                "Manifest identity differs for " + rel)
        rows[rel] = copy.deepcopy(row)
    return rows


def replace_rows(base, replacements):
    result = copy.deepcopy(base)
    task_rows(base)  # Validate both sides; leave all other rows/top-level fields alone.
    for i, row in enumerate(result["items"]):
        if row.get("file") in SOURCES:
            result["items"][i] = copy.deepcopy(replacements[row["file"]])
    return result


def artifact_paths(value):
    require(isinstance(value, list) and all(isinstance(p, str) for p in value), "Artifact selection must be a JSON string array")
    require(len(value) == len(set(value)), "Duplicate artifact path")
    for rel in value:
        path = PurePosixPath(rel)
        require(str(path) == rel and path.parent.as_posix() == TASK, "Only explicit top-level task artifacts are allowed: " + rel)
        require(path.suffix in {".json", ".md", ".py", ".luau"}, "Unsupported artifact type: " + rel)
        lower = path.name.lower()
        require(not any(token in lower for token in (".before.", ".candidate.", "sources.json", "secret", "credential", ".env")),
                "Source snapshots/candidates/credentials are not commit artifacts: " + rel)
        require(path.suffix != ".luau" or lower.startswith("probe_"), "Only native probe Luau artifacts are allowed: " + rel)
    return value


def read_file(root, rel):
    path = root / rel
    require(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(root.resolve()),
            "Expected regular repository file: " + rel)
    return path.read_bytes()


def blob(root, rel, raw):
    # Git's normal clean conversion (including this checkout's CRLF policy).
    return git(root, "hash-object", "-w", "--path=" + rel, "--stdin", data=raw).decode().strip()


def update_entries(root, index, values):
    data = b"".join((mode + " " + oid + "\t" + rel).encode("utf-8") + b"\0"
                    for rel, (mode, oid) in sorted(values.items()))
    git(root, "update-index", "-z", "--index-info", index=index, data=data)


def stage(root, selection_file, plan_dir=None):
    root = root.resolve()
    reference = head_ref(root)
    baseline = head(root)
    real_index = Path(git(root, "rev-parse", "--path-format=absolute", "--git-path", "index").decode().strip())
    git_dir = Path(git(root, "rev-parse", "--absolute-git-dir").decode().strip())
    directory = (plan_dir or git_dir / "stutter-assets-20261009" / ("stage-" + uuid.uuid4().hex)).resolve()
    require(directory.is_relative_to(git_dir.resolve()), "Plan directory must be inside this repository's Git directory")
    directory.mkdir(parents=True, exist_ok=False)
    alternate = directory / "alternate-index"
    artifacts = artifact_paths(json.loads(selection_file.read_bytes()))
    paths = list(SOURCES) + artifacts + [MANIFEST]
    before_index = entries(root)
    before_manifest = json.loads(git(root, "show", baseline + ":" + MANIFEST))
    working_manifest = json.loads(read_file(root, MANIFEST))
    replacements = task_rows(working_manifest)
    prepared_manifest = encode(replace_rows(before_manifest, replacements))
    git(root, "read-tree", baseline, index=alternate)
    head_entries = entries(root, alternate)
    staged, inputs = {}, {}
    for rel in paths:
        raw = prepared_manifest if rel == MANIFEST else read_file(root, rel)
        if rel in SOURCES:
            canonical = raw.decode("utf-8").replace("\r\n", "\n").encode("utf-8")
            row = replacements[rel]
            require(row.get("status") == "synced" and row.get("sourceEditorMatches") is True,
                    "Source/editor verification missing for " + rel)
            require(row.get("sha256") == sha(canonical) and row.get("bytes") == len(canonical),
                    "Manifest/mirror hash differs for " + rel)
        oid = blob(root, rel, raw)
        if rel in SOURCES:
            require(git(root, "cat-file", "blob", oid) == canonical, "Git clean conversion changed verified source: " + rel)
        staged[rel] = [head_entries.get(rel, ["100644"])[0], oid]
        if rel != MANIFEST:
            inputs[rel] = sha(raw)
    update_entries(root, alternate, staged)
    tree = git(root, "write-tree", index=alternate).decode().strip()
    changed = git(root, "diff", "--cached", "--name-only", "-z", baseline, index=alternate).split(b"\0")
    require(all(not p or p.decode("utf-8") in paths for p in changed), "Alternate index contains unrelated changes")
    require(any(changed), "No task changes to commit")
    diff = git(root, "diff", "--cached", "--no-ext-diff", "--no-textconv", "--binary", baseline, index=alternate)
    (directory / "staged.diff").write_bytes(diff)
    (directory / "name-status.txt").write_bytes(git(root, "diff", "--cached", "--name-status", baseline, index=alternate))
    (directory / "status-before.txt").write_bytes(git(root, "status", "--short"))
    (directory / "blobs.json").write_bytes(encode(staged))
    (directory / "task-manifest.json").write_bytes(prepared_manifest)
    require_head_ref(root, reference)
    require(head(root) == baseline, "HEAD changed while planning; make a fresh plan")
    current_index = entries(root)
    require({p: current_index.get(p) for p in paths} == {p: before_index.get(p) for p in paths},
            "Task target index entries changed while planning")
    plan = {"format": 1, "root": str(root), "head": baseline, "headRef": reference, "tree": tree,
            "createdAtUtc": datetime.now(timezone.utc).isoformat(), "alternateIndex": str(alternate),
            "alternateIndexSHA256": sha(alternate.read_bytes()), "realIndex": str(real_index),
            "paths": paths, "targetIndexBefore": {p: before_index.get(p) for p in paths},
            "blobs": staged, "inputsSHA256": inputs, "manifestRows": replacements,
            "diffSHA256": sha(diff)}
    plan_file = directory / "plan.json"
    plan_file.write_bytes(encode(plan))
    return {"plan": str(plan_file), "reviewedPlanSHA256": sha(plan_file.read_bytes()),
            "reviewDiff": str(directory / "staged.diff"), "nameStatus": str(directory / "name-status.txt"),
            "blobs": str(directory / "blobs.json"), "head": baseline, "tree": tree}


def commit(root, plan_file, reviewed_sha, message_file):
    root = root.resolve()
    raw_plan = plan_file.read_bytes()
    require(sha(raw_plan) == reviewed_sha, "Plan differs from the explicitly reviewed SHA-256")
    plan = json.loads(raw_plan)
    require(plan["format"] == 1 and Path(plan["root"]) == root, "Wrong plan repository/version")
    require_head_ref(root, plan["headRef"])
    paths = list(SOURCES) + artifact_paths([p for p in plan["paths"] if p not in SOURCES and p != MANIFEST]) + [MANIFEST]
    require(plan["paths"] == paths, "Plan scope differs")
    alternate = Path(plan["alternateIndex"])
    require(alternate.parent == plan_file.resolve().parent, "Alternate index is outside the plan directory")
    require(sha(alternate.read_bytes()) == plan["alternateIndexSHA256"], "Reviewed alternate index changed")
    require(git(root, "write-tree", index=alternate).decode().strip() == plan["tree"], "Reviewed tree changed")
    require(sha(alternate.read_bytes()) == plan["alternateIndexSHA256"], "Reviewed alternate index changed during tree verification")
    reviewed_entries = entries(root, alternate)
    require({p: reviewed_entries.get(p) for p in paths} == plan["blobs"], "Reviewed blob list changed")
    require(sha(git(root, "diff", "--cached", "--no-ext-diff", "--no-textconv", "--binary", plan["head"], index=alternate)) == plan["diffSHA256"],
            "Reviewed staged diff changed")
    for rel, expected in plan["inputsSHA256"].items():
        require(sha(read_file(root, rel)) == expected, "Working task file changed after review: " + rel)
    require(task_rows(json.loads(read_file(root, MANIFEST))) == plan["manifestRows"], "Working task manifest rows changed after review")
    message = message_file.read_bytes()
    require(message.strip(), "Empty commit message")
    real_index = Path(git(root, "rev-parse", "--path-format=absolute", "--git-path", "index").decode().strip())
    require(real_index == Path(plan["realIndex"]), "Real index path changed")
    lock = real_index.with_name(real_index.name + ".lock")
    receipt = plan_file.parent / "commit-receipt.json"
    require(not receipt.exists(), "This plan already has a commit receipt")
    require_head_ref(root, plan["headRef"])
    fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    moved_head = False
    result = {"headBefore": plan["head"], "headRef": plan["headRef"], "commit": None, "realIndexUpdated": False, "push": False}
    try:
        original = real_index.read_bytes()
        (plan_file.parent / "real-index-before-commit").write_bytes(original)
        require_head_ref(root, plan["headRef"])
        require(head(root) == plan["head"], "HEAD advanced since review; rebuild and review the plan")
        latest = entries(root)
        require({p: latest.get(p) for p in paths} == plan["targetIndexBefore"], "Task target staged entries changed since review")
        refreshed = plan_file.parent / "refreshed-real-index"
        require(not refreshed.exists(), "Recovery index already exists; inspect it before retrying")
        refreshed.write_bytes(original)
        # A staged manifest may contain another developer's rows. Preserve them.
        indexed_manifest = json.loads(git(root, "cat-file", "blob", latest[MANIFEST][1]))
        merged_manifest = encode(replace_rows(indexed_manifest, plan["manifestRows"]))
        updates = copy.deepcopy(plan["blobs"])
        updates[MANIFEST] = [latest[MANIFEST][0], blob(root, MANIFEST, merged_manifest)]
        update_entries(root, refreshed, updates)
        after = entries(root, refreshed)
        require({p: value for p, value in after.items() if p not in paths} == {p: value for p, value in latest.items() if p not in paths},
                "Unrelated staged entries changed in the refresh")
        require(real_index.read_bytes() == original, "Real index changed despite lock; stop and reconcile")
        commit_id = git(root, "commit-tree", plan["tree"], "-p", plan["head"], index=alternate, data=message).decode().strip()
        result["commit"] = commit_id
        receipt.write_bytes(encode(result))  # Recoverable receipt exists before ref mutation.
        with os.fdopen(fd, "wb", closefd=False) as handle:
            handle.write(refreshed.read_bytes())
            handle.flush()
            os.fsync(fd)
        require_head_ref(root, plan["headRef"])
        git(root, "update-ref", "-m", "commit: stutter-assets-20261009", plan["headRef"], commit_id, plan["head"])
        moved_head = True
        os.close(fd)
        fd = None
        os.replace(lock, real_index)
        result["realIndexUpdated"] = True
        result["unrelatedStagedEntriesPreserved"] = True
        result["manifestUnrelatedRowsPreserved"] = True
        receipt.write_bytes(encode(result))
        return result
    except Exception as error:
        result["headUpdated"] = moved_head
        result["error"] = str(error)
        receipt.write_bytes(encode(result))
        raise
    finally:
        if fd is not None:
            os.close(fd)
        # If HEAD moved but index replacement failed, preserve the prepared lock
        # and receipt for explicit recovery; do not leave a misleading index.
        if lock.exists() and not moved_head:
            lock.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prep = sub.add_parser("stage")
    prep.add_argument("artifacts", type=Path)
    prep.add_argument("--plan-dir", type=Path)
    finish = sub.add_parser("commit")
    finish.add_argument("plan", type=Path)
    finish.add_argument("--reviewed-plan-sha256", required=True)
    finish.add_argument("--message-file", required=True, type=Path)
    args = parser.parse_args()
    if args.command == "stage":
        result = stage(ROOT, args.artifacts, args.plan_dir)
    else:
        result = commit(ROOT, args.plan.resolve(), args.reviewed_plan_sha256, args.message_file)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
