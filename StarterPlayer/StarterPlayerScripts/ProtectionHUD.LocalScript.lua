-- Stored equipment: Entity Shield charges, Speed Potions and Route Markers.
-- Inventory and activation remain server-owned; this file shows what the server
-- published and asks it for an action. It decides nothing.
--
-- EQUIPMENT_HUD_20260916 (Trello #101). What changed, and what deliberately did
-- not:
--   * the lone shield chip became an EQUIPMENT panel drawn in the objectives
--     panel's own language. Every colour, face, radius and stroke comes from
--     UIStyle, which is where PuzzleUI's Level1Objectives numbers already live,
--     so nothing is restated here and the two surfaces cannot drift apart.
--   * two siblings joined it: Speed Potion (T) and Route Markers (X). They are
--     ROWS of the same panel and, on touch, slots of the same reserved control
--     cluster, so the three inventory actions read and reach the same way.
--   * every shield semantic is untouched. ProtectionClient still owns the
--     request and the retry, canPress still decides, Q / D-PAD DOWN still press
--     it, and while SPECTATING this HUD is still the read-only "SAFE 4.2s"
--     mirror of the watched player's shield with nothing else drawn and no
--     control rect registered.
--   * a player who owns no potions and no markers sees exactly what shipped
--     before: one shield row, and no clutter. The panel never exceeds three
--     rows, which is its whole inventory.
--
-- NO TWEEN, NO PULSE, ANYWHERE. A HUD that animates unconditionally cannot
-- honour ReduceFlashing/ReduceCameraShake, so this one simply does not animate;
-- the potion's countdown text changing each frame is the only motion.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
-- UI_STYLE_20260915 (Trello #98): chrome only. This control was already the
-- closest thing in the game to the reference; it was missing the stroke's
-- transparency, so its border read a full step harder than every panel's.
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))
local Client = require(ReplicatedStorage:WaitForChild("ProtectionClient"))
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))

-- ProtectionClient has already waited for both of these, so neither yields.
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("ZyntraAction")
local profileChanged = remotes:WaitForChild("ZyntraProfileChanged")
-- RouteMarkerService creates this one, and it is the only thing that can place
-- a marker. Resolved off the main thread so a build without it costs this HUD
-- nothing: the marker row simply never appears.
local markerRemote = nil
local detectorRemote = nil

-- The item numbers belong to ZyntraConfig (the owner tunes them there); these
-- reads only exist so the readout cannot print a cap the server does not use.
local ITEMS = Config.Items or {}
local MAX_MARKERS = (ITEMS.RouteMarker and ITEMS.RouteMarker.MaxActive) or 3
local POTION_SECONDS = (ITEMS.SpeedPotion and ITEMS.SpeedPotion.DurationSeconds) or 6

-- Panel metrics, in the reference's own idiom (PuzzleUI LAYOUT / UIStyle.Pad).
local PANEL_WIDTH = 300
local PAD_X, PAD_TOP, PAD_BOTTOM = 12, 22, UIStyle.Pad.Bottom
local ROW_HEIGHT, ROW_GAP = 30, UIStyle.Pad.RowGap
local ROW_PAD, NAME_WIDTH, COLUMN_GAP = 10, 96, 8
local TEXT_HEIGHT, KEY_HEIGHT = 18, 18
local CAPTION_HEIGHT, CAPTION_GAP, CAPTION_SECONDS = 22, 6, 2
-- The opaque chip face the touch control shipped with. A control laid over the
-- world has to be readable against it, so the touch rows keep it rather than
-- the panel row's translucency.
local TOUCH_CHIP = Color3.fromRGB(20, 35, 31)
local DIMMED = .3

local gui = Instance.new("ScreenGui")
gui.Name = "ProtectionHUD"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
-- Living players can cancel an L1 capture through this control. Real modals
-- and loading covers suppress it explicitly; JumpscareGui has order 1000.
gui.DisplayOrder = 1001
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "EquipmentPanel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Visible = false
panel.Parent = gui
UIStyle.panel(panel, {Radius = UIStyle.Radius.Panel})

do
	local accent = Instance.new("Frame")
	accent.Name = "SignalAccent"
	accent.Position = UDim2.fromOffset(0, 12)
	accent.Size = UDim2.new(0, UIStyle.Pad.AccentWidth, 1, -24)
	accent.BackgroundColor3 = UIStyle.Color.Accent
	accent.BackgroundTransparency = .14
	accent.BorderSizePixel = 0
	accent.Parent = panel
	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(1, 0)
	accentCorner.Parent = accent

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Name = "Eyebrow"
	eyebrow.Position = UDim2.fromOffset(PAD_X + 4, 7)
	eyebrow.Size = UDim2.new(1, -(PAD_X + 4) * 2, 0, 13)
	eyebrow.BackgroundTransparency = 1
	eyebrow.Text = "EQUIPMENT"
	eyebrow.TextXAlignment = Enum.TextXAlignment.Left
	eyebrow.Parent = panel
	UIStyle.readout(eyebrow, {TextSize = UIStyle.TextSize.Eyebrow})
end

-- One transient line for the things a row cannot say by itself: the server
-- refusing a marker, or a profile push arriving with an error tone mid-round.
local caption = Instance.new("TextLabel")
caption.Name = "EquipmentCaption"
caption.AnchorPoint = Vector2.new(0, 1)
caption.Size = UDim2.fromOffset(PANEL_WIDTH, CAPTION_HEIGHT)
caption.Text = ""
caption.Visible = false
caption.Parent = gui
UIStyle.caption(caption)
UIStyle.body(caption, {TextSize = 12, TextColor = UIStyle.Color.Caption3})

local reentryNotice = Instance.new("TextLabel")
reentryNotice.Name = "ReentryGrace"
reentryNotice.AnchorPoint = Vector2.new(.5, 1)
reentryNotice.Visible = false
reentryNotice.Parent = gui
UIStyle.caption(reentryNotice)
UIStyle.body(reentryNotice, {TextSize = 16, TextColor = UIStyle.Color.Live})
reentryNotice.TextWrapped = true

local connections, characterConnections = {}, {}
local boundCharacter, boundHumanoid
local healthConnection
local touch, registered, destroyed = false, false, false
local held = {}
local mirroring = false
local captionUntil = 0
local lastFired = {}
local applyLayout

local function connect(signal, callback, list)
	local connection = signal:Connect(callback)
	table.insert(list or connections, connection)
	return connection
end

local function disconnectAll(list)
	for _, connection in ipairs(list) do connection:Disconnect() end
	table.clear(list)
end

-- A keycap chip is sized from its own text rather than measured after a render
-- pass, because the binding is not always three characters: a gamepad-only
-- desktop is served "[D-PAD DOWN]", and a reserved constant would have let that
-- run straight through the readout beside it. Code at 11px advances ~6.6px.
local function keyChipWidth(text: string): number
	return #text * 7 + 10
end

local ROWS
do
	local function label(parent, name, x, width)
		local text = Instance.new("TextLabel")
		text.Name = name
		text.AnchorPoint = Vector2.new(0, .5)
		text.Position = UDim2.new(0, x, .5, 0)
		text.Size = UDim2.new(0, width, 0, TEXT_HEIGHT)
		text.BackgroundTransparency = 1
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.ZIndex = 3
		text.Parent = parent
		return text
	end

	local function makeRow(key, title, short, keyboard, gamepad)
		local button = Instance.new("TextButton")
		button.Name = key
		button.Size = UDim2.fromOffset(PANEL_WIDTH - PAD_X * 2, ROW_HEIGHT)
		button.AnchorPoint = Vector2.new(0, 1)
		button.Text = ""
		button.TextWrapped = false
		button.AutoButtonColor = false
		button.Selectable = false
		button.Modal = false
		button.Active = false
		button.Visible = false
		button.ZIndex = 2
		button.Parent = gui
		-- The reference's row treatment, and the soft green the objectives
		-- toggle prints in. TextSize is rewritten per form factor in
		-- applyLayout (10 in a touch slot), so the seed here is the pointer one.
		UIStyle.button(button, {
			Transparency = UIStyle.Transparency.Row,
			Radius = UIStyle.Radius.Chip,
			StrokeTransparency = UIStyle.Stroke.RowTransparency,
			TextColor = UIStyle.Color.Live,
			TextSize = 12,
		})
		local nameLabel = label(button, "ItemName", ROW_PAD, NAME_WIDTH)
		UIStyle.title(nameLabel, {TextSize = UIStyle.TextSize.Body})
		local readout = label(button, "Readout", ROW_PAD + NAME_WIDTH + COLUMN_GAP, 0)
		UIStyle.readout(readout, {TextSize = 12, TextColor = UIStyle.Color.Body})

		local chip = Instance.new("TextLabel")
		chip.Name = "KeyChip"
		chip.AnchorPoint = Vector2.new(1, .5)
		chip.Position = UDim2.new(1, -ROW_PAD, .5, 0)
		chip.Size = UDim2.fromOffset(keyChipWidth("[Q]"), KEY_HEIGHT)
		chip.Text = ""
		chip.ZIndex = 3
		chip.Parent = button
		UIStyle.panel(chip, {
			Background = UIStyle.Color.Chip,
			Transparency = UIStyle.Transparency.Chip,
			Radius = UIStyle.Radius.Key,
			Stroke = UIStyle.Color.LineSoft,
			StrokeTransparency = UIStyle.Stroke.SoftTransparency,
		})
		UIStyle.readout(chip, {TextSize = 11})

		local enterHover, leaveHover = UIStyle.hover(button, UIStyle.Color.Control, UIStyle.Color.ControlHover)
		table.insert(connections, enterHover)
		table.insert(connections, leaveHover)
		return {Key = key, Title = title, Short = short, Keyboard = keyboard, Gamepad = gamepad,
			Button = button, Name = nameLabel, Readout = readout, Chip = chip, Slotted = true}
	end

	-- Index 1 is the BOTTOM row on the panel and the lowest touch slot, i.e.
	-- exactly where the shield already sits on both.
	ROWS = {
		makeRow("ProtectionUse", "Entity Shield", "SHIELD", "Q", "D-PAD DOWN"),
		makeRow("SpeedPotionUse", "Speed Potion", "POTION", "T", nil),
		makeRow("RouteMarkerPlace", "Route Markers", "MARKER", "X", nil),
		makeRow("EntityDetectorScan", "Detector", "SCAN", "Z", "D-PAD LEFT"),
	}
end

local KEY_ROWS = {
	[Enum.KeyCode.Q] = 1, [Enum.KeyCode.DPadDown] = 1,
	[Enum.KeyCode.T] = 2,
	[Enum.KeyCode.X] = 3,
	[Enum.KeyCode.Z] = 4, [Enum.KeyCode.DPadLeft] = 4,
}

-- RouteMarkerService's whole vocabulary, kept short enough for one line.
-- Anything it sends that is not listed is shown verbatim rather than swallowed,
-- so a reason added server-side is visible on a client built before it.
-- There is deliberately no "at the cap" refusal: the service retires the OLDEST
-- marker instead, which is why the row stays pressable at 3/3.
local REFUSALS = {
	NoMarkers = "NO MARKERS LEFT",
	RateLimited = "TOO SOON",
	Hiding = "NOT WHILE HIDING",
	NotInRound = "NOT NOW",
	NoCharacter = "NOT NOW",
	Unavailable = "NOT NOW",
}

local function covered()
	local roundGui = playerGui:FindFirstChild("RoundGui")
	if not roundGui or not roundGui.Enabled then return false end
	-- These are the actual RoundUI frames, including the brief interval before
	-- their corresponding replicated/modal attributes catch up.
	for _, name in ipairs({"LevelLoading", "QueueHostShade"}) do
		local frame = roundGui:FindFirstChild(name)
		if frame and frame.Visible then return true end
	end
	return false
end

local function contextAvailable()
	return not destroyed and boundCharacter ~= nil and player.Character == boundCharacter
		and boundCharacter.Parent ~= nil and boundHumanoid ~= nil
		and boundCharacter:FindFirstChildOfClass("Humanoid") == boundHumanoid
		and boundHumanoid.Health > 0 and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true and player:GetAttribute("Spectating") ~= true
		and player:GetAttribute("Level2_ExitTransition") ~= true
		and workspace:GetAttribute("RoundActive") == true
		and workspace:GetAttribute("RoundLoadingState") == "ready"
		and player:GetAttribute("RoundEntryControlsReady") == true
		and player:GetAttribute("DispatchBriefingOpen") ~= true
		and not UIDevice.ScreenOwningModalOpen() and not covered()
		and not GuiService.MenuIsOpen and UIS:GetFocusedTextBox() == nil
end

-- SPECTATE_UI_PARITY_20260914 -- the player we are WATCHING, or nil.
-- SpectateController publishes `Spectating` / `SpectateTargetUserId` on the
-- LocalPlayer. A subject only counts while they are a living, in-round,
-- non-escaped participant, i.e. exactly the players SpectateController picks.
local function spectateSubject()
	if player:GetAttribute("Spectating") ~= true then return nil end
	local userId = player:GetAttribute("SpectateTargetUserId")
	local watched = type(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
	if not watched or watched:GetAttribute("InRound") ~= true
		or watched:GetAttribute("Escaped") == true then return nil end
	local character = watched.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") then
		return watched
	end
	return nil
end

-- PlayerProtectionActive / PlayerProtectionExpiresAt are SERVER-set on the
-- Player (ServerScriptService/PlayerProtection.ModuleScript.lua), so they
-- replicate and the watched player's shield can be read for anyone.
local function secondsRemaining(subject)
	subject = subject or player
	local expires = subject:GetAttribute("PlayerProtectionExpiresAt")
	if subject:GetAttribute("PlayerProtectionActive") ~= true or type(expires) ~= "number"
		or expires ~= expires or expires == math.huge or expires == -math.huge then return 0 end
	local duration = subject:GetAttribute("PlayerProtectionSource") == "Reentry" and 10 or 5
	return math.clamp(expires - workspace:GetServerTimeNow(), 0, duration)
end

local function canPress(state, remaining)
	if not contextAvailable() or GuiService.SelectedObject ~= nil then return false end
	if state.Pending then
		-- Q never retries a shop purchase. Both views still share one owner.
		return state.Pending.Action == "UseProtection" and state.CanRetry == true
	end
	return remaining <= 0 and state.Available == true and not state.ServerPending and state.Charges > 0
end

-- A replicated count, defensively. A missing, NaN, negative or fractional
-- attribute is a server that has not published yet, never an inventory.
local function storedCount(name: string): number
	local value = player:GetAttribute(name)
	if type(value) ~= "number" or value ~= value or value == math.huge then return 0 end
	return math.max(0, math.floor(value))
end

local function potionRemaining(): number
	local expires = player:GetAttribute("ZyntraSpeedBoostUntil")
	if type(expires) ~= "number" or expires ~= expires
		or expires == math.huge or expires == -math.huge then return 0 end
	-- Clamped to the configured duration for the same reason the shield's is:
	-- a stale or absurd attribute must not print a countdown of its own making.
	return math.clamp(expires - workspace:GetServerTimeNow(), 0, POTION_SECONDS)
end

-- Every row answers the same four questions -- is it drawn, may it be pressed,
-- what does it say on a panel, what does it say in a 58px slot -- so the panel
-- reads evenly and press() and refresh() cannot disagree about any of them.
local function computeStates()
	local available = contextAvailable()
	local states = {Available = available}

	do -- 1. ENTITY SHIELD. The shipped logic verbatim, split into the row's slots.
		local state = Client.GetState()
		local remaining = secondsRemaining()
		local pressable = canPress(state, remaining)
		local count = state.Charges > 99 and "99+" or tostring(state.Charges)
		local title, short = "Entity Shield", "SHIELD"
		local detail, shortDetail
		if remaining > 0 then
			title = pressable and "RETRY" or "SAFE"
			short = title
			detail = string.format("%.1fs", remaining)
		elseif state.Pending then
			detail = pressable and "RETRY" or "WAIT"
		elseif not state.Available or state.ServerPending then
			detail = "WAIT"
		else
			detail, shortDetail = count .. " CHARGES", "x" .. count
		end
		states[1] = {Visible = available, Enabled = pressable,
			Lit = pressable or remaining > 0, Live = remaining > 0,
			Title = title, Short = short, Detail = detail, ShortDetail = shortDetail or detail}
	end

	do -- 2. SPEED POTION. One use per round; the server owns both facts below.
		local stored = storedCount("ZyntraSpeedPotions")
		local used = player:GetAttribute("ZyntraSpeedPotionUsedThisRound") == true
		local remaining = potionRemaining()
		local detail, shortDetail, enabled
		if remaining > 0 then
			detail = string.format("ACTIVE %.1fs", remaining)
			shortDetail = string.format("%.1fs", remaining)
			enabled = false
		elseif used then
			detail, shortDetail, enabled = "USED THIS ROUND", "USED", false
		else
			detail, shortDetail = stored .. " STORED", "x" .. stored
			enabled = stored > 0
		end
		-- Owning nothing means the row is not there at all: that is what keeps
		-- the single-shield HUD exactly as it shipped for most players.
		states[2] = {Visible = available and (stored > 0 or remaining > 0 or used),
			Enabled = available and enabled, Lit = enabled or remaining > 0,
			Live = remaining > 0, Title = "Speed Potion", Short = "POTION",
			Detail = detail, ShortDetail = shortDetail}
	end

	do -- 3. ROUTE MARKERS. Stored and placed are two different counts.
		local stored = storedCount("ZyntraRouteMarkers")
		local placed = math.min(storedCount("RouteMarkersActive"), MAX_MARKERS)
		-- Pressable at the cap too. RouteMarkerService retires the oldest marker
		-- rather than refusing, so a row greyed out at 3/3 would be a lie.
		local enabled = stored > 0
		-- `placed > 0` keeps the row up after the last marker leaves the
		-- inventory, which is exactly when the player wants to read "3/3".
		states[3] = {Visible = markerRemote ~= nil and available and (stored > 0 or placed > 0),
			Enabled = available and enabled, Lit = enabled, Live = false,
			Title = "Route Markers", Short = "MARKER",
			Detail = stored .. " STORED · " .. placed .. "/" .. MAX_MARKERS .. " PLACED",
			ShortDetail = placed .. "/" .. MAX_MARKERS}
	end
 do -- Server-published snapshot; the client never determines danger.
  local now=workspace:GetServerTimeNow()
  local remaining=math.max(0,(player:GetAttribute("ZyntraDetectorReadyAt") or 0)-now)
  local live=(player:GetAttribute("ZyntraDetectorReadingUntil") or 0)>now
  local reading=live and player:GetAttribute("ZyntraDetectorReading") or nil
  local owned=player:GetAttribute("ZyntraOwnsEntityDetector")==true
  local detail=reading or (remaining>0 and (math.ceil(remaining).."s") or "READY")
  states[4]={Visible=available and owned and detectorRemote~=nil,
   Enabled=available and owned and remaining<=0, Lit=live or remaining<=0,Live=live,
   Title="Detector",Short="SCAN",Detail=detail,ShortDetail=detail}
 end
	return states
end

local function showCaption(text)
	if type(text) ~= "string" or text == "" then return end
	caption.Text = text
	captionUntil = os.clock() + CAPTION_SECONDS
end

-- The panel and the caption, placed for a POINTER device. Touch takes its
-- geometry from the control plan instead and draws no panel chrome at all.
local function placePointer(states)
	local layout = UIDevice.Layout()
	local shown = 0
	for index = 1, #ROWS do
		if states[index].Visible then shown += 1 end
	end
	panel.Visible = shown > 0
	if shown == 0 then return end
	local height = PAD_TOP + shown * ROW_HEIGHT + (shown - 1) * ROW_GAP + PAD_BOTTOM
	-- The desktop torch ends at x84. Stamina sits near bottom 22. The panel
	-- starts at x98 and ends 92px above the bottom, away from both, and grows
	-- UPWARD from there -- never through the safe area's own top.
	local rightmost = math.max(layout.Safe.Left + 8, layout.Safe.Right - PANEL_WIDTH - 8)
	local left = math.clamp(gui.AbsolutePosition.X + 98, layout.Safe.Left + 8, rightmost)
	local lowest = math.min(layout.Safe.Bottom - 8, layout.Safe.Top + 8 + height)
	local bottom = math.clamp(gui.AbsolutePosition.Y + gui.AbsoluteSize.Y - 92,
		lowest, layout.Safe.Bottom - 8)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, height)
	panel.Position = UIDevice.LocalPosition(gui, left, bottom)
	local rank = 0
	for index, row in ipairs(ROWS) do
		if states[index].Visible then
			rank += 1
			row.Button.Size = UDim2.fromOffset(PANEL_WIDTH - PAD_X * 2, ROW_HEIGHT)
			row.Button.Position = UIDevice.LocalPosition(gui, left + PAD_X,
				bottom - PAD_BOTTOM - (rank - 1) * (ROW_HEIGHT + ROW_GAP))
		end
	end
	caption.Size = UDim2.fromOffset(PANEL_WIDTH, CAPTION_HEIGHT)
	caption.Position = UIDevice.LocalPosition(gui, left, bottom + CAPTION_GAP + CAPTION_HEIGHT)
end

local function placeTouchCaption()
	-- ModalArea is UIDevice's own answer to "where may an overlay that takes no
	-- input live", already clear of the thumbstick, the jump button and the
	-- control cluster. A transient caption is exactly that.
	local area = UIDevice.Layout().ModalArea
	local width = math.clamp(area.Width, 120, PANEL_WIDTH)
	caption.Size = UDim2.fromOffset(width, CAPTION_HEIGHT)
	caption.Position = UIDevice.LocalPosition(gui,
		(area.Left + area.Right) * .5 - width * .5, area.Bottom)
end

local function refresh()
	if destroyed then return end
	reentryNotice.Visible = false
	local subject = spectateSubject()
	if (subject ~= nil) ~= mirroring then
		mirroring = subject ~= nil
		applyLayout() -- re-places the buttons and (un)registers the control rects
		return        -- ...and tail-calls this function with the flip consumed
	end
	-- SPECTATE_UI_PARITY_20260914: while spectating, this HUD stops being a
	-- control and becomes a READ-ONLY mirror of the watched player's shield --
	-- timer only. No charge count (Charges is ProtectionClient's view of OUR OWN
	-- inventory, so printing it beside their timer would be a lie), no key
	-- binding, no equipment rows, never pressable, and no touch control rect:
	-- `mirroring` is what tells applyLayout the last two. It stands down the
	-- moment the subject changes or goes invalid.
	if subject then
		local watchedRemaining = secondsRemaining(subject)
		local showing = watchedRemaining > 0
		gui.Enabled = showing
		panel.Visible, caption.Visible = false, false
		for index = 2, #ROWS do ROWS[index].Button.Visible = false end
		local button = ROWS[1].Button
		button.Visible = showing
		button.Active, button.AutoButtonColor = false, false
		button.Text = "SAFE\n" .. string.format("%.1fs", watchedRemaining)
		button.TextTransparency = 0
		return
	end
	local states = computeStates()
	gui.Enabled = states.Available
	for index, row in ipairs(ROWS) do
		local state = states[index]
		local button = row.Button
		state.Visible = state.Visible and row.Slotted
		button.Visible = state.Visible
		button.Active = state.Enabled
		button.AutoButtonColor = state.Enabled
		if state.Visible then
			local faded = state.Lit and 0 or DIMMED
			if touch then
				button.Text = state.Short .. "\n" .. state.ShortDetail
				button.TextTransparency = faded
			else
				button.Text = ""
				row.Name.Text = state.Title
				row.Name.TextColor3 = state.Live and UIStyle.Color.Live or UIStyle.Color.Title
				row.Name.TextTransparency = faded
				row.Readout.Text = state.Detail
				row.Readout.TextColor3 = state.Lit and UIStyle.Color.Body or UIStyle.Color.Muted
				row.Readout.TextTransparency = faded
			end
		end
	end
	if touch then panel.Visible = false else placePointer(states) end
	caption.Visible = states.Available and captionUntil > os.clock()
	local remaining = secondsRemaining()
	if states.Available and remaining > 0 and player:GetAttribute("PlayerProtectionSource") == "Reentry" then
		local area = UIDevice.Layout().ModalArea
		reentryNotice.Size = UDim2.fromOffset(math.max(120, math.min(360, area.Width - 16)), 50)
		reentryNotice.Position = UIDevice.LocalPosition(gui, (area.Left + area.Right) * .5, area.Bottom - 32)
		reentryNotice.Text = string.format("You are invisible to monsters\n%d seconds", math.ceil(remaining))
		reentryNotice.Visible = true
	end
end

function applyLayout()
	if destroyed then return end
	local layout = UIDevice.Layout()
	touch = layout.IsTouch
	-- The read-only mirror is a label, not a control, so it never takes a touch
	-- control slot -- it uses the plain placement on every device.
	local control = touch and not mirroring
	if control ~= registered then
		registered = control
		for _, row in ipairs(ROWS) do
			if registered then UIDevice.RegisterControlRect(row.Key, row.Button)
			else UIDevice.UnregisterControlRect(row.Button) end
		end
	end
	for index, row in ipairs(ROWS) do
		local button = row.Button
		local binding = UIDevice.Binding(row.Keyboard, row.Gamepad)
		row.Name.Visible = not control
		row.Readout.Visible = not control
		row.Chip.Visible = not control and binding ~= ""
		if row.Chip.Visible then
			row.Chip.Text = "[" .. binding .. "]"
			row.Chip.Size = UDim2.fromOffset(keyChipWidth(row.Chip.Text), KEY_HEIGHT)
		end
		local reserved = row.Chip.Visible and (row.Chip.Size.X.Offset + COLUMN_GAP) or 0
		row.Readout.Size = UDim2.new(1,
			-(ROW_PAD + NAME_WIDTH + COLUMN_GAP + ROW_PAD + reserved), 0, TEXT_HEIGHT)
		if control then
			local slot = layout.ControlPlan.Slots[row.Key]
			if index == 1 then
				assert(slot and slot.Width >= 44 and slot.Height >= 44,
					"ProtectionUse needs a 44px control slot")
			end
			-- A build whose UIDevice predates the equipment slots keeps its
			-- shield and simply does not offer the other two, rather than
			-- erroring out of the one control that cancels an L1 capture.
			row.Slotted = slot ~= nil and slot.Width >= 44 and slot.Height >= 44
			if row.Slotted then
				button.AnchorPoint = Vector2.new(1, 1)
				button.Size = UDim2.fromOffset(slot.Width, slot.Height)
				button.Position = UDim2.new(1, -slot.Right, 1, -slot.Bottom)
				button.TextSize = 10
			end
			button.BackgroundColor3 = TOUCH_CHIP
			button.BackgroundTransparency = 0
		else
			row.Slotted = true
			button.AnchorPoint = Vector2.new(0, 1)
			button.TextSize = 12
			button.BackgroundColor3 = UIStyle.Color.Control
			button.BackgroundTransparency = UIStyle.Transparency.Row
		end
	end
	if control then placeTouchCaption() end
	refresh()
end

-- One request in flight per action. The windows are deliberately longer than a
-- double-tap and shorter than a player waiting: they exist so a held finger or
-- a stuck key cannot spray the remote, not as a gameplay cooldown.
local RATE_WINDOW = {[2] = 1.2, [3] = 1.5, [4] = 1}

local function press(index)
	if destroyed then return end
	local states = computeStates()
	local state = states[index]
	if not state.Visible or not state.Enabled then return end
	if index == 1 then
		-- The shield's own owner decides between a retry and a fresh request.
		local clientState = Client.GetState()
		if clientState.Pending then Client.Retry() else Client.Request("UseProtection") end
	else
		if GuiService.SelectedObject ~= nil then return end
		local now = os.clock()
		if now - (lastFired[index] or -math.huge) < RATE_WINDOW[index] then return end
		lastFired[index] = now
		if index == 2 then
			actionRemote:FireServer("UseSpeedPotion")
		elseif index == 4 and detectorRemote then
			detectorRemote:FireServer("scan")
		elseif index == 3 and markerRemote then
			markerRemote:FireServer("place")
		end
	end
	refresh()
end

local function bindHumanoid()
	if destroyed then return end
	if healthConnection then healthConnection:Disconnect(); healthConnection = nil end
	boundHumanoid = boundCharacter and boundCharacter:FindFirstChildOfClass("Humanoid")
	if boundHumanoid then healthConnection = boundHumanoid.HealthChanged:Connect(refresh) end
	refresh()
end

local function bindCharacter(character)
	if player.Character ~= character or destroyed then return end
	disconnectAll(characterConnections)
	boundCharacter = character
	connect(character.ChildAdded, bindHumanoid, characterConnections)
	connect(character.ChildRemoved, bindHumanoid, characterConnections)
	bindHumanoid()
end

connect(player.CharacterAdded, bindCharacter)
connect(player.CharacterRemoving, function(character)
	if boundCharacter ~= character then return end
	boundCharacter = nil
	disconnectAll(characterConnections)
	bindHumanoid()
end)
connect(UIS.InputBegan, function(input, processed)
	local key = input.KeyCode
	local index = KEY_ROWS[key]
	if index == nil then return end
	if held[key] then return end
	held[key] = true
	if processed or input.UserInputState ~= Enum.UserInputState.Begin then return end
	press(index)
end)
connect(UIS.InputEnded, function(input) held[input.KeyCode] = nil end)
connect(UIS.WindowFocusReleased, function() table.clear(held) end)
for index, row in ipairs(ROWS) do
	connect(row.Button.Activated, function(input)
		if input and (input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1) then press(index) end
	end)
end
connect(Client.Changed, refresh)
connect(UIDevice.Changed, applyLayout)
connect(GuiService:GetPropertyChangedSignal("MenuIsOpen"), refresh)
connect(GuiService:GetPropertyChangedSignal("SelectedObject"), refresh)
connect(UIS.TextBoxFocused, refresh)
connect(UIS.TextBoxFocusReleased, refresh)
-- ZyntraStore's status line owns these in the LOBBY. In a round the terminal is
-- shut, so an error the player caused from this HUD would otherwise land
-- nowhere; only the error tone is surfaced, and only while the HUD is live.
connect(profileChanged.OnClientEvent, function(_, message, tone)
	if tone == "error" and contextAvailable() then showCaption(message) end
end)
for _, name in ipairs({"InRound", "Escaped", "Spectating", "SpectateTargetUserId",
	"Level2_ExitTransition", "RoundEntryControlsReady",
	"DispatchBriefingOpen", "ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen",
	"PlayerProtectionActive", "PlayerProtectionExpiresAt", "PlayerProtectionSource",
	"ZyntraSpeedPotions", "ZyntraRouteMarkers", "RouteMarkersActive",
	"ZyntraSpeedBoostUntil", "ZyntraSpeedPotionUsedThisRound"}) do
	connect(player:GetAttributeChangedSignal(name), refresh)
end
for _, name in ipairs({"RoundActive", "RoundLoadingState"}) do
	connect(workspace:GetAttributeChangedSignal(name), refresh)
end
-- Observe local covers and the server display clock even when no attribute
-- changes. This never requests, retries, activates or clears protection.
connect(RunService.RenderStepped, refresh)
connect(script.Destroying, function()
	destroyed = true
	disconnectAll(connections)
	disconnectAll(characterConnections)
	if healthConnection then healthConnection:Disconnect() end
	if registered then
		for _, row in ipairs(ROWS) do UIDevice.UnregisterControlRect(row.Button) end
	end
	gui:Destroy()
end)
task.spawn(function()
	local found = remotes:WaitForChild("RouteMarker", 10)
	if not found or destroyed then return end
	markerRemote = found
	connect(found.OnClientEvent, function(event, detail)
		if event ~= "refused" then return end
		showCaption(REFUSALS[detail] or (type(detail) == "string" and detail ~= ""
			and string.upper(string.sub(detail, 1, 28))) or "NOT NOW")
	end)
	refresh()
end)
task.spawn(function()
 local found=remotes:WaitForChild("ZyntraDetector",15)
 if not found or destroyed then return end
 detectorRemote=found
 connect(found.OnClientEvent,function(event,detail)
  if event=="refused" then showCaption(detail) end
 end)
 refresh()
end)
if player.Character then bindCharacter(player.Character) end
applyLayout()
