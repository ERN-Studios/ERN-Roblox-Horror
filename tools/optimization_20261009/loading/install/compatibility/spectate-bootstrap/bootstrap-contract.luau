-- Engine-boundary mocks only. Production helpers are substituted by the Python runner.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks += 1
end
local function signal()
	local records = {}
	local event = {}
	function event:Connect(callback)
		local connection = {Connected = true, Callback = callback}
		function connection:Disconnect() self.Connected = false end
		table.insert(records, connection)
		return connection
	end
	function event:Fire(...)
		for _, connection in ipairs(table.clone(records)) do
			if connection.Connected then connection.Callback(...) end
		end
	end
	function event:Count()
		local total = 0
		for _, connection in ipairs(records) do if connection.Connected then total += 1 end end
		return total
	end
	return event
end
local function character(world, health, withRoot, withHead)
	local model = {Parent = world, Humanoid = {Health = health}}
	function model:FindFirstChildOfClass(class)
		return class == "Humanoid" and self.Humanoid or nil
	end
	function model:FindFirstChild(name)
		return name == "HumanoidRootPart" and self.Root or name == "Head" and self.Head or nil
	end
	function model:WaitForChild(name)
		if name == "Humanoid" then return self.Humanoid end
		return assert(self:FindFirstChild(name), "fixture requested absent child")
	end
	model.Humanoid.Died = signal()
	local function part()
		local item = {Parent = model}
		function item:IsA(class) return class == "BasePart" end
		function item:IsDescendantOf(ancestor) return self.Parent ~= nil and self.Parent.Parent == ancestor end
		return item
	end
	if withRoot ~= false then model.Root = part() end
	if withHead ~= false then model.Head = part() end
	return model
end
local function baseScenario()
	local c = {Now = 0, Roster = {}, Messages = {}, Requests = {}, Tasks = {}, Warnings = {}, inRound = {}}
	c.World = {Attributes = {RoundActive = true, SelectedLevel = 2}, Signals = {}}
	function c.World:GetAttribute(key) return self.Attributes[key] end
	function c.World:GetAttributeChangedSignal(key)
		if not self.Signals[key] then self.Signals[key] = signal() end
		return self.Signals[key]
	end
	c.Players = {PlayerRemoving = signal()}
	function c.Players:GetPlayers() return table.clone(c.Roster) end
	function c.Players:GetPlayerByUserId(id)
		for _, player in ipairs(c.Roster) do
			if player.UserId == id and player.Parent == self then return player end
		end
		return nil
	end
	function c:Player(id, health)
		local player = {UserId = id, Parent = self.Players, Attributes = {InRound = true}, Foci = {}, FocusEvents = {},
			AddCalls = 0, RemoveCalls = 0, Peak = 0, ReplicationFocus = {Own = true}}
		function player:GetAttribute(key) return self.Attributes[key] end
		function player:SetAttribute(key, value) self.Attributes[key] = value end
		function player:AddReplicationFocus(part)
			assert(part:IsA("BasePart") and part:IsDescendantOf(c.World), "focus must be a live server part")
			assert(not self.Foci[part], "focus cannot be installed twice")
			self.Foci[part] = true
			self.AddCalls += 1
			table.insert(self.FocusEvents, {"add", part})
			local total = 0
			for _ in pairs(self.Foci) do total += 1 end
			self.Peak = math.max(self.Peak, total)
		end
		function player:RemoveReplicationFocus(part)
			assert(self.Foci[part], "foreign or already removed focus")
			self.Foci[part] = nil
			self.RemoveCalls += 1
			table.insert(self.FocusEvents, {"remove", part})
		end
		player.Character = character(self.World, health == nil and 100 or health)
		table.insert(self.Roster, player)
		self.inRound[player] = true
		return player
	end
	function c:Foci(player)
		local total = 0
		for _ in pairs(player.Foci) do total += 1 end
		return total
	end
	function c:Leave(player)
		self.Players.PlayerRemoving:Fire(player)
		player.Parent = nil
		self.inRound[player] = nil
	end
	function c:TickTasks()
		for _, thread in ipairs(self.Tasks) do
			if coroutine.status(thread) ~= "dead" then
				local ok, problem = coroutine.resume(thread)
				assert(ok, problem)
			end
		end
	end
	return c
end

local function serverScenario()
 local c = baseScenario()
 local Players, workspace, inRound = c.Players, c.World, c.inRound
 local os = {clock = function() return c.Now end}
 local task = {
  spawn = function(callback) table.insert(c.Tasks, coroutine.create(callback)) end,
  wait = function() coroutine.yield(); return true end,
 }
 local function warn(message) table.insert(c.Warnings, message) end
 local status = {}
 function status:FireClient(player, kind, payload)
  table.insert(c.Messages, {Player = player, Kind = kind, Payload = payload})
 end
local spectateTargets = {}
-- SPECTATE_BOOTSTRAP_SERVER_BEGIN
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
-- PERFORMANCE_STREAMING_20261009: a Scriptable spectator camera follows another
-- body. Keep that body's region streamed with one extra focus; never replace the
-- spectator's default own-character focus. The existing 1 s reconciliation owns
-- character/root changes, death and respawn; no per-target connections accumulate.
local spectateFocus = {Records = {}}
function spectateFocus:Clear(player)
 local record = self.Records[player]
 if not record then return true end
 if record.Part and player.Parent == Players then
  local ok, problem = pcall(function() player:RemoveReplicationFocus(record.Part) end)
  if not ok then
   -- Keep ownership and retry next reconciliation. Never add a second focus
   -- while removal of the first has not been confirmed.
   warn("[SpectateStreaming] remove focus: " .. tostring(problem))
   return false
  end
 end
 self.Records[player] = nil
 return true
end
function spectateFocus:Sync(player, target)
 local record = self.Records[player]
 if record and record.Character ~= player.Character then
  self:Clear(player)
  return false -- a respawn ends the previous camera owner
 end
 local character = target.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 if root and (not root:IsA("BasePart") or not root:IsDescendantOf(workspace)) then root = nil end
 if record and record.Part == root then return true end
 if not self:Clear(player) then return true end
 record = {Character = player.Character}
 self.Records[player] = record
 if root then
  local ok, problem = pcall(function() player:AddReplicationFocus(root) end)
  if ok then
   record.Part = root
  else
   warn("[SpectateStreaming] add focus: " .. tostring(problem))
  end
 end
 return true
end
local function republishSpectatorCounts()
 pruneSpectateCandidateRequests()
 local counts = {}
 for spectator, target in pairs(spectateTargets) do
  if validSpectatePair(spectator, target) and spectateFocus:Sync(spectator, target) then
   counts[target] = (counts[target] or 0) + 1
  else
   spectateTargets[spectator] = nil
   spectateFocus:Clear(spectator)
  end
 end
 for spectator in pairs(spectateFocus.Records) do
  if not spectateTargets[spectator] then spectateFocus:Clear(spectator) end
 end
 for _, subject in ipairs(Players:GetPlayers()) do
  if subject:GetAttribute("SpectatorCount") ~= counts[subject] then
   subject:SetAttribute("SpectatorCount", counts[subject])
  end
 end
end
local function setSpectateTarget(player, targetUserId)
 local target = nil
 if type(targetUserId) == "number" and targetUserId == targetUserId
  and math.abs(targetUserId) < 2^53 and targetUserId % 1 == 0 then
  -- Studio's actual multiplayer clients have negative UserIds. Resolve the
  -- current roster instead of assuming positive production account ids.
  target = Players:GetPlayerByUserId(targetUserId)
 end
 if target and not validSpectatePair(player, target) then target = nil end
 if spectateTargets[player] == target then return end
 spectateTargets[player] = target
 republishSpectatorCounts()
end
local function clearSpectatorCounts()
 table.clear(spectateCandidateRequests)
 if next(spectateTargets) == nil and next(spectateFocus.Records) == nil then return end
 table.clear(spectateTargets)
 republishSpectatorCounts()
end
-- Clear stale reports even when a client stops reporting after its target dies,
-- leaves, escapes, or the spectator respawns. No names are replicated.
task.spawn(function()
 while task.wait(1) do
  if next(spectateTargets) ~= nil or next(spectateFocus.Records) ~= nil or next(spectateCandidateRequests) ~= nil then republishSpectatorCounts() end
 end
end)

-- PlayerRemoving fires before Parent leaves Players: detach owned foci now.
Players.PlayerRemoving:Connect(function(leaving)
 spectateCandidateRequests[leaving] = nil
 for spectator, target in pairs(spectateTargets) do
  if spectator == leaving or target == leaving then
   spectateTargets[spectator] = nil
   spectateFocus:Clear(spectator)
  end
 end
 spectateFocus:Clear(leaving)
 republishSpectatorCounts()
end)


 c.Request, c.Select = requestSpectateCandidates, setSpectateTarget
 c.Reconcile, c.Clear = republishSpectatorCounts, clearSpectatorCounts
 c.Targets, c.Records = spectateTargets, spectateFocus.Records
 function c:LastResponse()
  local message = self.Messages[#self.Messages]
  if not message then return nil end
  assert(message.Kind == "spectatecandidates", "candidate response protocol changed")
  return {Serial = message.Payload.Serial, Ids = message.Payload.UserIds}
 end
 c.RateOwned = function(player) return spectateCandidateRequests[player] ~= nil end
 c:TickTasks() -- prime the unchanged periodic coroutine through its first wait
 return c
end

local function clientScenario()
 local c = baseScenario()
 local player = c:Player(-1, 0)
 c.LocalPlayer = player
 c.Players.LocalPlayer = player
 local Players, workspace = c.Players, c.World
 local task = {
  spawn = function(callback) table.insert(c.Tasks, coroutine.create(callback)) end,
  wait = function() coroutine.yield(); return true end,
 }
 local remote = {OnClientEvent = signal()}
 function remote:FireServer(kind, argument)
  table.insert(c.Requests, {Kind = kind, Argument = argument})
 end
 local spectating, targets, idx, spectated, snapCam = false, {}, 1, nil, true
 local hidden, hiddenParts, hiddenPartsConn = nil, {}, nil
 local lastBeamProfile, lastOn = nil, nil
 local band = {copy = function(target) c.BandTarget = target end}
 local prevButton, nextButton, exitButton, core, spill, beamMount = {}, {}, {}, {}, {}, {}
 local UIDevice = {SetInteractive = function() end}
 local function applySpectateLayout() end
 local function unhide() c.Unhides = (c.Unhides or 0) + 1 end
local reportedTarget = false
local function reportTarget(userId)
	if reportedTarget == userId then return end
	reportedTarget = userId
	remote:FireServer("spectatetarget", userId)
end


local watch -- response handler and cycle controls share the existing owner
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

watch = function(i)
	targets = livingOthers()
	if #targets == 0 then
		spectated = nil
		-- SPECTATE_TARGET_20260914: the one client-local fact every other local
		-- script reads to mirror the watched player's audio and POV-relative UI.
		player:SetAttribute("SpectateTargetUserId", nil)
		reportTarget(nil)
		unhide()
		band.copy(nil, player:GetAttribute("Escaped") == true)
		return
	end
	idx = ((i - 1) % #targets) + 1
	if spectated ~= targets[idx] then unhide(); snapCam = true end -- reveal prev body, snap to new POV
	spectated = targets[idx]
	player:SetAttribute("SpectateTargetUserId", spectated.UserId)
	reportTarget(spectated.UserId)
	band.copy(spectated, player:GetAttribute("Escaped") == true)
end

remote.OnClientEvent:Connect(function(message, payload)
 if message == "spectatecandidates" then receiveSpectateCandidates(payload) end
end)


local function startSpectate()
	if spectating or not (workspace:GetAttribute("RoundActive") or player:GetAttribute("Level6PlaygroundPreview") == true) then return end
	spectating = true
	beginSpectateCandidateSession()
	-- Publish the state. "Spectating" was already being READ by the Level 2
	-- Slidemouth client and (now) by the movement cluster, but nothing had ever
	-- written it, so both checks were dead.
	player:SetAttribute("Spectating", true)
	applySpectateLayout()
	watch(1)
	requestSpectateCandidates()
	applySpectateLayout()
end

local function stopSpectate()
	spectating = false
	endSpectateCandidateSession()
	player:SetAttribute("Spectating", nil)
	player:SetAttribute("SpectateTargetUserId", nil)
	reportTarget(nil)
	spectated = nil
	if band.root then band.attention:Hide(); band.root.Visible = false end
	UIDevice.SetInteractive(prevButton, false)
	UIDevice.SetInteractive(nextButton, false)
	UIDevice.SetInteractive(exitButton, false)
	unhide()
	core.Enabled = false; spill.Enabled = false
	lastBeamProfile, lastOn = nil, nil -- force a fresh write next time spectate resumes
	beamMount.Parent = nil
	local cam = workspace.CurrentCamera
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		if hum then cam.CameraSubject = hum end
	end
end

local function onChar(char)
	stopSpectate() -- fresh body → back to your own view
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(startSpectate)
end


workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if spectating and workspace:GetAttribute("RoundActive") ~= true then stopSpectate() end
end)


-- if the teammate you're watching dies, escapes, or leaves, jump to another
task.spawn(function()
	while true do
		task.wait(1)
		if spectating then
			requestSpectateCandidates()
			-- A missing body is pending streaming, not proof of death. The fresh
			-- server list removes dead targets; local membership/escape still clears promptly.
			if not spectated or not table.find(livingOthers(), spectated) then watch(idx) end
		end
	end
end)

 c.Start, c.Stop, c.Tick = startSpectate, stopSpectate, function() c.Now += 1; c:TickTasks() end
 c.Refresh = c.Tick
 c.Cycle = function(offset) watch(idx + offset) end
 function c:SelectedId() return spectated and spectated.UserId end
 function c:RequestCount()
  local total = 0
  for _, request in ipairs(self.Requests) do if request.Kind == "spectatecandidates" then total += 1 end end
  return total
 end
 function c:LastRequestSerial()
  for i = #self.Requests, 1, -1 do
   if self.Requests[i].Kind == "spectatecandidates" then return self.Requests[i].Argument end
  end
 end
 function c:LastTargetId()
  for i = #self.Requests, 1, -1 do
   if self.Requests[i].Kind == "spectatetarget" then return self.Requests[i].Argument end
  end
 end
 function c:TargetReportCount()
  local total = 0
  for _, request in ipairs(self.Requests) do if request.Kind == "spectatetarget" then total += 1 end end
  return total
 end
 function c:Response(serial, ids)
  remote.OnClientEvent:Fire("spectatecandidates", {Serial = serial, UserIds = ids})
 end
 c.RawResponse = function(payload) return receiveSpectateCandidates(payload) end
 c.Respawn = function()
  player.Character = character(c.World, 100)
  onChar(player.Character)
 end
 c.RoundEnded = function() workspace:GetAttributeChangedSignal("RoundActive"):Fire() end
 c:TickTasks() -- prime the exact production one-second loop through its first wait
 return c
end
do
	local c = serverScenario()
	local spectator = c:Player(-1, 0)
	local alive = c:Player(-2, 100)
	local dead = c:Player(-3, 0)
	local escaped = c:Player(-4, 100); escaped.Attributes.Escaped = true
	local outside = c:Player(-5, 100); c.inRound[outside] = nil
	c.Request(spectator, 1)
	local response = c:LastResponse()
	check(response ~= nil and response.Serial == 1, "valid spectator request returns its correlation serial")
	check(#response.Ids == 1 and response.Ids[1] == alive.UserId, "candidate roster is server-authoritative and excludes self/dead/escaped/nonparticipants")
	check(c:Foci(spectator) == 0, "candidate discovery alone does not create spectator ownership")
	local total = #c.Messages
	c.Request(alive, 1)
	check(#c.Messages == total, "living non-spectator cannot request a candidate roster")
	c.Request(spectator, 2, {999, outside.UserId})
	check(#c.Messages == total, "per-player rate guard rejects immediate repeat")
	c.Now = 0.79; c.Request(spectator, 3)
	check(#c.Messages == total, "rate guard remains closed before 0.8 seconds")
	c.Now = 1; c.Request(spectator, 4, {999, outside.UserId})
	response = c:LastResponse()
	check(#c.Messages == total + 1 and response.Serial == 4, "existing one-second client cadence can refresh candidates")
	check(#response.Ids == 1 and response.Ids[1] == alive.UserId, "forged client candidate IDs cannot change authoritative roster")
	c.Select(spectator, 999)
	check(c:Foci(spectator) == 0, "forged unknown selected ID cannot acquire focus")
	c.Select(spectator, outside.UserId)
	check(c:Foci(spectator) == 0, "selected nonparticipant cannot acquire focus")
	c.Select(spectator, alive.UserId)
	check(c:Foci(spectator) == 1 and spectator.Foci[alive.Character.Root], "valid candidate selection owns one server focus")
	check(alive:GetAttribute("SpectatorCount") == 1, "valid candidate selection retains existing spectator counts")
	local own = spectator.ReplicationFocus
	alive.Character.Humanoid.Health = 0; c.Reconcile()
	check(c:Foci(spectator) == 0 and (alive:GetAttribute("SpectatorCount") or 0) == 0, "target death releases focus and count")
	c.Now = 2; c.Request(spectator, 5)
	check(#c:LastResponse().Ids == 0, "fresh authoritative roster removes stale dead candidate")
	check(spectator.ReplicationFocus == own, "own-character replication focus remains untouched")
end

do
	local c = serverScenario()
	local spectator, sameLive, differentLive, lobby = c:Player(101, 0), c:Player(102, 100), c:Player(103, 100), c:Player(104, 100)
	c.World.Attributes.RoundActive = false
	for _, player in ipairs(c.Roster) do c.inRound[player] = nil end
	for _, player in ipairs({spectator, sameLive, differentLive}) do
		player.Attributes.Level6PlaygroundPreview = true
	end
	spectator.Attributes.Level5VoidRound, sameLive.Attributes.Level5VoidRound = true, true
	differentLive.Attributes.Level5VoidRound = nil
	c.Request(spectator, 1)
	local response = c:LastResponse()
	check(response ~= nil and #response.Ids == 1 and response.Ids[1] == sameLive.UserId, "live-level fallback includes only same active level domain")
	c.Select(spectator, differentLive.UserId)
	check(c:Foci(spectator) == 0, "forged cross-live-level selection cannot acquire focus")
	c.Select(spectator, sameLive.UserId)
	check(c:Foci(spectator) == 1 and spectator.Foci[sameLive.Character.Root], "same-live-level candidate uses existing single-focus owner")
	sameLive.Attributes.InRound = nil; c.Reconcile()
	check(c:Foci(spectator) == 0, "live participant leaving its round releases focus")
	c.Now = 1; c.Request(spectator, 2)
	check(#c:LastResponse().Ids == 0, "live-level roster removes inactive domain participant")
	c.Select(spectator, lobby.UserId)
	check(c:Foci(spectator) == 0, "ordinary lobby player remains outside live-level candidates")
end

do
	local c = serverScenario()
	local spectator, target, replacement = c:Player(10, 0), c:Player(20, 100), c:Player(30, 100)
	for _, invalid in ipairs({0, -1, 1.5, math.huge, 0/0, "1", {}}) do c.Request(spectator, invalid) end
	check(#c.Messages == 0, "malformed request correlation IDs produce no response")
	c.Request(spectator, 1)
	c.Select(spectator, target.UserId)
	c.Select(spectator, replacement.UserId)
	check(c:Foci(spectator) == 1 and spectator.Peak == 1 and spectator.Foci[replacement.Character.Root], "candidate cycling removes old focus before adding replacement")
	check(spectator.FocusEvents[2][1] == "remove" and spectator.FocusEvents[3][1] == "add", "focus replacement order remains exact")
	c:Leave(replacement)
	check(c:Foci(spectator) == 0 and next(c.Targets) == nil, "selected target departure releases stale ownership immediately")
	c.Now = 1; c.Request(spectator, 2)
	check(#c:LastResponse().Ids == 1 and c:LastResponse().Ids[1] == target.UserId, "departed target is absent from refreshed roster")
	c.Select(spectator, target.UserId)
	spectator.Character = character(c.World, 100)
	c.Reconcile()
	check(c:Foci(spectator) == 0 and next(c.Targets) == nil, "spectator respawn releases previous camera ownership")
	local responses = #c.Messages
	c.Now = 2; c.Request(spectator, 3)
	check(#c.Messages == responses, "respawned living spectator cannot reuse stale candidate eligibility")
	spectator.Character.Humanoid.Health = 0; c.Select(spectator, target.UserId)
	c.Clear()
	check(c:Foci(spectator) == 0 and next(c.Targets) == nil and next(c.Records) == nil, "round reset clears count and focus ownership")
	c:Leave(spectator)
	check(c.RateOwned(spectator) == false, "departed spectator cannot retain request-rate ownership")
	check(spectator.Peak == 1, "all lifecycle transitions retain one-focus maximum")
end

do
	local c = serverScenario()
	local first, second, target = c:Player(-100, 0), c:Player(-200, 0), c:Player(-300, 100)
	c.Request(first, 1); c.Request(second, 1)
	check(#c.Messages == 2, "candidate rate limit is independent for each participant")
	c.Select(first, target.UserId); c.Select(second, target.UserId)
	check(target:GetAttribute("SpectatorCount") == 2, "multiple spectators retain aggregate count")
	c:Leave(first)
	check(c:Foci(first) == 0 and target:GetAttribute("SpectatorCount") == 1, "one spectator departure preserves remaining viewer")
	check(not c.RateOwned(first) and c.RateOwned(second), "request-rate cleanup is scoped to departing participant")
	c.Clear()
	check(c:Foci(second) == 0 and (target:GetAttribute("SpectatorCount") or 0) == 0, "round end releases the remaining viewer")
	check(not c.RateOwned(second), "round reset clears request-rate ownership")
end

do
	local c = serverScenario()
	local spectator, survivor = c:Player(201, 0), c:Player(202, 100)
	c.Request(spectator, 1)
	check(c.RateOwned(spectator) and next(c.Targets) == nil, "candidate request can own rate state before target selection")
	c.Clear()
	check(not c.RateOwned(spectator), "empty-target round reset still clears request-rate state")
	c.Request(spectator, 2)
	check(#c.Messages == 2, "fresh round ownership is not delayed by a previous cleared rate record")
	spectator.Character = character(c.World, 100)
	c.Reconcile()
	check(not c.RateOwned(spectator), "periodic reconciliation prunes request-only ownership after respawn")
end
do
	local c = clientScenario()
	local first, second = c:Player(-2, 100), c:Player(-3, 100)
	first.Character, second.Character = nil, nil
	c.Start()
	check(c:RequestCount() == 1, "spectator immediately requests authoritative candidates on start")
	local serial = c:LastRequestSerial()
	c:Response(serial, {first.UserId, second.UserId})
	check(c:SelectedId() == first.UserId and c:LastTargetId() == first.UserId, "far-first candidate is selected and reported without streamed Humanoid/HRP")
	check(first.Character == nil, "bootstrap does not fabricate a client character")
	c.Refresh()
	check(c:SelectedId() == first.UserId and c:LastTargetId() == first.UserId, "missing whole character retains pending chosen target")
	first.Character = character(c.World, 100, false, false)
	c.Refresh()
	check(c:SelectedId() == first.UserId, "partial character missing Head/HRP retains selected target")
	c.Cycle(1)
	check(c:SelectedId() == second.UserId and c:LastTargetId() == second.UserId, "cycling can focus a different pending streamed-out candidate")
	local reports = c:TargetReportCount()
	second.Character = character(c.World, 100)
	c.Refresh()
	check(c:SelectedId() == second.UserId and c:TargetReportCount() == reports, "stream arrival keeps existing target and avoids redundant selection report")
	c.Cycle(1)
	check(c:SelectedId() == first.UserId, "pending roster cycling wraps deterministically")
	local requestsBeforeTick = c:RequestCount()
	c.Tick()
	check(c:RequestCount() == requestsBeforeTick + 1, "existing one-second reconciliation refreshes server candidate roster")
	local secondSerial = c:LastRequestSerial()
	c:Response(secondSerial, {second.UserId})
	check(c:SelectedId() == second.UserId and c:LastTargetId() == second.UserId, "fresh server removal of chosen candidate selects surviving replacement")
	c:Response(serial, {first.UserId})
	check(c:SelectedId() == second.UserId, "out-of-order older response cannot revive removed candidate")
	c.Tick(); c:Response(c:LastRequestSerial(), {})
	check(c:SelectedId() == nil and c:LastTargetId() == nil, "empty server candidate roster clears chosen target and focus report")
end

do
	local c = clientScenario()
	local first, second = c:Player(2, 100), c:Player(3, 100)
	c.Start()
	local oldest = c:LastRequestSerial()
	c.Tick()
	local latest = c:LastRequestSerial()
	check(latest > oldest, "request correlation serial increases at each refresh")
	c:Response(oldest, {first.UserId, second.UserId})
	check(c:SelectedId() == first.UserId, "valid delayed response is accepted even after a newer request was issued")
	c:Response(latest, {second.UserId})
	check(c:SelectedId() == second.UserId, "newer response advances accepted candidate snapshot")
	c:Response(oldest, {first.UserId})
	check(c:SelectedId() == second.UserId, "previously accepted response cannot overwrite a newer snapshot")
	c:Response(latest + 1000, {first.UserId})
	check(c:SelectedId() == second.UserId, "unissued future response cannot acquire selection ownership")
	c:Response(latest, {first.UserId})
	check(c:SelectedId() == second.UserId, "duplicate response correlation cannot replace chosen snapshot")
	local previousSession = latest
	c.Stop()
	check(c:SelectedId() == nil and c:LastTargetId() == nil, "stop clears chosen target and publishes focus release")
	c:Response(previousSession, {first.UserId})
	check(c:SelectedId() == nil, "response received while stopped cannot restore spectator ownership")
	c.Start()
	local nextSession = c:LastRequestSerial()
	check(nextSession > previousSession, "request serial is not reused across sessions")
	c:Response(previousSession, {first.UserId})
	check(c:SelectedId() == nil, "previous-session response cannot populate new spectator session")
	c:Response(nextSession, {second.UserId})
	check(c:SelectedId() == second.UserId, "current-session response establishes fresh target")
	c.Respawn()
	check(c:SelectedId() == nil and c:LastTargetId() == nil, "respawn uses production stop path to release bootstrap target")
	c:Response(nextSession, {first.UserId})
	check(c:SelectedId() == nil, "late response after respawn cannot restore target")
end

do
	local c = clientScenario()
	local first, second = c:Player(12, 100), c:Player(13, 100)
	c.Start(); c:Response(c:LastRequestSerial(), {first.UserId, second.UserId, second.UserId, 999, c.LocalPlayer.UserId})
	check(c:SelectedId() == first.UserId, "valid roster entries remain selectable among absent/duplicate/self IDs")
	first.Character.Humanoid.Health = 0
	c.Refresh()
	check(c:SelectedId() == first.UserId, "stale local dead Humanoid cannot invalidate server-listed living candidate")
	c.Tick(); c:Response(c:LastRequestSerial(), {second.UserId})
	check(c:SelectedId() == second.UserId, "fresh authoritative roster removes a target whose server health changed")
	second.Attributes.Escaped = true
	c.Refresh()
	check(c:SelectedId() == nil and c:LastTargetId() == nil, "escaped candidate cannot retain chosen target")
	first.Character.Humanoid.Health = 100
	second.Attributes.Escaped = nil
	c.Tick(); c:Response(c:LastRequestSerial(), {first.UserId, second.UserId})
	check(c:SelectedId() == first.UserId or c:SelectedId() == second.UserId, "fresh roster can repopulate a formerly empty spectator view")
	if c:SelectedId() ~= first.UserId then c.Cycle(1) end
	check(c:SelectedId() == first.UserId, "normal cycling can choose re-admitted candidate before departure")
	c:Leave(first); c.Refresh()
	check(c:SelectedId() == second.UserId, "removed Player instance cannot retain target ownership")
	c.World.Attributes.RoundActive = false
	c.RoundEnded()
	check(c:SelectedId() == nil and c:LastTargetId() == nil, "round-end stop path releases selected target")
	local requests = c:RequestCount()
	c.Tick()
	check(c:RequestCount() == requests, "one-second loop cannot issue requests after round-end stop")
end
do
	local server, client = serverScenario(), clientScenario()
	local spectator, survivor = server:Player(-1, 0), server:Player(-2, 100)
	local replica = client:Player(-2, 100)
	replica.Character = nil -- the failure boundary: server character exists, client character does not
	local cursor, responseCursor = 1, 1
	local function transmit()
		while cursor <= #client.Requests do
			local request = client.Requests[cursor]; cursor += 1
			if request.Kind == "spectatecandidates" then server.Request(spectator, request.Argument)
			elseif request.Kind == "spectatetarget" then server.Select(spectator, request.Argument)
			else error("unexpected fixture client request") end
		end
		while responseCursor <= #server.Messages do
			local response = server.Messages[responseCursor]; responseCursor += 1
			client:Response(response.Payload.Serial, response.Payload.UserIds)
		end
		while cursor <= #client.Requests do
			local request = client.Requests[cursor]; cursor += 1
			assert(request.Kind == "spectatetarget", "response must only publish the selected target")
			server.Select(spectator, request.Argument)
		end
	end
	client.Start(); transmit()
	check(client:SelectedId() == survivor.UserId and replica.Character == nil, "network bootstrap chooses survivor before any client character replica exists")
	check(server:Foci(spectator) == 1 and spectator.Foci[survivor.Character.Root], "candidate reply and client target report install server focus before client stream-in")
	check(survivor:GetAttribute("SpectatorCount") == 1, "bootstrap selection retains exact spectator count")
	server.Now = 1; client.Tick(); transmit()
	check(client:SelectedId() == survivor.UserId and server:Foci(spectator) == 1, "missing-character reconciliation retains both client choice and server ownership")
	replica.Character = character(client.World, 100)
	server.Now = 2; client.Tick(); transmit()
	check(spectator.AddCalls == 1 and survivor:GetAttribute("SpectatorCount") == 1, "stream arrival does not duplicate focus or count")
	survivor.Character.Humanoid.Health = 0
	server.Now = 3; client.Tick(); transmit()
	check(client:SelectedId() == nil and server:Foci(spectator) == 0, "server death roster propagates target/focus release even with stale healthy client replica")
	check((survivor:GetAttribute("SpectatorCount") or 0) == 0, "target death returns count to zero")
	local nextSurvivor = server:Player(-3, 100)
	local nextReplica = client:Player(-3, 100); nextReplica.Character = nil
	server.Now = 4; client.Tick(); transmit()
	check(client:SelectedId() == nextSurvivor.UserId and spectator.Foci[nextSurvivor.Character.Root], "later authoritative survivor can replace empty pending view")
	client.Stop(); transmit()
	check(server:Foci(spectator) == 0 and next(server.Targets) == nil and next(server.Records) == nil, "client stop report releases server focus and count ownership")
	check(spectator.Peak == 1, "full network trace never owns two added foci")
end

do
	local c = clientScenario()
	local selected, alternative = c:Player(72, 100), c:Player(73, 100)
	c.Start()
	local serial = c:LastRequestSerial()
	for _, malformed in ipairs({false, "response", {}, {Serial = serial}, {Serial = serial, UserIds = false},
		{Serial = serial, UserIds = {alternative.UserId, "forged"}}, {Serial = serial, UserIds = {0/0}},
		{Serial = serial + .5, UserIds = {alternative.UserId}}, {Serial = math.huge, UserIds = {alternative.UserId}}}) do
		check(c.RawResponse(malformed) == false and c:SelectedId() == nil, "malformed candidate payload cannot acquire selection")
	end
	c:Response(serial, {selected.UserId})
	check(c:SelectedId() == selected.UserId, "rejected malformed response does not consume valid correlation serial")
	local reports = c:TargetReportCount()
	c:Response(serial, {alternative.UserId})
	check(c:SelectedId() == selected.UserId and c:TargetReportCount() == reports, "duplicate valid serial cannot emit a replacement target report")
end

do
	local c = clientScenario()
	local same, different, lobby = c:Player(82, 100), c:Player(83, 100), c:Player(84, 100)
	c.LocalPlayer.Attributes.Level6PlaygroundPreview = true
	c.LocalPlayer.Attributes.Level5VoidRound = true
	for _, candidate in ipairs({same, different}) do candidate.Attributes.Level6PlaygroundPreview = true end
	same.Attributes.Level5VoidRound = true
	same.Character = nil
	c.Start(); c:Response(c:LastRequestSerial(), {different.UserId, lobby.UserId, same.UserId})
	check(c:SelectedId() == same.UserId, "client domain filter chooses only same live level without requiring character")
	c.Cycle(1)
	check(c:SelectedId() == same.UserId, "cycle cannot enter cross-level or lobby candidate")
	same.Attributes.Level6PlaygroundPreview = nil; c.Refresh()
	check(c:SelectedId() == nil and c:LastTargetId() == nil, "live-domain attribute departure releases stale selection")
end

print("spectator bootstrap contract checks: " .. checks)
return {checks = checks, realGameplayStreamingPerformancePass = false}
