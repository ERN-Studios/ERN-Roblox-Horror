-- Trial-only same-original Parent transaction. No permanent removal branch.
-- Every boundary is supplied by the exact native caller; fixtures execute this code.
local T = {}
function T.run(entries, hooks)
 local attempted, report = {}, {passed=false,detachAttempts=0,restoreAttempts=0,
  detachReadbacks=0,restoreReadbacks=0,rollbackErrors={},pending={},setterErrors={}}
 local function restore()
  for _,entry in entries do
   if attempted[entry] then
    local ok, why = pcall(function()
     hooks.rollbackEligibility(entry)
     local parent = hooks.parent(entry)
     if parent == hooks.originalParent(entry) then
      attempted[entry]=nil
      return
     end
     assert(parent==nil,"Foreign Parent preserved")
     hooks.beforeWrite(entry,"restore")
     hooks.rollbackEligibility(entry)
     assert(hooks.parent(entry)==nil,"Immediate inverse Parent CAS changed")
     report.restoreAttempts+=1
     local wrote, writeError=pcall(hooks.setParent,entry,hooks.originalParent(entry))
     local observed=hooks.parent(entry)
     if observed==hooks.originalParent(entry) then
      report.restoreReadbacks+=1
      attempted[entry]=nil
     end
     if not wrote then
      report.setterErrors[#report.setterErrors+1]={name=entry.name,phase="restore",error=tostring(writeError),readbackRestored=observed==hooks.originalParent(entry)}
      error(writeError)
     end
     assert(observed==hooks.originalParent(entry),"Restore Parent readback differs")
     hooks.afterWrite(entry,"restore")
    end)
    if not ok then report.rollbackErrors[#report.rollbackErrors+1]={name=entry.name,error=tostring(why)} end
   end
  end
 end
 local ok,why=xpcall(function()
  hooks.preflight()
  for _,entry in entries do
   hooks.detachEligibility(entry)
   assert(hooks.parent(entry)==hooks.originalParent(entry),"Original Parent CAS changed")
   hooks.beforeWrite(entry,"detach")
   hooks.detachEligibility(entry)
   assert(hooks.parent(entry)==hooks.originalParent(entry),"Immediate original Parent CAS changed")
   attempted[entry]=true -- Only the immediately following setter gains inverse eligibility.
   report.detachAttempts+=1
   local wrote,writeError=pcall(hooks.setParent,entry,nil)
   local observed=hooks.parent(entry)
   if observed==nil then report.detachReadbacks+=1 end
   if not wrote then
    report.setterErrors[#report.setterErrors+1]={name=entry.name,phase="detach",error=tostring(writeError),readbackDetached=observed==nil}
    error(writeError)
   end
   assert(observed==nil,"Detach Parent readback differs")
   hooks.afterWrite(entry,"detach")
  end
  hooks.absentPort()
 end,debug.traceback)
 restore() -- Independent per-root inverse even when preflight/port/setter throws.
 for _,entry in entries do
  if attempted[entry] then report.pending[#report.pending+1]=entry.name end
 end
 local finalOk,finalWhy=pcall(hooks.finalGuard)
 report.primaryError=if ok then nil else tostring(why)
 report.finalGuardError=if finalOk then nil else tostring(finalWhy)
 report.passed=ok and finalOk and #report.rollbackErrors==0 and #report.pending==0 and #report.setterErrors==0
 return report,attempted
end
