do
	local c = serverScenario()
	local spectator = c:Player(-1, 0)
	local alive = c:Player(-2, 100)
	local dead = c:Player(-3, 0)
	local escaped = c:Player(-4, 100); escaped.Attributes.Escaped = true
	local outside = c:Player(-5, 100); c.inRound[outside] = nil
	c.Request(spectator, 1)
	local response = c:LastResponse()
	check(response ~= nil and response.Serial == 1, "valid spectator request returns its correlation serial")
	check(#response.Ids == 1 and response.Ids[1] == alive.UserId, "candidate roster is server-authoritative and excludes self/dead/escaped/nonparticipants")
	check(c:Foci(spectator) == 0, "candidate discovery alone does not create spectator ownership")
	local total = #c.Messages
	c.Request(alive, 1)
	check(#c.Messages == total, "living non-spectator cannot request a candidate roster")
	c.Request(spectator, 2, {999, outside.UserId})
	check(#c.Messages == total, "per-player rate guard rejects immediate repeat")
	c.Now = 0.79; c.Request(spectator, 3)
	check(#c.Messages == total, "rate guard remains closed before 0.8 seconds")
	c.Now = 1; c.Request(spectator, 4, {999, outside.UserId})
	response = c:LastResponse()
	check(#c.Messages == total + 1 and response.Serial == 4, "existing one-second client cadence can refresh candidates")
	check(#response.Ids == 1 and response.Ids[1] == alive.UserId, "forged client candidate IDs cannot change authoritative roster")
	c.Select(spectator, 999)
	check(c:Foci(spectator) == 0, "forged unknown selected ID cannot acquire focus")
	c.Select(spectator, outside.UserId)
	check(c:Foci(spectator) == 0, "selected nonparticipant cannot acquire focus")
	c.Select(spectator, alive.UserId)
	check(c:Foci(spectator) == 1 and spectator.Foci[alive.Character.Root], "valid candidate selection owns one server focus")
	check(alive:GetAttribute("SpectatorCount") == 1, "valid candidate selection retains existing spectator counts")
	local own = spectator.ReplicationFocus
	alive.Character.Humanoid.Health = 0; c.Reconcile()
	check(c:Foci(spectator) == 0 and (alive:GetAttribute("SpectatorCount") or 0) == 0, "target death releases focus and count")
	c.Now = 2; c.Request(spectator, 5)
	check(#c:LastResponse().Ids == 0, "fresh authoritative roster removes stale dead candidate")
	check(spectator.ReplicationFocus == own, "own-character replication focus remains untouched")
end

do
	local c = serverScenario()
	local spectator, sameLive, differentLive, lobby = c:Player(101, 0), c:Player(102, 100), c:Player(103, 100), c:Player(104, 100)
	c.World.Attributes.RoundActive = false
	for _, player in ipairs(c.Roster) do c.inRound[player] = nil end
	for _, player in ipairs({spectator, sameLive, differentLive}) do
		player.Attributes.Level6PlaygroundPreview = true
	end
	spectator.Attributes.Level5VoidRound, sameLive.Attributes.Level5VoidRound = true, true
	differentLive.Attributes.Level5VoidRound = nil
	c.Request(spectator, 1)
	local response = c:LastResponse()
	check(response ~= nil and #response.Ids == 1 and response.Ids[1] == sameLive.UserId, "live-level fallback includes only same active level domain")
	c.Select(spectator, differentLive.UserId)
	check(c:Foci(spectator) == 0, "forged cross-live-level selection cannot acquire focus")
	c.Select(spectator, sameLive.UserId)
	check(c:Foci(spectator) == 1 and spectator.Foci[sameLive.Character.Root], "same-live-level candidate uses existing single-focus owner")
	sameLive.Attributes.InRound = nil; c.Reconcile()
	check(c:Foci(spectator) == 0, "live participant leaving its round releases focus")
	c.Now = 1; c.Request(spectator, 2)
	check(#c:LastResponse().Ids == 0, "live-level roster removes inactive domain participant")
	c.Select(spectator, lobby.UserId)
	check(c:Foci(spectator) == 0, "ordinary lobby player remains outside live-level candidates")
end

do
	local c = serverScenario()
	local spectator, target, replacement = c:Player(10, 0), c:Player(20, 100), c:Player(30, 100)
	for _, invalid in ipairs({0, -1, 1.5, math.huge, 0/0, "1", {}}) do c.Request(spectator, invalid) end
	check(#c.Messages == 0, "malformed request correlation IDs produce no response")
	c.Request(spectator, 1)
	c.Select(spectator, target.UserId)
	c.Select(spectator, replacement.UserId)
	check(c:Foci(spectator) == 1 and spectator.Peak == 1 and spectator.Foci[replacement.Character.Root], "candidate cycling removes old focus before adding replacement")
	check(spectator.FocusEvents[2][1] == "remove" and spectator.FocusEvents[3][1] == "add", "focus replacement order remains exact")
	c:Leave(replacement)
	check(c:Foci(spectator) == 0 and next(c.Targets) == nil, "selected target departure releases stale ownership immediately")
	c.Now = 1; c.Request(spectator, 2)
	check(#c:LastResponse().Ids == 1 and c:LastResponse().Ids[1] == target.UserId, "departed target is absent from refreshed roster")
	c.Select(spectator, target.UserId)
	spectator.Character = character(c.World, 100)
	c.Reconcile()
	check(c:Foci(spectator) == 0 and next(c.Targets) == nil, "spectator respawn releases previous camera ownership")
	local responses = #c.Messages
	c.Now = 2; c.Request(spectator, 3)
	check(#c.Messages == responses, "respawned living spectator cannot reuse stale candidate eligibility")
	spectator.Character.Humanoid.Health = 0; c.Select(spectator, target.UserId)
	c.Clear()
	check(c:Foci(spectator) == 0 and next(c.Targets) == nil and next(c.Records) == nil, "round reset clears count and focus ownership")
	c:Leave(spectator)
	check(c.RateOwned(spectator) == false, "departed spectator cannot retain request-rate ownership")
	check(spectator.Peak == 1, "all lifecycle transitions retain one-focus maximum")
end

do
	local c = serverScenario()
	local first, second, target = c:Player(-100, 0), c:Player(-200, 0), c:Player(-300, 100)
	c.Request(first, 1); c.Request(second, 1)
	check(#c.Messages == 2, "candidate rate limit is independent for each participant")
	c.Select(first, target.UserId); c.Select(second, target.UserId)
	check(target:GetAttribute("SpectatorCount") == 2, "multiple spectators retain aggregate count")
	c:Leave(first)
	check(c:Foci(first) == 0 and target:GetAttribute("SpectatorCount") == 1, "one spectator departure preserves remaining viewer")
	check(not c.RateOwned(first) and c.RateOwned(second), "request-rate cleanup is scoped to departing participant")
	c.Clear()
	check(c:Foci(second) == 0 and (target:GetAttribute("SpectatorCount") or 0) == 0, "round end releases the remaining viewer")
	check(not c.RateOwned(second), "round reset clears request-rate ownership")
end

do
	local c = serverScenario()
	local spectator, survivor = c:Player(201, 0), c:Player(202, 100)
	c.Request(spectator, 1)
	check(c.RateOwned(spectator) and next(c.Targets) == nil, "candidate request can own rate state before target selection")
	c.Clear()
	check(not c.RateOwned(spectator), "empty-target round reset still clears request-rate state")
	c.Request(spectator, 2)
	check(#c.Messages == 2, "fresh round ownership is not delayed by a previous cleared rate record")
	spectator.Character = character(c.World, 100)
	c.Reconcile()
	check(not c.RateOwned(spectator), "periodic reconciliation prunes request-only ownership after respawn")
end
