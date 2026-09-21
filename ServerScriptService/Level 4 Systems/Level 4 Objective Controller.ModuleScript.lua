--!strict
-- Level 4 Objective Controller
--
-- The round, as rules: the briefing, the three signal investigations, the house
-- state machine, the finale at the bus-stop cabinet, and the exit.
--
-- Three properties are load-bearing here, and each of them is a thing the brief
-- says must be true rather than a thing that merely happens to be true:
--
--   1. PROGRESS BELONGS TO THE ROUND, NOT TO A PLAYER. A signal is recorded on
--      the session the moment the server accepts it. Nothing is carried, so
--      there is no clue a death or a disconnect can take out of the world, and
--      re-entry needs no special case.
--   2. EVERY PROMPT IS REVALIDATED SERVER-SIDE. canUseSignal is shaped exactly
--      like Level 1's canUsePrompt and Level 2's canUsePump: living, in-round,
--      not escaped, in range, and touching an object that is still part of
--      THIS round's world.
--   3. A HOUSE STATE CHANGE IS A ROUTING PROBLEM, NEVER A TRAP. Warned is a
--      forewarning with time on it. Dangerous removes the house's protection
--      and invites the Neighbour; it does not lock a door, and it does not
--      damage anybody. The scheduler may never take the last safe house in a
--      zone, so there is always somewhere to go.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Configuration = require(script.Parent:WaitForChild("Level 4 Configuration"))
local TeamObjectives = require(ServerScriptService:WaitForChild("TeamObjectives"))
local NoiseRegistry = require(ServerScriptService:WaitForChild("NoiseRegistry"))

local ObjectiveController = {}

local OBJECTIVES = Configuration.Objectives
local HOUSE = Configuration.HouseStates
local COLORS = Configuration.Colors

local activeSession: any = nil

-- ---------------------------------------------------------------------------
-- Session helpers
-- ---------------------------------------------------------------------------

local function liveSession(session: any): boolean
	local world = session and session.Manifest and session.Manifest.World
	return activeSession == session
		and world ~= nil and world:IsA("Model") and world.Parent ~= nil
		and world:GetAttribute("Level4_Generation") == session.Generation
end

local function validSession(session: any): boolean
	return liveSession(session)
		and workspace:GetAttribute("SelectedLevel") == 4
		and workspace:GetAttribute("RoundActive") == true
end

local function livingCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not character.Parent or not humanoid or humanoid.Health <= 0
		or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root :: BasePart
end

local function validPlayer(player: Player, session: any): boolean
	return validSession(session)
		and player.Parent == Players
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true
end

-- Shaped after Level 3's canUsePrompt. A client can fire a prompt it has no
-- business firing; this is the only thing that decides whether it counts.
local function canUsePrompt(player: Player, session: any, prompt: ProximityPrompt, owner: Instance): boolean
	if not validPlayer(player, session) then return false end
	if not prompt.Enabled or not prompt:IsDescendantOf(session.Manifest.World) then return false end
	if not owner.Parent or not owner:IsDescendantOf(session.Manifest.World) then return false end
	local _, _, root = livingCharacter(player)
	if not root then return false end
	local target = owner:IsA("BasePart") and owner.Position or nil
	if not target then return false end
	return (root.Position - target).Magnitude
		<= prompt.MaxActivationDistance + OBJECTIVES.PromptDistanceAllowance
end

local function publish(session: any, key: string, value: any)
	if not session.State then return end
	session.State:SetAttribute(key, value)
end

local function fire(session: any, payload: any, target: Player?)
	if not liveSession(session) then return end
	payload.Generation = session.Generation
	local event = session.ClientEvent
	if not event then return end
	if target then
		if target.Parent == Players and target:GetAttribute("InRound") == true then
			event:FireClient(target, payload)
		end
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") == true then
			event:FireClient(player, payload)
		end
	end
end

local function alert(session: any, title: string, detail: string, tone: string, seconds: number?)
	fire(session, {Type = "Alert", Title = title, Detail = detail, Tone = tone,
		Duration = seconds or 5})
end

-- ---------------------------------------------------------------------------
-- Signals
-- ---------------------------------------------------------------------------

local function publishSignals(session: any)
	local done = 0
	for index = 1, OBJECTIVES.SignalGoal do
		local record = session.Signals[index]
		local complete = record ~= nil and record.Complete == true
		if complete then done += 1 end
		publish(session, "Level4_Signal" .. index, complete and "LOGGED" or "OPEN")
	end
	session.SignalProgress = done
	publish(session, "Level4_SignalProgress", done)
	workspace:SetAttribute("Level4SignalProgress", done)
end

local function unlockBeacon(session: any)
	if session.BeaconUnlocked then return end
	session.BeaconUnlocked = true
	publish(session, "Level4_BeaconUnlocked", true)
	workspace:SetAttribute("Level4BeaconUnlocked", true)
	local finale = session.Manifest.Finale
	finale.Status.Color = COLORS.SignalWarned
	for _, control in ipairs(finale.Controls) do
		control.Prompt.Enabled = true
	end
	publish(session, "Level4_Phase", "BEACON")
	alert(session, "EXTRACTION BEACON LIVE",
		"Three controls at the bus stop. Set them in order.", "good", 7)
	TeamObjectives.Announce("ZYNTRA", "EXTRACTION BEACON UNLOCKED  //  3/3 SIGNALS", 4)
end

local function completeSignal(session: any, index: number, player: Player)
	local record = session.Signals[index]
	if not record or record.Complete then return end
	record.Complete = true
	record.Prompt.Enabled = false
	record.Clue.Color = COLORS.SignalSafe
	-- The screen/readout stops saying "wrong": the clue part is the whole
	-- feedback, so it has to change state visibly and not only in the HUD.
	for _, gui in ipairs(record.Clue:GetChildren()) do
		if gui:IsA("SurfaceGui") then
			local label = gui:FindFirstChildWhichIsA("TextLabel")
			if label then label.Text = ("LOGGED %02d"):format(index) end
		end
	end
	publishSignals(session)

	TeamObjectives.Announce(player.Name,
		("SIGNAL %02d LOGGED  //  %d/%d"):format(index, session.SignalProgress, OBJECTIVES.SignalGoal), 4)
	fire(session, {Type = "Signal", Index = index, Progress = session.SignalProgress,
		Goal = OBJECTIVES.SignalGoal, Actor = player.Name})

	-- The forgiving first task is silent on purpose: a first-timer must not be
	-- able to summon the Neighbour by doing the tutorial correctly.
	if not record.Forgiving then
		local _, _, root = livingCharacter(player)
		if root then
			NoiseRegistry.Add(root.Position, OBJECTIVES.InvestigationNoiseState, player)
		end
	end

	if session.SignalProgress >= OBJECTIVES.SignalGoal then
		unlockBeacon(session)
	end
end

-- ---------------------------------------------------------------------------
-- Finale and exit
-- ---------------------------------------------------------------------------

local function openExit(session: any)
	if session.ExitOpen then return end
	session.ExitOpen = true
	local finale = session.Manifest.Finale
	finale.Status.Color = COLORS.SignalSafe
	-- The gate slides clear. It never closes again inside a round, so nobody
	-- can be shut out of an exit they were warned about.
	finale.Gate.CFrame = finale.Gate.CFrame * CFrame.new(0, 0, finale.Gate.Size.Z + 1)
	finale.Trigger.CanTouch = true
	publish(session, "Level4_ExitOpen", true)
	publish(session, "Level4_Phase", "EXIT")
	workspace:SetAttribute("Level4ExitOpen", true)
	alert(session, "TRANSIT DOOR OPEN", "Reach the bus stop to extract.", "good", 8)
	TeamObjectives.Announce("ZYNTRA", "TRANSIT DOOR OPEN  //  REACH THE BUS STOP", 4)
end

local function completeControl(session: any, index: number, player: Player)
	if not session.BeaconUnlocked or session.ExitOpen then return end
	-- Strictly in order. One player can walk 01 -> 02 -> 03; a party can stand
	-- at one each. Either way the sequence is the same.
	if index ~= session.ControlProgress + 1 then
		fire(session, {Type = "Alert", Title = "OUT OF SEQUENCE",
			Detail = ("Set control %02d first."):format(session.ControlProgress + 1),
			Tone = "warn", Duration = 4}, player)
		return
	end
	session.ControlProgress = index
	local control = session.Manifest.Finale.Controls[index]
	control.Part.Color = COLORS.SignalSafe
	control.Prompt.Enabled = false
	publish(session, "Level4_CabinetProgress", index)
	TeamObjectives.Announce(player.Name,
		("BEACON CONTROL %02d SET  //  %d/%d"):format(index, index, OBJECTIVES.CabinetControlCount), 4)

	local _, _, root = livingCharacter(player)
	if root then NoiseRegistry.Add(root.Position, OBJECTIVES.InvestigationNoiseState, player) end

	if index < OBJECTIVES.CabinetControlCount then return end

	-- The clear warning. Announced, published with a deadline the HUD can count
	-- down, and only then does the door open.
	local endsAt = workspace:GetServerTimeNow() + OBJECTIVES.ExitWarningSeconds
	publish(session, "Level4_ExitWarningEndsAt", endsAt)
	publish(session, "Level4_Phase", "EXIT_WARNING")
	alert(session, "BEACON RESTORED",
		("Transit door opens in %d seconds. Stand clear of the road.")
			:format(OBJECTIVES.ExitWarningSeconds), "warn", OBJECTIVES.ExitWarningSeconds)
	local token = session.Generation
	task.delay(OBJECTIVES.ExitWarningSeconds, function()
		if liveSession(session) and session.Generation == token then openExit(session) end
	end)
end

local function escapePlayer(session: any, player: Player)
	if not session.ExitOpen or session.Escaping[player] then return end
	if not validPlayer(player, session) then return end
	local trigger = session.Manifest.EscapeTrigger
	if not trigger or not trigger.Parent or not trigger.CanTouch
		or not trigger:IsDescendantOf(session.Manifest.World) then return end
	local character, _, root = livingCharacter(player)
	if not character or not root then return end
	-- A touch is only a wake-up. The server has to see the living root INSIDE
	-- the doorway: only players who actually reached the exit get Escaped.
	local offset = trigger.CFrame:PointToObjectSpace(root.Position)
	local half = trigger.Size * 0.5
	if math.abs(offset.X) > half.X or math.abs(offset.Y) > half.Y
		or math.abs(offset.Z) > half.Z then return end

	session.Escaping[player] = true
	session.EscapeOrdinal += 1
	player:SetAttribute("Escaped", true)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local slots = {
		Vector3.new(-6, 3, -4), Vector3.new(0, 3, -4), Vector3.new(6, 3, -4),
		Vector3.new(-6, 3, 4), Vector3.new(0, 3, 4), Vector3.new(6, 3, 4),
	}
	character:PivotTo(session.Manifest.ExitSafeSpawn.CFrame
		* CFrame.new(slots[((session.EscapeOrdinal - 1) % #slots) + 1]))

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local roundStatus = remotes and remotes:FindFirstChild("RoundStatus")
	if roundStatus and roundStatus:IsA("RemoteEvent") then
		for _, recipient in ipairs(Players:GetPlayers()) do
			if recipient:GetAttribute("InRound") == true then
				roundStatus:FireClient(recipient, "escape", player.Name)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- House states
-- ---------------------------------------------------------------------------

local STATE_COLORS = {
	SAFE = COLORS.SignalSafe,
	WARNED = COLORS.SignalWarned,
	DANGEROUS = COLORS.SignalDangerous,
}

local function setHouseState(session: any, record: any, stateName: string)
	if record.HouseState == stateName then return end
	record.HouseState = stateName
	record.HouseStateSince = os.clock()
	record.Model:SetAttribute("Level4_HouseState", stateName)
	record.PorchSignal.Color = STATE_COLORS[stateName] or COLORS.SignalSafe
	if record.PorchLight then
		record.PorchLight.Color = STATE_COLORS[stateName] or COLORS.SignalSafe
		-- Dangerous is dark: the porch light going out IS the second half of the
		-- warning, and it reads from the far end of the street.
		record.PorchLight.Enabled = stateName ~= "DANGEROUS"
	end

	local unsafe = 0
	for _, other in ipairs(session.Houses) do
		if other.HouseState ~= "SAFE" then unsafe += 1 end
	end
	publish(session, "Level4_UnsafeHouses", unsafe)

	if stateName == "WARNED" then
		fire(session, {Type = "House", LotId = record.Lot.Id, Zone = record.Lot.Zone,
			State = stateName, Cue = HOUSE.WarnCueName, Seconds = HOUSE.WarnSeconds})
		TeamObjectives.Announce("ZYNTRA",
			("HOUSE %s UNSTABLE  //  LEAVE WITHIN %ds"):format(record.Lot.Id, HOUSE.WarnSeconds), 4)
	elseif stateName == "DANGEROUS" then
		fire(session, {Type = "House", LotId = record.Lot.Id, Zone = record.Lot.Zone,
			State = stateName, Cue = HOUSE.DangerCueName})
	end
end

-- The invariant, in one function so it cannot be forgotten at a call site:
-- a house may only be taken if its ZONE keeps at least one safe enterable
-- house afterwards. The intro house is permanently safe and is not eligible,
-- so zone 1 always has a fallback even before this runs.
local function mayTake(session: any, record: any): boolean
	local safeInZone = 0
	for _, other in ipairs(session.Houses) do
		if other.Lot.Zone == record.Lot.Zone and other.HouseState == "SAFE" then
			safeInZone += 1
		end
	end
	return safeInZone >= 2
end

local function evaluateHouses(session: any)
	local now = os.clock()
	local unsafe = 0
	for _, record in ipairs(session.Houses) do
		if record.HouseState == "WARNED" and now - record.HouseStateSince >= HOUSE.WarnSeconds then
			setHouseState(session, record, "DANGEROUS")
		elseif record.HouseState == "DANGEROUS" and now - record.HouseStateSince >= HOUSE.DangerousSeconds then
			setHouseState(session, record, "SAFE")
			record.CooldownUntil = now + HOUSE.CooldownSeconds
		end
		if record.HouseState ~= "SAFE" then unsafe += 1 end
	end
	if unsafe >= HOUSE.MaximumUnsafe then return end
	if now < session.NextHouseEvaluateAt then return end
	session.NextHouseEvaluateAt = now + HOUSE.EvaluateIntervalSeconds

	local candidates = {}
	for _, record in ipairs(session.Houses) do
		if record.HouseState == "SAFE" and now >= (record.CooldownUntil or 0) and mayTake(session, record) then
			table.insert(candidates, record)
		end
	end
	if #candidates == 0 then return end
	setHouseState(session, candidates[session.Random:NextInteger(1, #candidates)], "WARNED")
end

-- The AI asks this before it may attack: a player standing inside a SAFE
-- house's interior is correctly hidden and is never hit.
function ObjectiveController.IsSheltered(player: Player): boolean
	local session = activeSession
	if not session or not liveSession(session) then return false end
	local _, _, root = livingCharacter(player)
	if not root then return false end
	-- session.Shelters, not session.Houses: the intro house is a shelter but is
	-- NOT in the scheduler's eligible set, and reading the wrong list here made
	-- the one permanently safe house in the level the one you could be hit in.
	for _, record in ipairs(session.Shelters) do
		local volume = record.InteriorVolume
		if volume and record.HouseState == "SAFE" then
			local offset = volume.CFrame:PointToObjectSpace(root.Position)
			local half = volume.Size * 0.5
			if math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y
				and math.abs(offset.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function validateManifest(manifest: any, generation: number)
	assert(type(manifest) == "table", "Level 4 objective manifest must be a table")
	assert(manifest.World and manifest.World:IsA("Model") and manifest.World.Parent == workspace,
		"Level 4 objective controller needs the live world")
	assert(manifest.World:GetAttribute("Level4_Generation") == generation,
		"Level 4 objective manifest generation does not match")
	assert(type(manifest.Signals) == "table", "Level 4 manifest carries no signals")
	for index = 1, OBJECTIVES.SignalGoal do
		local signal = manifest.Signals[index]
		assert(signal and signal.Prompt and signal.Prompt:IsA("ProximityPrompt"),
			"Level 4 signal " .. index .. " has no prompt")
		assert(signal.Fixture and signal.Fixture:IsDescendantOf(manifest.World),
			"Level 4 signal " .. index .. " is not part of this world")
		assert(signal.Clue and signal.Clue:IsDescendantOf(manifest.World),
			"Level 4 signal " .. index .. " has no visual clue; no task may require hearing")
	end
	local finale = manifest.Finale
	assert(type(finale) == "table" and #finale.Controls == OBJECTIVES.CabinetControlCount,
		"Level 4 finale needs exactly " .. OBJECTIVES.CabinetControlCount .. " controls")
end

function ObjectiveController.Start(manifest: any, generation: number): any
	ObjectiveController.Stop()
	validateManifest(manifest, generation)

	local remotes = ReplicatedStorage:FindFirstChild(Configuration.RemotesFolderName)
	local session = {
		Manifest = manifest,
		Generation = generation,
		State = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName),
		ClientEvent = remotes and remotes:FindFirstChild(Configuration.ClientEventName),
		Connections = {},
		Signals = {},
		-- Houses: what the state scheduler may promote (enterable, not the intro
		-- house). Shelters: every enterable house, which is what counts as cover.
		Houses = {},
		Shelters = {},
		Escaping = {},
		EscapeOrdinal = 0,
		SignalProgress = 0,
		ControlProgress = 0,
		BeaconUnlocked = false,
		ExitOpen = false,
		NextHouseEvaluateAt = os.clock() + Configuration.HouseStates.EvaluateIntervalSeconds,
		Random = Random.new(manifest.Plan.ResolvedSeed),
		Running = true,
	}
	activeSession = session

	for index, signal in pairs(manifest.Signals) do
		session.Signals[index] = {
			Index = index, Kind = signal.Kind, Forgiving = signal.Forgiving,
			Prompt = signal.Prompt, Fixture = signal.Fixture, Clue = signal.Clue,
			Complete = false,
		}
		table.insert(session.Connections, signal.Prompt.Triggered:Connect(function(player)
			if not canUsePrompt(player, session, signal.Prompt, signal.Fixture) then return end
			completeSignal(session, index, player)
		end))
	end

	-- Enterable houses that are NOT the intro house. The intro house is the
	-- safe area the briefing happens in and it never changes state.
	for _, record in ipairs(manifest.Lots) do
		record.HouseState = "SAFE"
		record.HouseStateSince = os.clock()
		record.Model:SetAttribute("Level4_HouseState", "SAFE")
		if record.Enterable then
			table.insert(session.Shelters, record)
			if record.Lot.Role ~= "Intro" then table.insert(session.Houses, record) end
		end
	end

	for _, control in ipairs(manifest.Finale.Controls) do
		table.insert(session.Connections, control.Prompt.Triggered:Connect(function(player)
			if not canUsePrompt(player, session, control.Prompt, control.Part) then return end
			completeControl(session, control.Index, player)
		end))
	end

	table.insert(session.Connections, manifest.EscapeTrigger.Touched:Connect(function(hit)
		local character = hit and hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then escapePlayer(session, player) end
	end))

	publish(session, "Level4_SignalGoal", OBJECTIVES.SignalGoal)
	publish(session, "Level4_Briefing", OBJECTIVES.BriefingLine)
	publish(session, "Level4_Phase", "INVESTIGATE")
	publishSignals(session)
	workspace:SetAttribute("Level4SignalGoal", OBJECTIVES.SignalGoal)

	-- The briefing. Fired once, at the intro house, in the Zyntra voice, and it
	-- is also the shared 0/3 objective that the existing Objectives feed draws.
	task.delay(1.5, function()
		if not liveSession(session) then return end
		alert(session, "ZYNTRA FIELD BRIEF", OBJECTIVES.BriefingLine, "brief", 10)
		TeamObjectives.Announce("ZYNTRA", OBJECTIVES.BriefingLine, 4)
		TeamObjectives.Announce("ZYNTRA",
			("RESIDENTIAL SIGNALS  //  0/%d"):format(OBJECTIVES.SignalGoal), 4)
	end)

	-- The house scheduler. A timer, not a Heartbeat: it changes state a handful
	-- of times a round and has no business running sixty times a second.
	task.spawn(function()
		while session.Running and liveSession(session) do
			if validSession(session) then
				local ok, problem = pcall(evaluateHouses, session)
				if not ok then warn("[Level 4] house scheduler failed: " .. tostring(problem)) end
			end
			task.wait(1)
		end
	end)

	return session
end

function ObjectiveController.Stop()
	local session = activeSession
	activeSession = nil
	if not session then return end
	session.Running = false
	for _, connection in ipairs(session.Connections) do
		if connection.Connected then connection:Disconnect() end
	end
	table.clear(session.Connections)
	table.clear(session.Signals)
	table.clear(session.Houses)
	table.clear(session.Shelters)
	table.clear(session.Escaping)
end

function ObjectiveController.GetSnapshot(): any
	local session = activeSession
	if not session then return nil end
	local signals = {}
	for index = 1, OBJECTIVES.SignalGoal do
		signals[index] = session.Signals[index] and session.Signals[index].Complete or false
	end
	local houses = {}
	for _, record in ipairs(session.Houses) do
		houses[record.Lot.Id] = record.HouseState
	end
	return {
		Generation = session.Generation,
		Signals = signals,
		SignalProgress = session.SignalProgress,
		ControlProgress = session.ControlProgress,
		BeaconUnlocked = session.BeaconUnlocked,
		ExitOpen = session.ExitOpen,
		Houses = houses,
	}
end

-- Studio-only helpers. They go through exactly the same code paths the prompts
-- do, so a smoke test proves the real rule and not a shortcut around it.
function ObjectiveController.DebugCompleteSignal(player: Player, index: number): boolean
	local session = activeSession
	if not session or not validPlayer(player, session) then return false end
	local record = session.Signals[index]
	if not record or record.Complete then return false end
	completeSignal(session, index, player)
	return true
end

function ObjectiveController.DebugSetHouseState(lotId: string, stateName: string): boolean
	local session = activeSession
	if not session then return false end
	for _, record in ipairs(session.Houses) do
		if record.Lot.Id == lotId then
			setHouseState(session, record, stateName)
			return true
		end
	end
	return false
end

return ObjectiveController
