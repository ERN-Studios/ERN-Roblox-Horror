Read-only review of ONLY installed GM warm changes/helper. No tools. <=180word verdict clear/material-fix/uncertain, concrete trigger/effect/minimalfix; no private reasoning.
60s Loading.Begin must follow coldkit(1200s cap). Check cancel/ownership/deadlines. ExistingStudio postwarm roundBusy check/set has no yield; readyAwait no yield. recover(nil,reason,group) resets players/round and cleans localworld; existingLevel2floor retained beforeBegin. Reserved SelectArrivalSession ignores rawLevel; unchanged staging remembers all departureevidence, tracks presence, reads finalMemoryStorecohort, admits only Final+fullcohort.1/2 retain bootdeadline.5/6DEV unchanged.
27virtual scenarios86checks pass; no live transport/perf claim.14Source/editor nativeCAS exact installed19:59:36Z; only these2reviewed; full14pins in receipt/inputmanifest.
ServerScriptService.GameManager 8e365508c1e42d9b50e28e8faa3d36ba72eb7b3ba667faf47e92d208262f0ef9
ServerScriptService.Level 3 Kit Warmup 870130d1282ed11df29998e286221a6597cc8d9e40e62baad5f957d020dfc72c
GM zero-context exact diff (whitespace/comment-only lines removed):
```diff
@@ -30,0 +31,4 @@
+local Level3KitWarmup = require(script.Parent:WaitForChild("Level 3 Kit Warmup"))
+Level3KitWarmup.Start()
@@ -1542 +1546,2 @@
-local previewCancel = station.previewQueue == true and requestedPrivacy == "cancel" and station.host == player
+local previewCancel = (station.previewQueue == true or station.kitWarming == true)
+and requestedPrivacy == "cancel" and station.host == player
@@ -2185 +2190,20 @@
-local function beginGroupLoading(group)
+local function beginGroupLoading(group, level, warmAllowed, originalDeadline)
+if level == 3 then
+local entryOwner = activeEntry
+if not Level3KitWarmup.Status().Ready then
+workspace:SetAttribute("RoundLoadingState", "warming")
+workspace:SetAttribute("LoadStage", "LEVEL_3_PREPARING_ASSETS")
+workspace:SetAttribute("RoundLoadingDeadline", nil)
+fireGroup(group, "loadinggame", 3)
+end
+local ready, problem = Level3KitWarmup.Await(function()
+return activeEntry == entryOwner and (not warmAllowed or warmAllowed() == true)
+end)
+if not ready then
+if activeEntry == entryOwner then
+recoverFailedEntry(nil, problem, IS_RESERVED_ROUND_SERVER and Players:GetPlayers() or group)
+end
+return nil
+end
+end
@@ -2186,0 +2211,2 @@
+if originalDeadline then activeEntry.Deadline = math.min(activeEntry.Deadline, originalDeadline) end
@@ -2561 +2587,6 @@
-local attempt = beginGroupLoading(continuing)
+local attempt = beginGroupLoading(continuing, nextLevel, function()
+if not canAccessLevel(nextLevel, livePlayers(continuing)) then return false end
+for _, player in ipairs(continuing) do if player.Parent == Players then return true end end
+return false
+end)
+if not attempt then return end
@@ -3229,0 +3261,31 @@
+if station.level == 3 then
+local epoch, host = station.admissionEpoch, station.host
+local characters = {}
+for _, player in ipairs(participants) do characters[player] = player.Character end
+station.kitWarming = true
+fireGroup(participants, "queueconfigclosed")
+setStationDisplay(station, "PREPARING LEVEL 3", "STEP OUT TO CANCEL", station.color)
+local ready, problem = Level3KitWarmup.Await(function()
+if not station.busy or station.level ~= 3 or station.cancelRequested or station.revisionRetired
+or station.admissionEpoch ~= epoch or station.host ~= host
+or (IS_STUDIO and roundBusy) or not station.zone:IsDescendantOf(workspace) then return false end
+for _, player in ipairs(participants) do
+local character = player.Character
+local humanoid = character and character:FindFirstChildOfClass("Humanoid")
+if player.Parent ~= Players or character ~= characters[player]
+or not humanoid or humanoid.Health <= 0 or player:GetAttribute("InRound") == true
+or not playerInsideZone(player, station, true) then return false end
+end
+return #participants > 0 and canAccessLevel(3, participants)
+end)
+station.kitWarming = nil
+if not ready then
+if problem ~= "ADMISSION_CANCELLED" then
+warn("[GameManager] Level 3 queue prewarm: " .. tostring(problem))
+setStationDisplay(station, "LEVEL 3 NOT READY", "STEP OUT AND TRY AGAIN", Color3.fromRGB(255,105,95))
+end
+fireGroup(participants, "lobbycancel")
+station.busy = false
+return
+end
+end
@@ -3243 +3305,2 @@
-local attempt = beginGroupLoading(participants)
+local attempt = beginGroupLoading(participants, station.level or 1)
+if not attempt then station.busy = false; return end
@@ -3845 +3908 @@
-local function stageArrivingParty(attempt)
+local function stageArrivingParty(attempt, startedAtOverride, expectedSession)
@@ -3849 +3912 @@
-local startedAt = os.clock()
+local startedAt = startedAtOverride or os.clock()
@@ -3859,0 +3923,4 @@
+if group and expectedSession and (group.SessionId ~= expectedSession.SessionId or group.Level ~= expectedSession.Level) then
+attempt:Fail("ARRIVAL_SESSION_CHANGED")
+return "abandon", nil
+end
@@ -3912,0 +3980,13 @@
+local function reservedEntryTarget()
+local startedAt = os.clock()
+local originalDeadline = startedAt + Loading.TimeoutSeconds
+while os.clock() < originalDeadline do
+local group = Routing.SelectArrivalSession(arrivalEntries())
+if group then return group, originalDeadline, startedAt end
+task.wait(.2)
+end
+return nil
+end
@@ -3918,2 +3998,10 @@
-local attempt = beginGroupLoading({})
-local decision, group = stageArrivingParty(attempt)
+local targetSession, originalDeadline, admissionStartedAt = reservedEntryTarget()
+if not targetSession then recoverFailedEntry(nil, "ARRIVAL_LOAD_FAILED", Players:GetPlayers()); return end
+local targetLevel = targetSession.Level
+local attempt = beginGroupLoading({}, targetLevel, function() return not failedReservedEntry end,
+targetLevel ~= 3 and originalDeadline or nil)
+if not attempt then return end
+local decision, group = stageArrivingParty(attempt, targetLevel ~= 3 and admissionStartedAt or nil,
+targetLevel == 3 and targetSession or nil)
```
Complete helper:
```luau
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Warmup = {}
Warmup.TimeoutSeconds = 1200
local REVISION_SHA = "d2eddfce3820a27f01cdd53b93b719ec8bf8d048b9313bc6cdf29610344acc6b"
local started, finished, startedAt, deadline, lastError = false, false, nil, nil, nil
local function readyKit()
local kit = ServerStorage:FindFirstChild("Level6BlenderKit")
return kit and kit:IsA("Folder") and kit:GetAttribute("Ready") == true
and kit:GetAttribute("BlenderSourceSHA256") == REVISION_SHA and kit or nil
end
local function publish(state)
workspace:SetAttribute("Level3KitReady", readyKit() ~= nil)
workspace:SetAttribute("Level3KitState", state)
workspace:SetAttribute("Level3KitError", lastError)
if startedAt then workspace:SetAttribute("Level3KitWarmSeconds", math.round((os.clock()-startedAt)*100)/100) end
end
function Warmup.Start()
assert(not RunService:IsClient(), "Level 3 kit prewarm is server-only")
if started then return end
started, startedAt = true, os.clock()
deadline = startedAt + Warmup.TimeoutSeconds
if readyKit() then finished = true; publish("ready"); return end
publish("warming")
task.spawn(function()
local ok, problem = pcall(function()
local systems = assert(ServerScriptService:FindFirstChild("Level 6 Systems"), "Missing shared Blender systems")
local module = assert(systems:FindFirstChild("Level6BlenderRuntimeBake"), "Missing shared Blender bake")
assert(module:IsA("ModuleScript"), "Wrong shared Blender bake class")
require(module).Ensure()
assert(readyKit(), "Shared Blender bake did not produce the revised public kit")
end)
finished = true
if not ok then
lastError = string.sub(tostring(problem), 1, 500)
publish("failed")
warn("[Level 3 Kit Warmup] " .. lastError)
return
end
lastError = nil
publish("ready")
end)
end
function Warmup.Status()
return {Ready=readyKit() ~= nil, Started=started, Busy=started and not finished,
Deadline=deadline, StartedAt=startedAt, LastError=lastError}
end
function Warmup.Await(allowed)
Warmup.Start()
while true do
if allowed and allowed() ~= true then return false, "ADMISSION_CANCELLED" end
if readyKit() then return true end
if finished then return false, "LEVEL3_KIT_FAILED" end
if os.clock() >= deadline then
lastError = "Revised Blender kit prewarm exceeded its bounded server wait"
publish("timeout")
return false, "LEVEL3_KIT_TIMEOUT"
end
task.wait(.2)
end
end
return Warmup
```
