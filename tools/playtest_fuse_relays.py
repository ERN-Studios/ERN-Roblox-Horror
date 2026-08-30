"""Run a bounded interaction test for Level 1 fuse relays."""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.stdout.reconfigure(line_buffering=True)

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


SETUP = r'''
local generator = require(game.ServerScriptService.Level2Generator)
generator.Cleanup()
workspace:SetAttribute("GenerateWorld", true)
return "Level 1 requested"
'''

START_AND_POSITION = r'''
local HttpService = game:GetService("HttpService")
local player = game:GetService("Players"):GetPlayers()[1]
if player then player:SetAttribute("InRound", true) end
workspace:SetAttribute("RoundActive", true)
workspace:SetAttribute("EntityPaused", true)
task.wait(6)
local items = workspace:FindFirstChild("PuzzleItems")
local relay = items and items:FindFirstChild("FuseRelay")
local body = relay and relay:FindFirstChild("RelayBody")
local prompt = body and body:FindFirstChildOfClass("ProximityPrompt")
if not (player and player.Character and relay and body and prompt) then
    return HttpService:JSONEncode({ok=false, reason="missing player or relay"})
end
local root = player.Character:FindFirstChild("HumanoidRootPart")
if not root then
    return HttpService:JSONEncode({ok=false, reason="missing root"})
end
root.CFrame = CFrame.lookAt(
    body.Position + body.CFrame.LookVector * 5 + Vector3.new(0, -0.5, 0),
    body.Position
)
return HttpService:JSONEncode({
    ok=true,
    relayCount=#items:GetChildren(),
    hold=prompt.HoldDuration,
    distance=(root.Position-body.Position).Magnitude,
})
'''

AUDIT = r'''
local HttpService = game:GetService("HttpService")
local player = game:GetService("Players"):GetPlayers()[1]
local items = workspace:FindFirstChild("PuzzleItems")
local total, active, empty, loose = 0, 0, 0, 0
local frontPrompts, weldedControls = 0, 0
for _, child in ipairs(items and items:GetChildren() or {}) do
    if child.Name == "FuseRelay" then
        total += 1
        if child:GetAttribute("ContainsFuse") == true then active += 1 else empty += 1 end
        local door = child:FindFirstChild("RelayDoor")
        local point = door and door:FindFirstChild("InteractionPoint")
        local prompt = point and point:FindFirstChildOfClass("ProximityPrompt")
        if prompt and prompt.Parent:IsA("Attachment") and math.abs(prompt.HoldDuration - 1.8) < .01 then
            frontPrompts += 1
        end
        for _, name in ipairs({"RelayIndicator", "ReleaseHandle", "RelayLabel"}) do
            local control = child:FindFirstChild(name)
            local weld = control and control:FindFirstChildOfClass("WeldConstraint")
            if control and not control.Anchored and weld and weld.Part0 == door and weld.Part1 == control then
                weldedControls += 1
            end
        end
    elseif child.Name == "Fuse" then
        loose += 1
    end
end
local noise = workspace:GetAttribute("LastRelayExtraction")
return HttpService:JSONEncode({
    total=total,
    active=active,
    empty=empty,
    loose=loose,
    carried=player and player:GetAttribute("CarriedFuses") or nil,
    noise=typeof(noise) == "Vector3",
    frontPrompts=frontPrompts,
    weldedControls=weldedControls,
})
'''


def main() -> int:
    manual_seconds = 45 if "--manual" in sys.argv[1:] else 1
    client = StudioMcpClient(find_mcp_batch())
    started = False
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        print("START", client.call("start_stop_play", {"is_start": True}))
        started = True
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            time.sleep(2)
            state = client.call("get_studio_state")
            if "Server" in state:
                break
        time.sleep(4)
        print("SETUP", client.call("execute_luau", {
            "datamodel_type": "Server", "code": SETUP,
        }))
        time.sleep(27)
        print("POSITION", client.call("execute_luau", {
            "datamodel_type": "Server", "code": START_AND_POSITION,
        }))
        print(f"MANUAL_WINDOW Hold E in Studio within {manual_seconds} seconds")
        time.sleep(manual_seconds)
        time.sleep(1)
        print("AUDIT", client.call("execute_luau", {
            "datamodel_type": "Server", "code": AUDIT,
        }))
        print("CONSOLE", client.call("get_console_output"))
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
