-- Reuse the native Level 4-6 developer preview prompt interaction.
-- The complete prompt is local to authorized developers; server rechecks entry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local access = ReplicatedStorage:WaitForChild("DevAccess", 10)
local ok, allowed = pcall(function() return access and require(access).IsAllowed(player) end)
if not ok or allowed ~= true then return end
local request = ReplicatedStorage:WaitForChild("Level2BlenderPreviewRequest", 10)
if not request or not request:IsA("RemoteEvent") then return end
local prompts = {}
local queueZones = {}
local nextClick = 0
local ACTION = "ENTER LEVEL 2 POOLROOMS PREVIEW"

local function insideQueue()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	if root.CollisionGroup == "QueueMember" then return true end
	for zone in pairs(queueZones) do
		if zone:IsDescendantOf(workspace) then
			local p = zone.CFrame:PointToObjectSpace(root.Position)
			local radius = tonumber(zone:GetAttribute("QueueRadius"))
			if p.Y > -6 and p.Y < 12 and ((radius and p.X*p.X + p.Z*p.Z <= math.min(radius, zone.Size.X*.5, zone.Size.Z*.5)^2)
				or (not radius and math.abs(p.X) <= zone.Size.X*.5 and math.abs(p.Z) <= zone.Size.Z*.5)) then return true end
		end
	end
	return false
end

local function refresh()
	local available = player:GetAttribute("InRound") ~= true
		and player:GetAttribute("Level6InRound") ~= true
		and workspace:GetAttribute("ReservedRoundServer") ~= true
		and not insideQueue()
	for _, prompt in pairs(prompts) do prompt.Enabled = available end
end

-- A visible pedestal under the prompt. Local to authorized developers: this
-- script returns above for everyone else, and nothing here replicates.
local function pedestal(host)
	local model = Instance.new("Model")
	model.Name = "Level2PreviewPedestal"
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {host, player.Character or host}
	local hit = workspace:Raycast(host.Position, Vector3.new(0, -12, 0), params)
	local floorY = hit and hit.Position.Y or host.Position.Y - 4
	local height = math.max(1, host.Position.Y - .6 - floorY)
	local function piece(name, length, diameter, y, color, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(length, diameter, diameter)
		part.CFrame = CFrame.new(host.Position.X, y, host.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		part.Color = color
		part.Material = material
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = model
		return part
	end
	piece("Post", height, 1.8, floorY + height / 2, Color3.fromRGB(236, 232, 220), Enum.Material.SmoothPlastic)
	local button = piece("Button", .5, 1.4, floorY + height + .25, Color3.fromRGB(70, 225, 205), Enum.Material.Neon)
	local sign = Instance.new("BillboardGui")
	sign.Name = "Label"
	sign.Size = UDim2.fromOffset(220, 48)
	sign.StudsOffset = Vector3.new(0, 2.4, 0)
	sign.MaxDistance = 80
	sign.LightInfluence = 0
	sign.Adornee = button
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(235, 255, 250)
	label.TextStrokeTransparency = .4
	label.Text = "LEVEL 2 POOLROOMS\nDEV PREVIEW"
	label.Parent = sign
	sign.Parent = button
	model.Parent = host
	return model
end

local function attach(host)
	if host:IsA("BasePart") and host:GetAttribute("QueueDetectorShape") == "Circle"
		and (host.Name:match("^LaunchZone%d+$") or host:GetAttribute("R3QueueId") ~= nil) then
		queueZones[host] = true
		refresh()
	end
	if host.Name ~= "Level2BlenderPreviewEntry" or not host:IsA("BasePart")
		or host:GetAttribute("Level2BlenderPreviewHost") ~= true or host.Transparency ~= 1
		or prompts[host] then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Level2DeveloperPreviewPrompt"
	prompt.ActionText = ACTION
	prompt.ObjectText = "DEVELOPER PREVIEW"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompts[host] = prompt
	prompt.Parent = host
	local marker = pedestal(host)
	local triggerConnection, ancestryConnection, destroyingConnection
	local function cleanup()
		if prompts[host] ~= prompt then return end
		prompts[host] = nil
		if triggerConnection then triggerConnection:Disconnect() end
		if ancestryConnection then ancestryConnection:Disconnect() end
		if destroyingConnection then destroyingConnection:Disconnect() end
		prompt:Destroy()
		marker:Destroy()
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
		elseif reason == "IN_QUEUE" then "LEAVE THE QUEUE TO PREVIEW"
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
workspace.DescendantRemoving:Connect(function(instance) queueZones[instance] = nil end)
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed >= 0.2 then elapsed = 0; refresh() end
end)
workspace.DescendantAdded:Connect(attach)
for _, instance in ipairs(workspace:GetDescendants()) do attach(instance) end
