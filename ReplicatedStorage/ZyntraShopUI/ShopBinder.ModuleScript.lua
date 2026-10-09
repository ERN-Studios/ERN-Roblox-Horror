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
