"""Level 1 relay spawn targets for party sizes 1-6 (Trello JYiwjBxw), offline Luau.

Runs the REAL arithmetic sliced out of PuzzleManager.startPuzzle: box count,
fuses needed, the spawn target with the small-party bonus, and the fallback that
tops placement up to the SPAWN target (not merely to what completion needs).
pickWallSpots is stubbed to place a chosen number of frames per call so the
top-up path is exercised too.

What still needs Studio: that the maze actually offers that many wall spots
with decor/pit clearance (see the handoff's two solo layouts). Set LUAU_BIN.
"""

from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PUZZLE = (ROOT / "ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


COUNTS = section(PUZZLE, "\tlocal n = math.clamp(#roundPlayers, 1, 6)", "\n\tlocal leverCount = boxCount")
PLACEMENT = section(PUZZLE, "\tlocal relayFrames = pickWallSpots(fuseCount, 2.2 * CELLv, false, stations)",
                    "\n\tfor _, cf in ipairs(relayFrames) do")

SCRIPT = r'''
local FUSES_PER_BOX = 1
local SPAWN_MULT = 2
local attrs = {}
local workspace = {SetAttribute = function(_, key, value) attrs[key] = value end}
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end

-- pickWallSpots stub: the first call yields `firstYield` frames, later calls
-- yield everything asked for. Records the requests.
local firstYield, calls
local function pickWallSpots(count, minDist, edgeOnly, avoid)
    calls[#calls + 1] = {count = count, minDist = minDist}
    local yield = (#calls == 1) and math.min(count, firstYield) or count
    local frames = {}
    for i = 1, yield do frames[i] = {x = i} end -- stands in for a CFrame
    return frames
end

local function run(players, placedFirst)
    firstYield, calls = placedFirst, {}
    local roundPlayers = {}
    for i = 1, players do roundPlayers[i] = i end
    local CELLv = 24
    local stations = {}
''' + COUNTS + PLACEMENT + r'''
    return fuseCount, fusesNeeded, boxCount, #relayFrames, calls
end

local expectedTargets = {3, 3, 6, 4, 6, 6}
local expectedNeeded = {1, 1, 2, 2, 3, 3}
for players = 1, 6 do
    local target, needed, boxes, placed = run(players, 99)
    expect(target, expectedTargets[players], 'spawn target for ' .. players)
    expect(needed, expectedNeeded[players], 'fuses needed for ' .. players)
    expect(boxes, math.ceil(players / 2), 'box count for ' .. players)
    expect(placed, expectedTargets[players], 'placed relays for ' .. players)
    expect(attrs.Level1RelaySpawnTarget, expectedTargets[players], 'published target for ' .. players)
    expect(attrs.Level1RelaysPlaced, expectedTargets[players], 'published placed for ' .. players)
    assert(target >= needed, 'target below need')
end

-- Crowded maze: the first pass places only 2 of the solo target of 3; the
-- fallback asks for the missing ONE at the tighter spacing and reaches 3.
local target, needed, _, placed, calls = run(1, 2)
expect(target, 3, 'solo target')
expect(placed, 3, 'solo placed after top-up')
expect(#calls, 2, 'two placement passes')
expect(calls[2].count, 1, 'fallback asks for the shortfall')
assert(calls[2].minDist < calls[1].minDist, 'fallback relaxes spacing')

-- A party of four keeps the old behaviour exactly (2 boxes x 2 = 4).
local t4, n4, _, p4, c4 = run(4, 99)
expect(t4, 4, 'party of four target'); expect(n4, 2, 'party of four needed'); expect(#c4, 1, 'no fallback needed')

print('Level 1 relay spawns: ' .. checks .. ' checks passed (offline; real wall-spot availability needs Studio)')
'''


def main():
    luau = os.environ.get("LUAU_BIN")
    if not luau:
        raise SystemExit("set LUAU_BIN to a Luau interpreter")
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "relays.luau"
        path.write_text(SCRIPT, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True)
        print(result.stdout.strip())
        if result.returncode != 0:
            raise SystemExit(result.stderr.strip() or result.stdout.strip() or "luau failed")


if __name__ == "__main__":
    main()
