"""Execute production Level 3 patrol, table skill check and hiding helpers in Luau.

Character lifecycle, release/controls, immunity clocks and random thresholds run
the real helpers. Engine clearance, sight and CFrame rotation are fixture stubs;
generated-world navigation and rotated table exits remain Studio checks.
--baseline-ref HEAD checks the former hidden-target routing against the new rule.
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
    return {Class=class,Attributes={},Parent=true,Children={},
        IsA=function(self,c) return self.Class==c end,
        IsDescendantOf=function(self,ancestor)
            local current=self.Parent
            while type(current)=="table" do
                if current==ancestor then return true end
                current=current.Parent
            end
            return false
        end,
        GetChildren=function(self) return self.Children end,
        GetAttribute=function(self,k) return self.Attributes[k] end,
        SetAttribute=function(self,k,v) self.Attributes[k]=v end,
        Play=function(self) self.Played=true end,
        Destroy=function(self) self.Parent=nil end}
end
local Instance={new=object}
local Enum={RollOffMode={InverseTapered="InverseTapered"},HumanoidDisplayDistanceType={None="None"}}
local task={spawn=function() end}
local roster={}
local Players={GetPlayers=function() return roster end}
local PlayerProtection={IsActive=function(p) return p.Protected==true end}
local rayWall=object("BasePart")
local workspace={Wall=false,SightBlocked=false,RayCount=0,SightBlockers={},RayLog={},
    GetServerTimeNow=function() return serverNow end,GetAttribute=function() return nil end,
    Raycast=function(self,origin,direction,params)
        self.RayCount+=1
        table.insert(self.RayLog,{Origin=origin,Direction=direction,Params=params})
        if self.Wall then return {Instance=rayWall} end
        if params.Kind=="Sight" then
            if self.SightBlocked then return {Instance=rayWall} end
            if self.RequireLowTarget and (origin+direction).Y>self.RequireLowTarget then return {Instance=rayWall} end
            for _,part in self.SightBlockers do
                if not table.find(params.FilterDescendantsInstances,part) then return {Instance=part} end
            end
        end
        return nil
    end}
local hiddenSession={Active=true,Generation=7,HiddenPlayers={},Occupants={},FlushImmuneUntil={},FlushImmuneCharacters={},
    AnchorSet={},Anchors={},LastAction={},World={}}
local checks,failures=0,{}
local function check(value,message)
    checks+=1
    if not value then table.insert(failures,message) end
end
local function validRound(s) return s.Valid~=false and s.Generation==7 end
local function player(id,x)
    local p=object("Player"); p.UserId=id; p.Parent=Players; p.Attributes={InRound=true}
    local root=object("BasePart"); root.Position=Vector3.new(x,0,0); root.Anchored=false
    root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero
    local human={Parent=true,Health=100,AutoRotate=true,WalkSpeed=16,JumpPower=50,JumpHeight=7.2,
        DisplayDistanceType="Viewer"}
    p.Character={Parent=true,Root=root,Human=human,
        PivotTo=function(self,cf) self.Root.Position=cf.Position end,
        FindFirstChild=function(self,n) return n=="HumanoidRootPart" and self.Root or nil end,
        FindFirstChildOfClass=function(self,n) return n=="Humanoid" and self.Human or nil end}
    root.Parent=p.Character
    return p
end
local function anchor(x)
    local a=object("BasePart"); a.Position=Vector3.new(x,0,0); a.CFrame=CFrame.new(a.Position)
    a.Parent=object("Model"); a.Parent.Parent=hiddenSession.World; table.insert(a.Parent.Children,a)
    a.Attributes.Level3_HideTableIndex=#hiddenSession.Anchors+1
    hiddenSession.AnchorSet[a]=true; hiddenSession.Occupants[a]={}
    table.insert(hiddenSession.Anchors,a)
    return a
end
local function reset()
    workspace.Wall=false; workspace.SightBlocked=false; workspace.RoomBoundary=math.huge; serverNow=100; cpuNow=10
    workspace.SightBlockers={}; workspace.RayLog={}; workspace.RequireLowTarget=nil
    roster={}; hiddenSession.HiddenPlayers={}; hiddenSession.Occupants={}; hiddenSession.Anchors={}
    hiddenSession.AnchorSet={}; hiddenSession.LastAction={}; hiddenSession.FlushImmuneUntil={}; hiddenSession.FlushImmuneCharacters={}
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
local function slotLateral(slot) return (slot==1 and -1 or 1)*Tuning.HideOccupantLateralOffset end
local function roundAllowsHiding(s) return liveSession(s) end
local function eligible(p) return p.Character,p.Character.Human,p.Character.Root end
local function captureCollisionState() return {} end
local function suppressCollision() end
local function restoreCollision() end
local function refreshPrompt() end
local function updateHiddenCount() end
local function cdOnTable() return false end
local function pivotRootTo(character,root,cf) character:PivotTo(cf) end
'''

AI_PRELUDE = r'''
local Tuning=Configuration.MallManager
local TableCheckTuning=Configuration.TableCheck
local debugTableChecksSuspended=false
local function liveSession(s) return validRound(s) end
local function profile(s) return s.Blackout and Tuning.Blackout or Tuning.Normal end
local function planarDistance(a,b) return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
local function flat(p,y) return Vector3.new(p.X,y,p.Z) end
local function stopChaseScream() end
local function publishState(s,state) s.State=state end
local function publishTableCheck(s,a,t) s.PublishedAnchor=a; s.PublishedEndsAt=t end
local function clearGoal(s) s.Goal=nil; s.FinalGoal=nil end
local function facePosition(s,p) s.FacingTarget=p end
local function arrivalGoal(s) return s.Goal end
local function setGoal(s,p,force)
    s.Goal=p; s.FinalGoal=p; s.ForcedGoal=force
    s.SetGoalCalls=(s.SetGoalCalls or 0)+1
    -- The engine builds this route while accepting the goal. Tests may supply
    -- maze detours without duplicating the production room-routing algorithm.
    if s.FixtureStrategicPoints then
        s.StrategicPoints=table.clone(s.FixtureStrategicPoints); s.StrategicIndex=1
    end
end
local function volumeFits(s,p)
    if s.VolumesBlocked then return false end
    local envelope=s.TableEnvelope
    if envelope then
        local delta=p-envelope.Anchor.Position
        local c,sine=math.cos(envelope.Yaw),math.sin(envelope.Yaw)
        local localX=c*delta.X-sine*delta.Z
        local localZ=sine*delta.X+c*delta.Z
        if math.abs(localX)<11.85 and math.abs(localZ)<11.65 then return false end
    end
    return true
end
local function navigationPointClear(s,p) return volumeFits(s,p) end
local function navigationParams() return {Kind="Navigation"} end
local function sightParams(s,character) return {Kind="Sight",FilterDescendantsInstances={s.Model}} end
local function layoutRooms() return {{Id="A",X=40,Z=40,W=80,D=80},{Id="B",X=80,Z=80,W=80,D=80}} end
local function roomDefinition(id) for _,r in layoutRooms() do if r.Id==id then return r end end end
local function roomCenter(id,y) local r=roomDefinition(id); return Vector3.new(r.X,y,r.Z) end
local function roomIdContaining(p) return p.X<=workspace.RoomBoundary and "A" or "B" end
local function insideFinalHall(s,p) return p.Z>=100 end
local function session()
    local s={Generation=7,Valid=true,Blackout=true,Root={Position=Vector3.zero},FloorY=0,
        Model=object("Model"),StateFolder=object("Folder"),State="PATROL",ActivatedAt=0,
        AnchorCheckCooldown={},NextTableCheckAt=0,AttackToken=0,Attacking=false,
        RecentPatrolRooms={},Suspicion={},LastVisualAt=-math.huge,LastSenseAt=-math.huge,
        Roll=0,RandomRollCount=0,TableCheckSerial=0,TableCheckFlushCount=0}
    s.Random={NextNumber=function(_,a,b)
            if a then return a+(b-a)*s.Roll end
            s.RandomRollCount+=1; return s.Roll
        end,
        NextInteger=function(_,a,b) return s.PickLast and b or a end}
    return s
end
local function hide(p,a)
    p.Character.Root.Position=a.Position+Vector3.new(0,0,4)
    local entered,reason=HidingController.TestTryEnter(hiddenSession,p,a)
    assert(entered,reason)
end
'''

BASELINE_TESTS = r'''
reset()
local s=session(); local p=player(1,10); local a=anchor(12); hide(p,a); roster={p}
trackNearestBlackoutPlayer(s,cpuNow)
check(s.State=="PATROL" and s.Target==nil,"an all-hidden roster patrols without a direct chase target")
check(p:GetAttribute("BeingChased")~=true,"hidden-only patrol clears BeingChased")
'''

TESTS = r'''
check(TableCheckTuning.SkillCheckSuccessChance==.25,"entity skill check is configured for 25 percent success")
do
    reset(); local s=session(); local destination=Vector3.new(20,0,0)
    local directBudget=blackoutSweepLegDuration(20)
    local route={Vector3.new(0,0,60),Vector3.new(60,0,60),destination}
    local lastLeg=planarDistance(route[2],destination)
    s.StrategicPoints=route
    local fullBudget=tablePatrolLegDuration(s,destination)
    check(math.abs(fullBudget-blackoutSweepLegDuration(120+lastLeg))<.001
        and fullBudget>directBudget,"table patrol budgets the legal maze detour rather than direct proximity")
    s.StrategicIndex=2
    local remainingBudget=tablePatrolLegDuration(s,destination)
    check(math.abs(remainingBudget-blackoutSweepLegDuration(route[2].Magnitude+lastLeg))<.001
        and remainingBudget<fullBudget,"table patrol budgets only strategic points not yet completed")
    s.StrategicIndex=#route+1
    check(tablePatrolLegDuration(s,destination)==directBudget,
        "an exhausted strategic route retains the direct-distance minimum budget")
    s.StrategicPoints=nil; s.StrategicIndex=nil
    check(tablePatrolLegDuration(s,destination)==directBudget,
        "table patrol without a strategic route uses the existing direct-distance budget")
    s.StrategicPoints={Vector3.new(5,0,0),Vector3.new(10,0,0)}
    check(tablePatrolLegDuration(s,destination)>=directBudget,
        "nearer intermediate points cannot shorten a table patrol below its direct-distance budget")

    local p=player(1,8); local a=anchor(8); hide(p,a); roster={p}
    s.FixtureStrategicPoints=route
    trackNearestBlackoutPlayer(s,cpuNow)
    local originalGoal=s.Goal; local deadline=s.PatrolLegUntil
    check(s.TableCheckTargetAnchor==a and originalGoal
        and planarDistance(originalGoal,destination)<.001,
        "occupied table selection uses the expected perimeter destination")
    check(math.abs(deadline-(cpuNow+fullBudget))<.001 and s.SetGoalCalls==1,
        "table patrol fixes its route-based deadline after accepting the navigation goal")
    s.Root.Position=Vector3.new(0,0,20); cpuNow+=directBudget+.5
    trackNearestBlackoutPlayer(s,cpuNow)
    check(s.TableCheckTargetAnchor==a and s.Goal==originalGoal and s.AnchorCheckCooldown[a]==nil,
        "a progressing maze detour keeps its table after the former direct-distance deadline")
    check(s.PatrolLegUntil==deadline and s.SetGoalCalls==1,
        "a progressing brain tick never renews the table patrol deadline")
    s.Root.Position=Vector3.new(0,0,40); cpuNow+=5
    trackNearestBlackoutPlayer(s,cpuNow)
    check(s.PatrolLegUntil==deadline and s.SetGoalCalls==1,
        "continued route progress preserves the same bounded patrol deadline")
    cpuNow=deadline+.01
    trackNearestBlackoutPlayer(s,cpuNow)
    check(s.TableCheckTargetAnchor==nil and s.Goal~=originalGoal
        and math.abs(s.AnchorCheckCooldown[a]-(cpuNow+TableCheckTuning.AnchorCooldownSeconds))<.001,
        "a table patrol that exceeds its fixed maze-route budget retires the target and moves on")
end
do
    reset(); local s=session(); local p=player(1,10); local a=anchor(12); hide(p,a)
    check(select(3,livingPlayer(p,s))==p.Character.Root,"hidden participant stays eligible for occupancy and spawn selection")
    p.Protected=true; check(livingPlayer(p,s)==nil,"protected life excluded"); p.Protected=false
    p.Character.Human.Health=0; check(livingPlayer(p,s)==nil,"dead participant excluded")
    p.Character.Human.Health=100; p:SetAttribute("Escaped",true)
    check(livingPlayer(p,s)==nil,"escaped participant excluded")
    p:SetAttribute("Escaped",false); p:SetAttribute("InRound",false)
    check(livingPlayer(p,s)==nil,"nonparticipant excluded"); p:SetAttribute("InRound",true)
    p.Parent=nil; check(livingPlayer(p,s)==nil,"disconnected participant excluded"); p.Parent=Players
    s.Valid=false; check(livingPlayer(p,s)==nil,"inactive round excluded"); s.Valid=true
    p.Character.Parent=nil; check(livingPlayer(p,s)==nil,"removed character excluded")
end
do
    reset(); local s=session(); local near,far=player(2,10),player(1,30)
    local a,b=anchor(12),anchor(32); hide(near,a); roster={far,near}
    check(nearestLivingPlayer(s)==near,"hidden player remains eligible for nearest living selection")
    publishTarget(s,near); trackNearestBlackoutPlayer(s,cpuNow)
    check(s.State=="CHASE" and s.Target==far,"exposed player owns chase even when a hider is closer")
    check(near:GetAttribute("BeingChased")==false and far:GetAttribute("BeingChased")==true,
        "chase flags follow the exposed target")
    check(s.TargetTableAnchor==nil and s.Goal.X==30,"exposed chase follows the player's location")
    hide(far,b); trackNearestBlackoutPlayer(s,cpuNow)
    check(s.State=="PATROL" and s.Target==nil,"all-hidden roster walks a patrol instead of a chase")
    check(far:GetAttribute("BeingChased")==false,"hiding clears the prior chase flag on the next AI tick")
    local target=s.TableCheckTargetAnchor
    check(target~=nil and s.Goal~=nil,"hidden-only patrol chooses an occupied table vicinity")
    check(target and planarDistance(s.Goal,target.Position)>=10,"hidden patrol keeps a clear offset from the table centre")
    HidingController.TestRelease(hiddenSession,far,true)
    far.Character.Root.Position=Vector3.new(5,0,0); trackNearestBlackoutPlayer(s,cpuNow)
    check(s.Target==far and s.State=="CHASE","voluntary exit resumes an exposed-player chase")
end
do
    reset(); local p=player(8,10); local a=anchor(12); hide(p,a)
    check(HidingController.GetAnchor(p,7)==a,"matching server hiding record exposes its anchor")
    check(HidingController.GetAnchor(p,8)==nil,"another generation rejects old anchor")
    local record=hiddenSession.HiddenPlayers[p]; record.Generation=6
    check(HidingController.GetAnchor(p,7)==nil,"stale record generation rejected"); record.Generation=7
    record.Character={}; check(HidingController.GetAnchor(p,7)==nil,"old character's hiding record rejected")
    record.Character=p.Character; a.Parent=nil
    check(HidingController.GetAnchor(p,7)==nil,"destroyed anchor rejected"); a.Parent=true
    p:SetAttribute("Level3_Hiding",false)
    check(HidingController.GetAnchor(p,7)==nil,"inactive hiding state rejects stale record")
end
do
    reset(); local s=session(); local p=player(1,10); local a=anchor(12); hide(p,a); roster={p}
    workspace.RoomBoundary=20
    trackNearestBlackoutPlayer(s,cpuNow)
    check(s.Goal and roomIdContaining(s.Goal)==roomIdContaining(a.Position),"table patrol ring stays inside its anchor's room")
    check(s.Goal and s.Goal.X<=20,"out-of-room first patrol angle is rejected")
    s.VolumesBlocked=true; s.PatrolGoal=nil
    trackNearestBlackoutPlayer(s,cpuNow)
    check(s.TableCheckTargetAnchor==nil and s.Goal~=nil,"no clear table perimeter falls back to a room patrol")
    check(s.AnchorCheckCooldown[a]==35,"unreachable table receives a bounded retry cooldown")
end
-- Studio's inflated table navigation rectangle can contain all eight points
-- on the old 12-stud ring at a 22.5-degree sampling phase. A clear goal must
-- still reach the 14-stud inspection range for authored and rotated tables.
for _,yaw in {0,math.pi/8,math.pi/4,math.pi/2} do
    reset(); local s=session(); local p=player(1,10); local a=anchor(12); hide(p,a); roster={p}
    s.Roll=(yaw+math.pi/8)/(math.pi*2)
    s.TableEnvelope={Anchor=a,Yaw=yaw}
    trackNearestBlackoutPlayer(s,cpuNow)
    check(s.TableCheckTargetAnchor==a and s.Goal~=nil,
        "rotated table footprint retains an occupied-table patrol destination")
    check(s.Goal and volumeFits(s,s.Goal),
        "rotated table patrol destination clears the inflated navigation rectangle")
    check(s.Goal and planarDistance(s.Goal,a.Position)<=TableCheckTuning.StartRange,
        "worst-phase patrol destination remains close enough to inspect its table")
    if s.Goal then s.Root.Position=s.Goal end
    check(updateTableCheck(s,cpuNow)==true and s.TableCheckAnchor==a,
        "arriving at a clear rotated-table patrol goal permits the inspection")
end
do
    reset(); local s=session(); local p=player(1,10); local a=anchor(12); hide(p,a); roster={p}
    s.ActivatedAt=11; trackNearestBlackoutPlayer(s,cpuNow)
    check(s.State=="AWAKENING" and s.Goal==nil,"hidden-player patrol waits for spawn activation")
end
do
    reset(); local s=session(); s.FinalHallChase=true
    trackNearestBlackoutPlayer(s,cpuNow)
    check(s.State=="WAITING" and s.Goal==nil,"empty finale preserves the exit-lane wait")
    local near,runner=player(1,5),player(2,40); runner.Character.Root.Position=Vector3.new(40,0,120)
    roster={near,runner}; trackNearestBlackoutPlayer(s,cpuNow)
    check(s.Target==runner and s.State=="CHASE","finale still prioritizes a runner in the exit lane")
end
local function tableFixture(roll)
    reset(); local s=session(); s.Roll=roll or 0
    local p=player(10,10); local a=anchor(12); hide(p,a); roster={p}
    trackNearestBlackoutPlayer(s,cpuNow)
    return s,p,a
end
local function tableSightPart(a,synthetic,offset)
    local part=object("BasePart"); part.Position=a.Position+(offset or Vector3.zero)
    part.Parent=a.Parent; part.Attributes.Level3_HideSightOccluder=synthetic
    table.insert(a.Parent.Children,part)
    return part
end
do
    local s,p,a=tableFixture(); local occluder=tableSightPart(a,true)
    workspace.SightBlockers={occluder}
    check(not hasSightRay(s,p.Character,p.Character.Root),"synthetic table occluder still blocks ordinary standing vision")
    workspace.RayLog={}
    check(hasTableInspectionSight(s,a,p.Character,p.Character.Root),"kneeling inspection can see through only its own synthetic occluder")
    local ray=workspace.RayLog[1]
    check(table.find(ray.Params.FilterDescendantsInstances,occluder)~=nil,
        "inspection ray explicitly excludes this table's synthetic sight part")
    check(table.find(ray.Params.FilterDescendantsInstances,s.Model)~=nil,
        "inspection preserves the normal sight filter's existing exclusions")
    check(ray.Origin.Y==s.FloorY+1.6,"inspection casts from the authored low eye height")
    check(not hasSightRay(s,p.Character,p.Character.Root),"inspection does not alter ordinary vision filters")
    check(updateTableCheck(s,cpuNow)==true,"real discovery helper begins a check despite the inspected table's synthetic occluder")
    serverNow=101
    check(updateTableCheck(s,cpuNow)==true,"active warning uses the same under-table inspection visibility")
end
for _,reason in {"otherTable","otherCentre","realFurniture","wall"} do
    local s,p,a=tableFixture(); local own=tableSightPart(a,true); local blocker
    if reason=="otherTable" then blocker=tableSightPart(anchor(40),true)
    elseif reason=="otherCentre" then blocker=tableSightPart(a,true,Vector3.new(3,0,0))
    elseif reason=="realFurniture" then blocker=tableSightPart(a,false)
    else workspace.Wall=true end
    workspace.SightBlockers=blocker and {own,blocker} or {own}
    check(not hasTableInspectionSight(s,a,p.Character,p.Character.Root),"inspection retains sight obstruction: "..reason)
    if blocker then
        check(not table.find(workspace.RayLog[1].Params.FilterDescendantsInstances,blocker),
            "inspection never excludes unrelated physical or synthetic geometry: "..reason)
    end
    check(updateTableCheck(s,cpuNow)==false,"discovery is still blocked by geometry: "..reason)
end
do
    local s,p,a=tableFixture(); s.FloorY=20; s.Root.Position=Vector3.new(0,24,0)
    workspace.RequireLowTarget=p.Character.Root.Position.Y-2.1; workspace.RayLog={}
    check(hasTableInspectionSight(s,a,p.Character,p.Character.Root),"inspection tries the lower root target when the first ray is blocked")
    check(#workspace.RayLog==2 and workspace.RayLog[1].Origin.Y==21.6
        and workspace.RayLog[2].Origin.Y==21.6,"inspection eye height follows floor rather than entity root height")
    local first=workspace.RayLog[1]; local second=workspace.RayLog[2]
    check((first.Origin+first.Direction-p.Character.Root.Position).Magnitude<.001
        and (second.Origin+second.Direction-(p.Character.Root.Position-Vector3.new(0,2.1,0))).Magnitude<.001,
        "inspection tests exactly root and root minus2.1 studs")
end
do
    local s,p,a=tableFixture(); workspace.SightBlockers={p.Character.Root}
    check(hasTableInspectionSight(s,a,p.Character,p.Character.Root),"inspection ray hitting the target character counts as visible")
end
for _,reason in {"wall","sight","distance","exposed","dead","protected","anchorCooldown","globalCooldown","disabled","round"} do
    local s,p,a=tableFixture()
    if reason=="wall" then workspace.Wall=true
    elseif reason=="sight" then workspace.SightBlocked=true
    elseif reason=="distance" then s.Root.Position=Vector3.new(-3,0,0)
    elseif reason=="exposed" then HidingController.TestRelease(hiddenSession,p,true)
    elseif reason=="dead" then p.Character.Human.Health=0
    elseif reason=="protected" then p.Protected=true
    elseif reason=="anchorCooldown" then s.AnchorCheckCooldown[a]=999
    elseif reason=="globalCooldown" then s.NextTableCheckAt=999
    elseif reason=="disabled" then debugTableChecksSuspended=true
    else s.Valid=false end
    check(updateTableCheck(s,cpuNow)==false and s.TableCheckAnchor==nil,"table check refuses invalid approach: "..reason)
    debugTableChecksSuspended=false
end
do
    local s,p,a=tableFixture(0)
    check(updateTableCheck(s,cpuNow)==true,"nearby visible occupant starts a skill check")
    check(s.State=="TABLE_CHECK" and s.TableCheckAnchor==a,"warning owns movement and the spotted table")
    check(s.TableCheckEndsAt==102 and s.PublishedEndsAt==102,"warning gives exactly two server-time seconds")
    check(s.NextTableCheckAt==28,"beginning warning schedules the global 18-second rate limit")
    check(s.RandomRollCount==0,"beginning warning does not roll the completed skill check")
    check(not attackLineClear(s,p,100),"hiding protects against a direct attack")
    serverNow=101.99; cpuNow=1000
    check(updateTableCheck(s,cpuNow)==true and HidingController.IsHidden(p),"CPU-clock advance cannot shorten visible warning")
    serverNow=102
    check(updateTableCheck(s,cpuNow)==false and not HidingController.IsHidden(p),"successful roll shoves the occupant when warning ends")
    check(s.LastTableCheckResult=="SUCCESS" and s.TableCheckFlushCount==1,"success telemetry records the ejected occupant")
    check(s.TableCheckSerial==1 and s.RandomRollCount==1,"one completed warning consumes exactly one skill roll")
    check(s.Target==p and s.State=="CHASE","successful shove resumes exposed-player chase")
    check(p.Character.Root.Anchored==false and p.Character.Human.WalkSpeed==16
        and p.Character.Human.AutoRotate==true,"shove restores player movement controls")
    check(HidingController.IsFlushImmune(p) and not attackLineClear(s,p,100),"shove grants a protected head start")
    serverNow=103.49; check(HidingController.IsFlushImmune(p),"head start lasts almost 1.5 server seconds")
    serverNow=103.5
    check(not HidingController.IsFlushImmune(p) and attackLineClear(s,p,100),"attack resumes at exact 1.5-second expiry")
end
for _,roll in {0,.249999,.25,.999999} do
    local s,p,a=tableFixture(roll)
    updateTableCheck(s,cpuNow); serverNow=102; updateTableCheck(s,cpuNow)
    check(HidingController.IsHidden(p)==(roll>=.25),"25-percent skill check boundary at roll "..tostring(roll))
end
do
    local s,p,a=tableFixture(.75); local other=player(11,40); local b=anchor(42)
    hide(other,b); table.insert(roster,other)
    updateTableCheck(s,cpuNow); serverNow=102; cpuNow=12
    check(updateTableCheck(s,cpuNow)==false,"failed roll releases the warning")
    check(HidingController.IsHidden(p) and not HidingController.IsFlushImmune(p),"failed check preserves hiding and grants no immunity")
    check(s.LastTableCheckResult=="FAILED" and s.TableCheckFlushCount==0,"failure telemetry records zero ejections")
    check(s.State=="PATROL" and s.Target==nil and s.FinalGoal~=nil,"failure chooses a movement goal immediately")
    check(s.TableCheckTargetAnchor==b,"failure heads toward the other occupied table")
    check(s.AnchorCheckCooldown[a]==37,"failed table receives its 25-second cooldown")
    check(s.LastKnownPosition==nil and s.SearchUntil==nil,"failure clears prior chase/search memory")
    s.Root.Position=s.Goal; cpuNow=20
    trackNearestBlackoutPlayer(s,cpuNow)
    check(s.AnchorCheckCooldown[b]==nil,"arriving near next table during global cooldown does not retire it")
    check(s.TableCheckTargetAnchor==b and s.Goal~=nil,"arrival keeps walking around the next occupied table")
    s.Root.Position=Vector3.new(42,0,0)
    check(updateTableCheck(s,cpuNow)==false,"another table cannot bypass the global cooldown")
    cpuNow=28
    check(updateTableCheck(s,cpuNow)==true and s.TableCheckAnchor==b,"another occupied table becomes checkable at global expiry")
end
for _,reason in {"exit","death","sight","wall","removed","round","life"} do
    local s,p,a=tableFixture(0); updateTableCheck(s,cpuNow)
    if reason=="exit" then HidingController.TestRelease(hiddenSession,p,true)
    elseif reason=="death" then p.Character.Human.Health=0
    elseif reason=="sight" then workspace.SightBlocked=true
    elseif reason=="wall" then workspace.Wall=true
    elseif reason=="removed" then a.Parent=nil
    elseif reason=="life" then
        HidingController.TestRelease(hiddenSession,p,true)
        p.Character=player(99,10).Character; cpuNow=11; hide(p,a)
    else s.Valid=false end
    local before=HidingController.IsHidden(p)
    serverNow=102.1
    check(updateTableCheck(s,cpuNow)==false and s.TableCheckAnchor==nil
        and HidingController.IsHidden(p)==before and not HidingController.IsFlushImmune(p),
        "warning cancels without shoving invalid occupant: "..reason)
    check(s.TableCheckSerial==0 and s.RandomRollCount==0,"cancelled warning consumes no skill roll: "..reason)
end
do
    reset(); local first,second=player(21,10),player(22,10); local a=anchor(12)
    hide(first,a); hide(second,a)
    local flushed=HidingController.FlushAnchor(a,a.Position+Vector3.new(0,0,12))
    check(#flushed==2 and HidingController.OccupantCount(a)==0,"successful table shove releases both occupied lanes")
    check(first.Character.Root.Position.Z<0 and second.Character.Root.Position.Z<0,"shove exits opposite the entity approach")
    check(first.Character.Root.Position.X~=second.Character.Root.Position.X,"shared table shove preserves separate exit lanes")
    check(HidingController.IsFlushImmune(first) and HidingController.IsFlushImmune(second),"both ejected occupants receive immunity")
    local oldCharacter=first.Character; first.Character=player(99,0).Character
    check(not HidingController.IsFlushImmune(first),"a replacement character never inherits old-life shove immunity")
    first.Character=oldCharacter
    check(#HidingController.FlushAnchor(a,a.Position)==0,"empty table shove is a no-op")
end
do
    local s,p=tableFixture(); HidingController.TestRelease(hiddenSession,p,true)
    workspace.SightBlocked=true; check(not attackLineClear(s,p,100),"wall blocks exposed-player attack")
    workspace.SightBlocked=false; check(not attackLineClear(s,p,4),"direct attack retains its range gate")
    check(attackLineClear(s,p,100),"eligible exposed target remains attackable")
end
'''

FINISH = r'''
for _,message in failures do print("FAIL: "..message) end
assert(#failures==0,tostring(#failures).." of "..checks.." hidden-patrol checks failed")
print("Level 3 hidden patrol: "..checks.." checks passed (offline helpers; engine geometry stubbed)")
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
              section(hiding, "local function releasePlayer", "local function releaseAll"),
              section(hiding, "function Controller.IsHidden", "function Controller.SetFurnitureSuspended"),
              section(hiding, "local function aiOccupant", "function Controller.GetSnapshot"),
              section(hiding, "local function tryEnter", "local function bindPlayer"),
              "Controller.TestTryEnter=tryEnter\nController.TestRelease=releasePlayer\nreturn Controller\nend)()",
              AI_PRELUDE, section(ai, "local function livingPlayer", "local function profile"),
              section(ai, "local function publishTargetTelemetry", "local function publishState"),
              section(ai, "local function hasSightRay", "local function flashlightOn"),
              section(ai, "local function navigationGoalLineClear", "-- LEVEL3_MANAGER_WALL_HUG_GOAL"),
              section(ai, "local function blackoutSweepLegDuration", "local function beginSearch")]
    if args.baseline_ref:
        pieces.append(BASELINE_TESTS)
    else:
        pieces.extend([section(ai, "local function endTableCheck", "local function beginAttack"), TESTS])
    pieces.append(FINISH)
    with tempfile.TemporaryDirectory(prefix="level3-hidden-patrol-") as directory:
        fixture = Path(directory) / "hidden_patrol.luau"
        fixture.write_text("\n".join(pieces), encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == "__main__":
    main()
