-- Exact final-cohort writer under a virtual expiring store; no live transport claim.
local fs,luau,serde=require("@lune/fs"),require("@lune/luau"),require("@lune/serde")
local root="tools/level3_promotion_20261002/admission/"
local m=serde.decode("json",fs.readFile(root.."post-review/candidate-manifest.json")).changes[1]
local candidate=fs.readFile(m.candidateFile)
assert(serde.hash("sha256",candidate)==m.candidateSHA256);luau.compile(candidate)
local baseline=fs.readFile(root.."ServerScriptService.GameManager.Script.candidate.v3.luau")
assert(serde.hash("sha256",baseline)==m.baselineSHA256)
local warm=fs.readFile(root.."Level 3 Kit Warmup.ModuleScript.candidate.luau")
assert(serde.hash("sha256",warm)=="870130d1282ed11df29998e286221a6597cc8d9e40e62baad5f957d020dfc72c")
local timeout=assert(tonumber(warm:match("Warmup.TimeoutSeconds = (%d+)")))
local Loading=luau.load(fs.readFile(root.."ServerScriptService.Round Loading Runtime.ModuleScript.baseline.luau"))()
local Routing=luau.load(fs.readFile(root.."ServerScriptService.Round Completion Routing.ModuleScript.baseline.luau"))()
local receipt={Scope="Offline exact cohort writer / actual pure routing and loading, virtual MemoryStore TTL only",CandidateSHA256=m.candidateSHA256,Checks=0,Levels={}}
local function check(v,label)receipt.Checks+=1;assert(v,label)end
local function writer(source)
 local a=assert(source:find('local cohortMap = MemoryStoreService:GetHashMap(',1,true))
 local b=assert(source:find('game:BindToClose(function()',a,true))
 local now,record,calls=0,nil,0
 local map={}
 function map:SetAsync(key,value,ttl)calls+=1;record={Key=key,Value=value,Expires=now+ttl,TTL=ttl};return true end
 function map:GetAsync(key)return record and key==record.Key and now<record.Expires and record.Value or nil end
 local publish=luau.load(source:sub(a,b-1).."\nreturn publishFinalCohort",{environment={
  MemoryStoreService={GetHashMap=function(_,name)assert(name=="RoundArrivalCohortsV1");return map end},
  IS_STUDIO=false,Loading=Loading,Routing=Routing,Level3KitWarmup={TimeoutSeconds=timeout},
  task={spawn=function(fn)fn()end,wait=function(dt)now+=dt end},os={clock=function()return now end},
  stillHere=function()return false end,warn=function()error("unexpected write failure")end}})()
 return {Publish=publish,Map=map,Clock=function(t)now=t end,Record=function()return record end,Calls=function()return calls end}
end
local p,q={UserId=71},{UserId=72}
local function session(level)
 local roster=Routing.NewRoster({p,q})
 check(Routing.RecordDecision(roster,p,Routing.Continuing),"p manual continue")
 check(Routing.RecordDecision(roster,q,Routing.Continuing),"q manual continue")
 Routing.MarkDeparted(roster,p);Routing.MarkDeparted(roster,q)
 return {Id="manual:"..level,NextLevel=level,Roster=roster}
end
local function decision(w,s,at)
 w.Clock(at)
 local entries={}
 for _,member in ipairs({p,q})do table.insert(entries,{Member=member,Data=Routing.ArrivalPacket({Level=s.NextLevel,SessionId=s.Id,Expected=2,Final=false,Deadline=15})})end
 local group=Routing.SelectArrivalSession(entries)
 check(not group.Final,"both departed source members carry only provisional packets")
 local ids,count=Loading.ReadCohort(w.Map:GetAsync(s.Id),s.Id,s.NextLevel)
 if ids then group.Expected=count;group.Final=true;group.CohortUserIds=ids end
 local tracker=Loading.NewArrivalTracker(Routing.SelectArrivalSession);tracker:Observe(entries);group=tracker:Apply(group)
 return Routing.ArrivalDecision({Now=at,LoadingDeadline=at+60,Arrived=#group.Members,Expected=group.Expected,Final=group.Final})
end
local old=writer(baseline);local s=session(3);old.Publish(s)
check(old.Record().TTL==120,"exact installed baseline expires at120")
check(decision(old,s,130)=="wait","regression:130s cold kit loses final cohort in old writer")
for _,level in ipairs({1,2,3})do
 local w=writer(candidate);local cohort=session(level);w.Publish(cohort);w.Publish(cohort)
 check(w.Calls()==1,"one cohort writer per session")
 local ttl=w.Record().TTL
 check(ttl==(level==3 and 1320 or 120),"only public3 TTL changes")
 check(decision(w,cohort,60)=="admit","usual admission stays valid")
 if level==3 then
  for _,at in ipairs({130,1200,1259})do check(decision(w,cohort,at)=="admit","cold warm+entry still sees final cohort")end
  w.Clock(1320);check(w.Map:GetAsync(cohort.Id)==nil,"new TTL remains bounded")
 else w.Clock(130);check(w.Map:GetAsync(cohort.Id)==nil,"other levels keep120s expiry")end
 table.insert(receipt.Levels,{Level=level,TTL=ttl,Passed=true})
end
receipt.Passed=true
fs.writeFile(root.."post-review/cohort-ttl-test-receipt.json",serde.encode("json",receipt,true).."\n")
print(serde.encode("json",receipt,true))
