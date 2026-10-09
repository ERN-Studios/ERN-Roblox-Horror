"""Entire current WELCOME/HELP LocalScript in real offline Luau.

Real source/Config, shared fake values/Instances/signals and a yielding clock.
No Studio, HTTP or source writes. Native fonts, input hardware, viewport/UIScale
rendering, multiplayer and streaming remain pending. Known C21/C22 diagnostics
are separate from passing feature contracts.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from test_round_hud import HARNESS as BASE, long_string

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua'
CONFIG = ROOT / 'ReplicatedStorage/ZyntraConfig.ModuleScript.lua'

BOUNDARY = r'''
SUPER.ScrollingFrame="GuiObject"
SUPER.Part="BasePart"
SUPER.BasePart="Instance"
function methods:ClearAllChildren() for _,c in ipairs(self:GetChildren()) do c:Destroy() end end
function methods:Invoke(...) return assert(self.OnInvoke)(...) end
local originalDestroy=methods.Destroy
function methods:Destroy()
 originalDestroy(self)
 local f=FIELDS[self]
 for _,v in pairs(f) do if type(v)=="table" and v.__signal then
  for _,e in ipairs(table.clone(v.entries)) do e.Conn:Disconnect() end
 end end
 for _,s in pairs(f.Watchers) do for _,e in ipairs(table.clone(s.entries)) do e.Conn:Disconnect() end end
end
local vm={}
local V={new=function(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},vm) end}
vm.__add=function(a,b) return V.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__sub=function(a,b) return V.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__mul=function(a,b)
 if type(a)=="number" then return V.new(a*b.X,a*b.Y,a*b.Z) end
 if type(b)=="number" then return V.new(a.X*b,a.Y*b,a.Z*b) end
 return V.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z)
end
vm.__index=function(a,k)
 if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
 if k=="Unit" then local m=a.Magnitude; return V.new(a.X/m,a.Y/m,a.Z/m) end
end
local CFrame={lookAt=function(p,t) return {Position=p,Target=t} end}
local MODALS={"HelpPanelOpen","ZyntraStoreOpen","DevPhoneOpen","ZyntraReentryOpen","QueueModalOpen","LuckyWheelOpen","DailyRewardsOpen","AchievementsOpen"}
local function context(opts)
 opts=opts or {}
 local c={Now=0,Timers={},Viewport=opts.view or Vector2.new(1280,800),Touch=opts.touch==true,Switches={},Steps=0}
 CURRENT=c
 c.Safe={Left=0,Top=20,Right=c.Viewport.X,Bottom=c.Viewport.Y-20}
 c.Modal={Left=0,Top=20,Width=c.Viewport.X,Height=c.Viewport.Y-40}
 c.World=newInstance("Workspace","Workspace"); c.Player=newInstance("Player","Player")
 c.Gui=newInstance("PlayerGui","PlayerGui"); c.Gui.Parent=c.Player
 local ps=newInstance("PlayerScripts","PlayerScripts"); ps.Parent=c.Player
 local switch=newInstance("BindableFunction","ZyntraRailSwitch"); switch.Parent=ps
 switch.OnInvoke=function(flag) table.insert(c.Switches,flag) end
 c.Player:SetAttribute("LobbyLoadingDone",opts.loaded~=false)
 c.Player:SetAttribute("ZyntraFirstLogin",if opts.unknown then nil else opts.first~=false)
 c.Player:SetAttribute("InRound",opts.round==true); c.Player:SetAttribute("ZyntraRailRight",120)
 c.World:SetAttribute("ReservedRoundServer",opts.reserved==true); c.World:SetAttribute("DevShowWelcome",opts.dev==true)
 local lobby=newInstance("Model","ServerLobby"); lobby.Parent=c.World
 local spawn=newInstance("Part","LobbySpawn"); spawn.Position=V.new(0,30,-900); spawn.Parent=lobby
 local stage=newInstance("Model","LobbyReimaginedPreview"); stage.Parent=c.World
 stage.GetPivot=function() return {Position=V.new(0,30,-700)} end
 c.World.CurrentCamera={CameraType=opts.scriptable and Enum.CameraType.Scriptable or Enum.CameraType.Custom,CFrame={Position=V.new()}}
 function c:Resume(co,...)
  if self.Stopped then return end
  local ok,wait=coroutine.resume(co,...); if not ok then error(debug.traceback(co,tostring(wait)),0) end
  if coroutine.status(co)~="dead" then assert(type(wait)=="number" and wait>0); table.insert(self.Timers,{At=self.Now+wait,Co=co}) end
 end
 local task={}
 function task.spawn(fn,...) local co=coroutine.create(fn); c:Resume(co,...); return co end
 function task.wait(s) return coroutine.yield(s or .03) end
 function c:Advance(seconds)
  CURRENT=self; local target=self.Now+seconds
  while true do
   local index,due
   for i,t in ipairs(self.Timers) do if t.At<=target+1e-9 and (not due or t.At<due.At) then index,due=i,t end end
   if not due then break end
   table.remove(self.Timers,index); self.Now=due.At; self.Steps+=1
   assert(self.Steps<20000,"unbounded fixture worker"); self:Resume(due.Co)
  end
  self.Now=target
 end
 c.Player.CharacterAdded=signal()
 local connect=c.Player.CharacterAdded.Connect
 c.Player.CharacterAdded.Connect=function(self,fn) return connect(self,function(...) task.spawn(fn,...) end) end
 function c:Character(noRoot)
  local char=newInstance("Model","Character"); char.Parent=self.World
  if not noRoot then local root=newInstance("Part","HumanoidRootPart"); root.Position=V.new(0,30,-900); root.Parent=char end
  self.Player.Character=char; self.Player.CharacterAdded:Fire(char)
 end
 c:Character(opts.noRoot)
 c.UIS={TouchEnabled=c.Touch,KeyboardEnabled=not c.Touch,InputBegan=signal()}
 c.UIS.GetFocusedTextBox=function() return c.Focus end
 local uid={Changed=signal()}
 uid.Layout=function() return {Viewport=c.Viewport,Safe=c.Safe,ModalViewport=c.Modal,IsTouch=c.Touch} end
 uid.LocalPosition=function(_,x,y) return UDim2.fromOffset(x,y) end
 uid.ScreenOwningModalOpen=function()
  if c.ModalElsewhere then return true end
  for _,flag in ipairs(MODALS) do if c.Player:GetAttribute(flag)==true then return true end end
  return false
 end
 uid.SuppressTouchMovement=function(v) c.Suppressed=v end; c.UIDevice=uid
 local badgeGui=newInstance("ScreenGui","Achievements"); badgeGui.Parent=c.Gui
 local badge=newInstance("TextButton","Open"); badge.Text="Badges"; badge.Parent=badgeGui
 badge.Size=UDim2.fromOffset(64,40); badge.AbsolutePosition=Vector2.new(16,250)
 local rail=newInstance("ScreenGui","ZyntraStore"); rail.Parent=c.Gui
 local music=newInstance("TextButton","Music"); music.Parent=rail
 music.Size=UDim2.fromOffset(64,40); music.AbsolutePosition=Vector2.new(16,298)
 local rs=newInstance("ReplicatedStorage","ReplicatedStorage")
 newInstance("ModuleScript","UIDevice").Parent=rs; newInstance("ModuleScript","ZyntraConfig").Parent=rs
 local services={Players={LocalPlayer=c.Player},ReplicatedStorage=rs,UserInputService=c.UIS,
  RunService={IsStudio=function() return opts.studio~=false end},TweenService={Create=function(_,item,_,goal)
   return {Play=function() for k,v in pairs(goal) do item[k]=v end end}
  end}}
 local configCode=assert(loadstring(CONFIG_SOURCE))
 setfenv(configCode,setmetatable({Color3=Color3},{__index=_G}))
 local config=opts.config or configCode()
 local env=setmetatable({game={GetService=function(_,n) return assert(services[n],n) end},workspace=c.World,
  task=task,os={clock=function() return c.Now end},Enum=Enum,Color3=Color3,UDim=UDim,UDim2=UDim2,
  Vector2=Vector2,Vector3=V,CFrame=CFrame,TweenInfo=TweenInfo,
  Instance={new=function(class,parent) local item=newInstance(class); item.Parent=parent; return item end},
  require=function(module)
   if module.Name=="UIDevice" then return uid end
   assert(module.Name=="ZyntraConfig"); if opts.configError then error("fixture config error") end
   return config
  end}, {__index=_G})
 local code=assert(loadstring(GUIDE_SOURCE,"=First Entry Guide")); setfenv(code,env); task.spawn(code)
 function c:Welcome() return self.Gui:FindFirstChild("WelcomeCard") end
 function c:Help() return self.Gui:FindFirstChild("HelpPanel") end
 function c:Button(name) return assert(self.Gui:FindFirstChild(name,true),name) end
 function c:Input(key,processed) self.UIS.InputBegan:Fire({KeyCode=Enum.KeyCode[key]},processed==true) end
 function c:Stop() self.Stopped=true; self.Timers={}; self.Gui:Destroy(); self.World:Destroy() end
 return c
end
local function settled(opts) local c=context(opts); c:Advance(1.3); return c end
local function card(c) return assert(c:Welcome(),"welcome missing"):FindFirstChild("Card",true) end
local function title(c) return card(c):FindFirstChild("Title").Text end
local function click(c,name) c:Button(name).Activated:Fire() end
local function texts(root)
 local out={}; for _,n in ipairs(root:GetDescendants()) do if n:IsA("TextLabel") then table.insert(out,n.Text) end end
 return table.concat(out,"\n")
end
local function help(c)
 local holder=assert(c.Gui:FindFirstChild("HelpButton")); holder:SetAttribute("Toggle",(holder:GetAttribute("Toggle") or 0)+1)
 return c:Help()
end
'''

TESTS = r'''
do
 for _,o in ipairs({{first=false},{unknown=true},{reserved=true},{round=true}}) do
  local c=settled(o); check(c:Welcome()==nil,"suppressed context has no unsolicited tutorial"); c:Stop()
 end
 local c=context({loaded=false}); c:Advance(3); check(not c:Welcome(),"loading cover delays tutorial")
 c.Player:SetAttribute("LobbyLoadingDone",true); c:Advance(1.5); check(c:Welcome(),"cover release starts tutorial"); c:Stop()
 c=context({unknown=true}); c:Advance(2); check(not c:Welcome(),"unknown profile waits")
 c.Player:SetAttribute("ZyntraFirstLogin",true); c:Advance(1.5); check(c:Welcome(),"late profile starts tutorial")
 click(c,"Skip"); c.Player:SetAttribute("ZyntraFirstLogin",false); c.Player:SetAttribute("ZyntraFirstLogin",true); c:Advance(2)
 check(not c:Welcome(),"automatic tutorial is one shot"); c:Stop()
 c=settled({first=false,dev=true}); check(c:Welcome(),"Studio authoring override available"); c:Stop()
 c=settled({first=false,dev=true,studio=false}); check(not c:Welcome(),"override is Studio-only"); c:Stop()
end
do
 local c=settled(); local pages={"WELCOME TO THE BACKROOMS","QUIET, LIGHT, HIDE","BRING A TEAM","EARN THEM, SPEND THEM"}
 check(c.Player:GetAttribute("WelcomeCardOpen")==true and not c:Welcome().ResetOnSpawn,"tutorial ownership and respawn")
 check(c:Welcome():FindFirstChild("Shade").BackgroundTransparency==.45,"tutorial opening tween applies shade goal")
 check(not help(c),"HELP never opens over tutorial")
 check(title(c)==pages[1] and not c:Button("Back").Visible,"first page boundary")
 click(c,"Next"); check(title(c)==pages[2],"button advances")
 c:Input("Left"); check(title(c)==pages[1],"keyboard back")
 c:Input("ButtonL1"); check(title(c)==pages[1],"back clamps")
 for i=2,4 do c:Input("ButtonR1"); check(title(c)==pages[i],"gamepad page "..i) end
 check(c:Button("Next").Text=="START PLAYING","last page completion copy")
 c:Input("ButtonA"); check(not c:Welcome(),"final page closes")
 check(c.Player:GetAttribute("WelcomeCardOpen")==nil and #c.UIS.InputBegan.entries==0,"tutorial closes input and flag")
 check(help(c),"HELP available after tutorial"); click(c,"Tutorial")
 check(not c:Help() and c:Welcome(),"HELP tutorial replay")
 c:Input("Escape"); check(not c:Welcome() and #c.UIS.InputBegan.entries==0,"Escape skips and cleans input"); c:Stop()
end
do
 local c=settled(); local gui=c:Welcome(); local first=title(c)
 gui:SetAttribute("Page",99); check(title(c)==first,"invalid page leaves tutorial usable")
 gui:SetAttribute("Page",2); check(title(c)=="QUIET, LIGHT, HIDE","authoring page control remains available")
 local scale=card(c):FindFirstChildOfClass("UIScale").Scale
 c.Viewport=Vector2.new(900,500); c.UIDevice.Changed:Fire()
 check(card(c):FindFirstChildOfClass("UIScale").Scale<scale,"tutorial responds to viewport shrink")
 c.Player:SetAttribute("InRound",true)
 check(not c:Welcome() and #c.UIDevice.Changed.entries==0 and #c.UIS.InputBegan.entries==0,"round entry releases tutorial listeners")
 c.Player:SetAttribute("InRound",false); c:Advance(1)
 check(not c:Welcome(),"round exit does not repeat first-login tutorial"); c:Stop()
end
do
 for _,o in ipairs({{}, {config={LevelCompletionTokens=7,Child={StartingTokens=41,
  A={Name="Entity Shield",TokenCost=13},B={Name="Speed Potion",TokenCost=11},C={Name="Route Marker Pack",TokenCost=9}}}}, {configError=true}}) do
  local c=settled(o); c:Welcome():SetAttribute("Page",4); local copy=texts(card(c))
  local start=o.config and 41 or 25; local reward=o.config and 7 or 2
  check(copy:find("You start with "..start,1,true),"starting tokens use config/fallback")
  check(copy:find("Clear a level: +"..reward,1,true),"completion reward uses config/fallback")
  if o.config then check(copy:find("Entity Shield 13",1,true) and copy:find("Speed Potion 11",1,true) and copy:find("Route Markers 9",1,true),"all prices come from named config items") end
  click(c,"Skip"); local h=help(c); h:SetAttribute("Topic",7)
  check(texts(h):find("You start with "..start,1,true),"HELP uses same token config"); c:Stop()
 end
end
do
 for _,touch in ipairs({false,true}) do
  local c=settled({first=false,touch=touch,view=touch and Vector2.new(520,780) or nil})
  local h=assert(help(c)); local p=h:FindFirstChild("Panel",true)
  check(h.DisplayOrder==117 and not h.ResetOnSpawn,"HELP rail layering and respawn")
  check(c.Player:GetAttribute("HelpPanelOpen")==true and c.Suppressed,"HELP owns movement suppression")
  check(c.Switches[1]=="HelpPanelOpen","HELP requests rail window switch")
  local list,content=p:FindFirstChild("Topics"),p:FindFirstChild("Content")
  for i,name in ipairs({"THE GOAL","CONTROLS","STAYING ALIVE","THE LEVELS","PLAYING TOGETHER","IF YOU DIE","TOKENS","ITEMS","REWARDS & BADGES","SETTINGS & SUPPORT"}) do
   h:SetAttribute("Topic",i); check(texts(content):find(name,1,true),"selected topic "..name)
   check(list:FindFirstChild("Topic"..i),"topic button "..i)
  end
  h:SetAttribute("Topic",2); check(texts(content):find(touch and "Left stick" or "WASD",1,true),"device controls copy")
  check(content.AutomaticCanvasSize==Enum.AutomaticSize.Y and list.AutomaticCanvasSize==Enum.AutomaticSize.Y,"HELP columns scroll")
  local size,pos=p.Size,p.Position; local scale=p:FindFirstChildOfClass("UIScale").Scale
  if touch then check(scale==1,"touch HELP preserves text size") end
  check(pos.X.Offset-size.X.Offset*scale/2>=128-.01 and pos.X.Offset+size.X.Offset*scale/2<=c.Viewport.X+.01,"HELP outside rail and in modal viewport")
  local head,sub
  for _,child in ipairs(p:GetChildren()) do
   if child:IsA("TextLabel") and child.Text=="HELP" then head=child end
   if child:IsA("TextLabel") and child.Text=="ZYNTRA  //  FIELD MANUAL" then sub=child end
  end
  check(head and sub and p:FindFirstChild("Tutorial").Text=="PLAY THE TUTORIAL" and p:FindFirstChild("Close").Size.X.Offset==44,"current header and close/replay contracts")
  check(sub.Visible==(size.X.Offset>=560),"narrow header avoids replay button")
  check(list.Size.X.Scale==(size.X.Offset<560 and .4 or .3),"responsive topic width")
  h:SetAttribute("Topic",99); check(texts(content):find("CONTROLS",1,true),"invalid topic leaves HELP usable")
  content.CanvasPosition=Vector2.new(0,300); list:FindFirstChild("Topic3").Activated:Fire()
  check(texts(content):find("STAYING ALIVE",1,true) and content.CanvasPosition.Y==0,"topic button replaces content and resets scroll")
  c.Viewport=Vector2.new(1000,760); c.Safe.Right,c.Safe.Bottom=1000,740; c.Modal.Width,c.Modal.Height=1000,720; c.UIDevice.Changed:Fire()
  check(p.Size.X.Offset>size.X.Offset or not touch,"safe viewport reflow")
  c.Player.PlayerScripts:FindFirstChild("CloseHelpPanel"):Invoke()
  check(not c:Help() and c.Player:GetAttribute("HelpPanelOpen")==nil and not c.Suppressed and #c.UIS.InputBegan.entries==0 and #c.UIDevice.Changed.entries==0,"rail bridge releases HELP resources")
  help(c); c.Player:SetAttribute("QueueModalOpen",true); check(not c:Help() and c.Suppressed,"new modal keeps movement suppression")
  c.Player:SetAttribute("QueueModalOpen",nil); help(c); c.Player:SetAttribute("InRound",true); check(not c:Help(),"round entry closes HELP"); c:Stop()
 end
end
do
 for _,flag in ipairs({"ZyntraStoreOpen","DevPhoneOpen","ZyntraReentryOpen","QueueModalOpen","LuckyWheelOpen","DailyRewardsOpen","AchievementsOpen"}) do
  local c=settled({first=false}); help(c); c.Player:SetAttribute(flag,true)
  check(not c:Help() and c.Suppressed and #c.UIDevice.Changed.entries==0,"modal handoff releases HELP: "..flag); c:Stop()
 end
 local c=settled({first=false}); help(c); c:Input("ButtonB")
 check(not c:Help() and not c.Suppressed,"gamepad closes HELP")
 help(c):SetAttribute("Topic",0); check(not c:Help(),"authoring topic control can close HELP")
 help(c); click(c,"Close"); check(not c:Help() and #c.UIS.InputBegan.entries==0,"close button releases HELP input")
 c.Player:SetAttribute("InRound",true); check(not help(c),"HELP cannot reopen during a round"); c:Stop()
end
do
 local c=settled({first=false}); local button=c.Gui:FindFirstChild("HelpButton"):FindFirstChild("Open")
 check(button.Visible and button.Position.Y.Offset==212,"HELP entry chooses clear rail slot above blocked BADGES")
 c.ModalElsewhere=true; c:Advance(.6); check(not button.Visible,"screen owner hides HELP entry")
 c.ModalElsewhere=false; c.Player:SetAttribute("LuckyWheelOpen",true); c:Advance(.6); check(not button.Visible,"wheel hides HELP entry"); c:Stop()
 c=settled({first=false,scriptable=true}); check(not c.World.CurrentCamera.CFrame.Target,"scripted camera stays owned")
 c.World.CurrentCamera.CameraType=Enum.CameraType.Custom; c:Advance(.2)
 check(c.World.CurrentCamera.CFrame.Target.Z>-900,"spawn view aims toward DJ stage")
 local aim=c.World.CurrentCamera.CFrame; c:Advance(1); check(c.World.CurrentCamera.CFrame==aim,"spawn aim is one shot")
 c:Character(); check(c.World.CurrentCamera.CFrame~=aim,"respawn reaims lobby")
 c.Player:SetAttribute("InRound",true); aim=c.World.CurrentCamera.CFrame; c:Character()
 check(c.World.CurrentCamera.CFrame==aim,"round respawn never uses lobby aim"); c:Stop()
 c=settled({first=false,noRoot=true}); check(not c.World.CurrentCamera.CFrame.Target,"missing root abandons aim safely"); c:Stop()
end
print("First Entry Guide current WELCOME/HELP: "..checks.." checks passed (entire actual script, offline Luau)")
'''

DIAGNOSTICS = r'''
local c=settled(); local before=title(c)
c.Focus=newInstance("TextBox","Chat"); c:Input("Space",true)
print("C21 focus/processed-input: "..(title(c)~=before and "REPRODUCED; runtime retained" or "not reproduced")); c:Stop()
c=settled({touch=true,view=Vector2.new(568,320)})
local skip=c:Button("Skip"); local scale=card(c):FindFirstChildOfClass("UIScale").Scale
print(string.format("C22 touch Skip: %.2fx%.2f effective authored px; native fonts/hit routing pending",skip.Size.X.Offset*scale,skip.Size.Y.Offset*scale)); c:Stop()
'''

def program(source, tests=TESTS):
    parts=BASE.read_text(encoding='utf-8').split('-- ------------------------------------------------------------ tree builder',1)
    assert len(parts)==2 and parts[0].count('--@@INJECT@@')==1,'shared fake-engine boundary changed'
    primitives=parts[0]
    injection='local GUIDE_SOURCE='+long_string(source)+'\nlocal CONFIG_SOURCE='+long_string(CONFIG.read_text(encoding='utf-8'))
    return primitives.replace('--@@INJECT@@',injection)+BOUNDARY+tests

def execute(binary, directory, name, code):
    path=Path(directory)/(name+'.luau'); path.write_text(code,encoding='utf-8')
    return subprocess.run([binary,str(path)],capture_output=True,encoding='utf-8',timeout=30)

def main():
    binary=os.environ.get('LUAU_BIN') or shutil.which('luau')
    if not binary: raise SystemExit('Set LUAU_BIN; no tests executed.')
    source=SOURCE.read_text(encoding='utf-8')
    protected={p:hashlib.sha256(p.read_bytes()).hexdigest() for p in (SOURCE,CONFIG,BASE)}
    with tempfile.TemporaryDirectory(prefix='first-entry-guide-') as directory:
        result=execute(binary,directory,'current',program(source))
        assert result.returncode==0,result.stdout+result.stderr
        print(result.stdout.strip())
        mutants={
            'first-login':('return player:GetAttribute("ZyntraFirstLogin") == true','return true','suppressed context'),
            'next-button':('nextButton.Activated:Connect(function() step(1) end)','nextButton.Activated:Connect(function() step(-1) end)','button advances'),
            'help-movement':('UIDevice.SuppressTouchMovement(true)','UIDevice.SuppressTouchMovement(false)','movement suppression'),
            'help-rail':('if type(railRight) == "number" and left < railRight + 8 then','if false then','outside rail'),
            'config-reward':('local perClear = config and tonumber(config.LevelCompletionTokens) or 2','local perClear = 2','completion reward'),
            'help-header':('label(panel, "HELP", 28','label(panel, "ARCHIVE", 28','current header'),
        }
        for name,(old,new,fragment) in mutants.items():
            assert source.count(old)==1,'source drift at '+name
            bad=execute(binary,directory,name,program(source.replace(old,new,1)))
            assert bad.returncode!=0 and fragment in bad.stdout+bad.stderr,name+': '+bad.stdout+bad.stderr
        print('6 negative fixtures rejected: onboarding gate/navigation/movement/rail/config/header')
        result=execute(binary,directory,'diagnostics',program(source,DIAGNOSTICS))
        assert result.returncode==0,result.stdout+result.stderr
        print(result.stdout.strip())
    assert all(hashlib.sha256(p.read_bytes()).hexdigest()==digest for p,digest in protected.items()),'authoritative input changed during gate'

if __name__=='__main__': main()
