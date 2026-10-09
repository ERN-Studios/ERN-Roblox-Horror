"""Prepare/apply only seven verified source rows and two missing source entries.

Default is local-only proposal preparation. Root uses --apply after reviewing it.
Fresh native seven-source CAS and exact current global-file/HEAD checks precede
the write. All non-target rows/fields remain intact; no Studio writes/backups/git.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode=True
from refresh_verified_source import HERE,TASK,ROOT,EXPORT,read_native,reviewed_rows

GLOBAL=ROOT/"studio-sync-manifest.json"
PLAN=HERE/"global-manifest-plan.json"
PROPOSED=HERE/"studio-sync-manifest.proposed.json"
RECEIPT=HERE/"global-manifest-refresh-receipt.json"


def sha(raw):return hashlib.sha256(raw).hexdigest()


def git(*args):
    result=subprocess.run(["git",*args],cwd=ROOT,capture_output=True)
    assert result.returncode==0,result.stderr.decode("utf-8",errors="replace")
    return result.stdout


def construct(current,pins):
    proposed=copy.deepcopy(current)
    targets={pin["path"]:pin for pin in pins}
    original_targets={row["studioPath"]:row for row in current["items"] if row["studioPath"] in targets}
    assert len(original_targets)==len([row for row in current["items"] if row["studioPath"] in targets]),"Duplicate target row"
    changed=[]
    for path,pin in targets.items():
        item=next((row for row in proposed["items"] if row["studioPath"]==path),None)
        relative=Path(*pin["segments"][:-1])/(pin["segments"][-1]+"."+pin["class"]+".lua")
        mirror=(ROOT/relative).read_bytes()
        assert len(mirror)==pin["rawBytes"] and sha(mirror)==pin["sourceSha256"],"Runtime mirror differs from verified native export: "+path
        if item is None:
            item={"studioPath":path,"segments":pin["segments"],"className":pin["class"],"file":relative.as_posix(),
                "properties":pin["properties"],"attributes":pin["attributes"]}
            proposed["items"].append(item)
            action="add-missing-verified-source"
        else:
            assert item["className"]==pin["class"] and item["segments"]==pin["segments"] and item["file"]==relative.as_posix(),"Target identity/path differs in current global manifest"
            action="refresh-source-fields"
        item.update(bytes=pin["rawBytes"],sha256=pin["sourceSha256"],status="synced",sourceEditorMatches=True)
        item.pop("studioTrailingNewline",None)
        changed.append({"studioPath":path,"action":action,"currentSha256":original_targets.get(path,{}).get("sha256"),
            "verifiedNativeSha256":pin["sourceSha256"],"runtimeMirrorSha256":sha(mirror),"bytes":len(mirror)})
    counts=proposed["counts"]
    counts["scripts"]=sum(row["className"] in {"Script","LocalScript","ModuleScript"} for row in proposed["items"])
    counts["total"]=len(proposed["items"])
    counts["studioTrailingNewline"]=sum(row.get("studioTrailingNewline") is True for row in proposed["items"])
    # These are historic whole-export operation totals, not refreshed counts.
    # Remote-event rows/count and every other count/top-level field are preserved.
    assert [row for row in proposed["items"] if row["studioPath"] not in targets]==[row for row in current["items"] if row["studioPath"] not in targets]
    for key in current:
        if key not in {"items","counts"}:assert proposed[key]==current[key]
    for path,previous in original_targets.items():
        after=next(row for row in proposed["items"] if row["studioPath"]==path)
        for key in previous:
            if key not in {"bytes","sha256","status","sourceEditorMatches","studioTrailingNewline"}:assert after[key]==previous[key]
    return proposed,changed


def prepare():
    assert not PLAN.exists() and not PROPOSED.exists(),"Preserve prior prepared plan/history; root must review before a new plan"
    refresh=json.loads((HERE/"verified-source-refresh-receipt.json").read_text(encoding="utf-8"))
    assert refresh["complete"] and refresh["applyMirrors"]
    pins=refresh["nativeEnd"]["pins"]
    assert len(pins)==7
    raw=GLOBAL.read_bytes();current=json.loads(raw)
    assert current["placeId"]==131311258779917 and current["universeId"]==10559217407
    proposed,changed=construct(current,pins)
    head=git("rev-parse","HEAD").decode().strip()
    head_raw=git("show","HEAD:studio-sync-manifest.json")
    head_items={row["studioPath"]:row for row in json.loads(head_raw)["items"]}
    for row in changed:
        row["headSha256"]=head_items.get(row["studioPath"],{}).get("sha256")
        row["headEntryPresent"]=row["studioPath"] in head_items
        row["currentDiffersFromHead"]=row["currentSha256"]!=row["headSha256"]
    after=(json.dumps(proposed,indent=2,ensure_ascii=False)+"\n").encode("utf-8")
    PROPOSED.write_bytes(after)
    plan={"headCommit":head,"headGlobalManifestSha256":sha(head_raw),"currentGlobalManifestSha256":sha(raw),
        "proposedGlobalManifestSha256":sha(after),"proposedFile":PROPOSED.relative_to(ROOT).as_posix(),
        "nativeVerifiedUtc":refresh["nativeEnd"]["verifiedUtc"],"targets":changed,
        "addedSourceEntries":sum(row["action"]=="add-missing-verified-source" for row in changed),
        "preservedAllNonTargetRows":True,"preservedExistingTargetNonSourceFields":True,"preservedUnrelatedTopLevelMetadata":True,
        "countsBefore":current["counts"],"countsAfter":proposed["counts"],"nativeSourcePins":pins,
        "globalManifestWritten":False,"studioMutation":False,"nativeBackup":False,"gitStaged":False,"gitCommitted":False}
    PLAN.write_text(json.dumps(plan,indent=2)+"\n",encoding="utf-8")
    print(f"Prepared {len(changed)} scoped source rows, {plan['addedSourceEntries']} new entries; current dirty manifest/HEAD pinned; global file untouched.")


def apply():
    assert not RECEIPT.exists(),"Preserve prior global refresh receipt"
    plan=json.loads(PLAN.read_text(encoding="utf-8"));proposed=PROPOSED.read_bytes()
    assert sha(proposed)==plan["proposedGlobalManifestSha256"]
    assert git("rev-parse","HEAD").decode().strip()==plan["headCommit"],"HEAD changed; reconcile and prepare a fresh plan"
    before=GLOBAL.read_bytes();assert sha(before)==plan["currentGlobalManifestSha256"],"Concurrent global manifest change; preserve/reprepare from fresh current file"
    native=read_native(reviewed_rows()) # Exact current native Source/editor/id/parent CAS for all seven.
    reconstructed,changed=construct(json.loads(before),native["pins"])
    assert reconstructed==json.loads(proposed),"Native/source metadata changed since review"
    receipt={"nativeFreshCas":native,"headCommit":plan["headCommit"],"beforeGlobalManifestSha256":sha(before),
        "afterGlobalManifestSha256":sha(proposed),"targets":changed,"complete":False,"studioMutation":False,
        "nativeBackup":False,"otherRowsAndFieldsPreserved":True,"gitStaged":False,"gitCommitted":False}
    def save():RECEIPT.write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
    save()
    try:
        assert GLOBAL.read_bytes()==before,"Concurrent global manifest changed immediately before write"
        GLOBAL.write_bytes(proposed)
        assert GLOBAL.read_bytes()==proposed
        receipt["complete"]=True
        print("Scoped seven-row/two-new-source global manifest refresh applied; fresh native CAS and exact local before/after verified.")
    except Exception as error:
        receipt["error"]=f"{type(error).__name__}: {error}";raise
    finally:save()


def main():
    global PLAN,PROPOSED,RECEIPT
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--apply",action="store_true")
    parser.add_argument("--plan",type=Path,default=PLAN)
    parser.add_argument("--proposed",type=Path,default=PROPOSED)
    parser.add_argument("--receipt",type=Path,default=RECEIPT)
    args=parser.parse_args()
    PLAN,PROPOSED,RECEIPT=(path.resolve() for path in (args.plan,args.proposed,args.receipt))
    assert all(path.is_relative_to(HERE) and path.suffix==".json" for path in (PLAN,PROPOSED,RECEIPT)),"Plan/proposed/receipt must remain task-owned JSON files"
    assert len({PLAN,PROPOSED,RECEIPT})==3
    if args.apply:apply()
    else:prepare()


if __name__=="__main__":main()
