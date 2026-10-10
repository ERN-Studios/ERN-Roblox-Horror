"""Actual wrapper filesystem/CAS/rollback ports; native boundary only is fake.

No production/native calls, no real network, no real git mutations. Business
behavior is tested separately by the immutable 105/105 current actual UI contracts and 197-proto compiler equivalence.
"""
from pathlib import Path
import copy
import argparse
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("apply_c26", Path(__file__).with_name("apply_c26_comments_cleanup.py"))
app = importlib.util.module_from_spec(spec);spec.loader.exec_module(app)
ROOT = app.ROOT
checks = 0


def check(value, message):
    global checks
    checks += 1
    assert value, message


def setup(root):
    before, after, old, newer, request, template = app.scope()
    proof=json.loads((ROOT/app.ART/"proof.json").read_bytes())
    for relative in (app.ART+"/proof.json",app.ART+"/native-baseline-v1/result.json",*proof["portableInputs"].values()):
        target=root/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((ROOT/relative).read_bytes())
    rows = []
    items = []
    target = old["originals"][0]
    for i in range(212):
        if i == 0:
            row = {key: copy.deepcopy(target[key]) for key in ("segments", "studioPath", "instanceId", "parentId", "className", "properties", "attributes", "tags")}
            file = app.TARGET_FILE;body = before
        else:
            row = {"segments": ["ServerScriptService", "fixture" + str(i)], "studioPath": "ServerScriptService.fixture" + str(i),
                   "instanceId": "fixture" + str(i), "parentId": "fixtureParent", "className": "ModuleScript",
                   "properties": {"Archivable": True, "LinkedSource": ""}, "attributes": [], "tags": []}
            file = "ServerScriptService/fixture" + str(i) + ".ModuleScript.lua";body = ("return " + str(i) + "\n").encode()
        row["sha256"] = app.sha(body);row["bytes"] = len(body);rows.append(row)
        path = root / file;path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(body)
        items.append({**{key: copy.deepcopy(row[key]) for key in ("studioPath", "segments", "className", "properties", "attributes")},
                      "file": file, "sha256": row["sha256"], "bytes": row["bytes"], "sourceEditorMatches": True, "status": "synced"})
    raw = app.encoded({"counts": {"scripts": 212, "remoteEvents": 15, "total": 227}, "items": items, "ownerMetadata": "preserve"})
    (root / app.MANIFEST).write_bytes(raw)
    return before, after, request, rows, raw


class FakeClient:
    def __init__(self, root, mode, before, after, rows):
        self.root, self.scenario, self.before, self.after = root, mode, before, after
        self.rows = copy.deepcopy(rows);self.source = before;self.calls = [];self.observeCount = 0
        self.closed = False;self.nativeWrites = 0

    def initialize(self): pass
    def close(self): self.closed = True

    def observation(self, operation, request=None):
        self.rows[0]["sha256"] = app.sha(self.source);self.rows[0]["bytes"] = len(self.source)
        summary=copy.deepcopy(self.rows[0]);summary.pop("sha256")
        summary.update(sourceSHA256=app.sha(self.source),editorSHA256=app.sha(self.source),sourceEditorMatches=True,editorBytes=len(self.source))
        value={"pass":True,"operation":operation,"target":summary}
        if operation!="target":
            first=request["pageFirst"]
            value.update(rows=copy.deepcopy(self.rows[first-1:first+19]),totalRows=212,pageFirst=first,pageCount=20,
                         catalogSHA256=app.sha(app.encoded(self.rows)))
            if self.scenario=="catalogDrift" and first==21:value["catalogSHA256"]="f"*64
            if self.scenario=="shortPage" and first==21:value["rows"].pop()
        return value

    def call(self, name, args):
        self.calls.append(name)
        if name == "get_studio_state":
            return "Current Studio Mode: Play" if self.scenario == "play" else "Current Studio Mode: Edit"
        if name == "get_console_output":
            return "new unexpected console message" if self.scenario == "console" and self.source == self.after else "console baseline"
        code = args["code"]
        if "local lineCount = 1" in code:
            data=self.source;digest=5381
            for byte in data:digest=(digest*33+byte)%4294967296
            return str(len(data))+"\t"+str(digest)+"\t"+str(data.count(b"\n")+1)+"\tModuleScript"
        if "local first, count =" in code:
            first,count=map(int,re.search(r"local first, count = (\d+), (\d+)",code).groups())
            assert count==64,"actual helper chunk must be bounded"
            if self.scenario=="chunkFailure":raise RuntimeError("controlled chunk transport failure")
            return "\n".join(self.source.decode().split("\n")[first-1:first-1+count])
        assert 'local request=H:JSONDecode(' in code, "No native runtime ModuleScript probe belongs to this comment-only installer"
        match = re.search(r'local request=H:JSONDecode\(string.sub\(\[=\[_([^\n]+)\]=\],2\)\)', code)
        assert match, "Actual generated request literal parser"
        request = json.loads(match[1]);operation = request["operation"];self.calls.append(operation)
        if operation == "capture":
            if self.scenario=="truncatedCapture":return '{"pass":true,"rows":['
            if self.scenario=="oversizedCapture":return "x"*20001
            return json.dumps(self.observation(operation,request))
        if operation=="target":
            if self.scenario=="observeUnknown" and self.source==self.after:raise RuntimeError("controlled unreadable native outcome")
            return json.dumps(self.observation(operation,request))
        if operation == "observe":
            self.observeCount += 1
            if self.scenario == "observeUnknown": raise RuntimeError("controlled unreadable native outcome")
            return json.dumps(self.observation(operation,request))
        if operation=="verify":
            return json.dumps({"pass":True,"operation":"verify","sourceSHA256":app.sha(self.source),"originalSourceCoverage":212})
        if operation == "apply":
            if self.scenario == "beforeWrite": raise RuntimeError("controlled before native write")
            if self.scenario == "foreignNative":
                self.source = b"foreign native actor source\n";raise RuntimeError("controlled foreign native outcome")
            self.source = self.after;self.nativeWrites += 1
            if self.scenario in ("commitThenError", "observeUnknown"): raise RuntimeError("controlled commit then transport error")
            return json.dumps({"pass": True, "sourceSHA256": app.sha(self.source)})
        assert operation == "rollback"
        assert self.source == self.after, "Only own native candidate rollback"
        self.source = self.before;self.nativeWrites += 1
        return json.dumps({"pass": True, "sourceSHA256": app.sha(self.source)})


def main(receipt=None):
    starting = {path: (ROOT / path).read_bytes() for path in (app.TARGET_FILE, app.MANIFEST)}
    cases = []
    for scenario in ("success", "play", "beforeWrite", "commitThenError", "observeUnknown", "foreignNative", "replay", "actorManifest", "actorSource", "actorTargetRow", "console", "truncatedCapture", "oversizedCapture", "shortPage", "catalogDrift", "chunkFailure"):
        with tempfile.TemporaryDirectory(prefix="mongotv-c26-comments-wrapper-") as directory:
            root = Path(directory);before, after, request, rows, raw = setup(root)
            client = FakeClient(root, scenario, before, after, rows)
            def git_reader(_root, *args): return b"fixtureHead\n" if args[0] == "rev-parse" else raw
            ok = True
            def contract_runner(_root,destination):
                if scenario == "actorManifest":
                    data=json.loads((root/app.MANIFEST).read_bytes());data["ownerMetadata"]="new actor metadata"
                    data["items"][1]["ownerFlag"]="preserve actor row";(root/app.MANIFEST).write_bytes(app.encoded(data))
                elif scenario == "actorSource":(root/app.TARGET_FILE).write_bytes(b"owner changed source\n")
                elif scenario == "actorTargetRow":
                    data=json.loads((root/app.MANIFEST).read_bytes());data["items"][0]["sha256"]="f"*64;data["items"][0]["bytes"]=777
                    (root/app.MANIFEST).write_bytes(app.encoded(data))
                result={"pass":scenario not in ("replay","actorManifest","actorSource","actorTargetRow"),"boundary":"fake offline contract result only"}
                app.save(destination/"installed-contract-result.json",app.encoded(result));return result
            try: app.apply(root, lambda: client, git_reader, contract_runner=contract_runner)
            except (AssertionError,ValueError): ok = False
            result = json.loads((root / app.DEST / "result.json").read_bytes())
            check(ok == (scenario == "success"), scenario + " expected wrapper outcome")
            check(client.closed, scenario + " independent client cleanup")
            check(result["pass"] == ok, scenario + " truthful receipt outcome")
            check((root / app.CHECKPOINT / "repo-source.before.bin").read_bytes() == before, scenario + " exact private rollback input")
            if scenario == "success":
                check(client.source == after and (root / app.TARGET_FILE).read_bytes() == after, "verified native export only")
                check(result["afterParity"]["scripts"] == 212, "all 212 source mirrors checked")
                changed = json.loads((root / app.MANIFEST).read_bytes());original = json.loads(raw)
                changed["items"][0]["sha256"] = original["items"][0]["sha256"];changed["items"][0]["bytes"] = original["items"][0]["bytes"]
                check(changed == original, "only two fields of target row changed")
            elif scenario == "foreignNative":
                check(client.source == b"foreign native actor source\n" and client.nativeWrites == 0, "foreign native Source never overwritten")
            elif scenario == "observeUnknown":
                check(client.source == after and client.nativeWrites == 1, "unknown native outcome receives no blind restore")
                check("unknown outcome" in result["rollback"]["native"], "ambiguity explicit in receipt")
            else: check(client.source == before, scenario + " before source kept or own candidate rolled back")
            if scenario == "actorSource": check((root / app.TARGET_FILE).read_bytes() == b"owner changed source\n", "foreign local source preserved")
            elif scenario != "success": check((root / app.TARGET_FILE).read_bytes() == before, scenario + " local source rollback")
            if scenario == "actorManifest":
                live = json.loads((root / app.MANIFEST).read_bytes())
                check(live["ownerMetadata"] == "new actor metadata" and live["items"][1]["ownerFlag"] == "preserve actor row", "actor metadata/other row preserved on rollback")
                check(app.item(live)["sha256"] == app.sha(before), "only own manifest Source fields reversed")
            if scenario == "actorTargetRow":
                live = json.loads((root / app.MANIFEST).read_bytes())
                check(live["items"][0]["sha256"] == "f" * 64 and live["items"][0]["bytes"] == 777, "foreign target Source row preserved")
            if scenario in ("beforeWrite", "play", "truncatedCapture", "oversizedCapture", "shortPage", "catalogDrift", "chunkFailure"): check(client.nativeWrites == 0, "prewrite rejection makes no native write")
            cases.append({"scenario": scenario, "pass": True, "nativeBoundary": "fake only; actual wrapper/files/manifest/CAS/rollback executed"})
    check(all((ROOT / path).read_bytes() == raw for path, raw in starting.items()), "canonical Source/manifest unchanged by tests")
    transform = actual_transform_checks()
    proof = {"pass": True, "cases": cases, "checks": checks, "nativeCalls": 0, "productionWrites": 0,
             "actualNativeTransform": transform,
             "wrapperSHA256": app.sha(Path(app.__file__).read_bytes()), "templateSHA256": app.sha(Path(app.__file__).with_name("c26_comments_source_cas.luau").read_bytes()),
             "limits": "Fake MCP/native/console/git boundaries; actual filesystem and wrapper operations. Real native source CAS and global after-port remain parent-owned."}
    destination = receipt or ROOT / app.ART / "c26-comments-source-proposal-v1/offline-wrapper-tests-final.json"
    app.save(destination, app.encoded(proof));print(json.dumps({"pass": True, "cases": len(cases), "checks": checks, "nativeCalls": 0}))


def actual_transform_checks():
    before,after,_,_,_,template=app.scope()
    start=template.index("local replacements=request.commentPatches")
    stop=template.index("SES:UpdateSourceAsync(target",start)
    body=template[start:stop]
    source='''local request={operation="apply",commentPatches=__PATCHES__}
local before=__BEFORE__
local after=__AFTER__
local beforeSHA=__BEFORESHA__
local afterSHA=__AFTERSHA__
local toHash=afterSHA
local checks=0
local function check(v,why)checks+=1;assert(v,why)end
local function sha(value)
 if value==before then return beforeSHA elseif value==after then return afterSHA else return "unrecognized fixture bytes" end
end
__ACTUAL_TRANSFORM__
check(transform(before)==after,"actual ten-comment-anchor apply is exact saved candidate")
request.operation="rollback";toHash=beforeSHA
check(transform(after)==before,"actual reverse-anchor rollback is exact saved before")
request.operation="apply";toHash=afterSHA
local duplicate=before..replacements[1].old
local missing=before:gsub("Used by BriefingFitMatrix only","Changed comment anchor")
for _,entry in {{duplicate,"Unique scoped comment anchor required"},{missing,"Unique scoped comment anchor required"}} do
 local ok,err=pcall(transform,entry[1])
 check(not ok,"actual transform rejects changed/ambiguous anchor")
 check(tostring(err):find(entry[2],1,true)~=nil,"intended exact-anchor gate rejects")
end
toHash="foreign expected hash"
local ok,err=pcall(transform,before)
check(not ok,"actual transform rejects changed candidate SHA")
check(tostring(err):find("Scoped replacement result differs",1,true)~=nil,"intended final SHA gate rejects")
print("TRANSFORM_CASES=5 CHECKS="..checks)
'''
    proof=json.loads((ROOT/app.ART/"proof.json").read_bytes())
    patch_table="{"+",".join("{old="+app.helpers.lua_literal(p["old"])+",new="+app.helpers.lua_literal(p["new"])+"}" for p in proof["commentPatches"])+"}"
    source=source.replace("__PATCHES__",patch_table)
    for key,value in {"__BEFORE__":app.helpers.lua_literal(before.decode()),"__AFTER__":app.helpers.lua_literal(after.decode()),
                      "__BEFORESHA__":app.helpers.lua_literal(app.sha(before)),"__AFTERSHA__":app.helpers.lua_literal(app.sha(after)),
                      "__ACTUAL_TRANSFORM__":body}.items():source=source.replace(key,value)
    compiles=[]
    with tempfile.TemporaryDirectory(prefix="mongotv-c26-comments-native-transform-") as directory:
        p=Path(directory)/"actual-transform.luau";p.write_bytes(source.encode())
        for opt in ("-O0","-O1"):
            run=subprocess.run([str(app.COMPILER),"--binary",opt,str(p)],capture_output=True,timeout=15)
            assert run.returncode==0,run.stderr.decode(errors="replace")
            compiles.append({"optimization":opt,"pass":True})
        run=subprocess.run([str(app.COMPILER.with_name("luau.exe")),str(p)],capture_output=True,text=True,timeout=15)
        assert run.returncode==0,run.stdout+run.stderr
        count=int(re.search(r"TRANSFORM_CASES=5 CHECKS=(\d+)",run.stdout)[1])
    return {"pass":True,"cases":5,"checks":count,"compileChecks":compiles,"fixtureSHA256":app.sha(source.encode()),
            "actualTransformSHA256":app.sha(body.encode()),"scope":"Actual native-template ten exact comment anchors/forward/reverse transform; known exact body SHA boundary, not real ScriptEditorService callback or native guard certification."}


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--receipt",type=Path)
    main(parser.parse_args().receipt)
