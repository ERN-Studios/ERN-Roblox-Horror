-- Native Edit command only. Exact instance/class/Source/editor CAS, scoped promotion.
local H,E = game:GetService("HttpService"),game:GetService("EncodingService")
local SES,R = game:GetService("ScriptEditorService"),game:GetService("RunService")
local BASE = "http://127.0.0.1:8914"
assert(not R:IsRunning(),"Edit only")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and game.CreatorId==1039373905,"Wrong place")
local function hash(s) return (E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",c:byte())end))end
local function at(path)
 local x=game
 for part in path:gmatch("[^.]+")do x=assert(x:FindFirstChild(part),"Missing live path: "..path)end
 return x
end
local raw=H:GetAsync(BASE.."/payload",true)
assert(hash(raw)=="103a2de88f8548dd2725d1c86d2301e0996f0b9439c5e2ffce34222bafd42c42","Frozen payload changed")
local data=H:JSONDecode(raw)
assert(data.task=="level3-promotion-20261002" and data.nativeBeforeVerified and data.nativeBeforeCaptureId=="551b88e1-2e3a-4333-8157-00e622b7bc54","Missing checkpoint")
local level3=at("ServerScriptService.Level 3 Systems")
local preview=at("ServerScriptService.LobbyReimaginedPreview")
assert(level3:IsA("Folder") and preview:IsA("Folder") and preview:GetAttribute("LobbyReimaginedOwned")==true,"Wrong owner")
local targets,parents,expected,prepared={},{},{},{}
for _,row in ipairs(data.rows)do
 assert(hash(row.source)==row.candidateSHA256 and #row.source==row.candidateBytes,"Candidate changed: "..row.path)
 assert(loadstring(row.source,"="..row.path),"Compile failed: "..row.path)
 local parentPath=row.path:match("^(.*)%.[^.]+$")
 parents[row.path]=at(parentPath)
 if not row.new then targets[row.path]=at(row.path);expected[row.path]=row.baselineSHA256 end
end
local function verify()
 assert(not R:IsRunning() and at("ServerScriptService.Level 3 Systems")==level3 and at("ServerScriptService.LobbyReimaginedPreview")==preview,"Context changed")
 for _,row in ipairs(data.rows)do
  local parentPath,name=row.path:match("^(.*)%.([^.]*)$")
  assert(at(parentPath)==parents[row.path],"Parent changed: "..row.path)
  if row.new then
   local existing=parents[row.path]:FindFirstChild(name)
   assert(existing==nil or existing==prepared[row.path],"New helper conflict: "..row.path)
  else
   local x=at(row.path)
   assert(x==targets[row.path] and x.ClassName==row.className and hash(x.Source)==expected[row.path] and hash(SES:GetEditorSource(x))==expected[row.path],"Fresh Source/editor baseline changed: "..row.path)
  end
 end
end
verify()
for _,row in ipairs(data.rows)do
 if row.new then
  assert(row.className=="ModuleScript" and (parents[row.path]==level3 or row.path=="ServerScriptService.Level 3 Kit Warmup"),"Unexpected new helper scope")
  local x=Instance.new(row.className);x.Name=row.path:match("([^.]*)$")
  x:SetAttribute("Level3PromotionOwned","20261002")
  SES:UpdateSourceAsync(x,function(current)assert(current=="","Prepared source conflict");return row.source end)
  assert(x.Source==row.source and SES:GetEditorSource(x)==row.source,"Prepared Source/editor conflict")
  prepared[row.path]=x
 end
end
verify()
for _,row in ipairs(data.rows)do if row.new then prepared[row.path].Parent=parents[row.path] end end
for _,row in ipairs(data.rows)do
 if not row.new then
  local x=targets[row.path]
  SES:UpdateSourceAsync(x,function(current)
   verify();assert(hash(current)==expected[row.path],"Callback baseline changed: "..row.path);return row.source
  end)
  assert(x.Source==row.source and SES:GetEditorSource(x)==row.source,"Post-write conflict: "..row.path)
  expected[row.path]=row.candidateSHA256
 end
end
verify()
local receipt={task=data.task,installedAt=DateTime.now():ToIsoDate(),placeId=game.PlaceId,universeId=game.GameId,nativeBeforeCaptureId=data.nativeBeforeCaptureId,sceneChanged=false,sources={}}
for _,row in ipairs(data.rows)do
 local x=at(row.path)
 assert(hash(x.Source)==row.candidateSHA256 and SES:GetEditorSource(x)==row.source,"Final mismatch: "..row.path)
 table.insert(receipt.sources,{path=row.path,className=x.ClassName,sha256=row.candidateSHA256,bytes=#x.Source,editorMatch=true,new=row.new})
end
assert(H:PostAsync(BASE.."/receipt/install",H:JSONEncode(receipt),Enum.HttpContentType.ApplicationJson)=="saved","Receipt failed")
print("LEVEL3_PROMOTION_SCOPED_INSTALL_OK",#receipt.sources)
return receipt
