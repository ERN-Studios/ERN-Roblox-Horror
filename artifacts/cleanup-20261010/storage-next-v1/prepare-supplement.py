"""Prepare a reviewed future native probe; never connects to Studio."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
FACTS = ROOT / "artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1/facts.json"
BEFORE = ROOT / "tools/cleanup_20261009/external_storage_archive_reopen.luau"
FACTS_SHA = "b6b86b7871bab31d8fdebd9afa5cf3367426fad4e6a5eaef9038e4e8b1434f33"
NATIVE_SHA = "139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca"
PATHS = [
    "TEMP_PipeEntityValidation.PipeEntity_LocalPreview.RootPart.Root.Hips.LeftUpperLeg",
    "TEMP_PipeEntityValidation.PipeEntity_LocalPreview.RootPart.Root.Hips.RightUpperLeg",
    "TrelloPoolSlideReleaseBackup_20260910.Level 2 Pool Slide Template.RootPart.Root.Hips.LeftUpperLeg",
    "TrelloPoolSlideReleaseBackup_20260910.Level 2 Pool Slide Template.RootPart.Root.Hips.RightUpperLeg",
]

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def write_new(name, raw):
    with (OUT / name).open("xb") as stream:
        assert stream.write(raw) == len(raw)

facts_raw = FACTS.read_bytes()
assert len(facts_raw) == 41912358 and sha(facts_raw) == FACTS_SHA
facts = json.loads(facts_raw)
selected = {}
for row in facts["nodes"]:
    if row["path"] not in PATHS:
        continue
    assert row["path"] not in selected and row["class"] == "Bone"
    value = row["properties"]["CFrame"]
    assert value["type"] == "CFrame" and len(value["value"]) == 12
    selected[row["path"]] = {"path": row["path"], "class": "Bone", "property": "CFrame", "components": value["value"]}
assert set(selected) == set(PATHS)
supplement = {"schema": "s06-exact-four-bone-cframe-supplement-v1", "factsSHA256": FACTS_SHA,
    "nativeSHA256": NATIVE_SHA, "rows": [selected[path] for path in PATHS], "normalizationApplied": False}
supplement_raw = (json.dumps(supplement, indent=2) + "\n").encode()
source_raw = BEFORE.read_bytes()
source = source_raw.decode("utf-8")

def replace(before, after):
    global source
    assert source.count(before) == 1, "Probe insertion boundary changed"
    source = source.replace(before, after)

replace('local BASE="http://127.0.0.1:18915"', 'local BASE="http://127.0.0.1:18916"')
replace('local KEY="__MongoTVExternalStorageReopen20261009"', 'local KEY="__MongoTVExternalStorageSupplement20261010"')
replace('local SCHEMA="external-held-storage-native-reopen-v1"', 'local SCHEMA="external-held-storage-native-restoration-supplement-v1"')
replace('local context,originalSnapshot', 'local context,originalSnapshot,supplement')
replace(' context=HS:JSONDecode(HS:GetAsync(BASE.."/context",true))', ''' context=HS:JSONDecode(HS:GetAsync(BASE.."/context",true))
 local supplementRaw=HS:GetAsync(BASE.."/supplement",true)
 check(sha(buffer.fromstring(supplementRaw))=="''' + sha(supplement_raw) + '''","exact supplemental facts changed")
 supplement=HS:JSONDecode(supplementRaw)
 check(supplement.schema=="s06-exact-four-bone-cframe-supplement-v1" and supplement.factsSHA256=="''' + FACTS_SHA + '''"
  and supplement.nativeSHA256=="''' + NATIVE_SHA + '''" and supplement.normalizationApplied==false,"wrong pinned supplemental archive/facts")
 check(context.nativeSHA256==supplement.nativeSHA256,"context differs from pinned historical archive")''')

helper = '''-- RESTORE SUPPLEMENT CONTRACT BEGIN: extract this exact helper offline.
local function restoreFourCFrames(snapshot,label)
 check(type(supplement)=="table" and #supplement.rows==4,"exact four supplemental rows required")
 local originalsByPath,copiesByPath={},{}
 for original,row in rows do
  check(not originalsByPath[row.path],"ambiguous original path") originalsByPath[row.path]=original
 end
 for copy,row in snapshot.rows do
  check(not copiesByPath[row.path],"ambiguous owned-copy path") copiesByPath[row.path]=copy
 end
 local writes=0
 for _,spec in supplement.rows do
  check(spec.class=="Bone" and spec.property=="CFrame" and type(spec.components)=="table" and #spec.components==12,"wrong supplemental class/property/data")
  local original=assert(originalsByPath[spec.path],"supplement original unavailable")
  local copy=assert(copiesByPath[spec.path],"supplement owned copy unavailable")
  check(original~=copy and knownOriginals[original] and not knownOriginals[copy] and copyOwnedNodes[copy]
   and copy:IsA("Bone") and not copy:IsDescendantOf(game),"supplement cannot write original/foreign/live identity")
  local slot
  for _,candidate in rows[original].slots do if candidate.name=="CFrame" then check(not slot,"duplicate original CFrame slot") slot=candidate end end
  check(slot and slot.read and typeof(slot.value)=="CFrame","original native CFrame not readable")
  for _,number in spec.components do check(type(number)=="number" and number==number and math.abs(number)<math.huge,"invalid supplemental number") end
  check(canonical({slot.value:GetComponents()})==canonical(spec.components),"fresh held original differs from exact historical facts")
  local wanted=CFrame.new(table.unpack(spec.components))
  -- Require a portable JSON recipe; a constructor/setter normalization is a
  -- failure, never an epsilon comparison or automatic acceptance.
  check(wanted==slot.value and canonical({wanted:GetComponents()})==canonical(spec.components),"CFrame constructor changed exact components")
  originals()
  check(copyOwnedNodes[copy] and not knownOriginals[copy] and copy:IsA("Bone") and not copy:IsDescendantOf(game)
   and copy.Parent==snapshot.rows[copy].parent,"supplement identity escaped before setter")
  copy.CFrame=wanted
  writes+=1 report.testOwnedCFrameWrites=(report.testOwnedCFrameWrites or 0)+1
  check(copy.CFrame==wanted and canonical({copy.CFrame:GetComponents()})==canonical(spec.components),"Bone setter changed exact components")
  originals()
 end
 check(writes==4,"exact four owned writes required")
 report.supplementPasses=(report.supplementPasses or 0)+1
 report.lastSupplementPhase=label
end
-- RESTORE SUPPLEMENT CONTRACT END.
'''
replace('local function postParts(raw)', helper + 'local function postParts(raw)')
replace(' local snapshot=forestSnapshot(copies,false)', ''' local snapshot=forestSnapshot(copies,false)
 report.unrestoredReadableRootTrees=snapshot.roots
 report.unrestoredReadableDataPass=canonical(snapshot.roots)==canonical(originalSnapshot.roots)
 check(not report.unrestoredReadableDataPass,"expected historical raw-reopen mismatch was not reproduced; re-review instead of writing")
 restoreFourCFrames(snapshot,"first-reopen")
 snapshot=forestSnapshot(copies,false)
 originals()''')
replace(' local transfer=postParts(buffer.tostring(roundtrip))', ''' check(sha(roundtrip)==context.nativeSHA256 and buffer.len(roundtrip)==context.nativeBytes,"restored-copy binary is not byte-exact original")
 local copies2=SER:DeserializeInstancesAsync(roundtrip)
 report.createdRoots+=#copies2
 local secondAdoptionErrors=adoptCopies(copies2)
 report.secondCopyAdoptionErrors=secondAdoptionErrors report.adoptedRoots=#copyOwnedRoots
 originals()
 check(#secondAdoptionErrors==0 and #copies2==23,"second reopen adoption/count mismatch")
 local secondSnapshot=forestSnapshot(copies2,false)
 restoreFourCFrames(secondSnapshot,"second-reopen")
 secondSnapshot=forestSnapshot(copies2,false)
 originals()
 check(canonical(secondSnapshot.roots)==canonical(originalSnapshot.roots)
  and secondSnapshot.referenceSHA256==originalSnapshot.referenceSHA256,"second supplemented readable forest/referents differ")
 local secondNative=SER:SerializeInstancesAsync(copies2)
 originals()
 check(sha(secondNative)==context.nativeSHA256 and buffer.len(secondNative)==context.nativeBytes,"second supplemented binary differs from original")
 report.secondSupplementedReopenPass=true report.secondNativeSHA256=sha(secondNative)
 local transfer=postParts(buffer.tostring(roundtrip))''')
replace(' report.readableRootTrees=snapshot.roots', ' report.readableRootTrees=snapshot.roots\n report.restorationRecipe="pinned raw RBXM plus pinned exact four-Bone CFrame supplemental facts after each reopen; pending unless all final cleanup/original guards pass"')
replace(' check(report.readableDataPass,"readable native property/subtree reconstruction differs; complete roundtrip retained")',
        ' check(report.readableDataPass and report.nativeSerializedBytesExact and report.secondSupplementedReopenPass,"exact supplemented reconstruction differs")')
replace(' limits="Owned off-place native deserialize/readable data/internal referents/raw reserialization only. Protected serialized properties remain opaque when raw bytes differ. External assets, UI workflows, gameplay and performance are not certified."',
        ' limits="Candidate only: exact four-Bone CFrame supplemental setters on adopted unparented copies, complete readable forest and byte-exact raw original across two supplemented reopens. No tolerance. Native execution, full-place recovery, external assets, gameplay, multiplayer and streaming remain unverified."')
assert source.count("copy.CFrame=wanted") == 1 and source.count("restoreFourCFrames(") == 3
assert "sourceWrites=0,originalParentWrites=0" in source
assert "restorationCertified=false" in source
assert "copyOwnedNodes[copy] and not knownOriginals[copy]" in source
source_out = source.encode("utf-8")
assert BEFORE.read_bytes() == source_raw and FACTS.read_bytes() == facts_raw
write_new("restore-supplement.json", supplement_raw)
write_new("restoration-supplement-probe.luau", source_out)
receipt = {"schema": "s06-restoration-supplement-preparation-v1", "nativeCalls": 0, "nativeWrites": 0,
    "restorationCertified": False, "candidateExecuted": False, "normalizationApplied": False,
    "facts": {"path": str(FACTS.relative_to(ROOT)), "bytes": len(facts_raw), "sha256": FACTS_SHA},
    "derivedFrom": {"path": str(BEFORE.relative_to(ROOT)), "bytes": len(source_raw), "sha256": sha(source_raw)},
    "files": [{"path": "restore-supplement.json", "bytes": len(supplement_raw), "sha256": sha(supplement_raw)},
        {"path": "restoration-supplement-probe.luau", "bytes": len(source_out), "sha256": sha(source_out)}],
    "requiredBeforeNativeExecution": "Root review exact generated request, dedicated immutable loopback receiver/context, current Edit/place and original ledger, offline helper+ownership fault gates, all native original/source guards; if constructor/setter changes values then pending, never epsilon-pass.",
    "futureOwnedCopiesExpected": 46, "futureOwnedCFrameSettersExpected": 8,
    "scope": "Preparation of a future exact restoration recipe for owned copies only. No authoritative source, properties, parenting, mode, existing tooling, manifest, index or commits changed."}
write_new("supplement-preparation.json", (json.dumps(receipt, indent=2) + "\n").encode())
print(json.dumps({"pass": True, "supplementSHA256": sha(supplement_raw), "candidateBytes": len(source_out), "candidateSHA256": sha(source_out), "nativeCalls": 0}))
