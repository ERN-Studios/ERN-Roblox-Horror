-- QA only: execute on the native Play server through the trusted command context.
-- Caller supplies any required HTTP permission; this helper never changes HttpEnabled.
local H=game:GetService('HttpService')
local R=game:GetService('RunService')
local RS=game:GetService('ReplicatedStorage')
local Players=game:GetService('Players')
assert(R:IsRunning() and R:IsServer(),'Native Play server required')
local world=assert(workspace:FindFirstChild('Level 5 Generated World'))
local architecture=assert(world:FindFirstChild('Level5_IndoorSuburbs'))
local player=assert(Players:GetPlayers()[1],'Native test player required')
local gui=assert(player:FindFirstChildOfClass('PlayerGui'),'PlayerGui required')
local names={FluorescentPanel=true,SuspendedSharedFluorescent=true,SharedLowDomesticPanel=true,LastFluorescent=true}
local token=H:GenerateGUID(false)
local baseline={version='2026-09-26.server-baseline.1',token=token,worldGeneration=world:GetAttribute('Level5_Generation'),
 capturedAt=workspace:GetServerTimeNow(),fixtures={},sectionCounts={},lighting={}}
local state=assert(RS:FindFirstChild('Level 5 State'))
for _,key in ipairs({'Brightness','Ambient','OutdoorAmbient','EnvironmentDiffuseScale','EnvironmentSpecularScale','FogColor'}) do
 local value=state:GetAttribute('Lighting_'..key)
 if typeof(value)=='Color3' then baseline.lighting[key]={value.R,value.G,value.B} else baseline.lighting[key]=value end
end
local function vector(v)return{v.X,v.Y,v.Z}end
for _,key in ipairs({'Level5OutageExemptMin','Level5OutageExemptMax','Level5OutageExitMin','Level5OutageExitMax'}) do
 local value=world:GetAttribute(key);assert(typeof(value)=='Vector3','Missing real exit bounds: '..key)
 baseline[key]=vector(value)
end
local fixtures={}
for _,p in ipairs(architecture:GetDescendants()) do if p:IsA('BasePart') and names[p.Name] then table.insert(fixtures,p) end end
assert(#fixtures>0 and #fixtures<=2048,'Unexpected server fixture count')
table.sort(fixtures,function(a,b)
 local an,bn=a:GetFullName(),b:GetFullName();if an~=bn then return an<bn end
 if a.Position.Z~=b.Position.Z then return a.Position.Z<b.Position.Z end
 if a.Position.X~=b.Position.X then return a.Position.X<b.Position.X end
 return a.Position.Y<b.Position.Y
end)
for index,p in ipairs(fixtures) do
 local id=token..':F'..index
 local section=p:GetAttribute('Level5OutageSection')
 assert(type(section)=='number' and section>=1 and section<=8,'Fixture missing section')
 local entry={id=id,path=p:GetFullName(),name=p.Name,section=section,colour={p.Color.R,p.Color.G,p.Color.B},material=p.Material.Name,
  dead=p:GetAttribute('TubeState')=='Off' or p:GetAttribute('FailedTube')==true,lights={}}
 p:SetAttribute('Level5ExitQAId',id)
 local lightIndex=0
 for _,light in ipairs(p:GetChildren()) do if light:IsA('Light') then
  lightIndex+=1;local lightId=id..':L'..lightIndex;light:SetAttribute('Level5ExitQAId',lightId)
  table.insert(entry.lights,{id=lightId,name=light.Name,class=light.ClassName,enabled=light.Enabled,brightness=light.Brightness})
 end end
 table.insert(baseline.fixtures,entry)
 local key=tostring(section);baseline.sectionCounts[key]=(baseline.sectionCounts[key] or 0)+1
end
local source=H:GetAsync('http://127.0.0.1:8769/qa/observe_exit_outage.luau',true)
assert(type(source)=='string' and #source>1000,'Missing observer source')
local folder=Instance.new('Folder');folder.Name='Level5ExitOutageQA_'..string.sub(token,1,8)
folder:SetAttribute('PlayOnlyQA',true);folder:SetAttribute('RunToken',token)
local data=Instance.new('StringValue');data.Name='ServerBaseline';data.Value=H:JSONEncode(baseline);data.Parent=folder
folder.Parent=RS
local observer=Instance.new('LocalScript');observer.Name='Level5ExitOutageQAObserver_'..string.sub(token,1,8)
observer:SetAttribute('PlayOnlyQA',true);observer:SetAttribute('QAFolderName',folder.Name);observer.Source=source;observer.Parent=gui
return {ok=true,fixtureCount=#fixtures,sectionCounts=baseline.sectionCounts,baseline=folder:GetFullName(),observer=observer:GetFullName(),token=token,
 notes='Play-only IDs, baseline and observer. End native Play before export/publish. No HttpEnabled mutation.'}
