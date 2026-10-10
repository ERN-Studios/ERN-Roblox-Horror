"""Actual wrapper filesystem/CAS/rollback ports; native boundary only is fake.

No production/native calls, no real network, no real git mutations. Business
behavior is tested separately by the immutable 47/47/94 actual-source contracts.
"""
from pathlib import Path
import copy
import argparse
import importlib.util
import json
import re
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("apply_latch", Path(__file__).with_name("apply_latch_mode_cleanup_v2.py"))
app = importlib.util.module_from_spec(spec);spec.loader.exec_module(app)
ROOT = app.ROOT
checks = 0


def check(value, message):
    global checks
    checks += 1
    assert value, message


def setup(root):
    before, after, old, newer, request, template = app.scope()
    for relative in (app.ART + "/latch-only/proposal.json", app.ART + "/latch-only-v2/proposal.json",
                     app.ART + "/latch-only-v2/native-installed.luau", old["beforeFile"], old["candidateFile"]):
        target = root / relative;target.parent.mkdir(parents=True, exist_ok=True);target.write_bytes((ROOT / relative).read_bytes())
    receipt = {"pass": True, "originalsUnchanged": True, "ownedLeaseReleased": True, "nativeInputSHA256": newer["nativeCodeHashes"]["before"],
               "originalSourceCoverage": 212, "remainingProbes": 0}
    p = root / app.ART / "native-before-v2-result.json";p.write_bytes(app.encoded(receipt))
    rows = []
    items = []
    target = old["originals"][0]
    for i in range(212):
        if i == 0:
            row = {key: copy.deepcopy(target[key]) for key in ("segments", "studioPath", "instanceId", "parentId", "className", "properties", "attributes", "tags")}
            file = app.PUZZLE;body = before
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
            return str(len(data))+"\t"+str(digest)+"\t"+str(data.count(b"\n")+1)+"\tScript"
        if "local first, count =" in code:
            first,count=map(int,re.search(r"local first, count = (\d+), (\d+)",code).groups())
            assert count==64,"actual helper chunk must be bounded"
            if self.scenario=="chunkFailure":raise RuntimeError("controlled chunk transport failure")
            return "\n".join(self.source.decode().split("\n")[first-1:first-1+count])
        if 'local request=H:JSONDecode(' not in code:
            if self.scenario == "replay": return json.dumps({"pass": False})
            if self.scenario == "actorManifest":
                data = json.loads((self.root / app.MANIFEST).read_bytes());data["ownerMetadata"] = "new actor metadata"
                data["items"][1]["ownerFlag"] = "preserve actor row";(self.root / app.MANIFEST).write_bytes(app.encoded(data))
                return json.dumps({"pass": False})
            if self.scenario == "actorSource":
                (self.root / app.PUZZLE).write_bytes(b"owner changed source\n")
                return json.dumps({"pass": False})
            if self.scenario == "actorTargetRow":
                data = json.loads((self.root / app.MANIFEST).read_bytes())
                data["items"][0]["sha256"] = "f" * 64
                data["items"][0]["bytes"] = 777
                (self.root / app.MANIFEST).write_bytes(app.encoded(data))
                return json.dumps({"pass": False})
            return json.dumps({"pass": True, "originalsUnchanged": True, "ownedLeaseReleased": True, "remainingProbes": 0,
                               "contract": {"checksPerVersion": 47, "pairedChecks": 94, "reentryChecks": 94}})
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
    starting = {path: (ROOT / path).read_bytes() for path in (app.PUZZLE, app.MANIFEST)}
    cases = []
    for scenario in ("success", "play", "beforeWrite", "commitThenError", "observeUnknown", "foreignNative", "replay", "actorManifest", "actorSource", "actorTargetRow", "console", "truncatedCapture", "oversizedCapture", "shortPage", "catalogDrift", "chunkFailure"):
        with tempfile.TemporaryDirectory(prefix="mongotv-latch-wrapper-") as directory:
            root = Path(directory);before, after, request, rows, raw = setup(root)
            client = FakeClient(root, scenario, before, after, rows)
            def git_reader(_root, *args): return b"fixtureHead\n" if args[0] == "rev-parse" else raw
            ok = True
            try: app.apply(root, lambda: client, git_reader)
            except (AssertionError,ValueError): ok = False
            result = json.loads((root / app.DEST / "result.json").read_bytes())
            check(ok == (scenario == "success"), scenario + " expected wrapper outcome")
            check(client.closed, scenario + " independent client cleanup")
            check(result["pass"] == ok, scenario + " truthful receipt outcome")
            check((root / app.CHECKPOINT / "repo-source.before.bin").read_bytes() == before, scenario + " exact private rollback input")
            if scenario == "success":
                check(client.source == after and (root / app.PUZZLE).read_bytes() == after, "verified native export only")
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
            if scenario == "actorSource": check((root / app.PUZZLE).read_bytes() == b"owner changed source\n", "foreign local source preserved")
            elif scenario != "success": check((root / app.PUZZLE).read_bytes() == before, scenario + " local source rollback")
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
    proof = {"pass": True, "cases": cases, "checks": checks, "nativeCalls": 0, "productionWrites": 0,
             "wrapperSHA256": app.sha(Path(app.__file__).read_bytes()), "templateSHA256": app.sha(Path(app.__file__).with_name("latch_mode_source_cas_v2.luau").read_bytes()),
             "limits": "Fake MCP/native/console/git boundaries; actual filesystem and wrapper operations. Real native source CAS and global after-port remain parent-owned."}
    destination = receipt or ROOT / app.ART / "latch-source-proposal-v2/offline-wrapper-tests.json"
    app.save(destination, app.encoded(proof));print(json.dumps({"pass": True, "cases": len(cases), "checks": checks, "nativeCalls": 0}))


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--receipt",type=Path)
    main(parser.parse_args().receipt)
