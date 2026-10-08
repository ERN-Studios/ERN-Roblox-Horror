-- LIVE_LEVEL_SERVERS_20261008. The half of "a server per party for Levels 5 and 6" that runs ON that server.
--
-- ServerKind says whether this is a party's own lobby started for a live level. Everywhere else this script ends
-- at once. Here it does two things:
--   IN   every arrival carries what it came for in its teleport data (LiveLevel, LiveSession, and how many are
--        coming). Arrivals of one session are one party. When the party is here and each client has said its
--        lobby is loaded (the loading screen sends "ready"), the level's own launcher takes them
--        (ServerStorage.Level5LaunchParty / Level6LaunchParty): the same handshake, join and round body the
--        queue pad gives. A latecomer of the same session is launched into the same party.
--   OUT  a player who has been in the level and is back in lobby state is sent to the PUBLIC lobby, as a round
--        server sends its players home. Players who come out in the same moment (the end of a level) travel in
--        ONE teleport, so they land in the same lobby. If Roblox refuses, they are standing in a working lobby
--        already; it is tried four times.
-- Player attribute `LiveLevelPending` (replicated): true from arrival until the launch has been tried, then
-- false. The loading screen keeps its cover up while it is true.
-- A party is never held: every wait has a cap, and a launch that cannot be made leaves its players in this lobby,
-- which works like any other.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local ServerKind = require(script.Parent:WaitForChild("ServerKind"))
local LEVEL = ServerKind.LiveLevel()
if not LEVEL then return end

local info = ServerKind.Info() or {}
local MARKER = "Level6PlaygroundPreview"       -- shared by both live levels
local READY_WAIT = 35                          -- a client that never says "ready" is taken as ready after this
local PARTY_WAIT = 12                          -- a pad launch teleports the whole party at once
local DEADLINE_GRACE = 8                       -- a CONTINUE out of Level 4 trickles in until its window closes
local HOME_TRIES, HOME_RETRY = 4, 12

local remote = ReplicatedStorage:FindFirstChild("LiveLevelArrival")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "LiveLevelArrival"
	remote.Parent = ReplicatedStorage
end

local arrivals = {}        -- player -> {session, joinedAt, ready, launched, entered, outSince, tries, nextTry}
local parties = {}         -- session -> {token, firstAt, expected, final, deadline, launching}

remote.OnServerEvent:Connect(function(player, what)
	local record = arrivals[player]
	if record and what == "ready" then record.ready = true end
end)

local function packetOf(player)
	local ok, data = pcall(function() return player:GetJoinData() end)
	local packet = ok and data and data.TeleportData
	if type(packet) == "table" and (packet.LiveLevel == 5 or packet.LiveLevel == 6) then return packet end
	if info.Simulated then return {LiveLevel = LEVEL, LiveSession = "studio", Expected = 1} end
	return nil
end

local function onPlayer(player)
	local packet = packetOf(player)
	if not packet then                      -- somebody who did not come for a level: this is a lobby, let them be
		player:SetAttribute("LiveLevelPending", false)
		return
	end
	player:SetAttribute("LiveLevelPending", true)
	local session = tostring(packet.LiveSession or "none")
	local party = parties[session]
	if not party then
		party = {token = {}, firstAt = os.clock(), expected = 1, final = false}
		parties[session] = party
	end
	local expected = tonumber(packet.Expected) or tonumber(packet.ExpectedContinuers) or 1
	party.expected = math.max(party.expected, math.floor(expected))
	if packet.FinalCohort ~= false then party.final = true end
	if type(packet.DecisionDeadline) == "number" then party.deadline = packet.DecisionDeadline end
	arrivals[player] = {session = session, joinedAt = os.clock(), tries = 0}
	print(string.format("[LiveLevelServer] %s arrived for Level %d, session %s, expecting %d", player.Name, LEVEL, session, party.expected))
end

local function standing(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and humanoid.RootPart ~= nil and character:IsDescendantOf(workspace)
end

local function launch(session, party, members)
	party.launching = true
	local launcher = ServerStorage:WaitForChild("Level" .. LEVEL .. "LaunchParty", 15)
	local entered = false
	for attempt = 1, 3 do
		local list = {}
		for _, player in ipairs(members) do
			local record = arrivals[player]
			if record and not record.entered and player.Parent == Players and standing(player)
				and player:GetAttribute(MARKER) ~= true then
				table.insert(list, player)
			end
		end
		if #list == 0 or not launcher then break end
		local ok, joined, count = pcall(launcher.Invoke, launcher, list, party.token)
		print(string.format("[LiveLevelServer] launch %d of session %s: %s %s %s", attempt, session, tostring(ok), tostring(joined), tostring(count)))
		local left = 0
		for _, player in ipairs(list) do
			local record = arrivals[player]
			if record and player:GetAttribute(MARKER) == true then
				record.entered = true
				entered = true
			elseif record then
				left += 1
			end
		end
		if left == 0 then break end
		task.wait(2.5)
	end
	-- whoever could not be taken is not asked again: they are in a lobby that works, with its pad
	for _, player in ipairs(members) do
		local record = arrivals[player]
		if record then record.launched = true end
		if player.Parent == Players then player:SetAttribute("LiveLevelPending", false) end
	end
	party.launching = false
	party.launched = party.launched or entered
end

local function cover(player, on)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	local old = playerGui:FindFirstChild("LiveLevelHomeCover")
	if old then old:Destroy() end
	if not on then return end
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "LiveLevelHomeCover", false, true, 900
	local black = Instance.new("Frame")
	black.Size, black.BackgroundColor3, black.BorderSizePixel = UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 0
	black.Parent = gui
	local line = Instance.new("TextLabel")
	line.BackgroundTransparency = 1
	line.AnchorPoint, line.Position, line.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.new(0.9, 0, 0, 40)
	line.Font, line.TextSize, line.TextColor3 = Enum.Font.GothamBold, 22, Color3.fromRGB(242, 242, 236)
	line.Text = "RETURNING TO THE LOBBY"
	line.Parent = black
	gui.Parent = playerGui
end

local function sendHome(list)
	for _, player in ipairs(list) do
		local record = arrivals[player]
		if record then
			record.tries += 1
			record.nextTry = os.clock() + HOME_RETRY
		end
	end
	local ok, problem = pcall(function()
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({ReturnToLobby = true})
		TeleportService:TeleportAsync(game.PlaceId, list, options)
	end)
	if ok then return end
	warn("[LiveLevelServer] could not send " .. #list .. " player(s) to the public lobby: " .. tostring(problem))
	for _, player in ipairs(list) do
		local record = arrivals[player]
		if record then
			record.covered = nil
			if RunService:IsStudio() then record.tries = HOME_TRIES end      -- Studio cannot teleport: once is the test
		end
		cover(player, false)
	end
end

TeleportService.TeleportInitFailed:Connect(function(player)
	local record = arrivals[player]
	if record then
		record.covered = nil
		cover(player, false)
	end
end)

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, player) end
Players.PlayerRemoving:Connect(function(player) arrivals[player] = nil end)

while true do
	task.wait(0.25)
	local now = os.clock()
	-- IN
	for session, party in pairs(parties) do
		if not party.launching then
			local waiting, present, allReady = {}, 0, true
			for player, record in pairs(arrivals) do
				if record.session == session and player.Parent == Players then
					present += 1
					if not record.launched then
						local isReady = standing(player) and (record.ready or now - record.joinedAt > READY_WAIT)
						if isReady then table.insert(waiting, player) else allReady = false end
					end
				end
			end
			if #waiting > 0 and allReady then
				local complete = party.launched                              -- a latecomer goes straight in
					or present >= party.expected
					or (party.deadline ~= nil and workspace:GetServerTimeNow() > party.deadline + DEADLINE_GRACE)
					or (party.deadline == nil and now - party.firstAt > PARTY_WAIT)
					or now - party.firstAt > 45
				if complete then task.spawn(launch, session, party, waiting) end
			end
		end
	end
	-- OUT
	local going = {}
	for player, record in pairs(arrivals) do
		if record.entered and player.Parent == Players then
			local out = player:GetAttribute(MARKER) ~= true and player:GetAttribute("InRound") ~= true
			if not out then
				record.outSince = nil
				if record.covered then
					record.covered = nil
					cover(player, false)
				end
			elseif now >= (record.nextTry or 0) then
				record.outSince = record.outSince or now
				if record.tries < HOME_TRIES then
					if not record.covered then                  -- the private lobby is not where they are going
						record.covered = true
						cover(player, true)
					end
					if now - record.outSince > 1.25 then table.insert(going, player) end
				elseif record.covered then                      -- asked four times and still here: this lobby works
					record.covered = nil
					cover(player, false)
				end
			end
		end
	end
	if #going > 0 then task.spawn(sendHome, going) end
end
