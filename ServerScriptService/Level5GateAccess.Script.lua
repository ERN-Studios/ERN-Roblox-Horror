-- Level 5 stays sealed for ordinary players. The existing DevAccess allowlist
-- alone grants passage; no collision group, noclip state or Level 4 gate changes.
local Players = game:GetService("Players")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))
local gates = {}
local characters = {}

local function permitted(player)
	return player.Parent == Players and DevAccess.IsAllowed(player)
		and workspace:GetAttribute("Level5DevEnabled") == true
end

local function link(state, part, gate)
	if not part:IsA("BasePart") or not permitted(state.player) then return end
	if not part:IsDescendantOf(state.character) or not gate:IsDescendantOf(workspace) then return end
	local links = state.links[gate]
	if not links then links = {}; state.links[gate] = links end
	if links[part] then return end
	local constraint = Instance.new("NoCollisionConstraint")
	constraint.Name = "Level5DeveloperPassage"
	constraint.Part0, constraint.Part1 = gate, part
	constraint.Parent = part
	links[part] = constraint
end

local function clear(state)
	for _, links in pairs(state.links) do
		for _, constraint in pairs(links) do constraint:Destroy() end
	end
	state.links = {}
end

local function refresh(state)
	clear(state)
	if not permitted(state.player) then return end
	for gate in pairs(gates) do
		for _, part in ipairs(state.character:GetDescendants()) do link(state, part, gate) end
	end
end

local function watchCharacter(player, character)
	if not DevAccess.IsAllowed(player) or characters[character] then return end
	local state = {player = player, character = character, links = {}}
	characters[character] = state
	refresh(state)
	local added = character.DescendantAdded:Connect(function(part)
		for gate in pairs(gates) do link(state, part, gate) end
	end)
	local removing = character.DescendantRemoving:Connect(function(part)
		for _, links in pairs(state.links) do
			local constraint = links[part]
			if constraint then constraint:Destroy(); links[part] = nil end
		end
	end)
	character.Destroying:Once(function()
		added:Disconnect()
		removing:Disconnect()
		clear(state)
		characters[character] = nil
	end)
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(function(character) watchCharacter(player, character) end)
	if player.Character then watchCharacter(player, player.Character) end
end

local function addGate(part)
	if not part:IsA("BasePart") or part.Name ~= "Level5SealedDoor" or gates[part] then return end
	gates[part] = true
	for _, state in pairs(characters) do
		for _, bodyPart in ipairs(state.character:GetDescendants()) do link(state, bodyPart, part) end
	end
end

workspace.DescendantAdded:Connect(addGate)
workspace.DescendantRemoving:Connect(function(part)
	if not gates[part] then return end
	gates[part] = nil
	for _, state in pairs(characters) do
		for _, constraint in pairs(state.links[part] or {}) do constraint:Destroy() end
		state.links[part] = nil
	end
end)
workspace:GetAttributeChangedSignal("Level5DevEnabled"):Connect(function()
	for _, state in pairs(characters) do refresh(state) end
end)
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(player)
	for _, state in pairs(characters) do
		if state.player == player then clear(state) end
	end
end)
for _, part in ipairs(workspace:GetDescendants()) do addGate(part) end
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
