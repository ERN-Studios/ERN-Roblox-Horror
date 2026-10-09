-- Offline full current capture suffix. Fake serializer rejects empty lists like Roblox.
local run=require("./native_capture_fixture")
local names={"LobbyReimaginedBlenderSource20261001","LobbyReimaginedBlenderSource20261001R2",
 "LobbyReimaginedBlenderSource20261001R3","LobbyReimaginedBlenderSource20261001R3B","Level1BlenderKit"}
local config={captureId="offline-positive-capture-lease",expectedRootCount=52,expectedSourceCount=1}
local state={config=config,epoch=0,baselineComplete=true,roots={},sources={},sourceCount=1,
 facts={instanceCount=1617},connections={},watchersConnected=true}
for i,name in names do state.roots[i]={Name=name,ClassName="Folder"} end
local sourceNode={Name="FixtureSource"}
state.sources[sourceNode]={path="ServerScriptService.FixtureSource",class="ModuleScript",source="return 1",properties={},tags={}}
local shared={} local serializeCalls=0 local emptyCalls=0 local guardCalls=0 local finalized=false
local A={KEY="offlineCapture",NAMES=names,SCHEMA="retired-authoring-native-archive-v1",BASE="offline://no-network"}
local hash=string.rep("a",64)
A.check=assert A.sha=function()return hash end A.shaText=function()return string.rep("b",64)end
A.begin=function(c)assert(c==config)shared[A.KEY]=state return state end
A.same=function(a,b)for i,v in a do if b[i]~=v then return false end end return #a==#b end
A.guard=function(s)
 assert(s==state and shared[A.KEY]==s and s.epoch==0)
 assert(#s.roots==5)
 for i,name in names do assert(s.roots[i].Name==name)end
 guardCalls+=1
end
A.SER={SerializeInstancesAsync=function(_,roots)
 if #roots==0 then emptyCalls+=1 error("No instances provided for serialization")end
 assert(roots==state.roots and #roots==5,"Serializer must receive exact five originals")
 serializeCalls+=1 return buffer.fromstring("raw")
end,DeserializeInstancesAsync=function()error("Capture must not deserialize")end}
A.HS={JSONEncode=function(_,v)return v end,JSONDecode=function(_,v)return v end,
 GetAsync=function()return {schema=A.SCHEMA,captureId=config.captureId,phase="capture",names=names}end}
A.references=function()return {externalReadable={},slots=0,unreadable={}}end
A.attributes=function()return {}end
A.upload=function(_,kind,value)
 if kind=="native" then assert(value=="raw")
 else
  assert(kind=="facts" and value.stage=="precompletion" and value.passed==false)
  assert(value.rootCount==5 and value.totalInstances==1617)
  assert(value.sourceInventory[1].source==nil and value.sourceInventory[1].bytes==8)
 end
 return {parts=1,bytes=3,sha256=hash}
end
A.post=function(_,path)assert(path=="/finalize") finalized=true return {Success=true,Body="saved"}end
A.disconnect=function(s)s.watchersConnected=false return {}end
A.diagnostics=function()return {offlineFixture=true}end
local game={PlaceId=131311258779917,GameId=10559217407}
local DateTime={now=function()return {ToIsoDate=function()return "offline"end}end}
local report=run(A,config,shared,game,DateTime)
assert(report.passed and report.stage=="mcp-completion" and finalized)
assert(serializeCalls==2 and emptyCalls==0 and guardCalls>=7)
assert(report.capability.serializer and report.capability.serializedRoots==5 and report.capability.reopenExecuted==false)
assert(report.finalOriginalGuardPassed and report.postCleanupOriginalGuardPassed)
assert(report.originalWrites==0 and report.sourceWrites==0 and report.probeObjectsCreated==0)
assert(state.phase=="captured" and state.captureReport==report and shared[A.KEY]==state)
print("S04 offline current-capture positive-five-root scenario passed: 1")
