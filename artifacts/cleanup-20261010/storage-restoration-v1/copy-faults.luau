-- Owned fake-instance contracts around exact current prepared source fragments.
-- Hashing uses Lune; exact CFrame/serializer/reflection/scene semantics are fakes.
local fs=require("@lune/fs")
local serde=require("@lune/serde")
local process=require("@lune/process")
local recipe=require("./actual_recipe")
local beforeRecipe=require("./actual_recipe_before")
local supplement=serde.decode("json",fs.readFile("restore-supplement.json"))
local raw=fs.readFile(process.args[1])
assert(#raw==2739764 and serde.hash("sha256",raw)==supplement.nativeSHA256,"Pinned native input changed")
local cases,checks,constructorChecks=0,0,0
local results={}
local function check(value,message) assert(value,message)checks+=1 end
local function copyTable(value)
 if type(value)~="table" then return value end
 local out={} for k,v in value do out[k]=copyTable(v) end return out
end
local function components(cf)return {cf:GetComponents()}end
local function equalComponents(a,b)
 if #a~=#b then return false end
 for i,v in a do if v~=b[i] then return false end end return true
end
local fakeCFrame={}
local fakeCFrameMT={__eq=function(a,b)return equalComponents(a.values,b.values)end}
function fakeCFrame.new(...)
 local values={...} assert(#values==12,"Exact fake CFrame needs twelve components")
 return setmetatable({values=values,__fakeCFrame=true,GetComponents=function(self)return table.unpack(self.values)end},fakeCFrameMT)
end
for _,spec in supplement.rows do
 local cf=fakeCFrame.new(table.unpack(spec.components))
 check(equalComponents(components(cf),spec.components),"Fake constructor changed exact supplemental components")
 constructorChecks+=12
end
local function scenario(kind)
 local originalNodes,allCopies,passes={}, {}, {}
 local setterCalls,originalSetterCalls,sourceWrites,destroyCalls,originalDestroyCalls=0,0,0,0,0
 local originalGuardCalls,deserializeCalls,serializeCalls=0,0,0
 local originalsSet={}
 local function node(name,class,path,parent,original,cf)
  local item={Name=name,ClassName=class,path=path,Parent=parent,children={},Source="return '"..path.."'",_cf=cf,destroyed=false}
  local mt={}
  function mt.__index(self,key)
   if key=="CFrame" then return rawget(self,"_cf") end
   return mt[key]
  end
  function mt.__newindex(self,key,value)
   if key=="CFrame" then
    setterCalls+=1
    if originalsSet[self] then originalSetterCalls+=1 error("Original setter forbidden") end
    if kind=="setter-before-error" and setterCalls==1 then error("failure before setter commit") end
    if kind=="setter-difference" and setterCalls==1 then
     local p=components(value)p[11]+=1e-12 value=fakeCFrame.new(table.unpack(p))
    end
    rawset(self,"_cf",value)
    if kind=="setter-commit-then-error" and setterCalls==1 then error("setter committed then lost reply") end
    if kind=="setter-commit-then-error-second" and setterCalls==5 then error("second setter committed then lost reply") end
   elseif key=="Source" then sourceWrites+=1 error("Source write forbidden")
   else rawset(self,key,value) end
  end
  function mt.IsA(self,want)return self.ClassName==want or want=="LuaSourceContainer" and self.ClassName=="ModuleScript" end
  function mt.IsDescendantOf(self,target)
   local at=self.Parent while at do if at==target then return true end at=at.Parent end return false
  end
  function mt.GetDescendants(self)
   local out={}
   local function walk(at) for _,child in at.children do if child.Parent==at then out[#out+1]=child walk(child) end end end
   walk(self)return out
  end
  function mt.GetFullName(self)return self.path end
  function mt.Destroy(self)
   destroyCalls+=1
   if originalsSet[self] then originalDestroyCalls+=1 error("Original Destroy forbidden") end
   if kind=="cleanup-first-root-error" and self.Name=="Root1" and self.pass==1 then error("first root cleanup failure") end
   if kind=="cleanup-second-root-error" and self.Name=="Root1" and self.pass==2 then error("second root cleanup failure") end
   self.destroyed=true
   for _,child in self.children do if child.Parent==self then child:Destroy() end end
  end
  setmetatable(item,mt)
  if original then originalsSet[item]=true originalNodes[#originalNodes+1]=item end
  return item
 end
 local game=node("game","DataModel","game",nil,true)
 local live=node("Live","Folder","game.Live",game,true)game.children={live}
 local roots,rows,expectedSources={}, {}, {}
 local function makeForest(original,pass)
  local forest={}
  for i=1,23 do
   local root=node("Root"..i,"Folder","Root"..i,nil,original)root.pass=pass
   forest[#forest+1]=root
   if not original then allCopies[#allCopies+1]=root end
   if i<=4 then
    local spec=supplement.rows[i]
    local values=copyTable(spec.components)
    if not original then values[11]+=1e-9 end
    local bone=node("Bone"..i,"Bone",spec.path,root,original,fakeCFrame.new(table.unpack(values)))
    root.children[#root.children+1]=bone
    if original then rows[bone]={path=bone.path,slots={{name="CFrame",read=true,value=bone.CFrame}}} end
   end
   if i>=5 and i<=16 then
    local script=node("Script"..i,"ModuleScript",root.path..".Script"..i,root,original)
    root.children[#root.children+1]=script
    if original then expectedSources[script.path]={class=script.ClassName,sourceSHA256=serde.hash("sha256",script.Source),bytes=#script.Source} end
   end
   -- Legitimate irrelevant duplicate full paths: strict target mapping must ignore them.
   local a=node("Keyframe","Folder",root.path..".Keyframe",root,original)
   local b=node("Keyframe","Folder",root.path..".Keyframe",root,original)
   root.children[#root.children+1]=a root.children[#root.children+1]=b
   if original then rows[root]={path=root.path,slots={}}rows[a]={path=a.path,slots={}}rows[b]={path=b.path,slots={}} end
  end
  return forest
 end
 roots=makeForest(true,0)
 local state={rootRefs={},scriptRefs={}}
 for _,root in roots do state.rootRefs[root]={}for _,child in root.children do if child.ClassName=="ModuleScript" then state.scriptRefs[child]={} end end end
 local originalFacts={}
 for _,n in originalNodes do originalFacts[n]={name=n.Name,class=n.ClassName,parent=n.Parent,source=n.Source,cf=n.CFrame,destroyed=n.destroyed} end
 local function originalUnchanged()
  for n,f in originalFacts do
   check(n.Name==f.name and n.ClassName==f.class and n.Parent==f.parent and n.Source==f.source and n.CFrame==f.cf and n.destroyed==f.destroyed,"Original fact changed")
  end
 end
 local function originals()
  originalGuardCalls+=1
  originalUnchanged()
  if kind=="guard-after-first-setter" and setterCalls==1 then error("original guard failed after borrowed operation") end
  if kind=="identity-before-setter" and setterCalls==0 and passes[1] and originalGuardCalls>=2 then
   passes[1][1].Parent=live
  end
 end
 local function snapshot(forest)
  local out={nodes={},rows={},roots={},references=10,referenceSHA256="refs-stable"}
  for _,root in forest do
   local digest={}
   local nodes={root}for _,n in root:GetDescendants() do nodes[#nodes+1]=n end
   for _,n in nodes do
    out.nodes[#out.nodes+1]=n out.rows[n]={path=n.path,parent=n.Parent}
    digest[#digest+1]={path=n.path,class=n.ClassName,source=if n.ClassName=="ModuleScript" then n.Source else nil,cf=if n.ClassName=="Bone" then components(n.CFrame) else nil}
   end
   out.roots[#out.roots+1]={name=root.Name,class=root.ClassName,children=#root.children,treeSHA256=serde.hash("sha256",serde.encode("json",digest))}
  end
  return out
 end
 local originalSnapshot=snapshot(roots)
 local function forestEqualsOriginal(forest)
  return serde.encode("json",snapshot(forest).roots)==serde.encode("json",originalSnapshot.roots)
 end
 local SER={}
 function SER.DeserializeInstancesAsync(_,bytes)
  deserializeCalls+=1
  if kind=="first-deserialize-error" and deserializeCalls==1 then error("first DS failure") end
  if kind=="second-deserialize-error" and deserializeCalls==2 then error("second DS failure") end
  check(buffer.tostring(bytes)==raw,"unexpected fake serializer archive input")
  local forest=makeForest(false,deserializeCalls)passes[deserializeCalls]=forest
  if kind=="original-alias-return" then table.insert(forest,1,roots[1]) end
  if kind=="duplicate-target" then
   local bone=forest[1].children[1]
   local extra=node("DuplicateTarget","Bone",bone.path,forest[1],false,bone.CFrame)
   forest[1].children[#forest[1].children+1]=extra
  end
  if kind=="foreign-child-second-adoption" and deserializeCalls==2 then
   local wrapper=forest[1]wrapper.children[#wrapper.children+1]=roots[1].children[1]
   -- Ownership sees a forged original-containing hierarchy; authoritative Parent is untouched.
   wrapper.GetDescendants=function(self)local t={}for _,child in self.children do t[#t+1]=child end return t end
  end
  return forest
 end
 function SER.SerializeInstancesAsync(_,forest)
  serializeCalls+=1
  if kind=="first-serialize-error" and serializeCalls==1 then error("first serialize failure") end
  if kind=="second-serialize-error" and serializeCalls==2 then error("second serialize failure") end
  return buffer.fromstring(if forestEqualsOriginal(forest) then raw else "incorrect fake forest")
 end
 local CFrame=fakeCFrame
 if kind=="constructor-difference" then CFrame={new=function(...)
  local values={...}values[11]+=1e-12 return fakeCFrame.new(table.unpack(values))
 end} end
 local localSupplement=copyTable(supplement)
 if kind=="historical-components-differ" then localSupplement.rows[1].components[11]+=1e-12 end
 local env={game=game,state=state,rows=rows,roots=roots,census={live},report={},supplement=localSupplement,CFrame=CFrame,
  typeof=function(value)
   if type(value)=="table" and value.ClassName then return "Instance" end
   if type(value)=="table" and value.__fakeCFrame then return "CFrame" end
   return typeof(value)
  end,
  check=check,originals=originals,SER=SER,context={nativeSHA256=supplement.nativeSHA256,nativeBytes=#raw},raw=buffer.fromstring(raw),
  originalSnapshot=originalSnapshot,expectedSources=expectedSources,forestSnapshot=snapshot,
  sha=function(value)return serde.hash("sha256",buffer.tostring(value))end,
  beforeCleanup=function()
   if kind=="foreign-root-before-cleanup" and passes[2] then passes[2][1].Parent=live end
  end}
 local result=(if kind=="lexical-V3-before" then beforeRecipe else recipe)(env)
 originalUnchanged()
 check(originalSetterCalls==0 and originalDestroyCalls==0 and sourceWrites==0,"Original or Source mutation attempted")
 local remaining=0 for _,root in allCopies do if not root.destroyed then remaining+=1 end end
 if kind=="success" then
  check(result.pass and result.createdRoots==46 and result.destroyedRoots==46 and result.testOwnedRootsRemaining==0,"paired recipe/cleanup failed: "..tostring(result.error))
  check(setterCalls==8 and result.testOwnedCFrameSetAttempts==8 and result.testOwnedCFrameWrites==8 and result.supplementPasses==2,"paired exact setters not exercised")
  check(result.secondSupplementedReopenPass and deserializeCalls==2 and serializeCalls==2,"second recipe not checked")
 else
  check(not result.pass,"fault silently passed: "..kind)
  local preserved=if kind=="cleanup-first-root-error" or kind=="cleanup-second-root-error" or kind=="foreign-root-before-cleanup" or kind=="identity-before-setter" or kind=="foreign-child-second-adoption" then 1 else 0
  check(remaining==preserved,"owned roots leaked/foreign root destroyed: "..kind.." remaining="..remaining)
  if kind=="setter-before-error" or kind=="setter-commit-then-error" then
   check(setterCalls==1 and result.testOwnedCFrameSetAttempts==1 and not result.testOwnedCFrameWrites,"failure attempt mistaken as confirmed write")
  elseif kind=="setter-commit-then-error-second" then
   check(setterCalls==5 and result.testOwnedCFrameSetAttempts==5 and result.testOwnedCFrameWrites==4,"second commit lost-reply count incorrect")
  elseif kind=="lexical-V3-before" then
   check(setterCalls==0 and result.createdRoots==23 and result.destroyedRoots==23,"lexical negative control did not fail before setters and clean copies")
   check(string.find(result.error,"exact four supplemental rows required",1,true)~=nil,"negative control failed for a different reason")
  end
 end
 cases+=1
 results[#results+1]={kind=kind,pass=true,recipeAccepted=result.pass,deserializeCalls=deserializeCalls,serializeCalls=serializeCalls,
  copySetterCalls=setterCalls,originalSetterCalls=originalSetterCalls,originalDestroyCalls=originalDestroyCalls,
  created=result.createdRoots,destroyed=result.destroyedRoots,preservedOwnedRoots=remaining}
end
for _,kind in {"lexical-V3-before","success","historical-components-differ","constructor-difference","setter-difference","setter-before-error",
 "setter-commit-then-error","setter-commit-then-error-second","guard-after-first-setter","identity-before-setter",
 "first-deserialize-error","second-deserialize-error","first-serialize-error","second-serialize-error",
 "original-alias-return","duplicate-target","foreign-child-second-adoption","cleanup-first-root-error",
 "cleanup-second-root-error","foreign-root-before-cleanup"} do scenario(kind) end
print(serde.encode("json",{cases=cases,checks=checks,fakeExactConstructorComponents=constructorChecks,
 nativeCalls=0,robloxEngineConstructorCertified=false,results=results}))
