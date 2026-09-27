local H=game:GetService("HttpService")
local E=game:GetService("ScriptEditorService")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
assert(not game:GetService("RunService"):IsRunning(),"Read-only Edit audit requires stopped play")
local function hashes(s)
 local d,f=5381,2166136261
 for i=1,#s do
  local byte=string.byte(s,i)
  d=(d*33+byte)%4294967296
  f=bit32.bxor(f,byte)
  f=(f*403+bit32.lshift(f,24))%4294967296
 end
 return d,f
end
local report={placeId=game.PlaceId,universeId=game.GameId,version=game.PlaceVersion,observedAtUtc=DateTime.now():ToIsoDate(),scripts={},errors={},services={}}
for _,serviceName in ipairs({"Workspace","ReplicatedStorage","ServerScriptService","ServerStorage","StarterGui","StarterPack","StarterPlayer","ReplicatedFirst"}) do
 local service=game:GetService(serviceName)
 table.insert(report.services,serviceName)
 for _,obj in ipairs(service:GetDescendants()) do
  if obj:IsA("LuaSourceContainer") then
   local names={}
   local p=obj
   while p and p~=game do table.insert(names,1,p.Name);p=p.Parent end
   local row={path=obj:GetFullName(),class=obj.ClassName,names=names,properties={}}
   local sourceOK,source=pcall(function() return obj.Source end)
   local editorOK,editor=pcall(function() return E:GetEditorSource(obj) end)
   row.sourceOK=sourceOK;row.editorOK=editorOK
   if sourceOK then row.sourceLength=#source;row.sourceDjb2,row.sourceFnv1a=hashes(source) end
   if editorOK then
    row.editorLength=#editor
    if sourceOK and source==editor then row.editorDjb2,row.editorFnv1a=row.sourceDjb2,row.sourceFnv1a
    else row.editorDjb2,row.editorFnv1a=hashes(editor) end
   end
   row.equal=sourceOK and editorOK and source==editor
   for _,key in ipairs({"Archivable","LinkedSource","Disabled","Enabled","RunContext"}) do
    local ok,value=pcall(function() return obj[key] end)
    if ok then row.properties[key]=typeof(value)=="EnumItem" and tostring(value) or value end
   end
   if not sourceOK then table.insert(report.errors,{path=row.path,kind="Source",error=tostring(source)}) end
   if not editorOK then table.insert(report.errors,{path=row.path,kind="EditorSource",error=tostring(editor)}) end
   table.insert(report.scripts,row)
  end
 end
end
table.sort(report.scripts,function(a,b)return a.path<b.path end)
report.count=#report.scripts
return H:JSONEncode(report)
