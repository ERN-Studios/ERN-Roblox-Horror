"""Read-only final five-script/editor and imported-kit evidence from Studio Edit.

Does not write Studio, source mirrors, or a native place backup. Every transfer
chunk rechecks its source/editor or full-kit fingerprint; partial exports have
no manifest and must not be represented as a verified snapshot.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DEST = ROOT / "artifacts/level1-facelift-20261002/verified-studio"
SCRIPTS = [
    (["ServerScriptService", "GameManager"], "Script"),
    (["ServerScriptService", "Level 1 Systems", "MazeGenerator"], "Script"),
    (["ServerScriptService", "Level 1 Systems", "BlenderRoomRenderer"], "ModuleScript"),
    (["ServerScriptService", "Level1BlenderPreviewAccess"], "Script"),
    (["StarterPlayer", "StarterPlayerScripts", "Level1BlenderPreviewButton"], "LocalScript"),
]

COMMON = r'''
assert(game.PlaceId == 131311258779917, "Wrong place")
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local function fingerprint(text)
    local h = 5381
    for i=1,#text do h=(h*33+string.byte(text,i))%4294967296 end
    return h
end
local function resolve(segments)
    local inst=game
    for _,name in ipairs(segments) do
        local matched
        for _,child in ipairs(inst:GetChildren()) do
            if child.Name==name then
                assert(not matched,"Ambiguous instance name: "..name)
                matched=child
            end
        end
        inst=assert(matched,"Missing instance: "..name)
    end
    return inst
end
local function encoded(value)
    local kind=typeof(value)
    if kind=="nil" or kind=="boolean" or kind=="number" or kind=="string" then return value end
    if kind=="Vector3" then return {value.X,value.Y,value.Z} end
    if kind=="Vector2" then return {value.X,value.Y} end
    if kind=="Color3" then return {value.R,value.G,value.B} end
    if kind=="CFrame" then return {value:GetComponents()} end
    if kind=="EnumItem" then return tostring(value) end
    if kind=="Instance" then return value:GetFullName() end
    return {type=kind,value=tostring(value)}
end
local function attrs(inst)
    local out={}
    for key,value in pairs(inst:GetAttributes()) do out[key]=encoded(value) end
    return out
end
local function properties(inst,names)
    local out,errors={},{}
    for _,name in ipairs(names) do
        local ok,value=pcall(function() return inst[name] end)
        if ok then out[name]=encoded(value) else errors[#errors+1]=name end
    end
    return out,errors
end
local function scriptRecord(segments,expectedClass)
    local inst=resolve(segments)
    assert(inst.ClassName==expectedClass,"Changed script class")
    local source=inst.Source
    local ok,editor=pcall(SES.GetEditorSource,SES,inst)
    local names={"Archivable","SourceAssetId","LinkedSource"}
    if inst:IsA("BaseScript") then names[#names+1]="Disabled";names[#names+1]="RunContext" end
    local props,unsupported=properties(inst,names)
    return {segments=segments,class=inst.ClassName,sourceBytes=#source,sourceHash=fingerprint(source),
        editorReadSucceeded=ok,editorMatches=ok and editor==source,
        editorBytes=ok and #editor or nil,editorHash=ok and fingerprint(editor) or nil,
        properties=props,unsupportedProperties=unsupported,attributes=attrs(inst)}
end
-- Sorted keys make repeated JSON construction deterministic across reads.
local function canonical(value)
    if type(value)~="table" then return HS:JSONEncode(value) end
    local n=#value
    if n>0 then
        local parts={}
        for i=1,n do parts[i]=canonical(value[i]) end
        return "["..table.concat(parts,",").."]"
    end
    local keys,parts={},{}
    for key in pairs(value) do keys[#keys+1]=key end
    table.sort(keys)
    for i,key in ipairs(keys) do parts[i]=HS:JSONEncode(key)..":"..canonical(value[key]) end
    return "{"..table.concat(parts,",").."}"
end
local function hexChunk(text,first,last)
    -- A byte transfer avoids JSON corruption when a boundary splits UTF-8.
    return (string.gsub(string.sub(text,first,last),".",function(char)
        return string.format("%02x",string.byte(char))
    end))
end
'''

KIT = r'''
local function kitJSON()
    local kit=resolve({"ServerStorage","Level1BlenderKit"})
    assert(kit:IsA("Folder"),"Changed kit class")
    local records={}
    local counts={instances=0,meshParts=0,surfaceAppearances=0,colliders=0,rooms=0,components=0}
    local meshIds,pbrIds={},{}
    local function visit(inst,segments,indices)
        local names={"Archivable"}
        if inst:IsA("BasePart") then
            for _,name in ipairs({"Size","CFrame","Anchored","CanCollide","CanQuery","CanTouch",
                "CastShadow","Color","Material","MaterialVariant","Transparency","Reflectance",
                "CollisionGroup","LocalTransparencyModifier"}) do names[#names+1]=name end
        end
        if inst:IsA("Part") then names[#names+1]="Shape" end
        if inst:IsA("MeshPart") then
            for _,name in ipairs({"MeshId","TextureID","CollisionFidelity","RenderFidelity","DoubleSided"}) do names[#names+1]=name end
            counts.meshParts+=1
            meshIds[inst.MeshId]=true
        elseif inst:IsA("SurfaceAppearance") then
            for _,name in ipairs({"ColorMap","NormalMap","RoughnessMap","MetalnessMap","Color","AlphaMode"}) do names[#names+1]=name end
            counts.surfaceAppearances+=1
            for _,name in ipairs({"ColorMap","NormalMap","RoughnessMap","MetalnessMap"}) do
                if inst[name]~="" then pbrIds[inst[name]]=true end
            end
        elseif inst:IsA("Model") then
            for _,name in ipairs({"WorldPivot","PrimaryPart","ModelStreamingMode","LevelOfDetail"}) do names[#names+1]=name end
        end
        if inst:GetAttribute("RoomRole")=="Collider" then counts.colliders+=1 end
        if inst.Parent==kit:FindFirstChild("Rooms") then counts.rooms+=1 end
        if inst.Parent==kit:FindFirstChild("Components") then counts.components+=1 end
        local props,unsupported=properties(inst,names)
        records[#records+1]={path=inst:GetFullName(),segments=segments,childIndexPath=indices,
            class=inst.ClassName,properties=props,unsupportedProperties=unsupported,attributes=attrs(inst)}
        counts.instances+=1
        for index,child in ipairs(inst:GetChildren()) do
            local childSegments=table.clone(segments);childSegments[#childSegments+1]=child.Name
            local childIndices=table.clone(indices);childIndices[#childIndices+1]=index
            visit(child,childSegments,childIndices)
        end
    end
    visit(kit,{"ServerStorage","Level1BlenderKit"},{})
    local uniqueMeshIds,uniquePbrIds={},{}
    for id in pairs(meshIds) do uniqueMeshIds[#uniqueMeshIds+1]=id end
    for id in pairs(pbrIds) do uniquePbrIds[#uniquePbrIds+1]=id end
    table.sort(uniqueMeshIds);table.sort(uniquePbrIds)
    return canonical({placeId=game.PlaceId,universeId=game.GameId,
        root="ServerStorage.Level1BlenderKit",counts=counts,
        meshAssetIds=uniqueMeshIds,pbrAssetIds=uniquePbrIds,instances=records})
end
'''


def luau_table(values: list[str]) -> str:
    return "{" + ",".join(json.dumps(v) for v in values) + "}"


def fingerprint(data: bytes) -> int:
    value = 5381
    for byte in data:
        value = (value * 33 + byte) % 4294967296
    return value


def main() -> None:
    global SCRIPTS, KIT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Read fresh Studio Edit evidence")
    parser.add_argument("--output", type=Path, default=DEFAULT_DEST)
    parser.add_argument("--revision-v2", action="store_true")
    args = parser.parse_args()
    if args.revision_v2:
        SCRIPTS += [(["ServerScriptService", "Level 1 Systems", "PuzzleManager"], "Script"),
                    (["ServerScriptService", "Level 1 Systems", "EntityAnimation"], "Script")]
        KIT = KIT.replace("Level1BlenderKit", "Level1BlenderKitV2")
    if not args.run:
        print("Prepared read-only exporter. Run with --run only when Studio is in Edit.")
        return
    dest = args.output.resolve()
    if (dest / "manifest.json").exists():
        raise RuntimeError("A completed snapshot already exists; use a new evidence directory")
    if dest.exists() and any(dest.iterdir()):
        raise RuntimeError("Partial evidence exists; use a new evidence directory rather than overwrite")
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 15)

        def edit_state() -> str:
            state = client.call("get_studio_state", {"studio_id": studio["id"]})
            if "Current Studio Mode: Edit" not in state:
                raise RuntimeError("Authoritative Edit export required; stop Play before running")
            return state

        def execute(code: str):
            return json.loads(client.call("execute_luau", {
                "studio_id": studio["id"], "datamodel_type": "Edit", "code": code,
            }))

        state = edit_state()
        selected = "{" + ",".join(
            "{segments=" + luau_table(path) + ",class=" + json.dumps(cls) + "}"
            for path, cls in SCRIPTS
        ) + "}"
        metadata_code = COMMON + f'''
local selected={selected}
local out={{placeId=game.PlaceId,universeId=game.GameId,sources={{}},workspaceAttributes=attrs(workspace)}}
for _,item in ipairs(selected) do out.sources[#out.sources+1]=scriptRecord(item.segments,item.class) end
return HS:JSONEncode(out)
'''
        snapshot = execute(metadata_code)
        snapshot.update(studio=studio, state=state, datamodel="Edit",
                        capturedAtUtc=datetime.now(timezone.utc).isoformat(), readOnly=True)
        initial_sources = [dict(item) for item in snapshot["sources"]]

        def transfer(code: str, byte_count: int, expected_hash: int) -> bytes:
            pieces = []
            for start in range(1, byte_count + 1, 24000):
                chunk = execute(code + f"\nreturn HS:JSONEncode(hexChunk(text,{start},{start+23999}))")
                pieces.append(bytes.fromhex(chunk))
            data = b"".join(pieces)
            if len(data) != byte_count or fingerprint(data) != expected_hash:
                raise RuntimeError("Incomplete or changed transfer")
            return data

        dest.mkdir(parents=True)
        for item in snapshot["sources"]:
            if not item["editorReadSucceeded"]:
                raise RuntimeError("Editor source read failed: " + ".".join(item["segments"]))
            checks = COMMON + f'''
local inst=resolve({luau_table(item['segments'])})
assert(inst.ClassName=={json.dumps(item['class'])},"Script class changed")
local source=inst.Source
local editor=SES:GetEditorSource(inst)
assert(#source=={item['sourceBytes']} and fingerprint(source)=={item['sourceHash']},"Source changed during export")
assert(#editor=={item['editorBytes']} and fingerprint(editor)=={item['editorHash']},"Editor source changed during export")
assert((editor==source)=={str(item['editorMatches']).lower()},"Source/editor parity changed during export")
'''
            data = transfer(checks + "local text=source", item["sourceBytes"], item["sourceHash"])
            relative = Path(*item["segments"][:-1]) / (item["segments"][-1] + "." + item["class"] + ".lua")
            target = dest / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            item.update(file=relative.as_posix(), bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
            if item["editorMatches"]:
                item["editorSha256"] = item["sha256"]
            else:
                editor_data = transfer(checks + "local text=editor", item["editorBytes"], item["editorHash"])
                editor_relative = Path(str(relative) + ".editor.lua")
                (dest / editor_relative).write_bytes(editor_data)
                item.update(editorFile=editor_relative.as_posix(), editorSha256=hashlib.sha256(editor_data).hexdigest())
            print(f"Verified {relative.as_posix()} ({len(data)} bytes; editorMatches={item['editorMatches']})", flush=True)

        kit_baseline = execute(COMMON + KIT + '''
local text=kitJSON()
return HS:JSONEncode({bytes=#text,hash=fingerprint(text)})
''')
        print(f"Reading imported kit metadata ({kit_baseline['bytes']} bytes)", flush=True)
        kit_code = COMMON + KIT + f'''
local text=kitJSON()
assert(#text=={kit_baseline['bytes']} and fingerprint(text)=={kit_baseline['hash']},"Imported kit changed during export")
'''
        kit_data = transfer(kit_code, kit_baseline["bytes"], kit_baseline["hash"])
        kit = json.loads(kit_data)
        kit_file = ("Level1BlenderKitV2" if args.revision_v2 else "Level1BlenderKit") + ".instances.json"
        (dest / kit_file).write_bytes(kit_data)
        snapshot["kit"] = dict(kit_baseline, file=kit_file, sha256=hashlib.sha256(kit_data).hexdigest(),
                               counts=kit["counts"], meshAssetIds=kit["meshAssetIds"], pbrAssetIds=kit["pbrAssetIds"])

        # Recheck every source/editor/property record after the longer kit transfer.
        final_sources = execute(metadata_code)["sources"]
        if final_sources != initial_sources:
            raise RuntimeError("A script, editor, property or attribute changed during final export")
        execute(kit_code + '\nreturn HS:JSONEncode(true)')
        edit_state()
        snapshot["completedAtUtc"] = datetime.now(timezone.utc).isoformat()
        snapshot["editorConflicts"] = [item["file"] for item in snapshot["sources"] if not item["editorMatches"]]
        snapshot["allEditorSourcesMatch"] = not snapshot["editorConflicts"]
        (dest / "manifest.json").write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"destination": str(dest), "scripts": len(snapshot["sources"]),
                          "editorConflicts": snapshot["editorConflicts"], "kitCounts": kit["counts"]}), flush=True)
        if snapshot["editorConflicts"]:
            raise RuntimeError("Source/editor conflict recorded; do not mirror or claim parity")
    finally:
        client.close()


if __name__ == "__main__":
    main()
