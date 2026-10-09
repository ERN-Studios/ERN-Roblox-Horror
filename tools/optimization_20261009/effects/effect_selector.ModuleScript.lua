-- READ-ONLY selector. Root owns every Studio mutation and must compare these fresh baselines again inside its write.
local Selector = {}
local function uniqueMap(dataModel, name)
	local found
	for _, service in ipairs({dataModel:GetService("Workspace"), dataModel:GetService("ServerStorage")}) do
		for _, child in ipairs(service:GetChildren()) do
			if child.Name == name then
				assert(not found, "Duplicate map " .. name)
				assert(child:IsA("Model"), "Map class mismatch " .. name)
				found = child
			end
		end
	end
	return assert(found, "Map missing " .. name)
end

function Selector.ParticleBound(lifetime, speed, acceleration, holderDiagonal, maxSize, wind)
	assert(wind == false, "Water FX wind requires a new conservative bound")
	-- A sphere covering emitter half-size, all travel, and camera-facing particle corners.
	local bound = speed * lifetime + 0.5 * acceleration * lifetime * lifetime
		+ holderDiagonal / 2 + maxSize * math.sqrt(2) / 2
	assert(bound <= 32, "Water FX particle influence exceeds 32 studs; re-evaluate")
	return bound
end

function Selector.Collect(dataModel)
	assert(not dataModel:GetService("RunService"):IsRunning(), "Select authored Enabled baselines in Edit only")
	local entries, counts = {}, {}
	local function add(instance, map, influence)
		assert(instance.Parent:IsA("BasePart") and instance.Parent.Anchored, "Effect mount is not static")
		table.insert(entries, {
			Instance = instance, Map = map,
			Baseline = {Enabled = instance.Enabled,
				Wanted = instance:GetAttribute("SceneBudgetWantedEnabled"),
				Influence = instance:GetAttribute("SceneBudgetInfluenceRadius")},
			Wanted = instance.Enabled, Influence = influence,
		})
		counts[map] = (counts[map] or 0) + 1
	end
	local cinema = uniqueMap(dataModel, "Level 4 Cinema Blender")
	for _, instance in ipairs(cinema:GetDescendants()) do
		if instance:IsA("Light") and instance.Parent:IsA("BasePart")
			and type(instance.Parent:GetAttribute("L4Zone")) == "number"
			and instance.Parent.Anchored then
			-- Use Edit-mode authoring state, before a round owns Enabled.
			add(instance, cinema.Name, nil)
		end
	end
	local void = uniqueMap(dataModel, "Level 5 Void")
	local lights = assert(void:FindFirstChild("Lights"), "Void Lights missing")
	for _, instance in ipairs(lights:GetDescendants()) do
		if instance:IsA("PointLight") and instance.Parent.Name == "Light"
			and instance.Parent:IsA("BasePart") and instance.Parent.Anchored then
			add(instance, void.Name, nil)
		end
	end
	local pool = uniqueMap(dataModel, "Level2PoolroomsMap")
	local foam = assert(pool:FindFirstChild("Water FX"), "Water FX missing")
	for _, instance in ipairs(foam:GetDescendants()) do
		if instance:IsA("ParticleEmitter") and instance.Parent:IsA("BasePart") and instance.Parent.Anchored then
			local maxSize = 0
			for _, keypoint in ipairs(instance.Size.Keypoints) do
				maxSize = math.max(maxSize, keypoint.Value + keypoint.Envelope)
			end
			Selector.ParticleBound(instance.Lifetime.Max, instance.Speed.Max, instance.Acceleration.Magnitude,
				instance.Parent.Size.Magnitude, maxSize, instance.WindAffectsDrag)
			add(instance, pool.Name, 32)
		end
	end
	return entries, counts
end

return Selector
