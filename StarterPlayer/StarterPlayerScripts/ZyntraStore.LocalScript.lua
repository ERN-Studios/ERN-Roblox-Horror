-- ZyntraStore
-- The lobby rail (SHOPS, UPGRADES, REWARDS, WHEEL, MUSIC), Emergency Re-entry,
-- the PlayerScripts.ZyntraOpenTerminal route and the lobby SHOP wall's buy bridge.
--
-- RECORDS_SETTINGS_L4_20261007: the RECORDS / SETTINGS terminal is deleted (owner:
-- the old UI is replaced and deleted). Both are pages of the L4 shop now, from
-- the owner-approved Figma (artifacts/shop-ui-figma-20261005/records-settings).
-- ZyntraOpenTerminal "Records" / "Settings" asks the L4 bridge like every other
-- shop name; "Rewards" still opens Daily Rewards. MUSIC sends through ShopData's
-- settings switch, the one the L4 SETTINGS row uses.
--
-- SHOP_UI_L4_GO_LIVE_20261007: the shop pages (Upgrades, Shop, Skins, Donate,
-- Colors) and the DEV tab were deleted. SHOPS and UPGRADES open the L4 shop
-- ("Zyntra Shop L4", PlayerScripts.ZyntraShopUIOpen); J, DevPhoneCommand and the
-- in-round ZYNTRA // DEV chip open the L4 dev menu ("Zyntra Dev L4",
-- PlayerScripts.ZyntraDevUIOpen); in the lobby, touch and gamepad developers use
-- the L4 shop header's DEV. Their refusal is final: there is no legacy page
-- to fall back to. Backup of the last legacy build:
-- artifacts/shop-ui-figma-20261005/go-live/backup/ (sha f288523b1c68).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))

local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local devAllowed = DevAccess.IsAllowed(player)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local getProfileRemote = remotes:WaitForChild("ZyntraGetProfile")
local actionRemote = remotes:WaitForChild("ZyntraAction")
local profileChangedRemote = remotes:WaitForChild("ZyntraProfileChanged")

local profile
-- Only EmergencyReentry's live price lives here now (fetched in the re-entry block).
local displayedProductPrices = {}
local reentryDead = false
local reentryDismissed = false

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

local gui = Instance.new("ScreenGui")
gui.Name = "ZyntraStore"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 55
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

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
		if object:GetAttribute("SquareSectionButton") then return end
		if object.Active then object.BackgroundColor3 = Color3.fromRGB(32, 50, 53) end
	end)
	object.MouseLeave:Connect(function()
		if object:GetAttribute("SquareSectionButton") then return end
		object.BackgroundColor3 = COLORS.card2
	end)
	return object
end

-- Imagegen section art; approved asset IDs are filled at the upload checkpoint.
-- Rewards and Wheel are the 2026-09-16 pair (cards #104 / #103), 1254² RGBA with
-- real alpha -- see artifacts/trello-20260916-followup/assets-handoff.md. The
-- wheel art is a BUTTON ICON with its pointer baked in, so nothing may rotate it;
-- Lucky Wheel Client builds the spinning disc and its stationary pointer itself.
local SECTION_IMAGES = {Upgrades = "rbxassetid://119432640057145", Shop = "rbxassetid://132462891522145", Music = "rbxassetid://102262986416811",
	Rewards = "rbxassetid://85423575361057", Wheel = "rbxassetid://111918608092047"}
-- One caption per section kind, as a TABLE. It used to be a nested conditional
-- over the kind name whose final `or` was "Upgrades", so the first kind that was
-- neither Shop nor Music captioned itself "Upgrades" -- which is exactly what the
-- two new buttons would have done.
local SECTION_CAPTIONS = {Upgrades = "Upgrades", Shop = "Shops", Music = "Music",
	Rewards = "Rewards", Wheel = "Wheel"}
local function sectionButtonContent(parent, kinds)
	local content = Instance.new("Frame")
	content.Name = "SectionButtonContent"
	content.Size = UDim2.new(1, -6, 1, -6)
	content.Position = UDim2.fromOffset(3, 3)
	content.BackgroundTransparency = 1
	content.ClipsDescendants = true
	content.Active = false
	content.Parent = parent
	local icon = Instance.new("ImageLabel")
	icon.Name = kinds[1] .. "Icon"
	icon.Image = SECTION_IMAGES[kinds[1]]
	icon.BackgroundTransparency = 1
	-- The complete bitmap stays inside the inset frame, above its label.
	icon.Size = UDim2.new(1, 0, 1, -16)
	icon.Position = UDim2.fromOffset(0, 0)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Active = false
	icon.Parent = content
	local caption = label(content, SECTION_CAPTIONS[kinds[1]],
		UDim2.new(1, 0, 0, 16), UDim2.new(0, 0, 1, -16), 12, COLORS.accent, Enum.Font.GothamBold)
	caption.Name = "SectionCaption"
	caption.TextScaled = false
	caption.TextWrapped = false
	caption.TextXAlignment = Enum.TextXAlignment.Center
	caption.Active = false
	parent.TextTransparency = 1
	return content
end

-- The rail, top to bottom: SHOPS, UPGRADES, REWARDS, WHEEL, MUSIC. Arguments are
-- in that same order so the drawn order and the argument order cannot disagree;
-- this used to take three buttons in one order and re-order them in a literal
-- inside the loop, which is a second place to get the rail wrong.
--
-- Cards #103/#104 took Daily Rewards out of the terminal and gave it and the
-- Lucky Wheel a button each, so this column went from 3 to 5 -- and 5 x 64 + 4 x 8
-- is 352px, which does not fit the safe height of a landscape phone. The fit
-- ladder is therefore: full side, then the 52px floor, then TWO COLUMNS. It never
-- ends in a clipped button, because a control that has run off the bottom of the
-- screen is not a smaller control -- it is one the player cannot reach at all.
local function layoutSquareSections(layout, shopButton, openButton, rewardsButton, wheelButton, musicButton)
	local rail = {shopButton, openButton, rewardsButton, wheelButton, musicButton}
	local safe = layout.Safe
	local left = math.ceil(safe.Left + 8)
	local gap = layout.IsTouch and 6 or 8
	local side = layout.IsTouch and 56 or 64
	local available = safe.Bottom - safe.Top - 16
	local function stackHeight(rowCount, edge) return edge * rowCount + gap * (rowCount - 1) end
	local rows, columns = #rail, 1
	if stackHeight(rows, side) > available then side = 52 end
	if stackHeight(rows, side) > available then
		columns = 2
		rows = math.ceil(#rail / columns)
	end
	local height = stackHeight(rows, side)
	-- The rail's whole footprint, which is what the thumbstick has to be dodged
	-- against. Measuring one button's width there was already only correct while
	-- the rail was a single column.
	local width = side * columns + gap * (columns - 1)
	local top = math.floor((safe.Top + safe.Bottom - height) / 2 + 0.5)
	-- Keep the left rail centred. Only move it when the actual resting stick
	-- glyph intersects; the broad invisible activation zone is not a glyph.
	if layout.IsTouch then
		local touchGui = gui.Parent:FindFirstChild("TouchGui")
		local controls = touchGui and touchGui:FindFirstChild("TouchControlFrame")
		local stick = controls and controls:FindFirstChild("DynamicThumbstickFrame")
		local glyph = stick and stick:FindFirstChild("ThumbstickStart")
		if glyph and glyph:IsA("GuiObject") and glyph.AbsoluteSize.Y > 0 then
			local x, y = UIDevice.LocalOffset(touchGui, 0, 0)
			local position = glyph.AbsolutePosition - touchGui.AbsolutePosition
			local gx, gy = position.X - x, position.Y - y
			local gw, gh = glyph.AbsoluteSize.X, glyph.AbsoluteSize.Y
			-- The rail is re-solved against the glyph as a whole: first the stack
			-- it already has, then -- if that stack can dodge neither above nor
			-- below -- the two-column stack, which is half the height and does.
			-- Measured on a real iPhone 13 in landscape (749x368, 2026-09-16): five
			-- 52px buttons in one column are 297px tall, the resting glyph sits at
			-- y 217..291, and neither side had room, so WHEEL and MUTE were drawn
			-- under the thumbstick. Two columns (168px) clear it above.
			local function intersects(railTop, railHeight, railWidth)
				return left < gx + gw and left + railWidth > gx
					and railTop < gy + gh + 8 and railTop + railHeight > gy - 8
			end
			local function dodge(railTop, railHeight)
				local above = math.floor(gy - 8 - railHeight)
				local below = math.ceil(gy + gh + 8)
				local aboveFits = above >= safe.Top + 8
				local belowFits = below + railHeight <= safe.Bottom - 8
				if aboveFits and (not belowFits or math.abs(above - railTop) <= math.abs(below - railTop)) then
					return above
				elseif belowFits then
					return below
				end
				return nil
			end
			if intersects(top, height, width) then
				local moved = dodge(top, height)
				if moved == nil and columns == 1 then
					columns = 2
					rows = math.ceil(#rail / columns)
					height = stackHeight(rows, side)
					width = side * columns + gap * (columns - 1)
					top = math.floor((safe.Top + safe.Bottom - height) / 2 + 0.5)
					if intersects(top, height, width) then moved = dodge(top, height) end
				end
				if moved ~= nil then top = moved end
				-- If neither stack can dodge, retain the visible centred rail. Do
				-- not hide all five controls or silently relocate them to the right.
			end
		end
	end
	for index, entry in ipairs(rail) do
		-- Column-major: a 3-button column at `left` and a 2-button column beside
		-- it, both starting at the same `top`, so the order still reads downward.
		local column = math.floor((index - 1) / rows)
		local row = (index - 1) % rows
		entry.Size = UDim2.fromOffset(side, side)
		entry.Position = UIDevice.LocalPosition(gui,
			left + column * (side + gap), top + row * (side + gap))
		local caption = entry:FindFirstChild("SectionButtonContent"):FindFirstChild("SectionCaption")
		caption.TextSize = side >= 64 and 12 or (side >= 56 and 11 or 10)
	end
	-- The rail's right edge in UIDevice.Layout() space, published by
	-- updateVisibility as ZyntraRailRight for the windows that keep clear of it.
	return left + width
end

local openButton = button(gui, "Upgrades", UDim2.fromOffset(64, 64), UDim2.fromOffset(8, 80))
openButton.Name = "ZyntraOpenButton"
openButton.BackgroundColor3 = COLORS.bg
openButton.TextColor3 = COLORS.accent
openButton.TextSize = 18
openButton.TextWrapped = true
local openButtonOutline = outline(openButton, COLORS.accent, 0.22, 1.5)
sectionButtonContent(openButton, {"Upgrades"})

local shopButton = button(gui, "Shops", UDim2.fromOffset(64, 64), UDim2.fromOffset(8, 8))
shopButton.Name = "ZyntraShopButton"
shopButton.BackgroundColor3 = COLORS.bg
shopButton.TextColor3 = COLORS.accent
shopButton.TextSize = 18
local shopButtonRing = outline(shopButton, COLORS.accent, 0.22, 1.5)
sectionButtonContent(shopButton, {"Shop"})

local rewardsButton = button(gui, "Rewards", UDim2.fromOffset(64, 64), UDim2.fromOffset(8, 152))
rewardsButton.Name = "ZyntraRewardsButton"
rewardsButton.BackgroundColor3 = COLORS.bg
rewardsButton.TextColor3 = COLORS.accent
sectionButtonContent(rewardsButton, {"Rewards"})

local wheelButton = button(gui, "Wheel", UDim2.fromOffset(64, 64), UDim2.fromOffset(8, 224))
wheelButton.Name = "ZyntraWheelButton"
wheelButton.BackgroundColor3 = COLORS.bg
wheelButton.TextColor3 = COLORS.accent
sectionButtonContent(wheelButton, {"Wheel"})

-- RAIL_DOTS_20260922 (Trello MsEn2mya). A small red dot on REWARDS and WHEEL,
-- drawn ONLY while the published profile says something is actually there to
-- take: a playtime milestone reached and unclaimed, a free spin still unused
-- for this UTC day, or a spun prize not yet collected. It is recomputed from
-- every profile push (a claim, a spin, a collect, a playtime flush all push)
-- and once more at the UTC reset -- one delayed re-read, re-armed per push,
-- not a ticker.
local function notificationDot(parent)
	local dot = Instance.new("Frame")
	dot.Name = "NotificationDot"
	dot.AnchorPoint = Vector2.new(1, 0)
	dot.Position = UDim2.new(1, -4, 0, 4)
	dot.Size = UDim2.fromOffset(10, 10)
	dot.BackgroundColor3 = COLORS.error
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.ZIndex = 5
	dot.Active = false
	dot.Parent = parent
	corner(dot, 5)
	local ring = outline(dot, COLORS.bg, 0, 1.5)
	ring.Name = "DotRing"
	return dot
end
local rewardsDot = notificationDot(rewardsButton)
local wheelDot = notificationDot(wheelButton)

-- RAIL_DOTS_20260922 BEGIN -- pure reads of the profile ZyntraMonetization
-- publishes (dailyPublic: Today, PlaytimeSeconds, Claimed, WheelDay, WheelLast).
local function rewardsClaimable(data): boolean
	local daily = type(data) == "table" and type(data.Daily) == "table" and data.Daily or nil
	if not daily then return false end
	local played = tonumber(daily.PlaytimeSeconds) or 0
	local claimed = type(daily.Claimed) == "table" and daily.Claimed or {}
	for _, milestone in ipairs((Config.DailyRewards or {}).Milestones or {}) do
		local minutes = tonumber(milestone.Minutes)
		if minutes and played >= minutes * 60 and claimed[tostring(minutes)] ~= true then
			return true
		end
	end
	return false
end

local function wheelClaimable(data): boolean
	local daily = type(data) == "table" and type(data.Daily) == "table" and data.Daily or nil
	if not daily then return false end
	local last = type(daily.WheelLast) == "table" and daily.WheelLast or nil
	-- A spun prize still owed (WHEEL_COLLECT_20260922) is something to take,
	-- whatever day it was spun on.
	if last and last.Claimed == false then return true end
	local today = tostring(daily.Today or "")
	return today ~= "" and tostring(daily.WheelDay or "") ~= today
end
-- RAIL_DOTS_20260922 END

-- REWARDS_INTRO_20260922 BEGIN -- the one-time note after the first real
-- level completion (the server counts CompletedLevels only on an escape).
local function introWanted(data): boolean
	return type(data) == "table" and (tonumber(data.CompletedLevels) or 0) >= 1
		and data.RewardsIntroSeen ~= true
end
-- REWARDS_INTRO_20260922 END

local musicButton = button(gui, "Music", UDim2.fromOffset(64, 64), UDim2.fromOffset(8, 296))
musicButton.Name = "ZyntraMusicButton"
musicButton.BackgroundColor3 = COLORS.bg
musicButton.TextColor3 = COLORS.accent
musicButton.Active = false
sectionButtonContent(musicButton, {"Music"})
-- The whole rail, once, in the drawn order. Every loop over it below uses this
-- list rather than restating the members, because the members changed on
-- 2026-09-16 and the seven places that each named three buttons are exactly how
-- two of them would have been left out of one rule.
local railButtons = {shopButton, openButton, rewardsButton, wheelButton, musicButton}
for _, entry in ipairs(railButtons) do
	entry:SetAttribute("SquareSectionButton", true)
	local border = outline(entry, COLORS.accent, 0.22, 1.5)
	border.Name = "SquareSectionBorder"
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	entry.MouseEnter:Connect(function()
		if entry.Active and entry:GetAttribute("SquareSectionButton") then border.Transparency = 0 end
	end)
	entry.MouseLeave:Connect(function() border.Transparency = 0.22 end)
	-- SQUARE, like its two neighbours. Card 88 singled this one control out on
	-- 2026-09-15 -- a disc corner radius, an 8px content inset and a breathing
	-- accent ring, on ZyntraShopButton only. The owner's 2026-09-16 correction
	-- puts it back in the rail: all three buttons are built by exactly this loop
	-- now, and nothing in here may distinguish one of them again.
end

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
-- panel's OWN visibility as this attribute. The centred lobby rail now
-- explicitly remains usable during Dispatch; the in-round DEV phone still
-- honours this historical overlap guard.
local BRIEFING_ATTRIBUTE = "DispatchBriefingOpen"

local function queueModalOpen()
	return player:GetAttribute(QUEUE_MODAL_ATTRIBUTE) == true
end

local function briefingOpen()
	return player:GetAttribute(BRIEFING_ATTRIBUTE) == true
end

-- The centred lobby rail remains usable during Dispatch. Keep the prior
-- briefing exclusion for the in-round DEV phone and always honour the queue.
local function modalBlocksStore()
	return queueModalOpen() or (player:GetAttribute("InRound") == true and briefingOpen())
end

-- MUSIC, the rail's fifth button, is the lobby-music switch, and so is the L4
-- shop's SETTINGS row: both send SetAccessibility {Key = "LobbyMusicEnabled"},
-- and the server drops a second send of one key inside its 1 s window. So both
-- go through ONE send path, ShopData.toggleSetting: one optimistic value, one
-- last-send clock, the 1.1 s hold and the 12 s silent revert, whichever surface
-- was pressed (a row press, Close, then MUSIC within the second used to be
-- dropped and drawn wrong for 12 s). Off the main thread: if ZyntraShopUI never
-- arrives MUSIC keeps its MUSIC caption, and the rest of this script does not
-- wait for it. ShopData.start() is idempotent ("Zyntra Shop L4" starts it too).
-- "Zyntra Shop L4" mirrors the caption onto its rail graft: MUTE, UNMUTE or MUSIC.
task.spawn(function()
	local KEY = "LobbyMusicEnabled"
	local ShopData = require(ReplicatedStorage:WaitForChild("ZyntraShopUI"):WaitForChild("ShopData"))
	ShopData.start()
	local function refresh()
		local ready = ShopData.settingReady(KEY)
		local enabled = ShopData.setting(KEY) == true
		musicButton.Text = ready and (enabled and "Mute music" or "Unmute music") or "Loading music"
		local caption = musicButton.SectionButtonContent.SectionCaption
		caption.Text = ready and (enabled and "Mute" or "Unmute") or "Music"
		caption.TextColor3 = ready and COLORS.accent or COLORS.muted
		-- No modal clause (RAIL_OVER_WINDOWS_20261007): Visible already means "not
		-- hidden by a round, the queue or re-entry", and MUSIC toggles over the
		-- rail's own windows like the SETTINGS row does.
		UIDevice.SetEnabled(musicButton, musicButton.Visible and ready
			and player:GetAttribute("InRound") ~= true)
	end
	musicButton.Activated:Connect(function()
		if musicButton.Visible and musicButton.Active and player:GetAttribute("InRound") ~= true then
			ShopData.toggleSetting(KEY) -- refuses until the server has published the switch
		end
	end)
	musicButton:GetPropertyChangedSignal("Visible"):Connect(refresh)
	ShopData.Changed:Connect(refresh) -- the attribute, a press, its confirm or revert
	refresh()
end)

-- The re-entry modal's two errors and a failed profile read used to land in the
-- terminal's status line, which never shows in a round, where the modal is. The
-- terminal is deleted; they go to the output. Push messages reach the L4 shop's
-- footer and toast through ShopData.
local function showStatus(message)
	if type(message) == "string" and message ~= "" then warn("[ZyntraStore] " .. message) end
end

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
reentryShade.Selectable = false
reentryShade.Modal = true
reentryShade.ZIndex = 1
reentryShade.Parent = reentryGui

local reentry = Instance.new("Frame")
reentry.Name = "EmergencyReentry"
reentry.AnchorPoint = Vector2.new(0.5, 0.5)
reentry.Position = UDim2.fromScale(0.5, 0.54)
reentry.Size = UDim2.new(1, -32, 0, 216)
reentry.BackgroundColor3 = COLORS.bg
reentry.BorderSizePixel = 0
reentry.Visible = true
reentry.ZIndex = 2
reentry.Parent = reentryGui
local reentryConstraint = Instance.new("UISizeConstraint")
reentryConstraint.MinSize = Vector2.new(280, 216)
reentryConstraint.MaxSize = Vector2.new(480, 216)
reentryConstraint.Parent = reentry
corner(reentry, 10)
outline(reentry, COLORS.error, 0.15, 1.5)
local reentryTitle = label(reentry, "EMERGENCY RE-ENTRY", UDim2.new(1, -32, 0, 28), UDim2.fromOffset(16, 10), 19, COLORS.text, Enum.Font.GothamBold)
reentryTitle.ZIndex = 3
local reentryInfo = label(reentry, "Use a credit to rejoin the run, or spectate your teammates.", UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 44), 13, COLORS.muted)
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
	local roundActive = workspace:GetAttribute("RoundActive") == true or player:GetAttribute("Level6PlaygroundPreview") == true
	local used = player:GetAttribute("ZyntraReentryUsed") == true
	if not inRound or not roundActive then reentryDismissed = false end
	local shouldShow = inRound and roundActive and reentryDead and not used and not reentryDismissed
	-- C_PARTY_DOWN_ONE_PURCHASE_SURFACE_20260904: RoundUI's PARTY DOWN card
	-- carries the same re-entry action for the 15-second wipe window. For that
	-- whole WINDOW this panel stands down -- two purchase surfaces for one
	-- product, stacked (RoundGui is DisplayOrder 100, this modal 120), is how a
	-- player ends up buying twice, and declining the card must not simply pop
	-- this one up in its place.
	--
	-- The published modal flag follows what is actually DRAWN, though, never the
	-- window: it is what frees the cursor and stands the touch movement cluster
	-- down, and asserting it for a window with no card on screen left a declined
	-- player with a forced cursor over a stood-down HUD for fifteen seconds.
	local windowOpen = player:GetAttribute("PartyDownWindowOpen") == true
	local cardOpen = player:GetAttribute("PartyDownCardOpen") == true
	reentryGui.Enabled = shouldShow and not windowOpen
	-- Hidden modal selections still block SpectateController's input handlers.
	if not reentryGui.Enabled then
		local GuiService = game:GetService("GuiService")
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(reentryGui) then
			GuiService.SelectedObject = nil
		end
	end
	player:SetAttribute("ZyntraReentryOpen",
		(reentryGui.Enabled or cardOpen) and true or nil)
	local credits = profile and profile.ReentryCredits or 0
	reentryButton.Text = credits > 0
		and ("USE RE-ENTRY CREDIT  //  " .. credits .. " OWNED")
		or (tostring(displayedProductPrices.EmergencyReentry or Config.Products.EmergencyReentry.Price) .. " R$  //  BUY CREDIT")
	-- The smallest public surface for the card, which is in another script and
	-- cannot see this file's `profile`, its live-fetched price or Config. Three
	-- numbers, written from the one function every profile change, death,
	-- re-entry and round transition already lands on -- including the spawn call
	-- below, so they are published before any round can be lost. Reading them
	-- rather than requiring ZyntraConfig is what keeps RoundUI from yielding on
	-- a WaitForChild in the middle of its own chunk.
	player:SetAttribute("ZyntraReentryCredits", credits)
	player:SetAttribute("ZyntraReentryPrice",
		displayedProductPrices.EmergencyReentry or Config.Products.EmergencyReentry.Price)
	player:SetAttribute("ZyntraReentryProductId", Config.Products.EmergencyReentry.Id)
end
player:GetAttributeChangedSignal("PartyDownCardOpen"):Connect(updateReentry)
player:GetAttributeChangedSignal("PartyDownWindowOpen"):Connect(updateReentry)

do
	-- The LIVE price (Managed Pricing can differ per player) for this modal and
	-- for RoundUI's PARTY DOWN card, which reads ZyntraReentryPrice. The config
	-- price is only the fallback until this answers. It used to arrive as a side
	-- effect of the legacy Shop page's re-entry card, deleted on go-live.
	task.spawn(function()
		local id = tonumber(Config.Products.EmergencyReentry.Id) or 0
		if id <= 0 then return end
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
		end)
		local price = ok and type(info) == "table" and tonumber(info.PriceInRobux) or nil
		if price and price >= 0 then
			displayedProductPrices.EmergencyReentry = math.floor(price)
			updateReentry()
		end
	end)

	-- DEV_FREE_RESPAWN_OFFER_20260915 (card 81): whitelisted developers get the
	-- free server-only respawn inside the same offer, between the paid action
	-- and SPECTATE. `devAllowed` is cosmetic: GameManager re-checks DevAccess
	-- and the dead InRound body, and the free path never reserves a credit,
	-- spends tokens or prompts Robux. Same DevCheatCommand bridge the dev menu uses.
	if devAllowed then
		reentry.Size = UDim2.new(1, -32, 0, 268)
		reentryConstraint.MinSize = Vector2.new(280, 268)
		reentryConstraint.MaxSize = Vector2.new(480, 268)
		local reentryFree = button(reentry, "FREE RESPAWN  //  DEV", UDim2.new(1, -32, 0, 44), UDim2.fromOffset(16, 156))
		reentryFree.Name = "ReentryFreeRespawn"
		reentryFree.TextColor3 = COLORS.accent
		reentryFree.ZIndex = 3
		local function refreshFree()
			local busy = player:GetAttribute("DevRespawnBusy") == true
			reentryFree.Text = busy and "RESPAWNING..." or "FREE RESPAWN  //  DEV"
			UIDevice.SetEnabled(reentryFree, not busy)
		end
		player:GetAttributeChangedSignal("DevRespawnBusy"):Connect(refreshFree)
		refreshFree()
		reentryFree.Activated:Connect(function()
			if not reentryGui.Enabled or player:GetAttribute("DevRespawnBusy") == true then return end
			local scripts = player:FindFirstChild("PlayerScripts")
			local command = scripts and scripts:FindFirstChild("DevCheatCommand")
			if command and command:IsA("BindableEvent") then
				command:Fire("freeRespawn")
			else
				showStatus("Developer controls are still loading. Try again.", "error")
			end
		end)
	end
	local reentryDecline = button(reentry, "SPECTATE", UDim2.new(1, -32, 0, 44), UDim2.fromOffset(16, devAllowed and 208 or 156))
	reentryDecline.Name = "ReentryDecline"
	reentryDecline.ZIndex = 3
	reentryDecline.Activated:Connect(function()
		if not reentryGui.Enabled then return end
		-- Remember the choice for this death, including profile refreshes and
		-- the PARTY DOWN window opening or clearing after a teammate re-enters.
		reentryDismissed = true
		updateReentry()
	end)
end

local function bindCharacter(character)
	reentryDead = false
	reentryDismissed = false
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
	updateReentry()
end

-- RAIL_DOTS_20260922: recomputed on every push; one delayed re-read at the
-- UTC reset so a dot that depends on "today" flips without a ticker.
local dotResetSerial = 0
local function refreshRailDots()
	rewardsDot.Visible = rewardsClaimable(profile)
	wheelDot.Visible = wheelClaimable(profile)
	local daily = type(profile) == "table" and type(profile.Daily) == "table" and profile.Daily or nil
	local seconds = daily and tonumber(daily.SecondsToReset) or nil
	if not seconds then return end
	dotResetSerial += 1
	local serial = dotResetSerial
	task.delay(math.max(1, seconds + 1), function()
		if serial ~= dotResetSerial then return end
		task.spawn(function()
			local gotIt, answer = pcall(getProfileRemote.InvokeServer, getProfileRemote)
			if gotIt and answer then
				profile = answer
				refreshUI()
				refreshRailDots()
			end
		end)
	end)
end

-- REWARDS_INTRO_20260922 (Trello MsEn2mya). A short, dismissable note beside
-- the rail after the player's FIRST real level completion: what REWARDS and
-- WHEEL give and what the red dot means. Shown only at a quiet lobby moment --
-- not in a round, not over the briefing, the queue modal or any screen-owning
-- modal (the L4 shop is one) -- and only after those conditions have held for
-- INTRO_QUIET_SECONDS, which is what keeps it clear of the win / Continue /
-- Return flow the player has just come out of. GOT IT persists RewardsIntroSeen
-- through MarkRewardsIntroSeen (idempotent on the server); a save that fails
-- shows it again on a later join, never twice in one session.
local INTRO_QUIET_SECONDS = 4
local introDismissed = false
local introArmSerial = 0
local introCard = Instance.new("Frame")
introCard.Name = "RewardsIntroCard"
introCard.Size = UDim2.fromOffset(300, 150)
introCard.BackgroundColor3 = COLORS.panel
introCard.BorderSizePixel = 0
introCard.Visible = false
introCard.ZIndex = 6
introCard.Parent = gui
corner(introCard, 10)
outline(introCard, COLORS.accent, 0.35, 1.5)
local introEyebrow = label(introCard, "ZYNTRA FIRST CLEAR LOGGED", UDim2.new(1, -24, 0, 14),
	UDim2.fromOffset(12, 10), 11, COLORS.muted, Enum.Font.Code)
introEyebrow.TextXAlignment = Enum.TextXAlignment.Left
local introTitle = label(introCard, "REWARDS AND THE WHEEL", UDim2.new(1, -24, 0, 20),
	UDim2.fromOffset(12, 26), 15, COLORS.accent, Enum.Font.GothamBlack)
introTitle.TextXAlignment = Enum.TextXAlignment.Left
local introBody = label(introCard,
	"REWARDS pays tokens and gear for minutes played today. WHEEL gives one free spin a day -- collect what it lands on. A red dot on either button means something is waiting.",
	UDim2.new(1, -24, 0, 58), UDim2.fromOffset(12, 48), 12, COLORS.text, Enum.Font.Gotham)
introBody.TextXAlignment = Enum.TextXAlignment.Left
introBody.TextYAlignment = Enum.TextYAlignment.Top
introBody.TextWrapped = true
local introGotIt = button(introCard, "GOT IT", UDim2.new(1, -24, 0, 30), UDim2.new(0, 12, 1, -40))
introGotIt.Name = "GotIt"
introGotIt.TextSize = 13

local function placeIntro()
	-- Beside the rail, level with REWARDS, inside this gui's own offsets.
	local x = rewardsButton.AbsolutePosition.X - gui.AbsolutePosition.X + rewardsButton.AbsoluteSize.X + 12
	local y = rewardsButton.AbsolutePosition.Y - gui.AbsolutePosition.Y
	local layout = UIDevice.Layout()
	local width = math.min(300, math.max(220, layout.Safe.Right - (rewardsButton.AbsolutePosition.X + rewardsButton.AbsoluteSize.X) - 24))
	introCard.Size = UDim2.fromOffset(width, 150)
	introCard.Position = UDim2.fromOffset(x, math.max(0, math.min(y, layout.Safe.Bottom - gui.AbsolutePosition.Y - 160)))
end

local function introConditions(): boolean
	return not introDismissed and introWanted(profile)
		and player:GetAttribute("InRound") ~= true
		and player:GetAttribute(BRIEFING_ATTRIBUTE) ~= true
		and not modalBlocksStore()
		and not UIDevice.ScreenOwningModalOpen()
end

local function syncRewardsIntro()
	if introConditions() then
		if introCard.Visible then return end
		introArmSerial += 1
		local serial = introArmSerial
		task.delay(INTRO_QUIET_SECONDS, function()
			if serial ~= introArmSerial or introCard.Visible then return end
			if introConditions() then
				placeIntro()
				introCard.Visible = true
			end
		end)
	else
		introArmSerial += 1
		introCard.Visible = false
	end
end

introGotIt.Activated:Connect(function()
	introDismissed = true
	introArmSerial += 1
	introCard.Visible = false
	actionRemote:FireServer("MarkRewardsIntroSeen")
end)
for _, attribute in ipairs({"InRound", BRIEFING_ATTRIBUTE}) do
	player:GetAttributeChangedSignal(attribute):Connect(syncRewardsIntro)
end

profileChangedRemote.OnClientEvent:Connect(function(newProfile)
	if newProfile then profile = newProfile end
	refreshUI()
	refreshRailDots()
	syncRewardsIntro()
end)

task.spawn(function()
	local ok, result = pcall(getProfileRemote.InvokeServer, getProfileRemote)
	if ok then
		profile = result
		refreshUI()
		refreshRailDots()
		syncRewardsIntro()
	else
		showStatus("Could not load the Zyntra profile.", "error")
	end
end)

local function updateVisibility()
	local inRound = player:GetAttribute("InRound") == true
	local touchDevInLevel = inRound and devAllowed and UserInputService.TouchEnabled
	local blockedByModal = modalBlocksStore()
	-- Visible = false alone was never enough: an Active TextButton keeps taking
	-- taps through its own transparent background, which is how this control was
	-- swallowing the queue modal's Close. SetInteractive clears Active/Selectable
	-- with it, so a hidden button is genuinely gone from the input stack.
	-- Two independent suppressors, both of which own this same strip of screen:
	-- the queue host modal, and the dispatch briefing panel. Either one being up
	-- takes the opener off the screen AND out of the input stack.
	-- RAIL_OVER_WINDOWS_20261007 (owner, 2026-10-07): the rail stays up
	-- over its OWN windows -- the L4 shop, the L4 dev menu, Daily Rewards and the
	-- Lucky Wheel -- so a rail press switches window instead of needing a Close
	-- first. In the lobby only re-entry hides it here; the queue still does
	-- through blockedByModal. In a round the old rule stands unchanged (every
	-- screen-owning modal hides it), so the touch DEV chip still hides under
	-- DevPhoneOpen. Before this, the 2026-09-16 lead fix hid the rail under every
	-- modal because SHOPS stayed Active beside an open Daily Rewards, one tap
	-- from a second modal; switchFrom (below) is what makes that tap safe now.
	local otherModal = if inRound then UIDevice.ScreenOwningModalOpen()
		else player:GetAttribute("ZyntraReentryOpen") == true
	UIDevice.SetInteractive(openButton,
		(not inRound or touchDevInLevel)
			and not blockedByModal
			and not otherModal)
	UIDevice.SetInteractive(shopButton, not inRound and not blockedByModal
		and not otherModal)
	-- REWARDS, WHEEL and MUSIC share one predicate with SHOPS. Their windows
	-- draw full-screen Active shields (Shop 56, Dev 57, Daily 117, Wheel 118), so
	-- while one is open the rail gui rises to 119 -- above all four, below
	-- re-entry's 120 -- and a rail tap lands before any shield takes it. Back at
	-- 55 the moment no rail window is open.
	local railAvailable = not inRound and not blockedByModal and not otherModal
	UIDevice.SetInteractive(rewardsButton, railAvailable)
	UIDevice.SetInteractive(wheelButton, railAvailable)
	UIDevice.SetInteractive(musicButton, railAvailable)
	gui.DisplayOrder = if railAvailable and UIDevice.ScreenOwningModalOpen() then 119 else 55
	syncRewardsIntro()
	if type(player:GetAttribute("LobbyMusicEnabled")) ~= "boolean" then
		musicButton.Active = false
		musicButton.Selectable = false
	end
	local layout = UIDevice.Layout()
	if layout.IsTouch then
		-- The right edge is owned by the game's RUN/JUMP/GLOW/FLASHLIGHT
		-- cluster on handhelds. Keep this lobby entry point in the small strip
		-- above it and end it just before the control column; this also leaves
		-- the briefing card's safe content band unobstructed below.
		local requestedWidth = touchDevInLevel and 136
			or (layout.Class == "tablet" and 280 or 220)
		-- A TAP TARGET OR NOTHING. `math.max(1, ...)` was the floor here, and a
		-- one-pixel-wide button is not a smaller control -- it is an invisible
		-- one, which is exactly what a stale control-zone measurement produced
		-- on the frame a round began. The floor is the same 44px minimum every
		-- other touch control in this game is held to; if the strip beside the
		-- cluster genuinely cannot hold that, the overlap becomes a visible
		-- failure in the touch-target matrix rather than a button nobody can hit.
		-- With no controls drawn, their empty zone sits at Display.Right, which
		-- extends past a phone's safe area. Keep both lobby buttons inside it.
		local rightLimit = touchDevInLevel and layout.Zones.Controls.Left
			or math.min(layout.Safe.Right, layout.Zones.Controls.Left)
		local availableWidth = math.max(1, rightLimit - layout.SafeLeft - 8)
		local buttonWidth = math.max(TOUCH_MIN_TAP_HEIGHT,
			math.min(requestedWidth, availableWidth))
		-- The authored 30/36/42 heights were ALL below the 44px tap target this
		-- game holds every other touch control to, which is why the dev variant in
		-- particular was almost unhittable. The floor is applied here, once, so no
		-- future per-class tweak can drop back under it. The TOP edge stays at
		-- y = 8 (= TopBand.Top once the 58px inset is added), so the button grows
		-- DOWNWARD into the safe band and never up under the Roblox topbar.
		local buttonHeight = math.max(TOUCH_MIN_TAP_HEIGHT, touchDevInLevel and 30
			or (layout.Class == "tablet" and 64 or 56))
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
				math.max(layout.SafeLeft, rightLimit - buttonWidth - 8),
				layout.Safe.Top + 8)
		end
	else
		openButton.Size = UDim2.fromOffset(280, 64)
		openButton.Position = UDim2.new(1, -298, 0, 20)
	end
	shopButton.Size = UDim2.fromOffset(openButton.Size.X.Offset, 48)
	shopButton.Position = openButton.Position + UDim2.fromOffset(0, openButton.Size.Y.Offset + 8)
	-- ZyntraRailRight: client-local, the rail's right edge in UIDevice.Layout()
	-- space. The L4 shop, Daily and dev windows start 8px right of it and re-fit
	-- when it changes; nil in a round, where there is no rail to keep clear of.
	player:SetAttribute("ZyntraRailRight", if inRound then nil
		else layoutSquareSections(layout, shopButton, openButton, rewardsButton, wheelButton, musicButton))
	for _, entry in ipairs(railButtons) do
		entry:SetAttribute("SquareSectionButton", not touchDevInLevel)
		entry:FindFirstChild("SquareSectionBorder").Enabled = not touchDevInLevel
		if not touchDevInLevel then entry.BackgroundColor3 = COLORS.bg end
	end
	if touchDevInLevel then
		-- Keep a discreet phone-only escape hatch for whitelisted developers.
		-- Desktop developers use J in levels, so no clickable HUD control is shown.
		openButton.Text = "ZYNTRA // DEV"
		openButton.TextSize = 11
		openButton.TextWrapped = false
		openButton.BackgroundTransparency = 0.48
		openButton.TextTransparency = 0.22
		openButtonOutline.Transparency = 0.64
		openButtonOutline.Thickness = 1
	else
		openButton.Text = "Upgrades"
		openButton.TextSize = 18
		openButton.TextWrapped = true
		openButton.BackgroundTransparency = 0
		openButton.TextTransparency = 0
		openButtonOutline.Transparency = 0.22
		openButtonOutline.Thickness = 1.5
	end
	-- Lobby squares keep their centered artwork and labels; the existing DEV chip stays text-only.
	-- "Zyntra Shop L4" grafts its own face (L4Skin_Face) into every rail button and
	-- hides SectionButtonContent once. Both follow this predicate: the in-round DEV
	-- chip shows neither, and a skinned square never gets the legacy art back under
	-- its graft.
	local sectionIconsVisible = not touchDevInLevel
	for _, entry in ipairs(railButtons) do
		local skin = entry:FindFirstChild("L4Skin_Face")
		if skin then skin.Visible = sectionIconsVisible end
		entry.SectionButtonContent.Visible = sectionIconsVisible and not skin
	end
	if sectionIconsVisible then openButton.TextTransparency = 1 end
	shopButton.TextTransparency = sectionIconsVisible and 1 or 0
	-- The three icon-only buttons never show their fallback caption: the icon and
	-- its SectionCaption are the label, and the TextButton text underneath is only
	-- there so a place without the art still has a reachable, named control.
	rewardsButton.TextTransparency = 1
	wheelButton.TextTransparency = 1
	musicButton.TextTransparency = 1
	-- Contextual UIStrokes still paint the hidden original caption in Roblox.
	for _, entry in ipairs(railButtons) do
		for _, child in ipairs(entry:GetChildren()) do
			if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
				child.Enabled = not sectionIconsVisible
			end
		end
	end
	updateReentry()
end
player:GetAttributeChangedSignal("InRound"):Connect(updateVisibility)
player:GetAttributeChangedSignal(QUEUE_MODAL_ATTRIBUTE):Connect(updateVisibility)
player:GetAttributeChangedSignal(BRIEFING_ATTRIBUTE):Connect(updateVisibility)
-- The rail reads the screen-owning modal set -- re-entry hides it, a rail
-- window raises it to DisplayOrder 119, and in a round any modal hides it --
-- and until this line nothing re-evaluated it: only QueueModalOpen and the
-- briefing re-ran updateVisibility, so MUSIC was once left drawn and Active
-- underneath a re-entry modal. The L4 shop's ZyntraStoreOpen lands here too.
UIDevice.OnScreenOwningModalChanged(updateVisibility)
-- The L4 graft can land after a round has already made UPGRADES the DEV chip.
for _, entry in ipairs(railButtons) do
	entry.ChildAdded:Connect(function(child)
		if child.Name == "L4Skin_Face" then updateVisibility() end
	end)
end
player:GetAttributeChangedSignal("ZyntraReentryUsed"):Connect(updateReentry)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(updateReentry)
updateVisibility()

-- J, PlayerScripts.DevPhoneCommand and the in-round ZYNTRA // DEV chip, for
-- whitelisted developers: the L4 dev menu ("Zyntra Dev L4"), lobby and round
-- alike. Its refusal is final -- there is no DEV tab to fall back to.
local function toggleDevMenu(requested)
	if not devAllowed then return end
	local alt = player:WaitForChild("PlayerScripts"):FindFirstChild("ZyntraDevUIOpen")
	if alt and alt:IsA("BindableFunction") then
		local ok, used = pcall(alt.Invoke, alt, requested)
		if ok and used == true then return end
	else
		warn("[ZyntraStore] PlayerScripts.ZyntraDevUIOpen is missing: Zyntra Dev L4 is not installed, so the dev menu cannot open")
	end
end

-- The two lobby modals that are not the shop (cards #103 / #104). This
-- LocalScript owns the rail BUTTON for each and nothing else about them: it
-- fires a BindableEvent in PlayerScripts and the owning client decides the rest.
-- Create-if-absent on both sides -- the PlayerScripts.RoundExitPrompt pattern --
-- so neither script has to have loaded before the other.
local function lobbyModalOpener(name)
	local playerScripts = player:WaitForChild("PlayerScripts")
	local event = playerScripts:FindFirstChild(name)
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = name
		event.Parent = playerScripts
	elseif not event:IsA("BindableEvent") then
		warn("[ZyntraStore] PlayerScripts." .. name .. " must be a BindableEvent")
		return function() end
	end
	return function()
		-- The kiosk's two guards, plus the modal set. Two screen-owning modals may
		-- never be up at once; the receiving client refuses as well, but refusing
		-- HERE is what keeps the refusal true for ZyntraOpenTerminal "Rewards" too.
		-- A RAIL press over one of the rail's own windows reaches this only after
		-- switchFrom has closed that window (RAIL_OVER_WINDOWS_20261007); every
		-- other caller still refuses over any modal.
		if player:GetAttribute("InRound") == true or modalBlocksStore()
			or UIDevice.ScreenOwningModalOpen() then
			return
		end
		event:Fire()
	end
end
local openDailyRewards = lobbyModalOpener("OpenDailyRewards")
local openLuckyWheel = lobbyModalOpener("OpenLuckyWheel")

-- Every shop entry: the SHOPS and UPGRADES rail buttons and the public route
-- PlayerScripts.ZyntraOpenTerminal ("open the shop on tab X"; the name stays,
-- the terminal it once opened is deleted). "Rewards" is the Daily Rewards modal;
-- every other name (nil = Shop), RECORDS and SETTINGS included, belongs to the
-- L4 shop ("Zyntra Shop L4"), whose refusal is final: it applies the same guards
-- and warns about its own build failures, and there is nothing to fall back to.
-- Returns whether something opened.
local function openKioskShop(tab)
	-- REWARDS LEFT THE TERMINAL (card #104) and is answered HERE, once, so there
	-- is a single answer to "Rewards".
	if tab == "Rewards" then
		openDailyRewards()
		return false
	end
	local alt = player:WaitForChild("PlayerScripts"):FindFirstChild("ZyntraShopUIOpen")
	if not (alt and alt:IsA("BindableFunction")) then
		warn("[ZyntraStore] PlayerScripts.ZyntraShopUIOpen is missing: Zyntra Shop L4 is not installed, so the shop cannot open")
		return false
	end
	-- pcall'd: a fault in the L4 window never takes this rail down with it.
	local ok, used = pcall(alt.Invoke, alt, type(tab) == "string" and tab or "Shop")
	return ok and used == true
end

do
	local opener = Instance.new("BindableEvent")
	opener.Name = "ZyntraOpenTerminal"
	opener.Parent = player:WaitForChild("PlayerScripts")
	opener.Event:Connect(function(tab) openKioskShop(tab) end)
end

-- RAIL_OVER_WINDOWS_20261007. A rail press closes the OTHER open rail window
-- first, through that window's own synchronous bridge (each clears its flag
-- before Invoke returns), then opens its own through the usual route. Every
-- receiver still refuses over a modal, so a missing or failed close means
-- nothing opens -- never two windows stacked. Pressing the open window's own
-- button closes nothing: SHOPS / UPGRADES switch tab, REWARDS / WHEEL refuse.
-- Only the rail handlers and the lobby token pill's + (PlayerScripts.ZyntraRailSwitch,
-- below) call this; ZyntraOpenTerminal, J and DevPhoneCommand still refuse over
-- any modal.
local RAIL_WINDOWS = {
	ZyntraStoreOpen = {"ZyntraShopUIOpen", "close"},
	DailyRewardsOpen = {"ZyntraDailyUIOpen", "close"},
	LuckyWheelOpen = {"CloseLuckyWheel"},
	DevPhoneOpen = {"ZyntraDevUIOpen", false},
	-- MOBILE_QA_20261008: BADGES and HELP are screen-owning windows now (UIDevice), so a rail press has to close
	-- them like the others: the L4 windows refuse to open over somebody else's modal.
	AchievementsOpen = {"CloseAchievements"},
	HelpPanelOpen = {"CloseHelpPanel"},
}
local function switchFrom(keep)
	local playerScripts = player:WaitForChild("PlayerScripts")
	for flag, route in pairs(RAIL_WINDOWS) do
		local bridge = flag ~= keep and player:GetAttribute(flag) == true
			and playerScripts:FindFirstChild(route[1])
		if bridge and bridge:IsA("BindableFunction") then pcall(bridge.Invoke, bridge, route[2]) end
	end
end
-- The lobby token pill's + ("Zyntra Shop L4", owner 2026-10-08) switches like a
-- rail press, through RAIL_WINDOWS above: one table. Synchronous, so the closed
-- window's flag is down when Invoke returns. A do-block: no new top-level local.
do
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "ZyntraRailSwitch"
	bridge.OnInvoke = switchFrom
	bridge.Parent = player:WaitForChild("PlayerScripts")
end

-- Studio-only input seam for UIRegression (BriefingExclusionMatrix) and the
-- install QA probe: `kiosk` is the SHOPS button and returns the L4 shop's
-- answer. Every other action answers false; the terminal it drove is deleted.
if RunService:IsStudio() then
	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionZyntraStoreProbe"
	probe.OnInvoke = function(action)
		if action == "kiosk" then return openKioskShop() end
		return false
	end
	probe.Parent = gui
end

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
		devPhoneCommand.Event:Connect(toggleDevMenu)
	else
		warn("[ZyntraStore] PlayerScripts.DevPhoneCommand must be a BindableEvent")
		devPhoneCommand = nil
	end
end

openButton.Activated:Connect(function()
	-- UPGRADES opens the L4 shop on Upgrades. In a round this button is the touch
	-- developer's ZYNTRA // DEV chip, which opens the dev menu.
	-- In the lobby it switches away from any other open rail window first.
	if player:GetAttribute("InRound") == true then toggleDevMenu()
	else switchFrom("ZyntraStoreOpen"); openKioskShop("Upgrades") end
end)
-- Wrapped: Activated passes an InputObject, which openKioskShop would
-- otherwise be handed as a tab name.
shopButton.Activated:Connect(function() switchFrom("ZyntraStoreOpen"); openKioskShop() end)
-- Wrapped for the same reason, and both guard inside lobbyModalOpener.
rewardsButton.Activated:Connect(function() switchFrom("DailyRewardsOpen"); openDailyRewards() end)
wheelButton.Activated:Connect(function() switchFrom("LuckyWheelOpen"); openLuckyWheel() end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.J and devAllowed then
		if devPhoneCommand then devPhoneCommand:Fire() else toggleDevMenu() end
	end
end)

UIDevice.Changed:Connect(updateVisibility)

-- ── the lobby SHOP wall's buy bridge (card 88) ──────────────────────────────
-- The pedestals out on the concourse sell what LobbyShopDisplay reads from
-- ZyntraConfig: Passes, Products and Items. Their detail card
-- (StarterPlayerScripts."Shop Display Client") has no purchase path of its own:
-- it fires this with an item key, and the kind is decided by the same three
-- tables. It used to run the legacy Shop page's card buy, deleted on go-live.
-- Passes and Products prompt here, NOT through ShopData.purchase: the wall also
-- sells Tokens4 and Emergency Re-entry, which the L4 shop must refuse (owner
-- decision; the L4 harness asserts it). Token items DO go through it (below).
-- An unknown key is ignored rather than guessed at.
do
	local bridge = Instance.new("BindableEvent")
	bridge.Name = "ZyntraShopBuy"
	bridge.Parent = player:WaitForChild("PlayerScripts")
	bridge.Event:Connect(function(key)
		key = tostring(key)
		local pass = (Config.Passes or {})[key]
		local item = pass or (Config.Products or {})[key]
		if type(item) == "table" then
			if (tonumber(item.Id) or 0) <= 0 then
				warn("[ZyntraStore] " .. key .. ": Product ID is not configured yet")
			elseif pass then
				MarketplaceService:PromptGamePassPurchase(player, item.Id)
			else
				MarketplaceService:PromptProductPurchase(player, item.Id)
			end
		elseif type((Config.Items or {})[key]) == "table" then
			-- Token items: ShopData.purchase, the module instance "Zyntra Shop L4"
			-- started. It checks the balance and latches the key until the next
			-- profile push (or 6 s), so a second BUY during a slow write is not a
			-- second purchase: the server's 1 s per-action window cannot see one.
			local folder = ReplicatedStorage:FindFirstChild("ZyntraShopUI")
			local shopData = folder and folder:FindFirstChild("ShopData")
			if shopData and shopData:IsA("ModuleScript") then
				require(shopData).purchase(key)
			else
				warn("[ZyntraStore] ReplicatedStorage.ZyntraShopUI.ShopData is missing: the wall cannot sell " .. key)
			end
		end
	end)
end
