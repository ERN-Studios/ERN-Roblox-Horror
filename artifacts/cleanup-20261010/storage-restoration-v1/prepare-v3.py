"""Prepare fresh-baseline guards around the immutable copy-only V2 recipe."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
OLD = ROOT / "artifacts/cleanup-20261010/storage-next-v1"
sha = lambda raw: hashlib.sha256(raw).hexdigest()
base = (OLD / "restoration-supplement-probe-v2.luau").read_bytes()
assert (len(base), sha(base)) == (27000, "c9ae7a5f71fd836d8722eb77786c7c1a6ded062c0f8dbfd53387982a022a66ab")
source = base.decode()

def replace(old, new):
    global source
    assert source.count(old) == 1, "Exact prepared source boundary changed"
    source = source.replace(old, new)

replace('local KEY="__MongoTVExternalStorageSupplement20261010V2"', 'local KEY="__MongoTVExternalStorageSupplement20261010V3"')
replace('local SCHEMA="external-held-storage-native-restoration-supplement-v2"', 'local SCHEMA="external-held-storage-native-restoration-supplement-v3"')
replace(' check(context.schema==SCHEMA and #context.roots==23 and #context.heldSources==12,"wrong archive context")', ''' check(context.schema==SCHEMA and #context.roots==23 and #context.heldSources==12,"wrong archive context")
 check(context.liveBaselineSchema=="storage-restoration-live-baseline-v1" and context.expectedLiveSources==213
  and context.expectedLedgerRootRefs==73 and context.expectedLedgerScriptRefs==222,"wrong exact baseline/ledger counts")
 local function countKeys(t) local n=0 for _ in t do n+=1 end return n end
 check(countKeys(state.rootRefs)==context.expectedLedgerRootRefs and countKeys(state.scriptRefs)==context.expectedLedgerScriptRefs,"historical original ledger changed")
 check(type(context.sourcePins)=="table" and #context.sourcePins==context.expectedLiveSources,"missing fresh all-source pins")
 local sourcePins={}
 for _,pin in context.sourcePins do
  check(type(pin.path)=="string" and not sourcePins[pin.path] and type(pin.identity)=="string"
   and type(pin.parentIdentity)=="string" and type(pin.metadataSHA256)=="string","invalid/duplicate source pin")
  sourcePins[pin.path]=pin
 end
 check(#SS:GetChildren()==context.expectedLiveRoots and #game:GetDescendants()==context.expectedLiveDescendants,"fresh live root/census baseline changed")''')
replace('  if s:IsA("LuaSourceContainer") then liveSources[s]=scriptRow(s) watchNode(s) end', '''  if s:IsA("LuaSourceContainer") then
   local row=scriptRow(s) local pin=assert(sourcePins[row.path],"unexpected fresh original Source")
   check(row.class==pin.class and s:GetDebugId()==pin.identity and row.parent:GetDebugId()==pin.parentIdentity
    and sha(buffer.fromstring(row.source))==pin.sourceSHA256 and #row.source==pin.bytes
    and sha(buffer.fromstring(canonical({properties=row.properties,attributes=row.attributes,tags=row.tags})))==pin.metadataSHA256,
    "fresh all-source identity/parent/Source/editor/metadata baseline changed")
   liveSources[s]=row watchNode(s)
  end''')
replace(' local heldCount=0 for _ in heldSources do heldCount+=1 end check(heldCount==12,"held Source count changed")', ''' local liveSourceCount=0 for _ in liveSources do liveSourceCount+=1 end
 check(liveSourceCount==context.expectedLiveSources,"fresh all-source count changed")
 report.freshSourcePinsValidated=liveSourceCount report.liveBaselineSHA256=context.liveBaselineSHA256
 local heldCount=0 for _ in heldSources do heldCount+=1 end check(heldCount==12,"held Source count changed")''')
replace('report.originalSourcesUnchanged=valid and final and sourceBaselineComplete', '''report.originalSourcesUnchanged=valid and final and sourceBaselineComplete
report.originalSourcePinsUnchanged=report.originalSourcesUnchanged and report.freshSourcePinsValidated==213
report.normalizationApplied=false''')
replace('if shared[KEY]==lease then shared[KEY]=nil end -- Never clear or overwrite held original state.', '''report.leaseReleased=false
if shared[KEY]==lease then shared[KEY]=nil report.leaseReleased=true end -- Never clear or overwrite held original state.
if not report.leaseReleased then report.pass=false report.error=tostring(report.error).."\\nowned lease replaced; preserve foreign state" end''')
assert source.count("copy.CFrame=wanted") == 1 and "original.CFrame=" not in source
candidate = source.encode()
with (OUT / "restoration-probe-v3.luau").open("xb") as stream:
    stream.write(candidate)
supplement = (OLD / "restore-supplement.json").read_bytes()
assert sha(supplement) == "0c83647db8c7a2c299834481c0d3b1032a97ca2aafe9aacf8091f2523392b7a1"
with (OUT / "restore-supplement.json").open("xb") as stream:
    stream.write(supplement)
receipt = {"schema": "s06-exact-restoration-preparation-v3", "nativeCalls": 0, "nativeWrites": 0,
    "candidateExecuted": False, "restorationCertified": False, "normalizationApplied": False,
    "base": {"path": str((OLD / "restoration-supplement-probe-v2.luau").relative_to(ROOT)), "bytes": len(base), "sha256": sha(base)},
    "candidate": {"path": "restoration-probe-v3.luau", "bytes": len(candidate), "sha256": sha(candidate)},
    "requiredFreshSourceCount": 213, "expectedLedgerRootRefs": 73, "expectedLedgerScriptRefs": 222,
    "scope": "Future Root-native request only; current native baseline is required independently and historical original archive must match byte-exact before deserialization. No epsilon."}
with (OUT / "preparation-v3.json").open("xb") as stream:
    stream.write((json.dumps(receipt, indent=2) + "\n").encode())
print(json.dumps({"candidateBytes": len(candidate), "candidateSHA256": sha(candidate), "nativeCalls": 0}))
