"""Level 1 team prompts, server and client, in offline Luau.

Runs the REAL code: PuzzleManager's announceTeam helper and the three
ProximityPrompt handlers that mutate the puzzle (fuse pickup, fuse box, lever),
and PuzzleUI's objective / Feed helpers and PuzzleStatus handler. Nothing is
reimplemented -- the blocks are sliced out of the shipping sources by string
markers and given a stubbed engine.

What still needs Studio: the rendered pixel width of a prompt on a real device,
and that two real clients see the same line. Set LUAU_BIN to a Luau interpreter.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PUZZLE = (ROOT / "ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua").read_text(encoding="utf-8")
UI = (ROOT / "StarterPlayer/StarterPlayerScripts/PuzzleUI.LocalScript.lua").read_text(encoding="utf-8")
TEAM = (ROOT / "ServerScriptService/TeamObjectives.ModuleScript.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


def handler(source, opener, closer):
    """One Triggered:Connect body, as a bare `function(player) ... end`."""
    begin = source.index(opener)
    end = source.index(closer, begin)
    body = source[begin + len(opener):end]
    return "function(player)" + body + "\nend"


ANNOUNCE = section(PUZZLE, "local function announceTeam(", "\n\n-- ")
FUSE_HANDLER = handler(
    PUZZLE,
    "table.insert(owningSession.conns, prompt.Triggered:Connect(function(player)",
    "\n\tend))")
BOX_HANDLER = handler(
    PUZZLE,
    "table.insert(session.conns, box.prompt.Triggered:Connect(function(player)",
    "\n\t\tend))")
LEVER_HANDLER = handler(
    PUZZLE,
    "table.insert(session.conns, lever.prompt.Triggered:Connect(function(player)",
    "\n\t\tend))")

CLIENT_HELPERS = section(UI, "local leverPhase,", "remote.OnClientEvent:Connect")
CLIENT_EVENTS = section(UI, "remote.OnClientEvent:Connect(function(ev, a, b, c, d)", "\nend)\n")

SERVER = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end

-- ── engine stubs: only the boundary, never the logic under test ──
local sent = {}
local status = {}
function status:FireClient(target, ...) table.insert(sent, {target = target, args = {...}}) end
function status:FireAllClients(...) table.insert(sent, {target = 'all', args = {...}}) end
local function teamEvents()
    local out = {}
    for _, entry in ipairs(sent) do
        if entry.args[1] == 'objective' then table.insert(out, entry) end
    end
    return out
end

local function makePlayer(name, inRound)
    local p = {Name = name, Attributes = {InRound = inRound}, Character = {}}
    function p:GetAttribute(key) return self.Attributes[key] end
    function p:SetAttribute(key, value) self.Attributes[key] = value end
    function p.Character:FindFirstChildOfClass() return p.Humanoid end
    function p.Character:FindFirstChild() return nil end
    return p
end

local roster = {}
local Players = {}
function Players:GetPlayers() return roster end
function Players:FindFirstChild(name) for _, p in ipairs(roster) do if p.Name == name then return p end end end

local workspaceAttributes = {RoundActive = true}
local workspace = {}
function workspace:GetAttribute(key) return workspaceAttributes[key] end
function workspace:SetAttribute(key, value) workspaceAttributes[key] = value end
function workspace:FindFirstChild() return nil end

local Color3 = {fromRGB = function(r, g, b) return {r, g, b} end}
local task = {delay = function() end}
local game = {GetService = function() return {FindFirstChild = function() return nil end} end}
local function attr(_, default) return default end
local function updateCarriedFuse() end
local function updateEntityObjectiveTarget() end
local function showFuseInBox() end
local function entityToArea() end
local function setLeverHandle(lever, on) lever.on = on end
local FUSES_PER_BOX, FLICK_PER_FUSE, SPEED_PER_FUSE = 1, 0.6, 0.06
local ENTITY_AREA_CELLS, CELLv, LEVER_WINDOW = 5, 24, 10

-- ── the production announceTeam, verbatim ──
local remote = status
local Analytics = {Objective = function() end}
local TeamObjectives, serial = {}, 0
__TEAM_DELIVERY__
__ANNOUNCE__

-- ── the production prompt handlers, verbatim ──
local session, canUsePrompt
local allowed = true
canUsePrompt = function() return allowed end

local mikkel = makePlayer('MikkelCzar', true)
local mate = makePlayer('Mate', true)
local lobby = makePlayer('Lobby', nil)
roster = {mikkel, mate, lobby}

-- fuse pickup off a dropped stack
local owningSession, count, model, prompt, claimed
local fuseHandler

-- fuse box
local box, boxIndex
local boxHandler

-- lever
local lever
local leverHandler

local function freshSession()
    session = {
        active = true, stage = 'fuses', carried = {}, boxes = {}, levers = {},
        circuits = {}, boxesDone = 0, boxCount = 3, latchMode = false,
        fuseCharacters = {},
    }
    session.fuseCharacters[mikkel] = {Character = mikkel.Character, Humanoid = mikkel.Humanoid}
    session.fuseCharacters[mate] = {Character = mate.Character, Humanoid = mate.Humanoid}
    owningSession = session
    session.updateEntityObjectiveTarget = updateEntityObjectiveTarget
    for index = 1, 3 do
        session.circuits[index] = {Attributes = {},
            SetAttribute = function(self, key, value) self.Attributes[key] = value end,
            GetAttribute = function(self, key) return self.Attributes[key] end}
    end
    table.clear(sent)
end

local function freshBox(index)
    boxIndex = index
    box = {count = 0, complete = false, prompt = {Enabled = true}, model = {},
        ind = {}, indicatorLight = {}, statusLabel = {}, body = {Position = 0}}
    session.boxes[index] = box
    return box
end

local function freshLever(index)
    lever = {latched = false, activeUntil = 0, prompt = {Enabled = true}, model = {},
        pullSound = nil, cf = {Position = 0}}
    session.levers[index] = lever
    return lever
end

fuseHandler = __FUSE__
boxHandler = __BOX__
leverHandler = __LEVER__

local function boxOnLevers() end

-- ═══ 1. a validated fuse pickup announces exactly one team event ═══
freshSession()
count, claimed = 1, false
model = {Parent = true, Destroy = function(self) self.Parent = nil end}
prompt = {Enabled = true}
fuseHandler(mikkel)
local events = teamEvents()
expect(#events, 2, 'one team event per in-round player (three players, one in the lobby)')
local recipients = {}
for _, entry in ipairs(events) do recipients[entry.target.Name] = true end
expect(recipients.Lobby, nil, 'the lobby player is never told about a round it is not in')
expect(events[1].args[2].Actor, 'MikkelCzar', 'actor name')
expect(events[1].args[2].Key, 'level1:fuse', 'kind')
expect(events[1].args[2].Detail, 'took a fuse', 'detail')

-- ═══ 2. a refused prompt announces nothing ═══
freshSession()
allowed = false
count, claimed = 1, false
model = {Parent = true, Destroy = function(self) self.Parent = nil end}
prompt = {Enabled = true}
fuseHandler(mikkel)
expect(#teamEvents(), 0, 'canUsePrompt refused -> no team prompt')
allowed = true

-- ═══ 3. a multi-fuse stack says so ═══
freshSession()
count, claimed = 3, false
model = {Parent = true, Destroy = function(self) self.Parent = nil end}
prompt = {Enabled = true}
fuseHandler(mate)
expect(teamEvents()[1].args[2].Detail, 'took 3 fuses', 'a stack of three')

-- ═══ 4. powering a fuse box: one event, running count, circuit powered ═══
freshSession()
session.onAllBoxes = boxOnLevers
session.carried[mikkel] = 1
freshBox(2)
boxHandler(mikkel)
local boxEvents = teamEvents()
expect(#boxEvents, 2, 'one team event per in-round player')
expect(boxEvents[1].args[2].Key, 'level1:box', 'kind')
expect(boxEvents[1].args[2].Detail, 'powered a box \u{B7} 1/3', 'what changed and what remains')
expect(session.circuits[2]:GetAttribute('Powered'), true, 'the pair circuit is marked powered')
expect(session.circuits[1]:GetAttribute('Powered'), nil, 'and only that pair')

-- ═══ 5. a deposit with no fuse is a private refusal, not a team prompt ═══
freshSession()
session.onAllBoxes = boxOnLevers
session.carried[mikkel] = 0
freshBox(1)
boxHandler(mikkel)
expect(#teamEvents(), 0, 'no fuse carried -> no team prompt')
expect(sent[1].args[1], 'msg', 'the actor alone is told')

-- ═══ 6. the last box announces before the lever phase opens ═══
freshSession()
session.boxesDone = 2
local opened = false
session.onAllBoxes = function() opened = true end
session.carried[mikkel] = 1
freshBox(3)
boxHandler(mikkel)
expect(teamEvents()[1].args[2].Detail, 'powered a box \u{B7} 3/3', 'the final box')
expect(opened, true, 'and the lever phase still opens')

-- ═══ 7. a lever pull announces once; re-triggering inside its window does not ═══
freshSession()
session.stage = 'levers'
freshLever(1)
session.levers[2] = {latched = false, activeUntil = 0, prompt = {Enabled = true}}
session.levers[3] = {latched = false, activeUntil = 0, prompt = {Enabled = true}}
session.onLevers = function() end
session.broadcastLeverStatus = function() end
session.updateLeverLights = function() end
session.updateEntityObjectiveTarget = updateEntityObjectiveTarget
leverHandler(mate)
local leverEvents = teamEvents()
expect(#leverEvents, 2, 'one per in-round player')
expect(leverEvents[1].args[2].Key, 'level1:lever', 'kind')
expect(leverEvents[1].args[2].Detail, 'pulled lever \u{B7} 1/3', 'running lever count')
table.clear(sent)
leverHandler(mate)
expect(#teamEvents(), 0, 'the same lever, still inside its window, says nothing new')

-- ═══ 8. a second lever counts up ═══
table.clear(sent)
session.levers[2].activeUntil = 0
lever = session.levers[2]
leverHandler(mikkel)
expect(teamEvents()[1].args[2].Detail, 'pulled lever \u{B7} 2/3', 'second lever')

print(('server ok (%d checks)'):format(checks))
'''

CLIENT = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end
local attributes = {InRound = true}
local player = {GetAttribute = function(_, key) return attributes[key] end}
local worldAttrs = {SelectedLevel = 1, ExitPos = {kind='Vector3'}}
local workspace = {GetAttribute = function(_, key) return worldAttrs[key] end}
local typeof = function(value) return type(value) == 'table' and value.kind or type(value) end
local Players = {GetPlayerByUserId = function() return nil end}
local RoundHud = {Rows={}}
function RoundHud.SetObjective(state) RoundHud.State = state end
function RoundHud.Feed(row) table.insert(RoundHud.Rows,row) end
__HELPERS__
local onEvent = __EVENTS__
onEvent('begin',3,3)
expect(RoundHud.State.Title,'RESTORE THE POWER','begin objective')
expect(RoundHud.State.Count,0,'begin count')
onEvent('carry',1)
-- LEVER_PATH_20261010 (puzzle-client): preserve the actual receiver checks with the new return-route copy.
expect(RoundHud.State.Lines[1],'Follow a colored cable to a fuse box.','carry next action')
expect(RoundHud.State.Lines[2],'Insert the fuse. Then go back the same way.','carry return route')
onEvent('carry',0)
expect(RoundHud.State.Lines[1],'Find a fuse relay under the amber lights.','empty carry next action')
expect(RoundHud.State.Lines[2],'Pull the fuse out. Carry it to a fuse box.','empty carry extraction')
onEvent('team','MikkelCzar','box','powered a box \u{B7} 1/3')
expect(RoundHud.Rows[1].Actor,'MikkelCzar','untruncated actor for shared DisplayName')
expect(RoundHud.Rows[1].Detail,'powered a box \u{B7} 1/3','sentence-case detail')
expect(RoundHud.Rows[1].Key,'level1:box','shared coalescing key')
onEvent('team','AVeryLongRobloxName','lever','PULLED LEVER 1/3')
expect(RoundHud.Rows[2].Actor,'AVeryLongRobloxName','shared layout owns actor sizing')
expect(RoundHud.Rows[2].Detail,'pulled lever 1/3','old server compatibility')
onEvent('levers',3)
expect(RoundHud.State.Lines[1],'Go back along the cable from the fuse box.','lever next action')
expect(RoundHud.State.Lines[2],'Where it splits, follow the moving current.','lever junction')
expect(RoundHud.State.Status.Text,'Levers stay on. No time limit.','no lever countdown')
expect(RoundHud.State.Status.Kind,'info','lever persistence status')
onEvent('exit')
expect(RoundHud.State.Title,'GET OUT','exit objective')
expect(RoundHud.State.Compass.Target,worldAttrs.ExitPos,'server exit signal')
-- EXIT_COMPASS_20261010 (puzzle-client): repeated server exit packets must not duplicate the cue.
expect(RoundHud.Rows[3].Detail,'Exit open. Follow the green marker.','exit feed announcement')
expect(RoundHud.Rows[3].Kind,'LEVEL','exit feed kind')
onEvent('exit')
expect(#RoundHud.Rows,3,'single exit announcement')
attributes.InRound = nil
table.clear(RoundHud.Rows)
onEvent('team','MikkelCzar','box','powered a box \u{B7} 2/3')
expect(#RoundHud.Rows,0,'lobby player receives nothing')
attributes.InRound = true
attributes.Spectating = true
onEvent('team','MikkelCzar','box','powered a box \u{B7} 2/3')
expect(#RoundHud.Rows,1,'party spectator receives team feed')
worldAttrs.SelectedLevel=2
table.clear(RoundHud.Rows)
onEvent('team','MikkelCzar','box','powered a box \u{B7} 3/3')
expect(#RoundHud.Rows,0,'stale Level1 signal cannot reach another round')
print(('client ok (%d checks)'):format(checks))
'''


def run(name, source):
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("set LUAU_BIN to a Luau interpreter")
    directory = tempfile.mkdtemp()
    path = Path(directory) / f"{name}.luau"
    path.write_text(source, encoding="utf-8")
    result = subprocess.run([binary, str(path)], capture_output=True, text=True)
    shutil.rmtree(directory, ignore_errors=True)
    if result.returncode != 0:
        raise SystemExit(f"{name}:\n{result.stdout}\n{result.stderr}")
    print(result.stdout.strip())


def main():
    server = (SERVER
              .replace("__ANNOUNCE__", ANNOUNCE)
              .replace("__TEAM_DELIVERY__", section(TEAM, "function TeamObjectives.Announce(", "\nreturn TeamObjectives"))
              .replace("__FUSE__", FUSE_HANDLER)
              .replace("__BOX__", BOX_HANDLER)
              .replace("__LEVER__", LEVER_HANDLER))
    client = (CLIENT
              .replace("__HELPERS__", CLIENT_HELPERS)
              .replace("__EVENTS__", "function(ev, a, b, c, d)"
                       + CLIENT_EVENTS[len("remote.OnClientEvent:Connect(function(ev, a, b, c, d)"):]
                       + "\nend"))
    run("level1_team_prompts_server", server)
    run("level1_team_prompts_client", client)


if __name__ == "__main__":
    main()
