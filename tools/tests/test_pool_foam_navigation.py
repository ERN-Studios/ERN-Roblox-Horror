"""Exercise the real navigator's async route lifecycle in offline Luau.

Geometry and engine path queries are replaced with deterministic fixtures. The
real SetGoal, SetGraphGoal, request installer and body-checked route join run.
This covers route churn/backtracking; generated geometry needs Studio playtests.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "ServerScriptService/Level 2 Systems/Level 2 Pool Foam Navigator.ModuleScript.lua").read_text(encoding="utf-8")
CONTROLLER = (ROOT / "ServerScriptService/Level 2 Systems/Level 2 Pool Foam Controller.ModuleScript.lua").read_text(encoding="utf-8")

PRELUDE = r'''
local clock = 100
local os = table.clone(os)
os.clock = function() return clock end
local Vector3 = {}
local vectorMethods = {}
local vectorMeta = {
    __index = function(v, key)
        if key == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
        if key == "Unit" then return Vector3.new(v.X,v.Y,v.Z)/v.Magnitude end
        return vectorMethods[key]
    end,
    __add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end,
    __sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end,
    __mul = function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end,
    __div = function(a,b) return Vector3.new(a.X/b,a.Y/b,a.Z/b) end,
}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end
function vectorMethods:Dot(v) return self.X*v.X+self.Y*v.Y+self.Z*v.Z end
function vectorMethods:Lerp(v,t) return self+(v-self)*t end
Vector3.zero = Vector3.new(0,0,0)
local function typeof(value)
    return getmetatable(value)==vectorMeta and "Vector3" or type(value)
end
local pending = {}
local task = {}
function task.spawn(fn)
    local thread = coroutine.create(fn)
    local ok, err = coroutine.resume(thread)
    assert(ok,err)
    if coroutine.status(thread)~="dead" then table.insert(pending,thread) end
end
function task.wait() return coroutine.yield() end
local function drain()
    while #pending > 0 do
        local thread = table.remove(pending,1)
        local ok, err = coroutine.resume(thread)
        assert(ok,err)
        if coroutine.status(thread)~="dead" then table.insert(pending,thread) end
    end
end
local pathService = {}
local game = {GetService=function(_,name) return name=="PathfindingService" and pathService or {} end}
local Enum = {PathStatus={Success="Success"}}
local failures, checks = {}, 0
local function check(condition,message)
    checks += 1
    if not condition then table.insert(failures,message) end
end
'''

TESTS = r'''
local goal = Vector3.new(100,0,0)
local function makeNavigator()
    return setmetatable({
        Tuning={StableRoutes=false,RepathInterval=.55,RepathDistance=5,
            PathRequestTimeout=8,WaypointArrivalDistance=1.25,MaxStepHeight=3.5},
        FootPosition=Vector3.zero,Waypoints={goal},WaypointIndex=1,Goal=goal,
        LastRequestedGoal=goal,LastPathAt=clock-1,RequestId=0,Computing=false,
        RouteRejectedCount=0,RouteInstallCount=0,RoutePrefixSkips=0,
        _positionAllowed=function() return true end,
        _clearBlocked=function() end,
        _standableAt=function() return true end,
        _walkingEdgeClear=function() return true end,
    },Navigator)
end
for _, method in {"SetGoal","SetGraphGoal"} do
    local nav = makeNavigator()
    local requests = 0
    nav._requestPath = function(self)
        requests += 1
        self.LastPathAt=clock
    end
    for _=1,4 do clock+=1; nav[method](nav,goal) end
    check(requests==0,method..": static target retains its healthy route")
    nav[method](nav,Vector3.new(106,0,0))
    check(requests==1,method..": meaningful target motion requests replacement")
    nav[method](nav,Vector3.new(112,0,0))
    check(requests==1,method..": moving target still respects request interval")
    nav.LastRequestedGoal=goal
    nav.WaypointIndex=2
    clock+=1
    nav[method](nav,goal)
    check(requests==2,method..": exhausted indexed route replans")
    nav.Computing=true
    nav.LastPathAt=clock-2
    nav[method](nav,Vector3.new(120,0,0))
    check(requests==2 and nav.Computing,method..": active request survives ordinary goal updates")
    nav.LastPathAt=clock-9
    nav[method](nav,Vector3.new(120,0,0))
    check(requests==3 and nav.RequestId==1,method..": timed-out request invalidated and retried")
end
local function plan(nav,points)
    nav._fallbackWaypoints=function() return points,"GRAPH" end
    nav._centreRoute=function(_,given,_,origin)
        nav.CertifiedOrigin=origin
        task.wait()
        return given,{Unwalkable=0,Unresolved=0,Queries=1,Aborted=false}
    end
    nav:_requestPath(goal,true)
end
do
    local nav=makeNavigator()
    plan(nav,{Vector3.new(5,0,0),goal})
    nav.FootPosition=Vector3.new(15,0,0)
    drain()
    check(nav.Waypoints[nav.WaypointIndex].X>=15,"delayed installation never rewinds past forward progress")
    check(nav.CertifiedOrigin~=nil and nav.CertifiedOrigin.X==0,"route certification uses captured request origin")
    check(not nav.Computing,"successful replacement settles request")
end
do
    local nav=makeNavigator()
    local corner=Vector3.new(20,0,0)
    nav._walkingEdgeClear=function(_,_,to) return to==corner end
    plan(nav,{Vector3.new(5,0,0),corner,goal})
    nav.FootPosition=Vector3.new(15,0,0)
    drain()
    check(nav.Waypoints[1]==corner,"joining keeps the corner when a shortcut crosses an obstruction")
end
do
    local nav=makeNavigator()
    local incumbent=Vector3.new(15,0,30)
    nav.Waypoints={incumbent}
    nav._walkingEdgeClear=function(_,_,to) return to==incumbent end
    plan(nav,{Vector3.new(5,0,0),goal})
    nav.FootPosition=Vector3.new(15,0,0)
    drain()
    check(nav.Waypoints[1]==incumbent,"unsafe replacement preserves usable incumbent")
    check(not nav.Computing,"rejected replacement settles request")
end
do
    local nav=makeNavigator()
    plan(nav,{Vector3.new(5,0,0),goal})
    nav:Stop()
    drain()
    check(nav.Goal==nil and #nav.Waypoints==0 and not nav.Computing,"Stop prevents late route resurrection")
end
'''

CONTROLLER_PRELUDE = r'''
local player = {}
local targetRoot = {Position=goal}
local PHASES={Dormant="Dormant"}
local function entityIsActive(_,entity) return entity.Active~=false end
local function setModelAttribute() end
local function resetThreatState() end
local function observationFreezes() return false end
local function setEntityAnimationPaused() end
local function setEntityAnimation() end
local function bestTarget() return player,targetRoot,100 end
local function instantKill() return false end
local function movementSpeed() return 10 end
local function createTrail() end
local function setChaseTarget(entity,value) entity.ChaseTarget=value end
local function choosePatrolPosition() return Vector3.new(0,0,100) end
local function numberOr(value,fallback,minimum,maximum)
    if type(value)~="number" or value~=value then value=fallback end
    if minimum then value=math.max(minimum,value) end
    if maximum then value=math.min(maximum,value) end
    return value
end
'''

CONTROLLER_TESTS = r'''
do
    local requests=0
    local nav={Computing=true,RequestStartedAt=clock,
        GetPosition=function() return Vector3.zero end,
        GetGoal=function() return goal end,
        Step=function() return false end,
        Stop=function(self) self.Stopped=true end,
        GetDebugSnapshot=function(self) return {Computing=self.Computing,RequestStartedAt=self.RequestStartedAt} end,
        SetGoal=function(self) requests+=1; self.Computing=false end}
    local entity={Navigator=nav,ProgressTarget=player,ProgressGoal=goal,
        ProgressAnchor=Vector3.zero,ProgressGoalDistance=100,RepathAttempts=0,
        NoProgressFor=0,NextGoalAt=math.huge,NextTrailAt=math.huge,
        StationaryFor=0,ChaseTriggered=true,ChaseTarget=player,UnreachableUntil={}}
    local session={Phase="Pressure",Configuration={Movement={StuckRepathSeconds=1.1,PathRequestTimeout=8}}}
    for _=1,15 do clock+=.1; updateEntity(session,entity,.1,clock) end
    check(requests==0 and entity.RepathAttempts==0,"watchdog lets a pending route finish beyond 1.1 seconds")
    check(entity.UnreachableUntil[player]==nil,"pending calculation does not make the pursued player unreachable")
    clock=nav.RequestStartedAt+9
    clock+=.1; updateEntity(session,entity,.1,clock)
    check(requests==1,"watchdog still retries after the request timeout")
    for _=1,12 do clock+=.1; updateEntity(session,entity,.1,clock) end
    check(entity.UnreachableUntil[player]~=nil,"completed failed retry still releases an unreachable target")
    local before=requests
    entity.Active=false
    updateEntity(session,entity,.1,clock)
    check(nav.Stopped and requests==before,"inactive entity stops without requesting routes")
    entity.Active=true
    entity.NoProgressFor=0
    entity.RepathAttempts=0
    entity.ProgressGoal=goal
    entity.ProgressAnchor=Vector3.zero
    entity.ProgressGoalDistance=100
    entity.ProgressTarget=player
    entity.NextGoalAt=math.huge
    requests=0
    for _=1,90 do
        clock+=.1
        -- The navigator may time out and start fresh before the controller
        -- samples it. Each request is young; total time without movement is not.
        nav.Computing=true
        nav.RequestStartedAt=clock
        updateEntity(session,entity,.1,clock)
    end
    check(requests==1,"successive fresh requests cannot extend watchdog grace forever")
end
for _,message in failures do print("FAIL: "..message) end
assert(#failures==0,tostring(#failures).." of "..checks.." navigation checks failed")
print("Pool Foam navigation: "..checks.." checks passed (offline async lifecycle; geometry stubbed)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    update_entity = CONTROLLER[CONTROLLER.index("local function resetProgressWindow"):CONTROLLER.index("local function refreshTemplate")]
    fixture_source = "\n".join([PRELUDE, "local Navigator=(function()", SOURCE,
                                "end)()", TESTS, CONTROLLER_PRELUDE, update_entity, CONTROLLER_TESTS])
    with tempfile.TemporaryDirectory(prefix="pool-foam-navigation-") as directory:
        fixture = Path(directory) / "navigation_test.luau"
        fixture.write_text(fixture_source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=20)


if __name__ == "__main__":
    main()
