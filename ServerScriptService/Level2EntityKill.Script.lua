-- Close-range kill behavior for the Pool Foam Entity.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ENTITY_NAME = "PoolFoamEntity"
local KILL_DISTANCE = 5.2

local activeToken = 0

local function bindEntity(entity)
	activeToken += 1
	local token = activeToken
	local root = entity.PrimaryPart or entity:FindFirstChild("char1", true) or entity:FindFirstChildWhichIsA("BasePart", true)
	if not root then return end

	local connection
	local elapsed = 0
	connection = RunService.Heartbeat:Connect(function(dt)
		if token ~= activeToken or not entity.Parent or workspace:GetAttribute("SelectedLevel") ~= 2 then
			connection:Disconnect()
			return
		end
		elapsed += dt
		if elapsed < .1 then return end
		elapsed = 0
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") ~= true then
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
				if humanoid and humanoid.Health > 0 and playerRoot and (playerRoot.Position - root.Position).Magnitude <= KILL_DISTANCE then
					humanoid.Health = 0
				end
			end
		end
	end)
end

local function consider(object)
	if object.Name == ENTITY_NAME and object:IsA("Model") then task.defer(bindEntity, object) end
end

workspace.ChildAdded:Connect(consider)
local existing = workspace:FindFirstChild(ENTITY_NAME)
if existing then consider(existing) end

