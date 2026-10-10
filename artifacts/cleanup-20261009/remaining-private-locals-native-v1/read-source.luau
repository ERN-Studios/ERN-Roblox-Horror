local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
assert(not game:GetService("RunService"):IsRunning(),"Preserve owner's Play")
local paths={
{"ServerScriptService","Level 3 Systems","Level 3 Worn Party Room Dressing"},
{"ServerScriptService","Level 4 Systems","Level 4 Usher Controller"},
{"ServerScriptService","Level 3 Systems","Level 3 Worn Party Visual Adapter"},
{"ServerScriptService","Level4RoundGenerator"},
{"ServerScriptService","Level 4 Systems","Level 4 Configuration"},
{"ServerScriptService","NoiseRegistry"},
{"ServerScriptService","PlayerProtection"},
{"ReplicatedStorage","DeathAdvice"}}
local function hash(s)
 local b=ENC:ComputeBufferHash(buffer.fromstring(s),Enum.HashAlgorithm.Sha256)
 local o={} for i=0,buffer.len(b)-1 do o[#o+1]=string.format("%02x",buffer.readu8(b,i)) end return table.concat(o)
end
local rows={}
for _,parts in paths do
 local n=game
 for _,name in parts do local found={} for _,c in n:GetChildren() do if c.Name==name then found[#found+1]=c end end;assert(#found==1,"Missing/ambiguous path");n=found[1] end
 local source=n.Source local editor=SES:GetEditorSource(n)
 assert(source==editor and n.Source==source and SES:GetEditorSource(n)==editor,"Source/editor conflict or drift")
 local props={} for _,key in {"Enabled","Disabled","RunContext","Archivable","LinkedSource"} do local ok,v=pcall(function()return n[key]end);if ok then props[key]=if typeof(v)=="EnumItem" then tostring(v) else v end end
 local tags=n:GetTags() table.sort(tags)
 rows[#rows+1]={segments=parts,studioPath=n:GetFullName(),instanceId=n:GetDebugId(16),parentId=n.Parent:GetDebugId(16),className=n.ClassName,properties=props,attributes=n:GetAttributes(),tags=tags,bytes=#source,rawSourceSHA256=hash(source),sourceSHA256=hash(source:gsub("\r\n","\n")),editorMatches=true}
end
assert(not game:GetService("RunService"):IsRunning(),"Owner changed mode")
return H:JSONEncode({schema="mongo-private-locals-fresh-observation-v2",readAtUtc=DateTime.now():ToIsoDate(),rows=rows,nativeWrites=0,objectsCreated=0,modeSwitches=0})

