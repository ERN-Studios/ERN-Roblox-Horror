-- Level 3 QA bot (client). Ordinary movement only: PathfindingService + Humanoid:MoveTo at the
-- game's own WalkSpeed, prompts through the engine's ProximityPrompt hold with the camera aimed at
-- them, hiding through the real HideUnderTablePrompt. No CFrame writes, no speed/health changes.
if _G.L3Bot then _G.L3Bot.stop = true task.wait(0.3) end
local B = { stop = false, go = false, hideEnabled = true }
_G.L3Bot = B
local Players = game:GetService("Players")
local PFS = game:GetService("PathfindingService")
local PPS = game:GetService("ProximityPromptService")
local RS = game:GetService("ReplicatedStorage")
local P = Players.LocalPlayer
local S = RS:WaitForChild("Level 3 State")
local L3R = RS:WaitForChild("Level 3 Remotes")
local cam = workspace.CurrentCamera
local world = workspace:WaitForChild("Level 3 Generated World")

local lines = {}
local function log(s)
	local line = string.format("%7.1f %s", workspace:GetServerTimeNow() - (B.t0 or workspace:GetServerTimeNow()), s)
	lines[#lines + 1] = line
	if #lines > 300 then table.remove(lines, 1) end
	P:SetAttribute("L3Bot_Log", table.concat(lines, "\n"))
end
B.t0 = workspace:GetServerTimeNow()
local function phase(s) P:SetAttribute("L3Bot_Phase", s) log("PHASE " .. s) end

local shown = {}
local c1 = PPS.PromptShown:Connect(function(pr) shown[pr] = true end)
local c2 = PPS.PromptHidden:Connect(function(pr) shown[pr] = nil end)

local function chr()
	local c = P.Character
	return c, c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("Head")
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function alive() local _, _, h = chr() return h and h.Health > 0 end
local function now() return workspace:GetServerTimeNow() end

local AGENT = { AgentRadius = 2, AgentHeight = 6, AgentCanJump = false, AgentCanClimb = false, WaypointSpacing = 6 }

-- hunt clock -------------------------------------------------------------------------------
local function huntAt()
	local start = S:GetAttribute("Level3_RoomSongStartServerTime")
	local ph = S:GetAttribute("Level3_RoomSongPhase")
	if typeof(start) ~= "number" or start <= 0 then return math.huge end
	if ph == "DONE" or ph == "WAITING_FOR_FIRST_CD" or ph == "WAITING_FOR_ROUND" then return math.huge end
	local t = start + 180.036
	if now() > t + 30.2 then return math.huge end -- this cycle's hunt is over; next cycle not armed yet
	return t
end
local function huntLive()
	return workspace:GetAttribute("Level3MallManagerHuntActive") == true or S:GetAttribute("Level3_MallManagerActive") == true
end
B.hideMargin = 32 -- seconds of slack before the hunt at which we go and hide

-- movement ---------------------------------------------------------------------------------
local function moveStraight(goal, tol, timeout, check)
	local _, root, hum = chr()
	hum:MoveTo(goal)
	local t, reissue = os.clock(), os.clock()
	while os.clock() - t < timeout do
		if B.stop or not alive() then return false end
		if check and check() then return "interrupt" end
		if (flat(root.Position) - flat(goal)).Magnitude <= tol then return true end
		if os.clock() - reissue > 6 then hum:MoveTo(goal) reissue = os.clock() end
		task.wait(0.05)
	end
	return false
end

local function pathTo(goal)
	local _, root = chr()
	local path = PFS:CreatePath(AGENT)
	local ok = pcall(function() path:ComputeAsync(root.Position, goal) end)
	if ok and path.Status == Enum.PathStatus.Success then return path:GetWaypoints() end
	return nil, ok and tostring(path.Status) or "compute error"
end

local function walkTo(goal, tol, check)
	for attempt = 1, 6 do
		local _, root = chr()
		if not alive() then return false end
		if (flat(root.Position) - flat(goal)).Magnitude <= tol then return true end
		local wps, why = pathTo(goal)
		if wps then
			local ok = true
			for i = 2, #wps do
				P:SetAttribute("L3Bot_Waypoint", i .. "/" .. #wps)
				local wp = wps[i].Position
				local d = (flat(root.Position) - flat(wp)).Magnitude
				local r = moveStraight(wp, (i == #wps) and tol or 2.2, d / 11 + 2.5, check)
				if r == "interrupt" then return "interrupt" end
				if not r then ok = false break end
			end
			if ok then return true end
			log("stall, recompute (attempt " .. attempt .. ")")
		else
			log("path " .. tostring(why) .. " (attempt " .. attempt .. "), straight nudge")
			local r = moveStraight(goal, tol, 3, check)
			if r == "interrupt" then return "interrupt" end
		end
	end
	return false
end

-- approach point with a clear head->target line (what canUsePrompt checks) ------------------
local function standOk(pos, target, owner, noLos)
	local c = P.Character
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c }
	local down = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
	if not down or not down.Instance.CanCollide then return false end
	local rootPos = down.Position + Vector3.new(0, 3.6, 0)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { c }
	for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(rootPos), Vector3.new(3.2, 4.5, 3.2), op)) do
		if part.CanCollide then return false end
	end
	if noLos then return true, rootPos end
	local headPos = rootPos + Vector3.new(0, 1.55, 0)
	local hit = workspace:Raycast(headPos, target - headPos, params)
	if hit and not (owner and hit.Instance:IsDescendantOf(owner)) then return false end
	return true, rootPos
end

local function approachPoints(target, owner, radii, noLos)
	local _, root = chr()
	local cands = {}
	for _, r in ipairs(radii) do
		for k = 0, 23 do
			local a = k * math.pi / 12
			local p = Vector3.new(target.X + math.cos(a) * r, target.Y, target.Z + math.sin(a) * r)
			local ok, rp = standOk(p, target, owner, noLos)
			if ok then cands[#cands + 1] = { pos = rp, r = r, d = (flat(rp) - flat(root.Position)).Magnitude } end
		end
	end
	table.sort(cands, function(a, b) return a.d < b.d end)
	return cands
end

-- prompt hold with the camera aimed at the prompt ---------------------------------------------
local function aimAndHold(prompt, targetPos, hold)
	local _, root, _, head = chr()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(head.Position, targetPos)
	local t = os.clock()
	while not shown[prompt] and os.clock() - t < 2.5 do task.wait(0.05) end
	if not shown[prompt] then
		cam.CFrame = CFrame.lookAt(head.Position, targetPos + Vector3.new(0, 0, 12)) task.wait(0.35)
		cam.CFrame = CFrame.lookAt(head.Position, targetPos)
		t = os.clock()
		while not shown[prompt] and os.clock() - t < 2 do task.wait(0.05) end
	end
	local wasShown = shown[prompt] == true
	local dist = (root.Position - targetPos).Magnitude
	pcall(function() prompt:InputHoldBegin() end)
	task.wait(hold + 0.3)
	pcall(function() prompt:InputHoldEnd() end)
	task.wait(0.5)
	cam.CameraType = Enum.CameraType.Custom
	return wasShown, dist
end

-- hiding -----------------------------------------------------------------------------------
local function anchors()
	local out = {}
	for _, d in ipairs(world:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Level3_HideTableAnchor") == true then out[#out + 1] = d end
	end
	return out
end

local function hideNow(reason)
	phase("HIDE_SEEK (" .. reason .. ")")
	local _, root = chr()
	local list = {}
	for _, a in ipairs(anchors()) do
		local pr = a:FindFirstChild("HideUnderTablePrompt")
		if pr and pr.Enabled and (a:GetAttribute("Level3_HideOccupiedUserId") or 0) == 0 then
			list[#list + 1] = { a = a, pr = pr, d = (flat(a.Position) - flat(root.Position)).Magnitude }
		end
	end
	table.sort(list, function(x, y) return x.d < y.d end)
	for i = 1, math.min(3, #list) do
		local e = list[i]
		log(string.format("hide target table %s at %.0f studs", tostring(e.a:GetAttribute("Level3_HideTableIndex")), e.d))
		local cands = approachPoints(e.a.Position, nil, { 4.5, 5.5, 6.5 }, true)
		for j = 1, math.min(4, #cands) do
			if walkTo(cands[j].pos, 1.5) == true then
				for _ = 1, 3 do
					local wasShown, dist = aimAndHold(e.pr, e.a.Position, 0.1)
					task.wait(0.4)
					if P:GetAttribute("Level3_Hiding") == true then
						log(string.format("HIDDEN at table %s (shown=%s dist=%.1f)", tostring(e.a:GetAttribute("Level3_HideTableIndex")), tostring(wasShown), dist))
						return true
					end
				end
			end
		end
	end
	log("HIDE FAILED")
	return false
end

local function waitOutHunt()
	phase("HIDDEN_WAIT")
	local sawHunt = false
	while not B.stop do
		if not alive() then return false end
		if huntLive() then sawHunt = true end
		local ph = S:GetAttribute("Level3_RoomSongPhase")
		if sawHunt and not huntLive() and (ph == "RECOVERY_FLICKER" or ph == "RESTARTING" or ph == "ARMED" or ph == "PLAYING") then break end
		if P:GetAttribute("Level3_Hiding") ~= true then log("no longer hidden?!") return true end
		task.wait(0.25)
	end
	task.wait(1)
	phase("UNHIDE")
	L3R.Level3HideRequest:FireServer("EXIT")
	local t = os.clock()
	while P:GetAttribute("Level3_Hiding") == true and os.clock() - t < 4 do task.wait(0.1) end
	log("left hiding; hiding=" .. tostring(P:GetAttribute("Level3_Hiding")) .. " phase=" .. tostring(S:GetAttribute("Level3_RoomSongPhase")))
	return P:GetAttribute("Level3_Hiding") ~= true
end

local function mustHide()
	if not B.hideEnabled then return false end
	return (huntAt() - now()) < B.hideMargin or huntLive()
end

local function hideCycle(reason)
	if hideNow(reason) then return waitOutHunt() end
	return false
end

-- objectives -------------------------------------------------------------------------------
B.results = {}
local function findHideNear(pos)
	for _, a in ipairs(anchors()) do
		if (flat(a.Position) - flat(pos)).Magnitude < 3 then return a end
	end
end

local function collectCD(i)
	local tries = 0
	while tries < 6 and not B.stop do
		tries += 1
		if S:GetAttribute("Level3_CD" .. i .. "State") ~= "WORLD" then return true end
		if mustHide() then if not hideCycle("before CD" .. i) then return false end end
		local model = world:FindFirstChild(string.format("Birthday Music CD %02d", i), true)
		local case = model and model:FindFirstChild("Transparent Jewel Case")
		local prompt = case and case:FindFirstChild("CollectPrompt")
		if not prompt then log("CD" .. i .. " model/prompt missing on client") return false end
		phase("GO_CD" .. i)
		local cands = approachPoints(case.Position, model, { 3.8, 4.6, 5.5, 6.5 })
		log(string.format("CD%d: %d stand points", i, #cands))
		local reached = false
		for j = 1, math.min(5, #cands) do
			local r = walkTo(cands[j].pos, 1.2, mustHide)
			if r == "interrupt" then break end
			if r == true then reached = true break end
		end
		if not alive() then return false end
		if reached then
			local anchor = findHideNear(case.Position)
			local hp = anchor and anchor:FindFirstChild("HideUnderTablePrompt")
			local hideBefore = hp and hp.Enabled
			phase("HOLD_CD" .. i)
			local wasShown, dist = aimAndHold(prompt, case.Position, prompt.HoldDuration)
			task.wait(0.3)
			local st = S:GetAttribute("Level3_CD" .. i .. "State")
			local rec = string.format("CD%d try%d: collectShown=%s dist=%.1f hideEnabledBefore=%s -> state=%s hideEnabledAfter=%s held=%s progress=%s hiding=%s",
				i, tries, tostring(wasShown), dist, tostring(hideBefore), tostring(st), tostring(hp and hp.Enabled),
				tostring(P:GetAttribute("Level3_HeldCDCount")), tostring(S:GetAttribute("Level3_CDCollectedProgress")), tostring(P:GetAttribute("Level3_Hiding")))
			log(rec)
			B.results[#B.results + 1] = rec
			if st == "CARRIED" then return true end
		end
	end
	return S:GetAttribute("Level3_CD" .. i .. "State") == "CARRIED"
end

local function insertAll()
	local tries = 0
	while tries < 6 and not B.stop do
		tries += 1
		if mustHide() then if not hideCycle("before reader") then return false end end
		local dp = world:FindFirstChild("Level 3 Signal Hall Disc Player", true)
		local panel = dp and dp:FindFirstChild("Disc Player Control Panel", true)
		local prompt = panel and panel:FindFirstChild("InsertCDPrompt")
		if not prompt then log("disc player prompt missing") return false end
		phase("GO_READER")
		local cands = approachPoints(panel.Position, dp, { 3.5, 4.5, 5.5, 6.5 })
		log(string.format("reader: %d stand points", #cands))
		local reached = false
		for j = 1, math.min(6, #cands) do
			local r = walkTo(cands[j].pos, 1.2, mustHide)
			if r == "interrupt" then break end
			if r == true then reached = true break end
		end
		if reached then
			phase("HOLD_READER")
			local wasShown, dist = aimAndHold(prompt, panel.Position, prompt.HoldDuration)
			task.wait(0.5)
			local rec = string.format("READER try%d: shown=%s dist=%.1f inserted=%s exitUnlocked=%s phase=%s held=%s",
				tries, tostring(wasShown), dist, tostring(S:GetAttribute("Level3_CDInsertedProgress")),
				tostring(S:GetAttribute("Level3_ExitUnlocked")), tostring(S:GetAttribute("Level3_RoomSongPhase")), tostring(P:GetAttribute("Level3_HeldCDCount")))
			log(rec)
			B.results[#B.results + 1] = rec
			if S:GetAttribute("Level3_ExitUnlocked") == true then return true end
		end
	end
	return S:GetAttribute("Level3_ExitUnlocked") == true
end

local function finale()
	local esc = world:FindFirstChild("EscapeTrigger", true)
	local hallFloor
	for _, m in ipairs(world.Rooms:GetChildren()) do
		if m:GetAttribute("Level3_RoomId") == "SignalHall" then hallFloor = m:FindFirstChild("Level 3 Room Floor", true) end
	end
	if not (hallFloor and esc) then log("finale parts missing floor=" .. tostring(hallFloor) .. " esc=" .. tostring(esc)) return false end
	-- stage INSIDE SignalHall, 7 studs short of its east edge (the hall StartPoint); the chase
	-- trigger sits 4 studs past that edge, so standing here never starts the finale.
	local eastEdge = hallFloor.Position.X + hallFloor.Size.X / 2
	local stage = Vector3.new(eastEdge - 7, esc.Position.Y, esc.Position.Z)
	phase("FINALE_STAGE")
	walkTo(stage, 1.2)
	local t = os.clock()
	while (P:GetAttribute("Stamina") or 0) < 0.999 and os.clock() - t < 30 do task.wait(0.2) end
	local _, sroot = chr()
	log(string.format("staged x=%.1f (east edge %.1f), stamina=%s mult=%s triggered=%s", sroot.Position.X, eastEdge,
		tostring(P:GetAttribute("Stamina")), tostring(P:GetAttribute("ZyntraStaminaMultiplier")), tostring(S:GetAttribute("Level3_FinalHallChaseTriggered"))))
	phase("FINALE_READY")
	while not B.go and not B.stop do task.wait(0.1) end
	phase("FINALE_RUN")
	local _, root, hum = chr()
	local startT = now()
	local maxWS, samples, sprintS = 0, 0, 0
	local lastLog = 0
	while not B.stop and alive() and P:GetAttribute("Escaped") ~= true do
		hum:MoveTo(Vector3.new(esc.Position.X + 2, root.Position.Y, esc.Position.Z))
		samples += 1
		if hum.WalkSpeed > 20 then sprintS += 1 end
		if hum.WalkSpeed > maxWS then maxWS = hum.WalkSpeed end
		if os.clock() - lastLog > 1 then
			lastLog = os.clock()
			log(string.format("run x=%.0f ws=%.0f stam=%.2f mgr=%s dist=%s", root.Position.X, hum.WalkSpeed, P:GetAttribute("Stamina") or -1,
				tostring(S:GetAttribute("Level3_MallManagerState")), tostring(S:GetAttribute("Level3_MallManagerTargetDistance"))))
		end
		if now() - startT > 60 then log("finale timeout") break end
		task.wait(0.1)
	end
	log(string.format("FINALE END escaped=%s alive=%s t=%.1fs maxWS=%.0f sprintFrac=%.2f", tostring(P:GetAttribute("Escaped")), tostring(alive()), now() - startT, maxWS, sprintS / math.max(1, samples)))
	return P:GetAttribute("Escaped") == true
end

B.run = function(order)
	phase("START")
	for _, i in ipairs(order) do
		if B.stop then break end
		if not collectCD(i) then phase("FAIL_CD" .. i) return end
		log("have CD" .. i .. "; huntIn=" .. string.format("%.0f", huntAt() - now()))
	end
	if not insertAll() then phase("FAIL_READER") return end
	if not finale() then phase("FAIL_FINALE") return end
	phase("DONE_ESCAPED")
end

B.cleanup = function()
	B.stop = true
	c1:Disconnect() c2:Disconnect()
	cam.CameraType = Enum.CameraType.Custom
end
log("bot installed")
return "installed"
