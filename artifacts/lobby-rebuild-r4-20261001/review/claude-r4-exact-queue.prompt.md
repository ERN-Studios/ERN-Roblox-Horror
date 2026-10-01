Review exact supplied R4 candidate excerpts, read-only. Give at most500words: up to5 concrete bugs/risks with fixes, and a concise verdict on whether code is ready for actual Studio Play (not a claim tests passed). No tools, writes, deployment or approval authority. Roblox campaign remainsMaxLevel3, production private-round routing is unchanged. Revised owned queueIDs101–124 use same existing host/party/privacy/capacity/countdown engine. Levels4/5staticpreviews retainDevAccess.IsAllowed;6functionalpreview retainsseparateIsLevel6PreviewAllowed. OriginalEentrybodiesunchanged. RootbuilderremovesEattrsfromnewR4queuekiosks. Focus frozen character/epoch/zone cohort, cancellation during1260second boundedEnsureWorld, cooldown lock vsoriginalE pendingnonce, returnprompt/world/floor readiness after streams, source API and rollback consistency. IndependentCodexpeer identifiedreturnpromptrecheck/cooldown issues and current supplied version addresses both. Existing6Runtime.Join is idempotent, setsLevel6InRound andstartscontrollers on first member; it may yield. It rejectsInRound/reservedserver/unauthorized/dead/anchored/outside18studexit, doesnotteleport, Leavecleansup onlylastparticipant. Neverregeneratebeneathotherparticipants. Contextinternal helpers should prevent late ghost entry after cancel. No mobile/multiplayer check yet. Existingmodel-only floor/clearance checks use max16studexitdistance, humanoid-adjusted rootheight,4.5stud slotspacing. QueueActive staysduringpreviewbusy;host cancelonlyownedpreviewcontext. Lua candidate syntax compiles. Say if any material issue is definite vs theoretical.

## Exact current QueueBridge candidate
```luau
-- R3 adapter only. GameManager retains all admission, countdown and launch logic.
local Bridge = {}
local NAME = "LobbyReimaginedPreview"
local FIRST_ID, COUNT = 101, 24

function Bridge.IsLobby(model)
	return typeof(model) == "Instance" and model:IsA("Model") and model.Name == NAME
		and model.Parent == workspace and model:GetAttribute("LobbyReimaginedOwned") == true
		and model:GetAttribute("R3QueueRevision") == 3 and model:GetAttribute("Ready") == true
end

function Bridge.Build(model)
	assert(Bridge.IsLobby(model), "R3 queue model is not ready/owned")
	local found, result = {}, {}
	for _, zone in ipairs(model:GetDescendants()) do
		local id = zone:GetAttribute("R3QueueId")
		if id ~= nil then
			assert(zone:IsA("BasePart") and type(id) == "number" and id % 1 == 0
				and id >= FIRST_ID and id < FIRST_ID + COUNT, "Invalid R3 queue zone/id")
			assert(not found[id], "Duplicate R3 queue id")
			local ordinal = id - FIRST_ID
			local level, displayIndex = math.floor(ordinal / 4) + 1, ordinal % 4 + 1
			assert(zone:GetAttribute("LevelNumber") == level
				and zone:GetAttribute("QueueDisplayIndex") == displayIndex, "R3 queue metadata mismatch")
			assert(zone.Anchored and not zone.CanCollide and not zone.CanTouch and not zone.CanQuery,
				"Queue detector must be anchored/nonphysical")
			local radius = zone:GetAttribute("QueueRadius")
			assert(zone:GetAttribute("QueueDetectorShape") == "Circle" and type(radius) == "number"
				and radius == radius and radius > 0 and radius < math.huge
				and radius <= math.min(zone.Size.X, zone.Size.Z) * .5, "Invalid circular detector")
			local bay = zone.Parent
			local floor = bay and bay:FindFirstChild("ChamberFloor")
			local diameter = bay and bay:GetAttribute("CircularBayDiameter")
			assert(bay and bay:IsA("Model") and floor and floor:IsA("BasePart")
				and type(diameter) == "number" and diameter > radius * 2,
				"Queue zone requires direct bay parent, ChamberFloor and diameter")
			local ownerRef = zone:FindFirstChild("QueueRenderOwner")
			local owner = ownerRef and ownerRef:IsA("ObjectValue") and ownerRef.Value
			assert(owner and owner:IsA("Model") and owner:IsDescendantOf(model), "Missing queue render owner")
			local title, sub = owner:FindFirstChild("QueueTitle", true), owner:FindFirstChild("QueueSubtitle", true)
			assert(title and title:IsA("TextLabel") and sub and sub:IsA("TextLabel"), "Missing queue text labels")
			found[id] = {index = id, displayIndex = displayIndex, level = level,
				zone = zone, title = title, sub = sub, color = zone.Color, busy = false,
				revisionOwned = true, lobbyOwner = model, renderOwner = owner, previewOnly = level > 3, previewQueue = level > 3}
		end
	end
	for id = FIRST_ID, FIRST_ID + COUNT - 1 do
		assert(found[id], "Missing R3 queue id " .. id)
		table.insert(result, found[id])
	end
	return result
end

-- Called by existing DEV preview handlers before AND after their streaming yield.
-- This does not replace their allowlist, living-avatar, reach, cooldown or floor checks.
function Bridge.IsPreviewEntry(part, level)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or level < 4 or level > 6 then return false end
	local model = workspace:FindFirstChild(NAME)
	return Bridge.IsLobby(model) and part:IsDescendantOf(model)
		and part:GetAttribute("R3DeveloperPreviewEntry") == level
end

function Bridge.GetPreviewEntries(model, level)
	local result = {}
	if not Bridge.IsLobby(model) then return result end
	for _, part in ipairs(model:GetDescendants()) do
		if Bridge.IsPreviewEntry(part, level) then table.insert(result, part) end
	end
	return result
end

-- R4 uses the existing queue engine for DEV cohorts without changing campaign
-- routing. Only these exact active server controllers can register launchers.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local EXPECTED_CONTROLLERS = {
    [4] = "Level4V4PreviewAccess", [5] = "Level5PreviewAccess", [6] = "Level6PreviewAccess",
}
local launchers = {}
local contexts = setmetatable({}, {__mode = "k"})
local preparations = setmetatable({}, {__mode = "k"})

function Bridge.RegisterPreviewLauncher(level, controller, callbacks)
    assert(not RunService:IsClient(), "Preview launcher registration is server-only")
    local expected = EXPECTED_CONTROLLERS[level]
    assert(expected and controller == game:GetService("ServerScriptService"):FindFirstChild(expected)
        and controller:IsA("Script"), "Wrong active preview controller")
    assert(type(callbacks) == "table" and type(callbacks.allowed) == "function"
        and type(callbacks.ready) == "function" and type(callbacks.launch) == "function",
        "Incomplete preview launcher")
    launchers[level] = {controller = controller, callbacks = callbacks}
end

local function ownedStation(station)
    if type(station) ~= "table" or station.revisionOwned ~= true or station.revisionRetired
        or not Bridge.IsLobby(station.lobbyOwner) then return false end
    local zone = station.zone
    return typeof(zone) == "Instance" and zone:IsA("BasePart")
        and zone:IsDescendantOf(station.lobbyOwner)
        and zone:GetAttribute("R3QueueId") == station.index
        and zone:GetAttribute("LevelNumber") == station.level
        and station.index >= FIRST_ID and station.index < FIRST_ID + COUNT
        and math.floor((station.index - FIRST_ID) / 4) + 1 == station.level
end

local function liveLauncher(station)
    if not ownedStation(station) or station.previewQueue ~= true then return nil end
    local record = launchers[station.level]
    return record and record.controller.Parent == game:GetService("ServerScriptService")
        and record.controller.Name == EXPECTED_CONTROLLERS[station.level] and record.callbacks or nil
end

local function livingRoot(player, character)
    if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players
        or player.Character ~= character or not character:IsDescendantOf(workspace)
        or player:GetAttribute("InRound") == true then return nil end
    local hum = character:FindFirstChildOfClass("Humanoid")
    local root = hum and hum.RootPart
    if not root or root.Anchored or hum.Health <= 0 or hum.SeatPart
        or hum:GetState() == Enum.HumanoidStateType.Dead then return nil end
    return root, hum
end

local function insideZone(station, root)
    local point = station.zone.CFrame:PointToObjectSpace(root.Position)
    local radius = station.zone:GetAttribute("QueueRadius")
    return type(radius) == "number" and radius > 0
        and point.X * point.X + point.Z * point.Z <= radius * radius
        and point.Y > -6 and point.Y < 12
end

function Bridge.AllowsPreview(station, player, context)
    local callbacks = liveLauncher(station)
    if not callbacks or player:GetAttribute("Level6InRound") == true then return false end
    local previous = preparations[station]
    if previous and not previous.active then return false end
    local ok, allowed = pcall(callbacks.allowed, player, context, station)
    return ok and allowed == true
end

function Bridge.ContextOwns(context, player, station)
    local state = contexts[context]
    return state ~= nil and state.active and state.station == station
        and state.characters[player] ~= nil and state.characters[player] == player.Character
end

function Bridge.LockPreviewController(context, nextUse, locks, release)
    local state = contexts[context]
    if not state or not state.active then return false, "INVALID_PREVIEW_CONTEXT" end
    for _, player in ipairs(state.players) do
        if locks[player] or (nextUse[player] or 0) > os.clock()
            or not Bridge.ValidateQueueAdmission(context, player, state.characters[player]) then
            return false, "PREVIEW_PLAYER_BUSY"
        end
    end
    for _, player in ipairs(state.players) do locks[player]=context; nextUse[player]=math.huge end
    table.insert(state.finalizers, function()
        for _, player in ipairs(state.players) do
            if locks[player] == context then locks[player]=nil; release(player) end
        end
    end)
    return true
end

local function closeContext(context, state)
    state.active = false
    for _, finalize in ipairs(state.finalizers) do pcall(finalize) end
    table.clear(state.finalizers)
    contexts[context] = nil
end

function Bridge.ValidateQueueAdmission(context, player, character, requireZone)
    local state = contexts[context]
    if not state or not state.active or os.clock() > state.deadline then return nil end
    local station = state.station
    if not station.busy or station.cancelRequested or station.admissionEpoch ~= state.epoch
        or state.characters[player] ~= character or not ownedStation(station)
        or liveLauncher(station) ~= state.callbacks then return nil end
    local root, humanoid = livingRoot(player, character)
    if not root then return nil end
    -- Once committed, Runtime.Join sets Level6InRound. Admission was already
    -- checked for the whole frozen cohort; the living character is still checked.
    if requireZone ~= false then
        if not Bridge.AllowsPreview(station, player, context) or not insideZone(station, root) then return nil end
    else
        local ok, allowed = pcall(state.callbacks.allowed, player, context, station)
        if not ok or allowed ~= true then return nil end
    end
    return root, humanoid
end

local SLOT_OFFSETS = {
    Vector2.new(0,0), Vector2.new(-4.5,0), Vector2.new(4.5,0),
    Vector2.new(0,4.5), Vector2.new(-4.5,4.5), Vector2.new(4.5,4.5),
    Vector2.new(0,-4.5), Vector2.new(-4.5,-4.5), Vector2.new(4.5,-4.5),
    Vector2.new(0,9), Vector2.new(-4.5,9), Vector2.new(4.5,9),
    Vector2.new(0,-9), Vector2.new(-4.5,-9), Vector2.new(4.5,-9),
}

local function reserveLandings(context, model, exit)
    local state = contexts[context]
    if not state or not model or model.Parent ~= workspace or not exit
        or not exit:IsDescendantOf(model) then return nil, "PREVIEW_WORLD_CHANGED" end
    local look = Vector3.new(exit.CFrame.LookVector.X, 0, exit.CFrame.LookVector.Z)
    local facing = CFrame.lookAt(exit.Position, exit.Position + (if look.Magnitude > .01 then look else Vector3.zAxis))
    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Include
    ray.FilterDescendantsInstances = {model}; ray.RespectCanCollide = true
    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Include
    overlap.FilterDescendantsInstances = {model}; overlap.RespectCanCollide = true
    local chosen, entries = {}, {}
    for _, player in ipairs(state.players) do
        local character = state.characters[player]
        local root, hum = Bridge.ValidateQueueAdmission(context, player, character)
        if not root then return nil, "QUEUE_COHORT_CHANGED" end
        local selected
        for _, offset in ipairs(SLOT_OFFSETS) do
            local at = facing:PointToWorldSpace(Vector3.new(offset.X, 0, offset.Y))
            local hit = workspace:Raycast(at + Vector3.new(0,1.5,0), Vector3.new(0,-14,0), ray)
            if not hit or hit.Normal.Y < .7 or hit.Position.Y > exit.Position.Y - .75 then continue end
            local point = hit.Position + Vector3.new(0, math.max(3.5, hum.HipHeight + root.Size.Y * .5 + .2), 0)
            if (point - exit.Position).Magnitude > 16 then continue end
            local clear = true
            for _, used in ipairs(chosen) do
                if Vector3.new(point.X-used.X,0,point.Z-used.Z).Magnitude < 4.2 then clear = false; break end
            end
            if not clear then continue end
            for _, other in ipairs(Players:GetPlayers()) do
                local otherChar = other.Character
                local otherHum = otherChar and otherChar:FindFirstChildOfClass("Humanoid")
                local otherRoot = otherHum and otherHum.RootPart
                if other ~= player and otherRoot and otherHum.Health > 0
                    and (otherRoot.Position-point).Magnitude < 4.2 then clear = false; break end
            end
            if not clear then continue end
            for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(point), Vector3.new(3.4,5.4,3.4), overlap)) do
                if part.CanCollide then clear = false; break end
            end
            if clear then selected = point; break end
        end
        if not selected then return nil, "NO_SAFE_GROUP_ARRIVAL" end
        table.insert(chosen, selected)
        table.insert(entries, {player=player, character=character, root=root,
            previous=character:GetPivot(), frame=CFrame.lookAt(selected, selected+facing.LookVector)})
    end
    return entries
end

function Bridge.PreparePreviewGroup(context, model, exit, stream)
    local state = contexts[context]
    if not state or type(stream) ~= "function" then return nil, "INVALID_PREVIEW_CONTEXT" end
    local entries, problem = reserveLandings(context, model, exit)
    if not entries then return nil, problem end
    state.destinationModel = model; state.destinationExit = exit
    local completed, succeeded = 0, {}
    for index, entry in ipairs(entries) do
        task.spawn(function()
            local ok, streamed = pcall(stream, entry.player, entry.frame.Position)
            succeeded[index] = ok and streamed == true
            completed += 1
        end)
    end
    local deadline = os.clock() + 30
    while completed < #entries and os.clock() < deadline do
        if not Bridge.ValidateQueueAdmission(context, state.players[1], state.characters[state.players[1]]) then
            return nil, "QUEUE_COHORT_CHANGED"
        end
        task.wait(.1)
    end
    if completed < #entries then return nil, "GROUP_STREAM_TIMEOUT" end
    for index in ipairs(entries) do if not succeeded[index] then return nil, "GROUP_STREAM_FAILED" end end
    local nowModel, nowExit = state.callbacks.ready()
    if nowModel ~= model or nowExit ~= exit then return nil, "PREVIEW_WORLD_CHANGED" end
    -- Recheck floor, collision clearance, living characters and zone membership
    -- after every streaming yield, before any member is moved.
    return reserveLandings(context, model, exit)
end

function Bridge.CommitPreviewGroup(context, entries, commit, rollback)
    local state = contexts[context]
    if not state or type(entries) ~= "table" or #entries ~= #state.players then return false, "INVALID_COHORT" end
    for _, entry in ipairs(entries) do
        if not Bridge.ValidateQueueAdmission(context, entry.player, entry.character) then return false, "QUEUE_COHORT_CHANGED" end
    end
    local nowModel, nowExit = state.callbacks.ready()
    if nowModel ~= state.destinationModel or nowExit ~= state.destinationExit then return false, "PREVIEW_WORLD_CHANGED" end
    state.committing = true
    local moved = {}
    local ok, problem = xpcall(function()
        -- Freeze and validate everyone first, then release the whole cohort.
        for _, entry in ipairs(entries) do
            entry.root.AssemblyLinearVelocity = Vector3.zero
            entry.root.AssemblyAngularVelocity = Vector3.zero
            entry.character:PivotTo(entry.frame)
            table.insert(moved, entry)
        end
        for _, entry in ipairs(entries) do
            if not Bridge.ValidateQueueAdmission(context, entry.player, entry.character, false) then error("QUEUE_COHORT_CHANGED") end
            local joined, reason = commit(entry)
            if joined ~= true then error(tostring(reason or "PREVIEW_JOIN_REJECTED")) end
        end
    end, debug.traceback)
    if not ok then
        for _, entry in ipairs(moved) do
            if rollback then pcall(rollback, entry) end
            if livingRoot(entry.player, entry.character) then
                entry.root.AssemblyLinearVelocity = Vector3.zero
                entry.root.AssemblyAngularVelocity = Vector3.zero
                entry.character:PivotTo(entry.previous)
            end
        end
        return false, tostring(problem)
    end
    return true
end

function Bridge.LaunchPreviewGroup(station, players)
    local callbacks = liveLauncher(station)
    if not callbacks or not station.busy or type(players) ~= "table" or #players < 1 or #players > 6 then
        return false, "PREVIEW_LAUNCHER_UNAVAILABLE"
    end
    -- An abandoned EnsureWorld must finish its own bounded cleanup. Never
    -- task.cancel it or create another waiting job for this same station.
    if preparations[station] then return false, "PREVIEW_PREPARATION_BUSY" end
    local context = {}
    local state = {active=true, station=station, callbacks=callbacks, epoch=station.admissionEpoch,
        deadline=os.clock()+1400, players={}, characters={}, finalizers={}}
    contexts[context] = state
    for _, player in ipairs(players) do
        local character = player.Character
        if state.characters[player] or not character then closeContext(context,state); return false, "INVALID_COHORT" end
        state.characters[player] = character; table.insert(state.players, player)
        if not Bridge.ValidateQueueAdmission(context, player, character) then
            closeContext(context,state); return false, "QUEUE_COHORT_CHANGED"
        end
    end
    preparations[station] = state
    local done, ok, joined, problem = false, false, false, nil
    task.spawn(function()
        ok, joined, problem = pcall(callbacks.launch, context)
        done = true
        if preparations[station] == state then preparations[station] = nil end
    end)
    while not done do
        local valid = true
        for _, player in ipairs(state.players) do
            if not Bridge.ValidateQueueAdmission(context, player, state.characters[player], not state.committing) then
                valid = false; break
            end
        end
        if not valid then
            closeContext(context,state)
            return false, "QUEUE_COHORT_CHANGED"
        end
        task.wait(.1)
    end
    closeContext(context,state)
    return ok and joined == true, if ok then problem else tostring(joined)
end

return Bridge

```

## ServerScriptService.GameManager.Script.diff
```diff
--- ServerScriptService.GameManager.Script.before
+++ ServerScriptService.GameManager.Script.candidate
@@ -645,7 +645,7 @@
 local function setStationDisplay(station, main, secondary, color)
  -- R3 holograms mirror this engine's true host/reset/launch state only.
  if station.revisionOwned and station.renderOwner and station.renderOwner.Parent then
-  station.renderOwner:SetAttribute("QueueActive", station.host ~= nil and not station.busy and not station.revisionRetired)
+  station.renderOwner:SetAttribute("QueueActive", station.host ~= nil and (not station.busy or station.previewQueue == true) and not station.revisionRetired)
  end
  station.title.Text = main
  station.sub.Text = secondary or ""
@@ -1112,9 +1112,20 @@
  return nil
 end
 
+-- R4-owned preview queues share the existing station engine. Production
+-- routing and the original lobby remain untouched.
+local function revisedQueueBridge()
+ local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
+ local module = folder and folder:FindFirstChild("QueueBridge")
+ return module and module:IsA("ModuleScript") and require(module) or nil
+end
+
 local function playerInsideZone(player, station, includeBusy)
  if station.revisionOwned and not (RunService:IsStudio() or DevAccess.IsLevel6PreviewAllowed(player)) then return false end
- if station.level > Routing.MaxLevel and not canAccessLevel(station.level, {player}) then return false end
+ if station.previewQueue then
+  local bridge = revisedQueueBridge()
+  if not bridge or not bridge.AllowsPreview(station, player) then return false end
+ elseif station.level > Routing.MaxLevel and not canAccessLevel(station.level, {player}) then return false end
  if inRound[player] or (station.busy and not includeBusy) then return false end
  local char = player.Character
  local hum = char and char:FindFirstChildOfClass("Humanoid")
@@ -1398,8 +1409,10 @@
  if IS_RESERVED_ROUND_SERVER then return end
  stationIndex = math.floor(tonumber(stationIndex) or 0)
  local station = lobbyStations[stationIndex]
- if not station or station.busy then return end
- if station.host ~= player or not station.awaitingConfig then return end
+ if not station then return end
+ local previewCancel = station.previewQueue == true and requestedPrivacy == "cancel" and station.host == player
+ if station.busy and not previewCancel then return end
+ if station.host ~= player or (not station.awaitingConfig and not previewCancel) then return end
 
  if requestedPrivacy == "cancel" then
   -- The phone close button genuinely leaves the queue instead of only hiding UI.
@@ -3036,6 +3049,24 @@
 -- reserved server. Studio cannot test TeleportService, so it runs the same party
 -- locally as a practical editor-only fallback.
 local function launchStation(station, participants)
+ if station.previewQueue then
+  local bridge = revisedQueueBridge()
+  if not bridge or not bridge.LaunchPreviewGroup then return end
+  station.busy = true
+  setStationDisplay(station, "STARTING DEV PREVIEW", #participants .. "/" .. (station.maxPlayers or MAX_PLAYERS_PER_STATION) .. " PLAYERS", station.color)
+  -- Preview controllers own their stream/entry UI; never announce a campaign
+  -- loadinggame or create a reserved production server for levels4-6.
+  fireGroup(participants, "queueconfigclosed")
+  local ok, joined, problem = pcall(bridge.LaunchPreviewGroup, station, participants)
+  if not ok or joined ~= true then
+   warn("[R4 Preview Queue] " .. tostring(if ok then problem else joined))
+   setStationDisplay(station, "PREVIEW ENTRY FAILED", "STEP OUT AND TRY AGAIN", Color3.fromRGB(255,105,95))
+   fireGroup(participants, "lobbycancel")
+   task.wait(2.5)
+  end
+  station.busy = false
+  return
+ end
  if not canAccessLevel(station.level or 1, participants) then return end
  station.busy = true
  setStationDisplay(station, "STARTING PRIVATE WORLD", #participants .. "/" .. (station.maxPlayers or MAX_PLAYERS_PER_STATION) .. " PLAYERS", station.color)
@@ -3480,7 +3511,7 @@
 end
 
 -- R3 parallel lobby uses the same private queue engine, never a second countdown.
--- Only ready, explicitly owned pads 101-112 enter the registry; 4-6 stay DEV previews.
+-- Ready owned pads101-124 share one engine;4-6 use guarded local DEV launchers.
 if not IS_RESERVED_ROUND_SERVER then
  local r3Models = setmetatable({}, {__mode = "k"})
  local function bindR3(model)
@@ -3496,8 +3527,8 @@
   if not ok then warn("[R3 Queue Bridge] " .. tostring(specs)); return end
   local registered = {}
   for _, station in ipairs(specs) do
-   if not station.previewOnly then
-    if station.level > Routing.MaxLevel or lobbyStations[station.index] then
+   if station.previewQueue or not station.previewOnly then
+    if (not station.previewQueue and station.level > Routing.MaxLevel) or lobbyStations[station.index] then
      warn("[R3 Queue Bridge] conflicting or unavailable queue id " .. station.index); return
     end
     table.insert(registered, station)

```

## ServerScriptService.Level4V4PreviewAccess.Script.diff
```diff
--- ServerScriptService.Level4V4PreviewAccess.Script.before
+++ ServerScriptService.Level4V4PreviewAccess.Script.candidate
@@ -169,6 +169,40 @@
 		hooked[prompt] = true
 		prompt.Triggered:Connect(function(player) callback(player, prompt) end)
 	end
+end
+
+-- R4 queue cohorts use the same existing authorized preview/floor/stream
+-- helpers as the original E entry. Original door prompts are unchanged.
+do
+ local bridge = r3Bridge()
+ if bridge and bridge.RegisterPreviewLauncher then
+  local queueLocks = {}
+  bridge.RegisterPreviewLauncher(4, script, {
+   allowed = function(player, _, station)
+    local lock = queueLocks[player]
+    return (if lock then bridge.ContextOwns(lock, player, station) else (nextUse[player] or 0) <= os.clock())
+     and readyPlayer(player) ~= nil
+   end,
+   ready = function()
+    local model, exit = readyPreview()
+    local prompt = exit and exit:FindFirstChild(RETURN_PROMPT)
+    if not model or not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled
+     or not hasFloor(model, exit) then return nil end
+    return model, exit
+   end,
+   launch = function(context)
+    local locked, reason = bridge.LockPreviewController(context, nextUse, queueLocks, release)
+    if not locked then return false, reason end
+    local model, exit = readyPreview()
+    local returnPrompt = exit and exit:FindFirstChild(RETURN_PROMPT)
+    if not model or not returnPrompt or not returnPrompt:IsA("ProximityPrompt")
+     or not returnPrompt.Enabled or not hasFloor(model, exit) then return false, "PREVIEW_NOT_READY" end
+    local entries, problem = bridge.PreparePreviewGroup(context, model, exit, stream)
+    if not entries then return false, problem end
+    return bridge.CommitPreviewGroup(context, entries, function() return true end)
+   end,
+  })
+ end
 end
 
 local function hookDoor()

```

## ServerScriptService.Level6PreviewAccess.Script.diff
```diff
--- ServerScriptService.Level6PreviewAccess.Script.before
+++ ServerScriptService.Level6PreviewAccess.Script.candidate
@@ -176,6 +176,45 @@
 	release(player)
 	if not ok then warn("[Level6PreviewAccess] " .. tostring(err)) end
 end
+-- R4 queue cohorts keep the existing Level6 allowlist, floor/stream
+-- confirmation and Runtime.Join path. No campaign routing is changed.
+do
+ local bridge = r3Bridge()
+ if bridge and bridge.RegisterPreviewLauncher then
+  local queueLocks = {}
+  bridge.RegisterPreviewLauncher(6, script, {
+   allowed = function(player, _, station)
+    local lock = queueLocks[player]
+    return (if lock then bridge.ContextOwns(lock, player, station) else (nextUse[player] or 0) <= os.clock())
+     and playerReady(player) ~= nil
+   end,
+   ready = function()
+    local model, exit = previewReady()
+    local prompt = exit and exit:FindFirstChild(RETURN)
+    if not model or not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled
+     or not floorAt(model, exit.Position) then return nil end
+    return model, exit
+   end,
+   launch = function(context)
+    local locked, reason = bridge.LockPreviewController(context, nextUse, queueLocks, release)
+    if not locked then return false, reason end
+    local model, exit = Runtime.EnsureWorld()
+    hookExit()
+    if not model or not exit or not floorAt(model, exit.Position) then return false, "PREVIEW_NOT_READY" end
+    local entries, problem = bridge.PreparePreviewGroup(context, model, exit, function(player, position)
+     return streamReady(player, position, MODEL_NAME)
+    end)
+    if not entries then return false, problem end
+    return bridge.CommitPreviewGroup(context, entries, function(entry)
+     local joined, reason = Runtime.Join(entry.player)
+     if joined then transport:FireClient(entry.player, "ArrivalFacing", entry.frame, MODEL_NAME) end
+     return joined, reason
+    end, function(entry) Runtime.Leave(entry.player) end)
+   end,
+  })
+ end
+end
+
 local function hookDoor()
 	local door = lobbyPart("Level6SealedDoor")
 	if door and door:IsA("BasePart") then ensurePrompt(door, ENTER, "ENTER PARTY BACKROOMS", onEnter) end

```

Level5 additions are byte-for-byte equivalent toLevel4registration usingreadyPlayer/readyPreview/hasFloor/stream/RETURN_PROMPT underitsownallowedpredicate/activeScript.
