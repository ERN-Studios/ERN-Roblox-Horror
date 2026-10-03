-- Level 6 CD Dev ESP (renamed to Level 6 Playground Client)
--!strict
-- Level 6 CD Dev ESP. This is local presentation for preview-authorized players;
-- it does not grant any of the server-backed developer commands.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
if not DevAccess.IsLevel6PreviewAllowed(player) then return end

local genericDeveloper = DevAccess.IsAllowed(player)
local WORLD_NAME = "Level 6 Generated World"
local HIGHLIGHT_NAME = "Level6CDDevESP"
local CD_COLOR = Color3.fromRGB(35, 230, 255)

type CDRecord = {
	Model: Model,
	Highlight: Highlight?,
	Connections: {RBXScriptConnection},
}

local records: {[Model]: CDRecord} = {}
local pendingIndex: {[Model]: RBXScriptConnection} = {}
local lifetimeConnections: {RBXScriptConnection} = {}
local previewOnlyEspOn = true

local function inPreview(): boolean
	return player:GetAttribute("Level6InRound") == true
end

local function espEnabled(): boolean
	if not genericDeveloper then return previewOnlyEspOn end
	local sharedState = player:GetAttribute("DevEspEnabled")
	-- DevCheats starts with ESP on. Its attribute can arrive after this script.
	return sharedState == nil or sharedState == true
end

local function shouldHighlight(model: Model): boolean
	if not inPreview() or not espEnabled() or not model:IsDescendantOf(workspace) then return false end
	if typeof(model:GetAttribute("Level6_CDIndex")) ~= "number" then return false end
	if model:GetAttribute("Level6_Collected") == true then return false end
	local state = model:GetAttribute("Level6_CDState")
	return state == "WORLD" or state == "CARRIED" or state == "DROPPED"
end

local function refresh(record: CDRecord)
	local highlight = record.Highlight
	if not shouldHighlight(record.Model) then
		if highlight then highlight:Destroy(); record.Highlight = nil end
		return
	end
	if highlight and highlight.Parent then
		highlight.Enabled = true
		return
	end

	-- Never take over another script's instance with the same name.
	if record.Model:FindFirstChild(HIGHLIGHT_NAME) then return end
	local newHighlight = Instance.new("Highlight")
	newHighlight.Name = HIGHLIGHT_NAME
	newHighlight.Adornee = record.Model
	newHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	newHighlight.FillColor = CD_COLOR
	newHighlight.FillTransparency = 0.55
	newHighlight.OutlineColor = CD_COLOR
	newHighlight.OutlineTransparency = 0
	newHighlight.Enabled = true
	newHighlight.Parent = record.Model
	record.Highlight = newHighlight
end

local function clearPending(model: Model)
	local connection = pendingIndex[model]
	if connection then
		pendingIndex[model] = nil
		connection:Disconnect()
	end
end

local function untrack(model: Model)
	clearPending(model)
	local record = records[model]
	if not record then return end
	records[model] = nil
	for _, connection in ipairs(record.Connections) do connection:Disconnect() end
	if record.Highlight then record.Highlight:Destroy(); record.Highlight = nil end
end

local function track(model: Model)
	if records[model] or typeof(model:GetAttribute("Level6_CDIndex")) ~= "number" then return end
	clearPending(model)
	local record: CDRecord = {Model = model, Highlight = nil, Connections = {}}
	records[model] = record
	for _, attribute in ipairs({"Level6_CDIndex", "Level6_CDState", "Level6_Collected"}) do
		table.insert(record.Connections, model:GetAttributeChangedSignal(attribute):Connect(function()
			refresh(record)
		end))
	end
	refresh(record)
end

local function possibleCDName(name: string): boolean
	return name:match("^Birthday Music CD %d+$") ~= nil
		or name:match("^Carried Birthday Music CD %d+$") ~= nil
		or name:match("^Dropped Birthday Music CD %d+$") ~= nil
end

local function considerModel(model: Model)
	if typeof(model:GetAttribute("Level6_CDIndex")) == "number" then
		track(model)
	elseif possibleCDName(model.Name) and not pendingIndex[model] then
		-- A streamed model may arrive before its attributes. Watch only the three
		-- authored CD model names, not every model in the generated mall.
		pendingIndex[model] = model:GetAttributeChangedSignal("Level6_CDIndex"):Connect(function()
			if typeof(model:GetAttribute("Level6_CDIndex")) == "number" then track(model) end
		end)
	end
end

local function scan(root: Instance)
	if root:IsA("Model") then considerModel(root) end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Model") then considerModel(descendant) end
	end
end

local function refreshAll()
	for _, record in pairs(records) do refresh(record) end
end

local function untrackTree(root: Model)
	untrack(root)
	for model in pairs(records) do
		if model:IsDescendantOf(root) then untrack(model) end
	end
	for model in pairs(pendingIndex) do
		if model:IsDescendantOf(root) then clearPending(model) end
	end
end

local function clearAll()
	for model in pairs(records) do untrack(model) end
	for model in pairs(pendingIndex) do clearPending(model) end
end

table.insert(lifetimeConnections, workspace.DescendantAdded:Connect(function(descendant)
	if not inPreview() or not descendant:IsA("Model") then return end
	if descendant.Name == WORLD_NAME then scan(descendant) else considerModel(descendant) end
end))
table.insert(lifetimeConnections, workspace.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("Model") then untrackTree(descendant) end
end))
table.insert(lifetimeConnections, player:GetAttributeChangedSignal("Level6InRound"):Connect(function()
	if not inPreview() then clearAll(); return end
	local activeWorld = workspace:FindFirstChild(WORLD_NAME)
	if activeWorld then scan(activeWorld) end
	for _, subject in ipairs(Players:GetPlayers()) do
		if subject.Character then scan(subject.Character) end
	end
	refreshAll()
end))

if genericDeveloper then
	table.insert(lifetimeConnections, player:GetAttributeChangedSignal("DevEspEnabled"):Connect(refreshAll))
else
	-- ZenMeister02 is preview-authorized but is not in the general DevCheats
	-- whitelist. B controls only these CD highlights while inside Level 6.
	table.insert(lifetimeConnections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not inPreview() or input.KeyCode ~= Enum.KeyCode.B then return end
		previewOnlyEspOn = not previewOnlyEspOn
		refreshAll()
	end))
end

if inPreview() then
	local world = workspace:FindFirstChild(WORLD_NAME)
	if world then scan(world) end
	for _, subject in ipairs(Players:GetPlayers()) do
		if subject.Character then scan(subject.Character) end
	end
end

script.Destroying:Connect(function()
	for _, connection in ipairs(lifetimeConnections) do connection:Disconnect() end
	clearAll()
end)
