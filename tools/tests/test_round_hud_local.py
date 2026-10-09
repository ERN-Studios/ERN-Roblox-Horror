"""Run the real StarterPlayerScripts "Round HUD" LocalScript offline (owner, 2026-10-08; HUD batch B3).

artifacts/hud-final-20261008/b3/B3-DESIGN.md section 6.5 and its critic findings (K3-K16). The REAL
Round HUD runs in the HUD fake engine (tools/tests/hud_harness.luau) beside the REAL RoundHud,
ShopBinder, UIStyle and ZyntraDetectorVisual, over the REAL Framewisp import of HUD_PC
(tools/tests/fixtures/hud/framewisp-dump.HUD_PC.json). The layouts it is handed are computed by the
REAL ReplicatedStorage/UIDevice under test_equipment_hud's fake engine (ENGINE / CONTEXT / BOOTS / wrap,
imported, not copied), at the fixture rows of test_touch_control_plan, so the corridor, ModalArea and
KIT fan are the shipping arithmetic (critic K3: no synthetic corridor widths).

Checked:
  1. RoundHudThreat: order 20, ScreenInsets None, four ChaseEdge* bands (K6) with the D1 sizes and
     rotations, Active false, Coral, gradient 0 -> 1, transparency 1 at boot; one Heartbeat.
  2. The edge truth table: levels 1-4 x BeingChased true / false / nil x {alive, dead, Spectating,
     Escaped, InRound false, RoundActive false}; on is 0.8 over 0.18 s, off is 1 over 0.4 s.
  3. ReduceFlashing true / false / nil: identical goals and times.
  4. Static: the edge section (comments stripped, K14) holds no clock, sine or ReduceFlashing.
  5. Priority over all 18 combinations (K12): GRACE x {none, Level3_Hiding, Level4_Hidden} x MoveNoise;
     sprint standing still or falling is not LOUD (D5, K8).
  6. Attention: 100 % to 5.9 s, 45 % at 6 s, LOUD 60 %, a change re-wakes, a Hide then a Show re-wakes;
     LOUD lingers 0.5 s through a slow patch with no new tween, and hides after 0.6 s (K7);
     a walk's speed lends it no linger (D5).
  7. Grace: 10 s .. 1 s countdown without re-waking, then the next state; a renewal; Shield, inactive,
     NaN and +-huge give none; the template's 8 s sample never shows.
  8. Level 2: the marker shows, the edge never does.
  9. Spectating, dead, escaped, Level4CardOpen (K5): no marker; InRound true -> false calls
     RoundHud.Clear() and the marker survives it (K17).
 10. Placement: PC 1920 and 1366 (K4), touch 844x390 (short GRACE, D11), the 1024 tablet (full copy),
     667x375 (K3: SNEAKING in the corridor, GRACE in ModalArea, above the open KIT fan), portrait,
     a device flip; Soft hugs, the group is ceil(W) wide over a pinned clone (K6).
 11. Template facts against the dump: Label left edge 20, CHAR_W 7.36 (K11), Left aligned, Dot 8..14.
 12. Cross-check with NoiseReporter: MARKER_BOTTOM, MARKER_BOTTOM_TOUCH, KIT_RIGHT and BAR_HALF against
     BAR_BOTTOM, BAR_BOTTOM_TOUCH, BAR_TOUCH_SCALE, KIT_RIGHT and the StaminaBar template. RED until B3
     agent B lands NoiseReporter's bar section (critic K13); it runs last so the rest stays readable.
 13. Missing HUD_PC: one HUD_PC/NoiseMarker warning, no marker, the edge still works; the same
     for a NoiseMarker that lost its Label, and the round end still clears.
 14. Source: ASCII-only, LF, luau-compile, no ADRENALINE, no waits on templates, no Visible writes.

Not checked: real rendering, CanvasGroup clipping, real font metrics. Set LUAU_BIN (luau 0.737;
luau-compile.exe is expected beside it, or LUAU_COMPILE_BIN).
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from test_equipment_hud import BOOTS, CONTEXT, ENGINE, UIDEVICE, wrap
from test_round_hud import DUMPS, HARNESS, SOURCES, long_string, lua, trees

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "StarterPlayer/StarterPlayerScripts/Round HUD.LocalScript.lua"
NOISE = ROOT / "StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua"
EDGE_BEGIN = "-- == B3 chase edge (02 A, reduced flashing; owner, 2026-10-08) =="
EDGE_END = "-- == end B3 chase edge =="
MARKER_BEGIN = "-- == B3 marker (03 C; owner, 2026-10-08) =="
MARKER_END = "-- == end B3 marker =="

# Half 1, inside a `do` block so its engine's names never meet the harness's: the REAL UIDevice
# answers Layout() at the fixture rows (test_touch_control_plan's MATRIX geometry).
LAYOUT_BLOCK = r'''
local deviceCtx = makeContext()
deviceCtx.NoSpawn = true -- UIDevice's inset watcher is a loop a synchronous spawn never leaves
local device = bootModule(deviceCtx, UIDeviceSource)
check(type(device) == "table" and type(device.Layout) == "function", "the real UIDevice loads")
local ws = deviceCtx.workspace
local function layoutAt(row, isTouch)
	deviceCtx.UserInputService.TouchEnabled = isTouch
	deviceCtx.camera.ViewportSize = Vector2.new(row.Width, row.Height)
	local h = row.Housing or {0, 0, 0, 0}
	ws:SetAttribute("UIRegressionSafeInsetsLT", Vector2.new(h[1], h[2]))
	ws:SetAttribute("UIRegressionSafeInsetsRB", Vector2.new(h[3], h[4]))
	ws:SetAttribute("UIRegressionTopbarInsetLT", Vector2.new(0, row.Topbar or 0))
	ws:SetAttribute("UIRegressionTopbarInsetRB", Vector2.zero)
	ws:SetAttribute("ForceTouchUI", isTouch)
	ws:SetAttribute("UIRegressionViewport", Vector2.new(row.Width, row.Height))
	ws:SetAttribute("UIRegressionTopbarBandLR", Vector2.zero) -- force a recompute
	ws:SetAttribute("UIRegressionTopbarBandLR", nil)
	return device.Layout()
end
LAYOUTS.PC = layoutAt({Width = 1920, Height = 1080, Topbar = 58}, false)
LAYOUTS.PC1366 = layoutAt({Width = 1366, Height = 768, Topbar = 58}, false)
LAYOUTS.PC800 = layoutAt({Width = 800, Height = 600, Topbar = 58}, false)
LAYOUTS.PC640 = layoutAt({Width = 640, Height = 480, Topbar = 58}, false)
LAYOUTS.Phone = layoutAt({Width = 844, Height = 390, Topbar = 58, Housing = {47, 0, 47, 21}}, true)
LAYOUTS.Small = layoutAt({Width = 667, Height = 375, Topbar = 36, Housing = {44, 0, 44, 21}}, true)
LAYOUTS.Tablet = layoutAt({Width = 1024, Height = 768, Topbar = 36}, true)
LAYOUTS.Portrait = layoutAt({Width = 375, Height = 812, Topbar = 36}, true)
check(LAYOUTS.PC.IsTouch == false and LAYOUTS.Phone.IsTouch == true, "pointer and touch layouts")
addChecks(checks)
'''

TESTS = r'''
local B = "\u{B7}"
local P = {
	RailTeal = Color3.fromRGB(68, 221, 196), Amber = Color3.fromRGB(232, 160, 36),
	Coral = Color3.fromRGB(242, 112, 95), Sage = Color3.fromRGB(167, 184, 174),
}
-- K11: FW_M100 1242 over the 27 characters of FW_Text0, at the 16 px Roblox draws (12 x 1.3188).
local CHAR_W = 1242 / (100 * 27) * 16
local function pill(text) return 20 + utf8.len(text) * CHAR_W + 8 end
local function graceText(seconds) return "INVISIBLE TO MONSTERS " .. B .. " " .. seconds .. " s" end
local function shortGrace(seconds) return "INVISIBLE " .. B .. " " .. seconds .. " s" end
local BANDS = {"ChaseEdgeLeft", "ChaseEdgeRight", "ChaseEdgeTop", "ChaseEdgeBottom"}

-- A living, in-round body on `options.Layout`, then the REAL Round HUD, run as a LocalScript.
local function roundContext(options)
	options = options or {}
	local layout = options.Layout or LAYOUTS.PC
	local ctx = context({touch = layout.IsTouch == true, skip = options.Skip})
	if options.Prepare then options.Prepare(ctx) end -- edits the templates before the script runs
	ctx.Layout = layout
	local D = ctx.UIDevice
	function D.Layout() return ctx.Layout end
	local run = {Heartbeat = signal(), IsStudio = function() return options.IsStudio ~= false end}
	ctx.RunService = run
	local services = {Players = {LocalPlayer = ctx.Player}, ReplicatedStorage = ctx.Storage,
		RunService = run, TweenService = ctx.Tween}
	local game = {GetService = function(_, name) return assert(services[name], "service " .. name) end,
		IsLoaded = function() return true end}

	local player = ctx.Player
	local remotes = newInstance("Folder", "Remotes")
	remotes.Parent = ctx.Storage
	ctx.RoundStatus = newInstance("RemoteEvent", "RoundStatus")
	ctx.RoundStatus.Parent = remotes
	local character = newInstance("Model", "Character")
	character.Parent = ctx.Workspace
	local humanoid = newInstance("Humanoid", "Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character
	local rootPart = newInstance("Part", "HumanoidRootPart")
	rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	rootPart.Parent = character
	player.Character = character
	ctx.Humanoid, ctx.RootPart = humanoid, rootPart
	player:SetAttribute("InRound", true)
	player:SetAttribute("MoveNoise", "walk")
	ctx.Workspace:SetAttribute("RoundActive", true)
	ctx.Workspace:SetAttribute("SelectedLevel", options.Level or 1)

	local fn = assert(loadstring(ROUND_HUD_SOURCE, "=Round HUD"))
	setfenv(fn, setmetatable({
		game = game, workspace = ctx.Workspace, script = newInstance("LocalScript", "Round HUD"), task = ctx.Task,
		Instance = Instance, Color3 = Color3, UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Vector3 = Vector3,
		NumberSequence = NumberSequence, TweenInfo = TweenInfo, Enum = Enum, typeof = typeof, utf8 = utf8,
		os = {clock = function() return ctx.Now end},
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
			table.insert(ctx.Warnings, table.concat(parts, " "))
		end,
		require = function(module)
			if module.Name == "UIDevice" then return D end
			return ctx:Require(module.Name)
		end,
	}, {__index = _G}))
	ctx.Task.spawn(fn)
	ctx:Flush()
	ctx.Hud = ctx:Require("RoundHud")
	ctx.Threat = ctx.PlayerGui:FindFirstChild("RoundHudThreat")
	ctx.Marker = ctx.Hud.Gui():FindFirstChild("NoiseMarker")

	function ctx:Step(dt)
		dt = dt or 0.25
		self:Advance(dt)
		run.Heartbeat:Fire(dt)
		self:Flush()
	end
	-- Heartbeats for `seconds` in `dt` steps.
	function ctx:Run(seconds, dt)
		dt = dt or 0.25
		for _ = 1, math.floor(seconds / dt + 0.5) do self:Step(dt) end
	end
	function ctx:Set(attributes)
		for key, value in pairs(attributes) do
			if value == "nil" then value = nil end
			player:SetAttribute(key, value)
		end
	end
	function ctx:Speed(x, y, z) rootPart.AssemblyLinearVelocity = Vector3.new(x or 0, y or 0, z or 0) end
	function ctx:Band(name) return self.Threat:FindFirstChild(name) end
	function ctx:Edge() -- 0.8 on every band, or 1 on every band; nil when the bands disagree
		local alpha = self:Band(BANDS[1]).BackgroundTransparency
		for _, name in ipairs(BANDS) do
			if self:Band(name).BackgroundTransparency ~= alpha then return nil end
		end
		return alpha
	end
	function ctx:EdgeTime()
		local tween = self:LastTween(self:Band(BANDS[1]))
		for _, name in ipairs(BANDS) do
			local other = self:LastTween(self:Band(name))
			if (other and other.Time) ~= (tween and tween.Time) then return "mixed" end
		end
		return tween and tween.Time
	end
	function ctx:Part(name) return find(self.Marker, name) end
	function ctx:Text() return self:Part("Label").Text end
	function ctx:Opacity() return 1 - self.Marker.GroupTransparency end
	function ctx:Shown() return self.Marker ~= nil and drawn(self.Marker) and self:Opacity() > 0 end
	function ctx:MarkerTweens()
		local count = 0
		for _, tween in ipairs(self.Tweens) do
			if tween.Instance == self.Marker then count += 1 end
		end
		return count
	end
	return ctx
end

-- == 1. the gui =================================================================================
do
	local ctx = roundContext()
	local threat = ctx.Threat
	check(threat and threat.ClassName == "ScreenGui" and threat.Parent == ctx.PlayerGui, "RoundHudThreat in PlayerGui")
	check(threat.DisplayOrder == 20, "RoundHudThreat at DisplayOrder 20 (BUILD-PLAN 1.4)")
	check(threat.ScreenInsets == Enum.ScreenInsets.None and threat.IgnoreGuiInset == true, "full screen, under the notch")
	check(threat.ResetOnSpawn == false, "survives a respawn")
	local SPEC = {
		ChaseEdgeLeft = {0, 0, UDim2.new(), UDim2.fromScale(0.146, 1), 0},
		ChaseEdgeRight = {1, 0, UDim2.fromScale(1, 0), UDim2.fromScale(0.146, 1), 180},
		ChaseEdgeTop = {0, 0, UDim2.new(), UDim2.fromScale(1, 0.185), 90},
		ChaseEdgeBottom = {0, 1, UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.185), 270},
	}
	check(#threat:GetChildren() == 4, "exactly four bands")
	for name, spec in pairs(SPEC) do
		local band = ctx:Band(name)
		check(band and band.ClassName == "Frame", name .. " exists (K6 names)")
		check(band.AnchorPoint.X == spec[1] and band.AnchorPoint.Y == spec[2], name .. " AnchorPoint")
		check(band.Position == spec[3] and band.Size == spec[4], name .. " Position and Size: " .. tostring(band.Size))
		check(band.Active == false and band.BorderSizePixel == 0, name .. " is inert")
		check(band.BackgroundColor3 == P.Coral, name .. " is Coral")
		check(band.BackgroundTransparency == 1, name .. " starts at transparency 1")
		local gradient = band:FindFirstChildOfClass("UIGradient")
		check(gradient and gradient.Rotation == spec[5], name .. " gradient rotation " .. spec[5])
		local keys = gradient.Transparency.Keypoints
		check(keys[1].Value == 0 and keys[#keys].Value == 1, name .. " gradient runs 0 -> 1 from the screen edge")
		check(ctx:LastTween(band) == nil, name .. " is not tweened at boot")
	end
	check(#ctx.RunService.Heartbeat.entries == 1, "one Heartbeat connection")
	check(ctx.Marker and ctx.Marker.ClassName == "CanvasGroup" and ctx.Marker.Visible == false,
		"the marker is mounted hidden in the RoundHud gui")
end

-- == 2. edge truth table ========================================================================
do
	local ctx = roundContext()
	local CONDITIONS = {"alive", "dead", "Spectating", "Escaped", "InRound false", "RoundActive false"}
	local function baseline()
		ctx.Humanoid.Health = 100
		ctx:Set({Spectating = "nil", Escaped = "nil", InRound = true, BeingChased = true})
		ctx.Workspace:SetAttribute("RoundActive", true)
		ctx.Workspace:SetAttribute("SelectedLevel", 1)
		ctx:Step()
		check(ctx:Edge() == 0.8, "baseline: chased on Level 1 draws the edge")
	end
	local cases = 0
	for level = 1, 4 do
		for _, flag in ipairs({true, false, "nil"}) do
			for _, condition in ipairs(CONDITIONS) do
				baseline()
				ctx.Workspace:SetAttribute("SelectedLevel", level)
				ctx:Set({BeingChased = flag})
				if condition == "dead" then ctx.Humanoid.Health = 0
				elseif condition == "Spectating" then ctx:Set({Spectating = true})
				elseif condition == "Escaped" then ctx:Set({Escaped = true})
				elseif condition == "InRound false" then ctx:Set({InRound = false})
				elseif condition == "RoundActive false" then ctx.Workspace:SetAttribute("RoundActive", false) end
				ctx:Step()
				local on = flag == true and level ~= 2 and condition == "alive"
				local label = ("level %d, BeingChased %s, %s"):format(level, tostring(flag), condition)
				check(ctx:Edge() == (on and 0.8 or 1), label .. ": edge " .. (on and "on" or "off"))
				check(ctx:EdgeTime() == (on and 0.18 or 0.4), label .. ": tween time " .. tostring(ctx:EdgeTime()))
				cases += 1
			end
		end
	end
	check(cases == 72, "4 levels x 3 flags x 6 conditions")
end

-- == 3. ReduceFlashing is never read ============================================================
do
	local seen = {}
	for _, value in ipairs({true, false, "nil"}) do
		local ctx = roundContext()
		ctx:Set({ReduceFlashing = value, BeingChased = true})
		ctx:Step()
		local on = ctx:LastTween(ctx:Band("ChaseEdgeTop"))
		ctx:Set({BeingChased = "nil"})
		ctx:Step()
		local off = ctx:LastTween(ctx:Band("ChaseEdgeTop"))
		table.insert(seen, {on.Goal.BackgroundTransparency, on.Time, off.Goal.BackgroundTransparency, off.Time})
	end
	for index = 2, 3 do
		for field = 1, 4 do
			check(seen[index][field] == seen[1][field], "ReduceFlashing changes nothing (field " .. field .. ")")
		end
	end
	check(seen[1][1] == 0.8 and seen[1][2] == 0.18 and seen[1][3] == 1 and seen[1][4] == 0.4, "static 0.8, 0.18 in, 0.4 out")
end

-- == 5. priority: 18 combinations (K12) =========================================================
do
	local cases = 0
	for _, grace in ipairs({false, true}) do
		for _, hidden in ipairs({"none", "Level3_Hiding", "Level4_Hidden"}) do
			for _, noise in ipairs({"walk", "sprint", "crouch"}) do
				local ctx = roundContext()
				ctx:Speed(3, 0, 0)
				ctx:Set({MoveNoise = noise})
				if grace then
					ctx:Set({PlayerProtectionActive = true, PlayerProtectionSource = "Reentry",
						PlayerProtectionExpiresAt = ctx.Now + 10})
				end
				if hidden ~= "none" then ctx:Set({[hidden] = true}) end
				ctx:Step(0)
				local want, dot = nil, P.RailTeal
				if grace then want = graceText(10)
				elseif hidden ~= "none" then want = "HIDDEN"
				elseif noise == "sprint" then want, dot = "LOUD", P.Amber
				elseif noise == "crouch" then want = "SNEAKING" end
				local label = ("grace %s, %s, %s"):format(tostring(grace), hidden, noise)
				if want then
					check(ctx:Shown() and ctx:Text() == want, label .. ": " .. want .. " (got " .. ctx:Text() .. ")")
					check(ctx:Part("Dot").BackgroundColor3 == dot, label .. ": Dot colour")
					check(ctx:Part("Label").TextColor3 == P.Sage, label .. ": the Label keeps Sage (D4)")
				else
					check(not ctx:Shown(), label .. ": walking shows nothing")
				end
				cases += 1
			end
		end
	end
	check(cases == 18, "2 x 3 x 3 combinations")

	local still = roundContext()
	still:Set({MoveNoise = "sprint"})
	still:Speed(1, 0, 0)
	still:Run(2)
	check(not still:Shown(), "sprint at speed 1 is not LOUD (D5)")
	still:Speed(0, -50, 0)
	still:Run(2)
	check(not still:Shown(), "sprint while falling straight down is not LOUD (horizontal speed only, K8)")
	still:Speed(1.5, -50, 1.5)
	still:Step()
	check(still:Shown() and still:Text() == "LOUD", "sqrt(1.5^2 + 1.5^2) > 2 is LOUD")
end

-- == 6. Attention ================================================================================
do
	local ctx = roundContext()
	ctx:Set({MoveNoise = "crouch"})
	ctx:Step()
	check(ctx:Shown() and near(ctx:Opacity(), 1), "SNEAKING shows at 100 %")
	check(ctx:Part("Soft").BackgroundTransparency == 1, "SNEAKING has no backing")
	ctx:Advance(5.9)
	check(near(ctx:Opacity(), 1), "still 100 % at 5.9 s")
	ctx:Advance(0.1)
	check(near(ctx:Opacity(), 0.45), "45 % at 6 s")

	ctx:Set({Level3_Hiding = true})
	ctx:Step()
	check(ctx:Text() == "HIDDEN" and near(ctx:Opacity(), 1), "SNEAKING -> HIDDEN is a change")
	check(ctx:Part("Soft").BackgroundTransparency == 0, "SNEAKING -> HIDDEN restores its backing")
	ctx:Run(7)
	check(near(ctx:Opacity(), 0.45), "HIDDEN rests at 45 %")
	ctx:Set({Level3_Hiding = "nil"})
	ctx:Step()
	check(ctx:Text() == "SNEAKING" and near(ctx:Opacity(), 1), "HIDDEN -> SNEAKING is a change (100 % again)")
	check(ctx:Part("Soft").BackgroundTransparency == 1, "HIDDEN -> SNEAKING removes the backing again")
	ctx:Run(7)
	ctx:Set({MoveNoise = "walk"})
	ctx:Run(1)
	check(not ctx:Shown() and ctx.Marker.Visible == false, "walking hides it")
	ctx:Set({MoveNoise = "crouch"})
	ctx:Step()
	check(ctx:Shown() and near(ctx:Opacity(), 1), "crouching after a Hide is 100 %")

	ctx:Set({MoveNoise = "sprint"})
	ctx:Speed(3, 0, 0)
	ctx:Step()
	check(ctx:Text() == "LOUD" and near(ctx:Opacity(), 1), "LOUD shows at 100 %")
	check(ctx:Part("Soft").BackgroundTransparency == 1, "LOUD has no backing")
	ctx:Run(6.5)
	check(near(ctx:Opacity(), 0.6), "LOUD rests at 60 %")
end

do -- K7: LOUD lingers 0.5 s past the last fast frame
	local ctx = roundContext()
	ctx:Set({MoveNoise = "sprint"})
	ctx:Speed(3, 0, 0)
	ctx:Step(0.1)
	check(ctx:Text() == "LOUD" and ctx:Shown(), "LOUD")
	local tweens = ctx:MarkerTweens()
	ctx:Speed(1, 0, 0)
	ctx:Run(0.3, 0.1)
	check(ctx:Shown() and ctx:Text() == "LOUD", "a 0.3 s slow patch keeps LOUD")
	ctx:Speed(3, 0, 0)
	ctx:Step(0.1)
	check(ctx:MarkerTweens() == tweens, "one LOUD: no new tween through the slow patch")
	ctx:Speed(1, 0, 0)
	ctx:Run(0.6, 0.1)
	check(not ctx:Shown(), "0.6 s slow: LOUD hides")
end

do -- D5 with K7: a WALK's speed lends LOUD no linger
	local ctx = roundContext()
	ctx:Speed(3, 0, 0)
	ctx:Step(0.1)
	ctx:Speed(0, 0, 0)
	ctx:Step(0.1)
	ctx:Set({MoveNoise = "sprint"})
	ctx:Run(0.6, 0.1)
	check(not ctx:Shown() and ctx:MarkerTweens() == 0, "Shift 0.1 s after a walk, standing still: no LOUD blip (D5)")
end

-- == 7. grace ====================================================================================
do
	local ctx = roundContext()
	ctx:Set({MoveNoise = "crouch"})
	check(ctx:Text() == graceText(8), "the template's sample is still in the hidden clone")
	ctx:Step(0)
	check(ctx:Part("Soft").BackgroundTransparency == 1, "before GRACE the SNEAKING backing is absent")
	ctx:Set({PlayerProtectionActive = true, PlayerProtectionSource = "Reentry", PlayerProtectionExpiresAt = ctx.Now + 10})
	ctx:Step(0)
	check(ctx:Shown() and ctx:Text() == graceText(10), "GRACE reads 10 s: " .. ctx:Text())
	check(ctx:Part("Soft").BackgroundTransparency == 0, "SNEAKING -> GRACE restores its backing")
	check(ctx:Part("Dot").BackgroundColor3 == P.RailTeal, "GRACE dot is RailTeal")
	local tweens = ctx:MarkerTweens()
	for elapsed = 1, 9 do
		ctx:Step(1)
		check(ctx:Text() == graceText(10 - elapsed), "counts down: " .. ctx:Text())
		check(ctx:Text() ~= graceText(8) or elapsed == 2, "the 8 s sample only when it is really 8 s")
		check(near(ctx:Opacity(), elapsed < 6 and 1 or 0.45), "the tick never re-wakes it (" .. elapsed .. " s)")
	end
	check(ctx:MarkerTweens() == tweens + 1, "one tween in ten seconds: the rest at 6 s")
	ctx:Step(1)
	check(ctx:Text() == "SNEAKING" and near(ctx:Opacity(), 1), "at 10 s the next state takes over")
	check(ctx:Part("Soft").BackgroundTransparency == 1, "expired GRACE -> SNEAKING removes the backing")

	ctx:Set({PlayerProtectionExpiresAt = ctx.Now + 10})
	ctx:Step(0)
	ctx:Step(3)
	check(ctx:Text() == graceText(7), "a new grace counts down")
	ctx:Set({PlayerProtectionExpiresAt = ctx.Now + 10})
	ctx:Step(0)
	check(ctx:Text() == graceText(10), "a renewal shows 10 again")
	ctx:Set({PlayerProtectionExpiresAt = ctx.Now + 60})
	ctx:Step(0)
	check(ctx:Text() == graceText(10), "clamped to the 10 s window")

	for _, case in ipairs({
		{"Shield", {PlayerProtectionSource = "Shield", PlayerProtectionExpiresAt = ctx.Now + 5}},
		{"inactive", {PlayerProtectionActive = false}},
		{"NaN", {PlayerProtectionExpiresAt = 0 / 0}},
		{"math.huge", {PlayerProtectionExpiresAt = math.huge}},
		{"-math.huge", {PlayerProtectionExpiresAt = -math.huge}},
		{"a string", {PlayerProtectionExpiresAt = "soon"}},
		{"expired", {PlayerProtectionExpiresAt = ctx.Now - 1}},
	}) do
		ctx:Set({PlayerProtectionActive = true, PlayerProtectionSource = "Reentry", PlayerProtectionExpiresAt = ctx.Now + 10})
		ctx:Step(0)
		check(ctx:Text() == graceText(10), case[1] .. ": starts from GRACE")
		ctx:Set(case[2])
		ctx:Step(0)
		check(ctx:Text() == "SNEAKING", case[1] .. " gives no GRACE: " .. ctx:Text())
	end
end

-- == 8. Level 2 ==================================================================================
do
	local ctx = roundContext({Level = 2})
	ctx:Set({MoveNoise = "crouch", BeingChased = true})
	ctx:Run(1)
	check(ctx:Shown() and ctx:Text() == "SNEAKING", "Level 2 shows the marker")
	check(ctx:Edge() == 1 and ctx:LastTween(ctx:Band("ChaseEdgeLeft")) == nil, "Level 2 never draws the edge")
end

-- == 9. spectating, dead, escaped, Level 4 keypad, round end =====================================
do
	local ctx = roundContext({Level = 3})
	ctx:Set({MoveNoise = "crouch", BeingChased = true})
	ctx:Step()
	check(ctx:Shown() and ctx:Edge() == 0.8, "SNEAKING and the Level 3 edge")
	for _, case in ipairs({
		{"Spectating", function() ctx:Set({Spectating = true}) end, function() ctx:Set({Spectating = "nil"}) end},
		{"dead", function() ctx.Humanoid.Health = 0 end, function() ctx.Humanoid.Health = 100 end},
		{"Escaped", function() ctx:Set({Escaped = true}) end, function() ctx:Set({Escaped = "nil"}) end},
	}) do
		case[2]()
		ctx:Run(1) -- the 0.4 s fade-out, then Visible false
		check(not ctx:Shown() and ctx.Marker.Visible == false, case[1] .. ": no marker")
		check(ctx:Edge() == 1, case[1] .. ": no edge")
		case[3]()
		ctx:Step()
		check(ctx:Shown() and ctx:Edge() == 0.8, case[1] .. " cleared: both back")
	end
	ctx:Set({Level4CardOpen = true})
	ctx:Run(0.5)
	check(not ctx:Shown(), "K5: an open Level 4 card hides the marker")
	ctx:Set({Level4CardOpen = "nil"})
	ctx:Step()
	check(ctx:Shown(), "and it comes back when the card closes")

	ctx.Hud.Detector("HIGH", ctx.Now + 30)
	check(ctx.Hud.Gui():FindFirstChild("DetectorCard") ~= nil, "a detector card is up")
	ctx:Set({InRound = false})
	ctx:Step()
	check(ctx.Hud.Gui():FindFirstChild("DetectorCard") == nil, "InRound true -> false calls RoundHud.Clear()")
	ctx:Run(0.5)
	check(not ctx:Shown() and ctx:Edge() == 1, "round over: no marker, no edge")
	check(ctx.Marker.Parent == ctx.Hud.Gui(), "K17: Clear leaves the marker mounted")
	ctx:Set({InRound = true})
	ctx:Step()
	check(ctx:Shown() and ctx:Text() == "SNEAKING" and ctx:Edge() == 0.8, "the next round draws both again")
end

-- == 10. placement ===============================================================================
local function placed(ctx)
	local root, soft = ctx.Marker, ctx:Part("Soft")
	return {X = root.Position.X.Offset, Bottom = root.Position.Y.Offset, W = soft.Size.X.Offset,
		Centre = root.Position.X.Offset + soft.Size.X.Offset / 2}
end
local function centreOf(rect) return (rect.Left + rect.Right) / 2 end

do -- PC 1920 x 1080
	local ctx = roundContext()
	local safe = ctx.Layout.Safe
	ctx:Set({MoveNoise = "crouch"})
	ctx:Step()
	local root, soft, at = ctx.Marker, ctx:Part("Soft"), placed(ctx)
	check(root.AnchorPoint.X == 0 and root.AnchorPoint.Y == 1, "the root hangs from its bottom-left")
	check(at.Bottom == math.floor(safe.Bottom - 54), "PC: bottom at Safe.Bottom - 54 (D8)")
	check(math.abs(at.Centre - centreOf(safe)) <= 1, "PC: centred on Safe: " .. at.Centre)
	check(soft.AnchorPoint.X == 0 and soft.AnchorPoint.Y == 0.5 and soft.Position == UDim2.fromScale(0, 0.5), "Soft is anchored left")
	check(near(at.W, 20 + 8 * CHAR_W + 8) and soft.Size.Y.Scale == 1, "SNEAKING: W = 20 + 8 x 7.36 + 8 = " .. at.W)
	check(root.AbsoluteSize.X == math.ceil(at.W) and root.Size.Y.Offset == 24, "K6: the group clips to ceil(W) x 24")
	local inner = root:FindFirstChild("NoiseMarker")
	check(inner and inner.Size == UDim2.fromOffset(240, 24), "K6: the clone stays pinned at 240 x 24")
	check(ctx:Part("Label").TextSize == 16, "the label draws at 16 px")
	ctx:Set({PlayerProtectionActive = true, PlayerProtectionSource = "Reentry", PlayerProtectionExpiresAt = ctx.Now + 10})
	ctx:Step(0)
	at = placed(ctx)
	check(ctx:Text() == graceText(10) and near(at.W, pill(graceText(10))), "PC keeps the full GRACE copy")
	check(root.AbsoluteSize.X == math.ceil(at.W) and math.abs(at.Centre - centreOf(safe)) <= 1, "re-hugged and re-centred")
	check(at.W <= 240, "the full pill fits the 240 px clone")
end

do -- PC 1366 x 768: clear of B1's kit row (K4)
	local ctx = roundContext({Layout = LAYOUTS.PC1366})
	local safe = ctx.Layout.Safe
	ctx:Set({PlayerProtectionActive = true, PlayerProtectionSource = "Reentry", PlayerProtectionExpiresAt = ctx.Now + 10})
	ctx:Step(0)
	local at = placed(ctx)
	check(centreOf(safe) < safe.Left + 544 + 8 + 160, "1366: the Safe centre would sit on the kit row")
	check(math.abs(at.Centre - (safe.Left + 544 + 8 + 160)) <= 1, "1366: centred over the moved bar: " .. at.Centre)
	check(at.X >= safe.Left + 544 + 8, "1366: even the full GRACE pill clears the kit row")
	check(at.Bottom == math.floor(safe.Bottom - 54), "1366: bottom at Safe.Bottom - 54")
end

do -- narrow PC: full GRACE clears the active detector and maximum kit band
	for _, layout in ipairs({LAYOUTS.PC800, LAYOUTS.PC640}) do
		local ctx = roundContext({Layout = layout})
		ctx:Set({PlayerProtectionActive = true, PlayerProtectionSource = "Reentry", PlayerProtectionExpiresAt = ctx.Now + 10})
		ctx.Hud.Detector("HIGH", ctx.Now + 10)
		ctx:Step(0)
		local at, safe = placed(ctx), layout.Safe
		local detector = ctx.Hud.Gui():FindFirstChild("DetectorCard")
		check(ctx:Shown() and ctx:Text() == graceText(10), "narrow PC retains full 10s GRACE")
		check(at.X >= safe.Left and at.X + math.ceil(at.W) <= safe.Right, "narrow PC marker fits Safe")
		check(math.abs(at.Centre - centreOf(safe)) <= 1 and at.Bottom == math.floor(safe.Bottom - 258),
			"narrow PC marker centred in fixed upper band")
		check(detector.Visible and detector.Position.Y.Offset - detector.Size.Y.Offset >= at.Bottom + 4 + 26 + 8,
			"full GRACE has 4px to bar and 8px from bar to active detector")
		check(at.Bottom - 24 >= safe.Top, "narrow PC marker fits Safe vertically")
		ctx.Hud.Caption("USHER", "Shhh...")
		local caption = ctx.Hud.Gui():FindFirstChild("Caption")
		check(caption.Visible and caption.Position.Y.Offset >= safe.Top
			and caption.Position.Y.Offset + caption.Size.Y.Offset <= at.Bottom - 24 - 8,
			"narrow PC caption clears full GRACE marker by8px")
		ctx:Set({Spectating = true})
		ctx:Step(0)
		check(caption.Position.Y.Offset + caption.Size.Y.Offset <= safe.Bottom - 228 - 92 - 26 - 8,
			"narrow spectate caption sits above the raised watched-stamina bar")
	end
end

do -- B5 actual common driver: source level, serial, actor/detail gates and appended alive count.
	local ctx = roundContext()
	local function fire(kind, ...) ctx.RoundStatus.OnClientEvent:Fire(kind, ...); ctx:Step(0) end
	local function row(index) return ctx.Hud.Gui():FindFirstChild("FeedRow" .. (index or 1)) end
	local function detail(index) return row(index) and find(row(index), "Words/Detail").Text end
	fire("objective", {Level = 2, Serial = 1, Actor = "Other", Detail = "wrong level"})
	fire("objective", {Level = 1, Serial = 0/0, Actor = "Other", Detail = "invalid serial"})
	check(row() == nil, "B5 wrong level and invalid serial produce no row")
	fire("objective", {Level = 1, Serial = 1, Actor = "Other", Detail = "found a fuse", Key = "level1:fuse"})
	check(row() and detail() == "found a fuse", "B5 server objective routed to shared feed")
	fire("objective", {Level = 1, Serial = 1, Actor = "Other", Detail = "duplicate serial"})
	check(detail() == "found a fuse", "B5 duplicate monotonic serial rejected")
	ctx.Hud.Feed({Kind = "TEAM", Actor = "Other", Detail = "found a fuse", Key = "level1:fuse"})
	check(row(2) == nil, "B5 server and legacy validated team event merge by shared key")
	fire("objective", {Level = 1, Serial = 2, Actor = 23, Detail = "invalid actor"})
	check(row(2) == nil, "B5 actor/detail type gates retained")
	fire("death", ctx.Player.Name, Vector3.new(), "CORRIDOR_ENTITY", 3)
	check(row(2) == nil, "B5 own death belongs to death card")
	fire("death", "Other", Vector3.new(), "CORRIDOR_ENTITY", 3)
	check(detail(2) == "is down \u{B7} 3 left", "B5 appended aliveCount read after cause")
	fire("escape", "Other")
	check(detail(2) == "is down \u{B7} 3 left", "B5 escape is owned only by RoundUI")
	ctx:Set({InRound = false})
	ctx:Step(0)
	check(row() == nil, "B5 teardown on InRound transition removes pooled feed")
	fire("objective", {Level = 1, Serial = 3, Actor = "Other", Detail = "lobby stale"})
	check(row() == nil, "B5 InRound false rejects stale server objective")
end

do -- Studio QA calls the real player's module cache; production has no bindable probe.
	local ctx = roundContext()
	local probe = ctx.Hud.Gui():FindFirstChild("UIRegressionRoundHudProbe")
	check(probe and probe:IsA("BindableFunction"), "Studio cached-module probe exists")
	local empty = probe.OnInvoke("capture")
	check(probe.OnInvoke("setobjective", {Level = 1, Title = "RESTORE THE POWER", Count = 1, Goal = 3,
		Tag = "FUSE BOXES", Lines = {}}), "probe setobjective reaches actual cached owner")
	ctx:Flush()
	check(ctx.Hud.Gui():FindFirstChild("ObjectiveCard") ~= nil and ctx.Hud.LastObjective() == probe.OnInvoke("snapshot"),
		"probe snapshot and caller share module instance")
	check(probe.OnInvoke("restore", empty), "probe cleanup restores prior owned state")
	ctx:Flush()
	check(ctx.Hud.LastObjective() == nil and ctx.Hud.Gui():FindFirstChild("ObjectiveCard") == nil, "probe restores nil loss snapshot")
	local production = roundContext({IsStudio = false})
	check(production.Hud.Gui():FindFirstChild("UIRegressionRoundHudProbe") == nil, "no Studio probe in production")
end

do -- touch 844 x 390
	local ctx = roundContext({Layout = LAYOUTS.Phone})
	local layout, safe = ctx.Layout, ctx.Layout.Safe
	check(math.abs(layout.Corridor.Width - 191) < 1, "the 844 x 390 corridor is 191 wide (critic K3)")
	ctx:Set({MoveNoise = "crouch"})
	ctx:Step()
	local at = placed(ctx)
	check(at.Bottom == math.floor(safe.Bottom - 22), "touch: bottom at Safe.Bottom - 22")
	check(math.abs(at.Centre - centreOf(layout.Corridor)) <= 1, "touch: centred in the corridor (K15: its centre)")
	ctx:Set({PlayerProtectionActive = true, PlayerProtectionSource = "Reentry", PlayerProtectionExpiresAt = ctx.Now + 10})
	ctx:Step(0)
	at = placed(ctx)
	check(ctx:Text() == shortGrace(10), "D11: the phone reads the short copy: " .. ctx:Text())
	check(at.W <= layout.Corridor.Width and math.abs(at.Centre - centreOf(layout.Corridor)) <= 1, "and it fits the corridor")
	check(at.Bottom == math.floor(safe.Bottom - 22), "in the corridor's band")
end

do -- the 1024 x 768 tablet keeps the full copy
	local ctx = roundContext({Layout = LAYOUTS.Tablet})
	check(ctx.Layout.Corridor.Width >= pill(graceText(10)), "the tablet corridor holds the full pill")
	ctx:Set({PlayerProtectionActive = true, PlayerProtectionSource = "Reentry", PlayerProtectionExpiresAt = ctx.Now + 10})
	ctx:Step(0)
	check(ctx:Text() == graceText(10), "tablet: the full copy")
	check(math.abs(placed(ctx).Centre - centreOf(ctx.Layout.Corridor)) <= 1, "tablet: in the corridor")
end

do -- 667 x 375 (K3): SNEAKING stays in the corridor, GRACE moves to ModalArea, above an open fan
	local ctx = roundContext({Layout = LAYOUTS.Small})
	local layout, safe = ctx.Layout, ctx.Layout.Safe
	check(math.abs(layout.Corridor.Width - 88) < 1, "the 667 x 375 corridor is 88 wide (critic K3)")
	ctx:Set({MoveNoise = "crouch"})
	ctx:Step()
	local at = placed(ctx)
	check(at.W <= layout.Corridor.Width + 16, "SNEAKING fits the corridor and its gutters")
	check(at.Bottom == math.floor(safe.Bottom - 22) and math.abs(at.Centre - centreOf(layout.Corridor)) <= 1,
		"667: SNEAKING sits in the corridor")
	ctx:Set({PlayerProtectionActive = true, PlayerProtectionSource = "Reentry", PlayerProtectionExpiresAt = ctx.Now + 10})
	ctx:Step(0)
	at = placed(ctx)
	local area = layout.ModalArea
	check(ctx:Text() == shortGrace(10), "667: the short copy")
	check(at.Bottom == math.floor(area.Bottom - 32) and math.abs(at.Centre - centreOf(area)) <= 1,
		"667: GRACE takes ReentryGrace's ModalArea spot")
	local open = table.clone(layout)
	open.KitFanOpen = true
	ctx.Layout = open
	ctx:Device({})
	ctx:Step()
	at = placed(ctx)
	check(at.Bottom == math.floor(math.min(area.Bottom, layout.KitFan.Top - 8) - 32), "667: above the open KIT fan (C9)")
	check(at.Bottom <= layout.KitFan.Top, "the pill clears the fan")
	ctx.Layout = layout
	ctx:Device({})
	ctx:Step()
	check(placed(ctx).Bottom == math.floor(area.Bottom - 32), "the fan closes: back down")
end

do -- portrait: no corridor, every state in ModalArea
	local ctx = roundContext({Layout = LAYOUTS.Portrait})
	check(ctx.Layout.Corridor.Width == 0, "portrait has no corridor")
	ctx:Set({MoveNoise = "crouch"})
	ctx:Step()
	local at, area = placed(ctx), ctx.Layout.ModalArea
	check(ctx:Text() == "SNEAKING" and math.abs(at.Centre - centreOf(area)) <= 1
		and at.Bottom == math.floor(area.Bottom - 32), "portrait: SNEAKING in ModalArea")
end

do -- a device flip re-places the pill without a text change
	local ctx = roundContext()
	ctx:Set({MoveNoise = "crouch"})
	ctx:Step()
	ctx.Layout = LAYOUTS.Phone
	ctx:Device({Touch = true})
	ctx:Step()
	local at = placed(ctx)
	check(at.Bottom == math.floor(LAYOUTS.Phone.Safe.Bottom - 22) and math.abs(at.Centre - centreOf(LAYOUTS.Phone.Corridor)) <= 1,
		"PC -> touch: re-placed in the corridor")
	check(#ctx.Hud.Gui():GetChildren() == 2 and ctx.Hud.Gui():FindFirstChild("UIRegressionRoundHudProbe"):IsA("BindableFunction"),
		"one marker plus one Studio-only cached-module probe")
end

-- == 11. template facts against the dump =========================================================
do
	local ctx = roundContext()
	local template = find(ctx.Templates.HUD_PC, "NoiseMarker")
	check(near(template.Size.X.Scale * 1920, 240, 0.01) and near(template.Size.Y.Scale * 1080, 24, 0.01), "the marker is 240 x 24")
	local label, dot = find(template, "Label"), find(template, "Dot")
	local left = (label.Position.X.Scale - label.AnchorPoint.X * label.Size.X.Scale) * 240
	check(near(left, 20, 0.05), "the Label's left edge is at x 20: " .. left)
	check(label.TextXAlignment == Enum.TextXAlignment.Left, "the Label is left-aligned")
	local dotLeft = (dot.Position.X.Scale - dot.AnchorPoint.X * dot.Size.X.Scale) * 240
	check(near(dotLeft, 8, 0.05) and near(dotLeft + dot.Size.X.Scale * 240, 14, 0.05), "the Dot spans x 8..14")
	check(label:GetAttribute("FW_M100") == 1242 and utf8.len(label:GetAttribute("FW_Text0")) == 27
		and label:GetAttribute("FigmaFontSize") == 12, "the K11 inputs")
	check(near(CHAR_W, 7.36, 1e-9), "K11: CHAR_W = 1242 / 2700 x 16 = 7.36")
	check(find(template, "Soft").AnchorPoint.X == 0.5, "the template itself is never re-anchored")
end

-- == 13. a place without HUD_PC ==================================================================
do
	local ctx = roundContext({Skip = {HUD_PC = true}})
	check(ctx.Marker == nil, "no template: no marker")
	check(ctx:Warned("[RoundHud] missing template: HUD_PC/NoiseMarker") == 1, "warned by path, once")
	ctx:Set({MoveNoise = "crouch", BeingChased = true})
	ctx:Run(1)
	check(ctx:Edge() == 0.8, "the code-drawn edge still turns on")
	check(ctx:Warned("[RoundHud] missing template") == 1, "and nothing warns again")
end

do -- a re-import that lost a part: no marker, and the edge and Clear survive
	local ctx = roundContext({Prepare = function(c) find(c.Templates.HUD_PC, "NoiseMarker/Label"):Destroy() end})
	check(ctx.Marker == nil and ctx:Warned("[Round HUD] HUD_PC/NoiseMarker has no Soft, Dot or Label") == 1,
		"a NoiseMarker without its Label: warned, no marker")
	ctx:Set({MoveNoise = "crouch", BeingChased = true})
	ctx:Run(1)
	check(ctx:Edge() == 0.8, "the edge still turns on")
	ctx.Hud.Detector("HIGH", ctx.Now + 30)
	ctx:Set({InRound = false})
	ctx:Step()
	check(ctx.Hud.Gui():FindFirstChild("DetectorCard") == nil and ctx:Edge() == 1, "and the round end still clears")
end

print("Round HUD: " .. checks .. " checks passed (offline Luau; real Round HUD, RoundHud and UIDevice over the HUD_PC import)")
'''


def strip_comments(lua_text):
    """Lua source with every -- comment removed (no long strings or '--' in strings here)."""
    return "\n".join(line.split("--", 1)[0] for line in lua_text.splitlines())


def section(text, begin, end):
    start = text.index(begin)
    return text[start:text.index(end, start)]


def static_checks(raw):
    assert all(byte < 128 for byte in raw), "Round HUD must be ASCII-only (install_new_scripts embeds it with json.dumps)"
    assert b"\r" not in raw, "Round HUD must have LF line endings"
    text = raw.decode("ascii")
    edge = strip_comments(section(text, EDGE_BEGIN, EDGE_END))
    for banned in ("os.clock", "tick(", "time(", "sin(", "ReduceFlashing"):
        assert banned not in edge, "the chase edge section uses " + banned
    marker = section(text, MARKER_BEGIN, MARKER_END)
    assert "HUD_PC" in marker and "NoiseMarker" in marker, "the marker section mounts HUD_PC/NoiseMarker"
    code = strip_comments(text)
    assert "ADRENALINE" not in text, "ADRENALINE is never drawn"
    for name in ("RoundHud", "ZyntraHUD", "ZyntraShopUI"):
        assert 'WaitForChild("%s"' % name not in code, "Round HUD waits on " + name
    assert code.count("Heartbeat:Connect") == 1, "one Heartbeat connection"
    assert ".Visible =" not in code, "Attention owns Visible: Round HUD never writes it"


def numeric_locals(text):
    """{NAME: value} for every `local A, B = 1, 2` line whose names are UPPER_CASE and values numbers."""
    out = {}
    pattern = re.compile(r"^\s*local\s+([A-Z][A-Z0-9_]*(?:\s*,\s*[A-Z][A-Z0-9_]*)*)\s*=\s*"
                         r"(-?[\d.]+(?:\s*,\s*-?[\d.]+)*)\s*(?:--.*)?$", re.M)
    for match in pattern.finditer(text):
        names = [name.strip() for name in match.group(1).split(",")]
        values = [float(value) for value in match.group(2).split(",")]
        if len(names) == len(values):
            out.update(zip(names, values))
    return out


def stamina_bar_size():
    root = json.loads((DUMPS / "framewisp-dump.HUD_PC.json").read_text(encoding="utf-8"))["root"]
    bar = next(child for child in root["Children"] if child["Name"] == "StaminaBar")
    attrs = root["Attributes"]
    return round(bar["Size"][0] * attrs["BB_DesignW"]), round(bar["Size"][2] * attrs["BB_DesignH"])


def cross_check():
    """Test 12: one source per number, pinned on both sides (B3-DESIGN 2.2, critic K4)."""
    mine = numeric_locals(SCRIPT.read_text(encoding="utf-8"))
    noise = numeric_locals(NOISE.read_text(encoding="utf-8"))
    width, height = stamina_bar_size()
    assert (width, height) == (320, 26), "the StaminaBar template is 320 x 26: %r" % ((width, height),)
    assert mine.get("BAR_HALF") == width / 2, "BAR_HALF is half the StaminaBar template"
    missing = [name for name in ("BAR_BOTTOM", "BAR_BOTTOM_TOUCH", "BAR_TOUCH_SCALE", "KIT_RIGHT") if name not in noise]
    if missing:
        raise SystemExit("test_round_hud_local: check 12 RED (expected until B3 agent B lands NoiseReporter's bar "
                         "section, critic K13): NoiseReporter states no " + ", ".join(missing))
    assert mine["MARKER_BOTTOM"] == noise["BAR_BOTTOM"] + height + 4, "MARKER_BOTTOM = BAR_BOTTOM + 26 + 4"
    assert mine["MARKER_BOTTOM_NARROW"] == noise["BAR_BOTTOM_NARROW"] + height + 4, "narrow marker preserves 4px gap"
    assert mine["MARKER_BOTTOM_TOUCH"] == noise["BAR_BOTTOM_TOUCH"] + height * noise["BAR_TOUCH_SCALE"] + 5, \
        "MARKER_BOTTOM_TOUCH = BAR_BOTTOM_TOUCH + 26 x BAR_TOUCH_SCALE + 5"
    assert mine["KIT_RIGHT"] == noise["KIT_RIGHT"], "KIT_RIGHT agrees in both files (K4)"
    print("Round HUD cross-check: MARKER_BOTTOM %g, MARKER_BOTTOM_TOUCH %g, KIT_RIGHT %g agree with NoiseReporter"
          % (mine["MARKER_BOTTOM"], mine["MARKER_BOTTOM_TOUCH"], mine["KIT_RIGHT"]))


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    raw = SCRIPT.read_bytes()
    static_checks(raw)
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    if Path(compiler).exists():
        subprocess.run([compiler, "--null", str(SCRIPT)], check=True, capture_output=True)
    else:
        print("luau-compile not found; compile check skipped.")
    inject = "local SOURCES = {\n%s\n}\nlocal TREES = %s\nlocal ROUND_HUD_SOURCE = %s\n" % (
        ",\n".join("%s = %s" % (name, long_string(path.read_text(encoding="utf-8"))) for name, path in SOURCES.items()),
        lua(trees()), long_string(raw.decode("ascii")))
    harness = HARNESS.read_text(encoding="utf-8")
    assert "--@@INJECT@@" in harness
    program = "".join([
        harness.replace("--@@INJECT@@", inject, 1),
        "\nlocal LAYOUTS = {}\nlocal function addChecks(count) checks += count end\ndo\n",
        ENGINE, CONTEXT, BOOTS, wrap("UIDeviceSource", UIDEVICE.read_text(encoding="utf-8")), LAYOUT_BLOCK,
        "\nend\n",
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="round-hud-local-") as directory:
        path = Path(directory) / "round_hud_local.luau"
        path.write_text(program, encoding="utf-8")
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=180)
    if result.returncode != 0 or "checks passed" not in result.stdout:
        print(result.stdout.strip()[-4000:])
        print(result.stderr.strip()[-4000:])
        raise SystemExit("test_round_hud_local FAILED")
    print(result.stdout.strip().splitlines()[-1])
    cross_check()


if __name__ == "__main__":
    main()
