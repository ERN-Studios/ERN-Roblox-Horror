-- Field Notes Client -- the reading card a discovered note opens. (Trello #85/#88)
--
-- THIS IS NOT A MODAL, and that is the whole design. The player is standing in
-- a level with a hostile in it. So: no `ScreenOwningModal` attribute, no
-- movement suppression, no cursor unlock, no input-consuming shade. The card is
-- a panel that draws over the HUD, closes itself after AUTO_CLOSE_SECONDS, and
-- can be walked away from mid-sentence with no consequence -- the note is
-- already in the collection by the time this script hears about it, and the
-- terminal's NOTES page holds the full text forever.
--
-- DisplayOrder 60 places it above the HUD and the spectate band, and UNDER the
-- two cards that genuinely own the screen: Round Exit's confirm (70) and PARTY
-- DOWN (100). A note is never the most important thing on screen.
--
-- ON TOUCH the card goes in UIDevice's ModalArea, which is the lane that
-- excludes BOTH the thumbstick and the right-hand control cluster. Drawing it
-- centred over the whole screen -- which is what it looks like it should do --
-- covers the stick on short landscape phones, and walking away is how this card
-- is meant to end.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))
local FieldNotes = require(ReplicatedStorage:WaitForChild("ZyntraFieldNotes"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FieldNote")

local AUTO_CLOSE_SECONDS = 14
local CAPTION_SECONDS = 3
local CARD_MAX_WIDTH = 380
local PAD = 16
local GAP = 10

local byId = {}
for _, note in ipairs(FieldNotes.Notes) do byId[note.Id] = note end

local gui = Instance.new("ScreenGui")
gui.Name = "FieldNoteGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Parent = player:WaitForChild("PlayerGui")

-- The card. `Active` stays false on the frame itself so a tap anywhere but the
-- CLOSE button reaches the world behind it; only the button takes input.
local card = Instance.new("Frame")
card.Name = "FieldNoteCard"
card.Visible = false
card.Parent = gui
UIStyle.panel(card, {
	Background = UIStyle.Color.Card,
	Transparency = UIStyle.Transparency.Card,
	Radius = UIStyle.Radius.Card,
	StrokeTransparency = UIStyle.Stroke.CardTransparency,
})

local eyebrow = Instance.new("TextLabel")
eyebrow.Name = "Eyebrow"
eyebrow.BackgroundTransparency = 1
eyebrow.Text = "FIELD NOTE RECOVERED"
eyebrow.TextXAlignment = Enum.TextXAlignment.Left
eyebrow.Parent = card
UIStyle.readout(eyebrow, {TextSize = UIStyle.TextSize.Eyebrow})

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Text = ""
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = card
UIStyle.title(title, {TextSize = 17})

local stamp = Instance.new("TextLabel")
stamp.Name = "Stamp"
stamp.BackgroundTransparency = 1
stamp.Text = ""
stamp.TextXAlignment = Enum.TextXAlignment.Left
stamp.Parent = card
UIStyle.readout(stamp, {TextSize = 12, TextColor = UIStyle.Color.Muted})

local body = Instance.new("TextLabel")
body.Name = "Body"
body.BackgroundTransparency = 1
body.Text = ""
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.Parent = card
UIStyle.body(body, {TextSize = 14})

local close = Instance.new("TextButton")
close.Name = "Close"
close.AutoButtonColor = true
close.Text = "CLOSE"
close.Parent = card
UIStyle.button(close)

-- The transient line. Caption chrome rather than card chrome: it is the same
-- role as the subtitle band, a sentence that appears over the world and goes.
local caption = Instance.new("Frame")
caption.Name = "FieldNoteCaption"
caption.Visible = false
caption.Parent = gui
UIStyle.caption(caption)

local captionLabel = Instance.new("TextLabel")
captionLabel.Name = "Text"
captionLabel.BackgroundTransparency = 1
captionLabel.Size = UDim2.new(1, -20, 1, 0)
captionLabel.Position = UDim2.fromOffset(10, 0)
captionLabel.Text = ""
captionLabel.TextXAlignment = Enum.TextXAlignment.Center
captionLabel.Parent = caption
UIStyle.readout(captionLabel, {TextSize = 13, TextColor = UIStyle.Color.Live})

-- Serials, not booleans: an auto-close armed for the FIRST note must not close
-- the SECOND one that opened 200 ms later.
local cardSerial = 0
local captionSerial = 0
local shown = nil -- the note currently on the card, so a re-layout can re-measure

-- ── placement ───────────────────────────────────────────────────────────────

-- The free lane: on touch the rectangle that excludes the movement cluster,
-- otherwise the safe area less a margin. Same shape as Shop Display Client's
-- cardArea, because it answers the same question for the same reason.
local function lane()
	local layout = UIDevice.Layout()
	if layout.IsTouch and layout.ModalArea and layout.ModalArea.Fits then
		return layout.ModalArea
	end
	local safe = layout.Safe
	local margin = layout.IsTouch and 12 or 18
	local bottom = safe.Bottom - margin
	if layout.IsTouch and layout.Zones and layout.Zones.Controls then
		bottom = math.min(bottom, layout.Zones.Controls.Top - 10)
	end
	return {
		Left = safe.Left + margin,
		Top = safe.Top + margin,
		Right = safe.Right - margin,
		Bottom = bottom,
	}
end

local function applyLayout()
	local layout = UIDevice.Layout()
	local free = lane()
	local laneWidth = math.max(200, free.Right - free.Left)
	local laneHeight = math.max(160, free.Bottom - free.Top)
	local tap = layout.IsTouch and 44 or 32

	local width = math.floor(math.min(CARD_MAX_WIDTH, laneWidth))
	local inner = width - PAD * 2
	-- MEASURED, not assumed. The bodies run 35-60 words and the lane is 200px
	-- wide on the narrowest device in the matrix; a fixed body height either
	-- truncates the long notes there or leaves a hole under the short ones
	-- everywhere else. GetTextSize is the synchronous API, which matters because
	-- this runs from UIDevice.Changed and must not yield inside it.
	local measured = TextService:GetTextSize(body.Text, body.TextSize, body.Font,
		Vector2.new(inner, 10000))
	local head = PAD + 14 + 22 + 16
	local bodyHeight = math.clamp(math.ceil(measured.Y) + 2,
		20, math.max(20, laneHeight - head - GAP - tap - PAD))
	local height = head + bodyHeight + GAP + tap + PAD

	card.Size = UDim2.fromOffset(width, height)
	card.Position = UIDevice.LocalPosition(gui,
		math.floor((free.Left + free.Right - width) / 2),
		math.floor(math.max(free.Top, (free.Top + free.Bottom - height) / 2)))

	eyebrow.Position = UDim2.fromOffset(PAD, PAD)
	eyebrow.Size = UDim2.fromOffset(inner, 14)
	title.Position = UDim2.fromOffset(PAD, PAD + 14)
	title.Size = UDim2.fromOffset(inner, 22)
	stamp.Position = UDim2.fromOffset(PAD, PAD + 36)
	stamp.Size = UDim2.fromOffset(inner, 16)
	body.Position = UDim2.fromOffset(PAD, head)
	body.Size = UDim2.fromOffset(inner, bodyHeight)
	close.Position = UDim2.fromOffset(PAD, head + bodyHeight + GAP)
	close.Size = UDim2.fromOffset(inner, tap)
	close.TextSize = layout.IsTouch and 14 or 13

	local captionWidth = math.floor(math.min(340, laneWidth))
	caption.Size = UDim2.fromOffset(captionWidth, layout.IsTouch and 40 or 34)
	caption.Position = UIDevice.LocalPosition(gui,
		math.floor((free.Left + free.Right - captionWidth) / 2),
		math.floor(free.Bottom - (layout.IsTouch and 40 or 34)))
end

-- ── showing ─────────────────────────────────────────────────────────────────

local function closeCard()
	cardSerial += 1
	shown = nil
	card.Visible = false
end

local function openCard(note)
	cardSerial += 1
	local serial = cardSerial
	shown = note
	title.Text = note.Title
	stamp.Text = note.Stamp
	body.Text = note.Body
	applyLayout()
	card.Visible = true
	task.delay(AUTO_CLOSE_SECONDS, function()
		if cardSerial == serial then closeCard() end
	end)
end

local function showCaption(text)
	captionSerial += 1
	local serial = captionSerial
	captionLabel.Text = text
	applyLayout()
	caption.Visible = true
	task.delay(CAPTION_SECONDS, function()
		if captionSerial == serial then caption.Visible = false end
	end)
end

close.Activated:Connect(closeCard)

remote.OnClientEvent:Connect(function(event, noteId)
	if event == "discovered" then
		local note = byId[noteId]
		if not note then
			-- A build whose content module is older than its server. Say
			-- something true rather than open an empty card.
			showCaption("FIELD NOTE LOGGED")
			return
		end
		openCard(note)
	elseif event == "alreadyLogged" then
		showCaption("ALREADY IN YOUR COLLECTION")
	elseif event == "unavailable" then
		showCaption("FIELD NOTES UNAVAILABLE")
	end
end)

player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") ~= true then
		closeCard()
		captionSerial += 1
		caption.Visible = false
	end
end)

UIDevice.Changed:Connect(function()
	if shown or caption.Visible then applyLayout() end
end)

applyLayout()
