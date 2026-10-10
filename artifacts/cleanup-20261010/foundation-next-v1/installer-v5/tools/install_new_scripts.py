"""Install explicitly selected authoring mirrors with fresh native compare-and-swap.

Studio remains authoritative. This manual tool defaults to refusing differing
existing Source; --overwrite is an explicit authoring operation against a fresh
Source/editor/identity/class/property/attribute/tag baseline, checked again in
the UpdateSourceAsync callback. No raw Source setter, bulk sync or mode switch.

Missing targets use a fresh owned empty LuaSourceContainer; callback and cleanup
checks preserve concurrently created or modified objects. Fresh native metadata
is registered only after verification. Registration is separate from native
mutation: a final conflict can leave a successfully installed owned Source with
the old manifest, reported as a failure for current-native reconciliation.

    python tools/install_new_scripts.py --dry-run <mirror path> [...]
    python tools/install_new_scripts.py <mirror path> [...]

Source reads are bounded to 64 lines / 8 kB per native response. Write payloads
retain the existing single-literal request; no large native-write certification.
"""
from __future__ import annotations

import argparse
import copy
import os
import types
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sync_from_studio import (StudioMcpClient, StudioMcpError, find_mcp_batch, select_studio,
    native_metadata_code, validate_native_metadata, require_edit_state, EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID)  # noqa: E402
from push_repo_to_studio import luau_string, read_studio_source  # noqa: E402
from studio_source_contract import canonical_bytes, normalize, refresh_trailing_newline_metadata, sha256_of  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
PLACE = "BACKROOMS: STAY QUIET [CO-OP HORROR]"
CLASSES = ("Script", "LocalScript", "ModuleScript")


def plan(mirror: str) -> tuple[str, str, str]:
    """mirror path -> (file, studio dotted path, class)."""
    file = mirror.replace("\\", "/").strip("/")
    name = file.rsplit("/", 1)[-1]
    if not name.endswith(".lua"):
        raise SystemExit(f"not a mirrored Lua file: {mirror}")
    stem, kind = name[:-4].rsplit(".", 1)
    if kind not in CLASSES:
        raise SystemExit(f"unknown class suffix in {mirror}")
    parts = file.split("/")[:-1] + [stem]
    return file, ".".join(parts), kind


def lua_value(value) -> str:
    """Embed already-validated metadata, preserving strings/false/empty tables."""
    if value is None: return "nil"
    if isinstance(value, bool): return "true" if value else "false"
    if isinstance(value, (int, float)): return repr(value)
    if isinstance(value, str): return luau_string(value)
    if isinstance(value, list): return "{" + ",".join(lua_value(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[" + luau_string(k) + "]=" + lua_value(v) for k, v in value.items()) + "}"
    raise StudioMcpError("Unsupported installer metadata value")


PATH_GUARD = r"""
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local names=__NAMES__
assert(not RS:IsRunning(),"Installer requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
local function child(parent,name)
 local found=nil
 for _,value in parent:GetChildren() do
  if value.Name==name then assert(found==nil,"Ambiguous installer path");found=value end
 end
 return found
end
local function resolveParent()
 local value=game
 for index=1,#names-1 do value=assert(child(value,names[index]),"Missing installer parent") end
 return value
end
local parent=resolveParent()
local current=child(parent,names[#names])
"""


def path_guard(path: str) -> str:
    return PATH_GUARD.replace("__NAMES__", lua_value(path.split(".")))


def lua_lookup(path: str) -> str:
    # Presence and parent identity only. Existing Source/editor/property facts
    # are subsequently read by the verified shared metadata/chunk contract.
    return path_guard(path) + '\nreturn H:JSONEncode({missing=current==nil,parentId=parent:GetDebugId(16)})'


def lua_update(path: str, source: str, baseline: dict) -> str:
    metadata = native_metadata_code(path.split("."), baseline["className"], EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID)
    return path_guard(path) + r"""
assert(current,"Missing installer target")
local expected=__EXPECTED__
local function same(a,b)
 assert(type(a)==type(b),"Installer baseline changed")
 if type(a)~="table" then assert(a==b,"Installer baseline changed");return end
 for key,value in a do same(value,b[key]) end
 for key in b do assert(a[key]~=nil,"Installer baseline changed") end
end
local function capture()
 local result=(function()
__METADATA__
 end)()
 return H:JSONDecode(result)
end
local function sha(text)
 local bytes=game:GetService("EncodingService"):ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local values={} for index=0,buffer.len(bytes)-1 do values[#values+1]=string.format("%02x",buffer.readu8(bytes,index)) end
 return table.concat(values)
end
same(expected,capture())
SES:UpdateSourceAsync(current,function(old)
 -- Repeat Source/editor/identity/class/properties/attrs/tags/mode/place checks
 -- inside the callback, after every potentially yielding Python/native read.
 assert(child(parent,names[#names])==current,"Installer target replaced")
 same(expected,capture())
 assert(type(old)=="string" and sha(old)==expected.rawEditorSHA256,"Installer callback Source changed")
 return __SOURCE__
end)
return "ok"
""".replace("__EXPECTED__", lua_value(baseline)).replace("__METADATA__", metadata).replace("__SOURCE__", luau_string(source))


def lua_create(path: str, source: str, kind: str, parent_id: str) -> str:
    # The only writable object is created by this call, never looked up as an
    # overwrite fallback. Parent-path/identity races refuse inside the callback.
    return path_guard(path) + r"""
assert(current==nil,"Installer target appeared")
assert(parent:GetDebugId(16)==__PARENT__,"Installer parent changed")
local owned=Instance.new(__CLASS__)
local ownedId=owned:GetDebugId(16)
local attached=false
local initialEnabled=nil
local initialProps={Archivable=owned.Archivable,LinkedSource=owned.LinkedSource}
if __CLASS__~="ModuleScript" then
 initialEnabled=owned.Enabled
 initialProps.Enabled=owned.Enabled;initialProps.Disabled=owned.Disabled;initialProps.RunContext=owned.RunContext
end
local expectedProps=table.clone(initialProps)
local expectedName=owned.Name
local function identity()
 return owned.ClassName==__CLASS__ and owned:GetDebugId(16)==ownedId and owned.Name==expectedName
end
local function ownFields(allowedSource)
 if not identity() then return false end
 for key,value in expectedProps do if owned[key]~=value then return false end end
 return owned.Source==allowedSource and SES:GetEditorSource(owned)==allowedSource
  and next(owned:GetAttributes())==nil and #game:GetService("CollectionService"):GetTags(owned)==0
end
local function ownedState(allowedSource)
 return resolveParent()==parent and parent:GetDebugId(16)==__PARENT__
  and owned.Parent==parent and child(parent,names[#names])==owned and ownFields(allowedSource)
end
local ok,err=pcall(function()
 assert(owned.Source=="" and SES:GetEditorSource(owned)=="","New script not empty")
 expectedName=names[#names];owned.Name=expectedName
 if initialEnabled~=nil then
  expectedProps.Enabled=false;expectedProps.Disabled=true;owned.Enabled=false
 end
 assert(owned.Parent==nil and ownFields(""),"Fresh owned setup changed")
 assert(resolveParent()==parent and parent:GetDebugId(16)==__PARENT__,"Installer parent changed")
 assert(child(parent,names[#names])==nil,"Installer target appeared")
 owned.Parent=parent;attached=true
 SES:UpdateSourceAsync(owned,function(old)
  assert(not RS:IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407,"Native mode/place changed")
  assert(old=="" and ownedState(""),"Owned new script changed")
  return __SOURCE__
 end)
 assert(ownedState(__SOURCE__),"Owned script landing changed")
 if initialEnabled~=nil then
  expectedProps.Enabled=initialEnabled;expectedProps.Disabled=not initialEnabled
  owned.Enabled=initialEnabled
 end
 assert(ownedState(__SOURCE__),"Owned script final state changed")
end)
if not ok then
 -- Parent=nil is not unconditional deletion authority. Once attached, any
 -- foreign move is retained; unknown getter outcomes retain the object too.
 local clean,problem=pcall(function()
  local ownedParent=(not attached and owned.Parent==nil) or
   (owned.Parent==parent and resolveParent()==parent and parent:GetDebugId(16)==__PARENT__
    and child(parent,names[#names])==owned)
  if ownedParent and (ownFields("") or ownFields(__SOURCE__)) then owned:Destroy() end
 end)
 if not clean then error(tostring(err).."; owned cleanup unknown, preserved: "..tostring(problem)) end
 error(err)
end
return "ok"
""".replace("__PARENT__", luau_string(parent_id)).replace("__CLASS__", luau_string(kind)).replace("__SOURCE__", luau_string(source))


def native_read(client, sid, path, kind):
    """Use the S13 getter/schema and real reader in an isolated bounded namespace."""
    segments = path.split(".")
    code = native_metadata_code(segments, kind, EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID)
    namespace = {**read_studio_source.__globals__, "READ_CHUNK_LINES": 64}
    reader = types.FunctionType(read_studio_source.__code__, namespace)
    class BoundedClient:
        def call(self, tool, arguments=None):
            response = client.call(tool, arguments)
            if not isinstance(response, str):
                raise StudioMcpError("Unreadable installer native response")
            source_chunk = tool == "execute_luau" and "local first, count =" in (arguments or {}).get("code", "")
            limit = 8000 if source_chunk else 20000
            if len(response.encode("utf8")) > limit:
                raise StudioMcpError("Installer native response exceeds bounded transport")
            return response
    bounded = BoundedClient()
    def capture():
        try:
            value = json.loads(bounded.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}))
        except (ValueError, TypeError) as error:
            raise StudioMcpError("Unreadable native metadata response") from error
        if isinstance(value, dict) and value.get("attributes") == []:
            value["attributes"] = {}
        validate_native_metadata(value, segments, kind, EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID)
        return value
    require_edit_state(bounded, sid)
    before = capture()
    source = reader(bounded, sid, segments)
    after = capture()
    require_edit_state(bounded, sid)
    if before != after:
        raise StudioMcpError("Native Source/identity/properties/attributes/tags changed during chunk read")
    if len(canonical_bytes(source)) != before["canonicalBytes"] or sha256_of(source) != before["sourceSHA256"]:
        raise StudioMcpError("Native metadata/chunk Source hash mismatch")
    return source, before


def presence_read(client, sid, path):
    try:
        response = client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": lua_lookup(path)})
        if not isinstance(response, str) or len(response.encode("utf8")) > 20000:
            raise StudioMcpError("Unreadable installer presence")
        value = json.loads(response)
    except (ValueError, TypeError) as error:
        raise StudioMcpError("Unreadable installer presence") from error
    if not isinstance(value, dict) or set(value) != {"missing", "parentId"} or type(value["missing"]) is not bool or not isinstance(value["parentId"], str) or not value["parentId"]:
        raise StudioMcpError("Invalid installer presence/parent identity")
    return value


def register_manifest(path, before, value):
    """Immediate byte CAS and atomic replace, not a cross-process lock."""
    encoded = (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf8")
    temporary = path.with_name(path.name + ".installer-owned.tmp")
    if temporary.exists():
        raise StudioMcpError("Existing installer temp file preserved")
    owned_identity = None
    owned_body = None
    try:
        with temporary.open("xb") as stream:
            stat = os.fstat(stream.fileno())
            owned_identity = (stat.st_dev, stat.st_ino)
            # Unknown or partial write outcomes retain the temp for review.
            written = stream.write(encoded)
            if written != len(encoded):
                raise StudioMcpError("Incomplete installer temp write; preserved")
            owned_body = encoded
        if path.read_bytes() != before:
            raise StudioMcpError("Manifest changed before atomic registration; preserve it")
        os.replace(temporary, path)
        if path.read_bytes() != encoded:
            raise StudioMcpError("Manifest changed after registration; preserve current bytes")
    finally:
        if owned_identity is not None and owned_body is not None:
            try:
                current = temporary.stat()
            except FileNotFoundError:
                pass
            else:
                if (current.st_dev, current.st_ino) == owned_identity and temporary.read_bytes() == owned_body:
                    temporary.unlink()


def stable_metadata(before, after):
    source_fields = {"rawSourceSHA256", "rawEditorSHA256", "sourceSHA256", "canonicalBytes"}
    return {k: v for k, v in before.items() if k not in source_fields} == {k: v for k, v in after.items() if k not in source_fields}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", help="mirror paths relative to the repo root")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--overwrite", action="store_true", help="UpdateSourceAsync onto an existing script that differs")
    args = ap.parse_args()
    plans = [plan(f) for f in args.files]
    for file, path, kind in plans:
        if not (ROOT / file).exists():
            raise SystemExit(f"missing mirror file: {file}")
        print(f"PLAN {kind:12} game.{path}  <-  {file}")
    if args.dry_run:
        return 0
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    targeted = {file for file, _, _ in plans}
    for file in targeted:
        if sum(item.get("file") == file for item in manifest.get("items", [])) > 1:
            raise StudioMcpError("Duplicate targeted manifest rows; no write")
    queued = [item.get("file") for item in manifest.get("items", [])
              if item.get("file") in targeted and item.get("status") in {"pending-studio-push", "studio-push-conflict"}]
    if queued:
        raise StudioMcpError("Installer refuses queued/conflicted targets: " + ", ".join(queued))
    client = StudioMcpClient(find_mcp_batch())
    failures = 0
    try:
        client.initialize()
        time.sleep(3)
        studio = select_studio(client, PLACE, 20)
        sid = studio["id"]
        for file, path, kind in plans:
            src = normalize((ROOT / file).read_text(encoding="utf-8"))
            try:
                presence = presence_read(client, sid, path)
                if presence.get("missing") is True:
                    if not isinstance(presence.get("parentId"), str) or not presence["parentId"]:
                        raise StudioMcpError("Missing parent identity")
                    client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit",
                                "code": lua_create(path, src, kind, presence["parentId"])})
                    actual, native = native_read(client, sid, path, kind)
                else:
                    actual, before = native_read(client, sid, path, kind)
                    if actual not in (src, src + "\n"):
                        if not args.overwrite:
                            print(f"DIFFERS {path}: Studio holds other source; no write performed")
                            failures += 1
                            continue
                        client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit",
                                    "code": lua_update(path, src, before)})
                    actual, native = native_read(client, sid, path, kind)
                    if not stable_metadata(before, native):
                        raise StudioMcpError("Native identity/class/properties/attributes/tags changed before registration")
                if actual not in (src, src + "\n"):
                    raise StudioMcpError("Source mismatch after install")
                if manifest_path.read_bytes() != manifest_bytes:
                    raise StudioMcpError("Manifest changed concurrently; registration refused")
            except StudioMcpError as error:
                print(f"FAILED {path}: {error}")
                failures += 1
                continue
            previous = [row for row in manifest["items"] if row.get("file") == file]
            item = copy.deepcopy(previous[0]) if previous else {}
            item.pop("studioTrailingNewline", None)
            item.update({"studioPath": path, "className": kind, "file": file, "bytes": len(src.encode("utf-8")),
                    "sha256": sha256_of(src), "status": "synced",
                    "segments": native["segments"], "properties": native["properties"],
                    "attributes": native["attributes"] or [], "tags": native["tags"],
                    "sourceEditorMatches": native["sourceEditorMatches"]})
            if actual == src + "\n":
                item["studioTrailingNewline"] = True
            manifest["items"] = [i for i in manifest["items"] if i["file"] != file] + [item]
            manifest["studio"] = studio
            manifest["counts"]["scripts"] = sum(i["className"] in CLASSES for i in manifest["items"])
            manifest["counts"]["total"] = len(manifest["items"])
            refresh_trailing_newline_metadata(manifest)
            try:
                register_manifest(manifest_path, manifest_bytes, manifest)
            except (StudioMcpError, OSError) as error:
                print(f"FAILED {path}: {error}")
                failures += 1
                break
            manifest_bytes = manifest_path.read_bytes()
            print(f"VERIFIED {path}")
    finally:
        client.close()
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
