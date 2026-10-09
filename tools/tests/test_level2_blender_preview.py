"""Offline executable checks of the Level 2 Poolrooms developer-preview contract; no Git, Studio or network.

The preview code has lived in ServerScriptService/GameManager.Script.lua since a157fe6 (the old
drafts/level2-blender diff no longer applies and is not read). This lifts the CURRENT manager's
sections and runs them against fake services:
  * the Level2BlenderPreviewLaunch bindable (DevAccess gate, level2BlenderPreviewReady, busy/queue
    refusals, the Studio local launch that sets and always clears Level2BlenderPreviewActive, and the
    public-lobby reserved-server TeleportData packet with Level2BlenderPreview = true, capped at 2);
  * the reserved-server arrival that honours that packet only for an all-DevAccess party on Level 2;
  * no Continue and no completion award on a preview win;
  * boot and both cleanups clear Level2BlenderPreviewActive;
then runs the full Round Adapter against fake services and compiles the manager and adapter at -O0.
Level 1 has no preview any more (860a5ce removed it on purpose); nothing here depends on it.
Engine/gameplay checks remain in Studio.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MANAGER = ROOT / "ServerScriptService/GameManager.Script.lua"
ADAPTER = ROOT / "ServerScriptService/Level 2 Systems/Level 2 Round Adapter.ModuleScript.lua"


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


MANAGER_MOCK = r'''
local checks=0
local function check(value,label) checks+=1; assert(value,label) end
-- Fake Instances are tables; DevAccess must see Roblox's Instance type.
local function typeof(value) return type(value)=="table" and value.ClassName and "Instance" or type(value) end
local function instance(class,name)
 local o={ClassName=class,Name=name,children={},attrs={}}
 function o:IsA(kind) return self.ClassName==kind end
 function o:FindFirstChild(key) return self.children[key] end
 function o:GetAttribute(key) return self.attrs[key] end
 function o:SetAttribute(key,value) self.attrs[key]=value end
 return setmetatable(o,{__newindex=function(self,key,value)
  rawset(self,key,value)
  if key=="Parent" and value then value.children[self.Name]=self end
 end})
end
local Players=instance("Players","Players")
local ServerStorage=instance("ServerStorage","ServerStorage")
local workspace=instance("Workspace","Workspace")
local script={Parent=instance("ServerScriptService","ServerScriptService")}
local folder=instance("Folder","Level 2 Systems"); script.Parent.children[folder.Name]=folder
local kit=instance("Folder","Level2BlenderKit"); kit.attrs.Ready=true; ServerStorage.children[kit.Name]=kit
local generator=instance("ModuleScript","Level 2 Kit Layout Generator"); folder.children[generator.Name]=generator
local builder=instance("ModuleScript","Level 2 Kit World Builder"); folder.children[builder.Name]=builder
local hum={Health=100}
local player=instance("Player","Developer"); player.Parent=Players; player.UserId=40920547
player.Character={FindFirstChildOfClass=function() return hum end}
local DevAccess=(function()
__ACCESS__
end)()
local IS_RESERVED_ROUND_SERVER, IS_STUDIO, roundBusy=false,true,false
local activeEntry=nil
local developerPreviewLaunching={}
local lobbyStations={{}}
local station=lobbyStations[1]
local function playerInsideZone(p,s,includeBusy)
 check(p==player and s==station and includeBusy==true,"queue zone includes busy stations")
 return s.inside==true
end
local roundEntryMode="stale"
local game={PlaceId=131311258779917,JobId="offline-job"}
local Instance={new=function(class)
 local o=instance(class,"")
 function o:SetTeleportData(packet) self.Packet=packet end
 return o
end}
local teleports=0
local teleportFails=false
local lastOptions=nil
local TeleportService={TeleportAsync=function(_,place,group,options)
 check(place==game.PlaceId and #group==1 and group[1]==player,"existing place, solo developer")
 teleports+=1; lastOptions=options
 if teleportFails then error("offline teleport rejection") end
end}
local Routing={ArrivalPacket=function(options) return options end,NextLevel=function(level) return level+1 end}
local queue={}
local task={spawn=function(callback) table.insert(queue,callback) end}
local warnings={}
local function warn(message) table.insert(warnings,message) end
local function fireGroup(group,status,level) check(status=="loadinggame" and level==2,"Level 2 loading screen") end
local function beginGroupLoading(group) return {Members=group} end
local function clearGlowsticks() end
local function assignGlowstickSlots(group) check(group[1]==player,"same glowstick ownership") end
local prepareFails,prepareRejects,roundFails,recoveryFails=false,false,false,false
local plays,recoveries=0,0
local function prepareGroupLoading(attempt,group,level,resume)
 check(level==2 and resume==false and roundEntryMode==nil,"real Level 2 entry without slide resume")
 check(workspace.attrs.Level2BlenderPreviewActive==true,"preview selected before build")
 if prepareFails then error("offline load failure") end
 return not prepareRejects
end
local function playRound(group)
 plays+=1; check(workspace.attrs.Level2BlenderPreviewActive==true,"flag remains set during round")
 if roundFails then error("offline round failure") end
end
local function returnGroupToLobby(group)
 recoveries+=1
 if recoveryFails then error("offline recovery failure") end
end
local zyntraReentry={}
'''

MANAGER_CHECKS = r'''
local launch=ServerStorage:FindFirstChild("Level2BlenderPreviewLaunch")
check(launch and launch:IsA("BindableFunction") and type(launch.OnInvoke)=="function","registered launch surface")
local function invoke() return launch.OnInvoke(player) end
local function rejected(reason)
 local ok,actual=invoke(); check(not ok and actual==reason,"launch rejection "..reason)
end
check(level2BlenderPreviewReady(),"ready kit and both modules")
ServerStorage.children.Level2BlenderKit=nil; rejected("PREVIEW_NOT_READY"); ServerStorage.children.Level2BlenderKit=kit
kit.attrs.Ready=false; rejected("PREVIEW_NOT_READY"); kit.attrs.Ready=true
script.Parent.children[folder.Name]=nil; rejected("PREVIEW_NOT_READY"); script.Parent.children[folder.Name]=folder
for _,module in ipairs({generator,builder}) do
 folder.children[module.Name]=nil; rejected("PREVIEW_NOT_READY"); folder.children[module.Name]=module
 module.ClassName="Script"; rejected("PREVIEW_NOT_READY"); module.ClassName="ModuleScript"
end
player.UserId=11374988579; rejected("DEVELOPER_ONLY"); player.UserId=40920547
player.Parent={}; rejected("DEVELOPER_ONLY"); player.Parent=Players
check(not launch.OnInvoke(nil),"missing player denied")
IS_RESERVED_ROUND_SERVER=true; rejected("ROUND_BUSY"); IS_RESERVED_ROUND_SERVER=false
roundBusy=true; rejected("ROUND_BUSY"); roundBusy=false
activeEntry={IsOpen=function() return true end}; rejected("ROUND_BUSY"); activeEntry=nil
developerPreviewLaunching[player]=true; rejected("ROUND_BUSY"); developerPreviewLaunching[player]=nil
player.attrs.InRound=true; rejected("ROUND_BUSY"); player.attrs.InRound=nil
 hum.Health=0; rejected("ROUND_BUSY"); hum.Health=100
 local saved=player.Character; player.Character=nil; rejected("ROUND_BUSY"); player.Character=saved
 station.host=player; rejected("IN_QUEUE"); station.host=nil
 station.admittedCharacters={[player]=saved}; rejected("IN_QUEUE"); station.admittedCharacters=nil
 station.feedback={[player]="ready"}; rejected("IN_QUEUE"); station.feedback=nil
 station.entrySeen={[player]=0}; rejected("IN_QUEUE"); station.entrySeen=nil
 station.barrierMembers={[player]=saved}; rejected("IN_QUEUE"); station.barrierMembers=nil
 station.inside=true; station.busy=true; rejected("IN_QUEUE"); station.inside=nil; station.busy=nil
 check(teleports==0 and #queue==0,"all rejected launches have no side effects")
check(invoke(),"Studio launch accepted")
check(roundBusy and workspace.attrs.Level2BlenderPreviewActive==true and #queue==1,"Studio locks before task yields")
rejected("ROUND_BUSY")
table.remove(queue,1)()
check(plays==1 and not roundBusy and not workspace.attrs.Level2BlenderPreviewActive
 and not developerPreviewLaunching[player],"normal local completion releases flag and launch lock")
for _,failure in ipairs({"prepare","round","recovery"}) do
 prepareFails=failure=="prepare" or failure=="recovery"
 roundFails=failure=="round"; recoveryFails=failure=="recovery"
 check(invoke(),"asynchronous failing launch accepted initially")
 table.remove(queue,1)()
 check(not workspace.attrs.Level2BlenderPreviewActive and not developerPreviewLaunching[player]
  and not roundBusy,"errors always release preview flag and lock")
 check(workspace.attrs.RoundActive==false and workspace.attrs.PostWinIntermissionActive==false
  and zyntraReentry.OnInvoke()==false,"failure shuts down round state")
end
prepareFails=false; roundFails=false; recoveryFails=false
prepareRejects=true; activeEntry={IsOpen=function() return false end,State="failed"}
check(invoke(),"rejected loading attempt queues teardown")
table.remove(queue,1)()
check(not workspace.attrs.Level2BlenderPreviewActive and roundBusy,"failed entry retains shared recovery busy state")
prepareRejects=false; activeEntry=nil; roundBusy=false
IS_STUDIO=false
check(invoke(),"public lobby launch accepted")
check(lastOptions.ShouldReserveServer and lastOptions.Packet.Level==2 and lastOptions.Packet.Ceiling==2
 and lastOptions.Packet.Level2BlenderPreview==true and lastOptions.Packet.Level1BlenderPreview==nil
 and lastOptions.Packet.Expected==1 and lastOptions.Packet.Final==true
 and lastOptions.Packet.GlowstickSlots[tostring(player.UserId)]==1,"reserved Level 2 packet capped at 2")
check(not workspace.attrs.Level2BlenderPreviewActive and #queue==0,"public lobby does not build a local world")
teleportFails=true; rejected("TELEPORT_FAILED")
check(not developerPreviewLaunching[player] and not workspace.attrs.Level2BlenderPreviewActive,"teleport failure clears lock")
teleportFails=false
local activeLevel=2
local function nextLevel()
 __NEXT__
 return nextLevel
end
local awards=0
local participants={player}
local result="win"
local Analytics={Outcome=function() end}
local runFacts, reentryUsed={},{}
local runStartWall=nil
local runPartySize, runDevTouched=1,false
local completionRoundId="offline"
local FriendBoost={CountRoundFriends=function() return 0 end}
local zyntraLevelCompleted={Fire=function() awards+=1 end}
player.attrs.Escaped=true
local function complete()
__COMPLETION__
end
for _,preview in ipairs({false,true}) do
 workspace.attrs.Level2BlenderPreviewActive=preview
 check(nextLevel()==(not preview and 3 or nil),"Continue disabled for a Level 2 preview")
 local before=awards; complete()
 check(awards-before==(preview and 0 or 1),"completion event (progression) suppressed for a Level 2 preview")
end
workspace.attrs.Level2BlenderPreviewActive=false
result="lose"; local before=awards; complete(); check(awards==before,"loss never awards completion")
result="win"; player.attrs.Escaped=false; complete(); check(awards==before,"unescaped participant never awards completion")
local group={SessionId="party"}
local entries={}
local function arrivalEntries() return entries end
local selectedLevel=2
local arrivalPlayers={player,instance("Player","Other")}; arrivalPlayers[2].UserId=9488575949
local participants=arrivalPlayers
local attempt={failure=nil,SetMembers=function(self,members) self.members=members end,
 Fail=function(self,reason) self.failure=reason end}
local function arrive()
__ARRIVAL__
end
local function resetArrival()
 workspace.attrs.Level2BlenderPreviewActive=false; attempt.failure=nil
 selectedLevel=2; kit.attrs.Ready=true; arrivalPlayers[2].UserId=9488575949
 entries={{Data={RoundSessionId="party",Level2BlenderPreview=true}}}
end
resetArrival(); arrive(); check(workspace.attrs.Level2BlenderPreviewActive==true and not attempt.failure,"whole developer party accepts preview")
resetArrival(); selectedLevel=1; arrive(); check(attempt.failure=="LEVEL_ACCESS_DENIED" and not workspace.attrs.Level2BlenderPreviewActive,"wrong selected level fails closed")
resetArrival(); kit.attrs.Ready=false; arrive(); check(attempt.failure=="LEVEL_ACCESS_DENIED","destination readiness rechecked")
resetArrival(); arrivalPlayers[2].UserId=11374988579; arrive(); check(attempt.failure=="LEVEL_ACCESS_DENIED" and not workspace.attrs.Level2BlenderPreviewActive,"every actual participant must pass DevAccess")
resetArrival(); entries[1].Data.RoundSessionId="foreign"; arrive(); check(not attempt.failure and not workspace.attrs.Level2BlenderPreviewActive,"foreign session marker ignored")
resetArrival(); entries[1].Data.Level2BlenderPreview="true"; arrive(); check(not workspace.attrs.Level2BlenderPreviewActive,"nonboolean marker ignored")
resetArrival(); entries={{Data=false}}; arrive(); check(not workspace.attrs.Level2BlenderPreviewActive,"malformed arrival data ignored")
resetArrival(); entries={}; arrive(); check(not workspace.attrs.Level2BlenderPreviewActive,"unmarked live arrival stays live")
print("Level 2 GameManager wiring: "..checks.." executable checks passed")
'''

ADAPTER_MOCK = r'''
local checks=0
local function check(ok,label) checks+=1; assert(ok,label) end
local function obj(class,name)
 local o={ClassName=class,Name=name,attrs={},children={}}
 function o:IsA(kind) return self.ClassName==kind end
 function o:FindFirstChild(key) return self.children[key] end
 function o:WaitForChild(key) assert(self.children[key],"unexpected dependency: "..key); return self.children[key] end
 function o:GetAttribute(key) return self.attrs[key] end
 function o:SetAttribute(key,value) self.attrs[key]=value end
 function o:GetChildren() local children={}; for _,child in pairs(self.children) do table.insert(children,child) end; return children end
 function o:GetDescendants() return {} end
 function o:Destroy() self.Destroyed=true; if self.Parent then self.Parent.children[self.Name]=nil end; self.Parent=nil end
 return setmetatable(o,{__newindex=function(self,key,value)
  rawset(self,key,value); if key=="Parent" and value then value.children[self.Name]=self end
 end})
end
local vectorMT={}
local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z,kind="Vector3"},vectorMT) end
vectorMT.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMT.__sub=function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMT.__mul=function(a,b) return vec(a.X*b,a.Y*b,a.Z*b) end
vectorMT.__index=function(a,key) if key=="Unit" then local n=math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z); return vec(a.X/n,a.Y/n,a.Z/n) end end
local Vector3={new=vec}
local CFrame={new=function(position) return {kind="CFrame",Position=position} end,
 lookAt=function(position,target) return {Position=position,Target=target} end}
local function typeof(value) return type(value)=="table" and (value.kind or (value.ClassName and "Instance")) or type(value) end
local Enum={Material={Air="Air"}}
local Instance={new=function(class) return obj(class,"") end}
local workspace=obj("Workspace","Workspace")
local fills=0
workspace.Terrain={FillBlock=function() fills+=1 end}
local services={ReplicatedStorage=obj("ReplicatedStorage","ReplicatedStorage"),
 ServerStorage=obj("ServerStorage","ServerStorage"),ServerScriptService=obj("ServerScriptService","ServerScriptService")}
local placed=0
local root={}
local character={FindFirstChild=function(_,name) return name=="HumanoidRootPart" and root end,
 PivotTo=function(_,cf) placed+=1; check(cf.Position.Y==4,"shared arrival placement") end}
services.Players={GetPlayers=function() return {{Character=character}} end}
local game={GetService=function(_,key) return assert(services[key],key) end}
local script={Parent=obj("Folder","Level 2 Systems")}
local configuration={ComplexExtent=1400}
local enabled={Enabled=true}
local starts={objective=0,foam=0,slide=0}
local stops={objective=0,foam=0,slide=0}
local serial=0
local flipFlag=false
local failBuild=false
local trace={}
local function generator(kind)
 return {Generate=function(seed,options)
  check(type(seed)=="number" and seed>=1 and seed<2147483647,"shared usable seed")
  check(options.AllowRandomRecovery==(workspace.attrs.Level2Seed==nil),"shared recovery policy")
  table.insert(trace,kind..":layout")
  if flipFlag then workspace.attrs.Level2BlenderPreviewActive=not workspace.attrs.Level2BlenderPreviewActive end
  return {Seed=seed,Halls={{}},Attempt=1,Kind=kind}
 end}
end
local function builder(kind)
 return {Build=function(layout,generation)
  check(layout.Kind==kind,"generator and builder agree")
  table.insert(trace,kind..":world")
  if failBuild then error("offline builder failure") end
  serial+=1
  local world=obj("Model","Level 2 Generated World"); world.Parent=workspace
  local spawn={Position=vec(0,0,0),CFrame={LookVector=vec(0,0,1)}}
  return {World=world,Layout=layout,Arrival={ElevatorSpawn=spawn},WaterRegions={{CFrame=CFrame.new(vec(0,0,0)),Size=vec(8,8,8)}},
   PreviousWaterAppearance={WaterTransparency=.4},Kind=kind}
 end}
end
local modules={
 ["Level 2 Configuration"]=configuration,
 ["Level 2 Layout Generator"]=generator("live"),["Level 2 World Builder"]=builder("live"),
 ["Level 2 Pool Foam Configuration"]=enabled,["Level 2 Pool Slide Configuration"]=enabled,
}
for name,key in pairs({["Level 2 Objective Controller"]="objective",["Level 2 Pool Foam Controller"]="foam",["Level 2 Pool Slide Controller"]="slide"}) do
 modules[name]={Start=function(manifest,generation)
  starts[key]+=1; check(manifest==_G.expectedManifest or manifest.World.Parent==workspace,"shared manifest in controller start")
  return {}
 end,Stop=function() stops[key]+=1 end}
end
for name,module in pairs(modules) do local entry=obj("ModuleScript",name); entry.module=module; script.Parent.children[name]=entry end
local master=obj("ModuleScript","MasterConfiguration")
master.module={ApplyInto=function(config,prefix) check(config==configuration and prefix=="L2","shared master configuration") end}
services.ReplicatedStorage.children[master.Name]=master
local kitRequires=0
local function require(entry)
 assert(entry and entry.ClassName=="ModuleScript","missing or malformed module")
 if string.find(entry.Name,"Kit",1,true) then kitRequires+=1 end
 return entry.module
end
local DateTime={now=function() return {UnixTimestampMillis=123456} end}
local Random={new=function() return {NextInteger=function() return 42 end} end}
local warnings={}
local function warn(message) table.insert(warnings,message) end
'''

ADAPTER_CHECKS = r'''
check(kitRequires==0,"loading adapter does not require absent kit modules")
for _,flag in ipairs({false,"true",1}) do
 workspace.attrs.Level2BlenderPreviewActive=flag
 local world=Adapter.Build(); local manifest=Adapter.GetManifest()
 check(world==manifest.World and manifest.Kind=="live" and kitRequires==0,"flag off/nonboolean uses live pair without kit")
 check(workspace.attrs.WorldGenerated==true and workspace.attrs.SelectedLevel==2,"shared ready attributes")
 local state=services.ReplicatedStorage:FindFirstChild("Level 2 State")
 check(state.attrs.Level2_Phase=="READY" and state.attrs.Level2_PoolSlideEnabled==true,"shared replicated state")
 Adapter.Cleanup()
 check(world.Destroyed and Adapter.GetManifest()==nil and state.attrs.Level2_Phase=="IDLE","shared cleanup removes round world")
end
local kitGenerator=obj("ModuleScript","Level 2 Kit Layout Generator"); kitGenerator.module=generator("kit")
local kitBuilder=obj("ModuleScript","Level 2 Kit World Builder"); kitBuilder.module=builder("kit")
script.Parent.children[kitGenerator.Name]=kitGenerator; script.Parent.children[kitBuilder.Name]=kitBuilder
workspace.attrs.Level2Seed=101; workspace.attrs.Level2BlenderPreviewActive=true
flipFlag=true
local world=Adapter.Build(); local manifest=Adapter.GetManifest()
check(manifest.Kind=="kit" and kitRequires==2 and manifest.Layout.Seed==101,"flag on chooses both kit modules with pinned seed")
check(workspace.attrs.Level2BlenderPreviewActive==false,"test flips workspace flag while layout generates")
check(trace[#trace-1]=="kit:layout" and trace[#trace]=="kit:world","Build entry snapshot selects entire pair despite later flag change")
Adapter.Cleanup(); flipFlag=false
workspace.attrs.Level2BlenderPreviewActive=false
world=Adapter.Build(); check(Adapter.GetManifest().Kind=="live" and kitRequires==2,"next flag-off round uses live modules")
Adapter.Cleanup()
check(starts.objective==5 and starts.foam==5 and starts.slide==5 and placed==5,"both paths share placement, objectives, Pool Foam and Pool Slide")
check(stops.objective==stops.foam and stops.foam==stops.slide,"all controllers share teardown")
workspace.attrs.Level2BlenderPreviewActive=true; failBuild=true
local ok=pcall(Adapter.Build)
local state=services.ReplicatedStorage:FindFirstChild("Level 2 State")
check(not ok and workspace.attrs.LoadStage=="WORLD_ERROR" and state.attrs.Level2_Phase=="ERROR"
 and Adapter.GetManifest()==nil,"kit build errors use shared recovery")
failBuild=false; script.Parent.children[kitBuilder.Name]=nil
ok=pcall(Adapter.Build); check(not ok and workspace.attrs.LoadStage=="WORLD_ERROR","missing preview builder errors through shared recovery")
workspace.attrs.Level2BlenderPreviewActive=false
world=Adapter.Build(); check(Adapter.GetManifest().Kind=="live","missing kit still permits live build after failed preview")
Adapter.Cleanup()
check(workspace.Terrain.WaterTransparency==.4,"shared terrain appearance restored")
print("Level 2 Round Adapter: "..checks.." executable checks passed (mock services, no gameplay claim)")
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", type=Path, default=os.environ.get("LUAU_BIN") or shutil.which("luau"))
    args = parser.parse_args()
    if not args.luau:
        raise SystemExit("Set LUAU_BIN or pass --luau; no checks executed.")
    baseline_bytes = MANAGER.read_bytes()
    manager = baseline_bytes.decode("utf-8").replace("\r\n", "\n")
    adapter = ADAPTER.read_text(encoding="utf-8")
    assert adapter.count('workspace:GetAttribute("Level2BlenderPreviewActive")') == 1
    assert adapter.index('workspace:GetAttribute("Level2BlenderPreviewActive")') < adapter.index(
        "\tAdapter.Cleanup()", adapter.index("function Adapter.Build()"))
    # The flag is cleared at boot (before any station can launch) and by both world cleanups.
    boot = manager[:manager.index("-- A station launch")]
    cleanup1 = section(manager, "local function cleanupLevelOneWorld()", "local function livePlayers(")
    cleanup = section(manager, "cleanupActiveWorld = function()", "local function returnPlayersToLocalLobby")
    for code in (boot, cleanup1, cleanup):
        assert 'workspace:SetAttribute("Level2BlenderPreviewActive", false)' in code
    # Only boot, the two cleanups, the Studio launch (set and clear) and the arrival write the flag.
    writers = manager.count('workspace:SetAttribute("Level2BlenderPreviewActive"')
    assert writers == 6, f"Level2BlenderPreviewActive has {writers} writers; expected 6 (boot, 2 cleanups, launch x2, arrival)"
    # Keep the live Level 2 win rider lifecycle through the result window; the
    # nil NextLevel guard ends it via the existing closeRoundLifecycle below.
    assert 'if result ~= "win" or activeLevel ~= 2 then closeRoundLifecycle() end' in manager
    postwin = section(manager, '  local outcome = runPostWinIntermission',
                      '  workspace:SetAttribute("PostWinIntermissionActive", false)')
    assert "closeRoundLifecycle()" in postwin
    next_line = next(line for line in manager.splitlines()
                     if 'local nextLevel = workspace:GetAttribute("Level2BlenderPreviewActive") ~= true' in line)
    completion = section(manager, " local escapedCount = 0", '\n if result == "win" then')
    arrival = section(manager, "  local level2BlenderPreview = false", "  local glowstickSlots = nil")
    access = (ROOT / "ReplicatedStorage/DevAccess.ModuleScript.lua").read_text(encoding="utf-8")
    launch = section(manager, "-- Level 2 uses the shared round adapter", "\nlocal function resetStation")
    program = MANAGER_MOCK.replace("__ACCESS__", access) + launch + MANAGER_CHECKS
    program = program.replace("__NEXT__", next_line).replace("__COMPLETION__", completion).replace("__ARRIVAL__", arrival)

    def killed_by(temp, name, old, new, label):
        """A mutant manager program with one guard removed must fail on that guard's check."""
        assert program.count(old) == 1, f"mutation anchor for {name} changed"
        mutant = temp / f"manager-{name}.luau"
        mutant.write_text(program.replace(old, new, 1), encoding="utf-8")
        run = subprocess.run([str(args.luau), str(mutant)], capture_output=True, text=True, timeout=30)
        assert run.returncode != 0 and label in run.stdout + run.stderr, f"{name} mutation survived"

    with tempfile.TemporaryDirectory(prefix="level2-preview-offline-") as directory:
        temp = Path(directory)
        for name, source in (("manager.luau", program),
                             ("adapter.luau", ADAPTER_MOCK + "\nlocal Adapter=(function()\n" + adapter + "\nend)()\n"
                              + ADAPTER_CHECKS)):
            path = temp / name
            path.write_text(source, encoding="utf-8")
            subprocess.run([str(args.luau), str(path)], check=True, timeout=30)
        guard = section(launch, "  for _, station in pairs(lobbyStations) do", "  if not level2BlenderPreviewReady()")
        killed_by(temp, "no-queue-guard", guard, "", "launch rejection IN_QUEUE")
        killed_by(temp, "no-devaccess", "player.Parent ~= Players or not DevAccess.IsAllowed(player) then",
                  "player.Parent ~= Players then", "launch rejection DEVELOPER_ONLY")
        killed_by(temp, "preview-progresses", 'if result == "win" and workspace:GetAttribute("Level2BlenderPreviewActive") ~= true then',
                  'if result == "win" then', "completion event (progression) suppressed")
        killed_by(temp, "no-arrival-devaccess", "if not DevAccess.IsAllowed(player) then allowed = false end", "",
                  "every actual participant must pass DevAccess")
        compiler = args.luau.with_name("luau-compile.exe")
        assert compiler.is_file(), "luau-compile is required for the register-limit check"
        for path in (MANAGER, ADAPTER):
            subprocess.run([str(compiler), "-O0", str(path)], stdout=subprocess.DEVNULL, check=True, timeout=60)
    assert MANAGER.read_bytes() == baseline_bytes, "GameManager changed during checks"
    print("Current GameManager and Round Adapter compile at -O0.")
    print("Mutations killed: queue guard, launch DevAccess gate, preview-win progression, arrival DevAccess gate.")
    print(f"GameManager SHA256 checked: {hashlib.sha256(baseline_bytes).hexdigest()}")


if __name__ == "__main__":
    main()
