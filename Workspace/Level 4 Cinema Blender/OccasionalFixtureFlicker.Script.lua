-- Level 4 cinema (Blender build): flickering fixtures. Runs on every client (RunContext Client): a blink costs no
-- replication, and parts that stream in join. Any BasePart in this model with a truthy OccasionalFlicker attribute
-- is a fixture: every few seconds its lights stutter off in a short burst and its lens, if visible, goes dark.
-- Written by tools/level4_blender/place.luau.
local model = script.Parent
local running = {}

local function burst(part, rng)
	local lights = {}
	for _, l in part:GetChildren() do
		if l:IsA("Light") then table.insert(lights, { l, l.Enabled }) end
	end
	local visible = part.Transparency < 1
	local material, color = part.Material, part.Color
	for _ = 1, rng:NextInteger(1, 5) do
		for _, e in lights do e[1].Enabled = false end
		if visible then
			part.Material = Enum.Material.SmoothPlastic
			part.Color = color:Lerp(Color3.new(0, 0, 0), 0.8)
		end
		task.wait(rng:NextNumber(0.04, 0.16))
		for _, e in lights do e[1].Enabled = e[2] end
		if visible then part.Material, part.Color = material, color end
		task.wait(rng:NextNumber(0.03, 0.3))
	end
end

local function watch(part)
	if not (part:IsA("BasePart") and part:GetAttribute("OccasionalFlicker")) then return end
	local token = {}
	running[part] = token
	task.spawn(function()
		local rng = Random.new()
		-- a quarter of the fixtures are dying (a stutter every 1-4 s), the rest act up every 5-18 s
		local dying = rng:NextNumber() < 0.25
		local lo, hi = if dying then 1 else 5, if dying then 4 else 18
		task.wait(rng:NextNumber(0, hi))
		while running[part] == token and part:IsDescendantOf(model) do
			burst(part, rng)
			task.wait(rng:NextNumber(lo, hi))
		end
	end)
end

for _, d in model:GetDescendants() do watch(d) end
model.DescendantAdded:Connect(watch)
model.DescendantRemoving:Connect(function(d) running[d] = nil end)
