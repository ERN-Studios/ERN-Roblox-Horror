Focused FINAL delta review of three frozen Luau candidates; answer at most 1100 words (hard requirement). Use only supplied excerpts and facts. Report remaining concrete defects or say none found within this limited scope; distinguish source findings, owner-reported mocked checks, and unverified runtime. Do not repeat fixed baseline findings or infer a full-file approval from excerpts. Supply minimal fixes and a compact runtime test matrix if useful.

User contract: ALL living non-escaped current round participants must have strictly passed50% of the corridor before one Manager appears exactly at the authored far endpoint and immediately CHASES toward players. No near-player spawn distance veto, alternate placement, random roaming, or recovery teleport. Protected living participants count and can be chased; attack immunity remains. Crossings are latched per character and cleared at death/revive. Dead/disconnected/non-round spectators excluded. CD scanner uses each current state: all CARRIED/INSERTED with insertion incomplete -> precise CD PLAYER direction, distance and projected/edge pin. WORLD/DROPPED or unknown state -> SCAN, even when historical collectedcount==goal; all inserted/unlocked -> EXIT. Spectated subject and existing hidden/toast/modal/dispatch/hiding gates remain. Respect touch safe area; keep pin noninteractive and clean it up.

Facts independently read from unchanged code: Objective validPlayer requires live session, SelectedLevel3/RoundActive, Parent==Players, InRoundtrue, Escapedfalse. Missing live root counts+blocks; no character/humanoid is not established living, matching current GameManager lifecycle (report conditional limitation rather than inventing alive evidence). Music DONE stops normal Hunt. Adapter sync ignores an existing snapshot; forced Stop before new Hunt edge prevents reuse of a nearby normal rig. Adapter Cleanup530-534 disconnects lifecycle and stops Manager BEFORE Music/Objective cleanup, so earlier flag-order warning is resolved. Hiding module requires only Protection/Config, no require cycle. Normal AI protections/patrol unchanged. Finale selects protected records, defers at a blocked ENDPOINT only, and retries every.35s while hunt generation valid. No ordinary distance/LOS gate. Marker authoring is synchronized to EndPoint by world owner; actual clearance still needs runtime evidence. Production recovery performs route bookkeeping/checked kinematic steps only; independent audit found no teleport. Start acquires CHASE before first Heartbeat when unpaused. EntityPaused remains honored.

Other scoped changes: Objective publishes actual post-Visual DiscPlayer.Position as Level3_CDPlayerPosition/workspace Level3CDPlayerPosition, clears both on reset; full candidate display update is outside this review. Reader reads that Vector3 first, falls back to a bounded streamed control lookup. Mode update uses current CD states, not no-beacons or historical count. PLAYER branch passes watched-root+position into setPlayerGuide; all other branches clear it. Geometry refreshes per frame using existing RenderStepped connection; state/text remains10Hz. isActive unchanged: selectedlevel, local inround/nonescaped OR valid watched living subject, no dispatch/hiding/modal. panel.Visible incorporates hidden and toast. Toast immediately hides separate pin; teardown clears guide/cache and existing connections. Safe rectangle cached by layout; actual device fit unverified. Reader direct rotation avoids scalar smoothing across±180. Camera vertical yaw derives yAxis cross RightVector.

Checks: exact SHA256s verified below. Both full AI/Objective candidates compile;80 assertions in33 extracted-source mocked scenarios passed with receipt artifacts/level3-finale-player-20261002/finale-mock-receipt.json. Reader owner reports full compile+60 focused source-function checks. These do NOT establish physics, real multiplayer, replication, native assets, visual projection, or CPU/memory results. Existing thrown Start errors remain a conditional asset/runtime blocker; owner performs native validation separately. Source excerpts only, original line numbers; blank/comment-only lines omitted for compactness.

Objective SHA256 4271bc4890412385b496aebd626e33336e913fbf90bf9646d378ae62a31d8e38
```lua
-- fragment131-174
132: local function updateFinalHallChase(session: AnyTable)
133: 	if not session.ExitUnlocked
134: 		or session.State:GetAttribute("Level3_RoomSongPhase") ~= "DONE" then
135: 		return
136: 	end
137: 	local hall = session.Manifest.FinalHall
138: 	if type(hall) ~= "table" or not hall.Model or not hall.Model.Parent then return end
139: 	local horizontalForward = Vector3.new(hall.Forward.X, 0, hall.Forward.Z)
140: 	if horizontalForward.Magnitude <= .001 then return end
141: 	horizontalForward = horizontalForward.Unit
142: 	local eligibleCount = 0
143: 	local crossedCount = 0
144: 	for _, player in ipairs(Players:GetPlayers()) do
145: 		if validPlayer(player, session) then
146: 			local character = player.Character
147: 			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
148: 			local root = character and character:FindFirstChild("HumanoidRootPart")
150: 			if character and character.Parent and humanoid and humanoid.Health > 0 then
151: 				eligibleCount += 1
152: 				if session.FinalHallCrossed[player] ~= character then
153: 					character:SetAttribute("Level3_FinalHallCrossedGeneration", nil)
154: 				end
155: 				if root and root:IsA("BasePart") and session.FinalHallCrossed[player] ~= character then
156: 					local offset = Vector3.new(
157: 						root.Position.X - hall.StartPoint.X, 0, root.Position.Z - hall.StartPoint.Z)
158: 					local along = offset:Dot(horizontalForward)
159: 					local lateral = (offset - horizontalForward * along).Magnitude
162: 					local entryProgress = hall.Length * .50
163: 					local insideHallWidth = lateral <= hall.Width * .5 + 2.5
164: 					local insideHallHeight = math.abs(root.Position.Y - hall.FloorY) <= hall.Height + 6
165: 					if along > entryProgress and along <= hall.Length + 2.5
166: 						and insideHallWidth and insideHallHeight then
167: 						session.FinalHallCrossed[player] = character
168: 						character:SetAttribute("Level3_FinalHallCrossedGeneration", session.Generation)
169: 					end
170: 				end
171: 				if session.FinalHallCrossed[player] == character then crossedCount += 1 end
172: 			end
173: 		end
174: 	end
-- fragment183-200
183: 	if session.FinalHallChaseTriggered or eligibleCount == 0 or crossedCount ~= eligibleCount then return end
187: 	workspace:SetAttribute("Level3MallManagerHuntActive", false)
188: 	MallManagerController.Stop()
189: 	session.FinalHallChaseTriggered = true
190: 	session.State:SetAttribute("Level3_FinalHallChaseTriggered", true)
191: 	session.State:SetAttribute("Level3_FinalHallChaseActive", true)
192: 	session.State:SetAttribute("Level3_MallManagerHuntActive", true)
193: 	session.Manifest.World:SetAttribute("Level3_FinalHallChaseTriggered", true)
194: 	session.Manifest.World:SetAttribute("Level3_FinalHallChaseActive", true)
195: 	workspace:SetAttribute("Level3FinalHallChaseTriggered", true)
198: 	workspace:SetAttribute("Level3FinalHallChaseActive", true)
199: 	workspace:SetAttribute("Level3MallManagerHuntActive", true)
200: end
-- fragment391-396
391: 	local playerPosition = session.DiscPlayer and session.DiscPlayer.Position
392: 	session.State:SetAttribute("Level3_CDPlayerPosition", playerPosition)
393: 	workspace:SetAttribute("Level3CDPlayerPosition", playerPosition)
394: 	local insertedCount = math.max(0, session.InsertedCount or session.ModuleCount or 0)
395: 	local collectedCount = math.max(0, session.CollectedCount or 0)
396: 	local heldCount = math.max(0, session.HeldCount or 0)
```

AI SHA256 c78189234adcd884ef21371d5f4dfe0ebf7d54efbfc45c290f37a0e3ffeae490
```lua
-- fragment139-154
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
151: 		or (not session.FinalHallChase and PlayerProtection.IsActive(player, character)) then
152: 		return nil, nil, nil
153: 	end
154: 	return character, humanoid, root
-- fragment2061-2074
2061: 		session.SearchUntil = nil
2062: 		if session.FinalHallChase then
2064: 			session.PatrolGoal = nil
2065: 			session.PatrolLegUntil = nil
2066: 			clearGoal(session)
2067: 			publishState(session, "WAITING")
2068: 			publishTargetTelemetry(session, "NO_LIVING_PLAYER", -1, nil)
2069: 			return false
2070: 		end
2073: 		local sweepGoal = arrivalGoal(session)
2074: 		if session.PatrolGoal and (not sweepGoal
-- fragment2342-2357
2342: 	if not player or not character or not liveSession(session)
2343: 		or player.Character ~= character or not PlayerProtection.IsActive(player, character) then return end
2344: 	session.Suspicion[player] = nil
2345: 	local ownsTarget = not session.FinalHallChase and session.Target == player
2347: 	local ownsMemory = not session.FinalHallChase and session.LastKnownPlayer == player
2348: 	local ownsAttack = session.Attacking and session.AttackPlayer == player and session.AttackCharacter == character
2349: 	local ownsCheck = not session.FinalHallChase and session.TableCheckTargetPlayer == player
2350: 	if ownsAttack then
2351: 		session.AttackToken += 1
2352: 		session.Attacking = false
2353: 		session.AttackPlayer = nil
2354: 		session.AttackCharacter = nil
2355: 		if session.FinalHallChase and validRound(session) then publishState(session, "CHASE") end
2356: 	end
2357: 	if ownsCheck then endTableCheck(session, false) end
-- fragment2496-2504
2496: local function attackLineClear(session: any, player: Player, maximumRange: number): (boolean, Humanoid?)
2498: 	if PlayerProtection.IsActive(player, player.Character) then return false, nil end
2499: 	if HidingController.IsHidden(player, session.Generation) then return false, nil end
2502: 	if HidingController.IsFlushImmune(player) then return false, nil end
2503: 	local character, humanoid, root = livingPlayer(player, session)
2504: 	if not character or not humanoid or not root then return false, nil end
-- fragment3398-3431
3398: local function chooseFinalHallSpawn(manifest: any, generation: number): any?
3399: 	local records = eligibleSpawnPlayers(true)
3400: 	if #records == 0 then return nil end
3401: 	local hall = manifest.FinalHall
3402: 	if type(hall) ~= "table" or not hall.Model or not hall.Model.Parent then return nil end
3403: 	local state = stateFolder()
3404: 	local cycle = math.floor(tonumber(state:GetAttribute("Level3_RoomSongCycle")) or 0)
3405: 	local random = Random.new(generation * 7919 + cycle * 104729 + 20260824)
3408: 	for _, player in ipairs(Players:GetPlayers()) do
3409: 		if player.Parent == Players and player:GetAttribute("InRound") == true
3410: 			and player:GetAttribute("Escaped") ~= true then
3411: 			local character = player.Character
3412: 			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
3413: 			if character and character.Parent and humanoid and humanoid.Health > 0 then
3414: 				local root = character:FindFirstChild("HumanoidRootPart")
3415: 				if not root or not root:IsA("BasePart")
3416: 					or character:GetAttribute("Level3_FinalHallCrossedGeneration") ~= generation then return nil end
3417: 			end
3418: 		end
3419: 	end
3421: 	local position = Vector3.new(hall.EndPoint.X, hall.FloorY, hall.EndPoint.Z)
3422: 	if not spawnVolumeFits(position, spawnOverlapParams(records)) then return nil end
3424: 	table.sort(records, function(a, b)
3425: 		local aInHall = insideFinalHall({Manifest=manifest}, a.Position)
3426: 		local bInHall = insideFinalHall({Manifest=manifest}, b.Position)
3427: 		if aInHall ~= bInHall then return aInHall end
3428: 		local aDistance = planarDistance(position, a.Position)
3429: 		local bDistance = planarDistance(position, b.Position)
3430: 		if math.abs(aDistance - bDistance) > .001 then return aDistance < bDistance end
3431: 		return a.Player.UserId < b.Player.UserId
-- fragment3595-3612
3595: 	local groundOffset = pivot.Position.Y - (boundingCFrame.Position.Y - boundingSize.Y * .5)
3596: 	local rootPosition = spawnPosition + Vector3.new(0, groundOffset, 0)
3597: 	local target = Vector3.new(facePosition.X, rootPosition.Y, facePosition.Z)
3598: 	if (target - rootPosition).Magnitude <= .001 then
3601: 		local hall = manifest.FinalHall
3602: 		local forward = type(hall) == "table" and hall.Forward
3603: 		local direction = forward and Vector3.new(-forward.X, 0, -forward.Z) or Vector3.new(0, 0, -1)
3604: 		if direction.Magnitude <= .001 then direction = Vector3.new(0, 0, -1) end
3605: 		target = rootPosition + direction.Unit
3606: 	end
3607: 	model:PivotTo(CFrame.lookAt(rootPosition, target))
3608: 	model.Parent = manifest.MallManagerRuntime
3609: 	CollectionService:AddTag(model, "Level3HostileEntity")
3610: 	return model, root, groundOffset
3611: end
-- fragment3850-3859
3850: 	local function roundChanged()
3851: 		if not liveSession(session) then return end
3852: 		if workspace:GetAttribute("RoundActive") == true
3853: 			and workspace:GetAttribute("SelectedLevel") == 3
3854: 			and workspace:GetAttribute("Level3MallManagerHuntActive") == true then
3855: 			session.ActivatedAt = os.clock() + (session.FinalHallChase and 0 or Tuning.SpawnGraceSeconds)
3856: 			session.LastProgressAt = os.clock()
3857: 			session.LastGenuineProgressAt = os.clock()
3858: 			session.ProgressObjectiveKey = nil
3859: 			session.ProgressBestDistance = math.huge
```

Reader SHA256 b452be2e27d398c282ce8c2d26f3add7e78074a71a5d9799f086591a93c1fb9e
```lua
-- fragment1044-1120
1044: local function readerTargetMode(states: {any}, goal: number, inserted: number, unlocked: boolean): string
1045: 	if unlocked or inserted >= goal then return "EXIT" end
1046: 	local insertedStates = 0
1047: 	for index = 1, goal do
1048: 		local state = states[index]
1049: 		if state == "INSERTED" then insertedStates += 1
1050: 		elseif state ~= "CARRIED" then return "SCAN" end
1051: 	end
1052: 	return if insertedStates == goal then "EXIT" else "PLAYER"
1053: end
1054: local function precisePlanarBearing(fx: number, fz: number, dx: number, dz: number): number
1055: 	if fx*fx + fz*fz < .000001 or dx*dx + dz*dz < .000001 then return 0 end
1056: 	return math.atan2(fx*dz - fz*dx, fx*dx + fz*dz)
1057: end
1058: local function precisePlanarHeading(fx: number, fz: number, rx: number, rz: number,
1059: 	fallbackX: number, fallbackZ: number): (number, number)
1060: 	if fx*fx + fz*fz >= .000001 then return fx, fz end
1063: 	if rx*rx + rz*rz >= .000001 then return rz, -rx end
1064: 	return fallbackX, fallbackZ
1065: end
1066: local function projectGuidePoint(x: number, y: number, depth: number, bearing: number,
1067: 	minX: number, minY: number, maxX: number, maxY: number): (number, number, number, boolean)
1068: 	if depth > 0 and x >= minX and x <= maxX and y >= minY and y <= maxY then
1069: 		return x, y, 0, true
1070: 	end
1071: 	local cx, cy = (minX+maxX)*.5, (minY+maxY)*.5
1072: 	local dx, dy = x-cx, y-cy
1075: 	if depth <= 0 then dx, dy = math.sin(bearing), -math.cos(bearing) end
1076: 	if math.abs(dx)+math.abs(dy) < .000001 then dx, dy = 0, -1 end
1077: 	local sx = if math.abs(dx) > .000001 then (maxX-minX)*.5/math.abs(dx) else math.huge
1078: 	local sy = if math.abs(dy) > .000001 then (maxY-minY)*.5/math.abs(dy) else math.huge
1079: 	local scale = math.min(sx, sy)
1080: 	return cx+dx*scale, cy+dy*scale, math.deg(math.atan2(dx, -dy)), false
1081: end
1084: local function setPlayerGuide(enabled: boolean, target: Vector3?, root: BasePart?)
1085: 	guidePlayerMode, guideTarget, guideRoot = enabled, target, root
1086: 	needle.Visible, centerLine.Visible = not enabled, not enabled
1087: 	playerCompassArrow.Visible = enabled and target ~= nil
1088: 	playerCompassLabel.Visible = enabled and target ~= nil
1089: 	if not enabled or not target or not root then playerGuide.Visible = false end
1090: end
1091: local function updatePlayerGuideGeometry()
1092: 	local root, target = guideRoot, guideTarget
1093: 	if not guidePlayerMode or not root or not root.Parent or not target
1094: 		or not panel.Visible or not isActive() then
1095: 		playerGuide.Visible = false
1096: 		return
1097: 	end
1098: 	local camera = workspace.CurrentCamera
1099: 	local forward = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
1100: 	local fx, fz = forward.X, forward.Z
1101: 	if fx*fx + fz*fz < .000001 then
1102: 		local right = if camera then camera.CFrame.RightVector else root.CFrame.RightVector
1103: 		local fallback = root.CFrame.LookVector
1104: 		fx, fz = precisePlanarHeading(fx, fz, right.X, right.Z, fallback.X, fallback.Z)
1105: 	end
1106: 	local position = root.Position
1107: 	local dx, dy, dz = target.X-position.X, target.Y-position.Y, target.Z-position.Z
1108: 	guideBearing = precisePlanarBearing(fx, fz, dx, dz)
1109: 	guideDistance = math.sqrt(dx*dx + dy*dy + dz*dz)
1110: 	playerCompassArrow.Rotation = math.deg(guideBearing)
1111: 	if not camera then playerGuide.Visible = false; return end
1112: 	local projected = camera:WorldToViewportPoint(target)
1113: 	local x, y, rotation, onPoint = projectGuidePoint(projected.X, projected.Y, projected.Z,
1114: 		guideBearing, guideMinX, guideMinY, guideMaxX, guideMaxY)
1115: 	playerGuide.Position = UDim2.fromOffset(math.floor(x+guideOffsetX), math.floor(y+guideOffsetY))
1116: 	guideArrow.Rotation = rotation
1118: 	guideArrow.Text = if onPoint then "◆" else "▲"
1119: 	playerGuide.Visible = true
1120: end
-- fragment899-902
899: 	UIDevice.SetInteractive(restoreButton, false)
900: 	playerGuide.Visible = false
901: 	local hold = math.clamp(if type(duration) == "number" then duration else 2.4, 0.8, 6)
902: 	task.delay(hold, function()
-- fragment1415-1425
1415: trackReaderConnection(RunService.RenderStepped:Connect(function(dt)
1416: 	if not readerAlive then return end
1419: 	updatePlayerGuideGeometry()
1420: 	accumulated += dt
1421: 	if accumulated < UPDATE_INTERVAL then return end
1422: 	local elapsed = accumulated
1423: 	accumulated = 0
1424: 	bindClientEvent()
1425: 	updateReader(elapsed)
-- fragment1442-1449
1442: local function teardownReader()
1443: 	if not readerAlive then return end
1444: 	readerAlive = false
1445: 	playerGuide.Visible = false
1446: 	guidePlayerMode, guideTarget, guideRoot = false, nil, nil
1447: 	cachedPlayerWorld, cachedPlayerControl = nil, nil
1448: 	for _, connection in ipairs(readerConnections) do
1449: 		if connection.Connected then connection:Disconnect() end
```
