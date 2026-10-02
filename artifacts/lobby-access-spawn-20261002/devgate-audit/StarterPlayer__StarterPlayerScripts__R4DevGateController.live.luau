-- R4-only presentation. Existing server preview controllers authorize every entry.
-- These private client shutters do not grant or revoke server developer rights.
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
	local predicate = if level == 5 then access.IsAllowed else access.IsLevel6PreviewAllowed
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
		local notice = newPart(container, "Coming Soon Notice", Vector3.new(13, 2, .07),
			gate * CFrame.new(0, 8.6, .255), Color3.fromRGB(23, 25, 21), false)
		sign(notice, "COMING SOON", amber, Vector2.new(900, 140))
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
