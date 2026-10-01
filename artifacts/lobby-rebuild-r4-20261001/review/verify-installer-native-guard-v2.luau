-- Isolated native Instance fixture; extracted installer guard, no Studio connection.
local rbx=require("@lune/roblox")
local serde=require("@lune/serde")
local fs=require("@lune/fs")
local process=require("@lune/process")
local luau=require("@lune/luau")
local prepared=fs.readFile("artifacts/lobby-rebuild-r4-20261001/install-r4-prepared.luau")
assert(serde.hash("sha256",prepared)=="5f06eca8dd1a356904dc54a54622f7d6c8b3a491a744d77b095cc12483843a89","Prepared installer changed")
assert(pcall(luau.compile,prepared),"Exact prepared installer syntax failed")
local game,recovery,shared,editors
local DateTime={now=function() return {UnixTimestamp=1000} end}
local RUN={IsRunning=function() return false end}
local SES={GetEditorSource=function(_,instance) return assert(editors[instance],"Editor fixture missing") end}
local function recoveryFresh()
 assert(shared.__r4NativeRecovery==recovery and not RUN:IsRunning(),"Checkpoint or Edit state changed")
 assert(DateTime.now().UnixTimestamp-recovery.capturedAtUnix>=0
  and DateTime.now().UnixTimestamp-recovery.capturedAtUnix<=1800,"Refresh the native checkpoint before installation")
 local expectedRoots={}
 assert(#recovery.roots==#recovery.rootMappings and #recovery.sourceRows==recovery.sourceCount)
 for i,root in ipairs(recovery.roots) do
  local row=recovery.rootMappings[i]
  -- GetFullName is descriptive, not a tokenized path: native root names may
  -- contain decimal dots. Keep the captured Instance and exact service/name.
  assert(root.Parent==game:FindService(row.service) and root.Name==row.name
   and root:GetFullName()==row.path and root.ClassName==row.class and root.Archivable,
   "Native root identity changed: "..row.path)
  expectedRoots[root]=true
 end
 local count=0
 for _,class in ipairs(recovery.serviceClasses) do
  local service=assert(game:FindService(class),"Captured service disappeared")
  for _,root in ipairs(service:GetChildren()) do
   assert(root.Archivable and expectedRoots[root],"Native root set changed; capture a new checkpoint")
   count+=1
  end
 end
 assert(count==#recovery.roots,"Native root count changed")
 for _,row in ipairs(recovery.sourceRows) do
  local instance=row.instance
  assert(instance:IsDescendantOf(game) and instance:GetFullName()==row.path and instance.ClassName==row.class
   and instance.Source==row.source and SES:GetEditorSource(instance)==row.source,
   "Source/editor changed since checkpoint: "..row.path)
 end
end
local results={}
local function fixture(decimal)
 game=rbx.Instance.new("DataModel")
 local ws=game:GetService("Workspace")
 local ss=game:GetService("ServerStorage")
 local root=rbx.Instance.new("Model")
 root.Name=if decimal then "Bay56.0x22.0" else "Bay"
 root.Parent=ws
 local other=rbx.Instance.new("Folder");other.Name="Other";other.Parent=ss
 local middle=rbx.Instance.new("Folder");middle.Name=if decimal then "Geometry.7.1" else "Geometry";middle.Parent=root
 local source=rbx.Instance.new("ModuleScript")
 source.Name=if decimal then "Lighting6.0" else "Lighting";source.Source="return {safe=true}";source.Parent=middle
 editors={[source]=source.Source}
 local roots={root,other}
 local mappings={}
 for _,r in roots do
  table.insert(mappings,{service=if r.Parent==ws then "Workspace" else "ServerStorage",name=r.Name,path=r:GetFullName(),class=r.ClassName})
 end
 recovery={capturedAtUnix=1000,roots=roots,rootMappings=mappings,serviceClasses={"Workspace","ServerStorage"},sourceCount=1,
  sourceRows={{instance=source,path=source:GetFullName(),class=source.ClassName,source=source.Source}}}
 shared={__r4NativeRecovery=recovery}
 return {ws=ws,ss=ss,root=root,other=other,middle=middle,source=source}
end
local function case(name,expectedPass,mutate,decimal)
 local objects=fixture(decimal~=false)
 if mutate then mutate(objects) end
 local ok,why=pcall(recoveryFresh)
 assert(ok==expectedPass,name..": unexpected guard result "..tostring(why))
 table.insert(results,{name=name,expectedPass=expectedPass,actualPass=ok,testPassed=true,error=if ok then nil else tostring(why)})
 game:Destroy()
end
case("captured decimal root and nested decimal Source names accepted",true)
case("captured conventional names accepted",true,nil,false)
case("root moved to different captured service rejected",false,function(o) o.root.Parent=o.ss end)
case("root renamed rejected",false,function(o) o.root.Name="Renamed" end)
case("root detached rejected",false,function(o) o.root.Parent=nil end)
case("same-name same-class root replacement rejected",false,function(o)
 local replacement=o.root:Clone();o.root.Parent=nil;replacement.Parent=o.ws
end)
case("new duplicate named root rejected",false,function(o) o.root:Clone().Parent=o.ws end)
case("root made non-archivable rejected",false,function(o) o.root.Archivable=false end)
case("captured root class mismatch rejected",false,function() recovery.rootMappings[1].class="Folder" end)
case("Source property change rejected",false,function(o) o.source.Source="return {safe=false}" end)
case("Source editor conflict rejected",false,function(o) editors[o.source]="return {editorChanged=true}" end)
case("nested decimal Source renamed rejected",false,function(o) o.source.Name="Lighting7.0" end)
case("Source reparented to existing different root rejected",false,function(o) o.source.Parent=o.other end)
case("same-name same-class Source replacement rejected",false,function(o)
 local replacement=o.source:Clone();o.source.Parent=nil;replacement.Parent=o.middle;editors[replacement]=replacement.Source
end)
case("captured Source class mismatch rejected",false,function() recovery.sourceRows[1].class="Script" end)
case("checkpoint identity replacement rejected",false,function() shared.__r4NativeRecovery={} end)
case("expired checkpoint rejected",false,function() recovery.capturedAtUnix=-900 end)
local o=fixture(true)
local cursor=game
for token in recovery.rootMappings[1].path:gmatch("[^%.]+") do cursor=if cursor then cursor:FindFirstChild(token) else nil end
assert(cursor==nil,"Decimal regression fixture did not reproduce old dotted-resolve failure")
local decimalPath=recovery.rootMappings[1].path
recoveryFresh()
game:Destroy()
local report={schema="lobby-r4-installer-native-guard-fixture-v2",passed=true,completedTestCount=#results,
 installerSHA256="5f06eca8dd1a356904dc54a54622f7d6c8b3a491a744d77b095cc12483843a89",extractedGuardSHA256="ef2ed183d887fa2b141f0061cde5756082fc945470edbd323f698f9b154d7246",
 nativeInstances=true,preparedInstallerSyntax="PASS",executedStudio=false,studioWrites=false,results=results,
 regression={oldDottedResolverFails=true,newCapturedReferenceGuardPasses=true,decimalRootPath=decimalPath},
 limits="Native Instance identity/Parent/GetFullName/class/Source methods execute in local Lune. DateTime, RunService and editor source use deterministic fixture adapters. No real Studio, whole installer execution or publication claim."}
local output=assert(process.args[1],"Pass output path")
fs.writeFile(output,serde.encode("json",report,true).."\n")
print(serde.encode("json",{passed=true,completedTestCount=#results,installerSHA256=report.installerSHA256,output=output},true))
