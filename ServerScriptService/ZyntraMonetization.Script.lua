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
local remotes = ReplicatedStorage:WaitForChild("Remotes")

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
		Version = 1,
		Tokens = RunService:IsStudio() and Config.Studio.StartingTokens or 0,
		StaminaLevel = 0,
		BatteryLevel = 0,
		CompletedLevels = 0,
		ReentryCredits = 0,
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
	if type(data) ~= "table" then data = newProfile() end
	data.Version = 1
	data.Tokens = math.max(0, math.floor(tonumber(data.Tokens) or 0))
	data.StaminaLevel = math.max(0, math.floor(tonumber(data.StaminaLevel) or 0))
	data.BatteryLevel = math.max(0, math.floor(tonumber(data.BatteryLevel) or 0))
	data.CompletedLevels = math.max(0, math.floor(tonumber(data.CompletedLevels) or 0))
	data.ReentryCredits = math.max(0, math.floor(tonumber(data.ReentryCredits) or 0))
	data.Colors = type(data.Colors) == "table" and data.Colors or {}
	data.Colors.Hazmat = colorData(readColor(data.Colors.Hazmat, Config.Colors.HazmatDefault))
	data.Colors.Glowstick = colorData(readColor(data.Colors.Glowstick, Config.Colors.GlowstickDefault))
	data.Grants = type(data.Grants) == "table" and data.Grants or {}
	data.Grants.Supporter = data.Grants.Supporter == true
	data.Grants.AdvancedEquipment = data.Grants.AdvancedEquipment == true
	data.ReceiptIds = type(data.ReceiptIds) == "table" and data.ReceiptIds or {}
	while #data.ReceiptIds > 60 do table.remove(data.ReceiptIds, 1) end
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
	local ownsSupporter = player:GetAttribute("ZyntraOwnsSupporter") == true
	if not ownsAdvanced and not ownsSupporter then return end
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

local function loadProfile(player)
	player:SetAttribute("ZyntraProfileLoaded", false)
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
	player:SetAttribute("ZyntraProfileLoaded", true)
	pushProfile(player)
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
		local ownsAdvanced = player:GetAttribute("ZyntraOwnsAdvancedEquipment") == true
		local ownsSupporter = player:GetAttribute("ZyntraOwnsSupporter") == true
		if not ownsAdvanced and not ownsSupporter then
			pushProfile(player, "Zyntra Supporter or Advanced Equipment is required.", "error")
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
for key, product in pairs(Config.Products) do
	if product.Id > 0 then productById[product.Id] = { Key = key, Product = product } end
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	local entry = productById[receiptInfo.ProductId]
	if not player or not entry or not sessions[player] or not sessions[player].persistent and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
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
		while #data.ReceiptIds > 60 do table.remove(data.ReceiptIds, 1) end
		if entry.Product.TokenGrant then
			data.Tokens += entry.Product.TokenGrant
			return true, "+" .. entry.Product.TokenGrant .. " Zyntra Research Tokens", "success"
		elseif entry.Product.ReentryGrant then
			data.ReentryCredits += entry.Product.ReentryGrant
			return true, "+1 Emergency Re-entry credit", "success"
		end
		return false
	end)
	if changed or alreadyGranted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end
Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
	mutationLocks[player] = nil
	actionTimes[player] = nil
end)
