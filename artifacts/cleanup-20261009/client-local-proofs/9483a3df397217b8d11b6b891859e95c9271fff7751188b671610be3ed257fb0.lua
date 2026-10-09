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
	-- LIVE_LEVEL_SERVERS_20261008. A party's own server for Level 5 or 6 (`workspace.LiveLevelServer`, set by
	-- ServerKind before GameManager answers the question above). The player was sent here for the level, not for
	-- this lobby: nothing of the lobby is fetched, and the level's cover (the block at the end of this script)
	-- takes this one's place without the lobby ever being shown.
	local liveLevel = workspace:GetAttribute("LiveLevelServer")
	if liveLevel == 5 or liveLevel == 6 then return "live" end
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

-- GameManager entry is drawn by the imported RoundUI card. Keep only the
-- first-frame bootstrap cover until that card exists, without fading over it.
local function roundCover()
	local playerGui = player:FindFirstChild("PlayerGui")
	local round = playerGui and playerGui:FindFirstChild("RoundGui")
	local frame = round and round:FindFirstChild("LevelLoading")
	return frame ~= nil and frame:IsA("GuiObject") and frame.Visible and round.Enabled
end
if outcome == "round" then
	local began = os.clock()
	while os.clock() - began < 60 and not roundCover()
		and not (player:GetAttribute("InRound") == true and workspace:GetAttribute("RoundActive") == true) do
		task.wait(0.1)
	end
end

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
if outcome == "live" then
	-- LIVE_LEVEL_SERVERS_20261008: this cover stays, and the lobby stays "loading" for everything that waits on
	-- it (the welcome card, the BADGES button), until the level's cover is up underneath. See `coverArrival`.
	status.Text, detail.Text = "JOINING YOUR PARTY", ""
else
	cover.Active = false
	player:SetAttribute("LobbyLoadingOpen", false)
	player:SetAttribute("LobbyLoadingDone", true)
	if outcome == "round" then
		gui:Destroy() -- the new cover is already visible; no legacy fade on top
	else
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
	end
end

---------------------------------------------------------------------------
-- LEVEL_LOADING_20261004 (owner: "make sure a similar loading screen happens for every level, timed with the
-- load speed", "and change its colour scheme a little with the level you are in").
--
-- Every actual level entry uses the imported LoadingCardView layout. Loading state and release still
-- follow what has really loaded; the first-join lobby above keeps its existing boot cover:
--   ROUNDS (Levels 1-4, GameManager): RoundUI's imported `RoundGui.LevelLoading` is the only round cover.
--     This script prefetches arriving world assets in the background; it neither draws a duplicate cover
--     nor delays the tokenized entry release. Reserved-server bootstrap hands over to RoundUI above.
--   LIVE LEVELS (5 and 6, on the lobby server): raised when the level marks the player, held until the body is
--     in the level, the model has stopped arriving, there is ground under the feet, the level's meshes and
--     textures are fetched and the request queue has gone quiet.
-- Live-level cover waits have caps. Client attribute `LevelLoadingOpen` belongs only to those covers.
---------------------------------------------------------------------------
do
	local LIVE_MODELS = {[5] = "Level 5 Void", [6] = "Level 6 Indoor Playground"}
	local playerGui = player:WaitForChild("PlayerGui")
	local up = nil                                  -- the cover on screen, or nil

	local function raise(level)
		local screen = Instance.new("ScreenGui")
		screen.Name, screen.IgnoreGuiInset, screen.ResetOnSpawn, screen.DisplayOrder = "LevelLoadingGui", true, false, 99990
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		-- A stable group fades every imported/remounted child together.
		local sheet = Instance.new("CanvasGroup")
		sheet.Name, sheet.Size, sheet.BackgroundColor3, sheet.BorderSizePixel, sheet.Active = "Cover", UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 0, true
		sheet.BackgroundTransparency, sheet.GroupTransparency = 0, 0
		sheet.Parent = screen
		screen.Parent = playerGui
		player:SetAttribute("LevelLoadingOpen", true)
		up = {loading = true} -- module replication may yield; do not start another live cover
		local View = require(game:GetService("ReplicatedStorage"):WaitForChild("LoadingCardView"))
		local view = View.new(sheet, level)
		local self = {level = level, target = 0, open = true, startedAt = os.clock()}
		function self.stage(text, fraction, detailText)
			-- Keep measured progress monotone; the imported layout has no legacy detail row.
			if fraction and fraction > self.target then self.target = fraction end
			view:SetStatus(text, self.target)
		end
		function self.restyle(toLevel)
			local nextLevel = tonumber(toLevel)
			if not nextLevel or nextLevel % 1 ~= 0 or nextLevel < 1 or nextLevel > 6 or nextLevel == self.level then return end
			self.level = nextLevel
			view:SetLevel(nextLevel)
			view:SetStatus(nil, self.target)
		end
		function self.drop()
			if not self.open then return end
			self.target = 1
			view:SetStatus(nil, 1)
			task.wait(0.2)
			self.open = false
			sheet.Active = false
			player:SetAttribute("LevelLoadingOpen", false)
			local fade = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			TweenService:Create(sheet, fade, {BackgroundTransparency = 1, GroupTransparency = 1}):Play()
			task.delay(0.65, function()
				view:Destroy() -- disconnect the device-remount watch before removing its parent
				screen:Destroy()
			end)
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

	-- GameManager owns release. This sentinel prevents concurrent/repeated workers
	-- while the imported card is visible; bounded prefetch never owns presentation.
	local function coverRound(joined)
		up = {round = true}
		local began = os.clock()
		if joined then
			while os.clock() - began < 60 and not roundCover() and player:GetAttribute("InRound") ~= true do task.wait(0.1) end
		end
		local lastFetch = 0
		while roundCover() do
			if os.clock() - began < 150 and os.clock() - lastFetch > 1.5 then
				lastFetch = os.clock()
				task.spawn(fetch, levelWorlds(), 6, nil)
			end
			task.wait(0.15)
		end
		up = nil
	end

	-- Level 5 or 6: the level is a place on this server; the body is moved there.
	local function coverLive(level, standing)
		local cover = standing or raise(level)
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

	-- LIVE_LEVEL_SERVERS_20261008. A party's own server for Level 5 or 6: the join is covered in the LEVEL's
	-- colours from the first frame this block runs, the server is told this client is here, and the cover
	-- holds until the level has taken the player, then loads the level as for any other way in. The server
	-- says when there is nothing to wait for (player attribute `LiveLevelPending` false); 90 s is the last resort.
	local function coverArrival(level)
		local cover = raise(level)
		up = cover
		if gui.Parent then gui:Destroy() end             -- the lobby's cover, which stood over this one until now
		local function inLevel() return player:GetAttribute("Level6PlaygroundPreview") == true end
		cover.stage("JOINING YOUR PARTY", 0.03, "This server is for your party alone.")
		local remote = game:GetService("ReplicatedStorage"):WaitForChild("LiveLevelArrival", 20)
		local began = os.clock()
		while os.clock() - began < 20 do                 -- the server needs a body standing here to move
			local character = player.Character
			if character and character:IsDescendantOf(workspace) and character:FindFirstChild("HumanoidRootPart") then break end
			task.wait(0.1)
		end
		if remote then remote:FireServer("ready") end
		cover.stage("WAITING FOR YOUR PARTY", 0.06, "The level opens when everyone has arrived.")
		began = os.clock()
		while not inLevel() and player:GetAttribute("LiveLevelPending") ~= false and os.clock() - began < 90 do
			task.wait(0.1)
		end
		player:SetAttribute("LobbyLoadingOpen", false)
		player:SetAttribute("LobbyLoadingDone", true)
		if inLevel() then
			task.wait(0.15)                              -- Level 5 sets its own marker next to the shared one
			coverLive(player:GetAttribute("Level5VoidRound") == true and 5 or 6, cover)
		else
			-- The level did not take them. This is a lobby like any other, with the level's pad in it.
			cover.stage("OPENING THE LOBBY", 1, "The level could not be started. Use its pad in the lobby.")
			task.wait(1.6)
			cover.drop()
			up = nil
		end
	end

	if workspace:GetAttribute("ReservedRoundServer") == true then task.spawn(coverRound, true) end
	do
		local arriving = workspace:GetAttribute("LiveLevelServer")
		if (arriving == 5 or arriving == 6) and gui.Parent then task.spawn(coverArrival, arriving) end
	end
	local wasLive = player:GetAttribute("Level6PlaygroundPreview") == true
	local wasFive = player:GetAttribute("Level5VoidRound") == true
	while true do
		task.wait(0.1)
		local live = player:GetAttribute("Level6PlaygroundPreview") == true
		local five = player:GetAttribute("Level5VoidRound") == true
		if not up then
			if roundCover() then
				task.spawn(coverRound, false)
			elseif live and not wasLive then
				task.wait(0.15)                          -- Level 5 sets its own marker next to the shared one
				task.spawn(coverLive, player:GetAttribute("Level5VoidRound") == true and 5 or 6)
			elseif live and wasFive and not five then
				-- CONTINUE on Level 5's ending: the same player goes on into Level 6 with the shared marker
				-- still set, so there is no rising edge to see. Level 5's own marker dropping is the cue.
				task.spawn(coverLive, 6)
			end
		end
		wasLive, wasFive = live, five
	end
end
