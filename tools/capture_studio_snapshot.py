"""Capture/verify a complete read-only Studio snapshot; apply it only to the repo.

capture writes a frozen snapshot into --output after two complete native reads
agree. verify compares another complete native read. apply never connects to
Studio: it checks the recorded local baseline, saves before-mirror.zip, and
reconciles only the captured mirrors plus tracked/listed retired mirrors.
Neither this tool nor its generated Luau changes Studio or HttpEnabled. A code
snapshot is not a native place backup or a gameplay/performance test.
"""
from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import zipfile

from push_repo_to_studio import djb2, luau_string
from studio_source_contract import canonical_bytes, normalize, refresh_trailing_newline_metadata
from sync_from_studio import (
    EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID, MIRRORED_SERVICES, RELEASE_STUDIO_NAME,
    SCRIPT_CLASSES, StudioMcpClient, StudioMcpError, find_mcp_batch,
    require_edit_state, select_studio,
)

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "studio-sync-manifest.json"
MIRROR_NAME = re.compile(r"\.(?:Script|LocalScript|ModuleScript)\.lua$|\.RemoteEvent\.txt$", re.I)
INVALID_NAME = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
RESERVED = {"con", "prn", "aux", "nul", "conin$", "conout$"} | {
    f"{prefix}{digit}" for prefix in ("com", "lpt") for digit in "123456789¹²³"
}
BASE_ROOTS = set(MIRRORED_SERVICES) | {"StarterGui", "Lighting", "SoundService"}
CHUNK_BYTES = 24000
INVENTORY_CHUNK_BYTES = 40000  # Hex response stays below the MCP's ~100 kB cap.

COMMON = r'''
-- complete-studio-snapshot-v1; read-only
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local CS=game:GetService("CollectionService")
local RS=game:GetService("RunService")
assert(not RS:IsRunning(),"Snapshot requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
local function sha(text)
 local b=ENC:ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(b)-1 do out[#out+1]=string.format("%02x",buffer.readu8(b,i)) end
 return table.concat(out)
end
local function fingerprint(text)
 local h=5381 for i=1,#text do h=(h*33+string.byte(text,i))%4294967296 end return h
end
local function resolve(segments)
 local cur=game
 for _,name in ipairs(segments) do
  local found
  for _,child in ipairs(cur:GetChildren()) do
   if child.Name==name then assert(not found,"Ambiguous native path: "..name);found=child end
  end
  cur=assert(found,"Missing native path: "..name)
 end
 return cur
end
local function encoded(v)
 local t=typeof(v)
 if t=="string" or t=="boolean" then return v end
 if t=="number" then assert(v==v and math.abs(v)<math.huge,"Nonfinite attribute");return v end
 local a
 if t=="Vector2" then a={v.X,v.Y}
 elseif t=="Vector3" then a={v.X,v.Y,v.Z}
 elseif t=="Color3" then a={v.R,v.G,v.B}
 elseif t=="CFrame" then a={v:GetComponents()}
 elseif t=="BrickColor" then a=v.Number
 elseif t=="UDim" then a={v.Scale,v.Offset}
 elseif t=="UDim2" then a={v.X.Scale,v.X.Offset,v.Y.Scale,v.Y.Offset}
 elseif t=="NumberRange" then a={v.Min,v.Max}
 elseif t=="Rect" then a={v.Min.X,v.Min.Y,v.Max.X,v.Max.Y}
 elseif t=="EnumItem" then a=tostring(v)
 elseif t=="Font" then a={v.Family,tostring(v.Weight),tostring(v.Style)}
 elseif t=="NumberSequence" then
  a={} for _,k in ipairs(v.Keypoints) do a[#a+1]={k.Time,k.Value,k.Envelope} end
 elseif t=="ColorSequence" then
  a={} for _,k in ipairs(v.Keypoints) do a[#a+1]={k.Time,k.Value.R,k.Value.G,k.Value.B} end
 else error("Unsupported native attribute type: "..t) end
 return {robloxType=t,value=a}
end
local function canonical(v)
 if type(v)~="table" then return H:JSONEncode(v) end
 if #v>0 then local out={} for i=1,#v do out[i]=canonical(v[i]) end return "["..table.concat(out,",").."]" end
 local keys,out={},{} for k in pairs(v) do keys[#keys+1]=k end table.sort(keys)
 for i,k in ipairs(keys) do out[i]=H:JSONEncode(k)..":"..canonical(v[k]) end
 return "{"..table.concat(out,",").."}"
end
local function metadata(inst)
 local p={Archivable=inst.Archivable}
 if inst:IsA("LuaSourceContainer") then
  p.LinkedSource=inst.LinkedSource
  local ok,id=pcall(function() return inst.SourceAssetId end)
  if ok then p.SourceAssetId=id end
  if inst:IsA("BaseScript") then
   p.Enabled=inst.Enabled;p.Disabled=inst.Disabled;p.RunContext=tostring(inst.RunContext)
   assert(p.Enabled~=p.Disabled,"Invalid Enabled aliases")
  end
 end
 local a={} for k,v in pairs(inst:GetAttributes()) do a[k]=encoded(v) end
 local tags=CS:GetTags(inst);table.sort(tags)
 return {properties=p,attributes=a,tags=tags}
end
local function record(inst)
 local parent=assert(inst.Parent,"Detached native instance")
 local segments={inst.Name};local cur=parent
 while cur and cur~=game do table.insert(segments,1,cur.Name);cur=cur.Parent end
 assert(cur==game and resolve(segments)==inst,"Native identity/path conflict")
 local out=metadata(inst)
 local before=canonical(out)
 out.segments=segments;out.path=inst:GetFullName();out.className=inst.ClassName
 out.instanceId=inst:GetDebugId(16);out.parentId=parent:GetDebugId(16)
 if inst:IsA("LuaSourceContainer") then
  local source=inst.Source;local editor=SES:GetEditorSource(inst)
  assert(type(source)=="string" and type(editor)=="string" and source==editor,"Native Source/editor conflict: "..out.path)
  local text=source:gsub("\r\n","\n")
  out.rawSourceSHA256=sha(source);out.rawEditorSHA256=sha(editor)
  out.sourceSHA256=sha(text);out.sourceBytes=#source;out.canonicalBytes=#text
  out.sourceHash=fingerprint(source);out.sourceEditorMatches=true
  assert(inst.Source==source and SES:GetEditorSource(inst)==editor,"Source/editor changed during read")
 end
 assert(before==canonical(metadata(inst)),"Metadata changed during read")
 assert(inst.Parent==parent and inst:GetDebugId(16)==out.instanceId and inst:GetFullName()==out.path,"Identity changed during read")
 assert(not RS:IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407,"Mode/place changed")
 return out
end
local function hexChunk(text,first,last)
 return (string.gsub(string.sub(text,first,last),".",function(c) return string.format("%02x",string.byte(c)) end))
end
'''

ENUMERATE_BODY = COMMON + r'''
-- snapshot-inventory
local out={placeId=game.PlaceId,universeId=game.GameId,sources={},remotes={}}
for i,inst in ipairs(game:GetDescendants()) do
 if inst:IsA("LuaSourceContainer") then out.sources[#out.sources+1]=record(inst)
 elseif inst:IsA("RemoteEvent") then out.remotes[#out.remotes+1]=record(inst) end
 if i%1000==0 then task.wait() end
end
local function less(a,b) return canonical(a.segments)<canonical(b.segments) end
table.sort(out.sources,less);table.sort(out.remotes,less)
assert(not RS:IsRunning(),"Mode changed during enumeration")
local catalog=canonical(out)
local header={catalogBytes=#catalog,catalogSHA256=sha(catalog),catalogHash=fingerprint(catalog),
 sourceCount=#out.sources,remoteCount=#out.remotes}
'''


def inventory_page_code(first=1, header=None):
    guards = ""
    if header is not None:
        guards = (f"assert(header.catalogBytes=={header['catalogBytes']} and header.catalogSHA256=={luau_string(header['catalogSHA256'])} "
                  f"and header.catalogHash=={header['catalogHash']} and header.sourceCount=={header['sourceCount']} "
                  f"and header.remoteCount=={header['remoteCount']},\"Complete native catalog changed between pages\")\n")
    return ENUMERATE_BODY + guards + f'''
-- snapshot-inventory-page first={first}
header.first={first};header.hex=hexChunk(catalog,{first},{first + INVENTORY_CHUNK_BYTES - 1})
return H:JSONEncode(header)
'''


ENUMERATE = inventory_page_code()


def demand(ok, message):
    if not ok:
        raise StudioMcpError(message)


def checked_segment(value):
    demand(isinstance(value, str) and value and value not in {".", ".."}, "Unsafe path component")
    demand(not INVALID_NAME.search(value) and not value.endswith((" ", ".")), f"Unsafe Windows name: {value!r}")
    demand(value.split(".", 1)[0].casefold() not in RESERVED, f"Reserved Windows name: {value!r}")
    return value


def safe_path(root, relative):
    demand(isinstance(relative, str) and relative, "Invalid relative file path")
    parts = PurePosixPath(relative).parts
    demand(parts and PurePosixPath(relative).as_posix() == relative, f"Noncanonical path: {relative!r}")
    for part in parts:
        checked_segment(part)
    root = root.resolve()
    path = root.joinpath(*parts)
    demand(path.resolve().is_relative_to(root), f"Path escapes project root: {relative}")
    current = path
    while current != root:
        demand(not current.is_symlink(), f"Symlink in managed path: {relative}")
        if current.exists():
            demand(not (getattr(current.lstat(), "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0)), f"Reparse point in managed path: {relative}")
        current = current.parent
    demand(not path.exists() or path.is_file(), f"Managed path is not a file: {relative}")
    return path


def relative(item):
    segments, klass = item.get("segments"), item.get("className")
    demand(isinstance(segments, list) and len(segments) >= 2, "Missing native segments")
    demand(klass in SCRIPT_CLASSES | {"RemoteEvent"}, "Unexpected native class")
    for segment in segments:
        checked_segment(segment)
    demand(segments[0].casefold() not in {"tools", ".git", "_local", "artifacts", "docs"}, "Native root conflicts with repository content")
    suffix = ".txt" if klass == "RemoteEvent" else ".lua"
    return PurePosixPath(*segments[:-1], segments[-1] + "." + klass + suffix).as_posix()


def json_safe(value):
    if isinstance(value, dict):
        return all(isinstance(k, str) and json_safe(v) for k, v in value.items())
    if isinstance(value, list):
        return all(json_safe(v) for v in value)
    return type(value) in (str, bool, int) or (type(value) is float and math.isfinite(value))


def validate_inventory(value):
    demand(isinstance(value, dict), "Invalid native inventory")
    demand(value.get("placeId") == EXPECTED_PLACE_ID and value.get("universeId") == EXPECTED_UNIVERSE_ID, "Wrong native place/universe")
    aliases, paths, ids, dotted = {}, set(), set(), set()
    for group in ("sources", "remotes"):
        demand(isinstance(value.get(group), list), f"Invalid native {group}")
        for item in value[group]:
            demand(isinstance(item, dict), "Invalid native row")
            rel = relative(item)
            klass = item["className"]
            demand((klass == "RemoteEvent") == (group == "remotes"), "Wrong native inventory group")
            demand(item.get("path") == ".".join(item["segments"]), "Native path/segments conflict")
            demand(rel.casefold() not in paths and item["path"] not in dotted, "Colliding native mirror/path")
            paths.add(rel.casefold());dotted.add(item["path"])
            for key in ("instanceId", "parentId"):
                demand(isinstance(item.get(key), str) and item[key], "Missing native identity")
            demand(item["instanceId"] not in ids, "Duplicate native identity");ids.add(item["instanceId"])
            for i in range(1, len(PurePosixPath(rel).parts) + 1):
                prefix = PurePosixPath(*PurePosixPath(rel).parts[:i]).as_posix()
                demand(aliases.get(prefix.casefold(), prefix) == prefix, "Case-colliding native path components")
                aliases[prefix.casefold()] = prefix
            props = item.get("properties")
            wanted = {"Archivable"} if klass == "RemoteEvent" else {"Archivable", "LinkedSource"}
            if klass in {"Script", "LocalScript"}: wanted |= {"Enabled", "Disabled", "RunContext"}
            demand(isinstance(props, dict) and wanted <= props.keys() and type(props["Archivable"]) is bool, "Missing native properties")
            demand(set(props) <= wanted | {"SourceAssetId"}, "Unknown native properties")
            if klass != "RemoteEvent": demand(isinstance(props["LinkedSource"], str), "Invalid LinkedSource")
            if "SourceAssetId" in props: demand(type(props["SourceAssetId"]) is int, "Invalid SourceAssetId")
            if klass in {"Script", "LocalScript"}:
                demand(type(props["Enabled"]) is bool and type(props["Disabled"]) is bool and props["Enabled"] != props["Disabled"], "Invalid Enabled aliases")
                demand(isinstance(props["RunContext"], str) and props["RunContext"].startswith("Enum.RunContext."), "Invalid RunContext")
            if item.get("attributes") == []: item["attributes"] = {}
            demand(isinstance(item.get("attributes"), dict) and json_safe(item["attributes"]), "Invalid native attributes")
            tags = item.get("tags")
            # Native canonical serialization cannot distinguish an empty Lua
            # array from an empty dictionary; this schema field is an array.
            if tags == {}:
                item["tags"] = tags = []
            demand(isinstance(tags, list) and all(isinstance(t, str) for t in tags) and tags == sorted(set(tags)), "Invalid native tags")
            if klass != "RemoteEvent":
                demand(item.get("sourceEditorMatches") is True, "Native Source/editor conflict")
                for key in ("sourceBytes", "canonicalBytes", "sourceHash"):
                    demand(type(item.get(key)) is int and item[key] >= 0, "Invalid native source metadata")
                for key in ("rawSourceSHA256", "rawEditorSHA256", "sourceSHA256"):
                    demand(isinstance(item.get(key), str) and re.fullmatch(r"[0-9a-f]{64}", item[key]), "Invalid native SHA256")
                demand(item["rawSourceSHA256"] == item["rawEditorSHA256"], "Native Source/editor SHA256 conflict")
    for path in paths:
        demand(not any(PurePosixPath(*PurePosixPath(path).parts[:i]).as_posix() in paths for i in range(1, len(PurePosixPath(path).parts))), "Native file/directory collision")
    return value


def inventory(snapshot):
    return copy.deepcopy({key: snapshot[key] for key in ("placeId", "universeId", "sources", "remotes")})


def same(a, b):
    """JSON equality retains boolean/number distinctions that Python == loses."""
    return json.dumps(a, sort_keys=True, ensure_ascii=False, allow_nan=False) == json.dumps(b, sort_keys=True, ensure_ascii=False, allow_nan=False)


def file_sha(root, relative):
    path = safe_path(root, relative)
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def candidates(root, roots):
    result = set()
    for service in roots:
        checked_segment(service)
        folder = root / service
        demand(folder.resolve().is_relative_to(root.resolve()) and not folder.is_symlink(), "Unsafe Studio root")
        if folder.exists():
            demand(folder.is_dir(), f"Studio root is not a directory: {service}")
            for path in folder.rglob("*"):
                if path.is_file() and MIRROR_NAME.search(path.name):
                    rel = path.relative_to(root).as_posix()
                    safe_path(root, rel);result.add(rel)
    return result


def tracked_files(root):
    return set(subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode("utf-8").split("\0")) - {""}


def baseline(root, value, tracked=None):
    tracked = tracked_files(root) if tracked is None else tracked
    roots = sorted(BASE_ROOTS | {item["segments"][0] for item in value["sources"] + value["remotes"]})
    present = candidates(root, roots)
    listed = set()
    manifest_path = safe_path(root, MANIFEST)
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for item in manifest.get("items", []):
            rel = item.get("file")
            if isinstance(rel, str) and rel and PurePosixPath(rel).parts[0] in roots and MIRROR_NAME.search(rel):
                safe_path(root, rel);listed.add(rel)
    expected = {relative(item) for item in value["sources"] + value["remotes"]}
    expected_case = {rel.casefold(): rel for rel in expected}
    demand(all(expected_case.get(rel.casefold(), rel) == rel for rel in present), "Existing mirror casing differs from Studio; reconcile casing before capture")
    extras = present - expected
    removable = extras & (tracked | listed)
    demand(extras == removable, "Untracked/unlisted retired mirrors require review: " + repr(sorted(extras - removable)))
    affected = expected | present | {MANIFEST}
    return {"roots": roots, "presentMirrors": sorted(present), "removable": sorted(removable),
            "files": {rel: file_sha(root, rel) for rel in sorted(affected)}}


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def connect(args, factory):
    client = (factory or (lambda: StudioMcpClient(find_mcp_batch())))()
    try:
        client.initialize()
        studio = select_studio(client, args.studio_name, args.connect_timeout)
        require_edit_state(client, studio["id"])
        return client, studio
    except BaseException:
        client.close();raise


def native_read(client, studio, code):
    return json.loads(client.call("execute_luau", {"studio_id": studio["id"], "datamodel_type": "Edit", "code": code}))


def read_inventory(client, studio):
    page = native_read(client, studio, ENUMERATE)
    demand(isinstance(page, dict), "Invalid native catalog page")
    keys = ("catalogBytes", "catalogSHA256", "catalogHash", "sourceCount", "remoteCount")
    header = {key: page.get(key) for key in keys}
    for key in ("catalogBytes", "catalogHash", "sourceCount", "remoteCount"):
        demand(type(header[key]) is int and header[key] >= 0, "Invalid native catalog header")
    demand(header["catalogBytes"] > 0 and isinstance(header["catalogSHA256"], str)
           and re.fullmatch(r"[0-9a-f]{64}", header["catalogSHA256"]), "Invalid native catalog hash")
    chunks = []
    for first in range(1, header["catalogBytes"] + 1, INVENTORY_CHUNK_BYTES):
        if first > 1:
            page = native_read(client, studio, inventory_page_code(first, header))
        demand(isinstance(page, dict) and same({key: page.get(key) for key in keys}, header), "Complete native catalog changed between pages")
        demand(type(page.get("first")) is int and page["first"] == first and isinstance(page.get("hex"), str), "Invalid native catalog page offset/data")
        raw = bytes.fromhex(page["hex"])
        demand(len(raw) == min(INVENTORY_CHUNK_BYTES, header["catalogBytes"] - first + 1), "Truncated native catalog page")
        chunks.append(raw)
        if first > 1:
            print(f"Native catalog page {len(chunks)}: {min(first + len(raw) - 1, header['catalogBytes'])}/{header['catalogBytes']} bytes", flush=True)
    data = b"".join(chunks)
    demand(hashlib.sha256(data).hexdigest() == header["catalogSHA256"] and djb2(data) == header["catalogHash"], "Native catalog transfer hash mismatch")
    value = json.loads(data.decode("utf-8"))
    for group in ("sources", "remotes"):
        if value.get(group) == {}: value[group] = []
    value = validate_inventory(value)
    demand(len(value["sources"]) == header["sourceCount"] and len(value["remotes"]) == header["remoteCount"], "Native catalog count mismatch")
    return value


def chunk_code(item, start):
    # Compare the entire row on every chunk, including native identity/metadata.
    raw = json.dumps(item, ensure_ascii=False, separators=(",", ":"))
    return COMMON + f'''
-- snapshot-chunk
local segments={{{','.join(luau_string(s) for s in item['segments'])}}}
local expected=H:JSONDecode({luau_string(raw)})
local inst=resolve(segments)
local actual=record(inst)
-- Empty attributes can cross JSON as [] whereas the native table is {{}}.
assert(canonical(actual)==canonical(expected),"Instance/source/editor/metadata changed during transfer")
local text=inst.Source
assert(#text=={item['sourceBytes']} and sha(text)=={luau_string(item['rawSourceSHA256'])} and fingerprint(text)=={item['sourceHash']},"Source changed before chunk")
local chunk=hexChunk(text,{start},{start + CHUNK_BYTES - 1})
assert(canonical(record(inst))==canonical(expected),"Instance/source/editor/metadata changed after chunk")
return H:JSONEncode(chunk)
'''


def capture(args, client_factory=None, tracked=None):
    root, output = args.project_root.resolve(), args.output.resolve()
    demand(root.is_dir(), "Project root does not exist")
    demand(not (output / "snapshot.json").exists() and not (output / "sources").exists(), "Snapshot/partial sources already exist; use a fresh output directory")
    client, studio = connect(args, client_factory)
    try:
        first = read_inventory(client, studio)
        local_before = baseline(root, first, tracked)
        output.mkdir(parents=True, exist_ok=True)
        reused = transferred = 0
        for index, item in enumerate(first["sources"], 1):
            rel = relative(item)
            path = safe_path(root, rel)
            data = path.read_bytes() if path.is_file() else None
            if data is None or len(data) != item["sourceBytes"] or hashlib.sha256(data).hexdigest() != item["rawSourceSHA256"] or djb2(data) != item["sourceHash"]:
                data = b"".join(bytes.fromhex(native_read(client, studio, chunk_code(item, start))) for start in range(1, item["sourceBytes"] + 1, CHUNK_BYTES))
                transferred += 1
            else:
                reused += 1
            demand(len(data) == item["sourceBytes"] and hashlib.sha256(data).hexdigest() == item["rawSourceSHA256"] and djb2(data) == item["sourceHash"], f"Incomplete/corrupt native source: {rel}")
            canonical = canonical_bytes(data.decode("utf-8"))
            demand(len(canonical) == item["canonicalBytes"] and hashlib.sha256(canonical).hexdigest() == item["sourceSHA256"], f"Canonical native hash mismatch: {rel}")
            target = safe_path(output / "sources", rel)
            target.parent.mkdir(parents=True, exist_ok=True);target.write_bytes(data)
            print(f"[{index}/{len(first['sources'])}] {rel}", flush=True)
        final = read_inventory(client, studio)
        demand(same(first, final), "Complete Studio inventory changed during capture; frozen snapshot was not completed")
        require_edit_state(client, studio["id"])
        verify_baseline(root, local_before)
        snapshot = {**first, "schema": "complete-studio-snapshot-v1", "studio": studio,
                    "capturedAtUtc": datetime.now(timezone.utc).isoformat(), "datamodel": "Edit", "readOnly": True,
                    "reusedVerifiedFiles": reused, "transferredFiles": transferred, "repoBaseline": local_before}
        write_json(output / "snapshot.json", snapshot)
        print(f"Complete stable snapshot: {len(first['sources'])} scripts, {len(first['remotes'])} RemoteEvents.", flush=True)
        return snapshot
    finally:
        client.close()


def load_snapshot(output):
    snapshot = json.loads((output / "snapshot.json").read_text(encoding="utf-8"))
    demand(snapshot.get("schema") == "complete-studio-snapshot-v1" and snapshot.get("datamodel") == "Edit" and snapshot.get("readOnly") is True, "Not a complete read-only Edit snapshot")
    validate_inventory(snapshot)
    for item in snapshot["sources"]:
        data = safe_path(output / "sources", relative(item)).read_bytes()
        demand(len(data) == item["sourceBytes"] and hashlib.sha256(data).hexdigest() == item["rawSourceSHA256"] and djb2(data) == item["sourceHash"], "Frozen source was changed/corrupted")
        canonical = canonical_bytes(data.decode("utf-8"))
        demand(len(canonical) == item["canonicalBytes"] and hashlib.sha256(canonical).hexdigest() == item["sourceSHA256"], "Frozen canonical source metadata was changed/corrupted")
    return snapshot


def verify(args, client_factory=None):
    snapshot = load_snapshot(args.output.resolve())
    client, studio = connect(args, client_factory)
    try:
        demand(same(read_inventory(client, studio), inventory(snapshot)), "Current Studio differs from captured complete inventory")
        require_edit_state(client, studio["id"])
        write_json(args.output.resolve() / "studio-verification.json", {"verifiedAtUtc": datetime.now(timezone.utc).isoformat(), "placeId": snapshot["placeId"], "universeId": snapshot["universeId"], "scripts": len(snapshot["sources"]), "remoteEvents": len(snapshot["remotes"]), "sourceEditorMatches": True, "readOnly": True})
        print("Fresh complete native Studio inventory and Source/editor parity verified.", flush=True)
    finally:
        client.close()


def verify_baseline(root, before):
    demand(isinstance(before, dict) and isinstance(before.get("files"), dict), "Missing repo baseline")
    demand(candidates(root, before["roots"]) == set(before["presentMirrors"]), "Managed local inventory changed since capture")
    for rel, expected in before["files"].items():
        demand(file_sha(root, rel) == expected, f"Local file changed since capture: {rel}")


def apply(args):
    root, output = args.project_root.resolve(), args.output.resolve()
    snapshot = load_snapshot(output)
    before = snapshot["repoBaseline"]
    verify_baseline(root, before)
    demand(not (output / "before-mirror.zip").exists(), "Apply checkpoint already exists; do not reapply")
    entries, updates = [], {}
    previous = json.loads(safe_path(root, MANIFEST).read_text(encoding="utf-8")) if file_sha(root, MANIFEST) else {}
    from sync_from_studio import reconcile_source, trailing_newline_flags
    flags = trailing_newline_flags(previous)
    created = 0
    for item in snapshot["sources"] + snapshot["remotes"]:
        rel = relative(item);path = safe_path(root, rel)
        old = path.read_bytes() if path.is_file() else None
        verdict = None
        if item["className"] == "RemoteEvent":
            text = normalize(old.decode("utf-8")) if old is not None else (
                "NOT a script -- this file mirrors a RemoteEvent object in Roblox Studio.\n\n"
                f"Studio path: {item['path']}\nObject type: RemoteEvent\n")
        else:
            source = safe_path(output / "sources", rel).read_bytes().decode("utf-8")
            _, text, verdict = reconcile_source(normalize(old.decode("utf-8")) if old is not None else None,
                                                normalize(source), flagged=item["path"] in flags)
        data = canonical_bytes(text)
        entry = {key: copy.deepcopy(item[key]) for key in ("segments", "className", "instanceId", "parentId", "properties", "attributes", "tags")}
        entry.update(studioPath=item["path"], file=rel, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), status="synced")
        if item["className"] != "RemoteEvent":
            entry.update({key: item[key] for key in ("sourceEditorMatches", "rawSourceSHA256", "rawEditorSHA256", "sourceSHA256", "sourceBytes", "sourceHash")})
            if verdict == "trailing-newline": entry["studioTrailingNewline"] = True
        entries.append(entry)
        if old is None or canonical_bytes(old.decode("utf-8")) != data:
            updates[rel] = data;created += old is None
    expected = {entry["file"] for entry in entries}
    demand(set(before["files"]) == expected | set(before["presentMirrors"]) | {MANIFEST}, "Incomplete/malformed local baseline")
    demand(set(before["removable"]) == set(before["presentMirrors"]) - expected, "Invalid retired mirror set")
    manifest = {"formatVersion": 1, "source": "Complete Roblox Studio native Edit snapshot; Source/editor verified", "studio": snapshot["studio"],
                "capturedAtUtc": snapshot["capturedAtUtc"], "placeId": snapshot["placeId"], "universeId": snapshot["universeId"], "datamodel": "Edit",
                "counts": {"scripts": len(snapshot["sources"]), "remoteEvents": len(snapshot["remotes"]), "total": len(entries),
                           "created": created, "updated": len(updates) - created, "unchanged": len(entries) - len(updates)},
                "extraMirroredFilesNotInStudio": [], "items": entries}
    refresh_trailing_newline_metadata(manifest)
    updates[MANIFEST] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    changed = sorted(set(updates) | set(before["removable"]))
    verify_baseline(root, before)
    with zipfile.ZipFile(output / "before-mirror.zip", "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for rel in changed:
            path = safe_path(root, rel)
            if path.is_file(): archive.write(path, rel)
        archive.writestr("baseline.json", json.dumps(before, indent=2) + "\n")
    # Recheck the full baseline after the checkpoint, then each write's own path.
    verify_baseline(root, before)
    for rel, data in updates.items():
        demand(file_sha(root, rel) == before["files"][rel], f"Local baseline changed before write: {rel}")
        path = safe_path(root, rel);path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(data)
    for rel in before["removable"]:
        demand(file_sha(root, rel) == before["files"][rel], f"Local baseline changed before retirement: {rel}")
        safe_path(root, rel).unlink()
    for entry in entries:
        path = safe_path(root, entry["file"])
        demand(hashlib.sha256(canonical_bytes(path.read_bytes().decode("utf-8"))).hexdigest() == entry["sha256"], "Post-apply mirror verification failed")
    demand(candidates(root, before["roots"]) == expected, "Post-apply managed inventory mismatch")
    write_json(output / "stage-paths.json", changed)
    write_json(output / "apply-receipt.json", {"appliedAtUtc": datetime.now(timezone.utc).isoformat(), "filesChanged": changed,
                                               "removed": before["removable"], "counts": manifest["counts"], "studioWrites": 0})
    print(f"Repo reconciled: {len(entries)} mirrors, {len(updates) - 1} source/marker changes, {len(before['removable'])} retired mirrors.", flush=True)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("capture", "verify", "apply"))
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--studio-name", default=RELEASE_STUDIO_NAME)
    parser.add_argument("--connect-timeout", type=float, default=20)
    args = parser.parse_args()
    try:
        {"capture": capture, "verify": verify, "apply": apply}[args.command](args)
        return 0
    except (StudioMcpError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"SNAPSHOT FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
