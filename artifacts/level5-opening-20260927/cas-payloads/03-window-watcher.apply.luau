-- Single existing script only. Generated from verified baseline; DO NOT RUN AS A BATCH.
-- No new Instances, source buffers, runtime rebuilds, attributes or property edits.
local HttpService=game:GetService("HttpService")
local ScriptEditorService=game:GetService("ScriptEditorService")
local names={"ServerScriptService","Level 5 Systems","Level 5 Window Watcher Encounters"}
local wantedClass="ModuleScript"
local baselineLength,baselineDjb=23722,2001089542
local expectedLength,expectedDjb=23818,4257775843
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
 {old="-- Passive intermittent Window Watcher; one prepared rig, curated windows in all eight districts.\n-- No AI, damage, chase, sounds, rewards, movement/pathfinding or delayed tasks.\n-- Start only from the existing developer-only Level 5 round adapter.\n-- Import contract: bottom pivot, 8 studs tall, facing local -Z. Mesh/rest bones\n-- AND animation translations must share the import scale (~3.333 studs/metre).\n-- Never fix this by scaling only MeshPart.Size. Verify native animated extrema.\n",new="-- Passive intermittent Window Watcher; one prepared rig, curated windows in all eight districts.\n-- No AI, damage, chase, sounds, rewards, movement/pathfinding or delayed tasks.\n-- Start only from the enabled public/developer Level 5 preview round adapter.\n-- Import contract: bottom pivot, 8 studs tall, facing local -Z. Mesh/rest bones\n-- AND animation translations must share the import scale (~3.333 studs/metre).\n-- Never fix this by scaling only MeshPart.Size. Verify native animated extrema.\n"},
 {old="local MAX_RAYS_PER_SCAN=96\nlocal MAX_WINDOWS_PER_SCAN=24\nlocal SCAN_INTERVAL=.75\n\nlocal function finite(value)\n\treturn type(value)==\"number\" and value==value and math.abs(value)<math.huge\n",new="local MAX_RAYS_PER_SCAN=96\nlocal MAX_WINDOWS_PER_SCAN=24\nlocal SCAN_INTERVAL=.75\n\nlocal function previewEnabled()\n\treturn workspace:GetAttribute(\"Level5PublicPreviewEnabled\")==true\n\t\tor workspace:GetAttribute(\"Level5DevEnabled\")==true\nend\n\nlocal function finite(value)\n\treturn type(value)==\"number\" and value==value and math.abs(value)<math.huge\n"},
 {old="\tend\n\tif typeof(world)~=\"Instance\" or not world:IsA(\"Model\")\n\t\tor world.Name~=\"Level 5 Generated World\" or world:GetAttribute(\"Level5_MapOnly\")~=true\n\t\tor workspace:GetAttribute(\"Level5DevEnabled\")~=true or not world:IsDescendantOf(workspace) then\n\t\treturn failure(\"requires the enabled Level 5 developer map preview in Workspace\")\n\tend\n\tif typeof(options.Origin)~=\"Vector3\" or type(options.GetParticipants)~=\"function\" then\n\t\treturn failure(\"Origin and a synchronous GetParticipants callback are required\")\n",new="\tend\n\tif typeof(world)~=\"Instance\" or not world:IsA(\"Model\")\n\t\tor world.Name~=\"Level 5 Generated World\" or world:GetAttribute(\"Level5_MapOnly\")~=true\n\t\tor not previewEnabled() or not world:IsDescendantOf(workspace) then\n\t\treturn failure(\"requires an enabled Level 5 preview in Workspace\")\n\tend\n\tif typeof(options.Origin)~=\"Vector3\" or type(options.GetParticipants)~=\"function\" then\n\t\treturn failure(\"Origin and a synchronous GetParticipants callback are required\")\n"},
 {old="\t\tlocal elapsed=0\n\t\tlocal function step(now)\n\t\t\tif state.cleaned then return end\n\t\t\tif workspace:GetAttribute(\"Level5DevEnabled\")~=true then cleanup(false);return end\n\t\t\tif not ready then\n\t\t\t\tlocal loaded=true\n\t\t\t\tfor _,track in ipairs(state.tracks) do if track.Length<=0 then loaded=false;break end end\n",new="\t\tlocal elapsed=0\n\t\tlocal function step(now)\n\t\t\tif state.cleaned then return end\n\t\t\tif not previewEnabled() then cleanup(false);return end\n\t\t\tif not ready then\n\t\t\t\tlocal loaded=true\n\t\t\t\tfor _,track in ipairs(state.tracks) do if track.Length<=0 then loaded=false;break end end\n"}
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
