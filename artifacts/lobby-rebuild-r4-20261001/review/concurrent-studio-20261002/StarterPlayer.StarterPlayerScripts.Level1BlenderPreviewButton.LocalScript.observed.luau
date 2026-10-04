-- Reuse the native Level 4-6 developer preview prompt interaction.
-- The complete prompt is local to authorized developers; server rechecks entry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local access = ReplicatedStorage:WaitForChild("DevAccess", 10)
local ok, allowed = pcall(function() return access and require(access).IsAllowed(player) end)
if not ok or allowed ~= true then return end
local request = ReplicatedStorage:WaitForChild("Level1BlenderPreviewRequest", 10)
if not request or not request:IsA("RemoteEvent") then return end
local prompts = {}
local nextClick = 0
local ACTION = "ENTER LEVEL 1 FACELIFT PREVIEW"

local function refresh()
	local available = player:GetAttribute("InRound") ~= true
		and player:GetAttribute("Level6InRound") ~= true
		and workspace:GetAttribute("ReservedRoundServer") ~= true
	for _, prompt in pairs(prompts) do prompt.Enabled = available end
end

local function attach(host)
	if host.Name ~= "Level1BlenderPreviewEntry" or not host:IsA("BasePart")
		or host:GetAttribute("Level1BlenderPreviewHost") ~= true or host.Transparency ~= 1
		or prompts[host] then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Level1DeveloperPreviewPrompt"
	prompt.ActionText = ACTION
	prompt.ObjectText = "DEVELOPER PREVIEW"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompts[host] = prompt
	prompt.Parent = host
	local triggerConnection, ancestryConnection, destroyingConnection
	local function cleanup()
		if prompts[host] ~= prompt then return end
		prompts[host] = nil
		if triggerConnection then triggerConnection:Disconnect() end
		if ancestryConnection then ancestryConnection:Disconnect() end
		if destroyingConnection then destroyingConnection:Disconnect() end
		prompt:Destroy()
	end
	triggerConnection = prompt.Triggered:Connect(function()
		if os.clock() < nextClick or not prompt.Enabled or not host:IsDescendantOf(workspace) then return end
		nextClick = os.clock() + 2
		request:FireServer(host)
	end)
	ancestryConnection = host.AncestryChanged:Connect(function()
		if not host:IsDescendantOf(workspace) then cleanup() end
	end)
	destroyingConnection = host.Destroying:Once(cleanup)
	refresh()
end

request.OnClientEvent:Connect(function(accepted, reason)
	if accepted == true then return end
	local message = if reason == "ROUND_BUSY" then "ROUND BUSY · TRY AGAIN"
		elseif reason == "PREVIEW_NOT_READY" then "PREVIEW ASSETS NOT READY"
		else "PREVIEW UNAVAILABLE · TRY AGAIN"
	for _, prompt in pairs(prompts) do prompt.ActionText = message end
	task.delay(3, function()
		for _, prompt in pairs(prompts) do prompt.ActionText = ACTION end
	end)
end)
player:GetAttributeChangedSignal("InRound"):Connect(refresh)
player:GetAttributeChangedSignal("Level6InRound"):Connect(refresh)
workspace:GetAttributeChangedSignal("ReservedRoundServer"):Connect(refresh)
workspace.DescendantAdded:Connect(attach)
for _, instance in ipairs(workspace:GetDescendants()) do attach(instance) end
