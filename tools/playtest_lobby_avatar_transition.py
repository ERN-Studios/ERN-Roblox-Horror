"""Exercise the real lobby queue and verify personal-avatar -> StarterCharacter."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


SNAPSHOT = r'''
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local char = player.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
local accessories = 0
local meshIds = {}
if char then
    for _, item in ipairs(char:GetDescendants()) do
        if item:IsA("Accessory") then
            accessories += 1
        elseif item:IsA("MeshPart") and item.MeshId ~= "" then
            meshIds[#meshIds + 1] = item.MeshId
        end
    end
end
table.sort(meshIds)
return HttpService:JSONEncode({
    inRound = player:GetAttribute("InRound"),
    cameraMode = player.CameraMode.Name,
    minZoom = player.CameraMinZoomDistance,
    maxZoom = player.CameraMaxZoomDistance,
    character = char and char.Name or nil,
    rigType = hum and hum.RigType.Name or nil,
    jumpPower = hum and hum.JumpPower or nil,
    accessoryCount = accessories,
    meshIds = meshIds,
    hasStarterMarker = char and char:FindFirstChild("GameCharacterMarker", true) ~= nil or false,
    position = char and char:GetPivot().Position or nil,
})
'''

ENTER_QUEUE = r'''
local player = game:GetService("Players"):GetPlayers()[1]
local zone = workspace:FindFirstChild("LaunchZone1", true)
local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if not (player and zone and root) then return "missing player/zone/root" end
player:SetAttribute("DevFastQueue", true)
player.Character:PivotTo(zone.CFrame * CFrame.new(0, 3, 0))
return zone:GetFullName()
'''

CONFIGURE = r'''
game:GetService("ReplicatedStorage").Remotes.ConfigureQueue:FireServer(1, 1, "public")
return "configured"
'''


def decode(value: object) -> dict:
    if not isinstance(value, str):
        return {}
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return {}


def main() -> int:
    client = StudioMcpClient(find_mcp_batch())
    started = False
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "Backrooms: No Way Out", 20)
        print("START", client.call("start_stop_play", {"is_start": True}))
        started = True
        time.sleep(8)
        lobby_raw = client.call("execute_luau", {
            "datamodel_type": "Client", "code": SNAPSHOT,
        })
        print("LOBBY", lobby_raw)
        lobby = decode(lobby_raw)

        print("ENTER", client.call("execute_luau", {
            "datamodel_type": "Server", "code": ENTER_QUEUE,
        }))
        time.sleep(1.5)
        print("CONFIGURE", client.call("execute_luau", {
            "datamodel_type": "Client", "code": CONFIGURE,
        }))

        round_snapshot = {}
        deadline = time.monotonic() + 55
        while time.monotonic() < deadline:
            time.sleep(2)
            raw = client.call("execute_luau", {
                "datamodel_type": "Client", "code": SNAPSHOT,
            })
            round_snapshot = decode(raw)
            if round_snapshot.get("inRound") is True:
                print("ROUND", raw)
                break
        else:
            print("ROUND_TIMEOUT", round_snapshot)

        same_meshes = lobby.get("meshIds") == round_snapshot.get("meshIds")
        print("RESULT", json.dumps({
            "lobbyPersonalAvatar": lobby.get("inRound") is False
                and lobby.get("cameraMode") == "Classic",
            "roundGameplayAvatar": round_snapshot.get("inRound") is True
                and round_snapshot.get("cameraMode") == "LockFirstPerson",
            "characterAppearanceChanged": not same_meshes,
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
