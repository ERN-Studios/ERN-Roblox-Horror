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
--
-- HUD_B1_CHIPS (owner, 2026-10-08): artifacts/hud-final-20261008/BUILD-PLAN.md
-- 08 C and B1. On PC and gamepad the drawn EQUIPMENT panel is gone: the row of
-- C chips is the Framewisp template HUD_PC/EquipmentPanel (Chip_Shield,
-- Chip_Potion, Chip_Markers, Chip_Scan) plus HUD_PC/EquipmentCaption, mounted
-- through RoundHud into this same gui. Only owned chips draw. READY, then 40 %
-- after 6 s (RoundHud.Attention, the one fade this HUD has; it is an opacity
-- ramp, not a flash); COOLDOWN numerals; ACTIVE "4.2" over "SAFE"; EMPTY at
-- 50 %; REFUSED = Coral stroke plus one of four fixed tags, never a raw server
-- string. All empty hides the row; ACTIVE and REFUSED never dim. The gui keeps
-- its name and order 1001 (above the kill cam: the shield cancels a Level 1
-- capture) and now stands down under PARTY DOWN and the results (BUILD-PLAN 1.4).
--
-- HUD_B2_TOUCH (owner, 2026-10-08): artifacts/hud-final-20261008/b2/B2-DESIGN.md
-- 5. On touch the drawn squares are gone: SHIELD and KIT are HUD_Touch cells of
-- the 4 + 4 cluster and POTION, MARKER and SCAN live in the KIT fan (see the
-- "B2 touch kit" section). While spectating, touch draws nothing (D11); PC keeps
-- the chip mirror above.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local Client = require(ReplicatedStorage:WaitForChild("ProtectionClient"))
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local RoundHud = require(ReplicatedStorage:WaitForChild("RoundHud"))
local Binder = require(ReplicatedStorage:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
local P = Binder.Palette

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

-- The refusal tag's window (BUILD-PLAN 08: "The 2 s tag window is unchanged").
local CAPTION_SECONDS = 2
-- HUD_B1_CHIPS (owner, 2026-10-08): BUILD-PLAN 1.5 / 08 -- the chip row sits
-- bottom-left, 24 px in from the safe edges, right of the flashlight widget
-- (HUD_PC/FlashlightWidget, placed by FlashlightController at the same edge)
-- with a gap of 8. The refusal tag sits 8 above the row.
local KIT_EDGE, KIT_GAP = 24, 8

local gui = Instance.new("ScreenGui")
gui.Name = "ProtectionHUD"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
-- Living players can cancel an L1 capture through this control. Real modals
-- and loading covers suppress it explicitly; JumpscareGui has order 1000.
gui.DisplayOrder = 1001
gui.Enabled = false
gui.Parent = playerGui
-- HUD_B3 (owner, 2026-10-08): the re-entry grace sentence is gone; Round HUD's
-- GRACE marker shows it (B3-DESIGN 5). The chip keeps its ACTIVE look.

local connections, characterConnections = {}, {}
local boundCharacter, boundHumanoid
local healthConnection
-- HUD_B1_CHIPS (owner, 2026-10-08): `touch` is known before the first refresh
-- (bindCharacter and the remote resolvers refresh before applyLayout runs), so
-- a touch client that starts mid-round never mounts and fades the PC row.
local touch, registered, destroyed = UIDevice.Layout().IsTouch == true, false, false
local held = {}
local mirroring = false
local captionUntil = 0
-- HUD_B1_CHIPS (owner, 2026-10-08): the refusal tag's text, the chip it belongs
-- to, the last chip pressed (a profile error answers that one) and a use count
-- (a press is a change for the row's attention, BUILD-PLAN 1.3).
local captionText, refusedChip, lastPressed, uses = "", nil, nil, 0
local kit = {Tried = false, Shown = false, Chips = {}} -- the mounted PC row
local lastFired = {}
local applyLayout, press

local function connect(signal, callback, list)
	local connection = signal:Connect(callback)
	table.insert(list or connections, connection)
	return connection
end

local function disconnectAll(list)
	for _, connection in ipairs(list) do connection:Disconnect() end
	table.clear(list)
end

-- The four items: the C chip each one is on PC and gamepad, its keys, and on
-- touch its KIT fan item (HUD_B2_TOUCH, owner, 2026-10-08: nil for the shield,
-- which is its own cell). Index 1 is the shield on every surface.
-- AUDIT_FIX_20260924: potion and marker had no pad key, so a controller
-- player could own both and use neither (the rows are not Selectable and a
-- gamepad Activated is filtered). D-PAD RIGHT is SpectateController's only
-- while spectating, which contextAvailable excludes; RT is bound nowhere.
local ROWS = {
	{Key = "ProtectionUse", Chip = "Chip_Shield", Keyboard = Enum.KeyCode.Q, Gamepad = Enum.KeyCode.DPadDown},
	{Key = "SpeedPotionUse", Chip = "Chip_Potion", Keyboard = Enum.KeyCode.T, Gamepad = Enum.KeyCode.DPadRight,
		Fan = "Fan_Potion"},
	{Key = "RouteMarkerPlace", Chip = "Chip_Markers", Keyboard = Enum.KeyCode.X, Gamepad = Enum.KeyCode.ButtonR2,
		Fan = "Fan_Marker"},
	{Key = "EntityDetectorScan", Chip = "Chip_Scan", Keyboard = Enum.KeyCode.Z, Gamepad = Enum.KeyCode.DPadLeft,
		Fan = "Fan_Scan"},
}

local KEY_ROWS = {}
for index, row in ipairs(ROWS) do
	KEY_ROWS[row.Keyboard], KEY_ROWS[row.Gamepad] = index, index
end

-- == B2 touch kit (14 A + KIT fan C; owner, 2026-10-08) ==
-- artifacts/hud-final-20261008/b2/B2-DESIGN.md 5. On touch the kit is two cells
-- of UIDevice's 4 + 4 cluster, SHIELD (ProtectionUse) and KIT (KitToggle), and
-- the KIT fan one row above KIT: POTION, MARKER and SCAN, owned items only,
-- packed toward KIT. All three are HUD_Touch templates, mounted once at load on
-- every client (PC included, hidden), so a registered root never changes. The
-- client-local player attribute KitFanOpen is the fan's only state (D8): KIT's
-- tap writes it, a fan use clears it, and drawTouch forces it false whenever the
-- fan cannot be open. Only SHIELD and KIT reserve control rects; the fan is
-- transient and never registered.
-- The cells are flat (critic C5): the root TextButton is the face and carries
-- the UIStroke, there is no Face child. SHIELD's Glyph and a fan item's Icon are
-- Frames, dimmed through their parts' BackgroundTransparency like B1's
-- IconParts, never through a text property.
local cells = {Items = {}, Open = false}

-- One mounted cell bound to its parts, its template look cached, hidden and
-- inert. A part it needs that the template lacks is one warning and no cell.
local function bind(root, path, icon, need)
	local cell = {Root = root, Stroke = root and root:FindFirstChildOfClass("UIStroke"),
		Label = Binder.text(Binder.find(root, "Label")), Icon = Binder.find(root, icon),
		Cooldown = Binder.text(Binder.find(root, "Cooldown")), Badge = Binder.find(root, "Badge"), Parts = {}}
	cell.Count = Binder.text(Binder.find(cell.Badge, "Count"))
	for _, name in ipairs(need) do
		if not cell[name] then
			warn("[ProtectionHUD] HUD_Touch/" .. path .. " is incomplete (" .. name .. "): not drawn")
			if root then root:Destroy() end
			return nil
		end
	end
	-- The template ships Selectable, AutoButtonColor and Active all true.
	if root:IsA("GuiButton") then root.AutoButtonColor, root.Selectable = false, false end
	root.Visible, root.Active = false, false
	cell.FaceColor, cell.FaceAlpha = root.BackgroundColor3, root.BackgroundTransparency
	local stroke = cell.Stroke
	cell.StrokeColor, cell.Thickness = stroke.Color, stroke.Thickness
	cell.Width = stroke:GetAttribute("FigmaStrokeW") or 2
	local ok, scaled = pcall(function() return stroke.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize end)
	cell.Scaled = stroke:GetAttribute("FW_StrokeScaled") == true or (ok and scaled == true)
	cell.LabelText, cell.LabelColor, cell.LabelAlpha = cell.Label.Text, cell.Label.TextColor3, cell.Label.TextTransparency
	local icon = cell.Icon
	if icon:IsA("TextLabel") then cell.IconText, cell.IconColor = icon.Text, icon.TextColor3 end
	for _, part in ipairs(icon:GetDescendants()) do
		if part:IsA("GuiObject") then table.insert(cell.Parts, {part, part.BackgroundTransparency}) end
	end
	table.insert(cell.Parts, {icon, icon.BackgroundTransparency})
	-- The template's samples ("12", "2") never show before a state asks for them.
	if cell.Cooldown then cell.Cooldown.Visible, cell.CooldownColor = false, cell.Cooldown.TextColor3 end
	if cell.Badge then cell.Badge.Visible = false end
	return cell
end

do
	-- Critic C3: the templates are place data, present once the game has loaded,
	-- so they are looked up, never waited for. A missing one is RoundHud's warning
	-- by path and no cell (pipeline 5.3, D14).
	if not game:IsLoaded() then game.Loaded:Wait() end
	local shield = RoundHud.Mount("HUD_Touch", "TouchCluster/Cell_Shield", gui, {Name = "ProtectionUse"})
	cells.Shield = shield and bind(shield, "TouchCluster/Cell_Shield", "Glyph", {"Stroke", "Label", "Icon", "Cooldown"})
	local toggle = RoundHud.Mount("HUD_Touch", "TouchCluster/Cell_Kit", gui, {Name = "KitToggle"})
	cells.Kit = toggle and bind(toggle, "TouchCluster/Cell_Kit", "Glyph", {"Stroke", "Label", "Icon"})
	local fan = RoundHud.Mount("HUD_Touch", "KitFan", gui, {Name = "KitFan"})
	if fan then
		fan.Visible = false
		for index, row in ipairs(ROWS) do
			if row.Fan then
				cells.Items[index] = bind(Binder.find(fan, row.Fan), "KitFan/" .. row.Fan, "Icon",
					{"Root", "Stroke", "Label", "Icon", "Badge", "Count", "Cooldown"})
				if not cells.Items[index] then
					fan:Destroy()
					fan = nil
					table.clear(cells.Items)
					break
				end
			end
		end
	end
	if fan then
		-- D2 / critic C15: the items pack toward KIT. KitFan/Items is the import's
		-- wrapper (preorder reaches it before Fan_Scan/Icon/Items, which carries a
		-- list of its own), so never a recursive class search.
		local items = Binder.find(fan, "Items")
		local list = items and items:FindFirstChildOfClass("UIListLayout")
		if list then
			list.HorizontalAlignment = Enum.HorizontalAlignment.Right
		else
			warn("[ProtectionHUD] HUD_Touch/KitFan has no Items list: the fan packs left")
		end
	end
	cells.Fan = fan
end

-- One SHIELD or fan item in one state (B2-DESIGN 2.3), always written from the
-- cached template look so any state can follow any other. No count on SHIELD
-- (D9); SCAN's label is SCAN, HIDE or SHOW (DETECTOR_BIG_SCREEN_20261008).
local function paintCell(cell, index, state, refused)
	local look = state.Look
	local kind = look.State
	local dim, active = kind == "EMPTY" or kind == "WAIT", kind == "ACTIVE"
	local root, stroke = cell.Root, cell.Stroke
	root.BackgroundColor3 = dim and P.Tile or cell.FaceColor
	root.BackgroundTransparency = dim and .5 or cell.FaceAlpha
	stroke.Color = refused and P.Coral or active and P.RailTeal or cell.StrokeColor
	-- ACTIVE is 3 px where the template draws FigmaStrokeW. A ScaledSize stroke is
	-- a fraction of the cell, so its cached base holds at 52 and at 64 px; a pixel
	-- stroke is re-derived from the cell's size (52 = the design cell) on every
	-- frame, so scaleText's own rewrite on a resize cannot undo it (critic C8).
	local gain = active and 3 / cell.Width or 1
	stroke.Thickness = cell.Scaled and cell.Thickness * gain or cell.Width * root.AbsoluteSize.X / 52 * gain
	cell.Icon.Visible = kind ~= "COOLDOWN" and not active
	for _, part in ipairs(cell.Parts) do
		part[1].BackgroundTransparency = dim and .5 + part[2] * .5 or part[2]
	end
	local label = cell.Label
	label.Text = index == 1 and active and "SAFE" or index == 4 and state.Short or cell.LabelText
	label.TextColor3 = index == 1 and active and P.RailTeal or cell.LabelColor
	label.TextTransparency = dim and .5 or cell.LabelAlpha
	local cooldown = cell.Cooldown
	cooldown.Visible = kind == "COOLDOWN" or active
	if kind == "COOLDOWN" then
		cooldown.Text, cooldown.TextColor3 = tostring(math.ceil(look.Seconds)), cell.CooldownColor
	elseif active then
		cooldown.Text, cooldown.TextColor3 = string.format("%.1f", look.Seconds), P.RailTeal
	end
	if cell.Badge then
		local count = look.Count
		cell.Badge.Visible = kind == "READY" and type(count) == "number" and count > 0
		if cell.Badge.Visible then cell.Count.Text = count > 9 and "9+" or tostring(count) end
	end
end

-- The touch kit for one frame. `states` nil (PC, gamepad, or the spectate
-- mirror, D11) stands every touch node down. KIT is drawn only while a fan item
-- is (D7); the fan only while KitFanOpen and KIT could be tapped. An attribute
-- left true when the fan cannot be open (a modal, a cover, death, spectating,
-- PARTY DOWN, the round's end, the last item going, a flip to PC) is cleared
-- here, on change only.
local function drawTouch(states)
	local refusing = captionUntil > os.clock()
	local fanAny = false
	for index in pairs(cells.Items) do
		fanAny = fanAny or (states ~= nil and states[index].Visible)
	end
	local available = fanAny and states.Available
	local wanted = player:GetAttribute("KitFanOpen") == true
	local open = wanted and available
	cells.Open = open
	local shield = cells.Shield
	if shield then
		local state = states and states[1]
		shield.Root.Visible = state ~= nil and state.Visible
		shield.Root.Active = state ~= nil and state.Enabled
		if shield.Root.Visible then paintCell(shield, 1, state, refusing and refusedChip == 1) end
	end
	local toggle = cells.Kit
	if toggle then
		local root = toggle.Root
		root.Visible, root.Active = available, available
		root.BackgroundColor3 = open and P.RailTeal or toggle.FaceColor
		root.BackgroundTransparency = open and 0 or toggle.FaceAlpha
		-- Critic C7: the open KIT's edge is RailTeal too (phone-level-3).
		toggle.Stroke.Color = open and P.RailTeal or toggle.StrokeColor
		toggle.Icon.Text = open and "\u{D7}" or toggle.IconText
		toggle.Icon.TextColor3 = open and P.Ink or toggle.IconColor
		toggle.Label.TextColor3 = open and P.Ink or toggle.LabelColor
	end
	if cells.Fan then
		cells.Fan.Visible = open
		for index, item in pairs(cells.Items) do
			local state = states and states[index]
			item.Root.Visible = open and state.Visible
			item.Root.Active = open and state.Enabled
			if item.Root.Visible then paintCell(item, index, state, refusing and refusedChip == index) end
		end
	end
	if wanted and not open then player:SetAttribute("KitFanOpen", false) end
end

-- Critic C9: at 844x390 ModalArea's bottom centre (the refusal tag) lies on the
-- open fan, so while it is open the tag stands 8 above it.
local function clearOfFan(layout, bottom)
	return cells.Open and layout.KitFan and math.min(bottom, layout.KitFan.Top - 8) or bottom
end

-- B2-DESIGN 2.1: a slot is an inset from the safe gui's bottom-right corner, and
-- the cell takes its size on every pass (D6); it is never re-mounted.
local function seat(node, slot)
	if not (node and slot) then return end
	node.AnchorPoint = Vector2.new(1, 1)
	node.Position = UDim2.new(1, -slot.Right, 1, -slot.Bottom)
	node.Size = UDim2.fromOffset(slot.Width, slot.Height)
end

-- SHIELD and KIT, on the root, never a child; the fan items never.
local function registerTouch(on)
	for key, cell in pairs({ProtectionUse = cells.Shield, KitToggle = cells.Kit}) do
		if on then UIDevice.RegisterControlRect(key, cell.Root) else UIDevice.UnregisterControlRect(cell.Root) end
	end
end

-- A tap, or the Studio ForceTouchUI mouse; never a keyboard or pad Activated.
local function tapped(input)
	return input ~= nil and (input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1)
end
-- == end B2 touch kit ==

-- RouteMarkerService's whole vocabulary. HUD_B1_CHIPS (owner, 2026-10-08):
-- BUILD-PLAN 08 -- the tag is one of these four, and a raw server string (a
-- reason this table does not know, a detector refusal, a profile error) is
-- NOT NOW. It is never printed.
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

-- HUD_B1_CHIPS (owner, 2026-10-08): BUILD-PLAN 1.4. The gui stays at order 1001,
-- over the kill cam, but it never draws over RoundUI's PARTY DOWN card or the
-- results: it stands down while PartyDownCardOpen is set or the round is over.
-- The spectating mirror obeys this too.
local function underRoundUI()
	return player:GetAttribute("PartyDownCardOpen") == true or workspace:GetAttribute("RoundActive") ~= true
end

local function covered()
	local roundGui = playerGui:FindFirstChild("RoundGui")
	if not roundGui or not roundGui.Enabled then return false end
	-- These are the actual RoundUI frames, including the brief interval before
	-- their corresponding replicated/modal attributes catch up.
	for _, name in ipairs({"LevelLoading", "QueueHostShade"}) do
		local frame = roundGui:FindFirstChild(name)
		if frame and frame.Visible then return true end
	end
	-- MOBILE_QA_20261008: on a landscape phone the mission brief is a sheet over the whole modal viewport (RoundUI
	-- takes it where the band above the thumbstick is under 150 px); the slots drew on top of its rows.
	if player:GetAttribute("LevelOneGuideObjectivesOpen") == true then
		local layout = UIDevice.Layout()
		if layout.IsTouch and layout.TopBand.Height < 150 then return true end
	end
	-- and Level 4's keypad or note card, which publish this on touch only: their gui draws under these slots
	if player:GetAttribute("Level4CardOpen") == true then return true end
	return false
end

local function contextAvailable()
	return not destroyed and boundCharacter ~= nil and player.Character == boundCharacter
		and boundCharacter.Parent ~= nil and boundHumanoid ~= nil
		and boundCharacter:FindFirstChildOfClass("Humanoid") == boundHumanoid
		and boundHumanoid.Health > 0 and player:GetAttribute("InRound") == true
		and player:GetAttribute("Escaped") ~= true and player:GetAttribute("Spectating") ~= true
		and player:GetAttribute("Level2_ExitTransition") ~= true
		and not underRoundUI()
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

-- Every row answers the same questions -- is it drawn, may it be pressed, what
-- does its touch square say, which C chip state is it in -- so press() and
-- refresh() cannot disagree about any of them. HUD_B1_CHIPS (owner,
-- 2026-10-08): `Look` is the chip, {State = READY | WAIT | COOLDOWN | ACTIVE |
-- EMPTY, Count = badge number?, Seconds = numeral?}. WAIT (a request in flight,
-- an inventory not loaded yet) draws dimmed like EMPTY but is not "used up".
local function computeStates()
	local available = contextAvailable()
	local states = {Available = available}

	do -- 1. ENTITY SHIELD. The shipped logic verbatim, split into the row's slots.
		local state = Client.GetState()
		local remaining = secondsRemaining()
		local pressable = canPress(state, remaining)
		local count = state.Charges > 99 and "99+" or tostring(state.Charges)
		local short, detail = "SHIELD", nil
		local look = {State = "READY", Count = state.Charges}
		if remaining > 0 then
			short = pressable and "RETRY" or "SAFE"
			detail = string.format("%.1fs", remaining)
			look = {State = "ACTIVE", Seconds = remaining}
		elseif state.Pending then
			detail = pressable and "RETRY" or "WAIT"
			look.State = pressable and "READY" or "WAIT"
		elseif not state.Available or state.ServerPending then
			detail, look.State = "WAIT", "WAIT"
		else
			detail = "x" .. count
			if state.Charges <= 0 then look.State = "EMPTY" end
		end
		states[1] = {Visible = available, Enabled = pressable,
			Lit = pressable or remaining > 0, Short = short, ShortDetail = detail, Look = look}
	end

	do -- 2. SPEED POTION. One use per round; the server owns both facts below.
		local stored = storedCount("ZyntraSpeedPotions")
		local used = player:GetAttribute("ZyntraSpeedPotionUsedThisRound") == true
		local remaining = potionRemaining()
		local shortDetail, enabled, look
		if remaining > 0 then
			shortDetail = string.format("%.1fs", remaining)
			enabled, look = false, {State = "ACTIVE", Seconds = remaining}
		elseif used then
			shortDetail, enabled, look = "USED", false, {State = "EMPTY"}
		else
			shortDetail = "x" .. stored
			enabled, look = stored > 0, {State = "READY", Count = stored}
		end
		-- Owning nothing means the row is not there at all: that is what keeps
		-- the single-shield HUD exactly as it shipped for most players.
		states[2] = {Visible = available and (stored > 0 or remaining > 0 or used),
			Enabled = available and enabled, Lit = enabled or remaining > 0,
			Short = "POTION", ShortDetail = shortDetail, Look = look}
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
			Enabled = available and enabled, Lit = enabled,
			Short = "MARKER", ShortDetail = placed .. "/" .. MAX_MARKERS,
			Look = enabled and {State = "READY", Count = stored} or {State = "EMPTY"}}
	end
 do -- Server-published snapshot; the client never determines danger.
  local now=workspace:GetServerTimeNow()
  local remaining=math.max(0,(player:GetAttribute("ZyntraDetectorReadyAt") or 0)-now)
  local live=(player:GetAttribute("ZyntraDetectorReadingUntil") or 0)>now
  local reading=live and player:GetAttribute("ZyntraDetectorReading") or nil
  local owned=player:GetAttribute("ZyntraOwnsEntityDetector")==true
  local detail=reading or (remaining>0 and (math.ceil(remaining).."s") or "READY")
  -- DETECTOR_BIG_SCREEN_20261008: while the detector is on (thirty seconds, a large device in the hand) the same
  -- control puts it away and brings it back; `ZyntraDetectorStowed` is client-local and read by ZyntraDetectorClient.
  -- HUD_B1_CHIPS (owner, 2026-10-08): ReadyAt is the reading's end plus the cooldown, so the chip counts down
  -- through both as COOLDOWN; the reading itself is RoundHud's detector card above this chip.
  states[4]={Visible=available and owned and detectorRemote~=nil,
   Enabled=available and owned and (remaining<=0 or live), Lit=live or remaining<=0,Live=live,
   Short=live and (player:GetAttribute("ZyntraDetectorStowed")==true and "SHOW" or "HIDE") or "SCAN",
   ShortDetail=detail,Look=remaining>0 and {State="COOLDOWN",Seconds=remaining} or {State="READY"}}
 end
	return states
end

-- One tag for the things a chip cannot say by itself: the server refusing a
-- marker or a scan, or a profile push arriving with an error tone mid-round.
-- `index` is the refused chip, which gets the Coral stroke.
local function showCaption(detail, index)
	captionText = REFUSALS[detail] or "NOT NOW"
	refusedChip = index
	captionUntil = os.clock() + CAPTION_SECONDS
end

-- HUD_B1_CHIPS (owner, 2026-10-08) -- the C chip row (PC and gamepad), mounted
-- once, on the first frame the HUD is live, from HUD_PC. A missing template is
-- RoundHud's one warning and no row; the touch squares and every key still work.
local function mountKit()
	kit.Tried = true
	kit.Caption = RoundHud.Mount("HUD_PC", "EquipmentCaption", gui)
	kit.Label = kit.Caption and Binder.text(Binder.find(kit.Caption, "Label"))
	if kit.Caption then kit.Caption.Visible = false end
	local torch = RoundHud.Template("HUD_PC", "FlashlightWidget")
	-- Rounded as RoundHud.Mount rounds: the Scale chain gives 231.999 for the 232 px widget.
	kit.TorchWidth = torch and math.round(Binder.designSize(torch).X) or 0
	local root, attention = RoundHud.Mount("HUD_PC", "EquipmentPanel", gui,
		{Attention = {Hold = 6, Rest = .4}})
	if not root then return end
	for index, row in ipairs(ROWS) do
		local node = Binder.find(root, row.Chip)
		local face = node and Binder.find(node, "Face")
		local chip = node and {Node = node, Face = face, Icon = Binder.find(node, "Icon"),
			Badge = Binder.find(node, "Badge"), Count = Binder.text(Binder.find(node, "Count")),
			Cooldown = Binder.text(Binder.find(node, "Cooldown")),
			ActiveTime = Binder.text(Binder.find(node, "ActiveTime")),
			ActiveTag = Binder.text(Binder.find(node, "ActiveTag")), Key = Binder.find(node, "KeyChip"),
			Stroke = face and face:FindFirstChildOfClass("UIStroke"), IconParts = {}}
		for _, name in ipairs({"Face", "Icon", "Badge", "Count", "Cooldown", "ActiveTime", "ActiveTag", "Key", "Stroke"}) do
			if not (chip and chip[name]) then
				warn("[ProtectionHUD] HUD_PC/EquipmentPanel/" .. row.Chip .. " is incomplete (" .. name .. "): no chip row")
				root:Destroy()
				return
			end
		end
		chip.FaceColor, chip.FaceAlpha = face.BackgroundColor3, face.BackgroundTransparency
		chip.StrokeColor, chip.Thickness = chip.Stroke.Color, chip.Stroke.Thickness
		chip.StrokeWidth = chip.Stroke:GetAttribute("FigmaStrokeW") or 2
		for _, part in ipairs(chip.Icon:GetDescendants()) do
			if part:IsA("GuiObject") then table.insert(chip.IconParts, {part, part.BackgroundTransparency}) end
		end
		-- A chip is clicked like the old row; never a gamepad selection target.
		node.Selectable = false
		if node:IsA("GuiButton") then
			node.AutoButtonColor = false
			connect(node.Activated, function(input)
				if input and (input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseButton1) then press(index) end
			end)
		end
		kit.Chips[index] = chip
	end
	kit.Root, kit.Attention = root, attention
end

-- One chip in one state (BUILD-PLAN 08 C), always written from the template's
-- own values so any state can follow any other. nil hides the chip; the row's
-- UIListLayout closes the gap.
local function paintChip(index, chip, look, refused)
	chip.Node.Visible = look ~= nil
	if not look then return end
	local state = look.State
	local dim = state == "EMPTY" or state == "WAIT"
	chip.Face.BackgroundColor3 = dim and P.Tile or chip.FaceColor
	chip.Face.BackgroundTransparency = dim and .5 or state == "COOLDOWN" and 0 or chip.FaceAlpha
	chip.Stroke.Color = refused and P.Coral or state == "ACTIVE" and P.RailTeal or chip.StrokeColor
	-- ACTIVE is a 3 px stroke where the template draws 2 (its Thickness may be a fraction of the face).
	chip.Stroke.Thickness = state == "ACTIVE" and chip.Thickness * 3 / chip.StrokeWidth or chip.Thickness
	chip.Icon.Visible = state ~= "COOLDOWN" and state ~= "ACTIVE"
	for _, part in ipairs(chip.IconParts) do
		part[1].BackgroundTransparency = dim and .5 + part[2] * .5 or part[2]
	end
	chip.Cooldown.Visible = state == "COOLDOWN"
	if state == "COOLDOWN" then chip.Cooldown.Text = tostring(math.ceil(look.Seconds)) end
	chip.ActiveTime.Visible = state == "ACTIVE"
	if state == "ACTIVE" then chip.ActiveTime.Text = string.format("%.1f", look.Seconds) end
	-- SAFE is the shield's word; a running potion shows only its seconds.
	chip.ActiveTag.Visible = state == "ACTIVE" and index == 1
	local count = look.Count
	chip.Badge.Visible = (state == "READY" or state == "WAIT") and type(count) == "number" and count > 0
	if chip.Badge.Visible then chip.Count.Text = count > 9 and "9+" or tostring(count) end
	-- ACTIVE draws over the keycap's place, so the keycap goes; RoundHud.Keycap
	-- owns the chip's Visible, so it is re-bound (with no keys) only on a flip.
	local keyed = state ~= "ACTIVE"
	if chip.Keyed ~= keyed then
		chip.Keyed = keyed
		RoundHud.Keycap(chip.Key, keyed and ROWS[index].Keyboard or nil, keyed and ROWS[index].Gamepad or nil)
	end
end

-- The row's state, and the C visibility rule over it: on use or change 100 %
-- for 6 s, then 40 %; ACTIVE and a refusal never dim; all empty rests hidden.
-- `states` nil (touch, or the HUD not live) hides it at once.
local function drawKit(states)
	if not kit.Root then return end
	local refusing = captionUntil > os.clock()
	local shown, urgent, key = false, refusing, {}
	for index, chip in ipairs(kit.Chips) do
		local state = states and states[index]
		local look = state and state.Visible and state.Look or nil
		paintChip(index, chip, look, refusing and refusedChip == index)
		if look then
			shown = shown or look.State ~= "EMPTY"
			urgent = urgent or look.State == "ACTIVE"
			table.insert(key, index .. look.State .. (look.Count or ""))
		end
	end
	if #key > 0 then
		kit.Shown = true
		-- HUD_B1_CHIPS (owner, 2026-10-08): the 08 C EMPTY tile is "ON CHANGE 100 % for 6 s", then "IDLE
		-- hidden": the last charge going is shown, and only the rest is hidden (rest 0 = Visible false).
		kit.Attention:Show(table.concat(key, " ") .. " #" .. uses, urgent, not shown and 0 or nil)
	elseif kit.Shown then
		-- Only on the flip: the next Show is then a change (a new round wakes it).
		kit.Shown = false
		kit.Attention:Hide()
	end
end

-- Bottom-left, right of the flashlight; the tag 8 above the row. On touch the
-- tag keeps the old caption's place, UIDevice's ModalArea (clear of the
-- thumbstick, the jump button and the control cluster).
local function placeKit()
	local layout = UIDevice.Layout()
	local safe = layout.Safe
	local left = safe.Left + KIT_EDGE + (kit.TorchWidth > 0 and kit.TorchWidth + KIT_GAP or 0)
	local top = safe.Bottom - KIT_EDGE
	if kit.Root then
		kit.Root.AnchorPoint = Vector2.new(0, 1)
		kit.Root.Position = UIDevice.LocalPosition(gui, left, top)
		top -= kit.Root.Size.Y.Offset
	end
	if kit.Caption then
		local area = layout.ModalArea
		kit.Caption.AnchorPoint = touch and Vector2.new(.5, 1) or Vector2.new(0, 1)
		-- HUD_B2_TOUCH (owner, 2026-10-08): on touch, clear of the open KIT fan (critic C9).
		kit.Caption.Position = touch and UIDevice.LocalPosition(gui, (area.Left + area.Right) * .5,
			clearOfFan(layout, area.Bottom))
			or UIDevice.LocalPosition(gui, left, top - KIT_GAP)
		if kit.Label then kit.Label.Text = captionText end
	end
end

local function refresh()
	if destroyed then return end
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
	-- HUD_B1_CHIPS (owner, 2026-10-08): on PC the mirror is the shield chip in
	-- its ACTIVE look ("4.2" over "SAFE", no badge, no keycap). It does not draw
	-- under PARTY DOWN or the results. HUD_B2_TOUCH (owner, 2026-10-08): touch
	-- draws nothing while spectating (D11), the SHIELD mirror included.
	if subject then
		local watchedRemaining = secondsRemaining(subject)
		local showing = watchedRemaining > 0 and not underRoundUI()
		gui.Enabled = showing
		captionUntil = 0
		if kit.Caption then kit.Caption.Visible = false end
		drawTouch(nil)
		if showing and not touch and not kit.Tried then mountKit() end
		drawKit(showing and not touch and {{Visible = true, Look = {State = "ACTIVE", Seconds = watchedRemaining}}} or nil)
		if kit.Tried then placeKit() end
		return
	end
	local states = computeStates()
	gui.Enabled = states.Available
	-- HUD_B2_TOUCH (owner, 2026-10-08): the cells and the fan are the touch
	-- controls; on PC and gamepad the chips are, and the touch nodes stand down.
	drawTouch(touch and states or nil)
	if states.Available and not kit.Tried then mountKit() end
	drawKit(not touch and states.Available and states or nil)
	if kit.Caption then kit.Caption.Visible = states.Available and captionUntil > os.clock() end
	if kit.Tried then placeKit() end
end

function applyLayout()
	if destroyed then return end
	local layout = UIDevice.Layout()
	touch = layout.IsTouch
	-- The read-only mirror is not a control, so it never takes a touch control
	-- slot (and on touch it draws nothing, D11).
	local control = touch and not mirroring
	if control ~= registered then
		registered = control
		registerTouch(registered)
	end
	if control then
		-- HUD_B2_TOUCH (owner, 2026-10-08): SHIELD, KIT and the fan from
		-- UIDevice's plan, re-seated and resized on every pass (D6).
		local plan = layout.ControlPlan
		local slot = plan.Slots.ProtectionUse
		assert(slot and slot.Width >= 44 and slot.Height >= 44,
			"ProtectionUse needs a 44px control slot")
		seat(cells.Shield and cells.Shield.Root, slot)
		seat(cells.Kit and cells.Kit.Root, plan.Slots.KitToggle)
		seat(cells.Fan, plan.Fan)
	end
	refresh()
end

-- One request in flight per action. The windows are deliberately longer than a
-- double-tap and shorter than a player waiting: they exist so a held finger or
-- a stuck key cannot spray the remote, not as a gameplay cooldown.
local RATE_WINDOW = {[2] = 1.2, [3] = 1.5, [4] = 1}

function press(index)
	if destroyed then return end
	local states = computeStates()
	local state = states[index]
	if not state.Visible then return end
	if not state.Enabled then
		-- HUD_B1_CHIPS (owner, 2026-10-08): B1 QA "use a marker with none left and NO MARKERS LEFT shows". A
		-- drawn marker chip that cannot press is EMPTY (all placed, none stored), so the server never hears
		-- it; the tag is said here. Nothing is fired.
		if index == 3 and GuiService.SelectedObject == nil then
			showCaption("NoMarkers", 3)
			refresh()
		end
		return
	end
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
			if state.Live then
				player:SetAttribute("ZyntraDetectorStowed", player:GetAttribute("ZyntraDetectorStowed") ~= true)
			else
				detectorRemote:FireServer("scan")
			end
		elseif index == 3 and markerRemote then
			markerRemote:FireServer("place")
		end
	end
	-- HUD_B1_CHIPS (owner, 2026-10-08): a use wakes the row, and a profile
	-- error that answers it strokes this chip.
	lastPressed, uses = index, uses + 1
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
-- HUD_B2_TOUCH (owner, 2026-10-08): SHIELD presses like Q; KIT opens and closes
-- the fan; a fan item is used and closes the fan, a refused use too.
if cells.Shield then
	connect(cells.Shield.Root.Activated, function(input) if tapped(input) then press(1) end end)
end
if cells.Kit then
	connect(cells.Kit.Root.Activated, function(input)
		if not (tapped(input) and cells.Kit.Root.Active) then return end
		player:SetAttribute("KitFanOpen", not cells.Open)
		refresh()
	end)
end
for index, item in pairs(cells.Items) do
	connect(item.Root.Activated, function(input)
		if not tapped(input) then return end
		press(index)
		player:SetAttribute("KitFanOpen", false)
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
	if tone == "error" and contextAvailable() then showCaption(message, lastPressed) end
end)
for _, name in ipairs({"InRound", "Escaped", "Spectating", "SpectateTargetUserId",
	"Level2_ExitTransition", "RoundEntryControlsReady",
	"DispatchBriefingOpen", "LevelOneGuideObjectivesOpen", "Level4CardOpen", "ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen",
	"PartyDownCardOpen",
	"PlayerProtectionActive", "PlayerProtectionExpiresAt", "PlayerProtectionSource",
	"ZyntraSpeedPotions", "ZyntraRouteMarkers", "RouteMarkersActive",
	"ZyntraSpeedBoostUntil", "ZyntraSpeedPotionUsedThisRound", "KitFanOpen"}) do
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
	if registered then registerTouch(false) end
	-- HUD_B2_TOUCH (owner, 2026-10-08): the fan's state does not outlive its owner.
	if player:GetAttribute("KitFanOpen") == true then player:SetAttribute("KitFanOpen", false) end
	gui:Destroy()
end)
task.spawn(function()
	local found = remotes:WaitForChild("RouteMarker", 10)
	if not found or destroyed then return end
	markerRemote = found
	connect(found.OnClientEvent, function(event, detail)
		if event ~= "refused" then return end
		showCaption(detail, 3)
	end)
	refresh()
end)
task.spawn(function()
 local found=remotes:WaitForChild("ZyntraDetector",15)
 if not found or destroyed then return end
 detectorRemote=found
 connect(found.OnClientEvent,function(event,detail)
  if event=="refused" then showCaption(detail, 4) end
 end)
 refresh()
end)
if player.Character then bindCharacter(player.Character) end
applyLayout()
