-- FlashlightSync
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "FlashlightSync"
-- Keeps the server-authoritative FlashlightOn flag on each character,
-- so EntityAI can read it (client BoolValues don't replicate to the server).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ToggleFlashlight")

local function ensureFlag(char)
	local flag = char:FindFirstChild("FlashlightOn")
	if not flag then
		flag = Instance.new("BoolValue")
		flag.Name = "FlashlightOn"
		flag.Parent = char
	end
	return flag
end

remote.OnServerEvent:Connect(function(player, value)
	if type(value) ~= "boolean" then return end
	local char = player.Character
	if not char then return end
	ensureFlag(char).Value = value
end)

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(ensureFlag)
end)

-- cover characters that spawned before this script connected
for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(ensureFlag)
	if p.Character then ensureFlag(p.Character) end
end
