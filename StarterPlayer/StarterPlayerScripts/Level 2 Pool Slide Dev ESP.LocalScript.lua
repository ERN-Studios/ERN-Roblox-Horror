-- Developer-only presentation for the second-pump giant. Uses the existing
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
statusText.Size = UDim2.fromOffset(392, 94)
statusText.BackgroundColor3 = Color3.fromRGB(8, 17, 22)
statusText.BackgroundTransparency = .15
statusText.BorderSizePixel = 0
statusText.Font = Enum.Font.GothamMedium
statusText.TextSize = 14
statusText.TextColor3 = COLOR
statusText.TextWrapped = true
statusText.RichText = false -- server diagnostics are text, never UI markup
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
	local world = workspace:FindFirstChild("Level 2 Generated World")
	if not (world and model and model:IsA("Model") and model:IsDescendantOf(world)) then return false end
	local generation = model:GetAttribute("Level2_Generation")
	return generation == nil or generation == world:GetAttribute("Level2_Generation")
end

local function releaseRecord(record)
	record.Billboard:Destroy()
	-- Never delete a generic highlight owned by DevCheats.
	if record.OwnedHighlight then record.OwnedHighlight:Destroy() end
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
		record.OwnedHighlight = highlight
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
	local height = tonumber(model:GetAttribute("AgentHeight")) or 9
	local offset = tonumber(model:GetAttribute("GroundOffset")) or height * .5
	record.Billboard.StudsOffsetWorldSpace = Vector3.new(0, math.max(2, height - offset + 2), 0)
	record.Billboard.Enabled = espEnabled() and adornee ~= nil
	local state = model:GetAttribute("Level2_PoolSlideState") or "ACTIVE"
	local phase = model:GetAttribute("Level2_PoolSlidePhase") or "ACTIVE"
	record.Label.Text = string.format("POOL SLIDE GIANT | %s\n%d studs | %s", phase, rangeTo(model), state)
end

-- Pure formatting: separately table-tested without creating any UI or model.
local function statusMessage(snapshot)
	local phase = snapshot.Phase or "DORMANT"
	local state = snapshot.State or "IDLE"
	if snapshot.Model then
		return string.format("POOL SLIDE GIANT | %s | %s\n%d studs away - follow the cyan marker",
			phase, state, snapshot.Range or 0)
	end
	if snapshot.Enabled == false or state == "DISABLED" then
		return "POOL SLIDE GIANT | DISABLED\nEncounter configuration is off; no spawn is scheduled"
	end
	if not snapshot.RoundReady then
		return "POOL SLIDE GIANT | WAITING FOR ROUND\nNo active generated Level 2 round"
	end
	if state == "REMOVED" then
		return "POOL SLIDE GIANT | REMOVED\nServer reports model removal; it will not respawn this round"
	end
	local navigationFailure = type(snapshot.ContextError) == "string" and snapshot.ContextError ~= ""
	local failure = navigationFailure and snapshot.ContextError or snapshot.Error
	if type(failure) == "string" and failure ~= "" then
		-- Keep the useful first diagnostic line; a full traceback belongs in Output.
		local message = failure:match("[^\r\n]+") or failure
		message = message:gsub("^.-:%d+: ", "") -- trim Lua source/line prefix, not the failure itself
		message = message:gsub("%s+", " ")
		if #message > 180 then message = message:sub(1, 177) .. "..." end
		return string.format("POOL SLIDE GIANT | %s | %s\n%s", phase,
			navigationFailure and "NAVIGATION ERROR" or state, message)
	end
	if snapshot.ContextReady == false then
		return "POOL SLIDE GIANT | PREPARING NAVIGATION\nBuilding the current round's shared route context before spawning"
	end
	local count = math.clamp(math.floor(tonumber(snapshot.Pumps) or 0), 0, 3)
	if count < 2 then
		return string.format("POOL SLIDE GIANT | NOT SPAWNED\nPumps %d/3 - appears after the second lever", count)
	end
	if snapshot.Active then
		return string.format("POOL SLIDE GIANT | %s | LOADING MODEL\nServer reports it active; waiting for model replication", phase)
	end
	if state == "SPAWNING" then
		return string.format("POOL SLIDE GIANT | %s | SPAWNING\nPumps %d/3 - checking a safe spawn position", phase, count)
	end
	if state == "SPAWN_RETRY" then
		return string.format("POOL SLIDE GIANT | %s | SPAWN RETRY\nWaiting for the server's next safe-position attempt", phase)
	end
	return string.format("POOL SLIDE GIANT | %s | %s\nPumps %d/3 - no active model or spawn attempt reported", phase, state, count)
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
			releaseRecord(record)
			records[model] = nil
		end
	end
	statusGui.Enabled = espEnabled() and workspace:GetAttribute("SelectedLevel") == 2
	local state = ReplicatedStorage:FindFirstChild("Level 2 State")
	local function attribute(suffix)
		local value = nearest and nearest:GetAttribute("Level2_PoolSlide" .. suffix)
		if value == nil and state then value = state:GetAttribute("Level2_PoolSlide" .. suffix) end
		return value
	end
	statusText.Text = statusMessage({Model = nearest, Range = nearestRange,
		Enabled = attribute("Enabled"), State = attribute("State"), Phase = attribute("Phase"),
		ContextReady = attribute("NavigationContextReady"), ContextError = attribute("NavigationContextError"),
		Error = attribute("LastError"), Active = attribute("Active") == true
			or workspace:GetAttribute("Level2_PoolSlideActive") == true,
		Pumps = workspace:GetAttribute("Level2Pumps"),
		RoundReady = workspace:GetAttribute("RoundActive") == true
			and workspace:GetAttribute("WorldGenerated") == true})
end

table.insert(connections, player:GetAttributeChangedSignal("DevEspEnabled"):Connect(refresh))
table.insert(connections, CollectionService:GetInstanceAddedSignal("Level2PoolSlideEntity"):Connect(refresh))
table.insert(connections, CollectionService:GetInstanceRemovedSignal("Level2PoolSlideEntity"):Connect(refresh))
script.Destroying:Connect(function()
	stopped = true
	for _, connection in ipairs(connections) do connection:Disconnect() end
	for _, record in pairs(records) do releaseRecord(record) end
	table.clear(records)
	statusGui:Destroy()
end)
refresh()
while not stopped do
	task.wait(.25)
	refresh()
end
