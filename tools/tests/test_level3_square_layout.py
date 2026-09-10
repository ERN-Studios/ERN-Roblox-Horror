"""Run the actual Level 3 generator/validator and navigation fixtures in Luau.

The offline host uses a deterministic Park-Miller test PRNG, NOT Roblox Random.
Root must repeat the 104 acceptance seeds with engine Random in Studio. No game
source, Studio state, DataStore or live player is changed by this test.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SYSTEM = Path("ServerScriptService/Level 3 Systems")
BEFORE = ROOT / "artifacts/trello-20260909/level3-square-before"

HOST = r'''
local Vector3 = {new=function(x,y,z) return {X=x,Y=y,Z=z} end}
local Color3 = {fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end}
local Random = {}
function Random.new(seed)
    local state = math.floor(math.abs(seed)) % 2147483646 + 1
    local function nextUnit()
        state = (state * 16807) % 2147483647
        return (state - 1) / 2147483646
    end
    return {
        NextInteger=function(_, low, high) return low + math.floor(nextUnit() * (high-low+1)) end,
        NextNumber=function(_, low, high) return (low or 0) + nextUnit()*((high or 1)-(low or 0)) end,
    }
end
local checks = 0
local function check(value, message)
    checks += 1
    assert(value, message)
end
local function encode(value)
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    if type(value) == "string" then return string.format("%q", value) end
    assert(type(value) == "table", "fixture JSON type")
    local result = {}
    if #value > 0 then
        for _, item in ipairs(value) do table.insert(result, encode(item)) end
        return "[" .. table.concat(result, ",") .. "]"
    end
    for key, item in pairs(value) do table.insert(result, encode(tostring(key)) .. ":" .. encode(item)) end
    table.sort(result)
    return "{" .. table.concat(result, ",") .. "}"
end
'''

TESTS = r'''
local LayoutGenerator, Configuration = currentGenerator()
local Baseline = baselineGenerator()
local TestSuite = {}
__SUITE__
local seeds = {101,7331,65537,1900813}
for index=1,100 do table.insert(seeds, 104729*index+1) end
local baselineRejected, records, hashes = 0, {}, {}
local function independentBounds(rooms, excludeExit)
    local x1,x2,z1,z2 = math.huge,-math.huge,math.huge,-math.huge
    for _,room in ipairs(rooms) do
        if not excludeExit or room.Id ~= "Exit" then
            x1=math.min(x1,room.X-room.W/2); x2=math.max(x2,room.X+room.W/2)
            z1=math.min(z1,room.Z-room.D/2); z2=math.max(z2,room.Z+room.D/2)
        end
    end
    local width,depth=x2-x1,z2-z1
    return width,depth,math.max(width,depth)/math.min(width,depth)
end
for _,seed in ipairs(seeds) do
    local old=Baseline.Generate(seed)
    local _,_,oldAspect=independentBounds(old.Rooms,false)
    local _,_,oldCoreAspect=independentBounds(old.Rooms,true)
    check(oldAspect>1.5 and oldCoreAspect>2.1,"baseline must fail both shape targets")
    baselineRejected += 1
end
local structural=TestSuite.ValidateGeneratedLayouts(seeds,true)
local navigation=TestSuite.ValidateNavigationLayouts(seeds)
check(structural.FallbackCount==0 and structural.MaximumAttempt==1,"standard seeds must generate directly")
local unfiltered=currentUnfilteredGenerator()
local unfilteredRetried=0
for _,seed in ipairs(seeds) do
    if unfiltered.Generate(seed).Attempt>1 then unfilteredRetried+=1 end
end
check(unfilteredRetried>0,"removing the first-CD filter must reproduce rejected generation attempts")
for index=1,128 do table.insert(seeds, (index*982451653)%2147483646+1) end
for _,seed in ipairs(seeds) do
    local layout=LayoutGenerator.Generate(seed)
    local repeated=LayoutGenerator.Generate(seed)
    check(layout.LayoutHash==repeated.LayoutHash,"same seed must repeat exactly")
    check(layout.Attempt==1 and not layout.UsedFallbackSeed,"no concealed fallback dependence")
    check(LayoutGenerator.Validate(layout),"actual validator accepts emitted plan")
    check(#layout.Rooms==26 and #layout.Links==31 and layout.CyclomaticLoops==6,"counts and loops")
    local width,depth,aspect=independentBounds(layout.Rooms,false)
    local coreWidth,coreDepth,coreAspect=independentBounds(layout.Rooms,true)
    check(aspect<=1.5 and coreAspect<=2.1,"actual full/core aspect")
    check(width==layout.Bounds.Width and depth==layout.Bounds.Depth,"full measured bounds")
    check(coreWidth==layout.CoreBounds.Width and coreDepth==layout.CoreBounds.Depth,"core measured bounds")
    for column=1,4 do
        local sharedX
        for _,room in ipairs(layout.Rooms) do
            if room.SectionIndex>=1 and room.SectionIndex<=3 and room.GridColumn==column then
                if sharedX then check(room.X==sharedX,"shared column centre") else sharedX=room.X end
            end
        end
    end
    for gate=2,3 do
        local link=layout.GatewayLinks[gate]
        local a,b=layout.RoomById[link.A],layout.RoomById[link.B]
        local gap=b.Z-a.Z-(a.D+b.D)/2
        check(a.X==b.X and a.GridRow==2 and b.GridRow==1 and gap>=38 and gap<=48,
            "district south/north bridge and actual edge gap")
        check(a.GridColumn==layout.GatewayColumns[gate-1],"gateway column diagnostic")
    end
    local a,b=layout.RoomById.SignalHall,layout.RoomById.Exit
    check(a.Z==b.Z and b.X-a.X-(a.W+b.W)/2==560,"unchanged east-facing final hall")
    for first=1,#layout.ModuleRooms-1 do
        for second=first+1,#layout.ModuleRooms do
            local a,b=layout.ModuleRooms[first],layout.ModuleRooms[second]
            check((a.X-b.X)^2+(a.Z-b.Z)^2>=105^2,"all CDs are separated")
        end
    end
    hashes[layout.LayoutHash]=true
    table.insert(records,{seed=seed,width=width,depth=depth,aspect=aspect,coreWidth=coreWidth,
        coreDepth=coreDepth,coreAspect=coreAspect,attempt=layout.Attempt,hash=layout.LayoutHash,
        fallback=layout.UsedFallbackSeed,generationFailures=#layout.GenerationFailures})
end
local unique=0
for _ in pairs(hashes) do unique+=1 end
check(unique==#seeds,"every requested test seed retains distinct output")

-- Valid standard corners and deliberate Master overrides: shape acceptance is
-- optional, but geometry, counts, final length and CD spacing still validate.
local overrideFixtures={
    {MinimumRoomWidth=60,MaximumRoomWidth=60,MinimumRoomDepth=52,MaximumRoomDepth=52,
        MinimumInternalGap=24,MaximumInternalGap=24,MinimumGatewayGap=38,MaximumGatewayGap=38},
    {MinimumRoomWidth=78,MaximumRoomWidth=78,MinimumRoomDepth=68,MaximumRoomDepth=68,
        MinimumInternalGap=34,MaximumInternalGap=34,MinimumGatewayGap=48,MaximumGatewayGap=48},
    {ExtraLinksPerDistrict=0}, {ExtraLinksPerDistrict=3},
    {ExitCorridorLength=120}, {ExitCorridorLength=720},
    {MinimumRoomWidth=82,MaximumRoomWidth=90,MinimumRoomDepth=72,MaximumRoomDepth=80,
        RowHalfSpacing=100,MinimumModuleSeparation=120},
}
for _,overrides in ipairs(overrideFixtures) do
    local generator=currentGenerator(overrides)
    for _,seed in ipairs({101,7331,65537,1900813}) do
        local layout=generator.Generate(seed)
        check(generator.Validate(layout),"custom tuning remains structurally supported")
        check(not layout.UsedFallbackSeed,"override fixtures do not depend on fallback")
        local a,b=layout.RoomById.SignalHall,layout.RoomById.Exit
        check(b.X-a.X-(a.W+b.W)/2==(overrides.ExitCorridorLength or 560),"resolved final length")
        check(#layout.Links==3*(7+(overrides.ExtraLinksPerDistrict or 2))+4,"resolved extra links")
    end
end

local function rejectsMutation(change, expected)
    local layout=LayoutGenerator.Generate(101)
    change(layout)
    local valid,problem=LayoutGenerator.Validate(layout)
    check(not valid and string.find(problem,expected,1,true)~=nil,expected..": "..tostring(problem))
end
rejectsMutation(function(l) l.CoreBounds.Width+=1 end,"bounds are stale")
rejectsMutation(function(l) l.CoreBounds.Aspect=0/0 end,"bounds are stale")
rejectsMutation(function(l) l.GatewayColumns[1]=l.GatewayColumns[1]%4+1 end,"shared column")
rejectsMutation(function(l) l.GatewayLinks[2].FromThemeId="wrong" end,"gateway metadata")
rejectsMutation(function(l) l.Districts[2].IncomingGatewayLinkId="wrong" end,"district metadata")
rejectsMutation(function(l) l.RoomById.Exit.X+=1 end,"only hidden link")
rejectsMutation(function(l)
    local first=l.ModuleRooms[1]
    l.ModuleRooms[2]={X=first.X+104.99,Z=first.Z}
end,"not sufficiently separated")
rejectsMutation(function(l)
    for _,link in ipairs(l.Links) do
        local a,b=l.RoomById[link.A],l.RoomById[link.B]
        if a.Z==b.Z and a.X<b.X then
            for _,far in ipairs(l.Rooms) do
                if far.Z==a.Z and far.X>b.X and far.Id~="Exit" then
                    l.Links[#l.Links].A=a.Id; l.Links[#l.Links].B=far.Id
                    return
                end
            end
        end
    end
    error("no duplicate-port mutation fixture")
end,"same room side")

-- Execute the actual clearance-validation block with isolated geometric
-- counterexamples, without unrelated graph checks rejecting the fixture first.
local actual=LayoutGenerator.__test
local function room(id,x,z,w,d) return {Id=id,X=x,Z=z,W=w,D=d} end
local a,b=room("A",0,0,60,52),room("B",120,0,60,52)
local link={Id="AB",A="A",B="B"}
local footprint={Link=link,Bounds=actual.corridorBounds(a,b)}
check(actual.clearance({Rooms={a,b}},{footprint}),"endpoint joins and .04 seal are valid")
local crossing=room("FOREIGN",60,30,10,44)
local valid,problem=actual.clearance({Rooms={a,b,crossing}},{footprint})
check(not valid and string.find(problem,"unrelated room",1,true)~=nil,
    "foreign room shell must be rejected even where clear lane barely misses")
crossing.Z=31.3
check(actual.clearance({Rooms={a,b,crossing}},{footprint}),"non-overlapping foreign shell remains valid")
local c,d=room("C",60,-100,60,52),room("D",60,100,60,52)
local second={Link={Id="CD",A="C",B="D"},Bounds=actual.corridorBounds(c,d)}
valid,problem=actual.clearance({Rooms={a,b,c,d}},{footprint,second})
check(not valid and string.find(problem,"shells overlap",1,true)~=nil,
    "crossing unrelated corridor shells must be rejected")
c.X=150; d.X=150
second.Bounds=actual.corridorBounds(c,d)
check(actual.clearance({Rooms={}},{footprint,second}),"separated corridor shells remain valid")

print("RESULT "..encode({checks=checks,baselineRejected=baselineRejected,seedCount=#seeds,
    uniqueLayouts=unique,engine="Offline Park-Miller test PRNG; Roblox native sweep remains required",
    structural=structural,navigation=navigation,unfilteredCDSeedsRetried=unfilteredRetried,
    overrideFixtures=#overrideFixtures*4,records=records}))
'''


def between(text, start, end):
    return text[text.index(start):text.index(end, text.index(start))]


def generator_factory(root, name, testing=False, unfiltered=False):
    config = (root / SYSTEM / "Level 3 Configuration.ModuleScript.lua").read_text(encoding="utf-8-sig")
    source = (root / SYSTEM / "Level 3 Layout Generator.ModuleScript.lua").read_text(encoding="utf-8-sig")
    source = "\n".join(line for line in source.splitlines()
                       if not line.startswith("local Configuration = require(")
                       and not line.startswith("local Master = require("))
    if unfiltered:
        original = "if separated then table.insert(candidates, room) end"
        assert source.count(original) == 1
        source = source.replace(original, "table.insert(candidates, room)")
    if testing:
        clearance = between(source, "\tfor index, corridor in ipairs(corridorFootprints) do",
                            "\tif not boundsMatch(layout.Bounds")
        exports = ("LayoutGenerator.__test = {corridorBounds=corridorBounds, "
                   "clearance=function(layout,corridorFootprints)\n" + clearance + "\nreturn true end}\n")
        source = source.replace("return LayoutGenerator", exports + "return LayoutGenerator")
    return (f"local function {name}(overrides)\nlocal Configuration=(function()\n" + config +
            "\nend)()\nlocal Master={Overlay=function(configured)\nlocal result=table.clone(configured)\n"
            "for key,value in pairs(overrides or {}) do result[key]=value end\nreturn result end}\n"
            "local generator=(function()\n" + source + "\nend)()\nreturn generator,Configuration\nend\n")


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN to the Luau executable")
    suite = (ROOT / SYSTEM / "Level 3 Test Suite.ModuleScript.lua").read_text(encoding="utf-8-sig")
    fragments = (
        between(suite, "local DISTRICT_THEME_IDS", "local function containsArtifactFragment") +
        between(suite, "function TestSuite.ValidateGeneratedLayouts", "function TestSuite.ValidateConfiguration") +
        between(suite, "local NAVIGATION_TEST_SEEDS", "function TestSuite.ValidateManagerNavigationTelemetry")
    )
    script = (HOST + generator_factory(BEFORE, "baselineGenerator") +
              generator_factory(ROOT, "currentGenerator", testing=True) +
              generator_factory(ROOT, "currentUnfilteredGenerator", unfiltered=True) +
              TESTS.replace("__SUITE__", fragments))
    with tempfile.TemporaryDirectory(prefix="level3-square-") as temp:
        path = Path(temp) / "fixture.luau"
        path.write_text(script, encoding="utf-8")
        result = subprocess.run([binary, str(path)], text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
    line = next(line for line in result.stdout.splitlines() if line.startswith("RESULT "))
    report = json.loads(line.removeprefix("RESULT "))
    output = ROOT / "artifacts/trello-20260909/level3-square-offline.json"
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    maximum = max(row["aspect"] for row in report["records"])
    core_max = max(row["coreAspect"] for row in report["records"])
    print(f"L3 square: {report['checks']} checks passed; {report['seedCount']} seeds; "
          f"baseline rejected {report['baselineRejected']}; aspect max {maximum:.6f}; "
          f"core max {core_max:.6f}; native Roblox Random sweep still required")


if __name__ == "__main__":
    main()
