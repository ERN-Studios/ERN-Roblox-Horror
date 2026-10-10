return function()
--!nocheck
-- Offline fake engine for the in-round HUD (owner, 2026-10-08; FRAMEWISP-PIPELINE.md 3.6).
--
-- A trimmed copy of the shop harness's engine (artifacts/shop-ui-figma-20261005/roblox-draft/tests/
-- zyntra_shop_l4_harness.luau): signals, value types, instances with a laid-out AbsoluteSize and a
-- measured TextBounds, and build(spec) over the dump format of install/02_dump_hud.luau. The REAL
-- sources run against it: a test_*.py replaces the INJECT line with
--   SOURCES = {[moduleName] = source}   every ModuleScript the code under test requires
--   TREES   = {[bundle] = spec}         ReplicatedStorage.ZyntraHUD.Templates.<bundle>
-- and appends its checks. UIDevice is faked at its published contract (Binding, IsTouch, Layout,
-- LocalPosition, Changed); everything else a module requires is the real source.
--
-- Not modelled: UIScale, list padding, AutomaticSize, real font metrics, rendering.

local SOURCES = {RoundHud=true,ShopBinder=true,UIStyle=true,ZyntraDetectorVisual=true,ExitClient=true}
local FACTORIES = {
RoundHud=function() return function()
-- RoundHud (ReplicatedStorage.RoundHud) -- the in-round HUD's shared module (owner, 2026-10-08).
--
-- artifacts/hud-final-20261008/BUILD-PLAN.md 1.1, 1.3, 1.4 and FRAMEWISP-PIPELINE.md 5. Each level
-- and system script keeps its own data, logic and ScreenGui; the LOOK travels from Figma through
-- Framewisp into ReplicatedStorage.ZyntraHUD.Templates.<bundle> and is mounted through here. On one
-- client every LocalScript's require returns this same table, so there is one RoundHud ScreenGui.
-- execute_luau gets its own module instance: Studio QA reads the GUI, never this module's state.
--
-- API (B1-B5; Stack mounts every fixed part through Mount, preserving *Fill anchors and text):
--
--   RoundHud.Gui() -> ScreenGui
--       The "RoundHud" ScreenGui in PlayerGui (DisplayOrder 10, ResetOnSpawn false), made on first use.
--   RoundHud.Bundle() -> "HUD_Touch" | "HUD_PC"
--       The touch layout (UIDevice.IsTouch) mounts HUD_Touch; everything else, gamepad included, HUD_PC.
--   RoundHud.Template(bundle, path) -> Instance?
--       Binder.at(Templates[bundle], path). A missing one warns once per path and returns nil.
--   RoundHud.Mount(bundle, path, parent, opts?) -> root?, attention?
--       Clones the template node: strips scripts and _ignore layers, sizes it to its design size times
--       opts.Scale (default 1), resets AnchorPoint and Position for the caller, wraps multi-line text,
--       softens every `Soft`, floors touch text at 12 px, names it opts.Name (default: the template's
--       base name), parents it and keeps its text at design size (ShopBinder.scaleText, which re-fits
--       whenever the root's size changes). opts.Prepare(clone), when supplied, completes imported
--       children before font/layout bindings. With opts.Attention = {Hold = s, Rest = o} the clone sits
--       inside a CanvasGroup carrying that name; the group is the returned root and the second return
--       is its Attention. Position the root; never resize it (but see RULES: the Soft clip). A missing
--       template draws nothing.
--       HUD_B3 (owner, 2026-10-08): every `*Fill` is anchored on its left edge (the caller owns its
--       width); opts.Touch floors text at 12 px for a PC template drawn on the touch layout.
--   RoundHud.Attention(group, hold, rest) -> attention          (group: a CanvasGroup)
--       The C visibility rule. attention:Show(key, urgent?, rest?) is 100 % for `hold` seconds when
--       `key` changed since the last Show, then `rest` opacity (0 = hidden); while `urgent` it never
--       dims (DANGER, ACTIVE, REFUSED, HIGH). attention:Hide() fades it out; the next Show is a change.
--       attention:SetSuppressed(true) excludes it immediately without restarting its C timers.
--       Fades are 0.18 s in and 0.4 s out. ReduceFlashing is not read: these are opacity ramps.
--   RoundHud.Keycap(chip, keyboard, gamepad?)
--       Fills a template KeyChip (`Key` text + `GlyphSlot`): the key on keyboard (an Enum.KeyCode, or a
--       string such as "Esc"), the engine glyph (GetImageForKeyCode) on gamepad, hidden on touch.
--       UIDevice.Binding decides which, and it is re-applied on UIDevice.Changed. Owns chip.Visible.
--   RoundHud.Detector(reading?, expiresAt?)
--       The 09 C detector card: "LOW" | "MEDIUM" | "HIGH" until expiresAt (server time, as the
--       ZyntraDetector remote sends it). 100 % for 4 s per reading, then hidden; HIGH never dims.
--       nil (or anything else) hides it.
--   RoundHud.Clear()
--       Removes owned Objective/Detector/Feed/Caption roots on round teardown. It preserves the
--       last valid objective for results, and never touches caller-owned marker/stamina mounts.
--   RoundHud.Stack(bundle,path,parent,opts?) -> root?,parts,attention?
--       Fixed imported parts flow by current LayoutOrder; hidden/moved children close gaps. The
--       root reports HudStackHeight. opts.MinHeight can reserve transparent Attention hit bounds.
--   RoundHud.Paint(root,templateName,level), Soften(node), Ring(slot) -> set(fraction,colour)
--       Accent paths only; deterministic soft backing; two code-drawn half masks for hold sweeps.
--   RoundHud.SetObjective(state) -> accepted; LastObjective() -> stable latest valid snapshot?
--       BUILD-PLAN fields, plus optional OnOrderActivate. Counter={Label,Current,Max} serves results.
--       Wrong-level/inactive/nil receivers cannot erase the active card. A valid watched subject
--       supplies compass origin. Semantic changes expand/wake6s; target/timer updates do not.
--       EXIT_COMPASS_20261010: Title "GET OUT" with Compass = {State = "locked", Target = Vector3}
--       is the exit compass. It alone wears UIStyle.Hud.Exit ("EXIT 23 m", an outline, a facing
--       cue, an arrival swell, an every-frame needle, and on touch it stays under the collapsed
--       bar). QA reads the attributes HudExit / HudFacing / HudBearing on the Compass part.
--   RoundHud.Feed({Kind,Actor?,Detail,Key?}) -> accepted
--       Actor is Player/name/id, resolved to DisplayName.2 PC/1 touch rows,4s, sameKey2s merge.
--   RoundHud.Caption(speaker,text,seconds?) -> accepted
--       Gated3.5s dialogue; seconds0 clears. Source-gated COMMAND CENTER can caption lobby dispatch.
--   CaptureTestState(), RestoreTestState(snapshot), ExpandObjectiveForTest()
--       Studio only; enter through the actual Round HUD client's UIRegressionRoundHudProbe.
--
-- RULES (BUILD-PLAN 1.6, pipeline 5.3): ASCII-only source (write the middle dot as \u{B7}); a missing
-- template is a warning by path and no drawing, never an Instance.new fallback; callers write only the
-- dyn slots, state colours, Visible flags, a *Fill's width and a hugged `Soft`'s width, never other
-- mounted geometry. HUD_B3 (critic K6): an Attention group may be narrowed to clip a hugged Soft once
-- its clone is pinned at the mounted size, because scaleText reads the clone, not the group.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Binder = require(ReplicatedStorage:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))
local Visual = require(ReplicatedStorage:WaitForChild("ZyntraDetectorVisual"))

local RoundHud = {}
local P = Binder.Palette
local FADE_IN, FADE_OUT = 0.18, 0.4

-- ShopBinder's EM table (local there): Roblox TextSize per design em, per face. Only used to tell a
-- multi-line text box from a one-line one (pipeline 2.0 rule 7).
local EM = {Montserrat = 1.219, RobotoMono = 1.3188, RobotoCondensed = 1.1719, BuilderSans = 1.26}

local function isText(node)
	return node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")
end

-- -- gui and templates ------------------------------------------------------

local gui
function RoundHud.Gui()
	if gui and gui.Parent then return gui end
	gui = Instance.new("ScreenGui")
	gui.Name = "RoundHud"
	gui.DisplayOrder = 10 -- BUILD-PLAN 1.4: under the death card, PARTY DOWN and results (RoundUI, 100)
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None -- placement goes through UIDevice.LocalPosition
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function RoundHud.Bundle()
	return UIDevice.IsTouch() and "HUD_Touch" or "HUD_PC"
end

local function bundleRoot(bundle)
	local hud = ReplicatedStorage:FindFirstChild("ZyntraHUD")
	local templates = hud and hud:FindFirstChild("Templates")
	return templates and templates:FindFirstChild(bundle)
end

local warned = {}
function RoundHud.Template(bundle, path)
	local root = bundleRoot(bundle)
	local node = root and Binder.at(root, path)
	if not node then
		local key = tostring(bundle) .. "/" .. tostring(path)
		if not warned[key] then
			warned[key] = true
			warn("[RoundHud] missing template: " .. key)
		end
	end
	return node
end

-- The soft-Ink backing: Framewisp's gradient alpha is unproven, so the ramp is written here.
local function soften(node)
	local gradient = node:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = node
	end
	gradient.Transparency = NumberSequence.new(UIStyle.Hud.Soft.From, UIStyle.Hud.Soft.To)
end

RoundHud.Soften = soften

function RoundHud.Mount(bundle, path, parent, opts)
	opts = opts or {}
	local source = RoundHud.Template(bundle, path)
	if not source then return nil end
	-- Measured in the template, where the Scale chain up to BB_DesignW is intact.
	local design = Binder.designSize(source)
	local scale = opts.Scale or 1
	local factor = bundleRoot(bundle):GetAttribute("BB_TextFactor")
	-- HUD_B3: opts.Touch floors a PC template drawn on the touch layout (the B3 stamina bar at 0.5).
	local touch = opts.Touch == true or bundle == "HUD_Touch" or string.sub(Binder.base(source.Name), -5) == "Touch"
	local clone = source:Clone()
	Binder.strip(clone)
	clone.Name = opts.Name or Binder.base(source.Name)
	clone.AnchorPoint = Vector2.new(0, 0)
	clone.Position = UDim2.new()
	-- Rounded: an Offset is a whole pixel, and the Scale chain gives 447.99 for a 448 px node.
	clone.Size = UDim2.fromOffset(math.round(design.X * scale), math.round(design.Y * scale))
	if opts.Prepare then opts.Prepare(clone) end
	for _, node in ipairs(clone:GetDescendants()) do
		local fs = node:GetAttribute("FigmaFontSize")
		if isText(node) and type(fs) == "number" and fs > 0 then
			-- A box drawn 1.8 lines tall or more is multi-line (pipeline 2.0 rule 7). Set before
			-- scaleText, which solves a wrapped label by its line count.
			local height, at = design.Y, node
			while at ~= clone do
				height *= at.Size.Y.Scale
				at = at.Parent
			end
			local family = node.FontFace and string.match(node.FontFace.Family, "(%w+)%.json$")
			if height / (fs * (EM[family] or tonumber(factor) or 1.16)) >= 1.8 then node.TextWrapped = true end
			if touch then
				-- Touch floor (pipeline 2.0 rule 8); scaleText clamps to the constraint.
				local limit = node:FindFirstChildOfClass("UITextSizeConstraint")
				if not limit then
					limit = Instance.new("UITextSizeConstraint")
					limit.Parent = node
				end
				limit.MinTextSize = math.max(limit.MinTextSize, 12)
			end
		elseif Binder.base(node.Name) == "Soft" and node:IsA("GuiObject") then
			soften(node)
		elseif string.sub(Binder.base(node.Name), -4) == "Fill" and node:IsA("GuiObject") then
			-- HUD_B3: Framewisp centre-anchors every node, so a width write would grow a Fill both ways.
			-- Anchor it on the left edge it already starts at; the caller owns its width (pipeline 2.0
			-- rule 12; owner, 2026-10-08).
			local a, p, s = node.AnchorPoint, node.Position, node.Size
			node.AnchorPoint = Vector2.new(0, a.Y)
			node.Position = UDim2.new(p.X.Scale - a.X * s.X.Scale, p.X.Offset - a.X * s.X.Offset, p.Y.Scale, p.Y.Offset)
		end
	end
	local root, attention = clone, nil
	if opts.Attention then
		root = Instance.new("CanvasGroup")
		root.Name = clone.Name
		root.BackgroundTransparency = 1
		root.BorderSizePixel = 0
		root.Size = clone.Size
		root.GroupTransparency = 1
		root.Visible = false
		clone.Size = UDim2.fromScale(1, 1)
		clone.Parent = root
		attention = RoundHud.Attention(root, opts.Attention.Hold, opts.Attention.Rest)
	end
	root.Parent = parent
	Binder.scaleText(clone, design, factor)
	return root, attention
end

-- Fixed imported parts in a variable-height container. The current children, rather than the parts
-- map, own flow: results can move its six roster rows into a bounded ScrollingFrame without losing
-- the header/footer layout. A hidden advice/status row reserves no space.
function RoundHud.Stack(bundle, path, parent, opts)
	opts = opts or {}
	local source = RoundHud.Template(bundle, path)
	if not source then return nil, {} end
	local design, scale = Binder.designSize(source), opts.Scale or 1
	local clone = source:Clone()
	Binder.strip(clone)
	for _, child in ipairs(clone:GetChildren()) do
		if child:IsA("GuiObject") or child:IsA("UIListLayout") or child:IsA("UIPadding") then child:Destroy() end
	end
	clone.Name = opts.Name or Binder.base(source.Name)
	clone.AnchorPoint, clone.Position = Vector2.new(), UDim2.new()
	clone.Size = UDim2.fromOffset(math.round(design.X * scale), 0)
	if clone.BackgroundTransparency < 1 then soften(clone) end
	local root, attention = clone, nil
	if opts.Attention then
		root = Instance.new("CanvasGroup")
		root.Name, root.BackgroundTransparency, root.BorderSizePixel = clone.Name, 1, 0
		root.Size, root.Visible, root.GroupTransparency = clone.Size, false, 1
		clone.Parent = root
		attention = RoundHud.Attention(root, opts.Attention.Hold, opts.Attention.Rest)
	end
	root.Parent = parent
	local parts, authored, connections = {}, {}, {}
	local queued, sizing, destroyed = false, false, false
	local function reflow()
		queued = false
		if destroyed or sizing then return end
		sizing = true
		local rows = {}
		for _, child in ipairs(clone:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then table.insert(rows, child) end
		end
		table.sort(rows, function(a, b)
			if a.LayoutOrder == b.LayoutOrder then return a.Name < b.Name end
			return a.LayoutOrder < b.LayoutOrder
		end)
		local height = 0
		for _, row in ipairs(rows) do
			row.AnchorPoint = Vector2.new(0, 0)
			row.Position = UDim2.fromOffset(0, height)
			height += row.Size.Y.Offset
		end
		local width = math.round(design.X * scale)
		clone.Size = UDim2.fromOffset(width, height)
		local boundsHeight = math.max(height, opts.MinHeight or 0)
		if root ~= clone then root.Size = UDim2.fromOffset(width, boundsHeight) end
		root:SetAttribute("HudStackHeight", root == clone and height or boundsHeight)
		sizing = false
	end
	local function schedule()
		if queued or destroyed then return end
		queued = true
		task.defer(reflow)
	end
	local watched = setmetatable({}, {__mode = "k"})
	local function watch(child)
		if not child:IsA("GuiObject") or watched[child] then return end
		watched[child] = true
		for _, property in ipairs({"Visible", "Size", "LayoutOrder", "Parent"}) do
			table.insert(connections, child:GetPropertyChangedSignal(property):Connect(schedule))
		end
		schedule()
	end
	for _, child in ipairs(source:GetChildren()) do
		if child:IsA("GuiObject") then
			local y = (child.Position.Y.Scale - child.AnchorPoint.Y * child.Size.Y.Scale) * design.Y + child.Position.Y.Offset
			table.insert(authored, {Node = child, Y = y})
		end
	end
	table.sort(authored, function(a, b) return a.Y < b.Y end)
	for index, entry in ipairs(authored) do
		local name = Binder.base(entry.Node.Name)
		local part = RoundHud.Mount(bundle, path .. "/" .. name, clone, {Scale = scale, Touch = opts.Touch})
		if part then part.LayoutOrder = index; parts[name] = part; watch(part) end
	end
	table.insert(connections, clone.ChildAdded:Connect(watch))
	table.insert(connections, root.Destroying:Connect(function()
		destroyed = true
		for _, connection in ipairs(connections) do connection:Disconnect() end
	end))
	reflow()
	return root, parts, attention
end

function RoundHud.Paint(root, templateName, level)
	if not root then return end
	local accent = UIStyle.Hud.Accent[level] or P.Cream
	local paths = {}
	if templateName == "ObjectiveCard" or templateName == "ObjectivePill" then
		paths = {{"Eyebrow", "TextColor3"}, {"Underbar", "BackgroundColor3"},
			{"Progress/Track/Fill", "BackgroundColor3"}, {"Compass/Chevron", "TextColor3"}}
	elseif templateName == "LoadingCard" or templateName == "LoadingCardTouch" then
		paths = {{"Eyebrow", "TextColor3"}, {"Underbar", "BackgroundColor3"},
			{"Status/Track/Fill", "BackgroundColor3"}}
		local track = Binder.at(root, "LevelTrack")
		if track then
			for index = 1, 6 do
				local slot = Binder.text(Binder.find(track, "Slot" .. index))
				if slot then slot.TextColor3 = index == level and accent or P.Sage end
			end
		end
	elseif templateName == "Results" or templateName == "ResultsTouch" then
		paths = {{"Head/Eyebrow", "TextColor3"}}
	end
	for _, pair in ipairs(paths) do
		local node = Binder.at(root, pair[1])
		if node then node[pair[2]] = accent end
	end
end

-- Two clipped semicircles. UIGradient rotates the visible half within each fixed mask; no uploaded
-- image, timer or tween is owned here. A caller's hold clock can reset/reverse the same sweep.
function RoundHud.Ring(slot)
	if not slot then return function() end end
	local halves = {}
	for index = 1, 2 do
		local mask = Instance.new("Frame")
		mask.Name, mask.BackgroundTransparency, mask.BorderSizePixel = "SweepHalf" .. index, 1, 0
		mask.ClipsDescendants = true
		mask.Size, mask.Position = UDim2.fromScale(0.5, 1), UDim2.fromScale((index - 1) * 0.5, 0)
		mask.Parent = slot
		local circle = Instance.new("Frame")
		circle.BackgroundTransparency, circle.BorderSizePixel = 1, 0
		circle.Size, circle.Position = UDim2.fromScale(2, 1), UDim2.fromScale(index == 1 and 0 or -1, 0)
		circle.Parent = mask
		local corner = Instance.new("UICorner")
		corner.CornerRadius, corner.Parent = UDim.new(1, 0), circle
		local stroke = Instance.new("UIStroke")
		stroke.Thickness, stroke.ApplyStrokeMode, stroke.Parent = 2, Enum.ApplyStrokeMode.Border, circle
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.499, 0), NumberSequenceKeypoint.new(0.501, 1), NumberSequenceKeypoint.new(1, 1)})
		gradient.Parent = stroke
		halves[index] = {Mask = mask, Stroke = stroke, Gradient = gradient}
	end
	local function set(fraction, color)
		fraction = type(fraction) == "number" and fraction == fraction and math.clamp(fraction, 0, 1) or 0
		for index, half in ipairs(halves) do
			local amount = math.clamp(fraction * 2 - (index - 1), 0, 1)
			half.Mask.Visible = amount > 0
			half.Stroke.Color = color or P.Cream
			half.Gradient.Rotation = (index == 1 and 180 or 0) + amount * 180
		end
	end
	set(0)
	return set
end

-- -- C visibility rule ------------------------------------------------------

local Attention = {}
Attention.__index = Attention

function RoundHud.Attention(group, hold, rest)
	return setmetatable({Group = group, Hold = hold or 6, Rest = rest or 0, Serial = 0}, Attention)
end

local function fadeTo(self, opacity, seconds)
	local group = self.Group
	self.Opacity = opacity
	if self.Tween then self.Tween:Cancel(); self.Tween = nil end
	if self.Suppressed then
		group.Visible, group.GroupTransparency = false, 1
	else
		if opacity > 0 then group.Visible = true end
		self.Tween = TweenService:Create(group, TweenInfo.new(seconds), {GroupTransparency = 1 - opacity})
		self.Tween:Play()
	end
	if opacity <= 0 then
		local serial = self.Serial
		task.delay(seconds, function()
			if self.Serial == serial and self.Opacity <= 0 then group.Visible = false end
		end)
	end
end

function Attention:SetSuppressed(suppressed)
	suppressed = suppressed == true
	if self.Suppressed == suppressed then return end
	self.Suppressed = suppressed
	if self.Tween then self.Tween:Cancel(); self.Tween = nil end
	local opacity = suppressed and 0 or (self.Opacity or 0)
	self.Group.Visible, self.Group.GroupTransparency = opacity > 0, 1 - opacity
end

function Attention:Show(key, urgent, rest)
	self.Urgent = urgent == true
	self.RestNow = rest or self.Rest
	if not self.Shown or key ~= self.Key then
		self.Shown, self.Key, self.Held = true, key, true
		self.HoldUntil = workspace:GetServerTimeNow() + self.Hold
		self.Serial += 1
		local serial = self.Serial
		fadeTo(self, 1, FADE_IN)
		task.delay(self.Hold, function()
			if self.Serial ~= serial then return end
			self.Held = false
			if not self.Urgent then fadeTo(self, self.RestNow, FADE_OUT) end
		end)
	elseif self.Urgent then
		if self.Opacity < 1 then fadeTo(self, 1, FADE_IN) end
	elseif not self.Held and self.Opacity ~= self.RestNow then
		fadeTo(self, self.RestNow, FADE_OUT)
	end
end

function Attention:Hide()
	self.Serial += 1
	self.Shown, self.Key, self.Held, self.Urgent = false, nil, false, false
	if self.Group.Visible or (self.Opacity or 0) > 0 then fadeTo(self, 0, FADE_OUT) end
end

-- -- keycaps ----------------------------------------------------------------

local keycaps = setmetatable({}, {__mode = "k"}) -- chip -> {keyboard, gamepad}

local function keyLabel(key)
	if typeof(key) ~= "EnumItem" then return tostring(key) end
	local ok, text = pcall(UserInputService.GetStringForKeyCode, UserInputService, key)
	if not ok or type(text) ~= "string" or text == "" then
		text = string.gsub(key.Name, "^Button", "") -- ButtonR1 -> R1
	end
	return text
end

local function applyKeycap(chip, keyboard, gamepad)
	local pick = UIDevice.Binding(keyboard and "keyboard", gamepad and "gamepad")
	chip.Visible = pick ~= ""
	if pick == "" then return end
	local image = ""
	if pick == "gamepad" then
		local ok, found = pcall(UserInputService.GetImageForKeyCode, UserInputService, gamepad)
		if ok and type(found) == "string" then image = found end
	end
	local slot = Binder.find(chip, "GlyphSlot")
	local glyph = slot and (image ~= "" and Binder.image(slot) or slot:FindFirstChildWhichIsA("ImageLabel", true))
	if glyph then
		glyph.Image = image
		glyph.Visible = image ~= ""
	end
	local key = Binder.text(Binder.find(chip, "Key"))
	if key then key.Text = image ~= "" and "" or keyLabel(pick == "gamepad" and gamepad or keyboard) end
end

function RoundHud.Keycap(chip, keyboard, gamepad)
	if not chip then return end
	keycaps[chip] = {keyboard, gamepad}
	applyKeycap(chip, keyboard, gamepad)
end

-- -- shared objective, semantic attention and subject-safe compass -----------

local player = Players.LocalPlayer
local objective = {Serial = 0, Connections = {}}
local lastObjective
local renderObjective

-- EXIT_COMPASS_20261010 (owner: "Make the compass marker to the exit more distinct."). The exit
-- compass was a 10 px chevron in the level's own accent (in Level 1 the yellow of the walls and of
-- every other accent on the card) that read "23 m", stepped ten times a second and arrived
-- unannounced at the moment the lights die. While a GET OUT objective has its exit locked the row
-- now wears a look of its own: UIStyle.Hud.Exit (the door's green) on the chevron and the strip's
-- baseline, "EXIT 23 m", an Ink text outline, a cue when the camera faces the exit, three slow
-- swells on arrival, a needle that follows the camera every frame, and on touch it stays up under
-- the collapsed bar. The key is the convention paintCompass already had for "AT THE EXIT"
-- (Title == "GET OUT"), so Level 1, 3 and 4 get it with no publisher change.
-- NOTHING ELSE CHANGES: every other compass state is written exactly as before, and whatever the
-- exit look writes is put back from the values read off the mounted clone (undressExit). It adds
-- no node under the Compass row (UIRegression would count one as a rectangle of its own), and it
-- resizes nothing: the row's real size is a template change.
local EXIT = {
	-- UIStyle owns the colour. The literal is the same green, for a place where this module landed
	-- and UIStyle's new field did not: a nil here compiles, loads and only shows at the exit, as an
	-- error on every frame that also stops this module's 0.1 s refresh (review, 2026-10-10).
	Green = UIStyle.Hud.Exit or Color3.fromRGB(90, 255, 135), White = Color3.new(1, 1, 1),
	FaceIn = 8, FaceOut = 12,     -- degrees off dead ahead; in and out differ so the cue cannot chatter
	Swells = 3, FaceSwell = 0.4,  -- seconds: three 1 Hz swells on arrival, one short one on facing
	Strip = 0.45,                 -- how far the baseline leans from its own colour to the green at rest
	Stroke = 0.35,                -- TextStrokeTransparency of the Ink outline
}

local function exitLocked(state)
	local compass = state and state.Compass
	return compass ~= nil and state.Title == "GET OUT" and compass.State == "locked" and typeof(compass.Target) == "Vector3"
end

-- Color3:Lerp, written out: the offline HUD engine (tools/tests/hud_harness.luau) has no Lerp.
local function blend(from, to, alpha)
	return Color3.new(from.R + (to.R - from.R) * alpha, from.G + (to.G - from.G) * alpha, from.B + (to.B - from.B) * alpha)
end

-- Touch only: the pill collapses to its bar six seconds after every change or tap, and it took
-- the exit compass with it, so a phone player had the way out for six seconds per tap. While an
-- exit is locked the row stays up under the collapsed bar, but only if bar + compass (+ a danger
-- row, which stays up too) fit above the control cluster: a card that does not fit is hidden
-- WHOLE (placeObjective, objective.Fits), and no card is worse than no compass. 16 is the reach
-- placeObjective asks TopRightPanel for on touch.
local function pinsExit(state, parts, root)
	local bar, row = parts.Bar, parts.Compass
	if not bar or not row or not exitLocked(state) then return false end
	local need = bar.Size.Y.Offset + row.Size.Y.Offset
	if state.Status and state.Status.Kind == "danger" and parts.StatusRow then need += parts.StatusRow.Size.Y.Offset end
	return UIDevice.TopRightPanel(root.Size.X.Offset + 16, need).Height >= need
end

local function textAt(root, path, value, color)
	local node = Binder.text(Binder.at(root, path))
	if node then node.Text = value or ""; if color then node.TextColor3 = color end end
	return node
end

local function subject()
	local who = player
	if player:GetAttribute("Spectating") == true then
		local id = player:GetAttribute("SpectateTargetUserId")
		who = type(id) == "number" and Players:GetPlayerByUserId(id) or nil
	end
	if not who or who:GetAttribute("InRound") ~= true or who:GetAttribute("Escaped") == true
		or who:GetAttribute("EscapedRound") == true then return nil end
	local character = who.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return nil end
	return who, root
end

local function covered()
	if player:GetAttribute("ZyntraDispatchClientActive") == true or player:GetAttribute("LevelLoadingOpen") == true
		or player:GetAttribute("PartyDownCardOpen") == true or player:GetAttribute("RoundExitPromptOpen") == true then return true end
	if UIDevice.ScreenOwningModalOpen and UIDevice.ScreenOwningModalOpen() then return true end
	local pg = player:FindFirstChild("PlayerGui")
	local roundUI = pg and pg:FindFirstChild("RoundGui")
	for _, name in ipairs({"RoundEnding", "LevelLoading"}) do
		local node = roundUI and roundUI:FindFirstChild(name, true)
		if node and node:IsA("GuiObject") and node.Visible then return true end
	end
	return false
end

local function inRound()
	return player:GetAttribute("InRound") == true and workspace:GetAttribute("RoundActive") == true
end

local function objectiveAllowed()
	local state = objective.State
	if not state or state.Level ~= workspace:GetAttribute("SelectedLevel") or covered() then return false end
	local fixture = workspace:GetAttribute("UIRegressionForceLevel3Reader") == true
		or player:GetAttribute("UIRegressionForceLevel3Reader") == true
	local who = subject()
	if not fixture and (not inRound() or not who) then return false end
	return state.Level ~= 3 or not who or who:GetAttribute("Level3_Hiding") ~= true
end

local function semantic(state)
	local statusText = state.Status and string.gsub(state.Status.Text, "%d+%.?%d*", "#") or ""
	return table.concat({tostring(state.Level), state.Eyebrow or "", state.Title, tostring(state.Count),
		tostring(state.Goal), state.Tag or "", table.concat(state.Lines, "\n"),
		state.Status and state.Status.Kind or "", statusText, state.Compass and state.Compass.State or "", tostring(state.Done)}, "|")
end

local function placeObjective()
	if not objective.Root then return end
	local root = objective.Root
	local width, height = root.Size.X.Offset, root.Size.Y.Offset
	local rightInset = objective.Bundle == "HUD_Touch" and 16 or 24
	local panel = UIDevice.TopRightPanel(width + rightInset, height)
	-- Imported parts keep their mounted widths and text. If the full expansion cannot fit, the
	-- compact touch bar stays in its safe corner; no extra fit-driven scale is applied.
	if objective.Bundle == "HUD_Touch" and objective.Expanded and panel.Height < height then
		objective.Expanded = false
		local danger = objective.State.Status and objective.State.Status.Kind == "danger"
		-- EXIT_COMPASS_20261010: the same collapsed rows renderObjective draws, so a pinned exit
		-- compass does not blink off until the next render.
		local pin = pinsExit(objective.State, objective.Parts, root)
		for name, part in pairs(objective.Parts) do
			part.Visible = name == "Bar" or (name == "StatusRow" and danger == true) or (name == "Compass" and pin)
		end
		task.defer(placeObjective)
		return
	end
	root.Position = UIDevice.LocalPosition(RoundHud.Gui(), panel.Right - width - rightInset, panel.Top)
	objective.Fits = panel.Width >= width + rightInset and panel.Height >= height
	if objective.Hit then objective.Hit.Size = UDim2.fromOffset(width, math.max(44, objective.Parts.Bar.Size.Y.Offset)) end
	if not objective.Fits then root.Visible = false end
end

local function unmountObjective()
	for _, connection in ipairs(objective.Connections) do connection:Disconnect() end
	objective.Connections = {}
	if objective.Root then objective.Root:Destroy() end
	objective.Root, objective.Parts, objective.Hit, objective.OrderHit, objective.Attention = nil, nil, nil, nil, nil
	objective.CompassNodes = nil -- EXIT_COMPASS_20261010: the row cache belongs to the destroyed clone
end

local function expandObjective()
	objective.Expanded = true
	objective.ExpandUntil = workspace:GetServerTimeNow() + 6
	objective.Serial += 1
	local serial = objective.Serial
	task.delay(6, function()
		if objective.Serial ~= serial then return end
		if objective.State and objective.State.Status and objective.State.Status.Kind == "danger" then return end
		objective.Expanded = false
		if renderObjective then renderObjective() end
	end)
end

local function tapObjective()
	if not objectiveAllowed() or not objective.Attention then return false end
	expandObjective()
	objective.Attention:Show("tap:" .. objective.Serial, objective.State.Status and objective.State.Status.Kind == "danger")
	renderObjective()
	return true
end

-- Only the physical touch hit may open developer tools. QA expansion and the Level4 Order line
-- keep their existing actions. Expanding first preserves the ordinary-player fallback and avoids
-- opening a modal before the objective's own eligibility check has completed.
local function activateObjective()
	if not tapObjective() then return false end
	if objective.Bundle ~= "HUD_Touch" or not UIDevice.IsTouch() or not inRound()
		or not objective.Root or objective.Root.Parent ~= RoundHud.Gui() or not objective.Root.Visible
		or not RoundHud.Gui().Enabled or objective.Fits ~= true then return true end
	local accessModule = ReplicatedStorage:FindFirstChild("DevAccess")
	if not accessModule or not accessModule:IsA("ModuleScript") then return true end
	local ok, access = pcall(require, accessModule)
	if not ok or type(access) ~= "table" or type(access.IsAllowed) ~= "function" then return true end
	local allowedOk, allowed = pcall(access.IsAllowed, player)
	if not allowedOk or allowed ~= true then return true end
	local scripts = player:FindFirstChild("PlayerScripts")
	local bridge = scripts and scripts:FindFirstChild("ZyntraDevUIOpen")
	if bridge and bridge:IsA("BindableFunction") then pcall(bridge.Invoke, bridge, true) end
	return true
end

local function mountObjective()
	local bundle = RoundHud.Bundle()
	if objective.Root and objective.Bundle ~= bundle then unmountObjective() end
	if objective.Root then return true end
	objective.Bundle = bundle
	objective.Root, objective.Parts, objective.Attention = RoundHud.Stack(bundle,
		bundle == "HUD_Touch" and "ObjectivePill" or "ObjectiveCard", RoundHud.Gui(),
		{Name = "ObjectiveCard", Scale = 0.8, MinHeight = bundle == "HUD_Touch" and 44 or 0, Attention = {Hold = 6, Rest = 1}})
	if not objective.Root then return false end
	-- Keep the authored padding and text widths, but share the eyebrow's right edge.
	local header = objective.Parts.Bar or objective.Parts.Head
	local eyebrow = header and Binder.text(Binder.at(header, "Eyebrow"))
	if eyebrow then
		-- A first fit may already have cached the imported positions; refits must use this layout.
		for _, name in ipairs({"Eyebrow", "Title", "Count"}) do
			local node = Binder.text(Binder.at(header, name))
			if node then
				local size, position = node:GetAttribute("FW_FitSize"), node:GetAttribute("FW_FitPosition")
				if typeof(size) == "UDim2" and typeof(position) == "UDim2" then node.Size, node.Position = size, position end
				node:SetAttribute("FW_FitSize", nil)
				node:SetAttribute("FW_FitPosition", nil)
			end
		end
		eyebrow.TextXAlignment = Enum.TextXAlignment.Right
		local p, a, s = eyebrow.Position, eyebrow.AnchorPoint, eyebrow.Size
		local rightScale, rightOffset = p.X.Scale + (1 - a.X) * s.X.Scale, p.X.Offset + (1 - a.X) * s.X.Offset
		for _, name in ipairs({"Title", "Underbar"}) do
			local node = Binder.at(header, name)
			if node and node:IsA("GuiObject") then
				node.AnchorPoint = Vector2.new(1, node.AnchorPoint.Y)
				node.Position = UDim2.new(rightScale, rightOffset, node.Position.Y.Scale, node.Position.Y.Offset)
				if node:IsA("TextLabel") then node.TextXAlignment = Enum.TextXAlignment.Right end
			end
		end
		-- Touch keeps its inline count clear of the title, on the opposite margin.
		local count = bundle == "HUD_Touch" and Binder.at(header, "Count")
		if count and count:IsA("GuiObject") then
			count.AnchorPoint = Vector2.new(0, count.AnchorPoint.Y)
			count.Position = UDim2.new(p.X.Scale - a.X * s.X.Scale, p.X.Offset - a.X * s.X.Offset, count.Position.Y.Scale, count.Position.Y.Offset)
		end
	end
	-- The objective has no backing on either layout; text and accent graphics stay intact.
	local backing = objective.Root:FindFirstChildWhichIsA("GuiObject")
	if backing then backing.BackgroundTransparency = 1 end
	if bundle == "HUD_Touch" and objective.Parts.Bar then
		objective.Hit = Binder.button(objective.Parts.Bar, "Hit", 20)
		objective.Hit.Size = UDim2.fromOffset(objective.Root.Size.X.Offset, 44)
		table.insert(objective.Connections, objective.Hit.Activated:Connect(activateObjective))
	end
	if objective.Parts.Guide1 then
		objective.OrderHit = Binder.button(objective.Parts.Guide1, "OrderHit", 20)
		if bundle == "HUD_Touch" then
			objective.OrderHit.Size = UDim2.fromOffset(objective.Root.Size.X.Offset, 44)
			objective.OrderHit.Position = UDim2.fromOffset(0, (objective.Parts.Guide1.Size.Y.Offset - 44) / 2)
		end
		table.insert(objective.Connections, objective.OrderHit.Activated:Connect(function()
			local callback = objective.State and objective.State.OnOrderActivate
			if objectiveAllowed() and type(callback) == "function" then callback() end
		end))
	end
	table.insert(objective.Connections, objective.Root:GetAttributeChangedSignal("HudStackHeight"):Connect(placeObjective))
	return true
end

-- EXIT_COMPASS_20261010: the row's nodes, found once per mounted clone. The exit needle repaints
-- every frame, and five Binder walks a frame (Binder.base builds a table for every node it tests)
-- would be garbage for nothing. The table also carries what the exit look has to remember about
-- this clone: what the import drew (Authored), whether the look is on (Dressed), the last readout
-- and the last QA stamps.
local function compassNodes(part)
	local nodes = objective.CompassNodes
	if not nodes or nodes.Part ~= part then
		local centre, baseline = Binder.at(part, "Centre"), Binder.at(part, "Baseline")
		nodes = {Part = part, Chevron = Binder.text(Binder.at(part, "Chevron")), Readout = Binder.text(Binder.at(part, "Readout")),
			Ticks = Binder.at(part, "Ticks"),
			Centre = centre and centre:IsA("GuiObject") and centre or nil,
			Baseline = baseline and baseline:IsA("GuiObject") and baseline or nil}
		objective.CompassNodes = nodes
	end
	return nodes
end

-- QA readbacks on the Compass part (a play session reads the GUI, never this module's state):
-- HudExit, HudFacing, and HudBearing in whole degrees off dead ahead (right is positive). Written
-- only when they change, and nil whenever the row is not wearing the exit look.
local function stampExit(nodes, exit, facing, bearing)
	if nodes.HudExit ~= exit then nodes.HudExit = exit; nodes.Part:SetAttribute("HudExit", exit) end
	if nodes.HudFacing ~= facing then nodes.HudFacing = facing; nodes.Part:SetAttribute("HudFacing", facing) end
	if nodes.HudBearing ~= bearing then nodes.HudBearing = bearing; nodes.Part:SetAttribute("HudBearing", bearing) end
end

-- The exit look's writes beyond the chevron and readout colours (paintCompass owns those for every
-- state). Colours only, on nodes the import already has: no tween, no instance, nothing resized.
local function dressExit(nodes, facing, swell, bearing)
	local chevron, readout, centre, baseline = nodes.Chevron, nodes.Readout, nodes.Centre, nodes.Baseline
	if not nodes.Dressed then
		nodes.Dressed = true
		local authored = nodes.Authored
		if not authored then
			-- Read once per clone, before the first exit write: undressExit puts exactly this back.
			authored = {Centre = centre and centre.BackgroundColor3, Baseline = baseline and baseline.BackgroundColor3,
				ChevronStroke = chevron.TextStrokeColor3, ChevronStrokeAlpha = chevron.TextStrokeTransparency,
				ReadoutStroke = readout.TextStrokeColor3, ReadoutStrokeAlpha = readout.TextStrokeTransparency}
			nodes.Authored = authored
			nodes.Strip = baseline and blend(authored.Baseline, EXIT.Green, EXIT.Strip)
		end
		-- The card has no backing (mountObjective), so its copy sits straight on lit walls. The
		-- outline is the TextLabel's own stroke, never a UIStroke: UIRegression measures a label
		-- that carries a UIStroke by its whole box (Fit.drawnRect), which would report the readout
		-- colliding with a chevron pinned at the strip's right end.
		chevron.TextStrokeColor3, chevron.TextStrokeTransparency = P.Ink, EXIT.Stroke
		readout.TextStrokeColor3, readout.TextStrokeTransparency = P.Ink, EXIT.Stroke
	end
	if centre then centre.BackgroundColor3 = facing and EXIT.Green or nodes.Authored.Centre end
	if baseline then
		baseline.BackgroundColor3 = swell > 0
			and blend(nodes.Authored.Baseline, EXIT.Green, EXIT.Strip + (1 - EXIT.Strip) * swell) or nodes.Strip
	end
	stampExit(nodes, true, facing, math.floor(bearing + 0.5))
end

local function undressExit(nodes)
	if not nodes or not nodes.Dressed then return end
	nodes.Dressed = false
	local authored, chevron, readout = nodes.Authored, nodes.Chevron, nodes.Readout
	if nodes.Centre then nodes.Centre.BackgroundColor3 = authored.Centre end
	if nodes.Baseline then nodes.Baseline.BackgroundColor3 = authored.Baseline end
	chevron.TextStrokeColor3, chevron.TextStrokeTransparency = authored.ChevronStroke, authored.ChevronStrokeAlpha
	readout.TextStrokeColor3, readout.TextStrokeTransparency = authored.ReadoutStroke, authored.ReadoutStrokeAlpha
	stampExit(nodes, nil, nil, nil)
end

-- `frame` is true on the every-frame exit repaint (the Heartbeat at the end of this file).
local function paintCompass(state, frame)
	local part = objective.Parts.Compass
	if not part or not part.Visible then return end
	local compass = state.Compass
	local nodes = compassNodes(part)
	local chevron, readout, ticks = nodes.Chevron, nodes.Readout, nodes.Ticks
	if not chevron or not readout then return end
	local mode = compass.State
	local color = UIStyle.Hud.Accent[state.Level] or P.Cream
	local glyph, text, fraction = "\u{25BC}", "LOCATING", 0.5
	local readColor = P.Sage
	local exit, facing, swell, bearing = false, false, 0, nil
	if mode == "calibrating" then text = "CALIBRATING"
	elseif mode == "inRoom" then text, color, readColor = "IN THIS ROOM", P.Coral, P.Coral
	elseif mode == "locked" and typeof(compass.Target) == "Vector3" then
		local _, origin = subject()
		local camera = workspace.CurrentCamera
		if origin and camera then
			local target, position = compass.Target, origin.Position
			local dx, dy, dz = target.X - position.X, target.Y - position.Y, target.Z - position.Z
			local metres = math.sqrt(dx * dx + dy * dy + dz * dz) / 3.571
			local look = camera.CFrame.LookVector
			bearing = math.deg(math.atan2(look.X * dz - look.Z * dx, look.X * dx + look.Z * dz))
			fraction = (math.clamp(bearing, -60, 60) + 60) / 120
			if bearing < -60 then glyph = "\u{25C0}" elseif bearing > 60 then glyph = "\u{25B6}" end
			if state.Title ~= "GET OUT" then
				text = tostring(math.floor(metres + 0.5)) .. " m"
			else
				-- EXIT_COMPASS_20261010: this branch IS exitLocked(state). Say what the needle points
				-- at, in the door's colour: "23 m" in the level's accent did not. "EXIT 999 m" is
				-- 10 characters and the row is authored for 12 ("IN THIS ROOM"). The word carries it
				-- for a player who cannot tell the green from the accent.
				exit, color, readColor = true, EXIT.Green, P.Cream
				local whole = math.floor(metres + 0.5)
				if nodes.Metres ~= whole then nodes.Metres, nodes.MetresText = whole, "EXIT " .. whole .. " m" end
				text = nodes.MetresText
				if metres < 8 then text, readColor = "AT THE EXIT", EXIT.Green end
				-- Facing: the centre line and the readout turn green while the camera looks at the
				-- exit, so "that way" is a state the player can see, not a triangle to line up.
				local now = workspace:GetServerTimeNow()
				objective.ExitAt = objective.ExitAt or now
				facing = math.abs(bearing) <= (objective.Facing and EXIT.FaceOut or EXIT.FaceIn)
				-- A swell is never joined or restarted in mid-phase (review, 2026-10-10). Finding the
				-- exit while the arrival swells still run starts no swell of its own: it took over at
				-- the three-second mark part-way up, a one-frame jump to near white. And finding it
				-- again inside a running facing swell (overshoot, correct back: how a camera is aimed)
				-- lets that swell finish instead of cutting it to green and starting over.
				if facing and not objective.Facing and now - objective.ExitAt >= EXIT.Swells
					and now - (objective.FacingAt or -math.huge) >= EXIT.FaceSwell then objective.FacingAt = now end
				objective.Facing = facing
				if facing then readColor = EXIT.Green end
				-- Arrival: the row first paints as an exit at the moment the maze goes dark, and
				-- nothing else announces it. Three slow swells of the chevron toward white and of the
				-- strip toward full green, then one short one each time the camera finds the exit.
				-- 1 Hz on a few hundred pixels; under ReduceFlashing nothing swells at all and the
				-- steady colours carry it.
				if player:GetAttribute("ReduceFlashing") ~= true then
					local since = now - objective.ExitAt
					if since < EXIT.Swells then
						swell = 0.5 - 0.5 * math.cos(since * 2 * math.pi)
					elseif objective.FacingAt and now - objective.FacingAt < EXIT.FaceSwell then
						swell = math.sin((now - objective.FacingAt) / EXIT.FaceSwell * math.pi)
					end
					if swell > 0 then color = blend(EXIT.Green, EXIT.White, 0.7 * swell) end
				end
			end
		elseif frame then
			-- No living subject or no camera: the 0.1 s render decides what the card shows then
			-- (it hides it). The every-frame needle must not flash LOCATING in between.
			return
		end
	end
	-- A symbol is a bounded bearing graphic, not a text line. Framewisp stamped the ASCII sample
	-- `v`; its width-exact font size cannot size the native fallback font for these triangles. Let
	-- the engine fit this one symbol inside the unchanged imported slot. Readable copy retains the
	-- touch 12 px floor; the glyph may fit below it when its fallback font has a taller em.
	local glyphSize = chevron:GetAttribute("HudBearingFontSize")
	if not glyphSize then
		glyphSize = chevron:GetAttribute("FigmaFontSize") or 14
		chevron:SetAttribute("HudBearingFontSize", glyphSize)
		-- Opt this clone out of Binder's deferred width-exact ASCII solve. The source template and
		-- every text line keep their original Figma stamp; a resize must not undo native glyph fit.
		chevron:SetAttribute("FigmaFontSize", nil)
		chevron.TextSize = math.max(12, glyphSize)
	end
	local fit = chevron:FindFirstChildOfClass("UITextSizeConstraint")
	if not fit then fit = Instance.new("UITextSizeConstraint"); fit.Parent = chevron end
	fit.MinTextSize, fit.MaxTextSize = 1, math.max(12, glyphSize)
	-- Roblox disables TextScaled when wrapping is disabled; this single glyph keeps both enabled.
	chevron.TextScaled, chevron.TextWrapped = true, true
	chevron.Text, chevron.TextColor3, readout.Text, readout.TextColor3 = glyph, color, text, readColor
	-- EXIT_COMPASS_20261010: the rest of the exit look, or its removal the first time this clone
	-- paints anything else. A row that never showed an exit is not written to here at all.
	if exit then dressExit(nodes, facing, swell, bearing) else undressExit(nodes) end
	-- Position along the authored tick strip, not the entire compass part (readout occupies its end).
	if ticks then
		local a, p, size = ticks.AnchorPoint, ticks.Position, ticks.Size
		local left = p.X.Scale - a.X * size.X.Scale
		local offset = p.X.Offset - a.X * size.X.Offset
		chevron.Position = UDim2.new(left + fraction * size.X.Scale, offset + fraction * size.X.Offset,
			chevron.Position.Y.Scale, chevron.Position.Y.Offset)
	end
end

renderObjective = function()
	if not objectiveAllowed() then
		if objective.Attention then objective.Attention:SetSuppressed(true) end
		return
	end
	if not mountObjective() then return end
	local state, parts, root = objective.State, objective.Parts, objective.Root
	local touch = objective.Bundle == "HUD_Touch"
	local who = subject()
	local viewKey = objective.Key .. ":" .. tostring(who and who.UserId) .. ":" .. tostring(player:GetAttribute("Spectating"))
	if objective.ViewKey ~= viewKey then objective.ViewKey = viewKey; expandObjective() end
	local expanded = not touch or objective.Expanded
	local counter = type(state.Count) == "number" and type(state.Goal) == "number" and state.Goal > 0
	for name, part in pairs(parts) do
		if name == "Head" or name == "Bar" then part.Visible = true
		elseif name == "Counter" or name == "Progress" then part.Visible = expanded and counter
		elseif name == "Guide1" then part.Visible = expanded and state.Lines[1] ~= nil
		elseif name == "Guide2" then part.Visible = expanded and state.Lines[2] ~= nil
		elseif name == "StatusRow" then part.Visible = state.Status ~= nil and (expanded or state.Status.Kind == "danger")
		-- EXIT_COMPASS_20261010: `expanded` is only ever false on touch, where a locked exit keeps
		-- its compass under the collapsed bar when that fits (pinsExit).
		elseif name == "Compass" then part.Visible = state.Compass ~= nil and (expanded or pinsExit(state, parts, root)) end
	end
	RoundHud.Paint(root, touch and "ObjectivePill" or "ObjectiveCard", state.Level)
	local eyebrow = state.Eyebrow or ("LEVEL " .. state.Level .. (state.Level == 4 and " \u{B7} THE LAST SHOW" or ""))
	if player:GetAttribute("Spectating") == true and who then
		eyebrow = "WATCHING " .. string.upper(who.DisplayName or who.Name) .. " \u{B7} LEVEL " .. state.Level
	end
	textAt(root, "Eyebrow", eyebrow, player:GetAttribute("Spectating") == true and P.RailTeal or UIStyle.Hud.Accent[state.Level])
	textAt(root, "Title", state.Title)
	local doneTint = state.Done and workspace:GetServerTimeNow() - (objective.ChangedAt or 0) < 6
	textAt(root, "Count", counter and (state.Count .. "/" .. state.Goal) or "", doneTint and P.RailTeal or P.Cream)
	textAt(root, "CountTag", state.Tag or "")
	local fill = Binder.at(root, "Progress/Track/Fill")
	if fill then
		fill.Size = UDim2.fromScale(counter and math.clamp(state.Count / state.Goal, 0, 1) or 0, 1)
		if doneTint then fill.BackgroundColor3 = P.RailTeal end
	end
	for index = 1, 2 do textAt(root, "Guide" .. index .. "/Line", state.Lines[index]) end
	if objective.OrderHit then objective.OrderHit.Visible = expanded and type(state.OnOrderActivate) == "function" end
	if state.Status then
		local color = state.Status.Kind == "danger" and P.Coral or state.Status.Kind == "warning" and P.Amber or P.Sage
		textAt(root, "StatusRow/Label", state.Status.Text, color)
		local bar = Binder.at(root, "StatusRow/Bar")
		if bar then bar.BackgroundColor3 = color end
	end
	-- EXIT_COMPASS_20261010: the arrival swell plays once per exit, so its clock and the facing
	-- latch are dropped whenever the objective is not a locked exit. Here, not in paintCompass: that
	-- returns early on a hidden row and would never get to it. Clear() drops them with the round.
	if not exitLocked(state) then
		objective.ExitAt, objective.Facing, objective.FacingAt = nil, nil, nil
		undressExit(objective.CompassNodes)
	end
	paintCompass(state)
	placeObjective()
	objective.Attention:SetSuppressed(not objective.Fits)
	if objective.Fits then
		objective.Attention:Show(viewKey, state.Status and state.Status.Kind == "danger")
	end
end

function RoundHud.SetObjective(state)
	-- An inactive receiver's nil/stale tick must never hide the currently selected receiver's card.
	if type(state) ~= "table" or type(state.Level) ~= "number" or type(state.Title) ~= "string"
		or state.Level ~= workspace:GetAttribute("SelectedLevel") then return false end
	local fixture = workspace:GetAttribute("UIRegressionForceLevel3Reader") == true
		or player:GetAttribute("UIRegressionForceLevel3Reader") == true
	if not fixture and (not inRound() or not subject()) then return false end
	local copy = {Level = state.Level, Eyebrow = state.Eyebrow, Title = state.Title, Count = state.Count,
		Goal = state.Goal, Tag = state.Tag, Lines = {}, Done = state.Done == true, OnOrderActivate = state.OnOrderActivate}
	for index = 1, 2 do
		if type(state.Lines) == "table" and type(state.Lines[index]) == "string" then copy.Lines[index] = state.Lines[index] end
	end
	if type(state.Status) == "table" and type(state.Status.Text) == "string" then
		copy.Status = {Text = state.Status.Text, Kind = state.Status.Kind}
	end
	if type(state.Compass) == "table" then copy.Compass = {State = state.Compass.State, Target = state.Compass.Target} end
	if type(copy.Count) == "number" and type(copy.Goal) == "number" and copy.Goal > 0 then
		copy.Counter = {Label = copy.Tag, Current = copy.Count, Max = copy.Goal}
	end
	local key = semantic(copy)
	objective.State, lastObjective = copy, copy
	if objective.Key ~= key then objective.Key, objective.ChangedAt = key, workspace:GetServerTimeNow(); expandObjective() end
	renderObjective()
	return true
end

function RoundHud.LastObjective()
	return lastObjective
end

-- -- pooled action feed and optional dialogue caption ------------------------

local feed = {Rows = {}, Entries = {}, Serial = 0}
local caption = {Serial = 0}
local updateDetectorPlacement
local function laneScale(bundle)
	if bundle ~= "HUD_Touch" then return 1 end
	local safe = UIDevice.Layout().Safe
	-- The imported touch lane is 358 px. Scale its geometry once on narrow phones, with the
	-- readable text's 12 px constraint applied by Mount after scaling (no nested UIScale).
	return math.clamp((safe.Right - safe.Left - 16) / 358, 0.85, 1)
end
local function fitLaneText(root, scale)
	if not root or scale >= 1 then return end
	-- Only the lane's width has to contract. Restore its authored line height so captions,
	-- actor names and the initial badge retain room for a native12px font at the0.85 limit.
	root.Size = UDim2.fromOffset(root.Size.X.Offset, math.round(root.Size.Y.Offset / scale))
	for _, node in ipairs(root:GetDescendants()) do
		if isText(node) then
			local limit = node:FindFirstChildOfClass("UITextSizeConstraint")
			if limit then
				-- Preserve readable12px copy while the line width contracts, instead of shrinking
				-- the entire label through a UIScale.
				limit.MaxTextSize = math.max(12, limit.MinTextSize)
				node.TextSize = limit.MaxTextSize
			end
		end
	end
end
local feedWordLayouts = setmetatable({}, {__mode = "k"})
local flowFeedWords
flowFeedWords = function(words)
	if not words or not words.Parent then return end
	local who, detail = Binder.text(Binder.at(words, "Who")), Binder.text(Binder.at(words, "Detail"))
	if not who or not detail then return end
	local layout = feedWordLayouts[words]
	if not layout then
		local whoLeft = who.Position.X.Scale - who.AnchorPoint.X * who.Size.X.Scale
		local detailLeft = detail.Position.X.Scale - detail.AnchorPoint.X * detail.Size.X.Scale
		layout = {Left = whoLeft, Gap = math.max(0, detailLeft - whoLeft - who.Size.X.Scale)}
		feedWordLayouts[words] = layout
		-- These are two text fields, rather than a title plus fixed chips. Keep Binder's font solve,
		-- but own both boxes and reapply truncation after its deferred fitLine clears TextTruncate.
		who:SetAttribute("BinderFlowTitle", true)
		detail:SetAttribute("BinderFlowTitle", true)
		local function again()
			if layout.Queued then return end
			layout.Queued = true
			task.defer(function() layout.Queued = false; flowFeedWords(words) end)
		end
		for _, node in ipairs({who, detail}) do
			node:GetPropertyChangedSignal("TextBounds"):Connect(again)
			node:GetPropertyChangedSignal("TextTruncate"):Connect(again)
		end
		words:GetPropertyChangedSignal("AbsoluteSize"):Connect(again)
	end
	local width = words.AbsoluteSize.X
	if width <= 0 then return end
	local left, gap = layout.Left * width, who.Text ~= "" and layout.Gap * width or 0
	local room = math.max(0, width - left)
	-- Retain the full DisplayName in Text. Cache its full measured width so native ellipsis cannot
	-- make the allocation oscillate between the shortened and complete rendered name.
	local key = who.Text .. "@" .. tostring(who.TextSize)
	if layout.Key ~= key then layout.Key, layout.NameWidth = key, 0 end
	layout.NameWidth = math.max(layout.NameWidth, who.TextBounds.X)
	local detailKey = detail.Text .. "@" .. tostring(detail.TextSize)
	if layout.DetailKey ~= detailKey then layout.DetailKey, layout.DetailWidth = detailKey, 0 end
	layout.DetailWidth = math.max(layout.DetailWidth, detail.TextBounds.X)
	local detailBudget = math.min(layout.DetailWidth, math.max(48, room * 0.5))
	local nameWidth = math.min(math.ceil(layout.NameWidth), math.max(0, room - gap - detailBudget))
	local detailWidth = math.max(0, room - nameWidth - gap)
	for index, node in ipairs({who, detail}) do
		local box = index == 1 and nameWidth or detailWidth
		local x = index == 1 and left or left + nameWidth + gap
		if node.Size.X.Scale ~= 0 or node.Size.X.Offset ~= box then
			node.Size = UDim2.new(0, box, node.Size.Y.Scale, node.Size.Y.Offset)
		end
		local offset = x + node.AnchorPoint.X * box
		if node.Position.X.Scale ~= 0 or node.Position.X.Offset ~= offset then
			node.Position = UDim2.new(0, offset, node.Position.Y.Scale, node.Position.Y.Offset)
		end
		node.TextXAlignment = Enum.TextXAlignment.Left
		node.Visible = node.Text ~= ""
		local need = index == 1 and layout.NameWidth or layout.DetailWidth
		local truncate = need > box + 1 and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None
		if node.TextTruncate ~= truncate then node.TextTruncate = truncate end
	end
end

local function actorName(actor)
	local who
	if typeof(actor) == "Instance" and actor:IsA("Player") then who = actor
	elseif type(actor) == "number" then who = Players:GetPlayerByUserId(actor)
	elseif type(actor) == "string" then who = Players:FindFirstChild(actor) end
	return who and (who.DisplayName or who.Name) or (actor ~= nil and tostring(actor) or "")
end

local function feedAllowed()
	return inRound() and not covered()
end

local HIDE_PARTS = {"HiddenStatus", "LeaveHiding", "TableCheck"}
local function visible(node)
	if not node then return false end
	local at = node
	while at do
		if at:IsA("GuiObject") and not at.Visible then return false end
		if at:IsA("ScreenGui") then return at.Enabled end
		at = at.Parent
	end
	return false
end

local function laneTop()
	local safe = UIDevice.Layout().Safe
	local y = safe.Top + 12
	if player:GetAttribute("Level3_Hiding") == true then
		local pg = player:FindFirstChild("PlayerGui")
		local hiding = pg and pg:FindFirstChild("Level3TableHideUI")
		if hiding and hiding.Enabled then
			for _, name in ipairs(HIDE_PARTS) do
				local node = hiding:FindFirstChild(name, true)
				if node and node:IsA("GuiObject") and visible(node) then
					y = math.max(y, node.AbsolutePosition.Y + node.AbsoluteSize.Y + 8)
				end
			end
		end
	end
	return y
end

local function touchLane(width, height)
	local safe = UIDevice.Layout().Safe
	local x, y = safe.Left + 68, laneTop()
	if width > safe.Right - safe.Left - 16 then return x, y, false end
	if x + width > safe.Right - 8 then
		x = safe.Right - 8 - width
		-- A portrait lane that cannot stay beside the door starts below its44px target.
		y = math.max(y, safe.Top + 6 + 44 + 8)
	end
	local card = objective.Root
	if visible(card) then
		local origin = RoundHud.Gui().AbsolutePosition
		local left, top = card.Position.X.Offset + origin.X, card.Position.Y.Offset + origin.Y
		if x < left + card.Size.X.Offset and x + width > left and y < top + card.Size.Y.Offset
			and y + height > top then y = top + card.Size.Y.Offset + 8 end
	end
	return x, y, y + height <= safe.Bottom
end

local function unmountFeed()
	for _, row in ipairs(feed.Rows) do row:Destroy() end
	feed.Rows = {}
	if caption.Root then caption.Root:Destroy() end
	caption.Root = nil
end

local function renderFeed()
	local now, bundle = workspace:GetServerTimeNow(), RoundHud.Bundle()
	local scale = laneScale(bundle)
	for index = #feed.Entries, 1, -1 do
		if feed.Entries[index].Until <= now then table.remove(feed.Entries, index) end
	end
	if caption.Until and caption.Until <= now then caption.Text, caption.Until = nil, nil end
	if feed.Bundle ~= bundle or feed.Scale ~= scale then unmountFeed(); feed.Bundle, feed.Scale = bundle, scale end
	local touch, allowed = bundle == "HUD_Touch", feedAllowed()
	local captionScope = if caption.Dispatch then player:GetAttribute("DispatchTextActive") == true and not covered() else allowed
	local captionAllowed = captionScope and caption.Text ~= nil and player:GetAttribute("CaptionsEnabled") ~= false
		and player:GetAttribute("DisableCaptions") ~= true
	local count = touch and 1 or 2
	local safe = UIDevice.Layout().Safe
	for index = 1, count do
		local entry = feed.Entries[#feed.Entries - count + index]
		-- With fewer than two entries use the first lane, keeping chronological order for two.
		if #feed.Entries < count then entry = feed.Entries[index] end
		local root = feed.Rows[index]
		if entry and not root then
			root = RoundHud.Mount(bundle, touch and "FeedRowTouch" or "FeedRow", RoundHud.Gui(),
				{Name = "FeedRow" .. index, Scale = scale})
			fitLaneText(root, scale)
			feed.Rows[index] = root
		end
		if root then
			root.Visible = allowed and entry ~= nil and not (touch and captionAllowed)
			if entry then
				local color = entry.Kind == "TEAM" and P.RailTeal or entry.Kind == "DANGER" and P.Coral
					or entry.Kind == "LEVEL" and P.Amber or P.Cream
				local bar, dot = Binder.at(root, "Bar"), Binder.at(root, "Dot")
				if bar then bar.Visible = entry.Kind ~= "LEVEL"; bar.BackgroundColor3 = color end
				if dot then dot.Visible = entry.Kind == "LEVEL"; dot.BackgroundColor3 = P.Amber end
				local name = actorName(entry.Actor)
				textAt(root, "Words/Who", name)
				textAt(root, "Words/Detail", entry.Detail)
				local nextCharacter = utf8.offset(name, 2) or (#name + 1)
				textAt(root, "Initial/Letter", string.upper(string.sub(name, 1, nextCharacter - 1)))
				local initial = Binder.at(root, "Initial")
				if initial then initial.Visible = name ~= "" end
				local words = Binder.at(root, "Words")
				if words then flowFeedWords(words) end
			end
			local width = root.Size.X.Offset
			local x, y, fits = (safe.Left + safe.Right - width) / 2, laneTop(), width <= safe.Right - safe.Left
			if touch then x, y, fits = touchLane(width, root.Size.Y.Offset) end
			root.Visible = root.Visible and fits
			root.Position = UIDevice.LocalPosition(RoundHud.Gui(), x, y + (index - 1) * (root.Size.Y.Offset + 4))
		end
	end
	if captionAllowed and not caption.Root then
		caption.Root = RoundHud.Mount(bundle, touch and "CaptionTouch" or "Caption", RoundHud.Gui(), {Name = "Caption", Scale = scale})
		fitLaneText(caption.Root, scale)
	end
	if caption.Root then
		caption.Root.Visible = captionAllowed
		textAt(caption.Root, "Speaker", caption.Speaker)
		textAt(caption.Root, "Said", caption.Text)
		local width, height = caption.Root.Size.X.Offset, caption.Root.Size.Y.Offset
		local x = (safe.Left + safe.Right - width) / 2
		local narrow = safe.Right - safe.Left < 872
		local topDistance = (narrow and 258 or 54) + 24
		if player:GetAttribute("Spectating") == true then topDistance = (narrow and 228 or 24) + 92 + 26 end
		local y = touch and laneTop() or safe.Bottom - topDistance - 8 - height
		local fits = width <= safe.Right - safe.Left and y >= safe.Top
		if touch then x, y, fits = touchLane(width, height) end
		caption.Root.Visible = caption.Root.Visible and fits
		caption.Root.Position = UIDevice.LocalPosition(RoundHud.Gui(), x, y)
	end
	if updateDetectorPlacement then updateDetectorPlacement() end
end

function RoundHud.Feed(row)
	if type(row) ~= "table" or type(row.Detail) ~= "string" or not feedAllowed() then return false end
	local now = workspace:GetServerTimeNow()
	local entry
	if row.Key ~= nil then
		for _, existing in ipairs(feed.Entries) do
			if existing.Key == row.Key and now - existing.At <= 2 then entry = existing break end
		end
	end
	if not entry then entry = {}; table.insert(feed.Entries, entry) end
	local actor = row.Actor or row.Who
	-- A later local LEVEL toast must not remove the team actor or its validated progress copy.
	if actor ~= nil or entry.Actor == nil then
		entry.Kind, entry.Actor, entry.Detail = row.Kind or "SYSTEM", actor, row.Detail
	end
	entry.Key = row.Key
	entry.At, entry.Until = now, now + 4
	while #feed.Entries > 2 do table.remove(feed.Entries, 1) end
	feed.Serial += 1
	renderFeed()
	task.delay(4, renderFeed)
	return true
end

function RoundHud.Caption(speaker, text, seconds)
	if seconds == 0 then
		caption.Serial += 1
		caption.Text, caption.Until = nil, nil
		renderFeed()
		return true
	end
	local dispatch = speaker == "COMMAND CENTER" and player:GetAttribute("DispatchTextActive") == true
	local eligible = if dispatch then not covered() else feedAllowed()
	if type(text) ~= "string" or not eligible or player:GetAttribute("CaptionsEnabled") == false
		or player:GetAttribute("DisableCaptions") == true then return false end
	caption.Serial += 1
	caption.Speaker, caption.Text, caption.Dispatch = tostring(speaker or ""), text, dispatch
	caption.Until = workspace:GetServerTimeNow() + (type(seconds) == "number" and math.clamp(seconds, 0, 3.5) or 3.5)
	renderFeed()
	task.delay(3.5, renderFeed)
	return true
end

-- -- detector card (09 C) ---------------------------------------------------

local LEVELS = {
	LOW = {Lit = 1, Color = P.Sage},
	MEDIUM = {Lit = 2, Color = P.Amber},
	HIGH = {Lit = 3, Color = P.Coral},
}
-- PC: above the SCAN chip; with no chip drawn, above the bottom-left kit row (bottom -24, the
-- 84-tall HUD_PC/EquipmentPanel, gap 8). Both clear the refusal tag's band (EquipmentCaption, 24 tall,
-- 8 above the row), so a refusal during a reading never draws under the card (owner, 2026-10-08).
-- Phone: under the one feed row, in the feed lane, which starts 68 px right of the safe left edge (x 115 on the 844 px design, safe left 47).
-- The real HUD_Touch import agrees: its DetectorLine spans x 115..473, y 110..134 (owner, 2026-10-08).
local CAPTION_BAND = 24 + 8
local KIT_TOP = 24 + 84 + 8 + CAPTION_BAND
local TOUCH_LANE_X, TOUCH_LANE_Y = 68, 52

local detector = {Serial = 0}

local function setText(root, name, text, color)
	local node = Binder.text(Binder.find(root, name))
	if not node then return end
	node.Text = text
	if color then node.TextColor3 = color end
end

local function placeDetector(root)
	local safe = UIDevice.Layout().Safe
	local hudGui = RoundHud.Gui()
	if detector.Bundle == "HUD_Touch" then
		root.AnchorPoint = Vector2.new(0, 0)
		local x, y, fits = touchLane(root.Size.X.Offset, 32)
		local laneHeight = caption.Root and caption.Root.Visible and math.max(32, caption.Root.Size.Y.Offset) or 32
		root.Position = UIDevice.LocalPosition(hudGui, x, y + laneHeight + 8)
		detector.Fits = fits and y + laneHeight + 8 + root.Size.Y.Offset <= safe.Bottom
		if detector.Attention then detector.Attention:SetSuppressed(not detector.Fits or covered()) end
		return
	end
	detector.Fits = true
	local x, y = safe.Left + 24, safe.Bottom - KIT_TOP
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local protection = playerGui and playerGui:FindFirstChild("ProtectionHUD")
	local scan = protection and Binder.find(protection, "Chip_Scan")
	if scan and scan:IsA("GuiObject") and scan.Visible and scan.AbsoluteSize.X > 0 then
		x, y = scan.AbsolutePosition.X, scan.AbsolutePosition.Y - 8 - CAPTION_BAND
	end
	root.AnchorPoint = Vector2.new(0, 1)
	root.Position = UIDevice.LocalPosition(hudGui, x, y)
end

updateDetectorPlacement = function()
	if detector.Root and detector.Bundle == "HUD_Touch" then placeDetector(detector.Root) end
end

local function renderDetector(remaining)
	if covered() then
		if detector.Attention then detector.Attention:SetSuppressed(true) end
		return
	end
	local reading = detector.Reading
	local level = LEVELS[reading]
	local bundle = RoundHud.Bundle()
	local scale = laneScale(bundle)
	local priorAttention = detector.Bundle == bundle and detector.Attention or nil
	if detector.Root and (detector.Bundle ~= bundle or detector.Scale ~= scale) then
		if detector.Attention.Tween then detector.Attention.Tween:Cancel(); detector.Attention.Tween = nil end
		detector.Root:Destroy()
		detector.Root, detector.Attention = nil, nil
	end
	if not detector.Root then
		detector.Bundle, detector.Scale = bundle, scale
		detector.Root, detector.Attention = RoundHud.Mount(bundle,
			bundle == "HUD_Touch" and "DetectorLine" or "DetectorCard", RoundHud.Gui(),
			{Name = "DetectorCard", Scale = scale, Attention = {Hold = 4, Rest = 0}})
		if not detector.Root then return end
		fitLaneText(detector.Root, scale)
		-- A width-only remount changes no scan state. Keep its original attention deadlines; delayed
		-- hold callbacks use this attention object and will now fade the replacement group.
		if priorAttention then
			detector.Attention = priorAttention
			priorAttention.Group = detector.Root
			local opacity = priorAttention.Suppressed and 0 or (priorAttention.Opacity or 0)
			detector.Root.Visible, detector.Root.GroupTransparency = opacity > 0, 1 - opacity
		end
	end
	local root = detector.Root
	detector.Attention:SetSuppressed(false)
	placeDetector(root)
	for index = 1, 3 do
		local bar = Binder.at(root, "Bars/Bar" .. index)
		if bar then bar.BackgroundColor3 = index <= level.Lit and level.Color or P.Line end
	end
	local headline = Visual.Labels[reading]
	setText(root, "Reading", "SCAN \u{B7} " .. reading, level.Color)
	setText(root, "Headline", headline)
	setText(root, "Seconds", math.ceil(remaining) .. " s")
	setText(root, "Line", "SCAN \u{B7} " .. reading .. " \u{B7} " .. headline, level.Color)
	detector.Attention:Show(reading .. "@" .. tostring(detector.ExpiresAt), reading == "HIGH")
end

-- One tick per displayed second, so the countdown and the expiry land exactly.
local function tickDetector(serial)
	if detector.Serial ~= serial or not detector.Reading then return end
	local remaining = detector.ExpiresAt - workspace:GetServerTimeNow()
	if remaining <= 0 then
		RoundHud.Detector(nil)
		return
	end
	renderDetector(remaining)
	task.delay(remaining - math.ceil(remaining) + 1, tickDetector, serial)
end

function RoundHud.Detector(reading, expiresAt)
	detector.Serial += 1
	if not LEVELS[reading] or type(expiresAt) ~= "number" then
		detector.Reading = nil
		if detector.Attention then detector.Attention:SetSuppressed(covered()); detector.Attention:Hide() end
		return
	end
	detector.Reading, detector.ExpiresAt = reading, expiresAt
	tickDetector(detector.Serial)
end

-- -- teardown and device changes --------------------------------------------

function RoundHud.Clear()
	detector.Serial += 1
	detector.Reading = nil
	if detector.Attention then detector.Attention:Hide() end
	if detector.Root then detector.Root:Destroy() end
	detector.Root, detector.Attention, detector.Bundle = nil, nil, nil
	objective.Serial += 1
	objective.State, objective.Key, objective.ViewKey, objective.Expanded = nil, nil, nil, false
	objective.ExitAt, objective.Facing, objective.FacingAt = nil, nil, nil -- EXIT_COMPASS_20261010: the next round's exit swells again
	unmountObjective()
	feed.Serial += 1
	feed.Entries = {}
	caption.Serial += 1
	caption.Text, caption.Until = nil, nil
	unmountFeed()
	-- lastObjective survives teardown: B8 reads this stable loss-counter snapshot after InRound ends.
end

-- A Studio QA caller must enter through the real player's BindableFunction, never a second require
-- cache. Snapshots contain immutable plain data, absolute deadlines and attention state; restoring
-- invalidates old timers, rebuilds only owned roots and preserves the pre-test loss snapshot (nil
-- included). Caller-owned marker/stamina and their Attention objects never enter this snapshot.
local function copyPlain(value, frozen, seen)
	if typeof(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local copy = {}
	seen[value] = copy
	for key, item in pairs(value) do copy[key] = copyPlain(item, frozen, seen) end
	return frozen and table.freeze(copy) or copy
end

local function captureAttention(attention)
	if not attention then return nil end
	return {Key = attention.Key, Urgent = attention.Urgent, Shown = attention.Shown, Held = attention.Held,
		HoldUntil = attention.HoldUntil, RestNow = attention.RestNow, Opacity = attention.Opacity,
		Suppressed = attention.Suppressed}
end

local function restoreAttention(attention, state)
	if not attention or not state then return end
	if attention.Tween then attention.Tween:Cancel(); attention.Tween = nil end
	attention.Serial += 1
	attention.Key, attention.Urgent, attention.Shown = state.Key, state.Urgent, state.Shown
	attention.RestNow, attention.HoldUntil = state.RestNow, state.HoldUntil
	local remaining = (state.HoldUntil or 0) - workspace:GetServerTimeNow()
	attention.Held = state.Held == true and remaining > 0
	local opacity = state.Opacity or 0
	if state.Held and not attention.Held and not state.Urgent then opacity = state.RestNow or attention.Rest end
	attention.Opacity = opacity
	local drawn = attention.Suppressed and 0 or opacity
	attention.Group.GroupTransparency, attention.Group.Visible = 1 - drawn, drawn > 0
	if attention.Held then
		local serial = attention.Serial
		task.delay(remaining, function()
			if attention.Serial ~= serial then return end
			attention.Held = false
			if not attention.Urgent then fadeTo(attention, attention.RestNow or attention.Rest, FADE_OUT) end
		end)
	end
end

function RoundHud.CaptureTestState()
	if not RunService:IsStudio() then return nil end
	return copyPlain({Kind = "RoundHudTestState", LastObjective = lastObjective,
		Objective = {State = objective.State, Key = objective.Key, ViewKey = objective.ViewKey,
			Expanded = objective.Expanded, ExpandUntil = objective.ExpandUntil, ChangedAt = objective.ChangedAt,
			Attention = captureAttention(objective.Attention)},
		Feed = {Entries = feed.Entries},
		Caption = {Speaker = caption.Speaker, Text = caption.Text, Until = caption.Until, Dispatch = caption.Dispatch},
		Detector = {Reading = detector.Reading, ExpiresAt = detector.ExpiresAt, Attention = captureAttention(detector.Attention)},
	}, true)
end

function RoundHud.RestoreTestState(snapshot)
	if not RunService:IsStudio() or type(snapshot) ~= "table" or snapshot.Kind ~= "RoundHudTestState" then return false end
	local saved = copyPlain(snapshot, false)
	RoundHud.Clear()
	lastObjective = saved.LastObjective
	local state = saved.Objective
	objective.State, objective.Key, objective.ViewKey = state.State, state.Key, state.ViewKey
	objective.ExpandUntil, objective.ChangedAt = state.ExpandUntil, state.ChangedAt
	local danger = state.State and state.State.Status and state.State.Status.Kind == "danger"
	objective.Expanded = state.Expanded == true and (danger or (state.ExpandUntil or 0) > workspace:GetServerTimeNow())
	if objective.State then
		renderObjective()
		restoreAttention(objective.Attention, state.Attention)
		if objective.Expanded and not danger then
			local serial = objective.Serial
			task.delay(math.max(0, objective.ExpandUntil - workspace:GetServerTimeNow()), function()
				if objective.Serial ~= serial then return end
				objective.Expanded = false
				renderObjective()
			end)
		end
	end
	feed.Entries = saved.Feed.Entries
	caption.Speaker, caption.Text, caption.Until, caption.Dispatch = saved.Caption.Speaker, saved.Caption.Text,
		saved.Caption.Until, saved.Caption.Dispatch
	renderFeed()
	if saved.Detector.Reading and (saved.Detector.ExpiresAt or 0) > workspace:GetServerTimeNow() then
		RoundHud.Detector(saved.Detector.Reading, saved.Detector.ExpiresAt)
		restoreAttention(detector.Attention, saved.Detector.Attention)
	end
	return true
end

function RoundHud.ExpandObjectiveForTest()
	if not RunService:IsStudio() then return false end
	return tapObjective()
end

UIDevice.Changed:Connect(function()
	for chip, keys in pairs(keycaps) do
		if chip.Parent then applyKeycap(chip, keys[1], keys[2]) end
	end
	if detector.Reading then
		local remaining = detector.ExpiresAt - workspace:GetServerTimeNow()
		if remaining > 0 then renderDetector(remaining) end
	end
	if objective.State then renderObjective() end
	renderFeed()
end)

local watchedPlayer, watchedConnections = nil, {}
local refreshOwned
local function watchSubject()
	local id = player:GetAttribute("SpectateTargetUserId")
	local who = player:GetAttribute("Spectating") == true and type(id) == "number" and Players:GetPlayerByUserId(id) or nil
	if who == watchedPlayer then return end
	for _, connection in ipairs(watchedConnections) do connection:Disconnect() end
	watchedPlayer, watchedConnections = who, {}
	if who then
		for _, attribute in ipairs({"InRound", "Escaped", "EscapedRound", "Level3_Hiding"}) do
			table.insert(watchedConnections, who:GetAttributeChangedSignal(attribute):Connect(function() refreshOwned() end))
		end
	end
end
refreshOwned = function()
	watchSubject()
	if objective.State then renderObjective() end
	renderFeed()
	if detector.Attention then
		local suppressed, wasSuppressed = covered() or detector.Fits == false, detector.Attention.Suppressed
		detector.Attention:SetSuppressed(suppressed)
		if detector.Reading and wasSuppressed and not suppressed then
			local remaining = detector.ExpiresAt - workspace:GetServerTimeNow()
			if remaining > 0 then renderDetector(remaining) end
		end
	end
end
for _, attribute in ipairs({"InRound", "Spectating", "SpectateTargetUserId", "Escaped", "EscapedRound",
	"ZyntraDispatchClientActive", "LevelLoadingOpen", "PartyDownCardOpen", "RoundExitPromptOpen",
	"Level3_Hiding", "CaptionsEnabled", "DisableCaptions", "DispatchTextActive"}) do
	player:GetAttributeChangedSignal(attribute):Connect(refreshOwned)
end
for _, attribute in ipairs({"SelectedLevel", "RoundActive"}) do
	workspace:GetAttributeChangedSignal(attribute):Connect(refreshOwned)
end
if UIDevice.OnScreenOwningModalChanged then UIDevice.OnScreenOwningModalChanged(refreshOwned) end
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	-- EXIT_COMPASS_20261010: the compass's only clock was the 0.1 s refresh below, so the needle
	-- stepped ten times a second while the player turned. A locked exit repaints its row every
	-- frame instead: one atan2 and a handful of property writes on cached nodes, and a write of
	-- the value a property already has fires nothing. Only the exit: every other compass state
	-- keeps its 0.1 s clock. Root.Visible is the last 0.1 s render's verdict on whether the card
	-- may show (modals, loading, a wrong level, a card that does not fit).
	local state = objective.State
	if exitLocked(state) and objective.Parts and objective.Root and objective.Root.Visible then paintCompass(state, true) end
	elapsed += dt
	if elapsed < 0.1 then return end
	elapsed = 0
	refreshOwned()
end)

return RoundHud

end end,
ShopBinder=function() return function()
-- ShopBinder (ReplicatedStorage.ZyntraShopUI.ShopBinder)
--
-- The NAME CONTRACT between a Framewisp import and the code that drives it
-- (L4-ROBLOX-PLAN.md section 2.2, INTEGRATION-CONTRACT.md section 6). No state,
-- no remotes, no purchases: every function here is a pure read or a write to
-- the instances it is handed.
--
-- WHY TAG-TOLERANT. Framewisp layer names carry tags (`Buy_button`,
-- `Tab_Shop_tab:Shop`, `Close_button_close`). The 2026-10-06 import dropped
-- them all (tests/framewisp-dump.*.json: namesKeepingTags 0), but a re-export
-- may not, so every lookup compares BASE names: the same node binds as
-- `Buy_button`, `Buy` or `Buy` with `_tab_Shop` in place of `_tab:Shop`.
--
-- WHY CLASS-TOLERANT. A `_button` may arrive as a TextButton, an ImageButton or
-- a plain Frame, and an image fill as an ImageLabel or as a Frame holding one.
-- `button`, `text` and `image` hand back something with the property the caller
-- needs whatever class arrived. (The 2026-10-06 import made every tap target a
-- TextButton; the Frame overlay path is kept for re-exports.)

local Binder = {}

-- Framewisp's tag vocabulary plus the two layout tags the contract allows.
local TAGS = {
	button = true, close = true, panel = true, tabgroup = true, scroll = true,
	grid = true, list = true, txt = true, shadow = true, image = true,
	ignore = true, aspect = true, fit = true,
}

-- STYLE-GUIDE.md colour roles. One table so the controller and the skins paint
-- with the same numbers the Figma file was drawn with.
local P = {
	Tile = Color3.fromRGB(22, 29, 32),        -- #161D20
	TileHi = Color3.fromRGB(29, 38, 42),      -- #1D262A
	Ink = Color3.fromRGB(5, 9, 11),           -- #05090B
	Line = Color3.fromRGB(38, 49, 52),        -- #263134
	Cream = Color3.fromRGB(242, 235, 219),    -- #F2EBDB
	Sage = Color3.fromRGB(167, 184, 174),     -- #A7B8AE
	IconTeal = Color3.fromRGB(75, 180, 176),  -- #4BB4B0
	RailTeal = Color3.fromRGB(68, 221, 196),  -- #44DDC4
	Amber = Color3.fromRGB(232, 160, 36),     -- #E8A024
	AmberStroke = Color3.fromRGB(156, 100, 16), -- #9C6410
	TokenStroke = Color3.fromRGB(45, 119, 116), -- #2D7774
	OwnedFill = Color3.fromRGB(16, 41, 42),   -- #10292A
	Coral = Color3.fromRGB(242, 112, 95),     -- #F2705F
	CoralStroke = Color3.fromRGB(180, 71, 58), -- #B4473A, the import's Close ring
	Lime = Color3.fromRGB(196, 240, 108),     -- #C4F06C
}
Binder.Palette = P

-- Per-state button palette (STYLE-GUIDE "PRICE BUTTONS").
local STATES = {
	robux = {Face = P.Amber, Stroke = P.AmberStroke, Text = P.Tile, Shadow = true},
	token = {Face = P.IconTeal, Stroke = P.TokenStroke, Text = P.Tile, Shadow = true},
	owned = {Face = P.OwnedFill, Stroke = P.RailTeal, Text = P.RailTeal, Shadow = false},
	off = {Face = P.TileHi, Stroke = P.Line, Text = P.Sage, Shadow = false},
	equip = {Face = P.Cream, Stroke = P.Line, Text = P.Tile, Shadow = true},
}

-- -- names ----------------------------------------------------------------

-- Returns the base name and the set of tags that were stripped.
--   Close_button_close -> Close        Tab_Shop_tab:Shop -> Tab_Shop
--   Products_scroll    -> Products     Donate_Donation10000 -> unchanged
function Binder.base(name)
	local base = tostring(name)
	local tags = {}
	local stripped, count = base:gsub("_tab[:_][%w]+$", "", 1)
	if count > 0 then base = stripped; tags.tab = true end
	while true do
		local head, tag = base:match("^(.+)_(%a+)$")
		if not head or not TAGS[tag] then break end
		base = head
		tags[tag] = true
	end
	return base, tags
end

-- First descendant (preorder) whose base name is `base`.
function Binder.find(root, base)
	if not root then return nil end
	for _, child in ipairs(root:GetChildren()) do
		if Binder.base(child.Name) == base then return child end
		local found = Binder.find(child, base)
		if found then return found end
	end
	return nil
end

-- A "/"-separated chain of finds; "" or "." is `root` itself. Each step is a
-- descendant search, so wrappers (Art, BuySlot) never have to be named.
function Binder.at(root, path)
	if path == nil or path == "" or path == "." then return root end
	local node = root
	for segment in string.gmatch(path, "[^/]+") do
		node = Binder.find(node, segment)
		if not node then return nil end
	end
	return node
end

-- {[suffix] = node} for every descendant whose base starts with `prefix`
-- (Card_, SkinCard_, Donate_, Tab_, Page_, OddsRow_, Preset_). First wins.
function Binder.all(root, prefix)
	local out = {}
	if not root then return out end
	for _, node in ipairs(root:GetDescendants()) do
		local base = Binder.base(node.Name)
		if #base > #prefix and base:sub(1, #prefix) == prefix then
			local suffix = base:sub(#prefix + 1)
			if out[suffix] == nil then out[suffix] = node end
		end
	end
	return out
end

-- -- class tolerance ------------------------------------------------------

-- The input target for `node`: itself when it is a GuiButton with no button
-- inside it, otherwise a transparent TextButton laid over it (one per name, so
-- this is idempotent). A Price or TokenGlyph that arrived as a TextButton or
-- ImageButton would otherwise take the taps on the middle of its face and do
-- nothing with them. `z` overrides the computed ZIndex (the skin cards' select
-- hit sits UNDER Buy, so it leaves the buttons inside the card alone).
function Binder.button(node, name, z)
	name = name or "Hit"
	local hit = node:FindFirstChild(name)
	if hit and hit:IsA("GuiButton") then return hit end
	local inner = {}
	for _, child in ipairs(node:GetDescendants()) do
		if child:IsA("GuiButton") then table.insert(inner, child) end
	end
	if node:IsA("GuiButton") then
		node.AutoButtonColor = false
		if #inner == 0 then return node end
		node.Selectable = false
	end
	if not z then
		for _, button in ipairs(inner) do
			button.AutoButtonColor = false
			button.Selectable = false
		end
	end
	local top = 0
	for _, child in ipairs(node:GetDescendants()) do
		if child:IsA("GuiObject") and child.ZIndex > top then top = child.ZIndex end
	end
	hit = Instance.new("TextButton")
	hit.Name = name
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.BorderSizePixel = 0
	hit.Size = UDim2.fromScale(1, 1)
	hit.Position = UDim2.new()
	hit.Selectable = true
	hit.ZIndex = z or (top + 1)
	hit.Parent = node
	return hit
end

local function isText(node)
	return node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")
end

-- Something with `.Text`: the node, or its first text descendant.
function Binder.text(node)
	if not node then return nil end
	if isText(node) then return node end
	for _, child in ipairs(node:GetDescendants()) do
		if isText(child) then return child end
	end
	return nil
end

-- Something with `.Image`: the node, its first image descendant, or a new
-- full-size ImageLabel when the slot arrived as a bare Frame.
function Binder.image(node)
	if not node then return nil end
	if node:IsA("ImageLabel") or node:IsA("ImageButton") then return node end
	for _, child in ipairs(node:GetDescendants()) do
		if child:IsA("ImageLabel") or child:IsA("ImageButton") then return child end
	end
	local made = Instance.new("ImageLabel")
	made.Name = "L4Image"
	made.BackgroundTransparency = 1
	made.BorderSizePixel = 0
	made.Size = UDim2.fromScale(1, 1)
	made.ScaleType = Enum.ScaleType.Fit
	made.Parent = node
	return made
end

-- The sibling drawn under `face` as its hard shadow: `<Face>Shadow`, else any
-- sibling tagged `_shadow` or ending in "Shadow" (GetPass shares BuyShadow).
local function shadowOf(face)
	local parent = face.Parent
	if not parent then return nil end
	local faceBase = Binder.base(face.Name)
	local fallback
	for _, sibling in ipairs(parent:GetChildren()) do
		if sibling ~= face and sibling:IsA("GuiObject") then
			local base, tags = Binder.base(sibling.Name)
			if base == faceBase .. "Shadow" then return sibling end
			if not fallback and (tags.shadow or base:sub(-6) == "Shadow") then fallback = sibling end
		end
	end
	return fallback
end

-- A price button as one table: Face (what is painted), Hit (what takes
-- input), Price/PriceLabel (text), Glyph (TokenGlyph) and Shadow. Nil when the
-- face is absent; Price is nil when no text could be found.
function Binder.control(scope, base, textBase)
	local face = Binder.find(scope, base)
	if not face then return nil end
	local price = Binder.text(Binder.find(face, textBase or "Price"))
	if not price and isText(face) then price = face end
	return {
		Face = face,
		Hit = Binder.button(face),
		Price = price,
		PriceLabel = Binder.text(Binder.find(face, "PriceLabel")),
		Glyph = Binder.find(face, "TokenGlyph"),
		Shadow = shadowOf(face),
	}
end

-- -- visuals --------------------------------------------------------------

-- Hover fills (DESIGN-SYSTEM color/*-hover), keyed by the face colour they
-- replace. Keys are hex strings: Color3 table keys compare by identity.
local HOVER, UNHOVER = {}, {}
for _, pair in ipairs({
	{P.Amber, Color3.fromRGB(245, 181, 60)},     -- amber-hover #F5B53C
	{P.IconTeal, Color3.fromRGB(92, 198, 193)},  -- token-hover #5CC6C1
	{P.Cream, Color3.fromRGB(255, 248, 234)},    -- cream-hover #FFF8EA
	{P.Coral, Color3.fromRGB(247, 136, 122)},    -- coral-hover #F7887A
}) do
	HOVER[pair[1]:ToHex()] = pair[2]
	UNHOVER[pair[2]:ToHex()] = pair[1]
end
local function tint(face, map)
	local swap = map[face.BackgroundColor3:ToHex()]
	if swap then face.BackgroundColor3 = swap end
end

-- Press and hover feedback, after the design's Pressed/Hover variants and the
-- spirit of FramewispButtonFX (which dims a face on hover and press): hover
-- swaps the face to its state's hover fill; press drops the face by the
-- shadow's authored offset and hides the shadow ("Pressed: hide the shadow and
-- move the face down"). Release (InputEnded or MouseLeave) restores both. The
-- rest position is stored once as an attribute, so re-wiring after a re-bind
-- can never compound the drop. A disabled hit (Active false) shows neither.
function Binder.press(hit, face, shadow)
	if hit:GetAttribute("BinderPressWired") then return end
	hit:SetAttribute("BinderPressWired", true)
	face = face or hit
	local rest = face:GetAttribute("BinderRestPosition")
	if typeof(rest) ~= "UDim2" then
		rest = face.Position
		face:SetAttribute("BinderRestPosition", rest)
	end
	local drop = UDim2.new()
	if shadow then
		drop = UDim2.new(0, 0, shadow.Position.Y.Scale - rest.Y.Scale,
			shadow.Position.Y.Offset - rest.Y.Offset)
	end
	local function release()
		face.Position = rest
		if shadow then shadow.Visible = shadow:GetAttribute("BinderShadowOn") ~= false end
	end
	hit.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if not hit.Active or (kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch) then
			return
		end
		face.Position = rest + drop
		if shadow then shadow.Visible = false end
	end)
	hit.InputEnded:Connect(release)
	hit.MouseEnter:Connect(function() if hit.Active then tint(face, HOVER) end end)
	hit.MouseLeave:Connect(function()
		release()
		tint(face, UNHOVER)
	end)
end

-- Paint a control for a state: robux | token | owned | off | equip. Writes
-- only the face fill, its UIStroke colour, the Price/PriceLabel colour and the
-- shadow's Visible -- never geometry, never text.
function Binder.style(control, state)
	local p = STATES[state] or STATES.off
	control.Face.BackgroundColor3 = p.Face
	local stroke = control.Face:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = p.Stroke end
	if control.Price then control.Price.TextColor3 = p.Text end
	if control.PriceLabel then control.PriceLabel.TextColor3 = p.Text end
	if control.Shadow then
		control.Shadow:SetAttribute("BinderShadowOn", p.Shadow)
		control.Shadow.Visible = p.Shadow
	end
end

-- -- templates ------------------------------------------------------------

-- Destroy every script and every `_ignore` node. A RunContext=Client script
-- runs even inside ReplicatedStorage, so an import is never cloned with one
-- (contract risk 1). Returns how many nodes went.
function Binder.strip(root)
	local removed = 0
	for _, node in ipairs(root:GetDescendants()) do
		if node.Parent ~= nil then
			local _, tags = Binder.base(node.Name)
			if node:IsA("LuaSourceContainer") or tags.ignore then
				node:Destroy()
				removed += 1
			end
		end
	end
	return removed
end

-- Show `node` and every ancestor below `stop`. Framewisp imports a tab group's
-- inactive panels hidden: the 2026-10-07 bundle hid the shop's Skins and Donate
-- lists and five of the dev menu's six, although their pages are visible. A
-- bound control must be drawn whenever the page that holds it is.
function Binder.reveal(node, stop)
	while node and node ~= stop do
		if node:IsA("GuiObject") then node.Visible = true end
		node = node.Parent
	end
end

-- Grafted art must never take input away from the live control under it.
local function inert(root)
	local nodes = root:GetDescendants()
	table.insert(nodes, root)
	for _, node in ipairs(nodes) do
		if node:IsA("GuiButton") then
			node.Active = false
			node.Selectable = false
			node.AutoButtonColor = false
			pcall(function() node.Interactable = false end)
		end
	end
end

-- -- text scale -----------------------------------------------------------
-- PORTED FROM FRAMEWISP'S FramewispTextScaler, the runtime LocalScript every
-- Framewisp import ships with (removed from ours; source kept at
-- _local/shop-ui-figma/studio-turn/framewisp-scripts/FramewispTextScaler.20778.lua).
-- Framewisp sizes in Scale but writes text as a FIXED TextSize, and the
-- TextSize an import holds is whatever its plugin last solved for the EDIT
-- viewport (the 2026-10-06 dumps were taken at k = 361/1080: a 7 px design
-- stroke reads 2.34), so it is never a baseline. The design sizes travel in
-- Framewisp's own attributes, which Clone keeps:
--   FigmaFontSize          Figma font size, artboard px (every text node)
--   FigmaTextW, FW_M100    design text width, and the Roblox width of that text
--                          at TextSize 100 ("width-exact"; authored copy only)
--   FigmaStrokeW           a pixel UIStroke's design width
-- TextSize = 100 * FigmaTextW * k / FW_M100 while the text is the authored one,
-- else FigmaFontSize * k * em(face), em = Framewisp's TextSize per design em for
-- the face, BB_TextFactor for any other face. k = the root's on-screen size over
-- its design size (the smaller axis). A UITextSizeConstraint clamps the result.
-- Kept: re-run on every resize; a grid's pixel cells become its cells' Scale.
-- Dropped: runtime GetTextBoundsAsync measuring (unstamped text falls back to
-- em) and the >100 px UIScale spill.
local EM = { -- FramewispTextScaler's EM table, the faces the L4 imports use
	["rbxasset://fonts/families/Montserrat.json"] = 1.219,
	["rbxasset://fonts/families/RobotoCondensed.json"] = 1.1719,
	["rbxasset://fonts/families/RobotoMono.json"] = 1.3188,
	["rbxasset://fonts/families/LegacyArial.json"] = 1.1172,
	["rbxasset://fonts/families/BuilderSans.json"] = 1.26,
}

-- Design size (artboard px) of a template node: the artboard's BB_DesignW/H
-- times the Size.Scale chain down to the node. The walk stops at the artboard
-- (the node carrying BB_DesignW), so it also holds for a clone that has been
-- reparented into live UI (the shop window is measured after its artboard
-- moved under Root). A ScrollingFrame child is sized against the canvas.
-- ponytail: Scale only (the imports carry no Size offsets).
-- Roblox sizes a canvas from the ScrollingFrame's PARENT (the dev dump: a 0.872
-- list with canvas 1.46 holds 393 px of a 269 px page), and never below the
-- frame: the canvas spans max(1, canvas / frame) of the frame's own Scale.
local function canvasGain(scroll, axis)
	local frame = scroll.Size[axis].Scale
	return frame > 0 and math.max(1, scroll.CanvasSize[axis].Scale / frame) or 1
end
function Binder.designSize(node)
	local w, h = 1, 1
	while node:GetAttribute("BB_DesignW") == nil and node.Parent and node.Parent:IsA("GuiObject") do
		w *= node.Size.X.Scale
		h *= node.Size.Y.Scale
		node = node.Parent
		if node:IsA("ScrollingFrame") then
			w *= canvasGain(node, "X")
			h *= canvasGain(node, "Y")
		end
	end
	return Vector2.new(w * (node:GetAttribute("BB_DesignW") or 1920), h * (node:GetAttribute("BB_DesignH") or 1080))
end

-- The layers the design draws on several lines. STYLE-GUIDE: "a text layer is
-- multi-line only if its name ends in _txt"; Framewisp strips that tag and can
-- drop TextWrapped with it, so these base names (or a surviving _txt) restore it.
local MULTILINE = {Name = true, Benefit = true, Detail = true, Title = true}

-- Design height of `node` in root's design space (`rootH` tall): the
-- Size.Y.Scale chain up to root. A ScrollingFrame child is sized against the
-- canvas. ponytail: Scale only, like designSize.
local function heightIn(root, node, rootH)
	local h = rootH
	while node ~= root and node:IsA("GuiObject") do
		h *= node.Size.Y.Scale
		local parent = node.Parent
		if parent:IsA("ScrollingFrame") then h *= canvasGain(parent, "Y") end
		node = parent
	end
	return h
end

-- -- text fit -------------------------------------------------------------
-- Framewisp draws every text box round the Figma SAMPLE (a "hug" box: the dev
-- menu's State_noclip is 22 px wide at the 443 px Studio viewport, for OFF) and
-- scaleText solves the size for that sample. A longer runtime string
-- ("FLYING \u{B7} 90 STUDS/S") is then drawn past its box, and a centred one
-- spills out on the LEFT, where a scrolling list or a card clips it. Roblox's
-- fonts also draw a few percent wider than Figma's, so even a sample overruns
-- (HAZMAT SUIT's subtitle reached into its accent bar). fitLine keeps a one-line
-- label inside its box, cheapest change first:
--   1. widen the box into the room its parent leaves: in a horizontal list the
--      free width, otherwise up to the nearest sibling on the same line, never
--      nearer the parent's edge than 4% (or the import's own margin, if less).
--      A centred label grows away from the nearer side, so its text stays put;
--   2. shrink TextSize, to 60% of the solved size (a text with a digit in it
--      further) and never under 11 px;
--   3. TextTruncate AtEnd.
-- A button face is never moved or widened: it only shrinks. Every pass starts
-- from the imported box and the solved size, so a shorter text or a bigger
-- window gets the design back. TextBounds is engine-measured.
local FIT = {Margin = 0.04, Gap = 0.2, Floor = 0.6, MinPx = 11}

-- A GuiObject's edges in its parent (`room` = the parent's AbsoluteSize), in px.
local function edges(node, room)
	local size, pos, anchor = node.Size, node.Position, node.AnchorPoint
	local w, h = size.X.Scale * room.X + size.X.Offset, size.Y.Scale * room.Y + size.Y.Offset
	local x = pos.X.Scale * room.X + pos.X.Offset - anchor.X * w
	local y = pos.Y.Scale * room.Y + pos.Y.Offset - anchor.Y * h
	return x, x + w, y, y + h
end

local function fitLine(node)
	local import = node:GetAttribute("FW_FitSize")
	if typeof(import) == "UDim2" then
		node.Size, node.Position = import, node:GetAttribute("FW_FitPosition")
	end
	node.TextTruncate = Enum.TextTruncate.None
	local parent, scale = node.Parent, node:FindFirstChildOfClass("UIScale")
	-- Wrapped text has scaleText's backstop, a row title Binder.flowRow, and a
	-- label under a UIScale other than 1 the controller that set it.
	if node.TextWrapped or node:IsA("TextBox") or node:GetAttribute("BinderFlowTitle")
		or (scale and scale.Scale ~= 1) or not (parent and parent:IsA("GuiObject")) then
		return
	end
	local room = parent.AbsoluteSize
	local left, right, top, bottom = edges(node, room)
	local need = node.TextBounds.X
	if room.X <= 0 or need <= right - left + 1 then return end
	local px = node.TextSize
	local list = parent:FindFirstChildOfClass("UIListLayout")
	local face = node:IsA("GuiButton") -- keeps its box (Binder.press moves it)
	local lo, hi = left, right
	if face then
		list = nil
	elseif list then
		-- The layout places it; only the width is ours.
		local free = room.X
		if list.FillDirection == Enum.FillDirection.Horizontal then
			local shown = 0
			for _, sibling in ipairs(parent:GetChildren()) do
				if sibling:IsA("GuiObject") and sibling.Visible then
					shown += 1
					if sibling ~= node then free -= sibling.Size.X.Scale * room.X + sibling.Size.X.Offset end
				end
			end
			free -= (shown - 1) * (list.Padding.Scale * room.X + list.Padding.Offset)
		end
		hi = left + math.max(right - left, free)
	else
		local margin = math.max(0, math.min(left, room.X - right, FIT.Margin * room.X))
		lo, hi = margin, room.X - margin
		local gap = FIT.Gap * px
		for _, sibling in ipairs(parent:GetChildren()) do
			if sibling ~= node and sibling:IsA("GuiObject") and sibling.Visible then
				local sl, sr, st, sb = edges(sibling, room)
				if st < bottom and sb > top then -- on the same line
					if sr <= left + 0.5 then lo = math.max(lo, math.min(left, sr + gap))
					elseif sl >= right - 0.5 then hi = math.min(hi, math.max(right, sl - gap)) end
				end
			end
		end
		lo, hi = math.min(lo, left), math.max(hi, right)
	end
	local w = math.min(need, hi - lo)
	if not face then
		if typeof(import) ~= "UDim2" then
			node:SetAttribute("FW_FitSize", node.Size)
			node:SetAttribute("FW_FitPosition", node.Position)
		end
		node.Size = UDim2.new(w / room.X, 0, node.Size.Y.Scale, node.Size.Y.Offset)
	end
	if not (list or face) then
		local x, align = left, node.TextXAlignment
		if align == Enum.TextXAlignment.Right then
			x = right - w
		elseif align ~= Enum.TextXAlignment.Left then
			local near, far = left - lo, hi - right
			x = near < far - 1 and left or far < near - 1 and right - w or (left + right - w) / 2
		end
		x = math.max(lo, math.min(x, hi - w)) -- not math.clamp: hi - w can sit a rounding error under lo
		node.Position = UDim2.new((x + node.AnchorPoint.X * w) / room.X, 0, node.Position.Y.Scale, node.Position.Y.Offset)
	end
	if need > w then
		local limit = node:FindFirstChildOfClass("UITextSizeConstraint")
		-- A text holding a number is never cut at the 60% floor (a 1234 balance read
		-- "12..."): it may shrink to the pixel floor first.
		local least = node.Text:find("%d") and FIT.MinPx or math.ceil(px * FIT.Floor)
		local floor = math.min(px, math.max(FIT.MinPx, least, limit and limit.MinTextSize or 0))
		node.TextSize = math.max(floor, math.floor(px * w / need))
		for _ = 1, 3 do
			if node.TextBounds.X <= w or node.TextSize <= floor then break end
			node.TextSize -= 1
		end
		if node.TextBounds.X > w then node.TextTruncate = Enum.TextTruncate.AtEnd end
	end
end

-- Keep every Framewisp-stamped text and pixel stroke under `root` at design
-- size for `root`'s on-screen size. `design` is root's design size
-- (Binder.designSize of its template node). Returns the resize connection.
--
-- WRAPPED TEXT. Roblox's TextSize is the LINE HEIGHT (Montserrat: 1.219 em, the
-- EM table), Figma's lines are tighter, and a wrapped line that does not fit
-- its box is not drawn at all: a design-size "Zyntra Supporter" in its two-line
-- box showed "Zyntra". So a wrapped label is never solved width-exact (that is
-- the size of the text on ONE line) but by FigmaFontSize x k x em, capped so
-- the number of lines its design box holds fits (5% slack for the shelf's
-- scrollbar). Never larger than the design size, so it never wraps more often
-- than Figma did.
--
-- ONE-LINE TEXT goes through fitLine after every solve. A label is re-solved on
-- every resize, and on its own whenever its Text changes (deferred, so a render
-- that also moves its neighbours lands first); a text added later (the dev
-- menu's player chips, rebuilt on every join) is solved when it arrives.
function Binder.scaleText(root, design, factor)
	factor = tonumber(factor) or 1.16
	local function em(node)
		local face = node.FontFace
		return face and EM[face.Family] or factor
	end
	local wrapped = {} -- node -> {Height = design px, Lines = n}
	local k = 0
	local function solve(node)
		local fs = node:GetAttribute("FigmaFontSize")
		if not (k > 0 and type(fs) == "number" and isText(node)) then return end
		local width, m100 = node:GetAttribute("FigmaTextW"), node:GetAttribute("FW_M100")
		local box = wrapped[node]
		local px
		if box then
			px = math.min(fs * k * em(node), box.Height * k * 0.95 / box.Lines)
		elseif node.Text == node:GetAttribute("FW_Text0") and type(width) == "number" and type(m100) == "number" and m100 > 0 then
			px = 100 * width * k / m100
		else
			px = fs * k * em(node)
		end
		local limit = node:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then px = math.clamp(px, limit.MinTextSize, limit.MaxTextSize) end
		node.TextScaled = false
		node.TextSize = math.clamp(math.floor(px + 0.5), 1, 100) -- ponytail: no >100 spill (4K+ only)
		if not box then fitLine(node) end
	end
	-- Backstop: Roblox does not draw a wrapped line that does not fit, and only
	-- the engine can measure text. Shrink a wrapped label it still reports as not
	-- fitting, 1 px a frame (at most 6 steps).
	local function settle(node)
		local steps = 0
		while node.Parent and node.TextFits == false and node.TextSize > 8 and steps < 6 do
			node.TextSize -= 1
			steps += 1
			task.wait()
		end
	end
	-- ponytail: strong keys; a destroyed label stays listed (a few per join).
	local tracked, queued = {}, {}
	local function refit(node)
		if queued[node] then return end
		queued[node] = true
		task.defer(function()
			queued[node] = nil
			if not node.Parent then return end
			solve(node)
			-- The solve put a wrapped label back at design size: a rewritten one
			-- (the Donate totals) needs the backstop again.
			if wrapped[node] then settle(node) end
		end)
	end
	local function track(node)
		if tracked[node] then return end
		tracked[node] = true
		if isText(node) then
			-- The authored copy, stamped before anything rewrites it.
			if node:GetAttribute("FW_Text0") == nil then node:SetAttribute("FW_Text0", node.Text) end
			local fs = node:GetAttribute("FigmaFontSize")
			if type(fs) == "number" and fs > 0 then
				local height = heightIn(root, node, design.Y)
				local lines = math.floor(height / (fs * em(node)) + 0.5)
				local base, tags = Binder.base(node.Name)
				if lines >= 2 and (MULTILINE[base] or tags.txt) then node.TextWrapped = true end
				if node.TextWrapped then wrapped[node] = {Height = height, Lines = math.max(1, lines)} end
				node:GetPropertyChangedSignal("Text"):Connect(function() refit(node) end)
			end
		elseif node:IsA("UIGridLayout") and node.CellSize.X.Scale == 0 and node.CellSize.X.Offset > 0
			and node.CellSize.Y.Offset > 0 then
			-- Framewisp sizes grid cells in editor-viewport pixels (the Skins grid:
			-- 223x108 at k = 0.41) and re-fits them at runtime; that is not ported.
			-- Its cells carry their design Scale, so the grid takes that instead and
			-- holds its layout at every size with no resize hook.
			local cell = nil
			for _, sibling in ipairs(node.Parent:GetChildren()) do
				if sibling:IsA("GuiObject") and sibling.Size.X.Scale > 0 and sibling.Size.Y.Scale > 0 then
					cell = sibling
					break
				end
			end
			if cell then
				local sx, sy = cell.Size.X.Scale / node.CellSize.X.Offset, cell.Size.Y.Scale / node.CellSize.Y.Offset
				node.CellPadding = UDim2.fromScale(node.CellPadding.X.Offset * sx, node.CellPadding.Y.Offset * sy)
				node.CellSize = UDim2.fromScale(cell.Size.X.Scale, cell.Size.Y.Scale)
			end
		end
	end
	for _, node in ipairs(root:GetDescendants()) do track(node) end
	root.DescendantAdded:Connect(function(node)
		track(node)
		if isText(node) then refit(node) end
	end)
	local function apply()
		local size = root.AbsoluteSize
		local scale = math.min(size.X / design.X, size.Y / design.Y)
		if not (scale > 0 and scale < math.huge) then return end
		k = scale
		for _, node in ipairs(root:GetDescendants()) do
			if isText(node) then
				solve(node)
			elseif node:IsA("UIStroke") and type(node:GetAttribute("FigmaStrokeW")) == "number"
				and not node:GetAttribute("FW_StrokeScaled") then
				-- A ScaledSize stroke is a fraction of its host, never pixels.
				local ok, fraction = pcall(function() return node.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize end)
				if not (ok and fraction) then node.Thickness = math.max(0.35, node:GetAttribute("FigmaStrokeW") * k) end
			end
		end
		-- The wrapped labels' backstop, one frame later.
		task.defer(function()
			for node in pairs(wrapped) do settle(node) end
		end)
	end
	apply()
	return root:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
end

-- -- title rows -----------------------------------------------------------
-- A title with chips after it on one line (the dev menu's TitleRow: RowTitle,
-- then ScopeChip and/or KeyChip). Framewisp places each chip at its Figma x,
-- after the title as FIGMA measured it, and Roblox's Montserrat draws wider:
-- PULL TWO PUMPS ran into its IN ROUND chip. flowRow draws the title
-- left-aligned from its imported left edge and sets every chip after the title
-- Roblox actually drew, at the design gap (scaled with the row). The row may
-- use its parent's width; a chip that would leave it is hidden, and so is every
-- chip after it (the trailing chips go first). flowRow owns the chips'
-- Visible: a caller hides one by setting its BinderFlowOff attribute and calling
-- flowRow again. It re-runs by itself when the title's TextBounds or the row's
-- size changes. Call it before Binder.scaleText: it marks the title, which
-- fitLine then leaves alone. Returns false (and lays nothing out) for a node
-- that is not a text followed by something.
function Binder.flowRow(row)
	local items = {}
	for _, child in ipairs(row:GetChildren()) do
		if child:IsA("GuiObject") then
			if child:GetAttribute("FW_FlowX") == nil then
				-- The import's left edge (row Scale) and visibility, stamped once.
				child:SetAttribute("FW_FlowX", child.Position.X.Scale - child.AnchorPoint.X * child.Size.X.Scale)
				child:SetAttribute("FW_FlowShown", child.Visible)
			end
			table.insert(items, child)
		end
	end
	table.sort(items, function(a, b) return a:GetAttribute("FW_FlowX") < b:GetAttribute("FW_FlowX") end)
	local title, parent = items[1], row.Parent
	if not (title and #items > 1 and isText(title) and parent and parent:IsA("GuiObject")) then return false end
	if not title:GetAttribute("BinderFlowTitle") then
		title:SetAttribute("BinderFlowTitle", true)
		local function again() task.defer(Binder.flowRow, row) end
		title:GetPropertyChangedSignal("TextBounds"):Connect(again)
		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(again)
	end
	title.TextXAlignment = Enum.TextXAlignment.Left
	local width = row.AbsoluteSize.X
	if width <= 0 then return true end
	-- Everything below is in the row's Scale.
	local limit = (1 - (row.Position.X.Scale - row.AnchorPoint.X * row.Size.X.Scale)) * parent.AbsoluteSize.X / width
	local edge = title:GetAttribute("FW_FlowX") + title.Size.X.Scale -- the import's right edge so far
	local x = title:GetAttribute("FW_FlowX") + title.TextBounds.X / width
	local full = false
	for index = 2, #items do
		local chip = items[index]
		local start, w = chip:GetAttribute("FW_FlowX"), chip.Size.X.Scale
		local at = x + math.max(0, start - edge)
		edge = start + w
		local shown = not full and chip:GetAttribute("FW_FlowShown") == true and chip:GetAttribute("BinderFlowOff") ~= true
		if shown and at + w > limit + 1e-6 then shown, full = false, true end
		chip.Visible = shown
		if shown then
			chip.Position = UDim2.new(at + chip.AnchorPoint.X * w, 0, chip.Position.Y.Scale, chip.Position.Y.Offset)
			x = at + w
		end
	end
	return true
end

-- -- skins (rail, wheel, daily rewards) ------------------------------------
-- Explicit per-surface map; nothing is inferred. Entries:
--   {from = tplPath, to = livePath, props = {...}}   copy listed properties
--       ("Stroke" / "Corner" / "Gradient" copy the template's UIStroke / UICorner / UIGradient)
--   {set = livePath, props = {Prop = value}}          write values
--   {hide = {livePath, ...}}                          Visible / Enabled = false
--   {graft = tplPath, into = livePath?, name?, children?, size?, pos?, anchor?, z?, aspect?}
--       clone as L4Skin_<name or base>; `children` clones the template node's
--       children into a plain Frame (a template _button never nests a button);
--       `aspect` locks the graft to the template node's design aspect. Every
--       graft's template text is kept at design size by Binder.scaleText.
-- Every path is resolved FIRST. If anything is missing nothing is written and
-- the missing paths are returned: the caller warns and skips the surface.
-- Re-running a map is idempotent (grafts are found by name and reused).

-- "Stroke" / "Corner" / "Gradient": the template's modifier of that class and
-- the fields copied onto one the live node already has.
local MODIFIERS = {
	Stroke = {"UIStroke", "Color", "Thickness", "Transparency"},
	Corner = {"UICorner", "CornerRadius"},
	Gradient = {"UIGradient", "Color", "Rotation", "Offset", "Transparency", "Enabled"},
}

local function copyProp(source, target, prop)
	local modifier = MODIFIERS[prop]
	if modifier then
		local from = source:FindFirstChildOfClass(modifier[1])
		if not from then return end
		local to = target:FindFirstChildOfClass(modifier[1])
		if not to then
			from:Clone().Parent = target
		else
			for index = 2, #modifier do to[modifier[index]] = from[modifier[index]] end
		end
	elseif prop == "Image" then
		target.Image = Binder.image(source).Image
	elseif source[prop] ~= nil then
		target[prop] = source[prop]
	end
end

function Binder.skin(liveRoot, templateRoot, map)
	local missing, plan = {}, {}
	local function live(path)
		local node = Binder.at(liveRoot, path)
		if not node then table.insert(missing, tostring(path)) end
		return node
	end
	local function template(path)
		local node = Binder.at(templateRoot, path)
		if not node then table.insert(missing, "template:" .. tostring(path)) end
		return node
	end
	for _, entry in ipairs(map) do
		if entry.from then
			table.insert(plan, {entry, template(entry.from), live(entry.to)})
		elseif entry.set then
			table.insert(plan, {entry, nil, live(entry.set)})
		elseif entry.hide then
			for _, path in ipairs(entry.hide) do table.insert(plan, {entry, nil, live(path)}) end
		elseif entry.graft then
			table.insert(plan, {entry, template(entry.graft), live(entry.into)})
		end
	end
	local grafts = {}
	if #missing > 0 then return missing, grafts end
	for _, step in ipairs(plan) do
		local entry, source, target = step[1], step[2], step[3]
		if entry.from then
			for _, prop in ipairs(entry.props) do copyProp(source, target, prop) end
		elseif entry.set then
			for prop, value in pairs(entry.props) do target[prop] = value end
		elseif entry.hide then
			if target:IsA("GuiObject") then target.Visible = false else target.Enabled = false end
		else
			local key = entry.name or Binder.base(source.Name)
			local name = "L4Skin_" .. key
			local clone = target:FindFirstChild(name)
			if not clone then
				if entry.children then
					clone = Instance.new("Frame")
					clone.BackgroundTransparency = 1
					clone.BorderSizePixel = 0
					for _, child in ipairs(source:GetChildren()) do child:Clone().Parent = clone end
				else
					clone = source:Clone()
				end
				Binder.strip(clone)
				inert(clone)
				clone.Name = name
				if entry.size then clone.Size = entry.size end
				if entry.pos then clone.Position = entry.pos end
				if entry.anchor then clone.AnchorPoint = entry.anchor end
				if entry.z then clone.ZIndex = entry.z end
				local design = Binder.designSize(source)
				if entry.aspect then
					local ratio = Instance.new("UIAspectRatioConstraint")
					ratio.AspectRatio = design.X / design.Y
					ratio.Parent = clone
				end
				clone.Parent = target
				Binder.scaleText(clone, design, templateRoot:GetAttribute("BB_TextFactor"))
			end
			grafts[key] = clone
		end
	end
	return missing, grafts
end

return Binder

end end,
UIStyle=function() return function()
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

-- The in-round HUD (owner, 2026-10-08; artifacts/hud-final-20261008/BUILD-PLAN.md
-- 1.2 and its Framewisp adaptation). Its fixed colours are drawn in the Framewisp
-- templates and come from ShopBinder.Palette; only what the code paints lives
-- here. Accent/Dim are the owner's level colours (OWNER-PICKS.md, "Farve for
-- level 1: gul, 2: blaa, 3: roed, 4: neon pink, 5: graa/hvid, 6: violet") and
-- must equal RoundUI's LOADING_PALETTES[n].Title / .Status: they are copies,
-- held together by test_ui_style.py, not a dependency of RoundUI. Soft is the
-- soft-Ink UIGradient transparency ramp RoundHud writes on every `Soft` node.
UIStyle.Hud = {
	Accent = {
		[1] = Color3.fromRGB(255, 230, 0),   -- #FFE600 yellow
		[2] = Color3.fromRGB(77, 163, 255),  -- #4DA3FF blue
		[3] = Color3.fromRGB(255, 0, 0),     -- #FF0000 red
		[4] = Color3.fromRGB(255, 70, 200),  -- #FF46C8 neon pink
		[5] = Color3.fromRGB(212, 220, 232), -- #D4DCE8 silver white
		[6] = Color3.fromRGB(156, 134, 255), -- #9C86FF violet
	},
	Dim = {
		[1] = Color3.fromRGB(158, 143, 0),
		[2] = Color3.fromRGB(48, 101, 158),
		[3] = Color3.fromRGB(184, 0, 0),
		[4] = Color3.fromRGB(158, 43, 124),
		[5] = Color3.fromRGB(131, 136, 144),
		[6] = Color3.fromRGB(97, 83, 158),
	},
	Soft = {From = 0.35, To = 1},
	-- EXIT_COMPASS_20261010 (owner: "Make the compass marker to the exit more distinct."): the one
	-- colour the HUD keeps for the way out, so the exit compass stops reading as one more piece of
	-- the level's accent. It is the green of the exit door's own header (PuzzleManager makeExit,
	-- htext 90,255,135; Level 2's door header carries the same). Nothing else on the HUD is green:
	-- the level accents are above, Coral is danger, RailTeal the team, Amber the feed. Not per
	-- level on purpose: Level 3's and Level 4's GET OUT wear it too.
	Exit = Color3.fromRGB(90, 255, 135),
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

end end,
ZyntraDetectorVisual=function() return function()
-- Shared local presentation: the shop demo and the server-authorized scan use
-- the same model, face texture, colours and readout. No sensing or entitlement.
local Visual = {}
Visual.Texture = "rbxassetid://94042368093581"
Visual.Colors = {
 LOW = Color3.fromRGB(72, 174, 255),
 MEDIUM = Color3.fromRGB(255, 204, 65),
 HIGH = Color3.fromRGB(255, 69, 72),
}
Visual.Labels = {LOW="SAFE DISTANCE", MEDIUM="ENTITY NEARBY", HIGH="ENTITY VERY CLOSE"}
Visual.Explanations = {
 LOW="Blue: safe distance. The reading stays live for 30 seconds, so watch it as you move.",
 MEDIUM="Yellow: an entity is nearby. Slow down and listen before moving on.",
 HIGH="Red: warning! An entity is very close. React to its sound and behaviour.",
}
-- DETECTOR_BIG_SCREEN_20261008 (owner: "a much larger screen when used and demoed"). The generated face had a
-- screen opening of 61% x 29% of the housing, so the readout was about 110 x 80 pixels at its best. The device
-- now has a face of its own with a screen Width x Height of the housing, centred CentreY studs above the
-- housing's middle; Preview projects the readout onto exactly that glass. `ScreenBottom` is where the screen's
-- lower edge falls in a Preview frame (0 top, 1 bottom), for callers that place the device by its screen.
Visual.Screen = {Width=.86, Height=.64, CentreY=.2}
local HOUSING = Vector3.new(1.3,1.95,.36)
local GLASS_Z = HOUSING.Z/2+.052                 -- how far the glass stands in front of the housing's middle
local CAMERA = {FieldOfView=35, Height=.25, Distance=5}
local function viewHeight() return 2*math.tan(math.rad(CAMERA.FieldOfView/2))*(CAMERA.Distance-GLASS_Z) end
Visual.ScreenBottom = .5+(CAMERA.Height-(Visual.Screen.CentreY-HOUSING.Y*Visual.Screen.Height/2))/viewHeight()
local WHITE = Color3.fromRGB(228, 239, 242)
local DARK = Color3.fromRGB(9, 14, 19)
local function create(class, parent, properties)
 local object = Instance.new(class)
 for key,value in pairs(properties or {}) do object[key]=value end
 object.Parent=parent
 return object
end
local function label(parent, name, text, pos, size, fontSize)
 return create("TextLabel",parent,{Name=name,Text=text,Position=pos,Size=size,
  BackgroundTransparency=1,BorderSizePixel=0,Font=Enum.Font.Code,TextColor3=WHITE,
  TextSize=fontSize or 16,TextWrapped=true})
end
function Visual.Build(parent)
 local model=create("Model",nil,{Name="ZyntraLocalDetector"})
 local metal=Color3.fromRGB(40,43,43)
 local rubber=Color3.fromRGB(17,20,22)
 local brass=Color3.fromRGB(143,119,65)
 local function part(name,size,cf,color,material,shape)
  return create("Part",model,{Name=name,Size=size,CFrame=cf,Color=color,
   Material=material or Enum.Material.Metal,Shape=shape or Enum.PartType.Block,
   Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,CastShadow=false})
 end
 local body=part("ArmouredHousing",HOUSING,CFrame.new(),metal)
 model.PrimaryPart=body
 -- The face: a plate over the whole front, the screen in its bezel, and a control deck under it. (The generated
 -- face picture, Visual.Texture, had the small screen painted into it and is no longer applied.)
 local screen=Visual.Screen
 local sw,sh,sy=HOUSING.X*screen.Width,HOUSING.Y*screen.Height,screen.CentreY
 local front=-HOUSING.Z/2
 part("FrontPlate",Vector3.new(HOUSING.X-.04,HOUSING.Y-.04,.03),CFrame.new(0,0,front-.012),Color3.fromRGB(31,34,35))
 part("ScreenBezel",Vector3.new(sw+.1,sh+.1,.04),CFrame.new(0,sy,front-.03),rubber,Enum.Material.SmoothPlastic)
 local glass=part("ScreenGlass",Vector3.new(sw,sh,.012),CFrame.new(0,sy,-GLASS_Z+.006),Color3.fromRGB(5,9,12),Enum.Material.SmoothPlastic)
 glass.Reflectance=.08
 local deck=sy-sh/2-.05                            -- top of the strip under the bezel
 local low=-HOUSING.Y/2+.06
 local flat=CFrame.Angles(0,math.pi/2,0)           -- a cylinder lying with its round face to the front
 for i=-1,1 do
  part("DeckButton",Vector3.new(.05,.2,.2),CFrame.new(i*.34,deck-.13,front-.04)*flat,i==0 and brass or rubber,
   i==0 and Enum.Material.Metal or Enum.Material.SmoothPlastic,Enum.PartType.Cylinder)
 end
 for i=1,4 do
  part("SpeakerSlat",Vector3.new(.5,.018,.02),CFrame.new(0,low+.02+(i-1)*.032,front-.03),rubber,Enum.Material.SmoothPlastic)
 end
 part("StatusLamp",Vector3.new(.07,.07,.07),CFrame.new(HOUSING.X/2-.13,HOUSING.Y/2-.07,front-.03),Visual.Colors.LOW,Enum.Material.Neon,Enum.PartType.Ball)
 -- Raised rubber ribs and rounded antenna supply an actual silhouette/depth.
 part("RearCasing",Vector3.new(1.18,1.83,.11),CFrame.new(0,0,.215),rubber,Enum.Material.SmoothPlastic)
 for _,side in ipairs({-1,1}) do
  for i=1,7 do
   part("GripRib",Vector3.new(.1,.055,.39),CFrame.new(side*.67,.6-(i-1)*.2,0),rubber,Enum.Material.SmoothPlastic)
  end
 end
 local cyl=CFrame.Angles(0,0,math.pi/2)
 part("AntennaCollar",Vector3.new(.14,.23,.23),CFrame.new(.43,1.035,0)*cyl,brass,nil,Enum.PartType.Cylinder)
 part("RubberAntenna",Vector3.new(.43,.17,.17),CFrame.new(.43,1.305,0)*cyl,rubber,Enum.Material.SmoothPlastic,Enum.PartType.Cylinder)
 part("AntennaCap",Vector3.new(.17,.17,.17),CFrame.new(.43,1.52,0),rubber,Enum.Material.SmoothPlastic,Enum.PartType.Ball)
 for i=1,4 do
  part("CollarKnurl",Vector3.new(.018,.244,.244),CFrame.new(.43,.98+i*.026,0)*cyl,brass,nil,Enum.PartType.Cylinder)
 end
 model.Parent=parent
 return model
end

-- SurfaceGuis do not render in ViewportFrames. Project the real screen opening
-- into the preview and put its live readout there, with the same camera maths.
-- This isolated render layer also prevents the shop/HUD painting over the item.
function Visual.Preview(parent)
 local frame=create("Frame",parent,{Name="DetectorPreview",BackgroundTransparency=1,BorderSizePixel=0})
 local viewport=create("ViewportFrame",frame,{Name="Equipment",Size=UDim2.fromScale(1,1),
  BackgroundTransparency=1,Ambient=Color3.fromRGB(190,198,210),LightColor=Color3.fromRGB(255,244,222),
  LightDirection=Vector3.new(-.4,-.6,-1),ZIndex=1})
 local world=create("WorldModel",viewport)
 local model=Visual.Build(world)
 model:PivotTo(CFrame.Angles(0,math.pi,0))
 local camera=create("Camera",viewport,{FieldOfView=CAMERA.FieldOfView,CFrame=CFrame.new(0,CAMERA.Height,CAMERA.Distance)})
 viewport.CurrentCamera=camera
 local display=create("Frame",frame,{Name="DetectorScreen",BackgroundColor3=DARK,BorderSizePixel=0,ZIndex=2})
 create("UICorner",display,{CornerRadius=UDim.new(.04,0)})
 local edge=create("UIStroke",display,{Color=Visual.Colors.LOW,Thickness=2,Transparency=.25})
 local header=label(display,"Mode","LIVE READING",UDim2.fromScale(.06,.03),UDim2.fromScale(.88,.11),12)
 local bars={}
 for i,key in ipairs({"LOW","MEDIUM","HIGH"}) do
  bars[key]=create("Frame",display,{Name=key.."Bar",Position=UDim2.fromScale(.08,.17+(i-1)*.105),
   Size=UDim2.fromScale(.84,.075),BackgroundColor3=Visual.Colors[key],BackgroundTransparency=.84,BorderSizePixel=0,ZIndex=3})
  create("UICorner",bars[key],{CornerRadius=UDim.new(.35,0)})
 end
 local value=label(display,"Meaning","READY",UDim2.fromScale(.04,.5),UDim2.fromScale(.92,.32),16)
 local footer=label(display,"Readout","30 SECOND READING",UDim2.fromScale(.04,.85),UDim2.fromScale(.92,.11),10)
 header.ZIndex=3 value.ZIndex=3 footer.ZIndex=3
 local lamp=model:FindFirstChild("StatusLamp")
 local current="LOW"
 local compactScreen=false
 local function layout()
  local h=frame.AbsoluteSize.Y
  local pixels=h/viewHeight()
  -- The glass of the device's own face (Visual.Screen), a hair inside its bezel.
  local w,sh=HOUSING.X*Visual.Screen.Width*pixels*.97,HOUSING.Y*Visual.Screen.Height*pixels*.97
  display.Position=UDim2.fromOffset(frame.AbsoluteSize.X/2-w/2,h/2-(Visual.Screen.CentreY-CAMERA.Height)*pixels-sh/2)
  display.Size=UDim2.fromOffset(w,sh)
  edge.Thickness=math.max(1,math.floor(sh*.012))
  header.TextSize=math.clamp(math.floor(sh*.068),8,20)
  footer.TextSize=math.clamp(math.floor(sh*.072),7,20)
  compactScreen=sh<62
  header.Visible=not compactScreen footer.Visible=not compactScreen
  value.Position=UDim2.fromScale(.035,compactScreen and .52 or .5)
  value.Size=UDim2.fromScale(.93,compactScreen and .46 or .32)
  value.TextSize=compactScreen and math.max(8,math.floor(sh*.19)) or math.clamp(math.floor(sh*.125),10,36)
  value.Text=compactScreen and ({LOW="SAFE\nDISTANCE",MEDIUM="ENTITY\nNEARBY",HIGH="VERY\nCLOSE"})[current] or Visual.Labels[current]
 end
 local changed=frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
 local api={Root=frame,Model=model,Display=display}
 function api:SetReading(key,demo,seconds)
  if not Visual.Colors[key] then return end
  current=key
  frame:SetAttribute("Reading",key)
  for band,bar in pairs(bars) do bar.BackgroundTransparency=band==key and 0 or .87 end
  header.Text=demo and "SIMULATED DEMO" or "LIVE READING"
  edge.Color=Visual.Colors[key]
  if lamp then lamp.Color=Visual.Colors[key] end
  value.Text=compactScreen and ({LOW="SAFE\nDISTANCE",MEDIUM="ENTITY\nNEARBY",HIGH="VERY\nCLOSE"})[key] or Visual.Labels[key]
  value.TextColor3=Visual.Colors[key]
  footer.Text=demo and "NO REAL ENTITY" or string.format("%ds REMAINING",math.ceil(math.max(0,seconds or 0)))
 end
 function api:Destroy() changed:Disconnect() frame:Destroy() end
 layout()
 return api
end

-- A contained, dismissible demo: no purchases, ownership changes or live scan.
function Visual.Demo(playerGui,onClose)
 local UIS=game:GetService("UserInputService")
 local RunService=game:GetService("RunService")
 local UIDevice=require(script.Parent:WaitForChild("UIDevice"))
 local gui=create("ScreenGui",playerGui,{Name="ZyntraDetectorDemo",ResetOnSpawn=false,
  DisplayOrder=1200,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets})
 local shade=create("Frame",gui,{Name="Backdrop",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(),BackgroundTransparency=.16,BorderSizePixel=0,Active=true})
 local panel=create("Frame",shade,{Name="DemoPanel",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),BackgroundColor3=Color3.fromRGB(15,22,26),BorderSizePixel=0})
 create("UICorner",panel,{CornerRadius=UDim.new(0,12)})
 create("UIStroke",panel,{Color=Color3.fromRGB(68,119,123),Thickness=1})
 local title=label(panel,"Title","ZYNTRA / ENTITY DETECTOR",UDim2.fromOffset(16,10),UDim2.new(1,-80,0,28),19)
 title.TextXAlignment=Enum.TextXAlignment.Left
 local close=create("TextButton",panel,{Name="CloseDemo",Text="X",Font=Enum.Font.GothamBold,TextSize=22,
  Size=UDim2.fromOffset(44,44),AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-8,0,4),
  BackgroundColor3=Color3.fromRGB(31,46,51),TextColor3=WHITE,BorderSizePixel=0})
 create("UICorner",close,{CornerRadius=UDim.new(0,8)})
 local preview=Visual.Preview(panel)
 local info=create("Frame",panel,{Name="Explanation",BackgroundTransparency=1})
 local eyebrow=label(info,"Eyebrow","FREE SIMULATED DEMO",UDim2.fromOffset(0,0),UDim2.new(1,0,0,23),13)
 eyebrow.TextColor3=Color3.fromRGB(89,220,207) eyebrow.TextXAlignment=Enum.TextXAlignment.Left
 local meaning=label(info,"Meaning","",UDim2.fromOffset(0,27),UDim2.new(1,0,0,40),24)
 meaning.TextXAlignment=Enum.TextXAlignment.Left
 local explanation=label(info,"Explanation","",UDim2.fromOffset(0,71),UDim2.new(1,0,0,54),15)
 explanation.TextXAlignment=Enum.TextXAlignment.Left
 local buttons={}
 for i,key in ipairs({"LOW","MEDIUM","HIGH"}) do
  local b=create("TextButton",info,{Name="Show"..key,Text=({"BLUE / SAFE","YELLOW / NEARBY","RED / VERY CLOSE"})[i],
   Font=Enum.Font.GothamMedium,TextSize=13,TextColor3=WHITE,BackgroundColor3=Color3.fromRGB(25,37,44),BorderSizePixel=0,
   Size=UDim2.new(1,0,0,44),Position=UDim2.fromOffset(0,134+(i-1)*49)})
  create("UICorner",b,{CornerRadius=UDim.new(0,6)})
  create("Frame",b,{Name="Colour",Position=UDim2.fromOffset(0,0),Size=UDim2.new(0,5,1,0),BackgroundColor3=Visual.Colors[key],BorderSizePixel=0})
  buttons[key]=b
 end
 local note=label(panel,"UseInstructions","IN A RUN: Z / D-pad left / SCAN  •  live for 30 seconds  •  ready again 10 seconds later\nA reading, not a guarantee of safety. Demo never uses a real scan or buys anything.",UDim2.new(0,16,1,-54),UDim2.new(1,-32,0,46),12)
 local bandIndex=1 local began=os.clock() local manual=false local destroyed=false local conns={}
 local function setBand(index)
  bandIndex=index local key=({"LOW","MEDIUM","HIGH"})[index]
  preview:SetReading(key,true)
  meaning.Text=(key=="HIGH" and "WARNING! " or "")..Visual.Labels[key]
  meaning.TextColor3=Visual.Colors[key] explanation.Text=Visual.Explanations[key]
  gui:SetAttribute("Reading",key)
  for k,b in pairs(buttons) do b.BackgroundColor3=k==key and Color3.fromRGB(43,62,72) or Color3.fromRGB(25,37,44) end
 end
 for i,key in ipairs({"LOW","MEDIUM","HIGH"}) do
  table.insert(conns,buttons[key].Activated:Connect(function() manual=true setBand(i) end))
 end
 local function layout()
  local safe=UIDevice.Layout().Safe
  -- DETECTOR_BIG_SCREEN_20261008: the panel may grow with the display, and the device with it.
  local w=math.min(1040,math.max(280,safe.Width-24))
  local h=math.min(780,math.max(230,safe.Height-24))
  panel.Size=UDim2.fromOffset(w,h)
  panel.Position=UIDevice.LocalPosition(gui,(safe.Left+safe.Right)/2,(safe.Top+safe.Bottom)/2)
  local portrait=w<500 and h>450
  if portrait then
   preview.Root.Position=UDim2.fromOffset(8,43) preview.Root.Size=UDim2.fromOffset(w-16,h*.44)
   info.Position=UDim2.fromOffset(18,45+h*.44) info.Size=UDim2.fromOffset(w-36,h*.45-30)
   eyebrow.Visible=false
   meaning.Position=UDim2.fromOffset(0,0) meaning.Size=UDim2.new(1,0,0,30) meaning.TextSize=19
   explanation.Position=UDim2.fromOffset(0,31) explanation.Size=UDim2.new(1,0,0,42) explanation.TextSize=13
   for i,key in ipairs({"LOW","MEDIUM","HIGH"}) do
    local b=buttons[key] b.Position=UDim2.new((i-1)/3,2,0,79) b.Size=UDim2.new(1/3,-4,0,44)
    b.Text=({"BLUE","YELLOW","RED"})[i]
   end
  else
   local compact=h<420
   local previewWidth=math.floor(w*(compact and .39 or .47))
   preview.Root.Position=UDim2.fromOffset(8,42) preview.Root.Size=UDim2.fromOffset(previewWidth,h-94)
   info.Position=UDim2.fromOffset(previewWidth+16,compact and 43 or 65)
   info.Size=UDim2.fromOffset(w-previewWidth-34,h-112)
   eyebrow.Visible=not compact
   meaning.Position=UDim2.fromOffset(0,compact and 0 or 27) meaning.Size=UDim2.new(1,0,0,compact and 28 or 40) meaning.TextSize=compact and 17 or 24
   explanation.Position=UDim2.fromOffset(0,compact and 31 or 71) explanation.Size=UDim2.new(1,0,0,compact and 43 or 54) explanation.TextSize=compact and 12 or 15
   for i,key in ipairs({"LOW","MEDIUM","HIGH"}) do
    local b=buttons[key]
    b.Position=compact and UDim2.new((i-1)/3,2,0,84) or UDim2.fromOffset(0,134+(i-1)*49)
    b.Size=compact and UDim2.new(1/3,-4,0,44) or UDim2.new(1,0,0,44)
    b.Text=(compact and {"BLUE","YELLOW","RED"} or {"BLUE / SAFE","YELLOW / NEARBY","RED / VERY CLOSE"})[i]
   end
  end
  note.Position=UDim2.new(0,16,1,portrait and -76 or -54)
  note.Size=UDim2.new(1,-32,0,portrait and 68 or 46)
  note.Text=portrait and "Z / D-pad left / SCAN during a run\nLive for 30 seconds / ready again 10 seconds later\nSIMULATED DEMO / No purchase or live scan\nKeep listening: no guaranteed safety."
   or "IN A RUN: Z / D-pad left / SCAN  •  live for 30 seconds  •  ready again 10 seconds later\nA reading, not a guarantee of safety. Demo never uses a real scan or buys anything."
  title.TextSize=w<550 and 14 or 19
  note.TextSize=h<420 and 10 or 12
 end
 local api={Root=gui,Preview=preview}
 function api:Destroy()
  if destroyed then return end destroyed=true
  for _,c in ipairs(conns) do c:Disconnect() end
  preview:Destroy() gui:Destroy()
 end
 local function dismiss() api:Destroy() if onClose then onClose() end end
 table.insert(conns,close.Activated:Connect(dismiss))
 table.insert(conns,UIS.InputBegan:Connect(function(input,processed)
  if not processed and (input.KeyCode==Enum.KeyCode.ButtonB or input.KeyCode==Enum.KeyCode.Escape) then dismiss() end
 end))
 table.insert(conns,UIDevice.Changed:Connect(layout))
 table.insert(conns,gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
 table.insert(conns,RunService.Heartbeat:Connect(function()
  if not manual then
   local i=math.min(3,math.floor((os.clock()-began)/3)+1)
   if i~=bandIndex then setBand(i) end
  end
 end))
 setBand(1) layout()
 return api
end
return Visual

end end,
ExitClient=function() return function()
-- Round Exit Client  (BACK_TO_LOBBY_20260914, Trello card 74)
--
-- One player-local way out of a running level. An alive player HOLDS a chip at
-- the top-left of the safe area -- the L key on a keyboard, a finger on the chip
-- on touch; a dead or escaped player reaches a confirm card from the spectate
-- band (SpectateController fires PlayerScripts.RoundExitPrompt), because there
-- the cursor is already free and a question with two buttons reads better. The
-- server owns the decision either way: GameManager's "leaveround" removes only
-- this player from the party, and the round goes on for everybody else.
--
-- HOLD_TO_LEAVE_20260916 (card 74, second pass). WHY A HOLD: in a live round the
-- first-person camera owns the mouse, so a chip that has to be CLICKED is
-- unreachable unless the cursor is unlocked mid-chase, which the owner rejected.
-- A hold needs no pointer at all, on either device.
--
-- THE CONTRACT, stated once here because it is spread over a dozen call sites:
--
--   * HOLD_SECONDS = 1.5 seconds of held time, accumulated from RenderStepped's
--     own delta, so the bar fills in the same wall-clock time at 15 FPS and at
--     240. Deliberately NOT os.clock(): in this project os.clock is process CPU
--     time (see the Studio note in CLAUDE.md), which is not what a player holds
--     a key for. The frame delta is wall time by definition.
--   * A tap, a click or an early release leaves NOTHING behind -- progress goes
--     back to 0 the instant the hold stops, and only a full 1.5 s sends.
--   * Every frame re-reads holdBlocked(). Typing in chat, the Roblox menu, any
--     screen-owning modal (store, terminal, queue, re-entry), the dispatch
--     briefing, the Level 1 guide, the PARTY DOWN card, losing window focus,
--     dying, respawning, escaping, the Level 2 exit transition and the round
--     ending all stop the hold and reset the bar. The per-frame re-read is the
--     authority; the signals below only make the same cancel happen sooner.
--   * AT MOST ONE REQUEST. Both paths share `requestPending`, and a completed
--     hold latches until the key or finger physically lifts, so a player who
--     keeps holding after the answer cannot fire a second "leaveround".
--   * The transport is untouched: RoundStatus "leaveround" out, and
--     "leaveack" / "leavefailed" / the round events back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")
local playerScripts = player:WaitForChild("PlayerScripts")
local playerGui = player:WaitForChild("PlayerGui")

local HOLD_SECONDS = 1.5
-- L was the one letter left: the 2026-09-16 binding sweep found WASD, Space,
-- Shift, Ctrl, Tab, Esc, F, Q, E, G, H, M, N, R, J, B, V, P, C, F4, I/O and "/"
-- already spoken for by this game or by Roblox's own core scripts.
local HOLD_KEY = Enum.KeyCode.L
local MESSAGE_SECONDS = 3   -- how long a refusal stays on the chip
local NO_ANSWER_SECONDS = 8 -- silence after which the player may ask again

local prompt = playerScripts:FindFirstChild("RoundExitPrompt")
if not prompt then
	prompt = Instance.new("BindableEvent")
	prompt.Name = "RoundExitPrompt"
	prompt.Parent = playerScripts
end

-- B6: authored Framewisp controls, shared request/hold lifecycle below.
local Hud = require(ReplicatedStorage:WaitForChild("RoundHud"))
local Binder = require(ReplicatedStorage:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
local gui = Instance.new("ScreenGui")
gui.Name = "RoundExitGui"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = 70
gui.Parent = playerGui
local restChip = Hud.Mount("HUD_PC", "LeaveChip", gui)
local wideChip = Hud.Mount("HUD_PC", "LeaveChipWide", gui)
local touchChip = Hud.Mount("HUD_Touch", "LeaveChipTouch", gui)
local noticeRoot = Hud.Mount("HUD_PC", "RoundExitNotice", gui)
local shade = Instance.new("Frame")
shade.Name = "RoundExitShade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 0.55
shade.BorderSizePixel = 0
shade.Active = true
shade.Visible = false
shade.Parent = gui
local card = Hud.Mount("HUD_PC", "RoundExitCard", shade, {Touch = UIDevice.Layout().IsTouch})
if not (restChip and wideChip and touchChip and noticeRoot and card) then
	warn("Round Exit Client: missing imported HUD templates")
	gui:Destroy()
	return
end
local chip = restChip
local hovered = false
local fill = Binder.at(wideChip, "HoldFill")
local fillWidth = fill.Size.X.Scale
local hint = Binder.text(Binder.at(wideChip, "HoldHint"))
local notice = Binder.text(Binder.at(noticeRoot, "Notice"))
local wideLabel = Binder.text(Binder.at(wideChip, "Label"))
local confirm = Binder.at(card, "BackToLobby")
local stay = Binder.at(card, "Stay")
stay.Modal = true -- release first-person cursor while this confirmation is visible
local confirmLabel = Binder.text(Binder.at(confirm, "Label"))
local ring = Hud.Ring(Binder.at(touchChip, "RingSlot"))
Hud.Keycap(Binder.at(wideChip, "KeyChip"), HOLD_KEY, Enum.KeyCode.ButtonSelect)
restChip.Selectable, wideChip.Selectable, touchChip.Selectable = false, false, false
for _, control in ipairs({restChip, wideChip, touchChip}) do
	control.Visible = false
	control.Active = false
end
notice.Text, noticeRoot.Visible, hint.Visible = "", false, false
local function setFill(fraction)
	fill.Size = UDim2.new(fillWidth * fraction, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
	ring(fraction, Binder.Palette.RailTeal)
end
local function placeControls()
	local layout = UIDevice.Layout()
	local safe = layout.Safe
	local left = safe.Left + (layout.IsTouch and 12 or 24)
	local top = safe.Top + (layout.IsTouch and 6 or 16)
	for _, control in ipairs({restChip, wideChip, touchChip}) do
		control.Position = UIDevice.LocalPosition(gui, left, top)
	end
	chip = layout.IsTouch and touchChip or restChip
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UIDevice.LocalPosition(gui, (safe.Left + safe.Right) / 2, (safe.Top + safe.Bottom) / 2)
	card.Size = UDim2.fromOffset(math.min(380, safe.Right - safe.Left - 24), 144)
	-- Keep both confirmation targets at least 44 high on a phone.
	if layout.IsTouch then
		confirm.Size = UDim2.new(confirm.Size.X.Scale, 0, 0, 44)
		stay.Size = UDim2.new(stay.Size.X.Scale, 0, 0, 44)
	end
	noticeRoot.Position = UIDevice.LocalPosition(gui, left, top + 48)
end

local requestPending = false
local requestSerial = 0 -- bumped by every answer, so an old timeout stays dead
local label = nil       -- transient chip copy; nil means "the resting prompt"
local labelSerial = 0
local holdConn = nil    -- non-nil exactly while a hold is running
local holdInput = nil   -- the touch/mouse/gamepad InputObject driving that hold
local held = 0          -- seconds accumulated by the current hold
local holdLatched = false -- a finished hold, waiting for the key/finger to lift

-- "HOLD L \u{2022} LOBBY" on a keyboard, "HOLD \u{2022} LOBBY" on a phone. UIDevice.Binding
-- returns "" for every touchscreen (and for a gamepad-only device, where no L
-- key exists), so a finger is never told to press a key it does not have.
local function paint()
	wideLabel.Text = "\u{B7} BACK TO LOBBY"
	-- The separate notice preserves a 44px phone door even for a long refusal.
	if label then notice.Text = label end
	noticeRoot.Visible = label ~= nil and label ~= ""
end

-- `seconds` nil means the copy stays until something replaces it. The serial is
-- what stops a stale timer from wiping a newer message.
local function say(text, seconds)
	labelSerial += 1
	label = text
	paint()
	if not text or not seconds then return end
	local serial = labelSerial
	task.delay(seconds, function()
		if labelSerial ~= serial then return end
		label = nil
		paint()
	end)
end

local function applyLayout()
	placeControls()
	paint()
end

local function alive()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function chipAvailable()
	return player:GetAttribute("InRound") == true
		and (workspace:GetAttribute("RoundActive") == true or player:GetAttribute("Level6PlaygroundPreview") == true)
		and alive()
		and player:GetAttribute("Spectating") ~= true
		and player:GetAttribute("Escaped") ~= true
		and player:GetAttribute("Level2_ExitTransition") ~= true
		and player:GetAttribute("RoundEntryControlsReady") == true
		and player:GetAttribute("DispatchBriefingOpen") ~= true
				and player:GetAttribute("Level4CardOpen") ~= true      -- Level 4's keypad or note, on touch (MOBILE_QA_20261008)
		and player:GetAttribute("PartyDownCardOpen") ~= true
		and not UIDevice.ScreenOwningModalOpen()
		and not GuiService.MenuIsOpen
		and not shade.Visible
end

-- A focused text box blocks the HOLD but deliberately not the CHIP: someone
-- typing in chat should still see the way out, they just must not trigger it by
-- typing the letter L. Everything else that hides the chip also stops a hold.
local function holdBlocked()
	return not chipAvailable() or UserInputService:GetFocusedTextBox() ~= nil
end

-- Stops the bar. `holdInput` deliberately SURVIVES: a finished or cancelled
-- hold still has to recognise the finger that started it when it finally lifts,
-- and a touch InputObject is the only handle there is on that finger.
local function stopHold()
	if holdConn then holdConn:Disconnect() end
	holdConn, held = nil, 0
	setFill(0)
	hint.Visible = false
end

-- The key or finger physically came up. That, and only that, clears the latch a
-- finished hold leaves behind.
local function releaseHold()
	holdLatched = false
	holdInput = nil
	stopHold()
end

local function refresh()
	if holdConn and holdBlocked() then stopHold() end
	local available = chipAvailable()
	local touch = UIDevice.Layout().IsTouch
	local expanded = not touch and (hovered or holdConn ~= nil)
	UIDevice.SetInteractive(restChip, available and not touch and not expanded)
	UIDevice.SetInteractive(wideChip, available and expanded)
	UIDevice.SetInteractive(touchChip, available and touch)
	hint.Visible = available and not touch and holdConn ~= nil
	-- Quiet resting chrome, bright during a deliberate hold or hover.
	for _, control in ipairs({restChip, touchChip}) do
		for _, node in ipairs(control:GetDescendants()) do
			if node:IsA("UIStroke") then node.Transparency = holdConn and 0.12 or 0.5 end
		end
	end
	if shade.Visible then
		noticeRoot.Position = UIDevice.LocalPosition(gui,
			card.AbsolutePosition.X, card.AbsolutePosition.Y + card.AbsoluteSize.Y + 8)
	end
end

local function closeCard()
	if not shade.Visible then return end
	shade.Visible = false
	placeControls()
	player:SetAttribute("RoundExitPromptOpen", nil)
	if GuiService.SelectedObject == stay or GuiService.SelectedObject == confirm then
		GuiService.SelectedObject = nil
	end
	refresh()
end

local function openCard()
	if shade.Visible or player:GetAttribute("InRound") ~= true
		or not (workspace:GetAttribute("RoundActive") == true or player:GetAttribute("Level6PlaygroundPreview") == true) then return end
	stopHold()
	-- The card RENDERS the shared latch rather than clearing it: a request that
	-- is already in flight (held down, then died) must not become a second one.
	confirmLabel.Text = requestPending and "RETURNING..." or "BACK TO LOBBY"
	notice.Text = requestPending and "Returning to the lobby..." or ""
	UIDevice.SetEnabled(confirm, not requestPending)
	shade.Visible = true
	player:SetAttribute("RoundExitPromptOpen", true)
	refresh()
	if UIDevice.LastInput() == "Gamepad" then GuiService.SelectedObject = stay end
end

-- Back to "nothing is in flight". The latch a finished hold left is NOT cleared
-- here: only a real release does that, so a still-held key cannot re-arm.
local function resetRequest()
	requestSerial += 1
	requestPending = false
	stopHold()
	say(nil)
	confirmLabel.Text = "BACK TO LOBBY"
	UIDevice.SetEnabled(confirm, true)
	notice.Text = ""
end

-- The one place that talks to the server. Both the hold and the card come here.
local function sendLeave()
	if requestPending then return end
	requestPending = true
	requestSerial += 1
	local serial = requestSerial
	say("RETURNING...")
	confirmLabel.Text = "RETURNING..."
	UIDevice.SetEnabled(confirm, false)
	notice.Text = "Returning to the lobby..."
	remote:FireServer("leaveround")
	task.delay(NO_ANSWER_SECONDS, function()
		-- No answer at all: let the player ask again rather than sit forever.
		if requestSerial ~= serial then return end
		requestPending = false
		say("NO ANSWER \u{B7} HOLD AGAIN", MESSAGE_SECONDS)
		confirmLabel.Text = "TRY AGAIN"
		UIDevice.SetEnabled(confirm, true)
		notice.Text = "No answer from the server yet."
	end)
end

local function step(delta)
	-- Re-read the whole cancel list every frame. Some of it has no signal this
	-- file listens to (a modal another script opens, a humanoid that dies inside
	-- a transition), and a hold must never outlive the state that allowed it.
	if holdBlocked() then
		stopHold()
		refresh()
		return
	end
	held += delta
	setFill(math.min(1, held / HOLD_SECONDS))
	if held < HOLD_SECONDS then return end
	holdLatched = true -- no auto-repeat: the key/finger has to come up first
	stopHold()
	sendLeave()
	refresh()
end

local function beginHold(input)
	if holdConn or holdLatched or requestPending or holdBlocked() then return end
	holdInput = input
	held = 0
	setFill(0)
	hint.Visible = true
	holdConn = RunService.RenderStepped:Connect(step)
	refresh()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if (input.KeyCode ~= HOLD_KEY and input.KeyCode ~= Enum.KeyCode.ButtonSelect) or processed then return end
	if input.UserInputState ~= Enum.UserInputState.Begin then return end
	beginHold(input)
end)
UserInputService.InputEnded:Connect(function(input)
	-- Matched on the input OBJECT for a finger that slid off the chip before
	-- lifting: the chip's own InputEnded cannot be relied on to see that one.
	if input.KeyCode == HOLD_KEY or input.KeyCode == Enum.KeyCode.ButtonSelect or (holdInput ~= nil and input == holdInput) then
		releaseHold()
		refresh()
	end
end)
-- A key held while the window loses focus never reports its InputEnded, so this
-- is the only thing that can clear the latch in that case.
UserInputService.WindowFocusReleased:Connect(function() releaseHold() refresh() end)
UserInputService.TextBoxFocused:Connect(refresh)
UserInputService.TextBoxFocusReleased:Connect(refresh)

for _, control in ipairs({restChip, wideChip, touchChip}) do
	control.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then beginHold(input) end
	end)
	control.InputEnded:Connect(function(input)
		if holdInput ~= nil and input == holdInput then releaseHold() refresh() end
	end)
end
restChip.MouseEnter:Connect(function() hovered = true refresh() end)
wideChip.MouseLeave:Connect(function() hovered = false refresh() end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.ButtonB and shade.Visible
		and not GuiService.MenuIsOpen and UserInputService:GetFocusedTextBox() == nil then closeCard() end
end)

prompt.Event:Connect(openCard)
stay.Activated:Connect(closeCard)
confirm.Activated:Connect(function()
	-- sendLeave() is the single authority on "one request at a time"; repeating
	-- the test here would be a second place for that rule to drift out of.
	if shade.Visible then sendLeave() end
end)

remote.OnClientEvent:Connect(function(event)
	if event == "leaveack" then
		requestSerial += 1 -- answered; the armed no-answer timer belongs to the past
		say("RETURNING TO LOBBY...")
		notice.Text = "Returning to the lobby..."
	elseif event == "leavefailed" then
		requestSerial += 1
		requestPending = false
		say("NOT AVAILABLE IN THIS TEST ROUND", MESSAGE_SECONDS)
		confirmLabel.Text = "BACK TO LOBBY"
		UIDevice.SetEnabled(confirm, true)
		notice.Text = "Not available in this test round."
	elseif event == "lobby" or event == "loadinggame" or event == "lose" or event == "win" then
		resetRequest()
		closeCard()
	end
end)

for _, attribute in ipairs({"InRound", "Spectating", "Escaped", "Level2_ExitTransition",
	"RoundEntryControlsReady", "DispatchBriefingOpen", "LevelOneGuideObjectivesOpen", "Level4CardOpen",
	"PartyDownCardOpen"}) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if attribute == "InRound" and player:GetAttribute("InRound") ~= true then
			resetRequest()
			closeCard()
		end
		refresh()
	end)
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") ~= true then
		resetRequest()
		closeCard()
	end
	refresh()
end)
UIDevice.OnScreenOwningModalChanged(refresh)
GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(function()
	if GuiService.MenuIsOpen then closeCard() end
	refresh()
end)
UIDevice.Changed:Connect(function()
	releaseHold()
	hovered = false
	applyLayout()
	paint() -- the binding glyph is device-dependent
	refresh()
end)

local function bindCharacter(character)
	stopHold()
	closeCard()
	refresh()
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		humanoid.HealthChanged:Connect(refresh)
		humanoid.Died:Connect(refresh)
		refresh()
	end)
end
player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(function()
	stopHold()
	closeCard()
	refresh()
end)
if player.Character then bindCharacter(player.Character) end

applyLayout()
paint()
refresh()

end end
}
local TREES = {["HUD_PC"]={["Name"]="HUD_PC",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=1,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=false,["Attributes"]={["BB_DesignH"]=1080,["BB_DesignW"]=1920,["BB_TextFactor"]=1.16,["FW_Owned"]=true,["FigmaNodeId"]="313:2",["HudTemplateSource"]="Imports.Framewisp_Live_HUD_PC.HUD_PC"},["Children"]={{["Name"]="RecLine",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.233333,0,0.027778,0},["Position"]={0.154167,0,0.093519,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=4,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:3"},["Children"]={{["Name"]="Dot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.033482,0,0.5,0},["Position"]={0.016741,0,0.516667,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=6,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,112,95},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:4"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Rec",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.098214,0,0.966667,0},["Position"]={0.100446,0,0.520121,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=8,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="REC",["TextScaled"]=false,["TextSize"]=11,["TextColor3"]={242,235,219},["TextTransparency"]=0.08,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=11.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0253|0.0941",["FW_M100"]=138,["FW_Owned"]=true,["FW_Text0"]="REC",["FW_TextMine"]=11,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.505,["FigmaBaseF"]=0.7931,["FigmaBaseY"]=23,["FigmaFontSize"]=22,["FigmaInk"]="1.4,7.1,37.3,16.1",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:5",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=40},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Time",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.223214,0,0.966667,0},["Position"]={0.272321,0,0.520121,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=10,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="1:02:37",["TextScaled"]=false,["TextSize"]=11,["TextColor3"]={242,235,219},["TextTransparency"]=0.08,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=11.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0253|0.0941",["FW_M100"]=322,["FW_Owned"]=true,["FW_Text0"]="1:02:37",["FW_TextMine"]=11,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.505,["FigmaBaseF"]=0.7931,["FigmaBaseY"]=23,["FigmaFontSize"]=22,["FigmaInk"]="1.9,7.1,89.1,16.1",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:6",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=93},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="SignalLabel",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.133929,0,0.7,0},["Position"]={0.491071,0,0.53327,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=12,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="SIGNAL",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={242,235,219},["TextTransparency"]=0.1,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=8.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0184|0.0944",["FW_M100"]=276,["FW_Owned"]=true,["FW_Text0"]="SIGNAL",["FW_TextMine"]=8,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.511667,["FigmaBaseF"]=0.8095,["FigmaBaseY"]=17,["FigmaFontSize"]=16,["FigmaInk"]="0.7,5.5,56.1,11.7",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:7",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=58},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Bars",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.075893,0,0.633333,0},["Position"]={0.609375,0,0.516667,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=14,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:8"},["Children"]={{["Name"]="Bar1",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.205882,0,0.368421,0},["Position"]={0.102941,0,0.815789,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=16,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:9"}},{["Name"]="Bar2",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.205882,0,0.578947,0},["Position"]={0.367647,0,0.710526,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=18,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:10"}},{["Name"]="Bar3",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.205882,0,0.789474,0},["Position"]={0.632353,0,0.605263,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=20,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:11"}},{["Name"]="Bar4",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.205882,0,1,0},["Position"]={0.897059,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=22,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={38,49,52},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:12"}}}},{["Name"]="Watching",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.330357,0,0.7,0},["Position"]={0.834821,0,0.53327,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=24,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="\u{B7} 12 WATCHING",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=8.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0184|0.0944",["FW_M100"]=598,["FW_Owned"]=true,["FW_Text0"]="\u{B7} 12 WATCHING",["FW_TextMine"]=8,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.511667,["FigmaBaseF"]=0.8095,["FigmaBaseY"]=17,["FigmaFontSize"]=16,["FigmaInk"]="3.9,5.5,120.3,11.7",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:13",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=125},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Bracket",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.029167,0,0.051852,0},["Position"]={0.035417,0,0.090741,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=26,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:14"},["Children"]={{["Name"]="ArmH",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.071429,0},["Position"]={0.5,0,0.035714,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=28,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:15"}},{["Name"]="ArmV",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.071429,0,1,0},["Position"]={0.035714,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=30,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:16"}}}},{["Name"]="ObjectiveCard",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.1875,0,0.207407,0},["Position"]={0.86875,0,0.175926,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=32,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,255,255},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:17"},["Children"]={{["Name"]="UIGradient",["ClassName"]="UIGradient",["Rotation"]=0,["Offset"]={0,0},["Enabled"]=true,["ColorKeypoints"]={{0,5,9,11},{1,5,9,11}},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.0536,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Head",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.285714,0},["Position"]={0.5,0,0.142857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=34,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:18"},["Children"]={{["Name"]="Eyebrow",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.911111,0,0.28125,0},["Position"]={0.5,0,0.294994,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=36,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="WATCHING ALEXANDRA \u{B7} LEVEL 3",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={255,230,0},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.0897",["FW_M100"]=1288,["FW_Owned"]=true,["FW_Text0"]="WATCHING ALEXANDRA \u{B7} LEVEL 3",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.296875,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="0.2,3.9,234.3,10.2",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:19",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=236},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Title",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.911111,0,0.421875,0},["Position"]={0.5,0,0.678829,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=38,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="LOAD THE PROJECTORS",["TextScaled"]=false,["TextSize"]=10,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=10.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0230|0.1124",["FW_M100"]=1077,["FW_Owned"]=true,["FW_Text0"]="LOAD THE PROJECTORS",["FW_TextMine"]=10,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.675781,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=21,["FigmaFontSize"]=22,["FigmaInk"]="1.3,5.2,284.3,16.1",["FigmaInkC"]=0.3498,["FigmaNodeId"]="313:20",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=286},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Underbar",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.133333,0,0.0625,0},["Position"]={0.111111,0,0.9375,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=40,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,230,0},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:21"}}}},{["Name"]="Counter",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.142857,0},["Position"]={0.5,0,0.357143,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=42,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:22"},["Children"]={{["Name"]="Count",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.144444,0,0.9375,0},["Position"]={0.116667,0,0.551738,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=44,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="1/3",["TextScaled"]=false,["TextSize"]=12,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=12.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0276|0.1478",["FW_M100"]=117,["FW_Owned"]=true,["FW_Text0"]="1/3",["FW_TextMine"]=12,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.542188,["FigmaBaseF"]=0.8,["FigmaBaseY"]=24,["FigmaFontSize"]=26,["FigmaInk"]="2,5.2,31.6,20.3",["FigmaInkC"]=0.3299,["FigmaNodeId"]="313:23",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=35},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="CountTag",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.744444,0,0.5625,0},["Position"]={0.583333,0,0.527487,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=46,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="CDS IN THE PLAYER",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.1471",["FW_M100"]=782,["FW_Owned"]=true,["FW_Text0"]="CDS IN THE PLAYER",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.53125,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="0.5,3.9,142.2,10.2",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:24",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=143},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Progress",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.053571,0},["Position"]={0.5,0,0.455357,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=48,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:25"},["Children"]={{["Name"]="Track",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.911111,0,0.333333,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=50,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={38,49,52},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:26"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Fill",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.332317,0,1,0},["Position"]={0.166159,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=52,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,230,0},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:27"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Guide1",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.107143,0},["Position"]={0.5,0,0.535714,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=54,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:28"},["Children"]={{["Name"]="Line",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.911111,0,0.833333,0},["Position"]={0.5,0,0.605689,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=56,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="You carry 2 reels.",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.4 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0161|0.1857",["FW_M100"]=717,["FW_Owned"]=true,["FW_Text0"]="You carry 2 reels.",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.56875,["FigmaBaseF"]=0.8,["FigmaBaseY"]=16,["FigmaFontSize"]=16,["FigmaInk"]="-0.1,4.1,137.8,15.1",["FigmaInkC"]=0.2705,["FigmaNodeId"]="313:29",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=139},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Guide2",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.107143,0},["Position"]={0.5,0,0.642857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=58,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:30"},["Children"]={{["Name"]="Line",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.911111,0,0.833333,0},["Position"]={0.5,0,0.541106,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=60,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Follow the reader to the next CD.",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.4 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0161|0.2065",["FW_M100"]=1408,["FW_Owned"]=true,["FW_Text0"]="Follow the reader to the next CD.",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.504167,["FigmaBaseF"]=0.8,["FigmaBaseY"]=16,["FigmaFontSize"]=16,["FigmaInk"]="1.5,4.1,269.5,12",["FigmaInkC"]=0.3662,["FigmaNodeId"]="313:31",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=272},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="StatusRow",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.107143,0},["Position"]={0.5,0,0.75,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=62,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:32"},["Children"]={{["Name"]="Bar",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.011111,0,0.833333,0},["Position"]={0.05,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=64,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={232,160,36},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:33"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.872222,0,0.833333,0},["Position"]={0.519444,0,0.530689,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=66,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Main breaker: fuse 42 s",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={232,160,36},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.4 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0161|0.2285",["FW_M100"]=980,["FW_Owned"]=true,["FW_Text0"]="Main breaker: fuse 42 s",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.49375,["FigmaBaseF"]=0.8,["FigmaBaseY"]=16,["FigmaFontSize"]=16,["FigmaInk"]="1.5,3.6,187.1,12.5",["FigmaInkC"]=0.3828,["FigmaNodeId"]="313:34",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=190},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Compass",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.196429,0},["Position"]={0.5,0,0.901786,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=68,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:35"},["Children"]={{["Name"]="Ticks",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.544444,0,0.227273,0},["Position"]={0.316667,0,0.704545,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=70,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:36"},["Children"]={{["Name"]="Baseline",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.2,0},["Position"]={0.5,0,0.9,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=72,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={38,49,52},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:37"}},{["Name"]="Tick1",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.010204,0,0.8,0},["Position"]={0.005102,0,0.4,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=74,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:38"}},{["Name"]="Tick2",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.010204,0,0.8,0},["Position"]={0.127551,0,0.4,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=76,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:39"}},{["Name"]="Tick3",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.010204,0,0.8,0},["Position"]={0.255102,0,0.4,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=78,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:40"}},{["Name"]="Tick4",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.010204,0,0.8,0},["Position"]={0.377551,0,0.4,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=80,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:41"}},{["Name"]="Tick5",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.010204,0,0.8,0},["Position"]={0.5,0,0.4,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=82,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:42"}},{["Name"]="Tick6",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.010204,0,0.8,0},["Position"]={0.627551,0,0.4,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=84,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:43"}},{["Name"]="Tick7",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.010204,0,0.8,0},["Position"]={0.755102,0,0.4,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=86,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:44"}},{["Name"]="Tick8",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.010204,0,0.8,0},["Position"]={0.877551,0,0.4,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=88,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:45"}},{["Name"]="Tick9",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.010204,0,0.8,0},["Position"]={0.994898,0,0.4,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=90,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:46"}}}},{["Name"]="Centre",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.005556,0,0.409091,0},["Position"]={0.316667,0,0.568182,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=92,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:47"}},{["Name"]="Chevron",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.055556,0,0.363636,0},["Position"]={0.316667,0,0.231504,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=94,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="v",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={255,230,0},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Top",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Top)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.2483",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="v",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.227273,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="6.3,6.6,7.4,7.4",["FigmaInkC"]=0.264,["FigmaNodeId"]="313:48",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=9},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Readout",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.344444,0,0.409091,0},["Position"]={0.783333,0,0.451809,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=96,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="IN THIS ROOM",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Right",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.2573",["FW_M100"]=552,["FW_Owned"]=true,["FW_Text0"]="IN THIS ROOM",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.454545,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="24.4,3.9,98.8,10.2",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:49",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=101},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}},{["Name"]="FlashlightWidget",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.120833,0,0.063889,0},["Position"]={0.097917,0,0.913426,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=98,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:50"},["Children"]={{["Name"]="KeyChip",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.125,0,0.405797,0},["Position"]={0.0625,0,0.304348,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=100,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={22,29,32},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:51"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2143,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.071429,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="GlyphSlot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.689655,0,0.714286,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=102,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:52"}},{["Name"]="Key",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.495699,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=104,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="F",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.9008",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="F",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=19,["FigmaFontSize"]=14,["FigmaInk"]="11.3,9,6.7,10",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:53",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=9},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Battery",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.443966,0,0.57971,0},["Position"]={0.394397,0,0.289855,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=106,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:54"},["Children"]={{["Name"]="Shell",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.932039,0,1,0},["Position"]={0.466019,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=108,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:55"},["Children"]={{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={242,235,219},["Thickness"]=0.075,["Transparency"]=0.1,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Miter",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=3}}}},{["Name"]="Seg1",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.145631,0,0.7,0},["Position"]={0.121359,0,0.525,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=110,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:56"}},{["Name"]="Seg2",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.145631,0,0.7,0},["Position"]={0.296117,0,0.525,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=112,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:57"}},{["Name"]="Seg3",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.145631,0,0.7,0},["Position"]={0.461165,0,0.525,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=114,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:58"}},{["Name"]="Seg4",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.145631,0,0.7,0},["Position"]={0.616505,0,0.525,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=116,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:59"}},{["Name"]="Seg5",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.145631,0,0.7,0},["Position"]={0.781553,0,0.525,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=118,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={38,49,52},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:60"}},{["Name"]="Nub",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.067961,0,0.4,0},["Position"]={0.966019,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=120,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:61"}}}},{["Name"]="Plate",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.810345,0,0.347826,0},["Position"]={0.577586,0,0.826087,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=122,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.5,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:62"}},{["Name"]="Line",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.758621,0,0.26087,0},["Position"]={0.586207,0,0.824342,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=124,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="LIGHT OFF \u{B7} CHARGING",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0.1,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.9341",["FW_M100"]=920,["FW_Owned"]=true,["FW_Text0"]="LIGHT OFF \u{B7} CHARGING",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.826087,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="1,3.9,166.5,10.2",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:63",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=169},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="EquipmentPanel",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.145833,0,0.077778,0},["Position"]={0.236458,0,0.909259,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=126,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:64"},["Children"]={{["Name"]="Items",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=128,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="UIListLayout",["ClassName"]="UIListLayout",["FillDirection"]="Enum.FillDirection.Horizontal",["Padding"]={0.028571,0},["SortOrder"]="Enum.SortOrder.LayoutOrder",["HorizontalAlignment"]="Enum.HorizontalAlignment.Left",["VerticalAlignment"]="Enum.VerticalAlignment.Top",["Wraps"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaGap"]=8}},{["Name"]="Chip_Shield",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.228571,0,1,0},["Position"]={0,0,0,0},["AnchorPoint"]={0,0},["ZIndex"]=130,["LayoutOrder"]=1,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:65"},["Children"]={{["Name"]="Face",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.761905,0},["Position"]={0.5,0,0.47619,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=132,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:66"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1875,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.03125,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}}}},{["Name"]="Icon",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.4375,0,0.333333,0},["Position"]={0.5,0,0.369048,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=134,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:67"},["Children"]={{["Name"]="Top",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.642857,0,0.428571,0},["Position"]={0.5,0,0.321429,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=136,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:68"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1667,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Point",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.642857,0,0.642857,0},["Position"]={0.5,0,0.571429,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=138,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:69"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Cooldown",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.309524,0},["Position"]={0.5,0,0.473865,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=140,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="12",["TextScaled"]=false,["TextSize"]=10,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=10.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0230|0.9072",["FW_M100"]=88,["FW_Owned"]=true,["FW_Text0"]="12",["FW_TextMine"]=10,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.464881,["FigmaBaseF"]=0.8077,["FigmaBaseY"]=21,["FigmaFontSize"]=22,["FigmaInk"]="22.4,5.1,19.9,15.9",["FigmaInkC"]=0.3604,["FigmaNodeId"]="313:70",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=23},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="ActiveTime",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.27381,0},["Position"]={0.5,0,0.319395,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=142,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="4.2",["TextScaled"]=false,["TextSize"]=9,["TextColor3"]={68,221,196},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=9.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0207|0.8952",["FW_M100"]=113,["FW_Owned"]=true,["FW_Text0"]="4.2",["FW_TextMine"]=9,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.319643,["FigmaBaseF"]=0.7826,["FigmaBaseY"]=18,["FigmaFontSize"]=20,["FigmaInk"]="19.4,3.6,25,14.5",["FigmaInkC"]=0.3578,["FigmaNodeId"]="313:71",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=27},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="ActiveTag",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.190476,0},["Position"]={0.5,0,0.659656,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=144,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="SAFE",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={68,221,196},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0138|0.9217",["FW_M100"]=184,["FW_Owned"]=true,["FW_Text0"]="SAFE",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.652381,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="18.1,4.4,27.7,8.8",["FigmaInkC"]=0.3561,["FigmaNodeId"]="313:72",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=29},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Badge",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.3125,0,0.238095,0},["Position"]={0.90625,0,0.119048,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=146,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:73"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Count",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.9,0},["Position"]={0.5,0,0.493913,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=148,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="2",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={5,9,11},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0161|0.8795",["FW_M100"]=44,["FW_Owned"]=true,["FW_Text0"]="2",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.4975,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="6.8,3.9,6.2,10.1",["FigmaInkC"]=0.3605,["FigmaNodeId"]="313:74",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=8},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="KeyChip",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.453125,0,0.333333,0},["Position"]={0.507813,0,0.833333,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=150,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={22,29,32},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:75"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2143,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.071429,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="GlyphSlot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.689655,0,0.714286,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=152,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:76"}},{["Name"]="Key",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.496057,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=154,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Q",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.9351",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="Q",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=19.01,["FigmaFontSize"]=14,["FigmaInk"]="10.9,8.9,7.7,11.8",["FigmaInkC"]=0.298,["FigmaNodeId"]="313:77",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=9},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}},{["Name"]="Chip_Potion",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.228571,0,1,0},["Position"]={0,0,0,0},["AnchorPoint"]={0,0},["ZIndex"]=156,["LayoutOrder"]=2,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:78"},["Children"]={{["Name"]="Face",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.761905,0},["Position"]={0.5,0,0.47619,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=158,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:79"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1875,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.03125,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}}}},{["Name"]="Icon",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.4375,0,0.333333,0},["Position"]={0.5,0,0.369048,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=160,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:80"},["Children"]={{["Name"]="Bulb",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.571429,0,0.571429,0},["Position"]={0.5,0,0.642857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=162,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:81"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Neck",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.214286,0,0.25,0},["Position"]={0.5,0,0.303571,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=164,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:82"}},{["Name"]="Cap",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.357143,0,0.107143,0},["Position"]={0.5,0,0.125,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=166,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:83"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3333,0},["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Cooldown",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.309524,0},["Position"]={0.5,0,0.473865,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=168,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="12",["TextScaled"]=false,["TextSize"]=10,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=10.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0230|0.9072",["FW_M100"]=88,["FW_Owned"]=true,["FW_Text0"]="12",["FW_TextMine"]=10,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.464881,["FigmaBaseF"]=0.8077,["FigmaBaseY"]=21,["FigmaFontSize"]=22,["FigmaInk"]="22.4,5.1,19.9,15.9",["FigmaInkC"]=0.3604,["FigmaNodeId"]="313:84",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=23},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="ActiveTime",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.27381,0},["Position"]={0.5,0,0.319395,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=170,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="4.2",["TextScaled"]=false,["TextSize"]=9,["TextColor3"]={68,221,196},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=9.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0207|0.8952",["FW_M100"]=113,["FW_Owned"]=true,["FW_Text0"]="4.2",["FW_TextMine"]=9,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.319643,["FigmaBaseF"]=0.7826,["FigmaBaseY"]=18,["FigmaFontSize"]=20,["FigmaInk"]="19.4,3.6,25,14.5",["FigmaInkC"]=0.3578,["FigmaNodeId"]="313:85",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=27},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="ActiveTag",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.190476,0},["Position"]={0.5,0,0.659656,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=172,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="SAFE",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={68,221,196},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0138|0.9217",["FW_M100"]=184,["FW_Owned"]=true,["FW_Text0"]="SAFE",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.652381,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="18.1,4.4,27.7,8.8",["FigmaInkC"]=0.3561,["FigmaNodeId"]="313:86",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=29},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Badge",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.3125,0,0.238095,0},["Position"]={0.90625,0,0.119048,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=174,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:87"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Count",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.9,0},["Position"]={0.5,0,0.493913,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=176,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="2",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={5,9,11},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0161|0.8795",["FW_M100"]=44,["FW_Owned"]=true,["FW_Text0"]="2",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.4975,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="6.8,3.9,6.2,10.1",["FigmaInkC"]=0.3605,["FigmaNodeId"]="313:88",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=8},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="KeyChip",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.453125,0,0.333333,0},["Position"]={0.507813,0,0.833333,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=178,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={22,29,32},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:89"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2143,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.071429,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="GlyphSlot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.689655,0,0.714286,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=180,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:90"}},{["Name"]="Key",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.495699,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=182,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="T",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.9351",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="T",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=19,["FigmaFontSize"]=14,["FigmaInk"]="10.5,9,8,10",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:91",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=9},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}},{["Name"]="Chip_Markers",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.228571,0,1,0},["Position"]={0,0,0,0},["AnchorPoint"]={0,0},["ZIndex"]=184,["LayoutOrder"]=3,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:92"},["Children"]={{["Name"]="Face",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.761905,0},["Position"]={0.5,0,0.47619,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=186,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:93"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1875,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.03125,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}}}},{["Name"]="Icon",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.4375,0,0.333333,0},["Position"]={0.5,0,0.369048,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=188,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:94"},["Children"]={{["Name"]="Pole",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.107143,0,0.785714,0},["Position"]={0.267857,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=190,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:95"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3333,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Flag",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.464286,0,0.357143,0},["Position"]={0.553571,0,0.285714,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=192,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:96"}}}},{["Name"]="Cooldown",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.309524,0},["Position"]={0.5,0,0.473865,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=194,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="12",["TextScaled"]=false,["TextSize"]=10,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=10.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0230|0.9072",["FW_M100"]=88,["FW_Owned"]=true,["FW_Text0"]="12",["FW_TextMine"]=10,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.464881,["FigmaBaseF"]=0.8077,["FigmaBaseY"]=21,["FigmaFontSize"]=22,["FigmaInk"]="22.4,5.1,19.9,15.9",["FigmaInkC"]=0.3604,["FigmaNodeId"]="313:97",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=23},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="ActiveTime",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.27381,0},["Position"]={0.5,0,0.319395,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=196,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="4.2",["TextScaled"]=false,["TextSize"]=9,["TextColor3"]={68,221,196},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=9.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0207|0.8952",["FW_M100"]=113,["FW_Owned"]=true,["FW_Text0"]="4.2",["FW_TextMine"]=9,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.319643,["FigmaBaseF"]=0.7826,["FigmaBaseY"]=18,["FigmaFontSize"]=20,["FigmaInk"]="19.4,3.6,25,14.5",["FigmaInkC"]=0.3578,["FigmaNodeId"]="313:98",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=27},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="ActiveTag",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.190476,0},["Position"]={0.5,0,0.659656,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=198,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="SAFE",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={68,221,196},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0138|0.9217",["FW_M100"]=184,["FW_Owned"]=true,["FW_Text0"]="SAFE",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.652381,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="18.1,4.4,27.7,8.8",["FigmaInkC"]=0.3561,["FigmaNodeId"]="313:99",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=29},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Badge",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.3125,0,0.238095,0},["Position"]={0.90625,0,0.119048,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=200,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:100"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Count",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.9,0},["Position"]={0.5,0,0.493913,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=202,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="2",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={5,9,11},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0161|0.8795",["FW_M100"]=44,["FW_Owned"]=true,["FW_Text0"]="2",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.4975,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="6.8,3.9,6.2,10.1",["FigmaInkC"]=0.3605,["FigmaNodeId"]="313:101",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=8},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="KeyChip",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.453125,0,0.333333,0},["Position"]={0.507813,0,0.833333,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=204,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={22,29,32},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:102"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2143,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.071429,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="GlyphSlot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.689655,0,0.714286,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=206,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:103"}},{["Name"]="Key",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.495699,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=208,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="X",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.9351",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="X",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=19,["FigmaFontSize"]=14,["FigmaInk"]="10.5,9,8.2,10",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:104",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=9},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}},{["Name"]="Chip_Scan",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.228571,0,1,0},["Position"]={0,0,0,0},["AnchorPoint"]={0,0},["ZIndex"]=210,["LayoutOrder"]=4,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:105"},["Children"]={{["Name"]="Face",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.761905,0},["Position"]={0.5,0,0.47619,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=212,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:106"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1875,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.03125,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}}}},{["Name"]="Icon",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.4375,0,0.333333,0},["Position"]={0.5,0,0.369048,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=214,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:107"},["Children"]={{["Name"]="Bar1",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.178571,0,0.285714,0},["Position"]={0.267857,0,0.714286,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=216,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:108"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Bar2",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.178571,0,0.5,0},["Position"]={0.517857,0,0.607143,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=218,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:109"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Bar3",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.178571,0,0.714286,0},["Position"]={0.767857,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=220,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:110"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2,0},["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Cooldown",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.309524,0},["Position"]={0.5,0,0.473865,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=222,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="12",["TextScaled"]=false,["TextSize"]=10,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=10.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0230|0.9072",["FW_M100"]=88,["FW_Owned"]=true,["FW_Text0"]="12",["FW_TextMine"]=10,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.464881,["FigmaBaseF"]=0.8077,["FigmaBaseY"]=21,["FigmaFontSize"]=22,["FigmaInk"]="22.4,5.1,19.9,15.9",["FigmaInkC"]=0.3604,["FigmaNodeId"]="313:111",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=23},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="ActiveTime",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.27381,0},["Position"]={0.5,0,0.319395,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=224,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="4.2",["TextScaled"]=false,["TextSize"]=9,["TextColor3"]={68,221,196},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=9.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0207|0.8952",["FW_M100"]=113,["FW_Owned"]=true,["FW_Text0"]="4.2",["FW_TextMine"]=9,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.319643,["FigmaBaseF"]=0.7826,["FigmaBaseY"]=18,["FigmaFontSize"]=20,["FigmaInk"]="19.4,3.6,25,14.5",["FigmaInkC"]=0.3578,["FigmaNodeId"]="313:112",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=27},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="ActiveTag",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.190476,0},["Position"]={0.5,0,0.659656,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=226,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="SAFE",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={68,221,196},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0138|0.9217",["FW_M100"]=184,["FW_Owned"]=true,["FW_Text0"]="SAFE",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.652381,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="18.1,4.4,27.7,8.8",["FigmaInkC"]=0.3561,["FigmaNodeId"]="313:113",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=29},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Badge",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.3125,0,0.238095,0},["Position"]={0.90625,0,0.119048,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=228,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:114"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Count",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.9,0},["Position"]={0.5,0,0.493913,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=230,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="2",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={5,9,11},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0161|0.8795",["FW_M100"]=44,["FW_Owned"]=true,["FW_Text0"]="2",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.4975,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="6.8,3.9,6.2,10.1",["FigmaInkC"]=0.3605,["FigmaNodeId"]="313:115",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=8},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="KeyChip",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.453125,0,0.333333,0},["Position"]={0.507813,0,0.833333,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=232,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={22,29,32},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:116"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2143,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.071429,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="GlyphSlot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.689655,0,0.714286,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=234,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:117"}},{["Name"]="Key",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.495699,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=236,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Z",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.9351",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="Z",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=19,["FigmaFontSize"]=14,["FigmaInk"]="10.9,9,7.3,10",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:118",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=9},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}}}}}},{["Name"]="EquipmentCaption",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.104167,0,0.022222,0},["Position"]={0.375,0,0.927778,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=238,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:119"},["Children"]={{["Name"]="Soft",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=240,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,255,255},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:120"},["Children"]={{["Name"]="UIGradient",["ClassName"]="UIGradient",["Rotation"]=0,["Offset"]={0,0},["Enabled"]=true,["ColorKeypoints"]={{0,5,9,11},{1,5,9,11}},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.92,0,0.75,0},["Position"]={0.5,0,0.494983,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=242,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="NO MARKERS LEFT",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,112,95},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.9277",["FW_M100"]=690,["FW_Owned"]=true,["FW_Text0"]="NO MARKERS LEFT",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="0.8,3.9,125.1,10.2",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:121",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=127},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="DetectorCard",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.1625,0,0.066667,0},["Position"]={0.229687,0,0.82037,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=244,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:122"},["Children"]={{["Name"]="Soft",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=246,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,255,255},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:123"},["Children"]={{["Name"]="UIGradient",["ClassName"]="UIGradient",["Rotation"]=0,["Offset"]={0,0},["Enabled"]=true,["ColorKeypoints"]={{0,5,9,11},{1,5,9,11}},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1667,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Bars",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.096154,0,0.444444,0},["Position"]={0.099359,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=248,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:124"},["Children"]={{["Name"]="Bar1",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.266667,0,0.375,0},["Position"]={0.133333,0,0.8125,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=250,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={232,160,36},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:125"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Bar2",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.266667,0,0.6875,0},["Position"]={0.5,0,0.65625,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=252,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={232,160,36},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:126"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Bar3",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.266667,0,1,0},["Position"]={0.866667,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=254,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={38,49,52},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:127"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Reading",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.641026,0,0.25,0},["Position"]={0.512821,0,0.317772,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=256,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="SCAN \u{B7} MEDIUM",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={232,160,36},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.8082",["FW_M100"]=598,["FW_Owned"]=true,["FW_Text0"]="SCAN \u{B7} MEDIUM",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.319444,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="0.6,3.9,107.9,10.2",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:128",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=110},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Headline",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.641026,0,0.305556,0},["Position"]={0.512821,0,0.622445,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=258,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="ENTITY VERY CLOSE",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.ExtraBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=8.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0184|0.8285",["FW_M100"]=886,["FW_Owned"]=true,["FW_Text0"]="ENTITY VERY CLOSE",["FW_TextMine"]=8,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.620139,["FigmaBaseF"]=0.7727,["FigmaBaseY"]=17.01,["FigmaFontSize"]=18,["FigmaInk"]="1.3,4.1,190.4,13.1",["FigmaInkC"]=0.3503,["FigmaNodeId"]="313:129",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=193},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Seconds",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.115385,0,0.25,0},["Position"]={0.916667,0,0.498328,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=260,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="12 s",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.8203",["FW_M100"]=184,["FW_Owned"]=true,["FW_Text0"]="12 s",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="1.2,3.9,31.6,10.2",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:130",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=34},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="StaminaBar",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.166667,0,0.024074,0},["Position"]={0.5,0,0.949074,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=262,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:131"},["Children"]={{["Name"]="Track",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.230769,0},["Position"]={0.5,0,0.884615,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=264,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={38,49,52},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:132"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Fill",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.625,0,1,0},["Position"]={0.3125,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=266,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:133"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Winded",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.3125,0,0.692308,0},["Position"]={0.84375,0,0.341523,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=268,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="WINDED",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,112,95},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Right",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.9453",["FW_M100"]=276,["FW_Owned"]=true,["FW_Text0"]="WINDED",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.346154,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="49.7,4,49.7,10",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:134",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=51},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="NoiseMarker",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.125,0,0.022222,0},["Position"]={0.5,0,0.911111,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=270,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:135"},["Children"]={{["Name"]="Soft",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=272,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,255,255},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:136"},["Children"]={{["Name"]="UIGradient",["ClassName"]="UIGradient",["Rotation"]=0,["Offset"]={0,0},["Enabled"]=true,["ColorKeypoints"]={{0,5,9,11},{1,5,9,11}},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Dot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.025,0,0.25,0},["Position"]={0.045833,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=274,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={68,221,196},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:137"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.883333,0,0.666667,0},["Position"]={0.525,0,0.558795,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=276,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="INVISIBLE TO MONSTERS \u{B7} 8 s",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0138|0.9124",["FW_M100"]=1242,["FW_Owned"]=true,["FW_Text0"]="INVISIBLE TO MONSTERS \u{B7} 8 s",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.533333,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="1.1,4.4,192.8,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:138",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=195},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="FeedRow",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.291667,0,0.037037,0},["Position"]={0.5,0,0.087037,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=278,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:139"},["Children"]={{["Name"]="Soft",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=280,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,255,255},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:140"},["Children"]={{["Name"]="UIGradient",["ClassName"]="UIGradient",["Rotation"]=0,["Offset"]={0,0},["Enabled"]=true,["ColorKeypoints"]={{0,5,9,11},{1,5,9,11}},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Bar",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.007143,0,0.7,0},["Position"]={0.017857,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=282,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={68,221,196},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:141"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Dot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.014286,0,0.2,0},["Position"]={0.017857,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=284,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={232,160,36},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:142"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Initial",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.05,0,0.7,0},["Position"]={0.064286,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=286,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:143"},["Children"]={{["Name"]="Ring",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=288,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={22,29,32},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:144"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.071429,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}}}},{["Name"]="Letter",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.607143,0},["Position"]={0.5,0,0.57918,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=290,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="O",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.ExtraBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.4 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0138|0.0891",["FW_M100"]=70,["FW_Owned"]=true,["FW_Text0"]="O",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.539286,["FigmaBaseF"]=0.8235,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="8.6,4,10.9,10.2",["FigmaInkC"]=0.3499,["FigmaNodeId"]="313:145",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=12},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Words",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.871429,0,0.5,0},["Position"]={0.542857,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=292,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:146"},["Children"]={{["Name"]="Who",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.409836,0,1,0},["Position"]={0.204918,0,0.549327,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=294,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Alexandra",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.ExtraBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.4 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0161|0.0880",["FW_M100"]=447,["FW_Owned"]=true,["FW_Text0"]="Alexandra",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.505,["FigmaBaseF"]=0.8,["FigmaBaseY"]=16,["FigmaFontSize"]=16,["FigmaInk"]="-0.2,4.1,85.7,12",["FigmaInkC"]=0.3667,["FigmaNodeId"]="313:147",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=87},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Detail",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.569672,0,1,0},["Position"]={0.715164,0,0.546827,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=296,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="loaded a reel \u{B7} 1/3",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.4 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0161|0.0879",["FW_M100"]=732,["FW_Owned"]=true,["FW_Text0"]="loaded a reel \u{B7} 1/3",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5025,["FigmaBaseF"]=0.8,["FigmaBaseY"]=16,["FigmaFontSize"]=16,["FigmaInk"]="1.3,2.5,138.9,15.1",["FigmaInkC"]=0.3711,["FigmaNodeId"]="313:148",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=141},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}},{["Name"]="Caption",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.25,0,0.062963,0},["Position"]={0.5,0,0.846296,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=298,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:149"},["Children"]={{["Name"]="Soft",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=300,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,255,255},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:150"},["Children"]={{["Name"]="UIGradient",["ClassName"]="UIGradient",["Rotation"]=0,["Offset"]={0,0},["Enabled"]=true,["ColorKeypoints"]={{0,5,9,11},{1,5,9,11}},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1765,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Speaker",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.933333,0,0.264706,0},["Position"]={0.5,0,0.277641,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=302,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="USHER",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={75,180,176},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.8323",["FW_M100"]=230,["FW_Owned"]=true,["FW_Text0"]="USHER",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.279412,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="203.8,3.9,41,10.2",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:151",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=43},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Said",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.933333,0,0.397059,0},["Position"]={0.5,0,0.663898,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=304,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Shhh...",["TextScaled"]=false,["TextSize"]=10,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=10.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0230|0.8566",["FW_M100"]=283,["FW_Owned"]=true,["FW_Text0"]="Shhh...",["FW_TextMine"]=10,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.661029,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=21,["FigmaFontSize"]=22,["FigmaInk"]="187.2,4.7,73.5,16.5",["FigmaInkC"]=0.3661,["FigmaNodeId"]="313:152",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=76},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="PromptPlate",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.15625,0,0.059259,0},["Position"]={0.5,0,0.574074,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=306,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:153"},["Children"]={{["Name"]="Plate",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=308,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:154"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1875,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.03125,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}}}},{["Name"]="RingSlot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.16,0,0.75,0},["Position"]={0.106667,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=310,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:155"}},{["Name"]="KeyChip",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.133333,0,0.625,0},["Position"]={0.106667,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=312,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:156"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.05,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="GlyphSlot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.7,0,0.7,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=314,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:157"}},{["Name"]="Key",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.503702,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=316,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="E",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=8.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0184|0.5742",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="E",["FW_TextMine"]=8,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.8095,["FigmaBaseY"]=26,["FigmaFontSize"]=16,["FigmaInk"]="16.3,14.6,7.7,11.4",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:158",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=10},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="ObjectLine",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.733333,0,0.28125,0},["Position"]={0.58,0,0.326244,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=318,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="MAIN BREAKER",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.5638",["FW_M100"]=552,["FW_Owned"]=true,["FW_Text0"]="MAIN BREAKER",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.328125,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="0.9,4,99.8,10",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:159",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=101},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Reason",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.733333,0,0.28125,0},["Position"]={0.58,0,0.326244,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=320,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="NEEDS A FUSE",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={232,160,36},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.5638",["FW_M100"]=552,["FW_Owned"]=true,["FW_Text0"]="NEEDS A FUSE",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.328125,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="0.8,3.9,99.4,10.2",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:160",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=101},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="ActionLine",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.733333,0,0.34375,0},["Position"]={0.58,0,0.640719,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=322,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="HIDE UNDER TABLE",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.ExtraBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=8.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0184|0.5824",["FW_M100"]=870,["FW_Owned"]=true,["FW_Text0"]="HIDE UNDER TABLE",["FW_TextMine"]=8,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.638281,["FigmaBaseF"]=0.7727,["FigmaBaseY"]=17,["FigmaFontSize"]=18,["FigmaInk"]="1.3,4.4,186.9,12.9",["FigmaInkC"]=0.3429,["FigmaNodeId"]="313:161",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=189},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="LeaveChip",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.020833,0,0.037037,0},["Position"]={0.276563,0,0.090741,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=324,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:162"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.05,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Door",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.7,0,0.7,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=326,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:163"},["Children"]={{["Name"]="Leaf",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.5,0,0.785714,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=328,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:164"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1429,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={242,235,219},["Thickness"]=1.00651,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeMine"]=1.00651,["FigmaStrokeW"]=2.5}}}},{["Name"]="Knob",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.107143,0,0.107143,0},["Position"]={0.625,0,0.517857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=330,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:165"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="LeaveChipWide",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.140625,0,0.037037,0},["Position"]={0.336458,0,0.148148,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=332,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:166"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.05,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="HoldFill",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.603704,0,0.9,0},["Position"]={0.309259,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=334,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={68,221,196},["BackgroundTransparency"]=0.78,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:167"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2778,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Door",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.103704,0,0.7,0},["Position"]={0.096296,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=336,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:168"},["Children"]={{["Name"]="Leaf",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.5,0,0.785714,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=338,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:169"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1429,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={242,235,219},["Thickness"]=1.00651,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeMine"]=1.00651,["FigmaStrokeW"]=2.5}}}},{["Name"]="Knob",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.107143,0,0.107143,0},["Position"]={0.625,0,0.517857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=340,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:170"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Hold",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.155556,0,0.4,0},["Position"]={0.255556,0,0.526676,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=342,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="HOLD",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.ExtraBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0138|0.1491",["FW_M100"]=256,["FW_Owned"]=true,["FW_Text0"]="HOLD",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.51125,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=13,["FigmaInk"]="0.9,3.7,38.8,9.5",["FigmaInkC"]=0.3498,["FigmaNodeId"]="313:171",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=41},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="KeyChip",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.107407,0,0.7,0},["Position"]={0.412963,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=344,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={22,29,32},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:172"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2143,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.071429,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="GlyphSlot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.689655,0,0.714286,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=346,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:173"}},{["Name"]="Key",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.4957,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=348,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="L",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.1480",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="L",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=19,["FigmaFontSize"]=14,["FigmaInk"]="11.3,9,6.6,10",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:174",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=9},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.481481,0,0.4,0},["Position"]={0.733333,0,0.526676,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=350,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="\u{B7} BACK TO LOBBY",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.ExtraBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0138|0.1491",["FW_M100"]=775,["FW_Owned"]=true,["FW_Text0"]="\u{B7} BACK TO LOBBY",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.51125,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=13,["FigmaInk"]="0.6,3.7,121.1,9.5",["FigmaInkC"]=0.3498,["FigmaNodeId"]="313:175",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=122},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="HoldHint",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1.555556,0,0.5,0},["Position"]={0.777778,0,1.607164,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=352,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Leaving ends your run. The others keep playing.",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.4 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0161|0.1892",["FW_M100"]=2047,["FW_Owned"]=true,["FW_Text0"]="Leaving ends your run. The others keep playing.",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=1.585,["FigmaBaseF"]=0.8,["FigmaBaseY"]=16,["FigmaFontSize"]=16,["FigmaInk"]="1.5,3.6,392.2,15.6",["FigmaInkC"]=0.2856,["FigmaNodeId"]="313:176",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=395},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="RoundExitNotice",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.125,0,0.018519,0},["Position"]={0.328646,0,0.231481,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=354,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:177"},["Children"]={{["Name"]="Notice",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.9,0},["Position"]={0.5,0,0.493979,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=356,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="NO ANSWER \u{B7} HOLD AGAIN",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0161|0.2314",["FW_M100"]=1012,["FW_Owned"]=true,["FW_Text0"]="NO ANSWER \u{B7} HOLD AGAIN",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="0.8,3.9,183.2,10.2",["FigmaInkC"]=0.3555,["FigmaNodeId"]="313:178",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=185},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="RoundExitCard",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.197917,0,0.133333,0},["Position"]={0.5,0,0.344444,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=358,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={22,29,32},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:179"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1042,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.013889,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Title",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.894737,0,0.138889,0},["Position"]={0.5,0,0.211153,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=360,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="RETURN TO THE LOBBY?",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=8.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0184|0.3059",["FW_M100"]=1096,["FW_Owned"]=true,["FW_Text0"]="RETURN TO THE LOBBY?",["FW_TextMine"]=8,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.210069,["FigmaBaseF"]=0.8,["FigmaBaseY"]=16,["FigmaFontSize"]=16.5,["FigmaInk"]="0.9,4.2,216.6,12.1",["FigmaInkC"]=0.3499,["FigmaNodeId"]="313:180",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=219},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Body",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.894737,0,0.208333,0},["Position"]={0.5,0,0.438458,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=362,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Your run ends here. The others keep playing.",["TextScaled"]=false,["TextSize"]=5,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Top",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.9 px (L=5.0 baseF=0.794 align=Enum.TextYAlignment.Top)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0115|0.3362",["FW_M100"]=1910,["FW_Owned"]=true,["FW_Text0"]="Your run ends here. The others keep playing.",["FW_TextMine"]=5,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.423611,["FigmaBaseF"]=0.8,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="-0.1,2.7,275.4,11.7",["FigmaInkC"]=0.2858,["FigmaNodeId"]="313:181",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=276},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="BackToLobby",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.473684,0,0.291667,0},["Position"]={0.289474,0,0.715278,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=364,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,112,95},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:182"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2143,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.497299,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=366,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="BACK TO LOBBY",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0161|0.3730",["FW_M100"]=734,["FW_Owned"]=true,["FW_Text0"]="BACK TO LOBBY",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=26,["FigmaFontSize"]=15,["FigmaInk"]="24.4,15.3,132.4,11",["FigmaInkC"]=0.35,["FigmaNodeId"]="313:183",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=133},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Stay",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.397368,0,0.291667,0},["Position"]={0.748684,0,0.715278,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=368,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={29,38,42},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="313:184"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2143,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.035714,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=1.5}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.497299,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=370,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="STAY",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.ExtraBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0161|0.3730",["FW_M100"]=221,["FW_Owned"]=true,["FW_Text0"]="STAY",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7778,["FigmaBaseY"]=26,["FigmaFontSize"]=15,["FigmaInk"]="55.8,15.3,39.9,10.9",["FigmaInkC"]=0.35,["FigmaNodeId"]="313:185",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=40},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}},{["Name"]="UIAspectRatioConstraint",["ClassName"]="UIAspectRatioConstraint",["AspectRatio"]=1.777778,["AspectType"]="Enum.AspectType.FitWithinMaxSize",["DominantAxis"]="Enum.DominantAxis.Width",["Attributes"]={["FW_Owned"]=true}}}},["HUD_Touch"]={["Name"]="HUD_Touch",["ClassName"]="CanvasGroup",["Visible"]=true,["Size"]={0.439583,0,0.361111,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=1,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={29,38,42},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=false,["Attributes"]={["BB_DesignH"]=390,["BB_DesignW"]=844,["BB_TextFactor"]=1.16,["FW_Owned"]=true,["FigmaNodeId"]="314:2",["HudTemplateSource"]="Imports.Framewisp_Live_HUD_Touch.HUD_Touch"},["Children"]={{["Name"]="LeaveChipTouch",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.052133,0,0.112821,0},["Position"]={0.095972,0,0.220513,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=4,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:12"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2727,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.045455,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Door",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.636364,0,0.636364,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=6,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:16"},["Children"]={{["Name"]="Outline",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.5,0,0.785714,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=8,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:17"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.1429,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={242,235,219},["Thickness"]=1.00651,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeMine"]=1.00651,["FigmaStrokeW"]=2.5}}}},{["Name"]="Knob",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.107143,0,0.107143,0},["Position"]={0.625,0,0.517857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=10,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:18"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="RingSlot",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=12,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:19"}}}},{["Name"]="FeedRowTouch",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.424171,0,0.082051,0},["Position"]={0.348341,0,0.220513,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=14,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:20"},["Children"]={{["Name"]="Soft",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=16,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,255,255},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:21"},["Children"]={{["Name"]="UIGradient",["ClassName"]="UIGradient",["Rotation"]=0,["Offset"]={0,0},["Enabled"]=true,["ColorKeypoints"]={{0,5,9,11},{1,5,9,11}},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3125,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Bar",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.00838,0,0.6875,0},["Position"]={0.02095,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=18,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={68,221,196},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:22"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.6667,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Dot",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.01676,0,0.1875,0},["Position"]={0.022346,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=20,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={232,160,36},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:23"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Initial",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.061453,0,0.6875,0},["Position"]={0.081006,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=22,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:24"},["Children"]={{["Name"]="Ring",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=24,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={29,38,42},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:25"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.068182,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=1.5}}}},{["Name"]="Letter",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.482592,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=26,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="O",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.ExtraBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0382|0.2195",["FW_M100"]=70,["FW_Owned"]=true,["FW_Text0"]="O",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.8,["FigmaBaseY"]=15,["FigmaFontSize"]=12,["FigmaInk"]="6.3,6.4,9.3,8.7",["FigmaInkC"]=0.3496,["FigmaNodeId"]="314:26",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=11},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Words",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.843575,0,1,0},["Position"]={0.555866,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=28,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:27"},["Children"]={{["Name"]="Who",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.172185,0,0.5,0},["Position"]={0.086093,0,0.528345,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=30,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Oskar",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.ExtraBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0382|0.2228",["FW_M100"]=260,["FW_Owned"]=true,["FW_Text0"]="Oskar",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.509375,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12.99,["FigmaFontSize"]=13,["FigmaInk"]="0.4,3.4,40,9.8",["FigmaInkC"]=0.3636,["FigmaNodeId"]="314:28",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=41},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Detail",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.807947,0,0.5,0},["Position"]={0.596026,0,0.525845,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=32,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="loaded a reel \u{B7} 1/3",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0382|0.2226",["FW_M100"]=732,["FW_Owned"]=true,["FW_Text0"]="loaded a reel \u{B7} 1/3",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.50625,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13.01,["FigmaFontSize"]=13,["FigmaInk"]="1.1,2.1,112.9,12.2",["FigmaInkC"]=0.3714,["FigmaNodeId"]="314:29",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=115},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}},{["Name"]="DetectorLine",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.424171,0,0.061538,0},["Position"]={0.348341,0,0.312821,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=34,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:30"},["Children"]={{["Name"]="Soft",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=36,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,255,255},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:31"},["Children"]={{["Name"]="UIGradient",["ClassName"]="UIGradient",["Rotation"]=0,["Offset"]={0,0},["Enabled"]=true,["ColorKeypoints"]={{0,5,9,11},{1,5,9,11}},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3333,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Bars",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.044693,0,0.666667,0},["Position"]={0.050279,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=38,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:32"},["Children"]={{["Name"]="Bar1",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.25,0,0.375,0},["Position"]={0.125,0,0.8125,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=40,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,112,95},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:33"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Bar2",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.25,0,0.6875,0},["Position"]={0.5,0,0.65625,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=42,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,112,95},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:34"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Bar3",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.25,0,1,0},["Position"]={0.875,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=44,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,112,95},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:35"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Line",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.882682,0,0.666667,0},["Position"]={0.536313,0,0.554628,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=46,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="SCAN \u{B7} HIGH \u{B7} ENTITY VERY CLOSE",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,112,95},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.3162",["FW_M100"]=1426,["FW_Owned"]=true,["FW_Text0"]="SCAN \u{B7} HIGH \u{B7} ENTITY VERY CLOSE",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.529167,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="0.5,4.3,222.3,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:36",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=224},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="CaptionTouch",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.424171,0,0.112821,0},["Position"]={0.348341,0,0.420513,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=48,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:37"},["Children"]={{["Name"]="Soft",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=50,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,255,255},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:38"},["Children"]={{["Name"]="UIGradient",["ClassName"]="UIGradient",["Rotation"]=0,["Offset"]={0,0},["Enabled"]=true,["ColorKeypoints"]={{0,5,9,11},{1,5,9,11}},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2273,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Speaker",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.932961,0,0.340909,0},["Position"]={0.5,0,0.293433,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=52,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="USHER",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={75,180,176},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.0 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.3972",["FW_M100"]=230,["FW_Owned"]=true,["FW_Text0"]="USHER",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.290909,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="0.7,3.4,35.1,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:39",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=37},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Said",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.932961,0,0.409091,0},["Position"]={0.5,0,0.692433,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=54,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Shhh...",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0382|0.4422",["FW_M100"]=283,["FW_Owned"]=true,["FW_Text0"]="Shhh...",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.678409,["FigmaBaseF"]=0.8235,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="0.5,3.6,46.8,10.5",["FigmaInkC"]=0.3661,["FigmaNodeId"]="314:40",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=48},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="PromptPlateTouch",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.308057,0,0.14359,0},["Position"]={0.290284,0,0.584615,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=56,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:41"},["Children"]={{["Name"]="Plate",["ClassName"]="TextButton",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=58,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:47"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2143,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.035714,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}}}},{["Name"]="ObjectLine",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.876923,0,0.285714,0},["Position"]={0.5,0,0.326983,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=60,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="PROJECTOR",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.5598",["FW_M100"]=414,["FW_Owned"]=true,["FW_Text0"]="PROJECTOR",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.316071,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="0.9,4.3,63.8,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:48",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=65},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="ActionLine",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.876923,0,0.357143,0},["Position"]={0.5,0,0.665831,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=62,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="THREAD REEL",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.ExtraBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.4 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0446|0.6084",["FW_M100"]=618,["FW_Owned"]=true,["FW_Text0"]="THREAD REEL",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.65,["FigmaBaseF"]=0.8,["FigmaBaseY"]=16,["FigmaFontSize"]=16,["FigmaInk"]="0.1,4.8,119,11.2",["FigmaInkC"]=0.3501,["FigmaNodeId"]="314:49",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=120},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Reason",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.876923,0,0.285714,0},["Position"]={0.5,0,0.328769,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=64,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="NEEDS A FUSE",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={232,160,36},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.5600",["FW_M100"]=552,["FW_Owned"]=true,["FW_Text0"]="NEEDS A FUSE",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.317857,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="0.7,4.4,85.2,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:50",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=87},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="HoldBar",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.923077,0,0.053571,0},["Position"]={0.5,0,0.9375,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=66,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:51"},["Children"]={{["Name"]="Track",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=68,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={38,49,52},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:52"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3333,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Fill",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.5,0,1,0},["Position"]={0.25,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=70,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={68,221,196},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:53"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3333,0},["Attributes"]={["FW_Owned"]=true}}}}}}}}}},{["Name"]="ObjectivePill",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.28436,0,0.351282,0},["Position"]={0.780806,0,0.35,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=72,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,255,255},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:54"},["Children"]={{["Name"]="UIGradient",["ClassName"]="UIGradient",["Rotation"]=90,["Offset"]={0,0},["Enabled"]=true,["ColorKeypoints"]={{0,5,9,11},{1,5,9,11}},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.073,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Bar",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.291971,0},["Position"]={0.5,0,0.145985,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=74,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:55"},["Children"]={{["Name"]="Eyebrow",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.916667,0,0.4,0},["Position"]={0.5,0,0.285277,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=76,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="LEVEL 4 \u{B7} THE LAST SHOW",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={255,230,0},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.2036",["FW_M100"]=1058,["FW_Owned"]=true,["FW_Text0"]="LEVEL 4 \u{B7} THE LAST SHOW",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.27,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="0.9,4.4,164.7,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:56",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=166},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Title",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.708333,0,0.4,0},["Position"]={0.395833,0,0.678688,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=78,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="LOAD THE PROJECTORS",["TextScaled"]=false,["TextSize"]=5,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=5.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0318|0.2440",["FW_M100"]=1077,["FW_Owned"]=true,["FW_Text0"]="LOAD THE PROJECTORS",["FW_TextMine"]=5,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.67,["FigmaBaseF"]=0.8,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="0.7,3.4,155.1,8.8",["FigmaInkC"]=0.3503,["FigmaNodeId"]="314:57",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=156},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Count",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.183333,0,0.45,0},["Position"]={0.866667,0,0.70132,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=80,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="1/3",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Right",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=6.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0382|0.2463",["FW_M100"]=117,["FW_Owned"]=true,["FW_Text0"]="1/3",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.685,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=14,["FigmaFontSize"]=14,["FigmaInk"]="26.4,3.9,17,11",["FigmaInkC"]=0.3298,["FigmaNodeId"]="314:58",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=19},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Underbar",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.108333,0,0.075,0},["Position"]={0.095833,0,0.9625,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=82,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,230,0},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:59"}}}},{["Name"]="Progress",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.175182,0},["Position"]={0.5,0,0.379562,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=84,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:60"},["Children"]={{["Name"]="CountTag",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.916667,0,0.666667,0},["Position"]={0.5,0,0.475461,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=86,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="REELS LOADED",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.3062",["FW_M100"]=552,["FW_Owned"]=true,["FW_Text0"]="REELS LOADED",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.45,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="0.8,4.4,85.2,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:61",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=87},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Track",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.916667,0,0.083333,0},["Position"]={0.5,0,0.875,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=88,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={38,49,52},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:62"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="Fill",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.4,0,1,0},["Position"]={0.2,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=90,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={255,230,0},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:63"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Guide1",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.124088,0},["Position"]={0.5,0,0.529197,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=92,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:64"},["Children"]={{["Name"]="Line",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.916667,0,0.882353,0},["Position"]={0.5,0,0.623384,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=94,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="You carry 2 reels.",["TextScaled"]=false,["TextSize"]=5,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=5.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0318|0.3656",["FW_M100"]=717,["FW_Owned"]=true,["FW_Text0"]="You carry 2 reels.",["FW_TextMine"]=5,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.573529,["FigmaBaseF"]=0.8,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="-0.1,3.1,103.3,11.3",["FigmaInkC"]=0.2708,["FigmaNodeId"]="314:65",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=104},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Guide2",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.124088,0},["Position"]={0.5,0,0.653285,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=96,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:66"},["Children"]={{["Name"]="Line",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.916667,0,0.882353,0},["Position"]={0.5,0,0.602796,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=98,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Reels: Cafe, Arcade",["TextScaled"]=false,["TextSize"]=5,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=5.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0318|0.4083",["FW_M100"]=813,["FW_Owned"]=true,["FW_Text0"]="Reels: Cafe, Arcade",["FW_TextMine"]=5,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.552941,["FigmaBaseF"]=0.8,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="1.1,3,115.8,10.8",["FigmaInkC"]=0.2988,["FigmaNodeId"]="314:67",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=118},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="StatusRow",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.138686,0},["Position"]={0.5,0,0.784672,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=100,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:68"},["Children"]={{["Name"]="Bar",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.008333,0,0.789474,0},["Position"]={0.045833,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=102,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={232,160,36},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:69"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.883333,0,0.789474,0},["Position"]={0.516667,0,0.536712,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=104,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="Main breaker: fuse 42 s",["TextScaled"]=false,["TextSize"]=5,["TextColor3"]={232,160,36},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Left",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/Montserrat.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.SemiBold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.3 px (L=5.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7941,["FW_EDbg"]="0.0318|0.4518",["FW_M100"]=980,["FW_Owned"]=true,["FW_Text0"]="Main breaker: fuse 42 s",["FW_TextMine"]=5,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.492105,["FigmaBaseF"]=0.8,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="1.1,2.7,140.3,9.3",["FigmaInkC"]=0.3828,["FigmaNodeId"]="314:70",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=142},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Compass",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,0.145985,0},["Position"]={0.5,0,0.927007,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=106,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:71"},["Children"]={{["Name"]="Ticks",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.516667,0,0.3,0},["Position"]={0.3,0,0.75,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=108,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:72"},["Children"]={{["Name"]="Tick1",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.016129,0,1,0},["Position"]={0.008065,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=110,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:73"}},{["Name"]="Tick2",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.016129,0,1,0},["Position"]={0.131048,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=112,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:74"}},{["Name"]="Tick3",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.016129,0,1,0},["Position"]={0.254032,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=114,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:75"}},{["Name"]="Tick4",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.016129,0,1,0},["Position"]={0.377016,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=116,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:76"}},{["Name"]="Tick5",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.016129,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=118,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:77"}},{["Name"]="Tick6",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.016129,0,1,0},["Position"]={0.622984,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=120,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:78"}},{["Name"]="Tick7",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.016129,0,1,0},["Position"]={0.745968,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=122,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:79"}},{["Name"]="Tick8",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.016129,0,1,0},["Position"]={0.868952,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=124,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:80"}},{["Name"]="Tick9",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.016129,0,1,0},["Position"]={0.991935,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=126,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={167,184,174},["BackgroundTransparency"]=0.4,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:81"}}}},{["Name"]="Baseline",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.516667,0,0.1,0},["Position"]={0.3,0,0.95,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=128,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={38,49,52},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:82"}},{["Name"]="Centre",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.008333,0,0.55,0},["Position"]={0.3,0,0.725,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=130,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:83"}},{["Name"]="Chevron",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.05,0,0.7,0},["Position"]={0.391667,0,0.343979,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=132,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="v",["TextScaled"]=false,["TextSize"]=7,["TextColor3"]={255,230,0},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.0 px (L=7.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0446|0.4920",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="v",["FW_TextMine"]=7,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.35,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="2.8,5.7,6.4,6.3",["FigmaInkC"]=0.2643,["FigmaNodeId"]="314:84",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=8},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Readout",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={0.366667,0,0.8,0},["Position"]={0.775,0,0.565554,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=134,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="CALIBRATING",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={167,184,174},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Right",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.5034",["FW_M100"]=506,["FW_Owned"]=true,["FW_Text0"]="CALIBRATING",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.535,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="9.2,4.3,78.2,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:85",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=80},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}},{["Name"]="KitFan",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.203791,0,0.133333,0},["Position"]={0.548578,0,0.694872,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=136,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:86"},["Children"]={{["Name"]="Items",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=138,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="UIListLayout",["ClassName"]="UIListLayout",["FillDirection"]="Enum.FillDirection.Horizontal",["Padding"]={0.046512,0},["SortOrder"]="Enum.SortOrder.LayoutOrder",["HorizontalAlignment"]="Enum.HorizontalAlignment.Left",["VerticalAlignment"]="Enum.VerticalAlignment.Top",["Wraps"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaGap"]=8}},{["Name"]="Fan_Potion",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.302326,0,1,0},["Position"]={0,0,0,0},["AnchorPoint"]={0,0},["ZIndex"]=140,["LayoutOrder"]=1,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:92"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2308,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.038462,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.269231,0},["Position"]={0.5,0,0.777136,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=142,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="POTION",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.7318",["FW_M100"]=276,["FW_Owned"]=true,["FW_Text0"]="POTION",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.765385,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="5.3,3.4,41.6,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:94",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=44},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Icon",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.423077,0,0.423077,0},["Position"]={0.5,0,0.326923,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=144,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:102"},["Children"]={{["Name"]="Body",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.571429,0,0.571429,0},["Position"]={0.500003,0,0.642857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=146,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:103"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Neck",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.214286,0,0.25,0},["Position"]={0.50001,0,0.303572,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=148,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:104"}},{["Name"]="Cap",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.357143,0,0.107143,0},["Position"]={0.499994,0,0.125,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=150,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:105"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3333,0},["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Badge",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.346154,0,0.346154,0},["Position"]={0.826923,0,0.173077,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=152,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={29,38,42},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:106"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.055556,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=1}},{["Name"]="Count",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.480711,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=154,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="2",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.1 px (L=6.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0382|0.6504",["FW_M100"]=44,["FW_Owned"]=true,["FW_Text0"]="2",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7857,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="6.3,4.3,5.3,8.7",["FigmaInkC"]=0.3607,["FigmaNodeId"]="314:107",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=7},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Cooldown",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.423077,0},["Position"]={0.5,0,0.321226,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=156,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="12",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=8.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0510|0.6710",["FW_M100"]=88,["FW_Owned"]=true,["FW_Text0"]="12",["FW_TextMine"]=8,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.317308,["FigmaBaseF"]=0.8095,["FigmaBaseY"]=17,["FigmaFontSize"]=18,["FigmaInk"]="18.2,4,16.3,13",["FigmaInkC"]=0.3607,["FigmaNodeId"]="314:108",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=19},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Fan_Marker",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.302326,0,1,0},["Position"]={0,0,0,0},["AnchorPoint"]={0,0},["ZIndex"]=158,["LayoutOrder"]=2,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:114"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2308,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.038462,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.269231,0},["Position"]={0.5,0,0.776174,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=160,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="MARKER",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.7317",["FW_M100"]=276,["FW_Owned"]=true,["FW_Text0"]="MARKER",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.764423,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="5.1,3.5,42.3,8.5",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:116",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=44},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Icon",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.423077,0,0.423077,0},["Position"]={0.5,0,0.326923,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=162,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:122"},["Children"]={{["Name"]="Pole",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.107143,0,0.785714,0},["Position"]={0.26786,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=164,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:123"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.3333,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Flag",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.409091,0,0.318182,0},["Position"]={0.561679,0,0.266234,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=166,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:125"}}}},{["Name"]="Badge",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.346154,0,0.346154,0},["Position"]={0.826923,0,0.173077,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=168,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={29,38,42},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:126"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.055556,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=1}},{["Name"]="Count",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.480711,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=170,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="2",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.1 px (L=6.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0382|0.6504",["FW_M100"]=44,["FW_Owned"]=true,["FW_Text0"]="2",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7857,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="6.3,4.3,5.3,8.7",["FigmaInkC"]=0.3607,["FigmaNodeId"]="314:127",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=7},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Cooldown",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.423077,0},["Position"]={0.5,0,0.321226,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=172,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="12",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=8.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0510|0.6710",["FW_M100"]=88,["FW_Owned"]=true,["FW_Text0"]="12",["FW_TextMine"]=8,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.317308,["FigmaBaseF"]=0.8095,["FigmaBaseY"]=17,["FigmaFontSize"]=18,["FigmaInk"]="18.2,4,16.3,13",["FigmaInkC"]=0.3607,["FigmaNodeId"]="314:128",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=19},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Fan_Scan",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.302326,0,1,0},["Position"]={0,0,0,0},["AnchorPoint"]={0,0},["ZIndex"]=174,["LayoutOrder"]=3,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:136"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2308,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.038462,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.269231,0},["Position"]={0.5,0,0.775213,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=176,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="SCAN",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.7316",["FW_M100"]=184,["FW_Owned"]=true,["FW_Text0"]="SCAN",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.763462,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="12.1,3.3,27.5,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:139",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=29},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Icon",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.423077,0,0.423077,0},["Position"]={0.5,0,0.326923,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=178,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:147"},["Children"]={{["Name"]="Items",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.678636,0,0.714091,0},["Position"]={0.517955,0,0.499773,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=180,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="UIListLayout",["ClassName"]="UIListLayout",["FillDirection"]="Enum.FillDirection.Horizontal",["Padding"]={0.105157,0},["SortOrder"]="Enum.SortOrder.LayoutOrder",["HorizontalAlignment"]="Enum.HorizontalAlignment.Left",["VerticalAlignment"]="Enum.VerticalAlignment.Bottom",["Wraps"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaGap"]=1.57}},{["Name"]="Step1",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.263133,0,0.400109,0},["Position"]={0,0,0,0},["AnchorPoint"]={0,0},["ZIndex"]=182,["LayoutOrder"]=1,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:148"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Step2",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.263133,0,0.700191,0},["Position"]={0,0,0,0},["AnchorPoint"]={0,0},["ZIndex"]=184,["LayoutOrder"]=2,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:149"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Step3",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.263133,0,1.000273,0},["Position"]={0,0,0,0},["AnchorPoint"]={0,0},["ZIndex"]=186,["LayoutOrder"]=3,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:150"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2,0},["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Badge",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.346154,0,0.346154,0},["Position"]={0.826923,0,0.173077,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=188,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={29,38,42},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:151"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.5,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.055556,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Contextual",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=1}},{["Name"]="Count",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.480711,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=190,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="2",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok -0.1 px (L=6.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0382|0.6504",["FW_M100"]=44,["FW_Owned"]=true,["FW_Text0"]="2",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.5,["FigmaBaseF"]=0.7857,["FigmaBaseY"]=13,["FigmaFontSize"]=12,["FigmaInk"]="6.3,4.3,5.3,8.7",["FigmaInkC"]=0.3607,["FigmaNodeId"]="314:152",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=7},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Cooldown",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.423077,0},["Position"]={0.5,0,0.321226,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=192,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="12",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=8.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0510|0.6710",["FW_M100"]=88,["FW_Owned"]=true,["FW_Text0"]="12",["FW_TextMine"]=8,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.317308,["FigmaBaseF"]=0.8095,["FigmaBaseY"]=17,["FigmaFontSize"]=18,["FigmaInk"]="18.2,4,16.3,13",["FigmaInkC"]=0.3607,["FigmaNodeId"]="314:153",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=19},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}}}},{["Name"]="TouchCluster",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.274882,0,0.287179,0},["Position"]={0.792654,0,0.771795,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=194,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:154"},["Children"]={{["Name"]="FlashlightPower",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.224138,0,0.464286,0},["Position"]={0.112069,0,0.767857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=196,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:168"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2308,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.038462,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Seg1",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.115385,0,0.307692,0},["Position"]={0.192308,0,0.326923,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=198,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:169"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Seg2",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.115385,0,0.307692,0},["Position"]={0.346154,0,0.326923,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=200,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:170"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Seg3",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.115385,0,0.307692,0},["Position"]={0.5,0,0.326923,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=202,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:171"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Seg4",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.115385,0,0.307692,0},["Position"]={0.653846,0,0.326923,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=204,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:172"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Seg5",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.115385,0,0.307692,0},["Position"]={0.807692,0,0.326923,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=206,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0.85,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:173"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.25,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.269231,0},["Position"]={0.5,0,0.777136,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=208,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="LIGHT",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.8857",["FW_M100"]=230,["FW_Owned"]=true,["FW_Text0"]="LIGHT",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.765385,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="8.9,3.4,35,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:174",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=37},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Cell_Sneak",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.224138,0,0.464286,0},["Position"]={0.37069,0,0.767857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=210,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:180"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2308,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.038462,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Glyph",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.423077,0},["Position"]={0.5,0,0.331527,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=212,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="v",["TextScaled"]=false,["TextSize"]=9,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Top",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=9.0 baseF=0.794 align=Enum.TextYAlignment.Top)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0573|0.8263",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="v",["FW_TextMine"]=9,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.326923,["FigmaBaseF"]=0.7917,["FigmaBaseY"]=18,["FigmaFontSize"]=18,["FigmaInk"]="21.2,8.5,9.5,9.5",["FigmaInkC"]=0.2643,["FigmaNodeId"]="314:181",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=11},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.269231,0},["Position"]={0.5,0,0.777136,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=214,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="SNEAK",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.8857",["FW_M100"]=230,["FW_Owned"]=true,["FW_Text0"]="SNEAK",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.765385,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="8.5,3.4,35.7,8.8",["FigmaInkC"]=0.3561,["FigmaNodeId"]="314:182",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=37},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Cell_Run",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.224138,0,0.464286,0},["Position"]={0.62931,0,0.767857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=216,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:188"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2308,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.038462,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Glyph",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.423077,0},["Position"]={0.5,0,0.331527,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=218,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="\u{BB}",["TextScaled"]=false,["TextSize"]=9,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Top",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=9.0 baseF=0.794 align=Enum.TextYAlignment.Top)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0573|0.8263",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="\u{BB}",["FW_TextMine"]=9,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.326923,["FigmaBaseF"]=0.7917,["FigmaBaseY"]=18,["FigmaFontSize"]=18,["FigmaInk"]="22.6,9.9,7.4,7",["FigmaInkC"]=0.2569,["FigmaNodeId"]="314:189",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=11},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.269231,0},["Position"]={0.5,0,0.777136,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=220,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="RUN",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.8857",["FW_M100"]=138,["FW_Owned"]=true,["FW_Text0"]="RUN",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.765385,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="16,3.5,20,8.6",["FigmaInkC"]=0.3503,["FigmaNodeId"]="314:190",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=22},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="RingSlot",["ClassName"]="Frame",["Visible"]=true,["Size"]={1,0,1,0},["Position"]={0.5,0,0.5,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=222,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:191"}}}},{["Name"]="Cell_Jump",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.224138,0,0.464286,0},["Position"]={0.887931,0,0.767857,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=224,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:197"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2308,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.038462,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Glyph",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.423077,0},["Position"]={0.5,0,0.331527,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=226,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="^",["TextScaled"]=false,["TextSize"]=9,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Top",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=9.0 baseF=0.794 align=Enum.TextYAlignment.Top)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0573|0.8263",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="^",["FW_TextMine"]=9,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.326923,["FigmaBaseF"]=0.7917,["FigmaBaseY"]=18,["FigmaFontSize"]=18,["FigmaInk"]="22.5,5.2,7.4,6.8",["FigmaInkC"]=0.523,["FigmaNodeId"]="314:198",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=11},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.269231,0},["Position"]={0.5,0,0.777136,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=228,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="JUMP",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.8857",["FW_M100"]=184,["FW_Owned"]=true,["FW_Text0"]="JUMP",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.765385,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="12.2,3.5,27.8,8.6",["FigmaInkC"]=0.3503,["FigmaNodeId"]="314:199",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=29},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Cell_Glow",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.224138,0,0.464286,0},["Position"]={0.37069,0,0.232143,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=230,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaGlow"]=1,["FigmaGlowRad"]=0.231,["FigmaGlowRot"]=0,["FigmaGlowSH"]=1,["FigmaGlowSW"]=1,["FigmaNodeId"]="314:205"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2308,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.038462,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Glyph",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.423077,0},["Position"]={0.5,0,0.331527,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=232,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="*",["TextScaled"]=false,["TextSize"]=9,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Top",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=9.0 baseF=0.794 align=Enum.TextYAlignment.Top)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0573|0.6724",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="*",["FW_TextMine"]=9,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.326923,["FigmaBaseF"]=0.7917,["FigmaBaseY"]=18,["FigmaFontSize"]=18,["FigmaInk"]="21.9,5.2,9,9",["FigmaInkC"]=0.4601,["FigmaNodeId"]="314:206",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=11},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.269231,0},["Position"]={0.5,0,0.777136,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=234,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="GLOW",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.7318",["FW_M100"]=184,["FW_Owned"]=true,["FW_Text0"]="GLOW",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.765385,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="12.1,3.4,28.2,8.8",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:207",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=29},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Cell_Kit",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.224138,0,0.464286,0},["Position"]={0.62931,0,0.232143,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=236,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:213"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2308,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.038462,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Glyph",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.423077,0},["Position"]={0.5,0,0.331527,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=238,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="+",["TextScaled"]=false,["TextSize"]=9,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Top",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=9.0 baseF=0.794 align=Enum.TextYAlignment.Top)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0573|0.6724",["FW_M100"]=46,["FW_Owned"]=true,["FW_Text0"]="+",["FW_TextMine"]=9,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.326923,["FigmaBaseF"]=0.7917,["FigmaBaseY"]=18,["FigmaFontSize"]=18,["FigmaInk"]="21.5,7.4,8.8,9.3",["FigmaInkC"]=0.3299,["FigmaNodeId"]="314:214",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=11},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.269231,0},["Position"]={0.5,0,0.776174,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=240,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="KIT",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.7317",["FW_M100"]=138,["FW_Owned"]=true,["FW_Text0"]="KIT",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.764423,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="15.9,3.5,20.7,8.5",["FigmaInkC"]=0.3555,["FigmaNodeId"]="314:215",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=22},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}},{["Name"]="Cell_Shield",["ClassName"]="TextButton",["Visible"]=true,["Size"]={0.224138,0,0.464286,0},["Position"]={0.887931,0,0.232143,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=242,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={5,9,11},["BackgroundTransparency"]=0.3,["BorderSizePixel"]=0,["ClipsDescendants"]=true,["Active"]=true,["Text"]="",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={27,42,53},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/LegacyArial.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Regular"},["AutoButtonColor"]=true,["Selectable"]=true,["Attributes"]={["FW_Owned"]=true,["FigmaNodeId"]="314:221"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.2308,0},["Attributes"]={["FW_Owned"]=true}},{["Name"]="UIStroke",["ClassName"]="UIStroke",["Color"]={38,49,52},["Thickness"]=0.038462,["Transparency"]=0,["ApplyStrokeMode"]="Enum.ApplyStrokeMode.Border",["LineJoinMode"]="Enum.LineJoinMode.Round",["Enabled"]=true,["Attributes"]={["FW_Owned"]=true,["FW_StrokeScaled"]=true,["FigmaStrokeW"]=2}},{["Name"]="Label",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.269231,0},["Position"]={0.5,0,0.777136,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=244,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="SHIELD",["TextScaled"]=false,["TextSize"]=6,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoMono.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Bold"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.2 px (L=6.0 baseF=0.794 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7945,["FW_EDbg"]="0.0382|0.7318",["FW_M100"]=276,["FW_Owned"]=true,["FW_Text0"]="SHIELD",["FW_TextMine"]=6,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.765385,["FigmaBaseF"]=0.8125,["FigmaBaseY"]=12,["FigmaFontSize"]=12,["FigmaInk"]="4.9,3.4,42.2,8.8",["FigmaInkC"]=0.3561,["FigmaNodeId"]="314:223",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=44},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}},{["Name"]="Glyph",["ClassName"]="Frame",["Visible"]=true,["Size"]={0.211538,0,0.211538,0},["Position"]={0.499969,0,0.326923,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=246,["LayoutOrder"]=0,["Rotation"]=-45,["BackgroundColor3"]={242,235,219},["BackgroundTransparency"]=0,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Attributes"]={["FW_HadRotation"]=true,["FW_Owned"]=true,["FigmaNodeId"]="314:224"},["Children"]={{["Name"]="UICorner",["ClassName"]="UICorner",["CornerRadius"]={0.0909,0},["Attributes"]={["FW_Owned"]=true}}}},{["Name"]="Cooldown",["ClassName"]="TextLabel",["Visible"]=true,["Size"]={1,0,0.423077,0},["Position"]={0.5,0,0.321226,0},["AnchorPoint"]={0.5,0.5},["ZIndex"]=248,["LayoutOrder"]=0,["Rotation"]=0,["BackgroundColor3"]={163,162,165},["BackgroundTransparency"]=1,["BorderSizePixel"]=0,["ClipsDescendants"]=false,["Active"]=false,["Text"]="12",["TextScaled"]=false,["TextSize"]=8,["TextColor3"]={242,235,219},["TextTransparency"]=0,["TextWrapped"]=false,["TextXAlignment"]="Enum.TextXAlignment.Center",["TextYAlignment"]="Enum.TextYAlignment.Center",["FontFace"]={["Family"]="rbxasset://fonts/families/RobotoCondensed.json",["Style"]="Enum.FontStyle.Normal",["Weight"]="Enum.FontWeight.Heavy"},["RichText"]=false,["Attributes"]={["FW_Anchor"]="ok +0.1 px (L=8.0 baseF=0.792 align=Enum.TextYAlignment.Center)",["FW_BaseStamp"]=0.7917,["FW_EDbg"]="0.0510|0.6710",["FW_M100"]=88,["FW_Owned"]=true,["FW_Text0"]="12",["FW_TextMine"]=8,["FW_TextScaledMine"]=false,["FW_TextYS0"]=0.317308,["FigmaBaseF"]=0.8095,["FigmaBaseY"]=17,["FigmaFontSize"]=18,["FigmaInk"]="18.2,4,16.3,13",["FigmaInkC"]=0.3607,["FigmaNodeId"]="314:225",["FigmaPaints"]="f:SOLID|s:",["FigmaTextW"]=19},["Children"]={{["Name"]="FW_Scale",["ClassName"]="UIScale",["Scale"]=1,["Attributes"]={["FW_Owned"]=true},["Children"]={{["Name"]="k_text",["ClassName"]="NumberValue",["Attributes"]={["FW_Owned"]=true}}}}}}}}}},{["Name"]="UIAspectRatioConstraint",["ClassName"]="UIAspectRatioConstraint",["AspectRatio"]=2.164103,["AspectType"]="Enum.AspectType.FitWithinMaxSize",["DominantAxis"]="Enum.DominantAxis.Width",["Attributes"]={["FW_Owned"]=true}}}}}


local checks = 0
local function check(value, message)
	if not value then error("CHECK FAILED: " .. tostring(message), 2) end
	checks += 1
end
local function near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6) end

-- ---------------------------------------------------------------- signals
local function signal()
	local s = {__signal = true, entries = {}}
	function s:Connect(fn)
		local conn = {Connected = true}
		local entry = {Fn = fn, Conn = conn}
		table.insert(s.entries, entry)
		function conn:Disconnect()
			conn.Connected = false
			for index, other in ipairs(s.entries) do
				if other == entry then table.remove(s.entries, index) break end
			end
		end
		return conn
	end
	function s:Fire(...)
		for _, entry in ipairs(table.clone(s.entries)) do
			if entry.Conn.Connected then entry.Fn(...) end
		end
	end
	return s
end

-- ------------------------------------------------------------ value types
-- Color3 is memoised so `==` answers "same colour", as the engine's does.
local Color3Meta = {}
Color3Meta.__index = Color3Meta
local colorCache = {}
local Color3 = {}
function Color3.fromRGB(r, g, b)
	r, g, b = math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
	local key = r .. "," .. g .. "," .. b
	if not colorCache[key] then
		colorCache[key] = setmetatable({__kind = "Color3", Key = key, R = r / 255, G = g / 255, B = b / 255}, Color3Meta)
	end
	return colorCache[key]
end
function Color3.new(r, g, b) return Color3.fromRGB((r or 0) * 255, (g or 0) * 255, (b or 0) * 255) end
function Color3Meta:ToHex()
	return string.format("%02X%02X%02X", math.floor(self.R * 255 + 0.5), math.floor(self.G * 255 + 0.5), math.floor(self.B * 255 + 0.5))
end
Color3Meta.__tostring = function(self) return "Color3(" .. self.Key .. ")" end

local UDim = {new = function(s, o) return {__kind = "UDim", Scale = s or 0, Offset = o or 0} end}
local UDim2Meta = {}
local UDim2 = {}
function UDim2.new(sx, ox, sy, oy)
	return setmetatable({__kind = "UDim2", X = UDim.new(sx, ox), Y = UDim.new(sy, oy)}, UDim2Meta)
end
function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
UDim2Meta.__add = function(a, b)
	return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UDim2Meta.__eq = function(a, b)
	return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset
end
UDim2Meta.__tostring = function(a)
	return string.format("UDim2(%g,%g,%g,%g)", a.X.Scale, a.X.Offset, a.Y.Scale, a.Y.Offset)
end
local Vector2 = {new = function(x, y) return {__kind = "Vector2", X = x or 0, Y = y or 0} end}
Vector2.zero = Vector2.new(0, 0)
local Vector3 = {new = function(x, y, z) return {__kind = "Vector3", X = x or 0, Y = y or 0, Z = z or 0} end}
local Font = {new = function(family, weight, style) return {Family = family, Weight = weight, Style = style} end}
local ColorSequence = {new = function(a, b) return {__kind = "ColorSequence", A = a, B = b or a} end}
local NumberSequence = {new = function(a, b)
	if type(a) == "table" then return {__kind = "NumberSequence", Keypoints = a} end
	return {__kind = "NumberSequence", Keypoints = {{Time = 0, Value = a}, {Time = 1, Value = b or a}}}
end}
local NumberSequenceKeypoint = {new = function(time, value) return {Time = time, Value = value} end}
local TweenInfo = {new = function(...) return {__kind = "TweenInfo", ...} end}
local enumItems = {}
local Enum = setmetatable({}, {__index = function(_, group)
	return setmetatable({}, {__index = function(_, item)
		local key = group .. "." .. item
		if not enumItems[key] then
			enumItems[key] = setmetatable({__kind = "EnumItem", Name = item, Key = key},
				{__tostring = function() return "Enum." .. key end})
		end
		return enumItems[key]
	end})
end})

local function typeof(value)
	if type(value) == "table" then
		if value.__instance then return "Instance" end
		if value.__kind then return value.__kind end
	end
	return type(value)
end

-- -------------------------------------------------------------- instances
local CURRENT -- the running context (clock, viewport)
local SUPER = {
	TextButton = "GuiButton", ImageButton = "GuiButton", GuiButton = "GuiObject",
	TextLabel = "GuiObject", ImageLabel = "GuiObject", Frame = "GuiObject", TextBox = "GuiObject",
	ScrollingFrame = "GuiObject", CanvasGroup = "GuiObject", GuiObject = "GuiBase2d",
	ScreenGui = "LayerCollector", LayerCollector = "GuiBase2d",
	LocalScript = "Script", Script = "BaseScript", BaseScript = "LuaSourceContainer",
	ModuleScript = "LuaSourceContainer",
	UIStroke = "UIComponent", UICorner = "UIComponent", UIGradient = "UIComponent",
	UIListLayout = "UIComponent", UIGridLayout = "UIComponent", UIPadding = "UIComponent",
	UIAspectRatioConstraint = "UIComponent", UITextSizeConstraint = "UIComponent", UIScale = "UIComponent",
	UIShadow = "UIComponent",
}
local function isA(class, wanted)
	while class do
		if class == wanted then return true end
		class = SUPER[class]
	end
	return wanted == "Instance"
end
local SIGNALS = {
	Activated = true, InputBegan = true, InputEnded = true, MouseEnter = true, MouseLeave = true,
	Event = true, OnClientEvent = true, Changed = true, ChildAdded = true, DescendantAdded = true,
	Destroying = true,
}

-- AbsoluteSize: laid out on read from the parent's (Size Scale x parent + Offset), fitted by a
-- UIAspectRatioConstraint; a ScreenGui is the viewport. TextBounds: one line, TextSize x
-- characters x FakeAdvance (0.55 unless a test sets it). TextScaled uses the current box and a
-- UITextSizeConstraint; injected advance/em-height model unusually wide/tall fallback glyphs.
local TEXT_CLASSES = {TextLabel = true, TextButton = true, TextBox = true}
local MEASURED = {Text = true, TextSize = true, TextScaled = true, TextWrapped = true, FontFace = true, FakeAdvance = true, FakeEmHeight = true}
local function measureText(fields, node)
	local text = tostring(fields.Text or "")
	local count = utf8.len(text) or #text
	local size = fields.TextSize or 14
	local advance, height = fields.FakeAdvance or 0.55, fields.FakeEmHeight or 1
	if fields.TextScaled and node and count > 0 then
		local box, limit = node.AbsoluteSize, node:FindFirstChildOfClass("UITextSizeConstraint")
		size = math.clamp(math.min(box.X / (count * advance), box.Y / height),
			limit and limit.MinTextSize or 1, limit and limit.MaxTextSize or 100)
	end
	return {__kind = "Vector2", X = count * size * advance, Y = count > 0 and size * height or 0}
end
local function layoutSize(node)
	local parent = node.Parent
	local base = parent and parent.AbsoluteSize
	if type(base) ~= "table" then return Vector2.new(0, 0) end
	local size = node.Size
	local w, h = size.X.Scale * base.X + size.X.Offset, size.Y.Scale * base.Y + size.Y.Offset
	local ratio = node:FindFirstChildOfClass("UIAspectRatioConstraint")
	if ratio and (ratio.AspectRatio or 0) > 0 and h > 0 then
		if w / h > ratio.AspectRatio then w = h * ratio.AspectRatio else h = w / ratio.AspectRatio end
	end
	return Vector2.new(w, h)
end

local FIELDS = setmetatable({}, {__mode = "k"})
local methods = {}
local SKIP_CLONE = {Parent = true, Children = true, Attributes = true, Watchers = true, ClassName = true, Name = true}
local function newInstance(class, name)
	local fields = {ClassName = class, Name = name or class, Children = {}, Attributes = {}, Watchers = {}}
	if isA(class, "GuiObject") then
		fields.Visible = true
		fields.Active = false
		fields.ZIndex = 1
		fields.Size = UDim2.new()
		fields.Position = UDim2.new()
		fields.AnchorPoint = Vector2.new(0, 0)
		fields.BackgroundColor3 = Color3.new(1, 1, 1)
		fields.BackgroundTransparency = 0
		fields.AbsolutePosition = Vector2.new(0, 0)
	end
	if isA(class, "GuiButton") then fields.Active = true; fields.AutoButtonColor = true end
	if TEXT_CLASSES[class] then
		fields.Text = ""
		fields.TextScaled = false
		fields.TextWrapped = false
		fields.TextSize = 14
		fields.TextColor3 = Color3.new(0, 0, 0)
	end
	if class == "ImageLabel" or class == "ImageButton" then fields.Image = "" end
	if class == "CanvasGroup" then fields.GroupTransparency = 0 end
	if class == "ScreenGui" then
		fields.Enabled = true
		fields.DisplayOrder = 0
		fields.ResetOnSpawn = true
		fields.AbsolutePosition = Vector2.new(0, 0)
	end
	if class == "UIGradient" then fields.Enabled = true end
	if class == "UITextSizeConstraint" then fields.MinTextSize = 1; fields.MaxTextSize = 100 end
	local proxy
	proxy = setmetatable({__instance = true}, {
		__index = function(_, key)
			local value = fields[key]
			if value ~= nil then return value end
			if key == "AbsoluteSize" then
				if class == "ScreenGui" then return CURRENT and CURRENT.Viewport or Vector2.new(1920, 1080) end
				if isA(class, "GuiObject") then return layoutSize(proxy) end
			end
			if key == "TextBounds" and TEXT_CLASSES[class] then return measureText(fields, proxy) end
			if SIGNALS[key] then fields[key] = signal(); return fields[key] end
			if methods[key] then return methods[key] end
			for _, child in ipairs(fields.Children) do
				if child.Name == key then return child end
			end
			return nil
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local old = fields.Parent
				if old == value then return end
				if old then
					for index, child in ipairs(old.Children) do
						if child == proxy then table.remove(old.Children, index) break end
					end
				end
				fields.Parent = value
				if value ~= nil then
					table.insert(value.Children, proxy)
					value.ChildAdded:Fire(proxy)
					local added = proxy:GetDescendants()
					table.insert(added, 1, proxy)
					local ancestor = value
					while ancestor do
						for _, node in ipairs(added) do ancestor.DescendantAdded:Fire(node) end
						ancestor = ancestor.Parent
					end
				end
				local watcher = fields.Watchers["@Parent"]
				if watcher then watcher:Fire() end
				return
			end
			local bounds = MEASURED[key] and fields.Watchers["@TextBounds"]
			local before = bounds and measureText(fields, proxy)
			fields[key] = value
			-- Native TextLabel probe, 2026-10-09: scaling enables wrapping; disabling
			-- wrapping disables scaling. Model this coupling before text-fit assertions.
			local coupled
			if key == "TextScaled" and value == true and fields.TextWrapped == false then
				fields.TextWrapped, coupled = true, "TextWrapped"
			elseif key == "TextWrapped" and value == false and fields.TextScaled == true then
				fields.TextScaled, coupled = false, "TextScaled"
			end
			local coupledWatcher = coupled and fields.Watchers["@" .. coupled]
			if coupledWatcher then coupledWatcher:Fire() end
			local watcher = fields.Watchers["@" .. key]
			if watcher then watcher:Fire() end
			if before then
				local after = measureText(fields, proxy)
				if after.X ~= before.X or after.Y ~= before.Y then bounds:Fire() end
			end
		end,
	})
	FIELDS[proxy] = fields
	return proxy
end

function methods:IsA(class) return isA(self.ClassName, class) end
function methods:GetChildren() return table.clone(self.Children) end
function methods:GetDescendants()
	local out = {}
	for _, child in ipairs(self.Children) do
		table.insert(out, child)
		for _, nested in ipairs(child:GetDescendants()) do table.insert(out, nested) end
	end
	return out
end
function methods:FindFirstChild(name, recursive)
	for _, child in ipairs(self.Children) do if child.Name == name then return child end end
	if recursive then
		for _, child in ipairs(self.Children) do
			local found = child:FindFirstChild(name, true)
			if found then return found end
		end
	end
	return nil
end
function methods:FindFirstChildOfClass(class)
	for _, child in ipairs(self.Children) do if child.ClassName == class then return child end end
	return nil
end
function methods:FindFirstChildWhichIsA(class, recursive)
	for _, node in ipairs(recursive and self:GetDescendants() or self.Children) do
		if node:IsA(class) then return node end
	end
	return nil
end
function methods:WaitForChild(name, timeout)
	local found = self:FindFirstChild(name)
	if found or timeout then return found end
	error("fixture is missing " .. self.Name .. "." .. name)
end
function methods:Destroy()
	self.Destroying:Fire()
	for _, child in ipairs(self:GetChildren()) do child:Destroy() end
	self.Parent = nil
end
function methods:GetFullName()
	local names, node = {}, self
	while node do table.insert(names, 1, node.Name); node = node.Parent end
	return table.concat(names, ".")
end
function methods:GetAttribute(key) return self.Attributes[key] end
function methods:SetAttribute(key, value)
	self.Attributes[key] = value
	local watcher = self.Watchers[key]
	if watcher then watcher:Fire() end
end
function methods:GetAttributeChangedSignal(key)
	if not self.Watchers[key] then self.Watchers[key] = signal() end
	return self.Watchers[key]
end
function methods:GetPropertyChangedSignal(property)
	local key = "@" .. property
	if not self.Watchers[key] then self.Watchers[key] = signal() end
	return self.Watchers[key]
end
function methods:GetServerTimeNow() return CURRENT.Now end
-- Every plain property is copied (not signals, not tree links), then the children.
function methods:Clone()
	local copy = newInstance(self.ClassName, self.Name)
	local target = FIELDS[copy]
	for key, value in pairs(FIELDS[self]) do
		if not SKIP_CLONE[key] and not (type(value) == "table" and value.__signal) then target[key] = value end
	end
	for key, value in pairs(self.Attributes) do copy.Attributes[key] = value end
	for _, child in ipairs(self.Children) do child:Clone().Parent = copy end
	return copy
end
local Instance = {new = function(class) return newInstance(class) end}

-- Harness-side search by BASE name (Framewisp tags stripped), independent of ShopBinder.
local TAGS = {button = 1, close = 1, panel = 1, tabgroup = 1, scroll = 1, grid = 1, list = 1,
	txt = 1, shadow = 1, image = 1, ignore = 1, aspect = 1, fit = 1, nolist = 1}
local function baseName(name)
	while true do
		local head, tag = name:match("^(.+)_(%a+)$")
		if not head or not TAGS[tag] then return name end
		name = head
	end
end
local function find(root, path)
	local node = root
	for segment in string.gmatch(path, "[^/]+") do
		local hit = nil
		for _, child in ipairs(node:GetDescendants()) do
			if baseName(child.Name) == segment then hit = child break end
		end
		if not hit then return nil end
		node = hit
	end
	return node
end
-- Drawn: the node and every GuiObject ancestor up to its ScreenGui are Visible.
local function drawn(node)
	while node and node.ClassName ~= "ScreenGui" do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return node ~= nil
end

-- ------------------------------------------------------------ tree builder
local function toColor(rgb) return Color3.fromRGB(rgb[1], rgb[2], rgb[3]) end
local AS_UDIM2 = {Size = true, Position = true, CanvasSize = true, CellSize = true, CellPadding = true}
local AS_UDIM = {CornerRadius = true, Padding = true, PaddingTop = true, PaddingBottom = true, PaddingLeft = true, PaddingRight = true}
local AS_VECTOR2 = {AnchorPoint = true, AbsolutePosition = true, CanvasPosition = true, ImageRectOffset = true, ImageRectSize = true, Offset = true}
local AS_COLOR = {BackgroundColor3 = true, Color = true, TextColor3 = true, ImageColor3 = true}
local function build(spec)
	local node = newInstance(spec.ClassName, spec.Name)
	for key, value in pairs(spec) do
		-- AbsoluteSize: the dump's is the EDITOR viewport's; the fake lays out its own.
		if key == "Name" or key == "ClassName" or key == "Children" or key == "AbsoluteSize" or key == "AbsolutePosition" then continue end
		if key == "Attributes" then
			for name, attribute in pairs(value) do node.Attributes[name] = attribute end
			continue
		end
		if key == "ColorKeypoints" then
			node.Color = ColorSequence.new(toColor({value[1][2], value[1][3], value[1][4]}),
				toColor({value[#value][2], value[#value][3], value[#value][4]}))
		elseif AS_COLOR[key] and type(value) == "table" then node[key] = toColor(value)
		elseif AS_UDIM2[key] then node[key] = UDim2.new(value[1], value[2], value[3], value[4])
		elseif AS_UDIM[key] then node[key] = UDim.new(value[1], value[2])
		elseif AS_VECTOR2[key] then node[key] = Vector2.new(value[1], value[2])
		elseif type(value) == "string" and string.sub(value, 1, 5) == "Enum." then
			local group, item = string.match(value, "^Enum%.([^.]+)%.(.+)$")
			node[key] = Enum[group][item]
		else node[key] = value end
	end
	for _, child in ipairs(spec.Children or {}) do build(child).Parent = node end
	return node
end

-- ------------------------------------------------------------------- boot
-- opts: touch, gamepadEnabled, gamepadOnly, lastInput ("Keyboard" | "Gamepad"), safe, viewport,
-- skip = {[bundle] = true} (a place where that bundle was never imported), noGlyph (the engine
-- has no glyph image for a key).
local function context(opts)
	opts = opts or {}
	local ctx = {Now = 0, Timers = {}, Deferred = {}, Warnings = {}, Tweens = {},
		Touch = opts.touch == true, GamepadEnabled = opts.gamepadEnabled == true,
		GamepadOnly = opts.gamepadOnly == true, LastInput = opts.lastInput or "Keyboard",
		NoGlyph = opts.noGlyph == true, Viewport = opts.viewport or Vector2.new(1920, 1080)}
	ctx.Safe = opts.safe or {Left = 0, Top = 0, Right = ctx.Viewport.X, Bottom = ctx.Viewport.Y - 58,
		Width = ctx.Viewport.X, Height = ctx.Viewport.Y - 58}
	CURRENT = ctx

	-- task on a manual clock: delay is a timer, defer a queue, wait a no-op.
	local function run(fn, ...)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then error(debug.traceback(co, tostring(err)), 0) end
	end
	ctx.Task = {spawn = run, wait = function() end}
	function ctx.Task.defer(fn, ...) table.insert(ctx.Deferred, {fn, table.pack(...)}) end
	function ctx.Task.delay(seconds, fn, ...)
		table.insert(ctx.Timers, {At = ctx.Now + (seconds or 0), Fn = fn, Args = table.pack(...)})
	end
	function ctx:Flush()
		while #self.Deferred > 0 do
			local item = table.remove(self.Deferred, 1)
			run(item[1], table.unpack(item[2], 1, item[2].n))
		end
	end
	function ctx:Advance(seconds)
		local target = self.Now + seconds
		while true do
			local index, due = nil, nil
			for i, timer in ipairs(self.Timers) do
				if timer.At <= target + 1e-9 and (not due or timer.At < due.At) then index, due = i, timer end
			end
			if not due then break end
			table.remove(self.Timers, index)
			self.Now = math.max(self.Now, due.At)
			run(due.Fn, table.unpack(due.Args, 1, due.Args.n))
			self:Flush()
		end
		self.Now = target
		self:Flush()
	end

	ctx.Workspace = newInstance("Workspace", "Workspace")
	ctx.Player = newInstance("Player", "Player")
	ctx.Player.UserId, ctx.Player.DisplayName = 1, "Local Player"
	ctx.PlayerGui = newInstance("PlayerGui", "PlayerGui")
	ctx.PlayerGui.Parent = ctx.Player

	local storage = newInstance("ReplicatedStorage", "ReplicatedStorage")
	local shopUI = newInstance("Folder", "ZyntraShopUI")
	shopUI.Parent = storage
	for name in pairs(SOURCES) do
		newInstance("ModuleScript", name).Parent = name == "ShopBinder" and shopUI or storage
	end
	newInstance("ModuleScript", "UIDevice").Parent = storage
	local hud = newInstance("Folder", "ZyntraHUD")
	local templates = newInstance("Folder", "Templates")
	templates.Parent = hud
	for bundle, spec in pairs(TREES) do
		if not (opts.skip and opts.skip[bundle]) then build(spec).Parent = templates end
	end
	hud.Parent = storage
	ctx.Storage, ctx.Templates = storage, templates

	-- UIDevice at its published contract.
	local UIDeviceFake = {Changed = signal()}
	function UIDeviceFake.IsTouch() return ctx.Touch end
	function UIDeviceFake.LastInput() return ctx.LastInput end
	function UIDeviceFake.Binding(keyboard, gamepad)
		if ctx.Touch then return "" end
		if gamepad and gamepad ~= "" and ctx.GamepadEnabled and ctx.LastInput == "Gamepad" then return gamepad end
		if ctx.GamepadOnly then return "" end
		return keyboard or ""
	end
	function UIDeviceFake.Layout() return {IsTouch = ctx.Touch, Safe = ctx.Safe} end
	function UIDeviceFake.TopRightPanel(width, height)
		local safe = ctx.Safe
		local margin = ctx.Touch and 8 or 18
		local right, top = safe.Right - margin, safe.Top + margin
		width = math.min(width, right - safe.Left - margin)
		height = math.min(height, safe.Bottom - margin - top)
		return {Left = right - width, Right = right, Top = top, Bottom = top + height, Width = width, Height = height}
	end
	-- Every gui in the fake sits at the display origin, so absolute == local.
	function UIDeviceFake.LocalPosition(_, x, y) return UDim2.fromOffset(math.floor(x), math.floor(y)) end
	ctx.UIDevice = UIDeviceFake
	-- Flip a device fact and fire Changed, as UIDevice does.
	function ctx:Device(changes)
		for key, value in pairs(changes) do self[key] = value end
		UIDeviceFake.Changed:Fire()
		self:Flush()
	end

	ctx.UIS = {GamepadEnabled = false}
	function ctx.UIS:GetStringForKeyCode(key)
		-- A letter key prints its letter; others answer "" (the module falls back to the name).
		return #key.Name == 1 and key.Name or ""
	end
	function ctx.UIS:GetImageForKeyCode(key)
		if ctx.NoGlyph or not (key.Name:match("^Button") or key.Name:match("^DPad")) then return "" end
		return "rbxasset://textures/ui/Controls/xbox" .. key.Name .. ".png"
	end
	ctx.Tween = {}
	function ctx.Tween:Create(instance, info, goal)
		local tween = {Instance = instance, Time = info[1], Goal = goal}
		function tween:Play() for key, value in pairs(goal) do instance[key] = value end end
		function tween:Cancel() self.Cancelled = true end
		table.insert(ctx.Tweens, tween)
		return tween
	end
	ctx.Players = {LocalPlayer = ctx.Player, Members = {ctx.Player}}
	function ctx.Players:GetPlayers() return table.clone(self.Members) end
	function ctx.Players:GetPlayerByUserId(id)
		for _, who in ipairs(self.Members) do if who.UserId == id then return who end end
	end
	function ctx.Players:FindFirstChild(name)
		for _, who in ipairs(self.Members) do if who.Name == name then return who end end
	end
	ctx.RunService = {IsStudio = function() return true end, Heartbeat = signal()}
	local services = {
		Players = ctx.Players, ReplicatedStorage = storage, TweenService = ctx.Tween,
		UserInputService = ctx.UIS, RunService = ctx.RunService,
	}
	ctx.Services=services
	local game = {GetService = function(_, name) return assert(services[name], "service " .. name) end}

	-- require: the REAL sources, each in its own environment, one instance per context.
	local cache = {}
	local function load(name, scriptInstance)
		local fn = assert(FACTORIES[name], "known factory")()
		local env = setmetatable({
			game = game, workspace = ctx.Workspace, script = scriptInstance, task = ctx.Task,
			Instance = Instance, Color3 = Color3, UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Vector3 = Vector3,
			ColorSequence = ColorSequence, NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint,
			TweenInfo = TweenInfo, Enum = Enum,
			typeof = typeof, Font = Font,
			warn = function(...)
				local parts = {}
				for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
				table.insert(ctx.Warnings, table.concat(parts, " "))
			end,
		}, {__index = getfenv()})
		env.require = function(module)
			local key = module.Name
			if cache[key] == nil then
				cache[key] = key == "UIDevice" and UIDeviceFake or load(key, module)
			end
			return cache[key]
		end
		setfenv(fn, env)
		return fn()
	end
	function ctx:Require(name)
		if cache[name] == nil then
			local result
			run(function() result = load(name) end)
			cache[name] = result
		end
		self:Flush()
		return cache[name]
	end
	function ctx:Warned(needle)
		local count = 0
		for _, line in ipairs(self.Warnings) do
			if string.find(line, needle, 1, true) then count += 1 end
		end
		return count
	end
	function ctx:LastTween(instance)
		for index = #self.Tweens, 1, -1 do
			if self.Tweens[index].Instance == instance then return self.Tweens[index] end
		end
		return nil
	end
	return ctx
end


local function boot(touch)
 local ctx = context({touch=touch})
 local services=ctx.Services
 services.Players.LocalPlayer.Name="Tester"
 services.Players.LocalPlayer.DisplayName="Display Tester"
 function services.Players:GetPlayers() return {ctx.Player} end
 function services.Players:GetPlayerByUserId(id) return id==ctx.Player.UserId and ctx.Player or nil end
 ctx.Player.UserId=1
 ctx.GuiService={MenuIsOpen=false}
 services.GuiService=ctx.GuiService
 services.RunService={RenderStepped=signal(),Heartbeat=signal(),IsStudio=function() return true end}
 services.ProximityPromptService={PromptShown=signal(),PromptHidden=signal(),Enabled=true}
 ctx.UIS.InputBegan,ctx.UIS.InputEnded,ctx.UIS.WindowFocusReleased=signal(),signal(),signal()
 ctx.UIS.TextBoxFocused,ctx.UIS.TextBoxFocusReleased=signal(),signal()
 function ctx.UIS:GetFocusedTextBox() return self.Focused end
 function ctx.GuiService:GetPropertyChangedSignal(name) return signal() end
 ctx.UIDevice.SetInteractive=function(n,yes) n.Visible,n.Active=yes,yes end
 ctx.UIDevice.SetEnabled=function(n,yes) n.Active=yes end
 local originalLayout=ctx.UIDevice.Layout
 ctx.UIDevice.Layout=function()
  local d=originalLayout()
  d.Zones=ctx.HidingZones or {Thumbstick={Left=0,Top=0,Right=0,Bottom=0}}
  return d
 end
 ctx.UIDevice.OverlapsMovementZone=function(left,top,right,bottom)
  for name,z in pairs(ctx.UIDevice.Layout().Zones) do
   if left<z.Right and right>z.Left and top<z.Bottom and bottom>z.Top then return name end
  end
  return nil
 end
 ctx.UIDevice.ScreenOwningModalOpen=function() return ctx.Player:GetAttribute("ZyntraStoreOpen")==true end
 ctx.UIDevice.OnScreenOwningModalChanged=function(fn) ctx.Player:GetAttributeChangedSignal("ZyntraStoreOpen"):Connect(fn) end
 local remotes=Instance.new("Folder");remotes.Name="Remotes";remotes.Parent=ctx.Storage
 ctx.Remote=Instance.new("RemoteEvent");ctx.Remote.Name="RoundStatus";ctx.Remote.Parent=remotes
 ctx.Remote.OnClientEvent=signal();ctx.Requests={}
 function ctx.Remote:FireServer(...) table.insert(ctx.Requests,{...}) end
 ctx.PlayerScripts=Instance.new("Folder");ctx.PlayerScripts.Name="PlayerScripts";ctx.PlayerScripts.Parent=ctx.Player
 ctx.Humanoid=Instance.new("Humanoid");ctx.Humanoid.Health=100;ctx.Humanoid.HealthChanged=signal();ctx.Humanoid.Died=signal()
 ctx.Character=Instance.new("Model");ctx.Character.Name="Character";ctx.Humanoid.Parent=ctx.Character;ctx.Player.Character=ctx.Character
 ctx.Player.CharacterAdded,ctx.Player.CharacterRemoving=signal(),signal()
 ctx.Workspace:SetAttribute("RoundActive",true)
 ctx.Player:SetAttribute("InRound",true)
 ctx.Player:SetAttribute("RoundEntryControlsReady",true)
 function ctx:Step(dt) self:Advance(dt);services.RunService.RenderStepped:Fire(dt);services.RunService.Heartbeat:Fire(dt) end
 function ctx:Key(code,ended)
  local input={KeyCode=Enum.KeyCode[code],UserInputType=Enum.UserInputType.Keyboard,UserInputState=Enum.UserInputState.Begin}
  if ended then ctx.UIS.InputEnded:Fire(input) else ctx.UIS.InputBegan:Fire(input,false) end
 end
 return ctx
end

for _, fps in ipairs({15,60,240}) do
 local ctx=boot(false);ctx:Require("ExitClient");ctx:Key("L")
 for i=1,math.ceil(1.5*fps)-1 do ctx:Step(1/fps) end
 check(#ctx.Requests==0,"no early hold at "..fps.." FPS")
 ctx:Step(1/fps+.0001);check(#ctx.Requests==1,"1.5 wall seconds at "..fps.." FPS")
end
for _,gate in ipairs({"Spectating","Escaped","Level2_ExitTransition","DispatchBriefingOpen","Level4CardOpen","PartyDownCardOpen"}) do
 local ctx=boot(false);ctx:Require("ExitClient");ctx:Key("L");ctx:Step(.6)
 ctx.Player:SetAttribute(gate,true);ctx:Step(1.5)
 check(#ctx.Requests==0,"mid-hold "..gate.." cancels")
end
for _, mode in ipairs({"typing","menu","focus","death","roundend","respawn"}) do
 local ctx=boot(false);ctx:Require("ExitClient");ctx:Key("L");ctx:Step(.6)
 if mode=="typing" then ctx.UIS.Focused=true
 elseif mode=="menu" then ctx.GuiService.MenuIsOpen=true
 elseif mode=="focus" then ctx.UIS.WindowFocusReleased:Fire()
 elseif mode=="death" then ctx.Humanoid.Health=0
 elseif mode=="roundend" then ctx.Workspace:SetAttribute("RoundActive",false)
 elseif mode=="respawn" then ctx.Player.CharacterRemoving:Fire() end
 ctx:Step(1.5);check(#ctx.Requests==0,"mid-hold "..mode.." cancels")
end
for _, touch in ipairs({false,true}) do
 local ctx=boot(touch);ctx:Require("ExitClient")
 local gui=ctx.PlayerGui:FindFirstChild("RoundExitGui")
 local door=gui:FindFirstChild(touch and "LeaveChipTouch" or "LeaveChip")
 check(door.Visible and door.Active,"exit available")
 check(door.Size.X.Offset==(touch and 44 or 40),"authored door width")
 check(door.Position.X.Offset==(touch and 12 or 24),"safe door lane")
 ctx:Key("L");ctx:Step(.8);ctx:Key("L",true);ctx:Step(1)
 check(#ctx.Requests==0,"early release no request")
 ctx:Key("L");ctx:Step(.7);ctx.Player:SetAttribute("ZyntraStoreOpen",true);ctx:Step(1)
 check(#ctx.Requests==0,"modal cancels hold")
 ctx.Player:SetAttribute("ZyntraStoreOpen",nil);ctx:Key("L",true)
 ctx:Key("L");ctx:Step(1.5);check(#ctx.Requests==1,"full hold once")
 ctx.Remote.OnClientEvent:Fire("leavefailed");ctx:Step(2)
 check(#ctx.Requests==1,"finished hold latched after refusal")
 ctx:Key("L",true);ctx:Key("ButtonSelect");ctx:Step(1.5)
 check(#ctx.Requests==2,"View hold uses existing protocol")
 ctx:Key("ButtonSelect",true);ctx:Advance(8.1)
 ctx.PlayerScripts:FindFirstChild("RoundExitPrompt").Event:Fire()
 local shade=gui:FindFirstChild("RoundExitShade");local card=shade:FindFirstChild("RoundExitCard")
 check(shade.Visible,"spectate confirm opens")
 local Binder=ctx:Require("ShopBinder")
 local confirm=Binder.at(card,"BackToLobby");local stay=Binder.at(card,"Stay")
 check(confirm.Active and stay.Active,"timeout re-enables confirmation")
 if touch then check(confirm.Size.Y.Offset>=44 and stay.Size.Y.Offset>=44,"phone confirm hits") end
 ctx:Key("ButtonB");check(not shade.Visible,"B chooses stay")
 ctx:Device({Touch=not touch});check(#ctx.Requests==2,"device remount never requests")
end

do
 local ctx=boot(false);ctx:Require("ExitClient")
 ctx:Key("L");ctx:Step(1.5);ctx.Remote.OnClientEvent:Fire("leaveack")
 ctx:Key("L",true);ctx:Advance(8.1)
 ctx.PlayerScripts:FindFirstChild("RoundExitPrompt").Event:Fire()
 local gui=ctx.PlayerGui:FindFirstChild("RoundExitGui")
 local Binder=ctx:Require("ShopBinder")
 local confirm=Binder.at(gui,"BackToLobby")
 check(not confirm.Active,"ack invalidates silence timer and keeps one pending request")
 confirm.Activated:Fire();check(#ctx.Requests==1,"card cannot duplicate held request")
 ctx.Remote.OnClientEvent:Fire("lobby");ctx:Advance(10)
 check(not gui:FindFirstChild("RoundExitShade").Visible,"old request timers never reopen a reset card")
end
do
 local ctx=boot(false);ctx:Require("ExitClient")
 ctx:Key("L");ctx:Step(1.5);ctx.Remote.OnClientEvent:Fire("leavefailed");ctx:Key("L",true)
 ctx:Key("L");ctx:Step(1.5);ctx:Key("L",true);ctx:Advance(5.1)
 ctx.PlayerScripts:FindFirstChild("RoundExitPrompt").Event:Fire()
 local Binder=ctx:Require("ShopBinder")
 check(not Binder.at(ctx.PlayerGui:FindFirstChild("RoundExitGui"),"BackToLobby").Active,
  "superseded first timeout cannot unlock second request")
end

-- Early missing-import path: the source warns, destroys its owned GUI and
-- returns before binding hold/input callbacks. Controlled assets boundary.
do
 local ctx=boot(false)
 ctx.Templates:FindFirstChild("HUD_PC"):Destroy()
 ctx.Templates:FindFirstChild("HUD_Touch"):Destroy()
 ctx:Require("ExitClient")
 check(ctx.PlayerGui:FindFirstChild("RoundExitGui")==nil,"missing imports destroy the partial owned exit GUI")
 check(ctx:Warned("Round Exit Client: missing imported HUD templates")==1,"missing imports warn once")
 ctx:Key("L");ctx:Step(2)
 check(#ctx.Requests==0,"missing imports install no hold flow")
end
return {pass=true,checks=checks,scope="Whole actual Round Exit source, real source dependencies and imported fixture trees; controlled engine/player/input/transport/timer/UIDevice boundaries. Not native assets, gameplay, hardware, multiplayer, streaming or teleport certification."}

end
