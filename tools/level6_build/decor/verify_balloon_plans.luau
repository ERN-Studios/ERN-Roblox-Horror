local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local sourcePath = "tools/level6_build/decor/Level 6 Balloon Dressing.ModuleScript.luau"
local source = fs.readFile(sourcePath)
-- Compile the complete candidate, then execute only its portable planner.
luau.compile(source)
local prefix = source:sub(1, assert(source:find("local function footprint", 1, true))-1)
local dressing = luau.load(prefix .. "\nreturn Dressing", {debugName="balloon-planner"})()
local rooms = {{Id="Arrival",Role="Arrival",W=64,D=54,H=12},{Id="Exit",Role="Exit",W=58,D=52,H=12}}
for i=1,30 do table.insert(rooms,{Id="Test"..i,W=54+4*(i%6),D=48+4*(i%4),H=11+i%3}) end
local totals={Seeds=128,Rooms=0,Clusters=0,MinimumClustersPerSeed=math.huge,MaximumClustersPerSeed=0,
	DensityCounts={},Ceiling=0,Grounded=0,DistinctAssignments=0,DeterministicReplay=true}
local seen={}
for seed=1,totals.Seeds do
	local assignment = dressing.AssignDensities(rooms,seed)
	assert(not assignment.Arrival and not assignment.Exit)
	local tiers={Sparse=0,Medium=0,Dense=0}
	local total=0
	for _, room in ipairs(rooms) do
		local tier=assignment[room.Id]
		if not tier then continue end
		tiers[tier]+=1
		-- A central table, cardinal portal lanes, CD/hide anchor and a full
		-- service corner exercise collision-independent visual clearance.
		local obstacles={{x=0,z=0,hx=9,hz=6},{x=room.W*.5-10,z=room.D*.5-13,hx=9.4,hz=12},
			{x=-room.W*.5+8,z=-room.D*.5+8,hx=4,hz=4}}
		local plan=dressing.Plan(room,seed,tier,obstacles)
		assert(serde.encode("json",plan)==serde.encode("json",dressing.Plan(room,seed,tier,obstacles)))
		local bounds=if tier=="Sparse" then {1,2} elseif tier=="Medium" then {3,4} else {7,9}
		assert(plan.TargetClusters>=bounds[1] and plan.TargetClusters<=bounds[2])
		assert(#plan.Placements==plan.TargetClusters,"Expected usable perimeter not fully decorated: "..seed.." "..room.Id.." "..tier)
		for _,p in ipairs(plan.Placements) do
			local r=p.Footprint
			assert(math.abs(r.x)-r.hx>=7 and math.abs(r.z)-r.hz>=7)
			assert(math.abs(r.x)+r.hx<=room.W*.5-1.1 and math.abs(r.z)+r.hz<=room.D*.5-1.1)
			for _,b in ipairs(obstacles) do
				assert(math.abs(r.x-b.x)>=r.hx+b.hx+.45 or math.abs(r.z-b.z)>=r.hz+b.hz+.45)
			end
			assert(p.y+7.95*p.Scale<=room.H-.49)
			if p.Floating then assert(p.y>=7.15-1e-9) totals.Ceiling+=1 else assert(p.y==0) totals.Grounded+=1 end
		end
		total+=#plan.Placements totals.Rooms+=1
	end
	assert(tiers.Sparse==10 and tiers.Medium==10 and tiers.Dense==10)
	assert(total<=160)
	local signature=serde.encode("json",assignment)
	seen[signature]=true
	totals.Clusters+=total
	totals.MinimumClustersPerSeed=math.min(totals.MinimumClustersPerSeed,total)
	totals.MaximumClustersPerSeed=math.max(totals.MaximumClustersPerSeed,total)
	totals.DensityCounts=tiers
end
for _ in pairs(seen) do totals.DistinctAssignments+=1 end
assert(totals.DistinctAssignments==totals.Seeds,"Density room assignment did not vary by seed")
assert(totals.Ceiling>0 and totals.Grounded>0)
local result={Scope="Offline geometry planning; actual live placement, navigation and performance remain unverified",Passed=true,Totals=totals}
fs.writeFile("artifacts/level6-entity-decor-20261001/balloon-plans-128-seeds.json",serde.encode("json",result,true).."\n")
print(result)
