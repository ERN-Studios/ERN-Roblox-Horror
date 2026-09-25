"""Check Level 2 Pool Slide timeout and clearance recovery against real source.

Geometry is stubbed. Both clocks advance during scheduler yields, matching the
native Roblox measurement (task.wait(1) advanced os.clock by 1.0147 seconds).
Planning is already bounded in HEAD; the regression reproduces the separate
clearance latch that never releases for a stationary target.

The same fixtures run against git show HEAD. Only the clearance-latch failures
are expected before the fix; a CPU-only clock is not a Roblox reproduction.

Set LUAU_BIN or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
NAVIGATOR = "ServerScriptService/Level 2 Systems/Level 2 Pool Slide Navigator.ModuleScript.lua"

# Wall seconds the fixed navigator may spend on one planning pass. Matches the
# controller's PLANNING_WALL_TIMEOUT; the pre-fix navigator ignores it entirely.
WALL_TIMEOUT = 4

PRELUDE = r'''
-- Local monotonic and server clocks both advance through scheduler yields.
local cpu, wall = 100, 1000
local FRAME = 1/60
local os = table.clone(os)
os.clock = function() return cpu end
local function compute(seconds) cpu += seconds; wall += seconds end

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
    __eq = function(a,b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end,
}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end
function vectorMethods:Dot(v) return self.X*v.X+self.Y*v.Y+self.Z*v.Z end
function vectorMethods:Lerp(v,t) return self+(v-self)*t end
Vector3.zero = Vector3.new(0,0,0)
Vector3.yAxis = Vector3.new(0,1,0)
local function typeof(value)
    return getmetatable(value)==vectorMeta and "Vector3" or type(value)
end
local CFrame = {}
function CFrame.new(position) return {Position=position} end

local workspace = {
    GetServerTimeNow = function() return wall end,
    -- Nothing is ever in the way; these stalls are not about geometry.
    GetPartBoundsInBox = function() return {} end,
    Raycast = function() return nil end,
    Blockcast = function() return nil end,
}

local pending = {}
local task = {}
function task.defer(fn)
    table.insert(pending, coroutine.create(fn))
end
function task.wait() return coroutine.yield() end
-- One resumption is one frame of real time.
local function drain(limit)
    local frames = 0
    while #pending > 0 do
        frames += 1
        if frames > (limit or 100000) then error("scheduler did not settle") end
        local thread = table.remove(pending,1)
        cpu += FRAME; wall += FRAME
        local ok, err = coroutine.resume(thread)
        assert(ok,err)
        if coroutine.status(thread)~="dead" then table.insert(pending,thread) end
    end
    return frames
end

local pathService = {}
local game = {GetService=function(_,name)
    return name=="PathfindingService" and pathService or {}
end}
local Enum = {PathStatus={Success="Success"},
    RaycastFilterType={Exclude="Exclude",Include="Include"}}
local RaycastParams = {new=function() return {} end}
local OverlapParams = {new=function() return {} end}
local failures, checks = {}, 0
local function check(condition,message)
    checks += 1
    if not condition then table.insert(failures,message) end
end
'''

TESTS = r'''
local WALL_TIMEOUT = __WALL_TIMEOUT__
local goal = Vector3.new(400,0,0)

local function makeNavigator(overrides)
    local nav = setmetatable({
        Tuning={StableRoutes=true,RepathInterval=.75,RepathDistance=6,
            PathRequestTimeout=3,PlanningWallTimeout=WALL_TIMEOUT,
            WaypointArrivalDistance=1.4,GoalArrivalDistance=.2,MaxStepHeight=3.5,
            AgentRadius=8.2,AgentHeight=16.5,PathAgentRadius=8.2,WaypointSpacing=5},
        FootPosition=Vector3.zero,Waypoints={},WaypointIndex=1,Goal=goal,
        LastRequestedGoal=nil,LastPathAt=cpu-10,RequestId=0,Computing=false,
        RouteRejectedCount=0,RouteInstallCount=0,RoutePrefixSkips=0,
        ClearanceProbes=0,NextClearanceProbeAt=0,Trail={},
        _positionAllowed=function() return true end,
        _clearBlocked=function() end,
        _bindBlocked=function() end,
        _refreshObstacleFilters=function() end,
        _standableAt=function(_,point) return true, point end,
        _walkingEdgeClear=function() return true end,
        _pathPointsAllowed=function() return true end,
        _fallbackWaypoints=function() return {goal},"GRAPH" end,
        _smoothStableRoute=function(_,points) return points end,
    },Navigator)
    for key, value in pairs(overrides or {}) do nav[key] = value end
    return nav
end

-- ---------------------------------------------------------------------------
-- 1. One planning pass may not own the navigator for unbounded REAL time.
--
-- The stub stands in for the real _centreRoute: a long certification pass that
-- keeps working until its own shouldAbort says stop, and reaches the scheduler
-- through the same _bodyBoxClear -> planningCheckpoint the real pass uses.
-- ---------------------------------------------------------------------------
do
    local nav = makeNavigator()
    local iterations = 0
    nav._centreRoute = function(self, points, shouldAbort)
        while not (shouldAbort and shouldAbort()) do
            iterations += 1
            if iterations > 200000 then break end
            compute(.0005)
            self:_bodyBoxClear(Vector3.new(iterations % 100,0,0))
        end
        return points, {Aborted=true,Unwalkable=1,Unresolved=0,Queries=1}
    end
    pathService.CreatePath = function()
        return {ComputeAsync=function() end, Status="Success",
            GetWaypoints=function() return {{Position=Vector3.new(50,0,0)},
                {Position=goal}} end, Blocked={Connect=function() return {} end}}
    end
    local startedWall = wall
    nav:_requestPath(goal)
    drain()
    local spent = wall - startedWall
    check(not nav.Computing, "a finished planning pass clears Computing")
    check(spent <= WALL_TIMEOUT + 1,
        string.format("one planning pass held the navigator for %.1f s of real time"
            .. " (allowed %.1f); Step cannot repath and the watchdog is suppressed"
            .. " for all of it", spent, WALL_TIMEOUT + 1))
end

-- ---------------------------------------------------------------------------
-- 2. A wall-clock abort must not throw away a healthy incumbent route.
-- ---------------------------------------------------------------------------
do
    local incumbent = Vector3.new(30,0,0)
    local nav = makeNavigator({Waypoints={incumbent}})
    nav._centreRoute = function(self, points, shouldAbort)
        while not (shouldAbort and shouldAbort()) do
            compute(.0005)
            self:_bodyBoxClear(Vector3.zero)
        end
        return points, {Aborted=true,Unwalkable=1,Unresolved=0,Queries=1}
    end
    nav:_requestPath(goal)
    drain()
    check(nav.Waypoints[1] == incumbent,
        "an aborted pass keeps the route the rig is already walking")
end

-- ---------------------------------------------------------------------------
-- 3. WAITING_FOR_CLEARANCE has to end. The probe is a static geometry test; a
-- player standing still never moves the goal, so nothing else can release it.
-- ---------------------------------------------------------------------------
local function latched(overrides)
    local approach = Vector3.new(100,0,0)
    local nav = makeNavigator(overrides)
    nav.FootPosition = approach
    nav.BlockedGoalApproach = approach
    nav.InstalledGoal = goal
    nav.Goal = goal
    nav.LastRequestedGoal = goal
    nav.LastPathAt = cpu - 10
    nav.BlockedProbeFrom = approach
    nav.BlockedProbeTarget = Vector3.new(120,0,0)
    -- An authored vault rib. It is never going to move.
    nav._walkingEdgeClear = function() return false end
    return nav
end
do
    local nav = latched()
    check(nav:_waitingForClearance(), "fixture reproduces the clearance latch")
    local released = false
    for _ = 1, 40 do
        cpu += 1; wall += 1
        if nav:_stableNeedsPath(goal, false) then released = true; break end
    end
    check(released,
        "the rig waited on static geometry forever while the target stood still")
end
do
    -- Same latch, but the prefix walk recorded no usable endpoints: the pre-fix
    -- probe returned before it ever tested or counted anything.
    local nav = latched()
    nav.BlockedProbeFrom = nil
    nav.BlockedProbeTarget = nil
    local released = false
    for _ = 1, 40 do
        cpu += 1; wall += 1
        if nav:_stableNeedsPath(goal, false) then released = true; break end
    end
    check(released, "a latch with no recorded probe endpoints also has to end")
end
do
    -- The wait still exists: a genuinely transient obstruction clears on its own
    -- and must release on the probe, not on the budget.
    local nav = latched()
    nav._walkingEdgeClear = function() return true end
    cpu += 1; wall += 1
    check(nav:_probeBlockedClearance() and nav.BlockedGoalApproach == nil,
        "a cleared obstruction still releases the wait immediately")
end

for _,message in failures do print("FAIL: "..message) end
if __EXPECT_STALL__ then
    assert(#failures > 0, "pre-fix navigator passed the stall contracts; "
        .. "the fixture no longer reproduces anything")
    print("Pool Slide navigation: pre-fix source failed "..tostring(#failures)
        .." of "..checks.." checks, as expected")
else
    assert(#failures==0,tostring(#failures).." of "..checks.." navigation checks failed")
    print("Pool Slide navigation: "..checks.." checks passed "
        .."(offline clocks and scheduler; geometry stubbed)")
end
'''


def fixture(source, expect_stall):
    tests = (TESTS
             .replace("__WALL_TIMEOUT__", str(WALL_TIMEOUT))
             .replace("__EXPECT_STALL__", "true" if expect_stall else "false"))
    return "\n".join([PRELUDE, "local Navigator=(function()", source, "end)()", tests])


def run(binary, source, expect_stall):
    with tempfile.TemporaryDirectory(prefix="pool-slide-navigation-") as directory:
        path = Path(directory) / "navigation_test.luau"
        path.write_text(fixture(source, expect_stall), encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    run(binary, (ROOT / NAVIGATOR).read_text(encoding="utf-8"), expect_stall=False)
    # Pin the historical static-obstruction stall. HEAD advances with normal
    # work and now passes these checks, so it is not a negative control.
    previous = subprocess.run(["git", "show", "715e4d9:" + NAVIGATOR], cwd=ROOT,
                              capture_output=True, check=True).stdout.decode("utf-8")
    run(binary, previous, expect_stall=True)


if __name__ == "__main__":
    main()
