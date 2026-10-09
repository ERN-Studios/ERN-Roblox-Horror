local HS=game:GetService("HttpService")
local KEY="__MongoTVRetiredAuthoringArchive20261009"
local ORIGINAL="__MongoTVStorageCleanup20261009"
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
assert(not game:GetService("RunService"):IsRunning(),"Mode changed; preserve Play")
local state=assert(shared[KEY],"Owned state absent")
assert(state.config and state.config.captureId=="dc6a22ca9c2f48daba4d94ec84ca5746","Foreign state")
assert(state.phase=="captured" and state.nativeReopenPass==true,"Wrong state verdict")
assert(state.nativeSHA256=="e808f055403bd331b76e0831955b192abc8b4a914865c3936aa9b2d23ed2a8d7","Wrong capture")
assert(state.probeLease==nil and state.portLease==nil,"State busy")
assert(state.watchersConnected==false and type(state.connections)=="table" and next(state.connections)==nil,"State has watchers")
local old=assert(shared[ORIGINAL],"Original identity ledger absent")
assert(state.previous==old and old.probeLease==nil and old.portLease==nil,"Original ledger changed/busy")
local oldRoots=assert(old.rootRefs) local oldScripts=assert(old.scriptRefs)
local roots={} local scripts={} local rootCount,heldCount,scriptCount=0,0,0
for root,row in oldRoots do rootCount+=1 assert(rootCount<=100,"Root ledger bound") roots[root]={row=row,parent=root.Parent} if root.Parent==nil then heldCount+=1 end end
for node,row in oldScripts do scriptCount+=1 assert(scriptCount<=300,"Script ledger bound") scripts[node]=row end
assert(rootCount==73 and heldCount==23 and scriptCount==222,"Original ledger differs")
local names={"LobbyReimaginedBlenderSource20261001","LobbyReimaginedBlenderSource20261001R2","LobbyReimaginedBlenderSource20261001R3","LobbyReimaginedBlenderSource20261001R3B","Level1BlenderKit"}
local ids={"1_16181","1_16219","1_16257","1_16298","1_16419"}
local ss=game:GetService("ServerStorage") local rows={}
assert(#state.roots==5,"Root set differs")
for i,root in state.roots do
 assert(root.Name==names[i] and root:GetDebugId()==ids[i] and root.Parent==ss,"Original package identity differs")
 rows[i]={name=root.Name,id=root:GetDebugId(),class=root.ClassName,parent=root.Parent:GetFullName()}
end
-- The sole mutation drops this completed, inactive test's own shared metadata.
-- No yield occurs between ownership guards, release and verification.
assert(shared[KEY]==state and shared[ORIGINAL]==old and old.rootRefs==oldRoots and old.scriptRefs==oldScripts,"Ownership changed")
shared[KEY]=nil
assert(shared[KEY]==nil and shared[ORIGINAL]==old and old.rootRefs==oldRoots and old.scriptRefs==oldScripts,"Metadata/ledger changed")
local n=0 for root,row in oldRoots do n+=1 assert(roots[root] and roots[root].row==row and roots[root].parent==root.Parent,"Original root reference changed") end assert(n==rootCount,"Original root count changed")
n=0 for node,row in oldScripts do n+=1 assert(scripts[node]==row,"Original script reference changed") end assert(n==scriptCount,"Original script count changed")
for i,root in state.roots do assert(root.Name==rows[i].name and root:GetDebugId()==rows[i].id and root.Parent==ss,"Original package changed") end
return HS:JSONEncode({schema="cleanup-owned-metadata-release-v1",atUtc=DateTime.now():ToIsoDate(),placeId=game.PlaceId,universeId=game.GameId,passed=true,ownedKeyReleased=true,captureId=state.config.captureId,connectionsBefore=0,oldLedgerPreserved=true,oldRootRefs=rootCount,oldHeldRoots=heldCount,oldScriptRefs=scriptCount,roots=rows,nativeWrites=0,sourceWrites=0,editorWrites=0,modeSwitches=0,objectsDestroyed=0,semantics="Own inactive shared metadata only; no full current Source/forest parity or gameplay/performance certificate. Historical capture guards are not rerun after concurrent changes."})
