local SECTIONS = %s
local lp = game.Players.LocalPlayer
local Http = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local t0 = os.clock()
repeat task.wait(0.5) until lp:GetAttribute("LobbyLoadingDone") or os.clock() - t0 > 60
if lp:GetAttribute("Level5VoidRound") ~= true then
	local zone
	for _, d in ipairs(workspace.LobbyReimaginedPreview:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("R3QueueId") and d:GetAttribute("LevelNumber") == 5 then zone = d break end
	end
	lp.Character:PivotTo(zone.CFrame + Vector3.new(0, 4, 0))
	task.wait(1.5)
	game.ReplicatedStorage.Remotes.ConfigureQueue:FireServer(zone:GetAttribute("R3QueueId"), 1, "public", "normal")
	local t1 = os.clock()
	repeat task.wait(0.5) until (lp:GetAttribute("Level5VoidRound") == true and lp:GetAttribute("InRound") == true) or os.clock() - t1 > 60
	task.wait(9)
end
if lp:GetAttribute("Level5VoidRound") ~= true then return "not in level 5" end
local model = workspace["Level 5 Void"]
local origin = model:GetAttribute("Origin")
local route = Http:JSONDecode(model.Route.Value)
local out = {}
for _, sec in ipairs(SECTIONS) do
	local pts = {}
	for _, r in ipairs(route) do if r.sec == sec and not r.gate then pts[#pts + 1] = r end end
	local char = lp.Character
	local hum, root = char:FindFirstChildOfClass("Humanoid"), char.HumanoidRootPart
	if hum.Health <= 0 then out[#out + 1] = sec .. ": body is dead" break end
	local function world(r) return origin + Vector3.new(r.x, r.y, r.z) end
	root.AssemblyLinearVelocity = Vector3.zero
	char:PivotTo(CFrame.new(world(pts[1]) + Vector3.new(0, 3.2, 0)))
	task.wait(1.2)
	local jumps, made, fails, slow = 0, 0, {}, 0
	local started = os.clock()
	for i = 2, #pts do
		local a, b = world(pts[i - 1]), world(pts[i])
		local flatDir = (b - a) * Vector3.new(1, 0, 1)
		local dir = flatDir.Magnitude > 0.01 and flatDir.Unit or Vector3.xAxis
		local jumped = false
		local trigger = sec == "ivory" and 1.45 or 0.72
		if pts[i].jump then jumps += 1 end
		local deadline = os.clock() + 5
		local ok = false
		while os.clock() < deadline do
			hum:MoveTo(b)
			local pos = root.Position
			local flat = (pos - b) * Vector3.new(1, 0, 1)
			if pts[i].jump and not jumped and ((pos - a) * Vector3.new(1, 0, 1)):Dot(dir) >= trigger then
				jumped = true
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
			end
			if flat.Magnitude < 1.25 and math.abs(pos.Y - 3.6 - b.Y) < 2.5 and hum.FloorMaterial ~= Enum.Material.Air then ok = true break end
			if pos.Y - 3 < math.min(a.Y, b.Y) - 12 or hum.Health <= 0 then break end
			RunService.Heartbeat:Wait()
		end
		if ok then
			if pts[i].jump then made += 1 end
		else
			if os.clock() >= deadline then slow += 1 end
			fails[#fails + 1] = string.format("#%d%s(%.0f,%.0f,%.0f)", i, pts[i].jump and "J" or "", pts[i].x, pts[i].y, pts[i].z)
			if hum.Health <= 0 then break end
			root.AssemblyLinearVelocity = Vector3.zero
			char:PivotTo(CFrame.new(b + Vector3.new(0, 3.2, 0)))
			task.wait(0.5)
		end
	end
	out[#out + 1] = string.format("%s: %d/%d jumps, %d points, %d failed (%d by timeout) in %.0fs %s", sec, made, jumps, #pts, #fails, slow, os.clock() - started, table.concat(fails, " "))
end
return table.concat(out, "\n")
