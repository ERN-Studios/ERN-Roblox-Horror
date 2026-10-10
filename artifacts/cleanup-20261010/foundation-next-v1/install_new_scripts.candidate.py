"""Create NEW mirrored scripts in Studio through the supported editor tool, then register them.

The push tools cannot create scripts (CLAUDE.md, 2026-09-03), so a new mirror file is
installed here first: the Studio path and class are derived from the mirror path
(`StarterPlayer/StarterPlayerScripts/Name.LocalScript.lua` ->
`StarterPlayer.StarterPlayerScripts.Name`, class LocalScript), the script is created with
`multi_edit` when absent, its raw `.Source` is read back and compared byte for byte, and only
then is a `synced` manifest item written. An existing script whose source differs is reported
and left alone unless `--overwrite` is given (which then goes through
ScriptEditorService:UpdateSourceAsync, never a raw .Source write).

    python tools/install_new_scripts.py --dry-run <mirror path> [...]
    python tools/install_new_scripts.py <mirror path> [...]

Generalised from tools/install_trello_new_scripts.py (2026-09-14).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))  # Candidate location only
from sync_from_studio import (StudioMcpClient, StudioMcpError, find_mcp_batch, select_studio,
    read_native_record, native_metadata_code, EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID)  # noqa: E402
from push_repo_to_studio import luau_string  # noqa: E402
from studio_source_contract import normalize, refresh_trailing_newline_metadata, sha256_of  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]  # Candidate location only
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
local parent=game
for index=1,#names-1 do parent=assert(child(parent,names[index]),"Missing installer parent") end
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
    # Create only a new owned instance. Never route a missing-target race to an
    # edit operation that can attach to somebody else's newly created script.
    return path_guard(path) + r"""
assert(current==nil,"Installer target appeared")
assert(parent:GetDebugId(16)==__PARENT__,"Installer parent changed")
local owned=Instance.new(__CLASS__)
owned.Name=names[#names]
local initialEnabled=nil
if __CLASS__~="ModuleScript" then initialEnabled=owned.Enabled;owned.Enabled=false end
local initialProps={Archivable=owned.Archivable,LinkedSource=owned.LinkedSource}
if initialEnabled~=nil then initialProps.Enabled=owned.Enabled;initialProps.Disabled=owned.Disabled;initialProps.RunContext=owned.RunContext end
local function sameProps()
 for key,value in initialProps do if owned[key]~=value then return false end end
 return true
end
local function ownedState(allowedSource)
 return owned.Parent==parent and child(parent,names[#names])==owned
  and parent:GetDebugId(16)==__PARENT__ and owned.ClassName==__CLASS__
  and sameProps()
  and owned.Source==allowedSource and SES:GetEditorSource(owned)==allowedSource
  and next(owned:GetAttributes())==nil and #game:GetService("CollectionService"):GetTags(owned)==0
end
local ok,err=pcall(function()
 assert(owned.Source=="" and SES:GetEditorSource(owned)=="","New script not empty")
 assert(child(parent,names[#names])==nil,"Installer target appeared")
 owned.Parent=parent
 SES:UpdateSourceAsync(owned,function(old)
  assert(not RS:IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407,"Native mode/place changed")
  assert(old=="" and ownedState(""),"Owned new script changed")
  return __SOURCE__
 end)
 assert(ownedState(__SOURCE__),"Owned script landing changed")
 if initialEnabled~=nil then owned.Enabled=initialEnabled end
end)
if not ok then
 -- Destroy only the exact instance created by this call and only while its
 -- Source/editor/attrs/tags still belong to this attempt. Foreign edits stay.
 if owned.Parent==nil or ownedState("") or ownedState(__SOURCE__) then owned:Destroy() end
 error(err)
end
return "ok"
""".replace("__PARENT__", luau_string(parent_id)).replace("__CLASS__", luau_string(kind)).replace("__SOURCE__", luau_string(source))


def native_read(client, sid, path, kind):
    return read_native_record(client, sid, {"fullPath": path, "className": kind},
                              EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID)


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
                presence = json.loads(client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": lua_lookup(path)}))
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
            item = {"studioPath": path, "className": kind, "file": file, "bytes": len(src.encode("utf-8")),
                    "sha256": sha256_of(src), "status": "synced",
                    "segments": native["segments"], "properties": native["properties"],
                    "attributes": native["attributes"] or [], "tags": native["tags"],
                    "sourceEditorMatches": native["sourceEditorMatches"]}
            if actual == src + "\n":
                item["studioTrailingNewline"] = True
            manifest["items"] = [i for i in manifest["items"] if i["file"] != file] + [item]
            manifest["studio"] = studio
            manifest["counts"]["scripts"] = sum(i["className"] in CLASSES for i in manifest["items"])
            manifest["counts"]["total"] = len(manifest["items"])
            refresh_trailing_newline_metadata(manifest)
            manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            manifest_bytes = manifest_path.read_bytes()
            print(f"VERIFIED {path}")
    finally:
        client.close()
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
