-- EntityKill
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "EntityKill"
-- Kills a player the entity touches and triggers their jumpscare UI immediately.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local remote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
local entity = workspace:WaitForChild("Entity")

local debounce = {}

local function onTouched(hit)
	-- Find the player this body part belongs to.
	-- Accessories can be nested one level deeper.
	local char = hit.Parent
	local player = char and Players:GetPlayerFromCharacter(char)

	if not player and char then
		char = char.Parent
		player = char and Players:GetPlayerFromCharacter(char)
	end

	if not player then
		return
	end

	local hum = char:FindFirstChildOfClass("Humanoid")

	if not hum or hum.Health <= 0 then
		return
	end

	local now = os.clock()

	if debounce[player] and now - debounce[player] < 3 then
		return
	end

	debounce[player] = now

	print("[EntityKill] Entity caught:", player.Name)

	-- Trigger the jumpscare image immediately.
	remote:FireClient(player)

	-- Tiny delay so the client can draw the image before the death/respawn begins.
	task.wait(1.5)

	-- Kill the player.
	if hum and hum.Parent and hum.Health > 0 then
		hum.Health = 0
	end
end

local function connectPart(part)
	if not part:IsA("BasePart") then
		return
	end

	part.Touched:Connect(onTouched)
end

-- Connect all existing Entity body parts.
for _, descendant in ipairs(entity:GetDescendants()) do
	connectPart(descendant)
end

-- Also connect any body parts added later.
entity.DescendantAdded:Connect(connectPart)

Players.PlayerRemoving:Connect(function(player)
	debounce[player] = nil
end)

print("[EntityKill] Script active")