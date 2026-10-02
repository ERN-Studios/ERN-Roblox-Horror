local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local paths = {
	"tools/lobby_reimagined/polish_20261002/bays/LobbyPolishBays.ModuleScript.candidate.luau",
	"tools/lobby_reimagined/polish_20261002/bays/LobbyReimaginedQueueController.LocalScript.candidate.luau",
	"tools/lobby_reimagined/polish_20261002/bays/fix_render_fidelity.EditCAS.luau",
}
local receipt = {status="PASS", scope="Local Luau compilation and helper module/interface/serialized prop-plan check only", files={}}
for _, path in ipairs(paths) do
	local source = fs.readFile(path)
	luau.compile(source)
	table.insert(receipt.files,{path=path,bytes=#source,sha256=serde.hash("sha256",source),compiled=true})
end
local source = fs.readFile(paths[1])
local reviewed = source:gsub("function Module.Add%(model, kit, manifest%)", "function Module.__ReviewPlan() return PROPS end\nfunction Module.Add(model, kit, manifest)", 1)
local helper = luau.load(reviewed)()
assert(type(helper.Add)=="function", "Missing helper Add(model,kit,manifest)")
local expected = serde.decode("json",fs.readFile("tools/lobby_reimagined/polish_20261002/bays/props-plan.json"))
local maxNumericDifference = 0
local function equal(actual,wanted,context)
	assert(type(actual)==type(wanted),context)
	if type(wanted)=="number" then
		local difference=math.abs(actual-wanted)
		maxNumericDifference=math.max(maxNumericDifference,difference)
		assert(difference<1e-12,context)
	elseif type(wanted)=="table" then
		for key,value in pairs(wanted) do equal(actual[key],value,context.."."..tostring(key)) end
		for key in pairs(actual) do assert(wanted[key]~=nil,context.." unexpected key "..tostring(key)) end
	else assert(actual==wanted,context) end
end
equal(helper.__ReviewPlan(),expected,"PROPS")
receipt.interface = "Add(model,kit,manifest) -> owned Folder with AddedInstancedTriangles"
receipt.serializedPropsMatchGeometryReceipt = true
receipt.maxObservedNumericDifference = maxNumericDifference
fs.writeFile("artifacts/lobby-polish-20261002/bays/syntax-receipt.json",serde.encode("json",receipt,true))
print(serde.encode("json",receipt))
