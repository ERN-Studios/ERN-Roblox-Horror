"""Bounded whitelist/dev-phone/camera regression test; always returns to Edit."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


CLIENT_SNAPSHOT = r'''
local H = game:GetService("HttpService")
local player = game:GetService("Players").LocalPlayer
local store = player.PlayerGui:FindFirstChild("ZyntraStore")
local terminal = store and store:FindFirstChild("Terminal")
local devPage = terminal and terminal:FindFirstChild("Dev", true)
local controls = devPage and devPage:FindFirstChild("DevControls")
local openButton = store and store:FindFirstChild("ZyntraOpenButton")
local rows = {}
if controls then
    for _, row in ipairs(controls:GetChildren()) do
        if row:IsA("Frame") then
            local toggle = row:FindFirstChildWhichIsA("TextButton")
            rows[row.Name] = toggle and toggle.Text or "missing"
        end
    end
end
return H:JSONEncode({
    allowed=require(game.ReplicatedStorage.DevAccess).IsAllowed(player),
    rejectsUnknown=require(game.ReplicatedStorage.DevAccess).IsAllowed("DefinitelyNotADeveloper") == false,
    bridge=player.PlayerScripts:FindFirstChild("DevCheatCommand") ~= nil,
    devPage=devPage ~= nil,
    rows=rows,
    cameraMode=tostring(player.CameraMode),
    minZoom=player.CameraMinZoomDistance,
    maxZoom=player.CameraMaxZoomDistance,
    inRound=player:GetAttribute("InRound") == true,
    touch=game:GetService("UserInputService").TouchEnabled,
    openButtonVisible=openButton and openButton.Visible,
    openButtonText=openButton and openButton.Text,
})
'''

SET_ROUND = r'''
local player = game:GetService("Players"):GetPlayers()[1]
player:SetAttribute("InRound", true)
return player.Name
'''

KEY_C = r'''
local H = game:GetService("HttpService")
local player = game:GetService("Players").LocalPlayer
local event = player.PlayerScripts:FindFirstChild("DevCheatCommand")
assert(event and event:IsA("BindableEvent"), "DevCheatCommand missing")
event:Fire("thirdPerson")
task.wait(.4)
return H:JSONEncode({
    enabled=player:GetAttribute("DevCheatThirdPerson"),
    cameraMode=tostring(player.CameraMode),
    minZoom=player.CameraMinZoomDistance,
    maxZoom=player.CameraMaxZoomDistance,
})
'''

PHONE_TOGGLES = r'''
local H = game:GetService("HttpService")
local player = game:GetService("Players").LocalPlayer
local event = player.PlayerScripts:FindFirstChild("DevCheatCommand")
assert(event and event:IsA("BindableEvent"), "DevCheatCommand missing")
event:Fire("esp", false)
event:Fire("fastQueue", true)
event:Fire("pauseEntity", true)
event:Fire("immunePush", true)
event:Fire("unlimited", true)
event:Fire("noclip", true)
task.wait(.5)
local terminal = player.PlayerGui.ZyntraStore.Terminal
local devPage = terminal:FindFirstChild("Dev", true)
local controls = devPage and devPage:FindFirstChild("DevControls")
local rows = {}
if controls then
    for _, row in ipairs(controls:GetChildren()) do
        if row:IsA("Frame") then
            local toggle = row:FindFirstChildWhichIsA("TextButton")
            rows[row.Name] = toggle and toggle.Text or "missing"
        end
    end
end
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
return H:JSONEncode({
    esp=player:GetAttribute("DevCheatEsp"),
    queue=player:GetAttribute("DevCheatFastQueue"),
    paused=player:GetAttribute("DevCheatEntityPaused"),
    immune=player:GetAttribute("DevCheatPushImmune"),
    unlimited=player:GetAttribute("DevCheatUnlimited"),
    noclip=player:GetAttribute("DevCheatNoclip"),
    rootCollides=root and root.CanCollide,
    rows=rows,
})
'''

SERVER_TOGGLES = r'''
local H = game:GetService("HttpService")
local player = game:GetService("Players"):GetPlayers()[1]
return H:JSONEncode({
    queue=player:GetAttribute("DevFastQueue") == true,
    paused=workspace:GetAttribute("EntityPaused") == true,
    immune=player:GetAttribute("DevPushImmune") == true,
})
'''

RESET_PAUSE = r'''
workspace:SetAttribute("EntityPaused", false)
return "server reset"
'''

CLIENT_PAUSE_MIRROR = r'''
local H = game:GetService("HttpService")
local player = game:GetService("Players").LocalPlayer
local terminal = player.PlayerGui.ZyntraStore.Terminal
local row = terminal:FindFirstChild("pauseEntity", true)
local toggle = row and row:FindFirstChildWhichIsA("TextButton")
return H:JSONEncode({
    state=player:GetAttribute("DevCheatEntityPaused"),
    label=toggle and toggle.Text,
})
'''

KEY_J = r'''
local H = game:GetService("HttpService")
local player = game:GetService("Players").LocalPlayer
local event = player.PlayerScripts:FindFirstChild("DevPhoneCommand")
assert(event and event:IsA("BindableEvent"), "DevPhoneCommand missing")
event:Fire()
task.wait(.25)
local terminal = player.PlayerGui.ZyntraStore.Terminal
local devPage = terminal:FindFirstChild("Dev", true)
return H:JSONEncode({
    visible=terminal.Visible,
    modal=player:GetAttribute("DevPhoneOpen") == true,
    devVisible=devPage and devPage.Visible,
    mouseIcon=game:GetService("UserInputService").MouseIconEnabled,
    mouseBehavior=tostring(game:GetService("UserInputService").MouseBehavior),
})
'''

SET_ESCAPE = r'''
local player = game:GetService("Players"):GetPlayers()[1]
player:SetAttribute("Escaped", true)
return "escaped"
'''

CLEAR_ESCAPE = r'''
local player = game:GetService("Players"):GetPlayers()[1]
player:SetAttribute("Escaped", nil)
return "cleared"
'''

PHONE_STATE = r'''
local H = game:GetService("HttpService")
local player = game:GetService("Players").LocalPlayer
local store = player.PlayerGui.ZyntraStore
return H:JSONEncode({
    visible=store.Terminal.Visible,
    modal=player:GetAttribute("DevPhoneOpen") == true,
    openButtonVisible=store.ZyntraOpenButton.Visible,
})
'''

CLEANUP = r'''
local player = game:GetService("Players").LocalPlayer
local event = player.PlayerScripts:FindFirstChild("DevCheatCommand")
if event and event:IsA("BindableEvent") then
    event:Fire("esp", true)
    event:Fire("fastQueue", false)
    event:Fire("pauseEntity", false)
    event:Fire("immunePush", false)
    event:Fire("unlimited", false)
    event:Fire("noclip", false)
    event:Fire("thirdPerson", false)
end
player:SetAttribute("DevPhoneOpen", nil)
return "clean"
'''

CLEAR_ROUND = r'''
local player = game:GetService("Players"):GetPlayers()[1]
player:SetAttribute("InRound", false)
workspace:SetAttribute("EntityPaused", false)
return "lobby"
'''


def payload(result: object) -> object:
    if isinstance(result, str):
        try:
            decoded = json.loads(result)
            if isinstance(decoded, dict) and "result" in decoded:
                decoded = decoded["result"]
            if isinstance(decoded, str) and decoded.startswith("{"):
                return json.loads(decoded)
            return decoded
        except json.JSONDecodeError:
            return result
    if not isinstance(result, dict):
        return result
    content = result.get("content")
    if not isinstance(content, list) or not content:
        return result
    text = content[0].get("text") if isinstance(content[0], dict) else None
    if not isinstance(text, str):
        return result
    try:
        outer = json.loads(text)
        value = outer.get("result", outer) if isinstance(outer, dict) else outer
        return json.loads(value) if isinstance(value, str) and value.startswith("{") else value
    except json.JSONDecodeError:
        return text


def call(
    client: StudioMcpClient, studio_id: str, datamodel: str, code: str
) -> object:
    return payload(
        client.call(
            "execute_luau",
            {"studio_id": studio_id, "datamodel_type": datamodel, "code": code},
        )
    )


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    client = StudioMcpClient(find_mcp_batch())
    started = False
    studio_id: str | None = None
    try:
        client.initialize()
        time.sleep(2)
        studio = select_studio(client, "Backrooms: No Way Out", 20)
        studio_id = studio["id"]
        print(
            "START",
            client.call(
                "start_stop_play", {"studio_id": studio_id, "is_start": True}
            ),
        )
        started = True
        time.sleep(7)

        initial = call(client, studio_id, "Client", CLIENT_SNAPSHOT)
        print("INITIAL", initial)
        require(isinstance(initial, dict) and initial.get("allowed") is True, "test player is not whitelisted")
        require(initial.get("rejectsUnknown") is True, "unknown name unexpectedly has dev access")
        require(initial.get("bridge") is True and initial.get("devPage") is True, "dev phone did not initialize")
        require(len(initial.get("rows", {})) == 7, "dev phone must expose seven controls")
        require(initial.get("openButtonVisible") is True, "Equipment must be visible in the lobby")
        require(initial.get("openButtonText") == "ZYNTRA // EQUIPMENT", "lobby Equipment label is wrong")

        print("ROUND", call(client, studio_id, "Server", SET_ROUND))
        time.sleep(.7)

        level_ui = call(client, studio_id, "Client", PHONE_STATE)
        print("LEVEL_UI", level_ui)
        if initial.get("touch") is True:
            require(level_ui.get("openButtonVisible") is True, "dev mobile entry must remain visible in-level")
        else:
            require(level_ui.get("openButtonVisible") is False, "desktop Equipment button must be hidden in-level")

        camera = call(client, studio_id, "Client", KEY_C)
        print("KEY_C", camera)
        require(camera.get("enabled") is True, "C did not enable third person")
        require(
            "Classic" in camera.get("cameraMode", "")
            and camera.get("minZoom") == 6
            and camera.get("maxZoom") == 14,
            "third-person camera constraints are wrong",
        )

        toggles = call(client, studio_id, "Client", PHONE_TOGGLES)
        print("PHONE_TOGGLES", toggles)
        require(all(toggles.get(key) is value for key, value in {
            "esp": False,
            "queue": True,
            "paused": True,
            "immune": True,
            "unlimited": True,
            "noclip": True,
        }.items()), "phone state attributes did not synchronize")
        require(all(text.startswith("ON") for name, text in toggles.get("rows", {}).items() if name != "esp"), "phone ON labels did not refresh")
        require(toggles.get("rows", {}).get("esp", "").startswith("OFF"), "phone ESP label did not refresh")

        time.sleep(.4)
        server = call(client, studio_id, "Server", SERVER_TOGGLES)
        print("SERVER_TOGGLES", server)
        require(all(server.values()), "server-backed cheat states did not arrive")

        print("RESET_PAUSE", call(client, studio_id, "Server", RESET_PAUSE))
        time.sleep(.3)
        pause_mirror = call(client, studio_id, "Client", CLIENT_PAUSE_MIRROR)
        print("PAUSE_MIRROR", pause_mirror)
        require(
            pause_mirror.get("state") is False and pause_mirror.get("label", "").startswith("OFF"),
            "server pause reset did not reach the phone",
        )

        phone_open = call(client, studio_id, "Client", KEY_J)
        print("KEY_J_OPEN", phone_open)
        require(phone_open.get("visible") is True and phone_open.get("modal") is True, "J did not open the dev phone")
        require(phone_open.get("devVisible") is True and phone_open.get("mouseIcon") is True, "dev phone did not open as a usable modal")

        print("ESCAPE", call(client, studio_id, "Server", SET_ESCAPE))
        time.sleep(.3)
        phone_closed = call(client, studio_id, "Client", PHONE_STATE)
        print("AUTO_CLOSE", phone_closed)
        require(phone_closed.get("visible") is False and phone_closed.get("modal") is False, "escape did not close the dev phone")
        print("CLEAR_ESCAPE", call(client, studio_id, "Server", CLEAR_ESCAPE))

        phone_reopened = call(client, studio_id, "Client", KEY_J)
        print("KEY_J_REOPEN", phone_reopened)
        require(phone_reopened.get("visible") is True, "J did not reopen the dev phone")
        phone_closed_again = call(client, studio_id, "Client", KEY_J)
        print("KEY_J_CLOSE", phone_closed_again)
        require(phone_closed_again.get("visible") is False, "J did not close the dev phone")

        print("CLEANUP_CLIENT", call(client, studio_id, "Client", CLEANUP))
        print("CLEANUP_SERVER", call(client, studio_id, "Server", CLEAR_ROUND))
        time.sleep(.5)
        print("CONSOLE", client.call("get_console_output", {"studio_id": studio_id}))
    finally:
        if started and studio_id is not None:
            try:
                print(
                    "STOP",
                    client.call(
                        "start_stop_play",
                        {"studio_id": studio_id, "is_start": False},
                    ),
                )
            except Exception as error:  # noqa: BLE001
                print("STOP_ERROR", error, file=sys.stderr)
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
