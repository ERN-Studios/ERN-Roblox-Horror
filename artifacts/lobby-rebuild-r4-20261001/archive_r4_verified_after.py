"""Archive only a verified noncloud native-after capture; preserve existing files."""
from pathlib import Path
import datetime
import hashlib
import json
import os

TASK = Path(__file__).resolve().parent
SOURCE = Path("/private/tmp/lobby-r4-native-after-20261001")
DEST = TASK / "native-after"

def sha(path):
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda:stream.read(1024*1024),b""):
            digest.update(block)
    return digest.hexdigest()

def copy_exact(source,destination):
    digest=sha(source)
    destination.parent.mkdir(parents=True,exist_ok=True)
    if destination.exists():
        assert destination.stat().st_size==source.stat().st_size and sha(destination)==digest, f"Existing archive differs: {destination.name}"
    else:
        partial=destination.with_name(destination.name+".partial")
        with source.open("rb") as incoming,partial.open("xb") as outgoing:
            for block in iter(lambda:incoming.read(1024*1024),b""):
                outgoing.write(block)
            outgoing.flush();os.fsync(outgoing.fileno())
        os.replace(partial,destination)
        assert sha(destination)==digest,f"Archived bytes differ: {destination.name}"
    return {"file":destination.relative_to(TASK).as_posix(),"bytes":destination.stat().st_size,"sha256":digest}

def main():
    gate=json.loads((SOURCE/"checkpoint-install-gate.json").read_bytes())
    scope=json.loads((SOURCE/"scoped-native-preservation.json").read_bytes())
    mirrors=json.loads((SOURCE/"final-scoped-source-mirror.json").read_bytes())
    pbr=json.loads((SOURCE/"static-pbr-native-reference-verification.json").read_bytes())
    assert gate["verified"] is True and scope["verified"] is True
    assert gate["captureId"]==scope["afterCaptureId"] and gate["nativeSHA256"]==scope["afterNativeSHA256"]
    for proof in (mirrors,pbr):
        assert proof["verified"] is True and proof["captureId"]==gate["captureId"]
        assert proof["nativeSHA256"]==gate["nativeSHA256"] and proof["catalogSHA256"]==scope["catalogSHA256"]
    assert mirrors["sourceCount"]==8 and pbr["templateCount"]==3 and pbr["imageReferenceCount"]==9
    assert gate["placeId"]==131311258779917 and gate["universeId"]==10559217407 and gate["groupId"]==1039373905
    assert scope["scopedSourceCount"]==8 and scope["baselineForestCanonicalEqual"] is True
    for row in gate["files"]:
        source=(SOURCE/row["file"]).resolve()
        assert source.is_relative_to(SOURCE.resolve()) and source.stat().st_size==row["bytes"] and sha(source)==row["sha256"]
    records=[]
    for source in sorted(SOURCE.rglob("*")):
        if not source.is_file():continue
        assert not source.is_symlink() and not source.name.endswith(".partial")
        relative=source.relative_to(SOURCE)
        destination=(TASK/"fresh-source-after"/relative.relative_to("fresh-source")) if relative.parts[0]=="fresh-source" else (DEST/relative)
        records.append(copy_exact(source,destination))
    receipt={"schema":"lobby-r4-verified-native-after-archive-v1","verified":True,
             "archivedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
             "captureId":gate["captureId"],"nativeSHA256":gate["nativeSHA256"],"nativePlaceSHA256":gate["nativePlaceSHA256"],
             "noncloudSource":str(SOURCE),"archiveDirectory":str(DEST),"sourceExportDirectory":str(TASK/"fresh-source-after"),
             "recoveryGateVerified":True,"scopedPreservationVerified":True,"finalEightSourceMirrorsVerified":True,
             "staticPBRNativeReferencesVerified":True,"catalogSHA256":scope["catalogSHA256"],"fileCount":len(records),"files":records,
             "studioActions":False,"beforeCheckpointChanged":False}
    (TASK/"review/native-after-archive-verification.json").write_text(json.dumps(receipt,indent=2)+"\n")
    print(json.dumps({"verified":True,"captureId":gate["captureId"],"fileCount":len(records),"archiveDirectory":str(DEST)}),flush=True)

if __name__=="__main__":main()
