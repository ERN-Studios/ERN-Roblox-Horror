"""Run a bounded Roblox Studio Level 1 smoke test and always return to Edit mode."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


HEALTH_CODE = r'''
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local entity = workspace:FindFirstChild("Entity")
local elevator = workspace:FindFirstChild("Elevator")
local textureIds = {}
local textureCount = 0
if elevator then
    for _, item in ipairs(elevator:GetDescendants()) do
        if item:IsA("Texture") then
            textureCount += 1
            textureIds[item.Texture] = (textureIds[item.Texture] or 0) + 1
        end
    end
end
local tracks = {}
if entity then
    local humanoid = entity:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            table.insert(tracks, track.Name)
        end
    end
end
return HttpService:JSONEncode({
    entityExists = entity ~= nil,
    entityState = entity and entity:GetAttribute("EntityState") or nil,
    fogStart = Lighting.FogStart,
    fogEnd = Lighting.FogEnd,
    playingTracks = tracks,
    elevatorExists = elevator ~= nil,
    elevatorTextureCount = textureCount,
    elevatorTextureInstances = textureIds,
})
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

        deadline = time.monotonic() + 25
        state = ""
        while time.monotonic() < deadline:
            time.sleep(2)
            state = client.call("get_studio_state")
            if "Server" in state:
                break
        print("STATE", state)

        # Allow maze generation, elevator construction, and the entity controller to boot.
        time.sleep(25)
        print("HEALTH", client.call("execute_luau", {
            "datamodel_type": "Server",
            "code": HEALTH_CODE,
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
