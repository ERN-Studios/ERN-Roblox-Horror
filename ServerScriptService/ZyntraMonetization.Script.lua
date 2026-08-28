-- ZyntraMonetization
-- Server-owned persistence, pass grants, developer product receipts and upgrade actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

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
	if data.Settings.LobbyBriefingPlayed == nil then
		-- Anyone with legacy saved data has already logged in before this lifetime
		-- welcome existed; do not replay it once merely because schema v4 deployed.
		data.Settings.LobbyBriefingPlayed = existingProfile
	else
		data.Settings.LobbyBriefingPlayed = data.Settings.LobbyBriefingPlayed == true
	end
	data.Colors = type(data.Colors) == "table" and data.Colors or {}
	data.Colors.Hazmat = colorData(readColor(data.Colors.Hazmat, Config.Colors.HazmatDefault))
	data.Colors.Glowstick = colorData(readColor(data.Colors.Glowstick, Config.Colors.GlowstickDefault))
	data.Grants = type(data.Grants) == "table" and data.Grants or {}
	data.Grants.Supporter = data.Grants.Supporter == true
	data.Grants.AdvancedEquipment = data.Grants.AdvancedEquipment == true
	data.ReceiptIds = type(data.ReceiptIds) == "table" and data.ReceiptIds or {}
	while #data.ReceiptIds > 500 do table.remove(data.ReceiptIds, 1) end
	return data
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

local function acquireMutation(player)
	while mutationLocks[player] do task.wait() end
	mutationLocks[player] = true
end

local function releaseMutation(player)
	mutationLocks[player] = nil
end

local function mutate(player, transform)
	local session = sessions[player]
	if not session then return false, "Profile is not loaded" end
	acquireMutation(player)
	session = sessions[player]
	if not session then
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
	else
		local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		cached = ok and tostring(result) or ("USER " .. tostring(userId))
	end
	supportNameCache[userId] = cached
	return cached
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

claimLobbyBriefingRemote.OnServerInvoke = function(player)
	-- The welcome is a lifetime one-shot. Serialize its claim through the same
	-- profile lock and UpdateAsync path as purchases/settings, and fail quiet if
	-- persistence is unavailable. Returning players therefore cannot hear it due
	-- to a transient fallback profile, and two overlapping requests cannot win.
	local didClaim = false
	local changed = mutate(player, function(data)
		didClaim = data.Settings.LobbyBriefingPlayed ~= true
		if not didClaim then return false end
		data.Settings.LobbyBriefingPlayed = true
		return true
	end)
	return changed == true and didClaim == true
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

local function loadProfile(player)
	player:SetAttribute("ZyntraProfileLoaded", false)
	player:SetAttribute("ZyntraDispatchPreferenceLoaded", false)
	local data
	local persistent = not RunService:IsStudio()
	if RunService:IsStudio() then
		data = newProfile()
	else
		local lastError
		for attempt = 1, 3 do
			local ok, result = pcall(store.GetAsync, store, "u_" .. player.UserId)
			if ok then
				data = result or newProfile()
				lastError = nil
				break
			end
			lastError = result
			task.wait(attempt)
		end
		if lastError then
			warn("[Zyntra] Could not load profile for", player.Name, lastError)
			data = newProfile()
			persistent = false
		end
	end
	if not player.Parent then return end
	sessions[player] = { data = normalizeProfile(data), persistent = persistent }
	applyAttributes(player, sessions[player].data)
	-- Studio's in-memory profile is authoritative for local testing. In a live
	-- server, only expose the dispatch preference after a successful DataStore
	-- read; a fallback profile must not unmute a returning player by accident.
	player:SetAttribute("ZyntraDispatchPreferenceLoaded", RunService:IsStudio() or persistent)
	player:SetAttribute("ZyntraProfileLoaded", true)
	pushProfile(player)
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
	task.spawn(function()
		loadProfile(player)
		if sessions[player] then refreshPasses(player) end
	end)
	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			local head = character:WaitForChild("Head", 10)
			if head then addSupporterTag(player, character) end
			applyHazmatColor(player)
		end)
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
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

actionRemote.OnServerEvent:Connect(function(player, action, payload)
	if type(action) ~= "string" or not sessions[player] then return end
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
	elseif action == "SetMuteDispatch" then
		if type(payload) ~= "boolean" then return end
		mutate(player, function(data)
			if data.Settings.MuteDispatch == payload then return false end
			data.Settings.MuteDispatch = payload
			return true, payload and "Dispatch audio muted." or "Dispatch audio enabled.", "success"
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

	local donationSpent = 0
	if entry.Kind == "Donation" then
		local rawSpent = tonumber(receiptInfo.CurrencySpent)
		if RunService:IsStudio() and (not rawSpent or rawSpent <= 0) then
			rawSpent = tonumber(entry.Product.Price)
		end
		if not rawSpent or rawSpent ~= rawSpent or rawSpent <= 0 or rawSpent == math.huge then
			warn("[Zyntra] Donation receipt has no valid CurrencySpent:", receiptInfo.PurchaseId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		donationSpent = math.floor(rawSpent)
	end

	local alreadyGranted = false
	local changed = mutate(player, function(data)
		for _, id in ipairs(data.ReceiptIds) do
			if id == receiptInfo.PurchaseId then
				alreadyGranted = true
				return false
			end
		end
		table.insert(data.ReceiptIds, receiptInfo.PurchaseId)
		while #data.ReceiptIds > 500 do table.remove(data.ReceiptIds, 1) end
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
Players.PlayerRemoving:Connect(function(player)
	local session = sessions[player]
	if session and session.data then
		queueSupportTotalSync(player.UserId, session.data.DonationRobux)
	end
	sessions[player] = nil
	mutationLocks[player] = nil
	actionTimes[player] = nil
end)
