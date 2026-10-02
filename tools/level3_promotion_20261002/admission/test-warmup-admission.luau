-- Virtual-clock execution of the exact helper, runtime, routing and GM fragments.
-- No Studio instance, engine mesh bake, gameplay or performance claim.
local fs, luau, serde = require("@lune/fs"), require("@lune/luau"), require("@lune/serde")
local root = "tools/level3_promotion_20261002/admission/"
local manifest = serde.decode("json", fs.readFile(root.."candidate-manifest.json"))
local gm, warmSource
local receipt = {Scope="Offline virtual scheduler and mocked players only; actual Bake/Studio gameplay unverified", Checks=0, SchedulerSteps=0, Scenarios={}, Sources={}}
local function check(value, message) receipt.Checks += 1; assert(value, message) end
for _, change in ipairs(manifest.changes) do
 local source = fs.readFile(change.candidateFile)
 check(serde.hash("sha256",source)==change.candidateSHA256,"candidate hash")
 luau.compile(source)
 table.insert(receipt.Sources,{Path=change.path,SHA256=change.candidateSHA256,Syntax="PASS"})
 if change.new then warmSource=source else gm=source end
end
local Loading=luau.load(fs.readFile(root.."ServerScriptService.Round Loading Runtime.ModuleScript.baseline.luau"))()
local Routing=luau.load(fs.readFile(root.."ServerScriptService.Round Completion Routing.ModuleScript.baseline.luau"))()
local function fragment(source, first, following)
 local a=assert(source:find(first,1,true));local b=assert(source:find(following,a+1,true))
 return source:sub(a,b-1)
end
local beginSource=fragment(gm,"local function beginGroupLoading(","local function prepareGroupLoading(")
local stationSource="local function launchStation(station, participants)\n"..fragment(gm,
 " if not canAccessLevel(station.level or 1, participants) then return end\n station.busy = true",
 "-- A facelift preview runs")
local campaignSource=fragment(gm,"local function continueStudioCampaign(","playRound = function(")
local stageSource=fragment(gm,"local function stageArrivingParty(","if IS_RESERVED_ROUND_SERVER then\n task.spawn(function()\n  -- Hold characters")
local cancelSource=fragment(gm,"queueConfig.OnServerEvent:Connect(function(","local function connectElevator(")
local function scheduler()
 local s={now=0,serial=0,jobs={}}
 function s:enqueue(at,co,args)
  self.serial+=1;table.insert(self.jobs,{at=at,co=co,args=args,serial=self.serial})
 end
 function s:spawn(fn,...)
  local co=coroutine.create(fn);self:enqueue(self.now,co,table.pack(...));return co
 end
 function s:delay(seconds,fn,...)
  local co=coroutine.create(fn);self:enqueue(self.now+seconds,co,table.pack(...));return co
 end
 function s:run(untilDone,limit)
  local count=0
  while not untilDone() do
   table.sort(self.jobs,function(a,b)return a.at<b.at or (a.at==b.at and a.serial<b.serial)end)
   local j=table.remove(self.jobs,1);assert(j,"scheduler exhausted")
   assert(j.at<=limit,"scenario virtual deadline");receipt.SchedulerSteps+=1
   self.now=j.at;local ok,wait=coroutine.resume(j.co,table.unpack(j.args,1,j.args.n));assert(ok,wait)
   if coroutine.status(j.co)~="dead" then self:enqueue(self.now+(wait or .01),j.co,table.pack())end
   count+=1;assert(count<30000,"unbounded scheduler")
  end
 end
 s.task={spawn=function(fn,...)return s:spawn(fn,...)end,delay=function(t,fn,...)return s:delay(t,fn,...)end,
  wait=function(t)return coroutine.yield(t or .01)end}
 return s
end
local function fixture(bakeSeconds,options)
 options=options or {};local s=scheduler();local f={s=s,attrs={},calls={},recoveries={},begins=0,prepared=0,cleaned=0,rounds=0,players={}}
 local players={};function players:GetPlayers()return table.clone(f.players)end;f.Players=players
 local workspace={};function workspace:SetAttribute(k,v)f.attrs[k]=v;table.insert(f.calls,{kind="attribute",key=k,value=v,time=s.now})end
 function workspace:GetServerTimeNow()return 10000+s.now end;f.workspace=workspace
 local kit
 local function install()
  kit={};function kit:IsA(c)return c=="Folder"end
  function kit:GetAttribute(k)return if k=="Ready" then true elseif k=="BlenderSourceSHA256" then "d2eddfce3820a27f01cdd53b93b719ec8bf8d048b9313bc6cdf29610344acc6b" else nil end
 end
 if options.ready then install()end
 local module={};function module:IsA(c)return c=="ModuleScript"end
 local systems={};function systems:FindFirstChild(n)return n=="Level6BlenderRuntimeBake" and module or nil end
 local storage={};function storage:FindFirstChild(n)return n=="Level6BlenderKit" and kit or nil end
 local ss={};function ss:FindFirstChild(n)return n=="Level 6 Systems" and systems or nil end
 local services={ServerStorage=storage,ServerScriptService=ss,RunService={IsClient=function()return false end}}
 local bakeCalls=0
 local bake={Ensure=function()
  bakeCalls+=1;s.task.wait(bakeSeconds)
  if options.fail then error("mock engine bake failed")end
  install()
 end}
 f.Warmup=luau.load(warmSource,{environment={game={GetService=function(_,n)return services[n]end},workspace=workspace,
  os={clock=function()return s.now end},task=s.task,require=function(m)assert(m==module)return bake end,warn=function()end}})()
 f.bakeCalls=function()return bakeCalls end
 f.runtime=Loading.New({Now=function()return s.now end,Delay=s.task.delay,Spawn=s.task.spawn,Wait=s.task.wait,
  Present=function(p)return p.Parent==players end,Prepare=function()end,Validate=function()return true end,
  Failed=function(a,r)table.insert(f.recoveries,{attempt=a,reason=r,time=s.now})end})
 local runtime={Begin=function(_,group)f.begins+=1;f.beginAt=s.now;return f.runtime:Begin(group)end}
 function f:player(id)
  local p={UserId=id,Parent=players,inside=true,attrs={}}
  local hum={Health=100};local character={};function character:FindFirstChildOfClass(c)return c=="Humanoid" and hum or nil end
  function p:GetAttribute(k)return self.attrs[k]end;function p:SetAttribute(k,v)self.attrs[k]=v end
  p.Character=character;p.hum=hum;table.insert(f.players,p);return p
 end
 function f:station(p,level)
  local z={};function z:IsDescendantOf(w)return w==workspace and not z.retired end
  return {level=level or 3,host=p,zone=z,admissionEpoch=8,index=p.UserId,maxPlayers=6,color={}}
 end
 local source="local activeEntry = initialEntry\nlocal roundBusy = initialBusy or false\nlocal failedReservedEntry=false\n"
  .."local function recoverFailedEntry(a,r,g) recordRecovery(a,r,g);roundBusy=false end\n"
  ..beginSource..stationSource..campaignSource..stageSource
  .."return {Begin=beginGroupLoading,Station=launchStation,Campaign=continueStudioCampaign,Stage=stageArrivingParty,Target=reservedEntryTarget,"
  .."Entry=function()return activeEntry end,Replace=function(a)activeEntry=a end,Busy=function()return roundBusy end,SetBusy=function(v)roundBusy=v end}"
 f.entries={};f.evidence={}
 local environment={initialEntry=options.initialEntry,initialBusy=options.initialBusy,loadingRuntime=runtime,
  Level3KitWarmup=f.Warmup,workspace=workspace,Players=players,IS_STUDIO=options.studio~=false,IS_RESERVED_ROUND_SERVER=options.reserved==true,
  fireGroup=function(group,event,...)table.insert(f.calls,{kind="event",event=event,group=table.clone(group),time=s.now})end,
  loadingFailures={},canAccessLevel=function()return not f.denied end,livePlayers=function(group)local live={}for _,p in ipairs(group)do if p.Parent==players then table.insert(live,p)end end return live end,
  playerInsideZone=function(p,_,includeBusy)assert(includeBusy==true)return p.inside end,
  setStationDisplay=function(_,title,sub)table.insert(f.calls,{kind="display",title=title,sub=sub,time=s.now})end,
  recordRecovery=function(a,r,g)table.insert(f.recoveries,{attempt=a,reason=r,group=g,time=s.now})end,
  task=s.task,os={clock=function()return s.now end},warn=function()end,Color3={fromRGB=function()return {}end},
  clearGlowsticks=function()end,assignGlowstickSlots=function()end,MAX_PLAYERS_PER_STATION=6,LEVEL_TWO_TUBE_ENTRY_MODE="level2tube",
  prepareGroupLoading=function(a,group,level,resume)f.prepared+=1;f.preparedLevel=level;f.resume=resume;s.task.wait(options.prepareSeconds or 1);a.State="ready";return true end,
  playRound=function()f.rounds+=1 end,cleanupActiveWorld=function()f.cleaned+=1 end,returnGroupToLobby=function()f.cleaned+=1 end,
  Loading=Loading,Routing=Routing,arrivalEntries=function()return table.clone(f.entries)end,destinationArrivalEvidence=f.evidence,
  cohortMap={GetAsync=function()return f.snapshot end},print=function()end}
 f.host=luau.load(source,{environment=environment})()
 return f
end
local function scenario(name,fn)
 local prior=receipt.Checks;fn();table.insert(receipt.Scenarios,{Name=name,Checks=receipt.Checks-prior,Passed=true})
end
scenario("cold public3 gets fresh60s after130s singleton warmup",function()
 local f=fixture(130);local p=f:player(1);local a,b,done1,done2
 f.Warmup.Start();f.Warmup.Start()
 f.s:spawn(function()a=f.host.Begin({p},3,function()return true end);done1=true end)
 f.s:spawn(function()b=f.Warmup.Await(function()return true end);done2=true end)
 f.s:run(function()return done1 and done2 end,131)
 check(a and b and a.State=="loading","cold successful");check(f.begins==1 and f.bakeCalls()==1,"one mesh warm and one entry")
 check(f.beginAt>=130 and math.abs(a:Remaining()-60)<.001,"fresh60s after cold wait")
 check(f.attrs.RoundLoadingState=="loading","warming transitions loading")
 for _,call in ipairs(f.calls)do if call.kind=="attribute" then check(call.key~="RoundActive" and call.key~="InRound","helper has no gameplay mutation")end end
end)
for _,level in ipairs({1,2})do
 scenario("Level"..level.." starts immediately while shared job is cold",function()
  local f=fixture(130);local p=f:player(level);f.Warmup.Start();local a=f.host.Begin({p},level)
  check(f.begins==1 and f.beginAt==0 and a.Deadline==60,"unrelated local entry deadline unchanged")
 end)
end
scenario("already ready kit skips Ensure",function()
 local f=fixture(130,{ready=true});local p=f:player(1);local a=f.host.Begin({p},3)
 check(a.Deadline==60 and f.bakeCalls()==0,"ready fast path no bake")
end)
for _,mutation in ipairs({"stepout","departure","character","death","epoch","host","cancel","access","retired"})do
 scenario("cold station cancels on "..mutation,function()
  local f=fixture(130);local p=f:player(1);local st=f:station(p);local done=false
  f.s:spawn(function()f.host.Station(st,{p});done=true end)
  f.s:delay(1,function()
   if mutation=="stepout" then p.inside=false elseif mutation=="departure" then p.Parent=nil elseif mutation=="character" then p.Character=table.clone(p.Character)
   elseif mutation=="death" then p.hum.Health=0 elseif mutation=="epoch" then st.admissionEpoch+=1 elseif mutation=="host" then st.host={}
   elseif mutation=="cancel" then st.cancelRequested=true elseif mutation=="access" then f.denied=true elseif mutation=="retired" then st.zone.retired=true end
  end)
  f.s:run(function()return done end,1.5)
  check(f.begins==0 and f.prepared==0 and not st.busy and not st.kitWarming,"cancel does not launch or retain busy")
  check(not f.host.Busy(),"cancel does not acquire global round")
  local closed,notice=false,false
  for _,call in ipairs(f.calls)do closed=closed or call.event=="queueconfigclosed";notice=notice or(call.title=="PREPARING LEVEL 3" and call.sub=="STEP OUT TO CANCEL")end
  check(closed and notice,"waiting UI closes queue and exposes cancellation")
 end)
end
scenario("competing cold Studio stations produce one world",function()
 local f=fixture(130);local p,q=f:player(1),f:player(2);local a,b=f:station(p),f:station(q);local done=0
 f.s:spawn(function()f.host.Station(a,{p});done+=1 end);f.s:spawn(function()f.host.Station(b,{q});done+=1 end)
 f.s:run(function()return done==2 end,132)
 check(f.bakeCalls()==1 and f.begins==1 and f.prepared==1 and f.rounds==1,"atomic postwarm round lock")
 check(not a.busy and not b.busy and not f.host.Busy(),"both station lifecycle flags released")
end)
scenario("Level1 can enter while public3 waits",function()
 local f=fixture(130);local p,q=f:player(1),f:player(2);local a,b=f:station(p),f:station(q,1);local done=0
 f.s:spawn(function()f.host.Station(a,{p});done+=1 end)
 f.s:delay(.5,function()f.host.Station(b,{q});done+=1 end)
 f.s:run(function()return done==2 end,2)
 check(f.begins==1 and f.preparedLevel==1 and f.beginAt==.5,"level1 neither waits nor loses reservation")
 check(not a.busy and not a.kitWarming,"public3 cancelled when another round owns Studio")
end)
scenario("caller replacement cannot fail a newer entry",function()
 local owner={State="ready"};local f=fixture(130,{initialEntry=owner});local p=f:player(1);local done,result=false,nil
 local newer={State="loading"};f.s:spawn(function()result=f.host.Begin({p},3);done=true end)
 f.s:delay(1,function()f.host.Replace(newer)end);f.s:run(function()return done end,1.5)
 check(not result and f.begins==0 and #f.recoveries==0 and f.host.Entry()==newer,"stale caller neither begins nor recovers new owner")
end)
scenario("all campaign continuers depart before kit ready",function()
 local prior={State="ready"};local f=fixture(130,{initialEntry=prior,initialBusy=true});local p=f:player(1);local done=false
 f.s:spawn(function()f.host.Campaign({p},{p},{},3,"level2tube");done=true end)
 f.s:delay(1,function()check(f.cleaned==0 and prior.State=="ready","completedLevel2 retained during wait");p.Parent=nil end)
 f.s:run(function()return done end,1.5)
 check(f.begins==0 and f.prepared==0 and #f.recoveries==1 and not f.host.Busy(),"empty campaign recovered without new entry")
 check(prior.State=="ready","previous ready attempt not failed")
end)
scenario("successful tube continuation cleans only after warm",function()
 local prior={State="ready"};local f=fixture(130,{initialEntry=prior,initialBusy=true});local p=f:player(1);local done=false
 f.s:spawn(function()f.host.Campaign({p},{p},{},3,"level2tube");done=true end)
 f.s:delay(100,function()check(f.cleaned==0 and f.begins==0,"Level2 safe floor remains for cold wait")end)
 f.s:run(function()return done end,132)
 check(f.cleaned==1 and f.prepared==1 and f.resume and f.rounds==1,"tube mode preserved after postwarm cleanup")
end)
for _,kind in ipairs({"failed","timeout"})do
 scenario("warm "..kind.." stays bounded and late completion cannot launch cancelled party",function()
  local f=fixture(kind=="failed" and 3 or 1250,{fail=kind=="failed"});local p=f:player(1);local st=f:station(p);local done=false
  f.s:spawn(function()f.host.Station(st,{p});done=true end);f.s:run(function()return done end,1201)
  check(f.begins==0 and not st.busy and not st.kitWarming,"failed warm releases queue")
  check(f.attrs.Level3KitState==kind or(kind=="timeout" and f.attrs.Level3KitState=="timeout"),"published warm status")
  if kind=="timeout" then
   f.s:run(function()return f.Warmup.Status().Ready end,1251)
   check(f.begins==0 and f.rounds==0 and f.bakeCalls()==1,"late shared completion cannot resurrect cohort")
  end
 end)
end
for _,level in ipairs({1,2,3})do
 scenario("reserved target"..level.." discovery retains appropriate deadline",function()
  local f=fixture(130,{reserved=true});local p=f:player(1);local done=false;local a,group
  f.entries={{Member=p,Data={Level=3}}} -- untrusted raw Level must not select a target.
  f.Warmup.Start()
  f.s:delay(8,function()f.entries={{Member=p,Data=Routing.ArrivalPacket({Level=level,SessionId="trusted",Expected=1,Final=true})}}end)
  f.s:spawn(function()
   local target,original,start=f.host.Target();group=target
   a=f.host.Begin({},target.Level,function()return true end,target.Level~=3 and original or nil)
   local decision=f.host.Stage(a,target.Level~=3 and start or nil,target.Level==3 and target or nil)
   check(decision=="admit","validated final target admitted through existing tracker");done=true
  end)
  f.s:run(function()return done end,131)
  check(group.SessionId=="trusted" and group.Level==level,"raw first packet ignored")
  check(level==3 and a:Remaining()>59.9 or level~=3 and a.Deadline==60,"3 fresh60 / 1-2 absoluteboot60")
 end)
end
scenario("reserved warm retains arrival evidence for departed final carrier",function()
 local f=fixture(130,{reserved=true});local p,q=f:player(1),f:player(2);local done=false
 local packet=Routing.ArrivalPacket({Level=3,SessionId="cohort",Expected=2,Final=true})
 local early={Member=p,Data=packet};f.entries={early};table.insert(f.evidence,early)
 f.s:delay(10,function()p.Parent=nil;f.entries={}end)
 f.s:delay(120,function()local late={Member=q,Data=Routing.ArrivalPacket({Level=3,SessionId="cohort",Expected=2,Final=false})};f.entries={late};table.insert(f.evidence,late)end)
 f.s:spawn(function()
  local target=f.host.Target();local a=f.host.Begin({},3,function()return true end)
  local decision,group=f.host.Stage(a,nil,target)
  check(decision=="admit" and group.Final and group.Expected==1 and group.Members[1]==q,"departed carrier retained then subtracted once")
  done=true
 end)
 f.s:run(function()return done end,131)
end)
scenario("reserved changed session cannot hijack warmed target",function()
 local f=fixture(130,{reserved=true});local p=f:player(1);local done=false
 f.entries={{Member=p,Data=Routing.ArrivalPacket({Level=3,SessionId="first",Expected=1,Final=true})}}
 f.s:delay(10,function()f.entries={{Member=p,Data=Routing.ArrivalPacket({Level=2,SessionId="replacement",Expected=1,Final=true})}}end)
 f.s:spawn(function()
  local target=f.host.Target();local a=f.host.Begin({},3,function()return true end);local decision=f.host.Stage(a,nil,target)
  check(decision=="abandon" and a.Reason=="ARRIVAL_SESSION_CHANGED","first trusted session+level pinned");done=true
 end);f.s:run(function()return done end,131)
end)
scenario("reserved first provisional packet still waits for final full cohort",function()
 local f=fixture(130,{reserved=true});local p,q=f:player(1),f:player(2);local done=false
 local early={Member=p,Data=Routing.ArrivalPacket({Level=3,SessionId="pending",Expected=2,Final=false,Deadline=10015})}
 f.entries={early};table.insert(f.evidence,early)
 f.s:delay(135,function()
  check(not done,"first packet cannot admit before final snapshot")
  f.snapshot=Loading.CohortSnapshot("pending",3,{1,2})
 end)
 f.s:delay(140,function()
  check(not done,"final snapshot cannot admit missing member")
  local later={Member=q,Data=Routing.ArrivalPacket({Level=3,SessionId="pending",Expected=2,Final=false,Deadline=10015})}
  table.insert(f.entries,later);table.insert(f.evidence,later)
 end)
 f.s:spawn(function()
  local target=f.host.Target();local a=f.host.Begin({},3,function()return true end)
  local decision,group=f.host.Stage(a,nil,target)
  check(decision=="admit" and group.Final and group.Expected==2 and #group.Members==2,"actual tracker and snapshot admit full cohort")
  check(a.Deadline>189.9 and f.s.now>=140,"fresh entry deadline includes full staging")
  done=true
 end);f.s:run(function()return done end,141)
end)
scenario("busy public warm accepts only its host cancel",function()
 local handler;local event={Connect=function(_,fn)handler=fn end};local Players={};local p={Character=nil};local other={}
 local station={host=p,busy=true,kitWarming=true,admissionEpoch=7};local stations={station}
 luau.load(cancelSource,{environment={queueConfig={OnServerEvent=event},IS_RESERVED_ROUND_SERVER=false,lobbyStations=stations,
  playerInsideZone=function()error("cancel should precede admission")end,Vector3={zero={}}}})()
 handler(other,1,nil,"cancel");check(not station.cancelRequested,"nonhost cannot cancel")
 handler(p,1,nil,"friends");check(not station.cancelRequested,"busy warming cannot reconfigure")
 handler(p,1,nil,"cancel");check(station.cancelRequested and station.admissionEpoch==8,"host public cancel invalidates own epoch")
 station.cancelRequested=nil;station.kitWarming=nil;handler(p,1,nil,"cancel");check(not station.cancelRequested,"unrelated busy public queue contract unchanged")
end)
local baseline=fs.readFile(root.."ServerScriptService.GameManager.Script.baseline.luau")
check(fragment(gm,"local function launchStation(station, participants)"," if not canAccessLevel(station.level or 1, participants) then return end\n station.busy = true")
 ==fragment(baseline,"local function launchStation(station, participants)"," if not canAccessLevel(station.level or 1, participants) then return end\n station.busy = true"),"5/6 DEV preview launch branch byte-identical")
check(fragment(gm,"local function launchBlenderPreview(player)","local function resetStation(")
 ==fragment(baseline,"local function launchBlenderPreview(player)","local function resetStation("),"Level1 developer launch unchanged")
receipt.Passed=true
fs.writeFile(root.."warmup-admission-test-receipt-v2.json",serde.encode("json",receipt,true).."\n")
print(serde.encode("json",receipt,true))
