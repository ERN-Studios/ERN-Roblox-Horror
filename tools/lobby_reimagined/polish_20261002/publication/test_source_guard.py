"""Local fixtures for publication catalog closure; no Studio/Git operations."""
from pathlib import Path
import copy
import hashlib
import json


def main():
    helper=Path(__file__).with_name("verify-publication-checkpoint.py")
    module={"__file__":str(helper),"__name__":"publication_guard_fixture"}
    exec(compile(helper.read_bytes(),str(helper),"exec"),module)
    inventory=module["source_inventory"]
    compare=module["compare_prior_sources"]
    qa=copy.deepcopy(module["REMOVED_QA"])
    stable={"class":"ModuleScript","sourceBytes":4,"sourceSha256":hashlib.sha256(b"test").hexdigest()}
    prior={"ServerScriptService.Retained":stable,**qa}
    current={"ServerScriptService.Retained":copy.deepcopy(stable)}
    checks=[]
    def record(name,passed):
        assert passed,name
        checks.append({"name":name,"passed":True})
    record("Exact retained inventory and two pinned QA removals pass",compare(prior,current)["allPriorSourcesPreservedExceptRemovedQA"])
    added={**current,"ServerScriptService.UnrelatedAdded":stable}
    record("Unrelated added Source fails",not compare(prior,added)["allPriorSourcesPreservedExceptRemovedQA"])
    changed=copy.deepcopy(current);changed["ServerScriptService.Retained"]["sourceSha256"]="0"*64
    record("Unrelated changed Source fails",not compare(prior,changed)["allPriorSourcesPreservedExceptRemovedQA"])
    record("Extra removal fails",not compare(prior,{})["allPriorSourcesPreservedExceptRemovedQA"])
    record("QA retained fails",not compare(prior,prior)["allPriorSourcesPreservedExceptRemovedQA"])
    altered=copy.deepcopy(prior);altered[next(iter(qa))]["sourceSha256"]="0"*64
    record("Unpinned QA deletion fails",not compare(altered,current)["allPriorSourcesPreservedExceptRemovedQA"])
    row={"path":"ServerScriptService.Retained","class":"ModuleScript","source":"test","sourceBytes":4,
         "sourceSha256":stable["sourceSha256"],"editorSourceSha256":stable["sourceSha256"],"editorMatch":True}
    record("Every Source body is independently hashed",inventory([row])[row["path"]]==stable)
    def rejected(rows):
        try: inventory(rows)
        except AssertionError: return True
        return False
    record("Duplicate Source path fails",rejected([row,row]))
    for field,value,name in (("sourceBytes",5,"Wrong byte count fails"),("sourceSha256","0"*64,"Wrong Source hash fails"),
                             ("editorSourceSha256","0"*64,"Wrong editor hash fails"),("editorMatch",False,"Editor conflict fails")):
        bad={**row,field:value}
        record(name,rejected([bad]))
    print(json.dumps({"schema":"lobby-polish-publication-source-guard-fixtures-v1","passed":True,
        "fixtureCount":len(checks),"checks":checks,"helperSHA256":hashlib.sha256(helper.read_bytes()).hexdigest(),
        "scope":"Synthetic source-catalog fixtures only; actual native backup and captured preflight are separate.",
        "studioOrGitWrites":False},indent=2))


if __name__=="__main__": main()
