-- ZyntraMonetization
-- Server-owned persistence, pass grants, developer product receipts and upgrade actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")

local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local store = DataStoreService:GetDataStore(Config.DataStoreName)
local supportStore = DataStoreService:GetOrderedDataStore(Config.SupportLeaderboardDataStoreName)
local remotes = ReplicatedStorage:WaitForChild("Remotes")

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
supportStatus.Value = "CONNECTING TO DONATION RANKINGS"

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
	row.Value = rank == 1 and "NO DONATIONS RECORDED YET" or ""
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
local mutationLocks = {}
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

local function newProfile()
	return {
		Version = 4,
		Tokens = RunService:IsStudio() and Config.Studio.StartingTokens or 0,
		StaminaLevel = 0,
		BatteryLevel = 0,
		CompletedLevels = 0,
		ReentryCredits = 0,
		DonationRobux = 0,
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
	data.Tokens = math.max(0, math.floor(tonumber(data.Tokens) or 0))
	data.StaminaLevel = math.max(0, math.floor(tonumber(data.StaminaLevel) or 0))
	data.BatteryLevel = math.max(0, math.floor(tonumber(data.BatteryLevel) or 0))
	data.CompletedLevels = math.max(0, math.floor(tonumber(data.CompletedLevels) or 0))
	data.ReentryCredits = math.max(0, math.floor(tonumber(data.ReentryCredits) or 0))
	-- Deliberately do not migrate the retired SupportRobux field: that value
	-- included utility purchases. DonationRobux starts a clean, donation-only
	-- accounting stream backed by the v2 OrderedDataStore.
	data.DonationRobux = math.max(0, math.floor(tonumber(data.DonationRobux) or 0))
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

local function publicProfile(data)
	if not data then return nil end
	return {
		Tokens = data.Tokens,
		StaminaLevel = data.StaminaLevel,
		BatteryLevel = data.BatteryLevel,
		StaminaPercent = data.StaminaLevel * 5,
		BatteryPercent = data.BatteryLevel * 5,
		CompletedLevels = data.CompletedLevels,
		ReentryCredits = data.ReentryCredits,
		DonationRobux = data.DonationRobux,
		MuteDispatch = data.Settings.MuteDispatch,
		LobbyBriefingPlayed = data.Settings.LobbyBriefingPlayed,
		HazmatColor = readColor(data.Colors.Hazmat, Config.Colors.HazmatDefault),
		GlowstickColor = readColor(data.Colors.Glowstick, Config.Colors.GlowstickDefault),
		OwnsSupporter = false,
		OwnsAdvancedEquipment = false,
		OwnsCosmeticEquipment = false,
	}
end

local function addSupporterTag(player, character)
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	local old = head:FindFirstChild("ZyntraSupporterTag")
	if old then old:Destroy() end
	if player:GetAttribute("ZyntraOwnsSupporter") ~= true then return end
	-- A lobby badge only: inside a level it would mark its wearer to the whole
	-- party. Ownership and benefits are untouched.
	if player:GetAttribute("InRound") == true then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ZyntraSupporterTag"
	billboard.Size = UDim2.fromOffset(180, 28)
	billboard.StudsOffset = Vector3.new(0, 2.7, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 65
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = "ZYNTRA SUPPORTER"
	label.TextColor3 = Color3.fromRGB(90, 235, 215)
	label.TextStrokeColor3 = Color3.fromRGB(5, 12, 14)
	label.TextStrokeTransparency = 0.25
	label.TextScaled = true
	label.Parent = billboard
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
	if player:GetAttribute("InRound") == true and player:GetAttribute("ZyntraOwnsCosmeticEquipment") == true then
		player:SetAttribute("GlowstickColor", player:GetAttribute("ZyntraGlowstickColor"))
	end
	task.defer(applyHazmatColor, player)
end

local function enrichedPublicProfile(player)
	local session = sessions[player]
	local result = session and publicProfile(session.data) or nil
	if result then
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
		local ok, result = pcall(function()
			return store:UpdateAsync("u_" .. player.UserId, function(current)
				current = normalizeProfile(current)
				changed, message, tone = transform(current)
				return current
			end)
		end)
		success = ok
		if ok then resultData = normalizeProfile(result) else message = tostring(result) end
	end

	if success and resultData then
		session.data = resultData
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
			supportRows[rank].Value = rank == 1 and "NO DONATIONS RECORDED YET" or ""
		end
	end
	-- Historical Marketplace receipts cannot be replayed. This clean v2 board
	-- begins with the dedicated donation products, never utility purchases.
	supportStatus.Value = "DONATIONS SINCE AUG 2026  •  LIVE"
end

local function studioSupportEntries()
	local entries = {}
	for player, session in pairs(sessions) do
		local value = session.data and math.max(0, math.floor(tonumber(session.data.DonationRobux) or 0)) or 0
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
				local value = math.max(0, math.floor(tonumber(record.value) or 0))
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
		supportStatus.Value = "DONATION RANKINGS TEMPORARILY UNAVAILABLE"
	end
	supportRefreshRunning = false
end

local function syncSupportTotal(userId, total)
	total = math.max(0, math.floor(tonumber(total) or 0))
	if RunService:IsStudio() or total <= 0 then return true end
	local ok, err = pcall(function()
		supportStore:UpdateAsync("u_" .. tostring(userId), function(current)
			return math.max(math.floor(tonumber(current) or 0), total)
		end)
	end)
	if not ok then warn("[Zyntra] Support leaderboard sync failed for", userId, err) end
	return ok
end

-- Outer retries are safe only for target-state mutations. Currency, rewards
-- and credits deliberately stay on mutate(): an errored response can have an
-- unknown commit result, so replaying a delta could charge/grant twice.
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
			local ok, result = pcall(function()
				return store:UpdateAsync("u_" .. player.UserId, function(current)
					current = normalizeProfile(current)
					attemptChanged, attemptMessage, attemptTone = transform(current)
					return current
				end)
			end)
			if ok then
				success = true
				changed = attemptChanged == true
				message = attemptMessage
				tone = attemptTone
				resultData = normalizeProfile(result)
				break
			end
			message = tostring(result)
		end
	else
		message = "DataStore is unavailable; try again shortly"
	end

	if success and resultData and sessions[player] == session then
		session.data = resultData
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
	total = math.max(0, math.floor(tonumber(total) or 0))
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
	queueSupportTotalSync(player.UserId, sessions[player] and sessions[player].data.DonationRobux or 0)
end

local function ownsPass(player, pass)
	if RunService:IsStudio() and Config.Studio.GrantAllPasses then return true end
	if not pass or tonumber(pass.Id) == nil or pass.Id <= 0 then return false end
	local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
	if not ok then
		warn("[Zyntra] Pass ownership check failed:", pass.Name, result)
		return false
	end
	return result == true
end

local function refreshPasses(player)
	if not sessions[player] then return end
	local supporter = ownsPass(player, Config.Passes.Supporter)
	local advanced = ownsPass(player, Config.Passes.AdvancedEquipment)
	local cosmetic = ownsPass(player, Config.Passes.CosmeticEquipment)
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
			return true, "Advanced Equipment: +5% stamina and +5% battery", "success"
		end)
	end
	if cosmetic and player:GetAttribute("InRound") == true then
		player:SetAttribute("GlowstickColor", player:GetAttribute("ZyntraGlowstickColor"))
	end
	if player.Character then
		task.defer(addSupporterTag, player, player.Character)
		task.defer(applyHazmatColor, player)
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
	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			local head = character:WaitForChild("Head", 10)
			if head then addSupporterTag(player, character) end
			applyHazmatColor(player)
		end)
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player.Character then task.defer(addSupporterTag, player, player.Character) end
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

local function validColor(value)
	if typeof(value) ~= "Color3" then return nil end
	local h, s, v = value:ToHSV()
	s = math.clamp(s, 0, 0.9)
	v = math.clamp(v, 0.35, 1)
	return Color3.fromHSV(h, s, v)
end

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

		local remaining = 0.75 - (os.clock() - queue.lastAttemptFinishedAt)
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

actionRemote.OnServerEvent:Connect(function(player, action, payload)
	if type(action) ~= "string" or not sessions[player] then return end
	-- Dispatch preference is an idempotent target state with its own coalescing
	-- queue. It must never be silently dropped because the player clicked any
	-- unrelated store action during the shared 120 ms action window.
	if action == "SetMuteDispatch" then
		if type(payload) == "boolean" then queueMuteDispatch(player, payload) end
		return
	end
	local now = os.clock()
	if now - (actionTimes[player] or 0) < 0.12 then return end
	actionTimes[player] = now

	if action == "UpgradeStamina" or action == "UpgradeBattery" then
		mutate(player, function(data)
			if data.Tokens < 1 then return false, "You need 1 Zyntra Research Token.", "error" end
			data.Tokens -= 1
			if action == "UpgradeStamina" then
				data.StaminaLevel += 1
				return true, "Stamina increased by 5%.", "success"
			end
			data.BatteryLevel += 1
			return true, "Battery increased by 5%.", "success"
		end)
	elseif action == "SetHazmatColor" then
		if player:GetAttribute("ZyntraOwnsAdvancedEquipment") ~= true then
			pushProfile(player, "Advanced Equipment is required.", "error")
			return
		end
		local color = validColor(payload)
		if not color then return end
		mutate(player, function(data)
			data.Colors.Hazmat = colorData(color)
			return true, "Hazmat color saved.", "success"
		end)
	elseif action == "SetGlowstickColor" then
		if player:GetAttribute("ZyntraOwnsCosmeticEquipment") ~= true then
			pushProfile(player, "Glowstick Customizer is required.", "error")
			return
		end
		local color = validColor(payload)
		if not color then return end
		mutate(player, function(data)
			data.Colors.Glowstick = colorData(color)
			return true, "Glowstick color saved.", "success"
		end)
	elseif action == "UseReentry" then
		local session = sessions[player]
		if not session or session.data.ReentryCredits < 1 then
			pushProfile(player, "You do not have an Emergency Re-entry credit.", "error")
			return
		end
		local reentry = ServerStorage:FindFirstChild("ZyntraReentry")
		if not reentry or not reentry:IsA("BindableFunction") then
			pushProfile(player, "Re-entry is not available right now.", "error")
			return
		end
		local ok, accepted = pcall(reentry.Invoke, reentry, player)
		if not ok or accepted ~= true then
			pushProfile(player, "Re-entry is only available after death during an active round.", "error")
			return
		end
		mutate(player, function(data)
			if data.ReentryCredits < 1 then return false, "Re-entry credit was not consumed.", "error" end
			data.ReentryCredits -= 1
			return true, "Emergency Re-entry activated.", "success"
		end)
	end
end)

levelCompletedEvent.Event:Connect(function(player)
	if not player or not player:IsA("Player") or not sessions[player] then return end
	mutate(player, function(data)
		data.Tokens += Config.LevelCompletionTokens
		data.CompletedLevels += 1
		return true, "+1 Zyntra Research Token for completing the level.", "success"
	end)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then return end
	for _, pass in pairs(Config.Passes) do
		if pass.Id > 0 and pass.Id == passId then
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

	local donationSpent = 0
	if entry.Kind == "Donation" then
		local rawSpent = tonumber(receiptInfo.CurrencySpent)
		if RunService:IsStudio() and (not rawSpent or rawSpent <= 0) then
			rawSpent = tonumber(entry.Product.Price)
		end
		if not rawSpent or rawSpent ~= rawSpent or rawSpent <= 0 or rawSpent == math.huge then
			warn("[Zyntra] Donation receipt has no valid CurrencySpent:", purchaseId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		donationSpent = math.floor(rawSpent)
	end

	local alreadyGranted = false
	local changed = mutate(player, function(data)
		for _, id in ipairs(data.ReceiptIds) do
			if id == purchaseId then
				alreadyGranted = true
				return false
			end
		end
		table.insert(data.ReceiptIds, purchaseId)
		if entry.Kind == "Donation" then
			data.DonationRobux += donationSpent
			return true, string.format("Thank you — %d R$ added to your donation total.", donationSpent), "success"
		end
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
		if entry.Kind == "Donation" then
			local session = sessions[player]
			local total = session and session.data.DonationRobux or 0
			-- The profile mutation above is the authoritative receipt transaction.
			-- OrderedDataStore is a derived display cache: never leave a paid receipt
			-- retrying just because rankings are throttled or temporarily unavailable.
			queueSupportTotalSync(player.UserId, total)
		end
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
		local remaining = muteQueue
			and 0.75 - (os.clock() - muteQueue.lastAttemptFinishedAt) or 0
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
		queueSupportTotalSync(player.UserId, session.data.DonationRobux)
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
