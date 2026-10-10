-- Actual transaction core fixture. Fake scheduling/Parent boundaries; never native certification.
local serde=require("@lune/serde")
local T=require("./actual-core")
local checks,results=0,{}
local function check(v,why) checks+=1 assert(v,why) end
local function run(kind,at)
 local storage,foreign={},{}
 local entries={}
 for i=1,5 do entries[i]={name="retired"..i,parent=storage,index=i,originalName="retired"..i,invoked=false} end
 local eligible,restoreEligible=true,true
 local setters,absent,beforeDetach,beforeRestore=0,0,0,0
 local failed=false
 local function once(phase,e)
  return not failed and e.index==at and kind==phase
 end
 local hooks={
  parent=function(e)return e.parent end,
  originalParent=function()return storage end,
  preflight=function()if kind=="preflight" then error("preflight")end end,
  detachEligibility=function(e)
   check(eligible,"fresh mode/lease/Source eligibility")
   check(e.name==e.originalName,"identity/name")
   check(e.parent==storage,"exact original Parent")
  end,
  rollbackEligibility=function(e)
   check(restoreEligible,"scoped inverse mode/lease eligibility")
   check(e.invoked,"no inverse without actual setter entry")
   check(e.name==e.originalName,"identity/name")
   check(e.parent==storage or e.parent==nil,"foreign Parent")
  end,
  beforeWrite=function(e,phase)
   if phase=="detach" then
    beforeDetach+=1
    if once("foreign-nil-hook-throw",e) then failed=true e.parent=nil error("foreign nil before invocation") end
    if once("foreign-nil-hook-return",e) then failed=true e.parent=nil end
    if once("foreign-parent-hook",e) then failed=true e.parent=foreign end
    if once("foreign-name-hook",e) then failed=true e.name="foreign name" end
   else
    beforeRestore+=1
    if once("inverse-foreign-parent-hook",e) then failed=true e.parent=foreign end
    if once("inverse-foreign-name-hook",e) then failed=true e.name="foreign name" end
    if once("inverse-foreign-nil-hook-throw",e) then failed=true error("inverse prewrite hook") end
   end
  end,
  setParent=function(e,parent)
   setters+=1 e.invoked=true
   local phase=if parent==nil then "detach" else "restore"
   if once(phase.."-before-error",e) then failed=true error("setter before commit") end
   e.parent=parent
   if once(phase.."-commit-error",e) then failed=true error("setter commit then error") end
  end,
  afterWrite=function(e,phase)
   if phase=="detach" then
    if once("after-detach-error",e) then failed=true error("after detach") end
    if once("mode-after-detach",e) or once("lease-after-detach",e) or once("source-after-detach",e) then
     failed=true eligible=false
     if kind~="source-after-detach" then restoreEligible=false end
     error("concurrent authority change")
    end
   elseif once("after-restore-error",e) then failed=true error("after restore") end
  end,
  absentPort=function()
   absent+=1
   for _,e in entries do check(e.parent==nil,"all five absent") end
   if kind=="absent-error" then error("actual selector port failure") end
  end,
  finalGuard=function()
   check(eligible,"final lease/mode/source")
   for _,e in entries do check(e.parent==storage and e.name==e.originalName,"final exact originals") end
  end,
 }
 local report,pending=T.run(entries,hooks)
 check(report.detachAttempts+report.restoreAttempts==setters,"attempt counters are actual setter invocations")
 local pendingCount=0 for _ in pending do pendingCount+=1 end
 check(pendingCount==#report.pending,"pending names match exact retained entries")
 if kind=="pass" then
  check(report.passed and setters==10 and absent==1 and pendingCount==0,"normal same-original transaction")
 else
  check(not report.passed,"Every injected fault must revoke pass")
 end
 if string.sub(kind,1,8)=="foreign-" then
  check(report.detachAttempts==at-1,"prewrite foreign change does not gain inverse ownership")
  check(not entries[at].invoked,"foreign root never reaches setter")
  check(pending[entries[at]]==nil,"foreign nil/Parent/name not adopted")
  for i=1,at-1 do check(entries[i].parent==storage,"earlier owned roots restored independently") end
 elseif string.sub(kind,1,8)=="inverse-" then
  check(report.detachAttempts==5,"inverse fault happens after all own detaches")
  check(pending[entries[at]]==true,"foreign inverse state retained")
  for i=1,5 do if i~=at then check(entries[i].parent==storage,"other inverse attempts continue") end end
 elseif kind=="restore-before-error" then
  check(pending[entries[at]]==true and entries[at].parent==nil,"failed inverse preserved for recovery")
  check(report.restoreAttempts==5,"independent remaining inverse setters continue")
 elseif kind=="restore-commit-error" then
  check(pendingCount==0 and #report.setterErrors==1 and #report.rollbackErrors==1,"commit-then-error retained even with restored readback")
 elseif kind=="source-after-detach" then
  check(pendingCount==0 and report.restoreAttempts==at,"unrelated Source drift revokes pass after scoped own-state recovery")
 elseif string.find(kind,"after-detach",1,true) and kind~="after-detach-error" then
  check(pendingCount==at,"concurrent authority change prevents inverse writes")
  check(report.restoreAttempts==0,"no restore setter across lost lease/mode/Source guard")
 else
  check(pendingCount==0,"owned originals recovered when guard remains eligible")
 end
 results[#results+1]={name=kind,index=at,passed=true,checks=checks,actualCorePass=report.passed,
  setterAttempts=setters,detaches=report.detachAttempts,inverses=report.restoreAttempts,pending=pendingCount,
  absentPortCalls=absent,beforeDetach=beforeDetach,beforeRestore=beforeRestore}
end
run("pass",1)
run("preflight",1)
run("absent-error",1)
for _,kind in {"detach-before-error","detach-commit-error","after-detach-error","restore-before-error",
 "restore-commit-error","after-restore-error","foreign-nil-hook-throw","foreign-nil-hook-return",
 "foreign-parent-hook","foreign-name-hook","inverse-foreign-parent-hook","inverse-foreign-name-hook",
 "inverse-foreign-nil-hook-throw","mode-after-detach","lease-after-detach","source-after-detach"} do
 for _,at in {1,3,5} do run(kind,at) end
end
print(serde.encode("json",{passed=true,cases=#results,checks=checks,results=results}))
