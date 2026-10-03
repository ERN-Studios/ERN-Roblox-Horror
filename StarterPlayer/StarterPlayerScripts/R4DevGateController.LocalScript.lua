-- R4-only presentation. Existing server preview controllers authorize every entry.
-- These private client shutters do not grant or revoke server developer rights.
-- DevBayAccessGuard separately enforces the two restricted bays on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local MODEL_NAME, FOLDER_NAME = "LobbyReimaginedPreview", "R4ClientDevGates"
local OWNER = "R4DevGateControllerOwned"
local accessModule = ReplicatedStorage:WaitForChild("DevAccess", 10)
local accessOK, access = pcall(function()
	return accessModule and require(accessModule)
end)
local function allowed(level)
	if not accessOK or type(access) ~= "table" then return false end
	local predicate = level == 6 and access.IsLevel6Allowed or access.IsLevel6PreviewAllowed   -- Level 6 is public
	if type(predicate) ~= "function" then return false end
	local ok, result = pcall(predicate, player)
	return ok and result == true
end
local permissions = {[5] = allowed(5), [6] = allowed(6)}
local observed, observeConnections, active = nil, {}, nil
local function disconnect(list)
	for _, connection in ipairs(list) do connection:Disconnect() end
	table.clear(list)
end
local function cleanup()
	if not active then return end
	local previous = active
	active = nil
	disconnect(previous.connections)
	for instance, saved in pairs(previous.hidden) do
		if saved.connection then saved.connection:Disconnect() end
		if instance.Parent and instance[saved.property] == false then
			instance[saved.property] = saved.previous
		end
	end
	if previous.folder.Parent and previous.folder:GetAttribute(OWNER) == true then
		previous.folder:Destroy()
	end
end
local function ready(model)
	return model ~= nil and model:IsA("Model") and model.Name == MODEL_NAME
		and model.Parent == workspace and model:GetAttribute("LobbyReimaginedOwned") == true
		and model:GetAttribute("LobbyVisualRevision") == 4 and model:GetAttribute("Ready") == true
end
local function newPart(parent, name, size, frame, color, colliding)
	local part = Instance.new("Part")
	part.Name, part.Size, part.CFrame, part.Color = name, size, frame, color
	part.Anchored, part.CanCollide = true, colliding == true
	part.CanTouch, part.CanQuery, part.CastShadow = false, colliding == true, true
	part.Material = Enum.Material.Metal
	part:SetAttribute(OWNER, true)
	part.Parent = parent
	return part
end
local function sign(host, message, color, pixels)
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face = "R4 Gate Access Status", Enum.NormalId.Back
	gui.CanvasSize, gui.LightInfluence, gui.Brightness = pixels, 0, 1.15
	gui.AlwaysOnTop, gui.MaxDistance = false, 300
	local label = Instance.new("TextLabel")
	label.Name, label.Size = "Status", UDim2.fromScale(1, 1)
	label.BackgroundTransparency, label.Text = 1, message
	label.TextColor3, label.Font, label.TextScaled = color, Enum.Font.GothamBold, true
	label.Parent = gui
	gui.Parent = host
end
-- Keep the original author-configured development estimates, not this task's progress.
local COMING_SOON_PROGRESS = {[5] = 70, [6] = 30}
local COLORS = {red = Color3.fromRGB(255, 76, 60), zyntraCyan = Color3.fromRGB(73, 245, 204)}
local function addComingSoonBoard(panel, face, level)
	-- Owner's current development progress estimates for the sealed gates.
	local progressPercent = COMING_SOON_PROGRESS[level] or 0

	local gui = Instance.new("SurfaceGui")
	gui.Name = "ComingSoonDisplay"
	gui.Face = face or Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(900, 690)
	gui.LightInfluence = 0
	gui.Brightness = 1.35
	gui.AlwaysOnTop = false
	gui.MaxDistance = 130
	gui:SetAttribute("ComingSoonGateVersion", 3)
	gui:SetAttribute("FutureLevel", level)
	gui:SetAttribute("ProgressPercent", progressPercent)
	gui.Parent = panel

	local background = Instance.new("Frame")
	background.Name = "Screen"
	background.Position = UDim2.fromScale(0.035, 0.045)
	background.Size = UDim2.fromScale(0.93, 0.91)
	background.BackgroundColor3 = Color3.fromRGB(7, 12, 11)
	background.BackgroundTransparency = 0.02
	background.BorderSizePixel = 0
	background.ClipsDescendants = true
	background.Parent = gui

	local backgroundCorner = Instance.new("UICorner")
	backgroundCorner.CornerRadius = UDim.new(0, 28)
	backgroundCorner.Parent = background

	local backgroundBorder = Instance.new("UIStroke")
	backgroundBorder.Name = "RedGateBorder"
	backgroundBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	backgroundBorder.Color = COLORS.red
	backgroundBorder.Thickness = 5
	backgroundBorder.Transparency = 0.18
	backgroundBorder.LineJoinMode = Enum.LineJoinMode.Round
	backgroundBorder.Parent = background

	local backgroundGradient = Instance.new("UIGradient")
	backgroundGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 25, 22)),
		ColorSequenceKeypoint.new(0.58, Color3.fromRGB(8, 14, 12)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 8, 8)),
	})
	backgroundGradient.Rotation = 90
	backgroundGradient.Parent = background

	local kicker = Instance.new("TextLabel")
	kicker.Name = "GateKicker"
	kicker.Position = UDim2.fromScale(0.055, 0.052)
	kicker.Size = UDim2.fromScale(0.61, 0.075)
	kicker.BackgroundTransparency = 1
	kicker.Font = Enum.Font.Code
	kicker.Text = string.format("ZYNTRA TRANSIT // GATE %02d", level)
	kicker.TextColor3 = COLORS.zyntraCyan
	kicker.TextSize = 24
	kicker.TextXAlignment = Enum.TextXAlignment.Left
	kicker.Parent = background

	local upperDivider = Instance.new("Frame")
	upperDivider.Name = "UpperDivider"
	upperDivider.Position = UDim2.fromScale(0.055, 0.175)
	upperDivider.Size = UDim2.fromScale(0.89, 0.006)
	upperDivider.BackgroundColor3 = COLORS.red
	upperDivider.BackgroundTransparency = 0.18
	upperDivider.BorderSizePixel = 0
	upperDivider.Parent = background

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromScale(0.05, 0.235)
	title.Size = UDim2.fromScale(0.9, 0.2)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "COMING SOON"
	title.TextColor3 = COLORS.red
	title.TextSize = 96
	title.TextWrapped = false
	title.Parent = background

	local levelStatus = Instance.new("TextLabel")
	levelStatus.Name = "LevelStatus"
	levelStatus.Position = UDim2.fromScale(0.07, 0.47)
	levelStatus.Size = UDim2.fromScale(0.86, 0.12)
	levelStatus.BackgroundTransparency = 1
	levelStatus.Font = Enum.Font.Code
	levelStatus.Text = "WORK IN PROGRESS"
	levelStatus.TextColor3 = Color3.fromRGB(227, 218, 177)
	levelStatus.TextSize = 56
	levelStatus.TextWrapped = false
	levelStatus.Parent = background

	local progressTrack = Instance.new("Frame")
	progressTrack.Name = "ProgressTrack"
	progressTrack.Position = UDim2.fromScale(0.15, 0.625)
	progressTrack.Size = UDim2.fromScale(0.7, 0.04)
	progressTrack.BackgroundColor3 = Color3.fromRGB(54, 62, 58)
	progressTrack.BackgroundTransparency = 0.22
	progressTrack.BorderSizePixel = 0
	progressTrack.Parent = background
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = progressTrack
	local fill = Instance.new("Frame")
	fill.Name = "ProgressFill"
	fill.Size = UDim2.fromScale(progressPercent / 100, 1)
	fill.BackgroundColor3 = COLORS.red
	fill.BackgroundTransparency = 0.05
	fill.BorderSizePixel = 0
	fill.Parent = progressTrack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local routeStatus = Instance.new("TextLabel")
	routeStatus.Name = "ProgressPercent"
	routeStatus.Position = UDim2.fromScale(0.08, 0.69)
	routeStatus.Size = UDim2.fromScale(0.84, 0.12)
	routeStatus.BackgroundTransparency = 1
	routeStatus.Font = Enum.Font.Code
	routeStatus.Text = string.format("%d%% COMPLETE", progressPercent)
	routeStatus.TextColor3 = Color3.fromRGB(214, 222, 217)
	routeStatus.TextSize = 56
	routeStatus.Parent = background

	return gui
end
local function validOriginalDisplay(gui)
	if not gui:IsA("SurfaceGui") or gui.Name ~= "ComingSoonDisplay"
		or gui:GetAttribute("ComingSoonGateVersion") ~= 3 then return false end
	local screen = gui:FindFirstChild("Screen")
	local title = screen and screen:FindFirstChild("Title")
	local track = screen and screen:FindFirstChild("ProgressTrack")
	local fill = track and track:FindFirstChild("ProgressFill")
	local number = screen and screen:FindFirstChild("ProgressPercent")
	if not title or not title:IsA("TextLabel") or title.Text ~= "COMING SOON"
		or not fill or not fill:IsA("Frame") or not number or not number:IsA("TextLabel") then return false end
	for _, descendant in ipairs(gui:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then return false end
	end
	return true
end
local function comingSoonDisplay(panel, level)
	local original = workspace:FindFirstChild("ServerLobby")
	local doorways = original and original:FindFirstChild("LevelDoorways")
	local template, fallback
	if doorways then
		for _, candidate in ipairs(doorways:GetDescendants()) do
			if validOriginalDisplay(candidate) then
				if candidate:GetAttribute("FutureLevel") == level then template = candidate; break end
				fallback = fallback or candidate
			end
		end
	end
	template = template or fallback
	if not template then
		local gui = addComingSoonBoard(panel, Enum.NormalId.Back, level)
		gui:SetAttribute("TemplateSource", "FreshTunnelLobbyBuilderFallback")
		return gui
	end
	local gui = template:Clone()
	gui.Face, gui.CanvasSize = Enum.NormalId.Back, Vector2.new(900, 690)
	gui.LightInfluence, gui.Brightness, gui.AlwaysOnTop, gui.MaxDistance = 0, 1.35, false, 130
	gui:SetAttribute("FutureLevel", level)
	gui:SetAttribute("ProgressPercent", COMING_SOON_PROGRESS[level])
	gui:SetAttribute("TemplateSource", "OriginalLobbyComingSoonDisplay")
	local screen = gui:FindFirstChild("Screen")
	local kicker = screen:FindFirstChild("GateKicker")
	if kicker and kicker:IsA("TextLabel") then kicker.Text = string.format("ZYNTRA TRANSIT // GATE %02d", level) end
	screen.ProgressTrack.ProgressFill.Size = UDim2.fromScale(COMING_SOON_PROGRESS[level] / 100, 1)
	screen.ProgressPercent.Text = string.format("%d%% COMPLETE", COMING_SOON_PROGRESS[level])
	gui.Parent = panel
	return gui
end

local function mountGates(state)
	local signs = state.model:FindFirstChild("LevelGateSigns")
	if not signs then return end
	for _, level in ipairs({5, 6}) do
		local header = signs:FindFirstChild("LEVEL " .. level .. " Door Header")
		if state.mounted[level] or not header or not header:IsA("BasePart")
			or header:GetAttribute("Level") ~= level then continue end
		state.mounted[level] = true -- Set before parenting parts triggers DescendantAdded.
		local gate = header.CFrame * CFrame.new(0, -17.2, -1.42)
		local container = Instance.new("Model")
		container.Name = "Level" .. level .. " Client Gate"
		container:SetAttribute("LevelNumber", level)
		container:SetAttribute("PreviewAllowed", permissions[level])
		container.Parent = state.folder
		local amber, cyan = Color3.fromRGB(243, 194, 87), Color3.fromRGB(194, 248, 229)
		for _, x in ipairs({-5, 5}) do
			newPart(container, "Status Mount", Vector3.new(.12, .85, .18),
				gate * CFrame.new(x, 19.06, 1.2), Color3.fromRGB(48, 48, 42), false)
		end
		local status = newPart(container, "Mounted Access Subtitle", Vector3.new(14, .75, .08),
			gate * CFrame.new(0, 19.6, 1.46), Color3.fromRGB(20, 24, 22), false)
		sign(status, if permissions[level] then "DEV PREVIEW" else "COMING SOON",
			if permissions[level] then cyan else amber, Vector2.new(900, 80))
		if permissions[level] then continue end
		-- Door clear opening is 19.9 x 15.6 studs; the shutter overlaps its jambs .05 each side.
		newPart(container, "Coming Soon Shutter", Vector3.new(20, 15.6, .35),
			gate * CFrame.new(0, 7.8, 0), Color3.fromRGB(71, 69, 55), true)
		for y = 1, 15, 1 do
			newPart(container, "Shutter Rib", Vector3.new(19.8, .10, .06),
				gate * CFrame.new(0, y, .205), Color3.fromRGB(91, 88, 69), false)
		end
		local notice = newPart(container, "Coming Soon Notice", Vector3.new(15.9, 11.9, .07),
			gate * CFrame.new(0, 7.8, .255), Color3.fromRGB(9, 14, 13), false)
		comingSoonDisplay(notice, level)
		local warning = newPart(container, "Lower Safety Stripe", Vector3.new(19.6, .28, .06),
			gate * CFrame.new(0, .68, .24), amber, false)
		warning.CastShadow = false
	end
end
local function bayLevel(instance, model)
	local current = instance
	while current and current ~= model do
		if current:IsA("Model") then
			if current.Name == "QueueBay_Level5" then return 5 end
			if current.Name == "QueueBay_Level6" then return 6 end
		end
		current = current.Parent
	end
	return nil
end
local function hideBlocked(state, instance)
	local level = bayLevel(instance, state.model)
	if not level or permissions[level] or state.hidden[instance] then return end
	local property
	if instance:IsA("TextLabel") and (instance.Name == "QueueTitle" or instance.Name == "QueueSubtitle") then
		property = "Visible"
	elseif instance:IsA("ProximityPrompt") and instance.Name == "Level" .. level .. "DeveloperPreviewPrompt" then
		property = "Enabled"
	end
	if not property then return end
	local saved = {property = property, previous = instance[property]}
	state.hidden[instance] = saved
	instance[property] = false
	saved.connection = instance:GetPropertyChangedSignal(property):Connect(function()
		if active == state and instance[property] ~= false then instance[property] = false end
	end)
end
local function refresh()
	if not ready(observed) then cleanup(); return end
	if active and active.model == observed then return end
	cleanup()
	-- Refuse a conflicting local owner rather than deleting another developer's work.
	if observed:FindFirstChild(FOLDER_NAME) then warn("[R4 Dev Gate] conflicting local gate folder"); return end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder:SetAttribute(OWNER, true)
	folder:SetAttribute("Level5PreviewAllowed", permissions[5])
	folder:SetAttribute("Level6PreviewAllowed", permissions[6])
	folder.Parent = observed
	local state = {model = observed, folder = folder, connections = {}, hidden = {}, mounted = {}}
	active = state
	for _, instance in ipairs(observed:GetDescendants()) do hideBlocked(state, instance) end
	mountGates(state)
	table.insert(state.connections, observed.DescendantAdded:Connect(function(instance)
		if active ~= state or instance:IsDescendantOf(folder) then return end
		hideBlocked(state, instance)
		mountGates(state)
	end))
	-- Streaming/removal drops connections and restores only locally hidden properties.
	table.insert(state.connections, observed.DescendantRemoving:Connect(function(instance)
		local saved = state.hidden[instance]
		if saved and saved.connection then saved.connection:Disconnect() end
		if saved and instance.Parent and instance[saved.property] == false then
			instance[saved.property] = saved.previous
		end
		state.hidden[instance] = nil
	end))
end
local function observe(model)
	if observed == model then refresh(); return end
	cleanup()
	disconnect(observeConnections)
	observed = model
	if not model then return end
	for _, attribute in ipairs({"Ready", "LobbyReimaginedOwned", "LobbyVisualRevision"}) do
		table.insert(observeConnections, model:GetAttributeChangedSignal(attribute):Connect(refresh))
	end
	table.insert(observeConnections, model.AncestryChanged:Connect(function()
		if observed == model and model.Parent ~= workspace then observe(nil) end
	end))
	refresh()
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == MODEL_NAME and child:IsA("Model") then observe(child) end
end)
observe(workspace:FindFirstChild(MODEL_NAME))
