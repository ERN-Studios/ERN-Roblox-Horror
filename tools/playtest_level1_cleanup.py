"""Complete a fast Studio Level 1 round and verify generated-world cleanup."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


ENTER_QUEUE = r'''
local H=game:GetService("HttpService")
local player=game.Players:GetPlayers()[1]
local zone=workspace:FindFirstChild("LaunchZone1", true)
local root=player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if not (player and zone and root) then return H:JSONEncode({ok=false}) end
player:SetAttribute("DevFastQueue", true)
player.Character:PivotTo(zone.CFrame * CFrame.new(0, 3, 0))
return H:JSONEncode({ok=true, zone=zone:GetFullName()})
'''

CONFIGURE_QUEUE = r'''
game.ReplicatedStorage.Remotes.ConfigureQueue:FireServer(1, 1, "public")
return "configured"
'''

STATE = r'''
local H=game:GetService("HttpService")
return H:JSONEncode({
    active=workspace:GetAttribute("RoundActive") == true,
    generated=workspace:GetAttribute("WorldGenerated") == true,
    inRound=game.Players:GetPlayers()[1] and game.Players:GetPlayers()[1]:GetAttribute("InRound") == true,
})
'''

WIN = r'''
workspace:SetAttribute("PuzzleWon", true)
return "win forced"
'''

CLEAN_AUDIT = r'''
local H=game:GetService("HttpService")
local leftovers={}
for _,name in ipairs({"PuzzleItems","Decor","PitZones","Maze","Elevator","ElevatorSpawn","MazeStart","EntityStart"}) do
    if workspace:FindFirstChild(name) then table.insert(leftovers,name) end
end
local player=game.Players:GetPlayers()[1]
return H:JSONEncode({
    leftovers=leftovers,
    generated=workspace:GetAttribute("WorldGenerated"),
    generateWorld=workspace:GetAttribute("GenerateWorld"),
    inRound=player and player:GetAttribute("InRound"),
    lobby=workspace:FindFirstChild("ServerLobby") ~= nil,
    generatorEnabled=not game.ServerScriptService.MazeGenerator.Disabled,
    entityAIEnabled=not game.ServerScriptService.EntityAI.Disabled,
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
        time.sleep(8)
        print("ENTER", client.call("execute_luau", {"datamodel_type": "Server", "code": ENTER_QUEUE}))
        time.sleep(2)
        print("CONFIG", client.call("execute_luau", {"datamodel_type": "Client", "code": CONFIGURE_QUEUE}))
        deadline = time.monotonic() + 100
        state = {}
        while time.monotonic() < deadline:
            time.sleep(2)
            raw = client.call("execute_luau", {"datamodel_type": "Server", "code": STATE})
            state = json.loads(raw)
            if state.get("active"):
                break
        print("ROUND", json.dumps(state, separators=(",", ":")))
        if not state.get("active"):
            raise RuntimeError("Level 1 never became active")
        print("WIN", client.call("execute_luau", {"datamodel_type": "Server", "code": WIN}))
        time.sleep(10)
        print("CLEAN", client.call("execute_luau", {"datamodel_type": "Server", "code": CLEAN_AUDIT}))
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
