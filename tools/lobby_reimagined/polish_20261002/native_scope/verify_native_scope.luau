-- Local CLI. Inputs are immutable; only the requested JSON report is written.
local process,serde=require("@lune/process"),require("@lune/serde")
local audit=require("./native_audit")
local args=process.args
local report=audit.audit({before=assert(args[1],"before directory"),after=assert(args[2],"after directory"),
 frozen=assert(args[3],"frozen-source-hashes.json"),critical=assert(args[4],"baseline-critical.json"),
 assetManifest=assert(args[5],"material candidate-manifest.json"),uploads=assert(args[6],"uploaded-assets.json"),
 output=assert(args[7],"output report JSON"),
 expectedBeforeNativeSHA256="451e86549091122a992da3a8cabee5f38471dd20d5b77212dc6d77dad1433872"})
print(serde.encode("json",{verified=report.verified,taskScopeVerified=report.taskScopeVerified,
 wholeForestPreservedBeyondTaskScope=report.wholeForestPreservedBeyondTaskScope,serverLobbyUnchanged=report.serverLobby and report.serverLobby.unchangedBeyondTaskScope,
 concurrentSources=#report.unclassifiedConcurrentSourceDeltas,concurrentNativeRows=#report.unclassifiedConcurrentNativeDeltas,errors=report.errors,output=args[7]},true))
assert(report.verified,"Native audit has unresolved differences. Review the report and preserve current Studio; never restore the earlier forest.")
