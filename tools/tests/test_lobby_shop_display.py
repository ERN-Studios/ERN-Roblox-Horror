"""The lobby SHOP wall (Trello #88 -> #105 -> the 2026-09-16 refresh): the real
server module and the real client LocalScript, executed against a fake DataModel.

Both scripts are RUN, not pattern-matched -- LobbyShopDisplay.Build against a
fake lobby and the real ZyntraConfig catalogue, and Shop Display Client against
a fake PlayerGui/UIDevice -- so this fails on a typo as well as on a contract.

v4 is a deletion. The shopfront (deck, backdrop, pilasters, canopy, the overhead
SHOP sign, nameplates, projector discs, beams, the DAILY REWARDS plaque and its
prompt) and TunnelLobbyBuilder's whole ZyntraSupplyKiosk are gone; what is left
is eight product boxes strung along the wall between the Level 2 and Level 4
gates. What this holds:

  * EIGHT stands, one per catalogue item, evenly spaced at z = -66 + 52/7 * i,
    and each stand is exactly one hologram box and one INVISIBLE pressure plate;
  * the box is a 3.40 cube at (30.20, 7.00) wearing the product art on ALL SIX
    faces at Transparency 0 on a part that is 0.35 transparent, with its neon
    edge, its PointLight, its ShopBobOrigin and a distinct ShopBobPhase;
  * every box centre stays >= 3.4 studs clear of both gate post edges
    (rel z -69.45 and -10.55) so the gate openings stay walkable, and two plate
    zones are >= 4.0 studs apart so walking the row cannot switch product by
    accident;
  * EVERY corner of EVERY part is inside the tunnel's envelope -- r <= 33.70
    against the shell, r <= 33.05 for the slot that crosses the rib arch at
    z -52.36..-51.64 -- at rest AND at the top of the client's bob;
  * NOTHING is named Deck/Backdrop/Sign/NamePlate/Projector/Plinth/Plaque/
    Prompt, there is no ProximityPrompt and no drawn text ANYWHERE in the model,
    so no "SUPPLY" and no "ZYNTRA //" can survive on the wall;
  * the plates are the ONLY trigger: stepping on publishes ZyntraShopFocus,
    stepping across switches it, stepping off clears it, standing still writes
    nothing, and NOTHING on the server touches MarketplaceService;
  * the card carries the eyebrow "SHOP" -- the one place the word is written --
    and the kind tags PERMANENT PASS / TOKEN ITEM / ROBUX PRODUCT, states OWNED
    for an owned pass, routes BUY to PlayerScripts.ZyntraShopBuy exactly once,
    and CLOSE dismisses the current focus WITHOUT reopening while the player
    stands still;
  * the bob is y = origin + 0.35 * sin(t * 2pi / 3.4 + ShopBobPhase), checked
    against the server's own phase per box, never turns, and stands down in a
    round and under ReduceFlashing / ReduceCameraShake, restoring every pose;
  * the card draws three tiers (52/64/112px icon, 300/380/560 wide) and keeps a
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
BUILDER = (ROOT / "ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua").read_text(encoding="utf-8")

# ── source contracts that the run cannot see ────────────────────────────────
# A purchase prompt anywhere in the server module would mean walking onto a
# plate could cost money. The fake engine refuses MarketplaceService as well,
# but state it here too: this is the rule the owner's brief is built on.
for forbidden in ("PromptProductPurchase", "PromptGamePassPurchase", 'GetService("MarketplaceService")'):
    assert forbidden not in SERVER, f"server module must not reference {forbidden}"
# The card's BUY is a request to ZyntraStore, never its own prompt.
for forbidden in ("PromptProductPurchase", "PromptGamePassPurchase"):
    assert forbidden not in CLIENT, f"client must not call {forbidden} itself"
# #105 removed the Inspect interaction outright, and v4 removed the last prompt
# of any kind from the wall: the whole idea is gone, not renamed.
for name, source in (("server", SERVER), ("client", CLIENT)):
    assert "inspect" not in source.lower(), f"{name} still mentions the removed Inspect interaction"
assert "ProximityPrompt" not in SERVER, "the shop wall must not build a prompt of any kind"
# Nothing turns the boxes: the product art has to stay square to whoever reads it.
assert "CFrame.Angles" not in CLIENT, "the client must not rotate the hologram boxes"
# The same tier expression the terminal's Shop and Upgrades pages use, so the
# three tiers cannot drift apart silently.
assert "})[(compact and touch) and 1 or (touch and 2 or 3)]" in CLIENT
STORE = (ROOT / "StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua").read_text(encoding="utf-8")
assert "})[(fit.Compact and fit.Touch) and 1 or (fit.Touch and 2 or 3)]" in STORE

# ── the second shop is gone from TunnelLobbyBuilder ─────────────────────────
# ZyntraSupplyKiosk stood 12 studs from the frontage with its own SHOP masthead,
# "ZYNTRA // SUPPLY" fascia, counter, canisters, telemetry, shopkeeper and the
# ShopAccessTerminal that carried ZyntraShopPrompt. The builder must no longer
# define it, call it, or build the shopkeeper it parented.
for forbidden in (
    "addSupplyKiosk(concourse",
    "local function addSupplyKiosk",
    "local function addGameplayShopkeeper",
    'kiosk.Name = "ZyntraSupplyKiosk"',
    '"ZyntraShopkeeper"',
    '"ShopAccessTerminal"',
    '"ShopkeeperPlatform"',
    'prompt.Name = "ZyntraShopPrompt"',
    "ZYNTRA  //  SUPPLY",
):
    assert forbidden not in BUILDER, f"TunnelLobbyBuilder still carries {forbidden!r}"
# The concourse the kiosk stood in keeps everything else it had.
for kept in (
    "addConcourseBench(concourse",
    "addDonationLeaderboard(concourse",
    "addPartyButton(concourse",
    "ArrivalGantryPost",
    "ConcourseCrossingStripe",
    "ZyntraSignalConsole",
):
    assert kept in BUILDER, f"TunnelLobbyBuilder lost {kept!r} along with the kiosk"
# And the shop is still started from there, untouched.
assert 'require(script.Parent:WaitForChild("LobbyShopDisplay")).Build(model, {Center = center})' in BUILDER

# Every product keeps its OWN art: eight distinct ids, none shared.
BOX_TEXTURES = re.search(r"\tBox = \{\n(.*?)\n\t\},", SERVER, re.S)
assert BOX_TEXTURES, "SHOP_TEXTURES.Box not found"
BOX_IDS = dict(re.findall(r"(\w+) = \"(rbxassetid://\d+)\"", BOX_TEXTURES.group(1)))
assert len(BOX_IDS) == 8, f"expected 8 product textures, found {len(BOX_IDS)}"
assert len(set(BOX_IDS.values())) == 8, "two products share one texture id"

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
warnings = {}
function warn(...) table.insert(warnings, table.concat({...}, " ")) end
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
	function methods:FindFirstChildOfClass(kind)
		for _, child in ipairs(children) do if child.ClassName == kind then return child end end
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
-- ── 0. the envelope, measured the same way the module documents it ──────────
-- Every part in the shop is placed with CFrame.lookAt across the road, i.e. a
-- quarter turn about Y, so a part's LOCAL x runs along the tunnel and its local
-- z is depth. Anything placed another way would be a new convention and this
-- helper would have to be revisited rather than quietly mis-measuring it.
local SHELL_LIMIT, RIB_LIMIT = 33.70, 33.05
local RIB_NEAR, RIB_FAR = -52.36, -51.64
local BOB = 0.35                 -- the client's amplitude; the envelope owns it
local GATE_L2, GATE_L4 = -69.45, -10.55   -- post edges facing the shop wall
local GATE_CLEARANCE = 3.4

local function extents(part)
	local size, cf = part.Size, part.CFrame
	local sideways = math.abs(math.cos(cf.Yaw)) < 0.001
	return cf.Position,
		(sideways and size.Z or size.X) * 0.5,
		size.Y * 0.5,
		(sideways and size.X or size.Z) * 0.5
end

-- All EIGHT corners, not the centre and not the bounding sphere: the corner is
-- the thing that pokes through a curved concrete shell. `lift` is how far the
-- client may raise the part, so a bobbing box is measured at the top of its bob.
local function worstRadius(part, lift)
	local pos, hx, hy = extents(part)
	local worst = 0
	for _, sx in ipairs({-1, 1}) do
		for _, sy in ipairs({-1, 1}) do
			local x, y = pos.X + sx * hx, pos.Y + sy * hy + (sy > 0 and (lift or 0) or 0)
			local r = math.sqrt(x * x + (y - 1) * (y - 1))
			if r > worst then worst = r end
		end
	end
	return worst
end

local function crossesRib(part)
	local pos, _, _, hz = extents(part)
	return (pos.Z - hz) <= RIB_FAR and (pos.Z + hz) >= RIB_NEAR
end

-- ── 1. the build ────────────────────────────────────────────────────────────
local lobby = Instance.new("Model")
lobby.Name = "ServerLobby"
lobby.Parent = workspace
local center = Vector3.new(0, 0, 0)

local model = Shop.Build(lobby, {Center = center})
check(model ~= nil, "Build returned nothing")
check(model.Name == "ZyntraShopDisplay", "wrong model name: " .. tostring(model.Name))
check(model.Parent == lobby, "the shop is not parented to the lobby")
check(model:GetAttribute("ShopDisplayVersion") == 4, "the wall build must bump the version to 4")
check(model:GetAttribute("Placement") == "Right wall between the Level 2 and Level 4 gates",
	"placement: " .. tostring(model:GetAttribute("Placement")))
check(model:GetAttribute("FocusAttribute") == "ZyntraShopFocus", "the focus contract moved")
check(near(model:GetAttribute("FrontmostX"), 27.78 - 1.60, 0.0001),
	"FrontmostX disagrees with the plates: " .. tostring(model:GetAttribute("FrontmostX")))
-- The kiosk bays are gone, so nothing publishes a canopy ceiling any more.
check(model:GetAttribute("CanopyClearanceY") == nil, "the canopy attribute outlived the canopy")
check(#warnings == 0, "the build warned: " .. table.concat(warnings, " | "))

local catalogueKeys = {}
for _, source in ipairs({moduleResults.ZyntraConfig.Passes, moduleResults.ZyntraConfig.Products, moduleResults.ZyntraConfig.Items}) do
	for key in pairs(source) do table.insert(catalogueKeys, key) end
end
check(#catalogueKeys == 8, "expected 8 catalogue items, found " .. #catalogueKeys)

local stands = {}
local standCount = 0
for _, child in ipairs(model:GetChildren()) do
	check(child.ClassName == "Model", "the shop grew a loose " .. child.ClassName .. " named " .. child.Name)
	local key = child:GetAttribute("ShopItemKey")
	check(key ~= nil, "a stand with no item key")
	check(stands[key] == nil, "two stands for " .. tostring(key))
	stands[key] = child
	standCount += 1
end
check(standCount == 8, "the wall has " .. standCount .. " stands, expected 8")
for _, key in ipairs(catalogueKeys) do
	check(stands[key] ~= nil, "no hologram for catalogue item " .. key)
end
check(model:GetAttribute("ShopItemCount") == 8, "item count attribute disagrees")

-- ── 2. a stand is ONE box and ONE plate, and nothing else ───────────────────
local FACES = {"Front", "Back", "Left", "Right", "Top", "Bottom"}
local boxByKey, plateByKey, artByKey, phaseByKey = {}, {}, {}, {}
for key, stand in pairs(stands) do
	local seen, parts = {}, {}
	for _, node in ipairs(stand:GetDescendants()) do
		seen[node.ClassName] = (seen[node.ClassName] or 0) + 1
		if node.ClassName == "Part" then parts[node.Name] = node end
	end
	check(seen.Part == 2, key .. ": a stand is one box and one plate, found " .. tostring(seen.Part) .. " parts")
	local box, plate = parts.ShopHologramBox, parts.ShopPressurePlate
	check(box ~= nil and plate ~= nil, key .. ": the stand lost its box or its plate")
	boxByKey[key], plateByKey[key] = box, plate

	-- THE BOX. A 3.40 cube of translucent light, invisible to every query.
	check(box.Material == Enum.Material.ForceField, key .. ": the box is not a hologram material")
	check(near(box.Transparency, 0.35), key .. ": box transparency " .. tostring(box.Transparency))
	check(near(box.Size.X, 3.40) and near(box.Size.Y, 3.40) and near(box.Size.Z, 3.40),
		key .. ": box is not a 3.40 cube")
	check(near(box.Position.X, 30.20), key .. ": box x " .. box.Position.X)
	check(near(box.Position.Y, 7.00), key .. ": box y " .. box.Position.Y)
	check(box.Anchored == true, key .. ": the box is not anchored")
	check(box.CanCollide == false and box.CanQuery == false and box.CanTouch == false,
		key .. ": the box is in the way of something")
	check(box:GetAttribute("ShopItemKey") == key, key .. ": the box lost its key")
	check(typeof(box:GetAttribute("ShopBobOrigin")) == "CFrame", key .. ": no ShopBobOrigin for the client")
	check(tostring(box:GetAttribute("ShopTextureSlot")) == "Box:" .. key, key .. ": no texture slot")
	local phase = box:GetAttribute("ShopBobPhase")
	check(type(phase) == "number" and phase >= 0 and phase < math.pi * 2,
		key .. ": bob phase " .. tostring(phase))
	phaseByKey[key] = phase

	-- PRODUCT ART ON ALL SIX FACES, one Decal each, the same id, and opaque on a
	-- part that is not: a Decal inherits nothing from its part's transparency.
	local decals, byFace = 0, {}
	for _, node in ipairs(box:GetChildren()) do
		if node.ClassName == "Decal" then
			decals += 1
			check(node.Transparency == 0, key .. ": the product art inherited the box's transparency")
			check(tostring(node.Texture):match("^rbxassetid://%d+$") ~= nil, key .. ": bad texture url")
			check(byFace[node.Face.Name] == nil, key .. ": two decals on " .. node.Face.Name)
			byFace[node.Face.Name] = node.Texture
		end
	end
	check(decals == 6, key .. ": expected six decals, one per face, got " .. decals)
	for _, face in ipairs(FACES) do
		check(byFace[face] ~= nil, key .. ": no product art on the " .. face .. " face")
		check(byFace[face] == byFace.Front, key .. ": the " .. face .. " face shows another product")
	end
	artByKey[key] = byFace.Front
	check(seen.SurfaceGui == nil, key .. ": the box fell back to a drawn monogram")
	check(box:FindFirstChildOfClass("SelectionBox") ~= nil, key .. ": the neon edge is gone")
	check(box:FindFirstChildOfClass("PointLight") ~= nil, key .. ": the box light is gone")

	-- THE PLATE. Invisible by contract, and invisible to everything else too.
	check(near(plate.Transparency, 1), key .. ": the plate is still drawn")
	check(plate.CanQuery == false, key .. ": the plate can still be hit by a query")
	check(plate.CanCollide == false, key .. ": the plate is solid")
	check(plate.CanTouch == false, key .. ": the plate still fires Touched")
	check(plate:GetAttribute("ShopItemKey") == key, key .. ": the plate lost its key")
	check(#plate:GetChildren() == 0, key .. ": the plate still carries a stencil or a hint")
	check(near(plate.Size.X, 3.40) and near(plate.Size.Z, 3.20),
		key .. ": plate zone is " .. plate.Size.X .. " x " .. plate.Size.Z)
	check(near(plate.Position.X, 27.78), key .. ": plate x " .. plate.Position.X)
	check(near(plate.Position.Y, 0.71), key .. ": plate y " .. plate.Position.Y)
	check(near(plate.Position.Z, boxByKey[key].Position.Z),
		key .. ": the plate is not under its own box")
end

-- Each of the eight boxes shows its OWN product, never a neighbour's.
local artSeen = {}
for key, url in pairs(artByKey) do
	check(artSeen[url] == nil, key .. " and " .. tostring(artSeen[url]) .. " show the same art")
	artSeen[url] = key
end

-- The bob phases are spread over one cycle, so the row never pumps in unison.
local phases = {}
for _, phase in pairs(phaseByKey) do table.insert(phases, phase) end
table.sort(phases)
check(#phases == 8, "phase count")
for index = 2, #phases do
	check(phases[index] - phases[index - 1] > 0.5,
		"two boxes bob in step: " .. phases[index - 1] .. " and " .. phases[index])
end

-- ── 3. the row: evenly along the wall, clear of both gates ──────────────────
local row = {}
for key, box in pairs(boxByKey) do
	table.insert(row, {Z = box.Position.Z, Key = key})
end
table.sort(row, function(a, b) return a.Z < b.Z end)
check(#row == 8, "the row is not eight holograms: " .. #row)
for index, slot in ipairs(row) do
	local wanted = -66 + 52 / 7 * (index - 1)
	check(near(slot.Z, wanted, 1e-6),
		slot.Key .. " sits at z " .. slot.Z .. ", expected " .. wanted)
	-- Walkable gates: the brief's whole point is that the wall is now open from
	-- one doorway to the other.
	check(math.abs(slot.Z - GATE_L2) >= GATE_CLEARANCE - 1e-6,
		slot.Key .. " crowds the Level 2 gate post at z " .. slot.Z)
	check(math.abs(slot.Z - GATE_L4) >= GATE_CLEARANCE - 1e-6,
		slot.Key .. " crowds the Level 4 gate post at z " .. slot.Z)
	if index > 1 then
		local pitch = slot.Z - row[index - 1].Z
		check(near(pitch, 52 / 7, 1e-6), "the row pitch drifted at slot " .. index .. ": " .. pitch)
		-- 3.40 boxes at a 7.43 pitch leave about 4.03 studs of air; v3's had 0.15.
		check(pitch - 3.40 >= 3.9, "the boxes lost their air: " .. (pitch - 3.40))
	end
end

-- Two plate zones must stay far enough apart that walking the row cannot switch
-- product by accident, even with PLATE_HYSTERESIS reaching out of the held one.
local plateZ = {}
for _, slot in ipairs(row) do table.insert(plateZ, plateByKey[slot.Key].Position.Z) end
for index = 2, #plateZ do
	local gap = (plateZ[index] - plateZ[index - 1]) - 3.40
	check(gap >= 4.0 - 1e-6, "plate zones are only " .. gap .. " studs apart")
	check(gap > 0.6 + 0.6, "hysteresis on both sides can bridge the gap")
end

-- ── 4. every corner of every part, against the tunnel ───────────────────────
local partCount, worstShell, worstRib, ribParts = 0, 0, 0, 0
for _, node in ipairs(model:GetDescendants()) do
	if node.ClassName == "Part" then
		partCount += 1
		local pos, halfX, halfY = extents(node)
		-- A box is measured at the top of the client's bob, because that is where
		-- it actually gets to on a live server.
		local lift = node.Name == "ShopHologramBox" and BOB or 0
		local r = worstRadius(node, lift)
		if r > worstShell then worstShell = r end
		check(r <= SHELL_LIMIT, node.Name .. " corner r = " .. r .. " is inside the concrete shell")
		if crossesRib(node) then
			ribParts += 1
			if r > worstRib then worstRib = r end
			check(r <= RIB_LIMIT, node.Name .. " crosses the rib arch at r = " .. r)
		end
		-- The walkway, measured at the road-side face rather than the centre. The
		-- ledge's road edge is x 22.8 and nothing may reach past it.
		check(pos.X - halfX >= 22.80 - 0.0001,
			node.Name .. " reaches to x " .. (pos.X - halfX) .. ", past the road edge")
		check(pos.Y - halfY >= 0.55, node.Name .. " is under the ledge at y " .. (pos.Y - halfY))
		check(pos.Y + halfY + lift <= 16, node.Name .. " is over the tunnel at y " .. (pos.Y + halfY))
		-- NOTHING in the shop is solid: the boxes hang over the walkway and the
		-- plates are floor. A player must be able to walk the whole wall.
		check(node.CanCollide == false, node.Name .. " is solid and blocks the walkway")
	end
end
check(partCount == 16, "expected 16 parts (8 boxes + 8 plates), got " .. partCount)
check(ribParts >= 2, "nothing measured against the rib arch, which cannot be right")
check(worstShell <= SHELL_LIMIT and worstRib <= RIB_LIMIT, "envelope summary disagrees with itself")
-- The boxes hang high enough to walk under: bottom 5.30 is 4.65 over the ledge.
for _, slot in ipairs(row) do
	check(boxByKey[slot.Key].Position.Y - 1.70 - 0.35 >= 0.65 + 4.0,
		slot.Key .. " hangs too low to walk under")
end

-- ── 5. the shopfront is GONE ────────────────────────────────────────────────
-- Not renamed, not hidden: no part of the old presentation is built at all, and
-- there is no drawn text and no prompt anywhere on the wall.
local RETIRED = {"deck", "backdrop", "sign", "nameplate", "projector", "beam", "plinth",
	"plaque", "prompt", "canopy", "fascia", "pilaster", "pedestal", "kiosk", "monogram",
	"trim", "flood", "soffit"}
local RETIRED_CLASSES = {ProximityPrompt = true, SurfaceGui = true, TextLabel = true,
	Texture = true, SurfaceLight = true, SpotLight = true, CylinderMesh = true}
for _, node in ipairs(model:GetDescendants()) do
	local lower = node.Name:lower()
	for _, word in ipairs(RETIRED) do
		check(lower:find(word, 1, true) == nil,
			"the retired " .. word .. " is still being built as " .. node.Name)
	end
	check(RETIRED_CLASSES[node.ClassName] == nil,
		"the wall still builds a " .. node.ClassName .. " (" .. node.Name .. ")")
end

-- ── 6. a rebuild replaces the shop instead of stacking one on top of it ─────
local rebuilt = Shop.Build(lobby, {Center = center})
local shopModels = 0
for _, child in ipairs(lobby:GetChildren()) do
	if child.Name == "ZyntraShopDisplay" then shopModels += 1 end
end
check(shopModels == 1, "rebuild left " .. shopModels .. " shops")
check(rebuilt ~= model, "rebuild returned the old model")
model = rebuilt

-- ── 7. focus: the plate is the whole trigger ────────────────────────────────
local plates = {}
stands = {}
for _, child in ipairs(model:GetChildren()) do
	if child.ClassName == "Model" and child:GetAttribute("ShopItemKey") then
		stands[child:GetAttribute("ShopItemKey")] = child
	end
end
for key, stand in pairs(stands) do
	for _, node in ipairs(stand:GetDescendants()) do
		if node.Name == "ShopPressurePlate" then plates[key] = node.Position end
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

-- DEBOUNCE. The attribute is written on a CHANGE, not on every pass: the poll
-- is the debounce. Ten more passes standing still must write nothing.
local before = setAttributeCalls
step(10)
check(setAttributeCalls == before, "focus rewrote the attribute while standing still")

-- Walking up to the hologram from the road crosses the zone and stays in it.
standAt(samplePlate.X - 1.55, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") == sample, "the road-side edge of the zone is dead")
standAt(samplePlate.X + 1.55, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") == sample, "the wall-side edge of the zone is dead")

-- Hysteresis: past the plate's edge still counts while already inside.
standAt(samplePlate.X, samplePlate.Z + 2.2)
step()
check(player:GetAttribute("ZyntraShopFocus") == sample, "hysteresis dropped focus at the edge")

-- SWITCHING. Stepping fully into the neighbour's zone hands the card over, and
-- the held zone's hysteresis does not out-vote it once the player has left.
local neighbour, neighbourPlate = nil, nil
for key, position in pairs(plates) do
	if key ~= sample and math.abs(position.Z - samplePlate.Z) < 7.5
		and math.abs(position.X - samplePlate.X) < 0.1 then
		neighbour, neighbourPlate = key, position
	end
end
check(neighbour ~= nil, "the row has no neighbouring slot to switch to")
standAt(neighbourPlate.X, neighbourPlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") == neighbour,
	"stepping to the next hologram did not switch: " .. tostring(player:GetAttribute("ZyntraShopFocus")))
-- And the walk BETWEEN them is a clean nil, not a flicker from one to the other:
-- 4.03 studs of dead air is exactly what stops an accidental product switch.
standAt(neighbourPlate.X, (neighbourPlate.Z + samplePlate.Z) * 0.5)
step()
check(player:GetAttribute("ZyntraShopFocus") == nil,
	"the gap between two boxes still holds a card open")
standAt(samplePlate.X, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") == sample, "switching back did not work")

-- LEAVING. No zone, no card, and no state left behind that could reopen it.
standAt(samplePlate.X - 9, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") == nil, "walking off did not clear focus")
step(5)
check(player:GetAttribute("ZyntraShopFocus") == nil, "focus came back after walking away")

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
-- ── 8. the card ─────────────────────────────────────────────────────────────
local gui = playerGui:FindFirstChild("ZyntraShopDisplayCard")
check(gui ~= nil, "the client never built its ScreenGui")
local card = gui:FindFirstChild("ShopDetailCard")
local shopTitle = card:FindFirstChild("ShopTitle")
local buy = card:FindFirstChild("Buy")
local closeButton = card:FindFirstChild("Close")
local title = card:FindFirstChild("ItemName")
local kindTag = card:FindFirstChild("ItemKind")
local state = card:FindFirstChild("ItemState")
local hint = card:FindFirstChild("CloseHint")
check(shopTitle and buy and closeButton and title and kindTag and state and hint,
	"the card is missing its parts")
-- The ONE place the word SHOP is written now that the sign and the kiosk
-- masthead are both deleted.
check(shopTitle.Text == "SHOP", "the card eyebrow says " .. tostring(shopTitle.Text))
check(shopTitle.Font == Enum.Font.GothamBlack, "the eyebrow is not GothamBlack")

player:SetAttribute("ZyntraShopFocus", nil)
check(gui.Enabled == false, "the card is open with no focus")

player:SetAttribute("ZyntraShopFocus", "Tokens4")
check(gui.Enabled == true, "the card did not open on focus")
check(title.Text == moduleResults.ZyntraConfig.Products.Tokens4.Name, "wrong name: " .. tostring(title.Text))
check(buy.Text == "49 R$", "the card did not state the configured price: " .. tostring(buy.Text))
step()  -- the live price fetch answers
check(buy.Text == "77 R$", "the card ignored the live price: " .. tostring(buy.Text))

-- ── 8b. the kind tags say what you are paying WITH ──────────────────────────
-- No "SUPPLY DROP", no "FIELD SUPPLIES", no "ZYNTRA //" anywhere the player can
-- read it. The product NAME and DESCRIPTION are catalogue content and are left
-- alone; these three labels are the shop's own voice.
local KIND_TAGS = {
	Tokens4 = "ROBUX PRODUCT",
	EmergencyReentry = "ROBUX PRODUCT",
	Supporter = "PERMANENT PASS",
	AdvancedEquipment = "PERMANENT PASS",
	SpeedPotion = "TOKEN ITEM",
	RouteMarker = "TOKEN ITEM",
}
for key, wanted in pairs(KIND_TAGS) do
	player:SetAttribute("ZyntraShopFocus", nil)
	player:SetAttribute("ZyntraShopFocus", key)
	check(kindTag.Text == wanted, key .. " is tagged " .. tostring(kindTag.Text) .. ", expected " .. wanted)
end
for _, label in ipairs({shopTitle, kindTag, hint, buy, closeButton}) do
	local text = tostring(label.Text):upper()
	check(text:find("SUPPLY", 1, true) == nil, label.Name .. " still says SUPPLY: " .. text)
	check(text:find("ZYNTRA", 1, true) == nil, label.Name .. " still says ZYNTRA: " .. text)
end

player:SetAttribute("ZyntraShopFocus", nil)
player:SetAttribute("ZyntraShopFocus", "Tokens4")

-- BUY is a request to ZyntraStore, and exactly one. Opening the card was not.
local bridge = Instance.new("BindableEvent")
bridge.Name = "ZyntraShopBuy"
bridge.Parent = playerScripts
local fired = {}
bridge.Event:Connect(function(key) table.insert(fired, key) end)
check(#fired == 0, "opening a card already asked for a purchase")
buy.Activated:Fire()
check(#fired == 1 and fired[1] == "Tokens4", "BUY did not route once: " .. #fired)

-- ── 9. CLOSE cannot loop ────────────────────────────────────────────────────
-- The card is raised by an attribute change and by nothing else, so a player
-- who closes it and then stands still must not see it again. Re-running every
-- signal the client listens to, WITHOUT moving the focus, has to leave it down.
closeButton.Activated:Fire()
check(gui.Enabled == false, "CLOSE did not hide the card")
player:SetAttribute("ZyntraSpeedPotions", 3)
player:SetAttribute("ZyntraReentryCredits", 1)
fireModalChanged()
fireUIChanged()
check(gui.Enabled == false, "the dismissed card came back while the player stood still")
-- Switching hologram is a change of focus, so the card is welcome again.
player:SetAttribute("ZyntraShopFocus", "Tokens20")
check(gui.Enabled == true, "walking to the next hologram did not reopen the card")
check(title.Text == moduleResults.ZyntraConfig.Products.Tokens20.Name, "the card did not switch product")
-- And so is stepping off and back on to the same one.
closeButton.Activated:Fire()
check(gui.Enabled == false, "CLOSE did not hide the card the second time")
player:SetAttribute("ZyntraShopFocus", nil)
player:SetAttribute("ZyntraShopFocus", "Tokens20")
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

-- ── 10. the three tiers ─────────────────────────────────────────────────────
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
		Close = closeButton.Size.Y.Offset,
		Desc = card:FindFirstChild("ItemDescription").TextSize,
		Kind = kindTag.TextSize,
		Eyebrow = shopTitle.Visible,
		EyebrowSize = shopTitle.TextSize,
		Hint = hint.Text,
		HintSize = hint.TextSize,
		HintWidth = hint.Size.X.Offset,
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
check(phone.Icon == 52 and tablet.Icon == 64 and pointer.Icon == 112,
	"tier icons: " .. phone.Icon .. "/" .. tablet.Icon .. "/" .. pointer.Icon)
check(phone.Width == 300 and tablet.Width == 380 and pointer.Width == 560,
	"tier widths: " .. phone.Width .. "/" .. tablet.Width .. "/" .. pointer.Width)
check(phone.Height == 217, "the phone card is no longer 300x217: " .. phone.Height)
check(phone.Buy >= 44 and tablet.Buy >= 44, "a touch tier drew a tap target under 44")
check(phone.Close >= 44 and tablet.Close >= 44, "a touch tier drew CLOSE under 44")
check(pointer.Buy >= 32, "the pointer tier drew a tap target under 32")
check(phone.Desc >= 11 and tablet.Desc >= 11 and pointer.Desc >= 11, "type under 11px")
check(phone.Kind >= 11 and phone.HintSize >= 11, "the hint row is under 11px")
-- Every tier that has the room shows the SHOP eyebrow, at readable type.
for _, tier in ipairs({phone, tablet, pointer}) do
	check(tier.Eyebrow, "a full-size tier hid the SHOP eyebrow")
	check(tier.EyebrowSize >= 11, "the eyebrow is under 11px: " .. tier.EyebrowSize)
end
-- Every tier fits the screen it was measured on, and clears the touch cluster.
check(phone.Width <= 956 and phone.Top + phone.Height <= 382 - 140,
	"the phone card overlaps the movement cluster")
check(pointer.Height <= 684 and pointer.Width <= 1280, "the pointer card does not fit")

-- The copy line says how to get rid of the card, and says the true thing for
-- the input the player has.
check(phone.Hint == "Step off the plate to close", "phone hint: " .. phone.Hint)
check(tablet.Hint == "Step off the plate to close", "tablet hint: " .. tablet.Hint)
check(pointer.Hint == "Step off the plate or press CLOSE", "pointer hint: " .. pointer.Hint)
for _, tier in ipairs({phone, tablet, pointer}) do
	check(tier.HintWidth >= 120, "the hint lane collapsed to " .. tier.HintWidth)
end

-- A SHORT screen gives way in the authored order: the icon/description row
-- shrinks, the state line goes, the eyebrow goes last, and the tap target and
-- the type never move. 568x262 is the smallest landscape handheld UIDevice
-- documents.
local short = measure(true, 568, 262)
check(short.Top >= 0 and short.Top + short.Height <= 262,
	"the 568x262 card left the screen: top " .. short.Top .. " h " .. short.Height)
check(short.Buy >= 44, "the short screen shrank the tap target to " .. short.Buy)
check(short.Desc >= 11, "the short screen shrank the type to " .. short.Desc)
check(short.Icon >= 28 and short.Icon <= 52, "the icon gave way past its floor: " .. short.Icon)
check(short.Eyebrow == false, "the eyebrow survived a band too short for BUY")
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
measure(false, 1280, 684)

-- ── 11. motion ──────────────────────────────────────────────────────────────
-- The exact formula the contract states: y = origin + 0.35 * sin(t*2pi/3.4 +
-- ShopBobPhase), per box, with the SERVER's phase. Nothing else moves, and the
-- server does no per-frame work at all -- this is the whole animation.
local BOB_HEIGHT, BOB_PERIOD = 0.35, 3.4
local clock = 0
local function beat(delta)
	clock += delta
	heartbeat:Fire(delta)
end

local boxes = {}
for _, node in ipairs(model:GetDescendants()) do
	if node.Name == "ShopHologramBox" then table.insert(boxes, node) end
end
check(#boxes == 8, "the client has nothing to animate: " .. #boxes)
local resting, origins, phasesById = {}, {}, {}
for index, box in ipairs(boxes) do
	resting[index] = box.Position.Y
	origins[index] = box:GetAttribute("ShopBobOrigin").Position.Y
	phasesById[index] = box:GetAttribute("ShopBobPhase")
	check(near(resting[index], origins[index]), "a box did not start at its own origin")
end
local restingYaw = boxes[1].CFrame.Yaw

local function checkFormula(why)
	for index, box in ipairs(boxes) do
		local wanted = origins[index]
			+ BOB_HEIGHT * math.sin(clock * (math.pi * 2 / BOB_PERIOD) + phasesById[index])
		check(near(box.Position.Y, wanted, 1e-9),
			why .. ": box " .. index .. " at " .. box.Position.Y .. ", formula says " .. wanted)
		check(near(box.CFrame.Yaw, restingYaw, 1e-9), why .. ": a box turned away")
	end
end

-- Seven seconds is two full 3.4 s periods and a bit, sampled against the
-- formula three times a second -- enough to catch a phase, amplitude or period
-- that drifts, without 1700 identical assertions.
local moved, reach = false, 0
for frame = 1, 7 * 30 do
	beat(1 / 30)
	if frame % 10 == 0 then checkFormula("bob") end
	for index, box in ipairs(boxes) do
		local offset = math.abs(box.Position.Y - resting[index])
		if offset > 0.05 then moved = true end
		if offset > reach then reach = offset end
	end
end
check(moved, "the holograms never bobbed")
-- The server sized the envelope to a 0.35 bob at the top of the box.
check(reach <= 0.3501, "the bob went past the 0.35 the geometry was solved for: " .. reach)
check(reach > 0.34, "the bob never reached its own amplitude: " .. reach)

-- Accessibility: a player who asked for less motion gets none, and every pose
-- goes back. The boxes are readable standing still -- the art is on all six
-- faces -- so this costs the shop nothing.
for _, flag in ipairs({"ReduceFlashing", "ReduceCameraShake"}) do
	player:SetAttribute(flag, true)
	beat(1 / 30)
	for index, box in ipairs(boxes) do
		check(near(box.Position.Y, origins[index], 1e-9), flag .. " left a box bobbing")
	end
	beat(1 / 30)
	for index, box in ipairs(boxes) do
		check(near(box.Position.Y, origins[index], 1e-9), flag .. " let a box drift")
	end
	player:SetAttribute(flag, nil)
	beat(1 / 30)
	checkFormula("after " .. flag)
end

-- A round stops everything and puts every pose back.
workspace:SetAttribute("RoundActive", true)
beat(1 / 30)
for index, box in ipairs(boxes) do
	check(near(box.Position.Y, origins[index], 1e-9), "a hologram was left bobbing in a round")
end
beat(1 / 30)
for index, box in ipairs(boxes) do
	check(near(box.Position.Y, origins[index], 1e-9), "the holograms kept moving in a round")
end
workspace:SetAttribute("RoundActive", nil)
beat(1 / 30)
checkFormula("after the round")

-- Token items reuse the same bridge and never ask Roblox for a Robux price.
local beforeTokenPriceCalls = marketplaceCalls
for _, key in ipairs({"SpeedPotion", "RouteMarker"}) do
	player:SetAttribute("ZyntraShopFocus", nil)
	player:SetAttribute("ZyntraShopFocus", key)
	check(gui.Enabled, key .. " card did not open")
	check(buy.Text == tostring(moduleResults.ZyntraConfig.Items[key].TokenCost) .. " TOKENS  //  BUY", key .. " wrong currency")
	local beforeBuy = #fired
	buy.Activated:Fire()
	check(#fired == beforeBuy + 1 and fired[#fired] == key, key .. " bridge did not route")
end
check(marketplaceCalls == beforeTokenPriceCalls, "token supplies called MarketplaceService")
player:SetAttribute("ZyntraRouteMarkers", 6)
check(state.Text == "6 STORED", "physical stock did not refresh")

-- ── 11b. the boxes replicate AFTER the model ─────────────────────────────────
-- Measured in Studio Play (2026-09-16): a client saw ZyntraShopDisplay with
-- none of its boxes on the frame it appeared, collected nothing, and never
-- looked again. The server stamps ShopItemCount when the row is complete, so a
-- client that holds fewer boxes than that keeps collecting until it has them.
do
	local lobbyModel = model.Parent
	local stands = {}
	for _, child in ipairs(model:GetChildren()) do
		if child.Name:sub(1, 10) == "ShopStand_" then table.insert(stands, child) end
	end
	check(#stands == 8, "expected eight stands to detach: " .. #stands)
	for _, stand in ipairs(stands) do stand.Parent = nil end
	-- A fresh model arrival: the client must drop the old one and pick this up.
	model.Parent = nil
	beat(1 / 30)
	model.Parent = lobbyModel
	beat(1 / 30)
	for _, stand in ipairs(stands) do stand.Parent = model end
	beat(1 / 30)
	beat(1 / 30)
	local late = false
	for index, box in ipairs(boxes) do
		if math.abs(box.Position.Y - origins[index]) > 0.05 then late = true end
	end
	check(late, "boxes that replicated after their model never bobbed")
	checkFormula("late-replicated boxes")
end

-- ── 12. the shop going away takes the focus with it ─────────────────────────
standAt(samplePlate.X, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") ~= nil, "focus did not return before teardown")
model:Destroy()
step(2)
check(player:GetAttribute("ZyntraShopFocus") == nil, "a destroyed shop left a card open")

print(string.format(
	"ok  %d checks: 8 boxes on %d parts, z %.2f..%.2f, worst corner r %.3f (shell) / %.3f (rib), tiers %d/%d/%d px",
	checks, partCount, row[1].Z, row[#row].Z, worstShell, worstRib, phone.Width, tablet.Width, pointer.Width))
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
