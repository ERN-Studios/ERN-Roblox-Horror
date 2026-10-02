"""Create one scoped GameManager candidate from the verified fresh baseline."""
from pathlib import Path
import hashlib
import json
import difflib

ROOT = Path(__file__).resolve().parent
BASE = ROOT / "ServerScriptService.GameManager.Script.baseline.luau"
source = BASE.read_text()
assert hashlib.sha256(source.encode()).hexdigest() == "cd045eee01354ea97fb49b35a78a31a968aab47a8cdd34cb34a3d16318416a11"
candidate = source

def replace(old, new):
    global candidate
    assert candidate.count(old) == 1, old[:100]
    candidate = candidate.replace(old, new)

replace('local Loading = require(script.Parent:WaitForChild("Round Loading Runtime"))',
'''local Loading = require(script.Parent:WaitForChild("Round Loading Runtime"))
local Level3KitWarmup = require(script.Parent:WaitForChild("Level 3 Kit Warmup"))
-- Session-owned Blender meshes warm once in the background; Level 1/2 boot and
-- round deadlines do not wait for this job.
Level3KitWarmup.Start()''')

replace('local previewCancel = station.previewQueue == true and requestedPrivacy == "cancel" and station.host == player',
'''local previewCancel = (station.previewQueue == true or station.kitWarming == true)
  and requestedPrivacy == "cancel" and station.host == player''')

replace('''local function beginGroupLoading(group)
 activeEntry = loadingRuntime:Begin(group)''',
'''local function beginGroupLoading(group, level, warmAllowed, originalDeadline)
 if level == 3 then
  local entryOwner = activeEntry
  if not Level3KitWarmup.Status().Ready then
   workspace:SetAttribute("RoundLoadingState", "warming")
   workspace:SetAttribute("LoadStage", "LEVEL_3_PREPARING_ASSETS")
   workspace:SetAttribute("RoundLoadingDeadline", nil)
   fireGroup(group, "loadinggame", 3)
  end
  local ready, problem = Level3KitWarmup.Await(function()
   return activeEntry == entryOwner and (not warmAllowed or warmAllowed() == true)
  end)
  if not ready then
   -- A replaced caller cannot fail or tear down a newer entry.
   if activeEntry == entryOwner then
    recoverFailedEntry(nil, problem, IS_RESERVED_ROUND_SERVER and Players:GetPlayers() or group)
   end
   return nil
  end
 end
 activeEntry = loadingRuntime:Begin(group)
 -- For reserved Level 1/2, target discovery keeps the original boot deadline.
 if originalDeadline then activeEntry.Deadline = math.min(activeEntry.Deadline, originalDeadline) end''')

replace(''' local attempt = beginGroupLoading(continuing)
 fireGroup(continuing, "loadinggame", nextLevel)''',
''' local attempt = beginGroupLoading(continuing, nextLevel, function()
  if not canAccessLevel(nextLevel, livePlayers(continuing)) then return false end
  for _, player in ipairs(continuing) do if player.Parent == Players then return true end end
  return false
 end)
 if not attempt then return end
 fireGroup(continuing, "loadinggame", nextLevel)''')

replace(''' station.busy = true
 setStationDisplay(station, "STARTING PRIVATE WORLD", #participants .. "/" .. (station.maxPlayers or MAX_PLAYERS_PER_STATION) .. " PLAYERS", station.color)''',
''' station.busy = true
 if station.level == 3 then
  local epoch, host = station.admissionEpoch, station.host
  local characters = {}
  for _, player in ipairs(participants) do characters[player] = player.Character end
  station.kitWarming = true
  fireGroup(participants, "queueconfigclosed")
  setStationDisplay(station, "PREPARING LEVEL 3", "STEP OUT TO CANCEL", station.color)
  local ready, problem = Level3KitWarmup.Await(function()
   if not station.busy or station.level ~= 3 or station.cancelRequested or station.revisionRetired
    or station.admissionEpoch ~= epoch or station.host ~= host
    or (IS_STUDIO and roundBusy) or not station.zone:IsDescendantOf(workspace) then return false end
   for _, player in ipairs(participants) do
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if player.Parent ~= Players or character ~= characters[player]
     or not humanoid or humanoid.Health <= 0 or player:GetAttribute("InRound") == true
     or not playerInsideZone(player, station, true) then return false end
   end
   return #participants > 0 and canAccessLevel(3, participants)
  end)
  station.kitWarming = nil
  if not ready then
   if problem ~= "ADMISSION_CANCELLED" then
    warn("[GameManager] Level 3 queue prewarm: " .. tostring(problem))
    setStationDisplay(station, "LEVEL 3 NOT READY", "STEP OUT AND TRY AGAIN", Color3.fromRGB(255,105,95))
   end
   fireGroup(participants, "lobbycancel")
   station.busy = false
   return
  end
 end
 setStationDisplay(station, "STARTING PRIVATE WORLD", #participants .. "/" .. (station.maxPlayers or MAX_PLAYERS_PER_STATION) .. " PLAYERS", station.color)''')

replace('''  local attempt = beginGroupLoading(participants)
  clearGlowsticks()''',
'''  local attempt = beginGroupLoading(participants, station.level or 1)
  if not attempt then station.busy = false; return end
  clearGlowsticks()''')

replace('''local function stageArrivingParty(attempt)
 local cohortReads = {}''',
'''local function stageArrivingParty(attempt, startedAtOverride, expectedSession)
 local cohortReads = {}''')
replace(''' local startedAt = os.clock()
 local firstArrivalAt = nil''',
''' local startedAt = startedAtOverride or os.clock()
 local firstArrivalAt = nil''')
replace('''  local group = Routing.SelectArrivalSession(entries)
  if group and not group.Final and group.Deadline then''',
'''  local group = Routing.SelectArrivalSession(entries)
  if group and expectedSession and (group.SessionId ~= expectedSession.SessionId or group.Level ~= expectedSession.Level) then
   attempt:Fail("ARRIVAL_SESSION_CHANGED")
   return "abandon", nil
  end
  if group and not group.Final and group.Deadline then''')

replace('''if IS_RESERVED_ROUND_SERVER then
 task.spawn(function()
  -- Hold characters behind the loading screen until the source's result window''',
'''-- Inspect a server-trusted arrival before starting the entry watchdog. Until
-- a target is known, preserve the former 60-second boot admission cutoff.
local function reservedEntryTarget()
 local startedAt = os.clock()
 local originalDeadline = startedAt + Loading.TimeoutSeconds
 while os.clock() < originalDeadline do
  local group = Routing.SelectArrivalSession(arrivalEntries())
  if group then return group, originalDeadline, startedAt end
  task.wait(.2)
 end
 return nil
end

if IS_RESERVED_ROUND_SERVER then
 task.spawn(function()
  -- Hold characters behind the loading screen until the source's result window''')
replace('''  local attempt = beginGroupLoading({})
  local decision, group = stageArrivingParty(attempt)''',
'''  local targetSession, originalDeadline, admissionStartedAt = reservedEntryTarget()
  if not targetSession then recoverFailedEntry(nil, "ARRIVAL_LOAD_FAILED", Players:GetPlayers()); return end
  local targetLevel = targetSession.Level
  local attempt = beginGroupLoading({}, targetLevel, function() return not failedReservedEntry end,
   targetLevel ~= 3 and originalDeadline or nil)
  if not attempt then return end
  -- PlayerAdded evidence remains live throughout prewarm, including members who
  -- departed before later continuers arrived. The existing tracker owns that math.
  local decision, group = stageArrivingParty(attempt, targetLevel ~= 3 and admissionStartedAt or nil,
   targetLevel == 3 and targetSession or nil)''')

out = ROOT / "ServerScriptService.GameManager.Script.candidate.v3.luau"
out.write_text(candidate)
warm = ROOT / "Level 3 Kit Warmup.ModuleScript.candidate.luau"
manifest = [
    {"targetPath":"ServerScriptService.GameManager", "className":"Script", "operation":"edit",
     "beforeHash":hashlib.sha256(source.encode()).hexdigest(), "editorHash":hashlib.sha256(source.encode()).hexdigest(),
     "candidatePath":str(out), "candidateHash":hashlib.sha256(candidate.encode()).hexdigest()},
    {"targetPath":"ServerScriptService.Level 3 Kit Warmup", "className":"ModuleScript", "operation":"create",
     "beforeHash":None, "editorHash":None, "candidatePath":str(warm), "candidateHash":hashlib.sha256(warm.read_bytes()).hexdigest()},
]
(ROOT / "warmup-candidate-manifest-v3.json").write_text(json.dumps(manifest,indent=2)+"\n")
(ROOT / "candidate-manifest-v3.json").write_text(json.dumps({"changes":[
    {"path":x["targetPath"], "class":x["className"], "new":x["operation"]=="create",
     "baselineSHA256":x["beforeHash"], "candidateSHA256":x["candidateHash"], "candidateFile":x["candidatePath"]}
    for x in manifest]},indent=2)+"\n")
(ROOT / "GameManager.warmup.v3.diff").write_text("".join(difflib.unified_diff(source.splitlines(True),candidate.splitlines(True),fromfile="ServerScriptService.GameManager live Source",tofile=str(out))))
print(json.dumps(manifest,indent=2))
