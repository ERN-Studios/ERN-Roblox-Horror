-- Validate real before capture readability/parity; no installation is inferred.
local fs,serde=require("@lune/fs"),require("@lune/serde")
local audit=require("./native_audit")
local dir="/private/tmp/lobby-polish-before-20261002"
local report=audit.audit({before=dir,after=dir,allowSameCapture=true,
 frozen="artifacts/lobby-polish-20261002/root/frozen-source-hashes.json",
 critical="artifacts/lobby-polish-20261002/root/baseline-critical.json",
 assetManifest="artifacts/lobby-polish-20261002/materials/candidate-manifest.json",
 uploads="artifacts/lobby-polish-20261002/materials/uploaded-assets.json",
 output="artifacts/lobby-polish-20261002/materials/native-before-preflight.json",
 expectedBeforeNativeSHA256="451e86549091122a992da3a8cabee5f38471dd20d5b77212dc6d77dad1433872"})
assert(report.wholeForestPreservedBeyondTaskScope and report.serverLobby.unchangedBeyondTaskScope,"Before forest did not compare to itself")
assert(report.nativeSourceInventory.before==224 and report.nativeSourceInventory.after==224,"Actual before native/editor Source count differs")
assert(not report.verified and not report.taskScopeVerified,"Before preflight must not claim installation")
for _,error in report.errors do
 assert(error:match("^Scoped existing Source pin differs:") or error:match("^Scoped installed hash differs:")
  or error:match("^Missing frozen task Source:"),"Unexpected before preflight error: "..error)
end
assert(#report.errors==9,"Expected exactly six absent-after-source/hash pins plus three not-installed new helpers")
local receipt={schema="lobby-polish-native-before-preflight-v1",passed=true,beforeNativeSHA256=report.beforeNativeSHA256,
 nativeSourceCount=224,allNativeSourcesMatchFullLiveSourceEditorCatalog=true,serverLobbyFingerprint=report.serverLobby.beforeCanonicalSHA256,
 exactBeforeForestSelfComparison=true,expectedUninstalledScopeErrors=report.errors,referencesChecked=report.nativeSourceInventory.referencesChecked,
 installedOrAfterVerified=false,studioWrites=false,inputBackupWrites=false}
fs.writeFile("artifacts/lobby-polish-20261002/materials/native-before-preflight-receipt.json",serde.encode("json",receipt,true).."\n")
print(serde.encode("json",receipt,true))
