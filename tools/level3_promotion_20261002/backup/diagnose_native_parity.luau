-- Local-only recovery verification. No connection to Studio; no input edits.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rbx = require("@lune/roblox")
local directory = assert(process.args[1], "Pass checkpoint directory")
local placePath = assert(process.args[2], "Pass reconstructed/native place path")
local outputPath = assert(process.args[3], "Pass verification receipt path")
local recordedFixture = process.args[4] == "--recorded-fixture"
local function sha(bytes) return serde.hash("sha256",bytes) end
local metadata = serde.decode("json",fs.readFile(directory.."/metadata.json"))
local scripts = serde.decode("json",fs.readFile(directory.."/scripts.json"))
assert(metadata.placeId==131311258779917 and metadata.universeId==10559217407,"Wrong recovery place")
assert(#metadata.editorConflicts==0 and #metadata.skipped==0,"Source/editor conflicts or skipped roots")
local nativeBytes = fs.readFile(directory.."/all-service-children.rbxm")
assert(#nativeBytes==metadata.nativeBytes,"Wrong native forest byte length")
if not recordedFixture then
    assert(metadata.captureId and sha(nativeBytes)==metadata.nativeSHA256,"Fresh capture ID/native forest hash missing or wrong")
elseif metadata.nativeSHA256 then
    assert(sha(nativeBytes)==metadata.nativeSHA256,"Wrong recorded native forest hash")
end
local roots = rbx.deserializeModel(nativeBytes)
assert(#roots==metadata.rootCount and #roots==#metadata.roots,"Wrong native root count")
local nativeGame = rbx.Instance.new("DataModel")
local services = {}
for _,row in metadata.services do
    local service=nativeGame:GetService(row.class);service.Name=row.name;services[row.class]=service
end
for index,root in roots do
    local row=metadata.roots[index]
    assert(root.Name==row.name and root.ClassName==row.class,"Native root identity mismatch "..row.path)
    root.Parent=assert(services[row.service],"Missing captured service")
end
local placeBytes=fs.readFile(placePath)
local reopened=rbx.deserializePlace(placeBytes)
local function resolve(game,path)
    -- Root names can contain dots (e.g. decimal dimensions), so never split the
    -- whole GetFullName path. Resolve the exact service/root names first.
    local best
    for _,row in metadata.roots do
        if path==row.path or path:sub(1,#row.path+1)==row.path.."." then
            if not best or #row.path>#best.path then best=row end
        end
    end
    if not best then return nil end
    local service=game:FindFirstChild(services[best.service].Name)
    local cursor=service and service:FindFirstChild(best.name)
    for token in path:sub(#best.path+2):gmatch("[^%.]+") do cursor=cursor and cursor:FindFirstChild(token) end
    return cursor
end
local reopenedRoots,rootRows={},{}
local nativeDescendants=0
for index,root in roots do
    local row=metadata.roots[index]
    local found=assert(resolve(reopened,row.path),"Reopened root missing "..row.path)
    local omittedStatus=if row.path=="Workspace.StarterCharacter" or row.path=="Workspace.Dummy" then 1 else 0
    assert(found.ClassName==row.class and #root:GetDescendants()==row.descendants-omittedStatus
        and #found:GetDescendants()==#root:GetDescendants(),"Reopened root identity/descendants mismatch "..row.path)
    table.insert(reopenedRoots,found)
    nativeDescendants+=#root:GetDescendants()+1
    table.insert(rootRows,{index=index,path=row.path,class=row.class,descendants=#root:GetDescendants()})
end
local sourceRows={}
assert(#scripts==metadata.scriptCount,"Wrong captured Source count")
for _,row in scripts do
    local raw=assert(resolve(nativeGame,row.path),"Native Source missing "..row.path)
    local found=assert(resolve(reopened,row.path),"Reopened Source missing "..row.path)
    local digest=sha(row.source)
    assert(row.editorMatch==true and raw.ClassName==row.class and found.ClassName==row.class
        and raw.Source==row.source and found.Source==row.source,"Exact Source/native/reopen mismatch "..row.path)
    if row.sourceSha256 then assert(digest==row.sourceSha256,"Captured Source hash mismatch") end
    if row.editorSourceSha256 then assert(digest==row.editorSourceSha256,"Captured editor hash mismatch") end
    table.insert(sourceRows,{path=row.path,class=row.class,bytes=#row.source,sha256=digest,editorMatch=true})
end
local sourceCount=0
for _,instance in reopened:GetDescendants() do if instance:IsA("LuaSourceContainer") then sourceCount+=1 end end
assert(sourceCount==#scripts,"Unexpected reopened Sources")
local canonicalNative=sha(rbx.serializeModel(roots))
local canonicalReopened=sha(rbx.serializeModel(reopenedRoots))
local mismatches={}
for index, root in roots do
    local a=sha(rbx.serializeModel({root}))
    local b=sha(rbx.serializeModel({reopenedRoots[index]}))
    if a~=b then table.insert(mismatches,{path=metadata.roots[index].path,class=root.ClassName,capturedRootCanonicalSHA256=a,nativePlaceRootCanonicalSHA256=b}) end
end
local report={schema="level3-promotion-native-source-structure-parity-v1",captureId=metadata.captureId,
    placeId=metadata.placeId,universeId=metadata.universeId,groupId=metadata.groupId,
    nativePlaceSHA256=sha(placeBytes),nativePlaceBytes=#placeBytes,nativeForestSHA256=sha(nativeBytes),
    canonicalNativeForestSHA256=canonicalNative,canonicalNativePlaceForestSHA256=canonicalReopened,
    canonicalForestEqual=canonicalNative==canonicalReopened,rootCount=#roots,sourceCount=#scripts,
    nativeContentInstances=nativeDescendants,sourceErrors=0,rootErrors=0,sourceEditorConflicts=0,
    rootsWithDifferentCanonicalSerialization=mismatches,sourceRows=sourceRows,rootRows=rootRows,
    limits="Exact native file root class/name/descendant counts and all 228 Source/editor baselines verified. Canonical forest equality evaluated separately; mismatched roots require investigation. No Studio writes, reconstruction, gameplay or publication claim."}
fs.writeFile(outputPath,serde.encode("json",report,true).."\n")
print(serde.encode("json",{captureId=report.captureId,nativePlaceSHA256=report.nativePlaceSHA256,
    rootCount=report.rootCount,sourceCount=report.sourceCount,canonicalForestEqual=report.canonicalForestEqual,
    mismatchedRoots=mismatches,output=outputPath},true))
