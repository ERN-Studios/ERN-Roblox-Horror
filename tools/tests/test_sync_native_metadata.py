"""Actual full-sync loop with fake native/MCP boundaries and owned temp files.

No Studio/network/production Source writes or runtime initializers. Stale proxy
script_read text is distinct from the actual SES metadata protocol exercised
here; authoritative editor conflict always rejects this row's export.
"""
import argparse
import copy
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sync_from_studio as sync
import push_repo_to_studio as push
import studio_source_contract as contract

CHECKS = 0


def check(value, message):
    global CHECKS
    CHECKS += 1
    assert value, message


class NativeBoundary:
    def __init__(self, fault=None):
        self.items = [{"fullPath":"ServerScriptService.Sample", "className":"Script"},
                      {"fullPath":"StarterPlayer.Local", "className":"LocalScript"},
                      {"fullPath":"ReplicatedStorage.Library", "className":"ModuleScript"},
                      {"fullPath":"ReplicatedStorage.Event", "className":"RemoteEvent"}]
        self.sources = {r["fullPath"]:"-- synthetic fixture\r\nreturn 1\r\n" for r in self.items if r["className"] != "RemoteEvent"}
        self.fault = fault
        self.metadata_calls = {}
        self.closed = False
        self.initialized = False
        self.mode = "Edit"

    def initialize(self): self.initialized = True
    def close(self): self.closed = True

    def metadata(self, item):
        path, klass = item["fullPath"],item["className"]
        count = self.metadata_calls.get(path,0)+1;self.metadata_calls[path] = count
        value = {"path":path,"segments":path.split("."),"className":klass,"instanceId":"instance:"+path,
                 "parentId":"parent:"+path.rsplit(".",1)[0],"placeId":sync.EXPECTED_PLACE_ID,"universeId":sync.EXPECTED_UNIVERSE_ID,
                 "properties":{"Archivable":True},"attributes":{"Generation":17,"EnabledMarker":True},"tags":["a","z"]}
        if klass != "RemoteEvent":
            value["properties"]["LinkedSource"] = ""
            raw=self.sources[path].encode();canonical=contract.canonical_bytes(self.sources[path])
            value.update(sourceEditorMatches=True,canonicalBytes=len(canonical),sourceSHA256=hashlib.sha256(canonical).hexdigest(),
                         rawSourceSHA256=hashlib.sha256(raw).hexdigest(),rawEditorSHA256=hashlib.sha256(raw).hexdigest())
        if klass in {"Script","LocalScript"}:
            value["properties"].update(Enabled=True,Disabled=False,RunContext="Enum.RunContext.Server" if klass=="Script" else "Enum.RunContext.Client")
        if path == self.items[0]["fullPath"]:
            if self.fault == "actual-editor-conflict": value["rawEditorSHA256"] = "e"*64;value["sourceEditorMatches"] = False
            if self.fault == "class": value["className"] = "ModuleScript"
            if self.fault == "required-property": value["properties"].pop("Enabled")
            if self.fault == "nonboolean": value["properties"]["Enabled"] = 1
            if self.fault == "noninverse": value["properties"]["Enabled"] = False
            if self.fault == "unsupported-attribute": value["attributes"]["Position"] = {"X":1,"Y":2,"Z":3}
            if self.fault == "wrong-place": value["placeId"] += 1
            if self.fault == "wrong-universe": value["universeId"] += 1
            if self.fault == "malformed": return "not json"
            if count == 2:
                if self.fault == "identity-drift": value["instanceId"] += "actor"
                if self.fault == "parent-drift": value["parentId"] += "actor"
                if self.fault == "property-drift": value["properties"]["Enabled"] = False;value["properties"]["Disabled"] = True
                if self.fault == "attribute-drift": value["attributes"]["Generation"] += 1
                if self.fault == "tag-drift": value["tags"] = ["different"]
                if self.fault == "mode-drift": self.mode = "Play"
        if self.fault == "empty-attributes": value["attributes"] = []
        return json.dumps(value)

    def call(self, tool, arguments=None):
        arguments=arguments or {}
        if tool == "list_roblox_studios":return json.dumps({"studios":[{"id":"fake","name":sync.RELEASE_STUDIO_NAME+f" (placeId: {sync.EXPECTED_PLACE_ID})"}]})
        if tool == "get_studio_state":return f"- Current Studio Mode: {self.mode}\n- Available DataModels: Edit, Server"
        if tool == "search_game_tree":return json.dumps([r for r in self.items if (r["className"]=="RemoteEvent") == (arguments["instance_type"]=="RemoteEvent")])
        assert tool == "execute_luau", "No script_read, native mutations or unexpected API"
        assert arguments["datamodel_type"] == "Edit"
        code=arguments["code"]
        for item in self.items:
            path,klass=item["fullPath"],item["className"]
            if code == sync.native_metadata_code(path.split("."),klass,sync.EXPECTED_PLACE_ID,sync.EXPECTED_UNIVERSE_ID):
                return self.metadata(item)
            if klass == "RemoteEvent":continue
            text=contract.normalize(self.sources[path])
            if self.fault == "returned-source-mismatch" and path==self.items[0]["fullPath"]:text="return 999\n"
            literals=", ".join(push.luau_string(s) for s in path.split("."))
            if code == push.READ_META_LUAU % literals:
                data=text.encode();return f"{len(data)}\t{push.djb2(data)}\t{text.count(chr(10))+1}\t{klass}"
            match=re.search(r"local first, count = (\d+), (\d+)",code)
            if match:
                first,count=map(int,match.groups())
                if code == push.READ_CHUNK_LUAU % (literals,first,count):return "\n".join(text.split("\n")[first-1:first-1+count])
        raise AssertionError("Unknown native read code")


def run_case(fault=None):
    client=NativeBoundary(fault)
    if fault=="initial-play":client.mode="Play"
    with tempfile.TemporaryDirectory(prefix="sync-meta-") as directory:
        root=Path(directory)
        # Stale metadata is deliberately different from the fresh native fixture.
        old={"items":[{"studioPath":r["fullPath"],"file":str(sync.normalized_destination(root,r).relative_to(root)),
                      "className":r["className"],"properties":{"Enabled":False,"Disabled":True,"RunContext":"stale"},
                      "attributes":{"Generation":2},"tags":["old"],"sourceEditorMatches":False} for r in client.items],
             "counts":{},"finalNewlineContract":""}
        before=(json.dumps(old,indent=2)+"\n").encode();manifest=root/"studio-sync-manifest.json";manifest.write_bytes(before)
        first=sync.normalized_destination(root,client.items[0]);first.parent.mkdir(parents=True);first.write_bytes(b"-- existing mirror\nreturn 42\n")
        original=first.read_bytes();caught=None
        args=argparse.Namespace(project_root=root,studio_name=sync.LEGACY_STUDIO_NAME,connect_timeout=1)
        with redirect_stdout(io.StringIO()):
            try:result=sync.sync(args,client_factory=lambda:client)
            except sync.StudioMcpError as error:caught=error
        check(client.initialized and client.closed,"actual sync client lifecycle")
        if fault in (None,"empty-attributes"):
            check(caught is None,"all3 Source classes+remote sync successfully")
            rows={r["studioPath"]:r for r in result["items"]}
            check(len(rows)==4 and result["counts"]["scripts"]==3 and result["counts"]["remoteEvents"]==1,"exact fixture inventory")
            for item in client.items:
                row=rows[item["fullPath"]]
                check(row["segments"]==item["fullPath"].split("."),"fresh path segments")
                check(row["attributes"]==([] if fault else {"Generation":17,"EnabledMarker":True}),"native attrs replace stale attributes and preserve empty-list output")
                check(row["tags"]==["a","z"],"native tags replace stale tags")
                check(client.metadata_calls[item["fullPath"]]==2,"same-row metadata bracket")
                if item["className"] in {"Script","LocalScript"}:
                    check(row["properties"]["Enabled"] is True and row["properties"]["Disabled"] is False,"fresh Enabled/Disabled replace stale flags")
                    check(row["properties"]["RunContext"]==("Enum.RunContext.Server" if item["className"]=="Script" else "Enum.RunContext.Client"),"fresh RunContext")
                else:check("Enabled" not in row["properties"] and "RunContext" not in row["properties"],"unsupported stale BaseScript flags removed")
                check((row.get("sourceEditorMatches") is True)==(item["className"]!="RemoteEvent"),"native editor fact only on Source rows")
            check(first.read_bytes()==contract.canonical_bytes(client.sources[client.items[0]["fullPath"]]),"actual Source reconciliation still uses verified native text")
        else:
            check(caught is not None,"bad native fixture rejected")
            check(first.read_bytes()==original,"affected existing Source mirror unchanged")
            check(manifest.read_bytes()==before,"old manifest retained on rejected first row")
        return {"case":fault or "all-classes-fresh-metadata","pass":True}


def run():
    cases=[run_case(value) for value in (None,"empty-attributes","actual-editor-conflict","class","required-property","nonboolean","noninverse",
          "unsupported-attribute","wrong-place","wrong-universe","malformed","identity-drift","parent-drift","property-drift","attribute-drift",
          "tag-drift","mode-drift","initial-play","returned-source-mismatch")]
    return {"schema":"sync-native-metadata-offline-python-v1","pass":True,"caseCount":len(cases),"assertions":CHECKS,"cases":cases,
            "nativeCalls":0,"productionSourceWrites":0,"scope":"Actual sync loop/reader protocol with fake native boundaries and owned temporary mirrors; not native/gameplay/atomic full-export certification.",
            "toolRawSHA256":hashlib.sha256(Path(sync.__file__).read_bytes()).hexdigest(),"testRawSHA256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--receipt",type=Path);args=parser.parse_args();result=run()
    if args.receipt:
        args.receipt.parent.mkdir(parents=True,exist_ok=True)
        with args.receipt.open("x",encoding="utf8",newline="\n") as stream:stream.write(json.dumps(result,indent=2)+"\n")
    print(json.dumps({k:v for k,v in result.items() if k!="cases"}))
