"""Run the real death-cause pipeline offline: module, server blocks, HUD block.

DEATH_CAUSE_20260921 / RETRY_GUIDE_20260921. Nothing here is reimplemented. The
whole ReplicatedStorage/DeathAdvice module is loaded, and five production blocks
are extracted from GameManager and RoundUI by string marker (the same technique
test_round_loading_host.py uses) and executed against fakes:

  * hookLife           -- the real hum.Died handler: does the "death" payload
                          carry the key, and does an unmarked death fall back to
                          DeathAdvice.Unknown without reordering name/position?
  * teleportPlayersToLobby / returnPlayersToLocalLobby / the setupPlayer packet
                          read -- is RetryGuideLevel published ONLY for a
                          participant who did not escape?
  * RoundUI's death-card do-block -- does it draw its own death only, and does
                          an Unknown cause draw no tip?

Plus the copy contract (every key has a Title/Cause/Tip inside its limit) and a
luau-compile of RoundUI, which is the register-limit check: that chunk sits at
Luau's 200-local ceiling and a new top-level local fails with "Out of local
registers".

What this CANNOT see: real replication of the two attributes, whether a Studio
kill site is actually reached, and anything about how the card looks. Set
LUAU_BIN to an official Luau interpreter (luau-compile.exe is expected beside
it, or on PATH).
"""

from pathlib import Path
import os
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
    "L2Slide": "ServerScriptService/Level 2 Systems/Level 2 Pool Slide Controller.ModuleScript.lua",
    "L3Manager": "ServerScriptService/Level 3 Systems/Level 3 Mall Manager AI Controller.ModuleScript.lua",
}


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
    local scheduleTransitionRespawn = nil
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

------------------------------------------------------- 4. RetryGuideLevel, server side
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
    expect(dispatched.Data.RetryLevel, 2, "a participant who fell is offered the same level")
    expect(dispatched.Data.ReturnToLobby, true, "the existing packet field is untouched")

    send({escaped})
    expect(dispatched.Data.RetryLevel, nil, "an escapee is never told to try again")

    send({died, escaped})
    expect(dispatched.Data.RetryLevel, nil,
        "a mixed group shares one packet, so nobody is told to retry a level they cleared")

    local bystander = newPlayer("Bystander")
    send({bystander})
    expect(dispatched.Data.RetryLevel, nil, "somebody who never entered gets no retry")
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
    expect(died:GetAttribute("RetryGuideLevel"), 3, "the local fallback offers the same level")
    expect(escaped:GetAttribute("RetryGuideLevel"), nil, "and refuses an escapee")
    expect(bystander:GetAttribute("RetryGuideLevel"), nil, "and a swept-up bystander")
    expect(died:GetAttribute("InRound"), false, "the existing lobby reset still runs")
end

do  -- the lobby side: only from the server-trusted packet, and never in a round server
    local function arrive(packet, reserved)
        local player = newPlayer()
        local IS_RESERVED_ROUND_SERVER = reserved
        local run = function()
--[[SETUPPLAYER_SOURCE]]
        end
        run()
        return player:GetAttribute("RetryGuideLevel")
    end
    expect(arrive({ReturnToLobby = true, RetryLevel = 2}, false), 2, "the packet is read")
    expect(arrive({ReturnToLobby = true, RetryLevel = 2}, true), nil,
        "a reserved round server has no lobby to guide anyone through")
    expect(arrive({ReturnToLobby = true}, false), nil, "a packet without a level offers nothing")
    expect(arrive({RetryLevel = 2}, false), nil, "a packet that is not a lobby return is ignored")
    expect(arrive(nil, false), nil, "no packet at all is fine")
    expect(arrive({ReturnToLobby = true, RetryLevel = "2"}, false), nil,
        "a non-number level is refused")
end

--------------------------------------------------------- 5. RoundUI's death card
do
    local RunService = {IsStudio = function() return false end}
    local player = newPlayer("Me")
    player.CharacterAdded = signal()
    local gui = node("ScreenGui", "RoundGui")
    local remote = {OnClientEvent = signal()}
    local storage = node("ReplicatedStorage", "ReplicatedStorage")
    local moduleNode = node("ModuleScript", "DeathAdvice", storage)
    local RS = storage
    local require = function(target)
        return assert(target == moduleNode and DeathAdvice, "unexpected require")
    end
    local task = {delay = function() end}  -- the dwell timer never fires in these checks
--[[DEATHCARD_SOURCE]]
    local card = gui:FindFirstChild("DeathCause")
    check(card ~= nil, "the card is built")
    expect(card.Visible, false, "and starts hidden")
    local function textOf(name) return card:FindFirstChild(name).Text end

    remote.OnClientEvent:Fire("death", "SomebodyElse", nil, "L2Foam")
    expect(card.Visible, false, "a teammate's death draws nothing")

    remote.OnClientEvent:Fire("death", "Me", nil, "L2Foam")
    expect(card.Visible, true, "our own death draws the card")
    expect(textOf("DeathCauseTitle"), DeathAdvice.Causes.L2Foam.Title, "the real title")
    expect(textOf("DeathCauseBody"), DeathAdvice.Causes.L2Foam.Cause, "the real cause")
    expect(textOf("DeathCauseTip"), DeathAdvice.Causes.L2Foam.Tip, "the real tip")
    check(card:FindFirstChild("DeathCauseTip").Visible, "the tip row is shown")

    -- A later spectate target dying must not repaint this player's own card.
    remote.OnClientEvent:Fire("death", "SomebodyElse", nil, "L3Manager")
    expect(textOf("DeathCauseTitle"), DeathAdvice.Causes.L2Foam.Title,
        "a spectated death never overwrites our own explanation")

    remote.OnClientEvent:Fire("lose")
    expect(card.Visible, false, "the round ending closes it")

    remote.OnClientEvent:Fire("death", "Me", nil, DeathAdvice.Unknown)
    expect(textOf("DeathCauseTitle"), DeathAdvice.Causes.Unknown.Title, "SIGNAL LOST")
    expect(textOf("DeathCauseTip"), "", "an unexplained death shows no tip")
    expect(card:FindFirstChild("DeathCauseTip").Visible, false, "and no tip row")
    expect(card:FindFirstChild("DeathCauseEyebrow").Visible, false, "and no NEXT TIME label")

    remote.OnClientEvent:Fire("death", "Me", nil, "Fabricated")
    expect(textOf("DeathCauseTitle"), DeathAdvice.Causes.Unknown.Title,
        "a key this client does not know degrades to SIGNAL LOST")

    remote.OnClientEvent:Fire("death", "Me", nil, "L1Pit")
    player.CharacterAdded:Fire()
    expect(card.Visible, false, "a re-entry respawn clears it without a round event")

    remote.OnClientEvent:Fire("death", "Me", nil, "L1Entity")
    expect(card.Visible, true, "and it comes back for the next death")
    remote.OnClientEvent:Fire("reentry", "Me")
    expect(card.Visible, false, "our own re-entry closes it")
end

print("DeathAdvice: " .. checks .. " checks passed (real module and five production blocks)")
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
            " -- RETRY_GUIDE_20260921. Only in the public lobby",
            " player.CharacterAdded:Connect("))
        .replace("--[[DEATHCARD_SOURCE]]", section(
            ROUNDUI,
            "\tlocal copyFor = function()",
            "\tif RunService:IsStudio() then"))
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


if __name__ == "__main__":
    main()
