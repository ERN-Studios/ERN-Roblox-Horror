"""A new player's first tokens (NEW_PLAYER_TOKENS_20261011): the real profile mutation plus the real first-login
block from ZyntraMonetization, under a fake DataStore.

Covers: a first login banks Config.NewPlayerTokens and the free re-entry in ONE write, each behind its own marker; a
later login writes nothing; a repeat can never bank twice; an account that already holds the re-entry marker gets the
tokens without a second re-entry; a failed write leaves nothing behind and is retried; three failures are warned;
NewPlayerTokens = 0 switches the tokens off and leaves the re-entry alone; and the card's flag, its action and the
profile field are all wired. No Studio, no network. Set LUAU_BIN.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = (ROOT / "ServerScriptService/ZyntraMonetization.Script.lua").read_text(encoding="utf-8")
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")
GUIDE = (ROOT / "StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua").read_text(encoding="utf-8")


def section(start, stop):
    begin = SERVER.index(start)
    return SERVER[begin:SERVER.index(stop, begin)]


def welcome_block():
    block = section("\t-- WELCOME_REENTRY_20261010 (owner:", "\tlocal pendingSnapshot = pendingDispatchSnapshots")
    return "local function welcome(player, firstLogin)\n" + block + "end\n"


PRELUDE = r'''
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function equal(actual, expected, message)
    check(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end
local function world(gift, profile)
    local w = {pushes = {}, warnings = {}, committed = {}, storeCalls = 0, waits = 0, failures = 0, attributeCalls = 0}
    local function warn(...) table.insert(w.warnings, {...}) end
    local task = {wait = function() w.waits += 1 end, spawn = function(run) run() end}
    local Players = {}
    local player = {Name = "NewPlayer", UserId = 222, Parent = Players, ClassName = "Player"}
    local Config = {NewPlayerTokens = gift}
    local sessions, mutationLocks = {}, {}
    local data = profile or {Tokens = 0, ReentryCredits = 0, Grants = {Supporter = false, AdvancedEquipment = false},
        Settings = {TokenGuideSeen = false}}
    sessions[player] = {data = clone(data), persistent = true}
    w.committed["u_222"] = clone(data)
    local RunService = {IsStudio = function() return false end}
    local function normalizeProfile(value) return value end
    local function reassertPendingAccessibility() end
    local function applyAttributes() w.attributeCalls += 1 end
    local function pushProfile(p, message, tone) table.insert(w.pushes, {message = message, tone = tone}) end
    local store = {}
    function store:UpdateAsync(key, transform)
        w.storeCalls += 1
        if w.failures > 0 then w.failures -= 1 error("DataStore unavailable") end
        local result = transform(clone(w.committed[key]))
        if result then w.committed[key] = clone(result) end
        return clone(result)
    end
'''

TAIL = r'''
    w.player, w.sessions, w.welcome = player, sessions, welcome
    function w:saved() return self.committed["u_222"] end
    function w:live() return sessions[player].data end
    return w
end

-- A first login: tokens and the free re-entry in one write, each behind its own marker.
do
    local w = world(5)
    w.welcome(w.player, true)
    equal(w.storeCalls, 1, "one DataStore write for both gifts")
    equal(w:saved().Tokens, 5, "5 tokens committed")
    equal(w:saved().Grants.WelcomeTokens, true, "the tokens' marker is saved with them")
    equal(w:saved().ReentryCredits, 1, "the free re-entry is still banked")
    equal(w:saved().WelcomeReentry, "granted", "the re-entry's marker is still saved")
    equal(w:live().Tokens, 5, "the session copy adopts the saved profile")
    equal(#w.warnings, 0, "nothing to warn about")
    check(w.attributeCalls >= 1, "attributes are published again, which is what raises ZyntraTokenGuide")
    -- the same block run again for the same profile can never bank twice
    w.welcome(w.player, true); w.welcome(w.player, true)
    equal(w:saved().Tokens, 5, "a repeat never banks tokens again")
    equal(w:saved().ReentryCredits, 1, "a repeat never banks a second re-entry")
end

-- Every later login: nothing is read or written.
do
    local w = world(5)
    w.welcome(w.player, false)
    equal(w.storeCalls, 0, "a returning player triggers no write")
    equal(w:saved().Tokens, 0, "a returning player is given nothing")
    equal(w:saved().Grants.WelcomeTokens, nil, "and holds no marker")
end

-- A profile that already holds the re-entry marker: the tokens once, no second re-entry.
do
    local w = world(5, {Tokens = 3, ReentryCredits = 0, WelcomeReentry = "used", Grants = {}, Settings = {}})
    w.welcome(w.player, true)
    equal(w:saved().Tokens, 8, "tokens are added to what is there")
    equal(w:saved().ReentryCredits, 0, "a spent welcome re-entry is not banked again")
    equal(w:saved().WelcomeReentry, "used", "its marker is left as it was")
end

-- One failed write: nothing behind it, then the retry lands once.
do
    local w = world(5)
    w.failures = 1
    w.welcome(w.player, true)
    equal(w.storeCalls, 2, "the second try is made")
    equal(w:saved().Tokens, 5, "the retry banks the tokens once")
    equal(w:saved().ReentryCredits, 1, "and the re-entry once")
    equal(w.waits, 1, "it waited between the tries")
end

-- Three failed writes: nothing saved, no marker, and a warning; a later first login still delivers.
do
    local w = world(5)
    w.failures = 3
    w.welcome(w.player, true)
    equal(w.storeCalls, 3, "three tries, no more")
    equal(w:saved().Tokens, 0, "nothing committed")
    equal(w:saved().Grants.WelcomeTokens, nil, "no marker without the tokens")
    equal(w:live().Grants.WelcomeTokens, nil, "the session copy holds no marker either")
    check(#w.warnings >= 1, "the failure is warned, not swallowed")
    w.welcome(w.player, true)
    equal(w:saved().Tokens, 5, "the next successful first login delivers")
end

-- NewPlayerTokens = 0 (or missing) switches the tokens off and leaves the re-entry alone.
for _, off in ipairs({0, false}) do
    local w = world(off or nil)
    w.welcome(w.player, true)
    equal(w.storeCalls, 1, "one write, no retries waiting for tokens that are switched off")
    equal(w:saved().Tokens, 0, "no tokens")
    equal(w:saved().Grants.WelcomeTokens, nil, "no marker, so a later amount can still be given")
    equal(w:saved().ReentryCredits, 1, "the re-entry is banked as before")
    equal(#w.warnings, 0, "and it is not reported as a failure")
end

print(string.format("welcome tokens: %d checks passed (actual mutate + first-login block; fake DataStore)", checks))
'''


def check_wiring():
    count = 0

    def has(text, needle, why):
        nonlocal count
        assert needle in text, why
        count += 1

    has(CONFIG, "\tNewPlayerTokens = 5,", "the amount the owner chose (5) is the config's number")
    has(SERVER, "data.Grants.WelcomeTokens = data.Grants.WelcomeTokens == true or nil", "a hand-edited marker cannot be anything but true")
    has(SERVER, "data.Settings.TokenGuideSeen = data.Settings.TokenGuideSeen == true", "the card's flag is normalised to a boolean")
    has(SERVER, 'player:SetAttribute("ZyntraTokenGuide", data.Grants.WelcomeTokens == true and data.Settings.TokenGuideSeen ~= true)',
        "the card is owed only to a player who was given the tokens and has not answered it")
    has(SERVER, "\tMarkTokenGuideSeen = true,", "the card's answer is an allowed action")
    has(SERVER, '\telseif action == "MarkTokenGuideSeen" then\n\t\tmarkTokenGuideSeen(player)', "and it is dispatched")
    has(SERVER, 'RunService:IsStudio() and workspace:GetAttribute("DevSimulateFirstLogin") ~= true',
        "a simulated first login in Studio starts without Studio's test balance")
    has(GUIDE, 'config and tonumber(config.NewPlayerTokens) or 0', "the cards read the amount from the config")
    assert "StartingTokens" not in GUIDE, "the guide no longer shows Studio's test balance as a new player's start"
    has(GUIDE, 'action:FireServer("MarkTokenGuideSeen")', "the card reports its answer")
    has(GUIDE, 'player:GetAttribute("ZyntraTokenGuide") == true', "the card waits for the server's flag")
    return count + 1


def main():
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    wired = check_wiring()
    mutation = section("local function acquireMutation(player)", "-- Developer token gifts")
    source = "\n".join((PRELUDE, mutation, welcome_block(), TAIL))
    with tempfile.TemporaryDirectory(prefix="welcome-tokens-") as directory:
        path = Path(directory) / "welcome_tokens.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=60)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    if result.returncode == 0:
        print(f"welcome tokens: {wired} source checks passed")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
