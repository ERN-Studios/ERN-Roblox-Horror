-- S06 read-only snapshot. No object/property/Source/shared writes or requires.
local HS=game:GetService("HttpService")
local ENC=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local SS=game:GetService("ServerStorage")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and not RS:IsRunning(),"wrong place/Edit")
local state=assert(shared.__MongoTVStorageCleanup20261009,"held original references unavailable")
assert(state.rootRefs and state.scriptRefs and not state.probeLease and not state.portLease and state.storagePort==nil,"held original state in use")
assert(shared.__MongoTVExternalStorageArchive20261009==nil and shared.__MongoTVExternalStorageReopen20261009==nil,"archive/reopen in progress")
local expected=HS:JSONDecode(__EXPECTED_HELD__)
local expectedLive=HS:JSONDecode(__EXPECTED_LIVE__)
local function sha(value)
 local h=ENC:ComputeBufferHash(buffer.fromstring(value),Enum.HashAlgorithm.Sha256)
 local result={} for i=0,buffer.len(h)-1 do result[i+1]=string.format("%02x",buffer.readu8(h,i)) end
 return table.concat(result)
end
local function canonical(value)
 local kind=typeof(value)
 if kind=="nil" then return "nil" end
 if kind=="boolean" then return if value then "true" else "false" end
 if kind=="number" then return "n"..string.format("%.17g",value) end
 if kind=="string" then return "s"..#value..":"..value end
 if kind=="table" then
  local keys={} for k in value do keys[#keys+1]=k end
  table.sort(keys,function(a,b)return canonical(a)<canonical(b)end)
  local result={"{"} for _,k in keys do result[#result+1]=canonical(k)..canonical(value[k]) end
  result[#result+1]="}" return table.concat(result)
 end
 if kind=="Vector2" then return canonical({kind,value.X,value.Y}) end
 if kind=="Vector3" then return canonical({kind,value.X,value.Y,value.Z}) end
 if kind=="Color3" then return canonical({kind,value.R,value.G,value.B}) end
 if kind=="CFrame" then return canonical({kind,value:GetComponents()}) end
 if kind=="UDim" then return canonical({kind,value.Scale,value.Offset}) end
 if kind=="UDim2" then return canonical({kind,value.X.Scale,value.X.Offset,value.Y.Scale,value.Y.Offset}) end
 if kind=="Rect" then return canonical({kind,value.Min.X,value.Min.Y,value.Max.X,value.Max.Y}) end
 if kind=="NumberRange" then return canonical({kind,value.Min,value.Max}) end
 if kind=="BrickColor" then return canonical({kind,value.Number}) end
 if kind=="NumberSequence" then
  local list={kind} for _,p in value.Keypoints do list[#list+1]={p.Time,p.Value,p.Envelope} end return canonical(list)
 end
 if kind=="ColorSequence" then
  local list={kind} for _,p in value.Keypoints do list[#list+1]={p.Time,p.Value.R,p.Value.G,p.Value.B} end return canonical(list)
 end
 return canonical({kind,tostring(value)})
end
local function tags(s)local result=s:GetTags() table.sort(result)return result end
local function checkpoint()
 task.wait()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and not RS:IsRunning(),"Edit changed during read-only census")
 assert(shared.__MongoTVStorageCleanup20261009==state and not state.probeLease and not state.portLease and state.storagePort==nil,"original lease changed during read-only census")
 assert(shared.__MongoTVExternalStorageArchive20261009==nil and shared.__MongoTVExternalStorageReopen20261009==nil,"archive/reopen began during read-only census")
end
-- S06_SCENE_DIGEST_BEGIN: identical pure helper is extracted by the offline port.
local MAX_SCENE_NODES=500000
local MAX_BUCKET_UNIQUES=10000
local function sceneDigest(sceneCounts,total,hash,yieldCheckpoint)
 assert(type(total)=="number" and total%1==0 and total>=0 and total<=MAX_SCENE_NODES,"bounded scene census exceeded")
 local buckets={} local uniques,sum,maxBucket=0,0,0
 for row,count in sceneCounts do
  assert(type(row)=="string" and type(count)=="number" and count%1==0 and count>0,"invalid scene multiset row")
  sum+=count assert(sum<=MAX_SCENE_NODES,"bounded scene multiset exceeded")
  local digest=hash(row)
  assert(type(digest)=="string" and #digest==64 and string.match(digest,"^[0-9a-f]+$"),"invalid scene row hash")
  local index=tonumber(string.sub(digest,1,2),16)+1
  local bucket=buckets[index] if not bucket then bucket={} buckets[index]=bucket end
  bucket[#bucket+1]=tostring(#row)..":"..row..":"..tostring(count)..";"
  assert(#bucket<=MAX_BUCKET_UNIQUES,"bounded scene hash bucket exceeded")
  maxBucket=math.max(maxBucket,#bucket) uniques+=1
  if uniques%1000==0 then yieldCheckpoint() end
 end
 assert(sum==total,"scene multiset count changed")
 local seals={}
 for index=1,256 do
  local bucket=buckets[index] or {}
  table.sort(bucket) -- bounded <=10000, never sort the full scene.
  seals[index]=hash(table.concat(bucket))
  yieldCheckpoint()
 end
 return hash("s06-full-scene-multiset-v2:"..tostring(total)..":"..table.concat(seals)),
  {uniqueRows=uniques,maxBucketUniques=maxBucket,buckets=256,nodeLimit=MAX_SCENE_NODES,bucketLimit=MAX_BUCKET_UNIQUES}
end
-- S06_SCENE_DIGEST_END
local function sourceRow(s)
 local raw=s.Source
 assert(SES:GetEditorSource(s)==raw,"Source/editor conflict: "..s:GetFullName())
 local properties={Archivable=s.Archivable,LinkedSource=tostring(s.LinkedSource)}
 if s:IsA("BaseScript") then properties.Enabled=s.Enabled properties.Disabled=s.Disabled properties.RunContext=tostring(s.RunContext) end
 return {path=s:GetFullName(),class=s.ClassName,sourceSHA256=sha(raw),sourceBytes=#raw,
  properties=properties,attributes=s:GetAttributes(),tags=tags(s)}
end
local held={} local missing={}
for _,item in expected do
 local found
 for s,before in state.scriptRefs do if before.path==item.studioPath then
  assert(found==nil,"ambiguous held source identity") found=s
  assert(not s:IsDescendantOf(game) and s.Source==before.source,"held source changed or returned live")
 end end
 assert(found,"exact original source reference missing")
 local root=found
 while root.Parent do root=root.Parent end
 local rootBefore=assert(state.rootRefs[root],"source not in captured native root")
 assert(root.Parent==nil and rootBefore.name==item.segments[2] and root.Name==rootBefore.name,"held root reparented/renamed")
 for _,live in SS:GetChildren() do assert(live.Name~=root.Name,"held root name returned live") end
 local row=sourceRow(found)
 assert(row.path==string.sub(item.studioPath,#"ServerStorage."+1) and found.Name==item.segments[#item.segments],"held Source path/name changed")
 assert(row.class=="ModuleScript" and row.sourceSHA256==item.sha256 and row.sourceBytes==item.bytes,"held Source digest/class changed")
 assert(canonical(row.properties)==canonical(item.properties) and canonical(row.attributes)==canonical(item.attributes),"held Source metadata changed")
 row.studioPath=item.studioPath held[#held+1]=row missing[#missing+1]=item.studioPath
end
assert(#held==12,"wrong held source count")
table.sort(held,function(a,b)return a.studioPath<b.studioPath end) table.sort(missing)
local descendants=game:GetDescendants()
assert(#descendants<=MAX_SCENE_NODES,"bounded scene census exceeded")
local scene,sources,remotes,roots={},{},{},{}
for i,s in descendants do
 local row=canonical({s:GetFullName(),s.ClassName,if s.Parent then s.Parent:GetFullName() else "nil"})
 scene[row]=(scene[row] or 0)+1
 if s:IsA("LuaSourceContainer") then sources[#sources+1]=sourceRow(s) end
 if s:IsA("RemoteEvent") or s:IsA("RemoteFunction") then remotes[#remotes+1]=canonical({s:GetFullName(),s.ClassName,s.Archivable,s:GetAttributes(),tags(s)}) end
 if i%1000==0 then checkpoint() end
end
for _,f in SS:GetChildren() do roots[#roots+1]=canonical({f.Name,f.ClassName,f.Archivable,f:GetAttributes(),tags(f)}) end
local sceneSHA,sceneDigestBounds=sceneDigest(scene,#descendants,sha,checkpoint)
table.sort(roots) table.sort(remotes) table.sort(sources,function(a,b)return a.path<b.path end)
local byPath={} for _,row in sources do assert(byPath[row.path]==nil,"ambiguous live source path") byPath[row.path]=row end
for _,expectedRow in expectedLive do
 local current=assert(byPath[expectedRow.studioPath],"remaining mirror absent live: "..expectedRow.studioPath)
 assert(current.class==expectedRow.className and current.sourceSHA256==expectedRow.sha256 and current.sourceBytes==expectedRow.bytes,"remaining mirror/native Source contract drift: "..expectedRow.studioPath)
 for key,value in expectedRow.properties do assert(current.properties[key]==value,"remaining native property drift: "..expectedRow.studioPath.."."..key) end
 assert(canonical(current.attributes)==canonical(expectedRow.attributes),"remaining native attribute drift: "..expectedRow.studioPath)
end
assert(not RS:IsRunning() and shared.__MongoTVStorageCleanup20261009==state and not state.probeLease and not state.portLease,"mode/original lease changed")
assert(shared.__MongoTVExternalStorageArchive20261009==nil and shared.__MongoTVExternalStorageReopen20261009==nil,"archive/reopen began during guard")
local signature=sha(canonical({sceneSHA,sources,remotes,roots,held}))
return HS:JSONEncode({schema="external-mirror-retirement-native-guard-v1",placeId=game.PlaceId,universeId=game.GameId,
 datamodel="Edit",signatureSHA256=signature,sceneStructureSHA256=sceneSHA,sceneDigestBounds=sceneDigestBounds,
 liveSourceCount=#sources,liveSceneNodes=#descendants,liveRemoteCount=#remotes,
 liveServerStorageRoots=#roots,held=held,knownAbsent=missing,sourceEditorVerified=true,remainingMirrorsVerified=#expectedLive,nativeWrites=0,sourceWrites=0,modeSwitches=0,
 capturedAtUtc=DateTime.now():ToIsoDate(),scope="Two read-only live Source/editor/metadata and scene-structure snapshots; no full geometry/asset or gameplay certification."})
