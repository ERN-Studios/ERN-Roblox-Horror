-- ZyntraMonetization
-- Server-owned persistence, pass grants, developer product receipts and upgrade actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local BadgeService = game:GetService("BadgeService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")

local PlayerProtection = require(script.Parent:WaitForChild("PlayerProtection"))
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local store = DataStoreService:GetDataStore(Config.DataStoreName)
local supportStore = DataStoreService:GetOrderedDataStore(Config.SupportLeaderboardDataStoreName)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local PERCENT_PER_LEVEL = math.floor(Config.TokenPercentPerLevel * 100 + 0.5)
local PCT = PERCENT_PER_LEVEL .. "%"

-- The accessibility switches, resolved once. The list is the whole contract:
-- every key here is persisted in profile.Settings, published as a player
-- attribute of the same name, carried in the public profile, and is the only
-- key SetAccessibility will accept.
local ACCESSIBILITY_SETTINGS = Config.AccessibilitySettings or {}
local ACCESSIBILITY_BY_KEY = {}
for _, setting in ipairs(ACCESSIBILITY_SETTINGS) do
	ACCESSIBILITY_BY_KEY[setting.Key] = setting
end

local SUPPORT_LEADERBOARD_SIZE = math.clamp(math.floor(tonumber(Config.SupportLeaderboardSize) or 10), 1, 25)
local supportFolder = ReplicatedStorage:FindFirstChild("ZyntraDonationLeaderboard")
if supportFolder and not supportFolder:IsA("Folder") then
	supportFolder:Destroy()
	supportFolder = nil
end
if not supportFolder then
	supportFolder = Instance.new("Folder")
	supportFolder.Name = "ZyntraDonationLeaderboard"
	supportFolder.Parent = ReplicatedStorage
end

local supportStatus = supportFolder:FindFirstChild("Status")
if supportStatus and not supportStatus:IsA("StringValue") then supportStatus:Destroy(); supportStatus = nil end
if not supportStatus then
	supportStatus = Instance.new("StringValue")
	supportStatus.Name = "Status"
	supportStatus.Parent = supportFolder
end
supportStatus.Value = "CONNECTING TO SUPPORT RANKINGS"

local supportRows = {}
for rank = 1, SUPPORT_LEADERBOARD_SIZE do
	local name = string.format("Row%02d", rank)
	local row = supportFolder:FindFirstChild(name)
	if row and not row:IsA("StringValue") then row:Destroy(); row = nil end
	if not row then
		row = Instance.new("StringValue")
		row.Name = name
		row.Parent = supportFolder
	end
	row.Value = rank == 1 and "NO SUPPORT RECORDED YET" or ""
	supportRows[rank] = row
end

local function ensureRemote(className, name)
	local existing = remotes:FindFirstChild(name)
	if existing and existing.ClassName == className then return existing end
	if existing then existing:Destroy() end
	local object = Instance.new(className)
	object.Name = name
	object.Parent = remotes
	return object
end

local getProfileRemote = ensureRemote("RemoteFunction", "ZyntraGetProfile")
local claimLobbyBriefingRemote = ensureRemote("RemoteFunction", "ZyntraClaimLobbyBriefing")
local actionRemote = ensureRemote("RemoteEvent", "ZyntraAction")
local profileChangedRemote = ensureRemote("RemoteEvent", "ZyntraProfileChanged")

local levelCompletedEvent = ServerStorage:FindFirstChild("ZyntraLevelCompleted")
if not levelCompletedEvent then
	levelCompletedEvent = Instance.new("BindableEvent")
	levelCompletedEvent.Name = "ZyntraLevelCompleted"
	levelCompletedEvent.Parent = ServerStorage
end

local sessions = {}
local protectionAttempts = {}
local protectionResponses = {}
local mutationLocks = {}
-- player -> { [action window key] = os.clock() of the last accepted call }.
local actionTimes = {}
local dispatchMuteQueues = {}
local briefingClaims = {}
local pendingDispatchSnapshots = {}
local dispatchSnapshotConnection
local profileLoads = setmetatable({}, { __mode = "k" })
local sessionFinalizers = setmetatable({}, { __mode = "k" })
local activeSessionFinalizers = 0
local serverClosing = false

local DISPATCH_SNAPSHOT_TOPIC = "ZyntraDispatchPreferenceV1"
-- A superseded server gets this long to atomically hand off its final accepted
-- mute target. Afterwards the current lease fences every older claim. This is
-- deliberately elapsed-time based on the current server: no cross-server wall
-- clock participates in preference ordering or decides which input wins.
-- BindToClose waits at most 25 seconds below. Five seconds of margin ensures a
-- legitimate shutdown handoff is never fenced while that finalizer may run.
local DISPATCH_HANDOFF_GRACE_SECONDS = 30
local DISPATCH_RECOVERY_RETRY_SECONDS = 30

local function colorData(color)
	return {
		R = math.floor(math.clamp(color.R, 0, 1) * 255 + 0.5),
		G = math.floor(math.clamp(color.G, 0, 1) * 255 + 0.5),
		B = math.floor(math.clamp(color.B, 0, 1) * 255 + 0.5),
	}
end

local function readColor(value, fallback)
	if type(value) ~= "table" then return fallback end
	return Color3.fromRGB(
		math.clamp(math.floor(tonumber(value.R) or fallback.R * 255), 0, 255),
		math.clamp(math.floor(tonumber(value.G) or fallback.G * 255), 0, 255),
		math.clamp(math.floor(tonumber(value.B) or fallback.B * 255), 0, 255)
	)
end

local MAX_SAFE_SUPPORT = 9007199254740991
local function isSafeSupportAmount(value)
	return type(value) == "number" and value == value and value >= 0
		and value <= MAX_SAFE_SUPPORT and value % 1 == 0
end

local function normalizedSupportAmount(value)
	local amount = tonumber(value)
	if not amount or amount ~= amount or amount < 0 or amount > MAX_SAFE_SUPPORT then return 0 end
	return math.floor(amount)
end

local function recordedSupportRobux(data)
	if not data then return 0 end
	return math.min(MAX_SAFE_SUPPORT,
		normalizedSupportAmount(data.DonationRobux) + normalizedSupportAmount(data.UtilityRobux))
end

-- One bounded operation per inventory, separate from Roblox receipt history.
local function protectionState(data)
	local value = data and data.Protection
	if type(value) ~= "table" or not isSafeSupportAmount(value.Charges)
		or not isSafeSupportAmount(value.Revision) then return nil end
	local operation = value.LastOperation
	if operation ~= nil then
		if type(operation) ~= "table" or type(operation.SessionId) ~= "string"
			or #operation.SessionId == 0 or #operation.SessionId > 128
			or operation.Revision ~= value.Revision or operation.Revision < 1 then return nil end
		if operation.Kind == "Buy" then
			if operation.Status ~= "Bought" then return nil end
		elseif operation.Kind == "Use" then
			if operation.Status ~= "Reserved" and operation.Status ~= "Consumed"
				and operation.Status ~= "Refunded" then return nil end
		else
			return nil
		end
	elseif value.Revision ~= 0 then
		return nil
	end
	return value
end

local function protectionResult(value)
	local state = protectionState({Protection = value})
	local operation = state and state.LastOperation
	if not operation or operation.Status == "Reserved" then return nil end
	return {
		Action = operation.Kind == "Buy" and "BuyProtection" or "UseProtection",
		SessionNonce = operation.SessionId,
		Revision = operation.Revision - 1,
		Status = operation.Status,
	}
end

local function recoverProtectionReservation(data, ownerId)
	-- Called only in the existing atomic load/lease claim. An interrupted use
	-- never resumes gameplay. A still-Reserved operation gets one refund even
	-- if its old server applied an effect but lost the completion response.
	if data.Settings.MuteDispatchSessionId ~= ownerId then return false end
	local state = protectionState(data)
	local operation = state and state.LastOperation
	if not operation or operation.Status ~= "Reserved" or operation.SessionId == ownerId
		or state.Charges >= MAX_SAFE_SUPPORT then return false end
	state.Charges += 1
	operation.Status = "Refunded"
	return true
end

local function newProfile()
	return {
		Version = 4,
		Tokens = RunService:IsStudio() and Config.Studio.StartingTokens or 0,
		StaminaLevel = 0,
		BatteryLevel = 0,
		CompletedLevels = 0,
		-- Which levels have been cleared at least once (string keys so the
		-- DataStore never turns this into a sparse array), and which badges have
		-- already been handed out. The badge set is what makes an award
		-- idempotent without asking Roblox on every clear.
		LevelsCleared = {},
		AwardedBadges = {},
		ReentryCredits = 0,
		Protection = {Charges = 0, Revision = 0},
		DonationRobux = 0,
		UtilityRobux = 0,
		Settings = {
			MuteDispatch = false,
			MuteDispatchInputEpoch = 0,
			MuteDispatchRevision = 0,
			MuteDispatchClosedEpoch = 0,
			MuteDispatchSessionEpoch = 0,
			MuteDispatchSessionId = nil,
			MuteDispatchSessionClaims = {},
			LobbyBriefingPlayed = false,
		},
		Colors = {
			Hazmat = colorData(Config.Colors.HazmatDefault),
			Glowstick = colorData(Config.Colors.GlowstickDefault),
		},
		Grants = {
			Supporter = false,
			AdvancedEquipment = false,
		},
		ReceiptIds = {},
	}
end

local function normalizeProfile(data)
	local existingProfile = type(data) == "table"
	if not existingProfile then data = newProfile() end
	data.Version = 4
	-- Additive inventory: preserve malformed saved state for repair instead of
	-- inventing charges or discarding an unresolved reservation.
	if data.Protection == nil then data.Protection = {Charges = 0, Revision = 0} end
	data.Tokens = math.max(0, math.floor(tonumber(data.Tokens) or 0))
	data.StaminaLevel = math.max(0, math.floor(tonumber(data.StaminaLevel) or 0))
	data.BatteryLevel = math.max(0, math.floor(tonumber(data.BatteryLevel) or 0))
	data.CompletedLevels = math.max(0, math.floor(tonumber(data.CompletedLevels) or 0))
	-- Both sets are rebuilt from a KNOWN key set, so a corrupt or hand-edited
	-- save can neither grow the profile without bound nor claim a badge that
	-- this build does not know about. Numeric level keys from an older write are
	-- accepted once and re-saved as strings.
	local levelsCleared = {}
	local savedLevels = type(data.LevelsCleared) == "table" and data.LevelsCleared or {}
	for level = 1, 3 do
		local levelKey = tostring(level)
		if savedLevels[levelKey] == true or savedLevels[level] == true then
			levelsCleared[levelKey] = true
		end
	end
	data.LevelsCleared = levelsCleared
	local awardedBadges = {}
	local savedBadges = type(data.AwardedBadges) == "table" and data.AwardedBadges or {}
	for badgeKey in pairs(Config.Badges or {}) do
		if savedBadges[badgeKey] == true then awardedBadges[badgeKey] = true end
	end
	data.AwardedBadges = awardedBadges
	data.ReentryCredits = math.max(0, math.floor(tonumber(data.ReentryCredits) or 0))
	-- Keep the two recorded streams separate. Retired SupportRobux and old
	-- utility ReceiptIds are not evidence of an additional, uncounted payment.
	data.DonationRobux = normalizedSupportAmount(data.DonationRobux)
	data.UtilityRobux = normalizedSupportAmount(data.UtilityRobux)
	data.Settings = type(data.Settings) == "table" and data.Settings or {}
	data.Settings.MuteDispatch = data.Settings.MuteDispatch == true
	data.Settings.MuteDispatchInputEpoch = math.max(0,
		math.floor(tonumber(data.Settings.MuteDispatchInputEpoch) or 0))
	data.Settings.MuteDispatchRevision = math.max(0,
		math.floor(tonumber(data.Settings.MuteDispatchRevision) or 0))
	data.Settings.MuteDispatchClosedEpoch = math.max(0,
		math.floor(tonumber(data.Settings.MuteDispatchClosedEpoch) or 0))
	data.Settings.MuteDispatchSessionEpoch = math.max(
		data.Settings.MuteDispatchInputEpoch,
		math.floor(tonumber(data.Settings.MuteDispatchSessionEpoch) or 0)
	)
	local dispatchSessionId = data.Settings.MuteDispatchSessionId
	data.Settings.MuteDispatchSessionId = type(dispatchSessionId) == "string"
		and #dispatchSessionId > 0 and #dispatchSessionId <= 128 and dispatchSessionId or nil
	local rawSessionClaims = type(data.Settings.MuteDispatchSessionClaims) == "table"
		and data.Settings.MuteDispatchSessionClaims or {}
	local sessionClaims = {}
	local seenSessionClaims = {}
	local firstClaimIndex = math.max(1, #rawSessionClaims - 15)
	for index = firstClaimIndex, #rawSessionClaims do
		local record = rawSessionClaims[index]
		local id = type(record) == "table" and record.Id or nil
		local epoch = type(record) == "table" and math.max(0,
			math.floor(tonumber(record.Epoch) or 0)) or 0
		local previousId = type(record) == "table" and record.PreviousId or nil
		previousId = type(previousId) == "string" and #previousId > 0
			and #previousId <= 128 and previousId or nil
		local previousEpoch = type(record) == "table" and math.max(0,
			math.floor(tonumber(record.PreviousEpoch) or 0)) or 0
		if type(id) == "string" and #id > 0 and #id <= 128
			and epoch > 0 and not seenSessionClaims[id] then
			seenSessionClaims[id] = true
			local closed = record.Closed == true
				and epoch <= data.Settings.MuteDispatchClosedEpoch
			sessionClaims[#sessionClaims + 1] = {
				Id = id,
				Epoch = epoch,
				PreviousId = previousId,
				PreviousEpoch = previousEpoch,
				Departed = record.Departed == true or closed,
				Closed = closed,
				Recovered = closed and record.Recovered == true,
			}
		end
	end
	data.Settings.MuteDispatchSessionClaims = sessionClaims
	data.Settings.MuteDispatchSessionEpoch = math.max(
		data.Settings.MuteDispatchSessionEpoch,
		data.Settings.MuteDispatchClosedEpoch
	)
	if data.Settings.LobbyBriefingPlayed == nil then
		-- Anyone with legacy saved data has already logged in before this lifetime
		-- welcome existed; do not replay it once merely because schema v4 deployed.
		data.Settings.LobbyBriefingPlayed = existingProfile
	else
		data.Settings.LobbyBriefingPlayed = data.Settings.LobbyBriefingPlayed == true
	end
	local claimId = data.Settings.LobbyBriefingClaimId
	data.Settings.LobbyBriefingClaimId = data.Settings.LobbyBriefingPlayed == true
		and type(claimId) == "string" and #claimId <= 128 and claimId or nil
	-- Accessibility switches are a fixed, config-driven key set: a hand-edited
	-- save can neither add keys nor push a non-boolean into a player attribute,
	-- and an untouched switch lands on its documented default.
	for _, setting in ipairs(ACCESSIBILITY_SETTINGS) do
		local value = data.Settings[setting.Key]
		if type(value) ~= "boolean" then value = setting.Default == true end
		data.Settings[setting.Key] = value
	end
	data.Colors = type(data.Colors) == "table" and data.Colors or {}
	data.Colors.Hazmat = colorData(readColor(data.Colors.Hazmat, Config.Colors.HazmatDefault))
	data.Colors.Glowstick = colorData(readColor(data.Colors.Glowstick, Config.Colors.GlowstickDefault))
	data.Grants = type(data.Grants) == "table" and data.Grants or {}
	data.Grants.Supporter = data.Grants.Supporter == true
	data.Grants.AdvancedEquipment = data.Grants.AdvancedEquipment == true
	-- Receipt acknowledgement must be permanent. Roblox can retry any unresolved
	-- PurchaseId long after the original purchase; pruning old IDs would allow a
	-- delayed retry to grant the product and donation total a second time.
	-- Keep the established array representation so older live servers remain
	-- compatible during a rolling deploy. Clean malformed/duplicate entries, but
	-- never truncate a valid acknowledged PurchaseId.
	-- Deployment note: restart all servers when this migration first goes live;
	-- builds older than this one still contain the retired 500-receipt cap.
	local receiptIds = {}
	local seenReceiptIds = {}
	if type(data.ReceiptIds) == "table" then
		for key, value in pairs(data.ReceiptIds) do
			local receiptId = type(key) == "number" and value
				or (value == true and key or nil)
			if type(receiptId) == "string" and #receiptId > 0
				and #receiptId <= 128 and not seenReceiptIds[receiptId] then
				seenReceiptIds[receiptId] = true
				table.insert(receiptIds, receiptId)
			end
		end
	end
	data.ReceiptIds = receiptIds
	return data
end

local function isDispatchPredecessorClosed(settings, predecessorEpoch)
	predecessorEpoch = math.max(0, math.floor(tonumber(predecessorEpoch) or 0))
	return math.max(0, math.floor(tonumber(settings.MuteDispatchClosedEpoch) or 0))
		>= predecessorEpoch
end

local function advanceDispatchClosedEpoch(settings)
	local closedEpoch = math.max(0,
		math.floor(tonumber(settings.MuteDispatchClosedEpoch) or 0))
	local advanced = true
	while advanced do
		advanced = false
		for _, record in ipairs(settings.MuteDispatchSessionClaims) do
			local previousEpoch = math.max(0,
				math.floor(tonumber(record.PreviousEpoch) or 0))
			if record.Departed == true and record.Closed ~= true
				and previousEpoch <= closedEpoch then
				record.Closed = true
				closedEpoch = math.max(closedEpoch,
					math.floor(tonumber(record.Epoch) or 0))
				advanced = true
			end
		end
	end
	settings.MuteDispatchClosedEpoch = closedEpoch
	return closedEpoch
end

local function dispatchClaimCanFinalize(settings, sessionId, sessionEpoch)
	for _, record in ipairs(settings.MuteDispatchSessionClaims) do
		if record.Id == sessionId and record.Epoch == sessionEpoch then
			-- Recovery is a permanent fence. A callback that began before the
			-- fence will be re-run by UpdateAsync against this closed record and
			-- may no longer publish its older, previously unknown target.
			return record.Closed ~= true and record.Recovered ~= true
		end
	end
	-- A claim pruned from the bounded history is necessarily older than every
	-- retained lease. Refusing its late target is safer than resurrecting it.
	return false
end

-- Reads one accessibility switch off a profile without assuming it has been
-- normalized yet, so the default is applied in exactly one place.
local function accessibilityValue(data, setting)
	local value = data and data.Settings and data.Settings[setting.Key]
	if type(value) ~= "boolean" then value = setting.Default == true end
	return value
end

-- The switch a player just flipped lives here until its coalesced write lands.
-- Declared this early because EVERY mutation has to consult it: mutate() and
-- mutateIdempotent() replace session.data wholesale with the store's copy, and
-- that copy does not carry the pending toggle -- so an unrelated write (a mute
-- toggle, a level-completion token grant, or the switch's own in-flight write
-- after a second flip) republished the OLD value into the attribute the
-- gameplay readers consume, turning the shake back on for up to a write floor.
local accessibilityQueues = setmetatable({}, { __mode = "k" })

-- Re-assert the pending targets over a profile that was just read back, so the
-- attributes published from it match what the player last asked for. Targets
-- stay in the queue for the session, so once a write has landed this is a no-op.
local function reassertPendingAccessibility(player, data)
	local queue = accessibilityQueues[player]
	if not queue or not data or not data.Settings then return end
	for settingKey, settingValue in pairs(queue.desired) do
		data.Settings[settingKey] = settingValue
	end
end

local function publicProfile(data)
	if not data then return nil end
	local result = {
		Tokens = data.Tokens,
		StaminaLevel = data.StaminaLevel,
		BatteryLevel = data.BatteryLevel,
		StaminaPercent = data.StaminaLevel * PERCENT_PER_LEVEL,
		BatteryPercent = data.BatteryLevel * PERCENT_PER_LEVEL,
		CompletedLevels = data.CompletedLevels,
		-- Carried so campaign progress is observable from a client without
		-- reading the DataStore; nothing in the UI consumes it yet.
		LevelsCleared = data.LevelsCleared,
		ReentryCredits = data.ReentryCredits,
		ProtectionCharges = protectionState(data) and data.Protection.Charges or 0,
		ProtectionRevision = protectionState(data) and data.Protection.Revision or 0,
		ProtectionLastResult = protectionResult(data.Protection),
		DonationRobux = data.DonationRobux,
		UtilityRobux = data.UtilityRobux,
		RecordedSupportRobux = recordedSupportRobux(data),
		MuteDispatch = data.Settings.MuteDispatch,
		LobbyBriefingPlayed = data.Settings.LobbyBriefingPlayed,
		HazmatColor = readColor(data.Colors.Hazmat, Config.Colors.HazmatDefault),
		GlowstickColor = readColor(data.Colors.Glowstick, Config.Colors.GlowstickDefault),
		OwnsSupporter = false,
		OwnsAdvancedEquipment = false,
		OwnsCosmeticEquipment = false,
	}
	for _, setting in ipairs(ACCESSIBILITY_SETTINGS) do
		result[setting.Key] = accessibilityValue(data, setting)
	end
	return result
end

local tagCharacters = {}

local function clearPlayerTags(character)
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	for _, child in ipairs(head:GetChildren()) do
		if child.Name == "ZyntraSupporterTag" or child.Name == "ZyntraDeveloperTag" then
			child:Destroy()
		end
	end
end

local function createPlayerTag(head, name, text, row)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Size = UDim2.fromOffset(180, 28)
	billboard.StudsOffset = Vector3.new(0, 2.7, 0)
	-- Size-relative screen spacing keeps two fixed-pixel tags apart even at
	-- their maximum viewing distance. The existing Supporter anchor stays put.
	billboard.SizeOffset = Vector2.new(0, row * 1.1)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 65
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = Color3.fromRGB(90, 235, 215)
	label.TextStrokeColor3 = Color3.fromRGB(5, 12, 14)
	label.TextStrokeTransparency = 0.25
	label.TextScaled = true
	label.Parent = billboard
end

local function refreshPlayerTags(player, character)
	-- Deferred pass refreshes and old CharacterAdded work must not decorate a
	-- retired character, including after its replacement acquires a late Head.
	if player.Parent ~= Players or not character or player.Character ~= character
		or tagCharacters[player] ~= character then return end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end
	clearPlayerTags(character)
	-- Both tags are lobby badges. Developer identity never grants paid benefits.
	if player:GetAttribute("InRound") == true then return end
	local supporter = player:GetAttribute("ZyntraOwnsSupporter") == true
	if supporter then
		createPlayerTag(head, "ZyntraSupporterTag", "ZYNTRA SUPPORTER", 0)
	end
	if DevAccess.IsAllowed(player) then
		createPlayerTag(head, "ZyntraDeveloperTag", "Developer", if supporter then 1 else 0)
	end
end

local function applyHazmatColor(player)
	local character = player.Character
	if not character or player:GetAttribute("InRound") ~= true then return end
	local ownsAdvanced = player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true
	if not ownsAdvanced then return end
	local color = player:GetAttribute("ZyntraHazmatColor") or Config.Colors.HazmatDefault
	for _, object in ipairs(character:GetChildren()) do
		if object:IsA("MeshPart") then
			local surface = object:FindFirstChildOfClass("SurfaceAppearance")
			if surface then
				surface.Color = color
			end
		end
	end
end

local function applyAttributes(player, data)
	local step = Config.TokenPercentPerLevel
	-- Raw profile numbers (tokens, levels, credits) travel only in the
	-- ZyntraProfileChanged/ZyntraGetProfile payloads; gameplay consumes the two
	-- derived multipliers plus the cosmetic colors below.
	player:SetAttribute("ZyntraStaminaMultiplier", 1 + data.StaminaLevel * step)
	player:SetAttribute("ZyntraBatteryMultiplier", 1 + data.BatteryLevel * step)
	player:SetAttribute("ZyntraHazmatColor", readColor(data.Colors.Hazmat, Config.Colors.HazmatDefault))
	player:SetAttribute("ZyntraGlowstickColor", readColor(data.Colors.Glowstick, Config.Colors.GlowstickDefault))
	player:SetAttribute("ZyntraMuteDispatch", data.Settings.MuteDispatch)
	player:SetAttribute("ZyntraLobbyBriefingPlayed", data.Settings.LobbyBriefingPlayed)
	player:SetAttribute("ZyntraDonationRobux", data.DonationRobux)
	player:SetAttribute("ZyntraUtilityRobux", data.UtilityRobux)
	player:SetAttribute("ZyntraRecordedSupportRobux", recordedSupportRobux(data))
	-- Accessibility switches are published under their own bare names because
	-- that is what the client readers already ask for (ReduceCameraShake,
	-- ReduceFlashing, CaptionsEnabled, DisableCaptions) -- do not prefix them.
	for _, setting in ipairs(ACCESSIBILITY_SETTINGS) do
		player:SetAttribute(setting.Key, accessibilityValue(data, setting))
	end
	if player:GetAttribute("InRound") == true and player:GetAttribute("ZyntraOwnsCosmeticEquipment") == true then
		player:SetAttribute("GlowstickColor", player:GetAttribute("ZyntraGlowstickColor"))
	end
	task.defer(applyHazmatColor, player)
end

local function enrichedPublicProfile(player)
	local session = sessions[player]
	local result = session and publicProfile(session.data) or nil
	if result then
		result.ProtectionSessionNonce = session.dispatchSessionId
		result.ProtectionAvailable = not RunService:IsStudio() and session.persistent == true
			and not session.closing and not serverClosing and session.dispatchLeaseActive == true
			and protectionState(session.data) ~= nil
			and session.data.Protection.Revision < MAX_SAFE_SUPPORT
		local attempt = protectionAttempts[player]
		local operation = protectionState(session.data) and session.data.Protection.LastOperation
		if operation and operation.Status == "Reserved" and not attempt then
			result.ProtectionAvailable = false
		end
		result.ProtectionPending = attempt and table.clone(attempt.Command) or nil
		result.ProtectionLastResponse = protectionResponses[player]
		result.OwnsSupporter = player:GetAttribute("ZyntraOwnsSupporter") == true
		result.OwnsAdvancedEquipment = player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true
		result.OwnsCosmeticEquipment = player:GetAttribute("ZyntraOwnsCosmeticEquipment") == true
	end
	return result
end

local function pushProfile(player, message, tone)
	if not player.Parent then return end
	profileChangedRemote:FireClient(player, enrichedPublicProfile(player), message, tone or "info")
end

local function dispatchSnapshotFromData(userId, data)
	data = normalizeProfile(data)
	return {
		UserId = math.floor(tonumber(userId) or 0),
		SessionId = data.Settings.MuteDispatchSessionId,
		SessionEpoch = data.Settings.MuteDispatchSessionEpoch,
		Muted = data.Settings.MuteDispatch == true,
		InputEpoch = data.Settings.MuteDispatchInputEpoch,
		Revision = data.Settings.MuteDispatchRevision,
		ClosedEpoch = data.Settings.MuteDispatchClosedEpoch,
	}
end

local function validDispatchSnapshot(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.Muted) ~= "boolean" then return nil end
	local userId = math.floor(tonumber(snapshot.UserId) or 0)
	local sessionId = snapshot.SessionId
	local sessionEpoch = math.max(0, math.floor(tonumber(snapshot.SessionEpoch) or 0))
	local inputEpoch = math.max(0, math.floor(tonumber(snapshot.InputEpoch) or 0))
	local revision = math.max(0, math.floor(tonumber(snapshot.Revision) or 0))
	local closedEpoch = math.max(0, math.floor(tonumber(snapshot.ClosedEpoch) or 0))
	if userId <= 0 or sessionEpoch <= 0
		or type(sessionId) ~= "string" or #sessionId == 0 or #sessionId > 128 then return nil end
	return {
		UserId = userId,
		SessionId = sessionId,
		SessionEpoch = sessionEpoch,
		Muted = snapshot.Muted,
		InputEpoch = inputEpoch,
		Revision = revision,
		ClosedEpoch = closedEpoch,
	}
end

local function dispatchVersionIsNewer(leftEpoch, leftRevision, rightEpoch, rightRevision)
	return leftEpoch > rightEpoch or (leftEpoch == rightEpoch and leftRevision > rightRevision)
end

local function applyDispatchSnapshot(snapshot)
	snapshot = validDispatchSnapshot(snapshot)
	if not snapshot then return false end
	local player = Players:GetPlayerByUserId(snapshot.UserId)
	if not player then return false end
	local session = sessions[player]
	if not session then
		local pending = pendingDispatchSnapshots[snapshot.UserId]
		if not pending or snapshot.SessionEpoch > pending.SessionEpoch then
			pendingDispatchSnapshots[snapshot.UserId] = snapshot
		elseif snapshot.SessionEpoch == pending.SessionEpoch then
			if dispatchVersionIsNewer(snapshot.InputEpoch, snapshot.Revision,
				pending.InputEpoch, pending.Revision) then
				pendingDispatchSnapshots[snapshot.UserId] = snapshot
			elseif snapshot.ClosedEpoch > (pending.ClosedEpoch or 0) then
				pending.ClosedEpoch = snapshot.ClosedEpoch
			end
		end
		return false
	end

	-- Serialize local snapshot application with every profile mutation. A
	-- DataStore mutation that started before this message must apply its older
	-- response first; the authoritative handoff snapshot then wins locally.
	while mutationLocks[player] do task.wait() end
	mutationLocks[player] = true
	session = sessions[player]
	if not session or session.closing then
		mutationLocks[player] = nil
		return false
	end
	if session.dispatchSessionId ~= snapshot.SessionId
		or session.dispatchSessionEpoch ~= snapshot.SessionEpoch then
		local newerSession = snapshot.SessionEpoch > (session.dispatchSessionEpoch or 0)
		if newerSession then
			session.dispatchLeaseActive = false
		end
		mutationLocks[player] = nil
		if newerSession then player:SetAttribute("ZyntraDispatchPreferenceLoaded", false) end
		return false
	end

	local changed = false
	if snapshot.ClosedEpoch > (session.dispatchClosedEpoch or 0) then
		session.dispatchClosedEpoch = snapshot.ClosedEpoch
		session.dispatchPredecessorClosed = snapshot.ClosedEpoch
			>= (session.dispatchPredecessorEpoch or 0)
		session.data.Settings.MuteDispatchClosedEpoch = snapshot.ClosedEpoch
		changed = true
	end
	local current = session.data.Settings
	local currentEpoch = math.max(0, math.floor(tonumber(current.MuteDispatchInputEpoch) or 0))
	local currentRevision = math.max(0, math.floor(tonumber(current.MuteDispatchRevision) or 0))
	if dispatchVersionIsNewer(snapshot.InputEpoch, snapshot.Revision,
		currentEpoch, currentRevision) then
		current.MuteDispatch = snapshot.Muted
		current.MuteDispatchInputEpoch = snapshot.InputEpoch
		current.MuteDispatchRevision = snapshot.Revision
		changed = true
	end
	local preferenceReady = session.persistent and session.dispatchLeaseActive
		and session.dispatchPredecessorClosed
	mutationLocks[player] = nil
	-- Publish the authoritative value before opening the readiness barrier. Client
	-- listeners must never observe Loaded=true with the predecessor's stale mute.
	if changed then
		applyAttributes(player, session.data)
		pushProfile(player)
	end
	if preferenceReady then player:SetAttribute("ZyntraDispatchPreferenceLoaded", true) end
	return true
end

local function publishDispatchSnapshot(userId, data)
	if RunService:IsStudio() then return true end
	local snapshot = dispatchSnapshotFromData(userId, data)
	local ok, err = pcall(MessagingService.PublishAsync,
		MessagingService, DISPATCH_SNAPSHOT_TOPIC, snapshot)
	if not ok then warn("[Zyntra] Dispatch snapshot publish failed for", userId, err) end
	return ok
end

if not RunService:IsStudio() then
	task.spawn(function()
		local ok, result = pcall(MessagingService.SubscribeAsync,
			MessagingService, DISPATCH_SNAPSHOT_TOPIC, function(message)
				task.defer(applyDispatchSnapshot, message.Data)
			end)
		if not ok then
			warn("[Zyntra] Dispatch snapshot subscription failed:", result)
		else
			dispatchSnapshotConnection = result
		end
	end)
end

local function acquireMutation(player)
	while mutationLocks[player] do task.wait() end
	mutationLocks[player] = true
end

local function releaseMutation(player)
	mutationLocks[player] = nil
end

local function mutate(player, transform)
	local session = sessions[player]
	if not session or session.closing then return false, "Profile is not loaded" end
	acquireMutation(player)
	session = sessions[player]
	if not session or session.closing then
		releaseMutation(player)
		return false, "Profile is not loaded"
	end

	local changed = false
	local message
	local tone
	local resultData
	local success = true

	if RunService:IsStudio() then
		local current = normalizeProfile(session.data)
		changed, message, tone = transform(current)
		resultData = current
	else
		if not session.persistent then
			releaseMutation(player)
			return false, "DataStore is unavailable; try again shortly"
		end
		-- A transform that returns false REFUSED the action: no token to spend, a
		-- colour that is already saved, a receipt already granted. Returning nil
		-- from the callback CANCELS the update, so a refusal costs a read instead
		-- of a write -- the old code committed one either way, which is what let a
		-- player with zero tokens spend the server's DataStore budget by clicking.
		-- The profile the callback read is still adopted below, so the session copy
		-- ends as fresh as a committed write would have left it. This is only safe
		-- while no transform on this path mutates `current` and then returns false;
		-- keep it that way.
		local observed
		local cancelled = false
		local ok, result = pcall(function()
			return store:UpdateAsync("u_" .. player.UserId, function(current)
				current = normalizeProfile(current)
				changed, message, tone = transform(current)
				observed = current
				cancelled = changed ~= true
				if cancelled then return nil end
				return current
			end)
		end)
		success = ok
		if ok then
			resultData = cancelled and observed or normalizeProfile(result)
		else
			message = tostring(result)
		end
	end

	if success and resultData then
		session.data = resultData
		reassertPendingAccessibility(player, resultData)
		if session.dispatchSessionId
			and resultData.Settings.MuteDispatchSessionId ~= session.dispatchSessionId then
			session.dispatchLeaseActive = false
		end
		applyAttributes(player, resultData)
	end
	releaseMutation(player)
	if success then
		pushProfile(player, message, tone)
		return changed == true, message
	end
	warn("[Zyntra] Profile mutation failed for", player.Name, message)
	pushProfile(player, "Could not save that change. Please try again.", "error")
	return false, message
end

-- Developer token gifts use the same serialized profile write as purchases.
-- RemoteFunction supplies the caller; the UI only chooses a recipient and amount.
do
	local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
	local grantRemote = ensureRemote("RemoteFunction", "ZyntraGrantTokens")
	local MAX_GRANT = 10000
	local COOLDOWN = 3
	local grantStates = setmetatable({}, { __mode = "k" })
	local function result(success, message)
		return { Success = success, Message = message }
	end

	grantRemote.OnServerInvoke = function(issuer, targetUserId, amount)
		if not DevAccess.IsAllowed(issuer) or issuer.Parent ~= Players then
			return result(false, "Developer access is required.")
		end
		if serverClosing then return result(false, "Server is closing. No tokens were given.") end
		local state = grantStates[issuer]
		if state and (state.busy or os.clock() - state.finishedAt < COOLDOWN) then
			return result(false, "Please wait for the previous gift and 3 seconds before giving again.")
		end
		if type(targetUserId) ~= "number" or targetUserId ~= targetUserId
			or targetUserId < 1 or targetUserId > 9007199254740991 or targetUserId % 1 ~= 0 then
			return result(false, "Choose a player in this server.")
		end
		if type(amount) ~= "number" or amount ~= amount or amount < 1
			or amount > MAX_GRANT or amount % 1 ~= 0 then
			return result(false, "Enter a whole number from 1 to 10,000.")
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		if not target or target.Parent ~= Players then
			return result(false, "That player has left this server. Choose another player.")
		end
		local session = sessions[target]
		if not session or session.closing then
			return result(false, "That player's profile is still loading or closing. Try again shortly.")
		end
		if not RunService:IsStudio() and not session.persistent then
			return result(false, "That player's saved data is unavailable. No tokens were given.")
		end
		state = { busy = true, finishedAt = 0 }
		grantStates[issuer] = state
		local changed, reason = mutate(target, function(data)
			-- Recheck after waiting for another profile mutation to finish.
			if serverClosing or issuer.Parent ~= Players or target.Parent ~= Players then
				return false, "Gift cancelled because a player or server is leaving.", "error"
			end
			if data.Tokens ~= data.Tokens or data.Tokens + amount > 9007199254740991 then
				return false, "That player's token balance is too large for this gift.", "error"
			end
			data.Tokens += amount
			return true, "+" .. amount .. " free Zyntra Research Tokens from a developer.", "success"
		end)
		state.busy = false
		state.finishedAt = os.clock()
		if changed then
			local message = "Gave " .. amount .. " Research Tokens to @" .. target.Name .. "."
			if RunService:IsStudio() then message ..= " Studio test only; not saved." end
			print(string.format("[Zyntra] Token gift: issuer=%d target=%d amount=%d studio=%s",
				issuer.UserId, target.UserId, amount, tostring(RunService:IsStudio())))
			return result(true, message)
		else
			-- A failed UpdateAsync response may follow a committed write. Never
			-- automatically replay a currency delta or promise it was not saved.
			warn("[Zyntra] Token gift unconfirmed:", issuer.UserId, target.UserId, reason)
			return result(false, "Gift was not confirmed. Have the recipient rejoin and check their balance before repeating.")
		end
	end
end

local supportNameCache = {}
local supportRefreshRunning = false
local pendingSupportSync = {}
local supportSyncWorkers = {}

local function supportPlayerName(userId)
	local cached = supportNameCache[userId]
	if cached then return cached end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		cached = online.Name
		supportNameCache[userId] = cached
		return cached
	end
	local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if ok and type(result) == "string" and #result > 0 then
		supportNameCache[userId] = result
		return result
	end
	-- Keep the temporary fallback out of the cache so the next board refresh can
	-- recover automatically after a throttled or transient name-service failure.
	return "USER " .. tostring(userId)
end

local function publishSupportRows(entries)
	for rank = 1, SUPPORT_LEADERBOARD_SIZE do
		local entry = entries[rank]
		if entry then
			local name = string.upper(supportPlayerName(entry.UserId))
			supportRows[rank].Value = string.format("%02d   %s   •   %d R$", rank, name, entry.Value)
		else
			supportRows[rank].Value = rank == 1 and "NO SUPPORT RECORDED YET" or ""
		end
	end
	-- Keep the existing v2 cache so absent donors retain their rows. Only newly
	-- acknowledged utility receipts extend its totals; history is not backfilled.
	supportStatus.Value = "DONATIONS + RECORDED TOKEN / RE-ENTRY PURCHASES"
end

local function studioSupportEntries()
	local entries = {}
	for player, session in pairs(sessions) do
		local value = recordedSupportRobux(session.data)
		if player.Parent and value > 0 then
			entries[#entries + 1] = { UserId = player.UserId, Value = value }
		end
	end
	table.sort(entries, function(a, b)
		if a.Value == b.Value then return a.UserId < b.UserId end
		return a.Value > b.Value
	end)
	return entries
end

local function refreshSupportLeaderboard()
	if supportRefreshRunning then return end
	supportRefreshRunning = true
	local entries = {}
	local success = true
	local failure
	if RunService:IsStudio() then
		entries = studioSupportEntries()
	else
		local ok, result = pcall(function()
			return supportStore:GetSortedAsync(false, SUPPORT_LEADERBOARD_SIZE):GetCurrentPage()
		end)
		if ok then
			for _, record in ipairs(result) do
				local userId = tonumber(tostring(record.key):match("^u_(%d+)$"))
				local value = normalizedSupportAmount(record.value)
				if userId and value > 0 then
					entries[#entries + 1] = { UserId = userId, Value = value }
				end
			end
		else
			success = false
			failure = result
		end
	end
	if success then
		publishSupportRows(entries)
	else
		warn("[Zyntra] Support leaderboard refresh failed:", failure)
		supportStatus.Value = "SUPPORT RANKINGS TEMPORARILY UNAVAILABLE"
	end
	supportRefreshRunning = false
end

local function syncSupportTotal(userId, total)
	total = normalizedSupportAmount(total)
	if RunService:IsStudio() or total <= 0 then return true end
	local ok, err = pcall(function()
		supportStore:UpdateAsync("u_" .. tostring(userId), function(current)
			return math.max(normalizedSupportAmount(current), total)
		end)
	end)
	if not ok then warn("[Zyntra] Support leaderboard sync failed for", userId, err) end
	return ok
end

-- Outer retries are safe for target states or durable operation identities checked
-- before its delta (the protection item below). Unkeyed currency/reward deltas
-- stay on mutate(): an errored response may already have committed.
local IDEMPOTENT_RETRY_DELAYS = {0, 0.35, 0.80}
local function mutateIdempotent(player, transform, suppressPush)
	local session = sessions[player]
	if not session or session.closing then return false, false, "Profile is not loaded" end
	acquireMutation(player)
	session = sessions[player]
	if not session or session.closing then
		releaseMutation(player)
		return false, false, "Profile is not loaded"
	end

	local success = false
	local changed = false
	local message
	local tone
	local resultData
	if RunService:IsStudio() then
		local current = normalizeProfile(session.data)
		changed, message, tone = transform(current)
		resultData = current
		success = true
	elseif session.persistent then
		for _, delaySeconds in ipairs(IDEMPOTENT_RETRY_DELAYS) do
			if delaySeconds > 0 then task.wait(delaySeconds) end
			if not player.Parent or sessions[player] ~= session then break end
			local attemptChanged = false
			local attemptMessage
			local attemptTone
			local observed
			local cancelled = false
			local ok, result = pcall(function()
				return store:UpdateAsync("u_" .. player.UserId, function(current)
					current = normalizeProfile(current)
					attemptChanged, attemptMessage, attemptTone = transform(current)
					observed = current
					-- Same no-op rule as mutate(): a target-state transform that
					-- reports no change (already claimed, already awarded, a newer
					-- session owns the value) cancels its update instead of
					-- committing a write that changes nothing.
					cancelled = attemptChanged ~= true
					if cancelled then return nil end
					return current
				end)
			end)
			if ok then
				success = true
				changed = attemptChanged == true
				message = attemptMessage
				tone = attemptTone
				resultData = cancelled and observed or normalizeProfile(result)
				break
			end
			message = tostring(result)
		end
	else
		message = "DataStore is unavailable; try again shortly"
	end

	if success and resultData and sessions[player] == session then
		session.data = resultData
		reassertPendingAccessibility(player, resultData)
		if session.dispatchSessionId
			and resultData.Settings.MuteDispatchSessionId ~= session.dispatchSessionId then
			session.dispatchLeaseActive = false
		end
		applyAttributes(player, resultData)
	end
	releaseMutation(player)
	if success then
		if not suppressPush then pushProfile(player, message, tone) end
		return true, changed, message
	end
	warn("[Zyntra] Idempotent profile mutation failed for", player.Name, message)
	if not suppressPush then
		pushProfile(player, "Could not save that change. Please try again.", "error")
	end
	return false, false, message
end

local function sameProtectionCommand(left, right)
	return left and right and left.Action == right.Action
		and left.SessionNonce == right.SessionNonce and left.Revision == right.Revision
		and left.RequestNonce == right.RequestNonce
end

local function protectionOperationMatches(operation, command)
	return operation and operation.SessionId == command.SessionNonce
		and operation.Revision == command.Revision + 1
		and operation.Kind == (command.Action == "BuyProtection" and "Buy" or "Use")
end

local function protectionResponse(player, command, status, reason)
	local response = table.clone(command)
	response.Status = status
	response.Reason = reason
	protectionResponses[player] = response
	local refusals = {
		NeedFiveTokens = "You need 5 Research Tokens.",
		NoCharges = "Buy an Entity Shield charge in Upgrades first.",
		AlreadyActive = "Entity Shield is already active.",
		RetryLater = "Please wait a moment and try again.",
		AnotherActionPending = "Finish your pending Entity Shield action first.",
		StaleRevision = "Your inventory changed. Please try again.",
	}
	local messages = {
		Bought = "Entity Shield purchased: one charge.",
		Consumed = "Entity Shield charge used.",
		Refunded = "Entity Shield could not start. Your charge was returned.",
		Pending = "Confirming your Entity Shield action. Retry the same request.",
		Rejected = refusals[reason] or "Entity Shield is unavailable right now. No charge was used.",
	}
	pushProfile(player, messages[status], status == "Rejected" and "error" or "info")
end

local function protectionOwnsLease(player, session, data)
	return player.Parent == Players and sessions[player] == session and not session.closing
		and not serverClosing and session.persistent == true and session.dispatchLeaseActive == true
		and data.Settings.MuteDispatchSessionId == session.dispatchSessionId
		and data.Settings.MuteDispatchSessionEpoch == session.dispatchSessionEpoch
end

local function handleProtectionAction(player, action, payload)
	-- A malformed command cannot be correlated and never reaches persistence.
	if type(payload) ~= "table" or type(payload.SessionNonce) ~= "string"
		or #payload.SessionNonce == 0 or #payload.SessionNonce > 128
		or not isSafeSupportAmount(payload.Revision) or payload.Revision >= MAX_SAFE_SUPPORT then return end
	if payload.RequestNonce ~= nil and (type(payload.RequestNonce) ~= "string"
		or #payload.RequestNonce == 0 or #payload.RequestNonce > 64) then return end
	-- RequestNonce correlates UI intentions after a definitive refusal. It is
	-- deliberately absent from the durable operation ID and cannot bypass dedupe.
	local command = {
		Action = action, SessionNonce = payload.SessionNonce, Revision = payload.Revision,
		RequestNonce = payload.RequestNonce,
	}
	local session = sessions[player]
	local attempt = protectionAttempts[player]
	if attempt and not sameProtectionCommand(attempt.Command, command) then
		protectionResponse(player, command, "Rejected", "AnotherActionPending")
		return
	end
	if attempt and attempt.Running then
		protectionResponse(player, command, "Pending", "Processing")
		return
	end
	if not session or RunService:IsStudio() or not protectionOwnsLease(player, session, session.data)
		or command.SessionNonce ~= session.dispatchSessionId then
		protectionResponse(player, command, attempt and "Pending" or "Rejected", "ProfileUnavailable")
		return
	end
	local state = protectionState(session.data)
	if not state then
		protectionResponse(player, command, attempt and "Pending" or "Rejected", "InventoryUnavailable")
		return
	end
	local operation = state.LastOperation
	if protectionOperationMatches(operation, command) and operation.Status ~= "Reserved" then
		protectionAttempts[player] = nil
		protectionResponse(player, command, operation.Status)
		return
	end
	local times = actionTimes[player] or {}
	actionTimes[player] = times
	if os.clock() - (times.ProtectionItem or -math.huge) < 1 then
		protectionResponse(player, command, attempt and "Pending" or "Rejected", "RetryLater")
		return
	end
	times.ProtectionItem = os.clock()
	if not attempt then
		local reason
		if command.Revision ~= state.Revision then reason = "StaleRevision"
		elseif operation and operation.Status == "Reserved" then reason = "AnotherActionPending"
		elseif action == "BuyProtection" then
			if not isSafeSupportAmount(session.data.Tokens) or state.Charges >= MAX_SAFE_SUPPORT then
				reason = "InventoryUnavailable"
			elseif session.data.Tokens < Config.ProtectionItem.TokenCost then reason = "NeedFiveTokens" end
		elseif state.Charges < 1 then reason = "NoCharges" end
		local context
		if not reason and action == "UseProtection" then
			-- Capture once BEFORE any wait/lock/UpdateAsync. Retry never renews it.
			context, reason = PlayerProtection.GetContext(player)
		end
		if reason then
			protectionResponse(player, command, "Rejected", reason)
			return
		end
		attempt = {Command = command, Session = session, Context = context}
		protectionAttempts[player] = attempt
	end
	attempt.Running = true
	protectionResponse(player, command, "Pending", "Processing")
	local outcome
	local definiteRejection = false
	local success = mutateIdempotent(player, function(data)
		-- Roblox can discard a callback result and retry on a newer profile.
		outcome = nil
		definiteRejection = false
		local current = protectionState(data)
		if not current then outcome = "InventoryUnavailable"; return false end
		local last = current.LastOperation
		if protectionOperationMatches(last, command) then
			outcome = last.Status
			return false
		end
		-- A successful read at the original revision proves this operation has
		-- not committed, even if an earlier response was lost. A newer revision
		-- with an overwritten operation cannot establish that fact.
		definiteRejection = current.Revision == command.Revision
		if not protectionOwnsLease(player, attempt.Session, data) then outcome = "ProfileUnavailable"; return false end
		if current.Revision ~= command.Revision then outcome = "StaleRevision"; return false end
		if last and last.Status == "Reserved" then outcome = "AnotherActionPending"; return false end
		if action == "BuyProtection" then
			if not isSafeSupportAmount(data.Tokens) or current.Charges >= MAX_SAFE_SUPPORT then
				outcome = "InventoryUnavailable"; return false
			end
			if data.Tokens < Config.ProtectionItem.TokenCost then outcome = "NeedFiveTokens"; return false end
		else
			if current.Charges < 1 then outcome = "NoCharges"; return false end
		end
		definiteRejection = false
		-- Validate everything before changing balance, inventory or operation ID.
		if action == "BuyProtection" then
			data.Tokens -= Config.ProtectionItem.TokenCost
			current.Charges += 1
			outcome = "Bought"
		else
			current.Charges -= 1
			outcome = "Reserved"
		end
		current.Revision += 1
		current.LastOperation = {
			SessionId = command.SessionNonce, Revision = current.Revision,
			Kind = action == "BuyProtection" and "Buy" or "Use", Status = outcome,
		}
		return true
	end, true)
	if success and outcome == "Reserved" then
		if attempt.Applied == nil then
			-- The service call does not yield: its private epoch/character check and
			-- deadline commit happen together, after the durable reservation.
			attempt.Applied = protectionOwnsLease(player, attempt.Session, attempt.Session.data)
				and PlayerProtection.Activate(player, attempt.Context) == true
		end
		local wanted = attempt.Applied and "Consumed" or "Refunded"
		success = mutateIdempotent(player, function(data)
			outcome = nil
			definiteRejection = false
			local current = protectionState(data)
			local last = current and current.LastOperation
			if not protectionOperationMatches(last, command) then return false end
			outcome = last.Status
			if last.Status ~= "Reserved" then return false end
			if not protectionOwnsLease(player, attempt.Session, data) then return false end
			if wanted == "Refunded" then
				if current.Charges >= MAX_SAFE_SUPPORT then return false end
				current.Charges += 1
			end
			last.Status = wanted
			outcome = wanted
			return true
		end, true)
	end
	attempt.Running = false
	-- PlayerRemoving may complete while persistence yields. It owns cleanup;
	-- do not resurrect a response/attempt for a departed or replacement session.
	if sessions[player] ~= attempt.Session or protectionAttempts[player] ~= attempt then return end
	if success and (outcome == "Bought" or outcome == "Consumed" or outcome == "Refunded") then
		protectionAttempts[player] = nil
		protectionResponse(player, command, outcome)
	elseif success and outcome and definiteRejection then
		protectionAttempts[player] = nil
		protectionResponse(player, command, "Rejected", outcome)
	else
		-- No blind refund or fresh activation after an unknown completion. A retry
		-- retains Context and Applied and resolves precisely this operation.
		protectionResponse(player, command, "Pending", "SaveUnconfirmed")
	end
end

local function recoverStaleDispatchPredecessor(player, expectedSession)
	if RunService:IsStudio() or not expectedSession or not expectedSession.persistent then
		return false
	end
	local predecessorEpoch = math.max(0,
		math.floor(tonumber(expectedSession.dispatchPredecessorEpoch) or 0))
	if predecessorEpoch <= 0 then return true end

	local ownsLease = false
	local recovered = false
	local success = mutateIdempotent(player, function(data)
		ownsLease = data.Settings.MuteDispatchSessionId == expectedSession.dispatchSessionId
			and data.Settings.MuteDispatchSessionEpoch == expectedSession.dispatchSessionEpoch
		recovered = false
		if not ownsLease then
			return false
		end
		local closedEpoch = math.max(0,
			math.floor(tonumber(data.Settings.MuteDispatchClosedEpoch) or 0))
		if closedEpoch >= predecessorEpoch then
			recovered = true
			return false
		end

		-- The currently active lease has granted its entire predecessor chain a
		-- bounded handoff window. Atomically fencing every older epoch is safe now:
		-- normal mute writes require the active SessionId, and a late final callback
		-- must observe Closed/Recovered in this same UpdateAsync before writing.
		for _, record in ipairs(data.Settings.MuteDispatchSessionClaims) do
			if math.floor(tonumber(record.Epoch) or 0) <= predecessorEpoch then
				record.Departed = true
				record.Closed = true
				record.Recovered = true
			end
		end
		-- History is intentionally bounded. The watermark also fences an older
		-- record that was already pruned, without needing to reconstruct it.
		data.Settings.MuteDispatchClosedEpoch = math.max(closedEpoch, predecessorEpoch)
		advanceDispatchClosedEpoch(data.Settings)
		recovered = true
		return true
	end, true)

	local session = sessions[player]
	if not success or session ~= expectedSession then return false end
	if not ownsLease then
		session.dispatchLeaseActive = false
		player:SetAttribute("ZyntraDispatchPreferenceLoaded", false)
		return false
	end
	local closedEpoch = math.max(0,
		math.floor(tonumber(session.data.Settings.MuteDispatchClosedEpoch) or 0))
	if recovered and closedEpoch >= predecessorEpoch then
		session.dispatchClosedEpoch = closedEpoch
		session.dispatchPredecessorClosed = true
		player:SetAttribute("ZyntraDispatchPreferenceLoaded", true)
		task.spawn(publishDispatchSnapshot, player.UserId, session.data)
		return true
	end
	return false
end

local function closeAbandonedDispatchLoad(userId, sessionId)
	if RunService:IsStudio() or type(sessionId) ~= "string" or #sessionId == 0 then
		return true
	end
	local lastError
	for _, delaySeconds in ipairs(IDEMPOTENT_RETRY_DELAYS) do
		if delaySeconds > 0 then task.wait(delaySeconds) end
		local foundClaim = false
		local ok, result = pcall(function()
			return store:UpdateAsync("u_" .. tostring(userId), function(current)
				-- If the load never committed, do not create a profile merely to record
				-- its cancellation.
				if type(current) ~= "table" then return nil end
				current = normalizeProfile(current)
				foundClaim = false
				for _, record in ipairs(current.Settings.MuteDispatchSessionClaims) do
					if record.Id == sessionId then
						record.Departed = true
						foundClaim = true
						break
					end
				end
				if foundClaim then advanceDispatchClosedEpoch(current.Settings) end
				return current
			end)
		end)
		if ok then
			if foundClaim and type(result) == "table" then
				publishDispatchSnapshot(userId, normalizeProfile(result))
			end
			return true
		end
		lastError = result
	end
	warn("[Zyntra] Abandoned profile-load claim close failed for user", userId, lastError)
	return false
end

claimLobbyBriefingRemote.OnServerInvoke = function(player)
	local session = sessions[player]
	if not session or session.closing then return false end

	-- Keep one token for this player's entire server session. If UpdateAsync or
	-- the RemoteFunction response is lost, every later non-overlapping invocation
	-- with this same server-owned token receives the same true result. A different
	-- server/session token still cannot claim an already-played briefing.
	local claim = briefingClaims[player]
	if not claim then
		if session.data.Settings.LobbyBriefingPlayed == true then return false end
		claim = {
			id = game.JobId .. ":" .. tostring(player.UserId) .. ":" .. HttpService:GenerateGUID(false),
			running = false,
		}
		briefingClaims[player] = claim
	end

	-- Do not queue arbitrary InvokeServer callers behind an outage. The one
	-- active invocation already owns this stable token and its bounded retries;
	-- a later, non-overlapping client retry can reuse the token if it fails.
	if claim.running then return false end

	session = sessions[player]
	if not session or session.closing then return false end
	if session.data.Settings.LobbyBriefingPlayed == true then
		return session.data.Settings.LobbyBriefingClaimId == claim.id
	end

	claim.running = true
	local didClaim = false
	local success = mutateIdempotent(player, function(data)
		didClaim = false
		if data.Settings.LobbyBriefingPlayed == true then
			didClaim = data.Settings.LobbyBriefingClaimId == claim.id
			return false
		end
		didClaim = true
		data.Settings.LobbyBriefingPlayed = true
		data.Settings.LobbyBriefingClaimId = claim.id
		return true
	end)
	claim.running = false
	return success == true and didClaim == true
end

local queueSupportTotalSync
queueSupportTotalSync = function(userId, total)
	userId = math.floor(tonumber(userId) or 0)
	total = normalizedSupportAmount(total)
	if userId <= 0 or total <= 0 then return end
	pendingSupportSync[userId] = math.max(pendingSupportSync[userId] or 0, total)
	if supportSyncWorkers[userId] then return end

	supportSyncWorkers[userId] = true
	task.spawn(function()
		local lastAttempted = 0
		for _, delaySeconds in ipairs({0, 1, 3, 8, 20}) do
			if delaySeconds > 0 then task.wait(delaySeconds) end
			local target = pendingSupportSync[userId]
			if not target then break end
			lastAttempted = target
			if syncSupportTotal(userId, target) then
				-- A newer receipt may have raised the requested total while UpdateAsync
				-- yielded. Clear only the exact-or-older target we actually synced.
				if (pendingSupportSync[userId] or 0) <= target then
					pendingSupportSync[userId] = nil
				end
				refreshSupportLeaderboard()
				break
			end
		end

		supportSyncWorkers[userId] = nil
		local newest = pendingSupportSync[userId]
		if newest and newest > lastAttempted then
			task.defer(queueSupportTotalSync, userId, newest)
		end
	end)
end

task.spawn(function()
	task.wait(1)
	refreshSupportLeaderboard()
	while true do
		task.wait(math.max(30, tonumber(Config.SupportLeaderboardRefreshSeconds) or 90))
		-- Failed derived-cache writes stay dirty after their bounded immediate
		-- retries. Re-arm one worker per donor before each scheduled board read.
		for userId, total in pairs(pendingSupportSync) do
			queueSupportTotalSync(userId, total)
		end
		refreshSupportLeaderboard()
	end
end)

local function loadProfile(player, loadState)
	if not loadState or loadState.cancelled or not player.Parent then return end
	player:SetAttribute("ZyntraProfileLoaded", false)
	player:SetAttribute("ZyntraDispatchPreferenceLoaded", false)
	local data
	local persistent = not RunService:IsStudio()
	local dispatchSessionId = game.JobId .. ":" .. tostring(player.UserId) .. ":"
		.. HttpService:GenerateGUID(false)
	loadState.dispatchSessionId = dispatchSessionId
	local claimedSessionEpoch
	local predecessorSessionId
	local predecessorSessionEpoch = 0
	if RunService:IsStudio() then
		data = newProfile()
		data.Settings.MuteDispatchSessionEpoch = 1
		data.Settings.MuteDispatchSessionId = dispatchSessionId
		data.Settings.MuteDispatchSessionClaims = {{
			Id = dispatchSessionId,
			Epoch = 1,
			PreviousEpoch = 0,
			Closed = false,
		}}
		claimedSessionEpoch = 1
	else
		local lastError
		for attempt = 1, 3 do
			if loadState.cancelled then break end
			-- Loading atomically claims this player's dispatch-setting lease and a
			-- monotonically increasing session epoch. A newer GUID stops the old
			-- live queue; the epoch still lets PlayerRemoving hand off its last
			-- accepted input only when the newer session has not recorded one.
			loadState.claimAttempted = true
			local ok, result = pcall(function()
				return store:UpdateAsync("u_" .. player.UserId, function(current)
					current = normalizeProfile(current)
					-- PlayerRemoving/BindToClose can cancel while UpdateAsync is waiting.
					-- Roblox may re-run this callback after a competing server claims the
					-- profile; the in-callback fence prevents that retry from stealing the
					-- newer lease with this now-abandoned GUID.
					if loadState.cancelled then
						claimedSessionEpoch = nil
						return current
					end
					claimedSessionEpoch = nil
					for _, record in ipairs(current.Settings.MuteDispatchSessionClaims) do
						if record.Id == dispatchSessionId then
							claimedSessionEpoch = record.Epoch
							predecessorSessionId = record.PreviousId
							predecessorSessionEpoch = record.PreviousEpoch
							break
						end
					end
					if not claimedSessionEpoch then
						predecessorSessionId = current.Settings.MuteDispatchSessionId
						predecessorSessionEpoch = current.Settings.MuteDispatchSessionEpoch
						current.Settings.MuteDispatchSessionEpoch = math.max(
							current.Settings.MuteDispatchSessionEpoch,
							current.Settings.MuteDispatchInputEpoch
						) + 1
						current.Settings.MuteDispatchSessionId = dispatchSessionId
						claimedSessionEpoch = current.Settings.MuteDispatchSessionEpoch
						table.insert(current.Settings.MuteDispatchSessionClaims, {
							Id = dispatchSessionId,
							Epoch = claimedSessionEpoch,
							PreviousId = predecessorSessionId,
							PreviousEpoch = predecessorSessionEpoch,
							Departed = false,
							Closed = false,
						})
						while #current.Settings.MuteDispatchSessionClaims > 16 do
							table.remove(current.Settings.MuteDispatchSessionClaims, 1)
						end
					end
					recoverProtectionReservation(current, dispatchSessionId)
					return current
				end)
			end)
			if ok then
				data = result
				lastError = nil
				break
			end
			lastError = result
			if loadState.cancelled then break end
			task.wait(attempt)
		end
		if lastError then
			warn("[Zyntra] Could not load and claim profile for", player.Name, lastError)
			data = newProfile()
			data.Settings.MuteDispatchSessionEpoch = 1
			data.Settings.MuteDispatchSessionId = dispatchSessionId
			data.Settings.MuteDispatchSessionClaims = {{
				Id = dispatchSessionId,
				Epoch = 1,
				PreviousEpoch = 0,
				Closed = false,
			}}
			claimedSessionEpoch = 1
			persistent = false
		end
	end
	if loadState.cancelled or not player.Parent then return end
	local normalized = normalizeProfile(data)
	if not claimedSessionEpoch then
		for _, record in ipairs(normalized.Settings.MuteDispatchSessionClaims) do
			if record.Id == dispatchSessionId then
				claimedSessionEpoch = record.Epoch
				predecessorSessionId = record.PreviousId
				predecessorSessionEpoch = record.PreviousEpoch
				break
			end
		end
	end
	claimedSessionEpoch = math.max(0, math.floor(tonumber(claimedSessionEpoch) or 0))
	sessions[player] = {
		data = normalized,
		persistent = persistent,
		dispatchSessionId = dispatchSessionId,
		dispatchSessionEpoch = claimedSessionEpoch,
		dispatchLeaseActive = normalized.Settings.MuteDispatchSessionId == dispatchSessionId
			and normalized.Settings.MuteDispatchSessionEpoch == claimedSessionEpoch,
		dispatchPredecessorId = predecessorSessionId,
		dispatchPredecessorEpoch = predecessorSessionEpoch,
		dispatchClosedEpoch = normalized.Settings.MuteDispatchClosedEpoch,
		dispatchPredecessorClosed = isDispatchPredecessorClosed(
			normalized.Settings, predecessorSessionEpoch),
	}
	applyAttributes(player, sessions[player].data)
	player:SetAttribute("ZyntraProfileLoaded", true)
	local pendingSnapshot = pendingDispatchSnapshots[player.UserId]
	if pendingSnapshot then
		pendingDispatchSnapshots[player.UserId] = nil
		applyDispatchSnapshot(pendingSnapshot)
	end
	local loadedSession = sessions[player]
	-- A live session becomes audible only after its predecessor atomically closes
	-- (last input + Closed marker). Failure remains quiet instead of temporarily
	-- unmuting a returning player with an incomplete handoff.
	player:SetAttribute("ZyntraDispatchPreferenceLoaded", RunService:IsStudio()
		or (persistent and loadedSession.dispatchLeaseActive
			and loadedSession.dispatchPredecessorClosed))
	pushProfile(player)
	if persistent and sessions[player].dispatchLeaseActive
		and not sessions[player].dispatchPredecessorClosed then
		-- MessagingService provides the immediate handoff. This delayed read is a
		-- fallback for a publish/subscription outage or the tiny window between the
		-- lease claim and this local session being installed.
		task.spawn(function()
			local startedAt = os.clock()
			local delays = {1, 2, 4, 8}
			for _, delaySeconds in ipairs(delays) do
				task.wait(delaySeconds)
				local session = sessions[player]
				if not player.Parent or not session or session.closing
					or session.dispatchLeaseActive == false
					or session.dispatchPredecessorClosed then return end
				if os.clock() - startedAt >= DISPATCH_HANDOFF_GRACE_SECONDS then return end
				local ok, latest = pcall(store.GetAsync, store, "u_" .. player.UserId)
				if ok and type(latest) == "table" then
					latest = normalizeProfile(latest)
					if latest.Settings.MuteDispatchSessionId ~= session.dispatchSessionId then
						session.dispatchLeaseActive = false
						player:SetAttribute("ZyntraDispatchPreferenceLoaded", false)
						return
					end
					applyDispatchSnapshot(dispatchSnapshotFromData(player.UserId, latest))
				end
			end
		end)
		-- This timer is independent from the best-effort GetAsync reads above, so a
		-- slow read cannot extend the predecessor's write window. At the deadline,
		-- only the still-active lease may atomically fence it. DataStore outages retry
		-- slowly; successful recovery or a newer lease terminates this task.
		task.spawn(function()
			task.wait(DISPATCH_HANDOFF_GRACE_SECONDS)
			while true do
				local session = sessions[player]
				if not player.Parent or not session or session.closing
					or session.dispatchLeaseActive == false
					or session.dispatchPredecessorClosed then return end
				if recoverStaleDispatchPredecessor(player, session) then return end
				session = sessions[player]
				if not player.Parent or not session or session.closing
					or session.dispatchLeaseActive == false
					or session.dispatchPredecessorClosed then return end
				task.wait(DISPATCH_RECOVERY_RETRY_SECONDS)
			end
		end)
	end
	queueSupportTotalSync(player.UserId, recordedSupportRobux(sessions[player] and sessions[player].data))
end

-- A throw and a "no" used to collapse into the same false, and that false
-- latched for the whole session: one MarketplaceService blip at join cost a
-- paying Supporter their tag, their pickers and their grant until they rejoined.
-- Retry the throw a few times, and answer nil -- NOT false -- when Roblox never
-- answered at all, so a caller can tell "does not own" from "do not know".
local PASS_RETRY_DELAYS = {0, 1, 3}
local function ownsPass(player, pass)
	if RunService:IsStudio() and Config.Studio.GrantAllPasses then return true end
	if not pass or tonumber(pass.Id) == nil or pass.Id <= 0 then return false end
	local lastError
	for _, delaySeconds in ipairs(PASS_RETRY_DELAYS) do
		if delaySeconds > 0 then task.wait(delaySeconds) end
		if not player.Parent then return nil end
		local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
		if ok then return result == true end
		lastError = result
	end
	warn("[Zyntra] Pass ownership check failed:", pass.Name, lastError)
	return nil
end

-- A finished purchase is the strongest answer this server will ever get.
-- UserOwnsGamePassAsync caches per server and commonly still reads false for a
-- while after PromptGamePassPurchaseFinished, so the purchase is latched here
-- and wins over every later ownership read for the rest of the session; no
-- retry loop can beat that cache.
local passPurchases = setmetatable({}, { __mode = "k" })
-- Set when a read failed outright, so a bounded background re-check can pick the
-- pass up later instead of leaving the player locked out until they rejoin.
local passReadFailed = setmetatable({}, { __mode = "k" })
-- How many of those re-checks a player has already been given. The cap is what
-- stops a MarketplaceService outage becoming a permanent poll.
local passRechecks = setmetatable({}, { __mode = "k" })
local PASS_RECHECK_DELAY = 20
local PASS_RECHECK_LIMIT = 3

local function passOwnership(player, key, pass)
	local purchases = passPurchases[player]
	if purchases and purchases[key] then return true end
	local answer = ownsPass(player, pass)
	if answer == nil then
		passReadFailed[player] = true
		-- Unknown: keep whatever this session already published rather than
		-- downgrading an owner to false.
		return player:GetAttribute("ZyntraOwns" .. key) == true
	end
	return answer
end

local function refreshPasses(player)
	if not sessions[player] then return end
	passReadFailed[player] = nil
	local supporter = passOwnership(player, "Supporter", Config.Passes.Supporter)
	local advanced = passOwnership(player, "AdvancedEquipment", Config.Passes.AdvancedEquipment)
	local cosmetic = passOwnership(player, "CosmeticEquipment", Config.Passes.CosmeticEquipment)
	player:SetAttribute("ZyntraOwnsSupporter", supporter)
	player:SetAttribute("ZyntraOwnsAdvancedEquipment", advanced)
	player:SetAttribute("ZyntraOwnsCosmeticEquipment", cosmetic)

	if supporter then
		mutate(player, function(data)
			if data.Grants.Supporter then return false end
			data.Grants.Supporter = true
			data.Tokens += Config.Passes.Supporter.TokenGrant
			return true, "+" .. Config.Passes.Supporter.TokenGrant .. " Zyntra Research Tokens", "success"
		end)
	end
	if advanced then
		mutate(player, function(data)
			if data.Grants.AdvancedEquipment then return false end
			data.Grants.AdvancedEquipment = true
			data.StaminaLevel += 1
			data.BatteryLevel += 1
			return true, "Advanced Equipment: +" .. PCT .. " stamina and +" .. PCT .. " battery", "success"
		end)
	end
	if cosmetic and player:GetAttribute("InRound") == true then
		player:SetAttribute("GlowstickColor", player:GetAttribute("ZyntraGlowstickColor"))
	end
	if player.Character then
		task.defer(refreshPlayerTags, player, player.Character)
		task.defer(applyHazmatColor, player)
	end
	-- A read that never answered leaves a paying player without their pass, and
	-- nothing else re-asks. It cannot be left to "the next action that needs the
	-- pass" either: the store locks its colour picker on this very attribute and
	-- returns before firing the remote, so the one action that would trigger a
	-- re-check is exactly the one the client refuses to send -- and the Supporter
	-- pass has no such action at all. Re-ask in the background, a few times, then
	-- stop. A successful pass clears passReadFailed above and schedules no more.
	local rechecks = passRechecks[player] or 0
	if passReadFailed[player] and rechecks < PASS_RECHECK_LIMIT then
		passRechecks[player] = rechecks + 1
		task.delay(PASS_RECHECK_DELAY, function()
			if sessions[player] and passReadFailed[player] then refreshPasses(player) end
		end)
	end
	pushProfile(player)
end

local function setupPlayer(player)
	if serverClosing or profileLoads[player] or sessions[player] then return end
	local loadState = {
		cancelled = false,
		done = false,
		success = false,
		claimAttempted = false,
		dispatchSessionId = nil,
	}
	profileLoads[player] = loadState
	task.spawn(function()
		local ok, result = pcall(loadProfile, player, loadState)
		loadState.success = ok
		loadState.error = ok and nil or result
		loadState.done = true
		if not ok then
			warn("[Zyntra] Profile-load task failed for user", player.UserId, result)
		end
		if ok and not loadState.cancelled and sessions[player] then refreshPasses(player) end
	end)
	local headAddedConnection
	local function releaseCharacter()
		if headAddedConnection then headAddedConnection:Disconnect(); headAddedConnection = nil end
		local character = tagCharacters[player]
		-- CharacterRemoving may precede the Player.Character property update.
		-- Invalidate every queued Head/pass refresh before clearing its badges.
		tagCharacters[player] = nil
		if character then clearPlayerTags(character) end
	end
	local function characterReady(character)
		if player.Parent ~= Players or player.Character ~= character then return end
		releaseCharacter()
		tagCharacters[player] = character
		local function refreshCharacter()
			if player.Parent ~= Players or player.Character ~= character
				or tagCharacters[player] ~= character then return end
			refreshPlayerTags(player, character)
			applyHazmatColor(player)
		end
		-- No timeout: custom avatars may receive Head after profile loading or
		-- well after CharacterAdded. Disconnect when this character is retired.
		headAddedConnection = character.ChildAdded:Connect(function(child)
			if child.Name == "Head" and child:IsA("BasePart") then task.defer(refreshCharacter) end
		end)
		task.defer(refreshCharacter)
	end
	player.CharacterAdded:Connect(characterReady)
	player.CharacterRemoving:Connect(function(character)
		if tagCharacters[player] == character then releaseCharacter() end
	end)
	player.AncestryChanged:Connect(function()
		if player.Parent ~= Players then releaseCharacter() end
	end)
	if player.Character then characterReady(player.Character) end
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player.Character then task.defer(refreshPlayerTags, player, player.Character) end
		if player:GetAttribute("InRound") == true then
			if player:GetAttribute("ZyntraOwnsCosmeticEquipment") == true then
				player:SetAttribute("GlowstickColor", player:GetAttribute("ZyntraGlowstickColor"))
			end
			task.defer(applyHazmatColor, player)
		end
	end)
end

getProfileRemote.OnServerInvoke = function(player)
	local deadline = os.clock() + 10
	while not sessions[player] and os.clock() < deadline do task.wait(0.1) end
	return enrichedPublicProfile(player)
end

local function sameColorData(saved, wanted)
	return type(saved) == "table"
		and saved.R == wanted.R and saved.G == wanted.G and saved.B == wanted.B
end

local function validColor(value)
	if typeof(value) ~= "Color3" then return nil end
	local h, s, v = value:ToHSV()
	s = math.clamp(s, 0, 0.9)
	v = math.clamp(v, 0.35, 1)
	return Color3.fromHSV(h, s, v)
end

-- Back-to-back mute writes escalate toward Roblox's one-write-per-six-seconds
-- guidance for a single key. A client that alternates true/false is never a
-- duplicate, so without this floor every toggle it sends becomes a real
-- UpdateAsync on that player's profile key -- about 72 a minute, indefinitely,
-- out of a server budget of 60 + 10 per player. The first toggle after a quiet
-- spell still commits at the old responsive pace; only a stream of them slows
-- down, and the queue folds everything that arrives while it waits into the one
-- write that follows, so nothing is lost and the client stays optimistic.
local MUTE_WRITE_FLOORS = {0.75, 2, 6}
local MUTE_WRITE_STREAK_RESET_SECONDS = 30

local queueMuteDispatch
local function muteQueueActive(player, queue)
	return queue.closing ~= true
		and player.Parent ~= nil
		and sessions[player] ~= nil
		and sessions[player].closing ~= true
		and sessions[player].dispatchLeaseActive ~= false
		and dispatchMuteQueues[player] == queue
end

local function takeLatestMuteDesired(queue, desired, revision)
	if type(queue.desired) == "boolean" then
		desired = queue.desired
		revision = queue.desiredRevision
		queue.desired = nil
		queue.desiredRevision = nil
		queue.desiredIsReassert = nil
	end
	queue.processingDesired = desired
	queue.processingRevision = revision
	return desired, revision
end

local function runMuteDispatchQueue(player, queue)
	while muteQueueActive(player, queue) do
		local desired = queue.desired
		local revision = queue.desiredRevision
		queue.desired = nil
		queue.desiredRevision = nil
		if type(desired) ~= "boolean" or type(revision) ~= "number" then break end
		queue.processingDesired = desired
		queue.processingRevision = revision

		local idle = os.clock() - queue.lastAttemptFinishedAt
		if idle > MUTE_WRITE_STREAK_RESET_SECONDS then queue.writeStreak = 0 end
		local streak = math.floor(tonumber(queue.writeStreak) or 0)
		local remaining = MUTE_WRITE_FLOORS[math.clamp(streak + 1, 1, #MUTE_WRITE_FLOORS)] - idle
		if remaining > 0 then task.wait(remaining) end
		if not muteQueueActive(player, queue) then break end
		desired, revision = takeLatestMuteDesired(queue, desired, revision)

		-- A receipt/pass/profile mutation can own the shared lock for multiple
		-- seconds. Continue folding toggles into this one target while we wait,
		-- then call mutateIdempotent immediately after observing the lock free;
		-- acquireMutation has no yield on that path, so another writer cannot slip
		-- between this check and its acquisition.
		while mutationLocks[player] do
			task.wait()
			if not muteQueueActive(player, queue) then break end
			desired, revision = takeLatestMuteDesired(queue, desired, revision)
		end
		if not muteQueueActive(player, queue) then break end
		desired, revision = takeLatestMuteDesired(queue, desired, revision)

		local session = sessions[player]
		local current = session and session.data and session.data.Settings.MuteDispatch
		local dispatchSessionEpoch = session and session.dispatchSessionEpoch or 0
		local currentInputEpoch = session and session.data
			and math.max(0, math.floor(tonumber(session.data.Settings.MuteDispatchInputEpoch) or 0)) or 0
		local currentRevision = session and session.data
			and math.max(0, math.floor(tonumber(session.data.Settings.MuteDispatchRevision) or 0)) or 0
		if current == desired and currentInputEpoch == dispatchSessionEpoch
			and currentRevision >= revision and not queue.uncertain then
			-- A client may resend the same target every frame. Acknowledge an
			-- already-current target once, without spawning a worker or firing a
			-- profile packet for every duplicate RemoteEvent.
			if queue.lastAcknowledged ~= desired then
				pushProfile(player, desired and "Dispatch audio muted." or "Dispatch audio enabled.", "success")
				queue.lastAcknowledged = desired
			end
		else
			queue.inFlightDesired = desired
			queue.inFlightRevision = revision
			local targetApplied = false
			local dispatchSessionId = session and session.dispatchSessionId
			local success = mutateIdempotent(player, function(data)
				targetApplied = false
				if data.Settings.MuteDispatchSessionId ~= dispatchSessionId then
					return false, "Dispatch preference belongs to a newer session.", "info"
				end
				local storedInputEpoch = math.max(0,
					math.floor(tonumber(data.Settings.MuteDispatchInputEpoch) or 0))
				local storedRevision = math.max(0,
					math.floor(tonumber(data.Settings.MuteDispatchRevision) or 0))
				-- The atomically allocated session epoch is the cross-server causal
				-- order; revision is strictly increasing inside that epoch. Equality
				-- is this exact idempotent retry and must never overwrite an opposite.
				if storedInputEpoch > dispatchSessionEpoch
					or (storedInputEpoch == dispatchSessionEpoch and storedRevision >= revision) then
					targetApplied = data.Settings.MuteDispatch == desired
					return false,
						targetApplied and (desired and "Dispatch audio muted." or "Dispatch audio enabled.")
							or "Dispatch preference was updated in another server.",
						targetApplied and "success" or "info"
				end
				targetApplied = true
				local changed = data.Settings.MuteDispatch ~= desired
					or storedInputEpoch ~= dispatchSessionEpoch or storedRevision ~= revision
				data.Settings.MuteDispatch = desired
				data.Settings.MuteDispatchInputEpoch = dispatchSessionEpoch
				data.Settings.MuteDispatchRevision = revision
				return changed,
					desired and "Dispatch audio muted." or "Dispatch audio enabled.",
					"success"
			end)
			if success and session and session.data.Settings.MuteDispatchSessionId ~= dispatchSessionId then
				session.dispatchLeaseActive = false
			end
			queue.inFlightDesired = nil
			queue.inFlightRevision = nil
			-- Rate-limit from completion, not start. UpdateAsync plus its bounded
			-- retries may yield for seconds, and that time must not permit another
			-- write to begin immediately when it returns.
			queue.lastAttemptFinishedAt = os.clock()
			-- Only an attempt that actually opened a write counts toward the floor;
			-- an acknowledged duplicate above never reaches this branch.
			queue.writeStreak = math.min(streak + 1, #MUTE_WRITE_FLOORS)
			if success then
				queue.uncertain = false
				queue.lastAcknowledged = targetApplied and desired or nil
				if targetApplied and session and session.data then
					task.spawn(publishDispatchSnapshot, player.UserId, session.data)
				end
				if targetApplied and queue.desired == desired and queue.desiredIsReassert == true then
					-- Matching spam that arrived during this write is redundant once the
					-- target is confirmed. Preserve it only when this attempt lost to a
					-- newer external revision or remained ambiguous.
					queue.desired = nil
					queue.desiredRevision = nil
					queue.desiredIsReassert = nil
				end
			else
				-- A failed response does not prove UpdateAsync failed to commit. Until
				-- a later target-state write succeeds, never trust the local no-op
				-- shortcut: force the newest accepted target through DataStore.
				queue.uncertain = true
			end
		end
		queue.processingDesired = nil
		queue.processingRevision = nil
	end

	queue.processingDesired = nil
	queue.processingRevision = nil
	queue.inFlightDesired = nil
	queue.inFlightRevision = nil
	queue.running = false
end

queueMuteDispatch = function(player, desired)
	local queue = dispatchMuteQueues[player]
	if not queue then
		queue = {
			desired = nil,
			desiredRevision = nil,
			desiredIsReassert = nil,
			acceptedDesired = nil,
			acceptedRevision = 0,
			running = false,
			closing = false,
			uncertain = false,
			lastAttemptFinishedAt = -math.huge,
			writeStreak = 0,
			lastAcknowledged = nil,
			processingDesired = nil,
			processingRevision = nil,
			inFlightDesired = nil,
			inFlightRevision = nil,
		}
		dispatchMuteQueues[player] = queue
	end
	if queue.closing then return end

	local session = sessions[player]
	if not session or session.dispatchLeaseActive == false then return end
	local current = session and session.data and session.data.Settings.MuteDispatch
	local dispatchSessionEpoch = session and session.dispatchSessionEpoch or 0
	local duplicate = queue.acceptedDesired == desired
	local pendingSame = queue.desired == desired
	local processingSame = queue.processingDesired == desired or queue.inFlightDesired == desired
	if duplicate and not queue.running and not queue.uncertain and current == desired then
		return
	end
	local storedInputEpoch = session and session.data
		and math.max(0, math.floor(tonumber(session.data.Settings.MuteDispatchInputEpoch) or 0)) or 0
	local storedRevision = storedInputEpoch == dispatchSessionEpoch and session and session.data
		and math.max(0, math.floor(tonumber(session.data.Settings.MuteDispatchRevision) or 0)) or 0
	local revision = math.max(
		math.floor(tonumber(queue.acceptedRevision) or 0) + 1,
		storedRevision + 1
	)
	local isReassert = false
	if duplicate then
		if pendingSame then
			isReassert = queue.desiredIsReassert == true
		elseif processingSame then
			isReassert = true
		end
	end
	queue.acceptedDesired = desired
	queue.acceptedRevision = revision
	queue.lastAcknowledged = nil
	queue.desired = desired
	queue.desiredRevision = revision
	queue.desiredIsReassert = isReassert
	if queue.running then return end
	queue.running = true
	task.spawn(runMuteDispatchQueue, player, queue)
end

local function persistDispatchTargetOnLeave(player, session, queue)
	local desired = queue and queue.acceptedDesired
	local revision = queue and queue.acceptedRevision
	local dispatchSessionEpoch = session and session.dispatchSessionEpoch
	local dispatchSessionId = session and session.dispatchSessionId
	if type(dispatchSessionEpoch) ~= "number"
		or type(dispatchSessionId) ~= "string" or not session then return true end
	local hasAcceptedTarget = type(desired) == "boolean" and type(revision) == "number"

	local function closeClaim(settings)
		local found = false
		for _, record in ipairs(settings.MuteDispatchSessionClaims) do
			if record.Id == dispatchSessionId and record.Epoch == dispatchSessionEpoch then
				record.Departed = true
				found = true
				break
			end
		end
		if not found then
			local alreadyFenced = math.max(0,
				math.floor(tonumber(settings.MuteDispatchClosedEpoch) or 0)) >= dispatchSessionEpoch
			table.insert(settings.MuteDispatchSessionClaims, {
				Id = dispatchSessionId,
				Epoch = dispatchSessionEpoch,
				PreviousId = session.dispatchPredecessorId,
				PreviousEpoch = session.dispatchPredecessorEpoch or 0,
				Departed = true,
				Closed = alreadyFenced,
				Recovered = alreadyFenced,
			})
		end
		while #settings.MuteDispatchSessionClaims > 16 do
			table.remove(settings.MuteDispatchSessionClaims, 1)
		end

		-- Close only a causally contiguous departed chain. If B departs while A
		-- is still saving, B remains pending; A's later final transaction advances
		-- the watermark through both A and B in this same atomic UpdateAsync.
		advanceDispatchClosedEpoch(settings)
	end

	if RunService:IsStudio() then
		local current = normalizeProfile(session.data)
		if hasAcceptedTarget and dispatchClaimCanFinalize(current.Settings,
			dispatchSessionId, dispatchSessionEpoch) then
			local storedInputEpoch = math.max(0,
				math.floor(tonumber(current.Settings.MuteDispatchInputEpoch) or 0))
			local storedRevision = math.max(0,
				math.floor(tonumber(current.Settings.MuteDispatchRevision) or 0))
			if storedInputEpoch < dispatchSessionEpoch
				or (storedInputEpoch == dispatchSessionEpoch and storedRevision < revision) then
				current.Settings.MuteDispatch = desired
				current.Settings.MuteDispatchInputEpoch = dispatchSessionEpoch
				current.Settings.MuteDispatchRevision = revision
			end
		end
		closeClaim(current.Settings)
		session.data = current
		return true
	end
	if not session.persistent then return false end

	local userId = player.UserId
	local lastError
	for _, delaySeconds in ipairs(IDEMPOTENT_RETRY_DELAYS) do
		if delaySeconds > 0 then task.wait(delaySeconds) end
		local ok, result = pcall(function()
			return store:UpdateAsync("u_" .. tostring(userId), function(current)
				current = normalizeProfile(current)
				if hasAcceptedTarget and dispatchClaimCanFinalize(current.Settings,
					dispatchSessionId, dispatchSessionEpoch) then
					local storedInputEpoch = math.max(0,
						math.floor(tonumber(current.Settings.MuteDispatchInputEpoch) or 0))
					local storedRevision = math.max(0,
						math.floor(tonumber(current.Settings.MuteDispatchRevision) or 0))
					if storedInputEpoch < dispatchSessionEpoch
						or (storedInputEpoch == dispatchSessionEpoch and storedRevision < revision) then
						current.Settings.MuteDispatch = desired
						current.Settings.MuteDispatchInputEpoch = dispatchSessionEpoch
						current.Settings.MuteDispatchRevision = revision
					end
				end
				closeClaim(current.Settings)
				return current
			end)
		end)
		if ok then
			publishDispatchSnapshot(userId, normalizeProfile(result))
			return true
		end
		lastError = result
	end
	warn("[Zyntra] Final dispatch preference save failed for user", userId, lastError)
	return false
end

-- ---------------------------------------------------------------------------
-- Emergency Re-entry: reserve the credit, THEN ask for the respawn
-- ---------------------------------------------------------------------------
-- The old order invoked the respawn first and spent the credit afterwards, so a
-- DataStore write that failed behind an accepted respawn left the player holding
-- both. Reserving first inverts the failure: the worst case is now a credit
-- spent on a respawn that was refused, and that case refunds itself.
--
-- The refund is keyed on a per-attempt token and is only ever paid against the
-- attempt that is still current, so a superseded attempt, a repeated call, or a
-- player whose session ended mid-flow (the token dies with the session) can
-- never be credited twice for one reservation.
local reentryAttempts = {}

-- The exact conditions the store's re-entry button uses to show itself, read
-- server-side: in a live round, dead, and the round's one re-entry unspent.
local function reentryEligible(player)
	if not player.Parent then return false end
	if player:GetAttribute("InRound") ~= true then return false end
	if workspace:GetAttribute("RoundActive") ~= true then return false end
	if player:GetAttribute("ZyntraReentryUsed") == true then return false end
	-- GameManager's OnInvoke also refuses an escapee, so this has to as well:
	-- these conditions gate the AUTO-use after a purchase, and every condition
	-- missing here is a credit spent on a respawn that is then refused.
	if player:GetAttribute("Escaped") == true then return false end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid == nil or humanoid.Health <= 0
end

local function useReentry(player)
	local session = sessions[player]
	if not session then return false end
	-- One attempt at a time. Without this, a second click during the yielding
	-- respawn would reserve a second credit that the first attempt's refund
	-- would then decline to pay back.
	if reentryAttempts[player] then return false end
	if session.data.ReentryCredits < 1 then
		pushProfile(player, "You do not have an Emergency Re-entry credit.", "error")
		return false
	end
	local reentry = ServerStorage:FindFirstChild("ZyntraReentry")
	if not reentry or not reentry:IsA("BindableFunction") then
		pushProfile(player, "Re-entry is not available right now.", "error")
		return false
	end

	local token = {}
	reentryAttempts[player] = token
	local reserved = mutate(player, function(data)
		if data.ReentryCredits < 1 then
			return false, "You do not have an Emergency Re-entry credit.", "error"
		end
		data.ReentryCredits -= 1
		-- Deliberately no message: the credit is only RESERVED here. Announcing
		-- success now is how a player would read "activated" one frame before
		-- being told the respawn was refused. The push still carries the new
		-- credit count, so the store button updates either way.
		return true
	end)
	if not reserved then
		-- Nothing was spent, so there is nothing to give back.
		if reentryAttempts[player] == token then reentryAttempts[player] = nil end
		return false
	end

	local ok, accepted = pcall(reentry.Invoke, reentry, player)
	if reentryAttempts[player] ~= token then return ok and accepted == true end
	reentryAttempts[player] = nil
	if ok and accepted == true then
		pushProfile(player, "Emergency Re-entry activated.", "success")
		return true
	end

	-- The refund is a delta, so it cannot go through mutateIdempotent: replaying
	-- a `+= 1` whose write in fact committed would hand out a credit nobody paid
	-- for. It gets a small bounded retry instead, because one transient
	-- DataStore error must not turn "respawn refused" into "paid credit
	-- destroyed" -- and if all three attempts fail, the warn is the only trace
	-- left, so it names the userId to make the credit reconcilable by hand.
	local function refund(data)
		data.ReentryCredits += 1
		return true, "Re-entry is only available after death during an active round.", "error"
	end
	for attempt = 1, 3 do
		if mutate(player, refund) then return false end
		if not player.Parent or sessions[player] ~= session then break end
		if attempt < 3 then task.wait(0.35) end
	end
	warn("[Zyntra] Re-entry refund FAILED; owes 1 ReentryCredit to userId", player.UserId)
	return false
end

-- One Roblox badge, decided from OUR record first. UserHasBadgeAsync is asked
-- only when we have no record of the award, which keeps an account that earned
-- the badge before this shipped from being re-awarded (and re-notified) on every
-- later clear. Everything yields inside task.spawn and every Roblox call is
-- wrapped, so a throttled or failing badge service can neither block nor fail
-- the profile write that reported the clear.
local function awardBadge(player, badgeKey)
	local badgeId = math.floor(tonumber(Config.Badges and Config.Badges[badgeKey]) or 0)
	if badgeId <= 0 then return end
	local session = sessions[player]
	if not session or session.data.AwardedBadges[badgeKey] == true then return end
	task.spawn(function()
		local asked, owns = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, badgeId)
		if not (asked and owns == true) then
			-- BOTH returns matter. pcall's second value is AwardBadge's own
			-- boolean, and AwardBadge RETURNS false rather than throwing for the
			-- ordinary refusals: badge disabled, badge not owned by this place,
			-- award throttled, player gone. Reading only pcall's ok would record
			-- an award that never happened -- and that record is checked first on
			-- every later clear, so the badge would never be retried again.
			local ok, awarded = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badgeId)
			if not ok or awarded ~= true then
				warn("[Zyntra] AwardBadge failed for", player.Name, badgeKey, awarded)
				return
			end
		end
		-- Recording the award is a target state, not a delta, so a retried write
		-- cannot hand anything out twice: the idempotent path is the right one.
		mutateIdempotent(player, function(data)
			if data.AwardedBadges[badgeKey] == true then return false end
			data.AwardedBadges[badgeKey] = true
			return true
		end, true)
	end)
end

-- Accessibility switches persist like the dispatch mute and for the same
-- reason: they are target state, not deltas, and a client can flip one as fast
-- as it likes. The attribute and the session copy move immediately (the client
-- stays optimistic), while ONE deferred write commits whatever the newest
-- target is -- so forty flips cost one write, not forty. The first change after
-- a quiet spell writes at once; only a follow-up inside the floor waits. A
-- player who quits inside the floor is covered by the flush in
-- finalizePlayerSessionBody, which commits the same targets before the session
-- closes -- without it the second change of a session was simply lost.
local ACCESSIBILITY_WRITE_FLOOR = 6

-- Target state, not a delta: writing the same value twice is a no-op, so this
-- transform reports "no change" and mutateIdempotent cancels the update.
-- The caller hands over the LIVE queue, so snapshot it first (that copy cannot
-- yield): the write below can, and a switch flipped while it does must not be
-- added to a table this is still iterating.
local function writeAccessibilityTargets(player, desired)
	local targets = {}
	for settingKey, settingValue in pairs(desired) do
		targets[settingKey] = settingValue
	end
	return mutateIdempotent(player, function(data)
		local changed = false
		for settingKey, settingValue in pairs(targets) do
			if data.Settings[settingKey] ~= settingValue then
				data.Settings[settingKey] = settingValue
				changed = true
			end
		end
		return changed
	end, true)
end

local function queueAccessibilityWrite(player, key, value)
	local queue = accessibilityQueues[player]
	if not queue then
		queue = { running = false, dirty = false, desired = {}, lastWriteAt = -math.huge }
		accessibilityQueues[player] = queue
	end
	-- The target is remembered HERE and not read back out of session.data later:
	-- any unrelated profile write landing in between replaces session.data with
	-- the store's copy, which does not have this toggle in it yet. Keeping every
	-- key toggled this session also means the next write re-asserts them all, so
	-- a value that was overwritten that way heals itself.
	queue.desired[key] = value
	queue.dirty = true
	if queue.running then return end
	queue.running = true
	task.spawn(function()
		while queue.dirty do
			local remaining = ACCESSIBILITY_WRITE_FLOOR - (os.clock() - queue.lastWriteAt)
			if remaining > 0 then task.wait(remaining) end
			local session = sessions[player]
			if not session or session.closing or not player.Parent
				or accessibilityQueues[player] ~= queue then break end
			-- Snapshot AFTER the wait (writeAccessibilityTargets takes it): every
			-- toggle that arrived while we waited is already in queue.desired, so
			-- they all commit in this one write.
			queue.dirty = false
			writeAccessibilityTargets(player, queue.desired)
			-- Rate-limit from completion, as the dispatch queue does.
			queue.lastWriteAt = os.clock()
		end
		queue.running = false
	end)
end

-- Actions that open a DataStore write get a window a human click fits in;
-- everything else keeps the responsive one. UseReentry is deliberately NOT in
-- here: it is a single press inside the fifteen-second wipe window, it refuses
-- itself in memory when there is no credit, and reentryAttempts already allows
-- only one at a time.
-- SetAccessibility belongs here even though its DataStore write is coalesced
-- behind a six-second floor: every accepted call still republishes sixteen
-- attributes and a whole profile packet, and a client alternating true/false is
-- never a duplicate. One human click per switch per second is plenty.
local WRITE_BEARING_ACTIONS = {
	UpgradeStamina = true,
	UpgradeBattery = true,
	SetHazmatColor = true,
	SetGlowstickColor = true,
	SetAccessibility = true,
}
local ACTION_WINDOW = 0.12
local WRITE_ACTION_WINDOW = 1

actionRemote.OnServerEvent:Connect(function(player, action, payload)
	if type(action) ~= "string" or not sessions[player] then return end
	-- Dispatch preference is an idempotent target state with its own coalescing
	-- queue. It must never be silently dropped because the player clicked any
	-- unrelated store action during the shared 120 ms action window.
	if action == "BuyProtection" or action == "UseProtection" then
		handleProtectionAction(player, action, payload)
		return
	end
	if action == "SetMuteDispatch" then
		if type(payload) == "boolean" then queueMuteDispatch(player, payload) end
		return
	end
	local now = os.clock()
	-- The window is PER ACTION, not per player. One shared timestamp turned two
	-- legitimate consecutive clicks on different controls -- UPGRADE STAMINA then
	-- UPGRADE BATTERY, HAZMAT SAVE then GLOWSTICK SAVE -- into one click plus a
	-- dead button, which at a one-second window is a human interval. Accessibility
	-- switches key on the switch as well, because the settings page is a column of
	-- them; an unknown key falls into the shared bucket so a spammer cannot grow
	-- this table.
	local windowKey = action
	if action == "SetAccessibility" and type(payload) == "table"
		and ACCESSIBILITY_BY_KEY[payload.Key] then
		windowKey = "SetAccessibility:" .. payload.Key
	end
	local times = actionTimes[player]
	if not times then
		times = {}
		actionTimes[player] = times
	end
	local window = WRITE_BEARING_ACTIONS[action] and WRITE_ACTION_WINDOW or ACTION_WINDOW
	if now - (times[windowKey] or 0) < window then return end
	times[windowKey] = now

	if action == "UpgradeStamina" or action == "UpgradeBattery" then
		-- Refuse in memory FIRST. The in-transform check below stays as the
		-- cross-server race guard, but reaching it costs a DataStore write, and a
		-- player with zero tokens could once drive one of those per click.
		if sessions[player].data.Tokens < 1 then
			pushProfile(player, "You need 1 Zyntra Research Token.", "error")
			return
		end
		mutate(player, function(data)
			if data.Tokens < 1 then return false, "You need 1 Zyntra Research Token.", "error" end
			data.Tokens -= 1
			if action == "UpgradeStamina" then
				data.StaminaLevel += 1
				return true, "Stamina increased by " .. PCT .. ".", "success"
			end
			data.BatteryLevel += 1
			return true, "Battery increased by " .. PCT .. ".", "success"
		end)
	elseif action == "SetHazmatColor" then
		if player:GetAttribute("ZyntraOwnsAdvancedEquipment") ~= true then
			pushProfile(player, "Advanced Equipment is required.", "error")
			return
		end
		local color = validColor(payload)
		if not color then return end
		local wanted = colorData(color)
		local session = sessions[player]
		if not session then return end
		-- A colour that is already saved is acknowledged, not written. The same
		-- check inside the transform stays as the cross-server race guard.
		if sameColorData(session.data.Colors.Hazmat, wanted) then
			pushProfile(player, "Hazmat color saved.", "success")
			return
		end
		mutate(player, function(data)
			if sameColorData(data.Colors.Hazmat, wanted) then
				return false, "Hazmat color saved.", "success"
			end
			data.Colors.Hazmat = wanted
			return true, "Hazmat color saved.", "success"
		end)
	elseif action == "SetGlowstickColor" then
		if player:GetAttribute("ZyntraOwnsCosmeticEquipment") ~= true then
			pushProfile(player, "Glowstick Customizer is required.", "error")
			return
		end
		local color = validColor(payload)
		if not color then return end
		local wanted = colorData(color)
		local session = sessions[player]
		if not session then return end
		if sameColorData(session.data.Colors.Glowstick, wanted) then
			pushProfile(player, "Glowstick color saved.", "success")
			return
		end
		mutate(player, function(data)
			if sameColorData(data.Colors.Glowstick, wanted) then
				return false, "Glowstick color saved.", "success"
			end
			data.Colors.Glowstick = wanted
			return true, "Glowstick color saved.", "success"
		end)
	elseif action == "SetAccessibility" then
		if type(payload) ~= "table" or type(payload.Enabled) ~= "boolean"
			or type(payload.Key) ~= "string" then return end
		local setting = ACCESSIBILITY_BY_KEY[payload.Key]
		if not setting then return end
		local session = sessions[player]
		if not session or session.closing then return end
		-- Idempotent: an unchanged switch is not a write and not a packet.
		if accessibilityValue(session.data, setting) == payload.Enabled then return end
		session.data.Settings[setting.Key] = payload.Enabled
		-- Record the target BEFORE anything publishes it: from here on, a mutation
		-- finishing on another thread re-asserts it instead of overwriting it with
		-- the store's older copy (reassertPendingAccessibility).
		queueAccessibilityWrite(player, setting.Key, payload.Enabled)
		applyAttributes(player, session.data)
		pushProfile(player, setting.Label .. (payload.Enabled and ": on" or ": off"), "success")
	elseif action == "UseReentry" then
		useReentry(player)
	end
end)

levelCompletedEvent.Event:Connect(function(player, level)
	if not player or not player:IsA("Player") or not sessions[player] then return end
	-- GameManager fires this once per escapee with the level they just cleared.
	local cleared = math.floor(tonumber(level) or 0)
	local tracked = cleared >= 1 and cleared <= 3
	mutate(player, function(data)
		data.Tokens += Config.LevelCompletionTokens
		data.CompletedLevels += 1
		if tracked then data.LevelsCleared[tostring(cleared)] = true end
		return true, ("+%d Zyntra Research Tokens for completing the level."):format(Config.LevelCompletionTokens), "success"
	end)
	if not tracked then return end
	-- Badges hang off the write above rather than replacing it: awardBadge is
	-- non-blocking and every failure inside it is contained, so a badge that
	-- cannot be granted never costs the player the token they earned.
	awardBadge(player, "FirstClearLevel" .. cleared)
	local session = sessions[player]
	local levelsCleared = session and session.data.LevelsCleared
	if levelsCleared and levelsCleared["1"] and levelsCleared["2"] and levelsCleared["3"] then
		awardBadge(player, "CampaignComplete")
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then return end
	for key, pass in pairs(Config.Passes) do
		if pass.Id > 0 and pass.Id == passId then
			-- Latch the purchase BEFORE refreshing: Roblox has just told us this
			-- player paid, and its own ownership cache may still say otherwise for
			-- seconds. Without the latch a 99 R$ purchase can grant nothing until
			-- the player rejoins.
			local purchases = passPurchases[player]
			if not purchases then
				purchases = {}
				passPurchases[player] = purchases
			end
			purchases[key] = true
			task.spawn(refreshPasses, player)
			break
		end
	end
end)

local productById = {}
local function registerProductCatalog(catalog, kind)
	for key, product in pairs(catalog or {}) do
		local productId = math.floor(tonumber(product.Id) or 0)
		if productId > 0 then
			assert(not productById[productId],
				string.format("Duplicate Zyntra Developer Product ID %d (%s)", productId, key))
			productById[productId] = { Key = key, Kind = kind, Product = product }
		end
	end
end
registerProductCatalog(Config.Products, "Utility")
registerProductCatalog(Config.Donations, "Donation")

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	local entry = productById[receiptInfo.ProductId]
	if not player or not entry or not sessions[player] or not sessions[player].persistent and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = receiptInfo.PurchaseId
	if type(purchaseId) ~= "string" or #purchaseId == 0 or #purchaseId > 128 then
		warn("[Zyntra] Receipt has no valid PurchaseId:", purchaseId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Studio purchases are free test grants, never evidence of paid support.
	-- A live receipt's paid amount is authoritative; catalog prices are not.
	local spent = RunService:IsStudio() and 0 or receiptInfo.CurrencySpent

	local alreadyGranted = false
	local changed = mutate(player, function(data)
		alreadyGranted = false
		for _, id in ipairs(data.ReceiptIds) do
			if id == purchaseId then
				alreadyGranted = true
				return false
			end
		end
		-- Validate before changing any field: a rejected transform adopts its
		-- observed profile locally even though UpdateAsync cancels the write.
		if not isSafeSupportAmount(spent) then
			return false, "Receipt has no valid paid amount.", "error"
		end
		if data.DonationRobux > MAX_SAFE_SUPPORT - data.UtilityRobux
			or spent > MAX_SAFE_SUPPORT - recordedSupportRobux(data) then
			return false, "Recorded support total exceeds the safe limit.", "error"
		end
		local grant = entry.Product.TokenGrant or entry.Product.ReentryGrant
		local balance = entry.Product.TokenGrant and data.Tokens or data.ReentryCredits
		if grant and (not isSafeSupportAmount(grant) or not isSafeSupportAmount(balance)
			or grant > MAX_SAFE_SUPPORT - balance) then
			return false, "Purchase balance exceeds the safe limit.", "error"
		end
		table.insert(data.ReceiptIds, purchaseId)
		if entry.Kind == "Donation" then
			data.DonationRobux += spent
			return true, string.format("Thank you — %d R$ added to your donation total.", spent), "success"
		end
		data.UtilityRobux += spent
		if entry.Product.TokenGrant then
			data.Tokens += entry.Product.TokenGrant
			return true, "+" .. entry.Product.TokenGrant .. " Zyntra Research Tokens", "success"
		elseif entry.Product.ReentryGrant then
			data.ReentryCredits += entry.Product.ReentryGrant
			return true, "+1 Emergency Re-entry credit", "success"
		end
		return true, "Purchase recorded.", "success"
	end)
	if changed or alreadyGranted then
		if changed and entry.Product.ReentryGrant then
			-- The wipe window is fifteen seconds long. A player who buys a credit
			-- inside it has no time to find the button a second time, so a FRESH
			-- grant spends itself the moment it lands if the buyer is still dead in
			-- a live round. Spawned: the receipt is already committed above and must
			-- be acknowledged now, not after a respawn has finished yielding.
			task.spawn(function()
				if reentryEligible(player) then useReentry(player) end
			end)
		end
		local session = sessions[player]
		-- The profile mutation is authoritative. Ranking failure must not delay
		-- acknowledgement, and replay also repairs a missing derived-cache write.
		queueSupportTotalSync(player.UserId, recordedSupportRobux(session and session.data))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
local function finalizePlayerSessionBody(player)
	local loadState = profileLoads[player]
	if loadState then
		-- Cancellation is visible before we wait: a not-yet-started load performs no
		-- claim, while an in-flight UpdateAsync finishes before this finalizer closes
		-- any stable claim it may have committed.
		loadState.cancelled = true
		while not loadState.done do task.wait() end
	end
	local session = sessions[player]
	local muteQueue = dispatchMuteQueues[player]
	-- Accessibility switches wait up to ACCESSIBILITY_WRITE_FLOOR for their
	-- coalesced write, and nothing else on this path writes session.data -- the
	-- final save below carries only the dispatch preference. So commit the pending
	-- targets HERE, while the session is still open (mutateIdempotent refuses a
	-- closing one). Without it a player who flipped a second switch and quit
	-- inside the floor lost that change for good.
	local accessibility = accessibilityQueues[player]
	if session and not session.closing and accessibility and accessibility.dirty then
		accessibility.dirty = false
		writeAccessibilityTargets(player, accessibility.desired)
	end
	local dispatchPersisted = true
	if muteQueue then
		-- Stop a sleeping worker before it can begin an obsolete write. The last
		-- value accepted from the client remains in acceptedDesired for the final
		-- userId-keyed save below.
		muteQueue.closing = true
		muteQueue.desired = nil
		muteQueue.desiredRevision = nil
		muteQueue.desiredIsReassert = nil
	end
	if session then session.closing = true end

	-- Any mutation that acquired the lock before PlayerRemoving is older than
	-- acceptedDesired and must finish first. New mutations reject closing
	-- sessions, so once this drains the direct setter is the final eligible
	-- writer (a higher input epoch still wins inside UpdateAsync).
	while mutationLocks[player] do task.wait() end
	if session then
		-- Deliberately the BASE floor and not the escalated one: this is the
		-- session's single final write, and BindToClose has 25 seconds to fit
		-- every departing player into.
		local remaining = muteQueue
			and MUTE_WRITE_FLOORS[1] - (os.clock() - muteQueue.lastAttemptFinishedAt) or 0
		if remaining > 0 then task.wait(remaining) end
		dispatchPersisted = persistDispatchTargetOnLeave(player, session, muteQueue)
	end
	if loadState and loadState.claimAttempted and loadState.dispatchSessionId
		and (not session or not session.persistent) then
		-- A load can commit its lease and still lose every response. In that case it
		-- intentionally installed no persistent session, so close the stable claim
		-- by identity after all claim attempts have returned.
		dispatchPersisted = closeAbandonedDispatchLoad(
			player.UserId, loadState.dispatchSessionId) and dispatchPersisted
	end
	if session and session.data then
		queueSupportTotalSync(player.UserId, recordedSupportRobux(session.data))
	end
	return dispatchPersisted
end

local function finalizePlayerSession(player)
	local existing = sessionFinalizers[player]
	if existing then
		while not existing.done do task.wait() end
		return existing.success
	end

	local state = { done = false, success = false }
	sessionFinalizers[player] = state
	activeSessionFinalizers += 1
	local ok, result = pcall(finalizePlayerSessionBody, player)
	state.success = ok and result == true
	state.done = true
	activeSessionFinalizers = math.max(0, activeSessionFinalizers - 1)
	if not ok then
		warn("[Zyntra] Player finalization failed for user", player.UserId, result)
	end

	-- Cleanup is unconditional: a failed callback must not leave a local queue or
	-- mutation lock able to write after this finalizer has declared completion.
	sessions[player] = nil
	mutationLocks[player] = nil
	actionTimes[player] = nil
	protectionAttempts[player] = nil
	protectionResponses[player] = nil
	-- Dropping the token is what stops a refund landing for a reservation whose
	-- player is gone: no session, no second credit.
	reentryAttempts[player] = nil
	dispatchMuteQueues[player] = nil
	briefingClaims[player] = nil
	pendingDispatchSnapshots[player.UserId] = nil
	profileLoads[player] = nil
	return state.success
end

Players.PlayerRemoving:Connect(finalizePlayerSession)

game:BindToClose(function()
	serverClosing = true
	-- PlayerRemoving normally begins these writes first. Explicitly joining every
	-- remaining player here also covers shutdown order differences, and the active
	-- counter keeps BindToClose waiting for handlers whose Player already vanished.
	local players = {}
	local seenPlayers = {}
	for player in pairs(sessions) do
		seenPlayers[player] = true
		players[#players + 1] = player
	end
	for player in pairs(profileLoads) do
		if not seenPlayers[player] then
			seenPlayers[player] = true
			players[#players + 1] = player
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if not seenPlayers[player] then
			seenPlayers[player] = true
			players[#players + 1] = player
		end
	end
	local pendingStarts = #players
	for _, player in ipairs(players) do
		task.spawn(function()
			finalizePlayerSession(player)
			pendingStarts -= 1
		end)
	end
	local deadline = os.clock() + 25
	while (pendingStarts > 0 or activeSessionFinalizers > 0) and os.clock() < deadline do
		task.wait(0.05)
	end
end)
