--!strict
-- Level 4 Objective UI
--
-- Attribute-driven, like Level 2's panel: the server already publishes every
-- fact on the replicated "Level 4 State" folder and this file only draws it.
-- Nothing here decides anything -- a client that lies to itself about the
-- signal count changes nothing on the server.
--
-- It draws four things:
--   * SIGNALS n/3, the shared objective, with a pip per signal.
--   * The beacon line: the finale's control count, then the exit countdown.
--   * The HOUSE line: the state of the house the SUBJECT is standing in or
--     next to. This is half of the forewarning the brief requires, and it is
--     text, so it works with the sound off.
--   * The NEIGHBOUR line, only while the entity is telegraphing or chasing.
--     A warning the player cannot hear must still be a warning they can see.
--
-- SPECTATE PARITY: the subject is the watched player while spectating, the way
-- the Level 2 panel and the Level 3 reader resolve theirs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))

local player = Players.LocalPlayer
local LEVEL = 4
local STATE_FOLDER_NAME = "Level 4 State"
local REMOTES_FOLDER_NAME = "Level 4 Remotes"

local gui = Instance.new("ScreenGui")
gui.Name = "Level4ObjectiveGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

local function syncSuppression()
	gui.Enabled = player:GetAttribute("ZyntraDispatchClientActive") ~= true
		and not UIDevice.ScreenOwningModalOpen()
end
player:GetAttributeChangedSignal("ZyntraDispatchClientActive"):Connect(syncSuppression)
UIDevice.OnScreenOwningModalChanged(syncSuppression)
syncSuppression()

-- ---------------------------------------------------------------------------
-- Chrome
-- ---------------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.Name = "Level4ObjectivePanel"
panel.Size = UDim2.fromOffset(236, 104)
panel.Visible = false
panel.Parent = gui
UIStyle.panel(panel)

local panelSize = Instance.new("UISizeConstraint")
panelSize.MinSize = Vector2.new(150, 92)
panelSize.MaxSize = Vector2.new(248, 116)
panelSize.Parent = panel

local function place()
	if UIDevice.IsTouch() then
		local column = UIDevice.ObjectiveColumn(LEVEL)
		panel.AnchorPoint = Vector2.new(0, 0)
		-- The constraint must state the same numbers the placement used, or it
		-- clamps the panel to a size nothing was measured against.
		panelSize.MinSize = Vector2.new(column.Width, column.Height)
		panelSize.MaxSize = Vector2.new(column.Width, column.Height)
		panel.Size = UDim2.fromOffset(column.Width, column.Height)
		panel.Position = UIDevice.LocalPosition(gui, column.Left, column.Top)
	else
		panel.AnchorPoint = Vector2.new(1, 1)
		panelSize.MinSize = Vector2.new(150, 92)
		panelSize.MaxSize = Vector2.new(248, 116)
		panel.Size = UDim2.fromOffset(236, 104)
		panel.Position = UDim2.new(1, -18, 1, -18)
	end
end
UIDevice.Changed:Connect(place)
place()

local function label(name: string, y: number, height: number): TextLabel
	local object = Instance.new("TextLabel")
	object.Name = name
	object.BackgroundTransparency = 1
	object.Position = UDim2.new(0, UIStyle.Pad.X, 0, y)
	object.Size = UDim2.new(1, -UIStyle.Pad.X * 2, 0, height)
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextTruncate = Enum.TextTruncate.AtEnd
	object.Text = ""
	object.Parent = panel
	return object
end

local eyebrow = UIStyle.readout(label("Eyebrow", 8, 12), {TextSize = UIStyle.TextSize.Eyebrow})
eyebrow.Text = "> ZYNTRA RESIDENTIAL TEST SITE"
local signalLine = UIStyle.title(label("Signals", 22, 20))
local beaconLine = UIStyle.body(label("Beacon", 44, 16))
local houseLine = UIStyle.body(label("House", 62, 16), {TextColor = UIStyle.Color.Muted})
local threatLine = UIStyle.readout(label("Threat", 80, 16), {TextColor = UIStyle.Color.Warning})

-- A transient banner for the briefing and the house forewarnings. Bottom
-- centre, clear of the objective column and of the movement zones.
local banner = Instance.new("TextLabel")
banner.Name = "Level4Banner"
banner.AnchorPoint = Vector2.new(0.5, 1)
banner.Position = UDim2.new(0.5, 0, 1, -110)
banner.Size = UDim2.fromOffset(520, 44)
banner.TextXAlignment = Enum.TextXAlignment.Center
banner.TextTruncate = Enum.TextTruncate.AtEnd
banner.Text = ""
banner.Visible = false
banner.Parent = gui
UIStyle.caption(banner)
UIStyle.body(banner, {TextSize = UIStyle.TextSize.Body})

local bannerSerial = 0
local function showBanner(text: string, tone: string, seconds: number)
	bannerSerial += 1
	local serial = bannerSerial
	banner.Text = text
	banner.TextColor3 = tone == "warn" and UIStyle.Color.WarningText
		or tone == "bad" and UIStyle.Color.DangerText
		or UIStyle.Color.Body
	banner.Visible = true
	task.delay(math.clamp(seconds, 2, 14), function()
		if bannerSerial == serial then banner.Visible = false end
	end)
end

-- ---------------------------------------------------------------------------
-- Subject resolution and state reads
-- ---------------------------------------------------------------------------

local function subjectRoot(): BasePart?
	if player:GetAttribute("Spectating") == true then
		local userId = player:GetAttribute("SpectateTargetUserId")
		local watched = type(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
		local character = watched and watched.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then return root end
		return nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function stateFolder(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(STATE_FOLDER_NAME)
	return folder and folder:IsA("Folder") and folder or nil
end

local HOUSE_TEXT = {
	SAFE = "SHELTER: STABLE",
	WARNED = "SHELTER: UNSTABLE -- LEAVE",
	DANGEROUS = "SHELTER: LOST",
}
local HOUSE_COLOR = {
	SAFE = UIStyle.Color.Positive,
	WARNED = UIStyle.Color.WarningText,
	DANGEROUS = UIStyle.Color.DangerText,
}

-- The house the subject is standing IN, by its InteriorVolume -- the same box
-- the server's IsSheltered and the warning both use.
local function houseAround(root: BasePart): Model?
	local world = workspace:FindFirstChild("Level 4 Generated World")
	if not world then return nil end
	for _, child in ipairs(world:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Level4_HouseState") ~= nil then
			local volume = child:FindFirstChild("InteriorVolume")
			if volume and volume:IsA("BasePart") then
				local offset = volume.CFrame:PointToObjectSpace(root.Position)
				local half = volume.Size * 0.5
				if math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z then
					return child
				end
			end
		end
	end
	return nil
end

-- The nearest house model to the subject, within a lot's own reach. The house
-- state is replicated on the Model, so this needs no remote at all.
local function nearestHouseState(root: BasePart): (string?, number)
	local world = workspace:FindFirstChild("Level 4 Generated World")
	if not world then return nil, math.huge end
	local best, bestDistance = nil, math.huge
	for _, child in ipairs(world:GetChildren()) do
		-- Only a house you can actually get inside counts as shelter, so a
		-- decorative shell never reports "STABLE" at you from across the road.
		if child:IsA("Model") and child:GetAttribute("Level4_HouseState") ~= nil
			and child:FindFirstChild("InteriorVolume") ~= nil then
			local primary = child.PrimaryPart
			if primary then
				local distance = (primary.Position - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = child:GetAttribute("Level4_HouseState"), distance
				end
			end
		end
	end
	return best, bestDistance
end

local function pips(done: number, goal: number): string
	local text = ""
	for index = 1, goal do
		text ..= index <= done and "[#]" or "[ ]"
	end
	return text
end

local function refresh()
	local folder = stateFolder()
	if workspace:GetAttribute("SelectedLevel") ~= LEVEL or not folder then
		panel.Visible = false
		banner.Visible = false
		return
	end
	panel.Visible = true

	local goal = tonumber(folder:GetAttribute("Level4_SignalGoal")) or 3
	local done = tonumber(folder:GetAttribute("Level4_SignalProgress")) or 0
	signalLine.Text = ("SIGNALS %d/%d  %s"):format(done, goal, pips(done, goal))
	signalLine.TextColor3 = done >= goal and UIStyle.Color.Live or UIStyle.Color.Title

	if folder:GetAttribute("Level4_ExitOpen") == true then
		beaconLine.Text = "TRANSIT DOOR OPEN"
		beaconLine.TextColor3 = UIStyle.Color.Live
	elseif folder:GetAttribute("Level4_BeaconUnlocked") == true then
		local warningEndsAt = tonumber(folder:GetAttribute("Level4_ExitWarningEndsAt")) or 0
		local remaining = warningEndsAt - workspace:GetServerTimeNow()
		if warningEndsAt > 0 and remaining > 0 then
			beaconLine.Text = ("DOOR OPENS IN %d"):format(math.ceil(remaining))
			beaconLine.TextColor3 = UIStyle.Color.WarningText
		else
			local controls = tonumber(folder:GetAttribute("Level4_CabinetProgress")) or 0
			local controlGoal = tonumber(folder:GetAttribute("Level4_CabinetGoal")) or 3
			beaconLine.Text = ("BEACON CONTROLS %d/%d"):format(controls, controlGoal)
			beaconLine.TextColor3 = UIStyle.Color.Body
		end
	else
		beaconLine.Text = "BEACON: LOCKED"
		beaconLine.TextColor3 = UIStyle.Color.Muted
	end

	local root = subjectRoot()
	if root then
		-- CALM_ARRIVAL_20260922: inside a house the line names THAT house and,
		-- while it is warned, counts down the time left to leave -- text, not
		-- only a colour. Outside, the nearest shelter as before.
		local inside = houseAround(root)
		local insideState = inside and inside:GetAttribute("Level4_HouseState")
		if inside and insideState then
			local lotId = tostring(inside:GetAttribute("Level4_LotId") or "?")
			if insideState == "WARNED" then
				local endsAt = tonumber(inside:GetAttribute("Level4_HouseStateEndsAt")) or 0
				local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
				houseLine.Text = ("LEAVE HOUSE %s -- %ds LEFT"):format(lotId, left)
			elseif insideState == "DANGEROUS" then
				houseLine.Text = ("HOUSE %s DARK -- NOT SAFE HERE"):format(lotId)
			else
				houseLine.Text = ("HOUSE %s -- SHELTER STABLE"):format(lotId)
			end
			houseLine.TextColor3 = HOUSE_COLOR[insideState] or UIStyle.Color.Muted
		else
			local houseState, distance = nearestHouseState(root)
			if houseState and distance <= 34 then
				houseLine.Text = HOUSE_TEXT[houseState] or ("SHELTER: " .. tostring(houseState))
				houseLine.TextColor3 = HOUSE_COLOR[houseState] or UIStyle.Color.Muted
			else
				houseLine.Text = "SHELTER: NONE NEARBY"
				houseLine.TextColor3 = UIStyle.Color.Muted
			end
		end
	else
		houseLine.Text = ""
	end

	local neighbour = folder:GetAttribute("Level4_NeighbourState")
	if neighbour == "ALERT" then
		threatLine.Text = "!! YOU HAVE BEEN SEEN"
		threatLine.TextColor3 = UIStyle.Color.WarningText
	elseif neighbour == "CHASE" then
		threatLine.Text = "!! PURSUIT -- BREAK THE LINE"
		threatLine.TextColor3 = UIStyle.Color.DangerText
	elseif neighbour == "SEARCH" or neighbour == "INVESTIGATE" then
		threatLine.Text = "> SOMETHING IS LOOKING"
		threatLine.TextColor3 = UIStyle.Color.Warning
	else
		threatLine.Text = ""
	end
end

-- ---------------------------------------------------------------------------
-- Server messages
-- ---------------------------------------------------------------------------

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 60)
	local event = remotes and remotes:WaitForChild("ClientEvent", 60)
	if not (event and event:IsA("RemoteEvent")) then return end
	event.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		if payload.Type == "Alert" then
			showBanner(tostring(payload.Detail or payload.Title or ""),
				tostring(payload.Tone or "info"), tonumber(payload.Duration) or 5)
		elseif payload.Type == "House" and payload.State == "WARNED" then
			-- CALM_ARRIVAL_20260922. The order to leave is for the people INSIDE
			-- (the server marks them); outside, a short note only when the house
			-- is near enough to matter, and nothing at all across the map.
			local seconds = math.max(1, tonumber(payload.Seconds) or 10)
			if payload.Occupant == true then
				showBanner(("HOUSE %s IS GOING DARK -- LEAVE WITHIN %ds")
					:format(tostring(payload.LotId), seconds), "warn", math.max(4, seconds))
			else
				local root = subjectRoot()
				local world = workspace:FindFirstChild("Level 4 Generated World")
				local house = world and world:FindFirstChild("House_" .. tostring(payload.LotId))
				local primary = house and house:IsA("Model") and house.PrimaryPart
				if root and primary and (primary.Position - root.Position).Magnitude <= 70 then
					showBanner(("HOUSE %s UNSTABLE -- STAY OUT"):format(tostring(payload.LotId)), "info", 3)
				end
			end
		elseif payload.Type == "House" and payload.State == "DANGEROUS" and payload.Occupant == true then
			showBanner(("HOUSE %s IS DARK -- GET OUT"):format(tostring(payload.LotId)), "warn", 4)
		elseif payload.Type == "Signal" then
			showBanner(("SIGNAL %02d LOGGED  //  %d/%d"):format(
				tonumber(payload.Index) or 0, tonumber(payload.Progress) or 0,
				tonumber(payload.Goal) or 3), "info", 4)
		end
		refresh()
	end)
end)

-- DEV_RETRY_20260922. A dev-only Level 4 round has no lobby bay to retry from,
-- so GameManager raises this instead of RetryGuideLevel; say how to go again.
local DEV_HINT = "LEVEL 4 DEV ROUND ENDED -- ServerStorage.Level4DevStart:Invoke() TO RUN AGAIN"
local function syncDevHint()
	if player:GetAttribute("Level4DevRoundEnded") == true then
		bannerSerial += 1 -- no timer hides it; it stands until the next dev round clears the attribute
		banner.Text = DEV_HINT
		banner.TextColor3 = UIStyle.Color.Body
		banner.Visible = true
	elseif banner.Text == DEV_HINT then
		banner.Visible = false
	end
end
player:GetAttributeChangedSignal("Level4DevRoundEnded"):Connect(syncDevHint)
syncDevHint()

-- Five times a second, not every frame. The only moving number on the panel is
-- a countdown shown in whole seconds, and the house read walks the world's
-- top-level children -- neither belongs in a Heartbeat.
task.spawn(function()
	while true do
		local ok, problem = pcall(refresh)
		if not ok then warn("[Level 4] objective UI refresh failed: " .. tostring(problem)) end
		task.wait(0.2)
	end
end)

refresh()
