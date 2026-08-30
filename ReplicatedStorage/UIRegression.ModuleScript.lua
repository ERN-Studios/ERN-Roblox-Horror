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
-- Used by BriefingFitMatrix only. GetTextBoundsAsync is the ONE way to ask what
-- a string WOULD need at a size and wrap width the client is not currently
-- rendering; the TextBounds property can only ever answer for what is on screen
-- right now, at the one viewport Studio happens to be drawing.
local TextService = game:GetService("TextService")

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
	-- The touch crouch. It lives in the same reserved control column as RUN and
	-- JUMP, so like them it is exempt from the movement-zone test and still has
	-- to stay onscreen, stay >= 44, and overlap nothing. Added when crouch
	-- finally got a touch path at all: it was LeftControl-only, while the store
	-- page promised "crouch silent" and "full touch controls".
	TouchSneakHold = true,
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
	-- The lobby queue panel. Its controls live two levels down, so without this
	-- the matrix measured the shade and nothing inside it -- which is how five
	-- interactive controls stayed under the 44px floor unnoticed.
	QueueHostPanel = true,
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
-- A control always overlaps the panel it lives in. Comparing the two is not a
-- finding, it is the parent-child relationship, so containment is excluded from
-- every overlap test that names a specific target.
local function contains(outer: string, inner: string): boolean
	if outer == inner then return true end
	if inner:sub(1, #outer + 1) == outer .. "." then return true end
	if outer:sub(1, #inner + 1) == inner .. "." then return true end
	-- The two collectors spell the same panel differently: Scan() walks
	-- ScreenGui children and produces "RoundGui.QueueHostShade.QueueHostPanel",
	-- while Children() keys off the panel itself and produces
	-- "RoundGui.QueueHostPanel.CloseQueue". A control is still inside its panel,
	-- so match on the shared segment rather than on a literal prefix.
	local outerLast = outer:match("([^.]+)$")
	local innerLast = inner:match("([^.]+)$")
	if outerLast and inner:find("." .. outerLast .. ".", 1, true) then return true end
	if innerLast and outer:find("." .. innerLast .. ".", 1, true) then return true end
	return false
end

-- Everything that can be wrong with a required touch target, in one place.
-- `geometry` is false under the viewport override, where AbsolutePosition is
-- measured against the REAL window rather than the simulated screen and every
-- position-based comparison would be meaningless. Size is unaffected: a 44px
-- offset is 44 real pixels whatever the viewport claims to be.
local function touchTargetProblems(rect, rects, viewport, geometry: boolean): {string}
	local problems = {}
	if rect.Interactive ~= true then
		table.insert(problems, "not an interactive control")
	end
	if rect.Active ~= true then
		table.insert(problems, "not active, so it cannot be tapped")
	end
	local width = rect.Right - rect.Left
	local height = rect.Bottom - rect.Top
	if width < 44 or height < 44 then
		table.insert(problems, string.format("%.0fx%.0f, under 44x44", width, height))
	end
	if geometry then
		if rect.Left < -1 or rect.Top < -1
			or rect.Right > viewport.X + 1 or rect.Bottom > viewport.Y + 1 then
			table.insert(problems, string.format(
				"off screen at (%.0f,%.0f)-(%.0f,%.0f) in %.0fx%.0f",
				rect.Left, rect.Top, rect.Right, rect.Bottom, viewport.X, viewport.Y))
		end
		for _, other in ipairs(rects) do
			if not other.Overlay and not contains(other.Path, rect.Path)
				and rect.Left < other.Right and rect.Right > other.Left
				and rect.Top < other.Bottom and rect.Bottom > other.Top then
				table.insert(problems, "overlaps " .. other.Path)
				break
			end
		end
	end
	return problems
end

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
	-- The lobby queue lives inside RoundGui, which is never disabled, so nothing
	-- else here puts it away. Leaving it up leaked it into every scenario that
	-- ran after the queue row.
	local roundGui = findGui("RoundGui")
	local shade = roundGui and roundGui:FindFirstChild("QueueHostShade")
	if shade then shade.Visible = false end
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
	-- The harness's `inRound` flag only ever changed the Zyntra open button; it
	-- never told the CLIENT a round was running. So every control gated on
	-- NoiseReporter's controlsAvailable() -- JUMP, SNEAK, the glowstick drop --
	-- was invisible in every scenario, and a matrix that never saw them could
	-- never report them too small or overlapping. Cleared here so a scenario
	-- that does set it cannot leak the round into the next row.
	player:SetAttribute("InRound", nil)
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
		{Name = "objectives-button", Requires = "ObjectivesButton",
			TouchTargets = {"ObjectivesButton"}, Setup = function()
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
		end, TouchTargets = {"ObjectivesPanel.Close"}},
		-- The lobby queue panel: five interactive controls, all of which a
		-- player has to hit with a thumb, none of which were in this matrix.
		{Name = "queue-host-panel", Requires = "QueueHostPanel",
			TouchTargets = {
				"QueueHostPanel.CloseQueue", "QueueHostPanel.DecreasePlayers",
				"QueueHostPanel.IncreasePlayers", "QueueHostPanel.PrivacyToggle",
				"QueueHostPanel.CreateParty",
			}, Setup = function()
			resetScenario(false)
			revealGui("RoundGui", function(child)
				return child.Name == "QueueHostShade"
			end)
			local shade = findGui("RoundGui")
			shade = shade and shade:FindFirstChild("QueueHostShade")
			if shade then shade.Visible = true end
		end},
		{Name = "level1-objective-receiver", Setup = function()
			resetScenario(true); revealGui("PuzzleGui")
		end},
		-- The in-round touch cluster, measured as a cluster. RUN and JUMP were
		-- already covered by TouchTargetMatrix's own sweep; SNEAK is new and the
		-- crouch it drives is the one the store page advertises, so it is asserted
		-- here as a tappable target like any other.
		{Name = "touch-movement-cluster", TouchOnly = true, Requires = {"TouchSneakHold"},
			TouchTargets = {"TouchSneakHold", "TouchRunHold", "TouchJump"},
			Setup = function()
				resetScenario(true)
				-- These controls are level-only by design, so the scenario has to
				-- actually be in a round for them to exist at all.
				player:SetAttribute("InRound", true)
				task.wait(.1)
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
		-- The result overlay is full-bleed for EVERY outcome. Levels 1 and 2 show
		-- exactly two actions; the last level shows one and must not offer a route
		-- to a level that does not exist; a wipe shows none.
		{Name = "round-win-fullscreen", Requires = {
			"RoundEnding", "EndingTitle", "EndingStats", "EndingHint",
			"ContinueRun", "ReturnToLobby",
		}, TouchTargets = {"ContinueRun", "ReturnToLobby"},
			TextFitTargets = {"ContinueRun", "ReturnToLobby"},
			RoundEndingMode = "fullscreen", Setup = function()
			resetScenario(true)
			player:SetAttribute("DevRoundEnding", "win")
		end},
		{Name = "round-win-final-level", Requires = {
			"RoundEnding", "EndingTitle", "EndingStats", "EndingHint", "ReturnToLobby",
		}, Forbids = {"ContinueRun"}, TouchTargets = {"ReturnToLobby"},
			TextFitTargets = {"ReturnToLobby"},
			RoundEndingMode = "fullscreen", Setup = function()
			resetScenario(true)
			player:SetAttribute("DevRoundEnding", "winfinal")
		end},
		{Name = "round-loss-fullscreen", Requires = {
			"RoundEnding", "EndingTitle", "EndingStats", "EndingHint",
		}, Forbids = {"ContinueRun", "ReturnToLobby"},
			RoundEndingMode = "fullscreen", Setup = function()
			resetScenario(true)
			player:SetAttribute("DevRoundEnding", "lose")
		end},
	}
end

-- What the completion overlay OFFERS and where each action goes. The scenario
-- matrix above covers the geometry; this covers behaviour the geometry cannot
-- see: the exact action set per level, the remote message each button is wired
-- to, what the countdown promises, and what a real press actually does. The
-- press runs through RoundUI's own handler, so this is the production routing
-- and not a re-implementation of it.
function UIRegression.CompletionContract(): (string, number)
	local player = Players.LocalPlayer
	local report = {"=== completion contract ==="}
	local failures = 0
	local function check(ok: boolean, description: string, detail: string?)
		if ok then
			table.insert(report, "  ok   " .. description)
		else
			failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. detail .. ")") or ""))
		end
	end

	local function overlay(): Instance?
		local round = findGui("RoundGui")
		return round and round:FindFirstChild("RoundEnding") or nil
	end
	local function action(name: string): TextButton?
		local frame = overlay()
		local child = frame and frame:FindFirstChild(name)
		return (child and child:IsA("TextButton")) and child or nil
	end
	local function hintText(): string
		local frame = overlay()
		local hint = frame and frame:FindFirstChild("EndingHint")
		return (hint and hint:IsA("TextLabel")) and hint.Text or ""
	end
	local function visibleActions(): {string}
		local names = {}
		local frame = overlay()
		for _, child in ipairs(frame and frame:GetChildren() or {}) do
			if child:IsA("TextButton") and child.Visible then
				table.insert(names, child.Name)
			end
		end
		table.sort(names)
		return names
	end
	local function drive(mode: string)
		resetScenario(true)
		player:SetAttribute("DevRoundEnding", mode)
		task.wait(.3)
	end
	local function press(name: string)
		player:SetAttribute("UIRegressionCompletionPress", nil)
		player:SetAttribute("UIRegressionCompletionPress", name)
		task.wait(.15)
	end

	-- (1) Levels 1 and 2: exactly CONTINUE and BACK TO LOBBY.
	drive("win")
	local continueRun, returnLobby = action("ContinueRun"), action("ReturnToLobby")
	check(continueRun ~= nil and returnLobby ~= nil, "win offers both actions")
	check(table.concat(visibleActions(), ",") == "ContinueRun,ReturnToLobby",
		"win offers EXACTLY two actions", table.concat(visibleActions(), ","))
	if continueRun and returnLobby then
		check(continueRun.Text == "CONTINUE", "continue label", continueRun.Text)
		check(returnLobby.Text == "BACK TO LOBBY", "lobby label", returnLobby.Text)
		check(continueRun:GetAttribute("CompletionAction") == "continuenow",
			"continue is wired to continuenow",
			tostring(continueRun:GetAttribute("CompletionAction")))
		check(returnLobby:GetAttribute("CompletionAction") == "returntolobby",
			"lobby is wired to returntolobby",
			tostring(returnLobby:GetAttribute("CompletionAction")))
	end
	check(hintText():find("BEGINS IN", 1, true) ~= nil,
		"win countdown promises the next level", hintText())

	-- (2) Pressing CONTINUE takes the run onward and locks both actions.
	press("ContinueRun")
	continueRun, returnLobby = action("ContinueRun"), action("ReturnToLobby")
	if continueRun and returnLobby then
		check(continueRun.Text == "CONTINUING...", "continue press acknowledges",
			continueRun.Text)
		check(not continueRun.Active and not returnLobby.Active,
			"continue press locks both actions")
	end

	-- (3) Pressing BACK TO LOBBY takes the other route.
	drive("win")
	press("ReturnToLobby")
	returnLobby = action("ReturnToLobby")
	if returnLobby then
		check(returnLobby.Text == "RETURNING...", "lobby press acknowledges",
			returnLobby.Text)
	end

	-- (4) The last level: one action, and no route to a level 4.
	drive("winfinal")
	check(table.concat(visibleActions(), ",") == "ReturnToLobby",
		"final level offers ONLY back to lobby", table.concat(visibleActions(), ","))
	check(hintText():find("LOBBY", 1, true) ~= nil,
		"final countdown returns to the lobby", hintText())
	check(hintText():find("LEVEL 4", 1, true) == nil,
		"final countdown never routes to a level 4", hintText())
	press("ContinueRun")
	returnLobby = action("ReturnToLobby")
	check(returnLobby ~= nil and returnLobby.Text == "BACK TO LOBBY"
		and returnLobby.Active,
		"a hidden continue cannot be pressed on the final level")

	-- (5) A wipe offers nothing to press.
	drive("lose")
	check(#visibleActions() == 0, "a wipe offers no actions",
		table.concat(visibleActions(), ","))

	resetScenario()
	table.insert(report, string.format("COMPLETION: %d failed", failures))
	return table.concat(report, "\n"), failures
end

-- The result overlay's action row across a device matrix.
--
-- The scenario matrix can only measure the viewport Studio is actually
-- rendering, and the Device Simulator has to be set before Play and cannot be
-- driven from Luau, so a single run can never cover phone AND tablet. This
-- drives UIDevice's Studio-only viewport override instead, which makes the
-- real HUD re-measure at each simulated size, then resolves each button's
-- resulting UDim2 against that viewport. It is the production responsive maths
-- under test, not the pixels Studio happens to be drawing.
--
-- The override has to be set on `workspace`, not by replacing UIDevice.Layout:
-- a console/plugin VM gets its OWN module cache, so a table patched there is
-- invisible to the LocalScript being measured.
local FIT_DEVICES = {
	{Name = "desktop 1920x1080", Width = 1920, Height = 1080, Touch = false, Portrait = false, Class = "desktop"},
	{Name = "desktop 1280x720", Width = 1280, Height = 720, Touch = false, Portrait = false, Class = "desktop"},
	{Name = "tablet landscape 1024x768", Width = 1024, Height = 768, Touch = true, Portrait = false, Class = "tablet"},
	{Name = "tablet portrait 768x1024", Width = 768, Height = 1024, Touch = true, Portrait = true, Class = "tablet"},
	{Name = "phone landscape 812x375", Width = 812, Height = 375, Touch = true, Portrait = false, Class = "phone"},
	{Name = "phone landscape 667x375", Width = 667, Height = 375, Touch = true, Portrait = false, Class = "phone"},
	{Name = "phone portrait 390x844", Width = 390, Height = 844, Touch = true, Portrait = true, Class = "phone"},
	{Name = "phone portrait 375x667", Width = 375, Height = 667, Touch = true, Portrait = true, Class = "phone"},
	-- The exact viewport a Galaxy A06 reports in landscape, which is where the
	-- compact queue panel was first found to be too small to use.
	{Name = "phone landscape 705x338", Width = 705, Height = 338, Touch = true, Portrait = false, Class = "phone"},
}

function UIRegression.CompletionFit(): (string, number)
	local player = Players.LocalPlayer
	local report = {"=== completion fit matrix ==="}
	local failures = 0
	local function fail(message)
		failures += 1
		table.insert(report, "  FAIL " .. message)
	end

	local function resolve(button, width, height)
		local size, position = button.Size, button.Position
		local w = size.X.Offset + size.X.Scale * width
		local h = size.Y.Offset + size.Y.Scale * height
		local cx = position.X.Offset + position.X.Scale * width
		local cy = position.Y.Offset + position.Y.Scale * height
		return {
			Name = button.Name,
			Left = cx - w * button.AnchorPoint.X,
			Top = cy - h * button.AnchorPoint.Y,
			Right = cx + w * (1 - button.AnchorPoint.X),
			Bottom = cy + h * (1 - button.AnchorPoint.Y),
			Width = w,
			Height = h,
		}
	end

	local forcedTouch = workspace:GetAttribute("ForceTouchUI")
	local forcedViewport = workspace:GetAttribute("UIRegressionViewport")
	local ok, err = pcall(function()
		for _, mode in ipairs({
			{Label = "levels 1-2", Dev = "win", Expect = 2},
			{Label = "final level", Dev = "winfinal", Expect = 1},
		}) do
			for _, device in ipairs(FIT_DEVICES) do
				-- Simulate the device BEFORE the result screen is shown, so the
				-- first layout it performs is already the one under test.
				workspace:SetAttribute("ForceTouchUI", device.Touch or nil)
				workspace:SetAttribute("UIRegressionViewport",
					Vector2.new(device.Width, device.Height))
				task.wait(.12)
				resetScenario(true)
				player:SetAttribute("DevRoundEnding", mode.Dev)
				task.wait(.25)

				local round = findGui("RoundGui")
				local frame = round and round:FindFirstChild("RoundEnding")
				local rects = {}
				for _, child in ipairs(frame and frame:GetChildren() or {}) do
					if child:IsA("TextButton") and child.Visible then
						table.insert(rects, resolve(child, device.Width, device.Height))
					end
				end
				local hint = frame and frame:FindFirstChild("EndingHint")
				local hintRect = (hint and hint.Visible)
					and resolve(hint, device.Width, device.Height) or nil

				local label = string.format("%s / %s", mode.Label, device.Name)
				if #rects ~= mode.Expect then
					fail(string.format("%s: expected %d action(s), measured %d",
						label, mode.Expect, #rects))
				else
					local problems = {}
					for _, rect in ipairs(rects) do
						if rect.Left < 0 or rect.Top < 0
							or rect.Right > device.Width or rect.Bottom > device.Height then
							table.insert(problems, string.format(
								"%s offscreen (%.0f,%.0f)-(%.0f,%.0f)",
								rect.Name, rect.Left, rect.Top, rect.Right, rect.Bottom))
						end
						if device.Touch and (rect.Width < 44 or rect.Height < 44) then
							table.insert(problems, string.format("%s is %.0fx%.0f, under 44px",
								rect.Name, rect.Width, rect.Height))
						end
					end
					if #rects == 2 then
						local a, b = rects[1], rects[2]
						if a.Left < b.Right and b.Left < a.Right
							and a.Top < b.Bottom and b.Top < a.Bottom then
							table.insert(problems, "the two actions overlap each other")
						end
					end
					-- The countdown sits directly above the actions. A stacked pair on
					-- a portrait phone used to be laid out against the viewport
					-- independently of it and ran 11-19px into it.
					if hintRect then
						for _, rect in ipairs(rects) do
							if rect.Left < hintRect.Right and hintRect.Left < rect.Right
								and rect.Top < hintRect.Bottom and hintRect.Top < rect.Bottom then
								table.insert(problems, string.format(
									"%s overlaps the countdown by %.0fpx",
									rect.Name, hintRect.Bottom - rect.Top))
							end
						end
					end
					if #problems > 0 then
						fail(label .. ": " .. table.concat(problems, "; "))
					else
						local shape = #rects == 2
							and (math.abs(rects[1].Top - rects[2].Top) < 1 and "row" or "stack")
							or "single"
						table.insert(report, string.format("  ok   %-38s %s, %.0fx%.0f each",
							label, shape, rects[1].Width, rects[1].Height))
					end
				end
			end
		end
	end)
	workspace:SetAttribute("UIRegressionViewport", forcedViewport)
	workspace:SetAttribute("ForceTouchUI", forcedTouch)
	task.wait(.12)
	resetScenario()
	if not ok then
		failures += 1
		table.insert(report, "  FAIL fit matrix errored: " .. tostring(err))
	end
	table.insert(report, string.format("FIT: %d failed", failures))
	return table.concat(report, "\n"), failures
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

-- Touch targets, at real phone and tablet sizes, driven entirely from Luau.
--
-- RunAll deliberately refuses to run while UIRegressionViewport is set, because
-- its geometry assertions compare measured pixels against a REPORTED viewport
-- and the two diverge under the override. This matrix has no such problem: a
-- 44-pixel minimum is 44 real pixels whatever the screen claims to be, and the
-- layout under test was computed for the simulated size. So it owns the
-- override, sweeps device sizes and both orientations without the Device
-- Simulator, and re-checks keyboard glyphs while it is there -- "can a finger
-- reach this" and "does this print a key I have not got" are both viewport-free
-- questions.
local TOUCH_DEVICES = {
	{Name = "phone portrait 390x844", Size = Vector2.new(390, 844)},
	{Name = "phone landscape 844x390", Size = Vector2.new(844, 390)},
	{Name = "small phone landscape 568x320", Size = Vector2.new(568, 320)},
	{Name = "small phone landscape 667x375", Size = Vector2.new(667, 375)},
	-- The exact viewport a Galaxy A06 reports in landscape. Every control the
	-- matrix guards was measured here first.
	{Name = "Galaxy A06 landscape 705x338", Size = Vector2.new(705, 338)},
	{Name = "tablet portrait 820x1180", Size = Vector2.new(820, 1180)},
	{Name = "tablet landscape 1180x820", Size = Vector2.new(1180, 820)},
}

function UIRegression.TouchTargetMatrix(): (string, number)
	local previousViewport = workspace:GetAttribute("UIRegressionViewport")
	local previousTouch = workspace:GetAttribute("ForceTouchUI")
	local report = {"=== touch targets across phone and tablet ==="}
	local failures, checks = 0, 0
	local function record(ok, description, detail)
		checks += 1
		if ok then
			table.insert(report, "  ok   " .. description)
		else
			failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
		end
	end

	workspace:SetAttribute("ForceTouchUI", true)
	local ran, runError = pcall(function()
		for _, device in ipairs(TOUCH_DEVICES) do
			workspace:SetAttribute("UIRegressionViewport", device.Size)
			task.wait(.3)
			local layout = UIDevice.Layout()
			table.insert(report, string.format("--- %s (reported %.0fx%.0f, class=%s, touch=%s) ---",
				device.Name, layout.Width, layout.Height, layout.Class, tostring(layout.IsTouch)))
			record(layout.IsTouch and layout.Width == device.Size.X
				and layout.Height == device.Size.Y,
				device.Name .. ": the device override took",
				string.format("%.0fx%.0f touch=%s", layout.Width, layout.Height,
					tostring(layout.IsTouch)))

			-- A landscape phone's only bottom-anchored HUD lane is the corridor
			-- between the thumbstick and the right-side controls. Resolve the real
			-- production UDim2/UISizeConstraint values at the simulated viewport so
			-- a minimum-size clamp cannot silently push the Level 2 objective panel
			-- back into either control zone. Only X is asserted here: BottomOffsetFor
			-- intentionally measures the live ScreenGui, whose rendered Y still uses
			-- Studio's real viewport while this override is active.
			if layout.Corridor.Width >= 150 then
				local objectiveGui = findGui("Level2ObjectiveGui")
				local objectivePanel = objectiveGui
					and objectiveGui:FindFirstChild("Level2ObjectivePanel")
				local objectiveRect = objectivePanel
					and UIRegression.ResolveRect(objectivePanel, device.Size, layout.Inset.Y)
				local contained = objectiveRect ~= nil
					and objectiveRect.Unresolvable == nil
					and objectiveRect.Left >= layout.Corridor.Left - 1
					and objectiveRect.Right <= layout.Corridor.Right + 1
				record(contained,
					device.Name .. ": Level 2 objectives stay inside the horizontal control corridor",
					objectiveRect and string.format("x %.1f..%.1f vs corridor %.1f..%.1f%s",
						objectiveRect.Left, objectiveRect.Right,
						layout.Corridor.Left, layout.Corridor.Right,
						objectiveRect.Unresolvable and ("; " .. objectiveRect.Unresolvable) or "")
						or "Level2ObjectivePanel missing or unresolvable")
			end

			for _, scenario in ipairs(UIRegression.Scenarios()) do
				if scenario.TouchTargets then
					scenario.Setup()
					task.wait(.2)
					local result = UIRegression.Check()
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
					local viewport = UIDevice.Layout().Viewport
					for _, fragment in ipairs(scenario.TouchTargets) do
						local rect = findRect(fragment)
						if not rect then
							record(false, string.format("%s / %s: %s is on screen",
								device.Name, scenario.Name, fragment), "not measured")
						else
							-- Size, interactivity and activeness only. Position is
							-- deliberately NOT judged here: with the viewport
							-- override active, Studio still renders at its real
							-- window size, so AbsolutePosition is a real-screen
							-- coordinate being compared against a simulated
							-- screen. The geometry half runs below, at the real
							-- viewport, where it means something.
							record(#touchTargetProblems(rect, result.Rects, viewport, false) == 0,
								string.format("%s / %s: %s is interactive, active and at least 44x44",
									device.Name, scenario.Name, fragment),
								table.concat(touchTargetProblems(
									rect, result.Rects, viewport, false), "; "))
						end
					end
					-- Same sweep, same setup: nothing touch-only may print a key.
					record(#result.KeyboardBindings == 0,
						string.format("%s / %s: no keyboard glyph on a touch screen",
							device.Name, scenario.Name),
						table.concat(result.KeyboardBindings, "; "))
				end
			end
		end
	end)

	-- ------------------------------------------------------------------
	-- The geometry half, at the REAL rendered viewport.
	-- ------------------------------------------------------------------
	-- ForceTouchUI alone tells no lies about pixels: the touch LAYOUT is
	-- applied and Studio renders it at its actual window size, so on-screen,
	-- overlap, movement-zone and whole-screen assertions are all valid.
	workspace:SetAttribute("UIRegressionViewport", nil)
	task.wait(.35)
	local geometryRan, geometryError = pcall(function()
		local layout = UIDevice.Layout()
		table.insert(report, string.format(
			"--- real viewport %.0fx%.0f with the touch layout applied ---",
			layout.Width, layout.Height))
		record(layout.IsTouch, "the touch layout is applied at the real viewport")
		for _, scenario in ipairs(UIRegression.Scenarios()) do
			if scenario.TouchTargets then
				scenario.Setup()
				task.wait(.2)
				local result = UIRegression.Check()
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
				for _, fragment in ipairs(scenario.TouchTargets) do
					local rect = findRect(fragment)
					if not rect then
						record(false, string.format("real viewport / %s: %s is on screen",
							scenario.Name, fragment), "not measured")
					else
						local problems = touchTargetProblems(
							rect, result.Rects, layout.Viewport, true)
						record(#problems == 0, string.format(
							"real viewport / %s: %s is tappable, on screen, unobstructed"
							.. " and at least 44x44", scenario.Name, fragment),
							table.concat(problems, "; "))
					end
				end
				record(result.Passed == true, string.format(
					"real viewport / %s: the whole screen passes its own geometry checks",
					scenario.Name),
					string.format("%d offscreen, %d overlaps, %d zone hits, %d internal",
						#result.Offscreen, #result.Overlaps,
						#result.MovementZoneHits, #result.InternalOverlaps))
			end
		end
	end)
	if not geometryRan then
		failures += 1
		checks += 1
		table.insert(report, "  FAIL the real-viewport geometry pass ran  ("
			.. tostring(geometryError) .. ")")
	end

	workspace:SetAttribute("UIRegressionViewport", previousViewport)
	workspace:SetAttribute("ForceTouchUI", previousTouch)
	task.wait(.2)
	record(workspace:GetAttribute("UIRegressionViewport") == previousViewport
		and workspace:GetAttribute("ForceTouchUI") == previousTouch,
		"the device overrides were restored")
	if not ran then
		failures += 1
		checks += 1
		table.insert(report, "  FAIL the matrix ran to completion  (" .. tostring(runError) .. ")")
	end
	table.insert(report, string.format("TOTAL: %d checks, %d failed", checks, failures))
	return table.concat(report, "\n"), failures
end

-- ---------------------------------------------------------------------------
-- The analytic resolver, and the device matrix that can actually use it
-- ---------------------------------------------------------------------------
--
-- UIRegressionViewport makes UIDevice REPORT a simulated size while Studio keeps
-- rendering at its real window size, so AbsolutePosition is a real-screen
-- coordinate. The old matrix responded by switching every position assertion OFF
-- under the override and running the geometry half at Studio's real 1694x698 --
-- where the queue panel lands somewhere else entirely. A 705x338 phone was
-- therefore never measured at 705x338 by anything, and a panel sitting squarely
-- under the control column reported green.
--
-- ResolveRect computes what a rect WOULD be at a given viewport, from the UDim2
-- values production actually set, so the override becomes measurable instead of
-- unmeasurable. It refuses to guess: anything whose position the engine computes
-- (a list/grid/table/page layout, padding, an aspect-ratio constraint) comes back
-- Unresolvable, and an Unresolvable target is a FAILURE, never a pass. That rule
-- is what stops this from becoming the old false green in a new form.
--
-- Rects are in SCREEN space -- y = 0 at the top of the viewport -- which is the
-- space UIDevice.Zones is in. Measured AbsolutePosition is NOT: it puts y = 0
-- below the top inset, so live rects are shifted before they are compared.
-- Measured in this place on 2026-08-29: a ScreenGui with IgnoreGuiInset = false
-- reports AbsolutePosition (0,0) with height viewport.Y - inset; one with
-- IgnoreGuiInset = true reports (0, -inset) at full height. Both therefore share
-- one reported space whose origin is inset pixels below the screen top.
local ENGINE_LAID_OUT = {
	UIListLayout = true, UIGridLayout = true, UIPageLayout = true,
	UITableLayout = true, UIPadding = true,
}

-- How far a live AbsolutePosition sits ABOVE true screen space.
--
-- AbsolutePosition is reported relative to an origin that sits BELOW the topbar
-- inset, and it does so for EVERY ScreenGui -- IgnoreGuiInset moves where the
-- GUI's own content begins, it does not move the origin AbsolutePosition is
-- measured from. UIRegression.ResolveRect returns true screen coordinates, so
-- converting a measured rect to compare against one always means adding the
-- inset back.
--
-- This used to return the inset ONLY when IgnoreGuiInset was true, which is
-- backwards, and it went unnoticed for exactly one reason: every matrix that
-- calibrated against the engine happened to target an inset-IGNORING ScreenGui
-- (the queue panel, the round HUD, the pool-foam caption), where the wrong
-- branch returns the right number by accident. BriefingFitMatrix is the first
-- to measure LevelOneGuideGui, which does NOT ignore the inset, and its
-- calibration gate failed by exactly one inset -- 58px on the machine this was
-- found on. Measured across all thirteen live ScreenGuis, resolved.Top minus
-- AbsolutePosition.Y is the inset in every single case, both settings of the
-- flag.
function UIRegression.ScreenSpaceShift(object): number
	local node = object
	while node and not node:IsA("ScreenGui") do node = node.Parent end
	if not node then return 0 end
	return UIDevice.Layout().Inset.Y
end

function UIRegression.ResolveRect(object, viewport: Vector2, insetY: number)
	local chain, node = {}, object
	while node and not node:IsA("ScreenGui") do
		table.insert(chain, 1, node)
		node = node.Parent
	end
	if not node then return nil end
	local screenGui = node :: ScreenGui

	-- The ScreenGui's own frame, in SCREEN space.
	local left, top = 0, 0
	local width, height = viewport.X, viewport.Y
	if not screenGui.IgnoreGuiInset then
		top = insetY
		height = viewport.Y - insetY
	end

	local unresolvable = nil
	for _, child in ipairs(chain) do
		local parent = child.Parent
		if parent then
			for _, sibling in ipairs(parent:GetChildren()) do
				if ENGINE_LAID_OUT[sibling.ClassName] then
					unresolvable = sibling.ClassName .. " on " .. parent.Name
				end
			end
		end
		if child:FindFirstChildOfClass("UIAspectRatioConstraint") then
			unresolvable = "UIAspectRatioConstraint on " .. child.Name
		end
		local w = child.Size.X.Offset + child.Size.X.Scale * width
		local h = child.Size.Y.Offset + child.Size.Y.Scale * height
		local sizeConstraint = child:FindFirstChildOfClass("UISizeConstraint")
		if sizeConstraint then
			w = math.clamp(w, sizeConstraint.MinSize.X, sizeConstraint.MaxSize.X)
			h = math.clamp(h, sizeConstraint.MinSize.Y, sizeConstraint.MaxSize.Y)
		end
		local scale = child:FindFirstChildOfClass("UIScale")
		if scale then w, h = w * scale.Scale, h * scale.Scale end
		local cx = left + child.Position.X.Offset + child.Position.X.Scale * width
		local cy = top + child.Position.Y.Offset + child.Position.Y.Scale * height
		left = cx - w * child.AnchorPoint.X
		top = cy - h * child.AnchorPoint.Y
		width, height = w, h
	end
	return {
		Left = left, Top = top, Right = left + width, Bottom = top + height,
		Width = width, Height = height, Unresolvable = unresolvable,
	}
end

-- Every device the queue modal has to survive, with what it must classify as.
local MODAL_DEVICES = {
	{Name = "desktop 1920x1080", Size = Vector2.new(1920, 1080), Touch = false, Class = "desktop", Portrait = false},
	{Name = "desktop 1366x768", Size = Vector2.new(1366, 768), Touch = false, Class = "desktop", Portrait = false},
	-- The exact viewport a Galaxy A06 reports in landscape, and the shape the
	-- old layout was broken on.
	{Name = "Galaxy A06 landscape 705x338", Size = Vector2.new(705, 338), Touch = true, Class = "phone", Portrait = false},
	{Name = "Galaxy A06 portrait 338x705", Size = Vector2.new(338, 705), Touch = true, Class = "phone", Portrait = true},
	{Name = "iPhone portrait 390x844", Size = Vector2.new(390, 844), Touch = true, Class = "phone", Portrait = true},
	{Name = "iPhone landscape 844x390", Size = Vector2.new(844, 390), Touch = true, Class = "phone", Portrait = false},
	{Name = "iPhone SE portrait 375x667", Size = Vector2.new(375, 667), Touch = true, Class = "phone", Portrait = true},
	{Name = "iPhone SE landscape 667x375", Size = Vector2.new(667, 375), Touch = true, Class = "phone", Portrait = false},
	-- Smaller than anything in the matrix before, and the shape that made the
	-- fixed-width stepper row resolve to a negative size.
	{Name = "small landscape 568x320", Size = Vector2.new(568, 320), Touch = true, Class = "phone", Portrait = false},
	{Name = "iPad portrait 768x1024", Size = Vector2.new(768, 1024), Touch = true, Class = "tablet", Portrait = true},
	{Name = "iPad landscape 1024x768", Size = Vector2.new(1024, 768), Touch = true, Class = "tablet", Portrait = false},
	{Name = "iPad Pro portrait 834x1194", Size = Vector2.new(834, 1194), Touch = true, Class = "tablet", Portrait = true},
	{Name = "tablet landscape 1180x820", Size = Vector2.new(1180, 820), Touch = true, Class = "tablet", Portrait = false},
}

-- The five controls the queue modal must always offer, and the labels that must
-- stay inside it. Named, so a control silently disappearing is a failure rather
-- than a shorter loop.
local MODAL_CONTROLS = {"CloseQueue", "DecreasePlayers", "IncreasePlayers", "PrivacyToggle", "CreateParty"}

function UIRegression.QueueModalMatrix(): (string, number)
	local previousViewport = workspace:GetAttribute("UIRegressionViewport")
	local previousTouch = workspace:GetAttribute("ForceTouchUI")
	local report = {"=== queue modal geometry, resolved per device ==="}
	local failures, checks = 0, 0
	local function record(ok, description, detail)
		checks += 1
		if ok then
			table.insert(report, "  ok   " .. description)
		else
			failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
		end
	end

	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local shade, panel
	if playerGui then
		for _, descendant in ipairs(playerGui:GetDescendants()) do
			if descendant.Name == "QueueHostShade" then shade = descendant break end
		end
		panel = shade and shade:FindFirstChild("QueueHostPanel")
	end
	if not panel then
		record(false, "the queue modal exists to be measured", "QueueHostPanel not found")
		return table.concat(report, "\n"), failures
	end

	local wasVisible = shade.Visible
	local ran, runError = pcall(function()
		-- ------------------------------------------------------------------
		-- CALIBRATION. Before trusting the resolver anywhere, prove it agrees
		-- with the engine at the REAL viewport, where AbsolutePosition is true.
		-- A resolver that is wrong in the same direction as the code it checks
		-- is worth nothing, and this is the only thing that rules that out.
		-- ------------------------------------------------------------------
		workspace:SetAttribute("UIRegressionViewport", nil)
		workspace:SetAttribute("ForceTouchUI", nil)
		shade.Visible = true
		task.wait(0.35)
		local realLayout = UIDevice.Layout()
		local shift = UIRegression.ScreenSpaceShift(panel)
		local worst, worstName = 0, ""
		local targets = {panel}
		for _, name in ipairs(MODAL_CONTROLS) do
			local control = panel:FindFirstChild(name, true)
			if control then table.insert(targets, control) end
		end
		for _, object in ipairs(targets) do
			local resolved = UIRegression.ResolveRect(object, realLayout.Viewport, realLayout.Inset.Y)
			if resolved and not resolved.Unresolvable then
				local live = {
					Left = object.AbsolutePosition.X,
					Top = object.AbsolutePosition.Y + shift,
					Right = object.AbsolutePosition.X + object.AbsoluteSize.X,
					Bottom = object.AbsolutePosition.Y + object.AbsoluteSize.Y + shift,
				}
				for _, edge in ipairs({"Left", "Top", "Right", "Bottom"}) do
					local delta = math.abs(resolved[edge] - live[edge])
					if delta > worst then worst, worstName = delta, object.Name .. "." .. edge end
				end
			end
		end
		record(worst <= 1, "the resolver agrees with the engine at the real viewport",
			string.format("worst edge error %.2fpx at %s", worst, worstName))

		-- ------------------------------------------------------------------
		-- The sweep, at each simulated device.
		-- ------------------------------------------------------------------
		for _, device in ipairs(MODAL_DEVICES) do
			workspace:SetAttribute("ForceTouchUI", device.Touch or nil)
			workspace:SetAttribute("UIRegressionViewport", device.Size)
			shade.Visible = true
			task.wait(0.3)
			local layout = UIDevice.Layout()
			local viewport, insetY = device.Size, layout.Inset.Y

			record(layout.Width == device.Size.X and layout.Height == device.Size.Y,
				device.Name .. ": the device override took",
				string.format("%.0fx%.0f", layout.Width, layout.Height))
			record(layout.IsTouch == device.Touch and layout.Class == device.Class
				and layout.Portrait == device.Portrait,
				device.Name .. ": form factor, class and orientation are as declared",
				string.format("touch=%s class=%s portrait=%s",
					tostring(layout.IsTouch), tostring(layout.Class), tostring(layout.Portrait)))

			local panelRect = UIRegression.ResolveRect(panel, viewport, insetY)
			record(panelRect ~= nil and panelRect.Unresolvable == nil,
				device.Name .. ": the modal is analytically resolvable",
				panelRect and panelRect.Unresolvable or "no rect")
			if panelRect and not panelRect.Unresolvable then
				record(panelRect.Left >= -1 and panelRect.Top >= -1
					and panelRect.Right <= viewport.X + 1 and panelRect.Bottom <= viewport.Y + 1,
					device.Name .. ": the modal is fully on screen",
					string.format("x %.0f..%.0f y %.0f..%.0f", panelRect.Left, panelRect.Right,
						panelRect.Top, panelRect.Bottom))
				-- THE assertion the old matrix could not make.
				local zone = device.Touch and UIDevice.OverlapsMovementZone(
					panelRect.Left, panelRect.Top, panelRect.Right, panelRect.Bottom) or nil
				record(zone == nil,
					device.Name .. ": the modal is clear of every movement/control column",
					zone and (zone .. " zone") or nil)
				record(panelRect.Left >= layout.SafeLeft - 1
					and panelRect.Right <= layout.SafeRight + 1,
					device.Name .. ": and inside the horizontal safe area",
					string.format("%.0f..%.0f vs %.0f..%.0f", panelRect.Left, panelRect.Right,
						layout.SafeLeft, layout.SafeRight))
			end

			local rects = {}
			for _, name in ipairs(MODAL_CONTROLS) do
				local control = panel:FindFirstChild(name, true)
				local rect = control and UIRegression.ResolveRect(control, viewport, insetY)
				record(control ~= nil and rect ~= nil and rect.Unresolvable == nil,
					string.format("%s: %s is present and resolvable", device.Name, name),
					control == nil and "missing" or (rect and rect.Unresolvable) or "no rect")
				if control and rect and not rect.Unresolvable then
					rects[name] = rect
					record(control.Visible and control.Active and control.Interactable ~= false,
						string.format("%s: %s is visible, active and interactive", device.Name, name),
						string.format("visible=%s active=%s", tostring(control.Visible), tostring(control.Active)))
					if device.Touch then
						record(rect.Width >= 44 and rect.Height >= 44,
							string.format("%s: %s is at least 44x44", device.Name, name),
							string.format("%.0fx%.0f", rect.Width, rect.Height))
					end
					record(rect.Left >= -1 and rect.Top >= -1
						and rect.Right <= viewport.X + 1 and rect.Bottom <= viewport.Y + 1,
						string.format("%s: %s is on screen", device.Name, name),
						string.format("x %.0f..%.0f y %.0f..%.0f", rect.Left, rect.Right, rect.Top, rect.Bottom))
					local hit = device.Touch and UIDevice.OverlapsMovementZone(
						rect.Left, rect.Top, rect.Right, rect.Bottom) or nil
					record(hit == nil,
						string.format("%s: %s does not overlap a mobile control column",
							device.Name, name), hit and (hit .. " zone") or nil)
					if panelRect and not panelRect.Unresolvable then
						record(rect.Left >= panelRect.Left - 1 and rect.Right <= panelRect.Right + 1
							and rect.Top >= panelRect.Top - 1 and rect.Bottom <= panelRect.Bottom + 1,
							string.format("%s: %s stays inside the modal", device.Name, name))
					end
				end
			end
			-- Pairwise: no two controls may sit on top of each other.
			for indexA = 1, #MODAL_CONTROLS do
				for indexB = indexA + 1, #MODAL_CONTROLS do
					local a, b = rects[MODAL_CONTROLS[indexA]], rects[MODAL_CONTROLS[indexB]]
					if a and b then
						record(not (a.Left < b.Right - 1 and a.Right > b.Left + 1
							and a.Top < b.Bottom - 1 and a.Bottom > b.Top + 1),
							string.format("%s: %s and %s do not overlap", device.Name,
								MODAL_CONTROLS[indexA], MODAL_CONTROLS[indexB]))
					end
				end
			end
			-- No keybinding glyph may reach a touch screen.
			if device.Touch then
				record(UIDevice.SuppressesKeyboardGlyphs(),
					device.Name .. ": keyboard glyphs are suppressed")
			end
		end
	end)

	workspace:SetAttribute("UIRegressionViewport", previousViewport)
	workspace:SetAttribute("ForceTouchUI", previousTouch)
	shade.Visible = wasVisible
	task.wait(0.2)
	if not ran then
		failures += 1
		checks += 1
		table.insert(report, "  FAIL the queue modal matrix ran  (" .. tostring(runError) .. ")")
	end
	record(workspace:GetAttribute("UIRegressionViewport") == previousViewport
		and workspace:GetAttribute("ForceTouchUI") == previousTouch,
		"the matrix restored the simulator attributes it borrowed")
	table.insert(report, string.format("queue modal matrix: %d checks, %d failed", checks, failures))
	return table.concat(report, "\n"), failures
end

-- ---------------------------------------------------------------------------
-- Briefing text fit, resolved per device
-- ---------------------------------------------------------------------------
--
-- The dispatch panel is the one place in the HUD where the layout sizes a
-- rectangle and something else entirely fills it with a sentence. RoundUI's
-- `updateLevelOneGuideLayout` reserves the subtitle box arithmetically --
-- `textTop = math.max(28, controlsTop + controlsHeight + (touch and 0 or 2))`,
-- RoundUI L2425 -- and on a TOUCH row that picks OwnBand with two 44px columns
-- that lands the box top at exactly y = 74, the same pixel where the MUTE/STOP
-- row ends. Nothing hard-codes 74; it falls out of the arithmetic, and the two
-- rectangles ABUT by design. Abutment is fine. One pixel of real penetration is
-- the defect this file already exists to catch, and neither case was ever
-- asserted anywhere but at whatever viewport Studio happened to be rendering.
--
-- Worse, the boxes were the only thing ever checked. Whether the COPY fits the
-- box it was handed had exactly one automated assertion -- `TextFitTargets`
-- inside RunAll -- and that one reads the engine's `TextBounds` PROPERTY, which
-- can only describe the string currently on screen at the size currently
-- rendered. RunAll also refuses to start while `UIRegressionViewport` is set,
-- so it can never speak about any viewport but the real one. Every claim that
-- a 113-character cue fits on a 568x320 phone came from a human looking at the
-- Device Simulator.
--
-- This matrix asks arithmetically instead: ResolveRect for the boxes,
-- TextService:GetTextBoundsAsync for the copy. It is deliberately pessimistic
-- about what it may resolve. `BriefingControls` holds a UIListLayout, so the
-- two buttons inside it are ENGINE-placed and ResolveRect correctly refuses
-- them -- so the CONTAINER is resolved, and the buttons are measured against
-- its resolved extent and the list layout's own declared padding, rather than
-- pretending the resolver can place what the engine places.

-- LOCALISATION STRESS CORPUS.
--
-- This is a PROXY for the shipped copy, not a mirror of it. UIRegression lives
-- in ReplicatedStorage and the cues live in a LocalScript under
-- StarterPlayerScripts, which cannot be required from here, so the strings are
-- transcribed by hand and MUST be re-synced when the cue tables change. Their
-- sources, all in StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua:
--
--   L1917-1932  briefingCues             -- Level 1
--   L1934-1949  levelTwoBriefingCues     -- Level 2
--   L1952-1971  levelThreeBriefing.cues  -- Level 3
--   L1525-1543  lobbyBriefing.cues       -- the concourse briefing
--
-- The longest authored line across all four tables is RoundUI L1940 at 113
-- characters, and it is reproduced here verbatim. LONG_DISPATCH_CUE (L610 of
-- this file, 142 characters) is the string the live `briefing` scenario already
-- forces into the panel, so both matrices stress the same worst case. The third
-- entry is SYNTHETIC: 181 characters, 1.60x the longest authored line, standing
-- in for a localisation of it. German is the useful shape here -- the same
-- sentence runs long AND carries compounds the wrapper cannot break.
local BRIEFING_STRESS_CORPUS = {
	{
		Name = "the longest authored cue (RoundUI L1940, 113 chars)",
		Text = "Even more important: activating a pump appears to alert an unidentified, unusually large entity to your location.",
	},
	{
		Name = "LONG_DISPATCH_CUE (142 chars)",
		Text = LONG_DISPATCH_CUE,
	},
	{
		Name = "a synthetic 1.60x localisation (181 chars)",
		Text = "Noch wichtiger: das Aktivieren einer Pumpstation alarmiert offenbar eine bislang nicht identifizierte, ungewoehnlich grosse Entitaet und verraet ihr eure derzeitige Position sofort.",
	},
}

-- Every caption the two readouts can actually print, from RoundUI's
-- `dispatchAudio.refresh` (L128-165). "SAVING" is omitted deliberately: it is
-- strictly shorter than the four below and cannot fail a width they pass. The
-- "[M]" / "[N]" prefixes come from UIDevice.Binding and are never emitted on a
-- touch form factor, so they are prepended only on the desktop rows.
local BRIEFING_CONTROL_CAPTIONS = {
	DispatchMuteButton = {
		Binding = "[M]  ",
		Captions = {"MUTE DISPATCH", "UNMUTE DISPATCH", "LOADING DISPATCH", "DISPATCH OFFLINE"},
	},
	DispatchStopButton = {
		Binding = "[N]  ",
		Captions = {"STOP DISPATCH"},
	},
}
local BRIEFING_CONTROL_ORDER = {"DispatchMuteButton", "DispatchStopButton"}

-- The rows of MODAL_DEVICES this matrix sweeps: every PORTRAIT row, plus the
-- four short landscape shapes where the panel has the least vertical room and
-- the layout is driven into its compromise pass. Landscape rows are keyed by
-- size rather than by device name, so a renamed row cannot silently drop out.
local BRIEFING_LANDSCAPE_ROWS = {
	["705x338"] = true,  -- Galaxy A06, the shape the panel shipped broken on
	["568x320"] = true,  -- the smallest viewport in the matrix
	["844x390"] = true,  -- iPhone landscape
	["667x375"] = true,  -- iPhone SE landscape
}

local function briefingDevices(): {any}
	local rows = {}
	for _, device in ipairs(MODAL_DEVICES) do
		local key = string.format("%.0fx%.0f", device.Size.X, device.Size.Y)
		if device.Portrait or BRIEFING_LANDSCAPE_ROWS[key] then
			table.insert(rows, device)
		end
	end
	return rows
end

-- The overlap predicate for ANALYTICAL rects.
--
-- `rectsOverlap` above carries a one-pixel slack in every direction, and it is
-- right to: it compares MEASURED AbsolutePosition, where a shared edge can
-- round into a pixel of apparent penetration. These rects are not measured,
-- they are exact arithmetic over the UDim2 values production sets, so the same
-- slack would swallow a genuine one-pixel collision -- precisely the failure
-- this matrix exists to find, given the subtitle box is authored to land ON the
-- controls' lower edge. Half-open comparison instead, which is what the
-- rectsOverlap COMMENT describes: a shared edge (subtitle top 74, controls
-- bottom 74) is abutment and passes; one pixel of real penetration (subtitle
-- top 73) is an overlap and fails.
local function analyticalOverlap(a: any, b: any): boolean
	return a.Left < b.Right and a.Right > b.Left
		and a.Top < b.Bottom and a.Bottom > b.Top
end

function UIRegression.BriefingFitMatrix(): (string, number)
	local previousViewport = workspace:GetAttribute("UIRegressionViewport")
	local previousTouch = workspace:GetAttribute("ForceTouchUI")
	local report = {"=== briefing text fit, resolved per device ==="}
	local failures, checks = 0, 0
	local function record(ok, description, detail)
		checks += 1
		if ok then
			table.insert(report, "  ok   " .. description)
		else
			failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
		end
	end

	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	local guide = gui and gui:FindFirstChild("LevelOneGuideGui")
	local panel = guide and guide:FindFirstChild("CommandSubtitles")
	local subtitle = panel and panel:FindFirstChild("Subtitle")
	local controls = panel and panel:FindFirstChild("BriefingControls")
	local listLayout = controls and controls:FindFirstChildOfClass("UIListLayout")
	local buttons = {}
	for _, name in ipairs(BRIEFING_CONTROL_ORDER) do
		buttons[name] = controls and controls:FindFirstChild(name)
	end
	if not (guide and panel and subtitle and controls and listLayout
		and buttons.DispatchMuteButton and buttons.DispatchStopButton) then
		record(false, "the briefing panel exists to be measured", string.format(
			"guide=%s panel=%s subtitle=%s controls=%s layout=%s mute=%s stop=%s",
			tostring(guide ~= nil), tostring(panel ~= nil), tostring(subtitle ~= nil),
			tostring(controls ~= nil), tostring(listLayout ~= nil),
			tostring(buttons.DispatchMuteButton ~= nil),
			tostring(buttons.DispatchStopButton ~= nil)))
		table.insert(report, string.format("TOTAL: %d checks, %d failed", checks, failures))
		return table.concat(report, "\n"), failures
	end

	-- GetTextBoundsAsync yields and can throw (a font that has not finished
	-- loading, a malformed params object). It is called from this matrix's own
	-- thread, and every call is wrapped, so a service hiccup is reported as a
	-- failed check rather than unwinding the sweep and stranding the override.
	--
	-- `width` is the WRAP width and is passed only for text that actually wraps.
	-- GetTextBoundsParams.Width defaults to infinity, and leaving it there is the
	-- correct model for the two readouts: TextWrapped is false on them, so the
	-- engine lays them out on one line and lets them spill. Handing the params a
	-- width would have wrapped the measurement the engine never wraps, reporting
	-- a caption that overruns its hitbox as comfortably inside it.
	local function requiredBounds(text, fontFace, size, width)
		local params = Instance.new("GetTextBoundsParams")
		params.Text = text
		params.Font = fontFace
		params.Size = size
		if width then params.Width = width end
		local ok, result = pcall(function()
			return TextService:GetTextBoundsAsync(params)
		end)
		if ok and typeof(result) == "Vector2" then return result, nil end
		return nil, tostring(result)
	end

	-- One cast each, up front. Everything below writes through these, so no
	-- assignment target in this function is a parenthesised cast.
	local screen = guide :: any
	local panelObject = panel :: any
	local controlsObject = controls :: any
	local subtitleLabel = subtitle :: any
	local wasEnabled = screen.Enabled
	local wasPanelVisible = panelObject.Visible
	local wasControlsVisible = controlsObject.Visible
	local ran, runError = pcall(function()
		-- ------------------------------------------------------------------
		-- CALIBRATION. The sweep below never measures anything: it computes.
		-- A resolver that is wrong in the same direction as the layout it
		-- checks reports green for a broken panel, so before any simulated
		-- viewport is touched, prove the resolver reproduces the ENGINE at the
		-- REAL viewport -- the one place AbsolutePosition is trustworthy --
		-- within one pixel, for the panel, the subtitle box and the controls
		-- row. If it does not, that is a recorded FAILURE and this matrix is
		-- already red no matter what the sweep goes on to say.
		-- ------------------------------------------------------------------
		workspace:SetAttribute("UIRegressionViewport", nil)
		workspace:SetAttribute("ForceTouchUI", nil)
		screen.Enabled = true
		panelObject.Visible = true
		controlsObject.Visible = true
		task.wait(0.35)
		local realLayout = UIDevice.Layout()
		local shift = UIRegression.ScreenSpaceShift(panel)
		local worst, worstName = 0, ""
		for _, object in ipairs({panel, subtitle, controls}) do
			local resolved = UIRegression.ResolveRect(object, realLayout.Viewport, realLayout.Inset.Y)
			local node = object :: any
			if resolved and not resolved.Unresolvable then
				local live = {
					Left = node.AbsolutePosition.X,
					Top = node.AbsolutePosition.Y + shift,
					Right = node.AbsolutePosition.X + node.AbsoluteSize.X,
					Bottom = node.AbsolutePosition.Y + node.AbsoluteSize.Y + shift,
				}
				for _, edge in ipairs({"Left", "Top", "Right", "Bottom"}) do
					local delta = math.abs(resolved[edge] - live[edge])
					if delta > worst then worst, worstName = delta, object.Name .. "." .. edge end
				end
			else
				worst = math.huge
				worstName = object.Name .. " is unresolvable at the real viewport"
			end
		end
		record(worst <= 1,
			"the resolver agrees with the engine at the real viewport, for the panel,"
			.. " the Subtitle box and the BriefingControls row",
			string.format("worst edge error %.2fpx at %s", worst, worstName))

		-- ------------------------------------------------------------------
		-- The sweep, at each simulated device.
		-- ------------------------------------------------------------------
		for _, device in ipairs(briefingDevices()) do
			workspace:SetAttribute("ForceTouchUI", device.Touch or nil)
			workspace:SetAttribute("UIRegressionViewport", device.Size)
			screen.Enabled = true
			panelObject.Visible = true
			controlsObject.Visible = true
			-- Long enough for UIDevice's attribute watcher to refresh, fire
			-- Changed, and for RoundUI's updateLevelOneGuideLayout to have
			-- written every Size, Position and TextSize this row depends on.
			task.wait(0.3)
			local layout = UIDevice.Layout()
			local viewport, insetY = device.Size, layout.Inset.Y

			record(layout.Width == device.Size.X and layout.Height == device.Size.Y,
				device.Name .. ": the device override took",
				string.format("%.0fx%.0f", layout.Width, layout.Height))
			record(layout.IsTouch == device.Touch and layout.Class == device.Class
				and layout.Portrait == device.Portrait,
				device.Name .. ": form factor, class and orientation are as declared",
				string.format("touch=%s class=%s portrait=%s",
					tostring(layout.IsTouch), tostring(layout.Class), tostring(layout.Portrait)))

			local panelRect = UIRegression.ResolveRect(panel, viewport, insetY)
			local subtitleRect = UIRegression.ResolveRect(subtitle, viewport, insetY)
			local controlsRect = UIRegression.ResolveRect(controls, viewport, insetY)
			-- Unresolvable is a FAILURE, never a skip. An analytical matrix that
			-- quietly stops asserting the moment it meets something it cannot
			-- compute is the old false green wearing a new report format.
			record(panelRect ~= nil and panelRect.Unresolvable == nil,
				device.Name .. ": the briefing panel is analytically resolvable",
				panelRect and panelRect.Unresolvable or "no rect")
			record(subtitleRect ~= nil and subtitleRect.Unresolvable == nil,
				device.Name .. ": the Subtitle box is analytically resolvable",
				subtitleRect and subtitleRect.Unresolvable or "no rect")
			record(controlsRect ~= nil and controlsRect.Unresolvable == nil,
				device.Name .. ": the BriefingControls row is analytically resolvable",
				controlsRect and controlsRect.Unresolvable or "no rect")

			local havePanel = panelRect ~= nil and panelRect.Unresolvable == nil
			local haveSubtitle = subtitleRect ~= nil and subtitleRect.Unresolvable == nil
			local haveControls = controlsRect ~= nil and controlsRect.Unresolvable == nil

			-- ── the panel against the WORLD, not just against itself ─────────
			-- WHAT SHIPPED BROKEN: every assertion in this matrix compared the
			-- panel's children to the panel. Nothing compared the PANEL to the
			-- screen, to UIDevice's TopBand, or to a movement zone -- so a panel
			-- that grew straight out of its band and down into the thumbstick's
			-- activation region read GREEN. Proven by mutation: removing the
			-- BAND_CEILING clamp in RoundUI changed not one check here.
			local deviceLayout = UIDevice.Layout()
			local band = deviceLayout.TopBand
			record(havePanel
				and panelRect.Left >= -1 and panelRect.Top >= -1
				and panelRect.Right <= viewport.X + 1
				and panelRect.Bottom <= viewport.Y + 1,
				device.Name .. ": the briefing panel is entirely on screen",
				havePanel and string.format("x %.0f..%.0f y %.0f..%.0f",
					panelRect.Left, panelRect.Right, panelRect.Top, panelRect.Bottom) or "no rect")
			if device.Touch and band and band.Height and band.Height > 0 then
				-- SPACES. ResolveRect returns TRUE SCREEN coordinates (it adds the
				-- GUI inset itself for an inset-respecting ScreenGui), while
				-- UIDevice's TopBand and movement zones are expressed in the same
				-- space AbsolutePosition uses -- which excludes that inset. Compare
				-- them directly and every panel reads exactly one inset too low:
				-- the first version of this check called a correctly band-fitted
				-- panel a violation on four devices, because 124 - 58 is 66 and 66
				-- is precisely where the band starts. Convert once, here.
				local guiTop = panelRect.Top - insetY
				local guiBottom = panelRect.Bottom - insetY
				record(havePanel
					and guiTop >= band.Top - 1
					and guiBottom <= band.Top + band.Height + 1
					and panelRect.Left >= band.Left - 1
					and panelRect.Right <= band.Left + band.Width + 1,
					device.Name .. ": and fits inside UIDevice's TopBand",
					havePanel and string.format("panel y %.0f..%.0f vs band y %.0f..%.0f",
						guiTop, guiBottom, band.Top, band.Top + band.Height) or "no rect")
				local zone = havePanel and UIDevice.OverlapsMovementZone(
					panelRect.Left, guiTop, panelRect.Right, guiBottom) or nil
				record(havePanel and zone == nil,
					device.Name .. ": and enters no movement zone",
					tostring(zone))
			end

			record(havePanel and haveSubtitle
				and subtitleRect.Left >= panelRect.Left - 1
				and subtitleRect.Right <= panelRect.Right + 1
				and subtitleRect.Top >= panelRect.Top - 1
				and subtitleRect.Bottom <= panelRect.Bottom + 1,
				device.Name .. ": the Subtitle box stays inside the panel",
				(havePanel and haveSubtitle) and string.format(
					"subtitle x %.0f..%.0f y %.0f..%.0f in panel x %.0f..%.0f y %.0f..%.0f",
					subtitleRect.Left, subtitleRect.Right, subtitleRect.Top, subtitleRect.Bottom,
					panelRect.Left, panelRect.Right, panelRect.Top, panelRect.Bottom)
					or "unresolvable")
			record(havePanel and haveControls
				and controlsRect.Left >= panelRect.Left - 1
				and controlsRect.Right <= panelRect.Right + 1
				and controlsRect.Top >= panelRect.Top - 1
				and controlsRect.Bottom <= panelRect.Bottom + 1,
				device.Name .. ": the BriefingControls row stays inside the panel",
				(havePanel and haveControls) and string.format(
					"controls x %.0f..%.0f y %.0f..%.0f in panel x %.0f..%.0f y %.0f..%.0f",
					controlsRect.Left, controlsRect.Right, controlsRect.Top, controlsRect.Bottom,
					panelRect.Left, panelRect.Right, panelRect.Top, panelRect.Bottom)
					or "unresolvable")
			-- THE assertion this matrix was written for. Abutment passes, one
			-- pixel of penetration does not; see analyticalOverlap above.
			record(haveSubtitle and haveControls
				and not analyticalOverlap(subtitleRect, controlsRect),
				device.Name .. ": the Subtitle box does not overlap the MUTE/STOP row",
				(haveSubtitle and haveControls) and string.format(
					"subtitle (%.0f,%.0f)-(%.0f,%.0f) vs controls (%.0f,%.0f)-(%.0f,%.0f)",
					subtitleRect.Left, subtitleRect.Top, subtitleRect.Right, subtitleRect.Bottom,
					controlsRect.Left, controlsRect.Top, controlsRect.Right, controlsRect.Bottom)
					or "unresolvable")

			-- ---------------------------------------------------------------
			-- The controls row. Its CHILDREN are placed by the UIListLayout, so
			-- they are honestly out of the resolver's reach. Their SIZE is not:
			-- updateLevelOneGuideLayout writes it directly as an offset, and a
			-- UIListLayout never resizes what it arranges. So size is computed,
			-- position is not claimed, and the pair is checked against the
			-- container's own resolved extent plus the layout's declared padding
			-- along whichever axis the layout is filling on this row.
			-- ---------------------------------------------------------------
			local horizontal = listLayout.FillDirection == Enum.FillDirection.Horizontal
			local sizes = {}
			for _, name in ipairs(BRIEFING_CONTROL_ORDER) do
				local button = buttons[name] :: any
				local width = button.Size.X.Offset
					+ button.Size.X.Scale * (haveControls and controlsRect.Width or 0)
				local height = button.Size.Y.Offset
					+ button.Size.Y.Scale * (haveControls and controlsRect.Height or 0)
				sizes[name] = {Width = width, Height = height}
				if device.Touch then
					-- The compact fallback now gives up ornamental padding instead
					-- of input area, so even the 568x320 band keeps the game's 44px
					-- touch-target contract.
					record(width >= 44 and height >= 44,
						string.format("%s: %s is at least 44x44", device.Name, name),
						string.format("%.0fx%.0f", width, height))
				end
			end
			local padding = haveControls and (listLayout.Padding.Offset
				+ listLayout.Padding.Scale
					* (horizontal and controlsRect.Width or controlsRect.Height)) or 0
			local mute, stop = sizes.DispatchMuteButton, sizes.DispatchStopButton
			local along = horizontal and (mute.Width + stop.Width + padding)
				or (mute.Height + stop.Height + padding)
			local across = horizontal and math.max(mute.Height, stop.Height)
				or math.max(mute.Width, stop.Width)
			local alongLimit = haveControls
				and (horizontal and controlsRect.Width or controlsRect.Height) or 0
			local acrossLimit = haveControls
				and (horizontal and controlsRect.Height or controlsRect.Width) or 0
			record(haveControls and along <= alongLimit + 1 and across <= acrossLimit + 1,
				device.Name .. ": both readouts and the list padding fit inside BriefingControls",
				string.format("%s fill: %.0f + %.0f padding along %.0f, %.0f across %.0f",
					horizontal and "horizontal" or "vertical",
					along - padding, padding, alongLimit, across, acrossLimit))

			-- Every caption the readouts can print, at the TextSize this row's
			-- layout pass just wrote. A readout whose word does not fit its own
			-- transparent hitbox is the same defect as a clipped subtitle, one
			-- rectangle further in.
			for _, name in ipairs(BRIEFING_CONTROL_ORDER) do
				local button = buttons[name] :: any
				local spec = BRIEFING_CONTROL_CAPTIONS[name]
				local prefix = device.Touch and "" or spec.Binding
				for _, caption in ipairs(spec.Captions) do
					local text = prefix .. caption
					local bounds, boundsError = requiredBounds(
						text, button.FontFace, button.TextSize, nil)
					record(bounds ~= nil and bounds.X <= sizes[name].Width + 1
						and bounds.Y <= sizes[name].Height + 1,
						string.format("%s: %s fits %q", device.Name, name, text),
						bounds and string.format("needs %.0fx%.0f in %.0fx%.0f at TextSize %d",
							bounds.X, bounds.Y, sizes[name].Width, sizes[name].Height,
							button.TextSize) or boundsError)
				end
			end

			-- ---------------------------------------------------------------
			-- The copy itself. TextWrapped is true, so the wrap width IS the
			-- resolved box width, and the question is then whether the wrapped
			-- block comes out TALLER than the box the layout reserved -- which
			-- is what clipping looks like from the arithmetic side.
			-- ---------------------------------------------------------------
			for _, entry in ipairs(BRIEFING_STRESS_CORPUS) do
				local description = string.format("%s: %s fits the Subtitle box",
					device.Name, entry.Name)
				if not haveSubtitle then
					-- Same check, same count, still a failure. A row that could
					-- not resolve its box does not get to skip the fit question.
					record(false, description, "the Subtitle box is unresolvable")
				else
					local bounds, boundsError = requiredBounds(entry.Text,
						subtitleLabel.FontFace, subtitleLabel.TextSize, subtitleRect.Width)
					record(bounds ~= nil
						and bounds.X <= subtitleRect.Width + 1
						and bounds.Y <= subtitleRect.Height + 1,
						description,
						bounds and string.format("needs %.0fx%.0f in %.0fx%.0f at TextSize %d",
							bounds.X, bounds.Y, subtitleRect.Width, subtitleRect.Height,
							subtitleLabel.TextSize) or boundsError)
				end
			end
		end
	end)

	workspace:SetAttribute("UIRegressionViewport", previousViewport)
	workspace:SetAttribute("ForceTouchUI", previousTouch)
	screen.Enabled = wasEnabled
	panelObject.Visible = wasPanelVisible
	controlsObject.Visible = wasControlsVisible
	task.wait(0.2)
	if not ran then
		failures += 1
		checks += 1
		table.insert(report, "  FAIL the briefing fit matrix ran  (" .. tostring(runError) .. ")")
	end
	record(workspace:GetAttribute("UIRegressionViewport") == previousViewport
		and workspace:GetAttribute("ForceTouchUI") == previousTouch,
		"the matrix restored the simulator attributes it borrowed")
	table.insert(report, string.format("TOTAL: %d checks, %d failed", checks, failures))
	return table.concat(report, "\n"), failures
end

-- ---------------------------------------------------------------------------
-- BriefingExclusionMatrix -- briefing, queue modal and the full Zyntra terminal
-- ---------------------------------------------------------------------------
--
-- WHAT SHIPPED BROKEN, in pixels, at 705x338: the Zyntra opener occupied
-- (345,66)-(529,110), which is ENTIRELY inside the dispatch briefing panel
-- (12,66)-(529,141) and overlaps its MUTE/STOP row by 172x42. The briefing
-- panel in turn overlapped QueueHostPanel (290,66)-(529,326) by 239x75 and
-- covered its CloseQueue button completely. The panel draws above both
-- (DisplayOrder 110 against RoundGui 100 and ZyntraStore 55) and is opaque at
-- BackgroundTransparency .18 -- but its Frame is not Active, so a tap that
-- missed MUTE or STOP fell straight through onto a button the player could not
-- see. On a phone that is the entire top strip of the screen.
--
-- The rule is now one expression in one place (RoundUI's dispatchAudio.refresh),
-- published as the player attribute DispatchBriefingOpen. Queue always wins;
-- an already-open terminal suppresses only the panel while the transmission
-- keeps running. This matrix drives each state machine in BOTH orders because a
-- flag that is only ever set one way round is a flag that sticks.
--
-- Three things are asserted that a "does the panel hide" test would not:
--
--   * ZyntraDispatchClientActive must NOT follow DispatchBriefingOpen. The
--     transmission keeps running while its panel is suppressed; if it were torn
--     down, claimLobbyBriefing's one-shot claim would be burned by opening a
--     modal and the player would never hear the briefing at all.
--   * the suppression is UNCONDITIONAL, not touch-only, so the sweep runs at a
--     desktop viewport as well as at the phone.
--   * no rect anywhere under CommandSubtitles may intersect any rect anywhere
--     under QueueHostShade, in any state -- descendants included, because the
--     overlap that shipped was between two CHILDREN, not the two panels.
--
-- Then the developer-page captions, which are a different fault with the same
-- shape: they were chosen by UIDevice.IsTouch(), so a handheld that reports a
-- keyboard -- a tablet with a case, a hybrid -- was told to press J, B, V, P,
-- I, U and C on a device with no keys. They now follow
-- UIDevice.SuppressesKeyboardGlyphs(), which is true for EITHER touch input or
-- a handheld form factor, and they are re-rendered on UIDevice.Changed rather
-- than only at build time.
local BRIEFING_EXCLUSION_VIEWPORTS = {
	{Name = "phone-landscape", Size = Vector2.new(705, 338), Touch = true},
	{Name = "desktop", Size = nil, Touch = false},
}

-- command -> the key the caption must name when glyphs are shown. Mirrored by
-- hand from ZyntraStore's control table so a silent rebinding fails here.
-- B really does drive esp and fastQueue together (DevCheats' InputBegan toggles
-- both), so the repeat is correct and must not be "fixed".
local DEV_CAPTION_KEYS = {
	{Command = "esp", Key = "B"},
	{Command = "fastQueue", Key = "B"},
	{Command = "noclip", Key = "V"},
	{Command = "pauseEntity", Key = "P"},
	{Command = "immunePush", Key = "I"},
	{Command = "unlimited", Key = "U"},
	{Command = "thirdPerson", Key = "C"},
	{Command = "level3PreBlackout", Key = "K"},
}
local DEV_INTRO_BASE = "WHITELISTED DEVELOPER CONTROLS"
local DEV_INTRO_KEYBOARD = DEV_INTRO_BASE .. "  //  PHONE: J"
local DEV_NOCLIP_KEYBOARD = "Fly through geometry with WASD, Space and Left Ctrl."
local DEV_NOCLIP_TOUCH = "Fly through geometry using the movement stick."

function UIRegression.BriefingExclusionMatrix(): (string, number)
	local report = {"=== briefing / queue modal / full Zyntra terminal exclusion ==="}
	local failures, checks = 0, 0
	local function record(ok, description, detail)
		checks += 1
		if ok then
			table.insert(report, "  ok   " .. description)
		else
			failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
		end
	end

	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		record(false, "there is a PlayerGui to measure")
		return table.concat(report, "\n"), failures
	end
	local function find(name)
		for _, descendant in ipairs(gui:GetDescendants()) do
			if descendant.Name == name then return descendant end
		end
		return nil
	end
	local subtitles = find("CommandSubtitles")
	local opener = find("ZyntraOpenButton")
	local shade = find("QueueHostShade")
	local store = gui:FindFirstChild("ZyntraStore")
	local terminal = store and store:FindFirstChild("Terminal")
	local storeProbe = store and store:FindFirstChild("UIRegressionZyntraStoreProbe")
	if not (subtitles and opener and shade and terminal and storeProbe
		and storeProbe:IsA("BindableFunction")) then
		record(false, "the briefing, queue modal, store opener, terminal and Studio probe all exist",
			string.format("subtitles=%s opener=%s shade=%s terminal=%s probe=%s",
				tostring(subtitles ~= nil), tostring(opener ~= nil), tostring(shade ~= nil),
				tostring(terminal ~= nil), tostring(storeProbe ~= nil)))
		return table.concat(report, "\n"), failures
	end

	local previousViewport = workspace:GetAttribute("UIRegressionViewport")
	local previousTouch = workspace:GetAttribute("ForceTouchUI")
	local previousShade = shade.Visible
	local previousForce = player:GetAttribute("UIRegressionForceDispatchActive")
	local previousSuppress = player:GetAttribute("UIRegressionSuppressDispatch")
	local previousTerminal = terminal.Visible

	-- brief/modal are what this matrix ASKS for; the rest is what must follow.
	-- The order is the point: rows 2-3 raise the modal over a running briefing
	-- and take it away again, rows 5-6 raise a briefing under a modal that is
	-- already up. A one-directional flag passes one half and fails the other.
	local STATES = {
		{Label = "idle", Force = false, Shade = false,
			Brief = false, Subs = false, Opener = true, Transmission = false},
		{Label = "briefing only", Force = true, Shade = false,
			Brief = true, Subs = true, Opener = false, Transmission = true},
		{Label = "modal opened over a live briefing", Force = true, Shade = true,
			Brief = false, Subs = false, Opener = false, Transmission = true},
		{Label = "modal closed, briefing still running", Force = true, Shade = false,
			Brief = true, Subs = true, Opener = false, Transmission = true},
		{Label = "briefing cleared", Force = false, Shade = false,
			Brief = false, Subs = false, Opener = true, Transmission = false},
		{Label = "modal only", Force = false, Shade = true,
			Brief = false, Subs = false, Opener = false, Transmission = false},
		{Label = "briefing raised while the modal is up", Force = true, Shade = true,
			Brief = false, Subs = false, Opener = false, Transmission = true},
	}

	local ran, runError = pcall(function()
		-- A Studio session comes up with the first-login lobby briefing already
		-- running, so clearing the force flag does NOT reach an idle screen --
		-- the panel stays up, driven by a transmission this module has no handle
		-- on. Every "briefing off" row below would then be asserting against a
		-- real briefing. This suppresses the AMBIENT transmission for the length
		-- of the sweep and is restored on every exit path; the force flag still
		-- drives the "briefing on" rows exactly as before.
		player:SetAttribute("UIRegressionSuppressDispatch", true)
		storeProbe:Invoke("close")
		task.wait(.3)
		record(player:GetAttribute("DispatchBriefingOpen") ~= true
			and subtitles.Visible == false,
			"the sweep starts from a genuinely idle screen, not from whatever"
			.. " briefing this session happened to be playing",
			string.format("brief=%s subtitles=%s",
				tostring(player:GetAttribute("DispatchBriefingOpen")),
				tostring(subtitles.Visible)))

		for _, device in ipairs(BRIEFING_EXCLUSION_VIEWPORTS) do
			workspace:SetAttribute("ForceTouchUI", device.Touch or nil)
			workspace:SetAttribute("UIRegressionViewport", device.Size)
			-- Back to a known floor before each sweep, so a state left behind by
			-- the previous device cannot make the first row of this one pass.
			player:SetAttribute("UIRegressionForceDispatchActive", nil)
			shade.Visible = false
			storeProbe:Invoke("close")
			task.wait(.35)

			for _, state in ipairs(STATES) do
				player:SetAttribute("UIRegressionForceDispatchActive",
					state.Force and true or nil)
				shade.Visible = state.Shade
				task.wait(.3)
				local label = device.Name .. " / " .. state.Label

				record(player:GetAttribute("DispatchBriefingOpen") == state.Brief
					and player:GetAttribute("QueueModalOpen") == state.Shade,
					label .. ": the two published flags say what the screen is doing",
					string.format("brief=%s (want %s), modal=%s (want %s)",
						tostring(player:GetAttribute("DispatchBriefingOpen")),
						tostring(state.Brief),
						tostring(player:GetAttribute("QueueModalOpen")),
						tostring(state.Shade)))

				-- The flag and the pixels come from ONE expression; this is what
				-- makes that worth asserting rather than assuming.
				record(subtitles.Visible == state.Subs,
					label .. ": the briefing panel is drawn exactly when the flag says so",
					string.format("Visible=%s, want %s", tostring(subtitles.Visible),
						tostring(state.Subs)))

				-- SetInteractive clears Visible AND Active AND Selectable, so the
				-- opener leaves the input stack rather than merely going invisible
				-- underneath an opaque panel -- which is what shipped.
				record(opener.Visible == state.Opener and opener.Active == state.Opener,
					label .. ": the store opener is gone from the screen AND from the"
					.. " input stack whenever anything is over it",
					string.format("Visible=%s Active=%s, want %s",
						tostring(opener.Visible), tostring(opener.Active),
						tostring(state.Opener)))

				record(
					(player:GetAttribute("ZyntraDispatchClientActive") == true)
						== state.Transmission,
					label .. ": the transmission itself is untouched -- suppressing the"
					.. " panel must never end the briefing",
					string.format("ZyntraDispatchClientActive=%s, want %s",
						tostring(player:GetAttribute("ZyntraDispatchClientActive")),
						tostring(state.Transmission)))

				-- Geometry, descendants included: the overlap that shipped was
				-- between two CHILDREN of these two trees, not between the two
				-- panels, so comparing only the roots would have missed it.
				local worst, worstPair = 0, ""
				for _, a in ipairs(subtitles:GetDescendants()) do
					if a:IsA("GuiObject") and visibleChain(a) then
						for _, b in ipairs(shade:GetDescendants()) do
							if b:IsA("GuiObject") and visibleChain(b) then
								local overlapX = math.min(
									a.AbsolutePosition.X + a.AbsoluteSize.X,
									b.AbsolutePosition.X + b.AbsoluteSize.X)
									- math.max(a.AbsolutePosition.X, b.AbsolutePosition.X)
								local overlapY = math.min(
									a.AbsolutePosition.Y + a.AbsoluteSize.Y,
									b.AbsolutePosition.Y + b.AbsoluteSize.Y)
									- math.max(a.AbsolutePosition.Y, b.AbsolutePosition.Y)
								local area = math.max(0, overlapX) * math.max(0, overlapY)
								if area > worst then
									worst = area
									worstPair = a.Name .. " x " .. b.Name
								end
							end
						end
					end
				end
				record(worst == 0,
					label .. ": nothing under the briefing panel overlaps anything under"
					.. " the queue modal",
					string.format("%.0f px^2 at %s", worst, worstPair))
			end
		end

		-- ------------------------------------------------------------------
		-- The full terminal participates, not only its lobby opener.
		-- ------------------------------------------------------------------
		workspace:SetAttribute("UIRegressionViewport", nil)
		workspace:SetAttribute("ForceTouchUI", nil)
		player:SetAttribute("UIRegressionForceDispatchActive", nil)
		shade.Visible = false
		storeProbe:Invoke("close")
		task.wait(.35)
		record(player:GetAttribute("DispatchBriefingOpen") ~= true
			and opener.Visible == true and opener.Active == true,
			"and it ends back at an idle screen with the store opener returned to"
			.. " the input stack -- the suppression is not one-way",
			string.format("brief=%s opener.Visible=%s opener.Active=%s",
				tostring(player:GetAttribute("DispatchBriefingOpen")),
				tostring(opener.Visible), tostring(opener.Active)))

		local opened = storeProbe:Invoke("open")
		task.wait(.2)
		record(opened == true and terminal.Visible == true
			and player:GetAttribute("ZyntraStoreOpen") == true,
			"idle: the production toggle opens the terminal and publishes its modal state",
			string.format("Invoke=%s Visible=%s attribute=%s", tostring(opened),
				tostring(terminal.Visible), tostring(player:GetAttribute("ZyntraStoreOpen"))))

		player:SetAttribute("UIRegressionForceDispatchActive", true)
		task.wait(.3)
		record(player:GetAttribute("ZyntraDispatchClientActive") == true
			and player:GetAttribute("DispatchBriefingOpen") ~= true
			and subtitles.Visible == false and terminal.Visible == true,
			"terminal already open: RoundUI keeps transmission alive but yields its panel",
			string.format("active=%s brief=%s subtitles=%s terminal=%s",
				tostring(player:GetAttribute("ZyntraDispatchClientActive")),
				tostring(player:GetAttribute("DispatchBriefingOpen")),
				tostring(subtitles.Visible), tostring(terminal.Visible)))

		storeProbe:Invoke("close")
		task.wait(.3)
		record(terminal.Visible == false and player:GetAttribute("ZyntraStoreOpen") ~= true
			and player:GetAttribute("DispatchBriefingOpen") == true and subtitles.Visible == true,
			"closing the terminal restores the still-running briefing",
			string.format("store=%s brief=%s subtitles=%s",
				tostring(player:GetAttribute("ZyntraStoreOpen")),
				tostring(player:GetAttribute("DispatchBriefingOpen")), tostring(subtitles.Visible)))

		local toggleDuringBrief = storeProbe:Invoke("open")
		local kioskDuringBrief = storeProbe:Invoke("kiosk")
		task.wait(.2)
		record(toggleDuringBrief == false and kioskDuringBrief == false
			and terminal.Visible == false and player:GetAttribute("ZyntraStoreOpen") ~= true,
			"briefing already open: both toggle and kiosk paths refuse the terminal",
			string.format("toggle=%s kiosk=%s Visible=%s", tostring(toggleDuringBrief),
				tostring(kioskDuringBrief), tostring(terminal.Visible)))

		player:SetAttribute("UIRegressionForceDispatchActive", nil)
		task.wait(.3)
		storeProbe:Invoke("open")
		task.wait(.2)
		shade.Visible = true
		task.wait(.3)
		record(terminal.Visible == false and player:GetAttribute("ZyntraStoreOpen") ~= true,
			"queue raised over an open terminal closes the full terminal and clears its state",
			string.format("Visible=%s attribute=%s", tostring(terminal.Visible),
				tostring(player:GetAttribute("ZyntraStoreOpen"))))

		local toggleDuringQueue = storeProbe:Invoke("open")
		local kioskDuringQueue = storeProbe:Invoke("kiosk")
		record(toggleDuringQueue == false and kioskDuringQueue == false
			and terminal.Visible == false,
			"queue already open: both toggle and kiosk paths refuse the terminal",
			string.format("toggle=%s kiosk=%s Visible=%s", tostring(toggleDuringQueue),
				tostring(kioskDuringQueue), tostring(terminal.Visible)))

		shade.Visible = false
		task.wait(.25)
		storeProbe:Invoke("open")
		task.wait(.2)
		player:SetAttribute("DispatchBriefingOpen", true)
		task.wait(.2)
		record(terminal.Visible == false and player:GetAttribute("ZyntraStoreOpen") ~= true,
			"a briefing modal attribute closes a terminal that was already open",
			string.format("Visible=%s attribute=%s", tostring(terminal.Visible),
				tostring(player:GetAttribute("ZyntraStoreOpen"))))
		player:SetAttribute("DispatchBriefingOpen", nil)
		task.wait(.2)

		-- ------------------------------------------------------------------
		-- Developer-page captions follow the live input mode.
		-- ------------------------------------------------------------------
		-- Terminal has three unnamed children all called Frame, so the page has
		-- to be found recursively rather than indexed.
		local devPage = terminal and terminal:FindFirstChild("Dev", true)
		local devControls = devPage and devPage:FindFirstChild("DevControls")
		if not devControls then
			-- Not a pass and not a failure of the code under test: this account is
			-- not on the developer whitelist, so the page does not exist to read.
			record(true, "the developer page is not present for this account -- its"
				.. " caption contract is unexercised on this run, not verified",
				"whitelisted accounts only")
		else
			for _, mode in ipairs({
				{Name = "keyboard", Force = nil, Suppressed = false},
				{Name = "touch", Force = true, Suppressed = true},
			}) do
				workspace:SetAttribute("ForceTouchUI", mode.Force)
				task.wait(.4)
				record(UIDevice.SuppressesKeyboardGlyphs() == mode.Suppressed,
					mode.Name .. ": UIDevice reports the glyph mode this pass is testing",
					string.format("SuppressesKeyboardGlyphs=%s",
						tostring(UIDevice.SuppressesKeyboardGlyphs())))

				local intro = devPage:FindFirstChild("DevIntro")
				local wantedIntro = mode.Suppressed and DEV_INTRO_BASE or DEV_INTRO_KEYBOARD
				record(intro ~= nil and intro.Text == wantedIntro,
					mode.Name .. ": the developer intro line names a key only when there"
					.. " are keys to press",
					string.format("%q, want %q", intro and tostring(intro.Text) or "-",
						wantedIntro))

				local wrongToggle, wrongName, missing = 0, "", 0
				for _, entry in ipairs(DEV_CAPTION_KEYS) do
					local row = devControls:FindFirstChild(entry.Command)
					if not row then
						-- level3PreBlackout only exists for the timeline owner.
						missing += 1
					else
						local toggle = row:FindFirstChild("Toggle")
						local text = toggle and tostring(toggle.Text) or ""
						local named = text:find("//  " .. entry.Key, 1, true) ~= nil
						if named == mode.Suppressed then
							wrongToggle += 1
							if wrongName == "" then
								wrongName = entry.Command .. " = " .. text
							end
						end
					end
				end
				record(wrongToggle == 0,
					mode.Name .. ": every developer toggle caption shows its key exactly"
					.. " when the device has one",
					string.format("%d wrong, first %s (%d rows absent for this account)",
						wrongToggle, wrongName == "" and "-" or wrongName, missing))

				local noclip = devControls:FindFirstChild("noclip")
				local description = noclip and noclip:FindFirstChild("Description")
				local wantedNoclip = mode.Suppressed and DEV_NOCLIP_TOUCH or DEV_NOCLIP_KEYBOARD
				record(description ~= nil and description.Text == wantedNoclip,
					mode.Name .. ": the noclip row describes the controls this device"
					.. " actually has",
					string.format("%q, want %q",
						description and tostring(description.Text) or "-", wantedNoclip))
			end

			-- The whole point of hanging this off UIDevice.Changed rather than
			-- reading IsTouch() once at build time: a device that changes mode
			-- mid-session has to be re-captioned, not left lying.
			workspace:SetAttribute("ForceTouchUI", nil)
			task.wait(.4)
			local intro = devPage:FindFirstChild("DevIntro")
			record(intro ~= nil and intro.Text == DEV_INTRO_KEYBOARD,
				"and the captions come BACK when the device stops suppressing glyphs --"
				.. " they are re-rendered on UIDevice.Changed, not decided once",
				string.format("%q", intro and tostring(intro.Text) or "-"))
		end
	end)

	workspace:SetAttribute("UIRegressionViewport", previousViewport)
	workspace:SetAttribute("ForceTouchUI", previousTouch)
	-- The matrix directly raises this derived attribute once to exercise
	-- ZyntraStore's listener. Clear that synthetic write before restoring the
	-- real drivers below, even when the protected body stopped early.
	player:SetAttribute("DispatchBriefingOpen", nil)
	player:SetAttribute("UIRegressionForceDispatchActive", previousForce)
	player:SetAttribute("UIRegressionSuppressDispatch", previousSuppress)
	shade.Visible = previousShade
	storeProbe:Invoke("close")
	if previousTerminal and not previousShade
		and player:GetAttribute("DispatchBriefingOpen") ~= true then
		storeProbe:Invoke("open")
	end
	if not ran then
		record(false, "the matrix ran to completion", tostring(runError))
	end
	table.insert(report, string.format("TOTAL: %d checks, %d failed", checks, failures))
	return table.concat(report, "\n"), failures
end

function UIRegression.RunAll(): (string, number)
	-- UIRegressionViewport makes UIDevice REPORT a simulated size, but Studio
	-- still renders at the real one. Every assertion below compares measured
	-- AbsolutePosition against the reported viewport, so with the override
	-- active they would all compare real pixels against a fictional screen and
	-- fail meaninglessly. CompletionFit owns that override and resolves UDim2
	-- values arithmetically instead; this matrix needs the Device Simulator.
	if workspace:GetAttribute("UIRegressionViewport") ~= nil then
		return "UIRegressionViewport is set: clear it before running the scenario"
			.. " matrix, or call UIRegression.CompletionFit(), which owns it.", 1
	end
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
		-- A touch-only scenario cannot be asserted on a pass that is not touch:
		-- its controls do not exist, so `Requires` fails for a reason that is not
		-- a defect. It is NOT dropped -- TouchTargetMatrix drives the same
		-- scenario with ForceTouchUI across six device sizes plus the real
		-- viewport, which is where its coverage actually lives.
		if scenario.TouchOnly and not UIDevice.IsTouch() then
			table.insert(report, string.format("%-28s skip  (touch-only; covered by TouchTargetMatrix)",
				scenario.Name))
			continue
		end
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
			-- This matrix runs at the REAL rendered viewport, so the geometry
			-- half of the check is meaningful here and is included.
			for _, fragment in ipairs(scenario.TouchTargets or {}) do
				local rect = findRect(fragment)
				if not rect then
					table.insert(contractProblems, "TOUCH TARGET: missing " .. fragment)
				else
					for _, problem in ipairs(touchTargetProblems(
						rect, result.Rects, layout.Viewport, true)) do
						table.insert(contractProblems,
							"TOUCH TARGET: " .. fragment .. " " .. problem)
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
	local completionReport, completionFailures = UIRegression.CompletionContract()
	table.insert(report, completionReport)
	failures += completionFailures
	local fitReport, fitFailures = UIRegression.CompletionFit()
	table.insert(report, fitReport)
	failures += fitFailures
	-- The queue modal owns the override itself and resolves rects
	-- arithmetically, so it can run from here without the guard above applying.
	-- Running it from RunAll is deliberate: a device matrix nobody calls is the
	-- same as no device matrix, and this one guards the shape that shipped
	-- broken on a real Galaxy A06.
	local modalReport, modalFailures = UIRegression.QueueModalMatrix()
	table.insert(report, modalReport)
	failures += modalFailures
	-- Same contract, same reason: BriefingFitMatrix owns the override too, and
	-- it is the only thing in this file that can say whether the dispatch copy
	-- fits its box on a viewport Studio is not currently rendering.
	local briefingReport, briefingFailures = UIRegression.BriefingFitMatrix()
	table.insert(report, briefingReport)
	failures += briefingFailures
	-- Last, because it is the only matrix that drives the queue modal open and
	-- shut: anything measured while it is running would be measuring this
	-- matrix's own state rather than the screen the player gets. It restores the
	-- shade, the dispatch force flag and both device overrides on every exit
	-- path, error included.
	local exclusionReport, exclusionFailures = UIRegression.BriefingExclusionMatrix()
	table.insert(report, exclusionReport)
	failures += exclusionFailures
	table.insert(report, string.format("TOTAL: %d scenarios, %d failed",
		#UIRegression.Scenarios(), failures))
	return table.concat(report, "\n"), failures
end

return UIRegression
