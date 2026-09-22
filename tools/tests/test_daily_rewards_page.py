"""Run the real ZyntraDailyRewardsPage under offline Luau with an honest fake Roblox.

DAILY_REWARDS_PAGE_20260916 (Trello #83/#84/#89, wheel removed by #104). The
module under test is the whole shipped file -- not a retyped copy -- mounted
through the page contract in `artifacts/trello-20260916/claude-contracts.md`,
with:

  * the REAL ReplicatedStorage/UIStyle module, loaded and run;
  * the REAL ZyntraStore COLORS table and its corner/outline/label/button
    helpers, extracted from the LocalScript by string marker;
  * the REAL ReplicatedStorage/ZyntraConfig, so once A-SERVER lands
    `DailyRewards` this file becomes a CONTRACT test between the two sides: the
    milestones are asserted against the numbers the owner approved
    (5/15/35) whichever source supplies them. Until that lands, the
    contract's own table stands in and the run says so.

WHAT #104 CHANGED. The supply wheel moved out of this page into its own modal
(`Lucky Wheel Client`, Trello #103), so every assertion about spinning, replaying
a recorded prize, the odds rows and the SKIP control went with it -- those are
the wheel client's tests now. What is left is asserted harder: this file also
proves the wheel is GONE, because a page that still built a hidden SpinButton
would put a second `SpinDailyWheel` path back into the game.

WHAT THE 2026-09-16 REBUILD CHANGED. Only the drawing, and this file is the
proof of exactly that: the three milestones, the request shape, the one-in-
flight guard, the 6 s re-read and the UTC day guard are asserted here unchanged,
while the CARD is asserted against the new contract -- Codex's uploaded art per
reward, a gradient per card, a 45%-of-the-card icon, a CLAIM at 44px, and a
claimed state that HIDES the button behind a tick. The header (gift, title, X)
is the host's and is asserted in test_daily_rewards_client.py; this file proves
the page draws none of it, because two copies would lay out separately.

What it proves, by running the code rather than matching strings: the claim
states drawn for a given saved profile, the UTC day-roll guard, the local
countdown after real elapsed time, that one press fires exactly one action and
then locks, that a request nobody answers recovers by RE-READING instead of
granting, that nothing the page builds can send `SpinDailyWheel`, that no copy
still names the retired supply fiction, and that every rectangle at four
viewport tiers lands inside the host's own content box at or above the 44px
touch floor -- as one row of three cards everywhere except a phone held upright.

What it CANNOT see: real font metrics and TextBounds, the engine's UICorner /
UIStroke rendering, UIDevice's real form-factor detection, and anything about
how it looks. Studio captures on a phone, a tablet and a desktop are the proof
for those. Set LUAU_BIN or put luau on PATH.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PAGE = (ROOT / "ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua"
        ).read_text(encoding="utf-8")
UISTYLE = (ROOT / "ReplicatedStorage/UIStyle.ModuleScript.lua").read_text(encoding="utf-8")
CONFIG = (ROOT / "ReplicatedStorage/ZyntraConfig.ModuleScript.lua").read_text(encoding="utf-8")
RESEARCH = (ROOT / "ReplicatedStorage/ZyntraDailyResearch.ModuleScript.lua").read_text(encoding="utf-8")
STORE = (ROOT / "StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua"
         ).read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


PRELUDE = r'''
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, "FAILED: " .. message)
end
local function expect(value, wanted, message)
	checks += 1
	assert(value == wanted, "FAILED: " .. message .. " -- expected "
		.. tostring(wanted) .. ", got " .. tostring(value))
end

-- ── value types ──────────────────────────────────────────────────────────
-- Memoised, so `==` answers "same value" the way the engine's own types do.
local function memo(kind, build)
	local cache = {}
	return function(...)
		local key = kind .. ":" .. table.concat({...}, ",")
		if not cache[key] then cache[key] = build(key, ...) end
		return cache[key]
	end
end

-- Roblox Color3 has NO arithmetic. A fake that quietly allowed `a + b` would
-- pass code the engine throws on, which is exactly the fault that shipped from
-- a Codex proposal on 2026-09-14.
local colorMeta = {
	__add = function() error("Color3 has no arithmetic", 2) end,
	__sub = function() error("Color3 has no arithmetic", 2) end,
	__mul = function() error("Color3 has no arithmetic", 2) end,
	__div = function() error("Color3 has no arithmetic", 2) end,
	__tostring = function(self) return self.Key end,
}
local Color3 = {
	fromRGB = memo("Color3", function(key, r, g, b)
		return setmetatable({Kind = "Color3", Key = key, R = r, G = g, B = b}, colorMeta)
	end),
	new = memo("Color3n", function(key, r, g, b)
		return setmetatable({Kind = "Color3", Key = key, R = r, G = g, B = b}, colorMeta)
	end),
}
local UDim = {new = memo("UDim", function(key, scale, offset)
	return {Kind = "UDim", Key = key, Scale = scale, Offset = offset}
end)}
-- UDim2 DOES have arithmetic in Roblox, so the fake keeps it.
local udim2Meta = {}
local function makeUDim2(sx, ox, sy, oy)
	return setmetatable({Kind = "UDim2", SX = sx, OX = ox, SY = sy, OY = oy}, udim2Meta)
end
udim2Meta.__add = function(a, b) return makeUDim2(a.SX + b.SX, a.OX + b.OX, a.SY + b.SY, a.OY + b.OY) end
udim2Meta.__sub = function(a, b) return makeUDim2(a.SX - b.SX, a.OX - b.OX, a.SY - b.SY, a.OY - b.OY) end
local UDim2 = {
	new = function(sx, ox, sy, oy) return makeUDim2(sx or 0, ox or 0, sy or 0, oy or 0) end,
	fromOffset = function(x, y) return makeUDim2(0, x or 0, 0, y or 0) end,
	fromScale = function(x, y) return makeUDim2(x or 0, 0, y or 0, 0) end,
}
local vector2Meta = {}
local function makeVector2(x, y) return setmetatable({Kind = "Vector2", X = x, Y = y}, vector2Meta) end
vector2Meta.__add = function(a, b) return makeVector2(a.X + b.X, a.Y + b.Y) end
vector2Meta.__sub = function(a, b) return makeVector2(a.X - b.X, a.Y - b.Y) end
local Vector2 = {new = makeVector2}
local ColorSequenceKeypoint = {new = function(t, c) return {T = t, C = c} end}
local ColorSequence = {new = function(v) return {Kind = "ColorSequence", Value = v} end}
local Enum = setmetatable({}, {__index = function(_, group)
	return setmetatable({}, {__index = function(_, item) return group .. "." .. item end})
end})

-- ── signals ──────────────────────────────────────────────────────────────
local function signal()
	local listeners = {}
	local this = {}
	function this:Connect(fn)
		table.insert(listeners, fn)
		local connection = {Connected = true}
		function connection:Disconnect()
			connection.Connected = false
			for index, stored in ipairs(listeners) do
				if stored == fn then table.remove(listeners, index) break end
			end
		end
		return connection
	end
	function this:Fire(...)
		for _, fn in ipairs(table.clone(listeners)) do fn(...) end
	end
	function this:Count() return #listeners end
	return this
end

-- ── instances ────────────────────────────────────────────────────────────
local instanceCount = 0
local function newInstance(class)
	instanceCount += 1
	local fields = {
		ClassName = class, Name = class, Children = {}, Attributes = {},
		-- Roblox's own defaults for the properties this page reads back.
		Visible = true, Text = "", TextScaled = false, Destroyed = false,
		Active = class == "TextButton" or class == "ImageButton",
	}
	-- An ImageLabel that does not carry these is a fake that would pass a page
	-- which never set Image or left ScaleType at Stretch.
	if class == "ImageLabel" or class == "ImageButton" then
		fields.Image = ""
		fields.ScaleType = Enum.ScaleType.Stretch
		fields.ImageColor3 = Color3.new(1, 1, 1)
		fields.IsLoaded = false
	end
	local proxy
	fields.MouseEnter, fields.MouseLeave, fields.Activated = signal(), signal(), signal()
	fields.FindFirstChildOfClass = function(_, want)
		for _, child in ipairs(fields.Children) do
			if child.ClassName == want then return child end
		end
		return nil
	end
	fields.FindFirstChild = function(_, want)
		for _, child in ipairs(fields.Children) do
			if child.Name == want then return child end
		end
		return nil
	end
	fields.GetChildren = function() return table.clone(fields.Children) end
	fields.IsA = function(_, want)
		return want == class
			or (want == "GuiObject" and class ~= "Player")
			or (want == "GuiButton" and (class == "TextButton" or class == "ImageButton"))
	end
	fields.GetAttribute = function(_, key) return fields.Attributes[key] end
	fields.SetAttribute = function(_, key, value) fields.Attributes[key] = value end
	local function unparent()
		local parent = fields.Parent
		if not parent then return end
		for index, child in ipairs(parent.Children) do
			if child == proxy then table.remove(parent.Children, index) break end
		end
	end
	fields.Destroy = function()
		unparent()
		fields.Destroyed = true
		fields.Parent = nil
		for _, child in ipairs(table.clone(fields.Children)) do child:Destroy() end
	end
	proxy = setmetatable({}, {
		__index = fields,
		__newindex = function(_, key, value)
			if key == "Parent" then
				unparent()
				if value ~= nil then table.insert(value.Children, proxy) end
			end
			fields[key] = value
		end,
	})
	return proxy
end
local Instance = {new = newInstance}

local function findByName(root, name)
	for _, child in ipairs(root.Children) do
		if child.Name == name then return child end
		local deeper = findByName(child, name)
		if deeper then return deeper end
	end
	return nil
end
local function mustFind(root, name)
	local found = findByName(root, name)
	assert(found, "no instance named " .. name)
	return found
end
-- Where a node actually sits inside `root`, by walking the parents the way the
-- engine resolves an absolute position. Guessing a card's section (as a first
-- pass here did) double-counts the offset for a card that IS its section.
local function offsetWithin(node, root)
	local x, y = 0, 0
	local current = node
	while current and current ~= root do
		if current.Position then
			x += current.Position.OX
			y += current.Position.OY
		end
		current = current.Parent
	end
	return x, y
end

local function descendants(root, into)
	into = into or {}
	for _, child in ipairs(root.Children) do
		table.insert(into, child)
		descendants(child, into)
	end
	return into
end

-- ── clock, scheduler, services ───────────────────────────────────────────
local clock = {Now = 1000, Queue = {}}
local heartbeat = signal()
local tweensCreated = 0
local task = {}
function task.delay(seconds, fn)
	table.insert(clock.Queue, {At = clock.Now + (seconds or 0), Fn = fn})
end
function task.spawn(fn, ...) fn(...) end
function task.defer(fn, ...) fn(...) end
function task.wait(seconds) return seconds or 0 end

local workspace = newInstance("Workspace")
workspace.GetServerTimeNow = function() return clock.Now end

local services = {
	RunService = {Heartbeat = heartbeat, RenderStepped = signal(),
		IsStudio = function() return true end},
	-- Present so an unexpected tween is COUNTED rather than erroring: the
	-- reduced-flashing contract is "no stepping", and the count is the proof
	-- that neither path leaves a tween running behind the page.
	TweenService = {Create = function()
		tweensCreated += 1
		return {Play = function() end, Cancel = function() end, Completed = signal()}
	end},
	Players = {LocalPlayer = false},
}
local game = {GetService = function(_, name)
	return assert(services[name], "unfaked service " .. name)
end}
-- The page requires the REAL daily research ledger off ReplicatedStorage.
game.ReplicatedStorage = {WaitForChild = function(_, name) return name end}
local Research -- assigned once the real module source below has run
local function require(name)
	if name == "ZyntraDailyResearch" then return Research end
	error("unfaked module " .. tostring(name))
end

-- Advance real time in small steps, running due task.delay callbacks and
-- firing Heartbeat exactly as the engine would.
local function advance(total, step, sample)
	step = step or 1 / 60
	local remaining = total
	local guard = 0
	while remaining > 1e-9 do
		local delta = math.min(step, remaining)
		clock.Now += delta
		remaining -= delta
		guard += 1
		assert(guard < 200000, "scheduler runaway")
		local ran = true
		while ran do
			ran = false
			for index, item in ipairs(clock.Queue) do
				if item.At <= clock.Now then
					table.remove(clock.Queue, index)
					item.Fn()
					ran = true
					break
				end
			end
		end
		heartbeat:Fire(delta)
		if sample then sample() end
	end
end
'''


HARNESS = r'''
-- ── the contract's own reward table ──────────────────────────────────────
-- Used only while ZyntraConfig does not carry DailyRewards yet. The assertions
-- below hold the NUMBERS either way, so if A-SERVER lands different ones this
-- file fails and names them.
local FALLBACK_DAILY = {
	AfkGraceSeconds = 90, ActivityMinimumStuds = 1, FlushIntervalSeconds = 60,
	Milestones = {
		{Minutes = 5, Reward = {Kind = "Tokens", Amount = 1}},
		{Minutes = 15, Reward = {Kind = "Item", Key = "SpeedPotion", Amount = 1}},
		{Minutes = 35, Reward = {Kind = "Item", Key = "EntityShield", Amount = 1}},
	},
	Wheel = {
		{Key = "Token1", Weight = 45, Label = "1 Research Token",
			Reward = {Kind = "Tokens", Amount = 1}},
		{Key = "Token3", Weight = 20, Label = "3 Research Tokens",
			Reward = {Kind = "Tokens", Amount = 3}},
		{Key = "Potion1", Weight = 20, Label = "1 Speed Potion",
			Reward = {Kind = "Item", Key = "SpeedPotion", Amount = 1}},
		{Key = "Potion2", Weight = 5, Label = "2 Speed Potions",
			Reward = {Kind = "Item", Key = "SpeedPotion", Amount = 2}},
		{Key = "Shield1", Weight = 10, Label = "1 Entity Shield",
			Reward = {Kind = "Item", Key = "EntityShield", Amount = 1}},
	},
}
local FALLBACK_ITEMS = {
	SpeedPotion = {Name = "Speed Potion", TokenCost = 3, DurationSeconds = 6,
		SpeedMultiplier = 1.10, MaxUsesPerRound = 1},
	RouteMarker = {Name = "Route Marker Pack", TokenCost = 2, PackSize = 3, MaxActive = 3},
}

local Config, configSource = RealConfig, "ZyntraConfig"
if type(Config.DailyRewards) ~= "table" then
	Config = table.clone(RealConfig)
	Config.DailyRewards = FALLBACK_DAILY
	Config.Items = Config.Items or FALLBACK_ITEMS
	configSource = "contract fallback (ZyntraConfig has no DailyRewards yet)"
end

local TODAY, YESTERDAY = "2026-09-16", "2026-09-15"
local RESET_SECONDS = 18753 -- 05:12:33

local function profileOf(overrides)
	local daily = {Day = TODAY, Today = TODAY, PlaytimeSeconds = 0, Claimed = {},
		SecondsToReset = RESET_SECONDS, Accruing = false}
	for key, value in pairs(overrides or {}) do daily[key] = value end
	return {Daily = daily, Tokens = 12, Items = {SpeedPotion = 0, RouteMarker = 0}}
end

-- ── a terminal that keeps the page's contract and records what it is told ──
local function newHost()
	local host = {Actions = {}, Status = {}, Refreshes = 0, Cards = {}, Scrolls = {},
		Hooks = {}, Visible = true, Listeners = {}, Disconnects = 0}
	host.Page = newInstance("Frame")
	host.Page.Name = "Rewards"
	host.Player = newInstance("Player")
	host.Profile = profileOf()
	host.ctx = {
		player = host.Player,
		Config = Config,
		UIStyle = UIStyle,
		-- The real UIDevice reaches for UserInputService, GuiService and a live
		-- viewport; what this page uses of it is SetEnabled, and SetEnabled's
		-- observable effect on a TextButton is Active.
		UIDevice = {
			SetEnabled = function(element, enabled) element.Active = enabled end,
			SetInteractive = function(element, shown)
				element.Visible = shown
				element.Active = shown
			end,
			SuppressesKeyboardGlyphs = function() return true end,
		},
		COLORS = COLORS,
		label = label, button = button, corner = corner, outline = outline,
		pageName = "Rewards",
		action = function(name, payload)
			table.insert(host.Actions, {Name = name, Payload = payload})
		end,
		profile = function() return host.Profile end,
		onProfile = function(fn)
			table.insert(host.Listeners, fn)
			return function() host.Disconnects += 1 end
		end,
		refreshProfile = function() host.Refreshes += 1 end,
		showStatus = function(message, tone)
			table.insert(host.Status, {Message = message, Tone = tone})
		end,
		registerLayoutHook = function(fn) table.insert(host.Hooks, fn) end,
		isVisible = function() return host.Visible end,
		contract = {
			scroll = function(page, frame)
				table.insert(host.Scrolls, page .. "|" .. frame.Name)
			end,
			card = function(page, key, card, action)
				table.insert(host.Cards, {Page = page, Key = key, Card = card, Action = action})
			end,
		},
	}
	function host:push(overrides)
		self.Profile = profileOf(overrides)
		for _, fn in ipairs(self.Listeners) do fn(self.Profile, nil, nil) end
	end
	function host:layout(fit)
		for _, fn in ipairs(self.Hooks) do fn(fit) end
	end
	function host:find(name) return mustFind(self.Page, name) end
	return host
end

-- The fit table the Daily Rewards Client publishes, rebuilt from the SAME
-- figures its applyLayout uses (720x640 design, 260 floor, compact under
-- 640x430, 12/20 padding, 44 tap, a 56/64 header bar plus its 8px margin, and
-- a 22/30 status line). ContentHeight matters now: the card's icon is sized
-- against the height the host actually handed the page.
--
-- The arguments are MODAL VIEWPORT sizes, not display sizes -- that is what the
-- client clamps against, and the difference is the safe-area inset.
local function fitFor(viewportWidth, viewportHeight, touch)
	local width = math.floor(math.clamp(math.min(720, viewportWidth), 260, 720))
	local height = math.floor(math.min(640, viewportHeight))
	local compact = width < 640 or height < 430
	local tap = touch and 44 or 32
	local pad = compact and 12 or 20
	local gap = compact and 8 or 12
	local statusHeight = compact and 22 or 30
	local headerHeight = math.max(math.max(48, tap) + 8, compact and 56 or 64) + 8
	return {Width = width, Height = height, ContentWidth = width - pad * 2,
		ContentHeight = height - headerHeight - gap - statusHeight - gap,
		Compact = compact, Touch = touch,
		Tap = tap, TabHeight = math.max(tap, compact and 40 or 42),
		TabMinWidth = compact and 88 or 110}
end
-- 390x844 phone, 844x390 phone, 1024x768 tablet and 1280x720 desktop, each
-- already reduced to the modal viewport UIDevice would hand the shell. The
-- landscape row is the one that was MEASURED rather than derived: Studio at
-- 844x390 with the UIDevice overrides gives a 720x316 panel and a 696x214
-- content box, which is 22px tighter than this file first assumed.
local PHONE_PORTRAIT = fitFor(358, 774, true)
local PHONE_LANDSCAPE = fitFor(812, 316, true)
local TABLET = fitFor(992, 716, true)
local POINTER = fitFor(1248, 668, false)

local function mount(host, fit)
	local handle = Page.mount(host.Page, host.ctx)
	host:layout(fit or POINTER)
	return handle
end

local function buttonFor(host, key)
	for _, entry in ipairs(host.Cards) do
		if entry.Key == key then return entry.Action, entry.Card end
	end
	return nil, nil
end

-- The wheel is not this page's any more, and "not drawn" is not the same fact
-- as "not built": a hidden SpinButton would still be wired to the action. This
-- walks the WHOLE tree the page built, so nothing survives by being invisible.
local function wheelRemnant(host)
	for _, node in ipairs(descendants(host.Page)) do
		local name = tostring(node.Name)
		if name == "SpinButton" or name == "SkipButton" or name == "WheelSection"
			or name == "ResultBanner" or name == "NextSpinNote" or name == "OddsNote"
			or string.match(name, "^Segment%d+$") then
			return name
		end
	end
	return nil
end

-- The two glyphs the page draws that are not ASCII, written as escapes on both
-- sides so the comparison cannot turn into a test of this file's encoding.
local RESET_TAIL = "  \u{00B7}  00:00 UTC"
local CHECK_MARK = "\u{2713}"

-- Codex's uploaded art, by milestone. Asserted here rather than read out of the
-- module: a test that took the id from the code under test would pass whatever
-- the code happened to hold.
local ICON_ID = {
	[5] = "rbxassetid://93116899475472",
	[15] = "rbxassetid://120211340805188",
	[35] = "rbxassetid://126728249949579",
}
local CARD_TOP_COLOR = {
	[5] = Color3.fromRGB(255, 205, 60),
	[15] = Color3.fromRGB(80, 220, 255),
	[35] = Color3.fromRGB(150, 90, 230),
}
local CARD_BOTTOM_COLOR = {
	[5] = Color3.fromRGB(255, 150, 30),
	[15] = Color3.fromRGB(40, 120, 220),
	[35] = Color3.fromRGB(60, 200, 140),
}
local CLAIM_READY = Color3.fromRGB(70, 200, 90)

local function cardOf(host, minutes) return host:find("Milestone" .. tostring(minutes)) end
local function partOf(host, minutes, name)
	return cardOf(host, minutes):FindFirstChild(name)
end

-- Nothing on this page may still name the retired supply fiction. Walks the
-- whole tree, because the eyebrow used to be a label like any other.
local function forbiddenCopy(host)
	for _, node in ipairs(descendants(host.Page)) do
		local text = tostring(node.Text or "")
		if string.find(text, "SUPPLY", 1, true) or string.find(text, "Supply", 1, true)
			or string.find(text, "ZYNTRA", 1, true) then
			return node.Name .. ": " .. text
		end
	end
	return nil
end
'''


TESTS = r'''
-- ══ 1. a fresh day, and the card the owner asked for ══════════════════════
do
	local host = newHost()
	local handle = mount(host)
	expect(#host.Scrolls, 1, "the page registers exactly one scroll")
	expect(host.Scrolls[1], "Rewards|DailyRewards", "the scroll is registered by page and name")
	expect(#host.Cards, 3, "the three milestones are registered as cards")
	local keys = {}
	for _, entry in ipairs(host.Cards) do
		keys[entry.Key] = true
		expect(entry.Page, "Rewards", entry.Key .. " is registered under the Rewards page")
	end
	for _, key in ipairs({"Playtime5", "Playtime15", "Playtime35"}) do
		check(keys[key], key .. " is a registered card")
	end
	check(not keys.Wheel, "and the Wheel is NOT one of them any more")

	-- THE HOST OWNS THE MODAL'S IDENTITY. The gift, the title and the X are the
	-- Daily Rewards Client's header bar; a second copy of any of them here would
	-- be the same thing twice, 40px apart, in two files that lay out separately.
	for _, name in ipairs({"Title", "HeaderTitle", "Eyebrow", "RewardsHeader",
		"HeaderGift", "CloseButton"}) do
		expect(findByName(host.Page, name), nil, "the page draws no " .. name .. " of its own")
	end

	expect(host:find("ResetCountdown").Text, "RESETS IN 05:12:33" .. RESET_TAIL,
		"one strip carries the countdown and the UTC boundary it counts to")
	expect(host:find("PlaytimeReadout").Text, "ACTIVE PLAY TODAY  0:00",
		"a fresh day has no active play")
	expect(host:find("ProgressCaption").Text, "5:00 to the 5 minute reward",
		"the caption names the next milestone")
	expect(host:find("ProgressTrack"):FindFirstChild("Fill").Size.SX, 0,
		"the progress fill is empty at zero seconds")

	-- The card: threshold, the product's own art, the reward, the state.
	for _, minutes in ipairs({5, 15, 35}) do
		expect(partOf(host, minutes, "Threshold").Text, tostring(minutes) .. " MIN",
			minutes .. ": the threshold is stated in minutes")
		local icon = partOf(host, minutes, "RewardIcon")
		check(icon ~= nil and icon.ClassName == "ImageLabel",
			minutes .. ": the reward art is an ImageLabel")
		expect(icon.Image, ICON_ID[minutes], minutes .. ": wearing Codex's uploaded art")
		expect(icon.ScaleType, Enum.ScaleType.Fit,
			minutes .. ": Fit, so the motif is never stretched or cropped")
		expect(icon.BackgroundTransparency, 1, minutes .. ": over the card, not on a plate")
		local ramp = cardOf(host, minutes):FindFirstChildOfClass("UIGradient")
		check(ramp ~= nil, minutes .. ": the card carries a gradient")
		expect(ramp.Color.Value[1].C, CARD_TOP_COLOR[minutes], minutes .. ": from its own colour")
		expect(ramp.Color.Value[2].C, CARD_BOTTOM_COLOR[minutes], minutes .. ": to its own colour")
		-- A UIGradient MULTIPLIES BackgroundColor3. A card left dark underneath
		-- would render the warm ramp as a slightly-less-dark card.
		expect(cardOf(host, minutes).BackgroundColor3, Color3.fromRGB(255, 255, 255),
			minutes .. ": and is white underneath so the ramp reads as authored")
		expect(partOf(host, minutes, "ClaimedCheck").Visible, false,
			minutes .. ": nothing is claimed on a fresh day")
		expect(partOf(host, minutes, "ClaimedLabel").Visible, false,
			minutes .. ": and the word CLAIMED is not drawn either")
	end
	expect(partOf(host, 5, "RewardName").Text, "1 Research Token", "5 minutes pays a token")
	expect(partOf(host, 15, "RewardName").Text, "1 Speed Potion", "15 minutes pays a potion")
	expect(partOf(host, 35, "RewardName").Text, "1 Entity Shield", "35 minutes pays a shield charge")
	expect(partOf(host, 5, "ClaimedCheck"):FindFirstChild("CheckMark").Text, CHECK_MARK,
		"the claimed badge is a tick")

	for _, case in ipairs({{"Playtime5", "5:00 TO GO"}, {"Playtime15", "15:00 TO GO"},
		{"Playtime35", "35:00 TO GO"}}) do
		local action = buttonFor(host, case[1])
		expect(action.Text, case[2], case[1] .. " is locked with its remaining time")
		expect(action.Active, false, case[1] .. " cannot be pressed while locked")
		expect(action.Visible, true, case[1] .. " is still drawn, so the wait is legible")
	end

	expect(wheelRemnant(host), nil, "the page builds no wheel instance at all")
	local wheelNoteLeft = nil
	for _, node in ipairs(descendants(host.Page)) do
		if tostring(node.Name) == "WheelNote" then wheelNoteLeft = node end
	end
	expect(wheelNoteLeft, nil, "the wheel pointer note is gone (owner, 2026-09-17)")
	expect(host:find("PlaytimeNote").Text, "Only time in an active round counts.",
		"the playtime note is one line and no longer excludes spectating")
	expect(forbiddenCopy(host), nil, "nothing on the page still names the supply fiction")
	expect(#host.Actions, 0, "drawing the page sends nothing to the server")
	expect(tweensCreated, 0, "the page creates no tweens at rest")
	handle.destroy()
end

-- ══ 1b. the wheel cannot be reached from here by any path ═════════════════
do
	-- A page that still HELD the wheel, merely hidden, would still be able to
	-- fire SpinDailyWheel from a stale connection -- and a second spin path is
	-- exactly what the split was meant to remove. Fired at every button the page
	-- built, with a profile that has an unspent spin on it.
	local host = newHost()
	local handle = mount(host)
	host:push({WheelDay = nil, WheelLast = nil})
	for _, node in ipairs(descendants(host.Page)) do
		if node.ClassName == "TextButton" then node.Activated:Fire() end
	end
	for _, entry in ipairs(host.Actions) do
		check(entry.Name ~= "SpinDailyWheel",
			"no control on this page sends SpinDailyWheel (sent " .. entry.Name .. ")")
	end
	-- A recorded prize on the profile must not resurrect a banner or a replay.
	host:push({WheelDay = TODAY, WheelLast = {Day = TODAY, Key = "Token3", Serial = 3}})
	expect(wheelRemnant(host), nil, "a recorded prize draws nothing here")
	advance(4)
	expect(wheelRemnant(host), nil, "and nothing appears on a later frame either")
	handle.destroy()
end

-- ══ 3. milestone states come only from the saved profile ══════════════════
do
	local host = newHost()
	local handle = mount(host)

	host:push({PlaytimeSeconds = 299})
	expect(buttonFor(host, "Playtime5").Text, "0:01 TO GO",
		"one second short of five minutes is still locked")
	expect(buttonFor(host, "Playtime5").Active, false, "and cannot be pressed")
	expect(host:find("PlaytimeReadout").Text, "ACTIVE PLAY TODAY  4:59", "4:59 played")

	host:push({PlaytimeSeconds = 300})
	local ready = buttonFor(host, "Playtime5")
	expect(ready.Text, "CLAIM", "five minutes unlocks the claim")
	expect(ready.Active, true, "and it is reachable")
	expect(ready.BackgroundColor3, CLAIM_READY, "a ready CLAIM is the bright green one")
	expect(buttonFor(host, "Playtime15").Text, "10:00 TO GO", "the next one is still locked")
	check(buttonFor(host, "Playtime15").BackgroundColor3 ~= CLAIM_READY,
		"and a locked one is not")
	expect(host:find("ProgressCaption").Text, "10:00 to the 15 minute reward",
		"the caption moves to the next milestone")

	host:push({PlaytimeSeconds = 300, Claimed = {["5"] = true}})
	expect(partOf(host, 5, "ClaimedCheck").Visible, true, "a claimed card shows the tick")
	expect(partOf(host, 5, "ClaimedLabel").Visible, true, "and says CLAIMED in words")
	expect(partOf(host, 5, "ClaimedLabel").Text, "CLAIMED", "in those words")
	expect(buttonFor(host, "Playtime5").Visible, false, "and the button is hidden, not relabelled")
	expect(buttonFor(host, "Playtime5").Active, false, "so it cannot be claimed twice")
	expect(partOf(host, 15, "ClaimedCheck").Visible, false, "the other cards are untouched")

	host:push({PlaytimeSeconds = 2100})
	for _, minutes in ipairs({5, 15, 35}) do
		expect(buttonFor(host, "Playtime" .. minutes).Text, "CLAIM",
			"35 minutes clears the " .. minutes)
		expect(buttonFor(host, "Playtime" .. minutes).Visible, true,
			"and the " .. minutes .. " button is back from the claimed state")
		expect(partOf(host, minutes, "ClaimedCheck").Visible, false,
			"with the " .. minutes .. " tick taken down again")
	end
	expect(host:find("ProgressTrack"):FindFirstChild("Fill").Size.SX, 1,
		"the progress bar is full at the last milestone")
	expect(host:find("ProgressCaption").Text, "Every milestone reached today.",
		"with nothing left, the caption says so")

	host:push({PlaytimeSeconds = 4000, Claimed = {["5"] = true, ["15"] = true, ["35"] = true}})
	for _, minutes in ipairs({5, 15, 35}) do
		expect(partOf(host, minutes, "ClaimedCheck").Visible, true,
			minutes .. " is claimed for the day")
		expect(buttonFor(host, "Playtime" .. minutes).Visible, false,
			minutes .. " has no button left to press")
		expect(buttonFor(host, "Playtime" .. minutes).Active, false,
			minutes .. " is out of the input stack")
	end
	expect(host:find("PlaytimeReadout").Text, "ACTIVE PLAY TODAY  1:06:40",
		"past an hour the readout grows an hours field")

	-- Accruing is a live hint, not state: it only annotates the readout.
	host:push({PlaytimeSeconds = 760, Accruing = true})
	expect(host:find("PlaytimeReadout").Text, "ACTIVE PLAY TODAY  12:40  //  COUNTING",
		"the readout says so while the server is counting")
	handle.destroy()
end

-- ══ 4. the UTC day roll ═══════════════════════════════════════════════════
do
	local host = newHost()
	local handle = mount(host)
	-- The server resets PlaytimeSeconds and Claimed LAZILY inside its own
	-- transform, so between midnight and the next write the fields still
	-- describe yesterday. Reading them as today's would show three claimed
	-- cards one second into the new day.
	host:push({Day = YESTERDAY, PlaytimeSeconds = 3000,
		Claimed = {["5"] = true, ["15"] = true, ["35"] = true},
		WheelDay = YESTERDAY,
		WheelLast = {Day = YESTERDAY, Key = "Token3", Serial = 7}})
	expect(host:find("PlaytimeReadout").Text, "ACTIVE PLAY TODAY  0:00",
		"yesterday's seconds are not today's")
	expect(buttonFor(host, "Playtime5").Text, "5:00 TO GO", "yesterday's claim does not carry over")
	expect(buttonFor(host, "Playtime5").Active, false, "and the fresh card is locked, not pressable")
	expect(partOf(host, 5, "ClaimedCheck").Visible, false, "and yesterday's tick comes down")
	expect(wheelRemnant(host), nil, "and yesterday's recorded prize draws nothing")
	handle.destroy()
end

-- ══ 5. the countdown ticks locally, at 1 Hz, and re-anchors on every push ══
do
	local host = newHost()
	local handle = mount(host)
	expect(host:find("ResetCountdown").Text, "RESETS IN 05:12:33" .. RESET_TAIL,
		"the anchored countdown")
	advance(61)
	expect(host:find("ResetCountdown").Text, "RESETS IN 05:11:32" .. RESET_TAIL,
		"61 seconds of real time takes 61 seconds off the countdown")
	-- Hidden: the ticker stops redrawing. The clock underneath is server time,
	-- so the countdown is correct again the moment the page comes back.
	host.Visible = false
	advance(120)
	expect(host:find("ResetCountdown").Text, "RESETS IN 05:11:32" .. RESET_TAIL,
		"a page nobody is looking at does not redraw")
	host.Visible = true
	advance(1)
	expect(host:find("ResetCountdown").Text, "RESETS IN 05:09:31" .. RESET_TAIL,
		"and it catches up from the clock, not from what it drew last")
	-- A push re-anchors it, which is what keeps it from drifting.
	host:push({SecondsToReset = 65})
	expect(host:find("ResetCountdown").Text, "RESETS IN 00:01:05" .. RESET_TAIL,
		"a push re-anchors the countdown")
	local before = host.Refreshes
	advance(66)
	expect(host:find("ResetCountdown").Text, "RESETS IN 00:00:00" .. RESET_TAIL, "it floors at zero")
	expect(host.Refreshes, before + 1, "reaching the reset RE-READS the profile once")
	advance(10)
	expect(host.Refreshes, before + 1, "and asks exactly once, not once a second")
	handle.destroy()
end

-- ══ 6. claiming: one press, one action, then locked ═══════════════════════
do
	local host = newHost()
	local handle = mount(host)
	host:push({PlaytimeSeconds = 400})
	local claim = buttonFor(host, "Playtime5")
	expect(claim.Active, true, "the claim is reachable at 6:40 played")
	claim.Activated:Fire()
	expect(#host.Actions, 1, "one press sends one action")
	expect(host.Actions[1].Name, "ClaimPlaytimeReward", "the contract's action name")
	expect(host.Actions[1].Payload.Minutes, 5, "carrying the milestone it belongs to")
	expect(claim.Text, "CLAIMING...", "the button says what it is waiting for")
	expect(claim.Active, false, "and is out of the input stack until it is answered")
	expect(claim.Visible, true, "still drawn, because the wait is the message")
	claim.Activated:Fire()
	claim.Activated:Fire()
	expect(#host.Actions, 1, "a second and third press send nothing")

	-- The 15 minute card is a DIFFERENT request and stays reachable.
	local other = buttonFor(host, "Playtime15")
	expect(other.Text, "8:20 TO GO", "the fifteen is still locked at 6:40")

	host:push({PlaytimeSeconds = 400, Claimed = {["5"] = true}})
	expect(partOf(host, 5, "ClaimedCheck").Visible, true, "the push is the answer")
	expect(claim.Visible, false, "and the button gives way to the tick")
	advance(8)
	expect(#host.Status, 0, "the timeout does not fire for a request that was answered")
	expect(host.Refreshes, 0, "and nothing is re-read needlessly")
	handle.destroy()
end

-- ══ 7. a request nobody answers recovers by RE-READING ════════════════════
do
	local host = newHost()
	local handle = mount(host)
	host:push({PlaytimeSeconds = 900})
	local claim = buttonFor(host, "Playtime15")
	expect(claim.Text, "CLAIM", "fifteen minutes is claimable")
	claim.Activated:Fire()
	expect(claim.Text, "CLAIMING...", "and the press locks it")
	advance(5)
	expect(claim.Text, "CLAIMING...", "it is still waiting at five seconds")
	expect(host.Refreshes, 0, "and has not given up")
	advance(1.5)
	expect(#host.Status, 1, "at six seconds the terminal is told")
	expect(host.Status[1].Message, "No answer yet. Try again.", "in plain words")
	expect(host.Status[1].Tone, "error", "as an error")
	expect(host.Refreshes, 1, "and the page RE-READS rather than guessing")
	expect(claim.Text, "CLAIM", "the control comes back")
	expect(claim.Active, true, "reachable, so the player can retry")
	expect(claim.BackgroundColor3, CLAIM_READY, "and green again")
	expect(#host.Actions, 1, "the recovery itself sends nothing")
	claim.Activated:Fire()
	expect(#host.Actions, 2, "and a retry is a genuine second request")
	handle.destroy()
end

-- ══ 13. refresh() and destroy() ═══════════════════════════════════════════
do
	local host = newHost()
	local handle = mount(host)
	local listeners = heartbeat:Count()
	check(listeners >= 1, "the page runs one ticker")
	-- refresh() re-reads whatever the terminal holds now, without a push.
	host.Profile = profileOf({PlaytimeSeconds = 900, SecondsToReset = 3661})
	expect(buttonFor(host, "Playtime15").Text, "15:00 TO GO", "not yet re-read")
	handle.refresh()
	expect(buttonFor(host, "Playtime15").Text, "CLAIM", "refresh() re-renders from the profile")
	expect(host:find("ResetCountdown").Text, "RESETS IN 01:01:01" .. RESET_TAIL,
		"and re-anchors the countdown too")

	local scroll = host.Page.Children[1]
	expect(scroll.Name, "DailyRewards", "the page drew one root inside the frame it was given")
	expect(#host.Page.Children, 1, "and exactly one, so the host's frame stays its own")
	handle.destroy()
	expect(heartbeat:Count(), listeners - 1, "destroy() disconnects the ticker")
	expect(host.Disconnects, 1, "and the profile subscription")
	expect(scroll.Destroyed, true, "and takes its own tree down")
	expect(#host.Page.Children, 0, "leaving the terminal's page frame empty")
	local before = host.Refreshes
	advance(10)
	expect(host.Refreshes, before, "a destroyed page does nothing on later frames")
	handle.refresh()
	expect(host.Refreshes, before, "and refresh() after destroy is a no-op")
end

-- ══ 14. fit: four viewports, measured ═════════════════════════════════════
-- ONE ROW OF THREE everywhere except a phone held upright, where three cards
-- across 330px of content box would be 100px each -- narrower than the art they
-- exist to show. That tier gets one horizontal card per row instead.
-- `Tight` is the phone held sideways: one merged strip, no progress caption and
-- the shorter card. `AboveFold` is the promise that CLAIM can be pressed without
-- scrolling -- true everywhere except the portrait column, which is a list by
-- design and scrolls like one.
local FITS = {
	{Name = "phone portrait 390x844", Fit = PHONE_PORTRAIT, Column = true,
		Tight = false, AboveFold = false},
	{Name = "phone landscape 844x390", Fit = PHONE_LANDSCAPE, Column = false,
		Tight = true, AboveFold = true},
	{Name = "tablet 1024x768", Fit = TABLET, Column = false,
		Tight = false, AboveFold = true},
	{Name = "pointer 1280x720", Fit = POINTER, Column = false,
		Tight = false, AboveFold = true},
}
for _, entry in ipairs(FITS) do
	local fit, name = entry.Fit, entry.Name
	local host = newHost()
	local handle = mount(host, fit)
	host:push({PlaytimeSeconds = 900})
	host:layout(fit)

	local scroll = host.Page.Children[1]
	local body = host:find("PlaytimeSection")
	local strip = host:find("CountdownStrip")

	local play = host:find("PlayStrip")
	local parts = entry.Tight and {body, play} or {strip, body, play}
	for _, part in ipairs(parts) do
		local left = offsetWithin(part, scroll)
		check(left >= 0 and left + part.Size.OX <= fit.ContentWidth,
			name .. ": " .. part.Name .. " spans " .. tostring(left) .. ".."
			.. tostring(left + part.Size.OX) .. " inside " .. tostring(fit.ContentWidth))
		check(part.Size.OX > 0 and part.Size.OY > 0,
			name .. ": " .. part.Name .. " has a real rectangle")
	end

	-- The strips: two rows on every tier but the phone held sideways, where the
	-- countdown moves into the play strip and shares its one row.
	local clock = host:find("ResetCountdown")
	expect(strip.Visible, not entry.Tight, name .. ": the countdown strip's own row")
	expect(host:find("ProgressCaption").Visible, not entry.Tight,
		name .. ": the progress caption")
	if entry.Tight then
		expect(clock.Parent, play, name .. ": the countdown shares the play strip's row")
		expect(clock.TextXAlignment, Enum.TextXAlignment.Right,
			name .. ": pushed to the right of it, with the played time on the left")
		expect(clock.Text, "RESETS IN 05:12:33",
			name .. ": and shortened, because it no longer has a row to itself")
		check(play.Size.OY <= 44, name .. ": the merged strip is "
			.. tostring(play.Size.OY) .. "px, the ceiling is 44")
		expect(offsetWithin(body, scroll), 0, name .. ": and it starts at the top of the scroll")
		local _, playTop = offsetWithin(play, scroll)
		expect(playTop, 0, name .. ": with nothing above it")
	else
		expect(clock.Parent, strip, name .. ": the countdown keeps its own strip")
		expect(clock.Text, "RESETS IN 05:12:33" .. RESET_TAIL,
			name .. ": with room for the UTC boundary it counts to")
	end
	expect(body.Position.OX, 0, name .. ": the body is flush with the left edge")
	expect(body.Size.OX, fit.ContentWidth - 8,
		name .. ": and takes the full content width less the scrollbar")
	expect(wheelRemnant(host), nil, name .. ": nothing of the wheel is drawn at this tier")
	expect(forbiddenCopy(host), nil, name .. ": and nothing names the supply fiction")
	local bottom = body.Position.OY + body.Size.OY
	check(scroll.CanvasSize.OY >= bottom,
		name .. ": the canvas reaches the last row (" .. tostring(scroll.CanvasSize.OY)
		.. " >= " .. tostring(bottom) .. ")")

	-- The three cards, in the arrangement this tier calls for.
	local previous = nil
	for _, minutes in ipairs({5, 15, 35}) do
		local card = cardOf(host, minutes)
		local left, top = offsetWithin(card, scroll)
		check(left >= 0 and left + card.Size.OX <= fit.ContentWidth,
			name .. ": card " .. minutes .. " spans " .. tostring(left) .. ".."
			.. tostring(left + card.Size.OX) .. " inside " .. tostring(fit.ContentWidth))
		check(top >= 0 and top + card.Size.OY <= scroll.CanvasSize.OY,
			name .. ": card " .. minutes .. " is inside the scrollable canvas")
		if previous then
			if entry.Column then
				expect(card.Position.OX, previous.Position.OX,
					name .. ": a column keeps every card on the same left edge")
				check(card.Position.OY >= previous.Position.OY + previous.Size.OY,
					name .. ": and stacks card " .. minutes .. " under the one before it")
			else
				expect(card.Position.OY, previous.Position.OY,
					name .. ": a row keeps every card on the same top edge")
				check(card.Position.OX >= previous.Position.OX + previous.Size.OX,
					name .. ": and sets card " .. minutes .. " beside the one before it")
			end
		end
		previous = card

		local icon = partOf(host, minutes, "RewardIcon")
		expect(icon.Size.OX, icon.Size.OY, name .. ": card " .. minutes .. "'s icon is square")
		check(icon.Size.OX >= 56, name .. ": card " .. minutes .. "'s icon is "
			.. tostring(icon.Size.OX) .. "px, the floor is 56")
		-- The icon is the dominant element -- 45% of the card -- unless the host
		-- handed the page so little height that it has been squeezed to the floor,
		-- in which case the body scrolls instead of shrinking the art further.
		check(icon.Size.OY * 100 >= card.Size.OY * 45 or icon.Size.OY == 56,
			name .. ": card " .. minutes .. "'s icon is " .. tostring(icon.Size.OY)
			.. " of " .. tostring(card.Size.OY))
		local ix, iy = offsetWithin(icon, card)
		check(ix >= 0 and ix + icon.Size.OX <= card.Size.OX,
			name .. ": card " .. minutes .. "'s icon fits horizontally")
		check(iy >= 0 and iy + icon.Size.OY <= card.Size.OY,
			name .. ": card " .. minutes .. "'s icon fits vertically")

		local badge = partOf(host, minutes, "ClaimedCheck")
		local bx, by = offsetWithin(badge, card)
		check(bx >= 0 and bx + badge.Size.OX <= card.Size.OX,
			name .. ": card " .. minutes .. "'s tick cannot hang off the card")
		check(by >= 0 and by + badge.Size.OY <= card.Size.OY,
			name .. ": card " .. minutes .. "'s tick stays on it vertically")
	end

	-- Every card action: drawn, inside the box, and at the tap floor on touch.
	for _, card in ipairs(host.Cards) do
		local action = card.Action
		local actionLeft, actionTop = offsetWithin(action, scroll)
		check(action.Size.OX > 0 and action.Size.OY > 0,
			name .. ": " .. card.Key .. "'s action is drawn")
		check(actionLeft >= 0 and actionLeft + action.Size.OX <= fit.ContentWidth,
			name .. ": " .. card.Key .. "'s action ends inside the content box")
		check(actionTop >= 0 and actionTop + action.Size.OY <= scroll.CanvasSize.OY,
			name .. ": " .. card.Key .. "'s action is inside the scrollable canvas")
		check(action.Size.OY >= 44,
			name .. ": " .. card.Key .. "'s CLAIM is " .. tostring(action.Size.OY)
			.. "px tall, the floor is 44 at every tier")
		-- REACHABLE WITHOUT SCROLLING. The portrait column is a list and scrolls
		-- like one; every other tier has to land the whole state row inside the
		-- box the host handed the page, or the one control the card exists for
		-- is a flick away on the tier where a thumb covers half the screen.
		if entry.AboveFold then
			check(actionTop + action.Size.OY <= fit.ContentHeight,
				name .. ": " .. card.Key .. "'s CLAIM ends at "
				.. tostring(actionTop + action.Size.OY) .. ", the fold is "
				.. tostring(fit.ContentHeight))
		end
		if fit.Touch then
			check(action.Size.OX >= 44,
				name .. ": " .. card.Key .. "'s action is " .. tostring(action.Size.OX)
				.. "px wide, the floor is 44")
		end
	end

	-- Nothing prints below 11px, anywhere on the page, at any tier.
	local smallest = 999
	local counted = 0
	for _, node in ipairs(descendants(scroll)) do
		if node.TextSize ~= nil and (node.ClassName == "TextLabel"
			or node.ClassName == "TextButton") then
			smallest = math.min(smallest, node.TextSize)
			counted += 1
		end
	end
	check(counted >= 12, name .. ": the page draws its full set of copy (" .. counted .. ")")
	check(smallest >= 11, name .. ": the smallest face is " .. tostring(smallest) .. "px")

	-- Every label stays inside the card or strip it belongs to. This is the
	-- arithmetic that catches a rectangle still sized against the previous tier.
	for _, node in ipairs(descendants(body)) do
		if node.ClassName == "TextLabel" or node.ClassName == "TextButton" then
			local left = offsetWithin(node, node.Parent)
			check(left >= 0 and left + node.Size.OX <= node.Parent.Size.OX,
				name .. ": " .. node.Name .. " spans " .. tostring(left) .. ".."
				.. tostring(left + node.Size.OX) .. " inside its parent "
				.. tostring(node.Parent.Size.OX))
		end
	end
	handle.destroy()
end

-- ══ 15. the page survives a host that is missing pieces ═══════════════════
do
	-- Not a hypothetical: the Daily Rewards Client draws "DAILY REWARDS
	-- UNAVAILABLE" when the module is absent, and a module that errored on mount
	-- would take its host's whole layout pass with it.
	local host = newHost()
	host.ctx.contract = nil
	host.ctx.showStatus = nil
	host.ctx.isVisible = nil
	local ok, err = pcall(function() return Page.mount(host.Page, host.ctx) end)
	check(ok, "mounting without the optional ctx members does not error: " .. tostring(err))
	check(findByName(host.Page, "DailyRewards") ~= nil, "and the page is still drawn")
end

do
	-- A host with no SetInteractive at all still hides the claimed button: the
	-- page falls back to Visible/Active rather than leaving a dead control up.
	local host = newHost()
	host.ctx.UIDevice = {SetEnabled = function(element, enabled) element.Active = enabled end}
	local handle = mount(host)
	host:push({PlaytimeSeconds = 400, Claimed = {["5"] = true}})
	expect(buttonFor(host, "Playtime5").Visible, false, "the claimed button is hidden anyway")
	expect(buttonFor(host, "Playtime5").Active, false, "and cannot be pressed")
	handle.destroy()
end

do
	-- A server without the config cannot honour a claim, so the page says so
	-- rather than offering a control that does nothing.
	local host = newHost()
	local bare = table.clone(Config)
	bare.DailyRewards = nil
	host.ctx.Config = bare
	local handle = mount(host)
	expect(#host.Cards, 0, "no config, no card actions")
	check(findByName(host.Page, "RewardsOffline") ~= nil, "the page states that it is offline")
	expect(host:find("PlaytimeSection").Visible, false, "and draws no playtime controls")
	expect(wheelRemnant(host), nil, "and there was no wheel to hide in the first place")
	expect(host:find("ResetCountdown").Text, "RESETS IN 05:12:33" .. RESET_TAIL,
		"the countdown strip still reads correctly")
	expect(forbiddenCopy(host), nil, "and the offline page names no supply fiction either")
	handle.destroy()
end

print("Daily rewards page: " .. tostring(checks)
	.. " checks passed (offline Luau, config source: " .. configSource
	.. "; font metrics, TextBounds, real UIDevice and rendering not exercised)")
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    source = "\n".join([
        PRELUDE,
        # the real shared style module
        "local UIStyle = (function()", UISTYLE, "end)()",
        # the real config, so the reward numbers are the shipped ones
        "local RealConfig = (function()", CONFIG, "end)()",
        # ZyntraStore's real palette and its real corner/outline/label/button
        section(STORE, "local COLORS = {", 'local gui = Instance.new("ScreenGui")'),
        section(STORE, "local function corner(parent, radius)", "-- Imagegen section art"),
        # the module under test, run as a module
        "Research = (function()", RESEARCH, "end)()",
        "local Page = (function()", PAGE, "end)()",
        HARNESS,
        TESTS,
    ])
    with tempfile.TemporaryDirectory(prefix="daily-rewards-page-") as directory:
        fixture = Path(directory) / "daily_rewards_page.luau"
        fixture.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=120)


if __name__ == "__main__":
    main()
