-- ZyntraDailyRewardsPage -- the terminal's DAILY REWARDS tab. (Trello #83/#84/#89)
--
-- WHAT THIS PAGE IS ALLOWED TO DECIDE: nothing. Every number on it is read back
-- from the public profile the server already committed -- how many seconds of
-- ACTIVE round play the player has today, which milestones are already claimed,
-- whether today's free spin is spent and which prize it landed on. The page
-- asks (`ClaimPlaytimeReward`, `SpinDailyWheel`) and then RE-READS; it never
-- grants, never picks a prize, and never keeps a second copy of the state that
-- could disagree with the save. That is what makes loss, rejoin, retry and a
-- double press incapable of granting twice: the second press is a second read.
--
-- WHY THE WHEEL ANIMATES AFTER THE FACT. The server picks and WRITES the prize
-- inside its own transaction before it answers, so by the time this file sees
-- `Daily.WheelLast` the outcome is already durable. The animation is a replay
-- of a recorded result, which is why it can be skipped, cut short by closing
-- the terminal, or -- on a REPLAY push carrying the same Serial -- not played
-- at all. It never decides where it lands.
--
-- WHY THE COUNTDOWN IS LOCAL AND THE DAY IS UTC. The reset boundary is a UTC
-- day so every player on every server rolls over at the same instant; the
-- countdown to it ticks off `workspace:GetServerTimeNow()`, re-anchored on
-- EVERY push, so it stays honest without a second clock to keep in sync.
--
-- The page draws only inside the frame it is handed, never requires ZyntraStore
-- (the mount is the other direction), and never yields at require.

local RunService = game:GetService("RunService")

-- The spin is a garnish on a decision already made, so it is bounded hard: the
-- player can skip it, and even untouched it is over well inside the brief's
-- 2.5 s ceiling. The first step is 0.11 s, which caps the highlight at ~9
-- moves/second before it decelerates -- and ReduceFlashing replaces the whole
-- stepping pass with one slow fade rather than a slower flicker.
local SPIN_STEP_FIRST = 0.11
local SPIN_STEP_GROWTH = 1.15
local SPIN_BUDGET = 2.2
local SPIN_FADE_SECONDS = 1.2

-- How long a request may sit unanswered before the page stops pretending. The
-- terminal's own write window is 1 s, so 6 s is a genuine failure rather than a
-- rate limit, and the recovery is a RE-READ -- never a local grant.
local ACTION_TIMEOUT = 6

-- Three tiers, taken from the two facts the terminal publishes about itself,
-- exactly as ZyntraStore's own Upgrades and Shop pages take them:
--   1  phone    fit.Compact AND fit.Touch
--   2  tablet   fit.Touch, not compact
--   3  pointer  neither
-- Nothing here is under 11px, including the eyebrow: the shared token is 10,
-- but that face is drawn at arm's length on a HUD, not inside a scrolling
-- panel a phone holds a foot from someone's eyes.
local FACES = {
	{Pad = 12, Gap = 10, Eyebrow = 11, Title = 20, Section = 15, Card = 14,
		Body = 11, Clock = 15, Button = 44, Row = 46, Swatch = 8},
	{Pad = 14, Gap = 12, Eyebrow = 11, Title = 24, Section = 17, Card = 16,
		Body = 12, Clock = 18, Button = 44, Row = 50, Swatch = 10},
	{Pad = 16, Gap = 14, Eyebrow = 11, Title = 28, Section = 18, Card = 17,
		Body = 13, Clock = 21, Button = 40, Row = 56, Swatch = 12},
}

-- Two columns need room for TWO readable columns, not merely a wide panel: the
-- wheel's widest row is a label plus an odds readout, and below this the pair
-- reads better stacked than squeezed.
local TWO_COLUMN_MIN = 620
-- The terminal's scrollbar is 5px and sits inside the page, so the content
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

-- A reward as the player reads it. The wheel's config entries carry their own
-- Label; the milestones do not, so their copy is derived from the SAME config
-- the server grants from and cannot drift from what actually lands.
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

-- Whole percent, from the SERVER's own weights. Rounded values need not sum to
-- exactly 100 if the weights are awkward, and that is preferred to inventing a
-- precision the roll does not have; the shipped weights sum to 100 exactly.
local function oddsText(weight: number, total: number): string
	if total <= 0 then return "--" end
	return tostring(math.floor(weight / total * 100 + 0.5)) .. "%"
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
	-- ACCENTS come from the terminal's own palette, so the tab reads like the
	-- panel it copies without clashing with the terminal it lives in. Teal is
	-- the system colour; gold is money, and only money.
	local accent = COLORS.accent or UIStyle.Color.Accent
	local gold = COLORS.accent2 or UIStyle.Color.Warning
	local muted = COLORS.muted or UIStyle.Color.Muted
	local bodyColor = UIStyle.Color.Body
	local titleColor = COLORS.text or UIStyle.Color.Title

	local rewards = type(Config.DailyRewards) == "table" and Config.DailyRewards or nil

	local scroll = Instance.new("ScrollingFrame")
	-- NAMED like every other page scroll in this terminal: "ScrollingFrame" is
	-- not something a failure report can point a reader at.
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

	local eyebrow = ctx.label(header, "ZYNTRA // DAILY SUPPLY", UDim2.new(),
		UDim2.new(), 11, UIStyle.Color.AccentText, UIStyle.Font.Readout)
	eyebrow.Name = "Eyebrow"
	local title = ctx.label(header, "DAILY REWARDS", UDim2.new(), UDim2.new(),
		20, titleColor, UIStyle.Font.Title)
	title.Name = "Title"

	-- The countdown and its UTC note travel together -- one moves to the right
	-- of the title on a wide panel, one sits under it on a phone -- so they are
	-- placed as a block instead of two independently guessed rectangles.
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

	-- ── wheel ────────────────────────────────────────────────────────────────
	local wheel = Instance.new("Frame")
	wheel.Name = "WheelSection"
	wheel.Parent = scroll
	UIStyle.panel(wheel, {Background = UIStyle.Color.Card,
		Transparency = UIStyle.Transparency.Card, Radius = UIStyle.Radius.Card,
		StrokeTransparency = UIStyle.Stroke.CardTransparency})

	local wheelTitle = ctx.label(wheel, "SUPPLY WHEEL", UDim2.new(), UDim2.new(),
		15, titleColor, UIStyle.Font.Title)
	wheelTitle.Name = "SectionTitle"
	local oddsNote = ctx.label(wheel, "One free spin a day. These are the real odds.",
		UDim2.new(), UDim2.new(), 11, muted, UIStyle.Font.Body)
	oddsNote.Name = "OddsNote"

	-- The five prizes, with the weights the server rolls on. Drawn as a list
	-- with a proportional bar per row rather than a pie: a pie built out of
	-- rotated frames is unreadable at a phone's width and needs artwork this
	-- project has not approved, and the thing a player actually wants to read
	-- is "what can I get, and how likely is it".
	local segments = {}
	local weightTotal = 0
	for _, entry in ipairs(rewards and rewards.Wheel or {}) do
		if type(entry) == "table" then
			weightTotal += math.max(0, tonumber(entry.Weight) or 0)
		end
	end
	for order, entry in ipairs(rewards and rewards.Wheel or {}) do
		if type(entry) == "table" then
			local weight = math.max(0, tonumber(entry.Weight) or 0)
			local row = Instance.new("Frame")
			row.Name = "Segment" .. tostring(order)
			row.BackgroundTransparency = 1
			row.Parent = wheel

			-- The highlight is a separate frame whose TRANSPARENCY moves. Roblox
			-- Color3 has no arithmetic, so an animation that "fades a colour"
			-- would have to build a new Color3 per frame from three lerped
			-- channels; fading a fixed-colour surface says the same thing and
			-- cannot drift off-palette.
			local highlight = Instance.new("Frame")
			highlight.Name = "Highlight"
			highlight.Size = UDim2.fromScale(1, 1)
			highlight.BackgroundColor3 = accent
			highlight.BackgroundTransparency = 1
			highlight.BorderSizePixel = 0
			highlight.Parent = row
			call(ctx.corner, highlight, 7)

			local reward = entry.Reward
			local kindColor = accent
			if type(reward) == "table" then
				if reward.Kind == "Tokens" then
					kindColor = gold
				elseif reward.Key == "EntityShield" then
					kindColor = UIStyle.Color.Positive
				end
			end

			local swatch = Instance.new("Frame")
			swatch.Name = "Swatch"
			swatch.BackgroundColor3 = kindColor
			swatch.BorderSizePixel = 0
			swatch.Parent = row
			call(ctx.corner, swatch, 3)

			local segmentLabel = ctx.label(row, tostring(entry.Label or rewardLabel(Config, reward)),
				UDim2.new(), UDim2.new(), 11, bodyColor, UIStyle.Font.Body)
			segmentLabel.Name = "SegmentLabel"
			local segmentOdds = ctx.label(row, oddsText(weight, weightTotal), UDim2.new(),
				UDim2.new(), 11, kindColor, UIStyle.Font.Readout)
			segmentOdds.Name = "SegmentOdds"
			segmentOdds.TextXAlignment = Enum.TextXAlignment.Right

			local bar = Instance.new("Frame")
			bar.Name = "OddsBar"
			bar.BackgroundColor3 = kindColor
			bar.BackgroundTransparency = 0.45
			bar.BorderSizePixel = 0
			bar.Parent = row
			call(ctx.corner, bar, 2)

			table.insert(segments, {
				Key = tostring(entry.Key or ""),
				Label = tostring(entry.Label or rewardLabel(Config, reward)),
				Weight = weight,
				Share = weightTotal > 0 and weight / weightTotal or 0,
				Row = row,
				Highlight = highlight,
				Swatch = swatch,
				Bar = bar,
				LabelText = segmentLabel,
				OddsText = segmentOdds,
			})
		end
	end

	local spin = ctx.button(wheel, "FREE SPIN", UDim2.new(), UDim2.new())
	spin.Name = "SpinButton"
	-- Registered only when there is a wheel to spin. The fit matrix measures
	-- every TAGGED action and requires it to be drawn, so tagging the control
	-- of a section this server hid would report a hidden rectangle as a fault.
	if #segments > 0 then call(contract.card, pageName, "Wheel", wheel, spin) end

	-- SKIP is deliberately NOT a contract card. It exists only while a result is
	-- replaying, and a card action the fit matrix has to find must be drawn at
	-- every moment the page is open.
	local skip = ctx.button(wheel, "SKIP", UDim2.new(), UDim2.new())
	skip.Name = "SkipButton"
	skip.Visible = false

	local banner = Instance.new("Frame")
	banner.Name = "ResultBanner"
	banner.Visible = false
	banner.Parent = wheel
	UIStyle.caption(banner)
	local bannerText = ctx.label(banner, "", UDim2.new(), UDim2.new(), 13,
		UIStyle.Color.Live, UIStyle.Font.Readout)
	bannerText.Name = "ResultText"
	bannerText.TextXAlignment = Enum.TextXAlignment.Center

	local nextSpin = ctx.label(wheel, "", UDim2.new(), UDim2.new(), 11, muted, UIStyle.Font.Body)
	nextSpin.Name = "NextSpinNote"
	nextSpin.Visible = false

	local offline
	if not rewards then
		-- The config and the server that honours it land together, so with the
		-- config absent a CLAIM button would be a control that cannot work. The
		-- page says so instead of offering one.
		offline = ctx.label(scroll, "Daily rewards are not configured on this server.",
			UDim2.new(), UDim2.new(), 12, COLORS.error or UIStyle.Color.Danger, UIStyle.Font.Body)
		offline.Name = "RewardsOffline"
		playtime.Visible = false
		wheel.Visible = false
	end

	-- ── state ────────────────────────────────────────────────────────────────
	local destroyed = false
	local lastFit = nil
	local pending = {}          -- request key -> serial, cleared by any push
	local pendingSeq = 0
	local resetAt = nil         -- server-clock instant of the next 00:00 UTC
	local rollAsked = false
	local sawProfile = false    -- a profile has been read at least once
	local wheelSeenSerial = nil -- the last spin Serial this session has DRAWN
	local spinActive = false
	local spinReduced = false
	local spinWinner = nil
	local spinElapsed = 0
	local spinTotal = 0
	local spinSteps = nil
	local clockAccum = 0
	local render
	-- Forward-declared: render() re-runs the layout after it changes what is
	-- drawn (the banner and SKIP both take room), and the layout is defined
	-- below it. A module-level handle would be shared between mounts.
	local layoutFor

	local function now(): number
		return workspace:GetServerTimeNow()
	end

	local function reduceFlashing(): boolean
		local who = ctx.player
		return who ~= nil and who:GetAttribute("ReduceFlashing") == true
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

	local function setHighlight(index: number?, transparency: number)
		for order, segment in ipairs(segments) do
			segment.Highlight.BackgroundTransparency = order == index and transparency or 1
		end
	end

	-- Walk BACKWARDS from the recorded prize so the last step is always the one
	-- the server wrote: the animation cannot land anywhere else, whatever the
	-- step count works out to.
	local function buildSteps(winner: number)
		local plan, total, step = {}, 0, SPIN_STEP_FIRST
		while total + step <= SPIN_BUDGET do
			total += step
			table.insert(plan, total)
			step *= SPIN_STEP_GROWTH
		end
		if #plan == 0 then
			plan = {SPIN_STEP_FIRST}
			total = SPIN_STEP_FIRST
		end
		local count, size = #plan, #segments
		local order = table.create(count)
		for at = count, 1, -1 do
			order[at] = ((winner - 1 - (count - at)) % size) + 1
		end
		return plan, order, total
	end

	local function finishSpin()
		spinActive = false
		setHighlight(spinWinner, 0)
		render()
	end

	local function startSpin(winner: number)
		spinWinner = winner
		spinElapsed = 0
		spinActive = true
		spinReduced = reduceFlashing()
		if spinReduced then
			-- No stepping at all: the winning segment alone fades up. Nothing
			-- else on the page changes colour, so the 2-per-second ceiling is
			-- met by construction rather than by a rate limiter.
			spinSteps, spinTotal = nil, SPIN_FADE_SECONDS
			setHighlight(winner, 1)
		else
			local plan, order, total = buildSteps(winner)
			spinSteps, spinTotal = {Plan = plan, Order = order}, total
			setHighlight(order[1], 0)
		end
		if not visible() then finishSpin() end
	end

	local function stepAt(elapsed: number): number
		local plan, order = spinSteps.Plan, spinSteps.Order
		for at = 1, #plan do
			if elapsed < plan[at] then return order[at] end
		end
		return order[#order]
	end

	local function dailyOf(profile)
		if type(profile) ~= "table" then return nil end
		return type(profile.Daily) == "table" and profile.Daily or nil
	end

	local function segmentByKey(key: string)
		for order, segment in ipairs(segments) do
			if segment.Key == key then return order, segment end
		end
		return nil, nil
	end

	-- The clocks are the only thing that changes without a push, so they are the
	-- only thing the 1 Hz ticker redraws.
	local function updateClocks(spun: boolean?)
		local remaining = resetAt and math.max(0, resetAt - now()) or nil
		countdown.Text = remaining and ("RESETS IN " .. formatClock(remaining)) or "RESETS IN --:--:--"
		if spun ~= nil then
			nextSpin.Visible = spun == true
		end
		if nextSpin.Visible then
			nextSpin.Text = remaining and ("Next spin in " .. formatClock(remaining))
				or "Next spin after the daily reset"
		end
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

		-- The wheel. WheelDay is compared to TODAY rather than to Daily.Day, for
		-- the same reason the counters are: it is never reset, only outgrown.
		local spun = daily ~= nil and today ~= "" and tostring(daily.WheelDay or "") == today
		local record = daily and type(daily.WheelLast) == "table" and daily.WheelLast or nil
		local recorded = record and today ~= "" and tostring(record.Day or "") == today and record or nil

		if recorded then
			local serial = tonumber(recorded.Serial) or 0
			if not sawProfile then
				-- THE FIRST PROFILE THIS SESSION READS is a seed, never a
				-- trigger: a player who spun this morning and rejoined at lunch
				-- is shown their prize, not made to watch it land again. The
				-- flag is the whole page's first read, not the first time a
				-- record happens to appear -- a spin made HERE arrives on a
				-- later push and has to replay.
				wheelSeenSerial = serial
			elseif serial ~= wheelSeenSerial then
				wheelSeenSerial = serial
				local index = segmentByKey(tostring(recorded.Key or ""))
				if index and not spinActive then startSpin(index) end
			end
		end
		if daily ~= nil then sawProfile = true end

		if pending.Wheel or spinActive then
			spin.Text = "SPINNING..."
			spin.TextColor3 = muted
			setEnabled(spin, false)
		elseif spun then
			spin.Text = "SPUN TODAY"
			spin.TextColor3 = muted
			setEnabled(spin, false)
		else
			spin.Text = "FREE SPIN"
			spin.TextColor3 = accent
			setEnabled(spin, true)
		end
		skip.Visible = spinActive
		setEnabled(skip, spinActive)

		local index, segment = nil, nil
		if recorded then index, segment = segmentByKey(tostring(recorded.Key or "")) end
		banner.Visible = segment ~= nil and not spinActive
		if banner.Visible and segment then
			bannerText.Text = "YOU RECEIVED: " .. segment.Label
			setHighlight(index, 0.55)
		elseif not spinActive then
			setHighlight(nil, 1)
		end

		updateClocks(spun)
		-- Sections grow and shrink with the banner and the SKIP control, so the
		-- geometry is re-resolved from the fit the terminal last published
		-- rather than left describing the previous state.
		if lastFit then layoutFor(lastFit) end
	end

	-- ── layout ───────────────────────────────────────────────────────────────
	-- Every rectangle on this page is an OFFSET derived from fit.ContentWidth,
	-- the way ZyntraStore's own pages derive theirs, so "does this card fit" is
	-- arithmetic a test can do rather than a screenshot someone has to look at.
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
		local twoColumn = tier > 1 and usable >= TWO_COLUMN_MIN
		local column = twoColumn and math.floor((usable - gap) / 2) or usable
		local inner = math.max(60, column - pad * 2)

		-- header
		local eyebrowHeight = face.Eyebrow + 5
		local titleHeight = face.Title + 10
		local clockHeight = face.Clock + 8
		local noteHeight = face.Body + 6
		local clockWidth = twoColumn
			and math.min(260, math.max(150, math.floor(usable * 0.34)))
			or (usable - pad * 2 - 8)
		local copyWidth = math.max(60, usable - pad * 2 - 8 - (twoColumn and clockWidth + gap or 0))
		local stackHeight = pad + eyebrowHeight + 4 + titleHeight
		local headerHeight = twoColumn
			and math.max(stackHeight + pad, pad + clockHeight + 2 + noteHeight + pad)
			or (stackHeight + 6 + clockHeight + 2 + noteHeight + pad)

		header.Position = UDim2.fromOffset(0, 0)
		header.Size = UDim2.fromOffset(usable, headerHeight)
		headerAccent.Position = UDim2.fromOffset(0, 10)
		headerAccent.Size = UDim2.fromOffset(3, math.max(8, headerHeight - 20))
		eyebrow.Position = UDim2.fromOffset(pad + 8, pad)
		eyebrow.Size = UDim2.fromOffset(copyWidth, eyebrowHeight)
		eyebrow.TextSize = face.Eyebrow
		title.Position = UDim2.fromOffset(pad + 8, pad + eyebrowHeight + 4)
		title.Size = UDim2.fromOffset(copyWidth, titleHeight)
		title.TextSize = face.Title

		resetBlock.Size = UDim2.fromOffset(clockWidth, clockHeight + 2 + noteHeight)
		resetBlock.Position = twoColumn
			and UDim2.fromOffset(usable - pad - clockWidth, pad)
			or UDim2.fromOffset(pad + 8, stackHeight + 6)
		countdown.Position = UDim2.fromOffset(0, 0)
		countdown.Size = UDim2.fromOffset(clockWidth, clockHeight)
		countdown.TextSize = face.Clock
		countdown.TextXAlignment = twoColumn and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
		resetNote.Position = UDim2.fromOffset(0, clockHeight + 2)
		resetNote.Size = UDim2.fromOffset(clockWidth, noteHeight)
		resetNote.TextSize = face.Body
		resetNote.TextXAlignment = countdown.TextXAlignment

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
		local playtimeHeight = y + playtimeNoteHeight + pad

		-- wheel
		local rowHeight = face.Row
		local oddsWidth = math.max(44, math.floor(face.Body * 3.4))
		y = pad
		wheelTitle.Position = UDim2.fromOffset(pad, y)
		wheelTitle.Size = UDim2.fromOffset(inner, sectionTitleHeight)
		wheelTitle.TextSize = face.Section
		y += sectionTitleHeight + 4
		oddsNote.Position = UDim2.fromOffset(pad, y)
		oddsNote.Size = UDim2.fromOffset(inner, captionHeight)
		oddsNote.TextSize = face.Body
		y += captionHeight + gap
		local labelLeft = face.Swatch + 12
		local labelWidth = math.max(40, inner - labelLeft - oddsWidth - 8)
		for _, segment in ipairs(segments) do
			segment.Row.Position = UDim2.fromOffset(pad, y)
			segment.Row.Size = UDim2.fromOffset(inner, rowHeight)
			segment.Swatch.Position = UDim2.fromOffset(4, math.floor((rowHeight - face.Swatch) / 2))
			segment.Swatch.Size = UDim2.fromOffset(face.Swatch, face.Swatch)
			segment.LabelText.Position = UDim2.fromOffset(labelLeft, 5)
			segment.LabelText.Size = UDim2.fromOffset(labelWidth, face.Body + 10)
			segment.LabelText.TextSize = face.Body
			segment.OddsText.Position = UDim2.fromOffset(inner - oddsWidth - 6, 5)
			segment.OddsText.Size = UDim2.fromOffset(oddsWidth, face.Body + 10)
			segment.OddsText.TextSize = face.Body
			segment.Bar.Position = UDim2.fromOffset(labelLeft, rowHeight - 12)
			segment.Bar.Size = UDim2.fromOffset(
				math.max(2, math.floor(labelWidth * segment.Share)), 3)
			y += rowHeight + 6
		end
		if #segments > 0 then y += gap - 6 end

		local skipWidth = math.max(tap, 92)
		spin.Position = UDim2.fromOffset(pad, y)
		spin.Size = UDim2.fromOffset(
			math.max(44, inner - (skip.Visible and skipWidth + 8 or 0)), buttonHeight)
		spin.TextSize = face.Body + 3
		skip.Position = UDim2.fromOffset(pad + inner - skipWidth, y)
		skip.Size = UDim2.fromOffset(skipWidth, buttonHeight)
		skip.TextSize = face.Body + 1
		y += buttonHeight + gap

		if banner.Visible then
			local bannerHeight = face.Body + 24
			banner.Position = UDim2.fromOffset(pad, y)
			banner.Size = UDim2.fromOffset(inner, bannerHeight)
			bannerText.Position = UDim2.fromOffset(10, 0)
			bannerText.Size = UDim2.fromOffset(math.max(40, inner - 20), bannerHeight)
			bannerText.TextSize = face.Body + 2
			y += bannerHeight + 6
		end
		if nextSpin.Visible then
			nextSpin.Position = UDim2.fromOffset(pad, y)
			nextSpin.Size = UDim2.fromOffset(inner, captionHeight)
			nextSpin.TextSize = face.Body
			y += captionHeight + 6
		end
		local wheelHeight = y + pad - 6

		playtime.Position = UDim2.fromOffset(0, top)
		playtime.Size = UDim2.fromOffset(column, playtimeHeight)
		if twoColumn then
			wheel.Position = UDim2.fromOffset(column + gap, top)
			wheel.Size = UDim2.fromOffset(column, wheelHeight)
			scroll.CanvasSize = UDim2.fromOffset(0,
				top + math.max(playtimeHeight, wheelHeight) + pad)
		else
			wheel.Position = UDim2.fromOffset(0, top + playtimeHeight + gap)
			wheel.Size = UDim2.fromOffset(column, wheelHeight)
			scroll.CanvasSize = UDim2.fromOffset(0,
				top + playtimeHeight + gap + wheelHeight + pad)
		end
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

	spin.Activated:Connect(function()
		if destroyed or pending.Wheel or spinActive then return end
		if not spin.Active then return end
		await("Wheel")
		call(ctx.action, "SpinDailyWheel")
		render()
	end)

	skip.Activated:Connect(function()
		if spinActive then finishSpin() end
	end)

	local ticker = RunService.Heartbeat:Connect(function(delta)
		if destroyed then return end
		if spinActive then
			if not visible() then
				-- Nobody is watching the replay, so it is over. The prize was
				-- already banked; only the garnish is being skipped.
				finishSpin()
			else
				spinElapsed += delta
				if spinElapsed >= spinTotal then
					finishSpin()
				elseif spinReduced then
					setHighlight(spinWinner, 1 - clamp01(spinElapsed / SPIN_FADE_SECONDS))
				else
					setHighlight(stepAt(spinElapsed), 0)
				end
			end
		end
		clockAccum += delta
		-- 1 Hz, and only while the page is on screen: a countdown redrawn every
		-- frame is 59 wasted string builds a second, and one redrawn behind a
		-- closed terminal is 60.
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
