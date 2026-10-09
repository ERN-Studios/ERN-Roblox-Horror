-- Offline actual-source ownership contracts. All instances/services below are fakes.
local current=require("./new_reopen_contract")
local before=require("./before_reopen_contract")
local cases,checks=0,0
local function check(value,message) assert(value,message) checks+=1 end
local function scenario(kind,run,old)
 local originals,all,originalFacts,validRoots={},{},{},{}
 local destroyAttempts,originalDestroyAttempts,destroyed,yields=0,0,0,0
 local modeOkay=true
 local function make(name,parent,original,class)
  local node={_instance=true,Name=name,ClassName=class or "Folder",Parent=parent,Source="source:"..name,
   attributes={preserve=name},children={},destroyed=false}
  function node:GetDescendants()
   if self.throwDescendants then error("fake descendant getter failed") end
   local result={}
   local function walk(s)
    for _,child in s.children do result[#result+1]=child walk(child) end
   end
   walk(self) return result
  end
  function node:IsDescendantOf(target)
   local p=self.Parent local seen={}
   while p do assert(not seen[p],"fake parent cycle") seen[p]=true
    if p==target then return true end p=p.Parent
   end
   return false
  end
  function node:Destroy()
   destroyAttempts+=1
   if originals[self] then originalDestroyAttempts+=1 error("ORIGINAL DESTROY FORBIDDEN") end
   if self.throwDestroy then error("fake independent destroy failure") end
   assert(not self.destroyed,"double fake destroy")
   self.destroyed=true destroyed+=1
   for _,child in self.children do child:Destroy() end
  end
  all[#all+1]=node
  if original then
   originals[node]=true
   originalFacts[node]={name=node.Name,class=node.ClassName,parent=node.Parent,source=node.Source,
    attributes=node.attributes,attributeValue=node.attributes.preserve}
  end
  return node
 end
 local game=make("game",nil,true)
 local live=make("LiveNative",game,true) game.children={live}
 local liveChild=make("LiveChild",live,true) live.children={liveChild}
 local held=make("HeldParentNil",nil,true)
 local heldChild=make("HeldChild",held,true) held.children={heldChild}
 local ledgerScript=make("OtherLedgerScript",nil,true,"ModuleScript")
 local ledgerScriptChild=make("OtherLedgerScriptChild",ledgerScript,true) ledgerScript.children={ledgerScriptChild}
 local state={rootRefs={[held]={},[live]={}},scriptRefs={[ledgerScript]={}}}
 local rows={[held]={},[heldChild]={}}
 local copies={}
 for i=1,23 do
  local root=make("Copy"..i,nil,false)
  local child=make("CopyChild"..i,root,false) root.children={child}
  copies[#copies+1]=root validRoots[#validRoots+1]=root
 end
 local rejected
 if kind=="first-held-original" then rejected=held table.insert(copies,1,held)
 elseif kind=="first-held-child" then
  rejected=make("ForeignWrapper",nil,false) rejected.children={heldChild}
  table.insert(copies,1,rejected)
 elseif kind=="first-live-child" then
  rejected=make("ForeignWrapper",nil,false) rejected.children={liveChild}
  table.insert(copies,1,rejected)
 elseif kind=="first-other-ledger-source" then rejected=ledgerScript table.insert(copies,1,ledgerScript)
 elseif kind=="first-ledger-source-child" then
  rejected=make("ForeignWrapper",nil,false) rejected.children={ledgerScriptChild}
  table.insert(copies,1,rejected)
 elseif kind=="first-getter-error" then
  rejected=make("GetterError",nil,false) rejected.throwDescendants=true
  table.insert(copies,1,rejected)
 elseif kind=="duplicate-return" then table.insert(copies,1,copies[1])
 elseif kind=="wrong-count" then
  local extra=make("ExtraCopy",nil,false) copies[#copies+1]=extra validRoots[#validRoots+1]=extra
 elseif kind=="destroy-error" then copies[1].throwDestroy=true
 elseif kind=="baseline-yield-mode-change" then
  for i=1,550 do local n=make("LedgerNode"..i,held,true) held.children[#held.children+1]=n end
 end
 local function originalsUnchanged()
  for node,fact in originalFacts do
   check(not node.destroyed and node.Name==fact.name and node.ClassName==fact.class and node.Parent==fact.parent
    and node.Source==fact.source and node.attributes==fact.attributes and node.attributes.preserve==fact.attributeValue,
    "original metadata/source/parent changed")
  end
 end
 local env={game=game,state=state,census=game:GetDescendants(),rows=rows,copies=copies,
  typeof=function(v)return if type(v)=="table" and v._instance then "Instance" else type(v)end,
  owned=function()return modeOkay end,
  wait=function()yields+=1 if kind=="baseline-yield-mode-change" then modeOkay=false end end,
  check=check,originals=originalsUnchanged}
 env.beforeCleanup=function()
  if kind=="foreign-parent-after-adopt" then copies[1].Parent=live
  elseif kind=="original-child-after-adopt" then copies[1].children[#copies[1].children+1]=liveChild
  elseif kind=="foreign-child-after-adopt" then
   local alien=make("Alien",copies[1],false) copies[1].children[#copies[1].children+1]=alien
  end
 end
 local result=run(env)
 originalsUnchanged()
 check(originalDestroyAttempts==0,"original Destroy attempted")
 if old then
  check(not result.pass,"old abnormal result falsely succeeded")
  check(result.destroyedRoots==0,"old first rejection should reproduce later cleanup leak")
  for _,root in validRoots do check(not root.destroyed,"old before-control leak reproduction changed") end
 elseif kind=="baseline-yield-mode-change" then
  check(yields==1 and not result.baselineComplete and result.createdRoots==0 and result.destroyedRoots==0,
   "bounded original registration must stop before deserialization")
 else
  check(result.baselineComplete and result.protectedGameAndLedger,"full game/ledger identity closure not protected")
  local exceptional=kind=="destroy-error" or kind=="foreign-parent-after-adopt"
   or kind=="original-child-after-adopt" or kind=="foreign-child-after-adopt"
  local count=if kind=="wrong-count" then 24 else 23
  check(result.adoptedRoots==count,"later eligible roots not independently adopted: "..kind)
  check(result.destroyedRoots==count-(if exceptional then 1 else 0),"later owned cleanup skipped: "..kind)
  check(result.testOwnedRootsRemaining==(if exceptional then 1 else 0),"remaining owned result false")
  check(result.pass==(kind=="success"),"abnormal result cannot pass: "..kind)
  for i,root in validRoots do
   check(root.destroyed==(not exceptional or i~=1),"eligible later root leaked: "..kind)
  end
  if rejected and not originals[rejected] then check(not rejected.destroyed,"unsafe returned wrapper destroyed") end
  if string.sub(kind,1,6)=="first-" or kind=="duplicate-return" then
   check(#result.copyAdoptionErrors==1,"independent adoption error not retained")
  end
 end
 cases+=1
end
for _,kind in {"success","first-held-original","first-held-child","first-live-child","first-other-ledger-source",
 "first-ledger-source-child","first-getter-error","duplicate-return","wrong-count","destroy-error",
 "foreign-parent-after-adopt","original-child-after-adopt","foreign-child-after-adopt","baseline-yield-mode-change"} do
 scenario(kind,current,false)
end
scenario("first-held-original",before,true)
scenario("first-held-child",before,true)
print("S06 actual-source ownership fixture passed: cases="..cases.." checks="..checks)
