"""ZyntraStore's lobby rail: the five square HUD buttons, MUSIC's switch, and
the routing that sends every shop entry -- RECORDS and SETTINGS included -- to
the L4 shop.

RECORDS_SETTINGS_L4_20261007 deleted the RECORDS / SETTINGS terminal (owner: the
old UI is replaced and deleted). Both are pages of "Zyntra Shop L4" now, proven by
its harness (artifacts/shop-ui-figma-20261005/roblox-draft/tests). The sections
that only measured the terminal -- its clamped design size (4) and its mounted-
page tab set (6) -- were REWRITTEN to the new rule: the terminal is gone and
nothing builds it.

SHOP_UI_L4_GO_LIVE_20261007 deleted the terminal's Upgrades, Shop, Skins, Donate
and Colors pages and its DEV tab (the L4 shop "Zyntra Shop L4" and the L4 dev menu
"Zyntra Dev L4" replace them). The sections that only measured those pages -- the
upgrade/shop card tiers, FIELD SUPPLIES and the Shop list+detail hook -- were
deleted with them; the L4 harness covers the new pages. What is left has to stay
true and none of it is visible from a screenshot:

  * the terminal is gone: no shell, no tabs, no pages, no layout, no probe
    action but `kiosk`, and nothing mounts ZyntraRecordsPage,
  * the rail is five buttons in one drawn order, built by one loop over one list,
  * layoutSquareSections fits them at 64 / 56 / 52px and then in two columns
    rather than clipping one off the bottom, and dodges the thumbstick glyph
    against the rail's WHOLE footprint,
  * REWARDS and WHEEL fire PlayerScripts.OpenDailyRewards / OpenLuckyWheel and
    refuse in a round, under a queue and under any screen-owning modal that is
    not a rail window, and every "Rewards" caller reaches the modal,
  * RAIL_OVER_WINDOWS_20261007: the rail stays up (DisplayOrder 119) over its own
    windows -- L4 shop, L4 dev menu, Daily Rewards, Lucky Wheel -- and a rail
    press closes the OTHER open window through its synchronous bridge before
    opening its own; the open window's own button closes nothing, a window that
    cannot be closed is never stacked on, and re-entry, the queue and rounds
    still hide the rail; layoutSquareSections returns the rail's right edge
    (ZyntraRailRight) and the rail out-ranks every window it switches between,
  * SHOPS, UPGRADES and every shop name -- RECORDS and SETTINGS included -- ask
    the L4 bridge and nothing else, and its refusal is final; J and the in-round
    DEV chip ask the L4 dev menu,
  * MUSIC is the lobby-music switch: SetAccessibility {LobbyMusicEnabled}, drawn
    at once, confirmed by the attribute, put back after 12 s without one, and
    stood down until the attribute is published, in a round and while hidden;
    it toggles over the rail's own windows; it sends through the REAL
    ShopData.toggleSetting, the L4 SETTINGS row's send, so a press on either
    surface inside the server's 1 s window is held, never sent to be dropped,
  * the lobby SHOP wall's BUY (PlayerScripts.ZyntraShopBuy) prompts the
    configured pass / product id, sends a token item through the REAL ShopData
    dispatcher (one BuyItem per write, never two), and ignores unknown keys,
  * the L4 graft on the rail follows the in-round DEV chip: hidden on the chip,
    shown in the lobby, and the legacy art never comes back under it.

Everything below section 4 RUNS the production Lua under the real luau
interpreter against honest fakes, which is what catches a typo as well as a
contract.

Run:  LUAU_BIN=.../luau.exe python tools/tests/test_zyntra_store_compact.py
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC_PATH = ROOT / "StarterPlayer" / "StarterPlayerScripts" / "ZyntraStore.LocalScript.lua"
SRC = SRC_PATH.read_text(encoding="utf-8")
UIDEVICE = (ROOT / "ReplicatedStorage" / "UIDevice.ModuleScript.lua").read_text(encoding="utf-8")
SHOPDATA = (ROOT / "ReplicatedStorage" / "ZyntraShopUI" / "ShopData.ModuleScript.lua").read_text(encoding="utf-8")

CHECKS = 0


def check(condition, message):
    global CHECKS
    CHECKS += 1
    assert condition, message


def section(start: str, stop: str) -> str:
    """The production Lua between two literal markers, start inclusive."""
    begin = SRC.index(start)
    return SRC[begin:SRC.index(stop, begin)]


# ── 4. THE TERMINAL IS GONE (RECORDS_SETTINGS_L4_20261007) ───────────────────────
# REWRITTEN from "the panel is 1180x760 and clamped to the viewport": the owner
# replaced RECORDS and SETTINGS with L4 pages and ordered the old UI deleted.
for gone in ('main.Name = "Terminal"', "STORE_DESIGN_WIDTH", "applyTerminalLayout", "setMainVisible",
             "TERMINAL_PAGE_MODULES", "ZyntraRecordsPage", "local function selectTab", "tabButtons",
             "TerminalHeader", "CloseTerminal", "TerminalStatus", "ZyntraCloseTerminal",
             "ZyntraTerminalAction", "pageMounts", "layoutHooks", "openTerminal("):
    check(gone not in SRC, f"the deleted terminal is still in ZyntraStore: {gone!r}")
check('if action == "kiosk" then return openKioskShop() end\n\t\treturn false' in SRC,
      "the Studio probe keeps only `kiosk`; every other action answers false")
check(re.search(r"^local function showStatus\(message\)", SRC, re.M) is not None,
      "showStatus stays (the re-entry modal calls it) as a warn stand-in")
check('local function refreshUI()\n\tupdateReentry()\nend' in SRC,
      "refreshUI is only the re-entry refresh now (the re-entry tests slice up to it)")

# ── 5. THE SQUARE HUD BUTTON (#88 correction) ──────────────────────────────
check("SHOP_ICON_CIRCLE" not in SRC, "the circular shop-button block is gone")
check("UDim.new(1, 0)" not in SRC, "no disc corner radius survives anywhere in the store")
check("TweenService" not in SRC, "the breathing ring's tween is gone with it")
check("shopButtonSections.Size" not in SRC, "the 8px disc inset is gone")
rail = section("for _, entry in ipairs(railButtons) do",
               "-- C5_ZYNTRA_OPEN_BUTTON_20260829")

# ── 5a. THE RAIL IS ENUMERATED ONCE (cards #103/#104) ──────────────────────
# Seven places used to each name three buttons. Two more buttons arrived on
# 2026-09-16, and a place that kept its literal would have silently left them
# out of that one rule -- the exact shape of the Level 1 FindFirstChild bug this
# project already paid for. The list is built once and every loop reads it.
check(re.search(r"^local railButtons = \{shopButton, openButton, rewardsButton,"
                r" wheelButton, musicButton\}$", SRC, re.M) is not None,
      "the rail is one named list, in drawn order, built once")
check(SRC.count("ipairs({openButton, shopButton, musicButton})") == 0,
      "no three-button literal survives anywhere in the store")
# Five since 2026-10-07: the L4 graft's visibility and its late-arrival hook
# joined the attribute, border and stroke loops.
check(SRC.count("ipairs(railButtons)") == 5,
      f"all five rail loops read that list, found {SRC.count('ipairs(railButtons)')}")
check(re.search(r"ButtonSections\.Visible = ", SRC) is None,
      "no per-button SectionButtonContent line bypasses the graft rule")
check('if child.Name == "L4Skin_Face" then updateVisibility() end' in SRC,
      "a graft that lands after the round began re-runs updateVisibility")
for name in ("ZyntraShopButton", "ZyntraOpenButton", "ZyntraRewardsButton",
             "ZyntraWheelButton", "ZyntraMusicButton"):
    check(SRC.count(f'.Name = "{name}"') == 1, f"{name} is named exactly once")
# Order in the SOURCE is the order on the SCREEN: layoutSquareSections takes its
# five arguments in drawn order, so there is no second literal to disagree with.
check("local function layoutSquareSections(layout, shopButton, openButton,"
      " rewardsButton, wheelButton, musicButton)" in SRC,
      "layoutSquareSections takes the rail in drawn order")
check("layoutSquareSections(layout, shopButton, openButton, rewardsButton,"
      " wheelButton, musicButton)" in SRC, "and is called with it in that order")

# The shop pages are gone: nothing in the store may still build them.
for gone in ('local function makeUpgradeCard', 'local function makeProductCard',
             'local function makeDonationCard', 'local function makeColorPicker',
             'FIELD SUPPLIES', 'Prices are read live from Roblox', 'ZyntraSkinsPage',
             'selectTab("Dev")', 'ShopUIVersion', 'ZyntraShopPrompt'):
    check(gone not in SRC, f"the deleted legacy UI is still in ZyntraStore: {gone!r}")
check("if entry == shopButton" not in rail, "nothing in the rail singles out one button")
check(rail.count("SquareSectionBorder") == 1, "one hover border, built once for all five")

# ── 5c. THE TWO NEW ICONS, and the caption table that replaced the ternary ──
# The captions used to be `Shop and "Shops" or (Music and "Music" or "Upgrades")`,
# whose final `or` is a DEFAULT: the first kind that was neither would have
# captioned itself "Upgrades". Adding a fourth and a fifth kind is precisely the
# case that breaks, so the expression is a table now.
check('Rewards = "rbxassetid://85423575361057"' in SRC, "the Daily Rewards icon is the handed-over asset")
check('Wheel = "rbxassetid://111918608092047"' in SRC, "and so is the Lucky Wheel icon")
captions = re.search(r"local SECTION_CAPTIONS = \{(.*?)\}", SRC, re.S)
check(captions is not None, "the captions are a table rather than a nested ternary")
CAPTIONS = dict(re.findall(r'(\w+) = "([^"]+)"', captions.group(1)))
check(CAPTIONS == {"Upgrades": "Upgrades", "Shop": "Shops", "Music": "Music",
                   "Rewards": "Rewards", "Wheel": "Wheel"}, CAPTIONS)
check('kinds[1] == "Shop" and "Shops"' not in SRC, "the defaulting ternary is gone")
images = re.search(r"local SECTION_IMAGES = \{(.*?)\}", SRC, re.S)
IMAGES = dict(re.findall(r'(\w+) = "([^"]+)"', images.group(1)))
check(set(IMAGES) == set(CAPTIONS), f"every section kind has both an icon and a caption: {IMAGES}")

# ── 5d. THE RAIL OUT-RANKS ITS OWN WINDOWS (RAIL_OVER_WINDOWS_20261007) ─────
# While one of its windows is open the rail gui rises so a tap reaches it before
# that window's full-screen Active shield, and stays under re-entry. The window
# orders are read from the four scripts that own them, not restated here.
SPS = ROOT / "StarterPlayer" / "StarterPlayerScripts"


def display_order(source: str, pattern: str, owner: str) -> int:
    found = re.findall(pattern, source, re.M)
    check(len(found) == 1, f"{owner} sets its gui's DisplayOrder exactly once: {found}")
    return int(found[0])


raised = re.search(r"^\tgui\.DisplayOrder = if railAvailable and UIDevice\.ScreenOwningModalOpen\(\)"
                   r" then (\d+) else (\d+)$", SRC, re.M)
check(raised is not None, "updateVisibility raises the rail gui only while a rail window is open")
RAISED, RESTING = int(raised.group(1)), int(raised.group(2))
check(RESTING == display_order(SRC, r"^gui\.DisplayOrder = (\d+)$", "ZyntraStore"),
      "and drops it back to the order the gui is built with")
WINDOW_ORDERS = {
    owner: display_order((SPS / f"{owner}.LocalScript.lua").read_text(encoding="utf-8"), pattern, owner)
    for owner, pattern in (("Zyntra Shop L4", r"^ui\.gui\.DisplayOrder = (\d+)"),
                           ("Zyntra Dev L4", r"^ui\.gui\.DisplayOrder = (\d+)"),
                           ("Zyntra Daily L4", r"^ui\.gui\.DisplayOrder = (\d+)"),
                           ("Lucky Wheel Client", r"^gui\.DisplayOrder = (\d+)"))
}
for owner, order in WINDOW_ORDERS.items():
    check(RAISED > order, f"the raised rail ({RAISED}) draws over {owner} ({order})")
REENTRY = display_order(SRC, r"^reentryGui\.DisplayOrder = (\d+)$", "the re-entry modal")
check(RAISED < REENTRY, f"the raised rail ({RAISED}) stays under re-entry ({REENTRY})")
# The lobby token pill and the Friend Boost chip rise to the rail's own order over
# the same windows (owner, 2026-10-08), so both draw over every window's shield
# and under re-entry, exactly as the rail does.
for owner, pattern in (("Zyntra Shop L4", r"^\t\tpillGui\.DisplayOrder = if visible and over then (\d+) else 55$"),
                       ("Friend Boost Client", r"^\tgui\.DisplayOrder = if shown and over then (\d+) else 60$")):
    over = display_order((SPS / f"{owner}.LocalScript.lua").read_text(encoding="utf-8"), pattern, owner)
    check(over == RAISED, f"{owner} rises to the raised rail's order over a window: {over} vs {RAISED}")
# The right edge goes out under the one name the three fitted windows re-fit
# on, and is cleared in a round, where there is no rail to keep clear of.
published = re.findall(r'player:SetAttribute\("(\w+)", if inRound then nil\n\t\telse layoutSquareSections\('
                       r'layout, shopButton, openButton, rewardsButton, wheelButton, musicButton\)\)', SRC)
check(published == ["ZyntraRailRight"] and SRC.count('SetAttribute("ZyntraRailRight"') == 1,
      f"updateVisibility publishes ZyntraRailRight once, nil in a round: {published}")
for owner in ("Zyntra Shop L4", "Zyntra Dev L4", "Zyntra Daily L4"):
    window = (SPS / f"{owner}.LocalScript.lua").read_text(encoding="utf-8")
    check('GetAttributeChangedSignal("ZyntraRailRight")' in window,
          f"{owner} re-fits on the ZyntraRailRight the rail publishes")


# ── 6..9 RUN THE PRODUCTION LUA ────────────────────────────────────────────

FAKES = r"""
local checks = 0
local function expect(actual, expected, message)
	checks += 1
	assert(actual == expected, message .. ': expected ' .. tostring(expected)
		.. ', got ' .. tostring(actual))
end
local function ok(condition, message)
	checks += 1
	assert(condition, message)
end
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function() end}
		end,
		Fire = function(_, ...)
			for _, callback in ipairs(callbacks) do callback(...) end
		end,
	}
end
local objects = {}
local function object(class)
	local obj = {ClassName = class, Activated = signal(), Visible = true,
		Active = true, Selectable = true, Children = {}}
	table.insert(objects, obj)
	return obj
end
local Instance = {new = object}
local UDim = {new = function(scale, offset) return {Scale = scale, Offset = offset} end}
-- The engine's UDim2 exposes .X/.Y as UDims; the source reads both forms, so
-- the fake carries both rather than the flat one it is convenient to assert on.
local function udim2(sx, ox, sy, oy)
	return {SX = sx, OX = ox, SY = sy, OY = oy,
		X = {Scale = sx, Offset = ox}, Y = {Scale = sy, Offset = oy}}
end
-- RAIL_DOTS_20260922: the notification dots anchor with Vector2.
local Vector2 = {new = function(x, y) return {X = x, Y = y} end}
local UDim2 = {
	new = udim2,
	fromOffset = function(x, y) return udim2(0, x, 0, y) end,
	fromScale = function(x, y) return udim2(x, 0, y, 0) end,
}
local Color3 = {fromRGB = function(r, g, b) return ('rgb%d,%d,%d'):format(r, g, b) end,
	fromHSV = function() return 'hsv' end}
local Enum = {
	AutomaticSize = {Y = 'Y', X = 'X'},
	SortOrder = {LayoutOrder = 'LayoutOrder', Name = 'Name'},
	Font = {GothamMedium = 'GothamMedium', GothamBold = 'GothamBold',
		GothamBlack = 'GothamBlack', Code = 'Code'},
	TextXAlignment = {Left = 'Left', Center = 'Center', Right = 'Right'},
	TextYAlignment = {Top = 'Top', Center = 'Center'},
	ScaleType = {Fit = 'Fit', Crop = 'Crop'},
	ApplyStrokeMode = {Border = 'Border'},
	FillDirection = {Horizontal = 'Horizontal'},
	VerticalAlignment = {Center = 'Center'},
}
local COLORS = {bg = 'bg', panel = 'panel', card = 'card', card2 = 'card2', line = 'line',
	text = 'text', muted = 'muted', accent = 'accent', accent2 = 'accent2', error = 'error'}
-- GetTextSize is a real engine call; these two stand in for it with a linear
-- model. Nothing asserted below depends on the model being the engine's -- only
-- on the SOURCE feeding it the face and width it says it does.
local function textWidthFor(text, face, _font)
	return math.floor(#tostring(text) * face * 0.55)
end
local function textHeightFor(text, face, _font, width)
	local lines = math.max(1, math.ceil(textWidthFor(text, face) / math.max(1, width)))
	return math.floor(lines * face * 1.3)
end
local UIDevice = {}
function UIDevice.SetEnabled(element, enabled)
	element.Active = enabled
	element.Selectable = enabled
end
local delayed = {}
local task = {
	spawn = function(fn, ...) fn(...) end,
	delay = function(seconds, fn) table.insert(delayed, {Seconds = seconds, Fn = fn}) end,
}
"""

RAIL_TESTS = r"""
-- ---- THE RAIL IS FIVE BUTTONS, in the drawn order ------------------------
expect(#railButtons, 5, 'the rail is five buttons')
local NAMES = {'ZyntraShopButton', 'ZyntraOpenButton', 'ZyntraRewardsButton',
	'ZyntraWheelButton', 'ZyntraMusicButton'}
for index, entry in ipairs(railButtons) do
	expect(entry.Name, NAMES[index], 'rail slot ' .. index .. ' is ' .. NAMES[index])
end
expect(rewardsButton.Name, 'ZyntraRewardsButton', 'the rewards button carries the contract name')
expect(wheelButton.Name, 'ZyntraWheelButton', 'and so does the wheel button')

-- ---- the two new buttons are built EXACTLY like the other three ----------
local CAPTIONS = {ZyntraShopButton = 'Shops', ZyntraOpenButton = 'Upgrades',
	ZyntraRewardsButton = 'Rewards', ZyntraWheelButton = 'Wheel',
	ZyntraMusicButton = 'Music'}
local ICONS = {ZyntraShopButton = 'rbxassetid://132462891522145',
	ZyntraOpenButton = 'rbxassetid://119432640057145',
	ZyntraRewardsButton = 'rbxassetid://85423575361057',
	ZyntraWheelButton = 'rbxassetid://111918608092047',
	ZyntraMusicButton = 'rbxassetid://102262986416811'}
for _, entry in ipairs(railButtons) do
	expect(entry.BackgroundColor3, COLORS.bg, entry.Name .. ' wears the rail background')
	expect(entry.TextColor3, COLORS.accent, entry.Name .. ' wears the accent')
	expect(entry.Size.OX, 64, entry.Name .. ' is authored 64 wide')
	expect(entry.Size.OY, 64, entry.Name .. ' is authored 64 tall -- SQUARE')
	local content = entry:FindFirstChild('SectionButtonContent')
	ok(content ~= nil, entry.Name .. ' has its inset content frame')
	local caption, icon
	for _, child in ipairs(content.Children) do
		if child.Name == 'SectionCaption' then caption = child end
		if child.ClassName == 'ImageLabel' then icon = child end
	end
	expect(caption.Text, CAPTIONS[entry.Name], entry.Name .. ' says what it opens')
	expect(icon.Image, ICONS[entry.Name], entry.Name .. ' carries its own art')
	expect(icon.ScaleType, 'Fit', entry.Name .. ' keeps the aspect ratio of a 1254^2 PNG')
	expect(icon.Size.OY, -16, entry.Name .. ' leaves its caption row uncovered')
	expect(entry.TextTransparency, 1, entry.Name .. " hides button()'s own text under the icon")
end
-- The rail's ACTIVE state is authored, not incidental: MUSIC ships out of the
-- input stack (it is a readout until the profile lands) and the other four ship
-- in it. Getting this backwards for the two new buttons would mean a rail button
-- that never responds, which no screenshot shows.
expect(musicButton.Active, false, 'MUSIC ships inactive, as it always has')
expect(rewardsButton.Active, true, 'REWARDS ships pressable')
expect(wheelButton.Active, true, 'WHEEL ships pressable')

local corners = {}
for _, entry in ipairs(railButtons) do
	local radius, content, caption
	for _, child in ipairs(entry.Children) do
		if child.ClassName == 'UICorner' then radius = child.CornerRadius end
		if child.Name == 'SectionButtonContent' then content = child end
	end
	ok(radius ~= nil, 'every rail button has a corner')
	table.insert(corners, radius.Scale .. ':' .. radius.Offset)
	ok(content ~= nil, 'every rail button has its inset content frame')
	expect(content.Position.OX, 3, 'the content inset is 3px on x')
	expect(content.Position.OY, 3, 'the content inset is 3px on y')
	expect(content.Size.OX, -6, 'and the frame gives back both insets on x')
	expect(content.Size.OY, -6, 'and on y')
	expect(entry:GetAttribute('SquareSectionButton'), true, 'all five are square-section buttons')
	for _, child in ipairs(entry.Children) do
		if child.ClassName == 'UIStroke' and child.Name == 'SquareSectionBorder' then
			caption = child
			expect(child.Transparency, 0.22, 'the hover border rests at the same transparency')
		end
	end
	ok(caption ~= nil, 'and all five carry the same named hover border')
end
for index = 2, #corners do
	expect(corners[index], corners[1], 'rail slot ' .. index .. ' has its neighbours corner')
end
expect(corners[1], '0:7', 'which is the square 7px corner button() draws')
-- The hover is the only thing that writes the border, and it behaves the same
-- on all five: the card-88 ring wrote the shop button's stroke from a tween
-- as well, so "one writer per property" is the thing worth proving.
local function borderOf(entry)
	for _, child in ipairs(entry.Children) do
		if child.Name == 'SquareSectionBorder' then return child end
	end
	return nil
end
for _, entry in ipairs(railButtons) do
	local border = borderOf(entry)
	-- MUSIC ships Active = false (it is a readout, not a control), so it is
	-- lifted here: the point is that the HOVER RULE is one rule for all five,
	-- not that all five are pressable.
	local was = entry.Active
	entry.Active = true
	entry.MouseEnter:Fire()
	expect(border.Transparency, 0, 'hover opens the border')
	entry.MouseLeave:Fire()
	expect(border.Transparency, 0.22, 'and leaving closes it back to the resting value')
	entry.Active = was
end
-- An inactive control must not light up under the pointer.
local music = borderOf(musicButton)
expect(musicButton.Active, false, 'the music readout ships out of the input stack')
musicButton.MouseEnter:Fire()
expect(music.Transparency, 0.22, 'an inactive rail button does not respond to hover')
print('rail|' .. checks)
"""

# ── 10. THE FIT LADDER, running the real layoutSquareSections ───────────────
# 5 x 64 + 4 x 8 is 352px of rail. A landscape phone's safe area is nowhere near
# that, so the function grew a ladder -- full side, the 52px floor, then TWO
# COLUMNS -- and a ladder is arithmetic that a screenshot cannot check.
LAYOUT_TESTS = r"""
local function run(safe, isTouch, glyph)
	setGlyph(glyph)
	local railRight = layoutSquareSections({Safe = safe, IsTouch = isTouch},
		shopButton, openButton, rewardsButton, wheelButton, musicButton)
	-- RAIL_OVER_WINDOWS_20261007: the return is ZyntraRailRight, kept beside the
	-- array part so #placed and ipairs still see exactly the five buttons.
	local placed = {RailRight = railRight}
	for index, entry in ipairs(railButtons) do
		placed[index] = {Name = entry.Name,
			Left = entry.Position.OX, Top = entry.Position.OY,
			Right = entry.Position.OX + entry.Size.OX,
			Bottom = entry.Position.OY + entry.Size.OY,
			Side = entry.Size.OX,
			Caption = entry:FindFirstChild('SectionButtonContent')
				:FindFirstChild('SectionCaption').TextSize}
	end
	return placed
end
local function rectOf(placed)
	local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
	for _, slot in ipairs(placed) do
		left = math.min(left, slot.Left)
		top = math.min(top, slot.Top)
		right = math.max(right, slot.Right)
		bottom = math.max(bottom, slot.Bottom)
	end
	return {Left = left, Top = top, Right = right, Bottom = bottom}
end
local function overlaps(a, b)
	return a.Left < b.Right and a.Right > b.Left and a.Top < b.Bottom and a.Bottom > b.Top
end

-- ---- DESKTOP: the authored rail, one column of five 64px squares ---------
local desk = run({Left = 0, Top = 0, Right = 1920, Bottom = 1080}, false)
expect(#desk, 5, 'five buttons are placed')
for index, slot in ipairs(desk) do
	expect(slot.Side, 64, slot.Name .. ' keeps the authored 64px side on a desktop')
	expect(slot.Left, 8, slot.Name .. ' sits in one column at the safe left + 8')
	expect(slot.Caption, 12, slot.Name .. ' captions at 12px while the square is 64')
	if index > 1 then
		expect(slot.Top, desk[index - 1].Bottom + 8, slot.Name .. ' follows the one above it')
	end
end
expect(desk[1].Top, 364, 'the column is centred in the safe area: (1080 - 352) / 2')
expect(desk[5].Bottom, 716, 'and ends 364px above the bottom, symmetrically')
expect(desk[1].Name, 'ZyntraShopButton', 'SHOPS is the top of the rail')
expect(desk[5].Name, 'ZyntraMusicButton', 'MUSIC is the bottom of it')

-- ---- TABLET: 56px squares, still one column ------------------------------
local tab = run({Left = 0, Top = 0, Right = 1024, Bottom = 768}, true)
for _, slot in ipairs(tab) do
	expect(slot.Side, 56, 'a tablet gets the 56px touch square')
	expect(slot.Caption, 11, 'and an 11px caption')
end
expect(tab[1].Top, 232, 'centred: (768 - 304) / 2')
expect(tab[2].Top, tab[1].Bottom + 6, 'with the 6px touch gap')

-- ---- RUNG 2: the 52px floor, one column ---------------------------------
-- 284px of safe height is exactly 5 x 52 + 4 x 6, so this is the last row that
-- does NOT split. One pixel less and the next assertion would be two columns.
local floorRow = run({Left = 0, Top = 0, Right = 800, Bottom = 300}, true)
for _, slot in ipairs(floorRow) do
	expect(slot.Side, 52, 'the floor square is 52px')
	expect(slot.Left, 8, 'and the rail is still one column at the floor')
	expect(slot.Caption, 10, 'with the 10px caption')
end
expect(floorRow[1].Top, 8, 'the column fills the safe area exactly')
expect(floorRow[5].Bottom, 292, 'down to its last pixel')

-- ---- RUNG 3: TWO COLUMNS, 3 + 2 -----------------------------------------
-- The brief's short screen: 260px of safe height. 5 x 52 + 4 x 8 = 292 does not
-- fit 244, so the rail splits rather than running off the bottom.
local split = run({Left = 0, Top = 0, Right = 900, Bottom = 260}, false)
for _, slot in ipairs(split) do
	expect(slot.Side, 52, 'the split rail is drawn at the 52px floor')
end
expect(split[1].Left, 8, 'SHOPS heads the first column')
expect(split[2].Left, 8, 'UPGRADES under it')
expect(split[3].Left, 8, 'REWARDS under that -- three in the first column')
expect(split[4].Left, 68, 'WHEEL starts the second column, one side + one gap over')
expect(split[5].Left, 68, 'MUSIC under it -- two in the second')
expect(split[1].Top, split[4].Top, 'both columns start at the same top')
expect(split[1].Top, 44, 'which is the centred top of a 3-row stack: (260 - 172) / 2')
expect(split[3].Bottom, 216, 'and the taller column still ends inside the safe area')
ok(split[3].Bottom <= 260, 'nothing is clipped off the bottom')

-- ---- NO TWO BUTTONS EVER OVERLAP, at any safe height --------------------
-- 184px is the arithmetic floor of the ladder (3 x 52 + 2 x 6 = 168, plus the
-- 16px margin). Below it the rail overflows rather than vanishing, which no
-- shipping device reaches -- the shortest in the matrix is 338px tall.
-- One row per safe height, and one CHECK per invariant over the whole sweep:
-- 300 passing assertions of the same rule say nothing 1 does not, and they bury
-- the lanes that do.
local sides, columns = {}, {}
local short, uneven, notSquare, tiny, collide, spill = 0, 0, 0, 0, 0, 0
local rows, wrongRight = 0, 0
for height = 184, 1200, 4 do
	for _, touch in ipairs({true, false}) do
		rows += 1
		local placed = run({Left = 0, Top = 0, Right = 900, Bottom = height}, touch)
		if #placed ~= 5 then short += 1 end
		sides[placed[1].Side] = true
		local wide = false
		for _, slot in ipairs(placed) do
			if slot.Side < 44 then tiny += 1 end
			if slot.Side ~= placed[1].Side then uneven += 1 end
			if slot.Right - slot.Left ~= slot.Bottom - slot.Top then notSquare += 1 end
			if slot.Left > 8 then wide = true end
		end
		columns[wide and 2 or 1] = true
		for a = 1, 5 do
			for b = a + 1, 5 do
				if overlaps(placed[a], placed[b]) then collide += 1 end
			end
		end
		local rect = rectOf(placed)
		-- 184px is the arithmetic floor: 3 x 52 + 2 x 6 + the 16px margin. No
		-- shipping device is anywhere near it; the shortest in the matrix is 338.
		if rect.Bottom - rect.Top > height - 16 and height >= 200 then spill += 1 end
		if placed.RailRight ~= rect.Right then wrongRight += 1 end
	end
end
ok(rows > 400, 'the sweep covered ' .. rows .. ' safe heights on both form factors')
expect(short, 0, 'every one of them placed all five buttons')
expect(tiny, 0, 'and never drew a square under the 44px tap floor')
expect(uneven, 0, 'and never mixed two sizes in one rail')
expect(notSquare, 0, 'and never drew a rail button that was not square')
expect(collide, 0, 'and never overlapped two rail buttons')
expect(spill, 0, 'and never ran the rail past the safe height it was given')
expect(wrongRight, 0, 'and always returned the drawn right edge as ZyntraRailRight')
ok(sides[64] and sides[56] and sides[52], 'the sweep exercised all three side rungs')
ok(columns[1] and columns[2], 'and both the one- and two-column layouts')

-- ---- THE THUMBSTICK GLYPH, on the 705x338 reference phone ---------------
-- Galaxy A06, inset 0,58 -> safe (0,58)-(705,338). 264px of room, so the rail is
-- two 52px columns: x 8..118. THE GLYPH IS TESTED AGAINST THAT FULL WIDTH.
-- A glyph at x = 114 sits outside a single 64px column and inside the real
-- two-column rail, which is the case the old `left + side` test could not see.
local PHONE = {Left = 0, Top = 58, Right = 705, Bottom = 338}
local resting = run(PHONE, true, nil)
expect(resting[1].Left, 8, 'with no glyph drawn the rail keeps its column')
expect(resting[4].Left, 66, 'and its second column, one 52px side + the 6px touch gap over')
expect(resting[1].Top, 114, 'centred in the safe area: 58 + (280 - 168) / 2')
local glyph = {Left = 114, Top = 286, Width = 40, Height = 40}
local dodged = run(PHONE, true, glyph)
local glyphRect = {Left = glyph.Left, Top = glyph.Top,
	Right = glyph.Left + glyph.Width, Bottom = glyph.Top + glyph.Height}
expect(dodged[1].Top, 110, 'the rail moves ABOVE the glyph, by its own 8px margin')
for _, slot in ipairs(dodged) do
	ok(not overlaps(slot, glyphRect),
		slot.Name .. ' is clear of the resting thumbstick glyph')
	ok(slot.Top >= PHONE.Top and slot.Bottom <= PHONE.Bottom,
		slot.Name .. ' is still inside the safe area after the dodge')
end
-- A glyph that only a ONE-column rail would miss still has to move the rail:
-- this is the whole reason the test measures the combined width.
ok(glyph.Left >= 8 + 52, 'the glyph starts outside a single 52px column')
ok(glyph.Left < 8 + 52 * 2 + 6, 'and inside the two-column rail')
ok(dodged[1].Top ~= resting[1].Top, 'so the rail did move for it')

-- ---- neither side fits: the DOCUMENTED fallback, not a hidden rail ------
-- A glyph in the middle of a short screen leaves no room above or below. The
-- rail stays centred and complete; it is never hidden, shrunk further, or
-- silently moved to the other side of the screen.
local trapped = run(PHONE, true, {Left = 20, Top = 200, Width = 90, Height = 90})
expect(#trapped, 5, 'all five buttons are still placed')
expect(trapped[1].Top, resting[1].Top, 'the rail keeps the centred position')
expect(trapped[1].Left, 8, 'on the same side of the screen')
for _, slot in ipairs(trapped) do
	expect(slot.Side, 52, 'and at the same size')
end

-- ---- iPhone 13 LANDSCAPE, measured 2026-09-16 in the Studio Device Simulator ------
-- Viewport 749x368 with the 58px topbar already outside the safe gui space, so
-- safe (0,0)-(749,310). One column of five 52px buttons is 284 tall (y 13..297)
-- and the resting thumbstick glyph sits at (29,217) 74x74: neither above nor
-- below has room for 284px, so the OLD code left WHEEL and MUTE under the stick.
-- The rail has to fall back to two columns (168px), which DO fit above.
local IPHONE_LANDSCAPE = {Left = 0, Top = 0, Right = 749, Bottom = 310}
local landscapeGlyph = {Left = 29, Top = 217, Width = 74, Height = 74}
local landscapeRect = {Left = 29, Top = 217, Right = 103, Bottom = 291}
local single = run(IPHONE_LANDSCAPE, true, nil)
expect(single[1].Left, 8, 'landscape: with no glyph the rail is one column')
expect(single[5].Left, 8, 'landscape: all five in that column')
expect(single[1].Top, 13, 'landscape: centred, y 13')
local dodgedLandscape = run(IPHONE_LANDSCAPE, true, landscapeGlyph)
expect(dodgedLandscape[4].Left, 66, 'landscape: the rail split into two columns to dodge the stick')
expect(dodgedLandscape[1].Top, 41, 'landscape: and moved ABOVE the glyph by its 8px margin')
for _, slot in ipairs(dodgedLandscape) do
	ok(not overlaps(slot, landscapeRect), slot.Name .. ' (landscape) is clear of the thumbstick glyph')
	ok(slot.Top >= IPHONE_LANDSCAPE.Top and slot.Bottom <= IPHONE_LANDSCAPE.Bottom,
		slot.Name .. ' (landscape) stays inside the safe area')
	expect(slot.Side, 52, slot.Name .. ' (landscape) keeps the 52px side')
end

-- ---- ZyntraRailRight: the right edge the windows keep clear of -----------
-- RAIL_OVER_WINDOWS_20261007. Safe.Left + 8 + side * cols + gap * (cols - 1), in
-- UIDevice.Layout() space. The L4 shop, Daily and dev windows start 8px right
-- of it, so a value one column short would put a window under the rail.
expect(desk.RailRight, 72, 'one 64px pointer column at Safe.Left 0 ends at 8 + 64')
expect(tab.RailRight, 64, 'one 56px touch column ends at 8 + 56')
expect(floorRow.RailRight, 60, 'one 52px column at the floor ends at 8 + 52')
expect(split.RailRight, 120, 'two 52px pointer columns: 8 + 2 x 52 + the 8px gap')
expect(resting.RailRight, 118, 'the 705x338 phone, two 52px touch columns: 8 + 2 x 52 + 6')
expect(dodgedLandscape.RailRight, 118, 'iPhone 13 landscape after the dodge split: Safe.Left + 118')
expect(single.RailRight, 60, 'and before it, one 52px column: Safe.Left + 60')
-- 56px squares only reach two columns through the glyph path: a column that
-- fits the height but cannot dodge a tall glyph either way.
local tall = run({Left = 0, Top = 0, Right = 1024, Bottom = 768}, true,
	{Left = 20, Top = 100, Width = 60, Height = 500})
expect(tall[1].Side, 56, 'the tall-glyph tablet keeps the 56px side')
expect(tall[4].Left, 70, 'and splits into two columns: 8 + 56 + 6')
expect(tall.RailRight, 126, 'two 56px touch columns end at Safe.Left + 126')
-- A notched phone: the rail starts at ceil(Safe.Left + 8).
local notched = run({Left = 47, Top = 0, Right = 797, Bottom = 310}, true)
expect(notched[1].Left, 55, 'a notched phone starts the rail 8px inside its safe left')
expect(notched.RailRight, 55 + 52, 'and ZyntraRailRight follows the safe left: 47 + 8 + 52')
print('layout|' .. checks)
"""

# ── 11. EVERY RAIL DESTINATION, running the real routing ───────────────────
# REWARDS and WHEEL raise their own modals. SHOPS, UPGRADES and every shop name
# belong to the L4 shop, and since go-live (SHOP_UI_L4_GO_LIVE_20261007) its
# refusal is FINAL: there is no legacy page left to fall back to. REWRITTEN for
# RECORDS_SETTINGS_L4_20261007 (was "only RECORDS and SETTINGS open the
# terminal"): they are L4 pages, asked of the L4 bridge like every other name,
# and the L4 shop applies the round / queue / modal guards itself (its harness).
# The dev routes (J, the in-round DEV chip) ask the L4 dev menu the same way.
ROUTING_TESTS = r"""
local playerScripts = player:WaitForChild('PlayerScripts')
local rewardsEvent = playerScripts:FindFirstChild('OpenDailyRewards')
local wheelEvent = playerScripts:FindFirstChild('OpenLuckyWheel')
local terminalEvent = playerScripts:FindFirstChild('ZyntraOpenTerminal')
ok(rewardsEvent ~= nil, 'PlayerScripts.OpenDailyRewards exists')
ok(wheelEvent ~= nil, 'PlayerScripts.OpenLuckyWheel exists')
ok(terminalEvent ~= nil, 'PlayerScripts.ZyntraOpenTerminal exists (the public "open the shop on tab X" route)')
expect(rewardsEvent.ClassName, 'BindableEvent', 'and it is a BindableEvent')
expect(wheelEvent.ClassName, 'BindableEvent', 'and so is the wheel opener')
expect(wheelEvent.Adopted, true, 'the pre-existing OpenLuckyWheel was ADOPTED, not replaced')
expect(wheelEvent, adopted, 'it is the same instance the other client already created')
local count = 0
for _, child in ipairs(playerScripts.Children) do
	if child.Name == 'OpenLuckyWheel' then count += 1 end
end
expect(count, 1, 'create-if-absent never leaves two openers with one name')

local fired = {Rewards = 0, Wheel = 0}
rewardsEvent.Event:Connect(function() fired.Rewards += 1; table.insert(log, 'Rewards') end)
wheelEvent.Event:Connect(function() fired.Wheel += 1; table.insert(log, 'Wheel') end)
local function reset()
	fired.Rewards, fired.Wheel = 0, 0
	table.clear(shopAsks)
	table.clear(devAsks)
	table.clear(warnings)
	table.clear(flags)
	table.clear(log)
	inRound, queueBlocked, modalOpen = false, false, false
	shopAnswer, devAnswer = true, true
	shopBridge.Parent = playerScripts
	wheelBridge.Parent = playerScripts
end

-- ---- the two lobby-modal rail buttons -----------------------------------
reset()
rewardsButton.Activated:Fire({UserInputType = 'MouseButton1'})
expect(fired.Rewards, 1, 'REWARDS fires PlayerScripts.OpenDailyRewards')
expect(fired.Wheel, 0, 'and nothing else')
expect(#shopAsks, 0, 'and never opens the shop')
reset()
wheelButton.Activated:Fire({UserInputType = 'MouseButton1'})
expect(fired.Wheel, 1, 'WHEEL fires PlayerScripts.OpenLuckyWheel')
expect(fired.Rewards, 0, 'and nothing else')
expect(#shopAsks, 0, 'and never opens the shop')

-- ---- SHOPS and UPGRADES ask the L4 shop, and only the L4 shop -------------
reset()
shopButton.Activated:Fire({UserInputType = 'MouseButton1'})
expect(#shopAsks, 1, 'SHOPS asks PlayerScripts.ZyntraShopUIOpen once')
expect(shopAsks[1], 'Shop', 'for the Shop page')
expect(fired.Rewards + fired.Wheel + #devAsks, 0, 'and raises nothing else')
reset()
openButton.Activated:Fire({UserInputType = 'MouseButton1'})
expect(#shopAsks, 1, 'UPGRADES asks the L4 shop once')
expect(shopAsks[1], 'Upgrades', 'for the Upgrades page')
expect(#devAsks, 0, 'and not the dev menu in the lobby')
-- THE REFUSAL IS FINAL. L4 applies the guards itself and warns about its own
-- build failures; this script must not open anything in its place.
reset()
shopAnswer = false
shopButton.Activated:Fire()
openButton.Activated:Fire()
expect(#shopAsks, 2, 'a refusing L4 shop was still asked, once per press')
expect(fired.Rewards + fired.Wheel + #devAsks + #warnings, 0, 'and a refusal opens nothing else, silently')
reset()
shopAnswer = 'boom'
shopButton.Activated:Fire()
expect(#shopAsks, 1, 'a bridge that throws is asked')
expect(fired.Rewards + fired.Wheel + #devAsks, 0, 'and its fault opens nothing here')
-- No L4 install at all: one clear warning naming the bridge, and nothing opens.
reset()
shopBridge.Parent = nil
shopButton.Activated:Fire()
terminalEvent:Fire('Records')
expect(#shopAsks, 0, 'with no L4 shop installed nothing is asked')
expect(#warnings, 2, 'and the missing install is reported, once per route')
ok(string.find(warnings[1], 'ZyntraShopUIOpen', 1, true) ~= nil, 'by the bridge name')

-- ---- the three refusals, on the lobby-modal buttons and on the event -----
-- 'modal' is a screen-owning modal that is NOT one of the rail's own windows
-- (re-entry): no flag is set, so switchFrom closes nothing and both refuse.
for _, case in ipairs({'inRound', 'queue', 'modal'}) do
	reset()
	if case == 'inRound' then inRound = true
	elseif case == 'queue' then queueBlocked = true
	else modalOpen = true end
	rewardsButton.Activated:Fire()
	wheelButton.Activated:Fire()
	terminalEvent:Fire('Rewards')
	expect(fired.Rewards, 0, 'no rewards modal is raised while ' .. case)
	expect(fired.Wheel, 0, 'and no wheel modal while ' .. case)
	-- RECORDS / SETTINGS are L4 pages: L4 owns the same guards and refuses there.
	terminalEvent:Fire('Records')
	terminalEvent:Fire('Settings')
	expect(table.concat(shopAsks, ','), 'Records,Settings', 'RECORDS / SETTINGS are asked of L4, which owns the guards, while ' .. case)
end

-- ---- RAIL_OVER_WINDOWS_20261007: a rail press switches window -------------
-- The rail stays up over its own windows. A press closes the OTHER open window
-- through its synchronous bridge, then opens its own through the usual route.
-- The log is one ordered list, so the close is proved to come FIRST.
reset()
flags.ZyntraStoreOpen = true
rewardsButton.Activated:Fire()
expect(table.concat(log, ','), 'shop:close,Rewards', 'shop open + REWARDS: the shop closes, then Daily Rewards fires')
expect(flags.ZyntraStoreOpen, nil, 'and the shop flag is down')
reset()
flags.LuckyWheelOpen = true
shopButton.Activated:Fire()
expect(table.concat(log, ','), 'wheel:close,shop:Shop', 'wheel open + SHOPS: CloseLuckyWheel, then the Shop page is asked')
reset()
flags.DailyRewardsOpen = true
wheelButton.Activated:Fire()
expect(table.concat(log, ','), 'daily:close,Wheel', 'Daily open + WHEEL: Daily closes, then the wheel fires')
reset()
devAllowed = true
flags.DevPhoneOpen = true
openButton.Activated:Fire()
expect(table.concat(log, ','), 'dev:false,shop:Upgrades', 'dev menu open + UPGRADES: the dev menu is asked to close (false), then Upgrades')
devAllowed = false
-- The open window's own button SELECTS, it never closes.
reset()
flags.ZyntraStoreOpen = true
openButton.Activated:Fire()
expect(table.concat(log, ','), 'shop:Upgrades', 'shop open + UPGRADES: no close, one Upgrades ask (a tab switch)')
expect(flags.ZyntraStoreOpen, true, 'and the shop stays open')
reset()
flags.DailyRewardsOpen = true
rewardsButton.Activated:Fire()
expect(#log, 0, 'Daily open + REWARDS: nothing is invoked')
expect(fired.Rewards, 0, 'and Daily Rewards is not fired a second time')
expect(flags.DailyRewardsOpen, true, 'and it stays open')
reset()
flags.ZyntraStoreOpen = true
shopButton.Activated:Fire()
expect(table.concat(log, ','), 'shop:Shop', 'shop open + SHOPS: no close, one Shop ask (a tab switch)')
expect(flags.ZyntraStoreOpen, true, 'and the shop stays open')
reset()
flags.LuckyWheelOpen = true
wheelButton.Activated:Fire()
expect(#log, 0, 'wheel open + WHEEL: nothing is invoked')
expect(fired.Wheel, 0, 'and the wheel is not fired a second time')
expect(flags.LuckyWheelOpen, true, 'and it stays open')
-- A window that cannot be closed is never stacked on.
reset()
wheelBridge.Parent = nil
flags.LuckyWheelOpen = true
rewardsButton.Activated:Fire()
expect(fired.Rewards, 0, 'wheel open without CloseLuckyWheel + REWARDS: no second modal')
expect(#log, 0, 'and nothing else is invoked')
-- In a round UPGRADES is the touch developer's DEV chip: no switching there.
reset()
devAllowed, inRound = true, true
flags.DailyRewardsOpen = true
openButton.Activated:Fire()
expect(table.concat(log, ','), 'dev:nil', 'in a round UPGRADES asks the dev menu once and closes nothing')
devAllowed = false
-- The lobby token pill's + (owner, 2026-10-08) switches through the SAME table:
-- PlayerScripts.ZyntraRailSwitch is switchFrom itself, so the pill never needs a
-- second copy of the bridges. The pill then opens the shop on its own.
local railSwitch = playerScripts:FindFirstChild('ZyntraRailSwitch')
ok(railSwitch ~= nil, 'PlayerScripts.ZyntraRailSwitch exists')
expect(railSwitch.ClassName, 'BindableFunction', 'and it is a BindableFunction (synchronous)')
reset()
flags.DailyRewardsOpen = true
railSwitch.OnInvoke('ZyntraStoreOpen')
expect(table.concat(log, ','), 'daily:close', 'pill + over Daily: Daily closes, exactly once')
expect(#shopAsks, 0, 'and the switch asks the shop nothing')
expect(flags.DailyRewardsOpen, nil, 'and the Daily flag is down when it returns')
reset()
flags.ZyntraStoreOpen = true
railSwitch.OnInvoke('ZyntraStoreOpen')
expect(#log, 0, 'pill + over the shop: nothing is closed')
expect(flags.ZyntraStoreOpen, true, 'and the shop stays open')
reset()
flags.LuckyWheelOpen = true
railSwitch.OnInvoke('ZyntraStoreOpen')
expect(table.concat(log, ','), 'wheel:close', 'pill + over the wheel: CloseLuckyWheel')
reset()
flags.DevPhoneOpen = true
railSwitch.OnInvoke('ZyntraStoreOpen')
expect(table.concat(log, ','), 'dev:false', 'pill + over the dev menu: it is asked to close (false)')

-- ---- ZyntraOpenTerminal: Rewards to its modal, every other name to L4 ----
reset()
terminalEvent:Fire('Rewards')
expect(fired.Rewards, 1, 'ZyntraOpenTerminal "Rewards" reaches the standalone modal')
expect(#shopAsks, 0, 'and never the shop')
for _, case in ipairs({{'Records', 'Records'}, {'Settings', 'Settings'}, {'Shop', 'Shop'}, {'Upgrades', 'Upgrades'},
	{'Skins', 'Skins'}, {'Donate', 'Donate'}, {'Colors', 'Colors'}, {'Notes', 'Notes'},
	{'Rewords', 'Rewords'}}) do
	reset()
	shopAnswer = false
	terminalEvent:Fire(case[1])
	expect(#shopAsks, 1, case[1] .. ' is asked of the L4 shop once')
	expect(shopAsks[1], case[2], case[1] .. ' is asked of the L4 shop as ' .. case[2])
	expect(fired.Rewards + fired.Wheel + #devAsks, 0, case[1] .. ': a refusal opens nothing else; a near-miss spelling never reaches the rewards modal')
end
reset()
shopAnswer = false
terminalEvent:Fire()
expect(shopAsks[1], 'Shop', 'no tab means the L4 Shop page')

-- ---- the dev routes: the L4 dev menu, final as well ---------------------
reset()
devAllowed, inRound = true, true
openButton.Activated:Fire()
expect(#devAsks, 1, 'the in-round ZYNTRA // DEV chip asks the L4 dev menu')
expect(devAsks[1], 'nil', 'as a toggle')
expect(#shopAsks, 0, 'and never the shop')
reset()
devAllowed, devAnswer = true, false
toggleDevMenu()
toggleDevMenu(true)
expect(table.concat(devAsks, ','), 'nil,true', 'J and an explicit OPEN both ask the dev menu')
expect(#shopAsks + fired.Rewards + fired.Wheel, 0, 'and its refusal opens nothing else (there is no DEV tab, no terminal)')
reset()
devAllowed = false
toggleDevMenu()
inRound = true
openButton.Activated:Fire()
expect(#devAsks, 0, 'a player who is not a developer never reaches the dev menu')
-- A developer in the LOBBY without a keyboard (go-live review 2026-10-07): the
-- L4 shop's DEV header is the way in (proven in the L4 shop harness, section 1c,
-- and the dev harness, 6b), so UPGRADES and SHOPS must still reach the shop
-- for a developer, and J / DevPhoneCommand there still asks the dev menu.
reset()
devAllowed = true
openButton.Activated:Fire()
shopButton.Activated:Fire()
expect(table.concat(shopAsks, ','), 'Upgrades,Shop', 'a developer in the lobby reaches the L4 shop from UPGRADES and SHOPS')
expect(#devAsks, 0, 'and neither lobby button skips to the dev menu')
toggleDevMenu()
expect(#devAsks, 1, 'J / DevPhoneCommand in the lobby asks the dev menu')

-- ---- a BindableEvent that is not one -------------------------------------
-- A place where something else already owns the name must WARN and stand down,
-- not throw on the first press and take the whole rail down with it.
reset()
local impostorOpener = lobbyModalOpener('OpenImpostor')
expect(#warnings, 1, 'a wrongly-typed opener is reported once')
ok(string.find(warnings[1], 'OpenImpostor') ~= nil, 'and named in the warning')
impostorOpener()
expect(#warnings, 1, 'pressing it is a no-op rather than an error')
print('routing|' .. checks)
"""

# -- 11a. MUSIC, the lobby-music switch, running the production block --------
# The terminal's SETTINGS page shared this logic with the rail button. The page
# is deleted (the L4 SETTINGS row is its replacement, in the L4 harness); the
# rail keeps the switch, with the same action, payload, readback and revert.
# REWRITTEN 2026-10-07 (review): MUSIC kept its own pending state and fired at
# once, so a SETTINGS row press, Close, then MUSIC inside the server's 1 s window
# (and the reverse) was dropped by the server and drawn wrong for 12 s. Both
# surfaces now send through the REAL ShopData.toggleSetting: one Pending, one
# last-send clock. "the only timer is the 12 s revert" became "the 1.1 s hold
# and the 12 s revert"; every other check is kept.
MUSIC_TESTS = r"""
local caption = musicButton.SectionButtonContent.SectionCaption
local ShopData = require(shopDataModule)
-- Runs (and drops) the timers of at most `limit` seconds; the rest stay queued.
local function runDelays(limit)
	local due, keep = {}, {}
	for _, entry in ipairs(delayed) do
		ok(entry.Seconds == 12 or (entry.Seconds > 0 and entry.Seconds <= 1.1),
			'the only timers are the 1.1 s hold and the 12 s revert: ' .. entry.Seconds)
		table.insert(entry.Seconds <= limit and due or keep, entry)
	end
	delayed = keep
	for _, entry in ipairs(due) do entry.Fn() end
	return #due
end
expect(musicButton.Active, false, 'MUSIC ships inactive until the server publishes the switch')
expect(caption.Text, 'Music', 'and reads MUSIC (the L4 graft mirrors it)')
expect(musicButton.Text, 'Loading music', 'with its fallback caption')
musicButton.Activated:Fire()
expect(#fired, 0, 'a press before the attribute is published sends nothing')
setAttr('LobbyMusicEnabled', true)
expect(caption.Text, 'Mute', 'published ON: MUTE')
expect(caption.TextColor3, COLORS.accent, 'in the accent')
expect(musicButton.Active, true, 'and the button arms')
musicButton.Activated:Fire()
expect(#fired, 1, 'a press sends once')
expect(fired[1].Action, 'SetAccessibility', 'the legacy action')
expect(fired[1].Payload.Key, 'LobbyMusicEnabled', 'for the lobby music key')
expect(fired[1].Payload.Enabled, false, 'asking for OFF')
expect(caption.Text, 'Unmute', 'drawn at once')
expect(ShopData.setting('LobbyMusicEnabled'), false, 'and the SETTINGS row reads the same press')
setAttr('LobbyMusicEnabled', false)
expect(caption.Text, 'Unmute', 'the attribute confirms it')
runDelays(12)
expect(caption.Text, 'Unmute', 'and no revert follows a confirmed press')
-- The review case: the SETTINGS row ("Zyntra Shop L4" calls ShopData.toggleSetting),
-- Close, then MUSIC 0.7 s later. MUSIC is held past the server's window.
now += 30
ShopData.toggleSetting('LobbyMusicEnabled')
expect(#fired, 2, 'the row sends at once')
expect(fired[2].Payload.Enabled, true, 'asking for ON')
expect(caption.Text, 'Mute', 'and the rail draws it at once')
setAttr('LobbyMusicEnabled', true)
now += 0.7
musicButton.Activated:Fire()
expect(#fired, 2, 'MUSIC 0.7 s after the row is held, not sent to be dropped')
expect(caption.Text, 'Unmute', 'and drawn at once all the same')
expect(runDelays(1.1), 1, 'one held send')
expect(#fired, 3, 'sent once the window has passed')
expect(fired[3].Payload.Enabled, false, 'asking for OFF')
setAttr('LobbyMusicEnabled', false)
expect(caption.Text, 'Unmute', 'and confirmed')
-- The reverse: MUSIC, then the row 0.5 s later.
now += 30
musicButton.Activated:Fire()
expect(#fired, 4, 'MUSIC sends at once')
expect(fired[4].Payload.Enabled, true, 'asking for ON')
now += 0.5
ShopData.toggleSetting('LobbyMusicEnabled')
expect(#fired, 4, 'the row 0.5 s after MUSIC is held')
expect(caption.Text, 'Unmute', 'and the rail draws the row press at once')
expect(runDelays(1.1), 1, 'one held send')
expect(fired[5].Payload.Enabled, false, 'the row press goes out after the window, asking for OFF')
setAttr('LobbyMusicEnabled', false)
runDelays(12)
expect(caption.Text, 'Unmute', 'confirmed, and no revert follows')
now += 30
musicButton.Activated:Fire()
expect(fired[6].Payload.Enabled, true, 'the next press asks for ON')
expect(caption.Text, 'Mute', 'drawn at once')
runDelays(12)
expect(caption.Text, 'Unmute', '12 s without the attribute: back to what the server says')
-- 'hidden' was 'modal' until RAIL_OVER_WINDOWS_20261007: the rail now stays up
-- over its own windows, and what hides it (a round, the queue, re-entry) shows
-- up here as Visible = false.
for _, case in ipairs({'InRound', 'hidden'}) do
	if case == 'InRound' then setAttr('InRound', true) else musicButton.Visible = false end
	musicButton.Active = true -- even a stale Active cannot send
	musicButton.Activated:Fire()
	runDelays(12)
	expect(#fired, 6, 'no send while ' .. case)
	if case == 'InRound' then setAttr('InRound', nil) else musicButton.Visible = true end
end
-- Over a rail window MUSIC still toggles: Visible, armed by its own refresh.
now += 30
modalOpen = true
musicButton.Active = false
musicButton:FireVisible()
expect(musicButton.Active, true, 'a screen-owning modal no longer stands a visible MUSIC down')
musicButton.Activated:Fire()
expect(#fired, 7, 'and a press over the modal sends')
expect(fired[7].Payload.Enabled, true, 'asking for ON')
modalOpen = false
musicButton.Visible = false
musicButton:FireVisible()
expect(musicButton.Active, false, 'a hidden rail stands MUSIC down')
print('music|' .. checks)
"""

# ── 11b. THE L4 RAIL GRAFT FOLLOWS THE DEV CHIP (go-live review 2026-10-07) ─
# "Zyntra Shop L4" grafts an opaque face (L4Skin_Face) into every rail button and
# hides SectionButtonContent once. In a round a touch developer's UPGRADES is the
# text-only ZYNTRA // DEV chip: a graft left visible there covered the chip's
# text with an UPGRADES tile. Runs the production block of updateVisibility.
CHIPSKIN_TESTS = r"""
local function rail(skinned)
	local list = {}
	for index = 1, 5 do
		local entry = Instance.new('TextButton')
		local content = Instance.new('Frame')
		content.Name = 'SectionButtonContent'
		content.Parent = entry
		entry.SectionButtonContent = content
		if skinned[index] then
			local graft = Instance.new('Frame')
			graft.Name = 'L4Skin_Face'
			graft.Parent = entry
		end
		table.insert(list, entry)
	end
	return list
end
local function faces(list, label, skin, content)
	for index, entry in ipairs(list) do
		local graft = entry:FindFirstChild('L4Skin_Face')
		if graft then
			expect(graft.Visible, skin, label .. ': graft ' .. index)
			expect(entry.SectionButtonContent.Visible, false, label .. ': no legacy art under graft ' .. index)
		else
			expect(entry.SectionButtonContent.Visible, content, label .. ': legacy art ' .. index)
		end
	end
end
local skinned = rail({true, true, true, true, true})
apply(false, skinned)
faces(skinned, 'lobby, L4 skinned', true)
apply(true, skinned)
faces(skinned, 'in-round DEV chip', false)
apply(false, skinned)
faces(skinned, 'back in the lobby', true)
expect(skinned[2].TextTransparency, 1, 'and the square hides its fallback caption again')
-- Without L4 (or before its grafts land) the legacy art is the face.
local bare = rail({})
apply(false, bare)
faces(bare, 'lobby, unskinned', nil, true)
apply(true, bare)
faces(bare, 'DEV chip, unskinned', nil, false)
-- A rail L4 skinned only in part: each button follows its own graft.
local mixed = rail({true, false, true, false, true})
apply(false, mixed)
faces(mixed, 'lobby, partly skinned', true, true)
apply(true, mixed)
faces(mixed, 'DEV chip, partly skinned', false, false)
print('chipskin|' .. checks)
"""

# ── 11c. THE RAIL OVER ITS OWN WINDOWS (RAIL_OVER_WINDOWS_20261007) ─────────
# Runs updateVisibility's real head -- its three locals, the otherModal rule,
# the five SetInteractive calls and the DisplayOrder line -- against the REAL
# UIDevice modal set and the REAL modalBlocksStore. In the lobby a rail window
# keeps all five buttons up and raises the gui to 119; re-entry and the queue
# hide them at 55; a round keeps the old rule (any modal hides the DEV chip).
RAILMODAL_TESTS = r"""
local RAIL = {shopButton, openButton, rewardsButton, wheelButton, musicButton}
local function state(label, setup, shown, order)
	table.clear(attributes)
	for key, value in pairs(setup) do attributes[key] = value end
	for _, entry in ipairs(RAIL) do entry.Visible, entry.Active = 'stale', 'stale' end
	gui.DisplayOrder = 'stale'
	updateVisibility()
	for index, entry in ipairs(RAIL) do
		expect(entry.Visible, shown[index], label .. ': ' .. entry.Name .. ' Visible')
		expect(entry.Active, shown[index], label .. ': ' .. entry.Name .. ' Active')
	end
	expect(gui.DisplayOrder, order, label .. ': rail DisplayOrder')
end
local ALL, NONE = {true, true, true, true, true}, {false, false, false, false, false}
state('idle lobby', {}, ALL, 55)
for _, flag in ipairs({'ZyntraStoreOpen', 'DailyRewardsOpen', 'LuckyWheelOpen', 'DevPhoneOpen'}) do
	state(flag, {[flag] = true}, ALL, 119)
end
state('a closed window drops the rail back', {}, ALL, 55)
state('ZyntraReentryOpen', {ZyntraReentryOpen = true}, NONE, 55)
state('re-entry over a rail window', {ZyntraReentryOpen = true, ZyntraStoreOpen = true}, NONE, 55)
state('queue', {QueueModalOpen = true}, NONE, 55)
state('queue over a rail window', {QueueModalOpen = true, LuckyWheelOpen = true}, NONE, 55)
state('lobby dispatch briefing', {DispatchBriefingOpen = true}, ALL, 55)
-- Rounds: only a touch developer's UPGRADES (the DEV chip) is ever drawn, and
-- any screen-owning modal still hides it.
state('round, touch dev', {InRound = true}, {false, true, false, false, false}, 55)
state('round, touch dev, DevPhoneOpen', {InRound = true, DevPhoneOpen = true}, NONE, 55)
state('round, touch dev, briefing', {InRound = true, DispatchBriefingOpen = true}, NONE, 55)
touchLayout = false
state('round, raw touchscreen with pointer layout', {InRound = true}, NONE, 55)
touchLayout = true
UserInputService.TouchEnabled = false
state('round, forced touch layout on pointer host', {InRound = true}, {false, true, false, false, false}, 55)
devAllowed = false
state('round, not a developer', {InRound = true}, NONE, 55)
print('railmodal|' .. checks)
"""

# ── 12. THE MODAL SET, running UIDevice's own list and predicate ────────────
# ZyntraStore's rail, and both new clients, gate on
# UIDevice.ScreenOwningModalOpen(). The two new modals are only in that answer if
# they are in the list, and a name that is merely SPELLED in the file proves
# nothing -- so the list and the predicate are run together.
MODALS_TESTS = r"""
expect(UIDevice.ScreenOwningModalOpen(), false, 'an idle lobby owns no modal')
for _, attribute in ipairs({'ZyntraStoreOpen', 'DevPhoneOpen', 'ZyntraReentryOpen',
	'QueueModalOpen', 'LuckyWheelOpen', 'DailyRewardsOpen', 'AchievementsOpen', 'HelpPanelOpen'}) do
	attributes[attribute] = true
	expect(UIDevice.ScreenOwningModalOpen(), true, attribute .. ' owns the screen')
	attributes[attribute] = nil
	expect(UIDevice.ScreenOwningModalOpen(), false, attribute .. ' releases it again')
end
expect(#SCREEN_OWNING_MODALS, 9, 'the set includes achievements, help and the actual results modal')
-- Not `== true` is the whole point of the predicate: a client that writes the
-- attribute as a string, or clears it to false, must not read as "modal up".
attributes.LuckyWheelOpen = false
expect(UIDevice.ScreenOwningModalOpen(), false, 'false is not open')
attributes.LuckyWheelOpen = 'yes'
expect(UIDevice.ScreenOwningModalOpen(), false, 'and neither is a truthy non-boolean')
attributes.LuckyWheelOpen = nil
-- OnScreenOwningModalChanged has to watch the SAME list -- ZyntraStore now
-- re-runs updateVisibility from it, and a rail that never hears about the wheel
-- stays Active underneath it.
local fired = 0
UIDevice.OnScreenOwningModalChanged(function() fired += 1 end)
expect(#watched, 9, 'the change hook subscribes to all nine')
for _, attribute in ipairs({'LuckyWheelOpen', 'DailyRewardsOpen'}) do
	ok(table.find(watched, attribute) ~= nil, attribute .. ' is watched, not just listed')
end
print('modals|' .. checks)
"""


# ── 13. THE LOBBY SHOP WALL'S BUY, running the real bridge ─────────────────
# The wall's detail card fires PlayerScripts.ZyntraShopBuy with an item key. It
# used to run the legacy Shop page's card buy; that page is gone, so the bridge
# now decides the kind from the same three ZyntraConfig tables the wall is built
# from. It must prompt exactly the configured id, never a guessed one, and a
# token item goes through the real ShopData dispatcher and its pending latch.
WALL_BUY_TESTS = r"""
local bridge = playerScripts:FindFirstChild('ZyntraShopBuy')
ok(bridge ~= nil, 'PlayerScripts.ZyntraShopBuy exists')
local function buy(key)
	table.clear(prompts)
	table.clear(fired)
	table.clear(warnings)
	bridge:Fire(key)
end
buy('Supporter')
expect(#prompts, 1, 'a pass prompts once')
expect(prompts[1], 'pass:11', 'as a GAME PASS, with its configured id')
buy('Tokens4')
expect(prompts[1], 'product:22', 'Tokens4 (hidden from the L4 shop) still sells on the wall, as a product')
buy('EmergencyReentry')
expect(prompts[1], 'product:33', 'and so does Emergency Re-entry')
buy('SpeedPotion')
expect(#prompts, 0, 'a token item prompts no Robux')
expect(#fired, 1, 'it fires one action')
expect(fired[1].Action, 'BuyItem', 'the contract action')
expect(fired[1].Payload.Key, 'SpeedPotion', 'with the contract payload key')
-- ONE BUY PER WRITE (go-live review 2026-10-07). A second BUY while the first
-- write is still pending bought twice: the server's 1 s per-action window had
-- already passed. The wall now shares ShopData's latch with the L4 cards.
table.clear(fired)
bridge:Fire('SpeedPotion')
expect(#fired, 0, 'a second BUY during the write fires nothing')
-- The push ends the write. The next BUY is held past the server's window, then sent.
profileChanged.OnClientEvent:Fire({Tokens = 7})
local before = #delayed
bridge:Fire('SpeedPotion')
local held
for index = before + 1, #delayed do
	if delayed[index].Seconds <= 1.1 then held = delayed[index] end
end
ok(held ~= nil and #fired == 0, 'right after the push the next BUY waits out the server window')
held.Fn()
expect(#fired, 1, 'and then fires once')
-- Short of tokens: nothing leaves the client.
profileChanged.OnClientEvent:Fire({Tokens = 2})
buy('SpeedPotion')
expect(#fired, 0, 'a BUY the balance cannot cover fires nothing')
-- No ShopData in the place: warned by name, nothing fired.
shopUI.Name = 'Elsewhere'
buy('SpeedPotion')
expect(#fired + #prompts, 0, 'without ShopData nothing fires')
ok(#warnings == 1 and string.find(warnings[1], 'ShopData', 1, true) ~= nil, 'and the missing module is named')
shopUI.Name = 'ZyntraShopUI'
buy('Unconfigured')
expect(#prompts, 0, 'an unconfigured id prompts nothing')
expect(#warnings, 1, 'and says so')
buy('NoSuchThing')
expect(#prompts + #fired + #warnings, 0, 'an unknown key is ignored rather than guessed at')
buy(nil)
expect(#prompts + #fired, 0, 'and so is no key')
print('wallbuy|' .. checks)
"""


LANES: dict[str, int] = {}


def lua(binary: str, name: str, body: str) -> int:
    with tempfile.TemporaryDirectory(prefix="zyntra-store-") as directory:
        fixture = Path(directory) / f"{name}.luau"
        fixture.write_text(body, encoding="utf-8")
        result = subprocess.run([binary, str(fixture)], timeout=30,
                                capture_output=True, text=True)
        if result.returncode != 0:
            raise SystemExit(name + " fixture failed:" + chr(10)
                             + result.stdout + chr(10) + result.stderr)
    line = result.stdout.strip().splitlines()[-1]
    label, _, count = line.partition("|")
    assert label == name, f"{name}: unexpected output {result.stdout!r}"
    # A lane that runs nothing still exits 0 and still prints its label, so the
    # count is reported rather than only summed.
    assert int(count) > 0, f"{name}: the fixture asserted nothing"
    LANES[name] = int(count)
    return int(count)


def main() -> None:
    global CHECKS
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")

    # The REAL ShopData (ReplicatedStorage.ZyntraShopUI) behind the three remotes
    # it uses, shared by lanes 11a and 13. Needs `player`, `Config`,
    # `MarketplaceService` and `fired` declared before it.
    shopdata_fixture = r"""
-- Token items go through the REAL ShopData (ReplicatedStorage.ZyntraShopUI),
-- behind the three remotes it uses, so the latch under test is production's.
local function folder(name, parent)
	local node = Instance.new('Folder')
	node.Name = name
	function node:WaitForChild(child) return assert(self:FindFirstChild(child), 'fixture is missing ' .. child) end
	if parent then node.Parent = parent end
	return node
end
local ReplicatedStorage = folder('ReplicatedStorage')
local remotes = folder('Remotes', ReplicatedStorage)
local actionRemote = Instance.new('RemoteEvent')
actionRemote.Name = 'ZyntraAction'
function actionRemote:FireServer(action, payload) table.insert(fired, {Action = action, Payload = payload}) end
actionRemote.Parent = remotes
local profileAnswer = {Tokens = 10}
local getProfile = Instance.new('RemoteFunction')
getProfile.Name = 'ZyntraGetProfile'
function getProfile:InvokeServer() return profileAnswer end
getProfile.Parent = remotes
local profileChanged = Instance.new('RemoteEvent')
profileChanged.Name = 'ZyntraProfileChanged'
profileChanged.OnClientEvent = signal()
profileChanged.Parent = remotes
local values = {ZyntraConfig = Config, ZyntraSkins = {Get = function() return nil end},
	ProtectionClient = {Changed = signal(), GetState = function() return {} end}}
for name in pairs(values) do
	local module = Instance.new('ModuleScript')
	module.Name = name
	module.Parent = ReplicatedStorage
end
local shopUI = folder('ZyntraShopUI', ReplicatedStorage)
local shopDataModule = Instance.new('ModuleScript')
shopDataModule.Name = 'ShopData'
shopDataModule.Parent = shopUI
local game = {GetService = function(_, name)
	return ({Players = {LocalPlayer = player}, ReplicatedStorage = ReplicatedStorage,
		MarketplaceService = MarketplaceService})[name]
end}
local require
local function loadShopData()
--@@SHOPDATA@@
end
local loaded = {}
require = function(module)
	if loaded[module] == nil then
		loaded[module] = module.Name == 'ShopData' and loadShopData() or values[module.Name]
	end
	return loaded[module]
end
""".replace("--@@SHOPDATA@@", SHOPDATA, 1)

    # ── 9. the HUD rail, from the production block ─────────────────────────
    rail_block = section("local openButton = button(gui,",
                         "-- C5_ZYNTRA_OPEN_BUTTON_20260829")
    helpers = "\n".join([
        section("local function corner(parent, radius)", "\nlocal function outline("),
        section("local function outline(parent, color, transparency, thickness)",
                "\nlocal function label("),
        section("local function label(parent, text, size, position, textSize, color, font)",
                "\nlocal function button("),
        section("local function button(parent, text, size, position)",
                "\n-- Imagegen section art"),
        section("local SECTION_IMAGES = ", "\nlocal function layoutSquareSections("),
    ])
    rail_fakes = r"""
-- NO TweenService and NO player here on purpose: the removed circular block
-- reached for both, so this fixture cannot even load if it comes back.
local function object2(class)
	local obj = object(class)
	obj.Attributes = {}
	function obj:SetAttribute(key, value) self.Attributes[key] = value end
	function obj:GetAttribute(key) return self.Attributes[key] end
	function obj:FindFirstChild(name)
		for _, child in ipairs(self.Children) do
			if child.Name == name then return child end
		end
		return nil
	end
	function obj:FindFirstChildOfClass(class2)
		for _, child in ipairs(self.Children) do
			if child.ClassName == class2 then return child end
		end
		return nil
	end
	function obj:IsA(className) return self.ClassName == className end
	if class == 'BindableEvent' then
		obj.Event = signal()
		function obj:Fire(...) self.Event:Fire(...) end
	end
	obj.MouseEnter, obj.MouseLeave = signal(), signal()
	obj.__newindex = nil
	return obj
end
Instance.new = function(class)
	local obj = object2(class)
	setmetatable(obj, {__newindex = function(self, key, value)
		rawset(self, key, value)
		if key == 'Parent' and type(value) == 'table' and value.Children then
			table.insert(value.Children, self)
		end
	end})
	return obj
end
local gui = Instance.new('ScreenGui')
"""
    CHECKS += lua(binary, "rail", "\n".join([
        FAKES, rail_fakes, helpers, rail_block, RAIL_TESTS,
    ]))

    # ── 10. the fit ladder, from the production layoutSquareSections ───────
    layout_block = section("local function layoutSquareSections(layout,",
                           "\nlocal openButton = button(gui,")
    layout_fakes = r"""
-- The thumbstick GLYPH, not its activation region: the production code walks
-- PlayerGui.TouchGui.TouchControlFrame.DynamicThumbstickFrame.ThumbstickStart
-- and reads AbsolutePosition/AbsoluteSize off it, so the fixture stands up that
-- exact chain. An AbsoluteSize.Y of 0 is how "no glyph is drawn" looks.
local vector2
vector2 = function(x, y)
	return setmetatable({X = x, Y = y},
		{__sub = function(a, b) return vector2(a.X - b.X, a.Y - b.Y) end})
end
local function node(name, children)
	local entry = {Name = name, Children = children or {},
		AbsolutePosition = vector2(0, 0), AbsoluteSize = vector2(0, 0)}
	function entry:FindFirstChild(childName)
		for _, child in ipairs(self.Children) do
			if child.Name == childName then return child end
		end
		return nil
	end
	function entry:IsA(className) return className == 'GuiObject' end
	return entry
end
local glyphNode = node('ThumbstickStart')
local playerGui = node('PlayerGui', {node('TouchGui',
	{node('TouchControlFrame', {node('DynamicThumbstickFrame', {glyphNode})})})})
gui.Parent = playerGui
local function setGlyph(glyph)
	if glyph then
		glyphNode.AbsolutePosition = vector2(glyph.Left, glyph.Top)
		glyphNode.AbsoluteSize = vector2(glyph.Width, glyph.Height)
	else
		glyphNode.AbsoluteSize = vector2(0, 0)
	end
end
function UIDevice.LocalPosition(_gui, x, y) return UDim2.fromOffset(x, y) end
function UIDevice.LocalOffset(_gui, x, y) return x, y end
"""
    CHECKS += lua(binary, "layout", "\n".join([
        FAKES, rail_fakes, layout_fakes, helpers, layout_block, rail_block,
        LAYOUT_TESTS,
    ]))

    # ── 11. the routing, from the production blocks ────────────────────────
    dev_block = section("-- J, PlayerScripts.DevPhoneCommand and the in-round",
                        "\n-- The two lobby modals that are not the shop")
    opener_block = section("-- The two lobby modals that are not the shop",
                           "\n-- Every shop entry: the SHOPS and UPGRADES rail buttons")
    kiosk_block = section("-- Every shop entry: the SHOPS and UPGRADES rail buttons",
                          "\n-- Studio-only input seam")
    activated_block = section("openButton.Activated:Connect(function()",
                              "\nUserInputService.InputBegan")
    routing_fakes = r"""
local warnings = {}
local function warn(message) table.insert(warnings, message) end
local inRound, queueBlocked, modalOpen = false, false, false
local devAllowed = false
local playerScripts = Instance.new('Folder')
playerScripts.Name = 'PlayerScripts'
-- Another client got to the wheel opener first. The create-if-absent pattern has
-- to ADOPT it -- both sides create it and whichever loads first wins -- so this
-- fixture starts with one already parented.
local adopted = Instance.new('BindableEvent')
adopted.Name = 'OpenLuckyWheel'
adopted.Adopted = true
adopted.Parent = playerScripts
-- And something that is NOT a BindableEvent, for the refusal path.
local impostor = Instance.new('Folder')
impostor.Name = 'OpenImpostor'
impostor.Parent = playerScripts
-- The rail windows' open flags (RAIL_OVER_WINDOWS_20261007), read through
-- player:GetAttribute, and ONE ordered log of every bridge call and every
-- modal fired, so "closed, THEN opened" is an assertion and not a hope.
local flags, log = {}, {}
-- The two L4 bridges, as the L4 scripts create them: BindableFunctions whose
-- answer is true (opened) or false (refused). 'boom' makes the shop one throw.
-- Each close clears its window's flag before Invoke returns, as the real
-- setOpen(false) / closeModal() do.
local shopAsks, devAsks = {}, {}
local shopAnswer, devAnswer = true, true
local shopBridge = Instance.new('BindableFunction')
shopBridge.Name = 'ZyntraShopUIOpen'
shopBridge.Invoke = function(_, tab)
	table.insert(shopAsks, tostring(tab))
	table.insert(log, 'shop:' .. tostring(tab))
	if tab == 'close' then
		flags.ZyntraStoreOpen = nil
		return false
	end
	if shopAnswer == 'boom' then error('L4 build fault') end
	return shopAnswer
end
shopBridge.Parent = playerScripts
local devBridge = Instance.new('BindableFunction')
devBridge.Name = 'ZyntraDevUIOpen'
devBridge.Invoke = function(_, requested)
	table.insert(devAsks, tostring(requested))
	table.insert(log, 'dev:' .. tostring(requested))
	if requested == false then flags.DevPhoneOpen = nil end
	return devAnswer
end
devBridge.Parent = playerScripts
local dailyBridge = Instance.new('BindableFunction')
dailyBridge.Name = 'ZyntraDailyUIOpen'
dailyBridge.Invoke = function(_, request)
	table.insert(log, 'daily:' .. tostring(request))
	if request == 'close' then flags.DailyRewardsOpen = nil end
	return false
end
dailyBridge.Parent = playerScripts
local wheelBridge = Instance.new('BindableFunction')
wheelBridge.Name = 'CloseLuckyWheel'
wheelBridge.Invoke = function()
	table.insert(log, 'wheel:close')
	flags.LuckyWheelOpen = nil
	return false
end
wheelBridge.Parent = playerScripts
-- The fake's Parent setter only appends, so detaching the shop bridge (the
-- "not installed" case) is modelled by FindFirstChild honouring Parent.
function playerScripts:FindFirstChild(name)
	for _, child in ipairs(self.Children) do
		if child.Name == name and child.Parent == self then return child end
	end
	return nil
end
local player = {}
function player:GetAttribute(key)
	if key == 'InRound' then return inRound or nil end
	return flags[key]
end
function player:WaitForChild() return playerScripts end
local function modalBlocksStore() return queueBlocked end
-- `modalOpen` is a screen-owning modal that is NOT a rail window (re-entry);
-- any rail window's flag owns the screen as well.
function UIDevice.ScreenOwningModalOpen() return modalOpen or next(flags) ~= nil end
"""
    CHECKS += lua(binary, "routing", "\n".join([
        FAKES, rail_fakes, helpers, rail_block, routing_fakes,
        dev_block, opener_block, kiosk_block, activated_block, ROUTING_TESTS,
    ]))

    # ── 11a. MUSIC's switch, from the production block ──────────────────────────
    music_block = section("-- MUSIC, the rail's fifth button, is the lobby-music switch",
                          "\n-- The re-entry modal's two errors")
    check("FireServer" not in music_block and music_block.count("ShopData.toggleSetting(KEY)") == 1,
          "MUSIC has no send of its own: it presses ShopData's switch, the SETTINGS row's")
    music_fakes = r"""
local fired, attrs, watchers = {}, {}, {}
local modalOpen = false
local player = {UserId = 7}
function player:GetAttribute(key) return attrs[key] end
function player:GetAttributeChangedSignal(key)
	watchers[key] = watchers[key] or signal()
	return watchers[key]
end
local function setAttr(key, value)
	attrs[key] = value
	if watchers[key] then watchers[key]:Fire() end
end
attrs.ZyntraProfileLoaded = true
local Config = {Passes = {}, Products = {}, Items = {}, AccessibilitySettings = {
	{Key = 'LobbyMusicEnabled', Default = true}, {Key = 'DisableCaptions', Hidden = true}}}
local MarketplaceService = {PromptGamePassPurchaseFinished = signal(),
	PromptProductPurchaseFinished = signal()}
-- ShopData's last-send clock (os.clock) is stepped by hand.
local now = 100
local os = setmetatable({clock = function() return now end}, {__index = os})
function UIDevice.ScreenOwningModalOpen() return modalOpen end
--@@SHOPDATA_FIXTURE@@
-- The engine indexes children by name; the rail fake only lists them.
musicButton.SectionButtonContent = musicButton:FindFirstChild('SectionButtonContent')
musicButton.SectionButtonContent.SectionCaption = musicButton.SectionButtonContent:FindFirstChild('SectionCaption')
local visibleSignal = signal()
function musicButton:GetPropertyChangedSignal(name)
	assert(name == 'Visible', 'MUSIC only watches Visible')
	return visibleSignal
end
function musicButton:FireVisible() visibleSignal:Fire() end
""".replace("--@@SHOPDATA_FIXTURE@@", shopdata_fixture, 1)
    CHECKS += lua(binary, "music", "\n".join([
        FAKES, rail_fakes, helpers, rail_block, music_fakes, music_block, MUSIC_TESTS,
    ]))

    # ── 11b. the graft rule, from the production updateVisibility block ────
    chip_block = section("\t-- Lobby squares keep their centered artwork",
                         "\n\t-- The three icon-only buttons never show")
    CHECKS += lua(binary, "chipskin", "\n".join([
        FAKES, rail_fakes,
        "local function apply(touchDevInLevel, railButtons)",
        "\tlocal shopButton, openButton = railButtons[1], railButtons[2]",
        chip_block, "end", CHIPSKIN_TESTS,
    ]))

    # ── 12. the modal set, from the REAL UIDevice module ───────────────────
    begin = UIDEVICE.index("local SCREEN_OWNING_MODALS = {")
    modal_block = UIDEVICE[begin:UIDEVICE.index("\n-- ------", begin)]

    # ── 11c. the rail over its own windows, from the production blocks ─────
    guards_block = section("local TOUCH_MIN_TAP_HEIGHT = 44", "\n-- MUSIC, the rail's fifth button")
    visibility_head = section("local function updateVisibility()", "\tsyncRewardsIntro()")
    railmodal_fakes = r"""
local attributes = {}
local fakePlayer = {}
function fakePlayer:GetAttribute(key) return attributes[key] end
function fakePlayer:GetAttributeChangedSignal() return {Connect = function() end} end
function fakePlayer:FindFirstChild() return nil end
local workspace = {GetAttribute = function(_, key) return key == 'RoundActive' and true or nil end}
local Players = {LocalPlayer = fakePlayer}
local player = fakePlayer
local devAllowed = true
local UserInputService = {TouchEnabled = true}
local touchLayout = true
function UIDevice.Layout() return {IsTouch = touchLayout} end
function UIDevice.SetInteractive(element, visible)
	element.Visible = visible
	element.Active = visible
end
local gui = {DisplayOrder = 55}
local function railEntry(name) return {Name = name} end
local shopButton, openButton = railEntry('ZyntraShopButton'), railEntry('ZyntraOpenButton')
local rewardsButton, wheelButton = railEntry('ZyntraRewardsButton'), railEntry('ZyntraWheelButton')
local musicButton = railEntry('ZyntraMusicButton')
"""
    CHECKS += lua(binary, "railmodal", "\n".join([
        FAKES, railmodal_fakes, modal_block, guards_block, visibility_head, "end", RAILMODAL_TESTS,
    ]))
    modal_fakes = r"""
local attributes = {}
local watched = {}
local fakePlayer = {}
function fakePlayer:GetAttribute(key) return attributes[key] end
function fakePlayer:GetAttributeChangedSignal(key)
	table.insert(watched, key)
	return {Connect = function() end}
end
local Players = {LocalPlayer = fakePlayer}
"""
    CHECKS += lua(binary, "modals", "\n".join([
        FAKES, modal_fakes, modal_block, MODALS_TESTS,
    ]))

    # ── 13. the wall's buy bridge, from the production block ──────────────
    wall_block = SRC[SRC.index("-- ── the lobby SHOP wall's buy bridge"):]
    wall_fakes = r"""
local warnings, prompts, fired = {}, {}, {}
local function warn(message) table.insert(warnings, message) end
local playerScripts = Instance.new('Folder')
local attributes = {ZyntraProfileLoaded = true}
local player = {UserId = 7}
function player:WaitForChild() return playerScripts end
function player:GetAttribute(key) return attributes[key] end
function player:GetAttributeChangedSignal() return signal() end
local Config = {
	Passes = {Supporter = {Id = 11}},
	Products = {Tokens4 = {Id = 22}, EmergencyReentry = {Id = 33}, Unconfigured = {Id = 0}},
	Items = {SpeedPotion = {Name = 'Speed Potion', TokenCost = 3}},
}
local MarketplaceService = {PromptGamePassPurchaseFinished = signal(),
	PromptProductPurchaseFinished = signal()}
function MarketplaceService:PromptGamePassPurchase(who, id)
	assert(who == player, 'prompts the local player')
	table.insert(prompts, 'pass:' .. id)
end
function MarketplaceService:PromptProductPurchase(who, id)
	assert(who == player, 'prompts the local player')
	table.insert(prompts, 'product:' .. id)
end
--@@SHOPDATA_FIXTURE@@
require(shopDataModule).start() -- "Zyntra Shop L4" starts it at boot
"""
    CHECKS += lua(binary, "wallbuy", "\n".join([
        FAKES, rail_fakes, wall_fakes.replace("--@@SHOPDATA_FIXTURE@@", shopdata_fixture, 1),
        wall_block, WALL_BUY_TESTS,
    ]))

    print(f"ok  {CHECKS} checks: no terminal, 5-button rail with MUSIC's switch,"
          f" every shop entry (RECORDS and SETTINGS included) routed to the L4 shop"
          f" ({', '.join(f'{k} {v}' for k, v in LANES.items())})")
    sys.exit(0)


if __name__ == "__main__":
    main()
