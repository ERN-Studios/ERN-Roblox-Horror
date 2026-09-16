"""The Zyntra terminal: content tiers, the shop's list+detail split, FIELD
SUPPLIES, the mounted-page tab rule, and the square HUD button.

Trello #68 gave this terminal three content tiers (phone / tablet / pointer)
because 67.7% of this game's audience plays on touch. Trello #102 made the
pointer composition bigger and turned the Shop tab into a list + detail browser,
#85 put two token consumables on the Upgrades tab, and the owner's 2026-09-16
correction took the circular treatment back off the HUD shop button.

Four things have to stay true and none of them is visible from a screenshot:

  * the POINTER tier is still the authored card, to the pixel (330px upgrade
    card, 76px product icon, copyLeft 104 / copyInset 118),
  * no tier draws type under 11px or a tap target under 44 on touch, and TOUCH
    NEVER GETS THE SECOND PANE,
  * a FIELD SUPPLIES button spends tokens through ZyntraAction "BuyItem" with the
    contract's payload, and says SAVING... exactly while it cannot be pressed,
  * REWARDS and NOTES exist as tabs only where their page module does.

The tier tables and the height expressions are EXTRACTED from
ZyntraStore.LocalScript.lua so the arithmetic mirror cannot drift. Everything
below section 4 goes further and RUNS the production Lua under the real luau
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

PHONE, TABLET, POINTER = 0, 1, 2
TOUCH_TAP, POINTER_TAP = 44, 32

CHECKS = 0


def check(condition, message):
    global CHECKS
    CHECKS += 1
    assert condition, message


def section(start: str, stop: str) -> str:
    """The production Lua between two literal markers, start inclusive."""
    begin = SRC.index(start)
    return SRC[begin:SRC.index(stop, begin)]


def tier_tables() -> list[list[dict[str, int]]]:
    """The two `local face = ({...})[...]` literals, upgrades first then shop."""
    blocks = re.findall(r"local face = \(\{(.*?)\}\)\[", SRC, re.S)
    assert len(blocks) == 2, f"expected 2 tier tables, found {len(blocks)}"
    tables = []
    for block in blocks:
        rows = [dict((k, int(v)) for k, v in re.findall(r"(\w+) = (\d+)", row))
                for row in re.findall(r"\{([^{}]*)\}", block)]
        assert len(rows) == 3, f"expected 3 tiers, found {len(rows)}"
        tables.append(rows)
    return tables


UPGRADE, SHOP = tier_tables()

# The mirror is only worth anything while the source still computes it this way.
check(SRC.count("})[(fit.Compact and fit.Touch) and 1 or (fit.Touch and 2 or 3)]") == 2,
      "both pages still pick their tier from the same expression")
check("""	local descTop = face.Pad + titleHeight + face.GapTitle
	local pctTop = descTop + descHeight + face.GapDesc
	local cellHeight = pctTop + face.PctBox + face.LevelBox + face.GapLevel
		+ buttonHeight + face.Pad""" in SRC, "the upgrade stack is unchanged")
check("\tlocal cellHeight = bodyBottom + face.Lead + buyHeight + face.Foot\n" in SRC,
      "the shop cell height is unchanged")
check("\tlocal bodyBottom = face.IconTop + face.Icon\n" in SRC, "icon bottom unchanged")
check("\tlocal copyLeft = face.Pad * 2 + face.Icon\n\tlocal copyInset = copyLeft + face.Pad\n"
      in SRC, "the copy column is still derived from the icon")


def upgrade_card(tier: int, tap: int, title: int = 0, desc: int = 0) -> dict[str, int]:
    """One upgrade cell: the measured stack, and where each child lands in it."""
    f = UPGRADE[tier]
    title = max(f["TitleBox"], title)
    desc = max(f["DescBox"], desc)
    button = max(tap, f["Button"])
    desc_top = f["Pad"] + title + f["GapTitle"]
    pct_top = desc_top + desc + f["GapDesc"]
    height = pct_top + f["PctBox"] + f["LevelBox"] + f["GapLevel"] + button + f["Pad"]
    return {"Height": height, "Title": f["Pad"], "Desc": desc_top, "Pct": pct_top,
            "Level": pct_top + f["PctBox"], "Button": button,
            "ButtonOffset": -(button + f["Pad"]), "Inset": -f["Pad"] * 2}


def shop_cell(tier: int, tap: int, top: int = 28, title: int = 0, desc: int = 0) -> dict[str, int]:
    f = SHOP[tier]
    buy = max(tap, 38)
    icon_bottom = f["IconTop"] + f["Icon"]
    body = max(icon_bottom, top + max(22, title) + 6 + max(14, desc))
    return {"Height": body + f["Lead"] + buy + f["Foot"], "Buy": buy,
            "IconBottom": icon_bottom, "CopyLeft": f["Pad"] * 2 + f["Icon"],
            "CopyInset": f["Pad"] * 3 + f["Icon"], "Inset": -f["Pad"] * 2}


# ── 1. THE POINTER TIER IS THE AUTHORED CARD, to the pixel ──────────────────
# 18 pad + 34 title + 8 + 72 desc + 10 + 80 readout + 24 level + 18 + 48 + 18.
pc = upgrade_card(POINTER, POINTER_TAP)
check(pc["Height"] == 330, f"pointer upgrade card is 330px, got {pc}")
check((pc["Title"], pc["Desc"], pc["Pct"], pc["Level"]) == (18, 60, 142, 222), pc)
check((pc["Button"], pc["ButtonOffset"], pc["Inset"]) == (48, -66, -36), pc)

shop_pc = shop_cell(POINTER, POINTER_TAP)
check(SHOP[POINTER]["Icon"] == 76, SHOP[POINTER])
check((shop_pc["CopyLeft"], shop_pc["CopyInset"]) == (104, 118), shop_pc)
check((shop_pc["IconBottom"], shop_pc["Buy"], shop_pc["Inset"]) == (94, 38, -28), shop_pc)
# bodyBottom + 16 + 38 + 12, and 94 while the copy is shorter than the icon.
check(shop_pc["Height"] == 94 + 16 + 38 + 12 == 160, shop_pc)
check(shop_cell(POINTER, POINTER_TAP, desc=56)["Height"] == 112 + 16 + 38 + 12, "PC stack")

# ── 2. THE TOUCH TIERS SHRINK, and stay measurable ─────────────────────────
# 956x440 landscape phone: the page is 201px tall and the authored card is 330.
phone = upgrade_card(PHONE, TOUCH_TAP)
check(phone["Height"] == 210, phone)
check(phone["Height"] < 260, phone)
f = UPGRADE[PHONE]
check(phone["Height"] >= (f["TitleBox"] + f["DescBox"] + f["PctBox"] + f["LevelBox"]
                          + max(TOUCH_TAP, f["Button"])), phone)
check(upgrade_card(PHONE, TOUCH_TAP, desc=42)["Height"] == 220, "measured, not clamped")

tablet = upgrade_card(TABLET, TOUCH_TAP)
check(tablet["Height"] == 246, tablet)
check(phone["Height"] < tablet["Height"] < pc["Height"], (phone, tablet, pc))

# ── 3. EVERY TOUCH TARGET CLEARS 44, and no type is drawn under 11 ─────────
for tier in (PHONE, TABLET, POINTER):
    check(upgrade_card(tier, TOUCH_TAP)["Button"] >= 44, UPGRADE[tier])
    check(shop_cell(tier, TOUCH_TAP)["Buy"] >= 44, SHOP[tier])
    for key in ("Title", "Desc", "Level"):
        check(UPGRADE[tier][key] >= 11, (tier, key, UPGRADE[tier]))
    check(UPGRADE[tier]["Pct"] >= 11 and SHOP[tier]["Title"] >= 11, tier)
    check(SHOP[tier]["Desc"] >= 11, SHOP[tier])
    cell = shop_cell(tier, TOUCH_TAP)
    check(cell["Height"] >= cell["IconBottom"] + cell["Buy"], cell)

# The phone shop card: a 52px icon gives the copy 36 more pixels of column.
check(SHOP[PHONE]["Icon"] == 52 and SHOP[TABLET]["Icon"] == 64, SHOP)
check(shop_cell(PHONE, TOUCH_TAP)["CopyInset"] == 82, SHOP[PHONE])
check(shop_cell(PHONE, TOUCH_TAP, desc=39)["Height"] == 157, "956x440 shop cell")

# ── 4. THE PANEL IS BIGGER, and still clamped ──────────────────────────────
design = re.search(r"local STORE_DESIGN_WIDTH, STORE_DESIGN_HEIGHT = (\d+), (\d+)", SRC)
check(design is not None, "the design size is still one named pair")
DESIGN_W, DESIGN_H = int(design.group(1)), int(design.group(2))
check((DESIGN_W, DESIGN_H) == (1180, 760), f"card 102 design size, got {DESIGN_W}x{DESIGN_H}")
check(f"main.Size = UDim2.fromOffset({DESIGN_W}, {DESIGN_H})" in SRC,
      "the frame's authored size matches the design size it is clamped to")
# The clamp is what keeps a laptop -- and every handheld -- inside its viewport.
check("math.min(STORE_DESIGN_WIDTH, area.Width)" in SRC, "width still clamps to the viewport")
check("math.min(STORE_DESIGN_HEIGHT, area.Height)" in SRC, "height still clamps")
check("local compact = width < 640 or height < 430" in SRC,
      "the compact rung is unchanged, so the touch tiers keep their arithmetic")

# ── 5. THE SQUARE HUD BUTTON (#88 correction) ──────────────────────────────
check("SHOP_ICON_CIRCLE" not in SRC, "the circular shop-button block is gone")
check("UDim.new(1, 0)" not in SRC, "no disc corner radius survives anywhere in the store")
check("TweenService" not in SRC, "the breathing ring's tween is gone with it")
check("shopButtonSections.Size" not in SRC, "the 8px disc inset is gone")
rail = section("for _, entry in ipairs({openButton, shopButton, musicButton}) do",
               "-- C5_ZYNTRA_OPEN_BUTTON_20260829")

# ── 5b. THE CONTRACT KEYS the two supplies cards will report ───────────────
# makeUpgradeCard names its frame `titleText:match("^%a+")`, and the terminal's
# card contract -- which UIRegression's fit matrix looks cards up by -- uses that
# name. The keys are therefore decided by ZyntraConfig's item names, which is
# worth pinning: a rename in the config silently renames a contract key.
check('string.upper(tostring(item.Name or key))' in SRC,
      "the supplies title is the configured name, upper-cased")
CONFIG = (ROOT / "ReplicatedStorage" / "ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")
items = re.search(r"\n\tItems = \{(.*?)\n\t\},\n", CONFIG, re.S)
check(items is not None, "ZyntraConfig carries the Items table the supplies read")
names = dict(re.findall(r'(\w+) = \{\s*\n\s*Name = "([^"]+)"', items.group(1)))
check(names.get("SpeedPotion") == "Speed Potion", names)
check(names.get("RouteMarker") == "Route Marker Pack", names)
for key, expected in (("SpeedPotion", "SPEED"), ("RouteMarker", "ROUTE")):
    check(re.match(r"[A-Za-z]+", names[key].upper()).group(0) == expected,
          f"{key} reports contract card key {expected}")
check("if entry == shopButton" not in rail, "nothing in the rail singles out one button")
check(rail.count("SquareSectionBorder") == 1, "one hover border, built once for all three")


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

TAB_TESTS = r"""
local function fakeStorage(present)
	return {FindFirstChild = function(_, name)
		if present[name] then return {Name = name} end
		return nil
	end}
end
local both = buildTabs(fakeStorage({ZyntraDailyRewardsPage = true, ZyntraFieldNotesPage = true}), false)
expect(table.concat(both, ','), 'Upgrades,Shop,Rewards,Notes,Donate,Colors,Settings',
	'both page modules present')
local neither = buildTabs(fakeStorage({}), false)
expect(table.concat(neither, ','), 'Upgrades,Shop,Donate,Colors,Settings',
	'neither module present -- the terminal is exactly what it was')
local rewardsOnly = buildTabs(fakeStorage({ZyntraDailyRewardsPage = true}), false)
expect(table.concat(rewardsOnly, ','), 'Upgrades,Shop,Rewards,Donate,Colors,Settings',
	'one module present builds one tab')
local notesOnly = buildTabs(fakeStorage({ZyntraFieldNotesPage = true}), false)
expect(table.concat(notesOnly, ','), 'Upgrades,Shop,Notes,Donate,Colors,Settings',
	'and the other builds the other')
local dev = buildTabs(fakeStorage({ZyntraDailyRewardsPage = true, ZyntraFieldNotesPage = true}), true)
expect(table.concat(dev, ','), 'Upgrades,Shop,Rewards,Notes,Donate,Colors,Settings,Dev',
	'DEV is still last, after the mounted pages')
expect(buildTabs(fakeStorage({}), true)[6], 'Dev', 'DEV is still last when no page mounts')
-- The order is AUTHORED, not alphabetical: the tab bar breaks LayoutOrder ties
-- by name and this list is the only thing that states the intent.
expect(both[1], 'Upgrades', 'Upgrades first')
expect(both[7], 'Settings', 'Settings last before DEV')
ok(table.find(both, 'Rewards') < table.find(both, 'Donate'),
	'Rewards sits with the equipment pages, ahead of Donate')
print('tabs|' .. checks)
"""

SUPPLIES_TESTS = r"""
expect(#rows, 2, 'both configured supplies built a card')
expect(cards[1].Title.Text, 'SPEED POTION', 'the title is the configured name, upper-cased')
expect(cards[2].Title.Text, 'ROUTE MARKER PACK', 'and so is the second')
expect(cards[1].Desc.Text, Config.Items.SpeedPotion.Description, 'description comes from config')
expect(cards[2].Desc.Text, Config.Items.RouteMarker.Description, 'and for the marker pack')
expect(cards[1].Current.Text, '+10%', 'the potion headline is its configured multiplier')
expect(cards[2].Current.Text, 'x3', 'the marker headline is its configured pack size')
expect(cards[1].Spend.Text, '3 TOKENS  //  BUY', 'the potion costs what config says')
expect(cards[2].Spend.Text, '2 TOKENS  //  BUY', 'and so does the marker pack')
expect(cards[1].Level.Text, '0 STORED', 'the potion readout before any profile')
expect(cards[2].Level.Text, '0 MARKERS', 'the marker readout before any profile')
expect(cards[1].Order, 1, 'the potion is the first cell of its group')
expect(cards[2].Order, 2, 'the pack is the second')
expect(cards[1].Parent, section, 'the cards live in the FIELD SUPPLIES section')
expect(heading.Text, 'FIELD SUPPLIES', 'the group is named on the page')
expect(heading.LayoutOrder, 2, 'the heading sits between the two groups')
expect(section.LayoutOrder, 3, 'and the supplies section under it')

-- ---- the purchase --------------------------------------------------------
cards[1].Spend.Activated:Fire()
expect(#fired, 1, 'pressing BUY fires exactly one action')
expect(fired[1].Action, 'BuyItem', 'and it is the contract action')
expect(fired[1].Payload.Key, 'SpeedPotion', 'with the contract payload key')
expect(cards[1].Spend.Text, 'SAVING...', 'the button says what it is doing')
expect(cards[1].Spend.Active, false, 'and cannot be pressed again while it does it')
cards[1].Spend.Activated:Fire()
expect(#fired, 1, 'a second press during the write spends nothing')
productPurchase.SpeedPotion()
expect(#fired, 1, 'the wall bridge shares the same pending latch')
expect(cards[2].Spend.Active, true, 'the other supply is untouched by it')

-- ---- the profile push clears it -----------------------------------------
profile = {Items = {SpeedPotion = 4, RouteMarker = 2}}
for _, subscriber in ipairs(pageMounts.Subscribers) do subscriber(profile) end
expect(cards[1].Spend.Text, '3 TOKENS  //  BUY', 'the push clears SAVING...')
expect(cards[1].Spend.Active, true, 'and gives the button back')
expect(cards[1].Level.Text, '4 STORED', 'the readout is the stored count')
expect(cards[2].Level.Text, '2 MARKERS', 'and the marker count')

-- A profile with no Items table at all must read zero, not crash or blank.
profile = {}
for _, subscriber in ipairs(pageMounts.Subscribers) do subscriber(profile) end
expect(cards[1].Level.Text, '0 STORED', 'a profile without Items reads zero')

-- ---- a write that never answers -----------------------------------------
productPurchase.RouteMarker()
expect(cards[2].Spend.Text, 'SAVING...', 'the marker pack latches too')
expect(#delayed, 2, 'each press that actually fired armed a timeout, the blocked one did not')
expect(delayed[#delayed].Seconds, 6, 'the floor under a silent server is 6s')
delayed[#delayed].Fn()
expect(cards[2].Spend.Text, '2 TOKENS  //  BUY', 'the timeout gives the button back')
expect(cards[2].Spend.Active, true, 'and returns it to the input stack')
-- A stale timeout from an earlier, already-cleared press must do nothing.
cards[1].Spend.Activated:Fire()
expect(cards[1].Spend.Text, 'SAVING...', 'fresh press latches')
delayed[1].Fn()
expect(cards[1].Spend.Text, 'SAVING...', 'a stale timeout cannot clear a newer press')

-- ---- the two grids share one cell ---------------------------------------
upgradeGrid.CellSize = {SX = 0.5, OX = -8, SY = 0, OY = 246}
for _, hook in ipairs(layoutHooks) do hook({Compact = true}) end
expect(grid.CellSize.OY, 246, 'the supplies grid takes the cell the upgrades hook wrote')
expect(heading.TextSize, 12, 'the heading shrinks on a compact panel')
for _, hook in ipairs(layoutHooks) do hook({Compact = false}) end
expect(heading.TextSize, 14, 'and grows back on a pointer panel')

-- ---- the optional crate art ---------------------------------------------
expect(rows[1].Art, nil, 'no IconId means no ImageLabel at all')
expect(rows[2].Art, nil, 'and the same for the marker pack')
print('supplies|' .. checks)
"""

SUPPLIES_ABSENT_TESTS = r"""
expect(#rows, 0, 'no Items table means no FIELD SUPPLIES cards')
expect(heading, nil, 'and no group heading')
expect(#layoutHooks, 0, 'and no layout hook of its own')
expect(#pageMounts.Subscribers, 0, 'and nothing subscribed to the profile')
print('supplies-absent|' .. checks)
"""

SHOP_TESTS = r"""
local function run(fit)
	shopGrid.CellSize = nil
	detail = nil
	for _, hook in ipairs(layoutHooks) do hook(fit) end
end
local function fit(width, height, touch, compact)
	return {ContentWidth = width, ContentHeight = height, Touch = touch,
		Compact = compact, Tap = touch and 44 or 32}
end

-- ---- POINTER, 1180 design: the split ------------------------------------
run(fit(1140, 540, false, false))
ok(detail ~= nil, 'the pointer terminal hands the detail pane its geometry')
expect(detail.TwoPane, true, '1140px of content splits into two panes')
expect(detail.Left, 531, 'the pane starts after the list and a 14px gutter')
expect(detail.Width, 609, 'and takes the rest of the content box')
expect(shopScroll.Size.OX, 517, 'the list keeps 46% of the box')
expect(shopScroll.Size.OY, 540, 'and the full content height')
ok(detail.Width > shopScroll.Size.OX, 'the detail pane is the wider of the two')
ok(shopScroll.Size.OX >= 343, 'the list column is never narrower than a phone card')
expect(detail.Left + detail.Width, 1140, 'the two panes and the gutter fill the box exactly')
for _, entry in ipairs(productCards) do
	expect(entry.Pick.Active, true, 'a row is a pick target while the pane exists')
end
expect(shopGrid.CellSize.SX, 1, 'beside a detail pane the list is one column')

-- ---- the breakpoint ------------------------------------------------------
run(fit(760, 520, false, false))
expect(detail.TwoPane, true, '760 is the floor and it splits')
run(fit(759, 520, false, false))
expect(detail.TwoPane, false, 'one pixel under it does not')
expect(shopScroll.Size.SX, 1, 'and the list takes the whole page back')
expect(shopScroll.Size.SY, 1, 'on both axes')
for _, entry in ipairs(productCards) do
	expect(entry.Pick.Active, false, 'with no pane to fill, a row is not a pick target')
end

-- ---- TOUCH NEVER SPLITS, however wide ------------------------------------
run(fit(1400, 700, true, false))
expect(detail.TwoPane, false, 'a tablet as wide as a desktop keeps the card list')
run(fit(956, 201, true, true))
expect(detail.TwoPane, false, 'and so does a landscape phone')
expect(shopScroll.Size.SX, 1, 'the phone list is the whole page')

-- ---- the tap floor holds in every tier -----------------------------------
for _, case in ipairs({fit(360, 300, true, true), fit(760, 500, true, false),
	fit(1140, 540, false, false)}) do
	run(case)
	for _, entry in ipairs(productCards) do
		ok(entry.Buy.Size.OY >= (case.Touch and 44 or 38),
			'the buy action is drawn at the tap floor')
		ok(entry.Heading.TextSize >= 11, 'no product name under 11px')
		ok(entry.Desc.TextSize >= 11, 'no product description under 11px')
		ok(entry.Icon.Size.OX >= 52, 'the icon stays recognisable')
	end
end

-- ---- the cell is measured from the LIST, not the page --------------------
run(fit(1140, 540, false, false))
local splitCell = shopGrid.CellSize
run(fit(517, 540, false, false))
expect(shopGrid.CellSize.SX, splitCell.SX,
	'a one-pane page the width of the list column lays its cards out the same way')
print('shop|' .. checks)
"""

RAIL_TESTS = r"""
local corners = {}
for _, entry in ipairs({openButton, shopButton, musicButton}) do
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
	expect(entry:GetAttribute('SquareSectionButton'), true, 'all three are square-section buttons')
	for _, child in ipairs(entry.Children) do
		if child.ClassName == 'UIStroke' and child.Name == 'SquareSectionBorder' then
			caption = child
			expect(child.Transparency, 0.22, 'the hover border rests at the same transparency')
		end
	end
	ok(caption ~= nil, 'and all three carry the same named hover border')
end
expect(corners[1], corners[2], 'the shop button has its neighbours corner')
expect(corners[2], corners[3], 'and so does the music button')
expect(corners[1], '0:7', 'which is the square 7px corner button() draws')
-- The hover is the only thing that writes the border, and it behaves the same
-- on all three: the card-88 ring wrote the shop button's stroke from a tween
-- as well, so "one writer per property" is the thing worth proving.
local function borderOf(entry)
	for _, child in ipairs(entry.Children) do
		if child.Name == 'SquareSectionBorder' then return child end
	end
	return nil
end
for _, entry in ipairs({openButton, shopButton, musicButton}) do
	local border = borderOf(entry)
	-- MUSIC ships Active = false (it is a readout, not a control), so it is
	-- lifted here: the point is that the HOVER RULE is one rule for all three,
	-- not that all three are pressable.
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
    return int(count)


def main() -> None:
    global CHECKS
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")

    # ── 6. the tab set, from the production block ──────────────────────────
    tabs = section("local TERMINAL_PAGE_MODULES = {",
                   "\nfor order, name in ipairs(tabNames) do")
    tabs = tabs[:tabs.index('if devAllowed then table.insert(tabNames, "Dev") end')
                + len('if devAllowed then table.insert(tabNames, "Dev") end')]
    CHECKS += lua(binary, "tabs", "\n".join([
        FAKES,
        "local function buildTabs(ReplicatedStorage, devAllowed)",
        tabs,
        "\treturn tabNames\nend",
        TAB_TESTS,
    ]))

    # ── 7. FIELD SUPPLIES, from the production block ───────────────────────
    supplies = section('if type(Config.Items) == "table" then',
                       "\nlocal supportTotalLabel = label(")
    supplies_fakes = r"""
local layoutHooks, pageMounts = {}, {Handles = {}, Subscribers = {}}
local productPurchase = {}
local profile = nil
local upgradeScroll = object('ScrollingFrame')
local upgradeGrid = {CellSize = {SX = 0.5, OX = -8, SY = 0, OY = 330}}
local fired = {}
local actionRemote = {FireServer = function(_, action, payload)
	table.insert(fired, {Action = action, Payload = payload})
end}
local cards = {}
local function label(parent, text, size, position, textSize, color, font)
	local obj = object('TextLabel')
	obj.Parent, obj.Text, obj.Size, obj.Position = parent, text, size, position
	obj.TextSize, obj.TextColor3, obj.Font = textSize, color, font
	return obj
end
-- The real makeUpgradeCard: same five parts, same registration surface.
local function makeUpgradeCard(parent, order, titleText, description)
	local frame = object('Frame')
	local card = {
		Parent = parent, Order = order, Frame = frame,
		-- Sized and positioned the way the Upgrades hook leaves a POINTER card,
		-- because the supplies hook reads those numbers back rather than
		-- restating them.
		Title = {Text = titleText, Size = UDim2.new(1, -36, 0, 34),
			Position = UDim2.fromOffset(18, 18)},
		Desc = {Text = description}, Current = {Text = '+0%'}, Level = {Text = 'LEVEL 0'},
		Spend = object('TextButton'),
	}
	card.Spend.Text = 'SPEND'
	card.Spend.Parent = frame
	table.insert(cards, card)
	return card
end
"""
    grab = ("\nlocal heading, section, grid, rows = nil, nil, nil, {}\n"
            "local function build()\n"
            + re.sub(r"^\tlocal (heading|section|grid|rows) = ", r"\t\1 = ",
                     supplies.replace("\n\tlocal heading", "\n\theading")
                     .replace("\n\tlocal section", "\n\tsection")
                     .replace("\n\tlocal grid", "\n\tgrid")
                     .replace("\n\tlocal rows = {}", "\n\trows = {}"), flags=re.M)
            + "\nend\nbuild()\n")
    CHECKS += lua(binary, "supplies", "\n".join([
        FAKES, supplies_fakes,
        "local Config = {Items = {"
        "SpeedPotion = {Name = 'Speed Potion', TokenCost = 3, DurationSeconds = 6,"
        " SpeedMultiplier = 1.10, MaxUsesPerRound = 1,"
        " Description = 'Drink for a short burst of speed. One use per run.'},"
        "RouteMarker = {Name = 'Route Marker Pack', TokenCost = 2, PackSize = 3,"
        " MaxActive = 3, Description = 'Three markers your team can see. They clear at round end.'},"
        "}}",
        grab, SUPPLIES_TESTS,
    ]))
    CHECKS += lua(binary, "supplies-absent", "\n".join([
        FAKES, supplies_fakes, "local Config = {}", grab, SUPPLIES_ABSENT_TESTS,
    ]))

    # ── 8. the Shop hook, from the production block ────────────────────────
    hook = section("table.insert(layoutHooks, function(fit)\n\t-- THE SAME THREE TIERS",
                   "\nlocal function makeProductCard(")
    shop_fakes = r"""
local layoutHooks = {}
local shopScroll, shopGrid = object('ScrollingFrame'), {}
local detail = nil
local shopDetail = {Order = {}, Items = {}}
shopDetail.apply = function(_fit, twoPane, left, width)
	detail = {TwoPane = twoPane, Left = left, Width = width}
end
local productCards = {}
for _, name in ipairs({'Zyntra Supporter', 'Advanced Equipment', '4 Research Tokens',
	'20 Research Tokens', 'Emergency Re-entry', 'Glowstick Customizer'}) do
	table.insert(productCards, {
		Heading = {Text = name, Font = 'GothamBold', TextSize = 18},
		Desc = {Text = 'A short description of the item, two sentences long.',
			Font = 'GothamMedium', TextSize = 12},
		Buy = {Size = {OY = 0}, Position = {}}, Icon = {Size = {OX = 0}, Position = {}},
		Tag = nil, Top = 28, Pick = object('TextButton'),
	})
end
"""
    CHECKS += lua(binary, "shop", "\n".join([FAKES, shop_fakes, hook, SHOP_TESTS]))

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

    print(f"ok  {CHECKS} checks: terminal {DESIGN_W}x{DESIGN_H},"
          f" upgrade card {phone['Height']}/{tablet['Height']}/{pc['Height']}px"
          f" (phone/tablet/pointer), shop icon"
          f" {SHOP[PHONE]['Icon']}/{SHOP[TABLET]['Icon']}/{SHOP[POINTER]['Icon']}px,"
          f" list+detail at >=760 pointer only")
    sys.exit(0)


if __name__ == "__main__":
    main()
