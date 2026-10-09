"""In-memory preservation checks; never writes the real global manifest or Studio."""
import copy
import json
import sys

sys.dont_write_bytecode=True
import refresh_global_manifest as tool


def main():
    current=json.loads(tool.GLOBAL.read_text(encoding="utf-8"))
    pins=json.loads((tool.HERE/"verified-source-refresh-receipt.json").read_text(encoding="utf-8"))["nativeEnd"]["pins"]
    targets={row["path"] for row in pins}
    synthetic=copy.deepcopy(current)
    synthetic["ownerConcurrentMetadata"]={"keep":"unrelated metadata"}
    existing=next(row for row in synthetic["items"] if row["studioPath"] in targets)
    existing["ownerConcurrentNote"]="preserve current dirty target metadata"
    existing["properties"]["OwnerProperty"]="preserve"
    unrelated=next(row for row in synthetic["items"] if row["studioPath"] not in targets)
    unrelated["ownerConcurrentSourceRecord"]={"keep":"non-target row work"}
    proposed,changed=tool.construct(synthetic,pins)
    checks=0
    def check(condition):
        nonlocal checks
        assert condition;checks+=1
    check(len(changed)==7)
    check(sum(row["action"]=="add-missing-verified-source" for row in changed)==2)
    check([row for row in proposed["items"] if row["studioPath"] not in targets]==[row for row in synthetic["items"] if row["studioPath"] not in targets])
    check(proposed["ownerConcurrentMetadata"]==synthetic["ownerConcurrentMetadata"])
    updated=next(row for row in proposed["items"] if row["studioPath"]==existing["studioPath"])
    check(updated["ownerConcurrentNote"]==existing["ownerConcurrentNote"] and updated["properties"]["OwnerProperty"]=="preserve")
    for pin in pins:
        row=next(row for row in proposed["items"] if row["studioPath"]==pin["path"])
        check(row["sha256"]==pin["sourceSha256"] and row["bytes"]==pin["rawBytes"] and row["sourceEditorMatches"])
    check(proposed["counts"]["remoteEvents"]==synthetic["counts"]["remoteEvents"])
    check(all(proposed["counts"][key]==synthetic["counts"][key] for key in ("created","updated","unchanged")))
    check(proposed["counts"]["total"]==len(synthetic["items"])+2)
    second,second_changes=tool.construct(proposed,pins)
    check(second==proposed and all(row["action"]=="refresh-source-fields" for row in second_changes))
    duplicate=copy.deepcopy(synthetic);duplicate["items"].append(copy.deepcopy(existing))
    try:tool.construct(duplicate,pins)
    except AssertionError:checks+=1
    else:raise AssertionError("Duplicate target manifest row accepted")
    mismatch=copy.deepcopy(synthetic)
    next(row for row in mismatch["items"] if row["studioPath"]==existing["studioPath"])["className"]="ModuleScript" if existing["className"]!="ModuleScript" else "Script"
    try:tool.construct(mismatch,pins)
    except AssertionError:checks+=1
    else:raise AssertionError("Mismatched target identity accepted")
    receipt={"inMemoryChecks":checks,"realGlobalManifestWritten":False,"studioConnected":False,
        "nonTargetRowsAndDirtyMetadataPreserved":True,"verifiedRuntimeSourcesReadOnly":True}
    (tool.HERE/"global-manifest-plan-test-result.json").write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
    print(f"{checks} in-memory seven-row/new-two-entry preservation checks passed; global manifest and Studio untouched.")


if __name__=="__main__":main()
