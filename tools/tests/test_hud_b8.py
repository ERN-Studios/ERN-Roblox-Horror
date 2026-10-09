"""Execute the real B8 controllers against the real Framewisp HUD_Screens dump.

This uses the shared HUD fake engine, real RoundHud/ShopBinder/DeathAdvice and
production blocks from RoundUI/SpectateController. It checks state and authored
parts, not font rendering, Roblox menu delivery, camera replication or hit tests.
Those remain the coordinator's Studio gate. Set LUAU_BIN to official Luau.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_round_hud import SOURCES, HARNESS, DUMPS, lua, long_string, trees

ROOT = Path(__file__).resolve().parents[2]
ROUND = ROOT / "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"
SPECTATE = ROOT / "StarterPlayer/StarterPlayerScripts/SpectateController.LocalScript.lua"


def section(source, start, stop):
    a = source.index(start)
    return source[a:source.index(stop, a)]


SETUP = r'''
return function(ctx, mode)
 local player, RS, workspace = ctx.Player, ctx.Storage, ctx.Workspace
 local Players, UIS, UIDevice, RunService = ctx.Players, ctx.UIS, ctx.UIDevice, ctx.RunService
 local TweenService, task = ctx.Tween, ctx.Task
 local os = {clock=function() return ctx.Now end}
 local GuiService={MenuIsOpen=false,MenuOpened=signal(),SelectedObject=nil,Changed=signal()}
 function GuiService:GetPropertyChangedSignal() return self.Changed end
 local ContextActionService={Actions={}}
 function ContextActionService:UnbindAction(name) self.Actions[name]=nil end
 function ContextActionService:BindActionAtPriority(name,callback) self.Actions[name]=callback end
 local MarketplaceService={PromptProductPurchaseFinished=signal(),Purchases={}}
 function MarketplaceService:PromptProductPurchase(who,id) table.insert(self.Purchases,{who,id}) end
 local engineGame=game
 local game={GetService=function(_,name)
  if name=='GuiService' then return GuiService end
  if name=='MarketplaceService' then return MarketplaceService end
  return engineGame:GetService(name)
 end}
 UIS.InputBegan,UIS.LastInputTypeChanged=signal(),signal()
 function UIS:GetFocusedTextBox() return self.Focused end
 RunService.RenderStepped=signal()
 player.CharacterAdded=signal()
 local modal=false
 function UIDevice.ScreenOwningModalOpen() return modal or player:GetAttribute('RoundEndingOpen')==true end
 function UIDevice.OnScreenOwningModalChanged(fn) ctx.ModalChanged=fn end
 function UIDevice.SetInteractive(node,value) node.Visible,node.Active,node.Selectable=value,value,value end
 function workspace:GetServerTimeNow() return ctx.Now end
 local gui=Instance.new('ScreenGui');gui.Name='RoundGui';gui.Parent=ctx.PlayerGui
 local remote={OnClientEvent=signal(),Sent={}}
 function remote:FireServer(...) table.insert(self.Sent,table.pack(...)) end
 local dispatchAudio={action={Sent={}}}
 function dispatchAudio.action:FireServer(...) table.insert(self.Sent,table.pack(...)) end
 local label=Instance.new('TextLabel');label.Text='';label.Parent=gui
 local function setMsg(text) label.Text=text or '' end
 local script={Parent=Instance.new('Folder')}
 local command=Instance.new('BindableEvent');command.Name='DevCheatCommand';command.Parent=script.Parent
 local commands={};function command:Fire(value) table.insert(commands,value) end
 local completion={returnVisible=false,buttons={}}
 local endFrame=Instance.new('Frame');endFrame.Name='RoundEnding';endFrame.Visible=false;endFrame.Parent=gui
 local endFlash=Instance.new('Frame');endFlash.Name='SignalFlash';endFlash.Parent=endFrame
 local endLine=Instance.new('Frame');endLine.Name='SignalLine';endLine.Parent=endFrame
 local loadingFrame,queueShade={Visible=false},{Visible=false}
 local endingSerial,dead=0,false
 local function refreshCursor() end
 local function cancelAllCommandBriefings() end
 local function stopSpectating() end
 local function startSpectating() end
 local function formatRoundTime(seconds) return string.format('%02d:%02d',math.floor(seconds/60),seconds%60) end
 local exitThud={TimePosition=0,Stop=function() end,Play=function() end}
 local exitChime={TimePosition=0,Stop=function() end,Play=function() end}
 local Binder=require(RS:WaitForChild('ZyntraShopUI'):WaitForChild('ShopBinder'))
 local Hud=require(RS:WaitForChild('RoundHud'))
 local out={Gui=gui,Remote=remote,Navigation=GuiService,CAS=ContextActionService,Market=MarketplaceService,
  Dispatch=dispatchAudio,Completion=completion,Commands=commands,Label=label}
 function out.Find(name) return Binder.find(gui,name) end
 function out.Text(root,path) return Binder.at(root,path).Text end
 function out.Modal(value) modal=value;if ctx.ModalChanged then ctx.ModalChanged() end end
 if mode=='loading' then
 __LOADING__
  out.Cards=dispatchAudio.loadingCards
  out.Frame=loadingFrame
  out.Apply=applyLoadingPalette
 elseif mode=='results' then
 __RESULTS_UI__
 __RESULTS_LOGIC__
 __ENDING__
  remote.OnClientEvent:Connect(function(ev,a,b,c,d,e,f)
 __RESULT_EVENTS__
  end)
  out.Show=showRoundEnding
  out.Hide=hideRoundEnding
  out.Frame=endFrame
  out.Flash=endFlash
 elseif mode=='party' then
  completion.Hud=Hud
 __PARTY__
 elseif mode=='death' then
 __DEATH__
 elseif mode=='caption' then
  dispatchAudio.Hud=Hud
  dispatchAudio.panel={Visible=false}
  dispatchAudio.group={Volume=0}
  dispatchAudio.voiceEnabled=false
  dispatchAudio.active=true
  function dispatchAudio.preferenceLoaded() return true end
  function dispatchAudio.preferenceUnavailable() return false end
  function dispatchAudio.hasActiveTransmission() return dispatchAudio.active end
 __CAPTION_CLOCK__
 __CAPTION_REFRESH__
  out.Refresh=dispatchAudio.refresh
  out.Clock=dispatchAudio.newCaptionClock
  out.Position=dispatchAudio.captionPosition
 elseif mode=='spectate' then
  local ReplicatedStorage=RS
  local playerScripts=script.Parent
  local prompt=Instance.new('BindableEvent');prompt.Name='RoundExitPrompt';prompt.Parent=playerScripts
  local prompts=0;function prompt:Fire() prompts+=1 end
  local spectating,targets,idx,spectated=false,{},1,nil
  local snapCam=true
  local function unhide() end
  local beamMount,core,spill={},{},{}
  local lastBeamProfile,lastOn=nil,nil
 __REPORT_TARGET__
 __BAND__
 __LIVING__
 __WATCH__
 __BAND_LAYOUT__
 __SPECTATE_STATE__
 __SPECTATE_INPUT__
  out.Start,out.Stop,out.Watch=startSpectate,stopSpectate,watch
  function out.Prompts() return prompts end
 end
 ctx:Flush()
 return out
end
'''

TESTS = r'''
local function boot(mode,opts)
 local ctx=context(opts)
 if opts and opts.dev then ctx:Require('DevAccess').Allowed=true end
 local controller=ctx:Require('B8Controller')(ctx,mode)
 return ctx,controller
end
local function member(ctx,id,name,display,health,escaped)
 local p=Instance.new('Player');p.UserId,p.Name,p.DisplayName=id,name,display
 local char=Instance.new('Model');local hum=Instance.new('Humanoid');hum.Health=health;hum.Parent=char
 local root=Instance.new('Part');root.Name='HumanoidRootPart';root.Parent=char;p.Character=char
 p:SetAttribute('Escaped',escaped);table.insert(ctx.Players.Members,p)
 return p
end
local B='\u{B7}'
do -- Loading: all six real cards, mystery privacy, copy and black opacity.
 local ctx,c=boot('loading')
 local advice=ctx:Require('DeathAdvice')
 local accents={{255,230,0},{77,163,255},{255,0,0},{255,70,200},{212,220,232},{156,134,255}}
 for level=1,6 do
  c.Apply(level);ctx:Flush()
  check(c.Frame.BackgroundColor3==Color3.new(0,0,0) and c.Frame.BackgroundTransparency==0,'opaque black level '..level)
  check(c.Text(c.Cards.root,'Title')==({[1]='RESTORE THE POWER',[2]='UNRECORDED',[3]='FIND THE CDS',[4]='RESTORE THE POWER',[5]='??? WHERE?',[6]='THE PLAYGROUND'})[level],'loading title '..level)
  check(c.Cards.root:FindFirstChild('Title',true).TextColor3==Color3.fromRGB(table.unpack(accents[level])),'accent '..level)
  for i=1,6 do
   local slot=c.Cards.root:FindFirstChild('Slot'..i,true)
   check(slot.Text==((i==2 or i==5) and '?' or tostring(i)),'mystery track slot')
   check(slot.TextTransparency==(i==level and 0 or 0.55),'track highlight')
  end
  if level==2 or level==5 then
   for _,name in ipairs({'Eyebrow','Steps','Tip','Divider'}) do check(not c.Cards.root:FindFirstChild(name,true).Visible,'mystery hides '..name) end
  end
  local key=({[1]='L1Entity',[3]='L3Manager',[4]='L4Usher'})[level]
  if key then check(c.Text(c.Cards.root,'Tip/TipText')==advice.Copy(key).Tip,'real advice loading tip') end
  for _,n in ipairs(c.Frame:GetDescendants()) do check(not n:IsA('ImageLabel') and not n:IsA('ImageButton'),'no loading image') end
 end
 c.Cards.MysteryTitleMode='random'
 for i=1,12 do c.Apply(i%2==0 and 2 or 5);check(table.find(c.Cards.MysteryTitlePool,c.Text(c.Cards.root,'Title'))~=nil,'random mystery pool') end
 c.Cards.stage(0.8);ctx:Device({Touch=true});check(near(c.Cards.fill.Size.X.Scale,0.8),'resize preserves progress')
 check(c.Text(c.Cards.root,'Status/StatusLine')=='PREPARING YOUR PARTY','status retained on resize')
end
do -- Death: actual imported nested parts, all closes, serial cancellation and life reset.
 local ctx,c=boot('death')
 c.Remote.OnClientEvent:Fire('death','Other',nil,'L2Foam');check(c.Find('DeathCause')==nil,'own death only')
 c.Remote.OnClientEvent:Fire('death',ctx.Player.Name,nil,'L2Hole');ctx:Flush()
 check(c.Find('DeathCause').Visible,'own death shows imported standalone')
 check(c.Text(c.Find('DeathCause'),'Head/DeathCauseTitle')=='YOU FELL','hole copy')
 ctx.Player:SetAttribute('PartyDownCardOpen',true);check(not c.Find('DeathCause').Visible and c.Find('DeathCauseDocked').Visible,'always dock under party')
 check(c.CAS.Actions.DeathCauseClose('',Enum.UserInputState.Begin)==Enum.ContextActionResult.Pass,'B passes under party')
 c.Find('DeathCauseDocked'):FindFirstChild('Close',true).Activated:Fire()
 ctx.Player:SetAttribute('PartyDownCardOpen',nil);ctx.Player:SetAttribute('PartyDownCardOpen',true)
 check(not c.Find('DeathCause').Visible and not c.Find('DeathCauseDocked').Visible,'closed life cannot re-dock')
 ctx:Advance(13);check(not c.Find('DeathCauseDocked').Visible,'closed timer cannot revive card')
 ctx.Player:SetAttribute('PartyDownCardOpen',nil)
 c.Remote.OnClientEvent:Fire('death',ctx.Player.Name,nil,'Unknown');ctx:Flush()
 check(c.Find('DeathCause').Visible and not c.Find('DeathCause'):FindFirstChild('Advice',true).Visible,'next death opens without empty advice')
 c.Navigation.MenuIsOpen=true
 check(c.CAS.Actions.DeathCauseClose('',Enum.UserInputState.Begin)==Enum.ContextActionResult.Pass,'B passes Roblox menu')
 c.Navigation.MenuIsOpen=false
 check(c.CAS.Actions.DeathCauseClose('',Enum.UserInputState.Begin)==Enum.ContextActionResult.Sink,'B closes standalone')
 c.Remote.OnClientEvent:Fire('death',ctx.Player.Name,nil,'L3Manager');c.Navigation.MenuOpened:Fire()
 check(not c.Find('DeathCause').Visible,'menu fallback closes Esc')
 c.Remote.OnClientEvent:Fire('death',ctx.Player.Name,nil,'L1Pit');ctx.UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.Escape},true)
 check(not c.Find('DeathCause').Visible,'Escape closes even if Roblox processed it')
 c.Remote.OnClientEvent:Fire('death',ctx.Player.Name,nil,'L1Entity');ctx:Advance(6);ctx:Device({Touch=true});ctx:Advance(6)
 check(not c.Find('DeathCause').Visible,'device remount preserves original expiry')
 c.Remote.OnClientEvent:Fire('death',ctx.Player.Name,nil,'L1Entity');ctx.Player.CharacterAdded:Fire();check(not c.Find('DeathCause').Visible,'respawn closes')
end
for _,dev in ipairs({false,true}) do -- Re-entry and dev entitlement, actual Offer/Items.
 local ctx,c=boot('party',{lastInput='Gamepad',dev=dev})
 ctx:Require('DevAccess').Allowed=dev
 ctx.Player:SetAttribute('InRound',true);ctx.Workspace:SetAttribute('RoundActive',true)
 ctx.Player:SetAttribute('ZyntraReentryCredits',1);ctx.Player:SetAttribute('ZyntraReentryPrice',29);ctx.Player:SetAttribute('ZyntraReentryProductId',77)
 member(ctx,2,'anna_user','Anna',0,false)
 c.Remote.OnClientEvent:Fire('partydown',15,'anna_user');ctx:Flush()
 check(c.Text(c.Find('PartyDownCard'),'PartyDownFallen')=='ANNA FELL','DisplayName faller')
 local primary=c.Find('PartyDownReentry')
 check(not primary.Active,'death mash delay')
 ctx:Advance(0.6);ctx.RunService.RenderStepped:Fire()
 check(primary.Active and c.Navigation.SelectedObject==primary,'primary gamepad focus after arm')
 check(c.Text(primary,'Label')=='USE CREDIT '..B..' 1 OWNED','credit caption')
 primary.Activated:Fire();check(#c.Dispatch.action.Sent==1 and #c.Market.Purchases==0,'stored credit path')
 ctx.Player:SetAttribute('ZyntraReentryCredits',0)
 check(c.Text(primary,'Label')=='REVIVE '..B..' R$ 29 '..B..' 0 OWNED','purchase caption')
 primary.Activated:Fire();primary.Activated:Fire();check(#c.Market.Purchases==1 and not primary.Active,'purchase latch')
 check(c.Text(primary,'Label')=='WAITING FOR ROBLOX...','waiting caption')
 c.Market.PromptProductPurchaseFinished:Fire(ctx.Player.UserId,77,false);check(primary.Active,'cancelled Roblox purchase re-arms')
 ctx.Player:SetAttribute('ZyntraReentryUsed',true);check(not primary.Visible,'ineligible closes slot')
 check(c.Find('PartyDownFreeRespawn').Visible==dev,'developer offer visibility')
 if dev then c.Find('PartyDownFreeRespawn').Activated:Fire();check(c.Commands[1]=='freeRespawn','dev path no purchase') end
 check(c.CAS.Actions.PartyDownDecline('',Enum.UserInputState.Begin)==Enum.ContextActionResult.Sink,'B declines')
 check(ctx.Player:GetAttribute('PartyDownCardOpen')==nil and ctx.Player:GetAttribute('PartyDownWindowOpen')==true,'card/window flags remain distinct')
 ctx.RunService.RenderStepped:Fire();check(c.Label.Text:match('PARTY DOWN')~=nil,'declined countdown')
 c.Remote.OnClientEvent:Fire('partydownclear');check(ctx.Player:GetAttribute('PartyDownWindowOpen')==nil,'server clears ownership')
 c.Remote.OnClientEvent:Fire('partydown',15,nil);ctx:Device({Touch=true});check(not c.Find('CornerBrackets').Visible,'touch brackets removed')
 check(not c.Find('PartyDownFallen').Visible,'nil faller hides line')
 for _,name in ipairs({'PartyDownReentry','PartyDownFreeRespawn','PartyDownDecline'}) do if c.Find(name).Visible then check(c.Find(name).AbsoluteSize.Y>=44,'touch target '..name) end end
end
-- PARTY_GEOMETRY_BEGIN: Real mounted fixture properties, after deferred Stack reflow.
-- The shared fake engine measures size but leaves AbsolutePosition at its origin.
-- Resolve the fixture's scale/offset and anchor chain here; do not substitute
-- hard-coded track positions or depend on a particular centering implementation.
do
 local function rect(node)
  if node:IsA('ScreenGui') then
   local s=node.AbsoluteSize;return {Left=0,Top=0,Right=s.X,Bottom=s.Y,Width=s.X,Height=s.Y}
  end
  local parent=rect(node.Parent)
  local size,p,a=node.AbsoluteSize,node.Position,node.AnchorPoint
  local left=parent.Left+p.X.Scale*parent.Width+p.X.Offset-a.X*size.X
  local top=parent.Top+p.Y.Scale*parent.Height+p.Y.Offset-a.Y*size.Y
  return {Left=left,Top=top,Right=left+size.X,Bottom=top+size.Y,Width=size.X,Height=size.Y}
 end
 local function geometry(c,stage,fraction)
  local card,track,fill=c.Find('PartyDownCard'),c.Find('PartyDownTrack'),c.Find('PartyDownFill')
  local cr,tr,fr=rect(card),rect(track),rect(fill)
  check(tr.Width>0 and tr.Height>0 and tr.Width<cr.Width,stage..' actual imported narrow track')
  check(math.abs((tr.Left+tr.Right-cr.Left-cr.Right)/2)<=0.5,stage..' track centered on actual card')
  check(tr.Left>=cr.Left-0.5 and tr.Right<=cr.Right+0.5,stage..' track inside card horizontally')
  check(tr.Top>=cr.Top-0.5 and tr.Bottom<=cr.Bottom+0.5,stage..' track inside card vertically')
  check(fr.Left>=tr.Left-0.5 and fr.Right<=tr.Right+0.5,stage..' countdown fill contained horizontally')
  check(fr.Top>=tr.Top-0.5 and fr.Bottom<=tr.Bottom+0.5,stage..' countdown fill contained vertically')
  check(math.abs(fr.Left-tr.Left)<=0.5,stage..' fill stays at left edge as it shrinks')
  check(math.abs(fr.Width-tr.Width*fraction)<=0.5,stage..' countdown width follows actual elapsed fraction')
 end
 local cases={
  {Name='full PC',Touch=false,Viewport=Vector2.new(1920,1080)},
  {Name='compact PC',Touch=false,Viewport=Vector2.new(1413,577)},
  {Name='phone',Touch=true,Viewport=Vector2.new(666,374)},
  {Name='tablet',Touch=true,Viewport=Vector2.new(1375,776)},
 }
 for _,device in ipairs(cases) do
  for _,dev in ipairs({false,true}) do
   local ctx,c=boot('party',{touch=device.Touch,viewport=device.Viewport,dev=dev})
   ctx.Player:SetAttribute('InRound',true);ctx.Workspace:SetAttribute('RoundActive',true)
   ctx.Player:SetAttribute('ZyntraReentryCredits',0);ctx.Player:SetAttribute('ZyntraReentryPrice',29)
   ctx.Player:SetAttribute('ZyntraReentryProductId',77)
   c.Remote.OnClientEvent:Fire('partydown',15,'fallen');ctx:Flush()
   local label=device.Name..(dev and ' developer' or ' player')
   geometry(c,label..' initial deferred layout',1)
   ctx:Advance(.6);ctx.RunService.RenderStepped:Fire();ctx:Flush()
   geometry(c,label..' armed offer',14.4/15)
   ctx.Player:SetAttribute('ZyntraReentryCredits',1);ctx:Flush()
   check(c.Text(c.Find('PartyDownReentry'),'Label')=='USE CREDIT '..B..' 1 OWNED',label..' owned state remains canonical')
   geometry(c,label..' owned offer',14.4/15)
   local beforeHeight=c.Find('PartyDownCard'):GetAttribute('HudStackHeight')
   ctx.Player:SetAttribute('ZyntraReentryUsed',true);ctx:Flush()
   check(not c.Find('PartyDownReentry').Visible,label..' ineligible offer hides')
   check(c.Find('PartyDownCard'):GetAttribute('HudStackHeight')<beforeHeight,label..' hidden reentry row closes after defer')
   geometry(c,label..' hidden offer row',14.4/15)
   ctx.Player:SetAttribute('ZyntraReentryUsed',nil);ctx:Flush()
   check(near(c.Find('PartyDownCard'):GetAttribute('HudStackHeight'),beforeHeight),label..' eligible row restores same measured height')
   ctx:Advance(4.4);ctx.RunService.RenderStepped:Fire();ctx:Flush()
   geometry(c,label..' five second countdown',10/15)
   ctx:Device({Touch=not device.Touch})
   geometry(c,label..' device remount preserves deadline',10/15)
   ctx:Advance(10);ctx.RunService.RenderStepped:Fire();ctx:Flush()
   geometry(c,label..' countdown expired',0)
   check(not c.Find('PartyDownReentry').Active,label..' expired offer remains disarmed')
   check(#c.Market.Purchases==0 and #c.Dispatch.action.Sent==0,label..' geometry tests do not award or purchase')
  end
 end
end
-- PARTY_GEOMETRY_END

do -- Results use only the server's roster, truthful counter and existing transport.
 local ctx,c=boot('results',{lastInput='Gamepad'})
 ctx.Player:SetAttribute('InRound',true)
 local anna=member(ctx,2,'anna_user','Anna',100,true)
 local outsider=member(ctx,3,'outside_user','Outsider',100,false)
 c.Remote.OnClientEvent:Fire('resultroster',{Members={{UserId=2,Name='anna_user'}}})
 ctx.Player:SetAttribute('ReduceFlashing',true)
 c.Remote.OnClientEvent:Fire('win',222,1,1,ctx.Now+15,4,7);ctx:Flush()
 check(ctx.Player:GetAttribute('RoundEndingOpen')==true,'fullscreen win owns movement/modal screen')
 check(c.Text(c.Find('PartyChoice1'),'Who')=='Anna','results use DisplayName')
 check(not c.Find('PartyChoice2').Visible,'bystander excluded from actual roster')
 check(c.Flash.BackgroundTransparency==1,'ReduceFlashing disables signal flash')
 check(c.Navigation.SelectedObject==c.Find('ContinueRun'),'result primary focus')
 c.Find('ContinueRun').Activated:Fire();check(c.Remote.Sent[1][1]=='continuenow' and c.Remote.Sent[1][2]==7,'serial transport preserved')
 check(c.Text(c.Find('ContinueRun'),'Label')=='CONTINUING...','pressed text')
 c.Remote.OnClientEvent:Fire('postwinchoices',{Serial=7,Revision=2,Members={{UserId=2,Name='anna_user',Choice='returning'}}})
 check(c.Text(c.Find('PartyChoice1'),'Chip/Label')=='LOBBY','server chosen chip')
 c.Remote.OnClientEvent:Fire('postwinchoices',{Serial=7,Revision=1,Members={}})
 check(c.Find('PartyChoice1').Visible,'stale roster revision ignored')
 ctx:Device({Touch=true});check(c.Text(c.Find('ContinueRun'),'Label')=='CONTINUING...','pressed caption survives device remount')
 check(c.Find('ContinueRun').Size.Y.Offset>=44 and c.Find('ReturnToLobby').Size.Y.Offset>=44,'results touch actions')
 c.Remote.OnClientEvent:Fire('returnpending',8);check(c.Find('ContinueRun').Active,'wrong serial cannot suspend choices')
 c.Remote.OnClientEvent:Fire('returnpending',7);check(not c.Find('ContinueRun').Active and not c.Find('ReturnToLobby').Active,'pending suspends both actions')
 c.Remote.OnClientEvent:Fire('returnfailed',7);check(c.Find('ContinueRun').Active and c.Find('ReturnToLobby').Active,'failed return re-arms live deadline')
 c.Remote.OnClientEvent:Fire('postwinchoices',{Serial=7,Revision=3,Closed=true,Members={{UserId=2,Name='anna_user',Choice='returning'}}})
 c.Remote.OnClientEvent:Fire('postwinchoices',{Serial=7,Revision=4,Closed=false,Members={{UserId=2,Name='anna_user',Choice='continuing'}}})
 check(not c.Find('ContinueRun').Active,'closed choice window stays terminal')
 c.Completion.start(ctx.Now+15,nil,10);ctx:Flush()
 check(not c.Find('ContinueRun').Visible and c.Find('ReturnToLobby').Visible,'server nextLevel exclusively controls continue')
 check(not c.Completion.activate(c.Find('ContinueRun')),'hidden continue never routes final level')
 ctx:Advance(15);ctx.RunService.RenderStepped:Fire();check(not c.Find('ReturnToLobby').Active,'deadline disarms action')
 c.Remote.OnClientEvent:Fire('escape',ctx.Player.Name)
 check(ctx.Player:GetAttribute('RoundEndingOpen')==false,'temporary own escape does not block spectate cycle')
 check(c.Text(c.Find('ResultsWindow'),'Head/EndingTitle')=='YOU GOT OUT','escape never SIGNAL LOST')
 ctx:Advance(0.1);c.Hide(true);ctx:Advance(4);check(not c.Frame.Visible,'old escape timer cannot restore result')
 check(ctx.Player:GetAttribute('RoundEndingOpen')==false,'immediate hide clears screen ownership')
end

do -- Fullscreen ownership survives fades and serial replacement, but not temporary escape.
 local ctx,c=boot('results',{touch=true})
 c.Show('LEVEL 1 CLEARED','TIME 00:10  •  SURVIVORS 1/1','RETURNING',nil,false)
 check(ctx.Player:GetAttribute('RoundEndingOpen')==true,'fullscreen owns screen immediately')
 c.Hide(false);ctx:Advance(.45)
 check(c.Frame.Visible and ctx.Player:GetAttribute('RoundEndingOpen')==true,'fade keeps ownership until actual hide')
 ctx:Advance(.02)
 check(not c.Frame.Visible and ctx.Player:GetAttribute('RoundEndingOpen')==false,'completed fade releases ownership')
 c.Completion.reset();check(ctx.Player:GetAttribute('RoundEndingOpen')==false,'hidden reset clears ownership')
 c.Show('NO ONE FOUND A WAY OUT','','',nil,false);c.Hide(false);ctx:Advance(.1)
 c.Show('LEVEL 3 CLEARED','','',nil,false);ctx:Advance(.5)
 check(c.Frame.Visible and ctx.Player:GetAttribute('RoundEndingOpen')==true,'stale fade cannot release replacement result')
 c.Hide(true);check(not c.Frame.Visible and ctx.Player:GetAttribute('RoundEndingOpen')==false,'immediate replacement hide releases')
 c.Show('YOU GOT OUT','','WAITING FOR THE OTHERS',nil,true)
 check(c.Frame.Visible and ctx.Player:GetAttribute('RoundEndingOpen')==false,'temporary escape is not fullscreen input owner')
 ctx:Advance(3.3);check(not c.Frame.Visible and ctx.Player:GetAttribute('RoundEndingOpen')==false,'temporary escape fade leaves screen free')
end
do -- Truthful loss snapshot and a bounded six-person roster at the real phone safe area.
 local ctx,c=boot('results',{touch=true,viewport=Vector2.new(844,390),safe={Left=59,Top=64,Right=785,Bottom=357,Width=726,Height=293}})
 ctx.Player:SetAttribute('InRound',true)
 local roster={}
 for i=1,6 do member(ctx,i+1,'party'..i,'Party '..i,0,false);roster[i]={UserId=i+1,Name='party'..i} end
 local Hud=ctx:Require('RoundHud')
 Hud.SetObjective({Level=2,Eyebrow='LEVEL 2',Title='START THE PUMPS',Count=2,Goal=3,Tag='PUMP STATIONS',Lines={}})
 Hud.Clear()
 c.Remote.OnClientEvent:Fire('resultroster',{Members=roster})
 c.Remote.OnClientEvent:Fire('lose',222,0,6);ctx:Flush()
 check(c.Text(c.Find('Stat_Counter'),'Label')=='PUMP STATIONS','loss snapshot label survives Clear')
 check(c.Text(c.Find('Stat_Counter'),'Num')=='2/3','loss snapshot count survives Clear')
 check(c.Find('PartyChoices').ScrollingEnabled,'six players scroll in bounded roster')
 check(c.Find('ResultsWindow'):GetAttribute('HudStackHeight')<=293,'actual imported six-row results stay in phone safe height')
 check(c.Find('PartyChoice6').Visible,'sixth party member retained')
 c.Completion.start(ctx.Now+15,4,9);ctx:Flush()
 check(c.Find('ContinueRun').AbsoluteSize.Y>=44 and c.Find('ReturnToLobby').AbsoluteSize.Y>=44,'phone result hit targets')
end
do -- Spectate presentation, target replication, modal gates, no second counter.
 local ctx,c=boot('spectate')
 ctx.Workspace:SetAttribute('RoundActive',true)
 local a=member(ctx,2,'anna_user','Anna',100,false)
 local b=member(ctx,3,'jonas_user','Jonas',100,false)
 c.Start();check(c.Text(c.Find('SpectateBand'),'Who')=='Anna','watch DisplayName')
 check(ctx.Player:GetAttribute('SpectateTargetUserId')==2,'target replication retained')
 c.Find('SpectateNext').Activated:Fire();check(ctx.Player:GetAttribute('SpectateTargetUserId')==3,'touch cycle real watch')
 ctx.Player:SetAttribute('PartyDownCardOpen',true);c.Find('SpectateNext').Activated:Fire()
 check(ctx.Player:GetAttribute('SpectateTargetUserId')==3,'party blocks camera cycling')
 ctx.Player:SetAttribute('PartyDownCardOpen',nil);ctx:Device({Touch=true})
 check(c.Find('SpectatePrevious').Size.Y.Offset==44,'spectate touch hit target')
 c.Find('SpectateBackToLobby').Activated:Fire();check(c.Prompts()==1,'leave prompt bridge retained')
 for _,n in ipairs(c.Find('SpectateBand'):GetDescendants()) do
  if n:IsA('Frame') then check(n.BackgroundTransparency==1,'no spectate plate') end
  if n:IsA('TextLabel') then check(n:FindFirstChildOfClass('UIStroke').Thickness==1.5,'text contextual stroke') end
 end
 check(c.Find('SpectatorCounter')==nil,'counter removed')
 a.Character:FindFirstChildOfClass('Humanoid').Health=0;b.Character:FindFirstChildOfClass('Humanoid').Health=0
 c.Watch(1);check(c.Text(c.Find('SpectateBand'),'Who')=='NO ONE LEFT TO WATCH','empty copy')
 c.Stop();check(ctx.Player:GetAttribute('SpectateTargetUserId')==nil,'stop clears target')
end

do -- Actual touch Back target clears activation regions without shrinking or moving the band.
 local ctx,c=boot('spectate',{touch=true,viewport=Vector2.new(666,374),safe={Left=0,Top=0,Right=666,Bottom=316,Width=666,Height=316}})
 local zones={Thumbstick={Left=0,Top=66.6,Right=266,Bottom=316},Controls={Left=666,Top=316,Right=666,Bottom=316},Jump={Left=546,Top=196,Right=666,Bottom=316}}
 ctx.UIDevice.Layout=function() return {IsTouch=ctx.Touch,Safe=ctx.Safe,Zones=zones} end
 ctx.Workspace:SetAttribute('RoundActive',true)
 member(ctx,2,'anna_user','Anna',100,false);member(ctx,3,'jonas_user','Jonas',100,false)
 c.Start();ctx:Flush()
 local function bounds(node)
  -- The fixture computes authored size; its AbsolutePosition is deliberately static.
  -- These mounted roots share the display-origin ScreenGui, so resolve production offsets/anchors.
  local left=node.Position.X.Offset-node.AnchorPoint.X*node.AbsoluteSize.X
  local top=node.Position.Y.Offset-node.AnchorPoint.Y*node.AbsoluteSize.Y
  return {Left=left,Top=top,Right=left+node.AbsoluteSize.X,Bottom=top+node.AbsoluteSize.Y}
 end
 local function hits(a,b) return b.Right>b.Left and b.Bottom>b.Top and a.Left<b.Right and a.Right>b.Left and a.Top<b.Bottom and a.Bottom>b.Top end
 local target=c.Find('SpectateBackToLobby');local rect=bounds(target);local band=bounds(c.Find('SpectateBand'))
 check(target.AbsoluteSize.X==240 and target.AbsoluteSize.Y==44,'native666 Back keeps full240x44 activation target')
 check(rect.Left==274,'Back prefers horizontal eightpx gap after native thumbstick: '..rect.Left..'/'..rect.Top..'/'..rect.Right..'/'..rect.Bottom)
 check(rect.Bottom<band.Top,'shifted Back remains above transparent navigation band')
 for name,zone in pairs(zones) do check(not hits(rect,zone),'shifted Back clear of '..name) end
 target.Activated:Fire();check(c.Prompts()==1,'shifted actual button still routes exit prompt')
 zones.Thumbstick.Right=616;ctx:Device({Touch=true});ctx:Flush()
 target=c.Find('SpectateBackToLobby');rect=bounds(target)
 check(rect.Top>=0 and rect.Bottom<zones.Thumbstick.Top,'no horizontal room falls above activation region')
 check(target.AbsoluteSize.X==240 and target.AbsoluteSize.Y==44,'fallback never shrinks target')
 for name,zone in pairs(zones) do check(not hits(rect,zone),'fallback Back clear of '..name) end
 zones.Controls={Left=360,Top=160,Right=600,Bottom=316};zones.Thumbstick.Right=266;ctx:Device({Touch=true})
 rect=bounds(c.Find('SpectateBackToLobby'))
 for name,zone in pairs(zones) do check(not hits(rect,zone),'crowded Back clear of '..name) end
 ctx.Player:SetAttribute('RoundEndingOpen',true);ctx:Device({Touch=true})
 check(not c.Find('SpectateBackToLobby').Visible and not c.Find('SpectateNext').Active,'fullscreen result suppresses actual spectate buttons')
 local before=ctx.Player:GetAttribute('SpectateTargetUserId');c.Find('SpectateNext').Activated:Fire()
 check(ctx.Player:GetAttribute('SpectateTargetUserId')==before,'fullscreen modal cannot cycle camera target')
 ctx.Player:SetAttribute('RoundEndingOpen',false);ctx:Device({Touch=true});c.Find('SpectateNext').Activated:Fire()
 check(ctx.Player:GetAttribute('SpectateTargetUserId')~=before,'released result restores normal target cycle')
end
do -- The old hidden subtitle plate never owns the text clock or rendered cue.
 local ctx,c=boot('caption')
 ctx.Player:SetAttribute('InRound',true)
 c.Dispatch.subtitleCopy='The circuit is ready.'
 c.Refresh();ctx:Flush()
 check(c.Dispatch.panel.Visible==false,'old CommandSubtitles stays hidden')
 check(c.Dispatch.captionSent=='The circuit is ready.','accepted caption recorded')
 local clock=c.Clock();ctx:Advance(0.5)
 check(near(c.Position(clock,{}),0.5),'text-only muted clock advances with the new visible caption')
 c.Modal(true);c.Refresh();ctx:Advance(1)
 check(near(c.Position(clock,{}),0.5),'source modal pauses text clock')
 c.Modal(false);c.Refresh();ctx:Advance(0.5)
 check(near(c.Position(clock,{}),1),'closing modal resumes caption clock')
 ctx.Player:SetAttribute('CaptionsEnabled',false);c.Dispatch.subtitleCopy='Suppressed cue';c.Refresh()
 check(c.Dispatch.captionSent~='Suppressed cue','rejected delivery not cached')
 ctx:Advance(0.5);check(near(c.Position(clock,{}),1.5),'disabled captions never stall the transport')
 ctx.Player:SetAttribute('CaptionsEnabled',true);c.Refresh()
 check(c.Dispatch.captionSent=='Suppressed cue','same cue retries after caption permission returns')
end
print('HUD B8: '..checks..' checks passed (actual controller blocks and actual imported fixture)')
'''


def program():
    source = ROUND.read_text(encoding="utf-8")
    spectate = SPECTATE.read_text(encoding="utf-8")
    before = ROOT / "_local/hud-final/codex-takeover/before/StarterPlayer/StarterPlayerScripts/SpectateController.LocalScript.lua"
    if before.exists():
        baseline = before.read_text(encoding="utf-8")
        for start, stop in (("local reportedTarget = false", "local gui = Instance.new"),
                            ("-- drive the POV camera", "-- The label was a fixed"),
                            ("local function syncSpectateForEscape()", "UIS.InputBegan:Connect")):
            current_stop = "applySpectateLayout = function()" if start == "-- drive the POV camera" else stop
            assert section(baseline,start,stop).strip() == section(spectate,start,current_stop).strip(), "spectate ownership drift: " + start
    snippets = {
        "LOADING": section(source, "local LOADING_PALETTES = ", "-- Full-screen round payoff."),
        "RESULTS_UI": section(source, "local endTitle = nil", "-- C_ONE_SPECTATE_CAMERA_20260904: the SpectateBanner"),
        "RESULTS_LOGIC": section(source, "function completion.reset()", "-- AUDIT_FIX_20260924 (Codex review): a pad picked up"),
        "ENDING": section(source, "local function hideRoundEnding(immediate)", "\nif RunService:IsStudio() then"),
        "RESULT_EVENTS": section(source, '\telseif ev == "escape" then', "\nend)\n\n-- ").replace("elseif", "if", 1),
        "PARTY": section(source, "-- HUD_B8_PARTY_DOWN:", "-- WHAT KILLED YOU,"),
        "DEATH": section(source, "-- HUD_B8_DEATH:", "-- Announce readiness only after"),
        "CAPTION_CLOCK": section(source, "function dispatchAudio.newCaptionClock()", "function dispatchAudio.refresh()"),
        "CAPTION_REFRESH": section(source, "function dispatchAudio.refresh()", "function dispatchAudio.requestToggle()"),
        "REPORT_TARGET": section(spectate, "local reportedTarget = false", "local gui = Instance.new"),
        "BAND": section(spectate, "local label, prevButton", "local SMOOTH = 11"),
        "LIVING": section(spectate, "local function cycleAvailable()", "-- borrowed flashlight:"),
        "WATCH": section(spectate, "local function watch(i)", "-- drive the POV camera"),
        "BAND_LAYOUT": section(spectate, "applySpectateLayout = function()", "local function startSpectate()"),
        "SPECTATE_STATE": section(spectate, "local function startSpectate()", "local function onChar(char)"),
        "SPECTATE_INPUT": section(spectate, "UIS.InputBegan:Connect(function(input, processed)", "-- if the teammate you're watching"),
    }
    wrapper = SETUP
    for marker, code in snippets.items():
        wrapper = wrapper.replace("__" + marker + "__", code)
    paths = dict(SOURCES)
    paths["DeathAdvice"] = ROOT / "ReplicatedStorage/DeathAdvice.ModuleScript.lua"
    paths["LoadingCardView"] = ROOT / "ReplicatedStorage/LoadingCardView.ModuleScript.lua"
    modules = {name: path.read_text(encoding="utf-8") for name, path in paths.items()}
    # DevAccess is an entitlement boundary, never reimplemented in product code.
    modules["DevAccess"] = "local A={Allowed=false};function A.IsAllowed() return A.Allowed end;return A"
    # Expose the fake engine's signal factory only to the test controller environment.
    wrapper = wrapper.replace("return function(ctx, mode)", "local signal=TEST_SIGNAL\nreturn function(ctx, mode)", 1)
    modules["B8Controller"] = wrapper
    fixtures = trees()
    fixtures["HUD_Screens"] = json.loads((DUMPS / "framewisp-dump.HUD_Screens.json").read_text(encoding="utf-8"))["root"]
    injection = "local SOURCES=" + lua(modules) + "\nlocal TREES=" + lua(fixtures)
    harness = HARNESS.read_text(encoding="utf-8").replace("--@@INJECT@@", injection)
    # The shared harness owns no B8 service surface. This test adds one test-only
    # dependency to its module environment without changing the shared file.
    harness = harness.replace("game = game, workspace = ctx.Workspace", "TEST_SIGNAL = signal, game = game, workspace = ctx.Workspace", 1)
    harness = harness.replace("function methods:IsA(class)", "function methods:IsDescendantOf(ancestor) local p=self.Parent;while p do if p==ancestor then return true end;p=p.Parent end;return false end\nfunction methods:IsA(class)", 1)
    return harness + TESTS


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no checks executed.")
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile" + Path(binary).suffix))
    for path in (ROUND, SPECTATE):
        subprocess.run([compiler, "--null", str(path)], check=True, timeout=30)
    with tempfile.TemporaryDirectory(prefix="hud-b8-") as directory:
        path = Path(directory) / "hud_b8.luau"
        path.write_text(program(), encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=120)


if __name__ == "__main__":
    main()
