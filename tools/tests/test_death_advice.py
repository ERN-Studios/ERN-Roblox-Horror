"""Run the real death-cause pipeline offline: module, server blocks, HUD block.

DEATH_CAUSE_20260921 / RETRY_GUIDE_20260921. Nothing here is reimplemented. The
whole ReplicatedStorage/DeathAdvice module is loaded, and four server blocks and the real B8 fixture
are extracted from GameManager and RoundUI by string marker (the same technique
test_round_loading_host.py uses) and executed against fakes:

  * hookLife           -- the real hum.Died handler: does the "death" payload
                          carry the key, and does an unmarked death fall back to
                          DeathAdvice.Unknown without reordering name/position?
  * teleportPlayersToLobby / returnPlayersToLocalLobby / the setupPlayer packet
                          read -- RETRY_GUIDE_REMOVED_20260922: is NO retry level published for a
                          participant who did not escape?
  * RoundUI's death-card do-block -- does it draw its own death only, and does
                          an Unknown cause draw no tip?

Plus the copy contract (every key has a Title/Cause/Tip inside its limit), the
call-site contract (every DeathAdvice.Mark key under ServerScriptService is in
Causes, 2026-10-08), and a luau-compile of RoundUI, which is the register-limit
check: that chunk sits at Luau's 200-local ceiling and a new top-level local
fails with "Out of local registers".

What this CANNOT see: real replication of the two attributes, whether a Studio
kill site is actually reached, and anything about how the card looks. Set
LUAU_BIN to an official Luau interpreter (luau-compile.exe is expected beside
it, or on PATH).
"""

from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "ReplicatedStorage/DeathAdvice.ModuleScript.lua"
MANAGER = (ROOT / "ServerScriptService/GameManager.Script.lua").read_text(encoding="utf-8")
ROUNDUI_PATH = ROOT / "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"
ROUNDUI = ROUNDUI_PATH.read_text(encoding="utf-8")
KILL_SITES = {
    "L1Entity": "ServerScriptService/Level 1 Systems/EntityKill.Script.lua",
    "L1Pit": "ServerScriptService/Level 1 Systems/MazeGenerator.Script.lua",
    "L2Foam": "ServerScriptService/Level 2 Systems/Level 2 Pool Foam Controller.ModuleScript.lua",
    # L2Slide leaves (key, tip and this row) in the build where the Pool Slide no
    # longer spawns; dropping only the tip would turn its kills into SIGNAL LOST.
    "L2Slide": "ServerScriptService/Level 2 Systems/Level 2 Pool Slide Controller.ModuleScript.lua",
    "L3Manager": "ServerScriptService/Level 3 Systems/Level 3 Mall Manager AI Controller.ModuleScript.lua",
    # L2Hole (owner, 2026-10-08) joins with the file that adds its kill site: the
    # no-entity Level 2 is not built yet, so nothing marks it today.
}

# Mark call sites whose key is NOT in DeathAdvice.Causes, each with the reason it
# is tolerated. Mark refuses an unknown key, so such a death reads SIGNAL LOST.
# Every entry must still be observed; fixing one fails here until it is removed.
UNKEYED_MARKS = {
    ("ServerScriptService/Level 6 Systems/Level 6 Mall Manager AI Controller.ModuleScript.lua", "L6Manager"):
        "the dormant Level 6 mall clone (Routing.MaxLevel 4); DeathAdvice has no Level 6 key and no honest tip "
        "exists in code (HUD plan section 17), so its kills read SIGNAL LOST",
}
MARK_CALL = re.compile(r'DeathAdvice\.Mark\(\s*[^,()]+,\s*"([^"]*)"\s*\)')


def cause_keys(module_source):
    """The keys of DeathAdvice.Causes, read off the module's own table."""
    table = section(module_source, "DeathAdvice.Causes = {", "\n}\n")
    return set(re.findall(r"^\t([A-Za-z_]\w*) = \{", table, re.M))


def check_mark_call_sites(keys):
    """Every DeathAdvice.Mark(_, "X") under ServerScriptService names a key in Causes.

    This is what fails when one half of a cause is removed without the other: a
    key dropped from the table while a kill site still marks it, or a kill site
    added with a key nobody wrote copy for.
    """
    seen, unkeyed = 0, set()
    for path in sorted((ROOT / "ServerScriptService").rglob("*.lua")):
        relative = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        # A call MARK_CALL cannot read (a variable key, parentheses in the player
        # argument) would otherwise be skipped in silence.
        assert text.count("DeathAdvice.Mark(") == len(MARK_CALL.findall(text)), \
            f"{relative} has a DeathAdvice.Mark call this check cannot read"
        for key in MARK_CALL.findall(text):
            seen += 1
            if key in keys:
                continue
            assert (relative, key) in UNKEYED_MARKS, \
                f'{relative} marks "{key}", which DeathAdvice.Causes does not carry'
            unkeyed.add((relative, key))
    assert seen >= len(KILL_SITES), "the Mark call-site scan found too few call sites"
    for relative, key in UNKEYED_MARKS:
        assert (relative, key) in unkeyed, \
            f'UNKEYED_MARKS lists {relative} "{key}", which is no longer an unkeyed mark: remove the entry'
    return seen


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


HARNESS = r'''
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local function expect(actual, wanted, message)
    checks += 1
    assert(actual == wanted, message .. ': expected ' .. tostring(wanted)
        .. ', got ' .. tostring(actual))
end

local function signal()
    local listeners = {}
    return {
        Connect = function(_, fn)
            local entry = {fn = fn}
            table.insert(listeners, entry)
            return {Disconnect = function()
                for index, item in listeners do
                    if item == entry then table.remove(listeners, index) return end
                end
            end}
        end,
        Fire = function(_, ...)
            local snapshot = {}
            for index, item in listeners do snapshot[index] = item end
            for _, item in snapshot do item.fn(...) end
        end,
    }
end

local ALL = {}
local nodeMethods = {}
local function node(class, name, parent)
    local value = setmetatable({ClassName = class, Name = name, Parent = parent,
        Attributes = {}, Signals = {}}, {__index = nodeMethods})
    table.insert(ALL, value)
    return value
end
function nodeMethods:GetChildren()
    local result = {}
    for _, candidate in ALL do
        if candidate.Parent == self then table.insert(result, candidate) end
    end
    return result
end
function nodeMethods:FindFirstChild(name)
    for _, candidate in ALL do
        if candidate.Parent == self and candidate.Name == name then return candidate end
    end
end
function nodeMethods:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
function nodeMethods:IsA(class) return class == self.ClassName end
function nodeMethods:GetAttribute(key) return self.Attributes[key] end
function nodeMethods:SetAttribute(key, value)
    self.Attributes[key] = value
    if self.Signals[key] then self.Signals[key]:Fire() end
end
function nodeMethods:GetAttributeChangedSignal(key)
    self.Signals[key] = self.Signals[key] or signal()
    return self.Signals[key]
end
function nodeMethods:Destroy() self.Parent = nil end

local Instance = {new = function(class) return node(class, class, nil) end}
local Vector2 = {new = function(x, y) return {Kind = "Vector2", X = x, Y = y} end}
local Vector3 = {new = function(x, y, z) return {Kind = "Vector3", X = x, Y = y, Z = z} end}
local Color3 = {fromRGB = function(r, g, b) return {Kind = "Color3", R = r, G = g, B = b} end}
local UDim = {new = function(s, o) return {Kind = "UDim", S = s, O = o} end}
local UDim2 = {
    new = function(sx, ox, sy, oy) return {Kind = "UDim2", SX = sx, OX = ox, SY = sy, OY = oy} end,
    fromOffset = function(x, y) return {Kind = "UDim2", SX = 0, OX = x, SY = 0, OY = y} end,
    fromScale = function(x, y) return {Kind = "UDim2", SX = x, OX = 0, SY = y, OY = 0} end,
}
local Enum = {
    Font = {GothamBold = "GothamBold", GothamMedium = "GothamMedium", Code = "Code"},
    TextXAlignment = {Left = "Left"},
    TextYAlignment = {Top = "Top"},
    EasingStyle = {Quad = "Quad"},
}
local TweenInfo = {new = function(...) return {...} end}
local TweenService = {Create = function(_, object, _info, goal)
    return {Play = function() for key, value in goal do object[key] = value end end}
end}

-- The one clock the module reads. Tests drive it directly; there is no os.clock
-- anywhere in this pipeline on purpose (it is CPU time in the server datamodel).
local clock = {Now = 1000}
local workspace = node("Workspace", "Workspace")
function workspace:GetServerTimeNow() return clock.Now end

local DeathAdvice = (function()
--[[DEATHADVICE_SOURCE]]
end)()

local function newPlayer(name) return node("Player", name or "Tester") end

---------------------------------------------------------------- 1. the copy
do
    local seen = 0
    for key, advice in DeathAdvice.Causes do
        seen += 1
        check(type(advice.Title) == "string" and advice.Title ~= "", key .. " has a title")
        check(type(advice.Cause) == "string" and advice.Cause ~= "", key .. " has a cause")
        check(type(advice.Tip) == "string", key .. " has a tip field")
        check(#advice.Title <= DeathAdvice.TitleLimit,
            key .. " title is " .. #advice.Title .. " chars, over the limit")
        check(#advice.Cause <= DeathAdvice.CauseLimit,
            key .. " cause is " .. #advice.Cause .. " chars, over the limit")
        check(#advice.Tip <= DeathAdvice.TipLimit,
            key .. " tip is " .. #advice.Tip .. " chars, over the limit")
        check(advice.Title == string.upper(advice.Title), key .. " title is a HUD label")
        if key ~= DeathAdvice.Unknown then
            check(advice.Tip ~= "", key .. " must carry an actionable tip")
        end
    end
    check(seen >= 6, "every shipped cause key is in the table")
    -- The one key that is allowed to have no advice, and the only one that may.
    expect(DeathAdvice.Causes[DeathAdvice.Unknown].Tip, "",
        "an unexplained death offers no tip")
    expect(DeathAdvice.Copy("NoSuchKey").Title, DeathAdvice.Causes.Unknown.Title,
        "an unknown key reads as Unknown")
    expect(DeathAdvice.Copy(nil).Title, DeathAdvice.Causes.Unknown.Title,
        "a nil key reads as Unknown")
    -- The Level 2 floor hole (owner, 2026-10-08), word for word from the HUD plan.
    local hole = DeathAdvice.Causes.L2Hole
    check(hole ~= nil, "L2Hole is in the copy table")
    expect(hole.Title, "YOU FELL", "L2Hole title")
    expect(hole.Cause, "You fell through a hole in the floor.", "L2Hole cause")
    expect(hole.Tip, "Watch your step: some of the floor gives way.", "L2Hole tip")
    expect(DeathAdvice.IsKnown("L2Hole"), true, "L2Hole is a key a kill site may mark")
    -- The Pool Slide is still live in Level 2, so its tip stays until it is retired.
    check(DeathAdvice.Causes.L2Slide ~= nil, "L2Slide stays while the Pool Slide spawns")
end

---------------------------------------------- 2. Mark / Take / the freshness window
do
    local player = newPlayer()
    expect(DeathAdvice.Mark(player, "Fabricated"), false, "an invented key is refused")
    expect(DeathAdvice.Mark(player, DeathAdvice.Unknown), false,
        "Unknown is a fallback, not something a kill site may claim")
    expect(DeathAdvice.Mark(player, 7), false, "a non-string key is refused")
    expect(DeathAdvice.Mark(nil, "L2Foam"), false, "a nil player is refused")
    expect(player:GetAttribute(DeathAdvice.CauseAttribute), nil,
        "a refused mark writes nothing at all")

    expect(DeathAdvice.Mark(player, "L2Foam"), true, "a known key is accepted")
    expect(player:GetAttribute(DeathAdvice.CauseAttribute), "L2Foam", "the key is published")
    expect(player:GetAttribute(DeathAdvice.TimeAttribute), 1000, "the server time is published")
    expect(DeathAdvice.Take(player), "L2Foam", "a fresh mark is returned")
    expect(player:GetAttribute(DeathAdvice.CauseAttribute), nil, "Take consumes the mark")
    expect(DeathAdvice.Take(player), DeathAdvice.Unknown,
        "one mark can never explain two deaths")

    DeathAdvice.Mark(player, "L1Pit")
    clock.Now += DeathAdvice.FreshSeconds - 0.01
    expect(DeathAdvice.Take(player), "L1Pit", "still fresh just inside the window")
    DeathAdvice.Mark(player, "L1Pit")
    clock.Now += DeathAdvice.FreshSeconds + 0.01
    expect(DeathAdvice.Take(player), DeathAdvice.Unknown, "a stale mark is not inherited")
    expect(player:GetAttribute(DeathAdvice.TimeAttribute), nil,
        "a stale mark is cleared as well as ignored")

    -- A clock that went backwards (a server-time correction) is not evidence.
    DeathAdvice.Mark(player, "L3Manager")
    clock.Now -= 5
    expect(DeathAdvice.Take(player), DeathAdvice.Unknown, "a mark from the future is refused")

    DeathAdvice.Mark(player, "L1Entity")
    DeathAdvice.Clear(player)
    expect(player:GetAttribute(DeathAdvice.CauseAttribute), nil, "Clear removes the key")
    expect(player:GetAttribute(DeathAdvice.TimeAttribute), nil, "Clear removes the stamp")
end

-------------------------------------------------- 3. GameManager's real hum.Died
local function deathContext()
    local ctx = {Fired = {}, Alive = {}, Participants = {}, Conns = {}}
    ctx.Player = newPlayer("Faller")
    local character = node("Model", "Faller")
    local root = node("Part", "HumanoidRootPart", character)
    root.CFrame, root.Position = "frame", Vector3.new(1, 2, 3)
    ctx.Player.Character = character
    ctx.Humanoid = node("Humanoid", "Humanoid", character)
    ctx.Humanoid.Died = signal()
    ctx.Alive[ctx.Player] = true
    table.insert(ctx.Participants, ctx.Player)
    return ctx
end

local function runHookLife(ctx)
    local conns = ctx.Conns
    local alive = ctx.Alive
    local aliveCount = 1
    local deathFrames = {}
    local participants = ctx.Participants
    local lastDeathName = nil
    local lastDeathCause = DeathAdvice.Unknown
    -- CHALLENGES_20260923: the real hookLife counts each death into the run.
    local runFacts = {[ctx.Player] = {Deaths = 0}}
    ctx.RunFacts = runFacts
    local scheduleTransitionRespawn = nil
    -- The same block also reports to ZyntraAnalytics (added by the analytics work).
    local Analytics = setmetatable({}, {__index = function() return function() end end})
    local function fireGroup(_group, ...) table.insert(ctx.Fired, {...}) end
--[[HOOKLIFE_SOURCE]]
    hookLife(ctx.Player, ctx.Humanoid)
    function ctx:Report() return lastDeathName, lastDeathCause, aliveCount end
end

do
    local ctx = deathContext()
    runHookLife(ctx)
    DeathAdvice.Mark(ctx.Player, "L3Manager")
    ctx.Humanoid.Died:Fire()
    local payload = ctx.Fired[1]
    expect(payload[1], "death", "the event name is unchanged")
    expect(payload[2], "Faller", "the name still comes second")
    check(payload[3] ~= nil, "the position still comes third")
    expect(payload[4], "L3Manager", "the cause is APPENDED as the fourth value")
    local name, cause = ctx:Report()
    expect(name, "Faller", "the PARTY DOWN name is remembered")
    expect(cause, "L3Manager", "the PARTY DOWN cause is remembered")
    expect(ctx.Player:GetAttribute(DeathAdvice.CauseAttribute), nil,
        "the mark is consumed by the death that used it")
    expect(ctx.RunFacts[ctx.Player].Deaths, 1,
        "the death is counted into the run (CHALLENGES_20260923)")
end

do  -- an unmarked death: a void fall, a placement failure, a new kill site
    local ctx = deathContext()
    runHookLife(ctx)
    ctx.Humanoid.Died:Fire()
    expect(ctx.Fired[1][4], DeathAdvice.Unknown, "an unmarked death is Unknown, never invented")
end

do  -- a mark left over from a round that ended minutes ago
    local ctx = deathContext()
    runHookLife(ctx)
    DeathAdvice.Mark(ctx.Player, "L1Entity")
    clock.Now += 600
    ctx.Humanoid.Died:Fire()
    expect(ctx.Fired[1][4], DeathAdvice.Unknown, "a stale mark cannot explain a later death")
end

------------------------------------------------------- 4. No retry guide, server side
-- RETRY_GUIDE_REMOVED_20260922 (owner instruction): a non-escaped return draws
-- nothing. The packet carries no RetryLevel, the local fallback publishes no
-- RetryGuideLevel, and an OLD packet that still carries RetryLevel is ignored.
do
    local dispatched = nil
    local activeLevel = 2
    local inRound = {}
    local loadingFailures = {}
    local IS_RESERVED_ROUND_SERVER, IS_STUDIO = true, false
    local claimed = nil
    local function claimForTransfer(group) claimed = group; return group end
    local function releaseUndispatchedClaims() end
    local function dispatchTransfer(_group, descriptor)
        dispatched = descriptor
        return true, nil, 1
    end
    local function reportDispatchFailure() end
--[[TELEPORT_SOURCE]]
    local function send(members) dispatched = nil; teleportPlayersToLobby(members) end

    local died, escaped = newPlayer("Died"), newPlayer("Escaped")
    inRound[died], inRound[escaped] = true, true
    escaped:SetAttribute("Escaped", true)

    send({died})
    expect(dispatched.Data.RetryLevel, nil, "a participant who fell is NOT offered a retry level")
    expect(dispatched.Data.ReturnToLobby, true, "the existing packet field is untouched")
    send({died, escaped})
    expect(dispatched.Data.RetryLevel, nil, "nor is a mixed group")
    check(claimed ~= nil, "the real claim path still ran")
end

do
    local activeLevel = 3
    local inRound = {}
    local loadingFailures = {}
    local lobbySpawn = node("Part", "LobbySpawn")
    local task = {spawn = function(fn) fn() end}
    local status = {FireClient = function() end}
    local function livePlayers(group) return group end
    local function scatterAt() end
    local function loadLobbyCharacter() end
--[[LOCALLOBBY_SOURCE]]
    local died, escaped, bystander = newPlayer("D"), newPlayer("E"), newPlayer("B")
    inRound[died], inRound[escaped] = true, true
    escaped:SetAttribute("Escaped", true)
    returnPlayersToLocalLobby({died, escaped, bystander})
    expect(died:GetAttribute("RetryGuideLevel"), nil, "the local fallback publishes no retry level")
    expect(died:GetAttribute("Level4DevRoundEnded"), nil, "and no Level 4 dev banner flag")
    expect(escaped:GetAttribute("RetryGuideLevel"), nil, "not for an escapee")
    expect(bystander:GetAttribute("RetryGuideLevel"), nil, "not for a swept-up bystander")
    expect(died:GetAttribute("InRound"), false, "the existing lobby reset still runs")
end

do  -- the lobby side: an OLD packet that still names a RetryLevel is ignored
    local function arrive(packet, reserved)
        local player = newPlayer()
        local IS_RESERVED_ROUND_SERVER = reserved
        local run = function()
--[[SETUPPLAYER_SOURCE]]
        end
        run()
        return player:GetAttribute("RetryGuideLevel")
    end
    expect(arrive({ReturnToLobby = true, RetryLevel = 2}, false), nil, "an old packet's RetryLevel is read by nobody")
    expect(arrive({ReturnToLobby = true, RetryLevel = 2}, true), nil, "in a reserved round server too")
    expect(arrive({ReturnToLobby = true}, false), nil, "a packet without a level offers nothing")
    expect(arrive(nil, false), nil, "no packet at all is fine")
end

-- B8 card lifecycle is executed against actual HUD_Screens by test_hud_b8 below.

print("DeathAdvice: " .. checks .. " checks passed (real module and four server blocks and the real B8 fixture)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")

    # Every cause key the copy table carries must be spoken by a kill site, and
    # every mark a kill site makes must exist in the table. A key nothing marks
    # is dead copy; a mark with no key silently degrades to SIGNAL LOST.
    for key, relative in KILL_SITES.items():
        source = (ROOT / relative).read_text(encoding="utf-8")
        marker = 'DeathAdvice.Mark('
        assert marker in source, f"{relative} never marks a cause"
        assert f'"{key}")' in source, f"{relative} does not mark {key}"
    keys = cause_keys(MODULE.read_text(encoding="utf-8"))
    assert {"L2Hole", "L2Slide"} <= keys, "L2Hole is new and L2Slide stays until the Pool Slide is retired"
    sites = check_mark_call_sites(keys)
    print(f"DeathAdvice: {sites} Mark call sites under ServerScriptService checked against Causes "
          f"({len(UNKEYED_MARKS)} documented unkeyed exception)", flush=True)

    body = (
        HARNESS
        .replace("--[[DEATHADVICE_SOURCE]]", MODULE.read_text(encoding="utf-8"))
        .replace("--[[HOOKLIFE_SOURCE]]", section(
            MANAGER,
            "\tlocal function hookLife(player, hum)",
            "\t-- CharacterAutoLoads is intentionally disabled"))
        .replace("--[[TELEPORT_SOURCE]]", section(
            MANAGER,
            "local function teleportPlayersToLobby(group)",
            "\n-- THE transfer runtime."))
        .replace("--[[LOCALLOBBY_SOURCE]]", section(
            MANAGER,
            "local function returnPlayersToLocalLobby(group)",
            "\n-- One authoritative transfer per player"))
        .replace("--[[SETUPPLAYER_SOURCE]]", section(
            MANAGER,
            " -- RETRY_GUIDE_REMOVED_20260922",
            " player.CharacterAdded:Connect("))

    )

    with tempfile.TemporaryDirectory(prefix="death-advice-") as directory:
        path = Path(directory) / "death_advice_test.luau"
        path.write_text(body, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=30)

    # The register-limit check. RoundUI's main chunk holds 200 top-level locals;
    # a 201st fails to compile with "Out of local registers", which is why the
    # death card lives in a do-block.
    compiler = os.environ.get("LUAU_COMPILE_BIN") or shutil.which("luau-compile") \
        or str(Path(binary).with_name("luau-compile.exe"))
    if Path(compiler).exists() or shutil.which(compiler):
        subprocess.run([compiler, "--binary", "-O2", str(ROUNDUI_PATH)],
                       check=True, timeout=60, stdout=subprocess.DEVNULL)
        print("RoundUI compiles: the death card added no top-level local.")
    else:
        print("luau-compile not found; register-limit check skipped.")
    from test_hud_b8 import main as verify_b8
    verify_b8()


if __name__ == "__main__":
    main()
