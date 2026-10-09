"""Public Level 2: execute actual access, cohort and remote handlers.

No Studio or network. This does not establish physical collision or remote
integration in Play. Set LUAU_BIN to the official Luau interpreter. Candidate
files can be checked with --game-manager / --dev-access before a Studio CAS.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def section(source, start, stop):
    assert source.count(start) == 1, "GameManager access start marker drifted"
    assert source.count(stop) == 1, "GameManager access stop marker drifted"
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


PRELUDE = r'''
local checks = 0
local function check(ok, why)
 checks += 1
 assert(ok, why)
end
local function typeof(value)
 return if type(value) == "table" and rawget(value, "__instance") == true then "Instance" else type(value)
end
local studio = false
local Players = {}
local notices = {}
local clock = 0
local os = {clock = function() return clock end}
local status = {FireClient = function(_, target, ...)
 notices[#notices + 1] = {target = target, args = table.pack(...)}
end}
local game = {GetService = function(_, name)
 assert(name == "RunService", "unexpected service " .. name)
 return {IsStudio = function() return studio end}
end}
local function player(userId)
 return {__instance = true, UserId = userId, Parent = Players, Character = {},
  IsA = function(_, class) return class == "Player" end}
end
'''


INTEGRATION_PRELUDE = r'''
local IS_RESERVED_ROUND_SERVER = false
local MAX_PLAYERS_PER_STATION = 6
local lobbyStations = {}
local queueHandler
local queueConfig = {OnServerEvent = {Connect = function(_, callback) queueHandler = callback end}}
local geometryChecks = 0
local function playerInsideZone() geometryChecks += 1; return true end
local function level4ChoiceModes() return nil end
local function setStationDisplay(station, title, subtitle) station.display = {title, subtitle} end
local function revisedQueueIdleSubtitle() return "ENTER TO HOST" end
local task = {wait = function() end}
local function fireGroup(group, ...)
 for _, target in ipairs(group) do status:FireClient(target, ...) end
end
'''


CHECKS = r'''
local owner, developer = player(40920547), player(9488575949)
local guest, studioGuest = player(222), player(-1)
local previewGuest = player(11374988579)
local fakePlayer = {UserId = 40920547, ClassName = "Player", IsA = function() return true end}
local nonPlayer = {__instance = true, UserId = 40920547, IsA = function() return false end}
check(DevAccess.Level2Public == true, "the new Poolrooms ships open to ordinary players")
check(type(DevAccess.IsLevel2Allowed) == "function", "the shared Level 2 check exists")
check(Routing.MaxLevel == 4 and Routing.DevMaxLevel == 4, "the existing campaign ceilings remain four")
for _, subject in ipairs({guest, studioGuest, previewGuest, 222, -1}) do
 check(DevAccess.IsLevel2Allowed(subject), "shipped public access accepts ordinary players")
 check(not DevAccess.IsAllowed(subject), "shipped public access grants no developer commands")
end
check(canAccessLevel(2, {guest, studioGuest, previewGuest}), "shipped public access accepts a wholly ordinary cohort")

-- The optional maintenance flag still supports a deliberate closure. Exercise
-- its old denial paths explicitly rather than requiring the shipped place closed.
DevAccess.Level2Public = false

-- The Level 6 Studio/preview exception must never authorize Level 2.
for _, inStudio in ipairs({false, true}) do
 studio = inStudio
 for _, subject in ipairs({owner, developer, 40920547, 9488575949}) do
  check(DevAccess.IsAllowed(subject), "allowlisted subject keeps developer commands")
  check(DevAccess.IsLevel2Allowed(subject), "allowlisted subject may enter Level 2")
 end
 for _, subject in ipairs({guest, studioGuest, previewGuest, 222, -1, -2, 0, 11374988579,
  "40920547", fakePlayer, nonPlayer, false}) do
  check(not DevAccess.IsAllowed(subject), "non-allowlisted subject never becomes a developer")
  check(not DevAccess.IsLevel2Allowed(subject), "non-allowlisted subject is refused Level 2")
 end
 check(not DevAccess.IsLevel2Allowed(nil), "nil subject is refused Level 2")
 check(DevAccess.IsLevel6PreviewAllowed(studioGuest) == inStudio,
  "the preexisting negative Studio ID preview exception still applies to Level 6 only")
 check(DevAccess.IsLevel6PreviewAllowed(previewGuest), "the Level 6 preview guest stays authorized there")
end
studio = false

local malformed = {
 {label = "nil"}, {label = "boolean", value = false}, {label = "number", value = 40920547},
 {label = "string", value = "developers"}, {label = "empty", value = {}},
 {label = "numeric IDs", value = {40920547, 9488575949}},
 {label = "forged Player table", value = {fakePlayer}},
 {label = "non-Player instance", value = {nonPlayer}},
 {label = "developer then malformed", value = {owner, false}},
 {label = "sparse malformed member", value = {[1] = owner, [3] = false}},
 {label = "dictionary malformed member", value = {owner = owner, bad = 40920547}},
}
for _, case in ipairs(malformed) do
 local ok, allowed = pcall(canAccessLevel, 2, case.value)
 check(ok and allowed == false, "malformed group fails closed without throwing: " .. case.label)
end

for _, inStudio in ipairs({false, true}) do
 studio = inStudio
 for _, group in ipairs({{owner}, {developer}, {owner, developer}, {developer, owner},
  {[1] = owner, [3] = developer}, {owner = owner, developer = developer}}) do
  check(canAccessLevel(2, group), "every valid developer in the group may enter Level 2")
  check(canAccessLevel("2", group), "the existing numeric-string level input remains supported")
 end
 for _, group in ipairs({{guest}, {studioGuest}, {previewGuest}, {owner, guest}, {guest, owner},
  {owner, studioGuest}, {owner, previewGuest}, {[1] = owner, [3] = guest},
  {owner = owner, guest = guest}}) do
  check(not canAccessLevel(2, group), "one non-developer refuses the whole party, including sparse/dictionary groups")
 end
end
studio = false

-- Every unrelated public campaign level retains its previous behavior.
for _, level in ipairs({1, 3, 4}) do
 for _, group in ipairs({{guest}, {studioGuest}, {previewGuest}, {owner}, {owner, guest}, {}}) do
  check(canAccessLevel(level, group), "unrelated public level " .. level .. " remains accessible")
 end
 check(canAccessLevel(level, nil), "unrelated public level retains its old nil-group behavior")
end
for _, level in ipairs({5, 6, 7, 100}) do
 for _, group in ipairs({{owner}, {owner, developer}, {guest}, {owner, guest}, {}}) do
  check(not canAccessLevel(level, group), "the round ceiling still refuses level " .. level)
 end
end
for _, level in ipairs({0, -1, 1.5, 2.5, math.huge, -math.huge, 0/0, "bad", "2x", false, {}}) do
 local ok, allowed = pcall(canAccessLevel, level, {owner})
 check(ok and allowed == false, "invalid level fails closed without throwing: " .. tostring(level))
end
check(not canAccessLevel(nil, {owner}), "nil level is refused")

-- Changing one flag reopens Level 2 and does not grant developer commands or
-- alter either the campaign ceiling or other levels' preview gates.
DevAccess.Level2Public = true
for _, subject in ipairs({guest, studioGuest, previewGuest, 222, -1}) do
 check(DevAccess.IsLevel2Allowed(subject), "the single public flag opens Level 2")
 check(not DevAccess.IsAllowed(subject), "public Level 2 grants no developer commands")
end
for _, group in ipairs({{guest}, {studioGuest}, {previewGuest}, {owner, guest},
 {[1] = owner, [3] = guest}, {owner = owner, guest = guest}}) do
 check(canAccessLevel(2, group), "the single flag opens Level 2 for ordinary and mixed parties")
end
for _, case in ipairs(malformed) do
 local ok, allowed = pcall(canAccessLevel, 2, case.value)
 check(ok and allowed == false, "public mode still needs a valid nonempty Player group: " .. case.label)
end
check(not canAccessLevel(5, {guest}), "opening Level 2 never raises the round ceiling")
check(not DevAccess.IsLevel6PreviewAllowed(guest), "opening Level 2 never opens another preview")
DevAccess.Level2Public = false
check(not canAccessLevel(2, {owner, guest}), "closing the same flag again refuses mixed parties")

local function freshStation(level, host, privacy, capacity)
 clock += 3
 table.clear(notices)
 geometryChecks = 0
 return {index = 105, level = level, configured = true, host = host, privacy = privacy or "public",
  maxPlayers = capacity or 6, friendCache = {}, admittedCharacters = {}, admissionEpoch = 1}
end
local function denied(target)
 for _, notice in ipairs(notices) do
  if notice.target == target and notice.args[1] == "queueaccessdenied" then
   return notice.args[2] == 2 and notice.args[3] == DevAccess.Level2ClosedMessage
  end
 end
 return false
end

-- Execute the real cohort selection. It checks only the accepted party after
-- privacy/capacity selection, so an outsider cannot cancel a full/private party.
local station = freshStation(2, owner)
local accepted, raw, rejected, accessDenied = selectQueuedPlayers(station, {owner, developer})
check(#accepted == 2 and accepted[1] == owner and accepted[2] == developer, "developer party remains accepted")
check(station.admittedCharacters[owner] == owner.Character and station.admittedCharacters[developer] == developer.Character,
 "developer party preserves the normal admitted character tracking")
check(#notices == 0, "developer cohort emits no access denial")
check(not accessDenied, "developer cohort returns no denial flag")
for _, nondev in ipairs({guest, studioGuest, previewGuest}) do
 station = freshStation(2, owner)
 station.admittedCharacters = {[owner] = owner.Character, [nondev] = nondev.Character}
 accepted, raw, rejected, accessDenied = selectQueuedPlayers(station, {nondev, owner, developer})
 check(#accepted == 0 and #raw == 3, "one accepted non-developer refuses the whole cohort")
 check(next(station.admittedCharacters) == nil, "denial clears all old admitted characters")
 check(denied(owner) and denied(nondev), "host and denied member receive the same short notice")
 check(accessDenied == true, "the rejected cohort tells queue cleanup to preserve the denial")
end
station = freshStation(2, guest)
accepted = selectQueuedPlayers(station, {guest, owner})
check(#accepted == 0 and denied(guest), "a forged non-developer host is also refused")

station = freshStation(2, owner, "friends")
station.friendCache[guest.UserId] = true
accepted = selectQueuedPlayers(station, {owner, guest})
check(#accepted == 0 and denied(owner), "a non-developer friend refuses the mixed party")
station = freshStation(2, owner, "friends")
station.friendCache[guest.UserId] = false
station.friendCache[developer.UserId] = true
accepted, raw, rejected = selectQueuedPlayers(station, {guest, owner, developer})
check(#accepted == 2 and accepted[2] == developer, "a nonfriend outsider cannot cancel a developer party")
check(#rejected == 1 and rejected[1].player == guest and rejected[1].reason == "private",
 "a nonfriend keeps the normal private rejection reason")
check(#notices == 0, "a private outsider causes no party access denial")

station = freshStation(2, owner, "public", 2)
station.admittedCharacters[developer] = developer.Character
accepted, raw, rejected = selectQueuedPlayers(station, {guest, owner, developer})
check(#accepted == 2 and accepted[2] == developer, "an existing developer member keeps their place ahead of an outsider")
check(#rejected == 1 and rejected[1].player == guest and rejected[1].reason == "full",
 "a full-party outsider keeps the normal full rejection reason")
check(#notices == 0, "a full-party outsider causes no party access denial")
station = freshStation(2, owner, "public", 1)
accepted = selectQueuedPlayers(station, {owner, guest})
check(#accepted == 1 and accepted[1] == owner and #notices == 0, "solo capacity ignores a rejected outsider")

for _, level in ipairs({1, 3, 4}) do
 station = freshStation(level, owner)
 accepted = selectQueuedPlayers(station, {owner, guest})
 check(#accepted == 2 and #notices == 0, "unrelated level " .. level .. " still accepts ordinary mixed cohorts")
end
DevAccess.Level2Public = true
station = freshStation(2, owner)
accepted = selectQueuedPlayers(station, {owner, guest})
check(#accepted == 2 and #notices == 0, "one public flag reopens mixed cohort selection")
station = freshStation(2, guest, "public", 3)
accepted, raw, rejected, accessDenied = selectQueuedPlayers(station, {studioGuest, previewGuest, guest})
check(#accepted == 3 and accepted[1] == guest and #rejected == 0 and not accessDenied,
 "a full public party with no developers preserves its ordinary host and all members")
check(station.admittedCharacters[guest] == guest.Character
 and station.admittedCharacters[studioGuest] == studioGuest.Character
 and station.admittedCharacters[previewGuest] == previewGuest.Character and #notices == 0,
 "a wholly ordinary public cohort tracks each admitted character without a denial")
DevAccess.Level2Public = false

-- Execute the complete real ConfigureQueue callback against fake remote/UI
-- boundaries. Admission refuses even a nonhost caller before other early exits.
local function configureStation(level, host)
 local value = freshStation(level, host)
 value.awaitingConfig, value.configured = true, false
 lobbyStations[105] = value
 return value
end
for _, nondev in ipairs({guest, studioGuest, previewGuest}) do
 station = configureStation(2, owner)
 queueHandler(nondev, 105, 1, "public")
 check(denied(nondev), "direct nonhost ConfigureQueue call receives access denial")
 check(not station.configured and station.awaitingConfig and station.maxPlayers == 6,
  "direct nonhost ConfigureQueue call cannot mutate the station")
 check(geometryChecks == 0, "direct nonhost caller is refused before geometry or host checks")
 station = configureStation(2, nondev)
 queueHandler(nondev, 105, 1, "friends")
 check(denied(nondev) and not station.configured, "forged non-developer host cannot configure Level 2")
end
station = configureStation(2, owner)
station.busy, station.awaitingConfig = true, false
queueHandler(guest, 105, 1, "public")
check(denied(guest) and not station.configured, "busy/nonawaiting early exits do not swallow the refusal message")
for _, dev in ipairs({owner, developer}) do
 station = configureStation(2, dev)
 queueHandler(dev, 105, 2, "friends")
 check(station.configured and not station.awaitingConfig and station.maxPlayers == 2 and station.privacy == "friends",
  "developers configure the ordinary Level 2 party")
 check(geometryChecks == 1 and #notices == 1 and notices[1].args[1] == "queueconfigured",
  "developer configuration preserves the normal status event")
end
for _, level in ipairs({1, 3, 4}) do
 station = configureStation(level, guest)
 queueHandler(guest, 105, 3, "public")
 check(station.configured and station.maxPlayers == 3 and not denied(guest),
  "ordinary caller still configures unrelated level " .. level)
end
DevAccess.Level2Public = true
station = configureStation(2, guest)
queueHandler(studioGuest, 105, 1, "public")
check(not station.configured and station.awaitingConfig and #notices == 0 and geometryChecks == 0,
 "public access does not let a nonhost configure another player's party")
queueHandler(guest, 105, 3, "public")
check(station.configured and not station.awaitingConfig and station.maxPlayers == 3
 and station.privacy == "public" and geometryChecks == 1,
 "a wholly ordinary host configures a three-player public party through the real callback")
check(#notices == 1 and notices[1].target == guest and notices[1].args[1] == "queueconfigured"
 and not denied(guest), "ordinary configuration emits the normal confirmation without denial")
accepted, raw, rejected, accessDenied = selectQueuedPlayers(station, {guest, studioGuest, previewGuest})
check(#accepted == 3 and #rejected == 0 and not accessDenied,
 "the ordinary configured public party admits its complete nondeveloper cohort")
station = configureStation(2, guest)
queueHandler(guest, 105, 2, "friends")
-- Friendship is resolved after configuration; the real callback clears its
-- cache so the next once-per-second admission pass starts with fresh evidence.
station.friendCache[studioGuest.UserId] = true
accepted, raw, rejected, accessDenied = selectQueuedPlayers(station, {guest, previewGuest, studioGuest})
check(station.configured and station.privacy == "friends" and #accepted == 2
 and accepted[2] == studioGuest and #rejected == 1 and rejected[1].player == previewGuest
 and rejected[1].reason == "private" and not accessDenied,
 "public Level 2 retains friends-only party admission for an ordinary host")
DevAccess.Level2Public = false

-- Run the actual small reset branches and resetStation, ensuring ordinary
-- lobby/cancel feedback cannot immediately erase the access-denied message.
station = freshStation(2, owner)
station.feedback = {[owner] = "host", [guest] = "waiting"}
notifyLevel2AccessDenied({owner, guest})
local countBeforeReset = #notices
resetEmptyCohort(station, {}, true)
check(#notices == countBeforeReset and denied(owner) and denied(guest), "empty denied-party reset preserves both notices")
check(station.host == nil and not station.configured and next(station.feedback) == nil,
 "denied-party reset still clears queue state")
station = freshStation(2, owner)
station.feedback = {[owner] = "host", [guest] = "waiting"}
notifyLevel2AccessDenied({owner, guest})
countBeforeReset = #notices
resetCancelledCohort(station, {owner, guest}, true, true)
check(#notices == countBeforeReset, "denied countdown cleanup emits no lobbycancel or lobby overwrite")
check(station.host == nil and not station.configured, "denied countdown still resets the station")
station = freshStation(1, owner)
station.feedback = {[owner] = "host", [guest] = "waiting"}
resetEmptyCohort(station, {}, false)
check(#notices == 2 and notices[1].args[1] == "queueconfigclosed" and notices[2].args[1] == "lobby",
 "ordinary empty-party cleanup keeps host-close and lobby feedback")
station = freshStation(1, owner)
resetCancelledCohort(station, {owner, guest}, false, true)
check(#notices == 2 and notices[1].args[1] == "lobbycancel" and notices[2].args[1] == "lobbycancel",
 "ordinary countdown cancellation keeps lobbycancel feedback")

-- Leave the harness in the shipped state after its optional-maintenance checks.
DevAccess.Level2Public = true
check(canAccessLevel(2, {guest, studioGuest}), "public access is restored after closed-mode regression coverage")
print("Level 2 public queue: " .. checks .. " checks passed (actual public access, cohort, ConfigureQueue and maintenance fallback)")
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT)
    parser.add_argument("--game-manager", type=Path)
    parser.add_argument("--dev-access", type=Path)
    parser.add_argument("--routing", type=Path)
    args = parser.parse_args()
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests were executed.")
    manager = args.game_manager or args.source_root / "ServerScriptService/GameManager.Script.lua"
    access = args.dev_access or args.source_root / "ReplicatedStorage/DevAccess.ModuleScript.lua"
    routing = args.routing or args.source_root / "ServerScriptService/Round Completion Routing.ModuleScript.lua"
    manager_source = manager.read_text(encoding="utf-8")
    source = "\n".join([
        PRELUDE,
        "local DevAccess = (function()\n" + access.read_text(encoding="utf-8") + "\nend)()",
        "local Routing = (function()\n" + routing.read_text(encoding="utf-8") + "\nend)()",
        section(manager_source, "local LEVEL4_PUBLIC", "\n-- Always-on server authority"),
        INTEGRATION_PRELUDE,
        section(manager_source, "local function selectQueuedPlayers(station, raw)", "\nlocal function queuedPlayers(station)"),
        section(manager_source, "local function privacyLabel(station)", "\nlocal function connectElevator()"),
        section(manager_source, "local function resetStation(station, closeHost)", "\nlocal function syncSetupFeedback(station, raw)"),
        "local function resetEmptyCohort(station, ready, accessDenied)\n repeat\n" + section(
            manager_source, "  if #ready == 0 then\n", "\n  syncQueueFeedback(station, allInside, ready, rejected)",
        ) + "\n until true\nend",
        "local function resetCancelledCohort(station, lastReady, accessDenied, cancelled)\n repeat\n" + section(
            manager_source, "  if cancelled then\n", "\n  local participants = queuedPlayers(station)",
        ) + "\n until true\nend",
        CHECKS,
    ])
    with tempfile.TemporaryDirectory(prefix="level2-queue-gate-") as directory:
        fixture = Path(directory) / "level2_queue_gate.luau"
        fixture.write_text(source, encoding="utf-8")
        result = subprocess.run([binary, str(fixture)], capture_output=True, text=True, timeout=20)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
