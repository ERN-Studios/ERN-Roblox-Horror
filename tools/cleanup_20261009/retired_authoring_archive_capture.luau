-- Concatenate reviewed common prefix. Exact five originals are serialized, never modified.
local config=ARCHIVE_CONFIG
local state
local report={schema="retired-authoring-native-capture-result-v1",passed=false,deletionApproved=false,
 originalWrites=0,sourceWrites=0,modeSwitches=0,probeObjectsCreated=0}
local ok,why=xpcall(function()
 state=A.begin(config)
 local context=A.HS:JSONDecode(A.HS:GetAsync(A.BASE.."/context",true))
 A.check(context.schema==A.SCHEMA and context.captureId==config.captureId and context.phase=="capture","Wrong immutable receiver/phase")
 A.check(A.same(context.names,A.NAMES),"Receiver scope differs")
 A.guard(state)
 -- Roblox rejects an empty instance list. The exact five-root read below is the positive API gate.
 A.check(typeof(A.SER.SerializeInstancesAsync)=="function","Native serializer method unavailable")
 A.check(typeof(A.SER.DeserializeInstancesAsync)=="function","Native reopen API unavailable")
 report.capability={serializerMethod=true,deserializerMethod=true,reopenExecuted=false}
 state.references=A.references(state)
 A.check(#state.references.externalReadable==0,"Readable inbound reference prevents standalone recovery")
 A.guard(state)
 local native=A.SER:SerializeInstancesAsync(state.roots)
 A.check(typeof(native)=="buffer" and buffer.len(native)>0,"Native serializer returned no buffer")
 report.capability.serializedRoots=#state.roots report.capability.serializer=true
 A.guard(state)
 local second=A.SER:SerializeInstancesAsync(state.roots)
 A.check(A.sha(native)==A.sha(second),"Repeated unchanged-original serialization differs")
 A.guard(state)
 state.nativeSHA256=A.sha(native) state.nativeBytes=buffer.len(native)
 local sources={}
 for node,row in state.sources do
  local direct={}
  for _,name in A.NAMES do
   if string.find(row.source,'"'..name..'"',1,true) or string.find(row.source,"'"..name.."'",1,true) then direct[#direct+1]=name end
  end
  A.check(#direct==0,"Fresh direct retired-name Source consumer requires review: "..row.path)
  sources[#sources+1]={path=row.path,class=row.class,sourceSHA256=A.shaText(row.source),bytes=#row.source,
   properties=row.properties,attributes=A.attributes(node),tags=row.tags,directRetiredNameMatches=direct}
 end
 table.sort(sources,function(a,b)return a.path<b.path end)
 local facts={schema=A.SCHEMA,stage="precompletion",passed=false,captureId=config.captureId,placeId=game.PlaceId,universeId=game.GameId,
  capturedAtUtc=DateTime.now():ToIsoDate(),scopeNames=table.clone(A.NAMES),rootCount=5,totalInstances=1617,
  sourceCount=state.sourceCount,serverStorageRootCount=config.expectedRootCount,forest=state.facts,sourceInventory=sources,
  references=state.references,nativeSHA256=state.nativeSHA256,nativeBytes=state.nativeBytes,
  noOriginalMutation=true,deletionApproved=false,reopenPort="pending separate native-engine verifier",
  limits="Native five-root archive only; no active gameplay, cache/cold-start, multiplayer, streaming, removal or performance pass."}
 local transfer={native=A.upload(config,"native",buffer.tostring(native)),facts=A.upload(config,"facts",A.HS:JSONEncode(facts))}
 A.guard(state)
 local response=A.post(config,"/finalize",A.HS:JSONEncode(transfer))
 A.check(response.Success and response.Body=="saved","Native archive not finalized")
 A.guard(state)
 state.phase="captured" state.archiveFacts=facts
 report.nativeSHA256=state.nativeSHA256 report.nativeBytes=state.nativeBytes report.sourceCount=state.sourceCount
 report.serverStorageRootCount=config.expectedRootCount report.totalInstances=1617 report.capturedAtUtc=facts.capturedAtUtc
 report.referenceSlots=state.references.slots report.unreadableReferenceKinds=#state.references.unreadable
end,debug.traceback)
-- Setup may throw after taking its lease. Recover only this invocation's owned state.
if not state then local candidate=shared[A.KEY] if candidate and candidate.config==config then state=candidate end end
local guardOk,guardWhy=false,"baseline not acquired"
if state and state.baselineComplete then guardOk,guardWhy=pcall(function()A.guard(state)end) end
report.finalOriginalGuardPassed=guardOk
if not guardOk then ok=false why=tostring(why).."\nfinal original guard: "..tostring(guardWhy) end
local cleanup=if state then A.disconnect(state) else {}
report.watcherCleanupErrors=cleanup
if #cleanup>0 then ok=false why=tostring(why).."\nwatcher cleanup failed" end
local afterCleanup,afterCleanupWhy=false,"baseline not acquired"
if state and state.baselineComplete then afterCleanup,afterCleanupWhy=pcall(function()A.guard(state)end) end
report.postCleanupOriginalGuardPassed=afterCleanup
report.postCleanupGuardSemantics="Point-in-time inventory/Source/editor/readable facts/opaque native snapshot checks across bounded yielding reads after watchers were disconnected; no continuous epoch guarantee or restoration/removal certificate."
if not afterCleanup then ok=false why=tostring(why).."\npost-cleanup original guard: "..tostring(afterCleanupWhy) end
report.stage="mcp-completion" report.passed=ok report.error=if ok then nil else tostring(why)
report.diagnostics=A.diagnostics(state)
if state then
 state.captureReport=report
 if not ok and shared[A.KEY]==state then shared[A.KEY]=nil end
end
report.ownedCaptureLeaseReleased=state~=nil and not ok and shared[A.KEY]~=state
return A.HS:JSONEncode(report)
