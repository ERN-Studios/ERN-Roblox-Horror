"""Run the whole ProtectionHUD LocalScript, and the real UIDevice control plan,
in offline Luau under a fake DataModel.

Two halves, one process:

  1. THE CONTROL PLAN. The REAL ReplicatedStorage/UIDevice.ModuleScript.lua is
     loaded against a fake engine and asked for a layout at a matrix of forced
     viewports. The equipment slots added for Trello #101 are then measured
     against the module's own zones -- thumbstick, jump, top band, safe area --
     rather than against numbers copied out of it.

  2. THE HUD. The REAL StarterPlayer/StarterPlayerScripts/ProtectionHUD
     .LocalScript.lua is loaded whole, with the REAL RoundHud, ShopBinder,
     UIStyle and ZyntraDetectorVisual beside it, a fake ProtectionClient/
     ZyntraConfig, and remotes whose FireServer calls are captured. It runs in
     the shared HUD fake engine (tools/tests/hud_harness.luau) over the REAL
     Framewisp import of HUD_PC (tools/tests/fixtures/hud/framewisp-dump.HUD_PC
     .json), so the C chips it mounts are the staged templates. UIDevice is the
     harness's contract fake, and its Layout() returns the layout half 1
     computed from the REAL module, so the control slots the touch squares sit
     in are the shipping arithmetic, not a stand-in.

HUD_B1_CHIPS (owner, 2026-10-08; artifacts/hud-final-20261008/BUILD-PLAN.md 08
C and B1): the PC half now checks the chip row -- READY then 40 % after 6 s,
COOLDOWN numerals, ACTIVE "4.2" over "SAFE", EMPTY, REFUSED with one of four
fixed tags (raw server strings never printed), owned-only, all-empty hides,
keycaps per input, the hide-under-RoundUI gate and order 1001 over the kill
cam -- in place of the drawn EQUIPMENT panel the plan retires.

HUD_B2_TOUCH (owner, 2026-10-08; artifacts/hud-final-20261008/b2/B2-DESIGN.md
5): the plan half is re-baselined on the 4 + 4 grid's eight keys and the KIT
fan's slot, and the touch half runs over the REAL HUD_Touch import too: the
SHIELD cell's states, KIT and its fan (owned only, open, close, use), the fan
items' looks, KitFanOpen forced false, the refusal tag clear of the open fan,
the touch spectate drawing nothing, a missing or incomplete template.

No network, no Studio. Set LUAU_BIN to an official Luau interpreter.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from test_round_hud import HARNESS, SOURCES as HUD_MODULES, long_string, lua, trees

ROOT = Path(__file__).resolve().parents[2]
UIDEVICE = ROOT / "ReplicatedStorage/UIDevice.ModuleScript.lua"
HUD = ROOT / "StarterPlayer/StarterPlayerScripts/ProtectionHUD.LocalScript.lua"
NOISE = ROOT / "StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua"

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
-- HUD_B2_TOUCH (owner, 2026-10-08): the 4 + 4 grid's eight keys. POTION, MARKER
-- and SCAN are KIT fan items now: transient, never a slot of their own.
local ALL_KEYS = {"TouchJump", "TouchRunHold", "TouchSneakHold", "FlashlightPower",
	"ProtectionUse", "KitToggle", "TouchDropGlowstick", "TouchPOV"}

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
	check(smallest >= 44, row.Name .. ": every one of the eight slots clears the 44px floor")

	local collisions = 0
	for i = 1, #ALL_KEYS do
		for j = i + 1, #ALL_KEYS do
			if overlaps(rects[ALL_KEYS[i]], rects[ALL_KEYS[j]]) then collisions += 1 end
		end
	end
	check(collisions == 0, row.Name .. ": no two control slots overlap")

	local function inside(rect)
		return rect.Left >= layout.Safe.Left and rect.Right <= layout.Safe.Right
			and rect.Top >= layout.Safe.Top and rect.Bottom <= layout.Safe.Bottom
	end
	for _, key in ipairs(ALL_KEYS) do
		check(inside(rects[key]), row.Name .. ": " .. key .. " is inside the safe area")
		check(not overlaps(rects[key], layout.Zones.Thumbstick),
			row.Name .. ": " .. key .. " is clear of the thumbstick region")
	end
	local kitSlot = slots.KitToggle
	check(kitSlot.Width >= 44 and kitSlot.Height >= 44, row.Name .. ": KIT clears the 44px floor")
	-- The KIT fan's slot: present, one row above KIT, inside Safe, clear of the
	-- thumbstick and of every reserved slot.
	local fan = layout.ControlPlan.Fan
	check(fan ~= nil and fan.Width > 0 and fan.Height > 0, row.Name .. ": the plan states the KIT fan's slot")
	local fanRect = slotRect(layout, fan)
	check(inside(fanRect), row.Name .. ": the KIT fan is inside the safe area")
	check(fanRect.Bottom == rects.KitToggle.Top - layout.ControlPlan.Gap and fanRect.Right == rects.KitToggle.Right,
		row.Name .. ": the fan sits one gap above KIT, on KIT's right edge")
	check(not overlaps(fanRect, layout.Zones.Thumbstick), row.Name .. ": the open fan is clear of the thumbstick region")
	for _, key in ipairs(ALL_KEYS) do
		check(not overlaps(fanRect, rects[key]), row.Name .. ": the open fan covers no " .. key)
	end
	check(layout.KitFan ~= nil and layout.KitFan.Left == fanRect.Left and layout.KitFan.Top == fanRect.Top
		and layout.KitFan.Right == fanRect.Right and layout.KitFan.Bottom == fanRect.Bottom,
		row.Name .. ": Layout().KitFan is the fan slot in display coordinates")
end

do -- and a pointer layout still publishes the plan, for the HUD to ignore
	local layout = layoutAt(1280, 720, false)
	check(layout.IsTouch == false, "a forced pointer layout reports no touch form factor")
	check(layout.ControlPlan ~= nil and layout.ControlPlan.Slots.ProtectionUse ~= nil
		and layout.ControlPlan.Fan ~= nil, "a pointer layout still states the plan and its fan slot")
end

local POINTER_LAYOUTS = {}
for _, size in ipairs({{1280, 720}, {1920, 1080}, {956, 382}}) do
	POINTER_LAYOUTS[size[1] .. "x" .. size[2]] = layoutAt(size[1], size[2], false)
end
local TOUCH_LAYOUT = touchLayouts["Galaxy A06 landscape"]
'''


# Half 1 runs inside a `do` block of the HUD harness program, so its engine's
# names never meet the harness's; it hands its layouts and its check count out.
PLAN_EXPORT = r'''
LAYOUTS.Touch = TOUCH_LAYOUT
LAYOUTS.Phone = touchLayouts["handheld 844x390"]
LAYOUTS.Tablet = touchLayouts["tablet 1024x768"]
LAYOUTS.Pointer = POINTER_LAYOUTS
addChecks(checks)
'''

HUD_TESTS = r'''
-- ===========================================================================
-- 2. THE HUD, whole, in the HUD harness over the real HUD_PC import.
-- ===========================================================================
local TOUCH_LAYOUT = LAYOUTS.Touch
local PHONE, TABLET = LAYOUTS.Phone, LAYOUTS.Tablet
local POINTER = LAYOUTS.Pointer["1280x720"]
local P = {
	Ink = Color3.fromRGB(5, 9, 11), Tile = Color3.fromRGB(22, 29, 32), Line = Color3.fromRGB(38, 49, 52),
	RailTeal = Color3.fromRGB(68, 221, 196), Coral = Color3.fromRGB(242, 112, 95),
	Cream = Color3.fromRGB(242, 235, 219),
}
local CHIPS = {"Shield", "Potion", "Markers", "Scan"}
local GLYPH = "rbxasset://textures/ui/Controls/xbox"

local function hudContext(options)
	options = options or {}
	local layout = options.Layout or POINTER
	local ctx = context({touch = layout.IsTouch == true, gamepadEnabled = options.Gamepad == true,
		lastInput = options.Gamepad and "Gamepad" or "Keyboard", skip = options.Skip})
	ctx.Layout = layout
	ctx.Fired, ctx.Requests = {}, {}
	ctx.ClientState = {Charges = 2, Available = true, ServerPending = false, Pending = nil, CanRetry = false}

	-- UIDevice: the harness's contract fake, given this layout and a control-rect registry.
	local D = ctx.UIDevice
	D.Registered = {}
	function D.Layout() return ctx.Layout end
	function D.ScreenOwningModalOpen() return ctx.Modal == true end
	function D.RegisterControlRect(key, element)
		D.Registered[key] = element
		element:SetAttribute("UIDeviceControlKey", key)
	end
	function D.UnregisterControlRect(element)
		for key, value in pairs(D.Registered) do
			if value == element then D.Registered[key] = nil end
		end
	end

	-- The services ProtectionHUD asks for beyond the harness's own.
	local run = {RenderStepped = signal()}
	ctx.Run = run
	local guiService = newInstance("GuiService", "GuiService")
	guiService.MenuIsOpen = false
	ctx.GuiService = guiService
	local uis = ctx.UIS
	for _, name in ipairs({"InputBegan", "InputEnded", "WindowFocusReleased", "TextBoxFocused", "TextBoxFocusReleased"}) do
		uis[name] = signal()
	end
	function uis:GetFocusedTextBox() return ctx.FocusedTextBox end
	local players = {LocalPlayer = ctx.Player}
	function players:GetPlayerByUserId(id) return ctx.Watched and ctx.Watched.UserId == id and ctx.Watched or nil end
	local services = {Players = players, ReplicatedStorage = ctx.Storage, RunService = run,
		UserInputService = uis, GuiService = guiService}
	-- HUD_B2_TOUCH: the touch kit mounts after game.Loaded (critic C3); this place has loaded.
	local game = {GetService = function(_, name) return assert(services[name], "service " .. name) end,
		IsLoaded = function() return true end}
	-- A test may edit the staged templates before the script mounts them.
	if options.Prepare then options.Prepare(ctx) end

	-- A living, in-round body: the whole HUD is gated on this.
	local player = ctx.Player
	player.CharacterAdded, player.CharacterRemoving = signal(), signal()
	local character = newInstance("Model", "Character")
	character.ChildRemoved = signal()
	character.Parent = ctx.Workspace
	local humanoid = newInstance("Humanoid", "Humanoid")
	humanoid.Health = 100
	humanoid.HealthChanged = signal()
	humanoid.Parent = character
	newInstance("Part", "HumanoidRootPart").Parent = character
	player.Character = character
	ctx.humanoid = humanoid
	player:SetAttribute("InRound", true)
	player:SetAttribute("RoundEntryControlsReady", true)
	ctx.Workspace:SetAttribute("RoundActive", true)
	ctx.Workspace:SetAttribute("RoundLoadingState", "ready")

	-- ProtectionClient and ZyntraConfig, faked; the remotes record what they are sent.
	local client = {Changed = signal()}
	function client.GetState()
		local state = ctx.ClientState
		return {Charges = state.Charges, Available = state.Available, ServerPending = state.ServerPending,
			Pending = state.Pending, CanRetry = state.CanRetry}
	end
	function client.Request(action) table.insert(ctx.Requests, "Request:" .. action) end
	function client.Retry() table.insert(ctx.Requests, "Retry") end
	local config = {Items = {SpeedPotion = {DurationSeconds = 6}, RouteMarker = {MaxActive = 3}}}
	for _, name in ipairs({"ProtectionClient", "ZyntraConfig"}) do
		newInstance("ModuleScript", name).Parent = ctx.Storage
	end
	local remotes = newInstance("Folder", "Remotes")
	remotes.Parent = ctx.Storage
	local function remote(name, wanted)
		if wanted == false then return nil end
		local event = newInstance("RemoteEvent", name)
		event.FireServer = function(_, action) table.insert(ctx.Fired, {Remote = name, Name = action}) end
		event.Parent = remotes
		return event
	end
	remote("ZyntraAction")
	ctx.ProfileRemote = remote("ZyntraProfileChanged")
	ctx.MarkerRemote = remote("RouteMarker", options.MarkerRemote)
	ctx.DetectorRemote = remote("ZyntraDetector", options.Detector == true)

	-- The LocalScript itself, in its own environment on the harness clock.
	ctx.Script = newInstance("LocalScript", "ProtectionHUD")
	local fn = assert(loadstring(HUD_SOURCE, "=ProtectionHUD"))
	setfenv(fn, setmetatable({
		game = game, workspace = ctx.Workspace, script = ctx.Script, task = ctx.Task,
		Instance = Instance, Color3 = Color3, UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Enum = Enum,
		typeof = typeof, os = {clock = function() return ctx.Now end},
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
			table.insert(ctx.Warnings, table.concat(parts, " "))
		end,
		require = function(module)
			local name = module.Name
			if name == "UIDevice" then return ctx.UIDevice end
			if name == "ProtectionClient" then return client end
			if name == "ZyntraConfig" then return config end
			return ctx:Require(name)
		end,
	}, {__index = _G}))
	ctx.Task.spawn(fn)
	ctx:Flush()

	ctx.gui = ctx.PlayerGui:FindFirstChild("ProtectionHUD")
	-- HUD_B2_TOUCH: the touch kit. Rows[1] is the SHIELD cell, Rows[2..4] the KIT
	-- fan's POTION, MARKER and SCAN; Kit is the KIT cell, Fan the fan itself.
	ctx.Kit = ctx.gui:FindFirstChild("KitToggle")
	ctx.Fan = ctx.gui:FindFirstChild("KitFan")
	ctx.Rows = {ctx.gui:FindFirstChild("ProtectionUse")}
	for index, name in ipairs({"Fan_Potion", "Fan_Marker", "Fan_Scan"}) do
		ctx.Rows[index + 1] = ctx.Fan and find(ctx.Fan, name)
	end
	function ctx:Step(delta)
		self:Advance(delta or 1 / 60)
		run.RenderStepped:Fire(delta or 1 / 60)
		self:Flush()
	end
	function ctx:Key(keyName, processed)
		uis.InputBegan:Fire({KeyCode = Enum.KeyCode[keyName], UserInputState = Enum.UserInputState.Begin}, processed == true)
	end
	function ctx:Release(keyName) uis.InputEnded:Fire({KeyCode = Enum.KeyCode[keyName]}) end
	function ctx:Tap(index) self.Rows[index].Activated:Fire({UserInputType = Enum.UserInputType.Touch}) end
	function ctx:TapKit() self.Kit.Activated:Fire({UserInputType = Enum.UserInputType.Touch}) end
	-- A touch node is drawn: the gui is on and it and every ancestor are Visible.
	function ctx:Drawn(node) return node ~= nil and self.gui.Enabled and drawn(node) end
	function ctx:FanOpen() return self.Player:GetAttribute("KitFanOpen") == true end
	function ctx:Row() return self.gui:FindFirstChild("EquipmentPanel") end
	function ctx:Chip(name) return find(self.gui, "EquipmentPanel/Chip_" .. name) end
	function ctx:Part(name, path) return find(self:Chip(name), path) end
	-- Drawn: the gui is on and the chip and every ancestor are Visible.
	function ctx:Shown(name)
		local chip = self:Chip(name)
		return chip ~= nil and self.gui.Enabled and drawn(chip)
	end
	function ctx:Opacity() return 1 - self:Row().GroupTransparency end
	function ctx:Caption() return self.gui:FindFirstChild("EquipmentCaption") end
	function ctx:Tag() return find(self:Caption(), "Label").Text end
	ctx:Step()
	return ctx
end

-- One look of one chip, as BUILD-PLAN 08 C draws it.
local function look(ctx, name)
	local face = ctx:Part(name, "Face")
	return {Face = face, Stroke = face:FindFirstChildOfClass("UIStroke"), Icon = ctx:Part(name, "Icon").Visible,
		Cooldown = ctx:Part(name, "Cooldown").Visible and ctx:Part(name, "Cooldown").Text or nil,
		Active = ctx:Part(name, "ActiveTime").Visible and ctx:Part(name, "ActiveTime").Text or nil,
		Safe = ctx:Part(name, "ActiveTag").Visible,
		Badge = ctx:Part(name, "Badge").Visible and ctx:Part(name, "Badge/Count").Text or nil,
		Key = ctx:Part(name, "KeyChip").Visible and ctx:Part(name, "KeyChip/Key").Text or nil}
end

do -- construction: the gui, the C row from HUD_PC, the touch kit from HUD_Touch
	local ctx = hudContext()
	check(ctx.gui ~= nil and ctx.gui.Name == "ProtectionHUD", "the ScreenGui keeps its name")
	check(ctx.gui.DisplayOrder == 1001 and ctx.gui.ResetOnSpawn == false,
		"display order 1001 (over the kill cam at 1000) and ResetOnSpawn are unchanged")
	check(ctx.Rows[1] ~= nil and ctx.Rows[1].Name == "ProtectionUse",
		"the shield cell keeps the name every other surface knows it by")
	check(ctx.Rows[2] ~= nil and ctx.Rows[3] ~= nil and ctx.Rows[4] ~= nil,
		"the potion, marker and scan fan items are mounted under the same gui")
	local row = ctx:Row()
	check(row ~= nil and row.ClassName == "CanvasGroup" and row.Parent == ctx.gui,
		"PC mounts HUD_PC/EquipmentPanel as EquipmentPanel, in its Attention group, in this gui")
	check(row.Size == UDim2.fromOffset(280, 84), "at its design size, 4 x 64 + 3 x 8 by 84: " .. tostring(row.Size))
	for _, name in ipairs(CHIPS) do
		check(ctx:Chip(name) ~= nil, "the row carries Chip_" .. name)
		check(ctx:Chip(name).Selectable == false, "Chip_" .. name .. " is never a gamepad selection target")
	end
	local caption = ctx:Caption()
	check(caption ~= nil and find(caption, "Label") ~= nil and caption.Size == UDim2.fromOffset(200, 24),
		"the refusal tag is HUD_PC/EquipmentCaption, mounted as EquipmentCaption")
	check(not caption.Visible, "and it is hidden until something is refused")
	for index = 1, 4 do check(not ctx.Rows[index].Visible, "PC draws no touch cell " .. index) end
	check(find(ctx.gui, "Eyebrow") == nil and find(ctx.gui, "SignalAccent") == nil
		and find(ctx.Rows[1], "ItemName") == nil and find(ctx.Rows[1], "KeyChip") == nil,
		"the drawn EQUIPMENT panel and its rows are gone")
	check(ctx:Warned("missing template") == 0 and ctx:Warned("[ProtectionHUD]") == 0,
		"no template warning with HUD_PC staged")
end

do -- default inventory: the shield chip alone, READY, placed bottom-left
	local ctx = hudContext()
	check(ctx.gui.Enabled and ctx:Shown("Shield"), "the shield chip shows in a live round")
	check(not ctx:Shown("Potion") and not ctx:Shown("Markers") and not ctx:Shown("Scan"),
		"a player who owns nothing else sees only the shield")
	local shield = look(ctx, "Shield")
	check(shield.Badge == "2", "READY: the badge counts the charges")
	check(shield.Icon and shield.Cooldown == nil and shield.Active == nil and not shield.Safe,
		"READY: the icon and no numerals")
	check(shield.Face.BackgroundColor3 == P.Ink and near(shield.Face.BackgroundTransparency, 0.3),
		"READY: the template's own face")
	check(shield.Stroke.Color == P.Line and near(shield.Stroke.Thickness, 0.03125),
		"READY: the template's own 2 px Line stroke")
	check(shield.Key == "Q", "the shield's keycap is Q")
	local safe = POINTER.Safe
	local row = ctx:Row()
	check(row.AnchorPoint.X == 0 and row.AnchorPoint.Y == 1, "the row hangs from its bottom-left corner")
	check(row.Position == UDim2.fromOffset(math.floor(safe.Left + 24 + 232 + 8), math.floor(safe.Bottom - 24)),
		"bottom-left, 24 in, right of the 232 px flashlight widget with a gap of 8: " .. tostring(row.Position))
end

do -- the C visibility rule: 100 % on change or use, 40 % after 6 s
	local ctx = hudContext()
	check(near(ctx:Opacity(), 1), "READY shows at 100 % when the round starts")
	ctx:Step(5.8)
	check(near(ctx:Opacity(), 1), "still 100 % before 6 s")
	ctx:Step(0.3)
	check(near(ctx:Opacity(), 0.4), "then rests at 40 %: " .. ctx:Opacity())
	check(drawn(ctx:Row()), "resting is drawn, not hidden")
	ctx:Step(30)
	check(near(ctx:Opacity(), 0.4), "and stays there while nothing changes")
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx:Step()
	check(near(ctx:Opacity(), 1) and ctx:Shown("Potion"), "a change (a potion arrives) wakes it to 100 %")
	ctx:Step(6.1)
	check(near(ctx:Opacity(), 0.4), "and it rests again 6 s later")
	ctx:Key("T")
	check(#ctx.Fired == 1 and near(ctx:Opacity(), 1), "a use wakes it")
	ctx:Release("T")
	ctx:Step(6.1)
	check(near(ctx:Opacity(), 0.4), "and it rests after the use, too")
end

do -- ACTIVE: "4.2" over "SAFE", a 3 px RailTeal stroke, never dims
	local ctx = hudContext()
	ctx:Step(7)
	ctx.Player:SetAttribute("PlayerProtectionSource", "Reentry")
	ctx.Player:SetAttribute("PlayerProtectionActive", true)
	ctx.Player:SetAttribute("PlayerProtectionExpiresAt", ctx.Now + 9.24)
	ctx:Step(0)
	local shield = look(ctx, "Shield")
	check(shield.Active == "9.2" and shield.Safe, "ACTIVE reads the seconds over SAFE: " .. tostring(shield.Active))
	check(not shield.Icon and shield.Badge == nil, "ACTIVE replaces the icon and drops the badge")
	check(shield.Key == nil, "ACTIVE draws over the keycap's place, so the keycap goes")
	check(shield.Stroke.Color == P.RailTeal and near(shield.Stroke.Thickness, 0.03125 * 1.5),
		"ACTIVE is a RailTeal 3 px stroke (the template's 2 px, times 1.5)")
	check(near(ctx:Opacity(), 1), "ACTIVE wakes the row")
	ctx:Step(5)
	check(look(ctx, "Shield").Active == "4.2", "and counts down to a tenth: " .. tostring(look(ctx, "Shield").Active))
	ctx:Step(3)
	check(near(ctx:Opacity(), 1), "ACTIVE never dims, past the 6 s hold")
	ctx:Step(1.5)
	shield = look(ctx, "Shield")
	check(shield.Active == nil and shield.Icon and shield.Badge == "2" and shield.Key == "Q",
		"when it ends the chip is READY again, keycap and badge back")
	check(shield.Stroke.Color == P.Line and near(shield.Stroke.Thickness, 0.03125), "with the template's stroke")
	check(near(ctx:Opacity(), 1), "the end of ACTIVE is a change: 100 % again")
	ctx:Step(6.1)
	check(near(ctx:Opacity(), 0.4), "then the row rests")
end

do -- COOLDOWN: the seconds numeral in place of the icon, a dimmed face
	local ctx = hudContext({Detector = true})
	ctx.Player:SetAttribute("ZyntraOwnsEntityDetector", true)
	ctx:Step()
	check(ctx:Shown("Scan") and look(ctx, "Scan").Icon and look(ctx, "Scan").Key == "Z",
		"an owned detector is a READY chip with Z")
	check(look(ctx, "Scan").Badge == nil, "the detector has no count")
	ctx:Key("Z")
	check(#ctx.Fired == 1 and ctx.Fired[1].Remote == "ZyntraDetector" and ctx.Fired[1].Name == "scan",
		"Z asks the server for a scan")
	ctx:Release("Z")
	ctx.Player:SetAttribute("ZyntraDetectorReadyAt", ctx.Now + 11.2)
	ctx:Step(0)
	local scan = look(ctx, "Scan")
	check(scan.Cooldown == "12" and not scan.Icon, "COOLDOWN shows the whole seconds left in place of the icon")
	check(near(scan.Face.BackgroundTransparency, 0) and scan.Face.BackgroundColor3 == P.Ink,
		"COOLDOWN dims the face (opaque Ink where READY is translucent)")
	check(scan.Key == "Z", "COOLDOWN keeps its keycap")
	ctx:Step(1)
	check(look(ctx, "Scan").Cooldown == "11", "the numeral counts down")
	ctx:Step(6)
	check(near(ctx:Opacity(), 0.4), "a cooldown rests like READY")
	ctx:Step(4.5)
	scan = look(ctx, "Scan")
	check(scan.Cooldown == nil and scan.Icon and near(scan.Face.BackgroundTransparency, 0.3), "then READY again")
	check(near(ctx:Opacity(), 1), "and ready again is a change")
end

do -- EMPTY at 50 %, and all empty hides the row (the 08 C tile: ON CHANGE 100 % for 6 s, IDLE hidden)
	local ctx = hudContext()
	ctx.ClientState.Charges = 0
	ctx:Step()
	ctx:Step(0.4)
	check(drawn(ctx:Row()) and near(ctx:Opacity(), 1),
		"the last charge going is a change: the empty shield shows at 100 % first")
	ctx:Step(5.4)
	check(drawn(ctx:Row()) and near(ctx:Opacity(), 1), "for the whole 6 s hold")
	ctx:Step(0.3)
	ctx:Step(0.4)
	check(not drawn(ctx:Row()), "a lone empty shield: all empty then rests hidden, never at 40 %")
	ctx:Step(10)
	check(not drawn(ctx:Row()), "and stays hidden while nothing changes")
	ctx.Player:SetAttribute("RouteMarkersActive", 2)
	ctx:Step(1)
	check(drawn(ctx:Row()) and near(ctx:Opacity(), 1), "an empty marker chip beside it is a change: shown")
	ctx:Step(5.1)
	ctx:Step(0.4)
	check(not drawn(ctx:Row()), "still all empty: hidden again after its hold")
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx:Step()
	check(drawn(ctx:Row()) and near(ctx:Opacity(), 1), "one READY chip brings the row back at 100 %")
	local shield = look(ctx, "Shield")
	check(shield.Face.BackgroundColor3 == P.Tile and near(shield.Face.BackgroundTransparency, 0.5),
		"EMPTY: a Tile face at 50 %")
	local dimmed, parts = true, 0
	for _, part in ipairs(ctx:Part("Shield", "Icon"):GetDescendants()) do
		if part:IsA("GuiObject") then
			parts += 1
			if not near(part.BackgroundTransparency, 0.5) then dimmed = false end
		end
	end
	check(shield.Icon and parts > 0 and dimmed, "EMPTY: the icon at 50 %")
	check(shield.Badge == nil and shield.Key == "Q", "EMPTY: no badge, the keycap stays")
	check(ctx:Shown("Markers") and look(ctx, "Markers").Badge == nil
		and look(ctx, "Markers").Face.BackgroundColor3 == P.Tile, "the placed-out marker chip is EMPTY too")
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 0)
	ctx.Player:SetAttribute("ZyntraSpeedPotionUsedThisRound", true)
	ctx:Step()
	check(ctx:Chip("Potion").Visible and look(ctx, "Potion").Face.BackgroundColor3 == P.Tile,
		"a potion used this round is EMPTY")
	ctx:Step(0.4)
	check(drawn(ctx:Row()) and near(ctx:Opacity(), 1), "the use is shown at 100 %")
	ctx:Step(5.7)
	ctx:Step(0.4)
	check(not drawn(ctx:Row()), "and with that all empty again: hidden")
	ctx.ClientState.Charges = 3
	ctx:Step()
	check(drawn(ctx:Row()) and near(ctx:Opacity(), 1) and look(ctx, "Shield").Badge == "3",
		"charges arrive: shown again, the shield READY with its count")
	check(look(ctx, "Shield").Face.BackgroundColor3 == P.Ink, "and its face is the template's again")
end

do -- the visibility matrix over the server's attributes: only owned chips draw
	local cases = {
		{Potions = 0, Markers = 0, Placed = 0, Chips = {true, false, false}},
		{Potions = 1, Markers = 0, Placed = 0, Chips = {true, true, false}},
		{Potions = 0, Markers = 3, Placed = 0, Chips = {true, false, true}},
		{Potions = 2, Markers = 3, Placed = 1, Chips = {true, true, true}},
		{Potions = 0, Markers = 0, Placed = 2, Chips = {true, false, true}},
		{Potions = 0, Markers = 0, Placed = 0, Used = true, Chips = {true, true, false}},
		{Potions = 0, Markers = 0, Placed = 0, Boost = 3, Chips = {true, true, false}},
	}
	for index, case in ipairs(cases) do
		local ctx = hudContext()
		ctx.Player:SetAttribute("ZyntraSpeedPotions", case.Potions)
		ctx.Player:SetAttribute("ZyntraRouteMarkers", case.Markers)
		ctx.Player:SetAttribute("RouteMarkersActive", case.Placed)
		if case.Used then ctx.Player:SetAttribute("ZyntraSpeedPotionUsedThisRound", true) end
		if case.Boost then ctx.Player:SetAttribute("ZyntraSpeedBoostUntil", ctx.Now + case.Boost) end
		ctx:Step()
		for chip = 1, 3 do
			check(ctx:Shown(CHIPS[chip]) == case.Chips[chip],
				"visibility case " .. index .. ": Chip_" .. CHIPS[chip] .. " draws as stated")
		end
		check(not ctx:Shown("Scan"), "visibility case " .. index .. ": no detector owned, no scan chip")
	end
end

do -- out of round nothing is drawn at all
	local ctx = hudContext()
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 2)
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 3)
	ctx:Step(7)
	ctx.Player:SetAttribute("InRound", false)
	ctx:Step()
	check(not ctx.gui.Enabled, "the whole HUD stands down out of round")
	ctx:Step(0.4)
	check(not drawn(ctx:Row()), "and the row is hidden behind it")
	ctx.Player:SetAttribute("InRound", true)
	ctx:Step()
	check(ctx.gui.Enabled and drawn(ctx:Row()) and near(ctx:Opacity(), 1),
		"the next round wakes the row at 100 %, not at its old rest")
end

do -- BUILD-PLAN 1.4: never over PARTY DOWN or the results; order 1001 over the kill cam
	local ctx = hudContext()
	local jumpscare = newInstance("ScreenGui", "JumpscareGui")
	jumpscare.DisplayOrder = 1000
	jumpscare.Parent = ctx.PlayerGui
	check(ctx.gui.Enabled and ctx.gui.DisplayOrder > jumpscare.DisplayOrder,
		"alive in a capture, the shield draws over the kill cam")
	ctx:Key("Q")
	check(#ctx.Requests == 1, "and Q still cancels it")
	ctx:Release("Q")
	ctx.Player:SetAttribute("PartyDownCardOpen", true)
	ctx:Step()
	check(not ctx.gui.Enabled, "PARTY DOWN's card: the kit stands down")
	ctx:Key("Q")
	check(#ctx.Requests == 1, "and nothing presses under it")
	ctx:Release("Q")
	ctx.Player:SetAttribute("PartyDownCardOpen", false)
	ctx:Step()
	check(ctx.gui.Enabled, "the card gone, the kit is back")
	ctx.Workspace:SetAttribute("RoundActive", false)
	ctx:Step()
	check(not ctx.gui.Enabled, "the round over (the results): the kit stands down")
	check(ctx.gui.DisplayOrder == 1001, "and its order never moved")
end

do -- potion: count, ACTIVE seconds, used
	local ctx = hudContext()
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 2)
	ctx:Step()
	check(look(ctx, "Potion").Badge == "2", "a stored potion reads its count")
	-- HUD_B2_TOUCH: on PC "pressable" is read off T itself (the touch nodes are
	-- inert on PC). Each refused T below comes after the 1.2 s rate window, so
	-- it is the state that refuses it, never the window.
	local function pressT()
		ctx:Key("T")
		ctx:Release("T")
		return #ctx.Fired
	end
	check(pressT() == 1, "a stored potion is pressable")
	ctx:Advance(1.3)
	check(look(ctx, "Potion").Key == "T", "the potion's keycap is T")
	ctx.Player:SetAttribute("ZyntraSpeedBoostUntil", ctx.Now + 4.24)
	ctx:Step(0)
	local potion = look(ctx, "Potion")
	check(potion.Active == "4.2" and not potion.Safe,
		"an active potion counts down to a tenth, without the shield's SAFE")
	check(potion.Stroke.Color == P.RailTeal and potion.Key == nil, "in the ACTIVE look")
	check(pressT() == 1, "an active potion cannot be used again")
	ctx:Step(1)
	check(look(ctx, "Potion").Active == "3.2", "the countdown follows RenderStepped")
	ctx:Step(4)
	check(look(ctx, "Potion").Active == nil and look(ctx, "Potion").Badge == "2",
		"the chip returns to its count when it lapses")
	ctx.Player:SetAttribute("ZyntraSpeedPotionUsedThisRound", true)
	ctx:Step()
	check(look(ctx, "Potion").Face.BackgroundColor3 == P.Tile and look(ctx, "Potion").Badge == nil,
		"a used potion is EMPTY")
	check(pressT() == 1, "a used potion is not pressable, even with stock")

	local empty = hudContext()
	empty.Player:SetAttribute("ZyntraSpeedPotions", 0)
	empty.Player:SetAttribute("ZyntraSpeedPotionUsedThisRound", true)
	empty:Step()
	empty:Key("T")
	check(#empty.Fired == 0, "an empty potion row is disabled")
end

do -- markers: stock on the badge, pressable at the cap
	local ctx = hudContext()
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 3)
	ctx.Player:SetAttribute("RouteMarkersActive", 1)
	ctx:Step()
	check(look(ctx, "Markers").Badge == "3" and look(ctx, "Markers").Key == "X",
		"the marker chip counts its stock, keycap X")
	-- HUD_B2_TOUCH: pressable is read off X (past the 1.5 s window each time).
	local function pressX()
		ctx:Key("X")
		ctx:Release("X")
		ctx:Advance(1.6)
		return #ctx.Fired
	end
	check(pressX() == 1, "a marker under the cap is placeable")
	ctx.Player:SetAttribute("RouteMarkersActive", 3)
	ctx:Step()
	-- RouteMarkerService retires the oldest marker at the cap rather than
	-- refusing, so the chip stays live.
	check(pressX() == 2 and look(ctx, "Markers").Badge == "3", "at the cap the marker chip is still pressable")
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 0/0)
	ctx:Step()
	check(look(ctx, "Markers").Badge == nil and look(ctx, "Markers").Face.BackgroundColor3 == P.Tile,
		"a NaN inventory attribute reads as nothing owned: EMPTY")
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 12)
	ctx:Step()
	check(look(ctx, "Markers").Badge == "9+", "the round badge saturates at 9+")
end

do -- no RouteMarker remote in the build: the chip never appears
	local ctx = hudContext({MarkerRemote = false})
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 3)
	ctx:Step()
	check(not ctx:Shown("Markers"), "without the remote there is no marker chip to press")
	ctx:Key("X")
	check(#ctx.Fired == 0, "and X fires nothing")
end

do -- T and X: what may press, and what may not
	local ctx = hudContext()
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 2)
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
	ctx:Advance(1.3)
	ctx:Release("T")
	ctx:Key("T")
	check(#ctx.Fired == 2, "after the window a second use is allowed through")

	ctx:Key("X")
	check(#ctx.Fired == 3 and ctx.Fired[3].Remote == "RouteMarker"
		and ctx.Fired[3].Name == "place", "X asks the server to place a marker")
	ctx:Release("X")
	ctx:Key("X")
	check(#ctx.Fired == 3, "the marker has its own rate window")
	ctx:Advance(1.6)
	ctx:Release("X")
	ctx:Key("X")
	check(#ctx.Fired == 4, "which is 1.5s, not the potion's")

	check(#ctx.Requests == 0, "neither key ever touched ProtectionClient")
end

do -- the gates every press shares
	local gates = {"textbox", "selected", "modal", "dead", "escaped", "loading", "briefing", "partydown"}
	for _, gate in ipairs(gates) do
		local ctx = hudContext()
		ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
		ctx.Player:SetAttribute("ZyntraRouteMarkers", 1)
		if gate == "textbox" then ctx.FocusedTextBox = newInstance("TextBox", "Box")
		elseif gate == "selected" then ctx.GuiService.SelectedObject = newInstance("TextButton", "Selected")
		elseif gate == "modal" then ctx.Modal = true
		elseif gate == "dead" then ctx.humanoid.Health = 0
		elseif gate == "escaped" then ctx.Player:SetAttribute("Escaped", true)
		elseif gate == "loading" then ctx.Workspace:SetAttribute("RoundLoadingState", "cover")
		elseif gate == "briefing" then ctx.Player:SetAttribute("DispatchBriefingOpen", true)
		elseif gate == "partydown" then ctx.Player:SetAttribute("PartyDownCardOpen", true) end
		ctx:Step()
		ctx:Key("T")
		ctx:Key("X")
		ctx:Key("Q")
		check(#ctx.Fired == 0 and #ctx.Requests == 0, gate .. " blocks every equipment action")
	end
end

do -- the shield's own behaviour, unchanged; its chip follows it
	local ctx = hudContext()
	ctx:Key("Q")
	check(#ctx.Requests == 1 and ctx.Requests[1] == "Request:UseProtection",
		"Q still asks ProtectionClient to use a charge")
	ctx:Release("Q")
	ctx.ClientState.Pending = {Action = "UseProtection"}
	ctx.ClientState.CanRetry = true
	ctx:Step()
	-- HUD_B2_TOUCH: on PC "pressable" is read off Q itself (the shield has no
	-- rate window, so a Q that asks nothing is the state refusing it).
	local function pressQ()
		ctx:Key("Q")
		ctx:Release("Q")
		return #ctx.Requests
	end
	check(look(ctx, "Shield").Face.BackgroundColor3 == P.Ink,
		"a retryable pending request stays a READY chip")
	check(pressQ() == 2 and ctx.Requests[2] == "Retry", "pressable: Q retries it")
	ctx.ClientState.CanRetry = false
	ctx:Step()
	check(look(ctx, "Shield").Face.BackgroundColor3 == P.Tile and look(ctx, "Shield").Badge == "2"
		and pressQ() == 2, "a pending request that cannot be retried waits: dimmed, count kept, dead")
	check(drawn(ctx:Row()), "and waiting is not empty: the row stays")
	ctx.ClientState.Pending = nil
	ctx.ClientState.Available = false
	ctx:Step()
	check(look(ctx, "Shield").Face.BackgroundColor3 == P.Tile and pressQ() == 2,
		"an unavailable inventory waits too")
	ctx.ClientState.Available = true
	ctx.ClientState.Charges = 0
	ctx:Step()
	check(look(ctx, "Shield").Badge == nil and pressQ() == 2, "zero charges is EMPTY and not pressable")
	ctx.ClientState.Charges = 120
	ctx:Step()
	check(look(ctx, "Shield").Badge == "9+", "a big stock saturates the badge")
	ctx.Player:SetAttribute("PlayerProtectionActive", true)
	ctx.Player:SetAttribute("PlayerProtectionExpiresAt", ctx.Now + 4.2)
	ctx:Step(0)
	check(look(ctx, "Shield").Active == "4.2" and look(ctx, "Shield").Safe, "an active shield is 4.2 over SAFE")
	check(pressQ() == 2, "an active shield cannot be spent again")
	check(#ctx.Fired == 0, "the shield never fires the equipment remotes")
end

-- ===========================================================================
-- HUD_B2_TOUCH (owner, 2026-10-08): the touch kit, B2-DESIGN.md 5 and 2.3, over
-- the REAL HUD_Touch import. SHIELD and KIT are cells of the 4 + 4 grid, the
-- KIT fan holds POTION, MARKER and SCAN; the drawn squares are gone.
-- ===========================================================================
local SCALED_2PX = 0.038462 -- the template's ScaledSize stroke: 2 px of a 52 px cell

do -- TOUCH: the SHIELD cell in each shield state, flat (C5), no count (D9)
	local ctx = hudContext({Layout = PHONE})
	local shield = ctx.Rows[1]
	local stroke = shield:FindFirstChildOfClass("UIStroke")
	local glyph, label, cooldown = find(shield, "Glyph"), find(shield, "Label"), find(shield, "Cooldown")
	check(shield.ClassName == "TextButton" and glyph.ClassName == "Frame" and find(shield, "Face") == nil,
		"the SHIELD cell is the template's flat button: the root is the face, the diamond a Frame")
	check(ctx:Drawn(shield) and shield.Active, "READY: drawn and live")
	check(shield.AnchorPoint.X == 1 and shield.AnchorPoint.Y == 1 and shield.Position == UDim2.new(1, -12, 1, -72)
		and shield.Size == UDim2.fromOffset(52, 52),
		"844x390: a 52 px cell 12 in and 72 up from the safe corner: " .. tostring(shield.Position))
	check(shield.BackgroundColor3 == P.Ink and near(shield.BackgroundTransparency, 0.3), "READY: the template's face, Ink at 0.3")
	check(stroke.Color == P.Line and near(stroke.Thickness, SCALED_2PX), "READY: the template's 2 px Line stroke")
	check(glyph.Visible and near(glyph.BackgroundTransparency, 0), "READY: the diamond at full strength")
	check(label.Text == "SHIELD" and label.TextColor3 == P.Cream and near(label.TextTransparency, 0), "READY: SHIELD in Cream")
	check(not cooldown.Visible, "READY: no numeral; the template's 12 sample never shows")
	check(find(shield, "Badge") == nil, "and the touch shield carries no count (D9)")
	check(shield.AutoButtonColor == false and shield.Selectable == false, "never a gamepad selection target")

	ctx.ClientState.Pending = {Action = "UseProtection"}
	ctx.ClientState.CanRetry = true
	ctx:Step()
	check(shield.Active and shield.BackgroundColor3 == P.Ink, "a retryable pending request is a READY, live cell")
	ctx.ClientState.CanRetry = false
	ctx:Step()
	check(ctx:Drawn(shield) and not shield.Active and shield.BackgroundColor3 == P.Tile
		and near(shield.BackgroundTransparency, 0.5), "WAIT: drawn, Tile at 0.5, not live")
	check(near(glyph.BackgroundTransparency, 0.5) and near(label.TextTransparency, 0.5), "WAIT: the diamond and SHIELD at 0.5")
	ctx.ClientState.Pending = nil
	ctx.ClientState.Charges = 0
	ctx:Step()
	check(ctx:Drawn(shield) and not shield.Active and shield.BackgroundColor3 == P.Tile
		and near(shield.BackgroundTransparency, 0.5), "EMPTY at x0: drawn, Tile at 0.5, not live")
	ctx.ClientState.Charges = 2
	ctx:Step()
	check(shield.Active and shield.BackgroundColor3 == P.Ink and near(glyph.BackgroundTransparency, 0)
		and near(label.TextTransparency, 0), "charges back: READY, every dimmed value restored")

	ctx.Player:SetAttribute("PlayerProtectionActive", true)
	ctx.Player:SetAttribute("PlayerProtectionExpiresAt", ctx.Now + 4.24)
	ctx:Step(0)
	check(cooldown.Visible and cooldown.Text == "4.2" and cooldown.TextColor3 == P.RailTeal, "ACTIVE: 4.2 in RailTeal")
	check(label.Text == "SAFE" and label.TextColor3 == P.RailTeal, "ACTIVE: the label reads SAFE in RailTeal")
	check(not glyph.Visible, "ACTIVE: the numeral replaces the diamond")
	check(stroke.Color == P.RailTeal and near(stroke.Thickness, SCALED_2PX * 1.5), "ACTIVE: a RailTeal 3 px stroke")
	check(not shield.Active, "ACTIVE: it cannot be spent again")
	ctx:Step(1)
	check(cooldown.Text == "3.2", "and counts down to a tenth")
	ctx:Step(4)
	check(not cooldown.Visible and glyph.Visible and label.Text == "SHIELD" and label.TextColor3 == P.Cream
		and stroke.Color == P.Line and near(stroke.Thickness, SCALED_2PX), "when it ends: READY, the template look")

	ctx:Tap(1)
	check(#ctx.Requests == 1 and ctx.Requests[1] == "Request:UseProtection", "a tap on SHIELD asks ProtectionClient, as Q does")
	shield.Activated:Fire({UserInputType = Enum.UserInputType.Keyboard})
	check(#ctx.Requests == 1, "an Activated from a keyboard is not a tap")
	shield.Activated:Fire({UserInputType = Enum.UserInputType.MouseButton1})
	check(#ctx.Requests == 2, "the Studio ForceTouchUI mouse is")
	ctx.ProfileRemote.OnClientEvent:Fire({}, "No charges.", "error")
	ctx:Step(0)
	check(stroke.Color == P.Coral, "REFUSED: an error answering a SHIELD tap strokes the cell Coral")
	check(ctx:Caption().Visible and ctx:Tag() == "NOT NOW", "with the tag, never the raw string")
	ctx:Step(2.1)
	check(stroke.Color == P.Line and not ctx:Caption().Visible, "for the 2 s window only")
end

do -- TOUCH: KIT and its fan (14 A + C): owned items only; a tap opens it, a second tap or a use closes it
	local ctx = hudContext({Layout = PHONE})
	local kit, fan = ctx.Kit, ctx.Fan
	local kitStroke = kit:FindFirstChildOfClass("UIStroke")
	local glyph, label = find(kit, "Glyph"), find(kit, "Label")
	check(ctx.UIDevice.Registered.ProtectionUse == ctx.Rows[1] and ctx.UIDevice.Registered.KitToggle == kit,
		"touch reserves SHIELD as ProtectionUse and KIT as KitToggle")
	local reserved = 0
	for _ in pairs(ctx.UIDevice.Registered) do reserved += 1 end
	check(reserved == 2, "and nothing else: the fan items are never reserved")
	for index = 2, 4 do
		local item = ctx.Rows[index]
		check(not find(item, "Badge").Visible and not find(item, "Cooldown").Visible,
			item.Name .. ": the template's 2 and 12 samples are not visible after mount")
		check(item.AutoButtonColor == false and item.Selectable == false and not item.Active, item.Name .. " is inert until drawn")
	end
	check(not ctx:Drawn(kit) and not kit.Active, "nothing to fan: KIT is neither drawn nor live (D7)")
	check(kit.AnchorPoint.X == 1 and kit.AnchorPoint.Y == 1 and kit.Position == UDim2.new(1, -72, 1, -72)
		and kit.Size == UDim2.fromOffset(52, 52), "and it is seated in its slot all the same: 52 at (72, 72)")
	check(not ctx:Drawn(fan) and not ctx:FanOpen(), "the fan is closed")

	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx:Step()
	check(ctx:Drawn(kit) and kit.Active, "one owned item: KIT is drawn and live")
	check(kit.BackgroundColor3 == P.Ink and near(kit.BackgroundTransparency, 0.3) and kitStroke.Color == P.Line,
		"closed: the template face and stroke")
	check(glyph.Text == "+" and glyph.TextColor3 == P.Cream and label.Text == "KIT" and label.TextColor3 == P.Cream,
		"closed: + over KIT")
	check(not ctx:Drawn(fan) and not ctx:FanOpen(), "and the fan starts closed")
	kit.Activated:Fire({UserInputType = Enum.UserInputType.Keyboard})
	check(not ctx:FanOpen(), "an Activated from a keyboard does not open it")

	ctx:TapKit()
	check(ctx:FanOpen() and ctx:Drawn(fan), "a tap opens the fan: KitFanOpen is true and the fan is drawn")
	check(kit.BackgroundColor3 == P.RailTeal and near(kit.BackgroundTransparency, 0) and kitStroke.Color == P.RailTeal,
		"open: a RailTeal face and a RailTeal edge (C7)")
	check(glyph.Text == "\u{D7}" and glyph.TextColor3 == P.Ink and label.TextColor3 == P.Ink, "open: the cross over KIT, in Ink")
	check(fan.AnchorPoint.X == 1 and fan.AnchorPoint.Y == 1 and fan.Position == UDim2.new(1, -72, 1, -132)
		and fan.Size == UDim2.fromOffset(172, 52), "the fan is 172x52, one gap above KIT, on KIT's right edge")
	check(ctx:Drawn(ctx.Rows[2]) and ctx.Rows[2].Active, "the owned potion is drawn and live")
	check(not ctx:Drawn(ctx.Rows[3]) and not ctx.Rows[3].Active and not ctx:Drawn(ctx.Rows[4]) and not ctx.Rows[4].Active,
		"the marker and the scan are not owned, so not drawn (owned only)")
	check(find(fan, "Items"):FindFirstChildOfClass("UIListLayout").HorizontalAlignment == Enum.HorizontalAlignment.Right,
		"the items pack toward KIT (D2)")
	check(find(fan, "Fan_Scan/Icon/Items"):FindFirstChildOfClass("UIListLayout").HorizontalAlignment
		== Enum.HorizontalAlignment.Left, "SCAN's own icon list is left alone (C15)")
	check(find(ctx.Rows[2], "Badge").Visible and find(ctx.Rows[2], "Badge/Count").Text == "1", "the potion's badge counts it")

	ctx:TapKit()
	check(not ctx:FanOpen() and not ctx:Drawn(fan), "a second tap closes it")
	check(kit.BackgroundColor3 == P.Ink and glyph.Text == "+" and kitStroke.Color == P.Line, "and KIT is closed again")
	ctx:TapKit()
	ctx:Tap(2)
	check(#ctx.Fired == 1 and ctx.Fired[1].Remote == "ZyntraAction" and ctx.Fired[1].Name == "UseSpeedPotion",
		"pressing a fan item fires its action")
	ctx:Step()
	check(not ctx:FanOpen() and not ctx:Drawn(fan), "and closes the fan")
	ctx:Advance(1.3)
	ctx:TapKit()
	ctx.Rows[2].Activated:Fire({UserInputType = Enum.UserInputType.Keyboard})
	check(#ctx.Fired == 1 and ctx:FanOpen(), "an Activated from a keyboard is not a tap (past the rate window)")
	ctx.Rows[2].Activated:Fire({UserInputType = Enum.UserInputType.MouseButton1})
	check(#ctx.Fired == 2 and not ctx:FanOpen(), "the ForceTouchUI mouse is")
	ctx.Player:SetAttribute("KitFanOpen", true)
	ctx:Step(0)
	check(ctx:Drawn(fan) and ctx:Drawn(ctx.Rows[2]) and kit.BackgroundColor3 == P.RailTeal,
		"the attribute alone opens the fan, as UIRegression's KitFanMatrix writes it (C13)")
end

do -- D7: KIT follows what the fan DRAWS, not what it can use: a cooling, running or used item keeps KIT up
	local ctx = hudContext({Layout = PHONE, Detector = true})
	ctx.Player:SetAttribute("ZyntraOwnsEntityDetector", true)
	ctx.Player:SetAttribute("ZyntraDetectorReadyAt", ctx.Now + 29.5)
	ctx:Step(0)
	check(ctx:Drawn(ctx.Kit) and ctx.Kit.Active, "a scan cooling down (drawn, not usable) keeps KIT drawn and live")
	ctx:TapKit()
	check(ctx:FanOpen() and ctx:Drawn(ctx.Rows[4]) and not ctx.Rows[4].Active
		and find(ctx.Rows[4], "Cooldown").Text == "30", "and the open fan shows its countdown")

	local used = hudContext({Layout = PHONE})
	used.Player:SetAttribute("ZyntraSpeedPotions", 1)
	used.Player:SetAttribute("ZyntraSpeedBoostUntil", used.Now + 4)
	used:Step(0)
	check(used:Drawn(used.Kit) and used.Kit.Active, "a running potion (ACTIVE, not usable) keeps KIT drawn and live")
	used.Player:SetAttribute("ZyntraSpeedPotions", 0)
	used.Player:SetAttribute("ZyntraSpeedBoostUntil", 0)
	used.Player:SetAttribute("ZyntraSpeedPotionUsedThisRound", true)
	used:Step()
	check(used:Drawn(used.Kit), "and so does the potion used this round (EMPTY, still drawn)")
end

do -- TOUCH: the fan items' looks (2.3): counts, 9+, the stored marker count, potion ACTIVE and USED, SCAN
	local ctx = hudContext({Layout = PHONE, Detector = true})
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 2)
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 12)
	ctx.Player:SetAttribute("RouteMarkersActive", 1)
	ctx.Player:SetAttribute("ZyntraOwnsEntityDetector", true)
	ctx:Step()
	ctx:TapKit()
	local potion, marker, scan = ctx.Rows[2], ctx.Rows[3], ctx.Rows[4]
	local function badge(item) return find(item, "Badge").Visible and find(item, "Badge/Count").Text or nil end
	local function cooldown(item) return find(item, "Cooldown").Visible and find(item, "Cooldown").Text or nil end
	check(ctx:Drawn(potion) and ctx:Drawn(marker) and ctx:Drawn(scan), "all three owned items are drawn")
	check(potion.Active and marker.Active and scan.Active, "and live")
	check(badge(potion) == "2" and badge(marker) == "9+", "the badges count the stock, saturating at 9+")
	check(badge(scan) == nil, "the detector has no count")
	check(find(potion, "Label").Text == "POTION" and find(marker, "Label").Text == "MARKER"
		and find(scan, "Label").Text == "SCAN", "POTION, MARKER, SCAN")
	check(cooldown(potion) == nil and cooldown(marker) == nil and cooldown(scan) == nil, "READY: no numerals")
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 3)
	ctx:Step()
	check(badge(marker) == "3", "MARKER reads its stored count, like the PC chip, never the placed 1/3")

	ctx.Player:SetAttribute("ZyntraSpeedBoostUntil", ctx.Now + 4.24)
	ctx:Step(0)
	local potionStroke = potion:FindFirstChildOfClass("UIStroke")
	check(cooldown(potion) == "4.2" and find(potion, "Cooldown").TextColor3 == P.RailTeal, "a running potion: 4.2 in RailTeal")
	check(find(potion, "Label").Text == "POTION" and find(potion, "Label").TextColor3 == P.Cream,
		"it keeps POTION (SAFE is the shield's word)")
	check(not find(potion, "Icon").Visible and badge(potion) == nil, "the numeral replaces the icon, and the badge goes")
	check(potionStroke.Color == P.RailTeal and near(potionStroke.Thickness, SCALED_2PX * 1.5), "a RailTeal 3 px stroke")
	check(not potion.Active, "a running potion cannot be used again")
	ctx:Step(5)
	check(cooldown(potion) == nil and badge(potion) == "2" and potion.Active and potionStroke.Color == P.Line,
		"it lapses back to READY with its count")
	ctx.Player:SetAttribute("ZyntraSpeedPotionUsedThisRound", true)
	ctx:Step()
	check(ctx:Drawn(potion) and not potion.Active and potion.BackgroundColor3 == P.Tile
		and near(potion.BackgroundTransparency, 0.5) and badge(potion) == nil, "USED: EMPTY, Tile at 0.5, no badge, not live")
	local dimmed, parts = true, 0
	for _, part in ipairs(find(potion, "Icon"):GetDescendants()) do
		if part:IsA("GuiObject") then
			parts += 1
			if not near(part.BackgroundTransparency, 0.5) then dimmed = false end
		end
	end
	check(parts == 3 and dimmed and near(find(potion, "Label").TextTransparency, 0.5),
		"USED: every icon Frame and the label at 0.5 (Frame transparency does not cascade, C5)")

	ctx.Player:SetAttribute("ZyntraDetectorReadyAt", ctx.Now + 11.2)
	ctx:Step(0)
	check(cooldown(scan) == "12" and find(scan, "Cooldown").TextColor3 == P.Cream and not find(scan, "Icon").Visible,
		"SCAN COOLDOWN: the whole seconds left in Cream, in place of the icon")
	check(find(scan, "Label").Text == "SCAN" and not scan.Active, "still SCAN, and not live")
	ctx.Player:SetAttribute("ZyntraDetectorReadyAt", ctx.Now + 40)
	ctx.Player:SetAttribute("ZyntraDetectorReadingUntil", ctx.Now + 30)
	ctx.Player:SetAttribute("ZyntraDetectorReading", "LOW")
	ctx:Step(0)
	check(find(scan, "Label").Text == "HIDE" and scan.Active, "a live reading: SCAN reads HIDE and puts it away")
	ctx:Tap(4)
	check(ctx.Player:GetAttribute("ZyntraDetectorStowed") == true and #ctx.Fired == 0, "the tap stows the device, firing nothing")
	check(not ctx:FanOpen(), "and closes the fan")
	ctx:TapKit()
	check(find(scan, "Label").Text == "SHOW", "stowed, it reads SHOW")
end

do -- TOUCH: a refused fan item, and the tag clear of the open fan (critic C9)
	local ctx = hudContext({Layout = PHONE})
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 2)
	ctx:Step()
	ctx:TapKit()
	ctx:Tap(3)
	check(#ctx.Fired == 1 and ctx.Fired[1].Remote == "RouteMarker" and ctx.Fired[1].Name == "place",
		"the marker item places a marker")
	check(not ctx:FanOpen(), "and closes the fan")
	ctx.MarkerRemote.OnClientEvent:Fire("refused", "RateLimited")
	ctx:Step(0)
	local area, kitFan = PHONE.ModalArea, PHONE.KitFan
	local caption = ctx:Caption()
	local x = math.floor((area.Left + area.Right) * 0.5)
	check(caption.Visible and ctx:Tag() == "TOO SOON", "a refusal tag shows on touch")
	check(caption.AnchorPoint.X == 0.5 and caption.Position == UDim2.fromOffset(x, math.floor(area.Bottom)),
		"fan closed: in the old caption's place, ModalArea's bottom centre")
	check(area.Bottom > kitFan.Top - 8, "(844x390: that bottom lies on the open fan's rows)")
	ctx:TapKit()
	check(ctx.Rows[3]:FindFirstChildOfClass("UIStroke").Color == P.Coral, "the refused marker item is stroked Coral")
	check(ctx.Rows[1]:FindFirstChildOfClass("UIStroke").Color == P.Line, "and only that cell")
	check(caption.Position == UDim2.fromOffset(x, math.floor(kitFan.Top - 8)), "fan open: the tag stands 8 above the fan")
	ctx:TapKit()
	ctx:Step(0)
	check(caption.Position == UDim2.fromOffset(x, math.floor(area.Bottom)), "fan closed again: so does the tag's place")
end

do -- HUD_B3 (owner, 2026-10-08): no re-entry grace sentence; Round HUD's GRACE marker replaces it (B3-DESIGN 5)
	for _, layout in ipairs({POINTER, PHONE}) do
		local ctx = hudContext({Layout = layout})
		ctx:Step()
		ctx.Player:SetAttribute("PlayerProtectionSource", "Reentry")
		ctx.Player:SetAttribute("PlayerProtectionActive", true)
		ctx.Player:SetAttribute("PlayerProtectionExpiresAt", ctx.Now + 10)
		ctx:Step(0)
		local tag = layout.IsTouch and " (touch)" or " (PC)"
		check(ctx.gui.Enabled and ctx.gui:FindFirstChild("ReentryGrace") == nil, "re-entry grace draws no ReentryGrace" .. tag)
		local labels = 0
		for _, node in ipairs(ctx.gui:GetDescendants()) do
			if node:IsA("TextLabel") then
				labels += 1
				check(not string.find(string.lower(node.Text), "invisible", 1, true),
					"no label says invisible" .. tag .. ": " .. node.Name)
			end
		end
		check(labels > 0, "the scan saw the HUD's labels" .. tag)
	end
end

do -- KitFanOpen is forced false wherever the fan cannot be open, written once on the change
	for _, gate in ipairs({"modal", "level4card", "dead", "spectating", "partydown", "lastitem", "pc"}) do
		local ctx = hudContext({Layout = PHONE})
		ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
		ctx:Step()
		ctx:TapKit()
		check(ctx:FanOpen() and ctx:Drawn(ctx.Fan), gate .. ": the fan is open first")
		local writes = 0
		ctx.Player:GetAttributeChangedSignal("KitFanOpen"):Connect(function() writes += 1 end)
		if gate == "modal" then ctx.Modal = true
		elseif gate == "level4card" then
			-- covered() reads it under a live RoundGui, which every round has.
			newInstance("ScreenGui", "RoundGui").Parent = ctx.PlayerGui
			ctx.Player:SetAttribute("Level4CardOpen", true)
		elseif gate == "dead" then ctx.humanoid.Health = 0
		elseif gate == "spectating" then ctx.Player:SetAttribute("Spectating", true)
		elseif gate == "partydown" then ctx.Player:SetAttribute("PartyDownCardOpen", true)
		elseif gate == "lastitem" then ctx.Player:SetAttribute("ZyntraSpeedPotions", 0)
		else ctx:Device({Touch = false, Layout = POINTER}) end
		ctx:Step()
		check(ctx.Player:GetAttribute("KitFanOpen") == false, gate .. " forces KitFanOpen false")
		check(not drawn(ctx.Fan) and not ctx.Rows[2].Active and not drawn(ctx.Kit) and not ctx.Kit.Active,
			gate .. ": the fan and KIT are neither drawn nor live")
		local settled = writes
		for _ = 1, 5 do ctx:Step() end
		check(settled == 1 and writes == settled, gate .. ": written once, on the change, never every frame")
	end
	local ctx = hudContext({Layout = PHONE})
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx:Step()
	ctx:TapKit()
	ctx.Modal = true
	ctx:Step()
	ctx.Modal = false
	ctx:Step()
	check(ctx:Drawn(ctx.Kit) and not ctx:FanOpen() and not ctx:Drawn(ctx.Fan), "the modal gone: KIT is back, the fan stays closed")
end

do -- DPadDown keeps its shield binding
	local ctx = hudContext()
	ctx:Key("DPadDown")
	check(#ctx.Requests == 1, "D-PAD DOWN still presses the shield")
	ctx.UIS.WindowFocusReleased:Fire()
	ctx:Key("DPadDown")
	check(#ctx.Requests == 2, "losing focus clears the held-key latch")
end

do -- PAD: the keycaps are the engine glyphs PHUD binds, and every chip fires from the pad
	local ctx = hudContext({Gamepad = true, Detector = true})
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 1)
	ctx.Player:SetAttribute("ZyntraOwnsEntityDetector", true)
	ctx:Step()
	for index, pad in ipairs({"DPadDown", "DPadRight", "ButtonR2", "DPadLeft"}) do
		local chip = ctx:Part(CHIPS[index], "KeyChip")
		local glyph = find(chip, "GlyphSlot"):FindFirstChildWhichIsA("ImageLabel", true)
		check(chip.Visible and glyph ~= nil and glyph.Visible and glyph.Image == GLYPH .. pad .. ".png",
			"Chip_" .. CHIPS[index] .. " shows the " .. pad .. " glyph")
		check(find(chip, "Key").Text == "", "Chip_" .. CHIPS[index] .. ": the letter gives way to the glyph")
	end
	for _, pad in ipairs({"DPadRight", "ButtonR2", "DPadLeft", "DPadDown"}) do ctx:Key(pad) end
	check(#ctx.Fired == 3 and ctx.Fired[1].Name == "UseSpeedPotion" and ctx.Fired[2].Name == "place"
		and ctx.Fired[3].Name == "scan", "D-pad right, RT and D-pad left use the potion, a marker and the scan")
	check(#ctx.Requests == 1, "and D-pad down the shield")
	ctx:Device({LastInput = "Keyboard"})
	for index, key in ipairs({"Q", "T", "X", "Z"}) do
		check(look(ctx, CHIPS[index]).Key == key, "back on the keyboard Chip_" .. CHIPS[index] .. " reads " .. key)
	end
end

do -- a tap is a press; a click on a chip is a press; a press from the wrong device is not
	local ctx = hudContext({Layout = TOUCH_LAYOUT})
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx:Step()
	ctx:TapKit()
	ctx:Tap(2)
	check(#ctx.Fired == 1, "tapping the potion in the open KIT fan uses it")
	ctx:Advance(1.3)
	ctx:TapKit()
	ctx.Rows[2].Activated:Fire({UserInputType = Enum.UserInputType.Keyboard})
	check(#ctx.Fired == 1, "an Activated from a keyboard is not a tap")

	local pc = hudContext()
	pc.Player:SetAttribute("ZyntraSpeedPotions", 1)
	pc:Step()
	pc:Chip("Potion").Activated:Fire({UserInputType = Enum.UserInputType.Keyboard})
	check(#pc.Fired == 0, "an Activated from a keyboard is not a click")
	pc:Chip("Potion").Activated:Fire({UserInputType = Enum.UserInputType.MouseButton1})
	check(#pc.Fired == 1 and pc.Fired[1].Name == "UseSpeedPotion", "clicking the potion chip uses it")
end

do -- REFUSED: a Coral stroke and one of four tags above the row, never dims
	local ctx = hudContext({Detector = true})
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 1)
	ctx:Step(7)
	check(near(ctx:Opacity(), 0.4) and not ctx:Caption().Visible, "no tag until something is refused; the row rests")
	ctx.MarkerRemote.OnClientEvent:Fire("refused", "NoMarkers")
	ctx:Step(0)
	check(ctx:Caption().Visible and ctx:Tag() == "NO MARKERS LEFT", "a known refusal maps to its tag")
	check(look(ctx, "Markers").Stroke.Color == P.Coral, "the refused chip gets the Coral stroke")
	check(look(ctx, "Shield").Stroke.Color == P.Line, "and only that chip")
	check(near(ctx:Opacity(), 1), "a refusal wakes the row")
	ctx:Step(1.9)
	check(ctx:Caption().Visible and near(ctx:Opacity(), 1), "and it never dims while the tag shows")
	ctx:Step(0.2)
	check(not ctx:Caption().Visible, "the tag clears itself after two seconds")
	check(look(ctx, "Markers").Stroke.Color == P.Line, "and so does the stroke")
	check(near(ctx:Opacity(), 0.4), "and the row goes back to rest")
	for reason, line in pairs({RateLimited = "TOO SOON", Hiding = "NOT WHILE HIDING",
		NotInRound = "NOT NOW", NoCharacter = "NOT NOW", Unavailable = "NOT NOW"}) do
		ctx.MarkerRemote.OnClientEvent:Fire("refused", reason)
		ctx:Step(0)
		check(ctx:Tag() == line, "RouteMarkerService's " .. reason .. " reads as " .. line)
	end
	ctx.MarkerRemote.OnClientEvent:Fire("refused", "somethingnew")
	ctx:Step(0)
	check(ctx:Caption().Visible and ctx:Tag() == "NOT NOW",
		"an unknown server reason still shows a tag, NOT NOW, and is never printed raw")
	ctx.MarkerRemote.OnClientEvent:Fire("placed", 2)
	ctx:Step(0)
	check(ctx:Tag() == "NOT NOW", "a successful placement needs no tag")

	ctx.Player:SetAttribute("ZyntraOwnsEntityDetector", true)
	ctx:Step(2.1)
	ctx.DetectorRemote.OnClientEvent:Fire("refused", "SCAN DURING A RUN")
	ctx:Step(0)
	check(ctx:Tag() == "NOT NOW" and look(ctx, "Scan").Stroke.Color == P.Coral,
		"a detector refusal is NOT NOW on the scan chip, never its raw string")

	ctx:Step(2.1)
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx:Step()
	ctx:Key("T")
	ctx.ProfileRemote.OnClientEvent:Fire({}, "Already used this round.", "error")
	ctx:Step(0)
	check(ctx:Caption().Visible and ctx:Tag() == "NOT NOW", "an error push in the round is a tag, never its text")
	check(look(ctx, "Potion").Stroke.Color == P.Coral, "on the chip that was just used")
	ctx:Step(2.1)
	ctx.ProfileRemote.OnClientEvent:Fire({}, "Purchase complete", "success")
	ctx:Step(0)
	check(not ctx:Caption().Visible, "a non-error push is left to the terminal")
	ctx.Player:SetAttribute("InRound", false)
	ctx:Step(0)
	ctx.ProfileRemote.OnClientEvent:Fire({}, "Out of round", "error")
	ctx:Step(0)
	check(not ctx:Caption().Visible, "and nothing is tagged outside a round")

	local safe = POINTER.Safe
	local placed = hudContext()
	placed.MarkerRemote.OnClientEvent:Fire("refused", "RateLimited")
	placed:Step(0)
	local caption = placed:Caption()
	check(caption.AnchorPoint.X == 0 and caption.AnchorPoint.Y == 1
		and caption.Position == UDim2.fromOffset(math.floor(safe.Left + 264), math.floor(safe.Bottom - 24 - 84 - 8)),
		"the tag sits 8 above the row, at its left edge: " .. tostring(caption.Position))
	-- HUD_B3 (owner, 2026-10-08): critic K4. NoiseReporter and Round HUD keep the stamina bar and the marker
	-- right of Safe.Left + KIT_RIGHT (Round HUD's test pins that both state the same number); this row owns it.
	local row = placed:Row()
	check(row.AnchorPoint.X == 0 and row.Position.X.Offset + row.Size.X.Offset <= math.floor(safe.Left + KIT_RIGHT),
		"the row ends by Safe.Left + KIT_RIGHT " .. KIT_RIGHT .. " (K4): " .. tostring(row.Position))
end

do -- B1 QA: "use a marker with none left and NO MARKERS LEFT shows" (said here; nothing is fired)
	local ctx = hudContext()
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 0)
	ctx.Player:SetAttribute("RouteMarkersActive", 3)
	ctx:Step(7)
	check(ctx:Shown("Markers") and look(ctx, "Markers").Face.BackgroundColor3 == P.Tile
		and near(ctx:Opacity(), 0.4), "all placed, none stored: an EMPTY marker chip in a resting row")
	ctx:Key("X")
	ctx:Step(0)
	check(#ctx.Fired == 0, "X with no marker left fires nothing")
	check(ctx:Caption().Visible and ctx:Tag() == "NO MARKERS LEFT", "and the tag says NO MARKERS LEFT")
	check(look(ctx, "Markers").Stroke.Color == P.Coral and look(ctx, "Shield").Stroke.Color == P.Line,
		"on the marker chip alone")
	check(near(ctx:Opacity(), 1), "and the refusal wakes the row")
	ctx:Release("X")
	ctx:Step(2.1)
	check(not ctx:Caption().Visible, "the tag keeps its 2 s window")
	ctx:Chip("Markers").Activated:Fire({UserInputType = Enum.UserInputType.MouseButton1})
	ctx:Step(0)
	check(#ctx.Fired == 0 and ctx:Caption().Visible and ctx:Tag() == "NO MARKERS LEFT",
		"a click on the empty chip says the same and fires nothing")

	local quiet = hudContext()
	quiet.ClientState.Charges = 0
	quiet:Step()
	quiet:Key("Q")
	quiet:Key("T")
	quiet:Step(0)
	check(#quiet.Requests == 0 and #quiet.Fired == 0 and not quiet:Caption().Visible,
		"an empty shield or an unowned potion says nothing")
end

do -- TOUCH: no chip row; SHIELD, KIT and the fan take UIDevice's slots at every touch layout
	for name, layout in pairs({["705x338"] = TOUCH_LAYOUT, ["844x390"] = PHONE, ["1024x768"] = TABLET}) do
		local ctx = hudContext({Layout = layout})
		ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
		ctx.Player:SetAttribute("ZyntraRouteMarkers", 2)
		ctx:Step()
		ctx:TapKit()
		check(ctx:Row() == nil or not drawn(ctx:Row()), name .. ": no chip row on a touch device")
		local plan = layout.ControlPlan
		local shield, kitSlot = plan.Slots.ProtectionUse, plan.Slots.KitToggle
		check(shield.Width >= 44 and shield.Height >= 44 and kitSlot.Width >= 44 and kitSlot.Height >= 44,
			name .. ": SHIELD and KIT are at least 44x44")
		for _, pair in ipairs({{ctx.Rows[1], shield}, {ctx.Kit, kitSlot}, {ctx.Fan, plan.Fan}}) do
			local node, slot = pair[1], pair[2]
			check(node.AnchorPoint.X == 1 and node.AnchorPoint.Y == 1
				and node.Position == UDim2.new(1, -slot.Right, 1, -slot.Bottom)
				and node.Size == UDim2.fromOffset(slot.Width, slot.Height), name .. ": " .. node.Name .. " takes its slot")
			check(ctx:Drawn(node), name .. ": " .. node.Name .. " is drawn")
		end
		check(ctx:Drawn(ctx.Rows[2]) and ctx:Drawn(ctx.Rows[3]), name .. ": both owned items are in the fan")
	end
	check(TABLET.ControlPlan.Slots.ProtectionUse.Width == 64 and TABLET.ControlPlan.Fan.Width == 212
		and TABLET.ControlPlan.Fan.Height == 64, "the tablet's 64 px cells and its 212x64 fan")

	-- D6: a layout change resizes the mounted cells; it never re-mounts them.
	local ctx = hudContext({Layout = PHONE})
	local shield, kit, fan = ctx.Rows[1], ctx.Kit, ctx.Fan
	ctx:Device({Layout = TABLET})
	ctx:Step()
	check(ctx.gui:FindFirstChild("ProtectionUse") == shield and ctx.gui:FindFirstChild("KitToggle") == kit
		and ctx.gui:FindFirstChild("KitFan") == fan, "a layout change keeps every mounted root")
	check(shield.Size == UDim2.fromOffset(64, 64) and fan.Size == UDim2.fromOffset(212, 64),
		"and resizes them to the new slots")
	check(near(shield:FindFirstChildOfClass("UIStroke").Thickness, SCALED_2PX),
		"a ScaledSize stroke keeps its fraction at 64 px")
end

do -- critic C8: a pixel stroke (not ScaledSize) is derived from the cell's size on every frame
	local function pixelStroke(ctx)
		local stroke = find(ctx.Templates, "HUD_Touch/TouchCluster/Cell_Shield"):FindFirstChildOfClass("UIStroke")
		stroke.Attributes.FW_StrokeScaled = nil
		stroke.Thickness = 2
	end
	local ctx = hudContext({Layout = TABLET, Prepare = pixelStroke})
	local stroke = ctx.Rows[1]:FindFirstChildOfClass("UIStroke")
	check(near(stroke.Thickness, 2 * 64 / 52), "READY at 64 px: the 2 px design stroke at the cell's scale")
	ctx.Player:SetAttribute("PlayerProtectionActive", true)
	ctx.Player:SetAttribute("PlayerProtectionExpiresAt", ctx.Now + 3)
	ctx:Step(0)
	check(near(stroke.Thickness, 3 * 64 / 52), "ACTIVE at 64 px: 3 px at the cell's scale")
	ctx:Device({Layout = PHONE})
	ctx:Step(0)
	check(near(stroke.Thickness, 3), "the same ACTIVE stroke at 52 px is 3 px")
end

do -- a place without HUD_Touch: warned by path, nothing drawn or reserved, every key still works
	local ctx = hudContext({Layout = PHONE, Skip = {HUD_Touch = true}})
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx:Step()
	check(ctx.Rows[1] == nil and ctx.Kit == nil and ctx.Fan == nil, "no template: no cell and no fan")
	for _, path in ipairs({"TouchCluster/Cell_Shield", "TouchCluster/Cell_Kit", "KitFan"}) do
		check(ctx:Warned("[RoundHud] missing template: HUD_Touch/" .. path) == 1, "warned once: HUD_Touch/" .. path)
	end
	check(next(ctx.UIDevice.Registered) == nil, "and nothing is reserved")
	ctx.Player:SetAttribute("KitFanOpen", true)
	ctx:Step()
	check(ctx.Player:GetAttribute("KitFanOpen") == false, "a fan that cannot be drawn cannot be held open")
	ctx:Key("Q")
	ctx:Key("T")
	check(#ctx.Requests == 1 and #ctx.Fired == 1, "Q and T still press")

	local broken = hudContext({Layout = PHONE, Prepare = function(c)
		find(c.Templates, "HUD_Touch/KitFan/Fan_Marker/Badge").Parent = nil
	end})
	broken.Player:SetAttribute("ZyntraSpeedPotions", 1)
	broken:Step()
	check(broken:Warned("[ProtectionHUD] HUD_Touch/KitFan/Fan_Marker is incomplete (Badge): not drawn") == 1,
		"an incomplete fan item is one warning")
	check(broken.Fan == nil and not broken:Drawn(broken.Kit), "and no fan, so no KIT to open it")
	check(broken:Drawn(broken.Rows[1]) and broken.UIDevice.Registered.ProtectionUse == broken.Rows[1],
		"SHIELD is unaffected")
end

do -- a device flip: PC -> touch hides the row and its keycaps; back wakes it
	local ctx = hudContext()
	check(drawn(ctx:Row()) and next(ctx.UIDevice.Registered) == nil, "PC: the row, no control rects")
	ctx:Device({Touch = true, Layout = TOUCH_LAYOUT})
	ctx:Step()
	ctx:Step(0.4)
	check(not drawn(ctx:Row()), "touch: the row is hidden")
	check(not ctx:Part("Shield", "KeyChip").Visible, "and its keycaps (UIDevice prints no binding on touch)")
	check(ctx.Rows[1].Visible and ctx.UIDevice.Registered.ProtectionUse == ctx.Rows[1]
		and ctx.UIDevice.Registered.KitToggle == ctx.Kit, "the shield cell and KIT take their control slots")
	ctx:Device({Touch = false, Layout = POINTER})
	ctx:Step()
	check(drawn(ctx:Row()) and near(ctx:Opacity(), 1) and look(ctx, "Shield").Key == "Q",
		"back on PC the row wakes with its keycap")
	check(not ctx.Rows[1].Visible and not ctx.Rows[1].Active and next(ctx.UIDevice.Registered) == nil,
		"and the cells let their slots go")
end

do -- POINTER: the row stays inside the safe area at every window
	for name, layout in pairs(LAYOUTS.Pointer) do
		local ctx = hudContext({Layout = layout})
		ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
		ctx.Player:SetAttribute("ZyntraRouteMarkers", 1)
		ctx:Step()
		local safe = layout.Safe
		local row = ctx:Row()
		local left, bottom = row.Position.X.Offset, row.Position.Y.Offset
		check(left >= safe.Left and left + row.Size.X.Offset <= safe.Right,
			name .. ": the row is inside the safe area horizontally")
		check(bottom - row.Size.Y.Offset >= safe.Top and bottom <= safe.Bottom,
			name .. ": the row is inside the safe area vertically")
		check(next(ctx.UIDevice.Registered) == nil, name .. ": a pointer device registers no touch control rect")
	end
end

do -- SPECTATING: the read-only mirror
	-- `targetFirst` publishes the target before Spectating, so the first spectating
	-- refresh is already the mirror (no live-but-gated frame in between).
	local function watch(ctx, targetFirst)
		local watched = newInstance("Player", "Watched")
		watched.UserId = 77
		local body = newInstance("Model", "Body")
		local humanoid = newInstance("Humanoid", "Humanoid")
		humanoid.Health = 100
		humanoid.Parent = body
		newInstance("Part", "HumanoidRootPart").Parent = body
		watched.Character = body
		watched:SetAttribute("InRound", true)
		watched:SetAttribute("PlayerProtectionActive", true)
		watched:SetAttribute("PlayerProtectionExpiresAt", ctx.Now + 4.2)
		ctx.Watched = watched
		if targetFirst then ctx.Player:SetAttribute("SpectateTargetUserId", 77) end
		ctx.Player:SetAttribute("Spectating", true)
		ctx.Player:SetAttribute("SpectateTargetUserId", 77)
		ctx:Step(0)
	end

	local ctx = hudContext()
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 2)
	ctx.Player:SetAttribute("ZyntraRouteMarkers", 2)
	ctx:Step()
	watch(ctx)
	local shield = look(ctx, "Shield")
	check(ctx.gui.Enabled and ctx:Shown("Shield"), "PC: the mirror is the shield chip")
	check(shield.Active == "4.2" and shield.Safe, "printing the watched player's timer over SAFE")
	check(shield.Badge == nil and shield.Key == nil, "with no count of our own and no keycap")
	check(not ctx:Shown("Potion") and not ctx:Shown("Markers"),
		"our own equipment is not drawn over someone else's shield")
	check(not ctx:Caption().Visible, "and neither is the tag")
	check(not ctx.Rows[1].Visible and not ctx.Rows[1].Active, "PC draws no square for it, and nothing is pressable")
	check(next(ctx.UIDevice.Registered) == nil, "the mirror takes no control slot")
	ctx:Key("Q")
	ctx:Key("T")
	check(#ctx.Requests == 0 and #ctx.Fired == 0, "and no key does anything while spectating")
	ctx.Player:SetAttribute("PartyDownCardOpen", true)
	ctx:Step(0)
	check(not ctx.gui.Enabled, "the mirror stands down under PARTY DOWN too")
	ctx.Player:SetAttribute("PartyDownCardOpen", false)
	ctx:Step(5)
	check(not ctx.gui.Enabled, "and when the watched shield runs out")
	ctx.Player:SetAttribute("Spectating", false)
	ctx:Step()
	check(ctx:Shown("Shield") and look(ctx, "Shield").Key == "Q" and look(ctx, "Shield").Badge == "2",
		"our own chip comes back with its keycap and count")

	-- HUD_B2_TOUCH: a touch spectate draws nothing, the SHIELD mirror included (D11).
	-- Both publish orders: with the target first, the mirror branch itself has to
	-- stand the live kit down (and close the open fan); no gated frame does it.
	for _, targetFirst in ipairs({false, true}) do
		local order = targetFirst and " (target published first)" or ""
		local touchCtx = hudContext({Layout = TOUCH_LAYOUT})
		touchCtx.Player:SetAttribute("ZyntraSpeedPotions", 1)
		touchCtx:Step()
		touchCtx:TapKit()
		check(touchCtx:FanOpen() and touchCtx:Drawn(touchCtx.Fan), "the fan is open before spectating" .. order)
		watch(touchCtx, targetFirst)
		for _, node in ipairs({touchCtx.Rows[1], touchCtx.Kit, touchCtx.Fan, touchCtx.Rows[2], touchCtx.Rows[3], touchCtx.Rows[4]}) do
			check(not node.Visible and not node.Active, "touch spectating: " .. node.Name .. " is neither drawn nor live" .. order)
		end
		check(touchCtx.Player:GetAttribute("KitFanOpen") == false, "the open fan closes as spectating starts" .. order)
		check(next(touchCtx.UIDevice.Registered) == nil,
			"a spectating touch client releases the control rects it held" .. order)
		touchCtx:Tap(1)
		touchCtx:Key("Q")
		check(#touchCtx.Requests == 0, "and nothing presses the shield" .. order)
	end
end

do -- a place without HUD_PC: one warning per template, no row, every key still works
	local ctx = hudContext({Skip = {HUD_PC = true}})
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx:Step(2)
	check(ctx:Row() == nil and ctx:Caption() == nil, "no template: nothing drawn in its place")
	check(ctx:Warned("[RoundHud] missing template: HUD_PC/EquipmentPanel") == 1
		and ctx:Warned("[RoundHud] missing template: HUD_PC/EquipmentCaption") == 1, "warned once per path")
	ctx:Key("Q")
	ctx:Key("T")
	check(#ctx.Requests == 1 and #ctx.Fired == 1, "the shield and the potion still press")
	ctx.MarkerRemote.OnClientEvent:Fire("refused", "NoMarkers")
	ctx:Step(0)
	check(ctx.gui.Enabled, "a refusal with no tag to draw is harmless")
end

do -- teardown
	local ctx = hudContext({Layout = TOUCH_LAYOUT})
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 1)
	ctx:Step()
	ctx:TapKit()
	check(next(ctx.UIDevice.Registered) ~= nil and ctx:FanOpen(), "the touch client holds control rects and an open fan")
	local before = #ctx.Run.RenderStepped.entries
	ctx.Script.Destroying:Fire()
	check(next(ctx.UIDevice.Registered) == nil, "destroying releases every control rect")
	check(ctx.Player:GetAttribute("KitFanOpen") == false, "and closes the fan")
	check(#ctx.Run.RenderStepped.entries == before - 1, "and disconnects the per-frame refresh")
	check(ctx.gui.Parent == nil, "and destroys its ScreenGui")
	ctx.Player:SetAttribute("ZyntraSpeedPotions", 4)
	ctx:Key("T")
	check(#ctx.Fired == 0, "a destroyed HUD fires nothing")
end

print("Equipment HUD: " .. checks .. " checks passed (real ProtectionHUD + real RoundHud over the HUD_PC import + real UIDevice plan, offline Luau)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")
    source = HUD.read_bytes()
    assert b"\r" not in source, "ProtectionHUD must keep LF line endings"
    # HUD_B2_TOUCH (owner, 2026-10-08): ASCII-only source (B2-DESIGN 2.2 rule 7),
    # the marked section present, and the drawn squares gone.
    text = source.decode("ascii")
    begin = text.index("-- == B2 touch kit (14 A + KIT fan C; owner, 2026-10-08) ==")
    assert begin < text.index("-- == end B2 touch kit ==", begin), "the B2 touch kit section is marked"
    for gone in ('Instance.new("TextButton")', "TOUCH_CHIP", "DIMMED", "makeRow", "row.Button", "Slotted",
                 'RegisterControlRect(row.Key'):
        assert gone not in text, "ProtectionHUD still carries " + gone
    assert text.count("RegisterControlRect(") == 1, "only registerTouch reserves control rects"
    # HUD_B3 (owner, 2026-10-08): the re-entry grace sentence is Round HUD's GRACE marker now (B3-DESIGN 5).
    assert "ReentryGrace" not in text, "ProtectionHUD still carries ReentryGrace"
    assert "invisible to monsters" not in text.lower(), "ProtectionHUD still carries the invisible-to-monsters sentence"
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    if Path(compiler).exists():
        subprocess.run([compiler, "--null", str(HUD)], check=True, capture_output=True)
    else:
        print("luau-compile not found; compile check skipped.")
    inject = "local SOURCES = {\n%s\n}\nlocal TREES = %s\nlocal HUD_SOURCE = %s\n" % (
        ",\n".join("%s = %s" % (name, long_string(path.read_text(encoding="utf-8")))
                   for name, path in HUD_MODULES.items()),
        lua(trees()), long_string(HUD.read_text(encoding="utf-8")))
    harness = HARNESS.read_text(encoding="utf-8")
    assert "--@@INJECT@@" in harness
    kit_right = re.search(r"^local KIT_RIGHT\b[^=\n]*=\s*(\d+)", NOISE.read_text(encoding="utf-8"), re.M)
    assert kit_right, "NoiseReporter states KIT_RIGHT (B3 critic K4)"
    program = "".join([
        harness.replace("--@@INJECT@@", inject, 1),
        "\nlocal LAYOUTS = {}\nlocal function addChecks(count) checks += count end\ndo\n",
        ENGINE,
        CONTEXT,
        BOOTS,
        wrap("UIDeviceSource", UIDEVICE.read_text(encoding="utf-8")),
        PLAN_TESTS,
        PLAN_EXPORT,
        "\nend\n",
        "local KIT_RIGHT = %s\n" % kit_right.group(1),
        HUD_TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="equipment-hud-") as directory:
        path = Path(directory) / "equipment_hud_test.luau"
        path.write_text(program, encoding="utf-8")
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or "checks passed" not in result.stdout:
        print(result.stdout.strip()[-4000:])
        print(result.stderr.strip()[-4000:])
        raise SystemExit("test_equipment_hud FAILED")
    print(result.stdout.strip().splitlines()[-1])


if __name__ == "__main__":
    main()
