"""Validate one root-reviewed concurrent test-only delta, without altering gates.

This is a closed captured-state review, not publication or a global parity claim.
It never normalizes native data, runs Studio, writes Source, or changes Git.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json

TASK=Path(__file__).resolve().parent
ROOT=TASK.parents[3]
BEFORE=Path("/private/tmp/lobby-polish-after-20261002")
AFTER=Path("/private/tmp/lobby-polish-publish-20261002")
REVIEW_REL="artifacts/lobby-polish-20261002/publication/review-concurrent-test-suite.json"
BEFORE_CAPTURE="4df9e7f4-49ec-434d-abbf-d2607efa9c2a"
AFTER_CAPTURE="e89b2ace-e45b-4a19-bf49-aafce986ef64"
BEFORE_NATIVE="868f29672e3bda6b501e44d5039880304f3fce989d2934e86ba510834b539b11"
AFTER_NATIVE="7bd1d2e12cb0dc3a284e8f7c135eb18fc8d1d5b2da1a7df3fcaa4a1e01a0a8e9"
PLACE_SHA="60dceb74ee67e2f3df72ce8a6aa036a686b9117410cd1aaa376596718826aeaa"
APPROVED_DELTA={"path":"ServerScriptService.Level 4 Systems.Level 4 Test Suite",
    "before":{"class":"ModuleScript","sourceBytes":5916,"sourceSha256":"f1499854f678f1de6153e9144f39044f7e3073fc590351df7294d4cce88151ff"},
    "after":{"class":"ModuleScript","sourceBytes":6821,"sourceSha256":"59f1cd5e87c72c89a60e0f1c4119a5d931b9084ba9689df1e1b94f06a3869335"}}
BINDINGS=[
    {"label":"priorSourceCatalog","path":str(BEFORE/"scripts.json"),"sha256":"4f26e8f4e929e6372eb34509220091fd7f5946a03cf7a1428c9e85e6eedcdb58"},
    {"label":"currentSourceCatalog","path":str(AFTER/"scripts.json"),"sha256":"1459c7bafa8551413874518eaa1b53ce2658168caf9ef4cdcb627939cd01093c"},
    {"label":"nativeRecovery","path":str(AFTER/"native-recovery-reopen-verification.json"),"sha256":"6fc35b9932fc25e4c3d9e33a60c3b4d35a261292ac4941953c2fdf211dd32f13"},
    {"label":"nativeGate","path":str(AFTER/"checkpoint-install-gate.json"),"sha256":"f2db1546fce719cf10856bbd16c40e48a93eb36c69fa60f93029a94c96028323"},
    {"label":"originalFailedPreflight","path":str(AFTER/"publication-source-preflight.json"),"sha256":"537837a247b62bdb4c37ec0aa0cc3e725516f9af68f7a6221b168deb4e38b038"},
    {"label":"durableBackupReceipt","path":str(AFTER/"durable-publication-backup-receipt.json"),"sha256":"a2883cfefe309ff9ccae8d7f2d0740746c169fb620b2258187031a24d7c940ff"},
    {"label":"capturedMetadata","path":str(AFTER/"metadata.received.json"),"sha256":"16c49c3020a7b00c21169f90de6ff5a22daf754a8f0ac7f4cfcd8b660df462ca"},
    {"label":"finalizedMetadata","path":str(AFTER/"metadata.json"),"sha256":"f135259a22a42a400cb1bfa625d86aee186cacd163a3e1eb322ec7a7a8d88e75"},
]
PIN_SHA="481d2a584db8bff9469c6f496ebdbdb68a89d0e6e0135caa03d76394102ed7a2"
GUARD_SHA="fa541ecf63328d26a3e9e1660642443a7a8a672d3e125cd042182d2531991051"

def read(path):return json.loads(path.read_text())
def sha(path):
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda:stream.read(1024*1024),b""):digest.update(block)
    return digest.hexdigest()

def closed_delta_passes(delta):
    return (delta["exactTwoKnownQARemovals"] is True and delta["addedSources"]==[]
            and delta["changedSources"]==[APPROVED_DELTA] and delta["retainedExactSourceCount"]==226
            and delta["allPriorSourcesPreservedExceptRemovedQA"] is False)

def pins_pass(inventory,pins):
    return (len(pins)==11 and len({p["path"] for p in pins})==11 and all(
        inventory.get(p["path"])=={"class":p["class"],"sourceBytes":p["sourceBytes"],"sourceSha256":p["sourceSha256"]}
        for p in pins))

def validate():
    review_path=ROOT/REVIEW_REL
    review=read(review_path)
    assert set(review)=={"schema","rootReviewAccepted","reviewedBy","decision","captures","bindings",
                         "approvedSourceDelta","expectedPinFileSHA256","scopeLimits"},"Review schema must stay closed"
    assert review["schema"]=="lobby-polish-publication-single-concurrent-delta-review-v1"
    assert review["rootReviewAccepted"] is True and review["reviewedBy"]=="/root"
    assert review["decision"]=="Preserve the exact concurrent test-only delta under the existing owner publish preference; no restoration and no Level 4 gameplay claim."
    assert review["approvedSourceDelta"]==APPROVED_DELTA
    assert review["captures"]=={"prior":BEFORE_CAPTURE,"current":AFTER_CAPTURE,"priorNativeSHA256":BEFORE_NATIVE,
                                "currentNativeSHA256":AFTER_NATIVE,"nativePlaceSHA256":PLACE_SHA}
    assert review["bindings"]==BINDINGS and review["expectedPinFileSHA256"]==PIN_SHA
    assert review["scopeLimits"]=={"sourceDeltaCount":1,"exactKnownQARemovalCount":2,"noAdditionalSourceDeltas":True,
        "originalPreflightRemainsFalse":True,"historicStrictNativeAuditRemainsFalse":True,
        "noNativeNormalization":True,"noSourceOrIndexWrites":True,"noActualPublishByThisTool":True,
        "rootMustRecheckAll227LiveImmediatelyBeforePublish":True}
    for binding in BINDINGS:assert sha(Path(binding["path"]))==binding["sha256"],f"Bound input changed: {binding['label']}"
    guard=TASK/"verify-publication-checkpoint.py"
    assert sha(guard)==GUARD_SHA and sha(TASK/"expected-source-pins.json")==PIN_SHA
    module={"__file__":str(guard),"__name__":"publication_closed_review_guard"}
    exec(compile(guard.read_bytes(),str(guard),"exec"),module)
    before_metadata=read(BEFORE/"metadata.json");after_metadata=read(AFTER/"metadata.json")
    assert before_metadata["captureId"]==BEFORE_CAPTURE and before_metadata["nativeSHA256"]==BEFORE_NATIVE
    assert after_metadata["captureId"]==AFTER_CAPTURE and after_metadata["nativeSHA256"]==AFTER_NATIVE
    assert not after_metadata["editorConflicts"] and not after_metadata["skipped"]
    assert after_metadata["placeId"]==131311258779917 and after_metadata["universeId"]==10559217407
    prior=module["source_inventory"](read(BEFORE/"scripts.json"))
    current=module["source_inventory"](read(AFTER/"scripts.json"))
    assert len(prior)==229 and len(current)==227
    delta=module["compare_prior_sources"](prior,current)
    assert closed_delta_passes(delta),"Captured Source delta differs from the single reviewed change"
    assert all(path not in current for path in module["REMOVED_QA"]),"Temporary QA returned"
    pins=read(TASK/"expected-source-pins.json")
    assert pins_pass(current,pins),"One of the eleven fixed Source/editor pins changed"
    preflight=read(AFTER/"publication-source-preflight.json")
    assert preflight["publicationPreflightPassed"] is False and preflight["sourceDelta"]==delta
    assert preflight["exact11PinnedSources"] is True and preflight["temporaryQAAbsent"] is True
    assert preflight["sourceInventory"]==[{"path":p,**current[p]} for p in sorted(current)]
    gate=read(AFTER/"checkpoint-install-gate.json");native=read(AFTER/"native-recovery-reopen-verification.json")
    durable=read(AFTER/"durable-publication-backup-receipt.json")
    for proof in (gate,native,durable):
        assert proof["verified"] is True and proof["captureId"]==AFTER_CAPTURE
        assert proof["nativeSHA256"]==AFTER_NATIVE and proof["nativePlaceSHA256"]==PLACE_SHA
        assert proof["sourceCount"]==227 and proof["rootCount"]==194
    assert native["sourceErrors"]==native["rootErrors"]==native["sourceEditorConflicts"]==0
    assert native["canonicalNativeForestSHA256"]==native["canonicalReopenedForestSHA256"]
    assert gate["publicationPreflightPassed"] is False and gate["publicationSourcePreflightSHA256"]==sha(AFTER/"publication-source-preflight.json")
    assert durable["publicationPreflightPassed"] is False and durable["fileCount"]==134
    durable_dir=Path(durable["destination"])
    assert durable_dir==Path("/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-lobby-polish/publication")
    assert sha(durable_dir/"durable-publication-backup-receipt.json")==sha(AFTER/"durable-publication-backup-receipt.json")
    assert sha(AFTER/"all-service-children.rbxm")==sha(durable_dir/"all-service-children.rbxm")==AFTER_NATIVE
    assert sha(AFTER/"PublishLobbyPolish-AuthoritativeStudio.rbxl")==sha(durable_dir/"PublishLobbyPolish-AuthoritativeStudio.rbxl")==PLACE_SHA
    return {"schema":"lobby-polish-publication-supplemental-eligibility-validation-v1","verified":True,
        "validatedAtUtc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"reviewSHA256":sha(review_path),
        "validatorSHA256":sha(Path(__file__)),"captures":review["captures"],"boundInputs":BINDINGS,
        "sourceCounts":{"prior":229,"current":227,"retainedExact":226},"sourceDelta":delta,
        "all11SourceEditorPinsExact":True,"temporaryQAAbsent":True,"nativeBackupAndDurableCopyVerified":True,
        "supplementalClosedReviewPassed":True,"originalCapturedPublicationPreflightPassed":False,
        "historicStrictNativeAuditVerified":False,"wholeForestParityClaimed":False,
        "actualPublicationPerformed":False,"studioOrGitWrites":False,
        "limits":"Exactly one root-reviewed concurrent test-only Source delta and two pinned QA removals. No global native normalization, Source restoration, Level 4 gameplay PASS, or publication claim. Root must freshly compare all 227 live Source/editor rows and QA absence immediately before actual Studio publish."}

def main():
    parser=argparse.ArgumentParser();parser.add_argument("--output",type=Path,required=True);args=parser.parse_args()
    receipt=validate()
    assert not args.output.exists(),"Preserve existing review validation receipt"
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(receipt,indent=2)+"\n")
    print(json.dumps({"verified":True,"supplementalClosedReviewPassed":True,"originalCapturedPublicationPreflightPassed":False,
                      "receipt":str(args.output),"receiptSHA256":sha(args.output)}))

if __name__=="__main__":main()
