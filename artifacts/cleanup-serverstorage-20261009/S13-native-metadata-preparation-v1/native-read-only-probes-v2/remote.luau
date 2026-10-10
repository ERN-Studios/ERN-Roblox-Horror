
-- sync-native-metadata-v1
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local CS=game:GetService("CollectionService")
local RS=game:GetService("RunService")
local wanted={"ReplicatedStorage", "Remotes", "RoundStatus"}
local expectedClass="RemoteEvent"
local expectedPlace=131311258779917
local expectedUniverse=10559217407
assert(not RS:IsRunning(),"Native metadata requires Edit")
assert(expectedPlace==nil or game.PlaceId==expectedPlace,"Wrong place")
assert(expectedUniverse==nil or game.GameId==expectedUniverse,"Wrong universe")
local cur=game
for _,name in wanted do
 local found=nil
 for _,child in cur:GetChildren() do
  if child.Name==name then assert(found==nil,"Ambiguous native path");found=child end
 end
 assert(found,"Missing native path");cur=found
end
assert(cur.ClassName==expectedClass,"Native class changed")
local parent=cur.Parent
assert(parent,"Detached native instance")
local function sha(text)
 local b=ENC:ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(b)-1 do out[#out+1]=string.format("%02x",buffer.readu8(b,i)) end
 return table.concat(out)
end
local function properties()
 local p={Archivable=cur.Archivable}
 assert(type(p.Archivable)=="boolean","Archivable unreadable")
 if expectedClass~="RemoteEvent" then
  p.LinkedSource=cur.LinkedSource
  assert(type(p.LinkedSource)=="string","LinkedSource unreadable")
  if expectedClass~="ModuleScript" then
   p.Enabled=cur.Enabled;p.Disabled=cur.Disabled
   assert(type(p.Enabled)=="boolean" and type(p.Disabled)=="boolean" and p.Enabled~=p.Disabled,"Invalid Enabled aliases")
   local context=cur.RunContext
   assert(typeof(context)=="EnumItem","RunContext unreadable")
   p.RunContext=tostring(context)
  end
 end
 return p
end
local function attributes()
 local a=cur:GetAttributes()
 for key,value in a do
  local t=type(value)
  assert(type(key)=="string" and (t=="string" or t=="boolean" or (t=="number" and value==value and math.abs(value)<math.huge)),"Unsupported native attribute")
 end
 return a
end
local function tags()
 local values=CS:GetTags(cur)
 for _,value in values do assert(type(value)=="string","Invalid native tag") end
 table.sort(values)
 return values
end
local function same(a,b)
 for key,value in a do assert(type(b[key])==type(value) and b[key]==value,"Native metadata changed during read") end
 for key in b do assert(a[key]~=nil,"Native metadata changed during read") end
end
local props,attrs,labels=properties(),attributes(),tags()
local result={segments=wanted,path=cur:GetFullName(),className=cur.ClassName,
 instanceId=cur:GetDebugId(16),parentId=parent:GetDebugId(16),
 placeId=game.PlaceId,universeId=game.GameId,properties=props,attributes=attrs,tags=labels}
if expectedClass~="RemoteEvent" then
 local source=cur.Source
 local editor=SES:GetEditorSource(cur)
 assert(type(source)=="string" and type(editor)=="string" and source==editor,"Native Source/editor conflict")
 local canonical=source:gsub("\r\n","\n")
 result.rawSourceSHA256=sha(source);result.rawEditorSHA256=sha(editor)
 result.sourceSHA256=sha(canonical);result.canonicalBytes=#canonical
 result.sourceEditorMatches=true
 assert(cur.Source==source and SES:GetEditorSource(cur)==editor,"Native Source/editor changed during read")
end
same(props,properties());same(attrs,attributes());same(labels,tags())
assert(cur.Parent==parent and cur.ClassName==expectedClass and cur:GetFullName()==result.path,"Native identity changed during read")
assert(not RS:IsRunning() and game.PlaceId==result.placeId and game.GameId==result.universeId,"Native mode/place changed")
return H:JSONEncode(result)
