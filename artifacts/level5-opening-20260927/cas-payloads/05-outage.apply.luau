-- Single existing script only. Generated from verified baseline; DO NOT RUN AS A BATCH.
-- No new Instances, source buffers, runtime rebuilds, attributes or property edits.
local HttpService=game:GetService("HttpService")
local ScriptEditorService=game:GetService("ScriptEditorService")
local names={"ServerScriptService","Level 5 Systems","Level 5 Power Outage"}
local wantedClass="ModuleScript"
local baselineLength,baselineDjb=8618,398132620
local expectedLength,expectedDjb=8818,3854323309
local invoked,accepted=false,false
local function djb2(text)
 local h=5381
 for i=1,#text do h=(h*33+string.byte(text,i))%4294967296 end
 return h
end
local function finish(status,detail)
 return HttpService:JSONEncode({status=status,detail=detail or "",path=table.concat(names,"."),class=wantedClass,
  updateInvoked=invoked,callbackAccepted=accepted,baselineLength=baselineLength,baselineDjb2=baselineDjb,
  expectedLength=expectedLength,expectedDjb2=expectedDjb})
end
if game.PlaceId~=131311258779917 or game.GameId~=10559217407 then return finish("WRONG_PLACE") end
if game:GetService("RunService"):IsRunning() then return finish("EDIT_MODE_REQUIRED") end
local function resolve()
 local parent=game
 for _,name in ipairs(names) do
  local found=nil
  for _,child in ipairs(parent:GetChildren()) do
   if child.Name==name then
    if found then return nil,"AMBIGUOUS_PATH" end
    found=child
   end
  end
  if not found then return nil,"MISSING_PATH" end
  parent=found
 end
 if parent.ClassName~=wantedClass then return nil,"WRONG_CLASS" end
 return parent,nil
end
local target,resolveError=resolve()
if not target then return finish(resolveError) end
local ok,current,editor=pcall(function()return target.Source,ScriptEditorService:GetEditorSource(target)end)
if not ok then return finish("READ_FAILED",tostring(current)) end
if current~=editor then return finish("SOURCE_EDITOR_CONFLICT") end
if #current~=baselineLength or djb2(current)~=baselineDjb then return finish("BASELINE_CHANGED") end
local edits={
 {old="local HttpService=game:GetService(\"HttpService\")\nlocal Logic=require(RS:WaitForChild(\"Level5OutageLogic\"))\nlocal Outage={}\nlocal sessions=setmetatable({},{__mode=\"k\"})\nlocal SCHEDULE_ATTRIBUTE=\"Level5OutageSchedule\"\nlocal SECTION_ATTRIBUTE=\"Level5OutageSection\"\n",new="local HttpService=game:GetService(\"HttpService\")\nlocal Logic=require(RS:WaitForChild(\"Level5OutageLogic\"))\nlocal Outage={}\nlocal OUTAGES_ENABLED=false -- Temporarily disabled at the owner's request; keep fixture metadata and cleanup.\nlocal sessions=setmetatable({},{__mode=\"k\"})\nlocal SCHEDULE_ATTRIBUTE=\"Level5OutageSchedule\"\nlocal SECTION_ATTRIBUTE=\"Level5OutageSection\"\n"},
 {old="end\n\nfunction Outage.Trigger(world,gate)\n\tlocal s=sessions[world]\n\tif not s or not live(s) then return false,\"No live outage controller\" end\n\tif not integer(gate,1,7) then return false,\"Gate outside 1..7\" end\n",new="end\n\nfunction Outage.Trigger(world,gate)\n\tif not OUTAGES_ENABLED then return false,\"Level 5 outages are temporarily disabled\" end\n\tlocal s=sessions[world]\n\tif not s or not live(s) then return false,\"No live outage controller\" end\n\tif not integer(gate,1,7) then return false,\"Gate outside 1..7\" end\n"}
}
local ranges={}
for index,edit in ipairs(edits) do
 local a,b=string.find(current,edit.old,1,true)
 if not a then return finish("FRAGMENT_MISSING",tostring(index)) end
 if string.find(current,edit.old,a+1,true) then return finish("FRAGMENT_NOT_UNIQUE",tostring(index)) end
 if index>1 and a<=ranges[index-1].last then return finish("OVERLAPPING_FRAGMENTS",tostring(index)) end
 ranges[index]={first=a,last=b,replacement=edit.new}
end
local newSource=current
for index=#ranges,1,-1 do
 local span=ranges[index]
 newSource=string.sub(newSource,1,span.first-1)..span.replacement..string.sub(newSource,span.last+1)
end
if #newSource~=expectedLength or djb2(newSource)~=expectedDjb then return finish("PATCH_FINGERPRINT_MISMATCH") end
if newSource==current then return finish("NO_CHANGE") end
local callbackProblem=nil
local writeOK,writeError=pcall(function()
 invoked=true
 ScriptEditorService:UpdateSourceAsync(target,function(old)
  -- Roblox may call again if an editor changes while the update is in flight.
  -- Returning nil cancels the update, including on a later retry.
  if callbackProblem then return nil end
  if old~=current then callbackProblem="CALLBACK_BASELINE_CHANGED";return nil end
  local stillTarget=resolve()
  if stillTarget~=target then callbackProblem="INSTANCE_PATH_CHANGED";return nil end
  if target.Source~=current then callbackProblem="SOURCE_CHANGED_DURING_UPDATE";return nil end
  accepted=true
  return newSource
 end)
end)
if callbackProblem then return finish(callbackProblem,"Cancelled; reread authoritative Source/editor before preparing another patch.") end
if not writeOK then return finish("UPDATE_FAILED",tostring(writeError)) end
if not accepted then return finish("UPDATE_CANCELLED") end
local readOK,sourceAfter,editorAfter=pcall(function()return target.Source,ScriptEditorService:GetEditorSource(target)end)
if not readOK then return finish("POSTWRITE_READ_FAILED",tostring(sourceAfter)) end
if sourceAfter==newSource and editorAfter==newSource then return finish("APPLIED_VERIFIED") end
return finish("POSTWRITE_PARITY_NOT_VERIFIED",HttpService:JSONEncode({sourceLength=#sourceAfter,sourceDjb2=djb2(sourceAfter),editorLength=#editorAfter,editorDjb2=djb2(editorAfter),equal=sourceAfter==editorAfter}))
