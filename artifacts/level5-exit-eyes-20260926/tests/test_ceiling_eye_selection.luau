-- BEGIN PURE TARGET_SELECTION
local function chooseTarget(candidates,currentId,loads,index)
	local nearest=math.huge
	for _,candidate in ipairs(candidates) do nearest=math.min(nearest,candidate.distance) end
	local winner,best=nil,math.huge
	for _,candidate in ipairs(candidates) do
		-- Keep each pair oriented toward nearby people. The assignment penalty
		-- distributes similar-distance group members across different eye pairs;
		-- it never recruits a far player just to equalize a global count.
		if candidate.distance<=nearest+48 then
			local cost=candidate.distance+(loads[candidate.userId] or 0)*6
				-(candidate.userId==currentId and 8 or 0)+((index*37+candidate.userId%29)%17)*.03
			if cost<best or cost==best and winner and candidate.userId<winner.userId then winner,best=candidate,cost end
		end
	end
	return winner
end

local n=0
local function check(good,why) n+=1;assert(good,why) end
check(chooseTarget({},0,{},1)==nil,"empty region returns rest")
local single={userId=11,distance=80}
check(chooseTarget({single},0,{},1)==single,"single live candidate tracked")
local loads={};local seen={}
for eye=1,48 do
 local winner=chooseTarget({{userId=11,distance=75},{userId=22,distance=78}},0,loads,eye)
 loads[winner.userId]=(loads[winner.userId] or 0)+1;seen[winner.userId]=true
end
check(seen[11] and seen[22],"nearby group members both receive eye pairs")
check(loads[11]>=20 and loads[22]>=20,"similar-distance group is distributed")
for eye=1,48 do
 local chosen=chooseTarget({{userId=11,distance=20},{userId=22,distance=150}},0,{[11]=48,[22]=0},eye)
 check(chosen.userId==11,"distant member cannot win load-balancing alone")
end
check(chooseTarget({{userId=11,distance=70},{userId=22,distance=73}},22,{},1).userId==22,"small position change keeps current target")
check(chooseTarget({{userId=11,distance=20},{userId=22,distance=100}},22,{},1).userId==11,"nearer arrival replaces far old target")
local first=chooseTarget({{userId=11,distance=75},{userId=22,distance=75}},0,{},7)
local second=chooseTarget({{userId=22,distance=75},{userId=11,distance=75}},0,{},7)
check(first.userId==second.userId,"selection stable across player enumeration order")
print("PASS "..n.." ceiling-eye selection assertions (mock distances, not native multiplayer)")
