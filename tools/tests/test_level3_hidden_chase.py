"""Run production hidden-target/table-check helpers with offline Luau fixtures.

The real target selection, table lifecycle, wall-ray gate, hiding records and
immunity clock run. Engine geometry, presentation, and character release are
stubbed; generated-world movement remains a Studio check.
--baseline-ref HEAD runs only eligibility against the old source to prove fail.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
AI_PATH = "ServerScriptService/Level 3 Systems/Level 3 Mall Manager AI Controller.ModuleScript.lua"
HIDING_PATH = "ServerScriptService/Level 3 Systems/Level 3 Hiding Controller.ModuleScript.lua"
CONFIG_PATH = "ServerScriptService/Level 3 Systems/Level 3 Configuration.ModuleScript.lua"


def section(source, start, end):
    return source[source.index(start):source.index(end)]


PRELUDE = r'''
local serverNow,cpuNow=100,10
local os=table.clone(os)
os.clock=function() return cpuNow end
local Vector3={}
local vm={}
local mt={
    __index=function(v,k)
        if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
        if k=="Unit" then return v/v.Magnitude end
        return vm[k]
    end,
    __add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end,
    __sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end,
    __mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end,
    __div=function(a,b) return Vector3.new(a.X/b,a.Y/b,a.Z/b) end,
}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},mt) end
function vm:Dot(v) return self.X*v.X+self.Y*v.Y+self.Z*v.Z end
Vector3.zero=Vector3.new(0,0,0)
local Color3={fromRGB=function() return {} end}
local CFrame={}
local cm={PointToObjectSpace=function(cf,p) return p-cf.Position end,
    PointToWorldSpace=function(cf,p) return p+cf.Position end}
local cmt={__index=cm,__mul=function(a,b) return CFrame.new(a.Position+b.Position) end}
function CFrame.new(x,y,z)
    return setmetatable({Position=type(x)=="table" and x or Vector3.new(x or 0,y or 0,z or 0)},cmt)
end
function CFrame.Angles() return CFrame.new() end
local function object(class)
    return {Class=class,Attributes={},Parent=true,
        IsA=function(self,c) return self.Class==c end,
        IsDescendantOf=function() return true end,
        GetAttribute=function(self,k) return self.Attributes[k] end,
        SetAttribute=function(self,k,v) self.Attributes[k]=v end,
        Play=function(self) self.Played=true end,
        Destroy=function(self) self.Parent=nil end}
end
local Instance={new=object}
local Enum={RollOffMode={InverseTapered="InverseTapered"},HumanoidDisplayDistanceType={None="None"}}
local roster={}
local Players={GetPlayers=function() return roster end}
local workspace={Wall=false,RayCount=0,GetServerTimeNow=function() return serverNow end,
    Raycast=function(self) self.RayCount+=1; return self.Wall and {} or nil end}
local hiddenSession={Active=true,Generation=7,HiddenPlayers={},Occupants={},FlushImmuneUntil={},AnchorSet={},LastAction={},World={}}
local released={}
local checks,failures=0,{}
local function check(value,message)
    checks+=1
    if not value then table.insert(failures,message) end
end
local function validRound(session) return session.Valid~=false and session.Generation==7 end
local function player(id,x)
    local p=object("Player"); p.UserId=id; p.Parent=Players
    p.Attributes={InRound=true}
    local root=object("BasePart"); root.Position=Vector3.new(x,0,0); root.AssemblyLinearVelocity=Vector3.zero
    local human={Health=100}
    p.Character={Parent=true,Root=root,Human=human,
        PivotTo=function(self,cf) self.Root.Position=cf.Position end,
        FindFirstChild=function(self,n) return n=="HumanoidRootPart" and self.Root or nil end,
        FindFirstChildOfClass=function(self,n) return n=="Humanoid" and self.Human or nil end}
    return p
end
local function anchor(x)
    local a=object("BasePart"); a.Position=Vector3.new(x,0,0); a.CFrame=CFrame.new(a.Position)
    a.Attributes.Level3_HideTableIndex=1
    return a
end
local function hide(p,a)
    p:SetAttribute("Level3_Hiding",true)
    hiddenSession.HiddenPlayers[p]={Generation=7,Character=p.Character,Anchor=a,Slot=1}
    hiddenSession.Occupants[a]=hiddenSession.Occupants[a] or {}
    table.insert(hiddenSession.Occupants[a],p)
end
local function releasePlayer(session,p)
    local record=session.HiddenPlayers[p]
    if not record then return false end
    session.HiddenPlayers[p]=nil
    p:SetAttribute("Level3_Hiding",false)
    for i,occupant in ipairs(session.Occupants[record.Anchor] or {}) do
        if occupant==p then table.remove(session.Occupants[record.Anchor],i); break end
    end
    table.insert(released,p)
    return true
end
'''

HIDING_PRELUDE = r'''
local HidingController=(function()
local Controller={}
local activeSession=hiddenSession
local Tuning=Configuration.Hiding
local TableCheckTuning=Configuration.TableCheck
local function liveSession(s) return s.Active and s.Generation==7 end
local function occupantsOf(s,a) return s.Occupants[a] or {} end
local function slotLateral() return 0 end
local function roundAllowsHiding(s) return liveSession(s) end
local function eligible(p) return p.Character,p.Character.Human,p.Character.Root end
local function captureCollisionState() return {} end
local function suppressCollision() end
local function refreshPrompt() end
local function updateHiddenCount() end
'''

AI_PRELUDE = r'''
local Tuning=Configuration.MallManager
local TableCheckTuning=Configuration.TableCheck
local debugTableChecksSuspended=false
local function planarDistance(a,b) return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
local function flat(p,y) return Vector3.new(p.X,y,p.Z) end
local function stopChaseScream() end
local function publishState(s,state) s.State=state end
local function publishTableCheck(s,a,t) s.PublishedAnchor=a; s.PublishedEndsAt=t end
local function clearGoal(s) s.Goal=nil end
local function facePosition(s,p) s.FacingTarget=p end
local function arrivalGoal(s) return s.Goal end
local function setGoal(s,p,force) s.Goal=p; s.ForcedGoal=force end
local function choosePatrolGoal(s) s.PatrolGoal=Vector3.new(50,0,50); s.State="PATROL" end
local function volumeFits() return true end
local function navigationParams() return {} end
local function hasSightRay() return not workspace.Wall end
local function session()
    return {Generation=7,Valid=true,Blackout=true,Root={Position=Vector3.zero},FloorY=0,
        Model=object("Model"),StateFolder=object("Folder"),State="CHASE",ActivatedAt=0,
        AnchorCheckCooldown={},NextTableCheckAt=0,AttackToken=0,Attacking=false}
end
'''

ELIGIBILITY_TESTS = r'''
do
    local s=session()
    local p=player(1,10); hide(p,anchor(12))
    check(select(3,livingPlayer(p,s))==p.Character.Root,"hidden living participant remains an eligible chase target")
    p.Character.Human.Health=0
    check(livingPlayer(p,s)==nil,"dead participant excluded")
    p.Character.Human.Health=100; p:SetAttribute("Escaped",true)
    check(livingPlayer(p,s)==nil,"escaped participant excluded")
    p:SetAttribute("Escaped",false); p:SetAttribute("InRound",false)
    check(livingPlayer(p,s)==nil,"nonparticipant excluded")
    p:SetAttribute("InRound",true); p.Parent=nil
    check(livingPlayer(p,s)==nil,"disconnected participant excluded")
    p.Parent=Players; s.Valid=false
    check(livingPlayer(p,s)==nil,"inactive round excluded")
    s.Valid=true; p.Character.Parent=nil
    check(livingPlayer(p,s)==nil,"removed character excluded")
end
'''

TESTS = r'''
do
    local p=player(77,10); local a=anchor(12)
    hiddenSession.AnchorSet[a]=true; hiddenSession.Occupants[a]={}
    p:SetAttribute("BeingChased",true)
    local entered=HidingController.TestTryEnter(hiddenSession,p,a)
    check(entered and p:GetAttribute("Level3_Hiding")==true,"real hiding entry succeeds for eligible participant")
    check(p:GetAttribute("BeingChased")==true,"entering a table preserves existing BeingChased")
    check(HidingController.GetAnchor(p,7)==a,"real hiding entry publishes authoritative chase anchor")
end
do
    local s=session()
    local near,far=player(2,10),player(1,30)
    local a=anchor(12); hide(near,a); roster={far,near}
    check(nearestLivingPlayer(s)==near,"nearer hidden player beats farther exposed player")
    hide(far,anchor(32))
    check(nearestLivingPlayer(s)==near,"all-hidden roster still has a nearest target")
    publishTarget(s,near)
    check(s.Target==near and near:GetAttribute("BeingChased")==true,"hidden target receives BeingChased")
    trackNearestBlackoutPlayer(s,cpuNow)
    check(s.State=="CHASE" and s.Target==near and near:GetAttribute("BeingChased")==true,"hidden target stays chased on subsequent think")
    check(s.TargetTableAnchor==a and s.Goal==a.Position,"hidden chase routes to authoritative table anchor")
    check(s.StateFolder:GetAttribute("Level3_MallManagerTargetMode")=="NEAREST_PLAYER","hidden chase publishes nearest-player telemetry")
    releasePlayer(hiddenSession,far); far.Character.Root.Position=Vector3.new(5,0,0)
    trackNearestBlackoutPlayer(s,cpuNow)
    check(s.Target==far and s.TargetTableAnchor==nil and near:GetAttribute("BeingChased")==false,"nearer exposed player takes chase and clears old hidden mark")
    check(s.Goal.X==5,"exposed chase uses the player's location")
    near.Character.Root.Position=Vector3.new(-5,0,0)
    check(nearestLivingPlayer(s)==far,"equal-distance tie remains deterministic by UserId")
end
do
    local p=player(8,10); local a=anchor(12); hide(p,a)
    check(HidingController.GetAnchor(p,7)==a,"matching hiding record exposes authoritative anchor")
    check(HidingController.GetAnchor(p,8)==nil,"another generation cannot expose old anchor")
    local record=hiddenSession.HiddenPlayers[p]
    record.Generation=6
    check(HidingController.GetAnchor(p,7)==nil,"stale record generation rejected")
    record.Generation=7; record.Character={}
    check(HidingController.GetAnchor(p,7)==nil,"old character's hiding record rejected")
    record.Character=p.Character; a.Parent=nil
    check(HidingController.GetAnchor(p,7)==nil,"destroyed anchor rejected")
    a.Parent=true; p:SetAttribute("Level3_Hiding",false)
    check(HidingController.GetAnchor(p,7)==nil,"stale hiding record without active state rejected")
end
local function tableFixture()
    workspace.Wall=false; serverNow=100; cpuNow=10
    local s=session(); local p=player(10,10); local a=anchor(12)
    hide(p,a); roster={p}; trackNearestBlackoutPlayer(s,cpuNow)
    s.NextTableCheckAt=999; s.AnchorCheckCooldown[a]=999
    return s,p,a
end
do
    local s,p,a=tableFixture()
    check(updateTableCheck(s,cpuNow)==true,"targeted chase starts table check despite random-patrol cooldown")
    check(s.State=="TABLE_CHECK" and s.TableCheckAnchor==a,"table check owns movement and the target anchor")
    check(s.TableCheckEndsAt==102 and s.PublishedEndsAt==102,"warning gives exactly two server-time seconds")
    check(not attackLineClear(s,p,100),"hiding remains protected from a direct attack")
    local before=#released
    serverNow=101.99; cpuNow=1000
    check(updateTableCheck(s,cpuNow)==true and #released==before,"CPU-clock advance cannot shorten visible reaction window")
    serverNow=102
    check(updateTableCheck(s,cpuNow)==false and released[#released]==p,"occupant flushes when warning reaches zero")
    check(HidingController.IsFlushImmune(p) and not attackLineClear(s,p,100),"flush grants protected head start")
    serverNow=103.49
    check(HidingController.IsFlushImmune(p),"flush immunity lasts almost 1.5 server seconds")
    serverNow=103.5
    check(not HidingController.IsFlushImmune(p) and attackLineClear(s,p,100),"attack resumes after exact 1.5-second immunity")
end
for _,reason in {"wall","distance","exposed","dead","nearer"} do
    local s,p,a=tableFixture()
    if reason=="wall" then workspace.Wall=true
    elseif reason=="distance" then s.Root.Position=Vector3.new(-3,0,0)
    elseif reason=="exposed" then releasePlayer(hiddenSession,p)
    elseif reason=="dead" then p.Character.Human.Health=0
    else table.insert(roster,player(9,5)) end
    check(updateTableCheck(s,cpuNow)==false and s.TableCheckAnchor==nil,"table check refuses invalid approach: "..reason)
end
for _,reason in {"exit","death","nearer","wall","removed","round"} do
    local s,p,a=tableFixture(); updateTableCheck(s,cpuNow)
    local before=#released
    if reason=="exit" then releasePlayer(hiddenSession,p); before=#released
    elseif reason=="death" then p.Character.Human.Health=0
    elseif reason=="nearer" then table.insert(roster,player(9,5))
    elseif reason=="wall" then workspace.Wall=true
    elseif reason=="removed" then a.Parent=nil
    else s.Valid=false end
    serverNow=102.1
    check(updateTableCheck(s,cpuNow)==false and s.TableCheckAnchor==nil and #released==before,
        "active warning cancels without flushing invalid target: "..reason)
end
do
    local s,p=tableFixture(); releasePlayer(hiddenSession,p)
    workspace.Wall=true
    check(not attackLineClear(s,p,100),"wall still blocks an exposed player's direct attack")
    workspace.Wall=false
    check(not attackLineClear(s,p,4),"direct attack retains its range gate")
    check(attackLineClear(s,p,100),"eligible exposed target remains attackable")
end
'''

FINISH = r'''
for _,message in failures do print("FAIL: "..message) end
assert(#failures==0,tostring(#failures).." of "..checks.." hidden-chase checks failed")
print("Level 3 hidden chase: "..checks.." checks passed (offline helpers; engine geometry stubbed)")
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-ref")
    args = parser.parse_args()
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests executed.")
    ai = ((ROOT / AI_PATH).read_text(encoding="utf-8") if not args.baseline_ref else
          subprocess.check_output(["git", "show", f"{args.baseline_ref}:{AI_PATH}"], cwd=ROOT, encoding="utf-8"))
    hiding = (ROOT / HIDING_PATH).read_text(encoding="utf-8")
    config = (ROOT / CONFIG_PATH).read_text(encoding="utf-8")
    pieces = [PRELUDE, "local Configuration=(function()", config, "end)()", HIDING_PRELUDE,
              section(hiding, "function Controller.IsHidden", "function Controller.SetFurnitureSuspended"),
              section(hiding, "function Controller.OccupantCount", "function Controller.GetOccupiedAnchors"),
              section(hiding, "function Controller.FlushAnchor", "function Controller.GetSnapshot"),
              section(hiding, "local function tryEnter", "local function bindPlayer"),
              "Controller.TestTryEnter=tryEnter\nreturn Controller\nend)()", AI_PRELUDE,
              section(ai, "local function livingPlayer", "local function profile"), ELIGIBILITY_TESTS]
    if not args.baseline_ref:
        pieces.extend([
            section(ai, "local function publishTargetTelemetry", "local function publishState"),
            section(ai, "local function navigationGoalLineClear", "-- LEVEL3_MANAGER_WALL_HUG_GOAL"),
            section(ai, "local function nearestLivingPlayer", "local function beginSearch"),
            section(ai, "local function endTableCheck", "local function beginAttack"), TESTS])
    pieces.append(FINISH)
    with tempfile.TemporaryDirectory(prefix="level3-hidden-chase-") as directory:
        fixture = Path(directory) / "hidden_chase.luau"
        fixture.write_text("\n".join(pieces), encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == "__main__":
    main()
