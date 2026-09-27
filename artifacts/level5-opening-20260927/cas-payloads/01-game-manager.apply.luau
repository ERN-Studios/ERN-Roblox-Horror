-- Single existing script only. Generated from verified baseline; DO NOT RUN AS A BATCH.
-- No new Instances, source buffers, runtime rebuilds, attributes or property edits.
local HttpService=game:GetService("HttpService")
local ScriptEditorService=game:GetService("ScriptEditorService")
local names={"ServerScriptService","GameManager"}
local wantedClass="Script"
local baselineLength,baselineDjb=165648,3634059721
local expectedLength,expectedDjb=166063,951332234
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
 {old=" workspace:SetAttribute(Routing.Level4DevAttribute, true)\nend\n\n-- LEVEL5_MAP_PREVIEW_20260923. A ceiling is only a transport bound. Access\n-- is checked against the REQUESTED level too, so enabling 5 cannot enable 4.\nif workspace:GetAttribute(Routing.Level5DevAttribute) == nil then\n workspace:SetAttribute(Routing.Level5DevAttribute, true)\nend\nlocal function devCeiling(group)\n if type(group) ~= \"table\" or #group == 0 then return Routing.MaxLevel end\n for _, player in ipairs(group) do\n  if not DevAccess.IsAllowed(player) then return Routing.MaxLevel end\n end\n",new=" workspace:SetAttribute(Routing.Level4DevAttribute, true)\nend\n\n-- Level 5 is a selectable public preview, separate from campaign progression.\n-- A ceiling is only a transport bound: canAccessLevel still checks the exact\n-- requested level, so opening 5 never opens the developer-only Level 4.\n-- Explicit false keeps public entry closed while preserving developer access.\nif workspace:GetAttribute(\"Level5PublicPreviewEnabled\") == nil then\n workspace:SetAttribute(\"Level5PublicPreviewEnabled\", true)\nend\nif workspace:GetAttribute(Routing.Level5DevAttribute) == nil then\n workspace:SetAttribute(Routing.Level5DevAttribute, true)\nend\nlocal function devCeiling(group)\n if type(group) ~= \"table\" or #group == 0 then return Routing.MaxLevel end\n if workspace:GetAttribute(\"Level5PublicPreviewEnabled\") == true then return 5 end\n for _, player in ipairs(group) do\n  if not DevAccess.IsAllowed(player) then return Routing.MaxLevel end\n end\n"},
 {old="\nlocal function canAccessLevel(requestedLevel, group)\n local level = tonumber(requestedLevel)\n if not level or level ~= level then return false end\n if level <= Routing.MaxLevel then return true end\n local flag = level == 4 and Routing.Level4DevAttribute\n  or level == 5 and Routing.Level5DevAttribute or nil\n if not flag or workspace:GetAttribute(flag) ~= true then return false end\n",new="\nlocal function canAccessLevel(requestedLevel, group)\n local level = tonumber(requestedLevel)\n if not level or level ~= level or level % 1 ~= 0 or level < 1 then return false end\n if level <= Routing.MaxLevel then return true end\n if level == 5 and workspace:GetAttribute(\"Level5PublicPreviewEnabled\") == true then\n  return type(group) == \"table\" and #group > 0\n end\n local flag = level == 4 and Routing.Level4DevAttribute\n  or level == 5 and Routing.Level5DevAttribute or nil\n if not flag or workspace:GetAttribute(flag) ~= true then return false end\n"},
 {old="local function ensureWorld(group, requestedLevel, attempt)\n if attempt and not attempt:IsOpen() then return false end\n if not canAccessLevel(requestedLevel, group) then return false end\n -- LEVEL4_DEV_GATE_20260921: ClampLevelTo with the dev ceiling. For every\n -- normal party devCeiling() returns Routing.MaxLevel, so this is exactly the\n -- old Routing.ClampLevel(requestedLevel).\n local level = Routing.ClampLevelTo(requestedLevel, devCeiling(group))\n if worldReady and activeLevel == level then return true end\n activeLevel = level\n",new="local function ensureWorld(group, requestedLevel, attempt)\n if attempt and not attempt:IsOpen() then return false end\n if not canAccessLevel(requestedLevel, group) then return false end\n -- Access was checked for this exact level. The transport ceiling also\n -- includes the standalone public preview without changing the campaign.\n local level = Routing.ClampLevelTo(requestedLevel, devCeiling(group))\n if worldReady and activeLevel == level then return true end\n activeLevel = level\n"},
 {old="  table.sort(participants, function(a, b) return a.UserId < b.UserId end)\n  while #participants > MAX_PLAYERS_PER_STATION do table.remove(participants) end\n  if #participants == 0 then attempt:Fail(\"PARTY_LEFT\"); return end\n  -- LEVEL4_DEV_GATE_20260921: clamped AFTER the roster is known, because the\n  -- dev ceiling requires every arriving member to pass DevAccess. For a normal\n  -- party this is exactly the old Routing.ClampLevel(group.Level).\n  if not canAccessLevel(group.Level, participants) then\n   attempt:SetMembers(participants)\n   attempt:Fail(\"LEVEL_ACCESS_DENIED\")\n",new="  table.sort(participants, function(a, b) return a.UserId < b.UserId end)\n  while #participants > MAX_PLAYERS_PER_STATION do table.remove(participants) end\n  if #participants == 0 then attempt:Fail(\"PARTY_LEFT\"); return end\n  -- Check the exact destination after the whole roster arrives. The public\n  -- Level 5 preview is independent of Level 4's entire-party developer check.\n  if not canAccessLevel(group.Level, participants) then\n   attempt:SetMembers(participants)\n   attempt:Fail(\"LEVEL_ACCESS_DENIED\")\n"}
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
