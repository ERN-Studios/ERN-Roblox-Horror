-- Explicit exact concurrent exceptions, approved for preservation by root. No Studio writes.
-- Local native snapshot comparison only. Mutations are confined to deserialized
-- in-memory copies used to normalize the explicitly allowed scoped Source edits.
local fs=require("@lune/fs")
local process=require("@lune/process")
local serde=require("@lune/serde")
local rbx=require("@lune/roblox")
local beforeDir=assert(process.args[1],"Pass before checkpoint directory")
local afterDir=assert(process.args[2],"Pass after checkpoint directory")
local catalogPath=assert(process.args[3],"Pass final scoped source catalog")
local outputPath=assert(process.args[4],"Pass output receipt path")
local concurrentPath=assert(process.args[5],"Pass exact acknowledged concurrent difference catalog")
local function read(path)return serde.decode("json",fs.readFile(path))end
local function sha(raw)return serde.hash("sha256",raw)end
local before=read(beforeDir.."/metadata.json")
local after=read(afterDir.."/metadata.json")
local catalog=read(catalogPath)
local concurrent=read(concurrentPath)
assert(concurrent.afterCaptureId==after.captureId and concurrent.afterNativeSHA256==after.nativeSHA256,"Wrong concurrent capture")
local concurrentChanged,concurrentAdded,concurrentRoots={},{},{}
for _,row in concurrent.changedUnrelatedSourceRows do concurrentChanged[row.path]=row end
for _,row in concurrent.addedSourceRows do concurrentAdded[row.path]=row end
for _,row in concurrent.addedNativeRoots do
 if row.path~="ServerStorage."..catalog.payload.sourceName then concurrentRoots[row.path]=row end
end
assert(#concurrent.changedUnrelatedSourceRows==2 and #concurrent.addedSourceRows==3,"Unexpected acknowledged concurrent Source scope")
local concurrentRows,concurrentRootRows={},{}
assert(before.placeId==131311258779917 and after.placeId==before.placeId
 and before.universeId==10559217407 and after.universeId==before.universeId,"Wrong place/universe")
assert(before.groupId==1039373905 and after.groupId==before.groupId,"Wrong owner")
local errors,sourceRows,rootRows,serviceRows={},{},{},{}
local function check(value,label)
 if not value then table.insert(errors,label)end
 return value
end
local function same(a,b)
 if typeof(a)~=typeof(b)then return false end
 if typeof(a)~="table"then return a==b end
 for key,value in a do if not same(value,b[key])then return false end end
 for key in b do if a[key]==nil then return false end end
 return true
end
local function native(directory,metadata)
 local bytes=fs.readFile(directory.."/all-service-children.rbxm")
 assert(sha(bytes)==metadata.nativeSHA256 and #bytes==metadata.nativeBytes,"Wrong native forest bytes")
 local roots=rbx.deserializeModel(bytes)
 assert(#roots==metadata.rootCount and #roots==#metadata.roots,"Wrong native root count")
 local game=rbx.Instance.new("DataModel")
 local services,lookup={},{ }
 for _,row in metadata.services do local s=game:GetService(row.class);s.Name=row.name;services[row.class]=s end
 for i,root in roots do
  local row=metadata.roots[i]
  assert(root.Name==row.name and root.ClassName==row.class,"Wrong root identity")
  root.Parent=assert(services[row.service])
  local key=row.service.."|"..row.name.."|"..row.class
  assert(not lookup[key],"Ambiguous duplicate root identity "..row.path)
  lookup[key]={instance=root,row=row}
 end
 local function resolve(path)
  local best
  for _,row in metadata.roots do
   if path==row.path or path:sub(1,#row.path+1)==row.path.."."then
    if not best or #row.path>#best.path then best=row end
   end
  end
  if not best then return nil end
  local cursor=services[best.service]:FindFirstChild(best.name)
  for token in path:sub(#best.path+2):gmatch("[^%.]+")do cursor=cursor and cursor:FindFirstChild(token)end
  return cursor
 end
 return roots,lookup,resolve
end
local beforeRoots,beforeLookup,resolveBefore=native(beforeDir,before)
local afterRoots,afterLookup,resolveAfter=native(afterDir,after)
local function canonicalizeEmptyAttributeStorage(roots)
 -- Lune can encode an absent AttributesSerialize field differently from an
 -- explicit empty field after a round trip. Apply an absent nil key on both
 -- copies; assert that every actual attribute value remains byte-for-byte or
 -- datatype-equal. This is serialization normalization, not a game change.
 local key="__R4AuditAbsentAttributeStorageKey"
 for _,root in roots do
  local nodes=root:GetDescendants();table.insert(nodes,root)
  for _,instance in nodes do
   assert(instance:GetAttribute(key)==nil,"Audit normalization key unexpectedly exists")
   local old=instance:GetAttributes()
   instance:SetAttribute(key,nil)
   assert(same(old,instance:GetAttributes()),"Attribute value changed during normalization")
  end
 end
end
canonicalizeEmptyAttributeStorage(beforeRoots)
canonicalizeEmptyAttributeStorage(afterRoots)
local specs={}
local expectedScopedSources=#catalog.sources
assert((expectedScopedSources==7 or expectedScopedSources==8) and catalog.payload.additiveOnly==true,"Unexpected source/payload scope")
for _,spec in catalog.sources do assert(not specs[spec.path]);specs[spec.path]=spec end
local beforeSources=read(beforeDir.."/scripts.json")
local afterSources=read(afterDir.."/scripts.json")
local afterSourceLookup={}
for _,row in afterSources do assert(not afterSourceLookup[row.path]);afterSourceLookup[row.path]=row end
check(#afterSources==#beforeSources+3,"Source count differs from eight updates plus exact three concurrent additions")
local changed=0
for _,row in beforeSources do
 local found=afterSourceLookup[row.path]
 local spec=specs[row.path]
 local beforeSHA=sha(row.source)
 local afterSHA=found and sha(found.source)
 local classMatch=found and found.class==row.class
 local editorMatch=found and found.editorMatch==true and found.editorSourceSha256==afterSHA
 check(row.editorMatch==true and row.editorSourceSha256==beforeSHA,"Before editor receipt mismatch: "..row.path)
 check(classMatch and editorMatch,"After Source/class/editor mismatch: "..row.path)
 if spec then
  check(spec.class==row.class and spec.expectedSourceSHA256==beforeSHA,"Catalog baseline differs: "..row.path)
  check(spec.afterSHA256==afterSHA,"After Source differs from final catalog: "..row.path)
  local b=assert(resolveBefore(row.path))
  local a=assert(resolveAfter(row.path))
  assert(b.ClassName==row.class and a.ClassName==row.class)
  check(b.Source==row.source and a.Source==found.source,"Native Source receipt differs: "..row.path)
  if spec.owned then
   check(a:GetAttribute("InstalledSourceSHA256")==afterSHA,"Installed Source hash attribute differs: "..row.path)
   local oldInstalledSHA=b:GetAttribute("InstalledSourceSHA256")
   -- Reapply the same value on both deserialized copies to canonicalize Lune's
   -- attribute storage representation, without changing any before value.
   b:SetAttribute("InstalledSourceSHA256",oldInstalledSHA)
   a:SetAttribute("InstalledSourceSHA256",oldInstalledSHA)
  end
  a.Source=b.Source -- Only in-memory audit normalization; never a Studio write.
  changed+=1
 else
  local exception=concurrentChanged[row.path]
  if exception then
   check(exception.class==row.class and exception.beforeSourceSHA256==beforeSHA and exception.sourceSHA256==afterSHA and exception.bytes==#found.source,"Concurrent Source pin differs: "..row.path)
   local b=assert(resolveBefore(row.path));local a=assert(resolveAfter(row.path))
   check(b.Source==row.source and a.Source==found.source,"Concurrent native Source receipt differs: "..row.path)
   a.Source=b.Source -- Local comparison memory only. Both full native artifacts stay untouched.
   table.insert(concurrentRows,{path=row.path,class=row.class,beforeSHA256=beforeSHA,afterSHA256=afterSHA,editorMatch=editorMatch,kind="changed existing concurrent Source"})
  else check(beforeSHA==afterSHA,"Unrecorded unrelated Source changed: "..row.path) end
 end
 table.insert(sourceRows,{path=row.path,class=row.class,beforeSHA256=beforeSHA,afterSHA256=afterSHA,
  scoped=spec~=nil,sourceUnchanged=beforeSHA==afterSHA,editorMatch=editorMatch==true})
 afterSourceLookup[row.path]=nil
end
local addedCount=0
for path,row in afterSourceLookup do
 local exception=concurrentAdded[path]
 check(exception~=nil,"Unrecorded additional Source: "..path)
 if exception then
  local sourceSHA=sha(row.source)
  local instance=assert(resolveAfter(path))
  check(row.class==exception.class and sourceSHA==exception.sourceSHA256 and #row.source==exception.bytes
   and row.editorMatch==true and row.editorSourceSha256==sourceSHA and instance.Source==row.source,"Concurrent added Source pin differs: "..path)
  table.insert(concurrentRows,{path=path,class=row.class,afterSHA256=sourceSHA,editorMatch=row.editorMatch,kind="new concurrent Source"})
  -- Descendant additions are omitted only in the local normalized comparison.
  -- An additive root is already omitted when selecting the original baseline roots.
  if not concurrentRoots[path]then instance.Parent=nil end
  addedCount+=1
 end
end
check(addedCount==3,"Missing exact concurrent Source additions")
check(changed==expectedScopedSources,"Not all scoped catalog Sources were compared")
local expectedAddition="ServerStorage|"..catalog.payload.sourceName.."|Folder"
local addedRoots={}
for key,row in afterLookup do
 if not beforeLookup[key]then
  table.insert(addedRoots,{path=row.row.path,class=row.row.class,descendants=#row.instance:GetDescendants()})
  local exception=concurrentRoots[row.row.path]
  check(key==expectedAddition or exception~=nil,"Unrecorded additive native root: "..row.row.path)
  if exception then
   check(row.row.class==exception.class and row.row.service==exception.service and row.row.name==exception.name and #row.instance:GetDescendants()==exception.descendants,"Concurrent additive root identity differs: "..row.row.path)
   table.insert(concurrentRootRows,{path=row.row.path,class=row.row.class,descendants=#row.instance:GetDescendants(),canonicalNativeSHA256=sha(rbx.serializeModel({row.instance})),kind="acknowledged concurrent additive root; full bytes retained"})
  end
  if key==expectedAddition then
   check(row.instance:GetAttribute("LobbyReimaginedOwned")==true and row.instance:GetAttribute("Ready")==true,"R4 root ownership/readiness differs")
   check(row.instance:GetAttribute("ManifestSHA256")==catalog.payload.manifestSHA256,"R4 root manifest pin differs")
  end
 end
end
check(#addedRoots==3 and #concurrentRootRows==2,"Expected exactly one R4 root plus two acknowledged concurrent roots")
local normalizedAfterRoots={}
for _,root in beforeRoots do
 local key
 for candidate,row in beforeLookup do if row.instance==root then key=candidate;break end end
 local match=afterLookup[key]
 check(match~=nil,"Existing native root removed: "..beforeLookup[key].row.path)
 if match then
  local b=sha(rbx.serializeModel({root}))
  local a=sha(rbx.serializeModel({match.instance}))
  check(a==b,"Existing native root differs beyond scoped Source/hash attributes: "..match.row.path)
  table.insert(rootRows,{path=match.row.path,class=match.row.class,normalizedCanonicalEqual=a==b,beforeCanonicalSHA256=b,afterNormalizedCanonicalSHA256=a})
  table.insert(normalizedAfterRoots,match.instance)
 end
end
local beforeCanonical=sha(rbx.serializeModel(beforeRoots))
local afterNormalizedCanonical=sha(rbx.serializeModel(normalizedAfterRoots))
check(beforeCanonical==afterNormalizedCanonical,"Whole baseline forest differs beyond exact scoped normalization")
for _,field in {"services","collisionGroups","collisionMatrix","materialOverrides"}do
 local equal=same(before[field],after[field])
 check(equal,"Saved service/settings receipt changed: "..field)
 table.insert(serviceRows,{field=field,equal=equal})
end
local report={schema="lobby-r4-accounted-concurrent-native-preservation-v1",verified=#errors==0,
 strictOnlyTaskPreservationVerified=false,allUnrelatedStateUnchanged=false,
 concurrentChangesAcknowledged=true,allDifferencesAccountedAfterExactLocalNormalization=#errors==0,
 concurrentDifferenceCatalogSHA256=sha(fs.readFile(concurrentPath)),concurrentSourceRows=concurrentRows,concurrentNativeRootRows=concurrentRootRows,
 scope="Independent exact before/after native comparison accounting explicitly acknowledged concurrent developer changes; not an unchanged-state claim, authorization to deploy, or Studio action",
 beforeCaptureId=before.captureId,afterCaptureId=after.captureId,beforeNativeSHA256=before.nativeSHA256,afterNativeSHA256=after.nativeSHA256,
 catalogSHA256=sha(fs.readFile(catalogPath)),beforeSourceCount=#beforeSources,afterSourceCount=#afterSources,
 scopedSourceCount=changed,beforeRootCount=#beforeRoots,afterRootCount=#afterRoots,
 canonicalBeforeSHA256=beforeCanonical,canonicalAfterScopedNormalizationSHA256=afterNormalizedCanonical,
 baselineForestCanonicalEqual=beforeCanonical==afterNormalizedCanonical,
 sourceRows=sourceRows,rootRows=rootRows,serviceRows=serviceRows,additiveRoots=addedRoots,errors=errors,
 normalization="Exact eight task-catalog Sources, two pinned concurrent existing Sources and three owned InstalledSourceSHA attributes reset in local comparison memory; exact three concurrent Source additions and one R4 plus two concurrent roots omitted only from normalized comparison. Every other native property, source, root and saved service/settings field must equal baseline. Full before and after artifacts remain unchanged and preserve all concurrent bytes; this is not an all-unrelated-unchanged claim."}
fs.writeFile(outputPath,serde.encode("json",report,true).."\n")
print(serde.encode("json",{verified=report.verified,errors=errors,scopedSourceCount=changed,baselineForestCanonicalEqual=report.baselineForestCanonicalEqual,output=outputPath},true))
assert(report.verified,"Unrecorded before/after differences remain; preserve observed data, never restore old Studio state")
