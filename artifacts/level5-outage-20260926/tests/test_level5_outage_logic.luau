-- Run with the standalone Luau CLI. Supports task/patches and artifacts/<release>/tests layouts.
local loaded,Logic=pcall(require,"../patches/Level5OutageLogic.ModuleScript")
if not loaded then Logic=require("../../../ReplicatedStorage/Level5OutageLogic.ModuleScript") end
local assertions=0
local function check(ok,message) assertions+=1;assert(ok,message) end
local function near(a,b,message,tolerance) check(math.abs(a-b)<(tolerance or 1e-7),message) end
local function copy(value) local result={};for k,v in pairs(value) do result[k]=v end;return result end
local initial=Logic.NewSchedule(nil,100,4,1)
check(Logic.ValidateSchedule(initial),"A new schedule is valid")
near(initial.startedAt,100,"Start uses server time")
near(initial.blackoutAt,105,"Five seconds to all-off")
near(initial.restoreAt,165,"Full sixty-second dark hold follows cascade")
check(initial.gate==4 and initial.serial==1,"Gate and serial recorded")
for _,case in ipairs({{99,"NORMAL"},{100,"FALLING"},{104.999,"FALLING"},{105,"BLACKOUT"},{164.999,"BLACKOUT"},{165,"RECOVERING"},{166.499,"RECOVERING"},{166.5,"NORMAL"}}) do
	check(Logic.Phase(initial,case[1])==case[2],"Exact phase boundary at "..case[1])
end
for _,invalid in ipairs({false,true,2,"outage",{}, {startedAt=100,blackoutAt=105,restoreAt=165,gate=4}}) do
	check(not Logic.ValidateSchedule(invalid),"Incomplete/invalid schedules rejected")
	check(Logic.Phase(invalid,100)=="NORMAL","Invalid schedule fails open to normal lighting")
	near(Logic.AmbientPower(invalid,100),1,"Invalid schedule cannot leave ambient black")
end
for key,values in pairs({startedAt={math.huge,0/0,"100"},blackoutAt={104,106,-math.huge},restoreAt={164.9,0/0},gate={0,8,1.5,"4"},serial={0,1.5,math.huge}}) do
	for _,bad in ipairs(values) do local s=copy(initial);s[key]=bad;check(not Logic.ValidateSchedule(s),"Reject invalid "..key) end
end
for _,bad in ipairs({math.huge,0/0,"time"}) do check(not pcall(Logic.NewSchedule,nil,bad,1,1),"Reject invalid server clock input") end
for _,bad in ipairs({0,8,1.5,"1",math.huge}) do check(not pcall(Logic.NewSchedule,nil,100,bad,1),"Reject invalid gate") end

local expectedForFour={4,5,3,6,2,7,1,8}
for rank,section in ipairs(expectedForFour) do near(Logic.SectionRank(4,section),rank-1,"Forward ties before backward ties") end
for gate=1,7 do
	local schedule=Logic.NewSchedule(nil,100,gate,1)
	local seen={};local earliest=math.huge;local latest=-math.huge
	for section=1,8 do
		local rank=Logic.SectionRank(gate,section)
		check(rank>=0 and rank<=7 and not seen[rank],"Every section has a unique stable rank")
		seen[rank]=true
		near(Logic.SectionRank(gate,section),rank,"Repeated rank call is stable")
		local first=Logic.FixtureOffTime(schedule,section,0)
		local last=Logic.FixtureOffTime(schedule,section,1)
		earliest=math.min(earliest,first);latest=math.max(latest,last)
		check(first>100 and first<last and last<=105.000001,"Ordered fixtures fit the five-second cascade")
		for _,order in ipairs({0,.17,.5,1}) do
			local previous=1;local reflashSeen=false;local offSeen=false
			for step=0,500 do
				local now=100+step/100
				local reduced=Logic.FixturePower(schedule,now,section,order,true)
				local standard=Logic.FixturePower(schedule,now,section,order,false)
				check(reduced>=0 and reduced<=1 and standard>=0 and standard<=1,"Power remains normalized")
				check(reduced<=previous+1e-10,"Reduced flashing is monotonic until black")
				near(Logic.FixturePower(schedule,now,section,order,nil),reduced,"Unknown preference is reduced")
				if offSeen and standard>1e-6 then reflashSeen=true;check(standard<=Logic.REFLASH_POWER+1e-7,"Reflash stays dim") end
				if standard==0 then offSeen=true end
				previous=reduced
			end
			check(reflashSeen,"Standard preference gets its brief off-to-dim reflash")
			near(Logic.FixturePower(schedule,100,section,order,false),1,"No fixture begins partly off")
			near(Logic.FixturePower(schedule,105,section,order,false),0,"Every fixture fully off by five seconds")
			for _,time in ipairs({105,105.001,120,150,164.999,165}) do
				near(Logic.FixturePower(schedule,time,section,order,false),0,"Fixture holds off through all sixty seconds")
			end
			near(Logic.FixturePower(schedule,165.75,section,order,false),.5,"Halfway recovery power")
			near(Logic.FixturePower(schedule,166.5,section,order,false),1,"Exact original-power multiplier after recovery")
		end
	end
	near(latest,105,"Last-ranked last fixture reaches exactly five seconds")
	check(earliest<101,"Cascade starts within first second")
end

local before=copy(initial)
local overlap=Logic.NewSchedule(initial,125,5,2)
check(overlap~=initial,"Schedule update does not mutate prior object")
for k,v in pairs(before) do check(initial[k]==v,"Original schedule unchanged") end
near(overlap.startedAt,100,"Overlap preserves start")
near(overlap.blackoutAt,105,"Overlap preserves blackout boundary")
near(overlap.restoreAt,185,"Overlap grants sixty seconds from the new gate")
check(overlap.gate==4 and overlap.serial==2,"Wave origin preserved while serial advances")
for section=1,8 do for _,order in ipairs({0,.5,1}) do
	near(Logic.FixturePower(overlap,125,section,order,false),0,"Overlapping gate cannot relight blackout")
	near(Logic.FixturePower(overlap,184.999,section,order,false),0,"Extended hold remains black")
end end
local falling=Logic.NewSchedule(initial,102,5,2)
near(falling.restoreAt,165,"Early overlap never shortens original full hold")
for section=1,8 do for _,order in ipairs({0,.5,1}) do
	near(Logic.FixturePower(falling,102,section,order,false),Logic.FixturePower(initial,102,section,order,false),"Falling overlap does not restart fixture pulses")
end end
local recovery=Logic.NewSchedule(initial,165.6,6,2)
near(recovery.startedAt,100,"Recovery overlap retains previous start")
near(recovery.blackoutAt,105,"Recovery overlap retains previous wave")
near(recovery.restoreAt,225.6,"Recovery overlap extends sixty seconds")
check(recovery.gate==4 and Logic.Phase(recovery,165.6)=="BLACKOUT","Recovery interrupted directly to black, without bright restart")
near(Logic.AmbientPower(recovery,165.6),0,"Recovery overlap ambient returns to black")
local nextCycle=Logic.NewSchedule(initial,166.5,7,2)
near(nextCycle.startedAt,166.5,"New cycle allowed only after fully normal")
near(nextCycle.blackoutAt,171.5,"New cycle gets a fresh five seconds")
check(nextCycle.gate==7,"New cycle uses new gate wave origin")

local previousAmbient=1
for step=0,500 do
	local power=Logic.AmbientPower(initial,100+step/100)
	check(power>=0 and power<=1 and power<=previousAmbient+1e-10,"Ambient shutdown is continuous and monotonic")
	previousAmbient=power
end
near(Logic.AmbientPower(initial,102.5),.5,"Ambient half fall")
local previousRecovery=0
for step=0,150 do
	local power=Logic.AmbientPower(initial,165+step/100)
	check(power>=previousRecovery-1e-10 and power>=0 and power<=1,"Ambient recovery is monotonic")
	previousRecovery=power
end
near(Logic.AmbientPower(initial,104.99999),Logic.AmbientPower(initial,105),"Continuous fall-to-dark edge",1e-6)
near(Logic.AmbientPower(initial,164.99999),Logic.AmbientPower(initial,165.00001),"Continuous dark-to-recovery edge",1e-6)
near(Logic.AmbientPower(initial,166.49999),Logic.AmbientPower(initial,166.5),"Continuous recovery-to-normal edge",1e-6)
print("PASS Level 5 outage logic: "..assertions.." assertions; all gate/section waves, accessibility, blackout, recovery and overlap timing")
