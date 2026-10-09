"""The touch cluster's control plan, from the REAL UIDevice module, in offline Luau.

GRID_CONTROL_PLAN_20261008 (owner, 2026-10-08; HUD B2, element 14 A + KIT fan C;
artifacts/hud-final-20261008/b2/B2-DESIGN.md section 3). The real
ReplicatedStorage/UIDevice.ModuleScript.lua is loaded under the fake engine of
test_equipment_hud.py (ENGINE / CONTEXT / BOOTS / wrap / UIDEVICE, imported, not
copied) and asked for layouts at stated fixtures. Checked:

  1. Order is the eight keys in template order (D1).
  2. The phone grid is the approved 52 / 8 / 12 to the pixel, at 844x390 and
     812x375, and the KIT fan slot is 72, 132, 172x52 (D2).
  3. The tablet grid is 64 / 10 / 15 with a 212x64 fan.
  4. On every fixture: eight slots >= 44, no overlaps (fan included), all inside
     Safe, the fan one Gap above the KIT row, clear of the raw 40 % line.
  5. Layout().KitFan: inside Safe, overlaps no movement zone, clear of Jump.
  6. 568x320 keeps the grid; the ROW fallback is reached only by a synthetic
     812x220 screen (critic C10), and is asserted there.
  7. TopRightPanel stops above the open fan, and KitFanOpen fires Changed.
  8. A pointer layout still publishes the plan, and its panel ignores the fan.
  9. The slicing anchors other suites depend on survive.

The slot helpers (slotRect, overlaps, layoutAt, the fixture matrix, the layout
table) are this file's own copies: the ones in test_equipment_hud.py live inside
its PLAN_TESTS, which agent C re-baselines (critic C1).

No network, no Studio. Set LUAU_BIN to an official Luau interpreter.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_equipment_hud import BOOTS, CONTEXT, ENGINE, UIDEVICE, wrap

TESTS = r'''
local KEYS = {"TouchJump", "TouchRunHold", "TouchSneakHold", "FlashlightPower",
	"ProtectionUse", "KitToggle", "TouchDropGlowstick", "TouchPOV"}
-- 844x390 (safe 47..797 x 58..369): Right, Bottom per key, from B2-DESIGN 2.1.
local PHONE_SLOTS = {
	TouchJump = {12, 12}, TouchRunHold = {72, 12}, TouchSneakHold = {132, 12},
	FlashlightPower = {192, 12}, ProtectionUse = {12, 72}, KitToggle = {72, 72},
	TouchDropGlowstick = {132, 72}, TouchPOV = {192, 72},
}

local function slotRect(layout, slot)
	local right = layout.Safe.Right - slot.Right
	local bottom = layout.Safe.Bottom - slot.Bottom
	return {Left = right - slot.Width, Top = bottom - slot.Height, Right = right, Bottom = bottom}
end

local function overlaps(a, b)
	return a.Left < b.Right and a.Right > b.Left and a.Top < b.Bottom and a.Bottom > b.Top
end

local function inside(rect, outer)
	return rect.Left >= outer.Left and rect.Right <= outer.Right
		and rect.Top >= outer.Top and rect.Bottom <= outer.Bottom
end

-- The objective readout's headroom, as computeLayout's objectiveHeadroom states it.
local function headroom(layout)
	return math.min(layout.Zones.Controls.Top, layout.Zones.Jump.Top) - 8 - (layout.Safe.Top + 8)
end

-- Raw 40 % line of the dynamic thumbstick, plus THUMBSTICK_CLEARANCE.
local function stickLine(layout)
	return layout.Display.Left + layout.Width * .4 + 8
end

local device, deviceCtx
do
	deviceCtx = makeContext()
	deviceCtx.NoSpawn = true
	-- A host that can also state its own insets (the real-device row in 6).
	function deviceCtx.GuiService:GetInsetArea(kind)
		if deviceCtx.HostInsets then return deviceCtx.HostInsets[kind.Name] end
		local size = deviceCtx.camera.ViewportSize
		return Rect.new(0, 0, size.X, size.Y)
	end
	device = bootModule(deviceCtx, UIDeviceSource)
	check(type(device) == "table" and type(device.Layout) == "function",
		"the real UIDevice module loads under the fake DataModel")
end
local ws = deviceCtx.workspace

-- Every fixture input fires a forced refresh on its own; this one makes sure a
-- recompute happens even when nothing about the row changed.
local function relayout()
	ws:SetAttribute("UIRegressionTopbarBandLR", Vector2.zero)
	ws:SetAttribute("UIRegressionTopbarBandLR", nil)
end

local function layoutAt(row, isTouch)
	deviceCtx.HostInsets = nil
	deviceCtx.UserInputService.TouchEnabled = isTouch
	deviceCtx.camera.ViewportSize = Vector2.new(row.Width, row.Height)
	local h = row.Housing or {0, 0, 0, 0}
	ws:SetAttribute("UIRegressionSafeInsetsLT", Vector2.new(h[1], h[2]))
	ws:SetAttribute("UIRegressionSafeInsetsRB", Vector2.new(h[3], h[4]))
	ws:SetAttribute("UIRegressionTopbarInsetLT", Vector2.new(0, row.Topbar or 0))
	ws:SetAttribute("UIRegressionTopbarInsetRB", Vector2.zero)
	ws:SetAttribute("ForceTouchUI", isTouch)
	ws:SetAttribute("UIRegressionViewport", Vector2.new(row.Width, row.Height))
	relayout()
	return device.Layout()
end

local MATRIX = {
	{Name = "705x338", Width = 705, Height = 338, Topbar = 36},
	{Name = "568x320", Width = 568, Height = 320, Topbar = 36},
	{Name = "667x375", Width = 667, Height = 375, Topbar = 36, Housing = {44, 0, 44, 21}},
	{Name = "812x375", Width = 812, Height = 375, Topbar = 58, Housing = {44, 0, 44, 21}},
	{Name = "844x390", Width = 844, Height = 390, Topbar = 58, Housing = {47, 0, 47, 21}},
	{Name = "956x440", Width = 956, Height = 440, Topbar = 58, Housing = {0, 0, 59, 21}},
	{Name = "1024x768", Width = 1024, Height = 768, Topbar = 36},
	{Name = "375x812", Width = 375, Height = 812, Topbar = 36},
}

-- The cluster checks every layout gets, whatever its arrangement.
local function checkPlacement(name, layout)
	local plan = layout.ControlPlan
	local rects = {}
	for _, key in ipairs(KEYS) do
		local slot = plan.Slots[key]
		check(slot ~= nil, name .. ": the plan states a slot for " .. key)
		check(slot.Width >= 44 and slot.Height >= 44, name .. ": " .. key .. " clears the 44px floor")
		rects[key] = slotRect(layout, slot)
		check(inside(rects[key], layout.Safe), name .. ": " .. key .. " is inside Safe")
	end
	local fan = slotRect(layout, plan.Fan)
	check(fan.Bottom - fan.Top >= 44, name .. ": a fan item (Fan.Height square) clears 44px")
	check(inside(fan, layout.Safe), name .. ": the KIT fan is inside Safe")
	check(fan.Bottom == rects.KitToggle.Top - plan.Gap,
		name .. ": the fan's bottom is the KIT row's top minus Gap")
	check(fan.Right == rects.KitToggle.Right, name .. ": the fan's right edge is KIT's")
	local all = table.clone(KEYS)
	rects.Fan = fan
	table.insert(all, "Fan")
	local collisions = 0
	for i = 1, #all do
		for j = i + 1, #all do
			if overlaps(rects[all[i]], rects[all[j]]) then collisions += 1 end
		end
	end
	check(collisions == 0, name .. ": no two slots overlap, the fan included")

	local kitFan = layout.KitFan
	check(kitFan.Left == fan.Left and kitFan.Top == fan.Top and kitFan.Right == fan.Right
		and kitFan.Bottom == fan.Bottom and kitFan.Width == plan.Fan.Width
		and kitFan.Height == plan.Fan.Height,
		name .. ": Layout().KitFan is ControlPlan.Fan through the safe rect")
	-- OverlapsMovementZone tests Thumbstick, then Controls, then Jump, so "Jump"
	-- means the first two are clear.
	local hit = device.OverlapsMovementZone(kitFan.Left, kitFan.Top, kitFan.Right, kitFan.Bottom)
	check(hit == nil or hit == "Jump", name .. ": the KIT fan is clear of the thumbstick and Controls")
	if layout.Zones.Jump.Size == 70 then
		check(hit == nil, name .. ": the KIT fan overlaps no movement zone")
		check(not overlaps(kitFan, layout.Zones.Jump), name .. ": the KIT fan is clear of Roblox's jump")
	else
		-- Where Roblox's jump is the 120px button (min axis > 500, every tablet) its
		-- zone reaches up over the grid's own upper rank, so the fan cannot clear it
		-- without leaving KIT. The fan is drawn only in a round, where the cluster
		-- has suppressed that jump (SuppressDefaultJump); assert that premise: the
		-- fan conflicts with nothing the drawn cluster does not already cover.
		local rankHits = overlaps(rects.ProtectionUse, layout.Zones.Jump)
			or overlaps(rects.KitToggle, layout.Zones.Jump)
		check(hit == nil or rankHits,
			name .. ": the fan reaches Roblox's 120px jump only where the upper rank already does")
	end
	check(kitFan.Left >= layout.Zones.Thumbstick.Right,
		name .. ": the KIT fan is right of the thumbstick region")

	if not layout.Portrait then
		local line = stickLine(layout)
		for _, key in ipairs(KEYS) do
			check(rects[key].Left >= line, name .. ": " .. key .. " is right of the raw 40% line")
		end
		check(fan.Left >= line, name .. ": the fan is right of the raw 40% line")
		-- planZone subtracts CONTROL_CUSHION from the leftmost slot, and the row is
		-- sized to the line itself, so the row may only be held to line - 8 (C10).
		local slack = plan.Mode == "row" and 8 or 0
		check(layout.Zones.Controls.Left >= line - slack,
			name .. ": Zones.Controls starts right of the 40% line (" .. plan.Mode .. ")")
	end
	return rects
end

-- 1. The key order is UIDevice's, so it is asserted here.
do
	local layout = layoutAt(MATRIX[5], true)
	local order = layout.ControlPlan.Order
	check(#order == 8, "Order holds exactly eight keys")
	for index, key in ipairs(KEYS) do
		check(order[index] == key, "Order[" .. index .. "] is " .. key)
	end
end

-- 2. The phone grid, to the pixel.
for _, row in ipairs({MATRIX[5], MATRIX[4]}) do
	local layout = layoutAt(row, true)
	local plan = layout.ControlPlan
	check(layout.Class == "phone" and plan.Mode == "grid", row.Name .. ": a phone gets the grid")
	check(plan.Cell == 52 and plan.Gap == 8 and plan.Edge == 12, row.Name .. ": cell 52, gap 8, edge 12")
	for key, inset in pairs(PHONE_SLOTS) do
		local slot = plan.Slots[key]
		check(slot.Right == inset[1] and slot.Bottom == inset[2] and slot.Width == 52 and slot.Height == 52,
			row.Name .. ": " .. key .. " sits at " .. inset[1] .. ", " .. inset[2] .. ", 52x52")
	end
	local fan = plan.Fan
	check(fan.Right == 72 and fan.Bottom == 132 and fan.Width == 172 and fan.Height == 52,
		row.Name .. ": the fan slot is 72, 132, 172x52")
	local jump = slotRect(layout, plan.Slots.TouchJump)
	check(jump.Left == layout.Safe.Right - 64 and jump.Right == layout.Safe.Right - 12
		and jump.Top == layout.Safe.Bottom - 64 and jump.Bottom == layout.Safe.Bottom - 12,
		row.Name .. ": JUMP is Safe.Right-64..-12 by Safe.Bottom-64..-12")
	checkPlacement(row.Name, layout)
end
do -- and in the display's own pixels, against the dump and phone-level-3
	local layout = layoutAt(MATRIX[5], true)
	local ox, oy = layout.Display.Left, layout.Display.Top
	check(layout.Safe.Left - ox == 47 and layout.Safe.Right - ox == 797
		and layout.Safe.Top - oy == 58 and layout.Safe.Bottom - oy == 369,
		"844x390: the fixture's safe area is 47..797 x 58..369")
	local jump = slotRect(layout, layout.ControlPlan.Slots.TouchJump)
	check(jump.Left - ox == 733 and jump.Right - ox == 785 and jump.Top - oy == 305 and jump.Bottom - oy == 357,
		"844x390: JUMP at x 733..785, y 305..357")
	local pov = slotRect(layout, layout.ControlPlan.Slots.TouchPOV)
	check(pov.Left - ox == 553 and pov.Top - oy == 245, "844x390: the cluster starts at x 553, y 245")
	local fan = layout.KitFan
	check(fan.Left - ox == 553 and fan.Right - ox == 725 and fan.Top - oy == 185 and fan.Bottom - oy == 237,
		"844x390: the KIT fan at x 553..725, y 185..237 (D2)")
	check(fan.Bottom == layout.Zones.Controls.Top,
		"844x390: the fan's bottom is Controls.Top (touching, not overlapping)")
end

-- 3. The tablet grid.
do
	local layout = layoutAt(MATRIX[7], true)
	local plan = layout.ControlPlan
	check(layout.Class == "tablet" and plan.Mode == "grid", "1024x768: a tablet gets the grid")
	check(plan.Cell == 64 and plan.Gap == 10 and plan.Edge == 15, "1024x768: cell 64, gap 10, edge 15")
	check(plan.Slots.TouchJump.Right == 15 and plan.Slots.KitToggle.Right == 89
		and plan.Slots.KitToggle.Bottom == 89, "1024x768: the tablet slots step 74")
	check(plan.Fan.Right == 89 and plan.Fan.Bottom == 163 and plan.Fan.Width == 212 and plan.Fan.Height == 64,
		"1024x768: the fan slot is 89, 163, 212x64")
end

-- 4 + 5. Every fixture.
for _, row in ipairs(MATRIX) do
	local layout = layoutAt(row, true)
	check(layout.ControlPlan.Mode == "grid", row.Name .. ": the grid stands")
	checkPlacement(row.Name, layout)
end

-- 6. Short screens.
do
	local layout = layoutAt(MATRIX[2], true)
	check(layout.ControlPlan.Mode == "grid", "568x320: keeps the grid")
	check(headroom(layout) >= 56, "568x320: the objective keeps its 56px")
	check(headroom(layout) == 136, "568x320: objective headroom is 136 (measured " .. headroom(layout) .. ")")
end
do
	-- No fixture or real device is short enough for the row: the grid leaves 56px
	-- whenever the safe area is ~204px tall. So the fallback is reached by a
	-- SYNTHETIC 812x220 screen with a stated 36px topbar (critic C10). Its height
	-- is under the 240 floor of UIRegressionViewport, so it is stated as the
	-- HOST's own insets instead: a real-device layout, nothing forced.
	deviceCtx.HostInsets = {
		None = Rect.new(0, -36, 812, 184), DeviceSafeInsets = Rect.new(0, -36, 812, 184),
		CoreUISafeInsets = Rect.new(0, 0, 812, 184), TopbarSafeInsets = Rect.new(0, -36, 812, 0),
	}
	deviceCtx.camera.ViewportSize = Vector2.new(812, 220)
	ws:SetAttribute("ForceTouchUI", true)
	ws:SetAttribute("UIRegressionViewport", nil)
	relayout()
	local layout = device.Layout()
	check(layout.Synthetic == false and layout.Width == 812 and layout.Safe.Bottom == 184,
		"812x220: a real-device layout with a 184px safe area")
	local gridTop = layout.Safe.Bottom - (12 + 52 + 8 + 52) - 8
	check(math.min(gridTop, layout.Zones.Jump.Top) - 16 - layout.Safe.Top == 36,
		"812x220: the grid would leave the readout 36px, under 56")
	local plan = layout.ControlPlan
	check(plan.Mode == "row", "812x220: the row fallback is chosen")
	check(plan.Cell == 50, "812x220: one rank of eight at cell 50")
	check(headroom(layout) == 78, "812x220: the row buys the readout 78px (" .. headroom(layout) .. ")")
	check(plan.Fan.Right == 312 and plan.Fan.Bottom == 80 and plan.Fan.Width == 165 and plan.Fan.Height == 50,
		"812x220: the fan slot is 312, 80, 165x50")
	check(layout.KitFan.Left == 335 and layout.KitFan.Right == 500
		and layout.KitFan.Top == 54 and layout.KitFan.Bottom == 104,
		"812x220: the fan is x 335..500, y 54..104")
	checkPlacement("812x220 row", layout)
	deviceCtx.HostInsets = nil
end

-- 7. TopRightPanel and the open fan.
do
	local layout = layoutAt(MATRIX[5], true)
	local fires = 0
	local connection = device.Changed:Connect(function() fires += 1 end)
	deviceCtx.player:SetAttribute("KitFanOpen", true)
	check(fires >= 1, "KitFanOpen = true fires UIDevice.Changed")
	layout = device.Layout()
	check(layout.KitFanOpen == true, "Layout().KitFanOpen copies the attribute")
	local panel = device.TopRightPanel(240, 300)
	check(panel.Bottom <= layout.KitFan.Top - 8, "an open fan: the panel stops 8px above it")
	check(panel.Bottom == layout.KitFan.Top - 8, "an open fan: the panel uses all the room above it")
	local narrow = device.TopRightPanel(60, 300)
	check(narrow.Bottom == layout.Zones.Controls.Top - 8,
		"a panel clear of the fan's columns keeps the cluster's limit")
	fires = 0
	deviceCtx.player:SetAttribute("KitFanOpen", false)
	check(fires >= 1, "KitFanOpen = false fires UIDevice.Changed")
	layout = device.Layout()
	check(layout.KitFanOpen == false, "Layout().KitFanOpen follows it back")
	panel = device.TopRightPanel(240, 300)
	check(panel.Bottom == layout.Zones.Controls.Top - 8, "a closed fan: the panel is back to Controls.Top - 8")
	connection:Disconnect()
end

-- 8. A pointer layout publishes the plan and ignores the fan.
do
	local row = {Width = 1280, Height = 720}
	local layout = layoutAt(row, false)
	check(layout.IsTouch == false, "a forced pointer layout reports no touch form factor")
	check(layout.ControlPlan.Mode == "grid" and layout.ControlPlan.Slots.KitToggle ~= nil
		and layout.ControlPlan.Fan ~= nil and layout.KitFan ~= nil,
		"a pointer layout still publishes the grid plan and the fan")
	local closed = device.TopRightPanel(240, 300)
	deviceCtx.player:SetAttribute("KitFanOpen", true)
	local open = device.TopRightPanel(240, 300)
	check(open.Bottom == closed.Bottom and open.Right == closed.Right,
		"the pointer panel ignores KitFanOpen")
	deviceCtx.player:SetAttribute("KitFanOpen", nil)
end

print("Touch control plan: " .. checks .. " checks passed (real UIDevice, offline Luau)")
'''

ANCHORS = [
    "function UIDevice.IsGamepadOnly()",
    "-- ---------------------------------------------------------------------------\n-- 3. Layout",
    "local SCREEN_OWNING_MODALS = {",
    "-- Run `callback` whenever",
]


def main():
    source = UIDEVICE.read_text(encoding="utf-8")
    # 9. The anchors other suites slice on, byte for byte.
    for anchor in ANCHORS:
        assert anchor in source, "UIDevice lost the anchor %r" % anchor
    modals = source.index("local SCREEN_OWNING_MODALS = {")
    assert "\n-- ------" in source[modals:], "no section rule after SCREEN_OWNING_MODALS"
    assert "columnControlPlan" not in source and '"column"' not in source, "the column plan is gone"
    begin = source.index("local CONTROL_KEYS_RIGHT_FIRST")
    plan_section = source[begin:source.index("local function insetArea", begin)]
    assert plan_section.isascii(), "the plan section is ASCII-only"
    for line in source.splitlines():
        if "KitFan" in line or "GRID_CONTROL_PLAN_20261008" in line:
            assert line.isascii(), "non-ASCII B2 line: %r" % line

    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    if Path(compiler).exists():
        subprocess.run([compiler, "--null", str(UIDEVICE)], check=True, capture_output=True)
    program = "".join([ENGINE, CONTEXT, BOOTS, wrap("UIDeviceSource", source), TESTS])
    with tempfile.TemporaryDirectory(prefix="touch-plan-") as directory:
        path = Path(directory) / "touch_control_plan_test.luau"
        path.write_text(program, encoding="utf-8")
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or "checks passed" not in result.stdout:
        print(result.stdout.strip()[-4000:])
        print(result.stderr.strip()[-4000:])
        raise SystemExit("test_touch_control_plan FAILED")
    print(result.stdout.strip().splitlines()[-1])


if __name__ == "__main__":
    main()
