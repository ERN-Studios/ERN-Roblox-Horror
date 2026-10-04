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
	-- TEXTURE_SETTLE_20261004 (owner: "all objects load in but some textures still need a couple of seconds").
	-- PreloadAsync returns when the files are fetched; the renderer then still decodes and uploads them, and
	-- surface/material maps arrive through the same request queue. Hold the cover until that queue has stayed
	-- empty for a moment, then a beat more for the sharp mip levels. Capped, so a slow device is never trapped.
	progress = 0.98
	status.Text = "FINISHING TEXTURES"
	detail.Text = ""
	do
		local began, calm = os.clock(), nil
		while os.clock() - began < 5 do
			if ContentProvider.RequestQueueSize == 0 then
				calm = calm or os.clock()
				if os.clock() - calm >= 1.2 then break end
			else
				calm = nil
			end
			task.wait(0.1)
		end
		task.wait(1.0)
	end
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

---------------------------------------------------------------------------
-- LEVEL_LOADING_20261004 (owner: "make sure a similar loading screen happens for every level, timed with the
-- load speed", "and change its colour scheme a little with the level you are in").
--
-- The same cover as the lobby's - kicker, title, bar, status, detail, tip - in each level's own colours, raised
-- for every way into a level and dropped by what has really loaded, not by a timer:
--   ROUNDS (Levels 1-4, GameManager): it stands over RoundUI's own cover (`RoundGui.LevelLoading`) for exactly
--     as long as that is up - the server drops it when the world is built and the party is released - and
--     preloads whatever of the level has reached this client meanwhile. On a reserved round server it is up
--     from the first frame, before RoundUI exists. RoundUI publishes the level as the attribute `LoadingLevel`.
--   LIVE LEVELS (5 and 6, on the lobby server): raised when the level marks the player, held until the body is
--     in the level, the model has stopped arriving, there is ground under the feet, the level's meshes and
--     textures are fetched and the request queue has gone quiet.
-- Every wait has a cap, so nobody is ever held behind it. Client attribute `LevelLoadingOpen` while it is up.
---------------------------------------------------------------------------
do
	local LEVELS = {
		[0] = {name = "ENTERING ANOMALOUS SPACE", kicker = "ZYNTRA  //  DESCENT", accent = Color3.fromRGB(111, 255, 214), ink = Color3.fromRGB(6, 11, 12),
			tip = "Noise attracts it. Walk. Crouch. Stay quiet."},
		[1] = {name = "LEVEL 1  ·  THE OFFICE", kicker = "ZYNTRA  //  DESCENT 01", accent = Color3.fromRGB(236, 198, 84), ink = Color3.fromRGB(13, 11, 4),
			tip = "Noise attracts it. Walk. Crouch. Stay quiet."},
		[2] = {name = "LEVEL 2  ·  THE POOLROOMS", kicker = "ZYNTRA  //  DESCENT 02", accent = Color3.fromRGB(105, 222, 238), ink = Color3.fromRGB(3, 9, 12),
			tip = "Start the pumps. Watch the water."},
		[3] = {name = "LEVEL 3  ·  THE MALL", kicker = "ZYNTRA  //  DESCENT 03", accent = Color3.fromRGB(255, 150, 72), ink = Color3.fromRGB(13, 7, 3),
			tip = "Under a table is safe, until it checks."},
		[4] = {name = "LEVEL 4  ·  THE CINEMA", kicker = "ZYNTRA  //  DESCENT 04", accent = Color3.fromRGB(255, 84, 212), ink = Color3.fromRGB(10, 4, 14),
			tip = "The power is out. Your flashlight is all you have."},
		[5] = {name = "LEVEL 5  ·  THE VOID ROOMS", kicker = "ZYNTRA  //  DESCENT 05", accent = Color3.fromRGB(244, 160, 198), ink = Color3.fromRGB(11, 5, 9),
			tip = "Everyone on the plate. Do not fall."},
		[6] = {name = "LEVEL 6  ·  THE PLAYGROUND", kicker = "ZYNTRA  //  DESCENT 06", accent = Color3.fromRGB(255, 212, 64), ink = Color3.fromRGB(13, 5, 4),
			tip = "It is counting. Find a place to hide."},
	}
	local LIVE_MODELS = {[5] = "Level 5 Void", [6] = "Level 6 Indoor Playground"}
	local playerGui = player:WaitForChild("PlayerGui")
	local up = nil                                  -- the cover on screen, or nil

	local function raise(level)
		local style = LEVELS[level] or LEVELS[0]
		local screen = Instance.new("ScreenGui")
		screen.Name, screen.IgnoreGuiInset, screen.ResetOnSpawn, screen.DisplayOrder = "LevelLoadingGui", true, false, 99990
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		local sheet = Instance.new("Frame")
		sheet.Name, sheet.Size, sheet.BackgroundColor3, sheet.BorderSizePixel, sheet.Active = "Cover", UDim2.fromScale(1, 1), style.ink, 0, true
		sheet.Parent = screen
		local function line(name, text, font, size, colour, position)
			local l = Instance.new("TextLabel")
			l.Name, l.BackgroundTransparency, l.Font, l.Text, l.TextSize, l.TextColor3 = name, 1, font, text, size, colour
			l.AnchorPoint, l.Position, l.Size, l.TextWrapped = Vector2.new(0.5, 0.5), position, UDim2.new(0.9, 0, 0, size + 10), true
			l.Parent = sheet
			return l
		end
		local kick = line("Kicker", style.kicker, Enum.Font.RobotoMono, 14, style.accent, UDim2.fromScale(0.5, 0.36))
		local name = line("Title", style.name, Enum.Font.GothamBlack, 40, Color3.fromRGB(236, 244, 240), UDim2.fromScale(0.5, 0.44))
		name.Size, name.TextScaled = UDim2.new(0.9, 0, 0, 96), true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize, limit.MinTextSize = 40, 20
		limit.Parent = name
		local rail = Instance.new("Frame")
		rail.Name, rail.AnchorPoint, rail.Position, rail.Size = "Track", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.56), UDim2.new(0.5, 0, 0, 6)
		rail.BackgroundColor3, rail.BorderSizePixel = style.accent:Lerp(style.ink, 0.82), 0
		rail.Parent = sheet
		local railLimit = Instance.new("UISizeConstraint")
		railLimit.MinSize, railLimit.MaxSize = Vector2.new(220, 6), Vector2.new(560, 6)
		railLimit.Parent = rail
		local bar = Instance.new("Frame")
		bar.Name, bar.Size, bar.BackgroundColor3, bar.BorderSizePixel = "Fill", UDim2.fromScale(0, 1), style.accent, 0
		bar.Parent = rail
		local state = line("Status", "CONNECTING", Enum.Font.RobotoMono, 15, style.accent:Lerp(Color3.new(1, 1, 1), 0.55), UDim2.new(0.5, 0, 0.56, 28))
		local note = line("Detail", "", Enum.Font.RobotoMono, 13, style.accent:Lerp(style.ink, 0.45), UDim2.new(0.5, 0, 0.56, 52))
		local hint = line("Tip", style.tip, Enum.Font.Gotham, 14, style.accent:Lerp(style.ink, 0.4), UDim2.new(0.5, 0, 1, -40))
		screen.Parent = playerGui
		player:SetAttribute("LevelLoadingOpen", true)
		local self = {level = level, shown = 0, target = 0, open = true, startedAt = os.clock()}
		task.spawn(function()                          -- the bar eases toward the measured value and never runs ahead of it
			while self.open do
				local dt = RunService.RenderStepped:Wait()
				self.shown += (self.target - self.shown) * math.min(1, dt * 8)
				bar.Size = UDim2.fromScale(self.shown, 1)
			end
		end)
		function self.stage(text, fraction, detailText)
			state.Text, note.Text = text, detailText or ""
			if fraction and fraction > self.target then self.target = fraction end
		end
		function self.restyle(toLevel)
			local to = LEVELS[toLevel]
			if not to or toLevel == self.level then return end
			self.level = toLevel
			local swap = TweenInfo.new(0.35)
			TweenService:Create(sheet, swap, {BackgroundColor3 = to.ink}):Play()
			TweenService:Create(bar, swap, {BackgroundColor3 = to.accent}):Play()
			TweenService:Create(rail, swap, {BackgroundColor3 = to.accent:Lerp(to.ink, 0.82)}):Play()
			kick.Text, kick.TextColor3, name.Text, hint.Text = to.kicker, to.accent, to.name, to.tip
			state.TextColor3, note.TextColor3, hint.TextColor3 = to.accent:Lerp(Color3.new(1, 1, 1), 0.55), to.accent:Lerp(to.ink, 0.45), to.accent:Lerp(to.ink, 0.4)
		end
		function self.drop()
			if not self.open then return end
			self.target = 1
			task.wait(0.2)
			self.open = false
			sheet.Active = false
			player:SetAttribute("LevelLoadingOpen", false)
			local fade = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(sheet, fade, {BackgroundTransparency = 1}):Play()
			for _, child in ipairs(sheet:GetDescendants()) do
				if child:IsA("TextLabel") then TweenService:Create(child, fade, {TextTransparency = 1}):Play()
				elseif child:IsA("Frame") then TweenService:Create(child, fade, {BackgroundTransparency = 1}):Play() end
			end
			task.delay(0.65, function() screen:Destroy() end)
			print(string.format("[LevelLoading] level %s covered for %.1f s", tostring(self.level), os.clock() - self.startedAt))
		end
		return self
	end

	-- Fetch everything `roots` reference that is not fetched yet; `report(done, total)` as it goes. Stops at `cap`.
	local seen, carriers = {}, {}
	local function fetch(roots, cap, report)
		local fresh = census(roots, seen, carriers)
		if fresh == 0 then return 0 end
		local work = {}
		for _, instance in ipairs(carriers) do
			for _, property in ipairs(CONTENT_PROPERTIES[instance.ClassName]) do
				local ok, value = pcall(function() return instance[property] end)
				if ok and seen[value] == "pending" then table.insert(work, instance) break end
			end
		end
		local done, cursor, running, deadline = 0, 1, 0, os.clock() + cap
		local function settle(id)
			if seen[id] == "pending" then
				seen[id] = "ok"
				done += 1
				if report then report(math.min(done, fresh), fresh) end
			end
		end
		for _ = 1, WORKERS do
			running += 1
			task.spawn(function()
				while cursor <= #work and os.clock() < deadline do
					local batch = table.move(work, cursor, math.min(#work, cursor + BATCH - 1), 1, {})
					cursor += BATCH
					pcall(function() ContentProvider:PreloadAsync(batch, function(id) settle(id) end) end)
					for _, instance in ipairs(batch) do
						for _, property in ipairs(CONTENT_PROPERTIES[instance.ClassName]) do
							local ok, value = pcall(function() return instance[property] end)
							if ok then settle(value) end
						end
					end
				end
				running -= 1
			end)
		end
		while running > 0 and os.clock() < deadline do task.wait(0.1) end
		for id, value in pairs(seen) do if value == "pending" then seen[id] = "ok" end end      -- past the cap: not asked for again
		return fresh
	end
	local function quiet(cap, hold)                  -- the request queue has stayed empty for `hold` seconds
		local began, calm = os.clock(), nil
		while os.clock() - began < cap do
			if ContentProvider.RequestQueueSize == 0 then
				calm = calm or os.clock()
				if os.clock() - calm >= hold then return end
			else
				calm = nil
			end
			task.wait(0.1)
		end
	end
	local function roundCover()
		local round = playerGui:FindFirstChild("RoundGui")
		local frame = round and round:FindFirstChild("LevelLoading")
		return frame ~= nil and frame:IsA("GuiObject") and frame.Visible and round.Enabled
	end
	local function announced()
		return tonumber(player:GetAttribute("LoadingLevel")) or tonumber(workspace:GetAttribute("SelectedLevel")) or 0
	end
	local function levelWorlds()                     -- everything in the workspace that is not a lobby or a body
		local list = {}
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name ~= REVISED_LOBBY and child.Name ~= ORIGINAL_LOBBY and not Players:GetPlayerFromCharacter(child)
				and (child:IsA("Model") or child:IsA("Folder")) and child.Name ~= LIVE_MODELS[5] and child.Name ~= LIVE_MODELS[6] then
				table.insert(list, child)
			end
		end
		return list
	end

	-- A GameManager round. `joined` = this is a reserved round server and RoundUI's cover has not come up yet.
	local function coverRound(joined)
		local cover = raise(joined and 0 or announced())
		up = cover
		cover.stage("PREPARING YOUR PARTY", 0.08, "The server is building the level.")
		local began = os.clock()
		if joined then                                -- wait for the round's own cover (or for the round itself)
			while os.clock() - began < 60 and not roundCover() and player:GetAttribute("InRound") ~= true do task.wait(0.1) end
		end
		local lastFetch = 0
		while roundCover() and os.clock() - began < 150 do
			cover.restyle(announced())
			local waited = os.clock() - began
			cover.stage("BUILDING THE LEVEL", 0.1 + 0.55 * (1 - math.exp(-waited / 9)), "The server is building the level.")
			if os.clock() - lastFetch > 1.5 then        -- whatever of it is here already
				lastFetch = os.clock()
				task.spawn(fetch, levelWorlds(), 6, nil)
			end
			task.wait(0.15)
		end
		cover.restyle(announced())
		-- the round has let us in: one bounded pass over what arrived, then out
		cover.stage("LOADING THE LEVEL", 0.7, "Meshes, textures, decals and materials.")
		fetch(levelWorlds(), 2.5, function(done, total)
			cover.stage(string.format("LOADING THE LEVEL  %d / %d", done, total), 0.7 + 0.25 * done / math.max(1, total), "Meshes, textures, decals and materials.")
		end)
		cover.stage("FINISHING TEXTURES", 0.97)
		quiet(1.5, 0.4)
		cover.stage("LEVEL READY", 1)
		cover.drop()
		up = nil
	end

	-- Level 5 or 6: the level is a place on this server; the body is moved there.
	local function coverLive(level)
		local cover = raise(level)
		up = cover
		local function still() return player:GetAttribute("Level6PlaygroundPreview") == true end
		local function root()
			local character = player.Character
			return character and character:IsDescendantOf(workspace) and character:FindFirstChild("HumanoidRootPart") or nil
		end
		cover.stage("ENTERING THE LEVEL", 0.08, "Waiting for your character.")
		local began = os.clock()
		local model
		while still() and os.clock() - began < 14 do    -- the body is in the level (the levels stand far from the lobby)
			model = workspace:FindFirstChild(LIVE_MODELS[level])
			local part = root()
			if model and part and (part.Position - model:GetPivot().Position).Magnitude < 3000
				and player:GetAttribute("InRound") == true then break end
			task.wait(0.1)
		end
		if model and still() then
			cover.stage("STREAMING THE LEVEL", 0.25, "Receiving the level from the server.")
			local last, arrivals = os.clock(), 0
			local watch = model.DescendantAdded:Connect(function() last = os.clock() arrivals += 1 end)
			local from = os.clock()
			while still() and os.clock() - last < SETTLE_SECONDS and os.clock() - from < 5 do
				if arrivals > 0 then cover.stage("STREAMING THE LEVEL", 0.25 + 0.1 * math.min(1, (os.clock() - from) / 3), string.format("Receiving the level from the server (%d).", arrivals)) end
				task.wait(0.1)
			end
			watch:Disconnect()
			cover.stage("PLACING YOU IN THE LEVEL", 0.4, "Waiting for the floor under you.")
			from = os.clock()
			local params = RaycastParams.new()
			params.FilterType, params.FilterDescendantsInstances, params.RespectCanCollide = Enum.RaycastFilterType.Include, {model}, true
			while still() and os.clock() - from < 5 do
				local part = root()
				local hit = part and workspace:Raycast(part.Position + Vector3.yAxis * 2, Vector3.new(0, -18, 0), params)
				if hit then break end
				task.wait(0.1)
			end
			cover.stage("LOADING THE LEVEL", 0.45, "Meshes, textures, decals and materials.")
			fetch({model}, 8, function(done, total)
				cover.stage(string.format("LOADING THE LEVEL  %d / %d", done, total), 0.45 + 0.5 * done / math.max(1, total), "Meshes, textures, decals and materials.")
			end)
			cover.stage("FINISHING TEXTURES", 0.97)
			quiet(2.5, 0.6)
		end
		cover.stage("LEVEL READY", 1)
		cover.drop()
		up = nil
	end

	if workspace:GetAttribute("ReservedRoundServer") == true then task.spawn(coverRound, true) end
	local wasLive = player:GetAttribute("Level6PlaygroundPreview") == true
	while true do
		task.wait(0.1)
		local live = player:GetAttribute("Level6PlaygroundPreview") == true
		if not up then
			if roundCover() then
				task.spawn(coverRound, false)
			elseif live and not wasLive then
				task.wait(0.15)                          -- Level 5 sets its own marker next to the shared one
				task.spawn(coverLive, player:GetAttribute("Level5VoidRound") == true and 5 or 6)
			end
		end
		wasLive = live
	end
end
