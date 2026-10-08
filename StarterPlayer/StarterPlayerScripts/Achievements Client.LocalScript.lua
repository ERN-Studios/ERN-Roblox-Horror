-- Achievements Client (2026-10-04). The server owns the record (ZyntraMonetization: `ZyntraAchievements`, the
-- comma-joined keys this player has unlocked); the list, names and icons are ZyntraConfig.Achievements.
--   TOAST: when a key appears that was not there before, a card names it for a few seconds (not on the first
--   read after joining: those were earned earlier).
--   PANEL: a BADGES button under the lobby's left rail opens the full list: unlocked ones in colour, locked ones
--   dimmed, secret ones as "???" until found. Lobby only.
-- This script took over the retired, disabled `Level 6 Lighting Controller`.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
-- MOBILE_QA_20261008: where things may stand is asked of UIDevice (the safe area and the rectangle a window may
-- take on THIS device), never of the raw camera viewport: that counts Roblox's top bar and a phone's cut-outs,
-- and it put the BADGES button under the screen's bottom edge and the panel over the top bar on phones.
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local LIST = Config.Achievements or {}
local BG, CREAM, TEAL, AMBER = Color3.fromRGB(22, 29, 32), Color3.fromRGB(243, 236, 218), Color3.fromRGB(79, 173, 170), Color3.fromRGB(237, 168, 39)

local gui = Instance.new("ScreenGui")
gui.Name = "Achievements"
gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = false, false, 25
gui.Parent = player:WaitForChild("PlayerGui")

local function unlocked()
	local have = {}
	for key in string.gmatch(player:GetAttribute("ZyntraAchievements") or "", "[^,]+") do have[key] = true end
	return have
end
local function icon(parent, entry, size)
	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.Size, image.BackgroundColor3, image.BorderSizePixel = UDim2.fromOffset(size, size), BG, 0
	image.Image = (entry.Icon or 0) ~= 0 and ("rbxassetid://" .. string.format("%.0f", entry.Icon)) or ""
	image.Parent = parent
	Instance.new("UICorner", image).CornerRadius = UDim.new(1, 0)
	return image
end

-- the toast ------------------------------------------------------------------------------------------------
local toast = Instance.new("Frame")
toast.Name = "Unlocked"
toast.AnchorPoint, toast.Position, toast.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, -170), UDim2.fromOffset(340, 76)
toast.BackgroundColor3, toast.BorderSizePixel, toast.Visible = BG, 0, false   -- only drawn while it is down
toast.Parent = gui
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 12)
local toastStroke = Instance.new("UIStroke", toast)
toastStroke.Color, toastStroke.Thickness = AMBER, 2
local toastIcon = icon(toast, {Icon = 0}, 56)
toastIcon.Position = UDim2.fromOffset(10, 10)
local function line(parent, name, y, size, colour, font)
	local label = Instance.new("TextLabel")
	label.Name, label.BackgroundTransparency = name, 1
	label.Position, label.Size = UDim2.fromOffset(78, y), UDim2.new(1, -90, 0, size + 6)
	label.Font, label.TextSize, label.TextColor3 = font, size, colour
	label.TextXAlignment, label.TextTruncate = Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end
line(toast, "Kicker", 10, 12, AMBER, Enum.Font.Code).Text = "ACHIEVEMENT UNLOCKED"
local toastName = line(toast, "Name", 28, 20, CREAM, Enum.Font.GothamBold)
-- LUNA_KIND_20261008: an achievement with a `Reward` line (a gift, see ZyntraConfig.Achievements) shows it under the
-- name, and the toast is that much taller for it.
local toastReward = line(toast, "Reward", 55, 13, TEAL, Enum.Font.GothamMedium)
toastReward.Visible = false
local queue, showing = {}, false
-- MOBILE_HUD_20261007: the toast drops in at the top of the screen, and on a phone that is where RoundUI's PARTY
-- DOWN card is (it takes the screen from y 61 to 329 of 390): "Found You" unlocked at the very moment the card
-- came up and was drawn under it, unseen. A toast waits for the card to go; one that is already down when the card
-- arrives is taken away and shown again afterwards.
local function cardUp() return player:GetAttribute("PartyDownCardOpen") == true end
local function showNext()
	if showing or #queue == 0 then return end
	showing = true
	local waited = os.clock()
	while cardUp() and os.clock() - waited < 60 do task.wait(0.25) end
	local entry = table.remove(queue, 1)
	toastName.Text = entry.Name
	toastReward.Text, toastReward.Visible = entry.Reward or "", entry.Reward ~= nil
	toast.Size = UDim2.fromOffset(340, entry.Reward and 86 or 76)
	toastIcon.Image = (entry.Icon or 0) ~= 0 and ("rbxassetid://" .. string.format("%.0f", entry.Icon)) or ""
	toast.Visible = true
	local ping = Instance.new("Sound")
	ping.SoundId, ping.Volume = "rbxasset://sounds/electronicpingshort.wav", 0.35
	ping.Parent = gui
	ping:Play()
	ping.Ended:Once(function() ping:Destroy() end)
	TweenService:Create(toast, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 0, 10)}):Play()
	task.spawn(function()
		local shown, again = os.clock(), false
		while os.clock() - shown < 4 do
			if cardUp() and os.clock() - shown < 3 then again = true; break end
			task.wait(0.2)
		end
		TweenService:Create(toast, TweenInfo.new(0.3), {Position = UDim2.new(0.5, 0, 0, -170)}):Play()
		task.wait(0.4)
		toast.Visible = false
		if again then table.insert(queue, 1, entry) end
		showing = false
		showNext()
	end)
end

-- the panel ------------------------------------------------------------------------------------------------
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint, panel.Position, panel.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(640, 560)
panel.BackgroundColor3, panel.BorderSizePixel, panel.Visible = BG, 0, false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
local edge = Instance.new("UIStroke", panel)
edge.Color, edge.Thickness = TEAL, 2
local scale = Instance.new("UIScale", panel)
local fit                                                 -- defined under the grid it lays out
local title = Instance.new("TextLabel")
title.BackgroundTransparency, title.Position, title.Size = 1, UDim2.fromOffset(24, 16), UDim2.new(1, -110, 0, 32)
title.Font, title.TextSize, title.TextColor3, title.TextXAlignment = Enum.Font.GothamBlack, 26, CREAM, Enum.TextXAlignment.Left
title.Parent = panel
local close = Instance.new("TextButton")
close.Name, close.Text, close.TextSize, close.Font, close.TextColor3 = "Close", "×", 26, Enum.Font.GothamBold, CREAM
close.Position, close.Size, close.BackgroundColor3, close.BorderSizePixel = UDim2.new(1, -56, 0, 12), UDim2.fromOffset(44, 44), Color3.fromRGB(38, 48, 52), 0
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)
local footer = Instance.new("TextLabel")
footer.BackgroundTransparency, footer.Position, footer.Size = 1, UDim2.new(0, 24, 1, -54), UDim2.new(1, -48, 0, 40)
footer.Font, footer.TextSize, footer.TextColor3, footer.TextWrapped = Enum.Font.GothamMedium, 15, CREAM, true
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text = "Tap a badge to see how to earn it."
footer.Parent = panel
local grid = Instance.new("ScrollingFrame")
grid.Name = "Grid"
grid.BackgroundTransparency, grid.BorderSizePixel, grid.Position, grid.Size = 1, 0, UDim2.fromOffset(20, 62), UDim2.new(1, -40, 1, -124)
grid.CanvasSize, grid.AutomaticCanvasSize, grid.ScrollingDirection = UDim2.new(), Enum.AutomaticSize.Y, Enum.ScrollingDirection.Y
grid.ScrollBarThickness, grid.ScrollBarImageColor3 = 5, TEAL
grid.Parent = panel
local layout = Instance.new("UIGridLayout", grid)
layout.SortOrder = Enum.SortOrder.LayoutOrder
-- The authored panel is 640 x 560 and holds every badge in four rows (five columns hold twenty; more badges than
-- that get narrower tiles, never a fifth row). Where the device gives a window less than that, the panel takes what
-- there is and the grid scrolls: a phone keeps tiles of full size to tap and names it can read, instead of the
-- whole panel shrunk to half.
fit = function()
	-- the rectangle the lobby's own windows take (Zyntra Daily L4's rule): the modal viewport, on touch the whole
	-- safe height, and never under the rail, which stays up over a window (ZyntraRailRight is its right edge)
	local device = UIDevice.Layout()
	local area = device.ModalViewport
	local left, top, room, tall = area.Left, area.Top, area.Width, area.Height
	if device.IsTouch then top, tall = device.Safe.Top, device.Safe.Bottom - device.Safe.Top end
	local railRight = player:GetAttribute("ZyntraRailRight")
	if type(railRight) == "number" and left < railRight + 8 then
		room, left = room - (railRight + 8 - left), railRight + 8
	end
	local floor = device.IsTouch and 1 or 0.85
	local s = math.clamp(math.min(room / 640, tall / 560), floor, 1.25)
	local width, height = math.min(640, math.floor(room / s)), math.min(560, math.floor(tall / s))
	scale.Scale = s
	panel.Size = UDim2.fromOffset(width, height)
	local x, y = UIDevice.LocalOffset(gui, left + room / 2, top + tall / 2)
	panel.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	local inner = width - 40
	if inner >= 600 then
		local columns = math.max(5, math.ceil(#LIST / 4))
		layout.CellSize = UDim2.fromOffset(columns == 5 and 112 or math.floor((600 - (columns - 1) * 8) / columns), 104)
		layout.CellPadding = UDim2.fromOffset(columns == 5 and 10 or 8, 6)
	else
		local columns = math.max(2, math.floor((inner + 8) / 112))
		layout.CellSize = UDim2.fromOffset(math.floor((inner - 6 - (columns - 1) * 8) / columns), 104)
		layout.CellPadding = UDim2.fromOffset(8, 6)
	end
	footer.TextSize = width < 520 and 13 or 15
	title.TextSize = width < 520 and 18 or 26
end
fit()
UIDevice.Changed:Connect(fit)
player:GetAttributeChangedSignal("ZyntraRailRight"):Connect(fit)
local tiles = {}
for index, entry in ipairs(LIST) do
	local tile = Instance.new("TextButton")
	tile.Name, tile.LayoutOrder, tile.Text, tile.AutoButtonColor = entry.Key, index, "", false
	tile.BackgroundColor3, tile.BorderSizePixel = Color3.fromRGB(30, 39, 43), 0
	tile.Parent = grid
	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 10)
	local image = icon(tile, entry, 62)
	image.AnchorPoint, image.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 6)
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency, name.Position, name.Size = 1, UDim2.new(0, 4, 1, -32), UDim2.new(1, -8, 0, 28)
	name.Font, name.TextSize, name.TextWrapped, name.TextColor3 = Enum.Font.GothamBold, 11, true, CREAM
	name.Parent = tile
	tiles[entry.Key] = {entry = entry, image = image, name = name, tile = tile}
	tile.Activated:Connect(function()
		local have = unlocked()[entry.Key] == true
		footer.Text = (entry.Secret and not have) and "???  ·  A secret. Keep looking." or (entry.Name .. "  ·  " .. entry.Text)
	end)
end
-- While it is up the panel owns the screen like the lobby's other windows (UIDevice.SCREEN_OWNING_MODALS): it
-- publishes AchievementsOpen, draws at their height (117, under the rail's 119), and gives way when one of them opens.
local OTHER_WINDOWS = {"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen", "LuckyWheelOpen",
	"DailyRewardsOpen", "HelpPanelOpen"}
local refresh
local function setOpen(on)
	if on then
		local switch = player:FindFirstChild("PlayerScripts") and player.PlayerScripts:FindFirstChild("ZyntraRailSwitch")
		if switch and switch:IsA("BindableFunction") then pcall(switch.Invoke, switch, "AchievementsOpen") end
	end
	panel.Visible = on
	gui.DisplayOrder = on and 117 or 25
	player:SetAttribute("AchievementsOpen", on or nil)
	UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())   -- the thumbstick and RUN stand down under it
	if on then fit() refresh() end
end
UIDevice.OnScreenOwningModalChanged(function()
	if not panel.Visible then return end
	for _, flag in ipairs(OTHER_WINDOWS) do
		if player:GetAttribute(flag) == true then setOpen(false) return end
	end
end)
gui:GetAttributeChangedSignal("Toggle"):Connect(function() setOpen(not panel.Visible) end)   -- for tests: any change
do   -- the rail closes this window through here before it opens one of its own (ZyntraStore.RAIL_WINDOWS)
	local closer = Instance.new("BindableFunction")
	closer.Name = "CloseAchievements"
	closer.OnInvoke = function() setOpen(false) return true end
	closer.Parent = player:WaitForChild("PlayerScripts")
end
refresh = function()
	local have, count = unlocked(), 0
	for key, tile in pairs(tiles) do
		local on = have[key] == true
		if on then count += 1 end
		tile.image.ImageTransparency = on and 0 or 0.78
		tile.name.TextTransparency = on and 0 or 0.55
		tile.name.Text = (tile.entry.Secret and not on) and "???" or tile.entry.Name
	end
	title.Text = string.format("ACHIEVEMENTS   %d / %d", count, #LIST)
end

-- the button, under the lobby's left rail --------------------------------------------------------------------
local open = Instance.new("TextButton")
open.Name, open.Text, open.TextSize, open.Font, open.TextColor3 = "Open", "Badges", 13, Enum.Font.GothamBold, CREAM
open.BackgroundColor3, open.BorderSizePixel, open.Size = BG, 0, UDim2.fromOffset(64, 30)
open.Parent = gui
Instance.new("UICorner", open).CornerRadius = UDim.new(0, 8)
local openStroke = Instance.new("UIStroke", open)
openStroke.Color, openStroke.Thickness, openStroke.ApplyStrokeMode = TEAL, 1.5, Enum.ApplyStrokeMode.Border
local function place()
	local store = player.PlayerGui:FindFirstChild("ZyntraStore")
	local lowest, right = nil, 0
	for _, item in ipairs(store and store:GetChildren() or {}) do
		if item:IsA("GuiButton") and item.Visible and item.AbsolutePosition.X < 120 and item.AbsoluteSize.X < 140 then
			if not lowest or item.AbsolutePosition.Y > lowest.AbsolutePosition.Y then lowest = item end
			right = math.max(right, item.AbsolutePosition.X + item.AbsoluteSize.X)
		end
	end
	local inLobby = player:GetAttribute("InRound") ~= true and workspace:GetAttribute("ReservedRoundServer") ~= true
		and player:GetAttribute("LuckyWheelOpen") ~= true and player:GetAttribute("LobbyLoadingDone") == true
	open.Visible = inLobby and lowest ~= nil and not UIDevice.ScreenOwningModalOpen()
	if not lowest then return end
	-- under the rail's lowest button where the safe area still has 30 px for it, otherwise beside that button's foot
	-- (a phone's rail runs to the bottom edge). All in this ScreenGui's own space, which is the safe area's.
	local bottom = UIDevice.Layout().Safe.Bottom - 6
	local below = lowest.AbsolutePosition.Y + lowest.AbsoluteSize.Y + 8
	open.Size = UDim2.fromOffset(lowest.AbsoluteSize.X, 30)
	if below + 30 <= bottom then
		open.Position = UDim2.fromOffset(lowest.AbsolutePosition.X, below)
	else
		open.Position = UDim2.fromOffset(right + 8, math.min(lowest.AbsolutePosition.Y + lowest.AbsoluteSize.Y, bottom) - 30)
	end
	if not inLobby and panel.Visible then setOpen(false) end
end
task.spawn(function()
	while true do
		place()
		task.wait(0.5)
	end
end)
open.Activated:Connect(function() setOpen(not panel.Visible) end)
close.Activated:Connect(function() setOpen(false) end)
UserInputService.InputBegan:Connect(function(input, processed)
	if panel.Visible and not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then setOpen(false) end
end)

-- what changed -----------------------------------------------------------------------------------------------
local known = nil
local function changed()
	local have = unlocked()
	if known then
		for _, entry in ipairs(LIST) do
			if have[entry.Key] and not known[entry.Key] then table.insert(queue, entry) end
		end
		showNext()
	end
	if player:GetAttribute("ZyntraAchievements") ~= nil then known = have end
	if panel.Visible then refresh() end
end
player:GetAttributeChangedSignal("ZyntraAchievements"):Connect(changed)
changed()
