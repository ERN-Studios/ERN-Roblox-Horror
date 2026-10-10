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
-- Retained analytical text helper. GetTextBoundsAsync can ask what
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
	ProtectionUse = true,
	-- HUD_B2_TOUCH (owner, 2026-10-08): the eighth cell of UIDevice's 4 + 4 grid.
	-- POTION, MARKER and SCAN left the cluster for the KIT fan, which is not
	-- listed: the fan is transient, never registered, and has to clear the
	-- movement zones like any other panel (KitFanMatrix holds it to that).
	KitToggle = true,
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
	-- HUD_B3 (owner, 2026-10-08): Round HUD's chase edge, the four static Coral
	-- bands in RoundHudThreat (order 20) while BeingChased. Same idea as the two
	-- above: MEANT to sit over every rect near a screen edge, and at 0.146 of the
	-- width / 0.185 of the height too shallow for the 92 % rule (B3 critic K6).
	ChaseEdgeLeft = true,
	ChaseEdgeRight = true,
	ChaseEdgeTop = true,
	ChaseEdgeBottom = true,
	-- Modal panels own the screen while they are open, and the movement cluster
	-- hides underneath them. WindowHolder is the L4 windows' (the shop, with
	-- RECORDS and SETTINGS since 2026-10-07, the dev menu, Daily Rewards); the
	-- Zyntra terminal that was listed here is deleted.
	WindowHolder = true,
	ReentryPanel = true,
	-- The result screen's accent wash. Full-bleed by design, and named after the
	-- instance rather than after the variable that used to be listed here.
	SignalFlash = true,
	Bracket1 = true, Bracket2 = true, Bracket3 = true, Bracket4 = true,
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
	ResultsWindow = true,
	ObjectiveCard = true,
	RoundExitCard = true,
	Keypad = true,
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
		and (object :: any).TextTransparency < 1 and (object :: any).Text ~= "" then return false end
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
		if (object :: any).TextTransparency < 1 and (object :: any).Text ~= "" then return false end
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

-- A transparent, non-interactive TextLabel draws its measured ink, not the
-- empty padding of its authored box. Buttons, backgrounds and stroked surfaces
-- retain their full bounds. This still reports real glyph collisions.
function Fit.drawnRect(object)
	local position, size = object.AbsolutePosition, object.AbsoluteSize
	local left, top, width, height = position.X, position.Y, size.X, size.Y
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if object:IsA("TextLabel") and object.BackgroundTransparency >= 1
		and not (stroke and stroke.Transparency < 1) then
		local bounds = object.TextBounds
		width, height = bounds.X, bounds.Y
		if object.TextXAlignment == Enum.TextXAlignment.Center then left += (size.X - width) / 2
		elseif object.TextXAlignment == Enum.TextXAlignment.Right then left += size.X - width end
		if object.TextYAlignment == Enum.TextYAlignment.Center then top += (size.Y - height) / 2
		elseif object.TextYAlignment == Enum.TextYAlignment.Bottom then top += size.Y - height end
	end
	return {Left = left, Top = top, Right = left + width, Bottom = top + height}
end

local function visibleChain(object: Instance): boolean
	local node: Instance? = object
	while node and not node:IsA("PlayerGui") do
		if node:IsA("CanvasGroup") and (node :: CanvasGroup).GroupTransparency >= 1 then return false end
		if node:IsA("ScreenGui") then
			if not (node :: ScreenGui).Enabled then return false end
		elseif node:IsA("GuiObject") then
			if not (node :: GuiObject).Visible then return false end
		end
		node = node.Parent
	end
	return true
end

-- The wheel is authored as a round image with its X just beyond the rim. Its
-- transparent square holder is not painted in the corner occupied by the X.
-- Keep any protruding pointer/text ink as additional real drawn rectangles.
function Fit.roundWheelShape(object, guiName)
	if guiName ~= "LuckyWheelGui" or object.Name ~= "WheelHolder"
		or object.BackgroundTransparency < 1 then return nil, nil end
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if stroke and stroke.Transparency < 1 then return nil, nil end
	local disc = object:FindFirstChild("WheelDisc")
	local size, position = object.AbsoluteSize, object.AbsolutePosition
	if not (disc and disc:IsA("ImageLabel") and disc.Visible and disc.ScaleType == Enum.ScaleType.Fit
		and size.X > 0 and math.abs(size.X - size.Y) <= 1) then return nil, nil end
	if math.abs(disc.AbsoluteSize.X-size.X) > 1 or math.abs(disc.AbsoluteSize.Y-size.Y) > 1
		or math.abs(disc.AbsolutePosition.X-position.X) > 1 or math.abs(disc.AbsolutePosition.Y-position.Y) > 1 then
		return nil, nil
	end
	local extra = {}
	local centreX, centreY, radius = position.X + size.X / 2, position.Y + size.Y / 2, size.X / 2
	for _, child in ipairs(object:GetDescendants()) do
		if child:IsA("GuiObject") and visibleChain(child) and not isFullyFaded(child)
			and (child.Name == "WheelPointer" or child:IsA("TextLabel")) then
			local rect = Fit.drawnRect(child)
			if child.Name == "WheelPointer" then
				local w, h = child.AbsoluteSize.X, child.AbsoluteSize.Y
				local angle = math.rad(child.Rotation)
				local width = math.abs(math.cos(angle) * w) + math.abs(math.sin(angle) * h)
				local height = math.abs(math.sin(angle) * w) + math.abs(math.cos(angle) * h)
				local x, y = (rect.Left + rect.Right) / 2, (rect.Top + rect.Bottom) / 2
				rect = {Left=x-width/2,Top=y-height/2,Right=x+width/2,Bottom=y+height/2}
			end
			local furthestX = math.max(math.abs(rect.Left-centreX), math.abs(rect.Right-centreX))
			local furthestY = math.max(math.abs(rect.Top-centreY), math.abs(rect.Bottom-centreY))
			if furthestX^2 + furthestY^2 > radius^2 then table.insert(extra, rect) end
		end
	end
	return "Circle", extra
end

-- Only these authored shared rows may paint over the thumbstick's activation
-- region. They take no input; actual buttons, scrolling and Active shields still
-- fail, as do collisions with the drawn movement cluster and jump control.
function Fit.passiveSharedRow(object, guiName): boolean
	if guiName ~= "RoundHud" or not table.find({"Caption", "FeedRow1", "FeedRow2"}, object.Name) then return false end
	local function takesInput(node)
		return node:IsA("GuiObject") and visibleChain(node)
			and (node.Active or node:IsA("GuiButton") or node:IsA("TextBox") or node:IsA("ScrollingFrame"))
	end
	if takesInput(object) then return false end
	for _, node in ipairs(object:GetDescendants()) do if takesInput(node) then return false end end
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
							local shape, adornments = Fit.roundWheelShape(child, screenGui.Name)
							table.insert(rects, {
								Path = prefix .. "." .. child.Name,
								Name = child.Name,
								Gui = screenGui.Name,
								Shape = shape, Adornments = adornments,
								TopBound = topBound,
								Overlay = isOverlay(child, viewport),
								MovementControl = isControl,
								PassiveThumbstick = Fit.passiveSharedRow(child, screenGui.Name),
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
function Fit.compassBearing(container, prefix)
	if container.Name ~= "Compass" then return nil end
	local ticks, centre = container:FindFirstChild("Ticks"), container:FindFirstChild("Centre")
	local chevron, readout = container:FindFirstChild("Chevron"), container:FindFirstChild("Readout")
	if not (ticks and centre and chevron and readout) then return nil end
	local bearing = nil
	local function include(node)
		if not (node:IsA("GuiObject") and visibleChain(node) and not isFullyFaded(node)) then return end
		local stroke = node:FindFirstChildOfClass("UIStroke")
		local draws = node.BackgroundTransparency < 1 or (stroke and stroke.Transparency < 1)
			or (node:IsA("TextLabel") and node.Text ~= "" and node.TextTransparency < 1)
		if not draws then return end
		local rect = Fit.drawnRect(node)
		if not bearing then
			bearing = {Name="Bearing",Path=prefix..".Bearing",Interactive=false,Active=false,
				Left=rect.Left,Top=rect.Top,Right=rect.Right,Bottom=rect.Bottom}
		else
			bearing.Left, bearing.Top = math.min(bearing.Left,rect.Left), math.min(bearing.Top,rect.Top)
			bearing.Right, bearing.Bottom = math.max(bearing.Right,rect.Right), math.max(bearing.Bottom,rect.Bottom)
		end
	end
	-- Ticks, baseline, centre line and pointing glyph are the joined marks of ONE bearing
	-- graphic. Their union still must clear the separate metre readout and every
	-- objective row; no interactive target or actual ink collision is exempted.
	include(ticks)
	for _, node in ipairs(ticks:GetDescendants()) do include(node) end
	include(centre)
	include(chevron)
	local baseline = container:FindFirstChild("Baseline")
	if baseline then include(baseline) end
	return bearing
end

function Fit.movementZoneHit(rect): string?
	local zone = UIDevice.OverlapsMovementZone(rect.Left, rect.Top, rect.Right, rect.Bottom)
	if zone ~= "Thumbstick" or rect.PassiveThumbstick ~= true then return zone end
	-- A passive caption/feed exemption never hides a collision with real controls.
	local zones = UIDevice.Layout().Zones
	for _, name in ipairs({"Controls", "Jump"}) do
		local drawn = zones[name]
		if rect.Left < drawn.Right and rect.Right > drawn.Left
			and rect.Top < drawn.Bottom and rect.Bottom > drawn.Top then return name end
	end
	return nil
end

local function collectDrawnChildren(container: Instance, prefix: string,
	viewport: Vector2, out: {any})
	local bearing = Fit.compassBearing(container, prefix)
	if bearing then table.insert(out, bearing) end
	for _, child in ipairs(container:GetChildren()) do
		if bearing and (child.Name == "Ticks" or child.Name == "Centre" or child.Name == "Chevron" or child.Name == "Baseline") then continue end
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
				local drawn = Fit.drawnRect(child)
				table.insert(out, {
					Path = path,
					Name = child.Name,
					Interactive = child:IsA("TextButton") or child:IsA("ImageButton"),
					Active = (child:IsA("TextButton") or child:IsA("ImageButton"))
						and (child :: any).Active or false,
					TextBounds = (child:IsA("TextLabel") or child:IsA("TextButton"))
						and (child :: any).TextBounds or nil,
					Left = drawn.Left,
					Top = drawn.Top,
					Right = drawn.Right,
					Bottom = drawn.Bottom,
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
					and not descendant:FindFirstChild(descendant.Name)
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
	if a.Shape == "Circle" then
		local cx, cy = (a.Left+a.Right)/2, (a.Top+a.Bottom)/2
		local radius = (a.Right-a.Left)/2
		local intersects
		if b.Shape == "Circle" then
			local dx, dy = cx-(b.Left+b.Right)/2, cy-(b.Top+b.Bottom)/2
			intersects = dx*dx+dy*dy < (radius+(b.Right-b.Left)/2-1)^2
		else
			local dx, dy = cx-math.clamp(cx,b.Left,b.Right), cy-math.clamp(cy,b.Top,b.Bottom)
			intersects = dx*dx+dy*dy < math.max(0,radius-1)^2
		end
		if intersects then return true end
		for _, extra in ipairs(a.Adornments or {}) do if rectsOverlap(extra,b) then return true end end
		for _, extra in ipairs(b.Adornments or {}) do if rectsOverlap(a,extra) then return true end end
		return false
	elseif b.Shape == "Circle" then return rectsOverlap(b,a) end
	-- A one-pixel shared edge is abutment, not overlap.
	return a.Left < b.Right - 1 and a.Right > b.Left + 1
		and a.Top < b.Bottom - 1 and a.Bottom > b.Top + 1
end

-- Kept as a non-mutating compatibility entry point for older QA scripts.
-- Shared HUD captions have their own movement-safe lane; the retired reader
-- pair grants no overlap exemption.
function UIRegression.PassiveReaderCaptionSafe(): (boolean, string)
	return false, "retired reader/caption pair"
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
				local zone = Fit.movementZoneHit(a)
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
	-- RoundUI derives this from its actual result surface. Reset the output too
	-- so another scenario cannot inherit movement suppression from a staged win.
	player:SetAttribute("RoundEndingOpen", false)
	-- The lobby queue lives inside RoundGui, which is never disabled, so nothing
	-- else here puts it away. Leaving it up leaked it into every scenario that
	-- ran after the queue row.
	local roundGui = findGui("RoundGui")
	local shade = roundGui and roundGui:FindFirstChild("QueueHostShade")
	if shade then
		shade.Visible = false
		-- LEVEL4_QUEUE_CHOICE_20261002. queue-host-panel-level4 splits the submit
		-- row through this attribute. RoundUI clears it when the shade hides, but
		-- only on a Visible CHANGE and on a deferred signal; clearing it here is
		-- synchronous, so every later row measures the single CREATE PARTY layout.
		shade:SetAttribute("QueueLaunchModes", nil)
	end
	for _, name in ipairs(OPTIONAL_GUIS) do
		local screen = findGui(name)
		if screen then
			(screen :: ScreenGui).Enabled = false
			for _, child in ipairs(screen:GetChildren()) do
				if child:IsA("GuiObject") then child.Visible = false end
			end
		end
	end
	-- RoundHud is a shared owner: disabling it also blanks caller-owned noise
	-- and stamina, and SetObjective cannot repair that ScreenGui flag. Reset only
	-- the fixture-owned objective/feed/caption/detector state through its real
	-- reversible seam; keep its owner GUI and other clients' roots untouched.
	if not Fit.realDispatchLive() then Fit.resetSharedHud() end
	player:SetAttribute("Level3_Hiding", nil)
	player:SetAttribute("Spectating", nil)
	-- HUD_B3 (owner, 2026-10-08): the two Round HUD inputs the b3-* rows force, so
	-- neither the edge nor the marker leaks into the next row. A cleared MoveNoise
	-- reads as walking, and NoiseReporter writes it again on its next applySpeed.
	player:SetAttribute("BeingChased", nil)
	player:SetAttribute("MoveNoise", nil)
	-- The harness's `inRound` flag only ever changed the Zyntra open button; it
	-- never told the CLIENT a round was running. So every control gated on
	-- NoiseReporter's controlsAvailable() -- JUMP, SNEAK, the glowstick drop --
	-- was invisible in every scenario, and a matrix that never saw them could
	-- never report them too small or overlapping. Cleared here so a scenario
	-- that does set it cannot leak the round into the next lobby row. An in-round
	-- reset keeps that context across the yield below, so lobby-only polls cannot
	-- briefly draw their buttons while the next round fixture is being staged.
	player:SetAttribute("InRound", if inRound == true then true else nil)
	player:SetAttribute("Level2AlertOwnsBand", nil)
	player:SetAttribute("ZyntraStoreOpen", nil)
	local store = findGui("ZyntraStore")
	-- SHOP_UI_L4_GO_LIVE_20261007: the shop is "Zyntra Shop L4" for every account
	-- (RECORDS and SETTINGS too since 2026-10-07; the terminal is deleted) and the
	-- dev menu is "Zyntra Dev L4". Both draw over the HUD and re-assert their own
	-- modal flag, so one left open would sit over every later row. Closed through
	-- their own production toggles: writing Visible = false directly would leave
	-- ZyntraStoreOpen and the movement suppression out of step with the pixels.
	-- RAIL_OVER_WINDOWS_20261007: Daily Rewards and the Lucky Wheel too, now that
	-- the daily-modal and wheel-modal rows open them. The wheel's close is also
	-- what hands every ScreenGui its takeover disabled back, so it runs here,
	-- before FriendBoostGui's Enabled below is written for this scenario.
	for _, l4 in ipairs({{"ZyntraShopL4", "UIRegressionZyntraShopL4Probe"},
		{"ZyntraDevL4", "UIRegressionZyntraDevL4Probe"},
		{"ZyntraDailyL4", "UIRegressionZyntraDailyL4Probe"},
		{"LuckyWheelGui", "UIRegressionLuckyWheelProbe"}}) do
		local screen = findGui(l4[1])
		local l4Probe = screen and screen:FindFirstChild(l4[2])
		if l4Probe and l4Probe:IsA("BindableFunction") then
			pcall(function() l4Probe:Invoke("close") end)
		end
	end
	-- THE WHOLE RAIL, not the two buttons it happened to hold when this was
	-- written. It grew to five on 2026-09-16 (cards #103 / #104), and a reset that
	-- puts three of them back leaves the other two drawn into the next scenario --
	-- a state leak that then reads as a real overlap finding.
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
	for _, name in ipairs({"ZyntraShopButton", "ZyntraRewardsButton",
		"ZyntraWheelButton", "ZyntraMusicButton"}) do
		local railButton = store and store:FindFirstChild(name)
		if railButton and railButton:IsA("GuiObject") then
			railButton.Visible = not inRound
		end
	end
	-- UI_REGRESSION_20260923. The OTHER lobby-only surfaces, for the same reason
	-- as the rail: an in-round row must not measure UI the game only draws in the
	-- lobby. The Friend Boost chip (lobby only by owner decision 2026-09-17) and
	-- the Level 3 reader now share UIDevice.TopRightPanel on desktop (e4bc4a7),
	-- so level3-reader-open reported an overlap no player can see. Enabled, not
	-- chip.Visible: the chip's own 0.5 s poll rewrites Visible inside the settle,
	-- and nothing in that script writes Enabled; the closing reset (inRound nil)
	-- turns it back on. The rewards intro card is lobby-only in the same way.
	local boost = findGui("FriendBoostGui")
	if boost and boost:IsA("ScreenGui") then boost.Enabled = not inRound end
	local intro = store and store:FindFirstChild("RewardsIntroCard")
	if inRound and intro and intro:IsA("GuiObject") then intro.Visible = false end
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
	-- The five lobby rail buttons, which the *-modal rows hold to the
	-- rail-over-windows contract (RAIL_OVER_WINDOWS_20261007).
	local rail = {"ZyntraOpenButton", "ZyntraShopButton", "ZyntraRewardsButton",
		"ZyntraWheelButton", "ZyntraMusicButton"}
	-- The token pill and Friend Boost chip stay up over the same windows (owner 2026-10-08).
	local overWindows = {"ZyntraLobbyPillL4.TokenPill", "FriendBoostGui.FriendBoostChip", table.unpack(rail)}
	-- Round HUD's chase edge, for the b3-chase-edge row. HUD_B3 (owner, 2026-10-08).
	local edgeBands = {"RoundHudThreat.ChaseEdgeLeft", "RoundHudThreat.ChaseEdgeRight",
		"RoundHudThreat.ChaseEdgeTop", "RoundHudThreat.ChaseEdgeBottom"}
	local levelTwo = workspace:GetAttribute("SelectedLevel") == 2
	return {
		{Name = "gameplay", Setup = function()
			local live = Fit.liveRoundEligible(player:GetAttribute("InRound"),
				player:GetAttribute("Spectating"), player:GetAttribute("Escaped"))
			resetScenario(live)
			if live then player:SetAttribute("InRound", true) end
		end},
		{Name = "shared-caption", LiveRound = true, Requires = {"RoundHud.Caption"}, Setup = function()
			resetScenario(true); Fit.stageRoundObjective(3, true)
		end},
		{Name = "shared-objective", Requires = {"RoundHud.ObjectiveCard"}, Setup = function()
			resetScenario(true); Fit.stageRoundObjective(1)
		end},
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
		-- LEVEL4_QUEUE_CHOICE_20261002. A Level 4 bay offers TRIAL ROUND and MAP
		-- PREVIEW: GameManager's queuehost carries "trial,preview" and RoundUI puts
		-- it on the shade as QueueLaunchModes, which splits the submit row into
		-- CreateParty (relabelled TRIAL ROUND) and MapPreview -- two half-width
		-- buttons, so both are asserted as thumb targets and as fitting their text.
		-- The attribute goes on BEFORE the reveal, the production order. The yield
		-- first lets RoundUI's deferred Visible=false handler (resetScenario just
		-- hid the shade, and that handler also clears the attribute) run before
		-- this write rather than after it. resetScenario clears it again for the
		-- next row.
		{Name = "queue-host-panel-level4", Requires = "QueueHostPanel",
			TouchTargets = {
				"QueueHostPanel.CloseQueue", "QueueHostPanel.DecreasePlayers",
				"QueueHostPanel.IncreasePlayers", "QueueHostPanel.PrivacyToggle",
				"QueueHostPanel.CreateParty", "QueueHostPanel.MapPreview",
			}, TextFitTargets = {"QueueHostPanel.CreateParty", "QueueHostPanel.MapPreview"},
			Setup = function()
			resetScenario(false)
			task.wait()
			local shade = findGui("RoundGui")
			shade = shade and shade:FindFirstChild("QueueHostShade")
			if shade then shade:SetAttribute("QueueLaunchModes", "trial,preview") end
			revealGui("RoundGui", function(child)
				return child.Name == "QueueHostShade"
			end)
			if shade then shade.Visible = true end
		end},
		{Name = "level1-objective-receiver", Requires = {"RoundHud.ObjectiveCard"}, Setup = function()
			resetScenario(true); Fit.stageRoundObjective(1)
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
		-- HUD_B3 (owner, 2026-10-08): the B3 QA rows (B3-DESIGN critic K6). Round
		-- HUD draws on a living body in an active round only, and RoundActive is
		-- not the harness's to write (B2 critic C13), so both are LiveRound rows:
		-- a skip outside a round started with the playtest recipe.
		--
		-- The marker with SNEAK engaged. A harness cannot tap the cell, so it
		-- publishes what the tap would, MoveNoise = "crouch", once the InRound
		-- write has run applySpeed (which would overwrite it). The group is clipped
		-- to its pill (K6), so on TOUCH it has to clear the LIGHT and SNEAK cells
		-- and every movement zone, and on PC the kit row (K4). Run it on TOUCH.
		{Name = "b3-sneak-marker", LiveRound = true,
			Requires = if UIDevice.IsTouch() then {"RoundHud.NoiseMarker", "TouchSneakHold"}
				else {"RoundHud.NoiseMarker"},
			Setup = function()
				resetScenario(true)
				player:SetAttribute("InRound", true)
				task.wait(.1)
				player:SetAttribute("MoveNoise", "crouch")
			end},
		-- The chase edge with BeingChased forced, as a Level 1 entity chase sets
		-- it. The bands are FULLSCREEN_OVERLAYS: measured and held onscreen, never
		-- an overlap. Level 2 never draws the edge (owner), so there it is forbidden.
		{Name = "b3-chase-edge", LiveRound = true,
			Requires = if levelTwo then nil else edgeBands,
			Forbids = if levelTwo then edgeBands else nil,
			Setup = function()
				resetScenario(true)
				player:SetAttribute("InRound", true)
				player:SetAttribute("BeingChased", true)
			end},
		{Name = "shared-objective-and-feed", LiveRound = true,
			Requires = {"RoundHud.ObjectiveCard", "RoundHud.FeedRow1"}, Setup = function()
			resetScenario(true); Fit.stageRoundObjective(2, false, true)
		end},
		{Name = "level3-shared-objective", Requires = {"RoundHud.ObjectiveCard"}, Setup = function()
			resetScenario(true); Fit.stageRoundObjective(3)
		end},
		{Name = "hiding", Requires = {"HiddenStatus", "LeaveHiding"}, Setup = function()
			resetScenario(true)
			player:SetAttribute("InRound", true)
			player:SetAttribute("Level3_Hiding", true)
			player:SetAttribute("UIRegressionForceHiding", true)
			local screen = findGui("Level3TableHideUI"); if screen then (screen :: ScreenGui).Enabled = true end
		end},
		{Name = "hiding-plus-reader", Requires = {"HiddenStatus", "LeaveHiding"},
			Forbids = {"RoundHud.ObjectiveCard"}, Setup = function()
			resetScenario(true)
			Fit.stageRoundObjective(3)
			player:SetAttribute("Level3_Hiding", true)
			player:SetAttribute("UIRegressionForceHiding", true)
			local screen = findGui("Level3TableHideUI"); if screen then (screen :: ScreenGui).Enabled = true end
		end},
		{Name = "spectate", Setup = function()
			resetScenario(true)
			player:SetAttribute("Spectating", true)
			revealGui("SpectateGui")
		end},
		-- WHAT THIS ROW USED TO BE: `resetScenario(); SetAttribute; revealGui` and
		-- nothing else; then the Zyntra terminal on SETTINGS, opened through its
		-- production toggle, with its shell rectangles required and its
		-- CloseTerminal as a touch target.
		--
		-- REWRITTEN for RECORDS_SETTINGS_L4_20261007 (owner: the terminal is
		-- deleted, SETTINGS is a page of the L4 shop). The row opens SETTINGS
		-- through the shop's PRODUCTION bridge (its probe's open:Settings) and
		-- requires the window. The window's own controls are not rectangles this
		-- scan reaches (Check stops two layout groups down, and the window cannot
		-- be an internal panel: its drop shadows overlap their faces by design), so
		-- their 44 px floor, text fit and states -- CloseTerminal's old
		-- touch-target row included -- are asserted by the L4 harness
		-- (roblox-draft/tests, sections 4 and 17).
		--
		-- RAIL_OVER_WINDOWS_20261007 (owner request, 2026-10-07): the rail stays
		-- up over its own windows and a press switches window. Until then this row
		-- FORBADE the five rail buttons, because one left drawn under the window
		-- was a second screen-owning modal one tap away; ZyntraStore's switchFrom
		-- now closes the open window before the next one opens, so the same five
		-- are REQUIRED: drawn, Active, and the topmost thing at their own centre.
		-- The last is the one that matters. Every window draws a full-screen Active
		-- shield (Shop 56, Dev 57, Daily 117, Wheel 118) that Scan cannot see -- a
		-- transparent Dim is skipped as faded and WindowHolder is an overlay -- so
		-- without RequiresTopmost a rail behind the shield passes Requires and
		-- RequiresActive while every real tap on it is swallowed.
		-- OWNER 2026-10-08: the lobby token pill and the Friend Boost chip are held to
		-- the same drawn-and-topmost contract over every window (overWindows, above).
		-- Not RequiresActive (the invite depends on CanSendGameInviteAsync) and not
		-- TouchTargets (a docked pill sits in the topbar band, at a negative Top).
		{Name = "store-modal", LiveLobby = true, Requires = {"ZyntraShopL4.Root.WindowHolder", table.unpack(overWindows)},
			RequiresActive = rail, RequiresTopmost = overWindows, Setup = function()
			resetScenario()
			local shop = findGui("ZyntraShopL4")
			local probe = shop and shop:FindFirstChild("UIRegressionZyntraShopL4Probe")
			-- No probe means no Studio seam (or no L4 install), which is a failure
			-- to report and not a row to skip: Requires catches the missing window.
			if probe and probe:IsA("BindableFunction") then probe:Invoke("open:Settings") end
			task.wait(.15)
		end},
		-- The same rail contract over the other two lobby windows every account
		-- can open (RAIL_OVER_WINDOWS_20261007). Each opens through its own Studio
		-- probe's "open", which is the production request path with its refusals.
		-- No dev row: the dev menu only opens for whitelisted accounts, so it would
		-- fail on every other one for a reason that is not a defect.
		{Name = "daily-modal", LiveLobby = true, Requires = {"ZyntraDailyL4.Root.WindowHolder", table.unpack(overWindows)},
			RequiresActive = rail, RequiresTopmost = overWindows, Setup = function()
			resetScenario()
			local daily = findGui("ZyntraDailyL4")
			local probe = daily and daily:FindFirstChild("UIRegressionZyntraDailyL4Probe")
			if probe and probe:IsA("BindableFunction") then probe:Invoke("open") end
			task.wait(.15)
		end},
		-- The wheel's takeover disables every OTHER ScreenGui, and Scan skips a
		-- disabled gui, so requiring the rail, the pill and the chip here is also
		-- what proves the takeover's three exemptions ("ZyntraStore",
		-- "ZyntraLobbyPillL4", "FriendBoostGui"; owner 2026-10-08) hold.
		{Name = "wheel-modal", LiveLobby = true, Requires = {"LuckyWheelGui.WheelShade", table.unpack(overWindows)},
			RequiresActive = rail, RequiresTopmost = overWindows, Setup = function()
			resetScenario()
			local wheel = findGui("LuckyWheelGui")
			local probe = wheel and wheel:FindFirstChild("UIRegressionLuckyWheelProbe")
			if probe and probe:IsA("BindableFunction") then probe:Invoke("open") end
			task.wait(.15)
		end},
		-- (store-modal-dev is gone with the DEV tab, go-live 2026-10-07. The L4 dev
		-- menu's captions are measured in BriefingExclusionMatrix.)
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
function Fit.buttonText(button): string
	if not button then return "" end
	local label = button:FindFirstChild("Label", true)
	return label and label:IsA("TextLabel") and label.Text or (button :: any).Text or ""
end

function Fit.hudProbe()
	local gui = findGui("RoundHud")
	local probe = gui and gui:FindFirstChild("UIRegressionRoundHudProbe")
	assert(probe and probe:IsA("BindableFunction"), "actual player UIRegressionRoundHudProbe missing")
	return probe
end

function Fit.stageRoundObjective(level: number, caption: boolean?, feed: boolean?)
	local player = Players.LocalPlayer
	player:SetAttribute("UIRegressionForceLevel3Reader", true)
	workspace:SetAttribute("SelectedLevel", level)
	player:SetAttribute("InRound", true)
	local probe = Fit.hudProbe()
	local state = level == 2 and {Level = 2, Title = "Find the exit", Lines = {}, Done = false}
		or {Level = level, Title = level == 3 and "LOAD THE PLAYER" or "FIND THE EXIT",
			Count = 2, Goal = 4, Tag = level == 3 and "CDs" or "PUMPS",
			Lines = {"Search the rooms", "Stay close to the group"}, Compass = {State = "locating"}}
	assert(probe:Invoke("setobjective", state) ~= false,
		"actual player objective refused the staged contract")
	if caption then probe:Invoke("caption", "COMMAND CENTER", "Keep moving and listen for the others.") end
	if feed then probe:Invoke("feed", {Kind = "TEAM", Actor = player.Name, Detail = "found a CD", Key = "ui-regression"}) end
end

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
		local child = frame and frame:FindFirstChild(name, true)
		return (child and child:IsA("TextButton")) and child or nil
	end
	local function hintText(): string
		local frame = overlay()
		local hint = frame and frame:FindFirstChild("Countdown", true)
		return (hint and hint:IsA("TextLabel")) and hint.Text or ""
	end
	local function visibleActions(): {string}
		local names = {}
		local frame = overlay()
		for _, child in ipairs(frame and frame:GetDescendants() or {}) do
			if child:IsA("TextButton") and child:GetAttribute("CompletionAction") ~= nil and visibleChain(child) then
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

	-- (1) Levels 1 to 3: exactly CONTINUE and BACK TO LOBBY.
	drive("win")
	local continueRun, returnLobby = action("ContinueRun"), action("ReturnToLobby")
	check(continueRun ~= nil and returnLobby ~= nil, "win offers both actions")
	check(table.concat(visibleActions(), ",") == "ContinueRun,ReturnToLobby",
		"win offers EXACTLY two actions", table.concat(visibleActions(), ","))
	if continueRun and returnLobby then
		check(Fit.buttonText(continueRun) == "CONTINUE", "continue label", Fit.buttonText(continueRun))
		check(Fit.buttonText(returnLobby) == "BACK TO LOBBY", "lobby label", Fit.buttonText(returnLobby))
		check(continueRun:GetAttribute("CompletionAction") == "continuenow",
			"continue is wired to continuenow",
			tostring(continueRun:GetAttribute("CompletionAction")))
		check(returnLobby:GetAttribute("CompletionAction") == "returntolobby",
			"lobby is wired to returntolobby",
			tostring(returnLobby:GetAttribute("CompletionAction")))
	end
	check(hintText():find("IN", 1, true) ~= nil,
		"win countdown promises the next level", hintText())

	-- (2) First choices are provisional until the original deadline.
	press("ContinueRun")
	continueRun, returnLobby = action("ContinueRun"), action("ReturnToLobby")
	if continueRun and returnLobby then
		check(Fit.buttonText(continueRun) == "CONTINUING...", "provisional continue shows pressed label", Fit.buttonText(continueRun))
		check(continueRun.Active and returnLobby.Active,
			"continue leaves both choices available")
	end

	-- (3) Switch both ways in THIS window, without resetScenario/drive.
	press("ReturnToLobby")
	continueRun, returnLobby = action("ContinueRun"), action("ReturnToLobby")
	if continueRun and returnLobby then
		check(Fit.buttonText(returnLobby) == "RETURNING...", "provisional lobby shows pressed label", Fit.buttonText(returnLobby))
		check(continueRun.Active and returnLobby.Active,
			"Continue to Lobby leaves the opposite choice available")
	end
	press("ContinueRun")
	continueRun, returnLobby = action("ContinueRun"), action("ReturnToLobby")
	check(continueRun ~= nil and returnLobby ~= nil and continueRun.Active and returnLobby.Active,
		"Lobby to Continue remains editable in the same window")

	-- (4) The last level: one action, and no route onward.
	drive("winfinal")
	check(table.concat(visibleActions(), ",") == "ReturnToLobby",
		"final level offers ONLY back to lobby", table.concat(visibleActions(), ","))
	check(hintText():find("LOBBY", 1, true) ~= nil,
		"final countdown returns to the lobby", hintText())
	check(hintText():find("LEVEL", 1, true) == nil and hintText():find("ENTERING", 1, true) == nil,
		"final countdown never routes to a next level", hintText())
	press("ContinueRun")
	returnLobby = action("ReturnToLobby")
	check(returnLobby ~= nil and Fit.buttonText(returnLobby) == "BACK TO LOBBY"
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
		local rect = UIRegression.ResolveRect(button, Vector2.new(width, height), UIDevice.Layout().Inset.Y)
		if rect then rect.Name = button.Name end
		return rect
	end

	local forcedTouch = workspace:GetAttribute("ForceTouchUI")
	local forcedViewport = workspace:GetAttribute("UIRegressionViewport")
	local ok, err = pcall(function()
		for _, mode in ipairs({
			{Label = "levels 1-3", Dev = "win", Expect = 2},
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
				for _, child in ipairs(frame and frame:GetDescendants() or {}) do
					if child:IsA("TextButton") and child:GetAttribute("CompletionAction") ~= nil and visibleChain(child) then
						table.insert(rects, resolve(child, device.Width, device.Height))
					end
				end
				local hint = frame and frame:FindFirstChild("EndingHint", true)
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
	"RoundGui", "LevelOneGuideGui", "StaminaGui", "FlashlightPopup",
	"SpectateGui", "ZyntraStore", "Level3TableHideUI",
	"RoundHud", "RoundHudThreat", "FoundFootageHUD", "RoundExitGui",
	-- The only shop since the go-live (2026-10-07). It exists only once
	-- ReplicatedStorage.ZyntraShopUI loaded, so a broken install fails here by
	-- name. ZyntraDevL4 is deliberately absent: non-developers never get it.
	"ZyntraShopL4",
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

-- Every helper the three matrices below share lives on ONE file-level local.
-- Not a style choice: this module already carries a large number of names at
-- chunk scope and Luau caps that at 200, so fourteen more would have cost the
-- file its ability to compile.

-- GetTextBoundsAsync is the ONE way to ask what a string WOULD need at a size
-- and wrap width the client is not currently rendering. The current shared
-- HUD matrix uses native TextBounds; it does not call this analytical helper.
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
	"UIRegressionViewport", "ForceTouchUI", "SelectedLevel",
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
	-- KitFanMatrix lends the player one of each fan item so the KIT fan has
	-- something to open. HUD_B2_TOUCH (owner, 2026-10-08).
	"ZyntraSpeedPotions", "ZyntraRouteMarkers", "ZyntraOwnsEntityDetector",
	-- The b3-chase-edge row forces it, as the server does on a chase.
	-- HUD_B3 (owner, 2026-10-08).
	"BeingChased",
}
-- OUTPUTS production derives from those inputs. They are restored with
-- everything else, but they are not held to the snapshot afterwards: production
-- republishes them from its own state, and demanding they match a value the
-- harness wrote would be demanding that production stop deriving them.
local DERIVED_PLAYER_ATTRIBUTES = {
	-- RoundUI republishes this from the actual results surface, like queue/card visibility.
	"RoundEndingOpen",
	"Level2AlertOwnsBand", "DispatchBriefingOpen",
	"DispatchTextActive", "ZyntraDispatchClientActive",
	"TouchMovementSuppressed",
	-- RoundUI publishes both of these from the party-down window itself, and
	-- ZyntraStore reads them to stand its own re-entry modal down. They are NOT
	-- the same fact: the card flag says a card is drawn (it frees the cursor),
	-- the window flag outlives it once NO THANKS is pressed.
	"PartyDownCardOpen", "PartyDownWindowOpen",
	-- The KIT fan's one state. KitFanMatrix writes it the way KIT's own tap
	-- does, and ProtectionHUD forces it false whenever the fan cannot be open.
	-- HUD_B2_TOUCH (owner, 2026-10-08).
	"KitFanOpen",
	-- NoiseReporter's applySpeed republishes it on its next round-branch call;
	-- the b3-sneak-marker row writes "crouch" in its place. HUD_B3 (owner, 2026-10-08).
	"MoveNoise",
}
local BORROWED_GUIS = {
	"PuzzleGui", "Level2ObjectiveGui", "Level2AlertGui", "Level3ReaderGui",
	"Level3TableHideUI", "SpectateGui", "LevelOneGuideGui", "RoundGui",
	"ZyntraStore", "NoiseGui", "FlashlightPopup", "RoundHud", "RoundHudThreat", "RoundExitGui", "FoundFootageHUD",
	"FriendBoostGui", "ZyntraShopL4", "ZyntraDevL4", "ZyntraDailyL4", "LuckyWheelGui", "ZyntraLobbyPillL4",
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
	-- The text caption is intentionally non-modal. DispatchBriefingOpen stays
	-- false even while a real briefing continues behind a store or queue.
	if player:GetAttribute("DispatchTextActive") ~= true then return false end
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
				.. " briefing has finished, or inspect DispatchTextActive if it is stuck.",
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

-- Shared HUD roots are rebuilt by its reversible QA seam. Instance identity is
-- not a state assertion: compare the captured semantic counter (including nil)
-- and remeasure the current roots after restore instead.
Fit.HudOwnedRoots = {"ObjectiveCard", "FeedRow1", "FeedRow2", "Caption", "DetectorCard"}

function Fit.resetSharedHud()
	local gui = findGui("RoundHud")
	local probe = gui and gui:FindFirstChild("UIRegressionRoundHudProbe")
	if not (probe and probe:IsA("BindableFunction")) then return end
	local captured = probe:Invoke("capture")
	assert(type(captured) == "table", "RoundHud actual-player QA capture was refused")
	assert(probe:Invoke("restore", {Kind = "RoundHudTestState", LastObjective = captured.LastObjective,
		Objective = {}, Feed = {Entries = {}}, Caption = {}, Detector = {}}) == true,
		"RoundHud fixture reset was refused")
end

function Fit.liveRoundEligible(inRound, spectating, escaped): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return workspace:GetAttribute("RoundActive") == true and inRound == true
		and spectating ~= true and escaped ~= true and humanoid ~= nil and humanoid.Health > 0
		and character:FindFirstChild("HumanoidRootPart") ~= nil
end

function Fit.liveLobbyEligible(roundBefore): boolean
	if roundBefore == true or workspace:GetAttribute("RoundActive") == true
		or workspace:GetAttribute("RoundLoadingState") == "loading" then return false end
	local lobby = workspace:FindFirstChild("ServerLobby")
	local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
	if spawn and spawn:IsA("SpawnLocation")
		and spawn:GetAttribute("LobbySpawnFloorModelName") == "LobbyReimaginedPreview" then
		local revised = workspace:FindFirstChild("LobbyReimaginedPreview")
		if revised and revised:IsA("Model") and revised:GetAttribute("LobbyReimaginedOwned") == true
			and revised:GetAttribute("Ready") == true then lobby = revised end
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (lobby and lobby:IsA("Model") and root) then return false end
	local cf, size = lobby:GetBoundingBox()
	local point, centre = root.Position, cf.Position
	return math.abs(point.X - centre.X) <= size.X / 2 + 6
		and math.abs(point.Y - centre.Y) <= size.Y / 2 + 6
		and math.abs(point.Z - centre.Z) <= size.Z / 2 + 6
end

function Fit.samePlain(a, b): boolean
	if typeof(a) ~= typeof(b) then return false end
	if typeof(a) ~= "table" then return a == b end
	for key, value in pairs(a) do
		if not Fit.samePlain(value, b[key]) then return false end
	end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end

function Fit.hudOwnedNode(screen, child): boolean
	if screen.Name ~= "RoundHud" then return false end
	local root = child
	while root and root.Parent ~= screen do root = root.Parent end
	return root ~= nil and table.find(Fit.HudOwnedRoots, root.Name) ~= nil
end

function Fit.hudProjection()
	local projected = {}
	local gui = findGui("RoundHud")
	for _, name in ipairs(Fit.HudOwnedRoots) do
		local root = gui and gui:FindFirstChild(name)
		local row = {Exists = root ~= nil, Visible = false}
		if root and root:IsA("GuiObject") then
			row.Visible = visibleChain(root) and not isFullyFaded(root)
			row.Left, row.Top = root.AbsolutePosition.X, root.AbsolutePosition.Y
			row.Width, row.Height = root.AbsoluteSize.X, root.AbsoluteSize.Y
		end
		projected[name] = row
	end
	return projected
end

function Fit.hudRestoreProblems(saved): {string}
	local problems = {}
	if not saved.HudState then return problems end
	local gui = findGui("RoundHud")
	local probe = gui and gui:FindFirstChild("UIRegressionRoundHudProbe")
	if not (probe and probe:IsA("BindableFunction")) then
		return {"RoundHud actual-player QA probe is gone"}
	end
	local read, snapshot, current = pcall(function()
		return probe:Invoke("snapshot"), probe:Invoke("capture")
	end)
	if not read or type(current) ~= "table" then
		return {"RoundHud actual-player state cannot be reprobed"}
	end
	if not Fit.samePlain(snapshot, saved.HudState.LastObjective) then
		table.insert(problems, "RoundHud.LastObjective differs from the captured semantic snapshot")
	end
	local state, now = saved.HudState, workspace:GetServerTimeNow()
	local entries, feedExpired = {}, false
	for _, entry in ipairs(state.Feed.Entries) do
		if entry.Until > now then table.insert(entries, entry) else feedExpired = true end
	end
	if not Fit.samePlain(entries, current.Feed.Entries) then
		table.insert(problems, "RoundHud feed state or its original deadlines were not restored")
	end
	local captionExpired = state.Caption.Text ~= nil and (state.Caption.Until or 0) <= now
	local captionText = if captionExpired then nil else state.Caption.Text
	if current.Caption.Text ~= captionText
		or (captionText ~= nil and current.Caption.Until ~= state.Caption.Until) then
		table.insert(problems, "RoundHud caption state or its original deadline was not restored")
	end
	local objective = state.Objective
	local danger = objective.State and objective.State.Status and objective.State.Status.Kind == "danger"
	local collapsed = objective.Expanded == true and not danger and (objective.ExpandUntil or 0) <= now
	local detector = state.Detector
	local detectorExpired = (detector.ExpiresAt or 0) <= now
	local attention = detector.Attention
	local detectorRested = attention and not attention.Urgent and (attention.HoldUntil or 0) <= now
		and (attention.RestNow or 0) == 0
	local projected = Fit.hudProjection()
	for _, name in ipairs(Fit.HudOwnedRoots) do
		local before, after = saved.HudGeometry[name], projected[name]
		local isFeed = name == "FeedRow1" or name == "FeedRow2"
		local timedLaneChange = (isFeed or name == "Caption") and (feedExpired or captionExpired)
		local expired = (name == "Caption" and captionText == nil)
			or (isFeed and (#entries == 0 or (name == "FeedRow2" and #entries < 2)))
			or (name == "DetectorCard" and (detectorExpired or detectorRested))
		local expectedVisible = before.Visible and not expired
		if after.Visible ~= expectedVisible and not (isFeed and timedLaneChange and not expired) then
			table.insert(problems, "RoundHud." .. name .. ".Visible differs after restore")
		end
		if before.Visible and after.Visible and not timedLaneChange then
			for _, field in ipairs({"Left", "Top", "Width", "Height"}) do
				-- Touch expansion has a real six-second deadline; restoring a long
				-- test must not restart it just to reproduce the old card height.
				local changedHeight = collapsed and (field == "Height" or isFeed or name == "Caption")
				if not changedHeight and math.abs(after[field] - before[field]) > 1 then
					table.insert(problems, "RoundHud." .. name .. "." .. field .. " geometry differs after restore")
				end
			end
		end
	end
	return problems
end

function Fit.borrow()
	local player = Players.LocalPlayer
	local saved = {
		Workspace = {}, Player = {}, Guis = {}, Subtitle = nil,
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
	-- controls and scroll them. A snapshot one level deep
	-- restored the shade and left the panel inside it forced on, which is how a
	-- later row measured a screen the player never sees.
	for _, name in ipairs(BORROWED_GUIS) do
		local screen = playerGui():FindFirstChild(name)
		if screen and screen:IsA("ScreenGui") then
			local entry = {Enabled = screen.Enabled, Children = {}}
			for _, child in ipairs(screen:GetDescendants()) do
				if child:IsA("GuiObject") and not Fit.hudOwnedNode(screen, child) then
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
	local hud = findGui("RoundHud")
	local hudProbe = hud and hud:FindFirstChild("UIRegressionRoundHudProbe")
	if hudProbe and hudProbe:IsA("BindableFunction") then
		saved.HudState = hudProbe:Invoke("capture")
		saved.HudGeometry = Fit.hudProjection()
	end
	-- WAS A BRIEFING IN FLIGHT? Recorded for CONTEXT only. It used to license an
	-- excuse in Fit.residue -- the widgets a briefing owns were dropped from the
	-- comparison if it had ended since -- and it no longer does. Every lane that
	-- can disturb a live dispatch now waits for one to end BEFORE it takes this
	-- snapshot (Fit.awaitQuietDispatch), so this reads false whenever a lane is
	-- behaving; when it does not, residue says a transition happened instead of
	-- quietly forgiving the widgets that moved.
	saved.DispatchOpen = Players.LocalPlayer:GetAttribute("DispatchTextActive") == true
	-- Preserve the live dispatch caption so every QA lane restores the copy it borrowed.
	local guide = playerGui():FindFirstChild("LevelOneGuideGui")
	local subtitle = guide and guide:FindFirstChild("Subtitle", true)
	if subtitle and subtitle:IsA("TextLabel") then
		saved.Subtitle = {Label = subtitle, Text = subtitle.Text}
	end
	return saved
end

function Fit.restore(saved)
	if not saved then return end
	local player = Players.LocalPlayer
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
	local hud = findGui("RoundHud")
	local hudProbe = hud and hud:FindFirstChild("UIRegressionRoundHudProbe")
	if saved.HudState and hudProbe and hudProbe:IsA("BindableFunction") then
		assert(hudProbe:Invoke("restore", saved.HudState) == true, "RoundHud QA restore was refused")
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
-- where it has one; the shared HUD's semantic state and current root geometry;
-- and that the dispatch caption no longer holds the test cue.
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
		~= (player:GetAttribute("DispatchTextActive") == true) then
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
	for _, problem in ipairs(Fit.hudRestoreProblems(saved)) do table.insert(problems, problem) end
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
-- TouchTargetMatrix
-- ---------------------------------------------------------------------------

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
	-- Every scenario input, GUI and actual-player HUD state is borrowed before
	-- the first override; restore also runs after an error in either sweep.
	local saved = Fit.borrow()
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
			-- Close the preceding device's fixture-owned modal/result before staging this readout.
			resetScenario(true)
			Fit.stageRoundObjective(1)
			task.wait(.12)
			for _, spec in ipairs({
				{"RoundHud", "ObjectiveCard"},
			}) do
				local objectiveGui = findGui(spec[1])
				local objectivePanel = objectiveGui and objectiveGui:FindFirstChild(spec[2], true)
				local objectiveRect = objectivePanel
					and UIRegression.ResolveRect(objectivePanel, device.Size, layout.Inset.Y)
				if objectiveRect and not objectiveRect.Unresolvable then
					local problems = Fit.anchorProblems(objectiveRect, layout, spec[2], layout.IsTouch and 16 or 24)
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

	local restored, restoreWhy = pcall(Fit.restore, saved)
	task.wait(.2)
	record(restored, "the full borrowed state was restored", restoreWhy)
	local residue, note = Fit.residue(saved)
	if note then table.insert(report, note) end
	record(#residue == 0, "touch target sweeps leave no borrowed-state residue", table.concat(residue, "; "))
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
function UIRegression.ResolveRect(object, viewport: Vector2, insetY: number, renderedFrame: any?)
	local chain, node = {}, object
	while node and not node:IsA("ScreenGui") do
		table.insert(chain, 1, node)
		node = node.Parent
	end
	if not node then return nil end
	local frame = renderedFrame or UIRegression.ScreenGuiFrame(node :: ScreenGui, viewport)
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

-- The engine keeps rendering at the native ScreenGui frame during a synthetic
-- viewport sweep. Resolve that actual frame independently for readback parity;
-- fixture policy and safe-slot assertions continue to use the stated fixture.
function Fit.engineRect(object)
	local screen = object
	while screen and not screen:IsA("ScreenGui") do screen = screen.Parent end
	if not screen then return nil end
	return UIRegression.ResolveRect(object, screen.AbsoluteSize, 0, {
		Left = screen.AbsolutePosition.X, Top = screen.AbsolutePosition.Y,
		Width = screen.AbsoluteSize.X, Height = screen.AbsoluteSize.Y,
	})
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
		-- HUD_B2_TOUCH (owner, 2026-10-08): the eight cells of UIDevice's 4 + 4
		-- grid. ProtectionHUD registers SHIELD and KIT on any touch device,
		-- whether or not the player owns anything -- registration follows the
		-- form factor, visibility follows the inventory. POTION, MARKER and SCAN
		-- (SpeedPotionUse, RouteMarkerPlace, EntityDetectorScan) are items in
		-- the KIT fan now, which is transient and never registered.
		ProtectionUse = true, KitToggle = true,
		-- UI_REGRESSION_20260923: FriendBoost is the lobby chip's rectangle
		-- (Friend Boost Client, FRIEND_BOOST_20260916), registered so layouts
		-- avoid it. It stands down under the shade like everything else here.
		FriendBoost = true,
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
				-- The registered rectangle can be visual while a child owns input
				-- (FlashlightPower was that shape until the B2 LIGHT cell made the
				-- root the button). Snapshot the complete GuiObject subtree so an
				-- invisible-but-Active child cannot disappear from the proof.
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
					device.Name .. ": exactly the authored registered-control keys are present",
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
-- BriefingFitMatrix: compatibility alias for the shared HUD matrix.
-- ---------------------------------------------------------------------------
-- Preserves this public lane name, token ownership and borrow/restore behavior.
-- Current coverage is Fit.bodyRoundHudMatrix: shared objectives and native
-- text bounds across device fixtures, plus admitted feed/caption checks.
-- It does not run the retired analytical briefing layout or localisation corpus.

function Fit.bodyBriefingFitMatrix(): (string, number)
	return Fit.bodyRoundHudMatrix()
end

function UIRegression.BriefingFitMatrix(token: string?): (string, number)
	return Fit.lane("BriefingFitMatrix", token, Fit.bodyBriefingFitMatrix)
end

-- ---------------------------------------------------------------------------
-- BriefingExclusionMatrix: compatibility alias for the shared HUD matrix.
-- ---------------------------------------------------------------------------
-- Current checks are delegated to Fit.bodyRoundHudMatrix. This entrypoint no
-- longer independently sweeps legacy briefing/terminal exclusion state or
-- developer-page keyboard captions. Those old claims are not current coverage.

function Fit.bodyBriefingExclusionMatrix(): (string, number)
	return Fit.bodyRoundHudMatrix()
end

function UIRegression.BriefingExclusionMatrix(token: string?): (string, number)
	return Fit.lane("BriefingExclusionMatrix", token, Fit.bodyBriefingExclusionMatrix)
end

-- ---------------------------------------------------------------------------
-- ObjectiveCornerMatrix
-- ---------------------------------------------------------------------------

-- ObjectiveCornerMatrix delegates to the shared HUD matrix. It stages the
-- current shared objective for Levels 1 through 4 across the device fixtures.
-- The legacy placement history below explains why the helper keeps a single
-- expected corner; the shared card reserves 16 px on touch or 24 px on PC.
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
-- touch, 18 on a pointer), within AnchorSlack. Shared callers reserve their
-- additional authored 16/24 px through Fit.anchorProblems rightInset.
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

function Fit.anchorProblems(rect, layout, label, rightInset: number?): {string}
	if not rect then return {label .. " was not measured"} end
	local problems = {}
	if rect.Width <= 0 or rect.Height <= 0 then return {label .. " has no drawable size"} end
	local inset = rightInset or 0
	local expected = UIDevice.TopRightPanel(rect.Width + inset, rect.Height)
	if math.abs(rect.Right - (expected.Right - inset)) > Fit.AnchorSlack or math.abs(rect.Top - expected.Top) > Fit.AnchorSlack then
		table.insert(problems, label .. " is outside its actual UIDevice.TopRightPanel slot")
	end
	if not Fit.within(rect, layout.Safe, 1) then table.insert(problems, label .. " escapes the safe area") end
	if layout.IsTouch then
		local zone = UIDevice.OverlapsMovementZone(rect.Left, rect.Top, rect.Right, rect.Bottom)
		if zone then table.insert(problems, label .. " overlaps " .. zone) end
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

-- UI_REGRESSION_20260923. The two stacks a round can actually draw, staged
-- through PuzzleUI's own status handler (UIRegressionPuzzleProbe) with the
-- server's own events and copy. The old staging wrote Visible on all three rows
-- AND a message at once -- five rows no round can produce: the only message left
-- is PuzzleManager's private refusal "You have no fuses", sent for an unfilled
-- box, and every box is filled before the lever row exists (team prompts moved to
-- the objective feed in 41fc4de). Since f3b8923 PuzzleUI's layout pass also
-- re-derives the panel and toggle from the round's counters, which undid those
-- writes in the lobby: 11 devices reported "Level1Objectives is not visible", and
-- 375x667 measured the leaked five-row stack past the control cluster.
Fit.Level1Phases = {
	{Name = "fuse phase, refusal message", Rows = {"FuseBoxStatus", "FuseCarryStatus"},
		Events = {{"begin", 3, 3}, {"carry", 0}}, Message = "You have no fuses"},
	{Name = "lever phase", Rows = {"FuseBoxStatus", "FuseCarryStatus", "LeverStatus"},
		Events = {{"begin", 3, 3}, {"boxes", 3, 3}, {"levers", 3}}},
}

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
function Fit.stageLevel1(device, phase): (any, string?)
	Fit.beat()
	local screen = findGui("PuzzleGui")
	if not screen then return nil, "PuzzleGui missing" end
	local probe = screen:FindFirstChild("UIRegressionPuzzleProbe")
	if not (probe and probe:IsA("BindableFunction")) then
		return nil, "PuzzleUI's UIRegressionPuzzleProbe is missing"
	end
	phase = phase or Fit.Level1Phases[#Fit.Level1Phases]
	local panel = screen:FindFirstChild("Level1Objectives")
	local pieces = {
		Screen = screen,
		Probe = probe,
		Phase = phase,
		Panel = panel,
		Toggle = screen:FindFirstChild("Level1ObjectivesToggle"),
		Title = panel and panel:FindFirstChild("ObjectiveTitle", true) or nil,
		Message = phase.Message and screen:FindFirstChild("PuzzleMessage", true) or nil,
		Rows = {},
	}
	-- The real handler, the server's events: the rows, the toggle and the panel
	-- come up because the round's counters did, as they do in a round.
	;(probe :: any):Invoke("reset")
	for _, event in ipairs(phase.Events) do
		(probe :: any):Invoke(table.unpack(event))
	end
	if panel then
		for _, name in ipairs(phase.Rows) do
			local row = panel:FindFirstChild(name, true)
			if row then table.insert(pieces.Rows, {Name = name, Object = row}) end
		end
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
	-- LAST, because the real message lives 1.8 s and re-lays the stack itself on
	-- both edges: sent after the nudge it is measured inside its own lifetime.
	if phase.Message then
		(probe :: any):Invoke("msg", phase.Message)
		task.wait(0.15)
	end
	return pieces, nil
end

-- The real round-end reset, so no staged row, counter or message can leak into
-- the next device (the leak the 375x667 row measured).
function Fit.unstageLevel1(pieces)
	if pieces and pieces.Probe then
		pcall(function() (pieces.Probe :: any):Invoke("reset") end)
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
	local phase = pieces.Phase or {Rows = Fit.Level1Rows}
	local message = phase.Message and take(pieces.Message, "PuzzleMessage") or nil
	local rows = {}
	for _, entry in ipairs(pieces.Rows) do
		local rect = take(entry.Object, entry.Name)
		if rect then table.insert(rows, {Name = entry.Name, Rect = rect}) end
	end
	-- An empty row set is the vacuum this whole helper exists to close, so a row
	-- that could not be staged is a FAILURE here rather than one fewer comparison.
	if #rows < #phase.Rows then
		table.insert(problems, string.format(
			"only %d of the %d objective rows this phase draws could be staged and measured",
			#rows, #phase.Rows))
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

function Fit.bodyRoundHudMatrix(): (string, number)
	local state = Fit.recorder("=== shared objective, feed and caption ===")
	local quiet, reason = Fit.awaitQuietDispatch()
	if not quiet then state.record(false, "quiet dispatch before borrowing", reason); return state.finish() end
	local saved = Fit.borrow()
	local ran, why = pcall(function()
		local probe = Fit.hudProbe()
		for _, device in ipairs(Fit.Devices) do
			state.record(Fit.apply(device), device.Name .. ": override applied")
			for _, level in ipairs({1, 2, 3, 4}) do
				Fit.stageRoundObjective(level)
				task.wait(0.12)
				local gui = findGui("RoundHud")
				local root = gui and gui:FindFirstChild("ObjectiveCard")
				state.record(root ~= nil and root.Visible and gui.Enabled, device.Name .. ": level " .. level .. " actual objective visible")
				if root and root.Visible then
					local layout = UIDevice.Layout()
					local rect = UIRegression.ResolveRect(root, device.Size, layout.Inset.Y)
					-- RoundHud reserves an additional authored right margin inside the safe slot.
					-- Legacy objective callers retain their exact TopRightPanel edge above.
					local problems = Fit.anchorProblems(rect, layout, "ObjectiveCard", layout.IsTouch and 16 or 24)
					state.record(#problems == 0, device.Name .. ": exact shared safe slot", table.concat(problems, "; "))
					local absolute, rendered = Fit.live(root), Fit.engineRect(root)
					state.record(rendered and not rendered.Unresolvable and math.abs(rendered.Left - absolute.Left) <= 1
						and math.abs(rendered.Top - absolute.Top) <= 1
						and math.abs(rendered.Width - absolute.Width) <= 1 and math.abs(rendered.Height - absolute.Height) <= 1,
						device.Name .. ": native-frame resolver matches engine")
					if layout.IsTouch then
						local hit = root:FindFirstChild("Hit", true)
						state.record(hit ~= nil and hit.AbsoluteSize.X >= 44 and hit.AbsoluteSize.Y >= 44, device.Name .. ": objective expansion hit44")
					end
					for _, node in ipairs(root:GetDescendants()) do
						if node:IsA("TextLabel") and visibleChain(node) and node.Text ~= "" then
							state.record(not layout.IsTouch or node.TextSize >= 12, device.Name .. ": " .. node.Name .. " touch text floor")
							state.record(node.TextBounds.X <= node.AbsoluteSize.X + 1 and node.TextBounds.Y <= node.AbsoluteSize.Y + 1,
								device.Name .. ": " .. node.Name .. " real text fits", node.Text)
						end
					end
				end
			end
			-- Captions/feed use gameplay admission, not the objective-only fixture gate.
			if workspace:GetAttribute("RoundActive") == true then
				state.record(probe:Invoke("feed", {Kind="TEAM",Actor=Players.LocalPlayer.Name,Detail="found a CD",Key="ui-regression"}) == true,
					device.Name .. ": validated feed accepted")
				state.record(probe:Invoke("caption", "COMMAND CENTER", "Keep moving.") == true, device.Name .. ": caption accepted")
				task.wait()
				local gui = findGui("RoundHud")
				local caption = gui and gui:FindFirstChild("Caption")
				local feed = gui and gui:FindFirstChild("FeedRow1")
				state.record(caption ~= nil and caption.Visible, device.Name .. ": actual caption visible")
				state.record(not device.Touch or feed == nil or not feed.Visible, device.Name .. ": phone one feed/caption lane")
			else state.note("  skip native feed/caption admission outside a live round") end
		end
	end)
	pcall(resetScenario)
	Fit.restore(saved)
	task.wait(0.15)
	if not ran then state.record(false, "shared HUD lane ran", tostring(why)) end
	local residue, note = Fit.residue(saved)
	if note then state.note(note) end
	state.record(#residue == 0, "shared lane restored borrowed state", table.concat(residue, "; "))
	return state.finish()
end

function UIRegression.RoundHudMatrix(token: string?): (string, number)
	return Fit.lane("RoundHudMatrix", token, Fit.bodyRoundHudMatrix)
end

function Fit.bodyObjectiveCornerMatrix(): (string, number)
	return Fit.bodyRoundHudMatrix()
end

function UIRegression.ObjectiveCornerMatrix(token: string?): (string, number)
	return Fit.lane("ObjectiveCornerMatrix", token, Fit.bodyObjectiveCornerMatrix)
end

-- ---------------------------------------------------------------------------
-- DispatchCompactMatrix
-- ---------------------------------------------------------------------------

-- DispatchCompactMatrix is a compatibility alias for Fit.bodyRoundHudMatrix.
-- It no longer asserts the legacy phone-briefing maximum footprint below.
-- Keep DispatchReference as retained metadata; no current matrix reads it.
Fit.DispatchReference = {Width = 560, Height = 100}

function Fit.bodyDispatchCompactMatrix(): (string, number)
	return Fit.bodyRoundHudMatrix()
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
			.. " CanvasPosition, the reader state and the caption",
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
			-- HUD_B2_TOUCH (owner, 2026-10-08): the B2 LIGHT cell is the hit
			-- target itself, a GuiButton mounted as FlashlightPopup's direct child;
			-- the old torch's transparent TouchFlashlightToggle child is gone.
			local flashlightGui = findGui("FlashlightPopup")
			local flashlightTarget = flashlightGui
				and flashlightGui:FindFirstChild("FlashlightPower")
			if flashlightTarget and not flashlightTarget:IsA("GuiButton") then flashlightTarget = nil end
			local flashlightBeforeVisible = flashlightTarget
				and (flashlightTarget :: GuiObject).Visible or false
			local flashlightBeforeActive = flashlightTarget
				and (flashlightTarget :: GuiObject).Active or false
			record(flashlightTarget ~= nil and flashlightBeforeVisible and flashlightBeforeActive,
				"before the queue opens, the LIGHT cell is live (a drawn, active GuiButton)",
				string.format("button=%s visible=%s active=%s", tostring(flashlightTarget ~= nil),
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
				"opening QueueHostShade stands the LIGHT cell down (neither drawn nor active)",
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
				"closing the queue restores the LIGHT cell",
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
		-- Measured on a control the HARNESS owns, for the reason in the header.
		-- This row used to hide drawn[1], whichever control GetTagged listed first,
		-- and when that was FlashlightPower it failed: FlashlightController writes
		-- the torch's Visible every frame, so it was drawn again before the
		-- deferred refresh ran and the zone rightly never moved. Measured
		-- 2026-09-23: hiding TouchRunHold or TouchPOV fired twice, FlashlightPower
		-- 0 times (UI_REGRESSION_20260923).
		probeControl = Instance.new("Frame")
		local hider = probeControl
		hider.Name = "UIRegressionControlProbe"
		hider.AnchorPoint = Vector2.new(1, 1)
		hider.BackgroundTransparency = 1
		hider.Size = UDim2.fromOffset(64, 64)
		hider.Position = UDim2.new(1, -22, 1, -(before.Bottom - before.Top) - 120)
		hider.Parent = drawn[1].Parent
		UIDevice.RegisterControlRect("UIRegressionControlProbe", hider)
		task.wait(0.45)
		local withHider = zone()
		baseline = fires
		hider.Visible = false
		task.wait(0.45)
		local hiddenFires = fires - baseline
		local hiddenZone = zone()
		hider.Visible = true
		task.wait(0.45)
		local reshown = zone()
		record(hiddenFires >= 1 and hiddenZone.Count == (withHider.Count or 0) - 1,
			"hiding a registered control invalidates the zone rather than leaving a"
			.. " cached rectangle behind",
			string.format("%d fire(s) while the probe was hidden, count %s -> %s",
				hiddenFires, tostring(withHider.Count), tostring(hiddenZone.Count)))
		record(math.abs(reshown.Top - withHider.Top) < 0.5 and reshown.Count == withHider.Count,
			"...and showing it again settles back on the same rectangle",
			string.format("top %.0f (was %.0f), count %s (was %s)",
				reshown.Top, withHider.Top, tostring(reshown.Count), tostring(withHider.Count)))
		UIDevice.UnregisterControlRect(hider)
		hider:Destroy()
		probeControl = nil
		task.wait(0.3)

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
-- KitFanMatrix
-- ---------------------------------------------------------------------------

-- HUD_B2_TOUCH (owner, 2026-10-08): artifacts/hud-final-20261008/b2/B2-DESIGN.md
-- 7.4, with critic C9 and C13. The KIT fan (element 14 C) is one row of POTION,
-- MARKER and SCAN directly above the KIT cell, opened by the client-local player
-- attribute KitFanOpen. It is transient, never registered and never reserved,
-- so no other lane measures it. Two halves:
--   (a) ANALYTIC, at every touch row of Fit.Devices plus the 844x390 reference
--       phone the brief's numbers come from: where Layout().KitFan lands.
--   (b) LIVE, at the real viewport, and ONLY inside a live round started with
--       the playtest recipe (C13). Writing RoundActive / RoundLoadingState from
--       the lobby wakes every client listener on them, and putting the values
--       back does not undo what those listeners did. So the lane borrows
--       nothing but the three inventory attributes and KitFanOpen, and outside
--       a live round (b) is a SKIP.

-- Which movement zone `r` sits in, if any. ONE case is excused, by rule: Roblox's
-- 120 px jump (min axis > 500, every tablet). Its zone reaches up over the
-- grid's upper rank, so the KIT cell itself already sits in it, and the fan can
-- only open while KIT is drawn -- in a round, where NoiseReporter suppresses that
-- button. The fan then shares a corner the cluster has already claimed. Live,
-- the engine's button must also be MEASURED hidden (`engineJumpDrawn` false).
-- Returns the zone and whether it was excused.
function Fit.fanZone(layout, r, engineJumpDrawn: boolean?): (string?, boolean)
	local zone = UIDevice.OverlapsMovementZone(r.Left, r.Top, r.Right, r.Bottom)
	if zone ~= "Jump" then return zone, false end
	local safe, kit = layout.Safe, layout.ControlPlan.Slots.KitToggle
	local kitRect = {
		Left = safe.Right - kit.Right - kit.Width, Top = safe.Bottom - kit.Bottom - kit.Height,
		Right = safe.Right - kit.Right, Bottom = safe.Bottom - kit.Bottom,
	}
	if layout.Zones.Jump.Size > 70 and Fit.overlaps(kitRect, layout.Zones.Jump)
		and engineJumpDrawn ~= true then
		return nil, true
	end
	return zone, false
end

-- Everything that can be wrong with where Layout().KitFan lands, in one place,
-- so the fixtures and the live viewport are held to the same rules.
function Fit.kitFanProblems(layout, engineJumpDrawn: boolean?): ({string}, boolean)
	local problems = {}
	local fan, safe, plan = layout.KitFan, layout.Safe, layout.ControlPlan
	local kit = plan and plan.Slots and plan.Slots.KitToggle
	if not (fan and kit and plan.Fan) then
		return {"the layout publishes no KitFan, KitToggle slot or ControlPlan.Fan"}, false
	end
	if not Fit.within(fan, safe, 0.5) then
		table.insert(problems, "KitFan " .. Fit.text(fan) .. " leaves Safe " .. Fit.text(safe))
	end
	local zone, excused = Fit.fanZone(layout, fan, engineJumpDrawn)
	if zone then table.insert(problems, "KitFan sits in the " .. zone .. " movement zone") end
	-- The raw 40 % line plus UIDevice's THUMBSTICK_CLEARANCE (8), the guarantee
	-- every slot of the cluster carries, the fan included. Landscape only: in
	-- portrait the thumbstick is the bottom band, which the Thumbstick zone holds.
	if not layout.Portrait and fan.Left < layout.Display.Left + layout.Width * .4 + 8 then
		table.insert(problems, string.format("KitFan starts at x %.0f, left of the 40%% line + 8 (%.0f)",
			fan.Left, layout.Display.Left + layout.Width * .4 + 8))
	end
	if fan.Height < 44 then
		table.insert(problems, string.format("a fan item is %.0f px, under 44", fan.Height))
	end
	-- D2: one Gap above the KIT row, its right edge on KIT's right edge.
	local kitTop = safe.Bottom - kit.Bottom - kit.Height
	if math.abs(fan.Bottom - (kitTop - plan.Gap)) > 0.5
		or math.abs(fan.Right - (safe.Right - kit.Right)) > 0.5 then
		table.insert(problems, string.format(
			"KitFan bottom/right %.0f/%.0f, KIT's top less Gap/right are %.0f/%.0f",
			fan.Bottom, fan.Right, kitTop - plan.Gap, safe.Right - kit.Right))
	end
	return problems, excused
end

function Fit.bodyKitFanMatrix(): (string, number)
	local quiet, quietWhy = Fit.awaitQuietDispatch()
	if not quiet then
		return "=== KIT fan: not reached ===\n  FAIL " .. tostring(quietWhy)
			.. "\nTOTAL: 1 checks, 1 failed", 1
	end
	local state = Fit.recorder("=== KIT fan: one row above KIT, clear of every movement zone ===")
	local record = state.record
	local saved = Fit.borrow()
	local player = Players.LocalPlayer
	local hud = findGui("ProtectionHUD")
	local function drawn(object): boolean
		return object ~= nil and visibleChain(object)
			and object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1
	end
	-- The KIT touch nodes as the player had them, so the end of the lane can be
	-- held to them: ProtectionHUD derives these from the attributes put back
	-- below. (SHIELD is left out: its Active follows the shield's own clock.)
	local function hudState(): {[string]: string}
		local out = {}
		for _, name in ipairs({"KitToggle", "KitFan", "Fan_Potion", "Fan_Marker", "Fan_Scan"}) do
			local node = hud and hud:FindFirstChild(name, true)
			out[name] = node and string.format("visible=%s active=%s", tostring(node.Visible),
				tostring((node :: any).Active)) or "missing"
		end
		return out
	end
	local hudBefore = hudState()
	local shade: GuiObject? = nil
	local shadeWasVisible = false

	local ran, runError = pcall(function()
		-- (a) ANALYTIC. The 844x390 row is the brief's reference phone (safe
		-- 47..797 x 58..369), and its fan is stated as the literal the approved
		-- phone-level-3 frame draws, relative to the display's top-left.
		local rows = {}
		for _, device in ipairs(Fit.Devices) do
			if device.Touch then table.insert(rows, device) end
		end
		table.insert(rows, {Name = "844x390 landscape, the B2 reference phone",
			Size = Vector2.new(844, 390), Touch = true, Class = "phone", Portrait = false,
			Safe = {47, 0, 47, 21}, Topbar = {0, 58, 0, 0},
			Frames = {
				None = {0, 0, 844, 390}, DeviceSafeInsets = {47, 0, 797, 369},
				CoreUISafeInsets = {47, 58, 797, 369}, TopbarSafeInsets = {47, 0, 797, 58},
			},
			KitFan = {553, 185, 725, 237}})
		for _, device in ipairs(rows) do
			record(Fit.apply(device), device.Name .. ": the explicit fixture took", "timed out")
			local fixtureProblems = Fit.fixtureProblems(device)
			record(#fixtureProblems == 0,
				device.Name .. ": viewport, safe area and topbar are exactly the stated fixture",
				table.concat(fixtureProblems, "; "))
			local layout = UIDevice.Layout()
			local problems, excused = Fit.kitFanProblems(layout, nil)
			record(#problems == 0, device.Name .. ": KitFan is inside Safe, one Gap above KIT,"
				.. " right of the 40% line, >= 44 and clear of every movement zone",
				table.concat(problems, "; "))
			if excused then
				state.note("  note " .. device.Name .. ": the fan shares Roblox's 120 px jump corner"
					.. " with KIT itself; excused because the in-round cluster suppresses that button")
			end
			local stated = (device :: any).KitFan
			if stated and layout.KitFan then
				local display, fan = layout.Display, layout.KitFan
				record(math.abs(fan.Left - display.Left - stated[1]) < 0.5
					and math.abs(fan.Top - display.Top - stated[2]) < 0.5
					and math.abs(fan.Right - display.Left - stated[3]) < 0.5
					and math.abs(fan.Bottom - display.Top - stated[4]) < 0.5,
					string.format("%s: KitFan is x %d..%d, y %d..%d, the approved frame's tray",
						device.Name, stated[1], stated[3], stated[2], stated[4]),
					string.format("x %.0f..%.0f y %.0f..%.0f", fan.Left - display.Left,
						fan.Right - display.Left, fan.Top - display.Top, fan.Bottom - display.Top))
			end
		end

		-- (b) LIVE, inside a live round only (C13). Checked BEFORE anything is
		-- written for it.
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (workspace:GetAttribute("RoundActive") == true
			and workspace:GetAttribute("RoundLoadingState") == "ready"
			and player:GetAttribute("InRound") == true
			and player:GetAttribute("RoundEntryControlsReady") == true
			and player:GetAttribute("Escaped") ~= true
			and player:GetAttribute("Spectating") ~= true
			and humanoid ~= nil and humanoid.Health > 0) then
			state.note("  SKIP (b) the live KIT fan: not inside a live round. Start one with the"
				.. " playtest recipe and run KitFanMatrix there; from the lobby it would have to"
				.. " write RoundActive and RoundLoadingState (critic C13)")
			return
		end
		-- THE REAL DEVICE: the drawn fan is laid out for the real window, so it
		-- is compared with the real layout, never a fixture.
		for _, name in ipairs(BORROWED_WORKSPACE_ATTRIBUTES) do
			workspace:SetAttribute(name, nil)
		end
		workspace:SetAttribute("ForceTouchUI", true)
		local settle = 40
		while settle > 0 and (UIDevice.Layout().Synthetic or not UIDevice.Layout().IsTouch) do
			task.wait(0.05)
			settle -= 1
		end
		player:SetAttribute("KitFanOpen", false)
		player:SetAttribute("ZyntraSpeedPotions", 1)
		player:SetAttribute("ZyntraRouteMarkers", 1)
		player:SetAttribute("ZyntraOwnsEntityDetector", true)
		task.wait(0.5)
		local kit = hud and hud:FindFirstChild("KitToggle")
		local fan = hud and hud:FindFirstChild("KitFan")
		local items = {}
		for _, name in ipairs({"Fan_Potion", "Fan_Marker", "Fan_Scan"}) do
			items[name] = fan and fan:FindFirstChild(name, true)
		end
		record(kit ~= nil and fan ~= nil and items.Fan_Potion ~= nil and items.Fan_Marker ~= nil
			and items.Fan_Scan ~= nil, "ProtectionHUD mounted KitToggle, KitFan and the three fan items",
			string.format("hud=%s kit=%s fan=%s", tostring(hud ~= nil), tostring(kit ~= nil), tostring(fan ~= nil)))
		if not (kit and fan and items.Fan_Potion and items.Fan_Marker and items.Fan_Scan) then return end
		record(drawn(kit) and (kit :: any).Active == true,
			"with one of each item lent, KIT is drawn and active",
			string.format("visible=%s active=%s", tostring(kit.Visible), tostring((kit :: any).Active)))
		record(not drawn(fan), "...and the fan is closed while KitFanOpen is false")

		local touchGui = playerGui():FindFirstChild("TouchGui")
		local engineJump = touchGui and touchGui:FindFirstChild("JumpButton", true)
		local engineJumpDrawn = engineJump ~= nil and visibleChain(engineJump)
		player:SetAttribute("KitFanOpen", true)
		task.wait(0.35)
		local layout = UIDevice.Layout()
		local fanRect = Fit.live(fan)
		record(player:GetAttribute("KitFanOpen") == true and drawn(fan),
			"KitFanOpen = true, the attribute KIT's own tap writes, opens the fan",
			string.format("attribute=%s visible=%s", tostring(player:GetAttribute("KitFanOpen")),
				tostring(fan.Visible)))
		local want = layout.KitFan
		record(want ~= nil and math.abs(fanRect.Left - want.Left) <= 1 and math.abs(fanRect.Top - want.Top) <= 1
			and math.abs(fanRect.Right - want.Right) <= 1 and math.abs(fanRect.Bottom - want.Bottom) <= 1,
			"the drawn fan is Layout().KitFan within 1 px",
			Fit.text(fanRect) .. " vs " .. Fit.text(want))
		local problems, excused = Fit.kitFanProblems(layout, engineJumpDrawn)
		record(#problems == 0, "at the real viewport KitFan is inside Safe, one Gap above KIT,"
			.. " right of the 40% line, >= 44 and clear of every movement zone",
			table.concat(problems, "; "))
		if excused then
			state.note("  note the open fan shares Roblox's 120 px jump corner with KIT; that button"
				.. " was measured hidden")
		end
		local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		-- Drawn, not necessarily Active: a potion used this round or a scan
		-- cooling down draws its item EMPTY / COOLDOWN, and that is correct.
		for name, item in pairs(items) do
			local r = Fit.live(item)
			record(drawn(item) and r.Width >= 44 and r.Height >= 44,
				name .. " is drawn and at least 44x44",
				string.format("visible=%s active=%s %s; Remotes.RouteMarker=%s Remotes.ZyntraDetector=%s",
					tostring(item.Visible), tostring((item :: any).Active), Fit.text(r),
					tostring(remotes ~= nil and remotes:FindFirstChild("RouteMarker") ~= nil),
					tostring(remotes ~= nil and remotes:FindFirstChild("ZyntraDetector") ~= nil)))
			local zone = Fit.fanZone(layout, r, engineJumpDrawn)
			record(zone == nil, name .. " is clear of every movement zone", zone and (zone .. " zone") or nil)
		end
		do
			local shopUI = game:GetService("ReplicatedStorage"):FindFirstChild("ZyntraShopUI")
			local binder = shopUI and shopUI:FindFirstChild("ShopBinder")
			local teal = binder and (require(binder :: any) :: any).Palette.RailTeal
			local face = (kit :: any).BackgroundColor3
			local glyph = kit:FindFirstChild("Glyph", true)
			record(teal ~= nil and math.abs(face.R - teal.R) < 0.01 and math.abs(face.G - teal.G) < 0.01
				and math.abs(face.B - teal.B) < 0.01 and (kit :: any).BackgroundTransparency < 0.01
				and glyph ~= nil and (glyph :: any).Text == "\u{D7}",
				"the open KIT face is solid RailTeal with the \u{D7} glyph",
				string.format("face %s at %.2f, glyph %q", tostring(face), (kit :: any).BackgroundTransparency,
					glyph and tostring((glyph :: any).Text) or "missing"))
		end
		local panel = UIDevice.TopRightPanel(240, 300)
		record(want ~= nil and panel.Bottom <= want.Top - 8 + 0.5,
			"an objective readout (TopRightPanel 240x300) stops 8 above the open fan",
			string.format("panel bottom %.0f, fan top %.0f", panel.Bottom, want and want.Top or -1))
		-- C9: ProtectionHUD seats the refusal tag at ModalArea's bottom centre,
		-- which on a phone lies on the open fan, so while it is open the tag
		-- stands 8 above it. The tag is measured where it is SEATED (it is only
		-- drawn for two seconds after a refusal): its bottom is its anchor, so
		-- the seat's vertical edge is exact whatever width the text takes.
		local caption = hud and hud:FindFirstChild("EquipmentCaption")
		local seat = caption and UIRegression.ResolveRect(caption, layout.Viewport, layout.Inset.Y)
		record(seat ~= nil and seat.Unresolvable == nil and want ~= nil and not Fit.overlaps(seat, want),
			"the refusal tag's seat (HUD_PC/EquipmentCaption) stays clear of the open fan (critic C9)",
			seat and (seat.Unresolvable or Fit.text(seat)) or "no EquipmentCaption mounted")

		-- OWNED ITEMS ONLY: the potion goes, and the other two keep their seats.
		-- The Items list is right-aligned (D2), so dropping the leftmost item
		-- moves nothing and SCAN stays on KIT's right edge.
		local marker, scan = Fit.live(items.Fan_Marker), Fit.live(items.Fan_Scan)
		local boost = player:GetAttribute("ZyntraSpeedBoostUntil")
		local potionBusy = player:GetAttribute("ZyntraSpeedPotionUsedThisRound") == true
			or (type(boost) == "number" and boost > workspace:GetServerTimeNow())
		player:SetAttribute("ZyntraSpeedPotions", 0)
		task.wait(0.35)
		if potionBusy then
			state.note("  SKIP Fan_Potion hiding: a potion was used or is running this round, so"
				.. " POTION stays drawn (USED / ACTIVE) by design")
		else
			record(not drawn(items.Fan_Potion) and (items.Fan_Potion :: any).Active ~= true,
				"with no potion left, Fan_Potion is neither drawn nor active",
				string.format("visible=%s active=%s", tostring(items.Fan_Potion.Visible),
					tostring((items.Fan_Potion :: any).Active)))
		end
		local markerAfter, scanAfter = Fit.live(items.Fan_Marker), Fit.live(items.Fan_Scan)
		record(drawn(items.Fan_Marker) and drawn(items.Fan_Scan)
			and math.abs(markerAfter.Left - marker.Left) <= 1 and math.abs(scanAfter.Left - scan.Left) <= 1
			and math.abs(scanAfter.Right - fanRect.Right) <= 1,
			"MARKER and SCAN stay packed toward KIT",
			string.format("marker %s (was %s), scan %s, fan right %.0f", Fit.text(markerAfter),
				Fit.text(marker), Fit.text(scanAfter), fanRect.Right))

		-- A SCREEN-OWNING MODAL, through production's own choke point (see
		-- ControlZoneMatrix): the fan cannot stay open under it.
		local roundGui = findGui("RoundGui")
		shade = roundGui and roundGui:FindFirstChild("QueueHostShade") :: any
		record(shade ~= nil, "the party dialog's shade is reachable to drive",
			roundGui and "no QueueHostShade" or "no RoundGui")
		if not shade then return end
		shadeWasVisible = shade.Visible
		local function anyActive(): string?
			for _, node in ipairs({kit, fan, items.Fan_Potion, items.Fan_Marker, items.Fan_Scan}) do
				if drawn(node) or (node :: any).Active == true then return node.Name end
			end
			return nil
		end
		shade.Visible = true
		task.wait(0.35)
		local during = anyActive()
		record(player:GetAttribute("KitFanOpen") ~= true,
			"opening QueueHostShade forces KitFanOpen false",
			tostring(player:GetAttribute("KitFanOpen")))
		record(during == nil, "...and neither KIT nor the fan is drawn or active under it",
			during and (during .. " is still drawn or active") or nil)
		shade.Visible = false
		task.wait(0.35)
		record(player:GetAttribute("KitFanOpen") ~= true and not drawn(fan),
			"closing the shade leaves the fan closed",
			string.format("attribute=%s visible=%s", tostring(player:GetAttribute("KitFanOpen")),
				tostring(fan.Visible)))
		record(drawn(kit) and (kit :: any).Active == true, "...and KIT is back",
			string.format("visible=%s active=%s", tostring(kit.Visible), tostring((kit :: any).Active)))
	end)

	if shade then (shade :: GuiObject).Visible = shadeWasVisible end
	Fit.restore(saved)
	task.wait(0.35)
	if not ran then
		state.Failures += 1
		state.Checks += 1
		state.note("  FAIL the KIT fan matrix ran  (" .. tostring(runError) .. ")")
	end
	local residue, residueNote = Fit.residue(saved)
	if residueNote then state.note(residueNote) end
	local hudAfter = hudState()
	for name, was in pairs(hudBefore) do
		if hudAfter[name] ~= was then
			table.insert(residue, string.format("ProtectionHUD.%s %s, was %s", name, hudAfter[name], was))
		end
	end
	record(#residue == 0,
		"the matrix restored every borrowed attribute, gui state and the KIT touch nodes",
		table.concat(residue, "; "))
	return state.finish()
end

function UIRegression.KitFanMatrix(token: string?): (string, number)
	return Fit.lane("KitFanMatrix", token, Fit.bodyKitFanMatrix)
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
		Fit.stageRoundObjective(3)
		local gui = findGui("RoundHud")
		local root = gui and gui:FindFirstChild("ObjectiveCard")
		record(root ~= nil and root.Visible, "shared objective exists before modal gate")
		player:SetAttribute("ZyntraStoreOpen", true)
		game:GetService("RunService").Heartbeat:Wait()
		game:GetService("RunService").Heartbeat:Wait()
		record(root ~= nil and not root.Visible, "shared objective yields to modal within2 heartbeats")
		player:SetAttribute("ZyntraStoreOpen", nil)
		task.wait(.15)
		record(root ~= nil and root.Visible, "shared objective recovers after modal")
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
		if scenario.LiveLobby and not Fit.liveLobbyEligible(outerSaved.Player.InRound) then
			table.insert(report, string.format("%-28s skip  (live lobby only; Friend Boost requires"
				.. " no active/loading round and a body inside the lobby)", scenario.Name))
			continue
		end
		-- HUD_B3 (owner, 2026-10-08): a LiveRound row measures Round HUD, which
		-- draws only on a living body in an active round. The sweep's own reset
		-- clears InRound and Spectating locally, so those are read from the outer
		-- snapshot; RoundActive is never written by the harness.
		if scenario.LiveRound then
			if not Fit.liveRoundEligible(outerSaved.Player.InRound,
				outerSaved.Player.Spectating, outerSaved.Player.Escaped) then
				table.insert(report, string.format("%-28s skip  (live round only; start one with the"
					.. " playtest recipe)", scenario.Name))
				continue
			end
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
		-- A control that is ACTIVE but SHIELDED (RAIL_OVER_WINDOWS_20261007). Scan
		-- cannot see an input shield: a transparent Active Dim is skipped as faded
		-- and WindowHolder is an exempt overlay, so a rail button under an open
		-- window's Dim passed the two checks above while every real tap on it was
		-- swallowed. Hit-test its centre instead, topmost first: the first hit
		-- that is the control (or inside it) passes; the first Active hit that is
		-- not fails, since that is what takes the tap. Hits that are not Active
		-- (decoration drawn above the rail) let the tap through and are passed
		-- over. Same coordinate space as AbsolutePosition, which Rects carry.
		for _, fragment in ipairs(scenario.RequiresTopmost or {}) do
			local rect = findRect(fragment)
			local name = rect and (rect.Name or rect.Path:match("([^.]+)$"))
			local problem: string? = "was not measured"
			if rect and name then
				problem = "is not hit at its own centre"
				for _, hit in ipairs((playerGui() :: PlayerGui):GetGuiObjectsAtPosition(
					(rect.Left + rect.Right) / 2, (rect.Top + rect.Bottom) / 2)) do
					if hit.Name == name or hit:FindFirstAncestor(name) then
						problem = nil
						break
					elseif hit.Active then
						problem = "is under " .. hit:GetFullName()
						break
					end
				end
			end
			if problem then
				table.insert(contractProblems, "SHIELDED: " .. fragment .. " " .. problem)
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
	-- Run the shared HUD matrix once. The four compatibility aliases delegate
	-- to that same body, so repeating them would repeat identical fixture work.
	-- This lane measures current shared objectives and admitted feed/captions.
	local hudReport, hudFailures = UIRegression.RoundHudMatrix(lease.Token)
	table.insert(report, hudReport)
	failures += hudFailures

	-- The live cluster, last: it is the only lane that parents an instance into
	-- the HUD, and it runs at the REAL viewport rather than a fixture, so
	-- anything measured while it is up would be measuring it.
	local zoneReport, zoneFailures = UIRegression.ControlZoneMatrix(lease.Token)
	table.insert(report, zoneReport)
	failures += zoneFailures
	-- Right after the live cluster: the KIT fan sits on top of it. Its live half
	-- runs only inside a live round and is a SKIP note anywhere else (critic C13).
	-- HUD_B2_TOUCH (owner, 2026-10-08).
	local fanReport, fanFailures = UIRegression.KitFanMatrix(lease.Token)
	table.insert(report, fanReport)
	failures += fanFailures
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
	-- residue is ASSERTED rather than assumed -- every
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

-- Any single lane, compactly. `UIRegression.Compact("BriefingExclusionMatrix")`.
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
