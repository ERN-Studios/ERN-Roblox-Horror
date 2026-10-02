Read-only focused integration review, no tools. Review ONLY two installed warmup changes plus supplied unchanged ownership/deadline context. Return <=350 words: verdict clear/material-fix/uncertain; concrete severity, function, trigger/effect, minimal fix. Omitted code is not reviewed. Do not disclose private reasoning. Distinguish source inference from observed tests.

Goal: existing 279-chunk Level6 opaque mesh kit may take130s+ (wait cap1200). Public3 queue/campaign/reserved entry MUST prewarm before generic60s Loading.Begin; preserve Level1/2 timing, DEV5/6 access, all routing IDs/rewards and Level2tube. Background shared Ensure owns concurrent original6DEV callers. Cannot cancel engine worker; late completion may serve future admissions but cannot resurrect cancelled parties. Ready checks exact revised SHA. Level3 RoundAdapter requires kit ready and never bakes.

Current root install receipt proves all14 scoped Source/editor CAS matches at2026-10-02T19:59:36Z, correct place131311258779917/universe10559217407. Only two sources reviewed here. Parent started Play separately; no live transport, engine/performance or multiplayer result supplied or claimed.

27 offline virtual-clock scenarios/86semantic checks execute exact helper, fresh Loading+Routing modules and GM fragments:130s cold thenfresh60;1/2 immediate andboot60;host cancel and9invalidations;2coldStudio stations1world;Level1 preempts waiting3;staleentryowner safe;1200timeout+latecompletion;Level2 floor beforewarm+same tube mode;trustedreserved selection+session pin;departed finalcarrier evidence;first provisional packet+snapshot wait until fullcohort. Tests are mocks, not engine evidence.

Unchanged context: Studio roundBusy existing check/set directly before Begin has no yield; when sharedkit ready, Await checks predicate/ready without yielding. Station warm polling owns host+epoch+party character identities and busy flag, but intentionally does not reserve global roundBusy for1200s. PublicCancel exception only warming host cancel. Existing runStation resets after launch returns. Campaign roundBusy already held by prior round; keep its completed floor until warm. Every Begin caller is in diff except Level1 DEV launch, unchanged/nolevel. prepareGroupLoading rechecks canAccessLevel and actual live rigs; marks InRound only afterBegin. Existing reserved setupPlayer appends each trusted arrival to destinationArrivalEvidence even if removed before staging. stageArrivingParty always RememberArrival all recorded evidence, Observe currententries, SelectArrivalSession, async finalcohort MemoryStore read, tracker.Apply subtract only observed departures, Routing.ArrivalDecision; loading-deadline branch admits only Final and full Expected>0 cohort. Those tracker functions themselves unchanged. New target uses SelectArrivalSession (ignores raw Level packet), pinsSessionId+Level throughwarm; reserved1/2 capture original boot deadline before newly-added discovery yields; reserved3 gets fresh60afterwarm. Noearlyfirstpacketadmit.

The input manifest pins all14 installed Source SHA256s; do not claim all14review.
Installed receipt SHA256 and reviewed sources:
8fa6fb902d6e8f1cdf6ac3563913ba269c4d2959520c6f6cfba969a10fc408cb
ServerScriptService.GameManager 8e365508c1e42d9b50e28e8faa3d36ba72eb7b3ba667faf47e92d208262f0ef9
ServerScriptService.Level 3 Kit Warmup 870130d1282ed11df29998e286221a6597cc8d9e40e62baad5f957d020dfc72c

### Exact scoped GM v3 diff (blank/comment-only lines removed)
```luau
--- 
+++ 
@@ -28,6 +28,10 @@
 -- while production ran another.
 local Routing = require(script.Parent:WaitForChild("Round Completion Routing"))
 local Loading = require(script.Parent:WaitForChild("Round Loading Runtime"))
+local Level3KitWarmup = require(script.Parent:WaitForChild("Level 3 Kit Warmup"))
+-- Session-owned Blender meshes warm once in the background; Level 1/2 boot and
+-- round deadlines do not wait for this job.
+Level3KitWarmup.Start()
 -- FRIEND_BOOST_20260916. The module owns the friendship cache and the two lobby
 -- attributes; GameManager only tells it when a party launches and hands it the
 -- round roster at completion. Start() connects PlayerAdded/PlayerRemoving and
@@ -1539,7 +1543,8 @@
  stationIndex = math.floor(tonumber(stationIndex) or 0)
  local station = lobbyStations[stationIndex]
  if not station then return end
- local previewCancel = station.previewQueue == true and requestedPrivacy == "cancel" and station.host == player
+ local previewCancel = (station.previewQueue == true or station.kitWarming == true)
+  and requestedPrivacy == "cancel" and station.host == player
  if station.busy and not previewCancel then return end
  if station.host ~= player or (not station.awaitingConfig and not previewCancel) then return end
@@ -2182,8 +2187,29 @@
  Warn = function(message) warn("[GameManager] entry worker failed: " .. message) end,
 })
-local function beginGroupLoading(group)
+local function beginGroupLoading(group, level, warmAllowed, originalDeadline)
+ if level == 3 then
+  local entryOwner = activeEntry
+  if not Level3KitWarmup.Status().Ready then
+   workspace:SetAttribute("RoundLoadingState", "warming")
+   workspace:SetAttribute("LoadStage", "LEVEL_3_PREPARING_ASSETS")
+   workspace:SetAttribute("RoundLoadingDeadline", nil)
+   fireGroup(group, "loadinggame", 3)
+  end
+  local ready, problem = Level3KitWarmup.Await(function()
+   return activeEntry == entryOwner and (not warmAllowed or warmAllowed() == true)
+  end)
+  if not ready then
+   -- A replaced caller cannot fail or tear down a newer entry.
+   if activeEntry == entryOwner then
+    recoverFailedEntry(nil, problem, IS_RESERVED_ROUND_SERVER and Players:GetPlayers() or group)
+   end
+   return nil
+  end
+ end
  activeEntry = loadingRuntime:Begin(group)
+ -- For reserved Level 1/2, target discovery keeps the original boot deadline.
+ if originalDeadline then activeEntry.Deadline = math.min(activeEntry.Deadline, originalDeadline) end
  workspace:SetAttribute("RoundLoadingState", "loading")
  workspace:SetAttribute("RoundLoadingToken", activeEntry.Token)
  workspace:SetAttribute("RoundLoadingDeadline", workspace:GetServerTimeNow() + activeEntry:Remaining())
@@ -2558,7 +2584,12 @@
 		return
 	end
- local attempt = beginGroupLoading(continuing)
+ local attempt = beginGroupLoading(continuing, nextLevel, function()
+  if not canAccessLevel(nextLevel, livePlayers(continuing)) then return false end
+  for _, player in ipairs(continuing) do if player.Parent == Players then return true end end
+  return false
+ end)
+ if not attempt then return end
  fireGroup(continuing, "loadinggame", nextLevel)
  attempt.WorldWorkerDone = false
  local cleaned = attempt:Run(function()
@@ -3227,6 +3258,37 @@
  end
  if not canAccessLevel(station.level or 1, participants) then return end
  station.busy = true
+ if station.level == 3 then
+  local epoch, host = station.admissionEpoch, station.host
+  local characters = {}
+  for _, player in ipairs(participants) do characters[player] = player.Character end
+  station.kitWarming = true
+  fireGroup(participants, "queueconfigclosed")
+  setStationDisplay(station, "PREPARING LEVEL 3", "STEP OUT TO CANCEL", station.color)
+  local ready, problem = Level3KitWarmup.Await(function()
+   if not station.busy or station.level ~= 3 or station.cancelRequested or station.revisionRetired
+    or station.admissionEpoch ~= epoch or station.host ~= host
+    or (IS_STUDIO and roundBusy) or not station.zone:IsDescendantOf(workspace) then return false end
+   for _, player in ipairs(participants) do
+    local character = player.Character
+    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
+    if player.Parent ~= Players or character ~= characters[player]
+     or not humanoid or humanoid.Health <= 0 or player:GetAttribute("InRound") == true
+     or not playerInsideZone(player, station, true) then return false end
+   end
+   return #participants > 0 and canAccessLevel(3, participants)
+  end)
+  station.kitWarming = nil
+  if not ready then
+   if problem ~= "ADMISSION_CANCELLED" then
+    warn("[GameManager] Level 3 queue prewarm: " .. tostring(problem))
+    setStationDisplay(station, "LEVEL 3 NOT READY", "STEP OUT AND TRY AGAIN", Color3.fromRGB(255,105,95))
+   end
+   fireGroup(participants, "lobbycancel")
+   station.busy = false
+   return
+  end
+ end
  setStationDisplay(station, "STARTING PRIVATE WORLD", #participants .. "/" .. (station.maxPlayers or MAX_PLAYERS_PER_STATION) .. " PLAYERS", station.color)
  fireGroup(participants, "loadinggame", station.level or 1)
@@ -3240,7 +3302,8 @@
   end
   roundBusy = true
-  local attempt = beginGroupLoading(participants)
+  local attempt = beginGroupLoading(participants, station.level or 1)
+  if not attempt then station.busy = false; return end
   clearGlowsticks()
   assignGlowstickSlots(participants)
   -- A round started from the lobby is never a continuation, whatever the last
@@ -3842,11 +3905,11 @@
 -- the round and everybody after them -- a later manual Continue, and every
 -- player the 15-second countdown carried -- landed into roundBusy and was
 -- initialised as a spectator.
-local function stageArrivingParty(attempt)
+local function stageArrivingParty(attempt, startedAtOverride, expectedSession)
  local cohortReads = {}
  local arrivals = Loading.NewArrivalTracker(Routing.SelectArrivalSession)
  local observedArrivals = 0
- local startedAt = os.clock()
+ local startedAt = startedAtOverride or os.clock()
  local firstArrivalAt = nil
  local announced = nil
  while attempt:IsOpen() do
@@ -3857,6 +3920,10 @@
   local entries = arrivalEntries()
   arrivals:Observe(entries)
   local group = Routing.SelectArrivalSession(entries)
+  if group and expectedSession and (group.SessionId ~= expectedSession.SessionId or group.Level ~= expectedSession.Level) then
+   attempt:Fail("ARRIVAL_SESSION_CHANGED")
+   return "abandon", nil
+  end
   if group and not group.Final and group.Deadline then
    local read = cohortReads[group.SessionId]
    if not read then read = {Busy = false, NextAt = 0}; cohortReads[group.SessionId] = read end
@@ -3910,13 +3977,34 @@
  return "abandon", nil
 end
+-- Inspect a server-trusted arrival before starting the entry watchdog. Until
+-- a target is known, preserve the former 60-second boot admission cutoff.
+local function reservedEntryTarget()
+ local startedAt = os.clock()
+ local originalDeadline = startedAt + Loading.TimeoutSeconds
+ while os.clock() < originalDeadline do
+  local group = Routing.SelectArrivalSession(arrivalEntries())
+  if group then return group, originalDeadline, startedAt end
+  task.wait(.2)
+ end
+ return nil
+end
+
 if IS_RESERVED_ROUND_SERVER then
  task.spawn(function()
   -- Hold characters behind the loading screen until the source's result window
   -- has closed and the whole cohort has landed, then generate exactly one
   -- isolated world for that group.
-  local attempt = beginGroupLoading({})
-  local decision, group = stageArrivingParty(attempt)
+  local targetSession, originalDeadline, admissionStartedAt = reservedEntryTarget()
+  if not targetSession then recoverFailedEntry(nil, "ARRIVAL_LOAD_FAILED", Players:GetPlayers()); return end
+  local targetLevel = targetSession.Level
+  local attempt = beginGroupLoading({}, targetLevel, function() return not failedReservedEntry end,
+   targetLevel ~= 3 and originalDeadline or nil)
+  if not attempt then return end
+  -- PlayerAdded evidence remains live throughout prewarm, including members who
+  -- departed before later continuers arrived. The existing tracker owns that math.
+  local decision, group = stageArrivingParty(attempt, targetLevel ~= 3 and admissionStartedAt or nil,
+   targetLevel == 3 and targetSession or nil)
   if decision ~= "admit" or not group then attempt:Fail("ARRIVAL_LOAD_FAILED"); return end
   local participants = {}
```

### Complete new singleton helper
```luau
-- One server-owned prewarm job, shared by every public Level 3 admission.
-- Opaque Blender content is session-owned; never charge its bake to round entry.
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
 -- Ensure itself owns concurrent callers from the original Level 6 DEV preview.
 -- A cancelled round never cancels this shared engine job or starts a second one.
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
  -- Recheck the caller's own cohort/epoch before returning a shared result.
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

### Unchanged failed-entry cleanup ownership excerpts (player reset body omitted)
```luau
recoverFailedEntry = function(attempt, reason, arrivals)
 local group = arrivals or (IS_RESERVED_ROUND_SERVER and Players:GetPlayers() or attempt.Members)
 if IS_RESERVED_ROUND_SERVER then failedReservedEntry = true end
 workspace:SetAttribute("RoundActive", false)
 workspace:SetAttribute("RoundLoadingState", "failed")
 workspace:SetAttribute("LoadStage", "WORLD_ERROR")
 zyntraReentry.OnInvoke = function() return false end
-- omitted existing per-player entrycancel/loadfailed/reset notifications
 task.spawn(function()
  if IS_RESERVED_ROUND_SERVER and not IS_STUDIO then
   returnGroupToLobby(group)
   local settled, stranded = awaitTransferSettlement(Routing.Endpoints.Fallback)
   if not settled then holdCompletedWorld(stranded, Routing.Endpoints.Fallback) end
   return
  end
  while attempt and attempt.WorldWorkerDone == false do task.wait(.1) end
  returnGroupToLobby(group)
  if not attempt or activeEntry == attempt then roundBusy = false end
 end)
end
```

### Unchanged Loading.Begin deadline core
```luau
 function runtime:Begin(members)
  serial += 1
  local attempt = {
   Token = tostring(env.Identity or "loading") .. ":" .. tostring(serial),
   Deadline = env.Now() + Loading.TimeoutSeconds,
   State = "loading", Members = {}, Expected = {},
  }
  attempt:SetMembers(members or {})
  env.Delay(Loading.TimeoutSeconds, function() attempt:IsOpen() end)
  return attempt
 end
```

