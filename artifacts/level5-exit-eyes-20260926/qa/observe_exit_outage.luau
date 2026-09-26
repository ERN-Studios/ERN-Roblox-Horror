-- Native client QA observer. Reads server originals and streamed instances;
-- writes only its own report attributes, never fixtures, movement or schedules.
local H=game:GetService('HttpService')
local R=game:GetService('RunService')
local RS=game:GetService('ReplicatedStorage')
local P=game:GetService('Players').LocalPlayer
local Lighting=game:GetService('Lighting')
local Logic=require(RS:WaitForChild('Level5OutageLogic'))
local folder=assert(RS:WaitForChild(script:GetAttribute('QAFolderName'),30),'QA baseline folder missing')
local baseline=H:JSONDecode(assert(folder:WaitForChild('ServerBaseline',30)).Value)
local world=assert(workspace:FindFirstChild('Level 5 Generated World'))
local architecture=assert(world:FindFirstChild('Level5_IndoorSuburbs'))
local report={version='2026-09-26.streamed-server-originals.1',token=baseline.token,status='RUNNING',started=workspace:GetServerTimeNow(),
 baselineFixtureCount=#baseline.fixtures,sections={},samples={},failures={},phaseFrames={},ambientFrames={H=0,AG=0},
 scope='Server originals for all fixtures; native comparisons cover each fixture when streamed to this client.'}
local byId,lightById,live,lightLive={},{},{},{}
local streamSince={}
local seen,restored,blackoutSeen={},{},{}
local connections={};local failureKeys={};local triggered,lastSchedule=false,nil
local elapsed,discoverElapsed,sampleElapsed=0,0,0
local lastPosition,lastPositionAt=nil,report.started
local complete=false
for _,entry in ipairs(baseline.fixtures) do
 byId[entry.id]=entry
 local section=tostring(entry.section)
 report.sections[section]=report.sections[section] or {baseline=baseline.sectionCounts[section],frames=0,fixtureComparisons=0,blackoutFrames=0,
  exemptFrames=0,failedTubeComparisons=0,restoredFrames=0,uniqueSeen=0,uniqueBlackout=0,uniqueRestored=0}
 for _,light in ipairs(entry.lights) do lightById[light.id]={base=light,fixtureId=entry.id} end
end
local function connect(signal,callback)local c=signal:Connect(callback);table.insert(connections,c);return c end
local function fail(reason,path)
 local key=reason..':'..tostring(path)
 if failureKeys[key] then return end;failureKeys[key]=true
 if #report.failures<40 then table.insert(report.failures,{reason=reason,path=path,time=workspace:GetServerTimeNow()-report.started}) end
end
local function register(object)
 if not object:IsDescendantOf(architecture) then return end
 local id=object:GetAttribute('Level5ExitQAId')
 if object:IsA('BasePart') and byId[id] then
  if live[id]~=object then streamSince[id]=workspace:GetServerTimeNow() end
  live[id]=object;seen[id]=true
 elseif object:IsA('Light') and lightById[id] then lightLive[id]=object end
end
local function discover()
 for _,object in ipairs(architecture:GetDescendants()) do register(object) end
 for id,object in pairs(live) do if not object:IsDescendantOf(architecture) then live[id]=nil end end
 for id,object in pairs(lightLive) do if not object:IsDescendantOf(architecture) then lightLive[id]=nil end end
end
local function equalColour(a,b)
 return math.abs(a.R-b[1])<.001 and math.abs(a.G-b[2])<.001 and math.abs(a.B-b[3])<.001
end
local function original(id,p)
 local entry=byId[id]
 local changed=p.Material.Name~=entry.material or not equalColour(p.Color,entry.colour)
 local pending=0
 for _,base in ipairs(entry.lights) do
  local light=lightLive[base.id]
  if light and light.Parent==p then
   if light.Enabled~=base.enabled or math.abs(light.Brightness-base.brightness)>.001 then changed=true end
  else pending+=1 end
 end
 return not changed and pending==0,changed,pending
end
local function region(point,minKey,maxKey)
 local lo,hi=baseline[minKey],baseline[maxKey]
 return Logic.ContainsPoint(point.X,point.Y,point.Z,lo[1],lo[2],lo[3],hi[1],hi[2],hi[3])
end
local function exempt(point)
 return region(point,'Level5OutageExemptMin','Level5OutageExemptMax') or region(point,'Level5OutageExitMin','Level5OutageExitMax')
end
local function lightingMismatches(power)
 local mismatches={}
 for key,base in pairs(baseline.lighting) do
  local actual=Lighting[key]
  if type(base)=='table' then
   if not equalColour(actual,{base[1]*power,base[2]*power,base[3]*power}) then table.insert(mismatches,key) end
  elseif math.abs(actual-base*power)>.001 then table.insert(mismatches,key) end
 end
 return mismatches
end
local function updateUniqueCounts()
 for _,section in pairs(report.sections) do section.uniqueSeen=0;section.uniqueBlackout=0;section.uniqueRestored=0 end
 for id in pairs(seen) do report.sections[tostring(byId[id].section)].uniqueSeen+=1 end
 for id in pairs(blackoutSeen) do report.sections[tostring(byId[id].section)].uniqueBlackout+=1 end
 for id in pairs(restored) do report.sections[tostring(byId[id].section)].uniqueRestored+=1 end
end
local function finish(reason,completedCycle)
 if complete then return end;complete=true
 for _,c in ipairs(connections) do c:Disconnect() end
 updateUniqueCounts();report.finished=workspace:GetServerTimeNow();report.duration=report.finished-report.started
 report.reason=reason;report.lastSchedule=lastSchedule;report.restorationMismatches={}
 for id,p in pairs(live) do if p:IsDescendantOf(architecture) then
  local ok,changed,pending=original(id,p)
  if changed then table.insert(report.restorationMismatches,byId[id].path) end
 end end
 local phases=report.phaseFrames
 local fullCycle=completedCycle and report.capturedStart==true and (phases.FALLING or 0)>0 and (phases.BLACKOUT or 0)>0 and (phases.RECOVERING or 0)>0
 local agBlackoutUnique=0;for i=1,7 do agBlackoutUnique+=report.sections[tostring(i)].uniqueBlackout end
 local coverage=report.ambientFrames.H>0 and report.ambientFrames.AG>0 and report.sections['8'].uniqueSeen>0 and agBlackoutUnique>0
 report.status=#report.failures>0 and 'FAIL' or fullCycle and coverage and #report.restorationMismatches==0 and 'PASS' or 'INCONCLUSIVE'
 report.fullCycleObserved=fullCycle;report.boundaryAmbientCoverage=coverage
 script:SetAttribute('Report',H:JSONEncode(report))
 script:SetAttribute('Summary',H:JSONEncode({status=report.status,reason=reason,duration=report.duration,baselineFixtures=report.baselineFixtureCount,
  phaseFrames=report.phaseFrames,ambientFrames=report.ambientFrames,sections=report.sections,failures=report.failures,
  restorationMismatches=report.restorationMismatches,fullCycleObserved=fullCycle,lastSchedule=lastSchedule}))
 script:SetAttribute('Status',report.status)
end
discover()
connect(architecture.DescendantAdded,register)
connect(architecture.DescendantRemoving,function(object)
 local id=object:GetAttribute('Level5ExitQAId')
 if live[id]==object then live[id]=nil end
 if lightLive[id]==object then lightLive[id]=nil end
end)
connect(R.Heartbeat,function(dt)
 if complete then return end
 elapsed+=dt;discoverElapsed+=dt;sampleElapsed+=dt
 if elapsed<.15 then return end;elapsed=0
 local now=workspace:GetServerTimeNow()
 if world.Parent~=workspace or not architecture:IsDescendantOf(world) then finish('World removed before completed cycle',false);return end
 if discoverElapsed>=.5 then discoverElapsed=0;discover() end
 local encoded=world:GetAttribute('Level5OutageSchedule')
 local schedule
 if type(encoded)=='string' then local ok,value=pcall(H.JSONDecode,H,encoded);if ok and Logic.ValidateSchedule(value) then schedule=value end end
 if schedule then
  if not triggered then report.capturedStart=schedule.startedAt>=report.started-.3 end
  lastSchedule=schedule;triggered=true
 end
 local phase=Logic.Phase(schedule,now)
 report.phaseFrames[phase]=(report.phaseFrames[phase] or 0)+1
 local character=P.Character;local rootPart=character and character:FindFirstChild('HumanoidRootPart')
 local position=rootPart and rootPart.Position
 if position and (not lastPosition or (position-lastPosition).Magnitude>8) then lastPositionAt=now end
 lastPosition=position
 local stablePosition=position and now-lastPositionAt>.5
 local inExit=position and exempt(position)
 local black=schedule and now>schedule.blackoutAt+.4 and now<schedule.restoreAt
 local expired=triggered and not schedule and encoded==nil and lastSchedule and now>lastSchedule.restoreAt+Logic.RESTORE_SECONDS+.4
 local visible,changedTotal,pendingTotal=0,0,0
 local sectionFrame={};local allVisibleRestored=true
 for id,p in pairs(live) do if p:IsDescendantOf(architecture) then
  local entry=byId[id];visible+=1;seen[id]=true
  local section=tostring(entry.section);local stats=report.sections[section]
  local ok,changed,pending=original(id,p);pendingTotal+=pending
  if changed then changedTotal+=1 end
  if not ok then allVisibleRestored=false end
  stats.fixtureComparisons+=1;sectionFrame[section]=true
  if entry.dead then stats.failedTubeComparisons+=1 end
  if (entry.section==8 or entry.dead) and changed then fail(entry.section==8 and 'H fixture changed' or 'Originally failed tube changed',entry.path) end
  if entry.section==8 then stats.exemptFrames+=1 end
  if black and entry.section<=7 and not entry.dead and now-(streamSince[id] or now)>.4 then
   blackoutSeen[id]=true
   if p.Material==Enum.Material.Neon then fail('A-G emissive fixture remained on',entry.path) end
   for _,lightBase in ipairs(entry.lights) do local light=lightLive[lightBase.id]
    if light and light.Parent==p and light.Enabled and light.Brightness>.001 then fail('A-G light remained on',entry.path..'.'..lightBase.name) end
   end
  end
  if expired and ok then restored[id]=true;stats.restoredFrames+=1 end
 end end
 for section in pairs(sectionFrame) do
  report.sections[section].frames+=1
  if black then report.sections[section].blackoutFrames+=1 end
 end
 if black and stablePosition then
  local target=inExit and 1 or 0
  local zone=inExit and 'H' or 'AG';report.ambientFrames[zone]+=1
  for _,key in ipairs(lightingMismatches(target)) do fail(inExit and 'H ambient darkened' or 'A-G ambient did not black out',zone..'.'..key) end
 end
 if sampleElapsed>=1 then
  sampleElapsed=0;table.insert(report.samples,{t=math.round((now-report.started)*100)/100,phase=phase,visualPhase=world:GetAttribute('Level5OutageVisualPhase'),
   relative=schedule and now-schedule.startedAt,brightness=Lighting.Brightness,zone=inExit and 'H' or 'AG',streamed=visible,changed=changedTotal,pendingLights=pendingTotal,
   position=position and {position.X,position.Y,position.Z}})
 end
 script:SetAttribute('Status','RUNNING');script:SetAttribute('SampleCount',#report.samples);script:SetAttribute('StreamedFixtureCount',visible)
 if expired and visible>0 and allVisibleRestored and pendingTotal==0 and #lightingMismatches(1)==0 then
  finish('Schedule expired; all currently streamed originals restored',true)
 elseif now-report.started>300 then finish('300-second deadline; full expiry/restoration not observed',false) end
end)
