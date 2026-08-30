-- Round Completion Routing
--
-- Every rule the post-win path depends on, as pure functions that can be
-- asserted without teleporting anybody. GameManager owns the timers, the world
-- and the TeleportService calls; this module owns the questions:
--
--   * where does this level lead?
--   * who is in this result window, and what did each of them decide?
--   * how many players is the destination still waiting for?
--   * who owns an unfinished transfer, and which attempt was it?
--
-- Three properties are load-bearing, and each replaced something that failed:
--
-- 1. THE ROSTER IS IMMUTABLE. Membership of a result window is frozen when the
--    window opens and is never removed from. The old code dropped a player from
--    the eligible set on PlayerRemoving, so a player who pressed Continue,
--    departed, and left the source server disappeared from the roster entirely
--    -- and the settlement then told the destination to expect one fewer player
--    than was actually coming. The destination could start on that undercount
--    and a later continuer walked into a running round as a spectator. What
--    changes here is a player's DECISION, never their membership.
--
-- 2. A TRANSFER CLAIM IS NOT A REPORT OF SUCCESS. TeleportAsync returning
--    without an error only means Roblox accepted the request. A claim stays
--    PENDING until something resolves it.
--
-- 3. EVERY OUTBOUND ATTEMPT IS IDENTIFIED. TeleportInitFailed can arrive twice
--    for one request, and can arrive for a request the caller has already given
--    up on. Correlating a failure to an attempt id is what stops a late
--    next-level callback from poisoning the fresh lobby claim that replaced it,
--    and what stops one failure being counted twice.

local Routing = {}

-- Bumped whenever the rules below change shape. GameManager publishes this on
-- Workspace at load and answers a live probe with it, which is how the suite
-- proves the production host really requires this module.
Routing.Version = "2026-08-29.3"
Routing.LoadedAttribute = "RoundCompletionRoutingVersion"
-- The host also answers a BindableFunction under this name in ServerStorage. An
-- OnInvoke handler cannot be saved into a place file, so a reply can only come
-- from a host that is running right now and holding this module.
Routing.ProbeName = "RoundCompletionRoutingProbe"

-- The campaign ends at Level 3. There is no Level 4, so the last level offers
-- no Continue and no automatic route onward.
Routing.MaxLevel = 3
Routing.PostWinSeconds = 15

-- How long past the source server's decision deadline the destination keeps
-- staging arrivals. This covers Roblox's own transport latency only; it is not
-- a second decision window.
Routing.TransportGraceSeconds = 6
-- A destination must never hang on a deadline it cannot verify. Measured from
-- the FIRST arrival, this bounds the staging window whatever the packet said.
Routing.AdmissionLocalCapSeconds = 34
-- With nobody at all on the destination, give the transport this long before
-- concluding the party is never coming.
Routing.AdmissionEmptySeconds = 40
-- A pending attempt that neither succeeds nor reports a failure has to end
-- somewhere, or the settlement would wait on it forever. These three numbers
-- are one policy and are checked against each other by SettlementCoversTimeout:
-- the watchdog sweeps on its interval, an attempt goes stale after the timeout,
-- and an endpoint that waits for settlement must wait long enough for both to
-- have happened. Setting them independently is how the previous version came to
-- run its expiry pass five seconds BEFORE anything could possibly be stale.
Routing.TransferTimeoutSeconds = 25
Routing.WatchdogIntervalSeconds = 5
-- A COHORT-BOUND attempt is different in kind from a lobby transfer, and the
-- difference is a deadline somebody else is holding. A continuer travelling to
-- the reserved next-level server has to be there before the destination admits
-- the party; a player going home has nobody waiting on them. Detecting a silent
-- cohort attempt on the lobby schedule (25s stale + a 5s sweep + a 1s retry
-- delay = a retry dispatched 31s later) meant the retry could not possibly
-- arrive inside the destination's admission grace -- so the destination froze
-- its roster and started the round, and the retried player walked in as a
-- spectator. That is the whole of release blocker A1: two halves of one
-- protocol that were never checked against each other.
--
-- These two numbers and Routing.CohortArrivalHorizonSeconds() below are one
-- policy; AdmissionCoversCohortHorizon asserts they still agree.
--
-- 6 seconds, not 4, and measured from the moment Roblox ACCEPTED the request
-- rather than from the moment we started asking (see Routing.RestampAttempt).
-- TeleportAsync yields, and a dispatch that merely took its time would
-- otherwise be charged a failure and re-dispatched underneath a transfer that
-- was about to succeed.
Routing.CohortDestination = "next"
Routing.CohortTransferTimeoutSeconds = 6
Routing.CohortWatchdogIntervalSeconds = 1
-- How much of TeleportAsync's OWN yield the attempt clock may be re-anchored
-- across. This number exists because the horizon below is measured from the
-- source's decision DEADLINE, while the stale clock is measured from the moment
-- Roblox ACCEPTED the request -- and those are not the same instant.
--
-- Routing.RestampAttempt moves StartedAt forward to acceptance so a dispatch
-- that merely took its time is not charged a failure. Unclamped, that made the
-- declared horizon a lie: a press at the deadline whose TeleportAsync yielded Y
-- seconds could not be re-dispatched until deadline + Y + 8, and the packet had
-- already told the destination to stop staging at deadline + 14. Any Y > 0 broke
-- it, and Y is not something this server controls.
--
-- Clamping the re-anchor bounds Y at the source. Past this grace the attempt is
-- dated as if acceptance had happened here, so the whole lineage stays inside
-- the horizon whatever TeleportAsync does. The cost is the one it was protecting
-- against -- an accept slower than the grace can still be re-dispatched
-- underneath -- and that is the honest trade: a bounded, declared horizon cannot
-- also grant unbounded yield tolerance. The retry is still guarded by
-- env.Present, so a player Roblox actually moved is not re-sent.
Routing.CohortAcceptGraceSeconds = 4
-- A claim that was TAKEN and never dispatched has no attempt to report on and
-- no attempt to time out, so neither the callback path nor the stale-attempt
-- path can ever end it. It gets its own bound, measured from the claim.
Routing.UnstartedClaimTimeoutSeconds = 10
-- How long an authorised retry waits before it re-dispatches. Owned here rather
-- than hard-coded at the call site, because the settlement wait below has to
-- account for it: a retry that starts one second after a sweep pushes the end
-- of the lineage a whole second later, and a settlement that does not know that
-- returns while the retry is still in flight.
Routing.RetryDelaySeconds = 1
-- How long the sweep leaves an authorised retry alone before concluding the
-- handoff itself died (the scheduling thread was cancelled, the coroutine
-- errored). Must exceed RetryDelaySeconds or the sweep would steal every retry
-- it authorised; must be finite or a lost handoff would hold the claim forever.
Routing.RetryHandoffGraceSeconds = 6
-- How many times the sweep will re-hand-out a plan whose owner never acted
-- before it spends the retry budget instead. Bounded so a claim whose authority
-- keeps dying escalates to its fallback rather than being re-offered forever.
Routing.MaxHandoffTakeovers = 1

-- One authoritative retry, then one authoritative fallback, then local recovery.
-- Declared with the timings rather than beside the retry policy, because the
-- settlement wait below is computed FROM it: raising the retry budget without
-- lengthening the wait is how an endpoint comes to return while a claim it is
-- responsible for is still in flight.
Routing.MaxTransferRetries = 1

-- How often the settlement loop re-examines the claims it is waiting on.
Routing.SettlementPollSeconds = 0.25

-- One attempt costs a stale window plus the sweep that has to notice it.
function Routing.AttemptWindowSeconds(): number
	return Routing.TransferTimeoutSeconds + Routing.WatchdogIntervalSeconds
end

-- The stale threshold THIS claim's destination earns. A cohort attempt is held
-- to the tighter one, because a destination is waiting on it.
function Routing.TimeoutForDestination(destination): number
	if destination == Routing.CohortDestination then
		return Routing.CohortTransferTimeoutSeconds
	end
	return Routing.TransferTimeoutSeconds
end

-- The watchdog has to tick at least as often as the SHORTEST threshold in play,
-- or the tighter cohort timeout is decoration: a 4-second stale attempt noticed
-- by a 5-second sweep is a 9-second detection.
function Routing.SweepIntervalSeconds(): number
	return math.min(Routing.WatchdogIntervalSeconds, Routing.CohortWatchdogIntervalSeconds)
end

-- THE number that ties the source's retry policy to the destination's staging
-- window: the last moment a member of a settled cohort can still land, measured
-- from the source's decision deadline. A cohort attempt dispatched at the very
-- end of the window goes silent, is noticed one sweep after it goes stale, is
-- re-dispatched one retry delay later, and then needs the transport grace to
-- arrive. There is exactly one retry, so this is finite by construction and
-- nothing extends it.
function Routing.CohortArrivalHorizonSeconds(): number
	return Routing.CohortAcceptGraceSeconds
		+ Routing.CohortTransferTimeoutSeconds
		+ Routing.CohortWatchdogIntervalSeconds
		+ Routing.RetryDelaySeconds
		+ Routing.TransportGraceSeconds
end

-- The worst case for ONE claim's whole lineage: every attempt it is allowed
-- goes completely silent, each retry costs its delay on top, and the last
-- handoff may sit its full grace before the sweep re-drives it.
function Routing.LineageWorstCaseSeconds(): number
	local attempts = Routing.MaxTransferRetries + 1
	return Routing.AttemptWindowSeconds() * attempts
		+ Routing.RetryDelaySeconds * Routing.MaxTransferRetries
		+ Routing.RetryHandoffGraceSeconds
end

-- The budget one claim lineage gets: first attempt, retry delay, retry, and the
-- sweeps that notice each. 25+5 +1+ 25+5 +6 = 67, so 70 leaves a little slack.
Routing.SettlementLineageSeconds = 70
-- A refused NEXT-level lineage earns a lobby fallback, and that fallback is a
-- lineage of its own. Two is the most any claim can produce, because a lobby
-- transfer has no fallback of its own.
Routing.SettlementMaxLineages = 2
-- The absolute ceiling. Reaching it is not "give up": ForceSettle resolves every
-- claim still open and hands its player to local recovery, so ownership is
-- transferred rather than dropped. Nothing may extend this by re-claiming.
Routing.SettlementHardCapSeconds = 145

-- Kept as the single number the old fixed wait used to be, so anything still
-- asking "how long does an endpoint wait" gets the lineage budget rather than
-- the 35 seconds that covered only the first attempt.
Routing.SettlementWaitSeconds = Routing.SettlementLineageSeconds

function Routing.SettlementCoversTimeout(): boolean
	return Routing.SettlementLineageSeconds
		>= Routing.TransferTimeoutSeconds + Routing.WatchdogIntervalSeconds
end

-- The invariant that actually matters, and the one the old policy failed: the
-- budget must cover not just an attempt going stale, but the RETRY that attempt
-- earns going stale as well -- and the hard cap must cover every lineage a
-- single claim can produce.
function Routing.SettlementCoversRetryLineage(): boolean
	return Routing.SettlementLineageSeconds >= Routing.LineageWorstCaseSeconds()
		and Routing.SettlementHardCapSeconds
			>= Routing.SettlementLineageSeconds * Routing.SettlementMaxLineages
				+ Routing.WatchdogIntervalSeconds
		and Routing.WatchdogIntervalSeconds > 0
		and Routing.WatchdogIntervalSeconds < Routing.TransferTimeoutSeconds
		and Routing.RetryDelaySeconds > 0
		-- The sweep must never steal a retry it authorised itself.
		and Routing.RetryHandoffGraceSeconds > Routing.RetryDelaySeconds
		-- The tighter cohort schedule must still be a schedule: noticed before
		-- it is stale, and stale before the lobby threshold it replaces.
		and Routing.CohortWatchdogIntervalSeconds > 0
		and Routing.CohortWatchdogIntervalSeconds < Routing.CohortTransferTimeoutSeconds
		and Routing.CohortTransferTimeoutSeconds <= Routing.TransferTimeoutSeconds
		-- A claim that never dispatched has to end sooner than the settlement
		-- budget it would otherwise sit inside.
		and Routing.UnstartedClaimTimeoutSeconds > 0
		and Routing.UnstartedClaimTimeoutSeconds < Routing.SettlementLineageSeconds
end

-- The OTHER half of the same protocol, and the one that was never written down:
-- the destination's staging window has to be long enough to contain the source's
-- bounded retry horizon, or the source can be doing everything correctly and
-- still miss the round.
--
-- The transport grace stays small on purpose -- it is not a second decision
-- window -- so the extra waiting is not granted generally. It is granted only
-- when the destination holds an AUTHORITATIVE cohort count and can see that
-- somebody named in it has not arrived, and it is bounded by this horizon and by
-- the local staging cap underneath it.
function Routing.AdmissionCoversCohortHorizon(): boolean
	return Routing.CohortArrivalHorizonSeconds() > Routing.TransportGraceSeconds
		-- The accept grace has to be inside the horizon, and has to be a real
		-- allowance: at zero the clamp would date every attempt at its dispatch
		-- and the re-anchor would do nothing at all.
		and Routing.CohortAcceptGraceSeconds > 0
		and Routing.CohortArrivalHorizonSeconds()
			> Routing.CohortAcceptGraceSeconds + Routing.TransportGraceSeconds
		and Routing.AdmissionLocalCapSeconds
			>= Routing.PostWinSeconds + Routing.CohortArrivalHorizonSeconds()
		and Routing.AdmissionEmptySeconds >= Routing.AdmissionLocalCapSeconds
		and Routing.TransportGraceSeconds > 0
end

-- How much cohort authority a packet carries. A packet marked FinalCohort was
-- written by the settlement sweep, which knows the exact head count; anything
-- else is an estimate made while players were still deciding.
Routing.EstimateAuthority = 0
Routing.FinalAuthority = 1

function Routing.PacketAuthority(data): number
	if type(data) == "table" and data.FinalCohort == true then return Routing.FinalAuthority end
	return Routing.EstimateAuthority
end

-- ---------------------------------------------------------------------------
-- Level chain
-- ---------------------------------------------------------------------------

function Routing.NextLevel(level: number?): number?
	local current = tonumber(level)
	if not current then return nil end
	if current < 1 or current >= Routing.MaxLevel then return nil end
	return current + 1
end

function Routing.OffersContinue(level: number?): boolean
	return Routing.NextLevel(level) ~= nil
end

function Routing.ClampLevel(level: any): number
	local requested = tonumber(level)
	if not requested then return 1 end
	return math.clamp(math.floor(requested), 1, Routing.MaxLevel)
end

-- ---------------------------------------------------------------------------
-- The session roster
-- ---------------------------------------------------------------------------

Routing.Deciding = "deciding"
Routing.Returning = "returning"
Routing.Continuing = "continuing"
Routing.Gone = "gone"

local TERMINAL_FROM_DECIDING = {
	[Routing.Returning] = true,
	[Routing.Continuing] = true,
	[Routing.Gone] = true,
}

-- Freeze the participants of one result window. Order is preserved so every
-- derived list is stable, and nothing removes a member for the window's life.
function Routing.NewRoster(members)
	local roster = {Order = {}, Index = {}, Decision = {}, Departed = {}}
	for _, member in ipairs(members or {}) do
		if roster.Index[member] == nil then
			roster.Order[#roster.Order + 1] = member
			roster.Index[member] = #roster.Order
			roster.Decision[member] = Routing.Deciding
		end
	end
	return roster
end

function Routing.RosterSize(roster): number
	return #roster.Order
end

function Routing.RosterMembers(roster)
	local copy = {}
	for index, member in ipairs(roster.Order) do copy[index] = member end
	return copy
end

function Routing.InRoster(roster, member): boolean
	return roster.Index[member] ~= nil
end

function Routing.DecisionOf(roster, member)
	if roster.Index[member] == nil then return nil end
	return roster.Decision[member] or Routing.Deciding
end

function Routing.HasDeparted(roster, member): boolean
	return roster.Departed[member] == true
end

-- The ONLY way a decision changes. A member who has already been handed to
-- TeleportService is settled: nothing may move them again, including their own
-- second button press and including their disconnect.
function Routing.RecordDecision(roster, member, decision): boolean
	if roster.Index[member] == nil then return false end
	if roster.Departed[member] then return false end
	if not TERMINAL_FROM_DECIDING[decision] then return false end
	if (roster.Decision[member] or Routing.Deciding) ~= Routing.Deciding then return false end
	roster.Decision[member] = decision
	return true
end

-- A transfer this session started was rejected while the window was still open,
-- so the player gets their choice back. Never available once they have departed.
function Routing.ClearDecision(roster, member): boolean
	if roster.Index[member] == nil then return false end
	if roster.Departed[member] then return false end
	local current = roster.Decision[member] or Routing.Deciding
	if current ~= Routing.Returning and current ~= Routing.Continuing then return false end
	roster.Decision[member] = Routing.Deciding
	return true
end

-- Roblox accepted this player's transfer. Terminal.
function Routing.MarkDeparted(roster, member): boolean
	if roster.Index[member] == nil then return false end
	roster.Departed[member] = true
	return true
end

-- PlayerRemoving. A member who had already chosen keeps that choice -- leaving
-- IS how a Continue or a Back completes. Only somebody who never chose is gone.
function Routing.NoteDeparture(roster, member): boolean
	if roster.Index[member] == nil then return false end
	if roster.Departed[member] then return false end
	if (roster.Decision[member] or Routing.Deciding) ~= Routing.Deciding then return false end
	roster.Decision[member] = Routing.Gone
	return true
end

-- How many players the destination should expect from this session.
--
-- Note what is NOT consulted: whether a continuer is still connected. Somebody
-- who pressed Continue and has already left is on their way there; dropping
-- them from this count is precisely the undercount that let the destination
-- start a round before the rest of the cohort landed.
function Routing.ExpectedContinuers(roster, present): number
	present = present or function() return true end
	local expected = 0
	for _, member in ipairs(roster.Order) do
		local decision = roster.Decision[member] or Routing.Deciding
		if decision == Routing.Continuing then
			expected += 1
		elseif decision == Routing.Deciding and present(member) then
			expected += 1
		end
	end
	return expected
end

-- Split the frozen roster four ways at settlement.
--
--   departed   -- already handed to TeleportService; never moved again
--   continuing -- pressed Continue and not yet sent, or never chose and is here
--   returning  -- pressed Back and is still here to be sent
--   gone       -- left without choosing
function Routing.Partition(roster, present)
	present = present or function() return true end
	local continuing, returning, departed, gone = {}, {}, {}, {}
	for _, member in ipairs(roster.Order) do
		local decision = roster.Decision[member] or Routing.Deciding
		if roster.Departed[member] then
			departed[#departed + 1] = member
		elseif decision == Routing.Continuing then
			continuing[#continuing + 1] = member
		elseif decision == Routing.Returning then
			if present(member) then returning[#returning + 1] = member end
		elseif decision == Routing.Gone then
			gone[#gone + 1] = member
		elseif present(member) then
			continuing[#continuing + 1] = member
		end
	end
	return continuing, returning, departed, gone
end

-- The window may close before its deadline only when nobody is still deciding.
function Routing.Settled(roster, present): boolean
	present = present or function() return true end
	for _, member in ipairs(roster.Order) do
		local decision = roster.Decision[member] or Routing.Deciding
		if decision == Routing.Deciding and present(member) then return false end
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Session identity and admission
-- ---------------------------------------------------------------------------

function Routing.SessionId(jobId: any, serial: any): string
	return tostring(jobId or "studio") .. ":post-win:" .. tostring(tonumber(serial) or 0)
end

-- The teleport payload every continuer carries. `Final` marks the settlement
-- sweep's packet: at that point the source knows the head count exactly and the
-- destination may start as soon as that many have arrived.
function Routing.ArrivalPacket(state)
	local deadline = tonumber(state.Deadline)
	return {
		BackroomsRound = true,
		Level = Routing.ClampLevel(state.Level),
		EntryMode = state.EntryMode,
		RoundSessionId = tostring(state.SessionId),
		ExpectedContinuers = math.max(0, math.floor(tonumber(state.Expected) or 0)),
		DecisionDeadline = deadline,
		-- The last moment the source's own bounded retry could still deliver a
		-- member of this cohort. Sent rather than derived at the far end so the
		-- two servers do not have to be running the same build of this file --
		-- but the destination still clamps it to its OWN horizon, so a stale or
		-- malformed packet cannot buy an unbounded wait.
		CohortHorizon = deadline and (deadline + Routing.CohortArrivalHorizonSeconds()) or nil,
		FinalCohort = state.Final == true,
		PartySize = math.max(1, math.floor(tonumber(state.Expected) or 1)),
		GlowstickSlots = state.GlowstickSlots,
		LaunchToken = state.LaunchToken,
		TransferAttemptId = tonumber(state.AttemptId) or nil,
	}
end

local function packetOf(entry)
	local data = entry and entry.Data
	if type(data) ~= "table" then return nil end
	if data.BackroomsRound ~= true then return nil end
	return data
end

-- Group the destination's arrivals by session. Malformed packets are ignored, a
-- player counts once however many packets carry them, and the session with the
-- most members wins -- a reserved next-level server should only ever see one,
-- but a stray reconnect must not be able to take the round from it.
function Routing.SelectArrivalSession(entries)
	local bySession, order = {}, {}
	local seen = {}
	for _, entry in ipairs(entries or {}) do
		local data = packetOf(entry)
		local member = entry and entry.Member
		if data and member ~= nil and not seen[member] then
			seen[member] = true
			local id = tostring(data.RoundSessionId or data.LaunchToken or "unidentified")
			local group = bySession[id]
			if not group then
				group = {
					SessionId = id,
					Members = {},
					Level = Routing.ClampLevel(data.Level),
					EntryMode = data.EntryMode,
					Expected = nil,
					Deadline = nil,
					CohortHorizon = nil,
					Final = false,
					Authority = -1,
				}
				bySession[id] = group
				order[#order + 1] = id
			end
			group.Members[#group.Members + 1] = member
			-- AUTHORITY IS MONOTONIC. Packets arrive in transport order, not in
			-- the order they were written, so a stale estimate can land after
			-- the settlement's exact count. Once a final packet has been
			-- accepted for a session, no estimate may touch its head count or
			-- its finality again.
			--
			-- This is not hypothetical: a Back to Lobby that Roblox rejects is
			-- re-armed, which puts that player back among the continuers and
			-- makes the cohort GROW. An early continuer's packet, written
			-- before that happened, then says a smaller number -- and the old
			-- "smallest estimate wins" rule applied it over the final count and
			-- started the round with a player still in transit.
			local authority = Routing.PacketAuthority(data)
			local expected = tonumber(data.ExpectedContinuers)
			if expected then expected = math.max(0, math.floor(expected)) end
			if authority > group.Authority then
				group.Authority = authority
				group.Final = authority == Routing.FinalAuthority
				if expected then group.Expected = expected end
			elseif authority == group.Authority and expected then
				if authority == Routing.EstimateAuthority then
					-- Among estimates the smallest is the freshest: opting out
					-- and disconnecting only ever remove continuers.
					if group.Expected == nil or expected < group.Expected then
						group.Expected = expected
					end
				elseif expected > group.Expected then
					-- Two authoritative packets should be identical. If they are
					-- not, wait for the larger: admitting early is the failure
					-- that costs a player their round.
					group.Expected = expected
				end
			end
			local deadline = tonumber(data.DecisionDeadline)
			if deadline and (group.Deadline == nil or deadline > group.Deadline) then
				group.Deadline = deadline
			end
			-- The furthest horizon any member of this session declared. Taking
			-- the maximum is safe because ArrivalDecision clamps it to the
			-- destination's own bound before it is allowed to hold anything.
			local horizon = tonumber(data.CohortHorizon)
			if horizon and (group.CohortHorizon == nil or horizon > group.CohortHorizon) then
				group.CohortHorizon = horizon
			end
			if data.EntryMode ~= nil then group.EntryMode = data.EntryMode end
		end
	end
	local best
	for _, id in ipairs(order) do
		local group = bySession[id]
		if not best
			or #group.Members > #best.Members
			or (#group.Members == #best.Members and group.SessionId < best.SessionId)
		then
			best = group
		end
	end
	return best
end

-- Should the destination start the round yet?
--
--   "admit"   -- run the round with everybody who has arrived
--   "wait"    -- the source's decision window has not closed; keep staging
--   "abandon" -- nobody came and the transport had its chance
--
-- There is one case where staging outlasts the transport grace, and it is
-- narrow on purpose. A FINAL packet is the settlement sweep's: it names the
-- exact cohort. If that many have not arrived, the source is not "still
-- deciding" -- somebody's transfer was refused or dropped, and the source's
-- bounded retry may be carrying them right now. Admitting on the grace alone
-- freezes the roster and starts the round without them, which is the failure
-- this branch exists to stop. It is bounded twice over: by the horizon the
-- packet declares (clamped to the destination's own), and by the local staging
-- cap underneath it.
function Routing.ArrivalDecision(state)
	-- Two clocks on purpose. The caps are measured on the DESTINATION's own
	-- monotonic clock, because that is the only one it can trust; the source's
	-- decision deadline is compared on the shared server clock both ends read.
	local now = tonumber(state.Now) or 0
	local serverNow = tonumber(state.ServerNow)
	local arrived = math.max(0, math.floor(tonumber(state.Arrived) or 0))
	local expected = tonumber(state.Expected)
	local deadline = tonumber(state.Deadline)
	local firstArrivalAt = tonumber(state.FirstArrivalAt)
	local startedAt = tonumber(state.StartedAt) or now
	local grace = tonumber(state.Grace) or Routing.TransportGraceSeconds
	local localCap = tonumber(state.LocalCap) or Routing.AdmissionLocalCapSeconds
	local emptyCap = tonumber(state.EmptyCap) or Routing.AdmissionEmptySeconds

	if arrived == 0 then
		if now - startedAt >= emptyCap then return "abandon", "nobody arrived" end
		return "wait", "no arrivals yet"
	end

	-- The source told us exactly how many are coming and they are all here.
	if state.Final == true and expected and arrived >= expected then
		return "admit", "the full cohort arrived"
	end

	-- A destination must never hang on a clock it cannot verify.
	if firstArrivalAt and now - firstArrivalAt >= localCap then
		return "admit", "local staging cap reached"
	end

	if deadline and serverNow then
		if serverNow >= deadline + grace then
			-- TOKEN-AWARE. A count the source stated, and somebody it names is
			-- demonstrably missing.
			--
			-- This used to require `state.Final == true`, and that requirement had
			-- a hole big enough to lose a whole party through. When EVERY player
			-- presses Continue by hand, each one's first TeleportAsync succeeds,
			-- each is marked Departed at once, and Routing.Partition therefore
			-- reports NO continuers left at settlement -- so the source never
			-- sends a final packet at all, because there is nobody left to carry
			-- one. The destination then held only estimates, the Final branch
			-- never fired, and it admitted at deadline + transport grace: a late
			-- presser whose first attempt went silent was retried into a round
			-- that had already frozen its roster.
			--
			-- An estimate is enough to wait on because the wait itself is bounded
			-- twice over -- by the horizon below (clamped to this server's own
			-- ceiling, so a stale or hostile packet buys nothing) and by the local
			-- staging cap above. And an estimate can only ever SHRINK: among
			-- equal-authority packets SelectArrivalSession keeps the smallest, so
			-- a player who opts out lowers the bar rather than hanging the round.
			if expected and arrived < expected then
				local ceiling = deadline + Routing.CohortArrivalHorizonSeconds()
				local declared = tonumber(state.CohortHorizon)
				local horizon = (declared and declared < ceiling) and declared or ceiling
				if serverNow < horizon then
					return "wait", "the cohort is short and the source's retry horizon has not passed"
				end
				return "admit", "the source's retry horizon passed with the cohort still short"
			end
			return "admit", "the source's decision deadline plus transport grace passed"
		end
		return "wait", "the source's decision window is still open"
	end

	-- No deadline in the payload at all (a station launch, or a malformed
	-- packet). Fall back to the head count, then to the local cap above.
	if expected and arrived >= expected then
		return "admit", "the expected head count arrived"
	end
	return "wait", "waiting for the expected head count"
end

-- What may happen to the completed world after a group lobby transfer.
--
--   "released"    -- Roblox accepted the party. The reserved server and its
--                    world disappear on their own once the last player leaves.
--   "keep-world"  -- the transfer was refused and this is a reserved server, so
--                    there is no lobby here to recover into. The map stays
--                    under the players it could not move, and the per-player
--                    retry owns them. Tearing it down here -- which is what the
--                    old code did unconditionally -- deletes the floor beneath
--                    somebody Roblox has just declined to move.
--   "local-lobby" -- a public or Studio server, which really does own a lobby:
--                    clean the world and stand the players up in it.
--
-- The rule is the same at the Level 3 endpoint, after a loss, and on the
-- fallback out of a refused next-level transfer, because in all three the
-- question is only "did Roblox take them, and is there a lobby here?".
function Routing.TeardownPlan(state)
	local reserved = state.Reserved == true and state.Studio ~= true
	if state.Accepted == true and reserved then return "released" end
	if reserved then return "keep-world" end
	return "local-lobby"
end

-- Every place a round can end. All four hand their players to TeleportService
-- and all four must then settle: the completed world is not released, and the
-- endpoint is not finished, until no player on this server still holds an
-- unresolved claim. Naming them here is what stops a new endpoint being written
-- without a settlement wait -- the suite asserts the production host mentions
-- every one of them.
Routing.Endpoints = {
	Continuation = "continuation",  -- the settlement sweep into the next level
	Level3 = "level3",              -- the campaign endpoint: Back to Lobby only
	Loss = "loss",                  -- the party was wiped
	Fallback = "fallback",          -- a refused next-level transfer's lobby escape
}

-- What an endpoint has to do after its group transfer. There is one answer for
-- all four, which is the point: an endpoint cannot opt out of settling, and it
-- cannot invent its own timings.
function Routing.EndpointPlan(state)
	local endpoint = state.Endpoint
	if endpoint ~= Routing.Endpoints.Continuation
		and endpoint ~= Routing.Endpoints.Level3
		and endpoint ~= Routing.Endpoints.Loss
		and endpoint ~= Routing.Endpoints.Fallback then
		endpoint = nil
	end
	return {
		Endpoint = endpoint,
		-- Not optional anywhere. A pending claim outlives any endpoint that
		-- returns without waiting for it.
		Settle = true,
		-- The budget ONE claim lineage gets. Not a deadline the endpoint may
		-- freeze at entry: the settlement recomputes from the live claims, so a
		-- retry dispatched late is still inside the wait that is responsible
		-- for it. `WaitFor` is kept pointing at the same number for any reader
		-- that only wants "how long, roughly".
		LineageBudget = Routing.SettlementLineageSeconds,
		WaitFor = Routing.SettlementLineageSeconds,
		HardCap = Routing.SettlementHardCapSeconds,
		ExpireAfter = Routing.TransferTimeoutSeconds,
		Poll = Routing.SettlementPollSeconds,
		Teardown = Routing.TeardownPlan(state),
	}
end

-- ---------------------------------------------------------------------------
-- Transfer claims and attempts
-- ---------------------------------------------------------------------------

Routing.Pending = "pending"
Routing.Succeeded = "succeeded"
Routing.Failed = "failed"
-- Routing.MaxTransferRetries is declared with the timing policy above, because
-- Routing.SettlementWaitSeconds is derived from it.

local lastAttemptId = 0

-- Test hook: attempt ids only have to be unique, but a suite that asserts on
-- them wants to start from a known point.
function Routing.ResetAttemptIds()
	lastAttemptId = 0
end

-- A claim entry may be a state record (production) or a plain truthy marker
-- (synthetic rosters in tests). Only a claim that is still pending, or that
-- already succeeded, owns the player; a FAILED claim owns nobody and must not
-- keep its player out of the settlement sweep.
local function claimOwns(entry)
	if entry == nil or entry == false then return false end
	if type(entry) == "table" and entry.State ~= nil then
		return entry.State == Routing.Pending or entry.State == Routing.Succeeded
	end
	return true
end
Routing.ClaimOwns = claimOwns

-- Who the settlement sweep may still send to the lobby. A player who is
-- progressing, or who holds a live transfer claim, is somebody else's
-- responsibility -- including their own earlier Back to Lobby press.
function Routing.LobbyBound(present, progressing, claims)
	progressing = progressing or {}
	claims = claims or {}
	local bound = {}
	for _, member in ipairs(present or {}) do
		if not progressing[member] and not claimOwns(claims[member]) then
			bound[#bound + 1] = member
		end
	end
	return bound
end

-- `at` is when this claim was TAKEN, and it is the anchor everything bounded
-- about the claim is measured from.
--
-- It used to be absent, and that absence was release blocker A2. A claim whose
-- thread died before Routing.BeginAttempt -- a TeleportOptions constructor that
-- threw, a cancelled coroutine -- had a nil LineageStartedAt and a nil
-- StartedAt. Routing.SweepTransfers skipped it (nothing to time out), and
-- Routing.SettlementStatus fell back to `now`, so its hard-cap deadline moved
-- forward on EVERY poll. The claim was pending, invisible, and could never
-- expire: an endpoint holding the finished world awaited it forever.
--
-- The anchor is written once, at claim time, and nothing moves it later.
function Routing.ClaimTransfer(claims, member, destination, at)
	local record = claims[member]
	if record ~= nil and claimOwns(record) then return false, record end
	local claimedAt = tonumber(at)
	local fresh = {
		ClaimedAt = claimedAt,
		State = Routing.Pending,
		Destination = destination or "claim",
		-- A NEW claim starts clean. Carrying the previous claim's failure count
		-- forward is what let a next-level transfer that had already used up its
		-- retries hand a fresh lobby claim a budget of zero, so the player's only
		-- remaining escape surrendered on its first hiccup.
		Failures = 0,
		Attempts = 0,
		AttemptId = nil,
		ChargedAttempt = nil,
		-- A fresh claim owes nobody anything and no authority holds it.
		Handoff = nil,
		HandoffAt = nil,
		HandoffToken = nil,
		HandoffTakeovers = 0,
		-- When this claim's lineage began. Anchored at the claim rather than at
		-- the first attempt, so a claim that never reaches an attempt is still
		-- inside a finite settlement. Never moved by a retry, because the
		-- settlement budget belongs to the lineage, not the attempt; only
		-- Routing.InheritLineage may move it, and only EARLIER.
		LineageStartedAt = claimedAt,
		Options = nil,
		PlaceId = nil,
		StartedAt = nil,
		FellBack = false,
	}
	claims[member] = fresh
	return true, fresh
end

-- One TeleportAsync call is one attempt, however many players ride it: they all
-- travel under the same TeleportOptions and therefore the same id.
function Routing.NewAttemptId(): number
	lastAttemptId += 1
	return lastAttemptId
end

-- Hand this claim to TeleportService as part of attempt `attemptId`. The id
-- travels in the teleport data, so a failure callback can be matched to the
-- attempt that produced it instead of to whatever claim happens to be current
-- when it arrives. The DESCRIPTOR is kept as well, because a retry has to
-- rebuild equivalent options under a fresh id -- reusing the old options object
-- would make the retry's failures indistinguishable from the original's.
function Routing.BeginAttempt(claims, member, destination, attemptId, options, placeId, at, descriptor)
	local record = claims[member]
	if type(record) ~= "table" or record.State ~= Routing.Pending then return nil end
	record.AttemptId = tonumber(attemptId)
	-- A new attempt may be charged once. The previous attempt's charge does not
	-- carry over, and the previous attempt can never be charged again.
	record.ChargedAttempt = nil
	-- Whatever handoff authorised this dispatch has now been discharged by it.
	-- Leaving the stamp behind would let the sweep's abandoned-handoff branch
	-- fire against an attempt that is genuinely in flight.
	record.Handoff, record.HandoffAt, record.HandoffToken = nil, nil, nil
	record.HandoffTakeovers = 0
	-- The lineage clock starts at the FIRST attempt and never restarts, so a
	-- claim cannot buy itself an unbounded settlement by retrying forever.
	if record.LineageStartedAt == nil then record.LineageStartedAt = at end
	record.Attempts += 1
	record.Destination = destination or record.Destination
	record.Options = options
	record.PlaceId = placeId
	record.StartedAt = at
	if descriptor ~= nil then record.Descriptor = descriptor end
	return record.AttemptId
end

-- Roblox has now ACCEPTED this attempt. Re-anchor the stale clock to that
-- moment.
--
-- Routing.BeginAttempt has to stamp before the call, because a TeleportAsync
-- that never returns at all still has to time out. But the stale threshold
-- means "Roblox took the request and then nothing happened", and TeleportAsync
-- yields -- so measuring from before it returned charges the yield itself
-- against the attempt. On the cohort schedule, where the whole budget is six
-- seconds, a dispatch that merely took its time would be re-dispatched
-- underneath a transfer that was about to succeed.
--
-- Only the CURRENT, UNCHARGED attempt may be re-anchored: a failure already
-- charged owns the claim through its handoff stamp, and moving the attempt
-- clock under it would hide a lapsed handoff from the sweep.
function Routing.RestampAttempt(claims, member, attemptId, at, dispatchedAt): boolean
	local record = claims[member]
	if type(record) ~= "table" or record.State ~= Routing.Pending then return false end
	if record.AttemptId == nil or record.AttemptId ~= attemptId then return false end
	if record.ChargedAttempt ~= nil and record.ChargedAttempt == record.AttemptId then
		return false
	end
	local stamp = tonumber(at)
	if stamp == nil then return false end
	-- CLAMPED. Re-anchoring is a courtesy to a slow accept, not a licence to move
	-- the whole lineage past the horizon the packet already declared. `at` may be
	-- arbitrarily far after the dispatch; the attempt clock may only follow it as
	-- far as the accept grace. Callers that cannot supply the dispatch instant get
	-- the old unclamped behaviour, which is why every production caller passes it.
	local dispatched = tonumber(dispatchedAt) or tonumber(record.StartedAt)
	if dispatched ~= nil then
		local ceiling = dispatched + Routing.CohortAcceptGraceSeconds
		if stamp > ceiling then stamp = ceiling end
		-- Never move the clock BACKWARDS: a late report must not un-age an attempt.
		if stamp < dispatched then stamp = dispatched end
	end
	record.StartedAt = stamp
	return true
end

function Routing.DescriptorOf(claims, member)
	local record = claims[member]
	if type(record) ~= "table" then return nil end
	return record.Descriptor
end

-- Read an attempt id back out of the TeleportOptions Roblox hands to
-- TeleportInitFailed. The id inside the teleport data is the primary match;
-- identity of the options object is the fallback.
function Routing.AttemptIdOf(options)
	if options == nil then return nil end
	local ok, data = pcall(function() return options:GetTeleportData() end)
	if not ok or type(data) ~= "table" then return nil end
	return tonumber(data.TransferAttemptId)
end

function Routing.MatchesCurrentAttempt(claims, member, attemptId, options)
	local record = claims[member]
	if type(record) ~= "table" then return false, nil end
	if record.State ~= Routing.Pending then return false, record end
	if record.AttemptId == nil then return false, record end
	if attemptId ~= nil then return attemptId == record.AttemptId, record end
	if options ~= nil and record.Options ~= nil then return options == record.Options, record end
	-- Nothing to correlate on. Refusing here is deliberate: acting on an
	-- unidentifiable failure is what let a stale next-level callback retry its
	-- own dead options over a fresh lobby claim. An attempt that genuinely goes
	-- quiet is caught by ExpireStaleTransfers instead.
	return false, record
end

-- Roblox reported this attempt failed.
--
-- ONE attempt earns AT MOST ONE failure, ever. Roblox can report the same
-- request more than once, and charging each report is how a single rejection
-- used to consume a player's retry AND their fallback in one go. A second
-- report of an already-charged attempt, and any report of an attempt that is no
-- longer current, both return nil and change nothing. This is also the only
-- place the failure counter moves.
-- THE transition. Both the TeleportInitFailed callback and the silent-transfer
-- sweep enter here, and nothing else moves `Failures`.
--
-- They used to differ, and the difference was a release blocker. FailAttempt
-- charged the attempt but left the claim PENDING for the one-second retry
-- delay; ExpireStaleTransfers did not look at ChargedAttempt at all, so a
-- report landing at age 24.5s charged failure #1 and scheduled the retry, and
-- the age-25 sweep 0.5s later charged failure #2 and resolved the claim -- the
-- retry then found a non-pending claim and exited. One callback plus one
-- timeout consumed two failures AND the authorised retry.
--
-- `at` is when this failure is being charged. It stamps the retry's handoff
-- window so the sweep can tell "a retry is on its way" from "the retry never
-- happened", without ever charging the same attempt twice.
-- Where a failure came from. An unnamed source is refused rather than guessed
-- at: the two paths correlate differently (a callback must match the attempt it
-- names; a sweep IS the attempt's own clock) and conflating them is how a
-- report nobody could identify came to be charged to whatever claim was current.
Routing.FailureSources = {Callback = "callback", Timeout = "timeout"}

function Routing.AttemptFailure(claims, member, source, attemptId, options, now)
	local record = claims[member]
	if type(record) ~= "table" then return nil, nil, nil end
	if record.State ~= Routing.Pending then return nil, record, nil end
	if record.AttemptId == nil then return nil, record, nil end
	if source == Routing.FailureSources.Callback then
		local matches = Routing.MatchesCurrentAttempt(claims, member, attemptId, options)
		if not matches then return nil, record, nil end
	elseif source ~= Routing.FailureSources.Timeout then
		return nil, record, nil
	end
	-- IDEMPOTENCE. This single guard is what makes callback-then-sweep and
	-- sweep-then-callback identical. It is also why the sweep can no longer
	-- steal an authorised retry: a second arrival changes NOTHING -- not
	-- Failures, not State, and not the handoff token the first arrival issued.
	if record.ChargedAttempt ~= nil and record.ChargedAttempt == record.AttemptId then
		return nil, record, record.HandoffToken
	end
	record.ChargedAttempt = record.AttemptId
	record.Failures += 1
	-- The plan is awarded ATOMICALLY with the charge, and stamped, so the sweep
	-- can tell "an authority is on its way" from "the authority died".
	record.Handoff = Routing.RetryPlan(record)
	record.HandoffAt = tonumber(now)
	record.HandoffToken = {}
	return record.Handoff, record, record.HandoffToken
end

-- The historical name, kept so a caller that only ever meant "Roblox reported
-- this attempt failed" cannot accidentally acquire the timeout's correlation
-- rules by dropping an argument.
function Routing.FailAttempt(claims, member, attemptId, options, now)
	return Routing.AttemptFailure(
		claims, member, Routing.FailureSources.Callback, attemptId, options, now)
end

function Routing.HandoffToken(claims, member)
	local record = claims[member]
	if type(record) ~= "table" then return nil end
	return record.HandoffToken
end

function Routing.HandoffPlan(claims, member)
	local record = claims[member]
	if type(record) ~= "table" then return nil end
	return record.Handoff
end

-- Resolve a claim as failed, but ONLY on behalf of the authority that currently
-- owns it. A thread holding a superseded token has already been overtaken by a
-- newer attempt; letting it resolve would delete a transfer that is in flight.
function Routing.ResolveFailedAttempt(claims, member, token): boolean
	local record = claims[member]
	if type(record) ~= "table" or record.State ~= Routing.Pending then return false end
	-- A caller that PRESENTS a token is claiming to be the current authority, so
	-- it must match exactly. The earlier form also accepted a nil current token
	-- as "nobody owns this, go ahead" -- but a nil token means the handoff was
	-- already discharged by a newer attempt, which is precisely when a stale
	-- thread must be turned away. That let a superseded fallback resolve a
	-- transfer that was in flight.
	if token ~= nil and record.HandoffToken ~= token then return false end
	record.State = Routing.Failed
	record.Handoff, record.HandoffAt, record.HandoffToken = nil, nil, nil
	return true
end

-- What a failed transfer earns next. "retry" repeats the same destination once,
-- with the options THIS module recorded rather than any the caller was handed;
-- "fallback" is the lobby escape a failed next-level transfer gets instead of
-- being stranded in a finished world; "surrender" hands the player to local
-- recovery. A lobby transfer has no fallback -- the lobby IS the fallback.
function Routing.RetryPlan(record, maxRetries)
	if type(record) ~= "table" then return "surrender" end
	local limit = tonumber(maxRetries) or Routing.MaxTransferRetries
	if (tonumber(record.Failures) or 0) <= limit then return "retry" end
	if record.Destination == "next" and record.FellBack ~= true then return "fallback" end
	return "surrender"
end

function Routing.MarkFellBack(claims, member): boolean
	local record = claims[member]
	if type(record) ~= "table" then return false end
	record.FellBack = true
	return true
end

-- Duplicate and late callbacks are the normal case here. Only a PENDING claim
-- can change state, only once, and only for the attempt that is current.
function Routing.ResolveTransfer(claims, member, state, attemptId)
	local record = claims[member]
	if type(record) ~= "table" or record.State ~= Routing.Pending then return false end
	if state ~= Routing.Succeeded and state ~= Routing.Failed then return false end
	if attemptId ~= nil and record.AttemptId ~= nil and attemptId ~= record.AttemptId then
		return false
	end
	record.State = state
	return true
end

-- The hard-cap transition applied to ONE claim, and applied EXACTLY ONCE.
--
-- Routing.ResolveTransfer already refuses a second call -- it only moves a
-- PENDING claim -- but the caller was not reading it: Runtime:ForceSettle
-- warned, spawned a surrender and appended to `stranded` unconditionally. Two
-- passes of an expired settlement, or a concurrent one, therefore handed the
-- same player to local recovery twice, cancelling the first recovery's retry
-- token with the second's and reporting the same strand twice over.
--
-- The marker lives on the record, so it is scoped to the claim it settled: the
-- FRESH claim a later path takes for the same player is a different record and
-- may be force-settled on its own account.
function Routing.ForceSettleClaim(claims, member): boolean
	local record = claims[member]
	if type(record) ~= "table" then return false end
	if record.ForceSettled == true then return false end
	record.ForceSettled = true
	-- A succeeded claim stays succeeded; only a pending one is failed here.
	Routing.ResolveTransfer(claims, member, Routing.Failed)
	-- No authority may act on this claim afterwards. Clearing the token is what
	-- makes a late callback a no-op instead of a second recovery: every path
	-- that resolves presents a token, and none of them can match nil.
	record.Handoff, record.HandoffAt, record.HandoffToken = nil, nil, nil
	-- A claim caught mid-handover is ended here too, or it would stay "owned"
	-- forever and the settlement could never resolve again.
	record.HandoverPending = nil
	return true
end

function Routing.WasForceSettled(claims, member): boolean
	local record = claims[member]
	return type(record) == "table" and record.ForceSettled == true
end

-- Give up ownership entirely, so a later path may take a fresh claim. Used only
-- by the final local-recovery sweep.
function Routing.ReleaseTransfer(claims, member): boolean
	if claims[member] == nil then return false end
	claims[member] = nil
	return true
end

function Routing.TransferState(claims, member)
	local record = claims[member]
	if type(record) ~= "table" then return nil end
	return record.State
end

function Routing.AttemptOf(claims, member)
	local record = claims[member]
	if type(record) ~= "table" then return nil end
	return record.AttemptId
end

function Routing.OptionsOf(claims, member)
	local record = claims[member]
	if type(record) ~= "table" then return nil end
	return record.Options, record.PlaceId
end

-- A fallback resolves one claim and opens the next in a spawned thread, so for
-- an instant the player owns NOTHING. A settlement polling in that instant sees
-- zero pending claims, concludes everybody is accounted for, and releases the
-- completed world out from under a lobby transfer that has not been made yet.
--
-- The handover marker closes that window: between resolving the old claim and
-- taking the new one, the player is still owned. It deliberately does NOT block
-- Routing.ClaimTransfer -- the whole point is that the next claim can be taken.
function Routing.BeginHandover(claims, member): boolean
	local record = claims[member]
	if type(record) ~= "table" then return false end
	record.HandoverPending = true
	return true
end

function Routing.EndHandover(claims, member): boolean
	local record = claims[member]
	if type(record) ~= "table" then return false end
	record.HandoverPending = nil
	return true
end

function Routing.InHandover(claims, member): boolean
	local record = claims[member]
	return type(record) == "table" and record.HandoverPending == true
end

function Routing.PendingTransfers(claims, present)
	present = present or function() return true end
	local pending = {}
	for member, record in pairs(claims or {}) do
		if type(record) == "table" and present(member)
			and (record.State == Routing.Pending or record.HandoverPending == true) then
			pending[#pending + 1] = member
		end
	end
	return pending
end

-- The settlement may only let go of the completed world once no present player
-- still holds an unresolved claim.
function Routing.TransfersResolved(claims, present): boolean
	return #Routing.PendingTransfers(claims, present) == 0
end

-- An attempt that never reported anything at all still has to end.
--
-- This sweep does NOT have a policy of its own. It used to: it incremented
-- Failures itself and forced the claim to Failed, and the caller then sent
-- every expired player straight to local recovery -- which, in a reserved
-- server, opened a fresh LOBBY transfer. So a next-level attempt that Roblox
-- merely dropped silently lost the one next-level retry the policy promises it,
-- while an identical attempt that Roblox bothered to REPORT kept it. Two
-- different outcomes for the same failure, decided by whether a callback fired.
--
-- Now a stale attempt enters Routing.FailAttempt, exactly as a report does, and
-- the returned plan is the same plan a report would have earned. The caller
-- applies it through the same code path.
--
-- This function MUTATES NOTHING. It reports what the sweep should do, and the
-- caller performs it through Routing.AttemptFailure -- the same door a callback
-- comes through. That separation is the fix: charging lived in two places, and
-- the second place did not know about the first.
--
-- Each action is one of:
--   {Member, Kind = "attempt"}
--       the current attempt is UNCHARGED and older than `timeout`.
--   {Member, Kind = "handoff", Plan, Token}
--       the attempt is charged and a plan was awarded, but nobody acted on it
--       within RetryHandoffGraceSeconds -- the thread that owned it died.
--   {Member, Kind = "unstarted"}
--       the claim was taken and NO attempt was ever made on it. There is
--       nothing to charge and nothing to time out, so the ordinary failure
--       policy cannot reach it; it is surrendered directly.
function Routing.SweepTransfers(claims, now, timeout, present)
	present = present or function() return true end
	-- An explicit `timeout` overrides everything (the suite drives specific
	-- ages); otherwise each claim is held to the threshold ITS destination
	-- earns, so a cohort-bound attempt is noticed inside the destination's
	-- staging window instead of thirty seconds after it closed.
	local override = tonumber(timeout)
	local actions = {}
	for member, record in pairs(claims or {}) do
		if type(record) == "table" and record.State == Routing.Pending and present(member) then
			local limit = override or Routing.TimeoutForDestination(record.Destination)
			local charged = record.ChargedAttempt ~= nil
				and record.ChargedAttempt == record.AttemptId
			if record.AttemptId == nil then
				local claimedAt = tonumber(record.ClaimedAt)
				local unstartedLimit = override or Routing.UnstartedClaimTimeoutSeconds
				if claimedAt and (now - claimedAt) >= unstartedLimit then
					actions[#actions + 1] = {Member = member, Kind = "unstarted"}
				end
			elseif charged then
				local at = tonumber(record.HandoffAt)
				if record.Handoff and at and (now - at) >= Routing.RetryHandoffGraceSeconds then
					-- RE-ARM. This is the one thing the sweep does mutate, and it
					-- must: without it the stamp stays old, every later sweep
					-- sees the same lapsed handoff, and the settlement loop --
					-- which sweeps four times a second -- spawns a re-drive
					-- closure every quarter second for the rest of the window.
					-- Re-arming touches neither Failures nor State, which is
					-- what "the sweep must not charge or resolve" protects.
					record.HandoffAt = now
					record.HandoffTakeovers = (tonumber(record.HandoffTakeovers) or 0) + 1
					local plan = record.Handoff
					if record.HandoffTakeovers > Routing.MaxHandoffTakeovers then
						-- Handed out and lost often enough. Spend the retry
						-- budget WITHOUT charging a second failure: lowering the
						-- limit for this one decision turns "retry" into the
						-- fallback the player is actually owed, so a claim whose
						-- authority keeps dying escalates instead of looping.
						plan = Routing.RetryPlan(record, Routing.MaxTransferRetries - 1)
						record.Handoff = plan
					end
					actions[#actions + 1] = {
						Member = member,
						Kind = "handoff",
						Plan = plan,
						Token = record.HandoffToken,
					}
				end
			else
				local startedAt = tonumber(record.StartedAt)
				if startedAt and (now - startedAt) >= limit then
					actions[#actions + 1] = {Member = member, Kind = "attempt"}
				end
			end
		end
	end
	-- Deterministic order, so a suite can assert on the sequence.
	table.sort(actions, function(a, b) return tostring(a.Member) < tostring(b.Member) end)
	return actions
end

-- ---------------------------------------------------------------------------
-- Settlement, followed across a claim's whole lineage
-- ---------------------------------------------------------------------------

-- When this claim's lineage must be over. Read off the LIVE record, so a retry
-- dispatched late moves nothing: the lineage began when the FIRST attempt did.
-- A fallback resolves one claim and opens another for the same player. The
-- second is a NEW claim with a clean retry budget -- deliberately -- but it is
-- the SAME player still trying to leave, so the settlement ceiling must keep
-- counting from where their first attempt began.
function Routing.InheritLineage(claims, member, startedAt): boolean
	local record = claims[member]
	if type(record) ~= "table" then return false end
	local inherited = tonumber(startedAt)
	if inherited == nil then return false end
	local current = tonumber(record.LineageStartedAt)
	if current ~= nil and current <= inherited then return false end
	record.LineageStartedAt = inherited
	return true
end

function Routing.LineageStartOf(claims, member): number?
	local record = claims[member]
	if type(record) ~= "table" then return nil end
	return tonumber(record.LineageStartedAt)
end

-- The immutable start of this claim's ownership. Claim time first, because a
-- claim that never reached an attempt still has to be inside a finite
-- settlement; the attempt stamps are only a fallback for a record built by
-- hand.
function Routing.SettlementAnchorOf(record): number?
	if type(record) ~= "table" then return nil end
	return tonumber(record.LineageStartedAt)
		or tonumber(record.ClaimedAt)
		or tonumber(record.StartedAt)
end

function Routing.ClaimSettlementDeadline(record): number?
	if type(record) ~= "table" or record.State ~= Routing.Pending then return nil end
	local started = Routing.SettlementAnchorOf(record)
	if not started then return nil end
	return started + Routing.SettlementLineageSeconds
end

-- "resolved" | "waiting" | "expired", plus the members behind the verdict.
--
-- The old settlement froze one absolute deadline at entry and compared it to
-- nothing but the wall clock, so a retry begun at t=21 -- which cannot go stale
-- before t=46 -- was simply outside the wait. Recomputing from the live claims
-- on every pass is what makes the wait follow the lineage instead of the first
-- attempt of it.
function Routing.SettlementStatus(claims, now, present)
	present = present or function() return true end
	local pending, expired, soonest = {}, {}, nil
	for _, member in ipairs(Routing.PendingTransfers(claims, present)) do
		pending[#pending + 1] = member
		local record = claims[member]
		-- The ceiling is measured from the first attempt of the player's WHOLE
		-- transfer story -- carried across the fresh claim a fallback opens --
		-- and is the only thing that ends the wait early.
		--
		-- It was briefly written as math.min(lineageBudget, hardCap), which is
		-- always the smaller of the two and so made the cap dead code; and the
		-- lineage stamp was not carried across a fallback, so the budget quietly
		-- restarted and NOTHING could ever expire. The cap has to be reachable
		-- or the ownership transition it guards is decoration.
		--
		-- `or now` used to stand where the anchor lookup does. A claim with no
		-- stamp at all therefore had its deadline recomputed as now + 145 on
		-- every quarter-second poll: never reached, never expired, and the
		-- endpoint holding the finished world waited on it forever. A claim
		-- nobody can date is not "young", it is unaccountable -- so it expires
		-- at once and ForceSettle transfers its ownership to local recovery.
		local anchor = Routing.SettlementAnchorOf(record)
		local hard = anchor and (anchor + Routing.SettlementHardCapSeconds) or nil
		if hard == nil or now >= hard then
			expired[#expired + 1] = member
		elseif soonest == nil or hard < soonest then
			soonest = hard
		end
	end
	table.sort(pending, function(a, b) return tostring(a) < tostring(b) end)
	table.sort(expired, function(a, b) return tostring(a) < tostring(b) end)
	if #pending == 0 then
		return "resolved", {Pending = pending, Expired = expired}
	end
	if #expired > 0 then
		return "expired", {Pending = pending, Expired = expired}
	end
	return "waiting", {Pending = pending, Expired = expired, NextDeadline = soonest}
end

-- ---------------------------------------------------------------------------
-- The transfer runtime: the ORCHESTRATION, not just the rules
-- ---------------------------------------------------------------------------
--
-- Everything above is a pure function, and that is exactly why the previous
-- suite could report green over three release blockers. It asserted that
-- RetryPlan said "retry" -- and then opened a lobby claim by hand, because the
-- code that ACTS on a plan lived in GameManager where no test could reach it.
-- The callback path and the timeout path could therefore drift apart without a
-- single assertion noticing.
--
-- So the acting lives here too, behind an injected environment. GameManager
-- passes os.clock/task.delay/TeleportService; the suite passes a fake clock and
-- a scripted dispatcher. Both drive THE SAME transition and THE SAME settlement
-- loop. A test that cannot run the production path cannot guard it.
--
-- env = {
--   Claims        : table                       -- the claim map (pendingTeleports)
--   Now           : () -> number                -- os.clock
--   Delay         : (seconds, fn) -> ()         -- task.delay
--   Spawn         : (fn, ...) -> ()             -- task.spawn
--   Wait          : (seconds) -> ()             -- task.wait
--   Present       : (member) -> boolean         -- still on this server
--   Dispatch      : (member, descriptor) -> ok, err, attemptId
--   LobbyTransfer : (member) -> ok, err
--   Surrender     : (member, reason) -> ()      -- hand to local recovery
--   Notify        : (member, event, ...) -> ()
--   Warn          : (text) -> ()
--   Reserved      : boolean
--   Studio        : boolean
-- }
local Runtime = {}
Runtime.__index = Runtime

function Routing.NewTransferRuntime(env)
	assert(type(env) == "table", "a transfer runtime needs an environment")
	assert(type(env.Claims) == "table", "a transfer runtime needs a claim map")
	return setmetatable({Env = env}, Runtime)
end

-- Sole entry from TeleportService.TeleportInitFailed.
function Runtime:ReportFailure(member, attemptId, options, reason)
	local env = self.Env
	local plan, _, token = Routing.AttemptFailure(
		env.Claims, member, Routing.FailureSources.Callback, attemptId, options, env.Now())
	-- nil means: no claim, not pending, an uncorrelatable report, or this
	-- attempt is already charged. All four are no-ops, by design.
	if not plan then return nil end
	self:_ApplyHandoff(member, plan, token, reason)
	return plan
end

-- Sole entry for a dispatch that was refused SYNCHRONOUSLY: TeleportAsync threw,
-- or the request could not even be built.
--
-- It used to not exist. Both wrappers marked the claim Failed by hand, which
-- looks harmless and is not: a claim resolved that way earns no retry, no lobby
-- fallback out of a refused next-level transfer, and no surrender to local
-- recovery. The player was simply left standing in a finished world with a dead
-- claim -- the exact outcome the whole policy exists to prevent -- and no test
-- could see it, because the bypass was in the caller.
--
-- A synchronous rejection IS the failure a callback would report a moment
-- later, so it is charged as one, against the attempt that produced it.
function Runtime:ReportDispatchFailure(member, attemptId, reason)
	local env = self.Env
	local plan, _, token = Routing.AttemptFailure(
		env.Claims, member, Routing.FailureSources.Callback, attemptId, nil, env.Now())
	if not plan then return nil end
	self:_ApplyHandoff(member, plan, token, reason)
	return plan
end

-- Sole entry from the watchdog loop AND from the settlement loop. One sweep
-- owns every unfinished transfer on this server, whatever path opened it.
function Runtime:Sweep(reason)
	local env = self.Env
	local charged, redriven = 0, 0
	for _, action in ipairs(Routing.SweepTransfers(env.Claims, env.Now(), nil, env.Present)) do
		if action.Kind == "unstarted" then
			-- No attempt was ever made, so there is nothing to charge and no
			-- report will ever come. The claim is ended and its player handed to
			-- local recovery, which is bounded and keeps the world standing.
			redriven += 1
			env.Warn("the claim for " .. tostring(action.Member)
				.. " was never dispatched; surrendering it (" .. tostring(reason) .. ")")
			self:_Surrender(action.Member, nil, "CLAIM_NEVER_DISPATCHED")
		elseif action.Kind == "attempt" then
			local plan, _, token = Routing.AttemptFailure(
				env.Claims, action.Member, Routing.FailureSources.Timeout, nil, nil, env.Now())
			-- nil here means a callback charged it between the report and now.
			-- Not recharged, and its retry is not stolen.
			if plan then
				charged += 1
				env.Warn("transfer for " .. tostring(action.Member)
					.. " was never reported on; expiring it (" .. tostring(reason) .. ")")
				self:_ApplyHandoff(action.Member, plan, token, "TRANSFER_TIMED_OUT")
			end
		else
			-- A plan was awarded and the thread that owned it never acted.
			redriven += 1
			env.Warn("the authority for " .. tostring(action.Member)
				.. "'s transfer never acted; re-driving it (" .. tostring(reason) .. ")")
			self:_ApplyHandoff(action.Member, action.Plan, action.Token, "HANDOFF_ABANDONED")
		end
	end
	return charged, redriven
end

-- THE one policy. A silent attempt and a reported one arrive here identically,
-- which is the whole point: the timeout used to bypass this and go straight to
-- local recovery, so a dropped next-level request lost the retry an equally
-- failed but REPORTED request would have kept.
function Runtime:_ApplyHandoff(member, plan, token, reason)
	local env = self.Env
	if plan == "retry" then
		-- The claim stays PENDING: same transfer, attempted again, under a NEW
		-- id so its own failure report is distinguishable. Rebuilt from the
		-- descriptor Routing recorded, never from options a callback handed in.
		local descriptor = Routing.DescriptorOf(env.Claims, member)
		if not descriptor then
			return self:_Surrender(member, token, "no descriptor to retry from")
		end
		env.Delay(Routing.RetryDelaySeconds, function()
			if not env.Present(member) then return end
			if Routing.TransferState(env.Claims, member) ~= Routing.Pending then return end
			-- Superseded: something else already re-attempted this claim.
			if Routing.HandoffToken(env.Claims, member) ~= token then return end
			local ok, err, newId = env.Dispatch(member, descriptor)
			if not ok then
				local nextPlan, _, nextToken = Routing.AttemptFailure(
					env.Claims, member, Routing.FailureSources.Callback,
					newId, nil, env.Now())
				if nextPlan then
					self:_ApplyHandoff(member, nextPlan, nextToken, err)
				end
			end
		end)
		return
	end

	if plan == "fallback" then
		-- A player who cannot enter the next reserved server must still escape
		-- the completed one. Resolve THIS claim and take a fresh lobby claim,
		-- which carries its own retry and its own attempt ids.
		--
		-- Ownership is checked FIRST. Marking the claim fallen-back before
		-- knowing whether this thread still owns it let a superseded authority
		-- brand a transfer that had already been re-attempted, which spends the
		-- fallback of a claim that never used it.
		local lineageStartedAt = Routing.LineageStartOf(env.Claims, member)
		if not Routing.ResolveFailedAttempt(env.Claims, member, token) then return end
		Routing.MarkFellBack(env.Claims, member)
		-- Owned continuously across the gap: the lobby claim is taken in a
		-- spawned thread, and without this the settlement can run in between and
		-- release the world while this player has no claim at all.
		Routing.BeginHandover(env.Claims, member)
		env.Notify(member, "transitionfailed")
		env.Spawn(function()
			local ok, err = env.LobbyTransfer(member)
			-- The lobby claim is a NEW claim with a clean retry budget, but it is
			-- the same player still trying to leave: the settlement ceiling keeps
			-- counting from their first attempt, so a fallback cannot silently
			-- restart the budget and make the hard cap unreachable.
			Routing.InheritLineage(env.Claims, member, lineageStartedAt)
			Routing.EndHandover(env.Claims, member)
			-- A lobby transfer that was refused synchronously now reports through
			-- Runtime:ReportDispatchFailure, so it can come back false with a
			-- retry already scheduled against a live claim. Surrendering on the
			-- return value alone would resolve that claim out from under the
			-- retry and send the player to local recovery a whole attempt early.
			if not ok and not Routing.ClaimOwns(env.Claims[member]) then
				env.Surrender(member, err)
			end
		end)
		return
	end

	self:_Surrender(member, token, reason)
end

function Runtime:_Surrender(member, token, reason)
	local env = self.Env
	if Routing.ResolveFailedAttempt(env.Claims, member, token) then
		env.Spawn(env.Surrender, member, reason)
	end
end

-- What every endpoint calls before it lets go.
--
-- Returns (resolved, stranded). `resolved == false` is NOT advisory: it means
-- players on this server are still unaccounted for, and the caller must keep
-- the completed world standing. Every one of the four endpoints used to discard
-- this value entirely.
function Runtime:AwaitSettlement(endpoint)
	local env = self.Env
	local plan = Routing.EndpointPlan({
		Endpoint = endpoint,
		Reserved = env.Reserved,
		Studio = env.Studio,
	})
	local nextSweepAt = env.Now()
	while true do
		local status = Routing.SettlementStatus(env.Claims, env.Now(), env.Present)
		if status == "resolved" then return true, {} end
		-- The settlement drives the sweep itself rather than hoping the watchdog
		-- ticks inside its window: timeouts AND abandoned handoffs both move.
		-- On the WATCHDOG's cadence, not the poll's: sweeping four times a
		-- second re-drove every lapsed handoff four times a second, spawning a
		-- re-dispatch closure each time for the rest of the window. The cadence
		-- is the SHORTEST threshold in play, or the tighter cohort timeout would
		-- be noticed a whole lobby sweep late and the retry would miss the
		-- destination's staging window.
		if env.Now() >= nextSweepAt then
			nextSweepAt = env.Now() + Routing.SweepIntervalSeconds()
			self:Sweep(endpoint)
		end
		local after, detail = Routing.SettlementStatus(env.Claims, env.Now(), env.Present)
		if after == "resolved" then return true, {} end
		if after == "expired" then
			return false, self:ForceSettle(detail.Expired, endpoint)
		end
		env.Wait(plan.Poll)
	end
end

-- The bounded hard-cap transition. It does not abandon anybody: every claim it
-- ends is resolved terminally AND handed to local recovery, which in a reserved
-- server keeps the finished world standing and retries the lobby. After this,
-- no present player owns a pending claim.
function Runtime:ForceSettle(members, endpoint)
	local env = self.Env
	local stranded = {}
	for _, member in ipairs(members or {}) do
		-- Idempotent by the record, so a repeated or concurrent force -- and any
		-- callback that lands afterwards -- changes nothing and reports nothing.
		if Routing.ForceSettleClaim(env.Claims, member) then
			env.Warn("settlement hard cap reached at " .. tostring(endpoint)
				.. " for " .. tostring(member) .. "; handing them to local recovery")
			env.Spawn(env.Surrender, member, "SETTLEMENT_HARD_CAP")
			stranded[#stranded + 1] = member
		end
	end
	return stranded
end

return Routing
