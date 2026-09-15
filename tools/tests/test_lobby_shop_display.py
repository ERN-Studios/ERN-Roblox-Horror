"""The lobby SHOP wall (Trello #88): the real server module and the real client
LocalScript, executed against a fake DataModel.

Both scripts are RUN, not pattern-matched -- LobbyShopDisplay.Build against a
fake lobby and the real ZyntraConfig catalogue, and Shop Display Client against
a fake PlayerGui/UIDevice -- so this fails on a typo as well as on a contract.

What it holds:

  * one stand, pedestal, crate, plate and INSPECT prompt per catalogue item,
    and the catalogue is every Pass and Product in ZyntraConfig;
  * a rebuild replaces the shop instead of stacking a second one;
  * the frontage stays inside the empty wall stretch (z -70..-45, x under the
    tunnel wall's inner face at 32.9) and never collides except at the pedestals;
  * stepping on a plate publishes ZyntraShopFocus and stepping off clears it,
    once per poll, with hysteresis at the edge, and the INSPECT prompt toggles
    the same attribute;
  * NOTHING on the server touches MarketplaceService -- focus cannot cost money;
  * the card opens and closes on the attribute, states OWNED for an owned pass,
    routes BUY to PlayerScripts.ZyntraShopBuy exactly once, and CLOSE dismisses
    only until the focus changes;
  * ReduceFlashing shrinks the sign's swell instead of strobing it, and all
    motion stops in a round;
  * the card draws the terminal's own three tiers (52/64/76px icon) and keeps a
    44px tap target on touch.

Run:  LUAU_BIN=/path/to/luau python tools/tests/test_lobby_shop_display.py
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LUAU = Path(os.environ.get("LUAU_BIN") or (Path(__file__).resolve().parent / "luau"))

CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")
SERVER = (ROOT / "ServerScriptService/LobbyShopDisplay.ModuleScript.lua").read_text(encoding="utf-8")
CLIENT = (ROOT / "StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua").read_text(encoding="utf-8")

# ── source contracts that the run cannot see ────────────────────────────────
# A purchase prompt anywhere in the server module would mean walking onto a
# plate could cost money. The fake engine refuses MarketplaceService as well,
# but state it here too: this is the rule the owner's brief is built on.
for forbidden in ("PromptProductPurchase", "PromptGamePassPurchase", 'GetService("MarketplaceService")'):
    assert forbidden not in SERVER, f"server module must not reference {forbidden}"
# The card's BUY is a request to ZyntraStore, never its own prompt.
for forbidden in ("PromptProductPurchase", "PromptGamePassPurchase"):
    assert forbidden not in CLIENT, f"client must not call {forbidden} itself"
# The same tier expression the terminal's Shop and Upgrades pages use, so the
# three tiers cannot drift apart silently.
assert "})[(compact and touch) and 1 or (touch and 2 or 3)]" in CLIENT
STORE = (ROOT / "StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua").read_text(encoding="utf-8")
assert "})[(fit.Compact and fit.Touch) and 1 or (fit.Touch and 2 or 3)]" in STORE

PRELUDE = r"""
local checks = 0
local function check(ok, why) checks += 1; if not ok then error(why, 2) end end
local function near(a, b, slack) return math.abs(a - b) <= (slack or 0.001) end

-- ── vectors, CFrames, colours ───────────────────────────────────────────────
local V = {}
V.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	return rawget(V, k)
end
local function vec(x, y, z) return setmetatable({X = x, Y = y, Z = z}, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, b) return vec(a.X * b, a.Y * b, a.Z * b) end
Vector3 = {new = function(x, y, z) return vec(x or 0, y or 0, z or 0) end}
Vector2 = {new = function(x, y) return {X = x or 0, Y = y or 0} end}
Color3 = {
	fromRGB = function(r, g, b) return {__color = true, R = r, G = g, B = b} end,
	new = function(r, g, b) return {__color = true, R = r, G = g, B = b} end,
}
UDim = {new = function(s, o) return {Scale = s, Offset = o} end}
UDim2 = {
	new = function(sx, ox, sy, oy) return {X = {Scale = sx, Offset = ox}, Y = {Scale = sy, Offset = oy}} end,
	fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end,
	fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end,
}

local CF = {}
CF.__index = CF
local function cframe(position, yaw)
	return setmetatable({__cf = true, Position = position, Yaw = yaw or 0}, CF)
end
CFrame = {
	new = function(x, y, z)
		if type(x) == "table" then return cframe(x) end
		return cframe(vec(x or 0, y or 0, z or 0))
	end,
	lookAt = function(from, to)
		return cframe(from, math.atan2(to.X - from.X, to.Z - from.Z))
	end,
	Angles = function(_, y, _) return cframe(vec(0, 0, 0), y) end,
}
CF.__mul = function(a, b)
	-- Yaw-only, which is all this geometry uses: rotate b's offset into a.
	local c, s = math.cos(a.Yaw), math.sin(a.Yaw)
	local p = b.Position
	return cframe(a.Position + vec(c * p.X + s * p.Z, p.Y, -s * p.X + c * p.Z), a.Yaw + b.Yaw)
end

function typeof(value)
	if type(value) == "table" then
		if rawget(value, "__instance") then return "Instance" end
		if rawget(value, "__cf") then return "CFrame" end
		if getmetatable(value) == V then return "Vector3" end
	end
	return type(value)
end

-- ── Enum: every path is a distinct memoised token ───────────────────────────
local function enumGroup(name)
	return setmetatable({}, {__index = function(t, key)
		local item = {Name = key, EnumType = name}
		rawset(t, key, item)
		return item
	end})
end
Enum = setmetatable({}, {__index = function(t, key)
	local group = enumGroup(key)
	rawset(t, key, group)
	return group
end})

-- ── task scheduler: co-operative, stepped by the test ───────────────────────
local waiting = {}
task = {
	spawn = function(fn, ...)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then error(err, 0) end
		return co
	end,
	wait = function()
		table.insert(waiting, coroutine.running())
		coroutine.yield()
	end,
	delay = function(_, fn) return task.spawn(fn) end,
}
function step(times)
	for _ = 1, (times or 1) do
		local due = waiting
		waiting = {}
		for _, co in ipairs(due) do
			local ok, err = coroutine.resume(co)
			if not ok then error(err, 0) end
		end
	end
end

-- ── instances ───────────────────────────────────────────────────────────────
local function signal()
	local handlers = {}
	local self = {}
	function self:Connect(fn) table.insert(handlers, fn); return {Disconnect = function() end} end
	function self:Fire(...) for _, fn in ipairs(handlers) do fn(...) end end
	return self
end

setAttributeCalls = 0
Instance = {}

function Instance.new(className)
	local children, attributes, signals = {}, {}, {}
	local inst
	local fields = {ClassName = className, Name = className, Parent = nil, Children = children}
	local methods = {}
	function methods:IsA(kind)
		return kind == className
			or (kind == "BasePart" and (className == "Part" or className == "MeshPart"))
			or (kind == "GuiObject" and (className == "Frame" or className == "TextLabel"
				or className == "TextButton" or className == "ImageLabel"))
	end
	function methods:FindFirstChild(name)
		for _, child in ipairs(children) do if child.Name == name then return child end end
		return nil
	end
	function methods:WaitForChild(name) return methods.FindFirstChild(self, name) end
	function methods:GetChildren() local out = {} for i, c in ipairs(children) do out[i] = c end return out end
	function methods:GetDescendants()
		local out = {}
		local function walk(node)
			for _, child in ipairs(node.Children) do table.insert(out, child); walk(child) end
		end
		walk(inst)
		return out
	end
	function methods:SetAttribute(name, value)
		setAttributeCalls += 1
		local previous = attributes[name]
		attributes[name] = value
		if previous ~= value and signals[name] then signals[name]:Fire() end
	end
	function methods:GetAttribute(name) return attributes[name] end
	function methods:GetAttributeChangedSignal(name)
		signals[name] = signals[name] or signal()
		return signals[name]
	end
	function methods:GetPropertyChangedSignal(name)
		local key = "property:" .. name
		signals[key] = signals[key] or signal()
		return signals[key]
	end
	function methods:GetPivot() return CFrame.new(vec(0, 0, 0)) end
	function methods:Destroy()
		if fields.Parent then
			for index, child in ipairs(fields.Parent.Children) do
				if child == inst then table.remove(fields.Parent.Children, index) break end
			end
		end
		fields.Parent = nil
	end
	function methods:Fire(...) inst.Event:Fire(...) end

	inst = setmetatable({__instance = true, Children = children}, {
		__index = function(_, key)
			if methods[key] then return methods[key] end
			if key == "Position" and fields.CFrame then return fields.CFrame.Position end
			return fields[key]
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				if fields.Parent then
					for index, child in ipairs(fields.Parent.Children) do
						if child == inst then table.remove(fields.Parent.Children, index) break end
					end
				end
				if value then table.insert(value.Children, inst) end
			end
			fields[key] = value
		end,
	})
	fields.Triggered = signal()
	fields.Activated = signal()
	fields.Event = signal()
	fields.Destroying = signal()
	return inst
end

-- ── services ────────────────────────────────────────────────────────────────
local function makeFolder(name)
	local folder = Instance.new("Folder")
	folder.Name = name
	return folder
end

workspace = makeFolder("Workspace")
local replicated = makeFolder("ReplicatedStorage")
local players = makeFolder("Players")
heartbeat = signal()
local runService = {Heartbeat = heartbeat}
local marketplace = {}
marketplaceCalls = 0
function marketplace:GetProductInfo(id, infoType)
	marketplaceCalls += 1
	task.wait()  -- a real web call yields; the card must read before it answers
	return {PriceInRobux = 77, Name = "live"}
end
local services = {
	Players = players,
	ReplicatedStorage = replicated,
	RunService = runService,
	MarketplaceService = marketplace,
	TweenService = {Create = function() return {Play = function() end} end},
}
game = {
	GetService = function(_, name)
		local service = services[name]
		if not service then error("the shop must not use " .. name, 0) end
		return service
	end,
}
script = Instance.new("LocalScript")

-- ── the player ──────────────────────────────────────────────────────────────
player = Instance.new("Player")
player.Name = "Tester"
player.UserId = 4242
local playerGui = makeFolder("PlayerGui")
playerGui.Parent = player
local playerScripts = makeFolder("PlayerScripts")
playerScripts.Parent = player
local character = makeFolder("Character")
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.CFrame = CFrame.new(vec(0, 3, 0))
root.Parent = character
player.Character = character
players.LocalPlayer = player
function players:GetPlayers() return {player} end

function standAt(x, z)
	root.CFrame = CFrame.new(vec(x, 3, z))
end

-- ── the modules ─────────────────────────────────────────────────────────────
local moduleResults = {}
function require(target)
	local result = moduleResults[target.Name]
	if not result then error("no fake module for " .. tostring(target.Name), 0) end
	return result
end

local function loadConfig()
CONFIG_SOURCE
end
local configModule = makeFolder("ZyntraConfig")
configModule.Parent = replicated
moduleResults.ZyntraConfig = loadConfig()

-- UIDevice, stubbed to the surface the card actually uses.
uiState = {
	Touch = false,
	Modal = false,
	Safe = {Left = 0, Top = 0, Right = 1280, Bottom = 720},
	Viewport = {Width = 1280, Height = 720},
}
local uiChanged = signal()
local modalWatchers = {}
local UIDevice = {Changed = uiChanged}
function UIDevice.Layout()
	return {
		Safe = uiState.Safe,
		ModalViewport = {Width = uiState.Viewport.Width, Height = uiState.Viewport.Height},
		ModalArea = uiState.ModalArea,
		IsTouch = uiState.Touch,
		Zones = uiState.Zones,
	}
end
function UIDevice.LocalPosition(_, x, y) return UDim2.fromOffset(x, y) end
function UIDevice.ScreenOwningModalOpen() return uiState.Modal end
function UIDevice.OnScreenOwningModalChanged(fn) table.insert(modalWatchers, fn) end
function UIDevice.SetEnabled(element, enabled) element.Active = enabled end
function fireModalChanged() for _, fn in ipairs(modalWatchers) do fn() end end
function fireUIChanged() uiChanged:Fire() end
local uiModule = makeFolder("UIDevice")
uiModule.Parent = replicated
moduleResults.UIDevice = UIDevice

local function loadServer()
SERVER_SOURCE
end
Shop = loadServer()
"""

CLIENT_LOADER = r"""
local function loadClient()
CLIENT_SOURCE
end
loadClient()
"""

ASSERTIONS = r"""
-- ── 1. the build ────────────────────────────────────────────────────────────
local lobby = Instance.new("Model")
lobby.Name = "ServerLobby"
lobby.Parent = workspace
local center = Vector3.new(0, 0, 0)

local model = Shop.Build(lobby, {Center = center})
check(model ~= nil, "Build returned nothing")
check(model.Name == "ZyntraShopDisplay", "wrong model name: " .. tostring(model.Name))
check(model.Parent == lobby, "the shop is not parented to the lobby")

local catalogueKeys = {}
for _, source in ipairs({moduleResults.ZyntraConfig.Passes, moduleResults.ZyntraConfig.Products}) do
	for key in pairs(source) do table.insert(catalogueKeys, key) end
end
check(#catalogueKeys == 6, "expected 6 catalogue items, found " .. #catalogueKeys)

local stands = {}
for _, child in ipairs(model:GetChildren()) do
	if child.ClassName == "Model" then
		local key = child:GetAttribute("ShopItemKey")
		check(key ~= nil, "a stand with no item key")
		check(stands[key] == nil, "two stands for " .. tostring(key))
		stands[key] = child
	end
end
for _, key in ipairs(catalogueKeys) do
	check(stands[key] ~= nil, "no pedestal for catalogue item " .. key)
end
check(model:GetAttribute("ShopItemCount") == #catalogueKeys, "item count attribute disagrees")

-- 2. every stand is complete, and only the pedestal is solid.
local plateCount, promptCount, boxCount = 0, 0, 0
for key, stand in pairs(stands) do
	local seen = {}
	for _, node in ipairs(stand:GetDescendants()) do
		seen[node.Name] = (seen[node.Name] or 0) + 1
		if node.ClassName == "Part" then
			check(node.Anchored == true, key .. ": " .. node.Name .. " is not anchored")
			local solid = node.Name == "ShopPedestal"
			check(node.CanCollide == solid, key .. ": " .. node.Name .. " collision is wrong")
		end
		if node.ClassName == "ProximityPrompt" then
			promptCount += 1
			check(node.ActionText == "INSPECT", "prompt says " .. tostring(node.ActionText))
			-- The prompt is the deliberate alternative to the plate on touch and
			-- gamepad, so it needs both bindings.
			check(node.KeyboardKeyCode ~= nil and node.GamepadKeyCode ~= nil, key .. ": prompt binding")
		end
	end
	check(seen.ShopPedestal == 1, key .. ": pedestal count " .. tostring(seen.ShopPedestal))
	check(seen.ShopPedestalCap == 1, key .. ": cap count")
	check(seen.ShopItemBox == 1, key .. ": crate count")
	check(seen.ShopInspectPlate == 1, key .. ": plate count")
	plateCount += seen.ShopInspectPlate
	boxCount += seen.ShopItemBox
end
check(plateCount == #catalogueKeys and promptCount == #catalogueKeys and boxCount == #catalogueKeys,
	"one plate, prompt and crate per item")

-- 3. it stays inside the empty stretch of wall and never crosses the wall face.
for _, node in ipairs(model:GetDescendants()) do
	if node.ClassName == "Part" then
		local p = node.Position
		check(p.Z <= -45 and p.Z >= -70, node.Name .. " is outside z -70..-45: " .. p.Z)
		check(p.X >= 25 and p.X <= 32.9, node.Name .. " is outside the ledge: " .. p.X)
		check(p.Y >= 0.6 and p.Y <= 11, node.Name .. " is outside y 0.6..11: " .. p.Y)
	end
end

-- 4. a rebuild replaces the shop instead of stacking one on top of it.
local rebuilt = Shop.Build(lobby, {Center = center})
local shopModels = 0
for _, child in ipairs(lobby:GetChildren()) do
	if child.Name == "ZyntraShopDisplay" then shopModels += 1 end
end
check(shopModels == 1, "rebuild left " .. shopModels .. " shops")
check(rebuilt ~= model, "rebuild returned the old model")
model = rebuilt

-- ── 5. focus ────────────────────────────────────────────────────────────────
local plates = {}
for key, stand in pairs(stands) do plates[key] = nil end
stands = {}
for _, child in ipairs(model:GetChildren()) do
	if child.ClassName == "Model" then stands[child:GetAttribute("ShopItemKey")] = child end
end
for key, stand in pairs(stands) do
	for _, node in ipairs(stand:GetDescendants()) do
		if node.Name == "ShopInspectPlate" then plates[key] = node.Position end
	end
end

local sample = "Tokens4"
local samplePlate = plates[sample]
check(samplePlate ~= nil, "no plate position for " .. sample)

check(player:GetAttribute("ZyntraShopFocus") == nil, "focus started set")
standAt(samplePlate.X, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") == sample,
	"standing on the plate did not publish focus: " .. tostring(player:GetAttribute("ZyntraShopFocus")))
check(marketplaceCalls == 0, "the server touched MarketplaceService for a focus")

-- The attribute is written on a CHANGE, not on every pass: the poll is the
-- debounce. Ten more passes standing still must write nothing.
local before = setAttributeCalls
step(10)
check(setAttributeCalls == before, "focus rewrote the attribute while standing still")

-- Hysteresis: 0.3 studs past the plate's edge still counts while already inside.
standAt(samplePlate.X, samplePlate.Z + 2.0)
step()
check(player:GetAttribute("ZyntraShopFocus") == sample, "hysteresis dropped focus at the edge")

standAt(samplePlate.X - 9, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") == nil, "walking off did not clear focus")

-- The prompt is the other way in, and pressing it again closes.
local prompt
for _, node in ipairs(stands[sample]:GetDescendants()) do
	if node.ClassName == "ProximityPrompt" then prompt = node end
end
prompt.Triggered:Fire(player)
check(player:GetAttribute("ZyntraShopFocus") == sample, "INSPECT did not open")
prompt.Triggered:Fire(player)
check(player:GetAttribute("ZyntraShopFocus") == nil, "INSPECT did not toggle closed")

-- A latch only survives while the player stays near that pedestal.
prompt.Triggered:Fire(player)
standAt(0, 0)
step()
check(player:GetAttribute("ZyntraShopFocus") == nil, "the prompt's focus followed the player away")

-- In a round, the lobby shop says nothing at all.
standAt(samplePlate.X, samplePlate.Z)
player:SetAttribute("InRound", true)
step()
check(player:GetAttribute("ZyntraShopFocus") == nil, "focus published during a round")
player:SetAttribute("InRound", nil)
step()
check(player:GetAttribute("ZyntraShopFocus") == sample, "focus did not come back after the round")
"""

CLIENT_ASSERTIONS = r"""
-- ── 6. the card ─────────────────────────────────────────────────────────────
local gui = playerGui:FindFirstChild("ZyntraShopDisplayCard")
check(gui ~= nil, "the client never built its ScreenGui")
local card = gui:FindFirstChild("ShopDetailCard")
local buy = card:FindFirstChild("Buy")
local closeButton = card:FindFirstChild("Close")
local title = card:FindFirstChild("ItemName")
local state = card:FindFirstChild("ItemState")
check(buy and closeButton and title and state, "the card is missing its parts")

player:SetAttribute("ZyntraShopFocus", nil)
check(gui.Enabled == false, "the card is open with no focus")

player:SetAttribute("ZyntraShopFocus", "Tokens4")
check(gui.Enabled == true, "the card did not open on focus")
check(title.Text == moduleResults.ZyntraConfig.Products.Tokens4.Name, "wrong name: " .. tostring(title.Text))
check(buy.Text == "49 R$", "the card did not state the configured price: " .. tostring(buy.Text))
step()  -- the live price fetch answers
check(buy.Text == "77 R$", "the card ignored the live price: " .. tostring(buy.Text))

-- BUY is a request to ZyntraStore, and exactly one.
local bridge = Instance.new("BindableEvent")
bridge.Name = "ZyntraShopBuy"
bridge.Parent = playerScripts
local fired = {}
bridge.Event:Connect(function(key) table.insert(fired, key) end)
buy.Activated:Fire()
check(#fired == 1 and fired[1] == "Tokens4", "BUY did not route once: " .. #fired)

-- CLOSE dismisses this focus only.
closeButton.Activated:Fire()
check(gui.Enabled == false, "CLOSE did not hide the card")
player:SetAttribute("ZyntraShopFocus", nil)
player:SetAttribute("ZyntraShopFocus", "Tokens4")
check(gui.Enabled == true, "stepping back on did not reopen the card")

-- An owned pass states the reason instead of offering the sale again.
player:SetAttribute("ZyntraOwnsSupporter", true)
player:SetAttribute("ZyntraShopFocus", "Supporter")
check(buy.Text == "OWNED", "an owned pass still offered a price: " .. tostring(buy.Text))
check(buy.Active == false, "an owned pass left BUY in the input stack")
buy.Activated:Fire()
check(#fired == 1, "an owned pass still routed a purchase")

-- Stored credits are a used-state, not an owned-state: you may buy more.
player:SetAttribute("ZyntraReentryCredits", 2)
player:SetAttribute("ZyntraShopFocus", "EmergencyReentry")
check(state.Text:find("2") ~= nil, "the card did not state the stored credits: " .. state.Text)
check(buy.Active == true, "re-entry credits blocked a second purchase")

-- A modal that owns the screen takes the card down with it.
uiState.Modal = true
fireModalChanged()
check(gui.Enabled == false, "the card stayed up under the terminal")
uiState.Modal = false
fireModalChanged()
check(gui.Enabled == true, "the card did not come back")

-- ── 7. the three tiers ──────────────────────────────────────────────────────
local function measure(touch, width, height)
	uiState.Touch = touch
	uiState.Viewport = {Width = width, Height = height}
	uiState.Safe = {Left = 0, Top = 0, Right = width, Bottom = height}
	uiState.Zones = touch and {Controls = {Top = height - 140}} or nil
	fireUIChanged()
	local icon = card:FindFirstChild("ItemIcon")
	return {
		Width = card.Size.X.Offset,
		Height = card.Size.Y.Offset,
		Icon = icon.Size.X.Offset,
		Buy = buy.Size.Y.Offset,
		Desc = card:FindFirstChild("ItemDescription").TextSize,
		Top = card.Position.Y.Offset,
	}
end

-- MODAL VIEWPORTS, not raw screens -- the same measure the terminal's own tier
-- choice is made against. 956x382 is the 956x440 landscape phone from
-- test_zyntra_store_compact.py once its topbar inset is taken off; the other
-- two are an ordinary tablet and a desktop viewport.
local phone = measure(true, 956, 382)
local tablet = measure(true, 1024, 700)
local pointer = measure(false, 1280, 684)
-- The terminal's own Shop icon ladder, so a crate's card and its terminal card
-- are visibly the same object.
check(phone.Icon == 52 and tablet.Icon == 64 and pointer.Icon == 76,
	"tier icons: " .. phone.Icon .. "/" .. tablet.Icon .. "/" .. pointer.Icon)
check(phone.Width == 300 and tablet.Width == 380 and pointer.Width == 420,
	"tier widths: " .. phone.Width .. "/" .. tablet.Width .. "/" .. pointer.Width)
check(phone.Buy >= 44 and tablet.Buy >= 44, "a touch tier drew a tap target under 44")
check(pointer.Buy >= 32, "the pointer tier drew a tap target under 32")
check(phone.Desc >= 11 and tablet.Desc >= 11 and pointer.Desc >= 11, "type under 11px")
-- Every tier fits the screen it was measured on, and clears the touch cluster.
check(phone.Width <= 956 and phone.Top + phone.Height <= 382 - 140,
	"the phone card overlaps the movement cluster")
check(pointer.Height <= 684, "the pointer card does not fit")

-- A SHORT screen gives way in the authored order: the icon/description row
-- shrinks, the state line goes, and the tap target and the type never move.
-- 568x262 is the smallest landscape handheld UIDevice documents.
local short = measure(true, 568, 262)
check(short.Top >= 0 and short.Top + short.Height <= 262,
	"the 568x262 card left the screen: top " .. short.Top .. " h " .. short.Height)
check(short.Buy >= 44, "the short screen shrank the tap target to " .. short.Buy)
check(short.Desc >= 11, "the short screen shrank the type to " .. short.Desc)
check(short.Icon >= 28 and short.Icon <= 52, "the icon gave way past its floor: " .. short.Icon)
-- The BUY row is inside the card it is drawn in, which is the thing a clipped
-- card actually costs the player.
local buyBottom = buy.Position.Y.Offset + buy.Size.Y.Offset
check(buyBottom <= short.Height, "BUY is clipped off the card: " .. buyBottom .. " > " .. short.Height)

-- Native UIDevice's short-landscape free lane: right of the thumbstick and
-- above the movement row. The card must use that lane, not screen centre.
uiState.ModalArea = {Left=235, Top=8, Right=555, Bottom=164}
local lane = measure(true, 568, 320)
check(card.Position.X.Offset >= 235, "shop card reaches into the thumbstick")
check(card.Position.X.Offset + card.Size.X.Offset <= 555, "shop card leaves the free lane")
check(lane.Top >= 8 and lane.Top + lane.Height <= 164, "shop card covers the bottom controls")
check(lane.Buy >= 44, "free-lane composition shrank BUY")
uiState.ModalArea = nil

-- ── 8. motion ───────────────────────────────────────────────────────────────
local boxes, glow = {}, nil
for _, node in ipairs(model:GetDescendants()) do
	if node.Name == "ShopItemBox" then table.insert(boxes, node) end
	if node.Name == "ShopSignGlowPanel" then glow = node end
end
check(#boxes == 6 and glow ~= nil, "the client has nothing to animate")
local restingY = boxes[1].Position.Y
local restingGlow = glow.Transparency

local function sampleMotion(seconds)
	local lowest, highest = math.huge, -math.huge
	local movedY = false
	for _ = 1, seconds * 30 do
		heartbeat:Fire(1 / 30)
		lowest = math.min(lowest, glow.Transparency)
		highest = math.max(highest, glow.Transparency)
		if math.abs(boxes[1].Position.Y - restingY) > 0.05 then movedY = true end
	end
	return highest - lowest, movedY
end

local swing, bobbed = sampleMotion(7)
check(bobbed, "the crates never bobbed")
check(swing > 0.15, "the sign never breathed: " .. swing)

player:SetAttribute("ReduceFlashing", true)
local reducedSwing, stillBobbed = sampleMotion(7)
check(stillBobbed, "ReduceFlashing stopped the crates as well")
check(reducedSwing < swing * 0.6, "ReduceFlashing did not calm the sign: "
	.. reducedSwing .. " vs " .. swing)
check(reducedSwing <= 0.11, "ReduceFlashing left a visible pulse: " .. reducedSwing)
player:SetAttribute("ReduceFlashing", nil)

-- A round stops everything and puts every pose back.
workspace:SetAttribute("RoundActive", true)
heartbeat:Fire(1 / 30)
check(near(boxes[1].Position.Y, restingY, 0.0001), "a crate was left bobbing in a round")
check(near(glow.Transparency, restingGlow, 0.0001), "the sign was left mid-pulse in a round")
local frozen = boxes[1].Position.Y
heartbeat:Fire(1 / 30)
check(near(boxes[1].Position.Y, frozen, 0.0001), "the crates kept moving in a round")
workspace:SetAttribute("RoundActive", nil)

-- ── 9. the shop going away takes the focus with it ──────────────────────────
standAt(samplePlate.X, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") ~= nil, "focus did not return before teardown")
model:Destroy()
step(2)
check(player:GetAttribute("ZyntraShopFocus") == nil, "a destroyed shop left a card open")

print(string.format("ok  %d checks: 6 stands, %d plates, three tiers %d/%d/%d px",
	checks, plateCount, phone.Width, tablet.Width, pointer.Width))
"""


def indent(source: str) -> str:
    return "\n".join(("\t" + line) if line.strip() else line for line in source.splitlines())


def build_program() -> str:
    body = PRELUDE.replace("CONFIG_SOURCE", indent(CONFIG))
    body = body.replace("SERVER_SOURCE", indent(SERVER))
    client = CLIENT_LOADER.replace("CLIENT_SOURCE", indent(CLIENT))
    return body + ASSERTIONS + client + CLIENT_ASSERTIONS


def main() -> int:
    if not LUAU.exists():
        print(f"skip  no luau interpreter at {LUAU} (set LUAU_BIN)")
        return 0
    program = build_program()
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "shop.luau"
        path.write_text(program, encoding="utf-8")
        done = subprocess.run([str(LUAU), str(path)], capture_output=True, text=True)
    sys.stdout.write(done.stdout)
    if done.returncode != 0:
        sys.stderr.write(done.stderr)
        return done.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
