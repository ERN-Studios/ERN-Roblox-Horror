"""Replay the exact prepared frontier template with explicit table boundaries."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
INVENTORY = HERE.with_name("animation-cache-inventory-v1")
SHA = lambda b: hashlib.sha256(b).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    output = args.receipt.resolve()
    assert output.is_relative_to(ROOT / "artifacts/cleanup-20261010") and output.parent.is_dir() and not output.exists()
    paths = [HERE / "frontier-template.luau", HERE / "frontier-suffix.luau", INVENTORY / "offline-fixtures.luau", Path(__file__).resolve()]
    inputs = {path: path.read_bytes() for path in paths}
    template = inputs[paths[0]].decode().replace("\r\n", "\n")
    fixtures = inputs[paths[2]].decode().replace("\r\n", "\n")
    assert fixtures.count("-- COLLECTOR_INSERTION:") == 1
    fixture = fixtures.split("-- COLLECTOR_INSERTION:", 1)[0]
    marker = "local report={schema=\"mongotv-animation-archive-reference-frontier-v1\""
    assert template.count(marker) == 1
    template = template.replace(marker, r'''
local _,offlineHash=sourceCatalog()
P.expectedSourceCatalogSHA256=offlineHash
P.roots={header(SS:GetChildren()[1]),header(SS:GetChildren()[2])}
P.records={}
local selectedClasses={Folder=true,Model=true}
for _,r in P.roots do
 local root=uniqueRoot(r.name,r.className,r.childCount) local tops={}
 for _,node in root:GetChildren()do tops[node]=true end
 for _,node in root:GetDescendants()do
  selectedClasses[node.ClassName]=true
  if candidate(node,tops[node])then local row=metadata(node)row.rootName=r.name row.topChild=tops[node]==true P.records[#P.records+1]=row end
 end
end
P.classes={}for class in selectedClasses do P.classes[#P.classes+1]=class end table.sort(P.classes)
if P.scenario=='initial-source-drift'then P.expectedSourceCatalogSHA256=string.rep('b',64)end
if P.scenario=='initial-root-id'then P.roots[1].instanceId='foreign'end
if P.scenario=='initial-cache-id'then P.records[1].instanceId='foreign'end
local report={schema="mongotv-animation-archive-reference-frontier-v1"''', 1)
    # The only substitution is offline request construction between unchanged
    # prefix and unchanged suffix entry. Production assembled code remains pinned.
    fixture += "\nlocal function actual(REQUEST,game,shared,task,typeof,Enum,SecurityCapabilities)\n" + template + "\nend\n"
    fixture += r'''
for _,case in {'success-external-references','unreadable-slot','missing-slot-schema','wrong-slot-schema','initial-source-drift','initial-root-id','initial-cache-id','slot-change-late','new-cache-candidate','Source-change-late','mode-change-late'}do
 local f=fixture() local rows=f.values
 local rig=f.node({Name='ExternalRig',ClassName='Model',id='externalRig',Parent=f.game})
 for i=118,144 do rows[f.tops[i]].ClassName='ObjectValue'rows[f.tops[i]].Value=rig end
 if case=='unreadable-slot'then rows[f.tops[118]].denied={Value=true}end
 local classReads=0
 local reflection={GetPropertiesOfClass=function(_,class,options)
  check(options.ExcludeInherited==false and options.ExcludeDisplay==true,'actualreflectionoptions')classReads+=1
  local specs={{Name='Name',Serialized=true,Type={ScriptType='string'}},{Name='Parent',Serialized=false,Type={ScriptType='Instance',InstanceType='Instance'}}}
  if class=='ObjectValue' and case~='missing-slot-schema'then
   specs[#specs+1]={Name='Value',Serialized=true,Type={ScriptType=if case=='wrong-slot-schema'then 'string'else 'Instance',InstanceType='Instance'}}
  elseif class=='Model'then specs[#specs+1]={Name='PrimaryPart',Serialized=true,Type={ScriptType='Instance',InstanceType='BasePart'}}end
  return specs
 end}
 local mt=getmetatable(f.game)local oldIndex=mt.__index
 mt.__index=function(object,key)
  if key=='GetService'then return function(self,name)
   if name=='ReflectionService'then return reflection end return oldIndex(self,key)(self,name)
  end end return oldIndex(object,key)
 end
 f.onYield(function(n)
  if n==4 then
   if case=='slot-change-late'then rows[f.tops[118]].Value=nil
   elseif case=='new-cache-candidate'then rows[f.pose].attributes.PublishedAssetId='new'
   elseif case=='Source-change-late'then rows[f.sources[1]].Source='foreign'
   elseif case=='mode-change-late'then rows[f.game].running=true end
  end
 end)
 local raw=actual({captureId='offline-animation-full-archive-frontier-20261010',templateSHA256=string.rep('a',64),inventoryManifestSHA256=string.rep('b',64),scenario=case},
  f.game,f.shared,f.task,f.typeof,{HashAlgorithm={Sha256='sha256'},SecurityCapability={GetEnumItems=function()return {'controlled'}end}},
  {new=function()return 'controlledCaps'end})
 check(#raw<=20000,'boundedactualsuffixresponse')local report=serde.decode('json',raw)
 local expected=case=='success-external-references' or case=='unreadable-slot'
 check(report.passed==expected,'frontiersuccess/failureexpected '..case)
 check(report.deletionApproved==false and report.fullNativeArchiveCertified==false and report.referenceAbsenceCertified==false,'noarchive/ref/deletecertificate')
 local writes,yields=f.counts()check(writes==0 and next(f.shared)==nil,'noInstance/property/Source/sharedwrites')
 if expected then
  check(report.slotCount==28 and report.sourceCount==213 and report.finalOriginalGuardPassed,'actualexactslotcount/sourceguard')
  local external=0 local unreadable=0
  for _,slot in report.slots do
   if not slot.readable then unreadable+=1 check(slot.value==nil and type(slot.error)=='string','unknownnotnilcertificate')
   elseif slot.value.kind=='Instance'then external+=1 check(slot.value.instanceId=='externalRig','actualexternalendpointpreserved')end
  end
  check(external==(if case=='unreadable-slot'then 26 else 27),'all27externaltargets')
  check(unreadable==(if case=='unreadable-slot'then 1 else 0),'actualreadabilitypreserved')
 end
 results[#results+1]={case=case,expectedPass=expected,observedPass=report.passed,nativeWrites=writes,sharedWrites=0,yields=yields,reflectedClassReads=classReads}
end
print(serde.encode('json',{passed=true,cases=#results,checks=checks,results=results,nativeCalls=0,
 limits='Actual frontier template/suffix under explicit fake Source/editor/game/reflection/security/reference/task boundaries. No actual native reflection, asset, reference absence or archive/reopen certificate.'}))
'''
    raw_fixture = fixture.encode()
    receipt = {"schema": "mongotv-animation-archive-frontier-offline-v1", "passed": False, "nativeCalls": 0,
               "productionWrites": 0, "inputs": [{"path": p.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)} for p, raw in inputs.items()],
               "assembledFixtureBytes": len(raw_fixture), "assembledFixtureSHA256": SHA(raw_fixture),
               "limits": "Explicit offline request-construction insertion only; unchanged native prefix/suffix have no native execution evidence."}
    try:
        with tempfile.TemporaryDirectory(prefix="mongotv-animation-frontier-") as folder:
            path = Path(folder) / "actual-frontier.luau"
            path.write_bytes(raw_fixture)
            compile_result = subprocess.run(["C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe", str(path)], capture_output=True, text=True, timeout=30)
            receipt["compile"] = {"exitCode": compile_result.returncode, "stderr": compile_result.stderr[:8000]}
            assert compile_result.returncode == 0, compile_result.stderr
            replay = subprocess.run(["C:/Users/mikke/AppData/Local/Temp/codex-lune-0.10.5/lune.exe", "run", str(path)], capture_output=True, text=True, timeout=120)
            receipt["stderr"] = replay.stderr[:10000]
            receipt["stdout"] = replay.stdout[:30000]
            assert replay.returncode == 0, replay.stderr
            receipt["replay"] = json.loads(replay.stdout)
            assert receipt["replay"]["passed"] and receipt["replay"]["cases"] == 11
            del receipt["stdout"]
            receipt["passed"] = True
    except BaseException as error:
        receipt["error"] = str(error)
        raise
    finally:
        for path, raw in inputs.items():
            assert path.read_bytes() == raw, "Frozen frontier input drifted during port"
        with output.open("xb") as stream:
            stream.write((json.dumps(receipt, indent=2) + "\n").encode())
    print(json.dumps({"passed": True, "cases": receipt["replay"]["cases"], "checks": receipt["replay"]["checks"], "receiptSHA256": SHA(output.read_bytes())}))


if __name__ == "__main__":
    main()
