-- Developer-only presentation for the third-pump giant. Uses the existing
-- phone/B-key ESP state; grants no access, spawns nothing and changes no AI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local player = Players.LocalPlayer
local accessModule = ReplicatedStorage:WaitForChild("DevAccess", 10)
if not accessModule or not require(accessModule).IsAllowed(player) then return end
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then return end

local COLOR = Color3.fromRGB(35, 230, 255)
local records = {}
local stopped = false
local connections = {}
local statusGui = Instance.new("ScreenGui")
statusGui.Name = "PoolSlideDevESPStatus"
statusGui.ResetOnSpawn = false
statusGui.DisplayOrder = 30
statusGui.Enabled = false
statusGui.Parent = playerGui
local statusText = Instance.new("TextLabel")
statusText.Name = "Status"
statusText.Position = UDim2.fromOffset(12, 66)
statusText.Size = UDim2.fromOffset(336, 52)
statusText.BackgroundColor3 = Color3.fromRGB(8, 17, 22)
statusText.BackgroundTransparency = .15
statusText.BorderSizePixel = 0
statusText.Font = Enum.Font.GothamMedium
statusText.TextSize = 14
statusText.TextColor3 = COLOR
statusText.TextWrapped = true
statusText.Text = "POOL SLIDE GIANT"
statusText.Parent = statusGui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 5)
corner.Parent = statusText

local function espEnabled()
	return player:GetAttribute("DevEspEnabled") == true
end

local function rangeTo(model)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local origin = root and root.Position or (camera and camera.CFrame.Position)
	return origin and math.floor((model:GetPivot().Position - origin).Magnitude + .5) or 0
end

local function validModel(model)
	return model and model:IsA("Model") and model:IsDescendantOf(workspace)
end

local function mark(model)
	local record = records[model]
	if not record then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "DevPoolSlideLabel"
		billboard.Size = UDim2.fromOffset(300, 56)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = 0 -- no distance cull, including noclip inspection
		billboard.Enabled = false
		billboard.Parent = model
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(5, 12, 18)
		label.BackgroundTransparency = .25
		label.BorderSizePixel = 0
		label.Font = Enum.Font.GothamBold
		label.TextSize = 15
		label.TextColor3 = COLOR
		label.TextStrokeTransparency = .45
		label.TextWrapped = true
		label.Parent = billboard
		record = {Billboard = billboard, Label = label}
		records[model] = record
	end
	-- Reuse the generic developer highlight instead of spending two Highlight
	-- slots on one creature. DevCheats keeps its existing B/phone toggle logic.
	local highlight = model:FindFirstChild("DevESP")
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "DevESP"
		highlight.Parent = model
	end
	if highlight:IsA("Highlight") then
		highlight.Adornee = model
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillColor = COLOR
		highlight.OutlineColor = COLOR
		highlight.FillTransparency = .45
		highlight.OutlineTransparency = 0
		highlight.Enabled = espEnabled()
	end
	local adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	record.Billboard.Adornee = adornee
	record.Billboard.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("AgentHeight") or 16) + 2, 0)
	record.Billboard.Enabled = espEnabled() and adornee ~= nil
	local state = model:GetAttribute("Level2_PoolSlideState") or "ACTIVE"
	record.Label.Text = string.format("POOL SLIDE GIANT\n%d studs | %s", rangeTo(model), state)
end

local function refresh()
	if stopped then return end
	local found = {}
	for _, model in ipairs(CollectionService:GetTagged("Level2PoolSlideEntity")) do
		if validModel(model) then found[model] = true end
	end
	-- A narrow runtime-path fallback covers tag/descendant replication ordering.
	local world = workspace:FindFirstChild("Level 2 Generated World")
	local runtime = world and world:FindFirstChild("Level 2 Pool Slide Runtime")
	local named = runtime and runtime:FindFirstChild("Level 2 Pool Slide")
	if validModel(named) then found[named] = true end
	local nearest, nearestRange
	for model in pairs(found) do
		mark(model)
		local range = rangeTo(model)
		if not nearestRange or range < nearestRange then nearest, nearestRange = model, range end
	end
	for model, record in pairs(records) do
		if not found[model] then
			record.Billboard:Destroy()
			records[model] = nil
		end
	end
	statusGui.Enabled = espEnabled() and workspace:GetAttribute("SelectedLevel") == 2
	if nearest then
		statusText.Text = string.format("POOL SLIDE GIANT | %s\n%d studs away - follow the cyan marker",
			nearest:GetAttribute("Level2_PoolSlideState") or "ACTIVE", nearestRange)
	else
		local count = math.clamp(tonumber(workspace:GetAttribute("Level2Pumps")) or 0, 0, 3)
		local state = ReplicatedStorage:FindFirstChild("Level 2 State")
		if count < 3 then
			statusText.Text = string.format("POOL SLIDE GIANT | NOT SPAWNED\nPumps %d/3 - appears after the third lever", count)
		elseif state and state:GetAttribute("Level2_PoolSlideActive") == true then
			statusText.Text = "POOL SLIDE GIANT | LOADING MODEL\nServer spawned it; waiting for replication"
		else
			statusText.Text = "POOL SLIDE GIANT | SPAWNING\nPumps 3/3 - checking a safe spawn position"
		end
	end
end

table.insert(connections, player:GetAttributeChangedSignal("DevEspEnabled"):Connect(refresh))
table.insert(connections, CollectionService:GetInstanceAddedSignal("Level2PoolSlideEntity"):Connect(refresh))
table.insert(connections, CollectionService:GetInstanceRemovedSignal("Level2PoolSlideEntity"):Connect(refresh))
script.Destroying:Connect(function()
	stopped = true
	for _, connection in ipairs(connections) do connection:Disconnect() end
	for _, record in pairs(records) do record.Billboard:Destroy() end
	table.clear(records)
	statusGui:Destroy()
end)
refresh()
while not stopped do
	task.wait(.25)
	refresh()
end
