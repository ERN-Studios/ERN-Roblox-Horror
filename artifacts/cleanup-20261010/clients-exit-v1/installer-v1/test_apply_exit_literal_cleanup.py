"""Actual wrapper filesystem/CAS/rollback ports; native boundary only is fake.

No production/native calls, no real network, no real git mutations. Business
behavior is tested separately by the immutable 50/50/reentry and 92/92 actual-source contracts.
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
spec = importlib.util.spec_from_file_location("apply_preview", Path(__file__).with_name("apply_exit_literal_cleanup.py"))
app = importlib.util.module_from_spec(spec);spec.loader.exec_module(app)
ROOT = app.ROOT
checks = 0


def check(value, message):
    global checks
    checks += 1
    assert value, message


def setup(root):
    before, after, old, newer, request, template = app.scope()
    files=[app.ART+"/proposal-v1/proposal.json",app.ART+"/native-target-read-v1.json",app.ART+"/prepare_exit_literal.py",
           app.ART+"/verify_exit_neighbors.py",old["beforeFile"],old["candidateFile"]]
    files += [row["file"] for row in newer["closure"] if row["file"] != app.TARGET_FILE]
    for relative in set(files):
        target=root/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((ROOT/relative).read_bytes())
    rows = []
    items = []
    target = old["originals"][0]
    for i in range(213):
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
    raw = app.encoded({"counts": {"scripts": 213, "remoteEvents": 15, "total": 228}, "items": items, "ownerMetadata": "preserve"})
    (root / app.MANIFEST).write_bytes(raw)
    return before, after, request, rows, raw


class FakeClient:
    def __init__(self, root, mode, before, after, rows):
        self.root, self.scenario, self.before, self.after = root, mode, before, after
        self.rows = copy.deepcopy(rows);self.source = before;self.calls = [];self.observeCount = 0
        self.closed = False;self.nativeWrites = 0;self.requests = []

    def initialize(self): pass
    def close(self): self.closed = True

    def _request(self, method, params, timeout=60):
        assert method == "tools/call" and params["name"] == "execute_luau" and timeout == 180
        assert params["arguments"]["datamodel_type"] == "Edit"
        code=params["arguments"]["code"]
        request=self.parse(code)
        assert request["operation"]=="compile"
        assert app.sha(request["compileSources"]["before"].encode())==app.sha(self.before)
        assert app.sha(request["compileSources"]["candidate"].encode())==app.sha(self.after)
        installed=self.source==self.after
        self.requests.append({"method":method,"tool":params["name"],"timeout":timeout,"installed":installed})
        self.calls.append("parserInstalledRequest" if installed else "parserBeforeRequest")
        if self.scenario=="parserBeforeTimeout" or (installed and self.scenario=="installedTimeout"):
            raise RuntimeError("controlled timeout; parser probe may still run")
        if installed and self.scenario in ("actorManifest","actorSource","actorTargetRow"):
            if self.scenario=="actorSource":(self.root/app.TARGET_FILE).write_bytes(b"owner changed source\n")
            else:
                data=json.loads((self.root/app.MANIFEST).read_bytes())
                if self.scenario=="actorManifest":
                    data["ownerMetadata"]="new actor metadata";data["items"][1]["ownerFlag"]="preserve actor row"
                else:data["items"][0].update(sha256="f"*64,bytes=777)
                (self.root/app.MANIFEST).write_bytes(app.encoded(data))
        compiles=[]
        for phase,body in (("Before",self.before),("Candidate",self.after)):
            compiles.append({"phase":phase,"sourceSHA256":app.sha(body),"factorySHA256":app.sha(b"return function()\n"+body+b"\nend\n"),"bytes":len(body),"factoryUncalled":True})
        value={"schema":"mongotv-exit-literal-native-parser-v1","operation":"compile","pass":True,"parserPassed":True,
            "originalsUnchanged":True,"ownedLeaseReleased":True,"sourceSHA256":app.sha(self.source),"borrowedRuntimeState":False,
            "cleanupErrors":[],"clientBodiesExecuted":0,"originalSourceCoverage":213,"probesCreated":2,"probesDestroyed":2,"remainingProbes":0,
            "originalSourceWrites":0,"originalParentWrites":0,"originalPropertyWrites":0,"modeSwitches":0,"compiles":compiles}
        if self.scenario=="parserBeforeFailure" and not installed:value["pass"]=False
        if installed:
            if self.scenario in ("replay","actorManifest","actorSource","actorTargetRow"):value["pass"]=False
            for scenario,field,bad in (("installedCoverage","originalSourceCoverage",212),("installedProbes","probesDestroyed",1),
                ("installedWrites","originalSourceWrites",1),("installedMode","modeSwitches",1),("installedCleanup","cleanupErrors",["controlled owned cleanup error"]),
                ("installedExecuted","clientBodiesExecuted",1),("installedFactory","compiles",[]),("installedLease","ownedLeaseReleased",False)):
                if self.scenario==scenario:value[field]=bad
        text=json.dumps(value)
        if installed and self.scenario=="installedOversized":text="x"*20000
        return {"result":{"content":[{"type":"text","text":text}],"isError":installed and self.scenario=="installedError"}}

    def parse(self,code):
        match=re.search(r'local request=H:JSONDecode\(string.sub\(\[=\[_([^\n]+)\]=\],2\)\)',code)
        assert match,"Actual generated request literal parser"
        return json.loads(match[1])

    def observation(self, operation, request=None):
        self.rows[0]["sha256"] = app.sha(self.source);self.rows[0]["bytes"] = len(self.source)
        summary=copy.deepcopy(self.rows[0]);summary.pop("sha256")
        summary.update(sourceSHA256=app.sha(self.source),editorSHA256=app.sha(self.source),sourceEditorMatches=True,editorBytes=len(self.source))
        if self.scenario=="editorConflict":
            summary["sourceEditorMatches"]=False;summary["editorSHA256"]="f"*64
        if self.scenario=="propertyChanged":
            summary["properties"]["Enabled"]=False;summary["properties"]["Disabled"]=True
        if self.scenario=="classChanged":summary["className"]="ModuleScript"
        if self.scenario=="identityChanged":summary["instanceId"]="foreign-instance-id"
        value={"pass":True,"operation":operation,"target":summary}
        if operation!="target":
            first=request["pageFirst"]
            value.update(rows=copy.deepcopy(self.rows[first-1:first+19]),totalRows=213,pageFirst=first,pageCount=20,
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
            return str(len(data))+"\t"+str(digest)+"\t"+str(data.count(b"\n")+1)+"\tLocalScript"
        if "local first, count =" in code:
            first,count=map(int,re.search(r"local first, count = (\d+), (\d+)",code).groups())
            assert count==64,"actual helper chunk must be bounded"
            if self.scenario=="chunkFailure":raise RuntimeError("controlled chunk transport failure")
            return "\n".join(self.source.decode().split("\n")[first-1:first-1+count])
        request = self.parse(code);operation = request["operation"];self.calls.append(operation)
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
            return json.dumps({"pass":True,"operation":"verify","sourceSHA256":app.sha(self.source),"originalSourceCoverage":213})
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
    for scenario in ("success", "play", "beforeWrite", "commitThenError", "observeUnknown", "foreignNative", "replay", "actorManifest", "actorSource", "actorTargetRow", "console", "truncatedCapture", "oversizedCapture", "shortPage", "catalogDrift", "chunkFailure", "editorConflict", "propertyChanged", "classChanged", "identityChanged", "postReplaceManifestMetadata", "postReplaceManifestTarget", "postReplaceSourceForeign", "postReplaceSourceFailure", "postReplaceManifestFailure", "installedTimeout", "installedOversized", "installedError", "installedCoverage", "installedProbes", "installedWrites", "installedMode", "installedCleanup", "installedFactory", "installedExecuted", "installedLease", "parserBeforeFailure", "parserBeforeTimeout", "offlineBeforeFailure", "offlineInstalledFailure", "tempSourceEdited", "tempManifestEdited", "tempSourceReplaced", "tempManifestReplaced", "postReplaceSourceForeignTemp", "postReplaceManifestForeignTemp"):
        with tempfile.TemporaryDirectory(prefix="mongotv-preview-wrapper-") as directory:
            root = Path(directory);before, after, request, rows, raw = setup(root)
            client = FakeClient(root, scenario, before, after, rows)
            def git_reader(_root, *args): return b"fixtureHead\n" if args[0] == "rev-parse" else raw
            ok = True
            replace=app.os.replace
            injected=False
            foreign_temp=None
            def replace_then_fault(source,destination):
                nonlocal injected,foreign_temp
                wanted = root / (app.MANIFEST if "Manifest" in scenario else app.TARGET_FILE)
                if scenario.startswith("temp") and not injected and Path(destination)==wanted:
                    injected=True
                    foreign_temp=Path(source)
                    if scenario.endswith("Replaced"):
                        previous=Path(source).read_bytes()
                        Path(source).rename(Path(source).with_name("fixture-held-own-temp.bin"))
                        Path(source).write_bytes(previous) # Same bytes, foreign inode.
                    else:Path(source).write_bytes(b"foreign edited CAS temp\n")
                    raise RuntimeError("controlled foreign temp before actual replace")
                replace(source,destination)
                if not scenario.startswith("postReplace") or injected or Path(destination) != wanted:
                    return
                injected=True
                if scenario=="postReplaceManifestMetadata":
                    data=json.loads(wanted.read_bytes());data["ownerMetadata"]="new actor metadata"
                    data["items"][1]["ownerFlag"]="preserve actor row";wanted.write_bytes(app.encoded(data))
                elif scenario=="postReplaceManifestTarget":
                    data=json.loads(wanted.read_bytes());data["items"][0]["sha256"]="f"*64
                    data["items"][0]["bytes"]=777;wanted.write_bytes(app.encoded(data))
                elif scenario=="postReplaceSourceForeign":wanted.write_bytes(b"owner changed source\n")
                elif scenario.endswith("ForeignTemp"):
                    foreign_temp=Path(source)
                    Path(source).write_bytes(b"foreign recreated CAS temp\n")
                else:raise RuntimeError("controlled exception after actual atomic replace")
            app.os.replace=replace_then_fault
            def offline_runner(_root,destination,installed,a,b):
                assert _root==root and a==before and b==after
                assert app.sha((root/app.TARGET_FILE).read_bytes())==app.sha(after if installed else before)
                if scenario==("offlineInstalledFailure" if installed else "offlineBeforeFailure"):raise AssertionError("controlled actual-port boundary failure")
                return {"pass":True,"installed":installed,"nativeCalls":0,"productionWrites":0,"scope":"controlled offline boundary; actual ports run separately"}
            try:
                try: app.apply(root, lambda: client, git_reader, offline_runner=offline_runner)
                except (AssertionError,ValueError): ok = False
            finally:app.os.replace=replace
            result = json.loads((root / app.DEST / "result.json").read_bytes())
            check(ok == (scenario == "success"), scenario + " expected wrapper outcome")
            check(client.closed, scenario + " independent client cleanup")
            check(result["pass"] == ok, scenario + " truthful receipt outcome")
            check((root / app.CHECKPOINT / "repo-source.before.bin").read_bytes() == before, scenario + " exact private rollback input")
            check(len(client.requests) <= 2, scenario + " no parser retry")
            if scenario == "success":
                check(client.source == after and (root / app.TARGET_FILE).read_bytes() == after, "verified native export only")
                check(result["afterParity"]["scripts"] == 213, "all 213 source mirrors checked")
                changed = json.loads((root / app.MANIFEST).read_bytes());original = json.loads(raw)
                changed["items"][0]["sha256"] = original["items"][0]["sha256"];changed["items"][0]["bytes"] = original["items"][0]["bytes"]
                check(changed == original, "only two fields of target row changed")
            elif scenario == "foreignNative":
                check(client.source == b"foreign native actor source\n" and client.nativeWrites == 0, "foreign native Source never overwritten")
            elif scenario == "observeUnknown":
                check(client.source == after and client.nativeWrites == 1, "unknown native outcome receives no blind restore")
                check("unknown outcome" in result["rollback"]["native"], "ambiguity explicit in receipt")
            elif scenario == "installedTimeout":
                check(client.source == after and client.nativeWrites == 1, "pending installed probe receives no concurrent native rollback")
                check((root/app.TARGET_FILE).read_bytes() == after and app.item(json.loads((root/app.MANIFEST).read_bytes()))["sha256"] == app.sha(after), "pending installed probe keeps its candidate mirrors")
                check("outcome unknown" in result["rollback"]["native"] and len(client.requests) == 2, "pending installed outcome explicit; one bounded request only")
                check(client.calls[-1] == "parserInstalledRequest", "no further native call after pending installed transport outcome")
            else: check(client.source == before, scenario + " before source kept or own candidate rolled back")
            if scenario in ("actorSource","postReplaceSourceForeign"): check((root / app.TARGET_FILE).read_bytes() == b"owner changed source\n", "foreign local source preserved")
            elif scenario not in ("success","installedTimeout"): check((root / app.TARGET_FILE).read_bytes() == before, scenario + " local source rollback")
            if scenario in ("actorManifest","postReplaceManifestMetadata"):
                live = json.loads((root / app.MANIFEST).read_bytes())
                check(live["ownerMetadata"] == "new actor metadata" and live["items"][1]["ownerFlag"] == "preserve actor row", "actor metadata/other row preserved on rollback")
                check(app.item(live)["sha256"] == app.sha(before), "only own manifest Source fields reversed")
            if scenario in ("actorTargetRow","postReplaceManifestTarget"):
                live = json.loads((root / app.MANIFEST).read_bytes())
                check(live["items"][0]["sha256"] == "f" * 64 and live["items"][0]["bytes"] == 777, "foreign target Source row preserved")
            if scenario.startswith("temp") or scenario.endswith("ForeignTemp"):
                temporary=foreign_temp
                check(temporary.exists(),"foreign CAS temp preserved through actual wrapper rollback "+scenario)
                check("Foreign CAS temp" in result["error"],"foreign temp failure documented "+scenario)
                if scenario.endswith("Replaced"):
                    held=temporary.with_name("fixture-held-own-temp.bin")
                    check(temporary.stat().st_ino!=held.stat().st_ino and temporary.read_bytes()==held.read_bytes(),"same-byte foreign temp identity preserved "+scenario)
                else:check(temporary.read_bytes()==(b"foreign edited CAS temp\n" if scenario.startswith("temp") else b"foreign recreated CAS temp\n"),"foreign CAS temp bytes preserved "+scenario)
            if scenario in ("beforeWrite", "play", "truncatedCapture", "oversizedCapture", "shortPage", "catalogDrift", "chunkFailure", "editorConflict", "propertyChanged", "classChanged", "identityChanged", "parserBeforeFailure", "parserBeforeTimeout", "offlineBeforeFailure"): check(client.nativeWrites == 0, "prewrite rejection makes no native write")
            cases.append({"scenario": scenario, "pass": True, "nativeBoundary": "fake only; actual wrapper/files/manifest/CAS/rollback executed"})
    check(all((ROOT / path).read_bytes() == raw for path, raw in starting.items()), "canonical Source/manifest unchanged by tests")
    transform = actual_transform_checks()
    integration = contract_validation_checks()
    exclusive = atomic_exclusive_checks()
    proof = {"pass": True, "cases": cases, "checks": checks, "nativeCalls": 0, "productionWrites": 0,
             "actualNativeTransform": transform,
             "actualParserReceiptIntegration": integration,
             "actualExclusiveFileCAS": exclusive,
             "wrapperSHA256": app.sha(Path(app.__file__).read_bytes()), "templateSHA256": app.sha(Path(app.__file__).with_name("exit_literal_source_cas.luau").read_bytes()),
             "limits": "Fake MCP/native/console/git boundaries; actual filesystem and wrapper operations. Real native source CAS and global after-port remain parent-owned."}
    destination = receipt or ROOT / app.ART / "installer-v1/offline-wrapper-tests-v1.json"
    app.save(destination, app.encoded(proof));print(json.dumps({"pass": True, "cases": len(cases), "checks": checks, "nativeCalls": 0}))


def atomic_exclusive_checks():
    cases=[]
    for label in ("source","manifest"):
        with tempfile.TemporaryDirectory(prefix="mongotv-exit-exclusive-cas-") as directory:
            path=Path(directory)/("source.lua" if label=="source" else "manifest.json")
            before=b"before fixture\n";after=b"candidate fixture\n"
            path.write_bytes(before)
            temporary=path.with_name(path.name+".mongotv-exit-private-locals-fixturecollision-cas.tmp")
            temporary.write_bytes(after)
            identity=(temporary.stat().st_dev,temporary.stat().st_ino)
            original=app.uuid.uuid4
            class FixedIdentity:hex="fixturecollision"
            app.uuid.uuid4=lambda:FixedIdentity()
            rejected=False
            try:
                try:app.atomic_cas(path,before,after)
                except FileExistsError:rejected=True
            finally:app.uuid.uuid4=original
            check(rejected,label+" exclusive temp creation rejects existing foreign same-byte file")
            check(path.read_bytes()==before,label+" failed exclusive creation makes no Source/manifest write")
            check(temporary.read_bytes()==after,label+" failed creation never deletes foreign temp bytes")
            check((temporary.stat().st_dev,temporary.stat().st_ino)==identity,label+" foreign temp identity unchanged")
            cases.append({"label":label,"pass":True})
    return {"pass":True,"cases":cases,"checks":8,"scope":"Actual atomic_cas/exclusive filesystem open with deterministic UUID collision; test-owned files only."}


def contract_validation_checks():
    before,after,_,_,_,_=app.scope()
    client=FakeClient(None,"success",before,after,[])
    _,_,_,_,request,template=app.scope()
    code=app.native_code(template,request,"compile",[],compileSources={"before":before.decode(),"candidate":after.decode()})
    response=client._request("tools/call",{"name":"execute_luau","arguments":{"datamodel_type":"Edit","code":code}},timeout=180)
    receipt={**json.loads(response["result"]["content"][0]["text"]),"nativeInputSHA256":app.sha(code.encode())}
    app.validate_compile(receipt,app.sha(code.encode()),app.sha(before),before,after)
    count=1
    for field,value in (("nativeInputSHA256","f"*64),("sourceSHA256","f"*64),("originalSourceCoverage",212),
                        ("probesDestroyed",1),("originalParentWrites",1),("borrowedRuntimeState",True),("clientBodiesExecuted",1),("compiles",[])):
        altered=copy.deepcopy(receipt);altered[field]=value
        ok=True
        try:app.validate_compile(altered,app.sha(code.encode()),app.sha(before),before,after)
        except AssertionError:ok=False
        assert not ok,"actual parser receipt must reject "+field
        count+=1
    return {"pass":True,"cases":count,"checks":count,"parserTimeoutSeconds":180,
            "limits":"Actual strict validator with controlled parser response; native execution remains Root-owned."}


def actual_transform_checks():
    before,after,_,_,_,template=app.scope()
    start=template.index("local replacements={")
    stop=template.index("-- Native parser port only:",start)
    body=template[start:stop]
    source='''local request={operation="apply"}
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
check(transform(before)==after,"actual one-anchor apply is exact saved candidate")
request.operation="rollback";toHash=beforeSHA
check(transform(after)==before,"actual reverse-anchor rollback is exact saved before")
request.operation="apply";toHash=afterSHA
local duplicate=before..replacements[1].old
local missing=before:gsub("local HINT_HEIGHT","changedPrivateDeclaration")
for _,entry in {{duplicate,"Unique scoped private helper required"},{missing,"Unique scoped private helper required"}} do
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
    for key,value in {"__BEFORE__":app.lua_literal(before.decode()),"__AFTER__":app.lua_literal(after.decode()),
                      "__BEFORESHA__":app.lua_literal(app.sha(before)),"__AFTERSHA__":app.lua_literal(app.sha(after)),
                      "__ACTUAL_TRANSFORM__":body}.items():source=source.replace(key,value)
    compiles=[]
    with tempfile.TemporaryDirectory(prefix="mongotv-preview-native-transform-") as directory:
        p=Path(directory)/"actual-transform.luau";p.write_bytes(source.encode())
        for opt in ("-O0","-O1"):
            run=subprocess.run([str(app.helpers.COMPILER),"--binary",opt,str(p)],capture_output=True,timeout=15)
            assert run.returncode==0,run.stderr.decode(errors="replace")
            compiles.append({"optimization":opt,"pass":True})
        run=subprocess.run([str(app.helpers.LUAU),str(p)],capture_output=True,text=True,timeout=15)
        assert run.returncode==0,run.stdout+run.stderr
        count=int(re.search(r"TRANSFORM_CASES=5 CHECKS=(\d+)",run.stdout)[1])
    return {"pass":True,"cases":5,"checks":count,"compileChecks":compiles,"fixtureSHA256":app.sha(source.encode()),
            "actualTransformSHA256":app.sha(body.encode()),"scope":"Actual native-template one exact anchor/forward/reverse transform; known exact body SHA boundary, not real ScriptEditorService callback or native guard certification."}


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--receipt",type=Path)
    main(parser.parse_args().receipt)
