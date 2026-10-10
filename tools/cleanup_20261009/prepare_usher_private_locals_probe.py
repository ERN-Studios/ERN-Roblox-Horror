"""Prepare exact86-byte private unused Usher locals with real-source contracts.

Default is offline-only immutable preparation. Root alone can execute reviewed
fresh unparented ModuleScript probes; production Source/objects/mode are never
modified. Perception/navigation/capture are explicit controlled boundaries.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/"artifacts/cleanup-20261009/usher-private-locals-native-v1"
DEST=ART/"proposal-v1"
FILE="ServerScriptService/Level 4 Systems/Level 4 Usher Controller.ModuleScript.lua"
BEFORE="9af1a745968b95928355707aeaf81bf36b2e9495bdc589918b72bca10d6ba7e3"
AFTER="ec4252424a0a513ca370851a5ff45b212bab4c2bfcbe20cba58c0a740a2b2a2f"
LUAU=Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe")
COMPILER=LUAU.with_name("luau-compile.exe")
sha=lambda b:hashlib.sha256(b).hexdigest()
lf=lambda b:b.replace(b"\r\n",b"\n")


def encoded(v):return (json.dumps(v,indent=2,ensure_ascii=False)+"\n").encode()


def save(p,b):
    p.parent.mkdir(parents=True,exist_ok=True)
    with p.open("xb") as f:assert f.write(b)==len(b)
    assert p.read_bytes()==b


def lua_literal(text):
    level="="
    while "]"+level+"]" in text:level+="="
    return "string.sub(["+level+"[_"+text+"]"+level+"],2)"


FAULTS=r'''
    -- Actual Stop boundaries fail once; retry is the same actual function.
    for _,kind in {"capture","disconnect","proxy"} do
        setMode("holder");e.clock=80
        target=e.player;path={Vector3.new(1,0,1)};beamTime=.2;stunCooldownUntil=99;nextHopAt=120
        setBeamers({e.player})
        proxy=e.new("Model","Fault Usher Proxy");root=e.new("Part","Fault Root",proxy);head=e.new("Part","Fault Head",proxy)
        lights={OnZoneChanged=onZoneChanged};capture={Player=e.player}
        local injected=true;local disconnected=0;local priorFinish=#e.finish;local oldFinish=finishCapture
        finishCapture=function(record,cancelled)
            oldFinish(record,cancelled)
            if kind=="capture" and injected then error("controlled capture finish failure",0)end
        end
        connections={{Disconnect=function()
            disconnected+=1
            if kind=="disconnect" and injected then error("controlled connection failure",0)end
        end},{Disconnect=function()disconnected+=1 end}}
        if kind=="proxy" then rawset(proxy,"Destroy",function()error("controlled proxy destroy failure",0)end)end
        local ownedProxy=proxy;local originalSession=session
        local ok,err=pcall(Usher.Stop)
        local expected=kind=="capture" and "controlled capture finish failure" or kind=="disconnect" and "controlled connection failure" or "controlled proxy destroy failure"
        check(not ok and err==expected,"actual Stop failure propagates unchanged "..kind)
        check(not active and not finale and not hopping and session==originalSession+1,"failed Stop still invalidates active/session "..kind)
        check(proxy==ownedProxy and not ownedProxy.Destroyed,"failed Stop preserves current proxy until retry "..kind)
        if kind=="capture" then
            check(capture~=nil and disconnected==0,"capture error stops before capture/connection clear")
        elseif kind=="disconnect" then
            check(capture==nil and #connections==2 and disconnected==1,"disconnect error preserves remaining connection list")
        else
            check(capture==nil and #connections==0 and disconnected==2 and lights.OnZoneChanged==nil,"proxy error occurs after prior cleanup")
        end
        rows[#rows+1]={Failure=kind,Error=err,State=snapshot(),Session=session,Disconnected=disconnected}
        injected=false;rawset(ownedProxy,"Destroy",nil)
        Usher.Stop();finishCapture=oldFinish
        check(session==originalSession+2 and not active and state=="Dormant" and hidden,"same Stop retries and reaches dormant "..kind)
        check(capture==nil and target==nil and path==nil and proxy==nil and #connections==0,"retry clears active capture/target/proxy/connections "..kind)
        check(beamTime==0 and stunCooldownUntil==0 and nextHopAt==0 and e.player:GetAttribute("Level4_BeamingUsher")==nil,"retry clears active cooldown/beamer fields "..kind)
        check(disconnected==(kind=="disconnect" and 3 or 2),"retry disconnect ordering retained "..kind)
        check(#e.finish==priorFinish+(kind=="capture" and 2 or 1),"same capture finish retry boundary retained "..kind)
        rows[#rows+1]={Retried=kind,State=snapshot(),Session=session,Disconnected=disconnected}
        Usher.Stop();check(session==originalSession+3 and proxy==nil and #connections==0,"Stop reentry remains idempotent for owned resources "..kind)
    end
'''


def load_port():
    p=ROOT/"artifacts/cleanup-20261009/verify_usher_locals.py"
    assert sha(p.read_bytes())=="e21fc02fe0f6db80d0c44a9fb66c6007583f49c1b21f8e0e91b44cc5f91e5061"
    spec=importlib.util.spec_from_file_location("immutable_usher_contract",p)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def payload(base,host,source,port):
    marker="    stateFolder:Destroy()\n    return rows"
    assert host.count(marker)==1
    extended=host.replace(marker,FAULTS+marker,1)
    body=port.port(extended,source,"actualPort")
    return "return function()\n"+base+body+"\nlocal rows=usherFixture(actualPort)\nreturn {checks=checks,signature=stable(rows)}\nend\n"


def prepare():
    assert not DEST.exists(),"Immutable proposal exists; reconcile into a new version"
    raw=(ROOT/FILE).read_bytes();manifest_raw=(ROOT/"studio-sync-manifest.json").read_bytes()
    before=(ROOT/"artifacts/cleanup-20261009/usher-locals/Usher.before.luau").read_bytes()
    after=(ROOT/"artifacts/cleanup-20261009/usher-locals/Usher.candidate.luau").read_bytes()
    assert before==lf(raw) and sha(before)==BEFORE and sha(after)==AFTER and len(before)-len(after)==86
    manifest=json.loads(manifest_raw);entry=next(r for r in manifest["items"] if r["file"]==FILE)
    assert entry["sha256"]==BEFORE and entry["sourceEditorMatches"] is True
    source=before.decode();candidate=source
    port=load_port()
    for name,count in (("targetReason",2),("nextThinkAt",1),("stunUntil",2)):
        assert len(re.findall(r"\b"+name+r"\b",source))==count
    for a,b in port.EDITS:
        assert candidate.count(a)==1
        candidate=candidate.replace(a,b,1)
    assert candidate.encode()==after
    # Root's actual S14 final snapshot supplies recent native metadata/identity/
    # Source hashes; the prospective probe rechecks these live before staging.
    native_path=ROOT/"artifacts/cleanup-20261009/remaining-private-locals-native-v1/room-source-install-v1/native-final.json"
    native=json.loads(native_path.read_bytes())
    wanted={"ServerScriptService.Level 4 Systems.Level 4 Usher Controller","ServerScriptService.Level4RoundGenerator",
            "ServerScriptService.Level 4 Systems.Level 4 Configuration","ServerScriptService.NoiseRegistry",
            "ServerScriptService.PlayerProtection","ReplicatedStorage.DeathAdvice"}
    originals=[];entries={r["studioPath"]:r for r in manifest["items"]}
    for r in native["rows"]:
        if r["studioPath"] not in wanted:continue
        live=dict(r);live["sourceSHA256"]=r["sha256"]
        recorded=entries[r["studioPath"]]
        assert recorded["sha256"]==r["sha256"]==sha(lf((ROOT/recorded["file"]).read_bytes()))
        for key in ("className","properties","attributes"):
            assert recorded[key]==r[key],"Closure metadata changed"
        assert not r["tags"] or recorded.get("tags")==r["tags"]
        originals.append(live)
    assert len(originals)==6
    originals.sort(key=lambda r:(r["studioPath"]!=entry["studioPath"],r["studioPath"]))
    assert originals[0]["instanceId"]=="1_42775" and originals[0]["parentId"]=="1_15624"
    pinned={"artifacts/cleanup-20261009/local-helpers-host.luau":"d7333b5cfcf813de0f60a22f4b0795286530d7f9bf8a777409d506e3efd69b45",
            "artifacts/cleanup-20261009/additional-locals-host.luau":"425d7a48747a06bd378145ee17abec7d914d0459eebd2449cf806454837477ce",
            "artifacts/cleanup-20261009/usher-locals-host.luau":"f01cba0e6df96fb01102654345e991ad06d94f57c93f479933193602d089d0cb"}
    for p,h in pinned.items():assert sha((ROOT/p).read_bytes())==h
    base="".join((ROOT/p).read_text(encoding="utf8") for p in list(pinned)[:2])
    host=(ROOT/list(pinned)[2]).read_text(encoding="utf8")
    payloads={"before":payload(base,host,source,port),"candidate":payload(base,host,candidate,port),
              "reasonNegative":payload(base,host,candidate.replace('reason == "sight" or reason == "holder" or finale','false',1),port),
              "cooldownNegative":payload(base,host,candidate.replace('stunCooldownUntil = t + C.StunCooldownSeconds','stunCooldownUntil = 0',1),port)}
    template=Path(__file__).with_name("usher_private_locals_probe.luau").read_text(encoding="utf8")
    spec=importlib.util.spec_from_file_location("owned_latch_probe_v2",Path(__file__).with_name("prepare_latch_mode_probe_v2.py"))
    owned=importlib.util.module_from_spec(spec);spec.loader.exec_module(owned)
    ownership=owned.ownership_fixture(template);compiles=[]
    with tempfile.TemporaryDirectory(prefix="usher-private-locals-") as directory:
        temp=Path(directory)
        wrappers="\n".join("local "+name+"=(function()\n"+body+"\nend)()" for name,body in payloads.items())
        test=wrappers+'''
local a,b=before(),candidate();assert(a.checks==b.checks and a.signature==b.signature,"Actual targeting/stun/Stop/failure/retry output changed")
local aa,bb=before(),candidate();assert(aa.checks==a.checks and aa.signature==a.signature and bb.checks==b.checks and bb.signature==b.signature,"Runner reentry changed")
for _,entry in {{reasonNegative,"reason still controls target mode holder"},{cooldownNegative,"held stun keeps existing cooldown"}} do
 local ok,err=pcall(entry[1]);assert(not ok and tostring(err):find(entry[2],1,true),"Actual active reason/cooldown semantic mutant not rejected")
end
print("CHECKS="..a.checks)
'''
        p=temp/"paired.luau";p.write_bytes(test.encode())
        run=subprocess.run([str(LUAU),str(p)],capture_output=True,text=True,timeout=30)
        assert run.returncode==0,run.stdout+run.stderr
        count=int(re.search(r"CHECKS=(\d+)",run.stdout)[1])
        expected={"nativeScriptCount":manifest["counts"]["scripts"],"contractChecks":count,"originals":originals}
        assert expected["nativeScriptCount"]==212
        codes={}
        for phase in ("before","installed"):
            values=json.loads(json.dumps(expected))
            if phase=="installed":values["originals"][0]["sourceSHA256"]=AFTER
            code=template.replace("__EXPECTED__",lua_literal(json.dumps(values,ensure_ascii=False)))
            code=code.replace("__PAYLOADS__",lua_literal(json.dumps(payloads,ensure_ascii=False))).replace("__INSTALLED__",str(phase=="installed").lower())
            codes[phase]=code
        inputs={**{"native-"+k:v for k,v in codes.items()},**{"payload-"+k:v for k,v in payloads.items()},"ownership":ownership,"beforeFullSource":source,"candidateFullSource":candidate}
        for name,body in inputs.items():
            p=temp/(name+".luau");p.write_bytes(body.encode())
            for opt in ("-O0","-O1"):
                run=subprocess.run([str(COMPILER),"--binary",opt,str(p)],capture_output=True,timeout=15)
                assert run.returncode==0,run.stderr.decode(errors="replace")
                compiles.append({"input":name,"optimization":opt,"pass":True,"sourceSHA256":sha(body.encode())})
        run=subprocess.run([str(LUAU),str(temp/"ownership.luau")],capture_output=True,text=True,timeout=15)
        assert run.returncode==0,run.stdout+run.stderr
        owner_count=int(re.search(r"OWNERSHIP_CHECKS=(\d+)",run.stdout)[1])
    assert (ROOT/FILE).read_bytes()==raw and (ROOT/"studio-sync-manifest.json").read_bytes()==manifest_raw
    save(ART/".gitattributes",b"* -text\n")
    for name,body in payloads.items():save(DEST/(name+".module.luau"),body.encode())
    for name,code in codes.items():save(DEST/("native-"+name+".luau"),code.encode())
    save(DEST/"ownership-fixture.luau",ownership.encode())
    proof={"schema":"usher-private-locals-native-proposal-v1","pass":True,"finding":"LE-32","file":FILE,
           "beforeSHA256":BEFORE,"candidateSHA256":AFTER,"removedBytes":86,"checksPerVersion":count,"pairedChecks":count*2,"reentryChecks":count*2,
           "semanticNegativeControls":2,"ownershipCases":8,"ownershipChecks":owner_count,"nativeScriptCount":212,
           "originals":originals,"templateSHA256":sha(template.encode()),"toolSHA256":sha(Path(__file__).read_bytes()),
           "nativeCodeHashes":{k:sha(v.encode()) for k,v in codes.items()},"payloadHashes":{k:sha(v.encode()) for k,v in payloads.items()},
           "compileChecks":compiles,"immutableInputHashes":pinned,"originalPortSHA256":sha(Path(port.__file__).read_bytes()),
           "recentNativeMetadataPath":native_path.relative_to(ROOT).as_posix(),"recentNativeMetadataSHA256":sha(native_path.read_bytes()),
           "currentManifestSHA256":sha(manifest_raw),"nativeCalls":0,"productionWrites":0,"manifestWrites":0,
           "scope":"Actual Source state/chooseTarget/think/setState/setBeamers/Stop with explicit controlled engine/perception/nav/capture boundaries. No live module initializer, round, real capture/jumpscare/physics/assets/multiplayer/streaming/performance certificate.",
           "status":"offline meaningful paired failure/retry/reentry contracts pass; Root native-before/installation/final ports pending"}
    save(DEST/"proposal.json",encoded(proof))
    print(json.dumps({"pass":True,"checksPerVersion":count,"pairedChecks":count*2,"reentryChecks":count*2,"compileChecks":len(compiles),"ownershipChecks":owner_count,"nativeCalls":0,"nativeCodeHashes":proof["nativeCodeHashes"]}))


def execute(phase,receipt):
    assert receipt is not None and not receipt.exists(),"Require a new immutable receipt"
    proof=json.loads((DEST/"proposal.json").read_bytes());code=(DEST/("native-"+phase+".luau")).read_bytes()
    assert sha(code)==proof["nativeCodeHashes"][phase] and sha(lf((ROOT/FILE).read_bytes()))==proof["beforeSHA256" if phase=="before" else "candidateSHA256"]
    sys.path.insert(0,str(ROOT/"tools"))
    from sync_from_studio import StudioMcpClient,find_mcp_batch,select_studio,RELEASE_STUDIO_NAME,require_edit_state
    client=StudioMcpClient(find_mcp_batch());result=None;error=None
    try:
        client.initialize();studio=select_studio(client,RELEASE_STUDIO_NAME,15)
        assert studio["id"]=="1b603e69-7ae1-4572-b210-d5bf05c684ff";require_edit_state(client,studio["id"])
        result=json.loads(client.call("execute_luau",{"studio_id":studio["id"],"datamodel_type":"Edit","code":code.decode()}))
    except BaseException as primary:error=primary
    finally:
        try:client.close()
        except BaseException as cleanup:
            if error is None:error=cleanup
            else:error.add_note("MCP close: "+str(cleanup))
        if result is None:result={"pass":False}
        if error is not None:result.update({"pass":False,"transportError":str(error)})
        result["nativeInputSHA256"]=sha(code);save(receipt,encoded(result))
    print(json.dumps({k:result.get(k) for k in ("pass","originalsUnchanged","remainingProbes","ownedLeaseReleased","error","transportError")}))
    assert error is None and result.get("pass") is True,"Native gate failed; preserve candidate pending"


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--execute",choices=("before","installed"));parser.add_argument("--receipt",type=Path)
    args=parser.parse_args()
    if args.execute:execute(args.execute,args.receipt)
    else:prepare()
