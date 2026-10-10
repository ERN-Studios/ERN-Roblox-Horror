local H=game:GetService("HttpService")
local RS=game:GetService("RunService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local function guard()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
 assert(not RS:IsRunning(),"Edit only; no mode switch")
end
local function sha(s)
 local b=ENC:ComputeBufferHash(buffer.fromstring(s),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(b)-1 do out[#out+1]=string.format("%02x",buffer.readu8(b,i)) end return table.concat(out)
end
local function resolve(segments)
 local n=game for _,name in segments do
  local found={} for _,child in n:GetChildren() do if child.Name==name then found[#found+1]=child end end
  assert(#found==1,"Ambiguous/missing exact path")
  n=found[1]
 end return n
end
guard()
local targets={
 {segments={"ServerScriptService","Level 3 Systems","Level 3 Worn Party Room Dressing"},oldSHA="4424920501f4fafa63788f1fb70a3263e23d75e31741d68a37bd6f55b48f511a",names={"reservePerimeter","safeRect","localPosition"}},
 {segments={"ServerScriptService","Level 1 Systems","PuzzleManager"},oldSHA="6cde618088f7aff94385e7348c830f07b597b011bb64640def7395b7a53b2ad7",names={"latchMode"}},
 {segments={"ServerScriptService","Level 4 Systems","Level 4 Usher Controller"},oldSHA="9af1a745968b95928355707aeaf81bf36b2e9495bdc589918b72bca10d6ba7e3",names={"targetReason","nextThinkAt","stunUntil"}}
}
local rows={}
for _,target in targets do
 local n=resolve(target.segments)
 local source=n.Source local editor=SES:GetEditorSource(n) local canonical=source:gsub("\r\n","\n")
 local properties={}
 for _,name in {"Enabled","Disabled","RunContext","Archivable","LinkedSource"} do
  local ok,value=pcall(function()return n[name]end)
  if ok then properties[name]=if typeof(value)=="EnumItem" then tostring(value) else value end
 end
 local excerpts={} local lineNumber=0
 for line in (canonical.."\n"):gmatch("(.-)\n") do
  lineNumber+=1
  for _,name in target.names do if line:find(name,1,true) then
   assert(#line<650,"Unexpected long matching line")
   excerpts[#excerpts+1]={lineNumber=lineNumber,text=line};break
  end end
 end
 assert(#excerpts<30,"Unexpected bounded closure growth")
 local row={segments=target.segments,studioPath=n:GetFullName(),instanceId=n:GetDebugId(16),parentId=n.Parent:GetDebugId(16),className=n.ClassName,properties=properties,attributes=n:GetAttributes(),tags=n:GetTags(),rawBytes=#source,canonicalBytes=#canonical,rawSourceSHA256=sha(source),sourceSHA256=sha(canonical),rawEditorSHA256=sha(editor),sourceEditorMatches=source==editor,oldCASStillValid=sha(canonical)==target.oldSHA,excerpts=excerpts}
 assert(n.Source==source and SES:GetEditorSource(n)==editor,"Source drift during observation")
 rows[#rows+1]=row
end
guard()
return H:JSONEncode({schema="mongo-cleanup-pending-locals-fresh-observation-v1",readAtUtc=DateTime.now():ToIsoDate(),placeId=game.PlaceId,universeId=game.GameId,datamodel="Edit",nativeWrites=0,sourceWrites=0,probeObjects=0,modeSwitches=0,rows=rows})
