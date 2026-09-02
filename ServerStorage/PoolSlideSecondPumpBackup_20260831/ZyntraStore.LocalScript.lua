-- ZyntraStore
-- Lobby shop, unlimited +5% upgrades, product prompts and HSV equipment color pickers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))

-- Captions whose text depends on the touch form factor (they drop key names
-- on a phone or tablet). Each registers itself so a form-factor change can
-- rebuild it instead of leaving whatever it was constructed with.
local deviceCaptionRefreshers = {}
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local devAllowed = DevAccess.IsAllowed(player)
local level3TimelineOwner = DevAccess.IsLevel3TimelineOwner(player)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local getProfileRemote = remotes:WaitForChild("ZyntraGetProfile")
local actionRemote = remotes:WaitForChild("ZyntraAction")
local profileChangedRemote = remotes:WaitForChild("ZyntraProfileChanged")

local profile
local currentTab = "Upgrades"
local productButtons = {}
local displayedProductPrices = {}
local reentryDead = false

local COLORS = {
	bg = Color3.fromRGB(7, 11, 13),
	panel = Color3.fromRGB(14, 21, 24),
	card = Color3.fromRGB(20, 29, 33),
	card2 = Color3.fromRGB(25, 36, 40),
	line = Color3.fromRGB(65, 92, 98),
	text = Color3.fromRGB(232, 240, 238),
	muted = Color3.fromRGB(144, 164, 165),
	accent = Color3.fromRGB(68, 221, 196),
	accent2 = Color3.fromRGB(255, 203, 79),
	error = Color3.fromRGB(244, 95, 82),
}

local gui = Instance.new("ScreenGui")
gui.Name = "ZyntraStore"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 55
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent, radius)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius or 8)
	object.Parent = parent
	return object
end

local function outline(parent, color, transparency, thickness)
	local object = Instance.new("UIStroke")
	object.Color = color or COLORS.line
	object.Transparency = transparency or 0
	object.Thickness = thickness or 1
	object.Parent = parent
	return object
end

local function label(parent, text, size, position, textSize, color, font)
	local object = Instance.new("TextLabel")
	object.BackgroundTransparency = 1
	object.Size = size
	object.Position = position or UDim2.new()
	object.Font = font or Enum.Font.Gotham
	object.Text = text or ""
	object.TextColor3 = color or COLORS.text
	object.TextSize = textSize or 16
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextYAlignment = Enum.TextYAlignment.Center
	object.Parent = parent
	return object
end

local function button(parent, text, size, position)
	local object = Instance.new("TextButton")
	object.AutoButtonColor = false
	object.BackgroundColor3 = COLORS.card2
	object.Size = size
	object.Position = position or UDim2.new()
	object.Font = Enum.Font.GothamBold
	object.Text = text
	object.TextColor3 = COLORS.text
	object.TextSize = 14
	object.Parent = parent
	corner(object, 7)
	outline(object, COLORS.line, 0.2, 1)
	object.MouseEnter:Connect(function()
		if object.Active then object.BackgroundColor3 = Color3.fromRGB(32, 50, 53) end
	end)
	object.MouseLeave:Connect(function()
		object.BackgroundColor3 = COLORS.card2
	end)
	return object
end

local openButton = button(gui, "ZYNTRA // EQUIPMENT", UDim2.fromOffset(220, 42), UDim2.new(1, -238, 0, 20))
openButton.Name = "ZyntraOpenButton"
openButton.BackgroundColor3 = COLORS.bg
openButton.TextColor3 = COLORS.accent
local openButtonOutline = outline(openButton, COLORS.accent, 0.22, 1.5)

-- C5_ZYNTRA_OPEN_BUTTON_20260829 -- WHAT SHIPPED BROKEN.
-- This lobby entry point was 36px tall on a phone (30 for the whitelisted dev
-- variant, 42 on a tablet) and right-aligned to the SAME edge as RoundUI's
-- queue-host modal. Measured on a Galaxy A06 (705x338, inset 0,58) it occupied
-- (345,8)-(529,44) while QueueHostPanel.CloseQueue occupied (479,14)-(523,58):
-- a 44x30 overlap. A TextButton left Active keeps taking taps through a
-- transparent background, so this button was also eating the modal's Close.
--
-- Both halves are fixed VISUALLY rather than by input priority, which is what
-- the owner asked for:
--   1. no touch state of this control is ever shorter than TOUCH_MIN_TAP_HEIGHT;
--   2. the control is not drawn at all while the queue host modal is up. RoundUI
--      publishes that as player:GetAttribute("QueueModalOpen"); a missing or
--      non-true value means "no modal", so this degrades to the old behaviour if
--      the attribute is never written.
local TOUCH_MIN_TAP_HEIGHT = 44
local QUEUE_MODAL_ATTRIBUTE = "QueueModalOpen"

-- C4A_ZYNTRA_OPENER_VS_BRIEFING_20260829 -- WHAT SHIPPED BROKEN.
-- The dispatch briefing panel and this opener were drawn in the SAME rectangle
-- and neither knew about the other. RoundUI pins CommandSubtitles to UIDevice's
-- TopBand on touch; on a Galaxy A06 (705x338, GUI inset 0,58) that band is
-- (12,66)-(529,141), its MUTE/STOP readouts occupy (171,68)-(517,112), and this
-- button occupies (345,66)-(529,110) -- entirely inside the briefing. The panel
-- draws above it (LevelOneGuideGui DisplayOrder 110 against ZyntraStore's 55)
-- but is not itself Active, so every tap that missed MUTE or STOP fell through
-- a visibly opaque briefing onto an invisible ZYNTRA // EQUIPMENT button.
--
-- Same remedy as the queue modal above, same shape: RoundUI publishes the
-- panel's OWN visibility as this attribute and the opener is not drawn while it
-- is true. A missing or non-true value means "no briefing", so this degrades to
-- the old behaviour if the attribute is never written.
local BRIEFING_ATTRIBUTE = "DispatchBriefingOpen"

local function queueModalOpen()
	return player:GetAttribute(QUEUE_MODAL_ATTRIBUTE) == true
end

local function briefingOpen()
	return player:GetAttribute(BRIEFING_ATTRIBUTE) == true
end

local function modalBlocksStore()
	return queueModalOpen() or briefingOpen()
end

-- C_TERMINAL_RESPONSIVE_20260830 -- WHAT SHIPPED BROKEN.
-- This terminal was a FIXED 840x610 composition of fixed-offset children, and
-- the only thing that ever adapted was a UIScale clamped to >= 0.78. Worse, the
-- rectangle it measured itself against was SafeBottom - SafeTop, and on touch
-- UIDevice's SafeBottom is TopBand.Bottom -- the HUD strip that has to dodge
-- the movement controls, about 117 logical pixels on a 956x440 iPhone 16 Pro
-- Max. So the whole terminal was asked to fit inside a band shorter than its
-- own 70px header: `content` resolved to a NEGATIVE height, the tab bar and the
-- status line landed on top of the header, and every page collapsed into one
-- horizontal row.
--
-- Both halves are fixed at the source rather than by another scale clamp:
--   1. LAYOUT CONTRACT. A modal is measured against UIDevice's ModalViewport --
--      the whole true safe area -- because a modal OWNS the screen and the
--      movement cluster stands down underneath it. HUD panels keep TopBand.
--   2. REAL RESPONSIVENESS. Every structural rectangle below is computed in
--      applyTerminalLayout() from that viewport: the header gives up its
--      subtitle before its height, the tab bar SCROLLS horizontally so every
--      tab stays reachable at any width, the pages stack from two columns to
--      one, and each page's own scroll takes the overflow. Nothing is scaled;
--      UIScale stays at 1 so 11px type stays 11px type.
--
-- Positions are written as OFFSETS from the modal viewport's own corner, never
-- as UDim2 scale, for a second reason: under the Studio viewport override the
-- engine still renders at the real window size, so a scale-positioned panel
-- measures against a screen that is not the one under test. Offsets computed
-- from UIDevice's reported layout measure true at every simulated size, which
-- is what lets ZyntraTerminalFitMatrix assert live rectangles at all.
local main = Instance.new("Frame")
main.Name = "Terminal"
main.AnchorPoint = Vector2.new(0, 0)
main.Position = UDim2.fromOffset(0, 0)
main.Size = UDim2.fromOffset(840, 610)
main.BackgroundColor3 = COLORS.bg
main.BorderSizePixel = 0
main.Visible = false
main.Parent = gui
corner(main, 12)
outline(main, COLORS.accent, 0.3, 1.5)
local mainScale = Instance.new("UIScale")
mainScale.Parent = main

-- Each responsive part registers a function here instead of exporting a local.
-- Two reasons, both real: applyTerminalLayout lives at the bottom of the file
-- and would otherwise need a forward local for every card, row and page it
-- touches, and this LocalScript is already close to Luau's 200-local ceiling.
local layoutHooks = {}

-- C_TERMINAL_CONTRACT_20260831 -- WHAT SHIPPED BROKEN.
-- The terminal knew everything about its own composition and published none of
-- it. Which card carries which action, and whether a page holds the set that
-- was AUTHORED rather than the set that happened to build, lived in module
-- locals -- `productCards`, `donationEntries`, the DEV `controls` table -- and
-- Studio's execute_luau runs in a SEPARATE require cache from this
-- LocalScript, so a local is invisible to a harness however carefully it is
-- named. A regression was left rediscovering the composition by walking the
-- tree, and a walk cannot see the one thing that matters: a Donate page that
-- built five of its six authored tiers looks exactly like a Donate page that
-- was authored with five.
--
-- Three publications, one per reader, every one of them written at the point
-- the card is BUILT so none of them can drift from what was built:
--   * the action button carries the CollectionService tag `contract.Tag` and
--     the page and card key it belongs to. A TAG, because it crosses the VM
--     boundary the way UIDevice.RegisterControlRect's does. Enumerating by tag
--     also finds the DISABLED actions, which a sweep over interactive
--     descendants skips by construction -- a disabled action is Visible but
--     not Active -- and those are measured too: a 44x44 floor that only holds
--     while a product is unowned is not a floor.
--   * the card frame carries the same key, so tier key -> card -> action is a
--     lookup and not a name match.
--   * the probe near the bottom of this file returns the whole index as text,
--     so a matrix can state what it expects BEFORE it goes looking for it.
local contract = {Tag = "ZyntraTerminalAction", Cards = {}, Scrolls = {}, Donations = {}}
main:SetAttribute("TerminalActionTag", contract.Tag)

function contract.scroll(page, scroll)
	-- STATED, never inherited. Every page here overflows on some device in the
	-- matrix -- that is the reason each one owns a ScrollingFrame at all -- so
	-- the single property that decides whether a player can reach that overflow
	-- is written down where the page is built.
	scroll.ScrollingEnabled = true
	scroll:SetAttribute("ZyntraPage", page)
	table.insert(contract.Scrolls, page .. "|" .. scroll.Name)
	return scroll
end

function contract.card(page, key, card, action)
	card:SetAttribute("ZyntraPage", page)
	card:SetAttribute("ZyntraCardKey", key)
	action:SetAttribute("ZyntraPage", page)
	action:SetAttribute("ZyntraCardKey", key)
	CollectionService:AddTag(action, contract.Tag)
	table.insert(contract.Cards, page .. "|" .. key .. "|" .. action.Name)
	return action
end

-- TextService:GetTextSize is the SYNCHRONOUS measurement API. The layout runs
-- from UIDevice.Changed, and yielding inside it would let a second pass start
-- inside the first, so GetTextBoundsAsync is the wrong tool here.
local TextService = game:GetService("TextService")
local function textHeightFor(text, face, font, width)
	return TextService:GetTextSize(text, face, font,
		Vector2.new(math.max(1, width), 100000)).Y
end
local function textWidthFor(text, face, font)
	return TextService:GetTextSize(text, face, font, Vector2.new(100000, 100000)).X
end
-- Every ladder below that chooses between drawing an UNWRAPPED string and
-- reflowing the row around it decides with GetTextSize, and the regression
-- that re-measures those same strings afterwards decides with
-- GetTextBoundsAsync. The two APIs do not agree to the pixel, so a choice
-- taken at exact equality can be right in the layout and wrong in the report
-- -- and the player loses either way, because the string that "just fits" is
-- the one drawn a pixel into its neighbour. Those ladders give way this many
-- pixels early. It is deliberately small: it buys the boundary, not a margin.
local TEXT_FIT_SLACK = 4

-- Forward declaration: the Studio-only regression probe below is built well
-- before the layout function, and has to be able to ask for a re-layout.
local applyTerminalLayout

local header = Instance.new("Frame")
header.Name = "TerminalHeader"
header.Size = UDim2.new(1, 0, 0, 70)
header.BackgroundColor3 = COLORS.panel
header.BorderSizePixel = 0
header.Parent = main
corner(header, 12)

local title = label(header, "ZYNTRA", UDim2.new(0, 260, 0, 30), UDim2.fromOffset(24, 10), 24, COLORS.accent, Enum.Font.GothamBlack)
title.Name = "TerminalTitle"
title.Text = "ZYNTRA // RESEARCH"
local headerSubtitle = label(header, "EQUIPMENT DEVELOPMENT TERMINAL", UDim2.new(0, 420, 0, 20), UDim2.fromOffset(25, 40), 11, COLORS.muted, Enum.Font.Code)
headerSubtitle.Name = "TerminalSubtitle"

local tokenLabel = label(header, "TOKENS  --", UDim2.fromOffset(190, 34), UDim2.new(1, -250, 0, 18), 18, COLORS.accent2, Enum.Font.GothamBold)
tokenLabel.Name = "TokenReadout"
tokenLabel.TextXAlignment = Enum.TextXAlignment.Right
local closeButton = button(header, "\u{00D7}", UDim2.fromOffset(42, 36), UDim2.new(1, -54, 0, 16))
closeButton.Name = "CloseTerminal"
closeButton.TextSize = 25

-- The tab bar SCROLLS. Five tabs at their authored 150px need 790px, which is
-- wider than most phones; a non-scrolling row simply put DEV off the end of the
-- panel where nothing could reach it. Horizontal overflow is now reachable at
-- every width, and where the tabs do fit they are widened to fill the bar so
-- the scroll never shows.
local tabBar = Instance.new("ScrollingFrame")
tabBar.Name = "TerminalTabs"
tabBar.Position = UDim2.fromOffset(20, 82)
tabBar.Size = UDim2.new(1, -40, 0, 42)
tabBar.BackgroundTransparency = 1
tabBar.BorderSizePixel = 0
tabBar.ScrollingDirection = Enum.ScrollingDirection.X
tabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
tabBar.CanvasSize = UDim2.new()
tabBar.ScrollBarThickness = 3
tabBar.ScrollBarImageColor3 = COLORS.accent
tabBar.Parent = main
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 10)
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
-- STATED, because the default is not what it looks like. Every other layout in
-- this file sets SortOrder explicitly; this one did not, and UIListLayout's
-- default is Enum.SortOrder.Name -- not LayoutOrder. It went unnoticed while
-- the tabs were all unnamed "TextButton"; the moment they were given names so a
-- regression could find them, the bar silently re-sorted alphabetically to
-- COLORS, DEV, DONATE, SHOP, UPGRADES. Measured, then fixed here.
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabBar

local content = Instance.new("Frame")
content.Name = "TerminalContent"
content.Position = UDim2.fromOffset(20, 134)
content.Size = UDim2.new(1, -40, 1, -188)
content.BackgroundTransparency = 1
content.ClipsDescendants = true
content.Parent = main

local statusLabel = label(main, "", UDim2.new(1, -40, 0, 38), UDim2.new(0, 20, 1, -47), 14, COLORS.muted, Enum.Font.GothamMedium)
statusLabel.Name = "TerminalStatus"
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.TextWrapped = true

local function showStatus(message, tone)
	statusLabel.Text = message or ""
	statusLabel.TextColor3 = tone == "error" and COLORS.error
		or tone == "success" and COLORS.accent
		or COLORS.muted
end

local pages = {}
local tabButtons = {}
local function selectTab(name)
	if not pages[name] then return end
	currentTab = name
	for pageName, otherPage in pairs(pages) do otherPage.Visible = pageName == name end
	for buttonName, otherButton in pairs(tabButtons) do
		otherButton.TextColor3 = buttonName == name and COLORS.accent or COLORS.text
	end
end

local tabNames = { "Upgrades", "Shop", "Donate", "Colors" }
if devAllowed then table.insert(tabNames, "Dev") end
for order, name in ipairs(tabNames) do
	local tab = button(tabBar, string.upper(name), UDim2.fromOffset(150, 40))
	tab.Name = name .. "Tab"
	-- EXPLICIT, and it has to be. The bar's UIListLayout sorts by LayoutOrder
	-- and breaks ties by NAME, and every tab used to be an unnamed "TextButton"
	-- so the tie-break was invisible. Naming them for the regression matrix made
	-- it visible and alphabetical: COLORS, DEV, DONATE, SHOP, UPGRADES. The
	-- authored order is Upgrades first and Dev last, so it is stated here rather
	-- than left to a tie-break.
	tab.LayoutOrder = order
	tabButtons[name] = tab
	local page = Instance.new("Frame")
	page.Name = name
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.Visible = name == currentTab
	page.Parent = content
	pages[name] = page
	tab.Activated:Connect(function()
		selectTab(name)
	end)
end
selectTab(currentTab)

-- The tab row, sized to the bar rather than to a fixed 150. Five tabs at 150
-- plus four 10px gaps is 790px, so on anything narrower than a laptop the last
-- tabs -- DEV among them -- simply hung outside the panel with no way to reach
-- them. Tabs are shrunk to share the bar down to a legible floor, and below
-- that the bar SCROLLS, which is why nothing can become unreachable however
-- narrow the screen gets.
table.insert(layoutHooks, function(fit)
	local count = #tabNames
	local gaps = (count - 1) * 10
	local share = math.floor((fit.ContentWidth - gaps) / math.max(1, count))
	local width = math.clamp(share, fit.TabMinWidth, 150)
	for _, name in ipairs(tabNames) do
		local tab = tabButtons[name]
		tab.Size = UDim2.fromOffset(width, fit.TabHeight)
		tab.TextSize = fit.Compact and 12 or 14
	end
	-- Scroll only where it is genuinely needed, so the bar has no scrollbar
	-- artefact on a screen that fits its tabs.
	local total = width * count + gaps
	tabBar.ScrollingEnabled = total > fit.ContentWidth + 1
	tabBar.ScrollBarThickness = tabBar.ScrollingEnabled and 3 or 0
end)

-- Whitelisted developer controls. The buttons only send commands to
-- DevCheats, which owns the actual state and publishes it through attributes.
-- This keeps keyboard shortcuts and the phone perfectly synchronized.
if devAllowed and pages.Dev then
	local devIntro = label(
		pages.Dev,
		"WHITELISTED DEVELOPER CONTROLS",
		UDim2.new(1, 0, 0, 34),
		UDim2.fromOffset(4, 0),
		14,
		COLORS.accent,
		Enum.Font.Code
	)
	-- Named, because it could not be addressed otherwise: `label()` leaves the
	-- default "TextLabel", and the Dev page holds several of them.
	devIntro.Name = "DevIntro"
	devIntro.TextWrapped = true
	-- C4B_DEV_CAPTION_LIVE_INPUT_20260829 -- WHAT SHIPPED BROKEN.
	-- This heading was built from a ONE-TIME UIDevice.IsTouch() read, and that was
	-- the wrong question twice over.
	--
	-- Wrong PREDICATE: IsTouch() is a FORM FACTOR test -- "phone or tablet" -- and
	-- UIDevice answers it false for any touchscreen that ALSO reports a mouse and
	-- a keyboard. A touchscreen laptop, a Surface, a tablet in a keyboard case:
	-- all of them were served "PHONE: J", a key glyph, on a device whose player
	-- reaches for the screen. SuppressesKeyboardGlyphs() is the question that
	-- actually decides whether a key glyph may be drawn at all, and it is true the
	-- moment a touchscreen exists at all. It is what UIDevice.Caption already uses
	-- for the ON/OFF rows below, so the heading and the rows now agree.
	--
	-- Wrong LIFETIME: it was resolved once, at construction, so pairing or
	-- unpairing a keyboard or a mouse afterwards left the stale caption on screen
	-- forever. It is re-derived from UIDevice.Changed now, which fires on exactly
	-- those hardware transitions.
	local function refreshDevIntro()
		devIntro.Text = UIDevice.SuppressesKeyboardGlyphs()
			and "WHITELISTED DEVELOPER CONTROLS"
			or "WHITELISTED DEVELOPER CONTROLS  //  PHONE: J"
	end
	refreshDevIntro()
	table.insert(deviceCaptionRefreshers, refreshDevIntro)

	local devScroll = Instance.new("ScrollingFrame")
	devScroll.Name = "DevControls"
	devScroll.Position = UDim2.fromOffset(0, 42)
	devScroll.Size = UDim2.new(1, 0, 1, -42)
	devScroll.BackgroundTransparency = 1
	devScroll.BorderSizePixel = 0
	devScroll.ScrollBarThickness = 5
	devScroll.ScrollBarImageColor3 = COLORS.accent
	devScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	devScroll.CanvasSize = UDim2.new()
	devScroll.Parent = pages.Dev
	contract.scroll("Dev", devScroll)

	local devLayout = Instance.new("UIListLayout")
	devLayout.Padding = UDim.new(0, 6)
	devLayout.SortOrder = Enum.SortOrder.LayoutOrder
	devLayout.Parent = devScroll
	local devPadding = Instance.new("UIPadding")
	devPadding.PaddingRight = UDim.new(0, 8)
	devPadding.Parent = devScroll

	-- Declared here and not beside devIntro: devScroll is created below it, so a
	-- hook written up there would capture a global rather than this local.
	table.insert(layoutHooks, function(fit)
		local height = fit.Compact and 30 or 42
		devIntro.Size = UDim2.new(1, 0, 0, height - 8)
		devIntro.TextSize = fit.Compact and 12 or 14
		devScroll.Position = UDim2.fromOffset(0, height)
		devScroll.Size = UDim2.new(1, 0, 1, -height)
	end)

	local controls = {
		{
			Name = "ESP",
			Description = "Highlights objectives and hostile entities through walls.",
			Key = "B",
			Command = "esp",
			Attribute = "DevCheatEsp",
		},
		{
			Name = "3-SECOND QUEUE",
			Description = "Shortens the lobby station countdown for rapid testing.",
			Key = "B",
			Command = "fastQueue",
			Attribute = "DevCheatFastQueue",
		},
		{
			Name = "NOCLIP FLY",
			-- WASD / Space / Left Ctrl are the only keyboard-movement strings in
			-- any client file. On touch the same cheat is driven by the on-screen
			-- stick, so the caption must not name keys the device has not got.
			-- Same fault as the heading above (C4B_DEV_CAPTION_LIVE_INPUT_20260829):
			-- this was one IsTouch() read baked into the table at construction. BOTH
			-- strings are carried now and which one is drawn is decided per refresh
			-- by SuppressesKeyboardGlyphs(), so a hybrid device gets the stick copy
			-- and a keyboard attached mid-session changes the row.
			Description = "Fly through geometry with WASD, Space and Left Ctrl.",
			TouchDescription = "Fly through geometry using the movement stick.",
			Key = "V",
			Command = "noclip",
			Attribute = "DevCheatNoclip",
		},
		{
			Name = "PAUSE ENTITIES",
			Description = "Freezes or resumes hostile entity behavior.",
			Key = "P",
			Command = "pauseEntity",
			Attribute = "DevCheatEntityPaused",
		},
		{
			Name = "PUSH IMMUNITY",
			Description = "Ignores the Level 1 Entity's yell push-back.",
			Key = "I",
			Command = "immunePush",
			Attribute = "DevCheatPushImmune",
		},
		{
			Name = "UNLIMITED EQUIPMENT",
			Description = "Unlimited flashlight battery and player stamina.",
			Key = "U",
			Command = "unlimited",
			Attribute = "DevCheatUnlimited",
		},
		{
			Name = "THIRD-PERSON CAMERA",
			Description = "Switches gameplay between first and third person.",
			Key = "C",
			Command = "thirdPerson",
			Attribute = "DevCheatThirdPerson",
		},
	}
	if level3TimelineOwner then
		table.insert(controls, {
			Name = "SKIP TO BLACKOUT WARNING",
			Description = "Jumps the active Level 3 song to 2:25 for the five-second warning.",
			Key = "K",
			Command = "level3PreBlackout",
			Action = true,
		})
	end

	local playerScripts = player:WaitForChild("PlayerScripts")
	local function sendDevCommand(command)
		local event = playerScripts:FindFirstChild("DevCheatCommand")
		if event and event:IsA("BindableEvent") then
			event:Fire(command)
		else
			showStatus("Developer controls are still loading. Try again.", "error")
		end
	end

	for order, info in ipairs(controls) do
		local row = Instance.new("Frame")
		row.Name = info.Command
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 48)
		row.BackgroundColor3 = COLORS.card
		row.BorderSizePixel = 0
		row.Parent = devScroll
		corner(row, 8)
		outline(row, COLORS.line, 0.4)

		local rowTitle = label(
			row,
			info.Name,
			UDim2.new(1, -190, 0, 24),
			UDim2.fromOffset(14, 4),
			14,
			COLORS.text,
			Enum.Font.GothamBold
		)
		rowTitle.Name = "RowTitle"
		local description = label(
			row,
			info.Description,
			UDim2.new(1, -190, 0, 18),
			UDim2.fromOffset(14, 27),
			11,
			COLORS.muted
		)
		-- Named for the same reason as DevIntro: the row's title label and this one
		-- were both the default "TextLabel", so neither could be addressed.
		description.Name = "Description"
		-- WRAPPED, never truncated. This was TextTruncate.AtEnd, and on a
		-- 440x956 portrait phone the label column resolves to 192px against
		-- 284-332px of copy -- so every developer description was ellipsized
		-- mid-sentence. A description that cannot be read is not a description;
		-- the ROW grows instead, and the page scrolls.
		description.TextWrapped = true
		description.TextYAlignment = Enum.TextYAlignment.Top
		if info.TouchDescription then
			-- A row whose copy names keys follows the LIVE input mode, exactly like
			-- the ON/OFF caption beside it. Registered with the shared refresher list
			-- so UIDevice.Changed rebuilds it; resolved once here so the row is right
			-- on the very first frame rather than one signal later.
			local function refreshDescription()
				description.Text = UIDevice.SuppressesKeyboardGlyphs()
					and info.TouchDescription
					or info.Description
				-- The row's height is measured FROM this string, so a caption
				-- swap has to re-run the layout or the box keeps the other
				-- variant's height.
				if applyTerminalLayout then applyTerminalLayout() end
			end
			refreshDescription()
			table.insert(deviceCaptionRefreshers, refreshDescription)
		end

		local toggle = button(row, "OFF", UDim2.fromOffset(158, 36), UDim2.new(1, -172, 0, 6))
		toggle.Name = "Toggle"
		-- The row is keyed by its COMMAND, which is what DevCheats answers to, so a
		-- row that stops reaching the cheat it names cannot still look correct.
		contract.card("Dev", info.Command, row, toggle)
		-- The DEV row was a fixed side-by-side: a `1, -190` label column and a
		-- 158px toggle. On a 300px-wide page that label column resolves to 110px
		-- and the toggle starts at x = -32, i.e. off the left edge of its own row
		-- -- which is exactly the "everything in one horizontal line" the DEV page
		-- shipped as. Under 380 the row STACKS instead: full-width title and
		-- description, then a full-width control under them.
		-- The row's height is DERIVED from the measured copy, in both
		-- arrangements. It used to be a constant (48 side-by-side, 30+tap
		-- stacked) with a fixed 14/18px description box, so the copy was
		-- truncated to fit the box rather than the box sized to fit the copy.
		table.insert(layoutHooks, function(fit)
			local tap = math.max(fit.Tap, 36)
			local titleFace = fit.DevStacked and 13 or 14
			local descFace = 11
			local pad = 14
			if fit.DevStacked then
				local copyWidth = fit.ContentWidth - 8 - pad * 2
				local titleHeight = math.max(18,
					textHeightFor(info.Name, titleFace, rowTitle.Font, copyWidth))
				local descHeight = math.max(14,
					textHeightFor(description.Text, descFace, description.Font, copyWidth))
				rowTitle.TextSize = titleFace
				rowTitle.Position = UDim2.fromOffset(pad, 6)
				rowTitle.Size = UDim2.new(1, -pad * 2, 0, titleHeight)
				description.TextSize = descFace
				description.Position = UDim2.fromOffset(pad, 6 + titleHeight + 2)
				description.Size = UDim2.new(1, -pad * 2, 0, descHeight)
				local toggleTop = 6 + titleHeight + 2 + descHeight + 8
				toggle.Size = UDim2.new(1, -pad * 2, 0, tap)
				toggle.Position = UDim2.new(0, pad, 0, toggleTop)
				row.Size = UDim2.new(1, 0, 0, toggleTop + tap + 8)
			else
				local toggleWidth = math.min(158, math.max(110, fit.ContentWidth - 240))
				local copyWidth = fit.ContentWidth - 8 - pad * 2 - toggleWidth - 12
				local titleHeight = math.max(20,
					textHeightFor(info.Name, titleFace, rowTitle.Font, copyWidth))
				local descHeight = math.max(16,
					textHeightFor(description.Text, descFace, description.Font, copyWidth))
				local content = 6 + titleHeight + 3 + descHeight + 6
				local height = math.max(content, tap + 12)
				rowTitle.TextSize = titleFace
				rowTitle.Position = UDim2.fromOffset(pad, 6)
				rowTitle.Size = UDim2.fromOffset(copyWidth, titleHeight)
				description.TextSize = descFace
				description.Position = UDim2.fromOffset(pad, 6 + titleHeight + 3)
				description.Size = UDim2.fromOffset(copyWidth, descHeight)
				toggle.Size = UDim2.fromOffset(toggleWidth, tap)
				toggle.Position = UDim2.new(1, -(toggleWidth + pad), 0,
					math.floor((height - tap) / 2))
				row.Size = UDim2.new(1, 0, 0, height)
			end
		end)
		local function actionAvailable()
			return workspace:GetAttribute("SelectedLevel") == 3
				and workspace:GetAttribute("RoundActive") == true
				and player:GetAttribute("InRound") == true
		end
		local function refresh()
			if info.Action then
				local available = actionAvailable()
				-- info.Key is a keyboard binding. On a phone or tablet it names a
				-- key that does not exist, so UIDevice drops it entirely.
				toggle.Text = UIDevice.Caption(
					available and "SKIP" or "LEVEL 3 ONLY", "//  " .. info.Key)
				toggle.TextColor3 = available and COLORS.accent or COLORS.muted
				-- LEVEL 3 ONLY is the message, so the row stays drawn and stays
				-- measurable at its tap floor and only leaves the input stack. Same
				-- idiom as an owned product on the Shop page.
				UIDevice.SetEnabled(toggle, available)
				toggle.AutoButtonColor = available
			else
				local enabled = player:GetAttribute(info.Attribute) == true
				toggle.Text = UIDevice.Caption(enabled and "ON" or "OFF", "//  " .. info.Key)
				toggle.TextColor3 = enabled and COLORS.accent or COLORS.muted
			end
		end
		toggle.Activated:Connect(function()
			if not info.Action or actionAvailable() then sendDevCommand(info.Command) end
		end)
		if info.Action then
			workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(refresh)
			workspace:GetAttributeChangedSignal("RoundActive"):Connect(refresh)
			player:GetAttributeChangedSignal("InRound"):Connect(refresh)
		else
			player:GetAttributeChangedSignal(info.Attribute):Connect(refresh)
		end
		refresh()
		table.insert(deviceCaptionRefreshers, refresh)
	end

	if level3TimelineOwner then
		player:GetAttributeChangedSignal("DevLevel3TimelineSerial"):Connect(function()
			local status = tostring(player:GetAttribute("DevLevel3TimelineStatus") or "")
			if status == "SKIPPED_TO_2_25" then
				showStatus("Skipped to 2:25 — blackout warning started.", "success")
			elseif status == "ALREADY_AT_OR_PAST_WARNING" then
				showStatus("Already at or past the 2:25 warning.", "error")
			elseif status == "OBJECTIVE_COMPLETE" then
				showStatus("Level 3 is already complete.", "error")
			else
				showStatus("Level 3 skip unavailable: " .. status, "error")
			end
		end)
	end
end

local upgradeIntro = label(
	pages.Upgrades,
	"Every Research Token permanently adds +5%. There is no maximum level.",
	UDim2.new(1, 0, 0, 42),
	UDim2.fromOffset(4, 0),
	15,
	COLORS.muted
)
upgradeIntro.Name = "UpgradeIntro"
upgradeIntro.TextWrapped = true

-- The two upgrade cards used to be two half-width frames pinned to the page
-- with `Size = UDim2.new(0.5, -10, 1, -68)`. On a page 100px tall -- which is
-- what the collapsed terminal produced -- that is a 32px card holding a 44px
-- headline and a 48px button, i.e. four children stacked outside their own box.
-- They now live in a SCROLL with a grid that flips to a single column, and the
-- card keeps a fixed authored height so its internals are never squeezed: the
-- page scrolls instead of the composition breaking.
local upgradeScroll = Instance.new("ScrollingFrame")
upgradeScroll.Name = "UpgradeCards"
upgradeScroll.Position = UDim2.fromOffset(0, 50)
upgradeScroll.Size = UDim2.new(1, 0, 1, -50)
upgradeScroll.BackgroundTransparency = 1
upgradeScroll.BorderSizePixel = 0
upgradeScroll.ScrollBarThickness = 5
upgradeScroll.ScrollBarImageColor3 = COLORS.accent
upgradeScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
upgradeScroll.CanvasSize = UDim2.new()
upgradeScroll.Parent = pages.Upgrades
contract.scroll("Upgrades", upgradeScroll)

local upgradeGrid = Instance.new("UIGridLayout")
upgradeGrid.CellSize = UDim2.new(0.5, -8, 0, 330)
upgradeGrid.CellPadding = UDim2.fromOffset(12, 12)
upgradeGrid.SortOrder = Enum.SortOrder.LayoutOrder
upgradeGrid.Parent = upgradeScroll

-- The card's authored internal stack, measured: 18 top pad + 34 title + 8 +
-- 72 description + 10 + 80 readout + 24 level + 18 gap + 48 button + 18 pad.
local UPGRADE_CARD_HEIGHT = 330

local function makeUpgradeCard(parent, order, titleText, description)
	local card = Instance.new("Frame")
	card.Name = titleText:match("^%a+") or "Upgrade"
	card.LayoutOrder = order
	card.BackgroundColor3 = COLORS.card
	card.BorderSizePixel = 0
	card.Parent = parent
	corner(card, 10)
	outline(card, COLORS.line, 0.35)

	label(card, titleText, UDim2.new(1, -36, 0, 34), UDim2.fromOffset(18, 18), 22, COLORS.text, Enum.Font.GothamBold)
	local desc = label(card, description, UDim2.new(1, -36, 0, 72), UDim2.fromOffset(18, 60), 14, COLORS.muted)
	desc.Name = "Description"
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	local current = label(card, "+0%", UDim2.new(1, -36, 0, 80), UDim2.fromOffset(18, 142), 44, COLORS.accent, Enum.Font.GothamBlack)
	current.Name = "Percent"
	local level = label(card, "LEVEL 0", UDim2.new(1, -36, 0, 24), UDim2.fromOffset(18, 222), 13, COLORS.muted, Enum.Font.Code)
	level.Name = "Level"
	local spend = button(card, "SPEND 1 TOKEN  //  +5%", UDim2.new(1, -36, 0, 48), UDim2.new(0, 18, 1, -66))
	spend.Name = "Spend"
	spend.BackgroundColor3 = Color3.fromRGB(21, 55, 53)
	spend.TextWrapped = true
	outline(spend, COLORS.accent, 0.2, 1.5)
	contract.card("Upgrades", card.Name, card, spend)
	return { Current = current, Level = level, Spend = spend }
end

local staminaCard = makeUpgradeCard(
	upgradeScroll,
	1,
	"STAMINA CAPACITY",
	"Run for longer before exhaustion. Sprint speed and noise remain unchanged."
)
local batteryCard = makeUpgradeCard(
	upgradeScroll,
	2,
	"BATTERY CAPACITY",
	"Keep the flashlight active for longer. Recharge speed remains unchanged."
)

table.insert(layoutHooks, function(fit)
	local introHeight = fit.Compact and 34 or 50
	upgradeIntro.Size = UDim2.new(1, 0, 0, introHeight - 8)
	upgradeIntro.TextSize = fit.Compact and 12 or 15
	upgradeScroll.Position = UDim2.fromOffset(0, introHeight)
	upgradeScroll.Size = UDim2.new(1, 0, 1, -introHeight)
	-- Two columns only where a column is still wide enough to hold the copy;
	-- one column, full width, below that. 240 is the width at which the 14px
	-- description wraps to four lines inside its 72px box.
	local twoUp = fit.ContentWidth >= 520
	upgradeGrid.CellSize = twoUp
		and UDim2.new(0.5, -8, 0, UPGRADE_CARD_HEIGHT)
		or UDim2.new(1, -8, 0, UPGRADE_CARD_HEIGHT)
	staminaCard.Spend.Size = UDim2.new(1, -36, 0, math.max(fit.Tap, 48))
	batteryCard.Spend.Size = UDim2.new(1, -36, 0, math.max(fit.Tap, 48))
end)
staminaCard.Spend.Activated:Connect(function() actionRemote:FireServer("UpgradeStamina") end)
batteryCard.Spend.Activated:Connect(function() actionRemote:FireServer("UpgradeBattery") end)

local shopScroll = Instance.new("ScrollingFrame")
-- NAMED. It was the default "ScrollingFrame", which is what a report saying
-- "ScrollingFrame's canvas does not reach its last row" was left calling it.
shopScroll.Name = "ShopCards"
shopScroll.Size = UDim2.fromScale(1, 1)
shopScroll.BackgroundTransparency = 1
shopScroll.BorderSizePixel = 0
shopScroll.ScrollBarThickness = 5
shopScroll.ScrollBarImageColor3 = COLORS.accent
shopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopScroll.CanvasSize = UDim2.new()
shopScroll.Parent = pages.Shop
contract.scroll("Shop", shopScroll)

local shopGrid = Instance.new("UIGridLayout")
shopGrid.CellSize = UDim2.new(0.5, -8, 0, 220)
shopGrid.CellPadding = UDim2.fromOffset(12, 12)
shopGrid.SortOrder = Enum.SortOrder.LayoutOrder
shopGrid.Parent = shopScroll

-- Every product card registers its measurable parts here. The grid carries ONE
-- cell size for the whole page, so the height has to be the TALLEST card's
-- measured stack, and that cannot be worked out from a card in isolation.
local productCards = {}

-- C_SHOP_CARD_MEASURED_20260830 -- WHAT SHIPPED BROKEN.
-- The card was a composition of constants: a 42px title box, a 68px description
-- box pinned at y = 72, and a 220px cell that only ever grew by the difference
-- between the tap floor and the authored 38px buy button. Nothing in it was
-- measured, so the copy was cut to fit the box instead of the box sized to fit
-- the copy -- the same fault the DEV rows had.
--
-- Measured at 568x320, where the old breakpoint (contentWidth >= 460) still put
-- two cards side by side: the description box resolves to roughly 134x68, while
-- Advanced Equipment and both token products need 72-84px of wrapped 12px copy.
-- All three were clipped mid-sentence. At 667x375 the token copy still needs
-- about 72px in that same 68px box.
--
-- Both halves are fixed at the source:
--   1. THE CELL IS MEASURED. Title, description and buy action are measured at
--      the ACTUAL card width and stacked, and the cell takes the tallest card's
--      stack. No box in the card is a constant any more, so nothing can clip.
--   2. THE BREAKPOINT IS MEASURED TOO. 460 was a PANEL width, but the text goes
--      in the panel minus the 76px icon and its insets -- 118px narrower. Two
--      columns are used only while that copy column can still hold the widest
--      product NAME on one line at its 18px face; below it the card is mostly
--      icon, so the page takes one full-width column and scrolls instead.
table.insert(layoutHooks, function(fit)
	-- The copy column starts after the icon (14 pad + 76 icon + 14 gap) and ends
	-- at the card's own 14px right pad. Stated once here, so the measurement and
	-- the placement below cannot disagree about where the text goes.
	local copyLeft, copyInset = 104, 118
	local buyHeight = math.max(fit.Tap, 38)
	local twoUpWidth = math.floor(fit.ContentWidth * 0.5) - 8
	local twoUp = true
	for _, entry in ipairs(productCards) do
		if textWidthFor(entry.Heading.Text, entry.Heading.TextSize, entry.Heading.Font)
			> twoUpWidth - copyInset then
			twoUp = false
			break
		end
	end
	local cellWidth = twoUp and twoUpWidth or (fit.ContentWidth - 8)
	local copyWidth = math.max(48, cellWidth - copyInset)
	-- 94 is the icon's own bottom edge (18 top + 76 tall). A card is never
	-- shorter than the icon standing beside its copy.
	local bodyBottom = 94
	for _, entry in ipairs(productCards) do
		-- Measured at the label's OWN face, not a repeated literal, so a face
		-- change cannot leave the box sized for the other one.
		local titleHeight = math.max(22, textHeightFor(entry.Heading.Text,
			entry.Heading.TextSize, entry.Heading.Font, copyWidth))
		local descHeight = math.max(14, textHeightFor(entry.Desc.Text,
			entry.Desc.TextSize, entry.Desc.Font, copyWidth))
		-- MEASURED at copyWidth, but SIZED against the cell's own width, the way
		-- the authored card was. The grid resolves 0.5 of the canvas itself and
		-- may land a pixel either side of the width measured here; an offset
		-- width would hang that pixel outside the card.
		if entry.Tag then
			entry.Tag.Position = UDim2.fromOffset(copyLeft, 10)
			entry.Tag.Size = UDim2.new(1, -copyInset, 0, 18)
		end
		entry.Heading.Position = UDim2.fromOffset(copyLeft, entry.Top)
		entry.Heading.Size = UDim2.new(1, -copyInset, 0, titleHeight)
		entry.Desc.Position = UDim2.fromOffset(copyLeft, entry.Top + titleHeight + 6)
		entry.Desc.Size = UDim2.new(1, -copyInset, 0, descHeight)
		entry.Buy.Size = UDim2.new(1, -28, 0, buyHeight)
		entry.Buy.Position = UDim2.new(0, 14, 1, -(buyHeight + 12))
		bodyBottom = math.max(bodyBottom, entry.Top + titleHeight + 6 + descHeight)
	end
	local cellHeight = bodyBottom + 16 + buyHeight + 12
	shopGrid.CellSize = twoUp
		and UDim2.new(0.5, -8, 0, cellHeight)
		or UDim2.new(1, -8, 0, cellHeight)
end)

local function makeProductCard(key, item, kind)
	local card = Instance.new("Frame")
	card.Name = key
	card.BackgroundColor3 = COLORS.card
	card.BorderSizePixel = 0
	card.Parent = shopScroll
	corner(card, 9)
	outline(card, COLORS.line, 0.4)

	local icon = Instance.new("ImageLabel")
	icon.Name = "ProductIcon"
	icon.Size = UDim2.fromOffset(76, 76)
	icon.Position = UDim2.fromOffset(14, 18)
	icon.BackgroundColor3 = COLORS.bg
	icon.BorderSizePixel = 0
	local iconId = tonumber(item.IconId) or 0
	icon.Image = iconId > 0 and ("rbxassetid://" .. tostring(iconId)) or ""
	icon.ScaleType = Enum.ScaleType.Crop
	icon.Parent = card
	corner(icon, 38)
	outline(icon, COLORS.accent, 0.35, 1.5)
	-- A product without an approved image gets a deliberately authored text mark,
	-- never a stale or unrelated Marketplace thumbnail. Supporter uses this path
	-- after retiring its old hazmat artwork.
	if iconId <= 0 then
		local monogram = Instance.new("TextLabel")
		monogram.Name = "ProductMonogram"
		monogram.Size = UDim2.fromScale(1, 1)
		monogram.BackgroundTransparency = 1
		monogram.Font = Enum.Font.GothamBlack
		monogram.Text = type(item.IconText) == "string" and item.IconText or "Z//"
		monogram.TextColor3 = COLORS.accent
		monogram.TextScaled = true
		monogram.Parent = icon
		local textConstraint = Instance.new("UITextSizeConstraint")
		textConstraint.MinTextSize = 12
		textConstraint.MaxTextSize = 20
		textConstraint.Parent = monogram
	end

	-- The pass tag sits above the name, so a pass starts its name 12px lower.
	-- Both are authored starting points; the layout hook measures from here.
	local headingY = kind == "Pass" and 28 or 16
	local tag
	if kind == "Pass" then
		tag = label(card, "PERMANENT PASS", UDim2.new(1, -118, 0, 18), UDim2.fromOffset(104, 10), 10, COLORS.accent, Enum.Font.Code)
		tag.Name = "PassTag"
	end
	local heading = label(card, item.Name, UDim2.new(1, -118, 0, 42), UDim2.fromOffset(104, headingY), 18, COLORS.text, Enum.Font.GothamBold)
	-- Named for the same reason the DEV rows were: `label()` leaves the default
	-- "TextLabel" and the card holds several of them, so a clipping report could
	-- not say WHICH string overflowed.
	heading.Name = "ProductName"
	heading.TextWrapped = true
	local desc = label(card, item.Description or "", UDim2.new(1, -118, 0, 68), UDim2.fromOffset(104, 72), 12, COLORS.muted)
	desc.Name = "ProductDescription"
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	local buy = button(card, tostring(item.Price) .. " R$", UDim2.new(1, -28, 0, 38), UDim2.new(0, 14, 1, -50))
	buy.Name = "Buy"
	buy.TextColor3 = COLORS.accent2
	contract.card("Shop", key, card, buy)
	table.insert(productCards, {
		Heading = heading,
		Desc = desc,
		Buy = buy,
		Tag = tag,
		Top = headingY,
	})
	productButtons[key] = buy
	displayedProductPrices[key] = math.max(0, math.floor(tonumber(item.Price) or 0))
	if tonumber(item.Id) and item.Id > 0 then
		task.spawn(function()
			local infoType = kind == "Pass" and Enum.InfoType.GamePass or Enum.InfoType.Product
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, item.Id, infoType)
			local price = ok and type(info) == "table" and tonumber(info.PriceInRobux) or nil
			-- Profile rendering may have marked a pass OWNED while this request was
			-- in flight. Never replace that authoritative state with a late price.
			if price and price >= 0 and buy.Parent and buy.Active then
				displayedProductPrices[key] = math.floor(price)
				buy.Text = tostring(math.floor(price)) .. " R$"
			end
		end)
	end
	buy.Activated:Connect(function()
		if tonumber(item.Id) == nil or item.Id <= 0 then
			showStatus(item.Name .. ": Product ID is not configured yet.", "error")
			return
		end
		if kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, item.Id)
		else
			MarketplaceService:PromptProductPurchase(player, item.Id)
		end
	end)
	return card
end

makeProductCard("Supporter", Config.Passes.Supporter, "Pass")
makeProductCard("AdvancedEquipment", Config.Passes.AdvancedEquipment, "Pass")
makeProductCard("Tokens4", Config.Products.Tokens4, "Product")
makeProductCard("Tokens20", Config.Products.Tokens20, "Product")
makeProductCard("EmergencyReentry", Config.Products.EmergencyReentry, "Product")
makeProductCard("CosmeticEquipment", Config.Passes.CosmeticEquipment, "Pass")

local supportTotalLabel = label(
	pages.Donate,
	"YOUR RECORDED DONATIONS  0 R$",
	UDim2.new(1, -8, 0, 24),
	UDim2.fromOffset(4, 0),
	13,
	COLORS.accent2,
	Enum.Font.GothamBold
)
supportTotalLabel.Name = "DonationTotal"
supportTotalLabel.TextXAlignment = Enum.TextXAlignment.Left

local supportScroll = Instance.new("ScrollingFrame")
-- NAMED, for the same reason the shop's scroll is: the default
-- "ScrollingFrame" is not something a failure report can point at.
supportScroll.Name = "DonationCards"
supportScroll.Position = UDim2.fromOffset(0, 32)
supportScroll.Size = UDim2.new(1, 0, 1, -32)
supportScroll.BackgroundTransparency = 1
supportScroll.BorderSizePixel = 0
supportScroll.ScrollBarThickness = 5
supportScroll.ScrollBarImageColor3 = COLORS.accent
supportScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
supportScroll.CanvasSize = UDim2.new()
supportScroll.Parent = pages.Donate
contract.scroll("Donate", supportScroll)

local supportGrid = Instance.new("UIGridLayout")
supportGrid.CellSize = UDim2.new(0.5, -8, 0, 92)
supportGrid.CellPadding = UDim2.fromOffset(12, 10)
supportGrid.SortOrder = Enum.SortOrder.LayoutOrder
supportGrid.Parent = supportScroll

-- C_DONATION_CARD_MEASURED_20260831 -- WHAT SHIPPED BROKEN.
-- The donation card is a heading over one button, and that heading was the last
-- box in this terminal still drawn as a CONSTANT: 28px tall, WRAPPED, at a 16px
-- face, inside a cell whose width is a fraction of the content box. The card's
-- height was the matching constant, 48 plus the button.
--
-- The arithmetic is what condemns it. Two columns begin at a 440px content box,
-- where the cell resolves to 212px and the heading box to 188; the authored tier
-- names run to 24 characters -- "ZYNTRA Donate — Director", em dash and all --
-- at a 16px GothamBold face, near enough to that 188px that whether the name
-- takes a second line is settled by a font metric no code in the card ever asked
-- for. And a wrapped label that needs a second line in a 28px box does not push
-- its card open: it draws that line outside the box, and the reader loses the
-- tier they are being asked to pay for. No fixture in today's matrix lands in
-- that band, which is precisely what makes it worth fixing now rather than
-- later -- it is one authored string, or one breakpoint, away.
--
-- The heading is measured at the cell's own copy width, the way the shop card
-- beside it already is, and the cell takes the TALLEST heading on the page: a
-- UIGridLayout carries one cell size for every cell in it, so no card here can
-- be sized on its own.
table.insert(layoutHooks, function(fit)
	local buyHeight = math.max(fit.Tap, 36)
	local twoUp = fit.ContentWidth >= 440
	local cellWidth = twoUp and (math.floor(fit.ContentWidth * 0.5) - 8)
		or (fit.ContentWidth - 8)
	local copyWidth = math.max(48, cellWidth - 24)
	-- The authored 8 + 28 stays the FLOOR, so a short tier name keeps the card it
	-- was drawn for and only a heading that needs more room grows one.
	local headingBottom = 36
	for _, card in ipairs(supportScroll:GetChildren()) do
		local heading = card:IsA("Frame") and card:FindFirstChild("TierName")
		if heading then
			local headingHeight = math.max(28, textHeightFor(heading.Text,
				heading.TextSize, heading.Font, copyWidth))
			-- MEASURED at copyWidth but SIZED against the cell's own width, the way
			-- the shop card is: the grid resolves its own fraction of the canvas and
			-- may land a pixel either side of the width measured here, and an offset
			-- width would hang that pixel outside the card.
			heading.Position = UDim2.fromOffset(12, 8)
			heading.Size = UDim2.new(1, -24, 0, headingHeight)
			headingBottom = math.max(headingBottom, 8 + headingHeight)
		end
	end
	-- The button hangs off the card's BOTTOM edge, so the card has to carry the
	-- heading, the 12px gap under it and the tap target: a 44px target grows the
	-- cell rather than climbing into the name above it.
	local height = headingBottom + 12 + buyHeight + 8
	supportGrid.CellSize = twoUp
		and UDim2.new(0.5, -8, 0, height)
		or UDim2.new(1, -8, 0, height)
	supportTotalLabel.TextSize = fit.Compact and 12 or 13
	for _, card in ipairs(supportScroll:GetChildren()) do
		local buy = card:IsA("Frame") and card:FindFirstChild("Buy")
		if buy then
			buy.Size = UDim2.new(1, -24, 0, buyHeight)
			buy.Position = UDim2.new(0, 12, 1, -(buyHeight + 8))
		end
	end
end)

local function makeDonationCard(key, item)
	local card = Instance.new("Frame")
	card.Name = key
	card.LayoutOrder = math.floor(tonumber(item.Order) or 0)
	card.BackgroundColor3 = COLORS.card
	card.BorderSizePixel = 0
	card.Parent = supportScroll
	corner(card, 9)
	outline(card, COLORS.accent, 0.52)

	local heading = label(
		card,
		item.Name,
		UDim2.new(1, -24, 0, 28),
		UDim2.fromOffset(12, 8),
		16,
		COLORS.text,
		Enum.Font.GothamBold
	)
	-- Named for the same reason the shop card's ProductName is: `label()` leaves
	-- the default "TextLabel", and the layout hook above has to find this one to
	-- measure it.
	heading.Name = "TierName"
	heading.TextWrapped = true
	local productId = math.floor(tonumber(item.Id) or 0)
	local buy = button(card, tostring(item.Price) .. " R$  //  DONATE", UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 1, -44))
	buy.Name = "Buy"
	buy.TextWrapped = true
	buy.TextColor3 = COLORS.accent2
	productButtons[key] = buy
	displayedProductPrices[key] = math.max(0, math.floor(tonumber(item.Price) or 0))
	-- The tier KEY is the card's name and the card's key, so a matrix can go
	-- ZyntraConfig.Donations key -> card -> action without matching a display
	-- string that a copy change is free to rewrite.
	card:SetAttribute("DonationTierKey", key)
	card:SetAttribute("DonationProductId", productId)
	contract.card("Donate", key, card, buy)
	if productId <= 0 then
		buy.Text = "COMING SOON"
		buy.TextColor3 = COLORS.muted
		-- DISABLED, not hidden and not merely un-Actived. The card's action is what
		-- the touch-target floor is measured on, so an unconfigured tier keeps its
		-- whole rectangle and its label -- COMING SOON is the message -- and only
		-- leaves the input stack. UIDevice.SetEnabled is this codebase's idiom for
		-- exactly that, and it takes Selectable and Modal down with Active so a
		-- gamepad cannot land on a product that cannot be bought.
		UIDevice.SetEnabled(buy, false)
	else
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
			local price = ok and type(info) == "table" and tonumber(info.PriceInRobux) or nil
			if price and price >= 0 and buy.Parent and buy.Active then
				displayedProductPrices[key] = math.floor(price)
				buy.Text = tostring(math.floor(price)) .. " R$  //  DONATE"
			end
		end)
		buy.Activated:Connect(function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
	end
	return card
end

local donationEntries = {}
for key, item in pairs(Config.Donations or {}) do
	donationEntries[#donationEntries + 1] = { Key = key, Item = item }
end
table.sort(donationEntries, function(a, b)
	local aOrder = tonumber(a.Item.Order) or math.huge
	local bOrder = tonumber(b.Item.Order) or math.huge
	if aOrder == bOrder then return a.Key < b.Key end
	return aOrder < bOrder
end)
for _, entry in ipairs(donationEntries) do
	makeDonationCard(entry.Key, entry.Item)
	-- The authored order, published. A harness that reads ZyntraConfig itself
	-- gets an UNORDERED dictionary back and cannot tell a tier that is missing
	-- from one that was renamed.
	table.insert(contract.Donations, entry.Key)
end

local colorsScroll = Instance.new("ScrollingFrame")
-- NAMED, for the same reason the other two page scrolls now are: the default
-- "ScrollingFrame" is not something a failure report can point at.
colorsScroll.Name = "ColorPickers"
colorsScroll.Size = UDim2.fromScale(1, 1)
colorsScroll.BackgroundTransparency = 1
colorsScroll.BorderSizePixel = 0
colorsScroll.ScrollBarThickness = 5
colorsScroll.ScrollBarImageColor3 = COLORS.accent
colorsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
colorsScroll.CanvasSize = UDim2.new()
colorsScroll.Parent = pages.Colors
contract.scroll("Colors", colorsScroll)
local colorsLayout = Instance.new("UIListLayout")
colorsLayout.Padding = UDim.new(0, 12)
colorsLayout.SortOrder = Enum.SortOrder.LayoutOrder
colorsLayout.Parent = colorsScroll
local colorsPadding = Instance.new("UIPadding")
colorsPadding.PaddingRight = UDim.new(0, 8)
colorsPadding.Parent = colorsScroll

local HUE_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
	ColorSequenceKeypoint.new(1/6, Color3.fromHSV(1/6, 1, 1)),
	ColorSequenceKeypoint.new(2/6, Color3.fromHSV(2/6, 1, 1)),
	ColorSequenceKeypoint.new(3/6, Color3.fromHSV(3/6, 1, 1)),
	ColorSequenceKeypoint.new(4/6, Color3.fromHSV(4/6, 1, 1)),
	ColorSequenceKeypoint.new(5/6, Color3.fromHSV(5/6, 1, 1)),
	ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
})

local function makeColorPicker(parent, key, titleText, actionName)
	local card = Instance.new("Frame")
	card.Name = key
	card.Size = UDim2.new(1, 0, 0, 214)
	card.BackgroundColor3 = COLORS.card
	card.BorderSizePixel = 0
	card.Parent = parent
	corner(card, 9)
	outline(card, COLORS.line, 0.4)

	local heading = label(card, titleText, UDim2.new(1, -170, 0, 28), UDim2.fromOffset(16, 12), 18, COLORS.text, Enum.Font.GothamBold)
	-- Named so a clipping report can say WHICH string overflowed; `label()`
	-- leaves the default "TextLabel" and this card holds five of them.
	heading.Name = "Title"
	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.Position = UDim2.new(1, -148, 0, 12)
	preview.Size = UDim2.fromOffset(48, 28)
	preview.BackgroundColor3 = Color3.new(1, 1, 1)
	preview.BorderSizePixel = 0
	preview.Parent = card
	corner(preview, 6)
	outline(preview, Color3.new(1, 1, 1), 0.35)

	local save = button(card, "SAVE", UDim2.fromOffset(82, 30), UDim2.new(1, -92, 0, 11))
	save.Name = "Save"
	save.TextColor3 = COLORS.accent
	contract.card("Colors", key, card, save)

	local state = { H = 0, S = 0.5, V = 1, Action = actionName }
	local sliderObjects = {}

	local function makeSlider(row, name, minimum, maximum)
		local caption = label(card, name, UDim2.fromOffset(34, 24), UDim2.fromOffset(18, 52 + row * 48), 12, COLORS.muted, Enum.Font.Code)
		caption.Name = name .. "Caption"
		local bar = Instance.new("Frame")
		bar.Position = UDim2.fromOffset(58, 58 + row * 48)
		bar.Size = UDim2.new(1, -82, 0, 16)
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BorderSizePixel = 0
		bar.Parent = card
		corner(bar, 8)
		local gradient = Instance.new("UIGradient")
		gradient.Parent = bar
		local knob = Instance.new("Frame")
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Position = UDim2.fromScale(0, 0.5)
		knob.Size = UDim2.fromOffset(12, 26)
		knob.BackgroundColor3 = COLORS.text
		knob.BorderSizePixel = 0
		knob.ZIndex = 4
		knob.Parent = bar
		corner(knob, 6)
		outline(knob, COLORS.bg, 0, 2)
		local hit = Instance.new("TextButton")
		hit.Name = name .. "Slider"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.new(1, 16, 1, 20)
		hit.Position = UDim2.fromOffset(-8, -10)
		hit.ZIndex = 5
		hit.Parent = bar
		sliderObjects[name] = {
			Bar = bar,
			Caption = caption,
			Hit = hit,
			Row = row,
			Gradient = gradient,
			Knob = knob,
			Min = minimum,
			Max = maximum,
		}

		local dragging = false
		local function updateFromX(x)
			local fraction = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
			state[name] = minimum + (maximum - minimum) * fraction
			if state.Refresh then state.Refresh() end
		end
		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				updateFromX(input.Position.X)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				updateFromX(input.Position.X)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
		end)
	end

	makeSlider(0, "H", 0, 1)
	makeSlider(1, "S", 0, 0.9)
	makeSlider(2, "V", 0.35, 1)

	-- C_COLOR_PICKER_REFLOW_20260830 -- WHAT SHIPPED BROKEN.
	-- The card's top row was three rectangles placed by constant subtraction and
	-- nothing ever asked how wide the name actually is: a `1, -170` title box, a
	-- 48px preview swatch and SAVE against the right edge. The previous pass did
	-- grow SAVE to the 44px tap floor and shift the swatch left to clear it, but
	-- the title box stayed `1, -170` -- so the fix moved the swatch INTO the name
	-- rather than away from it.
	--
	-- Measured at 375x667: the card resolves to 319px wide, which leaves the
	-- title box 149px, and "GLOWSTICK LIGHT" needs about 153px at its 18px face.
	-- The name ran under the preview swatch. 338x705 is narrower and worse.
	--
	-- The row is measured now and gives way in one ordered ladder: the authored
	-- 18px face, a 16px face on a compact panel, and if the name still does not
	-- fit beside the swatch and SAVE the header STACKS -- name on its own
	-- full-width row, swatch and SAVE right-aligned beneath it. The name is
	-- never abbreviated and never truncated.
	--
	-- Everything below the header is measured FROM the header's bottom instead
	-- of from the authored 52/58 constants, because a stacked header moves it,
	-- and the card's own height follows the last hit rectangle rather than the
	-- constant 214 that assumed a one-row header and a 30px SAVE.
	table.insert(layoutHooks, function(fit)
		-- colorsScroll carries an 8px right pad, so a `1, 0` card is that much
		-- narrower than the content box.
		local cardWidth = math.max(160, fit.ContentWidth - 8)
		local leftPad, rightPad, gap = 16, 10, 8
		local previewWidth, previewHeight = 48, 28
		local saveWidth = 88
		local saveHeight = math.max(fit.Tap, 30)
		-- The swatch and SAVE keep their authored cluster: SAVE against the
		-- card's right pad, the swatch 8px inside it. Stated once, so the title's
		-- room and the two positions cannot disagree the way they used to.
		local clusterWidth = previewWidth + gap + saveWidth + rightPad
		local titleFace = fit.Compact and 16 or 18
		local titleRoom = cardWidth - leftPad - clusterWidth - gap
		-- The card is MEASURED from the content box above, but every horizontal
		-- rectangle below is expressed against the card's OWN width, the way the
		-- authored row was: the scroll's padding and the card's `1, 0` width can
		-- land a pixel either side of the measured value, and an offset position
		-- would hang SAVE that pixel outside its card.
		local saveInset = rightPad + saveWidth
		local previewInset = saveInset + gap + previewWidth
		-- TEXT_FIT_SLACK, because the losing branch draws this heading UNWRAPPED.
		-- A name that clears its room by a pixel here is a name the regression's own
		-- re-measurement can report as running into the swatch, and the player who
		-- sees it cannot tell the difference either.
		local stacked = textWidthFor(heading.Text, titleFace, heading.Font)
			+ TEXT_FIT_SLACK > titleRoom
		local headerBottom
		heading.TextSize = titleFace
		save.Size = UDim2.fromOffset(saveWidth, saveHeight)
		preview.Size = UDim2.fromOffset(previewWidth, previewHeight)
		if stacked then
			local titleHeight = math.max(22, textHeightFor(heading.Text, titleFace,
				heading.Font, math.max(60, cardWidth - leftPad * 2)))
			heading.TextWrapped = true
			heading.Position = UDim2.fromOffset(leftPad, 12)
			heading.Size = UDim2.new(1, -leftPad * 2, 0, titleHeight)
			local rowTop = 12 + titleHeight + gap
			local rowHeight = math.max(saveHeight, previewHeight)
			save.Position = UDim2.new(1, -saveInset, 0,
				rowTop + math.floor((rowHeight - saveHeight) / 2))
			preview.Position = UDim2.new(1, -previewInset, 0,
				rowTop + math.floor((rowHeight - previewHeight) / 2))
			headerBottom = rowTop + rowHeight
		else
			local titleHeight = titleFace + 8
			local rowHeight = math.max(saveHeight, previewHeight, titleHeight)
			heading.TextWrapped = false
			heading.Position = UDim2.fromOffset(leftPad,
				12 + math.floor((rowHeight - titleHeight) / 2))
			heading.Size = UDim2.new(1, -(leftPad + clusterWidth + gap), 0, titleHeight)
			save.Position = UDim2.new(1, -saveInset, 0,
				12 + math.floor((rowHeight - saveHeight) / 2))
			preview.Position = UDim2.new(1, -previewInset, 0,
				12 + math.floor((rowHeight - previewHeight) / 2))
			headerBottom = 12 + rowHeight
		end
		-- The bar is 16px tall and its hit rectangle was 36. The three rows sit
		-- one PITCH apart, and the pitch is derived from the target rather than
		-- left at the authored 48: a 44px target centred on a bar overhangs it by
		-- 14 top and bottom, so anything under target + 4 makes two neighbouring
		-- targets overlap and steal each other's drags.
		local hitHeight = math.max(fit.Tap, 36)
		local pitch = math.max(48, hitHeight + 4)
		local captionTop = headerBottom + 12
		local lastRow = 0
		for _, slider in pairs(sliderObjects) do
			slider.Caption.Position =
				UDim2.fromOffset(18, captionTop + slider.Row * pitch)
			slider.Bar.Position =
				UDim2.fromOffset(58, captionTop + 6 + slider.Row * pitch)
			slider.Bar.Size = UDim2.new(1, -82, 0, 16)
			slider.Hit.Size = UDim2.new(1, 16, 0, hitHeight)
			slider.Hit.Position = UDim2.fromOffset(-8, math.floor((16 - hitHeight) / 2))
			lastRow = math.max(lastRow, slider.Row)
		end
		-- The card ends below the last HIT rectangle, not below the last bar --
		-- the target overhangs the 16px bar by half its excess. Counted from the
		-- rows that exist rather than from a literal three.
		card.Size = UDim2.new(1, 0, 0, captionTop + 6 + lastRow * pitch + 16
			+ math.ceil((hitHeight - 16) / 2) + 10)
	end)

	function state.Refresh()
		local selected = Color3.fromHSV(state.H, state.S, state.V)
		preview.BackgroundColor3 = selected
		sliderObjects.H.Gradient.Color = HUE_SEQUENCE
		sliderObjects.S.Gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(state.H, 0.9, 1))
		sliderObjects.V.Gradient.Color = ColorSequence.new(Color3.fromHSV(state.H, state.S, 0.35), Color3.fromHSV(state.H, state.S, 1))
		for name, slider in pairs(sliderObjects) do
			local fraction = (state[name] - slider.Min) / (slider.Max - slider.Min)
			slider.Knob.Position = UDim2.fromScale(fraction, 0.5)
		end
	end

	local lock = label(card, "PASS REQUIRED", UDim2.fromScale(1, 1), UDim2.new(), 16, COLORS.accent2, Enum.Font.GothamBold)
	lock.Name = "Lock"
	-- WRAPPED for the same reason the title is measured: this cover carries
	-- "ADVANCED EQUIPMENT REQUIRED", about 250px at 16px GothamBold, and the
	-- card is 306px wide at 338x705 and narrower still below it. An unwrapped
	-- cover caption runs out of its own card.
	lock.TextWrapped = true
	lock.BackgroundTransparency = 0.14
	lock.BackgroundColor3 = COLORS.bg
	lock.TextXAlignment = Enum.TextXAlignment.Center
	lock.ZIndex = 12
	corner(lock, 9)

	save.Activated:Connect(function()
		-- The lock is a LABEL: it draws over the card but takes no input, so SAVE
		-- underneath it stays a full 88x44 target that a player can reach and press.
		-- It kept returning in silence, which reads as a broken button rather than a
		-- locked one. The control stays Active -- it is the only action this card
		-- has, and the terminal now publishes it as such -- so it answers instead.
		if lock.Visible then
			showStatus(lock.Text, "error")
			return
		end
		actionRemote:FireServer(actionName, Color3.fromHSV(state.H, state.S, state.V))
	end)

	local control = {}
	function control.SetColor(color)
		if typeof(color) ~= "Color3" then return end
		state.H, state.S, state.V = color:ToHSV()
		state.V = math.clamp(state.V, 0.35, 1)
		state.S = math.clamp(state.S, 0, 0.9)
		state.Refresh()
	end
	function control.SetLocked(locked, text)
		lock.Visible = locked
		lock.Text = text or "PASS REQUIRED"
	end
	state.Refresh()
	return control
end

local hazmatPicker = makeColorPicker(colorsScroll, "Hazmat", "HAZMAT SUIT", "SetHazmatColor")
local glowstickPicker = makeColorPicker(colorsScroll, "Glowstick", "GLOWSTICK LIGHT", "SetGlowstickColor")

player:SetAttribute("ZyntraReentryOpen", nil)

-- Re-entry is a true modal, separate from the store HUD. It stays centered and
-- constrained on desktop, tablet and phone, and its input shield prevents dead
-- players from clicking gameplay controls through the purchase card.
local reentryGui = Instance.new("ScreenGui")
reentryGui.Name = "ZyntraReentryModal"
reentryGui.ResetOnSpawn = false
reentryGui.IgnoreGuiInset = false
reentryGui.DisplayOrder = 120
reentryGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
reentryGui.Enabled = false
reentryGui.Parent = player:WaitForChild("PlayerGui")

local reentryShade = Instance.new("TextButton")
reentryShade.Name = "InputShield"
reentryShade.Size = UDim2.fromScale(1, 1)
reentryShade.BackgroundColor3 = Color3.fromRGB(2, 4, 5)
reentryShade.BackgroundTransparency = 0.36
reentryShade.BorderSizePixel = 0
reentryShade.Text = ""
reentryShade.AutoButtonColor = false
reentryShade.Active = true
reentryShade.Modal = true
reentryShade.ZIndex = 1
reentryShade.Parent = reentryGui

local reentry = Instance.new("Frame")
reentry.Name = "EmergencyReentry"
reentry.AnchorPoint = Vector2.new(0.5, 0.5)
reentry.Position = UDim2.fromScale(0.5, 0.54)
reentry.Size = UDim2.new(1, -32, 0, 164)
reentry.BackgroundColor3 = COLORS.bg
reentry.BorderSizePixel = 0
reentry.Visible = true
reentry.ZIndex = 2
reentry.Parent = reentryGui
local reentryConstraint = Instance.new("UISizeConstraint")
reentryConstraint.MinSize = Vector2.new(280, 164)
reentryConstraint.MaxSize = Vector2.new(480, 164)
reentryConstraint.Parent = reentry
corner(reentry, 10)
outline(reentry, COLORS.error, 0.15, 1.5)
local reentryTitle = label(reentry, "EMERGENCY RE-ENTRY", UDim2.new(1, -32, 0, 28), UDim2.fromOffset(16, 10), 19, COLORS.text, Enum.Font.GothamBold)
reentryTitle.ZIndex = 3
local reentryInfo = label(reentry, "The team has 15 seconds before the run is lost.", UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 44), 13, COLORS.muted)
reentryInfo.TextWrapped = true
reentryInfo.TextYAlignment = Enum.TextYAlignment.Top
reentryInfo.ZIndex = 3
local reentryButton = button(reentry, "USE RE-ENTRY", UDim2.new(1, -32, 0, 48), UDim2.fromOffset(16, 100))
reentryButton.TextColor3 = COLORS.error
reentryButton.TextScaled = true
reentryButton.ZIndex = 3
local reentryButtonTextConstraint = Instance.new("UITextSizeConstraint")
reentryButtonTextConstraint.MinTextSize = 11
reentryButtonTextConstraint.MaxTextSize = 14
reentryButtonTextConstraint.Parent = reentryButton
reentryButton.Activated:Connect(function()
	if profile and profile.ReentryCredits > 0 then
		actionRemote:FireServer("UseReentry")
	else
		local item = Config.Products.EmergencyReentry
		if item.Id <= 0 then
			showStatus("Emergency Re-entry Product ID is not configured yet.", "error")
			return
		end
		MarketplaceService:PromptProductPurchase(player, item.Id)
	end
end)

local function updateReentry()
	local inRound = player:GetAttribute("InRound") == true
	local roundActive = workspace:GetAttribute("RoundActive") == true
	local used = player:GetAttribute("ZyntraReentryUsed") == true
	local shouldShow = inRound and roundActive and reentryDead and not used
	reentryGui.Enabled = shouldShow
	player:SetAttribute("ZyntraReentryOpen", shouldShow or nil)
	local credits = profile and profile.ReentryCredits or 0
	reentryButton.Text = credits > 0
		and ("USE RE-ENTRY CREDIT  //  " .. credits .. " OWNED")
		or (tostring(displayedProductPrices.EmergencyReentry or Config.Products.EmergencyReentry.Price) .. " R$  //  BUY CREDIT")
end

local function bindCharacter(character)
	reentryDead = false
	updateReentry()
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		reentryDead = humanoid.Health <= 0
		updateReentry()
		humanoid.Died:Connect(function()
			reentryDead = true
			updateReentry()
		end)
	end)
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local function refreshUI()
	if not profile then
		tokenLabel.Text = "TOKENS  --"
		return
	end
	tokenLabel.Text = "TOKENS  " .. tostring(profile.Tokens)
	supportTotalLabel.Text = "YOUR RECORDED DONATIONS  " .. tostring(profile.DonationRobux or 0) .. " R$"
	staminaCard.Current.Text = "+" .. tostring(profile.StaminaPercent) .. "%"
	staminaCard.Level.Text = "LEVEL " .. tostring(profile.StaminaLevel)
	batteryCard.Current.Text = "+" .. tostring(profile.BatteryPercent) .. "%"
	batteryCard.Level.Text = "LEVEL " .. tostring(profile.BatteryLevel)

	local owned = {
		Supporter = profile.OwnsSupporter,
		AdvancedEquipment = profile.OwnsAdvancedEquipment,
		CosmeticEquipment = profile.OwnsCosmeticEquipment,
	}
	for key, isOwned in pairs(owned) do
		local itemButton = productButtons[key]
		if itemButton and isOwned then
			itemButton.Text = "OWNED"
			itemButton.TextColor3 = COLORS.accent
			-- DISABLED, not hidden. The card's action is what the touch-target floor
			-- is measured on, so an owned product keeps its whole rectangle and its
			-- label -- OWNED is the message -- and only leaves the input stack.
			-- SetEnabled also takes Selectable and Modal down with Active, which a
			-- bare `Active = false` did not: a gamepad could still land on a product
			-- that cannot be bought.
			UIDevice.SetEnabled(itemButton, false)
		end
	end

	hazmatPicker.SetLocked(not profile.OwnsAdvancedEquipment, "ADVANCED EQUIPMENT REQUIRED")
	glowstickPicker.SetLocked(not profile.OwnsCosmeticEquipment, "GLOWSTICK CUSTOMIZER REQUIRED")
	hazmatPicker.SetColor(profile.HazmatColor)
	glowstickPicker.SetColor(profile.GlowstickColor)
	updateReentry()
end

profileChangedRemote.OnClientEvent:Connect(function(newProfile, message, tone)
	if newProfile then profile = newProfile end
	refreshUI()
	if message and message ~= "" then showStatus(message, tone) end
end)

task.spawn(function()
	local ok, result = pcall(getProfileRemote.InvokeServer, getProfileRemote)
	if ok then
		profile = result
		refreshUI()
	else
		showStatus("Could not load the Zyntra profile.", "error")
	end
end)

-- Forward declaration. setMainVisible has to re-apply the OPENER predicate the
-- moment the terminal opens or closes, and that predicate lives in
-- updateVisibility below; updateVisibility in turn calls setMainVisible for its
-- own modal-exclusion rules. One of the two has to be declared early, and this
-- is the one with no dependencies of its own. The re-entrance latch is what
-- makes the pair terminate: updateVisibility's calls to setMainVisible must not
-- bounce straight back into updateVisibility.
local updateVisibility
local refreshingVisibility = false

local function setMainVisible(visible)
	-- Keep the invariant at the final write as well as at each input path. This
	-- makes a future caller unable to bypass queue/briefing mutual exclusion.
	main.Visible = visible == true and not modalBlocksStore()
	-- RoundUI uses this modal flag to release the cursor only while the
	-- whitelisted in-round phone is actually open.
	player:SetAttribute("DevPhoneOpen", devAllowed and main.Visible or nil)
	-- The terminal is a modal: while it is up it covers the movement controls,
	-- so the on-screen cluster must stand down rather than take taps through it.
	-- DevPhoneOpen only ever covered the whitelisted dev case, so the ordinary
	-- store had no such signal at all.
	player:SetAttribute("ZyntraStoreOpen", main.Visible or nil)
	-- The GAME's cluster honours that attribute already. Roblox's own dynamic
	-- thumbstick did not, and its activation region is the left 40% of the
	-- bottom two thirds -- straight through a modal that now uses the whole safe
	-- area, so every finger that landed on the terminal's left half was also
	-- walking the character. PlayerModule's ControlModule is the documented,
	-- reversible way to stand it down, and UIDevice does it on touch only.
	-- Suppression is shared by every screen-owning modal. Closing/refusing this
	-- terminal must not re-enable Roblox controls while QueueHostShade (or a
	-- re-entry modal) still owns the screen; derive the request from the complete
	-- published modal set instead of letting the last caller win.
	UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
	-- THE WAY OUT IS PART OF THE CONTRACT, and it is the mirror image of the rule
	-- below it: the opener leaves the input stack whenever the terminal is up, so
	-- the terminal's own close control has to be put into it just as
	-- deliberately. Nothing hides CloseTerminal today, which is the whole reason
	-- to state it here rather than trust a default -- on a phone this button and
	-- the Escape key are not equivalent, and an edit that gave the close control
	-- the opener's predicate by symmetry would leave a handheld player sealed
	-- inside the modal.
	if main.Visible then UIDevice.SetInteractive(closeButton, true) end
	-- The opener is not a companion to the terminal, it is its alternative. It
	-- was left drawn -- and Active -- UNDERNEATH the modal it had just opened,
	-- so a tap landing on the terminal's top-right corner reached a button that
	-- toggled the terminal shut. updateVisibility owns the full predicate.
	if not refreshingVisibility and updateVisibility then updateVisibility() end
end

function updateVisibility()
	refreshingVisibility = true
	local inRound = player:GetAttribute("InRound") == true
	local touchDevInLevel = inRound and devAllowed and UserInputService.TouchEnabled
	local blockedByModal = modalBlocksStore()
	-- The full terminal is part of the same modal-exclusion contract as its
	-- opener. If a queue or visible briefing is raised over an already-open
	-- terminal, close it and clear both modal attributes before updating input.
	if blockedByModal and main.Visible then
		setMainVisible(false)
	end
	-- Visible = false alone was never enough: an Active TextButton keeps taking
	-- taps through its own transparent background, which is how this control was
	-- swallowing the queue modal's Close. SetInteractive clears Active/Selectable
	-- with it, so a hidden button is genuinely gone from the input stack.
	-- Two independent suppressors, both of which own this same strip of screen:
	-- the queue host modal, and the dispatch briefing panel. Either one being up
	-- takes the opener off the screen AND out of the input stack.
	UIDevice.SetInteractive(openButton,
		(not inRound or touchDevInLevel)
			and not blockedByModal
			-- ...and never behind the terminal it opens.
			and not main.Visible)
	local layout = UIDevice.Layout()
	if layout.IsTouch then
		-- The right edge is owned by the game's RUN/JUMP/GLOW/FLASHLIGHT
		-- cluster on handhelds. Keep this lobby entry point in the small strip
		-- above it and end it just before the control column; this also leaves
		-- the briefing card's safe content band unobstructed below.
		local requestedWidth = touchDevInLevel and 136
			or (layout.Class == "tablet" and 220 or 184)
		-- A TAP TARGET OR NOTHING. `math.max(1, ...)` was the floor here, and a
		-- one-pixel-wide button is not a smaller control -- it is an invisible
		-- one, which is exactly what a stale control-zone measurement produced
		-- on the frame a round began. The floor is the same 44px minimum every
		-- other touch control in this game is held to; if the strip beside the
		-- cluster genuinely cannot hold that, the overlap becomes a visible
		-- failure in the touch-target matrix rather than a button nobody can hit.
		local availableWidth = math.max(1, layout.Zones.Controls.Left - layout.SafeLeft - 8)
		local buttonWidth = math.max(TOUCH_MIN_TAP_HEIGHT,
			math.min(requestedWidth, availableWidth))
		-- The authored 30/36/42 heights were ALL below the 44px tap target this
		-- game holds every other touch control to, which is why the dev variant in
		-- particular was almost unhittable. The floor is applied here, once, so no
		-- future per-class tweak can drop back under it. The TOP edge stays at
		-- y = 8 (= TopBand.Top once the 58px inset is added), so the button grows
		-- DOWNWARD into the safe band and never up under the Roblox topbar.
		local buttonHeight = math.max(TOUCH_MIN_TAP_HEIGHT, touchDevInLevel and 30
			or (layout.Class == "tablet" and 42 or 36))
		openButton.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
		if touchDevInLevel then
			-- C_OBJECTIVES_UPPER_RIGHT_20260830. In a LEVEL the upper right now
			-- belongs to the objective readout -- all three of them -- and this
			-- whitelisted-developer chip used to be pinned to exactly that corner.
			-- Measured at the real viewport with the touch layout applied, the
			-- Level 3 reader panel and this button overlapped outright.
			--
			-- It hangs UNDER the reserved column instead, right-aligned to the same
			-- edge, which is clear of every movement zone at every size in the
			-- matrix: the column's own right edge is already proved clear of the
			-- control cluster, and the space below it is clear of the thumbstick
			-- precisely because the column is far enough right to be.
			--
			-- The widest request of the three levels is used (Level 1's), so the
			-- chip clears whichever readout is actually on screen.
			-- C_ZYNTRA_DEV_CHIP_CLEARS_THE_CLUSTER_20260831.
			--
			-- "Under the column" was a single hard-coded spot, and it stopped
			-- being clear the moment the control zone became the MEASURED
			-- cluster rather than a 290px guess: the objective column now ends
			-- 8px above the real buttons, so `column.Bottom + 10` put this chip
			-- 2px INSIDE them and it sat on SNEAK. The spot is now chosen, not
			-- assumed -- ordered candidates, first one clear of every movement
			-- zone and of the readout itself wins, and the same test is what the
			-- touch-target matrix applies afterwards.
			local column = UIDevice.TopRightPanel(300, 190)
			local zones = layout.Zones
			local function hits(rect, other)
				return rect.Left < other.Right - 1 and rect.Right > other.Left + 1
					and rect.Top < other.Bottom - 1 and rect.Bottom > other.Top + 1
			end
			local function clear(left, top)
				local rect = {Left = left, Top = top,
					Right = left + buttonWidth, Bottom = top + buttonHeight}
				if rect.Left < layout.Safe.Left or rect.Right > layout.Safe.Right
					or rect.Top < layout.Safe.Top or rect.Bottom > layout.Safe.Bottom then
					return false
				end
				for _, key in ipairs({"Thumbstick", "Controls", "Jump"}) do
					if zones[key] and hits(rect, zones[key]) then return false end
				end
				return not hits(rect, column)
			end
			local placements = {
				-- 1. under the readout, right-aligned to it: the authored spot,
				--    kept wherever the cluster leaves room for it.
				{math.floor(column.Right) - buttonWidth, math.floor(column.Bottom) + 10},
				-- 2. beside the readout on its own row, to its left.
				{math.floor(column.Left) - 10 - buttonWidth, math.floor(column.Top)},
				-- 3. the far end of the same row, which no readout reaches.
				{layout.Safe.Left + 8, math.floor(column.Top)},
			}
			local chosen = placements[#placements]
			for _, spot in ipairs(placements) do
				if clear(spot[1], spot[2]) then chosen = spot break end
			end
			openButton.Position = UIDevice.LocalPosition(gui,
				math.max(layout.Safe.Left, chosen[1]), chosen[2])
		else
			-- The LOBBY has no objective readout, so the corner is free and this
			-- is the one place a player looks for the store.
			openButton.Position = UIDevice.LocalPosition(gui,
				math.max(layout.SafeLeft, layout.Zones.Controls.Left - buttonWidth - 8),
				layout.Safe.Top + 8)
		end
	else
		openButton.Size = UDim2.fromOffset(220, 42)
		openButton.Position = UDim2.new(1, -238, 0, 20)
	end
	if touchDevInLevel then
		-- Keep a discreet phone-only escape hatch for whitelisted developers.
		-- Desktop developers use J in levels, so no clickable HUD control is shown.
		openButton.Text = "ZYNTRA // DEV"
		openButton.TextSize = 11
		openButton.BackgroundTransparency = 0.48
		openButton.TextTransparency = 0.22
		openButtonOutline.Transparency = 0.64
		openButtonOutline.Thickness = 1
	else
		openButton.Text = "ZYNTRA // EQUIPMENT"
		openButton.TextSize = layout.IsTouch and layout.Class ~= "tablet" and 12 or 14
		openButton.BackgroundTransparency = 0
		openButton.TextTransparency = 0
		openButtonOutline.Transparency = 0.22
		openButtonOutline.Thickness = 1.5
	end
	if inRound and not devAllowed then setMainVisible(false) end
	updateReentry()
	refreshingVisibility = false
end
player:GetAttributeChangedSignal("InRound"):Connect(function()
	-- Do not carry an open shop across a character/world transition. Developers
	-- can reopen directly on the DEV page with J once the round is ready.
	setMainVisible(false)
	updateVisibility()
end)
player:GetAttributeChangedSignal(QUEUE_MODAL_ATTRIBUTE):Connect(updateVisibility)
player:GetAttributeChangedSignal(BRIEFING_ATTRIBUTE):Connect(updateVisibility)
player:GetAttributeChangedSignal("ZyntraReentryUsed"):Connect(updateReentry)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(updateReentry)
setMainVisible(false)
updateVisibility()

local function toggleMain(requested)
	local inRound = player:GetAttribute("InRound") == true
	if inRound and not devAllowed then return end
	local visible = if typeof(requested) == "boolean" then requested else not main.Visible
	if visible and modalBlocksStore() then
		setMainVisible(false)
		return
	end
	if visible and inRound and devAllowed then selectTab("Dev") end
	setMainVisible(visible)
	if main.Visible then showStatus("") end
end

-- Lobby supply kiosks use the same Equipment dashboard instead of creating a
-- second store interface. Prompts are bound dynamically because the server
-- builder can replace the concourse after this LocalScript starts.
local boundShopPrompts = setmetatable({}, { __mode = "k" })

local function openKioskShop()
	if player:GetAttribute("InRound") == true or modalBlocksStore() then return end
	selectTab("Shop")
	setMainVisible(true)
	showStatus("")
end

-- Studio-only input seam for UIRegression. It exercises the exact production
-- toggle and kiosk paths without needing a whitelisted account or fake input.
if RunService:IsStudio() then
	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionZyntraStoreProbe"
	probe.OnInvoke = function(action)
		if action == "open" then
			toggleMain(true)
		elseif action == "kiosk" then
			openKioskShop()
		elseif action == "close" then
			setMainVisible(false)
		elseif action == "tabs" then
			-- The tab set is decided at build time by the developer whitelist, so
			-- a matrix that hard-codes it would silently stop covering DEV on a
			-- whitelisted account and silently DEMAND it on an ordinary one.
			return table.concat(tabNames, ",")
		elseif action == "cards" then
			-- One line per card, "page|card|action", in build order. This is the
			-- half a tree walk cannot supply: it says what the terminal was AUTHORED
			-- to hold, so a page that quietly built one card fewer fails instead of
			-- passing for want of anything to check. The names are addressable --
			-- content[page] -> FindFirstChild(card, true) -> FindFirstChild(action)
			-- -- and every action also carries the tag and the attributes above.
			return table.concat(contract.Cards, "\n")
		elseif action == "scrolls" then
			-- "page|scroll", so an overflow assertion can name the frame it is
			-- measuring rather than reporting on "a ScrollingFrame".
			return table.concat(contract.Scrolls, "\n")
		elseif action == "donations" then
			-- The tier keys, in the order the cards were built. ZyntraConfig's own
			-- Donations table is an unordered dictionary, so this is the only place
			-- the built order is stated.
			return table.concat(contract.Donations, ",")
		elseif action == "relayout" then
			applyTerminalLayout()
		elseif type(action) == "string" and action:sub(1, 4) == "tab:" then
			-- Through selectTab, the very function the tab buttons call. A matrix
			-- that set page.Visible itself would be testing its own reimplementation
			-- of tab switching rather than the production one.
			selectTab(action:sub(5))
			return currentTab
		end
		return main.Visible
	end
	probe.Parent = gui
end

local function bindShopPrompt(instance)
	if not instance:IsA("ProximityPrompt") or instance.Name ~= "ZyntraShopPrompt" or boundShopPrompts[instance] then
		return
	end
	boundShopPrompts[instance] = true
	instance.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer and triggeringPlayer ~= player then return end
		openKioskShop()
	end)
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	bindShopPrompt(descendant)
end
workspace.DescendantAdded:Connect(bindShopPrompt)

local devPhoneCommand
if devAllowed then
	local playerScripts = player:WaitForChild("PlayerScripts")
	devPhoneCommand = playerScripts:FindFirstChild("DevPhoneCommand")
	if not devPhoneCommand then
		devPhoneCommand = Instance.new("BindableEvent")
		devPhoneCommand.Name = "DevPhoneCommand"
		devPhoneCommand.Parent = playerScripts
	end
	if devPhoneCommand:IsA("BindableEvent") then
		devPhoneCommand.Event:Connect(toggleMain)
	else
		warn("[ZyntraStore] PlayerScripts.DevPhoneCommand must be a BindableEvent")
		devPhoneCommand = nil
	end
end

openButton.Activated:Connect(function()
	toggleMain()
end)
closeButton.Activated:Connect(function() setMainVisible(false) end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.J and devAllowed then
		if devPhoneCommand then devPhoneCommand:Fire() else toggleMain() end
	elseif input.KeyCode == Enum.KeyCode.Escape and main.Visible then
		setMainVisible(false)
	end
end)

local function bindPhoneAutoClose(character)
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		humanoid.Died:Connect(function()
			setMainVisible(false)
		end)
	end)
end
player.CharacterAdded:Connect(bindPhoneAutoClose)
if player.Character then bindPhoneAutoClose(player.Character) end
player:GetAttributeChangedSignal("Escaped"):Connect(function()
	if player:GetAttribute("Escaped") == true then setMainVisible(false) end
end)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") ~= true and player:GetAttribute("InRound") == true then
		setMainVisible(false)
	end
end)

-- ── the one place the terminal's geometry is decided ────────────────────────
-- Measured against UIDevice's ModalViewport -- the whole true safe area --
-- because this is a MODAL and the movement cluster stands down underneath it
-- (setMainVisible publishes ZyntraStoreOpen, which NoiseReporter and
-- FlashlightController already honour, and calls UIDevice.SuppressTouchMovement
-- for the engine's own thumbstick). It is emphatically NOT measured against
-- SafeBottom - SafeTop: on touch that is the HUD band, roughly 117 logical
-- pixels on the reference device, which is what collapsed this panel.
--
-- Every rectangle below is an OFFSET, and the panel's own origin is computed
-- rather than expressed as a 0.5 scale, so the geometry a regression measures
-- at a simulated viewport is the geometry a player gets at the real one.
local STORE_DESIGN_WIDTH, STORE_DESIGN_HEIGHT = 840, 610
-- Nothing may resolve to zero or negative. These are the smallest rectangles
-- the composition is still a composition at; below them the panel takes the
-- whole modal viewport and the pages scroll.
local MIN_CONTENT_HEIGHT = 96
local MIN_TERMINAL_WIDTH = 260

function applyTerminalLayout()
	local layout = UIDevice.Layout()
	local area = layout.ModalViewport
	local touch = layout.IsTouch
	-- No UIScale, ever. Shrinking 11px type below 9px to make a fixed
	-- composition fit is not a layout; it is an unreadable one.
	mainScale.Scale = 1

	local width = math.floor(math.clamp(
		math.min(STORE_DESIGN_WIDTH, area.Width), MIN_TERMINAL_WIDTH, STORE_DESIGN_WIDTH))
	local height = math.floor(math.min(STORE_DESIGN_HEIGHT, area.Height))
	local compact = width < 640 or height < 430

	local tap = touch and TOUCH_MIN_TAP_HEIGHT or 32
	local pad = compact and 12 or 20
	local tabHeight = math.max(tap, compact and 40 or 42)
	local statusHeight = compact and 22 or 30
	local gap = compact and 8 or 12

	-- THE HEADER COMPOSITION IS DECIDED FIRST, because it can change the header's
	-- HEIGHT and the give-way ladder below sizes the panel against that height.
	-- "ZYNTRA // RESEARCH" needs about 200px at the compact face and a 375x667
	-- portrait phone leaves a one-row header 175, so the terminal's own name was
	-- being ellipsized. Measured, not assumed: one row while the name genuinely
	-- fits beside the token readout, and a deliberate two-row header when it
	-- does not -- name on its own line, token readout beneath it. The name is
	-- never abbreviated and never truncated.
	local closeSize = math.max(tap, 36)
	local closeLeft = width - closeSize - 10
	local titleLeft = compact and 16 or 24
	local titleFace = compact and 18 or 24
	local tokenFace = compact and 14 or 18
	local tokenWidth = math.max(80, math.min(190, math.floor(width * .24)))
	local titleNeeds = textWidthFor(title.Text, titleFace, title.Font)
	local oneRowTitleWidth = closeLeft - 10 - tokenWidth - titleLeft - 12
	-- TEXT_FIT_SLACK, for the same reason the Colors heading carries it: the
	-- one-row branch draws this name UNWRAPPED, so a name that clears its room by
	-- a pixel is a name that can still be reported -- and seen -- running into the
	-- token readout beside it.
	local stackHeader = titleNeeds + TEXT_FIT_SLACK > oneRowTitleWidth
	local headerHeight = compact and 54 or 70
	if stackHeader then headerHeight = math.max(headerHeight, 58) end

	-- One ordered give-way ladder, so a short screen loses ornament before it
	-- loses structure. Each step is only taken if the step before it left the
	-- content area under its floor.
	local function contentHeight()
		return height - headerHeight - gap - tabHeight - gap - statusHeight - gap
	end
	local showSubtitle = not compact
	if stackHeader and showSubtitle then headerHeight = math.max(headerHeight, 76) end
	if contentHeight() < MIN_CONTENT_HEIGHT then
		showSubtitle = false
		headerHeight = stackHeader and 58 or math.max(44, tap)
	end
	if contentHeight() < MIN_CONTENT_HEIGHT then statusHeight = 18 end
	if contentHeight() < MIN_CONTENT_HEIGHT then
		-- Last resort: take the height back from the panel's own margins by
		-- growing into whatever the modal viewport still has.
		height = math.floor(math.min(area.Height,
			headerHeight + gap + tabHeight + gap + statusHeight + gap + MIN_CONTENT_HEIGHT))
	end

	main.Size = UDim2.fromOffset(width, height)
	main.AnchorPoint = Vector2.new(0, 0)
	main.Position = UIDevice.LocalPosition(gui,
		math.floor(area.Left + (area.Width - width) / 2),
		math.floor(area.Top + (area.Height - height) / 2))

	-- The header is laid out RIGHT TO LEFT -- close, then the token readout,
	-- then whatever is left for the title -- rather than each child taking a
	-- guess at `width - <constant>`. The authored version did guess, and the
	-- guesses disagreed: a `width - 220` title and a right-anchored 190px token
	-- readout overlap by 58px on an 814-wide panel. Nothing here can overlap
	-- now, because each element's edge is derived from the one outside it.
	closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	closeButton.TextSize = compact and 21 or 25

	if stackHeader then
		title.Position = UDim2.fromOffset(titleLeft, 6)
		title.Size = UDim2.fromOffset(
			math.max(60, closeLeft - 10 - titleLeft), titleFace + 8)
		tokenLabel.Size = UDim2.fromOffset(
			math.max(80, closeLeft - 10 - titleLeft), 22)
		tokenLabel.Position = UDim2.fromOffset(titleLeft,
			6 + titleFace + 8 + (showSubtitle and 20 or 2))
		headerSubtitle.Visible = showSubtitle
		headerSubtitle.Size = UDim2.fromOffset(
			math.max(60, closeLeft - 10 - titleLeft), 18)
		headerSubtitle.Position = UDim2.fromOffset(titleLeft + 1, 6 + titleFace + 8)
	else
		local tokenLeft = closeLeft - 10 - tokenWidth
		tokenLabel.Size = UDim2.fromOffset(tokenWidth, 30)
		tokenLabel.Position = UDim2.fromOffset(tokenLeft,
			math.max(2, math.floor((headerHeight - 30) / 2)))
		title.Size = UDim2.fromOffset(math.max(60, oneRowTitleWidth),
			showSubtitle and 30 or headerHeight - 12)
		title.Position = UDim2.fromOffset(titleLeft, showSubtitle and 10 or 6)
		headerSubtitle.Visible = showSubtitle
		headerSubtitle.Size = UDim2.fromOffset(math.max(60, oneRowTitleWidth), 20)
		headerSubtitle.Position = UDim2.fromOffset(titleLeft + 1, 40)
	end
	title.TextSize = titleFace
	tokenLabel.TextSize = tokenFace
	tokenLabel.TextXAlignment = stackHeader
		and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	-- CLAMPED INSIDE THE HEADER, not floored at 4. The give-way ladder above can
	-- take the header down to max(44, tap), and on touch that IS this control's
	-- height -- so a 4px floor draws the one control that closes the modal 4px
	-- below the band it belongs to. Reaching that rung needs a modal viewport
	-- shorter than any device in the matrix, so this is latent rather than
	-- shipped; it is fixed because the rule the terminal now publishes -- the
	-- close control is drawn, Active and whole -- has to hold at the bottom of
	-- the ladder too, not only where a real device happens to land.
	closeButton.Position = UDim2.new(1, -(closeSize + 10), 0,
		math.clamp(math.floor((math.min(headerHeight, 70) - closeSize) / 2),
			0, math.max(0, headerHeight - closeSize)))
	main:SetAttribute("TerminalHeaderStacked", stackHeader)

	-- headerHeight may have GROWN for a two-row header, so everything below is
	-- measured from the value the composition actually used.
	local contentWidth = width - pad * 2
	tabBar.Position = UDim2.fromOffset(pad, headerHeight + gap)
	tabBar.Size = UDim2.fromOffset(contentWidth, tabHeight)
	local contentTop = headerHeight + gap + tabHeight + gap
	local available = height - contentTop - statusHeight - gap
	content.Position = UDim2.fromOffset(pad, contentTop)
	content.Size = UDim2.fromOffset(contentWidth, math.max(1, available))

	statusLabel.Size = UDim2.fromOffset(contentWidth, statusHeight)
	statusLabel.Position = UDim2.fromOffset(pad, height - statusHeight - math.floor(gap / 2))
	statusLabel.TextSize = compact and 12 or 14

	local fit = {
		Width = width,
		Height = height,
		ContentWidth = contentWidth,
		ContentHeight = math.max(1, available),
		Compact = compact,
		Touch = touch,
		Tap = tap,
		TabHeight = tabHeight,
		TabMinWidth = compact and 88 or 110,
		-- The DEV row stacks whenever the side-by-side label column would be
		-- narrower than DEV_COPY_MIN_WIDTH. 380 was measured against the
		-- CONTROL, not the copy, so a 392px content box stayed side-by-side with
		-- a 192px label column and truncated every description in it. 460 is
		-- 240 of readable copy plus a 110px control plus the paddings.
		DevStacked = contentWidth < 460,
	}
	for _, hook in ipairs(layoutHooks) do
		local ok, err = pcall(hook, fit)
		if not ok then warn("[ZyntraStore] layout hook failed: " .. tostring(err)) end
	end

	-- Published so a regression can assert the CHOICES and not merely the
	-- pixels: which give-way rung this viewport landed on, and the viewport it
	-- was measured against.
	main:SetAttribute("TerminalCompact", compact)
	-- The floor every card action on every page was sized against this pass, so a
	-- matrix can assert the rectangles against the terminal's OWN number instead
	-- of restating 44 and agreeing with itself.
	main:SetAttribute("TerminalTapFloor", tap)
	main:SetAttribute("TerminalSubtitleShown", showSubtitle)
	main:SetAttribute("TerminalModalWidth", area.Width)
	main:SetAttribute("TerminalModalHeight", area.Height)
	main:SetAttribute("TerminalContentHeight", math.max(1, available))
end

UIDevice.Changed:Connect(function()
	applyTerminalLayout()
	updateVisibility()
	-- The dev-page captions drop their key names on a touch form factor, so
	-- a form-factor change has to rebuild every row, not just resize the
	-- panel. Each row registered a refresh when it was built.
	for _, refresh in ipairs(deviceCaptionRefreshers) do
		local ok, err = pcall(refresh)
		if not ok then warn("[ZyntraStore] caption refresh failed: " .. tostring(err)) end
	end
end)
applyTerminalLayout()

