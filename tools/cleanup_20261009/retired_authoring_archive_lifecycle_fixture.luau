-- Offline fake services driving the complete, current real verifier suffix.
-- Driver writes reviewed suffix into a temporary module; no Roblox/Studio APIs run.
local run=require("./native_verify_fixture")
local scenarios={"success","wrong-count","wrong-name","known-original","duplicate-copy","facts-error",
 "cleanup-error","disconnect-mutation","transfer-mutation","transfer-error","lease-mutation","shared-state-mutation"}
local cases=0
for _,scenario in scenarios do
 local names={"LobbyReimaginedBlenderSource20261001","LobbyReimaginedBlenderSource20261001R2",
  "LobbyReimaginedBlenderSource20261001R3","LobbyReimaginedBlenderSource20261001R3B","Level1BlenderKit"}
 local state={phase="captured",captureReport={passed=true},config={captureId="offline-capture-lease"},
  nodes={},sources={},heldRows={},rootRefs={},knownOriginals={},connections={},epoch=0,
  nativeBytes=3,nativeSHA256="raw",facts={fixture=true},roots={}}
 local shared={offline=state}
 local changed=false local destroyed={} local nextBatch=0 local precompletion=false
 local foreign={probeLease={foreign=true},nativeReopenPass="foreign-pass",nativeReopenReport={foreignReport=true},deletionApproved="foreign-decision"}
 local foreignReport=foreign.nativeReopenReport local foreignLease=foreign.probeLease
 local original={Name="HeldOriginal",ClassName="Folder",Parent=nil}
 function original:GetDescendants() return {} end
 function original:IsDescendantOf() return false end
 function original:Destroy() error("ORIGINAL DESTROY FORBIDDEN") end
 state.knownOriginals[original]=true
 local signal={}
 function signal:Connect()
  return {Disconnect=function()if scenario=="disconnect-mutation" then changed=true end end}
 end
 local game={DescendantAdded=signal,DescendantRemoving=signal}
 local A={KEY="offline",NAMES=names,BASE="offline://no-network",SCHEMA="retired-authoring-native-archive-v1",
  SS={ChildAdded=signal,ChildRemoved=signal},ENC={Base64Decode=function()return buffer.fromstring("raw")end}}
 A.mode=function()end A.check=assert A.sha=buffer.tostring
 A.guard=function(s)assert(shared.offline==s and not changed,"original drift fixture")end
 A.diagnostics=function()return {offlineFixture=true}end
 A.watchInventory=function(s)
  for _,event in {game.DescendantAdded,game.DescendantRemoving,A.SS.ChildAdded,A.SS.ChildRemoved} do
   s.connections[#s.connections+1]=event:Connect()
  end
 end
 A.watchNode=function()error("Unexpected nonempty original fixture scope")end
 A.forestFacts=function()return if scenario=="facts-error" then {fixture=false} else {fixture=true,unsupportedReadableProperties={}} end
 state.facts={fixture=true,unsupportedReadableProperties={}}
 A.same=function(a,b)return a.fixture==b.fixture end
 A.references=function()return {externalReadable={}}end
 A.disconnect=function(s)
  local errors={}
  for _,connection in s.connections do
   local ok,why=pcall(function()connection:Disconnect()end)
   if not ok then errors[#errors+1]=tostring(why) end
  end
  s.connections={} return errors
 end
 A.HS={JSONEncode=function(_,v)return v end,JSONDecode=function(_,v)return v end,
  GetAsync=function(_,url)
   if string.find(url,"/context",1,true) then
    return {schema=A.SCHEMA,captureId=state.config.captureId,phase="verify",nativeSHA256="raw",nativeBytes=3,nativeParts=1}
   end return "offline-base64"
  end}
 A.post=function(_,path,body)
  assert(path=="/verify-receipt" and body.stage=="precompletion" and body.passed==false)
  assert(state.nativeReopenPass~=true,"Pass published before transfer/final guard") precompletion=true
  if scenario=="transfer-mutation" then changed=true end
  if scenario=="lease-mutation" then
   state.probeLease=foreignLease state.nativeReopenPass=foreign.nativeReopenPass
   state.nativeReopenReport=foreignReport state.deletionApproved=foreign.deletionApproved
  end
  if scenario=="shared-state-mutation" then shared.offline=foreign end
  if scenario=="transfer-error" then error("offline transfer fixture") end
  return {Success=true,Body="saved"}
 end
 local allCreated={}
 A.SER={SerializeInstancesAsync=function()return buffer.fromstring("raw")end,
  DeserializeInstancesAsync=function()
   nextBatch+=1 local roots={}
   local count=if scenario=="wrong-count" and nextBatch==1 then 6 else 5
   for i=1,count do
    local root={Name=names[i] or "UnexpectedSixth",ClassName="Folder",Parent=nil}
    function root:GetDescendants() return {} end
    function root:IsDescendantOf()return false end
    function root:Destroy()
     if scenario=="cleanup-error" and #allCreated==10 and self==allCreated[1] then error("offline destroy fixture") end
     assert(not destroyed[self],"Double Destroy") destroyed[self]=true
    end
    roots[i]=root allCreated[#allCreated+1]=root
   end
   if scenario=="wrong-name" then roots[2].Name="Wrong" end
   if scenario=="known-original" then roots[3]=original end
   if scenario=="duplicate-copy" then roots[5]=roots[2] end
   return roots
  end}
 local DateTime={now=function()return {ToIsoDate=function()return "offline"end}end}
 local result=run(A,state.config,shared,game,DateTime)
 assert(precompletion,"Evidence transfer not attempted")
 assert(result.stage=="mcp-completion")
 local lost=scenario=="lease-mutation" or scenario=="shared-state-mutation"
 assert(result.stateVerdictPublished==not lost and result.ownedProbeLeaseReleased==not lost)
 if not lost then assert(result.passed==state.nativeReopenPass) end
 assert(result.deletionApproved==false and not destroyed[original])
 assert(result.passed==(scenario=="success"),scenario)
 local expected=if scenario=="wrong-count" then 6 elseif scenario=="known-original" or scenario=="duplicate-copy" then 4
  elseif scenario=="wrong-name" or scenario=="facts-error" then 5 else 10
 assert(result.createdRoots==expected,scenario..": every eligible result must be adopted")
 assert(result.destroyedRoots==expected-(if scenario=="cleanup-error" then 1 else 0),scenario..": independent cleanup")
 assert(result.testOwnedRootsRemaining==(if scenario=="cleanup-error" then 1 else 0),scenario)
 if not lost then assert(state.probeLease==nil,"Owned lease not released")
 elseif scenario=="lease-mutation" then
  assert(state.probeLease==foreignLease and state.nativeReopenPass=="foreign-pass"
   and state.nativeReopenReport==foreignReport and state.deletionApproved=="foreign-decision","Foreign metadata overwritten")
 else
  assert(shared.offline==foreign and foreign.probeLease==foreignLease and foreign.nativeReopenPass=="foreign-pass"
   and foreign.nativeReopenReport==foreignReport and foreign.deletionApproved=="foreign-decision","Replacement state overwritten")
  assert(state.nativeReopenPass==nil and state.nativeReopenReport==nil and state.deletionApproved==nil and state.probeLease~=nil,
   "No-longer-owned old state overwritten/released")
 end
 if scenario=="disconnect-mutation" then assert(not result.postCleanupOriginalGuardPassed) end
 if scenario=="transfer-mutation" then assert(not result.postReceiptOriginalGuardPassed) end
 cases+=1
end
print("S04 offline current-verifier lifecycle scenarios passed: "..cases)
