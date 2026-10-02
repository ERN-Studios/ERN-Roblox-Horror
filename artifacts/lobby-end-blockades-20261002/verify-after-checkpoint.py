"""Local disk gate: concatenate/reconstruct/reopen before exposing recovery proof.

This cannot set a Studio marker. It never communicates with Studio. Missing or
failed verification leaves verified=false, so the receiver refuses /checkpoint.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, shutil, subprocess, sys

TASK = Path(__file__).resolve().parent
ROOT = TASK.parents[1]
DEST = Path("/private/tmp/lobby-endfix-after-20261002")
GATE = DEST / "checkpoint-install-gate.json"
CONCURRENT = TASK / "review/concurrent-native/concurrent-delta-pins.json"
AUDIT = TASK / "review/concurrent-native/scoped-concurrent-native-preservation.json"

def read(path): return json.loads(path.read_text())
def sha(path):
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024),b""): digest.update(block)
    return digest.hexdigest()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--lune",type=Path,default=Path("/private/tmp/level6-lune-20261001/lune"))
    args=parser.parse_args()
    DEST.mkdir(parents=True,exist_ok=True)
    GATE.write_text(json.dumps({"verified":False,"reason":"Verification not yet complete"})+"\n")
    try:
        for file in ("metadata.json","scripts.json"):
            assert (DEST/file).is_file(),f"No fresh {file} export"
        metadata=read(DEST/"metadata.json")
        assert metadata.get("captureId"),"Fresh session capture ID missing"
        assert metadata["placeId"]==131311258779917 and metadata["universeId"]==10559217407
        assert metadata["groupId"]==1039373905
        concurrent=read(CONCURRENT)
        assert concurrent["schema"]=="lobby-endfix-explicit-concurrent-native-pins-v1"
        assert metadata["nativeSHA256"]==concurrent["expectedAfterNativeSHA256"] and metadata["captureId"]==concurrent["afterCaptureId"]
        assert metadata["rootCount"]==concurrent["expectedAfterRootCount"]==192 and metadata["scriptCount"]==concurrent["expectedAfterSourceCount"]==222,"Unexpected pinned concurrent root/source count"
        native=DEST/"all-service-children.rbxm"
        if not native.is_file() or native.stat().st_size!=metadata["nativeBytes"] or sha(native)!=metadata["nativeSHA256"]:
            subprocess.run([sys.executable,str(TASK/"finalize-after-checkpoint.py")],check=True,cwd=ROOT)
        metadata=read(DEST/"metadata.json")
        chunks=[DEST/f"native-part-{index:05d}.bin" for index in range(metadata["nativeParts"])]
        assert all(path.is_file() for path in chunks),"Native transfer/reuse chunks missing"
        digest=hashlib.sha256();count=0
        for path in chunks:
            value=path.read_bytes();digest.update(value);count+=len(value)
        assert count==metadata["nativeBytes"] and digest.hexdigest()==metadata["nativeSHA256"],"Native chunk reconstruction mismatch"
        assert sha(DEST/"all-service-children.rbxm")==metadata["nativeSHA256"]
        proof=read(DEST/"checkpoint-reuse-proof.json")
        place=DEST/"AfterLobbyEndFix-AuthoritativeStudio.rbxl"
        reopened=DEST/"native-recovery-reopen-verification.json"
        prior=read(reopened) if reopened.is_file() else {}
        already_reopened=(prior.get("verified") is True and prior.get("captureId")==metadata["captureId"]
            and prior.get("nativeSHA256")==metadata["nativeSHA256"] and place.is_file()
            and prior.get("nativePlaceSHA256")==sha(place)
            and prior.get("rootCount")==metadata["rootCount"] and prior.get("sourceCount")==metadata["scriptCount"]
            and prior.get("rootErrors")==prior.get("sourceErrors")==prior.get("sourceEditorConflicts")==0)
        if not already_reopened:
            if not proof["reused"]:
                subprocess.run([str(args.lune),"run",str(ROOT/"tools/level6_build/import/pack_native_backup.luau"),str(DEST)],check=True,cwd=ROOT)
                made=DEST/"BeforeLevel6-AuthoritativeStudio.rbxl"
                assert made.is_file(),"New reconstructed native place missing"
                shutil.copy2(made,place)
            assert place.is_file(),"Native place missing"
            subprocess.run([str(args.lune),"run",str(ROOT/"artifacts/lobby-rebuild-r4-20261001/verify_r4_native_recovery.luau"),str(DEST),str(place),str(reopened)],check=True,cwd=ROOT)
        report=read(reopened)
        assert report["verified"] is True and report["captureId"]==metadata["captureId"]
        assert report["nativeSHA256"]==metadata["nativeSHA256"] and report["nativePlaceSHA256"]==sha(place)
        assert report["rootErrors"]==report["sourceErrors"]==report["sourceEditorConflicts"]==0
        assert report["sourceCount"]==metadata["scriptCount"] and report["rootCount"]==metadata["rootCount"]
        preservation = DEST/"scoped-native-preservation.json"
        prior_audit=read(AUDIT) if AUDIT.is_file() else {}
        audit_reused=(prior_audit.get("verified") is True and prior_audit.get("afterCaptureId")==metadata["captureId"]
            and prior_audit.get("beforeNativeSHA256")==concurrent["expectedBeforeNativeSHA256"]
            and prior_audit.get("afterNativeSHA256")==metadata["nativeSHA256"]
            and prior_audit.get("taskPinsSHA256")==sha(TASK/"after-native-scope-pins.json")
            and prior_audit.get("concurrentPinsSHA256")==sha(CONCURRENT))
        if audit_reused:
            shutil.copy2(AUDIT,preservation)
        else:
            subprocess.run([str(args.lune),"run",str(TASK/"verify-endfix-concurrent-native.luau"),
                            "/private/tmp/lobby-endfix-before-20261002",str(DEST),
                            str(TASK/"after-native-scope-pins.json"),str(CONCURRENT),str(preservation)],check=True,cwd=ROOT)
        preservation_report=read(preservation)
        assert preservation_report["verified"] is True and preservation_report["baselineForestCanonicalEqual"] is True
        assert preservation_report["existingScopedSources"]==1 and preservation_report["newScopedSources"]==2
        assert preservation_report["concurrentChangedSources"]==10 and preservation_report["concurrentNewSources"]==7
        assert len(preservation_report["concurrentAddedRootRows"])==3 and not preservation_report["existingNonScriptPropertyDeltas"]
        assert not preservation_report["existingReferencePropertyDeltas"] and not preservation_report["errors"]
        records=[]
        for path in [DEST/"metadata.json",DEST/"metadata.received.json",DEST/"scripts.json",
                     DEST/"all-service-children.rbxm",place,DEST/"checkpoint-reuse-proof.json",reopened,preservation]+chunks:
            assert path.is_file(),f"Verified receipt input missing: {path.name}"
            records.append({"file":path.relative_to(DEST).as_posix(),"bytes":path.stat().st_size,"sha256":sha(path)})
        receipt={"schema":"lobby-r4-checkpoint-install-gate-v1","verified":True,
            "captureId":metadata["captureId"],"capturedAtUnix":metadata["captureFinishedUnixMillis"]//1000,
            "placeId":metadata["placeId"],"universeId":metadata["universeId"],"groupId":metadata["groupId"],
            "nativeSHA256":metadata["nativeSHA256"],"nativeBytes":metadata["nativeBytes"],
            "nativePlaceSHA256":sha(place),"nativePlaceBytes":place.stat().st_size,
            "rootCount":report["rootCount"],"sourceCount":report["sourceCount"],
            "recoveryVerifiedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "verification": {"chunksConcatenateExactly":True,"nativeForestDeserializes":True,
                             "placeReopens":True,"canonicalForestEqual":True,"exactSourceEditorParity":True,
                             "taskThreeSourcePinsExact":True,"explicitConcurrentDeltasRecorded":True,
                             "remainingBaselineForestUnchanged":True,"savedServiceSettingsUnchanged":True,
                             "concurrentGameplayVerified":False},
            "reusedAlreadyVerifiedNativePlace":already_reopened,"reusedAlreadyVerifiedConcurrentAudit":audit_reused,
            "concurrentManifestFile":str(CONCURRENT),"concurrentManifestSHA256":sha(CONCURRENT),
            "taskSourcePinsSHA256":sha(TASK/"after-native-scope-pins.json"),
            "files":records,"studioMarkerSetByThisScript":False,"studioWrites":False,
            "limits":(report["limits"] if isinstance(report["limits"],list) else [report["limits"]])+preservation_report["publicationLimits"]}
        GATE.write_text(json.dumps(receipt,indent=2)+"\n")
        print(json.dumps({"verified":True,"captureId":receipt["captureId"],"nativeSHA256":receipt["nativeSHA256"],"gate":str(GATE)}))
    except Exception as error:
        GATE.write_text(json.dumps({"verified":False,"reason":str(error)},indent=2)+"\n")
        raise

if __name__=="__main__": main()
