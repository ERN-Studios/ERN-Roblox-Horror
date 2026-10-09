"""Run the complete candidate EntityAnimation controller in official Luau.

Fake engine tracks/signals verify runtime transitions and ownership, not visual
quality, asset permissions, skinned bones or actual Studio movement.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "drafts/level1-quality-20261002/EntityAnimation.Script.lua"

MOCK = r'''
local checks=0
local function check(ok,label) checks+=1; assert(ok,label) end
local warnings={}
local function warn(message) table.insert(warnings,message) end
local function signal()
    local event={listeners={}}
    function event:Connect(callback)
        local connection={Connected=true}
        function connection:Disconnect() self.Connected=false end
        table.insert(self.listeners,{connection=connection,callback=callback})
        return connection
    end
    function event:Once(callback)
        local connection
        connection=self:Connect(function(...) connection:Disconnect(); callback(...) end)
        return connection
    end
    function event:Fire(...)
        for _,item in ipairs(self.listeners) do if item.connection.Connected then item.callback(...) end end
    end
    function event:ActiveCount()
        local count=0; for _,item in ipairs(self.listeners) do if item.connection.Connected then count+=1 end end
        return count
    end
    return event
end
local function object(class,name)
    local obj={ClassName=class,Name=name or "",attrs={},children={},signals={},Destroying=signal(),AncestryChanged=signal()}
    function obj:IsA(kind) return kind==self.ClassName or kind=="BaseScript" and self.ClassName=="Script" end
    function obj:FindFirstChild(key) return self.children[key] end
    function obj:WaitForChild(key) return self.children[key] end
    function obj:FindFirstChildOfClass(kind)
        for _,child in pairs(self.children) do if child:IsA(kind) then return child end end
    end
    function obj:GetAttribute(key) return self.attrs[key] end
    function obj:GetAttributeChangedSignal(key)
        self.signals[key]=self.signals[key] or signal(); return self.signals[key]
    end
    function obj:GetPropertyChangedSignal(key) return self:GetAttributeChangedSignal(key) end
    function obj:SetAttribute(key,value) self.attrs[key]=value; self:GetAttributeChangedSignal(key):Fire() end
    function obj:IsDescendantOf() return self.inside~=false end
    function obj:Destroy()
        self.Destroying:Fire(); self.Destroyed=true
        if self.Parent then self.Parent.children[self.Name]=nil end
        self.Parent=nil
    end
    return setmetatable(obj,{
        __index=function(self,key) return key=="Parent" and rawget(self,"_parent") or self.children[key] end,
        __newindex=function(self,key,value)
            if key=="Parent" then rawset(self,"_parent",value); if value then value.children[self.Name]=self end
            else rawset(self,key,value) end
        end})
end
local script=object("Script","EntityAnimation"); script.Enabled=true
local workspace=object("Workspace","Workspace")
local entity=object("Model","Entity"); workspace.children.Entity=entity
local humanoid=object("Humanoid","Humanoid"); humanoid.Health=100; entity.children.Humanoid=humanoid
local root=object("Part","HumanoidRootPart"); root.Anchored=false; root.AssemblyLinearVelocity={X=0,Y=0,Z=0}
entity.children.HumanoidRootPart=root
local animator=object("Animator","Animator"); humanoid.children.Animator=animator
local RunService={Heartbeat=signal()}
local game={GetService=function(_,name) assert(name=="RunService"); return RunService end}
local Enum={AnimationPriority={Idle="Idle",Movement="Movement",Action4="Action4"}}
local Vector3={new=function(x,y,z) return {X=x,Y=y,Z=z,Magnitude=math.sqrt(x*x+y*y+z*z)} end}
local createdAnimations={}
local bindInvokeObserver
local Instance={new=function(class)
    local obj=object(class)
    if class=="Animation" then table.insert(createdAnimations,obj) end
    if class=="BindableEvent" then obj.Event=signal(); function obj:Fire(...) self.Event:Fire(...) end end
    if class=="BindableFunction" then
        function obj:Invoke(...)
            if bindInvokeObserver then bindInvokeObserver("before") end
            local result=self.OnInvoke(...)
            if bindInvokeObserver then bindInvokeObserver("after") end
            return result
        end
    end
    return obj
end}
local allTracks={}
local function track(name,length,animation)
    local t={Name=name,Length=length,Animation=animation,IsPlaying=false,Speed=1,WeightCurrent=0,
        WeightTarget=0,TimePosition=0,PlayCount=0,StopCount=0,DestroyCount=0,Ended=signal()}
    function t:Play(fade,weight,speed)
        assert(not self.Destroyed,"a destroyed AnimationTrack cannot resume")
        self.IsPlaying=true; self.TimePosition=0; self.PlayCount+=1
        self.WeightTarget=weight or 1; self.fadeLeft=fade or .1; self.Speed=speed or 1; self.ending=false
    end
    function t:AdjustSpeed(speed) self.Speed=speed end
    function t:AdjustWeight(weight,fade) self.WeightTarget=weight; self.fadeLeft=fade or .1 end
    function t:Stop(fade)
        self.IsPlaying=false; self.StopCount+=1; self.WeightTarget=0; self.fadeLeft=fade or .1; self.ending=true
    end
    function t:Destroy()
        assert(not self.IsPlaying,"playing owned AnimationTrack must be stopped before destruction")
        self.DestroyCount+=1; self.Destroyed=true; self.ending=false
        for _,item in ipairs(self.Ended.listeners) do item.connection:Disconnect() end
    end
    table.insert(allTracks,t); return t
end
local foreignAnimation=object("Animation","Foreign"); foreignAnimation.Parent=entity
local foreign=track("ForeignAction",9,foreignAnimation); foreign.IsPlaying=true; foreign.Looped=true
local oldAnimation=object("Animation","OldOwned"); oldAnimation.Parent=script
local oldOwned=track("OldOwned",2,oldAnimation); oldOwned.IsPlaying=true
function animator:GetPlayingAnimationTracks() return {foreign,oldOwned} end
local lengths={Watch=5.966667,Walk=1.3,Run_Chase=.806,Yell_Howl=2.166667,Yell_FromRun=2.866667,
    Lunge=2.366667,Lunge_FromRun=1.7,Kill_GroundPinPunch=4.966667}
local named={}
local loadFailureName=nil
function animator:LoadAnimation(animation)
    if animation.Name==loadFailureName then error("intentional asset-load failure") end
    local t=track(animation.Name,lengths[animation.Name],animation); named[animation.Name]=t; return t
end
local function advance(dt)
    for _,t in ipairs(allTracks) do
        if not t.Destroyed and t.IsPlaying then
            t.TimePosition+=dt*t.Speed
            if t.Looped then t.TimePosition%=t.Length
            elseif t.TimePosition>=t.Length then t:Stop(.1) end
        end
        local remaining=t.fadeLeft or 0
        if remaining>0 then
            local portion=math.min(dt/remaining,1)
            t.WeightCurrent+=(t.WeightTarget-t.WeightCurrent)*portion
            t.fadeLeft=math.max(remaining-dt,0)
        end
        if t.ending and (t.fadeLeft or 0)==0 then t.ending=false; t.Ended:Fire() end
    end
    RunService.Heartbeat:Fire(dt)
end
local function drive(speed,state,seconds)
    root.AssemblyLinearVelocity={X=speed,Y=0,Z=0}; workspace.attrs.EntityState=state
    for _=1,math.floor((seconds or .5)*60) do advance(1/60) end
end
local function playing(name) return named[name].IsPlaying and named[name].WeightTarget>0 end
'''

CHECKS = r'''
check(foreign.StopCount==0 and oldOwned.StopCount==1,"startup stops only controller-owned tracks")
check(named.Watch.Looped and named.Walk.Looped and named.Run_Chase.Looped,"locomotion loops configured")
check(named.Watch.Priority=="Idle" and named.Walk.Priority=="Movement" and named.Run_Chase.Priority=="Movement"
    and named.Kill_GroundPinPunch.Priority=="Action4","locomotion/action priorities preserved")
local expected={Watch="92831421568704",Walk="121187609243437",Run_Chase="90840395594409",
    Yell_Howl="102035504530432",Yell_FromRun="132425538759403",Lunge="70970124497806",
    Lunge_FromRun="132839013239254",Kill_GroundPinPunch="94135265462008"}
for name,id in pairs(expected) do check(named[name].Animation.AnimationId=="rbxassetid://"..id,"published clip retained "..name) end
drive(0,"LURK",.3); check(playing("Watch"),"stationary idle")
local idlePlays=named.Watch.PlayCount
for i=1,60 do drive(i%2==0 and .28 or .35,"LURK",1/60) end
check(named.Watch.PlayCount==idlePlays and not playing("Walk"),"small velocity jitter does not restart idle/walk")
drive(9,"LURK",.8)
check(playing("Walk") and math.abs(named.Walk.Speed-1)<.01,"actual nine-stud walk matches authored pace")
local walkPlays=named.Walk.PlayCount; drive(9,"LURK",.3)
check(named.Walk.PlayCount==walkPlays,"stable locomotion does not restart loop")
named.Walk.TimePosition=.65
root.AssemblyLinearVelocity={X=15,Y=0,Z=0}; workspace.attrs.EntityState="CHASE"
RunService.Heartbeat:Fire(1/60)
check(playing("Run_Chase") and math.abs(named.Run_Chase.TimePosition-.403)<.001,"walk-to-run retains normalized half-stride phase")
drive(15,"CHASE",.8); check(math.abs(named.Run_Chase.Speed-1)<.01,"chase pace uses real smoothed velocity")
named.Run_Chase.TimePosition=.2015; workspace.attrs.EntityState="TRACK"; RunService.Heartbeat:Fire(1/60)
check(playing("Walk") and math.abs(named.Walk.TimePosition-.325)<.001,"run-to-track keeps quarter-stride and fast walk")
drive(1,"TRACK",.8); check(named.Walk.Speed<.2,"slow movement avoids old minimum 0.6 foot skating")
drive(0,"LURK",1); check(playing("Watch") and not playing("Walk"),"settled stop blends back to idle")
drive(27.2,"CHASE",1); check(named.Run_Chase.Speed>1.7 and named.Run_Chase.Speed<1.9,"full chase speed matched")
local runPlays=named.Run_Chase.PlayCount
entity.PlayHowl:Fire(); check(playing("Yell_Howl") and not playing("Run_Chase"),"howl owns one-shot priority")
check(playing("Watch"),"idle under action prevents an uncovered bind-pose reset")
drive(27.2,"CHASE",.3); check(named.Run_Chase.PlayCount==runPlays,"locomotion waits during action")
drive(27.2,"CHASE",2.5); check(playing("Run_Chase"),"locomotion resumes after full action fade")
workspace.attrs.EntityKillActive=true; workspace.attrs.EntityKillCaptureId="capture:1"
entity.PlayKill:Fire("spoofed"); check(not playing("Kill_GroundPinPunch"),"wrong kill capture rejected")
entity.PlayKill:Fire("capture:1"); check(playing("Kill_GroundPinPunch"),"owned kill clip starts")
local killPlays=named.Kill_GroundPinPunch.PlayCount
entity.PlayKill:Fire("capture:1"); entity.PlayHowl:Fire(); workspace:SetAttribute("EntityLunge",1)
check(named.Kill_GroundPinPunch.PlayCount==killPlays and playing("Kill_GroundPinPunch") and not playing("Lunge_FromRun"),
    "duplicate kill and late howl/lunge never restart or interrupt capture")
entity.CancelKill:Fire("other"); check(playing("Kill_GroundPinPunch"),"foreign cancel rejected")
workspace.attrs.EntityKillActive=false; entity.CancelKill:Fire("capture:1"); drive(15,"CHASE",.2)
check(playing("Run_Chase") and not playing("Kill_GroundPinPunch"),"owned cancellation resumes loop")
entity.inside=false; entity.AncestryChanged:Fire()
check(RunService.Heartbeat:ActiveCount()==0 and workspace:GetAttributeChangedSignal("EntityLunge"):ActiveCount()==0,
    "round removal disconnects recurring controller signals")
check(not entity.PlayHowl and not entity.PlayKill and named.Walk.Animation.Destroyed,"owned events/animations removed on reset")
for name,t in pairs(named) do
    check(t.Destroyed and t.DestroyCount==1 and t.Animation.Destroyed and t.Ended:ActiveCount()==0,
        "cleanup destroys exactly one loaded owned track and its asset: "..name)
end
check(named.Yell_FromRun.PlayCount==0 and named.Yell_FromRun.Destroyed,"never-played owned track releases its Animator slot")
check(foreign.StopCount==0 and foreign.DestroyCount==0 and foreign.IsPlaying,"cleanup preserves another animation owner's track")
local plays=named.Run_Chase.PlayCount; RunService.Heartbeat:Fire(1); workspace:SetAttribute("EntityLunge",2)
check(named.Run_Chase.PlayCount==plays,"closed controller cannot restart tracks")
entity.Destroying:Fire(); script.Destroying:Fire(); script.Enabled=false; script:GetPropertyChangedSignal("Enabled"):Fire()
check(named.Run_Chase.DestroyCount==1 and foreign.DestroyCount==0,"repeated teardown signals cannot dispose tracks twice")
local foreignTime=foreign.TimePosition; advance(.2)
check(foreign.TimePosition>foreignTime and foreign.IsPlaying,"foreign track keeps playing after owned cleanup")
print("Level 1 EntityAnimation: "..checks.." actual-controller checks passed")
'''

FAILED_LOCOMOTION = r'''
check(#warnings>=2,"failed required asset reports load and locomotion failure")
local count=0
for name,t in pairs(named) do
    count+=1
    check(t.Destroyed and t.DestroyCount==1 and t.Animation.Destroyed,
        "required-load failure releases loaded owned track "..name)
end
check(count==7,"seven successfully loaded clips released when one required clip fails")
check(#createdAnimations==8,"all eight authored Animation instances accounted for")
for _,animation in ipairs(createdAnimations) do check(animation.Destroyed,"failed startup retains no owned Animation instance") end
check(RunService.Heartbeat:ActiveCount()==0 and not entity.PlayHowl and not entity.PlayKill,
    "failed startup registers no controller tasks or action events")
check(foreign.StopCount==0 and foreign.DestroyCount==0 and foreign.IsPlaying,"failed startup leaves foreign owner intact")
print("Level 1 EntityAnimation required "..loadFailureName.." failure: "..checks.." actual-controller checks passed")
'''

FAILED_OPTIONAL = r'''
check(#warnings==1 and named.Yell_FromRun==nil,"optional clip failure is reported without aborting the controller")
local failed
for _,animation in ipairs(createdAnimations) do if animation.Name=="Yell_FromRun" then failed=animation end end
check(failed and failed.Destroyed,"optional failed Animation is released immediately")
drive(9,"LURK",.3);entity.PlayYell:Fire()
check(playing("Yell_Howl"),"optional yell uses its existing howl fallback")
entity.inside=false;entity.AncestryChanged:Fire()
local count=0
for _,t in pairs(named) do count+=1;check(t.Destroyed and t.DestroyCount==1,"optional-load session releases every loaded owned track") end
check(count==7 and foreign.DestroyCount==0 and foreign.StopCount==0,"optional-load cleanup owns only its seven loaded tracks")
print("Level 1 EntityAnimation optional failure: "..checks.." actual-controller checks passed")
'''

PARKING = r'''
drive(15,"CHASE",.5)
local ServerStorage=object("ServerStorage","ServerStorage")
local scripts=object("ServerScriptService","ServerScriptService")
script.Parent=scripts
entity.Parent=workspace
local ai=object("Script","EntityAI");ai.Enabled=true;ai.Parent=scripts
local kill=object("Script","EntityKill");kill.Enabled=true;kill.Parent=scripts
local invoked=0
bindInvokeObserver=function(stage)
    check(script.Enabled and entity.Parent==workspace,"synchronous "..stage.." handoff occurs before script disable/entity parking")
    if stage=="before" then invoked+=1
    else
        for name,t in pairs(named) do check(t.Destroyed and t.Animation.Destroyed,"owned track/asset destroyed before disabling: "..name) end
        check(RunService.Heartbeat:ActiveCount()==0,"recurring callback disconnected before disabling")
    end
end
'''

PARKING_CHECKS = r'''
setLevelOneEntityActive(false)
check(invoked==1,"actual manager invokes exactly one enabled owned release function")
check(entity.Parent==ServerStorage and entity.Name==STORED_LEVEL_ONE_ENTITY_NAME,"actual manager parks original Level1 entity after release")
check(not script.Enabled and not ai.Enabled and not kill.Enabled,"actual manager disables only its three Level1 controllers")
check(script.ReleaseAnimations and script.ReleaseAnimations:IsA("BindableFunction")
    and script.ReleaseAnimations:GetAttribute("OwnerSystem")=="Level1EntityAnimation","one stable explicitly owned release handoff survives for restart")
for name,t in pairs(named) do check(t.DestroyCount==1,"parking destroys each owned track exactly once: "..name) end
check(foreign.DestroyCount==0 and foreign.StopCount==0 and foreign.IsPlaying,"synchronous handoff preserves foreign animation owners")
setLevelOneEntityActive(false)
check(invoked==1,"already-disabled controller is never invoked through a stale handoff")
entity.AncestryChanged:Fire();script:GetPropertyChangedSignal("Enabled"):Fire()
check(named.Run_Chase.DestroyCount==1,"later deferred teardown cannot repeat owned destruction")
setLevelOneEntityActive(true)
check(script.Enabled and ai.Enabled and kill.Enabled and entity.Parent==workspace,"existing Level1 activation still restores entity/controllers")
print("Level 1 EntityAnimation synchronous parking: "..checks.." actual-controller/manager checks passed")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    artifact = ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe"
    if not binary and artifact.is_file():
        binary = str(artifact)
    if not binary:
        raise SystemExit("Luau runtime unavailable; no checks executed.")
    source = SOURCE.read_text(encoding="utf-8")
    manager = (ROOT / "drafts/level1-quality-20261002/GameManager.Script.lua").read_text(encoding="utf-8")
    before_manager = (ROOT / "artifacts/level1-quality-20261002/live-before-aperture-install/ServerScriptService/GameManager.Script.lua").read_text(encoding="utf-8")
    start = manager.index("local function setLevelOneEntityActive(active)")
    body = manager.index(' local entity = active and ServerStorage:FindFirstChild', start)
    added = manager[start + len("local function setLevelOneEntityActive(active)\n"):body]
    assert manager.replace(added, "", 1) == before_manager, "unrelated fresh Cinema GameManager source changed"
    manager_block = manager[manager.index("local LEVEL_ONE_ENTITY_SCRIPTS"):manager.index("\nsanitizePersistedLevelState()\nsetLevelOneEntityActive(false)")]
    with tempfile.TemporaryDirectory(prefix="entity-animation-") as directory:
        scenarios=[("controller", "", CHECKS), ("failed-walk", 'loadFailureName="Walk"', FAILED_LOCOMOTION),
                   ("failed-run", 'loadFailureName="Run_Chase"', FAILED_LOCOMOTION),
                   ("failed-optional", 'loadFailureName="Yell_FromRun"', FAILED_OPTIONAL)]
        for name,setup,checks in scenarios:
            path = Path(directory) / (name+".luau")
            path.write_text(MOCK + "\n" + setup + "\n(function()\n" + source + "\nend)()\n" + checks, encoding="utf-8")
            subprocess.run([binary, str(path)], check=True, timeout=20)
        path = Path(directory) / "synchronous-parking.luau"
        path.write_text(MOCK + "\n(function()\n" + source + "\nend)()\n" + PARKING + manager_block + PARKING_CHECKS, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)
        compiler = Path(binary).with_name("luau-compile.exe")
        if compiler.is_file():
            subprocess.run([str(compiler), "--null", str(SOURCE)], check=True)
            subprocess.run([str(compiler), "--null", str(ROOT / "drafts/level1-quality-20261002/GameManager.Script.lua")], check=True)


if __name__ == "__main__":
    main()
