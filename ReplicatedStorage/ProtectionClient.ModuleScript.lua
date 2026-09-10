-- Client coordination for the two views of the protection item: Shop and HUD.
-- Private profile responses own inventory; these checks only control the UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
assert(RunService:IsClient(), "ProtectionClient is client-only")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("ZyntraAction")
local getProfile = remotes:WaitForChild("ZyntraGetProfile")
local profileChanged = remotes:WaitForChild("ZyntraProfileChanged")
local changed = Instance.new("BindableEvent")
local Client = {Changed = changed.Event}
local profile, pending
local lastSentAt = -math.huge
local refreshing = false
local profileEventSerial = 0
local message = "Loading inventory..."

local function validCount(value)
	return type(value) == "number" and value == value and value >= 0
		and value <= 9007199254740991 and value % 1 == 0
end

local function validCommand(command)
	return type(command) == "table"
		and (command.Action == "BuyProtection" or command.Action == "UseProtection")
		and type(command.SessionNonce) == "string" and command.SessionNonce ~= ""
		and #command.SessionNonce <= 128 and validCount(command.Revision)
		and command.Revision < 9007199254740991
		and (command.RequestNonce == nil or (type(command.RequestNonce) == "string"
			and #command.RequestNonce > 0 and #command.RequestNonce <= 64))
end

local function sameCommand(a, b)
	return validCommand(a) and validCommand(b) and a.Action == b.Action
		and a.SessionNonce == b.SessionNonce and a.Revision == b.Revision
		and a.RequestNonce == b.RequestNonce
end

local function commandCopy(command)
	return {Action = command.Action, SessionNonce = command.SessionNonce,
		Revision = command.Revision, RequestNonce = command.RequestNonce}
end

local function acceptProfile(data, notification)
	if type(data) ~= "table" or not validCount(data.ProtectionRevision)
		or not validCount(data.ProtectionCharges)
		or type(data.ProtectionSessionNonce) ~= "string" then return end
	-- An initial GetProfile response may arrive after a newer mutation event.
	if profile and data.ProtectionSessionNonce == profile.ProtectionSessionNonce
		and data.ProtectionRevision < profile.ProtectionRevision then return end
	local oldNonce = profile and profile.ProtectionSessionNonce
	profile = data
	if oldNonce and oldNonce ~= data.ProtectionSessionNonce then
		-- A previous session's command must never be rewritten onto a new nonce.
		pending = nil
		lastSentAt = -math.huge
	end
	local response = data.ProtectionLastResponse
	local unrelatedResponse = pending and validCommand(response) and not sameCommand(response, pending)
	if pending and sameCommand(response, pending) then
		if response.Status == "Bought" or response.Status == "Consumed"
			or response.Status == "Refunded" or response.Status == "Rejected" then
			pending = nil
		elseif response.Status == "Pending" then
			message = "Confirming request..."
		end
	end
	local savedPending = data.ProtectionPending
	if not pending and validCommand(savedPending)
		and savedPending.SessionNonce == data.ProtectionSessionNonce then
		pending = commandCopy(savedPending)
	end
	if type(notification) == "string" and notification ~= "" and not unrelatedResponse then
		message = notification
	elseif not pending then
		message = data.ProtectionAvailable and "" or "Inventory unavailable"
	end
	changed:Fire()
	return true
end

function Client.GetState()
	return {
		Charges = profile and profile.ProtectionCharges or 0,
		Tokens = profile and profile.Tokens or 0,
		Available = profile ~= nil and profile.ProtectionAvailable == true,
		Pending = pending and commandCopy(pending) or nil,
		ServerPending = profile ~= nil and profile.ProtectionPending ~= nil,
		CanRetry = pending ~= nil and profile ~= nil
			and pending.SessionNonce == profile.ProtectionSessionNonce
			and os.clock() - lastSentAt >= 2,
		Message = message,
	}
end

local function send(command)
	lastSentAt = os.clock()
	local sentAt = lastSentAt
	message = "Confirming request..."
	changed:Fire()
	task.delay(2, function()
		if pending and sameCommand(pending, command) and lastSentAt == sentAt then changed:Fire() end
	end)
	-- A failed transport call has an uncertain outcome; retain its identity.
	local ok = pcall(function()
		actionRemote:FireServer(command.Action,
			{SessionNonce = command.SessionNonce, Revision = command.Revision,
				RequestNonce = command.RequestNonce})
	end)
	if not ok then message = "Could not confirm. Retry this request."; changed:Fire() end
	return ok
end

function Client.Request(action)
	if action ~= "BuyProtection" and action ~= "UseProtection" then return false, "INVALID_ACTION" end
	if pending or (profile and profile.ProtectionPending) then return false, "PENDING" end
	if not profile or profile.ProtectionAvailable ~= true
		or profile.ProtectionSessionNonce == "" then return false, "UNAVAILABLE" end
	if action == "BuyProtection" and (not validCount(profile.Tokens)
		or profile.Tokens < Config.ProtectionItem.TokenCost) then return false, "INSUFFICIENT_TOKENS" end
	if action == "UseProtection" then
		if profile.ProtectionCharges < 1 then return false, "NO_CHARGES" end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or player:GetAttribute("InRound") ~= true
			or workspace:GetAttribute("RoundActive") ~= true or player:GetAttribute("Escaped") == true then
			return false, "NOT_IN_ROUND"
		end
		local expires = player:GetAttribute("PlayerProtectionExpiresAt")
		if player:GetAttribute("PlayerProtectionActive") == true and type(expires) == "number"
			and expires > workspace:GetServerTimeNow() then return false, "ALREADY_ACTIVE" end
	end
	pending = {Action = action, SessionNonce = profile.ProtectionSessionNonce,
		Revision = profile.ProtectionRevision, RequestNonce = HttpService:GenerateGUID(false)}
	return send(pending)
end

function Client.Retry()
	if not Client.GetState().CanRetry then return false, "NOT_READY" end
	return send(commandCopy(pending))
end

function Client.Refresh()
	if refreshing then return end
	refreshing = true
	local requestSerial = profileEventSerial
	task.spawn(function()
		local ok, data = pcall(function() return getProfile:InvokeServer() end)
		refreshing = false
		if ok and requestSerial == profileEventSerial then acceptProfile(data)
		elseif not profile then message = "Inventory unavailable"; changed:Fire() end
	end)
end

profileChanged.OnClientEvent:Connect(function(data, notification)
	if acceptProfile(data, notification) then profileEventSerial += 1 end
end)
Client.Refresh()
return Client
