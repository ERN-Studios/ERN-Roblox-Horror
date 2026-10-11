-- LEVEL_LEADERBOARDS_20261008 (owner: "a tall sign out from the entrance at each level with people's completion
-- time, a leaderboard of the usernames that cleared that level fastest; it must match the lobby's style; the top 3
-- each get their own colour and font size", and: "it is when YOU reach the exit, so a group of five each have
-- their own time, and somebody who died has none").
--
-- Two halves, both in this script:
--   RECORD  on every server. A player's own time for a level, in whole milliseconds, kept in one OrderedDataStore
--           per level (`LevelBestTimes_v1_L<n>`, key = UserId) and only ever lowered. Levels 1-4 come from the
--           event GameManager already fires once per escapee (`ServerStorage.ZyntraLevelCompleted`, whose `run`
--           table carries that player's seconds from the round's start to their own escape, and `DevTouched`
--           for a run a developer tool changed: those are not recorded). Levels 5 and 6 report through
--           `ServerStorage.LevelTimeReported:Fire(player, level, seconds)` from their own finish lines.
--   SHOW    on lobby servers. A board beside each level's gate, standing out from the wall under the gate's
--           projecting arrow, lettered on both faces: ten rows, the first three as cards in gold, silver and
--           bronze with their own sizes. One level is read again every REFRESH_SECONDS, so each board is at
--           most two minutes old. No Light instances (the DJ's party lights recolour every Light in the lobby).
-- Studio never writes a time. `workspace.DevLeaderboardDemo = true` (Studio only) fills the boards with sample
-- rows so their look can be judged without a data store.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local ServerKind = require(script.Parent:WaitForChild("ServerKind"))
-- BOARD_NO_DEVS_20261010 (owner: "Begge DEVs: Mikkelczar og LaverSneglen skal begge ekskluderes fra leaderboards for
-- level completion tid"). DevAccess.IsAllowed is exactly those two accounts. Their times are never saved, never shown,
-- and a row of theirs that a read meets is removed from the store (a time is only ever lowered, so a row that is
-- there stays there until it is taken out).
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))
local DEVELOPERS = 2

local LEVELS, TOP = 6, 10
local STORE_PREFIX = "LevelBestTimes_v1_L"
local MIN_SECONDS, MAX_SECONDS = 10, 6 * 3600       -- outside this a time is a bug, not a record
local REFRESH_SECONDS = 20                          -- one level per step: six levels, two minutes a round
local IS_STUDIO = RunService:IsStudio()
local OWNED = "LobbyReimaginedOwned"

local function store(level)
	return DataStoreService:GetOrderedDataStore(STORE_PREFIX .. level)
end

---------------------------------------------------------------------------------------------------------------
-- RECORD
---------------------------------------------------------------------------------------------------------------
local shown = {}                -- level -> {{id = userId, ms = milliseconds}, ...} as last read (lobby servers)
local redraw                    -- set by SHOW

local function submit(player, level, seconds)
	level, seconds = math.floor(tonumber(level) or 0), tonumber(seconds)
	if level < 1 or level > LEVELS or not seconds or seconds ~= seconds
		or seconds < MIN_SECONDS or seconds > MAX_SECONDS then return end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.UserId <= 0 or IS_STUDIO then return end
	if DevAccess.IsAllowed(player) then return end
	local ms, key, better = math.floor(seconds * 1000 + 0.5), tostring(player.UserId), false
	for attempt = 1, 3 do
		local ok, problem = pcall(function()
			store(level):UpdateAsync(key, function(old)
				if type(old) == "number" and old > 0 and old <= ms then return nil end      -- not a better time
				better = true
				return ms
			end)
		end)
		if ok then break end
		warn("[LevelLeaderboards] could not save a Level " .. level .. " time (try " .. attempt .. "): " .. tostring(problem))
		task.wait(2 * attempt)
	end
	-- A server that also shows boards (Levels 5 and 6 finish on a lobby server) does not wait for its next read.
	local rows = shown[level]
	if better and rows and redraw then
		for index = #rows, 1, -1 do
			if rows[index].id == player.UserId then table.remove(rows, index) end
		end
		table.insert(rows, {id = player.UserId, ms = ms})
		table.sort(rows, function(a, b) return a.ms < b.ms end)
		while #rows > TOP do table.remove(rows) end
		redraw(level)
	end
end

task.spawn(function()
	local completed = ServerStorage:WaitForChild("ZyntraLevelCompleted", 120)
	if not completed then return end
	completed.Event:Connect(function(player, level, _, run)
		if type(run) ~= "table" or run.DevTouched == true then return end
		task.spawn(submit, player, level, run.Seconds)
	end)
end)
do
	local reported = ServerStorage:FindFirstChild("LevelTimeReported")
	if not reported then
		reported = Instance.new("BindableEvent")
		reported.Name = "LevelTimeReported"
		reported.Parent = ServerStorage
	end
	reported.Event:Connect(function(player, level, seconds) task.spawn(submit, player, level, seconds) end)
end

---------------------------------------------------------------------------------------------------------------
-- SHOW
---------------------------------------------------------------------------------------------------------------
if ServerKind.IsRoundServer() then return end       -- a round server has no lobby to hang boards in

local lobby = workspace:WaitForChild("LobbyReimaginedPreview", 180)
if not lobby then return end
do
	local began = os.clock()
	while lobby:GetAttribute("Ready") ~= true and os.clock() - began < 120 do task.wait(0.5) end
end

-- The lobby's own signage: pale mint lettering, Gotham, dark teal metal.
local INK = Color3.fromRGB(11, 17, 20)
local CARD = Color3.fromRGB(20, 30, 34)
local STEEL = Color3.fromRGB(38, 62, 66)
local MINT = Color3.fromRGB(111, 255, 214)
local PALE = Color3.fromRGB(208, 255, 247)
local MUTED = Color3.fromRGB(120, 156, 150)
local PODIUM = {
	{colour = Color3.fromRGB(255, 205, 84), top = 2.62, height = 1.72, rank = 0.98, name = 0.52, time = 0.6},     -- gold
	{colour = Color3.fromRGB(206, 222, 232), top = 4.44, height = 1.5, rank = 0.8, name = 0.44, time = 0.5},     -- silver
	{colour = Color3.fromRGB(230, 152, 92), top = 6.04, height = 1.34, rank = 0.7, name = 0.39, time = 0.44},    -- bronze
}
local W, H, LEG = 5.6, 13.2, 0.6                    -- the lettered face in studs, and the plinth under it
local SIDE_OUT, STAND_OFF = 15, 3.4                 -- beside the door (the arrow blade is at +15), out from the wall
local PPS = 50
local ROWS_TOP, ROW_STEP = 7.56, 0.7                -- ranks 4 to 10

local function clock(ms)
	local total = ms / 1000
	local hours, minutes = math.floor(total / 3600), math.floor(total % 3600 / 60)
	local seconds = total % 60
	if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, math.floor(seconds)) end
	return string.format("%d:%05.2f", minutes, seconds)
end

local names, asking = {}, {}
local function nameOf(userId, level)
	if names[userId] then return names[userId] end
	if not asking[userId] then
		asking[userId] = true
		task.spawn(function()
			local ok, found = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
			asking[userId] = nil
			if ok and type(found) == "string" and found ~= "" then
				names[userId] = found
				if redraw then redraw(level) end
			end
		end)
	end
	return "..."
end

local boards = {}               -- level -> {faces = {{podium = {...}, rows = {...}}, ...}}

-- MALL_LOBBY_20261012: `look` is how a face is printed. The lobby's own boards are lit screens (LIT); the mall lobby's
-- are sheets of paper pinned to its notice boards (PAPER, below), the same layout scaled to the sheet.
local LIT = {ink = INK, card = CARD, accent = MINT, pale = PALE, muted = MUTED, pps = PPS, light = 0}
local PAPER = {ink = Color3.fromRGB(232, 226, 204), card = Color3.fromRGB(212, 204, 178), accent = Color3.fromRGB(104, 62, 40),
	pale = Color3.fromRGB(50, 44, 36), muted = Color3.fromRGB(118, 106, 86), light = 0.75,
	podium = {Color3.fromRGB(150, 102, 16), Color3.fromRGB(84, 94, 104), Color3.fromRGB(142, 78, 36)}}
local function buildFace(panel, face, level, look)
	look = look or LIT
	local INK, CARD, MINT, PALE, MUTED = look.ink, look.card, look.accent, look.pale, look.muted
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face = "Leaderboard", face
	gui.SizingMode, gui.PixelsPerStud = Enum.SurfaceGuiSizingMode.PixelsPerStud, look.pps
	gui.LightInfluence, gui.Brightness, gui.ClipsDescendants, gui.MaxDistance = look.light, 1, true, 160
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local function box(class, x, y, w, h, parent)             -- in studs from the face's top left
		local item = Instance.new(class)
		item.Position, item.Size = UDim2.fromOffset(x * PPS, y * PPS), UDim2.fromOffset(w * PPS, h * PPS)
		item.BorderSizePixel = 0
		item.Parent = parent or gui
		return item
	end
	local function line(text, x, y, w, h, studs, colour, font, align)
		local label = box("TextLabel", x, y, w, h)
		label.BackgroundTransparency = 1
		label.Text, label.TextColor3, label.Font = text, colour, font
		label.TextSize = math.floor(studs * PPS + 0.5)
		label.TextXAlignment = align or Enum.TextXAlignment.Center
		label.TextTruncate = Enum.TextTruncate.AtEnd
		return label
	end
	local back = box("Frame", 0, 0, W, H)
	back.BackgroundColor3 = INK
	line("LEVEL " .. level, 0.3, 0.3, W - 0.6, 0.44, 0.36, MINT, Enum.Font.RobotoMono)
	line("FASTEST", 0.2, 0.76, W - 0.4, 0.8, 0.74, PALE, Enum.Font.GothamBlack)
	line("ESCAPES", 0.2, 1.5, W - 0.4, 0.8, 0.74, PALE, Enum.Font.GothamBlack)
	local rule = box("Frame", 0.4, 2.42, W - 0.8, 0.04)
	rule.BackgroundColor3 = MINT
	local parts = {podium = {}, rows = {}}
	for place, plain in ipairs(PODIUM) do
		local style = look.podium and setmetatable({colour = look.podium[place]}, {__index = plain}) or plain
		local card = box("Frame", 0.25, style.top, W - 0.5, style.height)
		card.BackgroundColor3 = CARD
		local bar = box("Frame", 0.25, style.top, 0.12, style.height)
		bar.BackgroundColor3 = style.colour
		local rank = line(tostring(place), 0.42, style.top, 0.9, style.height, style.rank, style.colour, Enum.Font.GothamBlack)
		local name = line("", 1.38, style.top + style.height * 0.1, W - 1.75, style.height * 0.42, style.name, style.colour,
			Enum.Font.GothamBold, Enum.TextXAlignment.Left)
		local time = line("", 1.38, style.top + style.height * 0.5, W - 1.75, style.height * 0.44, style.time,
			style.colour:Lerp(look.podium and Color3.new(0, 0, 0) or Color3.new(1, 1, 1), 0.45), Enum.Font.GothamBlack, Enum.TextXAlignment.Left)
		parts.podium[place] = {rank = rank, name = name, time = time}
	end
	for index = 1, TOP - #PODIUM do
		local y = ROWS_TOP + (index - 1) * ROW_STEP
		if index % 2 == 1 then
			local stripe = box("Frame", 0.25, y, W - 0.5, ROW_STEP)
			stripe.BackgroundColor3, stripe.BackgroundTransparency = CARD, 0.45
		end
		parts.rows[index] = {
			rank = line(tostring(index + #PODIUM), 0.3, y, 0.62, ROW_STEP, 0.3, MUTED, Enum.Font.RobotoMono),
			name = line("", 0.98, y, 2.72, ROW_STEP, 0.3, PALE, Enum.Font.GothamMedium, Enum.TextXAlignment.Left),
			time = line("", 3.72, y, 1.6, ROW_STEP, 0.3, PALE, Enum.Font.RobotoMono, Enum.TextXAlignment.Right),
		}
	end
	line("YOUR OWN TIME TO THE EXIT", 0.2, H - 0.62, W - 0.4, 0.44, 0.27, MUTED, Enum.Font.RobotoMono)
	gui.Parent = panel
	return parts
end

local function buildBoard(level)
	local signs, pads = lobby:FindFirstChild("LevelGateSigns"), lobby:FindFirstChild("PreviewQueuePads")
	local header = signs and signs:FindFirstChild("LEVEL " .. level .. " Door Header")
	local bay = pads and pads:FindFirstChild("QueueBay_Level" .. level)
	local floor, sill = bay and bay:FindFirstChild("ChamberFloor"), bay and bay:FindFirstChild("Door Threshold")
	if not (header and floor and sill) then return nil end
	local out = ((header.Position - floor.Position) * Vector3.new(1, 0, 1)).Unit          -- from the bay toward the tunnel
	local at = Vector3.new(header.Position.X, sill.Position.Y + sill.Size.Y / 2, header.Position.Z)
	local gate = CFrame.lookAt(at, at + out)                 -- X along the wall, Y up from the sidewalk, -Z into the tunnel
	-- Under the gate's arrow blade (+15 along the wall), except at Level 4, where that side is the shop's last box.
	local side = level == 4 and -1 or 1
	-- The board stands at right angles to the wall: its X runs out into the tunnel, its two faces look along it.
	local base = gate * CFrame.new(side * SIDE_OUT, 0, -STAND_OFF) * CFrame.Angles(0, math.pi / 2, 0)
	local set = Instance.new("Folder")
	set.Name = "Level " .. level .. " Leaderboard"
	set:SetAttribute(OWNED, true)
	local function piece(name, size, offset, colour, material, collide)
		local part = Instance.new("Part")
		part.Name, part.Size, part.Color, part.Material = name, size, colour, material
		part.CFrame = base * offset
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, collide, false, collide
		part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		part.CastShadow = false
		part:SetAttribute(OWNED, true)
		part.Parent = set
		return part
	end
	local panel = piece("Board", Vector3.new(W, H, 0.3), CFrame.new(0, LEG + H / 2, 0), INK, Enum.Material.SmoothPlastic, true)
	piece("Plinth", Vector3.new(W + 0.9, LEG, 1.5), CFrame.new(0, LEG / 2, 0), STEEL, Enum.Material.Metal, true)
	for _, edge in ipairs({-1, 1}) do
		piece("Upright", Vector3.new(0.26, H + 0.26, 0.44), CFrame.new(edge * (W / 2 + 0.13), LEG + H / 2 + 0.13, 0), STEEL, Enum.Material.Metal, false)
	end
	piece("Cap", Vector3.new(W + 0.52, 0.26, 0.44), CFrame.new(0, LEG + H + 0.13, 0), STEEL, Enum.Material.Metal, false)
	piece("CapGlow", Vector3.new(W, 0.07, 0.48), CFrame.new(0, LEG + H - 0.02, 0), MINT, Enum.Material.Neon, false)
	-- the arm that holds it to the wall, as the arrow blade above it is held (the wall is toward -X here)
	piece("WallArm", Vector3.new(2.2, 0.26, 0.26), CFrame.new(-(W / 2 + 1.1), LEG + H - 0.6, 0), STEEL, Enum.Material.Metal, false)
	local record = {faces = {buildFace(panel, Enum.NormalId.Front, level), buildFace(panel, Enum.NormalId.Back, level)}}
	set.Parent = lobby
	return record
end

redraw = function(level)
	local board, rows = boards[level], shown[level] or {}
	if not board then return end
	for _, face in ipairs(board.faces) do
		for place = 1, TOP do
			local row = rows[place]
			local slot = place <= #PODIUM and face.podium[place] or face.rows[place - #PODIUM]
			if row then
				slot.name.Text, slot.time.Text = nameOf(row.id, level), clock(row.ms)
			elseif place == 1 then
				slot.name.Text, slot.time.Text = "NO TIME YET", "BE THE FIRST"
			else
				slot.name.Text, slot.time.Text = place <= #PODIUM and "-" or "", ""
			end
		end
	end
end

local SAMPLE = {"hazmat_runner", "QuietWalker22", "xX_NoFlashlight_Xx", "mall_manager_fan", "poolroomsPro", "a",
	"TwentyCharacterNameAB", "ushers_friend", "counted_to_three", "void_jumper"}
local function read(level)
	if IS_STUDIO and workspace:GetAttribute("DevLeaderboardDemo") == true then
		local rows = {}
		for index, sample in ipairs(SAMPLE) do
			local id = -(level * 100 + index)
			names[id] = sample
			rows[index] = {id = id, ms = math.floor((95 + level * 31 + index * index * 7.37) * 1000)}
		end
		return rows
	end
	-- Studio has no access to the data stores here, and the engine prints every refused call: do not ask.
	if IS_STUDIO then return {} end
	local ok, pages = pcall(function() return store(level):GetSortedAsync(true, TOP + DEVELOPERS, MIN_SECONDS * 1000) end)
	if not ok then
		warn("[LevelLeaderboards] could not read Level " .. level .. ": " .. tostring(pages))
		return nil
	end
	local rows = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		local id = tonumber(entry.key)
		if id and DevAccess.IsAllowed(id) then
			task.spawn(function()
				local removed, problem = pcall(function() store(level):RemoveAsync(entry.key) end)
				if not removed then warn("[LevelLeaderboards] could not remove a developer row from Level " .. level .. ": " .. tostring(problem)) end
			end)
		elseif id and type(entry.value) == "number" and #rows < TOP then
			table.insert(rows, {id = id, ms = entry.value})
		end
	end
	return rows
end

-- MALL_LOBBY_20261012: the mall lobby beside this one has a notice board by each shop (LobbyMallPreview.Anchors.
-- Boards, `level1`..`level6`, front face toward the concourse). The same list is pinned to it as a printed sheet and
-- redrawn with the lobby's own.
local function buildMallSheet(level)
	local mall = workspace:FindFirstChild("LobbyMallPreview")
	local anchors = mall and mall:FindFirstChild("Anchors")
	local folder = anchors and anchors:FindFirstChild("Boards")
	local board = folder and folder:FindFirstChild("level" .. level)
	if not (board and board:IsA("BasePart")) then return nil end
	local scale = math.min((board.Size.Y - 0.5) / H, (board.Size.X - 0.5) / W)
	local sheet = Instance.new("Part")
	sheet.Name = "Level " .. level .. " Leaderboard Sheet"
	sheet.Size, sheet.Color, sheet.Material = Vector3.new(W * scale, H * scale, 0.04), PAPER.ink, Enum.Material.SmoothPlastic
	sheet.CFrame = board.CFrame * CFrame.new(0, 0, -0.1)
	sheet.Anchored, sheet.CanCollide, sheet.CanTouch, sheet.CanQuery, sheet.CastShadow = true, false, false, false, false
	sheet.Parent = board
	local look = setmetatable({pps = PPS / scale}, {__index = PAPER})
	return buildFace(sheet, Enum.NormalId.Front, level, look)
end

for level = 1, LEVELS do
	boards[level] = buildBoard(level)
	local sheet = buildMallSheet(level)
	if sheet then
		boards[level] = boards[level] or {faces = {}}
		table.insert(boards[level].faces, sheet)
	end
	shown[level] = {}
	redraw(level)
end
workspace:SetAttribute("LevelLeaderboards", "LEVEL_LEADERBOARDS_20261008")

-- MALL_LOBBY_20261012: the mall's big DIRECTORY board carries TOP SUPPORTERS. That board is drawn by
-- TunnelLobbyBuilder on this server (the SurfaceGui `DonationLeaderboardDisplay`); this pins a paper copy of it to
-- the mall's board and keeps the copy's text in step. Nothing about the ranking itself is touched.
task.spawn(function()
	local mall = workspace:FindFirstChild("LobbyMallPreview")
	local anchors = mall and mall:FindFirstChild("Anchors")
	local folder = anchors and anchors:FindFirstChild("Boards")
	local board = folder and folder:FindFirstChild("directory")
	if not (board and board:IsA("BasePart")) then return end
	local source
	for _ = 1, 90 do
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("SurfaceGui") and d.Name == "DonationLeaderboardDisplay" then source = d; break end
		end
		if source then break end
		task.wait(2)
	end
	if not source then return end
	local canvas = source.CanvasSize
	local width = math.min(board.Size.X - 1, (board.Size.Y - 1) * canvas.X / canvas.Y)
	local sheet = Instance.new("Part")
	sheet.Name = "Top Supporters Sheet"
	sheet.Size, sheet.Color, sheet.Material = Vector3.new(width, width * canvas.Y / canvas.X, 0.04), PAPER.ink, Enum.Material.SmoothPlastic
	sheet.CFrame = board.CFrame * CFrame.new(0, 0, -0.1)
	sheet.Anchored, sheet.CanCollide, sheet.CanTouch, sheet.CanQuery, sheet.CastShadow = true, false, false, false, false
	sheet.Parent = board
	local copy = source:Clone()
	copy.Face, copy.Adornee, copy.LightInfluence, copy.Brightness = Enum.NormalId.Front, nil, PAPER.light, 1
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("Frame") then
			local _, _, value = d.BackgroundColor3:ToHSV()
			d.BackgroundColor3 = if value < 0.35 then (if d.Parent == copy then PAPER.ink else PAPER.card) else PAPER.accent
		elseif d:IsA("TextLabel") then
			d.TextColor3 = PAPER.pale
		elseif d:IsA("UIStroke") then
			d.Color = PAPER.accent
		end
	end
	copy.Parent = sheet
	local from, to = source:GetDescendants(), copy:GetDescendants()
	while sheet.Parent and source.Parent do
		for index, d in ipairs(from) do
			local twin = to[index]
			if d:IsA("TextLabel") and twin and twin:IsA("TextLabel") and twin.Text ~= d.Text then twin.Text = d.Text end
		end
		task.wait(5)
	end
end)

local step = 0
while true do
	local level = step % LEVELS + 1
	local rows = read(level)
	if rows then
		shown[level] = rows
		redraw(level)
	end
	step += 1
	task.wait(step <= LEVELS and 1.5 or (IS_STUDIO and 4 or REFRESH_SECONDS))
end
