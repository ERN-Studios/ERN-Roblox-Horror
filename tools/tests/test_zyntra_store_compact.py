"""The Zyntra terminal's three content tiers, checked against the real source.

Trello #68: 67.7% of this game's audience plays on touch. The Upgrades and Shop
cards were authored for a mouse and the layout hooks now draw them in three
tiers -- phone / tablet / pointer. Two things have to stay true and neither is
visible from a screenshot:

  * the POINTER tier is still the authored card, to the pixel (330px upgrade
    card, 76px product icon, copyLeft 104 / copyInset 118), and
  * no tier draws type under 11px or a tap target under 44 on touch.

The tier tables and the two height expressions are EXTRACTED from
ZyntraStore.LocalScript.lua, so this fails when the source numbers move rather
than agreeing with a copy of them. The arithmetic below mirrors the hooks; the
two `assert ... in SRC` checks are what keep the mirror honest.

Run:  python tools/tests/test_zyntra_store_compact.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SRC_PATH = (Path(__file__).resolve().parents[2]
            / "StarterPlayer" / "StarterPlayerScripts" / "ZyntraStore.LocalScript.lua")
SRC = SRC_PATH.read_text(encoding="utf-8")

PHONE, TABLET, POINTER = 0, 1, 2
TOUCH_TAP, POINTER_TAP = 44, 32


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
assert SRC.count("})[(fit.Compact and fit.Touch) and 1 or (fit.Touch and 2 or 3)]") == 2
assert """	local descTop = face.Pad + titleHeight + face.GapTitle
	local pctTop = descTop + descHeight + face.GapDesc
	local cellHeight = pctTop + face.PctBox + face.LevelBox + face.GapLevel
		+ buttonHeight + face.Pad""" in SRC
assert "\tlocal cellHeight = bodyBottom + face.Lead + buyHeight + face.Foot\n" in SRC
assert "\tlocal bodyBottom = face.IconTop + face.Icon\n" in SRC
assert "\tlocal copyLeft = face.Pad * 2 + face.Icon\n\tlocal copyInset = copyLeft + face.Pad\n" in SRC


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
assert pc["Height"] == 330, pc
assert (pc["Title"], pc["Desc"], pc["Pct"], pc["Level"]) == (18, 60, 142, 222), pc
assert (pc["Button"], pc["ButtonOffset"], pc["Inset"]) == (48, -66, -36), pc

shop_pc = shop_cell(POINTER, POINTER_TAP)
assert SHOP[POINTER]["Icon"] == 76, SHOP[POINTER]
assert (shop_pc["CopyLeft"], shop_pc["CopyInset"]) == (104, 118), shop_pc
assert (shop_pc["IconBottom"], shop_pc["Buy"], shop_pc["Inset"]) == (94, 38, -28), shop_pc
# bodyBottom + 16 + 38 + 12, and 94 while the copy is shorter than the icon.
assert shop_pc["Height"] == 94 + 16 + 38 + 12 == 160, shop_pc
assert shop_cell(POINTER, POINTER_TAP, desc=56)["Height"] == 112 + 16 + 38 + 12, "PC stack"

# ── 2. THE TOUCH TIERS SHRINK, and stay measurable ─────────────────────────
# 956x440 landscape phone: the page is 201px tall and the authored card is 330.
phone = upgrade_card(PHONE, TOUCH_TAP)
assert phone["Height"] == 210, phone
assert phone["Height"] < 260, phone
# Never shorter than the parts it is made of.
f = UPGRADE[PHONE]
assert phone["Height"] >= (f["TitleBox"] + f["DescBox"] + f["PctBox"] + f["LevelBox"]
                           + max(TOUCH_TAP, f["Button"])), phone
# A three-line description at a narrow width grows the card; it never clips it.
assert upgrade_card(PHONE, TOUCH_TAP, desc=42)["Height"] == 220, "measured, not clamped"

tablet = upgrade_card(TABLET, TOUCH_TAP)
assert tablet["Height"] == 246, tablet
assert phone["Height"] < tablet["Height"] < pc["Height"], (phone, tablet, pc)

# ── 3. EVERY TOUCH TARGET CLEARS 44, and no type is drawn under 11 ─────────
for tier in (PHONE, TABLET, POINTER):
    assert upgrade_card(tier, TOUCH_TAP)["Button"] >= 44, UPGRADE[tier]
    assert shop_cell(tier, TOUCH_TAP)["Buy"] >= 44, SHOP[tier]
    for key in ("Title", "Desc", "Level"):
        assert UPGRADE[tier][key] >= 11, (tier, key, UPGRADE[tier])
    assert UPGRADE[tier]["Pct"] >= 11 and SHOP[tier]["Title"] >= 11, tier
    assert SHOP[tier]["Desc"] >= 11, SHOP[tier]
    # The cell always holds the icon standing beside the copy, plus the buy row.
    cell = shop_cell(tier, TOUCH_TAP)
    assert cell["Height"] >= cell["IconBottom"] + cell["Buy"], cell

# The phone shop card: a 52px icon gives the copy 36 more pixels of column.
assert SHOP[PHONE]["Icon"] == 52 and SHOP[TABLET]["Icon"] == 64
assert shop_cell(PHONE, TOUCH_TAP)["CopyInset"] == 82, SHOP[PHONE]
assert shop_cell(PHONE, TOUCH_TAP, desc=39)["Height"] == 157, "956x440 shop cell"

print(f"ok  upgrade card {phone['Height']}/{tablet['Height']}/{pc['Height']}px"
      f" (phone/tablet/pointer), shop icon"
      f" {SHOP[PHONE]['Icon']}/{SHOP[TABLET]['Icon']}/{SHOP[POINTER]['Icon']}px")
sys.exit(0)
