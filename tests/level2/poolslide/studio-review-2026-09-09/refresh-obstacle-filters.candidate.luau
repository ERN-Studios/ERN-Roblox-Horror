-- OFFLINE CANDIDATE ONLY. Replace precisely Navigator:_refreshObstacleFilters
-- in the fresh Studio source after rechecking Source == editor source.
-- BaseExclusions is immutable for this navigator's lifetime in the reviewed source.
-- Add `self.ObstacleCharacters = nil` beside BaseExclusions cleanup in Destroy.
function Navigator:_refreshObstacleFilters()
	local players = Players:GetPlayers()
	local previous = self.ObstacleCharacters
	local changed = previous == nil
	local count = 0
	-- Check actual character identity every call, without a time-based stale
	-- window. Respawns, joins, removals, and a changed player order rebuild now.
	for _, player in ipairs(players) do
		local character = player.Character
		if character then
			count += 1
			if not previous or previous[count] ~= character then changed = true end
		end
	end
	if not changed and count == #previous then return end
	-- Copy the large prop exclusion list and assign native filters only when
	-- membership changes, rather than twice at every sampled walking edge.
	local exclusions = table.clone(self.BaseExclusions)
	local characters = {}
	for _, player in ipairs(players) do
		local character = player.Character
		if character then
			table.insert(characters, character)
			table.insert(exclusions, character)
		end
	end
	self.RaycastParams.FilterDescendantsInstances = exclusions
	self.OverlapParams.FilterDescendantsInstances = exclusions
	self.ObstacleCharacters = characters
end
