-- ZyntraFieldNotesPage -- the terminal's NOTES tab. (Trello #85/#88)
--
-- Mounted by ZyntraStore through the shared page contract: one `mount(page,
-- ctx)` that draws only inside `page`, uses only the helpers ctx hands over,
-- never requires ZyntraStore back, and never yields at require time. If this
-- module is missing in Studio the terminal simply skips the tab.
--
-- WHAT THE PAGE HAS TO SAY, in this order, because it is the order a player
-- asks it in: how many are left, what finishing gets you, and then the twelve
-- rows themselves grouped by the level they are found on. A collection screen
-- that opens straight onto a grid makes the player count the cards themselves.
--
-- UNDISCOVERED ROWS ARE DRAWN, not hidden. An outline carrying the level it
-- lives on IS the progress mechanic: hiding them would leave a player with no
-- way to know whether they are missing one note or five, which is exactly the
-- transparent progress the card asks for. Their action carries the caption
-- NOT YET FOUND and is disabled through UIDevice.SetEnabled, so it stays
-- legible and stops taking input -- the label itself is the message.
--
-- NO KEY GLYPHS ANYWHERE. The terminal is reachable on a phone and this page
-- has no keyboard binding of its own to advertise.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local FIELD_NOTES_MODULE = "ZyntraFieldNotes"
local FALLBACK_TITLE = "FIELD ARCHIVIST"

local GAP = 8
local SECTION_GAP = 12
local CARD_PAD = 10
local MIN_CARD_WIDTH = 150

local Page = {}

local function firstLine(text: string): string
	-- The opening sentence, or the whole body when it has no sentence break.
	local sentence = string.match(text, "^(.-[%.%?!])%s") or text
	if #sentence > 72 then sentence = string.sub(sentence, 1, 69) .. "..." end
	return sentence
end

function Page.mount(page: Frame, ctx: any): any
	-- ZyntraStore pcalls its own UIStyle require and passes nil when it fails, so
	-- nil is a state this page is genuinely handed. An empty Font table makes
	-- every ctx.label fall back to the terminal's own default face: the tab
	-- draws in plain type instead of not existing.
	local UIStyle = ctx.UIStyle or {Font = {}}
	local UIDevice = ctx.UIDevice
	local COLORS = ctx.COLORS
	local pageName = ctx.pageName or "Notes"

	-- FindFirstChild, never WaitForChild. ZyntraStore found THIS module the same
	-- way, so ReplicatedStorage has already replicated; a WaitForChild here would
	-- turn a missing content module into a terminal tab that hangs forever
	-- instead of a tab that says what is wrong.
	local holder = ReplicatedStorage:FindFirstChild(FIELD_NOTES_MODULE)
	local okContent, content = false, nil
	if holder then
		okContent, content = pcall(require, holder)
	end
	if not (okContent and type(content) == "table" and type(content.Notes) == "table") then
		ctx.label(page, "FIELD NOTES UNAVAILABLE", UDim2.new(1, 0, 0, 24),
			UDim2.fromOffset(0, 0), 14, COLORS.muted, UIStyle.Font.Readout)
		return {refresh = function() end, destroy = function() end}
	end

	local completionTitle = FALLBACK_TITLE
	local configured = ctx.Config and ctx.Config.FieldNotes
	if type(configured) == "table" and type(configured.CompletionTitle) == "string"
		and configured.CompletionTitle ~= "" then
		completionTitle = configured.CompletionTitle
	end

	local destroyed = false
	-- Forward declared so the card and BACK handlers below can re-run the layout
	-- after they swap views. Per-mount state stays in this closure; nothing is
	-- parked on the module table, where a second mount would overwrite it.
	local relayout

	-- ── header ───────────────────────────────────────────────────────────────
	local header = Instance.new("Frame")
	header.Name = "NotesHeader"
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(0, 0)
	header.Parent = page

	local eyebrow = ctx.label(header, "ZYNTRA // ARCHIVE", UDim2.new(1, 0, 0, 13),
		UDim2.fromOffset(0, 0), 11, COLORS.accent, UIStyle.Font.Readout)
	local heading = ctx.label(header, "FIELD NOTES", UDim2.new(1, 0, 0, 22),
		UDim2.fromOffset(0, 14), 18, COLORS.text, UIStyle.Font.Title)
	local progress = ctx.label(header, "0 / " .. tostring(content.Total) .. " RECOVERED",
		UDim2.new(1, 0, 0, 15), UDim2.fromOffset(0, 36), 12, COLORS.muted, UIStyle.Font.Readout)

	local track = Instance.new("Frame")
	track.Name = "ProgressTrack"
	track.BackgroundColor3 = COLORS.card
	track.BorderSizePixel = 0
	track.Parent = header
	ctx.corner(track, 3)

	local fill = Instance.new("Frame")
	fill.Name = "ProgressFill"
	fill.BackgroundColor3 = COLORS.accent
	fill.BorderSizePixel = 0
	fill.Position = UDim2.fromScale(0, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	ctx.corner(fill, 3)

	local titleLine = ctx.label(header, "", UDim2.new(1, 0, 0, 16),
		UDim2.fromOffset(0, 66), 12, COLORS.muted, UIStyle.Font.Body)

	-- ── the scrolling body ───────────────────────────────────────────────────
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "NotesScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = COLORS.line
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = page
	if ctx.contract and ctx.contract.scroll then
		ctx.contract.scroll(pageName, scroll)
	else
		scroll.ScrollingEnabled = true
	end

	local grid = Instance.new("Frame")
	grid.Name = "NotesGrid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 1)
	grid.Parent = scroll

	-- ── the detail view ──────────────────────────────────────────────────────
	-- It REPLACES the grid inside the same ScrollingFrame rather than opening a
	-- second surface: one scroll per page is what the terminal's contract
	-- publishes, and a note body is the only thing here long enough to need
	-- scrolling at all.
	local detail = Instance.new("Frame")
	detail.Name = "NoteDetail"
	detail.BackgroundTransparency = 1
	detail.Visible = false
	detail.Parent = scroll

	local back = ctx.button(detail, "BACK", UDim2.fromOffset(120, 32), UDim2.fromOffset(0, 0))
	back.Name = "Back"

	local detailPanel = Instance.new("Frame")
	detailPanel.Name = "DetailPanel"
	detailPanel.BackgroundColor3 = COLORS.card
	detailPanel.BorderSizePixel = 0
	detailPanel.Parent = detail
	ctx.corner(detailPanel, 10)
	ctx.outline(detailPanel, COLORS.line, 0.3, 1)

	local detailTitle = ctx.label(detailPanel, "", UDim2.new(1, -CARD_PAD * 2, 0, 22),
		UDim2.fromOffset(CARD_PAD, CARD_PAD), 16, COLORS.text, UIStyle.Font.Title)
	local detailStamp = ctx.label(detailPanel, "", UDim2.new(1, -CARD_PAD * 2, 0, 16),
		UDim2.fromOffset(CARD_PAD, CARD_PAD + 22), 12, COLORS.accent, UIStyle.Font.Readout)
	local detailBody = ctx.label(detailPanel, "", UDim2.new(1, -CARD_PAD * 2, 0, 60),
		UDim2.fromOffset(CARD_PAD, CARD_PAD + 44), 13, COLORS.text, UIStyle.Font.Body)
	detailBody.TextWrapped = true
	detailBody.TextYAlignment = Enum.TextYAlignment.Top

	-- ── the twelve rows ──────────────────────────────────────────────────────
	local sections = {} -- [level] = {Header = TextLabel, Rows = {…}}
	local rows = {}     -- flat, in Notes order, for refresh

	for _, level in ipairs(content.Levels or {1, 2, 3}) do
		local sectionHeader = ctx.label(grid, "LEVEL " .. tostring(level),
			UDim2.new(1, -GAP, 0, 16), UDim2.fromOffset(0, 0), 12, COLORS.muted,
			UIStyle.Font.Readout)
		sectionHeader.Name = "Level" .. tostring(level) .. "Header"
		local section = {Header = sectionHeader, Rows = {}, Level = level}
		sections[level] = section

		for _, note in ipairs(content.ByLevel[level] or {}) do
			local card = Instance.new("Frame")
			card.Name = "Note" .. note.Id
			card.BackgroundColor3 = COLORS.card
			card.BorderSizePixel = 0
			card.Parent = grid
			ctx.corner(card, 9)
			local stroke = ctx.outline(card, COLORS.line, 0.34, 1)

			local cardTitle = ctx.label(card, note.Title, UDim2.new(1, -CARD_PAD * 2, 0, 18),
				UDim2.fromOffset(CARD_PAD, CARD_PAD), 13, COLORS.text, UIStyle.Font.Title)
			cardTitle.TextTruncate = Enum.TextTruncate.AtEnd
			local cardStamp = ctx.label(card, note.Stamp, UDim2.new(1, -CARD_PAD * 2, 0, 14),
				UDim2.fromOffset(CARD_PAD, CARD_PAD + 18), 11, COLORS.accent,
				UIStyle.Font.Readout)
			local cardBody = ctx.label(card, firstLine(note.Body),
				UDim2.new(1, -CARD_PAD * 2, 0, 30), UDim2.fromOffset(CARD_PAD, CARD_PAD + 34),
				11, COLORS.muted, UIStyle.Font.Body)
			cardBody.TextWrapped = true
			cardBody.TextYAlignment = Enum.TextYAlignment.Top

			local open = ctx.button(card, "READ", UDim2.new(1, -CARD_PAD * 2, 0, 30),
				UDim2.fromOffset(CARD_PAD, 0))
			open.Name = "Open"

			local row = {Note = note, Card = card, Stroke = stroke, Title = cardTitle,
				Stamp = cardStamp, Body = cardBody, Open = open, Found = false}
			table.insert(section.Rows, row)
			table.insert(rows, row)

			if ctx.contract and ctx.contract.card then
				ctx.contract.card(pageName, note.Id, card, open)
			end

			open.Activated:Connect(function()
				if destroyed or not row.Found then return end
				detailTitle.Text = note.Title
				detailStamp.Text = note.Stamp
				detailBody.Text = note.Body
				grid.Visible = false
				detail.Visible = true
				scroll.CanvasPosition = Vector2.new(0, 0)
				relayout(nil)
			end)
		end
	end

	back.Activated:Connect(function()
		if destroyed then return end
		detail.Visible = false
		grid.Visible = true
		scroll.CanvasPosition = Vector2.new(0, 0)
		relayout(nil)
	end)

	-- ── state ────────────────────────────────────────────────────────────────
	local function applyProfile()
		if destroyed then return end
		local profile = ctx.profile()
		local owned = {}
		local unlocked = false
		local field = profile and profile.FieldNotes
		if type(field) == "table" then
			if type(field.Discovered) == "table" then owned = field.Discovered end
			unlocked = field.TitleUnlocked == true
		end

		local count = 0
		for _, row in ipairs(rows) do
			local found = owned[row.Note.Id] == true
			row.Found = found
			if found then count += 1 end
			row.Title.Text = found and row.Note.Title or ("LEVEL " .. tostring(row.Note.Level))
			row.Title.TextColor3 = found and COLORS.text or COLORS.muted
			row.Stamp.Text = found and row.Note.Stamp or "UNFILED"
			row.Body.Text = found and firstLine(row.Note.Body) or "Not recovered yet."
			row.Stroke.Transparency = found and 0.34 or 0.62
			-- The caption IS the state. NOT YET FOUND belongs to the terminal's
			-- disabled-reason vocabulary, so a fit matrix measuring this
			-- rectangle still finds a reason printed on the control itself.
			row.Open.Text = found and "READ" or "NOT YET FOUND"
			row.Open.TextColor3 = found and COLORS.text or COLORS.muted
			UIDevice.SetEnabled(row.Open, found)
		end

		local total = content.Total or #rows
		progress.Text = string.format("%d / %d RECOVERED", count, total)
		fill.Size = UDim2.fromScale(total > 0 and math.clamp(count / total, 0, 1) or 0, 1)
		if unlocked then
			titleLine.Text = "TITLE: " .. completionTitle
			titleLine.TextColor3 = COLORS.accent
		else
			titleLine.Text = "Recover every note to earn the " .. completionTitle .. " title"
			titleLine.TextColor3 = COLORS.muted
		end
	end

	-- ── layout ───────────────────────────────────────────────────────────────
	local lastFit = nil

	function relayout(fit)
		if destroyed then return end
		fit = fit or lastFit
		if not fit then return end
		lastFit = fit

		local width = math.max(160, fit.ContentWidth)
		local tap = math.max(fit.Tap or 0, fit.Touch and 44 or 30)
		local compact = fit.Compact == true

		-- Phone one column, tablet two, pointer three -- then narrowed again if
		-- the arithmetic would make a column narrower than a card can be read
		-- at. The tier states the intent; the width decides whether it fits.
		local columns = 3
		if compact and fit.Touch then columns = 1
		elseif fit.Touch then columns = 2 end
		while columns > 1
			and (width - GAP - GAP * (columns - 1)) / columns < MIN_CARD_WIDTH do
			columns -= 1
		end

		local titleTop = compact and 12 or 14
		local trackTop = titleTop + (compact and 36 or 39)
		heading.Position = UDim2.fromOffset(0, titleTop)
		heading.Size = UDim2.new(1, 0, 0, compact and 20 or 22)
		heading.TextSize = compact and 16 or 18
		progress.Position = UDim2.fromOffset(0, titleTop + (compact and 20 or 22))
		track.Position = UDim2.fromOffset(0, trackTop)
		track.Size = UDim2.new(1, -GAP, 0, 5)
		-- The completion line wraps to two rows on a phone, so the header has to
		-- grow with it rather than clip the sentence that explains the title.
		titleLine.Position = UDim2.fromOffset(0, trackTop + 9)
		titleLine.Size = UDim2.new(1, -GAP, 0, compact and 28 or 16)
		titleLine.TextWrapped = compact
		local headerHeight = trackTop + 9 + (compact and 28 or 16) + 6
		local short = fit.ContentHeight < 170
		eyebrow.Visible = not short
		track.Visible = not short
		titleLine.Visible = not short
		progress.Size = UDim2.new(1, 0, 0, 15)
		if short then
			-- Keep a full touch target's worth of scrolling space on low screens.
			headerHeight = 30
			heading.Position = UDim2.fromOffset(0, 4)
			heading.Size = UDim2.new(0.5, -4, 0, 20)
			progress.Position = UDim2.new(0.5, 4, 0, 7)
			progress.Size = UDim2.new(0.5, -4, 0, 15)
		end
		header.Size = UDim2.new(1, 0, 0, headerHeight)

		scroll.Position = UDim2.fromOffset(0, headerHeight)
		scroll.Size = UDim2.new(1, 0, 0, math.max(1, fit.ContentHeight - headerHeight))

		local cellWidth = math.floor((width - GAP - GAP * (columns - 1)) / columns)
		local cardHeight = CARD_PAD * 2 + 18 + 14 + 30 + 4 + tap

		local y = 0
		for _, level in ipairs(content.Levels or {1, 2, 3}) do
			local section = sections[level]
			if section then
				section.Header.Position = UDim2.fromOffset(0, y)
				section.Header.Size = UDim2.new(0, width - GAP, 0, 16)
				y += 20
				for index, row in ipairs(section.Rows) do
					local column = (index - 1) % columns
					local line = math.floor((index - 1) / columns)
					row.Card.Position = UDim2.fromOffset(column * (cellWidth + GAP),
						y + line * (cardHeight + GAP))
					row.Card.Size = UDim2.fromOffset(cellWidth, cardHeight)
					row.Open.Size = UDim2.new(1, -CARD_PAD * 2, 0, tap)
					row.Open.Position = UDim2.fromOffset(CARD_PAD, cardHeight - CARD_PAD - tap)
				end
				y += math.ceil(#section.Rows / columns) * (cardHeight + GAP) + SECTION_GAP
			end
		end
		local gridHeight = y

		back.Size = UDim2.fromOffset(math.min(140, width - GAP), tap)
		local detailTop = tap + GAP
		detailPanel.Position = UDim2.fromOffset(0, detailTop)
		-- MEASURED. GetTextSize is the synchronous API, which is what a layout
		-- hook needs: yielding inside one would let the next fit pass start
		-- inside this one.
		local bodyWidth = math.max(60, width - GAP - CARD_PAD * 2)
		local measured = TextService:GetTextSize(detailBody.Text, detailBody.TextSize,
			detailBody.Font, Vector2.new(bodyWidth, 10000))
		local bodyHeight = math.max(34, math.ceil(measured.Y) + 4)
		detailBody.Size = UDim2.new(1, -CARD_PAD * 2, 0, bodyHeight)
		local panelHeight = CARD_PAD * 2 + 44 + bodyHeight
		detailPanel.Size = UDim2.fromOffset(width - GAP, panelHeight)
		detail.Size = UDim2.fromOffset(width - GAP, detailTop + panelHeight)

		local canvas = detail.Visible and (detailTop + panelHeight + GAP) or gridHeight
		scroll.CanvasSize = UDim2.fromOffset(0, math.max(0, canvas))
	end

	if ctx.registerLayoutHook then
		ctx.registerLayoutHook(function(fit) relayout(fit) end)
	end

	local disconnect = ctx.onProfile(function() applyProfile() end)

	applyProfile()
	relayout(nil)

	return {
		refresh = function()
			applyProfile()
			relayout(nil)
		end,
		destroy = function()
			destroyed = true
			if disconnect then pcall(disconnect) end
			header:Destroy()
			scroll:Destroy()
		end,
	}
end

return Page
