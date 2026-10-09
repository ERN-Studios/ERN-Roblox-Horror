-- Friend Boost Client  (FRIEND_BOOST_20260916, owner brief section 4)
--
-- The lobby chip for the Friend Boost, and nothing else. It DRAWS two replicated
-- Player attributes the server publishes -- FriendBoostFriends and
-- FriendBoostPercent -- and offers Roblox's own invite prompt.
--
-- IT SENDS NOTHING AND GRANTS NOTHING. Pressing INVITE FRIENDS opens Roblox's
-- invite UI and that is the whole of it: no request reaches the server, no
-- reward follows the press, and the bonus itself is counted server-side at
-- completion from verified friendships (see ServerScriptService.FriendBoost).
-- A client that rewrites these attributes lies only to its own screen.
--
-- WHERE IT IS: directly UNDER the lobby token pill, right-aligned to it (owner,
-- 2026-10-07: "tokens is at the top right corner, then the friend boost is
-- underneath"). The pill is "Zyntra Shop L4"'s PlayerGui.ZyntraLobbyPillL4.
-- TokenPill; with no pill drawn the chip takes the corner itself. Over a rail
-- window (Shop, Dev, Daily, Wheel) the chip stays up (owner, 2026-10-08), but
-- only beside a drawn pill; where the pill docks in the topbar band
-- (TokenPill.Docked) the chip docks LEFT of it, centred on it, as the line.
--
-- HOW IT LOOKS (owner, 2026-10-07: "on phone it needs to be very subtle"), in
-- the L4 Zyntra Flat palette and fonts the pill above it uses:
--   pointer: a compact box no wider than the pill -- FRIEND BOOST +N% in gold,
--            one short line, a small INVITE FRIENDS button;
--   touch:   one small translucent line, FRIENDS +N%. The whole line is the
--            invite button, through an invisible 44 px tap area hanging from it.
--
-- LOBBY ONLY (owner, 2026-09-17: never inside a
-- game). "Lobby" is read off the world, not off one flag: the chip shows only
-- while the player's root is inside the selected lobby model's bounding box AND no
-- round flag is up (InRound, RoundActive, a round loading). A level server has
-- no ServerLobby at all; in Studio the lobby is parked away while a Level 2/3
-- round runs and a Level 1 maze is built far outside it (measured 2026-09-17:
-- the box is 186 x 59 x 287 studs about (0.7, 58.4, -760.3), the maze at z -15,
-- Level 2 at z -349). The queue host modal and re-entry still stand it down, and
-- so do rounds; the Lucky Wheel's takeover exempts this gui (owner, 2026-10-08).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local player = Players.LocalPlayer
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
-- The L4 Zyntra Flat palette, the one the token pill above the chip is drawn in.
local P = require(ReplicatedStorage:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder")).Palette
local playerGui = player:WaitForChild("PlayerGui")

local PERCENT_PER_FRIEND = Config.FriendBoost.PercentPerFriend
local GOLD = Color3.fromRGB(255, 203, 79)
local CONDENSED = "rbxasset://fonts/families/RobotoCondensed.json"
local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local GAP = 6 -- under the token pill
-- Pointer: the box.
local BOX_WIDTH = 160 -- only when there is no pill to match
local PAD = 8
local BOOST_HEIGHT = 16
local DETAIL_HEIGHT = 14
local BUTTON_HEIGHT = 30
-- Touch: the line, and the tap area hanging from its top.
local LINE_WIDTH = 104
local LINE_HEIGHT = 24
local TAP = 44

local gui = Instance.new("ScreenGui")
gui.Name = "FriendBoostGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- the pill gui's insets: an offset in one is the same in the other
gui.Parent = playerGui

local chip = Instance.new("Frame")
chip.Name = "FriendBoostChip"
chip.Visible = false
chip.Parent = gui

local boost = Instance.new("TextLabel")
boost.Name = "BoostLabel"
boost.FontFace = Font.new(CONDENSED, Enum.FontWeight.Bold)
boost.TextColor3 = GOLD
boost.Text = "FRIEND BOOST +0%"
boost.Parent = chip

local detail = Instance.new("TextLabel")
detail.Name = "FriendsLabel"
detail.BackgroundTransparency = 1
detail.FontFace = Font.new(CONDENSED, Enum.FontWeight.Medium)
detail.TextColor3 = P.Sage
detail.TextXAlignment = Enum.TextXAlignment.Left
detail.TextSize = 11
detail.Text = ""
detail.Parent = chip

local invite = Instance.new("TextButton")
invite.Name = "InviteButton"
invite.AutoButtonColor = true
invite.BorderSizePixel = 0
invite.BackgroundColor3 = P.RailTeal
invite.FontFace = Font.new(MONTSERRAT, Enum.FontWeight.Bold)
invite.TextColor3 = P.Tile
invite.TextSize = 12
invite.Visible = false
invite.Parent = chip
local inviteCorner = Instance.new("UICorner")
inviteCorner.CornerRadius = UDim.new(0, 8)
inviteCorner.Parent = invite

-- Announce the chip's rectangle so anything that lays out around the touch
-- controls knows it is there; on touch the chip IS the tap area. The chip's OWN
-- placement takes only the right/top edge -- the token pill's, or TopRightPanel's
-- -- and keeps a content-sized height: TopRightPanel's height is "the room above
-- the registered controls", and a panel that both registers itself and sized
-- itself from that answer would shrink to zero, un-draw, grow back and oscillate
-- forever. The pill never reads this chip, so following it cannot loop either.
UIDevice.RegisterControlRect("FriendBoost", chip)

local inviteAllowed = false
local phone = false
local docked = false -- beside a pill docked in the topbar band (owner, 2026-10-08)
local wasOver = false -- a window closing takes a pad's focus off the chip (owner, 2026-10-08)
local followed = nil -- the token pill whose rectangle is being followed
local applyLayout, refresh

-- The token pill when it is drawn. "Zyntra Shop L4" makes it late (once its
-- template loads) and moves or hides it on its own, so its rectangle is
-- followed through its own signals rather than polled.
local function tokenPill(): GuiObject?
	local pillGui = playerGui:FindFirstChild("ZyntraLobbyPillL4")
	local pill = pillGui and pillGui:FindFirstChild("TokenPill")
	if not pill then return nil end
	if pill ~= followed then
		followed = pill
		-- refresh too: a pill hidden over a window takes the chip with it at once.
		for _, property in ipairs({"Visible", "AbsolutePosition", "AbsoluteSize"}) do
			pill:GetPropertyChangedSignal(property):Connect(function() applyLayout(); refresh() end)
		end
		pill:GetAttributeChangedSignal("Docked"):Connect(function() applyLayout(); refresh() end)
	end
	return if pill.Visible then pill else nil
end

local function paint()
	local count = math.max(0, math.floor(tonumber(player:GetAttribute("FriendBoostFriends")) or 0))
	local percent = math.max(0, math.floor(tonumber(player:GetAttribute("FriendBoostPercent")) or 0))
	boost.Text = (if phone then "FRIENDS +%d%%" else "FRIEND BOOST +%d%%"):format(percent)
	if count <= 0 then
		detail.Text = ("+%d%% PER FRIEND"):format(PERCENT_PER_FRIEND)
	elseif count == 1 then
		detail.Text = "1 FRIEND ON THIS SERVER"
	else
		detail.Text = ("%d FRIENDS ON THIS SERVER"):format(count)
	end
end

applyLayout = function()
	local pill = tokenPill()
	docked = pill ~= nil and pill:GetAttribute("Docked") == true
	phone = UIDevice.Layout().IsTouch == true or docked -- docked: the compact line, on PC too
	local width = if phone then LINE_WIDTH elseif pill then pill.AbsoluteSize.X else BOX_WIDTH
	local height = if phone then (if inviteAllowed then TAP else LINE_HEIGHT)
		else PAD + BOOST_HEIGHT + DETAIL_HEIGHT + (if inviteAllowed then 6 + BUTTON_HEIGHT else 0) + PAD
	local x, y
	if pill and docked then
		-- In the topbar band, LEFT of the docked pill and centred on it (owner 2026-10-08).
		local origin = (pill.Parent :: any).AbsolutePosition
		x = pill.AbsolutePosition.X - origin.X - GAP - width
		y = pill.AbsolutePosition.Y - origin.Y + (pill.AbsoluteSize.Y - height) / 2
	elseif pill then
		-- Both guis use DeviceSafeInsets, so an offset in the pill's gui is the
		-- same offset in this one (also under a forced fixture viewport).
		local origin = (pill.Parent :: any).AbsolutePosition
		x = pill.AbsolutePosition.X + pill.AbsoluteSize.X - origin.X - width
		y = pill.AbsolutePosition.Y + pill.AbsoluteSize.Y - origin.Y + GAP
	else
		local corner = UIDevice.TopRightPanel(width, height)
		x, y = UIDevice.LocalOffset(gui, corner.Right - width, corner.Top)
	end
	chip.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	chip.Size = UDim2.fromOffset(width, height)
	UIStyle.panel(chip, {Background = P.Ink, Transparency = if phone then 1 else 0,
		Stroke = P.Line, StrokeTransparency = if phone then 1 else 0})
	UIStyle.panel(boost, {Background = P.Ink, Transparency = if phone then 0.35 else 1,
		Radius = LINE_HEIGHT / 2, Stroke = P.Line, StrokeTransparency = if phone then 0.5 else 1})
	detail.Visible = not phone
	if phone then
		boost.Position = UDim2.fromOffset(0, if docked then (height - LINE_HEIGHT) / 2 else 0)
		boost.Size = UDim2.fromOffset(width, LINE_HEIGHT)
		boost.TextSize = 12
		boost.TextXAlignment = Enum.TextXAlignment.Center
		invite.Position = UDim2.fromOffset(0, 0)
		invite.Size = UDim2.fromOffset(width, TAP)
		invite.BackgroundTransparency = 1
		invite.Text = ""
	else
		local inner = width - PAD * 2
		boost.Position = UDim2.fromOffset(PAD, PAD)
		boost.Size = UDim2.fromOffset(inner, BOOST_HEIGHT)
		boost.TextSize = 13
		boost.TextXAlignment = Enum.TextXAlignment.Left
		detail.Position = UDim2.fromOffset(PAD, PAD + BOOST_HEIGHT)
		detail.Size = UDim2.fromOffset(inner, DETAIL_HEIGHT)
		invite.Position = UDim2.fromOffset(PAD, PAD + BOOST_HEIGHT + DETAIL_HEIGHT + 6)
		invite.Size = UDim2.fromOffset(inner, BUTTON_HEIGHT)
		invite.BackgroundTransparency = 0
		invite.Text = "INVITE FRIENDS"
	end
	paint()
end

-- The lobby's box, re-measured only when the model or its pivot changes: the
-- Studio lobby is PARKED (moved) for a Level 2/3 round, and a box measured
-- before the move would still say "lobby" about a spot that is now a level.
local LOBBY_MARGIN = 6
local lobbyBox = nil
local function lobbyBounds()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
	-- Follow only the server-selected, complete lobby; preserve the safe fallback.
	if spawn and spawn:IsA("SpawnLocation")
		and spawn:GetAttribute("LobbySpawnFloorModelName") == "LobbyReimaginedPreview" then
		local revised = workspace:FindFirstChild("LobbyReimaginedPreview")
		if revised and revised:IsA("Model") and revised:GetAttribute("LobbyReimaginedOwned") == true
			and revised:GetAttribute("Ready") == true then lobby = revised end
	end
	if not lobby or not lobby:IsA("Model") then
		lobbyBox = nil
		return nil
	end
	local pivot = lobby:GetPivot().Position
	if lobbyBox and lobbyBox.Model == lobby and lobbyBox.PX == pivot.X
		and lobbyBox.PY == pivot.Y and lobbyBox.PZ == pivot.Z then
		return lobbyBox
	end
	local cf, size = lobby:GetBoundingBox()
	lobbyBox = {
		Model = lobby, PX = pivot.X, PY = pivot.Y, PZ = pivot.Z,
		X = cf.Position.X, Y = cf.Position.Y, Z = cf.Position.Z,
		HX = size.X / 2 + LOBBY_MARGIN, HY = size.Y / 2 + LOBBY_MARGIN, HZ = size.Z / 2 + LOBBY_MARGIN,
	}
	return lobbyBox
end

local function inLobby(): boolean
	if player:GetAttribute("InRound") == true then return false end
	if workspace:GetAttribute("RoundActive") == true then return false end
	if workspace:GetAttribute("RoundLoadingState") == "loading" then return false end
	local box = lobbyBounds()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not box or not root then return false end
	local position = root.Position
	return math.abs(position.X - box.X) <= box.HX
		and math.abs(position.Y - box.Y) <= box.HY
		and math.abs(position.Z - box.Z) <= box.HZ
end

refresh = function()
	local over = UIDevice.ScreenOwningModalOpen()
	if wasOver and not over then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(gui) then GuiService.SelectedObject = nil end
	end
	wasOver = over
	local shown = inLobby() and player:GetAttribute("QueueModalOpen") ~= true
		and player:GetAttribute("ZyntraReentryOpen") ~= true
		and (not over or tokenPill() ~= nil) -- over a window only beside the pill, never on its Close
	chip.Visible = shown
	-- UI_REGRESSION_20260923: the button stands down WITH the chip -- Visible,
	-- Active and Selectable together, UIDevice's contract for every registered
	-- control -- instead of staying Active inside a hidden chip under the queue
	-- modal (UIRegression queue-modal lane: "1 active objects: InviteButton").
	UIDevice.SetInteractive(invite, inviteAllowed and shown)
	gui.DisplayOrder = if shown and over then 119 else 60
end

invite.Activated:Connect(function()
	if not inviteAllowed then return end
	-- Roblox's own invite flow. No auto-invite, and nothing is granted for
	-- opening it: the boost is earned by PLAYING the round together.
	pcall(function() SocialService:PromptGameInvite(player) end)
end)

task.spawn(function()
	-- CanSendGameInviteAsync is a web call, and a THROWN answer is not a "no" --
	-- the same rule the server's friendship lookups follow. Only a definitive
	-- false (or three failures) hides the button for the session.
	for attempt = 1, 3 do
		local ok, allowed = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok then
			inviteAllowed = allowed == true
			break
		end
		if attempt < 3 then task.wait(5) end
	end
	applyLayout()
	refresh()
end)

for _, attribute in ipairs({"FriendBoostFriends", "FriendBoostPercent"}) do
	player:GetAttributeChangedSignal(attribute):Connect(paint)
end
player:GetAttributeChangedSignal("InRound"):Connect(refresh)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(refresh)
workspace:GetAttributeChangedSignal("RoundLoadingState"):Connect(refresh)
UIDevice.OnScreenOwningModalChanged(refresh)
-- The position half of "in the lobby" has no signal of its own; twice a second
-- is fast enough for a chip and costs one box compare.
local pollAccum = 0
RunService.Heartbeat:Connect(function(delta)
	pollAccum += delta
	if pollAccum < 0.5 then return end
	pollAccum = 0
	refresh()
end)
UIDevice.Changed:Connect(function()
	applyLayout()
	refresh()
end)
-- The token pill's gui arriving is the one change its own signals cannot announce.
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "ZyntraLobbyPillL4" then applyLayout() end
end)

applyLayout()
refresh()
