"""Run the real ZyntraRecordsPage under offline Luau with an honest fake Roblox.

CHALLENGES_20260923 (Trello FnF49TWk). The module under test is the whole
shipped file, mounted through the terminal's page contract, with:

  * the REAL ReplicatedStorage/ZyntraChallenges ledger (the same pure module the
    server applies a finished run with), so a key the page reads is a key the
    server writes;
  * the REAL ReplicatedStorage/ZyntraConfig, so the goals (8:00 / 10:00 / 10:00)
    and the rewards (+3 / +3) are asserted against the numbers that ship;
  * the REAL UIStyle and ZyntraStore's real COLORS / corner / outline / label /
    button helpers, extracted by string marker;
  * the SAME fake engine as test_daily_rewards_page.py (imported, not copied):
    no Color3 arithmetic, real UDim2 arithmetic, memoised value types.

What it proves by running the code: the three level cards, m:ss times and a
dash where there is no record, EQUIPPED only beside an equipped record, the
challenge lines reading DONE or the token reward, the one toggle switching
clean <-> assisted without ever sending anything, that toggle being the page's
only control and always reachable, a profile from an older server (no Records,
no Challenges) drawing without error, and at four terminal tiers that every
rectangle sits inside the content box, no two cards overlap, the canvas reaches
the last card, the toggle is at least 44x44 and nothing prints under 11px.

What it CANNOT see: real font metrics and TextBounds (UIRegression's terminal
fit matrix measures those in Studio), UIDevice's real detection and rendering.
Set LUAU_BIN or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_daily_rewards_page import PRELUDE, section  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PAGE = (ROOT / "ReplicatedStorage/ZyntraRecordsPage.ModuleScript.lua").read_text(encoding="utf-8")
LEDGER = (ROOT / "ReplicatedStorage/ZyntraChallenges.ModuleScript.lua").read_text(encoding="utf-8")
UISTYLE = (ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua").read_text(encoding="utf-8")
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")
STORE = (ROOT / "StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua"
         ).read_text(encoding="utf-8")


# The page finds the ledger with FindFirstChild on ReplicatedStorage and requires
# it. The Daily prelude's `require` only knows the research ledger, so this one
# shadows it for the page.
LEDGER_WIRING = r'''
local Ledger -- the real ZyntraChallenges, assigned below
services.ReplicatedStorage = {FindFirstChild = function(_, name)
	if name == "ZyntraChallenges" then return "ZyntraChallenges" end
	return nil
end}
local function require(name)
	if name == "ZyntraChallenges" then return Ledger end
	error("unfaked module " .. tostring(name))
end
'''


HARNESS = r'''
local Config = RealConfig
local DASH, CHECK = "\u{2014}", "\u{2713}"

-- The shipped numbers, written down here rather than read from the module: a
-- test that took them from the code under test would pass whatever it held.
expect(type(Config.Challenges), "table", "ZyntraConfig carries the Challenges block")
expect(Config.Challenges.TimeGoalSeconds["1"], 480, "Level 1 goal is 8:00")
expect(Config.Challenges.TimeGoalSeconds["2"], 600, "Level 2 goal is 10:00")
expect(Config.Challenges.TimeGoalSeconds["3"], 600, "Level 3 goal is 10:00")
expect(Config.Challenges.RewardTokens.NoDeath, 3, "NO DEATHS pays 3")
expect(Config.Challenges.RewardTokens.TimeGoal, 3, "the time goal pays 3")

-- A saved ledger with something in every interesting cell.
local function fullProfile()
	return {
		Tokens = 12,
		Records = {
			["1:solo:clean"] = {Best = 272.4, Equipped = false, At = 1},
			["1:party:clean"] = {Best = 401, Equipped = true, At = 2},
			["2:solo:assisted"] = {Best = 599.9, Equipped = true, At = 3},
			["3:party:assisted"] = {Best = 61, Equipped = false, At = 4},
		},
		Challenges = {NoDeath = {["1"] = true}, TimeGoal = {["2"] = true}},
	}
end

local function newHost(profile)
	local host = {Actions = {}, Cards = {}, Scrolls = {}, Hooks = {}, Listeners = {},
		Disconnects = 0}
	host.Page = newInstance("Frame")
	host.Page.Name = "Records"
	host.Profile = profile
	host.ctx = {
		player = newInstance("Player"),
		Config = Config,
		UIStyle = UIStyle,
		UIDevice = {SetEnabled = function(element, enabled) element.Active = enabled end},
		COLORS = COLORS,
		label = label, button = button, corner = corner, outline = outline,
		pageName = "Records",
		action = function(name, payload)
			table.insert(host.Actions, {Name = name, Payload = payload})
		end,
		profile = function() return host.Profile end,
		onProfile = function(fn)
			table.insert(host.Listeners, fn)
			return function() host.Disconnects += 1 end
		end,
		refreshProfile = function() end,
		showStatus = function() end,
		registerLayoutHook = function(fn) table.insert(host.Hooks, fn) end,
		isVisible = function() return true end,
		contract = {
			scroll = function(page, frame)
				table.insert(host.Scrolls, page .. "|" .. frame.Name)
			end,
			card = function(page, key, card, action)
				table.insert(host.Cards, {Page = page, Key = key, Card = card, Action = action})
			end,
		},
	}
	function host:push(newProfile)
		self.Profile = newProfile
		for _, fn in ipairs(self.Listeners) do fn(newProfile, nil, nil) end
	end
	function host:layout(fit)
		for _, fn in ipairs(self.Hooks) do fn(fit) end
	end
	function host:find(name) return mustFind(self.Page, name) end
	return host
end

-- The fit ZyntraStore's applyTerminalLayout publishes, rebuilt from the same
-- figures (1180x760 design, 260 floor, compact under 640x430, 12/20 padding,
-- 44 touch / 32 pointer tap, 40/42 tabs, 22/30 status). The header height is
-- approximated -- 58 for the stacked narrow header, 54 compact, 70 otherwise --
-- which only moves ContentHeight, and this page scrolls rather than fitting to it.
local function fitFor(viewportWidth, viewportHeight, touch)
	local width = math.floor(math.clamp(math.min(1180, viewportWidth), 260, 1180))
	local height = math.floor(math.min(760, viewportHeight))
	local compact = width < 640 or height < 430
	local tap = touch and 44 or 32
	local pad = compact and 12 or 20
	local gap = compact and 8 or 12
	local tabHeight = math.max(tap, compact and 40 or 42)
	local statusHeight = compact and 22 or 30
	local headerHeight = compact and (width < 420 and 58 or 54) or 70
	return {Width = width, Height = height, ContentWidth = width - pad * 2,
		ContentHeight = height - headerHeight - gap - tabHeight - gap - statusHeight - gap,
		Compact = compact, Touch = touch, Tap = tap, TabHeight = tabHeight,
		TabMinWidth = compact and 88 or 110, DevStacked = width - pad * 2 < 460}
end
local PHONE_PORTRAIT = fitFor(358, 774, true)
local PHONE_LANDSCAPE = fitFor(812, 316, true)
local TABLET = fitFor(992, 716, true)
local POINTER = fitFor(1248, 668, false)
-- The narrowest panel the terminal will ever draw, where the toggle has to
-- give up its place beside the title and take a row of its own.
local FLOOR = fitFor(260, 600, true)

local function mount(host, fit)
	local handle = Page.mount(host.Page, host.ctx)
	host:layout(fit or POINTER)
	return handle
end

local function cardOf(host, level) return host:find("Level" .. tostring(level)) end
local function partOf(host, level, name)
	return assert(cardOf(host, level):FindFirstChild(name), "Level" .. level .. " has no " .. name)
end
local function buttons(host)
	local found = {}
	for _, node in ipairs(descendants(host.Page)) do
		if node.ClassName == "TextButton" or node.ClassName == "ImageButton" then
			table.insert(found, node)
		end
	end
	return found
end

-- Where a node sits inside its own parent, on both axes.
local function insideParent(node)
	local parent = node.Parent
	local x, y = node.Position.OX, node.Position.OY
	return x >= 0 and y >= 0 and x + node.Size.OX <= parent.Size.OX
		and y + node.Size.OY <= parent.Size.OY
end
local function overlaps(a, b)
	local ax, ay = a.Position.OX, a.Position.OY
	local bx, by = b.Position.OX, b.Position.OY
	return ax < bx + b.Size.OX and bx < ax + a.Size.OX
		and ay < by + b.Size.OY and by < ay + a.Size.OY
end
'''


TESTS = r'''
-- ══ 1. a saved ledger, drawn clean ════════════════════════════════════════
do
	local host = newHost(fullProfile())
	local handle = mount(host)
	expect(#host.Scrolls, 1, "the page registers exactly one scroll")
	expect(host.Scrolls[1], "Records|Records", "by page and name")
	expect(#host.Cards, 1, "the page registers exactly ONE card action")
	local view = host.Cards[1]
	expect(view.Page, "Records", "under the Records page")
	expect(view.Key, "View", "keyed View")
	expect(view.Action.Name, "ViewToggle", "and it is the view toggle")
	expect(view.Card.Name, "RecordsHeader", "carried by the header card")
	local all = buttons(host)
	expect(#all, 1, "the toggle is the only control the page builds")
	expect(all[1], view.Action, "and it is the tagged one")

	expect(host:find("HeaderTitle").Text, "RECORDS", "the header says RECORDS")
	local note = host:find("HeaderNote").Text
	for _, word in ipairs({"Personal bests", "CLEAN", "re-entry", "consumables",
		"EQUIPPED", "paid upgrade", "tokens once"}) do
		check(string.find(note, word, 1, true) ~= nil, "the note explains: " .. word)
	end
	expect(view.Action.Text, "SHOW ASSISTED", "clean is the default view")
	expect(view.Action.Active, true, "and the toggle is reachable")
	expect(host:find("ModeReadout").Text, "CLEAN RUNS", "the header names the view")

	local levels = 0
	for _, child in ipairs(host.Page.Children[1].Children) do
		if string.match(tostring(child.Name), "^Level%d$") then levels += 1 end
	end
	expect(levels, 3, "one card per level")
	for level = 1, 3 do
		expect(partOf(host, level, "LevelTitle").Text, "LEVEL " .. level, "card " .. level .. " is titled")
		expect(partOf(host, level, "SoloCaption").Text, "SOLO", "card " .. level .. " SOLO row")
		expect(partOf(host, level, "PartyCaption").Text, "PARTY", "card " .. level .. " PARTY row")
		expect(partOf(host, level, "NoDeathName").Text, "NO DEATHS", "card " .. level .. " NO DEATHS line")
	end

	-- times, m:ss via FormatTime, and a dash where nothing is recorded
	expect(partOf(host, 1, "SoloTime").Text, "4:32", "272.4 s reads 4:32")
	expect(partOf(host, 1, "PartyTime").Text, "6:41", "401 s reads 6:41")
	for _, cell in ipairs({{2, "SoloTime"}, {2, "PartyTime"}, {3, "SoloTime"}, {3, "PartyTime"}}) do
		expect(partOf(host, cell[1], cell[2]).Text, DASH,
			"Level " .. cell[1] .. " " .. cell[2] .. " has no clean record: a dash")
	end
	-- EQUIPPED only beside the equipped record
	expect(partOf(host, 1, "PartyEquipped").Visible, true, "the equipped party time is tagged")
	expect(partOf(host, 1, "PartyEquipped").Text, "EQUIPPED", "in those words")
	expect(partOf(host, 1, "SoloEquipped").Visible, false, "an unequipped time is not")
	for level = 2, 3 do
		expect(partOf(host, level, "SoloEquipped").Visible, false, "no record, no tag (solo " .. level .. ")")
		expect(partOf(host, level, "PartyEquipped").Visible, false, "no record, no tag (party " .. level .. ")")
	end

	-- challenges: DONE, or the reward still on offer
	expect(partOf(host, 1, "TimeGoalName").Text, "UNDER 8:00", "Level 1's goal from the config")
	expect(partOf(host, 2, "TimeGoalName").Text, "UNDER 10:00", "Level 2's goal")
	expect(partOf(host, 3, "TimeGoalName").Text, "UNDER 10:00", "Level 3's goal")
	expect(partOf(host, 1, "NoDeathState").Text, CHECK .. " DONE", "Level 1 NO DEATHS is done")
	expect(partOf(host, 1, "TimeGoalState").Text, "+3 TOKENS", "Level 1's time goal still pays 3")
	expect(partOf(host, 2, "NoDeathState").Text, "+3 TOKENS", "Level 2 NO DEATHS still pays 3")
	expect(partOf(host, 2, "TimeGoalState").Text, CHECK .. " DONE", "Level 2's time goal is done")
	expect(partOf(host, 3, "NoDeathState").Text, "+3 TOKENS", "Level 3 NO DEATHS pays 3")
	expect(partOf(host, 3, "TimeGoalState").Text, "+3 TOKENS", "Level 3's time goal pays 3")
	check(partOf(host, 1, "NoDeathState").TextColor3 ~= partOf(host, 1, "TimeGoalState").TextColor3,
		"DONE and a reward are drawn in different colours")
	expect(#host.Actions, 0, "drawing the page sends nothing")
	handle.destroy()
end

-- ══ 2. the toggle: client-only, clean <-> assisted ════════════════════════
do
	local host = newHost(fullProfile())
	local handle = mount(host)
	local toggle = host:find("ViewToggle")
	toggle.Activated:Fire()
	expect(toggle.Text, "SHOW CLEAN", "the toggle offers the way back")
	expect(toggle.Active, true, "and stays reachable")
	expect(host:find("ModeReadout").Text, "ASSISTED RUNS", "the header names the assisted view")
	expect(partOf(host, 2, "SoloTime").Text, "10:00", "599.9 s rounds to 10:00")
	expect(partOf(host, 2, "SoloEquipped").Visible, true, "an equipped assisted record is tagged")
	expect(partOf(host, 3, "PartyTime").Text, "1:01", "61 s reads 1:01")
	expect(partOf(host, 3, "PartyEquipped").Visible, false, "an unequipped one is not")
	expect(partOf(host, 1, "SoloTime").Text, DASH, "Level 1 has no assisted solo record")
	expect(partOf(host, 1, "PartyTime").Text, DASH, "nor an assisted party one")
	expect(partOf(host, 1, "PartyEquipped").Visible, false,
		"and the CLEAN record's tag does not leak into the assisted view")
	-- challenges are a property of the level, not of the view
	expect(partOf(host, 1, "NoDeathState").Text, CHECK .. " DONE", "the challenge lines do not change")
	expect(partOf(host, 2, "TimeGoalState").Text, CHECK .. " DONE", "on either card")

	-- a push keeps the player's choice of view
	local pushed = fullProfile()
	pushed.Records["1:solo:assisted"] = {Best = 700, Equipped = false, At = 9}
	host:push(pushed)
	expect(toggle.Text, "SHOW CLEAN", "a profile push keeps the assisted view")
	expect(partOf(host, 1, "SoloTime").Text, "11:40", "and draws the pushed record in it")

	toggle.Activated:Fire()
	expect(toggle.Text, "SHOW ASSISTED", "a second press goes back to clean")
	expect(partOf(host, 1, "SoloTime").Text, "4:32", "with the clean times back")
	expect(partOf(host, 1, "PartyEquipped").Visible, true, "and the clean tag back")
	expect(#host.Actions, 0, "the toggle never sends anything to the server")
	handle.destroy()
end

-- ══ 3. refresh() re-reads, pushes re-render, new records land ═════════════
do
	local host = newHost(fullProfile())
	local handle = mount(host)
	local fresh = fullProfile()
	fresh.Records["3:solo:clean"] = {Best = 455.5, Equipped = true, At = 5}
	fresh.Challenges.NoDeath["3"] = true
	host.Profile = fresh
	expect(partOf(host, 3, "SoloTime").Text, DASH, "nothing moves until the page is told")
	handle.refresh()
	expect(partOf(host, 3, "SoloTime").Text, "7:36", "refresh() re-reads the profile (455.5 s)")
	expect(partOf(host, 3, "SoloEquipped").Visible, true, "with its tag")
	expect(partOf(host, 3, "NoDeathState").Text, CHECK .. " DONE", "and the new challenge flag")
	host:push(fullProfile())
	expect(partOf(host, 3, "SoloTime").Text, DASH, "an onProfile push re-renders too")
	handle.destroy()
end

-- ══ 4. an older server: no Records, no Challenges, or junk ════════════════
for _, case in ipairs({
	{"a profile with neither field", {Tokens = 4}},
	{"no profile loaded yet", nil},
	{"fields of the wrong type", {Records = "corrupt", Challenges = 7}},
	{"Challenges with the wrong inner types", {Records = {}, Challenges = {NoDeath = true, TimeGoal = "x"}}},
}) do
	local host = newHost(case[2])
	local ok, handle = pcall(mount, host)
	check(ok, case[1] .. ": mounts without error (" .. tostring(handle) .. ")")
	for level = 1, 3 do
		expect(partOf(host, level, "SoloTime").Text, DASH, case[1] .. ": Level " .. level .. " solo is a dash")
		expect(partOf(host, level, "PartyTime").Text, DASH, case[1] .. ": Level " .. level .. " party is a dash")
		expect(partOf(host, level, "SoloEquipped").Visible, false, case[1] .. ": no tag")
		expect(partOf(host, level, "NoDeathState").Text, "+3 TOKENS", case[1] .. ": NO DEATHS on offer")
		expect(partOf(host, level, "TimeGoalState").Text, "+3 TOKENS", case[1] .. ": the time goal on offer")
	end
	host:find("ViewToggle").Activated:Fire()
	expect(partOf(host, 1, "SoloTime").Text, DASH, case[1] .. ": the assisted view is empty too")
	handle.destroy()
end

-- ══ 5. fit: four terminal tiers, and the narrowest panel ══════════════════
local FITS = {
	{Name = "phone portrait 390x844", Fit = PHONE_PORTRAIT, Split = false},
	{Name = "phone landscape 844x390", Fit = PHONE_LANDSCAPE, Split = true},
	{Name = "tablet 1024x768", Fit = TABLET, Split = true},
	{Name = "pointer 1280x720", Fit = POINTER, Split = true},
	{Name = "terminal floor 260 wide", Fit = FLOOR, Split = false, Stacked = true},
}
for _, entry in ipairs(FITS) do
	for _, assisted in ipairs({false, true}) do
		local fit = entry.Fit
		local name = entry.Name .. (assisted and " (assisted)" or " (clean)")
		local profile = fullProfile()
		-- the widest time the ledger can hold, with its tag, on every tier
		profile.Records["3:solo:clean"] = {Best = 86399, Equipped = true, At = 6}
		profile.Records["3:solo:assisted"] = {Best = 86399, Equipped = true, At = 6}
		local host = newHost(profile)
		local handle = mount(host, fit)
		if assisted then host:find("ViewToggle").Activated:Fire() end
		host:layout(fit)
		local scroll = host.Page.Children[1]
		expect(#host.Page.Children, 1, name .. ": the page draws one root in its frame")

		-- the rows UIRegression counts: header + three levels, stacked, contained
		local rows = {}
		for _, child in ipairs(scroll.Children) do
			if child.Visible and child.Size then table.insert(rows, child) end
		end
		expect(#rows, 4, name .. ": four visible rows (header + three levels), as PAGE_CONTENT expects")
		local previousBottom = -1
		for _, row in ipairs(rows) do
			check(row.Position.OX >= 0 and row.Position.OX + row.Size.OX <= fit.ContentWidth - 8,
				name .. ": " .. row.Name .. " stays clear of the scrollbar inside "
				.. tostring(fit.ContentWidth))
			check(row.Size.OX > 0 and row.Size.OY > 0, name .. ": " .. row.Name .. " has a real rectangle")
			check(row.Position.OY > previousBottom, name .. ": " .. row.Name .. " starts below the row before it")
			previousBottom = row.Position.OY + row.Size.OY
		end
		for index = 1, #rows do
			for other = index + 1, #rows do
				check(not overlaps(rows[index], rows[other]),
					name .. ": " .. rows[index].Name .. " does not overlap " .. rows[other].Name)
			end
		end
		check(scroll.CanvasSize.OY >= previousBottom,
			name .. ": the canvas (" .. scroll.CanvasSize.OY .. ") reaches the last card (" .. previousBottom .. ")")

		-- the one control
		local toggle = host:find("ViewToggle")
		check(toggle.Size.OX >= 44 and toggle.Size.OY >= 44, name .. ": the toggle is "
			.. toggle.Size.OX .. "x" .. toggle.Size.OY .. ", the floor is 44x44")
		check(insideParent(toggle), name .. ": the toggle sits inside the header card")
		expect(toggle.Active, true, name .. ": and is reachable")
		local title = host:find("HeaderTitle")
		check(not overlaps(title, toggle), name .. ": the title does not run under the toggle")
		if entry.Stacked then
			expect(toggle.Position.OX, title.Position.OX, name .. ": too narrow to share, the toggle takes its own row")
		end

		-- every label inside its card, and no two visible labels in a card colliding
		local smallest, counted = 999, 0
		for _, node in ipairs(descendants(scroll)) do
			if node.ClassName == "TextLabel" or node.ClassName == "TextButton" then
				counted += 1
				smallest = math.min(smallest, node.TextSize)
				if node.Visible then
					check(node.Size.OX > 0 and node.Size.OY > 0, name .. ": " .. node.Name .. " has a real box")
					check(insideParent(node), name .. ": " .. node.Parent.Name .. "." .. node.Name
						.. " at " .. node.Position.OX .. "," .. node.Position.OY .. " size "
						.. node.Size.OX .. "x" .. node.Size.OY .. " stays inside its "
						.. node.Parent.Size.OX .. "x" .. node.Parent.Size.OY .. " parent")
				end
			end
		end
		check(counted >= 30, name .. ": the page draws its full set of copy (" .. counted .. ")")
		check(smallest >= 11, name .. ": the smallest face is " .. smallest .. "px")
		for _, row in ipairs(rows) do
			local shown = {}
			for _, node in ipairs(row.Children) do
				if (node.ClassName == "TextLabel" or node.ClassName == "TextButton") and node.Visible then
					table.insert(shown, node)
				end
			end
			for index = 1, #shown do
				for other = index + 1, #shown do
					check(not overlaps(shown[index], shown[other]), name .. ": " .. row.Name .. "."
						.. shown[index].Name .. " does not overlap " .. shown[other].Name)
				end
			end
		end

		-- times | challenges side by side only where the card is wide enough
		local soloTime = partOf(host, 1, "SoloTime")
		local noDeath = partOf(host, 1, "NoDeathName")
		if entry.Split then
			expect(noDeath.Position.OY, soloTime.Position.OY, name .. ": challenges sit beside the times")
		else
			check(noDeath.Position.OY >= soloTime.Position.OY + soloTime.Size.OY,
				name .. ": challenges stack under the times")
		end
		-- the EQUIPPED tag sits right after its time on the same row -- or, on a
		-- panel too narrow for both, directly under it
		local time3 = partOf(host, 3, "SoloTime")
		local tag3 = partOf(host, 3, "SoloEquipped")
		expect(time3.Text, "1439:59", name .. ": the widest time the ledger allows")
		expect(tag3.Visible, true, name .. ": still tagged")
		if entry.Stacked then
			expect(tag3.Position.OX, time3.Position.OX, name .. ": the tag drops under its time")
			check(tag3.Position.OY >= time3.Position.OY + time3.Size.OY,
				name .. ": below the time's box")
		else
			check(tag3.Position.OX >= time3.Position.OX + time3.Size.OX,
				name .. ": the tag starts after its time's box")
			check(tag3.Position.OY >= time3.Position.OY
				and tag3.Position.OY + tag3.Size.OY <= time3.Position.OY + time3.Size.OY,
				name .. ": on the same row as it")
		end
		handle.destroy()
	end
end

-- ══ 6. destroy() and a host missing its optional pieces ═══════════════════
do
	local host = newHost(fullProfile())
	local handle = mount(host)
	local scroll = host.Page.Children[1]
	local toggle = host:find("ViewToggle")
	handle.destroy()
	expect(scroll.Destroyed, true, "destroy() takes its own tree down")
	expect(#host.Page.Children, 0, "leaving the terminal's page frame empty")
	expect(host.Disconnects, 1, "and drops the profile subscription")
	local ok = pcall(function()
		toggle.Activated:Fire()
		handle.refresh()
		host:push(fullProfile())
	end)
	check(ok, "a press, a refresh or a push after destroy is a harmless no-op")
end

do
	local host = newHost(fullProfile())
	host.ctx.contract = nil
	host.ctx.onProfile = nil
	host.ctx.registerLayoutHook = nil
	local ok, err = pcall(function() return Page.mount(host.Page, host.ctx) end)
	check(ok, "mounting without the optional ctx members does not error: " .. tostring(err))
	expect(host:find("SoloTime").Text, "4:32", "and the page still draws the ledger")
end

do
	-- A config without the block is not a shipped state, but it must not take
	-- the terminal's mount down with it.
	local host = newHost(fullProfile())
	local bare = table.clone(Config)
	bare.Challenges = nil
	host.ctx.Config = bare
	local ok, handle = pcall(mount, host)
	check(ok, "a config without Challenges still mounts: " .. tostring(handle))
	expect(partOf(host, 1, "SoloTime").Text, "4:32", "and draws the records it can key")
	expect(partOf(host, 1, "TimeGoalName").Visible, false, "with no goal configured, no goal line")
end

print("Records page: " .. tostring(checks)
	.. " checks passed (offline Luau, real ZyntraChallenges + ZyntraConfig; font metrics,"
	.. " TextBounds, real UIDevice and rendering not exercised)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    source = "\n".join([
        PRELUDE,
        LEDGER_WIRING,
        "local UIStyle = (function()", UISTYLE, "end)()",
        "local RealConfig = (function()", CONFIG, "end)()",
        section(STORE, "local COLORS = {", 'local gui = Instance.new("ScreenGui")'),
        section(STORE, "local function corner(parent, radius)", "-- Imagegen section art"),
        "Ledger = (function()", LEDGER, "end)()",
        "local Page = (function()", PAGE, "end)()",
        HARNESS,
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="zyntra-records-page-") as directory:
        fixture = Path(directory) / "zyntra_records_page.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=120)


if __name__ == "__main__":
    main()
