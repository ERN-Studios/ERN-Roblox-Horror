"""Run real navigators and kit/live generators in offline Luau.

Supply a pre-kit source directory, or save pre-edit navigator bytes outside
the repo as foam.lua and slide.lua, then run with --baseline-dir TEMP.

The baseline is supplied explicitly: this runner never runs repository commands
or silently compares the modified source with itself. Geometry uses ideal floor
fixtures, not Roblox physics; Studio gameplay/performance remain unverified.
"""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
import test_level2_kit_layout as kit
import test_pool_slide_navigation as slide

ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / "ServerScriptService/Level 2 Systems"
SOURCES = {name: SYSTEMS / f"Level 2 Pool {name.title()} Navigator.ModuleScript.lua"
           for name in ("foam", "slide")}


def instrument(source):
    # Expose local functions only inside the temporary Luau fixture.
    marker = "return Navigator"
    assert source.count(marker) == 1
    return source.replace(marker, """return {Navigator=Navigator, graphRoute=graphRoute,
        buildHallIndex=buildHallIndex, corridorCentreSeed=corridorCentreSeed,
        corridorContaining=corridorContaining, corridorEntryPoint=corridorEntryPoint}""")


TESTS = r'''
workspace.GetAttribute = function() return true end -- all pressure doors open
local offset = .08
local counts = {pairs=0, floors=0, narrow=0, golden=0, rejected=0}
local oldUnresolved=0
local coverage = {X=false, Z=false, Stair4=false, Stair8=false, rise16=false}
local function near(a,b) return math.abs(a-b) < 1e-8 end
local function center(h, y) return Vector3.new(h.Center.X, y or h.FloorY+offset, h.Center.Z) end
local function pairCorridor(layout,a,b)
    for _,c in ipairs(layout.Corridors) do
        if (c.A==a and c.B==b) or (c.A==b and c.B==a) then return c end
    end
end

-- Independent oracle: use corridor records, not navigator helpers or pair cache.
local function oracle(layout,start,goal,minimum)
    local queue, seen, head = {start}, {[start]=true}, 1
    local parent = {}
    while head<=#queue do
        local at=queue[head]; head+=1
        if at==goal then
            local path={goal}
            while path[1]~=start do table.insert(path,1,parent[path[1]]) end
            return path
        end
        for _,other in ipairs(layout.Halls[at].Connections) do
            local c=pairCorridor(layout,at,other)
            if not seen[other] and c and (c.Width or 34)>=minimum then
                seen[other]=true; parent[other]=at; table.insert(queue,other)
            end
        end
    end
end

local ground = {CanCollide=true, GetAttribute=function(_,key) return key=="Level2_EntityGround" end}
local function floorAt(layout,p)
    for _,h in ipairs(layout.Halls) do
        if p.X>=h.MinX and p.X<=h.MaxX and p.Z>=h.MinZ and p.Z<=h.MaxZ then return h.FloorY end
    end
    for _,c in ipairs(layout.Corridors) do
        local along=c.Axis=="X" and p.X or p.Z
        local cross=c.Axis=="X" and p.Z or p.X
        if along>=c.From and along<=c.To and math.abs(cross-c.Cross)<=c.Width/2 then
            return c.FromY+(c.ToY-c.FromY)*(along-c.From)/(c.To-c.From)
        end
    end
end
local function floorFixture(layout)
    workspace.Raycast=function(_,origin,direction)
        local y=floorAt(layout,origin)
        if y and y<=origin.Y and y>=origin.Y+direction.Y then
            return {Position=Vector3.new(origin.X,y,origin.Z), Normal=Vector3.yAxis, Instance=ground}
        end
    end
end
local function navFor(api,layout,origin)
    return setmetatable({Layout=layout,HallByIndex=api.buildHallIndex(layout),
        FootPosition=origin,HasGrounded=true,
        Tuning={FootClearance=offset,FloorProbeAbove=12,FloorProbeDepth=80,MaxStepHeight=3.5},
        _bodyBoxClear=function() return true end,
        _clearDirectLine=function() return true end,
    },api.Navigator)
end
local function pointAt(point,x,y,z,message)
    assert(point and near(point.X,x) and near(point.Y,y) and near(point.Z,z),message)
end

for _,seed in ipairs({1,101,1182081016,738163940,35746866,51232729,66718592,
    82204455,97690318,113176181,128662044,144147907,159633770,175119633,190605496,206091359}) do
    local layout=Generator.Generate(seed)
    floorFixture(layout)
    -- The fallback caller must pass the configured foot offset, including zero.
    local wide
    for _,c in ipairs(layout.Corridors) do if c.Width>=16 then wide=c break end end
    assert(wide,"fixture needs a normal tunnel")
    for _,clearance in ipairs({0,.25}) do
        for _,api in pairs(Current) do
            local a,b=layout.Halls[wide.A],layout.Halls[wide.B]
            local nav=navFor(api,layout,center(a,a.FloorY+clearance))
            nav.Tuning.FootClearance=clearance
            local points,status=nav:_fallbackWaypoints(center(b,b.FloorY+clearance))
            assert(status=="GRAPH" and near(points[1].Y,a.FloorY+clearance)
                and near(points[3].Y,(wide.FromY+wide.ToY)/2+clearance)
                and near(points[5].Y,b.FloorY+clearance),"configured foot offset in fallback")
        end
    end
    for name,api in pairs(Current) do
        local minimum=name=="slide" and 16 or 0
        for _,a in ipairs(layout.Halls) do
            for _,b in ipairs(layout.Halls) do
                local origin,goal=center(a),center(b)
                local expected=oracle(layout,a.Index,b.Index,minimum)
                local nav=navFor(api,layout,origin)
                local route=api.graphRoute(layout,nav.HallByIndex,nil,origin,goal,offset)
                counts.pairs+=1
                assert((route~=nil)==(expected~=nil),name..": width-filtered reachability")
                if b.FloorY-a.FloorY==16 then
                    local old=Baseline[name]
                    local oldNav=navFor(old,layout,origin)
                    local oldRoute=old.graphRoute(layout,oldNav.HallByIndex,nil,origin,goal)
                    for _,p in ipairs(oldRoute or {}) do
                        if not oldNav:_standableAt(p) then oldUnresolved+=1 end
                    end
                end
                if expected then
                    assert(#route==(#expected-1)*5+1,"kit hub/spoke/midpoint route shape")
                    if #expected>=3 and b.FloorY-a.FloorY==16 then coverage.rise16=true end
                    for hop=1,#expected-1 do
                        local h,n=layout.Halls[expected[hop]],layout.Halls[expected[hop+1]]
                        local c=pairCorridor(layout,h.Index,n.Index)
                        assert(c.Width>=minimum,"Slide graph used Width < 16")
                        coverage[c.Axis]=true
                        if c.Variant=="Stair4" or c.Variant=="Stair8" then coverage[c.Variant]=true end
                        local i=(hop-1)*5
                        pointAt(route[i+1],h.Center.X,h.FloorY+offset,h.Center.Z,"hall hub height")
                        pointAt(route[i+5],n.Center.X,n.FloorY+offset,n.Center.Z,"next hall hub height")
                        local middle=(c.From+c.To)/2
                        local middleY=(c.FromY+c.ToY)/2+offset
                        if c.Axis=="X" then
                            pointAt(route[i+2],h.Center.X,h.FloorY+offset,c.Cross,"X hall spoke height")
                            pointAt(route[i+3],middle,middleY,c.Cross,"X corridor interpolation")
                            pointAt(route[i+4],n.Center.X,n.FloorY+offset,c.Cross,"X next spoke height")
                        else
                            pointAt(route[i+2],c.Cross,h.FloorY+offset,h.Center.Z,"Z hall spoke height")
                            pointAt(route[i+3],c.Cross,middleY,middle,"Z corridor interpolation")
                            pointAt(route[i+4],c.Cross,n.FloorY+offset,n.Center.Z,"Z next spoke height")
                        end
                        if c.Kind=="Narrow" then
                            assert(name=="foam","Slide graph entered Narrow")
                            counts.narrow+=1
                        end
                    end
                    for _,p in ipairs(route) do
                        local ok,foot=nav:_standableAt(p)
                        assert(ok and near(foot.Y,p.Y),name..": authored heights resolve using real +12/-68 floor probe")
                        counts.floors+=1
                    end
                else
                    assert(name=="slide","Foam must reach every kit hall")
                    local points,status=nav:_fallbackWaypoints(goal)
                    assert(#points==0 and status=="NO_PATH","narrow-only target bypassed graph with DIRECT")
                    -- Real goal setters must reject before scheduling any path work,
                    -- including forced watchdog retries and an incumbent request.
                    nav.RequestId=0; nav.Waypoints={origin}; nav.WaypointIndex=1
                    nav.Computing=true; nav.Goal=origin
                    nav._clearBlocked=function() end
                    nav._requestPath=function() error("unreachable target started planning") end
                    for _=1,3 do
                        assert(nav:SetGoal(goal)==false,"unreachable SetGoal must reject")
                        assert(nav:SetGraphGoal(goal,true)==false,"unreachable forced graph goal must reject")
                    end
                    assert(nav.Goal==nil and #nav.Waypoints==0 and not nav.Computing and nav.Status=="NO_PATH",
                        "unreachable goal must clear old chase and in-flight work")
                    counts.rejected+=1
                end
            end
        end
    end
    -- Direct checks isolate all three centring helpers, both axes and width edges.
    for _,c in ipairs(layout.Corridors) do
        local isolated={Corridors={c}}
        local middle=(c.From+c.To)/2
        local p=c.Axis=="X" and Vector3.new(middle,7,c.Cross+1) or Vector3.new(c.Cross+1,7,middle)
        local seed,which=Current.foam.corridorCentreSeed(isolated,p)
        assert(seed and which==c and seed.Y==7,"Foam centres every corridor at unchanged Y")
        assert(Current.foam.corridorContaining(isolated,p)==c,"Foam contains narrow corridor")
        if c.Width<16 then
            assert(Current.slide.corridorCentreSeed(isolated,p)==nil,"Slide must ignore narrow centre seed")
            assert(Current.slide.corridorContaining(isolated,p)==nil,"Slide must ignore narrow containment")
            assert(Current.slide.corridorEntryPoint(c,p,7)==nil,"Slide must ignore narrow entry")
            local outside=c.Axis=="X" and Vector3.new(middle,7,c.Cross+9) or Vector3.new(c.Cross+9,7,middle)
            assert(Current.foam.corridorCentreSeed(isolated,outside)==nil,"Foam narrow snap must use Width=12, not 34")
            assert(Current.foam.corridorContaining(isolated,outside)==nil,"Foam narrow containment must use Width=12")
            for _,width in ipairs({15,16}) do
                local changed=table.clone(c); changed.Width=width; changed.Kind="Open"
                local one={Corridors={changed}}
                assert((Current.slide.corridorCentreSeed(one,p)~=nil)==(width==16),"Slide width boundary, independent of Kind")
                assert((Current.slide.corridorContaining(one,p)~=nil)==(width==16),"Slide containment width boundary")
                assert((Current.slide.corridorEntryPoint(changed,p,7)~=nil)==(width==16),"Slide entry width boundary")
                local a,b=table.clone(layout.Halls[c.A]),table.clone(layout.Halls[c.B])
                a.Connections={b.Index}; b.Connections={a.Index}
                one.Halls={a,b}
                local graph=Current.slide.graphRoute(one,Current.slide.buildHallIndex(one),nil,center(a),center(b),offset)
                assert((graph~=nil)==(width==16),"Slide graph width boundary, independent of Kind")
            end
        end
    end
    workspace.GetAttribute=function() return false end -- pressure doors closed
    for _,c in ipairs(layout.Corridors) do
        if c.Kind~="Narrow" then
            for _,fraction in ipairs({.25,.5,.75}) do
                local along=c.From+(c.To-c.From)*fraction
                local p=c.Axis=="X" and Vector3.new(along,c.FromY+offset,c.Cross)
                    or Vector3.new(c.Cross,c.FromY+offset,along)
                for name,api in pairs(Current) do
                    local nav=navFor(api,layout,p)
                    local hall=nav:FindHall(p)
                    assert(hall and hall.Role~="Small",name..": tunnel mapped to small room")
                    if name=="slide" then
                        nav._requestPath=function() end
                        nav.Tuning.RepathDistance=10; nav.Tuning.RepathInterval=2
                        nav.LastPathAt=os.clock(); nav.Computing=true; nav.Waypoints={}
                        assert(nav:SetGoal(center(hall)),"Slide cannot set a goal from its tunnel hub")
                    end
                end
            end
        end
    end
    workspace.GetAttribute=function() return true end
end
assert(counts.narrow>0 and counts.rejected>0,"fixtures must exercise narrow routes and unreachable rooms")
assert(coverage.X and coverage.Z and coverage.Stair4 and coverage.Stair8 and coverage.rise16,
    "fixtures must cover both axes, 4/8 rises and multi-hop +16 rise")
print("PASS kit: "..counts.pairs.." graph pairs, "..counts.floors.." real floor resolutions, "
    ..counts.narrow.." Foam narrow hops, "..counts.rejected.." Slide unreachable pairs")

-- The old flat route really fails the floor window on the same +16 fixtures.
assert(oldUnresolved>0,"baseline must reproduce multi-hop height failure")
print("PASS baseline reproduces height failure: "..oldUnresolved.." unresolved points")

for _,seed in ipairs({1,101,404}) do
    local layout=LiveGenerator.Generate(seed)
    for _,h in ipairs(layout.Halls) do assert(h.FloorY==nil,"live fixture has no FloorY") end
    for i,c in ipairs(layout.Corridors) do
        assert(c.FromY==nil and c.ToY==nil and c.Kind~="Narrow","live corridor contract")
        -- Exercise default-width and SharedWall legacy paths as well.
        if i%3==0 then c.Width=nil end
    end
    for _,powered in ipairs({false,true}) do
        workspace.GetAttribute=function() return powered end
        for name,api in pairs(Current) do
            local old=Baseline[name]
            for _,a in ipairs(layout.Halls) do
                for _,b in ipairs(layout.Halls) do
                    for _,y in ipairs({-.92,2.125,17}) do
                        local from,to=center(a,y),center(b,y+3)
                        local nav,oldNav=navFor(api,layout,from),navFor(old,layout,from)
                        local current=api.graphRoute(layout,nav.HallByIndex,nil,from,to,offset)
                        local previous=old.graphRoute(layout,oldNav.HallByIndex,nil,from,to)
                        assert(encode(current or {})==encode(previous or {}),name..": byte-identical legacy golden route")
                        local cp,cs=nav:_fallbackWaypoints(to)
                        local op,os=oldNav:_fallbackWaypoints(to)
                        assert(cs==os and encode(cp)==encode(op),name..": legacy fallback golden")
                        counts.golden+=1
                    end
                end
            end
            for _,c in ipairs(layout.Corridors) do
                local middle=(c.From+c.To)/2
                for _,delta in ipairs({0,7,18,22}) do
                    local p=c.Axis=="X" and Vector3.new(middle,2.125,c.Cross+delta)
                        or Vector3.new(c.Cross+delta,2.125,middle)
                    local cs=api.corridorCentreSeed(layout,p)
                    local os=old.corridorCentreSeed(layout,p)
                    assert(encode(cs or {})==encode(os or {}),name..": legacy centre golden")
                    local cc=api.corridorContaining(layout,p)
                    local oc=old.corridorContaining(layout,p)
                    assert(encode(cc or {})==encode(oc or {}),name..": legacy containment golden")
                    assert(encode(api.corridorEntryPoint(c,p,p.Y) or {})==encode(old.corridorEntryPoint(c,p,p.Y) or {}),
                        name..": legacy entry golden")
                end
            end
        end
    end
end
print("PASS live golden: "..counts.golden.." byte-identical routes/fallbacks; centring/default Width/doors checked")
'''


def fixture(current, baseline):
    # Reuse the existing engine/vector and deterministic generator RNG fixtures.
    prefix = slide.PRELUDE + kit.PRELUDE[kit.PRELUDE.index("local Color3"):]
    prefix = prefix.replace("__CONFIG__", kit.CONFIG.read_text(encoding="utf-8"))
    prefix = prefix.replace("__MODULE__", kit.MODULE.read_text(encoding="utf-8"))
    declarations = []
    for group, sources in (("Current", current), ("Baseline", baseline)):
        declarations.append(f"local {group}={{}}")
        for name, source in sources.items():
            declarations.append(f"{group}.{name}=(function()\n{instrument(source)}\nend)()")
    declarations.append("local LiveGenerator=(function()\n" + kit.LIVE.read_text(encoding="utf-8") + "\nend)()")
    return prefix.replace("__RUN__", "\n".join(declarations) + "\n" + TESTS)


def run(binary, current, baseline):
    with tempfile.TemporaryDirectory(prefix="level2-kit-navigation-") as directory:
        path = Path(directory) / "navigation.luau"
        path.write_text(fixture(current, baseline), encoding="utf-8")
        return subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-dir", type=Path, required=True)
    parser.add_argument("--mutation-check", action="store_true")
    args = parser.parse_args()
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau") or kit.DEFAULT_BIN
    protected = (*SOURCES.values(), kit.MODULE, kit.CONFIG, kit.LIVE)
    digests = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in protected}
    current = {name: path.read_text(encoding="utf-8") for name, path in SOURCES.items()}
    baseline = {name: (args.baseline_dir / f"{name}.lua").read_text(encoding="utf-8")
                if (args.baseline_dir / f"{name}.lua").exists()
                else (args.baseline_dir / f"Level 2 Pool {name.title()} Navigator.ModuleScript.lua").read_text(encoding="utf-8")
                for name in SOURCES}
    result = run(binary, current, baseline)
    print(result.stdout, end="")
    assert result.returncode == 0, result.stderr
    if args.mutation_check:
        marker = "if corridor and corridorFits(corridor) and not corridorBlocked(corridor) then"
        assert current["slide"].count(marker) == 1
        mutant = dict(current)
        mutant["slide"] = mutant["slide"].replace(marker, "if corridor and not corridorBlocked(corridor) then", 1)
        result = run(binary, mutant, baseline)
        assert result.returncode != 0 and "width-filtered reachability" in result.stderr, result.stdout + result.stderr
        print("PASS mutation: removing Slide graph width filter fails width-filtered reachability")
    assert all(hashlib.sha256(path.read_bytes()).hexdigest() == digest for path, digest in digests.items())
    print("PASS source files unchanged by fixtures/mutation (temporary copies only)")


if __name__ == "__main__":
    main()
