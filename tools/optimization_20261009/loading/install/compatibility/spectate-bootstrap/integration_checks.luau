do
	local server, client = serverScenario(), clientScenario()
	local spectator, survivor = server:Player(-1, 0), server:Player(-2, 100)
	local replica = client:Player(-2, 100)
	replica.Character = nil -- the failure boundary: server character exists, client character does not
	local cursor, responseCursor = 1, 1
	local function transmit()
		while cursor <= #client.Requests do
			local request = client.Requests[cursor]; cursor += 1
			if request.Kind == "spectatecandidates" then server.Request(spectator, request.Argument)
			elseif request.Kind == "spectatetarget" then server.Select(spectator, request.Argument)
			else error("unexpected fixture client request") end
		end
		while responseCursor <= #server.Messages do
			local response = server.Messages[responseCursor]; responseCursor += 1
			client:Response(response.Payload.Serial, response.Payload.UserIds)
		end
		while cursor <= #client.Requests do
			local request = client.Requests[cursor]; cursor += 1
			assert(request.Kind == "spectatetarget", "response must only publish the selected target")
			server.Select(spectator, request.Argument)
		end
	end
	client.Start(); transmit()
	check(client:SelectedId() == survivor.UserId and replica.Character == nil, "network bootstrap chooses survivor before any client character replica exists")
	check(server:Foci(spectator) == 1 and spectator.Foci[survivor.Character.Root], "candidate reply and client target report install server focus before client stream-in")
	check(survivor:GetAttribute("SpectatorCount") == 1, "bootstrap selection retains exact spectator count")
	server.Now = 1; client.Tick(); transmit()
	check(client:SelectedId() == survivor.UserId and server:Foci(spectator) == 1, "missing-character reconciliation retains both client choice and server ownership")
	replica.Character = character(client.World, 100)
	server.Now = 2; client.Tick(); transmit()
	check(spectator.AddCalls == 1 and survivor:GetAttribute("SpectatorCount") == 1, "stream arrival does not duplicate focus or count")
	survivor.Character.Humanoid.Health = 0
	server.Now = 3; client.Tick(); transmit()
	check(client:SelectedId() == nil and server:Foci(spectator) == 0, "server death roster propagates target/focus release even with stale healthy client replica")
	check((survivor:GetAttribute("SpectatorCount") or 0) == 0, "target death returns count to zero")
	local nextSurvivor = server:Player(-3, 100)
	local nextReplica = client:Player(-3, 100); nextReplica.Character = nil
	server.Now = 4; client.Tick(); transmit()
	check(client:SelectedId() == nextSurvivor.UserId and spectator.Foci[nextSurvivor.Character.Root], "later authoritative survivor can replace empty pending view")
	client.Stop(); transmit()
	check(server:Foci(spectator) == 0 and next(server.Targets) == nil and next(server.Records) == nil, "client stop report releases server focus and count ownership")
	check(spectator.Peak == 1, "full network trace never owns two added foci")
end

do
	local c = clientScenario()
	local selected, alternative = c:Player(72, 100), c:Player(73, 100)
	c.Start()
	local serial = c:LastRequestSerial()
	for _, malformed in ipairs({false, "response", {}, {Serial = serial}, {Serial = serial, UserIds = false},
		{Serial = serial, UserIds = {alternative.UserId, "forged"}}, {Serial = serial, UserIds = {0/0}},
		{Serial = serial + .5, UserIds = {alternative.UserId}}, {Serial = math.huge, UserIds = {alternative.UserId}}}) do
		check(c.RawResponse(malformed) == false and c:SelectedId() == nil, "malformed candidate payload cannot acquire selection")
	end
	c:Response(serial, {selected.UserId})
	check(c:SelectedId() == selected.UserId, "rejected malformed response does not consume valid correlation serial")
	local reports = c:TargetReportCount()
	c:Response(serial, {alternative.UserId})
	check(c:SelectedId() == selected.UserId and c:TargetReportCount() == reports, "duplicate valid serial cannot emit a replacement target report")
end

do
	local c = clientScenario()
	local same, different, lobby = c:Player(82, 100), c:Player(83, 100), c:Player(84, 100)
	c.LocalPlayer.Attributes.Level6PlaygroundPreview = true
	c.LocalPlayer.Attributes.Level5VoidRound = true
	for _, candidate in ipairs({same, different}) do candidate.Attributes.Level6PlaygroundPreview = true end
	same.Attributes.Level5VoidRound = true
	same.Character = nil
	c.Start(); c:Response(c:LastRequestSerial(), {different.UserId, lobby.UserId, same.UserId})
	check(c:SelectedId() == same.UserId, "client domain filter chooses only same live level without requiring character")
	c.Cycle(1)
	check(c:SelectedId() == same.UserId, "cycle cannot enter cross-level or lobby candidate")
	same.Attributes.Level6PlaygroundPreview = nil; c.Refresh()
	check(c:SelectedId() == nil and c:LastTargetId() == nil, "live-domain attribute departure releases stale selection")
end
