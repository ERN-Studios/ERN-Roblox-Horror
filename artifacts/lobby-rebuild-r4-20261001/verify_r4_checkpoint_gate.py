"""Local disk gate: concatenate/reconstruct/reopen before exposing recovery proof.

This cannot set a Studio marker. It never communicates with Studio. Missing or
failed verification leaves verified=false, so the receiver refuses /checkpoint.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, shutil, subprocess, sys

TASK = Path(__file__).resolve().parent
ROOT = TASK.parents[1]
DEST = TASK / "native-before"
GATE = DEST / "checkpoint-install-gate.json"

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
        subprocess.run([sys.executable,str(TASK/"finalize_r4_checkpoint.py")],check=True,cwd=ROOT)
        metadata=read(DEST/"metadata.json")
        chunks=[DEST/f"native-part-{index:05d}.bin" for index in range(metadata["nativeParts"])]
        assert all(path.is_file() for path in chunks),"Native transfer/reuse chunks missing"
        digest=hashlib.sha256();count=0
        for path in chunks:
            value=path.read_bytes();digest.update(value);count+=len(value)
        assert count==metadata["nativeBytes"] and digest.hexdigest()==metadata["nativeSHA256"],"Native chunk reconstruction mismatch"
        assert sha(DEST/"all-service-children.rbxm")==metadata["nativeSHA256"]
        proof=read(DEST/"checkpoint-reuse-proof.json")
        place=DEST/"BeforeLobbyR4-AuthoritativeStudio.rbxl"
        if not proof["reused"]:
            subprocess.run([str(args.lune),"run",str(ROOT/"tools/level6_build/import/pack_native_backup.luau"),str(DEST)],check=True,cwd=ROOT)
            made=DEST/"BeforeLevel6-AuthoritativeStudio.rbxl"
            assert made.is_file(),"New reconstructed native place missing"
            shutil.copy2(made,place)
        assert place.is_file(),"Native place missing"
        reopened=DEST/"native-recovery-reopen-verification.json"
        subprocess.run([str(args.lune),"run",str(TASK/"verify_r4_native_recovery.luau"),str(DEST),str(place),str(reopened)],check=True,cwd=ROOT)
        report=read(reopened)
        assert report["verified"] is True and report["captureId"]==metadata["captureId"]
        assert report["nativeSHA256"]==metadata["nativeSHA256"] and report["nativePlaceSHA256"]==sha(place)
        assert report["rootErrors"]==report["sourceErrors"]==report["sourceEditorConflicts"]==0
        assert report["sourceCount"]==metadata["scriptCount"] and report["rootCount"]==metadata["rootCount"]
        records=[]
        for path in [DEST/"metadata.json",DEST/"metadata.received.json",DEST/"scripts.json",
                     DEST/"all-service-children.rbxm",place,DEST/"checkpoint-reuse-proof.json",reopened]+chunks:
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
                             "placeReopens":True,"canonicalForestEqual":True,"exactSourceEditorParity":True},
            "files":records,"studioMarkerSetByThisScript":False,"studioWrites":False,
            "limits":report["limits"]}
        GATE.write_text(json.dumps(receipt,indent=2)+"\n")
        print(json.dumps({"verified":True,"captureId":receipt["captureId"],"nativeSHA256":receipt["nativeSHA256"],"gate":str(GATE)}))
    except Exception as error:
        GATE.write_text(json.dumps({"verified":False,"reason":str(error)},indent=2)+"\n")
        raise

if __name__=="__main__": main()
