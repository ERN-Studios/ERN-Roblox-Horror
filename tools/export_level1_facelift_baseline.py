"""Read-only, scoped source/editor snapshot for the Level 1 facelift."""

from __future__ import annotations

import hashlib
import json
import argparse
from pathlib import Path

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio


ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "artifacts/level1-facelift-20261002/live-before"
CODE = r'''
assert(game.PlaceId == 131311258779917, "Wrong place")
local selected = {}
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local SP = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local SES = game:GetService("ScriptEditorService")
local folder = SSS:FindFirstChild("Level 1 Systems")
assert(folder, "Missing Level 1 Systems")
for _, inst in folder:GetDescendants() do
    if inst:IsA("LuaSourceContainer") then selected[#selected+1] = inst end
end
local wanted = {
    [SSS] = {"GameManager", "Reentry", "Round Completion Routing", "Round Loading Runtime", "PlayerProtection", "Level1BlenderPreviewAccess"},
    [RS] = {"MasterConfiguration", "DevAccess", "NoiseRegistry", "DeathAdvice"},
}
if SP then wanted[SP] = {"Level 1 Cable Current", "Level 1 Sound Controller", "DevCheats", "RoundUI", "Round Entry Client", "Round Exit Client", "Level4PreviewAccess", "Level5PreviewAccess", "Level6PreviewAccess", "Level1BlenderPreviewButton"} end
for parent,names in wanted do
    for _,name in names do
        local inst = parent:FindFirstChild(name)
        if inst and inst:IsA("LuaSourceContainer") then selected[#selected+1]=inst end
    end
end
local out = {placeId=game.PlaceId, universeId=game.GameId, workspaceAttributes=workspace:GetAttributes(), sources={}}
local function hash(text)
    local h=5381
    for i=1,#text do h=(h*33+string.byte(text,i))%4294967296 end
    return h
end
for _,inst in selected do
    local segments={inst.Name}; local p=inst.Parent
    while p and p~=game do table.insert(segments,1,p.Name);p=p.Parent end
    local ok,editor=pcall(SES.GetEditorSource,SES,inst)
    local props={}
    if inst:IsA("BaseScript") then props.Disabled=inst.Disabled;props.RunContext=tostring(inst.RunContext) end
    out.sources[#out.sources+1]={segments=segments,class=inst.ClassName,sourceBytes=#inst.Source,sourceHash=hash(inst.Source),
        editorReadSucceeded=ok,editorMatches=ok and editor==inst.Source,editorBytes=ok and #editor or nil,
        editorHash=ok and hash(editor) or nil,
        properties=props,attributes=inst:GetAttributes()}
end
return game:GetService("HttpService"):JSONEncode(out)
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", type=Path, default=DEST)
    args = parser.parse_args()
    destination = args.dest.resolve()
    if (destination / "manifest.json").exists():
        raise RuntimeError("The first live-before snapshot already exists; do not overwrite its task evidence")
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 15)
        state = client.call("get_studio_state", {"studio_id": studio["id"]})
        if "Current Studio Mode: Edit" not in state:
            raise RuntimeError(f"Edit baseline required: {state}")
        snapshot = json.loads(client.call("execute_luau", {
            "studio_id": studio["id"], "datamodel_type": "Edit", "code": CODE,
        }))
        destination.mkdir(parents=True, exist_ok=True)
        snapshot["studio"] = studio
        for item in snapshot["sources"]:
            path = Path(*item["segments"][:-1]) / (item["segments"][-1] + "." + item["class"] + ".lua")
            segments = "{" + ",".join(json.dumps(segment) for segment in item["segments"]) + "}"
            source_parts = []
            for start in range(1, item["sourceBytes"] + 1, 24000):
                read_code = f'''local inst=game;for _,name in {segments} do inst=assert(inst:FindFirstChild(name),name) end
local text=inst.Source;local h=5381;for i=1,#text do h=(h*33+string.byte(text,i))%4294967296 end
assert(#text=={item['sourceBytes']} and h=={item['sourceHash']},"Source changed; export again")
local ok,editor=pcall(function() return game:GetService("ScriptEditorService"):GetEditorSource(inst) end)
assert(ok and (editor==text)=={str(item['editorMatches']).lower()},"Editor parity changed; export again")
return game:GetService("HttpService"):JSONEncode((string.gsub(string.sub(text,{start},{start + 23999}),".",function(char)
    return string.format("%02x",string.byte(char))
end)))'''
                source_parts.append(bytes.fromhex(json.loads(client.call("execute_luau", {
                    "studio_id": studio["id"], "datamodel_type": "Edit", "code": read_code,
                }))))
            data = b"".join(source_parts)
            fingerprint = 5381
            for byte in data:
                fingerprint = (fingerprint * 33 + byte) % 4294967296
            if len(data) != item["sourceBytes"] or fingerprint != item["sourceHash"]:
                raise RuntimeError(f"Incomplete or changed source transfer: {path}")
            target = destination / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            item.update(file=path.as_posix(), bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
            if item["editorMatches"]:
                item["editorSha256"] = item["sha256"]
            print(f"Exported {path.as_posix()} ({len(data)} bytes)", flush=True)
        (destination / "manifest.json").write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding="utf-8")
        conflicts = [item["file"] for item in snapshot["sources"] if not item["editorMatches"]]
        print(json.dumps({"destination": str(destination), "scripts": len(snapshot["sources"]), "editorConflicts": conflicts}))
    finally:
        client.close()


if __name__ == "__main__":
    main()
