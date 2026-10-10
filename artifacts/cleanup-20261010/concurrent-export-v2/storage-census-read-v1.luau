local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local RS=game:GetService("RunService")
local function mode()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
 assert(not RS:IsRunning(),"Authoritative Edit read only; no mode switch")
end
local function sha(text)
 local b=ENC:ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(b)-1 do out[#out+1]=string.format("%02x",buffer.readu8(b,i)) end
 return table.concat(out)
end
local function stable(v)
 if type(v)~="table" then return H:JSONEncode(v) end
 local keys={} for key in v do keys[#keys+1]=key end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={} for _,key in keys do out[#out+1]=H:JSONEncode(key)..":"..stable(v[key]) end
 return "{"..table.concat(out,",").."}"
end
local function segments(n)
 local out={} while n~=game do table.insert(out,1,n.Name);n=n.Parent;assert(n,"Detached during census") end
 return out
end
local function catalog()
 mode()
 local rows,conflicts={},{}
 local census=game:GetDescendants()
 for i,n in census do
  if n:IsA("LuaSourceContainer") or n.ClassName=="RemoteEvent" then
   local row={segments=segments(n),path=n:GetFullName(),className=n.ClassName,
    instanceId=n:GetDebugId(16),parentId=n.Parent:GetDebugId(16),properties={},propertyReadErrors={}}
   for _,name in {"Enabled","Disabled","RunContext","Archivable","LinkedSource"} do
    if n:IsA("LuaSourceContainer") or name=="Archivable" then
     local ok,value=pcall(function()return n[name]end)
     if ok then row.properties[name]=if typeof(value)=="EnumItem" then tostring(value) else value
     elseif name=="Archivable" or name=="LinkedSource" or n.ClassName~="ModuleScript" then row.propertyReadErrors[#row.propertyReadErrors+1]=name end
    end
   end
   if n:IsA("LuaSourceContainer") then
    local ok,source=pcall(function()return n.Source end)
    local editorOk,editor=pcall(function()return SES:GetEditorSource(n)end)
    row.sourceReadable=ok row.editorReadable=editorOk
    if ok then
     local canonical=source:gsub("\r\n","\n")
     row.rawSourceSHA256=sha(source) row.sourceSHA256=sha(canonical) row.rawBytes=#source row.canonicalBytes=#canonical
     if canonical:sub(-1)=="\n" then row.minusOneTrailingLFSHA256=sha(canonical:sub(1,-2)) end
    end
    if editorOk then row.rawEditorSHA256=sha(editor) row.editorSHA256=sha(editor:gsub("\r\n","\n")) end
    row.sourceEditorMatches=ok and editorOk and source==editor
    row.readStable=ok and editorOk and n.Source==source and SES:GetEditorSource(n)==editor
    if not row.sourceEditorMatches or not row.readStable then conflicts[#conflicts+1]=row.path end
   end
   rows[#rows+1]=row
  end
  if i%10000==0 then task.wait();mode() end
 end
 table.sort(rows,function(a,b)return stable(a.segments)..a.className<stable(b.segments)..b.className end)
 mode()
 return rows,{catalogSHA256=sha(stable(rows)),rowCount=#rows,sceneCount=#census,
  serverStorageRootCount=#game:GetService("ServerStorage"):GetChildren(),sourceEditorConflictCount=#conflicts,
  conflicts=conflicts,readAtUtc=DateTime.now():ToIsoDate(),datamodel="Edit",placeId=game.PlaceId,universeId=game.GameId}
end

local _, before=catalog()
local S=game:GetService("ServerStorage")
local roots={}
for _,n in S:GetChildren() do
 local descendants=n:GetDescendants()
 local scripts=0
 for i,d in descendants do
  if d:IsA("LuaSourceContainer") then scripts+=1 end
  if i%10000==0 then task.wait();mode() end
 end
 roots[#roots+1]={name=n.Name,className=n.ClassName,instanceId=n:GetDebugId(16),
 parentId=n.Parent:GetDebugId(16),nodeCount=#descendants+1,descendantScriptCount=scripts,
 attributes=n:GetAttributes(),tags=n:GetTags(),archivable=n.Archivable}
end
table.sort(roots,function(a,b)return a.name<b.name end)
local _,after=catalog()
assert(before.catalogSHA256==after.catalogSHA256 and #roots==before.serverStorageRootCount)
return H:JSONEncode({pass=true,nativeWrites=0,modeSwitches=0,before=before,after=after,roots=roots,
limits="Readonly root facts; not full asset/ref properties or deletion approval"})
