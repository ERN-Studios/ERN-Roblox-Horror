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
V10 = "--v10" in sys.argv[1:]
V9_ACTIONS = "--v9-actions" in sys.argv[1:]
V8_ACTIONS = "--v8-actions" in sys.argv[1:]
V7_ACTIONS = "--v7-actions" in sys.argv[1:]
V6_ACTIONS = "--v6-actions" in sys.argv[1:]
V6_WALK = "--v6-walk" in sys.argv[1:]
V5 = "--v5" in sys.argv[1:]
V3 = "--v3" in sys.argv[1:] or V5 or V6_WALK or V6_ACTIONS or V7_ACTIONS or V8_ACTIONS or V9_ACTIONS or V10
V2 = "--v2" in sys.argv[1:] and not V3
FORCE = "--force" in sys.argv[1:]
SOURCE_DIR = ROOT / "assets" / "animations" / "entity" / (
    "keyframes_v3" if V3 else "keyframes_v2" if V2 else "keyframes"
)
ACTION_FILES = ((
    "walk_restrained.json",
    "run_chase_corrected.json",
    "watch.json",
    "yell_howl.json",
    "yell_fromrun.json",
    "lunge.json",
    "lunge_fromrun.json",
    "kill_hunched_groundpunch.json",
) if V10 else ("kill_hunched_groundpunch.json",) if V9_ACTIONS
    else ("run_chase_corrected.json", "kill_hunched_groundpunch.json")
    if (V6_ACTIONS or V7_ACTIONS or V8_ACTIONS) else ("walk_restrained.json",)) if (V10 or V6_ACTIONS or V7_ACTIONS or V8_ACTIONS or V9_ACTIONS or V6_WALK) else (
    "walk.json",
    "run_chase.json",
    "watch.json",
    "yell_howl.json",
    "yell_fromrun.json",
    "lunge.json",
    "lunge_fromrun.json",
) + (("kill_groundpinpunch.json",) if V3 else ("kill_visorcrush.json",) if V2 else ())
VERSION_LABEL = "v10full" if V10 else "v9actions" if V9_ACTIONS else "v8actions" if V8_ACTIONS else "v7actions" if V7_ACTIONS else "v6actions" if V6_ACTIONS else "v6walk" if V6_WALK else "v5" if V5 else "v4" if V3 and FORCE else "v3" if V3 else "v2" if V2 else "v1"
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
for side in ("Left", "Right"):
    hand = side + "Hand"
    PARENTS[side + "HandThumb1"] = hand
    PARENTS[side + "HandThumb2"] = side + "HandThumb1"
    for digit in ("Index", "Middle", "Ring", "Pinky"):
        first = side + "Hand" + digit + "1"
        PARENTS[first] = hand
        PARENTS[side + "Hand" + digit + "2"] = first
        PARENTS[side + "Hand" + digit + "3"] = side + "Hand" + digit + "2"


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
local sequenceName = "MongoTV_Entity_" .. data.name .. "_{VERSION_LABEL}"
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
        Name = "MongoTV Entity " .. data.name .. " {VERSION_LABEL}",
        Description = "Level 1 entity animation retargeted from Blender to the live Studio rig",
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
        select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
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
    manifest_name = (
        "published-assets-v10-full.json" if V10
        else "published-assets-v9-actions.json" if V9_ACTIONS
        else "published-assets-v8-actions.json" if V8_ACTIONS
        else "published-assets-v7-actions.json" if V7_ACTIONS
        else "published-assets-v6-actions.json" if V6_ACTIONS
        else "published-assets-v6-walk.json" if V6_WALK
        else "published-assets-v5.json" if V5
        else "published-assets-v4.json" if V3 and FORCE
        else "published-assets-v3.json" if V3
        else "published-assets-v2.json" if V2
        else "published-assets.json"
    )
    (SOURCE_DIR.parent / manifest_name).write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return 0 if all(isinstance(v, dict) and v.get("id") for v in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
