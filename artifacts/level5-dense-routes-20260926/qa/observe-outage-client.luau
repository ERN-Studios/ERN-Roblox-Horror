local H=game.HttpService
local R=game:GetService('RunService')
local world=assert(workspace:FindFirstChild('Level 5 Generated World'))
local root=assert(world:FindFirstChild('Level5_IndoorSuburbs'))
local lighting=game.Lighting
local names={FluorescentPanel=true,SuspendedSharedFluorescent=true,SharedLowDomesticPanel=true,LastFluorescent=true}
if _G.Level5OutageObserver and _G.Level5OutageObserver.connection then _G.Level5OutageObserver.connection:Disconnect() end
local qa={samples={},fixtures={},started=workspace:GetServerTimeNow(),done=false,failures={},phaseCounts={}}
_G.Level5OutageObserver=qa
for _,v in ipairs(root:GetDescendants()) do
 if v:IsA('BasePart') and names[v.Name] then
  local entry={part=v,name=v.Name,colour=v.Color,material=v.Material,lights={},originallyOff=v:GetAttribute('TubeState')=='Off' or v:GetAttribute('FailedTube')==true}
  for _,l in ipairs(v:GetChildren()) do if l:IsA('Light') then entry.lights[l]={enabled=l.Enabled,brightness=l.Brightness} end end
  table.insert(qa.fixtures,entry)
 end
end
local elapsed=0
qa.connection=R.Heartbeat:Connect(function(dt)
 elapsed+=dt;if elapsed<.1 then return end;elapsed=0
 local now=workspace:GetServerTimeNow();local encoded=world:GetAttribute('Level5OutageSchedule')
 local s=encoded and H:JSONDecode(encoded) or nil
 local phase=world:GetAttribute('Level5OutageVisualPhase') or 'NORMAL'
 qa.phaseCounts[phase]=(qa.phaseCounts[phase] or 0)+1
 if s then qa.lastSchedule=s;qa.triggered=true end
 local sample={time=now,phase=phase,relative=s and now-s.startedAt or nil,brightness=lighting.Brightness,ambient={lighting.Ambient.R,lighting.Ambient.G,lighting.Ambient.B},neon=0,lit=0,offChanged=0,sections={}}
 for _,e in ipairs(qa.fixtures) do
  local p=e.part
  if p:IsDescendantOf(world) then
   local section=p:GetAttribute('Level5OutageSection') or 0
   local z=sample.sections[tostring(section)] or {total=0,neon=0};sample.sections[tostring(section)]=z;z.total+=1
   if p.Material==Enum.Material.Neon then sample.neon+=1;z.neon+=1 end
   for l,b in pairs(e.lights) do if l.Parent and l.Enabled and l.Brightness>0 then sample.lit+=1 end end
   if e.originallyOff and (p.Material~=e.material or math.max(math.abs(p.Color.R-e.colour.R),math.abs(p.Color.G-e.colour.G),math.abs(p.Color.B-e.colour.B))>.0001) then sample.offChanged+=1 end
  end
 end
 table.insert(qa.samples,sample)
 if phase=='BLACKOUT' and s and now>s.blackoutAt+.3 then
  if sample.neon~=0 or sample.lit~=0 or sample.brightness~=0 or lighting.Ambient~=Color3.new(0,0,0) then table.insert(qa.failures,{reason='Blackout not dark',sample=#qa.samples}) end
 end
 if sample.offChanged>0 then table.insert(qa.failures,{reason='Originally dead tube changed',sample=#qa.samples}) end
 if (qa.triggered and phase=='NORMAL' and qa.lastSchedule and now>qa.lastSchedule.restoreAt+1.7) or now-qa.started>100 then
  qa.done=true;qa.connection:Disconnect();qa.connection=nil
  qa.restoreMismatches={}
  for _,e in ipairs(qa.fixtures) do if e.part:IsDescendantOf(world) then
   if e.part.Material~=e.material or math.max(math.abs(e.part.Color.R-e.colour.R),math.abs(e.part.Color.G-e.colour.G),math.abs(e.part.Color.B-e.colour.B))>.0001 then table.insert(qa.restoreMismatches,e.part:GetFullName()) end
   for l,b in pairs(e.lights) do if l.Parent and (l.Enabled~=b.enabled or math.abs(l.Brightness-b.brightness)>.00001) then table.insert(qa.restoreMismatches,l:GetFullName()) end end
  end end
 end
end)
return {observing=true,fixtures=#qa.fixtures,started=qa.started}
