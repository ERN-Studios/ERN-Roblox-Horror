-- Lobby loading cover. Shown from the first frame the client runs Lua and held
-- until the lobby this client will stand in is really there: the server's own
-- lobby-startup markers, the streamed model, ground under the character and
-- every mesh/texture/decal/material the lobby references. Nothing here is a
-- cosmetic timer; the only clocks are stall detectors that OFFER a way out.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local MaterialService = game:GetService("MaterialService")

local player = Players.LocalPlayer
local startedAt = os.clock()

local REVISED_LOBBY = "LobbyReimaginedPreview"
local ORIGINAL_LOBBY = "ServerLobby"
local STALL_SECONDS = 15          -- no progress at all for this long -> offer recovery
local SETTLE_SECONDS = 0.75       -- lobby must stop receiving new instances for this long
local SETTLE_CAP_SECONDS = 10     -- a lobby that never stops changing does not hold the door
local WORKERS = 6
local BATCH = 24
local MINT = Color3.fromRGB(111, 255, 214)
local AMBER = Color3.fromRGB(255, 196, 77)
local INK = Color3.fromRGB(6, 11, 12)

---------------------------------------------------------------------------
-- Cover (no image assets: it has to draw before anything is downloaded)
---------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "LobbyLoadingGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local cover = Instance.new("Frame")
cover.Name = "Cover"
cover.Size = UDim2.fromScale(1, 1)
cover.BackgroundColor3 = INK
cover.BorderSizePixel = 0
cover.Active = true -- swallow clicks meant for the HUD underneath
cover.Parent = gui

local function label(name, text, font, size, colour, position, anchor)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font
	l.Text = text
	l.TextSize = size
	l.TextColor3 = colour
	l.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	l.Position = position
	l.Size = UDim2.new(0.9, 0, 0, size + 10)
	l.TextWrapped = true
	l.Parent = cover
	return l
end

local kicker = label("Kicker", "ZYNTRA  //  FACILITY LINK", Enum.Font.RobotoMono, 14, MINT, UDim2.fromScale(0.5, 0.36))
local title = label("Title", "BACKROOMS: STAY QUIET", Enum.Font.GothamBlack, 40, Color3.fromRGB(236, 244, 240), UDim2.fromScale(0.5, 0.44))
title.Size = UDim2.new(0.9, 0, 0, 96)
local titleLimit = Instance.new("UITextSizeConstraint")
titleLimit.MaxTextSize = 40
titleLimit.MinTextSize = 20
titleLimit.Parent = title
title.TextScaled = true

local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0.5, 0.5)
track.Position = UDim2.fromScale(0.5, 0.56)
track.Size = UDim2.new(0.5, 0, 0, 6)
track.BackgroundColor3 = Color3.fromRGB(24, 40, 40)
track.BorderSizePixel = 0
track.Parent = cover
local trackLimit = Instance.new("UISizeConstraint")
trackLimit.MinSize = Vector2.new(220, 6)
trackLimit.MaxSize = Vector2.new(560, 6)
trackLimit.Parent = track
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = MINT
fill.BorderSizePixel = 0
fill.Parent = track

local status = label("Status", "CONNECTING", Enum.Font.RobotoMono, 15, Color3.fromRGB(190, 214, 206), UDim2.new(0.5, 0, 0.56, 28))
local detail = label("Detail", "", Enum.Font.RobotoMono, 13, Color3.fromRGB(120, 146, 140), UDim2.new(0.5, 0, 0.56, 52))
local tip = label("Tip", "Noise attracts it. Walk. Crouch. Stay quiet.", Enum.Font.Gotham, 14, Color3.fromRGB(120, 146, 140), UDim2.new(0.5, 0, 1, -40))

local recovery = Instance.new("Frame")
recovery.Name = "Recovery"
recovery.AnchorPoint = Vector2.new(0.5, 0)
recovery.Position = UDim2.new(0.5, 0, 0.56, 84)
recovery.Size = UDim2.new(0.9, 0, 0, 48)
recovery.BackgroundTransparency = 1
recovery.Visible = false
recovery.Parent = cover
local row = Instance.new("UIListLayout")
row.FillDirection = Enum.FillDirection.Horizontal
row.HorizontalAlignment = Enum.HorizontalAlignment.Center
row.SortOrder = Enum.SortOrder.LayoutOrder
row.Padding = UDim.new(0, 12)
row.Parent = recovery

local function button(name, text, colour, order)
	local b = Instance.new("TextButton")
	b.Name = name
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(168, 48)
	b.BackgroundColor3 = Color3.fromRGB(12, 24, 24)
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.Text = text
	b.TextSize = 14
	b.TextColor3 = colour
	local stroke = Instance.new("UIStroke")
	stroke.Color = colour
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = b
	b.Parent = recovery
	return b
end
local retryButton = button("Retry", "RETRY", MINT, 1)
local enterButton = button("EnterAnyway", "ENTER ANYWAY", AMBER, 2)
local rejoinButton = button("Rejoin", "REJOIN", Color3.fromRGB(190, 214, 206), 3)

pcall(function() ReplicatedFirst:RemoveDefaultLoadingScreen() end)
gui.Parent = player:WaitForChild("PlayerGui")
player:SetAttribute("LobbyLoadingOpen", true)
player:SetAttribute("LobbyLoadingDone", false)

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local finished = false
local lastProgress = os.clock()
local progress = 0          -- 0..1 shown on the bar
local stage = "CONNECTING"
local retryToken = 0        -- bumping it restarts the current asset pass
local enterAnyway = false
local failedCount = 0

local function touch() lastProgress = os.clock() end
local function setStage(text, fraction, note)
	stage = text
	status.Text = text
	detail.Text = note or ""
	if fraction and fraction > progress then progress = fraction end
	touch()
end
local function devFlag(name)
	return RunService:IsStudio() and workspace:GetAttribute(name) == true
end

task.spawn(function()
	-- The bar eases towards the measured value; it never runs ahead of it.
	while not finished do
		local dt = RunService.RenderStepped:Wait()
		local shown = fill.Size.X.Scale
		fill.Size = UDim2.fromScale(shown + (progress - shown) * math.min(1, dt * 8), 1)
		local stalled = os.clock() - lastProgress > STALL_SECONDS
		if stalled and not recovery.Visible then
			recovery.Visible = true
			detail.Text = "This is taking longer than it should. Still trying."
			detail.TextColor3 = AMBER
		elseif not stalled and recovery.Visible and os.clock() - lastProgress < 1 then
			recovery.Visible = false
			detail.TextColor3 = Color3.fromRGB(120, 146, 140)
		end
	end
end)

retryButton.Activated:Connect(function()
	retryToken += 1
	recovery.Visible = false
	detail.TextColor3 = Color3.fromRGB(120, 146, 140)
	detail.Text = "Retrying."
	touch()
end)
enterButton.Activated:Connect(function() enterAnyway = true end)
rejoinButton.Activated:Connect(function()
	detail.Text = "Rejoining."
	pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
end)

local function waitUntil(predicate)
	-- Yields until the predicate holds or the player chose to enter anyway.
	while not predicate() do
		if enterAnyway then return false end
		task.wait(0.1)
	end
	return true
end

---------------------------------------------------------------------------
-- Asset census: every content id the lobby references, one entry per id
---------------------------------------------------------------------------
local CONTENT_PROPERTIES = {
	MeshPart = { "MeshId", "TextureID" },
	SpecialMesh = { "MeshId", "TextureId" },
	Decal = { "Texture" },
	Texture = { "Texture" },
	SurfaceAppearance = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" },
	MaterialVariant = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" },
	ImageLabel = { "Image" },
	ImageButton = { "Image" },
	ParticleEmitter = { "Texture" },
	Beam = { "Texture" },
	Trail = { "Texture" },
}

local function census(roots, ids, carriers)
	-- Adds what is new since the last call and returns how many ids that was:
	-- shop textures, bay dressing and the HUD's icons arrive after the model.
	local variants = {}
	local total = 0
	local function consider(instance)
		local properties = CONTENT_PROPERTIES[instance.ClassName]
		if properties then
			local fresh = false
			for _, property in ipairs(properties) do
				local ok, value = pcall(function() return instance[property] end)
				if ok and type(value) == "string" and value ~= "" and not ids[value] then
					ids[value] = "pending"
					total += 1
					fresh = true
				end
			end
			if fresh then table.insert(carriers, instance) end
		end
		if instance:IsA("BasePart") and instance.MaterialVariant ~= "" then
			variants[instance.MaterialVariant] = true
		end
	end
	for _, root in ipairs(roots) do
		for _, instance in ipairs(root:GetDescendants()) do consider(instance) end
	end
	for _, variant in ipairs(MaterialService:GetDescendants()) do
		if variant:IsA("MaterialVariant") and variants[variant.Name] then consider(variant) end
	end
	if devFlag("DevLobbyLoadBadAsset") then
		-- Studio-only failure injection: an id that cannot load.
		local broken = Instance.new("Decal")
		broken.Texture = "rbxassetid://999999999999999"
		consider(broken)
	end
	return total
end

local settledCount = 0 -- ids settled so far, across every pass
local function preload(ids, carriers, total)
	-- Returns the number of ids that did not load. Workers pull batches so one
	-- slow request cannot hold the rest; ids the engine never reports on are
	-- settled when their batch returns.
	local failed = 0
	local function settle(id, ok)
		if ids[id] ~= "pending" then return end
		ids[id] = ok and "ok" or "failed"
		settledCount += 1
		if not ok then failed += 1 end
		progress = math.max(progress, 0.3 + 0.7 * math.min(1, settledCount / math.max(1, total)))
		status.Text = string.format("LOADING LOBBY ASSETS  %d / %d", math.min(settledCount, total), total)
		touch()
	end
	local token = retryToken
	local cursor, running = 1, 0
	for _ = 1, WORKERS do
		running += 1
		task.spawn(function()
			while cursor <= #carriers and token == retryToken and not enterAnyway do
				while devFlag("DevLobbyLoadStall") do task.wait(0.2) end
				local batch = table.move(carriers, cursor, math.min(#carriers, cursor + BATCH - 1), 1, {})
				cursor += BATCH
				pcall(function()
					ContentProvider:PreloadAsync(batch, function(id, fetchStatus)
						if token == retryToken then settle(id, fetchStatus == Enum.AssetFetchStatus.Success) end
					end)
				end)
				if token ~= retryToken then break end
				for _, instance in ipairs(batch) do
					for _, property in ipairs(CONTENT_PROPERTIES[instance.ClassName]) do
						local ok, value = pcall(function() return instance[property] end)
						if ok and ids[value] == "pending" then settle(value, true) end
					end
				end
			end
			running -= 1
		end)
	end
	while running > 0 and token == retryToken and not enterAnyway do task.wait(0.1) end
	return failed, token ~= retryToken
end

local function pendingCarriers(ids, carriers, wanted)
	local out = {}
	for _, instance in ipairs(carriers) do
		for _, property in ipairs(CONTENT_PROPERTIES[instance.ClassName]) do
			local ok, value = pcall(function() return instance[property] end)
			if ok and ids[value] == wanted then
				table.insert(out, instance)
				break
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The sequence
---------------------------------------------------------------------------
local function lobbyRoots()
	local roots = {}
	for _, name in ipairs({ REVISED_LOBBY, ORIGINAL_LOBBY }) do
		local model = workspace:FindFirstChild(name)
		if model then table.insert(roots, model) end
	end
	return roots
end

local function groundUnderCharacter()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not character:IsDescendantOf(workspace) then return false end
	local roots = lobbyRoots()
	if #roots == 0 then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = roots
	params.RespectCanCollide = true
	local hit = workspace:Raycast(root.Position + Vector3.yAxis * 2, Vector3.new(0, -16, 0), params)
	return hit ~= nil and hit.Normal.Y > 0.5
end

local function run()
	setStage("CONNECTING", 0.02)
	if not game:IsLoaded() then game.Loaded:Wait() end

	setStage("WAITING FOR THE SERVER", 0.08, "The server is preparing the lobby.")
	waitUntil(function() return workspace:GetAttribute("ReservedRoundServer") ~= nil end)
	if workspace:GetAttribute("ReservedRoundServer") == true then
		-- A round server: the round's own loading cover owns this join.
		return "round"
	end
	waitUntil(function()
		return workspace:GetAttribute("LobbySpawnMigrationReady") == true
			or workspace:GetAttribute("LobbySpawnMigrationError") ~= nil
	end)
	local revised = workspace:GetAttribute("LobbySpawnMigrationReady") == true
	local wantedName = revised and REVISED_LOBBY or ORIGINAL_LOBBY

	setStage("STREAMING THE LOBBY", 0.14, "Receiving the lobby from the server.")
	local spawnPart
	waitUntil(function()
		local original = workspace:FindFirstChild(ORIGINAL_LOBBY)
		spawnPart = original and original:FindFirstChild("LobbySpawn")
		return spawnPart ~= nil
	end)
	if spawnPart then
		task.spawn(function()
			pcall(function() player:RequestStreamAroundAsync(spawnPart.Position, 10) end)
		end)
	end
	waitUntil(function()
		local model = workspace:FindFirstChild(wantedName)
		return model ~= nil and (not revised or model:GetAttribute("Ready") == true)
	end)
	touch()

	-- Objects the server adds while it sets the lobby up (shop boxes, queue bay
	-- dressing, signs) keep arriving after the model itself: wait for quiet.
	setStage("STREAMING THE LOBBY", 0.2, "Receiving objects placed during lobby setup.")
	local lastArrival, arrivals = os.clock(), 0
	local connections = {}
	for _, root in ipairs(lobbyRoots()) do
		table.insert(connections, root.DescendantAdded:Connect(function()
			lastArrival = os.clock()
			arrivals += 1
		end))
	end
	local settleStart = os.clock()
	waitUntil(function()
		if arrivals > 0 then
			detail.Text = string.format("Receiving objects placed during lobby setup (%d).", arrivals)
			touch()
		end
		return os.clock() - lastArrival >= SETTLE_SECONDS or os.clock() - settleStart >= SETTLE_CAP_SECONDS
	end)
	for _, connection in ipairs(connections) do connection:Disconnect() end

	setStage("PLACING YOU IN THE LOBBY", 0.26, "Waiting for your character and the floor under it.")
	waitUntil(groundUnderCharacter)

	local ids, carriers, total = {}, {}, 0
	local function roots()
		local list = lobbyRoots()
		table.insert(list, player:WaitForChild("PlayerGui")) -- the lobby HUD's icons
		return list
	end
	total = census(roots(), ids, carriers)
	setStage(string.format("LOADING LOBBY ASSETS  0 / %d", total), 0.3, "Meshes, textures, decals and materials.")
	local failed, restarted = 0, false
	repeat
		local work = pendingCarriers(ids, carriers, "pending")
		local missed
		missed, restarted = preload(ids, work, total)
		if not restarted then failed += missed end
		-- Anything that arrived while that pass ran is part of the lobby too.
		local arrived = census(roots(), ids, carriers)
		total += arrived
	until (not restarted and arrived == 0) or enterAnyway
	if failed > 0 and not enterAnyway then
		-- One more pass for what failed; a second failure does not hold the door.
		local again = pendingCarriers(ids, carriers, "failed")
		for id, state in pairs(ids) do
			if state == "failed" then
				ids[id] = "pending"
				settledCount -= 1
			end
		end
		detail.Text = string.format("Retrying %d assets that did not load.", failed)
		failed = select(1, preload(ids, again, total))
		for id, state in pairs(ids) do
			if state == "failed" then warn("[LobbyLoading] did not load: " .. id) end
		end
	end
	failedCount = failed
	return "lobby", total
end

local outcome, total = "error", 0
local ok, problem = pcall(function() outcome, total = run() end)
if not ok then warn("[LobbyLoading] " .. tostring(problem)) end

if outcome == "lobby" and not enterAnyway then
	progress = 1
	status.Text = "LOBBY READY"
	detail.Text = failedCount > 0
		and string.format("%d assets could not be loaded and may look wrong.", failedCount) or ""
	task.wait(failedCount > 0 and 1.2 or 0.25)
end
print(string.format("[LobbyLoading] %s in %.1f s, %d assets, %d failed%s", outcome,
	os.clock() - startedAt, total or 0, failedCount, enterAnyway and ", player chose ENTER ANYWAY" or ""))

finished = true
recovery.Visible = false
cover.Active = false
player:SetAttribute("LobbyLoadingOpen", false)
player:SetAttribute("LobbyLoadingDone", true)
local fade = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
TweenService:Create(cover, fade, { BackgroundTransparency = 1 }):Play()
for _, child in ipairs(cover:GetDescendants()) do
	if child:IsA("TextLabel") then
		TweenService:Create(child, fade, { TextTransparency = 1 }):Play()
	elseif child:IsA("Frame") then
		TweenService:Create(child, fade, { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(0.65)
gui:Destroy()
