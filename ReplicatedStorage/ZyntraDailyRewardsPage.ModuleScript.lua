-- ZyntraDailyRewardsPage -- the DAILY REWARDS page. (Trello #83/#84/#89/#104)
--
-- WHAT THIS PAGE IS ALLOWED TO DECIDE: nothing. Every number on it is read back
-- from the public profile the server already committed -- how many seconds of
-- ACTIVE round play the player has today, and which milestones are already
-- claimed. The page asks (`ClaimPlaytimeReward`) and then RE-READS; it never
-- grants and never keeps a second copy of the state that could disagree with
-- the save. That is what makes loss, rejoin, retry and a double press incapable
-- of granting twice: the second press is a second read.
--
-- WHERE THE WHEEL WENT (Trello #103/#104, 2026-09-16). The supply wheel used to
-- be the second half of this page. It is now its own modal --
-- StarterPlayerScripts."Lucky Wheel Client", opened from its own rail button --
-- so nothing here reads `Daily.WheelDay` / `Daily.WheelLast` or sends
-- `SpinDailyWheel` any more. The SERVER side is untouched; only this view
-- stopped drawing it, which is why removing it cannot change what a spin pays.
--
-- WHO MOUNTS THIS. `mount(page, ctx)` is the host-agnostic contract in
-- artifacts/trello-20260916/claude-contracts.md. The terminal used to be the
-- only host; since #104 the host is StarterPlayerScripts."Daily Rewards
-- Client", which builds its own modal shell and hands this page its content
-- frame. The page cannot tell the two apart and must not try to.
--
-- WHY THE COUNTDOWN IS LOCAL AND THE DAY IS UTC. The reset boundary is a UTC
-- day so every player on every server rolls over at the same instant; the
-- countdown to it ticks off `workspace:GetServerTimeNow()`, re-anchored on
-- EVERY push, so it stays honest without a second clock to keep in sync.
--
-- The page draws only inside the frame it is handed, never requires its host
-- (the mount is the other direction), and never yields at require.

local RunService = game:GetService("RunService")

-- How long a request may sit unanswered before the page stops pretending. The
-- server's own write window is 1 s, so 6 s is a genuine failure rather than a
-- rate limit, and the recovery is a RE-READ -- never a local grant.
local ACTION_TIMEOUT = 6

-- Three tiers, taken from the two facts the host publishes about itself,
-- exactly as ZyntraStore's own Upgrades and Shop pages take them:
--   1  phone    fit.Compact AND fit.Touch
--   2  tablet   fit.Touch, not compact
--   3  pointer  neither
-- Nothing here is under 11px: the shared Body token is 13 and the shared
-- Eyebrow token is 10, and 10 is a face drawn at arm's length on a HUD, not
-- inside a scrolling panel a phone holds a foot from someone's eyes.
local FACES = {
	{Pad = 12, Gap = 10, Section = 15, Card = 14, Body = 11, Clock = 15, Button = 44},
	{Pad = 14, Gap = 12, Section = 17, Card = 16, Body = 12, Clock = 18, Button = 44},
	{Pad = 16, Gap = 14, Section = 18, Card = 17, Body = 13, Clock = 21, Button = 40},
}

-- "Resets 00:00 UTC" sits BESIDE the countdown only on a panel wide enough for
-- both on one row; under it otherwise. It was the same threshold that used to
-- decide two content columns, and the number is kept because the header's own
-- arithmetic is what it was measured against.
local WIDE_HEADER_MIN = 620
-- The host's scrollbar is 5px and sits inside the page, so the content
-- stops short of it rather than under it.
local SCROLLBAR_ROOM = 8

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

-- HH:MM:SS, for the two countdowns. Always three fields: a reset that reads
-- "12:33" one minute and "1:05:12:33" the next is a readout nobody can scan.
local function formatClock(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", whole // 3600, (whole % 3600) // 60, whole % 60)
end

-- m:ss for a span a player thinks of in minutes ("12:40 played", "2:20 TO GO"),
-- growing an hours field only when it needs one.
local function formatSpan(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	local hours = whole // 3600
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, (whole % 3600) // 60, whole % 60)
	end
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function plural(count: number, name: string): string
	return tostring(count) .. " " .. (count == 1 and name or name .. "s")
end

-- A reward as the player reads it. The milestone config entries carry no Label
-- of their own, so their copy is derived from the SAME config the server grants
-- from and cannot drift from what actually lands.
local function rewardLabel(config, reward): string
	if type(reward) ~= "table" then return "Reward" end
	local amount = math.max(1, math.floor(tonumber(reward.Amount) or 1))
	if reward.Kind == "Tokens" then return plural(amount, "Research Token") end
	local key = tostring(reward.Key or "")
	local items = type(config) == "table" and type(config.Items) == "table" and config.Items or {}
	local entry = items[key]
	if type(entry) == "table" and entry.Name then return plural(amount, tostring(entry.Name)) end
	-- The shield is deliberately NOT in Config.Items -- its charges live in
	-- Protection.Charges, which is why a reward adds one there -- so its name
	-- has always come from ProtectionItem. Both have to resolve or the 35
	-- minute card reads "1 EntityShields".
	if key == "EntityShield" then
		local protection = type(config) == "table" and config.ProtectionItem or nil
		local name = type(protection) == "table" and protection.Name or "Entity Shield"
		return plural(amount, tostring(name))
	end
	return plural(amount, key ~= "" and key or "Reward")
end

local Page = {}

function Page.mount(page, ctx)
	-- Every ctx member is called through this, so a host that ever ships one of
	-- them nil degrades to a page that draws and reads rather than one that
	-- errors on mount. The contract still says they are all there.
	local function call(fn, ...)
		if type(fn) == "function" then return fn(...) end
		return nil
	end

	local Config = type(ctx.Config) == "table" and ctx.Config or {}
	local UIStyle = ctx.UIStyle
	local UIDevice = ctx.UIDevice
	local COLORS = type(ctx.COLORS) == "table" and ctx.COLORS or {}
	local pageName = ctx.pageName or "Rewards"
	local contract = type(ctx.contract) == "table" and ctx.contract or {}

	local function visible(): boolean
		if type(ctx.isVisible) ~= "function" then return true end
		return ctx.isVisible() == true
	end

	local function setEnabled(element, enabled: boolean)
		if UIDevice and type(UIDevice.SetEnabled) == "function" then
			UIDevice.SetEnabled(element, enabled)
		else
			element.Active = enabled
		end
	end

	-- SURFACES AND TYPE come from the shared UIStyle -- the owner named Level 1's
	-- Objectives panel and the Mission Brief as the reference -- while the two
	-- ACCENTS come from the host's own palette (ctx.COLORS), so the page reads
	-- like the panel it copies without clashing with the modal it lives in. Teal
	-- is the system colour; gold is money, and only money.
	local accent = COLORS.accent or UIStyle.Color.Accent
	local gold = COLORS.accent2 or UIStyle.Color.Warning
	local muted = COLORS.muted or UIStyle.Color.Muted
	local titleColor = COLORS.text or UIStyle.Color.Title

	local rewards = type(Config.DailyRewards) == "table" and Config.DailyRewards or nil

	local scroll = Instance.new("ScrollingFrame")
	-- NAMED like every other page scroll this project builds: "ScrollingFrame"
	-- is not something a failure report can point a reader at.
	scroll.Name = "DailyRewards"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = accent
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = page
	call(contract.scroll, pageName, scroll)

	-- ── header ───────────────────────────────────────────────────────────────
	local header = Instance.new("Frame")
	header.Name = "RewardsHeader"
	header.Parent = scroll
	UIStyle.panel(header, {Radius = UIStyle.Radius.Card})

	local headerAccent = Instance.new("Frame")
	headerAccent.Name = "HeaderAccent"
	headerAccent.BackgroundColor3 = accent
	headerAccent.BackgroundTransparency = 0.14
	headerAccent.BorderSizePixel = 0
	headerAccent.Parent = header
	call(ctx.corner, headerAccent, 2)

	-- WHY THERE IS NO PAGE TITLE HERE. The host owns the modal's identity: the
	-- Daily Rewards Client's title bar prints "ZYNTRA // DAILY SUPPLY" and
	-- "DAILY REWARDS" right above this frame, and the terminal prints its own
	-- name and a REWARDS tab. A title in both places is the same two words twice,
	-- 40px apart. What the page owns is the COUNTDOWN, because the countdown is
	-- state and the title is chrome.
	--
	-- The countdown and its UTC note travel together -- side by side on a wide
	-- panel, stacked on a phone -- so they are placed as a block instead of two
	-- independently guessed rectangles.
	local resetBlock = Instance.new("Frame")
	resetBlock.Name = "ResetBlock"
	resetBlock.BackgroundTransparency = 1
	resetBlock.Parent = header
	local countdown = ctx.label(resetBlock, "RESETS IN --:--:--", UDim2.new(),
		UDim2.new(), 15, accent, UIStyle.Font.Readout)
	countdown.Name = "ResetCountdown"
	local resetNote = ctx.label(resetBlock, "Resets 00:00 UTC", UDim2.new(),
		UDim2.new(), 11, muted, UIStyle.Font.Body)
	resetNote.Name = "ResetNote"

	-- ── playtime ─────────────────────────────────────────────────────────────
	local playtime = Instance.new("Frame")
	playtime.Name = "PlaytimeSection"
	playtime.Parent = scroll
	UIStyle.panel(playtime, {Background = UIStyle.Color.Card,
		Transparency = UIStyle.Transparency.Card, Radius = UIStyle.Radius.Card,
		StrokeTransparency = UIStyle.Stroke.CardTransparency})

	local playtimeTitle = ctx.label(playtime, "PLAYTIME REWARDS", UDim2.new(),
		UDim2.new(), 15, titleColor, UIStyle.Font.Title)
	playtimeTitle.Name = "SectionTitle"
	local playtimeReadout = ctx.label(playtime, "ACTIVE PLAY TODAY  0:00", UDim2.new(),
		UDim2.new(), 15, accent, UIStyle.Font.Readout)
	playtimeReadout.Name = "PlaytimeReadout"

	local track = Instance.new("Frame")
	track.Name = "ProgressTrack"
	track.BackgroundColor3 = Color3.fromRGB(52, 63, 57)
	track.BackgroundTransparency = 0.28
	track.BorderSizePixel = 0
	track.Parent = playtime
	call(ctx.corner, track, 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	call(ctx.corner, fill, 2)

	local progressCaption = ctx.label(playtime, "", UDim2.new(), UDim2.new(),
		11, muted, UIStyle.Font.Body)
	progressCaption.Name = "ProgressCaption"

	local playtimeNote = ctx.label(playtime,
		"Only time in an active round counts. The lobby and spectating do not,"
		.. " and a short break never takes back time already earned.",
		UDim2.new(), UDim2.new(), 11, muted, UIStyle.Font.Body)
	playtimeNote.Name = "PlaytimeNote"
	playtimeNote.TextWrapped = true
	playtimeNote.TextYAlignment = Enum.TextYAlignment.Top

	-- The wheel used to be the section under this one. A player who remembers it
	-- being here has to be told where it went, once, in the place they last saw
	-- it -- otherwise the page simply looks like it lost a feature.
	local wheelNote = ctx.label(playtime,
		"Spin the Lucky Wheel from its own button on the left rail.",
		UDim2.new(), UDim2.new(), 11, muted, UIStyle.Font.Body)
	wheelNote.Name = "WheelNote"

	local milestones = {}
	for order, entry in ipairs(rewards and rewards.Milestones or {}) do
		local minutes = type(entry) == "table" and math.floor(tonumber(entry.Minutes) or 0) or 0
		if minutes > 0 then
			local card = Instance.new("Frame")
			card.Name = "Milestone" .. tostring(minutes)
			card.LayoutOrder = order
			card.Parent = playtime
			UIStyle.panel(card, {Background = UIStyle.Color.Panel,
				Radius = UIStyle.Radius.Panel,
				StrokeTransparency = UIStyle.Stroke.RowTransparency})

			local cardTitle = ctx.label(card, plural(minutes, "MINUTE"):upper(),
				UDim2.new(), UDim2.new(), 14, titleColor, UIStyle.Font.Title)
			cardTitle.Name = "CardTitle"
			local reward = type(entry) == "table" and entry.Reward or nil
			local isTokens = type(reward) == "table" and reward.Kind == "Tokens"
			local cardReward = ctx.label(card, rewardLabel(Config, reward), UDim2.new(),
				UDim2.new(), 11, isTokens and gold or accent, UIStyle.Font.Body)
			cardReward.Name = "CardReward"

			local claim = ctx.button(card, "CLAIM", UDim2.new(), UDim2.new())
			claim.Name = "ClaimButton"
			call(contract.card, pageName, "Playtime" .. tostring(minutes), card, claim)

			table.insert(milestones, {
				Minutes = minutes,
				Seconds = minutes * 60,
				Key = tostring(minutes),
				Card = card,
				Title = cardTitle,
				Reward = cardReward,
				Button = claim,
			})
		end
	end
	table.sort(milestones, function(a, b) return a.Minutes < b.Minutes end)

	local offline
	if not rewards then
		-- The config and the server that honours it land together, so with the
		-- config absent a CLAIM button would be a control that cannot work. The
		-- page says so instead of offering one.
		offline = ctx.label(scroll, "Daily rewards are not configured on this server.",
			UDim2.new(), UDim2.new(), 12, COLORS.error or UIStyle.Color.Danger, UIStyle.Font.Body)
		offline.Name = "RewardsOffline"
		playtime.Visible = false
	end

	-- ── state ────────────────────────────────────────────────────────────────
	local destroyed = false
	local lastFit = nil
	local pending = {}          -- request key -> serial, cleared by any push
	local pendingSeq = 0
	local resetAt = nil         -- server-clock instant of the next 00:00 UTC
	local rollAsked = false
	local clockAccum = 0
	local render
	-- Forward-declared: render() re-runs the layout after it changes what is
	-- drawn (a CLAIM that becomes "12:40 TO GO" changes no rectangle, but the
	-- offline branch and a late config do), and the layout is defined below it.
	-- A module-level handle would be shared between mounts.
	local layoutFor

	local function now(): number
		return workspace:GetServerTimeNow()
	end

	-- One request in flight per key, and a re-read rather than a guess when the
	-- server never answers.
	local function await(key: string)
		pendingSeq += 1
		local serial = pendingSeq
		pending[key] = serial
		task.delay(ACTION_TIMEOUT, function()
			if destroyed or pending[key] ~= serial then return end
			pending[key] = nil
			call(ctx.showStatus, "No answer yet. Try again.", "error")
			call(ctx.refreshProfile)
			render()
		end)
	end

	local function dailyOf(profile)
		if type(profile) ~= "table" then return nil end
		return type(profile.Daily) == "table" and profile.Daily or nil
	end

	-- The clock is the only thing that changes without a push, so it is the
	-- only thing the 1 Hz ticker redraws.
	local function updateClocks()
		local remaining = resetAt and math.max(0, resetAt - now()) or nil
		countdown.Text = remaining and ("RESETS IN " .. formatClock(remaining)) or "RESETS IN --:--:--"
		if remaining == 0 and not rollAsked then
			-- The UTC day just rolled. The server owns the new counters, so the
			-- page asks for them rather than zeroing anything itself.
			rollAsked = true
			call(ctx.refreshProfile)
		end
	end

	function render()
		if destroyed then return end
		local profile = call(ctx.profile)
		local daily = dailyOf(profile)
		local today = daily and tostring(daily.Today or "") or ""
		-- THE DAY IS CHECKED, not assumed. The server resets PlaytimeSeconds and
		-- Claimed lazily inside its own transform, so between 00:00 UTC and the
		-- next write those two fields still describe YESTERDAY. Reading them as
		-- today's would draw three CLAIMED cards one second after the reset.
		local sameDay = daily ~= nil and today ~= "" and tostring(daily.Day or "") == today
		local played = sameDay and math.max(0, math.floor(tonumber(daily.PlaytimeSeconds) or 0)) or 0
		local claimed = (sameDay and type(daily.Claimed) == "table") and daily.Claimed or {}
		local accruing = daily ~= nil and daily.Accruing == true

		playtimeReadout.Text = "ACTIVE PLAY TODAY  " .. formatSpan(played)
			.. (accruing and "  //  COUNTING" or "")

		local last = milestones[#milestones]
		fill.Size = UDim2.fromScale(last and clamp01(played / math.max(1, last.Seconds)) or 0, 1)

		local nextUp = nil
		for _, milestone in ipairs(milestones) do
			if played < milestone.Seconds then
				nextUp = milestone
				break
			end
		end
		if nextUp then
			-- "5 minute reward", not "5 minutes reward": the number is an
			-- adjective here, so plural() is the wrong helper for this one.
			progressCaption.Text = formatSpan(nextUp.Seconds - played) .. " to the "
				.. tostring(nextUp.Minutes) .. " minute reward"
		elseif #milestones > 0 then
			progressCaption.Text = "Every milestone reached today."
		else
			progressCaption.Text = ""
		end

		for _, milestone in ipairs(milestones) do
			local button = milestone.Button
			if claimed[milestone.Key] == true then
				button.Text = "CLAIMED"
				button.TextColor3 = muted
				setEnabled(button, false)
			elseif pending[milestone.Key] then
				button.Text = "CLAIMING..."
				button.TextColor3 = muted
				setEnabled(button, false)
			elseif played >= milestone.Seconds then
				button.Text = "CLAIM"
				button.TextColor3 = accent
				setEnabled(button, true)
			else
				button.Text = formatSpan(milestone.Seconds - played) .. " TO GO"
				button.TextColor3 = muted
				setEnabled(button, false)
			end
		end

		updateClocks()
		-- The section can still grow and shrink -- a late config turns the
		-- offline branch off -- so the geometry is re-resolved from the fit the
		-- host last published rather than left describing the previous state.
		if lastFit then layoutFor(lastFit) end
	end

	-- ── layout ───────────────────────────────────────────────────────────────
	-- Every rectangle on this page is an OFFSET derived from fit.ContentWidth,
	-- the way ZyntraStore's own pages derive theirs, so "does this card fit" is
	-- arithmetic a test can do rather than a screenshot someone has to look at.
	-- The host publishes `fit`; both hosts publish the same shape.
	local function layout(fit)
		lastFit = fit
		local width = math.max(160, math.floor(tonumber(fit.ContentWidth) or 320))
		local touch = fit.Touch == true
		local tier = (fit.Compact and touch) and 1 or (touch and 2 or 3)
		local face = FACES[tier]
		local tap = math.max(touch and 44 or 28, math.floor(tonumber(fit.Tap) or 0))
		local buttonHeight = math.max(tap, face.Button)
		local pad, gap = face.Pad, face.Gap
		local usable = math.max(120, width - SCROLLBAR_ROOM)
		-- ONE COLUMN, always. The wheel was the second one; with it gone, a
		-- half-width playtime card beside an empty half is not a composition,
		-- so the section takes the whole usable width at every tier.
		local wideHeader = tier > 1 and usable >= WIDE_HEADER_MIN
		local inner = math.max(60, usable - pad * 2)

		-- header
		local clockHeight = face.Clock + 8
		local noteHeight = face.Body + 6
		local headerInner = math.max(60, usable - pad * 2 - 8)
		local blockHeight = wideHeader and clockHeight or (clockHeight + 2 + noteHeight)
		local headerHeight = pad + blockHeight + pad

		header.Position = UDim2.fromOffset(0, 0)
		header.Size = UDim2.fromOffset(usable, headerHeight)
		headerAccent.Position = UDim2.fromOffset(0, 10)
		headerAccent.Size = UDim2.fromOffset(3, math.max(8, headerHeight - 20))

		resetBlock.Position = UDim2.fromOffset(pad + 8, pad)
		resetBlock.Size = UDim2.fromOffset(headerInner, blockHeight)
		countdown.Position = UDim2.fromOffset(0, 0)
		countdown.TextSize = face.Clock
		countdown.TextXAlignment = Enum.TextXAlignment.Left
		resetNote.TextSize = face.Body
		if wideHeader then
			-- 0.4 of the row is measured against the longer of the two strings:
			-- "Resets 00:00 UTC" at the pointer Body face is about 110px and the
			-- narrowest row this branch can be handed is 620 - 32 - 8.
			local noteWidth = math.max(110, math.floor(headerInner * 0.4))
			countdown.Size = UDim2.fromOffset(math.max(60, headerInner - noteWidth - 8), clockHeight)
			resetNote.Position = UDim2.fromOffset(headerInner - noteWidth, 0)
			resetNote.Size = UDim2.fromOffset(noteWidth, clockHeight)
			resetNote.TextXAlignment = Enum.TextXAlignment.Right
		else
			countdown.Size = UDim2.fromOffset(headerInner, clockHeight)
			resetNote.Position = UDim2.fromOffset(0, clockHeight + 2)
			resetNote.Size = UDim2.fromOffset(headerInner, noteHeight)
			resetNote.TextXAlignment = Enum.TextXAlignment.Left
		end

		local top = headerHeight + gap
		if offline then
			offline.Position = UDim2.fromOffset(pad, top)
			offline.Size = UDim2.fromOffset(usable - pad * 2, face.Body + 14)
			scroll.CanvasSize = UDim2.fromOffset(0, top + face.Body + 14 + pad)
			return
		end

		-- playtime
		local sectionTitleHeight = face.Section + 8
		local readoutHeight = face.Clock + 6
		local captionHeight = face.Body + 6
		local cardTitleHeight = face.Card + 6
		local cardRewardHeight = face.Body + 6
		local cardHeight = pad + cardTitleHeight + 2 + cardRewardHeight + 8 + buttonHeight + pad
		local y = pad
		playtimeTitle.Position = UDim2.fromOffset(pad, y)
		playtimeTitle.Size = UDim2.fromOffset(inner, sectionTitleHeight)
		playtimeTitle.TextSize = face.Section
		y += sectionTitleHeight + 4
		playtimeReadout.Position = UDim2.fromOffset(pad, y)
		playtimeReadout.Size = UDim2.fromOffset(inner, readoutHeight)
		playtimeReadout.TextSize = face.Clock
		y += readoutHeight + 8
		track.Position = UDim2.fromOffset(pad, y)
		track.Size = UDim2.fromOffset(inner, 4)
		y += 4 + 6
		progressCaption.Position = UDim2.fromOffset(pad, y)
		progressCaption.Size = UDim2.fromOffset(inner, captionHeight)
		progressCaption.TextSize = face.Body
		y += captionHeight + gap
		for _, milestone in ipairs(milestones) do
			milestone.Card.Position = UDim2.fromOffset(pad, y)
			milestone.Card.Size = UDim2.fromOffset(inner, cardHeight)
			milestone.Title.Position = UDim2.fromOffset(pad, pad)
			milestone.Title.Size = UDim2.fromOffset(math.max(40, inner - pad * 2), cardTitleHeight)
			milestone.Title.TextSize = face.Card
			milestone.Reward.Position = UDim2.fromOffset(pad, pad + cardTitleHeight + 2)
			milestone.Reward.Size = UDim2.fromOffset(math.max(40, inner - pad * 2), cardRewardHeight)
			milestone.Reward.TextSize = face.Body
			milestone.Button.Position = UDim2.fromOffset(pad, cardHeight - pad - buttonHeight)
			milestone.Button.Size = UDim2.fromOffset(math.max(44, inner - pad * 2), buttonHeight)
			milestone.Button.TextSize = face.Body + 2
			y += cardHeight + gap
		end
		-- Two wrapped lines of the note, measured as boxes rather than with
		-- TextService: nothing here chooses a branch on the measurement, so a
		-- generous box is cheaper than a synchronous text query per layout pass.
		local playtimeNoteHeight = face.Body * 2 + 14
		playtimeNote.Position = UDim2.fromOffset(pad, y)
		playtimeNote.Size = UDim2.fromOffset(inner, playtimeNoteHeight)
		playtimeNote.TextSize = face.Body
		y += playtimeNoteHeight + 4
		wheelNote.Position = UDim2.fromOffset(pad, y)
		wheelNote.Size = UDim2.fromOffset(inner, captionHeight)
		wheelNote.TextSize = face.Body
		local playtimeHeight = y + captionHeight + pad

		playtime.Position = UDim2.fromOffset(0, top)
		playtime.Size = UDim2.fromOffset(usable, playtimeHeight)
		scroll.CanvasSize = UDim2.fromOffset(0, top + playtimeHeight + pad)
	end
	layoutFor = layout
	call(ctx.registerLayoutHook, layout)

	-- ── input ────────────────────────────────────────────────────────────────
	for _, milestone in ipairs(milestones) do
		milestone.Button.Activated:Connect(function()
			-- The claim is refused HERE as well as on the server: a second press
			-- that never leaves the client is a second grant that can never race.
			if destroyed or pending[milestone.Key] then return end
			if not milestone.Button.Active then return end
			await(milestone.Key)
			call(ctx.action, "ClaimPlaytimeReward", {Minutes = milestone.Minutes})
			render()
		end)
	end

	local ticker = RunService.Heartbeat:Connect(function(delta)
		if destroyed then return end
		clockAccum += delta
		-- 1 Hz, and only while the page is on screen: a countdown redrawn every
		-- frame is 59 wasted string builds a second, and one redrawn behind a
		-- closed modal is 60.
		if clockAccum >= 1 then
			clockAccum = 0
			if visible() then updateClocks() end
		end
	end)

	local stopProfile = call(ctx.onProfile, function(profile)
		if destroyed then return end
		-- ANY push is the server's answer to whatever was in flight: it carries
		-- the committed state, so nothing local needs to be believed any more.
		table.clear(pending)
		rollAsked = false
		local daily = dailyOf(profile)
		local seconds = daily and tonumber(daily.SecondsToReset) or nil
		-- Re-anchored on every push, which is what keeps the local countdown
		-- from drifting without a second clock to reconcile.
		resetAt = seconds and (now() + math.max(0, seconds)) or nil
		render()
	end)

	local handle = {}

	function handle.refresh()
		local daily = dailyOf(call(ctx.profile))
		local seconds = daily and tonumber(daily.SecondsToReset) or nil
		if seconds then resetAt = now() + math.max(0, seconds) end
		render()
	end

	function handle.destroy()
		destroyed = true
		if ticker then ticker:Disconnect() end
		if type(stopProfile) == "function" then stopProfile() end
		table.clear(pending)
		scroll:Destroy()
	end

	handle.refresh()
	return handle
end

return Page
