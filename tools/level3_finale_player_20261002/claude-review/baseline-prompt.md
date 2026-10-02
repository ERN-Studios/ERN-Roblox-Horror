Review the current baseline for a requested public Level 3 finale + CD player scanner change. This is a read-only baseline review to inform implementation, not a review of an already-final patch. Return concrete root causes, minimal scoped fixes, and an edge-case/runtime test matrix, in at most 1200 words. Prioritize actual code violations and distinguish inference from runtime facts. No gameplay/multiplayer/performance checks have been run by this review.

Owner requirements:
1. Studio is authoritative. Only fresh live-scope changes; never repository bulk push. You receive exact local mirrors matching root's current Source/editor fingerprints for AI, Objective, Reader.
2. After ALL living round participants have strictly PASSED 50% of the actual long exit corridor, Manager must spawn at exactly the authored far end and immediately CHASE toward players. Never spawn near the player, use an alternate nearby point, or relocate on navigation recovery. Dead, escaped, disconnected, non-round spectators do not count. Living protected participants do count toward the crossing barrier; preserve attack immunity. Character-scoped crossing latch means a new revived character cannot inherit old crossing. A character having crossed then walking back still has passed; identify if stale-position behavior matters for exact requested policy.
3. The scanner should change from finding discs to finding the CD PLAYER once all current team discs are CARRIED/INSERTED but insertion is incomplete. It should revert immediately when any CD is WORLD/DROPPED, even if cumulative collected count remains goal. Use the real post-Visual DiscPlayer.Position published by Objective as Level3_CDPlayerPosition / workspace Level3CDPlayerPosition; clear on reset. Provide precise full360 camera-relative bearing + distance and world/projected target or edge pointer; correctly handle behind-camera targets, spectated watched subject, hidden/toast/modal/dispatch/hiding gates, touch safe layout and teardown. Missing beacon positions alone do not prove every CD is secured. Never add implementation detail or backend wording to product UI.

Known facts: Config authored hall length560, midway.50, old Manager spawn progress.97, ordinary minimumdistance90, fixed finale speed28, SpawnGraceSeconds0. Runtime checks still required after implementation. GameManager's actual inRound map and participantSet are local server state; Level3 modules currently use server-written InRound attr. No actualInRound API appears in supplied baseline. Music DONE transitions Hunt false; adapter then makes a fresh start only on Hunt edge. Ordinary existing Manager cannot simply be preserved for finale. Review protection/pause, retries, fallback, target/no-target, state latch, cleanup.

Code excerpts (original line numbers):

### AI: ServerScriptService/Level 3 Systems/Level 3 Mall Manager AI Controller.ModuleScript.lua SHA256 af5885402a9d42760e7ba059057d186a97395fab20819a8bd6e7aab481f7598d
```lua

-- excerpt 98-190
98: local function liveSession(session: any): boolean
99: 	local world = session and session.World
100: 	return activeSession == session
101: 		and session.Active == true
102: 		and world ~= nil
103: 		and world:IsA("Model")
104: 		and world.Parent == workspace
105: 		and world:GetAttribute("Level3_Generation") == session.Generation
106: end
107: 
108: local function validRound(session: any): boolean
109: 	return liveSession(session)
110: 		and workspace:GetAttribute("SelectedLevel") == 3
111: 		and workspace:GetAttribute("RoundActive") == true
112: 		and workspace:GetAttribute("Level3MallManagerHuntActive") == true
113: 		and workspace:GetAttribute("EntityPaused") ~= true
114: end
115: 
116: local function blackoutProfileRequested(): boolean
117: 	return workspace:GetAttribute("Level3BlackoutActive") == true
118: 		or workspace:GetAttribute("Level3FinalHallChaseActive") == true
119: end
120: 
121: local function publishMotion(session: any, dt: number, hardSnap: boolean?)
122: 	if not session.MotionRemote or not session.Model or not session.Model.Parent then return end
123: 	local interval = 1 / math.max(1, Tuning.MotionSnapshotRate)
124: 	session.MotionAccumulator += dt
125: 	if not hardSnap and session.MotionAccumulator < interval then return end
126: 	session.MotionAccumulator = if hardSnap then 0 else session.MotionAccumulator % interval
127: 	session.MotionSequence += 1
128: 	session.MotionRemote:FireAllClients(
129: 		session.Model,
130: 		session.Generation,
131: 		session.SpawnSerial,
132: 		session.MotionSequence,
133: 		workspace:GetServerTimeNow(),
134: 		session.Root.CFrame,
135: 		hardSnap == true
136: 	)
137: end
138: 
139: local function livingPlayer(player: Player, session: any): (Model?, Humanoid?, BasePart?)
140: 	if not validRound(session)
141: 		or player.Parent ~= Players
142: 		or player:GetAttribute("InRound") ~= true
143: 		or player:GetAttribute("Escaped") == true then
144: 		return nil, nil, nil
145: 	end
146: 	local character = player.Character
147: 	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
148: 	local root = character and character:FindFirstChild("HumanoidRootPart")
149: 	if not character or not character.Parent or not humanoid or humanoid.Health <= 0
150: 		or not root or not root:IsA("BasePart")
151: 		or PlayerProtection.IsActive(player, character) then
152: 		return nil, nil, nil
153: 	end
154: 	return character, humanoid, root
155: end
156: 
157: local function profile(session: any): any
158: 	return if session.Blackout then Tuning.Blackout else Tuning.Normal
159: end
160: 
161: local function goalMoveThreshold(session: any): number
162: 	return if session.Blackout
163: 		then Tuning.BlackoutPathGoalMoveThreshold else Tuning.PathGoalMoveThreshold
164: end
165: 
166: -- The hard floor between ComputeAsync starts. In blackout this is
167: -- BlackoutPathRecomputeSeconds = 0.20, i.e. at most five requests per second;
168: -- forced recovery requests queue behind it instead of bypassing it.
169: local function pathRequestInterval(session: any): number
170: 	return if session.Blackout then Tuning.BlackoutPathRecomputeSeconds else Tuning.PathRecomputeSeconds
171: end
172: 
173: local insideFinalHall
174: local function currentSpeed(session: any): number
175: 	local stateName = session.State
176: 	local activeProfile = profile(session)
177: 	if session.FinalHallChase and stateName == "CHASE" then
178: 		-- The finale starts ahead of the players and walks toward them.
179: 		-- Keep a fixed speed; the old catch-up calculation assumed a spawn behind them.
180: 		return Tuning.FinaleApproachSpeed
181: 	end
182: 	if stateName == "PATROL" or stateName == "PATROL_LISTEN" or stateName == "AWAKENING" then
183: 		return activeProfile.PatrolSpeed
184: 	end
185: 	if stateName == "INVESTIGATE" or stateName == "ALERT" or stateName == "RECOVER" then
186: 		return activeProfile.InvestigateSpeed
187: 	end
188: 	if stateName == "SEARCH" or stateName == "TRACKING" then return activeProfile.SearchSpeed end
189: 	if stateName == "CHASE" then return activeProfile.ChaseSpeed end
190: 	if stateName == "ATTACK_WINDUP" then return activeProfile.PatrolSpeed end

-- excerpt 1973-2176
1973: local function choosePatrolGoal(session: any, now: number)
1974: 	abandonTableCheckTarget(session, now)
1975: 	local checkAnchor = chooseTableCheckAnchor(session, now)
1976: 	if checkAnchor then
1977: 		-- Same sweep-leg bookkeeping as an ordinary room goal, so the distance
1978: 		-- and leg-timeout escapes below still rescue a table the Manager cannot
1979: 		-- actually reach.
1980: 		session.TableCheckTargetAnchor = checkAnchor
1981: 		session.PatrolGoal = flat(checkAnchor.Position, session.FloorY)
1982: 		session.PatrolWaitUntil = nil
1983: 		session.PatrolLegUntil = now + blackoutSweepLegDuration(
1984: 			planarDistance(session.Root.Position, session.PatrolGoal))
1985: 		setGoal(session, session.PatrolGoal, true)
1986: 		publishState(session, "PATROL")
1987: 		return
1988: 	end
1989: 	local candidates = {}
1990: 	for _, room in ipairs(layoutRooms()) do
1991: 		if room.Id ~= "Arrival" and room.Id ~= "Exit" then
1992: 			local recentlyUsed = false
1993: 			for _, recentId in ipairs(session.RecentPatrolRooms) do
1994: 				if recentId == room.Id then recentlyUsed = true break end
1995: 			end
1996: 			if not recentlyUsed then table.insert(candidates, room.Id) end
1997: 		end
1998: 	end
1999: 	if #candidates == 0 then
2000: 		table.clear(session.RecentPatrolRooms)
2001: 		return choosePatrolGoal(session, now)
2002: 	end
2003: 	local roomId = candidates[session.Random:NextInteger(1, #candidates)]
2004: 	table.insert(session.RecentPatrolRooms, roomId)
2005: 	while #session.RecentPatrolRooms > 4 do table.remove(session.RecentPatrolRooms, 1) end
2006: 	local room = roomDefinition(roomId)
2007: 	local center = roomCenter(roomId, session.FloorY) :: Vector3
2008: 	local rangeX = math.min(12, room.W * .18)
2009: 	local rangeZ = math.min(12, room.D * .18)
2010: 	session.PatrolGoal = Vector3.new(
2011: 		center.X + session.Random:NextNumber(-rangeX, rangeX),
2012: 		session.FloorY,
2013: 		center.Z + session.Random:NextNumber(-rangeZ, rangeZ)
2014: 	)
2015: 	session.PatrolWaitUntil = nil
2016: 	session.PatrolLegUntil = now + blackoutSweepLegDuration(
2017: 		planarDistance(session.Root.Position, session.PatrolGoal))
2018: 	setGoal(session, session.PatrolGoal, true)
2019: 	publishState(session, "PATROL")
2020: end
2021: 
2022: local function nearestLivingPlayer(session: any): (Player?, BasePart?)
2023: 	local selected: Player? = nil
2024: 	local selectedRoot: BasePart? = nil
2025: 	local bestDistance = math.huge
2026: 	local selectedInFinalHall = false
2027: 	for _, candidate in ipairs(Players:GetPlayers()) do
2028: 		local _, _, candidateRoot = livingPlayer(candidate, session)
2029: 		if candidateRoot then
2030: 			local distance = planarDistance(session.Root.Position, candidateRoot.Position)
2031: 			-- During the finale, a nearby player in an adjacent room must not pull
2032: 			-- the ambush away from runners in the exit lane. Normal hunts are unchanged.
2033: 			local inFinalHall = session.FinalHallChase and insideFinalHall(session, candidateRoot.Position)
2034: 			if (inFinalHall and not selectedInFinalHall)
2035: 				or (inFinalHall == selectedInFinalHall and (distance < bestDistance - .001
2036: 					or (math.abs(distance - bestDistance) <= .001
2037: 						and (not selected or candidate.UserId < selected.UserId)))) then
2038: 				selected = candidate
2039: 				selectedRoot = candidateRoot
2040: 				bestDistance = distance
2041: 				selectedInFinalHall = inFinalHall
2042: 			end
2043: 		end
2044: 	end
2045: 	return selected, selectedRoot
2046: end
2047: 
2048: local function trackNearestBlackoutPlayer(session: any, now: number): boolean
2049: 	local nearestPlayer, nearestRoot = nearestLivingPlayer(session)
2050: 	if not nearestPlayer or not nearestRoot then
2051: 		if session.Attacking then
2052: 			session.AttackToken += 1
2053: 			session.Attacking = false
2054: 			session.AttackCooldownUntil = now
2055: 		end
2056: 		publishTarget(session, nil)
2057: 		session.LastKnownPosition = nil
2058: 		session.LastKnownPlayer = nil
2059: 		session.LastKnownCharacter = nil
2060: 		session.LastSenseAt = -math.huge
2061: 		session.SearchUntil = nil
2062: 		-- Patrol only when no living round participant remains. Hiding players
2063: 		-- remain chase targets and therefore never enter this fallback.
2064: 		local sweepGoal = arrivalGoal(session)
2065: 		if session.PatrolGoal and (not sweepGoal
2066: 			or planarDistance(session.Root.Position, sweepGoal) <= Tuning.GoalTolerance + 1) then
2067: 			session.PatrolGoal = nil
2068: 		end
2069: 		-- Second, independent reason to move on: a sweep leg that has taken longer
2070: 		-- than any honest walk across the mall is stuck, whether or not the
2071: 		-- distance test agrees. Without this the hunt can still stall on a goal
2072: 		-- navigation quietly gave up on.
2073: 		if session.PatrolGoal and session.PatrolLegUntil and now >= session.PatrolLegUntil then
2074: 			session.PatrolGoal = nil
2075: 		end
2076: 		if not session.PatrolGoal then
2077: 			choosePatrolGoal(session, now)
2078: 		else
2079: 			publishState(session, "PATROL")
2080: 		end
2081: 		publishTargetTelemetry(session, "NO_LIVING_PLAYER", -1, nil)
2082: 		return false
2083: 	end
2084: 
2085: 	local targetDistance = planarDistance(session.Root.Position, nearestRoot.Position)
2086: 
2087: 	local switchedTarget = session.Target ~= nearestPlayer
2088: 	if switchedTarget and session.Attacking then
2089: 		-- A nearer player owns the chase immediately. Cancel the old windup so the
2090: 		-- Manager never attacks a player it is no longer pursuing.
2091: 		session.AttackToken += 1
2092: 		session.Attacking = false
2093: 		session.AttackCooldownUntil = now
2094: 	end
2095: 	publishTarget(session, nearestPlayer)
2096: 	local targetAnchor = HidingController.GetAnchor(nearestPlayer, session.Generation)
2097: 	session.TargetTableAnchor = targetAnchor
2098: 	-- The nearest player owns the chase. A prior random patrol-table leg cannot
2099: 	-- divert it, whether that player is exposed or underneath a table.
2100: 	session.TableCheckTargetAnchor = nil
2101: 
2102: 	local targetPosition = flat(nearestRoot.Position, session.FloorY)
2103: 	local velocity = Vector3.new(nearestRoot.AssemblyLinearVelocity.X, 0,
2104: 		nearestRoot.AssemblyLinearVelocity.Z)
2105: 	local lead = velocity * Tuning.BlackoutTargetLeadSeconds
2106: 	if lead.Magnitude > Tuning.BlackoutTargetLeadMaximumDistance then
2107: 		lead = lead.Unit * Tuning.BlackoutTargetLeadMaximumDistance
2108: 	end
2109: 	local predicted = targetPosition + lead
2110: 	if not targetAnchor and volumeFits(session, predicted) then targetPosition = predicted end
2111: 
2112: 	session.LastKnownPosition = targetPosition
2113: 	session.LastKnownPlayer = nearestPlayer
2114: 	session.LastKnownCharacter = nearestPlayer.Character
2115: 	session.LastSenseAt = now
2116: 	session.LastVisualAt = now
2117: 	session.SearchUntil = nil
2118: 	session.PatrolGoal = nil
2119: 	session.AlertUntil = 0
2120: 	-- Aim at the table centre so safe-goal resolution selects its clear outer
2121: 	-- perimeter, rather than trying to squeeze the rig into an occupant slot.
2122: 	local navigationTarget = if targetAnchor then targetAnchor.Position else targetPosition
2123: 	setGoal(session, navigationTarget, switchedTarget)
2124: 
2125: 	publishTargetTelemetry(session, "NEAREST_PLAYER", targetDistance, targetPosition)
2126: 	if not session.Attacking then publishState(session, "CHASE") end
2127: 	return true
2128: end
2129: 
2130: local function beginSearch(session: any, now: number)
2131: 	publishTarget(session, nil)
2132: 	session.SearchUntil = now + profile(session).SearchSeconds
2133: 	session.SearchNextAt = 0
2134: 	publishState(session, "SEARCH")
2135: 	chooseSearchGoal(session, now)
2136: end
2137: 
2138: local function dormant(session: any, stateName: string)
2139: 	publishTarget(session, nil)
2140: 	session.LastKnownPosition = nil
2141: 	session.LastKnownPlayer = nil
2142: 	session.LastKnownCharacter = nil
2143: 	session.LastSenseAt = -math.huge
2144: 	session.AlertUntil = 0
2145: 	session.SearchUntil = nil
2146: 	session.PatrolGoal = nil
2147: 	session.CurrentMoveSpeed = 0
2148: 	session.LastActualStepDistance = 0
2149: 	clearGoal(session)
2150: 	publishState(session, stateName)
2151: 	if stateName == "PAUSED" then
2152: 		holdWalkPose(session)
2153: 	else
2154: 		setWalk(session, false, 0)
2155: 	end
2156: end
2157: 
2158: local function updateBrain(session: any, now: number, dt: number)
2159: 	if not validRound(session) then
2160: 		dormant(session, if workspace:GetAttribute("EntityPaused") == true then "PAUSED" else "WAITING")
2161: 		return
2162: 	end
2163: 	if now < session.ActivatedAt then
2164: 		publishTarget(session, nil)
2165: 		clearGoal(session)
2166: 		publishState(session, "AWAKENING")
2167: 		return
2168: 	end
2169: 	-- During the blackout hunt the Manager is supernatural: every think tick it
2170: 	-- chooses the nearest eligible player and feeds that moving position straight
2171: 	-- into the existing strategic/PFS route system. Normal non-blackout behavior
2172: 	-- still uses sight, suspicion, hearing, memory, and search below.
2173: 	if session.Blackout then
2174: 		trackNearestBlackoutPlayer(session, now)
2175: 		return
2176: 	end

-- excerpt 2486-2558
2486: local function attackLineClear(session: any, player: Player, maximumRange: number): (boolean, Humanoid?)
2487: 	if HidingController.IsHidden(player, session.Generation) then return false, nil end
2488: 	-- A flushed player gets a head start, never an instant kill: the Manager can
2489: 	-- chase and be right on top of them, but the attack itself is refused.
2490: 	if HidingController.IsFlushImmune(player) then return false, nil end
2491: 	local character, humanoid, root = livingPlayer(player, session)
2492: 	if not character or not humanoid or not root then return false, nil end
2493: 	if planarDistance(session.Root.Position, root.Position) > maximumRange
2494: 		or math.abs(session.Root.Position.Y - root.Position.Y) > Tuning.VerticalAttackTolerance then
2495: 		return false, humanoid
2496: 	end
2497: 	return hasSightRay(session, character, root), humanoid
2498: end
2499: 
2500: local function beginAttack(session: any, player: Player)
2501: 	if session.Attacking or os.clock() < session.AttackCooldownUntil then return end
2502: 	-- LEVEL3_MANAGER_WALL_HUG_ATTACK_20260827
2503: 	-- When the chase goal had to resolve away from the target (the target's
2504: 	-- own clearance volume is blocked — pressed against a wall), the Manager
2505: 	-- legitimately parks up to one resolved ring outside AttackRange. Initiate
2506: 	-- from the existing AttackConfirmRange in that case; the confirm range,
2507: 	-- windup, and line-of-sight ray still gate the actual kill, so a wall
2508: 	-- between the two continues to block attacks.
2509: 	local initiationRange = Tuning.AttackRange
2510: 	if session.FinalGoal and session.ResolvedFinalGoal
2511: 		and planarDistance(session.FinalGoal, session.ResolvedFinalGoal) > 1 then
2512: 		initiationRange = Tuning.AttackConfirmRange
2513: 	end
2514: 	local clear, attackHumanoid = attackLineClear(session, player, initiationRange)
2515: 	local attackCharacter = player.Character
2516: 	if not clear or not attackHumanoid or not attackCharacter then return end
2517: 	session.AttackPlayer = player
2518: 	session.AttackCharacter = attackCharacter
2519: 	session.Attacking = true
2520: 	session.AttackToken += 1
2521: 	local attackToken = session.AttackToken
2522: 	publishState(session, "ATTACK_WINDUP")
2523: 	local _, _, targetRoot = livingPlayer(player, session)
2524: 	if targetRoot then facePosition(session, targetRoot.Position) end
2525: 	local windup = if session.Blackout then Tuning.BlackoutAttackWindupSeconds else Tuning.AttackWindupSeconds
2526: 	task.delay(windup, function()
2527: 		if not liveSession(session) or session.AttackToken ~= attackToken then return end
2528: 		local confirmed, humanoid = attackLineClear(session, player, Tuning.AttackConfirmRange)
2529: 		confirmed = confirmed and player.Character == attackCharacter
2530: 			and humanoid == attackHumanoid and not PlayerProtection.IsActive(player, attackCharacter)
2531: 		if confirmed and humanoid and humanoid.Health > 0 then
2532: 			session.AttackSerial += 1
2533: 			session.StateFolder:SetAttribute("Level3_MallManagerAttackSerial", session.AttackSerial)
2534: 			session.StateFolder:SetAttribute("Level3_MallManagerLastCaptureUserId", player.UserId)
2535: 			if session.Model.Parent then
2536: 				session.Model:SetAttribute("Level3_MallManagerAttackSerial", session.AttackSerial)
2537: 				session.Model:SetAttribute("Level3_MallManagerLastCaptureUserId", player.UserId)
2538: 			end
2539: 			DeathAdvice.Mark(player, "L3Manager")
2540: 			humanoid.Health = 0
2541: 			session.LastKnownPosition = nil
2542: 			session.LastKnownPlayer = nil
2543: 			session.LastKnownCharacter = nil
2544: 			session.LastSenseAt = -math.huge
2545: 			publishTarget(session, nil)
2546: 		end
2547: 		session.Attacking = false
2548: 		session.AttackPlayer = nil
2549: 		session.AttackCharacter = nil
2550: 		local recovery = if session.Blackout
2551: 			then Tuning.BlackoutAttackRecoverySeconds else Tuning.AttackRecoverySeconds
2552: 		session.AttackCooldownUntil = os.clock() + recovery
2553: 		if validRound(session) then
2554: 			publishState(session, if confirmed then "SEARCH" else "RECOVER")
2555: 		else
2556: 			dormant(session, "WAITING")
2557: 		end
2558: 	end)

-- excerpt 2561-2589
2561: local function movementWaypoint(session: any, destination: Vector3, speed: number, dt: number): Vector3?
2562: 	local currentGround = flat(session.Root.Position, session.FloorY)
2563: 	-- Checked authored repairs have waypoints but no Roblox Path object.
2564: 	if not session.Path then
2565: 		-- Strategic destinations are adjacent authored room centers. A full-volume
2566: 		-- clear sweep is a real centerline fallback even when the segment is long.
2567: 		if volumeClear(session, currentGround, destination) then
2568: 			local resolvedGoal = session.ResolvedFinalGoal or session.FinalGoal
2569: 			if resolvedGoal and planarDistance(destination, resolvedGoal)
2570: 				<= Tuning.GoalTolerance then
2571: 				markPathValidated(session)
2572: 			end
2573: 			return destination
2574: 		end
2575: 		if session.PathFailures > 0 and installRoomPerimeterPath(session, destination) then
2576: 			return session.Path[1].Position
2577: 		end
2578: 		requestPath(session, destination)
2579: 		-- Keep advancing only through a verified short clear segment while the
2580: 		-- first route computes; this removes the visible path-acquisition pause.
2581: 		local offset = destination - currentGround
2582: 		if offset.Magnitude > .05 then
2583: 			local probeDistance = math.min(offset.Magnitude,
2584: 				math.max(2, speed * math.min(dt, Tuning.MaximumMovementDeltaSeconds) * 3))
2585: 			local probe = currentGround + offset.Unit * probeDistance
2586: 			if volumeClear(session, currentGround, probe) then return probe end
2587: 		end
2588: 		return nil
2589: 	end

-- excerpt 2669-2693
2669: local function resetBlockedRoute(session: any, now: number)
2670: 	-- Navigation recovery only resets progress bookkeeping. It never rewinds,
2671: 	-- teleports, or changes the rendered transform.
2672: 	--
2673: 	-- LEVEL3_MANAGER_ESCALATION_SURVIVES_RECOVERY_20260827
2674: 	-- This deliberately does NOT clear OverlapEscapeAttempts. Recovery fires
2675: 	-- after ObstructionRecoveryAttempts refused steering frames — the very
2676: 	-- frames the overlap ladder uses to escalate — so clearing it here made the
2677: 	-- exhausted branch unreachable and produced an endless reset/repath loop.
2678: 	-- The ladder now resets only where genuine improvement is proven: standing
2679: 	-- clear of the overlap, a renewal backed by a measurable blocker or
2680: 	-- goal-distance gain.
2681: 	--
2682: 	-- LastProgressAt is the stuck-timer baseline and is intentionally rearmed
2683: 	-- so recovery gets a fresh window; LastGenuineProgressAt is left untouched
2684: 	-- so recovery can never masquerade as movement in telemetry.
2685: 	session.LastProgressAt = now
2686: 	session.ProgressObjectiveKey = nil
2687: 	session.ProgressBestDistance = math.huge
2688: 	session.ProgressCreditedDistance = math.huge
2689: 	session.PathFailures = 0
2690: 	session.ConsecutiveObstructions = 0
2691: 	session.RecoveryRepaths += 1
2692: 	publishPathStatus(session, "RECOVERY_REPATH")
2693: end

-- excerpt 3041-3075
3041: 	if now - session.LastProgressAt < Tuning.StuckSeconds then return end
3042: 	-- No genuine progress across a whole stuck interval: repath, escalating to
3043: 	-- a full recovery with a fresh strategic route when failures pile up.
3044: 	session.LastProgressAt = now
3045: 	session.StuckRecoveries += 1
3046: 	session.PathFailures += 1
3047: 	local exhausted = session.PathFailures >= Tuning.MaxPathFailures
3048: 	clearPath(session, "STUCK_REPATH")
3049: 	if exhausted then
3050: 		resetBlockedRoute(session, now)
3051: 		rebuildStrategicRoute(session, true)
3052: 	end
3053: 	requestPath(session, destination, true)
3054: end
3055: 
3056: local function updateMovement(session: any, dt: number, now: number)
3057: 	if session.DebugMovementPaused == true then
3058: 		session.CurrentMoveSpeed = 0
3059: 		session.LastActualStepDistance = 0
3060: 		setWalk(session, false, 0)
3061: 		-- Studio regression fixtures freeze only the transform. Keep the real
3062: 		-- destination/progress bookkeeping alive so a moving target cannot receive
3063: 		-- an unearned progress credit merely because the test paused locomotion.
3064: 		local pausedDestination = currentDestination(session)
3065: 		if pausedDestination then
3066: 			trackNavigationProgress(session, now, pausedDestination)
3067: 		end
3068: 		return
3069: 	end
3070: 	if not validRound(session) then
3071: 		session.CurrentMoveSpeed = 0
3072: 		session.LastActualStepDistance = 0
3073: 		setWalk(session, false, 0)
3074: 		return
3075: 	end

-- excerpt 3195-3206
3195: local function applyBlackout(session: any, active: boolean)
3196: 	if not liveSession(session) or session.Blackout == active then
3197: 		if liveSession(session) then publishProfile(session) end
3198: 		return
3199: 	end
3200: 	session.Blackout = active
3201: 	-- Speed and awareness swap immediately, but the geometry and agent size do
3202: 	-- not. Preserve the current route so the blackout edge cannot cause a hitch.
3203: 	if session.Path then publishPathStatus(session, "PROFILE_CHANGED_CONTINUING") end
3204: 	publishProfile(session)
3205: 	publishState(session, session.State)
3206: end

-- excerpt 3306-3323
3306: local function eligibleSpawnPlayers(): {any}
3307: 	local records = {}
3308: 	if workspace:GetAttribute("SelectedLevel") ~= 3 or workspace:GetAttribute("RoundActive") ~= true then
3309: 		return records
3310: 	end
3311: 	for _, player in ipairs(Players:GetPlayers()) do
3312: 		if player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") ~= true then
3313: 			local character = player.Character
3314: 			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
3315: 			local root = character and character:FindFirstChild("HumanoidRootPart")
3316: 			if character and character.Parent and humanoid and humanoid.Health > 0
3317: 				and root and root:IsA("BasePart")
3318: 				and not PlayerProtection.IsActive(player, character) then
3319: 				table.insert(records, {Player=player, Character=character, Root=root, Position=root.Position})
3320: 			end
3321: 		end
3322: 	end
3323: 	return records

-- excerpt 3352-3456
3352: local function spawnOverlapParams(records: {any}): OverlapParams
3353: 	local params = OverlapParams.new()
3354: 	params.FilterType = Enum.RaycastFilterType.Exclude
3355: 	local ignored = {}
3356: 	for _, record in ipairs(records) do table.insert(ignored, record.Character) end
3357: 	params.FilterDescendantsInstances = ignored
3358: 	params.RespectCanCollide = true
3359: 	params.MaxParts = 1
3360: 	return params
3361: end
3362: 
3363: local function spawnVolumeFits(position: Vector3, params: OverlapParams): boolean
3364: 	local boxCFrame, size = clearanceBox(position)
3365: 	return #workspace:GetPartBoundsInBox(boxCFrame, size, params) == 0
3366: end
3367: 
3368: local function spawnVisibilityCount(position: Vector3, records: {any}): number
3369: 	local params = RaycastParams.new()
3370: 	params.FilterType = Enum.RaycastFilterType.Exclude
3371: 	local ignored = {}
3372: 	for _, record in ipairs(records) do table.insert(ignored, record.Character) end
3373: 	params.FilterDescendantsInstances = ignored
3374: 	params.IgnoreWater = true
3375: 	params.RespectCanCollide = true
3376: 	local target = position + Vector3.new(0, 4.2, 0)
3377: 	local visible = 0
3378: 	for _, record in ipairs(records) do
3379: 		local head = record.Character:FindFirstChild("Head")
3380: 		local origin = if head and head:IsA("BasePart") then head.Position else record.Position + Vector3.new(0, 2.5, 0)
3381: 		if not workspace:Raycast(origin, target - origin, params) then visible += 1 end
3382: 	end
3383: 	return visible
3384: end
3385: 
3386: local function chooseFinalHallSpawn(manifest: any, generation: number): any?
3387: 	local records = eligibleSpawnPlayers()
3388: 	if #records == 0 then return nil end
3389: 	local hall = manifest.FinalHall
3390: 	if type(hall) ~= "table" or not hall.Model or not hall.Model.Parent then return nil end
3391: 	local state = stateFolder()
3392: 	local cycle = math.floor(tonumber(state:GetAttribute("Level3_RoomSongCycle")) or 0)
3393: 	local random = Random.new(generation * 7919 + cycle * 104729 + 20260824)
3394: 	-- Start in the last ten percent of the actual final corridor and face its runners.
3395: 	-- Preserve the normal minimum distance from EVERY eligible living participant.
3396: 	-- If someone is already at the far end, bindManager retries until it is safe;
3397: 	-- never relocate the reveal beside that player or back to the level entrance.
3398: 	local position: Vector3? = nil
3399: 	local overlap = spawnOverlapParams(records)
3400: 	local preferred = math.clamp(tonumber(hall.SpawnProgress) or Tuning.FinalHallSpawnProgress, .90, .98)
3401: 	for _, progress in ipairs({preferred, .95, .93, .90}) do
3402: 		local candidate = hall.StartPoint:Lerp(hall.EndPoint, progress)
3403: 		candidate = Vector3.new(candidate.X, hall.FloorY, candidate.Z)
3404: 		local nearestDistance = math.huge
3405: 		for _, record in ipairs(records) do
3406: 			nearestDistance = math.min(nearestDistance, planarDistance(candidate, record.Position))
3407: 		end
3408: 		if nearestDistance >= Tuning.SpawnMinimumDistance and spawnVolumeFits(candidate, overlap) then
3409: 			position = candidate
3410: 			break
3411: 		end
3412: 	end
3413: 	if not position then return nil end
3414: 	-- Face a runner in the exit lane before the first authoritative chase tick.
3415: 	table.sort(records, function(a, b)
3416: 		local aInHall = insideFinalHall({Manifest=manifest}, a.Position)
3417: 		local bInHall = insideFinalHall({Manifest=manifest}, b.Position)
3418: 		if aInHall ~= bInHall then return aInHall end
3419: 		local aDistance = planarDistance(position, a.Position)
3420: 		local bDistance = planarDistance(position, b.Position)
3421: 		if math.abs(aDistance - bDistance) > .001 then return aDistance < bDistance end
3422: 		return a.Player.UserId < b.Player.UserId
3423: 	end)
3424: 	local anchor = records[1]
3425: 	local centroid = Vector3.zero
3426: 	local nearestDistance = math.huge
3427: 	for _, record in ipairs(records) do
3428: 		centroid += record.Position
3429: 		nearestDistance = math.min(nearestDistance, planarDistance(position, record.Position))
3430: 	end
3431: 	centroid /= #records
3432: 	return {
3433: 		Position = position,
3434: 		Anchor = anchor,
3435: 		GroupSize = #records,
3436: 		Centroid = centroid,
3437: 		Cycle = cycle,
3438: 		RoomId = nearestRoomId(position),
3439: 		Random = random,
3440: 		-- Volume clearance is real; route reachability is still proved by the existing sweep.
3441: 		SpawnClearanceValidated = true,
3442: 		Visibility = spawnVisibilityCount(position, records),
3443: 		NearestDistance = nearestDistance,
3444: 		AnchorDistance = planarDistance(position, anchor.Position),
3445: 		FinalHallChase = true,
3446: 	}
3447: end
3448: 
3449: local function chooseBlackoutSpawn(manifest: any, generation: number): any?
3450: 	if workspace:GetAttribute("Level3FinalHallChaseActive") == true then
3451: 		return chooseFinalHallSpawn(manifest, generation)
3452: 	end
3453: 	local records = eligibleSpawnPlayers()
3454: 	if #records == 0 then return nil end
3455: 	local state = stateFolder()
3456: 	local cycle = math.floor(tonumber(state:GetAttribute("Level3_RoomSongCycle")) or 0)

-- excerpt 3584-3619
3584: 	local boundingCFrame, boundingSize = model:GetBoundingBox()
3585: 	local pivot = model:GetPivot()
3586: 	local groundOffset = pivot.Position.Y - (boundingCFrame.Position.Y - boundingSize.Y * .5)
3587: 	local rootPosition = spawnPosition + Vector3.new(0, groundOffset, 0)
3588: 	local target = Vector3.new(facePosition.X, rootPosition.Y, facePosition.Z)
3589: 	model:PivotTo(CFrame.lookAt(rootPosition, target))
3590: 	model.Parent = manifest.MallManagerRuntime
3591: 	CollectionService:AddTag(model, "Level3HostileEntity")
3592: 	return model, root, groundOffset
3593: end
3594: 
3595: function Controller.Start(manifest: any, generation: number)
3596: 	Controller.Stop()
3597: 	Tuning = resolveTuning()
3598: 	assert(type(manifest) == "table" and manifest.World and manifest.World:IsA("Model")
3599: 		and manifest.World.Parent == workspace, "Mall Manager requires a live Level 3 manifest")
3600: 	assert(manifest.World:GetAttribute("Level3_Generation") == generation,
3601: 		"Mall Manager generation does not match the Level 3 world")
3602: 	assert(manifest.MallManagerSpawn and manifest.MallManagerSpawn:IsA("BasePart")
3603: 		and manifest.MallManagerSpawn:IsDescendantOf(manifest.World),
3604: 		"Level 3 manifest is missing Mall Manager Spawn")
3605: 	assert(manifest.MallManagerRuntime and manifest.MallManagerRuntime:IsA("Folder")
3606: 		and manifest.MallManagerRuntime:IsDescendantOf(manifest.World),
3607: 		"Level 3 manifest is missing Mall Manager Runtime")
3608: 	activeLayout = if type(manifest.Layout) == "table" then manifest.Layout else nil
3609: 	if workspace:GetAttribute("Level3MallManagerHuntActive") ~= true then
3610: 		activeLayout = nil
3611: 		resetPublishedState()
3612: 		return nil
3613: 	end
3614: 	local spawnData = chooseBlackoutSpawn(manifest, generation)
3615: 	if not spawnData then
3616: 		activeLayout = nil
3617: 		resetPublishedState()
3618: 		warn("[Level 3 Mall Manager] hunt edge has no eligible living player spawn yet")
3619: 		return nil

-- excerpt 3662-3671
3662: 		RecentPatrolRooms = {spawnData.RoomId},
3663: 		Random = spawnData.Random,
3664: 		SpawnAnchor = spawnData.Anchor.Player,
3665: 		SpawnGroupSize = spawnData.GroupSize,
3666: 		SpawnCycle = spawnData.Cycle,
3667: 		SpawnRoomId = spawnData.RoomId,
3668: 		Adjacency = buildAdjacency(),
3669: 		FinalHallChase = spawnData.FinalHallChase == true,
3670: 		FinalGoal = nil,
3671: 		ResolvedFinalGoal = nil,

-- excerpt 3832-3861
3832: 	local function roundChanged()
3833: 		if not liveSession(session) then return end
3834: 		if workspace:GetAttribute("RoundActive") == true
3835: 			and workspace:GetAttribute("SelectedLevel") == 3
3836: 			and workspace:GetAttribute("Level3MallManagerHuntActive") == true then
3837: 			session.ActivatedAt = os.clock() + Tuning.SpawnGraceSeconds
3838: 			session.LastProgressAt = os.clock()
3839: 			session.LastGenuineProgressAt = os.clock()
3840: 			session.ProgressObjectiveKey = nil
3841: 			session.ProgressBestDistance = math.huge
3842: 			session.ProgressCreditedDistance = math.huge
3843: 			publishState(session, "AWAKENING")
3844: 		else
3845: 			session.ActivatedAt = math.huge
3846: 			dormant(session, "WAITING")
3847: 		end
3848: 	end
3849: 	table.insert(session.Connections, workspace:GetAttributeChangedSignal("RoundActive"):Connect(roundChanged))
3850: 	table.insert(session.Connections, workspace:GetAttributeChangedSignal("EntityPaused"):Connect(function()
3851: 		if workspace:GetAttribute("EntityPaused") == true then dormant(session, "PAUSED") end
3852: 	end))
3853: 	local function refreshBlackoutProfile()
3854: 		applyBlackout(session, blackoutProfileRequested())
3855: 	end
3856: 	table.insert(session.Connections, workspace:GetAttributeChangedSignal("Level3BlackoutActive"):Connect(refreshBlackoutProfile))
3857: 	table.insert(session.Connections,
3858: 		workspace:GetAttributeChangedSignal("Level3FinalHallChaseActive"):Connect(refreshBlackoutProfile))
3859: 	table.insert(session.Connections, PlayerProtection.Activated:Connect(function(player, character)
3860: 		forgetProtectedPlayer(session, player, character)
3861: 	end))

-- excerpt 3885-3942
3885: 	table.insert(session.Connections, RunService.Heartbeat:Connect(function(dt)
3886: 		if not liveSession(session) then return end
3887: 		local now = os.clock()
3888: 		refreshNavigationFilters(session)
3889: 		-- Also fence deferred activation delivery before the table-check early return.
3890: 		forgetProtectedPlayer(session, session.Target, session.Target and session.Target.Character)
3891: 		forgetProtectedPlayer(session, session.LastKnownPlayer, session.LastKnownPlayer and session.LastKnownPlayer.Character)
3892: 		forgetProtectedPlayer(session, session.AttackPlayer, session.AttackCharacter)
3893: 		if updateTableCheck(session, now) then
3894: 			-- Kneeling at a table. Speed is 0 for TABLE_CHECK so updateMovement
3895: 			-- holds position and parks the walk cycle; perception and attacks are
3896: 			-- skipped entirely for the reaction window.
3897: 			updateMovement(session, dt, now)
3898: 			publishMotion(session, dt, false)
3899: 			updateFootsteps(session)
3900: 			return
3901: 		end
3902: 		session.ThinkAccumulator += dt
3903: 		local thinkInterval = if session.Blackout
3904: 			then Tuning.BlackoutThinkIntervalSeconds else Tuning.ThinkIntervalSeconds
3905: 		if session.ThinkAccumulator >= thinkInterval then
3906: 			local senseDt = session.ThinkAccumulator
3907: 			session.ThinkAccumulator = 0
3908: 			updateBrain(session, now, senseDt)
3909: 		end
3910: 		if validRound(session) and session.State == "CHASE" and session.Target then
3911: 			beginAttack(session, session.Target)
3912: 		end
3913: 		updateMovement(session, dt, now)
3914: 		publishMotion(session, dt, false)
3915: 		updateFootsteps(session)
3916: 	end))
3917: 
3918: 	applyBlackout(session, blackoutProfileRequested())
3919: 	roundChanged()
3920: 	-- Acquire before the first Heartbeat so the spawned Manager already exposes
3921: 	-- its target and begins the nearest-player route on the reveal frame.
3922: 	if session.Blackout and validRound(session) then
3923: 		trackNearestBlackoutPlayer(session, os.clock())
3924: 	else
3925: 		local seedPlayer, seedRoot = nearestLivingPlayer(session)
3926: 		if seedPlayer and seedRoot then
3927: 			session.LastKnownPosition = flat(seedRoot.Position, floorY)
3928: 			session.LastKnownPlayer = seedPlayer
3929: 			session.LastKnownCharacter = seedPlayer.Character
3930: 			session.LastSenseAt = os.clock()
3931: 			setGoal(session, session.LastKnownPosition, true)
3932: 		else
3933: 			session.LastKnownPosition = nil
3934: 			session.LastKnownPlayer = nil
3935: 			session.LastKnownCharacter = nil
3936: 			session.LastSenseAt = -math.huge
3937: 		end
3938: 	end
3939: 	publishMotion(session, 0, true)
3940: 	print(string.format("[Level 3 Mall Manager] hunt spawn %.1f studs from nearest player; group %d, room %s, blackout chase %.1f",
3941: 		spawnDistance, spawnData.GroupSize, spawnData.RoomId, Tuning.Blackout.ChaseSpeed))
3942: 	return session
```

### Objective: ServerScriptService/Level 3 Systems/Level 3 Objective Controller.ModuleScript.lua SHA256 5474b27128d9d48deaa5503f4e340b138a06596534d87bff0a21d695ad2f39e8
```lua

-- excerpt 97-189
97: local function liveSession(session: AnyTable): boolean
98: 	local manifest = session.Manifest
99: 	local world = manifest and manifest.World
100: 	return activeSession == session
101: 		and world ~= nil
102: 		and world:IsA("Model")
103: 		and world.Parent ~= nil
104: 		and world:GetAttribute("Level3_Generation") == session.Generation
105: end
106: 
107: local function validSession(session: AnyTable): boolean
108: 	return liveSession(session)
109: 		and workspace:GetAttribute("SelectedLevel") == 3
110: 		and workspace:GetAttribute("RoundActive") == true
111: end
112: 
113: local function livingCharacter(player: Player): (Model?, Humanoid?, BasePart?)
114: 	local character = player.Character
115: 	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
116: 	local root = character and character:FindFirstChild("HumanoidRootPart")
117: 	if not character or not character.Parent or not humanoid or humanoid.Health <= 0
118: 		or not root or not root:IsA("BasePart") then
119: 		return nil, nil, nil
120: 	end
121: 	return character, humanoid, root
122: end
123: 
124: local function validPlayer(player: Player, session: AnyTable): boolean
125: 	return validSession(session)
126: 		and player.Parent == Players
127: 		and player:GetAttribute("InRound") == true
128: 		and player:GetAttribute("Escaped") ~= true
129: end
130: 
131: local function updateFinalHallChase(session: AnyTable)
132: 	if not session.ExitUnlocked or session.FinalHallChaseTriggered
133: 		or session.State:GetAttribute("Level3_RoomSongPhase") ~= "DONE" then
134: 		return
135: 	end
136: 	local hall = session.Manifest.FinalHall
137: 	if type(hall) ~= "table" or not hall.Model or not hall.Model.Parent then return end
138: 	local horizontalForward = Vector3.new(hall.Forward.X, 0, hall.Forward.Z)
139: 	if horizontalForward.Magnitude <= .001 then return end
140: 	horizontalForward = horizontalForward.Unit
141: 	local eligibleCount = 0
142: 	local crossedCount = 0
143: 	for _, player in ipairs(Players:GetPlayers()) do
144: 		if validPlayer(player, session) then
145: 			local character, _, root = livingCharacter(player)
146: 			if character and root then
147: 				eligibleCount += 1
148: 				if session.FinalHallCrossed[player] ~= character then
149: 					local offset = Vector3.new(
150: 						root.Position.X - hall.StartPoint.X, 0, root.Position.Z - hall.StartPoint.Z)
151: 					local along = offset:Dot(horizontalForward)
152: 					local lateral = (offset - horizontalForward * along).Magnitude
153: 					-- The first living survivor must pass strictly beyond 50% of this hall.
154: 					-- Character-scoped latching keeps deaths/rejoins from carrying a stale crossing.
155: 					local entryProgress = hall.Length * (hall.HalfwayProgress
156: 						or Configuration.Layout.FinalHallHalfwayProgress or .50)
157: 					local insideHallWidth = lateral <= hall.Width * .5 + 2.5
158: 					local insideHallHeight = math.abs(root.Position.Y - hall.FloorY) <= hall.Height + 6
159: 					if along > entryProgress and along <= hall.Length + 2.5
160: 						and insideHallWidth and insideHallHeight then
161: 						session.FinalHallCrossed[player] = character
162: 					end
163: 				end
164: 				if session.FinalHallCrossed[player] == character then crossedCount += 1 end
165: 			end
166: 		end
167: 	end
168: 	session.FinalHallEligibleCount = eligibleCount
169: 	session.FinalHallCrossedCount = crossedCount
170: 	session.State:SetAttribute("Level3_FinalHallEligibleCount", eligibleCount)
171: 	session.State:SetAttribute("Level3_FinalHallCrossedCount", crossedCount)
172: 	session.Manifest.World:SetAttribute("Level3_FinalHallEligibleCount", eligibleCount)
173: 	session.Manifest.World:SetAttribute("Level3_FinalHallCrossedCount", crossedCount)
174: 	workspace:SetAttribute("Level3FinalHallEligibleCount", eligibleCount)
175: 	workspace:SetAttribute("Level3FinalHallCrossedCount", crossedCount)
176: 	if eligibleCount == 0 or crossedCount == 0 then return end
177: 
178: 	session.FinalHallChaseTriggered = true
179: 	session.State:SetAttribute("Level3_FinalHallChaseTriggered", true)
180: 	session.State:SetAttribute("Level3_FinalHallChaseActive", true)
181: 	session.State:SetAttribute("Level3_MallManagerHuntActive", true)
182: 	session.Manifest.World:SetAttribute("Level3_FinalHallChaseTriggered", true)
183: 	session.Manifest.World:SetAttribute("Level3_FinalHallChaseActive", true)
184: 	workspace:SetAttribute("Level3FinalHallChaseTriggered", true)
185: 	-- This must precede HuntActive so the Manager's synchronous Start selects the
186: 	-- far-end finale spawn rather than a normal hidden random-room spawn.
187: 	workspace:SetAttribute("Level3FinalHallChaseActive", true)
188: 	workspace:SetAttribute("Level3MallManagerHuntActive", true)
189: end

-- excerpt 1200-1259
1200: 			if object:IsA("BasePart") and (object.Name == "Final Exit Energon Rail" or object.Name == "Final Exit Lock Core") then
1201: 				playTween(session, object, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
1202: 					Transparency = 0.06,
1203: 				})
1204: 			elseif object:IsA("PointLight") and object.Name == "Final Exit Energon Spill" then
1205: 				object.Enabled = false
1206: 			end
1207: 		end
1208: 	end
1209: 
1210: 	firePayload(session, {
1211: 		Type = "ExitUnlocked",
1212: 		Progress = session.ModuleCount,
1213: 		Goal = session.ModuleGoal,
1214: 		ExitPosition = session.Manifest.ExitPosition,
1215: 	})
1216: 	fireSound(session, "ExitUnlocked", session.Manifest.ExitPosition, nil)
1217: end
1218: 
1219: local function collectModule(session: AnyTable, module: AnyTable, player: Player)
1220: 	local record = session.CDRecords[module.Index]
1221: 	if not record then return end
1222: 	collectRecord(session, record, player, module.Prompt, module.Model)
1223: end
1224: 
1225: local function escapePlayer(session: AnyTable, player: Player)
1226: 	if not session.ExitUnlocked or session.Escaping[player] then return end
1227: 	if not validPlayer(player, session) then return end
1228: 	local trigger = session.Manifest.EscapeTrigger
1229: 	if not trigger or not trigger.Parent or not trigger.CanTouch
1230: 		or not trigger:IsDescendantOf(session.Manifest.World) then return end
1231: 	local character, _, root = livingCharacter(player)
1232: 	if not character or not root then return end
1233: 	-- A client-reported limb touch is only a wake-up. The server must see the
1234: 	-- living character's root inside this doorway, not merely near the exit.
1235: 	local offset = trigger.CFrame:PointToObjectSpace(root.Position)
1236: 	local halfSize = trigger.Size * .5
1237: 	if not (math.abs(offset.X) <= halfSize.X and math.abs(offset.Y) <= halfSize.Y
1238: 		and math.abs(offset.Z) <= halfSize.Z) then return end
1239: 
1240: 	session.Escaping[player] = true
1241: 	session.EscapeOrdinal = (session.EscapeOrdinal or 0) + 1
1242: 	player:SetAttribute("Escaped", true)
1243: 	root.AssemblyLinearVelocity = Vector3.zero
1244: 	root.AssemblyAngularVelocity = Vector3.zero
1245: 	local slots = {
1246: 		Vector3.new(-6, 3, -4), Vector3.new(0, 3, -4), Vector3.new(6, 3, -4),
1247: 		Vector3.new(-6, 3, 4), Vector3.new(0, 3, 4), Vector3.new(6, 3, 4),
1248: 	}
1249: 	local slot = slots[((session.EscapeOrdinal - 1) % #slots) + 1]
1250: 	character:PivotTo(session.Manifest.ExitSafeSpawn.CFrame * CFrame.new(slot))
1251: 	fireSound(session, "Escape", session.Manifest.ExitPosition, player)
1252: 	fireEscapeStatus(player)
1253: end
1254: 
1255: local function validateManifest(manifest: AnyTable, generation: number)
1256: 	assert(type(manifest) == "table", "Level 3 objective manifest must be a table")
1257: 	assert(type(generation) == "number" and generation == generation,
1258: 		"Level 3 objective generation must be a valid number")
1259: 	assert(manifest.World and manifest.World:IsA("Model") and manifest.World.Parent,

-- excerpt 1347-1367
1347: 	assert(manifest.ExitSafeSpawn and manifest.ExitSafeSpawn:IsA("BasePart")
1348: 		and manifest.ExitSafeSpawn:IsDescendantOf(manifest.World),
1349: 		"Level 3 exit safe spawn is missing from the generated world")
1350: 	assert(typeof(manifest.ExitPosition) == "Vector3", "Level 3 exit position must be a Vector3")
1351: 	local finalHall = manifest.FinalHall
1352: 	assert(type(finalHall) == "table" and finalHall.Model and finalHall.Model:IsA("Model")
1353: 		and finalHall.Model:IsDescendantOf(manifest.World),
1354: 		"Level 3 objective manifest is missing its final hall")
1355: 	assert(typeof(finalHall.StartPoint) == "Vector3" and typeof(finalHall.EndPoint) == "Vector3"
1356: 		and typeof(finalHall.Forward) == "Vector3" and type(finalHall.Length) == "number"
1357: 		and finalHall.Length >= Configuration.Layout.ExitCorridorLength - .1,
1358: 		"Level 3 final hall geometry is invalid")
1359: 	assert(finalHall.HalfwayMarker and finalHall.HalfwayMarker:IsA("BasePart")
1360: 		and finalHall.HalfwayMarker:GetAttribute("Level3_FinalHallHalfway") == true,
1361: 		"Level 3 final hall halfway marker is missing")
1362: 	assert(finalHall.SpawnMarker and finalHall.SpawnMarker:IsA("BasePart")
1363: 		and finalHall.SpawnMarker:GetAttribute("Level3_MallManagerFinaleSpawn") == true,
1364: 		"Level 3 final hall Manager spawn marker is missing")
1365: end
1366: 
1367: local function scheduleIntro(session: AnyTable)

-- excerpt 1420-1437
1420: 		HeldCount = 0,
1421: 		DroppedCount = 0,
1422: 		ModuleCount = 0,
1423: 		ModuleGoal = #manifest.Modules,
1424: 		ExitUnlocked = false,
1425: 		ExitGuideStartRoom = "",
1426: 		ExitGuideCount = 0,
1427: 		FinalHallCrossed = {},
1428: 		FinalHallChaseTriggered = false,
1429: 		FinalHallEligibleCount = 0,
1430: 		FinalHallCrossedCount = 0,
1431: 		FinalHallAccumulator = 0,
1432: 		Escaping = {},
1433: 		EscapeOrdinal = 0,
1434: 		IntroScheduled = false,
1435: 	}
1436: 	activeSession = session
1437: 

-- excerpt 1465-1489
1465: 	for _, player in ipairs(Players:GetPlayers()) do bindPlayerLifecycle(session, player) end
1466: 	table.insert(session.Connections, Players.PlayerAdded:Connect(function(player)
1467: 		bindPlayerLifecycle(session, player)
1468: 	end))
1469: 	table.insert(session.Connections, Players.PlayerRemoving:Connect(function(player)
1470: 		transferLeavingCDs(session, player)
1471: 		session.FinalHallCrossed[player] = nil
1472: 		session.LastKnownPositions[player] = nil
1473: 		session.LastGroundPositions[player] = nil
1474: 	end))
1475: 	table.insert(session.Connections, RunService.Heartbeat:Connect(function(dt)
1476: 		if not liveSession(session) then return end
1477: 		session.FinalHallAccumulator += dt
1478: 		if session.FinalHallAccumulator < .10 then return end
1479: 		session.FinalHallAccumulator = 0
1480: 		rememberCarriedPositions(session)
1481: 		updatePlayerRooms(session)
1482: 		updateFinalHallChase(session)
1483: 		-- Touch events can be missed during streaming or when unlock happens
1484: 		-- while a player is already at the door. The solid door holds runners
1485: 		-- inside this small detector until this same server check accepts them.
1486: 		if session.ExitUnlocked then
1487: 			for _, player in ipairs(Players:GetPlayers()) do escapePlayer(session, player) end
1488: 		end
1489: 	end))

-- excerpt 1490-1510
1490: 
1491: 	session.State:SetAttribute("Level3_FinalHallEligibleCount", 0)
1492: 	session.State:SetAttribute("Level3_FinalHallCrossedCount", 0)
1493: 	session.State:SetAttribute("Level3_FinalHallChaseTriggered", false)
1494: 	session.State:SetAttribute("Level3_FinalHallChaseActive", false)
1495: 	manifest.World:SetAttribute("Level3_FinalHallEligibleCount", 0)
1496: 	manifest.World:SetAttribute("Level3_FinalHallCrossedCount", 0)
1497: 	manifest.World:SetAttribute("Level3_FinalHallChaseTriggered", false)
1498: 	manifest.World:SetAttribute("Level3_FinalHallChaseActive", false)
1499: 	workspace:SetAttribute("Level3FinalHallEligibleCount", 0)
1500: 	workspace:SetAttribute("Level3FinalHallCrossedCount", 0)
1501: 	workspace:SetAttribute("Level3FinalHallChaseTriggered", false)
1502: 	workspace:SetAttribute("Level3FinalHallChaseActive", false)
1503: 	workspace:SetAttribute("Level3CompletionDimStartedAtServerTime", 0)
1504: 	workspace:SetAttribute("Level3CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
1505: 	portal.Model:SetAttribute("Level3_ExitUnlocked", false)
1506: 	portal.Wall.CanCollide = true
1507: 	portal.Wall.CanTouch = false
1508: 	portal.Wall.CanQuery = true
1509: 	for _, framePart in ipairs(portal.FrameParts) do framePart.Transparency = 1 end
1510: 	if portal.Light then portal.Light.Enabled = false end

-- excerpt 1611-1656
1611: 	if session.State and session.State.Parent then
1612: 		session.State:SetAttribute("Level3_ModuleProgress", 0)
1613: 		session.State:SetAttribute("Level3_ModuleGoal", 0)
1614: 		session.State:SetAttribute("Level3_CDCollectedProgress", 0)
1615: 		session.State:SetAttribute("Level3_CDInsertedProgress", 0)
1616: 		session.State:SetAttribute("Level3_CDCarriedCount", 0)
1617: 		session.State:SetAttribute("Level3_CDDroppedCount", 0)
1618: 		session.State:SetAttribute("Level3_ExitUnlocked", false)
1619: 		session.State:SetAttribute("Level3_CompletionSongStartServerTime", 0)
1620: 		session.State:SetAttribute("Level3_CompletionDimStartedAtServerTime", 0)
1621: 		session.State:SetAttribute("Level3_CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
1622: 		session.State:SetAttribute("Level3_FinalHallEligibleCount", 0)
1623: 		session.State:SetAttribute("Level3_FinalHallCrossedCount", 0)
1624: 		session.State:SetAttribute("Level3_FinalHallChaseTriggered", false)
1625: 		session.State:SetAttribute("Level3_FinalHallChaseActive", false)
1626: 		session.State:SetAttribute("Level3_MallManagerHuntActive", false)
1627: 		session.State:SetAttribute("Level3_ExitGuideActive", false)
1628: 		session.State:SetAttribute("Level3_ExitGuideStartRoom", "")
1629: 		session.State:SetAttribute("Level3_ExitGuideLampCount", 0)
1630: 		session.State:SetAttribute("Level3_ExitPosition", nil)
1631: 		session.State:SetAttribute("Level3_Phase", "STOPPED")
1632: 		session.State:SetAttribute("Level3_EntryRoomId", "")
1633: 		session.State:SetAttribute("Level3_FirstCDRoomId", "")
1634: 		-- L3_CD_BEACONS_20260921: a stale position outlives the round otherwise,
1635: 		-- and the reader would keep a needle on a disc that no longer exists.
1636: 		for index in pairs(session.CDRecords or {}) do
1637: 			session.State:SetAttribute(string.format("Level3_CD%dState", index), "")
1638: 			session.State:SetAttribute(string.format("Level3_CD%dRoom", index), "")
1639: 			session.State:SetAttribute(string.format("Level3_CD%dPosition", index), nil)
1640: 		end
1641: 	end
1642: 	workspace:SetAttribute("Level3Modules", 0)
1643: 	workspace:SetAttribute("Level3ModuleGoal", 0)
1644: 	workspace:SetAttribute("Level3CDsCollected", 0)
1645: 	workspace:SetAttribute("Level3CDsCarried", 0)
1646: 	workspace:SetAttribute("Level3CDsDropped", 0)
1647: 	workspace:SetAttribute("Level3ExitUnlocked", false)
1648: 	workspace:SetAttribute("Level3ExitGuideActive", false)
1649: 	workspace:SetAttribute("Level3CompletionDimStartedAtServerTime", 0)
1650: 	workspace:SetAttribute("Level3CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
1651: 	workspace:SetAttribute("Level3FinalHallEligibleCount", 0)
1652: 	workspace:SetAttribute("Level3FinalHallCrossedCount", 0)
1653: 	workspace:SetAttribute("Level3FinalHallChaseTriggered", false)
1654: 	workspace:SetAttribute("Level3FinalHallChaseActive", false)
1655: 	workspace:SetAttribute("Level3MallManagerHuntActive", false)
1656: end
```

### Reader: tools/level3_promotion_20261002/gameplay_boards/capture-baseline/StarterPlayer.StarterPlayerScripts.Level 3 Reader Client.luau SHA256 0000562193cc57aa5ae2f7a659e5dff7b35773e28764e6bd83aad1a8b083281b
```lua

-- excerpt 13-38
13: local ContextActionService = game:GetService("ContextActionService")
14: local TextService = game:GetService("TextService")
15: 
16: local player = Players.LocalPlayer
17: 
18: local LEVEL = 3
19: local WORLD_NAME = "Level 3 Generated World"
20: local STATE_FOLDER_NAME = "Level 3 State"
21: local REMOTES_FOLDER_NAME = "Level 3 Remotes"
22: local CLIENT_EVENT_NAME = "ClientEvent"
23: 
24: local UPDATE_INTERVAL = 0.10
25: local MAXIMUM_RANGE = 650
26: local ACCURACY_DEGREES = {155, 105, 64, 36, 18, 5}
27: local DISTANCE_NOISE = {0.60, 0.42, 0.27, 0.15, 0.07, 0.0}
28: -- Full bars inside a room, one bar at roughly the far side of a district: the
29: -- CD bar is plain proximity, not the exit's fogged signal.
30: local CD_SIGNAL_RANGE = 260
31: -- radians/second on a sine, so ~0.8Hz -- a text pulse, never a scene flash, and
32: -- it never exceeds .40 transparency so the row stays legible at its dimmest.
33: local ROOM_BLINK_RATE = 5.0
34: 
35: -- UI_STYLE_20260915 (Trello #98). The panel surface, the body/muted/caution
36: -- faces and the chrome now come from the shared tokens taken off Level 1's
37: -- Objectives panel and the Mission Brief card. ENERGON stays local: it is the
38: -- reader's own instrument colour and it carries signal strength.

-- excerpt 668-765
668: 	if camera then
669: 		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
670: 	end
671: 	applyLayout()
672: end
673: trackReaderConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
674: bindCamera()
675: 
676: local function stateFolder(): Folder?
677: 	local folder = ReplicatedStorage:FindFirstChild(STATE_FOLDER_NAME)
678: 	return if folder and folder:IsA("Folder") then folder else nil
679: end
680: 
681: local function stateAttribute(name: string, workspaceMirror: string?): any
682: 	local state = stateFolder()
683: 	local value = state and state:GetAttribute(name)
684: 	if value == nil and workspaceMirror then value = workspace:GetAttribute(workspaceMirror) end
685: 	return value
686: end
687: 
688: local function numberAttribute(name: string, workspaceMirror: string?, fallback: number): number
689: 	local value = stateAttribute(name, workspaceMirror)
690: 	return if type(value) == "number" then value else fallback
691: end
692: 
693: -- SPECTATE_UI_PARITY_20260914 -- whose reader this panel is drawing.
694: --
695: -- While spectating, the camera sits on the WATCHED player's head
696: -- (SpectateController publishes them on the client-local `Spectating` /
697: -- `SpectateTargetUserId` attributes), so the needle, the signal bars and the
698: -- hiding blackout all have to come from THEIR body: a spectator must read the
699: -- panel the player they are watching is reading. `Level3_Hiding` is set by the
700: -- server on the player (Level 3 Hiding Controller), so it replicates and can be
701: -- read for anyone. Falls back to yourself whenever there is no living subject,
702: -- which is exactly the pre-spectate behaviour.
703: -- A subject only counts while they are a living, in-round, non-escaped
704: -- participant, i.e. exactly the players SpectateController is willing to pick.
705: local function spectateSubject(): Player?
706: 	if player:GetAttribute("Spectating") ~= true then return nil end
707: 	local userId = player:GetAttribute("SpectateTargetUserId")
708: 	local watched = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
709: 	if not watched or watched:GetAttribute("InRound") ~= true
710: 		or watched:GetAttribute("Escaped") == true then return nil end
711: 	local character = watched.Character
712: 	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
713: 	if humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") then
714: 		return watched
715: 	end
716: 	return nil
717: end
718: 
719: local function readerSubject(): Player
720: 	return spectateSubject() or player
721: end
722: 
723: -- SPECTATE_UI_PARITY_20260914: an ESCAPED spectator used to fail this gate on
724: -- their own `Escaped` and lose the panel entirely while watching a living
725: -- teammate whose panel is the whole point. Being a spectator with a valid
726: -- subject is now its own way in; the world condition (level) still applies.
727: local function isActive(): boolean
728: 	local levelActive = workspace:GetAttribute("SelectedLevel") == LEVEL
729: 		and ((player:GetAttribute("InRound") == true
730: 				and player:GetAttribute("Escaped") ~= true)
731: 			or spectateSubject() ~= nil)
732: 	if RunService:IsStudio()
733: 		and player:GetAttribute("UIRegressionForceLevel3Reader") == true then
734: 		levelActive = true
735: 	end
736: 	return levelActive
737: 		and player:GetAttribute("ZyntraDispatchClientActive") ~= true
738: 		and readerSubject():GetAttribute("Level3_Hiding") ~= true
739: 		-- A screen-owning modal takes the reader with it. The panel is a
740: 		-- TextButton on touch, so leaving it up under an open terminal would put
741: 		-- a live control beneath a modal.
742: 		and not UIDevice.ScreenOwningModalOpen()
743: end
744: 
745: local function currentWorld(): Model?
746: 	local world = workspace:FindFirstChild(WORLD_NAME)
747: 	return if world and world:IsA("Model") then world else nil
748: end
749: 
750: local function exitPosition(): Vector3?
751: 	local value = stateAttribute("Level3_ExitPosition", nil)
752: 	if typeof(value) == "Vector3" then return value :: Vector3 end
753: 	return nil
754: end
755: 
756: local function generationMatches(payload: {[any]: any}): boolean
757: 	local payloadGeneration = payload.Generation
758: 	if type(payloadGeneration) ~= "number" then return true end
759: 	local world = currentWorld()
760: 	local liveGeneration = world and world:GetAttribute("Level3_Generation")
761: 	return type(liveGeneration) ~= "number" or liveGeneration == payloadGeneration
762: end
763: 
764: local toastSerial = 0
765: local function cleanText(value: any, fallback: string, maximum: number): string

-- excerpt 868-1060
868: -- The reader points at the nearest disc a player can still PICK UP and says
869: -- whether one of them shares the room. Both answers come from server state
870: -- (Level3_CD<n>State/Room/Position on the Level 3 State folder, and
871: -- Level3_Room on the subject Player), never from the workspace: the CD model
872: -- streams out at range and a disc dropped across the mall may never have
873: -- replicated here at all. A CARRIED or INSERTED disc publishes no position, so
874: -- it cannot be pointed at.
875: --
876: -- The selection itself is this pure function over plain numbers -- no
877: -- instances, no Vector3 -- so tools/tests/test_level3_first_cd.py runs the very
878: -- code the client runs. Same-room is decided by ROOM ID, so a disc one wall
879: -- away in the adjacent room never lights the indicator however close it is.
880: local function chooseCDTarget(beacons: {any}, fromX: number, fromZ: number,
881: 	subjectRoom: string): (any, number, boolean)
882: 	local nearest, nearestDistance = nil, math.huge
883: 	local sameRoom = false
884: 	for _, beacon in ipairs(beacons) do
885: 		local dx, dz = beacon.X - fromX, beacon.Z - fromZ
886: 		local distance = math.sqrt(dx * dx + dz * dz)
887: 		if distance < nearestDistance then
888: 			nearest = beacon
889: 			nearestDistance = distance
890: 		end
891: 		if subjectRoom ~= "" and beacon.Room == subjectRoom then sameRoom = true end
892: 	end
893: 	return nearest, nearestDistance, sameRoom
894: end
895: 
896: local function pickableCDs(goal: number): {any}
897: 	local beacons = {}
898: 	for index = 1, goal do
899: 		local state = stateAttribute(string.format("Level3_CD%dState", index), nil)
900: 		local position = stateAttribute(string.format("Level3_CD%dPosition", index), nil)
901: 		if (state == "WORLD" or state == "DROPPED") and typeof(position) == "Vector3" then
902: 			local room = stateAttribute(string.format("Level3_CD%dRoom", index), nil)
903: 			table.insert(beacons, {
904: 				Index = index,
905: 				X = position.X,
906: 				Z = position.Z,
907: 				Room = if type(room) == "string" then room else "",
908: 			})
909: 		end
910: 	end
911: 	return beacons
912: end
913: -- L3_CD_READER_TARGET_END_20260921
914: 
915: local function signedPlanarAngle(forward: Vector3, target: Vector3): number
916: 	local a = Vector3.new(forward.X, 0, forward.Z)
917: 	local b = Vector3.new(target.X, 0, target.Z)
918: 	if a.Magnitude < 0.001 or b.Magnitude < 0.001 then return 0 end
919: 	a = a.Unit
920: 	b = b.Unit
921: 	return math.atan2(a.X * b.Z - a.Z * b.X, math.clamp(a:Dot(b), -1, 1))
922: end
923: 
924: local function updateReader(dt: number)
925: 	local active = isActive()
926: 	local hidden = readerHidden
927: 	if RunService:IsStudio() then
928: 		local forced = player:GetAttribute("UIRegressionForceReaderHidden")
929: 		if type(forced) == "boolean" then hidden = forced end
930: 	end
931: 	-- The two states are mutually exclusive and neither draws under a toast.
932: 	-- SetInteractive rather than a bare Visible write: a TextButton left Active
933: 	-- keeps taking taps through a transparent background, and BOTH of these are
934: 	-- buttons now -- the restore chip is transparent apart from its 30px mark,
935: 	-- and the panel is the control that hides itself.
936: 	local touch = UIDevice.IsTouch()
937: 	UIDevice.SetInteractive(panel, active and not hidden and not toast.Visible)
938: 	-- SetEnabled AFTER SetInteractive, which writes Active = Visible: this is the
939: 	-- correction that keeps the desktop readout inert, so a click at the panel's
940: 	-- corner still reaches the world behind it.
941: 	UIDevice.SetEnabled(panel, panel.Visible and touch)
942: 	-- `and touch` is the whole desktop fix here: on a mouse device the hidden
943: 	-- state draws nothing (C_READER_DESKTOP_CHIP_20260830). Touch is unchanged --
944: 	-- panel and chip remain mutually exclusive and neither draws under a toast.
945: 	UIDevice.SetInteractive(restoreButton,
946: 		touch and active and hidden and not toast.Visible)
947: 	if not active then
948: 		toastSerial += 1
949: 		toast.Visible = false
950: 		return
951: 	end
952: 
953: 	local goal = math.clamp(math.floor(numberAttribute("Level3_ModuleGoal", "Level3ModuleGoal", 5)), 1, 12)
954: 	local progress = math.clamp(math.floor(numberAttribute("Level3_ModuleProgress", "Level3Modules", 0)), 0, goal)
955: 	local index = math.clamp(progress + 1, 1, #ACCURACY_DEGREES)
956: 	local cells: {string} = {}
957: 	for cell = 1, goal do cells[cell] = if cell <= progress then "■" else "□" end
958: 	progressLabel.Text = string.format("DISC RELAY [%s]  %d/%d", table.concat(cells), progress, goal)
959: 
960: 	local character = readerSubject().Character
961: 	local root = character and character:FindFirstChild("HumanoidRootPart")
962: 	if not (root and root:IsA("BasePart")) then
963: 		signalLabel.Text = "SIGNAL // NO TRACE"
964: 		signalLabel.TextColor3 = MUTED
965: 		signalLabel.TextTransparency = 0
966: 		return
967: 	end
968: 
969: 	-- A remaining disc outranks the exit. Once every CD has been collected the
970: 	-- panel hands the needle straight back to the exit bearing it always had,
971: 	-- and the DISC RELAY row above keeps saying how many still owe the VCR.
972: 	local beacons = pickableCDs(goal)
973: 	local subjectRoom = readerSubject():GetAttribute("Level3_Room")
974: 	local cd, cdDistance, sameRoom = chooseCDTarget(beacons, root.Position.X, root.Position.Z,
975: 		if type(subjectRoom) == "string" then subjectRoom else "")
976: 	local exit = exitPosition()
977: 	if not cd and not exit then
978: 		title.Text = "> EXIT DOOR READER"
979: 		signalLabel.Text = "SIGNAL // NO TRACE"
980: 		signalLabel.TextColor3 = MUTED
981: 		signalLabel.TextTransparency = 0
982: 		return
983: 	end
984: 	title.Text = if cd then "> CD READER" else "> EXIT DOOR READER"
985: 
986: 	local targetX = if cd then cd.X else (exit :: Vector3).X
987: 	local targetZ = if cd then cd.Z else (exit :: Vector3).Z
988: 	local offset = Vector3.new(targetX - root.Position.X, 0, targetZ - root.Position.Z)
989: 	local distance = if cd then cdDistance else offset.Magnitude
990: 	local camera = workspace.CurrentCamera
991: 	local forward = camera and camera.CFrame.LookVector or root.CFrame.LookVector
992: 	local trueAngle = signedPlanarAngle(forward, offset)
993: 	local time = os.clock()
994: 	local needleTarget, signalTarget
995: 	if cd then
996: 		-- No fog on a CD bearing. The exit needle below lies by design -- up to
997: 		-- ACCURACY_DEGREES[1] = 155 degrees while nothing is inserted -- and that
998: 		-- is the whole reason the opening minutes were a blind search. A disc is
999: 		-- a findable object, so this needle is the true bearing and the bar is
1000: 		-- plain proximity.
1001: 		needleTarget = math.clamp(trueAngle / math.rad(90), -1, 1)
1002: 		signalTarget = 1 - math.clamp(distance / CD_SIGNAL_RANGE, 0, 1)
1003: 	else
1004: 		local angularNoise = math.noise(time * 0.43, progress * 2.71) * math.rad(ACCURACY_DEGREES[index])
1005: 		local noisyAngle = trueAngle + angularNoise
1006: 		needleTarget = math.clamp(noisyAngle / math.rad(90), -1, 1)
1007: 		local facing = math.clamp((math.cos(noisyAngle) + 1) * 0.5, 0, 1)
1008: 		local rangeSignal = 1 - math.clamp(distance / MAXIMUM_RANGE, 0, 1)
1009: 		local distanceJitter = math.noise(time * 0.61, 19 + progress) * DISTANCE_NOISE[index]
1010: 		signalTarget = math.clamp(facing * 0.72 + rangeSignal * 0.28 + distanceJitter, 0, 1)
1011: 	end
1012: 	local response = if cd then 6 else 1.3 + progress * 0.72
1013: 	local alpha = 1 - math.exp(-dt * response)
1014: 	smoothedNeedle += (needleTarget - smoothedNeedle) * alpha
1015: 	smoothedSignal += (signalTarget - smoothedSignal) * alpha
1016: 	needle.Position = UDim2.new(0.5 + smoothedNeedle * 0.43, 0, 0.5, 0)
1017: 
1018: 	local signalBars = math.clamp(math.floor(smoothedSignal * 5 + 0.5), 0, 5)
1019: 	local bars = string.rep("▮", signalBars) .. string.rep("□", 5 - signalBars)
1020: 	local unlocked = stateAttribute("Level3_ExitUnlocked", "Level3ExitUnlocked") == true
1021: 	signalLabel.TextTransparency = 0
1022: 	if cd then
1023: 		if sameRoom then
1024: 			-- EXACTLY this string, and nothing else in the row: it is the one
1025: 			-- signal that says "stop walking and look up". ReduceFlashing takes
1026: 			-- the pulse away and leaves the red at full strength instead of
1027: 			-- dimming it (C_L3_ROOM_BLINK_20260921).
1028: 			signalLabel.Text = "IN THIS ROOM"
1029: 			signalLabel.TextColor3 = DANGER
1030: 			if player:GetAttribute("ReduceFlashing") ~= true then
1031: 				signalLabel.TextTransparency = (math.sin(time * ROOM_BLINK_RATE) + 1) * .5 * .40
1032: 			end
1033: 			panelStroke.Color = DANGER
1034: 		else
1035: 			signalLabel.Text = string.format("CD // %s  %dm", bars, math.floor(distance / 3.571 + 0.5))
1036: 			signalLabel.TextColor3 = ENERGON
1037: 			panelStroke.Color = ENERGON
1038: 		end
1039: 		needle.BackgroundColor3 = if sameRoom then DANGER else ENERGON
1040: 		return
1041: 	end
1042: 	needle.BackgroundColor3 = if unlocked then Color3.fromRGB(128, 255, 222) else ENERGON
1043: 	if unlocked then
1044: 		signalLabel.Text = string.format("SIGNAL // %s  %dm", bars, math.floor(distance / 3.571 + 0.5))
1045: 		signalLabel.TextColor3 = ENERGON
1046: 		panelStroke.Color = ENERGON
1047: 	elseif progress == 0 then
1048: 		signalLabel.Text = "SIGNAL // UNSTABLE"
1049: 		signalLabel.TextColor3 = MUTED
1050: 		panelStroke.Color = Color3.fromRGB(75, 122, 116)
1051: 	elseif progress < math.ceil(goal * 0.6) then
1052: 		signalLabel.Text = "SIGNAL // " .. bars .. "  WEAK"
1053: 		signalLabel.TextColor3 = AMBER
1054: 		panelStroke.Color = Color3.fromRGB(89, 170, 159)
1055: 	else
1056: 		signalLabel.Text = "SIGNAL // " .. bars .. "  CALIBRATING"
1057: 		signalLabel.TextColor3 = TEXT
1058: 		panelStroke.Color = ENERGON
1059: 	end
1060: end

-- excerpt 1172-1230
1172: 		tostring(player:GetAttribute("InRound") == true),
1173: 		tostring(player:GetAttribute("Escaped") == true),
1174: 		tostring(player:GetAttribute("UIRegressionForceLevel3Reader") == true),
1175: 		tostring(player:GetAttribute("ZyntraDispatchClientActive") == true),
1176: 		tostring(player:GetAttribute("Level3_Hiding") == true),
1177: 		tostring(UIDevice.ScreenOwningModalOpen()))
1178: end
1179: 
1180: trackReaderConnection(RunService.RenderStepped:Connect(function(dt)
1181: 	accumulated += dt
1182: 	if accumulated < UPDATE_INTERVAL then return end
1183: 	local elapsed = accumulated
1184: 	accumulated = 0
1185: 	bindClientEvent()
1186: 	updateReader(elapsed)
1187: end))
1188: 
1189: -- C_READER_TEARDOWN_20260831.
1190: --
1191: -- One teardown, idempotent, that every exit path funnels into. The triggers are
1192: -- the three ways this reader can actually stop existing: the LocalScript being
1193: -- destroyed, the ScreenGui being destroyed, and the gui being pulled out of the
1194: -- tree WITHOUT being destroyed (PlayerGui cleared, gui reparented). The last
1195: -- one is checked as `not gui:IsDescendantOf(game)` rather than
1196: -- `gui.Parent == nil`, because a reparent into a detached folder leaves Parent
1197: -- non-nil and the reader just as dead.
1198: --
1199: -- The three trigger connections are deliberately NOT tracked. Each is made on
1200: -- an instance that is being destroyed or detached at the moment it fires, so
1201: -- none can outlive what it watches; tracking them would only mean disconnecting
1202: -- a connection from inside its own handler.
1203: local function teardownReader()
1204: 	if not readerAlive then return end
1205: 	readerAlive = false
1206: 	for _, connection in ipairs(readerConnections) do
1207: 		if connection.Connected then connection:Disconnect() end
1208: 	end
1209: 	table.clear(readerConnections)
1210: 	-- The two rebinding connections, by name, for the reason given in
1211: 	-- C_READER_CONNECTION_TRACKING_20260831.
1212: 	if viewportConnection then
1213: 		viewportConnection:Disconnect()
1214: 		viewportConnection = nil
1215: 	end
1216: 	if clientEventConnection then
1217: 		clientEventConnection:Disconnect()
1218: 		clientEventConnection = nil
1219: 	end
1220: 	boundClientEvent = nil
1221: 	-- The R / ButtonY binding is not an RBXScriptConnection and so was never in
1222: 	-- the list. ContextActionService holds it against the action NAME until that
1223: 	-- name is unbound, which outlives the gui on its own.
1224: 	pcall(function()
1225: 		ContextActionService:UnbindAction("Level3ToggleExitReader")
1226: 	end)
1227: end
1228: 
1229: script.Destroying:Connect(teardownReader)
1230: gui.Destroying:Connect(teardownReader)
```

### Config: ServerScriptService/Level 3 Systems/Level 3 Configuration.ModuleScript.lua SHA256 c510b59dc310b719b127a2ff53e4ccf83a215a47ebb63a1b30e2a1d3ab8855ba
```lua

-- excerpt 46-51
46: 		MinimumCorridorLength = 18,
47: 		-- The concealed Signal Hall route is deliberately much longer than every
48: 		-- ordinary mall connector so the reversed PA master has time to unsettle players.
49: 		ExitCorridorLength = 560,
50: 		FinalHallHalfwayProgress = .50,
51: 		ExitCorridorSpeakerCount = 7,

-- excerpt 152-230
152: 		ChaseSpeedMultiplier = 1.20,
153: 		RuntimeName = "Mall Manager",
154: 		-- Signal Hall remains an authored emergency fallback only. Every real blackout
155: 		-- spawn is selected near a random member of the densest living player group.
156: 		SpawnRoomId = "SignalHall",
157: 		SpawnMinimumDistance = 90,
158: 		SpawnPreferredDistance = 125,
159: 		SpawnMaximumDistance = 180,
160: 		FinalHallSpawnProgress = .97,
161: 		FinaleApproachSpeed = 28,
162: 		SpawnGroupRadius = 75,
163: 		SpawnRoomMargin = 10,
164: 		-- Radius 5 matches the animated root-relative body sway. The slightly
165: 		-- larger local sweep preserves a visible buffer from walls and corners.
166: 		AgentRadius = 5,
167: 		-- Roblox's four-stud navmesh voxels reject a radius-five agent in the
168: 		-- authored 14-stud corridors even though the exact geometry fits. Route
169: 		-- with four studs, then enforce the true body envelope on every local sweep.
170: 		PathAgentRadius = 4,
171: 		SweepRadius = 5.25,
172: 		AgentHeight = 10,
173: 		WaypointSpacing = 4,
174: 		WaypointReachDistance = 1.25,
175: 		PathLookaheadWaypoints = 4,
176: 		BlackoutPathLookaheadWaypoints = 7,
177: 		PathSampleHeight = 0.5,
178: 		CorridorCenteringLead = 12,
179: 		DirectPathRange = 32,
180: 		BlackoutDirectPathRange = 48,
181: 		GoalTolerance = 3.2,
182: 		PathGoalMoveThreshold = 7,
183: 		-- The hunt tracks a moving nearest-player goal. Refresh before a runner can
184: 		-- pull a stale route several studs behind them, without flooding PFS.
185: 		BlackoutPathGoalMoveThreshold = 3,
186: 		PathRecomputeSeconds = 0.45,
187: 		BlackoutPathRecomputeSeconds = 0.20,
188: 		ThinkIntervalSeconds = 0.12,
189: 		BlackoutThinkIntervalSeconds = 0.10,
190: 		StuckSeconds = 0.85,
191: 		MaxPathFailures = 3,
192: 		ObstructionRecoveryAttempts = 3,
193: 		-- LEVEL3_MANAGER_FURNITURE_NAV_20260821
194: 		-- Hold one avoidance side long enough to clear wide furniture instead of
195: 		-- choosing a new left/right answer every movement frame.
196: 		AvoidanceCommitSeconds = 1.35,
197: 		OverlapEscapeProbeDistance = 3.5,
198: 		FurniturePathLabel = "Level3ManagerFurniture",
199: 		FurniturePathPadding = 1.25,
200: 		ProgressResetDistance = 8,
201: 		MovementAcceleration = 48,
202: 		MovementDeceleration = 72,
203: 		BlackoutMovementAcceleration = 96,
204: 		BlackoutMovementDeceleration = 120,
205: 		TurnResponsiveness = 9,
206: 		BlackoutTurnResponsiveness = 18,
207: 		MaximumMovementDeltaSeconds = 0.05,
208: 		MotionSnapshotRate = 30,
209: 		MotionInterpolationDelaySeconds = 0.065,
210: 		MotionBufferSamples = 8,
211: 		MotionLongGapSeconds = 0.30,
212: 		ChaseVisualLossGraceSeconds = 1.25,
213: 		BlackoutTargetLeadSeconds = 0.25,
214: 		BlackoutTargetLeadMaximumDistance = 8,
215: 		AttackRange = 4.4,
216: 		AttackConfirmRange = 5.4,
217: 		VerticalAttackTolerance = 6,
218: 		AttackWindupSeconds = 0.40,
219: 		BlackoutAttackWindupSeconds = 0.22,
220: 		AttackRecoverySeconds = 0.65,
221: 		BlackoutAttackRecoverySeconds = 0.40,
222: 		RetargetDistanceAdvantage = 28,
223: 		-- The blackout-only Manager begins moving on the reveal frame and never idles at patrol goals.
224: 		SpawnGraceSeconds = 0,
225: 		PatrolPauseSeconds = 0,
226: 		-- Absolute floor for a blackout sweep leg. The controller extends this by
227: 		-- direct distance / patrol speed, a detour factor, and slack; a fixed 20s
228: 		-- deadline is shorter than even several healthy adjacent-room routes.
229: 		BlackoutSweepLegSeconds = 20,
230: 		BlackoutSweepDistanceFactor = 1.5,
```

### Adapter: ServerScriptService/Level 3 Systems/Level 3 Round Adapter.ModuleScript.lua SHA256 bfb6470711f716e4ea94c25fd3d3ac45bf6e6cc85eb50418c7e1aac61e566ef1
```lua

-- excerpt 276-305
276: local function bindManagerToHunt(manifest: any, activeGeneration: number)
277: 	disconnectManagerLifecycle()
278: 	local token = managerLifecycleToken
279: 	local function sync()
280: 		if token ~= managerLifecycleToken or activeManifest ~= manifest
281: 			or not manifest.World or manifest.World.Parent ~= workspace then return end
282: 		local shouldExist = workspace:GetAttribute("Level3MallManagerHuntActive") == true
283: 			and workspace:GetAttribute("RoundActive") == true
284: 			and workspace:GetAttribute("SelectedLevel") == 3
285: 		if not shouldExist then
286: 			stopMallManager()
287: 			return
288: 		end
289: 		if MallManagerController.GetSnapshot() then return end
290: 		local ok, result = pcall(MallManagerController.Start, manifest, activeGeneration)
291: 		if not ok then
292: 			warn("[Level 3] Mall Manager hunt spawn failed: " .. tostring(result))
293: 			return
294: 		end
295: 		if result == nil then
296: 			-- Characters can briefly be unavailable on the exact edge. Retry only
297: 			-- while this same hunt generation is still authoritative.
298: 			task.delay(.35, function()
299: 				if token == managerLifecycleToken
300: 					and workspace:GetAttribute("Level3MallManagerHuntActive") == true then sync() end
301: 			end)
302: 		end
303: 	end
304: 	managerBlackoutConnection = workspace:GetAttributeChangedSignal("Level3MallManagerHuntActive"):Connect(sync)
305: 	sync()
```

### Music: ServerScriptService/Level 3 Systems/Level 3 Music Sequence Controller.ModuleScript.lua SHA256 803c62833b63d7b2a4f45216c782087ee7b526140399a3bf27cdb31585e1f5a1
```lua

-- excerpt 119-165
119: local function setPhase(activeSession: any, phase: string)
120: 	if activeSession.Phase == phase then return end
121: 	activeSession.Phase = phase
122: 	local state = stateFolder()
123: 	state:SetAttribute("Level3_RoomSongPhase", phase)
124: 	local startTime = activeSession.StartServerTime
125: 	if phase == "PRE_BLACKOUT" and startTime then
126: 		setBlackout(false, 0)
127: 		setHunt(false)
128: 		setRecoveryFlicker(false, 0, 0)
129: 		local warningStartedAt = startTime + Configuration.MusicSequence.BlackoutStartSeconds
130: 			- Configuration.MusicSequence.PreBlackoutFlickerSeconds
131: 		local warningUntil = startTime + Configuration.MusicSequence.BlackoutStartSeconds
132: 		state:SetAttribute("Level3_PreBlackoutSerial",
133: 			(state:GetAttribute("Level3_PreBlackoutSerial") or 0) + 1)
134: 		setPreBlackout(true, warningStartedAt, warningUntil)
135: 	elseif phase == "BLACKOUT_SONG" and startTime then
136: 		setPreBlackout(false, 0, 0)
137: 		setHunt(false)
138: 		setRecoveryFlicker(false, 0, 0)
139: 		shiftBlackoutChairs(activeSession)
140: 		local blackoutStartedAt = startTime + Configuration.MusicSequence.BlackoutStartSeconds
141: 		local untilTime = startTime + Configuration.MusicSequence.CycleEndSeconds
142: 		state:SetAttribute("Level3_BlackoutStartedAtServerTime", blackoutStartedAt)
143: 		setBlackout(true, untilTime)
144: 	elseif phase == "BLACKOUT_HUNT" and startTime then
145: 		setPreBlackout(false, 0, 0)
146: 		setRecoveryFlicker(false, 0, 0)
147: 		local untilTime = startTime + Configuration.MusicSequence.CycleEndSeconds
148: 		setBlackout(true, untilTime)
149: 		-- The Manager still spawns only after the song ends. The scream edge is
150: 		-- scheduled independently during the final three seconds of the song.
151: 		setHunt(true)
152: 	elseif phase == "RECOVERY_FLICKER" and startTime then
153: 		setPreBlackout(false, 0, 0)
154: 		setHunt(false)
155: 		setBlackout(false, 0)
156: 		local recoveryStartedAt = startTime + Configuration.MusicSequence.CycleEndSeconds
157: 		setRecoveryFlicker(true, recoveryStartedAt,
158: 			recoveryStartedAt + Configuration.MusicSequence.RecoveryFlickerSeconds)
159: 	else
160: 		-- Backward Studio seeks and every idle/done phase restore all timeline flags.
161: 		setPreBlackout(false, 0, 0)
162: 		setHunt(false)
163: 		setRecoveryFlicker(false, 0, 0)
164: 		setBlackout(false, 0)
165: 	end

-- excerpt 208-225
208: local function update(activeSession: any)
209: 	if session ~= activeSession
210: 		or not activeSession.World.Parent
211: 		or activeSession.World:GetAttribute("Level3_Generation") ~= activeSession.Generation then
212: 		return
213: 	end
214: 	if not activeSession.StartServerTime then
215: 		arm(activeSession)
216: 		return
217: 	end
218: 
219: 	local state = stateFolder()
220: 	local progress = tonumber(state:GetAttribute("Level3_ModuleProgress")) or 0
221: 	local goal = tonumber(state:GetAttribute("Level3_ModuleGoal")) or Configuration.ModuleGoal
222: 	if progress >= goal then
223: 		setPhase(activeSession, "DONE")
224: 		return
225: 	end
```

### WorldBuilder: ServerScriptService/Level 3 Systems/Level 3 World Builder.ModuleScript.lua SHA256 507da2f517db2b31c2806db082244c5e07c299dd72e163d9223a29bd08d33ab2
```lua

-- excerpt 2185-2235
2185: 	local mallManagerRuntime = folder(world, "Mall Manager Runtime")
2186: 	local openings = connectionMap()
2187: 	local manifestRooms = {}
2188: 	for index, room in ipairs(layout.Rooms) do
2189: 		manifestRooms[room.Id] = makeRoom(roomsFolder, room, openings[room.Id], index)
2190: 		if index % Configuration.Layout.BuildYieldEveryRooms == 0 then task.wait() end
2191: 	end
2192: 	local doors = {}
2193: 	local corridors = {}
2194: 	local blackoutScreamOpenings = {}
2195: 	local exitPortal
2196: 	local finalHall
2197: 	for index, link in ipairs(layout.Links) do
2198: 		local corridor = makeCorridor(corridorsFolder, link, index)
2199: 		table.insert(corridors, corridor)
2200: 		for _, opening in ipairs(corridor.ScreamOpenings) do
2201: 			table.insert(blackoutScreamOpenings, opening)
2202: 		end
2203: 		if link.Door == "HiddenExit" then
2204: 			exitPortal = makeHiddenExitPortal(doorsFolder, corridor)
2205: 			local halfwayProgress = Configuration.Layout.FinalHallHalfwayProgress or .50
2206: 			local spawnProgress = Configuration.MallManager.FinalHallSpawnProgress or .97
2207: 			local halfwayMarker = part(corridor.Model, "Level 3 Final Hall Halfway",
2208: 				CFrame.new(corridor.StartPoint:Lerp(corridor.EndPoint, halfwayProgress) + Vector3.new(0, .05, 0)),
2209: 				Vector3.new(2, .1, 2), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 1)
2210: 			decorative(halfwayMarker)
2211: 			halfwayMarker:SetAttribute("Level3_FinalHallHalfway", true)
2212: 			halfwayMarker:SetAttribute("Level3_FinalHallProgress", halfwayProgress)
2213: 			local spawnMarker = part(corridor.Model, "Level 3 Mall Manager Finale Spawn",
2214: 				CFrame.new(corridor.StartPoint:Lerp(corridor.EndPoint, spawnProgress) + Vector3.new(0, .05, 0)),
2215: 				Vector3.new(2, .1, 2), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 1)
2216: 			decorative(spawnMarker)
2217: 			spawnMarker:SetAttribute("Level3_MallManagerFinaleSpawn", true)
2218: 			spawnMarker:SetAttribute("Level3_FinalHallProgress", spawnProgress)
2219: 			finalHall = {
2220: 				Corridor = corridor,
2221: 				Model = corridor.Model,
2222: 				StartPoint = corridor.StartPoint,
2223: 				EndPoint = corridor.EndPoint,
2224: 				Forward = corridor.Forward,
2225: 				Length = corridor.Length,
2226: 				Width = corridor.Width,
2227: 				Height = corridor.Height,
2228: 				FloorY = corridor.StartPoint.Y,
2229: 				HalfwayProgress = halfwayProgress,
2230: 				SpawnProgress = spawnProgress,
2231: 				HalfwayMarker = halfwayMarker,
2232: 				SpawnMarker = spawnMarker,
2233: 			}
2234: 		end
2235: 		if index % Configuration.Layout.BuildYieldEveryCorridors == 0 then task.wait() end
```
