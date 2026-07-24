-- EntityKill
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "EntityKill"
-- Kills a player the entity touches and triggers their jumpscare UI.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local remote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
local entity = workspace:WaitForChild("Entity")

local debounce = {}

local function onTouched(hit)
	-- find the player this body part belongs to (accessories nest one level deeper)
	local char = hit.Parent
	local player = char and Players:GetPlayerFromCharacter(char)
	if not player and char then
		char = char.Parent
		player = char and Players:GetPlayerFromCharacter(char)
	end
	if not player then return end

	local hum = char:FindFirstChild("Humanoid")
	if not hum or hum.Health <= 0 then return end

	local now = os.clock()
	if debounce[player] and now - debounce[player] < 3 then return end
	debounce[player] = now

	remote:FireClient(player)
	hum.Health = 0
end

for _, d in ipairs(entity:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Touched:Connect(onTouched)
	end
end

Players.PlayerRemoving:Connect(function(p) debounce[p] = nil end)
