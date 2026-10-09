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
		for name, part in pairs(objective.Parts) do part.Visible = name == "Bar" or (name == "StatusRow" and danger == true) end
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

local function paintCompass(state)
	local part = objective.Parts.Compass
	if not part or not part.Visible then return end
	local compass = state.Compass
	local chevron = Binder.text(Binder.at(part, "Chevron"))
	local readout = Binder.text(Binder.at(part, "Readout"))
	local ticks = Binder.at(part, "Ticks")
	if not chevron or not readout then return end
	local mode = compass.State
	local color = UIStyle.Hud.Accent[state.Level] or P.Cream
	local glyph, text, fraction = "\u{25BC}", "LOCATING", 0.5
	local readColor = P.Sage
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
			local bearing = math.deg(math.atan2(look.X * dz - look.Z * dx, look.X * dx + look.Z * dz))
			fraction = (math.clamp(bearing, -60, 60) + 60) / 120
			if bearing < -60 then glyph = "\u{25C0}" elseif bearing > 60 then glyph = "\u{25B6}" end
			text = tostring(math.floor(metres + 0.5)) .. " m"
			if state.Title == "GET OUT" and metres < 8 then text, readColor = "AT THE EXIT", P.RailTeal end
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
	chevron.TextScaled, chevron.TextWrapped = true, false
	chevron.Text, chevron.TextColor3, readout.Text, readout.TextColor3 = glyph, color, text, readColor
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
		elseif name == "Compass" then part.Visible = expanded and state.Compass ~= nil end
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
	elapsed += dt
	if elapsed < 0.1 then return end
	elapsed = 0
	refreshOwned()
end)

return RoundHud
