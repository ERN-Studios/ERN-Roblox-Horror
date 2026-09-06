-- Round Completion Test Suite
--
-- Deterministic assertions on the post-win completion path: which level leads
-- where, who is transferred and exactly once, whether every continuer out of a
-- single result window really lands in a single next-level round, and what
-- happens when Roblox rejects or misreports a transfer at each point in that
-- sequence.
--
-- Five suites:
--
--   Module()     -- the routing rules themselves, on synthetic rosters.
--   Host()       -- proof that the PRODUCTION host loaded and uses this module,
--                   and that it does not keep any transfer state of its own.
--   Admission()  -- source window -> teleport packets -> destination admission,
--                   replayed event by event, INCLUDING the production lifecycle:
--                   an early continuer whose PlayerRemoving fires while the
--                   window is still open.
--   Transfers()  -- the claim/attempt state machine under failure interleavings,
--                   driven with REAL TeleportOptions objects carrying the same
--                   teleport data production sends, through the same
--                   Routing.AttemptIdOf + Routing.FailAttempt pair the live
--                   TeleportInitFailed handler calls.
--   Teardown()   -- what happens to the completed world after a group transfer.
--
-- The real teleports cannot run in Studio, and a test that pretended otherwise
-- would be worth nothing. What IS asserted here is everything up to and after
-- the TeleportAsync call. Live TeleportService behaviour is not claimed.
--
-- Run from a Play session (the Host suite needs a running GameManager):
--
--   print((require(game.ServerScriptService["Round Completion Test Suite"]).RunAll()))

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Routing = require(script.Parent:WaitForChild("Round Completion Routing"))

local Suite = {}

-- Every suite declares the exact number of checks each branch it can take
-- performs. RunAll asserts the declaration, so a check that silently stops
-- running -- or a branch that quietly skips half its assertions -- fails
-- instead of shrinking the total nobody was watching.
local EXPECTED_CHECKS = {
	["Round completion routing rules"] = {full = 39},
	["Production host loads the routing module"] = {["with-source"] = 26, ["no-source"] = 8},
	["Post-win admission: one window, one round"] = {full = 59},
	["Transfer claims, attempts and failure reports"] = {full = 45},
	["Completed-world teardown"] = {full = 12},
	["Endpoint settlement and the silent-transfer watchdog"] = {full = 92},
	["Cohort timing, claim anchors and synchronous failures"] = {full = 118},
}

local function newReport(title, branch)
	return {Lines = {"=== " .. title .. " ==="}, Failures = 0, Checks = 0,
		Title = title, Branch = branch or "full"}
end

local function check(report, ok, description, detail)
	report.Checks += 1
	if ok then
		table.insert(report.Lines, "  ok   " .. description)
	else
		report.Failures += 1
		table.insert(report.Lines, "  FAIL " .. description
			.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
	end
	return ok
end

local function note(report, text)
	table.insert(report.Lines, "       " .. text)
end

local function names(list)
	local out = {}
	for _, member in ipairs(list) do table.insert(out, tostring(member)) end
	table.sort(out)
	return table.concat(out, ",")
end

local function setOf(...)
	local set = {}
	for _, key in ipairs({...}) do set[key] = true end
	return set
end

-- ---------------------------------------------------------------------------
-- Module -- the rules on synthetic rosters
-- ---------------------------------------------------------------------------

function Suite.Module()
	local report = newReport("Round completion routing rules")

	check(report, Routing.NextLevel(1) == 2, "Level 1 continues to Level 2",
		tostring(Routing.NextLevel(1)))
	check(report, Routing.NextLevel(2) == 3, "Level 2 continues to Level 3",
		tostring(Routing.NextLevel(2)))
	check(report, Routing.NextLevel(3) == nil, "Level 3 has no next level",
		tostring(Routing.NextLevel(3)))
	check(report, Routing.NextLevel(4) == nil, "there is no route beyond Level 3",
		tostring(Routing.NextLevel(4)))
	check(report, Routing.OffersContinue(1) and Routing.OffersContinue(2),
		"Levels 1 and 2 offer Continue")
	check(report, not Routing.OffersContinue(3),
		"Level 3 offers no Continue -- Back to Lobby only")
	check(report, Routing.MaxLevel == 3 and Routing.PostWinSeconds == 15,
		"the campaign ends at 3 and the window is 15 seconds",
		string.format("%s / %s", tostring(Routing.MaxLevel), tostring(Routing.PostWinSeconds)))
	check(report, Routing.ClampLevel(0) == 1 and Routing.ClampLevel(9) == 3
		and Routing.ClampLevel("2") == 2 and Routing.ClampLevel(nil) == 1,
		"level clamping is the module's, and holds for junk input")

	-- The roster is frozen at creation and never loses a member.
	local roster = Routing.NewRoster({"a", "b", "c", "a"})
	check(report, Routing.RosterSize(roster) == 3,
		"a duplicated participant joins the roster once", tostring(Routing.RosterSize(roster)))
	check(report, names(Routing.RosterMembers(roster)) == "a,b,c",
		"and every participant is in it", names(Routing.RosterMembers(roster)))
	check(report, Routing.DecisionOf(roster, "a") == Routing.Deciding,
		"everybody starts undecided", tostring(Routing.DecisionOf(roster, "a")))
	check(report, Routing.DecisionOf(roster, "zed") == nil,
		"somebody who was never in the window has no decision at all")
	check(report, not Routing.RecordDecision(roster, "zed", Routing.Continuing),
		"and cannot be given one")

	-- Decisions are one-way, and departure is terminal.
	check(report, Routing.RecordDecision(roster, "a", Routing.Continuing),
		"a Continue press is recorded")
	check(report, not Routing.RecordDecision(roster, "a", Routing.Returning),
		"a second, different press is refused")
	check(report, Routing.ClearDecision(roster, "a"),
		"a refused transfer gives the choice back")
	check(report, Routing.RecordDecision(roster, "a", Routing.Continuing),
		"and they may then choose again")
	check(report, Routing.MarkDeparted(roster, "a"), "Roblox accepted the transfer")
	check(report, not Routing.ClearDecision(roster, "a"),
		"after departure the choice can no longer be taken back")
	check(report, not Routing.NoteDeparture(roster, "a"),
		"and leaving the server does not turn a departed continuer into a quitter")
	check(report, Routing.DecisionOf(roster, "a") == Routing.Continuing,
		"a departed continuer is still a continuer",
		tostring(Routing.DecisionOf(roster, "a")))
	check(report, Routing.InRoster(roster, "a"),
		"and is still in the roster, which is what keeps the head count honest")

	-- THE RACE. "a" pressed Continue, departed, and has now left this server.
	-- "b" has not chosen; "c" opted out.
	Routing.RecordDecision(roster, "c", Routing.Returning)
	local present = function(member) return member ~= "a" end
	check(report, Routing.ExpectedContinuers(roster, present) == 2,
		"a departed continuer is still expected at the destination",
		tostring(Routing.ExpectedContinuers(roster, present)))
	local continuing, returning, departed, gone = Routing.Partition(roster, present)
	check(report, names(departed) == "a", "the departed one is not moved again", names(departed))
	check(report, names(continuing) == "b", "the undecided one is carried by the countdown",
		names(continuing))
	check(report, names(returning) == "c", "the opt-out goes to the lobby", names(returning))
	check(report, #gone == 0, "and nobody has quit", names(gone))

	-- A genuine quitter, who never chose.
	local quitters = Routing.NewRoster({"a", "b"})
	Routing.NoteDeparture(quitters, "a")
	check(report, Routing.DecisionOf(quitters, "a") == Routing.Gone,
		"leaving without choosing is recorded as gone",
		tostring(Routing.DecisionOf(quitters, "a")))
	check(report, Routing.ExpectedContinuers(quitters, function() return false end) == 0,
		"and a quitter is never expected at the destination")
	local qContinuing, _, _, qGone = Routing.Partition(quitters, function(m) return m ~= "a" end)
	check(report, names(qGone) == "a" and names(qContinuing) == "b",
		"the quitter is in no transfer list", names(qGone) .. " / " .. names(qContinuing))

	-- Settlement.
	local deciding = Routing.NewRoster({"a", "b"})
	check(report, not Routing.Settled(deciding), "a window with undecided players is not settled")
	Routing.RecordDecision(deciding, "a", Routing.Continuing)
	check(report, not Routing.Settled(deciding), "one chooser is not enough")
	check(report, Routing.Settled(deciding, function(m) return m ~= "b" end),
		"a disconnect settles the window instead of holding it open")
	Routing.RecordDecision(deciding, "b", Routing.Returning)
	check(report, Routing.Settled(deciding), "a window where everybody has chosen is settled")
	check(report, Routing.Settled(Routing.NewRoster({})), "an empty window is settled")

	-- Lobby sweep: exactly one transfer per player.
	local sweep = {"a", "b", "c", "d"}
	check(report, names(Routing.LobbyBound(sweep, setOf("a"), setOf("b"))) == "c,d",
		"the sweep skips progressing players and anyone already in flight",
		names(Routing.LobbyBound(sweep, setOf("a"), setOf("b"))))
	check(report, #Routing.LobbyBound(sweep, setOf("a", "b", "c", "d"), {}) == 0,
		"nobody is swept when everybody is progressing")
	check(report, #Routing.LobbyBound(sweep, {}, setOf("a", "b", "c", "d")) == 0,
		"nobody is swept when everybody already holds a transfer claim")
	check(report, names(Routing.LobbyBound(sweep, {}, {
		a = {State = Routing.Pending},
		b = {State = Routing.Succeeded},
		c = {State = Routing.Failed},
	})) == "c,d",
		"a failed claim releases its player back to the settlement sweep",
		names(Routing.LobbyBound(sweep, {}, {
			a = {State = Routing.Pending}, b = {State = Routing.Succeeded},
			c = {State = Routing.Failed}})))

	return report
end

-- ---------------------------------------------------------------------------
-- Host -- the production server really loaded and uses this module
-- ---------------------------------------------------------------------------

-- Shapes GameManager must NOT contain. Every one of them is a way of keeping
-- completion state outside this module, which is how the two drifted apart in
-- the first place. Written as Lua patterns so a mention in a comment cannot
-- satisfy or trip them.
local FORBIDDEN_SHAPES = {
	{"pendingTeleports%[[%w_%.]+%]%s*=", "assigns a transfer claim directly"},
	{"%.State%s*=[^=]", "assigns a transfer state directly"},
	{"%.Failures%s*%+=", "moves the failure counter directly"},
	{"%.FellBack%s*=", "sets the fallback marker directly"},
	{"session%.Eligible", "keeps its own eligibility set"},
	{"session%.Departed", "keeps its own departure set"},
	{"%.Roster%.Decision", "reaches into roster decisions directly"},
	-- Freezing an absolute settlement deadline is how the endpoint came to
	-- return while the retry it was responsible for was still in flight.
	{"os%.clock%(%)%s*%+%s*plan%.WaitFor", "freezes an absolute settlement deadline"},
}

local REQUIRED_SHAPES = {
	{'require(script.Parent:WaitForChild("Round Completion Routing"))', "requires the routing module"},
	{"Routing.NewRoster", "freezes the result window's roster through the module"},
	{"Routing.NoteDeparture", "records PlayerRemoving through the module"},
	{"Routing.ExpectedContinuers", "counts the cohort through the module"},
	{"Routing.ArrivalPacket", "builds every next-level packet through the module"},
	{"Routing.ArrivalDecision", "admits arrivals through the module"},
	{"Routing.AttemptIdOf", "correlates failure reports by attempt id"},
	{"Routing.NewTransferRuntime", "builds the transfer runtime from the module"},
	{"transfers:ReportFailure", "reports every failure into the runtime"},
	{"transfers:Sweep", "sweeps silent transfers through the runtime"},
	{"transfers:AwaitSettlement", "settles every endpoint through the runtime"},
	{"Routing.TeardownPlan", "decides the world teardown through the module"},
	{"Routing.TeardownPlan", "asks the module what the completed world is owed"},
	-- A1 renamed the schedule the host must read: the watchdog now ticks on the
	-- SHORTEST threshold in play, so a cohort attempt is noticed inside the
	-- destination's staging window. A host still reading WatchdogIntervalSeconds
	-- would sweep every 5s and miss it.
	{"Routing.SweepIntervalSeconds", "sweeps silent transfers on the module's shortest schedule"},
	{"Routing.Endpoints.Continuation", "settles the continuation endpoint"},
	{"Routing.Endpoints.Level3", "settles the Level 3 endpoint"},
	{"Routing.Endpoints.Loss", "settles the loss endpoint"},
	{"Routing.Endpoints.Fallback", "settles the fallback endpoint"},
}

function Suite.Host()
	local manager = game:GetService("ServerScriptService"):FindFirstChild("GameManager")
	local readable, source = pcall(function() return manager and manager.Source end)
	local hasSource = readable and type(source) == "string" and #source > 0
	local report = newReport("Production host loads the routing module",
		hasSource and "with-source" or "no-source")
	if not RunService:IsRunning() then
		note(report, "NOTE: GameManager only runs in a play session. In Edit mode")
		note(report, "there is no host to prove anything about, so these checks fail")
		note(report, "rather than pass vacuously. Run this suite from Play.")
	end

	-- The strongest available proof, and the only one that survives being run
	-- from the command bar: GameManager parents a BindableFunction whose
	-- OnInvoke reads the module at call time. OnInvoke cannot be serialised into
	-- a place file, so an answer can only come from a host that is running now
	-- and holding this module.
	local probe = ServerStorage:FindFirstChild(Routing.ProbeName)
	local answer = nil
	if check(report, probe ~= nil and probe:IsA("BindableFunction"),
		"the running host answers a live routing probe",
		probe and probe.ClassName or "no probe in ServerStorage") then
		local ok, reply = pcall(function() return probe:Invoke() end)
		answer = ok and reply or nil
	end
	check(report, type(answer) == "table", "the probe replies", typeof(answer))
	if type(answer) ~= "table" then answer = {} end
	check(report, answer.Host == "ServerScriptService.GameManager",
		"and the host answering it is GameManager", tostring(answer.Host))
	check(report, answer.Version == Routing.Version,
		"the host is holding THIS version of the module",
		string.format("host %s, module %s", tostring(answer.Version), tostring(Routing.Version)))
	check(report, answer.MaxLevel == Routing.MaxLevel
		and answer.PostWinSeconds == Routing.PostWinSeconds,
		"the host's campaign length and window come from the module",
		string.format("host %s/%s", tostring(answer.MaxLevel), tostring(answer.PostWinSeconds)))
	check(report, answer.NextAfterOne == 2 and answer.NextAfterTwo == 3
		and answer.EndsAtThree == true,
		"and the host routes L1->L2, L2->L3 and stops, through the module",
		string.format("%s / %s / %s", tostring(answer.NextAfterOne),
			tostring(answer.NextAfterTwo), tostring(answer.EndsAtThree)))
	check(report, workspace:GetAttribute(Routing.LoadedAttribute) == Routing.Version,
		"the running host also published this module's version on Workspace",
		tostring(workspace:GetAttribute(Routing.LoadedAttribute)))

	-- Only meaningful when the suite shares the host's require cache, which is
	-- true for an in-game requirer and false from the command bar's own VM.
	if Routing.LoadedBy ~= nil then
		check(report, Routing.LoadedBy == "ServerScriptService.GameManager",
			"and this suite shares the very table GameManager loaded",
			tostring(Routing.LoadedBy))
	else
		check(report, true,
			"shared-table check not applicable: this run has its own require cache")
	end

	if hasSource then
		local missing, present = {}, {}
		for _, entry in ipairs(REQUIRED_SHAPES) do
			if source:find(entry[1], 1, true) == nil then table.insert(missing, entry[2]) end
		end
		check(report, #missing == 0, "the host routes every completion rule through the module",
			table.concat(missing, "; "))
		for _, entry in ipairs(FORBIDDEN_SHAPES) do
			if source:find(entry[1]) ~= nil then table.insert(present, entry[2]) end
		end
		check(report, #present == 0,
			"and keeps no completion or transfer state of its own",
			table.concat(present, "; "))
		check(report, source:find("local MAX_LEVEL", 1, true) == nil
			and source:find("local POST_WIN_SECONDS", 1, true) == nil
			and source:find("local TRANSFER_SETTLEMENT_TIMEOUT", 1, true) == nil,
			"no duplicated campaign or settlement constants remain in the host")
		check(report, source:find("PartySize = #live", 1, true) == nil
			and source:find("data.PartySize", 1, true) == nil,
			"no continuer is sent as a party of one, and the bootstrap does not"
			.. " size a round from one frozen PartySize")
		-- The failure handler must be a thin wrapper over the module, or the
		-- correlation this suite tests would not be the correlation production
		-- runs.
		local handler = source:match("TeleportService%.TeleportInitFailed:Connect%(function.-\nend%)")
		check(report, handler ~= nil, "the TeleportInitFailed handler is present")
		check(report, handler ~= nil
			and handler:find("Routing.AttemptIdOf", 1, true) ~= nil
			and handler:find("transfers:ReportFailure", 1, true) ~= nil,
			"and correlates every failure report through the module")
		check(report, handler ~= nil and handler:find("TeleportAsync", 1, true) == nil,
			"and starts no transfer of its own")

		-- THE endpoint contract. Four endpoint NAMES, FIVE settlement call
		-- sites -- the loss endpoint is reached by two roads, the wipe during
		-- the round and the wipe before it ever started -- and every one of
		-- them must capture the answer and act on an unresolved one. They all
		-- used to discard it, so a settlement that reported "players are still
		-- unaccounted for" changed nothing at all; and the pre-round wipe did
		-- not settle at all, it waited a fixed 1.6 seconds and returned.
		local settlementCalls, captured, honoured = 0, 0, 0
		for _ in source:gmatch("awaitTransferSettlement%(Routing%.Endpoints%.%w+%)") do
			settlementCalls += 1
		end
		for _ in source:gmatch("=%s*awaitTransferSettlement%(Routing%.Endpoints%.%w+%)") do
			captured += 1
		end
		for _ in source:gmatch("if%s+not%s+settled%s+then%s+holdCompletedWorld") do
			honoured += 1
		end
		check(report, settlementCalls == 6,
			"all five completion exits and loading failure settle", tostring(settlementCalls))
		check(report, captured == settlementCalls,
			"and none of them discards the settlement result",
			string.format("%d of %d captured", captured, settlementCalls))
		check(report, honoured == 6,
			"and every one of them holds the completed world when it does not resolve",
			tostring(honoured))

		-- A3. sendWipedPartyHome is a LOCAL CLOSURE inside playRound, so nothing
		-- can require it and no behavioural test can call it. What IS provable
		-- from here is that its own body settles: it used to run the group lobby
		-- transfer, `task.wait(1.6)` and return, so a transfer Roblox merely
		-- dropped was left pending with the completed world coming down around
		-- its player. The behavioural half of this -- that the Loss endpoint
		-- really force-settles a wedged claim -- is in Suite.Cohort.
		-- `%b()` matches the balanced argument list; the body then runs to the
		-- first line that is nothing but indentation and `end`.
		local wipedPattern = "local function sendWipedPartyHome%b()(.-)\n[ \t]*end\n"
		local wiped = source:match(wipedPattern)
		check(report, wiped ~= nil
			and wiped:find("awaitTransferSettlement(Routing.Endpoints.Loss)", 1, true) ~= nil,
			"the pre-round wipe settles the Loss endpoint inside its OWN body",
			wiped == nil and "sendWipedPartyHome body not found" or "body found, no settlement call")
		check(report, wiped ~= nil
			and wiped:find("holdCompletedWorld", 1, true) ~= nil
			and wiped:find("if not settled then", 1, true) ~= nil,
			"and holds the completed world instead of merely waiting and returning",
			wiped == nil and "no body" or "body found, result discarded")
		note(report, "MUTATION PROOF: reverting sendWipedPartyHome to a bare"
			.. " task.wait(1.6) fails the two checks above and drops"
			.. " settlementCalls/honoured back to 4.")

		-- A3 (the OTHER one). The Studio next-level branch called
		-- `failPendingTeleport(live)` -- a name that had been renamed to
		-- releaseUndispatchedClaims when synchronous failures were routed through
		-- the runtime, and this one call site was missed. Luau resolves an unknown
		-- name as a global, so it was nil and every Studio next-level transition
		-- raised "attempt to call a nil value" straight out of the completion
		-- path. Nothing caught it because no test drove that branch.
		-- A CALL at statement position, not the mere word: the repair's own comment
		-- names the dead helper on purpose, and a test that cannot tell an
		-- explanation from an invocation would forbid documenting the bug.
		check(report, source:find("\n[ \t]*failPendingTeleport%(") == nil,
			"the host calls no transfer helper that does not exist",
			"failPendingTeleport is still called")
		local studioNext = source:match(
			"local function teleportPlayersToNextLevel%b()(.-)\n[ \t]*end\n")
		check(report, studioNext ~= nil
			and studioNext:find("releaseUndispatchedClaims(live)", 1, true) ~= nil,
			"and the Studio next-level branch releases its claims through the surviving helper",
			studioNext == nil and "body not found" or "no release call in the branch")

		-- A4. The three GameManager call sites the cohort contract depends on.
		-- Each is a place where the routing module is CORRECT and the host could
		-- still get it wrong by not calling it, or by calling it without the
		-- argument that makes it bounded.
		check(report, source:find("Routing.RestampAttempt(pendingTeleports, player, attemptId, acceptedAt, at)",
				1, true) ~= nil,
			"the host re-anchors an accepted attempt AND hands over the dispatch instant to clamp it",
			"RestampAttempt is missing or called without the dispatch anchor")
		check(report, source:find("transfers:ReportDispatchFailure", 1, true) ~= nil,
			"and reports synchronous dispatch rejections into the runtime")
		local staging = source:match("local function stageArrivingParty%b()(.-)\nif IS_RESERVED_ROUND_SERVER")
		check(report, staging ~= nil
			and staging:find("CohortHorizon = group and group.CohortHorizon", 1, true) ~= nil
            and staging:find("LoadingDeadline = attempt.Deadline", 1, true) ~= nil,
			"and the destination hands the source's declared horizon to ArrivalDecision",
			staging == nil and "stageArrivingParty body not found" or "CohortHorizon not forwarded")
		note(report, "MUTATION PROOF: dropping the `at` argument at the RestampAttempt call site,"
			.. " or the CohortHorizon field in stageArrivingParty, fails these -- and both are"
			.. " places the routing module cannot defend itself.")

		-- A5. PARTY DOWN. The fifteen seconds between the last death and the loss
		-- endpoint are the only window in which an Emergency Re-entry can still
		-- save the run, and the round loop used to poll them in complete silence.
		-- Both halves of the contract are asserted together because a card that
		-- is raised and never cleared is worse than no card: a re-entry that
		-- revives the party would leave every client still counting down.
		-- The clear is asserted at its CALL SITES, not at the one fire inside
		-- clearPartyDown: the regression that matters is the recovery branch
		-- losing its call, and the fire itself would still be in the file.
		-- The fire is matched as a SHAPE, not as literal text: the window length,
		-- the spacing, and the name of the local carrying the last death are all
		-- free to change without being regressions. What stays pinned is that a
		-- REAL name argument is passed -- a bare fireGroup(participants,
		-- "partydown", 15) fails, and so does a stubbed-out literal nil, which is
		-- the bug this check was written for -- and that the window it announces
		-- is the same number wipeDeadline counts to, so retuning one and not the
		-- other cannot ship a client countdown that disagrees with the server's
		-- own loss endpoint.
		local partyDownClears = select(2, source:gsub("clearPartyDown%(%)", ""))
		local partyDownWindow, partyDownName = source:match(
			'fireGroup%(participants,%s*"partydown",%s*(%d+),%s*([%w_%.]+)%s*%)')
		local wipeWindow = source:match("wipeDeadline = os%.clock%(%) %+ (%d+)")
		check(report, partyDownName ~= nil and partyDownName ~= "nil"
			and partyDownWindow == wipeWindow
			and source:find("wipeDeadline = nil%s+clearPartyDown%(%)") ~= nil
			and partyDownClears >= 4,
			"the host announces the wipe window by name and clears it again",
			"partydown is not fired with a name, or announces a window other than the"
				.. " one wipeDeadline counts to, or the window is not cleared on"
				.. " re-entry recovery, teardown and the post-loop exit")
	else
		note(report, "skipped 18 source-shape checks: Source is not readable here")
	end

	return report
end

-- ---------------------------------------------------------------------------
-- Admission -- one result window, one next-level round
-- ---------------------------------------------------------------------------

-- A production-lifecycle stand-in for the source server. It sequences events
-- only; every rule it applies is Routing's, called in the same order and with
-- the same arguments GameManager calls them, INCLUDING the PlayerRemoving path.
local function newSource(options)
	local source = {
		SessionId = Routing.SessionId("JOB-SOURCE", options.Serial or 7),
		Level = options.Level or 1,
		NextLevel = Routing.NextLevel(options.Level or 1),
		EntryMode = options.EntryMode,
		Deadline = (options.Now or 1000) + Routing.PostWinSeconds,
		Roster = Routing.NewRoster(options.Party),
		Gone = {},
		Sent = {},
	}
	function source:present(member) return self.Gone[member] ~= true end
	function source:presence() return function(member) return self:present(member) end end
	function source:expected()
		return Routing.ExpectedContinuers(self.Roster, self:presence())
	end
	function source:packet(final)
		return Routing.ArrivalPacket({
			Level = self.NextLevel,
			EntryMode = self.EntryMode,
			SessionId = self.SessionId,
			Expected = self:expected(),
			Deadline = self.Deadline,
			Final = final == true,
		})
	end
	-- The immediate Continue path, in GameManager's order: latch the decision,
	-- send, then mark departed.
	function source:continueNow(member)
		if not Routing.RecordDecision(self.Roster, member, Routing.Continuing) then return nil end
		local packet = self:packet(false)
		Routing.MarkDeparted(self.Roster, member)
		table.insert(self.Sent, {Member = member, Data = packet})
		return packet
	end
	function source:backToLobby(member)
		Routing.RecordDecision(self.Roster, member, Routing.Returning)
	end
	-- PLAYER REMOVING. This is the step the previous double did not model: the
	-- player is no longer in Players, and GameManager's handler runs.
	function source:playerRemoving(member)
		self.Gone[member] = true
		Routing.NoteDeparture(self.Roster, member)
	end
	-- The settlement sweep at the deadline: everybody still undecided is carried
	-- onward in one transfer, and the packet is FINAL -- the exact cohort.
	function source:settle()
		local continuing, returning, departed, gone =
			Routing.Partition(self.Roster, self:presence())
		local packet = self:packet(true)
		for _, member in ipairs(continuing) do
			table.insert(self.Sent, {Member = member, Data = packet})
		end
		return packet, continuing, returning, departed, gone
	end
	return source
end

-- The reserved next-level server: it sees arrivals, and only arrivals.
local function newDestination()
	local destination = {Arrivals = {}, StartedAt = 0, FirstArrivalAt = nil}
	function destination:arrive(entry, at)
		table.insert(self.Arrivals, {Member = entry.Member, Data = entry.Data})
		if not self.FirstArrivalAt then self.FirstArrivalAt = at end
	end
	function destination:decide(now, serverNow)
		local group = Routing.SelectArrivalSession(self.Arrivals)
		local decision, reason = Routing.ArrivalDecision({
			Now = now,
			StartedAt = self.StartedAt,
			FirstArrivalAt = self.FirstArrivalAt,
			ServerNow = serverNow,
			Deadline = group and group.Deadline or nil,
			Arrived = group and #group.Members or 0,
			Expected = group and group.Expected or nil,
			-- A1: the horizon the SOURCE declared for this cohort. Dropping it
			-- makes the destination fall back to its own ceiling, so a source
			-- running a tighter policy silently buys the longer wait.
			CohortHorizon = group and group.CohortHorizon,
			Final = group and group.Final or false,
		})
		return decision, group, reason
	end
	return destination
end

function Suite.Admission()
	local report = newReport("Post-win admission: one window, one round")
	local opened = 1000
	local deadlineAt = opened + Routing.PostWinSeconds

	-- (1) THE PRODUCTION RACE. An early continuer departs AND leaves the source
	-- server while the window is still open. The remaining players decide later
	-- or let the countdown carry them. Every intended continuer must end up in
	-- ONE next-level round.
	do
		local source = newSource({Party = {"ana", "bo", "cy"}, Level = 1, Now = opened})
		local destination = newDestination()

		local first = source:continueNow("ana")
		destination:arrive({Member = "ana", Data = first}, 2)
		-- ...and Roblox takes them off this server.
		source:playerRemoving("ana")
		check(report, Routing.DecisionOf(source.Roster, "ana") == Routing.Continuing,
			"a departed continuer survives PlayerRemoving as a continuer",
			tostring(Routing.DecisionOf(source.Roster, "ana")))
		check(report, Routing.InRoster(source.Roster, "ana"),
			"and is not erased from the window's roster")
		check(report, source:expected() == 3,
			"so the head count still says three are coming", tostring(source:expected()))

		local decision, group = destination:decide(3, opened + 3)
		check(report, decision == "wait",
			"the first Continue does not start the round by itself", tostring(decision))

		-- A later manual Continue.
		local second = source:continueNow("bo")
		destination:arrive({Member = "bo", Data = second}, 6)
		check(report, second.RoundSessionId == first.RoundSessionId,
			"the later continuer carries the SAME session id", tostring(second.RoundSessionId))
		decision, group = destination:decide(6, opened + 6)
		check(report, decision == "wait",
			"and is staged, not dropped into a running round", tostring(decision))

		-- The countdown carries the last one.
		local final, continuing, returning, departed, gone = source:settle()
		check(report, names(continuing) == "cy", "only the undecided player is carried",
			names(continuing))
		check(report, names(departed) == "ana,bo", "both early continuers already departed",
			names(departed))
		check(report, #returning == 0 and #gone == 0,
			"nobody opted out and nobody quit", names(returning) .. " / " .. names(gone))
		check(report, final.FinalCohort == true and final.ExpectedContinuers == 3,
			"the settlement packet is final and names all THREE",
			string.format("final=%s expected=%s", tostring(final.FinalCohort),
				tostring(final.ExpectedContinuers)))
		destination:arrive({Member = "cy", Data = final}, 16)
		decision, group = destination:decide(16, deadlineAt + 1)
		check(report, decision == "admit", "the round starts once all three have landed",
			tostring(decision))
		check(report, group ~= nil and #group.Members == 3,
			"and every intended continuer is in it, none of them a spectator",
			group and tostring(#group.Members) or "nil")
		check(report, group ~= nil and group.Level == 2, "into Level 2",
			group and tostring(group.Level) or "nil")

		-- The undercount this replaces: had the departed continuer been dropped
		-- from the roster, the final cohort would have said two, and the
		-- destination would have admitted at two arrivals with "cy" still in
		-- transit.
		check(report, final.ExpectedContinuers ~= 2,
			"the cohort is not undercounted by the early departure",
			tostring(final.ExpectedContinuers))
		local twoArrived = newDestination()
		twoArrived:arrive({Member = "ana", Data = first}, 1)
		twoArrived:arrive({Member = "bo", Data = second}, 2)
		local partial = twoArrived:decide(3, opened + 3)
		check(report, partial == "wait",
			"two of the three arriving is not enough to start", tostring(partial))
	end

	-- (2) A genuine quitter shrinks the cohort; a departed continuer does not.
	do
		local source = newSource({Party = {"ana", "bo", "cy"}, Level = 2, Now = opened})
		source:playerRemoving("cy")
		check(report, Routing.DecisionOf(source.Roster, "cy") == Routing.Gone,
			"leaving without choosing is recorded as gone",
			tostring(Routing.DecisionOf(source.Roster, "cy")))
		check(report, source:expected() == 2, "and the destination expects two",
			tostring(source:expected()))
		local first = source:continueNow("ana")
		source:playerRemoving("ana")
		check(report, source:expected() == 2,
			"the departing continuer does not shrink it further", tostring(source:expected()))
		local destination = newDestination()
		destination:arrive({Member = "ana", Data = first}, 1)
		local final = source:settle()
		destination:arrive({Member = "bo", Data = final}, 16)
		local decision, group = destination:decide(16, deadlineAt + 1)
		check(report, decision == "admit" and group and #group.Members == 2,
			"and the round starts with exactly the two who were coming",
			group and tostring(#group.Members) or "nil")
		check(report, group ~= nil and group.Level == 3, "Level 2 continues to Level 3",
			group and tostring(group.Level) or "nil")
	end

	-- (3) A Back to Lobby player is never expected at the destination.
	do
		local source = newSource({Party = {"ana", "bo", "cy"}, Level = 2, Now = opened})
		source:backToLobby("cy")
		local first = source:continueNow("ana")
		check(report, first.ExpectedContinuers == 2,
			"the opt-out is already subtracted from the head count",
			tostring(first.ExpectedContinuers))
		local final, continuing, returning = source:settle()
		check(report, names(returning) == "cy" and names(continuing) == "bo",
			"the opt-out returns and the undecided player continues",
			names(continuing) .. " / " .. names(returning))
		local destination = newDestination()
		destination:arrive({Member = "ana", Data = first}, 1)
		destination:arrive({Member = "bo", Data = final}, 16)
		local decision, group = destination:decide(16, deadlineAt + 1)
		check(report, decision == "admit" and group and group.Expected == 2,
			"the round starts with two, never waiting for the third",
			group and tostring(group.Expected) or "nil")
	end

	-- (4) Duplicate packets: one player, several deliveries, one seat.
	do
		local source = newSource({Party = {"ana", "bo"}, Level = 1, Now = opened})
		local destination = newDestination()
		local packet = source:continueNow("ana")
		destination:arrive({Member = "ana", Data = packet}, 1)
		destination:arrive({Member = "ana", Data = packet}, 1)
		destination:arrive({Member = "ana", Data = packet}, 2)
		local decision, group = destination:decide(2, opened + 2)
		check(report, group ~= nil and #group.Members == 1,
			"a duplicated arrival packet counts its player once",
			group and tostring(#group.Members) or "nil")
		check(report, decision == "wait",
			"and duplicates cannot fake the cohort into starting early", tostring(decision))
		local final = source:settle()
		destination:arrive({Member = "bo", Data = final}, 16)
		destination:arrive({Member = "bo", Data = final}, 16)
		decision, group = destination:decide(16, deadlineAt + 1)
		check(report, decision == "admit" and group and #group.Members == 2,
			"the real cohort still admits exactly once each",
			group and tostring(#group.Members) or "nil")
	end

	-- (5) Destination bootstrap edge cases.
	do
		local destination = newDestination()
		check(report, destination:decide(1, opened + 1) == "wait",
			"an empty reserved server waits for the transport")
		check(report, destination:decide(Routing.AdmissionEmptySeconds + 1,
			opened + Routing.AdmissionEmptySeconds + 1) == "abandon",
			"a reserved server nobody reaches is abandoned, not left spinning")

		local junk = newDestination()
		junk:arrive({Member = "ana", Data = {ReturnToLobby = true}}, 1)
		junk:arrive({Member = "bo", Data = "not a table"}, 1)
		check(report, Routing.SelectArrivalSession(junk.Arrivals) == nil,
			"a lobby-bound or malformed packet forms no round session")

		local launch = newDestination()
		local packet = Routing.ArrivalPacket({
			Level = 1, SessionId = "JOB:station2:1", Expected = 2, Final = true,
		})
		launch:arrive({Member = "ana", Data = packet}, 0)
		check(report, launch:decide(0.5, opened) == "wait",
			"a station launch waits for its whole party")
		launch:arrive({Member = "bo", Data = packet}, 1)
		check(report, launch:decide(1.5, opened) == "admit",
			"and starts the moment the whole party is there")

		local skewed = newDestination()
		skewed:arrive({Member = "ana", Data = Routing.ArrivalPacket({
			Level = 1, SessionId = "JOB:skew:1", Expected = 4,
			Deadline = opened + 10000, Final = false,
		})}, 0)
		check(report, skewed:decide(Routing.AdmissionLocalCapSeconds + 1, opened + 1) == "admit",
			"an unreachable deadline is bounded by the destination's own cap")

		local mixed = newDestination()
		local mine = Routing.ArrivalPacket({Level = 2, SessionId = "S-MAIN", Expected = 2, Final = true})
		local stray = Routing.ArrivalPacket({Level = 1, SessionId = "S-STRAY", Expected = 1, Final = true})
		mixed:arrive({Member = "ana", Data = mine}, 0)
		mixed:arrive({Member = "bo", Data = mine}, 0)
		mixed:arrive({Member = "zed", Data = stray}, 0)
		local mixedGroup = Routing.SelectArrivalSession(mixed.Arrivals)
		check(report, mixedGroup ~= nil and mixedGroup.SessionId == "S-MAIN"
			and #mixedGroup.Members == 2,
			"a stray reconnect cannot take the round from the real session",
			mixedGroup and mixedGroup.SessionId or "nil")
	end

	-- (6) The Level 2 exit-tube entry mode survives the whole handshake.
	do
		local source = newSource({
			Party = {"ana", "bo"}, Level = 2, Now = opened, EntryMode = "level2-exit-tube",
		})
		local destination = newDestination()
		local early = source:continueNow("ana")
		source:playerRemoving("ana")
		destination:arrive({Member = "ana", Data = early}, 1)
		local final = source:settle()
		destination:arrive({Member = "bo", Data = final}, 16)
		local decision, group = destination:decide(16, deadlineAt + 1)
		check(report, decision == "admit" and group and group.EntryMode == "level2-exit-tube",
			"both continuers arrive in Level 3's continuation bore, not on a pad",
			group and tostring(group.EntryMode) or "nil")
		check(report, early.EntryMode == final.EntryMode,
			"the instant continuer and the timed-out continuer enter the same way")
		check(report, group ~= nil and #group.Members == 2,
			"and the early departure did not cost the cohort a member",
			group and tostring(#group.Members) or "nil")
	end

	-- (7) A STALE ESTIMATE MAY NOT OVERWRITE AN AUTHORITATIVE COHORT.
	--
	-- Packets arrive in transport order, not in the order they were written. A
	-- Back to Lobby that Roblox refuses is re-armed, which puts that player back
	-- among the continuers and makes the cohort GROW -- so an early continuer's
	-- packet, written before that happened, carries a SMALLER number than the
	-- settlement's exact one. Applying it was how the destination started a
	-- round with a player still in transit.
	do
		local source = newSource({Party = {"ana", "bo", "cy"}, Level = 1, Now = opened})
		local destination = newDestination()

		source:backToLobby("bo")
		local early = source:continueNow("ana")
		check(report, early.ExpectedContinuers == 2 and early.FinalCohort == false,
			"the early continuer's packet is a non-final estimate of two",
			string.format("%s / final=%s", tostring(early.ExpectedContinuers),
				tostring(early.FinalCohort)))

		-- Roblox refuses bo's Back; production re-arms their choice.
		check(report, Routing.ClearDecision(source.Roster, "bo"),
			"a refused Back to Lobby gives that player their choice back")
		check(report, source:expected() == 3,
			"which makes the cohort GROW to three", tostring(source:expected()))

		local final, continuing = source:settle()
		check(report, final.FinalCohort == true and final.ExpectedContinuers == 3,
			"and the settlement packet is authoritative at three",
			string.format("final=%s expected=%s", tostring(final.FinalCohort),
				tostring(final.ExpectedContinuers)))
		check(report, names(continuing) == "bo,cy",
			"with bo carried onward rather than returned", names(continuing))

		-- C lands first with the FINAL packet; A's stale estimate lands after.
		destination:arrive({Member = "cy", Data = final}, 16)
		local decision, group = destination:decide(16, deadlineAt + 1)
		check(report, group ~= nil and group.Final == true and group.Expected == 3,
			"the destination takes the authoritative three",
			group and string.format("final=%s expected=%s", tostring(group.Final),
				tostring(group.Expected)) or "nil")
		check(report, decision == "wait", "and waits: one of three has landed",
			tostring(decision))

		destination:arrive({Member = "ana", Data = early}, 17)
		decision, group = destination:decide(17, deadlineAt + 2)
		check(report, group ~= nil and group.Final == true,
			"the late stale estimate cannot un-finalise the session",
			group and tostring(group.Final) or "nil")
		check(report, group ~= nil and group.Expected == 3,
			"nor shrink the authoritative head count",
			group and tostring(group.Expected) or "nil")
		check(report, decision == "wait",
			"so the round still waits for the player who is still in transit",
			tostring(decision))

		destination:arrive({Member = "bo", Data = final}, 18)
		decision, group = destination:decide(18, deadlineAt + 3)
		check(report, decision == "admit" and group and #group.Members == 3,
			"and admits all three into one round once the last one lands",
			group and tostring(#group.Members) or "nil")

		-- The authority rule itself, stated directly.
		check(report, Routing.PacketAuthority(final) > Routing.PacketAuthority(early),
			"a settlement packet outranks an estimate")
		check(report, Routing.PacketAuthority(nil) == Routing.EstimateAuthority,
			"and anything unrecognisable ranks as an estimate")
	end

	-- (8) SOLO / ALL-EARLY CONTINUE. Everybody presses Continue at once, so the
	-- settlement has nobody left to carry and never sends a final packet.
	--
	-- This is NOT a defect and must not be read as one. Continue means the
	-- player leaves the COMPLETED SERVER immediately -- asserted below on the
	-- source side. The destination then stages them, as it stages every
	-- continuer, until the source's decision deadline plus a bounded transport
	-- grace, because until that deadline passes it cannot know whether anybody
	-- else is still coming. They are a full participant throughout, never a
	-- spectator, and they are admitted no later than deadline + grace even
	-- though no final packet ever arrives.
	do
		local source = newSource({Party = {"ana"}, Level = 1, Now = opened})
		local destination = newDestination()
		local packet = source:continueNow("ana")
		check(report, Routing.HasDeparted(source.Roster, "ana"),
			"the solo continuer leaves the completed server immediately")
		source:playerRemoving("ana")
		check(report, Routing.DecisionOf(source.Roster, "ana") == Routing.Continuing,
			"and stays a continuer after PlayerRemoving",
			tostring(Routing.DecisionOf(source.Roster, "ana")))
		local _, continuing = source:settle()
		check(report, #continuing == 0,
			"the settlement has nobody left to carry, so no final packet is sent",
			names(continuing))

		destination:arrive({Member = "ana", Data = packet}, 1)
		local group = Routing.SelectArrivalSession(destination.Arrivals)
		check(report, group ~= nil and #group.Members == 1,
			"the destination still recognises them as this session's party",
			group and tostring(#group.Members) or "nil")
		check(report, group ~= nil and group.Final == false,
			"with no authoritative packet to mark it final",
			group and tostring(group.Final) or "nil")
		check(report, destination:decide(2, opened + 2) == "wait",
			"they are staged while the source's window is still open")
		check(report, destination:decide(3, deadlineAt + Routing.TransportGraceSeconds) == "admit",
			"and admitted at the deadline plus the bounded transport grace",
			destination:decide(3, deadlineAt + Routing.TransportGraceSeconds))
		check(report, destination:decide(3, deadlineAt - 1) == "wait",
			"never before the deadline")
		-- Even with the deadline unreadable, the destination's own cap admits.
		local capped = newDestination()
		capped:arrive({Member = "ana", Data = Routing.ArrivalPacket({
			Level = 2, SessionId = "solo-no-deadline", Expected = 1, Final = false,
		})}, 0)
		check(report, capped:decide(Routing.AdmissionLocalCapSeconds + 1, opened) == "admit",
			"and the local cap admits them even with no deadline at all")
	end

	-- (9) Level 3 is the end of the campaign.
	do
		local source = newSource({Party = {"ana"}, Level = 3, Now = opened})
		check(report, source.NextLevel == nil,
			"a finished Level 3 has nowhere to continue to", tostring(source.NextLevel))
	end

	return report
end

-- ---------------------------------------------------------------------------
-- Transfers -- claims, attempts and failure reports
-- ---------------------------------------------------------------------------

-- A real TeleportOptions carrying real teleport data, which is exactly what
-- Roblox hands back to TeleportInitFailed. Correlation is tested against these,
-- not against a hand-written record.
local function optionsFor(attemptId, extra)
	local options = Instance.new("TeleportOptions")
	local data = extra and table.clone(extra) or {}
	data.TransferAttemptId = attemptId
	options:SetTeleportData(data)
	return options
end

-- The production failure path, in the order GameManager's handler runs it.
local function reportFailure(claims, member, options)
	local attemptId = Routing.AttemptIdOf(options)
	return Routing.FailAttempt(claims, member, attemptId, options)
end

function Suite.Transfers()
	local report = newReport("Transfer claims, attempts and failure reports")

	-- A claim is exclusive while it is unresolved.
	do
		local claims = {}
		local first = Routing.ClaimTransfer(claims, "ana", "lobby")
		local second = Routing.ClaimTransfer(claims, "ana", "next")
		check(report, first == true and second == false,
			"only one path may claim a player at a time")
		check(report, Routing.TransferState(claims, "ana") == Routing.Pending,
			"an accepted TeleportAsync leaves the claim PENDING, not succeeded",
			tostring(Routing.TransferState(claims, "ana")))
		check(report, not Routing.TransfersResolved(claims),
			"a pending claim is not a settled transfer")
	end

	-- Attempt ids are unique and travel in the teleport data.
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "next")
		Routing.ClaimTransfer(claims, "bo", "next")
		local id = Routing.NewAttemptId()
		local options = optionsFor(id, {BackroomsRound = true})
		Routing.BeginAttempt(claims, "ana", "next", id, options, 1, 0, {Kind = "next"})
		Routing.BeginAttempt(claims, "bo", "next", id, options, 1, 0, {Kind = "next"})
		check(report, Routing.AttemptOf(claims, "ana") == id
			and Routing.AttemptOf(claims, "bo") == id,
			"one TeleportAsync call is one attempt, however many players ride it")
		check(report, Routing.AttemptIdOf(options) == id,
			"and the id is readable back out of the TeleportOptions Roblox returns",
			tostring(Routing.AttemptIdOf(options)))
		check(report, Routing.NewAttemptId() ~= id, "every new attempt gets a new id")
		check(report, Routing.AttemptIdOf(Instance.new("TeleportOptions")) == nil,
			"options with no attempt id correlate to nothing")
	end

	-- DUPLICATE CALLBACK BEFORE RESOLUTION. Roblox reports the same failed
	-- request twice; only the first may be charged.
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "next")
		local id = Routing.NewAttemptId()
		local options = optionsFor(id)
		Routing.BeginAttempt(claims, "ana", "next", id, options, 1, 0, {Kind = "next"})
		local firstPlan = reportFailure(claims, "ana", options)
		check(report, firstPlan == "retry", "the first report earns one retry",
			tostring(firstPlan))
		check(report, claims.ana.Failures == 1, "and charges exactly one failure",
			tostring(claims.ana.Failures))
		local duplicate = reportFailure(claims, "ana", options)
		check(report, duplicate == nil,
			"a SECOND report of the same attempt is a no-op", tostring(duplicate))
		check(report, claims.ana.Failures == 1,
			"so one rejection cannot consume the retry AND the fallback at once",
			tostring(claims.ana.Failures))
		-- The retry: a fresh id, so the old attempt's reports are dead.
		local retryId = Routing.NewAttemptId()
		local retryOptions = optionsFor(retryId)
		Routing.BeginAttempt(claims, "ana", "next", retryId, retryOptions, 1, 1, {Kind = "next"})
		local stale = reportFailure(claims, "ana", options)
		check(report, stale == nil,
			"a late report of the superseded attempt is a no-op", tostring(stale))
		check(report, claims.ana.Failures == 1,
			"and cannot inflate the failure counter", tostring(claims.ana.Failures))
		local retryPlan = reportFailure(claims, "ana", retryOptions)
		check(report, retryPlan == "fallback",
			"the retry's OWN failure is what escalates to the lobby fallback",
			tostring(retryPlan))
		check(report, claims.ana.Failures == 2, "on exactly two charged attempts",
			tostring(claims.ana.Failures))
	end

    -- STALE NEXT-LEVEL CALLBACK AFTER LOBBY FALLBACK. The next-level transfer
    -- failed twice and fell back to a fresh lobby claim. A report from the dead
    -- next-level attempt must not touch that claim.
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "next")
		local nextId = Routing.NewAttemptId()
		local nextOptions = optionsFor(nextId, {BackroomsRound = true})
		local nextDescriptor = {Kind = "next", AccessCode = "RESERVED-CODE"}
		Routing.BeginAttempt(claims, "ana", "next", nextId, nextOptions, 1, 0, nextDescriptor)
		reportFailure(claims, "ana", nextOptions)
		local id2 = Routing.NewAttemptId()
		local options2 = optionsFor(id2, {BackroomsRound = true})
		Routing.BeginAttempt(claims, "ana", "next", id2, options2, 1, 1, nextDescriptor)
		local plan = reportFailure(claims, "ana", options2)
		check(report, plan == "fallback", "a next-level transfer that fails twice falls back",
			tostring(plan))
		-- Production then marks the fallback, resolves the dead claim, and takes
		-- a brand new LOBBY claim.
		Routing.MarkFellBack(claims, "ana")
		Routing.ResolveTransfer(claims, "ana", Routing.Failed)
		check(report, Routing.ClaimTransfer(claims, "ana", "lobby"),
			"and a fresh lobby claim can be taken")
		local lobbyId = Routing.NewAttemptId()
		local lobbyOptions = optionsFor(lobbyId, {ReturnToLobby = true})
		local lobbyDescriptor = {Kind = "lobby", Data = {ReturnToLobby = true}}
		Routing.BeginAttempt(claims, "ana", "lobby", lobbyId, lobbyOptions, 1, 2, lobbyDescriptor)
		check(report, claims.ana.Failures == 0,
			"the fresh claim starts with a clean failure count",
			tostring(claims.ana.Failures))

		local poison = reportFailure(claims, "ana", options2)
		check(report, poison == nil,
			"the dead next-level report cannot charge the fresh lobby claim",
			tostring(poison))
		check(report, claims.ana.Failures == 0,
			"its failure counter is untouched", tostring(claims.ana.Failures))
		check(report, Routing.TransferState(claims, "ana") == Routing.Pending,
			"and the lobby transfer is still in flight",
			tostring(Routing.TransferState(claims, "ana")))
		-- STALE OPTIONS ARE NEVER RETRIED: the descriptor a retry rebuilds from
		-- is the LOBBY one, never the reserved-server options that just died.
		local descriptor = Routing.DescriptorOf(claims, "ana")
		check(report, descriptor ~= nil and descriptor.Kind == "lobby",
			"a retry would rebuild the lobby request, not the dead next-level one",
			descriptor and tostring(descriptor.Kind) or "nil")
		check(report, descriptor ~= nil and descriptor.AccessCode == nil,
			"and would not carry the old reservation code")
		-- The lobby attempt's own report still works.
		local lobbyPlan = reportFailure(claims, "ana", lobbyOptions)
		check(report, lobbyPlan == "retry", "the live lobby attempt can still fail normally",
			tostring(lobbyPlan))
		check(report, claims.ana.Failures == 1, "charging exactly one failure",
			tostring(claims.ana.Failures))
		local lobbyRetryId = Routing.NewAttemptId()
		local lobbyRetryOptions = optionsFor(lobbyRetryId, {ReturnToLobby = true})
		Routing.BeginAttempt(claims, "ana", "lobby", lobbyRetryId, lobbyRetryOptions,
			1, 3, lobbyDescriptor)
		check(report, reportFailure(claims, "ana", lobbyRetryOptions) == "surrender",
			"a lobby transfer has no fallback -- the lobby IS the fallback")
	end

	-- A report for a claim that never had an attempt, or for a stranger.
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "next")
		check(report, reportFailure(claims, "ana", optionsFor(999)) == nil,
			"a report for an attempt this claim never made is a no-op")
		check(report, reportFailure(claims, "zed", optionsFor(1)) == nil,
			"a report for a player with no claim at all is a no-op")
		check(report, Routing.FailAttempt(claims, "ana", nil, nil) == nil,
			"and an uncorrelatable report is refused rather than guessed at")
	end

	-- Early Back and early Continue failures release the player.
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "lobby")
		check(report, Routing.ResolveTransfer(claims, "ana", Routing.Failed),
			"a rejected early Back resolves its claim as failed")
		check(report, Routing.TransfersResolved(claims), "and the session stops waiting on it")
		check(report, names(Routing.LobbyBound({"ana", "bo"}, {}, claims)) == "ana,bo",
			"the settlement sweep may now send that player to the lobby",
			names(Routing.LobbyBound({"ana", "bo"}, {}, claims)))
		check(report, Routing.ClaimTransfer(claims, "ana", "lobby") == true,
			"a failed claim can be re-taken by exactly one new authority")
	end

	-- The final sweep runs while an early claim is still PENDING.
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "next")
		Routing.ClaimTransfer(claims, "bo", "lobby")
		check(report, names(Routing.LobbyBound({"ana", "bo", "cy"}, {}, claims)) == "cy",
			"the sweep skips both in-flight players and takes only the undecided one",
			names(Routing.LobbyBound({"ana", "bo", "cy"}, {}, claims)))
		check(report, not Routing.TransfersResolved(claims),
			"the session is not settled while either claim is pending")
		check(report, names(Routing.PendingTransfers(claims)) == "ana,bo",
			"and it can name exactly who it is still waiting for",
			names(Routing.PendingTransfers(claims)))
		Routing.ResolveTransfer(claims, "ana", Routing.Succeeded)
		Routing.ResolveTransfer(claims, "bo", Routing.Failed)
		check(report, Routing.TransfersResolved(claims),
			"settlement completes once every claim has an answer")
		check(report, names(Routing.LobbyBound({"ana", "bo", "cy"}, {}, claims)) == "bo,cy",
			"the failed one rejoins the sweep while the departed one does not",
			names(Routing.LobbyBound({"ana", "bo", "cy"}, {}, claims)))
	end

	-- The player leaves, and a report arrives afterwards.
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "next")
		local id = Routing.NewAttemptId()
		local options = optionsFor(id)
		Routing.BeginAttempt(claims, "ana", "next", id, options, 1, 0, {Kind = "next"})
		Routing.ResolveTransfer(claims, "ana", Routing.Succeeded)  -- PlayerRemoving
		check(report, reportFailure(claims, "ana", options) == nil,
			"a TeleportInitFailed arriving after the player left is a no-op")
		check(report, Routing.TransferState(claims, "ana") == Routing.Succeeded,
			"and cannot un-depart them", tostring(Routing.TransferState(claims, "ana")))
	end

	-- An attempt nobody ever reports on still has to end.
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "next")
		local id = Routing.NewAttemptId()
		Routing.BeginAttempt(claims, "ana", "next", id, optionsFor(id), 1, 100, {Kind = "next"})
		check(report, #Routing.SweepTransfers(claims, 105, 25) == 0,
			"a young attempt is left alone")
		local actions = Routing.SweepTransfers(claims, 130, 25)
		check(report, #actions == 1 and actions[1].Member == "ana"
			and actions[1].Kind == "attempt",
			"a silent attempt is eventually reported by the sweep",
			#actions > 0 and tostring(actions[1].Kind) or "none")
		check(report, Routing.TransferState(claims, "ana") == Routing.Pending
			and claims.ana.Failures == 0,
			"which REPORTS and charges nothing -- charging is AttemptFailure's alone",
			tostring(Routing.TransferState(claims, "ana")) .. "/" .. tostring(claims.ana.Failures))
		local plan = Routing.AttemptFailure(claims, "ana", Routing.FailureSources.Timeout,
			nil, nil, 130)
		check(report, plan == "retry" and claims.ana.Failures == 1,
			"and the timeout enters the SAME transition a callback does",
			tostring(plan) .. "/" .. tostring(claims.ana.Failures))
		check(report, Routing.AttemptFailure(claims, "ana", Routing.FailureSources.Timeout,
			nil, nil, 131) == nil and claims.ana.Failures == 1,
			"exactly once, however many times it is swept",
			tostring(claims.ana.Failures))
	end

	return report
end

-- ---------------------------------------------------------------------------
-- Teardown -- what happens to the completed world
-- ---------------------------------------------------------------------------

function Suite.Teardown()
	local report = newReport("Completed-world teardown")

	check(report, Routing.TeardownPlan({Accepted = true, Reserved = true}) == "released",
		"a reserved server whose party Roblox accepted just lets the world go",
		Routing.TeardownPlan({Accepted = true, Reserved = true}))
	check(report, Routing.TeardownPlan({Accepted = false, Reserved = true}) == "keep-world",
		"a REFUSED reserved-server transfer keeps the map under the stranded party",
		Routing.TeardownPlan({Accepted = false, Reserved = true}))
	check(report, Routing.TeardownPlan({Accepted = false, Reserved = false}) == "local-lobby",
		"a public server tears down and stands them up in its own lobby",
		Routing.TeardownPlan({Accepted = false, Reserved = false}))
	check(report, Routing.TeardownPlan({Accepted = true, Reserved = false}) == "local-lobby",
		"and so does a public server whose transfer was accepted",
		Routing.TeardownPlan({Accepted = true, Reserved = false}))
	check(report, Routing.TeardownPlan({Accepted = true, Reserved = true, Studio = true}) == "local-lobby",
		"Studio always recovers locally: it has no destination to send anyone to",
		Routing.TeardownPlan({Accepted = true, Reserved = true, Studio = true}))
	check(report, Routing.TeardownPlan({Accepted = false, Reserved = true, Studio = true}) == "local-lobby",
		"including when its local transfer is refused",
		Routing.TeardownPlan({Accepted = false, Reserved = true, Studio = true}))

	-- The three places production asks the question. The answer is the same in
	-- all of them, which is the point: none of them may delete a world out from
	-- under a player Roblox declined to move.
	for _, place in ipairs({"the Level 3 endpoint", "a lost round", "a refused next-level fallback"}) do
		check(report, Routing.TeardownPlan({Accepted = false, Reserved = true}) == "keep-world",
			place .. ": a refused reserved-server transfer keeps the world")
	end
	check(report, Routing.TeardownPlan({}) == "local-lobby",
		"an unknown context recovers locally rather than stranding anybody",
		Routing.TeardownPlan({}))

	-- And a kept world still has an owner for every player in it.
	local claims = {}
	Routing.ClaimTransfer(claims, "ana", "lobby")
	Routing.ResolveTransfer(claims, "ana", Routing.Failed)
	check(report, names(Routing.LobbyBound({"ana"}, {}, claims)) == "ana",
		"a player whose lobby transfer was refused is claimable again",
		names(Routing.LobbyBound({"ana"}, {}, claims)))
	check(report, Routing.TransfersResolved(claims),
		"and holds nothing that would keep the settlement waiting")

	return report
end

-- ---------------------------------------------------------------------------
-- Endpoints -- the transfer runtime, on a fake clock
-- ---------------------------------------------------------------------------
--
-- This suite used to call pure helpers and check that GameManager's SOURCE
-- mentioned the right names. Both are worthless against the three defects it
-- now guards, and all three shipped underneath it:
--
--   * it asserted `Routing.RetryPlan(claims.ana) == "retry"` and then opened a
--     lobby claim BY HAND, so it never noticed that the production timeout path
--     did not apply the retry it had just proved was owed;
--   * it called the expiry sweep directly, so it never saw that the sweep
--     charged an attempt a callback had already charged, and cancelled the
--     retry that charge had authorised;
--   * it read the settlement wait as a number, so it never saw that no endpoint
--     waited for a retry, or that all four discarded the answer.
--
-- Everything below drives Routing.NewTransferRuntime -- the SAME object
-- GameManager builds -- over a deterministic fake clock and a scripted
-- dispatcher. No real teleport, no os.clock, no wall time.

-- The fake clock, with TWO independent escape hatches.
--
-- `Steps` counts TIMERS FIRED, and for a long time that was the only guard. It
-- does not bound a settlement loop that never schedules anything: such a loop
-- calls Wait -> Advance, Advance finds no timer to run, `Steps` never moves, and
-- the loop spins on pure CPU forever. That is not hypothetical -- a mutation run
-- in this repo wedged Studio for twenty minutes on exactly that shape and the
-- editor had to be restarted, because the guard it was relying on could not see
-- a loop that did no work.
--
-- So `Advances` counts every call INTO the clock whether or not anything was
-- scheduled, and `Horizon` bounds simulated time. Neither is a CPU-time or
-- wall-clock measure: both are properties of the simulation, so they fire
-- identically on a fast machine and a slow one. A test that legitimately needs
-- to simulate longer raises `clock.Horizon` deliberately and says why.
local CLOCK_MAX_ADVANCES = 100000
local CLOCK_HORIZON_SECONDS = 5000

local function newClock()
	local clock = {T = 0, Timers = {}, Seq = 0, Steps = 0, Advances = 0,
		Horizon = CLOCK_HORIZON_SECONDS}
	function clock.Now() return clock.T end
	function clock.Delay(seconds, fn)
		clock.Seq += 1
		table.insert(clock.Timers, {At = clock.T + (tonumber(seconds) or 0), Seq = clock.Seq, Fn = fn})
	end
	function clock.Spawn(fn, ...)
		local packed = table.pack(...)
		clock.Delay(0, function() fn(table.unpack(packed, 1, packed.n)) end)
	end
	function clock.Advance(dt)
		-- Counted BEFORE any work, so a call that schedules and runs nothing is
		-- still counted. This is the guard that catches a timer-free spin.
		clock.Advances += 1
		assert(clock.Advances < CLOCK_MAX_ADVANCES,
			"fake clock: " .. CLOCK_MAX_ADVANCES .. " advances without the test resolving")
		local target = clock.T + dt
		assert(target <= clock.Horizon,
			string.format("fake clock: simulated time passed its horizon (%.2f > %d)",
				target, clock.Horizon))
		while true do
			local soonest, index
			for i, t in ipairs(clock.Timers) do
				if t.At <= target and (not soonest or t.At < soonest.At
					or (t.At == soonest.At and t.Seq < soonest.Seq)) then soonest, index = t, i end
			end
			if not soonest then break end
			table.remove(clock.Timers, index)
			clock.T = math.max(clock.T, soonest.At)
			clock.Steps += 1
			assert(clock.Steps < 20000, "fake clock ran away")
			soonest.Fn()
		end
		clock.T = target
	end
	function clock.Wait(s) clock.Advance((tonumber(s) or 0) > 0 and s or Routing.SettlementPollSeconds) end
	return clock
end

-- The injected transport. `spec` scripts what it does, keyed by the 1-BASED
-- ORDINAL of the call, so a test can say "the second dispatch is refused" or
-- "the first lobby request raises" without reaching into the runtime:
--
--   spec = {
--     Dispatch      = {[1] = false, [2] = true},   -- synchronous rejection
--     DispatchThrows = {[1] = "boom"},             -- the transport RAISES
--     Lobby         = {[1] = false},               -- the lobby request refused
--     LobbyThrows   = {[1] = "boom"},
--   }
--
-- It used to be dead scaffolding: `spec.Dispatch[#env.Dispatches] == false` was
-- the only thing read, nothing could script a throw, and no call site passed a
-- spec at all -- so release blocker A5, a synchronous refusal that never
-- entered the failure policy, had no way to be written down. Every existing
-- two-argument call site still behaves exactly as before: with no spec, every
-- dispatch succeeds.
local function newEnv(clock, claims, spec)
	spec = spec or {}
	local env = {
		Claims = claims, Now = clock.Now, Delay = clock.Delay, Spawn = clock.Spawn,
		Wait = clock.Wait, Present = function() return true end,
		Dispatches = {}, LobbyCalls = {}, Surrenders = {}, Notices = {}, Warnings = {},
		Reserved = true, Studio = false,
	}
	local dispatchOrdinal, lobbyOrdinal = 0, 0
	-- `refuse` is how LobbyTransfer scripts its OWN rejection without having to
	-- know which dispatch ordinal it will land on.
	env.Dispatch = function(member, descriptor, refuse)
		dispatchOrdinal += 1
		local ordinal = dispatchOrdinal
		local thrown = spec.DispatchThrows and spec.DispatchThrows[ordinal]
		if thrown ~= nil then
			-- The transport raised BEFORE anything was dispatched: no attempt is
			-- stamped, exactly as a TeleportOptions constructor that throws.
			error(thrown, 0)
		end
		local id = Routing.NewAttemptId()
		Routing.BeginAttempt(claims, member, descriptor.Kind, id, optionsFor(id), 1, clock.Now(), descriptor)
		table.insert(env.Dispatches, {Member = member, Kind = descriptor.Kind,
			AccessCode = descriptor.AccessCode, AttemptId = id, At = clock.Now(),
			Ordinal = ordinal})
		local ok = not (refuse == true or (spec.Dispatch and spec.Dispatch[ordinal] == false))
		return ok, (not ok) and "REJECTED" or nil, id
	end
	env.LobbyTransfer = function(member)
		lobbyOrdinal += 1
		local ordinal = lobbyOrdinal
		table.insert(env.LobbyCalls, {Member = member, At = clock.Now(), Ordinal = ordinal})
		local thrown = spec.LobbyThrows and spec.LobbyThrows[ordinal]
		if thrown ~= nil then error(thrown, 0) end
		if not Routing.ClaimTransfer(claims, member, "lobby", clock.Now()) then
			return false, "ALREADY_CLAIMED"
		end
		local refuse = spec.Lobby ~= nil and spec.Lobby[ordinal] == false
		local ok, err, id = env.Dispatch(member, {Kind = "lobby", Data = {ReturnToLobby = true}}, refuse)
		if not ok then
			-- PRODUCTION SHAPE (A5): teleportPlayersToLobby reports a refused
			-- dispatch through the runtime instead of resolving the claim by
			-- hand, so the lobby transfer earns its retry like any other.
			if env.Runtime then env.Runtime:ReportDispatchFailure(member, id, err) end
			return false, err or "REJECTED"
		end
		return true, nil
	end
	env.Surrender = function(m, r) table.insert(env.Surrenders, {Member = m, Reason = r, At = clock.Now()}) end
	env.Notify = function(m, e) table.insert(env.Notices, {Member = m, Event = e}) end
	env.Warn = function(t) table.insert(env.Warnings, t) end
	return env
end

local function stageNext(clock, claims, env, member)
	Routing.ClaimTransfer(claims, member, "next")
	env.Dispatch(member, {Kind = "next", AccessCode = "RESERVED-CODE", Data = {}})
	return env.Dispatches[#env.Dispatches].AttemptId
end

function Suite.Endpoints()
	local report = newReport("Endpoint settlement and the silent-transfer watchdog")

	-- The timings are ONE policy, and it must cover the whole lineage.
	check(report, Routing.SettlementCoversTimeout(),
		"an endpoint waits long enough for the watchdog to have expired a silent attempt",
		string.format("lineage %s, timeout %s, sweep %s",
			tostring(Routing.SettlementLineageSeconds),
			tostring(Routing.TransferTimeoutSeconds),
			tostring(Routing.WatchdogIntervalSeconds)))
	check(report, Routing.SettlementCoversRetryLineage(),
		"the settlement covers attempt + sweep + retry delay + retry + sweep + grace",
		string.format("lineage %s vs worst case %s, hard cap %s",
			tostring(Routing.SettlementLineageSeconds),
			tostring(Routing.LineageWorstCaseSeconds()),
			tostring(Routing.SettlementHardCapSeconds)))
	check(report, Routing.WatchdogIntervalSeconds > 0
		and Routing.WatchdogIntervalSeconds < Routing.TransferTimeoutSeconds,
		"the sweep runs several times inside one stale window",
		tostring(Routing.WatchdogIntervalSeconds))
	check(report, Routing.RetryHandoffGraceSeconds > Routing.RetryDelaySeconds,
		"and the sweep cannot steal a retry it authorised itself",
		string.format("grace %s vs delay %s",
			tostring(Routing.RetryHandoffGraceSeconds), tostring(Routing.RetryDelaySeconds)))

-- ============ T1: callback at 24.5s, then the age-25 sweep ============
note(report, "=== T1 callback@24.5 then sweep@25 ===")
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	local first = stageNext(clock, claims, env, "ana")
	clock.Advance(24.5)
	rt:ReportFailure("ana", first, optionsFor(first), "REJECTED")
	local token = Routing.HandoffToken(claims, "ana")
	check(report, claims.ana.Failures == 1, "callback charges exactly one failure", claims.ana.Failures)
	check(report, Routing.HandoffPlan(claims, "ana") == "retry" and claims.ana.State == Routing.Pending,
		"awards a retry without resolving", Routing.HandoffPlan(claims, "ana"))
	clock.T = 25.0
	rt:Sweep("watchdog")
	check(report, claims.ana.Failures == 1, "sweep does not charge an already-charged attempt", claims.ana.Failures)
	check(report, claims.ana.State == Routing.Pending, "and does not cancel the retry", claims.ana.State)
	check(report, Routing.HandoffToken(claims, "ana") == token, "nor steal its handoff")
	check(report, #env.Dispatches == 1, "and dispatches nothing of its own", #env.Dispatches)
	clock.Advance(1.0)
	check(report, #env.Dispatches == 2, "exactly one retry is dispatched", #env.Dispatches)
	check(report, #env.Dispatches == 2 and env.Dispatches[2].Kind == "next"
		and env.Dispatches[2].AccessCode == "RESERVED-CODE", "to the SAME destination")
	check(report, claims.ana.Failures == 1, "one rejection cost exactly one failure", claims.ana.Failures)
	check(report, claims.ana.LineageStartedAt == 0, "lineage still starts at the first attempt", claims.ana.LineageStartedAt)
end
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	local first = stageNext(clock, claims, env, "ana")
	clock.T = 25.0; rt:Sweep("watchdog")
	rt:ReportFailure("ana", first, optionsFor(first), "LATE")
	clock.Advance(2)
	check(report, claims.ana.Failures == 1 and #env.Dispatches == 2,
		"sweep-then-callback also charges once and retries once",
		claims.ana.Failures .. "/" .. #env.Dispatches)
end

-- ============ T2: silent first next-level attempt ============
note(report, "=== T2 silent first next-level attempt ===")
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	stageNext(clock, claims, env, "ana")
	-- A1: a NEXT-level claim is cohort-bound, so its stale threshold is the
	-- module's, not the 25s lobby one this block used to step through by hand.
	-- Sweeping on the module's own cadence keeps the block honest whichever
	-- threshold the policy is set to.
	local staleAt = Routing.TimeoutForDestination("next")
	local sweepStep = Routing.SweepIntervalSeconds()
	while clock.T + sweepStep < staleAt do
		clock.Advance(sweepStep)
		rt:Sweep("watchdog")
	end
	check(report, claims.ana.Failures == 0 and #env.Dispatches == 1, "a young silent attempt is left alone")
	clock.Advance(sweepStep); rt:Sweep("watchdog")
	check(report, claims.ana.Failures == 1, "the silent attempt charges exactly one failure", claims.ana.Failures)
	check(report, Routing.HandoffPlan(claims, "ana") == "retry", "enters the SAME policy as a callback",
		Routing.HandoffPlan(claims, "ana"))
	check(report, claims.ana.State == Routing.Pending, "without resolving the claim", claims.ana.State)
	clock.Advance(Routing.RetryDelaySeconds + 0.1)
	check(report, #env.Dispatches == 2 and env.Dispatches[2].Kind == "next",
		"the retry goes to the NEXT LEVEL, not the lobby",
		#env.Dispatches == 2 and env.Dispatches[2].Kind or "none")
	check(report, #env.LobbyCalls == 0, "no lobby transfer was started", #env.LobbyCalls)
	check(report, #env.Surrenders == 0, "and nobody was surrendered", #env.Surrenders)
end

-- ============ T3: silent retry -> terminal fallback ============
note(report, "=== T3 silent retry -> fallback -> surrender ===")
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	stageNext(clock, claims, env, "ana")
	local nextRecord = claims.ana
	-- A1: driven to the state under test rather than to a fixed 70 seconds,
	-- which was two next-level lineages under the OLD lobby threshold and is
	-- several under the cohort one.
	local sweepStep = Routing.SweepIntervalSeconds()
	for _ = 1, 2000 do
		if #env.LobbyCalls > 0 then break end
		clock.Advance(sweepStep)
		rt:Sweep("watchdog")
	end
	check(report, nextRecord.Failures == 2, "the retry's silence charges the second failure", nextRecord.Failures)
	check(report, nextRecord.State == Routing.Failed and nextRecord.FellBack == true,
		"the dead next-level claim is terminal and fell back",
		tostring(nextRecord.State) .. "/" .. tostring(nextRecord.FellBack))
	check(report, #env.LobbyCalls == 1, "exactly one lobby escape is opened", #env.LobbyCalls)
	check(report, claims.ana ~= nextRecord and claims.ana.Destination == "lobby" and claims.ana.Failures == 0,
		"on a FRESH claim with a clean budget",
		tostring(claims.ana.Destination) .. "/" .. tostring(claims.ana.Failures))
	check(report, claims.ana.LineageStartedAt == 0,
		"which INHERITS the lineage clock so the cap stays reachable", claims.ana.LineageStartedAt)
	for _ = 1, 2000 do
		if #Routing.PendingTransfers(claims) == 0 then break end
		clock.Advance(sweepStep)
		rt:Sweep("watchdog")
	end
	clock.Advance(0)
	local lobbyDispatches = 0
	for _, d in ipairs(env.Dispatches) do if d.Kind == "lobby" then lobbyDispatches += 1 end end
	check(report, lobbyDispatches == 2, "a lobby transfer retries once, and only once", lobbyDispatches)
	check(report, #env.Surrenders == 1, "then surrenders exactly once -- the lobby IS the fallback", #env.Surrenders)
	check(report, #Routing.PendingTransfers(claims) == 0, "leaving no pending claim behind",
		#Routing.PendingTransfers(claims))
end

-- ============ T4: retry begun late extends settlement ============
note(report, "=== T4 late retry extends settlement past 35s ===")
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	local first = stageNext(clock, claims, env, "ana")
	clock.Delay(20, function() rt:ReportFailure("ana", first, optionsFor(first), "REJECTED") end)
	clock.Delay(80, function() Routing.ResolveTransfer(claims, "ana", Routing.Succeeded) end)
	local settled, stranded = rt:AwaitSettlement(Routing.Endpoints.Continuation)
	check(report, clock.T > 35, "did not return at the old 35s deadline", string.format("t=%.2f", clock.T))
	check(report, clock.T >= 46, "followed the lineage across attempt ids", string.format("t=%.2f", clock.T))
	check(report, settled == true and #stranded == 0, "and reports the endpoint settled",
		tostring(settled) .. "/" .. tostring(#stranded))
end

-- ============ T5: repeated sweeps / duplicate callbacks are no-ops ============
note(report, "=== T5 repeated sweeps and duplicate callbacks ===")
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	local first = stageNext(clock, claims, env, "ana")
	clock.Advance(24.5)
	rt:ReportFailure("ana", first, optionsFor(first), "REJECTED")
	clock.T = 25.0
	for _ = 1, 10 do rt:Sweep("watchdog") end
	check(report, claims.ana.Failures == 1, "ten sweeps charge nothing", claims.ana.Failures)
	for _ = 1, 5 do rt:ReportFailure("ana", first, optionsFor(first), "DUP") end
	check(report, claims.ana.Failures == 1, "five duplicate callbacks charge nothing", claims.ana.Failures)
	check(report, #clock.Timers == 1, "and none schedules a second retry", #clock.Timers)
	check(report, #Routing.SweepTransfers(claims, 25.0, nil) == 0, "sweep reports nothing while the handoff is fresh")
	clock.Advance(1.0)
	local secondId = env.Dispatches[2] and env.Dispatches[2].AttemptId
	check(report, rt:ReportFailure("ana", first, optionsFor(first), "STALE") == nil,
		"a late report of the superseded attempt is a no-op")
	check(report, claims.ana.ChargedAttempt == nil and claims.ana.Failures == 1 and claims.ana.AttemptId == secondId,
		"and cannot touch the attempt that replaced it")
end

-- ============ T6: abandoned handoff re-driven, not re-charged, BOUNDED ============
note(report, "=== T6 abandoned handoff ===")
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	local first = stageNext(clock, claims, env, "ana")
	clock.Advance(10)
	rt:ReportFailure("ana", first, optionsFor(first), "REJECTED")
	local staleToken = Routing.HandoffToken(claims, "ana")
	table.clear(clock.Timers)          -- the scheduling thread died
	clock.Advance(Routing.RetryHandoffGraceSeconds + 0.1)
	local charged, redriven = rt:Sweep("watchdog")
	check(report, charged == 0 and redriven == 1, "the sweep re-drives the unacted handoff, charging nothing",
		tostring(charged) .. "/" .. tostring(redriven))
	check(report, claims.ana.Failures == 1, "and does not charge again", claims.ana.Failures)
	check(report, Routing.HandoffToken(claims, "ana") == staleToken,
		"the authorisation itself is unchanged -- only its window was re-armed")
	clock.Advance(Routing.RetryDelaySeconds + 0.1)
	check(report, #env.Dispatches == 2 and env.Dispatches[2].Kind == "next", "the retry finally dispatches",
		#env.Dispatches)
	check(report, Routing.HandoffToken(claims, "ana") == nil,
		"and the dispatch discharges the handoff")
end
-- the storm: a permanently dead scheduler must not spawn a closure per sweep
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	local first = stageNext(clock, claims, env, "ana")
	clock.Advance(10)
	rt:ReportFailure("ana", first, optionsFor(first), "REJECTED")
	local redrives = 0
	for _ = 1, 40 do
		table.clear(clock.Timers)      -- every scheduled retry dies
		clock.T += 5
		local _, r = rt:Sweep("watchdog")
		redrives += r
	end
	check(report, redrives <= Routing.MaxHandoffTakeovers + 1,
		"a permanently dead scheduler is re-driven a BOUNDED number of times", redrives)
	check(report, claims.ana.Failures == 1, "and is never charged twice for it", claims.ana.Failures)
end

-- ============ T6b: three guards that mutation testing found uncovered ============
note(report, "=== T6b superseded tokens and the re-drive window ===")
-- The re-arm. Without it the sweep re-drives the SAME lapsed handoff on every
-- pass, and the settlement loop sweeps repeatedly -- a closure storm.
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	local first = stageNext(clock, claims, env, "ana")
	clock.Advance(10)
	rt:ReportFailure("ana", first, optionsFor(first), "REJECTED")
	table.clear(clock.Timers)
	clock.Advance(Routing.RetryHandoffGraceSeconds + 0.1)
	local _, firstRedrive = rt:Sweep("watchdog")
	check(report, firstRedrive == 1, "a lapsed handoff is re-driven once", firstRedrive)
	local _, secondRedrive = rt:Sweep("watchdog")
	check(report, secondRedrive == 0,
		"and an immediate second sweep re-drives NOTHING -- the window was re-armed",
		secondRedrive)
	local _, thirdRedrive = rt:Sweep("watchdog")
	check(report, thirdRedrive == 0, "however many times the settlement loop sweeps", thirdRedrive)
end
-- The superseded-token re-check on the RETRY path.
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	local first = stageNext(clock, claims, env, "ana")
	clock.Advance(10)
	rt:ReportFailure("ana", first, optionsFor(first), "REJECTED")
	local staleToken = Routing.HandoffToken(claims, "ana")
	clock.Advance(Routing.RetryDelaySeconds + 0.1)      -- the authorised retry lands
	local before = #env.Dispatches
	rt:_ApplyHandoff("ana", "retry", staleToken, "REPLAY")
	clock.Advance(Routing.RetryDelaySeconds + 0.1)
	check(report, #env.Dispatches == before,
		"a superseded handoff token dispatches nothing",
		string.format("%d -> %d", before, #env.Dispatches))
end
-- The superseded-token re-check on the FALLBACK path: a thread that no longer
-- owns the claim must not brand it fallen-back, which would spend a fallback
-- the live attempt never used.
do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	local first = stageNext(clock, claims, env, "ana")
	clock.Advance(10)
	rt:ReportFailure("ana", first, optionsFor(first), "REJECTED")
	local staleToken = Routing.HandoffToken(claims, "ana")
	clock.Advance(Routing.RetryDelaySeconds + 0.1)      -- a new attempt supersedes it
	check(report, claims.ana.FellBack ~= true, "the live claim has not fallen back")
	rt:_ApplyHandoff("ana", "fallback", staleToken, "REPLAY")
	check(report, claims.ana.FellBack ~= true,
		"a superseded token cannot mark the live claim fallen back",
		tostring(claims.ana.FellBack))
	check(report, claims.ana.State == Routing.Pending,
		"nor resolve it", tostring(claims.ana.State))
	check(report, #env.LobbyCalls == 0,
		"nor open a lobby escape for a transfer that is still in flight", #env.LobbyCalls)
end

-- ============ T7a: every endpoint runs the full lineage and settles ============
note(report, "=== T7a all four endpoints, full lineage ===")
for _, ep in ipairs({
	{N = "continuation", E = Routing.Endpoints.Continuation, D = "next"},
	{N = "level3", E = Routing.Endpoints.Level3, D = "lobby"},
	{N = "loss", E = Routing.Endpoints.Loss, D = "lobby"},
	{N = "fallback", E = Routing.Endpoints.Fallback, D = "lobby"},
}) do
	local plan = Routing.EndpointPlan({Endpoint = ep.E, Reserved = true, Accepted = false})
	check(report, plan.Settle == true and plan.Endpoint == ep.E, ep.N .. ": must settle", plan.Endpoint)
	check(report, plan.Teardown == "keep-world", ep.N .. ": keeps the completed world", plan.Teardown)
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	Routing.ClaimTransfer(claims, "ana", ep.D)
	env.Dispatch("ana", {Kind = ep.D, AccessCode = "RESERVED-CODE", Data = {}})
	local settled, stranded = rt:AwaitSettlement(ep.E)
	clock.Advance(0)   -- flush the queued surrender, as task.spawn would
	check(report, settled == true and #stranded == 0,
		ep.N .. ": a totally silent transfer still terminates through the policy",
		tostring(settled) .. "/" .. tostring(#stranded) .. " at t=" .. string.format("%.1f", clock.T))
	check(report, #env.Surrenders == 1, ep.N .. ": ownership passes to local recovery exactly once", #env.Surrenders)
	check(report, #Routing.PendingTransfers(claims) == 0, ep.N .. ": and no claim is left pending",
		#Routing.PendingTransfers(claims))
end

-- ============ T7b: a WEDGED claim reaches the hard cap ============
note(report, "=== T7b wedged claim -> hard cap -> ForceSettle ===")
for _, ep in ipairs({
	{N = "continuation", E = Routing.Endpoints.Continuation},
	{N = "level3", E = Routing.Endpoints.Level3},
	{N = "loss", E = Routing.Endpoints.Loss},
	{N = "fallback", E = Routing.Endpoints.Fallback},
}) do
	local clock, claims = newClock(), {}
	local env = newEnv(clock, claims); local rt = Routing.NewTransferRuntime(env)
	Routing.ClaimTransfer(claims, "ana", "next")
	env.Dispatch("ana", {Kind = "next", AccessCode = "C", Data = {}})
	-- An unmodelled stuck state: charged, but holding no plan at all, so no
	-- sweep branch can ever advance it. Only the cap can end this.
	claims.ana.ChargedAttempt = claims.ana.AttemptId
	claims.ana.Handoff = nil
	local settled, stranded = rt:AwaitSettlement(ep.E)
	clock.Advance(0)   -- flush the queued surrender, as task.spawn would
	check(report, settled == false and #stranded == 1,
		ep.N .. ": a wedged claim reports an UNRESOLVED settlement",
		tostring(settled) .. "/" .. tostring(#stranded))
	check(report, clock.T >= Routing.SettlementHardCapSeconds and clock.T < Routing.SettlementHardCapSeconds + 2,
		ep.N .. ": at the hard cap, not before", string.format("t=%.2f", clock.T))
	check(report, #env.Surrenders == 1 and env.Surrenders[1].Reason == "SETTLEMENT_HARD_CAP",
		ep.N .. ": and every stranded player is handed to an owner",
		#env.Surrenders > 0 and env.Surrenders[1].Reason or "none")
	check(report, #Routing.PendingTransfers(claims) == 0, ep.N .. ": leaving no pending claim",
		#Routing.PendingTransfers(claims))
end

	check(report, Routing.EndpointPlan({Endpoint = "made-up"}).Endpoint == nil,
		"an endpoint name the module does not know is refused rather than assumed")
	check(report, Routing.EndpointPlan({Endpoint = "made-up"}).Settle == true,
		"but it still has to settle")

	return report
end

-- ---------------------------------------------------------------------------
-- Cohort -- the five release-blocker repairs, driven end to end
-- ---------------------------------------------------------------------------
--
-- Every other suite tests one half of the completion protocol at a time. This
-- one drives BOTH halves over ONE fake clock, because each defect it guards
-- lived in the seam between them:
--
--   A1  the source's silent-transfer schedule and the destination's staging
--       window were set independently, so a retry the source dispatched
--       correctly could not possibly arrive before the destination froze its
--       roster -- and the retried player walked into a running round.
--   A2  a claim taken and never dispatched had no anchor, so nothing could time
--       it out and the settlement recomputed its deadline on every poll.
--   A3  the pre-round wipe waited a fixed 1.6s instead of settling.
--   A4  ForceSettle was not idempotent, so one player could be handed to local
--       recovery twice and the second recovery cancelled the first.
--   A5  a synchronous dispatch refusal bypassed the failure policy entirely.
function Suite.Cohort()
	local report = newReport("Cohort timing, claim anchors and synchronous failures")

	-- =====================================================================
	-- A1 (i) THE TWO HALVES OF ONE PROTOCOL
	-- =====================================================================
	note(report, "=== A1 (i) the source's retry horizon and the destination's window ===")
	check(report, Routing.AdmissionCoversCohortHorizon(),
		"the destination's staging window contains the source's whole retry horizon",
		string.format("horizon %s, grace %s, cap %s, empty %s",
			tostring(Routing.CohortArrivalHorizonSeconds()),
			tostring(Routing.TransportGraceSeconds),
			tostring(Routing.AdmissionLocalCapSeconds),
			tostring(Routing.AdmissionEmptySeconds)))
	check(report, Routing.AdmissionLocalCapSeconds
		>= Routing.PostWinSeconds + Routing.CohortArrivalHorizonSeconds(),
		"and the local staging cap outlasts a whole result window plus that horizon",
		string.format("cap %s vs window %s + horizon %s",
			tostring(Routing.AdmissionLocalCapSeconds),
			tostring(Routing.PostWinSeconds),
			tostring(Routing.CohortArrivalHorizonSeconds())))
	check(report, Routing.CohortArrivalHorizonSeconds()
		== Routing.CohortAcceptGraceSeconds + Routing.CohortTransferTimeoutSeconds
			+ Routing.CohortWatchdogIntervalSeconds
			+ Routing.RetryDelaySeconds + Routing.TransportGraceSeconds,
		"the horizon is exactly accept grace + stale + sweep + retry delay + transport,"
			.. " and nothing more",
		tostring(Routing.CohortArrivalHorizonSeconds()))
	check(report, Routing.TimeoutForDestination(Routing.CohortDestination)
		== Routing.CohortTransferTimeoutSeconds
		and Routing.TimeoutForDestination("lobby") == Routing.TransferTimeoutSeconds
		and Routing.TimeoutForDestination(nil) == Routing.TransferTimeoutSeconds,
		"a cohort-bound claim earns the tight threshold and nothing else does",
		string.format("cohort %s, lobby %s",
			tostring(Routing.TimeoutForDestination(Routing.CohortDestination)),
			tostring(Routing.TimeoutForDestination("lobby"))))
	check(report, Routing.SweepIntervalSeconds()
		== math.min(Routing.WatchdogIntervalSeconds, Routing.CohortWatchdogIntervalSeconds)
		and Routing.SweepIntervalSeconds() <= Routing.CohortWatchdogIntervalSeconds,
		"and the watchdog ticks at least as often as the SHORTEST threshold in play",
		tostring(Routing.SweepIntervalSeconds()))
	note(report, "MUTATION PROOF: Routing.TimeoutForDestination handing a cohort claim"
		.. " the 25s lobby threshold, or Routing.SweepIntervalSeconds returning"
		.. " WatchdogIntervalSeconds, fails the two checks above and every timing"
		.. " assertion in A1 (ii).")

	-- The packet has to CARRY the horizon, or the destination is guessing.
	do
		local withDeadline = Routing.ArrivalPacket({
			Level = 2, SessionId = "H", Expected = 3, Deadline = 100, Final = true,
		})
		check(report, withDeadline.CohortHorizon
			== 100 + Routing.CohortArrivalHorizonSeconds(),
			"every packet declares the last moment its cohort can still land",
			tostring(withDeadline.CohortHorizon))
		local noDeadline = Routing.ArrivalPacket({
			Level = 2, SessionId = "H", Expected = 3, Final = true,
		})
		check(report, noDeadline.CohortHorizon == nil,
			"a packet with no deadline declares no horizon rather than a bogus one",
			tostring(noDeadline.CohortHorizon))
		local spread = newDestination()
		local near = Routing.ArrivalPacket({Level = 2, SessionId = "H", Expected = 3,
			Deadline = 100, Final = true})
		local far = Routing.ArrivalPacket({Level = 2, SessionId = "H", Expected = 3,
			Deadline = 140, Final = true})
		spread:arrive({Member = "ana", Data = near}, 0)
		spread:arrive({Member = "bo", Data = far}, 0)
		local group = Routing.SelectArrivalSession(spread.Arrivals)
		check(report, group ~= nil and group.CohortHorizon == far.CohortHorizon,
			"and the session carries the FURTHEST horizon any of its members declared",
			group and tostring(group.CohortHorizon) or "nil")
	end

	-- The declared horizon is honoured when it is TIGHTER than the
	-- destination's own and clamped when it is not, so a stale or forged packet
	-- cannot buy an unbounded wait.
	do
		local base = {
			Now = 24, StartedAt = 0, FirstArrivalAt = 20, ServerNow = 24,
			Deadline = 15, Arrived = 2, Expected = 3, Final = true,
		}
		check(report, Routing.ArrivalDecision(base) == "wait",
			"a short FINAL cohort past the grace waits on the source's retry",
			tostring(Routing.ArrivalDecision(base)))
		base.CohortHorizon = 23
		check(report, Routing.ArrivalDecision(base) == "admit",
			"a TIGHTER declared horizon is honoured and admits sooner",
			tostring(Routing.ArrivalDecision(base)))
		base.CohortHorizon = 1e9
		base.Now = 15 + Routing.CohortArrivalHorizonSeconds()
		base.ServerNow = base.Now
		base.FirstArrivalAt = base.Now - 1
		check(report, Routing.ArrivalDecision(base) == "admit",
			"a forged horizon far in the future is clamped to the destination's own",
			tostring(Routing.ArrivalDecision(base)))
	end

	-- The per-claim threshold, and the explicit override the other suites use.
	do
		local mixed = {}
		Routing.ClaimTransfer(mixed, "ana", "next", 0)
		Routing.BeginAttempt(mixed, "ana", "next", 8001, nil, 1, 0, {Kind = "next"})
		Routing.ClaimTransfer(mixed, "bo", "lobby", 0)
		Routing.BeginAttempt(mixed, "bo", "lobby", 8002, nil, 1, 0, {Kind = "lobby"})
		check(report, #Routing.SweepTransfers(mixed,
			Routing.CohortTransferTimeoutSeconds - 0.1, nil) == 0,
			"nothing is stale a moment before the cohort threshold")
		local tight = Routing.SweepTransfers(mixed, Routing.CohortTransferTimeoutSeconds, nil)
		check(report, #tight == 1 and tight[1].Member == "ana" and tight[1].Kind == "attempt",
			"the cohort-bound attempt alone goes stale at the cohort threshold",
			#tight > 0 and tostring(tight[1].Member) or "none")
		check(report, #Routing.SweepTransfers(mixed, Routing.TransferTimeoutSeconds, nil) == 2,
			"while the lobby-bound one waits for the lobby threshold")
		check(report, #Routing.SweepTransfers(mixed, 1, 0) == 2,
			"and an EXPLICIT timeout argument still overrides both, for every claim")
	end

	-- The clock the cohort threshold is measured ON.
	--
	-- Routing.BeginAttempt has to stamp BEFORE the dispatch, because a
	-- TeleportAsync that never returns at all still has to time out. But
	-- TeleportAsync yields, and the cohort budget is six seconds: measuring from
	-- before the call charges the yield to the attempt, so a dispatch that was
	-- merely slow gets re-dispatched underneath a transfer that had just
	-- succeeded. Routing.RestampAttempt re-anchors to the moment Roblox ACCEPTED
	-- the request, and refuses to move any attempt that is not both current and
	-- uncharged.
	note(report, "=== the attempt clock is re-anchored on acceptance ===")
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "next", 0)
		Routing.BeginAttempt(claims, "ana", "next", 9101, nil, 1, 0, {Kind = "next"})
		-- Inside the accept grace, so the clamp is not what is under test here.
		local slow = Routing.CohortAcceptGraceSeconds - 1
		check(report, #Routing.SweepTransfers(claims,
			slow + Routing.CohortTransferTimeoutSeconds, nil) == 1,
			"a dispatch stamped before a slow accept looks stale on the pre-call clock")
		check(report, Routing.RestampAttempt(claims, "ana", 9101, slow, 0) == true,
			"the accepted attempt is re-anchored")
		check(report, claims.ana.StartedAt == slow
			and #Routing.SweepTransfers(claims,
				slow + Routing.CohortTransferTimeoutSeconds - 0.1, nil) == 0,
			"and is no longer stale until the threshold passes from ACCEPTANCE",
			tostring(claims.ana.StartedAt))
		check(report, Routing.RestampAttempt(claims, "ana", 9102, slow + 5, 0) == false
			and claims.ana.StartedAt == slow,
			"a stale attempt id may not move the clock")
		check(report, Routing.RestampAttempt(claims, "ana", 9101, "soon", 0) == false
			and claims.ana.StartedAt == slow,
			"and neither may a non-number stamp")
		-- Once a failure is charged the claim is owned by its HANDOFF stamp, and
		-- moving the attempt clock under it would hide a lapsed handoff from the
		-- sweep that has to re-drive it.
		Routing.AttemptFailure(claims, "ana", Routing.FailureSources.Timeout, nil, nil, 40)
		check(report, Routing.RestampAttempt(claims, "ana", 9101, 41, 0) == false
			and claims.ana.StartedAt == slow,
			"a CHARGED attempt is owned by its handoff and may not be re-anchored")
		local resolved = {}
		Routing.ClaimTransfer(resolved, "bo", "lobby", 0)
		Routing.BeginAttempt(resolved, "bo", "lobby", 9103, nil, 1, 0, {Kind = "lobby"})
		Routing.ResolveTransfer(resolved, "bo", Routing.Succeeded)
		check(report, Routing.RestampAttempt(resolved, "bo", 9103, 12, 0) == false,
			"and a claim that is no longer pending may not be re-anchored at all")
		note(report, "MUTATION PROOF: deleting the RestampAttempt loop from"
			.. " dispatchTransfer, or dropping its ChargedAttempt guard, fails the"
			.. " checks above.")
	end

	-- =====================================================================
	-- A1 (ii) SOURCE AND DESTINATION, ONE CLOCK, ONE COHORT OF THREE
	-- =====================================================================
	note(report, "=== A1 (ii) one window, a silent continuer, one round ===")
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims)
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		-- The window opens at t=0 on the SAME clock the runtime reads, so the
		-- source's decision deadline and the destination's server clock are one
		-- timeline instead of two numbers nobody ever compared.
		local source = newSource({Party = {"ana", "bo", "cy"}, Level = 1, Now = 0})
		local destination = newDestination()
		local deadline = source.Deadline
		check(report, deadline == Routing.PostWinSeconds,
			"the result window closes at PostWinSeconds", tostring(deadline))

		-- t = 1. ana presses Continue at once. Roblox accepts the request and
		-- then does nothing at all: no arrival, and no TeleportInitFailed.
		clock.Advance(1)
		local anaDispatchedAt = clock.Now()
		local anaPacket = source:continueNow("ana")
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		env.Dispatch("ana", {Kind = "next", AccessCode = "RESERVED-CODE", Data = anaPacket})
		check(report, claims.ana.Destination == "next"
			and Routing.SettlementAnchorOf(claims.ana) == anaDispatchedAt,
			"her claim is cohort-bound and anchored at the moment it was taken",
			tostring(claims.ana.Destination) .. "/"
				.. tostring(Routing.SettlementAnchorOf(claims.ana)))

		local chargedAt, retryAt
		while clock.T < deadline and retryAt == nil do
			clock.Advance(Routing.SweepIntervalSeconds())
			rt:Sweep("watchdog")
			if chargedAt == nil and claims.ana.Failures == 1 then chargedAt = clock.T end
			if retryAt == nil and #env.Dispatches == 2 then retryAt = clock.T end
		end
		check(report, chargedAt ~= nil and chargedAt <= anaDispatchedAt
			+ Routing.CohortTransferTimeoutSeconds + Routing.CohortWatchdogIntervalSeconds,
			"her silent cohort attempt is charged within stale + one sweep of dispatch",
			string.format("charged at %s, dispatched at %s",
				tostring(chargedAt), tostring(anaDispatchedAt)))
		check(report, chargedAt ~= nil
			and chargedAt < anaDispatchedAt + Routing.TransferTimeoutSeconds,
			"on the COHORT schedule, not the lobby one it used to share",
			string.format("charged at %s, the lobby threshold alone would be %s",
				tostring(chargedAt),
				tostring(anaDispatchedAt + Routing.TransferTimeoutSeconds)))
		check(report, retryAt ~= nil and chargedAt ~= nil
			and math.abs(retryAt - (chargedAt + Routing.RetryDelaySeconds)) < 1e-6,
			"and the retry dispatches exactly one retry delay later",
			string.format("retry at %s, charge at %s", tostring(retryAt), tostring(chargedAt)))
		check(report, #env.Dispatches == 2 and env.Dispatches[2].Kind == "next"
			and env.Dispatches[2].AccessCode == "RESERVED-CODE",
			"to the SAME reserved server, never to the lobby",
			#env.Dispatches > 1 and tostring(env.Dispatches[2].Kind) or "none")
		check(report, claims.ana.Failures == 1 and #env.LobbyCalls == 0
			and #env.Surrenders == 0,
			"charging exactly one failure and stranding nobody",
			tostring(claims.ana.Failures))
		check(report, retryAt ~= nil and retryAt < deadline + Routing.TransportGraceSeconds,
			"the retry is in flight BEFORE the destination's transport grace expires",
			string.format("retry at %s, grace ends at %s",
				tostring(retryAt), tostring(deadline + Routing.TransportGraceSeconds)))

		-- Roblox accepts the retried request and she leaves this server. The
		-- transport itself is slow, which is exactly what the horizon budgets
		-- for beyond the transport grace.
		Routing.ResolveTransfer(claims, "ana", Routing.Succeeded)
		while clock.T < deadline do
			clock.Advance(Routing.SweepIntervalSeconds())
			rt:Sweep("watchdog")
		end

		-- t = 15. The settlement carries bo and cy in one FINAL packet naming
		-- the exact cohort of three, and both of them land at once.
		local final, continuing = source:settle()
		check(report, names(continuing) == "bo,cy" and final.FinalCohort == true
			and final.ExpectedContinuers == 3,
			"the settlement packet is final and names all THREE",
			string.format("%s / final=%s expected=%s", names(continuing),
				tostring(final.FinalCohort), tostring(final.ExpectedContinuers)))
		check(report, final.CohortHorizon == deadline + Routing.CohortArrivalHorizonSeconds(),
			"and declares the horizon the destination must respect",
			tostring(final.CohortHorizon))
		for _, member in ipairs(continuing) do
			Routing.ClaimTransfer(claims, member, "next", clock.Now())
			env.Dispatch(member, {Kind = "next", AccessCode = "RESERVED-CODE", Data = final})
			Routing.ResolveTransfer(claims, member, Routing.Succeeded)
			destination:arrive({Member = member, Data = final}, clock.T)
		end

		-- THE ROSTER MUST NOT FREEZE EARLY. Every poll from the settlement to
		-- the end of the transport grace has to keep staging.
		local startedEarlyAt = nil
		while clock.T < deadline + Routing.TransportGraceSeconds do
			if destination:decide(clock.T, clock.T) ~= "wait" then
				startedEarlyAt = startedEarlyAt or clock.T
			end
			clock.Advance(Routing.SweepIntervalSeconds())
			rt:Sweep("watchdog")
		end
		check(report, startedEarlyAt == nil,
			"the destination stages, and never starts, while the cohort is short",
			tostring(startedEarlyAt))

		-- deadline + grace. This is where the old destination admitted, froze
		-- its roster at two, and turned ana into a spectator in her own round.
		local decision, group, reason = destination:decide(clock.T, clock.T)
		check(report, decision == "wait",
			"AT deadline + transport grace it STILL waits: the final cohort is short",
			tostring(decision) .. " at t=" .. string.format("%.2f", clock.T))
		check(report,
			reason == "the cohort is short and the source's retry horizon has not passed",
			"for the token-aware reason, not by accident", tostring(reason))
		check(report, group ~= nil and group.Final == true and group.Expected == 3
			and #group.Members == 2,
			"holding an AUTHORITATIVE three against two arrivals",
			group and string.format("final=%s expected=%s arrived=%d", tostring(group.Final),
				tostring(group.Expected), #group.Members) or "nil")
		note(report, "MUTATION PROOF: deleting the (state.Final == true and expected and"
			.. " arrived < expected) branch from Routing.ArrivalDecision makes the three"
			.. " checks above admit a two-player round.")

		clock.Advance(0.9)
		check(report, destination:decide(clock.T, clock.T) == "wait",
			"and is still waiting a moment before she lands",
			string.format("t=%.2f", clock.T))

		-- The retried transfer finally delivers her, inside the horizon.
		clock.Advance(0.1)
		local anaArrivedAt = clock.T
		destination:arrive({Member = "ana", Data = anaPacket}, anaArrivedAt)
		check(report, anaArrivedAt < deadline + Routing.CohortArrivalHorizonSeconds(),
			"the retried arrival reaches the destination INSIDE the declared horizon",
			string.format("arrived %.2f, horizon %.2f", anaArrivedAt,
				deadline + Routing.CohortArrivalHorizonSeconds()))
		decision, group, reason = destination:decide(clock.T, clock.T)
		check(report, decision == "admit" and reason == "the full cohort arrived",
			"and only THEN does the round start",
			tostring(decision) .. "/" .. tostring(reason))
		check(report, group ~= nil and names(group.Members) == "ana,bo,cy",
			"with exactly ana, bo and cy in it",
			group and names(group.Members) or "nil")
		check(report, group ~= nil and group.SessionId == source.SessionId
			and anaPacket.RoundSessionId == final.RoundSessionId,
			"in ONE session: the early presser and the countdown carry the same id",
			group and tostring(group.SessionId) or "nil")
		check(report, group ~= nil and group.Level == 2 and group.Expected == 3,
			"one Level 2 round, sized at the authoritative three",
			group and tostring(group.Level) or "nil")

		-- And the SOURCE is finished: nobody is left holding a claim.
		local settled, stranded = rt:AwaitSettlement(Routing.Endpoints.Continuation)
		check(report, settled == true and #stranded == 0
			and #Routing.PendingTransfers(claims) == 0,
			"the source endpoint settles with nobody left behind",
			tostring(settled) .. "/" .. tostring(#stranded))

		-- THE BOUND. The same cohort, but ana's transfer never lands at all.
		-- The destination may not wait for her forever.
		local abandoned = newDestination()
		abandoned:arrive({Member = "bo", Data = final}, deadline)
		abandoned:arrive({Member = "cy", Data = final}, deadline)
		local horizon = deadline + Routing.CohortArrivalHorizonSeconds()
		check(report, abandoned:decide(deadline + Routing.TransportGraceSeconds,
			deadline + Routing.TransportGraceSeconds) == "wait",
			"with nobody else coming it still waits at deadline + grace")
		check(report, abandoned:decide(horizon - 0.01, horizon - 0.01) == "wait",
			"and a hundredth of a second before the horizon")
		local lastDecision, lastGroup, lastReason = abandoned:decide(horizon, horizon)
		check(report, lastDecision == "admit"
			and lastReason == "the source's retry horizon passed with the cohort still short",
			"but admits AT the horizon, on the horizon's own reason",
			tostring(lastDecision) .. "/" .. tostring(lastReason))
		check(report, lastGroup ~= nil and #lastGroup.Members == 2,
			"running the round with the two who actually arrived",
			lastGroup and tostring(#lastGroup.Members) or "nil")
		check(report, abandoned:decide(horizon + 10000, horizon + 10000) == "admit",
			"and never, at any later poll, goes back to waiting")
	end

	-- A1 (iii) The SETTLEMENT LOOP's own sweep runs on the cohort cadence too.
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims)
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		local expiredAt = nil
		local baseWarn = env.Warn
		env.Warn = function(text)
			if expiredAt == nil and type(text) == "string"
				and text:find("was never reported on", 1, true) then
				expiredAt = clock.T
			end
			baseWarn(text)
		end
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		env.Dispatch("ana", {Kind = "next", AccessCode = "RESERVED-CODE", Data = {}})
		clock.Delay(Routing.CohortTransferTimeoutSeconds + Routing.RetryDelaySeconds + 1,
			function() Routing.ResolveTransfer(claims, "ana", Routing.Succeeded) end)
		local settled = rt:AwaitSettlement(Routing.Endpoints.Continuation)
		check(report, settled == true, "the settlement resolves", tostring(settled))
		check(report, expiredAt ~= nil and expiredAt <= Routing.CohortTransferTimeoutSeconds
			+ Routing.SweepIntervalSeconds(),
			"AwaitSettlement charges a silent cohort attempt within ONE sweep of it"
			.. " going stale -- on the cohort cadence, not the lobby one",
			string.format("expired at %s, bound %s, a lobby-cadence loop could not"
				.. " charge before %s", tostring(expiredAt),
				tostring(Routing.CohortTransferTimeoutSeconds + Routing.SweepIntervalSeconds()),
				tostring(math.ceil(Routing.CohortTransferTimeoutSeconds
					/ Routing.WatchdogIntervalSeconds) * Routing.WatchdogIntervalSeconds)))
		note(report, "MUTATION PROOF: Runtime:AwaitSettlement re-arming on"
			.. " Routing.WatchdogIntervalSeconds instead of SweepIntervalSeconds()"
			.. " pushes that expiry out to 5s and fails the check above.")
	end

	-- =====================================================================
	-- A2 A CLAIM THAT WAS TAKEN AND NEVER DISPATCHED
	-- =====================================================================
	note(report, "=== A2 the claim-time anchor and the unstarted claim ===")
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "next", 100)
		check(report, claims.ana.ClaimedAt == 100 and claims.ana.LineageStartedAt == 100,
			"a claim records WHEN it was taken, and starts its lineage there",
			tostring(claims.ana.ClaimedAt) .. "/" .. tostring(claims.ana.LineageStartedAt))
		check(report, Routing.SettlementAnchorOf(claims.ana) == 100,
			"which is the settlement anchor even with no attempt on it at all",
			tostring(Routing.SettlementAnchorOf(claims.ana)))
		check(report, Routing.ClaimSettlementDeadline(claims.ana)
			== 100 + Routing.SettlementLineageSeconds,
			"so its settlement deadline is a fixed number rather than one that moves",
			tostring(Routing.ClaimSettlementDeadline(claims.ana)))
		check(report, #Routing.SweepTransfers(claims,
			100 + Routing.UnstartedClaimTimeoutSeconds - 0.1, nil) == 0,
			"an undispatched claim is left alone before its own timeout")
		local actions = Routing.SweepTransfers(claims,
			100 + Routing.UnstartedClaimTimeoutSeconds, nil)
		check(report, #actions == 1 and actions[1].Member == "ana"
			and actions[1].Kind == "unstarted",
			"and is reported UNSTARTED once that timeout passes -- it has no attempt"
			.. " to charge and no report will ever come",
			#actions > 0 and tostring(actions[1].Kind) or "none")
		check(report, claims.ana.State == Routing.Pending and claims.ana.Failures == 0,
			"the sweep itself still mutates nothing",
			tostring(claims.ana.State) .. "/" .. tostring(claims.ana.Failures))
		note(report, "MUTATION PROOF: dropping the `at` argument from"
			.. " Routing.ClaimTransfer leaves ClaimedAt nil, makes SweepTransfers'"
			.. " unstarted branch unreachable, and kills the four checks above.")
	end

	-- A pending claim with NO anchor at all is unaccountable, not young.
	do
		local bare = {ana = {State = Routing.Pending}}
		local verdict, detail = Routing.SettlementStatus(bare, 0)
		check(report, verdict == "expired" and detail.Expired[1] == "ana",
			"a pending claim nobody can date is EXPIRED at once, not waiting",
			tostring(verdict))
		check(report, Routing.SettlementStatus(bare, 1e9) == "expired",
			"and stays expired however long the endpoint polls -- the old code"
			.. " recomputed now + the hard cap every pass and could never reach it")
	end

	-- The runtime ends it, exactly once, and hands its player to an owner.
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims)
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		-- The production exception: the claim is taken and the dispatching
		-- thread dies before it ever reaches Routing.BeginAttempt.
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		clock.Advance(Routing.UnstartedClaimTimeoutSeconds - 0.1)
		local charged, redriven = rt:Sweep("watchdog")
		clock.Advance(0)
		check(report, charged == 0 and redriven == 0 and #env.Surrenders == 0
			and claims.ana.State == Routing.Pending,
			"the runtime leaves a young undispatched claim alone",
			tostring(charged) .. "/" .. tostring(redriven))
		clock.Advance(0.2)
		charged, redriven = rt:Sweep("watchdog")
		clock.Advance(0)
		check(report, charged == 0 and redriven == 1,
			"then surrenders it -- counted as a re-drive, never as a charge",
			tostring(charged) .. "/" .. tostring(redriven))
		check(report, claims.ana.State == Routing.Failed
			and #Routing.PendingTransfers(claims) == 0,
			"the claim ends FAILED and holds the settlement no longer",
			tostring(claims.ana.State))
		check(report, #env.Surrenders == 1 and env.Surrenders[1].Member == "ana",
			"its player is handed to local recovery exactly once",
			tostring(#env.Surrenders))
		local warned = false
		for _, text in ipairs(env.Warnings) do
			if type(text) == "string"
				and text:find("was never dispatched; surrendering it", 1, true) then
				warned = true
			end
		end
		check(report, warned, "and the warning says what actually happened",
			env.Warnings[1] or "none")
		local again, againRedriven = rt:Sweep("watchdog")
		clock.Advance(0)
		check(report, again == 0 and againRedriven == 0 and #env.Surrenders == 1,
			"a second sweep changes nothing -- ownership transfers once",
			tostring(#env.Surrenders))
	end

	-- AwaitSettlement over such a claim TERMINATES, and terminates bounded.
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims)
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		local settled, stranded = rt:AwaitSettlement(Routing.Endpoints.Continuation)
		clock.Advance(0)
		check(report, settled == true and #stranded == 0,
			"an endpoint holding an undispatched claim RETURNS",
			tostring(settled) .. "/" .. tostring(#stranded))
		check(report, clock.T <= Routing.UnstartedClaimTimeoutSeconds
			+ Routing.SweepIntervalSeconds() + Routing.SettlementPollSeconds,
			"at that claim's own timeout -- not at the hard cap, and not never",
			string.format("t=%.2f, the hard cap would be %s", clock.T,
				tostring(Routing.SettlementHardCapSeconds)))
		check(report, #env.Surrenders == 1,
			"having handed its one player to local recovery", tostring(#env.Surrenders))
	end

	-- =====================================================================
	-- A3 THE LOSS ENDPOINT REALLY SETTLES
	-- =====================================================================
	note(report, "=== A3 the loss endpoint, behaviourally ===")
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims)
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		env.Dispatch("ana", {Kind = "next", AccessCode = "RESERVED-CODE", Data = {}})
		-- Wedged: charged, but holding no plan, so no sweep branch can advance
		-- it. Only the hard cap can end this one.
		claims.ana.ChargedAttempt = claims.ana.AttemptId
		claims.ana.Handoff = nil
		local settled, stranded = rt:AwaitSettlement(Routing.Endpoints.Loss)
		clock.Advance(0)
		check(report, settled == false and #stranded == 1 and stranded[1] == "ana",
			"the LOSS endpoint runs the same settlement as every other one and"
			.. " names its stranded player",
			tostring(settled) .. "/" .. tostring(#stranded))
		check(report, clock.T >= Routing.SettlementHardCapSeconds,
			"waiting the full hard cap rather than a fixed 1.6 seconds",
			string.format("t=%.2f", clock.T))
		check(report, #env.Surrenders == 1
			and env.Surrenders[1].Reason == "SETTLEMENT_HARD_CAP"
			and #Routing.PendingTransfers(claims) == 0,
			"and transferring ownership before it lets go of the completed world",
			#env.Surrenders > 0 and tostring(env.Surrenders[1].Reason) or "none")
		note(report, "MUTATION PROOF: sendWipedPartyHome's task.wait(1.6) returned"
			.. " here with the claim above still pending. The source-shape half of"
			.. " this is in Suite.Host.")
	end

	-- =====================================================================
	-- A4 FORCE SETTLE IS IDEMPOTENT
	-- =====================================================================
	note(report, "=== A4 idempotent force settle ===")
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims)
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		local ok, _, attemptId = env.Dispatch("ana",
			{Kind = "next", AccessCode = "RESERVED-CODE", Data = {}})
		-- Charge it first, so the claim is holding a LIVE retry authority when
		-- the force lands. Forcing a claim that never had a token could not
		-- prove the token is cleared, and the check below would be vacuous.
		rt:ReportFailure("ana", attemptId, optionsFor(attemptId), "REJECTED")
		check(report, ok == true and attemptId ~= nil
			and Routing.HandoffToken(claims, "ana") ~= nil
			and Routing.HandoffPlan(claims, "ana") == "retry",
			"a live cohort claim is in flight, holding a retry authority",
			tostring(attemptId))

		local first = rt:ForceSettle({"ana"}, Routing.Endpoints.Loss)
		clock.Advance(0)
		check(report, #first == 1 and first[1] == "ana",
			"the first force reports exactly one stranded player", tostring(#first))
		check(report, #env.Surrenders == 1 and #env.Warnings == 1,
			"with one surrender and one warning",
			tostring(#env.Surrenders) .. "/" .. tostring(#env.Warnings))
		check(report, claims.ana.State == Routing.Failed
			and Routing.WasForceSettled(claims, "ana"),
			"and the claim is terminally marked", tostring(claims.ana.State))
		check(report, claims.ana.HandoffToken == nil and claims.ana.Handoff == nil
			and claims.ana.HandoffAt == nil,
			"holding no token, so no stale authority can resolve it afterwards",
			tostring(claims.ana.HandoffToken))

		local second = rt:ForceSettle({"ana"}, Routing.Endpoints.Loss)
		clock.Advance(0)
		check(report, #second == 0, "a second force reports NOTHING", tostring(#second))
		check(report, #env.Surrenders == 1 and #env.Warnings == 1,
			"and adds no second surrender and no second warning -- the second"
			.. " recovery used to cancel the first one's retry token",
			tostring(#env.Surrenders) .. "/" .. tostring(#env.Warnings))
		local concurrent = rt:ForceSettle({"ana", "ana"}, Routing.Endpoints.Loss)
		clock.Advance(0)
		check(report, #concurrent == 0 and #env.Surrenders == 1,
			"nor does a concurrent force naming the same player twice",
			tostring(#concurrent) .. "/" .. tostring(#env.Surrenders))

		local failures = claims.ana.Failures
		check(report, rt:ReportFailure("ana", attemptId, optionsFor(attemptId), "late") == nil,
			"a callback landing after the force is a no-op")
		clock.Advance(0)
		check(report, #env.Surrenders == 1 and claims.ana.Failures == failures
			and claims.ana.State == Routing.Failed,
			"charging nothing, surrendering nobody, changing no state",
			tostring(#env.Surrenders) .. "/" .. tostring(claims.ana.Failures))
		note(report, "MUTATION PROOF: Runtime:ForceSettle warning, spawning and"
			.. " appending unconditionally -- ignoring ForceSettleClaim's answer --"
			.. " doubles every count above.")
	end

	-- A claim caught MID-HANDOVER is ended here too, or it stays owned forever
	-- and the settlement can never resolve again.
	do
		local claims = {}
		Routing.ClaimTransfer(claims, "ana", "next", 0)
		Routing.ResolveTransfer(claims, "ana", Routing.Failed)
		Routing.BeginHandover(claims, "ana")
		check(report, Routing.InHandover(claims, "ana")
			and #Routing.PendingTransfers(claims) == 1
			and not Routing.TransfersResolved(claims),
			"a player mid-handover is still owned, though their claim has resolved")
		check(report, Routing.ForceSettleClaim(claims, "ana") == true,
			"the force reaches them")
		check(report, Routing.InHandover(claims, "ana") == false,
			"the handover marker is cleared", tostring(Routing.InHandover(claims, "ana")))
		check(report, #Routing.PendingTransfers(claims) == 0
			and Routing.TransfersResolved(claims),
			"so the settlement can resolve at all",
			tostring(#Routing.PendingTransfers(claims)))
		check(report, Routing.ForceSettleClaim(claims, "ana") == false,
			"and it still only ever happens once")
	end

	-- =====================================================================
	-- A5 SYNCHRONOUS FAILURES GO THROUGH THE RUNTIME
	-- =====================================================================
	note(report, "=== A5 a refused dispatch earns the same policy as a callback ===")
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims, {Dispatch = {[1] = false, [2] = false}})
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		local nextRecord = claims.ana
		local ok, err, attemptId = env.Dispatch("ana",
			{Kind = "next", AccessCode = "RESERVED-CODE", Data = {}})
		check(report, ok == false and attemptId ~= nil,
			"Roblox refuses the request synchronously, and it is still an ATTEMPT",
			tostring(ok) .. "/" .. tostring(attemptId))
		local plan = rt:ReportDispatchFailure("ana", attemptId, err)
		check(report, plan == "retry",
			"which the runtime charges into the SAME policy a callback earns",
			tostring(plan))
		check(report, nextRecord.Failures == 1 and nextRecord.State == Routing.Pending,
			"one failure, and the claim is NOT resolved by hand",
			tostring(nextRecord.Failures) .. "/" .. tostring(nextRecord.State))
		check(report, rt:ReportDispatchFailure("ana", attemptId, "DUPLICATE") == nil
			and nextRecord.Failures == 1,
			"a second report of the same refusal charges nothing",
			tostring(nextRecord.Failures))
		check(report, #env.Dispatches == 1,
			"and nothing re-dispatches before the retry delay", tostring(#env.Dispatches))
		clock.Advance(Routing.RetryDelaySeconds + 0.01)
		check(report, #env.Dispatches >= 2 and env.Dispatches[2].Kind == "next"
			and math.abs(env.Dispatches[2].At - Routing.RetryDelaySeconds) < 1e-6,
			"the retry dispatches to the next level exactly one retry delay later",
			#env.Dispatches >= 2
				and string.format("%s at %s", tostring(env.Dispatches[2].Kind),
					tostring(env.Dispatches[2].At))
				or tostring(#env.Dispatches))
		check(report, nextRecord.Failures == 2 and nextRecord.FellBack == true,
			"and a SECOND refusal escalates to the fallback, on exactly two charges",
			tostring(nextRecord.Failures) .. "/" .. tostring(nextRecord.FellBack))
		check(report, #env.LobbyCalls == 1 and claims.ana ~= nextRecord
			and claims.ana.Destination == "lobby" and claims.ana.Failures == 0,
			"opening a FRESH lobby claim with a clean budget",
			tostring(#env.LobbyCalls))
		check(report, Routing.LineageStartOf(claims, "ana") == 0,
			"that inherits the lineage clock",
			tostring(Routing.LineageStartOf(claims, "ana")))
		note(report, "MUTATION PROOF: resolving the claim Failed at the call site --"
			.. " what the old failPendingTeleport did for a refused REAL dispatch --"
			.. " fails every check in this block: no retry, no fallback, no lobby.")
	end

	-- The lobby fallback's OWN synchronous rejection, and the ClaimOwns guard.
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims,
			{Dispatch = {[1] = false, [2] = false, [4] = false}, Lobby = {[1] = false}})
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		local _, err, attemptId = env.Dispatch("ana",
			{Kind = "next", AccessCode = "RESERVED-CODE", Data = {}})
		rt:ReportDispatchFailure("ana", attemptId, err)
		clock.Advance(Routing.RetryDelaySeconds + 0.01)
		check(report, #env.LobbyCalls == 1 and claims.ana.Destination == "lobby",
			"the exhausted next-level lineage falls back to a lobby claim",
			tostring(#env.LobbyCalls))
		check(report, claims.ana.State == Routing.Pending and claims.ana.Failures == 1,
			"whose own synchronous refusal is charged once and earns ITS retry",
			tostring(claims.ana.State) .. "/" .. tostring(claims.ana.Failures))
		check(report, #env.Surrenders == 0,
			"and the player is NOT surrendered while that live claim still owns them",
			tostring(#env.Surrenders))
		note(report, "MUTATION PROOF: dropping `not Routing.ClaimOwns(env.Claims[member])`"
			.. " from Runtime:_ApplyHandoff's fallback thread surrenders them here, a"
			.. " whole attempt early.")
		clock.Advance(Routing.RetryDelaySeconds + 0.01)
		check(report, claims.ana.Failures == 2 and claims.ana.State == Routing.Failed,
			"the lobby retry's refusal is the second and last charge -- the lobby"
			.. " IS the fallback",
			tostring(claims.ana.Failures) .. "/" .. tostring(claims.ana.State))
		check(report, #env.Surrenders == 1 and #Routing.PendingTransfers(claims) == 0,
			"and only THEN is the player surrendered, exactly once",
			tostring(#env.Surrenders))
	end

	-- A transport that RAISES before it dispatches anything at all.
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims,
			{DispatchThrows = {[1] = "TELEPORT_REQUEST_UNBUILDABLE: boom"}})
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		local raised, thrown = pcall(env.Dispatch, "ana", {Kind = "next", Data = {}})
		check(report, raised == false
			and tostring(thrown):find("UNBUILDABLE", 1, true) ~= nil,
			"building the request throws before anything is dispatched",
			tostring(thrown))
		check(report, claims.ana.AttemptId == nil and claims.ana.State == Routing.Pending,
			"leaving a claim with no attempt on it -- the exact shape that used to"
			.. " be invisible to every sweep",
			tostring(claims.ana.AttemptId))
		-- THE CALLER CONTRACT: production stamps an attempt anyway and reports it
		-- through the runtime, so the ordinary policy owns the player.
		local stamped = Routing.NewAttemptId()
		Routing.BeginAttempt(claims, "ana", "next", stamped, nil, 1, clock.Now(),
			{Kind = "next", Data = {}})
		local plan = rt:ReportDispatchFailure("ana", stamped, tostring(thrown))
		check(report, plan == "retry" and claims.ana.Failures == 1,
			"a stamped, reported unbuildable request earns a retry like any refusal",
			tostring(plan) .. "/" .. tostring(claims.ana.Failures))
	end

	-- ...and if the exception escapes the caller entirely, the claim STILL ends.
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims, {DispatchThrows = {[1] = "boom"}})
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		local raised = pcall(env.Dispatch, "ana", {Kind = "next", Data = {}})
		check(report, raised == false and claims.ana.AttemptId == nil,
			"the dispatching thread dies with the claim already taken")
		local settled, stranded = rt:AwaitSettlement(Routing.Endpoints.Continuation)
		clock.Advance(0)
		check(report, settled == true and #stranded == 0,
			"the endpoint still settles finitely",
			tostring(settled) .. "/" .. tostring(#stranded))
		check(report, clock.T <= Routing.UnstartedClaimTimeoutSeconds
			+ Routing.SweepIntervalSeconds() + Routing.SettlementPollSeconds,
			"bounded by the undispatched-claim timeout",
			string.format("t=%.2f", clock.T))
		check(report, #env.Surrenders == 1
			and Routing.TransferState(claims, "ana") == Routing.Failed,
			"and ownership is transferred exactly once rather than dropped",
			tostring(#env.Surrenders))
	end

	-- =====================================================================
	-- A1  THE HORIZON HAS TO SURVIVE TELEPORTASYNC'S OWN YIELD
	-- =====================================================================
	note(report, "=== A1 a slow accept may not push the retry past the declared horizon ===")
	do
		local claims = {}
		local deadline = 1000
		-- The worst case the window allows: a manual Continue at the very last
		-- instant, dispatched AT the deadline.
		Routing.ClaimTransfer(claims, "ana", "next", deadline)
		Routing.BeginAttempt(claims, "ana", "next", 5101, nil, 1, deadline, {Kind = "next"})
		-- TeleportAsync then yields for THIRTY seconds before accepting.
		local accepted = Routing.RestampAttempt(claims, "ana", 5101, deadline + 30, deadline)
		local ceiling = deadline + Routing.CohortAcceptGraceSeconds
		check(report, accepted == true and claims.ana.StartedAt == ceiling,
			"a slow accept re-anchors the attempt only as far as the accept grace",
			string.format("StartedAt=%.2f wanted=%.2f", claims.ana.StartedAt, ceiling))
		-- From that clamped anchor, walk the whole worst-case lineage.
		local arrival = claims.ana.StartedAt
			+ Routing.CohortTransferTimeoutSeconds
			+ Routing.CohortWatchdogIntervalSeconds
			+ Routing.RetryDelaySeconds
			+ Routing.TransportGraceSeconds
		local declared = deadline + Routing.CohortArrivalHorizonSeconds()
		check(report, arrival <= declared,
			"so the retry's worst-case arrival still lands inside the horizon the packet declared",
			string.format("arrival=%.2f declared=%.2f", arrival, declared))
		-- And the destination is still staging at that moment.
		check(report, Routing.ArrivalDecision({
				-- `Now` is the DESTINATION's own monotonic clock. Keeping it well
				-- inside AdmissionLocalCapSeconds is the point: the local cap is a
				-- separate bound and must not be what answers here.
				Now = 5, StartedAt = 0, FirstArrivalAt = 1,
				ServerNow = arrival - 0.01, Deadline = deadline,
				Arrived = 1, Expected = 2, Final = true,
				CohortHorizon = declared,
			}) == "wait",
			"and the destination has not admitted yet when it arrives")
		check(report, Routing.RestampAttempt(claims, "ana", 5101, deadline - 50, deadline) == true
			and claims.ana.StartedAt >= deadline,
			"a stamp BEFORE the dispatch cannot un-age the attempt either",
			string.format("StartedAt=%.2f", claims.ana.StartedAt))
		-- WHY the call site hands over the dispatch instant explicitly, when the
		-- function would fall back to record.StartedAt anyway: the fallback is
		-- the value the LAST restamp wrote. Restamp twice and the grace ratchets
		-- forward a whole grace each time, and the horizon is a lie again -- just
		-- more slowly. Anchored on the true dispatch instant it cannot move.
		do
			local ratchet = {}
			Routing.ClaimTransfer(ratchet, "bo", "next", deadline)
			Routing.BeginAttempt(ratchet, "bo", "next", 5102, nil, 1, deadline, {Kind = "next"})
			Routing.RestampAttempt(ratchet, "bo", 5102, deadline + 30, deadline)
			Routing.RestampAttempt(ratchet, "bo", 5102, deadline + 60, deadline)
			check(report, ratchet.bo.StartedAt == ceiling,
				"and a SECOND slow accept cannot ratchet the anchor another grace forward",
				string.format("StartedAt=%.2f wanted=%.2f", ratchet.bo.StartedAt, ceiling))
		end
		note(report, "MUTATION PROOF: dropping the clamp in Routing.RestampAttempt, dropping"
			.. " CohortAcceptGraceSeconds from CohortArrivalHorizonSeconds, or dropping the"
			.. " dispatch anchor at the GameManager call site, fails these.")
	end

	-- =====================================================================
	-- A2  EVERY PLAYER PRESSES CONTINUE BY HAND -- SO NO FINAL PACKET EXISTS
	-- =====================================================================
	note(report, "=== A2 an all-manual cohort still holds the destination ===")
	do
		local opened = 2000
		local source = newSource({Party = {"ana", "bo", "cy"}, Level = 1, Now = opened})
		local destination = newDestination()
		-- All three press Continue by hand, and all three are accepted at once.
		for _, member in ipairs({"ana", "bo", "cy"}) do source:continueNow(member) end
		local _, continuing = source:settle()
		check(report, #continuing == 0,
			"with everyone already departed the settlement has nobody left to carry a packet",
			tostring(#continuing))
		local sawFinal = false
		for _, sent in ipairs(source.Sent) do
			if sent.Data.FinalCohort == true then sawFinal = true end
		end
		check(report, sawFinal == false,
			"so the destination never receives a FINAL packet at all")
		-- Two of the three land; ana's first attempt was silent.
		for _, sent in ipairs(source.Sent) do
			if sent.Member ~= "ana" then destination:arrive(sent, 1) end
		end
		local deadline = source.Deadline
		local decision = destination:decide(10, deadline + Routing.TransportGraceSeconds + 0.01)
		check(report, decision == "wait",
			"an ESTIMATE that names three still holds the round past the transport grace",
			tostring(decision))
		local group = Routing.SelectArrivalSession(destination.Arrivals)
		check(report, group ~= nil and group.Expected == 3 and group.Final == false,
			"because the estimate the early pressers carried already named the whole cohort",
			group and tostring(group.Expected) or "none")
		-- ana's retry lands inside the horizon and the round admits all three.
		for _, sent in ipairs(source.Sent) do
			if sent.Member == "ana" then destination:arrive(sent, 2) end
		end
		local admitted, admittedGroup = destination:decide(11, deadline + Routing.TransportGraceSeconds + 0.02)
		check(report, admitted == "admit" and admittedGroup ~= nil and #admittedGroup.Members == 3,
			"and once the retry lands all three are admitted into ONE round",
			admittedGroup and tostring(#admittedGroup.Members) or "none")
		note(report, "MUTATION PROOF: restoring `state.Final == true` to the token-aware branch in"
			.. " Routing.ArrivalDecision admits at the grace and fails the wait check above.")
	end

	-- =====================================================================
	-- A5  THE HARNESS ITSELF MUST NOT BE ABLE TO WEDGE STUDIO
	-- =====================================================================
	note(report, "=== A5 a timer-free settlement loop is caught, not survived ===")
	do
		local clock, claims = newClock(), {}
		local env = newEnv(clock, claims)
		local rt = Routing.NewTransferRuntime(env)
		env.Runtime = rt
		-- A claim that is pending, charged, holds no handoff, and is anchored so
		-- far ahead that the hard cap can never be reached. The sweep finds
		-- nothing to do, so NOTHING is ever scheduled: the settlement loop turns
		-- into a pure spin. `Steps` cannot see it -- it only counts timers fired.
		Routing.ClaimTransfer(claims, "ana", "next", clock.Now())
		Routing.BeginAttempt(claims, "ana", "next", 5201, nil, 1, clock.Now(), {Kind = "next"})
		claims.ana.ChargedAttempt = claims.ana.AttemptId
		claims.ana.Handoff = nil
		claims.ana.LineageStartedAt = 1e12
		local before = clock.Advances
		local ok, err = pcall(function()
			return rt:AwaitSettlement(Routing.Endpoints.Continuation)
		end)
		check(report, ok == false and string.find(tostring(err), "fake clock", 1, true) ~= nil,
			"the clock stops a settlement loop that schedules nothing at all",
			tostring(err))
		check(report, clock.Advances > before and clock.Steps == 0,
			"and it is the ADVANCE counter that caught it, with no timer ever firing",
			string.format("advances=%d steps=%d", clock.Advances - before, clock.Steps))
		note(report, "MUTATION PROOF: deleting the clock.Advances assert, or the Horizon assert,"
			.. " turns this case back into the hang that wedged Studio for twenty minutes.")
	end

	return report
end

-- ---------------------------------------------------------------------------

function Suite.RunAll()
	Routing.ResetAttemptIds()
	local runs = {Suite.Module, Suite.Host, Suite.Admission, Suite.Transfers,
		Suite.Teardown, Suite.Endpoints, Suite.Cohort}
	local lines, failures, checks = {}, 0, 0
	for _, run in ipairs(runs) do
		local ok, report = pcall(run)
		if ok then
			-- Exact counts, per branch. A suite that quietly stops running half
			-- its assertions fails here instead of reporting a smaller total.
			local expected = EXPECTED_CHECKS[report.Title]
			local wanted = expected and expected[report.Branch]
			report.Checks += 1
			if wanted == nil then
				report.Failures += 1
				table.insert(report.Lines, string.format(
					"  FAIL no expected check count declared for %q branch %q",
					report.Title, report.Branch))
			elseif report.Checks - 1 ~= wanted then
				report.Failures += 1
				table.insert(report.Lines, string.format(
					"  FAIL branch %q ran %d checks, expected %d",
					report.Branch, report.Checks - 1, wanted))
			else
				table.insert(report.Lines, string.format(
					"  ok   branch %q ran its declared %d checks", report.Branch, wanted))
			end
			table.insert(lines, table.concat(report.Lines, "\n"))
			failures += report.Failures
			checks += report.Checks
		else
			table.insert(lines, "=== suite errored ===\n  FAIL " .. tostring(report))
			failures += 1
			checks += 1
		end
	end
	table.insert(lines, string.format("TOTAL: %d checks, %d failed", checks, failures))
	return table.concat(lines, "\n"), failures
end

-- Kept so the previous entry point still resolves.
Suite.Run = Suite.RunAll

return Suite
