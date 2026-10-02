Review the planned scoped Roblox lobby changes for correctness and security. Output at most 500 words: actionable blockers with code/function references first, then a short list of essential actual Studio Play checks. Do not assert tests passed.

User requires: only developer accounts see/use the open Level 5 and Level 6 bays; everyone else sees a solid COMING SOON wall and the usual progress display. Main spawn, reset and lobby return must move to the revised lobby next to the original.

Authoritative baseline is a fresh Studio Edit capture dd47c97b-033d-40a3-9ae3-f23d88cacab1 with 227 sources and exact Source/editor parity, full native backup/reopen verified. These are FILE-ONLY candidates; root will perform fresh Source/editor CAS writes and Play tests. There is no implicit Studio developer bypass. Shared DevAccess unchanged. ZenMeister02 is deliberately included in the existing narrower Level6 preview predicate, alongside permanent DEV UIDs. Apply that same predicate uniformly for preview 5 and 6 without widening unrelated dev commands.

Server GameManager CreateParty/JoinStation/StartLevel party paths and QueueBridge public access integration are being prepared separately and are NOT included yet; do not mistake client presentation or physical guard for complete remote authorization. Root must add fail-closed DEV checks at the applicable server entry/party launch paths. R4 builder will Start the new DevBayAccessGuard after owned-ready geometry. New guard sweeps only two exact R4 bay connector/chamber footprints every 0.2 seconds, skips reserved-round servers, uses permanent UID predicate, and redirects denied characters to the tunnel side. InRound and Anchored skips were removed so stale round state does not grant access.

Geometry facts: revised lobby PreviewCenter(220,30,-760). Canonical SpawnLocation remains Workspace.ServerLobby.LobbySpawn, current CFrame position(0,30.4,-860), planned position(220,30.4,-860) lookAt(220,30.4,-760). Canonical pad is invisible, anchored, enabled, CanCollide false. Existing GameManager references its same object for join/reset/return. Level5 and6 header door clear opening is19.9x15.6 studs. Protection guard derives portal transform from the actual owned header CFrame and circular room transform from the actual ChamberFloor; client creates owned local shutters over those openings only.

Inspect async startup/shop completion, preview rights, regular-player visibility/collision, queue/remote bypass requirements, geometry transform assumptions, Source/module lifecycle, streaming acknowledgments on returning from Level6, and whether public spawn remains safe if revised startup fails.

UNCHANGED LIVE DevAccess:
```luau
-- One shared whitelist for every client and server developer command.
-- UserIds are permanent; usernames can change and should never be an authority boundary.
local DevAccess = {}

local ALLOWED_USER_IDS = {
	[40920547] = true,   -- mikkelczar
	[9488575949] = true, -- LaverSneglen
}

-- Timeline seeking is intentionally narrower than the shared developer tools.
local LEVEL3_TIMELINE_OWNER_USER_ID = 9488575949 -- LaverSneglen

function DevAccess.IsAllowed(subject)
	local userId
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		userId = subject.UserId
	elseif type(subject) == "number" then
		userId = subject
	end
	return userId ~= nil and ALLOWED_USER_IDS[userId] == true
end

-- Preview access is narrower than the general developer commands.
function DevAccess.IsLevel6PreviewAllowed(subject)
	if DevAccess.IsAllowed(subject) then return true end
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		return subject.UserId == 11374988579 -- ZenMeister02
	end
	return type(subject) == "number" and subject == 11374988579
end

function DevAccess.IsLevel3TimelineOwner(subject)
	local userId
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		userId = subject.UserId
	elseif type(subject) == "number" then
		userId = subject
	end
	return userId == LEVEL3_TIMELINE_OWNER_USER_ID
end

return DevAccess

```

FULL CLIENT CANDIDATE StarterPlayer.StarterPlayerScripts.R4DevGateController:
```luau
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
	local predicate = access.IsLevel6PreviewAllowed
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

```

LEVEL5 PREVIEW EXACT DIFF (unchanged handlers already server-authenticate every remote/prompt via the shown predicate):
```diff
--- ServerScriptService.Level5PreviewAccess.live
+++ ServerScriptService.Level5PreviewAccess.candidate
@@ -61,11 +61,11 @@
 	if not (exit and exit:IsA("BasePart") and exit:IsDescendantOf(model)) then return nil end
 	return model, exit
 end
 
 local function readyPlayer(player)
-	if player.Parent ~= Players or not DevAccess.IsAllowed(player)
+	if player.Parent ~= Players or not DevAccess.IsLevel6PreviewAllowed(player)
 		or player:GetAttribute("InRound") == true
 		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
 	local character = player.Character
 	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 	local root = humanoid and humanoid.RootPart
@@ -258,11 +258,11 @@
 				bounds, size = model:GetBoundingBox()
 				half = size * 0.5 + Vector3.new(8, 20, 8)
 				boundedModel = model
 			end
 			for _, player in ipairs(Players:GetPlayers()) do
-				if not DevAccess.IsAllowed(player) then
+				if not DevAccess.IsLevel6PreviewAllowed(player) then
 					local character = player.Character
 					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 					local root = humanoid and humanoid.RootPart
 					if root and humanoid.Health > 0 then
 						local p = bounds:PointToObjectSpace(root.Position)

```

FULL NEW SERVER GUARD CANDIDATE:
```luau
-- Authoritative, bounded Level 5/6 lobby bay access; client shutters are presentation.
-- No character collision groups, other levels, campaign progression or map geometry change.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))
local Module = {}
local states = setmetatable({}, {__mode = "k"})
local INTERVAL = .2
local LEVELS = {5, 6}

local function ownedReady(model)
	return typeof(model) == "Instance" and model:IsA("Model")
		and model.Name == "LobbyReimaginedPreview" and model.Parent == workspace
		and model:GetAttribute("LobbyReimaginedOwned") == true
		and model:GetAttribute("LobbyVisualRevision") == 4
		and model:GetAttribute("Ready") == true
end

local function allowed(player)
	local ok, result = pcall(DevAccess.IsLevel6PreviewAllowed, player)
	return ok and result == true
end

local function insideProtectedBay(record, position)
	-- Circular chamber floor and actual portal transform are the only protected volumes.
	-- The rectangle is just the narrow connector/aperture, never the tunnel or sidewalk.
	local gate = record.header.CFrame * CFrame.new(0, -17.2, -1.42)
	local localPoint = gate:PointToObjectSpace(position)
	if math.abs(localPoint.X) <= 10 and localPoint.Y >= -2 and localPoint.Y <= 18
		and localPoint.Z < -.12 and localPoint.Z >= -14 then return true, gate end
	local floor = record.floor
	local delta = position - floor.Position
	local halfThickness = math.min(floor.Size.X, floor.Size.Y, floor.Size.Z) * .5
	local top = floor.Position.Y + halfThickness
	local radius = record.radius
	return delta.X * delta.X + delta.Z * delta.Z <= radius * radius
		and position.Y >= top - 2 and position.Y <= top + 24, gate
end

local function stop(state)
	if state.stopped then return end
	state.stopped = true
	for _, connection in ipairs(state.connections) do connection:Disconnect() end
	table.clear(state.connections)
	if states[state.model] == state then states[state.model] = nil end
end

function Module.Start(model)
	assert(not RunService:IsClient(), "Developer bay guard is server-only")
	assert(ownedReady(model), "Developer bay guard requires the exact ready owned R4 lobby")
	if states[model] then return states[model] end
	local pads = assert(model:FindFirstChild("PreviewQueuePads"), "Missing queue bay folder")
	local signs = assert(model:FindFirstChild("LevelGateSigns"), "Missing gate signs")
	local records = {}
	for _, level in ipairs(LEVELS) do
		local bay = pads:FindFirstChild("QueueBay_Level" .. level)
		local floor = bay and bay:FindFirstChild("ChamberFloor")
		local header = signs:FindFirstChild("LEVEL " .. level .. " Door Header")
		local diameter = bay and bay:GetAttribute("CircularBayDiameter")
		assert(bay and bay:IsA("Model") and floor and floor:IsA("BasePart")
			and floor.Anchored and floor.CanCollide and floor.Parent == bay
			and header and header:IsA("BasePart") and header.Parent == signs
			and header:GetAttribute("Level") == level
			and type(diameter) == "number" and diameter > 40 and diameter < 65,
			"Wrong Level " .. level .. " bay guard geometry")
		table.insert(records, {level = level, bay = bay, floor = floor, header = header,
			radius = diameter * .5 + .5})
	end
	local state = {model = model, records = records, connections = {}, stopped = false, elapsed = 0}
	states[model] = state
	model:SetAttribute("DevBayAccessGuardVersion", 1)
	model:SetAttribute("DevBayProtectedLevels", "5,6")
	model:SetAttribute("DevBayGuardInterval", INTERVAL)
	if model:GetAttribute("DevBayDeniedEntryCount") == nil then model:SetAttribute("DevBayDeniedEntryCount", 0) end
	table.insert(state.connections, model.Destroying:Connect(function() stop(state) end))
	table.insert(state.connections, model.AncestryChanged:Connect(function()
		if model.Parent ~= workspace then stop(state) end
	end))
	table.insert(state.connections, RunService.Heartbeat:Connect(function(deltaTime)
		if state.stopped then return end
		state.elapsed += deltaTime
		if state.elapsed < INTERVAL then return end
		state.elapsed = 0 -- One sweep, never accumulated catch-up work after a long frame.
		if not ownedReady(model) or workspace:GetAttribute("ReservedRoundServer") == true then return end
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Parent ~= Players or allowed(player) then continue end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = humanoid and humanoid.RootPart
			if not root or humanoid.Health <= 0 or not character:IsDescendantOf(workspace) then continue end
			for _, record in ipairs(records) do
				if record.bay.Parent ~= pads or record.floor.Parent ~= record.bay
					or record.header.Parent ~= signs then continue end
				local inside, gate = insideProtectedBay(record, root.Position)
				if not inside then continue end
				-- Let the seat release before moving so a welded chair is never moved with a player.
				if humanoid.SeatPart then humanoid.Sit = false; break end
				local target = (gate * CFrame.new(0, 3, 3.75)).Position
				local outward = Vector3.new(gate.ZVector.X, 0, gate.ZVector.Z)
				local safe = CFrame.lookAt(target, target - outward)
				-- Move the exact live character, preserving its pivot relative to the root.
				character:PivotTo(safe * root.CFrame:ToObjectSpace(character:GetPivot()))
				root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
				model:SetAttribute("DevBayDeniedEntryCount", model:GetAttribute("DevBayDeniedEntryCount") + 1)
				break
			end
		end
	end))
	return state
end

return Module

```

EXACT SPAWN/RETURN DIFF ServerScriptService.GameManager:
```diff
--- ServerScriptService.GameManager.live
+++ ServerScriptService.GameManager.candidate
@@ -588,11 +588,65 @@
  end
  return nil
 end
 
 local function buildLobby()
- return require(script.Parent:WaitForChild("TunnelLobbyBuilder")).Build(LOBBY_CENTER)
+ local lobby, spawn, stations = require(script.Parent:WaitForChild("TunnelLobbyBuilder")).Build(LOBBY_CENTER)
+ if IS_RESERVED_ROUND_SERVER then return lobby, spawn, stations end
+ -- Preserve the canonical pad/reference used by every join, reset and preview return.
+ -- No lobby character is loaded until this synchronous startup wrapper returns.
+ workspace:SetAttribute("LobbySpawnMigrationReady", false)
+ workspace:SetAttribute("LobbySpawnMigrationError", nil)
+ local originalSpawn = spawn.CFrame
+ local ok, problem = pcall(function()
+  local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
+  local builder = folder and folder:FindFirstChild("Builder")
+  assert(builder and builder:IsA("ModuleScript"), "Revised lobby builder is missing")
+  -- The original builder starts its shop asynchronously. The clone must wait
+  -- for its existing completion marker, not merely the early-parented Model.
+  local shop, deadline = nil, os.clock() + 20
+  repeat
+   shop = lobby:FindFirstChild("ZyntraShopDisplay")
+   if shop and shop:IsA("Model") and (tonumber(shop:GetAttribute("ShopItemCount")) or 0) > 0 then break end
+   assert(lobby.Parent == workspace, "Lobby changed while waiting for its shop")
+   task.wait(.05)
+  until os.clock() >= deadline
+  assert(shop and shop:IsA("Model") and (tonumber(shop:GetAttribute("ShopItemCount")) or 0) > 0,
+   "Original lobby shop did not finish before revised lobby startup")
+  local revised = require(builder).Build()
+  assert(revised and revised:IsA("Model") and revised.Parent == workspace
+   and revised.Name == "LobbyReimaginedPreview" and revised:GetAttribute("LobbyReimaginedOwned") == true
+   and revised:GetAttribute("Ready") == true, "Revised lobby is not ready")
+  local center = revised:GetAttribute("PreviewCenter")
+  assert(center == Vector3.new(220, 30, -760), "Unexpected revised lobby center")
+  local position = center + Vector3.new(0, .4, -100)
+  local params = RaycastParams.new()
+  params.FilterType = Enum.RaycastFilterType.Include
+  params.FilterDescendantsInstances = {revised}
+  params.RespectCanCollide = true
+  -- Cover every possible scatter offset; fail safely before moving the pad.
+  for _, dx in ipairs({-2, 0, 2}) do
+   for _, dz in ipairs({-2, 0, 2}) do
+    local hit = workspace:Raycast(position + Vector3.new(dx, 12, dz), Vector3.new(0, -18, 0), params)
+    assert(hit and hit.Instance.CanCollide and hit.Normal.Y > .7
+     and math.abs(hit.Position.Y - position.Y) < 2, "Revised lobby spawn floor is incomplete")
+   end
+  end
+  assert(spawn.Parent == lobby and lobby.Parent == workspace, "Canonical lobby spawn changed during startup")
+  spawn.CFrame = CFrame.lookAt(position, center + Vector3.new(0, .4, 0))
+  spawn:SetAttribute("LobbySpawnFloorModelName", "LobbyReimaginedPreview")
+  spawn:SetAttribute("LobbySpawnRevision", 4)
+  workspace:SetAttribute("LobbySpawnMigrationReady", true)
+ end)
+ if not ok then
+  spawn.CFrame = originalSpawn
+  spawn:SetAttribute("LobbySpawnFloorModelName", nil)
+  spawn:SetAttribute("LobbySpawnRevision", nil)
+  workspace:SetAttribute("LobbySpawnMigrationError", tostring(problem))
+  warn("[GameManager] Revised lobby startup failed; retaining safe original spawn: " .. tostring(problem))
+ end
+ return lobby, spawn, stations
 end
 
 -- Recover automatically if a generated world was accidentally saved into the
 -- place from Edit mode. Without this, Level 1 builds its maze on top of the
 -- saved level while its Entity and puzzle scripts remain stored/disabled.

```

EXACT SPAWN/RETURN DIFF ServerScriptService.LobbyReimaginedPreview.Bootstrap:
```diff
--- ServerScriptService.LobbyReimaginedPreview.Bootstrap.live
+++ ServerScriptService.LobbyReimaginedPreview.Bootstrap.candidate
@@ -1,23 +1,38 @@
--- Build after a DEV joins; ordinary public servers avoid the preview bake cost.
-local Players = game:GetService("Players")
-local RunService = game:GetService("RunService")
-local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))
-local started = false
-local attempts, retryAt = 0, 0
-local function begin(player)
-	if started or attempts >= 2 or os.clock() < retryAt or (not RunService:IsStudio() and not DevAccess.IsLevel6PreviewAllowed(player)) then return end
-	started = true
-	attempts += 1; script:SetAttribute("BuildAttempts",attempts)
-	task.spawn(function()
-		local began = os.clock()
-		local ok, result = pcall(function() return require(script.Parent:WaitForChild("Builder")).Build() end)
-		if ok then script:SetAttribute("PreviewReady",true); script:SetAttribute("BuildSeconds",os.clock()-began)
-		else
-			script:SetAttribute("PreviewError",tostring(result)); warn("[Isolated Lobby Preview] "..tostring(result))
-			started = false; retryAt = os.clock()+30
-			task.delay(30,function() for _,candidate in ipairs(Players:GetPlayers()) do begin(candidate) end end)
-		end
-	end)
+-- GameManager builds and validates the public revised lobby before loading characters.
+-- This script only reports bounded readiness; it never races a second Build transaction.
+if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
+ script:SetAttribute("PreviewReady", false)
+ script:SetAttribute("BuildStatus", "Reserved round server")
+ return
 end
-Players.PlayerAdded:Connect(begin)
-for _,player in ipairs(Players:GetPlayers()) do begin(player) end
+local began, deadline = os.clock(), os.clock() + 60
+script:SetAttribute("BuildAttempts", 0)
+script:SetAttribute("BuildStatus", "Waiting for authoritative lobby startup")
+repeat
+ local model = workspace:FindFirstChild("LobbyReimaginedPreview")
+ local lobby = workspace:FindFirstChild("ServerLobby")
+ local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
+ if workspace:GetAttribute("LobbySpawnMigrationReady") == true and model and model:IsA("Model")
+  and model:GetAttribute("LobbyReimaginedOwned") == true and model:GetAttribute("Ready") == true
+  and spawn and spawn:IsA("SpawnLocation") and spawn:GetAttribute("LobbySpawnRevision") == 4
+  and spawn:GetAttribute("LobbySpawnFloorModelName") == model.Name then
+  script:SetAttribute("PreviewReady", true)
+  script:SetAttribute("PreviewError", nil)
+  script:SetAttribute("BuildSeconds", os.clock() - began)
+  script:SetAttribute("BuildStatus", "Public lobby ready")
+  return
+ end
+ local problem = workspace:GetAttribute("LobbySpawnMigrationError")
+ if type(problem) == "string" and problem ~= "" then
+  script:SetAttribute("PreviewReady", false)
+  script:SetAttribute("PreviewError", problem)
+  script:SetAttribute("BuildStatus", "Safe original spawn retained")
+  warn("[Lobby startup monitor] " .. problem)
+  return
+ end
+ task.wait(.1)
+until os.clock() >= deadline
+script:SetAttribute("PreviewReady", false)
+script:SetAttribute("PreviewError", "Authoritative revised lobby readiness timed out")
+script:SetAttribute("BuildStatus", "Readiness timeout")
+warn("[Lobby startup monitor] Authoritative revised lobby readiness timed out")

```

EXACT SPAWN/RETURN DIFF ServerScriptService.Level6PreviewAccess:
```diff
--- ServerScriptService.Level6PreviewAccess.live
+++ ServerScriptService.Level6PreviewAccess.candidate
@@ -207,11 +207,12 @@
 	if not character or not model or not exit or not spawn or player:GetAttribute("Level6InRound") ~= true
 		or not validReturnPrompt(prompt, exit) or (root.Position - exit.Position).Magnitude > 12 then return end
 	nextUse[player] = math.huge
 	local ok, err = pcall(function()
 		local landing = spawn.Position + Vector3.new(0, 4, 0)
-		if not streamReady(player, landing, "ServerLobby") then error("Lobby streaming confirmation timed out") end
+		local floorModelName = if spawn:GetAttribute("LobbySpawnFloorModelName") == "LobbyReimaginedPreview" then "LobbyReimaginedPreview" else "ServerLobby"
+		if not streamReady(player, landing, floorModelName) then error("Lobby streaming confirmation timed out") end
 		local currentCharacter, currentRoot = playerReady(player)
 		if currentCharacter ~= character or not exit.Parent or not validReturnPrompt(prompt, exit)
 			or (currentRoot.Position - exit.Position).Magnitude > 12 or lobbyPart("LobbySpawn") ~= spawn then return end
 		Runtime.Leave(player)
 		root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero

```

EXACT SPAWN/RETURN DIFF StarterPlayer.StarterPlayerScripts.Level6PreviewTransport:
```diff
--- StarterPlayer.StarterPlayerScripts.Level6PreviewTransport.live
+++ StarterPlayer.StarterPlayerScripts.Level6PreviewTransport.candidate
@@ -32,11 +32,12 @@
 			until os.clock() >= deadline
 		end)
 		return
 	end
 	if type(nonce) ~= "string" or typeof(target) ~= "Vector3"
-		or (modelName ~= "Level 6 Generated World" and modelName ~= "ServerLobby") then return end
+		or (modelName ~= "Level 6 Generated World" and modelName ~= "ServerLobby"
+			and modelName ~= "LobbyReimaginedPreview") then return end
 	generation += 1
 	local token = generation
 	task.spawn(function()
 		pcall(function() player:RequestStreamAroundAsync(target, 8) end)
 		local deadline = os.clock() + 12

```
