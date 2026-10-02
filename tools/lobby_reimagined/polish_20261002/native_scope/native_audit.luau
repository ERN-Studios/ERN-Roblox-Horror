-- Disk-only native preservation audit. Never opens Studio or writes either input.
local fs,serde,rbx=require("@lune/fs"),require("@lune/serde"),require("@lune/roblox")
local M={}
local OWNED="LobbyReimaginedOwned"
local HARD={
 ["ServerScriptService.LobbyReimaginedPreview.Builder"]={class="ModuleScript",new=false},
 ["ServerScriptService.LobbyReimaginedPreview.EndBlockades"]={class="ModuleScript",new=false},
 ["StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController"]={class="LocalScript",new=false},
 ["ServerScriptService.LobbyReimaginedPreview.MaterialPolish"]={class="ModuleScript",new=true},
 ["ServerScriptService.LobbyReimaginedPreview.LobbyPolishBays"]={class="ModuleScript",new=true},
 ["ServerScriptService.LobbyReimaginedPreview.LobbyPolishScene"]={class="ModuleScript",new=true},
}
local function sha(value)return serde.hash("sha256",value)end
local function read(path)return serde.decode("json",fs.readFile(path))end
local function same(x,y)
 if typeof(x)~=typeof(y)then return false end
 if typeof(x)~="table"then return x==y end
 for k,v in x do if not same(v,y[k])then return false end end
 for k in y do if x[k]==nil then return false end end
 return true
end
local function rootKey(row)return row.service.."|"..row.name.."|"..row.class end
local function load(directory)
 local meta=read(directory.."/metadata.json")
 local raw=fs.readFile(directory.."/all-service-children.rbxm")
 assert(sha(raw)==meta.nativeSHA256 and #raw==meta.nativeBytes,"Native capture bytes/hash differs: "..directory)
 local roots=rbx.deserializeModel(raw)
 assert(#roots==meta.rootCount and #roots==#meta.roots,"Native root inventory differs")
 local game=rbx.Instance.new("DataModel");local services,lookup,source={}, {}, {}
 for _,row in meta.services do local s=game:GetService(row.class);s.Name=row.name;services[row.class]=s end
 for i,node in roots do local row=meta.roots[i];assert(node.Name==row.name and node.ClassName==row.class)
  node.Parent=assert(services[row.service]);local key=rootKey(row);assert(not lookup[key],"Ambiguous native root")
  lookup[key]={node=node,row=row}
 end
 local function resolve(path)
  local best
  for _,row in meta.roots do if path==row.path or path:sub(1,#row.path+1)==row.path.."."then
   if not best or #row.path>#best.path then best=row end
  end end
  if not best then return nil end
  local node=lookup[rootKey(best)].node
  for token in path:sub(#best.path+2):gmatch("[^%.]+")do
   local found
   for _,child in node:GetChildren()do if child.Name==token then assert(not found,"Ambiguous exact path "..path);found=child end end
   node=found;if not node then return nil end
  end
  return node
 end
 local rows=read(directory.."/scripts.json")
 assert(#rows==meta.scriptCount,"Source catalog count differs")
 for _,row in rows do assert(not source[row.path],"Ambiguous Source catalog");source[row.path]=row end
 return {dir=directory,meta=meta,roots=roots,lookup=lookup,resolve=resolve,source=source,rows=rows,services=services}
end
local function storage(roots)
 -- Normalize only absent versus explicitly empty attribute storage in memory.
 -- Actual values are checked unchanged; no real attribute is discarded.
 local key="__LobbyPolishNativeAuditAbsentStorageKey"
 for _,root in roots do local nodes=root:GetDescendants();table.insert(nodes,root)
  for _,node in nodes do assert(node:GetAttribute(key)==nil);local old=node:GetAttributes()
   node:SetAttribute(key,nil);assert(same(old,node:GetAttributes()),"Attribute storage normalization changed data")
  end
 end
end
local function uri(node,property)
 -- Modern native files store Content fields; Lune may not expose the migrated
 -- legacy ContentId alias after deserialization. Read the saved Content first.
 local ok,v=pcall(function()return node[property.."Content"]end)
 if not ok then ok,v=pcall(function()return node[property]end)end
 if not ok then return nil end
 if typeof(v)=="Content"then return v.SourceType==rbx.Enum.ContentSourceType.Uri and v.Uri or "" end
 return tostring(v)
end
local function namedChildren(node)
 local result={};for _,child in node:GetChildren()do assert(not result[child.Name],"Ambiguous task-owned child");result[child.Name]=child end
 return result
end
local function pathKey(state,node)
 if not node then return {nilRef=true}end
 local chain={};local cursor=node
 while cursor and cursor~=state.services[cursor.ClassName] do
  local parent=cursor.Parent;local ordinal=1
  if parent then for _,sibling in parent:GetChildren()do
   if sibling==cursor then break end
   if sibling.Name==cursor.Name and sibling.ClassName==cursor.ClassName then ordinal+=1 end
  end end
  table.insert(chain,1,cursor.Name.."|"..cursor.ClassName.."#"..ordinal);cursor=parent
 end
 return {key=table.concat(chain,"/"),service=cursor and cursor.ClassName or "detached",class=node.ClassName}
end
local function encode(value,state)
 local t=typeof(value)
 if t=="nil"then return {type=t}end
 if t=="string"then
  if #value>300 or value:find("[^%z\1-\127]")then return {type=t,bytes=#value,sha256=sha(value)}end
  return {type=t,value=value}
 end
 if t=="boolean"then return {type=t,value=value}end
 if t=="number"then return {type=t,value=if value==value and math.abs(value)<math.huge then value else tostring(value)}end
 if t=="Instance"then return {type=t,value=pathKey(state,value)}end
 if t=="Vector2"then return {type=t,value={value.X,value.Y}}end
 if t=="Vector3"then return {type=t,value={value.X,value.Y,value.Z}}end
 if t=="Color3"then return {type=t,value={value.R,value.G,value.B}}end
 if t=="CFrame"then return {type=t,value={value:GetComponents()}}end
 if t=="Content"then return {type=t,sourceType=tostring(value.SourceType),uri=value.SourceType==rbx.Enum.ContentSourceType.Uri and value.Uri or ""}end
 if t=="buffer"then local s=buffer.tostring(value);return {type=t,bytes=#s,sha256=sha(s)}end
 return {type=t,value=tostring(value)}
end
local function attributes(node,state)local r={};for k,v in node:GetAttributes()do r[k]=encode(v,state)end;return r end
local db=rbx.getReflectionDatabase();local propertyCache={}
local function properties(className)
 if propertyCache[className]then return propertyCache[className]end
 local names={};local class=db:GetClass(className)
 while class do for name,prop in class.Properties do names[name]=prop.Datatype end
  class=if class.Superclass then db:GetClass(class.Superclass)else nil
 end
 propertyCache[className]=names;return names
end
local function diagnostic(before,after,old,new,path,rows)
 if not old or not new then
  local node=old or new;table.insert(rows,{path=path,class=node.ClassName,kind=if old then "removed"else "added",
   descendants=#node:GetDescendants(),canonicalSHA256=sha(rbx.serializeModel({node})),attributes=attributes(node,if old then before else after)})
  return
 end
 if old.ClassName~=new.ClassName then table.insert(rows,{path=path,kind="classChanged",beforeClass=old.ClassName,afterClass=new.ClassName});return end
 local delta={};local refs={};local unreadable={}
 for property,datatype in properties(old.ClassName)do
  if property~="AttributesSerialize" and property~="Tags" and property~="Source"then
   local ok1,x=pcall(function()return old[property]end);local ok2,y=pcall(function()return new[property]end)
   if ok1 and ok2 then local ex,ey=encode(x,before),encode(y,after)
    if not same(ex,ey)then local row={property=property,before=ex,after=ey}
     table.insert(if datatype=="Ref"then refs else delta,row)
    end
   elseif ok1~=ok2 then table.insert(unreadable,{property=property,beforeReadable=ok1,afterReadable=ok2})end
  end
 end
 local a,b=attributes(old,before),attributes(new,after)
 local oldTags,newTags=old:GetTags(),new:GetTags();table.sort(oldTags);table.sort(newTags)
 if #delta>0 or #refs>0 or #unreadable>0 or not same(a,b)or not same(oldTags,newTags)then
  table.insert(rows,{path=path,class=old.ClassName,kind="propertiesChanged",properties=delta,references=refs,
   readabilityChanges=unreadable,attributesBefore=a,attributesAfter=b,tagsBefore=oldTags,tagsAfter=newTags})
 end
 local function children(node)local r={};local counts={};for _,child in node:GetChildren()do
  local label=child.Name.."|"..child.ClassName;counts[label]=(counts[label]or 0)+1;r[label.."#"..counts[label]]=child
 end;return r end
 local oc,nc=children(old),children(new)
 for key,node in oc do diagnostic(before,after,node,nc[key],path.."/"..key,rows);nc[key]=nil end
 for key,node in nc do diagnostic(before,after,nil,node,path.."/"..key,rows)end
end

local function referenceAndSourceInventory(before,after,rows,check)
 -- Inspect saved references before task modules leave the local comparison.
 -- Serializing a referent outside a root/forest can otherwise turn it into nil.
 local counts={before=0,after=0};local referencesChecked=0
 local function inventory(state,node,path,label)
  if node:IsA("LuaSourceContainer")then
   counts[label]+=1
   local row=state.source[path]
   check(row and row.class==node.ClassName and row.source==node.Source,"Native Source missing from full live catalog: "..label.."/"..path)
  end
 end
 local function added(state,node,path,label)
  inventory(state,node,path,label)
  for _,child in node:GetChildren()do added(state,child,path.."."..child.Name,label)end
 end
 local function children(node)
  local result,ordinal={},{}
  for _,child in node:GetChildren()do local label=child.Name.."|"..child.ClassName
   ordinal[label]=(ordinal[label]or 0)+1;result[label.."#"..ordinal[label]]=child
  end
  return result
 end
 local function paired(old,new,path)
  if not old then added(after,new,path,"after");return end
  if not new then added(before,old,path,"before");return end
  inventory(before,old,path,"before");inventory(after,new,path,"after")
  if old.ClassName==new.ClassName then
   for property,datatype in properties(old.ClassName)do if datatype=="Ref"and property~="Parent"then
    local ok1,x=pcall(function()return old[property]end);local ok2,y=pcall(function()return new[property]end)
    if ok1 and ok2 then
     referencesChecked+=1
     local bx,ay=encode(x,before),encode(y,after)
     if not same(bx,ay)then table.insert(rows,{path=path,kind="existingReferenceChanged",property=property,before=bx,after=ay})end
    elseif ok1~=ok2 then table.insert(rows,{path=path,kind="referenceReadabilityChanged",property=property,beforeReadable=ok1,afterReadable=ok2})end
   end end
  end
  local oc,nc=children(old),children(new)
  for key,child in oc do paired(child,nc[key],path.."."..child.Name);nc[key]=nil end
  for _,child in nc do added(after,child,path.."."..child.Name,"after")end
 end
 for key,entry in before.lookup do local current=after.lookup[key];paired(entry.node,current and current.node,entry.row.path)end
 for key,entry in after.lookup do if not before.lookup[key]then added(after,entry.node,entry.row.path,"after")end end
 check(counts.before==#before.rows and counts.after==#after.rows,"Native and full live Source catalog counts differ")
 return {before=counts.before,after=counts.after,referencesChecked=referencesChecked}
end

function M.audit(config)
 local before,after=load(config.before),load(config.after)
 local frozen,critical,asset,uploads=read(config.frozen),read(config.critical),read(config.assetManifest),read(config.uploads)
 local errors,sourceRows,newRows,rootRows,serviceRows,sourceDeltas,nativeDeltas={},{},{},{},{},{},{}
 local function check(ok,label)if not ok then table.insert(errors,label)end;return ok end
 assert(before.meta.nativeSHA256==config.expectedBeforeNativeSHA256,"Wrong authoritative before native forest")
 assert(before.meta.placeId==131311258779917 and after.meta.placeId==before.meta.placeId
  and before.meta.universeId==10559217407 and after.meta.universeId==before.meta.universeId
  and before.meta.groupId==1039373905 and after.meta.groupId==before.meta.groupId,"Wrong experience/owner")
 check(config.allowSameCapture==true or before.meta.captureId~=after.meta.captureId,"Before/after capture IDs are not distinct")
 check(#before.meta.editorConflicts==0 and #after.meta.editorConflicts==0 and #before.meta.skipped==0 and #after.meta.skipped==0,"Capture has editor conflicts or skipped roots")
 local criticalByPath={};for _,row in critical do criticalByPath[row.path]=row end
 assert(#frozen==6,"Expected exactly six frozen task sources")
 local specs={};for _,row in frozen do local expected=assert(HARD[row.path],"Unexpected frozen task Source")
  assert(expected.class==row.className and expected.new==row.new and not specs[row.path],"Frozen task kind/class differs")
  local text=fs.readFile(row.file);assert(sha(text)==row.sha256,"Frozen candidate changed: "..row.path)
  specs[row.path]={path=row.path,class=row.className,new=row.new,sha=row.sha256,bytes=#text,file=row.file}
 end
 print("Native audit: catalogs and exact task scope")
 for _,state in {before,after}do
  for _,row in state.rows do local digest=sha(row.source);local node=state.resolve(row.path)
   check(row.editorMatch==true and row.editorSourceSha256==digest and row.sourceSha256==digest and row.sourceBytes==#row.source,"Source/editor/export differs: "..state.dir.."/"..row.path)
   check(node and node.ClassName==row.class and node.Source==row.source,"Native Source differs from full live catalog: "..row.path)
  end
 end
 local nativeInventory=referenceAndSourceInventory(before,after,nativeDeltas,check)
 for path,row in before.source do local found=after.source[path];local spec=specs[path]
  local oldSHA=sha(row.source);local newSHA=found and sha(found.source)
  check(found and found.class==row.class,"Existing Source removed/class changed: "..path)
  if spec then
   local prior=criticalByPath[path];local node=after.resolve(path)
   check(not spec.new and prior and prior.class==row.class and prior.sourceSha256==oldSHA
    and spec.sha==newSHA and found and #found.source==spec.bytes,"Scoped existing Source pin differs: "..path)
   check(node and node:GetAttribute("InstalledSourceSHA256")==spec.sha,"Scoped installed hash differs: "..path)
   if node then node.Source=row.source;node:SetAttribute("InstalledSourceSHA256",before.resolve(path):GetAttribute("InstalledSourceSHA256"))end
  elseif oldSHA~=newSHA then table.insert(sourceDeltas,{path=path,class=row.class,kind=if found then "changed"else "removed",beforeSHA256=oldSHA,afterSHA256=newSHA,beforeBytes=#row.source,afterBytes=found and #found.source,scope="unclassified-concurrent"})end
  table.insert(sourceRows,{path=path,class=row.class,beforeSHA256=oldSHA,afterSHA256=newSHA,taskOwned=spec~=nil,editorMatch=found and found.editorMatch==true})
 end
 local uploaded={};for url,id in uploads do local filename=url:match("([^/]+)$");assert(filename and not uploaded[filename]);uploaded[filename]=id end
 for path,row in after.source do if not before.source[path]then local spec=specs[path];local node=after.resolve(path)
  if not spec then table.insert(sourceDeltas,{path=path,class=row.class,kind="added",afterSHA256=sha(row.source),afterBytes=#row.source,scope="unclassified-concurrent"})
  else
   check(spec.new and spec.class==row.class and spec.sha==sha(row.source)and spec.bytes==#row.source,"New task Source pin differs: "..path)
   check(node and node:GetAttribute(OWNED)==true and node:GetAttribute("InstalledSourceSHA256")==spec.sha,"New task Source ownership/hash differs: "..path)
   local children=node and namedChildren(node)or {}
   if node and path:match("%.MaterialPolish$")then
    check(#node:GetDescendants()==5 and children.StaticPBRMaterials and children.SidewalkAtlas,"MaterialPolish exact child set differs")
    local folder=children.StaticPBRMaterials;local atlas=children.SidewalkAtlas
    check(folder and folder.ClassName=="Folder"and folder:GetAttribute(OWNED)==true and folder:GetAttribute("Ready")==true and #folder:GetChildren()==3,"Material template folder differs")
    if folder then local maps=namedChildren(folder)
     for key,specMap in asset.assetSpec.materials do local template=maps[key]
      check(template and template.ClassName=="SurfaceAppearance"and template:GetAttribute(OWNED)==true,"Static material class/ownership differs: "..key)
      if template then
       check(template.AlphaMode==rbx.Enum.AlphaMode.Overlay and template.Color==rbx.Color3.new(1,1,1),"Static material alpha/tint differs: "..key)
       check(uri(template,"MetalnessMap")=="","Static material metalness differs: "..key)
       check(uri(template,"EmissiveMask")=="","Unexpected emissive mask on static material: "..key)
       for role,property in {color="ColorMap",normal="NormalMap",roughness="RoughnessMap"}do
        check(uri(template,property)==uploaded[key.."_"..role..".png"]and template:GetAttribute(role.."PNG_SHA256")==specMap[role].pngSHA256,"Static material URI/PNG pin differs: "..key.."/"..role)
       end
      end
     end
    end
    check(atlas and atlas.ClassName=="StringValue"and atlas:GetAttribute(OWNED)==true
     and "rbxassetid://"..atlas.Value==uploaded["sidewalk_joint_atlas.png"]and atlas:GetAttribute("PNG_SHA256")==asset.assetSpec.sidewalkAtlas.pngSHA256,"SidewalkAtlas URI/PNG pin differs")
   else check(node and #node:GetDescendants()==0,"Unexpected new helper descendants: "..path)end
   table.insert(newRows,{path=path,class=row.class,sha256=spec.sha,bytes=spec.bytes,descendants=node and #node:GetDescendants(),canonicalSHA256=node and sha(rbx.serializeModel({node})),attributes=node and attributes(node,after)})
   if node then node.Parent=nil end -- Only exact pinned new task-owned modules, in deserialized memory.
  end
 end end
 for path,spec in specs do
  check(after.source[path]~=nil,"Missing frozen task Source: "..path)
  check((before.source[path]==nil)==spec.new,"Task source existence/kind differs: "..path)
 end
 print("Native audit: canonical storage and full saved forest")
 storage(before.roots);storage(after.roots)
 local pairedAfter={};local serverLobby
 for _,root in before.roots do
  local prior;for _,entry in before.lookup do if entry.node==root then prior=entry;break end end
  local current=after.lookup[rootKey(prior.row)]
  local oldHash=sha(rbx.serializeModel({root}));local newHash=current and sha(rbx.serializeModel({current.node}))
  local equal=oldHash==newHash
  local row={path=prior.row.path,class=root.ClassName,unchangedBeyondTaskScope=equal,beforeCanonicalSHA256=oldHash,afterTaskNormalizedCanonicalSHA256=newHash}
  table.insert(rootRows,row)
  if prior.row.path=="Workspace.ServerLobby"then serverLobby=row end
  if current then table.insert(pairedAfter,current.node)end
  if not equal then
   diagnostic(before,after,root,current and current.node,prior.row.path,nativeDeltas)
   table.insert(nativeDeltas,{path=prior.row.path,kind="savedRootFingerprintChanged",beforeCanonicalSHA256=oldHash,afterTaskNormalizedCanonicalSHA256=newHash,allSavedDataBoundByRawNativeCapture=true})
  end
 end
 for key,row in after.lookup do if not before.lookup[key]then
  diagnostic(before,after,nil,row.node,row.row.path,nativeDeltas)
 end end
 local oldForest=sha(rbx.serializeModel(before.roots));local afterForest=sha(rbx.serializeModel(pairedAfter))
 local equal=oldForest==afterForest and #before.roots==#after.roots
 for _,field in {"services","collisionGroups","collisionMatrix","materialOverrides"}do
  local identical=same(before.meta[field],after.meta[field]);table.insert(serviceRows,{field=field,equal=identical})
  if not identical then table.insert(nativeDeltas,{path="saved-settings",kind="metadataChanged",field=field,before=before.meta[field],after=after.meta[field]})end
 end
 check(serverLobby~=nil and serverLobby.unchangedBeyondTaskScope,"Original ServerLobby native fingerprint changed or missing")
 local report={schema="lobby-polish-full-native-scope-v1",verified=#errors==0 and equal and #sourceDeltas==0 and #nativeDeltas==0,
  taskScopeVerified=#errors==0,wholeForestPreservedBeyondTaskScope=equal and #nativeDeltas==0,
  beforeCaptureId=before.meta.captureId,afterCaptureId=after.meta.captureId,beforeNativeSHA256=before.meta.nativeSHA256,afterNativeSHA256=after.meta.nativeSHA256,
  beforeRootCount=#before.roots,afterRootCount=#after.roots,beforeSourceCount=#before.rows,afterSourceCount=#after.rows,nativeSourceInventory=nativeInventory,
  frozenSourcesSHA256=sha(fs.readFile(config.frozen)),criticalSourcesSHA256=sha(fs.readFile(config.critical)),uploadedAssetsSHA256=sha(fs.readFile(config.uploads)),
  canonicalBeforeSHA256=oldForest,canonicalAfterTaskNormalizationSHA256=afterForest,
  serverLobby=serverLobby,sourceRows=sourceRows,newTaskSourceRows=newRows,rootRows=rootRows,serviceRows=serviceRows,
  unclassifiedConcurrentSourceDeltas=sourceDeltas,unclassifiedConcurrentNativeDeltas=nativeDeltas,errors=errors,
  studioWrites=false,inputBackupWrites=false,
  normalization="Deserialized memory only: three exact pinned existing Sources and their InstalledSourceSHA256 attributes reset to before values; three exact pinned new modules and validated child subtrees omitted. Real attribute values preserved while absent/empty serialized storage is normalized equally. Concurrent/unclassified differences are reported and never normalized away or restored.",
  limits={"Native preservation and full Source/editor catalog parity are not gameplay/performance/multiplayer checks.","Unclassified deltas require owner review. This audit does not infer author identity or authorization.","Readable reflected properties and cross-references diagnose changed roots; raw/canonical hashes additionally bind all saved properties and opaque data."}}
 if config.output then fs.writeFile(config.output,serde.encode("json",report,true).."\n")end
 return report
end
return M
