-- Client acknowledgement is a streaming hint; entry authorization stays on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
if not DevAccess.IsLevel6PreviewAllowed(player) then return end
local remote = ReplicatedStorage:WaitForChild("Level6PreviewTransport")
local generation = 0
remote.OnClientEvent:Connect(function(nonce, target, modelName)
	if type(nonce) ~= "string" or typeof(target) ~= "Vector3"
		or (modelName ~= "Level 6 Generated World" and modelName ~= "ServerLobby") then return end
	generation += 1
	local token = generation
	task.spawn(function()
		pcall(function() player:RequestStreamAroundAsync(target, 8) end)
		local deadline = os.clock() + 12
		repeat
			if token ~= generation then return end
			local model = workspace:FindFirstChild(modelName)
			if model then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = {model}
				params.RespectCanCollide = true
				local hit = workspace:Raycast(target, Vector3.new(0, -10, 0), params)
				if hit and hit.Normal.Y > .7 then remote:FireServer(nonce, true); return end
			end
			task.wait(.1)
		until os.clock() >= deadline
	end)
end)
