"""Run ZyntraStore's real DEV admission, placement and geometry subscriptions.

Covers native touch+pointer mismatch, both ForceTouch override directions,
44px fallback target, objective tap-target admission, table warning exclusions,
and late mounted HUD/device changes. No Studio or remotes are used.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[2]
source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua"
source = source_path.read_text(encoding="utf-8")
device = (ROOT / "ReplicatedStorage/UIDevice.ModuleScript.lua").read_text(encoding="utf-8")
def section(text, first, last):
    begin = text.index(first)
    return text[begin:text.index(last, begin)]
production = section(source, "local function updateVisibility()", '\nplayer:GetAttributeChangedSignal("InRound")')
watch_start = "-- Objective expansion and table warnings can change the reserved footprint"
watch = section(source, watch_start, "\n-- The L4 graft can land") if watch_start in source else ""
classification = section(device, "local function forcedTouch()", "\n-- The same idea") + "\n" + section(device, "local function computeTouchFormFactor()", "\nlocal touchFormFactor")
lua = r"""
local checks=0
local function ok(value,message) checks+=1; assert(value,message) end
local function signal()
 local handlers={}
 return {Connect=function(_,f)table.insert(handlers,f) end,Fire=function(_,...)for _,f in ipairs(handlers) do f(...) end end}
end
local function dim(sx,ox,sy,oy)
 return setmetatable({X={Scale=sx,Offset=ox},Y={Scale=sy,Offset=oy}}, {__add=function(a,b)return dim(a.X.Scale+b.X.Scale,a.X.Offset+b.X.Offset,a.Y.Scale+b.Y.Scale,a.Y.Offset+b.Y.Offset) end})
end
local UDim2={new=dim,fromOffset=function(x,y)return dim(0,x,0,y) end}
local UserInputService={TouchEnabled=true,KeyboardEnabled=true,MouseEnabled=true}
local forced
local worldAttrs={RoundActive=true}
local workspace={GetAttribute=function(_,key)if key=='ForceTouchUI' then return forced end;return worldAttrs[key] end}
local RunService={IsStudio=function()return true end}
local typeof=type
--@@CLASSIFY@@
local queued={}
local task={defer=function(f)table.insert(queued,f) end}
local function flush() while #queued>0 do local work=queued;queued={};for _,f in ipairs(work)do f()end end end
local function node(name,width,height,x,y,anchorX)
 local n={Name=name,Visible=true,Enabled=true,Children={},Size=UDim2.fromOffset(width or 0,height or 0),Position=UDim2.fromOffset(x or 0,y or 0),AnchorPoint={X=anchorX or 0,Y=0},Signals={},DescendantAdded=signal()}
 function n:FindFirstChild(name,recursive)
  if self.Children[name] then return self.Children[name] end
  if recursive then for _,child in pairs(self.Children) do local found=child:FindFirstChild(name,true);if found then return found end end end
 end
 function n:IsA(c)return c=='GuiObject' end
 function n:GetPropertyChangedSignal(key) self.Signals[key]=self.Signals[key] or signal();return self.Signals[key] end
 function n:GetChildren()return {} end
 function n:GetDescendants()local found={};for _,child in pairs(self.Children) do table.insert(found,child);for _,d in ipairs(child:GetDescendants())do table.insert(found,d)end end;return found end
 function n:SetAttribute()end
 return n
end
local function attach(owner,child)owner.Children[child.Name]=child;child.Parent=owner end
local playerGui=node('PlayerGui')
local hud=node('RoundHud');attach(playerGui,hud)
hud.IsA=function(_,class)return class=='ScreenGui' end
local objective=node('ObjectiveCard',260,210,388,18);attach(hud,objective)
local marker=node('NoiseMarker',146,24,267,294);marker.AnchorPoint.Y=1;marker.Visible=false;attach(hud,marker)
marker.GroupTransparency=1;marker.IsA=function(_,class)return class=='CanvasGroup' or class=='GuiObject' end
local hiding=node('Level3TableHideUI');attach(playerGui,hiding);hiding.Enabled=false
 hiding.IsA=function(_,class)return class=='ScreenGui' end
local exitGui=node('RoundExitGui');attach(playerGui,exitGui)
exitGui.IsA=function(_,class)return class=='ScreenGui' end
local door=node('LeaveChipTouch',44,44,12,6);attach(exitGui,door);door.Visible=false
local banner=node('HiddenStatus',260,30,333,14,.5);attach(hiding,banner)
local leave=node('LeaveHiding',180,44,333,54,.5);attach(hiding,leave)
local warning=node('TableCheck',260,40,333,50,.5);attach(hiding,warning);warning.Visible=false
local attributes={InRound=true,LobbyMusicEnabled=true}
local player={GetAttribute=function(_,key)return attributes[key] end,SetAttribute=function(_,key,value)attributes[key]=value end,FindFirstChild=function(_,key)return key=='PlayerGui' and playerGui or nil end,WaitForChild=function()return playerGui end}
local gui={DisplayOrder=55}
local function button(name)
 local b=node(name);b.Children.SquareSectionBorder={Enabled=true};b.SectionButtonContent={Visible=true};return b
end
local shopButton,openButton,rewardsButton,wheelButton,musicButton=button('shop'),button('open'),button('rewards'),button('wheel'),button('music')
local railButtons={shopButton,openButton,rewardsButton,wheelButton,musicButton}
local openButtonOutline={}
local COLORS={bg='bg'}
local TOUCH_MIN_TAP_HEIGHT=44
local devAllowed=true
local modal=false
local function modalBlocksStore()return false end
local function syncRewardsIntro()end
local function updateReentry()end
local function layoutSquareSections()return 192 end
local Enum={ApplyStrokeMode={Contextual='Contextual'}}
local layout={Class='phone',Safe={Left=0,Top=0,Right=666,Bottom=374},SafeLeft=0,
 Zones={Controls={Left=476,Top=300,Right=666,Bottom=374},Thumbstick={Left=0,Top=230,Right=180,Bottom=374},Jump={Left=600,Top=300,Right=666,Bottom=374}}}
local UIDevice={Layout=function() layout.IsTouch=computeTouchFormFactor();return layout end,ScreenOwningModalOpen=function()return modal end}
function UIDevice.SetInteractive(b,value)b.Visible=value;b.Active=value;b.Selectable=value end
function UIDevice.LocalPosition(_,x,y)return UDim2.fromOffset(math.floor(x),math.floor(y)) end
function UIDevice.LocalOffset(screen,x,y)return x-(screen.OriginX or 0),y-(screen.OriginY or 0) end
function UIDevice.TopRightPanel(width,height)
 local top,right=18,648
 height=math.min(height,layout.Zones.Controls.Top-8-top)
 return {Left=right-width,Right=right,Top=top,Bottom=top+height,Width=width,Height=height}
end
--@@PRODUCTION@@
--@@WATCH@@
flush()
local function rect(n)
 local ox,oy=UIDevice.LocalOffset(n.Parent or {},0,0)
 local left=n.Position.X.Offset-ox-n.AnchorPoint.X*n.Size.X.Offset
 local top=n.Position.Y.Offset-oy-n.AnchorPoint.Y*n.Size.Y.Offset
 return {Left=left,Top=top,Right=left+n.Size.X.Offset,Bottom=top+n.Size.Y.Offset}
end
local function hits(a,b)return a.Left<b.Right and a.Right>b.Left and a.Top<b.Bottom and a.Bottom>b.Top end
local function clearOf(n,message)ok(not hits(rect(openButton),rect(n)),message)end
local function target(message)ok(openButton.Visible and openButton.Active and openButton.Selectable,message..' is reachable');ok(openButton.Size.X.Offset>=44 and openButton.Size.Y.Offset>=44,message..' keeps44px minimum') end
-- Actual native emulator reports all three inputs, while unified layout is desktop.
forced=nil;UserInputService.TouchEnabled=true;UserInputService.MouseEnabled=true;UserInputService.KeyboardEnabled=true
updateVisibility();ok(not layout.IsTouch,'actual classifier returns desktop with mouse+keyboard');ok(not openButton.Visible and not openButton.Active and not openButton.Selectable,'raw TouchEnabled must not admit desktop-size DEV chip')
-- Forced desktop matrix has the same rule even on a physically touch host.
forced=false;UserInputService.MouseEnabled=false;updateVisibility();ok(not openButton.Visible,'ForceTouch=false keeps desktop keyboard route')
-- Forced touch fixture must still show the chip on a pointer-only test host.
forced=true;UserInputService.TouchEnabled=false;updateVisibility();target('forced touch DEV');ok(openButton.Size.Y.Offset==44,'DEV target remains44px');clearOf(objective,'actual210px objective expansion stays clear')
-- Actual handheld with a Bluetooth keyboard but no mouse remains touch.
forced=nil;UserInputService.TouchEnabled=true;UserInputService.KeyboardEnabled=true;UserInputService.MouseEnabled=false;updateVisibility();target('actual handheld DEV');clearOf(objective,'actual handheld clears current objective')
-- Real hiding roots occupy upper middle; obsolete fallback spots are blocked.
layout.Zones.Controls.Top=232;layout.Zones.Jump.Top=232
hiding.Enabled=true;warning.Visible=true
updateVisibility();target('hiding DEV');clearOf(banner,'hiding banner excluded');clearOf(leave,'leave chip excluded');clearOf(warning,'table warning excluded');ok(not hits(rect(openButton),layout.Zones.Controls),'controls excluded');ok(not hits(rect(openButton),layout.Zones.Thumbstick),'thumbstick excluded')
-- The actual leave-door chip owns the former far-left fallback.
local beforeDoor=openButton.Position.Y.Offset;local beforeDoorX=openButton.Position.X.Offset
door.Visible=true;door:GetPropertyChangedSignal('Visible'):Fire();flush()
target('hiding DEV with door');clearOf(door,'actual44px door chip excluded');clearOf(leave,'door fallback also clears hiding leave');ok(openButton.Position.Y.Offset~=beforeDoor or openButton.Position.X.Offset~=beforeDoorX,'door visibility republishes placement '..beforeDoorX..','..beforeDoor..' -> '..openButton.Position.X.Offset..','..openButton.Position.Y.Offset)
door.Visible=false;door:GetPropertyChangedSignal('Visible'):Fire();flush()
ok(openButton.Position.Y.Offset==beforeDoor,'hidden door releases its reserved slot')
local newDoor=node('LeaveChipTouch',44,44,12,6);attach(exitGui,newDoor);playerGui.DescendantAdded:Fire(newDoor);flush()
target('remounted door DEV');clearOf(newDoor,'late mounted door is excluded immediately')
newDoor.Visible=false;newDoor:GetPropertyChangedSignal('Visible'):Fire();flush()
ok(openButton.Position.Y.Offset==beforeDoor,'remounted door keeps visibility subscription')
-- Shared GUI origins follow UIDevice, not native host pixels under a fixture.
hiding.OriginX=32;hiding.OriginY=58
banner.Position=UDim2.fromOffset(198,-44);leave.Position=UDim2.fromOffset(198,-4);warning.Position=UDim2.fromOffset(198,-8)
updateVisibility();clearOf(banner,'fixture origin preserves banner exclusion');clearOf(leave,'fixture origin preserves leave exclusion')
-- Modal hiding and developer authorization remain authoritative.
modal=true;updateVisibility();ok(not openButton.Visible and not openButton.Active,'modal hides DEV input');modal=false;devAllowed=false;updateVisibility();ok(not openButton.Visible,'non-developer never gets DEV');devAllowed=true
-- Geometry watchers must refresh without changing device or InRound.
hiding.Enabled=false;layout.Zones.Controls.Top=300;layout.Zones.Jump.Top=300;objective.Size=UDim2.fromOffset(260,44);updateVisibility();local before=openButton.Position.Y.Offset
objective.Size=UDim2.fromOffset(260,210);objective:GetPropertyChangedSignal('Size'):Fire();flush();ok(openButton.Position.Y.Offset~=before,'objective expansion republishes DEV placement');clearOf(objective,'watcher clears expanded objective')
-- Imported device remount creates a new root, watched through real DescendantAdded.
local nextObjective=node('ObjectiveCard',260,240,388,18);attach(hud,nextObjective);playerGui.DescendantAdded:Fire(nextObjective);flush();clearOf(nextObjective,'late imported root immediately repositions DEV');target('remounted DEV')
nextObjective.Size=UDim2.fromOffset(260,44);nextObjective:GetPropertyChangedSignal('Size'):Fire();flush();local short=openButton.Position.Y.Offset
nextObjective.Size=UDim2.fromOffset(260,210);nextObjective:GetPropertyChangedSignal('Size'):Fire();flush();ok(openButton.Position.Y.Offset~=short,'remounted root keeps geometry subscriptions')
-- Marker exclusions use its bottom anchor and follow dynamic width/state changes.
local markerBeforeX,markerBeforeY=openButton.Position.X.Offset,openButton.Position.Y.Offset
marker.Position=UDim2.fromOffset(markerBeforeX,markerBeforeY+24);marker.Visible=true
marker:GetPropertyChangedSignal('Visible'):Fire();flush()
target('DEV with visible marker');clearOf(marker,'bottom anchored drawn noise marker excluded')
clearOf(marker,'visible alpha1 marker reserves incoming fade bounds')
local incomingX,incomingY=openButton.Position.X.Offset,openButton.Position.Y.Offset
marker.GroupTransparency=.45
clearOf(marker,'later fade with unchanged geometry stays clear without another signal')
ok(openButton.Position.X.Offset==incomingX and openButton.Position.Y.Offset==incomingY,'fade transition needs no per-frame placement watcher')
ok(openButton.Position.X.Offset~=markerBeforeX or openButton.Position.Y.Offset~=markerBeforeY,'marker visibility republishes DEV placement')
marker.Visible=false;marker:GetPropertyChangedSignal('Visible'):Fire();flush()
ok(openButton.Position.X.Offset==markerBeforeX and openButton.Position.Y.Offset==markerBeforeY,'hidden marker releases reserved position')
local mountedMarker=node('NoiseMarker',146,24,markerBeforeX,markerBeforeY+24);mountedMarker.AnchorPoint.Y=1
attach(hud,mountedMarker);playerGui.DescendantAdded:Fire(mountedMarker);flush()
target('DEV with remounted marker');clearOf(mountedMarker,'new marker root reserved immediately')
mountedMarker.Position=UDim2.fromOffset(openButton.Position.X.Offset,openButton.Position.Y.Offset+24)
mountedMarker:GetPropertyChangedSignal('Position'):Fire();flush();clearOf(mountedMarker,'marker bounds change repositions DEV')
mountedMarker.Visible=false;mountedMarker:GetPropertyChangedSignal('Visible'):Fire();flush()
-- Only an actual enabled, parented objective tap target replaces the fallback.
-- The earlier objective fixtures intentionally lacked Hit and kept their geometry checks.
local function chipHidden(message)
 ok(not openButton.Visible and not openButton.Active and not openButton.Selectable,message)
end
local function change(n,key,value)n[key]=value;n:GetPropertyChangedSignal(key):Fire();flush() end
local function remove(owner,child)
 owner.Children[child.Name]=nil;child.Parent=nil;child:GetPropertyChangedSignal('Parent'):Fire();flush()
end
local function mount(owner,child)
 attach(owner,child);playerGui.DescendantAdded:Fire(child);child:GetPropertyChangedSignal('Parent'):Fire();flush()
end
nextObjective.IsA=function(_,class)return class=='CanvasGroup' or class=='GuiObject' end
local content=node('ObjectiveCard',192,44);mount(nextObjective,content)
local bar=node('Bar',192,32);mount(content,bar)
target('objective without Hit fallback')
local hit=node('Hit',192,44);hit.Active=true
hit.IsA=function(_,class)return class=='GuiButton' or class=='GuiObject' end
mount(bar,hit)
chipHidden('living objective with enabled physical Hit replaces the phone chip')
nextObjective.GroupTransparency=1;updateVisibility()
chipHidden('incoming objective fade does not flicker the fallback chip')
nextObjective.GroupTransparency=.8;updateVisibility()
chipHidden('ordinary objective opacity does not govern dev admission')
change(content,'Visible',false);target('hidden imported content frame fallback')
change(content,'Visible',true);chipHidden('shown imported content frame retakes route')
remove(nextObjective,content);target('removed imported content frame fallback')
mount(nextObjective,content);chipHidden('reparented imported content frame retakes route')
change(nextObjective,'Visible',false);target('hidden/hiding/dead objective fallback')
change(nextObjective,'Visible',true);chipHidden('shown objective takes back dev admission')
change(hud,'Enabled',false);target('disabled HUD fallback')
change(hud,'Enabled',true);chipHidden('enabled HUD takes back dev admission')
remove(hud,nextObjective);target('removed objective restores fallback through Parent signal')
mount(hud,nextObjective);chipHidden('reparented objective retakes phone route')
remove(playerGui,hud);target('removed HUD restores fallback through owner Parent signal')
mount(playerGui,hud);chipHidden('reparented HUD retakes phone route')
change(bar,'Visible',false);target('hidden Bar fallback')
change(bar,'Visible',true);chipHidden('visible Bar retakes phone route')
change(hit,'Visible',false);target('hidden Hit fallback')
change(hit,'Visible',true);chipHidden('visible Hit retakes phone route')
change(hit,'Active',false);target('inactive Hit fallback')
change(hit,'Active',true);chipHidden('active Hit retakes phone route')
remove(bar,hit);target('removed Hit fallback')
mount(bar,hit);chipHidden('late remounted Hit retakes phone route')
worldAttrs.RoundActive=false;updateVisibility();target('inactive round keeps fallback')
worldAttrs.RoundActive=true;updateVisibility();chipHidden('live round retakes objective route')
forced=false;updateVisibility();chipHidden('PC retains keyboard route with live objective')
forced=true;updateVisibility();chipHidden('touch override retains objective route')
devAllowed=false;change(nextObjective,'Visible',false);chipHidden('non-dev gets no hidden-objective fallback')
change(nextObjective,'Visible',true);chipHidden('non-dev gets no objective replacement chip')
devAllowed=true;modal=true;change(nextObjective,'Visible',false);chipHidden('modal still blocks fallback')
modal=false;updateVisibility();target('closing modal restores fallback without an objective')
change(nextObjective,'Visible',true);chipHidden('closing modal with live objective retires fallback again')
-- Actual results own the screen even after InRound clears; own rail windows still allow switching.
attributes.InRound=nil;attributes.RoundEndingOpen=true;modal=true;updateVisibility()
for _,entry in ipairs(railButtons)do ok(not entry.Visible and not entry.Active and not entry.Selectable,'results hide '..entry.Name..' rail input')end
attributes.RoundEndingOpen=false;updateVisibility()
for _,entry in ipairs(railButtons)do ok(entry.Visible and entry.Active and entry.Selectable,'own lobby window retains '..entry.Name..' switching')end
ok(gui.DisplayOrder==119,'own rail window keeps authored upper layer')
attributes.RoundEndingOpen=true;attributes.InRound=true;updateVisibility()
ok(not openButton.Visible and not openButton.Active,'results also hide in-round DEV')
attributes.RoundEndingOpen=false;modal=false
print('ok '..checks..' Zyntra DEV chip runtime checks')
""".replace("--@@CLASSIFY@@",classification).replace("--@@PRODUCTION@@",production).replace("--@@WATCH@@",watch)
binary=os.environ.get('LUAU_BIN')
assert binary and Path(binary).is_file(),'Set LUAU_BIN to the available Luau interpreter'
with tempfile.TemporaryDirectory(prefix='zyntra-dev-chip-') as directory:
    script=Path(directory)/'dev-chip.luau';script.write_text(lua,encoding='utf-8')
    result=subprocess.run([binary,str(script)],capture_output=True,text=True,encoding='utf-8')
    if result.returncode:raise SystemExit(result.stdout+result.stderr)
    print(result.stdout.strip())
