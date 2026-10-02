"""Local disk gate: concatenate/reconstruct/reopen before exposing recovery proof.

This cannot set a Studio marker. It never communicates with Studio. Missing or
failed verification leaves verified=false, so the receiver refuses /checkpoint.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, shutil, subprocess, sys

TASK = Path(__file__).resolve().parent
ROOT = TASK.parents[3]
DEST = Path("/private/tmp/lobby-polish-publish-20261002")
PREVIOUS = Path("/private/tmp/lobby-polish-after-20261002")
GATE = DEST / "checkpoint-install-gate.json"
PRIOR_CAPTURE_ID = "4df9e7f4-49ec-434d-abbf-d2607efa9c2a"
PRIOR_NATIVE_SHA = "868f29672e3bda6b501e44d5039880304f3fce989d2934e86ba510834b539b11"
PRIOR_SOURCE_CATALOG_SHA = "4f26e8f4e929e6372eb34509220091fd7f5946a03cf7a1428c9e85e6eedcdb58"
REMOVED_QA = {
    "ServerScriptService.Level4TemporaryIntegrationQA": {
        "class": "Script", "sourceBytes": 3371,
        "sourceSha256": "baf5440ac57bd5b768d52bcd59c6c8916910569b93834bf826e2b71684a8ed85"},
    "StarterPlayer.StarterPlayerScripts.Level4TemporaryProfileQA": {
        "class": "LocalScript", "sourceBytes": 3050,
        "sourceSha256": "afba9523a104afb621e10976d7a235b01951d319c38eb9fc1656c74b44ccfff8"},
}

def read(path): return json.loads(path.read_text())
def sha(path):
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024),b""): digest.update(block)
    return digest.hexdigest()

def source_inventory(rows):
    """Recompute every Source hash before comparing captured metadata."""
    index={}
    for row in rows:
        path=row["path"]
        assert path not in index, f"Source path collision: {path}"
        body=row["source"].encode("utf-8")
        digest=hashlib.sha256(body).hexdigest()
        assert len(body)==row["sourceBytes"], f"Source byte count mismatch: {path}"
        assert digest==row["sourceSha256"]==row["editorSourceSha256"], f"Source/editor digest mismatch: {path}"
        assert row["editorMatch"] is True, f"Source/editor conflict: {path}"
        index[path]={"class":row["class"],"sourceBytes":len(body),"sourceSha256":digest}
    return index

def compare_prior_sources(prior, current):
    removed=sorted(set(prior)-set(current))
    added=sorted(set(current)-set(prior))
    changed=[{"path":path,"before":prior[path],"after":current[path]}
             for path in sorted(set(prior)&set(current)) if prior[path]!=current[path]]
    exact_removed=(removed==sorted(REMOVED_QA) and all(prior.get(path)==pin for path,pin in REMOVED_QA.items()))
    return {"allPriorSourcesPreservedExceptRemovedQA":exact_removed and not added and not changed,
            "exactTwoKnownQARemovals":exact_removed,
            "removedSources":[{"path":path,**prior[path]} for path in removed],
            "addedSources":[{"path":path,**current[path]} for path in added],
            "changedSources":changed,
            "retainedExactSourceCount":len(set(prior)&set(current))-len(changed)}

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
        subprocess.run([sys.executable,str(TASK/"finalize-publication-checkpoint.py")],check=True,cwd=ROOT)
        metadata=read(DEST/"metadata.json")
        chunks=[DEST/f"native-part-{index:05d}.bin" for index in range(metadata["nativeParts"])]
        assert all(path.is_file() for path in chunks),"Native transfer/reuse chunks missing"
        digest=hashlib.sha256();count=0
        for path in chunks:
            value=path.read_bytes();digest.update(value);count+=len(value)
        assert count==metadata["nativeBytes"] and digest.hexdigest()==metadata["nativeSHA256"],"Native chunk reconstruction mismatch"
        assert sha(DEST/"all-service-children.rbxm")==metadata["nativeSHA256"]
        proof=read(DEST/"checkpoint-reuse-proof.json")
        place=DEST/"PublishLobbyPolish-AuthoritativeStudio.rbxl"
        if not proof["reused"]:
            subprocess.run([str(args.lune),"run",str(ROOT/"tools/level6_build/import/pack_native_backup.luau"),str(DEST)],check=True,cwd=ROOT)
            made=DEST/"BeforeLevel6-AuthoritativeStudio.rbxl"
            assert made.is_file(),"New reconstructed native place missing"
            shutil.copy2(made,place)
        assert place.is_file(),"Native place missing"
        reopened=DEST/"native-recovery-reopen-verification.json"
        subprocess.run([str(args.lune),"run",str(ROOT/"artifacts/lobby-rebuild-r4-20261001/verify_r4_native_recovery.luau"),str(DEST),str(place),str(reopened)],check=True,cwd=ROOT)
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
        # Recovery verification is independent of permission to publish.
        sources=read(DEST/"scripts.json")
        source_index={row["path"]:row for row in sources}
        assert len(source_index)==len(sources),"Publication Source path collision"
        current_inventory=source_inventory(sources)
        prior_metadata=read(PREVIOUS/"metadata.json")
        assert prior_metadata["captureId"]==PRIOR_CAPTURE_ID and prior_metadata["nativeSHA256"]==PRIOR_NATIVE_SHA
        assert sha(PREVIOUS/"scripts.json")==PRIOR_SOURCE_CATALOG_SHA,"Prior Source catalog changed"
        prior_inventory=source_inventory(read(PREVIOUS/"scripts.json"))
        assert len(prior_inventory)==prior_metadata["scriptCount"]==229
        source_delta=compare_prior_sources(prior_inventory,current_inventory)
        qa_paths=sorted(REMOVED_QA)
        qa_present=[path for path in qa_paths if path in source_index]
        expected=read(TASK/"expected-source-pins.json")
        assert len(expected)==11 and len({row["path"] for row in expected})==11
        source_checks=[]
        for pin in expected:
            row=source_index.get(pin["path"])
            ok=bool(row and row["class"]==pin["class"] and row["editorMatch"] is True
                    and row["sourceSha256"]==row["editorSourceSha256"]==pin["sourceSha256"]
                    and row["sourceBytes"]==pin["sourceBytes"])
            source_checks.append({"path":pin["path"],"class":pin["class"],"expectedSHA256":pin["sourceSha256"],
                                  "capturedSHA256":row["sourceSha256"] if row else None,"passed":ok})
        preflight={"schema":"lobby-polish-publication-captured-source-preflight-v1",
            "captureId":metadata["captureId"],"nativeSHA256":metadata["nativeSHA256"],
            "sourceCount":len(sources),"expectedSourceCount":227,
            "exact11PinnedSources":all(row["passed"] for row in source_checks),"sourceChecks":source_checks,
            "temporaryQAPresent":qa_present,"temporaryQAAbsent":not qa_present,
            "sourceAndEditorConflicts":0,"nativeRecoveryVerified":True,
            "priorCaptureId":PRIOR_CAPTURE_ID,"priorNativeSHA256":PRIOR_NATIVE_SHA,
            "priorSourceCatalogSHA256":PRIOR_SOURCE_CATALOG_SHA,
            "currentSourceCatalogSHA256":sha(DEST/"scripts.json"),
            "priorSourceCount":len(prior_inventory),"sourceDelta":source_delta,
            "sourceInventory":[{"path":path,**current_inventory[path]} for path in sorted(current_inventory)],
            "publicationPreflightPassed":not qa_present and len(sources)==227 and all(row["passed"] for row in source_checks)
                and source_delta["allPriorSourcesPreservedExceptRemovedQA"],
            "publicationAuthorized":False,"studioWrites":False,
            "limits":"Captured disk proof only. Root must recheck live Source/editor and QA absence immediately before an actual Studio publish; this does not authorize or claim publication."}
        (DEST/"publication-source-preflight.json").write_text(json.dumps(preflight,indent=2)+"\n")
        receipt["publicationPreflightPassed"]=preflight["publicationPreflightPassed"]
        receipt["publicationAuthorized"]=False
        receipt["publicationSourcePreflightSHA256"]=sha(DEST/"publication-source-preflight.json")
        GATE.write_text(json.dumps(receipt,indent=2)+"\n")
        print(json.dumps({"verified":True,"captureId":receipt["captureId"],"nativeSHA256":receipt["nativeSHA256"],"gate":str(GATE)}))
    except Exception as error:
        GATE.write_text(json.dumps({"verified":False,"reason":str(error)},indent=2)+"\n")
        raise

if __name__=="__main__": main()
