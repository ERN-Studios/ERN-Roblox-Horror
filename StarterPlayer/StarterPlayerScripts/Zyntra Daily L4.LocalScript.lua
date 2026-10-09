-- Zyntra Daily L4  (StarterPlayerScripts, DAILY_UI_L4_20261007)
--
-- THE Daily Rewards window: the Framewisp import
-- ReplicatedStorage.ZyntraShopUI.DailyRewards_L4, mounted and fitted exactly
-- like "Zyntra Shop L4". It replaced, and deleted, "Daily Rewards Client" and
-- ReplicatedStorage.ZyntraDailyRewardsPage (owner 2026-10-07: "Den skal altsaa
-- vaere figma versionen").
--
-- DATA. ShopData is the one profile copy (ZyntraGetProfile, then every
-- ZyntraProfileChanged) and the one dispatcher. CLAIM is ShopData.claim, the
-- legacy remote and payload: ZyntraAction("ClaimPlaytimeReward", {Minutes = n}).
-- Nothing is granted or claimed here; ZyntraMonetization decides and pushes.
--
-- OPENING. PlayerScripts.OpenDailyRewards (a BindableEvent: ZyntraStore's rail
-- REWARDS and ZyntraOpenTerminal "Rewards" fire it) and the bridge
-- PlayerScripts.ZyntraDailyUIOpen:Invoke("open" | "close" | "toggle"), which
-- answers true only when the window is open afterwards. Never yields: a rail
-- press over this window closes it with "close", which has cleared
-- DailyRewardsOpen by the time Invoke returns (ZyntraStore switchFrom, 2026-10-07).
--
-- MODAL CONTRACT (the legacy one). Lobby only: refused while InRound,
-- QueueModalOpen or any other screen-owning modal. Publishes DailyRewardsOpen
-- (true, or nil when closed -- never false), derives touch suppression from the
-- whole modal set, binds gamepad B. X, Escape and B close it; so do InRound,
-- QueueModalOpen, workspace.RoundActive and the Roblox menu.
--
-- WHAT THE IMPORT LACKS and this file supplies: the LUCKY WHEEL row (the export
-- frame deleted it; it is built from a clone of the last research row), the art
-- (four placeholders), the eyebrow and Milestone5's reward name as text (baked
-- images, the eyebrow with "//" in it), and the CLAIMED / CLAIMING... states.
--
-- PLAYTIME only accrues in a round, where this window is closed, so between
-- pushes it cannot change while the window is up. The countdown is the one
-- clock that moves on its own: it ticks at 1 Hz while open.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")

local CLOSE_ACTION = "ZyntraDailyL4Close"
local GIFT_ART = "rbxassetid://117126194981100"
-- Keyed on the reward, never on the minutes (the legacy page's REWARD_ART).
local REWARD_ART = {Tokens = "rbxassetid://93116899475472", SpeedPotion = "rbxassetid://120211340805188",
	EntityShield = "rbxassetid://126728249949579"}
local WHEEL_ART = "rbxassetid://115596488996319" -- the L4 rail's wheel icon (LobbyRail_L4 ZyntraWheelButton)
-- The L4 eyebrow type (ZyntraShop_L4 and LuckyWheel_L4 Eyebrow: RobotoMono Bold,
-- 16 px at the k = 443/1080 import), in Figma px.
local EYEBROW_FONT_SIZE = 29.6
local NOTE = "Only time in an active round counts."
local OFFLINE = "Daily rewards are not configured on this server."
-- The design's wheel row: 136 design px tall (the 44 px phone floor; Figma drew
-- 120), SpinChip 150x80 and Info 294 wide in the row's 558 x 92 list.
local WHEEL_ROW_HEIGHT, WHEEL_INFO_WIDTH, WHEEL_CHIP = 136, 294 / 558, Vector2.new(150 / 558, 80 / 92)

local ui = {open = false, built = false, bindFailed = false, session = {}, handlers = {}, contract = {},
	controls = {}, cards = {}, rows = {}, faces = {}, tickSerial = 0, messageSerial = 0}

-- The bridge and the opener exist from the first frame and say no until the
-- modules load, so neither ZyntraStore nor a router ever waits on this script.
do
	local function request(action)
		if not ui.request then return false end
		local ok, result = pcall(ui.request, action)
		if ok then return result == true end
		warn("[ZyntraDailyUI] L4 open failed: " .. tostring(result))
		ui.bindFailed = true
		if ui.setOpen then pcall(ui.setOpen, false) end
		return false
	end
	local old = playerScripts:FindFirstChild("ZyntraDailyUIOpen")
	if old then old:Destroy() end
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "ZyntraDailyUIOpen"
	bridge.OnInvoke = request
	bridge.Parent = playerScripts
	-- Created by whoever finds it missing (ZyntraStore does the same): the two
	-- scripts load in an order neither controls.
	local opener = playerScripts:FindFirstChild("OpenDailyRewards")
	if not opener then
		opener = Instance.new("BindableEvent")
		opener.Name = "OpenDailyRewards"
		opener.Parent = playerScripts
	end
	if opener:IsA("BindableEvent") then
		opener.Event:Connect(function() request("open") end)
	else
		warn("[ZyntraDailyUI] PlayerScripts.OpenDailyRewards must be a BindableEvent: the rail cannot open Daily Rewards")
	end
end

local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local Config = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local folder = ReplicatedStorage:WaitForChild("ZyntraShopUI", 30)
local binderModule = folder and folder:WaitForChild("ShopBinder", 10)
local dataModule = folder and folder:WaitForChild("ShopData", 10)
if not (binderModule and dataModule) then
	warn("[ZyntraDailyUI] ReplicatedStorage.ZyntraShopUI (ShopBinder, ShopData) is not installed: Daily Rewards cannot open")
	return
end
local Binder = require(binderModule)
local ShopData = require(dataModule)
local P = Binder.Palette
ShopData.start()

-- The milestones the server grants from, in minute order.
local MILESTONES = {}
for _, entry in ipairs(((Config.DailyRewards or {}).Milestones) or {}) do
	local minutes = tonumber(entry.Minutes)
	if minutes then
		table.insert(MILESTONES, {Minutes = minutes, Seconds = minutes * 60, Key = tostring(minutes), Reward = entry.Reward})
	end
end
table.sort(MILESTONES, function(a, b) return a.Minutes < b.Minutes end)

-- -- formats ----------------------------------------------------------------

-- m:ss, with an hours field only from an hour ("12:40", "1:05:12").
local function formatSpan(seconds)
	local whole = math.max(0, math.floor(seconds))
	if whole >= 3600 then
		return string.format("%d:%02d:%02d", whole // 3600, (whole % 3600) // 60, whole % 60)
	end
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- Always hh:mm:ss, for the reset countdown.
local function formatClock(seconds)
	local whole = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", whole // 3600, (whole % 3600) // 60, whole % 60)
end

local function plural(count, name) return tostring(count) .. " " .. (count == 1 and name or name .. "s") end

-- The reward as the player reads it, from the config the server grants from. The
-- shield is not in Config.Items: its name is ProtectionItem's.
local function rewardLabel(reward)
	if type(reward) ~= "table" then return "Reward" end
	local amount = math.max(1, math.floor(tonumber(reward.Amount) or 1))
	if reward.Kind == "Tokens" then return plural(amount, "Research Token") end
	local key = tostring(reward.Key or "")
	local item = type(Config.Items) == "table" and Config.Items[key] or nil
	if type(item) == "table" and item.Name then return plural(amount, tostring(item.Name)) end
	if key == "EntityShield" then
		return plural(amount, tostring((Config.ProtectionItem or {}).Name or "Entity Shield"))
	end
	return plural(amount, key ~= "" and key or "Reward")
end

local function artFor(reward)
	if type(reward) ~= "table" or reward.Kind == "Tokens" then return REWARD_ART.Tokens end
	return REWARD_ART[tostring(reward.Key or "")] or REWARD_ART.Tokens
end

local function dailyOf()
	local profile = ShopData.profile()
	local daily = type(profile) == "table" and profile.Daily or nil
	return type(daily) == "table" and daily or nil
end

-- -- controls -----------------------------------------------------------------

-- Every press goes through here: Activated runs `fn` while the hit is Active,
-- and the Studio probe's press: runs the very same `fn`.
function ui.onPress(hit, fn)
	ui.handlers[hit] = fn
	hit.Activated:Connect(function()
		if hit.Active then fn() end
	end)
end

-- One registration per control: the probe's `cards` and `state`, the
-- regression attribute, and the one place its press is routed. A control is
-- drawn whenever the window is (Framewisp can import an inactive panel hidden).
local function wire(id, hit, caption, fn)
	table.insert(ui.contract, id)
	table.insert(ui.controls, {Id = id, Hit = hit, Caption = caption})
	hit:SetAttribute("ZyntraDailyL4Card", id)
	ui.onPress(hit, fn)
	Binder.reveal(hit, ui.panel)
end

-- A hand-over to another screen-owning window: this one closes first, because
-- the other refuses to open over any modal (DailyRewardsOpen included).
local function handOver(name, class, owner, fn)
	local target = playerScripts:FindFirstChild(name)
	if not (target and target:IsA(class)) then
		warn(("[ZyntraDailyUI] PlayerScripts.%s (%s) is missing: that button cannot open it"):format(name, owner))
		return
	end
	ui.setOpen(false)
	fn(target)
end

-- -- messages ---------------------------------------------------------------
-- The import's StatusLine is the design's note. A push message (claimed, or
-- refused and why) takes its place for 6 s, in its tone, then the note returns.
-- The message has its own label (built from the note): the server's longest
-- line does not fit one line at the phone's 11 px floor, so it wraps in two.

function ui.restoreNote()
	ui.messageSerial += 1
	if ui.note then
		ui.note.Text = NOTE
		ui.note.Visible = true
		ui.message.Visible = false
	end
end

function ui.showMessage(text, tone)
	if not ui.message or type(text) ~= "string" or text == "" then return end
	ui.messageSerial += 1
	local mine = ui.messageSerial
	ui.message.Text = text
	ui.message.TextColor3 = tone == "error" and P.Coral or tone == "success" and P.RailTeal or P.Sage
	ui.message.Visible = true
	ui.note.Visible = false
	task.delay(6, function()
		if ui.messageSerial == mine then ui.restoreNote() end
	end)
end

-- -- render -------------------------------------------------------------------

-- The claim ladder (legacy order): CLAIMED, CLAIMING..., CLAIM, "m:ss TO GO".
local function claimState(card, played, claimed)
	if not ShopData.ready() then return "LOADING", "off", false end
	if claimed[card.Key] == true then return "CLAIMED", "owned", false end
	if ShopData.pending("Daily:" .. card.Key) then return "CLAIMING...", "off", false end
	if played >= card.Seconds then return "CLAIM", "equip", true end
	return formatSpan(card.Seconds - played) .. " TO GO", "off", false
end

function ui.render()
	if not ui.built or ui.bindFailed then return end
	local daily = dailyOf()
	local today = daily and tostring(daily.Today or "") or ""
	-- The server rolls the day lazily: until its next write, a profile from before
	-- 00:00 UTC still carries yesterday's counters.
	local sameDay = daily ~= nil and today ~= "" and tostring(daily.Day or "") == today
	local played = sameDay and math.max(0, math.floor(tonumber(daily.PlaytimeSeconds) or 0)) or 0
	local claimed = sameDay and type(daily.Claimed) == "table" and daily.Claimed or {}
	local online = Config.DailyRewards ~= nil

	local tokens = ShopData.tokens()
	if ui.count then ui.count.Text = tokens and tostring(tokens) or "--" end
	ui.playtime.Text = daily and formatSpan(played) or "--:--"

	-- Re-anchored on every new profile (a push or a re-read), ticked between.
	local profile = ShopData.profile()
	if profile ~= ui.anchored then
		ui.anchored = profile
		ui.rollAsked = false
		local seconds = daily and tonumber(daily.SecondsToReset) or nil
		ui.resetAt = seconds and workspace:GetServerTimeNow() + math.max(0, seconds) or nil
	end
	local remaining = ui.resetAt and math.max(0, ui.resetAt - workspace:GetServerTimeNow()) or nil
	ui.countdown.Text = remaining and formatClock(remaining) or "--:--:--"
	if remaining == 0 and ui.open and not ui.rollAsked then
		-- The UTC day rolled: the server owns the new counters, so ask for them.
		ui.rollAsked = true
		ShopData.refresh()
	end

	local last = MILESTONES[#MILESTONES]
	local fraction = last and math.clamp(played / last.Seconds, 0, 1) or 0
	ui.fill.Size = UDim2.new(fraction, 0, ui.fill.Size.Y.Scale, ui.fill.Size.Y.Offset)
	ui.fill.Visible = fraction > 0
	local nextUp = nil
	for _, card in ipairs(ui.cards) do
		if played < card.Seconds then nextUp = card break end
	end
	ui.caption.TextColor3 = online and ui.captionColor or P.Coral
	ui.caption.Text = not online and OFFLINE or not daily and ""
		or nextUp and ("%s to the %d minute reward"):format(formatSpan(nextUp.Seconds - played), nextUp.Minutes)
		or "Every milestone reached today."
	if ui.milestones then ui.milestones.Visible = online end

	for _, card in ipairs(ui.cards) do
		local text, style, enabled = claimState(card, played, claimed)
		-- The type follows the state, not the card (the import drew CLAIM big on
		-- the 5 MIN card and TO GO small on the others).
		local face = ui.faces[text == "CLAIM" and "Claim" or "Rest"]
		local label = card.Control.Price
		if face then
			label:SetAttribute("FigmaFontSize", face.Size)
			label.FontFace = face.Font
		end
		label.Text = text
		Binder.style(card.Control, style)
		UIDevice.SetEnabled(card.Control.Hit, enabled)
	end

	-- Research, by Key (the profile's entries carry it). The Detail line stays
	-- the design's copy: the server's "Personally ..." lines are display-only and
	-- do not fit the rows' one-line boxes on a phone.
	local entries = {}
	for _, entry in ipairs(daily and type(daily.Research) == "table" and daily.Research or {}) do
		if type(entry) == "table" and entry.Key ~= nil then entries[tostring(entry.Key)] = entry end
	end
	for key, row in pairs(ui.rows) do
		local entry = entries[key]
		local done = sameDay and entry ~= nil and entry.Complete == true
		-- Before the profile every row reads 0/1 (the import's sample is 1/1); after
		-- it, a goal the server no longer sends is not drawn.
		row.Node.Visible = entry ~= nil or daily == nil
		if entry and row.Title then row.Title.Text = tostring(entry.Title or row.Title.Text) end
		if entry and row.Amount then row.Amount.Text = "+" .. tostring(entry.Reward or 0) end
		row.Done.BackgroundColor3 = done and P.RailTeal or P.TileHi
		row.Done.BackgroundTransparency = 0
		if row.Value then
			row.Value.Text = done and "1/1" or "0/1"
			row.Value.TextColor3 = done and P.Tile or P.Sage
		end
		if row.Amount then row.Amount.TextColor3 = done and P.RailTeal or P.IconTeal end
	end

	-- LUCKY WHEEL: a prize still owed (any day), a free spin, or spun today. The
	-- wheel owns spinning and collecting; this row only opens it.
	local wheel = ui.wheel
	if wheel then
		local record = daily and type(daily.WheelLast) == "table" and daily.WheelLast or nil
		local state = record and record.Claimed == false and "prize"
			or (daily and today ~= "" and tostring(daily.WheelDay or "") ~= today) and "ready" or "spun"
		wheel.Node.Visible = online and daily ~= nil
		wheel.Hook.Text = state == "prize" and "PRIZE WAITING" or state == "ready" and "FREE SPIN READY" or "SPUN TODAY"
		wheel.Label.Text = state == "ready" and "SPIN" or "OPEN"
		local lit = state ~= "spun"
		wheel.Chip.BackgroundColor3 = lit and P.IconTeal or P.TileHi
		if wheel.Stroke then wheel.Stroke.Color = lit and P.IconTeal or P.Line end
		wheel.Label.TextColor3 = lit and P.Tile or P.Sage
	end
end

-- 1 Hz while open, for the countdown; a close or a reopen ends the old loop.
function ui.tick(serial)
	if serial ~= ui.tickSerial or not ui.open then return end
	ui.render()
	task.delay(1, ui.tick, serial)
end

-- -- open, close, fit -----------------------------------------------------------

function ui.focus()
	if not ui.open or UIDevice.LastInput() ~= "Gamepad" or GuiService.MenuIsOpen then return end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(ui.root) then return end
	GuiService.SelectedObject = ui.closeHit
end

function ui.setOpen(open)
	open = open == true
	if ui.open == open or not ui.root then return end
	ui.open = open
	ui.root.Visible = open
	-- Written before the suppression is derived: this window is in that set.
	player:SetAttribute("DailyRewardsOpen", open or nil)
	UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())
	ui.tickSerial += 1
	if open then
		ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState)
			if not ui.open or GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
			if inputState == Enum.UserInputState.Begin then ui.setOpen(false) end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		table.insert(ui.session, UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == Enum.KeyCode.Escape then ui.setOpen(false) end
		end))
		-- A pad picked up while the window is open takes focus too.
		table.insert(ui.session, UserInputService.LastInputTypeChanged:Connect(function()
			task.defer(ui.focus)
		end))
		ui.restoreNote()
		-- Drawn from the profile this client holds, so it is never blank, then re-read.
		ui.render()
		ShopData.refresh()
		task.delay(1, ui.tick, ui.tickSerial)
		task.defer(ui.focus)
	else
		ContextActionService:UnbindAction(CLOSE_ACTION)
		for _, connection in ipairs(ui.session) do connection:Disconnect() end
		table.clear(ui.session)
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(ui.root) then GuiService.SelectedObject = nil end
	end
end

-- Zyntra Shop L4's fit: the window in ModalViewport; on touch it also takes the
-- safe area's full height (at 844x390 that keeps a 136 design px button at 44.3
-- px); a PC (pointer, not a TV) shows it at HALF size, centred, never under
-- PC_MIN_HEIGHT px tall.
local PC_SCALE, PC_MIN_HEIGHT = 0.5, 400
function ui.fit()
	if not ui.holder then return end
	local layout = UIDevice.Layout()
	local area = layout.ModalViewport
	local left, top, width, height = area.Left, area.Top, area.Width, area.Height
	if layout.IsTouch then
		top, height = layout.Safe.Top, layout.Safe.Bottom - layout.Safe.Top
	elseif not GuiService:IsTenFootInterface() then
		-- The floor is on the WINDOW: in a viewport narrower than the panel's aspect
		-- (5:4, 1024x768) the window is width-bound and shorter than the holder.
		local fitH = math.min(height, width * ui.design.Y / ui.design.X)
		local scale = math.min(1, math.max(PC_SCALE, PC_MIN_HEIGHT / math.max(1, fitH)))
		left, top = left + width * (1 - scale) / 2, top + height * (1 - scale) / 2
		width, height = width * scale, height * scale
	end
	-- The lobby rail stays up over this window (2026-10-07): ZyntraStore publishes
	-- its right edge (Layout() space, nil in a round) and the window starts 8 px
	-- right of it, giving up that much width.
	local railRight = player:GetAttribute("ZyntraRailRight")
	if type(railRight) == "number" and left < railRight + 8 then
		width, left = width - (railRight + 8 - left), railRight + 8
	end
	ui.holder.Position = UIDevice.LocalPosition(ui.gui, left, top)
	ui.holder.Size = UDim2.fromOffset(width, height)
end

-- A clone that shows other copy than the sample its width-exact stamps
-- (FigmaTextW, FW_M100) were measured for: Binder.scaleText sizes it by em.
local function unstamp(root)
	local nodes = root:GetDescendants()
	table.insert(nodes, root)
	for _, node in ipairs(nodes) do
		node:SetAttribute("FigmaTextW", nil)
		node:SetAttribute("FW_M100", nil)
	end
end

-- The design's wheel row, from a clone of the last research row: the chip holds
-- the wheel icon, Name and Detail become LUCKY WHEEL and its state, the reward
-- becomes the SPIN chip, and ONE hit covers the row (the chip alone would be 26
-- px on a phone).
local function buildWheelRow(source)
	local row = source:Clone()
	unstamp(row)
	row.Name = "WheelLink"
	-- The design's one highlighted row: render keys its border to the chip (teal, grey once spun).
	local stroke = row:FindFirstChildOfClass("UIStroke")
	row.LayoutOrder = source.LayoutOrder + 1
	local height = Binder.designSize(source).Y
	row.Size = UDim2.new(source.Size.X.Scale, 0, source.Size.Y.Scale * WHEEL_ROW_HEIGHT / height, 0)
	local done, info, reward = Binder.find(row, "Done"), Binder.find(row, "Info"), Binder.find(row, "Reward")
	local name, hook = Binder.text(Binder.find(row, "Name")), Binder.text(Binder.find(row, "Detail"))
	local label = Binder.text(Binder.find(row, "Amount"))
	if not (done and info and reward and name and hook and label) then
		warn("[ZyntraDailyUI] L4 LUCKY WHEEL row skipped: " .. source.Name .. " lacks Done, Info/Name, Info/Detail or Reward/Amount")
		return nil
	end
	done.BackgroundTransparency = 1
	for _, child in ipairs(done:GetChildren()) do
		if child:IsA("GuiObject") then child.Visible = false end
	end
	Binder.image(done).Image = WHEEL_ART
	info.Size = UDim2.new(WHEEL_INFO_WIDTH, 0, info.Size.Y.Scale, 0)
	name.Text = "LUCKY WHEEL"
	hook.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
	hook.TextColor3 = P.IconTeal
	for _, child in ipairs(reward:GetChildren()) do
		if child:IsA("GuiObject") and child ~= label then child.Visible = false end
	end
	reward.Size = UDim2.fromScale(WHEEL_CHIP.X, WHEEL_CHIP.Y)
	reward.BackgroundTransparency = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = reward
	label.AnchorPoint, label.Position, label.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.7)
	-- SPIN in CLAIM's wide Montserrat Heavy, not the narrow "+2" face it was cloned from.
	label.FontFace = ui.faces.Claim and ui.faces.Claim.Font or Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	row.Parent = source.Parent
	local hit = Binder.button(row)
	Binder.press(hit, reward)
	wire("Daily|WheelLink|Spin", hit, label, function()
		handOver("OpenLuckyWheel", "BindableEvent", "Lucky Wheel Client", function(event) event:Fire() end)
	end)
	return {Node = row, Hook = hook, Label = label, Chip = reward, Stroke = stroke}
end

-- Clone, fix, bind, then mount; once per session; never yields. A missing name
-- the window needs fails it for this player, warned by path; nothing else opens.
function ui.build()
	if ui.built then return not ui.bindFailed end
	ui.built = true
	local template = folder:FindFirstChild("DailyRewards_L4")
	local art = template and template:Clone()
	if art then
		Binder.strip(art)
		if not art:IsA("GuiObject") then art = art:FindFirstChildWhichIsA("GuiObject") end
	end
	local panel = art and Binder.find(art, "DailyRewardsPanel")
	ui.panel = panel
	if not panel then
		warn("[ZyntraDailyUI] L4 missing: ReplicatedStorage.ZyntraShopUI.DailyRewards_L4/DailyRewardsPanel: Daily Rewards cannot open")
		ui.bindFailed = true
		return false
	end

	local missing = {}
	local function need(scope, path, where)
		local node = scope and Binder.at(scope, path)
		if not node then table.insert(missing, (where and where .. "/" or "") .. path) end
		return node
	end
	local close = need(panel, "CloseButton")
	ui.playtime = Binder.text(need(panel, "PlaytimeReadout"))
	ui.countdown = Binder.text(need(panel, "ResetCountdown"))
	local track = need(panel, "ProgressTrack")
	ui.fill = track and need(track, "Fill", "ProgressTrack")
	ui.caption = Binder.text(need(panel, "ProgressCaption"))
	ui.note = Binder.text(need(panel, "StatusLine"))
	ui.milestones = Binder.find(panel, "Milestones")

	-- Cards: one per configured milestone, by the legacy name; a card the config
	-- does not have is not drawn.
	local cards = {}
	for suffix, node in pairs(Binder.all(panel, "Milestone")) do
		if tonumber(suffix) then cards[suffix] = node end
	end
	local donor = nil -- a text RewardName, for a card whose reward name was baked into an image
	for _, node in pairs(cards) do
		local reward = Binder.text(Binder.find(node, "RewardName"))
		if reward then
			reward.TextWrapped = true -- a two-line box (the export dropped its _txt tag)
			donor = donor or reward
		end
	end
	for _, milestone in ipairs(MILESTONES) do
		local where = "Milestone" .. milestone.Key
		local node = cards[milestone.Key]
		cards[milestone.Key] = nil
		local baked = node and Binder.find(node, "RewardName")
		if baked and not Binder.text(baked) and donor then
			local label = donor:Clone()
			unstamp(label)
			label.Parent = baked.Parent
			baked:Destroy()
		end
		local control = node and Binder.control(node, "ClaimButton", "State")
		local reward = node and Binder.text(Binder.find(node, "RewardName"))
		local threshold = node and Binder.text(Binder.find(node, "Threshold"))
		if node and not (control and control.Price and reward and threshold) then
			table.insert(missing, where .. " (ClaimButton/State, RewardName, Threshold)")
		elseif node then
			local card = table.clone(milestone)
			card.Node, card.Control, card.RewardText, card.Threshold = node, control, reward, threshold
			card.Icon = Binder.find(node, "RewardIcon")
			table.insert(ui.cards, card)
		else
			need(nil, where)
		end
	end
	for _, node in pairs(cards) do node.Visible = false end

	-- Research rows, by the Key in their name.
	local research = Binder.find(panel, "Research")
	local lastRow = nil
	for key, node in pairs(Binder.all(research, "Research")) do
		local done = Binder.find(node, "Done")
		if done and Binder.find(node, "Info") then
			ui.rows[key] = {Node = node, Done = done, Value = Binder.text(done),
				Title = Binder.text(Binder.find(node, "Name")), Amount = Binder.text(Binder.find(node, "Amount"))}
			if not lastRow or node.LayoutOrder > lastRow.LayoutOrder then lastRow = node end
		end
	end

	if #missing > 0 then
		for _, path in ipairs(missing) do warn("[ZyntraDailyUI] L4 missing: DailyRewardsPanel/" .. path) end
		ui.bindFailed = true
		table.clear(ui.cards)
		return false
	end

	-- What the import baked or left as placeholders.
	local gift = Binder.find(panel, "HeaderGift")
	if gift then Binder.image(gift).Image = GIFT_ART end
	for _, card in ipairs(ui.cards) do
		if card.Icon then Binder.image(card.Icon).Image = artFor(card.Reward) end
	end
	local eyebrow = Binder.find(panel, "Eyebrow")
	if eyebrow and not Binder.text(eyebrow) then
		-- A baked "ZYNTRA // DAILY": the owner's rule allows no "//".
		local label = Instance.new("TextLabel")
		label.Name = "Eyebrow"
		label.BackgroundTransparency = 1
		label.AnchorPoint, label.Position, label.Size, label.ZIndex = eyebrow.AnchorPoint, eyebrow.Position, eyebrow.Size, eyebrow.ZIndex
		label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
		label.TextColor3 = P.IconTeal
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = "ZYNTRA DAILY"
		label:SetAttribute("FigmaFontSize", EYEBROW_FONT_SIZE)
		label.Parent = eyebrow.Parent
		eyebrow:Destroy()
	end
	-- The claim caption's two authored types: CLAIM (5 MIN) and TO GO (the others).
	for _, card in ipairs(ui.cards) do
		local label = card.Control.Price
		local kind = label.Text == "CLAIM" and "Claim" or string.find(label.Text, "TO GO", 1, true) and "Rest" or nil
		if kind and not ui.faces[kind] and label:GetAttribute("FigmaFontSize") then
			ui.faces[kind] = {Size = label:GetAttribute("FigmaFontSize"), Font = label.FontFace}
		end
	end
	ui.fill.AnchorPoint = Vector2.new(0, ui.fill.AnchorPoint.Y)
	ui.fill.Position = UDim2.new(0, 0, ui.fill.Position.Y.Scale, ui.fill.Position.Y.Offset)
	local lastMinutes = MILESTONES[#MILESTONES] and MILESTONES[#MILESTONES].Minutes
	for suffix, tick in pairs(Binder.all(track, "Tick")) do
		local minutes = tonumber(suffix)
		local shown = false
		for index, milestone in ipairs(MILESTONES) do
			if milestone.Minutes == minutes and index < #MILESTONES then shown = true end
		end
		tick.Visible = shown
		if shown then tick.Position = UDim2.new(minutes / lastMinutes, 0, tick.Position.Y.Scale, tick.Position.Y.Offset) end
	end
	ui.captionColor = ui.caption.TextColor3
	-- The message line: the note's type, the column's width, two lines from the
	-- note's top (2.4 x its 31 design px box holds two 36 px lines, and still ends
	-- inside the panel).
	local message = ui.note:Clone()
	message.Name = "Message"
	message.TextWrapped = true
	message.TextXAlignment, message.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
	message.AnchorPoint = Vector2.new(0, 0)
	message.Position = UDim2.fromScale(0, ui.note.Position.Y.Scale - ui.note.AnchorPoint.Y * ui.note.Size.Y.Scale)
	message.Size = UDim2.fromScale(1, 2.4 * ui.note.Size.Y.Scale)
	message.Visible = false
	message.Parent = ui.note.Parent
	ui.message = message
	if lastRow then
		ui.wheel = buildWheelRow(lastRow)
	else
		warn("[ZyntraDailyUI] L4 LUCKY WHEEL row skipped: the import has no Research row to build it from")
	end

	-- Controls.
	ui.closeHit = Binder.button(close)
	wire("Daily|Header|Close", ui.closeHit, nil, function() ui.setOpen(false) end)
	Binder.press(ui.closeHit, close, Binder.find(panel, "CloseShadow"))
	local add = Binder.find(panel, "AddTokens")
	if add then
		local hit = Binder.button(add)
		wire("Daily|Header|AddTokens", hit, nil, function()
			handOver("ZyntraShopUIOpen", "BindableFunction", "Zyntra Shop L4", function(bridge)
				pcall(bridge.Invoke, bridge, "Shop", "Tokens20")
			end)
		end)
		Binder.press(hit, add)
	end
	ui.count = Binder.text(Binder.find(panel, "TokenCount"))
	for _, card in ipairs(ui.cards) do
		wire(("Daily|Milestone%s|Claim"):format(card.Key), card.Control.Hit, card.Control.Price, function()
			ShopData.claim(card.Minutes)
		end)
		Binder.press(card.Control.Hit, card.Control.Face, card.Control.Shadow)
	end

	-- Mount: full-screen Root > artboard (input shield only) + holder > aspect-
	-- locked fit > shadow + panel. The fit box is the PANEL (1680x1020), not the
	-- modal with its shadow (1036 tall): only that keeps 136 px buttons at 44 px.
	local design = Binder.designSize(panel)
	ui.design = design -- ui.fit's aspect
	local modal = panel.Parent
	local shadow = Binder.find(art, "ModalShadow")
	local drop = shadow and (shadow.Position.Y.Scale - panel.Position.Y.Scale) * Binder.designSize(modal).Y / design.Y or 0
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
	-- The import's opaque #05090B fill WAS the backdrop: none (owner 2026-10-07).
	art.AnchorPoint, art.Position, art.Size, art.BackgroundTransparency = Vector2.new(0, 0), UDim2.new(), UDim2.fromScale(1, 1), 1
	-- Under WindowHolder (ZIndex 2) whatever ZIndex the import carries: above it,
	-- the Active Dim swallows every tap (v2770, phones).
	art.ZIndex = 1
	art.Parent = root
	-- The import has no Dim: a transparent, Active shield, so a tap past the
	-- window reaches nothing behind it.
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
	if shadow then
		shadow.AnchorPoint, shadow.Position, shadow.Size, shadow.ZIndex = Vector2.new(0, 0), UDim2.fromScale(0, math.clamp(drop, 0, 0.05)), UDim2.fromScale(1, 1), 1
		shadow.Parent = fitFrame
	end
	panel.AnchorPoint, panel.Position, panel.Size, panel.ZIndex = Vector2.new(0, 0), UDim2.new(), UDim2.fromScale(1, 1), 2
	panel.Parent = fitFrame
	ui.fit()
	Binder.scaleText(panel, design, art:GetAttribute("BB_TextFactor"))
	-- After scaleText has stamped each import sample (FW_Text0), so a text that
	-- differs from its sample is sized by em, never by the sample's width.
	for _, card in ipairs(ui.cards) do
		card.Threshold.Text = card.Minutes .. " MIN"
		card.RewardText.Text = rewardLabel(card.Reward)
	end
	return true
end

-- The bridge's answer: true when the window is open afterwards.
function ui.request(action)
	if action == "close" or (action == "toggle" and ui.open) then
		ui.setOpen(false)
		return false
	end
	if ui.open then return true end
	if player:GetAttribute("InRound") == true or player:GetAttribute("QueueModalOpen") == true
		or UIDevice.ScreenOwningModalOpen() or not ui.build() then
		return false
	end
	ui.setOpen(true)
	return true
end

-- -- wiring ----------------------------------------------------------------------

ui.gui = Instance.new("ScreenGui")
ui.gui.Name = "ZyntraDailyL4"
-- The legacy daily modal's order: over every HUD surface, under the Lucky Wheel (118).
-- The one exception is the lobby rail: while a rail window is open ZyntraStore
-- lifts itself to 119 (2026-10-07), so it stays tappable over this window and its Dim.
ui.gui.DisplayOrder = 117
ui.gui.ResetOnSpawn = false
ui.gui.IgnoreGuiInset = false
ui.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ui.gui.Parent = playerGui

ShopData.Changed:Connect(ui.render)
ShopData.Message:Connect(ui.showMessage)
for _, name in ipairs({"InRound", "QueueModalOpen"}) do
	player:GetAttributeChangedSignal(name):Connect(function()
		if player:GetAttribute(name) == true then ui.setOpen(false) end
	end)
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") == true then ui.setOpen(false) end
end)
GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(function()
	if GuiService.MenuIsOpen then ui.setOpen(false) end
end)
UIDevice.Changed:Connect(ui.fit)
player:GetAttributeChangedSignal("ZyntraRailRight"):Connect(ui.fit)

-- Studio-only seam for the main session's Play test and UIRegression:
--   open / close / toggle   the bridge's own paths, refusals included
--   cards                   "Daily|<node>|<action>" per control, in bind order
--   state                   "<id>|<caption>|<active>" per control
--   press:<id>              runs the press handler Activated would run (Active only)
if RunService:IsStudio() then
	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionZyntraDailyL4Probe"
	probe.OnInvoke = function(action)
		action = tostring(action)
		if action == "open" or action == "close" or action == "toggle" then return ui.request(action) end
		if action == "cards" then return table.concat(ui.contract, "\n") end
		if action == "state" then
			ui.render()
			local lines = {}
			for _, entry in ipairs(ui.controls) do
				table.insert(lines, ("%s|%s|%s"):format(entry.Id, entry.Caption and entry.Caption.Text or "", tostring(entry.Hit.Active)))
			end
			return table.concat(lines, "\n")
		end
		if string.sub(action, 1, 6) == "press:" then
			for _, entry in ipairs(ui.controls) do
				if entry.Id == string.sub(action, 7) then
					if not entry.Hit.Active then return false end
					ui.handlers[entry.Hit]()
					return true
				end
			end
			return false
		end
		return ui.open
	end
	probe.Parent = ui.gui
end
