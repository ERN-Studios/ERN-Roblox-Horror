-- Zyntra Dev L4  (StarterPlayerScripts, DEV_MENU_L4_20261006)
--
-- The developer menu ("ZYNTRA DEV") in the L4 Zyntra Flat style, built from
-- the Framewisp import ReplicatedStorage.ZyntraShopUI.DevMenu_L4 (Figma
-- 7FXycGKH6OT6Lme6FV3VBc, export frame 113:1252) through the shop's ShopBinder
-- (tag/class tolerance, text scaling, button states).
--
-- NO NEW POWER. Every row sends exactly what the legacy DEV tab sends:
--   toggles and actions  PlayerScripts.DevCheatCommand:Fire(<command>)  (one arg;
--                        DevCheats toggles and fires Remotes.DevControl)
--   GIVE RESEARCH TOKENS Remotes.ZyntraGrantTokens:InvokeServer(userId, amount)
-- Everything else only READS attributes the game already publishes. The client
-- gates are cosmetic: GameManager / ZyntraMonetization re-check DevAccess on
-- every remote. Non-developers return on line one: no gui, no bridge.
--
-- NAME CONTRACT (base names; Framewisp tags such as _button are tolerated):
--   DevWindow (required), Dim, WindowShadow, Close (required), Eyebrow, WhereText, Status
--   Dev_<command>                 one row per legacy command (required, see ROWS)
--     Toggle_<command> > Track > Knob, ToggleText   (switch; ToggleText = ON/OFF)
--     Action_<command> > ActionText                 (RESPAWN / WHEN DEAD / LEVEL 2 ONLY ...)
--     State_<command>               readback line (ENTITIES RUNNING, LAST: RESPAWNED ...)
--     KeyChip, Desc                 key chip (hidden on touch), description
--   Tab_<Group> > Label, ActiveBar, ActiveCount > CountText; Page_<Group>
--   Dev_grantTokens: Player_1 (chip template, one per player), AmountMinus,
--     AmountBox > AmountValue (a TextBox is laid over it), AmountPlus,
--     Action_grantTokens > GiveLabel, Amount; State_grantTokens (result line)
--   Dev_masterTuning: Action_masterTuning (F4 hint, disabled), State_masterTuning
-- A missing required name fails the window for this session, warned by name;
-- nothing else opens in its place (the old DEV tab is deleted, go-live
-- 2026-10-07).
--
-- OPENING. ZyntraStore asks PlayerScripts.ZyntraDevUIOpen:Invoke(requested)
-- (nil = toggle, true/false) from every developer route: J / DevPhoneCommand
-- in the lobby, and its dev toggle (J, the ZYNTRA // DEV chip) in a round.
-- In the lobby the L4 shop's DEV header button (touch and gamepad have no J)
-- closes the shop, then asks Invoke(true) the same way. The lobby rail stays up
-- over this menu (owner, 2026-10-07): any rail button but MUSIC closes it
-- first with Invoke(false) (ZyntraStore switchFrom), which clears DevPhoneOpen
-- before it returns, then opens its own window.
-- True = handled; false = refused (a guard below, or the menu cannot bind).
-- DevAccess (line one) is the only gate; there is no rollout switch.
-- The Figma export (113:1252) must reach Framewisp with all six Page_ frames
-- VISIBLE: the shop's import dropped its hidden pages, and a missing row fails
-- the menu (warned once, by name).
--
-- MODAL CONTRACT. Publishes DevPhoneOpen (in UIDevice's screen-owning set:
-- RoundUI frees the cursor, NoiseReporter/Flashlight stand down) and re-asserts
-- it if another script clears it while the menu is up. Closes like the old dev
-- phone: Escape, ButtonB, Close, death, Escaped, InRound change, RoundActive
-- off in a round, QueueModalOpen, DispatchBriefingOpen in a round. In the
-- lobby the window starts right of the rail: ui.fit reads ZyntraStore's
-- client-local ZyntraRailRight (nil in a round, so the round fit is unchanged).
--
-- REGISTERS. State lives in `ui`; the main chunk keeps ~25 locals.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
if not DevAccess.IsAllowed(player) then return end

local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local timelineOwner = DevAccess.IsLevel3TimelineOwner(player)

-- The legacy DEV tab's rows (ZyntraStore `controls`), keyed by command. On/Off
-- are the State_ lines the Figma frames draw; Result is the server's readback.
-- Action captions are the legacy words, but WAITING (legacy WAITING 5s /
-- RESPAWNING... would overflow the 280 px button). Only the ready caption is
-- drawn at the design's 40 px; WHEN DEAD / LEVEL n ONLY / WAITING at 30, one
-- line, like the Figma Action Disabled and Pending variants (build, renderRow).
local ROWS = {
	{Id = "freeRespawn", Action = true, DeadOnly = true, Ready = "RESPAWN",
		Disabled = "WHEN DEAD", Busy = "DevRespawnBusy", Result = "DevRespawnStatus"},
	{Id = "pauseEntity", Key = "P", Attr = "DevCheatEntityPaused", On = "ENTITIES PAUSED", Off = "ENTITIES RUNNING"},
	{Id = "level2PumpPair", Action = true, Level = 2, Ready = "PULL", Busy = "DevLevel2PumpBusy",
		Result = "DevLevel2PumpStatus"},
	{Id = "level5Fall", Action = true, Key = "O", Level = 5, Live = "Level5VoidRound", Ready = "DROP"},
	{Id = "level3PreBlackout", Action = true, Key = "K", Level = 3, Ready = "SKIP", OwnerOnly = true,
		Result = "DevLevel3TimelineStatus"},
	{Id = "noclip", Key = "V", Attr = "DevCheatNoclip", On = "FLYING \u{B7} 90 STUDS/S",
		KeyCopy = "Fly through geometry with WASD, Space and Left Ctrl.",
		TouchCopy = "Fly through geometry using the movement stick."},
	{Id = "immunePush", Key = "I", Attr = "DevCheatPushImmune"},
	{Id = "unlimited", Key = "U", Attr = "DevCheatUnlimited", On = "NO BATTERY OR STAMINA DRAIN"},
	{Id = "thirdPerson", Key = "C", Attr = "DevCheatThirdPerson", On = "THIRD PERSON IN ROUNDS", Off = "FIRST PERSON IN ROUNDS"},
	{Id = "esp", Key = "B", Attr = "DevCheatEsp", On = "HIGHLIGHTS ON"},
	{Id = "playerEsp", Attr = "DevCheatPlayerEsp"},
	{Id = "fastQueue", Key = "B", Attr = "DevCheatFastQueue", LobbyOnly = true, On = "3-SECOND COUNTDOWN",
		Off = "NORMAL COUNTDOWN"},
}
local GROUPS = {"Round", "Player", "Vision", "Lobby", "Economy", "Tuning"}
local CLOSE_ACTION = "ZyntraDevL4Close"
local KNOB_INSET = 6 / 72 -- the Figma switch: a 28 px knob 6 px inside a 72 px track

-- Readback results that count as success (rail teal); anything else is coral.
local OK = {
	DevRespawnStatus = {RESPAWNED = true},
	DevLevel2PumpStatus = {FIRST_PULLED_SECOND_IN_5_SECONDS = true, TWO_PUMPS_PULLED = true},
	DevLevel3TimelineStatus = {SKIPPED_TO_2_25 = true},
	DevTuningStatus = {OK = true},
}
-- Footer messages on a serial change, word for word from the legacy DEV tab.
-- The fallback is a format string fed the status.
local READBACKS = {
	DevRespawnSerial = {"DevRespawnStatus", {
		RESPAWNED = "Developer respawn complete. No Robux, tokens or credits used.",
		MUST_BE_DEAD = "Free respawn is available after death in an active level.",
		BUSY = "A respawn is already in progress.",
		PLACEMENT_FAILED = "No safe arrival space. Try again when space is free.",
		DEVELOPER_ONLY = "Free respawn is for whitelisted developers only.",
	}, "Free respawn is unavailable for this round."},
	DevLevel2PumpSerial = {"DevLevel2PumpStatus", {
		FIRST_PULLED_SECOND_IN_5_SECONDS = "First lever pulled. Second lever in 5 seconds.",
		TWO_PUMPS_PULLED = "Both levers pulled, 5 seconds apart.",
		SECOND_ALREADY_RUNNING = "Second lever was already pulled. No extra pump was started.",
		NEED_TWO_AVAILABLE_PUMPS = "Two unstarted pumps are needed. No lever was pulled.",
		SEQUENCE_BUSY = "A two-pump sequence is already running.",
		LEVEL_2_ONLY = "Join an active Level 2 round first.",
		MUST_BE_ALIVE = "Your character must be alive to pull the pumps.",
		FIRST_PUMP_UNAVAILABLE = "The first lever is unavailable. Sequence stopped.",
		SECOND_PUMP_UNAVAILABLE = "The second lever is unavailable. No extra pump was started.",
		UNAVAILABLE = "Level 2 pump controls are unavailable. Try again.",
	}, "Pump sequence: %s"},
	DevLevel3TimelineSerial = timelineOwner and {"DevLevel3TimelineStatus", {
		SKIPPED_TO_2_25 = "Skipped to 2:25 \u{2014} blackout warning started.",
		ALREADY_AT_OR_PAST_WARNING = "Already at or past the 2:25 warning.",
		OBJECTIVE_COMPLETE = "Level 3 is already complete.",
	}, "Level 3 skip unavailable: %s"} or nil,
}

local ui = {open = false, built = false, bindFailed = false, rows = {}, tabs = {}, pages = {},
	session = {}, handlers = {}, grant = {}}

-- The bridge exists from the first frame and says no until the menu can bind,
-- so ZyntraStore never waits on this script.
do
	local old = playerScripts:FindFirstChild("ZyntraDevUIOpen")
	if old then old:Destroy() end
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "ZyntraDevUIOpen"
	bridge.OnInvoke = function(requested)
		if not ui.toggle then return false end
		local ok, used = pcall(ui.toggle, requested)
		if ok then return used == true end
		warn("[ZyntraDevUI] L4 dev menu failed: " .. tostring(used))
		ui.bindFailed = true
		if ui.setOpen then pcall(ui.setOpen, false) end
		return false
	end
	bridge.Parent = playerScripts
end

local folder = ReplicatedStorage:WaitForChild("ZyntraShopUI", 30)
local binderModule = folder and folder:WaitForChild("ShopBinder", 10)
if not binderModule then
	warn("[ZyntraDevUI] ReplicatedStorage.ZyntraShopUI.ShopBinder is not installed: the dev menu cannot open")
	return
end
local Binder = require(binderModule)
local P = Binder.Palette

-- -- helpers ---------------------------------------------------------------

function ui.status(text, tone)
	if not ui.statusLabel then return end
	local hint = text == nil or text == ""
	ui.statusLabel.Text = hint and ui.statusHint or text
	ui.statusLabel.TextColor3 = not hint and (tone == "error" and P.Coral or tone == "success" and P.RailTeal) or P.Sage
end

-- The legacy sendDevCommand, verbatim in effect.
function ui.send(command)
	local event = playerScripts:FindFirstChild("DevCheatCommand")
	if event and event:IsA("BindableEvent") then
		event:Fire(command)
	else
		ui.status("Developer controls are still loading. Try again.", "error")
	end
end

local function liveRound()
	return workspace:GetAttribute("RoundActive") == true and player:GetAttribute("InRound") == true
end

-- The legacy actionAvailable: the same predicate decides the caption, the
-- enabled state and whether a press sends anything.
function ui.available(row)
	if row.DeadOnly then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return liveRound()
			and player:GetAttribute("Escaped") ~= true
			and player:GetAttribute("Level2_ExitTransition") ~= true
			and character ~= nil and character.Parent ~= nil
			and humanoid ~= nil and humanoid.Health <= 0
			and player:GetAttribute(row.Busy) ~= true
	end
	if row.Live then
		return player:GetAttribute(row.Live) == true and player:GetAttribute("InRound") == true
	end
	return workspace:GetAttribute("SelectedLevel") == row.Level and liveRound()
		and (not row.Busy or player:GetAttribute(row.Busy) ~= true)
end

-- GameManager drops fastQueue on a reserved round server (it publishes that as
-- workspace.ReservedRoundServer), but DevCheats has already published
-- DevCheatFastQueue ON by then. There the switch is OFF and inert, whatever
-- that attribute says, so it never shows a countdown the server refused.
function ui.refused(row)
	return row.LobbyOnly == true and workspace:GetAttribute("ReservedRoundServer") == true
end

-- Every press goes through here; the Studio probe runs the very same fn.
function ui.onPress(hit, fn)
	ui.handlers[hit] = fn
	hit.Activated:Connect(function()
		if hit.Active then fn() end
	end)
end

local function isText(node)
	return node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")
end

-- The label inside a control. Framewisp imports a _button as a TextButton with
-- empty Text holding a TextLabel, so the first text DESCENDANT wins over the
-- face itself. Called before Binder lays its empty Hit over a Frame face.
local function innerText(face)
	for _, node in ipairs(face:GetDescendants()) do
		if isText(node) then return node end
	end
	return isText(face) and face or nil
end

-- Binder.control with the inner label as its caption (nil when there is none).
local function rowControl(scope, base)
	local face = Binder.find(scope, base)
	local caption = face and innerText(face)
	if not caption then return nil end
	local control = Binder.control(scope, base)
	control.Price = caption
	return control
end

-- A key chip sits in a title row that Binder.flowRow lays out after the title
-- Roblox draws; flowRow owns the chip's Visible, so the wish travels as
-- BinderFlowOff. The plain Visible write stands where a chip has no title row.
function ui.showChip(chip, shown)
	chip.Visible = shown
	chip:SetAttribute("BinderFlowOff", not shown)
	Binder.flowRow(chip.Parent)
end

-- Selected/idle look of a Player_* chip, from the Figma Chip variants.
local function chipStyle(node, selected)
	node.BackgroundColor3 = selected and P.OwnedFill or P.TileHi
	local stroke = node:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = selected and P.RailTeal or P.Line end
	local label = innerText(node)
	if label then label.TextColor3 = selected and P.RailTeal or P.Cream end
end

-- -- rows ------------------------------------------------------------------

function ui.renderRow(row)
	local text, style, line, tone
	if row.Action then
		local available = ui.available(row)
		local busy = row.Busy and player:GetAttribute(row.Busy) == true
		text = busy and "WAITING" or available and row.Ready
			or row.Disabled or ("LEVEL %d ONLY"):format(row.Level)
		style = busy and "busy" or available and "token" or "off"
		local result = row.Result and player:GetAttribute(row.Result)
		if row.DeadOnly and liveRound() and not available and not busy then
			line = "ALIVE \u{B7} UNLOCKS ON DEATH"
		elseif type(result) == "string" and result ~= "" then
			line, tone = "LAST: " .. result:gsub("_", " "), OK[row.Result][result] and P.RailTeal or P.Coral
		end
		UIDevice.SetEnabled(row.Control.Hit, available)
	else
		local refused = ui.refused(row)
		local on = not refused and player:GetAttribute(row.Attr) == true
		text, style = on and "ON" or "OFF", on and "owned" or "off"
		line, tone = refused and "LOBBY SERVERS ONLY" or on and (row.On or "ON") or (row.Off or "OFF"),
			on and P.RailTeal or nil
		if row.Track then
			row.Track.BackgroundColor3 = on and P.RailTeal or P.Ink
			local stroke = row.Track:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Enabled = not on end
		end
		if row.Knob then
			row.Knob.BackgroundColor3 = on and P.Ink or P.Sage
			row.Knob.AnchorPoint = Vector2.new(on and 1 or 0, row.Knob.AnchorPoint.Y)
			row.Knob.Position = UDim2.new(on and 1 - KNOB_INSET or KNOB_INSET, 0,
				row.Knob.Position.Y.Scale, row.Knob.Position.Y.Offset)
		end
		UIDevice.SetEnabled(row.Control.Hit, not refused)
	end
	row.Control.Price.Text = text
	if row.CaptionScale then row.CaptionScale.Scale = style == "token" and 1 or 30 / 40 end
	Binder.style(row.Control, style == "busy" and "off" or style)
	if style == "busy" then
		-- The Figma Action/Pending variant: grey face, icon-teal ring and text.
		local stroke = row.Control.Face:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = P.IconTeal end
		row.Control.Price.TextColor3 = P.IconTeal
	end
	if row.State then
		row.State.Text = line or row.StateText
		row.State.TextColor3 = tone or P.Sage
	end
	if row.Chip then ui.showChip(row.Chip, row.ChipShown and not UIDevice.SuppressesKeyboardGlyphs()) end
	if row.Desc and row.TouchCopy then
		row.Desc.Text = UIDevice.SuppressesKeyboardGlyphs() and row.TouchCopy or row.KeyCopy
	end
end

-- -- GIVE RESEARCH TOKENS (the legacy form: same remote, same limits) ---------
do
	local g = ui.grant
	local selected, pending, cooldownUntil = nil, false, 0
	local LADDER = {1, 5, 10, 20, 50, 100, 250, 500, 1000, 2500, 5000, 10000}
	g.Chips = {}

	local function result(text, tone)
		if g.Result then
			g.Result.Text = text
			g.Result.TextColor3 = tone == "error" and P.Coral or tone == "success" and P.RailTeal or P.Sage
		end
		ui.status(text, tone)
	end

	local function ready()
		-- The legacy desktop-only gate: grants never go out from a phone or tablet.
		return not UIDevice.IsTouch() and not pending and os.clock() >= cooldownUntil
	end

	local function amount()
		local value = tonumber(g.Amount.Text)
		if not value or value ~= value or value < 1 or value > 10000 or value % 1 ~= 0 then return nil end
		return value
	end

	-- A TextBox the player can type in, laid over AmountValue (Framewisp
	-- imports text as TextLabels).
	local function textBox(node)
		if node:IsA("TextBox") then return node end
		local box = node:FindFirstChild("AmountInput")
		if box then return box end
		local label = innerText(node)
		box = Instance.new("TextBox")
		box.Name = "AmountInput"
		box.BackgroundTransparency = 1
		box.BorderSizePixel = 0
		box.Size = UDim2.fromScale(1, 1)
		box.ClearTextOnFocus = false
		box.PlaceholderText = "1-10,000"
		box.Text = label and label.Text or "20"
		box.ZIndex = node.ZIndex + 1
		if label then
			box.FontFace, box.TextColor3, box.TextSize = label.FontFace, label.TextColor3, label.TextSize
			box.PlaceholderColor3 = P.Sage
			box:SetAttribute("FigmaFontSize", label:GetAttribute("FigmaFontSize"))
			label.TextTransparency = 1
		end
		box.Parent = node
		return box
	end

	function g.bind(row, need)
		g.Row = row
		local first = need(row, "Player_1")
		local amountBox = need(row, "AmountBox")
		g.Give = rowControl(row, "Action_grantTokens")
		if not g.Give then need(nil, "Dev_grantTokens/Action_grantTokens > GiveLabel") end
		if not (first and amountBox and g.Give) then return end
		g.GiveAmount = Binder.text(Binder.find(g.Give.Face, "Amount"))
		g.Sep = Binder.text(Binder.find(g.Give.Face, "Sep"))
		g.Result = Binder.text(Binder.find(row, "State_grantTokens"))
		g.ResultText = g.Result and g.Result.Text
		g.Amount = textBox(amountBox)
		g.Amount:GetPropertyChangedSignal("Text"):Connect(function() g.render() end)
		-- Player_1 is the chip template. The design's row held one chip per player and did not
		-- scroll, so only three players could ever be chosen. It is now a dropdown (owner,
		-- 2026-10-08): one selector chip opens PlayerList, a scrolling list with a chip per player.
		g.ChipParent = first.Parent
		g.ChipTemplate = first:Clone()
		for _, node in ipairs(g.ChipParent:GetChildren()) do
			if string.match(Binder.base(node.Name), "^Player_%d+$") then node:Destroy() end
		end
		g.buildPicker()
		for _, pair in ipairs({{"AmountMinus", -1}, {"AmountPlus", 1}}) do
			local node = Binder.find(row, pair[1])
			if node then
				g[pair[1]] = Binder.button(node)
				ui.onPress(g[pair[1]], function() g.step(pair[2]) end)
				Binder.press(g[pair[1]], node)
			end
		end
		ui.onPress(g.Give.Hit, g.give)
		Binder.press(g.Give.Hit, g.Give.Face, g.Give.Shadow)
		g.rebuild()
	end

	local function nameOf(who) return "@" .. who.Name .. (who == player and " (you)" or "") end
	local LIST_ROWS, LIST_GAP = 5, 4 -- rows the list shows before it scrolls; the gap around each row

	-- The selector fills the design's chip row; the list floats above the window (a sibling of
	-- Root in this Sibling gui) so neither the row nor the page clips it.
	function g.buildPicker()
		local node = g.ChipTemplate:Clone()
		node.Name = "PlayerSelect"
		node.LayoutOrder = 1
		node.Size = UDim2.fromScale(1, 1)
		node.Parent = g.ChipParent
		g.Select = {Node = node, Label = innerText(node), Hit = Binder.button(node), Bars = {}}
		-- A drawn chevron: Montserrat has no arrow glyph (\u{25BE} drew as a box in Play).
		local chevron = Instance.new("Frame")
		chevron.Name = "Chevron"
		chevron.BackgroundTransparency = 1
		chevron.AnchorPoint = Vector2.new(1, 0.5)
		chevron.Position = UDim2.new(1, -18, 0.5, 0)
		chevron.Size = UDim2.fromOffset(14, 8)
		chevron.ZIndex = node.ZIndex + 3
		chevron.Parent = node
		for index = 1, 2 do
			local bar = Instance.new("Frame")
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(index == 1 and 0.3 or 0.7, 0.5)
			bar.Size = UDim2.fromOffset(9, 2)
			bar.ZIndex = chevron.ZIndex
			bar.Parent = chevron
			g.Select.Bars[index] = bar
		end
		ui.onPress(g.Select.Hit, function() g.setList(not g.ListOpen) end)
		local list = Instance.new("ScrollingFrame")
		list.Name = "PlayerList"
		list.Visible = false
		list.ZIndex = 10
		list.BackgroundColor3 = P.Ink
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.ScrollBarImageColor3 = P.Line
		list.CanvasSize = UDim2.new()
		local stroke = Instance.new("UIStroke")
		stroke.Color = P.Line
		stroke.Parent = list
		list.Parent = ui.gui
		g.List = list
	end

	-- Below the selector, or above it where the screen ends first; one chip per row.
	function g.placeList()
		local select, list = g.Select and g.Select.Node, g.List
		if not (select and list) then return end
		local at, size = select.AbsolutePosition, select.AbsoluteSize
		local rowHeight = math.max(24, size.Y)
		for index, chip in ipairs(g.Chips) do
			chip.Node.AnchorPoint = Vector2.zero
			chip.Node.Size = UDim2.new(1, -(LIST_GAP * 2 + list.ScrollBarThickness), 0, rowHeight)
			chip.Node.Position = UDim2.fromOffset(LIST_GAP, LIST_GAP + (index - 1) * (rowHeight + LIST_GAP))
		end
		local full = LIST_GAP + #g.Chips * (rowHeight + LIST_GAP)
		local height = math.min(full, LIST_GAP + LIST_ROWS * (rowHeight + LIST_GAP))
		list.CanvasSize = UDim2.fromOffset(0, full)
		list.Size = UDim2.fromOffset(size.X, height)
		local display = UIDevice.Layout().Display
		local below = at.Y + size.Y + LIST_GAP
		local y = (not display or below + height <= display.Bottom) and below or at.Y - LIST_GAP - height
		list.Position = UIDevice.LocalPosition(ui.gui, at.X, y)
	end

	function g.setList(open)
		open = open == true and ready() and #g.Chips > 0
		g.ListOpen = open
		if g.List then g.List.Visible = open end
		if open then
			g.placeList()
			local first = g.Chips[1]
			if first and UIDevice.LastInput() == "Gamepad" then GuiService.SelectedObject = first.Hit end
		elseif g.List and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(g.List) then
			GuiService.SelectedObject = g.Select and g.Select.Hit or nil
		end
		g.render()
	end

	function g.rebuild(leaving)
		if not g.ChipTemplate or not g.List then return end
		for _, chip in ipairs(g.Chips) do
			ui.handlers[chip.Hit] = nil
			chip.Node:Destroy()
		end
		table.clear(g.Chips)
		local everyone = {}
		for _, who in ipairs(Players:GetPlayers()) do
			if who ~= leaving then table.insert(everyone, who) end
		end
		table.sort(everyone, function(a, b) return a.Name:lower() < b.Name:lower() end)
		for index, who in ipairs(everyone) do
			local node = g.ChipTemplate:Clone()
			node.Name = "Player_" .. index
			node.LayoutOrder = index
			node.Parent = g.List
			local label = innerText(node)
			if label then label.Text = nameOf(who) end
			local chip = {Node = node, Player = who, Hit = Binder.button(node)}
			ui.onPress(chip.Hit, function()
				if not ready() then return end
				selected = who
				result("Ready to give tokens to @" .. who.Name .. ".")
				g.setList(false)
			end)
			table.insert(g.Chips, chip)
		end
		if g.ListOpen then
			if #g.Chips == 0 then return g.setList(false) end
			g.placeList()
		end
		g.render()
	end

	function g.step(direction)
		if not ready() then return end
		local current = tonumber(g.Amount.Text) or 20
		local value = current
		for index = direction > 0 and 1 or #LADDER, direction > 0 and #LADDER or 1, direction do
			if (direction > 0 and LADDER[index] > current) or (direction < 0 and LADDER[index] < current) then
				value = LADDER[index]
				break
			end
		end
		g.Amount.Text = tostring(value)
	end

	function g.render()
		if not g.Row or not g.Give then return end
		local desktop = not UIDevice.IsTouch()
		local canEdit = ready()
		local remaining = math.max(0, math.ceil(cooldownUntil - os.clock()))
		g.Row:SetAttribute("Pending", pending)
		g.Row:SetAttribute("SelectedUserId", selected and selected.UserId or nil)
		if g.ListOpen and not canEdit then
			g.ListOpen = false
			if g.List then g.List.Visible = false end
		end
		for _, chip in ipairs(g.Chips) do
			chipStyle(chip.Node, chip.Player == selected)
			UIDevice.SetEnabled(chip.Hit, canEdit)
		end
		if g.Select then
			-- The ring lights while the list is open; the label names the choice.
			chipStyle(g.Select.Node, g.ListOpen == true)
			if g.Select.Label then g.Select.Label.Text = selected and nameOf(selected) or "CHOOSE A PLAYER" end
			-- V while closed, ^ while open, in the label's colour.
			local open = g.ListOpen == true
			for index, bar in ipairs(g.Select.Bars) do
				bar.Rotation = ((index == 1) ~= open) and 45 or -45
				bar.BackgroundColor3 = g.Select.Label and g.Select.Label.TextColor3 or P.Cream
			end
			UIDevice.SetEnabled(g.Select.Hit, canEdit)
		end
		if g.AmountMinus then UIDevice.SetEnabled(g.AmountMinus, canEdit) end
		if g.AmountPlus then UIDevice.SetEnabled(g.AmountPlus, canEdit) end
		g.Amount.TextEditable = canEdit
		local value = amount()
		local canGive = canEdit and selected ~= nil and value ~= nil
		-- Authored-length words only, so nothing outgrows the 440 px face:
		-- GIVE <glyph> 250 / WAIT ... / WAIT 3s (legacy GIVING... / WAIT 3s).
		local waiting = pending or remaining > 0
		g.Give.Price.Text = waiting and "WAIT" or "GIVE"
		if g.GiveAmount then
			g.GiveAmount.Text = pending and "..." or remaining > 0 and (remaining .. "s") or value and tostring(value) or "--"
		end
		if g.Give.Glyph then g.Give.Glyph.Visible = not waiting end
		if g.Sep then g.Sep.Visible = not waiting end
		Binder.style(g.Give, canGive and "token" or "off")
		if g.GiveAmount then g.GiveAmount.TextColor3 = g.Give.Price.TextColor3 end
		UIDevice.SetEnabled(g.Give.Hit, canGive)
		if not desktop and g.Result then
			g.Result.Text = "DESKTOP ONLY"
			g.Result.TextColor3 = P.Sage
		end
	end

	function g.give()
		if not ready() then return end
		if not selected or not table.find(Players:GetPlayers(), selected) then
			selected = nil
			g.render()
			return result("Choose a player who is on this server.", "error")
		end
		local value = amount()
		if not value then return result("Enter a whole number from 1 to 10,000.", "error") end
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild("ZyntraGrantTokens")
		if not remote or not remote:IsA("RemoteFunction") then
			return result("Token grants are unavailable on this server. Rejoin an updated server.", "error")
		end
		local target = selected
		pending = true
		g.render()
		result(("Giving %d tokens to @%s..."):format(value, target.Name))
		local completed = false
		task.delay(12, function()
			if not completed then
				result("Still waiting for the server. Keep this request open; do not send it again.")
			end
		end)
		local ok, response = pcall(function() return remote:InvokeServer(target.UserId, value) end)
		completed, pending, cooldownUntil = true, false, os.clock() + 3
		if ok and type(response) == "table" and type(response.Success) == "boolean"
			and type(response.Message) == "string" and response.Message ~= "" then
			result(response.Message, response.Success and "success" or "error")
		else
			result("Result unknown. Ask @" .. target.Name .. " to rejoin and check their balance before giving again.", "error")
		end
		g.render()
		for second = 1, 3 do task.delay(second, g.render) end
	end

	Players.PlayerAdded:Connect(function() g.rebuild() end)
	Players.PlayerRemoving:Connect(function(leaving)
		if leaving == selected then
			selected = nil
			if not pending then result("Selected player left. Choose another player.", "error") end
		end
		g.rebuild(leaving)
	end)
end

-- -- render, nav, open/close -----------------------------------------------

function ui.render()
	if not ui.built or ui.bindFailed then return end
	-- The round's level (nil in the lobby), read afresh on every render: with no
	-- level chips nothing else could correct a filter that went stale while open.
	local inRound = player:GetAttribute("InRound") == true
	local level = workspace:GetAttribute("SelectedLevel")
	if player:GetAttribute("Level5VoidRound") == true then level = 5 end
	ui.filterLevel(inRound and level or nil)
	local counts = {}
	for _, row in ipairs(ui.rows) do
		ui.renderRow(row)
		if row.Attr and row.Group and not ui.refused(row) and player:GetAttribute(row.Attr) == true then
			counts[row.Group] = (counts[row.Group] or 0) + 1
		end
	end
	for group, tab in pairs(ui.tabs) do
		if tab.Count then tab.Count.Visible = (counts[group] or 0) > 0 end
		if tab.CountText then tab.CountText.Text = tostring(counts[group] or 0) end
	end
	ui.grant.render()
	local glyphs = not UIDevice.SuppressesKeyboardGlyphs()
	if ui.eyebrow then
		ui.eyebrow.Text = glyphs and "WHITELISTED DEVELOPER CONTROLS \u{B7} KEY J" or "WHITELISTED DEVELOPER CONTROLS"
	end
	if ui.where then
		ui.where.Text = not inRound
			and (workspace:GetAttribute("ReservedRoundServer") == true and "ROUND SERVER" or "LOBBY SERVER")
			or type(level) == "number" and ("IN ROUND \u{B7} LEVEL %d"):format(level) or "IN ROUND"
	end
	local tuning = ui.tuning
	if tuning then
		-- F4 (MasterTuningClient) is the only opener today: the button explains it.
		tuning.Control.Price.Text = glyphs and "PRESS F4" or "KEYBOARD"
		Binder.style(tuning.Control, "off")
		UIDevice.SetEnabled(tuning.Control.Hit, false)
		if tuning.Chip then ui.showChip(tuning.Chip, tuning.ChipShown and glyphs) end
		local status = player:GetAttribute("DevTuningStatus")
		if tuning.State and type(status) == "string" and status ~= "" then
			tuning.State.Text = "LAST WRITE: " .. status
			tuning.State.TextColor3 = status == "OK" and P.RailTeal or P.Coral
		end
	end
end

function ui.selectGroup(name)
	if not ui.pages[name] then return end
	if ui.grant.ListOpen then ui.grant.setList(false) end -- the player list belongs to its page
	ui.group = name
	for group, page in pairs(ui.pages) do page.Visible = group == name end
	for group, tab in pairs(ui.tabs) do
		local active = group == name
		tab.Node.BackgroundTransparency = active and 0 or 1
		if active then tab.Node.BackgroundColor3 = P.Tile end
		if tab.Stroke then tab.Stroke.Color = P.RailTeal; tab.Stroke.Enabled = active end
		if tab.Bar then tab.Bar.Visible = active end
		if tab.Label then tab.Label.TextColor3 = active and P.Cream or P.Sage end
	end
end

-- ROUND in a round: rows tied to another level step aside and the round's
-- level leads the list (the in-round Figma frame). nil (the lobby) shows every
-- row in its authored order.
function ui.filterLevel(level)
	if type(level) ~= "number" then level = nil end
	for _, row in ipairs(ui.rows) do
		if row.Level then
			row.Node.Visible = level == nil or row.Level == level
			row.Node.LayoutOrder = row.Level == level and -1 or row.Order
		end
	end
end

function ui.setOpen(open)
	open = open == true
	if ui.open == open or not ui.root then return end
	ui.open = open
	ui.root.Visible = open
	player:SetAttribute("DevPhoneOpen", open or nil)
	UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
	if open then
		ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState)
			if not ui.open or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
			if inputState == Enum.UserInputState.Begin then ui.setOpen(false) end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		table.insert(ui.session, UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == Enum.KeyCode.Escape then ui.setOpen(false) end
		end))
		-- A round lands on ROUND filtered to its level (legacy selectTab("Dev"));
		-- the lobby on the last group, every row shown (ui.render filters).
		ui.selectGroup(player:GetAttribute("InRound") == true and "Round" or ui.group or "Player")
		ui.status("")
		ui.render()
		if UIDevice.LastInput() == "Gamepad" then GuiService.SelectedObject = ui.closeHit end
	else
		if ui.grant.ListOpen then ui.grant.setList(false) end
		ContextActionService:UnbindAction(CLOSE_ACTION)
		for _, connection in ipairs(ui.session) do connection:Disconnect() end
		table.clear(ui.session)
		local selectedObject = GuiService.SelectedObject
		if selectedObject and selectedObject:IsDescendantOf(ui.root) then GuiService.SelectedObject = nil end
	end
end

-- PC (pointer layout, not a TV) at HALF size, centred, like the shop (owner
-- 2026-10-07: "Pc ui skal bare skaleres ned med 50%"); never under 400 px tall.
local PC_SCALE, PC_MIN_HEIGHT = 0.5, 400
function ui.fit()
	if not ui.holder then return end
	if ui.grant.ListOpen then task.defer(ui.grant.placeList) end -- follows the selector once the window moved
	local layout = UIDevice.Layout()
	local viewport = layout.ModalViewport
	local left, top, width, height = viewport.Left, viewport.Top, viewport.Width, viewport.Height
	if not layout.IsTouch and not GuiService:IsTenFootInterface() then
		-- The floor is on the WINDOW: in a viewport narrower than the window's aspect
		-- (5:4, 1024x768) the window is width-bound and shorter than the holder.
		local fitH = math.min(height, width * ui.design.Y / ui.design.X)
		local scale = math.min(1, math.max(PC_SCALE, PC_MIN_HEIGHT / math.max(1, fitH)))
		left, top = left + width * (1 - scale) / 2, top + height * (1 - scale) / 2
		width, height = width * scale, height * scale
	end
	-- The lobby rail stays tappable over this window (owner, 2026-10-07): start
	-- 8 px right of its right edge. ZyntraRailRight is nil in a round.
	local railRight = player:GetAttribute("ZyntraRailRight")
	if type(railRight) == "number" and left < railRight + 8 then
		width, left = width - (railRight + 8 - left), railRight + 8
	end
	ui.holder.Position = UIDevice.LocalPosition(ui.gui, left, top)
	ui.holder.Size = UDim2.fromOffset(width, height)
end

-- Clone, strip, bind, then mount; once per session; never yields.
function ui.build()
	if ui.built then return not ui.bindFailed end
	ui.built = true
	local template = folder:FindFirstChild("DevMenu_L4")
	local art = template and template:Clone()
	if art then
		Binder.strip(art)
		if not art:IsA("GuiObject") then art = art:FindFirstChildWhichIsA("GuiObject") end
	end
	local window = art and Binder.find(art, "DevWindow")
	if not window then
		warn("[ZyntraDevUI] L4 missing: ReplicatedStorage.ZyntraShopUI.DevMenu_L4/DevWindow: the dev menu cannot open")
		ui.bindFailed = true
		return false
	end
	if not timelineOwner then
		-- The legacy tab never builds this row for anyone but the timeline owner.
		local ownerRow = Binder.find(window, "Dev_level3PreBlackout")
		if ownerRow then ownerRow:Destroy() end
	end
	local foundPages = Binder.all(window, "Page_")
	local function groupOf(node)
		for group, page in pairs(foundPages) do
			if node:IsDescendantOf(page) then return group end
		end
		return nil
	end

	-- Bind first, mount only when everything required is there.
	local missing = {}
	local function need(scope, path)
		local node = scope and Binder.at(scope, path)
		if not node then table.insert(missing, path) end
		return node
	end
	-- Optional row parts, resolved before any Hit exists.
	local function parts(node, spec)
		local chip = Binder.find(node, "KeyChip")
		local state = Binder.text(Binder.find(node, "State_" .. spec.Id))
		local row = table.clone(spec)
		row.Node, row.Group, row.Order = node, groupOf(node), node.LayoutOrder
		row.Chip, row.ChipShown = chip, chip ~= nil and chip.Visible
		row.State, row.StateText = state, state and state.Text
		row.Desc = Binder.text(Binder.find(node, "Desc") or Binder.find(node, "Description"))
		return row
	end
	for _, spec in ipairs(ROWS) do
		if timelineOwner or not spec.OwnerOnly then
			local id = spec.Id
			local node = need(window, "Dev_" .. id)
			local base = (spec.Action and "Action_" or "Toggle_") .. id
			local row = node and parts(node, spec)
			local control = node and rowControl(node, base)
			if node and not control then table.insert(missing, ("Dev_%s/%s (with a text label)"):format(id, base)) end
			if control then
				if spec.Action then
					-- The Figma Action variants (page 113:2): Default draws its caption
					-- at 40 px, Disabled and Pending at 30 on one line (LEVEL 2 ONLY is
					-- 230 px there; at 40 it is ~300, wider than the 280 px face). A
					-- UIScale takes Binder.scaleText's 40 to that 30 (renderRow), so a
					-- resize can never undo it. The caption box is the face, centred,
					-- wide enough at 0.75 for the whole line. A merged face IS the
					-- caption and cannot be scaled without the button: it wraps.
					local caption = control.Price
					if caption ~= control.Face then
						caption.AnchorPoint, caption.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
						caption.Size, caption.TextXAlignment = UDim2.fromScale(4 / 3, 1), Enum.TextXAlignment.Center
						-- The 2026-10-07 bundle puts a UIScale (FW_Scale = 1) under every text;
						-- a second one on the same label is not a defined stack: drive that one.
						row.CaptionScale = caption:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
						row.CaptionScale.Scale = 1
						row.CaptionScale.Parent = caption
					else
						caption.TextWrapped = true
					end
				end
				row.Control = control
				row.Track = Binder.find(control.Face, "Track")
				row.Knob = Binder.find(control.Face, "Knob")
				table.insert(ui.rows, row)
				ui.onPress(control.Hit, spec.Action and function()
					if ui.available(row) then ui.send(id) end
				end or function()
					if not ui.refused(row) then ui.send(id) end
				end)
				Binder.press(control.Hit, control.Face, control.Shadow)
			end
		end
	end
	local grantRow = need(window, "Dev_grantTokens")
	if grantRow then ui.grant.bind(grantRow, need) end
	local close = need(window, "Close")
	if #missing > 0 then
		for _, path in ipairs(missing) do warn("[ZyntraDevUI] L4 missing: " .. path) end
		ui.bindFailed = true
		table.clear(ui.rows)
		return false
	end
	-- Framewisp imports a tab group's inactive panels hidden (the 2026-10-07 bundle:
	-- five of the six lists). A row is drawn whenever its page is; the row itself
	-- stays the level filter's.
	for _, node in pairs(Binder.all(window, "Dev_")) do
		local group = groupOf(node)
		if group then Binder.reveal(node.Parent, foundPages[group]) end
	end

	-- Optional chrome.
	ui.closeHit = Binder.button(close)
	ui.onPress(ui.closeHit, function() ui.setOpen(false) end)
	Binder.press(ui.closeHit, close, Binder.find(window, "CloseShadow"))
	ui.statusLabel = Binder.text(Binder.find(window, "Status"))
	ui.statusHint = ui.statusLabel and ui.statusLabel.Text or ""
	ui.eyebrow = Binder.text(Binder.find(window, "Eyebrow"))
	ui.where = Binder.text(Binder.find(window, "WhereText"))
	local tuningRow = Binder.find(window, "Dev_masterTuning")
	local tuningControl = tuningRow and rowControl(tuningRow, "Action_masterTuning")
	if tuningControl then
		ui.tuning = parts(tuningRow, {Id = "masterTuning"})
		ui.tuning.Control = tuningControl
	end
	local foundTabs = Binder.all(window, "Tab_")
	local lend = nil
	for _, tab in pairs(foundTabs) do lend = lend or tab:FindFirstChildOfClass("UIStroke") end
	for _, group in ipairs(GROUPS) do
		ui.pages[group] = foundPages[group]
		local tab = foundTabs[group]
		if tab and foundPages[group] then
			local stroke = tab:FindFirstChildOfClass("UIStroke")
			if not stroke and lend then
				-- Only the authored active tab carries the ring: lend it to the rest.
				stroke = lend:Clone()
				stroke.Parent = tab
			end
			local count = Binder.find(tab, "ActiveCount")
			ui.tabs[group] = {Node = tab, Stroke = stroke, Bar = Binder.find(tab, "ActiveBar"),
				Label = Binder.text(Binder.find(tab, "Label")), Count = count, CountText = count and Binder.text(count)}
			ui.onPress(Binder.button(tab), function() ui.selectGroup(group) end)
		end
	end

	-- Mount: full-screen root > artboard (scrim only) + ModalViewport holder >
	-- aspect-locked fit > shadow + window. Same as the L4 shop window.
	local design = Binder.designSize(window)
	ui.design = design -- ui.fit's aspect
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = ui.gui
	ui.root = root
	for _, child in ipairs(art:GetChildren()) do
		if child:IsA("UIAspectRatioConstraint") or child:IsA("UIScale") then child:Destroy() end
	end
	art.AnchorPoint, art.Position, art.Size, art.BackgroundTransparency = Vector2.new(0, 0), UDim2.new(), UDim2.fromScale(1, 1), 1
	-- Under WindowHolder (ZIndex 2) whatever the import carries (4 in the
	-- 2026-10-07 bundle): above it, the Active Dim swallowed every click (v2770).
	art.ZIndex = 1
	art.Parent = root
	-- No backdrop (owner 2026-10-07); Dim stays the Active input shield, and an
	-- import that lost the (now empty) layer still gets one. Same as the shop.
	local dim = Binder.find(art, "Dim")
	if not dim then
		dim = Instance.new("Frame")
		dim.Name, dim.BorderSizePixel, dim.Parent = "Dim", 0, art
	end
	dim.AnchorPoint, dim.Position, dim.Size = Vector2.new(0, 0), UDim2.new(), UDim2.fromScale(1, 1)
	dim.BackgroundTransparency, dim.Active = 1, true
	local holder = Instance.new("Frame")
	holder.Name = "WindowHolder"
	holder.BackgroundTransparency = 1
	holder.ZIndex = 2 -- above the artboard and its input-sinking Dim, never by tie order
	holder.Parent = root
	ui.holder = holder
	local fitFrame = Instance.new("Frame")
	fitFrame.Name = "WindowFit"
	fitFrame.BackgroundTransparency = 1
	fitFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	fitFrame.Position = UDim2.fromScale(0.5, 0.5)
	fitFrame.Size = UDim2.fromScale(1, 1)
	fitFrame.Parent = holder
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = design.X / design.Y
	ratio.Parent = fitFrame
	local shadow = Binder.find(art, "WindowShadow")
	if shadow then
		shadow.AnchorPoint, shadow.Position, shadow.Size, shadow.ZIndex = Vector2.new(0, 0), UDim2.fromScale(0, 0.012), UDim2.fromScale(1, 1), 1
		shadow.Parent = fitFrame
	end
	window.AnchorPoint, window.Position, window.Size, window.ZIndex = Vector2.new(0, 0), UDim2.new(), UDim2.fromScale(1, 1), 2
	window.Parent = fitFrame
	ui.fit()
	-- Chips after a title sit where Roblox's title ends (Binder.flowRow); first,
	-- so scaleText's line fit leaves the titles to it.
	for _, node in ipairs(window:GetDescendants()) do
		if Binder.base(node.Name) == "TitleRow" then Binder.flowRow(node) end
	end
	Binder.scaleText(window, design, template:GetAttribute("BB_TextFactor"))
	return true
end

-- The old dev phone's guards: never over the queue, a round's briefing or any
-- other screen-owning modal.
function ui.blocked()
	return player:GetAttribute("QueueModalOpen") == true
		or (player:GetAttribute("InRound") == true and player:GetAttribute("DispatchBriefingOpen") == true)
		or UIDevice.ScreenOwningModalOpen()
end

-- The bridge's answer. False means refused; nothing else opens instead.
function ui.toggle(requested)
	local want = if typeof(requested) == "boolean" then requested else not ui.open
	if not want then
		if not ui.open then return false end
		ui.setOpen(false)
		return true
	end
	if ui.open then return true end
	if ui.blocked() or not ui.build() then return false end
	ui.setOpen(true)
	return true
end

-- -- wiring ----------------------------------------------------------------

ui.gui = Instance.new("ScreenGui")
ui.gui.Name = "ZyntraDevL4"
-- Above the L4 shop (56). ZyntraStore's rail is 55, and 119 while one of its
-- windows (this one included) is open in the lobby, so it stays tappable.
ui.gui.DisplayOrder = 57
ui.gui.ResetOnSpawn = false
ui.gui.IgnoreGuiInset = false
ui.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ui.gui.Parent = playerGui

local CLOSES = {InRound = function() return true end,
	Escaped = function() return player:GetAttribute("Escaped") == true end,
	QueueModalOpen = function() return player:GetAttribute("QueueModalOpen") == true end,
	DispatchBriefingOpen = function()
		return player:GetAttribute("InRound") == true and player:GetAttribute("DispatchBriefingOpen") == true
	end}
-- Only the attributes the menu draws trigger a redraw: in a round Stamina and
-- friends change every frame, and a full redraw per frame is waste.
local RELEVANT = {InRound = true, Escaped = true, SelectedLevel = true, RoundActive = true,
	ReservedRoundServer = true, Level5VoidRound = true, Level2_ExitTransition = true,
	QueueModalOpen = true, DispatchBriefingOpen = true}
function ui.relevant(name)
	return RELEVANT[name] == true or string.sub(name, 1, 3) == "Dev"
end
player.AttributeChanged:Connect(function(name)
	local readback = READBACKS[name]
	if readback and ui.built and not ui.bindFailed then
		local status = tostring(player:GetAttribute(readback[1]) or "")
		local message = readback[2][status]
		if not message and name == "DevLevel2PumpSerial" and status:find("CANCELLED_", 1, true) == 1 then
			message = "Pump sequence cancelled because the round or character changed."
		end
		ui.status(message or readback[3]:format(status), OK[readback[1]][status] and "success" or "error")
	end
	if not ui.open then return end
	if CLOSES[name] and CLOSES[name]() then return ui.setOpen(false) end
	if name == "DevPhoneOpen" and player:GetAttribute("DevPhoneOpen") ~= true then
		-- While this menu is up the flag is ours, whoever cleared it; a close
		-- (setOpen(false), Invoke(false)) sets ui.open false first and skips this.
		task.defer(function()
			if not ui.open then return end
			player:SetAttribute("DevPhoneOpen", true)
			UIDevice.SuppressTouchMovement(true)
		end)
	end
	if ui.relevant(name) then ui.render() end
end)
workspace.AttributeChanged:Connect(function(name)
	if not ui.open then return end
	if name == "RoundActive" and workspace:GetAttribute("RoundActive") ~= true and player:GetAttribute("InRound") == true then
		return ui.setOpen(false)
	end
	if ui.relevant(name) then ui.render() end
end)
do
	local died = nil
	local function bindCharacter(character)
		if died then died:Disconnect(); died = nil end
		ui.render()
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and player.Character == character then
				if died then died:Disconnect() end
				died = humanoid.Died:Connect(function() ui.setOpen(false) end)
			end
		end)
	end
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then bindCharacter(player.Character) end
end
UIDevice.Changed:Connect(function()
	ui.fit()
	ui.render()
end)
player:GetAttributeChangedSignal("ZyntraRailRight"):Connect(ui.fit)

-- Studio-only seam for UIRegression and the install QA probe:
--   open / close / state ("id|caption|active" lines) / press:<id>
if RunService:IsStudio() then
	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionZyntraDevL4Probe"
	probe.OnInvoke = function(action)
		action = tostring(action)
		if action == "open" then return ui.toggle(true) end
		if action == "close" then return ui.toggle(false) end
		if action == "state" then
			local lines = {}
			for _, row in ipairs(ui.rows) do
				table.insert(lines, ("%s|%s|%s"):format(row.Id, row.Control.Price.Text, tostring(row.Control.Hit.Active)))
			end
			return table.concat(lines, "\n")
		end
		if action:sub(1, 6) == "press:" then
			local id = action:sub(7)
			for _, row in ipairs(ui.rows) do
				if row.Id == id and row.Control.Hit.Active then
					ui.handlers[row.Control.Hit]()
					return true
				end
			end
			return false
		end
		return ui.open
	end
	probe.Parent = ui.gui
end
