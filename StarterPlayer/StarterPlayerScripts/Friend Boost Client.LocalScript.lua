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
-- WHERE IT IS: the top-right panel, LOBBY ONLY (owner, 2026-09-17: never inside a
-- game). "Lobby" is read off the world, not off one flag: the chip shows only
-- while the player's root is inside the ServerLobby model's bounding box AND no
-- round flag is up (InRound, RoundActive, a round loading). A level server has
-- no ServerLobby at all; in Studio the lobby is parked away while a Level 2/3
-- round runs and a Level 1 maze is built far outside it (measured 2026-09-17:
-- the box is 186 x 59 x 287 studs about (0.7, 58.4, -760.3), the maze at z -15,
-- Level 2 at z -349). Any screen-owning modal also stands it down, which is what
-- keeps it off the Lucky Wheel's takeover screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local player = Players.LocalPlayer
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local playerGui = player:WaitForChild("PlayerGui")

local PERCENT_PER_FRIEND = Config.FriendBoost.PercentPerFriend
local GOLD = Color3.fromRGB(255, 203, 79)
local PAD = 10
local BOOST_HEIGHT = 20
local DETAIL_HEIGHT = 26 -- two wrapped lines of the longest copy

local gui = Instance.new("ScreenGui")
gui.Name = "FriendBoostGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Parent = playerGui

local chip = Instance.new("Frame")
chip.Name = "FriendBoostChip"
chip.Visible = false
chip.Parent = gui
UIStyle.panel(chip, {Radius = UIStyle.Radius.Panel})

local boost = Instance.new("TextLabel")
boost.Name = "BoostLabel"
boost.BackgroundTransparency = 1
boost.Font = Enum.Font.GothamBlack
boost.TextColor3 = GOLD
boost.TextXAlignment = Enum.TextXAlignment.Left
boost.Text = "FRIEND BOOST +0%"
boost.Parent = chip

local detail = Instance.new("TextLabel")
detail.Name = "FriendsLabel"
detail.BackgroundTransparency = 1
detail.Font = Enum.Font.Gotham
detail.TextColor3 = UIStyle.Color.Muted
detail.TextXAlignment = Enum.TextXAlignment.Left
detail.TextYAlignment = Enum.TextYAlignment.Top
detail.TextWrapped = true
detail.Text = ""
detail.Parent = chip

local invite = Instance.new("TextButton")
invite.Name = "InviteButton"
invite.AutoButtonColor = true
invite.Text = "INVITE FRIENDS"
invite.Visible = false
invite.Parent = chip
UIStyle.button(invite)

-- Announce the chip's rectangle so anything that lays out around the touch
-- controls knows it is there. The chip's OWN placement deliberately takes only
-- the left/top/width from TopRightPanel and keeps a content-sized height: that
-- helper's height is "the room above the registered controls", and a panel that
-- both registers itself and sized itself from that answer would shrink to zero,
-- un-draw, grow back and oscillate forever.
UIDevice.RegisterControlRect("FriendBoost", chip)

local inviteAllowed = false

local function applyLayout()
	local layout = UIDevice.Layout()
	local tap = layout.IsTouch and 44 or 30
	local buttonRow = inviteAllowed and (6 + tap) or 0
	local height = PAD + BOOST_HEIGHT + DETAIL_HEIGHT + buttonRow + PAD
	local rect = UIDevice.TopRightPanel(layout.Narrow and 220 or 260, height)
	local width = rect.Width
	local x, y = UIDevice.LocalOffset(gui, rect.Left, rect.Top)
	chip.Position = UDim2.fromOffset(x, y)
	chip.Size = UDim2.fromOffset(width, height)

	local inner = width - PAD * 2
	boost.Position = UDim2.fromOffset(PAD, PAD)
	boost.Size = UDim2.fromOffset(inner, BOOST_HEIGHT)
	boost.TextSize = layout.Narrow and 15 or 16
	detail.Position = UDim2.fromOffset(PAD, PAD + BOOST_HEIGHT)
	detail.Size = UDim2.fromOffset(inner, DETAIL_HEIGHT)
	detail.TextSize = 11
	invite.Position = UDim2.fromOffset(PAD, PAD + BOOST_HEIGHT + DETAIL_HEIGHT + 6)
	invite.Size = UDim2.fromOffset(inner, tap)
	invite.TextSize = 13
end

local function paint()
	local count = math.max(0, math.floor(tonumber(player:GetAttribute("FriendBoostFriends")) or 0))
	local percent = math.max(0, math.floor(tonumber(player:GetAttribute("FriendBoostPercent")) or 0))
	boost.Text = ("FRIEND BOOST +%d%%"):format(percent)
	if count <= 0 then
		detail.Text = ("INVITE FRIENDS TO EARN +%d%% PER FRIEND"):format(PERCENT_PER_FRIEND)
	elseif count == 1 then
		detail.Text = "1 FRIEND ON THIS SERVER"
	else
		detail.Text = ("%d FRIENDS ON THIS SERVER"):format(count)
	end
end

-- The lobby's box, re-measured only when the model or its pivot changes: the
-- Studio lobby is PARKED (moved) for a Level 2/3 round, and a box measured
-- before the move would still say "lobby" about a spot that is now a level.
local LOBBY_MARGIN = 6
local lobbyBox = nil
local function lobbyBounds()
	local lobby = workspace:FindFirstChild("ServerLobby")
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

local function refresh()
	chip.Visible = inLobby() and not UIDevice.ScreenOwningModalOpen()
	invite.Visible = inviteAllowed
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

applyLayout()
paint()
refresh()
