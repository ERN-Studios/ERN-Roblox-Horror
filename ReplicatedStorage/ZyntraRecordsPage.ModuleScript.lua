-- ZyntraRecordsPage -- the RECORDS tab (CHALLENGES_20260923, Trello FnF49TWk).
--
-- WHAT THIS PAGE IS ALLOWED TO DECIDE: nothing. Every time and every challenge
-- flag on it is read back from the public profile (`Records`, `Challenges`),
-- which ZyntraMonetization writes inside the same transaction that pays the
-- level clear. The page sends nothing to the server. Its one control,
-- SHOW ASSISTED / SHOW CLEAN, only chooses which half of the ledger is drawn,
-- and that choice is client-local state that dies with the mount.
--
-- ONE ROW SHAPE, and it is not this file's. ZyntraChallenges.Rows is the same
-- pure module the server applies a finished run with, so "which key is Level 2
-- party clean" is answered in one place and the page cannot disagree with the
-- ledger about it.
--
-- AN OLDER SERVER is a profile with neither field. Rows() reads that as "no
-- record yet, nothing done", so the page draws dashes and the rewards on offer
-- rather than erroring -- which is also exactly what a brand-new player sees.
--
-- WHO MOUNTS THIS. ZyntraStore, through TERMINAL_PAGE_MODULES, with the
-- host-agnostic mount(page, ctx) contract in
-- artifacts/trello-20260916/claude-contracts.md. The page draws only inside the
-- frame it is handed, never requires its host and never yields.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- FindFirstChild, never WaitForChild: the store mounts pages inside its own
-- startup, and a wait that never ended would stall the whole terminal. A missing
-- ledger is a require error instead, which the store turns into a warning and a
-- missing tab.
local Challenges = require(assert(ReplicatedStorage:FindFirstChild("ZyntraChallenges"),
	"ZyntraChallenges is missing from ReplicatedStorage"))

-- Three tiers from the two facts the host publishes, the way the Daily page and
-- the store's own Upgrades/Shop pages take them:
--   1  phone    fit.Compact AND fit.Touch
--   2  tablet   fit.Touch, not compact
--   3  pointer  neither
-- Nothing here is under 11px, and the one control is 44 tall at every tier.
local FACES = {
	{Pad = 12, Gap = 8, Title = 17, Level = 15, Time = 18, Body = 12, Row = 30},
	{Pad = 14, Gap = 10, Title = 18, Level = 16, Time = 20, Body = 13, Row = 32},
	{Pad = 16, Gap = 12, Title = 19, Level = 16, Time = 20, Body = 13, Row = 32},
}
local BUTTON = 44
local TOGGLE_WIDTH = 160      -- "SHOW ASSISTED" at 13px bold, with air
local TITLE_FLOOR = 110       -- under this the toggle takes its own row
local CAPTION_WIDTH = 64      -- "PARTY" at 13px Code, with air
local TAG_FACE, TAG_WIDTH, TAG_HEIGHT = 11, 80, 20
local STATE_WIDTH = 112       -- "+10 TOKENS" at 13px bold
-- A card splits into times | challenges once each half can hold a time row
-- (caption + the widest time + EQUIPPED) with room to spare.
local SPLIT_WIDTH = 520
local SCROLLBAR_ROOM = 8

local DASH = "\u{2014}"
local CHECK = "\u{2713}"
local NOTE = "Personal bests for each level. CLEAN: no re-entry, no consumables."
	.. " EQUIPPED: set with a paid upgrade. Challenges pay tokens once."

-- The time is drawn in Code, which is monospaced, so its box can hug the text
-- and the EQUIPPED tag can sit right beside it. 0.62em a glyph is generous for
-- Code; the floor of two glyphs covers the dash, which may fall back to a wider
-- face.
local function timeWidth(text: string, size: number): number
	return math.ceil(math.max(2, utf8.len(text) or #text) * size * 0.62) + 6
end

-- A wrapped note, measured as a box rather than with TextService (nothing here
-- branches on it, and a synchronous text query per layout pass buys nothing).
-- Gotham at ~0.55em a glyph plus one spare line: a box a line too tall costs
-- air, one a line too short clips the copy.
local function wrappedHeight(text: string, size: number, width: number): number
	local perLine = math.max(1, math.floor(width / (size * 0.55)))
	return (math.ceil(#text / perLine) + 1) * math.ceil(size * 1.25)
end

local function tokens(amount): string
	local count = math.max(0, math.floor(tonumber(amount) or 0))
	return "+" .. tostring(count) .. (count == 1 and " TOKEN" or " TOKENS")
end

local Page = {}

function Page.mount(page, ctx)
	local function call(fn, ...)
		if type(fn) == "function" then return fn(...) end
		return nil
	end

	local Config = type(ctx.Config) == "table" and ctx.Config or {}
	local UIStyle = ctx.UIStyle
	local COLORS = type(ctx.COLORS) == "table" and ctx.COLORS or {}
	local pageName = ctx.pageName or "Records"
	local contract = type(ctx.contract) == "table" and ctx.contract or {}
	-- The config and this page ship together; the fallback only keeps a config
	-- without the block from erroring on mount.
	local settings = type(Config.Challenges) == "table" and Config.Challenges
		or {Levels = {1, 2, 3}, TimeGoalSeconds = {}, RewardTokens = {}}
	local rewards = type(settings.RewardTokens) == "table" and settings.RewardTokens or {}

	-- Teal is the system colour and gold is money, as on every other tab.
	local accent = COLORS.accent or UIStyle.Color.Accent
	local muted = COLORS.muted or UIStyle.Color.Muted
	local ink = COLORS.text or UIStyle.Color.Title
	local gold = COLORS.accent2 or UIStyle.Color.Warning
	local doneColor = UIStyle.Color.Positive
	local cardStyle = {Background = UIStyle.Color.Card, Transparency = UIStyle.Transparency.Card,
		Radius = UIStyle.Radius.Card, StrokeTransparency = UIStyle.Stroke.CardTransparency}

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Records"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = accent
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = page
	call(contract.scroll, pageName, scroll)

	-- ── the header card, which carries the page's one action ────────────────
	local header = Instance.new("Frame")
	header.Name = "RecordsHeader"
	header.Parent = scroll
	UIStyle.panel(header, cardStyle)
	local title = ctx.label(header, "RECORDS", UDim2.new(), UDim2.new(), 18, accent, Enum.Font.GothamBlack)
	title.Name = "HeaderTitle"
	local modeReadout = ctx.label(header, "", UDim2.new(), UDim2.new(), 12, muted, UIStyle.Font.Readout)
	modeReadout.Name = "ModeReadout"
	local note = ctx.label(header, NOTE, UDim2.new(), UDim2.new(), 12, muted, UIStyle.Font.Body)
	note.Name = "HeaderNote"
	note.TextWrapped = true
	note.TextYAlignment = Enum.TextYAlignment.Top
	-- Never taken out of the input stack: both views are always available, so
	-- there is no stood-down caption for UIRegression to recognise, and none is
	-- needed.
	local toggle = ctx.button(header, "SHOW ASSISTED", UDim2.new(), UDim2.new())
	toggle.Name = "ViewToggle"
	call(contract.card, pageName, "View", header, toggle)

	-- ── one card per level ──────────────────────────────────────────────────
	local function goalLine(card, kind)
		local caption = ctx.label(card, "", UDim2.new(), UDim2.new(), 13, ink, UIStyle.Font.Title)
		caption.Name = kind .. "Name"
		local state = ctx.label(card, "", UDim2.new(), UDim2.new(), 13, gold, Enum.Font.GothamBold)
		state.Name = kind .. "State"
		state.TextXAlignment = Enum.TextXAlignment.Right
		return {Caption = caption, State = state}
	end

	local cards = {}
	for order, level in ipairs(settings.Levels) do
		local card = Instance.new("Frame")
		card.Name = "Level" .. tostring(level)
		card.LayoutOrder = order + 1
		card.Parent = scroll
		UIStyle.panel(card, cardStyle)
		local levelTitle = ctx.label(card, "LEVEL " .. tostring(level), UDim2.new(), UDim2.new(),
			16, ink, UIStyle.Font.Title)
		levelTitle.Name = "LevelTitle"
		local times = {}
		for _, mode in ipairs(Challenges.Modes) do
			local prefix = mode == "solo" and "Solo" or "Party"
			local caption = ctx.label(card, string.upper(mode), UDim2.new(), UDim2.new(),
				12, muted, UIStyle.Font.Readout)
			caption.Name = prefix .. "Caption"
			local time = ctx.label(card, DASH, UDim2.new(), UDim2.new(), 20, ink, UIStyle.Font.Readout)
			time.Name = prefix .. "Time"
			-- A record never hides what it was set with: the tag rides next to the
			-- time it qualifies, and only that one.
			local tag = ctx.label(card, "EQUIPPED", UDim2.new(), UDim2.new(), TAG_FACE,
				UIStyle.Color.WarningText, Enum.Font.GothamBold)
			tag.Name = prefix .. "Equipped"
			tag.TextXAlignment = Enum.TextXAlignment.Center
			tag.BackgroundColor3 = UIStyle.Color.WarningLine
			tag.BackgroundTransparency = 0.35
			tag.Visible = false
			call(ctx.corner, tag, 6)
			table.insert(times, {Mode = mode, Time = time, Caption = caption, Tag = tag})
		end
		table.insert(cards, {Card = card, Title = levelTitle, Times = times,
			NoDeath = goalLine(card, "NoDeath"), TimeGoal = goalLine(card, "TimeGoal")})
	end

	-- ── state ───────────────────────────────────────────────────────────────
	local destroyed = false
	local showAssisted = false
	local lastFit = nil
	local layout -- defined below; render() re-lays out because a time's box hugs its text

	local function setGoal(line, caption: string?, done: boolean, reward)
		line.Caption.Visible = caption ~= nil
		line.State.Visible = caption ~= nil
		line.Caption.Text = caption or ""
		line.State.Text = done and (CHECK .. " DONE") or tokens(reward)
		line.State.TextColor3 = done and doneColor or gold
	end

	local function render()
		if destroyed then return end
		local profile = call(ctx.profile)
		profile = type(profile) == "table" and profile or {}
		local rows = Challenges.Rows(profile.Records, profile.Challenges, settings)
		local condition = showAssisted and "assisted" or "clean"
		toggle.Text = showAssisted and "SHOW CLEAN" or "SHOW ASSISTED"
		modeReadout.Text = showAssisted and "ASSISTED RUNS" or "CLEAN RUNS"
		for index, entry in ipairs(cards) do
			local row = rows[index]
			for _, line in ipairs(entry.Times) do
				local record = row and row.Records[line.Mode .. ":" .. condition]
				line.Time.Text = record and Challenges.FormatTime(record.Best) or DASH
				line.Time.TextColor3 = record and ink or muted
				line.Tag.Visible = record ~= nil and record.Equipped == true
			end
			local goal = row and row.TimeGoal
			setGoal(entry.NoDeath, "NO DEATHS", row ~= nil and row.NoDeath, rewards.NoDeath)
			setGoal(entry.TimeGoal, goal and ("UNDER " .. Challenges.FormatTime(goal)) or nil,
				row ~= nil and row.TimeGoalDone, rewards.TimeGoal)
		end
		if lastFit then layout(lastFit) end
	end

	-- ── layout ──────────────────────────────────────────────────────────────
	-- Every rectangle is an offset derived from fit.ContentWidth, so "does it
	-- fit" is arithmetic a test can do. The page is a list: header, then one
	-- full-width card per level, scrolling where the host is short.
	function layout(fit)
		lastFit = fit
		local width = math.max(160, math.floor(tonumber(fit.ContentWidth) or 320))
		local touch = fit.Touch == true
		local face = FACES[(fit.Compact and touch) and 1 or (touch and 2 or 3)]
		local pad, gap = face.Pad, face.Gap
		local usable = math.max(120, width - SCROLLBAR_ROOM)
		local inner = usable - pad * 2
		local buttonHeight = math.max(BUTTON, math.floor(tonumber(fit.Tap) or 0))

		-- the header: title and mode on the left, the toggle on the right, and on
		-- a box too narrow for both the toggle takes a full-width row of its own
		local stacked = inner - TOGGLE_WIDTH - 8 < TITLE_FLOOR
		local titleWidth = stacked and inner or inner - TOGGLE_WIDTH - 8
		local titleBlock = face.Title + 6 + face.Body + 4
		local rowHeight = stacked and titleBlock or math.max(titleBlock, buttonHeight)
		local titleTop = pad + math.floor((rowHeight - titleBlock) / 2)
		title.Position = UDim2.fromOffset(pad, titleTop)
		title.Size = UDim2.fromOffset(titleWidth, face.Title + 6)
		title.TextSize = face.Title
		modeReadout.Position = UDim2.fromOffset(pad, titleTop + face.Title + 6)
		modeReadout.Size = UDim2.fromOffset(titleWidth, face.Body + 4)
		modeReadout.TextSize = face.Body
		local y = pad + rowHeight + 6
		if stacked then
			toggle.Position = UDim2.fromOffset(pad, y)
			toggle.Size = UDim2.fromOffset(inner, buttonHeight)
			y += buttonHeight + 6
		else
			toggle.Position = UDim2.fromOffset(pad + inner - TOGGLE_WIDTH,
				pad + math.floor((rowHeight - buttonHeight) / 2))
			toggle.Size = UDim2.fromOffset(TOGGLE_WIDTH, buttonHeight)
		end
		toggle.TextSize = face.Body
		local noteHeight = wrappedHeight(NOTE, face.Body, inner)
		note.Position = UDim2.fromOffset(pad, y)
		note.Size = UDim2.fromOffset(inner, noteHeight)
		note.TextSize = face.Body
		local headerHeight = y + noteHeight + pad
		header.Position = UDim2.fromOffset(0, 0)
		header.Size = UDim2.fromOffset(usable, headerHeight)

		-- the level cards: times, then challenges -- side by side where the card
		-- is wide enough for two columns, stacked where it is not
		local split = inner >= SPLIT_WIDTH
		local column = split and math.floor((inner - pad) / 2) or inner
		local top = headerHeight + gap
		for _, entry in ipairs(cards) do
			local cy = pad
			entry.Title.Position = UDim2.fromOffset(pad, cy)
			entry.Title.Size = UDim2.fromOffset(inner, face.Level + 6)
			entry.Title.TextSize = face.Level
			cy += face.Level + 10
			local timesTop = cy
			for _, line in ipairs(entry.Times) do
				local timeBox = timeWidth(line.Time.Text, face.Time)
				line.Caption.Position = UDim2.fromOffset(pad, cy)
				line.Caption.Size = UDim2.fromOffset(CAPTION_WIDTH, face.Row)
				line.Caption.TextSize = face.Body
				line.Time.Position = UDim2.fromOffset(pad + CAPTION_WIDTH, cy)
				line.Time.Size = UDim2.fromOffset(timeBox, face.Row)
				line.Time.TextSize = face.Time
				line.Tag.Size = UDim2.fromOffset(TAG_WIDTH, TAG_HEIGHT)
				local tagLeft = pad + CAPTION_WIDTH + timeBox + 6
				if line.Tag.Visible and tagLeft + TAG_WIDTH > pad + column then
					-- A panel too narrow to share the row (the terminal's 260px
					-- floor): the tag drops under its time instead of off the card.
					line.Tag.Position = UDim2.fromOffset(pad + CAPTION_WIDTH, cy + face.Row)
					cy += face.Row + TAG_HEIGHT + 4
				else
					line.Tag.Position = UDim2.fromOffset(tagLeft,
						cy + math.floor((face.Row - TAG_HEIGHT) / 2))
					cy += face.Row
				end
			end
			local gx = split and (pad + column + pad) or pad
			local gy = split and timesTop or (cy + 4)
			for _, line in ipairs({entry.NoDeath, entry.TimeGoal}) do
				line.Caption.Position = UDim2.fromOffset(gx, gy)
				line.Caption.Size = UDim2.fromOffset(column - STATE_WIDTH - 8, face.Row)
				line.Caption.TextSize = face.Body
				line.State.Position = UDim2.fromOffset(gx + column - STATE_WIDTH, gy)
				line.State.Size = UDim2.fromOffset(STATE_WIDTH, face.Row)
				line.State.TextSize = face.Body
				gy += face.Row
			end
			local height = math.max(cy, gy) + pad
			entry.Card.Position = UDim2.fromOffset(0, top)
			entry.Card.Size = UDim2.fromOffset(usable, height)
			top += height + gap
		end
		scroll.CanvasSize = UDim2.fromOffset(0, top - gap + pad)
	end
	call(ctx.registerLayoutHook, layout)

	-- ── input and pushes ────────────────────────────────────────────────────
	local toggled = toggle.Activated:Connect(function()
		if destroyed then return end
		showAssisted = not showAssisted
		render()
	end)
	local stopProfile = call(ctx.onProfile, function()
		render()
	end)

	local handle = {}
	function handle.refresh()
		render()
	end
	function handle.destroy()
		destroyed = true
		toggled:Disconnect()
		if type(stopProfile) == "function" then stopProfile() end
		scroll:Destroy()
	end

	render()
	return handle
end

return Page
