"""Capture the same nearby Level 1 prop with the flashlight off and on."""

from __future__ import annotations

import base64
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts"

SETUP = r'''
require(game.ServerScriptService.Level2Generator).Cleanup()
workspace:SetAttribute("GenerateWorld", true)
return "Level 1 requested"
'''

STAGE_CAMERA = r'''
local H = game:GetService("HttpService")
local camera = workspace.CurrentCamera
local decor = workspace:FindFirstChild("Decor")
local target
if decor then
    for _, item in ipairs(decor:GetDescendants()) do
        if item:IsA("BasePart") and item:FindFirstChild("PropSurface") then
            target = item
            break
        end
    end
end
if not (camera and target) then
    return H:JSONEncode({ok=false})
end
camera.CameraType = Enum.CameraType.Scriptable
local size = math.max(target.Size.X, target.Size.Y, target.Size.Z)
local targetPosition = target.Position
local eye = targetPosition + Vector3.new(0, math.max(0.4, target.Size.Y * 0.15), math.max(3.2, size * 1.35))
camera.CFrame = CFrame.lookAt(eye, targetPosition)
return H:JSONEncode({ok=true, target=target:GetFullName(), distance=(eye-targetPosition).Magnitude})
'''

STAGE_PLAYER = r'''
local player=game:GetService("Players"):GetPlayers()[1]
local decor=workspace:FindFirstChild("Decor")
local target
if decor then
    for _,item in ipairs(decor:GetDescendants()) do
        if item:IsA("BasePart") and item:FindFirstChild("PropSurface") then target=item break end
    end
end
local char=player and player.Character
if not (target and char) then return "missing target" end
local size=math.max(target.Size.X,target.Size.Y,target.Size.Z)
local eye=target.Position+Vector3.new(0,math.max(.4,target.Size.Y*.15),math.max(3.2,size*1.35))
char:PivotTo(CFrame.lookAt(eye-Vector3.new(0,1.5,0),target.Position))
return target:GetFullName()
'''

LIGHT_STATE = r'''
local H=game:GetService("HttpService")
local mount=workspace:FindFirstChild("FlashlightMount")
local core=mount and mount:FindFirstChild("Core") or mount and mount:FindFirstChildOfClass("SpotLight")
local point=mount and mount:FindFirstChildOfClass("PointLight")
local highlight=workspace:FindFirstChild("FlashlightNearField")
return H:JSONEncode({enabled=core and core.Enabled or false,
    brightness=core and core.Brightness or 0, range=core and core.Range or 0,
    hasPointLight=point ~= nil,
    highlightEnabled=highlight and highlight.Enabled or false,
    highlightAdornee=highlight and highlight.Adornee and highlight.Adornee:GetFullName() or nil})
'''

SERVER_LIGHT_STATE = r'''
local H=game:GetService("HttpService")
local player=game:GetService("Players"):GetPlayers()[1]
local mount=player and workspace:FindFirstChild("ReplicatedFlashlight_"..player.UserId)
local head=player and player.Character and player.Character:FindFirstChild("Head")
local decor=workspace:FindFirstChild("Decor")
local target
if decor then for _,item in ipairs(decor:GetDescendants()) do
    if item:IsA("BasePart") and item:FindFirstChild("PropSurface") then target=item break end
end end
local core=mount and mount:FindFirstChild("Core")
local point=mount and mount:FindFirstChildOfClass("PointLight")
return H:JSONEncode({mount=mount and {mount.Position.X,mount.Position.Y,mount.Position.Z},
 head=head and {head.Position.X,head.Position.Y,head.Position.Z},
 target=target and {target.Position.X,target.Position.Y,target.Position.Z},
 mountToTarget=mount and target and (mount.Position-target.Position).Magnitude,
 headToTarget=head and target and (head.Position-target.Position).Magnitude,
 enabled=core and core.Enabled or false, hasPointLight=point ~= nil})
'''

def capture(client: StudioMcpClient, capture_id: str, path: Path) -> None:
    response = client._request(  # pylint: disable=protected-access
        "tools/call",
        {"name": "screen_capture", "arguments": {"capture_id": capture_id}},
    )
    for block in response.get("result", {}).get("content", []):
        if block.get("type") == "image":
            path.write_bytes(base64.b64decode(block["data"]))
            return
    raise RuntimeError("Studio screen_capture returned no image")


def main() -> int:
    OUTPUT.mkdir(exist_ok=True)
    client = StudioMcpClient(find_mcp_batch())
    started = False
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        print("START", client.call("start_stop_play", {"is_start": True}))
        started = True
        time.sleep(7)
        print("SETUP", client.call("execute_luau", {"datamodel_type": "Server", "code": SETUP}))
        time.sleep(25)
        print("PLAYER", client.call("execute_luau", {"datamodel_type": "Server", "code": STAGE_PLAYER}))
        time.sleep(0.5)
        print("STAGE", client.call("execute_luau", {"datamodel_type": "Client", "code": STAGE_CAMERA}))
        time.sleep(1)
        capture(client, "FlashlightOff", OUTPUT / "flashlight_off.jpg")
        print("INPUT", client.call("user_keyboard_input", {
            "datamodel_type": "Client",
            "actions": [{"action": "keyPress", "key_code": "F"}],
        }))
        time.sleep(0.7)
        print("LIGHT", client.call("execute_luau", {"datamodel_type": "Client", "code": LIGHT_STATE}))
        print("SERVER_LIGHT", client.call("execute_luau", {"datamodel_type": "Server", "code": SERVER_LIGHT_STATE}))
        capture(client, "FlashlightOn", OUTPUT / "flashlight_on.jpg")
        print("CAPTURED", OUTPUT / "flashlight_off.jpg", OUTPUT / "flashlight_on.jpg")
    finally:
        if started:
            try:
                print("STOP", client.call("start_stop_play", {"is_start": False}))
            except Exception as error:  # noqa: BLE001
                print("STOP_ERROR", error)
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
