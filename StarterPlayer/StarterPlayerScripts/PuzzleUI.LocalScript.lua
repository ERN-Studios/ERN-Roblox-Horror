-- PuzzleUI (v3 — counters plus lever synchronization timer)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIDevice = require(RS:WaitForChild("UIDevice"))
local RunService = game:GetService("RunService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("PuzzleStatus")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "PuzzleGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 18

gui.Parent = player:WaitForChild("PlayerGui")

local function syncDispatchSuppression()
	gui.Enabled = player:GetAttribute("ZyntraDispatchClientActive") ~= true
		and player:GetAttribute("LevelOneGuideObjectivesOpen") ~= true
		-- ...and no screen-owning modal. This HUD is Active and sits at
		-- DisplayOrder 18, under the terminal's 55, so it did not paint over it
		-- -- but the objectives toggle stayed in the input stack underneath, and
		-- a modal that owns the screen owns the taps too.
		and not UIDevice.ScreenOwningModalOpen()
end
player:GetAttributeChangedSignal("ZyntraDispatchClientActive"):Connect(syncDispatchSuppression)
player:GetAttributeChangedSignal("LevelOneGuideObjectivesOpen"):Connect(syncDispatchSuppression)
UIDevice.OnScreenOwningModalChanged(syncDispatchSuppression)
syncDispatchSuppression()

-- C1_OBJECTIVES_LOWER_RIGHT_20260829 / C2_OBJECTIVE_ROWS_20260829 -- the whole
-- geometry contract for this HUD, in ONE table, so the layout code and a
-- regression test read the same numbers instead of two sets of magic literals.
--
-- WHAT SHIPPED BROKEN, twice over:
--
--  C1  The objective panel and the exit-energy detector were each authored as a
--      fixed box pinned to its own bottom corner, and nothing ever checked that
--      the corners were far enough apart. Measured at 705x338 the panel held
--      (387,150)-(687,262) and the detector (132,148)-(442,264) -- a 55px
--      horizontal overlap, with the detector's readout printed under the
--      objective rows. They are now laid out as ONE row with an explicit
--      separation rule, so an overlap is not a state the numbers can express.
--
--  C2  The panel was clamped to a 56px minimum height on touch while its rows
--      kept hard-coded offsets y = 34/59/84 at 23px each. Measured on a Galaxy
--      A06 the rows ran to y=257 inside a panel that ended at y=206: the carry
--      and lever rows were drawn OUTSIDE their own panel and on top of the
--      movement band. Rows are now stacked from the top pad downward and the
--      panel's height is DERIVED from the visible rows, so a row cannot land
--      outside the panel by construction.
local LAYOUT = {
	-- C1 corner contract, DESKTOP. The TOGGLE is the element pinned to the corner
	-- -- deliberately, so it cannot move when the panel it controls changes height
	-- or hides. The panel stacks directly above it, the transient message above
	-- that. Touch inverts the anchor and folds both of those into the panel: see
	-- C_L1_TOGGLE_AND_MESSAGE_OWN_THEIR_RECTANGLES_20260831 for that composition,
	-- and the TouchToggleSize block below for the figures it uses.
	Margin = 18,
	ToggleWidth = 36,
	ToggleHeight = 36,
	ToggleGap = 8,
	MessageHeight = 22,
	MessageGap = 4,
	MessageTextSize = 15,

	-- C_L1_TOGGLE_AND_MESSAGE_OWN_THEIR_RECTANGLES_20260831. On touch the toggle
	-- lives INSIDE the panel, so its rectangle is stated here once as a SQUARE at
	-- this game's tap-target floor rather than derived from whatever caption it
	-- happens to carry -- a control whose size follows its own text is a control
	-- whose overlaps cannot be reasoned about before it is drawn.
	--
	-- ToggleInsetGap is the clear space between the toggle and whatever row shares
	-- its band. ToggleBesideMinCopy is the narrowest copy column a row may be left
	-- with before the toggle stops sharing a band at all: it is the widest single
	-- unbreakable word Level 1 prints, "RESTORATION", which needs ~112px at the
	-- natural 17px Code face, rounded up. Below that the wrapper starts breaking
	-- the word itself, which is the "> POWER / RESTORATIO / N" the narrow columns
	-- would otherwise have shown.
	TouchToggleSize = 44,
	ToggleInsetGap = 8,
	ToggleBesideMinCopy = 120,
	CompactMessageHeight = 16,
	CompactMessageTextSize = 12,

	-- C1 reflow. The objectives column and the detector share one row and must
	-- stay ColumnGap apart; applyPuzzleLayout walks the ordered steps.
	ColumnGap = 16,
	ObjectivesWidth = 300,
	ObjectivesMinWidth = 220,
	DetectorWidth = 310,
	DetectorMinWidth = 240,
	DetectorTouchMinWidth = 150,
	DetectorHeight = 116,
	-- A TEST a rectangle either passes or fails, never a floor forced onto the
	-- answer. Forcing it is what shipped broken: applied inside a top band
	-- shorter than 44px it drew the card straight through the band's own bottom
	-- edge, which IS the thumbstick's activation top. See the candidate walk in
	-- applyPuzzleLayout. (C_L1_DETECTOR_FITS_20260830)
	DetectorMinHeight = 44,
	-- The smallest face this HUD prints. The detector's header and its readout
	-- step down to fit the box the placement could actually give them, and stop
	-- here rather than shrinking to nothing.
	DetectorMinFace = 9,
	DetectorLeft = 132,          -- the authored desktop inset
	DetectorMargin = 16,
	SafeLeft = 12,
	BottomSafe = 12,
	CorridorMinWidth = 150,      -- the threshold Level 2 Objective UI already uses

	-- C2 row metrics. The NATURAL tier reproduces the authored 300x112 panel
	-- exactly when all four rows are visible (6 + 25 + 2 + 3*23 + 2*2 + 6 = 112);
	-- the COMPACT tier is the stated minimum a row may shrink to.
	PadX = 16, PadTop = 27, PadBottom = 9,
	TitleHeight = 22, RowHeight = 21, RowGap = 3,
	TitleTextSize = 16, RowTextSize = 13,
	CompactPadX = 12, CompactPadTop = 21, CompactPadBottom = 7,
	CompactTitleHeight = 18, CompactRowHeight = 16,
	CompactTitleTextSize = 13, CompactRowTextSize = 11,
}

-- Forward declaration: the row helpers and the visibility helpers below all
-- need to re-place the column when a row appears or disappears, and the
-- placement function itself needs the row helpers. One of the two has to be
-- declared early; this is the one with no dependencies of its own.
local applyPuzzleLayout

-- Level 1 now uses the same compact terminal-card language as Level 2 instead
-- of three unrelated floating counters.
local objectivePanel = Instance.new("Frame")
objectivePanel.Name = "Level1Objectives"
objectivePanel.AnchorPoint = Vector2.new(1, 1)
objectivePanel.Position = UDim2.new(1, -18, 1, -18)
objectivePanel.Size = UDim2.new(0, 300, 0, 112)
objectivePanel.BackgroundColor3 = Color3.fromRGB(9, 13, 11)
objectivePanel.BackgroundTransparency = 0.08
objectivePanel.BorderSizePixel = 0
objectivePanel.Visible = false
objectivePanel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = objectivePanel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(75, 94, 83)
panelStroke.Transparency = 0.28
panelStroke.Thickness = 1
panelStroke.Parent = objectivePanel

-- A quiet field-brief hierarchy keeps the live objective readable without
-- turning the corner of the screen into a glowing terminal.
LAYOUT.visualSetup = (function()
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 23, 19)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 10, 9)),
	})
	gradient.Rotation = 90
	gradient.Parent = objectivePanel

	local accent = Instance.new("Frame")
	accent.Name = "SignalAccent"
	accent.Position = UDim2.fromOffset(0, 12)
	accent.Size = UDim2.new(0, 3, 1, -24)
	accent.BackgroundColor3 = Color3.fromRGB(83, 204, 145)
	accent.BackgroundTransparency = 0.14
	accent.BorderSizePixel = 0
	accent.Parent = objectivePanel
	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(1, 0)
	accentCorner.Parent = accent

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Name = "Eyebrow"
	eyebrow.Position = UDim2.fromOffset(16, 7)
	eyebrow.Size = UDim2.new(1, -80, 0, 13)
	eyebrow.BackgroundTransparency = 1
	eyebrow.Font = Enum.Font.Code
	eyebrow.Text = "LEVEL 1  //  ACTIVE OBJECTIVE"
	eyebrow.TextColor3 = Color3.fromRGB(101, 177, 139)
	eyebrow.TextSize = 10
	eyebrow.TextXAlignment = Enum.TextXAlignment.Left
	eyebrow.Parent = objectivePanel

	local progress = Instance.new("Frame")
	progress.Name = "ProgressTrack"
	progress.AnchorPoint = Vector2.new(0, 1)
	progress.Position = UDim2.new(0, 16, 1, -3)
	progress.Size = UDim2.new(1, -32, 0, 3)
	progress.BackgroundColor3 = Color3.fromRGB(52, 63, 57)
	progress.BackgroundTransparency = 0.28
	progress.BorderSizePixel = 0
	progress.Parent = objectivePanel
	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(1, 0)
	progressCorner.Parent = progress

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(83, 204, 145)
	fill.BorderSizePixel = 0
	fill.Parent = progress
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
end)()

function LAYOUT.SetProgress(current, total, colour)
	local track = objectivePanel:FindFirstChild("ProgressTrack")
	local fill = track and track:FindFirstChild("Fill")
	if not fill then return end
	local denominator = math.max(1, tonumber(total) or 1)
	fill.Size = UDim2.fromScale(math.clamp((tonumber(current) or 0) / denominator, 0, 1), 1)
	if colour then fill.BackgroundColor3 = colour end
end

local objectiveTitle = Instance.new("TextLabel")
objectiveTitle.Name = "ObjectiveTitle"
objectiveTitle.BackgroundTransparency = 1
-- Seeded from the contract; layoutObjectiveRows owns these from here on. (C2)
objectiveTitle.Position = UDim2.new(0, LAYOUT.PadX, 0, LAYOUT.PadTop)
objectiveTitle.Size = UDim2.new(1, -LAYOUT.PadX * 2, 0, LAYOUT.TitleHeight)
objectiveTitle.Font = Enum.Font.GothamBold
objectiveTitle.Text = "POWER RESTORATION"
objectiveTitle.TextColor3 = Color3.fromRGB(231, 238, 233)
objectiveTitle.TextSize = LAYOUT.TitleTextSize
objectiveTitle.TextXAlignment = Enum.TextXAlignment.Left
-- WRAPPED, and its height is measured. At 568x320 the objectives column is
-- 156px wide and "> POWER RESTORATION" needs 99x34 at the natural face -- two
-- lines in a 25px row, so the second line rendered outside the panel.
objectiveTitle.TextWrapped = true
objectiveTitle.TextYAlignment = Enum.TextYAlignment.Top
objectiveTitle.Parent = objectivePanel

-- C2: a row no longer carries a hard-coded y. It is handed one by
-- layoutObjectiveRows every time the set of VISIBLE rows changes, which is the
-- only way a row's position can stay inside a panel whose height also moves.
local function makeLabel(name)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.new(0, LAYOUT.PadX, 0, LAYOUT.PadTop)
	label.Size = UDim2.new(1, -LAYOUT.PadX * 2, 0, LAYOUT.RowHeight)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamMedium
	label.TextSize = LAYOUT.RowTextSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	-- Same as the title: "Levers: 0/3  -  NO TIME LIMIT" and
	-- "EXIT POWERED - FIND THE DOOR" both need two lines in a 156px column.
	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextColor3 = Color3.fromRGB(201, 213, 205)
	label.Visible = false
	label.Parent = objectivePanel
	return label
end

local boxesLabel = makeLabel("FuseBoxStatus")
local carryLabel = makeLabel("FuseCarryStatus")
local leverLabel = makeLabel("LeverStatus")
boxesLabel.TextColor3 = Color3.fromRGB(127, 218, 166)
carryLabel.TextColor3 = Color3.fromRGB(142, 159, 149)

-- FORWARD-DECLARED, and built with the other widgets further down. On touch the
-- transient message is a measured ROW of the same stack as the objective rows,
-- so the measurement helpers below have to be able to name it; on desktop it is
-- still a separate strip above the panel and is not in the stack at all.
local msgLabel

-- C1: the objectives TOGGLE. This is the element actually pinned to
-- AnchorPoint (1, 1) / Position (1, -Margin, 1, -Margin) on desktop; the panel
-- hangs above it. The user asked repeatedly for the objectives to live in the
-- LOWER-RIGHT corner, so the corner anchor is written once, here, as a contract
-- rather than rediscovered per branch.
local objectivesToggle = Instance.new("TextButton")
objectivesToggle.Name = "Level1ObjectivesToggle"
objectivesToggle.AnchorPoint = Vector2.new(1, 1)
objectivesToggle.Position = UDim2.new(1, -LAYOUT.Margin, 1, -LAYOUT.Margin)
objectivesToggle.Size = UDim2.fromOffset(LAYOUT.ToggleWidth, LAYOUT.ToggleHeight)
objectivesToggle.BackgroundColor3 = Color3.fromRGB(14, 20, 17)
objectivesToggle.BackgroundTransparency = 0.04
objectivesToggle.BorderSizePixel = 0
objectivesToggle.AutoButtonColor = false
objectivesToggle.Font = Enum.Font.GothamBold
objectivesToggle.Text = "v"
objectivesToggle.TextColor3 = Color3.fromRGB(155, 208, 178)
objectivesToggle.TextSize = 17
objectivesToggle.Visible = false
objectivesToggle.Parent = gui
local objectivesToggleCorner = Instance.new("UICorner")
objectivesToggleCorner.CornerRadius = UDim.new(0, 9)
objectivesToggleCorner.Parent = objectivesToggle
local objectivesToggleStroke = Instance.new("UIStroke")
objectivesToggleStroke.Color = Color3.fromRGB(75, 94, 83)
objectivesToggleStroke.Transparency = 0.28
objectivesToggleStroke.Thickness = 1
objectivesToggleStroke.Parent = objectivesToggle

objectivesToggle.MouseEnter:Connect(function()
	objectivesToggle.BackgroundColor3 = Color3.fromRGB(24, 33, 28)
end)
objectivesToggle.MouseLeave:Connect(function()
	objectivesToggle.BackgroundColor3 = Color3.fromRGB(14, 20, 17)
end)

local countersActive = false
local objectivesCollapsed = false
local objectivePanelWidth = LAYOUT.ObjectivesWidth

-- C2: how tall the stack of VISIBLE rows is. Two tiers and no interpolation --
-- natural, and the stated compact minimum -- because a half-scaled Code font
-- reads worse than a smaller one. `available` is the height the placement can
-- spare, or nil for "unconstrained" (desktop).
-- C_L1_COPY_FITS_20260830. The two tiers below used to hand back a CONSTANT
-- row height -- 23 natural, 16 compact -- and the rows were then given that
-- height whatever they had to say in it. Measured at 568x320, where the column
-- is 156px wide, every line of Level 1 copy needs two lines:
--
--   > POWER RESTORATION            99x34 at 17px in a 131px box
--   [---] FUSE BOXES  0/3         128x30 at 15px
--   Levers: 0/3  -  NO TIME LIMIT 112x30 at 15px
--   EXIT POWERED - FIND THE DOOR  114x30 at 15px
--
-- so all four rendered their second line outside the panel. Heights are
-- MEASURED now, at the face and wrap width the row will actually use, and the
-- panel is the sum of them. The tier still decides the FACE and the padding --
-- a smaller face is the right first move on a short column -- but it no longer
-- decides how much room a sentence gets.
local TextService = game:GetService("TextService")

-- ONE measurement, shared by the whole-stack pass below and by the single-row
-- re-check every copy change performs (setObjectiveText). Two copies of this
-- arithmetic is how the re-check would come to disagree with the layout it is
-- supposed to trigger.
-- `reserve` is the width a control BESIDE this row owns -- the inset toggle, and
-- nothing else. It is a parameter rather than a lookup because the whole-stack
-- pass and the single-row re-check have to agree on it, and the stack pass knows
-- it a row at a time.
local function rowTextHeight(text, face, floor, padX, width, reserve, font)
	local copyWidth = math.max(24,
		(width or LAYOUT.ObjectivesWidth) - padX * 2 - (reserve or 0))
	return math.max(floor, TextService:GetTextSize(text, face, font or Enum.Font.Code,
		Vector2.new(copyWidth, 100000)).Y)
end

-- The face and the floor a given row is measured at, by tier. Kept next to the
-- measurement so a caller cannot pick the title's face for a body row.
local function rowFaceAndFloor(label, compact)
	if label == objectiveTitle then
		return compact and LAYOUT.CompactTitleTextSize or LAYOUT.TitleTextSize,
			compact and LAYOUT.CompactTitleHeight or LAYOUT.TitleHeight
	end
	if label == msgLabel then
		return compact and LAYOUT.CompactMessageTextSize or LAYOUT.MessageTextSize,
			compact and LAYOUT.CompactMessageHeight or LAYOUT.MessageHeight
	end
	return compact and LAYOUT.CompactRowTextSize or LAYOUT.RowTextSize,
		compact and LAYOUT.CompactRowHeight or LAYOUT.RowHeight
end

-- C_L1_TOGGLE_AND_MESSAGE_OWN_THEIR_RECTANGLES_20260831 -- WHAT SHIPPED BROKEN.
--
-- The touch composition drew the toggle and the transient message ON TOP of the
-- panel's own content. The toggle was placed at panelTop + 2, right-aligned and
-- about 140x44; the message at panelTop + panelHeight - MessageHeight - 2.
-- Measured against the compact 300x80 stack this HUD actually produces on a
-- landscape handheld, the toggle's rectangle (y 2..46) covered the entire title
-- row (y 4..22) AND the first objective row (y 24..40), and the message
-- (y 56..78) covered the last one (y 60..76). Two of the four lines the player
-- is meant to read sat underneath a control, and on touch that control is also
-- the thing that eats the taps aimed at them.
--
-- Both now occupy space the stack has RESERVED, and the panel is the sum of it.
-- The guarantee is written down here rather than left to be re-derived, with
-- W = objectivePanelWidth, padX/padTop/padBottom the tier's padding,
-- T = LAYOUT.TouchToggleSize (44) and G = LAYOUT.ToggleInsetGap (8), every
-- figure panel-local:
--
--   TOGGLE  x [W - padX - T, W - padX]   y [padTop, padTop + T]
--           A square at the tap-target floor in the panel's top-right corner --
--           the same rectangle on every touch device and at both tiers, because
--           a control sized by its own caption is a control whose overlaps
--           cannot be settled before it is drawn.
--   ROWS    the title, then each VISIBLE objective row, then the message row
--           while it has something to say: stacked downward from the top pad,
--           RowGap apart, each exactly as tall as its own copy measures.
--           x [padX, W - padX - r], where r = T + G for a row whose TOP is
--           above the toggle's bottom edge and r = 0 for one below it.
--   PANEL   height = max(the last row's bottom, padTop + T) + padBottom.
--
-- which gives, by construction rather than by inspection:
--   * the toggle is inside the panel, and so is every row;
--   * a row that shares the toggle's band is G clear of it horizontally; a row
--     that does not starts below it. No row can meet the toggle either way;
--   * rows are RowGap apart in y, so no row can meet another -- and the message
--     is one of them, so it cannot sit on an objective row;
--   * the message is the LAST row, so it is below every objective row.
--
-- Where the panel is too narrow to leave a legible column beside the toggle
-- (copy narrower than ToggleBesideMinCopy) the toggle stops sharing a band
-- altogether: r is 0 for every row and the stack starts at padTop + T + RowGap.
-- That costs T + RowGap of height, and it is spent only on the columns
-- TopRightPanel has already stepped left of the control cluster to build, which
-- are the tall ones.
--
-- DESKTOP is untouched by all of this: there the toggle is the corner element
-- OUTSIDE the panel and the message is its own strip above it, so the stack is
-- still padTop + title + rows + padBottom and a four-row panel is still exactly
-- the authored 300x112.
local objectiveToggleInPanel = false

-- What the last layout pass decided, so a single copy change can be re-measured
-- against the SAME tier, width, floor and toggle reserve the stack was actually
-- laid out with.
local objectiveCompact = false
local objectiveRowGiven = {}
local objectiveRowReserve = {}

-- The stack, in the order it is drawn. The message joins it only on touch and
-- only while it has something to say -- exactly the way the lever row joins it
-- -- which is what makes "the message never sits on a row" a property of the
-- walk below rather than a clearance someone has to maintain by hand.
local function objectiveStack()
	local stack = {objectiveTitle}
	for _, row in ipairs({boxesLabel, carryLabel, leverLabel}) do
		if row.Visible then table.insert(stack, row) end
	end
	if objectiveToggleInPanel and msgLabel and msgLabel.Visible then
		table.insert(stack, msgLabel)
	end
	return stack
end

-- ONE walk. `apply` writes the result onto the labels; without it nothing is
-- touched and only the height comes back, so the height the placement ASKS the
-- anchor for and the geometry the rows are GIVEN can never be two calculations
-- that drift apart.
--
-- A row's reserve is decided from its own TOP, which is known before the row is
-- measured, so the top-down pass stays well defined even though a narrowed row
-- wraps taller and pushes the rows under it further down. A row that starts
-- above the toggle's bottom edge is narrowed for its whole height, which is the
-- conservative side of that test: it can only ever hold more clearance than the
-- overlap needs, never less.
local function walkObjectiveStack(compact, width, apply)
	width = width or LAYOUT.ObjectivesWidth
	local padX = compact and LAYOUT.CompactPadX or LAYOUT.PadX
	local padTop = compact and LAYOUT.CompactPadTop or LAYOUT.PadTop
	local padBottom = compact and LAYOUT.CompactPadBottom or LAYOUT.PadBottom
	local toggleBottom = padTop
	local reserve = 0
	local y = padTop
	if objectiveToggleInPanel then
		toggleBottom = padTop + LAYOUT.TouchToggleSize
		reserve = LAYOUT.TouchToggleSize + LAYOUT.ToggleInsetGap
		if width - padX * 2 - reserve < LAYOUT.ToggleBesideMinCopy then
			reserve = 0
			y = toggleBottom + LAYOUT.RowGap
		end
	end

	local first = true
	for _, label in ipairs(objectiveStack()) do
		if not first then y += LAYOUT.RowGap end
		first = false
		local face, floor = rowFaceAndFloor(label, compact)
		local rowReserve = (y < toggleBottom) and reserve or 0
		local height = rowTextHeight(label.Text, face, floor, padX, width, rowReserve, label.Font)
		if apply then
			label.Position = UDim2.new(0, padX, 0, y)
			label.Size = UDim2.new(1, -padX * 2 - rowReserve, 0, height)
			label.TextSize = face
			objectiveRowGiven[label] = height
			objectiveRowReserve[label] = rowReserve
		end
		y += height
	end
	-- The toggle's band is part of the panel even when the stack is shorter than
	-- it is: a one-row panel would otherwise end above its own toggle.
	return math.max(y, toggleBottom) + padBottom
end

local function totalHeight(compact, width)
	return walkObjectiveStack(compact, width, false)
end

local function objectiveRowMetrics(available, width)
	local natural = totalHeight(false, width)
	if available == nil or natural <= available then return natural, false end
	return totalHeight(true, width), true
end

-- C2: stack the visible rows from the top pad down and size the PANEL to the
-- result. The panel's height is never clamped below its own content -- if even
-- the compact stack is taller than the band it was offered, the panel keeps its
-- content and the placement above it is what gives. That is what makes "no
-- child outside the panel" structural rather than a value someone has to keep
-- in sync.
local function layoutObjectiveRows(available)
	local _, compact = objectiveRowMetrics(available, objectivePanelWidth)
	objectiveCompact = compact
	table.clear(objectiveRowGiven)
	table.clear(objectiveRowReserve)
	local height = walkObjectiveStack(compact, objectivePanelWidth, true)
	objectivePanel.Size = UDim2.fromOffset(objectivePanelWidth, height)
	local eyebrow = objectivePanel:FindFirstChild("Eyebrow")
	if eyebrow then
		eyebrow.Position = UDim2.fromOffset(compact and LAYOUT.CompactPadX or LAYOUT.PadX,
			compact and 4 or 7)
		eyebrow.TextSize = compact and 9 or 10
	end
	local progress = objectivePanel:FindFirstChild("ProgressTrack")
	if progress then
		local pad = compact and LAYOUT.CompactPadX or LAYOUT.PadX
		progress.Position = UDim2.new(0, pad, 1, -3)
		progress.Size = UDim2.new(1, -pad * 2, 0, 3)
	end
	return height
end

-- C_L1_TEXT_THEN_MEASURE_20260830 -- WHAT SHIPPED BROKEN.
--
-- The rows were measured, but never against the copy they were about to hold:
--
--   * refreshLever made the lever row visible and called applyPuzzleLayout()
--     and only THEN wrote "Levers: 0/3  •  NO TIME LIMIT". The stack was
--     measured against the row's PREVIOUS text -- the "Label" default it was
--     created with, on the frame the row appears -- so a two-line row was
--     handed the 23px one-line height and drew its second line outside the
--     panel.
--   * every later latch and timer update wrote straight to .Text and
--     re-measured nothing at all, so the row kept that height for the rest of
--     the round even though the copy grows mid-phase, from "Levers: 1/3" to
--     "Levers: 1/3  •  NO TIME LIMIT" the moment the latch arms.
--   * the "levers" and "exit" events rewrote the TITLE ("> POWER RESTORATION"
--     -> "> EXIT CIRCUIT" -> "> EXIT ONLINE") and left it to a relayout that
--     runs for a different reason -- a row appearing -- to measure it. Where
--     that row was already visible, nothing re-measured the title at all.
--
-- So the order is no longer something a caller can get wrong: this is the only
-- place a row's copy is written, it writes FIRST, and it re-enters the row
-- layout when -- and only when -- the new copy measures to a height other than
-- the one the row was last given. That gate is what keeps refreshLever's
-- per-frame timer off the whole-stack path: "Levers: 1/3  •  4.7s" and
-- "...  •  4.6s" measure identically, so a ticking second costs one
-- GetTextSize and no relayout.
--
-- msgLabel is deliberately NOT routed through here, even now that it is a row of
-- the stack on touch. Its copy and its VISIBILITY change together and always
-- from showMessage, which owns both and re-places the stack itself; routing it
-- through a helper that deliberately ignores hidden labels would drop exactly
-- the write that matters -- the one that arrives while the row is still down.
local function setObjectiveText(label, text, colour)
	if colour and label.TextColor3 ~= colour then label.TextColor3 = colour end
	text = tostring(text)
	if label.Text == text then return end
	label.Text = text
	-- A hidden row is not in the stack; whatever makes it visible lays the
	-- stack out, and measuring here would only buy a relayout nobody can see.
	if not label.Visible then return end
	local face, floor = rowFaceAndFloor(label, objectiveCompact)
	local padX = objectiveCompact and LAYOUT.CompactPadX or LAYOUT.PadX
	-- Against the SAME reserve the row was laid out with, not against the full
	-- panel width: a title measured as though the toggle were not beside it fits
	-- on one line where the real row needs two, and the gate would then decline
	-- the relayout that copy actually requires. An unchanged height means an
	-- unchanged stack, so the reserves below this row are unchanged too.
	if rowTextHeight(text, face, floor, padX, objectivePanelWidth,
		objectiveRowReserve[label], label.Font) ~= objectiveRowGiven[label] then
		applyPuzzleLayout()
	end
end

-- Transient feedback from the server ("Fuse extracted", "You have no fuses").
-- On desktop it is a strip of its own above the objective panel; on touch it is
-- the last ROW of the panel's stack. applyPuzzleLayout parents and configures it
-- for whichever of the two it is about to be, so nothing here decides that.
msgLabel = Instance.new("TextLabel")
msgLabel.Name = "PuzzleMessage"
msgLabel.AnchorPoint = Vector2.new(1, 1)
msgLabel.Position = UDim2.new(1, -18, 1, -136)
msgLabel.Size = UDim2.new(0, 300, 0, 22)
msgLabel.BackgroundTransparency = 1
msgLabel.Font = Enum.Font.Code
msgLabel.TextSize = 15
msgLabel.TextXAlignment = Enum.TextXAlignment.Right
msgLabel.TextColor3 = Color3.fromRGB(235, 220, 150)
msgLabel.Visible = false
msgLabel.Parent = gui

local msgSerial = 0
local function showMessage(text)
	-- The message belongs to the panel either way -- a row of it on touch, the
	-- strip above it on desktop -- so with the panel collapsed there is no stack
	-- for it to join and nothing for it to sit above; it would float in the corner
	-- on its own. Collapsed means collapsed.
	if objectivesCollapsed then return end
	msgSerial += 1
	local serial = msgSerial
	msgLabel.Text = tostring(text)
	msgLabel.Visible = true
	-- BOTH edges of the message re-place the stack, because on touch the message
	-- IS a row of it: appearing adds a row, the 1.8s expiry removes one, and a
	-- second message arriving over the first can measure to a different height in
	-- the row already standing. On desktop the message is not in the stack and
	-- this pass costs one relayout that changes nothing -- twice per message, at
	-- the rate a server sends them, which is not a budget worth an exception.
	applyPuzzleLayout()
	task.delay(1.8, function()
		if msgSerial == serial then
			msgLabel.Visible = false
			applyPuzzleLayout()
		end
	end)
end

-- Handheld exit-signal receiver
local receiver = Instance.new("Frame")
receiver.Name = "ExitEnergyDetector"
receiver.AnchorPoint = Vector2.new(0, 1)
receiver.Position = UDim2.new(0, 132, 1, -16)
receiver.Size = UDim2.new(0, 310, 0, 116)
receiver.BackgroundColor3 = Color3.fromRGB(5, 12, 7)
receiver.BackgroundTransparency = 0.08
receiver.BorderSizePixel = 0
receiver.Rotation = -1.5
receiver.Visible = false
receiver.Parent = gui

local receiverCorner = Instance.new("UICorner")
receiverCorner.CornerRadius = UDim.new(0, 8)
receiverCorner.Parent = receiver

local receiverStroke = Instance.new("UIStroke")
receiverStroke.Color = Color3.fromRGB(45, 170, 80)
receiverStroke.Thickness = 2
receiverStroke.Transparency = 0.42
receiverStroke.Parent = receiver

local receiverHeader = Instance.new("TextLabel")
-- NAMED, all four of them. They were every one of them the default
-- "TextLabel", so a regression could only report "TextLabel overlaps
-- TextLabel" and nobody could tell which two.
receiverHeader.Name = "DetectorHeader"
receiverHeader.Size = UDim2.new(1, -20, 0, 25)
receiverHeader.Position = UDim2.new(0, 10, 0, 8)
receiverHeader.BackgroundTransparency = 1
receiverHeader.Font = Enum.Font.Code
receiverHeader.TextSize = 15
receiverHeader.TextXAlignment = Enum.TextXAlignment.Left
receiverHeader.TextColor3 = Color3.fromRGB(65, 185, 95)
-- "> EXIT ENERGY DETECTOR // NAV" needs 150x22 at 11px against a 165px box on
-- the smallest landscape phone -- one line over, drawn outside its header.
receiverHeader.TextWrapped = true
receiverHeader.TextYAlignment = Enum.TextYAlignment.Top
receiverHeader.Text = "> EXIT ENERGY DETECTOR"
receiverHeader.Parent = receiver

local gammaMark = Instance.new("TextLabel")
gammaMark.Name = "DetectorBadge"
gammaMark.AnchorPoint = Vector2.new(1, 0)
gammaMark.Position = UDim2.new(1, -9, 0, 5)
gammaMark.Size = UDim2.new(0, 30, 0, 30)
gammaMark.BackgroundTransparency = 1
gammaMark.Font = Enum.Font.GothamBold
gammaMark.Text = "☢"
gammaMark.TextSize = 22
gammaMark.TextColor3 = Color3.fromRGB(80, 185, 105)
gammaMark.TextTransparency = 0.35
gammaMark.Parent = receiver

local receiverReadout = Instance.new("TextLabel")
receiverReadout.Name = "DetectorReadout"
receiverReadout.Size = UDim2.new(1, -20, 0, 66)
receiverReadout.Position = UDim2.new(0, 10, 0, 38)
receiverReadout.BackgroundTransparency = 1
receiverReadout.Font = Enum.Font.Code
receiverReadout.TextSize = 17
receiverReadout.TextWrapped = true
receiverReadout.TextXAlignment = Enum.TextXAlignment.Left
receiverReadout.TextYAlignment = Enum.TextYAlignment.Top
receiverReadout.TextColor3 = Color3.fromRGB(78, 178, 105)
receiverReadout.Text = "[■□□□] WEAK SIGNAL\nMove around to improve reception"
receiverReadout.Parent = receiver

local compassArrow = Instance.new("TextLabel")
compassArrow.Name = "DetectorCompass"
compassArrow.Position = UDim2.new(0, 12, 0, 36)
compassArrow.Size = UDim2.new(0, 66, 0, 68)
compassArrow.BackgroundTransparency = 1
compassArrow.Font = Enum.Font.Code
compassArrow.Text = "▲"
compassArrow.TextSize = 54
compassArrow.TextColor3 = Color3.fromRGB(75, 210, 110)
compassArrow.TextTransparency = 0.12
compassArrow.Visible = false
compassArrow.Parent = receiver

local receiverActive = false
local compassMode = false
local receiverClock = 0
local lastExitDistance = nil
local receiverHeight = LAYOUT.DetectorHeight
local receiverWidth = LAYOUT.DetectorWidth
local receiverNav = false

-- The two tiers' geometry in ONE table. detectorMinimumHeight has to test for
-- exactly the card layoutReceiver will then draw, and two copies of these
-- numbers is how a test and the thing it tests come apart.
local function receiverTier(compact)
 return {
  PadX = compact and 8 or 10,
  HeaderTop = compact and 3 or 8,
  HeaderHeight = compact and 15 or 25,
  HeaderFace = compact and 11 or 15,
  Badge = compact and 20 or 30,
  BadgeFace = compact and 15 or 22,
  Gap = compact and 2 or 5,
  PadBottom = compact and 4 or 12,
  ArrowWidth = compact and 40 or 66,
  ArrowFace = compact and 32 or 54,
  BodyFace = compact and 12 or 17,
 }
end

local function detectorTextHeight(text, face, width)
 return TextService:GetTextSize(text, face, Enum.Font.Code,
  Vector2.new(math.max(24, width), 100000)).Y
end

-- The largest face, from `start` down to LAYOUT.DetectorMinFace, that keeps the
-- string inside `height`. MEASURED, because the same copy is one line on a
-- 310px card and three on a 150px one.
local function fittedFace(text, width, height, start)
 local face = start
 while face > LAYOUT.DetectorMinFace and detectorTextHeight(text, face, width) > height do
  face -= 1
 end
 return face
end

local function detectorBodyLeft(tier)
 return receiverNav and (tier.PadX + tier.ArrowWidth + 8) or tier.PadX
end

-- What the card needs to hold what it currently SAYS, at a given width, on the
-- compact tier -- i.e. the least it can honestly be. The placement tests
-- candidate rectangles against this instead of against LAYOUT.DetectorMinHeight
-- alone, because that constant lies: every readout branch is two lines by
-- construction ("[■■□□] STRONG SIGNAL\nContinue this way"), which is 28px at the
-- compact 12px face, and a 44px card leaves 15px of body to put them in.
local function detectorMinimumHeight(width)
 local tier = receiverTier(true)
 local headerWidth = width - (tier.PadX * 2 + tier.Badge + 6)
 local headerFace = fittedFace(receiverHeader.Text, headerWidth,
  tier.HeaderHeight, tier.HeaderFace)
 local headerRow = math.max(tier.HeaderHeight,
  detectorTextHeight(receiverHeader.Text, headerFace, headerWidth))
 local bodyWidth = width - (detectorBodyLeft(tier) + tier.PadX)
 return tier.HeaderTop + math.max(headerRow, tier.Badge) + tier.Gap
  + detectorTextHeight(receiverReadout.Text, tier.BodyFace, bodyWidth)
  + tier.PadBottom
end

-- The detector had the same disease as the objective panel: applyPuzzleLayout
-- shrank the FRAME on touch while the header/readout/compass kept the offsets
-- authored for a 116px card, so at 705x338 a 75px detector still drew a readout
-- ending at y=104. Its children are now derived from receiverHeight, and the
-- NAV variant (which used to be written inline at two call sites, twice, with
-- slightly different numbers) is one flag read here.
local function layoutReceiver()
 local tier = receiverTier(receiverHeight < 96)
 -- The badge is anchored to the RIGHT edge and the header runs up to it. Its
 -- old geometry put it `padX - 1` from the edge and `headerTop - 3` from the
 -- top -- which is ABOVE the panel on the compact tier, where headerTop is 3 --
 -- and left the header a `-(padX * 2 + 26)` width that did not account for the
 -- badge's real size, so the two overlapped by a few pixels. Both are derived
 -- from the badge's actual footprint now.
 gammaMark.Position = UDim2.new(1, -tier.PadX, 0, tier.HeaderTop)
 gammaMark.Size = UDim2.fromOffset(tier.Badge, tier.Badge)
 gammaMark.TextSize = tier.BadgeFace

 -- MEASURED, both strings. "> EXIT ENERGY DETECTOR // NAV" needs 150x22 at 11px
 -- against the box a narrow card leaves it, i.e. two lines in a 15px header row
 -- drawn over the readout underneath. The face steps down until the copy fits
 -- the row the tier allots it, and the row itself grows only where even the
 -- floor face cannot hold it.
 local headerWidth = receiverWidth - (tier.PadX * 2 + tier.Badge + 6)
 local headerFace = fittedFace(receiverHeader.Text, headerWidth,
  tier.HeaderHeight, tier.HeaderFace)
 local headerHeight = math.max(tier.HeaderHeight,
  detectorTextHeight(receiverHeader.Text, headerFace, headerWidth))
 receiverHeader.Position = UDim2.new(0, tier.PadX, 0, tier.HeaderTop)
 receiverHeader.Size = UDim2.new(1, -(tier.PadX * 2 + tier.Badge + 6), 0, headerHeight)
 receiverHeader.TextSize = headerFace

 -- The body clears the HEADER ROW, which is the taller of the header and the
 -- badge beside it. Measured from the header alone, a 20px badge on the
 -- compact tier reached 3px past a 15px header and into the readout.
 local bodyTop = tier.HeaderTop + math.max(headerHeight, tier.Badge) + tier.Gap
 local bodyHeight = math.max(12, receiverHeight - bodyTop - tier.PadBottom)
 compassArrow.Position = UDim2.new(0, tier.PadX + 2, 0, bodyTop)
 compassArrow.Size = UDim2.fromOffset(tier.ArrowWidth, bodyHeight)
 compassArrow.TextSize = tier.ArrowFace

 local bodyLeft = detectorBodyLeft(tier)
 receiverReadout.Position = UDim2.new(0, bodyLeft, 0, bodyTop)
 receiverReadout.Size = UDim2.new(1, -(bodyLeft + tier.PadX), 0, bodyHeight)
 -- The readout is the only thing on this card anyone reads, so its face is
 -- fitted to the box the placement could actually give it rather than assumed
 -- from the tier.
 receiverReadout.TextSize = fittedFace(receiverReadout.Text,
  receiverWidth - (bodyLeft + tier.PadX), bodyHeight, tier.BodyFace)
end

-- The same rule as setObjectiveText, for the card's own copy: write FIRST, then
-- re-fit. layoutReceiver measures both strings, so re-running it after a copy
-- change is what keeps a two-line readout from being drawn against a box that
-- was fitted to the one-line string it replaced. Unchanged copy costs one
-- comparison -- the heartbeat rewrites the same sentence four times a second.
local function setDetectorText(label, text)
 text = tostring(text)
 if label.Text == text then return end
 label.Text = text
 layoutReceiver()
end

local function setReceiver(on)
 receiverActive = on
 receiver.Visible = on
 lastExitDistance = nil
 compassMode = false
 compassArrow.Visible = false
 -- NAV first, then the copy: detectorBodyLeft reads the flag, so writing the
 -- header while the previous round's flag is still set fits it to the wrong box.
 receiverNav = false
 setDetectorText(receiverHeader, "> EXIT ENERGY DETECTOR")
 layoutReceiver()
 receiverClock = 0
end

-- The NAV variant, in ONE place. It was written inline at both the "escape" and
-- the "exit" branches, and both wrote the readout AFTER the layout that was
-- meant to fit it. The order here is: flag, then copy, then place -- the flag
-- decides where the readout's box starts (the compass arrow takes the left of
-- the body), so both strings are measured against the box they end up in.
--
-- The full placement, not just layoutReceiver: the header gains " // NAV" and
-- the compass takes the left of the body, and how tall a card that copy needs
-- is what decides which rectangle the card is allowed to sit in.
local function enterNavMode()
 setReceiver(true)
 compassMode = true
 compassArrow.Visible = true
 receiverNav = true
 setDetectorText(receiverHeader, "> EXIT ENERGY DETECTOR // NAV")
 setDetectorText(receiverReadout, "EXIT VECTOR LOCKED\nFOLLOW DIRECTION")
 applyPuzzleLayout()
end

local function signalMeter(distance)
 local filled = math.clamp(9 - math.ceil(distance / 42), 1, 8)
 return "[" .. string.rep("■", filled) .. string.rep("□", 8 - filled) .. "]"
end

RunService.Heartbeat:Connect(function(dt)
 if not receiverActive then return end
 receiverClock += dt
 if receiverClock < 0.22 then return end
 receiverClock = 0

 local exitPos = workspace:GetAttribute("ExitPos")
 local character = player.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 if typeof(exitPos) ~= "Vector3" or not root then
  setDetectorText(receiverReadout, "[□□□□□□□□] SEARCHING...\nMove around to find the signal")
  return
 end

 if compassMode then
  local delta = Vector3.new(exitPos.X - root.Position.X, 0, exitPos.Z - root.Position.Z)
  local camera = workspace.CurrentCamera
  if delta.Magnitude > 0.01 and camera then
   local targetDir = delta.Unit
   local look = camera.CFrame.LookVector
   local forward = Vector3.new(look.X, 0, look.Z)
   if forward.Magnitude > 0.01 then
    forward = forward.Unit
    local dot = math.clamp(forward:Dot(targetDir), -1, 1)
    local cross = forward.X * targetDir.Z - forward.Z * targetDir.X
    compassArrow.Rotation = math.deg(math.atan2(cross, dot))
   end
  end
  setDetectorText(receiverReadout, "EXIT VECTOR LOCKED\nFOLLOW DIRECTION")
  return
 end

 local distance = (root.Position - exitPos).Magnitude
 local approaching = lastExitDistance and distance < lastExitDistance - 1
 local fading = lastExitDistance and distance > lastExitDistance + 1
 local meter = signalMeter(distance)
 lastExitDistance = distance

 if distance > 260 then
  setDetectorText(receiverReadout, meter .. " WEAK SIGNAL\nMove around to improve reception")
 elseif distance > 150 then
  setDetectorText(receiverReadout, approaching
   and meter .. " SIGNAL IMPROVING\nKeep going"
   or (fading
    and meter .. " SIGNAL FADING\nTry a different path"
    or meter .. " FAINT SIGNAL\nSearch for a clearer path"))
 elseif distance > 70 then
  setDetectorText(receiverReadout, approaching
   and meter .. " STRONG SIGNAL\nContinue this way"
   or (fading
    and meter .. " SIGNAL FADING\nTurn back and search nearby"
    or meter .. " STRONG SIGNAL\nSearch nearby"))
 else
  setDetectorText(receiverReadout, meter .. " VERY STRONG SIGNAL\nThe powered exit is close")
 end
end)

local leverPhase = false
local leverActive = 0
local leverTotal = 0
local leverEndsAt = 0
local leverLatchMode = false
local leverLatchDone = false

-- The toggle's caption follows the rectangle it has to fit in, which is why it
-- is decided here and not where the collapsed state changes. Inside the panel
-- the control is a 44x44 square -- the tap-target floor and nothing more, so it
-- costs the title beside it as little width as a tappable control can -- and
-- "OBJECTIVES  -" does not go in 44px at any face this HUD prints. The word is
-- not lost: the row it sits beside is the objective title. On desktop the toggle
-- is the corner element with 140px of its own and keeps the full caption.
local function refreshToggleCaption()
	objectivesToggle.Text = objectivesCollapsed and "^" or "v"
	objectivesToggle.TextSize = objectiveToggleInPanel and 20 or 17
end

-- One place decides what the objectives column shows. The panel is visible only
-- when the round wants counters AND the player has not collapsed it; the toggle
-- follows the round alone, so it never disappears out from under a tap.
local function applyObjectiveVisibility()
	-- The CAPTION is applyPuzzleLayout's, not this function's: it depends on the
	-- form factor as well as the collapsed state, and only the layout pass knows
	-- the form factor. This function ends by running one.
	-- SetInteractive rather than .Visible: a hidden-but-Active TextButton keeps
	-- eating taps through its transparent background, and this one sits in the
	-- corner every other lower-right HUD wants.
	UIDevice.SetInteractive(objectivesToggle, countersActive)
	objectivePanel.Visible = countersActive and not objectivesCollapsed
	if not objectivePanel.Visible then msgLabel.Visible = false end
	applyPuzzleLayout()
end

local function showCounters(on)
	countersActive = on
	boxesLabel.Visible = on
	carryLabel.Visible = on
	if not on then
		leverLabel.Visible = false
		msgLabel.Visible = false
	end
	-- The row set just changed, so the panel has to be re-measured, not just
	-- shown: this is the call that used to be missing and left the panel at
	-- whatever height the previous round's rows had wanted. (C2)
	applyObjectiveVisibility()
end

objectivesToggle.Activated:Connect(function()
	objectivesCollapsed = not objectivesCollapsed
	applyObjectiveVisibility()
end)

local function refreshLever()
	if not leverPhase then return end
	-- Skip the per-frame rebuild once the latch text is already showing.
	if leverLatchMode and leverLatchDone then return end
	-- The copy is decided BEFORE anything is laid out. The old order made the
	-- row visible and called applyPuzzleLayout() here, then wrote the text
	-- below, so the stack was measured against the string being replaced --
	-- against the label's "Label" default on the frame the row first appears.
	local text, colour
	if leverLatchMode then
		text = ("SYNC LEVERS   %d / %d  •  NO TIME LIMIT"):format(leverActive, leverTotal)
		colour = Color3.fromRGB(170, 225, 255)
	elseif leverActive > 0 and leverEndsAt > 0 then
		local remaining = math.max(leverEndsAt - os.clock(), 0)
		text = ("SYNC LEVERS   %d / %d  •  %.1fs"):format(leverActive, leverTotal, remaining)
		colour = remaining <= 3
			and Color3.fromRGB(255, 105, 105)
			or Color3.fromRGB(255, 220, 130)
	else
		text = ("SYNC LEVERS   %d / %d"):format(leverActive, leverTotal)
		colour = Color3.fromRGB(245, 245, 245)
	end

	-- This runs every RenderStepped. setObjectiveText re-enters the row layout
	-- only when the new copy MEASURES differently, so a ticking second costs one
	-- text measurement and no relayout, while the latch arming -- which is what
	-- turns a one-line row into a two-line one -- does re-place the stack. A row
	-- APPEARING is the one case the helper deliberately leaves to its caller,
	-- because a hidden row is not in the stack at all.
	local appearing = not leverLabel.Visible
	setObjectiveText(leverLabel, text, colour)
	if appearing then
		leverLabel.Visible = true
		applyPuzzleLayout()
	end
	leverLatchDone = leverLatchMode
end

RunService.RenderStepped:Connect(refreshLever)

local function progressMeter(current, total)
	current = math.max(0, math.floor(tonumber(current) or 0))
	total = math.max(1, math.floor(tonumber(total) or 1))
	return "[" .. string.rep("#", math.min(current, total))
		.. string.rep("-", math.max(total - current, 0)) .. "]"
end

remote.OnClientEvent:Connect(function(ev, a, b, c, d)
	-- PuzzleManager broadcasts shared world changes, but lobby spectators must
	-- never inherit the active party's maze HUD.
	if player:GetAttribute("InRound") ~= true then
		setReceiver(false)
		showCounters(false)
		return
	end

	if ev == "begin" then
		setReceiver(false)
		-- Every copy change goes through setObjectiveText, which writes the text
		-- and only then re-measures the stack. These three run before
		-- showCounters(true), which is the pass that places the rows.
		setObjectiveText(objectiveTitle, "POWER RESTORATION", Color3.fromRGB(231, 238, 233))
		setObjectiveText(carryLabel, "FUSES CARRIED   0")
		setObjectiveText(boxesLabel, ("RESTORE FUSE BOXES   0 / %d"):format(b))
		LAYOUT.SetProgress(0, b, Color3.fromRGB(83, 204, 145))
		leverPhase = false
		showCounters(true)

	elseif ev == "carry" then
		setObjectiveText(carryLabel, "FUSES CARRIED   " .. a)

	elseif ev == "msg" then
		showMessage(a)

	elseif ev == "boxes" then
		setObjectiveText(boxesLabel, ("RESTORE FUSE BOXES   %d / %d"):format(a, b))
		LAYOUT.SetProgress(a, b, Color3.fromRGB(83, 204, 145))

	elseif ev == "levers" then
		-- "> EXIT CIRCUIT" is shorter than "> POWER RESTORATION", so this shrinks
		-- the title row on a narrow column; it is written before refreshLever so
		-- the pass that lever row triggers measures the title it will hold.
		setObjectiveText(objectiveTitle, "EXIT CIRCUIT", Color3.fromRGB(221, 235, 241))
		leverPhase = true
		leverActive = 0
		leverTotal = a or 0
		leverEndsAt = 0
		leverLatchMode = false
		LAYOUT.SetProgress(0, leverTotal, Color3.fromRGB(112, 190, 223))
		refreshLever()

	elseif ev == "lever" then
		leverPhase = true
		leverActive = a or 0
		leverTotal = b or leverTotal
		leverLatchMode = d == true
		leverLatchDone = false
		leverEndsAt = (not leverLatchMode and (c or 0) > 0)
			and (os.clock() + c)
			or 0
		LAYOUT.SetProgress(leverActive, leverTotal, Color3.fromRGB(112, 190, 223))
		refreshLever()

	elseif ev == "escape" then
		enterNavMode()

	elseif ev == "exit" then
		setObjectiveText(objectiveTitle, "EXIT ONLINE", Color3.fromRGB(203, 239, 216))
		LAYOUT.SetProgress(1, 1, Color3.fromRGB(98, 221, 148))
		enterNavMode()
		leverPhase = false
		-- Copy first, then the row is shown, then the stack is placed. Written the
		-- other way round the stack was measured against the timer string this
		-- replaces, and "EXIT POWERED — FIND THE DOOR" is two lines wherever the
		-- column is narrow.
		local appearing = not leverLabel.Visible
		setObjectiveText(leverLabel, "FOLLOW THE READER TO THE EXIT", Color3.fromRGB(120, 224, 161))
		leverLabel.Visible = true
		if appearing then applyPuzzleLayout() end
	end
end)

workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if not workspace:GetAttribute("RoundActive") then
		leverPhase = false
		leverActive = 0
		leverTotal = 0
		leverEndsAt = 0
		setReceiver(false)
		showCounters(false)
	end
end)

-- LEVEL2_EXIT_TRANSITION_20260828 / C1_OBJECTIVES_LOWER_RIGHT_20260829.
-- Placement is ONE row: the objectives column (toggle at the corner, panel
-- above it, transient message above that) owns the bottom-right, and the
-- exit-energy detector owns the space to its LEFT. The two are never allowed
-- within LAYOUT.ColumnGap of each other -- the rule the shipped 705x338 layout
-- broke, where a bottom-right panel and a bottom-left detector simply were not
-- far enough apart on a 705px screen and overlapped by 55px.
--
-- DESKTOP reflow, ordered; the first step that clears wins and the later steps
-- are skipped, so a wide screen keeps the authored composition unchanged:
--   1. authored:       detector at x = 132, 310 wide.
--   2. slide left:     detector to SafeLeft (12).
--   3. narrow column:  objectives down to ObjectivesMinWidth (220) at the least.
--   4. narrow detector: down to DetectorMinWidth (240) at the least.
--   5. stack:          only if 1-4 all fail (a desktop viewport under ~506px
--                      wide). The DETECTOR lifts above the objectives column;
--                      the objectives column never leaves the corner, because
--                      staying in that corner is the whole point of C1.
-- Worked examples a regression test can assert:
--   705x338   -> step 2 wins. detector x 12..322, objectives x 387..687.
--   1920x1080 -> step 1 wins. detector x 132..442, objectives x 1602..1902.
--
-- TOUCH inverts the anchor and keeps the same separation rule. The column goes
-- to the UPPER right through UIDevice.TopRightPanel (panel, then toggle, then
-- the transient message, reading downward from the anchor), and the detector
-- takes the best rectangle that is both movement-safe and LAYOUT.ColumnGap
-- clear of that column -- the top band where the band can hold it, otherwise
-- Layout().ModalArea. Neither of those two things is a fixed corner any more,
-- so both are worked out below rather than stated here.
function applyPuzzleLayout()
	local layout = UIDevice.Layout()
	-- WHICH COMPOSITION, decided before the first measurement rather than after
	-- it. The toggle's band and the message row are part of the measured stack on
	-- touch and are not in it at all on desktop, so a stack measured before this
	-- is a stack measured for the other form factor.
	objectiveToggleInPanel = layout.IsTouch
	refreshToggleCaption()

	if not layout.IsTouch then
		local margin = LAYOUT.Margin
		objectivePanelWidth = LAYOUT.ObjectivesWidth
		local detectorLeft = LAYOUT.DetectorLeft
		local detectorWidth = LAYOUT.DetectorWidth
		local function objectivesLeft()
			return layout.Width - margin - objectivePanelWidth
		end
		local function clears()
			return detectorLeft + detectorWidth + LAYOUT.ColumnGap <= objectivesLeft()
		end
		if not clears() then detectorLeft = LAYOUT.SafeLeft end
		if not clears() then
			objectivePanelWidth = math.max(LAYOUT.ObjectivesMinWidth,
				layout.Width - margin - (detectorLeft + detectorWidth + LAYOUT.ColumnGap))
		end
		if not clears() then
			detectorWidth = math.max(LAYOUT.DetectorMinWidth,
				objectivesLeft() - LAYOUT.ColumnGap - detectorLeft)
		end
		local stacked = not clears()

		objectivesToggle.AnchorPoint = Vector2.new(1, 1)
		objectivesToggle.Size = UDim2.fromOffset(LAYOUT.ToggleWidth, LAYOUT.ToggleHeight)
		objectivesToggle.Position = UDim2.new(1, -margin, 1, -margin)

		-- Unconstrained on desktop: the rows always get their natural tier, so a
		-- four-row panel is exactly the authored 300x112.
		local panelBottom = margin + LAYOUT.ToggleHeight + LAYOUT.ToggleGap
		local panelHeight = layoutObjectiveRows(nil)
		objectivePanel.AnchorPoint = Vector2.new(1, 1)
		objectivePanel.Position = UDim2.new(1, -margin, 1, -panelBottom)

		-- The authored desktop strip: a fixed 22px box of its own, above the panel,
		-- outside it, one line and unwrapped. Restated in full every pass because
		-- the touch branch hands the same label to the row walk, which owns its
		-- parent, size, face and wrapping while it is a row.
		local messageBottom = panelBottom + panelHeight + LAYOUT.MessageGap
		msgLabel.Parent = gui
		msgLabel.TextWrapped = false
		msgLabel.TextYAlignment = Enum.TextYAlignment.Center
		msgLabel.TextSize = LAYOUT.MessageTextSize
		msgLabel.AnchorPoint = Vector2.new(1, 1)
		msgLabel.Size = UDim2.fromOffset(objectivePanelWidth, LAYOUT.MessageHeight)
		msgLabel.Position = UDim2.new(1, -margin, 1, -messageBottom)

		local detectorBottom = LAYOUT.DetectorMargin
		if stacked then
			-- Step 5. Clear the whole COLUMN, message row included -- clearing only
			-- the panel would put the detector's top-right corner through the
			-- transient message, which is exactly the class of miss that produced
			-- C1 in the first place.
			detectorBottom = math.min(
				messageBottom + LAYOUT.MessageHeight + LAYOUT.ColumnGap,
				math.max(LAYOUT.DetectorMargin,
					layout.Height - LAYOUT.DetectorHeight - LAYOUT.SafeLeft))
		end
		receiverHeight = LAYOUT.DetectorHeight
		receiverWidth = detectorWidth
		receiver.AnchorPoint = Vector2.new(0, 1)
		receiver.Size = UDim2.fromOffset(detectorWidth, receiverHeight)
		receiver.Position = UDim2.new(0, detectorLeft, 1, -detectorBottom)
		layoutReceiver()
		return
	end

	-- C_OBJECTIVES_UPPER_RIGHT_20260830 -- WHAT SHIPPED BROKEN.
	-- On a landscape handheld this column sat in the CORRIDOR between the two
	-- movement zones and stacked UP from `layout.Height - 12` -- i.e. bottom
	-- centre, in the middle of the screen between the player's thumbs -- and in
	-- portrait it stacked up from the bottom of the top band. Both were chosen
	-- for being clear of the movement zones, which they were; neither was the
	-- upper right, and neither agreed with Level 2 or Level 3, each of which had
	-- its own different answer.
	--
	-- One anchor now, shared by all three levels: UIDevice.TopRightPanel. It
	-- starts at the top of the TRUE safe area (past the topbar and past a
	-- landscape sensor housing), right-aligns to the highest movement-safe right
	-- edge -- the screen's own for a short panel, the control column's for a
	-- tall one -- and hands back the height that actually fits.
	--
	-- The stack ORDER inverts with the anchor, deliberately: pinned to the
	-- bottom the toggle is the corner element and the panel hangs above it;
	-- pinned to the top the panel leads and the toggle rides INSIDE it, in the
	-- top-right corner nearest the anchor, with the transient message the last
	-- row of the same stack. Either way the column reads outward from the anchor
	-- rather than into the screen. The rectangles are stated at
	-- C_L1_TOGGLE_AND_MESSAGE_OWN_THEIR_RECTANGLES_20260831.
	local band = layout.TopBand
	-- C_L1_COLUMN_KEEPS_THE_SAFE_EDGE_20260830.
	--
	-- TopRightPanel offers two right edges -- the screen's own safe edge, for a
	-- column that finishes above the control cluster, and the cluster's left
	-- edge for one that does not -- and it picks between them BY AREA. So what
	-- this file asks for decides which edge it gets, and asking for the authored
	-- four-row composition unconditionally is what pushed this column toward
	-- screen centre.
	--
	-- Two changes. The ask is now what the CURRENTLY VISIBLE rows measure, not a
	-- fixed 112px four-row figure: a two-row round asks for two rows and keeps
	-- the screen edge on devices where four would not have. And when the answer
	-- did not use the screen edge, the edge is asked again for what it can
	-- actually hold. The reply's own UsesScreenEdge decides -- never an
	-- assumption here about which zone bound the edge, because the estimate
	-- below reads Zones.Controls alone and the jump button binds first on some
	-- devices.
	--
	-- A short screen-edge column is only worth taking if the whole COMPOSITION
	-- still fits inside it, and `least` is what asks that: the compact stack with
	-- the toggle's band already in it. The toggle is a TAP TARGET, and a column
	-- too short for it puts it down on the movement cluster it was supposed to
	-- stay above. Measured on the landscape handheld: the registered cluster
	-- (JUMP, RUN and SNEAK at 64px with 14px gaps, 22px off the safe bottom) is
	-- 242px of a 360px safe area, which leaves ~94px above it at the screen's
	-- edge. The compact four-row composition measures ~80px, so that device now
	-- KEEPS the screen's own safe edge; it stepped left of the cluster only while
	-- the toggle and the message were charging the column 78px of their own that
	-- they no longer charge it.
	-- NOTHING IS ADDED ON TOP OF THE STACK. The toggle's band and the message row
	-- are inside the panel, so what the walk measures is the whole composition
	-- and the column IS the panel -- there is no separate 52px of toggle and 26px
	-- of message strip for the ask to remember, and therefore no way for the ask
	-- and the drawing to disagree about them. On the landscape handheld above,
	-- the compact four-row stack is the same ~80px it was before the toggle moved
	-- in, because the toggle shares the title's band instead of taking one.
	local probeWidth = math.min(LAYOUT.ObjectivesWidth, math.max(24, layout.Safe.Width - 16))
	local wanted = totalHeight(false, probeWidth)
	local least = totalHeight(true, probeWidth)
	local column = UIDevice.TopRightPanel(LAYOUT.ObjectivesWidth, wanted)
	if not column.UsesScreenEdge then
		local edgeRoom = math.floor((layout.Zones.Controls.Top - 8) - (layout.Safe.Top + 8))
		for _, ask in ipairs({edgeRoom, least}) do
			if ask >= least and ask < wanted then
				local candidate = UIDevice.TopRightPanel(LAYOUT.ObjectivesWidth, ask)
				if candidate.UsesScreenEdge and candidate.Height >= least then
					column = candidate
					break
				end
			end
		end
	end
	-- Take the width the anchor could actually give, NOT a readability floor
	-- forced on top of it. ObjectivesMinWidth is a desktop reflow bound; applied
	-- here it would push the panel's left edge back across the very movement
	-- zone TopRightPanel narrowed the column to clear. This is the same ~157px
	-- the corridor placement produced on the smallest landscape phone.
	objectivePanelWidth = math.max(1, math.floor(column.Width))
	local columnRight = math.floor(column.Right)
	local columnTop = math.floor(column.Top)
	local columnBottom = math.floor(column.Bottom)

	-- C_L1_COLUMN_KEEPS_THE_SAFE_EDGE_20260831 -- why the toggle is inside the
	-- panel at all, kept here with the numbers that forced it.
	--
	-- The column used to be panel + 8 + a 44px toggle + 4 + a reserved 22px
	-- message strip = 158px for a four-row panel. Measured in a live round on a
	-- 956x440 iPhone the registered cluster (JUMP + RUN + SNEAK, 64px each with
	-- 14px gaps, 22px off the safe bottom) is 242px inside a 360px safe area, so
	-- the space above it at the screen's OWN safe right edge is about 94px. 158
	-- does not fit in 94, and that is the entire reason this column used to step
	-- left of the control cluster and sit a sixth of the screen from the corner.
	--
	-- So the toggle moved inside the panel -- but INTO ITS OWN RECTANGLE beside
	-- the title, not on top of one. It shares the band the title already needed
	-- rather than adding 52px to the column, and the message is a row of the
	-- stack that exists only while it is up rather than a strip held open for the
	-- other 99% of the round. A four-row compact stack is ~80px either way, which
	-- is what fits the 94 and keeps the corner. Nothing here overlays anything:
	-- see C_L1_TOGGLE_AND_MESSAGE_OWN_THEIR_RECTANGLES_20260831 for the exact
	-- rectangles this branch guarantees. Desktop keeps the authored lower-right
	-- stack; this branch is touch-only.
	--
	-- The message has to be a ROW before the stack is measured, so its parent and
	-- its row settings are written here, ahead of layoutObjectiveRows.
	msgLabel.Parent = objectivePanel
	msgLabel.AnchorPoint = Vector2.new(0, 0)
	msgLabel.TextWrapped = true
	msgLabel.TextYAlignment = Enum.TextYAlignment.Top

	local available = columnBottom - columnTop
	local panelHeight = layoutObjectiveRows(available)

	local panelTop = columnTop
	local columnLeft = columnRight - objectivePanelWidth
	-- The toggle's reserved sub-rectangle of the panel: a TouchToggleSize square
	-- in the top-right corner of the panel's content box, padX in from the panel's
	-- right edge. Keep the control on the original touch inset so it remains clear
	-- of device chrome. The row walker still reserves the larger title band
	-- introduced by the field-brief eyebrow, which leaves the actual control extra
	-- breathing room instead of letting it collide with copy.
	local padX = objectiveCompact and 10 or 13
	local padTop = objectiveCompact and 4 or 6

	objectivesToggle.AnchorPoint = Vector2.new(1, 0)
	objectivesToggle.Size = UDim2.fromOffset(LAYOUT.TouchToggleSize, LAYOUT.TouchToggleSize)
	-- Every figure below is ABSOLUTE, in the one space UIDevice.Layout() speaks.
	-- UIDevice.LocalPosition converts it into this gui's offsets on BOTH axes --
	-- which matters here twice over, because this ScreenGui sets IgnoreGuiInset
	-- (so its origin is the display top, not the topbar's bottom) and because a
	-- device with a horizontal safe inset moves the X origin too.
	objectivesToggle.Position = UIDevice.LocalPosition(gui,
		columnRight - padX, panelTop + padTop)

	objectivePanel.AnchorPoint = Vector2.new(1, 0)
	objectivePanel.Position = UIDevice.LocalPosition(gui, columnRight, panelTop)

	-- C_L1_DETECTOR_FITS_20260830 -- WHAT SHIPPED BROKEN.
	--
	-- The card's height was  max(DetectorMinHeight, min(DetectorHeight,
	-- band.Height)), and that max() is the defect. Where the top band is a thin
	-- strip -- ~31px on the landscape handheld, because the registered control
	-- cluster closes in from the right and the thumbstick's activation edge from
	-- below -- a 44px card was drawn from band.Top straight THROUGH band.Bottom,
	-- which is thumbstick.Top - 10, and into the movement region. The forced
	-- height also gave a two-line readout 15px of body, so the card overflowed
	-- twice over. The 150px width minimum was forced the same way, on the same
	-- line of reasoning, and could push the card under the objectives column.
	--
	-- A minimum is a TEST, never a floor. A rectangle either holds a legible
	-- card -- DetectorTouchMinWidth wide, and as tall as the copy currently in
	-- it MEASURES -- or the card is not put there. Ordered candidates, first
	-- that holds one wins:
	--   1, 2. the top band, beside the objectives column, then below it.
	--   3, 4. Layout().ModalArea, the largest rectangle UIDevice knows to be
	--         clear of EVERY movement zone, beside the column then below it.
	--         This is where the card goes when the band is a strip: on the
	--         landscape handheld it is the full-height space between the
	--         thumbstick's activation edge and the control cluster.
	-- If none holds one, the largest is taken and the card is SHORTENED to it.
	-- The card is never grown past the rectangle it was placed in, which is what
	-- makes "the detector cannot reach the thumbstick" a property of the
	-- arithmetic rather than a number someone has to keep in sync.
	-- The whole column is the PANEL now -- the toggle and the message are inside
	-- it -- so the rectangle the detector has to stay clear of is the panel's,
	-- and there is no separate strip below it that a clearance could miss.
	local columnBottomEdge = panelTop + panelHeight
	local columnRect = {Left = columnLeft, Top = panelTop,
		Right = columnRight, Bottom = columnBottomEdge}

	local candidates = {}
	for _, area in ipairs({band, layout.ModalArea}) do
		if area.Left < columnRect.Right and area.Right > columnRect.Left
			and area.Top < columnRect.Bottom and area.Bottom > columnRect.Top then
			-- Beside the column first, then below it, LAYOUT.ColumnGap clear on
			-- whichever axis is used. That separation is the C1 rule, unchanged.
			table.insert(candidates, {Left = area.Left, Top = area.Top,
				Right = math.min(area.Right, columnRect.Left - LAYOUT.ColumnGap),
				Bottom = area.Bottom})
			table.insert(candidates, {Left = area.Left, Right = area.Right,
				Top = math.max(area.Top, columnRect.Bottom + LAYOUT.ColumnGap),
				Bottom = area.Bottom})
		else
			table.insert(candidates, {Left = area.Left, Top = area.Top,
				Right = area.Right, Bottom = area.Bottom})
		end
	end

	local chosen
	for _, rect in ipairs(candidates) do
		local placed = {
			Left = math.floor(rect.Left), Top = math.floor(rect.Top),
			Width = math.floor(math.min(LAYOUT.DetectorWidth, rect.Right - rect.Left)),
			Height = math.floor(math.min(LAYOUT.DetectorHeight, rect.Bottom - rect.Top)),
		}
		if placed.Width >= LAYOUT.DetectorTouchMinWidth
			and placed.Height >= math.max(LAYOUT.DetectorMinHeight,
				detectorMinimumHeight(placed.Width)) then
			chosen = placed
			break
		end
		if placed.Width > 0 and placed.Height > 0
			and (chosen == nil
				or placed.Width * placed.Height > chosen.Width * chosen.Height) then
			chosen = placed
		end
	end
	if chosen == nil then
		-- Every rectangle on this device was degenerate. The card still goes in
		-- the band, at whatever the band has, rather than at a size the band
		-- cannot contain.
		chosen = {Left = math.floor(band.Left), Top = math.floor(band.Top),
			Width = math.max(1, math.floor(math.min(LAYOUT.DetectorWidth, band.Width))),
			Height = math.max(1, math.floor(math.min(LAYOUT.DetectorHeight, band.Height)))}
	end

	-- Checked, not believed. The band and ModalArea are movement-safe wherever
	-- they were chosen from their candidates, and every rectangle above is a
	-- sub-rectangle of one of them -- but ModalArea has an unconditional last
	-- resort of its own, taken when none of ITS candidates cleared the zones, and
	-- that one is not safe. So the answer is tested, and a card that still meets
	-- a zone gives up whichever axis keeps more of it.
	local hit = UIDevice.OverlapsMovementZone(chosen.Left, chosen.Top,
		chosen.Left + chosen.Width, chosen.Top + chosen.Height)
	if hit then
		local zone = layout.Zones[hit]
		local shorter = math.clamp(math.floor(zone.Top) - chosen.Top, 0, chosen.Height)
		local narrower = math.clamp(math.floor(zone.Left) - chosen.Left, 0, chosen.Width)
		if chosen.Width * shorter >= narrower * chosen.Height then
			chosen.Height = math.max(1, shorter)
		else
			chosen.Width = math.max(1, narrower)
		end
	end

	receiverWidth = chosen.Width
	receiverHeight = chosen.Height
	receiver.AnchorPoint = Vector2.new(0, 0)
	receiver.Size = UDim2.fromOffset(receiverWidth, receiverHeight)
	receiver.Position = UIDevice.LocalPosition(gui, chosen.Left, chosen.Top)
	layoutReceiver()
end

applyPuzzleLayout()
UIDevice.Changed:Connect(applyPuzzleLayout)
