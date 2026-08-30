"""Generate Level 1 and capture the new elevator from inside and outside."""

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

STAGE = r'''
local H = game:GetService("HttpService")
local camera = workspace.CurrentCamera
local elevator = workspace:FindFirstChild("Elevator")
local cabin = elevator and elevator:FindFirstChild("Cabin")
local doorL = elevator and elevator:FindFirstChild("DoorL")
local doorR = elevator and elevator:FindFirstChild("DoorR")
if not (camera and cabin and doorL and doorR) then
    return H:JSONEncode({ok=false})
end
local _, size = cabin:GetBoundingBox()
local cabinCenter = cabin:GetPivot().Position
local doorCenter = (doorL.Position + doorR.Position) * 0.5
local inward = Vector3.new(cabinCenter.X-doorCenter.X, 0, cabinCenter.Z-doorCenter.Z).Unit
local mode = __MODE__
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = mode == "inside" and 78 or 65
if mode == "inside" then
    local eye = cabinCenter + inward * math.min(size.X, size.Z) * 0.18 + Vector3.new(0, 5.4, 0)
    camera.CFrame = CFrame.lookAt(eye, doorCenter + Vector3.new(0, 4.7, 0))
else
    local eye = doorCenter - inward * 13 + Vector3.new(0, 5.2, 0)
    camera.CFrame = CFrame.lookAt(eye, doorCenter + Vector3.new(0, 4.8, 0))
end
return H:JSONEncode({ok=true, mode=mode, door={doorCenter.X,doorCenter.Y,doorCenter.Z},
    cabin={cabinCenter.X,cabinCenter.Y,cabinCenter.Z}, size={size.X,size.Y,size.Z}})
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
        for mode in ("inside", "outside"):
            code = STAGE.replace("__MODE__", f'"{mode}"')
            print(mode.upper(), client.call("execute_luau", {"datamodel_type": "Client", "code": code}))
            time.sleep(1.5)
            path = OUTPUT / f"elevator_90s_{mode}.jpg"
            capture(client, f"Elevator90s-{mode}", path)
            print("CAPTURED", path)
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
