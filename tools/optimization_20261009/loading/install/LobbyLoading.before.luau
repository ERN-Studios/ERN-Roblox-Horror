-- Lobby loading cover. Shown from the first frame the client runs Lua and held
-- until the lobby this client will stand in is really there: the server's own
-- lobby-startup markers, the streamed model, ground under the character and
-- supported meshes/images the lobby references. Nothing here is a
-- cosmetic timer; the only clocks are stall detectors that OFFER a way out.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local startedAt = os.clock()

local REVISED_LOBBY = "LobbyReimaginedPreview"
local ORIGINAL_LOBBY = "ServerLobby"
local STALL_SECONDS = 15          -- no progress at all for this long -> offer recovery
local SETTLE_SECONDS = 0.75       -- lobby must stop receiving new instances for this long
local SETTLE_CAP_SECONDS = 10     -- a lobby that never stops changing does not hold the door
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
	MeshPart = { "MeshContent", "TextureContent" },
	SpecialMesh = { "MeshId", "TextureId" },
	Decal = { "Texture" }, Texture = { "Texture" },
	ImageLabel = { "Image" }, ImageButton = { "Image" },
	ParticleEmitter = { "Texture" }, Beam = { "Texture" }, Trail = { "Texture" },
}
local MAP_PROPERTIES = { "ColorMapContent", "NormalMapContent", "RoughnessMapContent", "MetalnessMapContent" }

local function contentKey(value)
	if type(value) == "string" then return value ~= "" and value or nil end
	if typeof(value) == "Content" then
		if value.SourceType == Enum.ContentSourceType.Uri then return value.Uri ~= "" and value.Uri or nil end
		if value.SourceType == Enum.ContentSourceType.Opaque then return value end
	end
	return nil
end

local function collectAsset(instance, ids, carriers)
	local added = 0
	local function add(key, imageId, keys)
		if not key or ids[key] then return end
		ids[key] = "pending"
		added += 1
		if imageId then
			table.insert(carriers, {ImageId = imageId, Keys = {key}})
		else
			table.insert(keys, key)
		end
	end
	if instance:IsA("SurfaceAppearance") then
		-- PreloadAsync ignores SurfaceAppearance. Warm URI images through supported
		-- Decals; this cannot certify that the renderer's processed PBR pack is ready.
		for _, property in ipairs(MAP_PROPERTIES) do
			local ok, value = pcall(function() return instance[property] end)
			if ok and typeof(value) == "Content" and value.SourceType == Enum.ContentSourceType.Uri then
				add(contentKey(value), value.Uri)
			end
		end
	else
		local keys = {}
		for _, property in ipairs(CONTENT_PROPERTIES[instance.ClassName] or {}) do
			local ok, value = pcall(function() return instance[property] end)
			if ok then
				local key = contentKey(value)
				if typeof(key) == "Content" then
					-- Embedded Opaque content without an asset ID has no remote fetch.
					local legacy = property == "MeshContent" and "MeshId" or "TextureID"
					local readable, id = pcall(function() return instance[legacy] end)
					key = readable and type(id) == "string" and id ~= "" and id or nil
				end
				add(key, nil, keys)
			end
		end
		if #keys > 0 then table.insert(carriers, {Instance = instance, Keys = keys}) end
	end
	return added
end

local function loadCarrier(carrier)
	local instance = carrier.Instance
	local reported, failed = false, false
	local ok = pcall(function()
		if carrier.ImageId then
			instance = Instance.new("Decal")
			instance.Texture = carrier.ImageId
		end
		-- Keep mesh instances: a MeshId string does not necessarily fetch the
		-- same content as the actual MeshPart, especially DataModel-scoped meshes.
		ContentProvider:PreloadAsync({instance}, function(_, fetchStatus)
			reported = true
			if fetchStatus ~= Enum.AssetFetchStatus.Success then failed = true end
		end)
	end)
	if carrier.ImageId and instance then
		local cleaned = pcall(function() instance:Destroy() end)
		if not cleaned then ok = false end
	end
	-- A return or absent callback is not evidence of a successful download.
	return ok and reported and not failed
end

local function pendingCarriers(ids, carriers, wanted)
	local out = {}
	for _, carrier in ipairs(carriers) do
		for _, key in ipairs(carrier.Keys) do
			if ids[key] == wanted then table.insert(out, carrier) break end
		end
	end
	return out
end

local function census(roots, ids, carriers, instances)
	local total, checked = 0, 0
	local function consider(instance)
		total += collectAsset(instance, ids, carriers)
		checked += 1
		if checked % 200 == 0 then task.wait() end
	end
	if instances then
		for _, instance in ipairs(instances) do consider(instance) end
	else
		for _, root in ipairs(roots) do
			for _, instance in ipairs(root:GetDescendants()) do consider(instance) end
		end
	end
	if devFlag("DevLobbyLoadBadAsset") then
		local broken = Instance.new("Decal")
		broken.Texture = "rbxassetid://999999999999999"
		consider(broken)
		-- Store the URI on a test-owned carrier so no destroyed probe is preloaded.
		for _, carrier in ipairs(carriers) do
			if carrier.Instance == broken then carrier.Instance, carrier.ImageId = nil, broken.Texture end
		end
		broken:Destroy()
	end
	return total
end

local settledCount = 0
local preloadBusy = false
local function preload(ids, carriers, total)
	local failed, token, done = 0, retryToken, false
	-- All workers from a retry/skip retain this owner until their engine calls drain.
	while preloadBusy and token == retryToken and not enterAnyway do task.wait(0.1) end
	if token ~= retryToken or enterAnyway then return 0, token ~= retryToken end
	local cursor, running = 1, math.min(4, #carriers)
	if running == 0 then return 0, false end
	preloadBusy = true
	for _ = 1, running do
		task.spawn(function()
			local ok, problem = pcall(function()
				while cursor <= #carriers and token == retryToken and not enterAnyway do
					-- Claim before yielding, so each typed carrier is requested once.
					local carrier = carriers[cursor]
					cursor += 1
					while devFlag("DevLobbyLoadStall") and token == retryToken and not enterAnyway do task.wait(0.2) end
					if token ~= retryToken or enterAnyway then break end
					local loaded = loadCarrier(carrier)
					if token ~= retryToken or enterAnyway then break end
					for _, key in ipairs(carrier.Keys) do
						if ids[key] == "pending" then
							ids[key] = loaded and "ok" or "failed"
							settledCount += 1
							if not loaded then failed += 1 end
						end
					end
					progress = math.max(progress, 0.3 + 0.7 * math.min(1, settledCount / math.max(1, total)))
					status.Text = string.format("LOADING LOBBY ASSETS  %d / %d", math.min(settledCount, total), total)
					touch()
					task.wait()
				end
			end)
			if not ok then warn("[LobbyLoading] worker: " .. tostring(problem)) end
			running -= 1
			if running == 0 then
				if token == retryToken and not enterAnyway then
					-- An unexpected worker error must not turn unreported work into success.
					for _, carrier in ipairs(carriers) do
						for _, key in ipairs(carrier.Keys) do
							if ids[key] == "pending" then ids[key] = "failed" failed += 1 settledCount += 1 end
						end
					end
				end
				preloadBusy, done = false, true
			end
		end)
	end
	while not done and token == retryToken and not enterAnyway do task.wait(0.1) end
	return failed, token ~= retryToken
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
	setStage(string.format("LOADING LOBBY ASSETS  0 / %d", total), 0.3, "Meshes and image downloads.")
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
			if state == "failed" then warn("[LobbyLoading] did not load: " .. tostring(id)) end
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
	-- This is a bounded settling allowance after measured fetches. An empty
	-- download queue cannot prove GPU upload, mip sharpness or processed PBR readiness.
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

	-- Index each streamed root once; arrivals add work without rescanning the map.
	local seen, carriers, watched, queued = {}, {}, {}, {}
	local fetching, fetchGeneration = false, 0
	local function resetFetch()
		fetchGeneration += 1
		for _, state in pairs(watched) do state.Connection:Disconnect() end
		seen, carriers, watched, queued = {}, {}, {}, {}
		-- The old worker still owns `fetching` until its engine request returns.
	end
	local function track(roots, generation, deadline)
		for root, state in pairs(watched) do
			if not root.Parent then state.Connection:Disconnect() watched[root] = nil end
		end
		for _, root in ipairs(roots) do
			if not watched[root] then
				watched[root] = {
					Connection = root.DescendantAdded:Connect(function(instance)
						if generation == fetchGeneration then table.insert(queued, instance) end
					end), Initial = root:GetDescendants(), Cursor = 1,
				}
			end
			local state, added = watched[root], 0
			while state.Initial and state.Cursor <= #state.Initial and added < 2000 do
				if generation ~= fetchGeneration or os.clock() >= deadline then return end
				table.insert(queued, state.Initial[state.Cursor])
				state.Cursor += 1
				added += 1
				if added % 200 == 0 then task.wait() end
			end
			if state.Initial and state.Cursor > #state.Initial then state.Initial = nil end
		end
	end
	local function fetch(roots, cap, report)
		if fetching then return 0 end
		fetching = true
		local deadline, done, count, generation = os.clock() + cap, false, 0, fetchGeneration
		task.spawn(function()
			local ok, problem = pcall(function()
				track(roots, generation, deadline)
				if generation ~= fetchGeneration then return end
				-- One bounded census slice per pass; the unprocessed queue remains queued.
				local slice = table.move(queued, 1, math.min(#queued, 2000), 1, {})
				queued = table.move(queued, #slice + 1, #queued, 1, {})
				census(nil, seen, carriers, slice)
				if generation ~= fetchGeneration then return end
				local work = {}
				for _, carrier in ipairs(carriers) do
					if (carrier.Attempts or 0) < 2 then
						for _, key in ipairs(carrier.Keys) do
							if seen[key] ~= "ok" then table.insert(work, carrier) break end
						end
					end
				end
				count = #work
				for index, carrier in ipairs(work) do
					if generation ~= fetchGeneration or os.clock() >= deadline then break end
					carrier.Attempts = (carrier.Attempts or 0) + 1
					local loaded = loadCarrier(carrier)
					if generation ~= fetchGeneration then break end
					for _, key in ipairs(carrier.Keys) do seen[key] = loaded and "ok" or "failed" end
					if not loaded and carrier.Attempts == 2 then
						warn("[LevelLoading] could not fetch: " .. tostring(carrier.Keys[1]))
					end
					if report then report(index, count) end
					task.wait()
				end
			end)
			if not ok then warn("[LevelLoading] prefetch: " .. tostring(problem)) end
			-- Only the worker releases ownership, even if PreloadAsync exceeded cap.
			fetching, done = false, true
		end)
		while not done and os.clock() < deadline do task.wait(0.1) end
		return count
	end
	local function needsFetch()
		if fetching or #queued > 0 then return true end
		for _, state in pairs(watched) do if state.Initial then return true end end
		for _, carrier in ipairs(carriers) do
			if (carrier.Attempts or 0) < 2 then
				for _, key in ipairs(carrier.Keys) do if seen[key] ~= "ok" then return true end end
			end
		end
		return false
	end
	local function failedFetch()
		for _, state in pairs(seen) do if state == "failed" then return true end end
		return false
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
	local function levelWorlds()
		local level, list = announced(), {}
		local names = level == 1 and {"Maze", "Elevator", "Decor", "PuzzleItems"}
			or level == 4 and {"Level 4 Cinema Blender", "PuzzleItems"}
			or {"Level " .. tostring(level) .. " Generated World"}
		for _, name in ipairs(names) do
			local root = workspace:FindFirstChild(name)
			if root then table.insert(list, root) end
		end
		return list
	end

	-- GameManager owns release. This sentinel prevents concurrent/repeated workers
	-- while the imported card is visible; bounded prefetch never owns presentation.
	local function coverRound(joined)
		resetFetch()
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
		resetFetch()
		up = nil
	end

	-- Level 5 or 6: the level is a place on this server; the body is moved there.
	local function coverLive(level, standing)
		resetFetch()
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
			cover.stage("LOADING THE LEVEL", 0.45, "Meshes and image downloads.")
			local fetchDeadline = os.clock() + 8
			repeat
				fetch({model}, math.max(0.1, fetchDeadline - os.clock()), nil)
				task.wait(0.1) -- An older generation may still own the engine request.
			until not still() or os.clock() >= fetchDeadline or (watched[model] and not needsFetch())
			cover.stage("FINISHING TEXTURES", 0.97)
			quiet(2.5, 0.6)
		end
		local incomplete = not model or not watched[model] or needsFetch() or failedFetch()
		resetFetch()
		cover.stage(incomplete and "ENTERING THE LEVEL" or "LEVEL READY", 1)
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
