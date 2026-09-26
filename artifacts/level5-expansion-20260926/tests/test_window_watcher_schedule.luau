-- Run from this folder with the Luau CLI; imports the actual draft, not a copy.
local Encounters=require("../../../ServerScriptService/Level 5 Systems/Level 5 Window Watcher Encounters.ModuleScript")
local assertions=0
local function check(value,message)
	assertions+=1;assert(value,message)
end
local function near(a,b) return math.abs(a-b)<1e-6 end
local function fixed(value) return Encounters.NewSchedule(function() return value end) end

local schedule=fixed(.5)
check(schedule.Step(0,false,{1,2,3})==nil,"no roster must not schedule")
check(schedule.Step(1000,false,{1,2,3})==nil,"no background catch-up")
check(schedule.Snapshot().due==nil,"empty rounds have no timer")
check(schedule.Step(1000,true,{1,2,3})==nil,"entering F starts a short delay")
check(near(schedule.Snapshot().due,1003),"first delay is 2-4 seconds")
check(schedule.Step(1002.99,true,{1,2,3})==nil,"not early")
local first=schedule.Step(1003,true,{1,2,3})
check(first.kind=="show" and first.index==2,"eligible random selection")
check(near(first.endsAt,1014),"8-14 second intended duration")
schedule.MarkRevealed(1003.25)
check(near(schedule.Snapshot().ends,1014.25),"animation warm-up does not shorten visible time")
schedule.MarkRevealed(1004)
check(near(schedule.Snapshot().ends,1014.25),"reveal marking is idempotent")
check(schedule.Step(1010,true,{})==nil,"temporary occlusion does not flicker the actor")
check(schedule.Step(1014.249,true,{1,2,3})==nil,"duration is respected")
local hidden=schedule.Step(1014.25,true,{1,2,3})
check(hidden.kind=="hide" and near(hidden.nextAt,1040.75),"18-35 second cooldown starts on hide")
check(schedule.Step(1040.74,true,{1,2,3})==nil,"cooldown never fires early")
check(schedule.Step(1040.75,true,{})==nil,"do not spawn behind a solid wall")
local nextShow=schedule.Step(1041,true,{1,2,3})
check(nextShow.kind=="show" and nextShow.index~=first.index,"different window when alternatives are visible")
check(schedule.Step(1041.1,false,{1,2,3}).reason=="audience-left","last participant leaving hides immediately")
check(schedule.Snapshot().due==nil and schedule.Snapshot().visible==nil,"leaving clears pending work")
schedule.Step(5000,true,{1})
check(near(schedule.Snapshot().due,5003),"re-entry gets a fresh short encounter delay")
check(schedule.Step(5003,true,{1}).index==1,"single visible pane remains usable")
check(schedule.Stop().reason=="stopped","cleanup cancels an active appearance")
check(schedule.Stop()==nil,"cleanup is idempotent")
check(schedule.Step(1e9,true,{1,2,3})==nil and not schedule.IsDue(1e9),"destroyed round never restarts")

local seed=17479
local function randomUnit()
	seed=(seed*16807)%2147483647
	return seed/2147483647
end
local fuzz=Encounters.NewSchedule(randomUnit)
local now,last,count,live=0,nil,0,false
fuzz.Step(now,true,{1,2,3})
for _=1,200 do
	local snapshot=fuzz.Snapshot()
	now=snapshot.due
	local event=fuzz.Step(now,true,{1,2,3})
	check(event and event.kind=="show" and not live,"never two simultaneous appearances")
	check(event.index~=last,"variety over 200 visits")
	check(event.endsAt-now>=8 and event.endsAt-now<=14,"duration remains bounded")
	live=true;last=event.index;count+=1
	fuzz.MarkRevealed(now+.25)
	now=fuzz.Snapshot().ends
	local off=fuzz.Step(now,true,{1,2,3})
	check(off and off.kind=="hide" and live,"one hide for each appearance")
	check(off.nextAt-now>=18 and off.nextAt-now<=35,"cooldown remains bounded")
	live=false
end
check(fuzz.Snapshot().count==count,"appearance diagnostics remain accurate")
fuzz.Stop()
check(fuzz.Snapshot().stopped and fuzz.Step(now+100,true,{1,2,3})==nil,"stopped schedule stays inert")

for _,unit in ipairs({0,1}) do
	local edge=fixed(unit)
	edge.Step(0,true,{1,2,3})
	local due=edge.Snapshot().due
	check(due>=2 and due<=4,"first delay range at RNG endpoints")
	local show=edge.Step(due,true,{1,2,3})
	check(show.index>=1 and show.index<=3,"RNG endpoint cannot index outside candidates")
	check(show.endsAt-due>=8 and show.endsAt-due<=14,"duration range at RNG endpoints")
	edge.Stop()
end
print("PASS Window Watcher schedule: "..assertions.." assertions; 200 full appearances; no runtime/asset QA claimed")
