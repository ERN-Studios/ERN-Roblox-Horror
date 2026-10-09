"""Run the real StarterPlayerScripts/ZyntraDetectorClient offline (owner, 2026-10-08; HUD batch B1, 09 C).

BUILD-PLAN.md 2 "09" and 4 B1 QA, FRAMEWISP-PIPELINE.md 2.6 (artifacts/hud-final-20261008/). The REAL
client drives the REAL RoundHud (with ShopBinder, UIStyle and ZyntraDetectorVisual) inside the fake
engine of tools/tests/hud_harness.luau, over the same template trees as test_round_hud.py (the real
HUD_PC and HUD_Touch imports from tools/tests/fixtures/hud).

Checked: the 1100 handheld gui is gone and the reading lands on RoundHud's DetectorCard (order 10, under
RoundUI's 100); LOW / MEDIUM / HIGH copy and colours; 100 % for 4 s then hidden, HIGH never dims; the
card sits above the SCAN chip on PC and is the one feed-lane line on touch; the live band
(ZyntraDetectorReading) and the server's cut-short (ZyntraDetectorReadingUntil, after the first second);
the stand-down gates (death, respawn, InRound, RoundActive -- the results --, Escaped, Spectating,
PARTY DOWN, a screen-owning modal, a dispatch briefing, a stowed detector) and the way back from the
ones that lift; the local ping; RoundHud is called on a change only, never per frame. Plus: the client is
ASCII-only with LF endings and luau-compile accepts it.

Set LUAU_BIN (luau 0.737; luau-compile.exe is expected beside it, or LUAU_COMPILE_BIN).
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import test_round_hud as base  # noqa: E402  (the shared HUD fixture: sources, trees, Lua literals)

CLIENT = base.ROOT / "StarterPlayer/StarterPlayerScripts/ZyntraDetectorClient.LocalScript.lua"

TESTS = r'''
local B = "\u{B7}"
local P = {
	Sage = Color3.fromRGB(167, 184, 174), Amber = Color3.fromRGB(232, 160, 36),
	Coral = Color3.fromRGB(242, 112, 95), Line = Color3.fromRGB(38, 49, 52),
}
local function opacity(group) return 1 - group.GroupTransparency end
methods.Play = function(self) self.Playing = true end -- Sound:Play, for the local ping

-- UIDevice.ScreenOwningModalOpen at its published contract (UIDevice SCREEN_OWNING_MODALS).
local MODALS = {"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen",
	"LuckyWheelOpen", "DailyRewardsOpen", "AchievementsOpen", "HelpPanelOpen"}

-- A living participant in a live round, with the real client running.
local function client(opts)
	local ctx = context(opts)
	local player = ctx.Player
	player.CharacterRemoving = signal()
	function ctx.UIDevice.ScreenOwningModalOpen()
		for _, attribute in ipairs(MODALS) do
			if player:GetAttribute(attribute) == true then return true end
		end
		return false
	end
	local remotes = newInstance("Folder", "Remotes")
	remotes.Parent = ctx.Storage
	local remote = newInstance("RemoteEvent", "ZyntraDetector")
	remote.Parent = remotes
	local runService = {RenderStepped = signal()}
	local sounds = newInstance("SoundService", "SoundService")
	local services = {Players = {LocalPlayer = player}, ReplicatedStorage = ctx.Storage,
		RunService = runService, SoundService = sounds}
	local body = newInstance("Model", "Character")
	local humanoid = newInstance("Humanoid", "Humanoid")
	humanoid.Health = 100
	humanoid.Parent = body
	player.Character = body
	player:SetAttribute("InRound", true)
	ctx.Workspace:SetAttribute("RoundActive", true)

	local Hud = ctx:Require("RoundHud")
	ctx.Calls = 0
	local detector = Hud.Detector
	Hud.Detector = function(...)
		ctx.Calls += 1
		return detector(...)
	end
	local scriptInstance = newInstance("LocalScript", "ZyntraDetectorClient")
	local fn = assert(loadstring(CLIENT, "=ZyntraDetectorClient"))
	setfenv(fn, setmetatable({
		game = {GetService = function(_, name) return assert(services[name], "service " .. name) end},
		workspace = ctx.Workspace, script = scriptInstance, task = ctx.Task, Instance = Instance, Enum = Enum,
		os = setmetatable({clock = function() return ctx.Now end}, {__index = os}),
		require = function(module)
			if module.Name == "UIDevice" then return ctx.UIDevice end
			return ctx:Require(module.Name)
		end,
	}, {__index = _G}))
	fn()
	ctx:Flush()

	ctx.Hud, ctx.Remote, ctx.Sounds, ctx.Script, ctx.Humanoid = Hud, remote, sounds, scriptInstance, humanoid
	ctx.Hook = runService.RenderStepped
	function ctx:Frame()
		self.Hook:Fire(1 / 60)
		self:Flush()
	end
	-- Advance the clock in 50 ms frames.
	function ctx:Run(seconds)
		local steps = math.max(1, math.round(seconds / 0.05))
		for _ = 1, steps do
			self:Advance(seconds / steps)
			self:Frame()
		end
	end
	function ctx:Scan(reading, expires)
		player:SetAttribute("ZyntraDetectorReading", reading)
		player:SetAttribute("ZyntraDetectorReadingUntil", expires)
		remote.OnClientEvent:Fire("reading", reading, expires)
		self:Frame()
	end
	function ctx:Card() return Hud.Gui():FindFirstChild("DetectorCard") end
	function ctx:Shown()
		local card = self:Card()
		return card ~= nil and card.Visible and near(opacity(card), 1)
	end
	function ctx:Gone()
		local card = self:Card()
		return card == nil or card.Visible == false
	end
	return ctx
end

-- == PC: a MEDIUM scan =======================================================================
do
	local ctx = client()
	local player = ctx.Player
	player:SetAttribute("ZyntraDetectorStowed", true)
	ctx:Scan("MEDIUM", 30)
	for _, child in ipairs(ctx.PlayerGui:GetChildren()) do
		check(child.Name ~= "ZyntraDetectorReadout", "the 1100 handheld gui is gone")
	end
	local gui = ctx.Hud.Gui()
	check(#ctx.PlayerGui:GetChildren() == 1 and gui.Parent == ctx.PlayerGui, "the reading draws only into RoundHud")
	check(gui.DisplayOrder == 10 and gui.DisplayOrder < 100, "RoundHud (10) sits under RoundUI's results and PARTY DOWN (100)")
	local card = ctx:Card()
	check(card and card.ClassName == "CanvasGroup", "a scan mounts the C card")
	check(ctx:Shown(), "a scan shows the card at 100 %")
	check(find(card, "Reading").Text == "SCAN " .. B .. " MEDIUM" and find(card, "Reading").TextColor3 == P.Amber,
		"MEDIUM reads SCAN . MEDIUM in Amber")
	check(find(card, "Headline").Text == "ENTITY NEARBY", "MEDIUM: ENTITY NEARBY")
	check(find(card, "Seconds").Text == "30 s", "the seconds left: " .. find(card, "Seconds").Text)
	check(find(card, "Bars/Bar2").BackgroundColor3 == P.Amber and find(card, "Bars/Bar3").BackgroundColor3 == P.Line,
		"MEDIUM lights two bars")
	check(player:GetAttribute("ZyntraDetectorStowed") == nil, "a fresh scan comes up in the hand (stowed cleared)")
	local ping = ctx.Sounds:FindFirstChild("LocalDetectorPing")
	check(ping and ping.Playing == true, "the local ping plays")
	local calls = ctx.Calls
	ctx:Run(3.9)
	check(ctx:Shown(), "100 % through 3.9 s")
	check(ctx.Calls == calls, "RoundHud is called on a change only, not per frame: " .. ctx.Calls - calls)
	ctx:Run(0.6)
	check(ctx:Gone(), "hidden after 4 s (rest is hidden)")
	ctx:Run(10)
	check(ctx:Gone() and ctx.Calls == calls, "and stays hidden while the reading holds")
	check(#ctx.Hook.entries == 1, "the frame hook runs while the detector is on")
	ctx:Run(16)
	check(ctx:Gone(), "still hidden at expiry")
	check(#ctx.Hook.entries == 0, "the frame hook is released at expiry")
	check(ctx.Sounds:FindFirstChild("LocalDetectorPing") == nil, "and the ping with it")
end

do -- the card sits above the SCAN chip on PC, clear of the refusal-tag band
	local ctx = client({safe = {Left = 0, Top = 0, Right = 1920, Bottom = 1022, Width = 1920, Height = 1022}})
	local protection = newInstance("ScreenGui", "ProtectionHUD")
	protection.Parent = ctx.PlayerGui
	local panel = ctx.Hud.Mount("HUD_PC", "EquipmentPanel", protection)
	find(panel, "Chip_Scan").AbsolutePosition = Vector2.new(400, 930)
	ctx:Scan("LOW", 30)
	local card = ctx:Card()
	check(card.AnchorPoint.Y == 1 and card.Position == UDim2.fromOffset(400, 890),
		"above the SCAN chip and the refusal-tag band: " .. tostring(card.Position))
	check(find(card, "Reading").TextColor3 == P.Sage and find(card, "Headline").Text == "SAFE DISTANCE", "LOW: Sage, SAFE DISTANCE")
end

-- == HIGH never dims; the live band ==========================================================
do
	local ctx = client()
	ctx:Scan("HIGH", 30)
	local card = ctx:Card()
	check(find(card, "Reading").TextColor3 == P.Coral and find(card, "Headline").Text == "ENTITY VERY CLOSE", "HIGH: Coral, ENTITY VERY CLOSE")
	for index = 1, 3 do
		check(find(card, "Bars/Bar" .. index).BackgroundColor3 == P.Coral, "HIGH lights all three bars")
	end
	ctx:Run(20)
	check(ctx:Shown(), "HIGH never dims")
	ctx.Player:SetAttribute("ZyntraDetectorReading", "LOW")
	ctx:Frame()
	check(ctx:Shown() and find(card, "Reading").Text == "SCAN " .. B .. " LOW", "the band follows the entity down")
	ctx:Run(4.5)
	check(ctx:Gone(), "a non-HIGH band hides after its 4 s")
	ctx.Player:SetAttribute("ZyntraDetectorReading", "HIGH")
	ctx:Frame()
	check(ctx:Shown() and find(card, "Headline").Text == "ENTITY VERY CLOSE", "the band coming back up wakes the card")
	ctx.Player:SetAttribute("ZyntraDetectorReading", "BOGUS")
	ctx:Run(5.4)
	check(ctx:Shown() and find(card, "Headline").Text == "ENTITY VERY CLOSE", "an unknown band keeps the last one")
	ctx:Run(0.6)
	check(ctx:Gone() and #ctx.Hook.entries == 0, "it ends at the remote's expiry (plus the 0.4 s fade)")
end

do -- the server cuts the reading short; not inside the first second
	local ctx = client()
	ctx:Scan("HIGH", 30)
	ctx.Player:SetAttribute("ZyntraDetectorReadingUntil", 0)
	ctx:Run(0.9)
	check(ctx:Shown(), "a 0 inside the first second may be the last reading's and is ignored")
	ctx:Run(0.6)
	check(ctx:Gone(), "after it the server's cut-short hides the card (plus the 0.4 s fade)")
	check(#ctx.Hook.entries == 0, "and releases the frame hook")
end

-- The case the grace is for (owner, 2026-10-08; review of B1 09 C): a LATER scan whose event lands while
-- ReadingUntil still holds the cut-short 0 of the last reading. The grace counts from this scan, not
-- from the script's start, so the card survives until the new value arrives.
do
	local ctx = client()
	ctx:Run(20)
	local player = ctx.Player
	player:SetAttribute("ZyntraDetectorReading", "MEDIUM")
	player:SetAttribute("ZyntraDetectorReadingUntil", 0)
	ctx.Remote.OnClientEvent:Fire("reading", "MEDIUM", ctx.Now + 30)
	ctx:Frame()
	ctx:Run(0.5)
	check(ctx:Shown() and #ctx.Hook.entries == 1, "a later scan is not ended by the last reading's stale 0")
	player:SetAttribute("ZyntraDetectorReadingUntil", ctx.Now + 29.5)
	ctx:Run(1.5)
	check(#ctx.Hook.entries == 1, "and keeps running once its own ReadingUntil arrives")
end

-- == stand-down gates ========================================================================
local function gate(label, apply)
	local ctx = client()
	ctx:Scan("HIGH", 30)
	check(ctx:Shown(), label .. ": shown before")
	apply(ctx)
	ctx:Run(0.5)
	check(ctx:Gone(), label .. " hides the card")
	check(#ctx.Hook.entries == 0, label .. " ends the reading")
end
gate("death", function(ctx) ctx.Humanoid.Health = 0 end)
gate("a respawn", function(ctx) ctx.Player.Character = newInstance("Model", "Character") end)
gate("leaving the round", function(ctx) ctx.Player:SetAttribute("InRound", false) end)
gate("the round's end (results)", function(ctx) ctx.Workspace:SetAttribute("RoundActive", false) end)
gate("an escape", function(ctx) ctx.Player:SetAttribute("Escaped", true) end)
gate("spectating", function(ctx) ctx.Player:SetAttribute("Spectating", true) end)
gate("CharacterRemoving", function(ctx) ctx.Player.CharacterRemoving:Fire() end)
gate("the script going", function(ctx) ctx.Script:Destroy() end)

local function standDown(label, attribute, target)
	local ctx = client()
	local subject = target == "workspace" and ctx.Workspace or ctx.Player
	ctx:Scan("HIGH", 30)
	subject:SetAttribute(attribute, true)
	ctx:Run(0.5)
	check(ctx:Gone(), label .. " hides the card")
	check(#ctx.Hook.entries == 1, label .. " keeps the reading alive underneath")
	subject:SetAttribute(attribute, false)
	ctx:Frame()
	check(ctx:Shown(), label .. " closing brings the HIGH card back")
	ctx:Run(10)
	check(ctx:Shown(), "and HIGH still never dims after " .. label)
	subject:SetAttribute(attribute, nil)
	return ctx
end
standDown("PARTY DOWN", "PartyDownCardOpen")
standDown("a dispatch briefing", "DispatchBriefingOpen")
for _, modal in ipairs(MODALS) do standDown(modal, modal) end
do -- the equipment key puts it away and brings it back for 4 s
	local ctx = standDown("a stowed detector", "ZyntraDetectorStowed")
	ctx.Player:SetAttribute("ZyntraDetectorReading", "MEDIUM")
	ctx:Frame()
	ctx:Run(4.5)
	check(ctx:Gone(), "MEDIUM rests hidden")
	ctx.Player:SetAttribute("ZyntraDetectorStowed", true)
	ctx:Run(0.5)
	ctx.Player:SetAttribute("ZyntraDetectorStowed", false)
	ctx:Frame()
	check(ctx:Shown(), "SHOW brings a resting MEDIUM back at 100 %")
	ctx:Run(4.5)
	check(ctx:Gone(), "for 4 s")
end

-- == a fresh scan, bad events ================================================================
do
	local ctx = client()
	ctx:Scan("LOW", 30)
	ctx:Run(5)
	check(ctx:Gone(), "LOW rests hidden")
	ctx.Remote.OnClientEvent:Fire("refused", "SCAN DURING A RUN")
	ctx.Remote.OnClientEvent:Fire("reading", "BOGUS", 60)
	ctx.Remote.OnClientEvent:Fire("reading", "HIGH", "soon")
	ctx:Frame()
	check(ctx:Gone(), "refusals, unknown readings and a non-number expiry draw nothing")
	ctx:Scan("LOW", ctx.Now + 30)
	check(ctx:Shown(), "a fresh scan with the same band shows again")
	local pings = 0
	for _, child in ipairs(ctx.Sounds:GetChildren()) do
		if child.Name == "LocalDetectorPing" then pings += 1 end
	end
	check(pings == 1, "one ping at a time: " .. pings)
	check(#ctx.Hook.entries == 1, "one frame hook at a time")
	check(#ctx.Hud.Gui():GetChildren() == 1, "one card, reused")
end

-- A scan that lands while a gate already holds (owner, 2026-10-08; review of B1 09 C).
do
	local ctx = client()
	ctx.Player:SetAttribute("ZyntraStoreOpen", true)
	ctx:Scan("HIGH", 30)
	check(ctx:Card() == nil, "a scan under a screen-owning modal draws nothing")
	ctx.Player:SetAttribute("ZyntraDetectorReading", "LOW")
	ctx:Run(2)
	ctx.Player:SetAttribute("ZyntraStoreOpen", false)
	ctx:Frame()
	check(ctx:Shown() and find(ctx:Card(), "Reading").Text == "SCAN " .. B .. " LOW",
		"closing it shows the band as it is now, at 100 %")
	ctx:Run(4.5)
	check(ctx:Gone(), "and a LOW still rests hidden after its 4 s")
end
do
	local ctx = client()
	ctx.Humanoid.Health = 0
	ctx:Scan("HIGH", 30)
	check(ctx:Card() == nil and #ctx.Hook.entries == 0, "a reading that reaches a dead body draws nothing and ends")
end

-- == touch and gamepad =======================================================================
do
	local ctx = client({touch = true, viewport = Vector2.new(844, 390),
		safe = {Left = 47, Top = 0, Right = 797, Bottom = 311, Width = 750, Height = 311}})
	ctx:Scan("HIGH", 30)
	local card = ctx:Card()
	local line = card and find(card, "Line")
	check(line and line.Text == "SCAN " .. B .. " HIGH " .. B .. " ENTITY VERY CLOSE", "touch: the one feed-lane line")
	check(line.TextColor3 == P.Coral, "coloured by the reading")
	check(find(card, "Headline") == nil and find(card, "Seconds") == nil, "no PC card texts on touch")
	check(card.Position == UDim2.fromOffset(47 + 68, 52), "in the feed lane: " .. tostring(card.Position))
	check(ctx:Shown(), "shown at 100 %")
end
do
	local ctx = client({gamepadEnabled = true, lastInput = "Gamepad"})
	ctx:Scan("MEDIUM", 30)
	check(find(ctx:Card(), "Headline") ~= nil, "a gamepad gets the PC card")
end

print("ZyntraDetectorClient: " .. checks .. " checks passed (offline Luau; real HUD_PC import)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    source = CLIENT.read_bytes()
    assert all(byte < 128 for byte in source), "ZyntraDetectorClient must be ASCII-only"
    assert b"\r" not in source, "ZyntraDetectorClient must have LF line endings"
    text = source.decode("ascii")
    code = re.sub(r"--.*", "", text)  # the header comment names what went
    for gone in ("ZyntraDetectorReadout", "1100", "Visual.Preview", '"ScreenGui"'):
        assert gone not in code, "the old handheld readout is back: " + gone
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    if Path(compiler).exists():
        subprocess.run([compiler, "--null", str(CLIENT)], check=True, capture_output=True)
    else:
        print("luau-compile not found; compile check skipped.")
    inject = "local SOURCES = {\n%s\n}\nlocal TREES = %s\nlocal CLIENT = %s\n" % (
        ",\n".join("%s = %s" % (name, base.long_string(path.read_text(encoding="utf-8")))
                   for name, path in base.SOURCES.items()),
        base.lua(base.trees()), base.long_string(text))
    harness = base.HARNESS.read_text(encoding="utf-8")
    assert "--@@INJECT@@" in harness
    program = harness.replace("--@@INJECT@@", inject, 1) + "\n" + TESTS
    with tempfile.TemporaryDirectory(prefix="detector-client-") as directory:
        path = Path(directory) / "detector_client.luau"
        path.write_text(program, encoding="utf-8")
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or "checks passed" not in result.stdout:
        print(result.stdout.strip()[-4000:])
        print(result.stderr.strip()[-4000:])
        raise SystemExit("test_zyntra_detector_client FAILED")
    print(result.stdout.strip().splitlines()[-1])


if __name__ == "__main__":
    main()
