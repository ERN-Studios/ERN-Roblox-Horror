
local H=game:GetService("HttpService")
local E=game:GetService("EncodingService")
local S=game:GetService("ScriptEditorService")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407)
local function sha(raw)
 local b=E:ComputeBufferHash(buffer.fromstring(raw),Enum.HashAlgorithm.Sha256)
 local t={} for i=0,buffer.len(b)-1 do t[#t+1]=string.format("%02x",buffer.readu8(b,i)) end
 return table.concat(t)
end
local roots=game:GetService("ServerStorage")
local paths={
{"ServerScriptService","Level 1 Systems","EntityAnimation"},
{"StarterPlayer","StarterPlayerScripts","Level 1 Entity Motion"},
{"ServerScriptService","Level 3 Systems","Level 3 Mall Manager AI Controller"},
{"ServerScriptService","Level 6 Systems","Level 6 Mall Manager AI Controller"},
{"ServerScriptService","LunaTribute"},
{"ServerScriptService","GameManager"}}
local rows={}
for _,p in ipairs(paths) do
 local o=game
 for _,n in ipairs(p) do o=assert(o:FindFirstChild(n),n) end
 local a=o.Source local b=S:GetEditorSource(o)
 assert(a==b,"Source/editor conflict")
 local props={Archivable=o.Archivable,LinkedSource=o.LinkedSource}
 if o:IsA("BaseScript") then props.Enabled=o.Enabled props.Disabled=o.Disabled props.RunContext=tostring(o.RunContext) end
 table.insert(rows,{path=table.concat(p,"."),id=o:GetDebugId(),parentId=o.Parent:GetDebugId(),class=o.ClassName,bytes=#a,
 sha256=sha(a),editorMatches=true,properties=props,attributes=o:GetAttributes(),
 tags=o:GetTags(),source=p[#p]=="EntityAnimation" and a or nil})
end
local caches={}
for _,n in ipairs({"MongoTVEntityAnimations","RBX_ANIMSAVES"}) do
 local o=assert(roots:FindFirstChild(n),n)
 table.insert(caches,{name=n,id=o:GetDebugId(),class=o.ClassName,parentId=o.Parent:GetDebugId(),children=#o:GetChildren(),
 nodes=1+#o:GetDescendants(),archivable=o.Archivable,attributes=o:GetAttributes(),tags=o:GetTags()})
end
return H:JSONEncode({readAtUtc=os.date("!%Y-%m-%dT%H:%M:%SZ"),placeId=game.PlaceId,universeId=game.GameId,
mode="Edit",sourceRows=rows,cacheRoots=caches,sourceWrites=0,objectWrites=0})

