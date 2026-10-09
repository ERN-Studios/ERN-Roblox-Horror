"""Capture the Level 1 objective card and the inset-free ending overlay."""

from __future__ import annotations

import base64
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts"

SHOW_OBJECTIVES = r'''
local p=game:GetService("Players"):GetPlayers()[1]
p:SetAttribute("InRound",true)
workspace:SetAttribute("SelectedLevel",1)
workspace:SetAttribute("RoundActive",true)
game.ReplicatedStorage.Remotes.PuzzleStatus:FireClient(p,"begin",2,2)
return "shown"
'''

SHOW_ENDING = r'''
local p=game:GetService("Players"):GetPlayers()[1]
game.ReplicatedStorage.Remotes.RoundStatus:FireClient(p,"win",142,1,1)
return "shown"
'''


def capture(client: StudioMcpClient, capture_id: str, path: Path) -> None:
    response = client._request(  # pylint: disable=protected-access
        "tools/call", {"name": "screen_capture", "arguments": {"capture_id": capture_id}},
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
        time.sleep(8)
        print("OBJECTIVES", client.call("execute_luau", {"datamodel_type": "Server", "code": SHOW_OBJECTIVES}))
        time.sleep(1)
        capture(client, "Level1ObjectivesV2", OUTPUT / "level1_objectives_v2.jpg")
        print("ENDING", client.call("execute_luau", {"datamodel_type": "Server", "code": SHOW_ENDING}))
        time.sleep(1)
        capture(client, "RoundOverlayFullscreen", OUTPUT / "round_overlay_fullscreen.jpg")
        print("CAPTURED", OUTPUT / "level1_objectives_v2.jpg", OUTPUT / "round_overlay_fullscreen.jpg")
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
