--!strict
-- Prepared server-only module; not installed in the running game.
-- Capture GetContext BEFORE a yielding inventory reservation, then Activate
-- with that exact context afterward. This module never charges or refunds.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
assert(RunService:IsServer(), "PlayerProtection must run on the server")

local Protection = {}
local DURATION = 5
local states: {[Player]: any} = {}
local roundEpoch = 0
local activated = Instance.new("BindableEvent")
Protection.Activated = activated.Event

local function newEpoch()
	return table.freeze({})
end

local function validPlayer(player: Player): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

function Protection.Clear(player: Player)
	local state = states[player]
	if not state then return end
	state.Active = nil
	state.Epoch = newEpoch()
	player:SetAttribute("PlayerProtectionActive", false)
	player:SetAttribute("PlayerProtectionExpiresAt", 0)
end

local function stateFor(player: Player)
	local state = states[player]
	if state then return state end
	state = {Epoch=newEpoch(), Active=nil, Character=nil, Humanoid=nil, Connections={}}
	states[player] = state
	local function invalidate()
		if states[player] == state then Protection.Clear(player) end
	end
	for _, name in ipairs({"InRound", "Escaped", "Level2_ExitTransition"}) do
		table.insert(state.Connections, player:GetAttributeChangedSignal(name):Connect(invalidate))
	end
	table.insert(state.Connections, player.CharacterAdded:Connect(invalidate))
	table.insert(state.Connections, player.CharacterRemoving:Connect(invalidate))
	Protection.Clear(player)
	return state
end

local function currentLife(player: Player, state: any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if state.Character ~= character or state.Humanoid ~= humanoid then
		Protection.Clear(player)
		if state.DeathConnection then state.DeathConnection:Disconnect() end
		state.Character = character
		state.Humanoid = humanoid
		state.DeathConnection = humanoid and humanoid.Died:Connect(function()
			if states[player] == state and state.Humanoid == humanoid then
				Protection.Clear(player)
			end
		end) or nil
	end
	return character, humanoid
end

local function eligibility(player: Player, character: Model?, humanoid: Humanoid?): string?
	if Workspace:GetAttribute("RoundActive") ~= true then return "RoundInactive" end
	if player:GetAttribute("InRound") ~= true then return "NotInRound" end
	if player:GetAttribute("Escaped") == true
		or player:GetAttribute("Level2_ExitTransition") == true then return "Exited" end
	if not character or not character:IsDescendantOf(Workspace) or not humanoid then
		return "CharacterUnavailable"
	end
	if humanoid.Health <= 0 then return "Dead" end
	return nil
end

function Protection.IsActive(player: Player, character: Model?): boolean
	if not validPlayer(player) then return false end
	local state = states[player]
	if not state or not state.Active then return false end
	local active = state.Active
	local currentCharacter, humanoid = currentLife(player, state)
	if active ~= state.Active or active.Character ~= currentCharacter
		or active.Epoch ~= state.Epoch or active.RoundEpoch ~= roundEpoch
		or eligibility(player, currentCharacter, humanoid)
		or Workspace:GetServerTimeNow() >= active.ExpiresAt then
		Protection.Clear(player)
		return false
	end
	-- A caller holding an older character cannot borrow the new one's effect.
	return character == nil or character == currentCharacter
end

function Protection.GetContext(player: Player): (any?, string?)
	if not validPlayer(player) then return nil, "InvalidPlayer" end
	local state = stateFor(player)
	local character, humanoid = currentLife(player, state)
	if Protection.IsActive(player, character) then return nil, "AlreadyActive" end
	local problem = eligibility(player, character, humanoid)
	if problem then return nil, problem end
	return table.freeze({Character=character, Epoch=state.Epoch, RoundEpoch=roundEpoch}), nil
end

function Protection.Activate(player: Player, context: any): (boolean, any)
	if not validPlayer(player) then return false, "InvalidPlayer" end
	local state = states[player]
	if not state or type(context) ~= "table" then return false, "InvalidContext" end
	local character, humanoid = currentLife(player, state)
	-- Expiry cleanup can replace the epoch; do it before comparing the context.
	if Protection.IsActive(player, character) then return false, "AlreadyActive" end
	if context.Character ~= character or context.Epoch ~= state.Epoch
		or context.RoundEpoch ~= roundEpoch then return false, "StaleContext" end
	local problem = eligibility(player, character, humanoid)
	if problem then return false, problem end
	local active = {
		Character=character, Epoch=state.Epoch, RoundEpoch=roundEpoch,
		ExpiresAt=Workspace:GetServerTimeNow() + DURATION,
	}
	state.Active = active
	player:SetAttribute("PlayerProtectionActive", true)
	player:SetAttribute("PlayerProtectionExpiresAt", active.ExpiresAt)
	local function expire()
		if states[player] ~= state or state.Active ~= active then return end
		local remaining = active.ExpiresAt - Workspace:GetServerTimeNow()
		if remaining > 0 then
			task.delay(remaining, expire)
		else
			Protection.Clear(player)
		end
	end
	task.delay(DURATION, expire)
	activated:Fire(player, character, active.ExpiresAt)
	return true, active.ExpiresAt
end

local function roundChanged()
	-- RoundActive changes fence consecutive rounds even when SelectedLevel is
	-- unchanged. Also observe a direct level change as an invalidation boundary.
	roundEpoch += 1
	for player in pairs(states) do Protection.Clear(player) end
end
Workspace:GetAttributeChangedSignal("RoundActive"):Connect(roundChanged)
Workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(roundChanged)
Players.PlayerRemoving:Connect(function(player)
	local state = states[player]
	if not state then return end
	Protection.Clear(player)
	for _, connection in ipairs(state.Connections) do connection:Disconnect() end
	if state.DeathConnection then state.DeathConnection:Disconnect() end
	states[player] = nil
end)

return table.freeze(Protection)
