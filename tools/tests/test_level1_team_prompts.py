"""Level 1 team prompts, server and client, in offline Luau.

Runs the REAL code: PuzzleManager's announceTeam helper and the three
ProximityPrompt handlers that mutate the puzzle (fuse pickup, fuse box, lever),
and PuzzleUI's teamPrompt / refreshNextStep / PuzzleStatus handler. Nothing is
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

CLIENT_HELPERS = section(UI, "local carriedFuses = 0", "\n-- The toggle's caption follows")
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
        if entry.args[1] == 'team' then table.insert(out, entry) end
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

local workspaceAttributes = {RoundActive = true}
local workspace = {}
function workspace:GetAttribute(key) return workspaceAttributes[key] end
function workspace:SetAttribute(key, value) workspaceAttributes[key] = value end
function workspace:FindFirstChild() return nil end

local Color3 = {fromRGB = function(r, g, b) return {r, g, b} end}
local task = {delay = function() end}
local function attr(_, default) return default end
local function updateCarriedFuse() end
local function updateEntityObjectiveTarget() end
local function showFuseInBox() end
local function entityToArea() end
local function setLeverHandle(lever, on) lever.on = on end
local FUSES_PER_BOX, FLICK_PER_FUSE, SPEED_PER_FUSE = 1, 0.6, 0.06
local ENTITY_AREA_CELLS, CELLv, LEVER_WINDOW = 5, 24, 10

-- ── the production announceTeam, verbatim ──
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
expect(events[1].args[2], 'MikkelCzar', 'actor name')
expect(events[1].args[3], 'fuse', 'kind')
expect(events[1].args[4], 'TOOK A FUSE', 'detail')

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
expect(teamEvents()[1].args[4], 'TOOK 3 FUSES', 'a stack of three')

-- ═══ 4. powering a fuse box: one event, running count, circuit powered ═══
freshSession()
session.onAllBoxes = boxOnLevers
session.carried[mikkel] = 1
freshBox(2)
boxHandler(mikkel)
local boxEvents = teamEvents()
expect(#boxEvents, 2, 'one team event per in-round player')
expect(boxEvents[1].args[3], 'box', 'kind')
expect(boxEvents[1].args[4], 'POWERED A BOX 1/3', 'what changed and what remains')
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
expect(teamEvents()[1].args[4], 'POWERED A BOX 3/3', 'the final box')
expect(opened, true, 'and the lever phase still opens')

-- ═══ 7. a lever pull announces once; re-triggering inside its window does not ═══
freshSession()
session.stage = 'levers'
freshLever(1)
session.levers[2] = {latched = false, activeUntil = 0}
session.levers[3] = {latched = false, activeUntil = 0}
session.onLevers = function() end
session.broadcastLeverStatus = function() end
session.updateLeverLights = function() end
session.updateEntityObjectiveTarget = updateEntityObjectiveTarget
leverHandler(mate)
local leverEvents = teamEvents()
expect(#leverEvents, 2, 'one per in-round player')
expect(leverEvents[1].args[3], 'lever', 'kind')
expect(leverEvents[1].args[4], 'PULLED LEVER 1/3', 'running lever count')
table.clear(sent)
leverHandler(mate)
expect(#teamEvents(), 0, 'the same lever, still inside its window, says nothing new')

-- ═══ 8. a second lever counts up ═══
table.clear(sent)
session.levers[2].activeUntil = 0
lever = session.levers[2]
leverHandler(mikkel)
expect(teamEvents()[1].args[4], 'PULLED LEVER 2/3', 'second lever')

print(('server ok (%d checks)'):format(checks))
'''

CLIENT = r'''
local checks = 0
local function expect(value, wanted, message)
    checks += 1
    assert(value == wanted, message .. ': expected ' .. tostring(wanted) .. ', got ' .. tostring(value))
end

local clock = 1000
os = {clock = function() return clock end}

local Color3 = {fromRGB = function(r, g, b) return ('rgb(%d,%d,%d)'):format(r, g, b) end}

local function label(name)
    return {Name = name, Text = '', TextColor3 = '', Visible = false, Font = 'Code'}
end
local objectiveTitle, boxesLabel, carryLabel, leverLabel = label('t'), label('b'), label('c'), label('l')
local msgLabel = label('msg')

local shown = {}
local function showMessage(text)
    msgLabel.Text = tostring(text)
    msgLabel.Visible = true
    table.insert(shown, {text = msgLabel.Text, colour = msgLabel.TextColor3})
end
local function setObjectiveText(target, text, colour)
    if colour then target.TextColor3 = colour end
    target.Text = tostring(text)
end
local function applyPuzzleLayout() end
local function setReceiver() end
local function enterNavMode() end
local counters = false
local function showCounters(on) counters = on end
local LAYOUT = {SetProgress = function() end}
local leverPhase, leverActive, leverTotal = false, 0, 0
local leverEndsAt, leverLatchMode, leverLatchDone = 0, false, false
local function refreshLever() end

local attributes = {InRound = true}
local player = {}
function player:GetAttribute(key) return attributes[key] end

-- ── the production helpers, verbatim ──
__HELPERS__

-- ── the production PuzzleStatus handler, verbatim ──
local onEvent = __EVENTS__

-- ═══ 1. begin gives the carry row a standing instruction ═══
onEvent('begin', 3, 3)
expect(carryLabel.Text, 'FUSES CARRIED   0  \u{2022}  FIND A FUSE', 'the next step with no fuse')
expect(counters, true, 'the panel is up')

-- ═══ 2. carrying one changes the instruction, not just the count ═══
onEvent('carry', 1)
expect(carryLabel.Text, 'FUSES CARRIED   1  \u{2022}  FILL A FUSE BOX', 'carrying one')
onEvent('carry', 0)
expect(carryLabel.Text, 'FUSES CARRIED   0  \u{2022}  FIND A FUSE', 'back to none')

-- ═══ 3. a team prompt renders actor + detail, in the kind's colour ═══
onEvent('team', 'MikkelCzar', 'box', 'POWERED A BOX 1/3')
expect(msgLabel.Text, 'MIKKELCZAR POWERED A BOX 1/3', 'who did what')
expect(msgLabel.TextColor3, Color3.fromRGB(127, 218, 166), 'a box prompt is the box row colour')
expect(#msgLabel.Text <= 33, true, 'fits the 300px desktop strip at 15px Code')

-- ═══ 4. a long display name is cut, not allowed to spend the whole line ═══
clock += 5
onEvent('team', 'AVeryLongRobloxName', 'lever', 'PULLED LEVER 1/3')
expect(msgLabel.Text, 'AVERYLONGROB PULLED LEVER 1/3', 'name cut to 12')
expect(msgLabel.TextColor3, Color3.fromRGB(170, 225, 255), 'a lever prompt is the lever row colour')

-- ═══ 5. a rapid burst coalesces instead of flashing three lines ═══
clock += 5
table.clear(shown)
onEvent('team', 'One', 'box', 'POWERED A BOX 1/3')
clock += 0.2
onEvent('team', 'Two', 'box', 'POWERED A BOX 2/3')
clock += 0.2
onEvent('team', 'Three', 'box', 'POWERED A BOX 3/3')
expect(#shown, 3, 'each arrival still writes the surface')
expect(shown[1].text, 'ONE POWERED A BOX 1/3', 'the first is the plain line')
expect(shown[2].text, 'TWO POWERED A BOX 2/3  +1', 'the second carries the backlog')
expect(shown[3].text, 'THREE POWERED A BOX 3/3  +2', 'and the third')
clock += 1
onEvent('team', 'Four', 'fuse', 'TOOK A FUSE')
expect(msgLabel.Text, 'FOUR TOOK A FUSE', 'a gap resets the burst counter')

-- ═══ 6. the lever phase replaces the carry row with the cable instruction ═══
onEvent('levers', 3, 10)
expect(carryLabel.Text, 'FOLLOW THE CURRENT TO A LEVER', 'the reversed current, in words')
expect(#carryLabel.Text <= 37, true, 'no wider than the shipped lever row')

-- ═══ 7. and the exit phase replaces it again ═══
onEvent('exit')
expect(carryLabel.Text, 'REACH THE LIT EXIT DOOR', 'the last instruction')

-- ═══ 8. a lobby player is shown nothing, whatever the server sends ═══
attributes.InRound = nil
table.clear(shown)
onEvent('team', 'MikkelCzar', 'box', 'POWERED A BOX 2/3')
expect(#shown, 0, 'out of the round -> no prompt')
expect(counters, false, 'and the panel stands down')

-- ═══ 9. a SPECTATOR is in the round, so it sees what its party sees ═══
-- A dead or escaped participant keeps InRound until GameManager closes the
-- lifecycle; that is the whole of the parity rule for a party-wide prompt.
attributes.InRound = true
attributes.Spectating = true
attributes.SpectateTargetUserId = 4242
clock += 5
table.clear(shown)
onEvent('team', 'MikkelCzar', 'box', 'POWERED A BOX 2/3')
expect(#shown, 1, 'a spectator sees its party')
expect(shown[1].text, 'MIKKELCZAR POWERED A BOX 2/3', 'the same line the party got')

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
