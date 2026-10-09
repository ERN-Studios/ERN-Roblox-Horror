"""Generate only the reviewed two-source bootstrap proposal from fresh native baselines."""
from __future__ import annotations
import difflib
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[5]

SERVER = '''-- SPECTATE_BOOTSTRAP_SERVER_BEGIN
-- Candidate IDs come from the server roster before a remote body is streamed.
-- Live Levels 5/6 own their server InRound/preview flags outside this private roster.
local spectateCandidateRequests = {}
local function spectateParticipant(player)
 return player.Parent == Players and (inRound[player] == true
  or (player:GetAttribute("InRound") == true and player:GetAttribute("Level6PlaygroundPreview") == true))
end
local function validSpectator(player)
 if not spectateParticipant(player) then return false end
 local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
 return player:GetAttribute("Escaped") == true or not humanoid or humanoid.Health <= 0
end
local function validSpectatePair(player, target)
 if target == player or not validSpectator(player) or target.Parent ~= Players
  or target:GetAttribute("Escaped") == true then return false end
 local ownLive = player:GetAttribute("Level6PlaygroundPreview") == true
 local targetLive = target:GetAttribute("Level6PlaygroundPreview") == true
 if ownLive or targetLive then
  if not (ownLive and targetLive and player:GetAttribute("InRound") == true and target:GetAttribute("InRound") == true
   and (player:GetAttribute("Level5VoidRound") == true) == (target:GetAttribute("Level5VoidRound") == true)) then return false end
 elseif inRound[player] ~= true or inRound[target] ~= true then return false end
 local targetHumanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
 return targetHumanoid ~= nil and targetHumanoid.Health > 0
end
local function pruneSpectateCandidateRequests()
 for player, record in pairs(spectateCandidateRequests) do
  if record.Character ~= player.Character or not validSpectator(player) then spectateCandidateRequests[player] = nil end
 end
end
local function requestSpectateCandidates(player, serial)
 if type(serial) ~= "number" or serial ~= serial or serial < 1 or serial >= 2^53 or serial % 1 ~= 0 then return end
 if not validSpectator(player) then spectateCandidateRequests[player] = nil; return end
 local now, previous = os.clock(), spectateCandidateRequests[player]
 if previous and previous.Character == player.Character and now - previous.At < .8 then return end
 spectateCandidateRequests[player] = {Character = player.Character, At = now}
 local ids = {}
 for _, target in ipairs(Players:GetPlayers()) do
  if validSpectatePair(player, target) then ids[#ids + 1] = target.UserId end
 end
 status:FireClient(player, "spectatecandidates", {Serial = serial, UserIds = ids})
end
-- SPECTATE_BOOTSTRAP_SERVER_END
'''

CLIENT = '''local watch -- response handler and cycle controls share the existing owner
-- SPECTATE_BOOTSTRAP_CLIENT_BEGIN
local candidateUserIds = {}
local candidateRequestSerial = 0 -- monotonic across stop/start; late old sessions cannot win
local candidateSessionFirstSerial = 1
local candidateLastAcceptedSerial = 0
local function beginSpectateCandidateSession()
 table.clear(candidateUserIds)
 candidateSessionFirstSerial = candidateRequestSerial + 1
 candidateLastAcceptedSerial = candidateRequestSerial
end
local function endSpectateCandidateSession()
 table.clear(candidateUserIds)
 candidateSessionFirstSerial = candidateRequestSerial + 1
 candidateLastAcceptedSerial = candidateRequestSerial
 targets = {}
end
local function requestSpectateCandidates()
 if not spectating then return end
 candidateRequestSerial += 1
 remote:FireServer("spectatecandidates", candidateRequestSerial)
end
local function livingOthers()
 local list = {}
 for _, userId in ipairs(candidateUserIds) do
  local target = Players:GetPlayerByUserId(userId)
  if target and target ~= player and target.Parent == Players and target:GetAttribute("Escaped") ~= true
   and (player:GetAttribute("Level6PlaygroundPreview") ~= true
    or (target:GetAttribute("Level6PlaygroundPreview") == true
     and (target:GetAttribute("Level5VoidRound") == true) == (player:GetAttribute("Level5VoidRound") == true))) then
   -- Health and eligibility came from the server. Missing/stale local avatar
   -- parts cannot discard the ID whose focus is needed to stream that avatar.
   list[#list + 1] = target
  end
 end
 return list
end
local function receiveSpectateCandidates(payload)
 if not spectating or type(payload) ~= "table" or type(payload.UserIds) ~= "table" then return false end
 local serial = payload.Serial
 if type(serial) ~= "number" or serial ~= serial or serial % 1 ~= 0
  or serial < candidateSessionFirstSerial or serial > candidateRequestSerial
  or serial <= candidateLastAcceptedSerial then return false end
 local ids, seen = {}, {}
 for _, userId in ipairs(payload.UserIds) do
  if type(userId) ~= "number" or userId ~= userId or math.abs(userId) >= 2^53 or userId % 1 ~= 0 then return false end
  if not seen[userId] then seen[userId] = true; ids[#ids + 1] = userId end
 end
 candidateLastAcceptedSerial = serial
 candidateUserIds = ids
 targets = livingOthers()
 local selected = spectated and table.find(targets, spectated)
 if selected then idx = selected else watch(idx) end
 return true
end
-- SPECTATE_BOOTSTRAP_CLIENT_END
'''


def replace_once(source, before, after):
    assert source.count(before) == 1, "Fresh replacement boundary differs: " + before[:100]
    return source.replace(before, after, 1)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    capture = json.loads((HERE / "baseline-capture.json").read_bytes())
    assert capture["complete"] and capture["readOnly"]
    manifest = {"placeId": capture["placeId"], "universeId": capture["universeId"], "status": "Fresh exact two-source proposal; no Studio writes", "scripts": []}
    for pin in capture["sources"]:
        name = "GameManager" if pin["class"] == "Script" else "SpectateController"
        before = (HERE / (name + ".before.luau")).read_bytes()
        assert sha(before) == pin["sourceSha256"] and len(before) == pin["rawBytes"]
        source = before.decode("utf-8")
        if name == "GameManager":
            start, end = source.index("local function validSpectatePair(player, target)"), source.index("-- PERFORMANCE_STREAMING_20261009: a Scriptable spectator camera")
            source = source[:start] + SERVER + source[end:]
            source = replace_once(source, "local function republishSpectatorCounts()\n local counts = {}", "local function republishSpectatorCounts()\n pruneSpectateCandidateRequests()\n local counts = {}")
            source = replace_once(source, "local function clearSpectatorCounts()\n", "local function clearSpectatorCounts()\n table.clear(spectateCandidateRequests)\n")
            source = replace_once(source, "if next(spectateTargets) ~= nil or next(spectateFocus.Records) ~= nil then republishSpectatorCounts() end", "if next(spectateTargets) ~= nil or next(spectateFocus.Records) ~= nil or next(spectateCandidateRequests) ~= nil then republishSpectatorCounts() end")
            source = replace_once(source, "Players.PlayerRemoving:Connect(function(leaving)\n", "Players.PlayerRemoving:Connect(function(leaving)\n spectateCandidateRequests[leaving] = nil\n")
            source = replace_once(source, ' elseif message == "spectatetarget" then\n', ' elseif message == "spectatecandidates" then\n  requestSpectateCandidates(player, requestSerial)\n elseif message == "spectatetarget" then\n')
        else:
            start, end = source.index("local function livingOthers()"), source.index("-- borrowed flashlight:")
            source = source[:start] + CLIENT + "\n" + source[end:]
            source = replace_once(source, "local function watch(i)\n", "watch = function(i)\n")
            source = replace_once(source, "-- drive the POV camera + borrowed flashlight every frame while spectating", '''remote.OnClientEvent:Connect(function(message, payload)
 if message == "spectatecandidates" then receiveSpectateCandidates(payload) end
end)

-- drive the POV camera + borrowed flashlight every frame while spectating''')
            source = replace_once(source, "\tspectating = true\n\t-- Publish", "\tspectating = true\n\tbeginSpectateCandidateSession()\n\t-- Publish")
            source = replace_once(source, "\twatch(1)\n\tapplySpectateLayout()\nend", "\twatch(1)\n\trequestSpectateCandidates()\n\tapplySpectateLayout()\nend")
            source = replace_once(source, "local function stopSpectate()\n\tspectating = false\n", "local function stopSpectate()\n\tspectating = false\n\tendSpectateCandidateSession()\n")
            old = '''\t\tif spectating then
\t\t\tlocal hum = spectated and spectated.Character
\t\t\t\tand spectated.Character:FindFirstChildOfClass("Humanoid")
\t\t\tif not (hum and hum.Health > 0)
\t\t\t\tor (spectated and spectated:GetAttribute("Escaped") == true) then
\t\t\t\twatch(idx)
\t\t\tend
\t\tend'''
            new = '''\t\tif spectating then
\t\t\trequestSpectateCandidates()
\t\t\t-- A missing body is pending streaming, not proof of death. The fresh
\t\t\t-- server list removes dead targets; local membership/escape still clears promptly.
\t\t\tif not spectated or not table.find(livingOthers(), spectated) then watch(idx) end
\t\tend'''
            source = replace_once(source, old, new)
        after = source.encode("utf-8")
        output = HERE / (name + ".proposed.luau")
        output.write_bytes(after)
        (HERE / (name + ".diff")).write_text("".join(difflib.unified_diff(before.decode().splitlines(keepends=True), source.splitlines(keepends=True), fromfile=name + ".before", tofile=name + ".proposed")), encoding="utf-8", newline="\n")
        identity = {key: pin[key] for key in ("path", "name", "instanceId", "parentId", "parentPath", "parentClass")}
        identity["class"] = pin["class"]
        manifest["scripts"].append({"segments": pin["segments"], "class": pin["class"], "identity": identity,
            "beforeFile": pin["beforeFile"], "beforeSha256": sha(before), "beforeBytes": len(before),
            "afterFile": output.relative_to(ROOT).as_posix(), "afterSha256": sha(after), "afterBytes": len(after)})
    (HERE / "source-install-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(manifest))


if __name__ == "__main__":
    main()
