# Stage B temporary source archive

Documentation only. Temporary runnable probe/helper files are removed after verified archival.


## _local/flashlight-flicker/apply_bloom.py

SHA256: 1b8744c0506658278f4a1bab655b563ccc704a9992714435cca75178679fa519

```text
"""Prepare a reviewable fresh Bloom plan, then explicitly apply that exact plan.

Studio access requires the session lock. Prepare writes artifacts only. Apply
uses scoped Source/editor CAS and preserves unrelated repo WIP. No publication.
"""
import argparse
from copy import deepcopy
from datetime import datetime, timezone
import difflib
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

import qa
from capture_frames import LockedClient, djb2

ROOT = qa.ROOT
MANIFEST = ROOT / "studio-sync-manifest.json"
COMPILER = Path("C:/Users/mikke/AppData/Local/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Local/CodexTools/luau/0.737/luau-compile.exe")
OUT = ROOT / "artifacts/flashlight-flicker-20261008"
PLACE_ID = 131311258779917
NATIVE_KEYS = {"Enabled", "Intensity", "Size", "Threshold"}

LUA_COMMON = '''
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong place/universe")
assert(game:GetService("RunService"):IsEdit(), "Edit mode required")
local H, SES = game:GetService("HttpService"), game:GetService("ScriptEditorService")
local function hash(value)
    local result = 5381
    for index = 1, #value do result = (result * 33 + string.byte(value, index)) % 4294967296 end
    return result
end
local function resolve(segments)
    local item = game
    for _, segment in ipairs(segments) do
        local found, count = nil, 0
        for _, child in ipairs(item:GetChildren()) do
            if child.Name == segment then found, count = child, count + 1 end
        end
        assert(count == 1, "Missing/ambiguous target: " .. segment)
        item = found
    end
    return item
end
local function nativeCheck(item, entry)
    assert(item.ClassName == entry.className and item:GetFullName() == entry.studioPath, "Native identity changed")
    for key, value in pairs(entry.before) do assert(item[key] == value, "Native baseline changed: " .. key) end
end
local function sourceCheck(item, entry)
    assert(item.ClassName == entry.className and item:GetFullName() == entry.studioPath, "Source identity changed")
    assert(item.Enabled == entry.enabled, "Enabled baseline changed")
    local raw = item.Source
    assert(#raw == entry.rawSourceBytes and hash(raw) == entry.rawSourceDjb2, "Raw source baseline changed")
    assert(SES:GetEditorSource(item) == raw, "Source/editor baseline changed")
    return raw
end
local function hunks(source, changes)
    source = source:gsub("\\r\\n", "\\n")
    for _, change in ipairs(changes) do
        local first, last = source:find(change.old, 1, true)
        assert(first and not source:find(change.old, first + 1, true), "Scoped anchor missing/duplicate")
        source = source:sub(1, first - 1) .. change.new .. source:sub(last + 1)
    end
    return source
end
'''


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(data):
    data.decode("utf-8", errors="strict")
    return data.replace(b"\r\n", b"\n")


def lua_json(value):
    text = json.dumps(value, ensure_ascii=True, separators=(",", ":"))
    count = 0
    while "]" + "=" * count + "]" in text:
        count += 1
    return "[" + "=" * count + "[" + text + "]" + "=" * count + "]"


def json_read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def json_write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def project_path(relative):
    path = (ROOT / relative).resolve()
    if not path.is_relative_to(ROOT.resolve()):
        raise ValueError("Path outside workspace")
    return path


def artifact_path(relative):
    path = project_path(relative)
    if not path.is_relative_to((ROOT / "artifacts").resolve()):
        raise ValueError("Snapshot/candidate path outside artifacts")
    return path


def relative(path):
    return path.resolve().relative_to(ROOT.resolve()).as_posix()


def apply_hunks(data, changes):
    """Replace only owned byte ranges, preserving the rest, including repo CRLF."""
    data.decode("utf-8", errors="strict")
    for change in changes:
        old, new = change["old"], change["new"]
        if not isinstance(old, str) or not old or not isinstance(new, str) or old == new or "\r" in old + new:
            raise ValueError("Hunks require distinct LF text and a nonempty old anchor")
        variants = [(old.encode(), new.encode())]
        if "\n" in old:
            variants.append((old.replace("\n", "\r\n").encode(), new.replace("\n", "\r\n").encode()))
        occurrences = 0
        for anchor, _ in variants:
            first = data.find(anchor)
            while first >= 0:
                occurrences += 1
                first = data.find(anchor, first + 1)
        if occurrences != 1:
            raise ValueError("Owned anchor missing/duplicate (count=" + str(occurrences) + ")")
        for anchor, replacement in variants:
            if anchor in data:
                data = data.replace(anchor, replacement, 1)
                break
    return data


def source_entry(item, changes):
    if item["className"] not in ("LocalScript", "Script"):
        raise ValueError("Only existing BaseScript targets supported")
    entry = {"studioPath": item["studioPath"], "segments": item["studioPath"].split("."),
             "className": item["className"], "repoFile": item["file"], "changes": changes}
    project_path(entry["repoFile"])
    return entry


def validate_native(entries):
    for entry in entries:
        if entry.get("className") != "BloomEffect" or entry.get("studioPath") != ".".join(entry.get("segments", [])):
            raise ValueError("Native plan requires exact BloomEffect class/path/segments")
        if set(entry.get("before", {})) != NATIVE_KEYS or set(entry.get("after", {})) != {"Intensity"}:
            raise ValueError("Native plan needs all four fresh before properties and only an Intensity write")
        for key, value in {**entry["before"], **entry["after"]}.items():
            if key == "Enabled":
                if type(value) is not bool:
                    raise ValueError("Native Enabled must be bool")
            elif type(value) not in (int, float) or not math.isfinite(value) or value < 0:
                raise ValueError("Native numeric properties must be finite and nonnegative")
    if len({tuple(item["segments"]) for item in entries}) != len(entries):
        raise ValueError("Duplicate native target")


def connect():
    qa.check_lock()
    client = LockedClient(qa.find_mcp_batch())
    try:
        client.initialize()
        studios = json.loads(client.call("list_roblox_studios", {}))["studios"]
        matches = [item for item in studios if qa.studio_place_id(item) == PLACE_ID]
        if len(matches) != 1:
            raise RuntimeError("Expected one exact placeId Studio")
        return client, matches[0]["id"]
    except BaseException:
        client.close()
        raise


def execute(client, sid, code):
    text = client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code})
    result = json.loads(text)
    if not isinstance(result, dict):
        raise ValueError("Malformed execute result")
    return result


def metadata(client, sid, entries, natives):
    code = LUA_COMMON + "\nlocal requested = H:JSONDecode(" + lua_json({"sources": entries, "native": natives}) + ")\n" + '''
local out = {sources = {}, native = {}}
for _, entry in ipairs(requested.sources) do
    local item = resolve(entry.segments)
    assert(item.ClassName == entry.className and item:GetFullName() == entry.studioPath, "Source target changed")
    local raw, editor = item.Source, SES:GetEditorSource(item)
    assert(raw == editor, "Unresolved Source/editor mismatch")
    table.insert(out.sources, {studioPath=entry.studioPath, className=item.ClassName,
        enabled=item.Enabled, rawSourceBytes=#raw, rawSourceDjb2=hash(raw),
        rawEditorBytes=#editor, rawEditorDjb2=hash(editor), EditorMatches=true})
end
for _, entry in ipairs(requested.native) do
    local item = resolve(entry.segments)
    assert(item.ClassName == "BloomEffect" and item:GetFullName() == entry.studioPath, "Native target changed")
    table.insert(out.native, {studioPath=entry.studioPath, className=item.ClassName,
        before={Enabled=item.Enabled, Intensity=item.Intensity, Size=item.Size, Threshold=item.Threshold}})
end
return H:JSONEncode(out)
'''
    return execute(client, sid, code)


def snapshot(client, sid, entries, natives, folder):
    folder.mkdir(parents=True, exist_ok=False)
    before = metadata(client, sid, entries, natives)
    if len(before.get("sources", [])) != len(entries) or len(before.get("native", [])) != len(natives):
        raise ValueError("Metadata target count mismatch")
    records = []
    for entry, meta in zip(entries, before["sources"]):
        if meta["studioPath"] != entry["studioPath"]:
            raise ValueError("Metadata order mismatch")
        chunks, first = [], 1
        while first <= meta["rawSourceBytes"]:
            read_entry = {**entry, **meta}
            code = LUA_COMMON + "\nlocal entry = H:JSONDecode(" + lua_json(read_entry) + ")\n" + f'''
local raw = sourceCheck(resolve(entry.segments), entry)
local first, last = {first}, math.min({first} + 19999, #raw)
while last < #raw do
    local nextByte = string.byte(raw, last + 1)
    if nextByte < 128 or nextByte >= 192 then break end
    last -= 1
end
assert(last >= first, "UTF-8 source chunk failed")
return H:JSONEncode({{First=first, Next=last+1, Text=raw:sub(first,last)}})
'''
            part = execute(client, sid, code)
            if part.get("First") != first or not isinstance(part.get("Text"), str):
                raise ValueError("Malformed source chunk")
            data = part["Text"].encode("utf-8")
            if not 1 <= len(data) <= 20000 or part.get("Next") != first + len(data):
                raise ValueError("Source chunk byte/index mismatch")
            chunks.append(data)
            first = part["Next"]
        data = b"".join(chunks)
        if len(data) != meta["rawSourceBytes"] or djb2(data) != meta["rawSourceDjb2"]:
            raise ValueError("Raw source export byte/hash mismatch")
        target = folder / entry["repoFile"]
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        records.append({**meta, "file": relative(target), "sha256": sha(data)})
    after = metadata(client, sid, entries, natives)
    if before != after:
        raise RuntimeError("Source/editor/native changed during snapshot")
    result = {"utc": datetime.now(timezone.utc).isoformat(), "studioId": sid,
              "stable": True, "sources": records, "native": before["native"]}
    json_write(folder / "snapshot.json", result)
    return result


def check_repo_plan(plan):
    manifest = json_read(MANIFEST)
    by_file = {item["file"]: item for item in manifest["items"]}
    for entry in plan["sources"]:
        if sum(item.get("file") == entry["repoFile"] for item in manifest["items"]) != 1:

            raise RuntimeError("Scoped manifest item missing/duplicate: " + entry["repoFile"])
        expected = artifact_path(entry["repoBeforeFile"]).read_bytes()
        if sha(expected) != entry["repoBeforeSha256"] or project_path(entry["repoFile"]).read_bytes() != expected:
            raise RuntimeError("Repo changed since prepare: " + entry["repoFile"])
        if by_file.get(entry["repoFile"]) != entry["manifestBefore"]:
            raise RuntimeError("Scoped manifest item changed since prepare: " + entry["repoFile"])
        apply_hunks(expected, entry["changes"])
    return manifest


def manifest_after(item, repo_data, installed_data):
    result = deepcopy(item)
    repo, installed = canonical(repo_data), canonical(installed_data)
    result.update(bytes=len(repo), sha256=sha(repo))
    result.pop("studioTrailingNewline", None)
    if repo == installed:
        result["status"] = "synced"
        result.pop("studioSha256Before", None)
    else:
        result["status"] = "studio-push-conflict"
        result["studioSha256Before"] = sha(installed)
    return result


def write_existing_cas(path, before, desired):
    with path.open("r+b") as stream:
        if stream.read() != before:
            raise RuntimeError("File changed before scoped write: " + str(path))
        stream.seek(0)
        stream.write(desired)
        stream.truncate()


def merge_manifest_bytes(raw, sources, updates):
    manifest = json.loads(raw.decode("utf-8-sig"))
    original = {entry["repoFile"]: entry["manifestBefore"] for entry in sources}
    for item_file in original:
        if sum(item.get("file") == item_file for item in manifest["items"]) != 1:
            raise RuntimeError("Scoped manifest target missing/duplicate before final merge")
    for item in manifest["items"]:
        item_file = item["file"]
        if item_file in original:
            if item != original[item_file]:
                raise RuntimeError("Scoped manifest changed before mirror update")
            item.clear()
            item.update(updates[item_file])
    from studio_source_contract import refresh_trailing_newline_metadata
    refresh_trailing_newline_metadata(manifest)
    return (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def prepare(args):
    entries = json_read(args.patch)
    if not isinstance(entries, list) or not entries:
        raise ValueError("Patch must be a nonempty array")
    manifest = json_read(MANIFEST)
    by_path = {item["studioPath"]: item for item in manifest["items"]}
    sources = []
    for patch in entries:
        item = by_path[patch["studioPath"]]
        entry = source_entry(item, patch["changes"])
        if patch.get("segments", entry["segments"]) != entry["segments"]:
            raise ValueError("Source segments differ from manifest path")
        entry["manifestBefore"] = deepcopy(item)
        sources.append(entry)
    if len({item["repoFile"] for item in sources}) != len(sources):
        raise ValueError("Duplicate source target")
    natives = json_read(args.native_plan) if args.native_plan else []
    validate_native(natives)
    folder = args.out.resolve() / args.label
    artifact_path(relative(folder))
    folder.mkdir(parents=True, exist_ok=False)
    for entry in sources:
        data = project_path(entry["repoFile"]).read_bytes()
        candidate = apply_hunks(data, entry["changes"])
        path = folder / "repo-before" / entry["repoFile"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        entry.update(repoBeforeFile=relative(path), repoBeforeSha256=sha(data))
        repo_candidate = folder / "repo-candidates" / entry["repoFile"]
        repo_candidate.parent.mkdir(parents=True, exist_ok=True)
        repo_candidate.write_bytes(candidate)
    client, sid = connect()
    try:
        observed = snapshot(client, sid, sources, natives, folder / "studio-before")
    finally:
        client.close()
    for native, actual in zip(natives, observed["native"]):
        if {key: native[key] for key in ("studioPath", "className", "before")} != actual:
            raise RuntimeError("Native plan does not match fresh audit: " + native["studioPath"])
    compile_files = []
    for entry, actual in zip(sources, observed["sources"]):
        before = artifact_path(actual["file"]).read_bytes()
        candidate = apply_hunks(canonical(before), entry["changes"])
        path = folder / "studio-candidates" / entry["repoFile"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(candidate)
        entry.update({key: actual[key] for key in ("enabled", "rawSourceBytes", "rawSourceDjb2")})
        entry.update(studioBeforeFile=actual["file"], studioBeforeSha256=sha(before),
                     candidateFile=relative(path), candidateSha256=sha(candidate),
                     newBytes=len(candidate), newDjb2=djb2(candidate))
        diff = "".join(difflib.unified_diff(canonical(before).decode().splitlines(True), candidate.decode().splitlines(True),
            fromfile="Studio-before/" + entry["repoFile"], tofile="candidate/" + entry["repoFile"]))
        (folder / ("__".join(entry["segments"]) + ".diff")).write_text(diff, encoding="utf-8")
        compile_files += [str(path), str(folder / "repo-candidates" / entry["repoFile"])]
    subprocess.run([str(COMPILER), "-O0", "--null", *compile_files], check=True, capture_output=True)
    plan = {"formatVersion": 1, "utc": datetime.now(timezone.utc).isoformat(), "placeId": PLACE_ID,
            "studioIdObserved": sid, "sources": sources, "native": natives, "CompiledO0": True}
    check_repo_plan(plan)
    json_write(folder / "plan.json", plan)
    print(json.dumps({"plan": relative(folder / "plan.json"), "sources": len(sources), "native": len(natives), "StudioWritten": False}))


def apply_code(plan):
    payload = {"sources": plan["sources"], "native": plan["native"]}
    return LUA_COMMON + "\nlocal plan = H:JSONDecode(" + lua_json(payload) + ")\n" + '''
local targets, nativeTargets, applied, nativeApplied, nativeLanding = {}, {}, {}, {}, {}
-- Combined preflight: no source/property writes happen before all checks pass.
for _, entry in ipairs(plan.sources) do
    local item = resolve(entry.segments)
    local before = sourceCheck(item, entry)
    local candidate = hunks(before, entry.changes)
    assert(#candidate == entry.newBytes and hash(candidate) == entry.newDjb2, "Candidate drift")
    table.insert(targets, {item=item, entry=entry, before=before, candidate=candidate})
end
for _, entry in ipairs(plan.native) do
    local item = resolve(entry.segments)
    nativeCheck(item, entry)
    table.insert(nativeTargets, {item=item, entry=entry})
end
local ok, failure = pcall(function()
    for _, target in ipairs(targets) do
        SES:UpdateSourceAsync(target.item, function(current)
            local raw = sourceCheck(target.item, target.entry)
            assert(current == target.before and raw == target.before, "Fresh callback CAS changed")
            local candidate = hunks(current, target.entry.changes)
            assert(candidate == target.candidate, "Fresh callback candidate changed")
            return candidate
        end)
        assert(target.item.Source == target.candidate and SES:GetEditorSource(target.item) == target.candidate, "Installed Source/editor verification failed")
        table.insert(applied, target.entry.studioPath)
    end
    -- Recheck all native baselines together after potentially yielding updates.
    for _, target in ipairs(nativeTargets) do nativeCheck(target.item, target.entry) end
    for _, target in ipairs(nativeTargets) do
        target.item.Intensity = target.entry.after.Intensity
        local observed, wanted = target.item.Intensity, target.entry.after.Intensity
        assert(math.abs(observed - wanted) <= 1e-6, "Native landing failed")
        for key, value in pairs(target.entry.before) do
            if key ~= "Intensity" then assert(target.item[key] == value, "Other native property changed: " .. key) end
        end
        table.insert(nativeLanding, {studioPath=target.entry.studioPath, Wanted=wanted, Observed=observed, Tolerance=1e-6})
        table.insert(nativeApplied, target.entry.studioPath)
    end
end)
return H:JSONEncode({Ok=ok, Error=not ok and tostring(failure) or false,
    SourceApplied=applied, NativeApplied=nativeApplied, NativeLanding=nativeLanding})
'''


def apply(args):
    plan = json_read(args.plan)
    if plan.get("formatVersion") != 1 or plan.get("placeId") != PLACE_ID or plan.get("CompiledO0") is not True:
        raise ValueError("Unrecognized/uncompiled plan")
    validate_native(plan["native"])
    check_repo_plan(plan)
    folder = args.plan.resolve().parent
    artifact_path(relative(folder))
    receipt_path = folder / "apply-receipt.json"
    if receipt_path.exists():
        raise RuntimeError("Plan has already been attempted; prepare a new plan")
    for entry in plan["sources"]:
        before = artifact_path(entry["studioBeforeFile"]).read_bytes()
        candidate = artifact_path(entry["candidateFile"]).read_bytes()
        if sha(before) != entry["studioBeforeSha256"] or sha(candidate) != entry["candidateSha256"] or candidate != apply_hunks(canonical(before), entry["changes"]):
            raise RuntimeError("Plan baseline/candidate tampered")
    client, sid = connect()
    receipt = {"utc": datetime.now(timezone.utc).isoformat(), "Success": False, "RepoWritten": [], "Errors": []}
    try:
        fresh = snapshot(client, sid, plan["sources"], plan["native"], folder / "apply-fresh-before")
        for entry, actual in zip(plan["sources"], fresh["sources"]):
            if artifact_path(actual["file"]).read_bytes() != artifact_path(entry["studioBeforeFile"]).read_bytes() or actual["enabled"] != entry["enabled"]:
                raise RuntimeError("Studio source/class/enabled changed since prepare")
        for entry, actual in zip(plan["native"], fresh["native"]):
            if actual["before"] != entry["before"]:
                raise RuntimeError("Native properties changed since prepare")
        check_repo_plan(plan)  # Fresh repo bytes immediately before Studio write.
        receipt["StudioReceipt"] = execute(client, sid, apply_code(plan))
        installed = snapshot(client, sid, plan["sources"], plan["native"], folder / "installed")
        if receipt["StudioReceipt"].get("Ok") is not True:
            raise RuntimeError("Scoped install failed/partially applied; inspect StudioReceipt")
        repo_writes = []
        for entry, actual in zip(plan["sources"], installed["sources"]):
            data = artifact_path(actual["file"]).read_bytes()
            if data != artifact_path(entry["candidateFile"]).read_bytes() or actual["enabled"] != entry["enabled"]:
                raise RuntimeError("Installed Source/editor/enabled does not match candidate")
            repo_before = artifact_path(entry["repoBeforeFile"]).read_bytes()
            studio_before = artifact_path(entry["studioBeforeFile"]).read_bytes()
            desired = data if repo_before == studio_before else apply_hunks(repo_before, entry["changes"])
            repo_writes.append((entry, desired, data))
        for entry, actual in zip(plan["native"], installed["native"]):
            observed = actual["before"]
            if (any(observed[key] != entry["before"][key] for key in NATIVE_KEYS - {"Intensity"})
                    or abs(observed["Intensity"] - entry["after"]["Intensity"]) > 1e-6):
                raise RuntimeError("Native post-write verification mismatch")
        manifest = check_repo_plan(plan)
        by_file = {item["file"]: item for item in manifest["items"]}
        for entry, desired, data in repo_writes:
            path = project_path(entry["repoFile"])
            before = artifact_path(entry["repoBeforeFile"]).read_bytes()
            write_existing_cas(path, before, desired)
            by_file[entry["repoFile"]] = manifest_after(by_file[entry["repoFile"]], desired, data)
            receipt["RepoWritten"].append({"file": entry["repoFile"], "sha256": sha(desired), "status": by_file[entry["repoFile"]]["status"]})
        # Preserve all unrelated manifest entries; fail if anybody changed it meanwhile.
        manifest_bytes = MANIFEST.read_bytes()
        desired_manifest = merge_manifest_bytes(manifest_bytes, plan["sources"], by_file)
        write_existing_cas(MANIFEST, manifest_bytes, desired_manifest)
        receipt["Success"] = True
    except Exception as failure:
        receipt["Errors"].append(type(failure).__name__ + ": " + str(failure))
    finally:
        try:
            client.close()
        except Exception as failure:
            receipt["Success"] = False
            receipt["Errors"].append("MCP close failed: " + str(failure))
        json_write(receipt_path, receipt)
    print(json.dumps({"Success": receipt["Success"], "receipt": relative(receipt_path), "RepoWritten": len(receipt["RepoWritten"]), "Errors": receipt["Errors"]}))
    return 0 if receipt["Success"] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)
    prepare_parser = sub.add_parser("prepare", help="Fresh read-only Studio audit; artifacts only")
    prepare_parser.add_argument("--patch", type=Path, required=True)
    prepare_parser.add_argument("--native-plan", type=Path)
    prepare_parser.add_argument("--label", required=True)
    prepare_parser.add_argument("--out", type=Path, default=OUT)
    apply_parser = sub.add_parser("apply", help="Write only a reviewed unchanged prepared plan")
    apply_parser.add_argument("--plan", type=Path, required=True)
    args = parser.parse_args()
    if args.mode == "prepare":
        if not re.fullmatch(r"[A-Za-z0-9_-]+", args.label):
            parser.error("Invalid label")
        prepare(args)
        return 0
    return apply(args)


if __name__ == "__main__":
    raise SystemExit(main())

```


## _local/flashlight-flicker/attribute_transport.luau

SHA256: d72dfc4c5bbac92853775ac412b2e9e01dbb4e99f1c01538f32c191d41b8e2e6

```text
-- Template only. The offline runner substitutes the three @@ tokens.
-- Capture callbacks must be finalized by the probe before its return.
assert(game.PlaceId == 131311258779917, "Wrong place id")
local transportPlayer = assert(game:GetService("Players").LocalPlayer, "Client required")
local H = game:GetService("HttpService")
local transportPrefix = @@PREFIX@@
local transportNonce = @@NONCE@@
local transportMetaKey = transportPrefix .. "meta"
local transportLimit, transportMaxChunks = 20000, 256
local function transportDjb2(value)
	local hash = 5381
	for index = 1, #value do hash = (hash * 33 + string.byte(value, index)) % 4294967296 end
	return hash
end
local function transportSplit(value)
	assert(utf8.len(value) ~= nil, "Payload is not valid UTF-8")
	local chunks, first = {}, 1
	while first <= #value do
		local last = math.min(first + transportLimit - 1, #value)
		while last < #value do
			local nextByte = string.byte(value, last + 1)
			if nextByte < 128 or nextByte >= 192 then break end
			last -= 1
		end
		assert(last >= first, "UTF-8 split made no progress")
		table.insert(chunks, value:sub(first, last))
		assert(#chunks <= transportMaxChunks, "Payload exceeds bounded attribute count")
		first = last + 1
	end
	return chunks
end
for key in pairs(transportPlayer:GetAttributes()) do
	if key:sub(1, #transportPrefix) == transportPrefix then
		return H:JSONEncode({Transport = "player_attributes_v1", Status = "Collision",
			Nonce = transportNonce, Prefix = transportPrefix, Stored = false})
	end
end
-- A reservation establishes ownership before any chunk is created.
local transportWritten, transportCleanupErrors = {}, {}
local function transportWrite(key, value)
	table.insert(transportWritten, key)
	transportPlayer:SetAttribute(key, value)
	assert(transportPlayer:GetAttribute(key) == value, "Attribute write/readback failed")
end
local transportOk, transportResult = pcall(function()
	transportWrite(transportMetaKey, H:JSONEncode({Nonce = transportNonce, Prefix = transportPrefix, Status = "Reserved"}))
	local transportPayload = (function()
@@PROBE@@
	end)()
	-- The original JSON is retained byte-for-byte, including every raw row.
	assert(type(transportPayload) == "string" and #transportPayload > 0, "Probe must return JSON text")
	local transportChunks = transportSplit(transportPayload)
	for index, chunk in ipairs(transportChunks) do
		transportWrite(transportPrefix .. tostring(index), chunk)
	end
	local receipt = {Transport = "player_attributes_v1", Status = "Ready", Stored = true,
		Nonce = transportNonce, Prefix = transportPrefix, Count = #transportChunks,
		Bytes = #transportPayload, Djb2 = transportDjb2(transportPayload), ChunkBytes = transportLimit}
	local encodedReceipt = H:JSONEncode(receipt)
	transportPlayer:SetAttribute(transportMetaKey, encodedReceipt)
	assert(transportPlayer:GetAttribute(transportMetaKey) == encodedReceipt, "Metadata readback failed")
	return receipt
end)
if not transportOk then
	for _, key in ipairs(transportWritten) do
		if key ~= transportMetaKey then
			local removed, removeError = pcall(function() transportPlayer:SetAttribute(key, nil) end)
			if not removed then table.insert(transportCleanupErrors, tostring(removeError)) end
		end
	end
	-- Retain ownership metadata if a partial chunk deletion needs a later retry.
	if #transportCleanupErrors == 0 then
		local removed, removeError = pcall(function() transportPlayer:SetAttribute(transportMetaKey, nil) end)
		if not removed then table.insert(transportCleanupErrors, tostring(removeError)) end
	end
	return H:JSONEncode({Transport = "player_attributes_v1", Status = "Error", Stored = false,
		Nonce = transportNonce, Prefix = transportPrefix, Error = tostring(transportResult),
		CleanupErrors = transportCleanupErrors})
end
return H:JSONEncode(transportResult)

```


## _local/flashlight-flicker/B-bloom-comp8.luau

SHA256: 65ccf93aecfe9130eb734b8d8a14ac5229ec36b285ec5f72aea918e8c75b1baa

```text
-- Bounded visual comparison: original vs 20% less Bloom, same camera/quality.
-- Take screenshots around t=1.5 and t=4.5 seconds while this call is active.
local H=game:GetService("HttpService")
local R=game:GetService("RunService")
local p=assert(game.Players.LocalPlayer)
local c=assert(workspace.CurrentCamera)
assert(game.PlaceId==131311258779917 and game.GameId==10559217407)
assert(p.Character and p.Character.Humanoid.Health>0)
local oldType,oldCF=c.CameraType,c.CFrame
local rendering=settings().Rendering
local oldQuality,oldEdit,oldFRM=rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM
local effects,original,rows,errors={},{},{},{}
local activeCount=0
for _,root in {game.Lighting,c} do for _,e in root:GetDescendants() do if e:IsA("BloomEffect") then
 effects[#effects+1]={path=e:GetFullName(),enabled=e.Enabled,intensity=e.Intensity,size=e.Size,threshold=e.Threshold}
 original[#original+1]={instance=e,enabled=e.Enabled,intensity=e.Intensity}
 if e.Enabled then activeCount+=1 end
end end end
assert(activeCount>0,"No active Bloom for a meaningful comparison")
local name="MongoBloomComparison"
local start=time()
local added,removed,maxCameraDeviation=0,0,0
local startedUnixMs,endedUnixMs
local appliedQuality
local connections={}
local ok,err=pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 appliedQuality={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM}
 assert(rendering.QualityLevel==Enum.QualityLevel.Level21 and rendering.EditQualityLevel==Enum.QualityLevel.Level21 and rendering.EnableFRM==false,"High quality not applied")
 c.CameraType=Enum.CameraType.Scriptable
 for _,root in {game.Lighting,c} do
  connections[#connections+1]=root.DescendantAdded:Connect(function(x)if x:IsA("BloomEffect")then added+=1 end end)
  connections[#connections+1]=root.DescendantRemoving:Connect(function(x)if x:IsA("BloomEffect")then removed+=1 end end)
 end
 start=time()
 startedUnixMs=DateTime.now().UnixTimestampMillis
 R:BindToRenderStep(name,Enum.RenderPriority.Camera.Value+4,function()
  if #errors>0 then return end
  local sampled,failure=pcall(function()
   local elapsed=time()-start
   local factor=if elapsed<4 then 1.25 else 1
   assert(workspace.CurrentCamera==c,"CurrentCamera replaced")
   c.CFrame=oldCF
   maxCameraDeviation=math.max(maxCameraDeviation,(c.CFrame.Position-oldCF.Position).Magnitude,(c.CFrame.LookVector-oldCF.LookVector).Magnitude)
   local row={elapsed,factor}
   for _,x in original do
    assert(x.instance.Parent,"Bloom instance removed during comparison")
    x.instance.Enabled=x.enabled
    x.instance.Intensity=x.intensity*factor
    row[#row+1]={x.instance.Enabled,x.instance.Intensity}
   end
   rows[#rows+1]=row
  end)
  if not sampled then errors[#errors+1]=tostring(failure) end
 end)
 while time()-start<8 and #errors==0 do task.wait(.05)end
 endedUnixMs=DateTime.now().UnixTimestampMillis
end)
local function cleanup(action)
 local cleaned,failure=pcall(action)
 if not cleaned then errors[#errors+1]="cleanup: "..tostring(failure)end
end
cleanup(function()R:UnbindFromRenderStep(name)end)
for _,connection in connections do cleanup(function()connection:Disconnect()end)end
for _,x in original do if x.instance.Parent then
 cleanup(function()x.instance.Enabled=x.enabled end)
 cleanup(function()x.instance.Intensity=x.intensity end)
end end
cleanup(function()c.CFrame=oldCF end)
cleanup(function()c.CameraType=oldType end)
cleanup(function()rendering.QualityLevel=oldQuality end)
cleanup(function()rendering.EditQualityLevel=oldEdit end)
cleanup(function()rendering.EnableFRM=oldFRM end)
if not ok then errors[#errors+1]=tostring(err)end
local state=game.ReplicatedStorage:FindFirstChild("Level 4 State")
return H:JSONEncode({kind="Temporary Bloom visual comparison, not a flicker verdict",duration=8,
 startedUnixMs=startedUnixMs,endedUnixMs=endedUnixMs,
 complete=#errors==0 and added==0 and removed==0 and workspace.CurrentCamera==c and maxCameraDeviation==0 and #rows>0 and rows[#rows][1]>=7.7,errors=errors,bloomAdded=added,bloomRemoved=removed,maxCameraDeviation=maxCameraDeviation,
 variants={1.25,1},effects=effects,rows=rows,camera={oldCF:GetComponents()},quality=appliedQuality,
 viewport={c.ViewportSize.X,c.ViewportSize.Y},touch=game.UserInputService.TouchEnabled,
 level=workspace:GetAttribute("SelectedLevel"),roundActive=workspace:GetAttribute("RoundActive"),
 inRound=p:GetAttribute("InRound"),powerState=state and state:GetAttribute("Level4_PowerState")})

```


## _local/flashlight-flicker/B-controller-cases.luau

SHA256: 017fab9470fc73fe33dd3624a752ca42336755b8cbfab1cf6476add38855efda

```text
assert(game.PlaceId==131311258779917 and game.GameId==10559217407)
local p=assert(game.Players.LocalPlayer)
local L=game.Lighting
local rec,rows={},{}
local function set(o,k,v)rec[#rec+1]={o,k,o:GetAttribute(k)};o:SetAttribute(k,v)end
local function sample(label,name,wanted)
 local e=assert(L:FindFirstChild(name),name)
 rows[#rows+1]={label=label,name=name,enabled=e.Enabled,intensity=e.Intensity,wanted=wanted}
 assert(e.Enabled and math.abs(e.Intensity-wanted)<1e-6,label..' mismatch')
end
local s2=assert(game.ReplicatedStorage:FindFirstChild('Level 2 State'))
local s3=assert(game.ReplicatedStorage:FindFirstChild('Level 3 State'))
local ok,err=pcall(function()
 assert(p:GetAttribute('InRound')~=true and workspace:GetAttribute('RoundActive')~=true)
 sample('Lobby','Bloom',.8)
 set(workspace,'SelectedLevel',2);set(workspace,'Level2LightingOwnedByController',true);set(p,'InRound',true)
 set(s2,'Level2_LightingMode','NORMAL');task.wait(.9);sample('L2 NORMAL','Level 2 Client Bloom',.068)
 set(s2,'Level2_LightingMode','EXIT_OPEN');task.wait(.9);sample('L2 EXIT_OPEN','Level 2 Client Bloom',.088)
 set(workspace,'Level2LightingOwnedByController',false);set(p,'InRound',false);task.wait(.3)
 set(workspace,'SelectedLevel',3);set(workspace,'Level3LightingOwnedByController',true);set(s3,'Level3_ExitUnlocked',false);set(p,'InRound',true)
 task.wait(1);sample('L3 LOCKED','Level3ClientBloom',.064)
 set(s3,'Level3_ExitUnlocked',true);task.wait(1);sample('L3 UNLOCKED','Level3ClientBloom',.088)
 set(workspace,'Level3LightingOwnedByController',false);set(p,'InRound',false);task.wait(.6)
 set(workspace,'SelectedLevel',1);set(p,'Level6PlaygroundPreview',true);task.wait(.6)
 sample('L6 Playground','Level6PlaygroundBloom',.24)
 set(p,'Level6PlaygroundPreview',false);task.wait(.6)
 sample('Lobby restored','Bloom',.8)
end)
for i=#rec,1,-1 do local r=rec[i];r[1]:SetAttribute(r[2],r[3])end
task.wait(.6)
return game.HttpService:JSONEncode({kind='Scoped runtime controller activation, not full rounds',ok=ok,error=not ok and tostring(err) or nil,rows=rows,cleanup=true,finalInRound=p:GetAttribute('InRound'),finalLevel=workspace:GetAttribute('SelectedLevel')})

```


## _local/flashlight-flicker/B-L1-PC-high-after.luau

SHA256: e389018826638498e42e8ca53f34bef04df36e8deed0dfe145996e76ffcabde3

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-high-quality-bloom-on",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
assert(workspace:GetAttribute("RoundActive") and player.Character.FlashlightOn.Value,"Requires active round and torch")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = oldCameraCF
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/B-L1-PC-high-reference.luau

SHA256: 684b2bdd53483da2da16e5aa4b9b41ecd2bcf88ba3ff266b39f8440665c67b22

```text
local bloom=assert(game.Lighting:FindFirstChild("Bloom"))
local oldIntensity=bloom.Intensity
bloom.Intensity=1
local ok,result=pcall(function()
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-high-quality-bloom-on",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
assert(workspace:GetAttribute("RoundActive") and player.Character.FlashlightOn.Value,"Requires active round and torch")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = oldCameraCF
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

end)
bloom.Intensity=oldIntensity
assert(math.abs(bloom.Intensity-oldIntensity)<1e-6,"Bloom restore failed")
if not ok then error(result) end
local report=game.HttpService:JSONDecode(result)
local function json(value)return game.HttpService:JSONEncode(value)end
return json(report)

```


## _local/flashlight-flicker/B-L4-high-reference.luau

SHA256: 7856785b160bf799fabd22f2a7e16c1568b06efb4aa18f91bd34d92985cbe4d9

```text
local R=game:GetService("RunService")
local e=assert(game.Lighting:FindFirstChild("Level 4 Client Bloom"))
local old=e.Intensity
local bloomRows={}
local name="MongoBloomReference"
R:BindToRenderStep(name,Enum.RenderPriority.Camera.Value+3,function()e.Intensity=.5;bloomRows[#bloomRows+1]=e.Intensity end)
local ok,result=pcall(function()
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "B-L4-high-reference",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = CFrame.lookAt(oldCameraCF.Position, Vector3.new(28863.865,29.7,101))
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Level 4 Client Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

end)
R:UnbindFromRenderStep(name)
e.Intensity=old
if not ok then error(result)end
local report=game.HttpService:JSONDecode(result)
report.QA_ReferenceRenderBloom=bloomRows
local function json(v)return game.HttpService:JSONEncode(v)end
return json(report)

```


## _local/flashlight-flicker/B-L4-PC-high-after.luau

SHA256: 67a4244c6ee5d9c6d912c8c2e3c9bf4e8029e32ac6d49275eb6507ada9624116

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "B-L4-PC-high-after",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = CFrame.lookAt(oldCameraCF.Position, Vector3.new(28863.865,29.7,101))
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Level 4 Client Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/bloom-comparison.luau

SHA256: 33ddfd37748f6aec91e282c4d820497d8a9695d193096bd3be8f2415eef0666c

```text
-- Bounded visual comparison: original vs 20% less Bloom, same camera/quality.
-- Take screenshots around t=1.5 and t=4.5 seconds while this call is active.
local H=game:GetService("HttpService")
local R=game:GetService("RunService")
local p=assert(game.Players.LocalPlayer)
local c=assert(workspace.CurrentCamera)
assert(game.PlaceId==131311258779917 and game.GameId==10559217407)
assert(p.Character and p.Character.Humanoid.Health>0)
local oldType,oldCF=c.CameraType,c.CFrame
local rendering=settings().Rendering
local oldQuality,oldEdit,oldFRM=rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM
local effects,original,rows,errors={},{},{},{}
local activeCount=0
for _,root in {game.Lighting,c} do for _,e in root:GetDescendants() do if e:IsA("BloomEffect") then
 effects[#effects+1]={path=e:GetFullName(),enabled=e.Enabled,intensity=e.Intensity,size=e.Size,threshold=e.Threshold}
 original[#original+1]={instance=e,enabled=e.Enabled,intensity=e.Intensity}
 if e.Enabled then activeCount+=1 end
end end end
assert(activeCount>0,"No active Bloom for a meaningful comparison")
local name="MongoBloomComparison"
local start=time()
local added,removed,maxCameraDeviation=0,0,0
local startedUnixMs,endedUnixMs
local appliedQuality
local connections={}
local ok,err=pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 appliedQuality={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM}
 assert(rendering.QualityLevel==Enum.QualityLevel.Level21 and rendering.EditQualityLevel==Enum.QualityLevel.Level21 and rendering.EnableFRM==false,"High quality not applied")
 c.CameraType=Enum.CameraType.Scriptable
 for _,root in {game.Lighting,c} do
  connections[#connections+1]=root.DescendantAdded:Connect(function(x)if x:IsA("BloomEffect")then added+=1 end end)
  connections[#connections+1]=root.DescendantRemoving:Connect(function(x)if x:IsA("BloomEffect")then removed+=1 end end)
 end
 start=time()
 startedUnixMs=DateTime.now().UnixTimestampMillis
 R:BindToRenderStep(name,Enum.RenderPriority.Camera.Value+4,function()
  if #errors>0 then return end
  local sampled,failure=pcall(function()
   local elapsed=time()-start
   local factor=if elapsed<3 then 1 else .8
   assert(workspace.CurrentCamera==c,"CurrentCamera replaced")
   c.CFrame=oldCF
   maxCameraDeviation=math.max(maxCameraDeviation,(c.CFrame.Position-oldCF.Position).Magnitude,(c.CFrame.LookVector-oldCF.LookVector).Magnitude)
   local row={elapsed,factor}
   for _,x in original do
    assert(x.instance.Parent,"Bloom instance removed during comparison")
    x.instance.Enabled=x.enabled
    x.instance.Intensity=x.intensity*factor
    row[#row+1]={x.instance.Enabled,x.instance.Intensity}
   end
   rows[#rows+1]=row
  end)
  if not sampled then errors[#errors+1]=tostring(failure) end
 end)
 while time()-start<6 and #errors==0 do task.wait(.05)end
 endedUnixMs=DateTime.now().UnixTimestampMillis
end)
local function cleanup(action)
 local cleaned,failure=pcall(action)
 if not cleaned then errors[#errors+1]="cleanup: "..tostring(failure)end
end
cleanup(function()R:UnbindFromRenderStep(name)end)
for _,connection in connections do cleanup(function()connection:Disconnect()end)end
for _,x in original do if x.instance.Parent then
 cleanup(function()x.instance.Enabled=x.enabled end)
 cleanup(function()x.instance.Intensity=x.intensity end)
end end
cleanup(function()c.CFrame=oldCF end)
cleanup(function()c.CameraType=oldType end)
cleanup(function()rendering.QualityLevel=oldQuality end)
cleanup(function()rendering.EditQualityLevel=oldEdit end)
cleanup(function()rendering.EnableFRM=oldFRM end)
if not ok then errors[#errors+1]=tostring(err)end
local state=game.ReplicatedStorage:FindFirstChild("Level 4 State")
return H:JSONEncode({kind="Temporary Bloom visual comparison, not a flicker verdict",duration=6,
 startedUnixMs=startedUnixMs,endedUnixMs=endedUnixMs,
 complete=#errors==0 and added==0 and removed==0 and workspace.CurrentCamera==c and maxCameraDeviation==0 and #rows>0 and rows[#rows][1]>=5.7,errors=errors,bloomAdded=added,bloomRemoved=removed,maxCameraDeviation=maxCameraDeviation,
 variants={1,.8},effects=effects,rows=rows,camera={oldCF:GetComponents()},quality=appliedQuality,
 viewport={c.ViewportSize.X,c.ViewportSize.Y},touch=game.UserInputService.TouchEnabled,
 level=workspace:GetAttribute("SelectedLevel"),roundActive=workspace:GetAttribute("RoundActive"),
 inRound=p:GetAttribute("InRound"),powerState=state and state:GetAttribute("Level4_PowerState")})

```


## _local/flashlight-flicker/bloom-inventory.luau

SHA256: 527446f1b67f19f67909d4b9e33ed9a4bb087bb3841fcf31e6e88ffa878999c0

```text
assert(game.PlaceId==131311258779917 and game.GameId==10559217407)
assert(game:GetService("RunService"):IsEdit(),"Inventory requires Edit")
local ses=game:GetService("ScriptEditorService")
local result={scripts={},effects={},level2Models={},sourceReadErrors={}}
local function hash(s)
 local h=5381
 for i=1,#s do h=(h*33+string.byte(s,i))%4294967296 end
 return h
end
for _,s in game:GetDescendants() do
  if s:IsA("LuaSourceContainer") then
   local readable,raw=pcall(function()return s.Source end)
   if not readable then
    table.insert(result.sourceReadErrors,{path=s:GetFullName(),error=tostring(raw)})
   elseif raw:lower():find("bloom",1,true) or s.Name:match("[Ll]evel.?5.*[Ll]ight") then
    local ok,editor=pcall(function()return ses:GetEditorSource(s)end)
    table.insert(result.scripts,{path=s:GetFullName(),class=s.ClassName,enabled=s:IsA("BaseScript") and s.Enabled or nil,
     bytes=#raw,djb2=hash(raw),editorReadable=ok,editorMatches=ok and editor==raw,
     hasBloomEffect=raw:find("BloomEffect",1,true)~=nil})
   end
  end
end
for _,root in {game:GetService("Lighting"),workspace.CurrentCamera} do
 if root then for _,e in root:GetDescendants() do if e:IsA("BloomEffect") then
  table.insert(result.effects,{path=e:GetFullName(),class=e.ClassName,enabled=e.Enabled,intensity=e.Intensity,size=e.Size,threshold=e.Threshold})
 end end end
end
for _,m in workspace:GetChildren() do
 if m.Name:match("Level.?2") then table.insert(result.level2Models,{path=m:GetFullName(),GradeBloom=m:GetAttribute("GradeBloom")}) end
end
return game:GetService("HttpService"):JSONEncode(result)

```


## _local/flashlight-flicker/bounded-frame-probe.luau

SHA256: 25c4824aa5efaabaf4e325f249c6c16a85032d59e77a8b169ce6546b7662f240

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-own-wall-near-before",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 8, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = false,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = oldCameraCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config,
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/capture.py

SHA256: 2ea7500de5fb0891c4518823c16a95feb9d5e30c2b4e428836452e1927c556e3

```text
import base64
import json
from pathlib import Path
import sys
from datetime import datetime, timezone
from qa import check_lock, ROOT, OUT
from sync_from_studio import StudioMcpClient, find_mcp_batch, studio_place_id

label = sys.argv[1]
assert label.replace('-', '').replace('_', '').isalnum()
check_lock()
c = StudioMcpClient(find_mcp_batch())
try:
    c.initialize()
    matches = [s for s in json.loads(c.call('list_roblox_studios', {}))['studios'] if studio_place_id(s) == 131311258779917]
    assert len(matches) == 1
    check_lock()
    requested = datetime.now(timezone.utc)
    response = c._request('tools/call', {'name':'screen_capture','arguments':{'studio_id':matches[0]['id'],'capture_id':label}}, timeout=30)
    returned = datetime.now(timezone.utc)
finally:
    c.close()
OUT.mkdir(parents=True, exist_ok=True)
result = response.get('result', {})
assert not result.get('isError'), result
images = [x for x in result.get('content', []) if x.get('type') == 'image']
assert len(images) == 1, result
path = OUT / (label + '.png')
path.write_bytes(base64.b64decode(images[0]['data']))
(OUT / (label + '.capture.json')).write_text(json.dumps({'requestedUTC':requested.isoformat(),
    'returnedUTC':returned.isoformat(), 'requestedUnixMs':int(requested.timestamp()*1000),
    'returnedUnixMs':int(returned.timestamp()*1000), 'studioId':matches[0]['id'],
    'imageFile':str(path)}, indent=2) + '\n', encoding='utf-8')
print(path)

```


## _local/flashlight-flicker/capture_frames.py

SHA256: c3a75c101ace5a1df744e68d42a5de39bf0084af9f25eb7b8df91addff48eaed

```text
"""Bounded Client probe transport. Only the current Studio lock holder may run it.

This does not edit a Studio script. The probe must return json(report) AFTER its
same-call callback/camera finalizer. Attribute/JSONEncode capabilities remain
unverified until transport-smoke.luau succeeds under an actual Studio grant.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import secrets
import sys

import qa  # Reuse this session's MCP client, exact place selector and lock guard.

PLACE_ID = 131311258779917
CHUNK_BYTES = 20000
MAX_CHUNKS = 256
TEMPLATE = Path(__file__).with_name("attribute_transport.luau")


class LockedClient(qa.StudioMcpClient):
    def _send(self, payload):
        # Includes initialize, initialized notification and every tools/call.
        qa.check_lock()
        return super()._send(payload)


def djb2(payload):
    value = 5381
    for byte in payload:
        value = (value * 33 + byte) & 0xFFFFFFFF
    return value


def make_capture(probe, nonce):
    if not re.fullmatch(r"[0-9a-f]{24}", nonce):
        raise ValueError("Invalid transport nonce")
    # A syntactic contract, not proof that an arbitrary probe finalized callbacks.
    if not re.search(r"return\s+json\s*\(\s*report\s*\)\s*\Z", probe):
        raise ValueError("Probe must end with return json(report)")
    prefix = "FFP_" + nonce + "_"
    template = TEMPLATE.read_text(encoding="utf-8")
    for token in ("@@PREFIX@@", "@@NONCE@@", "@@PROBE@@"):
        if template.count(token) != 1:
            raise ValueError("Malformed transport template: " + token)
    # Substitute the probe last; token-like text within a probe stays untouched.
    code = template.replace("@@PREFIX@@", json.dumps(prefix)).replace("@@NONCE@@", json.dumps(nonce))
    return prefix, code.replace("@@PROBE@@", probe)


def execute(client, sid, code, timeout=30):
    response = client._request("tools/call", {"name": "execute_luau", "arguments": {
        "studio_id": sid, "datamodel_type": "Client", "code": code}}, timeout=timeout)
    result = response.get("result", {})
    if result.get("isError"):
        raise RuntimeError("execute_luau returned isError")
    blocks = result.get("content")
    if not isinstance(blocks, list):
        raise ValueError("MCP result has no content list")
    texts = [block.get("text") for block in blocks if block.get("type") == "text"]
    if len(texts) != 1 or not isinstance(texts[0], str):
        raise ValueError("Expected exactly one MCP JSON text block")
    parsed = json.loads(texts[0])
    if not isinstance(parsed, dict):
        raise ValueError("Expected JSON object transport result")
    return parsed


def client_preamble(prefix, nonce):
    return f'''assert(game.PlaceId == {PLACE_ID}, "Wrong place id")
local P = assert(game:GetService("Players").LocalPlayer, "Client required")
local H = game:GetService("HttpService")
local prefix, nonce = {json.dumps(prefix)}, {json.dumps(nonce)}
'''


def fetch_code(prefix, nonce, index):
    return client_preamble(prefix, nonce) + f'''
local meta = H:JSONDecode(assert(P:GetAttribute(prefix .. "meta"), "Transport metadata missing"))
assert(meta.Nonce == nonce and meta.Prefix == prefix and meta.Status == "Ready", "Transport ownership/state mismatch")
local text = assert(P:GetAttribute(prefix .. tostring({index})), "Chunk missing")
assert(type(text) == "string", "Chunk type mismatch")
P:SetAttribute(prefix .. tostring({index}), nil)
assert(P:GetAttribute(prefix .. tostring({index})) == nil, "Chunk removal failed")
return H:JSONEncode({{Index = {index}, Text = text}})
'''


def cleanup_code(prefix, nonce):
    return client_preamble(prefix, nonce) + '''
local value = P:GetAttribute(prefix .. "meta")
local owned = false
if type(value) == "string" then
    local ok, meta = pcall(function() return H:JSONDecode(value) end)
    owned = ok and type(meta) == "table" and meta.Nonce == nonce and meta.Prefix == prefix
end
local removed, errors = 0, {}
if owned then
    for key in pairs(P:GetAttributes()) do
        if key:sub(1, #prefix) == prefix and key ~= prefix .. "meta" then
            local ok, failure = pcall(function() P:SetAttribute(key, nil) end)
            if ok then removed += 1 else table.insert(errors, tostring(failure)) end
        end
    end
    -- Keep ownership metadata if any chunk removal failed, so retry is safe.
    if #errors == 0 then
        local ok, failure = pcall(function() P:SetAttribute(prefix .. "meta", nil) end)
        if ok then removed += 1 else table.insert(errors, tostring(failure)) end
    end
end
local remaining = {}
for key in pairs(P:GetAttributes()) do
    if key:sub(1, #prefix) == prefix then table.insert(remaining, key) end
end
return H:JSONEncode({Owned = owned, Removed = removed, Remaining = remaining, Errors = errors,
    Clean = #remaining == 0 and #errors == 0})
'''


def validate_manifest(manifest, prefix, nonce):
    expected = {"Transport": "player_attributes_v1", "Status": "Ready", "Stored": True,
                "Nonce": nonce, "Prefix": prefix, "ChunkBytes": CHUNK_BYTES}
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise ValueError("Transport manifest mismatch: " + key)
    for key in ("Count", "Bytes", "Djb2"):
        if type(manifest.get(key)) is not int:
            raise ValueError("Transport integer missing: " + key)
    if not 1 <= manifest["Count"] <= MAX_CHUNKS:
        raise ValueError("Transport chunk count outside bound")
    if not 1 <= manifest["Bytes"] <= manifest["Count"] * CHUNK_BYTES:
        raise ValueError("Transport byte count outside bound")
    if not 0 <= manifest["Djb2"] <= 0xFFFFFFFF:
        raise ValueError("Transport checksum outside bound")


def assemble(manifest, chunks):
    if len(chunks) != manifest["Count"]:
        raise ValueError("Missing transport chunks")
    encoded = []
    for index, chunk in enumerate(chunks, 1):
        if type(chunk.get("Index")) is not int or chunk["Index"] != index or not isinstance(chunk.get("Text"), str):
            raise ValueError("Malformed or out-of-order chunk")
        raw = chunk["Text"].encode("utf-8", errors="strict")
        if not 1 <= len(raw) <= CHUNK_BYTES:
            raise ValueError("Chunk byte size outside bound")
        encoded.append(raw)
    payload = b"".join(encoded)
    if len(payload) != manifest["Bytes"] or djb2(payload) != manifest["Djb2"]:
        raise ValueError("Assembled payload byte/checksum mismatch")
    text = payload.decode("utf-8", errors="strict")
    report = json.loads(text)
    if not isinstance(report, dict):
        raise ValueError("Probe report must be JSON object")
    return payload, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=qa.OUT)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.label):
        parser.error("label must contain only letters, digits, underscore or dash")
    args.out.mkdir(parents=True, exist_ok=True)
    target = args.out / (args.label + ".txt")
    receipt_path = args.out / (args.label + ".transport.json")
    if target.exists() or receipt_path.exists():
        parser.error("evidence label already exists; choose a new label")
    probe = args.probe.read_text(encoding="utf-8-sig")
    nonce = secrets.token_hex(12)
    prefix, code = make_capture(probe, nonce)
    receipt = {"utc": datetime.now(timezone.utc).isoformat(), "label": args.label,
               "probe": str(args.probe), "probeSha256": hashlib.sha256(probe.encode()).hexdigest(),
               "prefix": prefix, "nonce": nonce, "placeId": PLACE_ID, "mode": "Client",
               "Success": False, "AssemblyVerified": False, "CleanupVerified": False,
               "FetchedChunks": 0, "Errors": []}
    client, sid, capture_attempted, collision, payload, report = None, None, False, False, None, None
    try:
        qa.check_lock()
        client = LockedClient(qa.find_mcp_batch())
        client.initialize()
        studios = json.loads(client.call("list_roblox_studios", {}))["studios"]
        matches = [item for item in studios if qa.studio_place_id(item) == PLACE_ID]
        if len(matches) != 1:
            raise RuntimeError("Expected exactly one Studio matching exact placeId")
        sid = matches[0]["id"]
        receipt["studioId"] = sid
        capture_attempted = True
        manifest = execute(client, sid, code, timeout=45)
        receipt["Manifest"] = manifest
        collision = (manifest.get("Status") == "Collision" and manifest.get("Stored") is False
                     and manifest.get("Transport") == "player_attributes_v1"
                     and manifest.get("Prefix") == prefix and manifest.get("Nonce") == nonce)
        validate_manifest(manifest, prefix, nonce)
        chunks = []
        for index in range(1, manifest["Count"] + 1):
            chunk = execute(client, sid, fetch_code(prefix, nonce, index))
            chunks.append(chunk)
            receipt["FetchedChunks"] = len(chunks)
        payload, report = assemble(manifest, chunks)
        receipt["AssemblyVerified"] = True
        receipt["PayloadSha256"] = hashlib.sha256(payload).hexdigest()
        receipt["ProbeSummary"] = {key: report[key] for key in
            ("Complete", "FrameCount", "MeasuredDuration", "Summary", "Errors") if key in report}
        # Save valid full evidence even if final cleanup later fails; receipt says so.
        with target.open("xb") as stream:
            stream.write(payload)
        receipt["saved"] = str(target)
    except Exception as failure:
        receipt["Errors"].append(type(failure).__name__ + ": " + str(failure))
    finally:
        if client is not None and sid is not None and capture_attempted and not collision:
            try:
                cleanup = execute(client, sid, cleanup_code(prefix, nonce))
                receipt["Cleanup"] = cleanup
                receipt["CleanupVerified"] = (cleanup.get("Clean") is True
                    and cleanup.get("Remaining") == [] and cleanup.get("Errors") == [])
                if not receipt["CleanupVerified"]:
                    receipt["Errors"].append("Temporary attribute cleanup not verified")
            except Exception as failure:
                # The lock guard applies here too: never clean after losing ownership.
                receipt["Errors"].append("Cleanup failed/unverified: " + type(failure).__name__ + ": " + str(failure))
        elif collision:
            receipt["CleanupSkipped"] = "Collision: existing prefix attributes were not ours"
        if client is not None:
            try:
                client.close()
            except Exception as failure:
                receipt["Errors"].append("MCP client close failed: " + type(failure).__name__ + ": " + str(failure))
        receipt["Success"] = bool(receipt["AssemblyVerified"] and receipt["CleanupVerified"] and not receipt["Errors"])
        with receipt_path.open("x", encoding="utf-8") as stream:
            json.dump(receipt, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
    print(json.dumps({"Success": receipt["Success"], "saved": receipt.get("saved"),
        "receipt": str(receipt_path), "bytes": len(payload) if payload is not None else 0,
        "chunks": receipt["FetchedChunks"], "CleanupVerified": receipt["CleanupVerified"],
        "ProbeComplete": report.get("Complete") if report is not None else None,
        "Errors": receipt["Errors"]}, ensure_ascii=False))
    return 0 if receipt["Success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

```


## _local/flashlight-flicker/client_state.luau

SHA256: acf6bbec8df8cfc8e39e96e0c44f9a4963643d8eda308301232a0c0de9c66488

```text
local player = game:GetService("Players").LocalPlayer
local char = player and player.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
local gui = player and player:FindFirstChild("PlayerGui")
local host = gui and gui:FindFirstChild("QueueHostShade", true)
local items = {}
if gui then
    for _, item in ipairs(gui:GetDescendants()) do
        if item:IsA("GuiObject") and (item.Name == "CreateParty" or item.Name == "DecreasePlayers" or item.Name == "QueueHostShade"
            or item.Name:find("Loading") or item.Name:find("Cover")) then
            table.insert(items, {path=item:GetFullName(),visible=item.Visible,size={item.AbsoluteSize.X,item.AbsoluteSize.Y}})
        end
    end
end
local mount = workspace:FindFirstChild("FlashlightMount")
local flag = char and char:FindFirstChild("FlashlightOn")
return game:GetService("HttpService"):JSONEncode({userId=player and player.UserId, health=hum and hum.Health,
    inRound=player and player:GetAttribute("InRound"), roundActive=workspace:GetAttribute("RoundActive"),
    selectedLevel=workspace:GetAttribute("SelectedLevel"), hostVisible=host and host.Visible,
    torchFlag=flag and flag.Value, mount=mount and {mount.CFrame:GetComponents()}, gui=items,
    camera=workspace.CurrentCamera and {workspace.CurrentCamera.CFrame:GetComponents()}})

```


## _local/flashlight-flicker/compact_audit.luau

SHA256: c3dfe2f3669924d3acadd56c840a1ccedab5e09563217bb1c4422b1fb117c02a

```text
-- Read-only. Execute only while Flashlight flicker fix holds the coordinated lock.
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Unexpected place")
assert(game:GetService("RunService"):IsEdit(), "Fresh baseline requires Edit mode")
local H = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local paths = {
    {"StarterPlayer", "StarterPlayerScripts", "FlashlightController"},
    {"ServerScriptService", "FlashlightSync"},
    {"ReplicatedStorage", "FlashlightProfiles"},
    {"StarterPlayer", "StarterPlayerScripts", "SpectateController"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 4 Round Client"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 4 Lighting Controller"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 2 Lighting Controller"},
}
local function hash(source)
    local value = 5381
    for i = 1, #source do value = (value * 33 + string.byte(source, i)) % 4294967296 end
    return value
end
local result = {placeId = game.PlaceId, universeId = game.GameId, scripts = {}, properties = {}}
for _, segments in ipairs(paths) do
    local target = game
    for _, segment in ipairs(segments) do target = target and target:FindFirstChild(segment) end
    if target and target:IsA("LuaSourceContainer") then
        local source = target.Source
        local ok, editor = pcall(function() return SES:GetEditorSource(target) end)
        table.insert(result.scripts, {segments = segments, path = target:GetFullName(), className = target.ClassName,
             sourceBytes = #source, sourceDjb2 = hash(source),
            editorReadable = ok, editorMatches = ok and editor == source,
            editorDjb2 = ok and hash(editor) or nil,
            enabled = target:IsA("BaseScript") and target.Enabled or nil})
    else
        table.insert(result.scripts, {segments = segments, missing = true})
    end
end
for _, item in ipairs({{workspace, "StreamingEnabled"}, {workspace, "StreamingMinRadius"},
    {workspace, "StreamingTargetRadius"}, {game:GetService("Lighting"), "LightingStyle"},
    {game:GetService("Lighting"), "PrioritizeLightingQuality"}, {game:GetService("Lighting"), "Technology"}}) do
    local ok, value = pcall(function() return item[1][item[2]] end)
    result.properties[item[2]] = ok and tostring(value) or "unreadable"
end
return H:JSONEncode(result)

```


## _local/flashlight-flicker/drift_audit.luau

SHA256: 7178379a94766c504269642c57128f214906cbc0b2a893a9f636e874f497780b

```text
-- Read-only. Execute only while Flashlight flicker fix holds the coordinated lock.
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Unexpected place")
assert(game:GetService("RunService"):IsEdit(), "Fresh baseline requires Edit mode")
local H = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local paths = {
    {"StarterPlayer", "StarterPlayerScripts", "FlashlightController"},
    {"ServerScriptService", "FlashlightSync"},
    {"ReplicatedStorage", "FlashlightProfiles"},
    {"StarterPlayer", "StarterPlayerScripts", "SpectateController"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 4 Round Client"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 4 Lighting Controller"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 2 Lighting Controller"},
}
local function hash(source)
    local value = 5381
    for i = 1, #source do value = (value * 33 + string.byte(source, i)) % 4294967296 end
    return value
end
local result = {placeId = game.PlaceId, universeId = game.GameId, scripts = {}, properties = {}}
for _, segments in ipairs(paths) do
    local target = game
    for _, segment in ipairs(segments) do target = target and target:FindFirstChild(segment) end
    if target and target:IsA("LuaSourceContainer") then
        local source = target.Source
        local ok, editor = pcall(function() return SES:GetEditorSource(target) end)
        table.insert(result.scripts, {segments = segments, path = target:GetFullName(), className = target.ClassName,
            source = source, sourceBytes = #source, sourceDjb2 = hash(source),
            editorReadable = ok, editorMatches = ok and editor == source,
            editorDjb2 = ok and hash(editor) or nil,
            enabled = target:IsA("BaseScript") and target.Enabled or nil})
    else
        table.insert(result.scripts, {segments = segments, missing = true})
    end
end
for _, item in ipairs({{workspace, "StreamingEnabled"}, {workspace, "StreamingMinRadius"},
    {workspace, "StreamingTargetRadius"}, {game:GetService("Lighting"), "LightingStyle"},
    {game:GetService("Lighting"), "PrioritizeLightingQuality"}, {game:GetService("Lighting"), "Technology"}}) do
    local ok, value = pcall(function() return item[1][item[2]] end)
    result.properties[item[2]] = ok and tostring(value) or "unreadable"
end
return H:JSONEncode(result)

```


## _local/flashlight-flicker/glint.luau

SHA256: 2efeaaa628eca6c8c60dec596452672a80bbdde75bbccd898571ae41b5093973

```text
local p=game.Players.LocalPlayer
assert(workspace:GetAttribute("SelectedLevel")==4 and workspace:GetAttribute("RoundActive") and p:GetAttribute("InRound"))
assert(p.Character.FlashlightOn.Value,"Torch must be on")
local c=workspace.CurrentCamera
local oldType,oldCF=c.CameraType,c.CFrame
local rt=workspace["Level 4 Cinema Blender"]["Level 4 Round Runtime"]
local reel=assert(rt:FindFirstChild("L4FilmReel_3"))
local part=reel.PrimaryPart or reel:FindFirstChildWhichIsA("BasePart",true)
assert(part)
local seen,examples,rows={}, {}, {}
local emitterBefore=part:FindFirstChild("L4TorchGlint")~=nil
local start=time()
local ok,err=pcall(function()
 c.CameraType=Enum.CameraType.Scriptable
 c.CFrame=CFrame.lookAt(oldCF.Position,part.Position)
 assert((part.Position-c.CFrame.Position).Magnitude<55)
 start=time()
 while time()-start<3 do
  local count,bright=0,0
  for _,x in part:GetChildren() do if x:IsA("PointLight") then
   count+=1;bright=math.max(bright,x.Brightness)
   if not seen[x] then seen[x]=true;table.insert(examples,{range=x.Range,shadows=x.Shadows,brightness=x.Brightness})end
  end end
  table.insert(rows,{time()-start,count,bright,part:FindFirstChild("L4TorchGlint")~=nil})
  task.wait(.05)
 end
end)
c.CFrame,c.CameraType=oldCF,oldType
return game:GetService("HttpService"):JSONEncode({kind="Actual unmodified L4 glint observation; targeted camera runtime-only",ok=ok,error=not ok and tostring(err) or nil,reel=part:GetFullName(),eye={oldCF.Position.X,oldCF.Position.Y,oldCF.Position.Z},reelPosition={part.Position.X,part.Position.Y,part.Position.Z},emitterBefore=emitterBefore,uniqueLights=#examples,lights=examples,rows=rows})

```


## _local/flashlight-flicker/L1-far.luau

SHA256: 99102c0b85e90fa47a1302157e6d7cad754ebde16ddfa3c242434a05db9b7920

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-elevator-door-far-before",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 8, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = oldCameraCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config,
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-high-bloom-off.luau

SHA256: e61903dc3e78b076ee7c8dd69115a7b160ad410c2e5b74b1d42e152d0f692afd

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-high-quality-bloom-off",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 4, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = oldCameraCF
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}
for _,root in {game:GetService("Lighting"),camera} do for _,e in root:GetDescendants() do if e:IsA("BloomEffect") then savedBloom[e]=e.Enabled;e.Enabled=false end end end

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-high-bloom-on.luau

SHA256: a6cca42ab0a6116c05df343f1bf565b063d478583b1b02c9fde38873e0c7f319

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-high-quality-bloom-on",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 4, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = oldCameraCF
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-high-short-off.luau

SHA256: 9e27eb5eb810f0826bdfe4b71a3abf0d9e6243b47af0a39d1c8228f7f245407f

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-high-quality-bloom-off",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 1.5, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
assert(workspace:GetAttribute("RoundActive") and player.Character.FlashlightOn.Value,"Requires active round and torch")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = oldCameraCF
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}
for _,root in {game:GetService("Lighting"),camera} do for _,e in root:GetDescendants() do if e:IsA("BloomEffect") then savedBloom[e]=e.Enabled;e.Enabled=false end end end

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-high-short-on.luau

SHA256: 09091c55a564d2d9330543fbb0f5e165e642d999c6870caa4f45279bba4561a3

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-high-quality-bloom-on",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 1.5, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
assert(workspace:GetAttribute("RoundActive") and player.Character.FlashlightOn.Value,"Requires active round and torch")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = oldCameraCF
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-maze-far.luau

SHA256: d80474e826c8f9a5921498ec51791e4eed6912f1f976e6394b006bea90d10a66

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-maze-multiple-walls-far-before",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = oldCameraCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config,
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-near.luau

SHA256: b0e8082168dbd76dc9d69d69e91fd3948036c00351ca18114eb898ebf76f27b0

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-maze-wall-near-before",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = oldCameraCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-phone-far.luau

SHA256: bf88ede22b132f356a42257ba141d2a62c9a2d710761ac3bd2d1179314d5e804

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-iPhone17Pro-maze-wall-far-before",
	DeviceLabel = "iPhone 17 Pro landscape", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = oldCameraCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-phone-high-held-off.luau

SHA256: a7c2ed818d91f673af3a41d8ae8db4d1cda062b2215fd39f818f4dfe70050b53

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-iPhone17Pro-high-quality-bloom-off",
	DeviceLabel = "iPhone 17 Pro landscape", -- explicitly record the real emulator chosen in Studio
	Duration = 1.5, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
assert(workspace:GetAttribute("RoundActive") and player.Character.FlashlightOn.Value,"Requires active round and torch")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = oldCameraCF
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering, renderBloomRows = {}, {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}
for _,root in {game:GetService("Lighting"),camera} do for _,e in root:GetDescendants() do if e:IsA("BloomEffect") then savedBloom[e]=e.Enabled;e.Enabled=false end end end

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				for e in pairs(savedBloom) do if e.Parent then e.Enabled=false end end
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		for e in pairs(savedBloom) do if e.Parent then e.Enabled=false end end
		table.insert(renderBloomRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=renderBloomRows, QA_BloomLoopRows=extraRows, QA_BloomHeldEachRender=true, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-phone-high-off.luau

SHA256: c9f62338dc590bba4892ca9ec5d2dad38b76f079b22baf17ee1bddea9a86763f

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-iPhone17Pro-high-quality-bloom-off",
	DeviceLabel = "iPhone 17 Pro landscape", -- explicitly record the real emulator chosen in Studio
	Duration = 1.5, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
assert(workspace:GetAttribute("RoundActive") and player.Character.FlashlightOn.Value,"Requires active round and torch")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = oldCameraCF
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}
for _,root in {game:GetService("Lighting"),camera} do for _,e in root:GetDescendants() do if e:IsA("BloomEffect") then savedBloom[e]=e.Enabled;e.Enabled=false end end end

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-phone-high-on.luau

SHA256: 72b72fe608e6428718d291a14474e3f8d4eb067c5c5bd300e3950cfc171d136f

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-iPhone17Pro-high-quality-bloom-on",
	DeviceLabel = "iPhone 17 Pro landscape", -- explicitly record the real emulator chosen in Studio
	Duration = 1.5, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
assert(workspace:GetAttribute("RoundActive") and player.Character.FlashlightOn.Value,"Requires active round and torch")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = oldCameraCF
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L1-phone-near.luau

SHA256: 7be5e46f488b389df929fe0fd0ccf20126e5b4afa0db71dcd2ccc5a09371c3c4

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-iPhone17Pro-maze-wall-near-before",
	DeviceLabel = "iPhone 17 Pro landscape", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = oldCameraCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L4-diagnostic.luau

SHA256: 4608e118fab1a1e5ecc7eae32af9db0a9b6a7de7ace7418be9585fa6c40ce9be

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Intervention = "Forced camera at z100.45 facing existing door leaf; avatar remains far. Diagnostic only, not ordinary stance.",
	Label = "L4-PC-diagnostic-forced-clearance-contact",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = CFrame.lookAt(Vector3.new(28864,29.7,100.45), Vector3.new(28864,29.7,101))
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L4-door-far.luau

SHA256: 837636f1b79c458c0047b3951704716d92e8455a18be74b065a937af2f1ec1b1

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L4-PC-service-door-glass-far-before",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = CFrame.lookAt(oldCameraCF.Position, Vector3.new(28863.865,29.7,101))
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L4-far.luau

SHA256: 9861f8b605b89a1225e91825303eb994040a514441bafef391555dd0194d3988

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L4-PC-entry-door-glass-far-before",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = oldCameraCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L4-near.luau

SHA256: 0748be9d574b129860be86b963c4d5b4efd13519f1235b92601798fe09c7e821

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L4-PC-service-door-glass-near-before",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = CFrame.lookAt(oldCameraCF.Position, Vector3.new(28863.865,29.7,101))
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L4-PC-high-quality-bloom-off.luau

SHA256: 7bb2d0368a0e0929e3102579f224130b329e2f0813ee10af25e4b0256929055a

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L4-PC-high-quality-bloom-off",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = CFrame.lookAt(oldCameraCF.Position, Vector3.new(28863.865,29.7,101))
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Level 4 Client Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}
for _,root in {game:GetService("Lighting"),camera} do for _,e in root:GetDescendants() do if e:IsA("BloomEffect") then savedBloom[e]=e.Enabled;e.Enabled=false end end end

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L4-PC-high-quality-bloom-on.luau

SHA256: 986d4a145c6543a1bb470cfa7caaefd961a355f7f3cfa5733e31cdc9ca378a10

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L4-PC-high-quality-bloom-on",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = CFrame.lookAt(oldCameraCF.Position, Vector3.new(28863.865,29.7,101))
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local rendering = settings().Rendering
local originalRendering = {QualityLevel=rendering.QualityLevel, EditQualityLevel=rendering.EditQualityLevel, EnableFRM=rendering.EnableFRM}
local savedBloom, extraRows, qaRendering = {}, {}, {}
local observedBloom = game:GetService("Lighting"):FindFirstChild("Level 4 Client Bloom")
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
 rendering.QualityLevel=Enum.QualityLevel.Level21
 rendering.EditQualityLevel=Enum.QualityLevel.Level21
 rendering.EnableFRM=false
 qaRendering={QualityLevel=tostring(rendering.QualityLevel),EditQualityLevel=tostring(rendering.EditQualityLevel),EnableFRM=rendering.EnableFRM,OriginalQuality=tostring(originalRendering.QualityLevel),OriginalEdit=tostring(originalRendering.EditQualityLevel),OriginalFRM=originalRendering.EnableFRM}

	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		table.insert(extraRows,{time()-started,observedBloom and observedBloom.Enabled,observedBloom and observedBloom.Intensity})
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
for e,v in pairs(savedBloom) do if e.Parent then e.Enabled=v end end
rendering.QualityLevel,rendering.EditQualityLevel,rendering.EnableFRM=originalRendering.QualityLevel,originalRendering.EditQualityLevel,originalRendering.EnableFRM
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, QA_Rendering=qaRendering, QA_BloomRows=extraRows, QA_BloomSchema={"time","Enabled","Intensity"}, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L4-phone-far.luau

SHA256: cc7bbbd269dbe9eaf7c311f872d2d977db2489789b6d918f40ef856433318d44

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L4-iPhone17Pro-service-door-glass-far-before",
	DeviceLabel = "iPhone 17 Pro landscape", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = CFrame.lookAt(oldCameraCF.Position, Vector3.new(28863.865,29.7,101))
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/L4-phone-near.luau

SHA256: f96ff4ad9536e02ad0e2c4c143a465021422d706845a6775afd18f8b88403006

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L4-iPhone17Pro-service-door-glass-near-before",
	DeviceLabel = "iPhone 17 Pro landscape", -- explicitly record the real emulator chosen in Studio
	Duration = 6, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = true,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 1,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local sweepBaseCF = CFrame.lookAt(oldCameraCF.Position, Vector3.new(28863.865,29.7,101))
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = sweepBaseCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config, RoundActive=workspace:GetAttribute("RoundActive"),
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json(report)

```


## _local/flashlight-flicker/qa.py

SHA256: 996c6b8a7431c9b526699bc916a51982d328b13e8b1f4f5148a19dab5e6399fd

```text
"""Save bounded Studio execute_luau evidence; run only for this lock holder."""
import argparse
import json
from pathlib import Path
import sys
from datetime import datetime, timezone

ROOT = Path(r"G:/Roblox/MongoTV")
OUT = ROOT / "artifacts/flashlight-flicker-20261008/play"
SESSION = "Flashlight flicker fix"
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, studio_place_id

def check_lock():
    state = json.loads((ROOT / "_local/studio-lock.json").read_text(encoding="utf-8-sig"))
    if state.get("holder") != SESSION:
        raise RuntimeError("Studio lock is not held by this session")

def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["Edit", "Client", "Server"])
    p.add_argument("label")
    p.add_argument("code", type=Path)
    args = p.parse_args()
    assert args.label.replace("-", "").replace("_", "").isalnum()
    check_lock()
    code = args.code.read_text(encoding="utf-8")
    OUT.mkdir(parents=True, exist_ok=True)
    c = StudioMcpClient(find_mcp_batch())
    try:
        c.initialize()
        studios = json.loads(c.call("list_roblox_studios", {}))["studios"]
        matches = [s for s in studios if studio_place_id(s) == 131311258779917]
        assert len(matches) == 1, "Expected one exact place-id Studio"
        sid = matches[0]["id"]
        check_lock()
        response = c._request("tools/call", {"name": "execute_luau", "arguments": {
            "studio_id": sid, "datamodel_type": args.mode, "code": code}}, timeout=45)
    finally:
        c.close()
    target = OUT / (args.label + ".mcp.json")
    target.write_text(json.dumps({"utc": datetime.now(timezone.utc).isoformat(), "mode": args.mode,
        "studioId": sid, "codeFile": str(args.code), "response": response}, ensure_ascii=False, indent=2), encoding="utf-8")
    content = response.get("result", {}).get("content", [])
    texts = "\n".join(b.get("text", "") for b in content if b.get("type") == "text")
    (OUT / (args.label + ".txt")).write_text(texts, encoding="utf-8")
    summary = {"saved": str(target), "bytes": len(texts.encode("utf-8")), "isError": response.get("result", {}).get("isError", False)}
    try:
        parsed = json.loads(texts)
        summary["summary"] = {k: parsed[k] for k in ["Complete", "FrameCount", "MeasuredDuration", "Summary", "Errors"] if k in parsed}
    except (json.JSONDecodeError, TypeError):
        summary["preview"] = texts[:1600]
    print(json.dumps(summary, ensure_ascii=False))
    if summary["isError"]:
        raise SystemExit(1)

if __name__ == "__main__":
    main()

```


## _local/flashlight-flicker/remaining_audit.luau

SHA256: 1db79b0b1c49599749c1c5bf060f4c9618feeb54f60de914e49e62f607947313

```text
-- Read-only. Execute only while Flashlight flicker fix holds the coordinated lock.
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Unexpected place")
assert(game:GetService("RunService"):IsEdit(), "Fresh baseline requires Edit mode")
local H = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local paths = {
    {"StarterPlayer", "StarterPlayerScripts", "FlashlightController"},
    {"ServerScriptService", "FlashlightSync"},
    {"ReplicatedStorage", "FlashlightProfiles"},
    {"StarterPlayer", "StarterPlayerScripts", "SpectateController"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 4 Round Client"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 4 Lighting Controller"},
    {"StarterPlayer", "StarterPlayerScripts", "Level 2 Lighting Controller"},
}
local function hash(source)
    local value = 5381
    for i = 1, #source do value = (value * 33 + string.byte(source, i)) % 4294967296 end
    return value
end
local result = {placeId = game.PlaceId, universeId = game.GameId, scripts = {}, properties = {}}
for _, segments in ipairs({paths[5],paths[6],paths[7]}) do
    local target = game
    for _, segment in ipairs(segments) do target = target and target:FindFirstChild(segment) end
    if target and target:IsA("LuaSourceContainer") then
        local source = target.Source
        local ok, editor = pcall(function() return SES:GetEditorSource(target) end)
        table.insert(result.scripts, {segments = segments, path = target:GetFullName(), className = target.ClassName,
            source = source, sourceBytes = #source, sourceDjb2 = hash(source),
            editorReadable = ok, editorMatches = ok and editor == source,
            editorDjb2 = ok and hash(editor) or nil,
            enabled = target:IsA("BaseScript") and target.Enabled or nil})
    else
        table.insert(result.scripts, {segments = segments, missing = true})
    end
end
for _, item in ipairs({{workspace, "StreamingEnabled"}, {workspace, "StreamingMinRadius"},
    {workspace, "StreamingTargetRadius"}, {game:GetService("Lighting"), "LightingStyle"},
    {game:GetService("Lighting"), "PrioritizeLightingQuality"}, {game:GetService("Lighting"), "Technology"}}) do
    local ok, value = pcall(function() return item[1][item[2]] end)
    result.properties[item[2]] = ok and tostring(value) or "unreadable"
end
return H:JSONEncode(result)

```


## _local/flashlight-flicker/scene_targets.luau

SHA256: 4a76ba2c747da03119d23d6d7ad8250bba23dc4b223f208e18563b4a2d98f2d1

```text
local player = game:GetService("Players").LocalPlayer
local camera = assert(workspace.CurrentCamera)
local char = assert(player.Character)
local eye = camera.CFrame.Position
local level = workspace:GetAttribute("SelectedLevel")
local candidates = {}
local words = {"wall", "door", "shelf", "shelv", "glass", "reel", "chair", "table", "column", "fuse"}
for _, part in ipairs(workspace:GetDescendants()) do
    if part:IsA("BasePart") and not part:IsDescendantOf(char) then
        local distance = (part.Position-eye).Magnitude
        if distance < 70 and part.Transparency < 1 then
            local name = string.lower(part.Name)
            for _, word in ipairs(words) do
                if name:find(word, 1, true) then
                    table.insert(candidates, {path=part:GetFullName(),name=part.Name,distance=distance,
                        position={part.Position.X,part.Position.Y,part.Position.Z},size={part.Size.X,part.Size.Y,part.Size.Z},
                        cframe={part.CFrame:GetComponents()},material=tostring(part.Material),transparency=part.Transparency,
                        canQuery=part.CanQuery,canCollide=part.CanCollide,castShadow=part.CastShadow})
                    break
                end
            end
        end
    end
end
table.sort(candidates,function(a,b) return a.distance < b.distance end)
while #candidates > 35 do table.remove(candidates) end
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
ray.FilterDescendantsInstances = {char,camera}
local rays = {}
for _, direction in ipairs({camera.CFrame.LookVector,camera.CFrame.RightVector,-camera.CFrame.RightVector,-camera.CFrame.LookVector}) do
    local hit = workspace:Raycast(eye,direction*35,ray)
    table.insert(rays, hit and {path=hit.Instance:GetFullName(),distance=hit.Distance,
        position={hit.Position.X,hit.Position.Y,hit.Position.Z},normal={hit.Normal.X,hit.Normal.Y,hit.Normal.Z}} or {missing=true})
end
return game:GetService("HttpService"):JSONEncode({level=level,eye={eye.X,eye.Y,eye.Z},targets=candidates,rays=rays})

```


## _local/flashlight-flicker/select_round.luau

SHA256: 5cc1e170f99750dabc594e7c5bc94929dc5b53d043fbe6a0fd5fc911fc418da6

```text
-- Runtime-only stage: a real lobby zone; actual CreateParty UI launches the round.
local LEVEL = 1
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407)
local Players = game:GetService("Players")
local player = assert(Players:GetPlayers()[1], "No player")
local char = assert(player.Character, "No character")
local hum = assert(char:FindFirstChildOfClass("Humanoid"), "No humanoid")
assert(hum.Health > 0 and player:GetAttribute("InRound") ~= true, "Requires living lobby player")
local lobby = assert(workspace:FindFirstChild("LobbyReimaginedPreview"), "Current lobby missing")
local first = 101 + (LEVEL - 1) * 4
local zone
for _, item in ipairs(lobby:GetDescendants()) do
    if item:IsA("BasePart") and item:GetAttribute("R3QueueId") == first then zone = item; break end
end
assert(zone and zone:GetAttribute("LevelNumber") == LEVEL, "Queue zone mismatch")
local floor = assert(zone.Parent:FindFirstChild("ChamberFloor"), "Bay floor missing")
local position = zone.Position + Vector3.new(0, 3, 0)
char:PivotTo(CFrame.new(position) * zone.CFrame.Rotation)
workspace:SetAttribute("EntityPaused", true)
return game:GetService("HttpService"):JSONEncode({level=LEVEL, zone=zone:GetFullName(), position={position.X,position.Y,position.Z},
    userId=player.UserId, inRound=player:GetAttribute("InRound"), radius=zone:GetAttribute("QueueRadius")})

```


## _local/flashlight-flicker/select_round1_wait.luau

SHA256: f2e599729d70d160f1477126020662fbf1a30e481114d5f17fc5fec7da439e57

```text
-- Runtime-only stage: a real lobby zone; actual CreateParty UI launches the round.
local LEVEL = 1
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407)
local Players = game:GetService("Players")
local player = assert(Players:GetPlayers()[1], "No player")
local deadline = time()+8
while not player.Character and time()<deadline do task.wait(.1) end
local char = assert(player.Character, "No character after bounded wait")
local hum = assert(char:FindFirstChildOfClass("Humanoid"), "No humanoid")
assert(hum.Health > 0 and player:GetAttribute("InRound") ~= true, "Requires living lobby player")
local lobby = assert(workspace:FindFirstChild("LobbyReimaginedPreview"), "Current lobby missing")
local first = 101 + (LEVEL - 1) * 4
local zone
for _, item in ipairs(lobby:GetDescendants()) do
    if item:IsA("BasePart") and item:GetAttribute("R3QueueId") == first then zone = item; break end
end
assert(zone and zone:GetAttribute("LevelNumber") == LEVEL, "Queue zone mismatch")
local floor = assert(zone.Parent:FindFirstChild("ChamberFloor"), "Bay floor missing")
local position = zone.Position + Vector3.new(0, 3, 0)
char:PivotTo(CFrame.new(position) * zone.CFrame.Rotation)
workspace:SetAttribute("EntityPaused", true)
return game:GetService("HttpService"):JSONEncode({level=LEVEL, zone=zone:GetFullName(), position={position.X,position.Y,position.Z},
    userId=player.UserId, inRound=player:GetAttribute("InRound"), radius=zone:GetAttribute("QueueRadius")})

```


## _local/flashlight-flicker/select_round4.luau

SHA256: 9f4d00a9a91a46e8c55330fce1d9fa1091becf648c902dd54ac51df76b8f968f

```text
-- Runtime-only stage: a real lobby zone; actual CreateParty UI launches the round.
local LEVEL = 4
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407)
local Players = game:GetService("Players")
local player = assert(Players:GetPlayers()[1], "No player")
local deadline = time()+8
while not player.Character and time()<deadline do task.wait(.1) end
local char = assert(player.Character, "No character after bounded wait")
local hum = assert(char:FindFirstChildOfClass("Humanoid"), "No humanoid")
assert(hum.Health > 0 and player:GetAttribute("InRound") ~= true, "Requires living lobby player")
local lobby = assert(workspace:FindFirstChild("LobbyReimaginedPreview"), "Current lobby missing")
local first = 101 + (LEVEL - 1) * 4
local zone
for _, item in ipairs(lobby:GetDescendants()) do
    if item:IsA("BasePart") and item:GetAttribute("R3QueueId") == first then zone = item; break end
end
assert(zone and zone:GetAttribute("LevelNumber") == LEVEL, "Queue zone mismatch")
local floor = assert(zone.Parent:FindFirstChild("ChamberFloor"), "Bay floor missing")
local position = zone.Position + Vector3.new(0, 3, 0)
char:PivotTo(CFrame.new(position) * zone.CFrame.Rotation)
workspace:SetAttribute("EntityPaused", true)
return game:GetService("HttpService"):JSONEncode({level=LEVEL, zone=zone:GetFullName(), position={position.X,position.Y,position.Z},
    userId=player.UserId, inRound=player:GetAttribute("InRound"), radius=zone:GetAttribute("QueueRadius")})

```


## _local/flashlight-flicker/smoke.luau

SHA256: 8fd935ed1109e92cbe133ad1d1cc606592abce6384b796aec5872bb225e57cfd

```text
-- DRAFT: one bounded Client execute_luau call, not a persistent runtime script.
-- Run only for the granted Studio-lock holder. No services/scripts are created.
-- Sampling happens AFTER MongoFlashlight (Camera + 2). All callbacks are removed
-- before this call ends. Save the complete returned JSON string to disk.
-- Observer mode is default. The optional Scriptable sweep restores the camera.
local config = {
	Label = "L1-PC-own-wall-near-before",
	DeviceLabel = "PC", -- explicitly record the real emulator chosen in Studio
	Duration = 0.5, -- must remain <= 10 (MCP calls must stay below 18 seconds)
	MaxFrames = 1800, -- bounded at 300 fps; capped captures are marked incomplete
	Sweep = false,
	SweepYawDegrees = 60, -- center->left->center->right->center; one cycle
	SweepPitchDegrees = 0,
	ClipJumpStuds = 0.15,
	StationaryEyeStepStuds = 0.02,
	StationaryRawStepStuds = 0.05,
	MaxMates = 0,
}
assert(config.Duration > 0 and config.Duration <= 10, "duration outside bounded range")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = assert(Players.LocalPlayer, "Client datamodel required")
local camera = assert(workspace.CurrentCamera, "No current camera")
-- A runtime clone comes from the actual Play session, not the offline mirror.
local liveController = assert(player:FindFirstChild("PlayerScripts")
	and player.PlayerScripts:FindFirstChild("FlashlightController"), "Live controller not found")
assert(liveController:IsA("LocalScript"), "Live controller has unexpected class")
local sourceOk, liveSource = pcall(function() return liveController.Source end)
assert(sourceOk, "Live Source inaccessible; use a fresh scoped source audit before adapting probe")
assert(tonumber(liveSource:match("local%s+HAND_SIDE%s*=%s*([%-%d%.]+)")) == .25,
	"Fresh live HAND_SIDE differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_DOWN%s*=%s*([%-%d%.]+)")) == -.25,
	"Fresh live HAND_DOWN differs; reconcile probe first")
assert(tonumber(liveSource:match("local%s+HAND_FORWARD%s*=%s*([%-%d%.]+)")) == .3,
	"Fresh live HAND_FORWARD differs; reconcile probe first")
assert(liveSource:find("mount.CFrame = aimCF.Rotation + handPos", 1, true)
	and liveSource:find("math.max((hit.Position - eye).Magnitude - 0.3, 0)", 1, true),
	"Fresh live origin assignment/clipping differs; reconcile probe first")
local oldCameraType, oldCameraCF = camera.CameraType, camera.CFrame
local samplerName, driverName = "MongoFlashlightFlickerProbe", "MongoFlashlightFlickerSweep"
local rows, lights, lightIds, originIds, origins, hitIds, hits = {}, {}, {}, {}, {}, {}, {}
local summaries = {ClipJumps = 0, AllOriginResidualJumps = 0, ExcludedOriginResidualJumps = 0,
	EnabledEdges = 0, PropertyEdges = 0, MissingMountFrames = 0,
	MaxClipDelta = 0, MaxResidualDelta = 0, MaxCameraDelta = 0, MaxActualDelta = 0, MaxRawDelta = 0,
	MaxReconstructionError = 0, HitSwitches = 0}
local errors, previous, frames, started = {}, nil, 0, time()
local connections, addedCount, removedCount = {}, 0, 0
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
local matePlayers = {}
for _, mate in ipairs(Players:GetPlayers()) do
	if mate ~= player and #matePlayers < config.MaxMates then
		table.insert(matePlayers, mate)
	end
end
local function vector(v) return {v.X, v.Y, v.Z} end
local function cf(value) return {value:GetComponents()} end
local function safeProperty(item, key)
	local ok, value = pcall(function() return item[key] end)
	return ok and tostring(value) or "restricted"
end
local function identifyHit(item)
	if not item then return 0 end
	if hitIds[item] then return hitIds[item] end
	local id = #hits + 1
	hitIds[item] = id
	hits[id] = {Path = item:GetFullName(), Class = item.ClassName,
		Material = safeProperty(item, "Material"), Transparency = safeProperty(item, "Transparency"),
		CanCollide = safeProperty(item, "CanCollide"), CanQuery = safeProperty(item, "CanQuery"),
		CastShadow = safeProperty(item, "CastShadow"), RenderFidelity = safeProperty(item, "RenderFidelity"),
		AncestryEdges = 0, DetachedEdges = 0}
	table.insert(connections, item.AncestryChanged:Connect(function(_, parent)
		hits[id].AncestryEdges += 1
		if not parent then hits[id].DetachedEdges += 1 end
	end))
	return id
end
local function originId(item, role)
	if originIds[item] then return originIds[item] end
	local id = #origins + 1
	originIds[item] = id
	origins[id] = {Role = role, Path = item:GetFullName(), Class = item.ClassName}
	return id
end
local function sampleChildren(parent, role, lightRows, originRows)
	if not parent then return end
	local oid = originId(parent, role)
	table.insert(originRows, {oid, cf(parent.CFrame)})
	for _, item in ipairs(parent:GetChildren()) do
		if item:IsA("Light") then
			local lid = lightIds[item]
			if not lid then
				lid = #lights + 1
				lightIds[item] = lid
				lights[lid] = {OriginId = oid, Path = item:GetFullName(), Name = item.Name,
					Class = item.ClassName, Face = safeProperty(item, "Face"), Role = role,
					FirstFrame = frames,
					InitialBrightness = item.Brightness, InitialRange = item.Range,
					InitialAngle = item:IsA("SpotLight") and item.Angle or false,
					InitialShadows = item.Shadows}
			end
			table.insert(lightRows, {lid, item.Enabled, item.Brightness, item.Range,
				item:IsA("SpotLight") and item.Angle or false, item.Shadows})
		end
	end
end
local function snapshotState()
	local char = player.Character
	local flag = char and char:FindFirstChild("FlashlightOn")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return {player:GetAttribute("SpectateBattery") or false,
		player:GetAttribute("DevUnlimited") == true, flag and flag.Value == true or false,
		char and char:GetAttribute("FlashlightFocused") == true or false,
		player:GetAttribute("InRound") == true, player:GetAttribute("Level2NewMapPreview") == true,
		player:GetAttribute("Spectating") == true, workspace:GetAttribute("SelectedLevel") or false,
		workspace:GetAttribute("Level3BlackoutActive") == true, hum and hum.Health or 0}
end
local function sample(dt)
	frames += 1
	local t = time() - started
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then error("CurrentCamera replaced during capture") end
	local mount = workspace:FindFirstChild("FlashlightMount")
	if not mount then summaries.MissingMountFrames += 1 end
	local lightRows, originRows, shaftRows = {}, {}, {}
	sampleChildren(mount, "own", lightRows, originRows)
	sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. player.UserId),
		"self-replicated", lightRows, originRows)
	for _, mate in ipairs(matePlayers) do
		local char = mate.Character
		local head = char and char:FindFirstChild("Head")
		sampleChildren(head, "mate-head-" .. mate.UserId, lightRows, originRows)
		sampleChildren(workspace:FindFirstChild("ReplicatedFlashlight_" .. mate.UserId),
			"mate-replicated-" .. mate.UserId, lightRows, originRows)
		local a0 = head and head:FindFirstChild("MateBeamA0")
		local a1 = char and workspace.Terrain:FindFirstChild("MateBeamA1_" .. char.Name)
		local shaft = a1 and a1:FindFirstChild("MateBeamShaft")
		if a0 and a1 then
			table.insert(shaftRows, {mate.UserId, vector(a0.WorldPosition), vector(a1.WorldPosition),
				shaft and shaft.Enabled == true or false})
		end
	end
	local eye, raw, actual, clip, hitId, reconstructionError = currentCamera.CFrame.Position, nil, nil, 0, 0, 0
	if mount then
		-- Exact reconstruction of current source constants/formula, not a proposed fix.
		-- Fresh live-source audit must confirm 0.25/-0.25/0.3 before running.
		local right = mount.CFrame.RightVector
		local flat = Vector3.new(right.X, 0, right.Z)
		flat = flat.Magnitude > .001 and flat.Unit or Vector3.new(1, 0, 0)
		raw = eye + flat * .25 + Vector3.new(0, -.25, 0) + mount.CFrame.LookVector * .3
		actual = mount.Position
		local filter = {currentCamera}
		if player.Character then table.insert(filter, player.Character) end
		ray.FilterDescendantsInstances = filter
		local toHand = raw - eye
		local hit = workspace:Raycast(eye, toHand, ray)
		hitId = identifyHit(hit and hit.Instance)
		local expected = hit and eye + toHand.Unit * math.max((hit.Position-eye).Magnitude-.3, 0) or raw
		reconstructionError = (actual - expected).Magnitude
		clip = (raw - actual).Magnitude
		summaries.MaxReconstructionError = math.max(summaries.MaxReconstructionError, reconstructionError)
	end
	local state = snapshotState()
	local metrics = {0, 0, 0, 0, clip, reconstructionError, hitId, 0}
	if previous then
		metrics[1] = (eye - previous.eye).Magnitude
		if raw and previous.raw then metrics[2] = (raw - previous.raw).Magnitude end
		if actual and previous.actual then metrics[3] = (actual - previous.actual).Magnitude end
		metrics[8] = math.abs(clip - previous.clip)
		if actual and raw and previous.actual and previous.raw then
			metrics[4] = ((actual-raw) - (previous.actual-previous.raw)).Magnitude
		end
		summaries.MaxCameraDelta = math.max(summaries.MaxCameraDelta, metrics[1])
		summaries.MaxRawDelta = math.max(summaries.MaxRawDelta, metrics[2])
		summaries.MaxActualDelta = math.max(summaries.MaxActualDelta, metrics[3])
		summaries.MaxClipDelta = math.max(summaries.MaxClipDelta, metrics[8])
		summaries.MaxResidualDelta = math.max(summaries.MaxResidualDelta, metrics[4])
		if raw and previous.raw and metrics[4] >= config.ClipJumpStuds then
			summaries.AllOriginResidualJumps += 1
			local stable = mount == previous.mount and state[4] == previous.state[4]
				and state[8] == previous.state[8] and state[9] == previous.state[9]
				and state[3] == true and previous.state[3] == true
				and metrics[1] <= config.StationaryEyeStepStuds
				and metrics[2] <= config.StationaryRawStepStuds
			if stable then summaries.ClipJumps += 1 else summaries.ExcludedOriginResidualJumps += 1 end
		end
		if hitId ~= previous.hitId then summaries.HitSwitches += 1 end
		for _, values in ipairs(lightRows) do
			local before = previous.lights[values[1]]
			if before then
				if before[2] ~= values[2] then summaries.EnabledEdges += 1 end
				for i = 3, 6 do
					if before[i] ~= values[i] then summaries.PropertyEdges += 1; break end
				end
			end
		end
	end
	local byId = {}
	for _, values in ipairs(lightRows) do byId[values[1]] = values end
	previous = {eye=eye, raw=raw, actual=actual, clip=clip, hitId=hitId, lights=byId, mount=mount, state=state}
	table.insert(rows, {t, dt, cf(currentCamera.CFrame), mount and cf(mount.CFrame) or false,
		raw and vector(raw) or false, metrics, state, lightRows, originRows, shaftRows,
		{addedCount, removedCount}})
end
local function nearbyShadowLights()
	local entries, descendants = {}, workspace:GetDescendants()
	for _, item in ipairs(descendants) do
		if item:IsA("Light") and item.Shadows then
			local parent, position = item.Parent, nil
			if parent and parent:IsA("BasePart") then position = parent.Position end
			if parent and parent:IsA("Attachment") then position = parent.WorldPosition end
			if position and (position-camera.CFrame.Position).Magnitude <= 120 then
				table.insert(entries, {Path=item:GetFullName(), Class=item.ClassName,
					Position=vector(position), Enabled=item.Enabled, Range=item.Range,
					Brightness=item.Brightness, Angle=item:IsA("SpotLight") and item.Angle or false})
			end
		end
	end
	return {DescendantCount=#descendants, Lights=entries}
end
local function json(value)
	local kind = type(value)
	if kind == "boolean" then return value and "true" or "false" end
	if kind == "number" then
		if value ~= value or math.abs(value) == math.huge then return "null" end
		return tostring(math.round(value * 100000) / 100000)
	end
	if kind == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
			if c == '"' then return '\\"' end
			if c == '\\' then return '\\\\' end
			return string.format('\\u%04x', string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		local pieces = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do table.insert(pieces, json(item)) end
			return '[' .. table.concat(pieces, ',') .. ']'
		end
		for key, item in pairs(value) do table.insert(pieces, json(tostring(key)) .. ':' .. json(item)) end
		return '{' .. table.concat(pieces, ',') .. '}'
	end
	return "null"
end
local preScene = nearbyShadowLights()
local ok, failure = pcall(function()
	table.insert(connections, workspace.DescendantAdded:Connect(function() addedCount += 1 end))
	table.insert(connections, workspace.DescendantRemoving:Connect(function() removedCount += 1 end))
	started = time() -- exclude setup scans from the measurement window
	if config.Sweep then
		local state = snapshotState()
		assert(state[10] > 0 and state[7] == false, "Sweep requires living, non-spectating player")
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(driverName, Enum.RenderPriority.Camera.Value + 1, function()
			if #errors > 0 then return end
			local driven, driveError = pcall(function()
				local elapsed = time() - started
				local yaw = math.sin(elapsed / config.Duration * math.pi * 2) * math.rad(config.SweepYawDegrees / 2)
				camera.CFrame = oldCameraCF * CFrame.Angles(math.rad(config.SweepPitchDegrees), yaw, 0)
			end)
			if not driven then table.insert(errors, tostring(driveError)) end
		end)
	end
	RunService:BindToRenderStep(samplerName, Enum.RenderPriority.Camera.Value + 4, function(dt)
		if #errors > 0 or frames >= config.MaxFrames then return end
		local sampled, sampleError = pcall(sample, dt)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	while time() - started < config.Duration and frames < config.MaxFrames and #errors == 0 do
		task.wait(.05)
	end
end)
-- Finalizer executes even if the setup/wait/sampler failed. No connections survive.
RunService:UnbindFromRenderStep(samplerName)
RunService:UnbindFromRenderStep(driverName)
for _, connection in ipairs(connections) do connection:Disconnect() end
if config.Sweep and workspace.CurrentCamera == camera then
	camera.CFrame, camera.CameraType = oldCameraCF, oldCameraType
end
if not ok then table.insert(errors, tostring(failure)) end
local measuredDuration = rows[#rows] and rows[#rows][1] or 0
local report = {
	Kind = "frame_property_probe_only_not_visual_flicker_verdict", Config = config,
	Complete = #errors == 0 and frames > 0 and frames < config.MaxFrames
		and measuredDuration >= config.Duration*.95 and summaries.MissingMountFrames == 0,
	Errors = errors, FrameCount = frames, Elapsed = time()-started, MeasuredDuration=measuredDuration, Summary = summaries,
	TouchEnabled = UIS.TouchEnabled, ForceTouchUI = workspace:GetAttribute("ForceTouchUI") == true,
	Viewport = {camera.ViewportSize.X, camera.ViewportSize.Y}, StreamingEnabled = safeProperty(workspace, "StreamingEnabled"),
	LiveController = {Path=liveController:GetFullName(), Class=liveController.ClassName, SourceBytes=#liveSource},
	NearbyShadowLightsBefore=preScene, NearbyShadowLightsAfter=nearbyShadowLights(),
	SceneMutationCounts={Added=addedCount, Removed=removedCount},
	RowSchema = {"time", "dt", "cameraCFrame12", "ownCFrame12", "rawHand3", "metrics", "state", "lights", "origins", "mateShafts", "sceneMutationCounts"},
	MetricSchema = {"cameraDelta", "rawDelta", "actualDelta", "originResidualDelta", "clipDistance", "reconstructionError", "hitId", "clipMagnitudeDelta"},
	StateSchema = {"SpectateBatteryProxy", "DevUnlimited", "FlashlightOn", "Focused", "InRound", "L2Preview", "Spectating", "SelectedLevel", "L3Blackout", "Health"},
	LightSchema = {"lightId", "Enabled", "Brightness", "Range", "Angle_or_false", "Shadows"},
	OriginSchema = {"originId", "cFrame12"}, ShaftSchema = {"userId", "start3", "end3", "Enabled"},
	Lights = lights, Origins = origins, Hits = hits, Rows = rows,
}
return json({Kind="smoke", Complete=report.Complete, FrameCount=report.FrameCount, MeasuredDuration=report.MeasuredDuration, Errors=report.Errors, Summary=report.Summary, LastFrame=report.Rows[#report.Rows]})

```


## _local/flashlight-flicker/take_lock.py

SHA256: 71ff6c4cd7903cba99f9022bf4d754eeb14cab140278c27b8f47745e0f961009

```text
"""Take only the free, explicitly granted slot; preserve the rest of the queue."""
from pathlib import Path
from datetime import datetime, timedelta, timezone
import json

path = Path(r"G:/Roblox/MongoTV/_local/studio-lock.json")
name = "Flashlight flicker fix"
with path.open("r+b") as f:
    baseline = f.read()
    state = json.loads(baseline.decode("utf-8-sig"))
    if state.get("holder") is not None or state.get("grantedTo") != name:
        print(json.dumps({"taken":False,"holder":state.get("holder"),"grantedTo":state.get("grantedTo")}))
        raise SystemExit(2)
    now = datetime.now(timezone.utc)
    state.update(holder=name,since=now.isoformat(),releaseEta=(now+timedelta(minutes=25)).isoformat(),
        grantedTo=None,note="Owner-authorized modest Bloom tuning across lobby/all levels: fresh Source/editor/native-property audit, scoped CAS and Play comparison. Preserve HUD/L2 WIP. No claimed flicker root cause, commit, push or publish. Return Edit and release promptly.")
    f.seek(0)
    assert f.read() == baseline, "Lock state changed while preparing acquisition"
    f.seek(0)
    f.write((json.dumps(state,indent=2,ensure_ascii=False)+"\n").encode("utf-8"))
    f.truncate()
print(json.dumps({"taken":True,"since":state["since"],"releaseEta":state["releaseEta"]}))

```


## _local/flashlight-flicker/transport-smoke.luau

SHA256: 7472b8efa0e6723400dbda3fc3e7f3b0ca3b05d428d047db3b3e45afc81901e3

```text
-- Transport smoke only; not flashlight/render quality evidence.
local H = game:GetService("HttpService")
local json = function(value) return H:JSONEncode(value) end
local R = game:GetService("RunService")
local rows, errors, frames = {}, {}, 0
local started = time()
local connection
local ok, failure = pcall(function()
	connection = R.RenderStepped:Connect(function(dt)
		local sampled, sampleError = pcall(function()
			frames += 1
			table.insert(rows, {time() - started, dt})
		end)
		if not sampled then table.insert(errors, tostring(sampleError)) end
	end)
	task.wait(.3)
end)
if connection then connection:Disconnect() end
if not ok then table.insert(errors, tostring(failure)) end
local report = {Kind = "transport_capability_smoke_only", Complete = frames > 0 and #errors == 0,
	FrameCount = frames, Errors = errors, Rows = rows, Summary = {Disconnected = connection == nil or not connection.Connected},
	-- >20 kB exercises a multibyte boundary plus more than one attribute.
	Utf8BoundaryPayload = string.rep(utf8.char(0xE6, 0x6F22, 0x1F642), 2600)}
return json(report)

```
