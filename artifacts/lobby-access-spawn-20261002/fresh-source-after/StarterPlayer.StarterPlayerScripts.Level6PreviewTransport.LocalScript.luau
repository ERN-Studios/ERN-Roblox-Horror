-- Client acknowledgement is a streaming hint; entry authorization stays on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
if not DevAccess.IsLevel6PreviewAllowed(player) then return end
local remote = ReplicatedStorage:WaitForChild("Level6PreviewTransport")
local generation = 0
remote.OnClientEvent:Connect(function(nonce, target, modelName)
	if nonce == "ArrivalFacing" then
		if typeof(target) ~= "CFrame" or modelName ~= "Level 6 Generated World" then return end
		generation += 1
		local token = generation
		local character = player.Character
		task.spawn(function()
			local deadline = os.clock() + 3
			repeat
				if token ~= generation or player.Character ~= character then return end
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and player:GetAttribute("Level6InRound") == true
					and (root.Position - target.Position).Magnitude < 12 then
					local camera = workspace.CurrentCamera
					if not camera or camera.CameraType ~= Enum.CameraType.Custom then return end
					local look = Vector3.new(target.LookVector.X, 0, target.LookVector.Z).Unit
					local focus = root.Position + Vector3.new(0, 1.5, 0)
					local distance = math.clamp((camera.CFrame.Position - camera.Focus.Position).Magnitude, .5, 12)
					camera.CFrame = CFrame.lookAt(focus - look * distance + Vector3.new(0, distance * .2, 0), focus)
					camera.Focus = CFrame.new(focus)
					return
				end
				task.wait(.05)
			until os.clock() >= deadline
		end)
		return
	end
	if type(nonce) ~= "string" or typeof(target) ~= "Vector3"
		or (modelName ~= "Level 6 Generated World" and modelName ~= "ServerLobby"
			and modelName ~= "LobbyReimaginedPreview") then return end
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
