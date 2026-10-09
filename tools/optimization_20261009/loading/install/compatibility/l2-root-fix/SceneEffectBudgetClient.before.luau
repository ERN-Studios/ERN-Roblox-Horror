-- Client room/sector budget for explicitly marked decorative effects.
-- Server gameplay state remains in SceneBudgetWantedEnabled; only local Enabled is budgeted.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local module = ReplicatedStorage:WaitForChild("SceneEffectBudget", 30)
if not module then warn("[SceneEffectBudget] Module unavailable"); return end
local Budget = require(module)
local player = Players.LocalPlayer
local CONFIG = {
	["Level 4 Cinema Blender"] = {ActiveDistance = 320, Hysteresis = 48, ScanRoots = {"Lights", "Props"}},
	["Level 5 Void"] = {ActiveDistance = 384, Hysteresis = 64, ScanRoots = {"Lights"}},
	["Level2PoolroomsMap"] = {ActiveDistance = 320, Hysteresis = 48, ScanRoots = {"Water FX"}},
}
-- The Level 6 arena's galleries share long sight lines; all stay visible.
-- Its union LOD is configured at authoring time, independently of this budget.
local sessions = {}
local connections = {}
local stopped = false
local suspended = workspace:GetAttribute("SceneEffectBudgetDisabled") == true
local elapsed = 0

local function release(model)
	local session = sessions[model]
	if session then
		sessions[model] = nil
		session:Destroy()
	end
end

local function bind(model)
	local config = CONFIG[model.Name]
	if stopped or suspended or not config or not model:IsA("Model") or model.Parent ~= workspace or sessions[model] then return end
	local options = {ActiveDistance = config.ActiveDistance, Hysteresis = config.Hysteresis,
		CellSize = 128, MaxInfluence = 120, PendingLimit = 128, ScanRoots = config.ScanRoots}
	sessions[model] = Budget.new(model, options)
end

local function stop()
	if stopped then return end
	stopped = true
	for _, connection in ipairs(connections) do connection:Disconnect() end
	local models = {}
	for model in pairs(sessions) do table.insert(models, model) end
	for _, model in ipairs(models) do release(model) end
	table.clear(connections)
end

table.insert(connections, workspace.ChildAdded:Connect(bind))
table.insert(connections, workspace.ChildRemoved:Connect(release))
table.insert(connections, script.Destroying:Connect(stop))
table.insert(connections, script:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not script.Enabled then stop() end
end))
for _, model in ipairs(workspace:GetChildren()) do bind(model) end

table.insert(connections, RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.25 then return end
	elapsed = 0
	local disable = workspace:GetAttribute("SceneEffectBudgetDisabled") == true
	if disable ~= suspended then
		suspended = disable
		if disable then
			local models = {}
			for model in pairs(sessions) do table.insert(models, model) end
			for _, model in ipairs(models) do release(model) end
		else
			for _, model in ipairs(workspace:GetChildren()) do bind(model) end
		end
	end
	if suspended then return end
	local views = {}
	local camera = workspace.CurrentCamera
	if camera then table.insert(views, camera.CFrame.Position) end
	local body = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if body then table.insert(views, body.Position) end
	local ok, problem = xpcall(function()
		debug.profilebegin("SceneEffectBudget")
		for _, session in pairs(sessions) do session:Step(views) end
		debug.profileend()
	end, debug.traceback)
	if not ok then
		debug.profileend()
		stop()
		warn("[SceneEffectBudget] Released local suppression: " .. tostring(problem))
	end
end))
