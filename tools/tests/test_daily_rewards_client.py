"""Run the whole Daily Rewards Client under offline Luau, and drive the modal.

DAILY_REWARDS_MODAL_20260916 (Trello #104). The LocalScript is not copied,
excerpted or string-matched: the entire file executes against a fake DataModel
and every assertion below is made by DRIVING it -- firing the opener bindable,
pressing CLOSE, pressing Escape, pressing ButtonB, pushing a profile down the
ZyntraProfileChanged remote, pressing a CLAIM button -- and then reading what
the script did to its own instances, to the LocalPlayer's attributes and to the
ZyntraAction remote.

WHAT THE 2026-09-16 REBUILD CHANGED. The shell's header: an orange UIGradient
bar carrying Codex's gift art, "DAILY REWARDS" and a 48px red X, in place of the
old accent bar, the "ZYNTRA // DAILY SUPPLY" eyebrow and the 36px chrome close
chip. Everything this file asserted about the MODAL RULES -- one mount, the five
refusals, every close path, the suppression derived from the whole modal set,
the Studio probe -- is asserted unchanged, because none of it moved.

REAL, not faked: ReplicatedStorage/UIStyle, ReplicatedStorage/ZyntraConfig and
ReplicatedStorage/ZyntraDailyRewardsPage. The page module is what the modal
exists to host, so mounting the real one is the only way the mount contract
(one mount, a fit table the page can read, a profile subscription, a working
CLAIM) is actually proved rather than assumed. It is also why the card
assertions below -- the art ids, the claimed tick, the 44px CLAIM -- are made
against the real page through the real fit this shell publishes, rather than
against numbers a page test made up for itself. The page is re-executed per
fixture so two tests cannot share its state, which is what `require`'s cache
gives it in the engine.

FAKED, and only where its published contract is: UIDevice. Layout() returns a
stated ModalViewport per viewport row, SuppressTouchMovement records every
request, ScreenOwningModalOpen reads the five screen-owning attributes (the
four ZyntraStore shipped plus DailyRewardsOpen, which A-RAIL adds to
SCREEN_OWNING_MODALS in this same batch -- see the NOTE this file prints if it
is not there yet), SetEnabled writes Active and LocalPosition subtracts the
gui's origin.

What it CANNOT see, and what the native QA pass in the report is for: the real
dynamic-thumbstick suppression, a real finger, font metrics and TextBounds, the
engine's UICorner/UIStroke rendering, and whether the panel reads well. Set
LUAU_BIN or put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "StarterPlayer/StarterPlayerScripts/Daily Rewards Client.LocalScript.lua"
PAGE = ROOT / "ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua"
UISTYLE = ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua"
CONFIG = ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua"
RESEARCH = ROOT / "ReplicatedStorage/ZyntraDailyResearch.ModuleScript.lua"
UIDEVICE = ROOT / "ReplicatedStorage/UIDevice.ModuleScript.lua"


PRELUDE = r'''
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, "FAILED: " .. message)
end
local function expect(value, wanted, message)
	checks += 1
	assert(value == wanted, "FAILED: " .. message .. " -- expected "
		.. tostring(wanted) .. ", got " .. tostring(value))
end

local warnings = {}
local function warn(...)
	local parts = {}
	for _, piece in ipairs({...}) do table.insert(parts, tostring(piece)) end
	table.insert(warnings, table.concat(parts, " "))
end

-- ── value types ──────────────────────────────────────────────────────────
-- Memoised, so `==` answers "same value" the way the engine's own types do.
local function memo(kind, build)
	local cache = {}
	return function(...)
		local key = kind .. ":" .. table.concat({...}, ",")
		if not cache[key] then cache[key] = build(key, ...) end
		return cache[key]
	end
end

-- Roblox Color3 has NO arithmetic. A fake that quietly allowed `a + b` would
-- pass code the engine throws on (the 2026-09-14 Codex regression).
local colorMeta = {
	__add = function() error("Color3 has no arithmetic", 2) end,
	__sub = function() error("Color3 has no arithmetic", 2) end,
	__mul = function() error("Color3 has no arithmetic", 2) end,
	__div = function() error("Color3 has no arithmetic", 2) end,
	__tostring = function(self) return self.Key end,
}
local Color3 = {
	fromRGB = memo("Color3", function(key, r, g, b)
		return setmetatable({Kind = "Color3", Key = key, R = r, G = g, B = b}, colorMeta)
	end),
	new = memo("Color3n", function(key, r, g, b)
		return setmetatable({Kind = "Color3", Key = key, R = r, G = g, B = b}, colorMeta)
	end),
}
local UDim = {new = memo("UDim", function(key, scale, offset)
	return {Kind = "UDim", Key = key, Scale = scale, Offset = offset}
end)}
local udim2Meta = {}
local function makeUDim2(sx, ox, sy, oy)
	return setmetatable({Kind = "UDim2", SX = sx, OX = ox, SY = sy, OY = oy}, udim2Meta)
end
udim2Meta.__add = function(a, b) return makeUDim2(a.SX + b.SX, a.OX + b.OX, a.SY + b.SY, a.OY + b.OY) end
udim2Meta.__sub = function(a, b) return makeUDim2(a.SX - b.SX, a.OX - b.OX, a.SY - b.SY, a.OY - b.OY) end
local UDim2 = {
	new = function(sx, ox, sy, oy) return makeUDim2(sx or 0, ox or 0, sy or 0, oy or 0) end,
	fromOffset = function(x, y) return makeUDim2(0, x or 0, 0, y or 0) end,
	fromScale = function(x, y) return makeUDim2(x or 0, 0, y or 0, 0) end,
}
local vector2Meta = {}
local function makeVector2(x, y) return setmetatable({Kind = "Vector2", X = x, Y = y}, vector2Meta) end
vector2Meta.__add = function(a, b) return makeVector2(a.X + b.X, a.Y + b.Y) end
vector2Meta.__sub = function(a, b) return makeVector2(a.X - b.X, a.Y - b.Y) end
local Vector2 = {new = makeVector2, zero = makeVector2(0, 0)}
local ColorSequenceKeypoint = {new = function(t, c) return {T = t, C = c} end}
local ColorSequence = {new = function(v) return {Kind = "ColorSequence", Value = v} end}
local enumItems = {}
local Enum = setmetatable({}, {__index = function(_, group)
	return setmetatable({}, {__index = function(_, item)
		local key = group .. "." .. item
		if not enumItems[key] then
			enumItems[key] = {Name = item, Group = group, Key = key, Value = 0}
		end
		return enumItems[key]
	end})
end})

-- ── signals that really disconnect ───────────────────────────────────────
local function signal()
	local listeners = {}
	local this = {}
	function this:Connect(fn)
		table.insert(listeners, fn)
		local connection = {Connected = true}
		function connection:Disconnect()
			connection.Connected = false
			for index, stored in ipairs(listeners) do
				if stored == fn then table.remove(listeners, index) break end
			end
		end
		return connection
	end
	function this:Fire(...)
		for _, fn in ipairs(table.clone(listeners)) do fn(...) end
	end
	function this:Count() return #listeners end
	return this
end

-- ── instances ────────────────────────────────────────────────────────────
local SIGNALS = {
	MouseEnter = true, MouseLeave = true, Activated = true, Event = true,
	InputBegan = true, InputEnded = true, OnClientEvent = true,
	ChildAdded = true, DescendantAdded = true, LastInputTypeChanged = true,
}
local function newInstance(class)
	local fields = {
		ClassName = class, Name = class, Children = {}, Attributes = {},
		Watchers = {}, Destroyed = false,
		-- Roblox's own defaults for the properties these files read back.
		Visible = true, Text = "", TextScaled = false, Selectable = false,
		Modal = false, Enabled = true, ScrollingEnabled = false,
		Active = class == "TextButton" or class == "ImageButton",
	}
	-- An ImageLabel that does not carry these is a fake that would pass a shell
	-- which never set Image or left ScaleType at Stretch.
	if class == "ImageLabel" or class == "ImageButton" then
		fields.Image = ""
		fields.ScaleType = Enum.ScaleType.Stretch
		fields.ImageColor3 = Color3.new(1, 1, 1)
		fields.IsLoaded = false
	end
	local proxy
	fields.FindFirstChildOfClass = function(_, want)
		for _, child in ipairs(fields.Children) do
			if child.ClassName == want then return child end
		end
		return nil
	end
	fields.FindFirstChild = function(_, want)
		for _, child in ipairs(fields.Children) do
			if child.Name == want then return child end
		end
		return nil
	end
	-- A timeout makes WaitForChild ANSWER rather than block: that is the branch
	-- the client takes when the page module is not in the place.
	fields.WaitForChild = function(self, want, timeout)
		local found = self:FindFirstChild(want)
		if found then return found end
		if timeout ~= nil then return nil end
		error("missing fixture child: " .. tostring(want))
	end
	fields.GetChildren = function() return table.clone(fields.Children) end
	fields.GetDescendants = function(self)
		local out = {}
		for _, child in ipairs(fields.Children) do
			table.insert(out, child)
			for _, nested in ipairs(child:GetDescendants()) do table.insert(out, nested) end
		end
		return out
	end
	fields.IsA = function(_, want)
		return want == class
			or (want == "GuiObject" and (class == "Frame" or class == "TextLabel"
				or class == "TextButton" or class == "ImageLabel"
				or class == "ImageButton" or class == "ScrollingFrame"))
			or (want == "GuiButton" and (class == "TextButton" or class == "ImageButton"))
	end
	fields.GetAttribute = function(_, key) return fields.Attributes[key] end
	fields.Watcher = function(_, key)
		if not fields.Watchers[key] then fields.Watchers[key] = signal() end
		return fields.Watchers[key]
	end
	fields.SetAttribute = function(self, key, value)
		local before = fields.Attributes[key]
		fields.Attributes[key] = value
		if before ~= value and fields.Watchers[key] then fields.Watchers[key]:Fire() end
	end
	fields.GetAttributeChangedSignal = function(self, key) return self:Watcher(key) end
	fields.GetPropertyChangedSignal = function(self, property) return self:Watcher("@" .. property) end
	-- A watched PROPERTY has to be written through here: __newindex cannot fire
	-- the signal without turning every property write into a broadcast.
	fields.SetProperty = function(self, property, value)
		proxy[property] = value
		if fields.Watchers["@" .. property] then fields.Watchers["@" .. property]:Fire() end
	end
	-- BindableEvent:Fire is the one place a signal is raised by a METHOD on the
	-- instance rather than on the signal itself, and it is how the rail button
	-- opens this modal.
	fields.Fire = function(self, ...) self.Event:Fire(...) end
	fields.Invoke = function(_, ...)
		assert(type(fields.OnInvoke) == "function", "BindableFunction has no OnInvoke")
		return fields.OnInvoke(...)
	end
	local function unparent()
		local parent = fields.Parent
		if not parent then return end
		for index, child in ipairs(parent.Children) do
			if child == proxy then table.remove(parent.Children, index) break end
		end
	end
	fields.Destroy = function()
		unparent()
		fields.Destroyed = true
		fields.Parent = nil
		for _, child in ipairs(table.clone(fields.Children)) do child:Destroy() end
	end
	proxy = setmetatable({}, {
		__index = function(_, key)
			local value = fields[key]
			if value ~= nil then return value end
			if SIGNALS[key] then fields[key] = signal() return fields[key] end
			return nil
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				unparent()
				if value ~= nil then table.insert(value.Children, proxy) end
			end
			fields[key] = value
		end,
	})
	return proxy
end
local Instance = {new = newInstance}

local function findByName(root, name)
	for _, child in ipairs(root.Children) do
		if child.Name == name then return child end
		local deeper = findByName(child, name)
		if deeper then return deeper end
	end
	return nil
end
local function mustFind(root, name)
	local found = findByName(root, name)
	assert(found, "no instance named " .. name)
	return found
end
local function descendants(root, into)
	into = into or {}
	for _, child in ipairs(root.Children) do
		table.insert(into, child)
		descendants(child, into)
	end
	return into
end
-- Where a node actually sits inside `root`, by walking the parents the way the
-- engine resolves an absolute position.
local function offsetWithin(node, root)
	local x, y = 0, 0
	local current = node
	while current and current ~= root do
		if current.Position then
			x += current.Position.OX
			y += current.Position.OY
		end
		current = current.Parent
	end
	return x, y
end
'''


FIXTURE = r'''
-- ── viewports ────────────────────────────────────────────────────────────
-- ModalViewport, the rectangle a screen-owning modal may occupy: the safe area
-- inset by UIDevice's own GUTTER (16) and 8px top/bottom. The gui uses
-- CoreUISafeInsets, so its origin is the safe area's top-left corner.
local function viewport(name, left, top, right, bottom, touch)
	return {
		Name = name,
		IsTouch = touch,
		OriginX = left - 16,
		OriginY = top - 8,
		ModalViewport = {Left = left, Top = top, Right = right, Bottom = bottom,
			Width = right - left, Height = bottom - top, Fits = true},
	}
end
local POINTER = viewport("pointer 1280x720", 16, 44, 1264, 712, false)
local PHONE_PORTRAIT = viewport("phone portrait 390x844", 16, 52, 374, 826, true)
-- MEASURED, not derived: Studio at 844x390 with the UIDevice overrides gives a
-- 720x316 panel and a 696x214 content box, 22px tighter than this file first
-- assumed. It is the tier where CLAIM was one flick below the fold.
local PHONE_LANDSCAPE = viewport("phone landscape 844x390", 16, 44, 828, 360, true)
local TABLET = viewport("tablet 1024x768", 16, 44, 1008, 760, true)
-- Whether CLAIM must be pressable without scrolling. The portrait phone is a
-- list of three full-width cards and scrolls like one; everything else has to
-- fit the state row inside the content box.
POINTER.ClaimAboveFold = true
PHONE_PORTRAIT.ClaimAboveFold = false
PHONE_LANDSCAPE.ClaimAboveFold = true
TABLET.ClaimAboveFold = true
local VIEWPORTS = {POINTER, PHONE_PORTRAIT, PHONE_LANDSCAPE, TABLET}

local TODAY, YESTERDAY = "2026-09-16", "2026-09-15"
local RESET_SECONDS = 18753 -- 05:12:33

local function profileOf(overrides)
	local daily = {Day = TODAY, Today = TODAY, PlaytimeSeconds = 0, Claimed = {},
		SecondsToReset = RESET_SECONDS, Accruing = false}
	for key, value in pairs(overrides or {}) do daily[key] = value end
	return {Daily = daily, Tokens = 12, Items = {SpeedPotion = 0, RouteMarker = 0}}
end

-- ── the fixture ──────────────────────────────────────────────────────────
local function context(options)
	options = options or {}
	local ctx = {
		Now = 1000, Queue = {}, Sent = {}, Invokes = 0, Suppressions = {},
		LastInput = options.LastInput or "Keyboard",
		Layout = options.Layout or POINTER,
		ServerProfile = options.Profile or profileOf(),
		ProfileFails = options.ProfileFails == true,
		MountCalls = 0, Bound = {},
	}

	ctx.Workspace = newInstance("Workspace")
	ctx.Workspace.Name = "Workspace"
	ctx.Workspace.GetServerTimeNow = function() return ctx.Now end

	ctx.Player = newInstance("Player")
	ctx.Player.Name = "Player"
	ctx.PlayerGui = newInstance("PlayerGui")
	ctx.PlayerGui.Name = "PlayerGui"
	ctx.PlayerGui.Parent = ctx.Player
	ctx.PlayerScripts = newInstance("PlayerScripts")
	ctx.PlayerScripts.Name = "PlayerScripts"
	ctx.PlayerScripts.Parent = ctx.Player
	if options.Opener then
		ctx.Opener = newInstance("BindableEvent")
		ctx.Opener.Name = "OpenDailyRewards"
		ctx.Opener.Parent = ctx.PlayerScripts
	end
	for key, value in pairs(options.Attributes or {}) do
		ctx.Player:SetAttribute(key, value)
	end

	local storage = newInstance("ReplicatedStorage")
	storage.Name = "ReplicatedStorage"
	ctx.Storage = storage
	for _, name in ipairs({"UIDevice", "UIStyle", "ZyntraConfig", "ZyntraDailyResearch"}) do
		local module = newInstance("ModuleScript")
		module.Name = name
		module.Parent = storage
	end
	if options.NoPageModule ~= true then
		ctx.PageModuleScript = newInstance("ModuleScript")
		ctx.PageModuleScript.Name = "ZyntraDailyRewardsPage"
		ctx.PageModuleScript.Parent = storage
	end
	local remotes = newInstance("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = storage

	ctx.ActionRemote = newInstance("RemoteEvent")
	ctx.ActionRemote.Name = "ZyntraAction"
	ctx.ActionRemote.FireServer = function(_, name, payload)
		table.insert(ctx.Sent, {Name = name, Payload = payload})
	end
	ctx.ActionRemote.Parent = remotes

	ctx.GetProfileRemote = newInstance("RemoteFunction")
	ctx.GetProfileRemote.Name = "ZyntraGetProfile"
	ctx.GetProfileRemote.InvokeServer = function()
		ctx.Invokes += 1
		if ctx.ProfileFails then error("no answer") end
		return ctx.ServerProfile
	end
	ctx.GetProfileRemote.Parent = remotes

	ctx.ProfileChangedRemote = newInstance("RemoteEvent")
	ctx.ProfileChangedRemote.Name = "ZyntraProfileChanged"
	ctx.ProfileChangedRemote.Parent = remotes

	ctx.UIS = newInstance("UserInputService")
	ctx.UIS.GetFocusedTextBox = function() return nil end
	ctx.GuiService = newInstance("GuiService")
	ctx.GuiService.MenuIsOpen = false
	ctx.GuiService.SelectedObject = nil
	ctx.RunService = {Heartbeat = signal(), RenderStepped = signal(),
		IsStudio = function() return true end}
	ctx.CAS = {}
	function ctx.CAS.BindActionAtPriority(_, name, handler, touchButton, priority, ...)
		ctx.Bound[name] = {Handler = handler, Keys = {...}, Priority = priority}
	end
	function ctx.CAS.BindAction(_, name, handler, touchButton, ...)
		ctx.Bound[name] = {Handler = handler, Keys = {...}}
	end
	function ctx.CAS.UnbindAction(_, name) ctx.Bound[name] = nil end

	local services = {
		Players = {LocalPlayer = ctx.Player},
		ReplicatedStorage = storage,
		RunService = ctx.RunService,
		UserInputService = ctx.UIS,
		GuiService = ctx.GuiService,
		ContextActionService = ctx.CAS,
		TweenService = {Create = function()
			error("the daily rewards modal must not tween", 2)
		end},
	}
	ctx.Game = {GetService = function(_, name)
		return assert(services[name], "unfaked service " .. tostring(name))
	end}

	ctx.Task = {}
	function ctx.Task.spawn(fn, ...) fn(...) end
	function ctx.Task.defer(fn, ...) fn(...) end
	function ctx.Task.wait(seconds) return seconds or 0 end
	function ctx.Task.delay(seconds, fn)
		table.insert(ctx.Queue, {At = ctx.Now + (seconds or 0), Fn = fn})
	end

	-- Advance real time in small steps, running due task.delay callbacks and
	-- firing Heartbeat exactly as the engine would.
	function ctx:Advance(total, step)
		step = step or 1 / 60
		local remaining = total
		local guard = 0
		while remaining > 1e-9 do
			local delta = math.min(step, remaining)
			self.Now += delta
			remaining -= delta
			guard += 1
			assert(guard < 200000, "scheduler runaway")
			local ran = true
			while ran do
				ran = false
				for index, item in ipairs(self.Queue) do
					if item.At <= self.Now then
						table.remove(self.Queue, index)
						item.Fn()
						ran = true
						break
					end
				end
			end
			self.RunService.Heartbeat:Fire(delta)
		end
	end

	-- ── UIDevice, faked only where its published contract is ──────────────
	-- DailyRewardsOpen is in this list because A-RAIL adds it to the real
	-- module's SCREEN_OWNING_MODALS in this same batch. If it is not there in
	-- the shipped file, the runner prints a NOTE -- the modal would then fail
	-- to stand the movement cluster down under itself.
	local MODALS = {"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen",
		"QueueModalOpen", "DailyRewardsOpen"}
	local device = {Changed = signal()}
	function device.Layout() return ctx.Layout end
	function device.LocalOffset(_, x, y)
		return x - ctx.Layout.OriginX, y - ctx.Layout.OriginY
	end
	function device.LocalPosition(gui, x, y)
		local lx, ly = device.LocalOffset(gui, x, y)
		return UDim2.fromOffset(math.floor(lx), math.floor(ly))
	end
	function device.SuppressesKeyboardGlyphs() return ctx.Layout.IsTouch == true end
	function device.Binding(keyboard, _)
		if device.SuppressesKeyboardGlyphs() then return "" end
		return keyboard or ""
	end
	function device.LastInput() return ctx.LastInput end
	function device.SetEnabled(element, enabled)
		if element:IsA("TextButton") or element:IsA("ImageButton") then
			element.Active = enabled
			element.Selectable = enabled
		end
	end
	function device.SetInteractive(element, shown)
		element.Visible = shown
		if element:IsA("TextButton") or element:IsA("ImageButton") then
			element.Active = shown
			element.Selectable = shown
		end
	end
	function device.ScreenOwningModalOpen()
		for _, attribute in ipairs(MODALS) do
			if ctx.Player:GetAttribute(attribute) == true then return true end
		end
		return false
	end
	function device.OnScreenOwningModalChanged(callback)
		for _, attribute in ipairs(MODALS) do
			ctx.Player:GetAttributeChangedSignal(attribute):Connect(callback)
		end
	end
	function device.SuppressTouchMovement(active)
		table.insert(ctx.Suppressions, active)
		ctx.Suppressed = active
	end
	ctx.UIDevice = device
	return ctx
end
'''


BOOT_HEAD = r'''
local function boot(ctx)
	-- The page reaches the research ledger as game.ReplicatedStorage, a property.
	ctx.Game.ReplicatedStorage = ctx.Storage
	local game, workspace, task = ctx.Game, ctx.Workspace, ctx.Task
	-- The page module is re-executed per fixture, which is what require's cache
	-- gives it in the engine: one instance per place, not one shared between
	-- two unrelated tests in the same process.
	-- The page chunk below requires the research ledger by instance; answer it
	-- with the REAL module (the client's own require is declared after the page).
	local function require(module)
		if module.Name == "ZyntraDailyResearch" then return RealResearch end
		error("unexpected page require: " .. tostring(module.Name))
	end
	local PageModule = (function()
'''

BOOT_BRIDGE = r'''
	end)()
	-- Counted by wrapping the REAL module's mount, so "mounted exactly once" is
	-- a fact about the shipped call rather than about a stub.
	local WrappedPage = {mount = function(frame, pageCtx)
		ctx.MountCalls += 1
		ctx.MountFrame = frame
		ctx.PageCtx = pageCtx
		local handle = PageModule.mount(frame, pageCtx)
		ctx.PageHandle = handle
		return handle
	end}
	local function require(module)
		if module.Name == "UIDevice" then return ctx.UIDevice end
		if module.Name == "UIStyle" then return UIStyle end
		if module.Name == "ZyntraConfig" then return RealConfig end
		if module.Name == "ZyntraDailyResearch" then return RealResearch end
		if module.Name == "ZyntraDailyRewardsPage" then return WrappedPage end
		error("unexpected require: " .. tostring(module.Name))
	end
'''

BOOT_TAIL = r'''
end
'''


TESTS = r'''
-- ── driving it ───────────────────────────────────────────────────────────
local function start(options)
	local ctx = context(options)
	boot(ctx)
	ctx.Gui = findByName(ctx.PlayerGui, "DailyRewardsGui")
	if ctx.Gui then
		ctx.Shade = findByName(ctx.Gui, "DailyRewardsShade")
		ctx.Panel = findByName(ctx.Gui, "DailyRewardsPanel")
		ctx.Header = findByName(ctx.Panel, "RewardsHeader")
		ctx.Gift = findByName(ctx.Panel, "HeaderGift")
		ctx.Title = findByName(ctx.Panel, "HeaderTitle")
		ctx.Close = findByName(ctx.Panel, "CloseButton")
		ctx.Content = findByName(ctx.Panel, "PageContent")
		ctx.Status = findByName(ctx.Panel, "StatusLine")
		ctx.Probe = findByName(ctx.Gui, "UIRegressionDailyRewardsProbe")
	end
	ctx.OpenerEvent = findByName(ctx.PlayerScripts, "OpenDailyRewards")
	return ctx
end
-- The retired supply fiction, hunted over the WHOLE modal -- shell and page
-- alike -- because the eyebrow that carried it used to be a label like any
-- other and a stray one would read as a second brand on a warm header.
local function forbiddenCopy(ctx)
	for _, node in ipairs(descendants(ctx.Gui)) do
		local text = tostring(node.Text or "")
		if string.find(text, "SUPPLY", 1, true) or string.find(text, "Supply", 1, true)
			or string.find(text, "ZYNTRA //", 1, true) then
			return node.Name .. ": " .. text
		end
	end
	return nil
end
local function openIt(ctx) ctx.OpenerEvent:Fire() end
local function push(ctx, overrides)
	ctx.ServerProfile = profileOf(overrides)
	ctx.ProfileChangedRemote.OnClientEvent:Fire(ctx.ServerProfile, nil, nil)
end
local function escape(ctx)
	ctx.UIS.InputBegan:Fire({KeyCode = Enum.KeyCode.Escape,
		UserInputType = Enum.UserInputType.Keyboard}, false)
end
local function buttonB(ctx)
	local bound = ctx.Bound.DailyRewardsClose
	assert(bound, "ButtonB is not bound while the modal is open")
	return bound.Handler("DailyRewardsClose", Enum.UserInputState.Begin, {})
end
local function cardPart(ctx, minutes, name)
	local card = findByName(ctx.Content, "Milestone" .. tostring(minutes))
	return card and card:FindFirstChild(name) or nil
end
local function claimButton(ctx, minutes) return cardPart(ctx, minutes, "ClaimButton") end
local function actionsNamed(ctx, name)
	local count = 0
	for _, entry in ipairs(ctx.Sent) do
		if entry.Name == name then count += 1 end
	end
	return count
end
local function spinRemnant(ctx)
	for _, node in ipairs(descendants(ctx.Gui)) do
		local nodeName = tostring(node.Name)
		if nodeName == "SpinButton" or nodeName == "SkipButton"
			or nodeName == "WheelSection" or nodeName == "ResultBanner" then
			return nodeName
		end
	end
	return nil
end

-- ══ 1. the shell is built, once, and sends nothing but its first read ═════
do
	local ctx = start()
	check(ctx.Gui ~= nil, "the ScreenGui is built")
	expect(ctx.Gui.Name, "DailyRewardsGui", "under the contracted name")
	expect(ctx.Gui.DisplayOrder, 117, "at the contracted DisplayOrder")
	expect(ctx.Gui.ResetOnSpawn, false, "and it survives a respawn")
	expect(ctx.Gui.ScreenInsets, Enum.ScreenInsets.CoreUISafeInsets,
		"the gui is inset to the CoreUI safe area")
	expect(ctx.Gui.Parent, ctx.PlayerGui, "and parented to PlayerGui")

	check(ctx.Shade ~= nil, "the shade is built")
	expect(ctx.Shade.Active, true, "the shade takes input so a mis-tap cannot reach the world")
	expect(ctx.Shade.Visible, false, "and the modal starts closed")
	expect(ctx.Shade.Size.SX, 1, "the shade spans the full width of the safe area")
	expect(ctx.Shade.Size.SY, 1, "and its full height")

	check(ctx.Panel ~= nil, "the panel is built")
	expect(ctx.Panel.Parent, ctx.Shade, "inside the shade")

	-- The warm header: the one surface in this game that is not the dark teal
	-- chrome, because it is the one screen that gives something away.
	check(ctx.Header ~= nil, "the header bar is built")
	expect(ctx.Header.Parent, ctx.Panel, "inside the panel")
	local ramp = ctx.Header:FindFirstChildOfClass("UIGradient")
	check(ramp ~= nil, "and carries a gradient")
	expect(ramp.Color.Value[1].C, Color3.fromRGB(255, 170, 60), "from the contracted orange")
	expect(ramp.Color.Value[2].C, Color3.fromRGB(255, 120, 40), "to the contracted deeper orange")
	-- A UIGradient MULTIPLIES BackgroundColor3; over the old dark panel colour
	-- the warm ramp would render as a slightly-less-dark bar.
	expect(ctx.Header.BackgroundColor3, Color3.fromRGB(255, 255, 255),
		"over a white bar, so the ramp reads as authored")

	check(ctx.Gift ~= nil and ctx.Gift.ClassName == "ImageLabel", "the gift is an ImageLabel")
	expect(ctx.Gift.Image, "rbxassetid://117126194981100", "wearing Codex's uploaded art")
	expect(ctx.Gift.ScaleType, Enum.ScaleType.Fit, "Fit, so it is never stretched")
	expect(ctx.Gift.BackgroundTransparency, 1, "over the ramp, not on a plate of its own")
	expect(ctx.Gift.Parent, ctx.Header, "and it belongs to the header")

	expect(ctx.Title.Text, "DAILY REWARDS", "the header names the modal")
	expect(ctx.Title.Parent, ctx.Header, "inside the header bar")
	expect(findByName(ctx.Panel, "Eyebrow"), nil, "the supply eyebrow is gone")
	expect(forbiddenCopy(ctx), nil, "and nothing left in the modal names it")

	check(ctx.Close ~= nil and ctx.Close.ClassName == "TextButton", "CLOSE is a button")
	expect(ctx.Close.Text, "X", "drawn as an X")
	expect(ctx.Close.Parent, ctx.Header, "at the top right of the header")
	expect(ctx.Close.BackgroundColor3, Color3.fromRGB(190, 60, 50), "in the contracted red")
	check(ctx.Content ~= nil, "there is a content frame for the page")
	expect(ctx.Status.Text, "", "the status line starts empty")

	expect(ctx.Player:GetAttribute("DailyRewardsOpen"), nil,
		"nothing is published while the modal is closed")
	expect(ctx.Invokes, 1, "the profile is read exactly once at boot")
	expect(#ctx.Sent, 0, "and building the modal sends no action")
	expect(#ctx.Suppressions, 0, "a closed modal makes no suppression request")
	expect(#warnings, 0, "nothing warned: " .. table.concat(warnings, " | "))
end

-- ══ 2. the page is mounted ONCE, at build time ════════════════════════════
do
	local ctx = start()
	expect(ctx.MountCalls, 1, "the page module is mounted exactly once")
	expect(ctx.MountFrame, ctx.Content, "into the content frame, not the panel")
	local scroll = findByName(ctx.Content, "DailyRewards")
	check(scroll ~= nil, "and the page drew its scroll inside it")
	expect(scroll.ScrollingEnabled, true, "which the contract enables")

	for _ = 1, 3 do
		openIt(ctx)
		ctx.Close.Activated:Fire()
	end
	expect(ctx.MountCalls, 1, "three open/close cycles do not mount it again")
	local roots = 0
	for _, node in ipairs(descendants(ctx.Content)) do
		if node.Name == "DailyRewards" then roots += 1 end
	end
	expect(roots, 1, "so there is still exactly one page tree")
	expect(scroll.Destroyed, false, "closing does NOT destroy the mount")

	-- Every field the page contract names, present and of the right kind.
	local pageCtx = ctx.PageCtx
	expect(pageCtx.player, ctx.Player, "ctx.player is the LocalPlayer")
	expect(pageCtx.UIStyle, UIStyle, "ctx.UIStyle is the shared style module")
	expect(pageCtx.UIDevice, ctx.UIDevice, "ctx.UIDevice is the shared device module")
	expect(pageCtx.Config, RealConfig, "ctx.Config is the shipped ZyntraConfig")
	expect(pageCtx.pageName, "Rewards", "ctx.pageName is the contracted page name")
	for _, field in ipairs({"label", "button", "corner", "outline", "action", "profile",
		"onProfile", "refreshProfile", "showStatus", "registerLayoutHook", "isVisible"}) do
		expect(type(pageCtx[field]), "function", "ctx." .. field .. " is a function")
	end
	expect(type(pageCtx.COLORS), "table", "ctx.COLORS is a table")
	for _, key in ipairs({"bg", "card", "accent", "accent2", "text", "muted", "line", "error"}) do
		check(pageCtx.COLORS[key] ~= nil, "ctx.COLORS carries " .. key)
	end
	expect(type(pageCtx.contract), "table", "ctx.contract is a table")
	expect(type(pageCtx.contract.scroll), "function", "ctx.contract.scroll is a function")
	expect(type(pageCtx.contract.card), "function", "ctx.contract.card is a function")
	expect(pageCtx.isVisible(), false, "isVisible() is false while the modal is closed")
end

-- ══ 3. the wheel is not here, and cannot be reached from here ═════════════
do
	local ctx = start()
	openIt(ctx)
	push(ctx, {WheelDay = TODAY, WheelLast = {Day = TODAY, Key = "Token3", Serial = 3}})
	expect(spinRemnant(ctx), nil, "the modal builds no wheel control of any kind")
	for _, node in ipairs(descendants(ctx.Gui)) do
		if node.ClassName == "TextButton" then node.Activated:Fire() end
	end
	expect(actionsNamed(ctx, "SpinDailyWheel"), 0,
		"and no control in it can send SpinDailyWheel")
end

-- ══ 4. opening ════════════════════════════════════════════════════════════
do
	local ctx = start()
	expect(ctx.OpenerEvent ~= nil, true, "the opener bindable is created when nothing else has")
	expect(ctx.OpenerEvent.ClassName, "BindableEvent", "and it is a BindableEvent")
	expect(ctx.OpenerEvent.Parent, ctx.PlayerScripts, "parented to PlayerScripts")

	openIt(ctx)
	expect(ctx.Shade.Visible, true, "firing it draws the modal")
	expect(ctx.Player:GetAttribute("DailyRewardsOpen"), true,
		"and publishes DailyRewardsOpen")
	expect(ctx.PageCtx.isVisible(), true, "the page is told it is on screen")
	expect(#ctx.Suppressions, 1, "one suppression request per open")
	expect(ctx.Suppressions[1], true, "asking for the movement cluster to stand down")
	expect(ctx.Invokes, 2, "opening RE-READS the profile")
	check(ctx.Bound.DailyRewardsClose ~= nil, "ButtonB is bound while it is open")
	expect(ctx.Bound.DailyRewardsClose.Keys[1], Enum.KeyCode.ButtonB, "to ButtonB")

	-- A second fire while it is already up changes nothing at all.
	openIt(ctx)
	expect(#ctx.Suppressions, 1, "firing the opener again does not re-publish")
	expect(ctx.Invokes, 2, "and does not send a second profile read")
	expect(ctx.MountCalls, 1, "and certainly does not mount a second page")
end
do
	local ctx = start({Opener = true})
	expect(ctx.OpenerEvent, ctx.Opener, "an opener another script already made is ADOPTED")
	local count = 0
	for _, child in ipairs(ctx.PlayerScripts.Children) do
		if child.Name == "OpenDailyRewards" then count += 1 end
	end
	expect(count, 1, "never duplicated")
	openIt(ctx)
	expect(ctx.Shade.Visible, true, "and the adopted one opens the modal")
end
do
	local ctx = start({LastInput = "Gamepad"})
	openIt(ctx)
	expect(ctx.GuiService.SelectedObject, ctx.Close,
		"a gamepad is given the CLOSE control to start from")
end
do
	-- AUDIT_FIX_20260924: a pad picked up while it is open takes focus too.
	local ctx = start({})
	openIt(ctx)
	expect(ctx.GuiService.SelectedObject, nil, "a keyboard open forces no selection")
	ctx.LastInput = "Gamepad"
	ctx.UIS.LastInputTypeChanged:Fire()
	expect(ctx.GuiService.SelectedObject, ctx.Close,
		"switching to a controller while open lands on CLOSE")
end

-- ══ 5. it is refused where the contract says it is ════════════════════════
for _, case in ipairs({
	{Name = "in a round", Key = "InRound"},
	{Name = "under the terminal", Key = "ZyntraStoreOpen"},
	{Name = "under the dev phone", Key = "DevPhoneOpen"},
	{Name = "under the re-entry modal", Key = "ZyntraReentryOpen"},
	{Name = "under the queue host panel", Key = "QueueModalOpen"},
}) do
	local ctx = start({Attributes = {[case.Key] = true}})
	openIt(ctx)
	expect(ctx.Shade.Visible, false, case.Name .. ": the modal refuses to open")
	expect(ctx.Player:GetAttribute("DailyRewardsOpen"), nil,
		case.Name .. ": and publishes nothing")
	expect(#ctx.Suppressions, 0, case.Name .. ": and makes no suppression request")
	expect(ctx.Invokes, 1, case.Name .. ": and sends no extra profile read")
	expect(ctx.Bound.DailyRewardsClose, nil, case.Name .. ": and binds no close action")
	-- Clearing the reason lets it open, so the refusal is the attribute and not
	-- something latched at build time.
	ctx.Player:SetAttribute(case.Key, nil)
	openIt(ctx)
	expect(ctx.Shade.Visible, true, case.Name .. ": and opens once the reason is gone")
end

-- ══ 6. every close path ═══════════════════════════════════════════════════
for _, case in ipairs({
	{Name = "CLOSE", Apply = function(ctx) ctx.Close.Activated:Fire() end},
	{Name = "Escape", Apply = escape},
	{Name = "ButtonB", Apply = buttonB},
	{Name = "InRound", Apply = function(ctx) ctx.Player:SetAttribute("InRound", true) end},
	{Name = "RoundActive",
		Apply = function(ctx) ctx.Workspace:SetAttribute("RoundActive", true) end},
	{Name = "QueueModalOpen",
		Apply = function(ctx) ctx.Player:SetAttribute("QueueModalOpen", true) end},
	{Name = "the Roblox menu",
		Apply = function(ctx) ctx.GuiService:SetProperty("MenuIsOpen", true) end},
}) do
	local ctx = start()
	openIt(ctx)
	check(ctx.Shade.Visible, case.Name .. ": it started open")
	case.Apply(ctx)
	expect(ctx.Shade.Visible, false, case.Name .. " closes the modal")
	expect(ctx.Player:GetAttribute("DailyRewardsOpen"), nil,
		case.Name .. " clears the published attribute")
	expect(ctx.PageCtx.isVisible(), false, case.Name .. " tells the page it is off screen")
	expect(#ctx.Suppressions, 2, case.Name .. " makes exactly one more suppression request")
	-- QueueModalOpen is the one case where something ELSE still owns the screen,
	-- so the movement cluster must stay down. Every other path frees it.
	local stillOwned = case.Name == "QueueModalOpen"
	expect(ctx.Suppressions[2], stillOwned,
		case.Name .. " derives the request from the whole modal set, not from itself")
	expect(ctx.Bound.DailyRewardsClose, nil, case.Name .. " unbinds ButtonB")
	expect(ctx.MountCalls, 1, case.Name .. " does not destroy or remount the page")
	check(findByName(ctx.Content, "DailyRewards") ~= nil,
		case.Name .. " leaves the page tree in place")
end
do
	-- The dedicated proof of the suppression rule: another modal opens on top of
	-- this one, and closing this one must NOT re-enable the movement controls.
	local ctx = start()
	openIt(ctx)
	ctx.Player:SetAttribute("ZyntraReentryOpen", true)
	ctx.Close.Activated:Fire()
	expect(ctx.Shade.Visible, false, "CLOSE still closes with another modal up")
	expect(ctx.Suppressed, true,
		"and the movement cluster stays down because re-entry still owns the screen")
	ctx.Player:SetAttribute("ZyntraReentryOpen", nil)
	openIt(ctx)
	ctx.Close.Activated:Fire()
	expect(ctx.Suppressed, false, "with nothing left open, the controls come back")
end
do
	-- Closing something already closed must not publish a second time.
	local ctx = start()
	ctx.Close.Activated:Fire()
	escape(ctx)
	expect(#ctx.Suppressions, 0, "closing a closed modal publishes nothing")
	expect(ctx.Player:GetAttribute("DailyRewardsOpen"), nil, "and writes no attribute")
end
do
	-- Escape while it is closed belongs to whatever else is listening.
	local ctx = start()
	openIt(ctx)
	ctx.Close.Activated:Fire()
	local before = #ctx.Suppressions
	escape(ctx)
	expect(#ctx.Suppressions, before, "Escape after a close is not this modal's business")
end

-- ══ 7. a profile push re-renders the milestone cards ══════════════════════
do
	local ctx = start()
	openIt(ctx)
	push(ctx, {PlaytimeSeconds = 0})
	expect(claimButton(ctx, 5).Text, "5:00 TO GO", "a fresh day locks the five")
	expect(claimButton(ctx, 5).Active, false, "and it cannot be pressed")

	push(ctx, {PlaytimeSeconds = 299})
	expect(claimButton(ctx, 5).Text, "0:01 TO GO", "one second short is still locked")

	push(ctx, {PlaytimeSeconds = 300})
	expect(claimButton(ctx, 5).Text, "CLAIM", "five minutes unlocks it")
	expect(claimButton(ctx, 5).Active, true, "and it is reachable")
	expect(claimButton(ctx, 5).BackgroundColor3, Color3.fromRGB(70, 200, 90),
		"a ready CLAIM is the bright green one")
	expect(claimButton(ctx, 15).Text, "10:00 TO GO", "the fifteen is still locked")
	expect(claimButton(ctx, 35).Text, "30:00 TO GO", "and so is the thirty-five")

	-- The card the owner asked for: the reward's own art, not a row of text.
	expect(cardPart(ctx, 5, "Threshold").Text, "5 MIN", "the threshold is stated in minutes")
	expect(cardPart(ctx, 5, "RewardIcon").Image, "rbxassetid://93116899475472",
		"the 5 minute card wears the token art")
	expect(cardPart(ctx, 15, "RewardIcon").Image, "rbxassetid://120211340805188",
		"the 15 minute card wears the speed potion art")
	expect(cardPart(ctx, 35, "RewardIcon").Image, "rbxassetid://126728249949579",
		"the 35 minute card wears the entity shield art")
	for _, minutes in ipairs({5, 15, 35}) do
		expect(cardPart(ctx, minutes, "RewardIcon").ScaleType, Enum.ScaleType.Fit,
			minutes .. ": Fit, so the motif is never stretched")
	end

	push(ctx, {PlaytimeSeconds = 300, Claimed = {["5"] = true}})
	expect(cardPart(ctx, 5, "ClaimedCheck").Visible, true, "a claimed milestone shows the tick")
	expect(cardPart(ctx, 5, "ClaimedLabel").Visible, true, "and says CLAIMED")
	expect(claimButton(ctx, 5).Visible, false, "with the button hidden, not relabelled")
	expect(claimButton(ctx, 5).Active, false, "and cannot be claimed twice")
	expect(cardPart(ctx, 15, "ClaimedCheck").Visible, false, "the other cards are untouched")

	push(ctx, {Day = YESTERDAY, PlaytimeSeconds = 3000,
		Claimed = {["5"] = true, ["15"] = true, ["35"] = true}})
	expect(claimButton(ctx, 5).Text, "5:00 TO GO",
		"yesterday's counters are not today's")
	expect(claimButton(ctx, 5).Visible, true, "and the button comes back with the new day")
	expect(claimButton(ctx, 5).Active, false, "locked, not pressable")
	expect(cardPart(ctx, 5, "ClaimedCheck").Visible, false, "with yesterday's tick taken down")

	-- A push while the modal is CLOSED is still accepted: the page has to be
	-- correct the moment it is drawn, not one frame later.
	ctx.Close.Activated:Fire()
	push(ctx, {PlaytimeSeconds = 2100})
	expect(claimButton(ctx, 35).Text, "CLAIM", "a push behind a closed modal still lands")
	openIt(ctx)
	expect(claimButton(ctx, 35).Text, "CLAIM", "and reopening shows it straight away")
end

-- ══ 8. CLAIM: one press, one action, then locked until an answer ══════════
do
	local ctx = start()
	openIt(ctx)
	push(ctx, {PlaytimeSeconds = 400})
	local claim = claimButton(ctx, 5)
	claim.Activated:Fire()
	expect(#ctx.Sent, 1, "one press sends one action")
	expect(ctx.Sent[1].Name, "ClaimPlaytimeReward", "the contracted action name")
	expect(ctx.Sent[1].Payload.Minutes, 5, "carrying the milestone it belongs to")
	expect(claim.Text, "CLAIMING...", "the button says what it is waiting for")
	expect(claim.Active, false, "and leaves the input stack")
	claim.Activated:Fire()
	claim.Activated:Fire()
	expect(#ctx.Sent, 1, "a second and third press send nothing")

	push(ctx, {PlaytimeSeconds = 400, Claimed = {["5"] = true}})
	expect(cardPart(ctx, 5, "ClaimedCheck").Visible, true, "the push is the answer")
	expect(claim.Visible, false, "and the button gives way to the tick")
	ctx:Advance(8)
	expect(ctx.Status.Text, "", "and the timeout never fires for a request that was answered")
	expect(#ctx.Sent, 1, "nothing else was sent")
end

-- ══ 9. the 6 s recovery is a RE-READ, never a local grant ═════════════════
do
	local ctx = start()
	openIt(ctx)
	push(ctx, {PlaytimeSeconds = 900})
	local claim = claimButton(ctx, 15)
	expect(claim.Text, "CLAIM", "fifteen minutes is claimable")
	local invokesBefore = ctx.Invokes
	claim.Activated:Fire()
	ctx:Advance(5)
	expect(claim.Text, "CLAIMING...", "it is still waiting at five seconds")
	expect(ctx.Invokes, invokesBefore, "and has not given up")
	ctx:Advance(1.5)
	expect(ctx.Status.Text, "No answer yet. Try again.", "at six seconds the player is told")
	expect(ctx.Status.TextColor3, Color3.fromRGB(244, 95, 82), "in the error colour")
	expect(ctx.Invokes, invokesBefore + 1, "and the page RE-READS rather than guessing")
	expect(claim.Text, "CLAIM", "the control comes back")
	expect(claim.Active, true, "reachable, so the player can retry")
	expect(#ctx.Sent, 1, "the recovery itself sends nothing")
	claim.Activated:Fire()
	expect(#ctx.Sent, 2, "and a retry is a genuine second request")
end

-- ══ 10. the status line ═══════════════════════════════════════════════════
do
	local ctx = start()
	ctx.ProfileChangedRemote.OnClientEvent:Fire(profileOf(), "Claimed 1 Research Token.", "success")
	expect(ctx.Status.Text, "Claimed 1 Research Token.", "a server notice reaches the status line")
	expect(ctx.Status.TextColor3, Color3.fromRGB(68, 221, 196), "a success reads in the accent")
	ctx.ProfileChangedRemote.OnClientEvent:Fire(profileOf(), "Not yet.", "error")
	expect(ctx.Status.TextColor3, Color3.fromRGB(244, 95, 82), "an error reads in the error colour")
	openIt(ctx)
	expect(ctx.Status.Text, "", "and opening the modal clears the last message")
end

-- ══ 11. a server that never answers the first read ════════════════════════
do
	local ctx = start({ProfileFails = true})
	expect(ctx.Invokes, 1, "the first read is still attempted")
	expect(ctx.Status.Text, "Could not load the Zyntra profile.", "and the failure is stated")
	openIt(ctx)
	expect(ctx.Shade.Visible, true, "the modal still opens")
	check(findByName(ctx.Content, "DailyRewards") ~= nil, "with the page drawn")
	expect(claimButton(ctx, 5).Text, "5:00 TO GO",
		"and every milestone locked, because nothing was read")
end

-- ══ 12. the module is missing from the place ══════════════════════════════
do
	local ctx = start({NoPageModule = true})
	expect(ctx.MountCalls, 0, "nothing is mounted")
	local missing = findByName(ctx.Content, "PageUnavailable")
	check(missing ~= nil, "the modal says DAILY REWARDS UNAVAILABLE instead")
	expect(missing.Text, "DAILY REWARDS UNAVAILABLE", "in those words")
	openIt(ctx)
	expect(ctx.Shade.Visible, true, "the shell still opens")
	expect(ctx.Player:GetAttribute("DailyRewardsOpen"), true, "and still publishes")
	ctx.Close.Activated:Fire()
	expect(ctx.Shade.Visible, false, "and CLOSE still works, so nobody is trapped")
	expect(ctx.Suppressed, false, "with the movement controls handed back")
	check(#warnings > 0, "and the missing module was warned about")
	table.clear(warnings)
end

-- ══ 13. the Studio probe drives the production paths ══════════════════════
do
	local ctx = start()
	check(ctx.Probe ~= nil, "the Studio probe is parented to the ScreenGui")
	expect(ctx.Probe.ClassName, "BindableFunction", "as a BindableFunction")
	expect(ctx.Probe:Invoke("state"), false, "state reports the modal closed")
	ctx.Probe:Invoke("open")
	expect(ctx.Shade.Visible, true, "open opens it")
	expect(ctx.Probe:Invoke("state"), true, "and state says so")
	expect(ctx.Player:GetAttribute("DailyRewardsOpen"), true,
		"through the production path, attribute and all")
	local cards = ctx.Probe:Invoke("cards")
	expect(cards, "Rewards|Playtime5|ClaimButton\nRewards|Playtime15|ClaimButton"
		.. "\nRewards|Playtime35|ClaimButton",
		"cards reports the three milestones the page was authored to hold")
	expect(ctx.Probe:Invoke("scrolls"), "Rewards|DailyRewards",
		"scrolls reports the one page scroll")
	ctx.Probe:Invoke("close")
	expect(ctx.Shade.Visible, false, "close closes it")
	expect(ctx.Probe:Invoke("nonsense"), nil, "and an unknown action answers nil")

	-- The probe is REFUSED exactly as a player is, or a matrix would measure a
	-- modal a player could never have opened.
	ctx.Player:SetAttribute("InRound", true)
	ctx.Probe:Invoke("open")
	expect(ctx.Probe:Invoke("state"), false, "the probe cannot open it in a round either")
end

-- ══ 14. fit: four viewports, measured ═════════════════════════════════════
for _, layout in ipairs(VIEWPORTS) do
	local name = layout.Name
	local ctx = start({Layout = layout})
	openIt(ctx)
	push(ctx, {PlaytimeSeconds = 900})
	ctx.UIDevice.Changed:Fire()

	local area = layout.ModalViewport
	local panel = ctx.Panel
	-- The panel is positioned in the GUI's own offsets, so it is converted back
	-- into the one space UIDevice speaks before being compared with the area.
	local left = panel.Position.OX + layout.OriginX
	local top = panel.Position.OY + layout.OriginY
	check(panel.Size.OX > 0 and panel.Size.OY > 0, name .. ": the panel is a real rectangle")
	check(left >= area.Left, name .. ": the panel starts inside the modal viewport ("
		.. tostring(left) .. " >= " .. tostring(area.Left) .. ")")
	check(top >= area.Top, name .. ": and below its top edge")
	check(left + panel.Size.OX <= area.Right,
		name .. ": it ends inside the right edge (" .. tostring(left + panel.Size.OX)
		.. " <= " .. tostring(area.Right) .. ")")
	check(top + panel.Size.OY <= area.Bottom,
		name .. ": and above the bottom edge (" .. tostring(top + panel.Size.OY)
		.. " <= " .. tostring(area.Bottom) .. ")")

	-- The content frame, the status line and CLOSE all inside the panel.
	for _, part in ipairs({ctx.Content, ctx.Status, ctx.Close, ctx.Title}) do
		local px, py = offsetWithin(part, panel)
		check(px >= 0 and px + part.Size.OX <= panel.Size.OX,
			name .. ": " .. part.Name .. " spans " .. tostring(px) .. ".."
			.. tostring(px + part.Size.OX) .. " inside " .. tostring(panel.Size.OX))
		check(py >= 0 and py + part.Size.OY <= panel.Size.OY,
			name .. ": " .. part.Name .. " is inside the panel vertically")
		check(part.Size.OX > 0 and part.Size.OY > 0,
			name .. ": " .. part.Name .. " has a real rectangle")
	end
	-- The title must never run under the control that dismisses the modal.
	local titleLeft = ctx.Title.Position.OX
	check(titleLeft + ctx.Title.Size.OX <= ctx.Close.Position.OX,
		name .. ": the title stops short of CLOSE")
	check(ctx.Content.Position.OY + ctx.Content.Size.OY <= ctx.Status.Position.OY,
		name .. ": the content stops short of the status line")

	-- 48, at EVERY tier: the X is the one control on a screen-owning modal a
	-- player must be able to hit, and a pointer is not an excuse to shrink it.
	check(ctx.Close.Size.OY >= 48,
		name .. ": CLOSE is " .. tostring(ctx.Close.Size.OY) .. "px tall, the floor is 48")
	check(ctx.Close.Size.OX >= 48,
		name .. ": CLOSE is " .. tostring(ctx.Close.Size.OX) .. "px wide, the floor is 48")
	check(ctx.Gift.Size.OX > 0 and ctx.Gift.Size.OX == ctx.Gift.Size.OY,
		name .. ": the gift is a real square")
	local gx, gy = offsetWithin(ctx.Gift, ctx.Header)
	check(gx >= 0 and gx + ctx.Gift.Size.OX <= ctx.Header.Size.OX,
		name .. ": the gift fits the header horizontally")
	check(gy >= 0 and gy + ctx.Gift.Size.OY <= ctx.Header.Size.OY,
		name .. ": and vertically")
	check(ctx.Title.Position.OX >= gx + ctx.Gift.Size.OX,
		name .. ": the title starts clear of the gift")

	-- The page laid itself out against the fit this shell published.
	local fit = nil
	ctx.PageCtx.registerLayoutHook(function(published) fit = published end)
	check(fit ~= nil, name .. ": a hook registered after boot is handed the fit at once")
	expect(fit.ContentWidth, ctx.Content.Size.OX,
		name .. ": the fit's ContentWidth is the content frame's own width")
	expect(fit.ContentHeight, ctx.Content.Size.OY,
		name .. ": and its ContentHeight the frame's own height")
	expect(fit.Touch, layout.IsTouch, name .. ": the fit reports the form factor")
	expect(fit.Tap, layout.IsTouch and 44 or 32, name .. ": and the tap floor")
	for _, key in ipairs({"Compact", "Touch", "ContentWidth", "ContentHeight",
		"TabHeight", "TabMinWidth", "Tap"}) do
		check(fit[key] ~= nil, name .. ": the fit carries " .. key)
	end

	local section = findByName(ctx.Content, "PlaytimeSection")
	check(section ~= nil, name .. ": the playtime section is drawn")
	local sx = offsetWithin(section, ctx.Content)
	check(sx >= 0 and sx + section.Size.OX <= ctx.Content.Size.OX,
		name .. ": and it fits the content frame the shell gave it")
	-- The phone held sideways gets ONE strip: the countdown moves in beside the
	-- play readout so the three cards start 52px down instead of 126px down.
	local clock = findByName(ctx.Content, "ResetCountdown")
	local play = findByName(ctx.Content, "PlayStrip")
	local merged = layout == PHONE_LANDSCAPE
	expect(clock.Parent == play, merged,
		name .. ": the countdown shares the play strip's row only when it has to")
	if merged then
		check(play.Size.OY <= 44, name .. ": the merged strip is "
			.. tostring(play.Size.OY) .. "px, the ceiling is 44")
		expect(findByName(ctx.Content, "CountdownStrip").Visible, false,
			name .. ": with no row of its own left")
	end

	for _, minutes in ipairs({5, 15, 35}) do
		local action = claimButton(ctx, minutes)
		check(action ~= nil, name .. ": the " .. minutes .. " minute card has a CLAIM")
		local ax, ay = offsetWithin(action, ctx.Content)
		check(ax >= 0 and ax + action.Size.OX <= ctx.Content.Size.OX,
			name .. ": " .. minutes .. "'s CLAIM ends inside the content frame")
		if layout.ClaimAboveFold then
			check(ay + action.Size.OY <= ctx.Content.Size.OY,
				name .. ": " .. minutes .. "'s CLAIM ends at "
				.. tostring(ay + action.Size.OY) .. ", the fold is "
				.. tostring(ctx.Content.Size.OY) .. " -- it must be pressable"
				.. " without scrolling")
		end
		if layout.IsTouch then
			check(action.Size.OY >= 44,
				name .. ": " .. minutes .. "'s CLAIM is " .. tostring(action.Size.OY)
				.. "px tall, the floor is 44")
			check(action.Size.OX >= 44, name .. ": " .. minutes .. "'s CLAIM is wide enough")
		end
	end

	-- Nothing prints below 11px, anywhere in the modal, at any tier.
	local smallest, counted = 999, 0
	for _, node in ipairs(descendants(ctx.Gui)) do
		if node.TextSize ~= nil and node.Visible ~= false
			and (node.ClassName == "TextLabel" or node.ClassName == "TextButton") then
			smallest = math.min(smallest, node.TextSize)
			counted += 1
		end
	end
	check(counted >= 14, name .. ": the modal draws its full set of copy (" .. counted .. ")")
	check(smallest >= 11, name .. ": the smallest face is " .. tostring(smallest) .. "px")
	expect(spinRemnant(ctx), nil, name .. ": and no wheel control at this tier")
	expect(#warnings, 0, name .. ": nothing warned: " .. table.concat(warnings, " | "))
end

-- ══ 15. a very short modal viewport still yields a usable modal ═══════════
do
	-- Below every device in the matrix on purpose: the give-way ladder's last
	-- rung has to leave a reachable CLOSE and a content box, not a panel that
	-- has given away its own structure.
	local tiny = viewport("tiny 320x260", 16, 8, 304, 252, true)
	local ctx = start({Layout = tiny})
	openIt(ctx)
	local panel = ctx.Panel
	check(panel.Size.OY <= tiny.ModalViewport.Height,
		"the panel never grows past the modal viewport")
	check(ctx.Content.Size.OY >= 1, "the content box is still a rectangle")
	check(ctx.Close.Size.OY >= 48, "and CLOSE still holds its 48px floor")
	local cx, cy = offsetWithin(ctx.Close, panel)
	check(cx >= 0 and cx + ctx.Close.Size.OX <= panel.Size.OX,
		"with CLOSE inside the panel horizontally")
	check(cy >= 0 and cy + ctx.Close.Size.OY <= panel.Size.OY,
		"and inside it vertically, so it can be pressed")
	ctx.Close.Activated:Fire()
	expect(ctx.Shade.Visible, false, "and pressing it closes the modal")
end

print("Daily Rewards modal: " .. tostring(checks)
	.. " checks passed (entire actual LocalScript plus the real page module,"
	.. " UIStyle and ZyntraConfig, offline Luau; real touch, thumbstick"
	.. " suppression, font metrics and rendering not exercised)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    # A soft cross-agent check: the modal can only stand the movement cluster
    # down under itself once UIDevice lists its attribute. A-RAIL owns that
    # file, so this reports rather than fails.
    if '"DailyRewardsOpen"' not in UIDEVICE.read_text(encoding="utf-8"):
        print("NOTE: UIDevice.SCREEN_OWNING_MODALS does not list DailyRewardsOpen yet"
              " (A-RAIL owns that edit); the fake below assumes it does.")
    source = "\n".join([
        PRELUDE,
        # the real shared style module and the real shipped config
        "local UIStyle = (function()", UISTYLE.read_text(encoding="utf-8"), "end)()",
        "local RealConfig = (function()", CONFIG.read_text(encoding="utf-8"), "end)()",
        "local RealResearch = (function()", RESEARCH.read_text(encoding="utf-8"), "end)()",
        FIXTURE,
        BOOT_HEAD,
        PAGE.read_text(encoding="utf-8"),
        BOOT_BRIDGE,
        CLIENT.read_text(encoding="utf-8"),
        BOOT_TAIL,
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="daily-rewards-client-") as directory:
        fixture = Path(directory) / "daily_rewards_client.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=120)


if __name__ == "__main__":
    main()
