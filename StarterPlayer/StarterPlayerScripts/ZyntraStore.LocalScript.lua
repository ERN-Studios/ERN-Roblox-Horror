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

local main = Instance.new("Frame")
main.Name = "Terminal"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.5)
main.Size = UDim2.fromOffset(840, 610)
main.BackgroundColor3 = COLORS.bg
main.BorderSizePixel = 0
main.Visible = false
main.Parent = gui
corner(main, 12)
outline(main, COLORS.accent, 0.3, 1.5)
local mainScale = Instance.new("UIScale")
mainScale.Parent = main

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 70)
header.BackgroundColor3 = COLORS.panel
header.BorderSizePixel = 0
header.Parent = main
corner(header, 12)

local title = label(header, "ZYNTRA", UDim2.new(0, 260, 0, 30), UDim2.fromOffset(24, 10), 24, COLORS.accent, Enum.Font.GothamBlack)
title.Text = "ZYNTRA // RESEARCH"
label(header, "EQUIPMENT DEVELOPMENT TERMINAL", UDim2.new(0, 420, 0, 20), UDim2.fromOffset(25, 40), 11, COLORS.muted, Enum.Font.Code)

local tokenLabel = label(header, "TOKENS  --", UDim2.fromOffset(190, 34), UDim2.new(1, -250, 0, 18), 18, COLORS.accent2, Enum.Font.GothamBold)
tokenLabel.TextXAlignment = Enum.TextXAlignment.Right
local closeButton = button(header, "\u{00D7}", UDim2.fromOffset(42, 36), UDim2.new(1, -54, 0, 16))
closeButton.TextSize = 25

local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.fromOffset(20, 82)
tabBar.Size = UDim2.new(1, -40, 0, 42)
tabBar.BackgroundTransparency = 1
tabBar.Parent = main
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 10)
tabLayout.Parent = tabBar

local content = Instance.new("Frame")
content.Position = UDim2.fromOffset(20, 134)
content.Size = UDim2.new(1, -40, 1, -188)
content.BackgroundTransparency = 1
content.ClipsDescendants = true
content.Parent = main

local statusLabel = label(main, "", UDim2.new(1, -40, 0, 38), UDim2.new(0, 20, 1, -47), 14, COLORS.muted, Enum.Font.GothamMedium)
statusLabel.TextXAlignment = Enum.TextXAlignment.Center

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
for _, name in ipairs(tabNames) do
	local tab = button(tabBar, string.upper(name), UDim2.fromOffset(150, 40))
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

	local devLayout = Instance.new("UIListLayout")
	devLayout.Padding = UDim.new(0, 6)
	devLayout.SortOrder = Enum.SortOrder.LayoutOrder
	devLayout.Parent = devScroll
	local devPadding = Instance.new("UIPadding")
	devPadding.PaddingRight = UDim.new(0, 8)
	devPadding.Parent = devScroll

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

		label(
			row,
			info.Name,
			UDim2.new(1, -190, 0, 24),
			UDim2.fromOffset(14, 4),
			14,
			COLORS.text,
			Enum.Font.GothamBold
		)
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
		description.TextTruncate = Enum.TextTruncate.AtEnd
		if info.TouchDescription then
			-- A row whose copy names keys follows the LIVE input mode, exactly like
			-- the ON/OFF caption beside it. Registered with the shared refresher list
			-- so UIDevice.Changed rebuilds it; resolved once here so the row is right
			-- on the very first frame rather than one signal later.
			local function refreshDescription()
				description.Text = UIDevice.SuppressesKeyboardGlyphs()
					and info.TouchDescription
					or info.Description
			end
			refreshDescription()
			table.insert(deviceCaptionRefreshers, refreshDescription)
		end

		local toggle = button(row, "OFF", UDim2.fromOffset(158, 36), UDim2.new(1, -172, 0, 6))
		toggle.Name = "Toggle"
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
				toggle.Active = available
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
upgradeIntro.TextWrapped = true

local function makeUpgradeCard(parent, xScale, titleText, description)
	local card = Instance.new("Frame")
	card.Position = UDim2.new(xScale, xScale == 0 and 0 or 10, 0, 58)
	card.Size = UDim2.new(0.5, -10, 1, -68)
	card.BackgroundColor3 = COLORS.card
	card.BorderSizePixel = 0
	card.Parent = parent
	corner(card, 10)
	outline(card, COLORS.line, 0.35)

	label(card, titleText, UDim2.new(1, -36, 0, 34), UDim2.fromOffset(18, 18), 22, COLORS.text, Enum.Font.GothamBold)
	local desc = label(card, description, UDim2.new(1, -36, 0, 72), UDim2.fromOffset(18, 60), 14, COLORS.muted)
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	local current = label(card, "+0%", UDim2.new(1, -36, 0, 80), UDim2.fromOffset(18, 142), 44, COLORS.accent, Enum.Font.GothamBlack)
	local level = label(card, "LEVEL 0", UDim2.new(1, -36, 0, 24), UDim2.fromOffset(18, 220), 13, COLORS.muted, Enum.Font.Code)
	local spend = button(card, "SPEND 1 TOKEN  //  +5%", UDim2.new(1, -36, 0, 48), UDim2.new(0, 18, 1, -66))
	spend.BackgroundColor3 = Color3.fromRGB(21, 55, 53)
	outline(spend, COLORS.accent, 0.2, 1.5)
	return { Current = current, Level = level, Spend = spend }
end

local staminaCard = makeUpgradeCard(
	pages.Upgrades,
	0,
	"STAMINA CAPACITY",
	"Run for longer before exhaustion. Sprint speed and noise remain unchanged."
)
local batteryCard = makeUpgradeCard(
	pages.Upgrades,
	0.5,
	"BATTERY CAPACITY",
	"Keep the flashlight active for longer. Recharge speed remains unchanged."
)
staminaCard.Spend.Activated:Connect(function() actionRemote:FireServer("UpgradeStamina") end)
batteryCard.Spend.Activated:Connect(function() actionRemote:FireServer("UpgradeBattery") end)

local shopScroll = Instance.new("ScrollingFrame")
shopScroll.Size = UDim2.fromScale(1, 1)
shopScroll.BackgroundTransparency = 1
shopScroll.BorderSizePixel = 0
shopScroll.ScrollBarThickness = 5
shopScroll.ScrollBarImageColor3 = COLORS.accent
shopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopScroll.CanvasSize = UDim2.new()
shopScroll.Parent = pages.Shop

local shopGrid = Instance.new("UIGridLayout")
shopGrid.CellSize = UDim2.new(0.5, -8, 0, 220)
shopGrid.CellPadding = UDim2.fromOffset(12, 12)
shopGrid.SortOrder = Enum.SortOrder.LayoutOrder
shopGrid.Parent = shopScroll

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

	local headingY = kind == "Pass" and 28 or 16
	if kind == "Pass" then
		label(card, "PERMANENT PASS", UDim2.new(1, -118, 0, 18), UDim2.fromOffset(104, 10), 10, COLORS.accent, Enum.Font.Code)
	end
	local heading = label(card, item.Name, UDim2.new(1, -118, 0, 42), UDim2.fromOffset(104, headingY), 18, COLORS.text, Enum.Font.GothamBold)
	heading.TextWrapped = true
	local desc = label(card, item.Description or "", UDim2.new(1, -118, 0, 68), UDim2.fromOffset(104, 72), 12, COLORS.muted)
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	local buy = button(card, tostring(item.Price) .. " R$", UDim2.new(1, -28, 0, 38), UDim2.new(0, 14, 1, -50))
	buy.TextColor3 = COLORS.accent2
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
supportTotalLabel.TextXAlignment = Enum.TextXAlignment.Left

local supportScroll = Instance.new("ScrollingFrame")
supportScroll.Position = UDim2.fromOffset(0, 32)
supportScroll.Size = UDim2.new(1, 0, 1, -32)
supportScroll.BackgroundTransparency = 1
supportScroll.BorderSizePixel = 0
supportScroll.ScrollBarThickness = 5
supportScroll.ScrollBarImageColor3 = COLORS.accent
supportScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
supportScroll.CanvasSize = UDim2.new()
supportScroll.Parent = pages.Donate

local supportGrid = Instance.new("UIGridLayout")
supportGrid.CellSize = UDim2.new(0.5, -8, 0, 92)
supportGrid.CellPadding = UDim2.fromOffset(12, 10)
supportGrid.SortOrder = Enum.SortOrder.LayoutOrder
supportGrid.Parent = supportScroll

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
	heading.TextWrapped = true
	local productId = math.floor(tonumber(item.Id) or 0)
	local buy = button(card, tostring(item.Price) .. " R$  //  DONATE", UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 1, -44))
	buy.TextColor3 = COLORS.accent2
	productButtons[key] = buy
	displayedProductPrices[key] = math.max(0, math.floor(tonumber(item.Price) or 0))
	if productId <= 0 then
		buy.Text = "COMING SOON"
		buy.TextColor3 = COLORS.muted
		buy.Active = false
		buy.Selectable = false
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
end

local colorsScroll = Instance.new("ScrollingFrame")
colorsScroll.Size = UDim2.fromScale(1, 1)
colorsScroll.BackgroundTransparency = 1
colorsScroll.BorderSizePixel = 0
colorsScroll.ScrollBarThickness = 5
colorsScroll.ScrollBarImageColor3 = COLORS.accent
colorsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
colorsScroll.CanvasSize = UDim2.new()
colorsScroll.Parent = pages.Colors
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

	label(card, titleText, UDim2.new(1, -170, 0, 28), UDim2.fromOffset(16, 12), 18, COLORS.text, Enum.Font.GothamBold)
	local preview = Instance.new("Frame")
	preview.Position = UDim2.new(1, -148, 0, 12)
	preview.Size = UDim2.fromOffset(48, 28)
	preview.BackgroundColor3 = Color3.new(1, 1, 1)
	preview.BorderSizePixel = 0
	preview.Parent = card
	corner(preview, 6)
	outline(preview, Color3.new(1, 1, 1), 0.35)

	local save = button(card, "SAVE", UDim2.fromOffset(82, 30), UDim2.new(1, -92, 0, 11))
	save.TextColor3 = COLORS.accent

	local state = { H = 0, S = 0.5, V = 1, Action = actionName }
	local sliderObjects = {}

	local function makeSlider(row, name, minimum, maximum)
		label(card, name, UDim2.fromOffset(34, 24), UDim2.fromOffset(18, 52 + row * 48), 12, COLORS.muted, Enum.Font.Code)
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
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.new(1, 16, 1, 20)
		hit.Position = UDim2.fromOffset(-8, -10)
		hit.ZIndex = 5
		hit.Parent = bar
		sliderObjects[name] = { Bar = bar, Gradient = gradient, Knob = knob, Min = minimum, Max = maximum }

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
	lock.BackgroundTransparency = 0.14
	lock.BackgroundColor3 = COLORS.bg
	lock.TextXAlignment = Enum.TextXAlignment.Center
	lock.ZIndex = 12
	corner(lock, 9)

	save.Activated:Connect(function()
		if lock.Visible then return end
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
			itemButton.Active = false
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
end

local function updateVisibility()
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
			and not blockedByModal)
	local layout = UIDevice.Layout()
	if layout.IsTouch then
		-- The right edge is owned by the game's RUN/JUMP/GLOW/FLASHLIGHT
		-- cluster on handhelds. Keep this lobby entry point in the small strip
		-- above it and end it just before the control column; this also leaves
		-- the briefing card's safe content band unobstructed below.
		local requestedWidth = touchDevInLevel and 136
			or (layout.Class == "tablet" and 220 or 184)
		local availableWidth = math.max(1, layout.Zones.Controls.Left - layout.SafeLeft - 8)
		local buttonWidth = math.min(requestedWidth, availableWidth)
		-- The authored 30/36/42 heights were ALL below the 44px tap target this
		-- game holds every other touch control to, which is why the dev variant in
		-- particular was almost unhittable. The floor is applied here, once, so no
		-- future per-class tweak can drop back under it. The TOP edge stays at
		-- y = 8 (= TopBand.Top once the 58px inset is added), so the button grows
		-- DOWNWARD into the safe band and never up under the Roblox topbar.
		local buttonHeight = math.max(TOUCH_MIN_TAP_HEIGHT, touchDevInLevel and 30
			or (layout.Class == "tablet" and 42 or 36))
		openButton.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
		openButton.Position = UDim2.fromOffset(
			math.max(layout.SafeLeft, layout.Zones.Controls.Left - buttonWidth - 8),
			8)
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

-- The terminal was a fixed 840x610 shrunk by a UIScale with a 0.56 FLOOR. On a
-- 375-wide portrait phone the required scale is 375/900 = 0.42, so the clamp
-- left the panel 100+ px wider than the screen -- and scaling further would
-- have made 11px body text illegible anyway. The panel now RESIZES instead of
-- only scaling: it takes the safe area on small screens and keeps its authored
-- 840x610 composition wherever that fits.
local STORE_DESIGN_WIDTH, STORE_DESIGN_HEIGHT = 840, 610
local function updateScale()
	local layout = UIDevice.Layout()
	local availableWidth = layout.SafeRight - layout.SafeLeft
	local availableHeight = layout.SafeBottom - layout.SafeTop
	if availableWidth >= STORE_DESIGN_WIDTH and availableHeight >= STORE_DESIGN_HEIGHT then
		main.Size = UDim2.fromOffset(STORE_DESIGN_WIDTH, STORE_DESIGN_HEIGHT)
		mainScale.Scale = 1
		return
	end
	-- Reflow to the space that exists, then apply only the gentle scale needed
	-- to keep the internal fixed-offset children in proportion. 0.78 is the
	-- floor at which the 11px row text is still readable; below that the panel
	-- keeps its real size and the content scrolls.
	local width = math.min(STORE_DESIGN_WIDTH, availableWidth)
	local height = math.min(STORE_DESIGN_HEIGHT, availableHeight)
	local fit = math.min(width / STORE_DESIGN_WIDTH, height / STORE_DESIGN_HEIGHT)
	mainScale.Scale = math.clamp(fit, 0.78, 1)
	main.Size = UDim2.fromOffset(
		math.floor(width / mainScale.Scale),
		math.floor(height / mainScale.Scale))
end
UIDevice.Changed:Connect(function()
	updateScale()
	updateVisibility()
	-- The dev-page captions drop their key names on a touch form factor, so
	-- a form-factor change has to rebuild every row, not just resize the
	-- panel. Each row registered a refresh when it was built.
	for _, refresh in ipairs(deviceCaptionRefreshers) do
		local ok, err = pcall(refresh)
		if not ok then warn("[ZyntraStore] caption refresh failed: " .. tostring(err)) end
	end
end)
updateScale()

