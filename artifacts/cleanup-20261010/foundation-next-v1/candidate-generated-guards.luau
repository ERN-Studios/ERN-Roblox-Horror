
local checks=0
local function check(value,why)checks+=1;assert(value,why)end
local knownHashes={[""]="\227\176\196\066\152\252\028\020\154\251\244\200\153\111\185\036\039\174\065\228\100\155\147\076\164\149\153\027\120\082\184\085",["-- café\nreturn 'old'\n"]="\172\035\197\199\215\035\179\103\088\078\103\007\059\052\224\081\189\114\178\163\083\076\064\039\225\247\207\113\213\251\147\169",["return 'foreign'\n"]="\122\236\220\061\165\034\074\115\071\202\046\226\210\161\151\046\240\217\240\161\125\037\113\164\090\216\176\027\138\166\160\246",["-- café\r\nreturn 'old'\r\n"]="\033\002\214\034\039\169\178\039\020\082\077\067\041\057\198\121\056\127\240\068\150\246\132\194\056\019\120\017\239\175\081\154",["-- æøå 😀\nreturn 'new'\n"]="\092\207\078\008\148\114\182\016\077\049\223\007\214\183\093\174\117\138\137\059\063\094\062\047\043\219\040\100\043\138\171\075"}
local trueType=typeof
local typeof=function(v) if type(v)=="table" and v.__enum then return "EnumItem" end return trueType(v) end
local Enum={HashAlgorithm={Sha256={__enum=true}}}
local context=setmetatable({__enum=true},{__tostring=function()return "Enum.RunContext.Legacy" end})
local function fresh(className,scenario,missing)
 local rows,services={},{}
 local writes,destroys,callbacks=0,0,0
 local methods={}
 local function node(row)
  local object={};rows[object]=row
  return setmetatable(object,{
   __index=function(_,key) if methods[key] then return methods[key] end return row[key] end,
   __newindex=function(_,key,value)
    if key=="Source" then writes+=1 end
    if key=="Parent" then
     local old=row.Parent
     if old then for i,child in rows[old].children do if child==object then table.remove(rows[old].children,i);break end end end
     if value then table.insert(rows[value].children,object) end
    end
    row[key]=value
    if key=="Enabled" then row.Disabled=not value end
   end,
  })
 end
 function methods.GetChildren(self)return table.clone(rows[self].children or {})end
 function methods.GetDebugId(self,depth)assert(depth==16);return rows[self].id end
 function methods.GetFullName(self)
  local names={} while rows[self].Parent do table.insert(names,1,rows[self].Name);self=rows[self].Parent end
  return table.concat(names,".")
 end
 function methods.GetAttributes(self)return table.clone(rows[self].attributes or {})end
 function methods.Destroy(self)destroys+=1;self.Parent=nil end
 local game=node({Name="game",ClassName="DataModel",id="game",children={},PlaceId=131311258779917,GameId=10559217407})
 local parent=node({Name="ServerScriptService",ClassName="ServerScriptService",id="parent",Parent=game,children={}})
 rows[game].children={parent}
 local target=node({Name="Fixture",ClassName=className,id="target",Parent=parent,children={},Source="-- café\r\nreturn 'old'\r\n",editor="-- café\r\nreturn 'old'\r\n",
  Archivable=true,LinkedSource="",Enabled=true,Disabled=false,RunContext=context,
  attributes={Marker="preserve",Generation=17,Active=false},tags={"z","a"}})
 rows[parent].children=missing and {} or {target}
 local running=false
 local created=nil
 Instance={new=function(klass)
  created=node({Name=klass,ClassName=klass,id="owned",children={},Source="",editor="",Archivable=true,
   LinkedSource="",Enabled=true,Disabled=false,RunContext=context,attributes={},tags={}})
  return created
 end}
 services.HttpService={JSONEncode=function(_,value)return value end,JSONDecode=function(_,value)return value end}
 services.RunService={IsRunning=function()return running end}
 services.EncodingService={ComputeBufferHash=function(_,value,algorithm)
  assert(algorithm==Enum.HashAlgorithm.Sha256)
  return buffer.fromstring(assert(knownHashes[buffer.tostring(value)],"Unexpected SHA boundary input"))
 end}
 services.CollectionService={GetTags=function(_,object)return table.clone(rows[object].tags or {})end}
 services.ScriptEditorService={GetEditorSource=function(_,object)return rows[object].editor end,
  UpdateSourceAsync=function(_,object,callback)
   callbacks+=1
   local row=rows[object]
   if scenario=="update-error" then error("fixture SES error before callback") end
   if scenario=="callback-source" then row.Source="return 'foreign'\n";row.editor="return 'foreign'\n" end
   if scenario=="editor-conflict" then row.editor="return 'foreign'\n" end
   if scenario=="identity" then row.id="foreign-target" end
   if scenario=="parent" then rows[parent].id="foreign-parent" end
   if scenario=="class" then row.ClassName="Folder" end
   if scenario=="property" then row.Archivable=false end
   if scenario=="attribute" then row.attributes.Generation=18 end
   if scenario=="tag" then row.tags={"foreign"} end
   if scenario=="mode" then running=true end
   if scenario=="place" then rows[game].PlaceId+=1 end
   local old=scenario=="callback-old" and "return 'foreign'\n" or row.editor
   local result=callback(old)
   object.Source=result;row.editor=result
   if scenario=="commit-then-error" then error("fixture committed then SES error") end
  end}
 function methods.GetService(self,name)assert(self==game);return assert(services[name])end
 if scenario=="initial-editor" then rows[target].editor="return 'foreign'\n" end
 if scenario=="initial-class" then rows[target].ClassName="Folder" end
 if scenario=="initial-source" then rows[target].Source="return 'foreign'\n";rows[target].editor="return 'foreign'\n" end
 if scenario=="initial-identity" then rows[target].id="foreign-target" end
 if scenario=="initial-property" then rows[target].Archivable=false end
 if scenario=="initial-attribute" then rows[target].attributes.Generation=18 end
 if scenario=="initial-tag" then rows[target].tags={"foreign"} end
 if scenario=="create-race" then rows[parent].children={target} end
 return game,function()
  return {writes=writes,destroys=destroys,callbacks=callbacks,source=rows[target].Source,editor=rows[target].editor,
    created=created,createdSource=created and rows[created].Source,createdParent=created and rows[created].Parent,
    originalParent=rows[target].Parent,originalChildren=#rows[parent].children,createdEnabled=created and rows[created].Enabled}
 end
end
local updateRunners={["ModuleScript"]=function(game)

local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local names={"ServerScriptService","Fixture"}
assert(not RS:IsRunning(),"Installer requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
local function child(parent,name)
 local found=nil
 for _,value in parent:GetChildren() do
  if value.Name==name then assert(found==nil,"Ambiguous installer path");found=value end
 end
 return found
end
local parent=game
for index=1,#names-1 do parent=assert(child(parent,names[index]),"Missing installer parent") end
local current=child(parent,names[#names])

assert(current,"Missing installer target")
local expected={["segments"]={"ServerScriptService","Fixture"},["path"]="ServerScriptService.Fixture",["className"]="ModuleScript",["instanceId"]="target",["parentId"]="parent",["placeId"]=131311258779917,["universeId"]=10559217407,["properties"]={["Archivable"]=true,["LinkedSource"]=""},["attributes"]={["Marker"]="preserve",["Generation"]=17,["Active"]=false},["tags"]={"a","z"},["sourceEditorMatches"]=true,["rawSourceSHA256"]="2102d62227a9b22714524d432939c679387ff04496f684c238137811efaf519a",["rawEditorSHA256"]="2102d62227a9b22714524d432939c679387ff04496f684c238137811efaf519a",["sourceSHA256"]="ac23c5c7d723b367584e67073b34e051bd72b2a3534c4027e1f7cf71d5fb93a9",["canonicalBytes"]=22}
local function same(a,b)
 assert(type(a)==type(b),"Installer baseline changed")
 if type(a)~="table" then assert(a==b,"Installer baseline changed");return end
 for key,value in a do same(value,b[key]) end
 for key in b do assert(a[key]~=nil,"Installer baseline changed") end
end
local function capture()
 local result=(function()

-- sync-native-metadata-v1
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local CS=game:GetService("CollectionService")
local RS=game:GetService("RunService")
local wanted={"ServerScriptService", "Fixture"}
local expectedClass="ModuleScript"
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

 end)()
 return H:JSONDecode(result)
end
local function sha(text)
 local bytes=game:GetService("EncodingService"):ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local values={} for index=0,buffer.len(bytes)-1 do values[#values+1]=string.format("%02x",buffer.readu8(bytes,index)) end
 return table.concat(values)
end
same(expected,capture())
SES:UpdateSourceAsync(current,function(old)
 -- Repeat Source/editor/identity/class/properties/attrs/tags/mode/place checks
 -- inside the callback, after every potentially yielding Python/native read.
 assert(child(parent,names[#names])==current,"Installer target replaced")
 same(expected,capture())
 assert(type(old)=="string" and sha(old)==expected.rawEditorSHA256,"Installer callback Source changed")
 return "-- æøå 😀\nreturn 'new'\n"
end)
return "ok"

end,["Script"]=function(game)

local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local names={"ServerScriptService","Fixture"}
assert(not RS:IsRunning(),"Installer requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
local function child(parent,name)
 local found=nil
 for _,value in parent:GetChildren() do
  if value.Name==name then assert(found==nil,"Ambiguous installer path");found=value end
 end
 return found
end
local parent=game
for index=1,#names-1 do parent=assert(child(parent,names[index]),"Missing installer parent") end
local current=child(parent,names[#names])

assert(current,"Missing installer target")
local expected={["segments"]={"ServerScriptService","Fixture"},["path"]="ServerScriptService.Fixture",["className"]="Script",["instanceId"]="target",["parentId"]="parent",["placeId"]=131311258779917,["universeId"]=10559217407,["properties"]={["Archivable"]=true,["LinkedSource"]="",["Enabled"]=true,["Disabled"]=false,["RunContext"]="Enum.RunContext.Legacy"},["attributes"]={["Marker"]="preserve",["Generation"]=17,["Active"]=false},["tags"]={"a","z"},["sourceEditorMatches"]=true,["rawSourceSHA256"]="2102d62227a9b22714524d432939c679387ff04496f684c238137811efaf519a",["rawEditorSHA256"]="2102d62227a9b22714524d432939c679387ff04496f684c238137811efaf519a",["sourceSHA256"]="ac23c5c7d723b367584e67073b34e051bd72b2a3534c4027e1f7cf71d5fb93a9",["canonicalBytes"]=22}
local function same(a,b)
 assert(type(a)==type(b),"Installer baseline changed")
 if type(a)~="table" then assert(a==b,"Installer baseline changed");return end
 for key,value in a do same(value,b[key]) end
 for key in b do assert(a[key]~=nil,"Installer baseline changed") end
end
local function capture()
 local result=(function()

-- sync-native-metadata-v1
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local CS=game:GetService("CollectionService")
local RS=game:GetService("RunService")
local wanted={"ServerScriptService", "Fixture"}
local expectedClass="Script"
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

 end)()
 return H:JSONDecode(result)
end
local function sha(text)
 local bytes=game:GetService("EncodingService"):ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local values={} for index=0,buffer.len(bytes)-1 do values[#values+1]=string.format("%02x",buffer.readu8(bytes,index)) end
 return table.concat(values)
end
same(expected,capture())
SES:UpdateSourceAsync(current,function(old)
 -- Repeat Source/editor/identity/class/properties/attrs/tags/mode/place checks
 -- inside the callback, after every potentially yielding Python/native read.
 assert(child(parent,names[#names])==current,"Installer target replaced")
 same(expected,capture())
 assert(type(old)=="string" and sha(old)==expected.rawEditorSHA256,"Installer callback Source changed")
 return "-- æøå 😀\nreturn 'new'\n"
end)
return "ok"

end,["LocalScript"]=function(game)

local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local names={"ServerScriptService","Fixture"}
assert(not RS:IsRunning(),"Installer requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
local function child(parent,name)
 local found=nil
 for _,value in parent:GetChildren() do
  if value.Name==name then assert(found==nil,"Ambiguous installer path");found=value end
 end
 return found
end
local parent=game
for index=1,#names-1 do parent=assert(child(parent,names[index]),"Missing installer parent") end
local current=child(parent,names[#names])

assert(current,"Missing installer target")
local expected={["segments"]={"ServerScriptService","Fixture"},["path"]="ServerScriptService.Fixture",["className"]="LocalScript",["instanceId"]="target",["parentId"]="parent",["placeId"]=131311258779917,["universeId"]=10559217407,["properties"]={["Archivable"]=true,["LinkedSource"]="",["Enabled"]=true,["Disabled"]=false,["RunContext"]="Enum.RunContext.Legacy"},["attributes"]={["Marker"]="preserve",["Generation"]=17,["Active"]=false},["tags"]={"a","z"},["sourceEditorMatches"]=true,["rawSourceSHA256"]="2102d62227a9b22714524d432939c679387ff04496f684c238137811efaf519a",["rawEditorSHA256"]="2102d62227a9b22714524d432939c679387ff04496f684c238137811efaf519a",["sourceSHA256"]="ac23c5c7d723b367584e67073b34e051bd72b2a3534c4027e1f7cf71d5fb93a9",["canonicalBytes"]=22}
local function same(a,b)
 assert(type(a)==type(b),"Installer baseline changed")
 if type(a)~="table" then assert(a==b,"Installer baseline changed");return end
 for key,value in a do same(value,b[key]) end
 for key in b do assert(a[key]~=nil,"Installer baseline changed") end
end
local function capture()
 local result=(function()

-- sync-native-metadata-v1
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local CS=game:GetService("CollectionService")
local RS=game:GetService("RunService")
local wanted={"ServerScriptService", "Fixture"}
local expectedClass="LocalScript"
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

 end)()
 return H:JSONDecode(result)
end
local function sha(text)
 local bytes=game:GetService("EncodingService"):ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local values={} for index=0,buffer.len(bytes)-1 do values[#values+1]=string.format("%02x",buffer.readu8(bytes,index)) end
 return table.concat(values)
end
same(expected,capture())
SES:UpdateSourceAsync(current,function(old)
 -- Repeat Source/editor/identity/class/properties/attrs/tags/mode/place checks
 -- inside the callback, after every potentially yielding Python/native read.
 assert(child(parent,names[#names])==current,"Installer target replaced")
 same(expected,capture())
 assert(type(old)=="string" and sha(old)==expected.rawEditorSHA256,"Installer callback Source changed")
 return "-- æøå 😀\nreturn 'new'\n"
end)
return "ok"

end}
local createRunners={["ModuleScript"]=function(game)

local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local names={"ServerScriptService","Fixture"}
assert(not RS:IsRunning(),"Installer requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
local function child(parent,name)
 local found=nil
 for _,value in parent:GetChildren() do
  if value.Name==name then assert(found==nil,"Ambiguous installer path");found=value end
 end
 return found
end
local parent=game
for index=1,#names-1 do parent=assert(child(parent,names[index]),"Missing installer parent") end
local current=child(parent,names[#names])

assert(current==nil,"Installer target appeared")
assert(parent:GetDebugId(16)=="parent","Installer parent changed")
local owned=Instance.new("ModuleScript")
owned.Name=names[#names]
local ownedId=owned:GetDebugId(16)
local initialEnabled=nil
if "ModuleScript"~="ModuleScript" then initialEnabled=owned.Enabled;owned.Enabled=false end
local initialProps={Archivable=owned.Archivable,LinkedSource=owned.LinkedSource}
if initialEnabled~=nil then initialProps.Enabled=owned.Enabled;initialProps.Disabled=owned.Disabled;initialProps.RunContext=owned.RunContext end
local function sameProps()
 for key,value in initialProps do if owned[key]~=value then return false end end
 return true
end
local function ownedState(allowedSource)
 return owned.Parent==parent and child(parent,names[#names])==owned
  and parent:GetDebugId(16)=="parent" and owned.ClassName=="ModuleScript" and owned:GetDebugId(16)==ownedId
  and sameProps()
  and owned.Source==allowedSource and SES:GetEditorSource(owned)==allowedSource
  and next(owned:GetAttributes())==nil and #game:GetService("CollectionService"):GetTags(owned)==0
end
local ok,err=pcall(function()
 assert(owned.Source=="" and SES:GetEditorSource(owned)=="","New script not empty")
 assert(child(parent,names[#names])==nil,"Installer target appeared")
 owned.Parent=parent
 SES:UpdateSourceAsync(owned,function(old)
  assert(not RS:IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407,"Native mode/place changed")
  assert(old=="" and ownedState(""),"Owned new script changed")
  return "-- æøå 😀\nreturn 'new'\n"
 end)
 assert(ownedState("-- æøå 😀\nreturn 'new'\n"),"Owned script landing changed")
 if initialEnabled~=nil then owned.Enabled=initialEnabled end
end)
if not ok then
 -- Destroy only the exact instance created by this call and only while its
 -- Source/editor/attrs/tags still belong to this attempt. Foreign edits stay.
 if owned.Parent==nil or ownedState("") or ownedState("-- æøå 😀\nreturn 'new'\n") then owned:Destroy() end
 error(err)
end
return "ok"

end,["Script"]=function(game)

local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local names={"ServerScriptService","Fixture"}
assert(not RS:IsRunning(),"Installer requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
local function child(parent,name)
 local found=nil
 for _,value in parent:GetChildren() do
  if value.Name==name then assert(found==nil,"Ambiguous installer path");found=value end
 end
 return found
end
local parent=game
for index=1,#names-1 do parent=assert(child(parent,names[index]),"Missing installer parent") end
local current=child(parent,names[#names])

assert(current==nil,"Installer target appeared")
assert(parent:GetDebugId(16)=="parent","Installer parent changed")
local owned=Instance.new("Script")
owned.Name=names[#names]
local ownedId=owned:GetDebugId(16)
local initialEnabled=nil
if "Script"~="ModuleScript" then initialEnabled=owned.Enabled;owned.Enabled=false end
local initialProps={Archivable=owned.Archivable,LinkedSource=owned.LinkedSource}
if initialEnabled~=nil then initialProps.Enabled=owned.Enabled;initialProps.Disabled=owned.Disabled;initialProps.RunContext=owned.RunContext end
local function sameProps()
 for key,value in initialProps do if owned[key]~=value then return false end end
 return true
end
local function ownedState(allowedSource)
 return owned.Parent==parent and child(parent,names[#names])==owned
  and parent:GetDebugId(16)=="parent" and owned.ClassName=="Script" and owned:GetDebugId(16)==ownedId
  and sameProps()
  and owned.Source==allowedSource and SES:GetEditorSource(owned)==allowedSource
  and next(owned:GetAttributes())==nil and #game:GetService("CollectionService"):GetTags(owned)==0
end
local ok,err=pcall(function()
 assert(owned.Source=="" and SES:GetEditorSource(owned)=="","New script not empty")
 assert(child(parent,names[#names])==nil,"Installer target appeared")
 owned.Parent=parent
 SES:UpdateSourceAsync(owned,function(old)
  assert(not RS:IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407,"Native mode/place changed")
  assert(old=="" and ownedState(""),"Owned new script changed")
  return "-- æøå 😀\nreturn 'new'\n"
 end)
 assert(ownedState("-- æøå 😀\nreturn 'new'\n"),"Owned script landing changed")
 if initialEnabled~=nil then owned.Enabled=initialEnabled end
end)
if not ok then
 -- Destroy only the exact instance created by this call and only while its
 -- Source/editor/attrs/tags still belong to this attempt. Foreign edits stay.
 if owned.Parent==nil or ownedState("") or ownedState("-- æøå 😀\nreturn 'new'\n") then owned:Destroy() end
 error(err)
end
return "ok"

end,["LocalScript"]=function(game)

local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local names={"ServerScriptService","Fixture"}
assert(not RS:IsRunning(),"Installer requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
local function child(parent,name)
 local found=nil
 for _,value in parent:GetChildren() do
  if value.Name==name then assert(found==nil,"Ambiguous installer path");found=value end
 end
 return found
end
local parent=game
for index=1,#names-1 do parent=assert(child(parent,names[index]),"Missing installer parent") end
local current=child(parent,names[#names])

assert(current==nil,"Installer target appeared")
assert(parent:GetDebugId(16)=="parent","Installer parent changed")
local owned=Instance.new("LocalScript")
owned.Name=names[#names]
local ownedId=owned:GetDebugId(16)
local initialEnabled=nil
if "LocalScript"~="ModuleScript" then initialEnabled=owned.Enabled;owned.Enabled=false end
local initialProps={Archivable=owned.Archivable,LinkedSource=owned.LinkedSource}
if initialEnabled~=nil then initialProps.Enabled=owned.Enabled;initialProps.Disabled=owned.Disabled;initialProps.RunContext=owned.RunContext end
local function sameProps()
 for key,value in initialProps do if owned[key]~=value then return false end end
 return true
end
local function ownedState(allowedSource)
 return owned.Parent==parent and child(parent,names[#names])==owned
  and parent:GetDebugId(16)=="parent" and owned.ClassName=="LocalScript" and owned:GetDebugId(16)==ownedId
  and sameProps()
  and owned.Source==allowedSource and SES:GetEditorSource(owned)==allowedSource
  and next(owned:GetAttributes())==nil and #game:GetService("CollectionService"):GetTags(owned)==0
end
local ok,err=pcall(function()
 assert(owned.Source=="" and SES:GetEditorSource(owned)=="","New script not empty")
 assert(child(parent,names[#names])==nil,"Installer target appeared")
 owned.Parent=parent
 SES:UpdateSourceAsync(owned,function(old)
  assert(not RS:IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407,"Native mode/place changed")
  assert(old=="" and ownedState(""),"Owned new script changed")
  return "-- æøå 😀\nreturn 'new'\n"
 end)
 assert(ownedState("-- æøå 😀\nreturn 'new'\n"),"Owned script landing changed")
 if initialEnabled~=nil then owned.Enabled=initialEnabled end
end)
if not ok then
 -- Destroy only the exact instance created by this call and only while its
 -- Source/editor/attrs/tags still belong to this attempt. Foreign edits stay.
 if owned.Parent==nil or ownedState("") or ownedState("-- æøå 😀\nreturn 'new'\n") then owned:Destroy() end
 error(err)
end
return "ok"

end}
local cases=0
for _,klass in {"ModuleScript","Script","LocalScript"} do
 local game,state=fresh(klass,"good",false)
 check(updateRunners[klass](game)=="ok","good CAS")
 local result=state();check(result.writes==1 and result.callbacks==1 and result.source=="-- æøå 😀\nreturn 'new'\n","one scoped source write")
 cases+=1
 for _,scenario in {"callback-source","callback-old","editor-conflict","identity","parent","class","property","attribute","tag","mode","place","update-error",
  "initial-editor","initial-class","initial-source","initial-identity","initial-property","initial-attribute","initial-tag"} do
  local g,state=fresh(klass,scenario,false)
  local ok,err=pcall(updateRunners[klass],g)
  check(not ok,"negative CAS rejects: "..scenario)
  local result=state();check(result.writes==0,"no Source write on failed guard: "..scenario)
  check(result.destroys==0 and result.created==nil,"no original destruction or probe on failed CAS")
  if scenario=="callback-source" or scenario=="initial-source" then check(result.source=="return 'foreign'\n","foreign Source preserved")end
  cases+=1
 end
 for _,scenario in {"good","create-race","update-error","commit-then-error","editor-conflict","property","attribute","tag","identity","class","mode","place"} do
  local g,state=fresh(klass,scenario,true)
  local ok,err=pcall(createRunners[klass],g)
  local result=state()
  if scenario=="good" then
   check(ok and result.writes==1 and result.createdSource=="-- æøå 😀\nreturn 'new'\n" and result.createdParent~=nil,"owned create and landing")
   check(klass=="ModuleScript" or result.createdEnabled==true,"restore own default Enabled only after landing")
  else
   check(not ok,"create negative rejects: "..scenario)
   check(result.source=="-- café\r\nreturn 'old'\r\n" and result.originalParent~=nil,"never edit/destroy raced original")
   if scenario=="update-error" or scenario=="commit-then-error" or scenario=="mode" or scenario=="place" then
    check(result.createdParent==nil,"clean exact owned instance after controlled failure")
   end
   if scenario~="commit-then-error" then check(result.writes==0,"failed creation guard does not write Source")end
  end
  cases+=1
 end
end
print("NATIVE CASES="..cases.." CHECKS="..checks)
