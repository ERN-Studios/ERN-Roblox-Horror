--!strict
-- UIRegression - deterministic HUD checks, run from a live client.
--
-- Three properties are asserted, at whatever viewport the client is currently
-- rendering. Drive it from the Studio Device Simulator (set the device BEFORE
-- entering Play; the simulator's setters error in PlayServer) and call
-- UIRegression.Assert() once per device in the matrix.
--
--   1. ONSCREEN   - every visible top-level HUD rectangle lies inside the
--                   viewport.
--   2. NO OVERLAP - visible top-level HUD rectangles do not overlap each other,
--                   and on a touch form factor none of them overlaps the
--                   movement-control reserved zones.
--   3. NO KEYS    - on a touch form factor, no visible string names a
--                   keyboard-only binding.
--
-- "Top-level HUD rectangle" means a direct child of a ScreenGui. That is the
-- honest unit: children overlapping their own parent is normal composition,
-- two HUD panels overlapping each other is the bug.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))

local UIRegression = {}

-- Deliberate full-screen overlays. These are MEANT to cover the HUD, so they
-- are excluded from the pairwise overlap test (they are still checked for
-- keyboard bindings and for staying onscreen).
-- Roblox's own touch controls. They ARE the movement zone, so scanning them
-- against it is circular, and TouchControlFrame is a full-screen container that
-- every HUD element trivially "overlaps".
local ENGINE_GUIS = {
	TouchGui = true,
	ControlGui = true,
}

-- This game's own movement cluster. These are movement controls, so they are
-- exempt from the movement-zone test -- but they are still required to stay
-- onscreen and not to overlap each other or any other HUD panel.
local MOVEMENT_CONTROLS = {
	TouchRunHold = true,
	TouchJump = true,
	TouchPOV = true,
	TouchDropGlowstick = true,
	FlashlightPower = true,
}

local FULLSCREEN_OVERLAYS = {
	LoadingCover = true,
	queueShade = true,
	QueueShade = true,
	endFrame = true,
	endFlash = true,
	Shade = true,
	Backdrop = true,
	BottomBar = true,
	-- Deliberate framing decoration drawn while the player is under a table.
	-- It is MEANT to cover the screen edges; that is the hiding effect.
	UnderTableShade = true,
	TableEdgeTop = true,
	TableEdgeBottom = true,
	-- Modal panels own the screen while they are open, and the movement cluster
	-- hides underneath them.
	Terminal = true,
	ReentryPanel = true,
	-- The result screen's accent wash. Full-bleed by design, and named after the
	-- instance rather than after the variable that used to be listed here.
	SignalFlash = true,
}

-- Panels whose INTERNAL composition is asserted, not only their outer rectangle.
-- Top-level testing is the right default -- a child overlapping its own parent is
-- ordinary composition -- but inside these panels the children are SIBLINGS
-- sharing one fixed box, and two of them landing on each other is exactly the
-- defect this harness exists to catch. It is also the defect that shipped: the
-- briefing subtitle spanned the whole panel below its speaker line while the
-- MUTE and STOP readouts sat in the same corner, and nothing here noticed.
local INTERNAL_PANELS = {
	CommandSubtitles = true,
	RoundEnding = true,
	ObjectivesPanel = true,
}

-- Patterns that name a key a phone or tablet does not have. Matched against
-- every visible string; a hit on a touch form factor is a failure.
local KEYBOARD_PATTERNS = {
	"%[%u%]",            -- [M] [N] [R] [Y] [H] [B] [E] [Q] [V]
	"%f[%w]WASD%f[%W]",
	"Left Ctrl",
	"LeftControl",
	"%f[%w]Q%s*/%s*E%f[%W]",
	"%f[%w]SHIFT%f[%W]",
	"%f[%w]SPACEBAR%f[%W]",
	"PHONE:%s*%u%f[%W]",
	"//%s+%u%f[%W]",     -- the "ACTION  //  E" idiom used by dev rows
}

local function isOverlay(object: Instance, viewport: Vector2): boolean
	if FULLSCREEN_OVERLAYS[object.Name] then return true end
	if object:IsA("GuiObject") then
		local size = object.AbsoluteSize
		if size.X >= viewport.X * .92 and size.Y >= viewport.Y * .92 then
			return true
		end
	end
	return false
end

local function isFullyFadedLeaf(object: GuiObject): boolean
	if object.BackgroundTransparency < 1 then return false end
	if (object:IsA("TextLabel") or object:IsA("TextButton"))
		and (object :: any).TextTransparency < 1 then return false end
	if (object:IsA("ImageLabel") or object:IsA("ImageButton"))
		and (object :: any).ImageTransparency < 1 then return false end
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if stroke and stroke.Transparency < 1 then return false end
	return true
end

-- Visible = true but every channel at transparency 1 means the element has been
-- FADED OUT, not shown. The Level 2 alert panel lives that way between
-- announcements: permanently Visible, fully transparent when idle. Counting it
-- as a rectangle then would report an overlap nobody can see.
local function isFullyFaded(object: GuiObject): boolean
	if object.BackgroundTransparency < 1 then return false end
	if object:IsA("TextLabel") or object:IsA("TextButton") then
		if (object :: any).TextTransparency < 1 then return false end
	end
	if object:IsA("ImageLabel") or object:IsA("ImageButton") then
		if (object :: any).ImageTransparency < 1 then return false end
	end
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if stroke and stroke.Transparency < 1 then return false end
	-- A container is only faded if everything it draws is faded too.
	for _, child in ipairs(object:GetDescendants()) do
		if child:IsA("GuiObject") and child.Visible and not isFullyFadedLeaf(child) then
			return false
		end
	end
	return true
end

local function visibleChain(object: Instance): boolean
	local node: Instance? = object
	while node and not node:IsA("PlayerGui") do
		if node:IsA("ScreenGui") then
			if not (node :: ScreenGui).Enabled then return false end
		elseif node:IsA("GuiObject") then
			if not (node :: GuiObject).Visible then return false end
		end
		node = node.Parent
	end
	return true
end

-- Collect every visible top-level HUD rectangle, plus every visible string.
function UIRegression.Scan(): {[string]: any}
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local layout = UIDevice.Layout()
	local viewport = layout.Viewport

	-- A frame with a fully transparent background and no stroke is a LAYOUT
	-- GROUP, not something the player can see. Measuring it as a rectangle makes
	-- every full-bleed container "overlap" the whole HUD, which says nothing.
	-- Descend through it and measure what actually renders.
	-- A FULL-BLEED transparent frame is a layout group: it exists only to hold
	-- the real panel somewhere inside itself, and measuring it as a rectangle
	-- makes it "overlap" the entire HUD while saying nothing. Descend into it.
	--
	-- A SMALL transparent frame is a composed widget -- the flashlight torch is a
	-- transparent box holding a body and three rays -- and its parts are meant to
	-- overlap each other. Those stay one rectangle.
	local function isLayoutGroup(object: GuiObject): boolean
		if object:IsA("TextButton") or object:IsA("ImageButton") then return false end
		if object:IsA("TextLabel") and (object :: TextLabel).TextTransparency < 1 then return false end
		if object:IsA("ImageLabel") and (object :: ImageLabel).ImageTransparency < 1 then return false end
		if object.BackgroundTransparency < 1 then return false end
		local stroke = object:FindFirstChildOfClass("UIStroke")
		if stroke and stroke.Transparency < 1 then return false end
		local size = object.AbsoluteSize
		return size.X >= viewport.X * .7 and size.Y >= viewport.Y * .7
	end

	local rects, texts = {}, {}
	for _, screenGui in ipairs(playerGui:GetChildren()) do
		if screenGui:IsA("ScreenGui") and screenGui.Enabled
			and not ENGINE_GUIS[screenGui.Name] then
			-- An IgnoreGuiInset ScreenGui legitimately starts above y = 0.
			local topBound = (screenGui :: ScreenGui).IgnoreGuiInset and -layout.Inset.Y or 0
			local function collect(container: Instance, prefix: string, depth: number,
				inheritedControl: boolean)
				for _, child in ipairs(container:GetChildren()) do
					if child:IsA("GuiObject") and child.Visible and visibleChain(child)
						and not isFullyFaded(child) then
						local position = child.AbsolutePosition
						local size = child.AbsoluteSize
						local isControl = inheritedControl or MOVEMENT_CONTROLS[child.Name] == true
						if isLayoutGroup(child) and depth < 2 then
							collect(child, prefix .. "." .. child.Name, depth + 1, isControl)
						elseif size.X > 1 and size.Y > 1 then
							table.insert(rects, {
								Path = prefix .. "." .. child.Name,
								Name = child.Name,
								Gui = screenGui.Name,
								TopBound = topBound,
								Overlay = isOverlay(child, viewport),
								MovementControl = isControl,
								Interactive = child:IsA("TextButton") or child:IsA("ImageButton"),
								Active = (child:IsA("TextButton") or child:IsA("ImageButton"))
									and (child :: any).Active or false,
								TextBounds = (child:IsA("TextLabel") or child:IsA("TextButton"))
									and (child :: any).TextBounds or nil,
								Left = position.X,
								Top = position.Y,
								Right = position.X + size.X,
								Bottom = position.Y + size.Y,
							})
						end
					end
				end
			end
			collect(screenGui, screenGui.Name, 0, false)
			for _, descendant in ipairs(screenGui:GetDescendants()) do
				if (descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox"))
					and (descendant :: any).Visible and visibleChain(descendant) then
					local text = (descendant :: any).Text
					if type(text) == "string" and text ~= "" then
						table.insert(texts, {
							Path = screenGui.Name .. "." .. descendant.Name,
							Text = text,
						})
					end
				end
			end
		end
	end

	return {
		Viewport = viewport,
		IsTouch = layout.IsTouch,
		Class = layout.Class,
		Portrait = layout.Portrait,
		Zones = layout.Zones,
		Rects = rects,
		Texts = texts,
	}
end

-- Flatten a panel to the rectangles it actually DRAWS. Transparent containers
-- (the BriefingControls row, any UIListLayout wrapper) are descended through, so
-- what comes back is MUTE and STOP themselves rather than the invisible box that
-- holds them -- which is the level the overlap question is really asked at.
local function collectDrawnChildren(container: Instance, prefix: string,
	viewport: Vector2, out: {any})
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible and not isFullyFaded(child) then
			local path = prefix .. "." .. child.Name
			local size = child.AbsoluteSize
			local position = child.AbsolutePosition
			-- A ScrollingFrame is one rectangle, never a container to descend
			-- into: its contents are MEANT to run past its bounds, which is the
			-- whole point of scrolling, and measuring them would report the
			-- scroll extent as a layout escape.
			local drawsItself = child:IsA("TextButton") or child:IsA("ImageButton")
				or child:IsA("ScrollingFrame")
				or child.BackgroundTransparency < 1
				or ((child:IsA("TextLabel") or child:IsA("TextBox"))
					and (child :: any).TextTransparency < 1)
				or (child:IsA("ImageLabel") and (child :: any).ImageTransparency < 1)
			local stroke = child:FindFirstChildOfClass("UIStroke")
			if stroke and stroke.Transparency < 1 then drawsItself = true end
			if not drawsItself then
				collectDrawnChildren(child, path, viewport, out)
			elseif size.X > 1 and size.Y > 1 and not isOverlay(child, viewport) then
				table.insert(out, {
					Path = path,
					Name = child.Name,
					Interactive = child:IsA("TextButton") or child:IsA("ImageButton"),
					Active = (child:IsA("TextButton") or child:IsA("ImageButton"))
						and (child :: any).Active or false,
					TextBounds = (child:IsA("TextLabel") or child:IsA("TextButton"))
						and (child :: any).TextBounds or nil,
					Left = position.X,
					Top = position.Y,
					Right = position.X + size.X,
					Bottom = position.Y + size.Y,
				})
			end
		end
	end
end

-- Every measured child rectangle inside the panels named above, for the panels
-- that are actually on screen right now.
function UIRegression.Children(): {any}
	local player = Players.LocalPlayer
	local gui = player:WaitForChild("PlayerGui")
	local viewport = UIDevice.Layout().Viewport
	local groups = {}
	for _, screenGui in ipairs(gui:GetChildren()) do
		if screenGui:IsA("ScreenGui") and screenGui.Enabled
			and not ENGINE_GUIS[screenGui.Name] then
			for _, descendant in ipairs(screenGui:GetDescendants()) do
				if descendant:IsA("GuiObject") and INTERNAL_PANELS[descendant.Name]
					and descendant.Visible and visibleChain(descendant) then
					local children = {}
					collectDrawnChildren(descendant, screenGui.Name .. "." .. descendant.Name,
						viewport, children)
					local position = descendant.AbsolutePosition
					local size = descendant.AbsoluteSize
					table.insert(groups, {
						Path = screenGui.Name .. "." .. descendant.Name,
						Left = position.X,
						Top = position.Y,
						Right = position.X + size.X,
						Bottom = position.Y + size.Y,
						Children = children,
					})
				end
			end
		end
	end
	return groups
end

local function rectsOverlap(a: any, b: any): boolean
	-- A one-pixel shared edge is abutment, not overlap.
	return a.Left < b.Right - 1 and a.Right > b.Left + 1
		and a.Top < b.Bottom - 1 and a.Bottom > b.Top + 1
end

function UIRegression.Check(): {[string]: any}
	local scan = UIRegression.Scan()
	local viewport = scan.Viewport
	local offscreen, overlaps, zoneHits, bindings = {}, {}, {}, {}
	local internal = {}
	local groups = UIRegression.Children()

	for _, rect in ipairs(scan.Rects) do
		if rect.Left < -1 or rect.Top < (rect.TopBound or 0) - 1
			or rect.Right > viewport.X + 1 or rect.Bottom > viewport.Y + 1 then
			table.insert(offscreen, string.format(
				"%s at (%.0f,%.0f)-(%.0f,%.0f) in a %.0fx%.0f viewport",
				rect.Path, rect.Left, rect.Top, rect.Right, rect.Bottom, viewport.X, viewport.Y))
		end
	end

	for indexA = 1, #scan.Rects do
		local a = scan.Rects[indexA]
		if not a.Overlay then
			for indexB = indexA + 1, #scan.Rects do
				local b = scan.Rects[indexB]
				if not b.Overlay and rectsOverlap(a, b) then
					table.insert(overlaps, string.format("%s overlaps %s", a.Path, b.Path))
				end
			end
			if scan.IsTouch and not a.MovementControl then
				local zone = UIDevice.OverlapsMovementZone(a.Left, a.Top, a.Right, a.Bottom)
				if zone then
					table.insert(zoneHits, string.format(
						"%s (%.0f,%.0f)-(%.0f,%.0f) sits in the %s movement zone",
						a.Path, a.Left, a.Top, a.Right, a.Bottom, zone))
				end
			end
		end
	end

	if UIDevice.SuppressesKeyboardGlyphs() then
		for _, entry in ipairs(scan.Texts) do
			for _, pattern in ipairs(KEYBOARD_PATTERNS) do
				if entry.Text:match(pattern) then
					table.insert(bindings, string.format(
						"%s shows a keyboard binding: %q", entry.Path, entry.Text))
					break
				end
			end
		end
	end

	for _, group in ipairs(groups) do
		for indexA = 1, #group.Children do
			local a = group.Children[indexA]
			for indexB = indexA + 1, #group.Children do
				local b = group.Children[indexB]
				if rectsOverlap(a, b) then
					table.insert(internal, string.format(
						"%s (%.0f,%.0f)-(%.0f,%.0f) overlaps %s (%.0f,%.0f)-(%.0f,%.0f)",
						a.Path, a.Left, a.Top, a.Right, a.Bottom,
						b.Path, b.Left, b.Top, b.Right, b.Bottom))
				end
			end
			-- A child that has escaped its own panel is the same defect seen from
			-- the other side: the layout reserved less space than it used.
			if a.Left < group.Left - 1 or a.Right > group.Right + 1
				or a.Top < group.Top - 1 or a.Bottom > group.Bottom + 1 then
				table.insert(internal, string.format(
					"%s (%.0f,%.0f)-(%.0f,%.0f) is outside %s (%.0f,%.0f)-(%.0f,%.0f)",
					a.Path, a.Left, a.Top, a.Right, a.Bottom,
					group.Path, group.Left, group.Top, group.Right, group.Bottom))
			end
		end
	end

	return {
		Viewport = viewport,
		Class = scan.Class,
		Portrait = scan.Portrait,
		IsTouch = scan.IsTouch,
		RectCount = #scan.Rects,
		TextCount = #scan.Texts,
		Offscreen = offscreen,
		Overlaps = overlaps,
		MovementZoneHits = zoneHits,
		KeyboardBindings = bindings,
		InternalOverlaps = internal,
		Rects = scan.Rects,
		Groups = groups,
		Passed = #offscreen == 0 and #overlaps == 0
			and #zoneHits == 0 and #bindings == 0 and #internal == 0,
	}
end

function UIRegression.Assert()
	local result = UIRegression.Check()
	local problems = {}
	for _, list in ipairs({result.Offscreen, result.Overlaps,
		result.MovementZoneHits, result.KeyboardBindings, result.InternalOverlaps}) do
		for _, problem in ipairs(list) do table.insert(problems, problem) end
	end
	assert(#problems == 0, string.format(
		"UI regression failed at %.0fx%.0f (%s):\n  %s",
		result.Viewport.X, result.Viewport.Y, result.Class,
		table.concat(problems, "\n  ")))
	return result
end

-- One-line summary suitable for a console log or an MCP probe return.
function UIRegression.Summary(): string
	local result = UIRegression.Check()
	local lines = {string.format("%.0fx%.0f  class=%s  touch=%s  rects=%d  texts=%d  %s",
		result.Viewport.X, result.Viewport.Y, result.Class, tostring(result.IsTouch),
		result.RectCount, result.TextCount, result.Passed and "PASS" or "FAIL")}
	for _, label in ipairs({"Offscreen", "Overlaps", "MovementZoneHits",
		"KeyboardBindings", "InternalOverlaps"}) do
		for _, problem in ipairs(result[label]) do
			table.insert(lines, "  " .. label .. ": " .. problem)
		end
	end
	-- The measured child rectangles are printed whether or not they passed. An
	-- assertion that only speaks up when it fails cannot be reviewed.
	for _, group in ipairs(result.Groups) do
		table.insert(lines, string.format("  %s (%.0f,%.0f)-(%.0f,%.0f)",
			group.Path, group.Left, group.Top, group.Right, group.Bottom))
		for _, child in ipairs(group.Children) do
			table.insert(lines, string.format("      %s (%.0f,%.0f)-(%.0f,%.0f)%s",
				child.Path, child.Left, child.Top, child.Right, child.Bottom,
				child.Interactive and "  [tappable]" or ""))
		end
	end
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Scenario matrix
-- ---------------------------------------------------------------------------

-- The HUD states the regression matrix has to cover. Panels are forced visible
-- directly rather than reached through gameplay: this is a LAYOUT test, so the
-- question is "where would this rectangle land", not "can the game get here".
local function playerGui(): Instance
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local OPTIONAL_GUIS = {
	"PuzzleGui", "Level2ObjectiveGui", "Level2AlertGui", "Level3ReaderGui",
	"Level3TableHideUI", "SpectateGui", "LevelOneGuideGui",
}

local function findGui(name: string): Instance?
	return playerGui():FindFirstChild(name)
end

-- `inRound` hides the lobby-only Zyntra shop button. ZyntraStore shows it with
-- `openButton.Visible = not inRound or touchDevInLevel`, so it and the in-round
-- objectives HUD can never be on screen together -- and forcing both visible
-- reports a collision between two things a player will never see at once, which
-- is a false failure rather than a finding.
local function resetScenario(inRound: boolean?)
	local player = Players.LocalPlayer
	player:SetAttribute("UIRegressionForceLevel3Reader", nil)
	player:SetAttribute("UIRegressionForceReaderHidden", nil)
	player:SetAttribute("UIRegressionForceDispatchActive", nil)
	player:SetAttribute("UIRegressionForceHiding", nil)
	-- RoundUI owns the result card state. Drive its Studio-only hide hook so a
	-- preceding win/loss scenario cannot leak into the next matrix row.
	player:SetAttribute("DevRoundEnding", "hide")
	-- End any live Command Center transmission first. It re-shows the subtitle
	-- panel on every cue, so hiding the panel and scanning 0.3s later is a race
	-- the harness loses -- and losing it reports a collision with a panel the
	-- scenario never asked for. RoundUI honours this in Studio only.
	player:SetAttribute("UIRegressionSilenceDispatch", true)
	-- RoundUI's stop hook runs in its own signal thread and, while clearing the
	-- dispatch authority, legitimately asks objective scripts to restore their
	-- ScreenGuis. Wait for that causal cleanup BEFORE disabling/hiding the test
	-- matrix; otherwise its late restore leaks the preceding scenario forward.
	task.wait(.05)
	player:SetAttribute("DevRoundEnding", nil)
	for _, name in ipairs(OPTIONAL_GUIS) do
		local screen = findGui(name)
		if screen then
			(screen :: ScreenGui).Enabled = false
			for _, child in ipairs(screen:GetChildren()) do
				if child:IsA("GuiObject") then child.Visible = false end
			end
		end
	end
	player:SetAttribute("Level3_Hiding", nil)
	player:SetAttribute("Spectating", nil)
	player:SetAttribute("ZyntraStoreOpen", nil)
	local store = findGui("ZyntraStore")
	local terminal = store and store:FindFirstChild("Terminal")
	if terminal and terminal:IsA("GuiObject") then terminal.Visible = false end
	local openButton = store and store:FindFirstChild("ZyntraOpenButton")
	if openButton and openButton:IsA("GuiObject") then
		openButton.Visible = not inRound
	end
end

local function revealGui(name: string, filter: ((Instance) -> boolean)?)
	local screen = findGui(name)
	if not screen then return end
	(screen :: ScreenGui).Enabled = true
	for _, child in ipairs(screen:GetChildren()) do
		if child:IsA("GuiObject") then
			child.Visible = filter == nil or filter(child)
		end
	end
end

local LONG_DISPATCH_CUE = "Keep moving through the flooded service halls. The water is above your knees, so listen for every heavy step and follow the green exit lights."

local function setLongDispatchCue()
	task.wait(.05)
	local guide = findGui("LevelOneGuideGui")
	local subtitle = guide and guide:FindFirstChild("Subtitle", true)
	if subtitle and subtitle:IsA("TextLabel") then subtitle.Text = LONG_DISPATCH_CUE end
end

function UIRegression.Scenarios(): {any}
	local player = Players.LocalPlayer
	return {
		{Name = "gameplay", Setup = resetScenario},
		{Name = "briefing", Requires = {
			"CommandSubtitles", "DispatchMuteButton", "DispatchStopButton",
		}, TouchTargets = {"DispatchMuteButton", "DispatchStopButton"},
			TextFitTargets = {"CommandSubtitles.Subtitle"}, Setup = function()
			resetScenario(true)
			local guide = findGui("LevelOneGuideGui")
			if guide then (guide :: ScreenGui).Enabled = true end
			player:SetAttribute("UIRegressionForceDispatchActive", true)
			setLongDispatchCue()
		end},
		{Name = "briefing-plus-level1-hud", Requires = {
			"CommandSubtitles", "DispatchMuteButton", "DispatchStopButton",
		}, TouchTargets = {"DispatchMuteButton", "DispatchStopButton"},
			Forbids = {"Level1Objectives", "ExitEnergyDetector"}, Setup = function()
			resetScenario(true)
			revealGui("PuzzleGui")
			local guide = findGui("LevelOneGuideGui")
			if guide then (guide :: ScreenGui).Enabled = true end
			player:SetAttribute("UIRegressionForceDispatchActive", true)
		end},
		{Name = "briefing-plus-level2-hud", Requires = {
			"CommandSubtitles", "DispatchMuteButton", "DispatchStopButton",
		}, TouchTargets = {"DispatchMuteButton", "DispatchStopButton"},
			Forbids = {"Level2ObjectiveGui", "Level2AlertGui"}, Setup = function()
			resetScenario(true)
			revealGui("Level2ObjectiveGui")
			revealGui("Level2AlertGui")
			local guide = findGui("LevelOneGuideGui")
			if guide then (guide :: ScreenGui).Enabled = true end
			player:SetAttribute("UIRegressionForceDispatchActive", true)
		end},
		-- The button on its own, with the panel closed. This is the state the
		-- OBJECTIVES control actually has to be reachable in, and keeping it as a
		-- separate row is what stops "panel open hides the button" from quietly
		-- removing the button from the matrix altogether.
		{Name = "objectives-button", Requires = "ObjectivesButton", Setup = function()
			resetScenario(true)
			revealGui("LevelOneGuideGui", function(child)
				return child.Name == "ObjectivesButton"
			end)
		end},
		{Name = "objectives-panel", Requires = "ObjectivesPanel", Setup = function()
			-- The objectives panel is nearly full-bleed AND Active, so it is the
			-- single most likely thing to swallow the movement controls. It was
			-- not in the original matrix, which is exactly why its touch case
			-- went unnoticed.
			resetScenario(true)
			-- On touch the panel owns the whole safe band and is Active, so RoundUI
			-- stands the button down while it is open -- they are alternatives, not
			-- companions. The matrix models that rather than forcing both visible
			-- and reporting a collision between two things a player cannot see at
			-- once; the button's own placement is covered by the row above.
			local touch = UIDevice.IsTouch()
			revealGui("LevelOneGuideGui", function(child)
				if child.Name == "ObjectivesPanel" then return true end
				return child.Name == "ObjectivesButton" and not touch
			end)
		end},
		{Name = "level1-objective-receiver", Setup = function()
			resetScenario(true); revealGui("PuzzleGui")
		end},
		{Name = "level2-alert-and-objective", Setup = function()
			resetScenario(true); revealGui("Level2AlertGui"); revealGui("Level2ObjectiveGui")
		end},
		{Name = "level3-reader-open", Requires = {"ReaderPanel", "ReaderToggle"},
			Capture = "ReaderToggle", Setup = function()
			resetScenario(true)
			player:SetAttribute("UIRegressionForceLevel3Reader", true)
			player:SetAttribute("UIRegressionForceReaderHidden", false)
			revealGui("Level3ReaderGui", function(child)
				return child.Name == "ReaderPanel" or child.Name == "ReaderToggle"
			end)
		end},
		{Name = "level3-reader-closed", Requires = {"ReaderToggle"},
			Forbids = {"ReaderPanel"}, Capture = "ReaderToggle",
			CompareWith = "level3-reader-open", Setup = function()
			resetScenario(true)
			player:SetAttribute("UIRegressionForceLevel3Reader", true)
			player:SetAttribute("UIRegressionForceReaderHidden", true)
			revealGui("Level3ReaderGui", function(child) return child.Name == "ReaderToggle" end)
		end},
		{Name = "briefing-plus-level3-reader", Requires = {
			"CommandSubtitles", "DispatchMuteButton", "DispatchStopButton",
		}, TouchTargets = {"DispatchMuteButton", "DispatchStopButton"},
			Forbids = {"ReaderPanel", "ReaderToggle"}, Setup = function()
			resetScenario(true)
			player:SetAttribute("UIRegressionForceLevel3Reader", true)
			player:SetAttribute("UIRegressionForceReaderHidden", false)
			local guide = findGui("LevelOneGuideGui")
			if guide then (guide :: ScreenGui).Enabled = true end
			player:SetAttribute("UIRegressionForceDispatchActive", true)
		end},
		{Name = "hiding", Requires = {"HiddenStatus", "LeaveHiding"}, Setup = function()
			resetScenario(true)
			player:SetAttribute("UIRegressionForceHiding", true)
			revealGui("Level3TableHideUI")
		end},
		{Name = "hiding-plus-reader", Requires = {"HiddenStatus", "LeaveHiding"},
			Forbids = {"ReaderPanel", "ReaderToggle"}, Setup = function()
			resetScenario(true)
			player:SetAttribute("UIRegressionForceLevel3Reader", true)
			player:SetAttribute("UIRegressionForceReaderHidden", false)
			player:SetAttribute("UIRegressionForceHiding", true)
			revealGui("Level3TableHideUI")
		end},
		{Name = "spectate", Setup = function()
			resetScenario(true)
			player:SetAttribute("Spectating", true)
			revealGui("SpectateGui")
		end},
		{Name = "store-modal", Setup = function()
			resetScenario()
			player:SetAttribute("ZyntraStoreOpen", true)
			revealGui("ZyntraStore")
		end},
		{Name = "round-win-compact", Requires = {
			"RoundEnding", "EndingTitle", "EndingStats", "EndingHint", "ReturnToLobby",
		}, TouchTargets = {"ReturnToLobby"}, RoundEndingMode = "compact", Setup = function()
			resetScenario(true)
			player:SetAttribute("DevRoundEnding", "win")
		end},
		{Name = "round-loss-fullscreen", Requires = {
			"RoundEnding", "EndingTitle", "EndingStats", "EndingHint",
		}, Forbids = {"ReturnToLobby"}, RoundEndingMode = "fullscreen", Setup = function()
			resetScenario(true)
			player:SetAttribute("DevRoundEnding", "lose")
		end},
	}
end

-- Run every scenario at the CURRENT viewport and return a printable report.
-- Drive the viewport itself from the Studio Device Simulator, before Play.
-- Every ScreenGui the matrix expects to exist. A missing one means its script
-- errored during startup, and without this check the scenario that needed it
-- would simply scan nothing and report PASS -- which is exactly what happened
-- when a bad require took RoundUI down and the briefing test went vacuous.
local REQUIRED_GUIS = {
	"RoundGui", "LevelOneGuideGui", "PuzzleGui", "StaminaGui", "FlashlightPopup",
	"SpectateGui", "ZyntraStore", "Level2AlertGui", "Level2ObjectiveGui",
	"Level3ReaderGui", "Level3TableHideUI",
}

function UIRegression.MissingGuis(): {string}
	local missing = {}
	for _, name in ipairs(REQUIRED_GUIS) do
		if not playerGui():FindFirstChild(name) then
			table.insert(missing, name)
		end
	end
	return missing
end

function UIRegression.RunAll(): (string, number)
	local layout = UIDevice.Layout()
	local report = {string.format("=== %.0fx%.0f  class=%s  portrait=%s  touch=%s ===",
		layout.Width, layout.Height, layout.Class,
		tostring(layout.Portrait), tostring(layout.IsTouch))}
	local failures = 0
	local captures = {}
	local missing = UIRegression.MissingGuis()
	if #missing > 0 then
		failures += 1
		table.insert(report, "MISSING SCREENGUIS (a HUD script failed to start): "
			.. table.concat(missing, ", "))
	end
	for _, scenario in ipairs(UIRegression.Scenarios()) do
		scenario.Setup()
		task.wait(.3)
		local result = UIRegression.Check()
		-- A scenario that measured nothing is not a pass. The briefing panel can
		-- be hidden again by a stray refresh between setup and scan, and without
		-- this the report would say PASS for a screen with nothing on it.
		local function findRect(fragment)
			for _, rect in ipairs(result.Rects) do
				if rect.Path:find(fragment, 1, true) then return rect end
			end
			for _, group in ipairs(result.Groups) do
				if group.Path:find(fragment, 1, true) then return group end
				for _, child in ipairs(group.Children) do
					if child.Path:find(fragment, 1, true) then return child end
				end
			end
			return nil
		end
		local contractProblems = {}
		local required = scenario.Requires
		if type(required) == "string" then required = {required} end
		for _, fragment in ipairs(required or {}) do
			if not findRect(fragment) then
				table.insert(contractProblems, "VACUOUS: " .. fragment .. " was not measured")
			end
		end
		for _, fragment in ipairs(scenario.Forbids or {}) do
			if findRect(fragment) then
				table.insert(contractProblems, "STATE LEAK: " .. fragment .. " should be hidden")
			end
		end
		if layout.IsTouch then
			for _, fragment in ipairs(scenario.TouchTargets or {}) do
				local rect = findRect(fragment)
				if not rect then
					table.insert(contractProblems, "TOUCH TARGET: missing " .. fragment)
				else
					local width = rect.Right - rect.Left
					local height = rect.Bottom - rect.Top
					if rect.Interactive ~= true or rect.Active ~= true then
						table.insert(contractProblems,
							"TOUCH TARGET: " .. fragment .. " is not active and tappable")
					end
					if width < 44 or height < 44 then
						table.insert(contractProblems, string.format(
							"TOUCH TARGET: %s is %.0fx%.0f (minimum 44x44)",
							fragment, width, height))
					end
				end
			end
		end
		for _, fragment in ipairs(scenario.TextFitTargets or {}) do
			local rect = findRect(fragment)
			if not rect or not rect.TextBounds then
				table.insert(contractProblems, "TEXT FIT: missing measurable " .. fragment)
			else
				local width = rect.Right - rect.Left
				local height = rect.Bottom - rect.Top
				if rect.TextBounds.X > width + 1 or rect.TextBounds.Y > height + 1 then
					table.insert(contractProblems, string.format(
						"TEXT FIT: %s needs %.0fx%.0f inside %.0fx%.0f",
						fragment, rect.TextBounds.X, rect.TextBounds.Y, width, height))
				end
			end
		end
		if scenario.RoundEndingMode then
			local rect = findRect("RoundEnding")
			if rect then
				local width = rect.Right - rect.Left
				local height = rect.Bottom - rect.Top
				if scenario.RoundEndingMode == "compact" then
					if width >= result.Viewport.X * .95 or height >= result.Viewport.Y * .50 then
						table.insert(contractProblems, string.format(
							"RESULT SHAPE: win is not compact (%.0fx%.0f in %.0fx%.0f)",
							width, height, result.Viewport.X, result.Viewport.Y))
					end
				else
					-- IgnoreGuiInset full-screen GUIs begin one top inset above the
					-- content origin. Their bottom is displaced by the same amount;
					-- comparing to 0..Viewport falsely reports a cropped overlay.
					local expectedTop = -layout.Inset.Y
					local expectedBottom = result.Viewport.Y - layout.Inset.Y
					if math.abs(rect.Left) > 2 or math.abs(rect.Top - expectedTop) > 2
					or math.abs(rect.Right - result.Viewport.X) > 2
					or math.abs(rect.Bottom - expectedBottom) > 2 then
						table.insert(contractProblems, string.format(
							"RESULT SHAPE: loss is not full-screen ((%.0f,%.0f)-(%.0f,%.0f))",
							rect.Left, rect.Top, rect.Right, rect.Bottom))
					end
				end
			else
				table.insert(contractProblems, "RESULT SHAPE: RoundEnding was not measured")
			end
		end
		if scenario.Capture then
			local rect = findRect(scenario.Capture)
			if rect then captures[scenario.Name] = rect end
			if scenario.CompareWith then
				local prior = captures[scenario.CompareWith]
				if not rect or not prior then
					table.insert(contractProblems, "COMPARE: missing " .. scenario.Capture)
				elseif math.abs(rect.Left - prior.Left) > 1
					or math.abs(rect.Top - prior.Top) > 1
					or math.abs(rect.Right - prior.Right) > 1
					or math.abs(rect.Bottom - prior.Bottom) > 1 then
					table.insert(contractProblems,
						"COMPARE: ReaderToggle moved or resized between open and closed")
				end
			end
		end
		local passed = result.Passed and #contractProblems == 0
		if not passed then failures += 1 end
		table.insert(report, string.format("%-28s %s  rects=%d texts=%d",
			scenario.Name, passed and "PASS" or "FAIL",
			result.RectCount, result.TextCount))
		for _, problem in ipairs(contractProblems) do
			table.insert(report, "     Contract: " .. problem)
		end
		for _, label in ipairs({"Offscreen", "Overlaps", "MovementZoneHits",
			"KeyboardBindings", "InternalOverlaps"}) do
			for _, problem in ipairs(result[label]) do
				table.insert(report, "     " .. label .. ": " .. problem)
			end
		end
		-- Measured child rectangles, printed pass or fail. A layout assertion
		-- that only speaks when it breaks cannot be reviewed, and these are the
		-- numbers the whole dispatch-overlap question turns on.
		for _, group in ipairs(result.Groups) do
			table.insert(report, string.format("     %s (%.0f,%.0f)-(%.0f,%.0f)",
				group.Path, group.Left, group.Top, group.Right, group.Bottom))
			for _, child in ipairs(group.Children) do
				table.insert(report, string.format("        %s (%.0f,%.0f)-(%.0f,%.0f)%s",
					child.Path, child.Left, child.Top, child.Right, child.Bottom,
					child.Interactive and " [tappable]" or ""))
			end
		end
	end
	resetScenario()
	table.insert(report, string.format("TOTAL: %d scenarios, %d failed",
		#UIRegression.Scenarios(), failures))
	return table.concat(report, "\n"), failures
end

return UIRegression
