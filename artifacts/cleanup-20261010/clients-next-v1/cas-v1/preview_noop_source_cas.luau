-- Root-only scoped Source CAS. Read/checkpoint first; no objects or mode switches.
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local ENC=game:GetService("EncodingService")
local request=H:JSONDecode(__REQUEST__)
local function mode()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
 assert(not RS:IsRunning(),"Edit-only CAS; preserve owner's Play")
end
local function sha(source)
 local b=ENC:ComputeBufferHash(buffer.fromstring(source),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(b)-1 do out[#out+1]=string.format("%02x",buffer.readu8(b,i)) end return table.concat(out)
end
local function stable(value)
 if type(value)~="table" then return H:JSONEncode(value) end
 local keys={} for key in value do keys[#keys+1]=key end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={} for _,key in keys do out[#out+1]=H:JSONEncode(key)..":"..stable(value[key]) end
 return "{"..table.concat(out,",").."}"
end
local function segments(n)
 local result={} while n~=game do table.insert(result,1,n.Name);n=assert(n.Parent,"Unparented original") end return result
end
local function metadata(n)
 local properties={} for _,name in {"Enabled","Disabled","RunContext","Archivable","LinkedSource"} do
  local ok,value=pcall(function()return n[name]end)
  if ok then properties[name]=if typeof(value)=="EnumItem" then tostring(value) else value end
 end
 local tags=n:GetTags() table.sort(tags)
 return {segments=segments(n),studioPath=n:GetFullName(),instanceId=n:GetDebugId(16),parentId=n.Parent:GetDebugId(16),
  className=n.ClassName,properties=properties,attributes=n:GetAttributes(),tags=tags}
end
local function resolve(parts)
 local n=game for _,name in parts do
  local found={} for _,child in n:GetChildren() do if child.Name==name then found[#found+1]=child end end
  assert(#found==1,"Missing/ambiguous original path") n=found[1]
 end return n
end
local targetParts={"StarterPlayer","StarterPlayerScripts","Level4PreviewPrompt"}
local target=resolve(targetParts)
local function targetIdentity()
 local m=metadata(target)
 assert(m.instanceId=="1_31106" and m.parentId=="1_410029" and m.className=="LocalScript","Fresh target identity changed")
 assert(stable(m.properties)==stable(request.targetProperties) and stable(m.attributes)==stable(request.targetAttributes)
  and stable(m.tags)==stable(request.targetTags),"Fresh target metadata changed")
 return m
end
mode();targetIdentity()
local function targetSummary()
 local source=target.Source local editor=SES:GetEditorSource(target)
 local row=metadata(target)
 row.sourceSHA256=sha(source) row.editorSHA256=sha(editor)
 row.sourceEditorMatches=source==editor row.bytes=#source row.editorBytes=#editor
 assert(target.Source==source and SES:GetEditorSource(target)==editor,"Target changed during summary")
 return row
end
if request.operation=="target" then
 return H:JSONEncode({pass=true,operation="target",target=targetSummary(),originalSourceWrites=0,modeSwitches=0})
end
if request.operation=="capture" or request.operation=="observe" then
 local rows,map={},{}
 local targetSource=target.Source local targetEditor=SES:GetEditorSource(target)
 assert(targetSource==targetEditor,"Target Source/editor conflict")
 if request.operation=="capture" then
  assert(sha(targetSource)==request.expectedTargetSHA256,"Fresh target is no longer exact selected Source")
 end
 for index,n in game:GetDescendants() do
  if n:IsA("LuaSourceContainer") then
   local body=n.Source local editor=SES:GetEditorSource(n) assert(body==editor,"Original Source/editor conflict")
   local row=metadata(n) row.sha256=sha(body) row.bytes=#body
   rows[#rows+1]=row;map[n]={body=body,meta=stable(metadata(n))}
  end
  if index%10000==0 then task.wait();mode() end
 end
 assert(#rows==request.nativeScriptCount,"Concurrent Source count change")
 -- Final no-yield full Source/editor/property guard after the bounded census.
 mode();targetIdentity()
 for n,saved in map do assert(n.Source==saved.body and SES:GetEditorSource(n)==saved.body and stable(metadata(n))==saved.meta,"Original changed during capture") end
 assert(target.Source==targetSource and SES:GetEditorSource(target)==targetEditor,"Target changed during capture")
 table.sort(rows,function(a,b)return a.studioPath<b.studioPath end)
 local first=request.pageFirst local count=request.pageCount
 assert(type(first)=="number" and first>=1 and first%1==0 and count==20,"Bounded page required")
 local page={} for index=first,math.min(first+count-1,#rows) do page[#page+1]=rows[index] end
 return H:JSONEncode({pass=true,operation=request.operation,target=targetSummary(),rows=page,
  catalogSHA256=sha(stable(rows)),totalRows=#rows,pageFirst=first,pageCount=count,
  readAtUtc=DateTime.now():ToIsoDate(),originalSourceWrites=0,modeSwitches=0,objectsCreated=0})
end
assert(request.operation=="apply" or request.operation=="rollback" or request.operation=="verify","Unknown operation")
local originals={}
for _,row in request.rows do
 local n=resolve(row.segments)
 assert(not originals[n],"Duplicate baseline original") originals[n]=row
end
assert(#request.rows==request.nativeScriptCount and originals[target],"Exact original coverage required")
local fromHash=if request.operation=="verify" then request.expectedTargetSHA256 elseif request.operation=="apply" then request.beforeSHA256 else request.afterSHA256
local toHash=if request.operation=="apply" then request.afterSHA256 else request.beforeSHA256
local function guard(fullCensus,changed)
 mode();targetIdentity()
 for n,row in originals do
  local m=metadata(n)
  local hash=if n==target then (if changed then toHash else fromHash) else row.sha256
  assert(m.instanceId==row.instanceId and m.parentId==row.parentId and m.className==row.className and stable(m.segments)==stable(row.segments),"Original identity/Parent/class changed")
  assert(stable(m.properties)==stable(row.properties) and stable(m.attributes)==stable(row.attributes) and stable(m.tags)==stable(row.tags),"Original metadata changed")
  local body=n.Source assert(SES:GetEditorSource(n)==body and sha(body)==hash,"Original Source/editor changed")
 end
 if fullCensus then
  local count=0 for index,n in game:GetDescendants() do
   if n:IsA("LuaSourceContainer") then assert(originals[n],"New original Source appeared");count+=1 end
   if index%10000==0 then task.wait();mode() end
  end
  assert(count==request.nativeScriptCount,"Original Source removed")
  guard(false,changed)
 end
end
guard(true,false)
if request.operation=="verify" then
 return H:JSONEncode({pass=true,operation="verify",originalSourceCoverage=request.nativeScriptCount,
  sourceSHA256=sha(target.Source),originalSourceWrites=0,modeSwitches=0})
end
local replacements={
 {old=string.sub([=[_if ok and allowed == true then return end
-- ZenMeister02 can see only the isolated Level 6 preview doorway.
if Players.LocalPlayer.UserId == 11374988579 then
	PROMPTS.Level6DeveloperPreviewPrompt = nil
	PROMPTS.Level6DeveloperPreviewReturnPrompt = nil
end

local watching = setmetatable({}, {__mode = "k"})]=],2),new=string.sub([=[_if ok and allowed == true then return end

local watching = setmetatable({}, {__mode = "k"})]=],2)},
}
local function transform(current)
 local result=current
 for i=1,#replacements do
  local index=if request.operation=="rollback" then #replacements-i+1 else i
  local entry=replacements[index]
  local old,new=entry.old,entry.new
  if request.operation=="rollback" then old,new=new,old end
  assert(#old>0 and #new>0,"Only exact nonempty scoped helper anchors")
  local start,finish=result:find(old,1,true)
  assert(start and not result:find(old,finish+1,true),"Unique scoped private helper required")
  result=result:sub(1,start-1)..new..result:sub(finish+1)
 end
 assert(sha(result)==toHash,"Scoped replacement result differs from reviewed Source")
 return result
end
SES:UpdateSourceAsync(target,function(current)
 -- No task.wait/async calls between this fresh guard and callback return.
 guard(false,false)
 assert(current==target.Source and current==SES:GetEditorSource(target) and sha(current)==fromHash,"Fresh callback Source/editor CAS changed")
 return transform(current)
end)
guard(true,true)
return H:JSONEncode({pass=true,operation=request.operation,path=target:GetFullName(),instanceId=target:GetDebugId(16),
 sourceSHA256=sha(target.Source),sourceEditorMatches=target.Source==SES:GetEditorSource(target),bytes=#target.Source,
 originalSourceCoverage=request.nativeScriptCount,originalSourceWrites=1,otherOriginalSourceWrites=0,
 originalPropertyWrites=0,originalParentWrites=0,modeSwitches=0,objectsCreated=0,
 readAtUtc=DateTime.now():ToIsoDate(),guardSemantics="Exact final point-in-time originals guard after yielding census; no continuous external-change certificate."})
