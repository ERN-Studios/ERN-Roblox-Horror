"""Exercise the Level 1 cinematic kill in Studio and return to Edit mode."""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


SETUP = r'''
require(game.ServerScriptService.Level2Generator).Cleanup()
workspace:SetAttribute("GenerateWorld", true)
return "Level 1 requested"
'''

KILL_TEST = r'''
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players:GetPlayers()[1]
local entity = workspace:FindFirstChild("Entity")
if not (player and entity) then
    return HttpService:JSONEncode({ok=false, reason="missing player or entity"})
end
if not player.Character then player:LoadCharacter() end
local char = player.Character or player.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart", 10)
local hum = char:FindFirstChildOfClass("Humanoid")
local entityRoot = entity:FindFirstChild("HumanoidRootPart")
local indexBone = entity:FindFirstChild("RightHandIndex2", true)
local rightHand = entity:FindFirstChild("RightHand", true)
local leftHand = entity:FindFirstChild("LeftHand", true)
if not (root and hum and entityRoot and indexBone and rightHand and leftHand) then
    return HttpService:JSONEncode({ok=false, reason="missing runtime parts"})
end

workspace:SetAttribute("EntityPaused", true)
hum.Health = hum.MaxHealth
root.CFrame = entityRoot.CFrame * CFrame.new(0, 0, -0.4)
root.AssemblyLinearVelocity = Vector3.zero
local entityRootStart = entityRoot.Position

local beganAt
local deadline = os.clock() + 4
while os.clock() < deadline do
    RunService.Heartbeat:Wait()
    if workspace:GetAttribute("EntityKillActive") then
        beganAt = os.clock()
        break
    end
end
if not beganAt then
    return HttpService:JSONEncode({ok=false, reason="touch did not start kill"})
end

task.wait(0.15) -- allow PlayKill to switch from locomotion to the action track

local trackName = ""
local animator = entity:FindFirstChildOfClass("Humanoid")
    and entity:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
if animator then
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if string.find(track.Name, "Kill", 1, true) then trackName = track.Name end
    end
end

local startFinger = indexBone.Transform
local rightStartForward = (rightHand.WorldPosition - entityRoot.Position):Dot(entityRoot.CFrame.LookVector)
local leftStartForward = (leftHand.WorldPosition - entityRoot.Position):Dot(entityRoot.CFrame.LookVector)
task.wait(0.75)
local rightReachForward = (rightHand.WorldPosition - entityRoot.Position):Dot(entityRoot.CFrame.LookVector)
local leftReachForward = (leftHand.WorldPosition - entityRoot.Position):Dot(entityRoot.CFrame.LookVector)
task.wait(1.65)
local midFingerDelta = (startFinger.Position - indexBone.Transform.Position).Magnitude
local fingerRotationDegrees = math.deg(math.acos(math.clamp(
    startFinger.LookVector:Dot(indexBone.Transform.LookVector), -1, 1)))
local lyingDot = math.abs(root.CFrame.UpVector:Dot(Vector3.yAxis))
local laidRootY = root.Position.Y
local laidVsEntityRootY = laidRootY - entityRoot.Position.Y
local healthBeforePunch = hum.Health
local entityRootMid = entityRoot.Position
task.wait(2.1)
local healthAfterPunch = hum.Health
task.wait(0.8)
local entityRootEnd = entityRoot.Position

return HttpService:JSONEncode({
    ok=true,
    trackName=trackName,
    fingerPositionDelta=midFingerDelta,
    fingerRotationDegrees=fingerRotationDegrees,
    rightReachForward=rightReachForward,
    leftReachForward=leftReachForward,
    rightStartForward=rightStartForward,
    leftStartForward=leftStartForward,
    rightReachDelta=rightReachForward-rightStartForward,
    leftReachDelta=leftReachForward-leftStartForward,
    lyingUpDot=lyingDot,
    laidRootY=laidRootY,
    laidVsEntityRootY=laidVsEntityRootY,
    healthBeforePunch=healthBeforePunch,
    healthAfterPunch=healthAfterPunch,
    killActiveAfter=workspace:GetAttribute("EntityKillActive"),
    entityRootMidDelta=(entityRootMid-entityRootStart).Magnitude,
    entityRootEndDelta=(entityRootEnd-entityRootStart).Magnitude,
})
'''


def main() -> int:
    client = StudioMcpClient(find_mcp_batch())
    started = False
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        print("START", client.call("start_stop_play", {"is_start": True}))
        started = True
        time.sleep(7)
        print("SETUP", client.call("execute_luau", {
            "datamodel_type": "Server", "code": SETUP,
        }))
        time.sleep(25)
        print("KILL", client.call("execute_luau", {
            "datamodel_type": "Server", "code": KILL_TEST,
        }))
        print("CONSOLE_BEGIN")
        print(client.call("get_console_output"))
        print("CONSOLE_END")
    finally:
        if started:
            try:
                print("STOP", client.call("start_stop_play", {"is_start": False}))
            except Exception as error:  # noqa: BLE001
                print(f"STOP_ERROR {error}", file=sys.stderr)
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
