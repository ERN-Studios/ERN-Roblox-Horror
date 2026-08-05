"""Bounded Level 2 entity/DevCheats regression test; always returns to Edit."""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


BUILD = r'''
local H = game:GetService("HttpService")
local generator = require(game.ServerScriptService.Level2Generator)
local player = game:GetService("Players"):GetPlayers()[1]
if player then player:SetAttribute("InRound", true) end
local world = generator.Build()
return H:JSONEncode({ok=world ~= nil, selected=workspace:GetAttribute("SelectedLevel")})
'''

SERVER_AUDIT = r'''
local H = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local tagged = CollectionService:GetTagged("Level2HostileEntity")
local entities = {}
for _, entity in ipairs(tagged) do
    if entity:IsDescendantOf(workspace) then
        local visible, parts = 0, 0
        for _, item in ipairs(entity:GetDescendants()) do
            if item:IsA("BasePart") then
                parts += 1
                if item.Transparency < .95 then visible += 1 end
            end
        end
        table.insert(entities, {
            name=entity.Name,
            visibleParts=visible,
            parts=parts,
            managed=entity:GetAttribute("ControllerManaged") == true,
            motion=entity:GetAttribute("MotionState"),
        })
    end
end
return H:JSONEncode({
    count=#entities,
    entities=entities,
    access=require(game.ReplicatedStorage.DevAccess).IsAllowed(game.Players:GetPlayers()[1]),
})
'''

CLIENT_AUDIT = r'''
local H = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
task.wait(1)
local highlighted, missing = 0, {}
for _, entity in ipairs(CollectionService:GetTagged("Level2HostileEntity")) do
    if entity:IsDescendantOf(workspace) then
        local h = entity:FindFirstChild("DevESP")
        if h and h:IsA("Highlight") and h.Enabled then highlighted += 1
        else table.insert(missing, entity.Name) end
    end
end
local valveHighlights = 0
for _, item in ipairs(workspace.CurrentCamera:GetChildren()) do
    if item.Name == "ValveVisionHighlight" and item:IsA("Highlight") and item.Enabled then
        valveHighlights += 1
    end
end
return H:JSONEncode({
    devEsp=game.Players.LocalPlayer:GetAttribute("DevEspEnabled"),
    highlighted=highlighted,
    missing=missing,
    valveHighlights=valveHighlights,
})
'''

PAUSE_CLIENT = r'''
game.ReplicatedStorage.Remotes.DevControl:FireServer("pauseEntity", true)
return "pause sent"
'''

PAUSE_AUDIT = r'''
local H = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local before = {}
for _, entity in ipairs(CollectionService:GetTagged("Level2HostileEntity")) do
    if entity:IsDescendantOf(workspace) then before[entity] = entity:GetPivot().Position end
end
task.wait(1)
local maxMove, idle = 0, 0
for _, entity in ipairs(CollectionService:GetTagged("Level2HostileEntity")) do
    if entity:IsDescendantOf(workspace) then
        local startPosition = before[entity]
        if startPosition then
            maxMove = math.max(maxMove, (entity:GetPivot().Position-startPosition).Magnitude)
        end
        if entity:GetAttribute("MotionState") == "Idle" then idle += 1 end
    end
end
return H:JSONEncode({paused=workspace:GetAttribute("EntityPaused"), maxMove=maxMove, idle=idle})
'''

RESUME_CLIENT = r'''
game.ReplicatedStorage.Remotes.DevControl:FireServer("pauseEntity", false)
return "resume sent"
'''


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
        print("BUILD", client.call("execute_luau", {"datamodel_type": "Server", "code": BUILD}))
        time.sleep(4)
        print("SERVER", client.call("execute_luau", {"datamodel_type": "Server", "code": SERVER_AUDIT}))
        print("CLIENT", client.call("execute_luau", {"datamodel_type": "Client", "code": CLIENT_AUDIT}))
        print("PAUSE", client.call("execute_luau", {"datamodel_type": "Client", "code": PAUSE_CLIENT}))
        time.sleep(1.2)
        print("PAUSE_AUDIT", client.call("execute_luau", {"datamodel_type": "Server", "code": PAUSE_AUDIT}))
        print("RESUME", client.call("execute_luau", {"datamodel_type": "Client", "code": RESUME_CLIENT}))
        time.sleep(.5)
        print("CONSOLE", client.call("get_console_output"))
    finally:
        if started:
            try:
                print("STOP", client.call("start_stop_play", {"is_start": False}))
            except Exception as error:  # noqa: BLE001
                print("STOP_ERROR", error, file=sys.stderr)
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
