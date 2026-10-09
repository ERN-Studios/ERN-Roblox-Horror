-- Shared by explicitly invoked capture/move/verify commands. No source writes.
local H=game:GetService("HttpService")
local E=game:GetService("EncodingService")
local SER=game:GetService("SerializationService")
local SES=game:GetService("ScriptEditorService")
local SS=game:GetService("ServerStorage")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and game.CreatorId==1039373905,"Wrong place/universe/owner")
assert(not game:GetService("RunService"):IsRunning(),"Edit only")
local NAMES={"Level 4 Cinema Blender","Level 5 Void","Level 6 Indoor Playground"}
local function sha(raw)
 local digest=E:ComputeBufferHash(typeof(raw)=="buffer" and raw or buffer.fromstring(raw),Enum.HashAlgorithm.Sha256)
 local chars={} for i=0,buffer.len(digest)-1 do chars[i+1]=string.format("%02x",buffer.readu8(digest,i)) end
 return table.concat(chars)
end
local function stable(value,noYield)
 if type(value)~="table" then return H:JSONEncode(value) end
 local keys={} for key in pairs(value) do table.insert(keys,key) end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local array=#keys>0 and type(keys[1])=="number"
 if array then table.sort(keys) end
 local out={} for i,key in keys do
  if not noYield and i%500==0 then task.wait() end
  table.insert(out,(array and "" or H:JSONEncode(key)..":")..stable(value[key],noYield))
 end
 return (array and "[" or "{")..table.concat(out,",")..(array and "]" or "}")
end
local function typed(value,index)
 local k=typeof(value)
 if value==nil then return {type="nil"} end
 if k=="string" or k=="boolean" then return {type=k,value=value} end
 if k=="number" then assert(value==value and math.abs(value)<math.huge,"Nonfinite native value") return {type=k,value=value} end
 if k=="EnumItem" then return {type=k,enum=tostring(value.EnumType),name=value.Name,value=value.Value} end
 if k=="Vector3" or k=="Color3" then return {type=k,value=k=="Vector3" and {value.X,value.Y,value.Z} or {value.R,value.G,value.B}} end
 if k=="Vector2" then return {type=k,value={value.X,value.Y}} end
 if k=="CFrame" then return {type=k,value={value:GetComponents()}} end
 if k=="UDim" then return {type=k,value={value.Scale,value.Offset}} end
 if k=="UDim2" then return {type=k,value={value.X.Scale,value.X.Offset,value.Y.Scale,value.Y.Offset}} end
 if k=="Rect" then return {type=k,min={value.Min.X,value.Min.Y},max={value.Max.X,value.Max.Y}} end
 if k=="BrickColor" then return {type=k,value=value.Number} end
 if k=="NumberRange" then return {type=k,value={value.Min,value.Max}} end
 if k=="NumberSequence" or k=="ColorSequence" then
  local points={} for _,p in value.Keypoints do table.insert(points,{time=p.Time,value=typed(p.Value,index),envelope=k=="NumberSequence" and p.Envelope or 0}) end
  return {type=k,keypoints=points}
 end
 if k=="PhysicalProperties" then return {type=k,value={value.Density,value.Friction,value.Elasticity,value.FrictionWeight,value.ElasticityWeight}} end
 if k=="Instance" then return {type=k,capturedIndex=index[value] or 0,externalPath=index[value] and "" or value:GetFullName(),class=value.ClassName} end
 if k=="Content" then
  local out={type=k,sourceType=tostring(value.SourceType),representation=tostring(value)}
  if value.SourceType==Enum.ContentSourceType.Uri then out.uri=value.Uri end
  return out
 end
 -- The exact native serialization binds saved types not represented above.
 return {type=k,representation=tostring(value),nativeSerializationRequired=true}
end
local COMMON={"Name","Archivable"}
local TYPES={
 {"Model",{"PrimaryPart","ModelStreamingMode","WorldPivot"}},
 {"BasePart",{"CFrame","Size","Color","Material","MaterialVariant","Transparency","Reflectance","Anchored","CanCollide","CanQuery","CanTouch","CollisionGroup","Massless","CastShadow","RootPriority","CustomPhysicalProperties","PivotOffset"}},
 {"MeshPart",{"MeshId","TextureID","MeshContent","TextureContent","RenderFidelity","CollisionFidelity","DoubleSided"}},
 {"SpecialMesh",{"MeshId","TextureId","MeshType","Scale","Offset","VertexColor"}},
 {"Decal",{"Texture","TextureContent","Transparency","Color3","Face"}},
 {"Texture",{"StudsPerTileU","StudsPerTileV","OffsetStudsU","OffsetStudsV"}},
 {"SurfaceAppearance",{"AlphaMode","Color","ColorMapContent","NormalMapContent","RoughnessMapContent","MetalnessMapContent","EmissiveMaskContent","EmissiveStrength","EmissiveTint"}},
 {"Light",{"Enabled","Brightness","Color","Shadows","Range","Angle","Face"}},
 {"Sound",{"SoundId","Volume","PlaybackSpeed","Looped","RollOffMode","RollOffMinDistance","RollOffMaxDistance","SoundGroup"}},
 {"Constraint",{"Enabled","Attachment0","Attachment1"}},
 {"JointInstance",{"Part0","Part1","C0","C1","Enabled"}},
 {"LuaSourceContainer",{"LinkedSource"}},
 {"BaseScript",{"Disabled","RunContext"}},
}
local function properties(object,index)
 local names=table.clone(COMMON)
 for _,spec in TYPES do if object:IsA(spec[1]) then for _,name in spec[2] do table.insert(names,name) end end end
 local out={}
 for _,name in names do
  local ok,value=pcall(function() return object[name] end)
  table.insert(out,{name=name,readable=ok,value=ok and typed(value,index) or {type="unreadable"}})
 end
 if object:IsA("Model") then table.insert(out,{name="GetPivot",readable=true,value=typed(object:GetPivot(),index)}) end
 return out
end
local function unique(parent,name)
 local found for _,child in parent:GetChildren() do if child.Name==name then assert(not found,"Duplicate native name: "..name) found=child end end
 return found
end
local function inspect(roots)
 local nodes,index={},{}
 local function visit(object,parentId,rootId,relative)
  if #nodes%500==0 then task.wait() end
  local id=#nodes+1 index[object]=id
  local entry={object=object,parent=object.Parent,parentId=parentId,rootId=rootId,relative=relative,children=object:GetChildren()}
  table.insert(nodes,entry)
  local ordinals={}
  for _,child in entry.children do
   local key=child.Name.."\0"..child.ClassName ordinals[key]=(ordinals[key] or 0)+1
   local path=table.clone(relative) table.insert(path,{name=child.Name,class=child.ClassName,ordinal=ordinals[key]})
   visit(child,id,rootId,path)
  end
 end
 for i,root in roots do visit(root,0,i,{}) end
 local rows,sources={},{}
 for id,entry in nodes do
  if id%500==0 then task.wait() end
  local object=entry.object
  local attrs={} for name,value in object:GetAttributes() do attrs[name]=typed(value,index) end
  local tags=object:GetTags() table.sort(tags)
  local row={id=id,parentId=entry.parentId,rootId=entry.rootId,relative=entry.relative,name=object.Name,class=object.ClassName,
   childCount=#entry.children,attributes=attrs,tags=tags,properties=properties(object,index)}
  if object:IsA("LuaSourceContainer") then
   local source=object.Source assert(SES:GetEditorSource(object)==source,"Source/editor conflict: "..object:GetFullName())
   entry.source=source row.source=source row.sourceSHA256=sha(source) row.sourceEditorMatches=true
   table.insert(sources,{path=object:GetFullName(),relative=entry.relative,class=object.ClassName,sourceSHA256=row.sourceSHA256,sourceBytes=#source})
  end
  table.insert(rows,row)
 end
 return nodes,index,rows,sources
end
local function rootMetadata(root,index)
 local attrs={} for name,value in root:GetAttributes() do attrs[name]=typed(value,index) end
 local tags=root:GetTags() table.sort(tags)
 return {name=root.Name,class=root.ClassName,attributes=attrs,tags=tags,properties=properties(root,index)}
end
local function bindCritical(c)
 c.criticalRoots={} c.sourceNodes={}
 for i,root in c.roots do
  assert(#c.nodes[c.index[root]].children<=1000,"Too many direct root children for bounded write guard")
  c.criticalRoots[i]=stable(rootMetadata(root,c.index),true)
 end
 for i,entry in c.nodes do
  if i%500==0 then task.wait() end
  if entry.source then table.insert(c.sourceNodes,entry) end
 end
end
-- This bounded guard never yields. Full descendant metadata is separately
-- checked across yielding passes before/after relocation; it is not an atomic
-- all-property transaction. Failure rollback changes captured root Parents only.
local function criticalGuard(c)
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and game.CreatorId==1039373905 and not game:GetService("RunService"):IsRunning(),"Place/Edit state changed")
 for i,root in c.roots do
  assert(root.Name==NAMES[i] and root.ClassName=="Model" and root.Parent==c.expectedParents[i],"Native root identity/parent changed")
  assert(unique(c.expectedParents[i],NAMES[i])==root,"Native root name collision")
  local other=c.expectedParents[i]==workspace and SS or workspace
  assert(not unique(other,NAMES[i]),"Destination/source collision")
  assert(stable(rootMetadata(root,c.index),true)==c.criticalRoots[i],"Root properties/attributes/tags changed")
  local baseline=c.nodes[c.index[root]].children local children=root:GetChildren()
  assert(#children==#baseline,"Root children changed")
  for j,child in baseline do assert(children[j]==child,"Root child identity/order changed") end
 end
 for _,entry in c.sourceNodes do assert(entry.object.Source==entry.source and SES:GetEditorSource(entry.object)==entry.source,"Embedded Source/editor changed") end
end
local function guard(c)
 criticalGuard(c)
 for i,entry in c.nodes do
  if i%500==0 then task.wait() end
  local object=entry.object
  assert(object:IsDescendantOf(c.roots[entry.rootId]) or object==c.roots[entry.rootId],"Captured instance left tree")
  if entry.parentId~=0 then assert(object.Parent==entry.parent,"Captured descendant parent changed") end
  local children=object:GetChildren() assert(#children==#entry.children,"Captured children changed")
  for i,child in entry.children do assert(children[i]==child,"Captured child identity/order changed") end
  if entry.source then assert(object.Source==entry.source and SES:GetEditorSource(object)==entry.source,"Captured Source/editor changed") end
 end
 local _,_,rows=inspect(c.roots)
 assert(sha(stable(rows))==c.treeSHA256,"Native properties/attributes/tags/assets changed")
 criticalGuard(c)
end
local function summary(c)
 local roots={}
 for i,root in c.roots do
  table.insert(roots,{beforePath="Workspace."..NAMES[i],path=root:GetFullName(),class=root.ClassName,descendants=#root:GetDescendants(),pivot=typed(root:GetPivot(),c.index),streaming=tostring(root.ModelStreamingMode)})
 end
 local sources={}
 for _,entry in c.nodes do if entry.source then table.insert(sources,{path=entry.object:GetFullName(),class=entry.object.ClassName,bytes=#entry.source,sha256=sha(entry.source),sourceEditorMatches=true}) end end
 return {task="lazy-levels-20261009",captureKey=c.key,captureId=c.captureId,placeId=game.PlaceId,universeId=game.GameId,placeVersion=game.PlaceVersion,
  phase=c.phase,nativeSHA256=c.nativeSHA256,nativeBytes=buffer.len(c.native),treeSHA256=c.treeSHA256,nodeCount=#c.nodes,roots=roots,sources=sources,
  limits="Same-instance native tree/property/source checks across yielding passes plus bounded non-yielding root/embedded-Source guards; descendant metadata is not checked atomically. No gameplay, streaming, performance or publication pass."}
end
