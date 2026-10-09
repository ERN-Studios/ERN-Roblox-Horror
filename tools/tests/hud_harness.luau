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

--@@INJECT@@

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
local MEASURED = {Text = true, TextSize = true, TextScaled = true, FontFace = true, FakeAdvance = true, FakeEmHeight = true}
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
	local game = {GetService = function(_, name) return assert(services[name], "service " .. name) end}

	-- require: the REAL sources, each in its own environment, one instance per context.
	local cache = {}
	local function load(name, scriptInstance)
		local fn = assert(loadstring(SOURCES[name], "=" .. name))
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
		}, {__index = _G})
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
