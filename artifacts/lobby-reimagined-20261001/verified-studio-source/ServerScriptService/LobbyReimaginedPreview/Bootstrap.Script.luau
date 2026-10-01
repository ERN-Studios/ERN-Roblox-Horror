-- Build after a DEV joins; ordinary public servers avoid the preview bake cost.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))
local started = false
local attempts, retryAt = 0, 0
local function begin(player)
	if started or attempts >= 2 or os.clock() < retryAt or (not RunService:IsStudio() and not DevAccess.IsLevel6PreviewAllowed(player)) then return end
	started = true
	attempts += 1; script:SetAttribute("BuildAttempts",attempts)
	task.spawn(function()
		local began = os.clock()
		local ok, result = pcall(function() return require(script.Parent:WaitForChild("Builder")).Build() end)
		if ok then script:SetAttribute("PreviewReady",true); script:SetAttribute("BuildSeconds",os.clock()-began)
		else
			script:SetAttribute("PreviewError",tostring(result)); warn("[Isolated Lobby Preview] "..tostring(result))
			started = false; retryAt = os.clock()+30
			task.delay(30,function() for _,candidate in ipairs(Players:GetPlayers()) do begin(candidate) end end)
		end
	end)
end
Players.PlayerAdded:Connect(begin)
for _,player in ipairs(Players:GetPlayers()) do begin(player) end
