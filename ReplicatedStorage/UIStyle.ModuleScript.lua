--!strict
-- UIStyle -- ONE statement of the in-game UI's shared look. (Trello #98)
--
-- WHERE THE NUMBERS COME FROM. The owner named two surfaces as the reference
-- and asked for the rest of the game to read like them. Every value below is
-- copied off one of those two, and the comment says which:
--
--   StarterPlayerScripts/PuzzleUI.LocalScript.lua  -- the OBJECTIVES panel
--     objectivePanel  "Level1Objectives"   panel bg .08 / stroke 75,94,83 @.28 / corner 10
--     SignalAccent, ProgressTrack, Fill    accent 83,204,145
--     Eyebrow                              Code 10, 101,177,139
--     objectiveTitle                       GothamBold 16, 231,238,233
--     makeLabel rows                       GothamMedium 13, 201,213,205 (muted 142,159,149)
--     objectivesToggle                     control bg 14,20,17 @.04, corner 9, hover 24,33,28
--     LAYOUT.PadX/PadTop/PadBottom/RowHeight/RowGap/Margin
--
--   StarterPlayerScripts/RoundUI.LocalScript.lua   -- the MISSION BRIEF card
--     subtitleFrame  "CommandSubtitles"    caption bg 4,8,6 @.18, corner 8, stroke 82,224,164 @.38 x1.5
--     subtitleSpeaker                      Code 13, 105,238,168
--     subtitleText                         GothamMedium 20, 240,242,235
--     objectivesButton "ObjectivesButton"  control bg 14,20,17 @.04, corner 9, hover 25,34,29
--     objectivesPanel  "ObjectivesPanel"   card bg 8,12,10 @.035, corner 12, stroke @.25
--     objectivesClose                      chip corner 8, stroke 84,101,92 @.46
--     Objective<n> rows                    corner 7, warning 42,34,20 / 139,111,58 / 224,188,111
--
-- WHAT THESE HELPERS DO: set properties, and adopt (never duplicate) an
-- existing UICorner/UIStroke. They never move, size, name, parent, show or
-- hide anything -- placement, copy and behaviour stay in the file that owns
-- them, because that is where the measured layout contracts live.

local UIStyle = {}

-- Chrome. The two panels differ only in depth: the HUD panel sits on the world
-- (.08) and the full card is nearly opaque (.035).
UIStyle.Color = {
	Panel = Color3.fromRGB(9, 13, 11),        -- Level1Objectives
	Card = Color3.fromRGB(8, 12, 10),         -- ObjectivesPanel
	Caption = Color3.fromRGB(4, 8, 6),        -- CommandSubtitles
	Control = Color3.fromRGB(14, 20, 17),     -- objectivesToggle / objectivesButton
	ControlHover = Color3.fromRGB(25, 34, 29),
	Chip = Color3.fromRGB(25, 33, 29),        -- objectivesClose
	Line = Color3.fromRGB(75, 94, 83),
	LineSoft = Color3.fromRGB(84, 101, 92),   -- objectivesClose
	Divider = Color3.fromRGB(72, 91, 80),

	Title = Color3.fromRGB(231, 238, 233),    -- objectiveTitle
	Body = Color3.fromRGB(201, 213, 205),     -- makeLabel
	Muted = Color3.fromRGB(142, 159, 149),    -- carryLabel
	Caption3 = Color3.fromRGB(240, 242, 235), -- subtitleText

	Accent = Color3.fromRGB(83, 204, 145),    -- SignalAccent / Fill
	AccentText = Color3.fromRGB(101, 177, 139), -- Eyebrow
	Live = Color3.fromRGB(105, 238, 168),     -- subtitleSpeaker, MUTE/STOP chips
	LiveStroke = Color3.fromRGB(82, 224, 164),-- CommandSubtitles stroke
	Positive = Color3.fromRGB(127, 218, 166), -- boxesLabel

	-- The brief's one non-green family: the "!" threat row.
	Warning = Color3.fromRGB(224, 188, 111),
	WarningText = Color3.fromRGB(224, 202, 151),
	WarningLine = Color3.fromRGB(139, 111, 58),
	-- The reference carries no red at all; these are the game's existing danger
	-- pair (Level 2 Objective UI's lethal-water state), stated here so the three
	-- levels stop each inventing their own.
	Danger = Color3.fromRGB(255, 116, 96),
	DangerText = Color3.fromRGB(255, 138, 120),
}

UIStyle.Radius = {
	Card = 12,     -- ObjectivesPanel
	Panel = 10,    -- Level1Objectives
	Control = 9,   -- objectivesToggle, objectivesButton
	Chip = 8,      -- objectivesClose, CommandSubtitles
	Inner = 7,     -- objective rows, number badges
	Key = 6,       -- Keycap
}

UIStyle.Stroke = {
	Thickness = 1,
	Transparency = 0.28,       -- Level1Objectives, objectivesToggle, objectivesButton
	CardTransparency = 0.25,   -- ObjectivesPanel
	SoftTransparency = 0.46,   -- objectivesClose
	RowTransparency = 0.48,    -- objective rows
	CaptionThickness = 1.5,    -- CommandSubtitles
	CaptionTransparency = 0.38,
}

UIStyle.Transparency = {
	Panel = 0.08,    -- Level1Objectives
	Card = 0.035,    -- ObjectivesPanel
	Caption = 0.18,  -- CommandSubtitles
	Control = 0.04,  -- objectivesToggle / objectivesButton
	Chip = 0.08,     -- objectivesClose
	Row = 0.42,      -- objective rows
}

UIStyle.Font = {
	Title = Enum.Font.GothamBold,    -- objectiveTitle, objectivesTitle, BriefLabel
	Body = Enum.Font.GothamMedium,   -- makeLabel, subtitleText, row Description
	Readout = Enum.Font.Code,        -- Eyebrow, subtitleSpeaker, MUTE/STOP
	Button = Enum.Font.GothamBold,
}

UIStyle.TextSize = {
	Eyebrow = 10,     -- Eyebrow
	Readout = 13,     -- subtitleSpeaker
	Title = 16,       -- objectiveTitle
	CardTitle = 20,   -- objectivesTitle
	Body = 13,        -- makeLabel, row Description
	Caption = 20,     -- subtitleText
	Button = 13,      -- MUTE DISPATCH
	ButtonSmall = 12, -- BriefLabel
}

-- Spacing, from PuzzleUI's LAYOUT contract.
UIStyle.Pad = {
	Margin = 18, X = 16, Top = 27, Bottom = 9,
	Row = 21, RowGap = 3, Accent = 12, AccentWidth = 3,
}

local EMPTY: {[string]: any} = {}

-- `or` is wrong for a 0 or a false: BackgroundTransparency = 0 is a real
-- request and would silently become the default.
local function pick(given: any, fallback: any): any
	if given == nil then return fallback end
	return given
end

local function adopt(parent: Instance, class: string): any
	local found = parent:FindFirstChildOfClass(class)
	if found then return found end
	local made = Instance.new(class)
	made.Parent = parent
	return made
end

-- The dark rounded card everything else sits on. `options`:
--   Background, Transparency, Radius, Stroke, StrokeTransparency, Thickness
function UIStyle.panel(frame: GuiObject, options: {[string]: any}?): GuiObject
	local opt = options or EMPTY
	frame.BackgroundColor3 = pick(opt.Background, UIStyle.Color.Panel)
	frame.BackgroundTransparency = pick(opt.Transparency, UIStyle.Transparency.Panel)
	frame.BorderSizePixel = 0
	adopt(frame, "UICorner").CornerRadius =
		UDim.new(0, pick(opt.Radius, UIStyle.Radius.Panel))
	local stroke = adopt(frame, "UIStroke")
	stroke.Color = pick(opt.Stroke, UIStyle.Color.Line)
	stroke.Thickness = pick(opt.Thickness, UIStyle.Stroke.Thickness)
	stroke.Transparency = pick(opt.StrokeTransparency, UIStyle.Stroke.Transparency)
	-- STATED, never defaulted. ApplyStrokeMode's default is Contextual, and on a
	-- TextLabel/TextButton Contextual means "outline the TEXT" -- so a stroke
	-- meant as a panel border either outlines the copy instead (ProtectionHUD's
	-- caption, Round Exit's buttons) or, when the object's own Text is "",
	-- draws NOTHING AT ALL. That last one is why Level 3's ReaderPanel, a
	-- TextButton whose whole rectangle is the tap target, has been carrying a
	-- border in code that the engine never drew. Every caller here wants the
	-- border, so say so.
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return frame
end

-- The MISSION BRIEF / objectives-toggle treatment. Same chrome as a panel, one
-- step lighter, plus the button face. AutoButtonColor is deliberately NOT
-- touched: the reference uses both settings and it is a feel decision the
-- owning file makes.
function UIStyle.button(object: TextButton, options: {[string]: any}?): TextButton
	local opt = options or EMPTY
	UIStyle.panel(object, {
		Background = pick(opt.Background, UIStyle.Color.Control),
		Transparency = pick(opt.Transparency, UIStyle.Transparency.Control),
		Radius = pick(opt.Radius, UIStyle.Radius.Control),
		Stroke = opt.Stroke, StrokeTransparency = opt.StrokeTransparency,
		Thickness = opt.Thickness,
	})
	object.Font = pick(opt.Font, UIStyle.Font.Button)
	object.TextColor3 = pick(opt.TextColor, UIStyle.Color.Title)
	if not object.TextScaled then
		object.TextSize = pick(opt.TextSize, UIStyle.TextSize.Button)
	end
	return object
end

-- The reference's own hover: swap the control background, nothing else.
-- Returns the two connections so a caller that tears its UI down can drop them.
function UIStyle.hover(object: GuiButton, resting: Color3?, lifted: Color3?)
	local base = resting or object.BackgroundColor3
	local over = lifted or UIStyle.Color.ControlHover
	return object.MouseEnter:Connect(function() object.BackgroundColor3 = over end),
		object.MouseLeave:Connect(function() object.BackgroundColor3 = base end)
end

function UIStyle.title(object: TextLabel | TextButton, options: {[string]: any}?): any
	local opt = options or EMPTY
	object.Font = pick(opt.Font, UIStyle.Font.Title)
	object.TextColor3 = pick(opt.TextColor, UIStyle.Color.Title)
	if not object.TextScaled then
		object.TextSize = pick(opt.TextSize, UIStyle.TextSize.Title)
	end
	return object
end

function UIStyle.body(object: TextLabel | TextButton, options: {[string]: any}?): any
	local opt = options or EMPTY
	object.Font = pick(opt.Font, UIStyle.Font.Body)
	object.TextColor3 = pick(opt.TextColor, UIStyle.Color.Body)
	if not object.TextScaled then
		object.TextSize = pick(opt.TextSize, UIStyle.TextSize.Body)
	end
	return object
end

-- A monospaced status line -- the reference's Eyebrow and "> COMMAND CENTER"
-- role. Meters whose box glyphs have to line up stay here rather than in
-- title(); that is the whole reason the reference keeps a Code face at all.
function UIStyle.readout(object: TextLabel | TextButton, options: {[string]: any}?): any
	local opt = options or EMPTY
	object.Font = pick(opt.Font, UIStyle.Font.Readout)
	object.TextColor3 = pick(opt.TextColor, UIStyle.Color.AccentText)
	if not object.TextScaled then
		object.TextSize = pick(opt.TextSize, UIStyle.TextSize.Readout)
	end
	return object
end

-- The subtitle band: a caption sitting over the world, so it is darker and its
-- stroke is the live-transmission green rather than the neutral line.
function UIStyle.caption(object: GuiObject, options: {[string]: any}?): GuiObject
	local opt = options or EMPTY
	UIStyle.panel(object, {
		Background = pick(opt.Background, UIStyle.Color.Caption),
		Transparency = pick(opt.Transparency, UIStyle.Transparency.Caption),
		Radius = pick(opt.Radius, UIStyle.Radius.Chip),
		Stroke = pick(opt.Stroke, UIStyle.Color.LiveStroke),
		Thickness = pick(opt.Thickness, UIStyle.Stroke.CaptionThickness),
		StrokeTransparency = pick(opt.StrokeTransparency, UIStyle.Stroke.CaptionTransparency),
	})
	return object
end

return UIStyle
