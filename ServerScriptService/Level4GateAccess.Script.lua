-- Keep the coming-soon gate solid and visible, except against developer avatars.
-- Pairwise constraints preserve queue collision groups and the noclip toggle.
local Players = game:GetService("Players")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))
local gates = {}
local characters = {}

local function permitted(player)
	return DevAccess.IsAllowed(player) and workspace:GetAttribute("Level4DevEnabled") == true
end

local function link(state, part, gate)
	if not part:IsA("BasePart") or not permitted(state.player) then return end
	local byPart = state.links[gate]
	if not byPart then byPart = {}; state.links[gate] = byPart end
	if byPart[part] then return end
	local constraint = Instance.new("NoCollisionConstraint")
	constraint.Name = "Level4DeveloperPassage"
	constraint.Part0 = gate
	constraint.Part1 = part
	constraint.Parent = part
	byPart[part] = constraint
end

local function refresh(state)
	for _, byPart in pairs(state.links) do
		for _, constraint in pairs(byPart) do constraint:Destroy() end
	end
	state.links = {}
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
	character.Destroying:Once(function()
		added:Disconnect()
		characters[character] = nil
	end)
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(function(character) watchCharacter(player, character) end)
	if player.Character then watchCharacter(player, player.Character) end
end

local function addGate(part)
	if not part:IsA("BasePart") or part.Name ~= "Level4SealedDoor" then return end
	if gates[part] then return end
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
workspace:GetAttributeChangedSignal("Level4DevEnabled"):Connect(function()
	for _, state in pairs(characters) do refresh(state) end
end)
Players.PlayerAdded:Connect(watchPlayer)
for _, part in ipairs(workspace:GetDescendants()) do addGate(part) end
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
