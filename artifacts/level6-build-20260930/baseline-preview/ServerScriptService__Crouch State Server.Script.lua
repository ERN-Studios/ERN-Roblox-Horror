--!strict
-- Crouch State Server
-- Owns the replicated Player.Crouching state used by the all-client pose
-- renderer. The client may request a state, but only this script publishes it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestObject = remotes:WaitForChild("SetCrouching")
assert(requestObject:IsA("RemoteEvent"), "ReplicatedStorage.Remotes.SetCrouching must be a RemoteEvent")
local request = requestObject :: RemoteEvent

local REQUEST_INTERVAL = 1 / 30
local lastRequestAt: {[Player]: number} = {}
local latestRequestSerial: {[Player]: number} = {}
local playerConnections: {[Player]: {RBXScriptConnection}} = {}

local BLOCKED_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true,
}

local function setCrouching(player: Player, active: boolean, responseSerial: number?)
	if player.Parent == Players and player:GetAttribute("Crouching") ~= active then
		player:SetAttribute("Crouching", active)
	end
	-- The owning client predicts immediately, but the server always answers --
	-- including a false->false rejection where no replicated attribute edge
	-- exists to reconcile that prediction.
	if player.Parent == Players then
		request:FireClient(player, active,
			responseSerial or latestRequestSerial[player] or 0)
	end
end

local function characterAllowsCrouch(player: Player): boolean
	if player.Parent ~= Players
		or player:GetAttribute("InRound") ~= true
		or workspace:GetAttribute("RoundActive") ~= true
		or player:GetAttribute("Escaped") == true
		or player:GetAttribute("Spectating") == true
		or player:GetAttribute("Level3_Hiding") == true then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not character.Parent or not humanoid or humanoid.Health <= 0
		or not root or not root:IsA("BasePart") or root.Anchored
		or character:GetAttribute("Level2_ForcedSliding") == true
		or character:GetAttribute("Level2_RagdollServerActive") == true then
		return false
	end
	return BLOCKED_STATES[humanoid:GetState()] ~= true
end

local function disconnectPlayer(player: Player)
	local connections = playerConnections[player]
	if connections then
		for _, connection in ipairs(connections) do connection:Disconnect() end
	end
	playerConnections[player] = nil
	lastRequestAt[player] = nil
	latestRequestSerial[player] = nil
end

local function bindCharacter(player: Player, character: Model)
	setCrouching(player, false)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 8) :: Humanoid?
	end
	if not humanoid or player.Character ~= character then return end

	local connections = playerConnections[player]
	if not connections then return end
	table.insert(connections, humanoid.StateChanged:Connect(function(_, newState)
		if player.Character == character and BLOCKED_STATES[newState] then
			setCrouching(player, false)
		end
	end))
	table.insert(connections, humanoid.Died:Connect(function()
		if player.Character == character then setCrouching(player, false) end
	end))
	table.insert(connections, character:GetAttributeChangedSignal("Level2_RagdollServerActive"):Connect(function()
		if player.Character == character
			and character:GetAttribute("Level2_RagdollServerActive") == true then
			setCrouching(player, false)
		end
	end))
	table.insert(connections, character:GetAttributeChangedSignal("Level2_ForcedSliding"):Connect(function()
		if player.Character == character
			and character:GetAttribute("Level2_ForcedSliding") == true then
			setCrouching(player, false)
		end
	end))
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		table.insert(connections, root:GetPropertyChangedSignal("Anchored"):Connect(function()
			if player.Character == character and root.Anchored then
				setCrouching(player, false)
			end
		end))
	end
end

local function bindPlayer(player: Player)
	disconnectPlayer(player)
	playerConnections[player] = {}
	setCrouching(player, false)

	local connections = playerConnections[player]
	local function clearIfUnavailable()
		if player:GetAttribute("Crouching") == true and not characterAllowsCrouch(player) then
			setCrouching(player, false)
		end
	end
	for _, attribute in ipairs({"InRound", "Escaped", "Spectating", "Level3_Hiding"}) do
		table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(clearIfUnavailable))
	end
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end))
	table.insert(connections, player.CharacterRemoving:Connect(function()
		setCrouching(player, false)
	end))
	if player.Character then task.spawn(bindCharacter, player, player.Character) end
end

request.OnServerEvent:Connect(function(player: Player, requestedState: any, requestSerial: any)
	if typeof(requestSerial) ~= "number" or requestSerial < 1
		or requestSerial > 1e9 or requestSerial % 1 ~= 0 then
		setCrouching(player, false)
		return
	end
	local previousSerial = latestRequestSerial[player] or 0
	if requestSerial <= previousSerial then
		request:FireClient(player, player:GetAttribute("Crouching") == true, requestSerial)
		return
	end
	latestRequestSerial[player] = requestSerial
	if typeof(requestedState) ~= "boolean" then
		setCrouching(player, false, requestSerial)
		return
	end
	local now = os.clock()
	if requestedState == true and now - (lastRequestAt[player] or -math.huge) < REQUEST_INTERVAL then
		request:FireClient(player, player:GetAttribute("Crouching") == true, requestSerial)
		return
	end
	if requestedState == true then lastRequestAt[player] = now end
	setCrouching(player, requestedState == true and characterAllowsCrouch(player), requestSerial)
end)

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(disconnectPlayer)
for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end

workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") == true then return end
	for _, player in ipairs(Players:GetPlayers()) do setCrouching(player, false) end
end)
