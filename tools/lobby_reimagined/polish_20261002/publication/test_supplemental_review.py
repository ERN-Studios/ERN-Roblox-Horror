"""Local negative fixtures for the one-delta supplemental Source closure."""
from pathlib import Path
import copy
import hashlib
import json


def main():
    helper=Path(__file__).with_name("validate_supplemental_review.py")
    m={"__file__":str(helper),"__name__":"supplemental_review_fixture"}
    exec(compile(helper.read_bytes(),str(helper),"exec"),m)
    actual=json.loads((m["AFTER"]/"publication-source-preflight.json").read_text())["sourceDelta"]
    checks=[]
    def check(name,ok):
        assert ok,name
        checks.append({"name":name,"passed":True})
    check("Exactly reviewed actual captured delta passes",m["closed_delta_passes"](actual))
    def reject(name,mutate):
        delta=copy.deepcopy(actual);mutate(delta)
        check(name,not m["closed_delta_passes"](delta))
    reject("Any added Source fails",lambda d:d["addedSources"].append({"path":"Unrelated"}))
    reject("A second changed Source fails",lambda d:d["changedSources"].append(copy.deepcopy(d["changedSources"][0])))
    reject("Different reviewed path fails",lambda d:d["changedSources"][0].update(path="ServerScriptService.Unrelated"))
    for stage in ("before","after"):
        for field,value in (("class","Script"),("sourceBytes",1),("sourceSha256","0"*64)):
            reject(f"Different {stage} {field} fails",lambda d,s=stage,f=field,v=value:d["changedSources"][0][s].update({f:v}))
    reject("Unpinned QA removals fail",lambda d:d.update(exactTwoKnownQARemovals=False))
    reject("Different retained count fails",lambda d:d.update(retainedExactSourceCount=225))
    reject("False global Source parity cannot pass as this review",lambda d:d.update(allPriorSourcesPreservedExceptRemovedQA=True))
    pins=json.loads(helper.with_name("expected-source-pins.json").read_text())
    inv={p["path"]:{"class":p["class"],"sourceBytes":p["sourceBytes"],"sourceSha256":p["sourceSha256"]} for p in pins}
    check("Eleven exact fixed pins pass",m["pins_pass"](inv,pins))
    check("Missing fixed pin fails",not m["pins_pass"](inv,pins[:-1]))
    changed=copy.deepcopy(inv);changed[pins[0]["path"]]["sourceSha256"]="0"*64
    check("Changed fixed pin fails",not m["pins_pass"](changed,pins))
    check("Duplicate fixed pin fails",not m["pins_pass"](inv,[pins[0]]+pins[1:-1]+[pins[0]]))
    print(json.dumps({"schema":"lobby-polish-publication-supplemental-guard-fixtures-v1","passed":True,
        "fixtureCount":len(checks),"checks":checks,"validatorSHA256":hashlib.sha256(helper.read_bytes()).hexdigest(),
        "limits":"Source closure fixtures only. Actual full captured-state validation and native recovery are separate.",
        "studioOrGitWrites":False},indent=2))


if __name__=="__main__":main()
