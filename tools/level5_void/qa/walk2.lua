-- the Level 5 walk-through with a clumsy thumb: MODE manual | early | late | auto, SPEED 16 or 26, ALT 0 = main route
local SECTIONS, MODE, SPEED, ALT = {__SECS__}, "__MODE__", __SPEED__, __ALT__
local lp = game.Players.LocalPlayer
lp:SetAttribute("L5Walk", "running")
task.spawn(function()
local Http = game:GetService("HttpService")
local RunService = game:GetService("RunService")
if lp:GetAttribute("Level5VoidRound") ~= true then lp:SetAttribute("L5Walk", "not in level 5") return end
local model = workspace["Level 5 Void"]
local origin = model:GetAttribute("Origin")
local route = Http:JSONDecode(model.Route.Value)
local alts = model:FindFirstChild("Alts") and Http:JSONDecode(model.Alts.Value) or {}
local tap = lp.PlayerScripts:FindFirstChild("Level5JumpTap")
workspace:SetAttribute("Level5AutoJumpAll", MODE == "auto")
local kinds = {}
local conn = lp:GetAttributeChangedSignal("Level5AssistCount"):Connect(function()
	local k = lp:GetAttribute("Level5AssistLast") or "?"
	kinds[k] = (kinds[k] or 0) + 1
end)
local out = {}
for _, sec in ipairs(SECTIONS) do
	local pts = {}
	if ALT > 0 then
		local n = 0
		for _, alt in ipairs(alts) do
			if alt.sec == sec then n += 1; if n == ALT then pts = alt.points end end
		end
	else
		for _, r in ipairs(route) do if r.sec == sec and not r.gate then pts[#pts + 1] = r end end
	end
	if #pts < 2 then out[#out + 1] = sec .. ": no such route" continue end
	local char = lp.Character
	local hum, root = char:FindFirstChildOfClass("Humanoid"), char.HumanoidRootPart
	if hum.Health <= 0 then out[#out + 1] = sec .. ": body is dead" break end
	local function world(r) return origin + Vector3.new(r.x, r.y, r.z) end
	root.AssemblyLinearVelocity = Vector3.zero
	char:PivotTo(CFrame.new(world(pts[1]) + Vector3.new(0, 3.2, 0)))
	task.wait(1.2)
	local jumps, made, fails, slow, top = 0, 0, {}, 0, 0
	local started = os.clock()
	for i = 2, #pts do
		local a, b = world(pts[i - 1]), world(pts[i])
		local flatDir = (b - a) * Vector3.new(1, 0, 1)
		local dir = flatDir.Magnitude > 0.01 and flatDir.Unit or Vector3.xAxis
		local jumped, airAt = false, nil
		local trigger = MODE == "early" and -1.1 or 0.72
		if pts[i].hop then trigger = -1.6 end          -- a block in the way: the body cannot come nearer than its face
		if pts[i].jump then jumps += 1 end
		local deadline = os.clock() + 6
		local ok = false
		while os.clock() < deadline do
			hum.WalkSpeed = SPEED
			hum:MoveTo(b)
			local pos = root.Position
			local flat = (pos - b) * Vector3.new(1, 0, 1)
			local along = ((pos - a) * Vector3.new(1, 0, 1)):Dot(dir)
			local v = root.AssemblyLinearVelocity
			top = math.max(top, Vector3.new(v.X, 0, v.Z).Magnitude)
			if pts[i].jump and not jumped then
				if (MODE == "manual" or MODE == "early") and along >= trigger then
					jumped = true
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
				elseif MODE == "late" and not pts[i].hop then
					-- the tap comes 2.5 studs past the take-off edge (the edge is 0.9 past `a`)
					if along >= 0.9 + 2.5 then jumped = true; tap:Fire() end
				elseif MODE == "late" and pts[i].hop and along >= trigger then
					jumped = true
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
				end
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
	out[#out + 1] = string.format("%s %s@%d alt%d: %d/%d jumps, %d points, %d failed (%d timeout), top speed %.0f, %.0fs %s", sec, MODE, SPEED, ALT, made, jumps, #pts, #fails, slow, top, os.clock() - started, table.concat(fails, " "))
end
conn:Disconnect()
workspace:SetAttribute("Level5AutoJumpAll", nil)
local k = {}
for name, n in pairs(kinds) do k[#k + 1] = name .. "=" .. n end
lp:SetAttribute("L5Walk", table.concat(out, " || ") .. " || assists " .. table.concat(k, ","))
end)
return "started"
