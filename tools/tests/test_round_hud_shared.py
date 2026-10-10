"""B4/B5 shared HUD APIs over the actual PC, touch and screen Framewisp imports.

Runs production RoundHud, ShopBinder and Round HUD event driver in the HUD engine. Compile uses -O0
to expose register ceilings. Assertions cover semantic attention, authored Stack geometry, spectator
compass origin, transient pooling/dedupe, captions, round/modal gates, remount and retained loss data.
EXIT_COMPASS_20261010 (owner: "Make the compass marker to the exit more distinct."): a locked GET OUT
wears the exit look (UIStyle.Hud.Exit, "EXIT 23 m", text outline, facing cue with hysteresis, three
arrival swells and none under ReduceFlashing, an every-Heartbeat needle, the QA stamps
HudExit/HudFacing/HudBearing, and on touch the compass pinned under the collapsed bar behind its fit
guard), and every other compass state is written exactly as before, including after an exit.
Real fonts, masks and pad hit routing still require Studio QA; so does how the green and the swell read
on a lit wall.
"""

import ast
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_round_hud import DUMPS, HARNESS, ROOT, SOURCES, long_string, lua, trees

TESTS = r'''
local function live(ctx, who, position)
	who = who or ctx.Player
	who:SetAttribute("InRound", true)
	local character = newInstance("Model", "Character")
	local hum = newInstance("Humanoid", "Humanoid")
	hum.Health, hum.Parent = 100, character
	local root = newInstance("Part", "HumanoidRootPart")
	root.Position, root.Parent = position or Vector3.new(), character
	who.Character = character
	ctx.Workspace:SetAttribute("RoundActive", true)
	ctx.Workspace:SetAttribute("SelectedLevel", 3)
	ctx.Workspace.CurrentCamera = {CFrame = {LookVector = Vector3.new(0, 0, -1)}}
	return root, hum
end
local function start(opts)
	local ctx = context(opts)
	live(ctx)
	return ctx, ctx:Require("RoundHud"), ctx:Require("ShopBinder").Palette
end
local function state(change)
	local value = {Level = 3, Title = "FIND THE CDS", Count = 2, Goal = 5, Tag = "CDS IN THE PLAYER",
		Lines = {"Follow the compass to the next CD."}, Compass = {State = "locked", Target = Vector3.new(0, 0, -35.71)}}
	for key, item in pairs(change or {}) do value[key] = item end
	return value
end
local function part(ctx, path) return find(ctx.Hud.Gui():FindFirstChild("ObjectiveCard"), path) end
local function card(ctx) return ctx.Hud.Gui():FindFirstChild("ObjectiveCard") end
local function opacity(root) return root.Visible and 1 - root.GroupTransparency or 0 end
local function beat(ctx, seconds)
	ctx:Advance(seconds or 0.1)
	ctx.RunService.Heartbeat:Fire(seconds or 0.1)
	ctx:Flush()
end
local function tweens(ctx, root)
	local count = 0
	for _, tween in ipairs(ctx.Tweens) do if tween.Instance == root then count += 1 end end
	return count
end
local function row(ctx, index) return ctx.Hud.Gui():FindFirstChild("FeedRow" .. (index or 1)) end
local function text(root, path) local node = find(root, path); return node and node.Text end

do -- Stack clones current fixture geometry and changes height without scaling any part's text.
	local ctx, Hud = start()
	ctx.Hud = Hud
	local root, parts = Hud.Stack("HUD_Screens", "DeathCause", Hud.Gui(), {Name = "DeathCause"})
	ctx:Flush()
	check(root and parts.Head and parts.Cause and parts.Advice, "real death stack parts")
	local height, adviceHeight = root.Size.Y.Offset, parts.Advice.Size.Y.Offset
	local titleSize = find(parts.Head, "DeathCauseTitle").TextSize
	parts.Advice.Visible = false
	ctx:Flush()
	check(root.Size.Y.Offset == height - adviceHeight, "hidden Advice closes its full gap")
	check(find(parts.Head, "DeathCauseTitle").TextSize == titleSize, "stack reflow never rescales title")
	parts.Advice.Visible = true
	ctx:Flush()
	check(root.Size.Y.Offset == height, "Advice restores authored fixed height")
	local results, p = Hud.Stack("HUD_Screens", "ResultsTouch", Hud.Gui(), {Name = "ResultsTouch"})
	ctx:Flush()
	local removed = 0
	local roster = newInstance("ScrollingFrame", "PartyChoices")
	roster.Size, roster.LayoutOrder = UDim2.fromOffset(results.Size.X.Offset, 88), 3
	for index = 1, 6 do removed += p["PartyChoice" .. index].Size.Y.Offset; p["PartyChoice" .. index].Parent = roster end
	local before = results.Size.Y.Offset
	roster.Parent = results
	ctx:Flush()
	check(results.Size.Y.Offset == before - removed + 88, "dynamic roster replaces the six imported rows in current flow")
	roster.Size = UDim2.fromOffset(results.Size.X.Offset, 44)
	ctx:Flush()
	check(results.Size.Y.Offset == before - removed + 44, "dynamic ScrollingFrame height is measured")
	check(p.Footer.Position.Y.Offset == p.Head.Size.Y.Offset + p.Party.Size.Y.Offset + 44,
		"footer follows bounded roster: " .. p.Footer.Position.Y.Offset)
	local fill = find(p.Head, "Stat_Counter")
	check(fill ~= nil, "actual nested stat Items retained")
	local ringSlot = newInstance("Frame", "RingSlot")
	ringSlot.Parent = Hud.Gui()
	local ring = Hud.Ring(ringSlot)
	ring(0.25, Color3.fromRGB(1, 2, 3))
	check(ringSlot.SweepHalf1.Visible and not ringSlot.SweepHalf2.Visible, "quarter sweep uses only first mask")
	ring(0.75)
	check(ringSlot.SweepHalf1.Visible and ringSlot.SweepHalf2.Visible, "three quarters use both masks")
	ring(2)
	check(ringSlot.SweepHalf2:FindFirstChildWhichIsA("UIGradient", true).Rotation == 180, "ring fraction clamps at one")
	ring(0/0)
	check(not ringSlot.SweepHalf1.Visible and not ringSlot.SweepHalf2.Visible, "invalid/cancel fraction resets masks")
end

do -- PC objective authoring, semantic attention and optional part closure.
	local ctx, Hud, P = start()
	ctx.Hud = Hud
	check(Hud.SetObjective(state()), "matching live receiver accepted")
	ctx:Flush()
	local root = card(ctx)
	check(root and root.Size.X.Offset == 288 and opacity(root) == 1, "one expanded80percent PC card")
	check(root:FindFirstChildWhichIsA("GuiObject").BackgroundTransparency == 1,
		"pointer objective backing removed without hiding the card")
	check(find(ctx.Templates.HUD_PC, "ObjectiveCard").BackgroundTransparency == 0,
		"pointer backing override leaves imported source intact")
	local deadline = Hud.CaptureTestState().Objective.Attention.HoldUntil
	check(text(root, "Title") == "FIND THE CDS" and text(root, "Count") == "2/5", "objective dynamic slots")
	check(part(ctx, "Progress/Track/Fill").AnchorPoint.X == 0 and near(part(ctx, "Progress/Track/Fill").Size.X.Scale, 0.4),
		"Stack keeps Mount's left-anchored progress fill")
	check(part(ctx, "Eyebrow").TextColor3 == Color3.fromRGB(255, 0, 0), "Level3 accent")
	check(text(root, "Compass/Readout") == "10 m", "studs to metres")
	check(text(root, "Compass/Chevron") == "\u{25BC}", "front bearing uses downward chevron")
	check(not Hud.SetObjective(nil) and not Hud.SetObjective(state({Level = 2})), "inactive nil and wrong level ignored")
	check(card(ctx) == root and text(root, "Title") == "FIND THE CDS", "inactive publishers cannot erase card")
	beat(ctx, 5.9)
	check(opacity(root) == 1, "ordinary six-second attention held")
	beat(ctx, 0.1)
	check(opacity(root) == 1 and not Hud.CaptureTestState().Objective.Attention.Held
		and Hud.CaptureTestState().Objective.Attention.HoldUntil == deadline,
		"ordinary remains opaque after original six-second hold expires")
	local n = tweens(ctx, root)
	Hud.SetObjective(state({Compass = {State = "locked", Target = Vector3.new(10, 0, -35.71)}}))
	ctx:Flush()
	check(tweens(ctx, root) == n and opacity(root) == 1
		and Hud.CaptureTestState().Objective.Attention.HoldUntil == deadline,
		"live target/bearing changes do not restart attention")
	Hud.SetObjective(state({Count = 3}))
	ctx:Flush()
	check(opacity(root) == 1 and text(root, "Count") == "3/5"
		and Hud.CaptureTestState().Objective.Attention.HoldUntil > deadline, "counter semantic change renews hold")
	Hud.SetObjective(state({Status = {Text = "Main breaker: fuse42s", Kind = "warning"}}))
	deadline = Hud.CaptureTestState().Objective.Attention.HoldUntil
	beat(ctx, 6)
	check(opacity(root) == 1 and part(ctx, "StatusRow/Label").TextColor3 == P.Amber, "warning remains opaque and paints Amber")
	n = tweens(ctx, root)
	Hud.SetObjective(state({Status = {Text = "Main breaker: fuse36s", Kind = "warning"}}))
	ctx:Flush()
	check(tweens(ctx, root) == n and Hud.CaptureTestState().Objective.Attention.HoldUntil == deadline,
		"countdown-only copy does not restart attention")
	Hud.SetObjective(state({Status = {Text = "The water is no longer safe.", Kind = "danger"}}))
	beat(ctx, 8)
	check(opacity(root) == 1 and part(ctx, "StatusRow/Label").TextColor3 == P.Coral, "danger stays bright")
	Hud.SetObjective(state({Done = true}))
	ctx:Flush()
	check(part(ctx, "Count").TextColor3 == P.RailTeal and part(ctx, "Progress/Track/Fill").BackgroundColor3 == P.RailTeal,
		"done counter/fill turn RailTeal in attention window")
	beat(ctx, 6)
	check(part(ctx, "Count").TextColor3 == P.Cream, "done tint returns after six-second window")
	Hud.SetObjective({Level = 3, Title = "GET OUT", Lines = {}})
	ctx:Flush()
	check(not part(ctx, "Counter").Visible and not part(ctx, "Progress").Visible
		and not part(ctx, "Guide1").Visible and not part(ctx, "StatusRow").Visible and not part(ctx, "Compass").Visible,
		"absent optional parts close completely")
	check(root.Size.Y.Offset == part(ctx, "Head").Size.Y.Offset, "optional rows reserve zero height")
	check(Hud.LastObjective().Counter == nil, "no fabricated loss counter for exit")
end

do -- Compass front, edge clamp, behind, static states, exit-only arrival and watched origin.
	local ctx, Hud, P = start()
	ctx.Hud = Hud
	local function compass(target, title, mode)
		Hud.SetObjective(state({Title = title or "FIND THE CDS", Compass = {State = mode or "locked", Target = target}}))
		ctx:Flush()
		return part(ctx, "Compass/Chevron"), part(ctx, "Compass/Readout")
	end
	local right = compass(Vector3.new(100, 0, 0))
	local rightX = right.Position.X.Scale
	check(right.Text == "\u{25B6}", "right behind target clamps right")
	local left = compass(Vector3.new(-100, 0, 0))
	check(left.Text == "\u{25C0}" and left.Position.X.Scale < rightX, "left behind target clamps left")
	local _, readout = compass(Vector3.new(0, 100, -3.571))
	check(readout.Text == "28 m", "distance includes vertical separation while bearing remains planar")
	-- EXIT_COMPASS_20261010 (owner: "Make the compass marker to the exit more distinct."): a locked
	-- GET OUT names what it points at ("EXIT 28 m", was "28 m") and arrives in UIStyle.Hud.Exit,
	-- the door's green (was RailTeal). The CD readouts either side are unchanged.
	local Exit = ctx:Require("UIStyle").Hud.Exit
	_, readout = compass(Vector3.new(0, 100, -3.571), "GET OUT")
	check(readout.Text == "EXIT 28 m", "different-floor exit cannot arrive from planar proximity")
	_, readout = compass(Vector3.new(0, 0, -3.571))
	check(readout.Text == "1 m", "near CD remains metre distance rather than exit arrival")
	_, readout = compass(Vector3.new(0, 0, -3.571), "GET OUT")
	check(readout.Text == "AT THE EXIT" and readout.TextColor3 == Exit, "GET OUT under8m arrives")
	local chevron
	chevron, readout = compass(nil, nil, "inRoom")
	check(chevron.TextColor3 == P.Coral and readout.Text == "IN THIS ROOM", "same-room static Coral")
	chevron, readout = compass(nil, "GET OUT", "calibrating")
	check(chevron.Text == "\u{25BC}" and readout.Text == "CALIBRATING", "calibrating retains bounded bearing symbol plus state copy")
	local watched = newInstance("Player", "AnnaUser")
	watched.UserId, watched.DisplayName = 2, "Anna"
	table.insert(ctx.Players.Members, watched)
	local watchedRoot = live(ctx, watched, Vector3.new(0, 0, -100))
	ctx.Player:SetAttribute("Spectating", true)
	ctx.Player:SetAttribute("SpectateTargetUserId", 2)
	compass(Vector3.new(0, 0, -135.71))
	check(text(card(ctx), "Compass/Readout") == "10 m", "spectator distance uses watched root")
	check(text(card(ctx), "Eyebrow") == "WATCHING ANNA \u{B7} LEVEL3" or text(card(ctx), "Eyebrow") == "WATCHING ANNA \u{B7} LEVEL 3",
		"spectator eyebrow uses DisplayName")
	ctx.Player:SetAttribute("SpectateTargetUserId", 999)
	beat(ctx, 0.5)
	check(not card(ctx).Visible, "invalid watched target hides instead of using parked body")
	check(not Hud.SetObjective(state()), "invalid watched publisher cannot replace snapshot")
	ctx.Player:SetAttribute("SpectateTargetUserId", 2)
	beat(ctx, 0.1)
	check(card(ctx).Visible, "valid watched target restores existing state")
	watched:SetAttribute("Level3_Hiding", true)
	beat(ctx, 0.5)
	check(not card(ctx).Visible, "watched Level3 hiding excludes objective")
	watched:SetAttribute("Level3_Hiding", false)
	ctx.Player:SetAttribute("LevelLoadingOpen", true)
	beat(ctx, 0.5)
	check(not card(ctx).Visible, "loading gate excludes objective")
end

do -- Native font fallback can be wider/taller than the imported ASCII sample without moving art.
	for _, touch in ipairs({false, true}) do
		local ctx, Hud = start({touch = touch})
		ctx.Hud = Hud
		Hud.SetObjective(state())
		ctx:Flush()
		local chevron = part(ctx, "Compass/Chevron")
		local size, anchor, y = chevron.Size, chevron.AnchorPoint, chevron.Position.Y
		chevron.FakeAdvance, chevron.FakeEmHeight = 2, 1.8
		for _, data in ipairs({{State = "locating"}, {State = "calibrating"}, {State = "inRoom"},
			{State = "locked", Target = Vector3.new(-100, 0, 0)}, {State = "locked", Target = Vector3.new(100, 0, 0)}}) do
			Hud.SetObjective(state({Compass = data}))
			ctx:Flush() -- includes Binder's deferred Text/resize solve, not just the synchronous render.
			check(chevron.TextBounds.X <= chevron.AbsoluteSize.X + 0.01
				and chevron.TextBounds.Y <= chevron.AbsoluteSize.Y + 0.01, "wide/tall fallback bearing glyph fits: " .. data.State)
			check(chevron.Size == size and chevron.AnchorPoint == anchor
				and chevron.Position.Y.Scale == y.Scale and chevron.Position.Y.Offset == y.Offset,
				"native glyph fit preserves imported size/anchor/y: " .. data.State)
		end
		check(chevron.TextSize >= 12 and part(ctx, "Compass/Readout").TextSize >= 12,
			"nominal symbol size and readable compass copy retain touch floor")
		local template = ctx.Templates:FindFirstChild(touch and "HUD_Touch" or "HUD_PC")
		local source = find(template, (touch and "ObjectivePill" or "ObjectiveCard") .. "/Compass/Chevron")
		check(source.Text == "v" and source:GetAttribute("FigmaFontSize") ~= nil and not source.TextScaled,
			"glyph fit never rewrites source template")
	end
end

do -- EXIT_COMPASS_20261010: a locked GET OUT wears the exit look; every other compass state is as it was.
	local ctx, Hud, P = start()
	ctx.Hud = Hud
	local Exit, Accent = ctx:Require("UIStyle").Hud.Exit, Color3.fromRGB(255, 0, 0)
	local Strip = Color3.fromRGB(61, 142, 89) -- 45 % of the way from Line (38,49,52) to the exit green
	check(Exit == Color3.fromRGB(90, 255, 135), "UIStyle.Hud.Exit is the exit door's header green")
	local function set(change) Hud.SetObjective(state(change)); ctx:Flush() end
	local function at(degrees, studs) -- a point `degrees` right of dead ahead for the fixture camera
		local r = math.rad(degrees)
		return Vector3.new(math.sin(r) * (studs or 100), 0, -math.cos(r) * (studs or 100))
	end
	local function exitAt(target) set({Title = "GET OUT", Compass = {State = "locked", Target = target}}) end
	local function stamps(row) return row:GetAttribute("HudExit"), row:GetAttribute("HudFacing"), row:GetAttribute("HudBearing") end
	set()
	local row, chevron, readout = part(ctx, "Compass"), part(ctx, "Compass/Chevron"), part(ctx, "Compass/Readout")
	local centre, baseline = part(ctx, "Compass/Centre"), part(ctx, "Compass/Baseline")
	local was = {Centre = centre.BackgroundColor3, Baseline = baseline.BackgroundColor3, Nodes = #row:GetDescendants(),
		StrokeColor = readout.TextStrokeColor3, Stroke = readout.TextStrokeTransparency}
	check(was.Centre == P.Cream and was.Baseline == P.Line, "fixture: the import draws a Cream centre line on a Line baseline")
	check(chevron.TextColor3 == Accent and readout.TextColor3 == P.Sage and readout.Text == "10 m"
		and stamps(row) == nil, "a CD compass keeps the level accent and carries no exit stamp")
	check(chevron.TextStrokeTransparency ~= 0.35 and readout.TextStrokeTransparency ~= 0.35
		and chevron.TextStrokeColor3 ~= P.Ink and readout.TextStrokeColor3 ~= P.Ink, "and no outline")

	exitAt(at(45, 50.5))
	check(readout.Text == "EXIT 14 m" and readout.TextColor3 == P.Cream, "exit readout names what it points at, in Cream")
	check(chevron.Text == "\u{25BC}" and chevron.TextColor3 == Exit, "exit chevron is the door's green, not the level accent")
	check(baseline.BackgroundColor3 == Strip and centre.BackgroundColor3 == was.Centre,
		"strip baseline leans to the green; centre line untouched while not facing")
	for _, label in ipairs({chevron, readout}) do
		check(label.TextStrokeColor3 == P.Ink and label.TextStrokeTransparency == 0.35,
			"Ink outline through the TextLabel's own stroke: " .. label.Name)
		check(label:FindFirstChildOfClass("UIStroke") == nil, "never a UIStroke (UIRegression would measure the whole box): " .. label.Name)
	end
	check(#row:GetDescendants() == was.Nodes, "exit look adds no node under the Compass row")
	local isExit, facing, bearing = stamps(row)
	check(isExit == true and facing == false and bearing == 45, "QA stamps: exit, not facing, 45 degrees right")

	exitAt(at(10))
	check(select(2, stamps(row)) == false and centre.BackgroundColor3 == was.Centre, "10 degrees off is not yet facing")
	exitAt(at(5))
	check(select(2, stamps(row)) == true and centre.BackgroundColor3 == Exit and readout.TextColor3 == Exit
		and readout.Text == "EXIT 28 m", "facing the exit turns the centre line and readout green")
	exitAt(at(10))
	isExit, facing, bearing = stamps(row)
	check(facing == true and bearing == 10 and centre.BackgroundColor3 == Exit, "facing holds out to 12 degrees once found")
	exitAt(at(15))
	check(select(2, stamps(row)) == false and centre.BackgroundColor3 == was.Centre and readout.TextColor3 == P.Cream,
		"turning away gives the centre line and readout back")
	exitAt(at(100))
	check(chevron.Text == "\u{25B6}" and chevron.TextColor3 == Exit and select(3, stamps(row)) == 100,
		"an exit behind still pins the green glyph at the strip's end")
	exitAt(at(40, 20))
	check(readout.Text == "AT THE EXIT" and readout.TextColor3 == Exit and select(2, stamps(row)) == false,
		"arrival reads AT THE EXIT in the door's green without facing it")

	local function restored(description)
		check(centre.BackgroundColor3 == was.Centre and baseline.BackgroundColor3 == was.Baseline,
			description .. ": centre line and baseline are the import's again")
		for _, label in ipairs({chevron, readout}) do
			check(label.TextStrokeColor3 == was.StrokeColor and label.TextStrokeTransparency == was.Stroke,
				description .. ": outline removed from " .. label.Name)
		end
		check(stamps(row) == nil and select(2, stamps(row)) == nil and select(3, stamps(row)) == nil,
			description .. ": exit stamps cleared")
	end
	set({Title = "GET OUT", Compass = {State = "calibrating", Target = at(0)}})
	check(readout.Text == "CALIBRATING" and readout.TextColor3 == P.Sage and chevron.TextColor3 == Accent,
		"a GET OUT that is still calibrating is not the exit look")
	restored("calibrating")
	exitAt(at(5))
	set({Compass = {State = "inRoom"}})
	check(chevron.TextColor3 == P.Coral and readout.Text == "IN THIS ROOM" and readout.TextColor3 == P.Coral, "same-room Coral after an exit")
	restored("inRoom")
	exitAt(at(5))
	set()
	check(chevron.TextColor3 == Accent and readout.Text == "10 m" and readout.TextColor3 == P.Sage, "CD compass after an exit")
	restored("locked CD")
	exitAt(at(5))
	Hud.SetObjective({Level = 3, Title = "GET OUT", Lines = {}})
	ctx:Flush()
	check(not row.Visible, "a GET OUT without a compass hides the row")
	restored("hidden row")

	-- Arrival: three 1 Hz swells, then steady; once per exit; nothing swells under ReduceFlashing.
	local function whiter() return chevron.TextColor3 ~= Exit and chevron.TextColor3.R > Exit.R and chevron.TextColor3.G == Exit.G end
	exitAt(at(45))
	check(chevron.TextColor3 == Exit and baseline.BackgroundColor3 == Strip, "the swell starts from the steady look")
	beat(ctx, 0.5)
	check(whiter() and baseline.BackgroundColor3 == Exit, "half a second in: chevron toward white, strip at full green")
	check(readout.TextColor3 == P.Cream and centre.BackgroundColor3 == was.Centre, "the swell moves no other colour")
	beat(ctx, 0.5)
	check(chevron.TextColor3 == Exit and baseline.BackgroundColor3 == Strip, "each swell returns to the steady look")
	beat(ctx, 1.5)
	check(whiter(), "third swell at 2.5 s")
	beat(ctx, 0.5)
	check(chevron.TextColor3 == Exit and baseline.BackgroundColor3 == Strip, "steady after three swells")
	beat(ctx, 0.5)
	check(chevron.TextColor3 == Exit, "no fourth swell")
	exitAt(at(0))
	beat(ctx, 0.2)
	check(whiter() and readout.TextColor3 == Exit, "finding the exit gives one short swell")
	beat(ctx, 0.3)
	check(chevron.TextColor3 == Exit and baseline.BackgroundColor3 == Strip and centre.BackgroundColor3 == Exit,
		"which ends in the steady facing look")
	set()
	ctx.Player:SetAttribute("ReduceFlashing", true)
	exitAt(at(45))
	for _ = 1, 8 do
		beat(ctx, 0.25)
		check(chevron.TextColor3 == Exit and baseline.BackgroundColor3 == Strip, "ReduceFlashing: nothing swells on arrival")
	end
	exitAt(at(0))
	beat(ctx, 0.2)
	check(chevron.TextColor3 == Exit and centre.BackgroundColor3 == Exit, "ReduceFlashing: nor on facing; the steady cue remains")
	ctx.Player:SetAttribute("ReduceFlashing", false)
	set()
	exitAt(at(45))
	beat(ctx, 0.5)
	check(whiter(), "a new exit swells again: the clock is per exit, not per session")
	-- A swell is never joined or restarted in mid-phase (review, 2026-10-10). This exit is 0.5 s old.
	beat(ctx, 2.25)
	exitAt(at(0)) -- found at 2.75 s, inside the third arrival swell
	check(whiter() and centre.BackgroundColor3 == Exit and readout.TextColor3 == Exit,
		"found during the arrival swells: the steady facing cue is immediate")
	beat(ctx, 0.35)
	check(chevron.TextColor3 == Exit and baseline.BackgroundColor3 == Strip and centre.BackgroundColor3 == Exit,
		"and no facing swell takes over part-way up when the arrival swells end")
	exitAt(at(15))
	exitAt(at(0)) -- lost and found again, now that the arrival swells are over
	beat(ctx, 0.15)
	check(whiter(), "found after the arrival swells: one facing swell")
	exitAt(at(15)) -- overshoot past the cone ...
	beat(ctx, 0.15)
	exitAt(at(0)) -- ... and correct back, 0.3 s into that swell
	check(whiter() and centre.BackgroundColor3 == Exit, "overshoot and correct: the running swell is not cut back to green")
	beat(ctx, 0.1)
	check(chevron.TextColor3 == Exit and baseline.BackgroundColor3 == Strip,
		"nor started over: it ends 0.4 s after it began")
	Hud.Clear()
	exitAt(at(45))
	check(part(ctx, "Compass/Chevron") ~= chevron, "Clear remounted the card")
	row, chevron, readout = part(ctx, "Compass"), part(ctx, "Compass/Chevron"), part(ctx, "Compass/Readout")
	centre, baseline = part(ctx, "Compass/Centre"), part(ctx, "Compass/Baseline")
	beat(ctx, 0.5)
	check(whiter(), "Clear drops the swell clock with the round")

	-- The needle: every Heartbeat for a locked exit, the 0.1 s clock for everything else.
	beat(ctx, 3)
	local x = chevron.Position.X.Scale
	ctx.Workspace.CurrentCamera = {CFrame = {LookVector = Vector3.new(1, 0, 0)}} -- turned 90 degrees right
	ctx.RunService.Heartbeat:Fire(0.016)
	check(chevron.Position.X.Scale < x and select(3, stamps(row)) == -45, "exit needle follows the camera on the very next Heartbeat")
	ctx.Player.Character:FindFirstChildOfClass("Humanoid").Health = 0
	ctx.RunService.Heartbeat:Fire(0.016)
	check(readout.Text == "EXIT 28 m" and stamps(row) == true, "a subject that just died never flashes LOCATING between renders")
	beat(ctx, 0.1)
	check(not card(ctx).Visible, "the 0.1 s render then hides the card of a dead subject")
	ctx.Player.Character:FindFirstChildOfClass("Humanoid").Health = 100
	set()
	beat(ctx, 0.1)
	x = chevron.Position.X.Scale
	ctx.Workspace.CurrentCamera = {CFrame = {LookVector = Vector3.new(0, 0, -1)}}
	ctx.RunService.Heartbeat:Fire(0.016)
	check(card(ctx).Visible and chevron.Position.X.Scale == x, "every other locked compass keeps its 0.1 s clock")
	beat(ctx, 0.1)
	check(chevron.Position.X.Scale > x, "and still follows on it")

	-- The QA fixture can show the card with no living subject. A locked exit then has no bearing:
	-- it reads LOCATING like any other compass and may not keep any of the exit look.
	exitAt(at(5))
	check(stamps(row) == true and centre.BackgroundColor3 == Exit and readout.TextStrokeTransparency == 0.35,
		"dressed again on the remounted card")
	ctx.Workspace:SetAttribute("UIRegressionForceLevel3Reader", true)
	ctx.Player.Character:FindFirstChildOfClass("Humanoid").Health = 0
	beat(ctx, 0.1)
	check(card(ctx).Visible and readout.Text == "LOCATING" and chevron.TextColor3 == Accent and readout.TextColor3 == P.Sage,
		"fixture without a living subject: a locked exit has no bearing and reads LOCATING")
	restored("no bearing")
end

do -- EXIT_COMPASS_20261010: on touch a locked exit keeps its compass under the collapsed bar, if that fits.
	local EXIT = {Level = 3, Title = "GET OUT", Lines = {"Reach the revealed wall frame."},
		Compass = {State = "locked", Target = Vector3.new(35.71, 0, -35.71)}}
	local function phone(bottom)
		local ctx, Hud = start({touch = true, viewport = Vector2.new(844, 390),
			safe = {Left = 47, Top = 58, Right = 797, Bottom = bottom or 369}})
		ctx.Hud = Hud
		return ctx, Hud
	end
	local ctx, Hud = phone()
	Hud.SetObjective(EXIT)
	ctx:Flush()
	local root = card(ctx)
	local bar, line, compassRow = part(ctx, "Bar").Size.Y.Offset, part(ctx, "Guide1").Size.Y.Offset, part(ctx, "Compass").Size.Y.Offset
	check(part(ctx, "Compass").Visible and part(ctx, "Guide1").Visible and root.Size.Y.Offset == bar + line + compassRow,
		"expanded exit pill: bar, line and compass")
	beat(ctx, 6)
	check(root.Visible and opacity(root) == 1 and part(ctx, "Compass").Visible and not part(ctx, "Guide1").Visible,
		"collapsed exit pill keeps its compass")
	check(root.Size.Y.Offset == bar + compassRow and root.Size.Y.Offset == 48, "collapsed exit pill is bar + compass, 48 px")
	check(text(root, "Compass/Readout") == "EXIT 14 m" and part(ctx, "Compass/Readout").TextSize >= 12,
		"pinned readout keeps the touch 12 px floor")
	check(part(ctx, "Hit").Size.Y.Offset == 44, "the 44 px tap target is unchanged")
	ctx.Workspace.CurrentCamera = {CFrame = {LookVector = Vector3.new(1, 0, 0)}}
	ctx.RunService.Heartbeat:Fire(0.016)
	check(part(ctx, "Compass"):GetAttribute("HudBearing") == -45, "the pinned needle is live")
	part(ctx, "Hit").Activated:Fire()
	ctx:Flush()
	check(root.Size.Y.Offset == bar + line + compassRow and part(ctx, "Guide1").Visible, "a tap still expands the exit pill")
	beat(ctx, 6)
	check(root.Size.Y.Offset == bar + compassRow and part(ctx, "Compass").Visible, "and it collapses back onto bar + compass")
	Hud.SetObjective(state())
	beat(ctx, 6)
	check(root.Size.Y.Offset == 44 and not part(ctx, "Compass").Visible, "any other locked compass still collapses with the pill")
	Hud.SetObjective({Level = 3, Title = "GET OUT", Lines = {}, Compass = {State = "calibrating", Target = EXIT.Compass.Target}})
	beat(ctx, 6)
	check(root.Size.Y.Offset == 44 and not part(ctx, "Compass").Visible, "an exit that is not locked yet is not pinned")

	-- The fit guard. The fake TopRightPanel offers safe.Bottom - 58 - 16 px above the controls.
	local function room(height, change)
		local tight, hud = phone(58 + 16 + height)
		local value = table.clone(EXIT)
		for key, item in pairs(change or {}) do value[key] = item end
		hud.SetObjective(value)
		tight:Flush()
		beat(tight, 0.1)
		return tight
	end
	local tight = room(bar + compassRow) -- the expanded pill does not fit, bar + compass exactly does
	check(card(tight).Visible and part(tight, "Compass").Visible and not part(tight, "Guide1").Visible
		and card(tight).Size.Y.Offset == bar + compassRow, "a forced collapse keeps the compass when bar + compass fit")
	beat(tight, 6)
	check(card(tight).Visible and part(tight, "Compass").Visible, "and it stays after the six seconds")
	part(tight, "Hit").Activated:Fire()
	tight:Flush() -- no Heartbeat: the forced collapse itself must keep the row, not the next render
	check(part(tight, "Compass").Visible and not part(tight, "Guide1").Visible and card(tight).Size.Y.Offset == bar + compassRow,
		"a tap that cannot expand leaves the pinned compass up, with no blink until the next render")
	tight = room(bar + compassRow - 1) -- one pixel short, but the 44 px bar alone fits
	check(card(tight).Visible and not part(tight, "Compass").Visible and card(tight).Size.Y.Offset == 44,
		"no room for bar + compass: the card stays, the compass waits for a tap")
	beat(tight, 6)
	check(card(tight).Visible and not part(tight, "Compass").Visible, "the guard never trades the whole card for the compass")
	local danger = {Status = {Text = "The water is no longer safe.", Kind = "danger"}}
	local status = part(room(400, danger), "StatusRow").Size.Y.Offset
	tight = room(bar + status + compassRow, danger)
	check(card(tight).Visible and part(tight, "StatusRow").Visible and part(tight, "Compass").Visible
		and card(tight).Size.Y.Offset == bar + status + compassRow, "a danger row is counted: bar + danger + compass fit")
	tight = room(bar + status + compassRow - 1, danger)
	check(card(tight).Visible and part(tight, "StatusRow").Visible and not part(tight, "Compass").Visible,
		"one pixel short with a danger row: the danger row stays, the compass does not")
end

do -- Modal exclusion is immediate; the original hold/rest deadlines continue behind it.
	local ctx, Hud = start()
	ctx.Hud = Hud
	Hud.SetObjective(state())
	Hud.Feed({Kind = "TEAM", Actor = "Player", Detail = "found a CD"})
	Hud.Caption("USHER", "Shhh...")
	Hud.Detector("MEDIUM", ctx.Now + 12)
	ctx:Flush()
	local objective, detector, cap, feed = card(ctx), Hud.Gui():FindFirstChild("DetectorCard"), Hud.Gui():FindFirstChild("Caption"), row(ctx)
	local deadline = Hud.CaptureTestState().Objective.Attention.HoldUntil
	beat(ctx, 1)
	ctx.Player:SetAttribute("RoundExitPromptOpen", true)
	check(not objective.Visible and not detector.Visible and not cap.Visible and not feed.Visible,
		"modal edge excludes all four owned lanes before any time advances")
	check(objective.GroupTransparency == 1 and detector.GroupTransparency == 1, "modal cancels pending attention tween visuals")
	beat(ctx, 4.9)
	check(not objective.Visible and not detector.Visible, "detector countdown and attention deadlines never reopen modal lanes")
	ctx.Player:SetAttribute("RoundExitPromptOpen", false)
	check(opacity(objective) == 1 and not detector.Visible, "modal close resumes original objective hold and already-rested detector")
	check(not cap.Visible and not feed.Visible, "expired feed/caption never revive on close")
	beat(ctx, 0.1)
	check(opacity(objective) == 1 and not Hud.CaptureTestState().Objective.Attention.Held
		and Hud.CaptureTestState().Objective.Attention.HoldUntil == deadline,
		"modal does not restart original six-second objective hold")
	Hud.Detector("HIGH", ctx.Now + 6)
	ctx.Player:SetAttribute("PartyDownCardOpen", true)
	check(not objective.Visible and not detector.Visible, "party modal immediately excludes urgent scan too")
	beat(ctx, 2)
	check(not detector.Visible, "urgent detector cannot bypass modal on next countdown tick")
	ctx.Player:SetAttribute("PartyDownCardOpen", false)
	check(opacity(objective) == 1 and opacity(detector) == 1, "close resumes opaque objective and still-live urgent scan")
	ctx.Player:SetAttribute("LevelLoadingOpen", true)
	Hud.Detector(nil)
	check(not detector.Visible, "driver clear while loading cannot introduce fade ghost")
	ctx.Player:SetAttribute("LevelLoadingOpen", false)
	check(not detector.Visible, "cleared scan does not reappear after modal")
end

do -- Touch80percent visuals,44 hit, attention/collapse/tap, alternate-template remount and note seam.
	local ctx, Hud = start({touch = true, viewport = Vector2.new(844, 390),
		safe = {Left = 47, Top = 58, Right = 797, Bottom = 369}})
	ctx.Hud = Hud
	local calls = 0
	Hud.SetObjective(state({OnOrderActivate = function() calls += 1 end}))
	ctx:Flush()
	local root = card(ctx)
	check(root.Size.X.Offset == 192 and part(ctx, "Bar").Size.Y.Offset == 32, "global80percent touch192x32 Bar")
	check(root:FindFirstChildWhichIsA("GuiObject").BackgroundTransparency == 1,
		"touch objective backing removed without hiding the card")
	check(part(ctx, "Hit").Size.X.Offset == 192 and part(ctx, "Hit").Size.Y.Offset == 44,
		"compact tap hit follows mounted width and keeps44 height")
	check(part(ctx, "OrderHit").Size.X.Offset == 192 and part(ctx, "OrderHit").Size.Y.Offset == 44,
		"Order-line hit follows mounted width and keeps44 height")
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("TextLabel") or node:IsA("TextButton") then
			if node:GetAttribute("FigmaFontSize") then check(node.TextSize >= 12, "touch text actual12 floor: " .. node.Name) end
		end
	end
	part(ctx, "OrderHit").Activated:Fire()
	check(calls == 1, "Order-line callback invoked without note gameplay in module")
	beat(ctx, 6)
	check(root.Size.Y.Offset == 44 and part(ctx, "Bar").Size.Y.Offset == 32 and not part(ctx, "Compass").Visible,
		"touch collapses to visual32 plus transparent44 hit bounds after6sec")
	part(ctx, "Hit").Activated:Fire()
	ctx:Flush()
	check(root.Size.Y.Offset > 40 and part(ctx, "Compass").Visible and opacity(root) == 1, "tap expands and wakes")
	beat(ctx, 6)
	check(root.Size.Y.Offset == 44, "tap expansion also expires after6sec")
	Hud.SetObjective(state({Status = {Text = "The water is no longer safe.", Kind = "danger"}}))
	beat(ctx, 8)
	check(part(ctx, "StatusRow").Visible and root.Size.Y.Offset > 40 and opacity(root) == 1,
		"touch danger row stays expanded and bright after6seconds")
	Hud.SetObjective(state())
	ctx:Device({Touch = false, Viewport = Vector2.new(1920, 1080),
		Safe = {Left = 0, Top = 58, Right = 1920, Bottom = 1080}})
	ctx:Flush()
	check(card(ctx) ~= root and card(ctx).Size.X.Offset == 288 and part(ctx, "Head") ~= nil, "device remount uses80percent PC alternate")
	local count = 0
	for _, child in ipairs(Hud.Gui():GetChildren()) do if child.Name == "ObjectiveCard" then count += 1 end end
	check(count == 1 and root.Parent == nil, "device flip leaves exactly one objective card")
	local snapshot = Hud.LastObjective()
	check(snapshot.Counter.Label == "CDS IN THE PLAYER" and snapshot.Counter.Current == 2 and snapshot.Counter.Max == 5,
		"stable B8 Counter contract")
	local marker = Hud.Mount("HUD_PC", "NoiseMarker", Hud.Gui(), {Name = "NoiseMarker"})
	Hud.Clear()
	beat(ctx, 10)
	check(card(ctx) == nil and marker.Parent == Hud.Gui(), "Clear removes owned card, preserves caller marker")
	check(Hud.LastObjective() == snapshot, "Clear preserves exact last valid snapshot table")
end

do -- Physical touch uses the real developer whitelist; QA and note actions never open tools.
	local function ready(userId, behavior)
		local ctx, Hud = start({touch = true})
		ctx.Hud, ctx.Player.UserId = Hud, userId
		ctx.UIDevice.ScreenOwningModalOpen = function()
			return ctx.Player:GetAttribute("DevPhoneOpen") == true
				or ctx.Player:GetAttribute("ZyntraStoreOpen") == true
				or ctx.Player:GetAttribute("RoundEndingOpen") == true
		end
		local scripts = newInstance("PlayerScripts", "PlayerScripts")
		scripts.Parent = ctx.Player
		local bridge = newInstance(behavior == "wrongClass" and "Folder" or "BindableFunction", "ZyntraDevUIOpen")
		if behavior ~= "missing" then bridge.Parent = scripts end
		local calls, requested = 0, nil
		bridge.Invoke = function(_, want)
			calls, requested = calls + 1, want
			if behavior == "error" then error("dev menu failed to bind") end
			if behavior == "refused" then return false end
			ctx.Player:SetAttribute("DevPhoneOpen", true)
			return true
		end
		Hud.SetObjective(state())
		beat(ctx, 6)
		return ctx, Hud, bridge, function() return calls, requested end
	end
	for _, data in ipairs({{40920547, true}, {9488575949, true}, {1, false}, {11374988579, false}, {-1, false}}) do
		local ctx, Hud, _, read = ready(data[1])
		check(ctx:Require("DevAccess").IsAllowed(ctx.Player) == data[2], "actual developer whitelist: " .. data[1])
		part(ctx, "Hit").Activated:Fire()
		ctx:Flush()
		local calls, requested = read()
		check(calls == (data[2] and 1 or 0), "physical touch opens tools only for whitelisted UserId: " .. data[1])
		check(data[2] and requested == true or not data[2] and requested == nil,
			"touch requests an explicit open, never a toggle: " .. data[1])
		if data[2] then
			check(ctx.Player:GetAttribute("DevPhoneOpen") == true, "authorized bridge owns the modal flag")
			beat(ctx, 0.1)
			check(not card(ctx).Visible, "opened developer modal suppresses the objective")
		else
			check(card(ctx).Visible and card(ctx).Size.Y.Offset > 44
				and ctx.Player:GetAttribute("DevPhoneOpen") == nil, "ordinary touch keeps objective expansion")
			beat(ctx, 6)
			check(card(ctx).Size.Y.Offset == 44, "ordinary touch keeps original six-second collapse")
		end
	end
	for _, behavior in ipairs({"missing", "wrongClass", "refused", "error"}) do
		local ctx, Hud, _, read = ready(40920547, behavior)
		part(ctx, "Hit").Activated:Fire()
		ctx:Flush()
		check(read() == ((behavior == "refused" or behavior == "error") and 1 or 0),
			"missing/refused dev bridge falls back safely: " .. behavior)
		check(card(ctx).Visible and card(ctx).Size.Y.Offset > 44
			and ctx.Player:GetAttribute("DevPhoneOpen") == nil, "bridge fallback leaves objective expanded: " .. behavior)
	end
	do
		local ctx, Hud, _, read = ready(40920547)
		ctx.Storage:FindFirstChild("DevAccess"):Destroy()
		part(ctx, "Hit").Activated:Fire()
		ctx:Flush()
		check(read() == 0 and card(ctx).Size.Y.Offset > 44, "missing DevAccess fails closed without losing expansion")
	end
	for _, flag in ipairs({"LevelLoadingOpen", "PartyDownCardOpen", "RoundExitPromptOpen",
		"DevPhoneOpen", "ZyntraStoreOpen", "RoundEndingOpen"}) do
		local ctx, Hud, _, read = ready(40920547)
		local hit, deadline = part(ctx, "Hit"), Hud.CaptureTestState().Objective.ExpandUntil
		ctx.Player:SetAttribute(flag, true)
		hit.Activated:Fire()
		check(read() == 0 and Hud.CaptureTestState().Objective.ExpandUntil == deadline,
			"modal rejects even a forged physical activation: " .. flag)
	end
	do
		local ctx, Hud, _, read = ready(40920547)
		check(Hud.ExpandObjectiveForTest(), "developer QA expansion accepted")
		ctx:Flush()
		check(card(ctx).Size.Y.Offset > 44, "developer QA expansion still expands the real touch objective")
		check(read() == 0 and ctx.Player:GetAttribute("DevPhoneOpen") == nil, "developer QA expansion never opens tools")
		ctx.RunService.IsStudio = function() return false end
		check(not Hud.ExpandObjectiveForTest() and read() == 0, "non-Studio QA entry remains denied")
	end
	do
		local ctx, Hud, _, read = ready(40920547)
		local hit = part(ctx, "Hit")
		ctx.Touch = false -- classifier changed while an old touch activation was queued.
		hit.Activated:Fire()
		check(read() == 0 and card(ctx).Size.X.Offset == 288 and part(ctx, "Hit") == nil,
			"pointer remount never opens developer tools from a stale touch hit")
	end
	do
		local ctx, Hud, _, read = ready(40920547)
		ctx.Workspace:SetAttribute("UIRegressionForceLevel3Reader", true)
		ctx.Player:SetAttribute("InRound", nil)
		ctx.Workspace:SetAttribute("RoundActive", false)
		part(ctx, "Hit").Activated:Fire()
		ctx:Flush()
		check(read() == 0 and card(ctx).Size.Y.Offset > 44, "QA fixture cannot bypass genuine live-round dev gate")
	end
	do
		local ctx, Hud, _, read = ready(40920547)
		Hud.Gui().Enabled = false
		part(ctx, "Hit").Activated:Fire()
		check(read() == 0, "disabled HUD cannot route a forged activation to developer tools")
	end
	do
		local ctx, Hud, _, read = ready(40920547)
		ctx:Device({Viewport = Vector2.new(150, 700), Safe = {Left = 0, Top = 58, Right = 150, Bottom = 700}})
		part(ctx, "Hit").Activated:Fire()
		check(read() == 0 and not card(ctx).Visible, "non-fitting objective cannot open developer tools")
	end
	do
		local ctx, Hud, _, read = ready(40920547)
		local notes = 0
		Hud.SetObjective(state({OnOrderActivate = function() notes += 1 end}))
		Hud.ExpandObjectiveForTest()
		ctx:Flush()
		part(ctx, "OrderHit").Activated:Fire()
		check(notes == 1 and read() == 0, "developer Order-line activation preserves note callback only")
	end
end

do -- The simple Level2 exit goal replaces every old pump/route row on both actual imports.
	for _, touch in ipairs({false, true}) do
		local ctx, Hud = start({touch = touch, viewport = Vector2.new(844, 390),
			safe = {Left = 47, Top = 58, Right = 797, Bottom = 369}})
		ctx.Hud = Hud
		ctx.Workspace:SetAttribute("SelectedLevel", 2)
		check(Hud.SetObjective({Level = 2, Title = "START THE PUMPS", Count = 1, Goal = 3,
			Tag = "PUMP STATIONS", Lines = {"2 stations left.", "Find the other pump stations."},
			Status = {Text = "The water is no longer safe.", Kind = "danger"},
			Compass = {State = "locating"}, Done = false}), "old Level2 detailed state admitted")
		ctx:Flush()
		local root = card(ctx)
		check(part(ctx, "Progress").Visible and part(ctx, "Guide1").Visible
			and part(ctx, "Guide2").Visible and part(ctx, "StatusRow").Visible
			and part(ctx, "Compass").Visible, "old Level2 rows really drawn before replacement")
		local before = root.Size.Y.Offset
		check(Hud.SetObjective({Level = 2, Title = "Find the exit", Lines = {}, Done = false}),
			"new Level2 title-only state admitted")
		ctx:Flush()
		check(card(ctx) == root and text(root, "Title") == "Find the exit", "title-only replaces same mounted card")
		for _, name in ipairs({"Counter", "Progress", "Guide1", "Guide2", "StatusRow", "Compass"}) do
			local rowPart = part(ctx, name)
			check(not rowPart or not rowPart.Visible, "new Level2 hides optional row: " .. name)
		end
		check(text(root, "Count") == "" and text(root, "CountTag") == ""
			and text(root, "Guide1/Line") == "" and text(root, "Guide2/Line") == "",
			"old count, tag and route text are cleared")
		check(not part(ctx, "OrderHit").Visible, "retired route leaves no active Order-line hit")
		check(root.Size.X.Offset == (touch and 192 or 288)
			and root.Size.Y.Offset == (touch and 44 or part(ctx, "Head").Size.Y.Offset)
			and root.Size.Y.Offset < before, "new Level2 reserves only scaled header and touch44 hit floor")
		check(Hud.LastObjective().Counter == nil and Hud.LastObjective().Compass == nil
			and #Hud.LastObjective().Lines == 0, "new Level2 snapshot carries no old counter or route")
	end
end

do -- Feed pooling, kinds, DisplayName/UTF8 initial, keyed merge, cap, expiry and modal gates.
	local ctx, Hud, P = start()
	ctx.Hud = Hud
	local anna = newInstance("Player", "AnnaUser")
	anna.UserId, anna.DisplayName = 2, "\u{D8}skar"
	table.insert(ctx.Players.Members, anna)
	check(Hud.Feed({Kind = "TEAM", Actor = "AnnaUser", Detail = "found a CD", Key = "level3:cd"}), "live Feed accepted")
	ctx:Flush()
	local first = row(ctx)
	check(first.Visible and text(first, "Words/Who") == "\u{D8}skar", "actor name resolves DisplayName")
	check(text(first, "Initial/Letter") == "\u{D8}", "UTF8 initial is complete character")
	check(find(first, "Bar").BackgroundColor3 == P.RailTeal and not find(first, "Dot").Visible, "TEAM RailTeal bar")
	beat(ctx, 1)
	Hud.Feed({Kind = "LEVEL", Detail = "A CD was found", Key = "level3:cd"})
	ctx:Flush()
	check(row(ctx, 2) == nil and row(ctx) == first and text(first, "Words/Who") == "\u{D8}skar",
		"later local duplicate merges and keeps validated actor")
	check(text(first, "Words/Detail") == "found a CD", "later LEVEL duplicate keeps validated team copy")
	Hud.Feed({Kind = "LEVEL", Detail = "Wrong order.", Key = "wrong"})
	ctx:Flush()
	check(row(ctx, 2).Visible and find(row(ctx, 2), "Dot").Visible and not find(row(ctx, 2), "Bar").Visible,
		"LEVEL uses Amber dot without bar")
	Hud.Feed({Kind = "DANGER", Actor = 2, Detail = "is down \u{B7} 3 left", Key = "death"})
	ctx:Flush()
	check(row(ctx) == first and text(row(ctx), "Words/Detail") == "Wrong order.", "PC pooled oldest row replaced, cap2")
	check(find(row(ctx, 2), "Bar").BackgroundColor3 == P.Coral, "DANGER Coral bar")
	beat(ctx, 4)
	check(not row(ctx).Visible and not row(ctx, 2).Visible, "4sec expiry hides pooled rows")
	Hud.Feed({Kind = "SYSTEM", Actor = "LeftUser", Detail = "got out"})
	ctx:Flush()
	check(text(row(ctx), "Words/Who") == "LeftUser" and find(row(ctx), "Bar").BackgroundColor3 == P.Cream,
		"departed actor has safe fallback, SYSTEM Cream")
	ctx.Player:SetAttribute("Level3_Hiding", true)
	local hiding = newInstance("ScreenGui", "Level3TableHideUI")
	hiding.Parent = ctx.PlayerGui
	local banner = newInstance("Frame", "HiddenStatus")
	banner.Size, banner.AbsolutePosition, banner.Parent = UDim2.fromOffset(358, 24), Vector2.new(115, 64), hiding
	local leave = newInstance("TextButton", "LeaveHiding")
	leave.Size, leave.AbsolutePosition, leave.Parent = UDim2.fromOffset(200, 44), Vector2.new(194, 94), hiding
	Hud.Feed({Kind = "LEVEL", Detail = "Still shown under table"})
	ctx:Flush()
	check(row(ctx).Visible and row(ctx).Position.Y.Offset == 146, "hiding feed clears banner plus actual44-high leave hit")
	local warning = newInstance("Frame", "TableCheck")
	warning.Size, warning.AbsolutePosition, warning.Parent = UDim2.fromOffset(358, 48), Vector2.new(115, 94), hiding
	leave.AbsolutePosition = Vector2.new(194, 148)
	beat(ctx, 0.1)
	check(row(ctx).Position.Y.Offset == 200, "table-check warning feed clears complete banner/check/leave union")
	hiding.Enabled = false
	beat(ctx, 0.1)
	check(row(ctx).Position.Y.Offset == ctx.Safe.Top + 12, "disabled hiding GUI reserves no stale lane")
	ctx.Player:SetAttribute("LevelLoadingOpen", true)
	check(not Hud.Feed({Kind = "TEAM", Detail = "stale while loading"}), "loading rejects new stale feed")
	check(not row(ctx).Visible, "loading hides existing feed immediately")
	ctx.Player:SetAttribute("LevelLoadingOpen", false)
	ctx.Player:SetAttribute("InRound", false)
	check(not Hud.Feed({Kind = "TEAM", Detail = "lobby stale"}), "outside round rejects feed")
	Hud.Clear()
	check(Hud.Gui():FindFirstChild("FeedRow1") == nil, "Clear tears down pooled rows")
end

do -- Phone's single row is replaced temporarily by gated3.5sec caption, then resumes if still live.
	local ctx, Hud = start({touch = true, viewport = Vector2.new(844, 390),
		safe = {Left = 47, Top = 58, Right = 797, Bottom = 369}})
	ctx.Hud = Hud
	Hud.Feed({Kind = "LEVEL", Detail = "A reel is ready."})
	ctx:Flush()
	check(row(ctx).Size.X.Offset == 358 and row(ctx).Position.X.Offset == 115, "real touch feed at approved lane")
	Hud.Feed({Kind = "TEAM", Actor = "Player", Detail = "loaded a reel"})
	check(row(ctx, 2) == nil and text(row(ctx), "Words/Detail") == "loaded a reel", "phone latest row only")
	ctx.Player:SetAttribute("CaptionsEnabled", false)
	check(not Hud.Caption("USHER", "Shhh..."), "CaptionsEnabled false gates")
	ctx.Player:SetAttribute("CaptionsEnabled", true)
	ctx.Player:SetAttribute("DisableCaptions", true)
	check(not Hud.Caption("USHER", "Shhh..."), "DisableCaptions true gates")
	ctx.Player:SetAttribute("DisableCaptions", false)
	check(Hud.Caption("USHER", "Shhh..."), "enabled caption accepted")
	ctx:Flush()
	local cap = Hud.Gui():FindFirstChild("Caption")
	check(cap.Visible and not row(ctx).Visible and text(cap, "Speaker") == "USHER" and text(cap, "Said") == "Shhh...",
		"caption replaces touch feed lane, copy no brackets")
	check(cap.Position.X.Offset == row(ctx).Position.X.Offset and cap.Position.Y.Offset == row(ctx).Position.Y.Offset,
		"touch caption and feed share exact lane")
	beat(ctx, 3.49)
	check(cap.Visible, "caption persists to3.49sec")
	beat(ctx, 0.01)
	check(not cap.Visible and row(ctx).Visible, "caption expires at3.5sec, live feed resumes")
	beat(ctx, 0.5)
	check(not row(ctx).Visible, "feed expires independently at4sec")
	ctx:Device({Touch = false, Viewport = Vector2.new(1920, 1080),
		Safe = {Left = 0, Top = 58, Right = 1920, Bottom = 1080}})
	Hud.Caption("USHER", "Shhh...")
	ctx:Flush()
	check(cap.Parent == nil and Hud.Gui():FindFirstChild("Caption") ~= cap, "alternate caption remounted without old node")
	ctx.Player:SetAttribute("InRound", false)
	ctx.Player:SetAttribute("DispatchTextActive", true)
	check(Hud.Caption("COMMAND CENTER", "Welcome to the station."), "source-gated lobby dispatch caption accepted")
	check(not Hud.Caption("USHER", "lobby stale"), "non-dispatch lobby captions still rejected")
	ctx.Player:SetAttribute("DisableCaptions", true)
	check(Hud.Caption("COMMAND CENTER", "", 0), "duration0 clears even after caption gates change")
	check(not Hud.Gui():FindFirstChild("Caption").Visible, "duration0 clearing hides immediately")
end

do -- Accent paths on all6 loading modes and both authored result stacks.
	local ctx, Hud, P = start()
	for _, template in ipairs({"LoadingCard", "LoadingCardTouch"}) do
		local root = Hud.Mount("HUD_Screens", template, Hud.Gui())
		for level = 1, 6 do
			Hud.Paint(root, template, level)
			local accent = ctx:Require("UIStyle").Hud.Accent[level]
			check(find(root, "Eyebrow").TextColor3 == accent and find(root, "Underbar").BackgroundColor3 == accent,
				"loading eyebrow/underbar accent " .. template .. level)
			check(find(root, "Status/Track/Fill").BackgroundColor3 == accent, "loading current progress accent")
			for slot = 1, 6 do
				check(find(root, "LevelTrack/Slot" .. slot).TextColor3 == (slot == level and accent or P.Sage),
					"only current loading slot has accent " .. slot)
			end
		end
	end
	for _, template in ipairs({"Results", "ResultsTouch"}) do
		local root = Hud.Stack("HUD_Screens", template, Hud.Gui())
		Hud.Paint(root, template, 4)
		check(find(root, "Head/Eyebrow").TextColor3 == Color3.fromRGB(255, 70, 200), "results Head eyebrow accent only")
	end
end

do -- Small landscape/portrait touch feed yields to the actual objective rectangle and44px door.
	for _, size in ipairs({{Width = 667, Height = 375, Left = 44, Top = 36, Right = 623, Bottom = 354},
		{Width = 375, Height = 812, Left = 0, Top = 36, Right = 375, Bottom = 812}}) do
		local ctx, Hud = start({touch = true, viewport = Vector2.new(size.Width, size.Height), safe = size})
		ctx.Hud = Hud
		Hud.SetObjective(state())
		ctx:Flush()
		Hud.Feed({Kind = "LEVEL", Detail = "A CD is ready."})
		ctx:Flush()
		local root, objective = row(ctx), card(ctx)
		check(root.Visible and root.Position.X.Offset >= size.Left
			and root.Position.X.Offset + root.Size.X.Offset <= size.Right, "small touch feed keeps authored358 withinSafe")
		check(root.Position.Y.Offset >= objective.Position.Y.Offset + objective.Size.Y.Offset + 8,
			"small touch feed sits below overlapping objective")
		if root.Position.X.Offset < size.Left + 68 then
			check(root.Position.Y.Offset >= size.Top + 6 + 44 + 8, "portrait feed clears44px door before stepping left")
		end
		Hud.Detector("HIGH", ctx.Now + 10)
		local detector = Hud.Gui():FindFirstChild("DetectorCard")
		check(detector.Position.Y.Offset >= root.Position.Y.Offset + root.Size.Y.Offset + 8, "touch detector follows moved feed lane")
		Hud.Caption("USHER", "Shhh...")
		ctx:Flush()
		local cap = Hud.Gui():FindFirstChild("Caption")
		check(cap.Visible and not root.Visible and cap.Position.Y.Offset >= objective.Position.Y.Offset + objective.Size.Y.Offset + 8,
			"touch caption uses same measured non-overlapping lane")
		check(detector.Position.Y.Offset >= cap.Position.Y.Offset + cap.Size.Y.Offset + 8, "touch detector clears taller caption")
	end
end

do -- A338px phone must show admitted feed/caption/scan, with real slots and readable native text.
	local ctx, Hud = start({touch = true, viewport = Vector2.new(338, 705),
		safe = {Left = 0, Top = 58, Right = 338, Bottom = 705}})
	ctx.Hud = Hud
	Hud.SetObjective(state())
	check(Hud.Feed({Kind = "TEAM", Actor = "Player", Detail = "found a CD", Key = "narrow"}), "338 feed admitted")
	Hud.Detector("MEDIUM", ctx.Now + 12)
	ctx:Flush()
	local function lane(root, description)
		check(root ~= nil and root.Visible, "338 " .. description .. " genuinely visible")
		check(root.Size.X.Offset == 322 and root.Position.X.Offset >= 8
			and root.Position.X.Offset + root.Size.X.Offset <= 330, "338 " .. description .. " retains8px side padding")
		for _, node in ipairs(root:GetDescendants()) do
			if node:IsA("UIScale") then check(node.Scale == 1, "338 imported scale never shrinks readable copy") end
			if node:IsA("TextLabel") and node.Visible and node.Text ~= "" then
				node.FakeEmHeight = 1.15 -- Native line height can exceed TextSize; it is not a square em.
				check(node.TextSize >= 12 and node.TextBounds.Y <= node.AbsoluteSize.Y + 1,
					"338 readable native12px line/badge has height: " .. node.Name)
			end
		end
	end
	lane(row(ctx), "feed")
	ctx.Player.DisplayName = "mikkelczar"
	local who, detail = find(row(ctx), "Words/Who"), find(row(ctx), "Words/Detail")
	who.FakeAdvance = 62 / (10 * 12) -- Exact native338 regression: full name62px, authored box46.77px.
	Hud.Feed({Kind = "TEAM", Actor = "Player", Detail = "restored a fuse box", Key = "narrow"})
	ctx:Flush()
	check(who.Text == "mikkelczar" and near(who.TextBounds.X, 62) and who.AbsoluteSize.X >= 62
		and who.TextTruncate == Enum.TextTruncate.None, "ordinary native62px DisplayName has full measured box")
	check(detail.Visible and detail.Text == "restored a fuse box" and who.TextSize == 12 and detail.TextSize == 12,
		"name growth retains detail and12px readable text")
	local left = who.Position.X.Offset - who.AnchorPoint.X * who.Size.X.Offset
	local detailLeft = detail.Position.X.Offset - detail.AnchorPoint.X * detail.Size.X.Offset
	check(detailLeft >= left + who.Size.X.Offset and detailLeft + detail.Size.X.Offset <= who.Parent.AbsoluteSize.X + 0.01,
		"measured name and detail have separate bounded boxes")
	ctx.Player.DisplayName = string.rep("W", 100)
	Hud.Feed({Kind = "TEAM", Actor = "Player", Detail = "restored a fuse box", Key = "narrow"})
	ctx:Flush()
	check(who.Text == ctx.Player.DisplayName and who.TextTruncate == Enum.TextTruncate.AtEnd
		and who.AbsoluteSize.X < who.TextBounds.X and detail.Visible, "truly overlong name retains semantic string with explicit bounded ellipsis")
	local retainedWidth = who.Size.X.Offset
	who.TextTruncate = Enum.TextTruncate.None -- Binder's deferred solve must not silently clear overflow policy.
	ctx:Flush()
	check(who.TextTruncate == Enum.TextTruncate.AtEnd and who.Size.X.Offset == retainedWidth,
		"deferred font solve cannot erase ellipsis or expand lane")
	ctx.Player.DisplayName = "Oskar"
	Hud.Feed({Kind = "TEAM", Actor = "Player", Detail = "found a CD", Key = "narrow"})
	ctx:Flush()
	check(who.Text == "Oskar" and who.TextTruncate == Enum.TextTruncate.None and who.AbsoluteSize.X < retainedWidth,
		"new shorter name releases old allocation and truncation")
	lane(Hud.Gui():FindFirstChild("DetectorCard"), "scan")
	check(Hud.Caption("COMMAND CENTER", "Keep moving."), "338 caption admitted")
	ctx:Flush()
	lane(Hud.Gui():FindFirstChild("Caption"), "caption")
	check(not row(ctx).Visible, "338 visible caption exclusively owns feed lane")
	local before = Hud.CaptureTestState()
	beat(ctx, 1)
	ctx:Device({Viewport = Vector2.new(375, 705), Safe = {Left = 0, Top = 58, Right = 375, Bottom = 705}})
	local after = Hud.CaptureTestState()
	check(Hud.Gui():FindFirstChild("Caption").Visible and Hud.Gui():FindFirstChild("Caption").Size.X.Offset == 358,
		"wider phone restores authored358px lane")
	check(after.Caption.Until == before.Caption.Until and after.Feed.Entries[1].Until == before.Feed.Entries[1].Until,
		"width remount never renews caption/feed deadlines")
	check(after.Detector.Attention.HoldUntil == before.Detector.Attention.HoldUntil,
		"width-only scan remount retains original attention deadline")
	Hud.Caption("COMMAND CENTER", "", 0)
	check(row(ctx).Visible, "wider feed resumes while original entry is live")
	ctx:Device({Viewport = Vector2.new(338, 705), Safe = {Left = 0, Top = 58, Right = 338, Bottom = 705}})
	lane(row(ctx), "remounted feed")
	beat(ctx, 3)
	check(not row(ctx).Visible and opacity(Hud.Gui():FindFirstChild("DetectorCard")) == 0,
		"resize cannot extend feed4sec or ordinary scan4sec hold")
end

do -- Studio capture/restore is immutable, restores all deadlines and nil, invalidates staged timers.
	local ctx, Hud = start({touch = true})
	ctx.Hud = Hud
	local empty = Hud.CaptureTestState()
	check(empty.Kind == "RoundHudTestState" and empty.LastObjective == nil, "nil initial loss snapshot captured")
	Hud.SetObjective(state())
	beat(ctx, 7)
	Hud.Feed({Kind = "TEAM", Actor = "Player", Detail = "original feed", Key = "original"})
	Hud.Caption("USHER", "Original caption")
	Hud.Detector("HIGH", ctx.Now + 20)
	local captured = Hud.CaptureTestState()
	check(table.isfrozen(captured) and table.isfrozen(captured.Objective.State.Lines) and table.isfrozen(captured.Feed.Entries),
		"captured state is recursively immutable plain data")
	local oldDeadline = captured.Feed.Entries[1].Until
	Hud.SetObjective(state({Count = 999, Title = "TEST FIXTURE"}))
	Hud.Feed({Kind = "DANGER", Detail = "staged fake", Key = "fake"})
	Hud.Caption("TEST", "Staged caption")
	Hud.Detector("LOW", ctx.Now + 1)
	beat(ctx, 1)
	check(Hud.RestoreTestState(captured), "Studio state restored")
	ctx:Flush()
	check(Hud.LastObjective().Title == "FIND THE CDS" and Hud.LastObjective().Counter.Current == 2, "original loss snapshot restored")
	check(card(ctx).Size.Y.Offset == 44 and opacity(card(ctx)) == 1
		and Hud.CaptureTestState().Objective.Attention.HoldUntil == captured.Objective.Attention.HoldUntil,
		"opaque/collapsed attention restored without6sec restart")
	check(text(row(ctx), "Words/Detail") == "original feed", "original pooled row restored")
	check(Hud.CaptureTestState().Feed.Entries[1].Until == oldDeadline, "feed absolute deadline not restarted")
	check(text(Hud.Gui():FindFirstChild("Caption"), "Said") == "Original caption", "original caption restored")
	check(text(Hud.Gui():FindFirstChild("DetectorCard"), "Line"):find("HIGH") ~= nil, "original detector reading restored")
	beat(ctx, 3)
	check(not row(ctx).Visible and not Hud.Gui():FindFirstChild("Caption").Visible, "restored feed/caption expire at original deadline")
	check(card(ctx).Size.Y.Offset == 44 and text(card(ctx), "Title") == "FIND THE CDS", "staged expansion timers cannot mutate restored objective")
	check(Hud.RestoreTestState(empty), "empty pre-test snapshot restores")
	beat(ctx, 20)
	check(Hud.LastObjective() == nil and card(ctx) == nil and Hud.Gui():FindFirstChild("FeedRow1") == nil
		and Hud.Gui():FindFirstChild("DetectorCard") == nil, "nil snapshot clears fake counters and owned roots permanently")
	Hud.SetObjective(state())
	beat(ctx, 1)
	local held = Hud.CaptureTestState()
	Hud.SetObjective(state({Count = 4}))
	beat(ctx, 2)
	Hud.RestoreTestState(held)
	beat(ctx, 2.9)
	check(card(ctx).Size.Y.Offset > 44 and opacity(card(ctx)) == 1, "restored held objective uses remaining original5seconds")
	beat(ctx, 0.1)
	check(card(ctx).Size.Y.Offset == 44 and opacity(card(ctx)) == 1
		and Hud.CaptureTestState().Objective.Attention.HoldUntil == held.Objective.Attention.HoldUntil,
		"original6sec deadline expires after restore without restart")
	ctx.RunService.IsStudio = function() return false end
	check(Hud.CaptureTestState() == nil and not Hud.RestoreTestState(empty) and not Hud.ExpandObjectiveForTest(),
		"QA state/tap APIs fail closed outside Studio")
end

print("RoundHud shared APIs: " .. checks .. " checks passed (real3 Framewisp imports)")
'''


def program():
    bundles = trees()
    bundles["HUD_Screens"] = json.loads((DUMPS / "framewisp-dump.HUD_Screens.json").read_text(encoding="utf-8"))["root"]
    # Only this program needs the actual whitelist. Generic mounting/stamina fixtures stay unchanged.
    modules = {name: path.read_text(encoding="utf-8") for name, path in SOURCES.items()}
    modules["DevAccess"] = (ROOT / "ReplicatedStorage/DevAccess.ModuleScript.lua").read_text(encoding="utf-8")
    inject = "local SOURCES = {\n%s\n}\nlocal TREES = %s\n" % (
        ",\n".join("%s = %s" % (name, long_string(source)) for name, source in modules.items()),
        lua(bundles),
    )
    return HARNESS.read_text(encoding="utf-8").replace("--@@INJECT@@", inject, 1) + "\n" + TESTS


def stamina_program():
    # Import only literal B3 fixtures from the existing suite. Its unrelated RoundUI extraction may
    # be temporarily unavailable while the single owner ports retired OBJECTIVES handlers.
    path = ROOT / "tools/tests/test_controller_input.py"
    values = {}
    for node in ast.parse(path.read_text(encoding="utf-8")).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            if node.targets[0].id in {"B3_PRELUDE", "B3_EXPORTS", "B3_TESTS"}:
                values[node.targets[0].id] = ast.literal_eval(node.value)
    source = (ROOT / "StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua").read_text(encoding="utf-8")
    begin = source.index("-- == B3 stamina bar (10 C; owner, 2026-10-08) ==")
    end = source.index("-- == end B3 stamina bar ==", begin)
    modules = {name: path.read_text(encoding="utf-8") for name, path in SOURCES.items()}
    modules["NoiseBarSection"] = values["B3_PRELUDE"] + source[begin:end] + values["B3_EXPORTS"]
    inject = "local SOURCES = {\n%s\n}\nlocal TREES = %s\n" % (
        ",\n".join("%s = %s" % (name, long_string(value)) for name, value in modules.items()), lua(trees()))
    return HARNESS.read_text(encoding="utf-8").replace("--@@INJECT@@", inject, 1) + "\n" + values["B3_TESTS"]


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no checks executed")
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    for source in [SOURCES["RoundHud"], ROOT / "StarterPlayer/StarterPlayerScripts/Round HUD.LocalScript.lua",
                   ROOT / "StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua"]:
        subprocess.run([compiler, "-O0", "--null", str(source)], check=True, capture_output=True, timeout=20)
    with tempfile.TemporaryDirectory(prefix="round-hud-shared-") as directory:
        for name, contents in [("shared", program()), ("stamina", stamina_program())]:
            path = Path(directory) / (name + ".luau")
            path.write_text(contents, encoding="utf-8")
            result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=120)
            if result.returncode or "checks passed" not in result.stdout:
                print(result.stdout[-3000:])
                print(result.stderr[-6000:])
                raise SystemExit(name + " FAILED")
            print(result.stdout.strip().splitlines()[-1])


if __name__ == "__main__":
    main()
