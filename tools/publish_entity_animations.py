"""Create and publish Roblox KeyframeSequences baked from Blender actions."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import (  # noqa: E402
    StudioMcpClient,
    find_mcp_batch,
    select_studio,
)


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets" / "animations" / "entity" / "keyframes"
ACTION_FILES = (
    "walk.json",
    "run_chase.json",
    "watch.json",
    "yell_howl.json",
    "yell_fromrun.json",
    "lunge.json",
    "lunge_fromrun.json",
)
CREATOR_ID = 1039373905

PARENTS = {
    "Hips": None,
    "LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg",
    "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot",
    "RightUpLeg": "Hips", "RightLeg": "RightUpLeg",
    "RightFoot": "RightLeg", "RightToeBase": "RightFoot",
    "Spine02": "Hips", "Spine01": "Spine02", "Spine": "Spine01",
    "LeftShoulder": "Spine", "LeftArm": "LeftShoulder",
    "LeftForeArm": "LeftArm", "LeftHand": "LeftForeArm",
    "RightShoulder": "Spine", "RightArm": "RightShoulder",
    "RightForeArm": "RightArm", "RightHand": "RightForeArm",
    "neck": "Spine", "Head": "neck",
}


def luau_table(mapping: dict[str, str | None]) -> str:
    items = []
    for key, value in mapping.items():
        rendered = "nil" if value is None else json.dumps(value)
        items.append(f"[{json.dumps(key)}]={rendered}")
    return "{" + ",".join(items) + "}"


def publish_code(payload: str) -> str:
    return f'''local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local AssetService = game:GetService("AssetService")
local data = HttpService:JSONDecode([=[{payload}]=])
local parents = {luau_table(PARENTS)}
local folder = ServerStorage:FindFirstChild("MongoTVEntityAnimations") or Instance.new("Folder")
folder.Name = "MongoTVEntityAnimations"
folder.Parent = ServerStorage
local sequenceName = "MongoTV_Entity_" .. data.name
local existing = folder:FindFirstChild(sequenceName)
if existing and existing:GetAttribute("PublishedAssetId") then
    return HttpService:JSONEncode({{name=data.name,id=existing:GetAttribute("PublishedAssetId"),reused=true}})
end
if existing then existing:Destroy() end
local sequence = Instance.new("KeyframeSequence")
sequence.Name = sequenceName
sequence.Loop = data.looped
sequence.Priority = Enum.AnimationPriority[data.priority]
for _, frameData in ipairs(data.frames) do
    local keyframe = Instance.new("Keyframe")
    keyframe.Time = frameData[1]
    local poses = {{}}
    for _, values in ipairs(frameData[2]) do
        local pose = Instance.new("Pose")
        pose.Name = values[1]
        pose.CFrame = CFrame.new(values[2], values[3], values[4], values[5], values[6], values[7], values[8])
        pose.Weight = 1
        pose.EasingStyle = Enum.PoseEasingStyle.Linear
        pose.EasingDirection = Enum.PoseEasingDirection.InOut
        poses[pose.Name] = pose
    end
    for name, pose in pairs(poses) do
        local parentName = parents[name]
        pose.Parent = parentName and poses[parentName] or keyframe
    end
    keyframe.Parent = sequence
end
sequence.Parent = folder
local ok, status, idOrError = pcall(function()
    return AssetService:CreateAssetAsync(sequence, Enum.AssetType.Animation, {{
        Name = "MongoTV Entity " .. data.name .. " v1",
        Description = "Level 1 entity animation exported from Blender",
        CreatorId = {CREATOR_ID},
        CreatorType = Enum.AssetCreatorType.Group,
    }})
end)
if not ok then
    return HttpService:JSONEncode({{name=data.name,error=tostring(status),stage="call"}})
end
if status ~= Enum.CreateAssetResult.Success then
    return HttpService:JSONEncode({{name=data.name,error=tostring(idOrError),status=tostring(status),stage="upload"}})
end
sequence:SetAttribute("PublishedAssetId", tostring(idOrError))
local animation = Instance.new("Animation")
animation.Name = data.name
animation.AnimationId = "rbxassetid://" .. tostring(idOrError)
animation.Parent = folder
return HttpService:JSONEncode({{name=data.name,id=tostring(idOrError),reused=false}})'''


def main() -> int:
    client = StudioMcpClient(find_mcp_batch())
    results: dict[str, object] = {}
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "Backrooms: No Way Out", 20)
        for filename in ACTION_FILES:
            source = SOURCE_DIR / filename
            response = client.call(
                "execute_luau",
                {
                    "datamodel_type": "Edit",
                    "code": publish_code(source.read_text(encoding="utf-8")),
                },
            )
            parsed = json.loads(response)
            results[str(parsed.get("name", filename))] = parsed
            print(json.dumps(parsed, ensure_ascii=False))
    finally:
        client.close()
    (SOURCE_DIR.parent / "published-assets.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return 0 if all(isinstance(v, dict) and v.get("id") for v in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
