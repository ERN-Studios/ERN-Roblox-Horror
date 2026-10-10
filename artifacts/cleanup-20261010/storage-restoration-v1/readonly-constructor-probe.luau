-- Four current held-original Bone reads plus pure CFrame construction only.
-- No Instances, setters, Source/editor operations, shared-state writes or modeswitch.
local HS=game:GetService("HttpService")
local RS=game:GetService("RunService")
local KEY="__MongoTVStorageCleanup20261009"
local expected=HS:JSONDecode([====[{
  "schema": "s06-exact-four-bone-cframe-supplement-v1",
  "factsSHA256": "b6b86b7871bab31d8fdebd9afa5cf3367426fad4e6a5eaef9038e4e8b1434f33",
  "nativeSHA256": "139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca",
  "rows": [
    {
      "path": "TEMP_PipeEntityValidation.PipeEntity_LocalPreview.RootPart.Root.Hips.LeftUpperLeg",
      "class": "Bone",
      "property": "CFrame",
      "components": [
        0.18999947607517242,
        -8.940696716308594e-08,
        4.7707207073699465e-09,
        0.9439874887466431,
        0.23667016625404358,
        0.22994564473628998,
        0.22994647920131683,
        -0.9715901017189026,
        0.05601239576935768,
        0.23666934669017792,
        1.8891469721893372e-07,
        -0.9715903997421265
      ]
    },
    {
      "path": "TEMP_PipeEntityValidation.PipeEntity_LocalPreview.RootPart.Root.Hips.RightUpperLeg",
      "class": "Bone",
      "property": "CFrame",
      "components": [
        -0.18999947607517242,
        -8.940696716308594e-08,
        4.770805972498238e-09,
        0.9439874887466431,
        -0.23667018115520477,
        -0.22994564473628998,
        -0.22994649410247803,
        -0.9715901017189026,
        0.05601239949464798,
        -0.23666934669017792,
        1.889619767325712e-07,
        -0.9715903997421265
      ]
    },
    {
      "path": "TrelloPoolSlideReleaseBackup_20260910.Level 2 Pool Slide Template.RootPart.Root.Hips.LeftUpperLeg",
      "class": "Bone",
      "property": "CFrame",
      "components": [
        0.7599979043006897,
        -3.5762786865234375e-07,
        1.9082882829479786e-08,
        0.9439874887466431,
        0.23667016625404358,
        0.22994564473628998,
        0.22994647920131683,
        -0.9715901017189026,
        0.05601239576935768,
        0.23666934669017792,
        1.8891469721893372e-07,
        -0.9715903997421265
      ]
    },
    {
      "path": "TrelloPoolSlideReleaseBackup_20260910.Level 2 Pool Slide Template.RootPart.Root.Hips.RightUpperLeg",
      "class": "Bone",
      "property": "CFrame",
      "components": [
        -0.7599979043006897,
        -3.5762786865234375e-07,
        1.908322388999295e-08,
        0.9439874887466431,
        -0.23667018115520477,
        -0.22994564473628998,
        -0.22994649410247803,
        -0.9715901017189026,
        0.05601239949464798,
        -0.23666934669017792,
        1.889619767325712e-07,
        -0.9715903997421265
      ]
    }
  ],
  "normalizationApplied": false
}
]====])
local state=shared[KEY]
local checks=0
local captured={}
local report={schema="s06-exact-readonly-native-constructor-v1",pass=false,rows={},nativeInstanceCreations=0,
 copySetterWrites=0,originalSetterWrites=0,sourceWrites=0,originalParentWrites=0,sharedStateWrites=0,
 modeSwitches=0,restorationCertified=false,normalizationApplied=false}
local function check(value,message)assert(value,message)checks+=1 end
local function count(t)local n=0 for _ in t do n+=1 end return n end
local function components(cf)return {cf:GetComponents()}end
local function equal(a,b)if #a~=#b then return false end for i,v in a do if v~=b[i] then return false end end return true end
local function guard()
 check(game.PlaceId==131311258779917 and game.GameId==10559217407 and not RS:IsRunning(),"correct place/Edit required")
 check(shared[KEY]==state and type(state)=="table" and type(state.rootRefs)=="table" and type(state.scriptRefs)=="table"
  and not state.probeLease and not state.portLease and state.storagePort==nil,"current exact original ledger unavailable/in use")
 check(count(state.rootRefs)==73 and count(state.scriptRefs)==222,"original ledger counts changed")
 for _,row in captured do
  check(row.root.Parent==nil and row.root.Name==row.rootName and row.root.ClassName=="Folder" and state.rootRefs[row.root]~=nil,"held root changed")
  check(row.bone.Parent==row.parent and row.bone:GetFullName()==row.path and row.bone:IsA("Bone")
   and row.bone.CFrame==row.before and equal(components(row.bone.CFrame),row.components),"original Bone changed during readonly math")
 end
end
local ok,why=xpcall(function()
 guard()
 check(expected.schema=="s06-exact-four-bone-cframe-supplement-v1" and #expected.rows==4 and expected.normalizationApplied==false,"wrong pinned supplement")
 for _,spec in expected.rows do
  local steps=string.split(spec.path,".")
  local root
  for candidate,record in state.rootRefs do if candidate.Name==steps[1] then
   check(root==nil and record.name==steps[1] and record.class=="Folder","ambiguous/mismatched held root") root=candidate
  end end
  check(root~=nil and root.Parent==nil and root.ClassName=="Folder","exact archived held root not present")
  local at=root
  local classes={"Folder","Model","Part","Bone","Bone","Bone"}
  check(#steps==#classes,"unexpected exact Bone path")
  for index=2,#steps do
   local nextNode
   for _,child in at:GetChildren() do if child.Name==steps[index] then check(nextNode==nil,"ambiguous Bone path") nextNode=child end end
   check(nextNode and nextNode.ClassName==classes[index],"held Bone hierarchy/class changed") at=nextNode
  end
  local before=at.CFrame
  local beforeComponents=components(before)
  captured[#captured+1]={root=root,rootName=steps[1],bone=at,parent=at.Parent,path=spec.path,before=before,components=beforeComponents}
  check(spec.class=="Bone" and spec.property=="CFrame" and #spec.components==12,"wrong exact property recipe")
  check(equal(beforeComponents,spec.components),"fresh held-original CFrame differs from historical full-facts")
  local constructed=CFrame.new(table.unpack(spec.components))
  local exact=constructed==before and equal(components(constructed),spec.components)
  report.rows[#report.rows+1]={path=spec.path,identity=at:GetDebugId(),originalMatchesHistorical=true,
   exactConstructor=exact,componentsChecked=12}
  check(exact,"Roblox CFrame constructor changed exact components")
  guard()
 end
end,debug.traceback)
local final,reason=pcall(guard)
if not final then ok=false why=tostring(why).."\nfinal readonly original guard: "..tostring(reason) end
report.pass=ok report.error=if ok then nil else tostring(why)
report.originalsUnchanged=final report.checks=checks report.capturedAtUtc=DateTime.now():ToIsoDate()
return HS:JSONEncode(report)
