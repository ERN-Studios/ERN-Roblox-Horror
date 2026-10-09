"""Drive B6 and B7 production renderers with real imported Framewisp templates.

Whole exit/prompt clients execute. Only hiding's preceding pose/camera code is
excluded; its complete UI, countdown, device and EXIT input code is executed.
Native rendering/font and hardware input remain Studio QA responsibilities.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
from test_round_hud import SOURCES, HARNESS, DUMPS, lua, long_string

ROOT = Path(__file__).resolve().parents[2]
CLIENTS = {
    'ExitClient': 'Round Exit Client',
    'FootageClient': 'Found Footage HUD',
    'HidingClient': 'Level 3 Table Hiding Client',
    'L2AlertClient': 'Level2AlertClient',
}
TESTS = r'''
local function boot(touch)
 local ctx = context({touch=touch})
 local services=ctx.Services
 services.Players.LocalPlayer.Name="Tester"
 services.Players.LocalPlayer.DisplayName="Display Tester"
 function services.Players:GetPlayers() return {ctx.Player} end
 function services.Players:GetPlayerByUserId(id) return id==ctx.Player.UserId and ctx.Player or nil end
 ctx.Player.UserId=1
 ctx.GuiService={MenuIsOpen=false}
 services.GuiService=ctx.GuiService
 services.RunService={RenderStepped=signal(),Heartbeat=signal(),IsStudio=function() return true end}
 services.ProximityPromptService={PromptShown=signal(),PromptHidden=signal(),Enabled=true}
 ctx.UIS.InputBegan,ctx.UIS.InputEnded,ctx.UIS.WindowFocusReleased=signal(),signal(),signal()
 ctx.UIS.TextBoxFocused,ctx.UIS.TextBoxFocusReleased=signal(),signal()
 function ctx.UIS:GetFocusedTextBox() return self.Focused end
 function ctx.GuiService:GetPropertyChangedSignal(name) return signal() end
 ctx.UIDevice.SetInteractive=function(n,yes) n.Visible,n.Active=yes,yes end
 ctx.UIDevice.SetEnabled=function(n,yes) n.Active=yes end
 local originalLayout=ctx.UIDevice.Layout
 ctx.UIDevice.Layout=function()
  local d=originalLayout()
  d.Zones=ctx.HidingZones or {Thumbstick={Left=0,Top=0,Right=0,Bottom=0}}
  return d
 end
 ctx.UIDevice.OverlapsMovementZone=function(left,top,right,bottom)
  for name,z in pairs(ctx.UIDevice.Layout().Zones) do
   if left<z.Right and right>z.Left and top<z.Bottom and bottom>z.Top then return name end
  end
  return nil
 end
 ctx.UIDevice.ScreenOwningModalOpen=function() return ctx.Player:GetAttribute("ZyntraStoreOpen")==true end
 ctx.UIDevice.OnScreenOwningModalChanged=function(fn) ctx.Player:GetAttributeChangedSignal("ZyntraStoreOpen"):Connect(fn) end
 local remotes=Instance.new("Folder");remotes.Name="Remotes";remotes.Parent=ctx.Storage
 ctx.Remote=Instance.new("RemoteEvent");ctx.Remote.Name="RoundStatus";ctx.Remote.Parent=remotes
 ctx.Remote.OnClientEvent=signal();ctx.Requests={}
 function ctx.Remote:FireServer(...) table.insert(ctx.Requests,{...}) end
 ctx.PlayerScripts=Instance.new("Folder");ctx.PlayerScripts.Name="PlayerScripts";ctx.PlayerScripts.Parent=ctx.Player
 ctx.Humanoid=Instance.new("Humanoid");ctx.Humanoid.Health=100;ctx.Humanoid.HealthChanged=signal();ctx.Humanoid.Died=signal()
 ctx.Character=Instance.new("Model");ctx.Character.Name="Character";ctx.Humanoid.Parent=ctx.Character;ctx.Player.Character=ctx.Character
 ctx.Player.CharacterAdded,ctx.Player.CharacterRemoving=signal(),signal()
 ctx.Workspace:SetAttribute("RoundActive",true)
 ctx.Player:SetAttribute("InRound",true)
 ctx.Player:SetAttribute("RoundEntryControlsReady",true)
 function ctx:Step(dt) self:Advance(dt);services.RunService.RenderStepped:Fire(dt);services.RunService.Heartbeat:Fire(dt) end
 function ctx:Key(code,ended)
  local input={KeyCode=Enum.KeyCode[code],UserInputType=Enum.UserInputType.Keyboard,UserInputState=Enum.UserInputState.Begin}
  if ended then ctx.UIS.InputEnded:Fire(input) else ctx.UIS.InputBegan:Fire(input,false) end
 end
 return ctx
end

for _, fps in ipairs({15,60,240}) do
 local ctx=boot(false);ctx:Require("ExitClient");ctx:Key("L")
 for i=1,math.ceil(1.5*fps)-1 do ctx:Step(1/fps) end
 check(#ctx.Requests==0,"no early hold at "..fps.." FPS")
 ctx:Step(1/fps+.0001);check(#ctx.Requests==1,"1.5 wall seconds at "..fps.." FPS")
end
for _,gate in ipairs({"Spectating","Escaped","Level2_ExitTransition","DispatchBriefingOpen","Level4CardOpen","PartyDownCardOpen"}) do
 local ctx=boot(false);ctx:Require("ExitClient");ctx:Key("L");ctx:Step(.6)
 ctx.Player:SetAttribute(gate,true);ctx:Step(1.5)
 check(#ctx.Requests==0,"mid-hold "..gate.." cancels")
end
for _, mode in ipairs({"typing","menu","focus","death","roundend","respawn"}) do
 local ctx=boot(false);ctx:Require("ExitClient");ctx:Key("L");ctx:Step(.6)
 if mode=="typing" then ctx.UIS.Focused=true
 elseif mode=="menu" then ctx.GuiService.MenuIsOpen=true
 elseif mode=="focus" then ctx.UIS.WindowFocusReleased:Fire()
 elseif mode=="death" then ctx.Humanoid.Health=0
 elseif mode=="roundend" then ctx.Workspace:SetAttribute("RoundActive",false)
 elseif mode=="respawn" then ctx.Player.CharacterRemoving:Fire() end
 ctx:Step(1.5);check(#ctx.Requests==0,"mid-hold "..mode.." cancels")
end
for _, touch in ipairs({false,true}) do
 local ctx=boot(touch);ctx:Require("ExitClient")
 local gui=ctx.PlayerGui:FindFirstChild("RoundExitGui")
 local door=gui:FindFirstChild(touch and "LeaveChipTouch" or "LeaveChip")
 check(door.Visible and door.Active,"exit available")
 check(door.Size.X.Offset==(touch and 44 or 40),"authored door width")
 check(door.Position.X.Offset==(touch and 12 or 24),"safe door lane")
 ctx:Key("L");ctx:Step(.8);ctx:Key("L",true);ctx:Step(1)
 check(#ctx.Requests==0,"early release no request")
 ctx:Key("L");ctx:Step(.7);ctx.Player:SetAttribute("ZyntraStoreOpen",true);ctx:Step(1)
 check(#ctx.Requests==0,"modal cancels hold")
 ctx.Player:SetAttribute("ZyntraStoreOpen",nil);ctx:Key("L",true)
 ctx:Key("L");ctx:Step(1.5);check(#ctx.Requests==1,"full hold once")
 ctx.Remote.OnClientEvent:Fire("leavefailed");ctx:Step(2)
 check(#ctx.Requests==1,"finished hold latched after refusal")
 ctx:Key("L",true);ctx:Key("ButtonSelect");ctx:Step(1.5)
 check(#ctx.Requests==2,"View hold uses existing protocol")
 ctx:Key("ButtonSelect",true);ctx:Advance(8.1)
 ctx.PlayerScripts:FindFirstChild("RoundExitPrompt").Event:Fire()
 local shade=gui:FindFirstChild("RoundExitShade");local card=shade:FindFirstChild("RoundExitCard")
 check(shade.Visible,"spectate confirm opens")
 local Binder=ctx:Require("ShopBinder")
 local confirm=Binder.at(card,"BackToLobby");local stay=Binder.at(card,"Stay")
 check(confirm.Active and stay.Active,"timeout re-enables confirmation")
 if touch then check(confirm.Size.Y.Offset>=44 and stay.Size.Y.Offset>=44,"phone confirm hits") end
 ctx:Key("ButtonB");check(not shade.Visible,"B chooses stay")
 ctx:Device({Touch=not touch});check(#ctx.Requests==2,"device remount never requests")
end

do
 local ctx=boot(false);ctx:Require("ExitClient")
 ctx:Key("L");ctx:Step(1.5);ctx.Remote.OnClientEvent:Fire("leaveack")
 ctx:Key("L",true);ctx:Advance(8.1)
 ctx.PlayerScripts:FindFirstChild("RoundExitPrompt").Event:Fire()
 local gui=ctx.PlayerGui:FindFirstChild("RoundExitGui")
 local Binder=ctx:Require("ShopBinder")
 local confirm=Binder.at(gui,"BackToLobby")
 check(not confirm.Active,"ack invalidates silence timer and keeps one pending request")
 confirm.Activated:Fire();check(#ctx.Requests==1,"card cannot duplicate held request")
 ctx.Remote.OnClientEvent:Fire("lobby");ctx:Advance(10)
 check(not gui:FindFirstChild("RoundExitShade").Visible,"old request timers never reopen a reset card")
end
do
 local ctx=boot(false);ctx:Require("ExitClient")
 ctx:Key("L");ctx:Step(1.5);ctx.Remote.OnClientEvent:Fire("leavefailed");ctx:Key("L",true)
 ctx:Key("L");ctx:Step(1.5);ctx:Key("L",true);ctx:Advance(5.1)
 ctx.PlayerScripts:FindFirstChild("RoundExitPrompt").Event:Fire()
 local Binder=ctx:Require("ShopBinder")
 check(not Binder.at(ctx.PlayerGui:FindFirstChild("RoundExitGui"),"BackToLobby").Active,
  "superseded first timeout cannot unlock second request")
end

do
 local ctx=boot(false);ctx.Workspace:SetAttribute("RoundStartedAt",-3661);ctx:Require("FootageClient");ctx:Step(0)
 local frame=ctx.PlayerGui:FindFirstChild("FoundFootageHUD")
 local Binder=ctx:Require("ShopBinder")
 check(Binder.at(frame,"Time").Text=="1:01:01","REC uses shared server time")
 ctx.Player:SetAttribute("SpectatorCount",2);ctx:Step(0)
 check(Binder.at(frame,"Watching").Text=="\u{B7} 2 WATCHING","REC owns watcher count")
 local prompt=Instance.new("ProximityPrompt");prompt.Style=Enum.ProximityPromptStyle.Custom
 prompt.ObjectText,prompt.ActionText="MAIN BREAKER","INSERT FUSE"
 prompt.HoldDuration=2;prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX
 prompt.UIOffset=Vector2.new(0,0);prompt.MaxActivationDistance=10
 prompt.PromptButtonHoldBegan,prompt.PromptButtonHoldEnded=signal(),signal()
 prompt.Parent=ctx.Character
 local begins,ends=0,0
 function prompt:InputHoldBegin() begins+=1;self.PromptButtonHoldBegan:Fire() end
 function prompt:InputHoldEnd() ends+=1;self.PromptButtonHoldEnded:Fire() end
 ctx.Services.ProximityPromptService.PromptShown:Fire(prompt)
 local board=ctx.PlayerGui:FindFirstChild("InteractionPrompt")
 check(board and board.Adornee==ctx.Character,"prompt attaches to real object")
 check(Binder.at(board,"ObjectLine").Text=="MAIN BREAKER","prompt actual copy")
 prompt.ActionText="Rub belly";prompt:GetPropertyChangedSignal("ActionText"):Fire()
 check(Binder.at(board,"ActionLine").Text=="RUB BELLY","Luna shown action refresh")
 local hit=Binder.at(board,"PromptHit");local finger={UserInputType=Enum.UserInputType.Touch}
 hit.InputBegan:Fire(finger);ctx:Step(1)
 check(begins==1 and Binder.at(board,"RingSlot").SweepHalf1.Visible,"prompt hold counts wall time")
 ctx.UIS.InputEnded:Fire(finger);check(ends==1,"finger release outside plate cancels")
 prompt:SetAttribute("HudDisabledReason","needs a fuse")
 check(Binder.at(board,"Reason").Text=="NEEDS A FUSE" and not Binder.at(board,"ObjectLine").Visible,"disabled reason replaces object")
 hit.InputBegan:Fire(finger);check(begins==1,"disabled plate never holds")
 ctx.Services.ProximityPromptService.PromptHidden:Fire(prompt)
 check(board.Parent==nil and board.Adornee==nil,"hidden pool drops attachment")
 prompt:SetAttribute("HudDisabledReason",nil);ctx.Services.ProximityPromptService.PromptShown:Fire(prompt)
 check(ctx.PlayerGui:FindFirstChild("InteractionPrompt")==board,"same layout reuses pooled board")
 ctx:Device({Touch=true})
 check(not frame:FindFirstChild("RecLine").Visible and not frame:FindFirstChild("Bracket1").Visible,"phone no REC/corners")
 local phoneBoard=ctx.PlayerGui:FindFirstChild("InteractionPrompt")
 check(Binder.at(phoneBoard,"KeyChip")==nil and Binder.at(phoneBoard,"HoldBar")~=nil,"phone prompt no key, actual hold bar")
end

for _,touch in ipairs({false,true}) do
 local ctx=boot(touch)
 ctx.Workspace:SetAttribute("SelectedLevel",3)
 local state=Instance.new("Folder");state.Name="Level 3 State";state.Parent=ctx.Storage
 local folder=Instance.new("Folder");folder.Name="Level 3 Remotes";folder.Parent=ctx.Storage
 local exit=Instance.new("RemoteEvent");exit.Name="Level3HideRequest";exit.Parent=folder
 local requests=0;function exit:FireServer(kind) check(kind=="EXIT","original exit payload");requests+=1 end
 ctx.Player:SetAttribute("Level3_Hiding",true);ctx.Player:SetAttribute("Level3_HideTableIndex",2)
 ctx:Require("HidingClient")
 local gui=ctx.PlayerGui:FindFirstChild("Level3TableHideUI")
 local banner=gui:FindFirstChild("HiddenStatus");local leave=gui:FindFirstChild("LeaveHiding")
 check(gui.Enabled and banner.Visible,"hidden banner active")
 ctx:Advance(6.1)
 check(near(banner.GroupTransparency,.55) and near(leave.GroupTransparency,.45),"authored quiet hidden state")
 state:SetAttribute("Level3_MallManagerTableCheckIndex",3);state:SetAttribute("Level3_MallManagerTableCheckEndsAt",ctx.Now+2)
 ctx:Step(0);check(not gui:FindFirstChild("TableCheck").Visible,"other table never warned")
 state:SetAttribute("Level3_MallManagerTableCheckIndex",2);ctx:Step(0)
 local Binder=ctx:Require("ShopBinder");local warning=gui:FindFirstChild("TableCheck")
 check(warning.Visible and near(banner.GroupTransparency,0),"own table urgent never dims")
 check(Binder.at(warning,"Seconds").Text=="2.0 s","server deadline seconds")
 local firstFill=Binder.at(warning,"Track/Fill").Size.X.Scale
 ctx:Step(1);check(Binder.at(warning,"Seconds").Text=="1.0 s","wall-clock warning drains")
 check(near(Binder.at(warning,"Track/Fill").Size.X.Scale,firstFill*.5),"draining fraction")
 ctx:Step(1.1);check(not warning.Visible,"expired warning hides")
 if touch then
  for _,width in ipairs({568,666}) do
   ctx.HidingZones={Thumbstick={Left=0,Top=48,Right=width*.4,Bottom=316},
    Controls={Left=width-124,Top=192,Right=width-8,Bottom=316}}
   ctx:Device({Touch=true,Safe={Left=0,Top=0,Right=width,Bottom=316,Width=width,Height=316}})
   leave=gui:FindFirstChild("LeaveHiding")
   local x,y=leave.Position.X.Offset-leave.Size.X.Offset/2,leave.Position.Y.Offset
   check(ctx.UIDevice.OverlapsMovementZone(x,y,x+leave.Size.X.Offset,y+leave.Size.Y.Offset)==nil,"short landscape EXIT clears activation region "..width)
   check(leave.Size.Y.Offset>=44,"short landscape keeps44px target "..width)
   state:SetAttribute("Level3_MallManagerTableCheckEndsAt",ctx.Now+2);ctx:Step(0)
   x,y=leave.Position.X.Offset-leave.Size.X.Offset/2,leave.Position.Y.Offset
   check(ctx.UIDevice.OverlapsMovementZone(x,y,x+leave.Size.X.Offset,y+leave.Size.Y.Offset)==nil,"urgent EXIT clears activation region "..width)
   ctx:Step(2.1)
  end
 end
 ctx:Key("E");check(requests==1,"E leaves hiding")
 ctx:Device({Touch=not touch});ctx:Key("ButtonB");check(requests==2,"device/B preserve request route")
 ctx.Player:SetAttribute("Level3_Hiding",nil);check(not gui.Enabled,"exit clears hiding GUI")
end
print("B6/B7: "..checks.." checks passed (production sources, real imported templates)")
'''

def main():
 sources={name:path.read_text(encoding='utf-8') for name,path in SOURCES.items()}
 for key,name in CLIENTS.items():
  source=(ROOT/'StarterPlayer/StarterPlayerScripts'/f'{name}.LocalScript.lua').read_text(encoding='utf-8')
  if key=='HidingClient':
   source='''local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local UIDevice=require(ReplicatedStorage:WaitForChild("UIDevice"))
local UserInputService=game:GetService("UserInputService")
local ProximityPromptService=game:GetService("ProximityPromptService")
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local requestRemote=nil
local hiding=false
local function setLocalCameraClipping() end
'''+source[source.index('local gui = Instance.new("ScreenGui")'):]
  sources[key]=source
 trees={bundle:json.loads((DUMPS/f'framewisp-dump.{bundle}.json').read_text(encoding='utf-8'))['root'] for bundle in ['HUD_PC','HUD_Touch','HUD_Screens']}
 inject='local SOURCES = {\n'+',\n'.join(f'{name} = {long_string(s)}' for name,s in sources.items())+'\n}\nlocal TREES = '+lua(trees)+'\n'
 harness=HARNESS.read_text(encoding='utf-8').replace('--@@INJECT@@',inject,1)
 harness=harness.replace('local game = {GetService', 'ctx.Services = services\n\tlocal game = {GetService',1)
 program=harness+'\n'+TESTS
 binary=os.environ['LUAU_BIN']
 with tempfile.TemporaryDirectory(prefix='hud-b6-b7-') as directory:
  path=Path(directory)/'test.luau';path.write_text(program,encoding='utf-8')
  result=subprocess.run([binary,str(path)],capture_output=True,text=True,timeout=120)
  if result.returncode:
   print(result.stdout);print(result.stderr);raise SystemExit(result.returncode)
  print(result.stdout.strip())

if __name__=='__main__': main()
