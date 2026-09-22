"""The Zyntra terminal and its lobby rail: content tiers, the shop's list+detail
split, FIELD SUPPLIES, the mounted-page tab rule, and the five square HUD
buttons.

Trello #68 gave this terminal three content tiers (phone / tablet / pointer)
because 67.7% of this game's audience plays on touch. Trello #102 made the
pointer composition bigger and turned the Shop tab into a list + detail browser,
#85 put two token consumables on the Upgrades tab, and the owner's 2026-09-16
correction took the circular treatment back off the HUD shop button. Cards #103
and #104 then took Daily Rewards OUT of the terminal and gave it and the new
Lucky Wheel a rail button each, so the rail went from three buttons to five.

Seven things have to stay true and none of them is visible from a screenshot:

  * the POINTER tier is still the authored card, to the pixel (330px upgrade
    card, 76px product icon, copyLeft 104 / copyInset 118),
  * no tier draws type under 11px or a tap target under 44 on touch, and TOUCH
    NEVER GETS THE SECOND PANE,
  * a FIELD SUPPLIES button spends tokens through ZyntraAction "BuyItem" with the
    contract's payload, and says SAVING... exactly while it cannot be pressed,
  * no page module adds a tab today (NOTES left with Field Notes), and REWARDS does NOT
    exist as a tab even though its page module is still in ReplicatedStorage,
  * the rail is five buttons in one drawn order, built by one loop over one list,
  * layoutSquareSections fits them at 64 / 56 / 52px and then in two columns
    rather than clipping one off the bottom, and dodges the thumbstick glyph
    against the rail's WHOLE footprint,
  * REWARDS and WHEEL fire PlayerScripts.OpenDailyRewards / OpenLuckyWheel and
    refuse in a round, under a queue and under any screen-owning modal -- and
    every "Rewards" caller reaches the modal rather than falling back to Shop.

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
UIDEVICE = (ROOT / "ReplicatedStorage" / "UIDevice.ModuleScript.lua").read_text(encoding="utf-8")

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
check(SRC.count("ipairs(railButtons)") == 3,
      f"all three rail loops read that list, found {SRC.count('ipairs(railButtons)')}")
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
-- REWARDS IS GONE FROM THE TERMINAL (card #104). The page module is still in
-- ReplicatedStorage -- the standalone Daily Rewards modal mounts it -- so the
-- interesting case is precisely "the module is present and the terminal still
-- does not build a tab for it". A second mount here would mean two profile
-- subscriptions and two claim buttons for one server-side claim.
local both = buildTabs(fakeStorage({ZyntraDailyRewardsPage = true, ZyntraFieldNotesPage = true}), false)
expect(table.concat(both, ','), 'Upgrades,Shop,Donate,Colors,Settings',
	'neither page module present brings a tab: Rewards has its own modal, NOTES left with Field Notes (FIELD_NOTES_REMOVED_20260922)')
expect(table.find(both, 'Rewards'), nil, 'there is no Rewards tab at all')
expect(table.find(both, 'Notes'), nil, 'and no Notes tab, even with a stale page module in the place')
local neither = buildTabs(fakeStorage({}), false)
expect(table.concat(neither, ','), 'Upgrades,Shop,Donate,Colors,Settings',
	'no module present -- the terminal is the five authored tabs')
local dev = buildTabs(fakeStorage({ZyntraDailyRewardsPage = true, ZyntraFieldNotesPage = true}), true)
expect(table.concat(dev, ','), 'Upgrades,Shop,Donate,Colors,Settings,Dev',
	'DEV is still last')
expect(buildTabs(fakeStorage({}), true)[6], 'Dev', 'DEV is still last when no page mounts')
-- The order is AUTHORED, not alphabetical: the tab bar breaks LayoutOrder ties
-- by name and this list is the only thing that states the intent.
expect(both[1], 'Upgrades', 'Upgrades first')
expect(both[5], 'Settings', 'Settings last before DEV')
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
	layoutSquareSections({Safe = safe, IsTouch = isTouch},
		shopButton, openButton, rewardsButton, wheelButton, musicButton)
	local placed = {}
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
local rows = 0
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
	end
end
ok(rows > 400, 'the sweep covered ' .. rows .. ' safe heights on both form factors')
expect(short, 0, 'every one of them placed all five buttons')
expect(tiny, 0, 'and never drew a square under the 44px tap floor')
expect(uneven, 0, 'and never mixed two sizes in one rail')
expect(notSquare, 0, 'and never drew a rail button that was not square')
expect(collide, 0, 'and never overlapped two rail buttons')
expect(spill, 0, 'and never ran the rail past the safe height it was given')
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
print('layout|' .. checks)
"""

# ── 11. THE RAIL'S TWO NEW DESTINATIONS, running the real routing ──────────
# The rail button, the terminal opener and the kiosk plaque all have to reach the
# same place, and REWARDS no longer has a tab to fall back on: an unrouted
# "Rewards" would silently open the SHOP tab, which is a defect with no symptom.
ROUTING_TESTS = r"""
local playerScripts = player:WaitForChild('PlayerScripts')
local rewardsEvent = playerScripts:FindFirstChild('OpenDailyRewards')
local wheelEvent = playerScripts:FindFirstChild('OpenLuckyWheel')
local terminalEvent = playerScripts:FindFirstChild('ZyntraOpenTerminal')
ok(rewardsEvent ~= nil, 'PlayerScripts.OpenDailyRewards exists')
ok(wheelEvent ~= nil, 'PlayerScripts.OpenLuckyWheel exists')
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
rewardsEvent.Event:Connect(function() fired.Rewards += 1 end)
wheelEvent.Event:Connect(function() fired.Wheel += 1 end)
local function reset()
	fired.Rewards, fired.Wheel = 0, 0
	opened = {}
	inRound, queueBlocked, modalOpen = false, false, false
end

-- ---- the two rail buttons ------------------------------------------------
reset()
rewardsButton.Activated:Fire({UserInputType = 'MouseButton1'})
expect(fired.Rewards, 1, 'REWARDS fires PlayerScripts.OpenDailyRewards')
expect(fired.Wheel, 0, 'and nothing else')
expect(#opened, 0, 'and never opens the terminal')
reset()
wheelButton.Activated:Fire({UserInputType = 'MouseButton1'})
expect(fired.Wheel, 1, 'WHEEL fires PlayerScripts.OpenLuckyWheel')
expect(fired.Rewards, 0, 'and nothing else')
expect(#opened, 0, 'and never opens the terminal')
reset()
shopButton.Activated:Fire({UserInputType = 'MouseButton1'})
expect(#opened, 1, 'SHOPS still opens the terminal')
expect(opened[1], 'Shop', 'on its own tab')
expect(fired.Rewards + fired.Wheel, 0, 'and raises no lobby modal')

-- ---- the three refusals, on BOTH buttons and on the plaque --------------
for _, case in ipairs({'inRound', 'queue', 'modal'}) do
	reset()
	if case == 'inRound' then inRound = true
	elseif case == 'queue' then queueBlocked = true
	else modalOpen = true end
	rewardsButton.Activated:Fire()
	wheelButton.Activated:Fire()
	terminalEvent:Fire('Rewards')
	rewardsPrompt.Triggered:Fire(player)
	expect(fired.Rewards, 0, 'no rewards modal is raised while ' .. case)
	expect(fired.Wheel, 0, 'and no wheel modal while ' .. case)
end

-- ---- REWARDS IS NOT A TAB ANY MORE --------------------------------------
reset()
terminalEvent:Fire('Rewards')
expect(fired.Rewards, 1, 'ZyntraOpenTerminal "Rewards" reaches the standalone modal')
expect(#opened, 0, 'and does NOT fall through to the Shop tab')
reset()
terminalEvent:Fire('Notes')
expect(#opened, 1, 'a tab that still exists still opens the terminal')
expect(opened[1], 'Notes', 'on the tab that was asked for')
reset()
terminalEvent:Fire()
expect(opened[1], 'Shop', 'no tab means Shop, as before')
reset()
terminalEvent:Fire('Rewords')
expect(opened[1], 'Shop', 'and an unknown name still falls back to Shop')
expect(fired.Rewards, 0, 'a near-miss spelling does not reach the modal either')

-- ---- the kiosk plaque prompt --------------------------------------------
reset()
rewardsPrompt.Triggered:Fire(player)
expect(fired.Rewards, 1, 'the ShopRewardsPrompt plaque opens Daily Rewards')
expect(#opened, 0, 'and not the terminal')
reset()
shopPrompt.Triggered:Fire(player)
expect(#opened, 1, 'an ordinary ZyntraShopPrompt still opens the terminal')
expect(opened[1], 'Shop', 'on the Shop tab')
expect(fired.Rewards, 0, 'without raising the rewards modal')
reset()
rewardsPrompt.Triggered:Fire(otherPlayer)
expect(fired.Rewards, 0, "another player's trigger reaches nobody's screen")
expect(#opened, 0, 'and opens nothing here')

-- ---- a BindableEvent that is not one -------------------------------------
-- A place where something else already owns the name must WARN and stand down,
-- not throw on the first press and take the whole rail down with it.
local impostorOpener = lobbyModalOpener('OpenImpostor')
expect(#warnings, 1, 'a wrongly-typed opener is reported once')
ok(string.find(warnings[1], 'OpenImpostor') ~= nil, 'and named in the warning')
impostorOpener()
expect(#warnings, 1, 'pressing it is a no-op rather than an error')
print('routing|' .. checks)
"""

# ── 12. THE MODAL SET, running UIDevice's own list and predicate ────────────
# ZyntraStore's rail, and both new clients, gate on
# UIDevice.ScreenOwningModalOpen(). The two new modals are only in that answer if
# they are in the list, and a name that is merely SPELLED in the file proves
# nothing -- so the list and the predicate are run together.
MODALS_TESTS = r"""
expect(UIDevice.ScreenOwningModalOpen(), false, 'an idle lobby owns no modal')
for _, attribute in ipairs({'ZyntraStoreOpen', 'DevPhoneOpen', 'ZyntraReentryOpen',
	'QueueModalOpen', 'LuckyWheelOpen', 'DailyRewardsOpen'}) do
	attributes[attribute] = true
	expect(UIDevice.ScreenOwningModalOpen(), true, attribute .. ' owns the screen')
	attributes[attribute] = nil
	expect(UIDevice.ScreenOwningModalOpen(), false, attribute .. ' releases it again')
end
expect(#SCREEN_OWNING_MODALS, 6, 'the set is exactly those six')
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
expect(#watched, 6, 'the change hook subscribes to all six')
for _, attribute in ipairs({'LuckyWheelOpen', 'DailyRewardsOpen'}) do
	ok(table.find(watched, attribute) ~= nil, attribute .. ' is watched, not just listed')
end
print('modals|' .. checks)
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
    opener_block = section("-- The two lobby modals that are NOT this terminal",
                           "\n-- Lobby supply kiosks use")
    kiosk_block = section("local boundShopPrompts = setmetatable(",
                          "\n-- Studio-only input seam")
    prompt_block = section("local function bindShopPrompt(instance)",
                           "\nlocal devPhoneCommand")
    activated_block = section("openButton.Activated:Connect(function()",
                              "\nUserInputService.InputBegan")
    routing_fakes = r"""
local warnings = {}
local function warn(message) table.insert(warnings, message) end
local inRound, queueBlocked, modalOpen = false, false, false
local opened = {}
local currentTab = 'Upgrades'
-- The tab set the terminal builds TODAY. Rewards is deliberately not in it.
local pages = {Upgrades = {}, Shop = {}, Notes = {}, Donate = {}, Colors = {},
	Settings = {}}
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
local player = {}
function player:GetAttribute(key)
	if key == 'InRound' then return inRound or nil end
	return nil
end
function player:WaitForChild() return playerScripts end
local otherPlayer = {}
local function modalBlocksStore() return queueBlocked end
function UIDevice.ScreenOwningModalOpen() return modalOpen end
local function selectTab(name) currentTab = name end
local function setMainVisible(visible)
	if visible then table.insert(opened, currentTab) end
end
local function showStatus() end
local function toggleMain() table.insert(opened, 'toggle') end
local closeButton = Instance.new('TextButton')
local function prompt(rewards)
	local instance = Instance.new('ProximityPrompt')
	instance.Name = 'ZyntraShopPrompt'
	instance.Triggered = signal()
	if rewards then instance:SetAttribute('ShopRewardsPrompt', true) end
	return instance
end
local rewardsPrompt, shopPrompt = prompt(true), prompt(false)
local workspace = {DescendantAdded = signal()}
function workspace:GetDescendants() return {rewardsPrompt, shopPrompt} end
"""
    CHECKS += lua(binary, "routing", "\n".join([
        FAKES, rail_fakes, helpers, rail_block, routing_fakes,
        opener_block, kiosk_block, prompt_block, activated_block, ROUTING_TESTS,
    ]))

    # ── 12. the modal set, from the REAL UIDevice module ───────────────────
    begin = UIDEVICE.index("local SCREEN_OWNING_MODALS = {")
    modal_block = UIDEVICE[begin:UIDEVICE.index("\n-- ------", begin)]
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

    print(f"ok  {CHECKS} checks: terminal {DESIGN_W}x{DESIGN_H},"
          f" upgrade card {phone['Height']}/{tablet['Height']}/{pc['Height']}px"
          f" (phone/tablet/pointer), shop icon"
          f" {SHOP[PHONE]['Icon']}/{SHOP[TABLET]['Icon']}/{SHOP[POINTER]['Icon']}px,"
          f" list+detail at >=760 pointer only, 5-button rail"
          f" ({', '.join(f'{k} {v}' for k, v in LANES.items())})")
    sys.exit(0)


if __name__ == "__main__":
    main()
