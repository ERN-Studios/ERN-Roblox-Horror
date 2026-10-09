-- Native engine reopen only. Every created root stays unparented and is test-owned.
-- Reopen never restores, reparents or destroys an authoritative original.
local config=ARCHIVE_CONFIG
A.mode()
local state=assert(shared[A.KEY],"No successful original capture in this exact Studio")
A.check(state.phase=="captured" and state.captureReport and state.captureReport.passed,"Capture did not pass")
A.check(config.captureId==state.config.captureId and not state.probeLease,"Wrong/reused reopen lease")
local lease={} state.probeLease=lease
local ownedRoots,allCopies={},{}
local report={schema="retired-authoring-native-reopen-v1",passed=false,deletionApproved=false,createdRoots=0,destroyedRoots=0,
 originalWrites=0,sourceWrites=0,modeSwitches=0,gameplayPassed=false,
 identityExclusions={"UniqueId","HistoryId"},binaryDifferenceClassified=false,
 limits="Unparented native-engine recovery only. No active R4/V2 gameplay, multiplayer/streaming, cold-cache or performance certification."}
local function download(context)
 local pieces={}
 for i=0,context.nativeParts-1 do
  A.mode() local text=A.HS:GetAsync(A.BASE.."/native-b64/"..i,true)
  pieces[#pieces+1]=buffer.tostring(A.ENC:Base64Decode(buffer.fromstring(text)))
 end
 local raw=buffer.fromstring(table.concat(pieces))
 A.check(buffer.len(raw)==state.nativeBytes and A.sha(raw)==state.nativeSHA256,"Disk archive differs from captured native bytes")
 return raw
end
local function own(roots)
 A.check(type(roots)=="table","Unexpected native reopen result")
 local adoptionErrors={}
 for _,root in roots do
  -- Identity proof before any Destroy eligibility; never adopt a known original.
  local adopted,reason=pcall(function()
   A.check(typeof(root)=="Instance" and not state.knownOriginals[root],"Native reopen returned a known original")
   A.check(root.Parent==nil and not root:IsDescendantOf(game),"Native reopen escaped off-place ownership")
   A.check(not ownedRoots[root],"Native reopen reused a prior test identity")
   for _,node in root:GetDescendants() do A.check(not state.knownOriginals[node],"Native reopen contains an original descendant") end
   ownedRoots[root]=true allCopies[#allCopies+1]=root report.createdRoots+=1
  end)
  if not adopted then adoptionErrors[#adoptionErrors+1]=tostring(reason) end
 end
 -- Adopt every safe result before count/name/identity assertions can interrupt cleanup.
 A.check(#adoptionErrors==0,table.concat(adoptionErrors,"\n"))
 A.check(#roots==5,"Native reopen root count differs")
 for i,root in roots do A.check(root.Name==A.NAMES[i] and root.ClassName=="Folder","Native reopen root identity differs") end
 return roots
end
local ok,why=xpcall(function()
 A.guard(state)
 -- Watchers are fresh for this separated verifier invocation.
 state.watchersConnected=true
 A.watchInventory(state)
 for _,node in state.nodes do
  A.watchNode(state,node,"retiredForest",false)
 end
 for node in state.sources do
  A.watchNode(state,node,"liveSource",false)
 end
 for node in state.heldRows do
  A.watchNode(state,node,"heldOriginal",true)
 end
 local context=A.HS:JSONDecode(A.HS:GetAsync(A.BASE.."/context",true))
 A.check(context.schema==A.SCHEMA and context.captureId==config.captureId and context.phase=="verify","Wrong disk archive verifier receiver")
 A.check(context.nativeSHA256==state.nativeSHA256 and context.nativeBytes==state.nativeBytes,"Context native hash/size differs")
 A.guard(state)
 local raw=download(context)
 local copies=own(A.SER:DeserializeInstancesAsync(raw))
 local facts=A.forestFacts(copies)
 report.firstReopenFactsMatch=A.same(facts,state.facts)
 A.check(report.firstReopenFactsMatch,"Native reopen readable facts, attrs/tags, assets/colliders/internal refs differ")
 A.check(#facts.unsupportedReadableProperties==0,"Unclassified readable property type prevents recovery approval")
 A.guard(state)
 local canonical=A.SER:SerializeInstancesAsync(copies)
 report.originalNativeSHA256=state.nativeSHA256 report.canonicalNativeSHA256=A.sha(canonical)
 report.originalToCanonicalByteEqual=report.originalNativeSHA256==report.canonicalNativeSHA256
 local copies2=own(A.SER:DeserializeInstancesAsync(canonical))
 local facts2=A.forestFacts(copies2)
 report.secondReopenFactsMatch=A.same(facts2,state.facts)
 A.check(report.secondReopenFactsMatch,"Second native reopen readable facts/internal refs differ")
 local second=A.SER:SerializeInstancesAsync(copies2)
 report.secondCanonicalSHA256=A.sha(second)
 report.nativeCanonicalStable=report.secondCanonicalSHA256==report.canonicalNativeSHA256
 A.check(report.nativeCanonicalStable,"Repeated native canonicalization is not stable")
 -- Do not attribute arbitrary hidden byte changes to IDs. Unexplained bytes remain a blocker.
 A.check(report.originalToCanonicalByteEqual,"Opaque native byte delta requires separate classification; no recovery/removal approval")
 report.binaryDifferenceClassified=true
 local originals=A.SER:SerializeInstancesAsync(state.roots)
 A.check(A.sha(originals)==state.nativeSHA256,"Authoritative native forest changed since capture")
 report.references=A.references(state)
 A.check(#report.references.externalReadable==0,"New readable inbound reference into retired forest")
 A.guard(state)
end,debug.traceback)
-- Each owned root cleanup is independent, including facts/assertion/serialization failures.
local errors={}
for _,root in allCopies do
 local clean,errorText=pcall(function()
  A.check(ownedRoots[root] and not state.knownOriginals[root],"Cleanup identity is an original")
  A.check(root.Parent==nil and not root:IsDescendantOf(game),"Test copy escaped ownership; preserve it for investigation")
  for _,node in root:GetDescendants() do A.check(not state.knownOriginals[node],"Cleanup tree contains an original descendant") end
  root:Destroy()
 end)
 if clean then report.destroyedRoots+=1 else errors[#errors+1]=tostring(errorText) end
end
report.cleanupErrors=errors report.testOwnedRootsRemaining=report.createdRoots-report.destroyedRoots
if #errors>0 then ok=false why=tostring(why).."\nowned-copy cleanup failed" end
local guardOk,guardWhy=pcall(function()A.guard(state)end)
report.finalOriginalGuardPassed=guardOk
if not guardOk then ok=false why=tostring(why).."\nfinal original guard: "..tostring(guardWhy) end
local disconnected=A.disconnect(state) report.watcherCleanupErrors=disconnected
if #disconnected>0 then ok=false why=tostring(why).."\nwatcher cleanup failed" end
local afterCleanup,afterCleanupWhy=pcall(function()A.guard(state)end)
report.postCleanupOriginalGuardPassed=afterCleanup
report.postCleanupGuardSemantics="Point-in-time native inventory/Source/editor/forest/held-original checks across bounded yielding reads after watchers were disconnected; no continuous epoch guarantee or active asset restoration certificate."
if not afterCleanup then ok=false why=tostring(why).."\npost-cleanup original guard: "..tostring(afterCleanupWhy) end
if state.probeLease~=lease then ok=false why=tostring(why).."\nprobe lease changed" end
-- This transfer records the precompletion evidence. Only the later MCP result can pass.
report.stage="precompletion" report.precompletionChecksPassed=ok report.passed=false
report.diagnostics=A.diagnostics(state)
report.error=if ok then nil else tostring(why) report.verifiedAtUtc=DateTime.now():ToIsoDate()
local transferred,transferWhy=pcall(function()
 local response=A.post(config,"/verify-receipt",A.HS:JSONEncode(report))
 A.check(response.Success and response.Body=="saved","Reopen receipt was not preserved")
end)
if not transferred then ok=false why=tostring(why).."\nreceipt transfer: "..tostring(transferWhy) end
local afterTransfer,afterTransferWhy=pcall(function()A.guard(state)end)
if not afterTransfer then ok=false why=tostring(why).."\npost-receipt original guard: "..tostring(afterTransferWhy) end
local finalOwned=shared[A.KEY]==state and state.probeLease==lease
if not finalOwned then ok=false why=tostring(why).."\ncompletion shared-state/probe lease changed" end
-- No yielding calls after this live-state verdict is published.
report.stage="mcp-completion" report.passed=ok report.error=if ok then nil else tostring(why)
report.postReceiptOriginalGuardPassed=afterTransfer report.receiptTransferred=transferred
report.diagnostics=A.diagnostics(state)
-- Publish or release only the exact still-owned state/lease. Preserve foreign metadata.
if finalOwned then
 state.probeLease=nil
 state.nativeReopenReport=report state.nativeReopenPass=ok state.deletionApproved=false
end
return A.HS:JSONEncode({schema=report.schema,passed=report.passed,error=report.error,createdRoots=report.createdRoots,
 destroyedRoots=report.destroyedRoots,testOwnedRootsRemaining=report.testOwnedRootsRemaining,
 originalToCanonicalByteEqual=report.originalToCanonicalByteEqual,nativeCanonicalStable=report.nativeCanonicalStable,
 finalOriginalGuardPassed=report.finalOriginalGuardPassed,postCleanupOriginalGuardPassed=report.postCleanupOriginalGuardPassed,
 postReceiptOriginalGuardPassed=afterTransfer,postCleanupGuardSemantics=report.postCleanupGuardSemantics,
 receiptTransferred=transferred,stage=report.stage,diagnostics=report.diagnostics,stateVerdictPublished=finalOwned,
 ownedProbeLeaseReleased=finalOwned,deletionApproved=false})
