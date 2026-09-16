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

What it proves, by running the code rather than matching strings: the claim
states drawn for a given saved profile, the UTC day-roll guard, the local
countdown after real elapsed time, that one press fires exactly one action and
then locks, that a request nobody answers recovers by RE-READING instead of
granting, that nothing the page builds can send `SpinDailyWheel`, and that every
rectangle at four viewport tiers lands inside the host's own content box at or
above the 44px touch floor.

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

-- The fit table applyTerminalLayout publishes, rebuilt from the same figures
-- (840x610 design, 260 floor, compact under 640x430, 12/20 padding, 44 tap).
-- ContentHeight is not used by this page, so it is only approximated.
local function fitFor(viewportWidth, viewportHeight, touch)
	local width = math.floor(math.clamp(math.min(840, viewportWidth), 260, 840))
	local height = math.floor(math.min(610, viewportHeight))
	local compact = width < 640 or height < 430
	local tap = touch and 44 or 32
	local pad = compact and 12 or 20
	return {Width = width, Height = height, ContentWidth = width - pad * 2,
		ContentHeight = math.max(96, height - 200), Compact = compact, Touch = touch,
		Tap = tap, TabHeight = math.max(tap, compact and 40 or 42),
		TabMinWidth = compact and 88 or 110}
end
local PHONE_PORTRAIT = fitFor(390, 844, true)
local PHONE_LANDSCAPE = fitFor(844, 390, true)
local TABLET = fitFor(1024, 768, true)
local POINTER = fitFor(1280, 720, false)

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
'''


TESTS = r'''
-- ══ 1. a fresh day ════════════════════════════════════════════════════════
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

	-- The MODAL owns its own name: the Daily Rewards Client prints the eyebrow
	-- and the title in its title bar, and the terminal prints its own. A page
	-- title here would be the same two words twice, 40px apart.
	expect(findByName(host.Page, "Title"), nil, "the page draws no title of its own")
	expect(findByName(host.Page, "Eyebrow"), nil, "and no eyebrow of its own")
	expect(host:find("ResetNote").Text, "Resets 00:00 UTC", "the UTC boundary is stated")
	expect(host:find("ResetCountdown").Text, "RESETS IN 05:12:33",
		"the countdown is drawn from SecondsToReset")
	expect(host:find("PlaytimeReadout").Text, "ACTIVE PLAY TODAY  0:00",
		"a fresh day has no active play")
	expect(host:find("ProgressCaption").Text, "5:00 to the 5 minute reward",
		"the caption names the next milestone")
	expect(host:find("ProgressTrack"):FindFirstChild("Fill").Size.SX, 0,
		"the progress fill is empty at zero seconds")

	expect(host:find("Milestone5"):FindFirstChild("CardTitle").Text, "5 MINUTES", "5 minute card")
	expect(host:find("Milestone15"):FindFirstChild("CardTitle").Text, "15 MINUTES", "15 minute card")
	expect(host:find("Milestone35"):FindFirstChild("CardTitle").Text, "35 MINUTES", "35 minute card")
	expect(host:find("Milestone5"):FindFirstChild("CardReward").Text, "1 Research Token",
		"5 minutes pays a token")
	expect(host:find("Milestone15"):FindFirstChild("CardReward").Text, "1 Speed Potion",
		"15 minutes pays a potion")
	expect(host:find("Milestone35"):FindFirstChild("CardReward").Text, "1 Entity Shield",
		"35 minutes pays a shield charge")

	for _, case in ipairs({{"Playtime5", "5:00 TO GO"}, {"Playtime15", "15:00 TO GO"},
		{"Playtime35", "35:00 TO GO"}}) do
		local action = buttonFor(host, case[1])
		expect(action.Text, case[2], case[1] .. " is locked with its remaining time")
		expect(action.Active, false, case[1] .. " cannot be pressed while locked")
	end

	expect(wheelRemnant(host), nil, "the page builds no wheel instance at all")
	expect(host:find("WheelNote").Text,
		"Spin the Lucky Wheel from its own button on the left rail.",
		"and says where the wheel went instead")
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
	expect(buttonFor(host, "Playtime5").Text, "CLAIM", "five minutes unlocks the claim")
	expect(buttonFor(host, "Playtime5").Active, true, "and it is reachable")
	expect(buttonFor(host, "Playtime15").Text, "10:00 TO GO", "the next one is still locked")
	expect(host:find("ProgressCaption").Text, "10:00 to the 15 minute reward",
		"the caption moves to the next milestone")

	host:push({PlaytimeSeconds = 300, Claimed = {["5"] = true}})
	expect(buttonFor(host, "Playtime5").Text, "CLAIMED", "a claimed milestone says so")
	expect(buttonFor(host, "Playtime5").Active, false, "and cannot be claimed twice")

	host:push({PlaytimeSeconds = 2100})
	expect(buttonFor(host, "Playtime5").Text, "CLAIM", "35 minutes clears the five")
	expect(buttonFor(host, "Playtime15").Text, "CLAIM", "35 minutes clears the fifteen")
	expect(buttonFor(host, "Playtime35").Text, "CLAIM", "35 minutes clears the thirty-five")
	expect(host:find("ProgressTrack"):FindFirstChild("Fill").Size.SX, 1,
		"the progress bar is full at the last milestone")
	expect(host:find("ProgressCaption").Text, "Every milestone reached today.",
		"with nothing left, the caption says so")

	host:push({PlaytimeSeconds = 4000, Claimed = {["5"] = true, ["15"] = true, ["35"] = true}})
	for _, key in ipairs({"Playtime5", "Playtime15", "Playtime35"}) do
		expect(buttonFor(host, key).Text, "CLAIMED", key .. " is claimed for the day")
		expect(buttonFor(host, key).Active, false, key .. " is out of the input stack")
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
	expect(wheelRemnant(host), nil, "and yesterday's recorded prize draws nothing")
	handle.destroy()
end

-- ══ 5. the countdown ticks locally, at 1 Hz, and re-anchors on every push ══
do
	local host = newHost()
	local handle = mount(host)
	expect(host:find("ResetCountdown").Text, "RESETS IN 05:12:33", "the anchored countdown")
	advance(61)
	expect(host:find("ResetCountdown").Text, "RESETS IN 05:11:32",
		"61 seconds of real time takes 61 seconds off the countdown")
	-- Hidden: the ticker stops redrawing. The clock underneath is server time,
	-- so the countdown is correct again the moment the page comes back.
	host.Visible = false
	advance(120)
	expect(host:find("ResetCountdown").Text, "RESETS IN 05:11:32",
		"a page nobody is looking at does not redraw")
	host.Visible = true
	advance(1)
	expect(host:find("ResetCountdown").Text, "RESETS IN 05:09:31",
		"and it catches up from the clock, not from what it drew last")
	-- A push re-anchors it, which is what keeps it from drifting.
	host:push({SecondsToReset = 65})
	expect(host:find("ResetCountdown").Text, "RESETS IN 00:01:05", "a push re-anchors the countdown")
	local before = host.Refreshes
	advance(66)
	expect(host:find("ResetCountdown").Text, "RESETS IN 00:00:00", "it floors at zero")
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
	claim.Activated:Fire()
	claim.Activated:Fire()
	expect(#host.Actions, 1, "a second and third press send nothing")

	-- The 15 minute card is a DIFFERENT request and stays reachable.
	local other = buttonFor(host, "Playtime15")
	expect(other.Text, "8:20 TO GO", "the fifteen is still locked at 6:40")

	host:push({PlaytimeSeconds = 400, Claimed = {["5"] = true}})
	expect(claim.Text, "CLAIMED", "the push is the answer")
	expect(claim.Active, false, "and a claimed milestone stays out of the stack")
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
	expect(host:find("ResetCountdown").Text, "RESETS IN 01:01:01",
		"and re-anchors the countdown too")

	local scroll = host.Page.Children[1]
	expect(scroll.Name, "DailyRewards", "the page drew one root inside the frame it was given")
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
-- ONE COLUMN AT EVERY TIER since #104: the wheel was the second column, and a
-- half-width card beside an empty half is not a composition.
local FITS = {
	{Name = "phone portrait 390x844", Fit = PHONE_PORTRAIT},
	{Name = "phone landscape 844x390", Fit = PHONE_LANDSCAPE},
	{Name = "tablet 1024x768", Fit = TABLET},
	{Name = "pointer 1280x720", Fit = POINTER},
}
for _, entry in ipairs(FITS) do
	local fit, name = entry.Fit, entry.Name
	local host = newHost()
	local handle = mount(host, fit)
	host:push({PlaytimeSeconds = 900})
	host:layout(fit)

	local scroll = host.Page.Children[1]
	local playtime = host:find("PlaytimeSection")
	local header = host:find("RewardsHeader")

	for _, part in ipairs({header, playtime}) do
		check(part.Position.OX + part.Size.OX <= fit.ContentWidth,
			name .. ": " .. part.Name .. " ends inside the content box")
		check(part.Position.OX >= 0, name .. ": " .. part.Name .. " starts inside it")
		check(part.Size.OX > 0 and part.Size.OY > 0,
			name .. ": " .. part.Name .. " has a real rectangle")
	end
	expect(playtime.Position.OX, 0, name .. ": one column, flush with the left edge")
	expect(playtime.Size.OX, fit.ContentWidth - 8,
		name .. ": and it takes the full content width less the scrollbar")
	expect(wheelRemnant(host), nil, name .. ": nothing of the wheel is drawn at this tier")
	local bottom = playtime.Position.OY + playtime.Size.OY
	check(scroll.CanvasSize.OY >= bottom,
		name .. ": the canvas reaches the last row (" .. tostring(scroll.CanvasSize.OY)
		.. " >= " .. tostring(bottom) .. ")")

	-- Every card action: drawn, inside the box, and at the tap floor on touch.
	for _, card in ipairs(host.Cards) do
		local left = offsetWithin(card.Card, scroll)
		check(left >= 0 and left + card.Card.Size.OX <= fit.ContentWidth,
			name .. ": card " .. card.Key .. " spans " .. tostring(left) .. ".."
			.. tostring(left + card.Card.Size.OX) .. " inside " .. tostring(fit.ContentWidth))
		local action = card.Action
		local actionLeft, actionTop = offsetWithin(action, scroll)
		check(action.Size.OX > 0 and action.Size.OY > 0,
			name .. ": " .. card.Key .. "'s action is drawn")
		check(actionLeft >= 0 and actionLeft + action.Size.OX <= fit.ContentWidth,
			name .. ": " .. card.Key .. "'s action ends inside the content box")
		check(actionTop >= 0 and actionTop + action.Size.OY <= scroll.CanvasSize.OY,
			name .. ": " .. card.Key .. "'s action is inside the scrollable canvas")
		if fit.Touch then
			check(action.Size.OY >= 44,
				name .. ": " .. card.Key .. "'s action is " .. tostring(action.Size.OY)
				.. "px tall, the floor is 44")
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

	-- Every label in the section stays inside the section it belongs to. The
	-- one-column collapse widened `inner`, so this is the arithmetic that would
	-- catch a rectangle still sized against the old half-width column.
	for _, node in ipairs(descendants(playtime)) do
		if node.ClassName == "TextLabel" or node.ClassName == "TextButton" then
			local left = offsetWithin(node, playtime)
			check(left >= 0 and left + node.Size.OX <= playtime.Size.OX,
				name .. ": " .. node.Name .. " spans " .. tostring(left) .. ".."
				.. tostring(left + node.Size.OX) .. " inside " .. tostring(playtime.Size.OX))
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
	expect(host:find("ResetNote").Text, "Resets 00:00 UTC",
		"the countdown strip still reads correctly")
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
