"""Run the real ReplicatedStorage/RoundHud module offline (owner, 2026-10-08; HUD batch B1).

BUILD-PLAN.md 1.1/1.3/1.4 and section 5, FRAMEWISP-PIPELINE.md 5.1 (artifacts/hud-final-20261008/).
The REAL RoundHud, ShopBinder, UIStyle and ZyntraDetectorVisual run inside the fake engine of
tools/tests/hud_harness.luau. Its template tree is the REAL Framewisp import of HUD_PC
(tools/tests/fixtures/hud/framewisp-dump.HUD_PC.json, as staged at
ReplicatedStorage.ZyntraHUD.Templates.HUD_PC) and of HUD_Touch
(fixtures/hud/framewisp-dump.HUD_Touch.json). Both dumps are required: the hand-written
section 2.6 stand-in for HUD_Touch is gone now that the real import exists (owner, 2026-10-08).

Checked: the RoundHud ScreenGui (DisplayOrder 10); Mount (clone, strip, design size x Scale,
reset placement, multi-line wrap, Soft ramp, touch 12 px floor, scaleText, the template left
untouched, a missing template warned once and nothing drawn); Attention (100 % for the hold on
change, rest opacity, hidden at rest 0, urgent never dims, stale timers, Hide, ReduceFlashing
irrelevant); Keycap on keyboard, gamepad (glyph and no-glyph), touch and gamepad-only, re-applied
on UIDevice.Changed; the detector card's LOW/MEDIUM/HIGH copy, colours, bars, countdown, 4 s
attention, HIGH never dimming, expiry, placement above the SCAN chip, the touch line, a device
flip; and Clear, which leaves a caller's Mount alone (B3 critic K17). B3 (owner, 2026-10-08): Mount
anchors every *Fill on its left edge (StaminaBar, HoldFill's inset, Scale and Offset, the template
untouched, no other node moved) and opts.Touch floors a PC template's text at 12 px. Plus: RoundHud is
ASCII-only with LF endings, and luau-compile accepts it.

Not checked: real font metrics, CanvasGroup rendering, the engine's glyph images. Set LUAU_BIN
(luau 0.737; luau-compile.exe is expected beside it, or LUAU_COMPILE_BIN).
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCES = {
    "RoundHud": ROOT / "ReplicatedStorage/RoundHud.ModuleScript.lua",
    "ShopBinder": ROOT / "ReplicatedStorage/ZyntraShopUI/ShopBinder.ModuleScript.lua",
    "UIStyle": ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua",
    "ZyntraDetectorVisual": ROOT / "ReplicatedStorage/ZyntraDetectorVisual.ModuleScript.lua",
}
HARNESS = HERE / "hud_harness.luau"
DUMPS = HERE / "fixtures/hud"


def trees():
    pc = json.loads((DUMPS / "framewisp-dump.HUD_PC.json").read_text(encoding="utf-8"))
    assert pc["frame"] == "HUD_PC", pc["frame"]
    out = {"HUD_PC": pc["root"]}
    touch = json.loads((DUMPS / "framewisp-dump.HUD_Touch.json").read_text(encoding="utf-8"))
    assert touch["frame"] == "HUD_Touch", touch["frame"]
    out["HUD_Touch"] = touch["root"]
    return out


def lua_string(text):
    out = ['"']
    for ch in text:
        code = ord(ch)
        if ch == '"' or ch == "\\":
            out.append("\\" + ch)
        elif ch == "\n":
            out.append("\\n")
        elif code < 32 or code > 126:
            out.append("\\u{%X}" % code)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, (list, tuple)):
        return "{" + ",".join(lua(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[%s]=%s" % (lua_string(k), lua(v)) for k, v in value.items()) + "}"
    raise TypeError(value)


def long_string(text):
    level = 1
    while "]" + "=" * level + "]" in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"


TESTS = r'''
local B = "\u{B7}"
local P = {
	Sage = Color3.fromRGB(167, 184, 174), Amber = Color3.fromRGB(232, 160, 36),
	Coral = Color3.fromRGB(242, 112, 95), Line = Color3.fromRGB(38, 49, 52),
}
local function fresh(opts)
	local ctx = context(opts)
	return ctx, ctx:Require("RoundHud")
end
local function opacity(group) return 1 - group.GroupTransparency end

-- == the RoundHud ScreenGui and the device pick =============================================
do
	local ctx, Hud = fresh()
	local gui = Hud.Gui()
	check(gui.ClassName == "ScreenGui" and gui.Name == "RoundHud", "Gui() is the RoundHud ScreenGui")
	check(gui.DisplayOrder == 10, "RoundHud sits at DisplayOrder 10 (BUILD-PLAN 1.4)")
	check(gui.ResetOnSpawn == false, "RoundHud survives a respawn")
	check(gui.Parent == ctx.PlayerGui, "RoundHud lives in PlayerGui")
	check(Hud.Gui() == gui, "Gui() makes the ScreenGui once")
	check(Hud.Bundle() == "HUD_PC", "PC mounts HUD_PC")
	ctx:Device({Touch = true})
	check(Hud.Bundle() == "HUD_Touch", "the touch layout mounts HUD_Touch")
	ctx:Device({Touch = false, GamepadEnabled = true, LastInput = "Gamepad"})
	check(Hud.Bundle() == "HUD_PC", "a gamepad keeps the PC look")
end

-- == Mount ===================================================================================
do
	local ctx, Hud = fresh()
	local gui = Hud.Gui()
	local template = find(ctx.Templates.HUD_PC, "DetectorCard")
	-- Template hygiene plants: an import runtime script and an _ignore note.
	newInstance("LocalScript", "FramewispRuntime").Parent = template
	newInstance("Frame", "Note_ignore").Parent = template
	local placed = template.Position
	local root, attention = Hud.Mount("HUD_PC", "DetectorCard", gui, {Name = "Probe"})
	ctx:Flush()
	check(root and root.Name == "Probe" and root.Parent == gui, "Mount parents the clone under opts.Name")
	check(attention == nil, "no Attention unless asked for")
	check(root.Size == UDim2.fromOffset(312, 72), "DetectorCard mounts at its design size: " .. tostring(root.Size))
	check(root.AnchorPoint.X == 0 and root.AnchorPoint.Y == 0 and root.Position == UDim2.new(),
		"Mount resets AnchorPoint and Position for the caller")
	for _, node in ipairs(root:GetDescendants()) do
		check(not node:IsA("LuaSourceContainer"), "no script survives a mount: " .. node:GetFullName())
		check(not string.find(node.Name, "_ignore$"), "no _ignore layer survives a mount")
	end
	check(template:FindFirstChild("FramewispRuntime") ~= nil and template.Position == placed,
		"the template itself is left untouched")
	local ramp = find(root, "Soft"):FindFirstChildOfClass("UIGradient").Transparency
	check(ramp and ramp.Keypoints[1].Value == 0.35 and ramp.Keypoints[2].Value == 1, "Soft gets the 0.35 -> 1 soft-Ink ramp")
	check(find(template, "Soft"):FindFirstChildOfClass("UIGradient").Transparency == nil, "the template's Soft is not softened")
	local reading = find(root, "Reading")
	check(reading.TextSize == 18 and reading.TextScaled == false,
		"text is solved at design size (Reading 18 px at k = 1): " .. tostring(reading.TextSize))
	check(reading:FindFirstChildOfClass("UITextSizeConstraint") == nil, "PC text gets no touch floor")

	local big = Hud.Mount("HUD_PC", "DetectorCard", gui, {Name = "Big", Scale = 1.5})
	ctx:Flush()
	check(big.Size == UDim2.fromOffset(468, 108), "opts.Scale scales the design size: " .. tostring(big.Size))
	check(find(big, "Reading").TextSize == 28, "and the text with it: " .. tostring(find(big, "Reading").TextSize))
	check(Hud.Mount("HUD_PC", "DetectorCard", gui).Name == "DetectorCard", "the default name is the template's base name")

	-- Multi-line boxes wrap (pipeline 2.0 rule 7); one-line boxes do not.
	local card = Hud.Mount("HUD_PC", "RoundExitCard", gui)
	check(find(ctx.Templates.HUD_PC, "RoundExitCard/Body").TextWrapped == false, "fixture: Body arrives unwrapped")
	check(find(card, "Body").TextWrapped == true, "a two-line box (Body, 30 px at 12 px) wraps")
	check(find(card, "Title").TextWrapped == false, "a one-line Title does not")
	check(find(Hud.Mount("HUD_PC", "LeaveChipWide", gui), "HoldHint").TextWrapped == false, "a one-line hint does not")

	-- The touch floor.
	local line = Hud.Mount("HUD_Touch", "DetectorLine", gui)
	local floor = find(line, "Line"):FindFirstChildOfClass("UITextSizeConstraint")
	check(floor and floor.MinTextSize == 12, "touch text is floored at 12 px")

	-- A missing template: nil, nothing drawn, one warning per path.
	local before = #gui:GetChildren()
	check(Hud.Mount("HUD_PC", "NoSuchTemplate", gui) == nil, "a missing template mounts nothing")
	Hud.Mount("HUD_PC", "NoSuchTemplate", gui)
	check(#gui:GetChildren() == before, "and draws nothing in its place")
	check(ctx:Warned("[RoundHud] missing template: HUD_PC/NoSuchTemplate") == 1, "warned once per path")
	check(Hud.Template("HUD_PC", "DetectorCard") == template, "Template returns the staged node")

	-- With Attention: a CanvasGroup carries the name and the size; the clone fills it.
	local group, att = Hud.Mount("HUD_PC", "DetectorCard", gui, {Name = "Wrapped", Attention = {Hold = 6, Rest = 0.45}})
	ctx:Flush()
	check(group.ClassName == "CanvasGroup" and group.Name == "Wrapped", "an Attention mount is a CanvasGroup under opts.Name")
	check(group.Size == UDim2.fromOffset(312, 72), "the group carries the design size")
	local inner = group:FindFirstChildWhichIsA("Frame")
	check(inner and inner.Size == UDim2.fromScale(1, 1) and inner.Position == UDim2.new(), "the clone fills its group")
	check(group.Visible == false and group.GroupTransparency == 1, "an Attention mount starts hidden")
	check(att ~= nil and find(group, "Reading").TextSize == 18, "text is solved through the group")
end

-- == B3: every *Fill is left-anchored; opts.Touch (HUD_B3; owner, 2026-10-08) ==================
local function leftEdge(node) return node.Position.X.Scale - node.AnchorPoint.X * node.Size.X.Scale end

do -- the stamina bar's Fill grows rightward from the track's left edge
	local ctx, Hud = fresh()
	local bar = Hud.Mount("HUD_PC", "StaminaBar", Hud.Gui())
	ctx:Flush()
	local fill = find(bar, "Track/Fill")
	check(fill.AnchorPoint.X == 0 and fill.AnchorPoint.Y == 0.5, "Mount anchors Fill on its left edge, Y kept")
	check(near(fill.Position.X.Scale, 0) and fill.Position.X.Offset == 0, "the left edge it already started at: " .. tostring(fill.Position))
	check(fill.Position.Y.Scale == 0.5 and fill.Size == UDim2.new(0.625, 0, 1, 0), "Fill's Y and size are left alone")
	local template = find(ctx.Templates.HUD_PC, "StaminaBar/Track/Fill")
	check(template.AnchorPoint.X == 0.5 and template.Position.X.Scale == 0.3125, "the template's Fill is untouched")
	local placed = fill.Position
	fill.Size = UDim2.fromScale(0.3, 1)
	check(fill.Position == placed and near(leftEdge(fill), 0), "a width write keeps the left edge at the track's left")
	local group = Hud.Mount("HUD_PC", "StaminaBar", Hud.Gui(), {Name = "Wrapped", Attention = {Hold = 0, Rest = 0.55}})
	check(find(group, "Track/Fill").AnchorPoint.X == 0, "an Attention mount's Fill is anchored too")
end

do -- HoldFill keeps its exact left inset; a planted Fill with offsets; a non-Fill name is not touched
	local ctx, Hud = fresh()
	local chip = Hud.Mount("HUD_PC", "LeaveChipWide", Hud.Gui())
	local hold = find(chip, "HoldFill")
	check(hold.AnchorPoint.X == 0 and near(hold.Position.X.Scale, 0.309259 - 0.5 * 0.603704),
		"HoldFill's left edge stays at 0.309259 - 0.5 x 0.603704: " .. tostring(hold.Position))
	check(hold.Position.Y.Scale == 0.5 and hold.AnchorPoint.Y == 0.5, "HoldFill's Y is kept")
	local card = find(ctx.Templates.HUD_PC, "DetectorCard")
	local probe = newInstance("Frame", "ProbeFill")
	probe.AnchorPoint, probe.Position, probe.Size = Vector2.new(1, 0.5), UDim2.new(0.5, 10, 0.5, 2), UDim2.new(0.2, 20, 1, 0)
	probe.Parent = card
	local other = newInstance("Frame", "FillHint")
	other.AnchorPoint = Vector2.new(0.5, 0.5)
	other.Parent = card
	local mounted = Hud.Mount("HUD_PC", "DetectorCard", Hud.Gui())
	local p = mounted:FindFirstChild("ProbeFill")
	check(p.AnchorPoint.X == 0 and near(p.Position.X.Scale, 0.3) and p.Position.X.Offset == -10
		and p.Position.Y.Scale == 0.5 and p.Position.Y.Offset == 2,
		"Scale and Offset both move by AnchorPoint.X x Size: " .. tostring(p.Position))
	check(mounted:FindFirstChild("FillHint").AnchorPoint.X == 0.5, "only a base name ENDING in Fill is anchored")
end

do -- opts.Touch: the PC stamina bar at Scale 0.5 on the touch layout keeps WINDED at 12 px
	local ctx, Hud = fresh()
	local root = Hud.Mount("HUD_PC", "StaminaBar", Hud.Gui(), {Name = "StaminaBar", Scale = 0.5, Touch = true,
		Attention = {Hold = 0, Rest = 0.55}})
	ctx:Flush()
	check(root.Size == UDim2.fromOffset(160, 13), "Scale 0.5: 160 x 13: " .. tostring(root.Size))
	local winded = find(root, "Winded")
	local limit = winded:FindFirstChildOfClass("UITextSizeConstraint")
	check(limit and limit.MinTextSize == 12, "opts.Touch floors WINDED at 12 px")
	check(winded.TextSize == 12, "and the solve lands on the floor, not 7 px: " .. tostring(winded.TextSize))
	local plain = Hud.Mount("HUD_PC", "StaminaBar", Hud.Gui(), {Scale = 0.5})
	check(find(plain, "Winded"):FindFirstChildOfClass("UITextSizeConstraint") == nil, "without opts.Touch: no floor")
	check(find(ctx.Templates.HUD_PC, "StaminaBar/Winded"):FindFirstChildOfClass("UITextSizeConstraint") == nil,
		"the template gets no constraint")
end

do -- a template with no Fill: nothing is re-anchored
	local ctx, Hud = fresh()
	local marker = Hud.Mount("HUD_PC", "NoiseMarker", Hud.Gui())
	ctx:Flush()
	local seen = 0
	for _, node in ipairs(marker:GetDescendants()) do
		if node:IsA("GuiObject") then
			seen += 1
			check(node.AnchorPoint.X == 0.5 and node.AnchorPoint.Y == 0.5, "NoiseMarker keeps its anchors: " .. node.Name)
		end
	end
	check(seen == 3, "Soft, Dot and Label were all looked at: " .. seen)
end

do -- a place where the bundle was never imported
	local ctx, Hud = fresh({skip = {HUD_Touch = true}})
	check(Hud.Mount("HUD_Touch", "DetectorLine", Hud.Gui()) == nil, "a missing bundle mounts nothing")
	check(ctx:Warned("[RoundHud] missing template: HUD_Touch/DetectorLine") == 1, "and warns by path")
end

-- == Attention: the C visibility rule ========================================================
do
	local ctx, Hud = fresh()
	local group, att = Hud.Mount("HUD_PC", "NoiseMarker", Hud.Gui(), {Attention = {Hold = 6, Rest = 0.45}})
	att:Show("SNEAKING")
	check(group.Visible and near(opacity(group), 1), "on change: 100 %")
	check(ctx:LastTween(group).Time == 0.18, "fades in over 0.18 s")
	ctx:Advance(5.9)
	check(near(opacity(group), 1), "still 100 % at 5.9 s")
	ctx:Advance(0.1)
	check(near(opacity(group), 0.45), "rests at 45 % after 6 s: " .. opacity(group))
	check(ctx:LastTween(group).Time == 0.4, "fades out over 0.4 s")
	att:Show("SNEAKING")
	check(near(opacity(group), 0.45), "an unchanged key does not wake it")
	att:Show("LOUD", false, 0.6)
	check(near(opacity(group), 1), "a changed key: 100 % again")
	ctx:Advance(6)
	check(near(opacity(group), 0.6), "a per-call rest (LOUD 60 %)")
	att:Show("A")
	ctx:Advance(3)
	att:Show("B")
	ctx:Advance(3.5)
	check(near(opacity(group), 1), "the first change's timer does not dim the second")
	ctx:Advance(2.5)
	check(near(opacity(group), 0.45), "the second change rests 6 s after itself")
	att:Show("DANGER", true)
	ctx:Advance(60)
	check(group.Visible and near(opacity(group), 1), "urgent never dims")
	att:Show("DANGER", false)
	check(near(opacity(group), 0.45), "no longer urgent, hold long over: rests at once")
	att:Show("DANGER", true)
	check(near(opacity(group), 1), "turning urgent again brings it back to 100 %")
	att:Hide()
	check(near(opacity(group), 0) and group.Visible, "Hide fades out, still drawn during the fade")
	ctx:Advance(0.4)
	check(group.Visible == false, "and is hidden after it")
	att:Show("DANGER")
	check(group.Visible and near(opacity(group), 1), "after Hide the same key is a change")
	att:Hide()
	ctx:Advance(0.2)
	att:Show("X")
	ctx:Advance(0.3)
	check(group.Visible and near(opacity(group), 1), "a Show inside the fade-out wins over the hide")
end

do -- rest 0: hidden at rest, not a ghost (BUILD-PLAN 1.3)
	local ctx, Hud = fresh()
	local group, att = Hud.Mount("HUD_PC", "DetectorCard", Hud.Gui(), {Attention = {Hold = 4, Rest = 0}})
	att:Show("k")
	ctx:Advance(3.99)
	check(near(opacity(group), 1), "100 % through the hold")
	ctx:Advance(0.01)
	check(near(opacity(group), 0), "rest 0 fades out after the hold")
	ctx:Advance(0.4)
	check(group.Visible == false, "rest 0 is hidden")
	att:Show("k")
	check(group.Visible == false, "the same key stays hidden")
end

do -- ReduceFlashing is irrelevant: the same opacities for true, false and nil
	local seen = {}
	for index, value in ipairs({true, false, "nil"}) do
		local ctx, Hud = fresh()
		if value ~= "nil" then ctx.Player:SetAttribute("ReduceFlashing", value) end
		local group, att = Hud.Mount("HUD_PC", "NoiseMarker", Hud.Gui(), {Attention = {Hold = 6, Rest = 0.45}})
		att:Show("a")
		local on = opacity(group)
		ctx:Advance(6)
		seen[index] = on .. "/" .. opacity(group) .. "/" .. ctx:LastTween(group).Time
	end
	check(seen[1] == seen[2] and seen[2] == seen[3], "ReduceFlashing changes nothing: " .. table.concat(seen, " "))
end

-- == Keycap ==================================================================================
do
	local ctx, Hud = fresh()
	local widget = Hud.Mount("HUD_PC", "FlashlightWidget", Hud.Gui())
	local chip = find(widget, "KeyChip")
	local key = find(chip, "Key")
	Hud.Keycap(chip, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
	check(chip.Visible and key.Text == "F", "keyboard: the key letter")
	local glyph = find(chip, "GlyphSlot"):FindFirstChildWhichIsA("ImageLabel", true)
	check(glyph == nil or not glyph.Visible, "keyboard: no glyph image")
	ctx:Device({GamepadEnabled = true, LastInput = "Gamepad"})
	glyph = find(chip, "GlyphSlot"):FindFirstChildWhichIsA("ImageLabel", true)
	check(glyph and glyph.Visible and glyph.Image == "rbxasset://textures/ui/Controls/xboxButtonR1.png",
		"gamepad: the engine glyph in GlyphSlot, re-applied on UIDevice.Changed")
	check(key.Text == "", "gamepad: the letter gives way to the glyph")
	ctx:Device({LastInput = "Keyboard"})
	check(key.Text == "F" and not glyph.Visible, "back on the keyboard: the letter, no glyph")
	ctx:Device({Touch = true})
	check(chip.Visible == false, "touch: the keycap is hidden")
	ctx:Device({Touch = false})
	check(chip.Visible and key.Text == "F", "leaving touch brings it back")
	ctx:Device({NoGlyph = true, LastInput = "Gamepad"})
	check(chip.Visible and key.Text == "R1", "no engine glyph: the short button name, never blank: " .. key.Text)
	ctx:Device({NoGlyph = false, GamepadOnly = true})
	local leave = find(Hud.Mount("HUD_PC", "LeaveChipWide", Hud.Gui()), "KeyChip")
	Hud.Keycap(leave, Enum.KeyCode.L)
	check(leave.Visible == false, "a gamepad-only device hides a keyboard-only keycap")
	check(chip.Visible and key.Text == "", "while a keycap with a pad binding shows its glyph")
	ctx:Device({GamepadOnly = false, LastInput = "Keyboard"})
	check(leave.Visible and find(leave, "Key").Text == "L", "a keyboard brings the keyboard-only keycap back")
	Hud.Keycap(chip, "Esc", Enum.KeyCode.ButtonB)
	check(key.Text == "Esc", "a string key is written as given")
	Hud.Keycap(chip, Enum.KeyCode.Q)
	ctx:Device({})
	check(key.Text == "Q", "a re-bound chip keeps its newest keys across Changed")
	Hud.Keycap(chip, Enum.KeyCode.LeftShift)
	check(key.Text == "LeftShift", "a key with no printable string falls back to its name")
	widget:Destroy()
	ctx:Device({LastInput = "Gamepad"})
	check(true, "a destroyed chip is skipped on Changed")
end

-- == Detector card (09 C) ====================================================================
do
	local ctx, Hud = fresh()
	ctx.Now = 100
	Hud.Detector("MEDIUM", 130)
	ctx:Flush()
	local gui = Hud.Gui()
	local card = gui:FindFirstChild("DetectorCard")
	check(card and card.ClassName == "CanvasGroup", "the reading mounts HUD_PC/DetectorCard into RoundHud")
	check(gui.DisplayOrder == 10, "at DisplayOrder 10, no longer 1100")
	check(card.Visible and near(opacity(card), 1), "a reading shows at 100 %")
	check(find(card, "Reading").Text == "SCAN " .. B .. " MEDIUM", "MEDIUM reads SCAN . MEDIUM")
	check(find(card, "Reading").TextColor3 == P.Amber, "MEDIUM is Amber")
	check(find(card, "Headline").Text == "ENTITY NEARBY", "MEDIUM means ENTITY NEARBY")
	check(find(card, "Seconds").Text == "30 s", "the seconds left: " .. find(card, "Seconds").Text)
	check(find(card, "Bars/Bar1").BackgroundColor3 == P.Amber and find(card, "Bars/Bar2").BackgroundColor3 == P.Amber
		and find(card, "Bars/Bar3").BackgroundColor3 == P.Line, "MEDIUM lights two Amber bars")
	ctx:Advance(1.5)
	check(find(card, "Seconds").Text == "29 s", "the seconds count down: " .. find(card, "Seconds").Text)
	ctx:Advance(2.4)
	check(near(opacity(card), 1), "100 % for 4 s")
	ctx:Advance(0.1)
	check(near(opacity(card), 0), "then it fades")
	ctx:Advance(0.4)
	check(card.Visible == false, "and hides (rest is hidden, not a ghost)")
	Hud.Detector("MEDIUM", 130)
	check(card.Visible == false, "the same reading re-sent does not wake it")
	Hud.Detector("HIGH", 130)
	check(card.Visible and near(opacity(card), 1), "a changed reading shows again")
	check(find(card, "Reading").Text == "SCAN " .. B .. " HIGH" and find(card, "Reading").TextColor3 == P.Coral,
		"HIGH is Coral")
	check(find(card, "Headline").Text == "ENTITY VERY CLOSE", "HIGH means ENTITY VERY CLOSE")
	for index = 1, 3 do
		check(find(card, "Bars/Bar" .. index).BackgroundColor3 == P.Coral, "HIGH lights all three bars Coral")
	end
	ctx:Advance(20)
	check(card.Visible and near(opacity(card), 1), "HIGH never dims")
	ctx:Advance(5.5)
	check(find(card, "Seconds").Text == "1 s", "one second left: " .. find(card, "Seconds").Text)
	ctx:Advance(0.1)
	check(near(opacity(card), 0), "the reading ends at expiresAt")
	ctx:Advance(0.4)
	check(card.Visible == false, "and the card is gone")
	ctx:Advance(10)
	check(card.Visible == false, "nothing comes back after expiry")
	Hud.Detector("LOW", ctx.Now + 30)
	check(card.Visible and near(opacity(card), 1), "a fresh scan shows again")
	check(find(card, "Reading").TextColor3 == P.Sage and find(card, "Headline").Text == "SAFE DISTANCE", "LOW is Sage, SAFE DISTANCE")
	check(find(card, "Bars/Bar1").BackgroundColor3 == P.Sage and find(card, "Bars/Bar2").BackgroundColor3 == P.Line,
		"LOW lights one Sage bar")
	Hud.Detector(nil)
	ctx:Advance(0.4)
	check(card.Visible == false, "Detector(nil) hides it")
	Hud.Detector("BOGUS", ctx.Now + 30)
	check(card.Visible == false, "an unknown reading draws nothing")
	Hud.Detector("LOW", ctx.Now - 1)
	check(card.Visible == false, "an already expired reading draws nothing")
	check(#gui:GetChildren() == 1, "one detector card, reused")
end

do -- placement: above the SCAN chip on PC, re-fitted on UIDevice.Changed
	local ctx, Hud = fresh({safe = {Left = 0, Top = 0, Right = 1920, Bottom = 1022, Width = 1920, Height = 1022}})
	Hud.Detector("LOW", 30)
	local card = Hud.Gui():FindFirstChild("DetectorCard")
	check(card.AnchorPoint.X == 0 and card.AnchorPoint.Y == 1, "the PC card hangs above its anchor")
	check(card.Position == UDim2.fromOffset(24, 1022 - 148), "no SCAN chip: above the kit row and its refusal-tag band: " .. tostring(card.Position))
	local protection = newInstance("ScreenGui", "ProtectionHUD")
	protection.Parent = ctx.PlayerGui
	local panel = Hud.Mount("HUD_PC", "EquipmentPanel", protection)
	local scan = find(panel, "Chip_Scan")
	scan.AbsolutePosition = Vector2.new(400, 930)
	ctx:Device({})
	check(card.Position == UDim2.fromOffset(400, 890), "above the SCAN chip, clear of the refusal-tag band (930 - 8 - 24 - 8): " .. tostring(card.Position))
	scan.Visible = false
	ctx:Advance(1)
	check(card.Position == UDim2.fromOffset(24, 874), "a hidden SCAN chip: back above the kit row")
	ctx:Device({Safe = {Left = 40, Top = 0, Right = 1880, Bottom = 1000, Width = 1840, Height = 1000}})
	check(card.Position == UDim2.fromOffset(64, 852), "a moved safe area re-fits on UIDevice.Changed")
end

do -- touch: one line in the feed lane; a device flip remounts
	local ctx, Hud = fresh({touch = true, viewport = Vector2.new(844, 390),
		safe = {Left = 47, Top = 0, Right = 797, Bottom = 311, Width = 750, Height = 311}})
	Hud.Detector("HIGH", 30)
	local card = Hud.Gui():FindFirstChild("DetectorCard")
	local line = card and find(card, "Line")
	check(line ~= nil, "touch mounts HUD_Touch/DetectorLine as DetectorCard")
	check(line.Text == "SCAN " .. B .. " HIGH " .. B .. " ENTITY VERY CLOSE", "the touch line: " .. line.Text)
	check(line.TextColor3 == P.Coral, "coloured by the reading")
	check(find(card, "Reading") == nil and find(card, "Headline") == nil, "the line replaces the three PC texts")
	check(line:FindFirstChildOfClass("UITextSizeConstraint").MinTextSize == 12, "never under 12 px")
	check(card.Size == UDim2.fromOffset(358, 24), "358x24")
	check(card.AnchorPoint.Y == 0 and card.Position == UDim2.fromOffset(47 + 68, 52), "in the feed lane, under the feed")
	ctx:Device({Touch = false})
	local pc = Hud.Gui():FindFirstChild("DetectorCard")
	check(pc ~= card and card.Parent == nil and find(pc, "Headline") ~= nil, "a flip to PC remounts the PC card")
	check(pc.Visible and near(opacity(pc), 1), "and keeps showing the HIGH reading")
	check(#Hud.Gui():GetChildren() == 1, "one detector card at a time")
end

do -- a place without HUD_Touch: nothing drawn, one warning, the countdown still ends
	local ctx, Hud = fresh({touch = true, skip = {HUD_Touch = true}})
	Hud.Detector("MEDIUM", 5)
	check(Hud.Gui():FindFirstChild("DetectorCard") == nil, "no template: nothing drawn")
	ctx:Advance(6)
	check(ctx:Warned("[RoundHud] missing template: HUD_Touch/DetectorLine") == 1, "warned by path, once")
end

-- == Clear ===================================================================================
do
	local ctx, Hud = fresh()
	Hud.Detector("HIGH", 30)
	check(Hud.Gui():FindFirstChild("DetectorCard") ~= nil, "a reading is drawn")
	Hud.Clear()
	check(Hud.Gui():FindFirstChild("DetectorCard") == nil, "Clear removes the detector card")
	ctx:Advance(40)
	check(Hud.Gui():FindFirstChild("DetectorCard") == nil, "no pending tick draws it again")
	Hud.Clear()
	check(Hud.Gui().Parent == ctx.PlayerGui, "Clear is idempotent and keeps the RoundHud gui")
	Hud.Detector("LOW", ctx.Now + 30)
	local card = Hud.Gui():FindFirstChild("DetectorCard")
	check(card and card.Visible and near(opacity(card), 1), "the next reading mounts afresh")
end

do -- K17 (HUD_B3; owner, 2026-10-08): Clear removes the module's own nodes, never a caller's Mount
	local ctx, Hud = fresh()
	local marker, att = Hud.Mount("HUD_PC", "NoiseMarker", Hud.Gui(), {Name = "NoiseMarker", Attention = {Hold = 6, Rest = 0.45}})
	att:Show("SNEAKING")
	Hud.Detector("HIGH", 30)
	Hud.Clear()
	ctx:Advance(1)
	check(Hud.Gui():FindFirstChild("DetectorCard") == nil, "the detector card goes")
	check(marker.Parent == Hud.Gui() and marker.Visible and near(opacity(marker), 1), "the caller's marker stays, as it was")
end

print("RoundHud: " .. checks .. " checks passed (offline Luau; real HUD_PC and HUD_Touch imports)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    source = SOURCES["RoundHud"].read_bytes()
    assert all(byte < 128 for byte in source), "RoundHud must be ASCII-only (install_new_scripts embeds it with json.dumps)"
    assert b"\r" not in source, "RoundHud must have LF line endings"
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    if Path(compiler).exists():
        subprocess.run([compiler, "--null", str(SOURCES["RoundHud"])], check=True, capture_output=True)
    else:
        print("luau-compile not found; compile check skipped.")
    inject = "local SOURCES = {\n%s\n}\nlocal TREES = %s\n" % (
        ",\n".join("%s = %s" % (name, long_string(path.read_text(encoding="utf-8"))) for name, path in SOURCES.items()),
        lua(trees()))
    harness = HARNESS.read_text(encoding="utf-8")
    assert "--@@INJECT@@" in harness
    program = harness.replace("--@@INJECT@@", inject, 1) + "\n" + TESTS
    with tempfile.TemporaryDirectory(prefix="round-hud-") as directory:
        path = Path(directory) / "round_hud.luau"
        path.write_text(program, encoding="utf-8")
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or "checks passed" not in result.stdout:
        print(result.stdout.strip()[-4000:])
        print(result.stderr.strip()[-4000:])
        raise SystemExit("test_round_hud FAILED")
    print(result.stdout.strip().splitlines()[-1])


if __name__ == "__main__":
    main()
