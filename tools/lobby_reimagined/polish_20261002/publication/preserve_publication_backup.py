"""Copy only this verified checkpoint to a durable, separate local backup.

No Studio/network/Git operations. Existing differing files are never replaced.
Recoverability may pass while the distinct publication preflight remains false.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os
import shutil
import uuid

SOURCE=Path("/private/tmp/lobby-polish-publish-20261002")
DESTINATION=Path("/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-lobby-polish/publication")
CAPTURE_ID="e89b2ace-e45b-4a19-bf49-aafce986ef64"
NATIVE_SHA="7bd1d2e12cb0dc3a284e8f7c135eb18fc8d1d5b2da1a7df3fcaa4a1e01a0a8e9"

def sha(path):
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda:stream.read(1024*1024),b""):digest.update(block)
    return digest.hexdigest()

def main():
    gate=json.loads((SOURCE/"checkpoint-install-gate.json").read_text())
    assert gate["verified"] is True and gate["captureId"]==CAPTURE_ID and gate["nativeSHA256"]==NATIVE_SHA
    assert gate["placeId"]==131311258779917 and gate["universeId"]==10559217407
    metadata=json.loads((SOURCE/"metadata.json").read_text())
    preflight=json.loads((SOURCE/"publication-source-preflight.json").read_text())
    reconstruction=json.loads((SOURCE/"native-place-verification.json").read_text())
    assert sha(SOURCE/"publication-source-preflight.json")==gate["publicationSourcePreflightSHA256"]
    assert preflight["captureId"]==CAPTURE_ID and preflight["nativeSHA256"]==NATIVE_SHA
    files={row["file"]:row for row in gate["files"]}
    extra=["checkpoint-install-gate.json","publication-source-preflight.json","service-property-schema.json",
           "native-place-verification.json","backup-metadata-summary.json","backup-file-hashes.json",
           "source-manifest.json","fresh-source-manifest.json","source-transfer-receipt.json"]
    extra += [f"script-part-{index:05d}.jsonpart" for index in range(metadata["scriptJsonParts"])]
    for name in extra:
        path=SOURCE/name
        assert path.is_file(),f"Missing local proof file: {name}"
        files[name]={"file":name,"bytes":path.stat().st_size,"sha256":sha(path)}
    DESTINATION.mkdir(parents=True,exist_ok=True)
    rows=[]
    for name,row in sorted(files.items()):
        rel=Path(name)
        assert not rel.is_absolute() and ".." not in rel.parts and len(rel.parts)==1,"Unsafe backup path"
        src=SOURCE/rel;dst=DESTINATION/rel
        assert src.is_file() and not src.is_symlink() and src.stat().st_size==row["bytes"] and sha(src)==row["sha256"],f"Checkpoint input changed: {name}"
        if dst.exists():
            assert dst.is_file() and not dst.is_symlink() and dst.stat().st_size==row["bytes"] and sha(dst)==row["sha256"],f"Existing durable file differs: {name}"
        else:
            temporary=DESTINATION/(name+".partial-"+uuid.uuid4().hex)
            with src.open("rb") as reader,temporary.open("xb") as writer:
                shutil.copyfileobj(reader,writer,1024*1024);writer.flush();os.fsync(writer.fileno())
            assert temporary.stat().st_size==row["bytes"] and sha(temporary)==row["sha256"],f"Durable copy hash mismatch: {name}"
            # Hard-link creation is atomic and cannot replace a concurrently
            # created destination. The temporary link belongs only to this run.
            try: os.link(temporary,dst)
            except FileExistsError:
                assert dst.is_file() and not dst.is_symlink() and sha(dst)==row["sha256"],f"Concurrent durable file differs: {name}"
            temporary.unlink()
        assert sha(dst)==row["sha256"],f"Durable reread mismatch: {name}"
        rows.append(row)
    receipt={"schema":"lobby-polish-durable-publication-backup-v1","verified":True,
        "verifiedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"captureId":CAPTURE_ID,
        "placeId":gate["placeId"],"universeId":gate["universeId"],"nativeSHA256":NATIVE_SHA,
        "nativePlaceSHA256":gate["nativePlaceSHA256"],"nativeBytes":gate["nativeBytes"],
        "nativePlaceBytes":gate["nativePlaceBytes"],"rootCount":gate["rootCount"],"sourceCount":gate["sourceCount"],
        "sourceEditorConflicts":0,"source":str(SOURCE),"destination":str(DESTINATION),"fileCount":len(rows),
        "totalVerifiedBytes":sum(row["bytes"] for row in rows),"files":rows,
        "backupVerification":gate["verification"],"reconstructionLimits":gate["limits"],
        "reconstructionReportSHA256":sha(SOURCE/"native-place-verification.json"),
        "reconstructionPropertyErrors":reconstruction.get("propertyErrors"),
        "reconstructionUnreadableProperties":reconstruction.get("limitations"),
        "publicationSourcePreflightSHA256":gate["publicationSourcePreflightSHA256"],
        "publicationPreflightPassed":preflight["publicationPreflightPassed"],"publicationAuthorized":False,
        "priorAfterCaptureOrExportModified":False,"studioOrGitWrites":False,
        "limits":"Durable copy and native recovery proof. Publication preflight and actual Studio publication are separate; unrelated work is preserved."}
    data=(json.dumps(receipt,indent=2)+"\n").encode()
    path=SOURCE/"durable-publication-backup-receipt.json"
    assert not path.exists(),"Receipt already exists; preserve its original verification time"
    path.write_bytes(data)
    with (DESTINATION/path.name).open("xb") as stream:stream.write(data);stream.flush();os.fsync(stream.fileno())
    assert sha(path)==sha(DESTINATION/path.name)
    print(json.dumps({"verified":True,"captureId":CAPTURE_ID,"fileCount":len(rows),"destination":str(DESTINATION),
                      "receipt":str(path),"receiptSHA256":sha(path),"publicationPreflightPassed":preflight["publicationPreflightPassed"]}))

if __name__=="__main__":main()
