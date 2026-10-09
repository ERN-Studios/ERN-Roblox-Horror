"""Capture the corrected chase and kill poses from the live Studio rig."""

from __future__ import annotations

import base64
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts"
SETUP = '''require(game.ServerScriptService.Level2Generator).Cleanup()
workspace:SetAttribute("GenerateWorld",true)
return "Level 1 requested"'''

START_RUN = '''local entity=workspace:FindFirstChild("Entity")
local root=entity and entity:FindFirstChild("HumanoidRootPart")
if not root then return "missing" end
workspace:SetAttribute("EntityPaused",true)
workspace:SetAttribute("EntityState","CHASE")
workspace:SetAttribute("CaptureRun",true)
task.spawn(function()
 while workspace:GetAttribute("CaptureRun") and root.Parent do
  root.AssemblyLinearVelocity=root.CFrame.LookVector*15
  task.wait()
 end
 root.AssemblyLinearVelocity=Vector3.zero
end)
return "run started"'''

STAGE_RUN_CAMERA = '''local camera=workspace.CurrentCamera
local entity=workspace:FindFirstChild("Entity")
local root=entity and entity:FindFirstChild("HumanoidRootPart")
if not (camera and root) then return "missing" end
camera.CameraType=Enum.CameraType.Scriptable
local target=root.Position+Vector3.new(0,2,0)
camera.CFrame=CFrame.lookAt(target+root.CFrame.RightVector*16-root.CFrame.LookVector*8+Vector3.new(0,3,0),target)
return "camera staged"'''

TRIGGER_KILL = '''workspace:SetAttribute("CaptureRun",false)
workspace:SetAttribute("EntityPaused",true)
local player=game:GetService("Players"):GetPlayers()[1]
local entity=workspace:FindFirstChild("Entity")
local eroot=entity and entity:FindFirstChild("HumanoidRootPart")
local char=player and player.Character
local root=char and char:FindFirstChild("HumanoidRootPart")
local hum=char and char:FindFirstChildOfClass("Humanoid")
if not (root and hum and eroot) then return "missing" end
hum.Health=hum.MaxHealth
root.CFrame=eroot.CFrame*CFrame.new(0,0,-0.4)
root.AssemblyLinearVelocity=Vector3.zero
return "kill triggered"'''


def capture(client: StudioMcpClient, capture_id: str, path: Path) -> None:
    response = client._request(  # pylint: disable=protected-access
        "tools/call", {"name": "screen_capture", "arguments": {"capture_id": capture_id}})
    for block in response.get("result", {}).get("content", []):
        if block.get("type") == "image":
            path.write_bytes(base64.b64decode(block["data"]))
            return
    raise RuntimeError("screen_capture returned no image")


def main() -> int:
    OUTPUT.mkdir(exist_ok=True)
    client = StudioMcpClient(find_mcp_batch())
    started = False
    try:
        client.initialize(); time.sleep(3)
        select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        print(client.call("start_stop_play", {"is_start": True})); started = True
        time.sleep(7)
        print(client.call("execute_luau", {"datamodel_type": "Server", "code": SETUP}))
        time.sleep(25)
        print(client.call("execute_luau", {"datamodel_type": "Server", "code": START_RUN}))
        print(client.call("execute_luau", {"datamodel_type": "Client", "code": STAGE_RUN_CAMERA}))
        time.sleep(0.8)
        capture(client, "CorrectedRun", OUTPUT / "entity_run_corrected.jpg")
        print(client.call("execute_luau", {"datamodel_type": "Server", "code": TRIGGER_KILL}))
        time.sleep(2.65)
        capture(client, "KillHunch", OUTPUT / "entity_kill_hunch.jpg")
        time.sleep(0.6)
        capture(client, "KillSideWindup", OUTPUT / "entity_kill_sidewindup.jpg")
        time.sleep(0.4)
        capture(client, "KillWindup", OUTPUT / "entity_kill_windup.jpg")
        print("CAPTURED corrected run and kill poses")
    finally:
        if started:
            try:
                print(client.call("start_stop_play", {"is_start": False}))
            except Exception as error:  # noqa: BLE001
                print("STOP_ERROR", error)
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
