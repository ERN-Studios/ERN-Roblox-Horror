"""Run the four production B4 receivers' state helpers in offline Luau.

Shared drawing/compass geometry belongs to test_round_hud. This suite checks
the actual gameplay-to-card transitions, private/team feed delivery, the
Level 2 exit-only contract and the newer Level 3 CD-player mode. Engine replication,
streaming, rendered templates and controller focus still need Studio QA.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CLIENTS = ROOT / "StarterPlayer/StarterPlayerScripts"


def read(name):
    return (CLIENTS / name).read_text(encoding="utf-8-sig")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


PRELUDE = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end
local playerAttrs = {InRound = true}
local player = {GetAttribute = function(_, key) return playerAttrs[key] end}
local worldAttrs = {SelectedLevel = 1, ExitPos = {kind = 'Vector3'}}
local workspace = {GetAttribute = function(_, key) return worldAttrs[key] end}
local typeof = function(value) return type(value) == 'table' and value.kind or type(value) end
local RoundHud = {Rows = {}, State = nil, Calls = 0}
function RoundHud.SetObjective(state) RoundHud.State = state; RoundHud.Calls += 1 end
function RoundHud.Feed(row) table.insert(RoundHud.Rows, row) end
local Players = {GetPlayerByUserId = function() return nil end}
'''


def script():
    l1 = read("PuzzleUI.LocalScript.lua")
    l2 = read("Level 2 Objective UI.LocalScript.lua")
    l3 = read("Level 3 Reader Client.LocalScript.lua")
    l4 = read("Level 4 Round Client.LocalScript.lua")
    return PRELUDE + section(l1, "local leverPhase,", "remote.OnClientEvent:Connect") + r'''
applyPuzzleStatus('begin', 3, 3)
expect(RoundHud.State.Title, 'RESTORE THE POWER', 'begin title')
expect(RoundHud.State.Count, 0, 'begin boxes')
expect(RoundHud.State.Goal, 3, 'server box goal')
expect(RoundHud.State.Lines[1], 'Find a fuse under a bright ceiling light.', 'no fuse guidance')
applyPuzzleStatus('carry', 2)
expect(RoundHud.State.Lines[1], 'Fill a fuse box.', 'carried fuse next action')
applyPuzzleStatus('boxes', 2, 3)
expect(RoundHud.State.Count, 2, 'boxes update')
expect(RoundHud.State.Done, false, 'partial boxes')
applyPuzzleStatus('boxes', 3, 3)
expect(RoundHud.State.Done, true, 'boxes completed')
applyPuzzleStatus('levers', 4)
expect(RoundHud.State.Title, 'PULL THE LEVERS', 'phase transition')
expect(RoundHud.State.Count, 0, 'lever reset')
applyPuzzleStatus('lever', 2, 4, 8, true)
expect(RoundHud.State.Count, 2, 'latched levers update')
expect(RoundHud.State.Lines[2], 'They stay on. There is no time limit.', 'no invented countdown')
applyPuzzleStatus('msg', 'You have no fuses')
expect(RoundHud.Rows[1].Detail, 'You have no fuses', 'private refusal survives')
applyPuzzleStatus('team', 'MikkelCzar', 'box', 'POWERED A BOX 1/3')
expect(RoundHud.Rows[2].Actor, 'MikkelCzar', 'actor kept for DisplayName resolution')
expect(RoundHud.Rows[2].Detail, 'powered a box 1/3', 'legacy detail converted')
expect(RoundHud.Rows[2].Key, 'level1:box', 'shared duplicate merge key')
applyPuzzleStatus('escape', 'AnotherPlayer')
expect(RoundHud.State.Title, 'PULL THE LEVERS', 'other escape does not unlock objective')
applyPuzzleStatus('exit')
expect(RoundHud.State.Title, 'GET OUT', 'exit title')
expect(RoundHud.State.Compass.Target, worldAttrs.ExitPos, 'replicated exit target')
expect(RoundHud.State.Compass.State, 'locked', 'exit compass locked')
expect(RoundHud.State.Count, nil, 'completed count retires')
playerAttrs.Spectating = true
applyPuzzleStatus('begin', 3, 3)
expect(RoundHud.State.Lines[1], 'Find fuses and fill the fuse boxes.', 'no invented watched private carry')
worldAttrs.SelectedLevel = 2
local old = RoundHud.State
applyPuzzleStatus('boxes', 1, 3)
expect(RoundHud.State, old, 'wrong level cannot overwrite active objective')
''' + section(l2, "local function exitObjective(", "-- B4_LEVEL2_STATE_END") + r'''
local function expectExit(state, message)
    expect(state.Level, 2, message .. ': level')
    expect(state.Title, 'Find the exit', message .. ': only approved copy')
    expect(type(state.Lines), 'table', message .. ': lines exists')
    expect(next(state.Lines), nil, message .. ': no route guidance')
    expect(state.Done, false, message .. ': exit not pre-completed')
    for _, field in ipairs({'Count','Goal','Tag','Status','Compass','Eyebrow'}) do
        expect(state[field], nil, message .. ': no ' .. field)
    end
end
expectExit(exitObjective(), 'pure exit goal')
''' + section(l2, "local function objectiveSubject(", "-- B4_LEVEL2_STATE_BEGIN") + section(l2, "local function refresh()", "for _, attribute in ipairs(") + r'''
local localHum, localRoot = {Health=100}, {Position={Y=0}}
local localCharacter = {FindFirstChildOfClass = function() return localHum end,
    FindFirstChild = function() return localRoot end}
local watchedAttrs, watchedHum = {InRound=true}, {Health=100}
local watchedCharacter = {FindFirstChildOfClass = function() return watchedHum end,
    FindFirstChild = function() return {Position={Y=200}} end}
local watched = {GetAttribute = function(_,key) return watchedAttrs[key] end, Character=watchedCharacter}
Players.GetPlayerByUserId = function(_,id) return id == 42 and watched or nil end
local generatedAttrs = {}
local generatedWorld = {GetAttribute = function(_,key) return generatedAttrs[key] end}
workspace.FindFirstChild = function(_,name) return name == 'Level 2 Generated World' and generatedWorld or nil end
local function localReady()
    playerAttrs.InRound, playerAttrs.Escaped, playerAttrs.Spectating = true,nil,nil
    playerAttrs.SpectateTargetUserId, playerAttrs.Level2NewMapPreview = nil,nil
    player.Character, localHum, localRoot = localCharacter,{Health=100},{Position={Y=0}}
    worldAttrs.SelectedLevel, worldAttrs.RoundActive = 2,true
end
local function expectPublish(message)
    local before = RoundHud.Calls
    refresh()
    expect(RoundHud.Calls,before+1,message .. ': publishes actual refresh')
    expectExit(RoundHud.State,message)
end
local function expectRejected(message)
    local before, state = RoundHud.Calls, RoundHud.State
    refresh()
    expect(RoundHud.Calls,before,message .. ': never publishes')
    expect(RoundHud.State,state,message .. ': leaves selected objective owned by shared module')
end
localReady()
-- Old-map and new-map leftovers, including powered/lethal pumps and targets
-- far above/below the body, cannot add counters, danger, directions or a compass.
for index, payload in ipairs({
    {Pumps=0,Goal=3,Powered=false,Lethal=false,NewMap=false},
    {Pumps=2,Goal=3,Powered=false,Lethal=true,Target={kind='Vector3',Y=100},NewMap=false},
    {Pumps=3,Goal=3,Powered=true,Lethal=true,Target={kind='Vector3',Y=100},NewMap=false},
    {Pumps=30,Goal=0,Powered=true,Lethal=true,Target={kind='Vector3',Y=-100},NewMap=true},
    {Target='unreplicated',NewMap=true},
}) do
    worldAttrs.Level2Pumps, worldAttrs.Level2PumpGoal = payload.Pumps,payload.Goal
    worldAttrs.Level2ExitPowered, worldAttrs.Level2FoamLethal = payload.Powered,payload.Lethal
    worldAttrs.Level2_ExitPosition, generatedAttrs.Level2NewMap = payload.Target,payload.NewMap
    localRoot.Position.Y = index % 2 == 0 and 200 or 0
    expectPublish('map/pump/target payload ' .. index)
end
localRoot = nil
expectPublish('missing movement root still has a valid living objective subject')
localReady()
worldAttrs.SelectedLevel = 1
expectRejected('another level')
localReady()
playerAttrs.Level2NewMapPreview = true
expectRejected('local explore preview')
for _, active in ipairs({false,'true'}) do
    localReady(); playerAttrs.InRound = active
    expectRejected('local participant must be true, not ' .. tostring(active))
end
localReady(); playerAttrs.InRound = nil
expectRejected('local participant missing')
localReady(); playerAttrs.Escaped = true
expectRejected('local escaped body')
localReady(); localHum.Health = 0
expectRejected('local dead body')
localReady(); player.Character = nil
expectRejected('local character missing')
localReady(); localHum = nil
expectRejected('local humanoid missing')
-- The living watched participant owns the objective while spectating; local
-- death/escape/out-of-round does not substitute the viewer for that subject.
localReady()
playerAttrs.Spectating, playerAttrs.SpectateTargetUserId = true,42
playerAttrs.InRound, playerAttrs.Escaped, localHum.Health = nil,true,0
expectPublish('valid watched living participant')
watchedAttrs.Level2NewMapPreview = true
expectRejected('watched explore preview')
watchedAttrs.Level2NewMapPreview = nil
watchedAttrs.InRound = false
expectRejected('watched outside round')
watchedAttrs.InRound = nil
expectRejected('watched participant missing')
watchedAttrs.InRound, watchedAttrs.Escaped = true,true
expectRejected('watched escaped body')
watchedAttrs.Escaped, watchedHum.Health = nil,0
expectRejected('watched dead body')
watchedHum.Health, watched.Character = 100,nil
expectRejected('watched character missing')
watched.Character, watchedHum = watchedCharacter,nil
expectRejected('watched humanoid missing')
watchedHum = {Health=100}
playerAttrs.SpectateTargetUserId = 99
expectRejected('missing watched player')
playerAttrs.SpectateTargetUserId = '42'
expectRejected('non-numeric watched target')
playerAttrs.SpectateTargetUserId, playerAttrs.Level2NewMapPreview = 42,true
expectRejected('viewer explore preview while spectating')
localReady()
''' + section(l3, "local function chooseCDTarget(", "-- L3_CD_READER_TARGET_END_20260921") + section(l3, "local function readerTargetMode(", "-- L3_CD_PLAYER_GUIDANCE_PURE_END") + section(l3, "local function guideMovementCeiling(", "-- L3_GUIDE_MOVEMENT_BOUNDS_END") + r'''
local cd, distance, room = chooseCDTarget({{X=4,Z=0,Room='B'}, {X=9,Z=0,Room='A'}}, 0, 0, 'A')
expect(cd.X, 4, 'nearest CD is planar')
expect(distance, 4, 'exact nearest distance')
expect(room, true, 'same-room parity even if nearest is another room')
expect(readerTargetMode({'WORLD','CARRIED'}, 2, 0, false), 'SCAN', 'world disc still requires search')
expect(readerTargetMode({'DROPPED','CARRIED'}, 2, 0, false), 'SCAN', 'dropped disc still requires recovery')
expect(readerTargetMode({'CARRIED','CARRIED'}, 2, 0, false), 'PLAYER', 'all held means CD player')
expect(readerTargetMode({'INSERTED','CARRIED'}, 2, 1, false), 'PLAYER', 'remaining holder goes to CD player')
expect(readerTargetMode({'INSERTED','INSERTED'}, 2, 1, false), 'EXIT', 'inserted states authoritative')
expect(readerTargetMode({'WORLD','WORLD'}, 2, 2, false), 'EXIT', 'inserted count beats stale CD states')
expect(readerTargetMode({'WORLD','WORLD'}, 2, 0, true), 'EXIT', 'unlock beats stale CD states')
expect(readerTargetMode({nil,'CARRIED'}, 2, 0, false), 'SCAN', 'missing replication is not carried proof')
expect(math.deg(precisePlanarBearing(0,-1,1,0)),90,'precise CD-player guide points right')
local fx,fz = precisePlanarHeading(0,0,1,0,1,0)
expect(fx,0,'pitched camera uses right-vector yaw X')
expect(fz,-1,'pitched camera uses right-vector yaw Z')
local x,y,rotation,onPoint = projectGuidePoint(200,200,-1,math.pi,0,0,400,400)
expect(math.floor(x+.5),200,'behind target keeps guide on correct horizontal axis')
expect(math.floor(y+.5),400,'behind target points to bottom edge instead of mirrored front')
expect(onPoint,false,'behind projection is never an onscreen pin')
local ceiling,fits = guideMovementCeiling(999,60,200,190,180)
expect(ceiling,126,'scene guide preserves movement ceiling plus54px gutter')
expect(fits,true,'scene guide valid in remaining strip')
expect(select(2,guideMovementCeiling(999,150,200,190,180)),false,'scene guide disappears rather than cover movement')
''' + section(l4, "local function reelRooms(", "-- B4_LEVEL4_STATE_END") + r'''
expect(reelRooms('Concessions|Arcade|Concessions'), 'Reels: Concessions x2, Arcade', 'room duplicate order preserved')
expect(reelRooms(''), nil, 'empty room row retires')
expect(breakerStatus('Anna', 20).Kind, 'positive', 'held breaker beats fuse')
expect(breakerStatus('Anna', 20).Text, 'Main breaker: held by Anna', 'DisplayName in held status')
expect(breakerStatus(nil, 41.2).Kind, 'warning', 'fuse is amber warning')
expect(breakerStatus(nil, 41.2).Text, 'Main breaker: fuse 42 s', 'server fuse rounded up')
expect(breakerStatus(nil, 0).Kind, 'danger', 'off breaker is danger')
print('Objective receiver runtime: ' .. checks .. ' checks passed')
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN to the official Luau interpreter")
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    for name in ("PuzzleUI.LocalScript.lua", "Level 2 Objective UI.LocalScript.lua",
                 "Level 3 Reader Client.LocalScript.lua", "Level 4 Round Client.LocalScript.lua"):
        result = subprocess.run([compiler, "-O0", "--binary", str(CLIENTS / name)], capture_output=True)
        if result.returncode:
            raise SystemExit(result.stderr.decode("utf-8", errors="replace"))
    with tempfile.TemporaryDirectory(prefix="objective-receivers-") as directory:
        path = Path(directory) / "receiver_test.luau"
        path.write_text(script(), encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=20)
    print("Four objective clients compiled successfully")


if __name__ == "__main__":
    main()
