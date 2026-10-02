-- Level 4 cinema (Blender build): flickering lights. Runs on every client (RunContext Client): a blink costs no
-- replication, and parts that stream in join. A unit is a Model with a truthy OccasionalFlicker attribute (its Neon
-- parts and every Light inside it) or a BasePart with the attribute outside such a Model (a light holder). Every few
-- seconds a unit stutters and usually stays OFF for 0.3-4 s (12 %: a 6-15 s outage), so its area goes dark. With
-- ReduceFlashing (anything but an explicit false: a profile that has not loaded yet never strobes) it fades out,
-- holds and fades back instead. Written by tools/level4_blender/place.luau.
local TweenService = game:GetService("TweenService")
local player = game:GetService("Players").LocalPlayer
local model = script.Parent
local running = {}
local FADE = 1.5

local function reduced()
	return player == nil or player:GetAttribute("ReduceFlashing") ~= false
end

local function members(unit)
	local lights, lenses = {}, {}
	local list = unit:GetDescendants()
	table.insert(list, unit)
	for _, d in list do
		if d:IsA("Light") then
			table.insert(lights, { d, d.Brightness })
		elseif d:IsA("BasePart") and d.Material == Enum.Material.Neon and d.Transparency < 1 then
			table.insert(lenses, { d, d.Color })
		end
	end
	return lights, lenses
end

local function set(lights, lenses, on)
	for _, e in lights do e[1].Brightness = if on then e[2] else 0 end
	for _, e in lenses do
		e[1].Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		e[1].Color = if on then e[2] else e[2]:Lerp(Color3.new(0, 0, 0), 0.85)
	end
end

local function fade(state, lights, lenses, on)
	local info = TweenInfo.new(FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local function tween(part, goals)
		local t = TweenService:Create(part, info, goals)
		table.insert(state.tweens, t)
		t:Play()
	end
	for _, e in lights do tween(e[1], { Brightness = if on then e[2] else 0 }) end
	for _, e in lenses do      -- stays Neon: a near-black Neon tube reads as dead without a material snap
		e[1].Material = Enum.Material.Neon
		tween(e[1], { Color = if on then e[2] else e[2]:Lerp(Color3.new(0, 0, 0), 0.9) })
	end
	task.wait(FADE)
	table.clear(state.tweens)
end

local function offTime(rng)
	return if rng:NextNumber() < 0.12 then rng:NextNumber(6, 15) else rng:NextNumber(0.3, 4)
end

local function event(unit, rng, state)
	local lights, lenses = members(unit)
	state.lights, state.lenses = lights, lenses
	if #lights + #lenses == 0 then return end
	local function slow()
		fade(state, lights, lenses, false)
		task.wait(offTime(rng))
		fade(state, lights, lenses, true)
	end
	if reduced() then slow(); return end
	for _ = 1, rng:NextInteger(1, 4) do                   -- the stutter
		if reduced() then slow(); return end
		set(lights, lenses, false)
		task.wait(rng:NextNumber(0.04, 0.16))
		if reduced() then slow(); return end
		set(lights, lenses, true)
		task.wait(rng:NextNumber(0.03, 0.25))
	end
	if rng:NextNumber() < 0.7 then                         -- and usually it gives out for a while
		set(lights, lenses, false)
		task.wait(offTime(rng))
		for _ = 1, rng:NextInteger(0, 2) do                -- a catch or two on the way back
			if reduced() then slow(); return end
			set(lights, lenses, true)
			task.wait(rng:NextNumber(0.04, 0.12))
			if reduced() then slow(); return end
			set(lights, lenses, false)
			task.wait(rng:NextNumber(0.05, 0.2))
		end
	end
	if reduced() then fade(state, lights, lenses, true); return end
	set(lights, lenses, true)
end

local function unitOf(d)
	if not d:GetAttribute("OccasionalFlicker") then return nil end
	if d:IsA("Model") then return d end
	if not d:IsA("BasePart") then return nil end
	local owner = d:FindFirstAncestorWhichIsA("Model")
	if owner and owner ~= model and owner:GetAttribute("OccasionalFlicker") then return nil end   -- the Model is the unit
	return d
end

local function watch(d)
	local unit = unitOf(d)
	if not unit or running[unit] then return end
	local state = { tweens = {} }
	running[unit] = state
	state.thread = task.spawn(function()
		local rng = Random.new()
		-- a quarter of the units are dying (an episode every 2-6 s), the rest act up every 6-20 s
		local dying = rng:NextNumber() < 0.25
		local lo, hi = if dying then 2 else 6, if dying then 6 else 20
		task.wait(rng:NextNumber(0, hi))
		while running[unit] == state and unit:IsDescendantOf(model) do
			event(unit, rng, state)
			task.wait(rng:NextNumber(lo, hi))
		end
	end)
end

local function stop(unit)
	local state = running[unit]
	if not state then return end
	running[unit] = nil
	if state.thread then task.cancel(state.thread) end
	for _, t in state.tweens do t:Cancel() end
	set(state.lights or {}, state.lenses or {}, true)
end

for _, d in model:GetDescendants() do watch(d) end
local added = model.DescendantAdded:Connect(watch)
local removing = model.DescendantRemoving:Connect(stop)
script.Destroying:Connect(function()
	added:Disconnect()
	removing:Disconnect()
	for unit in running do stop(unit) end
end)
