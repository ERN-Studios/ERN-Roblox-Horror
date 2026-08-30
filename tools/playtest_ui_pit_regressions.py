"""Verify lobby HUD gating, elevator briefing timing, Level 1 card, and pit howl."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


UI_SNAPSHOT = r'''
local H=game:GetService("HttpService")
local p=game:GetService("Players").LocalPlayer
local pg=p:FindFirstChildOfClass("PlayerGui")
local flash=pg and pg:FindFirstChild("FlashlightPopup")
local stamina=pg and pg:FindFirstChild("StaminaGui")
local round=pg and pg:FindFirstChild("RoundGui")
local puzzle=pg and pg:FindFirstChild("PuzzleGui")
local panel=puzzle and puzzle:FindFirstChild("Level1Objectives",true)
local staBg=stamina and stamina:FindFirstChildWhichIsA("Frame")
return H:JSONEncode({
 inRound=p:GetAttribute("InRound"),
 flashlightEnabled=flash and flash.Enabled or false,
 staminaEnabled=stamina and stamina.Enabled or false,
 staminaSize=staBg and {staBg.AbsoluteSize.X,staBg.AbsoluteSize.Y} or nil,
 roundIgnoreInset=round and round.IgnoreGuiInset or false,
 roundDisplayOrder=round and round.DisplayOrder or nil,
 objectivePanelExists=panel~=nil,
 objectivePanelVisible=panel and panel.Visible or false,
 objectivePanelSize=panel and {panel.AbsoluteSize.X,panel.AbsoluteSize.Y} or nil,
})
'''

ENTER_QUEUE = r'''
local p=game:GetService("Players"):GetPlayers()[1]
local z=workspace:FindFirstChild("LaunchZone1",true)
if not (p and p.Character and z) then return "missing" end
p:SetAttribute("DevFastQueue",true)
p.Character:PivotTo(z.CFrame*CFrame.new(0,3,0))
return "entered"
'''

CONFIGURE = r'''
game.ReplicatedStorage.Remotes.ConfigureQueue:FireServer(1,1,"public")
return "configured"
'''

INTRO_TIMING = r'''
local H=game:GetService("HttpService")
local p=game:GetService("Players").LocalPlayer
local gui=p.PlayerGui:WaitForChild("RoundGui")
local label=gui:FindFirstChildOfClass("TextLabel")
local started=os.clock()
local runVisible=0
local maxRunStreak=0
local currentRunStreak=0
local sawBriefing=false
local sawRun=false
local sample=0.05
while os.clock()-started<26 and p:GetAttribute("InRound")==true do
 local text=label and label.Text or ""
 local visible=label and label.Visible or false
 if visible and text~="" then sawBriefing=true end
 if visible and string.find(text,"RUN",1,true) then
  sawRun=true
  runVisible+=sample
  currentRunStreak+=sample
  maxRunStreak=math.max(maxRunStreak,currentRunStreak)
 else
  currentRunStreak=0
 end
 if workspace:GetAttribute("RoundActive")==true then break end
 task.wait(sample)
end
return H:JSONEncode({sawBriefing=sawBriefing,sawRun=sawRun,
 runVisible=runVisible,maxRunStreak=maxRunStreak,
 roundActive=workspace:GetAttribute("RoundActive")==true,
 elapsed=os.clock()-started,finalText=label and label.Text or ""})
'''

SHOW_LEVEL1_OBJECTIVE = r'''
local p=game:GetService("Players"):GetPlayers()[1]
game.ReplicatedStorage.Remotes.PuzzleStatus:FireClient(p,"begin",2,2)
return "sent"
'''

PIT_HOWL_TEST = r'''
local H=game:GetService("HttpService")
local RunService=game:GetService("RunService")
local p=game:GetService("Players"):GetPlayers()[1]
local char=p and p.Character
local playerRoot=char and char:FindFirstChild("HumanoidRootPart")
local entity=workspace:FindFirstChild("Entity")
local entityRoot=entity and entity:FindFirstChild("HumanoidRootPart")
local hum=entity and entity:FindFirstChildOfClass("Humanoid")
local animator=hum and hum:FindFirstChildOfClass("Animator")
local folder=workspace:FindFirstChild("PitZones")
local zone
if folder then for _,item in ipairs(folder:GetChildren()) do
 if item:IsA("BasePart") then zone=item break end
end end
if not (playerRoot and entityRoot and animator and zone) then
 return H:JSONEncode({ok=false,reason="missing test objects"})
end
local y=35
local playerPos=Vector3.new(zone.Position.X,y,zone.Position.Z)
local entityPos=Vector3.new(zone.Position.X+zone.Size.X*0.5+4.5,y,zone.Position.Z)
playerRoot.Anchored=true
entityRoot.Anchored=true
char:PivotTo(CFrame.lookAt(playerPos,entityPos))
entity:PivotTo(CFrame.lookAt(entityPos,playerPos))
workspace:SetAttribute("EntityPaused",false)
local baseline=workspace:GetAttribute("EntityYell") or 0
local sequence={}
local last=""
local deadline=os.clock()+10
while os.clock()<deadline do
 local active={}
 for _,track in ipairs(animator:GetPlayingAnimationTracks()) do
  if track.IsPlaying then active[#active+1]=track.Name end
 end
 table.sort(active)
 local name=table.concat(active,"+")
 if name~=last then sequence[#sequence+1]=name; last=name end
 if (workspace:GetAttribute("EntityYell") or 0)>=baseline+2
  and name=="Watch" then break end
 RunService.Heartbeat:Wait()
end
playerRoot.Anchored=false
entityRoot.Anchored=false
local howlIndex,watchAfter=nil,nil
for i,name in ipairs(sequence) do
 if string.find(name,"Yell_Howl",1,true) then howlIndex=howlIndex or i
 elseif howlIndex and name=="Watch" then watchAfter=i break end
end
return H:JSONEncode({ok=howlIndex~=nil and watchAfter~=nil,
 yellDelta=(workspace:GetAttribute("EntityYell") or 0)-baseline,
 sequence=sequence,howlIndex=howlIndex,watchAfter=watchAfter})
'''


def main() -> int:
    client = StudioMcpClient(find_mcp_batch())
    started = False
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        print("START", client.call("start_stop_play", {"is_start": True}))
        started = True
        time.sleep(8)
        print("LOBBY_UI", client.call("execute_luau", {"datamodel_type": "Client", "code": UI_SNAPSHOT}))
        print("ENTER", client.call("execute_luau", {"datamodel_type": "Server", "code": ENTER_QUEUE}))
        time.sleep(1.5)
        print("CONFIGURE", client.call("execute_luau", {"datamodel_type": "Client", "code": CONFIGURE}))

        deadline = time.monotonic() + 55
        while time.monotonic() < deadline:
            time.sleep(1)
            raw = client.call("execute_luau", {"datamodel_type": "Client", "code": UI_SNAPSHOT})
            data = json.loads(raw) if isinstance(raw, str) else {}
            if data.get("inRound") is True:
                print("ROUND_UI", raw)
                break
        print("INTRO", client.call("execute_luau", {"datamodel_type": "Client", "code": INTRO_TIMING}))
        print("OBJECTIVE_EVENT", client.call("execute_luau", {"datamodel_type": "Server", "code": SHOW_LEVEL1_OBJECTIVE}))
        time.sleep(0.5)
        print("OBJECTIVE_UI", client.call("execute_luau", {"datamodel_type": "Client", "code": UI_SNAPSHOT}))
        print("PIT_HOWL", client.call("execute_luau", {"datamodel_type": "Server", "code": PIT_HOWL_TEST}))
        print("CONSOLE_BEGIN")
        print(client.call("get_console_output"))
        print("CONSOLE_END")
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
