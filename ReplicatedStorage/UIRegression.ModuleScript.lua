--!strict
-- UIRegression - deterministic HUD checks, run from a live client.
--
-- Three properties are asserted, at whatever viewport the client is currently
-- rendering. Drive it from the Studio Device Simulator (set the device BEFORE
-- entering Play; the simulator's setters error in PlayServer) and call
-- UIRegression.Assert() once per device in the matrix.
--
--   1. ONSCREEN   - every visible top-level HUD rectangle lies inside the
--                   viewport.
--   2. NO OVERLAP - visible top-level HUD rectangles do not overlap each other,
--                   and on a touch form factor none of them overlaps the
--                   movement-control reserved zones.
--   3. NO KEYS    - on a touch form factor, no visible string names a
--                   keyboard-only binding.
--
-- "Top-level HUD rectangle" means a direct child of a ScreenGui. That is the
-- honest unit: children overlapping their own parent is normal composition,
-- two HUD panels overlapping each other is the bug.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Used by BriefingFitMatrix only. GetTextBoundsAsync is the ONE way to ask what
-- a string WOULD need at a size and wrap width the client is not currently
-- rendering; the TextBounds property can only ever answer for what is on screen
-- right now, at the one viewport Studio happens to be drawing.
local TextService = game:GetService("TextService")
-- GetInsetArea is the authority on where a ScreenGui actually is.
local GuiService = game:GetService("GuiService")

local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
-- The same whitelist the store consults, so "does this account have a DEV page"
-- is answered independently of whether the store built one.
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))

local Fit = {}

-- ── THE HARNESS LOCK ───────────────────────────────────────────────────
-- C_HARNESS_LOCK_20260831 -- WHAT SHIPPED BROKEN.
--
-- Every public matrix borrows the same workspace attributes, the same player
-- attributes and the same ScreenGuis. Two of them running at once do not
-- produce two reports; they produce two sets of half-applied device overrides
-- and a pile of failures belonging to neither. It happened: a run in which one
-- matrix errored mid-sweep left `UIRegressionForceDispatchActive` set, and the
-- next matrix reported eighteen failures for a terminal that simply refused to
-- open while a briefing it could not see was forced on.
--
-- The first lock was a MODULE LOCAL, and it serialized none of the three things
-- that actually needed serializing:
--
--   * IT COULD NOT BE SEEN FROM A SECOND VM. A matrix is driven from Studio's
--     execute_luau and every invocation gets its own require cache, so two
--     concurrent runs each held their own private `harnessLock`, each read
--     Depth == 0, and both proceeded. The one collision the lock exists to stop
--     was the one case it was structurally unable to observe.
--   * ADMISSION WAS BY NAME. Re-entry was granted to ANY caller whenever the
--     owner string happened to be "RunAll", so a lane fired by hand walked
--     straight into the middle of a full run and began rewriting the device
--     overrides under it -- and reported the result as its own.
--   * THE ABANDONMENT SWEEP EXEMPTED "RunAll" from being taken over, which is
--     backwards. RunAll is the longest holder and therefore the one most likely
--     to be killed mid-flight, and it was the only holder that could strand the
--     lock forever.
--
-- The lock is now DATAMODEL-BACKED, so every VM in the place reads one holder,
-- and admission is by TOKEN, so only the run that took the lock -- or a call it
-- explicitly handed the token to -- can re-enter. RunAll passes its token down
-- to each lane it composes; nothing enters on the strength of a name.
--
-- It also HEARTBEATS. A long lane can outlive the caller's request timeout: the
-- request is abandoned, the thread it started keeps running, and if it is later
-- killed with the lock held, every subsequent call is refused by a holder that
-- no longer exists. That happened, and it looks exactly like a hung suite. So
-- the holder stamps a wall-clock beat on every recorded check and every fixture
-- it applies, and a holder that has not beaten for LOCK_ABANDONED_AFTER seconds
-- is taken over -- RunAll included -- with the takeover REPORTED in the next
-- report rather than quietly benefited from.
--
-- os.time, not os.clock: inside the Studio datamodel os.clock is CPU time and
-- runs about four times slower than the wall, so a clock-based window would be
-- roughly four times wider than it reads.
--
-- WHY 180 SECONDS. The window has to exceed the longest gap BETWEEN BEATS, not
-- the length of a run. Beats land on every recorded check and every applied
-- fixture, so inside a sweeping lane the gap is well under a second; the widest
-- unbeaten stretch in the suite is RunAll's scenario loop, where one scenario's
-- Setup, its 0.3s settle and a full Check() over every ScreenGui cost about a
-- second, and the slowest single lane runs about 45s of wall clock end to end.
-- 180 is four times that slowest lane: wide enough that a Studio hitch or a
-- stalled GetTextBoundsAsync cannot get a live holder declared dead, narrow
-- enough that a genuinely killed run frees the harness within three minutes.
local LOCK_ABANDONED_AFTER = 180
-- C_LOCK_CLAIM_IS_VERIFIED_20260831 -- WHAT SHIPPED BROKEN.
--
-- Publishing the lock was three separate SetAttribute calls preceded by a
-- read-increment-write on the sequence counter, and nothing looked at the result
-- afterwards. Two VMs claiming at once interleave their writes and BOTH walk
-- away believing they hold it -- which is the exact failure the lock was rebuilt
-- to stop, moved one level down. There is no compare-and-swap on an attribute,
-- so the claim is made honest the way a lock without CAS has to be: publish,
-- wait long enough for a competing publish to have landed, read the whole record
-- back, and only proceed if every field is still the one you wrote. A claim that
-- cannot be verified is abandoned, not assumed.
--
-- The window is three frames at 60Hz. It has to outlast the gap between another
-- claimant's first and last attribute write -- three adjacent SetAttribute calls
-- on one thread, i.e. no yield at all -- so a single frame would do; three is
-- the cheap margin for a Studio hitch, and only a FRESH claim pays it. Re-entry
-- by identity, which is what a RunAll does eleven times, does not.
local LOCK_VERIFY_WINDOW = 0.05
local LOCK_CLAIM_ATTEMPTS = 4
-- The attribute names live IN the table rather than beside it: this chunk is
-- close enough to Luau's 200-locals-per-chunk ceiling that four more file-level
-- locals is a real risk, and the lock is not worth spending them on.
--
-- Token / Lane / Depth are what THIS VM believes. The attributes are what every
-- VM can see. The two are compared, never assumed to agree.
local harnessLock = {
	Token = nil, Lane = nil, Depth = 0, Beat = 0, Stolen = nil,
	TokenAttribute = "UIRegressionHarnessLockToken",
	LaneAttribute = "UIRegressionHarnessLockLane",
	BeatAttribute = "UIRegressionHarnessLockBeat",
	SequenceAttribute = "UIRegressionHarnessLockSequence",
}

-- The PUBLISHED holder: token, lane name, last beat. Read fresh on every call,
-- because another VM may have taken or dropped the lock since this one looked.
function Fit.lockHolder(): (string?, string, number)
	local token = workspace:GetAttribute(harnessLock.TokenAttribute)
	if type(token) ~= "string" or token == "" then return nil, "", 0 end
	local lane = workspace:GetAttribute(harnessLock.LaneAttribute)
	local beat = workspace:GetAttribute(harnessLock.BeatAttribute)
	return token,
		type(lane) == "string" and lane or "an unnamed lane",
		type(beat) == "number" and beat or 0
end

-- Called by every record() and every Fit.apply, so "is the holder alive" is
-- answered by work actually happening rather than by a timer.
--
-- Throttled to one write per wall-clock second. A full RunAll records about
-- 1800 checks, and an attribute write per check would be 1800 change signals
-- fired into the very UIDevice listeners this suite exists to measure.
--
-- It also refuses to beat a lock this VM no longer owns. Without that, a run
-- that had already been taken over as abandoned would keep its SUCCESSOR's beat
-- fresh from the outside, and the takeover would never settle.
function Fit.beat()
	if harnessLock.Depth <= 0 then return end
	local now = os.time()
	if now == harnessLock.Beat then return end
	harnessLock.Beat = now
	if workspace:GetAttribute(harnessLock.TokenAttribute) ~= harnessLock.Token then return end
	workspace:SetAttribute(harnessLock.BeatAttribute, now)
end

-- A token no other run can collide with, without reaching for math.random: the
-- monotonic counter separates two mints inside the same second, os.time
-- separates a run from one that started after the counter was cleared (a fresh
-- place, a wiped attribute), and the lane name makes the token readable in the
-- refusal message a blocked caller actually has to act on.
function Fit.mintToken(name: string): string
	local sequence = workspace:GetAttribute(harnessLock.SequenceAttribute)
	sequence = (type(sequence) == "number" and sequence or 0) + 1
	workspace:SetAttribute(harnessLock.SequenceAttribute, sequence)
	return string.format("%s#%d@%d", name, sequence, os.time())
end

-- Returns (admitted, why-not, lease). The LEASE is the only thing that can
-- release this acquisition, and it is one-shot; see Fit.release.
function Fit.acquire(name: string, token: string?): (boolean, string?, any)
	local held, heldLane, heldBeat = Fit.lockHolder()
	-- RE-ENTRY BY IDENTITY, NEVER BY NAME. The caller has to present the token
	-- of the run in flight, AND this VM has to be the one holding it. RunAll
	-- hands its token to each lane it composes; a lane invoked from anywhere
	-- else has no token to present and queues behind the run like any other
	-- caller, which is exactly what "RunAll" as a password never did.
	if held ~= nil and token ~= nil and token == held and token == harnessLock.Token then
		harnessLock.Depth += 1
		Fit.beat()
		return true, nil, {Token = token, Released = false}
	end
	if held ~= nil then
		local age = os.time() - heldBeat
		if age <= LOCK_ABANDONED_AFTER then
			return false, string.format(
				"%s cannot run: the UIRegression harness is held by %s (token %s),"
				.. " which last recorded a check %ds ago. The lanes share the device"
				.. " overrides and the HUD's gui state, so they are serialized rather"
				.. " than interleaved. Wait for it to finish, call RunAll -- which owns"
				.. " the lock and runs every lane in order -- or wait %ds more, after"
				.. " which that holder is treated as abandoned and taken over.",
				name, heldLane, held, age, LOCK_ABANDONED_AFTER - age + 1), nil
		end
		harnessLock.Stolen = string.format(
			"%s took the harness lock from %s (token %s), which had not recorded a"
			.. " check in %ds and is treated as abandoned. Whatever that run left"
			.. " behind is still on the screen this report measured.",
			name, heldLane, held, age)
	end
	if harnessLock.Depth > 0 then
		-- This VM still believed it held the lock, and does not. An outer frame
		-- here was taken over from the outside while it was running, so its
		-- fixtures are no longer the only ones in play and its report is no
		-- longer solely about its own work. Say so, rather than quietly stacking
		-- another depth on a lock that changed hands.
		harnessLock.Stolen = (harnessLock.Stolen and (harnessLock.Stolen .. " ") or "")
			.. string.format("%s also had to RE-TAKE the lock: %s was still running in"
				.. " this VM when the lock was taken away from it.",
				name, tostring(harnessLock.Lane))
	end
	-- C_LOCK_STALE_DEPTH_20260831 -- WHAT SHIPPED BROKEN.
	--
	-- The branch above SAID the lock had changed hands and then the claim below
	-- did `Depth += 1` regardless. A VM whose run had been killed or taken over
	-- while it believed Depth == 1 re-acquired at 2, and the single lease its new
	-- lane released took it back to 1 -- never to zero, so Fit.release never
	-- reached the branch that clears the published attributes. The lock it had
	-- just claimed was stranded for the whole 180-second abandonment window, and
	-- every lane in that VM was refused by a holder that was itself.
	--
	-- A fresh claim is a fresh start. The stale belief is discarded here, once,
	-- after it has been reported and before anything is published, so the depth
	-- the claim installs is always exactly 1.
	harnessLock.Token = nil
	harnessLock.Lane = nil
	harnessLock.Depth = 0
	harnessLock.Beat = 0

	-- CLAIM, VERIFY, RETRY. See LOCK_VERIFY_WINDOW.
	local lastSeenLane = ""
	for attempt = 1, LOCK_CLAIM_ATTEMPTS do
		local fresh = Fit.mintToken(name)
		workspace:SetAttribute(harnessLock.TokenAttribute, fresh)
		workspace:SetAttribute(harnessLock.LaneAttribute, name)
		workspace:SetAttribute(harnessLock.BeatAttribute, os.time())
		task.wait(LOCK_VERIFY_WINDOW)
		local seen, seenLane, _ = Fit.lockHolder()
		if seen == fresh and seenLane == name then
			harnessLock.Token = fresh
			harnessLock.Lane = name
			harnessLock.Depth = 1
			harnessLock.Beat = 0
			Fit.beat()
			return true, nil, {Token = fresh, Released = false}
		end
		-- Somebody else's record is published. It is THEIRS: this claim writes
		-- nothing further and, critically, clears nothing -- a loser that tidied
		-- up would be deleting the winner's lock.
		lastSeenLane = seenLane
		task.wait(LOCK_VERIFY_WINDOW * attempt)
	end
	return false, string.format(
		"%s cannot run: its claim on the UIRegression harness lock did not survive"
		.. " verification %d times running -- another run (%s) is claiming it at the"
		.. " same moment. Nothing was taken and nothing was cleared; retry once that"
		.. " run has finished.", name, LOCK_CLAIM_ATTEMPTS,
		lastSeenLane ~= "" and lastSeenLane or "unnamed"), nil
end

-- The whole lock, published and believed, so a test can put it back exactly.
-- Only HarnessLockMatrix uses these: it is the one lane whose subject IS the
-- lock, so it has to be able to stand the real one aside and restore it.
function Fit.lockSnapshot(): any
	return {
		Token = workspace:GetAttribute(harnessLock.TokenAttribute),
		Lane = workspace:GetAttribute(harnessLock.LaneAttribute),
		Beat = workspace:GetAttribute(harnessLock.BeatAttribute),
		Sequence = workspace:GetAttribute(harnessLock.SequenceAttribute),
		LocalToken = harnessLock.Token,
		LocalLane = harnessLock.Lane,
		LocalDepth = harnessLock.Depth,
		LocalBeat = harnessLock.Beat,
	}
end

function Fit.lockRestore(snapshot: any)
	workspace:SetAttribute(harnessLock.TokenAttribute, snapshot.Token)
	workspace:SetAttribute(harnessLock.LaneAttribute, snapshot.Lane)
	workspace:SetAttribute(harnessLock.BeatAttribute, snapshot.Beat)
	workspace:SetAttribute(harnessLock.SequenceAttribute, snapshot.Sequence)
	harnessLock.Token = snapshot.LocalToken
	harnessLock.Lane = snapshot.LocalLane
	harnessLock.Depth = snapshot.LocalDepth
	harnessLock.Beat = snapshot.LocalBeat
end

-- Publish a record directly, for the takeover and stale-depth experiments.
function Fit.lockPublish(token: any, lane: any, beat: any)
	workspace:SetAttribute(harnessLock.TokenAttribute, token)
	workspace:SetAttribute(harnessLock.LaneAttribute, lane)
	workspace:SetAttribute(harnessLock.BeatAttribute, beat)
end

function Fit.lockLocalDepth(): number
	return harnessLock.Depth
end

function Fit.lockSetLocal(token: any, lane: any, depth: number)
	harnessLock.Token = token
	harnessLock.Lane = lane
	harnessLock.Depth = depth
end

-- What the last takeover was, so a report can SAY it happened instead of
-- quietly benefiting from it. Consumed once.
function Fit.takeStolenNote(): string?
	local note = harnessLock.Stolen
	harnessLock.Stolen = nil
	return note
end

-- EXACTLY ONE RELEASE PER ACQUIRE. The lease is the receipt and it is one-shot,
-- so a lane that reaches two exits -- an early guard clause and its normal
-- return, or a return that Fit.lane then unwinds -- cannot decrement the depth
-- twice and drop a lock an outer frame still holds. Anything that is not a live
-- lease is ignored outright, which is what makes a stray legacy Fit.release()
-- harmless instead of catastrophic.
function Fit.release(lease)
	if type(lease) ~= "table" or lease.Released then return end
	-- OWNER ONLY, and checked against what THIS VM holds rather than only against
	-- what is published. A lease minted before a takeover names a token that is no
	-- longer ours; letting it decrement the depth would drop a lock the successor
	-- claim installed, and the successor would then be releasing a lock it no
	-- longer had. The lease is still marked spent so nothing retries it.
	if harnessLock.Token ~= nil and lease.Token ~= harnessLock.Token then
		lease.Released = true
		return
	end
	lease.Released = true
	harnessLock.Depth = math.max(0, harnessLock.Depth - 1)
	if harnessLock.Depth > 0 then return end
	-- Only clear the PUBLISHED lock if it is still ours. A run that was taken
	-- over as abandoned and then finished anyway must not delete its successor's
	-- claim on the way out.
	if workspace:GetAttribute(harnessLock.TokenAttribute) == harnessLock.Token then
		workspace:SetAttribute(harnessLock.TokenAttribute, nil)
		workspace:SetAttribute(harnessLock.LaneAttribute, nil)
		workspace:SetAttribute(harnessLock.BeatAttribute, nil)
	end
	harnessLock.Token = nil
	harnessLock.Lane = nil
	harnessLock.Beat = 0
end

function Fit.holder(): string?
	local held, lane = Fit.lockHolder()
	return held ~= nil and lane or nil
end

-- FINALLY-SHAPED. Every public mutating lane is a thin wrapper around a body
-- run through here, because the previous arrangement released the lock from
-- `state.finish()` -- the one exit a lane that THREW never reaches. A lane that
-- errored mid-sweep left the lock held by a thread that no longer existed, and
-- every later call was refused until the abandonment window expired: a harness
-- whose failure mode is "the harness is now unusable" is worse than no harness.
--
-- The body is handed its lease so nothing else has to thread it through, and
-- the release happens on the way out of xpcall whether the body returned or
-- threw. A thrown lane still returns a REPORT with a failure in it: a lane that
-- dies silently and a lane that passes are indistinguishable to a caller that
-- only adds up the numbers.
function Fit.lane(name: string, token: string?, body: (any) -> (string, number)): (string, number)
	local admitted, why, lease = Fit.acquire(name, token)
	if not admitted then return tostring(why), 1 end
	-- The lease is CLOSED OVER rather than handed to xpcall as a trailing
	-- argument. Forwarding arguments through xpcall is a Luau extension, and a
	-- harness whose lock release depends on a dialect extension is a harness that
	-- silently stops releasing the day it runs somewhere slightly older.
	local finished, first, second = xpcall(function()
		return body(lease)
	end, function(err)
		return tostring(err) .. "\n" .. debug.traceback("", 2)
	end)
	Fit.release(lease)
	if not finished then
		return string.format("=== %s ===\n  FAIL the lane threw and did not finish;"
			.. " the harness lock was released on the way out\n       %s\n"
			.. "TOTAL: 1 checks, 1 failed", name,
			(tostring(first):gsub("\n", "\n       "))), 1
	end
	return (first :: any) :: string, (second :: any) :: number
end

local UIRegression = {}

-- Deliberate full-screen overlays. These are MEANT to cover the HUD, so they
-- are excluded from the pairwise overlap test (they are still checked for
-- keyboard bindings and for staying onscreen).
-- Roblox's own touch controls. They ARE the movement zone, so scanning them
-- against it is circular, and TouchControlFrame is a full-screen container that
-- every HUD element trivially "overlaps".
local ENGINE_GUIS = {
	TouchGui = true,
	ControlGui = true,
}

-- This game's own movement cluster. These are movement controls, so they are
-- exempt from the movement-zone test -- but they are still required to stay
-- onscreen and not to overlap each other or any other HUD panel.
local MOVEMENT_CONTROLS = {
	TouchRunHold = true,
	-- The touch crouch. It lives in the same reserved control column as RUN and
	-- JUMP, so like them it is exempt from the movement-zone test and still has
	-- to stay onscreen, stay >= 44, and overlap nothing. Added when crouch
	-- finally got a touch path at all: it was LeftControl-only, while the store
	-- page promised "crouch silent" and "full touch controls".
	TouchSneakHold = true,
	TouchJump = true,
	TouchPOV = true,
	TouchDropGlowstick = true,
	FlashlightPower = true,
}

local FULLSCREEN_OVERLAYS = {
	LoadingCover = true,
	queueShade = true,
	QueueShade = true,
	endFrame = true,
	endFlash = true,
	Shade = true,
	Backdrop = true,
	BottomBar = true,
	-- Deliberate framing decoration drawn while the player is under a table.
	-- It is MEANT to cover the screen edges; that is the hiding effect.
	UnderTableShade = true,
	TableEdgeTop = true,
	TableEdgeBottom = true,
	-- Modal panels own the screen while they are open, and the movement cluster
	-- hides underneath them.
	Terminal = true,
	ReentryPanel = true,
	-- The result screen's accent wash. Full-bleed by design, and named after the
	-- instance rather than after the variable that used to be listed here.
	SignalFlash = true,
}

-- Panels whose INTERNAL composition is asserted, not only their outer rectangle.
-- Top-level testing is the right default -- a child overlapping its own parent is
-- ordinary composition -- but inside these panels the children are SIBLINGS
-- sharing one fixed box, and two of them landing on each other is exactly the
-- defect this harness exists to catch. It is also the defect that shipped: the
-- briefing subtitle spanned the whole panel below its speaker line while the
-- MUTE and STOP readouts sat in the same corner, and nothing here noticed.
local INTERNAL_PANELS = {
	CommandSubtitles = true,
	RoundEnding = true,
	ObjectivesPanel = true,
	-- The Zyntra terminal. It was in FULLSCREEN_OVERLAYS and NOWHERE else, so
	-- the harness measured its outer rectangle, called it a deliberate overlay
	-- and never looked inside -- while its content frame was resolving to a
	-- NEGATIVE height and every page was collapsing into one row. Its header,
	-- tab bar, content box and status line are siblings sharing one box, which
	-- is exactly the shape this list exists for.
	Terminal = true,
	-- The lobby queue panel. Its controls live two levels down, so without this
	-- the matrix measured the shade and nothing inside it -- which is how five
	-- interactive controls stayed under the 44px floor unnoticed.
	QueueHostPanel = true,
	-- The PARTY DOWN card. Its title, the line naming who fell last, the
	-- countdown bar and readout and the two actions are all siblings in one
	-- fixed box -- and one of those actions opens a Robux prompt, so the pair
	-- landing on each other is the worst version of this defect. It also has to
	-- be listed here for its children to be rectangles at all: the card sits
	-- inside a full-bleed overlay, which `collect` does not descend into.
	PartyDownCard = true,
	-- The terminal's header, for the same reason one level further in.
	-- `collectDrawnChildren` emits ONE rectangle for a child that draws itself
	-- and does not descend into it, so with only `Terminal` listed the header
	-- was measured as a solid bar and its close button, token readout and title
	-- were never rectangles at all -- which is how a title and a token readout
	-- overlapping by 58px went unreported, and why a TouchTargets fragment
	-- naming the close button could not be found.
	TerminalHeader = true,
}

-- Patterns that name a key a phone or tablet does not have. Matched against
-- every visible string; a hit on a touch form factor is a failure.
local KEYBOARD_PATTERNS = {
	-- [M] [N] [R] [Y] [H] [B] [E] [Q] [V], and the two-letter shoulder glyphs
	-- [RB] / [LB]: the one-letter form was the only one matched, so the
	-- flashlight's new gamepad caption would have printed on a phone unnoticed.
	"%[%u%u?%]",
	"%f[%w]WASD%f[%W]",
	"Left Ctrl",
	"LeftControl",
	"%f[%w]Q%s*/%s*E%f[%W]",
	"%f[%w]SHIFT%f[%W]",
	"%f[%w]SPACEBAR%f[%W]",
	"PHONE:%s*%u%f[%W]",
	"//%s+%u%f[%W]",     -- the "ACTION  //  E" idiom used by dev rows
}

local function isOverlay(object: Instance, viewport: Vector2): boolean
	if FULLSCREEN_OVERLAYS[object.Name] then return true end
	if object:IsA("GuiObject") then
		local size = object.AbsoluteSize
		if size.X >= viewport.X * .92 and size.Y >= viewport.Y * .92 then
			return true
		end
	end
	return false
end

local function isFullyFadedLeaf(object: GuiObject): boolean
	if object.BackgroundTransparency < 1 then return false end
	if (object:IsA("TextLabel") or object:IsA("TextButton"))
		and (object :: any).TextTransparency < 1 then return false end
	if (object:IsA("ImageLabel") or object:IsA("ImageButton"))
		and (object :: any).ImageTransparency < 1 then return false end
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if stroke and stroke.Transparency < 1 then return false end
	return true
end

-- Visible = true but every channel at transparency 1 means the element has been
-- FADED OUT, not shown. The Level 2 alert panel lives that way between
-- announcements: permanently Visible, fully transparent when idle. Counting it
-- as a rectangle then would report an overlap nobody can see.
local function isFullyFaded(object: GuiObject): boolean
	if object.BackgroundTransparency < 1 then return false end
	if object:IsA("TextLabel") or object:IsA("TextButton") then
		if (object :: any).TextTransparency < 1 then return false end
	end
	if object:IsA("ImageLabel") or object:IsA("ImageButton") then
		if (object :: any).ImageTransparency < 1 then return false end
	end
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if stroke and stroke.Transparency < 1 then return false end
	-- A container is only faded if everything it draws is faded too.
	for _, child in ipairs(object:GetDescendants()) do
		if child:IsA("GuiObject") and child.Visible and not isFullyFadedLeaf(child) then
			return false
		end
	end
	return true
end

local function visibleChain(object: Instance): boolean
	local node: Instance? = object
	while node and not node:IsA("PlayerGui") do
		if node:IsA("ScreenGui") then
			if not (node :: ScreenGui).Enabled then return false end
		elseif node:IsA("GuiObject") then
			if not (node :: GuiObject).Visible then return false end
		end
		node = node.Parent
	end
	return true
end

-- Collect every visible top-level HUD rectangle, plus every visible string.
-- A control always overlaps the panel it lives in. Comparing the two is not a
-- finding, it is the parent-child relationship, so containment is excluded from
-- every overlap test that names a specific target.
local function contains(outer: string, inner: string): boolean
	if outer == inner then return true end
	if inner:sub(1, #outer + 1) == outer .. "." then return true end
	if outer:sub(1, #inner + 1) == inner .. "." then return true end
	-- The two collectors spell the same panel differently: Scan() walks
	-- ScreenGui children and produces "RoundGui.QueueHostShade.QueueHostPanel",
	-- while Children() keys off the panel itself and produces
	-- "RoundGui.QueueHostPanel.CloseQueue". A control is still inside its panel,
	-- so match on the shared segment rather than on a literal prefix.
	local outerLast = outer:match("([^.]+)$")
	local innerLast = inner:match("([^.]+)$")
	if outerLast and inner:find("." .. outerLast .. ".", 1, true) then return true end
	if innerLast and outer:find("." .. innerLast .. ".", 1, true) then return true end
	return false
end

-- Everything that can be wrong with a required touch target, in one place.
-- `geometry` is false under the viewport override, where AbsolutePosition is
-- measured against the REAL window rather than the simulated screen and every
-- position-based comparison would be meaningless. Size is unaffected: a 44px
-- offset is 44 real pixels whatever the viewport claims to be.
local function touchTargetProblems(rect, rects, viewport, geometry: boolean): {string}
	local problems = {}
	if rect.Interactive ~= true then
		table.insert(problems, "not an interactive control")
	end
	if rect.Active ~= true then
		table.insert(problems, "not active, so it cannot be tapped")
	end
	local width = rect.Right - rect.Left
	local height = rect.Bottom - rect.Top
	if width < 44 or height < 44 then
		table.insert(problems, string.format("%.0fx%.0f, under 44x44", width, height))
	end
	if geometry then
		if rect.Left < -1 or rect.Top < -1
			or rect.Right > viewport.X + 1 or rect.Bottom > viewport.Y + 1 then
			table.insert(problems, string.format(
				"off screen at (%.0f,%.0f)-(%.0f,%.0f) in %.0fx%.0f",
				rect.Left, rect.Top, rect.Right, rect.Bottom, viewport.X, viewport.Y))
		end
		for _, other in ipairs(rects) do
			if not other.Overlay and not contains(other.Path, rect.Path)
				and rect.Left < other.Right and rect.Right > other.Left
				and rect.Top < other.Bottom and rect.Bottom > other.Top then
				table.insert(problems, "overlaps " .. other.Path)
				break
			end
		end
	end
	return problems
end

function UIRegression.Scan(): {[string]: any}
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local layout = UIDevice.Layout()
	local viewport = layout.Viewport

	-- A frame with a fully transparent background and no stroke is a LAYOUT
	-- GROUP, not something the player can see. Measuring it as a rectangle makes
	-- every full-bleed container "overlap" the whole HUD, which says nothing.
	-- Descend through it and measure what actually renders.
	-- A FULL-BLEED transparent frame is a layout group: it exists only to hold
	-- the real panel somewhere inside itself, and measuring it as a rectangle
	-- makes it "overlap" the entire HUD while saying nothing. Descend into it.
	--
	-- A SMALL transparent frame is a composed widget -- the flashlight torch is a
	-- transparent box holding a body and three rays -- and its parts are meant to
	-- overlap each other. Those stay one rectangle.

local function isLayoutGroup(object: GuiObject): boolean
		if object:IsA("TextButton") or object:IsA("ImageButton") then return false end
		if object:IsA("TextLabel") and (object :: TextLabel).TextTransparency < 1 then return false end
		if object:IsA("ImageLabel") and (object :: ImageLabel).ImageTransparency < 1 then return false end
		if object.BackgroundTransparency < 1 then return false end
		local stroke = object:FindFirstChildOfClass("UIStroke")
		if stroke and stroke.Transparency < 1 then return false end
		local size = object.AbsoluteSize
		return size.X >= viewport.X * .7 and size.Y >= viewport.Y * .7
	end

	local rects, texts = {}, {}
	for _, screenGui in ipairs(playerGui:GetChildren()) do
		if screenGui:IsA("ScreenGui") and screenGui.Enabled
			and not ENGINE_GUIS[screenGui.Name] then
			-- An IgnoreGuiInset ScreenGui legitimately starts above y = 0.
			-- The gui's own top edge, measured. In the one space a gui that
			-- ignores the insets legitimately starts above y = 0.
			local topBound = (screenGui :: ScreenGui).AbsolutePosition.Y
			local function collect(container: Instance, prefix: string, depth: number,
				inheritedControl: boolean)
				for _, child in ipairs(container:GetChildren()) do
					if child:IsA("GuiObject") and child.Visible and visibleChain(child)
						and not isFullyFaded(child) then
						local position = child.AbsolutePosition
						local size = child.AbsoluteSize
						local isControl = inheritedControl or MOVEMENT_CONTROLS[child.Name] == true
						if isLayoutGroup(child) and depth < 2 then
							collect(child, prefix .. "." .. child.Name, depth + 1, isControl)
						elseif size.X > 1 and size.Y > 1 then
							table.insert(rects, {
								Path = prefix .. "." .. child.Name,
								Name = child.Name,
								Gui = screenGui.Name,
								TopBound = topBound,
								Overlay = isOverlay(child, viewport),
								MovementControl = isControl,
								Interactive = child:IsA("TextButton") or child:IsA("ImageButton"),
								Active = (child:IsA("TextButton") or child:IsA("ImageButton"))
									and (child :: any).Active or false,
								TextBounds = (child:IsA("TextLabel") or child:IsA("TextButton"))
									and (child :: any).TextBounds or nil,
								Left = position.X,
								Top = position.Y,
								Right = position.X + size.X,
								Bottom = position.Y + size.Y,
							})
						end
					end
				end
			end
			collect(screenGui, screenGui.Name, 0, false)
			for _, descendant in ipairs(screenGui:GetDescendants()) do
				if (descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox"))
					and (descendant :: any).Visible and visibleChain(descendant) then
					local text = (descendant :: any).Text
					if type(text) == "string" and text ~= "" then
						table.insert(texts, {
							Path = screenGui.Name .. "." .. descendant.Name,
							Text = text,
						})
					end
				end
			end
		end
	end

	return {
		Viewport = viewport,
		IsTouch = layout.IsTouch,
		Class = layout.Class,
		Portrait = layout.Portrait,
		Zones = layout.Zones,
		Rects = rects,
		Texts = texts,
	}
end

-- Flatten a panel to the rectangles it actually DRAWS. Transparent containers
-- (the BriefingControls row, any UIListLayout wrapper) are descended through, so
-- what comes back is MUTE and STOP themselves rather than the invisible box that
-- holds them -- which is the level the overlap question is really asked at.
local function collectDrawnChildren(container: Instance, prefix: string,
	viewport: Vector2, out: {any})
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible and not isFullyFaded(child) then
			local path = prefix .. "." .. child.Name
			local size = child.AbsoluteSize
			local position = child.AbsolutePosition
			-- A ScrollingFrame is one rectangle, never a container to descend
			-- into: its contents are MEANT to run past its bounds, which is the
			-- whole point of scrolling, and measuring them would report the
			-- scroll extent as a layout escape.
			local drawsItself = child:IsA("TextButton") or child:IsA("ImageButton")
				or child:IsA("ScrollingFrame")
				or child.BackgroundTransparency < 1
				or ((child:IsA("TextLabel") or child:IsA("TextBox"))
					and (child :: any).TextTransparency < 1)
				or (child:IsA("ImageLabel") and (child :: any).ImageTransparency < 1)
			local stroke = child:FindFirstChildOfClass("UIStroke")
			if stroke and stroke.Transparency < 1 then drawsItself = true end
			if not drawsItself then
				collectDrawnChildren(child, path, viewport, out)
			elseif size.X > 1 and size.Y > 1 and not isOverlay(child, viewport) then
				table.insert(out, {
					Path = path,
					Name = child.Name,
					Interactive = child:IsA("TextButton") or child:IsA("ImageButton"),
					Active = (child:IsA("TextButton") or child:IsA("ImageButton"))
						and (child :: any).Active or false,
					TextBounds = (child:IsA("TextLabel") or child:IsA("TextButton"))
						and (child :: any).TextBounds or nil,
					Left = position.X,
					Top = position.Y,
					Right = position.X + size.X,
					Bottom = position.Y + size.Y,
				})
			end
		end
	end
end

-- Every measured child rectangle inside the panels named above, for the panels
-- that are actually on screen right now.
function UIRegression.Children(): {any}
	local player = Players.LocalPlayer
	local gui = player:WaitForChild("PlayerGui")
	local viewport = UIDevice.Layout().Viewport
	local groups = {}
	for _, screenGui in ipairs(gui:GetChildren()) do
		if screenGui:IsA("ScreenGui") and screenGui.Enabled
			and not ENGINE_GUIS[screenGui.Name] then
			for _, descendant in ipairs(screenGui:GetDescendants()) do
				if descendant:IsA("GuiObject") and INTERNAL_PANELS[descendant.Name]
					and descendant.Visible and visibleChain(descendant) then
					local children = {}
					collectDrawnChildren(descendant, screenGui.Name .. "." .. descendant.Name,
						viewport, children)
					local position = descendant.AbsolutePosition
					local size = descendant.AbsoluteSize
					table.insert(groups, {
						Path = screenGui.Name .. "." .. descendant.Name,
						Left = position.X,
						Top = position.Y,
						Right = position.X + size.X,
						Bottom = position.Y + size.Y,
						Children = children,
					})
				end
			end
		end
	end
	return groups
end

local function rectsOverlap(a: any, b: any): boolean
	-- A one-pixel shared edge is abutment, not overlap.
	return a.Left < b.Right - 1 and a.Right > b.Left + 1
		and a.Top < b.Bottom - 1 and a.Bottom > b.Top + 1
end

function UIRegression.Check(): {[string]: any}
	local scan = UIRegression.Scan()
	local viewport = scan.Viewport
	local offscreen, overlaps, zoneHits, bindings = {}, {}, {}, {}
	local internal = {}
	local groups = UIRegression.Children()

	for _, rect in ipairs(scan.Rects) do
		if rect.Left < -1 or rect.Top < (rect.TopBound or 0) - 1
			or rect.Right > viewport.X + 1 or rect.Bottom > viewport.Y + 1 then
			table.insert(offscreen, string.format(
				"%s at (%.0f,%.0f)-(%.0f,%.0f) in a %.0fx%.0f viewport",
				rect.Path, rect.Left, rect.Top, rect.Right, rect.Bottom, viewport.X, viewport.Y))
		end
	end

	for indexA = 1, #scan.Rects do
		local a = scan.Rects[indexA]
		if not a.Overlay then
			for indexB = indexA + 1, #scan.Rects do
				local b = scan.Rects[indexB]
				if not b.Overlay and rectsOverlap(a, b) then
					table.insert(overlaps, string.format("%s overlaps %s", a.Path, b.Path))
				end
			end
			if scan.IsTouch and not a.MovementControl then
				local zone = UIDevice.OverlapsMovementZone(a.Left, a.Top, a.Right, a.Bottom)
				if zone then
					table.insert(zoneHits, string.format(
						"%s (%.0f,%.0f)-(%.0f,%.0f) sits in the %s movement zone",
						a.Path, a.Left, a.Top, a.Right, a.Bottom, zone))
				end
			end
		end
	end

	if UIDevice.SuppressesKeyboardGlyphs() then
		for _, entry in ipairs(scan.Texts) do
			for _, pattern in ipairs(KEYBOARD_PATTERNS) do
				if entry.Text:match(pattern) then
					table.insert(bindings, string.format(
						"%s shows a keyboard binding: %q", entry.Path, entry.Text))
					break
				end
			end
		end
	end

	for _, group in ipairs(groups) do
		for indexA = 1, #group.Children do
			local a = group.Children[indexA]
			for indexB = indexA + 1, #group.Children do
				local b = group.Children[indexB]
				if rectsOverlap(a, b) then
					table.insert(internal, string.format(
						"%s (%.0f,%.0f)-(%.0f,%.0f) overlaps %s (%.0f,%.0f)-(%.0f,%.0f)",
						a.Path, a.Left, a.Top, a.Right, a.Bottom,
						b.Path, b.Left, b.Top, b.Right, b.Bottom))
				end
			end
			-- A child that has escaped its own panel is the same defect seen from
			-- the other side: the layout reserved less space than it used.
			if a.Left < group.Left - 1 or a.Right > group.Right + 1
				or a.Top < group.Top - 1 or a.Bottom > group.Bottom + 1 then
				table.insert(internal, string.format(
					"%s (%.0f,%.0f)-(%.0f,%.0f) is outside %s (%.0f,%.0f)-(%.0f,%.0f)",
					a.Path, a.Left, a.Top, a.Right, a.Bottom,
					group.Path, group.Left, group.Top, group.Right, group.Bottom))
			end
		end
	end

	return {
		Viewport = viewport,
		Class = scan.Class,
		Portrait = scan.Portrait,
		IsTouch = scan.IsTouch,
		RectCount = #scan.Rects,
		TextCount = #scan.Texts,
		Offscreen = offscreen,
		Overlaps = overlaps,
		MovementZoneHits = zoneHits,
		KeyboardBindings = bindings,
		InternalOverlaps = internal,
		Rects = scan.Rects,
		Groups = groups,
		Passed = #offscreen == 0 and #overlaps == 0
			and #zoneHits == 0 and #bindings == 0 and #internal == 0,
	}
end

function UIRegression.Assert()
	local result = UIRegression.Check()
	local problems = {}
	for _, list in ipairs({result.Offscreen, result.Overlaps,
		result.MovementZoneHits, result.KeyboardBindings, result.InternalOverlaps}) do
		for _, problem in ipairs(list) do table.insert(problems, problem) end
	end
	assert(#problems == 0, string.format(
		"UI regression failed at %.0fx%.0f (%s):\n  %s",
		result.Viewport.X, result.Viewport.Y, result.Class,
		table.concat(problems, "\n  ")))
	return result
end

-- One-line summary suitable for a console log or an MCP probe return.
function UIRegression.Summary(): string
	local result = UIRegression.Check()
	local lines = {string.format("%.0fx%.0f  class=%s  touch=%s  rects=%d  texts=%d  %s",
		result.Viewport.X, result.Viewport.Y, result.Class, tostring(result.IsTouch),
		result.RectCount, result.TextCount, result.Passed and "PASS" or "FAIL")}
	for _, label in ipairs({"Offscreen", "Overlaps", "MovementZoneHits",
		"KeyboardBindings", "InternalOverlaps"}) do
		for _, problem in ipairs(result[label]) do
			table.insert(lines, "  " .. label .. ": " .. problem)
		end
	end
	-- The measured child rectangles are printed whether or not they passed. An
	-- assertion that only speaks up when it fails cannot be reviewed.
	for _, group in ipairs(result.Groups) do
		table.insert(lines, string.format("  %s (%.0f,%.0f)-(%.0f,%.0f)",
			group.Path, group.Left, group.Top, group.Right, group.Bottom))
		for _, child in ipairs(group.Children) do
			table.insert(lines, string.format("      %s (%.0f,%.0f)-(%.0f,%.0f)%s",
				child.Path, child.Left, child.Top, child.Right, child.Bottom,
				child.Interactive and "  [tappable]" or ""))
		end
	end
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Scenario matrix
-- ---------------------------------------------------------------------------

-- The HUD states the regression matrix has to cover. Panels are forced visible
-- directly rather than reached through gameplay: this is a LAYOUT test, so the
-- question is "where would this rectangle land", not "can the game get here".
local function playerGui(): Instance
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local OPTIONAL_GUIS = {
	"PuzzleGui", "Level2ObjectiveGui", "Level2AlertGui", "Level3ReaderGui",
	"Level3TableHideUI", "SpectateGui", "LevelOneGuideGui",
}

local function findGui(name: string): Instance?
	return playerGui():FindFirstChild(name)
end

-- `inRound` hides the lobby-only Zyntra shop button. ZyntraStore shows it with
-- `openButton.Visible = not inRound or touchDevInLevel`, so it and the in-round
-- objectives HUD can never be on screen together -- and forcing both visible
-- reports a collision between two things a player will never see at once, which
-- is a false failure rather than a finding.
local function resetScenario(inRound: boolean?)
	local player = Players.LocalPlayer
	player:SetAttribute("UIRegressionForceLevel3Reader", nil)
	player:SetAttribute("UIRegressionForceReaderHidden", nil)
	player:SetAttribute("UIRegressionForceDispatchActive", nil)
	player:SetAttribute("UIRegressionForceHiding", nil)
	-- Same reason as DevRoundEnding below: the PARTY DOWN card stays up for its
	-- whole fifteen seconds, which is long enough to cover several rows, so the
	-- seam is cleared HERE rather than only in the row that raises it.
	player:SetAttribute("DevPartyDown", nil)
	-- RoundUI owns the result card state. Drive its Studio-only hide hook so a
	-- preceding win/loss scenario cannot leak into the next matrix row.
	player:SetAttribute("DevRoundEnding", "hide")
	-- End any live Command Center transmission first. It re-shows the subtitle
	-- panel on every cue, so hiding the panel and scanning 0.3s later is a race
	-- the harness loses -- and losing it reports a collision with a panel the
	-- scenario never asked for. RoundUI honours this in Studio only.
	-- C_NEVER_SILENCE_A_REAL_BRIEFING_20260831 -- WHAT SHIPPED BROKEN.
	--
	-- This ended whatever transmission was playing, unconditionally, so a player
	-- (or a reviewer watching the place) lost the middle of a real Command Center
	-- briefing because a matrix wanted a clean screen. A harness may reset what
	-- the harness raised; it may not reach into the running game and stop it.
	--
	-- A briefing the harness forced up carries UIRegressionForceDispatchActive
	-- and is ours to end. Anything else is the game's, and the lanes that need a
	-- quiet screen wait for it through Fit.awaitQuietDispatch instead of taking
	-- it. The silence flag is still cleared afterwards either way, so a previous
	-- run's flag can never persist.
	if not Fit.realDispatchLive() then
		player:SetAttribute("UIRegressionSilenceDispatch", true)
	end
	-- RoundUI's stop hook runs in its own signal thread and, while clearing the
	-- dispatch authority, legitimately asks objective scripts to restore their
	-- ScreenGuis. Wait for that causal cleanup BEFORE disabling/hiding the test
	-- matrix; otherwise its late restore leaks the preceding scenario forward.
	task.wait(.05)
	player:SetAttribute("DevRoundEnding", nil)
	-- The lobby queue lives inside RoundGui, which is never disabled, so nothing
	-- else here puts it away. Leaving it up leaked it into every scenario that
	-- ran after the queue row.
	local roundGui = findGui("RoundGui")
	local shade = roundGui and roundGui:FindFirstChild("QueueHostShade")
	if shade then shade.Visible = false end
	for _, name in ipairs(OPTIONAL_GUIS) do
		local screen = findGui(name)
		if screen then
			(screen :: ScreenGui).Enabled = false
			for _, child in ipairs(screen:GetChildren()) do
				if child:IsA("GuiObject") then child.Visible = false end
			end
		end
	end
	player:SetAttribute("Level3_Hiding", nil)
	player:SetAttribute("Spectating", nil)
	-- The harness's `inRound` flag only ever changed the Zyntra open button; it
	-- never told the CLIENT a round was running. So every control gated on
	-- NoiseReporter's controlsAvailable() -- JUMP, SNEAK, the glowstick drop --
	-- was invisible in every scenario, and a matrix that never saw them could
	-- never report them too small or overlapping. Cleared here so a scenario
	-- that does set it cannot leak the round into the next row.
	player:SetAttribute("InRound", nil)
	player:SetAttribute("Level2AlertOwnsBand", nil)
	player:SetAttribute("ZyntraStoreOpen", nil)
	local store = findGui("ZyntraStore")
	local terminal = store and store:FindFirstChild("Terminal")
	-- Close through the production path where it exists: writing Visible = false
	-- directly leaves ZyntraStoreOpen, the movement suppression and the opener's
	-- own state out of step with the pixels, which is the disagreement a later
	-- row would then measure.
	local storeProbe = store and store:FindFirstChild("UIRegressionZyntraStoreProbe")
	if storeProbe and storeProbe:IsA("BindableFunction") then
		pcall(function() storeProbe:Invoke("close") end)
	elseif terminal and terminal:IsA("GuiObject") then
		terminal.Visible = false
	end
	local openButton = store and store:FindFirstChild("ZyntraOpenButton")
	if openButton and openButton:IsA("GuiObject") then
		-- LAST, and after a yield. Clearing InRound above makes ZyntraStore's own
		-- attribute handler re-run and re-show this button, and attribute signals
		-- are deferred -- so writing Visible before that handler ran left the
		-- scenario's intent losing a race it did not know it was in. Yield once so
		-- the handler goes first and this write is the last word.
		task.wait()
		openButton.Visible = not inRound
	end
end

local function revealGui(name: string, filter: ((Instance) -> boolean)?)
	local screen = findGui(name)
	if not screen then return end
	(screen :: ScreenGui).Enabled = true
	for _, child in ipairs(screen:GetChildren()) do
		if child:IsA("GuiObject") then
			child.Visible = filter == nil or filter(child)
		end
	end
end

local LONG_DISPATCH_CUE = "Keep moving through the flooded service halls. The water is above your knees, so listen for every heavy step and follow the green exit lights."

local function setLongDispatchCue()
	task.wait(.05)
	local guide = findGui("LevelOneGuideGui")
	local subtitle = guide and guide:FindFirstChild("Subtitle", true)
	if subtitle and subtitle:IsA("TextLabel") then subtitle.Text = LONG_DISPATCH_CUE end
	-- The panel is sized for the copy, so changing the copy has to re-run the
	-- layout. Through the production function, via its Studio seam.
	local relayout = guide and guide:FindFirstChild("UIRegressionRelayoutGuide")
	if relayout and relayout:IsA("BindableFunction") then
		pcall(function() relayout:Invoke() end)
	end
	task.wait(.05)
end

-- NOT LOCKED, AND CORRECTLY SO -- but say why, because it is the one public
-- entry point in this file that is next door to a mutating lane and is not
-- guarded. Scenarios() only BUILDS descriptors; it writes nothing. The mutation
-- lives in the Setup closures it hands back, and those run under whatever lock
-- their caller holds -- RunAll's, in the only place the suite drives them.
--
-- Taking the harness lock here would be theatre: the caller keeps the closures
-- and can fire them minutes later, long after any lock this function took had
-- been released, so the lock would protect the table build and nothing that
-- matters. Calling a Setup by hand outside a lane genuinely does bypass the
-- lock, and there is no way to close that from here; it is a hand-held debug
-- affordance, and it is written down rather than pretended away.
function UIRegression.Scenarios(): {any}
	local player = Players.LocalPlayer
	return {
		{Name = "gameplay", Setup = resetScenario},
		{Name = "briefing", Requires = {
			"CommandSubtitles", "DispatchMuteButton", "DispatchStopButton",
		}, TouchTargets = {"DispatchMuteButton", "DispatchStopButton"},
			TextFitTargets = {"CommandSubtitles.Subtitle"}, Setup = function()
			resetScenario(true)
			local guide = findGui("LevelOneGuideGui")
			if guide then (guide :: ScreenGui).Enabled = true end
			player:SetAttribute("UIRegressionForceDispatchActive", true)
			setLongDispatchCue()
		end},
		{Name = "briefing-plus-level1-hud", Requires = {
			"CommandSubtitles", "DispatchMuteButton", "DispatchStopButton",
		}, TouchTargets = {"DispatchMuteButton", "DispatchStopButton"},
			Forbids = {"Level1Objectives", "ExitEnergyDetector"}, Setup = function()
			resetScenario(true)
			revealGui("PuzzleGui")
			local guide = findGui("LevelOneGuideGui")
			if guide then (guide :: ScreenGui).Enabled = true end
			player:SetAttribute("UIRegressionForceDispatchActive", true)
		end},
		{Name = "briefing-plus-level2-hud", Requires = {
			"CommandSubtitles", "DispatchMuteButton", "DispatchStopButton",
		}, TouchTargets = {"DispatchMuteButton", "DispatchStopButton"},
			Forbids = {"Level2ObjectiveGui", "Level2AlertGui"}, Setup = function()
			resetScenario(true)
			revealGui("Level2ObjectiveGui")
			revealGui("Level2AlertGui")
			local guide = findGui("LevelOneGuideGui")
			if guide then (guide :: ScreenGui).Enabled = true end
			player:SetAttribute("UIRegressionForceDispatchActive", true)
		end},
		-- The button on its own, with the panel closed. This is the state the
		-- OBJECTIVES control actually has to be reachable in, and keeping it as a
		-- separate row is what stops "panel open hides the button" from quietly
		-- removing the button from the matrix altogether.
		{Name = "objectives-button", Requires = "ObjectivesButton",
			TouchTargets = {"ObjectivesButton"}, Setup = function()
			resetScenario(true)
			revealGui("LevelOneGuideGui", function(child)
				return child.Name == "ObjectivesButton"
			end)
		end},
		-- FORBIDS THE QUEUE PANEL, and that is a diagnosis rather than a tidy-up.
		-- Both rect collectors require a visible chain, so a QueueHostPanel
		-- rectangle turning up in THIS row's scan means the queue shade genuinely
		-- was up while it ran -- and the only production route there is the
		-- "queuehost" event GameManager fires the moment the operator's avatar is
		-- the first body in a station's queue zone (and again after every
		-- resetStation). resetScenario hides the shade but leaves RoundUI's
		-- queueStation and the server-side host relation standing, so the game can
		-- raise the modal again mid-sweep. Naming it here reports a recurrence as
		-- STATE LEAK -- what it is -- instead of as a geometry failure on the
		-- objectives panel. Deliberately NOT hidden in resetScenario: the
		-- queue-host-panel row runs the same reset and would then fail VACUOUS,
		-- because revealGui only writes direct children of RoundGui.
		{Name = "objectives-panel", Requires = "ObjectivesPanel",
			Forbids = {"QueueHostPanel"}, Setup = function()
			-- The objectives panel is nearly full-bleed AND Active, so it is the
			-- single most likely thing to swallow the movement controls. It was
			-- not in the original matrix, which is exactly why its touch case
			-- went unnoticed.
			resetScenario(true)
			-- On touch the panel owns the whole safe band and is Active, so RoundUI
			-- stands the button down while it is open -- they are alternatives, not
			-- companions. The matrix models that rather than forcing both visible
			-- and reporting a collision between two things a player cannot see at
			-- once; the button's own placement is covered by the row above.
			local touch = UIDevice.IsTouch()
			revealGui("LevelOneGuideGui", function(child)
				if child.Name == "ObjectivesPanel" then return true end
				return child.Name == "ObjectivesButton" and not touch
			end)
		end, TouchTargets = {"ObjectivesPanel.Close"}},
		-- The lobby queue panel: five interactive controls, all of which a
		-- player has to hit with a thumb, none of which were in this matrix.
		{Name = "queue-host-panel", Requires = "QueueHostPanel",
			TouchTargets = {
				"QueueHostPanel.CloseQueue", "QueueHostPanel.DecreasePlayers",
				"QueueHostPanel.IncreasePlayers", "QueueHostPanel.PrivacyToggle",
				"QueueHostPanel.CreateParty",
			}, Setup = function()
			resetScenario(false)
			revealGui("RoundGui", function(child)
				return child.Name == "QueueHostShade"
			end)
			local shade = findGui("RoundGui")
			shade = shade and shade:FindFirstChild("QueueHostShade")
			if shade then shade.Visible = true end
		end},
		{Name = "level1-objective-receiver", Setup = function()
			resetScenario(true); revealGui("PuzzleGui")
		end},
		-- The in-round touch cluster, measured as a cluster. RUN and JUMP were
		-- already covered by TouchTargetMatrix's own sweep; SNEAK is new and the
		-- crouch it drives is the one the store page advertises, so it is asserted
		-- here as a tappable target like any other.
		{Name = "touch-movement-cluster", TouchOnly = true, Requires = {"TouchSneakHold"},
			TouchTargets = {"TouchSneakHold", "TouchRunHold", "TouchJump"},
			Setup = function()
				resetScenario(true)
				-- These controls are level-only by design, so the scenario has to
				-- actually be in a round for them to exist at all.
				player:SetAttribute("InRound", true)
				task.wait(.1)
			end},
		{Name = "level2-alert-and-objective", Setup = function()
			resetScenario(true); revealGui("Level2AlertGui"); revealGui("Level2ObjectiveGui")
		end},
		-- REPLACES the old level3-reader-open / -closed pair. Both REQUIRED
		-- `ReaderToggle` -- a permanently-visible "CLOSE READER [R]" chip beside
		-- the panel -- and one of them asserted it did not MOVE between the two
		-- states. That control is gone: the panel is now the control that hides
		-- it, and the hidden state carries only a compact restore chip. A test
		-- that still demanded the toggle would have forced it back.
		--
		-- The open state therefore FORBIDS both the toggle and the chip, and the
		-- hidden state forbids the panel. `Capture`/`CompareWith` now pin the
		-- ANCHOR instead of the button: the chip must appear where the panel's
		-- own top-right corner was, so nothing jumps under the finger.
		{Name = "level3-reader-open", Requires = {"ReaderPanel"},
			Forbids = {"ReaderToggle", "ReaderRestore"},
			TouchTargets = {"ReaderPanel"}, Setup = function()
			resetScenario(true)
			player:SetAttribute("UIRegressionForceLevel3Reader", true)
			player:SetAttribute("UIRegressionForceReaderHidden", false)
			revealGui("Level3ReaderGui", function(child)
				return child.Name == "ReaderPanel"
			end)
		end},
		-- The chip exists on TOUCH only: on a pointer device the hidden reader
		-- draws nothing at all and R is the only way back, so requiring the chip
		-- everywhere would demand the dedicated open button the product forbids.
		{Name = "level3-reader-hidden", TouchOnly = true,
			Requires = {"ReaderRestore"},
			Forbids = {"ReaderPanel", "ReaderToggle"},
			TouchTargets = {"ReaderRestore"}, Setup = function()
			resetScenario(true)
			player:SetAttribute("UIRegressionForceLevel3Reader", true)
			player:SetAttribute("UIRegressionForceReaderHidden", true)
			revealGui("Level3ReaderGui", function(child)
				return child.Name == "ReaderRestore"
			end)
		end},
		{Name = "briefing-plus-level3-reader", Requires = {
			"CommandSubtitles", "DispatchMuteButton", "DispatchStopButton",
		}, TouchTargets = {"DispatchMuteButton", "DispatchStopButton"},
			Forbids = {"ReaderPanel", "ReaderRestore"}, Setup = function()
			resetScenario(true)
			player:SetAttribute("UIRegressionForceLevel3Reader", true)
			player:SetAttribute("UIRegressionForceReaderHidden", false)
			local guide = findGui("LevelOneGuideGui")
			if guide then (guide :: ScreenGui).Enabled = true end
			player:SetAttribute("UIRegressionForceDispatchActive", true)
		end},
		{Name = "hiding", Requires = {"HiddenStatus", "LeaveHiding"}, Setup = function()
			resetScenario(true)
			player:SetAttribute("UIRegressionForceHiding", true)
			revealGui("Level3TableHideUI")
		end},
		{Name = "hiding-plus-reader", Requires = {"HiddenStatus", "LeaveHiding"},
			Forbids = {"ReaderPanel", "ReaderRestore"}, Setup = function()
			resetScenario(true)
			player:SetAttribute("UIRegressionForceLevel3Reader", true)
			player:SetAttribute("UIRegressionForceReaderHidden", false)
			player:SetAttribute("UIRegressionForceHiding", true)
			revealGui("Level3TableHideUI")
		end},
		{Name = "spectate", Setup = function()
			resetScenario(true)
			player:SetAttribute("Spectating", true)
			revealGui("SpectateGui")
		end},
		-- WHAT THIS ROW USED TO BE: `resetScenario(); SetAttribute; revealGui` and
		-- nothing else. No Requires, no TouchTargets, no Forbids -- so it passed
		-- for a terminal whose content frame had a negative height, because the
		-- only thing it ever measured was the outer rectangle of a panel the
		-- harness had already been told to treat as a deliberate overlay.
		--
		-- It now opens the terminal through the PRODUCTION toggle, names the
		-- shell rectangles it must be able to measure, requires the tap targets
		-- the header carries, and forbids the opener -- which is what proves the
		-- button standing behind its own modal has really gone. The full
		-- per-device sweep is ZyntraTerminalFitMatrix; this row is what makes the
		-- state part of the ordinary scenario matrix as well.
		{Name = "store-modal", Requires = {
			"Terminal", "TerminalHeader", "TerminalTabs", "TerminalContent",
			"TerminalStatus",
		}, Forbids = {"ZyntraOpenButton"},
			TouchTargets = {"TerminalHeader.CloseTerminal"}, Setup = function()
			resetScenario()
			local store = findGui("ZyntraStore")
			local probe = store and store:FindFirstChild("UIRegressionZyntraStoreProbe")
			if probe and probe:IsA("BindableFunction") then
				probe:Invoke("open")
				probe:Invoke("relayout")
			else
				-- No probe means no Studio seam, which is a failure to report and
				-- not a row to skip: Requires will catch the missing rectangles.
				revealGui("ZyntraStore")
			end
			task.wait(.15)
		end},
		-- The DEV page, which is the one the owner reported as unusable and the
		-- one no row has ever opened. On an account that is not whitelisted the
		-- page does not exist, so the row asks only for the shell -- the tab
		-- sweep in ZyntraTerminalFitMatrix reads the live tab list and cannot be
		-- fooled either way.
		{Name = "store-modal-dev", Requires = {"Terminal", "TerminalContent"},
			Setup = function()
			resetScenario()
			local store = findGui("ZyntraStore")
			local probe = store and store:FindFirstChild("UIRegressionZyntraStoreProbe")
			if probe and probe:IsA("BindableFunction") then
				probe:Invoke("open")
				probe:Invoke("tab:Dev")
				probe:Invoke("relayout")
			end
			task.wait(.15)
		end},
		-- The result overlay is full-bleed for EVERY outcome. Levels 1 and 2 show
		-- exactly two actions; the last level shows one and must not offer a route
		-- to a level that does not exist; a wipe shows none.
		{Name = "round-win-fullscreen", Requires = {
			"RoundEnding", "EndingTitle", "EndingStats", "EndingHint",
			"ContinueRun", "ReturnToLobby",
		}, TouchTargets = {"ContinueRun", "ReturnToLobby"},
			TextFitTargets = {"ContinueRun", "ReturnToLobby"},
			RoundEndingMode = "fullscreen", Setup = function()
			resetScenario(true)
			player:SetAttribute("DevRoundEnding", "win")
		end},
		{Name = "round-win-final-level", Requires = {
			"RoundEnding", "EndingTitle", "EndingStats", "EndingHint", "ReturnToLobby",
		}, Forbids = {"ContinueRun"}, TouchTargets = {"ReturnToLobby"},
			TextFitTargets = {"ReturnToLobby"},
			RoundEndingMode = "fullscreen", Setup = function()
			resetScenario(true)
			player:SetAttribute("DevRoundEnding", "winfinal")
		end},
		{Name = "round-loss-fullscreen", Requires = {
			"RoundEnding", "EndingTitle", "EndingStats", "EndingHint",
		}, Forbids = {"ContinueRun", "ReturnToLobby"},
			RoundEndingMode = "fullscreen", Setup = function()
			resetScenario(true)
			player:SetAttribute("DevRoundEnding", "lose")
		end},
		-- The 15-second wipe window. The card is RoundUI's own, driven through
		-- the same kind of Studio-only attribute seam the result overlay uses, so
		-- this measures the production card and not a stand-in for it. The
		-- purchase button is deliberately NOT required: it only appears while the
		-- player may actually re-enter, which needs a live round the harness must
		-- not fake, and the decline button is the one every dead player gets.
		{Name = "party-down-card", Requires = {
			"PartyDownCard", "PartyDownTitle", "PartyDownFallen",
			"PartyDownTimer", "PartyDownDecline",
			-- ONE purchase surface. ZyntraStore's own EMERGENCY RE-ENTRY modal
			-- carries the identical action, and the card is the reason it stands
			-- down for the whole window; the two of them stacked is a player
			-- buying twice, which is the most expensive way this can fail. The
			-- GUI is named, not the frame inside it: "EmergencyReentry" is also
			-- the store's own product card, three panels away.
		}, Forbids = {"ZyntraReentryModal"}, TouchTargets = {"PartyDownDecline"},
			-- The countdown is a FIXED TextSize inside a card that shrinks with
			-- the viewport, so it is the label in here that can outgrow its box.
			TextFitTargets = {"PartyDownDecline", "PartyDownTimer"},
			-- The 0.6s arming IS the accidental-purchase guard, and `Active` is
			-- otherwise only ever read on a touch pass -- so on every desktop run
			-- the one thing this card exists to get right went unasserted.
			RequiresActive = {"PartyDownDecline"}, Setup = function()
			-- resetScenario clears DevPartyDown, so this always fires a change.
			resetScenario(true)
			player:SetAttribute("InRound", true)
			player:SetAttribute("DevPartyDown", 15)
			-- Past the 0.6s accidental-purchase arming delay, so the row is
			-- measured in the state a player can actually press.
			task.wait(.7)
		end},
	}
end

-- What the completion overlay OFFERS and where each action goes. The scenario
-- matrix above covers the geometry; this covers behaviour the geometry cannot
-- see: the exact action set per level, the remote message each button is wired
-- to, what the countdown promises, and what a real press actually does. The
-- press runs through RoundUI's own handler, so this is the production routing
-- and not a re-implementation of it.
-- SERIALIZED, AND IT WAS NOT. This lane took no lock at all, and it is among
-- the most invasive in the file: it drives resetScenario, writes DevRoundEnding
-- and presses the completion buttons through RoundUI's own handler. Two callers
-- reaching it at once means one of them is pressing LOSE inside the round the
-- other is measuring a WIN in, and neither report says so.
function Fit.bodyCompletionContract(): (string, number)
	local player = Players.LocalPlayer
	local report = {"=== completion contract ==="}
	local stolen = Fit.takeStolenNote()
	if stolen then table.insert(report, "  note " .. stolen) end
	local failures = 0
	-- (b) AWAIT ITS NATURAL END, BOUNDED. resetScenario writes
	-- UIRegressionSilenceDispatch, which ENDS a real transmission mid-sentence,
	-- and this lane calls it before every drive.
	local quiet, dispatchWhy = Fit.awaitQuietDispatch()
	if not quiet then
		failures += 1
		table.insert(report, "  FAIL " .. tostring(dispatchWhy))
		table.insert(report, string.format("COMPLETION: %d failed", failures))
		return table.concat(report, "\n"), failures
	end
	local function check(ok: boolean, description: string, detail: string?)
		if ok then
			-- Compact keeps findings, not confirmations. See C_COMPACT_REPORT_20260831:
			-- five lanes build their own report table instead of using Fit.recorder,
			-- and every one of them printed a line per passing check -- which is why
			-- a "compact" run still came to 103KB.
			if not Fit.Compact then table.insert(report, "  ok   " .. description) end
		else
			failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. detail .. ")") or ""))
		end
	end

	local function overlay(): Instance?
		local round = findGui("RoundGui")
		return round and round:FindFirstChild("RoundEnding") or nil
	end
	local function action(name: string): TextButton?
		local frame = overlay()
		local child = frame and frame:FindFirstChild(name)
		return (child and child:IsA("TextButton")) and child or nil
	end
	local function hintText(): string
		local frame = overlay()
		local hint = frame and frame:FindFirstChild("EndingHint")
		return (hint and hint:IsA("TextLabel")) and hint.Text or ""
	end
	local function visibleActions(): {string}
		local names = {}
		local frame = overlay()
		for _, child in ipairs(frame and frame:GetChildren() or {}) do
			if child:IsA("TextButton") and child.Visible then
				table.insert(names, child.Name)
			end
		end
		table.sort(names)
		return names
	end
	local function drive(mode: string)
		resetScenario(true)
		player:SetAttribute("DevRoundEnding", mode)
		task.wait(.3)
	end
	local function press(name: string)
		player:SetAttribute("UIRegressionCompletionPress", nil)
		player:SetAttribute("UIRegressionCompletionPress", name)
		task.wait(.15)
	end

	-- (1) Levels 1 and 2: exactly CONTINUE and BACK TO LOBBY.
	drive("win")
	local continueRun, returnLobby = action("ContinueRun"), action("ReturnToLobby")
	check(continueRun ~= nil and returnLobby ~= nil, "win offers both actions")
	check(table.concat(visibleActions(), ",") == "ContinueRun,ReturnToLobby",
		"win offers EXACTLY two actions", table.concat(visibleActions(), ","))
	if continueRun and returnLobby then
		check(continueRun.Text == "CONTINUE", "continue label", continueRun.Text)
		check(returnLobby.Text == "BACK TO LOBBY", "lobby label", returnLobby.Text)
		check(continueRun:GetAttribute("CompletionAction") == "continuenow",
			"continue is wired to continuenow",
			tostring(continueRun:GetAttribute("CompletionAction")))
		check(returnLobby:GetAttribute("CompletionAction") == "returntolobby",
			"lobby is wired to returntolobby",
			tostring(returnLobby:GetAttribute("CompletionAction")))
	end
	check(hintText():find("BEGINS IN", 1, true) ~= nil,
		"win countdown promises the next level", hintText())

	-- (2) Pressing CONTINUE takes the run onward and locks both actions.
	press("ContinueRun")
	continueRun, returnLobby = action("ContinueRun"), action("ReturnToLobby")
	if continueRun and returnLobby then
		check(continueRun.Text == "CONTINUING...", "continue press acknowledges",
			continueRun.Text)
		check(not continueRun.Active and not returnLobby.Active,
			"continue press locks both actions")
	end

	-- (3) Pressing BACK TO LOBBY takes the other route.
	drive("win")
	press("ReturnToLobby")
	returnLobby = action("ReturnToLobby")
	if returnLobby then
		check(returnLobby.Text == "RETURNING...", "lobby press acknowledges",
			returnLobby.Text)
	end

	-- (4) The last level: one action, and no route to a level 4.
	drive("winfinal")
	check(table.concat(visibleActions(), ",") == "ReturnToLobby",
		"final level offers ONLY back to lobby", table.concat(visibleActions(), ","))
	check(hintText():find("LOBBY", 1, true) ~= nil,
		"final countdown returns to the lobby", hintText())
	check(hintText():find("LEVEL 4", 1, true) == nil,
		"final countdown never routes to a level 4", hintText())
	press("ContinueRun")
	returnLobby = action("ReturnToLobby")
	check(returnLobby ~= nil and returnLobby.Text == "BACK TO LOBBY"
		and returnLobby.Active,
		"a hidden continue cannot be pressed on the final level")

	-- (5) A wipe offers nothing to press.
	drive("lose")
	check(#visibleActions() == 0, "a wipe offers no actions",
		table.concat(visibleActions(), ","))

	resetScenario()
	table.insert(report, string.format("COMPLETION: %d failed", failures))
	return table.concat(report, "\n"), failures
end

function UIRegression.CompletionContract(token: string?): (string, number)
	return Fit.lane("CompletionContract", token, Fit.bodyCompletionContract)
end

-- The result overlay's action row across a device matrix.
--
-- The scenario matrix can only measure the viewport Studio is actually
-- rendering, and the Device Simulator has to be set before Play and cannot be
-- driven from Luau, so a single run can never cover phone AND tablet. This
-- drives UIDevice's Studio-only viewport override instead, which makes the
-- real HUD re-measure at each simulated size, then resolves each button's
-- resulting UDim2 against that viewport. It is the production responsive maths
-- under test, not the pixels Studio happens to be drawing.
--
-- The override has to be set on `workspace`, not by replacing UIDevice.Layout:
-- a console/plugin VM gets its OWN module cache, so a table patched there is
-- invisible to the LocalScript being measured.
local FIT_DEVICES = {
	{Name = "desktop 1920x1080", Width = 1920, Height = 1080, Touch = false, Portrait = false, Class = "desktop"},
	{Name = "desktop 1280x720", Width = 1280, Height = 720, Touch = false, Portrait = false, Class = "desktop"},
	{Name = "tablet landscape 1024x768", Width = 1024, Height = 768, Touch = true, Portrait = false, Class = "tablet"},
	{Name = "tablet portrait 768x1024", Width = 768, Height = 1024, Touch = true, Portrait = true, Class = "tablet"},
	{Name = "phone landscape 812x375", Width = 812, Height = 375, Touch = true, Portrait = false, Class = "phone"},
	{Name = "phone landscape 667x375", Width = 667, Height = 375, Touch = true, Portrait = false, Class = "phone"},
	{Name = "phone portrait 390x844", Width = 390, Height = 844, Touch = true, Portrait = true, Class = "phone"},
	{Name = "phone portrait 375x667", Width = 375, Height = 667, Touch = true, Portrait = true, Class = "phone"},
	-- The exact viewport a Galaxy A06 reports in landscape, which is where the
	-- compact queue panel was first found to be too small to use.
	{Name = "phone landscape 705x338", Width = 705, Height = 338, Touch = true, Portrait = false, Class = "phone"},
}

function Fit.bodyCompletionFit(): (string, number)
	local player = Players.LocalPlayer
	local report = {"=== completion fit matrix ==="}
	local stolen = Fit.takeStolenNote()
	if stolen then table.insert(report, "  note " .. stolen) end
	local failures = 0
	-- (b) AWAIT ITS NATURAL END, BOUNDED. Same reason as CompletionContract: this
	-- lane drives resetScenario per device row, and resetScenario silences a live
	-- briefing as its second act.
	local quiet, dispatchWhy = Fit.awaitQuietDispatch()
	if not quiet then
		failures += 1
		table.insert(report, "  FAIL " .. tostring(dispatchWhy))
		table.insert(report, string.format("FIT: %d failed", failures))
		return table.concat(report, "\n"), failures
	end
	local function fail(message)
		failures += 1
		table.insert(report, "  FAIL " .. message)
	end

	local function resolve(button, width, height)
		local size, position = button.Size, button.Position
		local w = size.X.Offset + size.X.Scale * width
		local h = size.Y.Offset + size.Y.Scale * height
		local cx = position.X.Offset + position.X.Scale * width
		local cy = position.Y.Offset + position.Y.Scale * height
		return {
			Name = button.Name,
			Left = cx - w * button.AnchorPoint.X,
			Top = cy - h * button.AnchorPoint.Y,
			Right = cx + w * (1 - button.AnchorPoint.X),
			Bottom = cy + h * (1 - button.AnchorPoint.Y),
			Width = w,
			Height = h,
		}
	end

	local forcedTouch = workspace:GetAttribute("ForceTouchUI")
	local forcedViewport = workspace:GetAttribute("UIRegressionViewport")
	local ok, err = pcall(function()
		for _, mode in ipairs({
			{Label = "levels 1-2", Dev = "win", Expect = 2},
			{Label = "final level", Dev = "winfinal", Expect = 1},
		}) do
			for _, device in ipairs(FIT_DEVICES) do
				-- Simulate the device BEFORE the result screen is shown, so the
				-- first layout it performs is already the one under test.
				workspace:SetAttribute("ForceTouchUI", device.Touch or nil)
				workspace:SetAttribute("UIRegressionViewport",
					Vector2.new(device.Width, device.Height))
				task.wait(.12)
				resetScenario(true)
				player:SetAttribute("DevRoundEnding", mode.Dev)
				task.wait(.25)

				local round = findGui("RoundGui")
				local frame = round and round:FindFirstChild("RoundEnding")
				local rects = {}
				for _, child in ipairs(frame and frame:GetChildren() or {}) do
					if child:IsA("TextButton") and child.Visible then
						table.insert(rects, resolve(child, device.Width, device.Height))
					end
				end
				local hint = frame and frame:FindFirstChild("EndingHint")
				local hintRect = (hint and hint.Visible)
					and resolve(hint, device.Width, device.Height) or nil

				local label = string.format("%s / %s", mode.Label, device.Name)
				if #rects ~= mode.Expect then
					fail(string.format("%s: expected %d action(s), measured %d",
						label, mode.Expect, #rects))
				else
					local problems = {}
					for _, rect in ipairs(rects) do
						if rect.Left < 0 or rect.Top < 0
							or rect.Right > device.Width or rect.Bottom > device.Height then
							table.insert(problems, string.format(
								"%s offscreen (%.0f,%.0f)-(%.0f,%.0f)",
								rect.Name, rect.Left, rect.Top, rect.Right, rect.Bottom))
						end
						if device.Touch and (rect.Width < 44 or rect.Height < 44) then
							table.insert(problems, string.format("%s is %.0fx%.0f, under 44px",
								rect.Name, rect.Width, rect.Height))
						end
					end
					if #rects == 2 then
						local a, b = rects[1], rects[2]
						if a.Left < b.Right and b.Left < a.Right
							and a.Top < b.Bottom and b.Top < a.Bottom then
							table.insert(problems, "the two actions overlap each other")
						end
					end
					-- The countdown sits directly above the actions. A stacked pair on
					-- a portrait phone used to be laid out against the viewport
					-- independently of it and ran 11-19px into it.
					if hintRect then
						for _, rect in ipairs(rects) do
							if rect.Left < hintRect.Right and hintRect.Left < rect.Right
								and rect.Top < hintRect.Bottom and hintRect.Top < rect.Bottom then
								table.insert(problems, string.format(
									"%s overlaps the countdown by %.0fpx",
									rect.Name, hintRect.Bottom - rect.Top))
							end
						end
					end
					if #problems > 0 then
						fail(label .. ": " .. table.concat(problems, "; "))
					else
						local shape = #rects == 2
							and (math.abs(rects[1].Top - rects[2].Top) < 1 and "row" or "stack")
							or "single"
						table.insert(report, string.format("  ok   %-38s %s, %.0fx%.0f each",
							label, shape, rects[1].Width, rects[1].Height))
					end
				end
			end
		end
	end)
	workspace:SetAttribute("UIRegressionViewport", forcedViewport)
	workspace:SetAttribute("ForceTouchUI", forcedTouch)
	task.wait(.12)
	resetScenario()
	if not ok then
		failures += 1
		table.insert(report, "  FAIL fit matrix errored: " .. tostring(err))
	end
	table.insert(report, string.format("FIT: %d failed", failures))
	return table.concat(report, "\n"), failures
end

function UIRegression.CompletionFit(token: string?): (string, number)
	return Fit.lane("CompletionFit", token, Fit.bodyCompletionFit)
end

-- Run every scenario at the CURRENT viewport and return a printable report.
-- Drive the viewport itself from the Studio Device Simulator, before Play.
-- Every ScreenGui the matrix expects to exist. A missing one means its script
-- errored during startup, and without this check the scenario that needed it
-- would simply scan nothing and report PASS -- which is exactly what happened
-- when a bad require took RoundUI down and the briefing test went vacuous.
local REQUIRED_GUIS = {
	"RoundGui", "LevelOneGuideGui", "PuzzleGui", "StaminaGui", "FlashlightPopup",
	"SpectateGui", "ZyntraStore", "Level2AlertGui", "Level2ObjectiveGui",
	"Level3ReaderGui", "Level3TableHideUI",
}

function UIRegression.MissingGuis(): {string}
	local missing = {}
	for _, name in ipairs(REQUIRED_GUIS) do
		if not playerGui():FindFirstChild(name) then
			table.insert(missing, name)
		end
	end
	return missing
end

-- ---------------------------------------------------------------------------
-- Responsive-layout matrices (C_*_20260830)
-- ---------------------------------------------------------------------------

-- What each terminal page MUST hold, stated independently of the terminal. The
-- counts come from the authored design -- two upgrade cards, the six Zyntra
-- products, the donation tiers in ZyntraConfig, two colour pickers, and the
-- developer control list -- so a page that renders nothing fails rather than
-- passing for want of anything to check.
local ZyntraConfig = require(ReplicatedStorage:WaitForChild("ZyntraConfig"))
local function donationTierCount(): number
	local count = 0
	for _ in pairs(ZyntraConfig.Donations or {}) do count += 1 end
	return count
end

local PAGE_CONTENT = {
	Upgrades = {Rows = 2, Actions = 2},
	Shop = {Rows = 6, Actions = 6},
	-- Derived from the production config below, not guessed. `Rows = 1` was
	-- vacuous: a Donate page that had built one card out of six would have
	-- passed.
	Donate = {Rows = 0, Actions = 0},
	Colors = {Rows = 2, Actions = 8},
	-- The accessibility page, and this literal is the LAST RESORT rather than the
	-- contract. Like Donate, the real count is derived from ZyntraConfig at the
	-- point of use (the visible entries of AccessibilitySettings); 2 is what the
	-- store's emergency two-key fallback draws, so it only stands when the config
	-- carries no list at all. A Settings page that built nothing fails here.
	Settings = {Rows = 2, Actions = 2},
	Dev = {Rows = 7, Actions = 7},
}

-- Every helper the three matrices below share lives on ONE file-level local.
-- Not a style choice: this module already carries a large number of names at
-- chunk scope and Luau caps that at 200, so fourteen more would have cost the
-- file its ability to compile.

-- GetTextBoundsAsync is the ONE way to ask what a string WOULD need at a size
-- and wrap width the client is not currently rendering. Hoisted here from
-- BriefingFitMatrix, which now shares it rather than keeping a second copy.
-- Every call is pcall'ed: a service hiccup must be a failed CHECK, not an
-- unwound sweep that strands the device override.
function Fit.measureText(text, fontFace, size, width)
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = fontFace
	params.Size = size
	if width then params.Width = width end
	local ok, result = pcall(function()
		return TextService:GetTextBoundsAsync(params)
	end)
	if ok and typeof(result) == "Vector2" then return result, nil end
	return nil, tostring(result)
end

-- ---------------------------------------------------------------------------
-- Phone/tablet/desktop device matrix shared by the three 20260830 matrices
-- ---------------------------------------------------------------------------

-- C_FIXTURES_ARE_NOT_DEVICES_20260831 -- WHAT SHIPPED BROKEN. This table was
-- headed "the TRUE safe-area insets each device actually reports", and not one
-- of those numbers was ever read off a device. 59/59/21 and 44/44/21 were
-- written down from what iOS is understood to report, and the viewports are
-- round numbers NEAR a real one rather than a real one: the only landscape
-- viewport anybody in this project has actually measured is 955x439, and the
-- row that called itself "iPhone 16 Pro Max landscape" said 956x440. A row
-- that claims to be a measurement gets trusted like one -- a failure on it
-- reads as "broken on hardware" and a pass as "proven on hardware", and
-- neither was ever true of these.
--
-- They are ADVERSARIAL FIXTURES: shapes the layout has to survive, chosen to
-- be awkward -- the shortest landscape, the narrowest portrait, housing on one
-- side only, a bottom inset with no top one, a housing top that is larger than
-- the topbar and one that is smaller. Their authority is that the layout must
-- not break on them, never that a phone reports them. The one genuinely
-- measured case is `Fit.MeasuredCase` below, and it is the only thing in this
-- file allowed to use the word.
--
-- WHAT EACH ROW STATES, and why every one of them is STATED rather than read:
--   Size    the fixture viewport.
--   Safe    the device HOUSING inset -- notch, island, home indicator. Absent
--           means a rectangular screen; it never means "inherit the host's".
--   Topbar  Roblox's own chrome, which every device has whatever its housing.
--           Stated for the same reason Safe is: measured off the host it is
--           ~36px under a desktop Studio window and 58px under the Device
--           Emulator on a notched phone, so one row would be two different
--           rectangles depending on where the suite was run, and no matrix
--           could state what it must produce. Written to the Studio-only
--           workspace attribute UIRegressionTopbarInset by Fit.apply.
--           Both insets are {left, top, right, bottom} PLAIN NUMBERS. They
--           become a Rect only inside Fit.apply, because a Rect clamps its Max
--           components up to its Min ones and a row has to be able to say
--           "58 at the top and nothing at the bottom" without the constructor
--           quietly disagreeing. Fit.fixtureProblems reads the attribute back
--           and holds it to these numbers.
--   Frames  the rectangle a ScreenGui of each Enum.ScreenInsets value must
--           occupy, as {Left, Top, Right, Bottom} RELATIVE TO THE FIXTURE
--           DISPLAY'S TOP-LEFT. With the viewport, the housing and the topbar
--           all fixed, these are fully determined -- so they are written down
--           as literals rather than recomputed from UIDevice.Layout(), which
--           is the subject under test and therefore cannot also be the oracle.
--           The four, defined independently of any code in UIDevice:
--             None              the whole panel.
--             DeviceSafeInsets  the panel less the HOUSING alone.
--             CoreUISafeInsets  the panel less housing AND topbar, combined by
--                               taking the larger edge by edge -- NOT by
--                               adding them, which would apply a housing the
--                               engine has already applied a second time.
--             TopbarSafeInsets  the strip the topbar occupies: the core-safe
--                               width, running from the device-safe top down
--                               to the core-safe top. A real device also
--                               reserves a run at the left of that strip for
--                               Roblox's own buttons (226px into the display
--                               on the one device we measured); nothing states
--                               that width to a fixture and nothing in this
--                               game positions against it, so the fixture
--                               model does not pretend to reproduce it.
--
-- Only the display ORIGIN is host-dependent, and deliberately so: the fixture
-- is anchored so its SAFE corner lands on the engine's real safe corner, which
-- is what makes an analytic rectangle and a live AbsolutePosition comparable
-- numbers. Fit.fixtureProblems checks that anchoring on its own, against
-- GuiService rather than against UIDevice.
Fit.Devices = {
	-- HOUSING ON ONE SIDE ONLY. A landscape phone's safe area is asymmetric --
	-- the island sits on whichever side the player rotated it to -- and every
	-- row here used to be left-right symmetric, so a model that swapped its left
	-- and right insets produced byte-identical numbers and nothing in the suite
	-- could see it. This row is the one that can. It is the RIGHT side rather
	-- than the left for a transport reason and not an aesthetic one: these four
	-- numbers reach UIDevice as a Rect, whose Max components clamp up to its Min
	-- ones, so a right inset smaller than the left one is a shape the attribute
	-- may be unable to carry. Fit.fixtureProblems checks that either way.
	{Name = "adversarial 956x440 landscape, housing on the right",
		Size = Vector2.new(956, 440),
		Touch = true, Class = "phone", Portrait = false,
		Safe = {0, 0, 59, 21}, Topbar = {0, 58, 0, 0},
		Frames = {
			None = {0, 0, 956, 440}, DeviceSafeInsets = {0, 0, 897, 419},
			CoreUISafeInsets = {0, 58, 897, 419}, TopbarSafeInsets = {0, 0, 897, 58},
		}},
	-- A HOUSING TOP AND A TOPBAR ON THE SAME EDGE, with the topbar the larger
	-- of the two. Combining them by ADDING gives 82 where taking the larger
	-- gives 58, so this row is what separates "the topbar and the housing are
	-- one inset" from "the housing is applied twice".
	{Name = "adversarial 440x956 portrait, status bar and indicator",
		Size = Vector2.new(440, 956),
		Touch = true, Class = "phone", Portrait = true,
		Safe = {0, 24, 0, 34}, Topbar = {0, 58, 0, 0},
		-- THE HOUSING AND THE TOPBAR NEST, they do not compete. This row is the
		-- only one that states a housing top AND a topbar top, and its literals
		-- were first written with max(24, 58) = 58 -- which is the arithmetic the
		-- layout used before C_FIXTURE_INSETS_NEST_20260831 and which the measured
		-- device cannot distinguish, because every real edge has a zero on one
		-- side (a landscape cutout is left/right, the topbar is top). Here they
		-- overlap, and the answer is 24 + 58 = 82: the topbar sits INSIDE the
		-- device-safe rect, under the status bar, not on top of it. That makes
		-- this row the one that catches a regression back to max().
		Frames = {
			None = {0, 0, 440, 956}, DeviceSafeInsets = {0, 24, 440, 922},
			CoreUISafeInsets = {0, 82, 440, 922}, TopbarSafeInsets = {0, 24, 440, 82},
		}},
	-- The four rectangular rows below state a 36px topbar and no housing at
	-- all. They are not "a device with no notch": they are the shape a layout
	-- must survive when the only thing eating the screen is Roblox's own bar,
	-- and -- run on a Device Emulator host, where the measured topbar is 58 --
	-- they are also what proves the topbar is taken from the row and not from
	-- the machine.
	{Name = "adversarial 705x338 landscape, no housing",
		Size = Vector2.new(705, 338),
		Touch = true, Class = "phone", Portrait = false,
		Topbar = {0, 36, 0, 0},
		Frames = {
			None = {0, 0, 705, 338}, DeviceSafeInsets = {0, 0, 705, 338},
			CoreUISafeInsets = {0, 36, 705, 338}, TopbarSafeInsets = {0, 0, 705, 36},
		}},
	{Name = "adversarial 568x320 landscape, no housing",
		Size = Vector2.new(568, 320),
		Touch = true, Class = "phone", Portrait = false,
		Topbar = {0, 36, 0, 0},
		Frames = {
			None = {0, 0, 568, 320}, DeviceSafeInsets = {0, 0, 568, 320},
			CoreUISafeInsets = {0, 36, 568, 320}, TopbarSafeInsets = {0, 0, 568, 36},
		}},
	-- Symmetric housing, deliberately kept alongside the one-sided row: a model
	-- that dropped the housing entirely passes the one-sided row's right edge
	-- and fails here on both.
	{Name = "adversarial 667x375 landscape, symmetric housing",
		Size = Vector2.new(667, 375),
		Touch = true, Class = "phone", Portrait = false,
		Safe = {44, 0, 44, 21}, Topbar = {0, 36, 0, 0},
		Frames = {
			None = {0, 0, 667, 375}, DeviceSafeInsets = {44, 0, 623, 354},
			CoreUISafeInsets = {44, 36, 623, 354}, TopbarSafeInsets = {44, 0, 623, 36},
		}},
	{Name = "adversarial 375x667 portrait, no housing",
		Size = Vector2.new(375, 667),
		Touch = true, Class = "phone", Portrait = true,
		Topbar = {0, 36, 0, 0},
		Frames = {
			None = {0, 0, 375, 667}, DeviceSafeInsets = {0, 0, 375, 667},
			CoreUISafeInsets = {0, 36, 375, 667}, TopbarSafeInsets = {0, 0, 375, 36},
		}},
	-- The narrowest supported portrait shape, and the one the Colors page
	-- overflows worst on.
	{Name = "adversarial 338x705 portrait, no housing",
		Size = Vector2.new(338, 705),
		Touch = true, Class = "phone", Portrait = true,
		Topbar = {0, 36, 0, 0},
		Frames = {
			None = {0, 0, 338, 705}, DeviceSafeInsets = {0, 0, 338, 705},
			CoreUISafeInsets = {0, 36, 338, 705}, TopbarSafeInsets = {0, 0, 338, 36},
		}},
	{Name = "adversarial 1180x820 tablet landscape",
		Size = Vector2.new(1180, 820),
		Touch = true, Class = "tablet", Portrait = false,
		Topbar = {0, 36, 0, 0},
		Frames = {
			None = {0, 0, 1180, 820}, DeviceSafeInsets = {0, 0, 1180, 820},
			CoreUISafeInsets = {0, 36, 1180, 820}, TopbarSafeInsets = {0, 0, 1180, 36},
		}},
	{Name = "adversarial 820x1180 tablet portrait",
		Size = Vector2.new(820, 1180),
		Touch = true, Class = "tablet", Portrait = true,
		Topbar = {0, 36, 0, 0},
		Frames = {
			None = {0, 0, 820, 1180}, DeviceSafeInsets = {0, 0, 820, 1180},
			CoreUISafeInsets = {0, 36, 820, 1180}, TopbarSafeInsets = {0, 0, 820, 36},
		}},
	{Name = "adversarial 1920x1080 desktop",
		Size = Vector2.new(1920, 1080),
		Touch = false, Class = "desktop", Portrait = false,
		Topbar = {0, 36, 0, 0},
		Frames = {
			None = {0, 0, 1920, 1080}, DeviceSafeInsets = {0, 0, 1920, 1080},
			CoreUISafeInsets = {0, 36, 1920, 1080}, TopbarSafeInsets = {0, 0, 1920, 36},
		}},
	{Name = "adversarial 1366x768 desktop",
		Size = Vector2.new(1366, 768),
		Touch = false, Class = "desktop", Portrait = false,
		Topbar = {0, 36, 0, 0},
		Frames = {
			None = {0, 0, 1366, 768}, DeviceSafeInsets = {0, 0, 1366, 768},
			CoreUISafeInsets = {0, 36, 1366, 768}, TopbarSafeInsets = {0, 0, 1366, 36},
		}},
}

-- THE ONE MEASURED CASE, and the only one.
--
-- Studio's Device Emulator, iPhone 16 Pro Max, landscape, read first-hand off
-- GuiService and Camera during that session. Not inferred, not copied out of a
-- specification, not rounded. Every number here was printed by the engine:
--
--   GetInsetArea(None)              (-62,-58)..(893,381)   955 x 439
--   GetInsetArea(DeviceSafeInsets)  (  0,-58)..(831,360)   831 x 418
--   GetInsetArea(CoreUISafeInsets)  (  0,  0)..(831,360)   831 x 360
--   GetInsetArea(TopbarSafeInsets)  (164,-58)..(831,  0)   667 x  58
--   Camera.ViewportSize                                    831 x 418
--
-- This row is NOT a fixture and is deliberately absent from Fit.Devices: it is
-- checked against the LIVE engine, so it can only prove its exact numbers on
-- the host that produced them. It earns its place twice over anyway. First,
-- the RELATIONSHIPS it encodes hold on every host and are asserted on every
-- host: Display is GetInsetArea(None); Safe is CoreUI intersected with Device;
-- and the camera is already device-safe, so a safe area narrower than the
-- camera means the housing was subtracted a second time -- which is exactly
-- the P0 this lane exists for. Second, the housing and topbar it IMPLIES make
-- a fixture, and the fixture model has to reproduce the measured rectangles
-- from them; if it cannot reproduce the one real device we have, the eleven
-- adversarial rows above prove nothing.
--
-- The topbar strip is the single place the fixture model knowingly falls short
-- of the measurement: the engine reserves 226px at the left of that strip for
-- Roblox's own buttons and nothing states that width to a fixture, so the
-- cross-check below holds the strip's top, bottom and right edges exactly and
-- requires only that its left edge lie inside the core-safe band.
Fit.MeasuredCase = {
	Name = "iPhone 16 Pro Max landscape, Studio Device Emulator, measured",
	None = {Min = Vector2.new(-62, -58), Max = Vector2.new(893, 381)},
	DeviceSafeInsets = {Min = Vector2.new(0, -58), Max = Vector2.new(831, 360)},
	CoreUISafeInsets = {Min = Vector2.new(0, 0), Max = Vector2.new(831, 360)},
	TopbarSafeInsets = {Min = Vector2.new(164, -58), Max = Vector2.new(831, 0)},
	Camera = Vector2.new(831, 418),
	-- Housing = DeviceSafeInsets against None. Topbar = CoreUISafeInsets
	-- against DeviceSafeInsets. Both read straight off the four rects above,
	-- and the frames below are then the same four rects expressed relative to
	-- the display's top-left -- so a disagreement here is the fixture model
	-- failing to reproduce a real device, not a transcription argument.
	Fixture = {Name = "the measured iPhone 16 Pro Max, rebuilt as a fixture",
		Size = Vector2.new(955, 439),
		Touch = true, Class = "phone", Portrait = false,
		Safe = {62, 0, 62, 21}, Topbar = {0, 58, 0, 0},
		Frames = {
			None = {0, 0, 955, 439}, DeviceSafeInsets = {62, 0, 893, 418},
			CoreUISafeInsets = {62, 58, 893, 418}, TopbarSafeInsets = {62, 0, 893, 58},
		}},
}

-- One reporter shape for all three matrices below.
-- C_COMPACT_REPORT_20260831 -- WHAT SHIPPED BROKEN.
--
-- Every lane appended a line per PASSING check and RunAll concatenated the lot,
-- plus a printed rectangle for every measured child of every scenario. A full
-- run came to about 230KB. That is past the 200KB a StringValue accepts -- the
-- assignment throws, which is how a completed run once looked like a hung one --
-- and a caller that returns it through Studio's execute_luau stalls the
-- transport outright. A suite whose report cannot be retrieved has not been run.
--
-- COMPACT is opt-in and changes only what is PRINTED. Every check still runs and
-- every number is still counted; failures keep their full detail, and note/skip
-- lines are never suppressed because they are the channel this suite reports its
-- own limitations through. Verbose remains the default so no existing caller
-- changes meaning underneath itself.
Fit.Compact = false

function Fit.compactly(body)
	-- Restores the flag on BOTH exits. A lane that throws with Compact left on
	-- would silently truncate every later report in the session.
	--
	-- ALL the return values, not the first. Every lane returns (report, failures)
	-- and this used to capture one -- so RunAllCompact handed its caller a report
	-- and a nil, and the summary's own header read "failures=nil" while the
	-- per-lane counts underneath it were right. table.pack/unpack rather than two
	-- named locals so it stays correct if a lane ever returns a third thing.
	local was = Fit.Compact
	Fit.Compact = true
	local results = table.pack(pcall(body))
	Fit.Compact = was
	if not results[1] then error(results[2], 0) end
	return table.unpack(results, 2, results.n)
end

-- Only in verbose mode. Used for the review-only rectangle dumps -- material a
-- human reads while judging a layout, and noise to a caller counting failures.
function Fit.detail(report: {string}, line: string)
	if not Fit.Compact then table.insert(report, line) end
end

function Fit.recorder(header: string)
	local report = {header}
	local stolen = Fit.takeStolenNote()
	if stolen then table.insert(report, "  note " .. stolen) end
	local state = {Checks = 0, Failures = 0}
	function state.record(ok, description, detail)
		state.Checks += 1
		Fit.beat()
		if ok then
			if not Fit.Compact then table.insert(report, "  ok   " .. description) end
		else
			state.Failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
		end
	end
	function state.note(line) table.insert(report, line) end
	function state.finish()
		table.insert(report, string.format("TOTAL: %d checks, %d failed",
			state.Checks, state.Failures))
		-- THE LOCK IS NOT RELEASED HERE any more. finish() is the exit a lane
		-- takes when it RETURNS, and a lane that THREW never reaches it -- so an
		-- errored sweep left the lock held by a thread that no longer existed and
		-- every later call was refused until the abandonment window expired. The
		-- release now happens in Fit.lane, on the way out of the xpcall, which is
		-- the one exit both outcomes share.
		return table.concat(report, "\n"), state.Failures
	end
	return state
end

-- Capture / restore, one shape, used by all three.
--
-- WHAT SHIPPED BROKEN: this captured three workspace attributes and nothing
-- else, while the matrices went on to write a dozen PLAYER attributes, enable
-- and disable ScreenGuis, force panels Visible, overwrite the live dispatch
-- subtitle with a test cue, open the Zyntra terminal and suppress movement.
-- Every one of those leaked into whatever ran next -- including the next matrix
-- and the player's own session -- so a green run could be an artefact of a
-- previous row's residue, and a red one could be its victim.
--
-- Everything the matrices touch is now snapshotted and restored, and the
-- restore is ASSERTED rather than assumed.
-- C_BORROW_TOPBAR_20260831 -- WHAT SHIPPED BROKEN. UIRegressionTopbarInset is
-- the FOURTH Studio-only override: it pins the synthetic fixture's topbar inset
-- so a row's expected rectangles do not depend on the host machine's own
-- measured topbar. It was added to UIDevice and to nothing here, so a lane that
-- set it left it set -- and the next lane, and the player's own session after
-- the suite finished, went on computing every safe rectangle against some
-- fixture's topbar instead of the machine's. An override the harness can write
-- is an override the harness has to put back; there is no such thing as a
-- read-only one.
local BORROWED_WORKSPACE_ATTRIBUTES = {
	"UIRegressionViewport", "ForceTouchUI",
	-- Both transports. The legacy Rect pair is still read by UIDevice for
	-- callers that write it, so a run that leaves one behind changes the next
	-- one's geometry; and the exact pairs are what Fit.apply actually states.
	"UIRegressionSafeInsets", "UIRegressionTopbarInset",
	"UIRegressionSafeInsetsLT", "UIRegressionSafeInsetsRB",
	"UIRegressionTopbarInsetLT", "UIRegressionTopbarInsetRB",
	"UIRegressionTopbarBandLR",
}
-- INPUTS the matrices write, and therefore have to put back.
local BORROWED_PLAYER_ATTRIBUTES = {
	"UIRegressionForceLevel3Reader", "UIRegressionForceReaderHidden",
	"UIRegressionForceDispatchActive", "UIRegressionForceHiding",
	"UIRegressionSilenceDispatch", "UIRegressionSuppressDispatch",
	"DevRoundEnding", "InRound", "Escaped", "Spectating", "Level3_Hiding",
	"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen", "QueueModalOpen",
	-- The PARTY DOWN seam, same shape as DevRoundEnding: the party-down row
	-- writes it, so the row has to put it back.
	"DevPartyDown",
}
-- OUTPUTS production derives from those inputs. They are restored with
-- everything else, but they are not held to the snapshot afterwards: production
-- republishes them from its own state, and demanding they match a value the
-- harness wrote would be demanding that production stop deriving them.
local DERIVED_PLAYER_ATTRIBUTES = {
	"Level2AlertOwnsBand", "LevelOneGuideObjectivesOpen", "DispatchBriefingOpen",
	"TouchMovementSuppressed",
	-- RoundUI publishes both of these from the party-down window itself, and
	-- ZyntraStore reads them to stand its own re-entry modal down. They are NOT
	-- the same fact: the card flag says a card is drawn (it frees the cursor),
	-- the window flag outlives it once NO THANKS is pressed.
	"PartyDownCardOpen", "PartyDownWindowOpen",
}
local BORROWED_GUIS = {
	"PuzzleGui", "Level2ObjectiveGui", "Level2AlertGui", "Level3ReaderGui",
	"Level3TableHideUI", "SpectateGui", "LevelOneGuideGui", "RoundGui",
	"ZyntraStore", "NoiseGui", "FlashlightPopup",
}

-- (b) AWAIT ITS NATURAL END, BOUNDED.
--
-- C_LIVE_DISPATCH_20260831 -- WHAT SHIPPED BROKEN. Eight lanes disturb a live
-- dispatch to do their job: they call resetScenario, which writes
-- UIRegressionSilenceDispatch and cuts a real transmission off mid-sentence, or
-- they force UIRegressionForceDispatchActive and overwrite the caption with a
-- test cue. Running one in the lobby while the join briefing was playing STOPPED
-- the briefing -- and Fit.residue then excused the resulting differences on the
-- grounds that the briefing had "ended on its own clock". It had not. The matrix
-- ended it, and the excuse was written by the thing it was excusing.
--
-- Of the three honest options -- refuse, await, or drive it through a reversible
-- seam -- there is no seam: nothing in production can rewind a transmission to
-- the second it was interrupted at, so (c) does not exist here. Between refusing
-- and waiting, waiting is what an operator actually wants, because the lobby cue
-- ends by itself about a minute after join and a suite that refuses for that
-- minute is a suite nobody runs twice. So every affected lane AWAITS the
-- briefing's natural end before it borrows anything, and refuses with a named
-- reason if it outlasts the bound. Nothing is borrowed, forced or measured on
-- the refusing path, so a refusal leaves the screen exactly as it found it.
--
-- WHY 90 SECONDS: the lobby cue runs about a minute; 90 leaves room for a long
-- one and still fails fast enough that a DispatchBriefingOpen attribute stuck
-- true is reported as a stuck attribute rather than as a hung suite.
Fit.LiveDispatchWait = 90

-- A briefing the HARNESS forced up is not a real one, and waiting for it would
-- be waiting for ourselves. That distinction is the only reason RunAll can wait
-- once at the top and then drive nine lanes that each wait again for nothing.
-- PRETENDING, for the guard's own test, and nothing else. See
-- C_GUARD_IS_PROVED_WITHOUT_A_VICTIM_20260831: the only honest way to prove the
-- refusal path is to make the predicate answer true, and the two ways of doing
-- that with real state are both unacceptable -- starting a real briefing means
-- waiting a minute for one, and faking DispatchBriefingOpen does not survive,
-- because RoundUI republishes that attribute from the transmission it is
-- actually playing and clears it again within a frame (measured: set true, read
-- back false 0.1s later). This flag is read ONLY here and set ONLY by
-- ExclusionTimingMatrix, which clears it on every exit including an error.
Fit.PretendDispatchLive = false

function Fit.realDispatchLive(): boolean
	if Fit.PretendDispatchLive then return true end
	local player = Players.LocalPlayer
	if player:GetAttribute("DispatchBriefingOpen") ~= true then return false end
	return player:GetAttribute("UIRegressionForceDispatchActive") == nil
end

function Fit.awaitQuietDispatch(): (boolean, string?)
	if not Fit.realDispatchLive() then return true, nil end
	-- os.time, not os.clock: os.clock inside the Studio datamodel is CPU time and
	-- would make this bound roughly four times longer than it reads.
	local deadline = os.time() + Fit.LiveDispatchWait
	while Fit.realDispatchLive() do
		if os.time() >= deadline then
			return false, string.format(
				"a real dispatch briefing has been playing for the whole %ds this lane"
				.. " is willing to wait, and this lane cannot run without interrupting"
				.. " it. Nothing was borrowed, forced or measured. Run it again once the"
				.. " briefing has finished, or clear DispatchBriefingOpen if it is stuck.",
				Fit.LiveDispatchWait)
		end
		Fit.beat()
		task.wait(0.5)
	end
	-- Production republishes the briefing's widgets on its own deferred clock
	-- after the transmission ends. Snapshotting inside that window would capture a
	-- half-torn-down briefing and then hold the restore to it, which is the same
	-- false failure the excuse was invented to hide -- just moved earlier.
	task.wait(0.5)
	Fit.beat()
	return true, nil
end

function Fit.borrow()
	local player = Players.LocalPlayer
	local saved = {
		Workspace = {}, Player = {}, Guis = {}, Subtitle = nil, TerminalOpen = false,
	}
	for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
		saved.Workspace[name] = workspace:GetAttribute(name)
	end
	for _, name in ipairs(BORROWED_PLAYER_ATTRIBUTES) do
		saved.Player[name] = player:GetAttribute(name)
	end
	for _, name in ipairs(DERIVED_PLAYER_ATTRIBUTES) do
		saved.Player[name] = player:GetAttribute(name)
	end
	-- EVERY DESCENDANT, not only the top-level children.
	--
	-- The matrices reach deep: they force pages Visible, flip Active on
	-- controls, select terminal tabs and scroll them. A snapshot one level deep
	-- restored the shade and left the panel inside it forced on, which is how a
	-- later row measured a screen the player never sees.
	for _, name in ipairs(BORROWED_GUIS) do
		local screen = playerGui():FindFirstChild(name)
		if screen and screen:IsA("ScreenGui") then
			local entry = {Enabled = screen.Enabled, Children = {}}
			for _, child in ipairs(screen:GetDescendants()) do
				if child:IsA("GuiObject") then
					entry.Children[child] = {
						Visible = child.Visible,
						Active = (child:IsA("TextButton") or child:IsA("ImageButton"))
							and (child :: any).Active or nil,
						Canvas = child:IsA("ScrollingFrame")
							and (child :: any).CanvasPosition or nil,
					}
				end
			end
			saved.Guis[name] = entry
		end
	end
	-- The terminal's own page state: which tab is selected, and where each of
	-- its scrolls is. A matrix that walks every tab used to leave the player on
	-- whichever one it happened to finish with -- in practice always the first,
	-- because the sweep reset to it -- rather than the one they had open.
	local store = playerGui():FindFirstChild("ZyntraStore")
	local storeProbe = store and store:FindFirstChild("UIRegressionZyntraStoreProbe")
	if storeProbe and storeProbe:IsA("BindableFunction") then
		local content = store:FindFirstChild("TerminalContent", true)
		if content then
			for _, page in ipairs(content:GetChildren()) do
				if page:IsA("GuiObject") and page.Visible then
					saved.TerminalTab = page.Name
				end
			end
		end
	end
	-- The Level 3 reader's hidden state, which the matrices toggle through the
	-- production handlers and never put back.
	local reader = playerGui():FindFirstChild("Level3ReaderGui")
	local readerProbe = reader and reader:FindFirstChild("UIRegressionReaderProbe")
	if readerProbe and readerProbe:IsA("BindableFunction") then
		local ok, state = pcall(function() return readerProbe:Invoke("state") end)
		saved.ReaderHidden = ok and state == "hidden" or false
	end
	-- WAS A BRIEFING IN FLIGHT? Recorded for CONTEXT only. It used to license an
	-- excuse in Fit.residue -- the widgets a briefing owns were dropped from the
	-- comparison if it had ended since -- and it no longer does. Every lane that
	-- can disturb a live dispatch now waits for one to end BEFORE it takes this
	-- snapshot (Fit.awaitQuietDispatch), so this reads false whenever a lane is
	-- behaving; when it does not, residue says a transition happened instead of
	-- quietly forgiving the widgets that moved.
	saved.DispatchOpen = Players.LocalPlayer:GetAttribute("DispatchBriefingOpen") == true
	-- The live dispatch caption. setLongDispatchCue overwrites it in place, and
	-- nothing put it back -- so every run left the player's briefing showing a
	-- test string until the next real cue.
	local guide = playerGui():FindFirstChild("LevelOneGuideGui")
	local subtitle = guide and guide:FindFirstChild("Subtitle", true)
	if subtitle and subtitle:IsA("TextLabel") then
		saved.Subtitle = {Label = subtitle, Text = subtitle.Text}
	end
	local store = playerGui():FindFirstChild("ZyntraStore")
	local terminal = store and store:FindFirstChild("Terminal")
	saved.TerminalOpen = terminal ~= nil and (terminal :: any).Visible == true
	return saved
end

function Fit.restore(saved)
	if not saved then return end
	local player = Players.LocalPlayer
	-- The terminal FIRST and through its own production path, so closing it
	-- republishes ZyntraStoreOpen and releases the movement suppression before
	-- the attributes below are put back.
	local store = playerGui():FindFirstChild("ZyntraStore")
	local probe = store and store:FindFirstChild("UIRegressionZyntraStoreProbe")
	if probe and probe:IsA("BindableFunction") then
		pcall(function() probe:Invoke(saved.TerminalOpen and "open" or "close") end)
	end
	for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
		workspace:SetAttribute(name, saved.Workspace[name])
	end
	for _, name in ipairs(BORROWED_PLAYER_ATTRIBUTES) do
		player:SetAttribute(name, saved.Player[name])
	end
	for _, name in ipairs(DERIVED_PLAYER_ATTRIBUTES) do
		player:SetAttribute(name, saved.Player[name])
	end
	for name, entry in pairs(saved.Guis) do
		local screen = playerGui():FindFirstChild(name)
		if screen and screen:IsA("ScreenGui") then
			(screen :: ScreenGui).Enabled = entry.Enabled
			for child, state in pairs(entry.Children) do
				if child.Parent then
					child.Visible = state.Visible
					if state.Active ~= nil then (child :: any).Active = state.Active end
					if state.Canvas ~= nil then (child :: any).CanvasPosition = state.Canvas end
				end
			end
		end
	end
	-- The terminal's selected tab, through the production selectTab.
	if saved.TerminalTab and probe and probe:IsA("BindableFunction") then
		pcall(function() probe:Invoke("tab:" .. saved.TerminalTab) end)
	end
	-- The reader's hidden state, through the production handlers.
	local readerScreen = playerGui():FindFirstChild("Level3ReaderGui")
	local readerProbe = readerScreen
		and readerScreen:FindFirstChild("UIRegressionReaderProbe")
	if readerProbe and readerProbe:IsA("BindableFunction") then
		pcall(function()
			local current = readerProbe:Invoke("state") == "hidden"
			if current ~= (saved.ReaderHidden == true) then
				readerProbe:Invoke(saved.ReaderHidden
					and "invokePanelHandler" or "invokeRestoreHandler")
			end
		end)
	end
	if saved.Subtitle and saved.Subtitle.Label.Parent then
		saved.Subtitle.Label.Text = saved.Subtitle.Text
	end
end

-- What is STILL different from the snapshot. Returned as a list so a matrix can
-- assert cleanup instead of claiming it.
--
-- Returns the problems and, separately, a NOTE. The note used to name the
-- differences this check DECLINED to count. It no longer declines any. It is
-- context only -- it says a real briefing started or ended mid-run, so a reader
-- looking at the problems knows what moved underneath them -- and it suppresses
-- nothing.
--
-- WHAT IT VERIFIES, which is exactly what its callers are entitled to claim:
-- every borrowed workspace attribute; every borrowed player attribute; each
-- borrowed ScreenGui's existence and Enabled flag; for every borrowed
-- descendant its Visible, its Active where it has one and its CanvasPosition
-- where it has one; the terminal's selected tab, as the one and only visible
-- page; the Level 3 reader's hidden state; and that the dispatch caption no
-- longer holds the test cue.
function Fit.residue(saved): ({string}, string?)
	local problems = {}
	if not saved then return {"nothing was captured"} end
	local player = Players.LocalPlayer
	for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
		if workspace:GetAttribute(name) ~= saved.Workspace[name] then
			table.insert(problems, "workspace." .. name .. " = "
				.. tostring(workspace:GetAttribute(name)))
		end
	end
	for _, name in ipairs(BORROWED_PLAYER_ATTRIBUTES) do
		if player:GetAttribute(name) ~= saved.Player[name] then
			table.insert(problems, "player." .. name .. " = "
				.. tostring(player:GetAttribute(name)))
		end
	end
	-- C_RESIDUE_NO_EXCUSES_20260831 -- WHAT SHIPPED BROKEN. This check used to
	-- excuse "briefing-following widgets": if a real briefing had been playing
	-- when the snapshot was taken and had ended by the time the lane finished,
	-- every difference under CommandSubtitles and on the Zyntra opener was
	-- credited to production and dropped. The hatch was shaped exactly like the
	-- residue it claimed to distinguish itself from -- the widgets a briefing
	-- owns are the widgets these lanes force hardest -- so it fired precisely
	-- where a leak would have been, and it excused real residue. Worse, the
	-- briefing it forgave was usually one the matrix had stopped itself, through
	-- resetScenario's UIRegressionSilenceDispatch.
	--
	-- The hatch is gone. The honest mechanism is upstream, in the lanes: nothing
	-- that disturbs a live dispatch starts while one is playing (see
	-- Fit.awaitQuietDispatch), so the snapshot is taken of a quiet world and there
	-- is no transition left for an excuse to be about. A briefing that starts
	-- DURING a lane is counted as problems -- because that is what it is, a report
	-- measured against a screen that changed underneath it -- and the note says a
	-- transition happened so the reader knows which way to look.
	local note: string? = nil
	if (saved.DispatchOpen == true)
		~= (player:GetAttribute("DispatchBriefingOpen") == true) then
		note = "      NOTE a real dispatch briefing "
			.. (saved.DispatchOpen == true and "ENDED" or "STARTED")
			.. " while this matrix was running. Nothing below is excused for it; the"
			.. " differences are reported exactly as found."
	end
	for name, entry in pairs(saved.Guis) do
		local screen = playerGui():FindFirstChild(name)
		if not (screen and screen:IsA("ScreenGui")) then
			-- A borrowed ScreenGui that is no longer there has not been "restored".
			-- Skipping it silently is how a lane could destroy the very thing it was
			-- measuring and still be reported as having put everything back.
			table.insert(problems, name .. " is gone")
			continue
		end
		if (screen :: ScreenGui).Enabled ~= entry.Enabled then
			table.insert(problems, name .. ".Enabled = "
				.. tostring((screen :: ScreenGui).Enabled))
		end
		for child, state in pairs(entry.Children) do
			if child.Parent then
				if child.Visible ~= state.Visible then
					table.insert(problems, string.format("%s.%s.Visible = %s",
						name, child.Name, tostring(child.Visible)))
				end
				if state.Active ~= nil and (child :: any).Active ~= state.Active then
					table.insert(problems, string.format("%s.%s.Active = %s",
						name, child.Name, tostring((child :: any).Active)))
				end
				-- CanvasPosition was snapshotted, was restored, and was never checked.
				-- So the one piece of state these lanes move MOST -- the terminal
				-- matrix scrolls every page of every tab -- was the one piece nothing
				-- held to the snapshot, and a scroll left halfway down is exactly the
				-- residue that makes the next lane's first row measure a card that is
				-- not where the player left it.
				if state.Canvas ~= nil and (child :: any).CanvasPosition ~= state.Canvas then
					table.insert(problems, string.format("%s.%s.CanvasPosition = %s",
						name, child.Name, tostring((child :: any).CanvasPosition)))
				end
			end
		end
	end
	-- THE SELECTED TAB, EXACTLY. The old check read the LAST visible page and
	-- compared that -- so two pages visible at once passed as long as the last one
	-- was right, and ZERO visible pages passed unconditionally. Zero is not a
	-- pass; it is the precise state a failed restore leaves behind, a terminal
	-- open on nothing. A tab that was selected has to still be the one and only
	-- selected tab. The container is reached through ZyntraStore rather than by a
	-- recursive search from PlayerGui, so this asks the same node Fit.borrow
	-- snapshotted and not whatever else in the HUD is called TerminalContent.
	if saved.TerminalTab then
		local store = playerGui():FindFirstChild("ZyntraStore")
		local content = store and store:FindFirstChild("TerminalContent", true)
		local shown, visibleCount = nil, 0
		if content then
			for _, page in ipairs(content:GetChildren()) do
				if page:IsA("GuiObject") and page.Visible then
					shown = page.Name
					visibleCount += 1
				end
			end
		end
		if not content then
			table.insert(problems, "the terminal's page container is gone, so the "
				.. saved.TerminalTab .. " tab could not be restored")
		elseif visibleCount == 0 then
			table.insert(problems, "the terminal is left showing NO page at all; "
				.. saved.TerminalTab .. " was the open tab")
		elseif visibleCount > 1 then
			table.insert(problems, string.format(
				"the terminal is left with %d pages visible at once; only %s was open",
				visibleCount, saved.TerminalTab))
		elseif shown ~= saved.TerminalTab then
			table.insert(problems, "the terminal is left on the " .. tostring(shown)
				.. " tab, not " .. saved.TerminalTab)
		end
	end
	do
		local readerScreen = playerGui():FindFirstChild("Level3ReaderGui")
		local readerProbe = readerScreen
			and readerScreen:FindFirstChild("UIRegressionReaderProbe")
		if readerProbe and readerProbe:IsA("BindableFunction") then
			local ok, state = pcall(function() return readerProbe:Invoke("state") end)
			if ok and (state == "hidden") ~= (saved.ReaderHidden == true) then
				table.insert(problems, "the Level 3 reader is left " .. tostring(state))
			end
		end
	end
	-- The caption only has to be free of the TEST cue. Production may have put
	-- its own live copy there in the meantime, and that is not residue.
	if saved.Subtitle and saved.Subtitle.Label.Parent
		and saved.Subtitle.Label.Text == LONG_DISPATCH_CUE
		and saved.Subtitle.Text ~= LONG_DISPATCH_CUE then
		table.insert(problems, "the dispatch subtitle still holds the test cue")
	end
	return problems, note
end

-- Apply a device AND WAIT FOR IT TO TAKE.
--
-- WHAT SHIPPED BROKEN in the harness: every matrix wrote the three override
-- attributes and then slept a fixed 0.3s. UIDevice recomputes from an
-- attribute-changed signal, which is DEFERRED -- so on a busy frame the sleep
-- can expire before the recompute lands and the row measures the PREVIOUS
-- device's layout. Observed directly: a run in which the "desktop 1366x768"
-- row reported 440x956, i.e. the layout was eight rows behind, and eleven
-- assertions failed against a screen that was never under test.
--
-- The wait is now on the CONDITION, with a bounded deadline, so a row either
-- measures the device it asked for or reports that it could not get it.
function Fit.apply(device): boolean
	Fit.beat()
	-- ALWAYS a boolean. It used to write nil for the pointer rows, which meant
	-- "ask the host" -- so every desktop and tablet-with-keys row was really the
	-- host's own form factor, and running the suite inside the Device Emulator
	-- silently turned all of them into touch devices. A fixture states its form
	-- factor; nothing about it is inherited.
	workspace:SetAttribute("ForceTouchUI", device.Touch == true)
	-- BOTH inset overrides are stated as four plain numbers -- {left, top, right,
	-- bottom} -- and turned into a Rect HERE, at the last possible moment.
	--
	-- C_INSETS_ARE_NUMBERS_20260831 -- WHAT SHIPPED BROKEN. A row wrote its
	-- insets as Rect.new(left, top, right, bottom), and a Rect is not four free
	-- numbers: its Max components cannot be smaller than its Min components, so
	-- Rect.new(0, 58, 0, 0) -- a topbar and nothing else, the commonest shape
	-- there is -- may not survive its own constructor. Read as insets that is a
	-- 58px BOTTOM inset appearing out of nowhere, on every row, silently, and it
	-- would have surfaced as a dozen unrelated-looking geometry failures rather
	-- than as the one thing that actually went wrong. The row now states numbers
	-- and Fit.fixtureProblems reads the attribute back and holds it to them, so
	-- the transport is checked instead of assumed.
	-- ...AND THE ROW'S NUMBERS NOW TRAVEL AS NUMBERS.
	--
	-- C_INSETS_SURVIVE_THE_TRIP_20260831. The paragraph above diagnosed the Rect
	-- exactly and then still shipped the values through Rect.new. Measured
	-- first-hand in the running place:
	--     Rect.new(0,58,0,0)  -> Min(0,0)  Max(0,58)     NOT PRESERVED
	--     Rect.new(12,3,4,7)  -> Min(4,3)  Max(12,7)     NOT PRESERVED
	-- Rect.new SORTS each axis. So the topbar row {0,58,0,0} arrived as a 58px
	-- BOTTOM inset, the layout was measured against a rectangle no row states,
	-- and the safe-area lane reported 81 failures that were all this one bug.
	--
	-- UIDevice now accepts the exact form: a PAIR of Vector2 attributes per
	-- inset, which keeps all four margins independent because a Vector2 has no
	-- ordering rule. The legacy Rect attributes are CLEARED rather than left
	-- alongside -- UIDevice prefers the exact form outright, but a stale Rect
	-- sitting next to it is a trap for the next person to read this.
	local function pair(stated, a: number, c: number): Vector2?
		if type(stated) ~= "table" then return nil end
		return Vector2.new(stated[a] or 0, stated[c] or 0)
	end
	workspace:SetAttribute("UIRegressionSafeInsets", nil)
	workspace:SetAttribute("UIRegressionTopbarInset", nil)
	workspace:SetAttribute("UIRegressionSafeInsetsLT", pair(device.Safe, 1, 2))
	workspace:SetAttribute("UIRegressionSafeInsetsRB", pair(device.Safe, 3, 4))
	workspace:SetAttribute("UIRegressionTopbarInsetLT", pair(device.Topbar, 1, 2))
	workspace:SetAttribute("UIRegressionTopbarInsetRB", pair(device.Topbar, 3, 4))
	-- The topbar BAND's horizontal margins. TopbarSafeInsets is the topbar
	-- widget's own strip and it does not span the screen -- measured, it is
	-- 667 wide inside an 831-wide device-safe rect, i.e. 164 in from the left --
	-- so a row that asserts that rectangle has to state where the strip starts.
	-- A row that states nothing gets a full-width band, which is what a device
	-- with no measurement to offer should be modelled as.
	workspace:SetAttribute("UIRegressionTopbarBandLR",
		type(device.Band) == "table"
			and Vector2.new(device.Band[1] or 0, device.Band[2] or 0) or nil)
	-- The topbar override is STATED the same way, for the same reason: a fixture
	-- that does not name a topbar inset gets none, never the previous row's. An
	-- inherited one would make a row's expected rectangles depend on which row
	-- happened to run before it, which is the whole failure mode the fixture
	-- exists to remove.
	workspace:SetAttribute("UIRegressionViewport", device.Size)
	local deadline = 40
	while deadline > 0 do
		local layout = UIDevice.Layout()
		if layout.Width == device.Size.X and layout.Height == device.Size.Y
			and layout.IsTouch == (device.Touch == true) then
			-- One more frame so every UIDevice.Changed listener has re-laid out
			-- against the size that just took.
			task.wait(0.15)
			return true
		end
		task.wait(0.05)
		deadline -= 1
	end
	return false
end

-- WHAT THE FIXTURE MUST BE, checked before anything is measured against it.
--
-- C_ORACLE_IS_STATED_20260831 -- WHAT SHIPPED BROKEN. This function claimed to
-- state the fixture's insets "INDEPENDENTLY", and it did nothing of the kind.
-- It read CoreUISafeInsets and DeviceSafeInsets off the LIVE host, subtracted
-- one from the other to get a topbar, and combined that with the row's housing
-- by taking the larger edge by edge -- which is, line for line, the arithmetic
-- UIDevice performs on those same two rectangles. Oracle and subject ran the
-- same program over the same inputs, so the comparison could only ever hold: a
-- fixture was incapable of being wrong. Flip the sign in UIDevice's
-- combination and this flipped with it. Both sides also moved with the machine
-- -- the same row was one rectangle under a desktop Studio window (~36px
-- topbar) and another under the Device Emulator (58px) -- so there was no
-- rectangle to write down even if anyone had wanted to.
--
-- A row now STATES its topbar as well as its housing, and states the four
-- rectangles they determine. Everything below is checked against those
-- literals and nothing is recomputed. The single exception is the display
-- ORIGIN, which is host-dependent on purpose: the fixture is anchored so its
-- safe corner lands on the engine's real safe corner, because that is what
-- makes an analytic rectangle and a live AbsolutePosition the same number.
-- That anchoring is checked here as well, against GuiService's own corner and
-- the row's stated top-left inset -- neither of which is UIDevice's arithmetic.
function Fit.fixtureProblems(device): {string}
	local problems = {}
	local layout = UIDevice.Layout()
	if not layout.Synthetic then
		table.insert(problems, "layout does not report itself as a fixture")
		return problems
	end
	local stated = device.Frames and device.Frames.CoreUISafeInsets
	if type(stated) ~= "table" or #stated ~= 4 then
		-- NOT a pass, and not a skip. A row with no stated rectangle has no
		-- oracle, and a row with no oracle is the exact thing this rewrite
		-- exists to abolish; reporting it as a problem is the only honest
		-- answer.
		table.insert(problems, "the row states no CoreUISafeInsets rectangle")
		return problems
	end
	local display = layout.Display
	if math.abs((display.Right - display.Left) - device.Size.X) > 0.5
		or math.abs((display.Bottom - display.Top) - device.Size.Y) > 0.5 then
		table.insert(problems, string.format(
			"fixture display is %.0fx%.0f, the row states %.0fx%.0f",
			display.Right - display.Left, display.Bottom - display.Top,
			device.Size.X, device.Size.Y))
	end
	-- THE FIXTURE THAT ARRIVED IS THE FIXTURE THAT WAS ASKED FOR. Both inset
	-- overrides travel to UIDevice as a Rect, and a Rect clamps its Max
	-- components up to its Min ones -- so a row stating a top inset and no bottom
	-- one can be handed a bottom inset nobody wrote down, and every literal below
	-- would then be measured against a fixture that was never requested. The
	-- attributes are read BACK and held to the row's own four numbers, so a
	-- mangled transport reports itself once, by name, instead of surfacing as a
	-- dozen unrelated-looking geometry failures.
	--
	-- The transport is now a PAIR of Vector2 attributes per inset, because a Rect
	-- cannot carry four independent margins (measured: Rect.new(0,58,0,0) comes
	-- back as Min(0,0) Max(0,58), so the topbar row arrived as a bottom inset).
	-- Both halves of both pairs are read back and held to the row's own numbers,
	-- and the legacy Rect attributes must be ABSENT -- UIDevice prefers the exact
	-- form, so a stale Rect would be invisible here and misleading to a reader.
	for _, entry in ipairs({
		{"UIRegressionSafeInsets", device.Safe},
		{"UIRegressionTopbarInset", device.Topbar},
	}) do
		if workspace:GetAttribute(entry[1]) ~= nil then
			table.insert(problems, entry[1]
				.. " (the legacy Rect transport) is still set; it cannot carry four"
				.. " independent margins and must be cleared")
		end
	end
	local function readbackProblems(label: string, wanted: any, lt: string, rb: string)
		local liveLT = workspace:GetAttribute(lt)
		local liveRB = workspace:GetAttribute(rb)
		if type(wanted) ~= "table" then
			if liveLT ~= nil or liveRB ~= nil then
				table.insert(problems, label .. " is set, the row states none")
			end
			return
		end
		if typeof(liveLT) ~= "Vector2" or typeof(liveRB) ~= "Vector2" then
			table.insert(problems, string.format("%s travelled as %s/%s, not Vector2/Vector2",
				label, typeof(liveLT), typeof(liveRB)))
			return
		end
		if math.abs(liveLT.X - wanted[1]) > 0.01 or math.abs(liveLT.Y - wanted[2]) > 0.01
			or math.abs(liveRB.X - wanted[3]) > 0.01 or math.abs(liveRB.Y - wanted[4]) > 0.01 then
			table.insert(problems, string.format(
				"%s carries (%.0f,%.0f,%.0f,%.0f), the row states (%d,%d,%d,%d)",
				label, liveLT.X, liveLT.Y, liveRB.X, liveRB.Y,
				wanted[1], wanted[2], wanted[3], wanted[4]))
		end
	end
	readbackProblems("the housing inset", device.Safe,
		"UIRegressionSafeInsetsLT", "UIRegressionSafeInsetsRB")
	readbackProblems("the topbar inset", device.Topbar,
		"UIRegressionTopbarInsetLT", "UIRegressionTopbarInsetRB")
	do
		local liveBand = workspace:GetAttribute("UIRegressionTopbarBandLR")
		local wantedBand = device.Band
		if type(wantedBand) ~= "table" then
			if liveBand ~= nil then
				table.insert(problems, "the topbar band is set, the row states none")
			end
		elseif typeof(liveBand) ~= "Vector2"
			or math.abs(liveBand.X - wantedBand[1]) > 0.01
			or math.abs(liveBand.Y - wantedBand[2]) > 0.01 then
			table.insert(problems, string.format(
				"the topbar band carries %s, the row states (%d,%d)",
				tostring(liveBand), wantedBand[1], wantedBand[2]))
		end
	end
	-- The four insets ARE the stated core-safe rectangle, read as insets off a
	-- panel of the stated size. Nothing here consults the host.
	local expected = {
		Left = stated[1], Top = stated[2],
		Right = device.Size.X - stated[3], Bottom = device.Size.Y - stated[4],
	}
	for _, edge in ipairs({"Left", "Top", "Right", "Bottom"}) do
		if math.abs(layout.SafeInsets[edge] - expected[edge]) > 0.5 then
			table.insert(problems, string.format(
				"safe inset %s is %.0f, the row states %.0f",
				edge, layout.SafeInsets[edge], expected[edge]))
		end
	end
	-- THE ANCHOR, and the one number that is allowed to depend on the machine.
	-- The fixture's display top-left must be the engine's real safe corner
	-- moved out by the row's stated top-left inset. Anything else and every
	-- panel converted through UIDevice.LocalPosition resolves somewhere other
	-- than where it renders -- which is how the whole cutout came to be
	-- subtracted twice in the first place.
	local core = GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
	local dev = GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
	local anchorX = math.max(core.Min.X, dev.Min.X) - expected.Left
	local anchorY = math.max(core.Min.Y, dev.Min.Y) - expected.Top
	if math.abs(display.Left - anchorX) > 0.5
		or math.abs(display.Top - anchorY) > 0.5 then
		table.insert(problems, string.format(
			"fixture display origin is (%.0f,%.0f); the engine's safe corner less"
			.. " the stated inset is (%.0f,%.0f)",
			display.Left, display.Top, anchorX, anchorY))
	end
	-- Safe must be inside Display on every edge, by construction.
	if layout.Safe.Left < display.Left - 0.5 or layout.Safe.Right > display.Right + 0.5
		or layout.Safe.Top < display.Top - 0.5 or layout.Safe.Bottom > display.Bottom + 0.5 then
		table.insert(problems, "the safe rect is not inside the display rect")
	end
	return problems
end

-- ONE Enum.ScreenInsets value, against the rectangle the ROW WROTE DOWN.
--
-- C_STATED_FRAMES_20260831 -- WHAT SHIPPED BROKEN. The fixture half of the safe
-- area lane asserted three things per row -- that the fixture took, that its
-- display was the requested size, and that three HUD rectangles were somewhere
-- inside Safe -- and every one of them was satisfied by a model that put the
-- safe area anywhere at all, so long as it put the HUD inside whatever it put
-- there. Nothing said WHERE. A ScreenGui set to DeviceSafeInsets could have
-- been handed the entire display, on every row, and the lane would have
-- reported green -- which is the same class of defect as the P0 the lane was
-- written to catch, sitting inside the lane itself.
--
-- This resolves a probe gui of ONE enum value plus the two children that
-- between them expose every edge of its frame -- one anchored to the
-- bottom-right corner in offsets, one positioned and sized in scale off the
-- middle -- and holds all of it to the row's literals. Under a fixture the
-- engine still renders at the real window, so the probe's own AbsolutePosition
-- is the host's and says nothing; the subject here is
-- UIRegression.ScreenGuiFrame and the resolver built on it, which is the path
-- every analytic rectangle in this file is read through.
function Fit.statedFrameProblems(device, kind): {string}
	local stated = device.Frames and device.Frames[kind.Name]
	local core = device.Frames and device.Frames.CoreUISafeInsets
	if type(stated) ~= "table" or type(core) ~= "table" then
		return {"the row states no " .. kind.Name .. " rectangle"}
	end
	local problems = {}
	-- The origin is taken from GuiService, NOT from UIDevice.Layout(): if the
	-- fixture's display origin moved, the expectation must not move with it,
	-- or an origin mutation cancels on both sides and disappears.
	local engineCore = GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
	local engineDev = GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
	local originX = math.max(engineCore.Min.X, engineDev.Min.X) - core[1]
	local originY = math.max(engineCore.Min.Y, engineDev.Min.Y) - core[2]
	local want = {
		Left = originX + stated[1], Top = originY + stated[2],
		Right = originX + stated[3], Bottom = originY + stated[4],
	}
	want.Width, want.Height = want.Right - want.Left, want.Bottom - want.Top

	local probe = Instance.new("ScreenGui")
	probe.Name = "SafeAreaFixtureProbe"
	probe.ResetOnSpawn = false
	probe.ScreenInsets = kind
	local corner = Instance.new("Frame")
	corner.Name = "AnchoredCorner"
	corner.AnchorPoint = Vector2.new(1, 1)
	corner.Position = UDim2.new(1, 0, 1, 0)
	corner.Size = UDim2.fromOffset(40, 24)
	corner.Parent = probe
	local middle = Instance.new("Frame")
	middle.Name = "ScaledMiddle"
	middle.Position = UDim2.new(0.5, 0, 0.5, 0)
	middle.Size = UDim2.fromScale(0.25, 0.25)
	middle.Parent = probe
	probe.Parent = playerGui()
	-- One frame, and only for the instances to settle. Nothing below reads a
	-- rendered pixel: under a fixture the probe renders at the HOST's size, so
	-- its AbsolutePosition is the wrong answer by construction and waiting for
	-- it would be waiting for a number this check must not use.
	task.wait()

	local layout = UIDevice.Layout()
	local frame = UIRegression.ScreenGuiFrame(probe, device.Size)
	local got = {
		Left = frame.Left, Top = frame.Top,
		Right = frame.Left + frame.Width, Bottom = frame.Top + frame.Height,
		Width = frame.Width, Height = frame.Height,
	}
	for _, edge in ipairs({"Left", "Top", "Right", "Bottom", "Width", "Height"}) do
		if math.abs(got[edge] - want[edge]) > 0.5 then
			table.insert(problems, string.format("%s %s is %.0f, the row states %.0f",
				kind.Name, string.lower(edge), got[edge], want[edge]))
		end
	end

	-- The anchored corner pins the frame's RIGHT and BOTTOM edges. A frame that
	-- is too wide by the cutout puts this child off the side of the screen, and
	-- that is precisely how the shipping bug presented.
	local cornerRect = UIRegression.ResolveRect(corner, device.Size, layout.Inset.Y)
	if cornerRect == nil or cornerRect.Unresolvable ~= nil then
		table.insert(problems, kind.Name .. ": the anchored corner did not resolve")
	elseif math.abs(cornerRect.Right - want.Right) > 0.5
		or math.abs(cornerRect.Bottom - want.Bottom) > 0.5
		or math.abs(cornerRect.Left - (want.Right - 40)) > 0.5
		or math.abs(cornerRect.Top - (want.Bottom - 24)) > 0.5 then
		table.insert(problems, string.format(
			"%s: a 40x24 child anchored (1,1) at the bottom-right lands %s, the row"
			.. " puts that corner at (%.0f,%.0f)",
			kind.Name, Fit.text(cornerRect), want.Right, want.Bottom))
	end
	-- The scaled child pins the frame's SIZE as well as its origin: a scale
	-- position and a scale size are both wrong if the frame is the wrong shape,
	-- even when its top-left happens to be right.
	local middleRect = UIRegression.ResolveRect(middle, device.Size, layout.Inset.Y)
	local wantMiddle = {
		Left = want.Left + want.Width * .5, Top = want.Top + want.Height * .5,
	}
	wantMiddle.Right = wantMiddle.Left + want.Width * .25
	wantMiddle.Bottom = wantMiddle.Top + want.Height * .25
	if middleRect == nil or middleRect.Unresolvable ~= nil then
		table.insert(problems, kind.Name .. ": the scaled child did not resolve")
	elseif math.abs(middleRect.Left - wantMiddle.Left) > 0.5
		or math.abs(middleRect.Top - wantMiddle.Top) > 0.5
		or math.abs(middleRect.Right - wantMiddle.Right) > 0.5
		or math.abs(middleRect.Bottom - wantMiddle.Bottom) > 0.5 then
		table.insert(problems, string.format(
			"%s: a child at UDim2.new(0.5,0,0.5,0) sized (0.25,0.25) lands %s, the"
			.. " row's rectangle puts it at (%.0f,%.0f)-(%.0f,%.0f)",
			kind.Name, Fit.text(middleRect), wantMiddle.Left, wantMiddle.Top,
			wantMiddle.Right, wantMiddle.Bottom))
	end
	probe:Destroy()
	return problems
end

-- ONE fixture, swept end to end: it took; it is exactly what the row states;
-- every Enum.ScreenInsets rectangle is where the row says it is, with an
-- anchored and a scaled child to prove the frame's edges and its size; and
-- every HUD band the layout hands out is inside Safe.
--
-- Extracted so the eleven adversarial rows and the fixture rebuilt from the one
-- measured device go through the IDENTICAL checks. If the measured rebuild were
-- swept by a second copy of this code, "the fixture model reproduces a real
-- device" would be a claim about the copy rather than about the model.
function Fit.sweepFixture(fixture, state)
	local record = state.record
	local applied = Fit.apply(fixture)
	record(applied, fixture.Name .. ": the fixture took", "timed out")
	local problems = Fit.fixtureProblems(fixture)
	record(#problems == 0,
		fixture.Name .. ": display size, all four safe insets and the display"
		.. " origin are exactly what the row states",
		table.concat(problems, "; "))
	local fixtureLayout = UIDevice.Layout()
	state.note(string.format(
		"      %-52s Display %.0fx%.0f  Safe (%.0f,%.0f)..(%.0f,%.0f)  insets L%.0f T%.0f R%.0f B%.0f",
		fixture.Name,
		fixtureLayout.Display.Right - fixtureLayout.Display.Left,
		fixtureLayout.Display.Bottom - fixtureLayout.Display.Top,
		fixtureLayout.Safe.Left, fixtureLayout.Safe.Top,
		fixtureLayout.Safe.Right, fixtureLayout.Safe.Bottom,
		fixtureLayout.SafeInsets.Left, fixtureLayout.SafeInsets.Top,
		fixtureLayout.SafeInsets.Right, fixtureLayout.SafeInsets.Bottom))
	-- ALL FOUR enum values, every time. Three of them were never checked under a
	-- fixture at all, and the fourth was checked only as "somewhere inside Safe".
	for _, kind in ipairs(Enum.ScreenInsets:GetEnumItems()) do
		local framed = Fit.statedFrameProblems(fixture, kind)
		record(#framed == 0,
			fixture.Name .. ": a ScreenGui at " .. kind.Name .. " occupies the"
			.. " rectangle the row states, and an anchored child and a scaled child"
			.. " of it land where that rectangle puts them",
			table.concat(framed, "; "))
	end
	-- Every HUD rectangle the layout hands out must be inside Safe. Weaker than
	-- the frame checks above and kept anyway: these are the bands production
	-- actually positions against, and "inside Safe" is the property they are
	-- promised to have.
	for _, entry in ipairs({
		{"TopBand", fixtureLayout.TopBand}, {"ModalArea", fixtureLayout.ModalArea},
		{"ModalViewport", fixtureLayout.ModalViewport},
	}) do
		local rect = entry[2]
		record(rect.Left >= fixtureLayout.Safe.Left - 0.5
			and rect.Right <= fixtureLayout.Safe.Right + 0.5
			and rect.Top >= fixtureLayout.Safe.Top - 0.5
			and rect.Bottom <= fixtureLayout.Safe.Bottom + 0.5,
			fixture.Name .. ": " .. entry[1] .. " is inside the safe area",
			string.format("(%.0f,%.0f)..(%.0f,%.0f) vs safe (%.0f,%.0f)..(%.0f,%.0f)",
				rect.Left, rect.Top, rect.Right, rect.Bottom,
				fixtureLayout.Safe.Left, fixtureLayout.Safe.Top,
				fixtureLayout.Safe.Right, fixtureLayout.Safe.Bottom))
	end
end

-- A live rectangle in the SAME space its siblings are measured in. Used only
-- for comparisons BETWEEN live rectangles (a child against its parent, a card
-- against its scroll), never against a simulated-viewport figure: the inset and
-- the real-window origin are common to both sides and cancel exactly.
function Fit.live(object)
	if not object then return nil end
	local p, s = object.AbsolutePosition, object.AbsoluteSize
	return {Left = p.X, Top = p.Y, Right = p.X + s.X, Bottom = p.Y + s.Y,
		Width = s.X, Height = s.Y}
end

function Fit.within(inner, outer, slack: number?): boolean
	local give = slack or 1
	return inner ~= nil and outer ~= nil
		and inner.Left >= outer.Left - give and inner.Right <= outer.Right + give
		and inner.Top >= outer.Top - give and inner.Bottom <= outer.Bottom + give
end

function Fit.overlaps(a, b): boolean
	return a ~= nil and b ~= nil
		and a.Left < b.Right and a.Right > b.Left
		and a.Top < b.Bottom and a.Bottom > b.Top
end

function Fit.text(rect): string
	if not rect then return "no rect" end
	return string.format("(%.0f,%.0f)-(%.0f,%.0f) %.0fx%.0f",
		rect.Left, rect.Top, rect.Right, rect.Bottom, rect.Width, rect.Height)
end

-- Does any string anywhere under `root` name a key this device has not got?
function Fit.keyGlyph(root): string?
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
			local text = (node :: any).Text
			if type(text) == "string" and text ~= "" then
				for _, pattern in ipairs(KEYBOARD_PATTERNS) do
					if text:find(pattern) then
						return node.Name .. ": " .. text
					end
				end
			end
		end
	end
	return nil
end

-- Every interactive descendant, with its live rectangle. The tap-target sweep
-- for a panel whose controls are built by a loop and cannot be named up front.
function Fit.interactive(root): {any}
	local found = {}
	for _, node in ipairs(root:GetDescendants()) do
		if (node:IsA("TextButton") or node:IsA("ImageButton"))
			and node.Visible and (node :: any).Active then
			local chain, visible = node.Parent, true
			while chain and not chain:IsA("ScreenGui") do
				if chain:IsA("GuiObject") and not (chain :: GuiObject).Visible then
					visible = false
					break
				end
				chain = chain.Parent
			end
			if visible then
				table.insert(found, {Object = node, Rect = Fit.live(node)})
			end
		end
	end
	return found
end

-- ---------------------------------------------------------------------------
-- ZyntraTerminalFitMatrix
-- ---------------------------------------------------------------------------

-- The matrix the store modal never had. The row that existed before this --
-- `store-modal` -- set an attribute, revealed the ScreenGui and asserted
-- nothing: no Requires, no TouchTargets, and `Terminal` was in
-- FULLSCREEN_OVERLAYS and absent from INTERNAL_PANELS, so not one rectangle
-- inside the terminal was ever measured. It reported green for a panel whose
-- content frame had a NEGATIVE height.
--
-- Two measurement regimes, deliberately, and each is used only where it is
-- valid:
--   * THE SHELL -- terminal, header, tabs, content, status -- is resolved
--     ANALYTICALLY against the simulated viewport, behind the same calibration
--     gate QueueModalMatrix and BriefingFitMatrix use: the resolver must first
--     reproduce the engine to within a pixel at the real viewport.
--   * THE INTERNALS -- pages, cards, dev rows, tabs -- are laid out by
--     UIGridLayout and UIListLayout, which the resolver cannot reproduce and
--     does not pretend to. They are measured LIVE and compared only against
--     other LIVE rectangles (a card against its scroll, a control against its
--     row), where the real-window origin is common to both sides and cancels.
-- Touch targets, at real phone and tablet sizes, driven entirely from Luau.
--
-- RunAll deliberately refuses to run while UIRegressionViewport is set, because
-- its geometry assertions compare measured pixels against a REPORTED viewport
-- and the two diverge under the override. This matrix has no such problem: a
-- 44-pixel minimum is 44 real pixels whatever the screen claims to be, and the
-- layout under test was computed for the simulated size. So it owns the
-- override, sweeps device sizes and both orientations without the Device
-- Simulator, and re-checks keyboard glyphs while it is there -- "can a finger
-- reach this" and "does this print a key I have not got" are both viewport-free
-- questions.
local TOUCH_DEVICES = {
	-- The device the responsive repair was reported on and measured against:
	-- 2868x1320 physical at 3x is 956x440 logical, and it is the widest phone
	-- landscape in the matrix as well as the shortest relative to its width.
	{Name = "iPhone 16 Pro Max landscape 956x440", Size = Vector2.new(956, 440)},
	{Name = "iPhone 16 Pro Max portrait 440x956", Size = Vector2.new(440, 956)},
	{Name = "phone portrait 390x844", Size = Vector2.new(390, 844)},
	{Name = "phone landscape 844x390", Size = Vector2.new(844, 390)},
	{Name = "small phone landscape 568x320", Size = Vector2.new(568, 320)},
	{Name = "small phone landscape 667x375", Size = Vector2.new(667, 375)},
	-- The exact viewport a Galaxy A06 reports in landscape. Every control the
	-- matrix guards was measured here first.
	{Name = "Galaxy A06 landscape 705x338", Size = Vector2.new(705, 338)},
	{Name = "tablet portrait 820x1180", Size = Vector2.new(820, 1180)},
	{Name = "tablet landscape 1180x820", Size = Vector2.new(1180, 820)},
}

function Fit.bodyTouchTargetMatrix(): (string, number)
	-- A REAL briefing is the game's, not ours: this lane calls resetScenario,
	-- which used to silence one. Wait for it, bounded, and refuse rather than
	-- interrupt. Nothing is borrowed or forced before this returns.
	local quiet, quietWhy = Fit.awaitQuietDispatch()
	if not quiet then
		return "=== touch targets: not reached ===\n  FAIL " .. tostring(quietWhy)
			.. "\nTOTAL: 1 checks, 1 failed", 1
	end
	-- (c) A REVERSIBLE SEAM, and therefore NO wait for a live dispatch. This lane
	-- writes exactly two Studio override attributes and puts both back, and the
	-- put-back is asserted at the end rather than assumed. It never reads the
	-- briefing, never forces it and never silences it: a real transmission is
	-- relaid out at each simulated viewport and is exactly where it was once the
	-- overrides come off. There is nothing here for a briefing to be disturbed by.
	local previousViewport = workspace:GetAttribute("UIRegressionViewport")
	local previousTouch = workspace:GetAttribute("ForceTouchUI")
	local report = {"=== touch targets across phone and tablet ==="}
	local stolen = Fit.takeStolenNote()
	if stolen then table.insert(report, "  note " .. stolen) end
	local failures, checks = 0, 0
	local function record(ok, description, detail)
		checks += 1
		if ok then
			-- Compact keeps findings, not confirmations. See C_COMPACT_REPORT_20260831:
			-- five lanes build their own report table instead of using Fit.recorder,
			-- and every one of them printed a line per passing check -- which is why
			-- a "compact" run still came to 103KB.
			if not Fit.Compact then table.insert(report, "  ok   " .. description) end
		else
			failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
		end
	end

	workspace:SetAttribute("ForceTouchUI", true)
	local ran, runError = pcall(function()
		for _, device in ipairs(TOUCH_DEVICES) do
			workspace:SetAttribute("UIRegressionViewport", device.Size)
			-- WAIT FOR IT TO TAKE. A fixed sleep after a deferred attribute
			-- signal measures the previous device on a busy frame.
			-- `device.Size` is nil for the desktop row, which means "clear the
			-- override" -- there is no size to wait for, only a settle.
			if device.Size then
				local spins = 40
				while spins > 0 and not (UIDevice.Layout().Width == device.Size.X
					and UIDevice.Layout().Height == device.Size.Y) do
					task.wait(0.05)
					spins -= 1
				end
			else
				task.wait(0.3)
			end
			-- WAIT FOR IT TO TAKE. A fixed sleep after a deferred
			-- attribute signal measures the previous device on a busy frame.
			do
				local spins = 40
				while spins > 0 and not (UIDevice.Layout().Width == device.Size.X
					and UIDevice.Layout().Height == device.Size.Y) do
					task.wait(0.05)
					spins -= 1
				end
				task.wait(0.2)
			end
			local layout = UIDevice.Layout()
			table.insert(report, string.format("--- %s (reported %.0fx%.0f, class=%s, touch=%s) ---",
				device.Name, layout.Width, layout.Height, layout.Class, tostring(layout.IsTouch)))
			record(layout.IsTouch and layout.Width == device.Size.X
				and layout.Height == device.Size.Y,
				device.Name .. ": the device override took",
				string.format("%.0fx%.0f touch=%s", layout.Width, layout.Height,
					tostring(layout.IsTouch)))

			-- OBSOLETE CONTRACT, REPLACED. This used to require the Level 2
			-- objective panel to stay INSIDE the horizontal control corridor --
			-- the lane down the middle of a landscape phone -- because that is
			-- where it lived. C_OBJECTIVES_UPPER_RIGHT_20260830 moved it, and all
			-- three levels' readouts with it, to the upper right; keeping this
			-- assertion would have required the bottom-centre placement the owner
			-- asked to be rid of.
			--
			-- What replaces it is not weaker: the corridor test only bounded the
			-- panel's X between two numbers, while Fit.anchorProblems checks the
			-- top anchor, both movement-safe right edges, containment in the true
			-- safe area, the right-hand portion of the screen and every movement
			-- zone -- and it is applied here to all THREE levels rather than to
			-- Level 2 alone. ObjectiveCornerMatrix runs the same predicate across
			-- its own device list; this keeps it in the tap-target sweep too.
			for _, spec in ipairs({
				{"PuzzleGui", "Level1Objectives"},
				{"Level2ObjectiveGui", "Level2ObjectivePanel"},
				{"Level3ReaderGui", "ReaderPanel"},
			}) do
				local objectiveGui = findGui(spec[1])
				local objectivePanel = objectiveGui and objectiveGui:FindFirstChild(spec[2], true)
				local objectiveRect = objectivePanel
					and UIRegression.ResolveRect(objectivePanel, device.Size, layout.Inset.Y)
				if objectiveRect and not objectiveRect.Unresolvable then
					local problems = Fit.anchorProblems(objectiveRect, layout, spec[2])
					record(#problems == 0,
						device.Name .. ": " .. spec[2] .. " holds the upper-right safe corner",
						table.concat(problems, "; "))
				else
					record(false, device.Name .. ": " .. spec[2] .. " is measurable",
						objectiveRect and objectiveRect.Unresolvable or "missing")
				end
			end

			for _, scenario in ipairs(UIRegression.Scenarios()) do
				if scenario.TouchTargets then
					scenario.Setup()
					task.wait(.2)
					local result = UIRegression.Check()
					local function findRect(fragment)
						for _, rect in ipairs(result.Rects) do
							if rect.Path:find(fragment, 1, true) then return rect end
						end
						for _, group in ipairs(result.Groups) do
							if group.Path:find(fragment, 1, true) then return group end
							for _, child in ipairs(group.Children) do
								if child.Path:find(fragment, 1, true) then return child end
							end
						end
						return nil
					end
					local viewport = UIDevice.Layout().Viewport
					for _, fragment in ipairs(scenario.TouchTargets) do
						local rect = findRect(fragment)
						if not rect then
							record(false, string.format("%s / %s: %s is on screen",
								device.Name, scenario.Name, fragment), "not measured")
						else
							-- Size, interactivity and activeness only. Position is
							-- deliberately NOT judged here: with the viewport
							-- override active, Studio still renders at its real
							-- window size, so AbsolutePosition is a real-screen
							-- coordinate being compared against a simulated
							-- screen. The geometry half runs below, at the real
							-- viewport, where it means something.
							record(#touchTargetProblems(rect, result.Rects, viewport, false) == 0,
								string.format("%s / %s: %s is interactive, active and at least 44x44",
									device.Name, scenario.Name, fragment),
								table.concat(touchTargetProblems(
									rect, result.Rects, viewport, false), "; "))
						end
					end
					-- Same sweep, same setup: nothing touch-only may print a key.
					record(#result.KeyboardBindings == 0,
						string.format("%s / %s: no keyboard glyph on a touch screen",
							device.Name, scenario.Name),
						table.concat(result.KeyboardBindings, "; "))
				end
			end
		end
	end)

	-- ------------------------------------------------------------------
	-- The geometry half, at the REAL rendered viewport.
	-- ------------------------------------------------------------------
	-- ForceTouchUI alone tells no lies about pixels: the touch LAYOUT is
	-- applied and Studio renders it at its actual window size, so on-screen,
	-- overlap, movement-zone and whole-screen assertions are all valid.
	workspace:SetAttribute("UIRegressionViewport", nil)
	task.wait(.35)
	local geometryRan, geometryError = pcall(function()
		local layout = UIDevice.Layout()
		table.insert(report, string.format(
			"--- real viewport %.0fx%.0f with the touch layout applied ---",
			layout.Width, layout.Height))
		record(layout.IsTouch, "the touch layout is applied at the real viewport")
		for _, scenario in ipairs(UIRegression.Scenarios()) do
			if scenario.TouchTargets then
				scenario.Setup()
				task.wait(.2)
				local result = UIRegression.Check()
				local function findRect(fragment)
					for _, rect in ipairs(result.Rects) do
						if rect.Path:find(fragment, 1, true) then return rect end
					end
					for _, group in ipairs(result.Groups) do
						if group.Path:find(fragment, 1, true) then return group end
						for _, child in ipairs(group.Children) do
							if child.Path:find(fragment, 1, true) then return child end
						end
					end
					return nil
				end
				for _, fragment in ipairs(scenario.TouchTargets) do
					local rect = findRect(fragment)
					if not rect then
						record(false, string.format("real viewport / %s: %s is on screen",
							scenario.Name, fragment), "not measured")
					else
						local problems = touchTargetProblems(
							rect, result.Rects, layout.Viewport, true)
						record(#problems == 0, string.format(
							"real viewport / %s: %s is tappable, on screen, unobstructed"
							.. " and at least 44x44", scenario.Name, fragment),
							table.concat(problems, "; "))
					end
				end
				record(result.Passed == true, string.format(
					"real viewport / %s: the whole screen passes its own geometry checks",
					scenario.Name),
					string.format("%d offscreen, %d overlaps, %d zone hits, %d internal",
						#result.Offscreen, #result.Overlaps,
						#result.MovementZoneHits, #result.InternalOverlaps))
			end
		end
	end)
	if not geometryRan then
		failures += 1
		checks += 1
		table.insert(report, "  FAIL the real-viewport geometry pass ran  ("
			.. tostring(geometryError) .. ")")
	end

	workspace:SetAttribute("UIRegressionViewport", previousViewport)
	workspace:SetAttribute("ForceTouchUI", previousTouch)
	task.wait(.2)
	record(workspace:GetAttribute("UIRegressionViewport") == previousViewport
		and workspace:GetAttribute("ForceTouchUI") == previousTouch,
		"the device overrides were restored")
	if not ran then
		failures += 1
		checks += 1
		table.insert(report, "  FAIL the matrix ran to completion  (" .. tostring(runError) .. ")")
	end
	table.insert(report, string.format("TOTAL: %d checks, %d failed", checks, failures))
	return table.concat(report, "\n"), failures
end

function UIRegression.TouchTargetMatrix(token: string?): (string, number)
	return Fit.lane("TouchTargetMatrix", token, Fit.bodyTouchTargetMatrix)
end

-- ---------------------------------------------------------------------------
-- The analytic resolver, and the device matrix that can actually use it
-- ---------------------------------------------------------------------------
--
-- UIRegressionViewport makes UIDevice REPORT a simulated size while Studio keeps
-- rendering at its real window size, so AbsolutePosition is a real-screen
-- coordinate. The old matrix responded by switching every position assertion OFF
-- under the override and running the geometry half at Studio's real 1694x698 --
-- where the queue panel lands somewhere else entirely. A 705x338 phone was
-- therefore never measured at 705x338 by anything, and a panel sitting squarely
-- under the control column reported green.
--
-- ResolveRect computes what a rect WOULD be at a given viewport, from the UDim2
-- values production actually set, so the override becomes measurable instead of
-- unmeasurable. It refuses to guess: anything whose position the engine computes
-- (a list/grid/table/page layout, padding, an aspect-ratio constraint) comes back
-- Unresolvable, and an Unresolvable target is a FAILURE, never a pass. That rule
-- is what stops this from becoming the old false green in a new form.
--
-- Rects are in SCREEN space -- y = 0 at the top of the viewport -- which is the
-- space UIDevice.Zones is in. Measured AbsolutePosition is NOT: it puts y = 0
-- below the top inset, so live rects are shifted before they are compared.
-- Measured in this place on 2026-08-29: a ScreenGui with IgnoreGuiInset = false
-- reports AbsolutePosition (0,0) with height viewport.Y - inset; one with
-- IgnoreGuiInset = true reports (0, -inset) at full height. Both therefore share
-- one reported space whose origin is inset pixels below the screen top.
local ENGINE_LAID_OUT = {
	UIListLayout = true, UIGridLayout = true, UIPageLayout = true,
	UITableLayout = true, UIPadding = true,
}

-- C_ONE_SAFE_AREA_20260830 / C_RESOLVE_PER_ENUM_20260831.
--
-- There is ONE space and the harness speaks it: `GuiObject.AbsolutePosition`.
-- Measured live on a Studio Device Emulator run (iPhone 16 Pro Max), for all
-- four ScreenInsets values and with the child at a known offset:
--
--   ScreenInsets        gui.AbsolutePosition   gui.AbsoluteSize
--   None                (-62, -58)             955 x 439
--   DeviceSafeInsets    (  0, -58)             831 x 418
--   CoreUISafeInsets    (  0,   0)             831 x 360
--   TopbarSafeInsets    (164, -58)             667 x  58
--
-- and in every case `gui.AbsolutePosition == GuiService:GetInsetArea(
-- gui.ScreenInsets).Min` and `gui.AbsoluteSize` the same rect's size, exactly.
-- So the shift is zero and the resolver's frame is the inset area its gui
-- names -- not a Y-origin heuristic.
function UIRegression.ScreenSpaceShift(object): number
	return 0
end

-- The exact frame a ScreenGui occupies, PER ENUM.
--
-- WHAT SHIPPED BROKEN: this used to classify a gui by comparing its measured
-- AbsolutePosition.Y against the display top and then pick "full display" or
-- "safe area". That is a two-way guess over a four-way property: None and
-- DeviceSafeInsets share a Y origin and differ in X and width, and
-- TopbarSafeInsets shares neither. A gui set to DeviceSafeInsets resolved as if
-- it spanned the whole display, which on a notched device is 124px wider than
-- it is.
function UIRegression.ScreenGuiFrame(screenGui: ScreenGui, viewport: Vector2)
	local kind = screenGui.ScreenInsets
	local area = GuiService:GetInsetArea(kind)
	local layout = UIDevice.Layout()
	-- Under a forced-viewport FIXTURE the engine still renders at the real
	-- window, so the gui's measured size is the real one and scale-sized
	-- children have to resolve against the SIMULATED frame instead. The
	-- fixture's frame is the same inset amounts applied to the fixture display.
	if layout.Synthetic then
		-- C_FIXTURE_FRAMES_ARE_ITS_OWN_20260831 -- WHAT SHIPPED BROKEN.
		--
		-- This used to take the inset AMOUNTS off the live host -- GetInsetArea
		-- differenced against None -- and apply them to the fixture's display,
		-- with Core and Device patched from the fixture's Safe rect and None and
		-- Topbar left entirely to the host. Three consequences, all of which the
		-- suite reported as layout failures:
		--   * a fixture that stated no housing still inherited the emulator's
		--     62px cutout, so "375x667" was measured as a 251px-wide screen;
		--   * TopbarSafeInsets was the HOST's topbar band -- (164,-58)..(831,0)
		--     on this machine -- applied to a 568-wide fixture, which is not a
		--     rectangle any device reports;
		--   * the same row was a different shape on a different machine, so a
		--     stated expectation could not be stated at all.
		--
		-- UIDevice answers all four from the row's own numbers now
		-- (C_INSET_AREAS_ARE_ANSWERED_20260831), including the topbar BAND --
		-- which is the topbar's own strip, not the screen minus it. Ask it.
		local fixture = UIDevice.InsetArea(kind)
		return {
			Left = fixture.Left, Top = fixture.Top,
			Width = math.max(0, fixture.Right - fixture.Left),
			Height = math.max(0, fixture.Bottom - fixture.Top),
		}
	end
	return {
		Left = area.Min.X, Top = area.Min.Y,
		Width = area.Max.X - area.Min.X, Height = area.Max.Y - area.Min.Y,
	}
end

-- Resolve a UDim2 chain ARITHMETICALLY against a stated viewport, returning the
-- rectangle in that same one space, so an analytic edge and a live
-- AbsolutePosition are directly comparable numbers.
function UIRegression.ResolveRect(object, viewport: Vector2, insetY: number)
	local chain, node = {}, object
	while node and not node:IsA("ScreenGui") do
		table.insert(chain, 1, node)
		node = node.Parent
	end
	if not node then return nil end
	local frame = UIRegression.ScreenGuiFrame(node :: ScreenGui, viewport)
	local left, top = frame.Left, frame.Top
	local width, height = frame.Width, frame.Height

	local unresolvable = nil
	for _, child in ipairs(chain) do
		local parent = child.Parent
		if parent then
			for _, sibling in ipairs(parent:GetChildren()) do
				if ENGINE_LAID_OUT[sibling.ClassName] then
					unresolvable = sibling.ClassName .. " on " .. parent.Name
				end
			end
		end
		if child:FindFirstChildOfClass("UIAspectRatioConstraint") then
			unresolvable = "UIAspectRatioConstraint on " .. child.Name
		end
		local w = child.Size.X.Offset + child.Size.X.Scale * width
		local h = child.Size.Y.Offset + child.Size.Y.Scale * height
		local sizeConstraint = child:FindFirstChildOfClass("UISizeConstraint")
		if sizeConstraint then
			w = math.clamp(w, sizeConstraint.MinSize.X, sizeConstraint.MaxSize.X)
			h = math.clamp(h, sizeConstraint.MinSize.Y, sizeConstraint.MaxSize.Y)
		end
		local scale = child:FindFirstChildOfClass("UIScale")
		if scale then w, h = w * scale.Scale, h * scale.Scale end
		local cx = left + child.Position.X.Offset + child.Position.X.Scale * width
		local cy = top + child.Position.Y.Offset + child.Position.Y.Scale * height
		left = cx - w * child.AnchorPoint.X
		top = cy - h * child.AnchorPoint.Y
		width, height = w, h
	end
	return {
		Left = left, Top = top, Right = left + width, Bottom = top + height,
		Width = width, Height = height, Unresolvable = unresolvable,
	}
end

-- Every queue-modal row is an EXPLICIT ADVERSARIAL FIXTURE. Reusing the shared
-- fixtures means Safe, Topbar and all four independently stated ScreenInsets
-- rectangles travel with the viewport instead of inheriting Studio's host
-- geometry. The two 390x844 orientations are additional stated fixtures because
-- that phone width is a required breakpoint but is not in the shared table.
local MODAL_DEVICES = table.clone(Fit.Devices)
table.insert(MODAL_DEVICES, {
	Name = "adversarial 390x844 portrait, no housing",
	Size = Vector2.new(390, 844), Touch = true, Class = "phone", Portrait = true,
	Topbar = {0, 36, 0, 0},
	Frames = {
		None = {0, 0, 390, 844}, DeviceSafeInsets = {0, 0, 390, 844},
		CoreUISafeInsets = {0, 36, 390, 844}, TopbarSafeInsets = {0, 0, 390, 36},
	},
})
table.insert(MODAL_DEVICES, {
	Name = "adversarial 844x390 landscape, no housing",
	Size = Vector2.new(844, 390), Touch = true, Class = "phone", Portrait = false,
	Topbar = {0, 36, 0, 0},
	Frames = {
		None = {0, 0, 844, 390}, DeviceSafeInsets = {0, 0, 844, 390},
		CoreUISafeInsets = {0, 36, 844, 390}, TopbarSafeInsets = {0, 0, 844, 36},
	},
})

-- The five controls the queue modal must always offer, and the labels that must
-- stay inside it. Named, so a control silently disappearing is a failure rather
-- than a shorter loop.
local MODAL_CONTROLS = {"CloseQueue", "DecreasePlayers", "IncreasePlayers", "PrivacyToggle", "CreateParty"}

function Fit.bodyQueueModalMatrix(): (string, number)
	-- A REAL briefing is the game's, not ours: this lane calls resetScenario,
	-- which used to silence one. Wait for it, bounded, and refuse rather than
	-- interrupt. Nothing is borrowed or forced before this returns.
	local quiet, quietWhy = Fit.awaitQuietDispatch()
	if not quiet then
		return "=== queue modal: not reached ===\n  FAIL " .. tostring(quietWhy)
			.. "\nTOTAL: 1 checks, 1 failed", 1
	end
	-- (c) A REVERSIBLE SEAM, and therefore NO wait for a live dispatch. Two Studio
	-- override attributes and one QueueHostShade.Visible flag, all three captured
	-- before and written back after, with the override restore asserted at the
	-- end. Nothing in this lane reads, forces or silences the dispatch, so a real
	-- briefing runs through it untouched.
	local previousWorkspace = {}
	for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
		previousWorkspace[name] = {Value = workspace:GetAttribute(name)}
	end
	local report = {"=== queue modal geometry, resolved per device ==="}
	local stolen = Fit.takeStolenNote()
	if stolen then table.insert(report, "  note " .. stolen) end
	local failures, checks = 0, 0
	local function record(ok, description, detail)
		checks += 1
		if ok then
			-- Compact keeps findings, not confirmations. See C_COMPACT_REPORT_20260831:
			-- five lanes build their own report table instead of using Fit.recorder,
			-- and every one of them printed a line per passing check -- which is why
			-- a "compact" run still came to 103KB.
			if not Fit.Compact then table.insert(report, "  ok   " .. description) end
		else
			failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
		end
	end

	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local shade, panel
	if playerGui then
		for _, descendant in ipairs(playerGui:GetDescendants()) do
			if descendant.Name == "QueueHostShade" then shade = descendant break end
		end
		panel = shade and shade:FindFirstChild("QueueHostPanel")
	end
	if not panel then
		record(false, "the queue modal exists to be measured", "QueueHostPanel not found")
		return table.concat(report, "\n"), failures
	end

	local wasVisible = shade.Visible
	local wasQueueModalOpen = player:GetAttribute("QueueModalOpen")
	local wasMovementSuppressed = UIDevice.TouchMovementSuppressed()
	local expectedControlKeys = {
		TouchRunHold = true, TouchJump = true, TouchPOV = true,
		TouchDropGlowstick = true, TouchSneakHold = true, FlashlightPower = true,
	}
	local function registeredControlState(element: GuiObject): any
		local ancestorsVisible = true
		local screenEnabled: boolean? = nil
		local node: Instance? = element.Parent
		while node ~= nil do
			if node:IsA("GuiObject") and not node.Visible then
				ancestorsVisible = false
			elseif node:IsA("ScreenGui") then
				screenEnabled = node.Enabled
				break
			end
			node = node.Parent
		end
		return {
			Visible = element.Visible,
			Active = element.Active,
			AncestorsVisible = ancestorsVisible,
			ScreenEnabled = screenEnabled,
			Drawn = element.Visible and ancestorsVisible and screenEnabled ~= false
				and element.AbsoluteSize.X > 1 and element.AbsoluteSize.Y > 1,
		}
	end
	local function captureRegisteredCluster(): any
		local snapshot = {Roots = {}, States = {}, Problems = {}}
		for _, element in ipairs(game:GetService("CollectionService")
			:GetTagged("UIDeviceControlRect")) do
			if element:IsA("GuiObject") then
				local key = element:GetAttribute("UIDeviceControlKey")
				if element.Parent == nil then
					table.insert(snapshot.Problems, element.Name .. " is tagged but destroyed")
				elseif type(key) ~= "string" or key == "" then
					table.insert(snapshot.Problems, element.Name .. " has no UIDeviceControlKey")
				elseif snapshot.Roots[key] ~= nil then
					table.insert(snapshot.Problems, "duplicate key " .. key)
				else
					snapshot.Roots[key] = element
				end
				-- The registered rectangle can be visual while a child owns input:
				-- FlashlightPower is exactly that shape. Snapshot the complete GuiObject
				-- subtree so an invisible-but-Active child cannot disappear from the proof.
				snapshot.States[element] = registeredControlState(element)
				for _, descendant in ipairs(element:GetDescendants()) do
					if descendant:IsA("GuiObject") then
						snapshot.States[descendant] = registeredControlState(descendant)
					end
				end
			end
		end
		return snapshot
	end
	local function expectedClusterProblems(snapshot): {string}
		local problems = table.clone(snapshot.Problems)
		for key in pairs(expectedControlKeys) do
			if snapshot.Roots[key] == nil then table.insert(problems, "missing key " .. key) end
		end
		for key in pairs(snapshot.Roots) do
			if not expectedControlKeys[key] then table.insert(problems, "unexpected key " .. key) end
		end
		return problems
	end
	local function clusterIdentityProblems(before, after): {string}
		local problems = table.clone(after.Problems)
		for key, root in pairs(before.Roots) do
			if after.Roots[key] ~= root then table.insert(problems, "changed/missing root " .. key) end
		end
		for key in pairs(after.Roots) do
			if before.Roots[key] == nil then table.insert(problems, "new root " .. key) end
		end
		for object in pairs(before.States) do
			if after.States[object] == nil then table.insert(problems, object.Name .. " disappeared") end
		end
		for object in pairs(after.States) do
			if before.States[object] == nil then table.insert(problems, object.Name .. " appeared") end
		end
		return problems
	end
	local function clusterRestorationProblems(before, after): {string}
		local problems = clusterIdentityProblems(before, after)
		for object, beforeState in pairs(before.States) do
			local afterState = after.States[object]
			if afterState then
				for _, field in ipairs({"Visible", "Active", "AncestorsVisible", "ScreenEnabled", "Drawn"}) do
					if afterState[field] ~= beforeState[field] then
						table.insert(problems, string.format("%s.%s %s->%s", object.Name, field,
							tostring(beforeState[field]), tostring(afterState[field])))
					end
				end
			end
		end
		return problems
	end
	local initialCluster = captureRegisteredCluster()
	local ran, runError = pcall(function()
		-- ------------------------------------------------------------------
		-- CALIBRATION. Before trusting the resolver anywhere, prove it agrees
		-- with the engine at the REAL viewport, where AbsolutePosition is true.
		-- A resolver that is wrong in the same direction as the code it checks
		-- is worth nothing, and this is the only thing that rules that out.
		-- ------------------------------------------------------------------
		for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
			workspace:SetAttribute(name, nil)
		end
		shade.Visible = true
		task.wait(0.35)
		local realLayout = UIDevice.Layout()
		local shift = UIRegression.ScreenSpaceShift(panel)
		local worst, worstName = 0, ""
		local targets = {panel}
		for _, name in ipairs(MODAL_CONTROLS) do
			local control = panel:FindFirstChild(name, true)
			if control then table.insert(targets, control) end
		end
		for _, object in ipairs(targets) do
			local resolved = UIRegression.ResolveRect(object, realLayout.Viewport, realLayout.Inset.Y)
			if resolved and not resolved.Unresolvable then
				local live = {
					Left = object.AbsolutePosition.X,
					Top = object.AbsolutePosition.Y + shift,
					Right = object.AbsolutePosition.X + object.AbsoluteSize.X,
					Bottom = object.AbsolutePosition.Y + object.AbsoluteSize.Y + shift,
				}
				for _, edge in ipairs({"Left", "Top", "Right", "Bottom"}) do
					local delta = math.abs(resolved[edge] - live[edge])
					if delta > worst then worst, worstName = delta, object.Name .. "." .. edge end
				end
			end
		end
		record(worst <= 1, "the resolver agrees with the engine at the real viewport",
			string.format("worst edge error %.2fpx at %s", worst, worstName))
		shade.Visible = false
		task.wait(0.2)

		-- ------------------------------------------------------------------
		-- The sweep, at each simulated device.
		-- ------------------------------------------------------------------
		for _, device in ipairs(MODAL_DEVICES) do
			local applied = Fit.apply(device)
			record(applied, device.Name .. ": the explicit fixture took", "timed out")
			local fixtureProblems = Fit.fixtureProblems(device)
			record(#fixtureProblems == 0,
				device.Name .. ": viewport, safe area and topbar are exactly the stated fixture",
				table.concat(fixtureProblems, "; "))
			local registeredBefore = nil
			if device.Touch then
				registeredBefore = captureRegisteredCluster()
				local authoredProblems = expectedClusterProblems(registeredBefore)
				record(#authoredProblems == 0,
					device.Name .. ": exactly the six authored registered-control keys are present",
					table.concat(authoredProblems, "; "))
				local activeBefore = 0
				for object, state in pairs(registeredBefore.States) do
					if object:IsA("GuiButton") and state.Active then activeBefore += 1 end
				end
				record(activeBefore > 0,
					device.Name .. ": at least one real registered input surface is active before open",
					string.format("%d active GuiButtons", activeBefore))
			end
			shade.Visible = true
			task.wait(0.3)
			local layout = UIDevice.Layout()
			local viewport, insetY = device.Size, layout.Inset.Y

			record(layout.Width == device.Size.X and layout.Height == device.Size.Y,
				device.Name .. ": the device override took",
				string.format("%.0fx%.0f", layout.Width, layout.Height))
			record(layout.IsTouch == device.Touch and layout.Class == device.Class
				and layout.Portrait == device.Portrait,
				device.Name .. ": form factor, class and orientation are as declared",
				string.format("touch=%s class=%s portrait=%s",
					tostring(layout.IsTouch), tostring(layout.Class), tostring(layout.Portrait)))
			if device.Touch then
				record(UIDevice.TouchMovementSuppressed() == true,
					device.Name .. ": opening the real queue shade suppresses touch movement",
					tostring(UIDevice.TouchMovementSuppressed()))
				local registeredDuring = captureRegisteredCluster()
				local membershipProblems = expectedClusterProblems(registeredDuring)
				for _, problem in ipairs(clusterIdentityProblems(registeredBefore, registeredDuring)) do
					table.insert(membershipProblems, problem)
				end
				record(#membershipProblems == 0,
					device.Name .. ": opening the shade neither drops nor creates a registered control",
					table.concat(membershipProblems, "; "))
				local drawn, active = 0, 0
				local activeNames = {}
				for _, element in pairs(registeredDuring.Roots) do
					if registeredDuring.States[element].Drawn then drawn += 1 end
				end
				for object, state in pairs(registeredDuring.States) do
					-- Active is intentionally independent of visibility. The actual
					-- input owner may be a child of the registered visual root.
					if state.Active then
						active += 1
						table.insert(activeNames, object.Name)
					end
				end
				record(drawn == 0 and active == 0,
					device.Name .. ": registered roots and every child hit target are not drawn or active",
					string.format("%d drawn roots, %d active objects: %s", drawn, active,
						table.concat(activeNames, ",")))
			end

			local panelRect = UIRegression.ResolveRect(panel, viewport, insetY)
			record(panelRect ~= nil and panelRect.Unresolvable == nil,
				device.Name .. ": the modal is analytically resolvable",
				panelRect and panelRect.Unresolvable or "no rect")
			if panelRect and not panelRect.Unresolvable then
				-- ON SCREEN means inside the DISPLAY rectangle. In the one space
				-- y = 0 is the bottom of the topbar and the display starts one
				-- topbar ABOVE it, so the old `>= -1` bound was simultaneously
				-- too strict at the top and blind to content under the topbar.
				-- The panel must also clear the topbar itself, which is what the
				-- Safe.Top term says.
				record(panelRect.Left >= layout.Display.Left - 1
					and panelRect.Top >= layout.Safe.Top - 1
					and panelRect.Right <= layout.Display.Right + 1
					and panelRect.Bottom <= layout.Display.Bottom + 1,
					device.Name .. ": the modal is fully on screen and clear of the topbar",
					string.format("x %.0f..%.0f y %.0f..%.0f", panelRect.Left, panelRect.Right,
						panelRect.Top, panelRect.Bottom))
				-- THE assertion the old matrix could not make.
				local zone = device.Touch and UIDevice.OverlapsMovementZone(
					panelRect.Left, panelRect.Top, panelRect.Right, panelRect.Bottom) or nil
					record(zone == nil,
					device.Name .. ": the modal is clear of every movement/control column",
						zone and (zone .. " zone") or nil)
				record(panelRect.Left >= layout.Safe.Left - 1
					and panelRect.Top >= layout.Safe.Top - 1
					and panelRect.Right <= layout.Safe.Right + 1
					and panelRect.Bottom <= layout.Safe.Bottom + 1,
					device.Name .. ": the modal is inside the physical safe rectangle on all four edges",
					string.format("panel %.0f,%.0f..%.0f,%.0f safe %.0f,%.0f..%.0f,%.0f",
						panelRect.Left, panelRect.Top, panelRect.Right, panelRect.Bottom,
						layout.Safe.Left, layout.Safe.Top, layout.Safe.Right, layout.Safe.Bottom))
				record(panelRect.Left >= layout.SafeLeft - 1
					and panelRect.Right <= layout.SafeRight + 1,
					device.Name .. ": and inside the authored horizontal HUD gutter",
					string.format("%.0f..%.0f vs %.0f..%.0f", panelRect.Left, panelRect.Right,
						layout.SafeLeft, layout.SafeRight))
			end

			local rects = {}
			for _, name in ipairs(MODAL_CONTROLS) do
				local control = panel:FindFirstChild(name, true)
				local rect = control and UIRegression.ResolveRect(control, viewport, insetY)
				record(control ~= nil and rect ~= nil and rect.Unresolvable == nil,
					string.format("%s: %s is present and resolvable", device.Name, name),
					control == nil and "missing" or (rect and rect.Unresolvable) or "no rect")
				if control and rect and not rect.Unresolvable then
					rects[name] = rect
					record(control.Visible and control.Active and control.Interactable ~= false,
						string.format("%s: %s is visible, active and interactive", device.Name, name),
						string.format("visible=%s active=%s", tostring(control.Visible), tostring(control.Active)))
					if device.Touch then
						record(rect.Width >= 44 and rect.Height >= 44,
							string.format("%s: %s is at least 44x44", device.Name, name),
							string.format("%.0fx%.0f", rect.Width, rect.Height))
					end
					record(rect.Left >= layout.Safe.Left - 1
						and rect.Top >= layout.Safe.Top - 1
						and rect.Right <= layout.Safe.Right + 1
						and rect.Bottom <= layout.Safe.Bottom + 1,
						string.format("%s: %s stays inside the physical safe rectangle",
							device.Name, name),
						string.format("x %.0f..%.0f y %.0f..%.0f", rect.Left, rect.Right, rect.Top, rect.Bottom))
					local hit = device.Touch and UIDevice.OverlapsMovementZone(
						rect.Left, rect.Top, rect.Right, rect.Bottom) or nil
					record(hit == nil,
						string.format("%s: %s does not overlap a mobile control column",
							device.Name, name), hit and (hit .. " zone") or nil)
					if panelRect and not panelRect.Unresolvable then
						record(rect.Left >= panelRect.Left - 1 and rect.Right <= panelRect.Right + 1
							and rect.Top >= panelRect.Top - 1 and rect.Bottom <= panelRect.Bottom + 1,
							string.format("%s: %s stays inside the modal", device.Name, name))
					end
				end
			end
			-- Pairwise: no two controls may sit on top of each other.
			for indexA = 1, #MODAL_CONTROLS do
				for indexB = indexA + 1, #MODAL_CONTROLS do
					local a, b = rects[MODAL_CONTROLS[indexA]], rects[MODAL_CONTROLS[indexB]]
					if a and b then
						record(not (a.Left < b.Right - 1 and a.Right > b.Left + 1
							and a.Top < b.Bottom - 1 and a.Bottom > b.Top + 1),
							string.format("%s: %s and %s do not overlap", device.Name,
								MODAL_CONTROLS[indexA], MODAL_CONTROLS[indexB]))
					end
				end
			end
			-- No keybinding glyph may reach a touch screen.
			if device.Touch then
				record(UIDevice.SuppressesKeyboardGlyphs(),
					device.Name .. ": keyboard glyphs are suppressed")
			end
			shade.Visible = false
			task.wait(0.15)
			if device.Touch then
				record(UIDevice.TouchMovementSuppressed() == false,
					device.Name .. ": closing the queue shade restores touch movement",
					tostring(UIDevice.TouchMovementSuppressed()))
				local registeredAfter = captureRegisteredCluster()
				local restorationProblems = expectedClusterProblems(registeredAfter)
				for _, problem in ipairs(clusterRestorationProblems(registeredBefore, registeredAfter)) do
					table.insert(restorationProblems, problem)
				end
				record(#restorationProblems == 0,
					device.Name .. ": closing the shade restores every registered control state",
					table.concat(restorationProblems, "; "))
			end
		end
	end)

	for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
		workspace:SetAttribute(name, previousWorkspace[name].Value)
	end
	shade.Visible = wasVisible
	task.wait(0.35)
	if not ran then
		failures += 1
		checks += 1
		table.insert(report, "  FAIL the queue modal matrix ran  (" .. tostring(runError) .. ")")
	end
	local restored = true
	for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
		if workspace:GetAttribute(name) ~= previousWorkspace[name].Value then
			restored = false
			break
		end
	end
	record(restored, "the matrix restored every simulator/inset attribute it borrowed")
	record(shade.Visible == wasVisible
		and player:GetAttribute("QueueModalOpen") == wasQueueModalOpen
		and UIDevice.TouchMovementSuppressed() == wasMovementSuppressed,
		"the matrix restored the real shade, derived queue flag and movement state",
		string.format("shade=%s/%s queue=%s/%s suppressed=%s/%s",
			tostring(shade.Visible), tostring(wasVisible),
			tostring(player:GetAttribute("QueueModalOpen")), tostring(wasQueueModalOpen),
			tostring(UIDevice.TouchMovementSuppressed()), tostring(wasMovementSuppressed)))
	local finalClusterProblems = clusterRestorationProblems(initialCluster, captureRegisteredCluster())
	record(#finalClusterProblems == 0,
		"the matrix restored the registered key set, roots and complete GuiObject state on final cleanup",
		table.concat(finalClusterProblems, "; "))
	table.insert(report, string.format("queue modal matrix: %d checks, %d failed", checks, failures))
	return table.concat(report, "\n"), failures
end

function UIRegression.QueueModalMatrix(token: string?): (string, number)
	return Fit.lane("QueueModalMatrix", token, Fit.bodyQueueModalMatrix)
end

-- ---------------------------------------------------------------------------
-- Briefing text fit, resolved per device
-- ---------------------------------------------------------------------------
--
-- The dispatch panel is the one place in the HUD where the layout sizes a
-- rectangle and something else entirely fills it with a sentence. RoundUI's
-- `updateLevelOneGuideLayout` reserves the subtitle box arithmetically --
-- `textTop = math.max(28, controlsTop + controlsHeight + (touch and 0 or 2))`,
-- RoundUI L2425 -- and on a TOUCH row that picks OwnBand with two 44px columns
-- that lands the box top at exactly y = 74, the same pixel where the MUTE/STOP
-- row ends. Nothing hard-codes 74; it falls out of the arithmetic, and the two
-- rectangles ABUT by design. Abutment is fine. One pixel of real penetration is
-- the defect this file already exists to catch, and neither case was ever
-- asserted anywhere but at whatever viewport Studio happened to be rendering.
--
-- Worse, the boxes were the only thing ever checked. Whether the COPY fits the
-- box it was handed had exactly one automated assertion -- `TextFitTargets`
-- inside RunAll -- and that one reads the engine's `TextBounds` PROPERTY, which
-- can only describe the string currently on screen at the size currently
-- rendered. RunAll also refuses to start while `UIRegressionViewport` is set,
-- so it can never speak about any viewport but the real one. Every claim that
-- a 113-character cue fits on a 568x320 phone came from a human looking at the
-- Device Simulator.
--
-- This matrix asks arithmetically instead: ResolveRect for the boxes,
-- TextService:GetTextBoundsAsync for the copy. It is deliberately pessimistic
-- about what it may resolve. `BriefingControls` holds a UIListLayout, so the
-- two buttons inside it are ENGINE-placed and ResolveRect correctly refuses
-- them -- so the CONTAINER is resolved, and the buttons are measured against
-- its resolved extent and the list layout's own declared padding, rather than
-- pretending the resolver can place what the engine places.

-- LOCALISATION STRESS CORPUS.
--
-- This is a PROXY for the shipped copy, not a mirror of it. UIRegression lives
-- in ReplicatedStorage and the cues live in a LocalScript under
-- StarterPlayerScripts, which cannot be required from here, so the strings are
-- transcribed by hand and MUST be re-synced when the cue tables change. Their
-- sources, all in StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua:
--
--   L1917-1932  briefingCues             -- Level 1
--   L1934-1949  levelTwoBriefingCues     -- Level 2
--   L1952-1971  levelThreeBriefing.cues  -- Level 3
--   L1525-1543  lobbyBriefing.cues       -- the concourse briefing
--
-- The longest authored line across all four tables is RoundUI L1940 at 113
-- characters, and it is reproduced here verbatim. LONG_DISPATCH_CUE (L610 of
-- this file, 142 characters) is the string the live `briefing` scenario already
-- forces into the panel, so both matrices stress the same worst case. The third
-- entry is SYNTHETIC: 181 characters, 1.60x the longest authored line, standing
-- in for a localisation of it. German is the useful shape here -- the same
-- sentence runs long AND carries compounds the wrapper cannot break.
local BRIEFING_STRESS_CORPUS = {
	{
		Name = "the longest authored cue (RoundUI L1940, 113 chars)",
		Text = "Even more important: activating a pump appears to alert an unidentified, unusually large entity to your location.",
	},
	{
		Name = "LONG_DISPATCH_CUE (142 chars)",
		Text = LONG_DISPATCH_CUE,
	},
	{
		Name = "a synthetic 1.60x localisation (181 chars)",
		Text = "Noch wichtiger: das Aktivieren einer Pumpstation alarmiert offenbar eine bislang nicht identifizierte, ungewoehnlich grosse Entitaet und verraet ihr eure derzeitige Position sofort.",
	},
}

-- Every caption the two readouts can actually print, from RoundUI's
-- `dispatchAudio.refresh` (L128-165). "SAVING" is omitted deliberately: it is
-- strictly shorter than the four below and cannot fail a width they pass. The
-- "[M]" / "[N]" prefixes come from UIDevice.Binding and are never emitted on a
-- touch form factor, so they are prepended only on the desktop rows.
local BRIEFING_CONTROL_CAPTIONS = {
	DispatchMuteButton = {
		Binding = "[M]  ",
		Captions = {"MUTE DISPATCH", "UNMUTE DISPATCH", "LOADING DISPATCH", "DISPATCH OFFLINE"},
	},
	DispatchStopButton = {
		Binding = "[N]  ",
		Captions = {"STOP DISPATCH"},
	},
}
local BRIEFING_CONTROL_ORDER = {"DispatchMuteButton", "DispatchStopButton"}

-- The rows of MODAL_DEVICES this matrix sweeps: every PORTRAIT row, plus the
-- four short landscape shapes where the panel has the least vertical room and
-- the layout is driven into its compromise pass. Landscape rows are keyed by
-- size rather than by device name, so a renamed row cannot silently drop out.
local BRIEFING_LANDSCAPE_ROWS = {
	-- The reference device for the compact-briefing repair.
	["956x440"] = true,
	["705x338"] = true,  -- Galaxy A06, the shape the panel shipped broken on
	["568x320"] = true,  -- the smallest viewport in the matrix
	["844x390"] = true,  -- iPhone landscape
	["667x375"] = true,  -- iPhone SE landscape
}

local function briefingDevices(): {any}
	local rows = {}
	for _, device in ipairs(MODAL_DEVICES) do
		local key = string.format("%.0fx%.0f", device.Size.X, device.Size.Y)
		if device.Portrait or BRIEFING_LANDSCAPE_ROWS[key] then
			table.insert(rows, device)
		end
	end
	return rows
end

-- The overlap predicate for ANALYTICAL rects.
--
-- `rectsOverlap` above carries a one-pixel slack in every direction, and it is
-- right to: it compares MEASURED AbsolutePosition, where a shared edge can
-- round into a pixel of apparent penetration. These rects are not measured,
-- they are exact arithmetic over the UDim2 values production sets, so the same
-- slack would swallow a genuine one-pixel collision -- precisely the failure
-- this matrix exists to find, given the subtitle box is authored to land ON the
-- controls' lower edge. Half-open comparison instead, which is what the
-- rectsOverlap COMMENT describes: a shared edge (subtitle top 74, controls
-- bottom 74) is abutment and passes; one pixel of real penetration (subtitle
-- top 73) is an overlap and fails.
local function analyticalOverlap(a: any, b: any): boolean
	return a.Left < b.Right and a.Right > b.Left
		and a.Top < b.Bottom and a.Bottom > b.Top
end

function Fit.bodyBriefingFitMatrix(): (string, number)
	local previousWorkspace = {}
	for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
		previousWorkspace[name] = {Value = workspace:GetAttribute(name)}
	end
	local report = {"=== briefing text fit, resolved per device ==="}
	local stolen = Fit.takeStolenNote()
	if stolen then table.insert(report, "  note " .. stolen) end
	local failures, checks = 0, 0
	-- (b) AWAIT ITS NATURAL END, BOUNDED. This lane forces the briefing screen,
	-- its panel and its controls Visible and then writes back the flags it found,
	-- which is reversible only if the briefing is in the same state at the end as
	-- at the start. Run it across a real transmission that finishes mid-sweep and
	-- the restore RE-SHOWS a briefing panel production had just put away -- a
	-- disturbance of a live dispatch, arriving disguised as a cleanup. So it waits
	-- for a quiet dispatch like the lanes that force the flag outright.
	local quiet, dispatchWhy = Fit.awaitQuietDispatch()
	if not quiet then
		failures += 1
		checks += 1
		table.insert(report, "  FAIL " .. tostring(dispatchWhy))
		table.insert(report, string.format("TOTAL: %d checks, %d failed", checks, failures))
		return table.concat(report, "\n"), failures
	end
	local function record(ok, description, detail)
		checks += 1
		if ok then
			-- Compact keeps findings, not confirmations. See C_COMPACT_REPORT_20260831:
			-- five lanes build their own report table instead of using Fit.recorder,
			-- and every one of them printed a line per passing check -- which is why
			-- a "compact" run still came to 103KB.
			if not Fit.Compact then table.insert(report, "  ok   " .. description) end
		else
			failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
		end
	end

	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	local guide = gui and gui:FindFirstChild("LevelOneGuideGui")
	local panel = guide and guide:FindFirstChild("CommandSubtitles")
	local subtitle = panel and panel:FindFirstChild("Subtitle")
	local controls = panel and panel:FindFirstChild("BriefingControls")
	local listLayout = controls and controls:FindFirstChildOfClass("UIListLayout")
	local buttons = {}
	for _, name in ipairs(BRIEFING_CONTROL_ORDER) do
		buttons[name] = controls and controls:FindFirstChild(name)
	end
	if not (guide and panel and subtitle and controls and listLayout
		and buttons.DispatchMuteButton and buttons.DispatchStopButton) then
		record(false, "the briefing panel exists to be measured", string.format(
			"guide=%s panel=%s subtitle=%s controls=%s layout=%s mute=%s stop=%s",
			tostring(guide ~= nil), tostring(panel ~= nil), tostring(subtitle ~= nil),
			tostring(controls ~= nil), tostring(listLayout ~= nil),
			tostring(buttons.DispatchMuteButton ~= nil),
			tostring(buttons.DispatchStopButton ~= nil)))
		table.insert(report, string.format("TOTAL: %d checks, %d failed", checks, failures))
		return table.concat(report, "\n"), failures
	end

	-- GetTextBoundsAsync yields and can throw (a font that has not finished
	-- loading, a malformed params object). It is called from this matrix's own
	-- thread, and every call is wrapped, so a service hiccup is reported as a
	-- failed check rather than unwinding the sweep and stranding the override.
	--
	-- `width` is the WRAP width and is passed only for text that actually wraps.
	-- GetTextBoundsParams.Width defaults to infinity, and leaving it there is the
	-- correct model for the two readouts: TextWrapped is false on them, so the
	-- engine lays them out on one line and lets them spill. Handing the params a
	-- width would have wrapped the measurement the engine never wraps, reporting
	-- a caption that overruns its hitbox as comfortably inside it.
	-- Hoisted to Fit.measureText, which DispatchCompactMatrix shares. Bound to
	-- a local here so every call site below reads unchanged.
	local requiredBounds = Fit.measureText

	-- One cast each, up front. Everything below writes through these, so no
	-- assignment target in this function is a parenthesised cast.
	local screen = guide :: any
	local panelObject = panel :: any
	local controlsObject = controls :: any
	local subtitleLabel = subtitle :: any
	local wasEnabled = screen.Enabled
	local wasPanelVisible = panelObject.Visible
	local wasControlsVisible = controlsObject.Visible
	local wasSubtitleText = subtitleLabel.Text
	local ran, runError = pcall(function()
		-- ------------------------------------------------------------------
		-- CALIBRATION. The sweep below never measures anything: it computes.
		-- A resolver that is wrong in the same direction as the layout it
		-- checks reports green for a broken panel, so before any simulated
		-- viewport is touched, prove the resolver reproduces the ENGINE at the
		-- REAL viewport -- the one place AbsolutePosition is trustworthy --
		-- within one pixel, for the panel, the subtitle box and the controls
		-- row. If it does not, that is a recorded FAILURE and this matrix is
		-- already red no matter what the sweep goes on to say.
		-- ------------------------------------------------------------------
		for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
			workspace:SetAttribute(name, nil)
		end
		screen.Enabled = true
		panelObject.Visible = true
		controlsObject.Visible = true
		task.wait(0.35)
		local realLayout = UIDevice.Layout()
		local shift = UIRegression.ScreenSpaceShift(panel)
		local worst, worstName = 0, ""
		for _, object in ipairs({panel, subtitle, controls}) do
			local resolved = UIRegression.ResolveRect(object, realLayout.Viewport, realLayout.Inset.Y)
			local node = object :: any
			if resolved and not resolved.Unresolvable then
				local live = {
					Left = node.AbsolutePosition.X,
					Top = node.AbsolutePosition.Y + shift,
					Right = node.AbsolutePosition.X + node.AbsoluteSize.X,
					Bottom = node.AbsolutePosition.Y + node.AbsoluteSize.Y + shift,
				}
				for _, edge in ipairs({"Left", "Top", "Right", "Bottom"}) do
					local delta = math.abs(resolved[edge] - live[edge])
					if delta > worst then worst, worstName = delta, object.Name .. "." .. edge end
				end
			else
				worst = math.huge
				worstName = object.Name .. " is unresolvable at the real viewport"
			end
		end
		record(worst <= 1,
			"the resolver agrees with the engine at the real viewport, for the panel,"
			.. " the Subtitle box and the BriefingControls row",
			string.format("worst edge error %.2fpx at %s", worst, worstName))

		-- ------------------------------------------------------------------
		-- The sweep, at each simulated device.
		-- ------------------------------------------------------------------
		for _, device in ipairs(briefingDevices()) do
			local applied = Fit.apply(device)
			record(applied, device.Name .. ": the explicit fixture took", "timed out")
			local fixtureProblems = Fit.fixtureProblems(device)
			record(#fixtureProblems == 0,
				device.Name .. ": viewport, safe area and topbar are exactly the stated fixture",
				table.concat(fixtureProblems, "; "))
			screen.Enabled = true
			panelObject.Visible = true
			controlsObject.Visible = true
			-- Long enough for UIDevice's attribute watcher to refresh, fire
			-- Changed, and for RoundUI's updateLevelOneGuideLayout to have
			-- written every Size, Position and TextSize this row depends on.
			task.wait(0.3)
			local layout = UIDevice.Layout()
			local viewport, insetY = device.Size, layout.Inset.Y

			record(layout.Width == device.Size.X and layout.Height == device.Size.Y,
				device.Name .. ": the device override took",
				string.format("%.0fx%.0f", layout.Width, layout.Height))
			record(layout.IsTouch == device.Touch and layout.Class == device.Class
				and layout.Portrait == device.Portrait,
				device.Name .. ": form factor, class and orientation are as declared",
				string.format("touch=%s class=%s portrait=%s",
					tostring(layout.IsTouch), tostring(layout.Class), tostring(layout.Portrait)))

			local panelRect = UIRegression.ResolveRect(panel, viewport, insetY)
			local subtitleRect = UIRegression.ResolveRect(subtitle, viewport, insetY)
			local controlsRect = UIRegression.ResolveRect(controls, viewport, insetY)
			-- Unresolvable is a FAILURE, never a skip. An analytical matrix that
			-- quietly stops asserting the moment it meets something it cannot
			-- compute is the old false green wearing a new report format.
			record(panelRect ~= nil and panelRect.Unresolvable == nil,
				device.Name .. ": the briefing panel is analytically resolvable",
				panelRect and panelRect.Unresolvable or "no rect")
			record(subtitleRect ~= nil and subtitleRect.Unresolvable == nil,
				device.Name .. ": the Subtitle box is analytically resolvable",
				subtitleRect and subtitleRect.Unresolvable or "no rect")
			record(controlsRect ~= nil and controlsRect.Unresolvable == nil,
				device.Name .. ": the BriefingControls row is analytically resolvable",
				controlsRect and controlsRect.Unresolvable or "no rect")

			local havePanel = panelRect ~= nil and panelRect.Unresolvable == nil
			local haveSubtitle = subtitleRect ~= nil and subtitleRect.Unresolvable == nil
			local haveControls = controlsRect ~= nil and controlsRect.Unresolvable == nil

			-- ── the panel against the WORLD, not just against itself ─────────
			-- WHAT SHIPPED BROKEN: every assertion in this matrix compared the
			-- panel's children to the panel. Nothing compared the PANEL to the
			-- screen, to UIDevice's TopBand, or to a movement zone -- so a panel
			-- that grew straight out of its band and down into the thumbstick's
			-- activation region read GREEN. Proven by mutation: removing the
			-- BAND_CEILING clamp in RoundUI changed not one check here.
			local deviceLayout = UIDevice.Layout()
			local band = deviceLayout.TopBand
			record(havePanel
				and panelRect.Left >= -1 and panelRect.Top >= -1
				and panelRect.Right <= viewport.X + 1
				and panelRect.Bottom <= viewport.Y + 1,
				device.Name .. ": the briefing panel is entirely on screen",
				havePanel and string.format("x %.0f..%.0f y %.0f..%.0f",
					panelRect.Left, panelRect.Right, panelRect.Top, panelRect.Bottom) or "no rect")
			if device.Touch and band and band.Height and band.Height > 0 then
				-- SPACES, RESTATED -- the old note here was wrong, and being wrong
				-- is what hid C_GUI_INSET_OFF_BY_ONE_20260830 for a release.
				--
				-- It claimed "UIDevice's TopBand and movement zones are expressed
				-- in the same space AbsolutePosition uses -- which excludes that
				-- inset", and subtracted an inset from the resolved rect before
				-- comparing. They are not: UIDevice builds bandTop from
				-- `usableTop = GetGuiInset().Y`, and its control zone was measured
				-- against the live RUN/JUMP cluster and only contains it in TRUE
				-- SCREEN space. Both sides of this comparison are true screen.
				--
				-- The subtraction was compensating for the SAME inset error in
				-- UIDevice.TopOffsetFor, which placed every touch panel one inset
				-- below the rectangle it had been fitted to. Two errors cancelled
				-- and a panel hanging an inset out of its band reported green.
				-- TopOffsetFor is fixed; this conversion is therefore gone, and
				-- the comparison is now made in one space with no conversion at
				-- all -- which is the only version of it that can fail.
				-- THE PANEL'S HOME, by the same rule production uses: the top band
				-- while it can hold a briefing, and UIDevice's movement-free
				-- ModalArea when it cannot. Asserting TopBand unconditionally
				-- would demand the panel stay in a 37px strip that cannot hold
				-- two 44px readouts.
				local home = band
				if band.Height < 80 and deviceLayout.ModalArea.Height > band.Height then
					home = deviceLayout.ModalArea
				end
				local guiTop = panelRect.Top
				local guiBottom = panelRect.Bottom
				record(havePanel
					and guiTop >= home.Top - 1
					and guiBottom <= home.Top + home.Height + 1
					and panelRect.Left >= home.Left - 1
					and panelRect.Right <= home.Left + home.Width + 1,
					device.Name .. ": and fits inside the rectangle it was given"
					.. " (top band, or ModalArea where the band is too short)",
					havePanel and string.format("panel y %.0f..%.0f vs band y %.0f..%.0f",
						guiTop, guiBottom, home.Top, home.Top + home.Height) or "no rect")
				local zone = havePanel and UIDevice.OverlapsMovementZone(
					panelRect.Left, guiTop, panelRect.Right, guiBottom) or nil
				record(havePanel and zone == nil,
					device.Name .. ": and enters no movement zone",
					tostring(zone))
			end

			record(havePanel and haveSubtitle
				and subtitleRect.Left >= panelRect.Left - 1
				and subtitleRect.Right <= panelRect.Right + 1
				and subtitleRect.Top >= panelRect.Top - 1
				and subtitleRect.Bottom <= panelRect.Bottom + 1,
				device.Name .. ": the Subtitle box stays inside the panel",
				(havePanel and haveSubtitle) and string.format(
					"subtitle x %.0f..%.0f y %.0f..%.0f in panel x %.0f..%.0f y %.0f..%.0f",
					subtitleRect.Left, subtitleRect.Right, subtitleRect.Top, subtitleRect.Bottom,
					panelRect.Left, panelRect.Right, panelRect.Top, panelRect.Bottom)
					or "unresolvable")
			record(havePanel and haveControls
				and controlsRect.Left >= panelRect.Left - 1
				and controlsRect.Right <= panelRect.Right + 1
				and controlsRect.Top >= panelRect.Top - 1
				and controlsRect.Bottom <= panelRect.Bottom + 1,
				device.Name .. ": the BriefingControls row stays inside the panel",
				(havePanel and haveControls) and string.format(
					"controls x %.0f..%.0f y %.0f..%.0f in panel x %.0f..%.0f y %.0f..%.0f",
					controlsRect.Left, controlsRect.Right, controlsRect.Top, controlsRect.Bottom,
					panelRect.Left, panelRect.Right, panelRect.Top, panelRect.Bottom)
					or "unresolvable")
			-- THE assertion this matrix was written for. Abutment passes, one
			-- pixel of penetration does not; see analyticalOverlap above.
			record(haveSubtitle and haveControls
				and not analyticalOverlap(subtitleRect, controlsRect),
				device.Name .. ": the Subtitle box does not overlap the MUTE/STOP row",
				(haveSubtitle and haveControls) and string.format(
					"subtitle (%.0f,%.0f)-(%.0f,%.0f) vs controls (%.0f,%.0f)-(%.0f,%.0f)",
					subtitleRect.Left, subtitleRect.Top, subtitleRect.Right, subtitleRect.Bottom,
					controlsRect.Left, controlsRect.Top, controlsRect.Right, controlsRect.Bottom)
					or "unresolvable")

			-- ---------------------------------------------------------------
			-- The controls row. Its CHILDREN are placed by the UIListLayout, so
			-- they are honestly out of the resolver's reach. Their SIZE is not:
			-- updateLevelOneGuideLayout writes it directly as an offset, and a
			-- UIListLayout never resizes what it arranges. So size is computed,
			-- position is not claimed, and the pair is checked against the
			-- container's own resolved extent plus the layout's declared padding
			-- along whichever axis the layout is filling on this row.
			-- ---------------------------------------------------------------
			local horizontal = listLayout.FillDirection == Enum.FillDirection.Horizontal
			local sizes = {}
			for _, name in ipairs(BRIEFING_CONTROL_ORDER) do
				local button = buttons[name] :: any
				local width = button.Size.X.Offset
					+ button.Size.X.Scale * (haveControls and controlsRect.Width or 0)
				local height = button.Size.Y.Offset
					+ button.Size.Y.Scale * (haveControls and controlsRect.Height or 0)
				sizes[name] = {Width = width, Height = height}
				if device.Touch then
					-- The compact fallback now gives up ornamental padding instead
					-- of input area, so even the 568x320 band keeps the game's 44px
					-- touch-target contract.
					record(width >= 44 and height >= 44,
						string.format("%s: %s is at least 44x44", device.Name, name),
						string.format("%.0fx%.0f", width, height))
				end
			end
			local padding = haveControls and (listLayout.Padding.Offset
				+ listLayout.Padding.Scale
					* (horizontal and controlsRect.Width or controlsRect.Height)) or 0
			local mute, stop = sizes.DispatchMuteButton, sizes.DispatchStopButton
			local along = horizontal and (mute.Width + stop.Width + padding)
				or (mute.Height + stop.Height + padding)
			local across = horizontal and math.max(mute.Height, stop.Height)
				or math.max(mute.Width, stop.Width)
			local alongLimit = haveControls
				and (horizontal and controlsRect.Width or controlsRect.Height) or 0
			local acrossLimit = haveControls
				and (horizontal and controlsRect.Height or controlsRect.Width) or 0
			record(haveControls and along <= alongLimit + 1 and across <= acrossLimit + 1,
				device.Name .. ": both readouts and the list padding fit inside BriefingControls",
				string.format("%s fill: %.0f + %.0f padding along %.0f, %.0f across %.0f",
					horizontal and "horizontal" or "vertical",
					along - padding, padding, alongLimit, across, acrossLimit))

			-- Every caption the readouts can print, at the TextSize this row's
			-- layout pass just wrote. A readout whose word does not fit its own
			-- transparent hitbox is the same defect as a clipped subtitle, one
			-- rectangle further in.
			for _, name in ipairs(BRIEFING_CONTROL_ORDER) do
				local button = buttons[name] :: any
				local spec = BRIEFING_CONTROL_CAPTIONS[name]
				local prefix = device.Touch and "" or spec.Binding
				for _, caption in ipairs(spec.Captions) do
					local text = prefix .. caption
					local bounds, boundsError = requiredBounds(
						text, button.FontFace, button.TextSize, nil)
					record(bounds ~= nil and bounds.X <= sizes[name].Width + 1
						and bounds.Y <= sizes[name].Height + 1,
						string.format("%s: %s fits %q", device.Name, name, text),
						bounds and string.format("needs %.0fx%.0f in %.0fx%.0f at TextSize %d",
							bounds.X, bounds.Y, sizes[name].Width, sizes[name].Height,
							button.TextSize) or boundsError)
				end
			end

			-- ---------------------------------------------------------------
			-- The copy itself. TextWrapped is true, so the wrap width IS the
			-- resolved box width, and the question is then whether the wrapped
			-- block comes out TALLER than the box the layout reserved -- which
			-- is what clipping looks like from the arithmetic side.
			-- ---------------------------------------------------------------
			-- Each corpus string is made the LIVE cue and the layout re-run before
			-- it is measured. Production sizes the copy box for the sentence that
			-- is on screen, so measuring a different sentence against a box fitted
			-- to another one tests nothing about either.
			local guideScreen = findGui("LevelOneGuideGui")
			local relayoutSeam = guideScreen
				and guideScreen:FindFirstChild("UIRegressionRelayoutGuide")
			for _, entry in ipairs(BRIEFING_STRESS_CORPUS) do
				if relayoutSeam and relayoutSeam:IsA("BindableFunction") and haveSubtitle then
					(subtitle :: any).Text = entry.Text
					pcall(function() relayoutSeam:Invoke() end)
					task.wait(0.05)
					subtitleRect = UIRegression.ResolveRect(subtitle, viewport, insetY)
				end
				local description = string.format("%s: %s fits the Subtitle box",
					device.Name, entry.Name)
				if not haveSubtitle then
					-- Same check, same count, still a failure. A row that could
					-- not resolve its box does not get to skip the fit question.
					record(false, description, "the Subtitle box is unresolvable")
				else
					local bounds, boundsError = requiredBounds(entry.Text,
						subtitleLabel.FontFace, subtitleLabel.TextSize, subtitleRect.Width)
					record(bounds ~= nil
						and bounds.X <= subtitleRect.Width + 1
						and bounds.Y <= subtitleRect.Height + 1,
						description,
						bounds and string.format("needs %.0fx%.0f in %.0fx%.0f at TextSize %d",
							bounds.X, bounds.Y, subtitleRect.Width, subtitleRect.Height,
							subtitleLabel.TextSize) or boundsError)
				end
			end
		end
	end)

	for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
		workspace:SetAttribute(name, previousWorkspace[name].Value)
	end
	subtitleLabel.Text = wasSubtitleText
	local restoreRelayout = guide:FindFirstChild("UIRegressionRelayoutGuide")
	if restoreRelayout and restoreRelayout:IsA("BindableFunction") then
		pcall(function() restoreRelayout:Invoke() end)
	end
	screen.Enabled = wasEnabled
	panelObject.Visible = wasPanelVisible
	controlsObject.Visible = wasControlsVisible
	task.wait(0.2)
	if not ran then
		failures += 1
		checks += 1
		table.insert(report, "  FAIL the briefing fit matrix ran  (" .. tostring(runError) .. ")")
	end
	local restored = true
	for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
		if workspace:GetAttribute(name) ~= previousWorkspace[name].Value then
			restored = false
			break
		end
	end
	record(restored, "the matrix restored every simulator/inset attribute it borrowed")
	record(subtitleLabel.Text == wasSubtitleText,
		"the matrix restored the live dispatch subtitle after every synthetic stress cue",
		string.format("restored=%s", tostring(subtitleLabel.Text == wasSubtitleText)))
	table.insert(report, string.format("TOTAL: %d checks, %d failed", checks, failures))
	return table.concat(report, "\n"), failures
end

function UIRegression.BriefingFitMatrix(token: string?): (string, number)
	return Fit.lane("BriefingFitMatrix", token, Fit.bodyBriefingFitMatrix)
end

-- ---------------------------------------------------------------------------
-- BriefingExclusionMatrix -- briefing, queue modal and the full Zyntra terminal
-- ---------------------------------------------------------------------------
--
-- WHAT SHIPPED BROKEN, in pixels, at 705x338: the Zyntra opener occupied
-- (345,66)-(529,110), which is ENTIRELY inside the dispatch briefing panel
-- (12,66)-(529,141) and overlaps its MUTE/STOP row by 172x42. The briefing
-- panel in turn overlapped QueueHostPanel (290,66)-(529,326) by 239x75 and
-- covered its CloseQueue button completely. The panel draws above both
-- (DisplayOrder 110 against RoundGui 100 and ZyntraStore 55) and is opaque at
-- BackgroundTransparency .18 -- but its Frame is not Active, so a tap that
-- missed MUTE or STOP fell straight through onto a button the player could not
-- see. On a phone that is the entire top strip of the screen.
--
-- The rule is now one expression in one place (RoundUI's dispatchAudio.refresh),
-- published as the player attribute DispatchBriefingOpen. Queue always wins;
-- an already-open terminal suppresses only the panel while the transmission
-- keeps running. This matrix drives each state machine in BOTH orders because a
-- flag that is only ever set one way round is a flag that sticks.
--
-- Three things are asserted that a "does the panel hide" test would not:
--
--   * ZyntraDispatchClientActive must NOT follow DispatchBriefingOpen. The
--     transmission keeps running while its panel is suppressed; if it were torn
--     down, claimLobbyBriefing's one-shot claim would be burned by opening a
--     modal and the player would never hear the briefing at all.
--   * the suppression is UNCONDITIONAL, not touch-only, so the sweep runs at a
--     desktop viewport as well as at the phone.
--   * no rect anywhere under CommandSubtitles may intersect any rect anywhere
--     under QueueHostShade, in any state -- descendants included, because the
--     overlap that shipped was between two CHILDREN, not the two panels.
--
-- Then the developer-page captions, which are a different fault with the same
-- shape: they were chosen by UIDevice.IsTouch(), so a handheld that reports a
-- keyboard -- a tablet with a case, a hybrid -- was told to press J, B, V, P,
-- I, U and C on a device with no keys. They now follow
-- UIDevice.SuppressesKeyboardGlyphs(), which is true for EITHER touch input or
-- a handheld form factor, and they are re-rendered on UIDevice.Changed rather
-- than only at build time.
local BRIEFING_EXCLUSION_VIEWPORTS = {
	{Name = "phone-landscape", Size = Vector2.new(705, 338), Touch = true},
	{Name = "desktop", Size = nil, Touch = false},
}

-- command -> the key the caption must name when glyphs are shown. Mirrored by
-- hand from ZyntraStore's control table so a silent rebinding fails here.
-- B really does drive esp and fastQueue together (DevCheats' InputBegan toggles
-- both), so the repeat is correct and must not be "fixed".
local DEV_CAPTION_KEYS = {
	{Command = "esp", Key = "B"},
	{Command = "fastQueue", Key = "B"},
	{Command = "noclip", Key = "V"},
	{Command = "pauseEntity", Key = "P"},
	{Command = "immunePush", Key = "I"},
	{Command = "unlimited", Key = "U"},
	{Command = "thirdPerson", Key = "C"},
	{Command = "level3PreBlackout", Key = "K"},
}
local DEV_INTRO_BASE = "WHITELISTED DEVELOPER CONTROLS"
local DEV_INTRO_KEYBOARD = DEV_INTRO_BASE .. "  //  PHONE: J"
local DEV_NOCLIP_KEYBOARD = "Fly through geometry with WASD, Space and Left Ctrl."
local DEV_NOCLIP_TOUCH = "Fly through geometry using the movement stick."

function Fit.bodyBriefingExclusionMatrix(): (string, number)
	local report = {"=== briefing / queue modal / full Zyntra terminal exclusion ==="}
	local stolen = Fit.takeStolenNote()
	if stolen then table.insert(report, "  note " .. stolen) end
	local failures, checks = 0, 0
	-- (b) AWAIT ITS NATURAL END, BOUNDED. This is the lane that forces
	-- UIRegressionForceDispatchActive and UIRegressionSuppressDispatch on and off
	-- for every row; run under a real briefing it would be steering someone
	-- else's transmission and reporting the result as geometry.
	local quiet, dispatchWhy = Fit.awaitQuietDispatch()
	if not quiet then
		failures += 1
		checks += 1
		table.insert(report, "  FAIL " .. tostring(dispatchWhy))
		table.insert(report, string.format("TOTAL: %d checks, %d failed", checks, failures))
		return table.concat(report, "\n"), failures
	end
	local function record(ok, description, detail)
		checks += 1
		if ok then
			-- Compact keeps findings, not confirmations. See C_COMPACT_REPORT_20260831:
			-- five lanes build their own report table instead of using Fit.recorder,
			-- and every one of them printed a line per passing check -- which is why
			-- a "compact" run still came to 103KB.
			if not Fit.Compact then table.insert(report, "  ok   " .. description) end
		else
			failures += 1
			table.insert(report, "  FAIL " .. description
				.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
		end
	end

	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		record(false, "there is a PlayerGui to measure")
		return table.concat(report, "\n"), failures
	end
	local function find(name)
		for _, descendant in ipairs(gui:GetDescendants()) do
			if descendant.Name == name then return descendant end
		end
		return nil
	end
	local subtitles = find("CommandSubtitles")
	local opener = find("ZyntraOpenButton")
	local shade = find("QueueHostShade")
	local store = gui:FindFirstChild("ZyntraStore")
	local terminal = store and store:FindFirstChild("Terminal")
	local storeProbe = store and store:FindFirstChild("UIRegressionZyntraStoreProbe")
	if not (subtitles and opener and shade and terminal and storeProbe
		and storeProbe:IsA("BindableFunction")) then
		record(false, "the briefing, queue modal, store opener, terminal and Studio probe all exist",
			string.format("subtitles=%s opener=%s shade=%s terminal=%s probe=%s",
				tostring(subtitles ~= nil), tostring(opener ~= nil), tostring(shade ~= nil),
				tostring(terminal ~= nil), tostring(storeProbe ~= nil)))
		return table.concat(report, "\n"), failures
	end

	local previousViewport = workspace:GetAttribute("UIRegressionViewport")
	local previousTouch = workspace:GetAttribute("ForceTouchUI")
	local previousShade = shade.Visible
	local previousForce = player:GetAttribute("UIRegressionForceDispatchActive")
	local previousSuppress = player:GetAttribute("UIRegressionSuppressDispatch")
	local previousTerminal = terminal.Visible
	local previousDerived = {
		QueueModalOpen = player:GetAttribute("QueueModalOpen"),
		DispatchBriefingOpen = player:GetAttribute("DispatchBriefingOpen"),
		ZyntraStoreOpen = player:GetAttribute("ZyntraStoreOpen"),
		DevPhoneOpen = player:GetAttribute("DevPhoneOpen"),
		MovementSuppressed = UIDevice.TouchMovementSuppressed(),
		SubtitlesVisible = subtitles.Visible,
		OpenerVisible = opener.Visible,
		OpenerActive = opener.Active,
		OpenerSelectable = opener.Selectable,
		OpenerText = opener.Text,
	}
	local previousDevText = {}
	local baselineDevPage = terminal:FindFirstChild("Dev", true)
	if baselineDevPage then
		for _, descendant in ipairs(baselineDevPage:GetDescendants()) do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				previousDevText[descendant] = descendant.Text
			end
		end
	end

	-- brief/modal are what this matrix ASKS for; the rest is what must follow.
	-- The order is the point: rows 2-3 raise the modal over a running briefing
	-- and take it away again, rows 5-6 raise a briefing under a modal that is
	-- already up. A one-directional flag passes one half and fails the other.
	local STATES = {
		{Label = "idle", Force = false, Shade = false,
			Brief = false, Subs = false, Opener = true, Transmission = false},
		{Label = "briefing only", Force = true, Shade = false,
			Brief = true, Subs = true, Opener = false, Transmission = true},
		{Label = "modal opened over a live briefing", Force = true, Shade = true,
			Brief = false, Subs = false, Opener = false, Transmission = true},
		{Label = "modal closed, briefing still running", Force = true, Shade = false,
			Brief = true, Subs = true, Opener = false, Transmission = true},
		{Label = "briefing cleared", Force = false, Shade = false,
			Brief = false, Subs = false, Opener = true, Transmission = false},
		{Label = "modal only", Force = false, Shade = true,
			Brief = false, Subs = false, Opener = false, Transmission = false},
		{Label = "briefing raised while the modal is up", Force = true, Shade = true,
			Brief = false, Subs = false, Opener = false, Transmission = true},
	}

	local ran, runError = pcall(function()
		-- A Studio session comes up with the first-login lobby briefing already
		-- running, so clearing the force flag does NOT reach an idle screen --
		-- the panel stays up, driven by a transmission this module has no handle
		-- on. Every "briefing off" row below would then be asserting against a
		-- real briefing. This suppresses the AMBIENT transmission for the length
		-- of the sweep and is restored on every exit path; the force flag still
		-- drives the "briefing on" rows exactly as before.
		player:SetAttribute("UIRegressionSuppressDispatch", true)
		storeProbe:Invoke("close")
		task.wait(.3)
		record(player:GetAttribute("DispatchBriefingOpen") ~= true
			and subtitles.Visible == false,
			"the sweep starts from a genuinely idle screen, not from whatever"
			.. " briefing this session happened to be playing",
			string.format("brief=%s subtitles=%s",
				tostring(player:GetAttribute("DispatchBriefingOpen")),
				tostring(subtitles.Visible)))

		for _, device in ipairs(BRIEFING_EXCLUSION_VIEWPORTS) do
			workspace:SetAttribute("ForceTouchUI", device.Touch or nil)
			workspace:SetAttribute("UIRegressionViewport", device.Size)
			-- WAIT FOR IT TO TAKE. A fixed sleep after a deferred attribute
			-- signal measures the previous device on a busy frame.
			-- `device.Size` is nil for the desktop row, which means "clear the
			-- override" -- there is no size to wait for, only a settle.
			if device.Size then
				local spins = 40
				while spins > 0 and not (UIDevice.Layout().Width == device.Size.X
					and UIDevice.Layout().Height == device.Size.Y) do
					task.wait(0.05)
					spins -= 1
				end
			else
				task.wait(0.3)
			end
			-- Back to a known floor before each sweep, so a state left behind by
			-- the previous device cannot make the first row of this one pass.
			player:SetAttribute("UIRegressionForceDispatchActive", nil)
			shade.Visible = false
			storeProbe:Invoke("close")
			task.wait(.35)

			for _, state in ipairs(STATES) do
				player:SetAttribute("UIRegressionForceDispatchActive",
					state.Force and true or nil)
				shade.Visible = state.Shade
				task.wait(.3)
				local label = device.Name .. " / " .. state.Label

				record(player:GetAttribute("DispatchBriefingOpen") == state.Brief
					and player:GetAttribute("QueueModalOpen") == state.Shade,
					label .. ": the two published flags say what the screen is doing",
					string.format("brief=%s (want %s), modal=%s (want %s)",
						tostring(player:GetAttribute("DispatchBriefingOpen")),
						tostring(state.Brief),
						tostring(player:GetAttribute("QueueModalOpen")),
						tostring(state.Shade)))

				-- The flag and the pixels come from ONE expression; this is what
				-- makes that worth asserting rather than assuming.
				record(subtitles.Visible == state.Subs,
					label .. ": the briefing panel is drawn exactly when the flag says so",
					string.format("Visible=%s, want %s", tostring(subtitles.Visible),
						tostring(state.Subs)))

				-- SetInteractive clears Visible AND Active AND Selectable, so the
				-- opener leaves the input stack rather than merely going invisible
				-- underneath an opaque panel -- which is what shipped.
				record(opener.Visible == state.Opener and opener.Active == state.Opener,
					label .. ": the store opener is gone from the screen AND from the"
					.. " input stack whenever anything is over it",
					string.format("Visible=%s Active=%s, want %s",
						tostring(opener.Visible), tostring(opener.Active),
						tostring(state.Opener)))

				record(
					(player:GetAttribute("ZyntraDispatchClientActive") == true)
						== state.Transmission,
					label .. ": the transmission itself is untouched -- suppressing the"
					.. " panel must never end the briefing",
					string.format("ZyntraDispatchClientActive=%s, want %s",
						tostring(player:GetAttribute("ZyntraDispatchClientActive")),
						tostring(state.Transmission)))

				-- Geometry, descendants included: the overlap that shipped was
				-- between two CHILDREN of these two trees, not between the two
				-- panels, so comparing only the roots would have missed it.
				local worst, worstPair = 0, ""
				for _, a in ipairs(subtitles:GetDescendants()) do
					if a:IsA("GuiObject") and visibleChain(a) then
						for _, b in ipairs(shade:GetDescendants()) do
							if b:IsA("GuiObject") and visibleChain(b) then
								local overlapX = math.min(
									a.AbsolutePosition.X + a.AbsoluteSize.X,
									b.AbsolutePosition.X + b.AbsoluteSize.X)
									- math.max(a.AbsolutePosition.X, b.AbsolutePosition.X)
								local overlapY = math.min(
									a.AbsolutePosition.Y + a.AbsoluteSize.Y,
									b.AbsolutePosition.Y + b.AbsoluteSize.Y)
									- math.max(a.AbsolutePosition.Y, b.AbsolutePosition.Y)
								local area = math.max(0, overlapX) * math.max(0, overlapY)
								if area > worst then
									worst = area
									worstPair = a.Name .. " x " .. b.Name
								end
							end
						end
					end
				end
				record(worst == 0,
					label .. ": nothing under the briefing panel overlaps anything under"
					.. " the queue modal",
					string.format("%.0f px^2 at %s", worst, worstPair))
			end
		end

		-- ------------------------------------------------------------------
		-- The full terminal participates, not only its lobby opener.
		-- ------------------------------------------------------------------
		workspace:SetAttribute("UIRegressionViewport", nil)
		workspace:SetAttribute("ForceTouchUI", true)
		player:SetAttribute("UIRegressionForceDispatchActive", nil)
		shade.Visible = false
		storeProbe:Invoke("close")
		task.wait(.45)
		record(player:GetAttribute("DispatchBriefingOpen") ~= true
			and opener.Visible == true and opener.Active == true,
			"and it ends back at an idle screen with the store opener returned to"
			.. " the input stack -- the suppression is not one-way",
			string.format("brief=%s opener.Visible=%s opener.Active=%s",
				tostring(player:GetAttribute("DispatchBriefingOpen")),
				tostring(opener.Visible), tostring(opener.Active)))
		record(UIDevice.TouchMovementSuppressed() == false,
			"idle touch screen: movement is enabled before either modal opens",
			tostring(UIDevice.TouchMovementSuppressed()))

		local opened = storeProbe:Invoke("open")
		task.wait(.2)
		record(opened == true and terminal.Visible == true
			and player:GetAttribute("ZyntraStoreOpen") == true,
			"idle: the production toggle opens the terminal and publishes its modal state",
				string.format("Invoke=%s Visible=%s attribute=%s", tostring(opened),
				tostring(terminal.Visible), tostring(player:GetAttribute("ZyntraStoreOpen"))))
		record(UIDevice.TouchMovementSuppressed() == true,
			"opening the terminal suppresses Roblox touch movement",
			tostring(UIDevice.TouchMovementSuppressed()))

		player:SetAttribute("UIRegressionForceDispatchActive", true)
		task.wait(.3)
		record(player:GetAttribute("ZyntraDispatchClientActive") == true
			and player:GetAttribute("DispatchBriefingOpen") ~= true
			and subtitles.Visible == false and terminal.Visible == true,
			"terminal already open: RoundUI keeps transmission alive but yields its panel",
			string.format("active=%s brief=%s subtitles=%s terminal=%s",
				tostring(player:GetAttribute("ZyntraDispatchClientActive")),
				tostring(player:GetAttribute("DispatchBriefingOpen")),
				tostring(subtitles.Visible), tostring(terminal.Visible)))
		record(UIDevice.TouchMovementSuppressed() == true,
			"a suppressed briefing panel does not release movement from the open terminal",
			tostring(UIDevice.TouchMovementSuppressed()))

		storeProbe:Invoke("close")
		task.wait(.3)
		record(terminal.Visible == false and player:GetAttribute("ZyntraStoreOpen") ~= true
			and player:GetAttribute("DispatchBriefingOpen") == true and subtitles.Visible == true,
			"closing the terminal restores the still-running briefing",
				string.format("store=%s brief=%s subtitles=%s",
					tostring(player:GetAttribute("ZyntraStoreOpen")),
					tostring(player:GetAttribute("DispatchBriefingOpen")), tostring(subtitles.Visible)))
		record(UIDevice.TouchMovementSuppressed() == false,
			"closing the terminal releases movement when no movement-owning modal remains",
			tostring(UIDevice.TouchMovementSuppressed()))

		local toggleDuringBrief = storeProbe:Invoke("open")
		local kioskDuringBrief = storeProbe:Invoke("kiosk")
		task.wait(.2)
		record(toggleDuringBrief == false and kioskDuringBrief == false
			and terminal.Visible == false and player:GetAttribute("ZyntraStoreOpen") ~= true,
			"briefing already open: both toggle and kiosk paths refuse the terminal",
			string.format("toggle=%s kiosk=%s Visible=%s", tostring(toggleDuringBrief),
				tostring(kioskDuringBrief), tostring(terminal.Visible)))

		player:SetAttribute("UIRegressionForceDispatchActive", nil)
		task.wait(.3)
		storeProbe:Invoke("open")
		task.wait(.2)
		shade.Visible = true
		task.wait(.3)
		record(terminal.Visible == false and player:GetAttribute("ZyntraStoreOpen") ~= true,
			"queue raised over an open terminal closes the full terminal and clears its state",
				string.format("Visible=%s attribute=%s", tostring(terminal.Visible),
					tostring(player:GetAttribute("ZyntraStoreOpen"))))
		record(player:GetAttribute("QueueModalOpen") == true
			and UIDevice.TouchMovementSuppressed() == true,
			"queue raised over Zyntra keeps movement suppressed after Zyntra closes",
			string.format("queue=%s suppressed=%s",
				tostring(player:GetAttribute("QueueModalOpen")),
				tostring(UIDevice.TouchMovementSuppressed())))

		local toggleDuringQueue = storeProbe:Invoke("open")
		local kioskDuringQueue = storeProbe:Invoke("kiosk")
		record(toggleDuringQueue == false and kioskDuringQueue == false
			and terminal.Visible == false,
			"queue already open: both toggle and kiosk paths refuse the terminal",
				string.format("toggle=%s kiosk=%s Visible=%s", tostring(toggleDuringQueue),
					tostring(kioskDuringQueue), tostring(terminal.Visible)))
		record(UIDevice.TouchMovementSuppressed() == true,
			"refused Zyntra opens cannot release movement beneath the still-open queue",
			tostring(UIDevice.TouchMovementSuppressed()))

		shade.Visible = false
		task.wait(.25)
		record(UIDevice.TouchMovementSuppressed() == false,
			"closing the last movement-owning modal restores movement",
			tostring(UIDevice.TouchMovementSuppressed()))
		storeProbe:Invoke("open")
		task.wait(.2)
		record(UIDevice.TouchMovementSuppressed() == true,
			"the terminal takes movement ownership again after queue closes",
			tostring(UIDevice.TouchMovementSuppressed()))
		player:SetAttribute("DispatchBriefingOpen", true)
		task.wait(.2)
		record(terminal.Visible == false and player:GetAttribute("ZyntraStoreOpen") ~= true,
			"a briefing modal attribute closes a terminal that was already open",
			string.format("Visible=%s attribute=%s", tostring(terminal.Visible),
				tostring(player:GetAttribute("ZyntraStoreOpen"))))
		record(UIDevice.TouchMovementSuppressed() == false,
			"briefing-only exclusion closes Zyntra without leaving movement suppressed",
			tostring(UIDevice.TouchMovementSuppressed()))
		player:SetAttribute("DispatchBriefingOpen", nil)
		task.wait(.2)

		-- ------------------------------------------------------------------
		-- Developer-page captions follow the live input mode.
		-- ------------------------------------------------------------------
		-- Terminal has three unnamed children all called Frame, so the page has
		-- to be found recursively rather than indexed.
		local devPage = terminal and terminal:FindFirstChild("Dev", true)
		local devControls = devPage and devPage:FindFirstChild("DevControls")
		if not devControls then
			-- Not a pass and not a failure of the code under test: this account is
			-- not on the developer whitelist, so the page does not exist to read.
			record(true, "the developer page is not present for this account -- its"
				.. " caption contract is unexercised on this run, not verified",
				"whitelisted accounts only")
		else
			for _, mode in ipairs({
				-- FALSE, not nil. nil means "ask the host", and the host here is
				-- Studio's Device Emulator, which reports TouchEnabled for the
				-- whole session while still offering a mouse and a keyboard --
				-- so the keyboard half used to be unreachable from the very
				-- place a mobile repair is verified. `false` states the fixture:
				-- a pointer device with no touchscreen.
				{Name = "keyboard", Force = false, Suppressed = false},
				{Name = "touch", Force = true, Suppressed = true},
			}) do
				workspace:SetAttribute("ForceTouchUI", mode.Force)
				task.wait(.4)
				record(UIDevice.SuppressesKeyboardGlyphs() == mode.Suppressed,
					mode.Name .. ": UIDevice reports the glyph mode this pass is testing",
					string.format("SuppressesKeyboardGlyphs=%s",
						tostring(UIDevice.SuppressesKeyboardGlyphs())))

				local intro = devPage:FindFirstChild("DevIntro")
				local wantedIntro = mode.Suppressed and DEV_INTRO_BASE or DEV_INTRO_KEYBOARD
				record(intro ~= nil and intro.Text == wantedIntro,
					mode.Name .. ": the developer intro line names a key only when there"
					.. " are keys to press",
					string.format("%q, want %q", intro and tostring(intro.Text) or "-",
						wantedIntro))

				local wrongToggle, wrongName, missing = 0, "", 0
				for _, entry in ipairs(DEV_CAPTION_KEYS) do
					local row = devControls:FindFirstChild(entry.Command)
					if not row then
						-- level3PreBlackout only exists for the timeline owner.
						missing += 1
					else
						local toggle = row:FindFirstChild("Toggle")
						local text = toggle and tostring(toggle.Text) or ""
						local named = text:find("//  " .. entry.Key, 1, true) ~= nil
						if named == mode.Suppressed then
							wrongToggle += 1
							if wrongName == "" then
								wrongName = entry.Command .. " = " .. text
							end
						end
					end
				end
				record(wrongToggle == 0,
					mode.Name .. ": every developer toggle caption shows its key exactly"
					.. " when the device has one",
					string.format("%d wrong, first %s (%d rows absent for this account)",
						wrongToggle, wrongName == "" and "-" or wrongName, missing))

				local noclip = devControls:FindFirstChild("noclip")
				local description = noclip and noclip:FindFirstChild("Description")
				local wantedNoclip = mode.Suppressed and DEV_NOCLIP_TOUCH or DEV_NOCLIP_KEYBOARD
				record(description ~= nil and description.Text == wantedNoclip,
					mode.Name .. ": the noclip row describes the controls this device"
					.. " actually has",
					string.format("%q, want %q",
						description and tostring(description.Text) or "-", wantedNoclip))
			end

			-- The whole point of hanging this off UIDevice.Changed rather than
			-- reading IsTouch() once at build time: a device that changes mode
			-- mid-session has to be re-captioned, not left lying.
			workspace:SetAttribute("ForceTouchUI", false)
			task.wait(.4)
			local intro = devPage:FindFirstChild("DevIntro")
			record(intro ~= nil and intro.Text == DEV_INTRO_KEYBOARD,
				"and the captions come BACK when the device stops suppressing glyphs --"
				.. " they are re-rendered on UIDevice.Changed, not decided once",
				string.format("%q", intro and tostring(intro.Text) or "-"))
		end
	end)

	-- Protected cleanup. Keep ambient dispatch suppressed while the structural
	-- owners are put back, otherwise a previously-open terminal cannot reopen:
	-- the temporarily exposed briefing would correctly block it. Restore the
	-- real dispatch drivers only after shade/store match their baseline.
	workspace:SetAttribute("UIRegressionViewport", previousViewport)
	workspace:SetAttribute("ForceTouchUI", previousTouch)
	player:SetAttribute("DispatchBriefingOpen", nil)
	player:SetAttribute("UIRegressionForceDispatchActive", nil)
	player:SetAttribute("UIRegressionSuppressDispatch", true)
	storeProbe:Invoke("close")
	shade.Visible = previousShade
	task.wait(0.25)
	if previousTerminal and not previousShade then
		storeProbe:Invoke("open")
	end
	player:SetAttribute("UIRegressionForceDispatchActive", previousForce)
	player:SetAttribute("UIRegressionSuppressDispatch", previousSuppress)
	-- Let every deferred attribute listener, UIDevice refresh, caption refresh and
	-- movement ControlModule call settle before judging the cleanup.
	task.wait(0.55)
	if not ran then
		record(false, "the matrix ran to completion", tostring(runError))
	end
	record(workspace:GetAttribute("UIRegressionViewport") == previousViewport
		and workspace:GetAttribute("ForceTouchUI") == previousTouch,
		"cleanup restored the two simulator attributes it borrowed")
	record(shade.Visible == previousShade
		and terminal.Visible == previousTerminal
		and player:GetAttribute("QueueModalOpen") == previousDerived.QueueModalOpen
		and player:GetAttribute("DispatchBriefingOpen") == previousDerived.DispatchBriefingOpen
		and player:GetAttribute("ZyntraStoreOpen") == previousDerived.ZyntraStoreOpen
		and player:GetAttribute("DevPhoneOpen") == previousDerived.DevPhoneOpen,
		"cleanup restored the real modal sources and every derived modal flag",
		string.format("shade=%s/%s terminal=%s/%s queue=%s/%s brief=%s/%s store=%s/%s dev=%s/%s",
			tostring(shade.Visible), tostring(previousShade),
			tostring(terminal.Visible), tostring(previousTerminal),
			tostring(player:GetAttribute("QueueModalOpen")), tostring(previousDerived.QueueModalOpen),
			tostring(player:GetAttribute("DispatchBriefingOpen")), tostring(previousDerived.DispatchBriefingOpen),
			tostring(player:GetAttribute("ZyntraStoreOpen")), tostring(previousDerived.ZyntraStoreOpen),
			tostring(player:GetAttribute("DevPhoneOpen")), tostring(previousDerived.DevPhoneOpen)))
	record(UIDevice.TouchMovementSuppressed() == previousDerived.MovementSuppressed,
		"cleanup restored Roblox touch movement to its exact baseline",
		string.format("%s/%s", tostring(UIDevice.TouchMovementSuppressed()),
			tostring(previousDerived.MovementSuppressed)))
	record(subtitles.Visible == previousDerived.SubtitlesVisible
		and opener.Visible == previousDerived.OpenerVisible
		and opener.Active == previousDerived.OpenerActive
		and opener.Selectable == previousDerived.OpenerSelectable
		and opener.Text == previousDerived.OpenerText,
		"cleanup restored the briefing panel and Zyntra opener pixels/input/caption",
		string.format("subs=%s/%s opener V=%s/%s A=%s/%s S=%s/%s text=%s",
			tostring(subtitles.Visible), tostring(previousDerived.SubtitlesVisible),
			tostring(opener.Visible), tostring(previousDerived.OpenerVisible),
			tostring(opener.Active), tostring(previousDerived.OpenerActive),
			tostring(opener.Selectable), tostring(previousDerived.OpenerSelectable),
			tostring(opener.Text == previousDerived.OpenerText)))
	local captionProblems = {}
	for object, text in pairs(previousDevText) do
		if object.Parent == nil then
			table.insert(captionProblems, object.Name .. " was destroyed")
		elseif object.Text ~= text then
			table.insert(captionProblems, string.format("%s=%q (was %q)", object.Name,
				tostring(object.Text), tostring(text)))
		end
	end
	record(#captionProblems == 0,
		"cleanup refreshed every developer caption back to the baseline input mode",
		table.concat(captionProblems, "; "))
	table.insert(report, string.format("TOTAL: %d checks, %d failed", checks, failures))
	return table.concat(report, "\n"), failures
end

function UIRegression.BriefingExclusionMatrix(token: string?): (string, number)
	return Fit.lane("BriefingExclusionMatrix", token, Fit.bodyBriefingExclusionMatrix)
end

-- C_ZYNTRA_ACTIONS_ARE_ENUMERATED_20260831 -- WHAT SHIPPED BROKEN in the tests.
--
-- The terminal's per-card proofs were counted rather than named, and everything
-- that mattered fell through the gap between those two words.
--
--   * The tap-target sweep walked VISIBLE, Active descendants. A DISABLED action
--     -- an OWNED product, a COMING SOON tier, a LEVEL 3 ONLY dev row -- is
--     Visible and full-size and NOT Active, which is precisely the state the
--     44px floor has to hold in, and it is precisely the state the sweep
--     skipped. A floor that only applies while a product is unowned is not a
--     floor.
--   * The Donate page was proved by COUNTING: six cards, six buttons. Six cards
--     drawn from one tier six times would have passed, and so would six cards
--     for the wrong six tiers.
--   * The floor itself was the literal 44, restated in the harness, so the
--     harness agreed with itself instead of with the terminal.
--
-- ZyntraStore now publishes the index this needs: the CollectionService tag
-- "ZyntraTerminalAction" on every card action (enumeration finds the disabled
-- ones), ZyntraPage/ZyntraCardKey on both the card and its action,
-- DonationTierKey/DonationProductId on each donation card, and
-- TerminalActionTag/TerminalTapFloor on the terminal itself -- the floor being
-- the number the actions were actually sized against on the pass that just ran.
Fit.ZyntraFloorFallback = 44

-- The six donation tiers, NAMED here so the assertion has an oracle the store
-- and the config cannot both drift away from at once. Reading the config and
-- comparing it to the store proves the two agree; it does not prove either is
-- what was authored. Both are held to this list.
Fit.DonationTierKeys = {
	"DonationSignal", "DonationSupply", "DonationField",
	"DonationResearch", "DonationCommand", "DonationDirector",
}

-- The captions the store is AUTHORED to take an action out of the input stack
-- with, and the only reasons an action may be inactive. An action that is
-- inactive without one of these has died silently, which is the failure this
-- names; an action that carries one and is still Active is a control the player
-- can press when the store has already said they cannot.
--
-- LUA PATTERNS, not literal substrings, and that is the fix for the 22 Dev-tab
-- failures this list was producing on its own. The store builds a level-gated
-- dev row's caption as `"LEVEL " .. (info.Level or 3) .. " ONLY"`, and PULL TWO
-- PUMPS carries Level = 2 -- so it renders "LEVEL 2 ONLY", Active = false, and
-- the literal "LEVEL 3 ONLY" never matched it. That row was reported twice per
-- device (once as "out of the input stack with no stated reason" and once in
-- the per-page accounting, 8 authored against 7 reachable and 0 stood down)
-- across the 11 rows of Fit.Devices: 11 x 2 = 22. The busy caption for the same
-- row is "WAITING 5s", which is the same shape and the same silence, so it is
-- named here too. Nothing in production changed; the harness was wrong.
Fit.ZyntraDisabledCaptions = {"OWNED", "COMING SOON", "LEVEL %d+ ONLY", "WAITING"}

-- HOW MANY OF A PAGE'S CARD ACTIONS THE PLAYER CAN PRESS, where that number is
-- a property of the build and not of the tester's save file.
--
-- Shop, Dev and Settings are deliberately ABSENT rather than given a number:
-- what the Shop offers depends on what this account already owns, the Dev
-- page's skip rows go inactive outside Level 3, and the Settings list is
-- configuration. A literal for any of them would encode one machine's state as
-- the contract and fail honestly-built terminals on every other. They are held
-- to the complete accounting instead -- reachable plus stood-down-with-a-reason
-- equals the whole authored contract -- which is a statement about the terminal
-- rather than about the account. Settings has no stood-down state at all: an
-- accessibility toggle is reachable in both of its positions, so the accounting
-- there reduces to "every authored switch can be pressed".
Fit.ZyntraExpectedActive = {
	-- The two upgrade cards. Neither is ever taken out of the input stack: a
	-- player short of tokens still presses SPEND and is told so.
	Upgrades = 2,
	-- The two colour pickers. SetLocked draws a lock OVERLAY over a card; it does
	-- not touch the Save button's Active, so both stay reachable at every
	-- ownership state.
	Colors = 2,
	-- Donate is computed from ZyntraConfig at the point of use: one per tier with
	-- a configured product id, which is the store's own COMING SOON condition and
	-- the only thing that legitimately lowers it.
}

function Fit.zyntraDisabledReason(button): string?
	local text = tostring((button :: any).Text or "")
	for _, caption in ipairs(Fit.ZyntraDisabledCaptions) do
		-- The MATCHED TEXT is returned, not the pattern that found it, so a
		-- failure line still says "LEVEL 2 ONLY" and names the row a reader can
		-- go and look at.
		local first, last = text:find(caption)
		if first then return text:sub(first, last) end
	end
	return nil
end

-- Every TAGGED action under one page. GetTagged is the half a Visible+Active
-- descendant walk cannot do: it finds a control the store deliberately took out
-- of the input stack, which is exactly the control whose rectangle needs
-- measuring most.
function Fit.zyntraActions(page, tagName): {any}
	local service = game:GetService("CollectionService")
	local found = {}
	for _, node in ipairs(service:GetTagged(tagName)) do
		if node:IsDescendantOf(page) then table.insert(found, node) end
	end
	return found
end

-- The probe's "cards" answer, "page|card|action" per line, grouped by page.
function Fit.parseZyntraCards(answer): any
	local byPage = {}
	for line in string.gmatch(tostring(answer), "[^\n]+") do
		local page, card, action = string.match(line, "^([^|]+)|([^|]+)|([^|]+)$")
		if page then
			byPage[page] = byPage[page] or {}
			table.insert(byPage[page], {Card = card, Action = action})
		end
	end
	return byPage
end

-- EVERY tagged action on one page, measured against the terminal's OWN tap
-- floor: drawn at all, drawn at the floor on both axes on touch, and either
-- reachable or inactive for a reason the store states in the button's own copy.
function Fit.zyntraActionProblems(page, pageName, tagName, floor, touch, authored): {string}
	local problems = {}
	local tagged = Fit.zyntraActions(page, tagName)
	if authored then
		if #tagged ~= #authored then
			table.insert(problems, string.format(
				"%s draws %d tagged actions, the terminal's own contract names %d",
				pageName, #tagged, #authored))
		end
		-- CARD BY CARD, through the key attribute rather than by counting: the
		-- contract names which cards exist, so a page that drew one card twice and
		-- another not at all fails here instead of passing on a total.
		for _, entry in ipairs(authored) do
			local matches = {}
			for _, action in ipairs(tagged) do
				if action:GetAttribute("ZyntraCardKey") == entry.Card then
					table.insert(matches, action)
				end
			end
			if #matches ~= 1 then
				table.insert(problems, string.format(
					"%s card %q has %d tagged actions, not exactly one",
					pageName, entry.Card, #matches))
			else
				local rect = Fit.live(matches[1])
				if (matches[1] :: any).Visible ~= true then
					table.insert(problems, string.format("%s card %q has no VISIBLE action",
						pageName, entry.Card))
				elseif rect.Width <= 0 or rect.Height <= 0 then
					table.insert(problems, string.format("%s card %q action is %.0fx%.0f",
						pageName, entry.Card, rect.Width, rect.Height))
				elseif touch and (rect.Width < floor or rect.Height < floor) then
					table.insert(problems, string.format(
						"%s card %q action is %.0fx%.0f, under the terminal's own %.0f tap floor",
						pageName, entry.Card, rect.Width, rect.Height, floor))
				end
			end
		end
	end
	for _, action in ipairs(tagged) do
		local rect = Fit.live(action)
		local reason = Fit.zyntraDisabledReason(action)
		local active = (action :: any).Active == true
		-- A DISABLED action keeps its whole rectangle. This is the case the old
		-- Visible+Active sweep could not reach at all.
		if (action :: any).Visible ~= true then
			table.insert(problems, string.format("%s.%s is not drawn (Visible=false)",
				pageName, action.Name))
		elseif touch and (rect.Width < floor or rect.Height < floor) then
			table.insert(problems, string.format(
				"%s.%s is %.0fx%.0f, under the %.0f tap floor (reason=%s active=%s)",
				pageName, action.Name, rect.Width, rect.Height, floor,
				reason or "none", tostring(active)))
		end
		if not active and reason == nil then
			table.insert(problems, string.format(
				"%s.%s is out of the input stack with no stated reason: %q",
				pageName, action.Name, string.sub(tostring((action :: any).Text), 1, 40)))
		end
		if active and reason ~= nil then
			table.insert(problems, string.format(
				"%s.%s says %q and is still reachable", pageName, action.Name, reason))
		end
	end
	return problems
end

function Fit.bodyZyntraTerminalFitMatrix(): (string, number)
	local player = Players.LocalPlayer
	local state = Fit.recorder("=== zyntra terminal fit, every tab, every device ===")
	local record = state.record
	-- (b) AWAIT ITS NATURAL END, BOUNDED. See Fit.awaitQuietDispatch: this lane
	-- cannot run without interrupting a live transmission, and it must not
	-- interrupt one. The wait is BEFORE Fit.borrow, so the snapshot is of a quiet
	-- world and the restore has nothing to be forgiven for.
	local quiet, dispatchWhy = Fit.awaitQuietDispatch()
	if not quiet then
		record(false, "no real dispatch briefing was live when the matrix started",
			dispatchWhy)
		return state.finish()
	end
	local saved = Fit.borrow()

	local store = findGui("ZyntraStore")
	local terminal = store and store:FindFirstChild("Terminal")
	local probe = store and store:FindFirstChild("UIRegressionZyntraStoreProbe")
	local opener = store and store:FindFirstChild("ZyntraOpenButton")
	if not (terminal and probe and probe:IsA("BindableFunction") and opener) then
		record(false, "the Zyntra terminal exists to be measured",
			string.format("terminal=%s probe=%s opener=%s",
				tostring(terminal ~= nil), tostring(probe ~= nil), tostring(opener ~= nil)))
		return state.finish()
	end
	local header = terminal:FindFirstChild("TerminalHeader")
	local tabs = terminal:FindFirstChild("TerminalTabs")
	local content = terminal:FindFirstChild("TerminalContent")
	local status = terminal:FindFirstChild("TerminalStatus")
	if not (header and tabs and content and status) then
		record(false, "the terminal shell exists to be measured",
			string.format("header=%s tabs=%s content=%s status=%s",
				tostring(header ~= nil), tostring(tabs ~= nil),
				tostring(content ~= nil), tostring(status ~= nil)))
		return state.finish()
	end

	local ran, runError = pcall(function()
		-- ---- calibration, at the REAL viewport ----------------------------
		workspace:SetAttribute("UIRegressionViewport", nil)
		workspace:SetAttribute("ForceTouchUI", nil)
		workspace:SetAttribute("UIRegressionSafeInsets", nil)
		resetScenario()
		probe:Invoke("open")
		task.wait(0.35)
		local realLayout = UIDevice.Layout()
		local shift = UIRegression.ScreenSpaceShift(terminal)
		local worst, worstName = 0, ""
		for _, object in ipairs({terminal, header, tabs, content, status}) do
			local resolved = UIRegression.ResolveRect(object, realLayout.Viewport, realLayout.Inset.Y)
			if resolved and not resolved.Unresolvable then
				local node = object :: any
				local live = {
					Left = node.AbsolutePosition.X,
					Top = node.AbsolutePosition.Y + shift,
					Right = node.AbsolutePosition.X + node.AbsoluteSize.X,
					Bottom = node.AbsolutePosition.Y + node.AbsoluteSize.Y + shift,
				}
				for _, edge in ipairs({"Left", "Top", "Right", "Bottom"}) do
					local delta = math.abs(resolved[edge] - live[edge])
					if delta > worst then worst, worstName = delta, object.Name .. "." .. edge end
				end
			else
				worst = math.huge
				worstName = object.Name .. " is unresolvable at the real viewport"
			end
		end
		record(worst <= 1,
			"the resolver reproduces the engine at the real viewport, so the"
			.. " per-device rectangles below mean something",
			string.format("worst edge error %.2fpx at %s", worst, worstName))

		-- THE EXPECTED TAB SET, derived INDEPENDENTLY of the terminal.
		--
		-- The old assertion was `#tabList >= 4`, which is vacuous in the exact
		-- direction that matters: a terminal that had silently stopped building
		-- its DEV page would still have four tabs and still pass. The authored
		-- set is stated here, and whether DEV belongs in it is answered by
		-- DevAccess -- the module the store itself consults -- rather than by the
		-- store's own report of what it happens to have built.
		-- SETTINGS is the accessibility page. It is in the authored set for every
		-- account, developer or not, so it is named here rather than left to the
		-- whitelist branch below.
		local expectedTabs = {"Upgrades", "Shop", "Donate", "Colors", "Settings"}
		local devExpected = DevAccess.IsAllowed(player)
		if devExpected then table.insert(expectedTabs, "Dev") end
		local tabList = {}
		for name in string.gmatch(tostring(probe:Invoke("tabs")), "[^,]+") do
			table.insert(tabList, name)
		end
		local tabsMatch = #tabList == #expectedTabs
		if tabsMatch then
			for index, name in ipairs(expectedTabs) do
				if tabList[index] ~= name then tabsMatch = false end
			end
		end
		record(tabsMatch,
			"the terminal builds EXACTLY the authored tab set, DEV included where"
			.. " DevAccess grants it",
			string.format("expected [%s] got [%s] devAccess=%s",
				table.concat(expectedTabs, ","), table.concat(tabList, ","),
				tostring(devExpected)))
		record(not devExpected or table.find(tabList, "Dev") ~= nil,
			"and this account's DEV page exists to be measured",
			devExpected and "DevAccess grants it" or "not a developer account")
		-- Nothing below may quietly measure fewer tabs than the contract names.
		tabList = expectedTabs

		-- ---- THE DONATION TIERS, as a SET and against a written-down oracle ----
		--
		-- C_ZYNTRA_ACTIONS_ARE_ENUMERATED_20260831. The old proof was a count:
		-- donationTierCount() cards and donationTierCount() buttons. Six copies of
		-- one tier satisfy that exactly as well as the six authored ones do, and so
		-- does six cards for the wrong six tiers. Three sets are compared here --
		-- the six keys named in Fit.DonationTierKeys, the keys ZyntraConfig actually
		-- carries, and the keys the store actually built -- because comparing only
		-- the last two proves they agree with each other and not that either is what
		-- was authored.
		local configuredTiers, configuredList = {}, {}
		for key in pairs(ZyntraConfig.Donations or {}) do
			configuredTiers[key] = true
			table.insert(configuredList, key)
		end
		table.sort(configuredList)
		local builtTiers, builtTierList = {}, {}
		for key in string.gmatch(tostring(probe:Invoke("donations")), "[^,]+") do
			builtTiers[key] = true
			table.insert(builtTierList, key)
		end
		local tierProblems = {}
		for _, key in ipairs(Fit.DonationTierKeys) do
			if not configuredTiers[key] then
				table.insert(tierProblems, "ZyntraConfig.Donations has no " .. key)
			end
			if not builtTiers[key] then
				table.insert(tierProblems, "the store never built a card for " .. key)
			end
		end
		for _, key in ipairs(configuredList) do
			if not table.find(Fit.DonationTierKeys, key) then
				table.insert(tierProblems, "ZyntraConfig.Donations carries an unauthored "
					.. key)
			end
		end
		for _, key in ipairs(builtTierList) do
			if not table.find(Fit.DonationTierKeys, key) then
				table.insert(tierProblems, "the store built an unauthored " .. key)
			end
		end
		-- DUPLICATES are the failure a set comparison alone cannot see: six cards
		-- all keyed to the same tier satisfy every membership test above.
		if #builtTierList ~= #Fit.DonationTierKeys then
			table.insert(tierProblems, string.format("the store built %d donation cards"
				.. " for %d authored tiers", #builtTierList, #Fit.DonationTierKeys))
		end
		record(#tierProblems == 0,
			"the Donate page builds EXACTLY the six authored tier keys -- the set, in"
			.. " both directions, against the config AND against the written oracle",
			string.format("authored [%s] config [%s] built [%s]; %s",
				table.concat(Fit.DonationTierKeys, ","), table.concat(configuredList, ","),
				table.concat(builtTierList, ","), table.concat(tierProblems, "; ")))

		-- The terminal's own card index, "page|card|action" per line, in build
		-- order. It says what the terminal was AUTHORED to hold, so a page that
		-- quietly built one card fewer fails below instead of passing for want of
		-- anything to check.
		local cardsByPage = Fit.parseZyntraCards(probe:Invoke("cards"))
		local actionTag = tostring(terminal:GetAttribute("TerminalActionTag") or "")
		record(actionTag ~= "",
			"the terminal publishes the tag its card actions carry, so the sweep can"
			.. " find the DISABLED ones a Visible+Active walk skips",
			actionTag == "" and "TerminalActionTag missing" or actionTag)
		if actionTag == "" then actionTag = "ZyntraTerminalAction" end

		-- ---- per device ----------------------------------------------------
		for _, device in ipairs(Fit.Devices) do
			local applied = Fit.apply(device)
			record(applied, device.Name .. ": the device override took before the row ran",
				applied and "" or "timed out waiting for UIDevice to report it")
			probe:Invoke("open")
			probe:Invoke("relayout")
			task.wait(0.25)

			local layout = UIDevice.Layout()
			local viewport, insetY = device.Size, layout.Inset.Y
			state.note(string.format("--- %s (reported %.0fx%.0f class=%s touch=%s) ---",
				device.Name, layout.Width, layout.Height, layout.Class,
				tostring(layout.IsTouch)))
			record(layout.Width == viewport.X and layout.Height == viewport.Y
				and layout.IsTouch == device.Touch and layout.Class == device.Class
				and layout.Portrait == device.Portrait,
				device.Name .. ": the device override took",
				string.format("%.0fx%.0f class=%s touch=%s portrait=%s",
					layout.Width, layout.Height, layout.Class,
					tostring(layout.IsTouch), tostring(layout.Portrait)))

			record((terminal :: any).Visible == true
				and player:GetAttribute("ZyntraStoreOpen") == true,
				device.Name .. ": the production toggle opened the terminal",
				string.format("visible=%s attribute=%s", tostring((terminal :: any).Visible),
					tostring(player:GetAttribute("ZyntraStoreOpen"))))

			-- ---- THE WAY OUT, on every fixture ------------------------------
			--
			-- C_ZYNTRA_ACTIONS_ARE_ENUMERATED_20260831. The header was only ever
			-- measured for SIZE, and only on touch, through Fit.interactive -- which
			-- filters on Visible AND Active before it returns anything. So a
			-- CloseTerminal left out of the input stack, or dropped from the build
			-- entirely, produced an EMPTY sweep and a passing row: a modal that opens
			-- over the whole screen with no way out of it, on every device, and the
			-- matrix silent. Presence, Visible and Active are asserted directly here,
			-- on pointer devices too.
			local closeButton = header:FindFirstChild("CloseTerminal", true)
			record(closeButton ~= nil and (closeButton :: any).Visible == true
				and (closeButton :: any).Active == true,
				device.Name .. ": CloseTerminal is drawn AND in the input stack while the"
				.. " terminal is open",
				closeButton and string.format("visible=%s active=%s %s",
					tostring((closeButton :: any).Visible),
					tostring((closeButton :: any).Active),
					Fit.text(Fit.live(closeButton))) or "CloseTerminal missing")
			local headerDead, headerControls = {}, 0
			for _, node in ipairs(header:GetDescendants()) do
				if node:IsA("TextButton") or node:IsA("ImageButton") then
					headerControls += 1
					if (node :: any).Visible ~= true or (node :: any).Active ~= true then
						table.insert(headerDead, string.format("%s visible=%s active=%s",
							node.Name, tostring((node :: any).Visible),
							tostring((node :: any).Active)))
					end
				end
			end
			record(headerControls > 0 and #headerDead == 0,
				device.Name .. ": and every control the header draws is Visible and Active,"
				.. " counted before it is filtered",
				string.format("%d controls; %s", headerControls,
					#headerDead == 0 and "all live" or table.concat(headerDead, "; ")))
			for _, readout in ipairs({"TerminalTitle", "TokenReadout"}) do
				local node = header:FindFirstChild(readout, true)
				record(node ~= nil and (node :: any).Visible == true,
					device.Name .. ": the header still draws " .. readout,
					node and tostring((node :: any).Visible) or "missing")
			end

			local modal = layout.ModalViewport
			local shellRects = {}
			local unresolved = nil
			for _, object in ipairs({terminal, header, tabs, content, status}) do
				local rect = UIRegression.ResolveRect(object, viewport, insetY)
				if not rect or rect.Unresolvable then
					unresolved = object.Name .. ": " .. tostring(rect and rect.Unresolvable or "nil")
				end
				shellRects[object.Name] = rect
			end
			record(unresolved == nil,
				device.Name .. ": every shell rectangle is analytically resolvable",
				unresolved)

			local terminalRect = shellRects.Terminal
			state.note(string.format("      Terminal %s  modal viewport (%.0f,%.0f)-(%.0f,%.0f)",
				Fit.text(terminalRect), modal.Left, modal.Top, modal.Right, modal.Bottom))

			-- THE ASSERTION THE OLD ROW DID NOT MAKE. The terminal must lie inside
			-- the MODAL viewport -- the true safe area -- and not inside the HUD
			-- band it used to be sized from.
			record(Fit.within(terminalRect, modal, 1),
				device.Name .. ": the terminal lies inside the modal safe viewport",
				Fit.text(terminalRect))
			record(terminalRect ~= nil and terminalRect.Left >= -1
				and terminalRect.Top >= -1
				and terminalRect.Right <= viewport.X + 1
				and terminalRect.Bottom <= viewport.Y + 1,
				device.Name .. ": and is entirely on screen", Fit.text(terminalRect))

			-- Positive, non-overlapping shell rectangles. `content` with a
			-- negative height is precisely what shipped.
			local order = {"TerminalHeader", "TerminalTabs", "TerminalContent", "TerminalStatus"}
			local smallest, smallestName = math.huge, ""
			for _, name in ipairs(order) do
				local rect = shellRects[name]
				local area = rect and math.min(rect.Width, rect.Height) or -1
				if area < smallest then smallest, smallestName = area, name end
				state.note(string.format("      %-16s %s", name, Fit.text(rect)))
			end
			record(smallest > 0,
				device.Name .. ": header, tabs, content and status all have positive size",
				string.format("smallest dimension %.0f at %s", smallest, smallestName))
			record(shellRects.TerminalContent ~= nil
				and shellRects.TerminalContent.Height >= 96,
				device.Name .. ": the active page has a usable height",
				shellRects.TerminalContent
					and string.format("%.0f", shellRects.TerminalContent.Height) or "no rect")

			local worstPair, worstArea = "", 0
			for i = 1, #order do
				for j = i + 1, #order do
					local a, b = shellRects[order[i]], shellRects[order[j]]
					if a and b and Fit.overlaps(a, b) then
						local area = (math.min(a.Right, b.Right) - math.max(a.Left, b.Left))
							* (math.min(a.Bottom, b.Bottom) - math.max(a.Top, b.Top))
						if area > worstArea then
							worstArea, worstPair = area, order[i] .. " x " .. order[j]
						end
					end
				end
			end
			record(worstArea == 0,
				device.Name .. ": no two shell rectangles overlap",
				string.format("%.0f px^2 at %s", worstArea, worstPair))
			for _, name in ipairs(order) do
				record(Fit.within(shellRects[name], terminalRect, 1),
					device.Name .. ": " .. name .. " stays inside the terminal",
					Fit.text(shellRects[name]))
			end

			-- ---- the opener and the movement controls stand down -----------
			record((opener :: any).Visible == false and (opener :: any).Active == false,
				device.Name .. ": the ZYNTRA // EQUIPMENT opener is neither drawn nor"
				.. " in the input stack behind its own modal",
				string.format("visible=%s active=%s",
					tostring((opener :: any).Visible), tostring((opener :: any).Active)))
			if device.Touch then
				record(UIDevice.TouchMovementSuppressed() == true,
					device.Name .. ": the engine's own thumbstick stands down under the modal",
					tostring(UIDevice.TouchMovementSuppressed()))
				local live = 0
				local liveNames = {}
				for movementName in pairs(MOVEMENT_CONTROLS) do
					local node = nil
					for _, screen in ipairs(playerGui():GetChildren()) do
						if screen:IsA("ScreenGui") and screen.Enabled and not ENGINE_GUIS[screen.Name] then
							node = screen:FindFirstChild(movementName, true)
							if node then break end
						end
					end
					if node and (node :: any).Active == true and (node :: any).Visible == true then
						live += 1
						table.insert(liveNames, movementName)
					end
				end
				record(live == 0,
					device.Name .. ": and no game movement control is left active under it",
					table.concat(liveNames, ", "))
			end

			-- ---- every tab, including DEV ----------------------------------
			local liveContent = Fit.live(content)
			local liveTabs = Fit.live(tabs)
			local tabTotal, tabWorst, tabWorstName = 0, math.huge, ""
			for index, name in ipairs(tabList) do
				local tabButton = (tabs :: any):FindFirstChild(name .. "Tab")
				if not tabButton then
					record(false, device.Name .. ": tab " .. name .. " exists", "not found")
				else
					local rect = Fit.live(tabButton)
					tabTotal += rect.Width + (index > 1 and 10 or 0)
					local axis = math.min(rect.Width, rect.Height)
					if axis < tabWorst then tabWorst, tabWorstName = axis, name end
					if device.Touch then
						record(rect.Height >= 44,
							device.Name .. ": tab " .. name .. " is at least 44 tall",
							string.format("%.0fx%.0f", rect.Width, rect.Height))
					end
				end
			end
			record(tabWorst > 0, device.Name .. ": every tab has positive size",
				string.format("smallest %.0f at %s", tabWorst, tabWorstName))
			-- ORDER, not just presence. The bar's UIListLayout breaks LayoutOrder
			-- ties by NAME, so the moment the tabs were given names for this
			-- matrix to find them they silently re-sorted alphabetically --
			-- COLORS, DEV, DONATE, SHOP, UPGRADES instead of the authored
			-- UPGRADES ... DEV. Presence assertions cannot see that; left-edge
			-- order can.
			local misordered = nil
			local previousLeft = -math.huge
			for _, name in ipairs(tabList) do
				local tabButton = (tabs :: any):FindFirstChild(name .. "Tab")
				local rect = tabButton and Fit.live(tabButton)
				if rect then
					if rect.Left <= previousLeft then
						misordered = name .. " at x " .. string.format("%.0f", rect.Left)
							.. " is not right of the tab before it"
					end
					previousLeft = rect.Left
				end
			end
			record(misordered == nil,
				device.Name .. ": the tabs run left to right in their authored order",
				misordered)
			-- REACHABILITY, which is the whole point of the scrolling bar: either
			-- the tabs fit the bar, or the bar scrolls to them. Never neither.
			local canvas = (tabs :: any).AbsoluteCanvasSize
			record(liveTabs ~= nil and (tabTotal <= liveTabs.Width + 1
					or ((tabs :: any).ScrollingEnabled == true and canvas.X + 1 >= tabTotal)),
				device.Name .. ": every tab is reachable -- the row fits the bar or the"
				.. " bar scrolls to it",
				string.format("tabs %.0f, bar %.0f, canvas %.0f, scrolling=%s",
					tabTotal, liveTabs and liveTabs.Width or -1, canvas.X,
					tostring((tabs :: any).ScrollingEnabled)))

			for _, name in ipairs(tabList) do
				local selected = probe:Invoke("tab:" .. name)
				task.wait(0.12)
				record(selected == name, device.Name .. " / " .. name .. ": the tab selects",
					tostring(selected))
				local page = (content :: any):FindFirstChild(name)
				if not page then
					record(false, device.Name .. " / " .. name .. ": the page exists", "not found")
					continue
				end
				local pageRect = Fit.live(page)
				record((page :: any).Visible == true and pageRect.Width > 0 and pageRect.Height > 0
					and Fit.within(pageRect, liveContent, 2),
					device.Name .. " / " .. name .. ": the page fills the content box and"
					.. " does not leave it",
					Fit.text(pageRect))

				-- The overflow route. Every page whose content can exceed its box
				-- must have a scroll, and the scroll must stay inside the box: this
				-- is what makes "the cards are contained" true without hiding
				-- anything from the player.
				local scroll = nil
				for _, node in ipairs(page:GetDescendants()) do
					if node:IsA("ScrollingFrame") then scroll = node break end
				end
				record(scroll ~= nil,
					device.Name .. " / " .. name .. ": the page can scroll its overflow",
					scroll and scroll.Name or "no ScrollingFrame")
				local scrollRect = scroll and Fit.live(scroll)
				if scroll then
					record(Fit.within(scrollRect, pageRect, 2),
						device.Name .. " / " .. name .. ": and its scroll stays inside the page",
						Fit.text(scrollRect))
					-- Cards and rows are laid out by a grid or a list inside that
					-- scroll. They may run PAST its bottom -- that is what scrolling
					-- is -- but never past its sides, which is the failure mode a
					-- fixed 0.5-width cell produces on a narrow screen.
					local escaped, escapedName = 0, ""
					for _, child in ipairs(scroll:GetChildren()) do
						if child:IsA("GuiObject") and child.Visible then
							local rect = Fit.live(child)
							if rect.Width <= 0 or rect.Height <= 0 then
								escaped += 1
								escapedName = child.Name .. " has size "
									.. string.format("%.0fx%.0f", rect.Width, rect.Height)
							elseif rect.Left < scrollRect.Left - 2
								or rect.Right > scrollRect.Right + 2 then
								escaped += 1
								escapedName = child.Name .. " at x "
									.. string.format("%.0f..%.0f vs %.0f..%.0f", rect.Left,
										rect.Right, scrollRect.Left, scrollRect.Right)
							end
						end
					end
					record(escaped == 0,
						device.Name .. " / " .. name .. ": every card or row is contained"
						.. " horizontally and none has a zero or negative size",
						escapedName)
				end

				-- WHAT THE PAGE MUST CONTAIN, stated here rather than counted from
				-- whatever the page happens to hold. A page that built nothing
				-- would otherwise pass every containment and tap-target check in
				-- this matrix trivially, because there would be nothing to fail.
				local expectedRows = PAGE_CONTENT[name]
				if name == "Donate" then
					-- The authored tier count, read from the same config the
					-- store builds its cards from.
					local tiers = donationTierCount()
					expectedRows = {Rows = tiers, Actions = tiers}
				end
				if name == "Settings" then
					-- SAME IDIOM, and for the same reason Donate does not use its
					-- PAGE_CONTENT literal: the authored switch count is
					-- ZyntraConfig.AccessibilitySettings minus the entries it marks
					-- Hidden. A literal 2 here would be exactly what the store's
					-- emergency two-key fallback draws, so the one failure this
					-- check exists to catch -- the config list going missing and the
					-- page silently dropping to that fallback -- would pass clean.
					-- The PAGE_CONTENT floor stands only when the config carries no
					-- list at all, which is the case the fallback answers.
					local switches = 0
					for _, entry in ipairs(ZyntraConfig.AccessibilitySettings or {}) do
						if type(entry) == "table" and entry.Hidden ~= true then
							switches += 1
						end
					end
					if switches > 0 then
						expectedRows = {Rows = switches, Actions = switches}
					end
					-- The count alone cannot see the Hidden filter INVERTING -- four
					-- rows drawn still clears a floor of three -- and Hidden is not
					-- cosmetic: DisableCaptions and CaptionsEnabled are two halves of
					-- one caption pair, so a terminal that draws both offers the
					-- player contradicting switches. Rows are named by their
					-- attribute key, so this is a lookup.
					if scroll then
						local shown: string? = nil
						for _, entry in ipairs(ZyntraConfig.AccessibilitySettings or {}) do
							if type(entry) == "table" and entry.Hidden == true
								and type(entry.Key) == "string"
								and scroll:FindFirstChild(entry.Key) then
								shown = entry.Key
							end
						end
						record(shown == nil,
							device.Name .. " / Settings: no switch the config marks Hidden"
							.. " is drawn", shown)
					end
				end
				if expectedRows and scroll then
					local drawn, actions = 0, 0
					for _, child in ipairs(scroll:GetChildren()) do
						if child:IsA("GuiObject") and child.Visible then
							drawn += 1
							for _, node in ipairs(child:GetDescendants()) do
								if node:IsA("TextButton") or node:IsA("ImageButton") then
									actions += 1
								end
							end
						end
					end
					record(drawn >= expectedRows.Rows and actions >= expectedRows.Actions,
						string.format("%s / %s: holds its authored content (%d+ rows,"
							.. " %d+ actions)", device.Name, name,
							expectedRows.Rows, expectedRows.Actions),
						string.format("%d rows, %d actions", drawn, actions))
					-- Sibling ORDER and non-overlap inside the scroll. A grid or
					-- list that collapses puts every cell at the same origin, and
					-- a containment test alone cannot see that.
					local previousBottom, disorder = -math.huge, nil
					local rows = {}
					for _, child in ipairs(scroll:GetChildren()) do
						if child:IsA("GuiObject") and child.Visible then
							table.insert(rows, {Object = child, Rect = Fit.live(child)})
						end
					end
					table.sort(rows, function(a, b)
						if math.abs(a.Rect.Top - b.Rect.Top) > 1 then
							return a.Rect.Top < b.Rect.Top
						end
						return a.Rect.Left < b.Rect.Left
					end)
					for index = 1, #rows do
						for other = index + 1, #rows do
							if Fit.overlaps(rows[index].Rect, rows[other].Rect) then
								disorder = rows[index].Object.Name .. " overlaps "
									.. rows[other].Object.Name
							end
						end
					end
					record(disorder == nil,
						string.format("%s / %s: no two cards or rows overlap each other",
							device.Name, name), disorder)
					-- CANVAS REACHABILITY, measured from the TOP of the canvas.
					--
					-- C_ZYNTRA_SCROLL_IS_NOT_A_PROOF_20260831 -- WHAT SHIPPED BROKEN
					-- in the tests. `lowest` was the distance from the SCROLL's top
					-- edge to the last row as both happened to be sitting, and a page
					-- already scrolled down reports its last row much closer to that
					-- edge -- in the limit, inside the viewport. So the more content a
					-- page had pushed above the fold, the EASIER this was to satisfy,
					-- and a page left scrolled by an earlier row of the matrix carried
					-- that excuse into this one. The canvas is put back to zero, the
					-- rows are re-measured against that, and the player's own scroll
					-- position is handed straight back.
					local savedCanvasPosition = (scroll :: any).CanvasPosition
					;(scroll :: any).CanvasPosition = Vector2.new(0, 0)
					task.wait()
					local canvas = (scroll :: any).AbsoluteCanvasSize
					local topScrollRect = Fit.live(scroll)
					local lowest = 0
					for _, row in ipairs(rows) do
						lowest = math.max(lowest,
							Fit.live(row.Object).Bottom - topScrollRect.Top)
					end
					local visibleHeight = topScrollRect.Height
					local scrollingEnabled = (scroll :: any).ScrollingEnabled == true
					;(scroll :: any).CanvasPosition = savedCanvasPosition
					-- A ZERO canvas is only acceptable when the last row is already
					-- inside the visible scrolling viewport. `or canvas.Y <= 0`
					-- alone excused every collapsed page: no canvas, no overflow,
					-- no failure -- which is exactly backwards.
					local reachable = lowest <= canvas.Y + 2
						or (canvas.Y <= 0 and lowest <= visibleHeight + 2)
					record(reachable,
						string.format("%s / %s: the scroll canvas reaches its last row,"
							.. " measured from a canvas reset to zero", device.Name, name),
						string.format("last row ends at %.0f, canvas %.0f, viewport %.0f",
							lowest, canvas.Y, visibleHeight))
					-- A canvas the player cannot MOVE is not a route to the overflow.
					-- Where the content genuinely runs past the viewport, the frame has
					-- to be scrollable; the terminal states ScrollingEnabled = true on
					-- all five page scrolls where it builds them, and this is the half
					-- that checks the statement survived the layout.
					record(lowest <= visibleHeight + 2 or scrollingEnabled,
						string.format("%s / %s: and where the content overflows the"
							.. " viewport the page can actually be scrolled",
							device.Name, name),
						string.format("content %.0f in a %.0f viewport, scrolling=%s",
							lowest, visibleHeight, tostring(scrollingEnabled)))
					-- REAL TEXT FIT. Every visible string on the page must fit the
					-- box it is drawn in, or be a deliberately wrapped label with
					-- room for the lines it needs.
					local clipped = nil
					for _, node in ipairs(page:GetDescendants()) do
						if (node:IsA("TextLabel") or node:IsA("TextButton"))
							and node.Visible and (node :: any).Text ~= ""
							and (node :: any).TextTruncate == Enum.TextTruncate.None
							and not (node :: any).TextScaled then
							local box = Fit.live(node)
							local bounds = (node :: any).TextBounds
							-- BOTH axes. A single-line label that is too WIDE
							-- overflows sideways and reported nothing, because
							-- only the height was ever compared.
							local wrapped = (node :: any).TextWrapped
							if box.Width > 1
								and (bounds.Y > box.Height + 1
									or (not wrapped and bounds.X > box.Width + 1)) then
								clipped = string.format("%s needs %.0fx%.0f in %.0fx%.0f (wrapped=%s)",
									node.Name, bounds.X, bounds.Y, box.Width, box.Height,
									tostring(wrapped))
							end
						end
					end
					record(clipped == nil,
						string.format("%s / %s: no visible string overflows its own box",
							device.Name, name), clipped)

					-- THE TWO NAMED PROOFS, kept separate from the sweep above on
					-- purpose. The generic pass reads TextBounds, which is what
					-- the engine DECIDED to draw; these re-measure the same
					-- strings through TextService at the face and box width the
					-- label actually carries, so a label whose bounds were stale
					-- or clamped cannot hide behind them. They also name the
					-- defect, so a regression report says which card broke rather
					-- than "a TextLabel".
					--
					-- SHOP. The two-column breakpoint used to arrive at 568x320
					-- and hand each product a 134x68 description box for copy
					-- that measures 72-84px; 667x375 needed 72. The box has to
					-- hold the copy at its own width, on every device.
					if name == "Shop" then
						local worst, worstName = nil, nil
						for _, node in ipairs(page:GetDescendants()) do
							if node.Name == "ProductDescription" and node:IsA("TextLabel")
								and node.Visible and node.Text ~= "" then
								local box = Fit.live(node)
								local need = Fit.measureText(node.Text, node.FontFace,
									node.TextSize, box.Width)
								if need and need.Y > box.Height + 1
									and (worst == nil or need.Y - box.Height > worst) then
									worst = need.Y - box.Height
									worstName = string.format("%s: %.0fpx of copy at %dpx"
										.. " in a %.0fx%.0f box",
										(node.Parent :: any).Name, need.Y, node.TextSize,
										box.Width, box.Height)
								end
							end
						end
						record(worst == nil, string.format("%s / Shop: every product"
							.. " description box holds its own copy at its own width",
							device.Name), worstName)
					end
					-- COLOURS. "GLOWSTICK LIGHT" measures about 153px at the
					-- authored 18px face and the heading box is 149 wide at
					-- 375x667 -- narrower still at 338x705. The heading is not
					-- wrapped, so it simply ran out over the preview swatch.
					if name == "Colors" then
						local overflow = nil
						for _, node in ipairs(page:GetDescendants()) do
							if node.Name == "Title" and node:IsA("TextLabel")
								and node.Visible and node.Text ~= "" then
								local box = Fit.live(node)
								local need = Fit.measureText(node.Text, node.FontFace,
									node.TextSize, node.TextWrapped and box.Width or nil)
								local tooWide = need and not node.TextWrapped
									and need.X > box.Width + 1
								local tooTall = need and need.Y > box.Height + 1
								if (tooWide or tooTall) and overflow == nil then
									overflow = string.format("%s %q needs %.0fx%.0f at"
										.. " %dpx in a %.0fx%.0f box (wrapped=%s)",
										(node.Parent :: any).Name, node.Text,
										need.X, need.Y, node.TextSize, box.Width,
										box.Height, tostring(node.TextWrapped))
								end
							end
						end
						record(overflow == nil, string.format("%s / Colors: every picker"
							.. " heading fits its own box", device.Name), overflow)
					end
				end

				-- ---- EVERY CARD ACTION, THE DISABLED ONES INCLUDED --------------
				--
				-- C_ZYNTRA_ACTIONS_ARE_ENUMERATED_20260831. Enumerated through the
				-- CollectionService tag rather than by walking Visible+Active
				-- descendants, because an OWNED product, a COMING SOON tier and a
				-- LEVEL 3 ONLY dev row are all Visible, full-size and NOT Active --
				-- which is exactly the state the tap floor has to hold in, and exactly
				-- the state the old sweep filtered away before it counted anything.
				--
				-- The floor comes from the terminal's own TerminalTapFloor, rewritten
				-- every layout pass with the number the actions were actually sized
				-- against, so this measures the terminal against itself instead of the
				-- harness restating 44 and agreeing with its own copy of the constant.
				-- 44 is still the FLOOR under that floor: a terminal that published 20
				-- would otherwise licence 20px targets.
				-- 44 IS A TOUCH REQUIREMENT, and only a touch requirement. It is the
				-- minimum a finger can reliably hit; a mouse pointer is a single
				-- pixel and the terminal deliberately draws a tighter 32px row on a
				-- pointer device, which is the composition every desktop screenshot
				-- in this project shows. Asserting 44 there failed ten rows for
				-- doing exactly what the design says, and "fixing" production to
				-- satisfy it would have inflated the desktop terminal by a third.
				-- The floor still exists on pointer devices -- it is just the
				-- pointer floor -- and the published number is still held to it, so
				-- a terminal that published 12 fails on any device.
				local publishedFloor = tonumber(terminal:GetAttribute("TerminalTapFloor"))
				local requiredFloor = device.Touch and 44 or 32
				record(publishedFloor ~= nil and publishedFloor >= requiredFloor,
					string.format("%s / %s: the terminal publishes the tap floor it sized"
						.. " its actions against, and it is at least %d (%s device)",
						device.Name, name, requiredFloor,
						device.Touch and "touch" or "pointer"),
					tostring(terminal:GetAttribute("TerminalTapFloor")))
				local tapFloor = math.max(publishedFloor or Fit.ZyntraFloorFallback, requiredFloor)
				local authoredCards = cardsByPage[name]
				record(authoredCards ~= nil and #authoredCards > 0,
					device.Name .. " / " .. name .. ": the terminal's card contract names"
					.. " what this page was authored to hold",
					authoredCards and string.format("%d cards", #authoredCards)
						or "no contract lines for this page")
				local actionProblems = Fit.zyntraActionProblems(page, name, actionTag,
					tapFloor, device.Touch, authoredCards)
				record(#actionProblems == 0,
					device.Name .. " / " .. name .. ": every authored card has exactly one"
					.. " tagged action, drawn at the terminal's own tap floor on both axes"
					.. " -- disabled ones included -- and nothing has left the input stack"
					.. " without saying why",
					table.concat(actionProblems, "; "))

				-- HOW MANY THE PLAYER CAN ACTUALLY PRESS, stated per tab.
				--
				-- Three pages have a reachable count that does not depend on this
				-- account at all, and those are asserted as exact numbers. Shop and Dev
				-- do depend on it -- what this account owns, and whether it is in Level
				-- 3 -- so restating a literal for them would only encode one tester's
				-- save file. They are held to the complete accounting instead: every
				-- authored action is either reachable or stood down for a reason the
				-- button itself states, and the two add up to the whole contract.
				local taggedActions = Fit.zyntraActions(page, actionTag)
				local activeActions, statedDown = 0, 0
				for _, action in ipairs(taggedActions) do
					if (action :: any).Active == true and (action :: any).Visible == true then
						activeActions += 1
					end
					if Fit.zyntraDisabledReason(action) ~= nil then statedDown += 1 end
				end
				local expectedActive = Fit.ZyntraExpectedActive[name]
				if name == "Donate" then
					-- Every tier with a configured product id, read from ZyntraConfig.
					-- A zero id is the store's own "COMING SOON" case and it is the one
					-- thing that legitimately lowers this number.
					expectedActive = 0
					for _, key in ipairs(Fit.DonationTierKeys) do
						local tier = (ZyntraConfig.Donations or {})[key]
						if tier and (tonumber((tier :: any).Id) or 0) > 0 then
							expectedActive += 1
						end
					end
				end
				if expectedActive ~= nil then
					record(activeActions == expectedActive,
						string.format("%s / %s: exactly %d of its card actions are reachable",
							device.Name, name, expectedActive),
						string.format("%d reachable of %d tagged, %d stood down with a reason",
							activeActions, #taggedActions, statedDown))
				else
					record(authoredCards ~= nil
						and activeActions + statedDown == #authoredCards,
						string.format("%s / %s: every authored action is either reachable or"
							.. " stood down for a stated reason, and the two account for the"
							.. " whole contract", device.Name, name),
						string.format("%d reachable + %d stood down vs %d authored",
							activeActions, statedDown,
							authoredCards and #authoredCards or -1))
				end

				-- ---- DONATE: the tier the card CARRIES, not the tier it looks like --
				if name == "Donate" then
					local tierProblems = {}
					for _, key in ipairs(Fit.DonationTierKeys) do
						local cards = {}
						for _, node in ipairs(page:GetDescendants()) do
							if node:IsA("GuiObject")
								and node:GetAttribute("DonationTierKey") == key then
								table.insert(cards, node)
							end
						end
						if #cards ~= 1 then
							table.insert(tierProblems, string.format(
								"%d cards carry DonationTierKey=%s", #cards, key))
							continue
						end
						local actions = {}
						for _, action in ipairs(taggedActions) do
							if action:IsDescendantOf(cards[1]) then
								table.insert(actions, action)
							end
						end
						if #actions ~= 1 then
							table.insert(tierProblems, string.format(
								"the %s card holds %d tagged actions, not exactly one",
								key, #actions))
						elseif actions[1]:GetAttribute("ZyntraCardKey") ~= key then
							table.insert(tierProblems, string.format(
								"the %s card's action is keyed to %s", key,
								tostring(actions[1]:GetAttribute("ZyntraCardKey"))))
						end
						local configured = (ZyntraConfig.Donations or {})[key]
						local declaredId = cards[1]:GetAttribute("DonationProductId")
						if configured == nil then
							table.insert(tierProblems, key .. " is not in ZyntraConfig")
						elseif declaredId ~= (configured :: any).Id then
							table.insert(tierProblems, string.format(
								"the %s card advertises product %s, the config says %s", key,
								tostring(declaredId), tostring((configured :: any).Id)))
						end
					end
					record(#tierProblems == 0,
						device.Name .. " / Donate: each of the six tiers has exactly one card"
						.. " and exactly one action, matched through DonationTierKey and"
						.. " selling the product the config names",
						table.concat(tierProblems, "; "))
				end

				-- ---- COLORS: three rectangles, not one string ---------------------
				--
				-- The heading, the preview swatch and the Save button share the card's
				-- top row and are placed with three independent offsets. The matrix
				-- proved only that the heading's COPY fit its own box -- which says
				-- nothing about the box landing on top of the swatch, and "GLOWSTICK
				-- LIGHT" over a colour preview is the same unreadable row either way.
				if name == "Colors" then
					local colourProblems = {}
					local pickerCards = 0
					for _, card in ipairs(page:GetDescendants()) do
						if card:IsA("GuiObject") and card:GetAttribute("ZyntraPage") == "Colors"
							and card:GetAttribute("ZyntraCardKey") ~= nil
							and not (card:IsA("TextButton") or card:IsA("ImageButton")) then
							pickerCards += 1
							local parts = {}
							for _, partName in ipairs({"Title", "Preview", "Save"}) do
								local node = card:FindFirstChild(partName)
								if not node or not node:IsA("GuiObject") then
									table.insert(colourProblems, string.format("%s has no %s",
										card.Name, partName))
								elseif (node :: any).Visible ~= true then
									table.insert(colourProblems, string.format(
										"%s.%s is not drawn", card.Name, partName))
								else
									table.insert(parts, {Name = partName, Rect = Fit.live(node)})
								end
							end
							for index = 1, #parts do
								for other = index + 1, #parts do
									if Fit.overlaps(parts[index].Rect, parts[other].Rect) then
										table.insert(colourProblems, string.format(
											"%s.%s %s overlaps %s.%s %s", card.Name,
											parts[index].Name, Fit.text(parts[index].Rect),
											card.Name, parts[other].Name,
											Fit.text(parts[other].Rect)))
									end
								end
							end
						end
					end
					-- The sweep above says nothing at all if it found no cards, so the
					-- two authored pickers are counted as well.
					record(pickerCards == 2 and #colourProblems == 0,
						device.Name .. " / Colors: both picker cards draw their heading, preview"
						.. " swatch and SAVE button as three separate rectangles",
						string.format("%d picker cards; %s", pickerCards,
							#colourProblems == 0 and "no overlaps"
								or table.concat(colourProblems, "; ")))
				end

				-- Tap targets, swept rather than declared: these controls are built
				-- by loops over config, so a named list would quietly stop covering
				-- whatever was added last.
				if device.Touch then
					local small, smallName = 0, ""
					for _, entry in ipairs(Fit.interactive(page)) do
						if entry.Rect.Width < 44 or entry.Rect.Height < 44 then
							small += 1
							smallName = entry.Object.Name .. " "
								.. string.format("%.0fx%.0f", entry.Rect.Width, entry.Rect.Height)
						end
					end
					record(small == 0,
						device.Name .. " / " .. name .. ": every touch action on the page is"
						.. " at least 44x44",
						string.format("%d under floor, e.g. %s", small, smallName))
					local glyph = Fit.keyGlyph(page)
					record(glyph == nil,
						device.Name .. " / " .. name .. ": and prints no keyboard glyph", glyph)
				end
			end

			-- The header's own controls, which live outside the pages.
			if device.Touch then
				local small, smallName = 0, ""
				for _, entry in ipairs(Fit.interactive(header)) do
					if entry.Rect.Width < 44 or entry.Rect.Height < 44 then
						small += 1
						smallName = entry.Object.Name .. " "
							.. string.format("%.0fx%.0f", entry.Rect.Width, entry.Rect.Height)
					end
				end
				record(small == 0,
					device.Name .. ": the header's own controls are at least 44x44", smallName)
			end
			probe:Invoke("tab:" .. tabList[1])
			probe:Invoke("close")
			task.wait(0.15)
		end
	end)

	pcall(resetScenario)
	task.wait(0.15)
	Fit.restore(saved)
	task.wait(0.2)
	if not ran then
		state.Failures += 1
		state.Checks += 1
		state.note("  FAIL the zyntra terminal fit matrix ran  (" .. tostring(runError) .. ")")
	end
	local residue, residueNote = Fit.residue(saved)
	if residueNote then state.note(residueNote) end
	record(#residue == 0,
		"the matrix restored every borrowed attribute, every borrowed ScreenGui's"
			.. " Enabled and every borrowed descendant's Visible, Active and"
			.. " CanvasPosition, the terminal tab, the reader state and the caption",
		table.concat(residue, "; "))
	return state.finish()
end

function UIRegression.ZyntraTerminalFitMatrix(token: string?): (string, number)
	return Fit.lane("ZyntraTerminalFitMatrix", token, Fit.bodyZyntraTerminalFitMatrix)
end

-- ---------------------------------------------------------------------------
-- ObjectiveCornerMatrix
-- ---------------------------------------------------------------------------

-- All three levels' persistent objective readouts, forced into every state they
-- have, at every device in the matrix. The question it answers is the one the
-- old suite could not even ask: not "does this rectangle avoid the movement
-- zones" -- the corridor and bottom-band placements it replaced both did -- but
-- "is it in the UPPER RIGHT of the true safe area", which is where the player
-- was told to look for it.
--
-- C_ONE_RIGHT_EDGE_20260831 -- WHAT SHIPPED BROKEN in the tests.
--
-- The right edge used to be accepted as EITHER the safe right edge OR the
-- control column's left edge minus a gutter, and the comment that stood here
-- called that "the only two answers". It was one answer too many. A disjunction
-- passes whenever either half holds, so the assertion was satisfied by the very
-- placement the product forbids: on 956x440 the readout stepped left to x 780,
-- 117px short of the corner, and this predicate called it correct because the
-- column edge was one of its two accepted answers. A test that accepts the bug
-- it was written to catch proves nothing about the good case either.
--
-- UIDevice.TopRightPanel no longer has a second answer to offer -- on touch its
-- contract is now flat, "Right IS ALWAYS Safe.Right - margin, and what varies is
-- HEIGHT", with the cluster reflowing into a bottom row when the column would
-- leave no headroom -- so the assertion states that single number and nothing
-- else. Not a fraction of the width, not a range, not an alternative: the panel
-- ends at Safe.Right minus the one authored margin (OBJECTIVE_MARGIN = 8 on
-- touch, 18 on a pointer), within AnchorSlack.
Fit.AnchorSlack = 2

-- EVERY CHILD of a panel: inside it, not on top of a sibling, and its string
-- inside its own box.
--
-- WHAT SHIPPED BROKEN in the tests: the objective matrices asserted the outer
-- rectangle's position and nothing else, so a panel could sit perfectly in the
-- upper-right corner with all four of its rows rendering outside it -- which is
-- exactly what 568x320 did. An outer rectangle is not a layout.
function Fit.childProblems(panel, label): {string}
	local problems = {}
	if not panel then return {label .. " was not measured"} end
	-- One frame, so AbsolutePosition reflects the layout pass that just ran
	-- rather than the one before it. Measuring a rect the engine has not
	-- committed yet produces failures nobody can reproduce.
	task.wait()
	local box = Fit.live(panel)
	local children = {}
	for _, child in ipairs(panel:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			local rect = Fit.live(child)
			if rect.Width <= 0 or rect.Height <= 0 then
				table.insert(problems, string.format("%s.%s has size %.0fx%.0f",
					label, child.Name, rect.Width, rect.Height))
			end
			if not Fit.within(rect, box, 1) then
				table.insert(problems, string.format("%s.%s at %s escapes %s",
					label, child.Name, Fit.text(rect), Fit.text(box)))
			end
			-- The STRING, not just the box. A wrapped label whose copy needs more
			-- lines than its height allows renders them outside itself.
			if (child:IsA("TextLabel") or child:IsA("TextButton"))
				and (child :: any).Text ~= ""
				and (child :: any).TextTruncate == Enum.TextTruncate.None
				and not (child :: any).TextScaled then
				local bounds = (child :: any).TextBounds
				-- BOTH axes: a non-wrapping label wider than its box runs out
				-- of the side of it, which the height-only test never saw.
				local wrapped = (child :: any).TextWrapped
				if bounds.Y > rect.Height + 1
					or (not wrapped and bounds.X > rect.Width + 1) then
					table.insert(problems, string.format(
						"%s.%s copy needs %.0fx%.0f in %.0fx%.0f (wrapped=%s): %q",
						label, child.Name, bounds.X, bounds.Y, rect.Width, rect.Height,
						tostring(wrapped), string.sub((child :: any).Text, 1, 40)))
				end
			end
			table.insert(children, {Name = child.Name, Rect = rect})
		end
	end
	for index = 1, #children do
		for other = index + 1, #children do
			if Fit.overlaps(children[index].Rect, children[other].Rect) then
				table.insert(problems, string.format("%s.%s overlaps %s.%s",
					label, children[index].Name, label, children[other].Name))
			end
		end
	end
	return problems
end

function Fit.anchorProblems(rect, layout, label): {string}
	local problems = {}
	if not rect then return {label .. " was not measured"} end
	local safe = layout.Safe
	local margin = layout.IsTouch and 8 or 18
	if rect.Width <= 0 or rect.Height <= 0 then
		table.insert(problems, string.format("%s has size %.0fx%.0f",
			label, rect.Width, rect.Height))
		return problems
	end
	-- TOP: pinned to the top of the true safe area, not a third of the way down
	-- it and not the bottom of a band.
	if rect.Top > safe.Top + margin + Fit.AnchorSlack then
		table.insert(problems, string.format("%s starts at y %.0f, below the safe top %.0f",
			label, rect.Top, safe.Top + margin))
	end
	-- RIGHT: the safe right edge, and that is the whole rule. See
	-- C_ONE_RIGHT_EDGE_20260831 above the AnchorSlack constant for why the
	-- control-column alternative had to go.
	local screenEdge = safe.Right - margin
	if math.abs(rect.Right - screenEdge) > Fit.AnchorSlack then
		table.insert(problems, string.format(
			"%s right edge %.0f is not the safe right edge %.0f (safe.Right %.0f - margin %.0f),"
			.. " off by %.0f",
			label, rect.Right, screenEdge, safe.Right, margin,
			math.abs(rect.Right - screenEdge)))
	end
	-- ...and having taken the corner, it has to EARN it by finishing above the
	-- control cluster. This used to be excused whenever the panel could also be
	-- read as sitting on the column edge, which is to say it was excused exactly
	-- when it mattered. There is no excuse now: a readout right-aligned to the
	-- screen edge that reaches down past the cluster's top is right-aligned to an
	-- edge a control owns at that height, whatever the movement-zone rectangles
	-- happen to say. The cluster's top is Zones.Controls.Top, which is measured
	-- from the registered buttons and follows them when the short-screen
	-- arrangement lays them along the bottom.
	if layout.IsTouch and rect.Bottom > layout.Zones.Controls.Top + Fit.AnchorSlack then
		table.insert(problems, string.format(
			"%s reaches y %.0f, past the control cluster top %.0f",
			label, rect.Bottom, layout.Zones.Controls.Top))
	end
	-- Inside the safe area on every side.
	if rect.Left < safe.Left - Fit.AnchorSlack
		or rect.Right > safe.Right + Fit.AnchorSlack
		or rect.Bottom > safe.Bottom + Fit.AnchorSlack
		or rect.Top < safe.Top - Fit.AnchorSlack then
		table.insert(problems, string.format("%s leaves the safe area (%.0f,%.0f)-(%.0f,%.0f)",
			label, safe.Left, safe.Top, safe.Right, safe.Bottom))
	end
	-- NOT the corridor, and NOT bottom-centre: the two placements this replaced.
	--
	-- A "is its centre in the right half" heuristic was tried here first and was
	-- WRONG, in the direction that matters: on a 568x320 phone the control
	-- column owns 168px of a 568px screen, so a correctly right-aligned 236px
	-- panel ends at x 392 and is centred at 274 -- ten pixels into the left
	-- half. It failed three correct layouts.
	--
	-- The two rules above already exclude both old placements outright, and they
	-- do it by construction rather than by proportion:
	--   * the corridor placement was bottom-anchored (Position y = height - 40),
	--     which the TOP rule rejects -- it measured y 202 against a safe top
	--     of 44;
	--   * the Level 3 top-LEFT placement had its right edge at band.Left + width
	--     = 260, which the RIGHT-EDGE rule rejects against both the safe edge
	--     and the control column.
	-- What is added here is the one thing neither covers: the panel has to be in
	-- the right-hand PORTION of the screen at all, which a centred corridor
	-- panel on a wide phone would not be.
	if layout.IsTouch and rect.Right < layout.Width * .55 then
		table.insert(problems, string.format(
			"%s ends at x %.0f, left of the screen's right portion (%.0f)",
			label, rect.Right, layout.Width * .55))
	end
	local zone = UIDevice.OverlapsMovementZone(rect.Left, rect.Top, rect.Right, rect.Bottom)
	if zone then
		table.insert(problems, label .. " enters the " .. zone .. " movement zone")
	end
	return problems
end

-- C_L1_COMPOSITION_IS_MEASURED_20260831 -- WHAT SHIPPED BROKEN in the tests.
--
-- PuzzleUI states Level 1's touch composition as a set of panel-local
-- rectangles (C_L1_TOGGLE_AND_MESSAGE_OWN_THEIR_RECTANGLES_20260831): a 44x44
-- toggle square in the panel's top-right content corner, the title and each
-- visible objective row stacked down from the top pad RowGap apart and narrowed
-- by T + G while they share the toggle's band, and the transient message as the
-- LAST row of that same stack. Nothing in this suite checked any of it, for two
-- separate reasons, and both of them made a green tick out of nothing.
--
-- First, the toggle is not a child of the panel. PuzzleUI parents
-- Level1ObjectivesToggle to the ScreenGui and positions it in absolute space, so
-- Fit.childProblems -- which walks a panel's CHILDREN -- never saw the one
-- element that had been drawn straight over the title and the first objective
-- row (measured on the compact 300x80 landscape stack: toggle y 2..46 across
-- title y 4..22 and row y 24..40). The element most likely to cover the copy was
-- the element outside every overlap sweep the harness owned.
--
-- Second, the set childProblems walked was usually EMPTY. The three objective
-- rows are hidden until a round makes counters live, and the message is down for
-- essentially the whole round; a sweep over no children records a pass. So the
-- rows are STAGED here -- made visible with real copy -- and the stack is then
-- re-walked by the production layout pass rather than by the harness, because
-- setting Visible on a row does not lay it out: PuzzleUI walks the stack from
-- applyPuzzleLayout, and UIDevice.Changed is the one signal it relayouts on.
Fit.Level1Rows = {"FuseBoxStatus", "FuseCarryStatus", "LeverStatus"}

-- Long enough to wrap in the ~156px column the smallest landscape fixture gives,
-- because a one-line message is the case that cannot fail.
Fit.Level1Message = "FUSE EXTRACTED -- CARRY IT TO THE NEXT BOX"

-- The two authored padding tiers, natural then compact. The toggle's inset from
-- the panel's top-right corner is padX/padTop of whichever tier the stack walk
-- chose, and the harness cannot read that choice out of the datamodel -- so it
-- names both tiers and requires the toggle to sit at one of them. That is the
-- authored figure either way, not a range picked to be safe.
Fit.Level1TogglePads = {{PadX = 13, PadTop = 6}, {PadX = 10, PadTop = 4}}

-- Put the composition on screen, then let PRODUCTION lay it out.
--
-- The viewport attribute is nudged one pixel and put back rather than written
-- once, because UIDevice only fires Changed when the layout it computes differs
-- from the one it published -- so re-stating the size a fixture already has is
-- silent, and the rows would keep the geometry they had while they were hidden.
-- Two real passes at two real sizes, the second at the fixture's own.
function Fit.stageLevel1(device): (any, string?)
	Fit.beat()
	local screen = findGui("PuzzleGui")
	if not screen then return nil, "PuzzleGui missing" end
	local panel = screen:FindFirstChild("Level1Objectives")
	local pieces = {
		Screen = screen,
		Panel = panel,
		Toggle = screen:FindFirstChild("Level1ObjectivesToggle"),
		Title = panel and panel:FindFirstChild("ObjectiveTitle", true) or nil,
		Message = screen:FindFirstChild("PuzzleMessage", true),
		Rows = {},
		MessageText = nil,
	}
	if panel then
		for _, name in ipairs(Fit.Level1Rows) do
			local row = panel:FindFirstChild(name, true)
			if row then
				table.insert(pieces.Rows, {Name = name, Object = row})
				;(row :: any).Visible = true
			end
		end
		;(panel :: any).Visible = true
	end
	if pieces.Toggle then (pieces.Toggle :: any).Visible = true end
	if pieces.Message then
		pieces.MessageText = (pieces.Message :: any).Text
		;(pieces.Message :: any).Text = Fit.Level1Message
		;(pieces.Message :: any).Visible = true
	end

	workspace:SetAttribute("UIRegressionViewport", device.Size + Vector2.new(0, 1))
	task.wait(0.12)
	workspace:SetAttribute("UIRegressionViewport", device.Size)
	local deadline = 20
	local settled = false
	while deadline > 0 do
		local layout = UIDevice.Layout()
		if layout.Width == device.Size.X and layout.Height == device.Size.Y then
			settled = true
			break
		end
		task.wait(0.05)
		deadline -= 1
	end
	task.wait(0.15)
	if not settled then
		return pieces, "the relayout nudge never settled back on the fixture size"
	end
	return pieces, nil
end

-- The message's copy is the one thing Fit.borrow does not snapshot (it records
-- Visible, Active and CanvasPosition, never Text), so the staging puts it back
-- itself rather than leaving a test string in the player's HUD.
function Fit.unstageLevel1(pieces)
	if pieces and pieces.Message and pieces.MessageText ~= nil then
		(pieces.Message :: any).Text = pieces.MessageText
	end
end

-- Every rectangle of the staged composition, against every other one, in
-- RESOLVED space -- never AbsolutePosition, which is the host's answer and not
-- the fixture's. `resolve` is the device row's own resolver, so this shares the
-- ResolveRect machinery the rest of the matrices measure with.
function Fit.level1CompositionProblems(pieces, resolve, touch): {string}
	local problems = {}
	if not pieces then return {"the Level 1 composition was never staged"} end
	local function take(object, label)
		if not object then
			table.insert(problems, label .. " is not on screen at all")
			return nil
		end
		if (object :: any).Visible ~= true then
			table.insert(problems, label .. " is not visible, so nothing about it was measured")
			return nil
		end
		local rect, why = resolve(object, label)
		if not rect then
			table.insert(problems, why or (label .. " is unresolvable"))
			return nil
		end
		if rect.Width <= 0 or rect.Height <= 0 then
			table.insert(problems, string.format("%s has size %.0fx%.0f",
				label, rect.Width, rect.Height))
			return nil
		end
		return rect
	end

	local panel = take(pieces.Panel, "Level1Objectives")
	local toggle = take(pieces.Toggle, "Level1ObjectivesToggle")
	local title = take(pieces.Title, "ObjectiveTitle")
	local message = take(pieces.Message, "PuzzleMessage")
	local rows = {}
	for _, entry in ipairs(pieces.Rows) do
		local rect = take(entry.Object, entry.Name)
		if rect then table.insert(rows, {Name = entry.Name, Rect = rect}) end
	end
	-- An empty row set is the vacuum this whole helper exists to close, so a row
	-- that could not be staged is a FAILURE here rather than one fewer comparison.
	if #rows < #Fit.Level1Rows then
		table.insert(problems, string.format(
			"only %d of the %d objective rows could be staged and measured",
			#rows, #Fit.Level1Rows))
	end

	local function disjoint(a, aLabel, b, bLabel)
		if a and b and Fit.overlaps(a, b) then
			table.insert(problems, string.format("%s %s overlaps %s %s",
				aLabel, Fit.text(a), bLabel, Fit.text(b)))
		end
	end
	disjoint(toggle, "Level1ObjectivesToggle", title, "ObjectiveTitle")
	disjoint(toggle, "Level1ObjectivesToggle", message, "PuzzleMessage")
	disjoint(message, "PuzzleMessage", title, "ObjectiveTitle")
	for _, row in ipairs(rows) do
		disjoint(toggle, "Level1ObjectivesToggle", row.Rect, row.Name)
		disjoint(message, "PuzzleMessage", row.Rect, row.Name)
	end

	local function inside(rect, label)
		if rect and panel and not Fit.within(rect, panel, 1) then
			table.insert(problems, string.format("%s at %s escapes the panel %s",
				label, Fit.text(rect), Fit.text(panel)))
		end
	end
	local function outside(rect, label)
		if rect and panel and Fit.overlaps(rect, panel) then
			table.insert(problems, string.format("%s at %s sits on the panel %s",
				label, Fit.text(rect), Fit.text(panel)))
		end
	end
	inside(title, "ObjectiveTitle")
	for _, row in ipairs(rows) do inside(row.Rect, row.Name) end

	if touch then
		-- The touch composition folds BOTH of them into the panel.
		inside(toggle, "Level1ObjectivesToggle")
		inside(message, "PuzzleMessage")
		-- ...and the message is the stack's LAST row, so it is below every
		-- objective row rather than merely clear of them.
		for _, row in ipairs(rows) do
			if message and message.Top < row.Rect.Bottom - 1 then
				table.insert(problems, string.format(
					"PuzzleMessage starts at y %.0f, above %s's bottom %.0f -- not the last row",
					message.Top, row.Name, row.Rect.Bottom))
			end
		end
		-- The toggle's stated square, at one of the two authored padding tiers.
		if toggle and panel then
			if math.abs(toggle.Width - 44) > 1 or math.abs(toggle.Height - 44) > 1 then
				table.insert(problems, string.format(
					"Level1ObjectivesToggle is %.0fx%.0f, not the authored 44x44 square",
					toggle.Width, toggle.Height))
			end
			local matched = false
			for _, tier in ipairs(Fit.Level1TogglePads) do
				if math.abs((panel.Right - toggle.Right) - tier.PadX) <= 1
					and math.abs((toggle.Top - panel.Top) - tier.PadTop) <= 1 then
					matched = true
				end
			end
			if not matched then
				table.insert(problems, string.format(
					"Level1ObjectivesToggle is inset %.0f,%.0f from the panel's top-right"
					.. " corner, which is neither authored tier (13,6 natural or 10,4 compact)",
					panel.Right - toggle.Right, toggle.Top - panel.Top))
			end
		end
	else
		-- DESKTOP is the other authored composition and is asserted as such: the
		-- toggle is the corner element BELOW the panel and the message is the strip
		-- above it, so both are outside the panel rather than in it. Stating it here
		-- is what stops a later touch change dragging the desktop stack along with
		-- it while nothing in the suite notices.
		outside(toggle, "Level1ObjectivesToggle")
		outside(message, "PuzzleMessage")
	end
	return problems
end

-- C_L2_ALERT_IS_DRIVEN_20260831 -- WHAT SHIPPED BROKEN in the tests.
--
-- The device matrix used to "raise" the Level 2 completion announcement by
-- reaching into its ScreenGui and writing Visible = true on the shade frame it
-- found. That paints a box and drives nothing else: the three labels keep the
-- empty strings they were built with, the production measurement answers zero
-- for empty copy, the panel is laid out about fourteen pixels tall, and every
-- child then fits inside it trivially. The row went green because it measured an
-- empty box -- and the one defect the announcement has ever had, the FINAL line
-- rendering outside the rectangle it was given, is invisible to a test that
-- never sets a final line.
--
-- Level2AlertClient now publishes UIRegressionLevel2AlertProbe, which drives the
-- production upvalues -- the real handler where the gate allows it, the real
-- presentation where it does not, real TextService measurement, real
-- applySafePanelLayout -- and hands back the rectangles that produced. The three
-- lines below are the ones the game actually announces, and the last of them is
-- the longest string this panel ever has to hold.
Fit.AlertLines = {
	Line1 = "PRESSURE EQUALIZED",
	Line2 = "GRAND HALL UNSEALED",
	Final = "CLIMB TO THE TOP DECK AND TAKE THE FLUME OUT",
}

-- The probe answers one string:
--   panel=L,T,R,B line1=L,T,R,B line2=L,T,R,B run=L,T,R,B
--   runVisible=b owns=b shown=b gate=b
-- Every rectangle in it is AbsolutePosition space, which is the space
-- UIDevice.Layout() reports its own rectangles in, so these edges and a
-- fixture's safe area are directly comparable numbers rather than two
-- coordinate systems that happen to agree on this host.
--
-- An unparseable field is left out rather than defaulted, so a probe that stops
-- answering produces a missing rectangle -- which every caller below treats as a
-- failure -- instead of a zero rectangle that fits inside everything.
function Fit.parseAlertAnswer(answer): any
	if type(answer) ~= "string" then return nil end
	local parsed = {Raw = answer, Rects = {}, Flags = {}}
	for key, value in string.gmatch(answer, "(%w+)=([^%s]+)") do
		local left, top, right, bottom = string.match(value,
			"^(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)$")
		if left then
			local l, t, r, b = tonumber(left), tonumber(top), tonumber(right), tonumber(bottom)
			parsed.Rects[key] = {Left = l, Top = t, Right = r, Bottom = b,
				Width = r - l, Height = b - t}
		elseif value == "true" or value == "false" then
			parsed.Flags[key] = value == "true"
		end
	end
	return parsed
end

-- The announcement, judged against the fixture it was drawn on: every line
-- inside the panel, no two lines on top of each other, the panel inside the safe
-- area and clear of every movement zone.
function Fit.alertProblems(shown, layout): {string}
	local problems = {}
	if not shown then return {"the alert probe answered nothing"} end
	local panel = shown.Rects.panel
	if not panel then
		table.insert(problems, "the answer carried no panel rectangle: " .. tostring(shown.Raw))
	end
	local named = {
		{Name = "AlertLine1", Rect = shown.Rects.line1},
		{Name = "AlertLine2", Rect = shown.Rects.line2},
		{Name = "AlertRunLine", Rect = shown.Rects.run},
	}
	for _, entry in ipairs(named) do
		if not entry.Rect then
			table.insert(problems, entry.Name .. " has no rectangle in the answer")
		else
			if entry.Rect.Width <= 0 or entry.Rect.Height <= 0 then
				table.insert(problems, string.format("%s has size %.0fx%.0f",
					entry.Name, entry.Rect.Width, entry.Rect.Height))
			end
			if panel and not Fit.within(entry.Rect, panel, 1) then
				table.insert(problems, string.format("%s at %s escapes the panel %s",
					entry.Name, Fit.text(entry.Rect), Fit.text(panel)))
			end
		end
	end
	for index = 1, #named do
		for other = index + 1, #named do
			if Fit.overlaps(named[index].Rect, named[other].Rect) then
				table.insert(problems, string.format("%s %s overlaps %s %s",
					named[index].Name, Fit.text(named[index].Rect),
					named[other].Name, Fit.text(named[other].Rect)))
			end
		end
	end
	-- The final line is the whole point of driving real copy through this panel,
	-- so its absence is a failure and not one fewer rectangle to compare.
	if shown.Flags.runVisible ~= true then
		table.insert(problems, "the final line was never put on screen")
	end
	if panel then
		if not Fit.within(panel, layout.Safe, Fit.AnchorSlack) then
			table.insert(problems, string.format(
				"the panel %s leaves the safe area (%.0f,%.0f)-(%.0f,%.0f)",
				Fit.text(panel), layout.Safe.Left, layout.Safe.Top,
				layout.Safe.Right, layout.Safe.Bottom))
		end
		local zone = UIDevice.OverlapsMovementZone(panel.Left, panel.Top,
			panel.Right, panel.Bottom)
		if zone then
			table.insert(problems, "the panel enters the " .. zone .. " movement zone")
		end
	end
	return problems
end

function Fit.bodyObjectiveCornerMatrix(): (string, number)
	local player = Players.LocalPlayer
	local state = Fit.recorder("=== objective readouts, upper right, every level and device ===")
	local record = state.record
	-- (b) AWAIT ITS NATURAL END, BOUNDED. See Fit.awaitQuietDispatch: this lane
	-- cannot run without interrupting a live transmission, and it must not
	-- interrupt one. The wait is BEFORE Fit.borrow, so the snapshot is of a quiet
	-- world and the restore has nothing to be forgiven for.
	local quiet, dispatchWhy = Fit.awaitQuietDispatch()
	if not quiet then
		record(false, "no real dispatch briefing was live when the matrix started",
			dispatchWhy)
		return state.finish()
	end
	local saved = Fit.borrow()

	local ran, runError = pcall(function()
		-- ---- calibration, at the REAL viewport ----------------------------
		workspace:SetAttribute("UIRegressionViewport", nil)
		workspace:SetAttribute("ForceTouchUI", true)
		workspace:SetAttribute("UIRegressionSafeInsets", nil)
		resetScenario(true)
		revealGui("PuzzleGui")
		task.wait(0.35)
		local realLayout = UIDevice.Layout()
		local worst, worstName = 0, ""
		local puzzle = findGui("PuzzleGui")
		local panel = puzzle and puzzle:FindFirstChild("Level1Objectives")
		if panel then
			local shift = UIRegression.ScreenSpaceShift(panel)
			local resolved = UIRegression.ResolveRect(panel, realLayout.Viewport, realLayout.Inset.Y)
			local node = panel :: any
			if resolved and not resolved.Unresolvable then
				local live = {
					Left = node.AbsolutePosition.X,
					Top = node.AbsolutePosition.Y + shift,
					Right = node.AbsolutePosition.X + node.AbsoluteSize.X,
					Bottom = node.AbsolutePosition.Y + node.AbsoluteSize.Y + shift,
				}
				for _, edge in ipairs({"Left", "Top", "Right", "Bottom"}) do
					local delta = math.abs(resolved[edge] - live[edge])
					if delta > worst then worst, worstName = delta, edge end
				end
			else
				worst, worstName = math.huge, "unresolvable"
			end
		else
			worst, worstName = math.huge, "Level1Objectives missing"
		end
		record(worst <= 1,
			"the resolver reproduces the engine for an inset-IGNORING objective gui"
			.. " at the real viewport",
			string.format("worst edge error %.2fpx at %s", worst, worstName))

		for _, device in ipairs(Fit.Devices) do
			local applied = Fit.apply(device)
			record(applied, device.Name .. ": the device override took before the row ran",
				applied and "" or "timed out waiting for UIDevice to report it")
			local layout = UIDevice.Layout()
			local viewport, insetY = device.Size, layout.Inset.Y
			state.note(string.format("--- %s (class=%s touch=%s) safe (%.0f,%.0f)-(%.0f,%.0f) ---",
				device.Name, layout.Class, tostring(layout.IsTouch),
				layout.Safe.Left, layout.Safe.Top, layout.Safe.Right, layout.Safe.Bottom))

			local function resolved(gui, name)
				local screen = findGui(gui)
				local object = screen and screen:FindFirstChild(name, true)
				if not object then return nil, name .. " missing" end
				local rect = UIRegression.ResolveRect(object, viewport, insetY)
				if not rect or rect.Unresolvable then
					return nil, name .. ": " .. tostring(rect and rect.Unresolvable or "nil")
				end
				return rect, nil
			end

			-- ---- LEVEL 1 -------------------------------------------------
			resetScenario(true)
			revealGui("PuzzleGui")
			task.wait(0.25)
			local level1, level1Error = resolved("PuzzleGui", "Level1Objectives")
			state.note("      Level1Objectives " .. Fit.text(level1))
			if not layout.IsTouch then
				-- DESKTOP REGRESSION, stated explicitly. The touch repair moved
				-- three HUDs; the desktop compositions they came from are part of
				-- the contract and are asserted here so a later touch change
				-- cannot quietly take them with it.
				record(level1 ~= nil
					and level1.Bottom > (layout.Safe.Top + layout.Safe.Bottom) * .5
					and level1.Right > (layout.Safe.Left + layout.Safe.Right) * .5,
					device.Name .. " / L1 desktop: keeps its authored LOWER-RIGHT column",
					Fit.text(level1) or level1Error)
			else
				local problems = Fit.anchorProblems(level1, layout, "Level1Objectives")
				record(#problems == 0,
					device.Name .. " / L1: the objectives column is in the upper-right safe corner",
					table.concat(problems, "; ") .. (level1Error and (" " .. level1Error) or ""))
				-- ...and its CONTENTS fit it. At 568x320 every one of the four
				-- Level 1 lines needed two lines in a 156px column while the panel
				-- gave each a 23px row, so all four rendered outside the panel that
				-- was, itself, perfectly placed.
				local puzzleScreen = findGui("PuzzleGui")
				local livePanel = puzzleScreen and puzzleScreen:FindFirstChild("Level1Objectives")
				local childProblems = Fit.childProblems(livePanel, "Level1Objectives")
				record(#childProblems == 0,
					device.Name .. " / L1: and every row fits inside it",
					table.concat(childProblems, "; "))
				local detectorObject = puzzleScreen
					and puzzleScreen:FindFirstChild("ExitEnergyDetector")
				local detectorProblems = Fit.childProblems(detectorObject, "ExitEnergyDetector")
				record(#detectorProblems == 0,
					device.Name .. " / L1: and the detector's own readout fits it",
					table.concat(detectorProblems, "; "))
				local toggle = resolved("PuzzleGui", "Level1ObjectivesToggle")
				record(toggle ~= nil and toggle.Height >= 44,
					device.Name .. " / L1: its toggle keeps a 44px target",
					Fit.text(toggle))
				local detector = resolved("PuzzleGui", "ExitEnergyDetector")
				record(detector == nil or level1 == nil or not Fit.overlaps(detector, level1),
					device.Name .. " / L1: and the exit detector does not overlap it",
					Fit.text(detector))
			end

			-- ---- LEVEL 1, THE WHOLE COMPOSITION --------------------------
			-- C_L1_COMPOSITION_IS_MEASURED_20260831. Runs on EVERY fixture, touch
			-- and pointer alike: the two form factors draw two different authored
			-- compositions and each has rectangles it has to keep. The staging makes
			-- the three objective rows and the message real -- with copy -- and lets
			-- the production layout pass place them, so what is compared below is a
			-- stack PuzzleUI laid out and not one the harness wrote.
			local pieces, stageWhy = Fit.stageLevel1(device)
			record(pieces ~= nil and stageWhy == nil,
				device.Name .. " / L1: the whole composition could be staged and relaid out",
				stageWhy or "staged")
			-- Resolved space, the same ResolveRect every other matrix measures with.
			-- AbsolutePosition would be the HOST's answer for these elements, and a
			-- fixture's rectangles are not the host's.
			local function resolveObject(object, label)
				local rect = UIRegression.ResolveRect(object, viewport, insetY)
				if not rect or rect.Unresolvable then
					return nil, label .. ": " .. tostring(rect and rect.Unresolvable or "nil")
				end
				return rect, nil
			end
			local composition = Fit.level1CompositionProblems(pieces, resolveObject,
				layout.IsTouch)
			record(#composition == 0,
				device.Name .. " / L1: the toggle, the title, all three objective rows and"
				.. " the message each own a separate rectangle, and the panel holds the"
				.. " ones this form factor draws inside it",
				table.concat(composition, "; "))
			-- ...and the child sweep AGAIN, now that there is something in the panel
			-- for it to walk. The identical call above this block runs against a round
			-- that never made the counters live, so its row set is empty and its copy
			-- proof is a pass over nothing. This one measures four rows of real copy at
			-- the width the fixture gives them, which is where 568x320 broke.
			local stagedChildren = Fit.childProblems(pieces and pieces.Panel,
				"Level1Objectives")
			record(#stagedChildren == 0,
				device.Name .. " / L1: and with every row carrying real copy, each one's"
				.. " string still fits the box the stack gave it",
				table.concat(stagedChildren, "; "))
			Fit.unstageLevel1(pieces)

			-- ---- LEVEL 2, alone and with the completion alert -------------
			resetScenario(true)
			revealGui("Level2ObjectiveGui")
			task.wait(0.25)
			local level2, level2Error = resolved("Level2ObjectiveGui", "Level2ObjectivePanel")
			state.note("      Level2ObjectivePanel " .. Fit.text(level2))
			if not layout.IsTouch then
				record(level2 ~= nil
					and level2.Bottom > (layout.Safe.Top + layout.Safe.Bottom) * .5
					and level2.Right > (layout.Safe.Left + layout.Safe.Right) * .5,
					device.Name .. " / L2 desktop: keeps its authored BOTTOM-RIGHT panel",
					Fit.text(level2) or level2Error)
			end
			if layout.IsTouch then
				local problems = Fit.anchorProblems(level2, layout, "Level2ObjectivePanel")
				record(#problems == 0,
					device.Name .. " / L2: the pump readout is in the upper-right safe corner",
					table.concat(problems, "; ") .. (level2Error and (" " .. level2Error) or ""))
				local l2Screen = findGui("Level2ObjectiveGui")
				local l2Panel = l2Screen and l2Screen:FindFirstChild("Level2ObjectivePanel")
				local l2Children = Fit.childProblems(l2Panel, "Level2ObjectivePanel")
				record(#l2Children == 0,
					device.Name .. " / L2: and its three lines fit inside it",
					table.concat(l2Children, "; "))
			end
			-- C_L2_ALERT_IS_DRIVEN_20260831. The gui is enabled with every child DOWN
			-- -- the filter returns false for all of them -- so the probe's own capture
			-- records "no announcement was up" and its restore can put that back. Left
			-- revealed, the shade would be visible before the show and the restore would
			-- hand back a raised announcement nobody asked for.
			revealGui("Level2AlertGui", function() return false end)
			task.wait(0.3)
			local alertScreen = findGui("Level2AlertGui")
			local shade = alertScreen and alertScreen:FindFirstChildOfClass("Frame")
			local alertProbe = alertScreen
				and alertScreen:FindFirstChild("UIRegressionLevel2AlertProbe")
			local haveAlertProbe = alertProbe ~= nil and alertProbe:IsA("BindableFunction")
			record(haveAlertProbe,
				device.Name .. " / L2: the announcement has a production seam to drive,"
				.. " so the matrix never has to fake one",
				haveAlertProbe and "UIRegressionLevel2AlertProbe"
					or "UIRegressionLevel2AlertProbe missing")
			-- THE WIRING, from both ends, the way the Level 3 reader's is. `remote` is
			-- the recorded RBXScriptConnection's own Connected state and `handler` is
			-- whether the function the remote is connected to is still onAlertEvent --
			-- so deleting the connect statement fails this even though every probe
			-- action below would keep working.
			local alertWiring = haveAlertProbe and alertProbe:Invoke("wiring") or ""
			record(alertWiring == "remote=true/true",
				device.Name .. " / L2: the announcement remote is still connected, and"
				.. " still to the production handler",
				tostring(alertWiring))
			-- REAL COPY, through the production presentation. Five seconds of hold so
			-- the fade cannot start while the panel is being measured; the probe returns
			-- immediately either way, because the presentation no longer yields.
			local alertShown = nil
			if haveAlertProbe then
				alertShown = Fit.parseAlertAnswer(alertProbe:Invoke("show",
					Fit.AlertLines.Line1, Fit.AlertLines.Line2, Fit.AlertLines.Final, 5))
			end
			task.wait(0.25)
			local alertPanel = alertShown and alertShown.Rects.panel or nil
			state.note("      Level2Alert " .. Fit.text(alertPanel)
				.. " gate=" .. tostring(alertShown and alertShown.Flags.gate))
			local alertProblems = Fit.alertProblems(alertShown, layout)
			record(#alertProblems == 0,
				device.Name .. " / L2: with all three authored lines on screen, every line"
				.. " is inside the panel, no two lines meet, and the panel is inside the"
				.. " safe area and clear of every movement zone",
				table.concat(alertProblems, "; "))
			local ownsBand = player:GetAttribute("Level2AlertOwnsBand") == true
			local objectiveShown = level2 ~= nil
			local screenPanel = findGui("Level2ObjectiveGui")
			local livePanel = screenPanel and screenPanel:FindFirstChild("Level2ObjectivePanel")
			objectiveShown = livePanel ~= nil and (livePanel :: any).Visible == true
			-- Either they are reflowed apart, or the alert has declared it owns
			-- the band and the objective has genuinely stood down. Never both on
			-- screen and overlapping, and never both hidden.
			-- EXACTLY ONE OWNER, and it has to be on screen. "Both hidden" used to
			-- satisfy this: `ownsBand and not objectiveShown` is true when the
			-- objective is hidden for any reason at all, including the alert gui
			-- being disabled and nothing being drawn. The alert's own visibility
			-- is now part of the assertion.
			local alertVisible = shade ~= nil and (shade :: any).Visible == true
				and alertScreen ~= nil and (alertScreen :: ScreenGui).Enabled == true
			record(alertVisible and ((ownsBand and not objectiveShown)
					or (not ownsBand and objectiveShown
						and not Fit.overlaps(alertPanel, level2))),
				device.Name .. " / L2: the completion alert and the objective column"
				.. " reflow apart, or mutually exclude -- and the owner is VISIBLE",
				string.format("alertVisible=%s ownsBand=%s objectiveShown=%s alert=%s objective=%s",
					tostring(alertVisible), tostring(ownsBand), tostring(objectiveShown),
					Fit.text(alertPanel), Fit.text(level2)))
			-- The alert's own copy has to fit the panel it was given. This walk is the
			-- one that reads the LIVE labels rather than the probe's answer, so it also
			-- catches a string that overflows a box whose rectangle is perfectly placed.
			local alertInner = shade and shade:FindFirstChildOfClass("Frame")
			local alertChildren = Fit.childProblems(alertInner, "Level2Alert")
			record(#alertChildren == 0,
				device.Name .. " / L2: and every line of the announcement fits its panel",
				table.concat(alertChildren, "; "))
			-- THE FINAL LINE, on BOTH axes, named on its own because it is the string
			-- C_L2_ALERT_COPY_FITS_20260830 was opened for and the longest one this
			-- panel ever holds. The height test is the one that defect failed; the width
			-- test is not redundant even though the label wraps -- TextBounds.X wider
			-- than the box means the wrapper had to break inside a word, which is copy
			-- running out of the side of its box rather than off the bottom of it.
			local runLabel = alertInner and alertInner:FindFirstChild("AlertRunLine")
			local runRect = alertShown and alertShown.Rects.run or nil
			local runBounds = runLabel and (runLabel :: any).TextBounds or nil
			record(runLabel ~= nil and runRect ~= nil and runBounds ~= nil
				and (runLabel :: any).Text == Fit.AlertLines.Final
				and runBounds.Y <= runRect.Height + 1
				and runBounds.X <= runRect.Width + 1,
				device.Name .. " / L2: and its FINAL line is not clipped on either axis",
				string.format("%q needs %sx%s in %s",
					runLabel and tostring((runLabel :: any).Text) or "no label",
					runBounds and string.format("%.0f", runBounds.X) or "?",
					runBounds and string.format("%.0f", runBounds.Y) or "?",
					Fit.text(runRect)))
			-- Ownership must TRANSFER BACK, and it is handed back through the probe's
			-- own restore rather than by writing the shade down: restore puts the copy,
			-- the four transparencies, the panel and the shade back to what capture()
			-- recorded and re-arms whatever hold was left of an announcement that was
			-- already up. Writing Visible = false leaves the test copy in the labels for
			-- the rest of the session.
			local restoredAnswer = haveAlertProbe and alertProbe:Invoke("restore") or nil
			task.wait(0.3)
			local afterRestore = Fit.parseAlertAnswer(restoredAnswer)
			record(afterRestore ~= nil and afterRestore.Flags.shown == false,
				device.Name .. " / L2: and the probe's restore takes the announcement down",
				tostring(restoredAnswer))
			local restoredScreen = findGui("Level2ObjectiveGui")
			local restoredPanel = restoredScreen
				and restoredScreen:FindFirstChild("Level2ObjectivePanel")
			-- The OWNERSHIP FLAG is what transfers; the panel's own visibility is
			-- additionally gated on being in Level 2 with a round running, which
			-- this matrix deliberately is not. Asserting the flag AND that the
			-- objective gui is no longer suppressed is the transfer; asserting the
			-- panel's Visible would be asserting the level gate.
			local restoredEnabled = restoredScreen ~= nil
				and (restoredScreen :: ScreenGui).Enabled == true
			record(player:GetAttribute("Level2AlertOwnsBand") ~= true and restoredEnabled,
				device.Name .. " / L2: and lowering the alert hands the band back",
				string.format("ownsBand=%s objectiveGuiEnabled=%s",
					tostring(player:GetAttribute("Level2AlertOwnsBand")),
					tostring(restoredEnabled)))

			-- ---- LEVEL 3, open then hidden then restored -----------------
			resetScenario(true)
			player:SetAttribute("UIRegressionForceLevel3Reader", true)
			player:SetAttribute("UIRegressionForceReaderHidden", false)
			revealGui("Level3ReaderGui", function(child)
				return child.Name == "ReaderPanel" or child.Name == "ReaderRestore"
			end)
			task.wait(0.3)
			local reader, readerError = resolved("Level3ReaderGui", "ReaderPanel")
			state.note("      ReaderPanel " .. Fit.text(reader))
			if not layout.IsTouch then
				-- DESKTOP IS LOWER-RIGHT, matching Level 1 and Level 2. It used to be
				-- hardcoded top-right, which was the one desktop composition in the
				-- game that disagreed with the other two.
				record(reader ~= nil
					and reader.Bottom > (layout.Safe.Top + layout.Safe.Bottom) * .5
					and reader.Right > (layout.Safe.Left + layout.Safe.Right) * .5,
					device.Name .. " / L3 desktop: keeps the authored LOWER-RIGHT reader",
					Fit.text(reader) or readerError)
			end
			if layout.IsTouch then
				local problems = Fit.anchorProblems(reader, layout, "ReaderPanel")
				record(#problems == 0,
					device.Name .. " / L3 open: the reader is in the upper-right safe corner",
					table.concat(problems, "; ") .. (readerError and (" " .. readerError) or ""))
				local l3Screen = findGui("Level3ReaderGui")
				local l3Panel = l3Screen and l3Screen:FindFirstChild("ReaderPanel")
				local l3Children = Fit.childProblems(l3Panel, "ReaderPanel")
				record(#l3Children == 0,
					device.Name .. " / L3 open: and its readout fits inside it",
					table.concat(l3Children, "; "))
			end
			-- REPLACES the old level3-reader-open / -closed pair, which REQUIRED
			-- ReaderToggle in both states. There is no separate control any more.
			local readerScreen = findGui("Level3ReaderGui")
			record(readerScreen ~= nil and readerScreen:FindFirstChild("ReaderToggle", true) == nil,
				device.Name .. " / L3 open: there is no separate CLOSE control at all",
				readerScreen and readerScreen:FindFirstChild("ReaderToggle", true)
					and "ReaderToggle still exists" or nil)
			local livePanelObject = readerScreen and readerScreen:FindFirstChild("ReaderPanel")
			local restoreObject = readerScreen and readerScreen:FindFirstChild("ReaderRestore")
			record(livePanelObject ~= nil and (livePanelObject :: any).Visible == true
				and (not layout.IsTouch or (livePanelObject :: any).Active == true),
				device.Name .. " / L3 open: the panel itself is the control that hides it"
				.. " on touch, and inert on desktop",
				string.format("visible=%s active=%s touch=%s",
					tostring(livePanelObject and (livePanelObject :: any).Visible),
					tostring(livePanelObject and (livePanelObject :: any).Active),
					tostring(layout.IsTouch)))
			record(restoreObject ~= nil and (restoreObject :: any).Visible == false,
				device.Name .. " / L3 open: and the restore chip is not also on screen",
				tostring(restoreObject and (restoreObject :: any).Visible))

			-- C_L3_ROWS_SAY_WHAT_THEY_PROVE_20260831 -- WHAT SHIPPED BROKEN in the
			-- tests, in their WORDING, which is the kind that survives longest.
			--
			-- These rows used to be introduced as "REAL INTERACTION -- the panel is
			-- TAPPED" and to report "TAPPING THE PANEL hides it", and they called the
			-- probe "the production tap handler is reachable". Nothing is tapped. The
			-- probe calls onPanelTapped as a plain Lua function: no touch, no click,
			-- no InputObject exists at any point, and the button itself is never
			-- involved -- so the hit test, Active, Visible, ZIndex and anything drawn
			-- over the top are all left unexercised. A row that says "tapped" tells
			-- the next reader an input path was proven when it was not, and a false
			-- claim in a passing row is worse than a missing check, because nobody
			-- goes looking for it.
			--
			-- WHAT IS ACTUALLY PROVEN, in three parts, each asserted below:
			--   1. a live Activated connection whose recorded Button is the very
			--      button this file draws and which is still in the tree (the
			--      `routed` half of the wiring answer);
			--   2. handler IDENTITY -- the function the seam invokes IS the function
			--      that was connected, not a copy of it (the `sameFunction` half);
			--   3. a DIRECT HANDLER INVOCATION and the state it leaves behind.
			--
			-- WHAT IS NOT PROVEN, and cannot be from here: the engine delivering a
			-- touch to a visible, Active button. VirtualInputManager is capability-
			-- blocked in this Studio session ("lacking capability RobloxScript") and
			-- the MCP bridge's synthetic mouse does not reach the GUI input stack at
			-- all -- it never even raises MouseEnter on a GuiObject. That last link is
			-- Roblox's own behaviour and it is untested here BY NECESSITY. It is
			-- written down rather than papered over with a verb.
			local readerProbe = readerScreen
				and readerScreen:FindFirstChild("UIRegressionReaderProbe")
			player:SetAttribute("UIRegressionForceReaderHidden", nil)
			task.wait(0.2)
			local handlerState = nil
			if readerProbe and readerProbe:IsA("BindableFunction") then
				handlerState = readerProbe:Invoke("invokePanelHandler")
			end
			task.wait(0.25)
			record(readerProbe ~= nil,
				device.Name .. " / L3: the handler seam exists, so the production"
				.. " onPanelTapped can be invoked directly",
				readerProbe and "UIRegressionReaderProbe" or "no probe")
			-- THE WIRING CONTRACT, which is the half a handler invocation cannot
			-- supply. Invoking the handler stays green with every Activated:Connect
			-- line deleted -- the body still works while no finger could ever reach
			-- it -- so the gap is closed from both ends. The RUNTIME half reports the
			-- recorded RBXScriptConnection's Connected state, that the connection was
			-- made on the button this file draws and that the button is still
			-- parented, plus that the seam invokes the same function object that was
			-- connected. The SOURCE half reads the shipping LocalScript and requires
			-- both connect statements verbatim. Delete either connection and both
			-- fail. Neither says an input event was delivered.
			local wiring = readerProbe and readerProbe:Invoke("wiring") or ""
			record(wiring == "ReaderPanel=true/true ReaderRestore=true/true",
				device.Name .. " / L3: both Activated connections are live on the very"
				.. " buttons this file draws, and the seam invokes the very functions"
				.. " they are connected to",
				tostring(wiring))
			local readerSource = nil
			do
				local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
				local script3 = sps and sps:FindFirstChild("Level 3 Reader Client")
				readerSource = script3 and (script3 :: any).Source or nil
			end
			record(readerSource ~= nil
				and readerSource:find('wireTap("ReaderPanel", panel, onPanelTapped)', 1, true) ~= nil
				and readerSource:find('wireTap("ReaderRestore", restoreButton, onRestoreTapped)', 1, true) ~= nil,
				device.Name .. " / L3: and the shipping source still contains both"
				.. " connect statements",
				readerSource and "source read" or "source unavailable")
			if layout.IsTouch then
				record(handlerState == "hidden",
					device.Name .. " / L3: INVOKING onPanelTapped hides the reader",
					tostring(handlerState))
			else
				-- Desktop: the handler itself declines. It is the same function a click
				-- would reach, and invoking it leaves the reader open, so R keeps the
				-- job of putting it away. The Active check below is the separate half:
				-- the panel is not in the input stack at all, so no click reaches the
				-- handler in the first place.
				record(handlerState == "open",
					device.Name .. " / L3 desktop: INVOKING onPanelTapped does NOT hide the"
					.. " reader -- the handler declines on a pointer device",
					tostring(handlerState))
				record(livePanelObject ~= nil and (livePanelObject :: any).Active == false,
					device.Name .. " / L3 desktop: and it is not in the input stack",
					tostring(livePanelObject and (livePanelObject :: any).Active))
				-- Drive the hidden state the only way a desktop can, so the rest
				-- of the row still measures the chip.
				player:SetAttribute("UIRegressionForceReaderHidden", true)
			end
			task.wait(0.3)
			local restoreRect = resolved("Level3ReaderGui", "ReaderRestore")
			state.note("      ReaderRestore " .. Fit.text(restoreRect))
			record(livePanelObject ~= nil and (livePanelObject :: any).Visible == false,
				device.Name .. " / L3 hidden: the panel is gone",
				tostring(livePanelObject and (livePanelObject :: any).Visible))
			if layout.IsTouch then
				record(restoreObject ~= nil and (restoreObject :: any).Visible == true
					and restoreRect ~= nil and restoreRect.Width >= 44
					and restoreRect.Height >= 44,
					device.Name .. " / L3 hidden: only a compact restore target remains,"
					.. " at least 44x44",
					Fit.text(restoreRect))
			else
				-- DESKTOP DRAWS NOTHING. R is the only way back, and a restore chip
				-- there would be the "dedicated open button" the product forbids.
				record(restoreObject == nil or (restoreObject :: any).Visible == false,
					device.Name .. " / L3 hidden: desktop draws NO restore chip -- R is"
					.. " the only way back",
					tostring(restoreObject and (restoreObject :: any).Visible))
			end
			if layout.IsTouch and reader ~= nil and restoreRect ~= nil then
				record(math.abs(restoreRect.Right - reader.Right) <= 1
					and math.abs(restoreRect.Top - reader.Top) <= 1,
					device.Name .. " / L3 hidden: at the same upper-right anchor the panel used",
					string.format("chip %s vs panel %s", Fit.text(restoreRect), Fit.text(reader)))
			end
			-- SUBTLE: the mark the player sees is smaller than the target the
			-- finger gets, and it carries no key name.
			local chip = restoreObject and restoreObject:FindFirstChild("Chip")
			local chipRect = chip and Fit.live(chip)
			record(chipRect ~= nil and chipRect.Width <= 34 and chipRect.Height <= 34,
				device.Name .. " / L3 hidden: its visible mark is a small chip, not a button bar",
				Fit.text(chipRect))
			record(restoreObject ~= nil and Fit.keyGlyph(restoreObject) == nil
				and tostring((restoreObject :: any).Text) == "",
				device.Name .. " / L3 hidden: and names no keyboard key",
				restoreObject and Fit.keyGlyph(restoreObject) or nil)

			-- The chip must be ACTIVE, not merely drawn: an inert 44px mark is a
			-- picture of a control.
			if layout.IsTouch then
				record(restoreObject ~= nil and (restoreObject :: any).Active == true,
					device.Name .. " / L3 hidden: and the restore chip is in the input stack",
					tostring(restoreObject and (restoreObject :: any).Active))
			else
				record(restoreObject == nil or (restoreObject :: any).Active == false,
					device.Name .. " / L3 hidden: and desktop leaves nothing in the input"
					.. " stack either",
					tostring(restoreObject and (restoreObject :: any).Active))
			end

			-- The chip's handler, invoked the same way and proven the same way. The
			-- wiring row above already covered ReaderRestore's connection and its
			-- button identity; this is the third part, the invocation.
			local restoredState = nil
			if readerProbe and readerProbe:IsA("BindableFunction") then
				player:SetAttribute("UIRegressionForceReaderHidden", nil)
				task.wait(0.15)
				restoredState = readerProbe:Invoke("invokeRestoreHandler")
			end
			task.wait(0.3)
			record(restoredState == "open",
				device.Name .. " / L3 restored: INVOKING onRestoreTapped brings the reader"
				.. " back",
				tostring(restoredState))
			record(livePanelObject ~= nil and (livePanelObject :: any).Visible == true
				and restoreObject ~= nil and (restoreObject :: any).Visible == false,
				device.Name .. " / L3 restored: the full panel comes back and the chip goes",
				string.format("panel=%s chip=%s",
					tostring(livePanelObject and (livePanelObject :: any).Visible),
					tostring(restoreObject and (restoreObject :: any).Visible)))

			-- ---- against the dispatch briefing ---------------------------
			player:SetAttribute("UIRegressionForceDispatchActive", true)
			task.wait(0.35)
			-- The QUESTION is whether a rectangle is on screen, not which mechanism
			-- put it away. Level 2 disables its whole ScreenGui on dispatch; the
			-- Level 3 reader keeps its gui enabled and hides the panel from
			-- isActive(); PuzzleUI hides its children. Asserting `Enabled` tested
			-- one of the three implementations and failed the other two while the
			-- screen was, in fact, clear.
			local onScreen = {}
			for _, spec in ipairs({
				{"PuzzleGui", "Level1Objectives"},
				{"PuzzleGui", "ExitEnergyDetector"},
				{"Level2ObjectiveGui", "Level2ObjectivePanel"},
				{"Level3ReaderGui", "ReaderPanel"},
				{"Level3ReaderGui", "ReaderRestore"},
			}) do
				local screen = findGui(spec[1])
				local object = screen and screen:FindFirstChild(spec[2], true)
				if object and (screen :: ScreenGui).Enabled and (object :: any).Visible then
					table.insert(onScreen, spec[2])
				end
			end
			record(#onScreen == 0,
				device.Name .. ": every objective readout yields to a live dispatch briefing,"
				.. " so the two can never share the corner",
				table.concat(onScreen, ", "))
			player:SetAttribute("UIRegressionForceDispatchActive", nil)
			player:SetAttribute("UIRegressionForceLevel3Reader", nil)
			player:SetAttribute("UIRegressionForceReaderHidden", nil)
			task.wait(0.15)
		end
	end)

	-- resetScenario FIRST: it writes attributes and gui states of its own, so
	-- running it after the restore would re-dirty everything the snapshot just
	-- put back -- which is exactly what the residue check caught.
	pcall(resetScenario)
	task.wait(0.15)
	Fit.restore(saved)
	task.wait(0.2)
	if not ran then
		state.Failures += 1
		state.Checks += 1
		state.note("  FAIL the objective corner matrix ran  (" .. tostring(runError) .. ")")
	end
	local residue, residueNote = Fit.residue(saved)
	if residueNote then state.note(residueNote) end
	record(#residue == 0,
		"the matrix restored every borrowed attribute, every borrowed ScreenGui's"
			.. " Enabled and every borrowed descendant's Visible, Active and"
			.. " CanvasPosition, the terminal tab, the reader state and the caption",
		table.concat(residue, "; "))
	return state.finish()
end

function UIRegression.ObjectiveCornerMatrix(token: string?): (string, number)
	return Fit.lane("ObjectiveCornerMatrix", token, Fit.bodyObjectiveCornerMatrix)
end

-- ---------------------------------------------------------------------------
-- DispatchCompactMatrix
-- ---------------------------------------------------------------------------

-- The compact contract for the phone briefing, asserted as a MAXIMUM footprint
-- rather than as the absence of an overlap. BriefingFitMatrix already proves
-- the panel's internals fit each other and that the panel fits its band; what
-- it cannot say -- and what the owner measured on a real iPhone 16 Pro Max --
-- is that a band-filling 768x117 panel for two readouts and one sentence is far
-- too much of the screen.
--
-- The reference device carries a HARD bound: 560 wide and 100 high on 956x440,
-- i.e. 59% and 23%. Every other phone is bound by what it PUBLISHES -- the
-- compact target it computed, and the ladder rung it had to climb -- so a
-- smaller screen may take the extra its own copy needs and nothing more.
Fit.DispatchReference = {Width = 560, Height = 100}

function Fit.bodyDispatchCompactMatrix(): (string, number)
	local player = Players.LocalPlayer
	local state = Fit.recorder("=== dispatch briefing, compact footprint, every device ===")
	local record = state.record
	-- (b) AWAIT ITS NATURAL END, BOUNDED. See Fit.awaitQuietDispatch: this lane
	-- cannot run without interrupting a live transmission, and it must not
	-- interrupt one. The wait is BEFORE Fit.borrow, so the snapshot is of a quiet
	-- world and the restore has nothing to be forgiven for.
	local quiet, dispatchWhy = Fit.awaitQuietDispatch()
	if not quiet then
		record(false, "no real dispatch briefing was live when the matrix started",
			dispatchWhy)
		return state.finish()
	end
	local saved = Fit.borrow()

	local guide = findGui("LevelOneGuideGui")
	local panel = guide and guide:FindFirstChild("CommandSubtitles")
	local subtitle = panel and panel:FindFirstChild("Subtitle")
	local controls = panel and panel:FindFirstChild("BriefingControls")
	local mute = controls and controls:FindFirstChild("DispatchMuteButton")
	local stop = controls and controls:FindFirstChild("DispatchStopButton")
	if not (panel and subtitle and controls and mute and stop) then
		record(false, "the briefing panel exists to be measured",
			string.format("panel=%s subtitle=%s controls=%s mute=%s stop=%s",
				tostring(panel ~= nil), tostring(subtitle ~= nil), tostring(controls ~= nil),
				tostring(mute ~= nil), tostring(stop ~= nil)))
		return state.finish()
	end

	local ran, runError = pcall(function()
		for _, device in ipairs(Fit.Devices) do
			local applied = Fit.apply(device)
			record(applied, device.Name .. ": the device override took before the row ran",
				applied and "" or "timed out waiting for UIDevice to report it")
			resetScenario(true)
			local screen = findGui("LevelOneGuideGui")
			if screen then (screen :: ScreenGui).Enabled = true end
			player:SetAttribute("UIRegressionForceDispatchActive", true)
			setLongDispatchCue()
			task.wait(0.4)

			local layout = UIDevice.Layout()
			local viewport, insetY = device.Size, layout.Inset.Y
			local panelRect = UIRegression.ResolveRect(panel, viewport, insetY)
			local subtitleRect = UIRegression.ResolveRect(subtitle, viewport, insetY)
			local controlsRect = UIRegression.ResolveRect(controls, viewport, insetY)
			state.note(string.format("--- %s --- panel %s", device.Name, Fit.text(panelRect)))
			record(panelRect ~= nil and panelRect.Unresolvable == nil
				and subtitleRect ~= nil and controlsRect ~= nil,
				device.Name .. ": the briefing rectangles are analytically resolvable",
				panelRect and panelRect.Unresolvable or "nil rect")
			if not (panelRect and subtitleRect and controlsRect) then continue end

			if not device.Touch then
				record(panelRect.Width <= viewport.X + 1 and panelRect.Height <= viewport.Y + 1,
					device.Name .. ": desktop keeps its authored composition", Fit.text(panelRect))
				continue
			end

			-- The reference device, bound absolutely.
			if device.Size == Vector2.new(956, 440) then
				record(panelRect.Width <= Fit.DispatchReference.Width + 1
					and panelRect.Height <= Fit.DispatchReference.Height + 1,
					device.Name .. ": at most 560x100 -- 59% of the width and 23% of"
					.. " the height, the owner's measured target",
					string.format("%.0fx%.0f (%.0f%% x %.0f%%)", panelRect.Width, panelRect.Height,
						panelRect.Width / viewport.X * 100, panelRect.Height / viewport.Y * 100))
			end

			-- INDEPENDENT EXPECTATIONS. The published attributes are checked for
			-- AGREEMENT, but they are no longer the oracle: a bound taken from the
			-- value production printed can only ever confirm that production
			-- agrees with itself. The compact target is recomputed here from the
			-- stated contract -- 59% of the width capped at 560, 23% of the height
			-- capped at 100 -- and the panel is measured against THAT.
			-- The HOME RECT, re-derived by the same rule production uses: the top
			-- band while it can hold a briefing, and UIDevice's movement-free
			-- ModalArea when it cannot. Re-deriving it here rather than reading
			-- it back keeps the expectation independent.
			local home = layout.TopBand
			if home.Height < 80 and layout.ModalArea.Height > home.Height then
				home = layout.ModalArea
			end
			local expectedWidth = math.min(math.floor(home.Width),
				math.max(240, math.min(560, math.floor(viewport.X * .59))))
			local expectedHeight = math.max(64, math.min(100, math.floor(viewport.Y * .23)))
			local compactWidth = panel:GetAttribute("BriefingCompactWidth")
			local compactCeiling = panel:GetAttribute("BriefingCompactCeiling")
			local ceiling = panel:GetAttribute("BriefingBandCeiling")
			local rung = panel:GetAttribute("BriefingWidthRung")
			local published = type(compactWidth) == "number"
				and type(compactCeiling) == "number" and type(ceiling) == "number"
				and type(rung) == "number"
			record(published,
				device.Name .. ": the layout publishes the compact contract it applied",
				string.format("width=%s ceiling=%s effective=%s rung=%s",
					tostring(compactWidth), tostring(compactCeiling),
					tostring(ceiling), tostring(rung)))
			-- ...and what it published must MATCH what the contract says it should
			-- have been. A drift here means production and this matrix have
			-- stopped describing the same rule.
			record(published and math.abs(compactWidth - expectedWidth) <= 1
				and math.abs(compactCeiling - expectedHeight) <= 1,
				device.Name .. ": and it matches the target recomputed independently",
				string.format("published %sx%s vs expected %dx%d",
					tostring(compactWidth), tostring(compactCeiling),
					expectedWidth, expectedHeight))
			-- GUARD the rung before comparing it. `rung > 1` on a nil rung is a
			-- runtime error, and on a matrix that swallowed it, a silent skip.
			if published then
				record(panelRect.Width <= expectedWidth + 1 or rung > 1,
					device.Name .. ": the panel keeps its compact width, or reports the"
					.. " rung it had to climb for its own copy",
					string.format("%.0f wide vs target %d, rung %d",
						panelRect.Width, expectedWidth, rung))
				record(panelRect.Height <= expectedHeight + 1
						or panelRect.Height <= ceiling + 1,
					device.Name .. ": and its compact height, or the measured height its"
					.. " own copy required",
					string.format("%.0f tall vs target %d, effective %.0f",
						panelRect.Height, expectedHeight, ceiling))
				-- FOOTPRINT, stated in the axis each orientation can actually give.
				--
				-- A width-only rule was tried here first and was the wrong shape:
				-- it failed a 375x667 portrait phone at 330x100 -- 88% of the
				-- width but 15% of the height, and 41% less screen than the
				-- 351x160 that shipped -- while passing anything wide and tall.
				-- Width is the cheap axis in portrait and the expensive one in
				-- landscape, so the rule follows the orientation, and an AREA
				-- bound underwrites both. That is three assertions where there
				-- was one, and every device in this matrix clears all three with
				-- margin (5-17% of screen area).
				if not layout.Portrait then
					record(panelRect.Width <= viewport.X * .75 + 1,
						device.Name .. ": landscape never gives it three quarters of the width",
						string.format("%.0f of %.0f (%.0f%%)", panelRect.Width, viewport.X,
							panelRect.Width / viewport.X * 100))
				end
				-- MEASURED NECESSITY, applied to EVERY touch device rather than
				-- only to the ones that cannot serve the compact target. It used
				-- to be the else-branch of that classification, which made it the
				-- weaker devices' rule and left the roomy ones free to sit at
				-- their ceiling with a sentence that occupied two thirds of it.
				-- It is the strictest of the three bounds here and there is no
				-- device it should not hold for: the panel may be no taller than
				-- the two 44px readouts plus the copy this device's width forces
				-- AT THE FACE IT ACHIEVED, plus the panel's own padding.
				--
				-- The bound is taken at the achieved face rather than at the
				-- 10px floor on purpose: the contract asks for 11 wherever
				-- width or height can be traded for it, so measuring the bound
				-- at 10 would call a panel that bought legibility with 30px of
				-- height "too tall" for doing exactly what it was told.
				-- The face the SEARCH ran at, not only the one the final pick
				-- landed on: the panel's height was chosen to satisfy the
				-- required face, so that is the face the necessity bound is
				-- measured at.
				local achieved = panel:GetAttribute("BriefingRequiredFace")
				local landed = panel:GetAttribute("BriefingFace")
				if type(achieved) ~= "number" then achieved = 11 end
				if type(landed) == "number" then achieved = math.max(achieved, landed) end
				local copyNeed = Fit.measureText(LONG_DISPATCH_CUE,
					(subtitle :: any).FontFace, achieved, subtitleRect.Width)
				-- The readouts STACK on a panel too narrow to hold two of them
				-- side by side, and a stacked pair is 44 + 6 + 44, not 44. A
				-- bound that assumed one row called a correctly stacked panel
				-- fifty pixels too tall.
				local twoColumns = panelRect.Width >= 2 * 120 + 10 + 24
				local rowsHeight = twoColumns and 44 or (44 * 2 + 6)
				-- HEIGHT SPENT TO EARN THE FACE IS NOT HEIGHT WASTED. The panel
				-- does not choose its type size freely: the authored ladder
				-- offers 16px only to a copy box of at least 40 and 13px only to
				-- one of at least 33, so a box held at 40 for a sentence that
				-- occupies 32 is the panel buying the larger face, which is what
				-- the contract asks it to do wherever height can be traded for
				-- legibility. Measuring the bound without that allowance failed
				-- both iPads by exactly the two pixels the ladder demands. The
				-- thresholds are stated here on purpose: if the ladder changes,
				-- this fails and both ends get updated together.
				local faceBoxFloor = 0
				if achieved >= 16 then faceBoxFloor = 40
				elseif achieved >= 13 then faceBoxFloor = 33 end
				local copyBox = math.max(copyNeed and copyNeed.Y or 40, faceBoxFloor)
				local allowed = rowsHeight + copyBox + 12
				record(panelRect.Height <= allowed + 1,
					device.Name .. ": no taller than its own copy requires at the"
					.. " face it achieved",
					string.format("%.0f tall, necessity bound %.0f at %dpx"
						.. " (%s readouts), home %.0fx%.0f",
						panelRect.Height, allowed, achieved,
						twoColumns and "side-by-side" or "stacked",
						home.Width, home.Height))

				-- THE PROPORTIONAL BOUNDS, on top, for the devices that can
				-- actually serve the compact target. "Can" is two questions, not
				-- one: the home rect has to HOLD the target, and the target has
				-- to hold this device's COPY. A 568x320 landscape phone clears
				-- the first and fails the second outright -- two 44px readouts
				-- plus the live cue at the readable floor need about 146px where
				-- a quarter of that screen is 80 -- so asserting a quarter there
				-- would be demanding a panel that cannot exist, and the
				-- necessity bound above is what holds it to account instead.
				local servesCompactTarget = home.Width >= expectedWidth
					and home.Height >= expectedHeight
					and allowed <= expectedHeight
				if servesCompactTarget then
					record(panelRect.Height <= viewport.Y * .25 + 1,
						device.Name .. ": and never a quarter of the height",
						string.format("%.0f of %.0f (%.0f%%)", panelRect.Height, viewport.Y,
							panelRect.Height / viewport.Y * 100))
					local share = (panelRect.Width * panelRect.Height) / (viewport.X * viewport.Y)
					record(share <= .20,
						device.Name .. ": and never a fifth of the screen",
						string.format("%.1f%% of the screen", share * 100))
				else
					state.note(string.format(
						"      %s: the compact target cannot hold this device's copy"
						.. " (needs %.0f in %d), so the proportional bounds do not"
						.. " apply and the necessity bound above is the whole rule",
						device.Name, allowed, expectedHeight))
				end
			end

			-- SAFE CONTAINMENT, and against the authoritative Safe rect rather than
			-- "somewhere on screen". TopBand is inside Safe by construction now,
			-- but asserting the band would test the construction rather than the
			-- panel.
			record(Fit.within(panelRect, layout.Safe, 1),
				device.Name .. ": the briefing lies inside the authoritative safe area",
				string.format("%s vs safe (%.0f,%.0f)-(%.0f,%.0f)", Fit.text(panelRect),
					layout.Safe.Left, layout.Safe.Top, layout.Safe.Right, layout.Safe.Bottom))
			record(UIDevice.OverlapsMovementZone(panelRect.Left, panelRect.Top,
				panelRect.Right, panelRect.Bottom) == nil,
				device.Name .. ": and enters no movement zone",
				tostring(UIDevice.OverlapsMovementZone(panelRect.Left, panelRect.Top,
					panelRect.Right, panelRect.Bottom)))

			-- THE READABLE FLOOR. Never 8 or 9 on a handheld: the copy stays at
			-- least 10, and the layout is expected to have reached 11 wherever it
			-- could trade width or height for it.
			local face = panel:GetAttribute("BriefingFace")
			record(type(face) == "number" and face >= 10,
				device.Name .. ": the briefing copy never drops below a readable 10px",
				tostring(face))
			record(subtitle.TextWrapped == true
				and (subtitle :: any).TextTruncate == Enum.TextTruncate.None,
				device.Name .. ": and it wraps rather than clipping",
				string.format("wrapped=%s truncate=%s", tostring(subtitle.TextWrapped),
					tostring((subtitle :: any).TextTruncate)))

			-- A FIXED, INDEPENDENT ceiling for every touch row, so a row cannot
			-- grow to fill a panel that grew.
			for _, spec in ipairs({{"MUTE", mute}, {"STOP", stop}}) do
				local node = spec[2] :: any
				local rowWidth = node.Size.X.Offset + node.Size.X.Scale * controlsRect.Width
				local rowHeight = node.Size.Y.Offset + node.Size.Y.Scale * controlsRect.Height
				-- The half-panel clause only applies where two rows are meant to sit
				-- SIDE BY SIDE. On a panel too narrow for that the rows stack, and
				-- a stacked row is supposed to span the panel.
				local sideBySide = panelRect.Width >= 2 * 120 + 10 + 24
				record(rowWidth <= 168 and rowHeight <= 56
					and (not sideBySide or rowWidth <= panelRect.Width * .5 + 1),
					device.Name .. ": " .. spec[1] .. " keeps an independent size ceiling"
					.. " (<=168x56, and at most half the panel where two fit side by side)",
					string.format("%.0fx%.0f in a %.0f-wide panel (sideBySide=%s)",
						rowWidth, rowHeight, panelRect.Width, tostring(sideBySide)))
			end

			-- Subtlety is not only size. A caption over the game, not a dialog.
			local rule = panel:FindFirstChildOfClass("UIStroke")
			record((panel :: any).BackgroundTransparency >= 0.24
				and (rule == nil or rule.Transparency >= 0.45),
				device.Name .. ": the chrome is a caption's, not a dialog's",
				string.format("fill=%.2f rule=%s", (panel :: any).BackgroundTransparency,
					rule and string.format("%.2f", rule.Transparency) or "none"))

			-- The two controls keep their targets whatever the panel gave up.
			for _, spec in ipairs({{"MUTE", mute}, {"STOP", stop}}) do
				local node = spec[2] :: any
				local width = node.Size.X.Offset + node.Size.X.Scale * controlsRect.Width
				local height = node.Size.Y.Offset + node.Size.Y.Scale * controlsRect.Height
				record(width >= 44 and height >= 44,
					device.Name .. ": " .. spec[1] .. " keeps a 44x44 target inside the"
					.. " compact panel",
					string.format("%.0fx%.0f", width, height))
			end

			record(not Fit.overlaps(subtitleRect, controlsRect),
				device.Name .. ": the copy does not land on the MUTE/STOP row",
				string.format("copy %s vs row %s", Fit.text(subtitleRect), Fit.text(controlsRect)))
			record(Fit.within(subtitleRect, panelRect, 1) and Fit.within(controlsRect, panelRect, 1),
				device.Name .. ": and both stay inside the panel",
				string.format("copy %s row %s", Fit.text(subtitleRect), Fit.text(controlsRect)))

			-- LONG TEXT. The compact panel has to hold the longest authored cue at
			-- the face it actually chose, or the shrink was bought with a clipped
			-- briefing -- which is not a trade this matrix will pass.
			local bounds, boundsError = Fit.measureText(LONG_DISPATCH_CUE,
				(subtitle :: any).FontFace, (subtitle :: any).TextSize,
				subtitleRect.Width)
			record(bounds ~= nil and bounds.X <= subtitleRect.Width + 1
				and bounds.Y <= subtitleRect.Height + 1,
				device.Name .. ": the longest dispatch cue still fits its box",
				bounds and string.format("needs %.0fx%.0f in %.0fx%.0f at %dpx",
					bounds.X, bounds.Y, subtitleRect.Width, subtitleRect.Height,
					(subtitle :: any).TextSize) or boundsError)

			-- THE STRESS CASE, kept separate from the runtime fit above. The 1.6x
			-- localisation string is headroom for a translation nobody has
			-- shipped; it must not be what every English briefing is sized
			-- against, but the panel should still hold it at the hard floor.
			local stress = "Noch wichtiger: das Aktivieren einer Pumpstation alarmiert offenbar"
				.. " eine bislang nicht identifizierte, ungewoehnlich grosse Entitaet und"
				.. " verraet ihr eure derzeitige Position sofort."
			local stressBounds = Fit.measureText(stress, (subtitle :: any).FontFace, 10,
				subtitleRect.Width)
			-- IT FITS TODAY, or the panel's own home could grow to hold it.
			--
			-- The second clause is the point of the change that produced it. This
			-- panel used to be sized for the 1.6x string on EVERY device, which is
			-- why every English briefing on a portrait phone rendered at 8px. The
			-- runtime is fitted to the copy that is actually on screen; what this
			-- asserts about the localisation is that the HEADROOM exists -- the
			-- home rectangle is big enough that a real translation could be
			-- accommodated by growing into it -- rather than that a shipped
			-- English cue must pay for it now.
			local stressNeed = stressBounds and stressBounds.Y or math.huge
			local headroom = home.Height >= 46 + stressNeed + 4
			record(stressBounds ~= nil
				and (stressNeed <= subtitleRect.Height + 1 or headroom),
				device.Name .. ": a 1.6x localisation fits at the 10px floor, or the"
				.. " panel's home has the headroom to hold one",
				stressBounds and string.format(
					"needs %.0fx%.0f in %.0fx%.0f; home %.0f tall, needs %.0f",
					stressBounds.X, stressBounds.Y, subtitleRect.Width,
					subtitleRect.Height, home.Height, 46 + stressNeed + 4)
					or "unmeasurable")

			local glyph = Fit.keyGlyph(panel)
			record(glyph == nil,
				device.Name .. ": and no keyboard binding text on a handheld", glyph)
		end
	end)

	pcall(resetScenario)
	task.wait(0.15)
	Fit.restore(saved)
	task.wait(0.2)
	if not ran then
		state.Failures += 1
		state.Checks += 1
		state.note("  FAIL the dispatch compact matrix ran  (" .. tostring(runError) .. ")")
	end
	local residue, residueNote = Fit.residue(saved)
	if residueNote then state.note(residueNote) end
	record(#residue == 0,
		"the matrix restored every borrowed attribute, every borrowed ScreenGui's"
			.. " Enabled and every borrowed descendant's Visible, Active and"
			.. " CanvasPosition, the terminal tab, the reader state and the caption",
		table.concat(residue, "; "))
	return state.finish()
end

function UIRegression.DispatchCompactMatrix(token: string?): (string, number)
	return Fit.lane("DispatchCompactMatrix", token, Fit.bodyDispatchCompactMatrix)
end

-- ---------------------------------------------------------------------------
-- SafeAreaMatrix
-- ---------------------------------------------------------------------------

-- The matrix that would have caught P0 on the day it was written.
--
-- Everything else in this file measures RECTANGLES the layout produced. This
-- measures the layout's INPUTS: that UIDevice's display and safe area are the
-- engine's own inset areas and not a reconstruction, and that a ScreenGui's
-- frame really is the inset area its ScreenInsets names -- for all four values,
-- with a live probe gui per value rather than a heuristic.
--
-- WHAT IT WOULD HAVE CAUGHT. Measured on a Studio Device Emulator run,
-- iPhone 16 Pro Max: Camera.ViewportSize is 831x418 and is ALREADY device-safe,
-- while GetInsetArea(None) is (-62,-58)..(893,381). The layout built its display
-- as None.Min plus the camera -- (-62,-58)..(769,360) -- and then subtracted the
-- cutout a second time, landing on a safe right edge of 707 where the truth is
-- 831. Every touch panel in the game was pinned 124px inside the screen.
--
-- C_TWO_HALVES_20260831 -- WHAT SHIPPED BROKEN. The lane read as one sweep over
-- twelve "devices", and it was nothing of the sort. Exactly one of those rows
-- was ever measured; the rest were plausible-looking numbers typed from
-- memory, and the report gave them the same standing. Someone reading a red
-- line on "iPhone SE landscape 667x375" had every reason to believe an iPhone
-- SE had been observed doing that, and no iPhone SE was ever involved.
--
-- The lane is now explicitly two halves and says so in its own header:
--   1. THE MEASURED DEVICE. Fit.MeasuredCase, checked against the LIVE engine
--      with no fixture in play. The relationships it encodes are asserted on
--      every host; its exact rectangles are asserted only on the host that
--      reports them, and the report says which of the two happened.
--   2. THE ADVERSARIAL FIXTURES. Fit.Devices, which are shapes the layout has
--      to survive, not observations of hardware. Each row states its viewport,
--      its housing, its topbar and the four rectangles those determine, and
--      every one of those literals is asserted -- origin, size and all four
--      edges -- plus an anchored child and a scaled child per enum value, so a
--      model that moved an origin or dropped an inset has nowhere to hide.
function Fit.bodySafeAreaMatrix(): (string, number)
	local state = Fit.recorder(
		"=== safe area: ONE measured device, then eleven ADVERSARIAL FIXTURES ===")
	local record = state.record
	state.note("  note the fixture rows below are shapes the layout must survive,"
		.. " NOT measurements of hardware -- the only measured case is"
		.. " Fit.MeasuredCase, and it is the only row checked against the live"
		.. " engine")
	-- (b) AWAIT ITS NATURAL END, BOUNDED. See Fit.awaitQuietDispatch: this lane
	-- cannot run without interrupting a live transmission, and it must not
	-- interrupt one. The wait is BEFORE Fit.borrow, so the snapshot is of a quiet
	-- world and the restore has nothing to be forgiven for.
	local quiet, dispatchWhy = Fit.awaitQuietDispatch()
	if not quiet then
		record(false, "no real dispatch briefing was live when the matrix started",
			dispatchWhy)
		return state.finish()
	end
	local saved = Fit.borrow()

	local ran, runError = pcall(function()
		-- ── the REAL device, no fixture ──────────────────────────────────
		workspace:SetAttribute("UIRegressionViewport", nil)
		workspace:SetAttribute("ForceTouchUI", nil)
		workspace:SetAttribute("UIRegressionSafeInsets", nil)
		-- The topbar override is cleared alongside the other three. It is inert
		-- while the viewport override is off -- UIDevice only consults it on the
		-- synthetic branch -- but a half of the sweep whose entire point is that no
		-- fixture is in play cannot leave one of the fixture's four inputs set and
		-- expect a later reader to know it did not matter.
		workspace:SetAttribute("UIRegressionTopbarInset", nil)
		task.wait(0.4)

		local none = GuiService:GetInsetArea(Enum.ScreenInsets.None)
		local core = GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
		local device = GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
		local layout = UIDevice.Layout()
		local camera = workspace.CurrentCamera.ViewportSize
		state.note(string.format("--- real device: camera %.0fx%.0f ---", camera.X, camera.Y))
		state.note(string.format("      None   (%.0f,%.0f)..(%.0f,%.0f)",
			none.Min.X, none.Min.Y, none.Max.X, none.Max.Y))
		state.note(string.format("      Core   (%.0f,%.0f)..(%.0f,%.0f)",
			core.Min.X, core.Min.Y, core.Max.X, core.Max.Y))
		state.note(string.format("      Device (%.0f,%.0f)..(%.0f,%.0f)",
			device.Min.X, device.Min.Y, device.Max.X, device.Max.Y))
		state.note(string.format("      UIDevice Display (%.0f,%.0f)..(%.0f,%.0f)  Safe (%.0f,%.0f)..(%.0f,%.0f)",
			layout.Display.Left, layout.Display.Top, layout.Display.Right, layout.Display.Bottom,
			layout.Safe.Left, layout.Safe.Top, layout.Safe.Right, layout.Safe.Bottom))

		record(layout.Synthetic ~= true,
			"the layout reports itself as a real device, not a fixture",
			tostring(layout.Synthetic))
		record(math.abs(layout.Display.Left - none.Min.X) < 0.5
			and math.abs(layout.Display.Top - none.Min.Y) < 0.5
			and math.abs(layout.Display.Right - none.Max.X) < 0.5
			and math.abs(layout.Display.Bottom - none.Max.Y) < 0.5,
			"Display IS GetInsetArea(None) -- not None.Min plus Camera.ViewportSize",
			string.format("(%.0f,%.0f)..(%.0f,%.0f) vs (%.0f,%.0f)..(%.0f,%.0f)",
				layout.Display.Left, layout.Display.Top, layout.Display.Right,
				layout.Display.Bottom, none.Min.X, none.Min.Y, none.Max.X, none.Max.Y))
		local expected = {
			Left = math.max(core.Min.X, device.Min.X), Top = math.max(core.Min.Y, device.Min.Y),
			Right = math.min(core.Max.X, device.Max.X), Bottom = math.min(core.Max.Y, device.Max.Y),
		}
		record(math.abs(layout.Safe.Left - expected.Left) < 0.5
			and math.abs(layout.Safe.Top - expected.Top) < 0.5
			and math.abs(layout.Safe.Right - expected.Right) < 0.5
			and math.abs(layout.Safe.Bottom - expected.Bottom) < 0.5,
			"Safe IS CoreUISafeInsets intersected with DeviceSafeInsets",
			string.format("(%.0f,%.0f)..(%.0f,%.0f) vs (%.0f,%.0f)..(%.0f,%.0f)",
				layout.Safe.Left, layout.Safe.Top, layout.Safe.Right, layout.Safe.Bottom,
				expected.Left, expected.Top, expected.Right, expected.Bottom))
		-- THE DOUBLE-APPLICATION, named. The camera is the device-safe size, so
		-- a safe rect narrower than the camera means the cutout was taken twice.
		record(layout.Safe.Right - layout.Safe.Left >= camera.X - 0.5,
			"the safe area is not narrower than the camera -- the cutout is not"
			.. " applied twice",
			string.format("safe width %.0f vs camera width %.0f",
				layout.Safe.Right - layout.Safe.Left, camera.X))

		-- ── the ONE measured device, held to its own numbers ────────────
		--
		-- Fit.MeasuredCase is the only row in this file that was read off an
		-- engine. On the host that produced it -- Studio's Device Emulator on
		-- an iPhone 16 Pro Max, landscape -- every rectangle it records must
		-- still come back byte for byte, or the emulator, the engine or the
		-- recording has moved and nothing downstream of it can be trusted.
		-- Anywhere else the numbers cannot apply, and the report SAYS the row
		-- did not apply rather than quietly counting a pass: a check that
		-- reports green on a host it never ran on is the vacuous kind this
		-- audit is removing, not the kind it is adding.
		local measured = Fit.MeasuredCase
		local onMeasuredHost = math.abs(none.Min.X - measured.None.Min.X) < 0.5
			and math.abs(none.Min.Y - measured.None.Min.Y) < 0.5
			and math.abs(none.Max.X - measured.None.Max.X) < 0.5
			and math.abs(none.Max.Y - measured.None.Max.Y) < 0.5
		if onMeasuredHost then
			state.note("      this host IS the measured device: every recorded"
				.. " rectangle is asserted exactly")
			for _, entry in ipairs({
				{"DeviceSafeInsets", device, measured.DeviceSafeInsets},
				{"CoreUISafeInsets", core, measured.CoreUISafeInsets},
				{"TopbarSafeInsets", GuiService:GetInsetArea(
					Enum.ScreenInsets.TopbarSafeInsets), measured.TopbarSafeInsets},
			}) do
				local live, want = entry[2], entry[3]
				record(math.abs(live.Min.X - want.Min.X) < 0.5
					and math.abs(live.Min.Y - want.Min.Y) < 0.5
					and math.abs(live.Max.X - want.Max.X) < 0.5
					and math.abs(live.Max.Y - want.Max.Y) < 0.5,
					"measured: GetInsetArea(" .. entry[1] .. ") is what was recorded",
					string.format("(%.0f,%.0f)..(%.0f,%.0f) vs (%.0f,%.0f)..(%.0f,%.0f)",
						live.Min.X, live.Min.Y, live.Max.X, live.Max.Y,
						want.Min.X, want.Min.Y, want.Max.X, want.Max.Y))
			end
			record(math.abs(camera.X - measured.Camera.X) < 0.5
				and math.abs(camera.Y - measured.Camera.Y) < 0.5,
				"measured: Camera.ViewportSize is what was recorded, and is the"
				.. " device-safe size rather than the display's",
				string.format("%.0fx%.0f vs %.0fx%.0f", camera.X, camera.Y,
					measured.Camera.X, measured.Camera.Y))
		else
			state.note("      this host is NOT the measured device -- the recorded"
				.. " rectangles are not asserted here; the relationships above are")
		end

		-- ── a live probe gui per ScreenInsets value ─────────────────────
		for _, kind in ipairs(Enum.ScreenInsets:GetEnumItems()) do
			local probe = Instance.new("ScreenGui")
			probe.Name = "SafeAreaProbe"
			probe.ResetOnSpawn = false
			probe.ScreenInsets = kind
			probe.Parent = playerGui()
			local child = Instance.new("Frame")
			child.Size = UDim2.fromOffset(30, 30)
			child.Position = UDim2.fromOffset(100, 200)
			child.Parent = probe
			task.wait(0.12)
			local area = GuiService:GetInsetArea(kind)
			record(math.abs(probe.AbsolutePosition.X - area.Min.X) < 0.5
				and math.abs(probe.AbsolutePosition.Y - area.Min.Y) < 0.5
				and math.abs(probe.AbsoluteSize.X - (area.Max.X - area.Min.X)) < 0.5
				and math.abs(probe.AbsoluteSize.Y - (area.Max.Y - area.Min.Y)) < 0.5,
				"a ScreenGui at " .. kind.Name .. " occupies exactly that inset area",
				string.format("gui (%.0f,%.0f) %.0fx%.0f vs area (%.0f,%.0f) %.0fx%.0f",
					probe.AbsolutePosition.X, probe.AbsolutePosition.Y,
					probe.AbsoluteSize.X, probe.AbsoluteSize.Y,
					area.Min.X, area.Min.Y, area.Max.X - area.Min.X, area.Max.Y - area.Min.Y))
			-- ...and the resolver agrees with it, per enum. This is the check the
			-- old Y-origin heuristic could not make: None and DeviceSafeInsets
			-- share a Y origin and differ in width by the whole cutout.
			local resolved = UIRegression.ResolveRect(child, camera, layout.Inset.Y)
			record(resolved ~= nil and resolved.Unresolvable == nil
				and math.abs(resolved.Left - child.AbsolutePosition.X) < 0.5
				and math.abs(resolved.Top - child.AbsolutePosition.Y) < 0.5,
				"and the resolver places a child of it exactly where the engine does"
				.. " (" .. kind.Name .. ")",
				resolved and string.format("resolved (%.0f,%.0f) vs live (%.0f,%.0f)",
					resolved.Left, resolved.Top,
					child.AbsolutePosition.X, child.AbsolutePosition.Y) or "unresolvable")
			probe:Destroy()
		end

		-- ── every fixture must be exactly what it claims ────────────────
		for _, fixture in ipairs(Fit.Devices) do
			Fit.sweepFixture(fixture, state)
		end

		-- ── and the model must reproduce the ONE real device ────────────
		--
		-- Eleven adversarial shapes prove the model is self-consistent. They
		-- cannot prove it is right, because every one of them was invented for
		-- it. The measured iPhone 16 Pro Max was not: its housing and topbar
		-- are read straight off four rectangles an engine printed, and if the
		-- fixture model cannot turn those two insets back into those four
		-- rectangles then the eleven rows above are eleven descriptions of a
		-- model that does not describe a phone.
		local rebuilt = Fit.MeasuredCase.Fixture
		Fit.sweepFixture(rebuilt, state)
		-- The rebuild's literals ARE the measurement, and this is where that
		-- gets proved instead of asserted in a comment: place each stated
		-- rectangle at the measured display's own origin and it must land on
		-- the measured inset area, to the pixel. Without this the rebuilt row
		-- could be internally consistent fiction and would still pass every
		-- check above -- because every check above compares it to itself.
		local base = Fit.MeasuredCase.None.Min
		for _, entry in ipairs({
			{"None", Fit.MeasuredCase.None},
			{"DeviceSafeInsets", Fit.MeasuredCase.DeviceSafeInsets},
			{"CoreUISafeInsets", Fit.MeasuredCase.CoreUISafeInsets},
		}) do
			local stated = rebuilt.Frames[entry[1]]
			local want = entry[2]
			record(math.abs(base.X + stated[1] - want.Min.X) < 0.5
				and math.abs(base.Y + stated[2] - want.Min.Y) < 0.5
				and math.abs(base.X + stated[3] - want.Max.X) < 0.5
				and math.abs(base.Y + stated[4] - want.Max.Y) < 0.5,
				"the rebuilt fixture's stated " .. entry[1] .. " rectangle IS the"
				.. " measured one, moved to the measured display's origin",
				string.format("(%.0f,%.0f)..(%.0f,%.0f) vs (%.0f,%.0f)..(%.0f,%.0f)",
					base.X + stated[1], base.Y + stated[2],
					base.X + stated[3], base.Y + stated[4],
					want.Min.X, want.Min.Y, want.Max.X, want.Max.Y))
		end
		do
			-- The topbar strip is the one rectangle the fixture model knowingly
			-- cannot reproduce whole: the engine reserves a run at its left for
			-- Roblox's own buttons -- 164 absolute, 226 into the display, on the
			-- device we measured -- and no fixture states that width because
			-- nothing in this game positions against it. So the three edges that
			-- ARE determined are held exactly, and the fourth is held to the one
			-- thing that is true of it. That is a NARROWER assertion, stated as
			-- one; it is not the wider assertion loosened until it passed.
			local stated = rebuilt.Frames.TopbarSafeInsets
			local want = Fit.MeasuredCase.TopbarSafeInsets
			record(math.abs(base.Y + stated[2] - want.Min.Y) < 0.5
				and math.abs(base.X + stated[3] - want.Max.X) < 0.5
				and math.abs(base.Y + stated[4] - want.Max.Y) < 0.5,
				"the rebuilt fixture's topbar strip has the measured strip's top,"
				.. " right and bottom edges",
				string.format("top %.0f right %.0f bottom %.0f vs %.0f %.0f %.0f",
					base.Y + stated[2], base.X + stated[3], base.Y + stated[4],
					want.Min.Y, want.Max.X, want.Max.Y))
			record(base.X + stated[1] <= want.Min.X + 0.5
				and base.X + stated[1] >= Fit.MeasuredCase.CoreUISafeInsets.Min.X - 0.5,
				"and its left edge lies between the core-safe left and the measured"
				.. " strip's left -- the button run no fixture states",
				string.format("%.0f, core-safe left %.0f, measured strip left %.0f",
					base.X + stated[1], Fit.MeasuredCase.CoreUISafeInsets.Min.X,
					want.Min.X))
		end
	end)

	pcall(resetScenario)
	task.wait(0.15)
	Fit.restore(saved)
	task.wait(0.2)
	if not ran then
		state.Failures += 1
		state.Checks += 1
		state.note("  FAIL the safe area matrix ran  (" .. tostring(runError) .. ")")
	end
	local residue, residueNote = Fit.residue(saved)
	if residueNote then state.note(residueNote) end
	record(#residue == 0,
		"the matrix restored every borrowed attribute, every borrowed ScreenGui's"
			.. " Enabled and every borrowed descendant's Visible, Active and"
			.. " CanvasPosition, the terminal tab, the reader state and the caption",
		table.concat(residue, "; "))
	return state.finish()
end

function UIRegression.SafeAreaMatrix(token: string?): (string, number)
	return Fit.lane("SafeAreaMatrix", token, Fit.bodySafeAreaMatrix)
end

-- ---------------------------------------------------------------------------
-- ControlZoneMatrix
-- ---------------------------------------------------------------------------

-- C_LIVE_CONTROL_ZONE_20260831.
--
-- Zones.Controls is the rectangle every HUD in this game dodges, and until this
-- matrix nothing proved it was LIVE. The PROXY was proved -- a fixture states a
-- viewport and the arithmetic is checked against it -- but the proxy is not what
-- a player meets. The measured branch unions the CollectionService-tagged
-- buttons, and three separate things had to be true for that to work at all,
-- none of which were tested: that the tag is visible from THIS VM (the harness
-- runs in a different require cache from the LocalScripts, so a module-local
-- registry would be an empty table here), that a mutation invalidates the
-- cached layout at all, and that UIDevice.Changed fires for it -- the refresh
-- comparison ignored Zones.Controls entirely, so a layout whose only difference
-- was the cluster was computed and then dropped.
--
-- MUTATING A SHIPPING BUTTON DOES NOT WORK AS A PROBE, and the reason is worth
-- recording. NoiseReporter relays the cluster out on UIDevice.Changed, so moving
-- one of its buttons fires the invalidation, the layout pass puts the button
-- straight back, and the zone that comes out is the one that went in. Measured
-- on the live emulator: SNEAK moved 40px down produced two Changed fires and an
-- unmoved Top. That is the system being correct -- it converges in two passes --
-- but it makes the shipping buttons useless as evidence.
--
-- So the probe registers a control the HARNESS owns, which production has no
-- opinion about and never reasserts. Measured first-hand on the iPhone 16 Pro
-- Max emulator while this was written: registering a 64x64 frame above the
-- cluster moved Zones.Controls.Top from 110 to -12 and Count from 6 to 7 in one
-- Changed fire; unregistering restored both; destroying it restored both again.
function Fit.bodyControlZoneMatrix(): (string, number)
	-- A REAL briefing is the game's, not ours: this lane calls resetScenario,
	-- which used to silence one. Wait for it, bounded, and refuse rather than
	-- interrupt. Nothing is borrowed or forced before this returns.
	local quiet, quietWhy = Fit.awaitQuietDispatch()
	if not quiet then
		return "=== control zone: not reached ===\n  FAIL " .. tostring(quietWhy)
			.. "\nTOTAL: 1 checks, 1 failed", 1
	end
	local state = Fit.recorder("=== control zone: the LIVE registered cluster, not the proxy ===")
	local record = state.record
	local saved = Fit.borrow()
	local player = Players.LocalPlayer
	local probeControl = nil

	local ran, runError = pcall(function()
		-- THE REAL DEVICE, no fixture. The measured branch is deliberately not
		-- used for a synthetic viewport -- the live buttons are laid out for the
		-- REAL window and say nothing about a simulated one -- so this matrix has
		-- to run at the real size or it would be measuring the very proxy it
		-- exists to tell itself apart from.
		workspace:SetAttribute("UIRegressionViewport", nil)
		workspace:SetAttribute("UIRegressionSafeInsets", nil)
		workspace:SetAttribute("UIRegressionTopbarInset", nil)
		workspace:SetAttribute("ForceTouchUI", true)
		player:SetAttribute("InRound", true)
		for _, attribute in ipairs({"Escaped", "Level3_Hiding", "Spectating",
			"ZyntraStoreOpen", "DevPhoneOpen", "ZyntraReentryOpen"}) do
			player:SetAttribute(attribute, nil)
		end
		task.wait(0.8)

		-- Fetched here, not at file scope: this module is close enough to Luau's
		-- 200-local ceiling that one more top-level name is a real cost.
		local tagged = game:GetService("CollectionService"):GetTagged("UIDeviceControlRect")
		local drawn = {}
		for _, element in ipairs(tagged) do
			if element:IsA("GuiObject") and element.Visible
				and element.AbsoluteSize.X > 1 and element.AbsoluteSize.Y > 1 then
				table.insert(drawn, element)
			end
		end
		-- THE CROSS-VM CLAIM, stated first because everything else rests on it.
		record(#tagged >= 5,
			"the control cluster is visible to THIS VM through CollectionService"
			.. " -- a module-local registry would be empty here",
			string.format("%d tagged, %d of them drawn", #tagged, #drawn))
		if #drawn == 0 then
			record(false, "at least one registered control is drawn to union", "none")
			return
		end

		local function zone()
			return UIDevice.Layout().Zones.Controls
		end
		local before = zone()
		record(before.Measured == true and before.Count == #drawn,
			"Zones.Controls is the MEASURED union of the drawn controls, not the proxy",
			string.format("measured=%s count=%s vs %d drawn",
				tostring(before.Measured), tostring(before.Count), #drawn))

		local fires = 0
		local connection = UIDevice.Changed:Connect(function() fires += 1 end)

		-- A control production has no opinion about. See above for why a shipping
		-- button cannot serve here.
		probeControl = Instance.new("Frame")
		local control = probeControl
		control.Name = "UIRegressionControlProbe"
		control.AnchorPoint = Vector2.new(1, 1)
		control.BackgroundTransparency = 1
		control.Size = UDim2.fromOffset(64, 64)
		control.Position = UDim2.new(1, -22, 1, -(before.Bottom - before.Top) - 120)
		control.Parent = drawn[1].Parent
		task.wait(0.3)
		record(math.abs(zone().Top - before.Top) < 0.5,
			"an UNREGISTERED control does not move the zone -- the union is the tag,"
			.. " not whatever happens to be on screen",
			string.format("top %.0f, was %.0f", zone().Top, before.Top))

		local baseline = fires
		UIDevice.RegisterControlRect("UIRegressionControlProbe", control)
		task.wait(0.45)
		local grown = zone()
		record(grown.Top < before.Top - 1 and grown.Count == (before.Count or 0) + 1,
			"registering a control GROWS the live zone",
			string.format("top %.0f -> %.0f, count %s -> %s",
				before.Top, grown.Top, tostring(before.Count), tostring(grown.Count)))
		record(fires - baseline >= 1,
			"...and UIDevice.Changed fires for it -- a layout whose only difference"
			.. " is the cluster is no longer computed and dropped",
			string.format("%d fire(s)", fires - baseline))

		baseline = fires
		UIDevice.UnregisterControlRect(control)
		task.wait(0.45)
		local shrunk = zone()
		record(math.abs(shrunk.Top - before.Top) < 0.5 and shrunk.Count == before.Count,
			"unregistering SHRINKS it back exactly",
			string.format("top %.0f (was %.0f), count %s (was %s)",
				shrunk.Top, before.Top, tostring(shrunk.Count), tostring(before.Count)))
		record(fires - baseline >= 1, "...and fires Changed again",
			string.format("%d fire(s)", fires - baseline))

		-- DESTRUCTION, which is the path a real control actually takes.
		baseline = fires
		UIDevice.RegisterControlRect("UIRegressionControlProbe", control)
		task.wait(0.35)
		local reGrown = zone()
		control:Destroy()
		probeControl = nil
		task.wait(0.45)
		local gone = zone()
		record(reGrown.Top < before.Top - 1,
			"re-registering grows it once more -- the watch was not left dangling",
			string.format("top %.0f", reGrown.Top))
		record(math.abs(gone.Top - before.Top) < 0.5 and gone.Count == before.Count,
			"and DESTROYING a registered control releases it -- no stale rectangle"
			.. " survives the instance",
			string.format("top %.0f (was %.0f), count %s (was %s)",
				gone.Top, before.Top, tostring(gone.Count), tostring(before.Count)))
		record(fires - baseline >= 2, "...with a Changed fire on each edge",
			string.format("%d fire(s)", fires - baseline))

		-- ------------------------------------------------------------------
		-- A SCREEN-OWNING MODAL EMPTIES ALL THREE MOVEMENT ZONES -- and this is
		-- the row that licenses that. C_NO_CONTROLS_IS_NOT_A_PROXY_20260831
		-- makes Controls, Jump and Thumbstick zero-area while a modal is open,
		-- which makes "the modal does not overlap a movement control" trivially
		-- true. That is only honest if the modal REALLY suppresses movement, so
		-- that is what is measured here: the flag UIDevice publishes when it has
		-- actually disabled the engine's ControlModule, not the modal attribute
		-- that asked it to.
		-- ------------------------------------------------------------------
		do
			local zonesBefore = UIDevice.Layout().Zones
			local flashlightGui = findGui("FlashlightPopup")
			local flashlightTarget = flashlightGui
				and flashlightGui:FindFirstChild("TouchFlashlightToggle", true)
			local flashlightBeforeVisible = flashlightTarget
				and (flashlightTarget :: GuiObject).Visible or false
			local flashlightBeforeActive = flashlightTarget
				and (flashlightTarget :: GuiObject).Active or false
			record(flashlightTarget ~= nil and flashlightBeforeVisible and flashlightBeforeActive,
				"before the queue opens, the flashlight's real child hit target is live",
				string.format("exists=%s visible=%s active=%s", tostring(flashlightTarget ~= nil),
					tostring(flashlightBeforeVisible), tostring(flashlightBeforeActive)))
			record(zonesBefore.Thumbstick.Right > zonesBefore.Thumbstick.Left,
				"with no modal open the thumbstick region is a real rectangle",
				string.format("%.0f wide", zonesBefore.Thumbstick.Right - zonesBefore.Thumbstick.Left))
			-- DRIVEN THROUGH PRODUCTION'S OWN CHOKE POINT, not by writing the
			-- attribute. RoundUI derives QueueModalOpen -- and now the movement
			-- suppression with it -- from one property, `QueueHostShade.Visible`,
			-- precisely so that no path can set the flag without the behaviour.
			-- Setting the attribute by hand bypasses exactly the wiring under
			-- test and reported "suppressed=false" for a modal production had
			-- never been told about.
			local roundGui = findGui("RoundGui")
			local shade = roundGui and roundGui:FindFirstChild("QueueHostShade")
			record(shade ~= nil, "the party dialog's shade is reachable to drive",
				roundGui and "no QueueHostShade" or "no RoundGui")
			if shade then (shade :: GuiObject).Visible = true end
			task.wait(0.35)
			record(UIDevice.TouchMovementSuppressed() == true,
				"a screen-owning modal really does stand the engine's movement"
				.. " controls down -- this is what licenses the empty zones",
				tostring(UIDevice.TouchMovementSuppressed()))
			record(flashlightTarget ~= nil
				and not (flashlightTarget :: GuiObject).Visible
				and not (flashlightTarget :: GuiObject).Active,
				"opening QueueHostShade stands down the flashlight's actual child hit target",
				flashlightTarget and string.format("visible=%s active=%s",
					tostring((flashlightTarget :: GuiObject).Visible),
					tostring((flashlightTarget :: GuiObject).Active)) or "missing")
			local zonesDuring = UIDevice.Layout().Zones
			local function empty(zone): boolean
				return zone.Right - zone.Left < 1 and zone.Bottom - zone.Top < 1
			end
			record(empty(zonesDuring.Thumbstick) and empty(zonesDuring.Jump)
				and empty(zonesDuring.Controls),
				"...and all three movement zones are empty while it is open,"
				.. " because the controls they describe are not on screen",
				string.format("thumbstick %.0fx%.0f jump %.0fx%.0f controls %.0fx%.0f",
					zonesDuring.Thumbstick.Right - zonesDuring.Thumbstick.Left,
					zonesDuring.Thumbstick.Bottom - zonesDuring.Thumbstick.Top,
					zonesDuring.Jump.Right - zonesDuring.Jump.Left,
					zonesDuring.Jump.Bottom - zonesDuring.Jump.Top,
					zonesDuring.Controls.Right - zonesDuring.Controls.Left,
					zonesDuring.Controls.Bottom - zonesDuring.Controls.Top))
			if shade then (shade :: GuiObject).Visible = false end
			task.wait(0.35)
			record(UIDevice.TouchMovementSuppressed() == false,
				"...and closing it gives movement back -- a modal that took the"
				.. " controls away and kept them is the worse bug",
				tostring(UIDevice.TouchMovementSuppressed()))
			record(flashlightTarget ~= nil
				and (flashlightTarget :: GuiObject).Visible == flashlightBeforeVisible
				and (flashlightTarget :: GuiObject).Active == flashlightBeforeActive,
				"closing the queue restores that same flashlight hit target",
				flashlightTarget and string.format("visible=%s/%s active=%s/%s",
					tostring((flashlightTarget :: GuiObject).Visible), tostring(flashlightBeforeVisible),
					tostring((flashlightTarget :: GuiObject).Active), tostring(flashlightBeforeActive)) or "missing")
			local zonesAfter = UIDevice.Layout().Zones
			local function sameZone(after, before): boolean
				return math.abs(after.Left - before.Left) < 1
					and math.abs(after.Top - before.Top) < 1
					and math.abs(after.Right - before.Right) < 1
					and math.abs(after.Bottom - before.Bottom) < 1
			end
			record(sameZone(zonesAfter.Thumbstick, zonesBefore.Thumbstick)
				and sameZone(zonesAfter.Jump, zonesBefore.Jump)
				and sameZone(zonesAfter.Controls, zonesBefore.Controls)
				and zonesAfter.Jump.Size == zonesBefore.Jump.Size
				and zonesAfter.Controls.Measured == zonesBefore.Controls.Measured
				and zonesAfter.Controls.Count == zonesBefore.Controls.Count,
				"...and the zones come back to exactly what they were",
				string.format("thumb R %.0f/%.0f, jump size %.0f/%.0f, controls T %.0f/%.0f measured %s/%s count %s/%s",
					zonesAfter.Thumbstick.Right, zonesBefore.Thumbstick.Right,
					zonesAfter.Jump.Size, zonesBefore.Jump.Size,
					zonesAfter.Controls.Top, zonesBefore.Controls.Top,
					tostring(zonesAfter.Controls.Measured), tostring(zonesBefore.Controls.Measured),
					tostring(zonesAfter.Controls.Count), tostring(zonesBefore.Controls.Count)))
		end

		-- HIDING is the other way a control leaves the union, and it is the one
		-- production itself uses (SetInteractive out of round, a disabled gui).
		-- The COUNT is what this row can claim: the cluster relayouts on the same
		-- Changed, so what the union settles at afterwards is production's answer,
		-- not the hide's.
		baseline = fires
		local victim = drawn[1]
		local wasVisible = victim.Visible
		victim.Visible = false
		task.wait(0.45)
		local hiddenFires = fires - baseline
		victim.Visible = wasVisible
		task.wait(0.45)
		record(hiddenFires >= 1,
			"hiding a registered control invalidates the zone rather than leaving a"
			.. " cached rectangle behind",
			string.format("%d fire(s) while %s was hidden", hiddenFires, victim.Name))
		record(math.abs(zone().Top - before.Top) < 0.5 and zone().Count == before.Count,
			"...and showing it again settles back on the same rectangle",
			string.format("top %.0f (was %.0f), count %s (was %s)",
				zone().Top, before.Top, tostring(zone().Count), tostring(before.Count)))

		connection:Disconnect()
	end)

	if probeControl then pcall(function() probeControl:Destroy() end) end
	player:SetAttribute("InRound", nil)
	pcall(resetScenario)
	task.wait(0.15)
	Fit.restore(saved)
	task.wait(0.2)
	if not ran then
		state.Failures += 1
		state.Checks += 1
		state.note("  FAIL the control zone matrix ran  (" .. tostring(runError) .. ")")
	end
	local residue, residueNote = Fit.residue(saved)
	if residueNote then state.note(residueNote) end
	record(#residue == 0,
		"the matrix restored every borrowed attribute, gui state and caption",
		table.concat(residue, "; "))
	return state.finish()
end

function UIRegression.ControlZoneMatrix(token: string?): (string, number)
	return Fit.lane("ControlZoneMatrix", token, Fit.bodyControlZoneMatrix)
end

-- ---------------------------------------------------------------------------
-- HarnessLockMatrix
-- ---------------------------------------------------------------------------

-- C_LOCK_IS_TESTED_20260831.
--
-- The lock was rebuilt twice this session on reasoning alone. Reasoning is how
-- it got the two defects it had: a fresh claim that incremented a stale depth,
-- and a publish nothing verified. So it gets a lane.
--
-- THE AWKWARD PART, stated plainly: this lane runs INSIDE Fit.lane, which is
-- holding the very lock under test. It therefore stands the real record aside
-- (Fit.lockSnapshot) before its first experiment and puts it back exactly
-- (Fit.lockRestore) before it returns, so the run that contains it still owns
-- what it thinks it owns and its own release still works. Every experiment
-- below happens between those two points, and the last checks confirm the
-- restore was exact rather than assuming it.
function Fit.bodyHarnessLockMatrix(): (string, number)
	local state = Fit.recorder("=== harness lock: contention, identity, abandonment ===")
	local record = state.record
	local outer = Fit.lockSnapshot()

	local ran, runError = pcall(function()
		-- ---------------------------------------------------------------
		-- SIMULTANEOUS CLAIM
		-- ---------------------------------------------------------------
		-- Two acquisitions raced from this VM. They cannot literally run on
		-- two threads at once in Luau, but the verification window makes the
		-- race real anyway: each publishes, then YIELDS for the window, so the
		-- second one's publish lands inside the first one's window and exactly
		-- the interleaving the protocol exists to survive is what happens.
		Fit.lockPublish(nil, nil, nil)
		Fit.lockSetLocal(nil, nil, 0)
		local results = {}
		local finished = 0
		for index = 1, 2 do
			task.spawn(function()
				local ok, why, lease = Fit.acquire("RaceClaimant" .. index)
				results[index] = {Ok = ok, Why = why, Lease = lease}
				finished += 1
			end)
		end
		local deadline = 60
		while finished < 2 and deadline > 0 do
			task.wait(0.05)
			deadline -= 1
		end
		local winners = 0
		local refusal = nil
		for index = 1, 2 do
			local outcome = results[index]
			if outcome and outcome.Ok then winners += 1
			elseif outcome then refusal = outcome.Why end
		end
		record(finished == 2, "both racing claimants finished",
			string.format("%d of 2", finished))
		record(winners == 1, "exactly ONE of two simultaneous claims is admitted",
			string.format("%d admitted", winners))
		record(refusal ~= nil and refusal ~= "",
			"...and the loser is refused with a reason, not silently",
			tostring(refusal))
		local heldToken, heldLane = Fit.lockHolder()
		record(heldToken ~= nil and heldLane:match("^RaceClaimant") ~= nil,
			"...and the winner's published record survived the race intact",
			string.format("%s / %s", tostring(heldLane), tostring(heldToken)))

		-- The winner's lease, for the release tests below.
		local winnerLease = nil
		for index = 1, 2 do
			if results[index] and results[index].Ok then winnerLease = results[index].Lease end
		end

		-- ---------------------------------------------------------------
		-- RE-ENTRY BY IDENTITY, NOT BY NAME
		-- ---------------------------------------------------------------
		local sameToken = heldToken
		local reOk = Fit.acquire(tostring(heldLane), sameToken)
		record(reOk == true, "the SAME token re-enters the lock it holds", "refused")
		if reOk then Fit.release({Token = sameToken, Released = false}) end
		-- The hole this closes: admission used to be granted to anything whose
		-- lane name read "RunAll". A different token presenting the same NAME
		-- is a different run and must queue.
		local nameOk, nameWhy = Fit.acquire(tostring(heldLane), "a-different-token")
		record(nameOk == false,
			"a DIFFERENT token presenting the same lane name is refused --"
			.. " admission is by identity, never by name",
			nameOk and "admitted" or tostring(nameWhy):sub(1, 90))

		-- ---------------------------------------------------------------
		-- OWNER-ONLY RELEASE
		-- ---------------------------------------------------------------
		local depthBefore = Fit.lockLocalDepth()
		Fit.release({Token = "not-the-owners-token", Released = false})
		local stillHeld = Fit.lockHolder()
		record(stillHeld == heldToken and Fit.lockLocalDepth() == depthBefore,
			"a release presenting a FOREIGN token clears nothing and decrements"
			.. " nothing",
			string.format("holder %s, depth %d", tostring(stillHeld), Fit.lockLocalDepth()))
		Fit.release(winnerLease)
		record(Fit.lockHolder() == nil and Fit.lockLocalDepth() == 0,
			"...and the real owner's single release clears it completely",
			string.format("holder %s, depth %d",
				tostring(Fit.lockHolder()), Fit.lockLocalDepth()))

		-- ---------------------------------------------------------------
		-- ABANDONMENT TAKEOVER
		-- ---------------------------------------------------------------
		Fit.takeStolenNote()
		Fit.lockPublish("ghost#0@0", "GhostRun", os.time() - (LOCK_ABANDONED_AFTER + 30))
		Fit.lockSetLocal(nil, nil, 0)
		local tookOver, takeWhy, takeLease = Fit.acquire("TakeoverClaimant")
		record(tookOver == true,
			"a holder that has not beaten inside the abandonment window is taken over",
			tostring(takeWhy))
		local note = Fit.takeStolenNote()
		record(note ~= nil and note:find("GhostRun", 1, true) ~= nil,
			"...and the takeover is REPORTED, naming what it took the lock from,"
			.. " never silently",
			tostring(note))
		if takeLease then Fit.release(takeLease) end

		-- ...and a holder that IS beating is not taken over.
		Fit.lockPublish("live#0@0", "LiveRun", os.time())
		Fit.lockSetLocal(nil, nil, 0)
		local barged, bargeWhy = Fit.acquire("ImpatientClaimant")
		record(barged == false,
			"a holder that IS beating is not taken over, however long it has run",
			barged and "admitted" or tostring(bargeWhy):sub(1, 90))
		Fit.lockPublish(nil, nil, nil)

		-- ---------------------------------------------------------------
		-- STALE LOCAL DEPTH RECOVERY
		-- ---------------------------------------------------------------
		-- The exact shape of the defect: this VM believes it is one frame deep
		-- in a lock that has since been taken away from it. The fresh claim
		-- must start from zero, so that ONE release empties it.
		Fit.lockSetLocal("a-token-that-was-taken", "AbandonedRun", 1)
		Fit.lockPublish(nil, nil, nil)
		Fit.takeStolenNote()
		local recovered, recoveredWhy, recoveredLease = Fit.acquire("RecoveryClaimant")
		record(recovered == true, "a VM with a stale local depth can still claim",
			tostring(recoveredWhy))
		record(Fit.lockLocalDepth() == 1,
			"...and the claim installs depth 1, not 2 -- the stale belief is"
			.. " discarded, not stacked on",
			string.format("depth %d", Fit.lockLocalDepth()))
		local retakeNote = Fit.takeStolenNote()
		record(retakeNote ~= nil and retakeNote:find("RE-TAKE", 1, true) ~= nil,
			"...and the stale belief is reported rather than swallowed",
			tostring(retakeNote))
		if recoveredLease then Fit.release(recoveredLease) end
		record(Fit.lockHolder() == nil and Fit.lockLocalDepth() == 0,
			"...so ONE release empties the lock completely",
			string.format("holder %s, depth %d",
				tostring(Fit.lockHolder()), Fit.lockLocalDepth()))
	end)

	-- THE REAL LOCK, back exactly as it was, before anything else can observe it.
	Fit.lockRestore(outer)
	if not ran then
		state.Failures += 1
		state.Checks += 1
		state.note("  FAIL the harness lock matrix ran  (" .. tostring(runError) .. ")")
	end
	local restored = Fit.lockSnapshot()
	record(restored.Token == outer.Token and restored.Lane == outer.Lane
		and restored.LocalToken == outer.LocalToken
		and restored.LocalDepth == outer.LocalDepth,
		"and the lane put the run's own lock back exactly as it found it",
		string.format("published %s/%s local %s depth %s",
			tostring(restored.Token), tostring(restored.Lane),
			tostring(restored.LocalToken), tostring(restored.LocalDepth)))
	return state.finish()
end

function UIRegression.HarnessLockMatrix(token: string?): (string, number)
	return Fit.lane("HarnessLockMatrix", token, Fit.bodyHarnessLockMatrix)
end

-- ---------------------------------------------------------------------------
-- ExclusionTimingMatrix
-- ---------------------------------------------------------------------------

-- C_SAME_FRAME_EXCLUSION_20260831.
--
-- The Level 3 reader used to consume its gating states only from a 0.10s
-- RenderStepped accumulator, so for up to 100ms after a dispatch, the Zyntra
-- terminal, the queue modal or a Level 3 hide turned on, ReaderPanel or
-- ReaderRestore was still Visible AND Active on top of it -- a live >= 44x44
-- target in the upper-right corner, which is exactly where a modal's own
-- dismiss lives. The reader now subscribes to each of those attributes and to
-- UIDevice's screen-owning-modal signal and updates immediately, keeping the
-- tick only as a fallback.
--
-- WHAT "IMMEDIATE" CAN HONESTLY MEAN HERE, measured rather than assumed.
-- Roblox fires GetAttributeChangedSignal DEFERRED, so a handler does not run
-- inside the SetAttribute call: reading the reader on the very next line still
-- shows it up, and no amount of production work can change that. Measured
-- directly in the running place:
--     write the gate, read immediately  -> active=false, ReaderPanel=true/true
--     write the gate, wait 1 heartbeat  -> ReaderPanel=false/false
-- across all four gates and six trials each, the worst case was ONE heartbeat,
-- every time.
--
-- So the claim this lane proves is the one that is true and the one that
-- matters: the reader is down within a single heartbeat of the gate closing,
-- CONSISTENTLY. That is what distinguishes it from the 0.10s fallback tick --
-- if the tick were what took the reader down, the latency would scatter across
-- the whole interval and some trial in a run of six would land past two
-- heartbeats. It never does. An `active=false` reader still drawn after two
-- heartbeats is the original defect and fails here.
--
-- ALSO NON-DESTRUCTIVE DISPATCH: the last block proves a mutating lane refuses
-- while a real briefing is live, and proves it WITHOUT ending one -- by making
-- the harness's own real-dispatch predicate true for an instant and checking
-- what a lane does with it.
function Fit.bodyExclusionTimingMatrix(): (string, number)
	local state = Fit.recorder("=== same-frame exclusion, and the dispatch guard ===")
	local record = state.record
	local saved = Fit.borrow()
	local player = Players.LocalPlayer

	local ran, runError = pcall(function()
		local reader = findGui("Level3ReaderGui")
		local probe = reader and reader:FindFirstChild("UIRegressionReaderProbe")
		if not (probe and probe:IsA("BindableFunction")) then
			record(false, "the Level 3 reader publishes its visibility probe",
				reader and "no UIRegressionReaderProbe" or "no Level3ReaderGui")
			return
		end
		local function look(): string
			local ok, answer = pcall(function() return probe:Invoke("visibility") end)
			return ok and tostring(answer) or ("visibility:error " .. tostring(answer))
		end
		local function field(answer: string, name: string): string
			return answer:match(name .. "=([^%s]+)") or "?"
		end
		local function down(answer: string): boolean
			return field(answer, "ReaderPanel") == "false/false"
				and field(answer, "ReaderRestore") == "false/false"
		end

		-- Put the reader ON, on touch, so there is something to take away.
		resetScenario(true)
		-- EXPLICITLY, after resetScenario: the first run of this lane measured
		-- inround=false and every row failed for a reader that was never up.
		Players.LocalPlayer:SetAttribute("InRound", true)
		workspace:SetAttribute("ForceTouchUI", true)
		workspace:SetAttribute("SelectedLevel", 3)
		player:SetAttribute("UIRegressionForceLevel3Reader", true)
		if reader then (reader :: ScreenGui).Enabled = true end
		task.wait(0.4)
		local up = look()
		record(field(up, "active") == "true",
			"the reader is active before each gate is applied", up)

		-- Fetched here rather than at file scope: this chunk is close to Luau's
		-- 200-local ceiling and one lane does not warrant a top-level name.
		local RunService = game:GetService("RunService")
		local TRIALS = 6
		local HEARTBEAT_BOUND = 2
		for _, gate in ipairs({
			{Name = "a dispatch briefing", Attribute = "ZyntraDispatchClientActive"},
			{Name = "the Zyntra terminal", Attribute = "ZyntraStoreOpen"},
			{Name = "the queue modal", Attribute = "QueueModalOpen"},
			{Name = "Level 3 hiding", Attribute = "Level3_Hiding"},
			{Name = "the dev phone", Attribute = "DevPhoneOpen"},
		}) do
			local worst, everUp, recovered = -1, false, false
			for _ = 1, TRIALS do
				-- The reader back up first, and settled, so each trial is measured
				-- from the same starting point and not from the previous one's
				-- wreckage. This wait is OUTSIDE the measurement.
				player:SetAttribute(gate.Attribute, nil)
				task.wait(0.25)
				if field(look(), "ReaderPanel") ~= "false/false"
					or field(look(), "ReaderRestore") ~= "false/false" then
					everUp = true
				end
				player:SetAttribute(gate.Attribute, true)
				-- Count HEARTBEATS, not seconds. A wall-clock bound would be a
				-- claim about this machine's frame rate; a heartbeat count is a
				-- claim about the code.
				local beats = 0
				while not down(look()) and beats < 40 do
					RunService.Heartbeat:Wait()
					beats += 1
				end
				worst = math.max(worst, beats)
				player:SetAttribute(gate.Attribute, nil)
				task.wait(0.25)
				if field(look(), "active") == "true" then recovered = true end
			end
			record(everUp,
				gate.Name .. ": the reader was on screen before the gate closed --"
				.. " otherwise these rows prove nothing", "never up")
			record(worst >= 0 and worst <= HEARTBEAT_BOUND,
				string.format("%s: takes the reader down within %d heartbeat(s), in"
					.. " EVERY one of %d trials -- the 0.10s fallback tick cannot"
					.. " produce that, it would scatter across its whole interval",
					gate.Name, HEARTBEAT_BOUND, TRIALS),
				string.format("worst case %d heartbeat(s)", worst))
			record(recovered,
				gate.Name .. ": ...and the reader recovers when it clears",
				look())
		end

		-- DESKTOP still draws nothing when hidden, and R remains the only way back.
		workspace:SetAttribute("ForceTouchUI", false)
		task.wait(0.35)
		local pointer = look()
		record(field(pointer, "touch") == "false",
			"the pointer pass really is a pointer device", pointer)
		record(field(pointer, "ReaderRestore") == "false/false",
			"desktop draws no restore chip and leaves nothing in the input stack",
			pointer)
		workspace:SetAttribute("ForceTouchUI", true)

		-- ------------------------------------------------------------------
		-- C_GUARD_IS_PROVED_WITHOUT_A_VICTIM_20260831
		-- ------------------------------------------------------------------
		-- The guard's whole purpose is that a lane will not talk over a real
		-- transmission. Proving it needs the predicate to answer true, and the
		-- two ways to do that with real state are both wrong: starting a real
		-- briefing means waiting a minute for one and then interrupting it, and
		-- writing DispatchBriefingOpen by hand does not survive -- RoundUI
		-- republishes that attribute from the cue it is actually playing and
		-- clears it within a frame. Measured: set true, read back false 0.1s
		-- later, which is exactly how the first version of this proof failed.
		--
		-- So the PREDICATE is overridden, not the game. Nothing on screen moves,
		-- no briefing is started and none is ended; the guard is asked the
		-- question it exists to answer and its behaviour is measured.
		local savedWait = Fit.LiveDispatchWait
		Fit.LiveDispatchWait = 1
		Fit.PretendDispatchLive = true
		record(Fit.realDispatchLive() == true,
			"with a live briefing, the harness says so",
			tostring(Fit.realDispatchLive()))
		-- The screen, before the refusal, so the lane can be shown to have left
		-- it alone.
		local terminalBefore = tostring(player:GetAttribute("ZyntraStoreOpen"))
		local viewportBefore = tostring(workspace:GetAttribute("UIRegressionViewport"))
		local touchBefore = tostring(workspace:GetAttribute("ForceTouchUI"))
		-- The GUARD itself, not a lane: calling a lane from in here would be
		-- refused by the LOCK first (this matrix is inside a RunAll that holds
		-- it) and the row would pass for the wrong reason -- which is what the
		-- first version of this proof actually measured.
		local waited, waitWhy = Fit.awaitQuietDispatch()
		record(waited == false and waitWhy ~= nil
			and tostring(waitWhy):find("real dispatch briefing", 1, true) ~= nil,
			"...and the guard every mutating lane calls REFUSES, naming the reason",
			tostring(waitWhy):sub(1, 120))
		record(tostring(player:GetAttribute("ZyntraStoreOpen")) == terminalBefore
			and tostring(workspace:GetAttribute("UIRegressionViewport")) == viewportBefore
			and tostring(workspace:GetAttribute("ForceTouchUI")) == touchBefore,
			"...and the refusing path borrowed, forced and mutated nothing",
			string.format("terminal %s -> %s, viewport %s -> %s, touch %s -> %s",
				terminalBefore, tostring(player:GetAttribute("ZyntraStoreOpen")),
				viewportBefore, tostring(workspace:GetAttribute("UIRegressionViewport")),
				touchBefore, tostring(workspace:GetAttribute("ForceTouchUI"))))
		-- And resetScenario -- the one thing in the harness that could end a
		-- transmission -- declines to silence it while the predicate is true.
		player:SetAttribute("UIRegressionSilenceDispatch", nil)
		resetScenario()
		record(player:GetAttribute("UIRegressionSilenceDispatch") ~= true,
			"...and resetScenario does NOT silence a briefing it did not raise",
			tostring(player:GetAttribute("UIRegressionSilenceDispatch")))
		Fit.PretendDispatchLive = false
		Fit.LiveDispatchWait = savedWait
		record(Fit.realDispatchLive() == false,
			"and the override is released, so the guard is live again",
			tostring(Fit.realDispatchLive()))
	end)

	-- RELEASED ON EVERY EXIT. A matrix that errored with this still true would
	-- make every later lane in the session refuse for a briefing that never
	-- existed.
	Fit.PretendDispatchLive = false
	player:SetAttribute("UIRegressionForceLevel3Reader", nil)
	pcall(resetScenario)
	task.wait(0.15)
	Fit.restore(saved)
	task.wait(0.2)
	if not ran then
		state.Failures += 1
		state.Checks += 1
		state.note("  FAIL the exclusion timing matrix ran  (" .. tostring(runError) .. ")")
	end
	local residue, residueNote = Fit.residue(saved)
	if residueNote then state.note(residueNote) end
	record(#residue == 0,
		"the matrix restored every borrowed attribute, gui state and caption",
		table.concat(residue, "; "))
	return state.finish()
end

function UIRegression.ExclusionTimingMatrix(token: string?): (string, number)
	return Fit.lane("ExclusionTimingMatrix", token, Fit.bodyExclusionTimingMatrix)
end

-- COMPOSES THE OTHER LANES, and hands each of them its own lease token so they
-- re-enter the lock it is already holding. Re-entry used to be granted to any
-- caller whose owner string read "RunAll", which meant a lane fired by hand from
-- a second console was admitted into the middle of a run on the strength of a
-- name it never had to prove.
-- C_RUNALL_OWNS_ITS_OUTER_STATE_20260831 -- WHAT SHIPPED BROKEN.
--
-- Every LANE borrowed and restored. RunAll did not: it waited for a quiet
-- dispatch once, then drove 21 scenarios directly -- resetScenario, forced
-- attributes, revealed guis -- with no snapshot of its own. Two consequences.
-- The scenario sweep could leave the player on a different Zyntra tab, with
-- different canvas positions and a different reader state, and nothing checked;
-- and a briefing that STARTED mid-run met a sweep that carried on mutating
-- through it.
--
-- So the whole of RunAll now sits inside one outer borrow/restore, its residue
-- is asserted like any lane's, and the sweep re-checks for a live briefing
-- between scenarios and unwinds if one appears. A truncated honest run is worth
-- more than a complete dishonest one.
function Fit.bodyRunAll(lease): (string, number)
	-- UIRegressionViewport makes UIDevice REPORT a simulated size, but Studio
	-- still renders at the real one. Every assertion below compares measured
	-- AbsolutePosition against the reported viewport, so with the override
	-- active they would all compare real pixels against a fictional screen and
	-- fail meaninglessly. CompletionFit owns that override and resolves UDim2
	-- values arithmetically instead; this matrix needs the Device Simulator.
	if workspace:GetAttribute("UIRegressionViewport") ~= nil then
		return "UIRegressionViewport is set: clear it before running the scenario"
			.. " matrix, or call UIRegression.CompletionFit(), which owns it.", 1
	end
	local layout = UIDevice.Layout()
	local report = {string.format("=== %.0fx%.0f  class=%s  portrait=%s  touch=%s ===",
		layout.Width, layout.Height, layout.Class,
		tostring(layout.Portrait), tostring(layout.IsTouch))}
	local stolen = Fit.takeStolenNote()
	if stolen then table.insert(report, "  note " .. stolen) end
	local failures = 0
	-- (b) AWAIT ITS NATURAL END, BOUNDED, and once, HERE. The scenario sweep below
	-- opens with resetScenario, which silences a live transmission; waiting at the
	-- top means the nine lanes this composes each find the dispatch already quiet
	-- and wait for nothing.
	local quiet, dispatchWhy = Fit.awaitQuietDispatch()
	if not quiet then
		table.insert(report, "  FAIL " .. tostring(dispatchWhy))
		table.insert(report, "TOTAL: 0 scenarios, 1 failed")
		return table.concat(report, "\n"), 1
	end
	-- THE OUTER SNAPSHOT. Taken after the dispatch wait -- so it records a quiet
	-- screen rather than a briefing about to end on its own -- and before the
	-- first mutation. Every composed lane takes its own as well; this one covers
	-- the SCENARIO SWEEP, which had none at all.
	local outerSaved = Fit.borrow()
	-- Set the moment a real briefing is seen mid-run: the sweep stops mutating,
	-- the composed lanes are skipped, and the outer restore still runs.
	local abandoned: string? = nil
	local captures = {}
	local missing = UIRegression.MissingGuis()
	if #missing > 0 then
		failures += 1
		table.insert(report, "MISSING SCREENGUIS (a HUD script failed to start): "
			.. table.concat(missing, ", "))
	end
	for _, scenario in ipairs(UIRegression.Scenarios()) do
		-- BETWEEN SCENARIOS, not during one. A briefing that starts here is the
		-- game's; the sweep stops rather than talking over it.
		if abandoned == nil and Fit.realDispatchLive() then
			abandoned = string.format(
				"a real dispatch briefing started during the scenario sweep, at %q."
				.. " The run stopped mutating there and unwound: everything before it"
				.. " is reported, nothing after it was measured, and the briefing was"
				.. " left alone.", scenario.Name)
		end
		if abandoned ~= nil then continue end
		-- A touch-only scenario cannot be asserted on a pass that is not touch:
		-- its controls do not exist, so `Requires` fails for a reason that is not
		-- a defect. It is NOT dropped -- TouchTargetMatrix drives the same
		-- scenario with ForceTouchUI across six device sizes plus the real
		-- viewport, which is where its coverage actually lives.
		if scenario.TouchOnly and not UIDevice.IsTouch() then
			table.insert(report, string.format("%-28s skip  (touch-only; covered by TouchTargetMatrix)",
				scenario.Name))
			continue
		end
		scenario.Setup()
		task.wait(.3)
		-- The scenario sweep records nothing through Fit.recorder, so without an
		-- explicit beat here RunAll falls silent for the whole loop and a second
		-- VM becomes entitled to declare the longest-running lane in the suite
		-- abandoned while it is halfway through it.
		Fit.beat()
		local result = UIRegression.Check()
		-- A scenario that measured nothing is not a pass. The briefing panel can
		-- be hidden again by a stray refresh between setup and scan, and without
		-- this the report would say PASS for a screen with nothing on it.
		local function findRect(fragment)
			for _, rect in ipairs(result.Rects) do
				if rect.Path:find(fragment, 1, true) then return rect end
			end
			for _, group in ipairs(result.Groups) do
				if group.Path:find(fragment, 1, true) then return group end
				for _, child in ipairs(group.Children) do
					if child.Path:find(fragment, 1, true) then return child end
				end
			end
			return nil
		end
		local contractProblems = {}
		local required = scenario.Requires
		if type(required) == "string" then required = {required} end
		for _, fragment in ipairs(required or {}) do
			if not findRect(fragment) then
				table.insert(contractProblems, "VACUOUS: " .. fragment .. " was not measured")
			end
		end
		for _, fragment in ipairs(scenario.Forbids or {}) do
			if findRect(fragment) then
				table.insert(contractProblems, "STATE LEAK: " .. fragment .. " should be hidden")
			end
		end
		-- A control that is DRAWN but not PRESSABLE. `Active` was read in exactly
		-- one place -- touchTargetProblems, inside the touch-only branch below --
		-- so a button that never arms passed every desktop run by existing. The
		-- PARTY DOWN card's 0.6s arming delay is the case that needs saying out
		-- loud: it is the whole accidental-purchase guard, and a bug that leaves
		-- it stuck inert is a card the player cannot answer at all.
		for _, fragment in ipairs(scenario.RequiresActive or {}) do
			local rect = findRect(fragment)
			if not rect then
				table.insert(contractProblems, "INERT: " .. fragment .. " was not measured")
			elseif not rect.Active then
				table.insert(contractProblems, "INERT: " .. fragment .. " is drawn but not Active")
			end
		end
		if layout.IsTouch then
			-- This matrix runs at the REAL rendered viewport, so the geometry
			-- half of the check is meaningful here and is included.
			for _, fragment in ipairs(scenario.TouchTargets or {}) do
				local rect = findRect(fragment)
				if not rect then
					table.insert(contractProblems, "TOUCH TARGET: missing " .. fragment)
				else
					for _, problem in ipairs(touchTargetProblems(
						rect, result.Rects, layout.Viewport, true)) do
						table.insert(contractProblems,
							"TOUCH TARGET: " .. fragment .. " " .. problem)
					end
				end
			end
		end
		for _, fragment in ipairs(scenario.TextFitTargets or {}) do
			local rect = findRect(fragment)
			if not rect or not rect.TextBounds then
				table.insert(contractProblems, "TEXT FIT: missing measurable " .. fragment)
			else
				local width = rect.Right - rect.Left
				local height = rect.Bottom - rect.Top
				if rect.TextBounds.X > width + 1 or rect.TextBounds.Y > height + 1 then
					table.insert(contractProblems, string.format(
						"TEXT FIT: %s needs %.0fx%.0f inside %.0fx%.0f",
						fragment, rect.TextBounds.X, rect.TextBounds.Y, width, height))
				end
			end
		end
		if scenario.RoundEndingMode then
			local rect = findRect("RoundEnding")
			if rect then
				local width = rect.Right - rect.Left
				local height = rect.Bottom - rect.Top
				if scenario.RoundEndingMode == "compact" then
					if width >= result.Viewport.X * .95 or height >= result.Viewport.Y * .50 then
						table.insert(contractProblems, string.format(
							"RESULT SHAPE: win is not compact (%.0fx%.0f in %.0fx%.0f)",
							width, height, result.Viewport.X, result.Viewport.Y))
					end
				else
					-- IgnoreGuiInset full-screen GUIs begin one top inset above the
					-- content origin. Their bottom is displaced by the same amount;
					-- comparing to 0..Viewport falsely reports a cropped overlay.
					local expectedTop = -layout.Inset.Y
					local expectedBottom = result.Viewport.Y - layout.Inset.Y
					if math.abs(rect.Left) > 2 or math.abs(rect.Top - expectedTop) > 2
					or math.abs(rect.Right - result.Viewport.X) > 2
					or math.abs(rect.Bottom - expectedBottom) > 2 then
						table.insert(contractProblems, string.format(
							"RESULT SHAPE: loss is not full-screen ((%.0f,%.0f)-(%.0f,%.0f))",
							rect.Left, rect.Top, rect.Right, rect.Bottom))
					end
				end
			else
				table.insert(contractProblems, "RESULT SHAPE: RoundEnding was not measured")
			end
		end
		if scenario.Capture then
			local rect = findRect(scenario.Capture)
			if rect then captures[scenario.Name] = rect end
			if scenario.CompareWith then
				local prior = captures[scenario.CompareWith]
				if not rect or not prior then
					table.insert(contractProblems, "COMPARE: missing " .. scenario.Capture)
				elseif math.abs(rect.Left - prior.Left) > 1
					or math.abs(rect.Top - prior.Top) > 1
					or math.abs(rect.Right - prior.Right) > 1
					or math.abs(rect.Bottom - prior.Bottom) > 1 then
					table.insert(contractProblems,
						"COMPARE: ReaderToggle moved or resized between open and closed")
				end
			end
		end
		local passed = result.Passed and #contractProblems == 0
		if not passed then failures += 1 end
		-- The per-scenario PASS line is review material; the FAIL line is the
		-- finding. Compact keeps the findings.
		if passed then
			Fit.detail(report, string.format("%-28s PASS  rects=%d texts=%d",
				scenario.Name, result.RectCount, result.TextCount))
		else
			table.insert(report, string.format("%-28s FAIL  rects=%d texts=%d",
				scenario.Name, result.RectCount, result.TextCount))
		end
		for _, problem in ipairs(contractProblems) do
			table.insert(report, "     Contract: " .. problem)
		end
		for _, label in ipairs({"Offscreen", "Overlaps", "MovementZoneHits",
			"KeyboardBindings", "InternalOverlaps"}) do
			for _, problem in ipairs(result[label]) do
				table.insert(report, "     " .. label .. ": " .. problem)
			end
		end
		-- Measured child rectangles, printed pass or fail. A layout assertion
		-- that only speaks when it breaks cannot be reviewed, and these are the
		-- numbers the whole dispatch-overlap question turns on.
		for _, group in ipairs(result.Groups) do
			Fit.detail(report, string.format("     %s (%.0f,%.0f)-(%.0f,%.0f)",
				group.Path, group.Left, group.Top, group.Right, group.Bottom))
			for _, child in ipairs(group.Children) do
				Fit.detail(report, string.format("        %s (%.0f,%.0f)-(%.0f,%.0f)%s",
					child.Path, child.Left, child.Top, child.Right, child.Bottom,
					child.Interactive and " [tappable]" or ""))
			end
		end
	end
	resetScenario()
	-- THE COMPOSED LANES ARE SKIPPED once a real briefing has appeared. Each of
	-- them would wait for it and then refuse anyway; running eleven refusals is
	-- noise, and the honest answer is the one line below.
	if abandoned ~= nil then
		table.insert(report, "  note the composed lanes were not run: " .. abandoned)
	else
	-- FIRST, because it validates the layout INPUTS every other lane measures
	-- against. A safe rect that is wrong makes every rectangle below wrong in
	-- the same direction, which is how a whole suite reports green.
	local safeReport, safeFailures = UIRegression.SafeAreaMatrix(lease.Token)
	table.insert(report, safeReport)
	failures += safeFailures
	local completionReport, completionFailures = UIRegression.CompletionContract(lease.Token)
	table.insert(report, completionReport)
	failures += completionFailures
	local fitReport, fitFailures = UIRegression.CompletionFit(lease.Token)
	table.insert(report, fitReport)
	failures += fitFailures
	-- The queue modal owns the override itself and resolves rects
	-- arithmetically, so it can run from here without the guard above applying.
	-- Running it from RunAll is deliberate: a device matrix nobody calls is the
	-- same as no device matrix, and this one guards the shape that shipped
	-- broken on a real Galaxy A06.
	local modalReport, modalFailures = UIRegression.QueueModalMatrix(lease.Token)
	table.insert(report, modalReport)
	failures += modalFailures
	-- Same contract, same reason: BriefingFitMatrix owns the override too, and
	-- it is the only thing in this file that can say whether the dispatch copy
	-- fits its box on a viewport Studio is not currently rendering.
	local briefingReport, briefingFailures = UIRegression.BriefingFitMatrix(lease.Token)
	table.insert(report, briefingReport)
	failures += briefingFailures
	-- Last, because it is the only matrix that drives the queue modal open and
	-- shut: anything measured while it is running would be measuring this
	-- matrix's own state rather than the screen the player gets. It restores the
	-- shade, the dispatch force flag and both device overrides on every exit
	-- path, error included.
	local exclusionReport, exclusionFailures = UIRegression.BriefingExclusionMatrix(lease.Token)
	table.insert(report, exclusionReport)
	failures += exclusionFailures
	-- The three 20260830 matrices. Each owns the device overrides itself and
	-- restores them on every exit path, so they run from here like the others.
	-- Order matters only in that the terminal matrix opens and closes a modal:
	-- anything measured while it runs would be measuring this matrix's state
	-- rather than the screen a player gets, so it goes after the panels.
	local cornerReport, cornerFailures = UIRegression.ObjectiveCornerMatrix(lease.Token)
	table.insert(report, cornerReport)
	failures += cornerFailures
	local compactReport, compactFailures = UIRegression.DispatchCompactMatrix(lease.Token)
	table.insert(report, compactReport)
	failures += compactFailures
	local terminalReport, terminalFailures = UIRegression.ZyntraTerminalFitMatrix(lease.Token)
	table.insert(report, terminalReport)
	failures += terminalFailures
	-- The live cluster, last: it is the only lane that parents an instance into
	-- the HUD, and it runs at the REAL viewport rather than a fixture, so
	-- anything measured while it is up would be measuring it.
	local zoneReport, zoneFailures = UIRegression.ControlZoneMatrix(lease.Token)
	table.insert(report, zoneReport)
	failures += zoneFailures
	-- The lock's own lane goes LAST, because it stands the run's lock aside to
	-- test it and puts it back; nothing else should be measuring while it does.
	local timingReport, timingFailures = UIRegression.ExclusionTimingMatrix(lease.Token)
	table.insert(report, timingReport)
	failures += timingFailures
	local lockReport, lockFailures = UIRegression.HarnessLockMatrix(lease.Token)
	table.insert(report, lockReport)
	failures += lockFailures
	end
	-- THE OUTER RESTORE, on every path including the unwind, and then the
	-- residue is ASSERTED rather than assumed -- the exact terminal tab, every
	-- canvas position, every borrowed gui's Visible/Active, the borrowed
	-- attributes, the reader state and the caption.
	pcall(resetScenario)
	task.wait(0.15)
	Fit.restore(outerSaved)
	task.wait(0.2)
	local outerResidue, outerNote = Fit.residue(outerSaved)
	if outerNote then table.insert(report, "  note " .. outerNote) end
	if abandoned ~= nil then
		failures += 1
		table.insert(report, "  FAIL " .. abandoned)
	end
	-- MOVEMENT STATE is part of the outer contract too: a lane that opened a
	-- screen-owning modal and died would leave the engine's own controls stood
	-- down, and the player with no thumbstick.
	if UIDevice.TouchMovementSuppressed() then
		failures += 1
		table.insert(report, "  FAIL the run left touch movement suppressed --"
			.. " a modal took the controls away and did not give them back")
	end
	if #outerResidue > 0 then
		failures += 1
		table.insert(report, "  FAIL the whole run restored the state it borrowed"
			.. " before the scenario sweep  (" .. table.concat(outerResidue, "; ") .. ")")
	else
		table.insert(report, "  ok   the whole run restored the state it borrowed"
			.. " before the scenario sweep")
	end
	table.insert(report, string.format("TOTAL: %d scenarios, %d failed",
		#UIRegression.Scenarios(), failures))
	return table.concat(report, "\n"), failures
end

function UIRegression.RunAll(token: string?): (string, number)
	return Fit.lane("RunAll", token, Fit.bodyRunAll)
end

-- THE ONE CALL A STUDIO CALLER SHOULD MAKE. Same run, same checks, same
-- numbers; only the passing lines are left out. The per-lane TOTAL lines survive
-- (they are what "per-matrix check and failure counts" means), as does every
-- note and skip.
function UIRegression.RunAllCompact(token: string?): (string, number)
	return Fit.compactly(function()
		return UIRegression.RunAll(token)
	end)
end

-- C_BOUNDED_SUMMARY_20260831.
--
-- Even compact, a full run's report is tens of KB, and it has to cross Studio's
-- execute_luau boundary to be read. That boundary is where a completed run has
-- twice looked like a hung one. So the SUMMARY is what a remote caller asks for:
-- the per-lane counts, the totals, and the failures in full -- never the passes.
--
-- Bounded on purpose. `limit` is a hard ceiling on the returned string; if the
-- failures do not fit, the summary says how many were dropped rather than
-- silently truncating, because a report that hides findings to fit is the exact
-- failure mode this whole session has been chasing.
function UIRegression.Summarise(report: string, failures: number, limit: number?): string
	local ceiling = limit or 5000
	local lanes, findings, notes = {}, {}, {}
	local header = nil
	local totalChecks, scenarios = 0, nil
	for line in report:gmatch("[^\n]+") do
		local checks, failed = line:match("^TOTAL: (%d+) checks, (%d+) failed")
		if checks then
			totalChecks += tonumber(checks) :: number
			table.insert(lanes, string.format("%-52s %4d checks %3d failed",
				(header or "(unnamed lane)"):sub(1, 52), tonumber(checks), tonumber(failed)))
			header = nil
		else
			local scenarioCount, scenarioFailed = line:match("^TOTAL: (%d+) scenarios, (%d+) failed")
			if scenarioCount then
				scenarios = string.format("%s scenarios, %s failed", scenarioCount, scenarioFailed)
			elseif line:match("^===") then
				header = line:gsub("^=+%s*", ""):gsub("%s*=+$", "")
			elseif line:match("^COMPLETION: (%d+) failed") or line:match("^FIT: (%d+) failed") then
				local kind, count = line:match("^(%a+): (%d+) failed")
				table.insert(lanes, string.format("%-52s        %3d failed",
					(header or kind):sub(1, 52), tonumber(count)))
				header = nil
			elseif line:match("FAIL") or line:match("^%s*skip") or line:match("skip  ") then
				table.insert(findings, line)
			elseif line:match("^%s*note ") then
				table.insert(notes, line)
			end
		end
	end
	local out = {string.format("checks=%d failures=%s scenarios=%s",
		totalChecks, tostring(failures), tostring(scenarios))}
	for _, lane in ipairs(lanes) do table.insert(out, lane) end
	for _, note in ipairs(notes) do table.insert(out, note) end
	local kept = 0
	for _, finding in ipairs(findings) do
		local candidate = #table.concat(out, "\n") + #finding + 1
		if candidate > ceiling then break end
		table.insert(out, finding)
		kept += 1
	end
	if kept < #findings then
		table.insert(out, string.format("... %d further failure line(s) did not fit in %d"
			.. " characters -- raise the limit or run the lane on its own",
			#findings - kept, ceiling))
	end
	return table.concat(out, "\n")
end

-- The whole run, reduced to something that fits through the MCP boundary, plus
-- the one thing a caller cannot see from the numbers: whether the harness lock
-- was left clean.
function UIRegression.RunAllSummary(limit: number?): (string, number)
	local report, failures = UIRegression.RunAllCompact()
	local held, lane, beat = Fit.lockHolder()
	local lockLine = held == nil
		and "lock: clear"
		or string.format("lock: STILL HELD by %s (%s), last beat %ds ago",
			tostring(lane), tostring(held), os.time() - beat)
	return UIRegression.Summarise(report, failures, limit) .. "\n" .. lockLine, failures
end

-- Any single lane, compactly. `UIRegression.Compact("ZyntraTerminalFitMatrix")`.
function UIRegression.Compact(lane: string, token: string?): (string, number)
	local entry = (UIRegression :: any)[lane]
	if type(entry) ~= "function" then
		return string.format("=== %s ===\n  FAIL there is no lane called %q\n"
			.. "TOTAL: 1 checks, 1 failed", tostring(lane), tostring(lane)), 1
	end
	return Fit.compactly(function()
		return entry(token)
	end)
end

return UIRegression
