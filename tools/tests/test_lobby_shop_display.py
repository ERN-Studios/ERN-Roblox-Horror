"""The lobby SHOP wall (Trello #88, rebuilt as holograms for #105): the real
server module and the real client LocalScript, executed against a fake DataModel.

Both scripts are RUN, not pattern-matched -- LobbyShopDisplay.Build against a
fake lobby and the real ZyntraConfig catalogue, and Shop Display Client against
a fake PlayerGui/UIDevice -- so this fails on a typo as well as on a contract.

What it holds after #105:

  * one stand per catalogue item, and each stand is a projector disc, a beam, a
    floating hologram box and an INVISIBLE pressure plate -- no pedestal, no
    cap, no plate edge, no plate stencil and no INSPECT prompt anywhere;
  * the box wears the product art on the face that looks at the road, at
    Transparency 0 on a part that is 0.35 transparent, and keeps its neon edge,
    its PointLight and the ShopBobOrigin the client animates;
  * the pressure plates are transparent, non-query, non-touch and
    non-collidable, and they are the ONLY trigger: stepping on publishes
    ZyntraShopFocus, stepping across switches it, stepping off clears it, and
    standing still writes nothing;
  * EVERY corner of EVERY part is inside the tunnel's envelope -- r <= 33.70
    against the shell, r <= 33.05 for the two slots that cross the rib arch at
    z -52.36..-51.64 -- and nothing reaches into the walk lane;
  * the DAILY REWARDS plaque is the one remaining prompt, and it says what it
    does now that the terminal's Rewards tab is gone;
  * NOTHING on the server touches MarketplaceService -- focus cannot cost money;
  * the card opens on the attribute, states OWNED for an owned pass, routes BUY
    to PlayerScripts.ZyntraShopBuy exactly once, and CLOSE dismisses the current
    focus WITHOUT reopening while the player stands still;
  * ReduceFlashing shrinks the sign's swell instead of strobing it, the boxes
    bob but never turn, and all motion stops in a round;
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

# ── source contracts that the run cannot see ────────────────────────────────
# A purchase prompt anywhere in the server module would mean walking onto a
# plate could cost money. The fake engine refuses MarketplaceService as well,
# but state it here too: this is the rule the owner's brief is built on.
for forbidden in ("PromptProductPurchase", "PromptGamePassPurchase", 'GetService("MarketplaceService")'):
    assert forbidden not in SERVER, f"server module must not reference {forbidden}"
# The card's BUY is a request to ZyntraStore, never its own prompt.
for forbidden in ("PromptProductPurchase", "PromptGamePassPurchase"):
    assert forbidden not in CLIENT, f"client must not call {forbidden} itself"
# #105 removed the Inspect interaction outright. Not "renamed the prompt" --
# the whole idea is gone, including the part names and the plate stencil that
# used to advertise it, so the word must not survive anywhere in either file.
for name, source in (("server", SERVER), ("client", CLIENT)):
    assert "inspect" not in source.lower(), f"{name} still mentions the removed Inspect interaction"
# Nothing turns the boxes any more: the product decal has to keep facing the road.
assert "CFrame.Angles" not in CLIENT, "the client must not rotate the hologram boxes"
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

local function extents(part)
	local size, cf = part.Size, part.CFrame
	local sideways = math.abs(math.cos(cf.Yaw)) < 0.001
	return cf.Position,
		(sideways and size.Z or size.X) * 0.5,
		size.Y * 0.5,
		(sideways and size.X or size.Z) * 0.5
end

-- All EIGHT corners, not the centre and not the bounding sphere: the corner is
-- the thing that pokes through a curved concrete shell.
local function worstRadius(part)
	local pos, hx, hy = extents(part)
	local worst = 0
	for _, sx in ipairs({-1, 1}) do
		for _, sy in ipairs({-1, 1}) do
			for _ = 1, 2 do
				local x, y = pos.X + sx * hx, pos.Y + sy * hy
				local r = math.sqrt(x * x + (y - 1) * (y - 1))
				if r > worst then worst = r end
			end
		end
	end
	return worst
end

local function crossesRib(part)
	local pos, _, _, hz = extents(part)
	return (pos.Z - hz) <= RIB_FAR and (pos.Z + hz) >= RIB_NEAR
end

-- The backdrop and the pilasters are flat wall DRESSING that sits behind the
-- rib line: the arch crosses in front of them at z = -52 and reads as
-- structure. That is the acceptance the 2026-09-15 build made and the module's
-- own header records, and it is the only one -- anything that stands proud of
-- the wall answers to 33.05. The x guard below keeps the exemption from
-- quietly covering a part that is not dressing.
local RIB_DRESSING = {ShopAlcoveBackdrop = true, ShopPilaster = true}

-- ── 1. the build ────────────────────────────────────────────────────────────
local lobby = Instance.new("Model")
lobby.Name = "ServerLobby"
lobby.Parent = workspace
local center = Vector3.new(0, 0, 0)

local model = Shop.Build(lobby, {Center = center})
check(model ~= nil, "Build returned nothing")
check(model.Name == "ZyntraShopDisplay", "wrong model name: " .. tostring(model.Name))
check(model.Parent == lobby, "the shop is not parented to the lobby")
check(model:GetAttribute("ShopDisplayVersion") == 3, "the hologram build must bump the version")
check(near(model:GetAttribute("FrontmostX"), 22.80, 0.0001),
	"FrontmostX disagrees with the kiosk plates: " .. tostring(model:GetAttribute("FrontmostX")))
check(near(model:GetAttribute("CanopyClearanceY"), 7.60, 0.0001), "the canopy ceiling is not published")

local catalogueKeys = {}
for _, source in ipairs({moduleResults.ZyntraConfig.Passes, moduleResults.ZyntraConfig.Products, moduleResults.ZyntraConfig.Items}) do
	for key in pairs(source) do table.insert(catalogueKeys, key) end
end
check(#catalogueKeys == 8, "expected 8 catalogue items, found " .. #catalogueKeys)

local stands = {}
for _, child in ipairs(model:GetChildren()) do
	if child.ClassName == "Model" and not child:GetAttribute("ShopRewardsStand") then
		local key = child:GetAttribute("ShopItemKey")
		check(key ~= nil, "a stand with no item key")
		check(stands[key] == nil, "two stands for " .. tostring(key))
		stands[key] = child
	end
end
for _, key in ipairs(catalogueKeys) do
	check(stands[key] ~= nil, "no hologram for catalogue item " .. key)
end
check(model:GetAttribute("ShopItemCount") == #catalogueKeys, "item count attribute disagrees")

-- ── 2. every stand is a hologram, and the old furniture is gone ─────────────
local RETIRED = {"ShopPedestal", "ShopPedestalCap", "ShopPedestalRing", "ShopItemBox",
	"ShopInspectPlate", "ShopInspectPlateEdge", "ShopInspectPrompt"}
local built = {}
for _, node in ipairs(model:GetDescendants()) do
	built[node.Name] = (built[node.Name] or 0) + 1
end
for _, name in ipairs(RETIRED) do
	check(built[name] == nil, "the retired " .. name .. " is still being built: " .. tostring(built[name]))
end

local boxCount, plateCount, discCount, beamCount = 0, 0, 0, 0
local boxByKey, plateByKey = {}, {}
for key, stand in pairs(stands) do
	local seen, parts = {}, {}
	for _, node in ipairs(stand:GetDescendants()) do
		seen[node.Name] = (seen[node.Name] or 0) + 1
		if node.ClassName == "Part" then parts[node.Name] = node end
	end
	check(seen.ShopHologramBox == 1, key .. ": hologram box count " .. tostring(seen.ShopHologramBox))
	check(seen.ShopProjectorDisc == 1, key .. ": projector disc count " .. tostring(seen.ShopProjectorDisc))
	check(seen.ShopProjectorBeam == 1, key .. ": beam count " .. tostring(seen.ShopProjectorBeam))
	check(seen.ShopPressurePlate == 1, key .. ": plate count " .. tostring(seen.ShopPressurePlate))
	boxCount += 1; plateCount += 1; discCount += 1; beamCount += 1

	local bay = stand:GetAttribute("ShopSupplyBay") == true
	local box, disc, beam, plate =
		parts.ShopHologramBox, parts.ShopProjectorDisc, parts.ShopProjectorBeam, parts.ShopPressurePlate
	boxByKey[key], plateByKey[key] = box, plate

	-- THE BOX. Translucent, the accent's own colour, the product art on the one
	-- face that looks at the road and nothing on the other five.
	check(box.Material == Enum.Material.ForceField, key .. ": the box is not a hologram material")
	check(near(box.Transparency, 0.35), key .. ": box transparency " .. tostring(box.Transparency))
	local edge = bay and 3.20 or 3.00
	check(near(box.Size.X, edge) and near(box.Size.Y, edge) and near(box.Size.Z, edge),
		key .. ": box is not a " .. edge .. " cube")
	check(box:GetAttribute("ShopItemKey") == key, key .. ": the box lost its key")
	check(typeof(box:GetAttribute("ShopBobOrigin")) == "CFrame", key .. ": no ShopBobOrigin for the client")
	check(tostring(box:GetAttribute("ShopTextureSlot")):sub(1, 3) == "Box", key .. ": no texture slot")
	local decals, guis = 0, 0
	for _, node in ipairs(box:GetChildren()) do
		if node.ClassName == "Decal" then
			decals += 1
			check(node.Face == Enum.NormalId.Front, key .. ": art on a face that does not see the road")
			check(node.Transparency == 0, key .. ": the product art inherited the box's transparency")
			check(tostring(node.Texture):match("^rbxassetid://%d+$") ~= nil, key .. ": bad texture url")
		elseif node.ClassName == "SurfaceGui" then
			guis += 1
		end
	end
	-- Every one of the eight keys has uploaded art, so the monogram fallback
	-- must not be what shipped.
	check(decals == 1, key .. ": expected exactly one road-facing decal, got " .. decals)
	check(guis == 0, key .. ": the box fell back to the monogram")
	check(box:FindFirstChildOfClass("SelectionBox") ~= nil, key .. ": the neon edge is gone")
	check(box:FindFirstChildOfClass("PointLight") ~= nil, key .. ": the box light is gone")

	-- THE PROJECTOR. A flat disc under the box, drawn by a CylinderMesh so the
	-- geometry never needs a roll to be measured.
	check(disc.Material == Enum.Material.Neon, key .. ": the disc is not lit")
	check(disc:FindFirstChildOfClass("CylinderMesh") ~= nil, key .. ": the disc is a box")
	check(near(disc.Size.X, 2.60) and near(disc.Size.Z, 2.60), key .. ": disc is not 2.60 across")
	check(near(disc.Size.Y, 0.20), key .. ": disc thickness " .. tostring(disc.Size.Y))
	check(near(disc.Position.X, box.Position.X), key .. ": the disc is not under the box")

	-- THE BEAM. Faint, invisible to every query, and long enough that the box's
	-- highest bob still lands in it.
	check(beam.Material == Enum.Material.Neon, key .. ": the beam is not lit")
	check(near(beam.Transparency, 0.85), key .. ": beam transparency " .. tostring(beam.Transparency))
	check(beam.CanCollide == false and beam.CanTouch == false and beam.CanQuery == false,
		key .. ": the beam is in the way of something")
	check(near(beam.Size.X, 0.50) and near(beam.Size.Z, 0.50), key .. ": beam is not 0.50 square")
	local discTop = disc.Position.Y + 0.10
	local beamBottom = beam.Position.Y - beam.Size.Y * 0.5
	local beamTop = beam.Position.Y + beam.Size.Y * 0.5
	check(near(beamBottom, discTop), key .. ": the beam does not start at the disc")
	check(near(beamTop, box.Position.Y - box.Size.Y * 0.5 + 0.35),
		key .. ": the beam stops short of the box's top bob")

	-- THE PLATE. Invisible by contract, and invisible to everything else too.
	check(near(plate.Transparency, 1), key .. ": the plate is still drawn")
	check(plate.CanQuery == false, key .. ": the plate can still be hit by a query")
	check(plate.CanCollide == false, key .. ": the plate is solid")
	check(plate.CanTouch == false, key .. ": the plate still fires Touched")
	check(plate:GetAttribute("ShopItemKey") == key, key .. ": the plate lost its key")
	check(#plate:GetChildren() == 0, key .. ": the plate still carries a stencil or a hint")
	check(near(plate.Size.X, 3.10) and near(plate.Size.Z, 3.40),
		key .. ": plate zone is " .. plate.Size.X .. " x " .. plate.Size.Z)
	local platePos, plateHalfX = extents(plate)
	local limit = platePos.Z > -44.75 and 22.60 or 25.78
	check(platePos.X - plateHalfX >= limit - 0.0001,
		key .. ": the plate reaches into the walk lane at x " .. (platePos.X - plateHalfX))

	-- The box hangs over its own plate, so walking to the hologram crosses it.
	local boxPos, boxHalfX = extents(box)
	check(boxPos.X + boxHalfX > platePos.X, key .. ": the box is not behind its plate")
	if not bay then
		check(near(plate.Position.X, 27.78), key .. ": frontage plate moved off 27.78")
	else
		check(near(plate.Position.X, 24.50), key .. ": bay plate moved off 24.50")
	end
end
check(boxCount == 8 and plateCount == 8 and discCount == 8 and beamCount == 8,
	"one box, disc, beam and plate per item")

-- ── 3. alternating hover heights on the frontage row ────────────────────────
local row = {}
for key, box in pairs(boxByKey) do
	if stands[key]:GetAttribute("ShopSupplyBay") ~= true then
		table.insert(row, {Z = box.Position.Z, Y = box.Position.Y, Key = key})
	end
end
table.sort(row, function(a, b) return a.Z < b.Z end)
check(#row == 6, "the frontage row is not six holograms: " .. #row)
for index, slot in ipairs(row) do
	local wanted = (index % 2 == 1) and 4.40 or 5.55
	check(near(slot.Y, wanted), slot.Key .. " hovers at " .. slot.Y .. ", expected " .. wanted)
	if index > 1 then
		check(near(slot.Z - row[index - 1].Z, 3.15, 0.0001), "the row pitch drifted at slot " .. index)
		check(math.abs(slot.Y - row[index - 1].Y) > 1.0, "two neighbours hover at the same height")
	end
end
-- 3.00 boxes at a 3.15 pitch clear each other by 0.15 whatever the stagger --
-- which is only true because nothing turns them.
check(near(3.15 - 3.00, 0.15, 0.0001), "the pitch no longer clears a 3.00 box")

-- ── 4. every corner of every part, against the tunnel ───────────────────────
local partCount, worstShell, worstRib, ribParts = 0, 0, 0, 0
for _, node in ipairs(model:GetDescendants()) do
	if node.ClassName == "Part" then
		partCount += 1
		local pos, halfX, halfY = extents(node)
		local r = worstRadius(node)
		if r > worstShell then worstShell = r end
		check(r <= SHELL_LIMIT, node.Name .. " corner r = " .. r .. " is inside the concrete shell")
		if crossesRib(node) then
			if RIB_DRESSING[node.Name] then
				check(pos.X - halfX >= 32.0,
					node.Name .. " claims the wall-dressing exemption at x " .. (pos.X - halfX))
			else
				ribParts += 1
				if r > worstRib then worstRib = r end
				check(r <= RIB_LIMIT, node.Name .. " crosses the rib arch at r = " .. r)
			end
		end
		-- The walk lane, measured at the road-side face rather than the centre.
		local lane = pos.Z > -44.75 and 22.60 or 25.78
		check(pos.X - halfX >= lane - 0.0001,
			node.Name .. " reaches to x " .. (pos.X - halfX) .. ", past the " .. lane .. " lane limit")
		check(pos.Y - halfY >= 0.55, node.Name .. " is under the ledge at y " .. (pos.Y - halfY))
		check(pos.Y + halfY <= 16, node.Name .. " is over the tunnel at y " .. (pos.Y + halfY))
		-- Only the rewards plinth is solid: the shop is walk-through so nothing
		-- on it can block the lobby's own traffic.
		check(node.CanCollide == (node.Name == "ShopRewardsPlinth"),
			node.Name .. " has the wrong collision")
	end
end
check(partCount >= 50, "the shop got suspiciously small: " .. partCount .. " parts")
check(ribParts >= 6, "nothing measured against the rib arch, which cannot be right")
check(worstShell <= SHELL_LIMIT and worstRib <= RIB_LIMIT, "envelope summary disagrees with itself")

-- The frontage boxes stay under the canopy's own line at the top of a bob. The
-- fascia is only 0.44 deep and the boxes stand behind it, so this is a
-- SIGHTLINE and not a collision: a box top over 7.66 has its front corner cut
-- off by the fascia for a player still on the far lane of the road. 8.90 is
-- where it would actually hit something, and the row keeps 1.50 studs of that.
for _, slot in ipairs(row) do
	check(slot.Y + 1.50 + 0.35 <= 7.60, slot.Key .. " tops out over the canopy line")
	check(slot.Y + 1.50 + 0.35 <= 8.90 - 1.0, slot.Key .. " lost its headroom under the soffit")
end

-- ── 5. the one prompt that is left ──────────────────────────────────────────
local prompts = {}
for _, node in ipairs(model:GetDescendants()) do
	if node.ClassName == "ProximityPrompt" then table.insert(prompts, node) end
end
check(#prompts == 1, "the frontage has " .. #prompts .. " prompts, expected only DAILY REWARDS")
local rewards = prompts[1]
check(rewards.Name == "ZyntraShopPrompt", "the rewards prompt lost the name ZyntraStore binds")
check(rewards:GetAttribute("ShopRewardsPrompt") == true, "the rewards prompt lost its flag")
check(rewards.ActionText == "DAILY REWARDS", "rewards action text: " .. tostring(rewards.ActionText))
check(rewards.ObjectText == "Daily Rewards", "rewards object text: " .. tostring(rewards.ObjectText))
check(rewards.KeyboardKeyCode ~= nil and rewards.GamepadKeyCode ~= nil, "rewards prompt binding")

-- The plaque no longer sends anyone to a terminal tab that is being removed.
local plaqueWords = {}
for _, node in ipairs(model:GetDescendants()) do
	if node.ClassName == "TextLabel" then
		plaqueWords[node.Name] = node.Text
		check(node.Text ~= "ZYNTRA TERMINAL", "the plaque still points at the terminal")
		check(node.Text:upper():find("INSPECT") == nil, "world text still says INSPECT")
	end
end
check(plaqueWords.RewardsTitle == "DAILY" and plaqueWords.RewardsTitle2 == "REWARDS",
	"the plaque title changed")
check(plaqueWords.RewardsLine == "PLAY TO EARN", "plaque line: " .. tostring(plaqueWords.RewardsLine))
check(plaqueWords.RewardsFoot == "PRESS E TO OPEN", "plaque foot: " .. tostring(plaqueWords.RewardsFoot))

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
standAt(samplePlate.X - 1.60, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") == sample, "the road-side edge of the zone is dead")
standAt(samplePlate.X + 1.60, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") == sample, "the wall-side edge of the zone is dead")

-- Hysteresis: past the plate's edge still counts while already inside.
standAt(samplePlate.X, samplePlate.Z + 2.0)
step()
check(player:GetAttribute("ZyntraShopFocus") == sample, "hysteresis dropped focus at the edge")

-- SWITCHING. Stepping fully into the neighbour's zone hands the card over, and
-- the held zone's hysteresis does not out-vote it once the player has left.
local neighbour, neighbourPlate = nil, nil
for key, position in pairs(plates) do
	if key ~= sample and math.abs(position.Z - samplePlate.Z) < 3.2
		and math.abs(position.X - samplePlate.X) < 0.1 then
		neighbour, neighbourPlate = key, position
	end
end
check(neighbour ~= nil, "the row has no neighbouring slot to switch to")
standAt(neighbourPlate.X, neighbourPlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") == neighbour,
	"stepping to the next hologram did not switch: " .. tostring(player:GetAttribute("ZyntraShopFocus")))
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
local buy = card:FindFirstChild("Buy")
local closeButton = card:FindFirstChild("Close")
local title = card:FindFirstChild("ItemName")
local state = card:FindFirstChild("ItemState")
local hint = card:FindFirstChild("CloseHint")
check(buy and closeButton and title and state and hint, "the card is missing its parts")

player:SetAttribute("ZyntraShopFocus", nil)
check(gui.Enabled == false, "the card is open with no focus")

player:SetAttribute("ZyntraShopFocus", "Tokens4")
check(gui.Enabled == true, "the card did not open on focus")
check(title.Text == moduleResults.ZyntraConfig.Products.Tokens4.Name, "wrong name: " .. tostring(title.Text))
check(buy.Text == "49 R$", "the card did not state the configured price: " .. tostring(buy.Text))
step()  -- the live price fetch answers
check(buy.Text == "77 R$", "the card ignored the live price: " .. tostring(buy.Text))

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
		Kind = card:FindFirstChild("ItemKind").TextSize,
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
check(phone.Height == 200, "the phone card is no longer 300x200: " .. phone.Height)
check(phone.Buy >= 44 and tablet.Buy >= 44, "a touch tier drew a tap target under 44")
check(phone.Close >= 44 and tablet.Close >= 44, "a touch tier drew CLOSE under 44")
check(pointer.Buy >= 32, "the pointer tier drew a tap target under 32")
check(phone.Desc >= 11 and tablet.Desc >= 11 and pointer.Desc >= 11, "type under 11px")
check(phone.Kind >= 11 and phone.HintSize >= 11, "the hint row is under 11px")
-- Every tier fits the screen it was measured on, and clears the touch cluster.
check(phone.Width <= 956 and phone.Top + phone.Height <= 382 - 140,
	"the phone card overlaps the movement cluster")
check(pointer.Height <= 684 and pointer.Width <= 1280, "the pointer card does not fit")

-- The copy line says how to get rid of the card, and says the true thing for
-- the input the player has. No tier mentions an interaction that was removed.
check(phone.Hint == "Step off the plate to close", "phone hint: " .. phone.Hint)
check(tablet.Hint == "Step off the plate to close", "tablet hint: " .. tablet.Hint)
check(pointer.Hint == "Step off the plate or press CLOSE", "pointer hint: " .. pointer.Hint)
for _, tier in ipairs({phone, tablet, pointer}) do
	check(tier.Hint:upper():find("INSPECT") == nil, "the card still says INSPECT")
	check(tier.HintWidth >= 120, "the hint lane collapsed to " .. tier.HintWidth)
end

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

-- ── 11. motion ──────────────────────────────────────────────────────────────
local boxes, glow = {}, nil
for _, node in ipairs(model:GetDescendants()) do
	if node.Name == "ShopHologramBox" then table.insert(boxes, node) end
	if node.Name == "ShopSignGlowPanel" then glow = node end
end
check(#boxes == 8 and glow ~= nil, "the client has nothing to animate")
local restingY = boxes[1].Position.Y
local restingGlow = glow.Transparency
local restingYaw = boxes[1].CFrame.Yaw

local function sampleMotion(seconds)
	local lowest, highest = math.huge, -math.huge
	local movedY, turned, highestY = false, false, -math.huge
	for _ = 1, seconds * 30 do
		heartbeat:Fire(1 / 30)
		lowest = math.min(lowest, glow.Transparency)
		highest = math.max(highest, glow.Transparency)
		local offset = boxes[1].Position.Y - restingY
		if math.abs(offset) > 0.05 then movedY = true end
		highestY = math.max(highestY, math.abs(offset))
		if not near(boxes[1].CFrame.Yaw, restingYaw, 1e-9) then turned = true end
	end
	return highest - lowest, movedY, turned, highestY
end

local swing, bobbed, turned, reach = sampleMotion(7)
check(bobbed, "the holograms never bobbed")
check(swing > 0.15, "the sign never breathed: " .. swing)
-- The server sized every beam to a 0.35 bob and every corner to a 0.35 bob.
check(reach <= 0.3501, "the bob went past the 0.35 the geometry was solved for: " .. reach)
-- And nothing turns: the product decal faces the road at every frame.
check(not turned, "a hologram box turned away from the road")

player:SetAttribute("ReduceFlashing", true)
local reducedSwing, stillBobbed = sampleMotion(7)
check(stillBobbed, "ReduceFlashing stopped the holograms as well")
check(reducedSwing < swing * 0.6, "ReduceFlashing did not calm the sign: "
	.. reducedSwing .. " vs " .. swing)
check(reducedSwing <= 0.11, "ReduceFlashing left a visible pulse: " .. reducedSwing)
player:SetAttribute("ReduceFlashing", nil)

-- A round stops everything and puts every pose back.
workspace:SetAttribute("RoundActive", true)
heartbeat:Fire(1 / 30)
check(near(boxes[1].Position.Y, restingY, 0.0001), "a hologram was left bobbing in a round")
check(near(glow.Transparency, restingGlow, 0.0001), "the sign was left mid-pulse in a round")
local frozen = boxes[1].Position.Y
heartbeat:Fire(1 / 30)
check(near(boxes[1].Position.Y, frozen, 0.0001), "the holograms kept moving in a round")
workspace:SetAttribute("RoundActive", nil)

-- Token items reuse the same bridge and never ask Roblox for a Robux price.
local beforeTokenPriceCalls = marketplaceCalls
for _, key in ipairs({"SpeedPotion", "RouteMarker"}) do
	player:SetAttribute("ZyntraShopFocus", key)
	check(gui.Enabled, key .. " physical card did not open")
	check(buy.Text == tostring(moduleResults.ZyntraConfig.Items[key].TokenCost) .. " TOKENS  //  BUY", key .. " wrong currency")
	local beforeBuy = #fired
	buy.Activated:Fire()
	check(#fired == beforeBuy + 1 and fired[#fired] == key, key .. " bridge did not route")
end
check(marketplaceCalls == beforeTokenPriceCalls, "token supplies called MarketplaceService")
player:SetAttribute("ZyntraRouteMarkers", 6)
check(state.Text == "6 STORED", "physical stock did not refresh")

-- ── 12. the shop going away takes the focus with it ─────────────────────────
standAt(samplePlate.X, samplePlate.Z)
step()
check(player:GetAttribute("ZyntraShopFocus") ~= nil, "focus did not return before teardown")
model:Destroy()
step(2)
check(player:GetAttribute("ZyntraShopFocus") == nil, "a destroyed shop left a card open")

print(string.format(
	"ok  %d checks: 8 holograms on %d parts, worst corner r %.3f (shell) / %.3f (rib), tiers %d/%d/%d px",
	checks, partCount, worstShell, worstRib, phone.Width, tablet.Width, pointer.Width))
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
