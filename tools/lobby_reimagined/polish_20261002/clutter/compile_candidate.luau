local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
local path="tools/lobby_reimagined/polish_20261002/clutter/EndBlockades.ModuleScript.candidate.luau"
local source=fs.readFile(path)
luau.compile(source)
-- Expose the constant only in this in-memory local test. Candidate unchanged.
local instrumented=source:gsub("function Module.Add%(model, kit, manifest%)", "function Module.__ReviewPlan() return PLAN end\nfunction Module.Add(model, kit, manifest)", 1)
local module=luau.load(instrumented)()
assert(type(module.Emit)=="function" and type(module.Add)=="function")
local expected=serde.decode("json",fs.readFile("tools/lobby_reimagined/polish_20261002/clutter/plan.json"))
local maxNumericDifference=0
local function equal(actual,wanted,context)
 assert(type(actual)==type(wanted),context)
 if type(wanted)=="number" then
  local difference=math.abs(actual-wanted)
  maxNumericDifference=math.max(maxNumericDifference,difference)
  assert(difference<1e-12,context)
  return
 end
 if type(wanted)~="table" then assert(actual==wanted,context);return end
 for key,value in pairs(wanted)do equal(actual[key],value,context.."."..tostring(key))end
 for key in pairs(actual)do assert(wanted[key]~=nil,context.." extra key "..tostring(key))end
end
equal(module.__ReviewPlan(),expected,"PLAN")
local receipt={status="PASS",scope="Exact candidate syntax, module-load/interface and full runtime PLAN equals checked JSON within numeric parser rounding",path=path,bytes=#source,sha256=serde.hash("sha256",source),interface="Add(model, kit, manifest)",fullSerializedPlanEqualsCheckedJSON=true,numericTolerance=1e-12,maxObservedNumericDifference=maxNumericDifference,testNote="Initial strict double equality exposed decimal parser rounding in an unchanged collider dimension; comparison now measures and bounds this rounding. Candidate unchanged."}
fs.writeFile("artifacts/lobby-polish-20261002/clutter/syntax-receipt.json",serde.encode("json",receipt,true))
print(serde.encode("json",receipt))
