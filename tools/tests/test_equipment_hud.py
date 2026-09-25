"""Run the whole ProtectionHUD LocalScript, and the real UIDevice control plan,
in offline Luau under a fake DataModel.

Two halves, one process:

  1. THE CONTROL PLAN. The REAL ReplicatedStorage/UIDevice.ModuleScript.lua is
     loaded against a fake engine and asked for a layout at a matrix of forced
     viewports. The equipment slots added for Trello #101 are then measured
     against the module's own zones -- thumbstick, jump, top band, safe area --
     rather than against numbers copied out of it.

  2. THE HUD. The REAL StarterPlayer/StarterPlayerScripts/ProtectionHUD
     .LocalScript.lua is loaded whole, with the REAL UIStyle beside it, a fake
     ProtectionClient/ZyntraConfig, and remotes whose FireServer calls are
     captured. UIDevice is a thin fake there -- its Layout() returns the layout
     half 1 computed from the REAL module, so the control slots the HUD places
     buttons in are the shipping arithmetic, not a stand-in.

No network, no Studio. Set LUAU_BIN to an official Luau interpreter.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
UIDEVICE = ROOT / "ReplicatedStorage/UIDevice.ModuleScript.lua"
UISTYLE = ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua"
HUD = ROOT / "StarterPlayer/StarterPlayerScripts/ProtectionHUD.LocalScript.lua"

ENGINE = r'''
local checks = 0
local function check(value, message)
	if not value then error("FAILED: " .. message, 2) end
	checks += 1
end

local function signal()
	local listeners = {}
	local self = {}
	function self:Connect(fn)
		table.insert(listeners, fn)
		return {Disconnect = function()
			for index, listener in ipairs(listeners) do
				if listener == fn then table.remove(listeners, index) break end
			end
		end}
	end
	function self:Fire(...)
		for _, fn in ipairs(table.clone(listeners)) do fn(...) end
	end
	function self:Count() return #listeners end
	return self
end

-- ── Roblox value types, only as far as the two scripts actually use them ────
local Vector2 = {}
local vector2Meta = {__index = function(v, key) return rawget(v, key) end}
vector2Meta.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
function Vector2.new(x, y)
	return setmetatable({Kind = "Vector2", X = x or 0, Y = y or 0}, vector2Meta)
end
Vector2.zero = Vector2.new(0, 0)

local Rect = {}
function Rect.new(minX, minY, maxX, maxY)
	return {Kind = "Rect", Min = Vector2.new(minX, minY), Max = Vector2.new(maxX, maxY)}
end

local UDim = {}
function UDim.new(scale, offset) return {Kind = "UDim", Scale = scale, Offset = offset} end

local UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	return {Kind = "UDim2", X = UDim.new(xs, xo), Y = UDim.new(ys, yo)}
end
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end

local Color3 = {}
local color3Meta = {}
color3Meta.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
function Color3.fromRGB(r, g, b)
	return setmetatable({Kind = "Color3", R = r, G = g, B = b}, color3Meta)
end
-- Roblox's Color3 has NO arithmetic; leaving it out is what keeps the fake honest.

local ColorSequenceKeypoint = {new = function(t, c) return {Time = t, Value = c} end}
local ColorSequence = {new = function(v) return {Kind = "ColorSequence", Keypoints = v} end}

-- Enum items are memoised so identity comparison works the way it does live.
local enumTypes = {}
local Enum = setmetatable({}, {__index = function(_, typeName)
	local existing = enumTypes[typeName]
	if existing then return existing end
	local items = {}
	local holder = setmetatable({}, {__index = function(_, itemName)
		local item = items[itemName]
		if item == nil then
			item = {Kind = "EnumItem", Name = itemName, EnumType = typeName}
			items[itemName] = item
		end
		return item
	end})
	enumTypes[typeName] = holder
	return holder
end})

local function typeof(value)
	if type(value) == "table" then return value.Kind or "table" end
	return type(value)
end

-- ── Instances ───────────────────────────────────────────────────────────────
-- Parent is the one property with behaviour, so it is the one property that
-- does not live in the raw table: every other assignment rawsets and is read
-- back directly. UIStyle's adopt() depends on Parent maintaining Children.
local instanceMethods = {}
local instanceMeta = {
	__index = function(self, key)
		if key == "Parent" then return rawget(self, "_parent") end
		return instanceMethods[key]
	end,
	__newindex = function(self, key, value)
		if key == "Parent" then
			local old = rawget(self, "_parent")
			if old then
				for index, child in ipairs(old.Children) do
					if child == self then table.remove(old.Children, index) break end
				end
			end
			rawset(self, "_parent", value)
			if value then table.insert(value.Children, self) end
			return
		end
		rawset(self, key, value)
	end,
}

function instanceMethods:IsA(class) return class == self.ClassName end
function instanceMethods:FindFirstChild(name)
	for _, child in ipairs(self.Children) do if child.Name == name then return child end end
	return nil
end
function instanceMethods:WaitForChild(name, _timeout) return self:FindFirstChild(name) end
function instanceMethods:FindFirstChildOfClass(class)
	for _, child in ipairs(self.Children) do if child.ClassName == class then return child end end
	return nil
end
function instanceMethods:FindFirstAncestorWhichIsA(class)
	local node = self.Parent
	while node do
		if node.ClassName == class then return node end
		node = node.Parent
	end
	return nil
end
function instanceMethods:GetDescendants()
	local out = {}
	local function walk(node)
		for _, child in ipairs(node.Children) do table.insert(out, child); walk(child) end
	end
	walk(self)
	return out
end
function instanceMethods:GetAttribute(key) return self.Attributes[key] end
function instanceMethods:SetAttribute(key, value)
	local previous = self.Attributes[key]
	self.Attributes[key] = value
	if previous ~= value then
		local sig = self.AttrSignals[key]
		if sig then sig:Fire() end
	end
end
function instanceMethods:GetAttributeChangedSignal(key)
	local sig = self.AttrSignals[key]
	if not sig then sig = signal(); self.AttrSignals[key] = sig end
	return sig
end
function instanceMethods:GetPropertyChangedSignal(key)
	local sig = self.Signals[key]
	if not sig then sig = signal(); self.Signals[key] = sig end
	return sig
end
function instanceMethods:Destroy()
	self.Parent = nil
	self.Destroyed = true
end

local GUI_DEFAULTS = {
	Visible = true, Text = "", TextScaled = false, TextTransparency = 0, ZIndex = 1,
	BackgroundTransparency = 0, BorderSizePixel = 1, Active = false,
	AbsolutePosition = Vector2.new(0, 0), AbsoluteSize = Vector2.new(0, 0),
	Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0, 0, 0, 0),
	AnchorPoint = Vector2.new(0, 0), Enabled = true, AutoButtonColor = true,
	TextSize = 14, TextColor3 = Color3.fromRGB(0, 0, 0),
}

local Instance = {}
function Instance.new(class)
	local object = setmetatable({ClassName = class, Name = class, Kind = "Instance",
		Children = {}, Attributes = {}, Signals = {}, AttrSignals = {}}, instanceMeta)
	rawset(object, "Destroying", signal())
	rawset(object, "AncestryChanged", signal())
	rawset(object, "ChildAdded", signal())
	rawset(object, "ChildRemoved", signal())
	if class == "BindableEvent" then
		local event = signal()
		rawset(object, "Event", event)
		rawset(object, "Fire", function(_, ...) event:Fire(...) end)
		return object
	end
	for key, value in pairs(GUI_DEFAULTS) do rawset(object, key, value) end
	rawset(object, "Activated", signal())
	rawset(object, "MouseEnter", signal())
	rawset(object, "MouseLeave", signal())
	return object
end
'''

CONTEXT = r'''
-- ── One fake DataModel, shared by both halves ───────────────────────────────
local function makeContext()
	local ctx = {Clock = 100, ServerTime = 1000, Fired = {}, Requests = {}, Tagged = {}}

	ctx.workspace = Instance.new("Workspace")
	ctx.workspace.Name = "Workspace"
	function ctx.workspace:GetServerTimeNow() return ctx.ServerTime end
	local camera = Instance.new("Camera")
	camera.ViewportSize = Vector2.new(1280, 720)
	rawset(ctx.workspace, "CurrentCamera", camera)
	ctx.camera = camera

	ctx.player = Instance.new("Player")
	ctx.player.Name = "LocalPlayer"
	rawset(ctx.player, "CharacterAdded", signal())
	rawset(ctx.player, "CharacterRemoving", signal())
	ctx.Players = {LocalPlayer = ctx.player}
	function ctx.Players:GetPlayerByUserId(id) return ctx.Watched and ctx.Watched.UserId == id and ctx.Watched or nil end

	ctx.CollectionService = {}
	function ctx.CollectionService:GetInstanceAddedSignal() return signal() end
	function ctx.CollectionService:GetInstanceRemovedSignal() return signal() end
	function ctx.CollectionService:GetTagged() return {} end
	function ctx.CollectionService:HasTag() return false end
	function ctx.CollectionService:AddTag() end
	function ctx.CollectionService:RemoveTag() end

	ctx.GuiService = Instance.new("GuiService")
	ctx.GuiService.MenuIsOpen = false
	ctx.GuiService.SelectedObject = nil
	ctx.GuiService.TopbarInset = Rect.new(0, 0, 0, 0)
	function ctx.GuiService:GetGuiInset() return Vector2.new(0, 0), Vector2.new(0, 0) end
	-- A notchless, topbar-less host. Every fixture row below states its own
	-- geometry, so what the "device" reports only has to be self-consistent.
	function ctx.GuiService:GetInsetArea(kind)
		local size = ctx.camera.ViewportSize
		return Rect.new(0, 0, size.X, size.Y)
	end

	ctx.UserInputService = Instance.new("UserInputService")
	ctx.UserInputService.TouchEnabled = false
	ctx.UserInputService.MouseEnabled = true
	ctx.UserInputService.KeyboardEnabled = true
	ctx.UserInputService.GamepadEnabled = false
	rawset(ctx.UserInputService, "LastInputTypeChanged", signal())
	rawset(ctx.UserInputService, "InputBegan", signal())
	rawset(ctx.UserInputService, "InputEnded", signal())
	rawset(ctx.UserInputService, "WindowFocusReleased", signal())
	rawset(ctx.UserInputService, "TextBoxFocused", signal())
	rawset(ctx.UserInputService, "TextBoxFocusReleased", signal())
	function ctx.UserInputService:GetFocusedTextBox() return ctx.FocusedTextBox end

	ctx.RunService = Instance.new("RunService")
	rawset(ctx.RunService, "RenderStepped", signal())
	function ctx.RunService:IsStudio() return true end
	function ctx.RunService:IsClient() return true end

	ctx.ReplicatedStorage = Instance.new("ReplicatedStorage")

	local services = {
		CollectionService = ctx.CollectionService, GuiService = ctx.GuiService,
		Players = ctx.Players, RunService = ctx.RunService,
		UserInputService = ctx.UserInputService, ReplicatedStorage = ctx.ReplicatedStorage,
	}
	ctx.game = {GetService = function(_, name) return assert(services[name], name) end}

	ctx.task = {}
	-- Synchronous: every spawn in these two scripts is a one-shot resolver, and
	-- the 1s inset watcher is a loop this harness must NOT enter.
	function ctx.task.spawn(fn, ...) if not ctx.NoSpawn then fn(...) end end
	function ctx.task.wait() end
	function ctx.task.defer(fn, ...) fn(...) end
	ctx.os = {clock = function() return ctx.Clock end}
	ctx.script = Instance.new("LocalScript")
	return ctx
end
'''

BOOTS = r'''
local function bootModule(ctx, source)
	local game, workspace, task, script, os = ctx.game, ctx.workspace, ctx.task, ctx.script, ctx.os
	local require = function() return nil end
	return source(game, workspace, task, script, os, require)
end
'''


def wrap(name: str, source: str) -> str:
    """Wrap a real Roblox source so its globals come from the fake DataModel."""
    return (
        "local %s = function(game, workspace, task, script, os, require)\n" % name
        + source
        + "\nend\n"
    )


PLAN_TESTS = r'''
-- ═══════════════════════════════════════════════════════════════════════════
-- 1. THE CONTROL PLAN, from the REAL UIDevice module.
-- ═══════════════════════════════════════════════════════════════════════════
local EQUIPMENT = {"ProtectionUse", "SpeedPotionUse", "RouteMarkerPlace"}
local ALL_KEYS = {"TouchJump", "TouchRunHold", "TouchSneakHold", "TouchDropGlowstick",
	"TouchPOV", "FlashlightPower", "ProtectionUse", "SpeedPotionUse", "RouteMarkerPlace"}

-- A slot is stated as insets from the SAFE right/bottom edges; this is the one
-- place the harness converts, and it is the same conversion planZone does.
local function slotRect(layout, slot)
	local right = layout.Safe.Right - slot.Right
	local bottom = layout.Safe.Bottom - slot.Bottom
	return {Left = right - slot.Width, Top = bottom - slot.Height, Right = right, Bottom = bottom}
end

local function overlaps(a, b)
	return a.Left < b.Right and a.Right > b.Left and a.Top < b.Bottom and a.Bottom > b.Top
end

local device, deviceCtx
do
	deviceCtx = makeContext()
	-- UIDevice's inset watcher is `while true do task.wait(1) end`; a synchronous
	-- fake spawn would never come back out of it.
	deviceCtx.NoSpawn = true
	device = bootModule(deviceCtx, UIDeviceSource)
	check(type(device) == "table" and type(device.Layout) == "function",
		"the real UIDevice module loads under the fake DataModel")
end

local function layoutAt(width, height, isTouch)
	deviceCtx.UserInputService.TouchEnabled = isTouch
	deviceCtx.camera.ViewportSize = Vector2.new(width, height)
	deviceCtx.workspace:SetAttribute("ForceTouchUI", isTouch)
	deviceCtx.workspace:SetAttribute("UIRegressionViewport", Vector2.new(width, height))
	return device.Layout()
end

local MATRIX = {
	{Name = "Galaxy A06 landscape", Width = 705, Height = 338},
	{Name = "iPhone SE landscape", Width = 568, Height = 320},
	{Name = "handheld 812x375", Width = 812, Height = 375},
	{Name = "handheld 844x390", Width = 844, Height = 390},
	{Name = "tablet 1024x768", Width = 1024, Height = 768},
	{Name = "phone portrait 375x812", Width = 375, Height = 812},
}

local touchLayouts = {}
for _, row in ipairs(MATRIX) do
	local layout = layoutAt(row.Width, row.Height, true)
	touchLayouts[row.Name] = layout
	local slots, rects = layout.ControlPlan.Slots, {}
	local smallest = math.huge
	for _, key in ipairs(ALL_KEYS) do
		local slot = slots[key]
		check(slot ~= nil, row.Name .. ": the plan states a slot for " .. key)
		smallest = math.min(smallest, slot.Width, slot.Height)
		rects[key] = slotRect(layout, slot)
	end
	check(smallest >= 44, row.Name .. ": every one of the nine slots clears the 44px floor")

	local collisions = 0
	for i = 1, #ALL_KEYS do
		for j = i + 1, #ALL_KEYS do
			if overlaps(rects[ALL_KEYS[i]], rects[ALL_KEYS[j]]) then collisions += 1 end
		end
	end
	check(collisions == 0, row.Name .. ": no two control slots overlap")

	local shield = rects.ProtectionUse
	for index = 2, #EQUIPMENT do
		local key = EQUIPMENT[index]
		local rect = rects[key]
		-- Further from the thumb than the shield is: above it, or left of it.
		check(rect.Bottom <= shield.Top or rect.Right <= shield.Left,
			row.Name .. ": " .. key .. " sits behind the shield, never in front of it")
		check(rect.Left >= layout.Safe.Left and rect.Right <= layout.Safe.Right
			and rect.Top >= layout.Safe.Top and rect.Bottom <= layout.Safe.Bottom,
			row.Name .. ": " .. key .. " is inside the safe area")
		check(not overlaps(rect, layout.Zones.Thumbstick),
			row.Name .. ": " .. key .. " is clear of the thumbstick region")
		check(not overlaps(rect, layout.Zones.Jump),
			row.Name .. ": " .. key .. " is clear of Roblox's own jump button")
		check(not overlaps(rect, layout.TopBand),
			row.Name .. ": " .. key .. " is clear of the objective top band")
	end
end

do -- the column arithmetic itself, on an arrangement that actually uses it
	local layout = touchLayouts["phone portrait 375x812"]
	local slots = layout.ControlPlan.Slots
	check(layout.ControlPlan.Mode == "column", "a portrait phone still uses the column")
	local step = slots.ProtectionUse.Width + layout.ControlPlan.Gap
	check(slots.SpeedPotionUse.Bottom == slots.ProtectionUse.Bottom + step
		and slots.RouteMarkerPlace.Bottom == slots.ProtectionUse.Bottom + step * 2,
		"the column stacks the equipment one cell-plus-gap apart")
	check(slots.SpeedPotionUse.Right == slots.ProtectionUse.Right
		and slots.RouteMarkerPlace.Right == slots.ProtectionUse.Right,
		"the equipment stack stays in the shield's own column")
	check(slots.SpeedPotionUse.Width == slots.ProtectionUse.Width
		and slots.RouteMarkerPlace.Height == slots.ProtectionUse.Height,
		"the equipment slots are the shield's size")
end

do -- and the plan is published on a pointer layout too, for the HUD to ignore
	local layout = layoutAt(1280, 720, false)
	check(layout.IsTouch == false, "a forced pointer layout reports no touch form factor")
	check(layout.ControlPlan.Slots.SpeedPotionUse ~= nil
		and layout.ControlPlan.Slots.RouteMarkerPlace ~= nil,
		"the equipment slots are present on every layout, touch or not")
end

local POINTER_LAYOUTS = {}
for _, size in ipairs({{1280, 720}, {1920, 1080}, {956, 382}}) do
	POINTER_LAYOUTS[size[1] .. "x" .. size[2]] = layoutAt(size[1], size[2], false)
end
local TOUCH_LAYOUT = touchLayouts["Galaxy A06 landscape"]
'''

HUD_TESTS = r'''
-- ═══════════════════════════════════════════════════════════════════════════
-- 2. THE HUD, whole, under the layouts half 1 just computed.
-- ═══════════════════════════════════════════════════════════════════════════
local function hudContext(options)
	options = options or {}
	local ctx = makeContext()
	ctx.Layout = options.Layout or POINTER_LAYOUTS["1280x720"]
	ctx.ClientState = {Charges = 2, Available = true, ServerPending = false,
		Pending = nil, CanRetry = false}

	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = ctx.player
	ctx.playerGui = playerGui

	-- A living, in-round body: the whole HUD is gated on this.
	local character = Instance.new("Model")
	character.Name = "Character"
	character.Parent = ctx.workspace
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	rawset(humanoid, "HealthChanged", signal())
	humanoid.Parent = character
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = character
	rawset(ctx.player, "Character", character)
	ctx.character, ctx.humanoid = character, humanoid

	ctx.player:SetAttribute("InRound", true)
	ctx.player:SetAttribute("RoundEntryControlsReady", true)
	ctx.workspace:SetAttribute("RoundActive", true)
	ctx.workspace:SetAttribute("RoundLoadingState", "ready")

	-- ── the module table ProtectionHUD requires ─────────────────────────────
	local deviceChanged = Instance.new("BindableEvent")
	local fake = {Changed = deviceChanged.Event, Registered = {}, Glyphs = false}
	ctx.Device = fake
	ctx.DeviceChanged = deviceChanged
	function fake.Layout() return ctx.Layout end
	function fake.IsTouch() return ctx.Layout.IsTouch end
	function fake.SuppressesKeyboardGlyphs() return fake.Glyphs end
	function fake.Binding(keyboard, gamepad)
		if fake.Glyphs then return "" end
		if ctx.Gamepad and gamepad then return gamepad end
		return keyboard or ""
	end
	function fake.ScreenOwningModalOpen() return ctx.Modal == true end
	function fake.RegisterControlRect(key, element)
		fake.Registered[key] = element
		element:SetAttribute("UIDeviceControlKey", key)
	end
	function fake.UnregisterControlRect(element)
		for key, value in pairs(fake.Registered) do
			if value == element then fake.Registered[key] = nil end
		end
	end
	function fake.LocalPosition(screenGui, x, y)
		local origin = screenGui.AbsolutePosition
		return UDim2.fromOffset(math.floor(x - origin.X), math.floor(y - origin.Y))
	end

	local clientChanged = Instance.new("BindableEvent")
	ctx.ClientChanged = clientChanged
	local client = {Changed = clientChanged.Event}
	function client.GetState()
		local state = ctx.ClientState
		return {Charges = state.Charges, Available = state.Available,
			ServerPending = state.ServerPending, Pending = state.Pending,
			CanRetry = state.CanRetry}
	end
	function client.Request(action) table.insert(ctx.Requests, "Request:" .. action) end
	function client.Retry() table.insert(ctx.Requests, "Retry") end

	local config = {Items = {SpeedPotion = {DurationSeconds = 6}, RouteMarker = {MaxActive = 3}}}

	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ctx.ReplicatedStorage
	local action = Instance.new("RemoteEvent")
	action.Name = "ZyntraAction"
	function action:FireServer(name, payload)
		table.insert(ctx.Fired, {Remote = "ZyntraAction", Name = name, Payload = payload,
			At = ctx.Clock})
	end
	action.Parent = remotes
	local profile = Instance.new("RemoteEvent")
	profile.Name = "ZyntraProfileChanged"
	rawset(profile, "OnClientEvent", signal())
	profile.Parent = remotes
	ctx.ProfileRemote = profile
	if options.MarkerRemote ~= false then
		local marker = Instance.new("RemoteEvent")
		marker.Name = "RouteMarker"
		rawset(marker, "OnClientEvent", signal())
		function marker:FireServer(name)
			table.insert(ctx.Fired, {Remote = "RouteMarker", Name = name, At = ctx.Clock})
		end
		marker.Parent = remotes
		ctx.MarkerRemote = marker
	end

	local style = bootModule(ctx, UIStyleSource)
	local modules = {UIDevice = fake, UIStyle = style, ProtectionClient = client,
		ZyntraConfig = config}
	for name in pairs(modules) do
		local node = Instance.new("ModuleScript")
		node.Name = name
		node.Parent = ctx.ReplicatedStorage
	end
	ctx.Style = style

	local game, workspace = ctx.game, ctx.workspace
	local task, script, os = ctx.task, ctx.script, ctx.os
	local require = function(node) return assert(modules[node.Name], node.Name) end
	HUDSource(game, workspace, task, script, os, require)

	ctx.gui = playerGui:FindFirstChild("ProtectionHUD")
	ctx.panel = ctx.gui:FindFirstChild("EquipmentPanel")
	ctx.caption = ctx.gui:FindFirstChild("EquipmentCaption")
	ctx.Rows = {
		ctx.gui:FindFirstChild("ProtectionUse"),
		ctx.gui:FindFirstChild("SpeedPotionUse"),
		ctx.gui:FindFirstChild("RouteMarkerPlace"),
	}
	-- The gui's own rectangle, which placePointer reads directly.
	local safe = ctx.Layout.Safe
	ctx.gui.AbsolutePosition = Vector2.new(safe.Left, safe.Top)
	ctx.gui.AbsoluteSize = Vector2.new(safe.Right - safe.Left, safe.Bottom - safe.Top)

	function ctx:Step(delta)
		self.Clock += (delta or 1 / 60)
		self.ServerTime += (delta or 1 / 60)
		self.RunService.RenderStepped:Fire(delta or 1 / 60)
	end
	function ctx:Key(keyName, processed)
		self.UserInputService.InputBegan:Fire({KeyCode = Enum.KeyCode[keyName],
			UserInputState = Enum.UserInputState.Begin}, processed == true)
	end
	function ctx:Release(keyName)
		self.UserInputService.InputEnded:Fire({KeyCode = Enum.KeyCode[keyName]})
	end
	function ctx:Tap(index)
		self.Rows[index].Activated:Fire({UserInputType = Enum.UserInputType.Touch})
	end
	function ctx:Text(index)
		local row = self.Rows[index]
		if self.Layout.IsTouch then return row.Text end
		return row:FindFirstChild("ItemName").Text .. " | " .. row:FindFirstChild("Readout").Text
	end
	ctx:Step()
	return ctx
end

do -- construction and the untouched shield identity
	local ctx = hudContext()
	check(ctx.gui ~= nil and ctx.gui.Name == "ProtectionHUD", "the ScreenGui keeps its name")
	check(ctx.gui.DisplayOrder == 1001 and ctx.gui.ResetOnSpawn == false,
		"display order and ResetOnSpawn are unchanged")
	check(ctx.Rows[1] ~= nil and ctx.Rows[1].Name == "ProtectionUse",
		"the shield button keeps the name every other surface knows it by")
	check(ctx.Rows[2] ~= nil and ctx.Rows[3] ~= nil,
		"the potion and marker rows are built under the same gui")
	check(ctx.panel ~= nil and ctx.panel:FindFirstChild("Eyebrow").Text == "EQUIPMENT",
		"the panel carries the EQUIPMENT eyebrow")
	check(ctx.panel:FindFirstChild("SignalAccent") ~= nil, "the panel carries the accent bar")
	check(ctx.panel:FindFirstChildOfClass("UICorner").CornerRadius.Offset
		== ctx.Style.Radius.Panel, "the panel's radius is UIStyle's panel radius")
	check(ctx.panel:FindFirstChildOfClass("UIStroke").Transparency
		== ctx.Style.Stroke.Transparency, "the panel's stroke is UIStyle's")
	check(ctx.panel:FindFirstChild("Eyebrow").TextColor3 == ctx.Style.Color.AccentText,
		"the eyebrow prints in the reference's eyebrow colour")
	check(ctx.Rows[1]:FindFirstChild("ItemName").TextColor3 == ctx.Style.Color.Title,
		"a row name prints in the reference's title colour")
	check(ctx.Rows[1]:FindFirstChild("ItemName").TextSize == ctx.Style.TextSize.Body,
		"a row name prints at the reference's 13px body size")
	check(ctx.Rows[1]:FindFirstChild("KeyChip"):FindFirstChildOfClass("UICorner")
		.CornerRadius.Offset == ctx.Style.Radius.Key, "the keycap uses UIStyle's key radius")
	check(ctx.Rows[1]:FindFirstChild("KeyChip").Font == ctx.Style.Font.Readout,
		"the keycap prints in the Code face")
end

do -- default inventory: one row, exactly what shipped
	local ctx = hudContext()
	check(ctx.gui.Enabled and ctx.Rows[1].Visible, "the shield row shows in a live round")
	check(not ctx.Rows[2].Visible and not ctx.Rows[3].Visible,
		"a player who owns nothing sees no potion and no marker row")
	check(ctx:Text(1) == "Entity Shield | 2 CHARGES", "the shield reads name and charges")
	check(ctx.Rows[1]:FindFirstChild("KeyChip").Text == "[Q]", "the shield's keycap is [Q]")
	check(ctx.panel.Visible and ctx.panel.Size.Y.Offset == 22 + 30 + 9,
		"the panel is one row tall")
end

do -- the visibility matrix over the server's attributes
	local cases = {
		{Potions = 0, Markers = 0, Placed = 0, Rows = {true, false, false}},
		{Potions = 1, Markers = 0, Placed = 0, Rows = {true, true, false}},
		{Potions = 0, Markers = 3, Placed = 0, Rows = {true, false, true}},
		{Potions = 2, Markers = 3, Placed = 1, Rows = {true, true, true}},
		{Potions = 0, Markers = 0, Placed = 2, Rows = {true, false, true}},
		{Potions = 0, Markers = 0, Placed = 0, Used = true, Rows = {true, true, false}},
		{Potions = 0, Markers = 0, Placed = 0, Boost = 3, Rows = {true, true, false}},
	}
	for index, case in ipairs(cases) do
		local ctx = hudContext()
		ctx.player:SetAttribute("ZyntraSpeedPotions", case.Potions)
		ctx.player:SetAttribute("ZyntraRouteMarkers", case.Markers)
		ctx.player:SetAttribute("RouteMarkersActive", case.Placed)
		if case.Used then ctx.player:SetAttribute("ZyntraSpeedPotionUsedThisRound", true) end
		if case.Boost then
			ctx.player:SetAttribute("ZyntraSpeedBoostUntil", ctx.ServerTime + case.Boost)
		end
		ctx:Step()
		for row = 1, 3 do
			check(ctx.Rows[row].Visible == case.Rows[row],
				"visibility case " .. index .. ": row " .. row .. " draws as stated")
		end
		check(ctx.panel.Size.Y.Offset
			== 22 + 9 + (case.Rows[2] and case.Rows[3] and 3 or (case.Rows[2] or case.Rows[3]) and 2 or 1)
				* 30 + ((case.Rows[2] and case.Rows[3] and 2 or (case.Rows[2] or case.Rows[3]) and 1 or 0)) * 3,
			"visibility case " .. index .. ": the panel is exactly as tall as its visible rows")
	end
end

do -- out of round nothing is drawn at all
	local ctx = hudContext()
	ctx.player:SetAttribute("ZyntraSpeedPotions", 2)
	ctx.player:SetAttribute("ZyntraRouteMarkers", 3)
	ctx.player:SetAttribute("InRound", false)
	ctx:Step()
	check(not ctx.gui.Enabled, "the whole HUD stands down out of round")
	for row = 1, 3 do
		check(not ctx.Rows[row].Visible, "row " .. row .. " is hidden out of round")
	end
	check(not ctx.panel.Visible, "the panel is hidden out of round")
end

do -- potion readouts and its disabled states
	local ctx = hudContext()
	ctx.player:SetAttribute("ZyntraSpeedPotions", 2)
	ctx:Step()
	check(ctx:Text(2) == "Speed Potion | 2 STORED", "a stored potion reads its count")
	check(ctx.Rows[2].Active, "a stored potion is pressable")
	check(ctx.Rows[2]:FindFirstChild("KeyChip").Text == "[T]", "the potion's keycap is [T]")

	ctx.player:SetAttribute("ZyntraSpeedBoostUntil", ctx.ServerTime + 4.24)
	ctx:Step(0)
	check(ctx:Text(2) == "Speed Potion | ACTIVE 4.2s", "an active potion counts down to a tenth")
	check(not ctx.Rows[2].Active, "an active potion cannot be used again")
	ctx:Step(1)
	check(ctx:Text(2) == "Speed Potion | ACTIVE 3.2s", "the countdown follows RenderStepped")
	ctx:Step(4)
	check(ctx:Text(2) == "Speed Potion | 2 STORED", "the readout returns to the count when it lapses")

	ctx.player:SetAttribute("ZyntraSpeedPotionUsedThisRound", true)
	ctx:Step()
	check(ctx:Text(2) == "Speed Potion | USED THIS ROUND", "a used potion says so")
	check(not ctx.Rows[2].Active, "a used potion is not pressable, even with stock")

	local empty = hudContext()
	empty.player:SetAttribute("ZyntraSpeedPotions", 0)
	empty.player:SetAttribute("ZyntraSpeedPotionUsedThisRound", true)
	empty:Step()
	check(not empty.Rows[2].Active, "an empty potion row is disabled")
end

do -- marker readouts
	local ctx = hudContext()
	ctx.player:SetAttribute("ZyntraRouteMarkers", 3)
	ctx.player:SetAttribute("RouteMarkersActive", 1)
	ctx:Step()
	check(ctx:Text(3) == "Route Markers | 3 STORED · 1/3 PLACED",
		"the marker row states stock and placed separately")
	check(ctx.Rows[3].Active, "a marker under the cap is placeable")
	check(ctx.Rows[3]:FindFirstChild("KeyChip").Text == "[X]", "the marker's keycap is [X]")
	ctx.player:SetAttribute("RouteMarkersActive", 3)
	ctx:Step()
	-- RouteMarkerService retires the oldest marker at the cap rather than
	-- refusing, so the row stays live and only the readout changes.
	check(ctx.Rows[3].Active, "at the cap the marker row is still pressable")
	check(ctx:Text(3) == "Route Markers | 3 STORED · 3/3 PLACED", "and states the cap")
	ctx.player:SetAttribute("RouteMarkersActive", 9)
	ctx:Step()
	check(ctx:Text(3) == "Route Markers | 3 STORED · 3/3 PLACED",
		"a placed count above the cap is clamped, never printed raw")
	ctx.player:SetAttribute("ZyntraRouteMarkers", 0/0)
	ctx:Step()
	check(ctx:Text(3) == "Route Markers | 0 STORED · 3/3 PLACED",
		"a NaN inventory attribute reads as nothing owned")
end

do -- no RouteMarker remote in the build: the row never appears
	local ctx = hudContext({MarkerRemote = false})
	ctx.player:SetAttribute("ZyntraRouteMarkers", 3)
	ctx:Step()
	check(not ctx.Rows[3].Visible, "without the remote there is no marker row to press")
	ctx:Key("X")
	check(#ctx.Fired == 0, "and X fires nothing")
end

do -- T and X: what may press, and what may not
	local ctx = hudContext()
	ctx.player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx.player:SetAttribute("ZyntraRouteMarkers", 2)
	ctx:Step()

	ctx:Key("T", true)
	check(#ctx.Fired == 0, "a game-processed T is ignored")
	ctx:Release("T")
	ctx:Key("T")
	check(#ctx.Fired == 1 and ctx.Fired[1].Remote == "ZyntraAction"
		and ctx.Fired[1].Name == "UseSpeedPotion", "T asks the server to use a potion")
	ctx:Key("T")
	check(#ctx.Fired == 1, "a held T cannot repeat while the key is still down")
	ctx:Release("T")
	ctx:Key("T")
	check(#ctx.Fired == 1, "and a re-press inside the rate window is dropped")
	ctx.Clock += 1.3
	ctx:Release("T")
	ctx:Key("T")
	check(#ctx.Fired == 2, "after the window a second use is allowed through")

	ctx:Key("X")
	check(#ctx.Fired == 3 and ctx.Fired[3].Remote == "RouteMarker"
		and ctx.Fired[3].Name == "place", "X asks the server to place a marker")
	ctx:Release("X")
	ctx:Key("X")
	check(#ctx.Fired == 3, "the marker has its own rate window")
	ctx.Clock += 1.6
	ctx:Release("X")
	ctx:Key("X")
	check(#ctx.Fired == 4, "which is 1.5s, not the potion's")

	check(#ctx.Requests == 0, "neither key ever touched ProtectionClient")
end

do -- the gates every press shares
	local gates = {"textbox", "selected", "modal", "dead", "escaped", "loading", "briefing"}
	for _, gate in ipairs(gates) do
		local ctx = hudContext()
		ctx.player:SetAttribute("ZyntraSpeedPotions", 1)
		ctx.player:SetAttribute("ZyntraRouteMarkers", 1)
		if gate == "textbox" then ctx.FocusedTextBox = Instance.new("TextBox")
		elseif gate == "selected" then ctx.GuiService.SelectedObject = Instance.new("TextButton")
		elseif gate == "modal" then ctx.Modal = true
		elseif gate == "dead" then ctx.humanoid.Health = 0
		elseif gate == "escaped" then ctx.player:SetAttribute("Escaped", true)
		elseif gate == "loading" then ctx.workspace:SetAttribute("RoundLoadingState", "cover")
		elseif gate == "briefing" then ctx.player:SetAttribute("DispatchBriefingOpen", true) end
		ctx:Step()
		ctx:Key("T")
		ctx:Key("X")
		ctx:Key("Q")
		check(#ctx.Fired == 0 and #ctx.Requests == 0, gate .. " blocks every equipment action")
	end
end

do -- the shield's own behaviour, unchanged
	local ctx = hudContext()
	ctx:Key("Q")
	check(#ctx.Requests == 1 and ctx.Requests[1] == "Request:UseProtection",
		"Q still asks ProtectionClient to use a charge")
	ctx:Release("Q")
	ctx.ClientState.Pending = {Action = "UseProtection"}
	ctx.ClientState.CanRetry = true
	ctx:Step()
	check(ctx:Text(1) == "Entity Shield | RETRY", "a retryable pending request reads RETRY")
	ctx:Key("Q")
	check(#ctx.Requests == 2 and ctx.Requests[2] == "Retry", "and Q retries it")
	ctx.ClientState.CanRetry = false
	ctx:Step()
	check(ctx:Text(1) == "Entity Shield | WAIT" and not ctx.Rows[1].Active,
		"a pending request that cannot be retried reads WAIT and is dead")
	ctx.ClientState.Pending = nil
	ctx.ClientState.Available = false
	ctx:Step()
	check(ctx:Text(1) == "Entity Shield | WAIT", "an unavailable inventory reads WAIT")
	ctx.ClientState.Available = true
	ctx.ClientState.Charges = 0
	ctx:Step()
	check(ctx:Text(1) == "Entity Shield | 0 CHARGES" and not ctx.Rows[1].Active,
		"zero charges is stated and not pressable")
	ctx.ClientState.Charges = 120
	ctx:Step()
	check(ctx:Text(1) == "Entity Shield | 99+ CHARGES", "the count still saturates at 99+")
	ctx.player:SetAttribute("PlayerProtectionActive", true)
	ctx.player:SetAttribute("PlayerProtectionExpiresAt", ctx.ServerTime + 4.2)
	ctx:Step(0)
	check(ctx:Text(1) == "SAFE | 4.2s", "an active shield is the SAFE readout")
	check(ctx.Rows[1]:FindFirstChild("ItemName").TextColor3 == ctx.Style.Color.Live,
		"and SAFE prints in the live colour")
	check(not ctx.Rows[1].Active, "an active shield cannot be spent again")
	check(#ctx.Fired == 0, "the shield never fires the equipment remotes")
end

do -- DPadDown keeps its shield binding
	local ctx = hudContext()
	ctx:Key("DPadDown")
	check(#ctx.Requests == 1, "D-PAD DOWN still presses the shield")
	ctx.UserInputService.WindowFocusReleased:Fire()
	ctx:Key("DPadDown")
	check(#ctx.Requests == 2, "losing focus clears the held-key latch")
end

do -- AUDIT_FIX_20260924: potion and marker have a pad key too
	local ctx = hudContext()
	ctx.player:SetAttribute("ZyntraSpeedPotions", 2)
	ctx.player:SetAttribute("ZyntraRouteMarkers", 2)
	ctx:Step()
	ctx:Key("DPadRight")
	check(#ctx.Fired == 1 and ctx.Fired[1].Remote == "ZyntraAction"
		and ctx.Fired[1].Name == "UseSpeedPotion", "D-PAD RIGHT uses a potion")
	ctx:Key("ButtonR2")
	check(#ctx.Fired == 2 and ctx.Fired[2].Remote == "RouteMarker"
		and ctx.Fired[2].Name == "place", "RT places a marker")
	ctx.Gamepad = true
	ctx.DeviceChanged:Fire()
	ctx:Step()
	check(ctx.Rows[2]:FindFirstChild("KeyChip").Text == "[D-PAD RIGHT]"
		and ctx.Rows[3]:FindFirstChild("KeyChip").Text == "[RT]",
		"and a live gamepad is shown those glyphs, not [T] / [X]")
end

do -- a tap is a press; a press from the wrong device is not
	local ctx = hudContext()
	ctx.player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx:Step()
	ctx:Tap(2)
	check(#ctx.Fired == 1, "tapping the potion row uses it")
	ctx.Rows[2].Activated:Fire({UserInputType = Enum.UserInputType.Keyboard})
	check(#ctx.Fired == 1, "an Activated from a keyboard is not a tap")
end

do -- refusals and error pushes become one transient caption
	local ctx = hudContext()
	ctx.player:SetAttribute("ZyntraRouteMarkers", 1)
	ctx:Step()
	check(not ctx.caption.Visible, "no caption until something is refused")
	ctx.MarkerRemote.OnClientEvent:Fire("refused", "NoMarkers")
	ctx:Step(0)
	check(ctx.caption.Visible and ctx.caption.Text == "NO MARKERS LEFT",
		"a known refusal maps to its short line")
	ctx:Step(2.1)
	check(not ctx.caption.Visible, "and it clears itself after two seconds")
	for reason, line in {RateLimited = "TOO SOON", Hiding = "NOT WHILE HIDING",
		NotInRound = "NOT NOW", NoCharacter = "NOT NOW", Unavailable = "NOT NOW"} do
		ctx.MarkerRemote.OnClientEvent:Fire("refused", reason)
		ctx:Step(0)
		check(ctx.caption.Text == line, "RouteMarkerService's " .. reason .. " reads as " .. line)
	end
	ctx.MarkerRemote.OnClientEvent:Fire("refused", "somethingnew")
	ctx:Step(0)
	check(ctx.caption.Text == "SOMETHINGNEW",
		"an unknown server reason is shown rather than swallowed")
	ctx.MarkerRemote.OnClientEvent:Fire("placed", 2)
	ctx:Step(0)
	check(ctx.caption.Text == "SOMETHINGNEW", "a successful placement needs no caption")

	ctx.ProfileRemote.OnClientEvent:Fire({}, "Not enough tokens", "error")
	ctx:Step(0)
	check(ctx.caption.Text == "Not enough tokens", "an error push is shown in the round")
	ctx.ProfileRemote.OnClientEvent:Fire({}, "Purchase complete", "success")
	ctx:Step(0)
	check(ctx.caption.Text == "Not enough tokens", "a non-error push is left to the terminal")
	ctx.player:SetAttribute("InRound", false)
	ctx:Step(0)
	ctx.ProfileRemote.OnClientEvent:Fire({}, "Out of round", "error")
	ctx:Step(0)
	check(ctx.caption.Text ~= "Out of round", "and nothing is captioned outside a round")
end

do -- TOUCH: three control rects, the plan's own slots, no panel chrome
	local ctx = hudContext({Layout = TOUCH_LAYOUT})
	ctx.player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx.player:SetAttribute("ZyntraRouteMarkers", 2)
	ctx.player:SetAttribute("RouteMarkersActive", 1)
	ctx:Step()
	check(not ctx.panel.Visible, "no panel chrome on a touch device")
	local keys = {"ProtectionUse", "SpeedPotionUse", "RouteMarkerPlace"}
	local seen = {}
	for index, key in ipairs(keys) do
		check(ctx.Device.Registered[key] == ctx.Rows[index],
			key .. " registers its own control rect")
		local slot = ctx.Layout.ControlPlan.Slots[key]
		check(ctx.Rows[index].Size.X.Offset == slot.Width
			and ctx.Rows[index].Size.Y.Offset == slot.Height,
			key .. " takes the plan's size")
		check(ctx.Rows[index].Position.X.Offset == -slot.Right
			and ctx.Rows[index].Position.Y.Offset == -slot.Bottom,
			key .. " takes the plan's inset")
		check(slot.Width >= 44 and slot.Height >= 44, key .. " is at least 44x44")
		local signature = slot.Right .. ":" .. slot.Bottom
		check(seen[signature] == nil, key .. " does not share a slot with another control")
		seen[signature] = true
	end
	check(ctx:Text(1) == "SHIELD\nx2", "the shield's touch caption is the shipped one")
	check(ctx:Text(2) == "POTION\nx1", "the potion's touch caption is short")
	check(ctx:Text(3) == "MARKER\n1/3", "the marker's touch caption is its placed count")
	check(ctx.Rows[1]:FindFirstChild("ItemName").Visible == false
		and ctx.Rows[1]:FindFirstChild("KeyChip").Visible == false,
		"the panel row's labels and keycap are not drawn in a touch slot")
	ctx:Tap(3)
	check(#ctx.Fired == 1 and ctx.Fired[1].Remote == "RouteMarker",
		"the touch slot places a marker")
end

do -- POINTER: the panel stays inside the safe area at every window
	for name, layout in pairs(POINTER_LAYOUTS) do
		local ctx = hudContext({Layout = layout})
		ctx.player:SetAttribute("ZyntraSpeedPotions", 1)
		ctx.player:SetAttribute("ZyntraRouteMarkers", 1)
		ctx:Step()
		local safe = layout.Safe
		local left = ctx.panel.Position.X.Offset + ctx.gui.AbsolutePosition.X
		local bottom = ctx.panel.Position.Y.Offset + ctx.gui.AbsolutePosition.Y
		local top = bottom - ctx.panel.Size.Y.Offset
		check(left >= safe.Left and left + ctx.panel.Size.X.Offset <= safe.Right,
			name .. ": the panel is inside the safe area horizontally")
		check(top >= safe.Top and bottom <= safe.Bottom,
			name .. ": the panel is inside the safe area vertically")
		check(next(ctx.Device.Registered) == nil,
			name .. ": a pointer device registers no touch control rect")
		-- The rows stack upward from the panel's bottom padding.
		local first = ctx.Rows[1].Position.Y.Offset
		local second = ctx.Rows[2].Position.Y.Offset
		check(second == first - (30 + 3), name .. ": rows stack upward by one row and gap")
		check(ctx.Rows[1].Position.X.Offset == ctx.panel.Position.X.Offset + 12,
			name .. ": rows sit on the panel's own left padding")
	end
end

do -- SPECTATING: the read-only mirror, unchanged
	local ctx = hudContext()
	ctx.player:SetAttribute("ZyntraSpeedPotions", 2)
	ctx.player:SetAttribute("ZyntraRouteMarkers", 2)
	local watched = Instance.new("Player")
	watched.Name = "Watched"
	watched.UserId = 77
	local body = Instance.new("Model")
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = body
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = body
	rawset(watched, "Character", body)
	watched:SetAttribute("InRound", true)
	watched:SetAttribute("PlayerProtectionActive", true)
	watched:SetAttribute("PlayerProtectionExpiresAt", ctx.ServerTime + 4.2)
	ctx.Watched = watched
	ctx.player:SetAttribute("Spectating", true)
	ctx.player:SetAttribute("SpectateTargetUserId", 77)
	ctx:Step(0)
	check(ctx.Rows[1].Text == "SAFE\n4.2s", "the mirror prints the watched player's timer")
	check(not ctx.Rows[1].Active and not ctx.Rows[1].AutoButtonColor,
		"the mirror is not pressable")
	check(not ctx.Rows[2].Visible and not ctx.Rows[3].Visible,
		"our own equipment is not drawn over someone else's shield")
	check(not ctx.panel.Visible and not ctx.caption.Visible,
		"and neither is the panel or the caption")
	check(next(ctx.Device.Registered) == nil, "the mirror takes no control slot")
	ctx:Key("Q")
	ctx:Key("T")
	check(#ctx.Requests == 0 and #ctx.Fired == 0, "and no key does anything while spectating")

	local touchCtx = hudContext({Layout = TOUCH_LAYOUT})
	touchCtx.Watched = watched
	touchCtx.player:SetAttribute("Spectating", true)
	touchCtx.player:SetAttribute("SpectateTargetUserId", 77)
	watched:SetAttribute("PlayerProtectionExpiresAt", touchCtx.ServerTime + 4.2)
	touchCtx:Step(0)
	check(next(touchCtx.Device.Registered) == nil,
		"a spectating touch client releases the control rects it held")
end

do -- keyboard glyphs are suppressed where they cannot be followed
	local ctx = hudContext()
	ctx.player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx.Device.Glyphs = true
	ctx.DeviceChanged:Fire()
	ctx:Step()
	for index = 1, 2 do
		check(not ctx.Rows[index]:FindFirstChild("KeyChip").Visible,
			"row " .. index .. " drops its keycap when glyphs are suppressed")
	end
end

do -- the keycap is sized from its own text, so a long binding cannot run over
	local ROW_WIDTH = 300 - 12 * 2
	-- A UDim2 of {1, -n} on a row this wide resolves to this many pixels.
	local function edges(row)
		local chip = row:FindFirstChild("KeyChip")
		local readout = row:FindFirstChild("Readout")
		local readoutRight = readout.Position.X.Offset + ROW_WIDTH + readout.Size.X.Offset
		local chipLeft = ROW_WIDTH - 10 - chip.Size.X.Offset
		return chip, readout, readoutRight, chipLeft
	end

	local short = hudContext()
	short:Step()
	local chip, _, readoutRight, chipLeft = edges(short.Rows[1])
	check(chip.Size.X.Offset == #chip.Text * 7 + 10, "the keycap is sized from its own text")
	check(readoutRight > 0 and readoutRight <= chipLeft - 8,
		"a [Q] keycap leaves the readout a real column and 8px of daylight")

	local ctx = hudContext()
	ctx.Gamepad = true
	ctx.DeviceChanged:Fire()
	ctx:Step()
	local wide, _, wideRight, wideChipLeft = edges(ctx.Rows[1])
	check(wide.Text == "[D-PAD DOWN]", "a live gamepad is served the gamepad glyph")
	check(wide.Size.X.Offset == #wide.Text * 7 + 10, "and the chip widens to hold it")
	check(wide.Size.X.Offset > chip.Size.X.Offset, "which is wider than the [Q] chip")
	check(wideRight > 0 and wideRight <= wideChipLeft - 8,
		"the readout gives the long chip its room rather than running under it")
end

do -- teardown
	local ctx = hudContext({Layout = TOUCH_LAYOUT})
	ctx:Step()
	check(next(ctx.Device.Registered) ~= nil, "the touch client holds control rects")
	local before = ctx.RunService.RenderStepped:Count()
	ctx.script.Destroying:Fire()
	check(next(ctx.Device.Registered) == nil, "destroying releases every control rect")
	check(ctx.RunService.RenderStepped:Count() == before - 1,
		"and disconnects the per-frame refresh")
	check(ctx.gui.Destroyed == true, "and destroys its ScreenGui")
	ctx.player:SetAttribute("ZyntraSpeedPotions", 4)
	ctx:Key("T")
	check(#ctx.Fired == 0, "a destroyed HUD fires nothing")
end

print("Equipment HUD: " .. checks .. " checks passed (real ProtectionHUD + real UIDevice plan, offline Luau)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")
    program = "".join([
        ENGINE,
        CONTEXT,
        BOOTS,
        wrap("UIDeviceSource", UIDEVICE.read_text(encoding="utf-8")),
        wrap("UIStyleSource", UISTYLE.read_text(encoding="utf-8")),
        wrap("HUDSource", HUD.read_text(encoding="utf-8")),
        PLAN_TESTS,
        HUD_TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="equipment-hud-") as directory:
        path = Path(directory) / "equipment_hud_test.luau"
        path.write_text(program, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
