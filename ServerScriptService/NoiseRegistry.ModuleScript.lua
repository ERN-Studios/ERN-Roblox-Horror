-- NoiseRegistry
-- PASTE INTO: ServerScriptService → Insert Object → ModuleScript → rename to "NoiseRegistry"

local NoiseRegistry = {}

local LOUDNESS = { sprint = 1.0, walk = 0.45, crouch = 0.0 }
local DECAY = 5

local sounds = {}

function NoiseRegistry.Add(position, stateName)
	local loud = LOUDNESS[stateName]
	if not loud or loud <= 0 then return end

	table.insert(sounds, {
		pos = position,
		loudness = loud,
		t = os.clock(),
	})
end

function NoiseRegistry.Prune()
	local now = os.clock()
	for i = #sounds, 1, -1 do
		if now - sounds[i].t > DECAY then
			table.remove(sounds, i)
		end
	end
end

function NoiseRegistry.GetBest(fromPos, maxRange)
	local best, bestScore = nil, 0
	for _, s in ipairs(sounds) do
		local dist = (s.pos - fromPos).Magnitude
		if dist < maxRange * s.loudness then
			local score = s.loudness / math.max(dist, 1)
			if score > bestScore then
				best, bestScore = s, score
			end
		end
	end
	return best
end

return NoiseRegistry
