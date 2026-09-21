"""Run the real Pool Foam separation pass in offline Luau.

No Studio and no geometry: the navigator is replaced by a stub whose Sidestep
honours the SAME contract as the real one (clamped offset, validated placement,
a refused placement moves nothing), so a wall is expressed as a walkability
predicate. Everything under test -- separationRadius, separationDirection,
separationSidestep, updateSeparation, the spawn chooser and the hold branch
inside updateEntity -- is extracted from the shipped controller source.

What this cannot show: real floors, real body sweeps and real frame times. Those
need a Studio playtest with the Level2_PoolFoam* readbacks.
Set LUAU_BIN to an official luau executable, or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = (ROOT / "ServerScriptService/Level 2 Systems/Level 2 Pool Foam Controller.ModuleScript.lua").read_text(encoding="utf-8")


def section(source, start, end):
    return source[source.index(start):source.index(end)]


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
Vector3.zero = Vector3.new(0,0,0)
local function typeof(value)
    return getmetatable(value)==vectorMeta and "Vector3" or type(value)
end
local failures, checks = {}, 0
local function check(condition,message)
    checks += 1
    if not condition then table.insert(failures,message) end
end
local shared = {}
local function setShared(name,value) shared[name]=value end
local function entityIsActive(_,entity) return entity.SpawnAwake~=false end
'''

# The stub navigator. MaxTravelStep mirrors the navigator's own authored .9, and
# a placement is refused exactly where the real _placeFoot would refuse one.
HARNESS = r'''
local MAX_TRAVEL_STEP = .9
local RADIUS = 3.75
local CONTACT = RADIUS*2
-- TRAIL_LIMIT * TRAIL_SPACING in the navigator: 48 breadcrumbs, .6 apart.
local TRAIL_CAP = 28.8
local SPEED = 10
local everywhere = function() return true end
local placements = 0

local function makeEntity(id,ordinal,x,z,facing,walkable)
    local nav = {
        Position=Vector3.new(x,0,z), Facing=facing or Vector3.new(0,0,-1),
        Walkable=walkable or everywhere, TrailStuds=0, Retreats=0,
    }
    function nav:GetPosition() return self.Position end
    function nav:GetFacing() return self.Facing end
    function nav:Sidestep(offset,limit)
        local flat = Vector3.new(offset.X,0,offset.Z)
        local requested = flat.Magnitude
        if requested < .01 then return false end
        local travel = math.min(requested,limit or requested,MAX_TRAVEL_STEP)
        if travel < .01 then return false end
        local target = self.Position + flat.Unit*travel
        placements += 1
        if not self.Walkable(target) then return false end
        self.Position = target
        -- Every validated placement lays a breadcrumb, capped, exactly as
        -- Navigator:_placeFoot does through _recordTrail.
        self.TrailStuds = math.min(TRAIL_CAP,self.TrailStuds+travel)
        return true
    end
    function nav:Retreat(distance)
        -- The real Retreat walks BACK along validated positions and stops the
        -- instant a placement fails; it returns the studs it actually covered.
        local travel = math.min(distance,self.TrailStuds)
        local target = self.Position - self.Facing*travel
        if travel <= 0 or not self.Walkable(target) then return 0 end
        self.Position = target
        self.TrailStuds -= travel
        self.Retreats += 1
        return travel
    end
    return {Id=id,SpawnOrdinal=ordinal,Navigator=nav,BodyRadius=RADIUS,
        SeparationPushX=0,SeparationPushZ=0,SeparationContactDistance=math.huge,
        SeparationAheadDistance=math.huge,SeparationHoldUntil=0,
        SeparationReleaseUntil=0,SeparationActive=true,Goal=nil,
        LastDesiredSpeed=SPEED,Deltas={},Reversals=0,LongestReversalRun=0}
end

local function makeSession(entities)
    return {Configuration={Separation={}},Entities=entities,
        SeparationMinimum=math.huge,SeparationOverlapFrames=0,
        SeparationYields=0,SeparationCostMs=0,NextSeparationPublishAt=0}
end

-- The controller's own loop, reduced to the two things that matter here: a
-- route step, and the SEPARATION HOLD that updateEntity applies before it (the
-- wiring of that hold is asserted separately against the real updateEntity).
local function routeStep(entity,deltaTime,now)
    if entity.Goal and now >= (entity.SeparationHoldUntil or 0) then
        local nav = entity.Navigator
        local offset = Vector3.new(entity.Goal.X-nav.Position.X,0,entity.Goal.Z-nav.Position.Z)
        local distance = offset.Magnitude
        if distance > .5 then
            local direction = offset/distance
            nav.Facing = direction
            local step = math.min(distance,SPEED*deltaTime)
            local target = nav.Position + direction*step
            if nav.Walkable(target) then
                nav.Position = target
                nav.TrailStuds = math.min(TRAIL_CAP,nav.TrailStuds+step)
            end
        end
    end
end

-- Jitter is measured on the WHOLE frame -- route step plus correction -- since a
-- correction that undoes the route step is precisely the failure mode.
local function recordDelta(entity,before)
    local delta = entity.Navigator.Position - before
    if delta.Magnitude <= 1e-4 then
        entity.Run = 0 -- standing still is not reversing
        return
    end
    local previous = entity.LastDelta
    if previous and previous.Magnitude > 1e-4 then
        if delta:Dot(previous) < 0 then
            entity.Reversals += 1
            entity.Run = (entity.Run or 0) + 1
            entity.LongestReversalRun = math.max(entity.LongestReversalRun,entity.Run)
        else
            entity.Run = 0
        end
    end
    entity.LastDelta = delta
end

local function finite(vector)
    return vector.X==vector.X and vector.Z==vector.Z
        and math.abs(vector.X)<math.huge and math.abs(vector.Z)<math.huge
end

local function run(session,steps,deltaTime)
    local closest = math.huge
    local finiteThroughout = true
    for _=1,steps do
        clock += deltaTime
        local before = {}
        for index,entity in session.Entities do
            before[index] = entity.Navigator.Position
            routeStep(entity,deltaTime,clock)
        end
        updateSeparation(session,clock,deltaTime)
        for index,entity in session.Entities do
            recordDelta(entity,before[index])
            finiteThroughout = finiteThroughout and finite(entity.Navigator.Position)
        end
        for index=1,#session.Entities-1 do
            for other=index+1,#session.Entities do
                local separation = (session.Entities[index].Navigator.Position
                    -session.Entities[other].Navigator.Position).Magnitude
                if separation < closest then closest = separation end
            end
        end
    end
    check(finiteThroughout,"every position stayed finite for the whole run")
    return closest
end
'''

TESTS = r'''
-- 1. The radius is MEASURED from the model, not taken from the configuration.
do
    local bloom = {GetBoundingBox=function() return nil,Vector3.new(7.5,4.8,6.5) end}
    local spire = {GetBoundingBox=function() return nil,Vector3.new(4.8,7.8,4.8) end}
    local broken = {GetBoundingBox=function() error("no bounds") end}
    local huge = {GetBoundingBox=function() return nil,Vector3.new(400,4,400) end}
    local configuration = {Separation={FallbackRadius=3.75,MinimumRadius=1,MaximumRadius=8}}
    check(separationRadius(configuration,bloom)==3.75,"Bloom proxy measures 7.5/2 = 3.75")
    check(separationRadius(configuration,spire)==2.4,"Spire proxy measures its own 4.8/2")
    check(separationRadius(configuration,broken)==3.75,"an unreadable model falls back")
    check(separationRadius(configuration,huge)==8,"a mis-scaled import is clamped")
end

-- 2. Five entities converging on ONE target never reach the no-overlap distance,
--    never produce a non-finite position and never shiver.
do
    local entities = {}
    local angle = 0
    for ordinal=1,5 do
        angle = (ordinal-1)*(2*math.pi/5)
        local entity = makeEntity(("Primary_%02d"):format(ordinal),ordinal,
            math.cos(angle)*30,math.sin(angle)*30)
        entity.Goal = Vector3.zero
        table.insert(entities,entity)
    end
    local session = makeSession(entities)
    local closest = run(session,900,1/60)
    check(closest >= CONTACT,
        ("five converging entities stayed outside %.1f studs (closest %.2f)"):format(CONTACT,closest))
    check(session.SeparationOverlapFrames==0,"no step reported an overlapping pair")
    for _,entity in entities do
        check(entity.LongestReversalRun<=2,
            entity.Id.." never reversed direction on more than two steps in a row")
    end
    check(shared.Level2_PoolFoamMinSeparation~=nil and shared.Level2_PoolFoamMinSeparation>=CONTACT,
        "the published minimum matches what was measured")
    check(shared.Level2_PoolFoamSeparationMs~=nil,"the cost average is published")
end

-- 3. Head-on in a corridor the bodies cannot pass in: no overlap, no deadlock,
--    and the entity with right of way keeps the ground the yielder gives up.
do
    local corridor = function(position) return math.abs(position.X) <= .4 end
    local first = makeEntity("Primary_01",1,0,0,Vector3.new(0,0,1),corridor)
    local second = makeEntity("Primary_02",2,0,26,Vector3.new(0,0,-1),corridor)
    first.Goal = Vector3.new(0,0,60)
    second.Goal = Vector3.new(0,0,-60)
    local session = makeSession({first,second})
    local closest = run(session,900,1/60)
    check(closest >= CONTACT,
        ("head-on pair never overlapped (closest %.2f)"):format(closest))
    check(session.SeparationOverlapFrames==0,"and no step reported one")
    check(session.SeparationYields>0,"the blocked yielder ran its bounded wait to a back-out")
    check(second.Navigator.Retreats>0,"the yielder backed out along its own trail")
    -- They first stand each other off around z=8.5 (26 studs apart, closing from
    -- both ends). Anything meaningfully past that is ground the yielder gave up.
    check(first.Navigator.Position.Z>12,
        ("right of way kept advancing through the ground given up (z=%.1f)"):format(
            first.Navigator.Position.Z))
    check(first.SeparationHoldUntil<=clock+.2 and second.SeparationHoldUntil<=clock+.2,
        "no hold outlives its lease")
    check(second.LongestReversalRun<=2,"the held yielder did not shiver against its route")
end

-- 4. A yielder with a wall on the side it was sent to takes the other lane once,
--    and one with a wall on BOTH sides is held rather than pushed backwards.
do
    local oneLane = function(position) return position.X >= -.1 end
    local blocked = makeEntity("Primary_01",1,0,8,Vector3.new(0,0,-1))
    local mover = makeEntity("Primary_02",2,0,0,Vector3.new(0,0,1),oneLane)
    local session = makeSession({blocked,mover})
    for _=1,5 do clock += 1/60; updateSeparation(session,clock,1/60) end
    check(mover.Navigator.Position.X>0,"a walled lane is answered by the other lane")
    check(mover.Navigator.Position.Z==0,"and never by backing up")
    check(mover.SeparationLane~=0 and not (blocked.SeparationHoldUntil>clock),
        "a yielder that can still move never stops the one with right of way")

    local pinned = makeEntity("Primary_02",2,0,0,Vector3.new(0,0,1),
        function(position) return math.abs(position.X)<=.01 end)
    local pair = makeSession({blocked,pinned})
    blocked.SeparationHoldUntil = 0
    clock += 1/60
    updateSeparation(pair,clock,1/60)
    check(pinned.Navigator.Position.X==0 and pinned.Navigator.Position.Z==0,
        "a pinned yielder is not moved at all")
    check(pinned.SeparationHoldUntil>clock,"it is held instead")
    check(blocked.SeparationHoldUntil>clock,
        "and so is the entity that would otherwise walk through it")
end

-- 5. A yielder that cannot back out either is RELEASED, never frozen for good.
do
    local pen = function(position) return math.abs(position.X)<=.01 and position.Z>=0 end
    local ahead = makeEntity("Primary_01",1,0,8,Vector3.new(0,0,-1))
    local trapped = makeEntity("Primary_02",2,0,0,Vector3.new(0,0,1),pen)
    local session = makeSession({ahead,trapped})
    for _=1,200 do
        clock += 1/60
        updateSeparation(session,clock,1/60)
    end
    check(session.SeparationYields>0,"the trapped yielder reached its back-out")
    check(trapped.SeparationReleaseUntil>clock,"and was released instead of held again")
    check(trapped.SeparationHoldUntil<=clock,"the hold is gone while the release stands")
end

-- 6. The pass is off by configuration, and one entity is never a pair.
do
    local a = makeEntity("Primary_01",1,0,0)
    local b = makeEntity("Primary_02",2,0,1)
    local session = makeSession({a,b})
    session.Configuration.Separation = {Enabled=false}
    updateSeparation(session,clock,1/60)
    check(a.Navigator.Position.Z==0 and b.Navigator.Position.Z==1,"Enabled=false moves nothing")
    check(session.SeparationOverlapFrames==0,"and measures nothing")
    local single = makeSession({makeEntity("Primary_01",1,0,0)})
    updateSeparation(single,clock,1/60)
    check(single.SeparationMinimum==math.huge,"a lone entity has no pair to measure")
end
'''

SPAWN_PRELUDE = r'''
local function hallOf(index) return {Index=index,MinX=-50,MaxX=50,MinZ=-50,MaxZ=50} end
'''

SPAWN_TESTS = r'''
do
    local session = {Configuration={Separation={SpawnGap=9}},Nodes={
        {Name="A",HallIndex=1,Position=Vector3.new(0,0,0)},
        {Name="B",HallIndex=1,Position=Vector3.new(4,0,0)},
        {Name="C",HallIndex=1,Position=Vector3.new(40,0,0)},
    }}
    local first = positionForHall(session,hallOf(1),{})
    check(first.X==0,"with nothing placed the first node is still chosen")
    local second = positionForHall(session,hallOf(1),{first})
    check(second.X==40,"a node inside the spawn gap is skipped for one that clears it")
    local third = positionForHall(session,hallOf(1),{Vector3.new(0,0,0),Vector3.new(40,0,0)})
    check(third.X==4,"when nothing clears the gap the roomiest real node wins")
    check((third-Vector3.new(0,0,0)).Magnitude>0,"and it is never a position that was taken")
    local empty = positionForHall(session,hallOf(7),{})
    check(empty.Y==2,"a hall without nodes still falls back to its centre")
end
'''

# The hold has to be WIRED, not merely computed: the real updateEntity must skip
# its locomotion while the lease stands. Stubs mirror test_pool_foam_navigation.
HOLD_PRELUDE = r'''
local player = {}
local holdGoal = Vector3.new(0,0,100)
local targetRoot = {Position=holdGoal}
local PHASES = {Dormant="Dormant"}
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
local function choosePatrolPosition() return holdGoal end
'''

HOLD_TESTS = r'''
do
    local steps = 0
    local nav = {GetPosition=function() return Vector3.zero end,
        GetGoal=function() return holdGoal end,
        Step=function() steps += 1; return false end,
        Stop=function() end,
        SetGoal=function() end,
        GetDebugSnapshot=function() return {Computing=false,RequestStartedAt=clock} end}
    local entity = {Navigator=nav,UnreachableUntil={},NoProgressFor=0,RepathAttempts=0,
        StationaryFor=0,NextGoalAt=math.huge,NextTrailAt=math.huge,ProgressAnchor=Vector3.zero,
        ProgressGoal=holdGoal,ProgressGoalDistance=100,ProgressTarget=player,
        ChaseTriggered=true,ChaseTarget=player,SeparationHoldUntil=0}
    local session = {Phase="Pressure",Configuration={Movement={}}}
    updateEntity(session,entity,1/60,clock)
    check(steps==1,"an unheld entity walks its route")
    entity.SeparationHoldUntil = clock + .15
    for _=1,8 do updateEntity(session,entity,1/60,clock) end
    check(steps==1,"a held entity takes no route step at all")
    check(entity.WasMoving==false,"and reports itself stationary")
    clock += .2
    updateEntity(session,entity,1/60,clock)
    check(steps==2,"the lease expires on its own")
    entity.SeparationHoldUntil = nil
    updateEntity(session,entity,1/60,clock)
    check(steps==3,"an entity created before the field existed is never held")
end

for _,message in failures do print("FAIL: "..message) end
assert(#failures==0,tostring(#failures).." of "..checks.." separation checks failed")
print("Pool Foam separation: "..checks.." checks passed, "..placements
    .." validated placements requested (offline; real floors/body sweeps need Studio)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    source = "\n".join([
        PRELUDE,
        section(CONTROLLER, "local function finiteNumber", "local function loadSibling"),
        section(CONTROLLER, "-- SEPARATION TUNING BEGIN", "-- SEPARATION TUNING END"),
        section(CONTROLLER, "-- SEPARATION BEGIN", "-- SEPARATION END"),
        HARNESS, TESTS,
        section(CONTROLLER, "local function hallCenter", "local function normalizeKidsArea"),
        section(CONTROLLER, "local function positionForHall", "local function setModelAttribute"),
        SPAWN_PRELUDE, SPAWN_TESTS, HOLD_PRELUDE,
        CONTROLLER[CONTROLLER.index("local function resetProgressWindow"):CONTROLLER.index("local function refreshTemplate")],
        HOLD_TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="pool-foam-separation-") as directory:
        fixture = Path(directory) / "separation_test.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=60)


if __name__ == "__main__":
    main()
