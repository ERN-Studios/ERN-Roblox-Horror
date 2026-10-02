-- Disk-only audit. No Studio access and no edits to either captured input.
-- Every compared-away delta is explicitly pinned and reported, never arbitrary.
local fs, process, serde, rbx = require("@lune/fs"), require("@lune/process"), require("@lune/serde"), require("@lune/roblox")
local beforeDir, afterDir, taskPinsPath, concurrentPinsPath, outputPath = assert(process.args[1]), assert(process.args[2]), assert(process.args[3]), assert(process.args[4]), assert(process.args[5])
local function read(path) return serde.decode("json", fs.readFile(path)) end
local function sha(bytes) return serde.hash("sha256", bytes) end
local before, after, taskPins, concurrent = read(beforeDir.."/metadata.json"), read(afterDir.."/metadata.json"), read(taskPinsPath), read(concurrentPinsPath)
local errors, sourceRows, additionRows, rootRows, referenceDeltas, serviceRows = {}, {}, {}, {}, {}, {}
local function check(ok, label) if not ok then table.insert(errors, label) end; return ok end
local function same(a,b)
    if typeof(a)~=typeof(b) then return false end
    if typeof(a)~="table" then return a==b end
    for k,v in a do if not same(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
assert(taskPins.schema=="lobby-endfix-exact-native-scope-v1" and #taskPins.sources==3)
assert(concurrent.schema=="lobby-endfix-explicit-concurrent-native-pins-v1" and #concurrent.concurrentSources==17 and #concurrent.concurrentAddedRoots==3)
assert(#concurrent.expectedExistingNonScriptPropertyDeltas==0, "This audit does not silently accept extra property differences")
local hardScope={
    ["ServerScriptService.LobbyReimaginedPreview.Builder"]={class="ModuleScript",kind="existing"},
    ["ServerScriptService.LobbyReimaginedPreview.EndBlockades"]={class="ModuleScript",kind="new"},
    ["StarterPlayer.StarterPlayerScripts.R4DevGateController"]={class="LocalScript",kind="new"},
}
local specs, extraSources, extraRoots={}, {}, {}
for _,spec in taskPins.sources do
    local hard=assert(hardScope[spec.path]); assert(hard.class==spec.class and hard.kind==spec.kind and not specs[spec.path])
    local candidate=fs.readFile(spec.candidateFile); assert(sha(candidate)==spec.afterSHA256 and #candidate==spec.afterBytes, "Task candidate pin changed")
    specs[spec.path]=spec
end
for _,spec in concurrent.concurrentSources do assert(not specs[spec.path] and not extraSources[spec.path]); extraSources[spec.path]=spec end
for _,spec in concurrent.concurrentAddedRoots do assert(not extraRoots[spec.path]); extraRoots[spec.path]=spec end
assert(before.nativeSHA256==taskPins.expectedBeforeNativeSHA256 and before.nativeSHA256==concurrent.expectedBeforeNativeSHA256 and after.nativeSHA256==concurrent.expectedAfterNativeSHA256)
assert(before.captureId==concurrent.beforeCaptureId and after.captureId==concurrent.afterCaptureId and before.captureId~=after.captureId)
assert(before.placeId==131311258779917 and after.placeId==before.placeId and before.universeId==10559217407 and after.universeId==before.universeId and before.groupId==1039373905 and after.groupId==before.groupId)
assert(before.rootCount==189 and after.rootCount==192 and before.scriptCount==213 and after.scriptCount==222)
assert(#before.editorConflicts==0 and #after.editorConflicts==0 and #before.skipped==0 and #after.skipped==0)

local function load(directory,metadata)
    local bytes=fs.readFile(directory.."/all-service-children.rbxm")
    assert(sha(bytes)==metadata.nativeSHA256 and #bytes==metadata.nativeBytes, "Input native hash/bytes mismatch")
    local roots=rbx.deserializeModel(bytes); assert(#roots==metadata.rootCount and #roots==#metadata.roots)
    local game=rbx.Instance.new("DataModel")
    local services, paths, lookup, byPath, nodesByKey={}, {}, {}, {}, {}
    paths[game]="DataModel"
    for _,row in metadata.services do local s=game:GetService(row.class);s.Name=row.name;services[row.class]=s;paths[s]=row.class end
    local function scan(instance,path,key)
        assert(not nodesByKey[key], "Ambiguous native audit key: "..key)
        paths[instance]=key;nodesByKey[key]={instance=instance,path=path}
        if instance:IsA("LuaSourceContainer") then assert(not byPath[path],"Ambiguous Source path: "..path);byPath[path]=instance end
        local counts={}
        for _,child in instance:GetChildren() do
            local label=child.Name.."|"..child.ClassName;counts[label]=(counts[label] or 0)+1
            scan(child,path.."."..child.Name,key.."/"..label.."#"..tostring(counts[label]))
        end
    end
    for index,root in roots do
        local row=metadata.roots[index]
        assert(root.Name==row.name and root.ClassName==row.class)
        root.Parent=assert(services[row.service]);assert(not lookup[row.path]);lookup[row.path]={instance=root,row=row}
        scan(root,row.path,row.path.."|"..root.ClassName)
    end
    return {roots=roots,lookup=lookup,paths=paths,byPath=byPath,nodesByKey=nodesByKey,metadata=metadata}
end
local b,a=load(beforeDir,before),load(afterDir,after)
local function encoded(value)
    local kind=typeof(value)
    if kind=="nil" then return {type="nil"} end
    if kind=="string" or kind=="number" or kind=="boolean" then return {type=kind,value=value} end
    if kind=="Vector3" then return {type=kind,value={value.X,value.Y,value.Z}} end
    if kind=="Color3" then return {type=kind,value={value.R,value.G,value.B}} end
    if kind=="CFrame" then return {type=kind,value={value:GetComponents()}} end
    if kind=="Content" then return {type=kind,sourceType=tostring(value.SourceType),uri=value.Uri} end
    return {type=kind,value=tostring(value)}
end
local function attrs(instance)
    local result={} for k,v in instance:GetAttributes() do result[k]=encoded(v) end return result
end
local addedRootRows={}
for path,row in a.lookup do
    if not b.lookup[path] then
        local spec=assert(extraRoots[path],"Unpinned added native root: "..path)
        local instance=row.instance
        assert(row.row.class==spec.class and row.row.service==spec.service and #instance:GetDescendants()==spec.descendants)
        local nodes=instance:GetDescendants();table.insert(nodes,1,instance)
        local inventory,classCounts={},{}
        for _,node in nodes do
            classCounts[node.ClassName]=(classCounts[node.ClassName] or 0)+1
            local properties={}
            if node:IsA("BasePart") then
                for _,property in {"CFrame","Size","Anchored","CanCollide","CanTouch","CanQuery","Transparency","Material","Color"} do
                    local ok,value=pcall(function() return node[property] end);if ok then properties[property]=encoded(value) end
                end
            end
            if node:IsA("MeshPart") then
                for _,property in {"MeshContent","TextureContent","MeshId","TextureID"} do local ok,value=pcall(function() return node[property] end);if ok then properties[property]=encoded(value) end end
            end
            table.insert(inventory,{path=a.paths[node],class=node.ClassName,attributes=attrs(node),tags=node:GetTags(),selectedGeometryAssetProperties=properties})
        end
        table.insert(addedRootRows,{path=path,class=instance.ClassName,descendants=#nodes-1,canonicalSHA256=sha(rbx.serializeModel({instance})),classCounts=classCounts,inventory=inventory,scope="Explicit pinned concurrent added root; full saved properties bound by canonical root hash and raw native hash, not gameplay verified"})
    end
end
for path in b.lookup do check(a.lookup[path]~=nil,"Removed existing native root: "..path) end
assert(#addedRootRows==3)

-- Inspect all reflected Instance-reference properties BEFORE any comparison
-- normalization. This also catches references to newly added roots that a
-- serialization of only the old roots might otherwise omit.
local db=rbx.getReflectionDatabase();local refPropertyCache={}
local function refProperties(className)
    if refPropertyCache[className] then return refPropertyCache[className] end
    local result={};local class=db:GetClass(className)
    while class do
        for name,prop in class.Properties do if prop.Datatype=="Ref" then result[name]=true end end
        class=if class.Superclass then db:GetClass(class.Superclass) else nil
    end
    refPropertyCache[className]=result;return result
end
local function refValue(state,value)
    if value==nil then return {nilRef=true} end
    return {path=state.paths[value] or value:GetFullName(),class=value.ClassName}
end
local refChecks=0
for key,entry in b.nodesByKey do
    local path,node=entry.path,entry.instance
    local currentEntry=a.nodesByKey[key];local current=currentEntry and currentEntry.instance
    check(current and current.ClassName==node.ClassName,"Existing native instance missing/class changed: "..path)
    if current and current.ClassName==node.ClassName then
        for property in refProperties(node.ClassName) do
            local ok1,v1=pcall(function()return node[property]end);local ok2,v2=pcall(function()return current[property]end)
            if ok1 and ok2 then
                refChecks+=1;local x,y=refValue(b,v1),refValue(a,v2)
                if not same(x,y) then table.insert(referenceDeltas,{path=path,property=property,before=x,after=y}) end
            else check(ok1==ok2,"Reference property readability changed: "..path.."."..property) end
        end
    end
end
check(#referenceDeltas==0,"Unpinned existing cross-reference/parent property changes")

local beforeSources,afterSources=read(beforeDir.."/scripts.json"),read(afterDir.."/scripts.json")
assert(#beforeSources==213 and #afterSources==222)
local afterByPath={};for _,row in afterSources do assert(not afterByPath[row.path]);afterByPath[row.path]=row end
local existingTask,changedConcurrent,newTask,newConcurrent=0,0,0,0
for _,row in beforeSources do
    local found=assert(afterByPath[row.path],"Existing source removed");assert(found.class==row.class)
    local oldSHA,newSHA=sha(row.source),sha(found.source)
    assert(row.editorMatch and row.editorSourceSha256==oldSHA and found.editorMatch and found.editorSourceSha256==newSHA)
    assert(b.byPath[row.path].Source==row.source and a.byPath[row.path].Source==found.source,"Native Source/catalog mismatch")
    local spec,extra=specs[row.path],extraSources[row.path]
    if spec then
        assert(spec.kind=="existing" and spec.beforeSHA256==oldSHA and spec.afterSHA256==newSHA and #found.source==spec.afterBytes)
        local node=a.byPath[row.path];assert(node:GetAttribute("InstalledSourceSHA256")==newSHA and node:GetAttribute("LobbyReimaginedOwned")==true)
        node:SetAttribute("InstalledSourceSHA256",b.byPath[row.path]:GetAttribute("InstalledSourceSHA256"));node.Source=row.source;existingTask+=1
    elseif oldSHA~=newSHA then
        assert(extra and extra.kind=="changed" and extra.class==row.class and extra.beforeSHA256==oldSHA and extra.afterSHA256==newSHA and extra.beforeBytes==#row.source and extra.afterBytes==#found.source,"Unpinned concurrent Source change: "..row.path)
        a.byPath[row.path].Source=row.source;changedConcurrent+=1
    else assert(not extra,"Pinned concurrent change absent: "..row.path) end
    table.insert(sourceRows,{path=row.path,class=row.class,beforeSHA256=oldSHA,afterSHA256=newSHA,scope=if spec then "task-owned" elseif extra then "explicit-concurrent" else "unchanged",editorMatch=true})
    afterByPath[row.path]=nil
end
for path,row in afterByPath do
    local spec,extra=specs[path],extraSources[path];assert(spec or extra,"Unpinned added Source: "..path)
    local digest=sha(row.source);assert(row.editorMatch and row.editorSourceSha256==digest)
    local node=assert(a.byPath[path]);assert(node.ClassName==row.class and node.Source==row.source and #node:GetDescendants()==0)
    if spec then
        assert(spec.kind=="new" and spec.class==row.class and spec.afterSHA256==digest and spec.afterBytes==#row.source and node:GetAttribute("LobbyReimaginedOwned")==true and node:GetAttribute("InstalledSourceSHA256")==digest);newTask+=1
    else assert(extra.kind=="added" and extra.class==row.class and extra.afterSHA256==digest and extra.afterBytes==#row.source);newConcurrent+=1 end
    table.insert(additionRows,{path=path,class=row.class,sha256=digest,bytes=#row.source,scope=if spec then "task-owned" else "explicit-concurrent",attributes=attrs(node),canonicalSHA256=sha(rbx.serializeModel({node})),editorMatch=true})
    node.Parent=nil -- Deserialized comparison memory only, exact reported addition.
end
assert(existingTask==1 and newTask==2 and changedConcurrent==10 and newConcurrent==7)
local function storage(roots)
    local absent="__EndFixAuditAbsentAttributeStorageKey"
    for _,root in roots do local nodes=root:GetDescendants();table.insert(nodes,root)
        for _,node in nodes do assert(node:GetAttribute(absent)==nil);local old=node:GetAttributes();node:SetAttribute(absent,nil);assert(same(old,node:GetAttributes())) end
    end
end
storage(b.roots);storage(a.roots)
local normalized={}
for _,root in b.roots do
    local path
    for candidate,row in b.lookup do if row.instance==root then path=candidate;break end end
    local current=assert(a.lookup[path]).instance
    local oldHash,newHash=sha(rbx.serializeModel({root})),sha(rbx.serializeModel({current}));local equal=oldHash==newHash
    check(equal,"Unpinned remaining saved properties/geometry: "..path)
    table.insert(rootRows,{path=path,class=root.ClassName,remainingCanonicalEqual=equal,beforeCanonicalSHA256=oldHash,afterExplicitDeltaNormalizationSHA256=newHash})
    if not equal then
        fs.writeFile(outputPath.."."..tostring(#rootRows)..".before.xml",rbx.serializeModel({root},true))
        fs.writeFile(outputPath.."."..tostring(#rootRows)..".after.xml",rbx.serializeModel({current},true))
    end
    table.insert(normalized,current)
end
local oldForest,newForest=sha(rbx.serializeModel(b.roots)),sha(rbx.serializeModel(normalized))
check(oldForest==newForest,"Remaining canonical forest differs")
for _,field in {"services","collisionGroups","collisionMatrix","materialOverrides"} do
    local equal=same(before[field],after[field]);check(equal,"Saved service settings changed: "..field);table.insert(serviceRows,{field=field,equal=equal})
end
local report={schema="lobby-endfix-explicit-concurrent-native-preservation-v1",verified=#errors==0,
    beforeCaptureId=before.captureId,afterCaptureId=after.captureId,beforeNativeSHA256=before.nativeSHA256,afterNativeSHA256=after.nativeSHA256,
    taskPinsSHA256=sha(fs.readFile(taskPinsPath)),concurrentPinsSHA256=sha(fs.readFile(concurrentPinsPath)),
    beforeRootCount=#b.roots,afterRootCount=#a.roots,beforeSourceCount=#beforeSources,afterSourceCount=#afterSources,
    existingScopedSources=existingTask,newScopedSources=newTask,concurrentChangedSources=changedConcurrent,concurrentNewSources=newConcurrent,
    baselineForestCanonicalEqual=oldForest==newForest,remainingForestCanonicalEqual=oldForest==newForest,
    canonicalBeforeSHA256=oldForest,canonicalAfterExplicitDeltaNormalizationSHA256=newForest,
    sourceRows=sourceRows,newSourceRows=additionRows,concurrentAddedRootRows=addedRootRows,rootRows=rootRows,serviceRows=serviceRows,
    existingReferencePropertyChecks=refChecks,existingReferencePropertyDeltas=referenceDeltas,
    existingNonScriptPropertyDeltas={},errors=errors,studioWrites=false,inputBackupWrites=false,
    normalization="Comparison memory only: exact pinned Builder Source/hash, ten explicitly recorded concurrent Sources, and nine exact recorded Source additions. Three exact captured concurrent added roots are reported with all saved properties bound by raw/canonical hashes and geometry inventories, then excluded from the old-root comparison. References to added roots are separately checked before normalization. No arbitrary Source, object, property or geometry difference is accepted.",
    publicationLimits={"Concurrent L4 gameplay, multiplayer and performance not verified by native/source comparison.","Captured L4 Test Suite expects missing Level 4 Usher Nav while controller has marker fallback; test mismatch is recorded, not repaired.","Capture records exact differences, not author identity; concurrent attribution comes from scoped write receipts and root task context."}}
fs.writeFile(outputPath,serde.encode("json",report,true).."\n")
print(serde.encode("json",{verified=report.verified,errors=errors,remainingForestCanonicalEqual=report.remainingForestCanonicalEqual,existingReferencePropertyChecks=refChecks,concurrentChangedSources=changedConcurrent,concurrentNewSources=newConcurrent,concurrentAddedRoots=#addedRootRows,output=outputPath},true))
assert(report.verified,"Unexplained concurrent native delta; preserve current Studio, never restore historical backup")
