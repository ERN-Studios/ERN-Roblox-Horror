-- Daily Rewards Client -- the standalone DAILY REWARDS modal. (Trello #104)
--
-- WHAT THIS FILE IS: a shell. It draws a shade, a panel, the warm header bar
-- (the gift, "DAILY REWARDS" and the big red X), a status line, and then hands
-- the content frame to ReplicatedStorage.ZyntraDailyRewardsPage -- the SAME
-- module the Zyntra terminal used to mount as its REWARDS tab, with the same
-- `mount(page, ctx)` contract. Nothing about daily rewards is decided here. The
-- playtime counters, the milestone claims and every number on them come out of
-- the public profile the server already committed; this file only owns when the
-- modal is up and what `ctx` the page is handed.
--
-- WHY THE HEADER IS WARM AND THE REST IS NOT (2026-09-16). Every other surface
-- in this game is the dark teal Zyntra chrome, because every other surface is
-- either a warning or a shop. This one gives something away, so the owner asked
-- for a header that says so: an orange ramp, the gift, and an X nobody has to
-- hunt for. The old eyebrow "ZYNTRA // DAILY SUPPLY" is gone with it -- the
-- fiction was naming a supply depot on the screen that hands out free rewards.
--
-- WHY A MODAL OF ITS OWN (card #104). Daily Rewards was a tab inside the shop
-- terminal, which meant reaching it was: open the terminal, find the tab, and
-- share a panel with seven other pages. It now has a rail button of its own
-- (A-RAIL's `ZyntraRewardsButton`) and this modal, and the terminal's Rewards
-- tab is gone -- so there is exactly ONE Daily Rewards surface in the game.
-- Two would be two claim buttons for the same milestone.
--
-- THE MOUNT HAPPENS ONCE, at build time, and the handle is kept for the life of
-- the session. Opening calls `handle.refresh()`; closing does NOT destroy it.
-- A mount per open would rebuild ~30 instances every time, re-register a layout
-- hook that the shell never drops, and leak a profile subscription per open --
-- and a page whose 1 Hz ticker is running in three copies draws three
-- countdowns that disagree. `isVisible()` is what tells the page it is off
-- screen; the page already stops redrawing on that.
--
-- THE MODAL RULES are the ones in artifacts/trello-20260916-followup/
-- claude-contracts.md, and they are shared with the Lucky Wheel client:
--   * lobby only -- refused while `InRound`, while any OTHER screen-owning
--     modal is up, and while the queue host panel is open;
--   * closed by CLOSE, Escape, gamepad ButtonB, `InRound` -> true,
--     `RoundActive` -> true and `QueueModalOpen` -> true;
--   * publishes `DailyRewardsOpen` on the LocalPlayer while it is drawn, and
--     calls `UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())`
--     after EVERY open and close -- derived from the complete published modal
--     set, never from "this one just closed", or closing this modal would
--     re-enable Roblox's dynamic thumbstick underneath a queue panel that is
--     still up. That is exactly what ZyntraStore.setMainVisible does.
--
-- WHAT IS NOT VERIFIABLE OFFLINE: the real thumbstick suppression, real touch,
-- font metrics and TextBounds, and whether the panel reads well. Studio
-- captures on a phone (portrait and landscape), a tablet and a desktop are the
-- proof for those.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("ZyntraAction")
local getProfileRemote = remotes:WaitForChild("ZyntraGetProfile")
local profileChangedRemote = remotes:WaitForChild("ZyntraProfileChanged")
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")

-- The page is authored for a single readable column, so the panel is sized to
-- ONE column plus its margins rather than to the terminal's 1180 -- a milestone
-- card stretched across a 1140px content box is a 1100px-wide CLAIM button.
local DESIGN_WIDTH, DESIGN_HEIGHT = 720, 640
local MIN_WIDTH = 260
local MIN_CONTENT_HEIGHT = 96
-- The module ships with the place. 30 s is long enough that a slow replication
-- pass is not mistaken for a missing script, and short enough that a place
-- which genuinely lacks it says so rather than hanging a rail button forever.
local MODULE_WAIT = 30
local CLOSE_ACTION = "DailyRewardsClose"

-- ZyntraStore's palette, copied by VALUE. The page takes its two accents from
-- ctx.COLORS, so a modal with a different palette would draw a differently
-- coloured DAILY REWARDS depending on which host opened it. Copied rather than
-- required because ZyntraStore is a LocalScript, not a module -- there is
-- nothing to require -- and these eight values have not moved since #88.
local COLORS = {
	bg = Color3.fromRGB(7, 11, 13),
	panel = Color3.fromRGB(14, 21, 24),
	card = Color3.fromRGB(20, 29, 33),
	card2 = Color3.fromRGB(25, 36, 40),
	line = Color3.fromRGB(75, 94, 83),
	text = Color3.fromRGB(231, 238, 233),
	muted = Color3.fromRGB(144, 164, 165),
	accent = Color3.fromRGB(68, 221, 196),
	accent2 = Color3.fromRGB(255, 203, 79),
	error = Color3.fromRGB(244, 95, 82),
}

-- ── the terminal's four helpers, locally ────────────────────────────────────
-- The page contract hands these to the page, and the page builds every label
-- and button on itself through them. They are ZyntraStore's, property for
-- property, so a page mounted here is drawn exactly as it was in the terminal.

local function corner(parent, radius)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius or 9)
	object.Parent = parent
	return object
end

local function outline(parent, color, transparency, thickness)
	local object = Instance.new("UIStroke")
	object.Color = color or COLORS.line
	object.Transparency = transparency or 0.28
	object.Thickness = thickness or 1
	object.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	object.Parent = parent
	return object
end

local function label(parent, text, size, position, textSize, color, font)
	local object = Instance.new("TextLabel")
	object.BackgroundTransparency = 1
	object.Size = size
	object.Position = position or UDim2.new()
	object.Font = font or Enum.Font.GothamMedium
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

-- ── the shell ───────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "DailyRewardsGui"
gui.ResetOnSpawn = false
-- 117, between the Level 1 guide (110) and the Lucky Wheel (118): both new
-- modals draw over every HUD surface, and the wheel draws over this one because
-- a spin opened from here would otherwise land behind it.
gui.DisplayOrder = 117
-- The shade is `fromScale(1, 1)` and has to mean THE SAFE AREA, not the display
-- -- a notch or a home indicator over a full-screen Active frame is a strip of
-- shade nobody can dismiss and a control the player cannot reach.
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Active, so a tap that misses the panel cannot reach the movement controls or
-- a world prompt behind it. It does NOT close the modal: a mis-tap on a phone
-- would throw away a card the player is reading.
local shade = Instance.new("Frame")
shade.Name = "DailyRewardsShade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 0.5
shade.BorderSizePixel = 0
shade.Active = true
shade.Visible = false
shade.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "DailyRewardsPanel"
panel.Parent = shade
UIStyle.panel(panel, {
	Background = COLORS.bg,
	Transparency = UIStyle.Transparency.Card,
	Radius = UIStyle.Radius.Card,
	StrokeTransparency = UIStyle.Stroke.CardTransparency,
})

-- ── the warm header ─────────────────────────────────────────────────────────
-- The one piece of this modal that is not the game's dark teal chrome, and
-- deliberately so: this is the screen a player opens to be GIVEN something.
-- The bar is WHITE underneath because a UIGradient multiplies BackgroundColor3
-- rather than replacing it -- over the old dark panel colour the warm ramp
-- would render as a slightly-less-dark bar.
local headerBar = Instance.new("Frame")
headerBar.Name = "RewardsHeader"
headerBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
headerBar.BackgroundTransparency = 0
headerBar.BorderSizePixel = 0
headerBar.Parent = panel
corner(headerBar, 10)

local headerGradient = Instance.new("UIGradient")
headerGradient.Name = "HeaderGradient"
headerGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 60)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 40)),
})
headerGradient.Rotation = 90
headerGradient.Parent = headerBar

-- Codex's uploaded art. Fit, never stretched: the PNG carries its own air.
local headerGift = Instance.new("ImageLabel")
headerGift.Name = "HeaderGift"
headerGift.Image = "rbxassetid://117126194981100"
headerGift.ScaleType = Enum.ScaleType.Fit
headerGift.BackgroundTransparency = 1
headerGift.BorderSizePixel = 0
headerGift.Parent = headerBar

local title = label(headerBar, "DAILY REWARDS", UDim2.new(), UDim2.new(),
	26, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBlack)
title.Name = "HeaderTitle"
do
	-- Contextual (the default) outlines the TEXT, which is what white copy over
	-- an orange ramp needs. UIStyle's helpers force Border, so this is its own
	-- four lines rather than a call.
	local titleShadow = Instance.new("UIStroke")
	titleShadow.Color = Color3.fromRGB(120, 55, 10)
	titleShadow.Thickness = 2
	titleShadow.Transparency = 0.15
	titleShadow.Parent = title
end

-- Built by hand rather than through button(): that helper paints the dark
-- terminal chrome and wires a MouseLeave that would put it back over the red.
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AutoButtonColor = false
closeButton.BackgroundColor3 = Color3.fromRGB(190, 60, 50)
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.GothamBlack
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 24
closeButton.TextXAlignment = Enum.TextXAlignment.Center
closeButton.Parent = headerBar
corner(closeButton, 9)
outline(closeButton, Color3.fromRGB(255, 220, 200), 0.45, 2)
-- The shared hover, so a hand-built control still answers a pointer the way
-- every other button in the game does.
UIStyle.hover(closeButton, Color3.fromRGB(190, 60, 50), Color3.fromRGB(222, 82, 68))

local content = Instance.new("Frame")
content.Name = "PageContent"
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ClipsDescendants = true
content.Parent = panel

local statusLabel = label(panel, "", UDim2.new(), UDim2.new(), 13, COLORS.muted,
	UIStyle.Font.Body)
statusLabel.Name = "StatusLine"

local function showStatus(message, tone)
	statusLabel.Text = message or ""
	statusLabel.TextColor3 = tone == "error" and COLORS.error
		or tone == "success" and COLORS.accent
		or COLORS.muted
end

-- ── the profile, exactly as ProtectionClient reads it ───────────────────────
-- ONE InvokeServer at start, pushes after. The serial is bumped by every push,
-- so an answer that was already in flight when a newer push landed is dropped
-- rather than overwriting the newer state with the older read.
local profile = nil
local profileSubscribers = {}
local profileSerial = 0
local refreshing = false

local function publishProfile(message, tone)
	for _, fn in ipairs(table.clone(profileSubscribers)) do
		local ok, err = pcall(fn, profile, message, tone)
		if not ok then warn("[DailyRewards] profile listener failed: " .. tostring(err)) end
	end
end

local function refreshProfile()
	if refreshing then return end
	refreshing = true
	local serial = profileSerial
	task.spawn(function()
		local ok, answer = pcall(getProfileRemote.InvokeServer, getProfileRemote)
		refreshing = false
		if ok and answer and serial == profileSerial then
			profile = answer
			publishProfile(nil, nil)
		elseif not ok and profile == nil then
			showStatus("Could not load the Zyntra profile.", "error")
		end
	end)
end

profileChangedRemote.OnClientEvent:Connect(function(newProfile, message, tone)
	if newProfile then profile = newProfile end
	profileSerial += 1
	publishProfile(message, tone)
	if message and message ~= "" then showStatus(message, tone) end
end)

-- ── layout ──────────────────────────────────────────────────────────────────
local layoutHooks = {}
local lastFit = nil

local function applyLayout()
	local area = UIDevice.Layout().ModalViewport
	local touch = UIDevice.Layout().IsTouch
	-- Measured against ModalViewport, never the HUD band: this modal takes the
	-- screen, so the movement cluster stands down underneath it and there is
	-- nothing left to dodge. Sizing a screen-owning modal from the HUD band is
	-- what collapsed the terminal before #98.
	local width = math.floor(math.clamp(
		math.min(DESIGN_WIDTH, area.Width), MIN_WIDTH, DESIGN_WIDTH))
	local height = math.floor(math.min(DESIGN_HEIGHT, area.Height))
	local compact = width < 640 or height < 430
	local tap = touch and 44 or 32
	local pad = compact and 12 or 20
	local gap = compact and 8 or 12
	local statusHeight = compact and 22 or 30
	-- The X NEVER gives way. It is the one control on a screen-owning modal a
	-- player must be able to hit, so 48 is a floor on a pointer as much as under
	-- a thumb, and the header bar is measured around it rather than the reverse.
	local closeSize = math.max(48, tap)
	local headerMargin = 8
	local titleFace = compact and 22 or 26
	local barHeight = math.max(closeSize + 8, compact and 56 or 64)
	local headerHeight = barHeight + headerMargin

	local function contentHeight()
		return height - headerHeight - gap - statusHeight - gap
	end
	-- The give-way ladder, cheapest rung first: the header's spare air, then the
	-- status line, then the panel's own margins.
	if contentHeight() < MIN_CONTENT_HEIGHT then
		barHeight = closeSize + 8
		headerHeight = barHeight + headerMargin
	end
	if contentHeight() < MIN_CONTENT_HEIGHT then statusHeight = 18 end
	if contentHeight() < MIN_CONTENT_HEIGHT then
		-- Last resort: take the height back from the panel's own margins by
		-- growing into whatever the modal viewport still has. The panel may end
		-- up the whole viewport; it may never end up shorter than its content.
		height = math.floor(math.min(area.Height,
			headerHeight + gap + statusHeight + gap + MIN_CONTENT_HEIGHT))
	end

	panel.Size = UDim2.fromOffset(width, height)
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UIDevice.LocalPosition(gui,
		math.floor(area.Left + (area.Width - width) / 2),
		math.floor(area.Top + (area.Height - height) / 2))

	-- The bar, then RIGHT TO LEFT inside it: gift, close, and whatever is left
	-- for the title. The title can never run under the one control that
	-- dismisses the modal, and the gift can never push it there.
	local barWidth = math.max(120, width - headerMargin * 2)
	headerBar.Position = UDim2.fromOffset(headerMargin, headerMargin)
	headerBar.Size = UDim2.fromOffset(barWidth, barHeight)

	local giftSize = math.max(32, barHeight - 10)
	headerGift.Position = UDim2.fromOffset(6, math.floor((barHeight - giftSize) / 2))
	headerGift.Size = UDim2.fromOffset(giftSize, giftSize)

	local closeLeft = barWidth - closeSize - 6
	closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	closeButton.Position = UDim2.fromOffset(closeLeft,
		math.max(0, math.floor((barHeight - closeSize) / 2)))
	closeButton.TextSize = compact and 22 or 24

	local titleLeft = 6 + giftSize + 8
	title.Position = UDim2.fromOffset(titleLeft, 0)
	title.Size = UDim2.fromOffset(math.max(60, closeLeft - 8 - titleLeft), barHeight)
	title.TextSize = titleFace

	local contentWidth = width - pad * 2
	local available = math.max(1, contentHeight())
	content.Position = UDim2.fromOffset(pad, headerHeight + gap)
	content.Size = UDim2.fromOffset(contentWidth, available)

	statusLabel.Position = UDim2.fromOffset(pad, height - statusHeight - math.floor(gap / 2))
	statusLabel.Size = UDim2.fromOffset(contentWidth, statusHeight)
	statusLabel.TextSize = compact and 12 or 14

	-- The fit table the page contract names. TabHeight and TabMinWidth describe
	-- a tab bar this modal does not have; they are published anyway, at the
	-- terminal's own values, because the contract says a `fit` carries them and
	-- a page that reads one must not have to know which host built it.
	lastFit = {
		Width = width,
		Height = height,
		ContentWidth = contentWidth,
		ContentHeight = available,
		Compact = compact,
		Touch = touch,
		Tap = tap,
		TabHeight = math.max(tap, compact and 40 or 42),
		TabMinWidth = compact and 88 or 110,
	}
	for _, hook in ipairs(layoutHooks) do
		local ok, err = pcall(hook, lastFit)
		if not ok then warn("[DailyRewards] layout hook failed: " .. tostring(err)) end
	end

	-- Published so a regression can assert the CHOICES and not merely the
	-- pixels, the way the terminal publishes its own.
	panel:SetAttribute("DailyRewardsCompact", compact)
	panel:SetAttribute("DailyRewardsTapFloor", tap)
	panel:SetAttribute("DailyRewardsContentHeight", available)
	panel:SetAttribute("DailyRewardsModalWidth", area.Width)
	panel:SetAttribute("DailyRewardsModalHeight", area.Height)
end

-- ── the page ────────────────────────────────────────────────────────────────
-- What the page was told to build, so the Studio probe can report the tree this
-- modal was AUTHORED to hold. Not CollectionService-tagged: the terminal's own
-- tag drives UIRegression's fit matrix, which measures every tagged control on
-- screen, and these are behind a modal that is closed almost all of the time.
local contractCards = {}
local contractScrolls = {}
local pageHandle = nil

local function isVisible(): boolean
	return shade.Visible == true
end

local pageContext = {
	player = player,
	Config = Config,
	UIStyle = UIStyle,
	UIDevice = UIDevice,
	COLORS = COLORS,
	label = label,
	button = button,
	corner = corner,
	outline = outline,
	action = function(name, payload) actionRemote:FireServer(name, payload) end,
	profile = function() return profile end,
	onProfile = function(fn)
		table.insert(profileSubscribers, fn)
		return function()
			for index, entry in ipairs(profileSubscribers) do
				if entry == fn then
					table.remove(profileSubscribers, index)
					break
				end
			end
		end
	end,
	refreshProfile = refreshProfile,
	showStatus = showStatus,
	registerLayoutHook = function(fn)
		table.insert(layoutHooks, fn)
		-- The shell lays itself out at boot and the mount can finish AFTER that
		-- pass, so a hook that registers late is handed the fit immediately.
		-- Without this the page would hold its build-time rectangles until the
		-- first device rotation.
		if lastFit then
			local ok, err = pcall(fn, lastFit)
			if not ok then warn("[DailyRewards] layout hook failed: " .. tostring(err)) end
		end
	end,
	isVisible = isVisible,
	contract = {
		scroll = function(pageName, frame)
			frame.ScrollingEnabled = true
			frame:SetAttribute("ZyntraPage", pageName)
			table.insert(contractScrolls, tostring(pageName) .. "|" .. frame.Name)
			return frame
		end,
		card = function(pageName, key, card, action)
			card:SetAttribute("ZyntraPage", pageName)
			card:SetAttribute("ZyntraCardKey", key)
			action:SetAttribute("ZyntraPage", pageName)
			action:SetAttribute("ZyntraCardKey", key)
			table.insert(contractCards,
				tostring(pageName) .. "|" .. tostring(key) .. "|" .. action.Name)
			return action
		end,
	},
	pageName = "Rewards",
}

-- ONE mount, in a spawned thread so a place without the module still gets a
-- working shell (and a working CLOSE) rather than a rail button whose modal
-- never appears. A MOUNT THAT THROWS IS A WARNING, never a dead modal.
task.spawn(function()
	local moduleScript = ReplicatedStorage:WaitForChild("ZyntraDailyRewardsPage", MODULE_WAIT)
	if not moduleScript then
		local missing = label(content, "DAILY REWARDS UNAVAILABLE",
			UDim2.fromScale(1, 0), UDim2.fromOffset(0, 8), 15, COLORS.error,
			UIStyle.Font.Readout)
		missing.Name = "PageUnavailable"
		missing.Size = UDim2.new(1, 0, 0, 24)
		warn("[DailyRewards] ZyntraDailyRewardsPage is not in ReplicatedStorage")
		return
	end
	local ok, result = pcall(function()
		return require(moduleScript).mount(content, pageContext)
	end)
	if ok and type(result) == "table" then
		pageHandle = result
	else
		warn("[DailyRewards] ZyntraDailyRewardsPage failed to mount: " .. tostring(result))
	end
end)

-- ── opening and closing ─────────────────────────────────────────────────────
-- LOBBY ONLY, and the three refusals are separate facts: a player in a round
-- has no business here, another screen-owning modal already owns the screen,
-- and the queue host panel is mid-configuration. `RoundActive` deliberately
-- CLOSES without refusing -- a lobby player on a server where somebody else's
-- round is running is not in that round, and `InRound` is the fact that says so.
local function canOpen(): boolean
	return player:GetAttribute("InRound") ~= true
		and player:GetAttribute("QueueModalOpen") ~= true
		and not UIDevice.ScreenOwningModalOpen()
end

-- ONE place writes the visibility, the attribute and the suppression, so the
-- three can never disagree. The attribute is written BEFORE the suppression is
-- read, because UIDevice derives the request from the complete published modal
-- set and this modal is part of that set.
local function publishOpen(open: boolean)
	shade.Visible = open
	player:SetAttribute("DailyRewardsOpen", open or nil)
	UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
end

local function close()
	if not shade.Visible then return end
	publishOpen(false)
	ContextActionService:UnbindAction(CLOSE_ACTION)
	if GuiService.SelectedObject == closeButton then GuiService.SelectedObject = nil end
end

local function open()
	if shade.Visible then return end
	if not canOpen() then return end
	showStatus("", nil)
	publishOpen(true)
	-- Refresh BOTH ways round: the handle re-renders from the profile this
	-- client already holds, so the modal is never blank while the server
	-- answers, and the re-read replaces it with whatever has changed since.
	if pageHandle then pcall(pageHandle.refresh) end
	refreshProfile()
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState)
		if not shade.Visible or GuiService.MenuIsOpen then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then close() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
	if UIDevice.LastInput() == "Gamepad" then GuiService.SelectedObject = closeButton end
end

do
	-- Created by whoever finds it missing, on either side: this file and the
	-- rail button that fires it load in an order neither of them controls.
	local opener = playerScripts:FindFirstChild("OpenDailyRewards")
	if not opener then
		opener = Instance.new("BindableEvent")
		opener.Name = "OpenDailyRewards"
		opener.Parent = playerScripts
	end
	-- Wrapped: Event passes whatever the firer sent, and open() takes nothing.
	opener.Event:Connect(function() open() end)
end

closeButton.Activated:Connect(close)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and shade.Visible then close() end
end)

for _, attribute in ipairs({"InRound", "QueueModalOpen"}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if player:GetAttribute(attribute) == true then close() end
	end)
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") == true then close() end
end)
GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(function()
	if GuiService.MenuIsOpen then close() end
end)
-- AUDIT_FIX_20260924: a pad picked up while the modal is already open takes
-- focus too, the way the terminal does -- open() only focuses a pad it sees.
UserInputService.LastInputTypeChanged:Connect(function()
	if shade.Visible and GuiService.SelectedObject == nil and not GuiService.MenuIsOpen
		and UIDevice.LastInput() == "Gamepad" then
		GuiService.SelectedObject = closeButton
	end
end)

UIDevice.Changed:Connect(applyLayout)

-- Studio-only input seam for UIRegression. It drives the EXACT production open
-- and close paths -- including the refusals -- so a matrix that opens the modal
-- through it is measuring what a player would get.
if RunService:IsStudio() then
	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionDailyRewardsProbe"
	probe.OnInvoke = function(action)
		if action == "open" then
			open()
		elseif action == "close" then
			close()
		elseif action == "state" then
			return shade.Visible
		elseif action == "cards" then
			-- "page|card|action", in build order. This is the half a tree walk
			-- cannot supply: it says what the page was AUTHORED to hold, so a
			-- page that quietly built one card fewer fails instead of passing
			-- for want of anything to check.
			return table.concat(contractCards, "\n")
		elseif action == "scrolls" then
			return table.concat(contractScrolls, "\n")
		end
		return nil
	end
	probe.Parent = gui
end

applyLayout()
refreshProfile()
