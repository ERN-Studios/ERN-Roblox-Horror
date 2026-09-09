-- OFFLINE TABLE-MOCK FIXTURE. Safe to run in Edit; no Instances or gameplay mutation.
-- Before routine copied byte-for-byte from the fresh Studio export at lines543-550.
local roster = {}
local Players = {GetPlayers = function() return table.clone(roster) end}
local Navigator = {}
local function before(self)
	local exclusions = table.clone(self.BaseExclusions)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclusions, player.Character) end
	end
	self.RaycastParams.FilterDescendantsInstances = exclusions
	self.OverlapParams.FilterDescendantsInstances = exclusions
end
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

local checks = {}
local function check(label, condition)
	table.insert(checks, {Name=label, Pass=condition == true})
	assert(condition, label)
end
local function same(a,b)
	if #a ~= #b then return false end
	for i,v in ipairs(a) do if v ~= b[i] then return false end end
	return true
end
local function params()
	local record = {Writes=0, Value={}}
	local proxy = setmetatable({}, {
		__index=function(_, key) assert(key=="FilterDescendantsInstances"); return table.clone(record.Value) end,
		__newindex=function(_, key, value)
			assert(key=="FilterDescendantsInstances")
			record.Writes += 1
			record.Value = table.clone(value)
		end,
	})
	return proxy, record
end
local function make()
	local ray, rayRecord = params()
	local overlap, overlapRecord = params()
	local base = {}
	for index=1,263 do base[index] = "PROP_"..index end
	return {BaseExclusions=base, RaycastParams=ray, OverlapParams=overlap},
		{Ray=rayRecord,Overlap=overlapRecord}
end
local old, oldCounters = make()
local new, newCounters = make()
local baseBefore = table.clone(new.BaseExclusions)
local function step(label)
	before(old)
	Navigator._refreshObstacleFilters(new)
	check(label.." ray", same(old.RaycastParams.FilterDescendantsInstances,new.RaycastParams.FilterDescendantsInstances))
	check(label.." overlap", same(old.OverlapParams.FilterDescendantsInstances,new.OverlapParams.FilterDescendantsInstances))
	check(label.." immutable base", same(baseBefore,new.BaseExclusions))
end
local a,b,c,d = {},{},{},{}
local p1,p2,p3 = {Character=a},{Character=b},{Character=nil}
roster={p1,p2}
step("first two characters")
local writesBefore = newCounters.Ray.Writes + newCounters.Overlap.Writes
for _=1,1000 do before(old); Navigator._refreshObstacleFilters(new) end
check("1000 unchanged calls preserve ordered filters",same(old.RaycastParams.FilterDescendantsInstances,new.RaycastParams.FilterDescendantsInstances))
check("1000 unchanged calls assign zero native filters",newCounters.Ray.Writes+newCounters.Overlap.Writes==writesBefore)
roster={p1,p2,p3}; step("join without Character")
p3.Character=c; step("new Character appears")
p2.Character=d; step("existing player respawns")
p1.Character=nil; step("character removed")
roster={p3,p2,p1}; step("player list reorder")
roster={p3}; step("player removal")
roster={}; step("all players removed")
step("unchanged empty roster")
roster={p1,p2}; step("empty character skipped")
p1.Character=d; step("duplicate character reference preserved")
new.ObstacleCharacters=nil; step("cache cleared rebuilds safely")
local pass=0
for _,result in ipairs(checks) do if result.Pass then pass+=1 end end
return {Pass=pass,Total=#checks,Checks=checks,
	OriginalFilterAssignments=oldCounters.Ray.Writes+oldCounters.Overlap.Writes,
	CachedFilterAssignments=newCounters.Ray.Writes+newCounters.Overlap.Writes,
	StaticPropCount=#baseBefore,FixtureOnly=true,GameplayAndPerformanceNotMeasured=true}

