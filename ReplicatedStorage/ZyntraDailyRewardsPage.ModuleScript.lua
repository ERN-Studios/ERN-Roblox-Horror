-- ZyntraDailyRewardsPage -- the DAILY REWARDS page. (Trello #83/#84/#89/#104,
-- rebuilt 2026-09-16 for the "make it inviting" round.)
--
-- WHAT THIS PAGE IS ALLOWED TO DECIDE: nothing. Every number on it is read back
-- from the public profile the server already committed -- how many seconds of
-- ACTIVE round play the player has today, and which milestones are already
-- claimed. The page asks (`ClaimPlaytimeReward`) and then RE-READS; it never
-- grants and never keeps a second copy of the state that could disagree with
-- the save. That is what makes loss, rejoin, retry and a double press incapable
-- of granting twice: the second press is a second read.
--
-- WHAT THE 2026-09-16 REBUILD CHANGED, AND WHAT IT DID NOT. Only the drawing.
-- The three milestones still come from `Config.DailyRewards.Milestones`, the
-- request is still `ClaimPlaytimeReward {Minutes}` with one in flight and a 6 s
-- re-read, the countdown is still `SecondsToReset` re-anchored on every push,
-- and the card frames are still named `Milestone<minutes>` with a
-- `ClaimButton` inside. What changed is that a card is now a big coloured panel
-- with the product's own art on it instead of a row of text: threshold, icon,
-- reward name, state. Nothing about the economy moved, and there is no
-- seven-day streak -- the reference the owner supplied was energy, not content.
--
-- WHY THE ART IS KEYED ON THE REWARD AND NOT ON THE MINUTES. `REWARD_ART` below
-- is indexed by `Kind`/`Key`, the same two fields the SERVER grants from. Keyed
-- on "5" instead, the day somebody re-orders the config table the 5 minute card
-- would draw a token over a potion and the page would be lying about what lands.
--
-- WHY THE CARDS ARE WHITE. A UIGradient MODULATES the object's BackgroundColor3
-- rather than replacing it, so a gold gradient over a dark card renders as a
-- dark card. Every gradient-bearing frame here is white underneath on purpose.
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
-- Client", which builds its own modal shell -- the warm header with the gift,
-- the title and the X -- and hands this page its content frame. The page cannot
-- tell the two apart and must not try to, which is why the page draws no title
-- and no close control of its own.
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
-- Nothing here is under 11px. `Button` is 44 at every tier, not just on touch:
-- CLAIM is meant to be the most prominent thing on a ready card, and a 28px
-- CLAIM on a desktop is a smaller promise than the icon above it.
local FACES = {
	{Pad = 12, Gap = 10, Clock = 15, Threshold = 16, Name = 12, Body = 11, Button = 44},
	{Pad = 14, Gap = 12, Clock = 18, Threshold = 19, Name = 14, Body = 12, Button = 44},
	{Pad = 16, Gap = 14, Clock = 19, Threshold = 21, Name = 15, Body = 13, Button = 44},
}

-- The host's scrollbar is 5px and sits inside the page, so the content
-- stops short of it rather than under it.
local SCROLLBAR_ROOM = 8
-- One horizontal card per row on a phone held UPRIGHT; that card is 150 tall
-- with the icon filling its left edge. Three cards across 330px of content
-- would be 100px each -- narrower than the art they exist to show.
local COLUMN_CARD_HEIGHT = 150
-- The icon is the card. 45% of the card's height is the floor the owner's brief
-- set ("hold belysningen stor og dominant"); 56px is the floor a finger-sized
-- landscape card cannot go under.
local ICON_SHARE = 0.45
local ICON_FLOOR = 56

-- Codex's uploaded art (artifacts/wheel-shop-refresh-20260916/REWARDS-ASSETS.md).
-- Every PNG carries its own air around the motif, which is why every label is
-- ScaleType.Fit and sized for the visual rather than for the file.
local REWARD_ART = {
	Tokens = {
		Icon = "rbxassetid://93116899475472",
		From = Color3.fromRGB(255, 205, 60), To = Color3.fromRGB(255, 150, 30),
	},
	SpeedPotion = {
		Icon = "rbxassetid://120211340805188",
		From = Color3.fromRGB(80, 220, 255), To = Color3.fromRGB(40, 120, 220),
	},
	EntityShield = {
		Icon = "rbxassetid://126728249949579",
		From = Color3.fromRGB(150, 90, 230), To = Color3.fromRGB(60, 200, 140),
	},
}

local CLAIM_READY = Color3.fromRGB(70, 200, 90)
local CLAIM_LOCKED = Color3.fromRGB(26, 34, 37)
local CARD_WHITE = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(255, 255, 255)
-- The stroke every white word on a coloured card carries. Gold under white text
-- is the one combination on this page with no contrast of its own.
local INK_SHADOW = Color3.fromRGB(24, 20, 10)

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

-- HH:MM:SS, for the reset countdown. Always three fields: a reset that reads
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

-- Which art a milestone wears, from the two fields the server grants from.
local function artFor(reward)
	if type(reward) ~= "table" then return REWARD_ART.Tokens end
	if reward.Kind == "Tokens" then return REWARD_ART.Tokens end
	return REWARD_ART[tostring(reward.Key or "")] or REWARD_ART.Tokens
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

	-- The claimed card HIDES its button rather than relabelling it: a green
	-- check plus the word CLAIMED is the state, and a disabled button that still
	-- occupies the row reads as something that failed rather than something that
	-- is done.
	local function setShown(element, shown: boolean)
		if UIDevice and type(UIDevice.SetInteractive) == "function" then
			UIDevice.SetInteractive(element, shown)
		else
			element.Visible = shown
			element.Active = shown
		end
	end

	-- A circle, for the claimed badge. ctx.corner only speaks offsets.
	local function circle(frame)
		local object = Instance.new("UICorner")
		object.CornerRadius = UDim.new(1, 0)
		object.Parent = frame
		return object
	end

	-- Contextual is the DEFAULT ApplyStrokeMode and on a TextLabel it outlines
	-- the TEXT, which is exactly what white copy over a gold gradient needs.
	-- UIStyle's own helpers force Border, so this is its own three lines.
	local function textShadow(object, thickness: number)
		local stroke = Instance.new("UIStroke")
		stroke.Color = INK_SHADOW
		stroke.Thickness = thickness
		stroke.Transparency = 0.2
		stroke.Parent = object
		return stroke
	end

	-- Two-stop vertical gradient. The frame underneath must be WHITE: UIGradient
	-- multiplies BackgroundColor3, it does not replace it.
	local function gradient(frame, from, to)
		local object = Instance.new("UIGradient")
		object.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, from),
			ColorSequenceKeypoint.new(1, to),
		})
		object.Rotation = 90
		object.Parent = frame
		return object
	end

	-- SURFACES AND TYPE come from the shared UIStyle -- the owner named Level 1's
	-- Objectives panel and the Mission Brief as the reference -- while the two
	-- ACCENTS come from the host's own palette (ctx.COLORS), so the page reads
	-- like the panel it copies without clashing with the modal it lives in. Teal
	-- is the system colour; gold is money, and only money.
	local accent = COLORS.accent or UIStyle.Color.Accent
	local muted = COLORS.muted or UIStyle.Color.Muted

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

	-- ── the two strips ───────────────────────────────────────────────────────
	-- WHAT THE PAGE OWNS OF THE CHROME: state. The host owns the modal's
	-- identity (gift, title, X); the countdown and the play readout are numbers
	-- that change, so they are drawn here, next to the cards they explain.
	local countdownStrip = Instance.new("Frame")
	countdownStrip.Name = "CountdownStrip"
	countdownStrip.Parent = scroll
	UIStyle.panel(countdownStrip, {Background = UIStyle.Color.Card,
		Transparency = UIStyle.Transparency.Card, Radius = UIStyle.Radius.Chip,
		StrokeTransparency = UIStyle.Stroke.RowTransparency})

	local countdown = ctx.label(countdownStrip, "RESETS IN --:--:--", UDim2.new(),
		UDim2.new(), 15, accent, UIStyle.Font.Readout)
	countdown.Name = "ResetCountdown"

	-- Everything under the countdown lives in one container so the "this server
	-- has no daily rewards configured" branch is a single Visible flip rather
	-- than six.
	local body = Instance.new("Frame")
	body.Name = "PlaytimeSection"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Parent = scroll

	local playStrip = Instance.new("Frame")
	playStrip.Name = "PlayStrip"
	playStrip.Parent = body
	UIStyle.panel(playStrip, {Background = UIStyle.Color.Card,
		Transparency = UIStyle.Transparency.Card, Radius = UIStyle.Radius.Card,
		StrokeTransparency = UIStyle.Stroke.CardTransparency})

	local playtimeReadout = ctx.label(playStrip, "ACTIVE PLAY TODAY  0:00", UDim2.new(),
		UDim2.new(), 15, accent, UIStyle.Font.Readout)
	playtimeReadout.Name = "PlaytimeReadout"

	local track = Instance.new("Frame")
	track.Name = "ProgressTrack"
	track.BackgroundColor3 = Color3.fromRGB(52, 63, 57)
	track.BackgroundTransparency = 0.28
	track.BorderSizePixel = 0
	track.Parent = playStrip
	call(ctx.corner, track, 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	call(ctx.corner, fill, 2)

	local progressCaption = ctx.label(playStrip, "", UDim2.new(), UDim2.new(),
		11, muted, UIStyle.Font.Body)
	progressCaption.Name = "ProgressCaption"

	-- ── the three cards ──────────────────────────────────────────────────────
	local milestones = {}
	for order, entry in ipairs(rewards and rewards.Milestones or {}) do
		local minutes = type(entry) == "table" and math.floor(tonumber(entry.Minutes) or 0) or 0
		if minutes > 0 then
			local reward = type(entry) == "table" and entry.Reward or nil
			local art = artFor(reward)

			local card = Instance.new("Frame")
			card.Name = "Milestone" .. tostring(minutes)
			card.LayoutOrder = order
			card.BackgroundColor3 = CARD_WHITE
			card.BackgroundTransparency = 0
			card.BorderSizePixel = 0
			card.Parent = body
			call(ctx.corner, card, 12)
			gradient(card, art.From, art.To)
			local cardEdge = Instance.new("UIStroke")
			cardEdge.Color = CARD_WHITE
			cardEdge.Thickness = 2
			cardEdge.Transparency = 0.6
			cardEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			cardEdge.Parent = card

			local threshold = ctx.label(card, tostring(minutes) .. " MIN", UDim2.new(),
				UDim2.new(), 16, INK, Enum.Font.GothamBlack)
			threshold.Name = "Threshold"
			textShadow(threshold, 2)

			local icon = Instance.new("ImageLabel")
			icon.Name = "RewardIcon"
			icon.Image = art.Icon
			icon.ScaleType = Enum.ScaleType.Fit
			icon.BackgroundTransparency = 1
			icon.BorderSizePixel = 0
			icon.Parent = card

			-- The badge sits ON the art, the way the owner's reference draws it,
			-- with the word underneath in the state row. Hidden until the profile
			-- says the milestone is claimed.
			local check = Instance.new("Frame")
			check.Name = "ClaimedCheck"
			check.BackgroundColor3 = CLAIM_READY
			check.BorderSizePixel = 0
			check.Visible = false
			check.ZIndex = 3
			check.Parent = card
			circle(check)
			local checkEdge = Instance.new("UIStroke")
			checkEdge.Color = CARD_WHITE
			checkEdge.Thickness = 2
			checkEdge.Transparency = 0.15
			checkEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			checkEdge.Parent = check
			local checkMark = ctx.label(check, "\u{2713}", UDim2.fromScale(1, 1),
				UDim2.new(), 20, INK, Enum.Font.GothamBlack)
			checkMark.Name = "CheckMark"
			checkMark.TextXAlignment = Enum.TextXAlignment.Center
			checkMark.ZIndex = 3

			local name = ctx.label(card, rewardLabel(Config, reward), UDim2.new(),
				UDim2.new(), 12, INK, Enum.Font.GothamBold)
			name.Name = "RewardName"
			textShadow(name, 1.5)

			-- Built here rather than through ctx.button: the host's helper wires a
			-- MouseLeave that puts its own card colour back, which would wipe the
			-- green off CLAIM the moment the pointer left it.
			local claim = Instance.new("TextButton")
			claim.Name = "ClaimButton"
			claim.AutoButtonColor = false
			claim.BackgroundColor3 = CLAIM_LOCKED
			claim.BorderSizePixel = 0
			claim.Font = Enum.Font.GothamBlack
			claim.Text = "CLAIM"
			claim.TextColor3 = INK
			claim.TextSize = 14
			claim.Parent = card
			call(ctx.corner, claim, 10)

			local claimed = ctx.label(card, "CLAIMED", UDim2.new(), UDim2.new(),
				14, INK, Enum.Font.GothamBlack)
			claimed.Name = "ClaimedLabel"
			claimed.TextXAlignment = Enum.TextXAlignment.Center
			claimed.Visible = false
			textShadow(claimed, 2)

			call(contract.card, pageName, "Playtime" .. tostring(minutes), card, claim)

			table.insert(milestones, {
				Minutes = minutes,
				Seconds = minutes * 60,
				Key = tostring(minutes),
				Card = card,
				Threshold = threshold,
				Icon = icon,
				Name = name,
				Button = claim,
				Check = check,
				CheckMark = checkMark,
				Claimed = claimed,
			})
		end
	end
	table.sort(milestones, function(a, b) return a.Minutes < b.Minutes end)

	-- Owner, 2026-09-17: one short line. The old second sentence ("the lobby and
	-- spectating do not ...") is gone because spectating now COUNTS (ZyntraMonetization
	-- playtimeCounts), and the note that pointed at the wheel's rail button went
	-- with it -- the rail button is where every player already finds the wheel.
	local playtimeNote = ctx.label(body, "Only time in an active round counts.",
		UDim2.new(), UDim2.new(), 11, muted, UIStyle.Font.Body)
	playtimeNote.Name = "PlaytimeNote"
	playtimeNote.TextWrapped = true
	playtimeNote.TextYAlignment = Enum.TextYAlignment.Top
 local researchTitle=ctx.label(body,"DAILY RESEARCH  //  SOLO · NO PURCHASES",UDim2.new(),UDim2.new(),14,accent,UIStyle.Font.Readout)
 researchTitle.Name="ResearchHeading"
 researchTitle.TextWrapped=true
 local researchRows={}
 for index,goal in ipairs(require(game.ReplicatedStorage:WaitForChild("ZyntraDailyResearch")).Goals) do
  local card=Instance.new("Frame")
  card.Name="Research"..goal.Key
  card.Parent=body
  UIStyle.panel(card,{Background=UIStyle.Color.Card,Radius=UIStyle.Radius.Card})
  local text=ctx.label(card,"",UDim2.new(1,-24,1,-16),UDim2.fromOffset(12,8),13,UIStyle.Color.Body,UIStyle.Font.Body)
  text.TextWrapped=true
  text.TextYAlignment=Enum.TextYAlignment.Center
  researchRows[index]={Card=card,Text=text,Goal=goal}
 end


	local offline
	if not rewards then
		-- The config and the server that honours it land together, so with the
		-- config absent a CLAIM button would be a control that cannot work. The
		-- page says so instead of offering one.
		offline = ctx.label(scroll, "Daily rewards are not configured on this server.",
			UDim2.new(), UDim2.new(), 12, COLORS.error or UIStyle.Color.Danger, UIStyle.Font.Body)
		offline.Name = "RewardsOffline"
		body.Visible = false
	end

	-- ── state ────────────────────────────────────────────────────────────────
	local destroyed = false
	local lastFit = nil
	local pending = {}          -- request key -> serial, cleared by any push
	local pendingSeq = 0
	local resetAt = nil         -- server-clock instant of the next 00:00 UTC
	local rollAsked = false
	local clockAccum = 0
	-- Set by layout(): a phone held sideways prints the countdown alone, because
	-- there it shares one 42px row with the play readout.
	local compactClock = false
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
	-- only thing the 1 Hz ticker redraws. The UTC boundary rides along on the
	-- same line -- one strip, one string, one thing to read.
	local function updateClocks()
		local remaining = resetAt and math.max(0, resetAt - now()) or nil
		countdown.Text = "RESETS IN " .. (remaining and formatClock(remaining) or "--:--:--")
			.. (compactClock and "" or "  \u{00B7}  00:00 UTC")
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
  for index,row in ipairs(researchRows) do
   local entry=daily and daily.Research and daily.Research[index]
   local done=sameDay and entry and entry.Complete==true
   row.Text.Text=(done and "COMPLETE  ·  " or "0/1  ·  ")..row.Goal.Title.."\n"..row.Goal.Detail
    .."\n"..(done and "RECEIVED +" or "REWARD +")..row.Goal.Reward.." RESEARCH TOKENS"
   row.Text.TextColor3=done and CLAIM_READY or UIStyle.Color.Body
  end


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
			local isClaimed = claimed[milestone.Key] == true
			milestone.Check.Visible = isClaimed
			milestone.Claimed.Visible = isClaimed
			-- Shown FIRST, then enabled: SetInteractive puts Active back on, so a
			-- locked button re-shown after a day roll would be pressable if the
			-- state branch below did not run second.
			setShown(button, not isClaimed)
			if isClaimed then
				-- The badge and the word are the whole state.
			elseif pending[milestone.Key] then
				button.Text = "CLAIMING..."
				button.BackgroundColor3 = CLAIM_LOCKED
				button.TextColor3 = muted
				setEnabled(button, false)
			elseif played >= milestone.Seconds then
				button.Text = "CLAIM"
				button.BackgroundColor3 = CLAIM_READY
				button.TextColor3 = INK
				setEnabled(button, true)
			else
				button.Text = formatSpan(milestone.Seconds - played) .. " TO GO"
				button.BackgroundColor3 = CLAIM_LOCKED
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
		local available = math.max(120, math.floor(tonumber(fit.ContentHeight) or 320))
		local touch = fit.Touch == true
		local tier = (fit.Compact and touch) and 1 or (touch and 2 or 3)
		local face = FACES[tier]
		local tap = math.max(touch and 44 or 28, math.floor(tonumber(fit.Tap) or 0))
		local buttonHeight = math.max(tap, face.Button)
		local pad, gap = face.Pad, face.Gap
		local usable = math.max(120, width - SCROLLBAR_ROOM)
		-- ONE ROW OF THREE everywhere except a phone held upright, where three
		-- cards across the content box would be 100px each.
		local column = tier == 1
			and (tonumber(fit.Height) or 0) >= (tonumber(fit.Width) or 0)
		-- A PHONE HELD SIDEWAYS is the tightest box this page is ever handed:
		-- 214px of content where the same phone upright gives 538. Measured in
		-- Studio at 844x390 on 2026-09-16, the countdown strip, the play strip
		-- and the caption pushed CLAIM to y 262 -- one flick below the fold, on
		-- the tier where a thumb already covers half the screen. So on THIS tier
		-- the two strips become one 42px row, the progress caption goes (each
		-- card's own threshold already prints 5/15/35 MIN) and every vertical
		-- number on the card is the tight one, which lands CLAIM at y 206 of a
		-- 214 box. The offline page is exempt: with no cards there is nothing
		-- crowding the strips, and its countdown has to stay where it is drawn.
		local tight = tier == 1 and not column and offline == nil

		-- the countdown strip: its own dark row, except on the tight tier where
		-- it has no row of its own
		local readoutHeight = face.Clock + 6
		local captionHeight = face.Body + 6
		local stripHeight = tight and 0 or math.clamp(face.Clock + 12, 28, 32)
		countdownStrip.Visible = not tight
		countdownStrip.Position = UDim2.fromOffset(0, 0)
		countdownStrip.Size = UDim2.fromOffset(usable, stripHeight)
		countdown.TextSize = face.Clock
		-- ONE countdown label, moved between the two strips rather than drawn
		-- twice: a second label is a second place to keep the clock honest.
		countdown.Parent = tight and playStrip or countdownStrip
		if not tight then
			countdown.Position = UDim2.fromOffset(10, 0)
			countdown.Size = UDim2.fromOffset(math.max(60, usable - 20), stripHeight)
			countdown.TextXAlignment = Enum.TextXAlignment.Left
		end
		-- The text itself gets shorter on the tight tier, so it is re-rendered
		-- the moment the tier changes rather than at the next 1 Hz tick. The
		-- guard is what keeps a rotation from re-entering render() forever.
		if compactClock ~= tight then
			compactClock = tight
			updateClocks()
		end

		local top = tight and 0 or (stripHeight + gap)
		if offline then
			offline.Position = UDim2.fromOffset(pad, top)
			offline.Size = UDim2.fromOffset(math.max(60, usable - pad * 2), face.Body + 14)
			scroll.CanvasSize = UDim2.fromOffset(0, top + face.Body + 14 + pad)
			return
		end

		-- the play strip
		local playHeight
		if tight then
			-- One row: played on the left, the reset on the right, the 4px track
			-- under both. 42px against the 28 + gap + 75 the two strips cost.
			playHeight = 42
			local inner = math.max(60, usable - 16)
			local readWidth = math.floor(inner * 0.55)
			playtimeReadout.Position = UDim2.fromOffset(8, 8)
			playtimeReadout.Size = UDim2.fromOffset(readWidth, readoutHeight)
			countdown.Position = UDim2.fromOffset(8 + readWidth + 8, 8)
			countdown.Size = UDim2.fromOffset(math.max(60, inner - readWidth - 8), readoutHeight)
			countdown.TextXAlignment = Enum.TextXAlignment.Right
			track.Position = UDim2.fromOffset(8, 8 + readoutHeight + 3)
			track.Size = UDim2.fromOffset(inner, 4)
		else
			local playInner = math.max(60, usable - pad * 2)
			playHeight = pad + readoutHeight + 6 + 4 + 6 + captionHeight + pad
			playtimeReadout.Position = UDim2.fromOffset(pad, pad)
			playtimeReadout.Size = UDim2.fromOffset(playInner, readoutHeight)
			track.Position = UDim2.fromOffset(pad, pad + readoutHeight + 6)
			track.Size = UDim2.fromOffset(playInner, 4)
			progressCaption.Position = UDim2.fromOffset(pad, pad + readoutHeight + 16)
			progressCaption.Size = UDim2.fromOffset(playInner, captionHeight)
			progressCaption.TextSize = face.Body
		end
		progressCaption.Visible = not tight
		playtimeReadout.TextSize = face.Clock
		playStrip.Position = UDim2.fromOffset(0, 0)
		playStrip.Size = UDim2.fromOffset(usable, playHeight)

		-- Two wrapped lines of the note, measured as boxes rather than with
		-- TextService: nothing here chooses a branch on the measurement, so a
		-- generous box is cheaper than a synchronous text query per layout pass.
		local noteHeight = face.Body + 8
		local notesHeight = noteHeight

		-- the cards. On the tight tier every vertical number shrinks -- the text
		-- FACES do not, so nothing drops under 11px; only the air around them
		-- does -- which is what takes the card from 178 to 162 and lands the
		-- CLAIM row above the fold.
		local cardPad = tight and 8 or pad
		local thresholdHeight = face.Threshold + (tight and 2 or 6)
		local nameHeight = face.Name + (tight and 4 or 6)
		local nameGap = tight and 4 or 6
		local cardsTop = playHeight + gap
		local cardWidth, cardHeight, iconSize
		if column then
			cardWidth = usable
			cardHeight = COLUMN_CARD_HEIGHT
			-- Square, off the card's HEIGHT -- but never so wide that the state
			-- row beside it drops under the 44px tap floor. This page does not
			-- get to assume a particular host's minimum panel width.
			iconSize = math.clamp(cardHeight - pad * 2, ICON_FLOOR,
				math.max(ICON_FLOOR, cardWidth - pad * 3 - 44))
		else
			cardWidth = math.floor((usable - gap * 2) / 3)
			-- Everything on the card that is NOT the icon.
			local chrome = cardPad + thresholdHeight + 4 + 4 + nameHeight + nameGap
				+ buttonHeight + cardPad
			-- icon / (chrome + icon) = ICON_SHARE, solved for icon, then capped by
			-- whatever height the host actually handed us. Under the cap the body
			-- scrolls rather than shrinking the one thing the card exists to show.
			local room = available - top - cardsTop - gap - notesHeight - pad
			-- ceil, not floor: floor lands the icon one pixel UNDER the 45% the
			-- brief asks for, which is a rule broken by rounding.
			local ideal = math.ceil(chrome * ICON_SHARE / (1 - ICON_SHARE))
			iconSize = math.clamp(ideal, ICON_FLOOR, math.max(ICON_FLOOR, room - chrome))
			cardHeight = chrome + iconSize
		end
		local checkSize = math.max(34, math.floor(iconSize * 0.42))

		local y = cardsTop
		for index, milestone in ipairs(milestones) do
			local card = milestone.Card
			local iconX, iconY, textLeft, textWidth
			if column then
				card.Position = UDim2.fromOffset(0, y)
				iconX, iconY = pad, pad
				textLeft = pad + iconSize + pad
				textWidth = math.max(44, cardWidth - textLeft - pad)
				milestone.Threshold.TextXAlignment = Enum.TextXAlignment.Left
				milestone.Name.TextXAlignment = Enum.TextXAlignment.Left
				milestone.Threshold.Position = UDim2.fromOffset(textLeft, pad)
				milestone.Name.Position = UDim2.fromOffset(textLeft, pad + thresholdHeight + 4)
				y += cardHeight + gap
			else
				card.Position = UDim2.fromOffset((index - 1) * (cardWidth + gap), y)
				iconX = math.floor((cardWidth - iconSize) / 2)
				iconY = cardPad + thresholdHeight + 4
				textLeft = cardPad
				textWidth = math.max(44, cardWidth - cardPad * 2)
				milestone.Threshold.TextXAlignment = Enum.TextXAlignment.Center
				milestone.Name.TextXAlignment = Enum.TextXAlignment.Center
				milestone.Threshold.Position = UDim2.fromOffset(cardPad, cardPad)
				milestone.Name.Position = UDim2.fromOffset(cardPad, iconY + iconSize + 4)
			end
			card.Size = UDim2.fromOffset(cardWidth, cardHeight)
			milestone.Threshold.Size = UDim2.fromOffset(textWidth, thresholdHeight)
			milestone.Threshold.TextSize = face.Threshold
			milestone.Icon.Position = UDim2.fromOffset(iconX, iconY)
			milestone.Icon.Size = UDim2.fromOffset(iconSize, iconSize)
			milestone.Name.Size = UDim2.fromOffset(textWidth, nameHeight)
			milestone.Name.TextSize = face.Name
			-- The badge straddles the art's top-right corner, clamped so it can
			-- never hang off the card on the narrowest tier.
			milestone.Check.Position = UDim2.fromOffset(
				math.min(cardWidth - checkSize - 4, iconX + iconSize - checkSize),
				math.max(2, iconY - 4))
			milestone.Check.Size = UDim2.fromOffset(checkSize, checkSize)
			milestone.CheckMark.TextSize = math.max(14, math.floor(checkSize * 0.6))

			local stateTop = cardHeight - cardPad - buttonHeight
			milestone.Button.Position = UDim2.fromOffset(textLeft, stateTop)
			milestone.Button.Size = UDim2.fromOffset(textWidth, buttonHeight)
			milestone.Button.TextSize = face.Name + 3
			milestone.Claimed.Position = UDim2.fromOffset(textLeft, stateTop)
			milestone.Claimed.Size = UDim2.fromOffset(textWidth, buttonHeight)
			milestone.Claimed.TextSize = face.Name + 3
		end
		if not column then y += cardHeight + gap end

		playtimeNote.Position = UDim2.fromOffset(0, y)
		playtimeNote.Size = UDim2.fromOffset(usable, noteHeight)
		playtimeNote.TextSize = face.Body
  y += noteHeight + gap
  researchTitle.Position=UDim2.fromOffset(0,y)
  researchTitle.Size=UDim2.fromOffset(usable,42)
  researchTitle.TextSize=face.Body+2
  y += 46
  for _,row in ipairs(researchRows) do
   row.Card.Position=UDim2.fromOffset(0,y)
   row.Card.Size=UDim2.fromOffset(usable,92)
   row.Text.TextSize=math.max(12,face.Body+1)
   y += 92+gap
  end
  local bodyHeight=y

		body.Position = UDim2.fromOffset(0, top)
		body.Size = UDim2.fromOffset(usable, bodyHeight)
		scroll.CanvasSize = UDim2.fromOffset(0, top + bodyHeight + pad)
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
