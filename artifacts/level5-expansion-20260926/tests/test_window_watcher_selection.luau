local E=require("../../../ServerScriptService/Level 5 Systems/Level 5 Window Watcher Encounters.ModuleScript")
local assertions=0
local function check(condition,message) assertions+=1;assert(condition,message) end
local nan=0/0
check(E.ViewQuality(20,1,-5)>0,"forward exterior player qualifies")
for _,sample in ipairs({{2.99,1,-5},{145.01,1,-5},{20,-1,-5},{20,0,-5},{20,1,0},{20,1,-.8}, {math.huge,1,-5},{20,nan,-5}}) do
 check(E.ViewQuality(table.unpack(sample))==nil,"behind/inside/range/nonfinite rejection")
end
check(E.ViewQuality(145,math.cos(math.rad(70)),-.801)>0,"documented broad-cone boundary")
local close=E.ViewQuality(10,1,-5)
local edge=E.ViewQuality(140,math.cos(math.rad(70)),-5)
check(close>edge and edge>0,"center/near sightlines earn higher quality")
check(E.CandidateScore(2,edge*2)>E.CandidateScore(1,close),"two confirmed viewers outrank any one viewer")
check(E.CandidateScore(3,edge*3)>E.CandidateScore(2,close*2),"three confirmed viewers outrank any two")
check(E.CandidateScore(0,1)==0 and E.CandidateScore(1,0)==0,"invisible windows cannot get weight")
check(E.ChooseCandidate({},nil,.5)==nil,"no eligible window means no spawn")
check(E.ChooseCandidate({{index=1,score=0},{index=2,score=nan}},nil,.2)==nil,"reject invalid scores")
for _,r in ipairs({0,.2,.5,.99999999,1}) do
 check(E.ChooseCandidate({{index=1,score=1000},{index=2,score=1}},1,r)==2,"last window avoided whenever another valid one exists")
 check(E.ChooseCandidate({{index=1,score=1000}},1,r)==1,"single valid window remains usable")
end
local selection={{index=1,score=E.CandidateScore(1,1),viewers=1},{index=2,score=E.CandidateScore(2,2),viewers=2}}
local hits={0,0}
for i=1,1000 do local n=E.ChooseCandidate(selection,nil,(i-.5)/1000);hits[n]+=1 end
check(hits[1]==200 and hits[2]==800,"group-weighted choice exactly follows 1:4 weights")
local schedule=E.NewSchedule(function() return .5 end)
schedule.Step(0,true,selection)
local show=schedule.Step(3,true,selection)
check(show.index==2 and show.viewers==2 and show.score==4,"real scheduler keeps weighted viewer diagnostics")
schedule.MarkRevealed(3.25)
check(schedule.Snapshot().ends==14.25,"map-wide selection preserves complete warmup-adjusted duration")
schedule.Step(14.25,true,selection)
local again=schedule.Step(40.75,true,selection)
check(again.index==1,"non-repeat weighting is used by actual schedule")
schedule.Stop();check(schedule.Step(100,true,selection)==nil,"stopped selector cannot spawn")
print("PASS map-wide selection: "..assertions.." assertions, 1000 exact weighted samples; pure logic only")
