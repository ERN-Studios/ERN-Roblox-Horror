return function()
local function actual(game,workspace,require)
-- Hides the Level 4 MAP PREVIEW prompts (the cinema with no entity, a developer tool) from players outside
-- DevAccess. Level 5 and Level 6 are public levels; their prompts are for everyone.
-- Cosmetic only: preview access and GameManager re-check DevAccess on every entry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PROMPTS = {
	Level4DeveloperPreviewPrompt = true,
	Level4DeveloperPreviewReturnPrompt = true,
	-- Level 6 is public since 2026-10-03: its prompts are no longer hidden
}

-- Fail closed: a missing or erroring allowlist hides the prompts.
local accessModule = ReplicatedStorage:WaitForChild("DevAccess", 10)
local ok, allowed = pcall(function()
	return accessModule ~= nil and require(accessModule).IsAllowed(Players.LocalPlayer)
end)
if ok and allowed then return end

local watching = setmetatable({}, {__mode = "k"})
local function hide(instance)
	if not PROMPTS[instance.Name] or not instance:IsA("ProximityPrompt") then return end
	if not watching[instance] then
		watching[instance] = true
		instance:GetPropertyChangedSignal("Enabled"):Connect(function()
			if instance.Enabled then instance.Enabled = false end
		end)
	end
	if instance.Enabled then instance.Enabled = false end
end

workspace.DescendantAdded:Connect(hide)
for _, descendant in ipairs(workspace:GetDescendants()) do hide(descendant) end

end
-- Native Instance/property signals; only service/access results and late-stream
-- delivery are controlled. Does not mount objects in the actual workspace.
local checks=0
local function check(value,message) checks+=1;assert(value,message) end
local function stable(value)
 if type(value)~="table" then return tostring(value) end
 local keys={} for key in value do keys[#keys+1]=key end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={} for _,key in keys do out[#out+1]=tostring(key)..":"..stable(value[key]) end
 return "{"..table.concat(out,",").."}"
end
local function settle() for _=1,3 do task.wait() end end
local cases={
 {name="ordinary",id=7,result=false},
 {name="special",id=11374988579,result=false},
 {name="developer",id=40920547,result=true},
 {name="special-developer",id=11374988579,result=true},
 {name="negative-studio-player",id=-1,result=false},
 {name="missing",id=7,missing=true},
 {name="require-error",id=7,requireError=true},
 {name="allowlist-error",id=7,allowlistError=true},
 {name="truthy-string",id=7,result="yes"},
 {name="truthy-number",id=7,result=1},
 {name="truthy-table",id=7,result={}},
 {name="enumeration-error",id=7,result=false,enumerationError=true},
}
local rows={}
for _,case in cases do
 local owned,ownership,connections={},{},{}
 local root=Instance.new("Folder");root.Name="MongoTVPreviewContract_"..case.name
 owned[#owned+1]=root;ownership[root]={name=root.Name,class=root.ClassName}
 local function create(class,name,parent)
  local n=Instance.new(class);owned[#owned+1]=n;n.Name=name;n.Parent=parent or root
  ownership[n]={name=name,class=class}
  return n
 end
 local function prompt(name,enabled,parent)
  local n=create("ProximityPrompt",name,parent);n.Enabled=enabled;return n
 end
 local nest=create("Folder","Nested")
 local enter=prompt("Level4DeveloperPreviewPrompt",true,nest)
 local leave=prompt("Level4DeveloperPreviewReturnPrompt",true,nest)
 local disabled=prompt("Level4DeveloperPreviewPrompt",false,nest)
 local level5=prompt("Level5DeveloperPreviewPrompt",true)
 local level6=prompt("Level6DeveloperPreviewPrompt",true)
 local level6return=prompt("Level6DeveloperPreviewReturnPrompt",true)
 local publicDisabled=prompt("Level6DeveloperPreviewPrompt",false)
 local namesake=create("Folder","Level4DeveloperPreviewPrompt")
 namesake:SetAttribute("Sentinel","keep")
 local unrelated=prompt("UnrelatedPrompt",true)
 local player={UserId=case.id}
 local accessToken={}
 local calls={services={},waits={},requireCount=0,allowedCount=0,worldConnections=0}
 local storage={WaitForChild=function(_,name,timeout)
  check(name=="DevAccess" and timeout==10,"actual bounded access lookup retained")
  calls.waits[#calls.waits+1]={name=name,timeout=timeout}
  return if case.missing then nil else accessToken
 end}
 local gameBoundary={GetService=function(_,name)
  check(name=="Players" or name=="ReplicatedStorage","only existing service dependencies requested")
  calls.services[#calls.services+1]=name
  return if name=="Players" then {LocalPlayer=player} else storage
 end}
 local worldBoundary={DescendantAdded={Connect=function(_,callback)
  calls.worldConnections+=1
  local connection=root.DescendantAdded:Connect(callback)
  connections[#connections+1]=connection
  return connection
 end},GetDescendants=function()
  if case.enumerationError then error("controlled enumeration failure",0) end
  return root:GetDescendants()
 end}
 local requireBoundary=function(token)
  check(token==accessToken,"only controlled DevAccess module requested")
  calls.requireCount+=1
  if case.requireError then error("controlled require failure",0) end
  return {IsAllowed=function(subject)
   check(subject==player,"actual local-player access subject retained")
   calls.allowedCount+=1
   if case.allowlistError then error("controlled allowlist failure",0) end
   return case.result
  end}
 end
 local ok,err=xpcall(function()
  local runOK,runError=pcall(actual,gameBoundary,worldBoundary,requireBoundary)
  if case.enumerationError then
   check(not runOK and tostring(runError):find("controlled enumeration failure",1,true),"same actual enumeration failure retained")
   check(#connections==1 and connections[1].Connected,"partial initializer connection is test-owned")
   rows[#rows+1]={case=case.name,failure="controlled enumeration failure",worldConnections=calls.worldConnections}
   return
  end
  check(runOK,"actual full client source completed: "..tostring(runError))
  settle()
  local allowed=case.result==true and not case.requireError and not case.allowlistError and not case.missing
  check(enter.Enabled==allowed,"L4 initial entry is fail-closed "..case.name)
  check(leave.Enabled==allowed,"L4 initial return is fail-closed "..case.name)
  check(not disabled.Enabled,"initially disabled L4 remains disabled "..case.name)
  check(level5.Enabled and level6.Enabled and level6return.Enabled,"public L5/L6 prompts remain enabled "..case.name)
  check(not publicDisabled.Enabled,"disabled public prompt remains untouched "..case.name)
  check(namesake.Parent==root and namesake:GetAttribute("Sentinel")=="keep","nonprompt namesake remains untouched "..case.name)
  check(unrelated.Enabled,"unrelated prompt remains untouched "..case.name)
  check(calls.worldConnections==(allowed and 0 or 1),"early allowed return preserves connection ownership "..case.name)
  check(calls.requireCount==(case.missing and 0 or 1),"missing module does not execute initializer "..case.name)
  check(calls.allowedCount==((case.missing or case.requireError) and 0 or 1),"allowlist executed once after require "..case.name)
  enter.Enabled=true;leave.Enabled=true;disabled.Enabled=true;settle()
  check(enter.Enabled==allowed and leave.Enabled==allowed and disabled.Enabled==allowed,"native re-enable policy retained "..case.name)
  local late=prompt("Level4DeveloperPreviewPrompt",true,nest);settle()
  check(late.Enabled==allowed,"owned descendant addition uses actual hide callback "..case.name)
  late.Enabled=true;settle();check(late.Enabled==allowed,"late native re-enable retained "..case.name)
  local latePublic=prompt("Level6DeveloperPreviewPrompt",true,nest);settle()
  check(latePublic.Enabled,"late public Level6 prompt retained "..case.name)
  local remove=prompt("Level4DeveloperPreviewReturnPrompt",true,nest);settle()
  check(remove.Enabled==allowed,"second distinct late return prompt uses actual callback "..case.name)
  remove.Parent=nil;settle();remove.Enabled=true;settle()
  check(remove.Enabled==allowed,"detached owned prompt watcher behavior retained "..case.name)
  remove.Parent=nest;settle()
  check(remove.Enabled==allowed,"reparented prompt still uses actual callback "..case.name)
  level6.Enabled=false;settle();level6.Enabled=true;settle()
  check(level6.Enabled,"public re-enable remains unconstrained "..case.name)
  rows[#rows+1]={case=case.name,allowed=allowed,entry=enter.Enabled,returnPrompt=leave.Enabled,
   late=late.Enabled,latePublic=latePublic.Enabled,detachedReparented=remove.Enabled,
   publicEnabled=level6.Enabled,publicDisabled=publicDisabled.Enabled,nonPromptSentinel=namesake:GetAttribute("Sentinel"),calls=calls}
 end,debug.traceback)
 -- Fixture cleanup applies on all successful and failing assertion/callback
 -- paths. The production client has no cleanup API; none is added or removed.
 local cleanupErrors={}
 for _,connection in connections do
  local clean,why=pcall(function()connection:Disconnect()end)
  if not clean then cleanupErrors[#cleanupErrors+1]=tostring(why) end
 end
 for index=#owned,1,-1 do
  local n=owned[index]
  local clean,why=pcall(function()
   assert(ownership[n] and n.Name==ownership[n].name and n.ClassName==ownership[n].class,"Only exact test-owned identity may be destroyed")
   assert(n==root or n.Parent==root or n:IsDescendantOf(root) or n.Parent==nil,"Only unchanged test-owned objects may be destroyed")
   for _,descendant in n:GetDescendants() do assert(ownership[descendant],"Preserve foreign objects added to owned fixture") end
   n:Destroy()
  end)
  if not clean then cleanupErrors[#cleanupErrors+1]=tostring(why) end
 end
 settle()
 for _,connection in connections do check(not connection.Connected,"owned world connection disconnected after "..case.name) end
 for _,n in owned do check(n.Parent==nil,"owned native object unparented after "..case.name) end
 check(#cleanupErrors==0,"owned cleanup completed after "..case.name..": "..table.concat(cleanupErrors," | "))
 if not ok then error(err,0) end
end
return {checks=checks,signature=stable(rows),caseCount=#cases}

end
