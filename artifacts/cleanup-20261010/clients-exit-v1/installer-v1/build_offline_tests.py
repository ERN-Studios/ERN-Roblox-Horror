"""Build new narrow wrapper/guard tests from the reviewed S18 test scaffold."""
from pathlib import Path

HERE=Path(__file__).resolve().parent
BASE=HERE.parents[1] / "clients-next-v1/cas-v1"


def put(name,body):
    with (HERE/name).open("xb") as stream:stream.write(body.encode())


test=(BASE / "test_apply_preview_noop_cleanup.py").read_text(encoding="utf8")
test=test.replace("apply_preview_noop_cleanup.py","apply_exit_literal_cleanup.py").replace("preview_noop_source_cas.luau","exit_literal_source_cas.luau")
test=test.replace("455/455/910", "50/50/reentry and 92/92")
start=test.index('    for relative in (app.ART+"/proposal-v1/proposal.json"')
stop=test.index("    rows = []",start)
test=test[:start]+'''    files=[app.ART+"/proposal-v1/proposal.json",app.ART+"/native-target-read-v1.json",app.ART+"/prepare_exit_literal.py",
           app.ART+"/verify_exit_neighbors.py",old["beforeFile"],old["candidateFile"]]
    files += [row["file"] for row in newer["closure"] if row["file"] != app.TARGET_FILE]
    for relative in set(files):
        target=root/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((ROOT/relative).read_bytes())
''' + test[stop:]
start=test.index('        assert app.sha(params["arguments"]["code"].encode())')
stop=test.index("    def observation(",start)
test=test[:start]+'''        code=params["arguments"]["code"]
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
            if self.scenario=="actorSource":(self.root/app.TARGET_FILE).write_bytes(b"owner changed source\\n")
            else:
                data=json.loads((self.root/app.MANIFEST).read_bytes())
                if self.scenario=="actorManifest":
                    data["ownerMetadata"]="new actor metadata";data["items"][1]["ownerFlag"]="preserve actor row"
                else:data["items"][0].update(sha256="f"*64,bytes=777)
                (self.root/app.MANIFEST).write_bytes(app.encoded(data))
        compiles=[]
        for phase,body in (("Before",self.before),("Candidate",self.after)):
            compiles.append({"phase":phase,"sourceSHA256":app.sha(body),"factorySHA256":app.sha(b"return function()\\n"+body+b"\\nend\\n"),"bytes":len(body),"factoryUncalled":True})
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
        match=re.search(r'local request=H:JSONDecode\\(string.sub\\(\\[=\\[_([^\\n]+)\\]=\\],2\\)\\)',code)
        assert match,"Actual generated request literal parser"
        return json.loads(match[1])

''' +test[stop:]
start=test.index("        if 'local request=H:JSONDecode(' not in code:")
stop=test.index('        request = json.loads(match[1]);',start)
test=test[:start]+'        request = self.parse(code);'+test[stop+len('        request = json.loads(match[1]);'):]
test=test.replace('"installedNegative"','"installedFactory", "installedExecuted", "installedLease", "parserBeforeFailure", "parserBeforeTimeout", "offlineBeforeFailure", "offlineInstalledFailure"')
test=test.replace('try: app.apply(root, lambda: client, git_reader)','try: app.apply(root, lambda: client, git_reader, offline_runner=offline_runner)')
point='            app.os.replace=replace_then_fault\n'
test=test.replace(point,point+'''            def offline_runner(_root,destination,installed,a,b):
                assert _root==root and a==before and b==after
                assert app.sha((root/app.TARGET_FILE).read_bytes())==app.sha(after if installed else before)
                if scenario==("offlineInstalledFailure" if installed else "offlineBeforeFailure"):raise AssertionError("controlled actual-port boundary failure")
                return {"pass":True,"installed":installed,"nativeCalls":0,"productionWrites":0,"scope":"controlled offline boundary; actual ports run separately"}
''')
test=test.replace('check(len(client.requests) <= 1, scenario + " no installed retry")','check(len(client.requests) <= 2, scenario + " no parser retry")')
test=test.replace('check(client.calls[-1] == "installedRequest"','check(client.calls[-1] == "parserInstalledRequest"')
test=test.replace('len(client.requests) == 1, "pending installed outcome','len(client.requests) == 2, "pending installed outcome')
test=test.replace('"identityChanged"): check(client.nativeWrites', '"identityChanged", "parserBeforeFailure", "parserBeforeTimeout", "offlineBeforeFailure"): check(client.nativeWrites')
test=test.replace('"actualReceiptIntegration": integration', '"actualParserReceiptIntegration": integration')
test=test.replace('"cas-v1/offline-wrapper-tests-v1.json"','"installer-v1/offline-wrapper-tests-v1.json"')
start=test.index("def contract_validation_checks():")
stop=test.index("def actual_transform_checks():",start)
test=test[:start]+'''def contract_validation_checks():
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


''' +test[stop:]
test=test.replace('if ok and allowed == true then return end','local NO_ANSWER_SECONDS = 8 -- silence after which the player may ask again')
test=test.replace('app.helpers.lua_literal','app.lua_literal')
put("test_apply_exit_literal_cleanup.py",test)

guard=(BASE / "test_preview_native_cas_guards.py").read_text(encoding="utf8")
guard=guard.replace("apply_preview_noop_cleanup.py","apply_exit_literal_cleanup.py").replace("app.helpers.lua_literal","app.lua_literal")
guard=guard.replace("Level4PreviewPrompt","Round Exit Client").replace("1_31106","1_31096")
# Compile branch is separately exercised by the parser fault port.
guard=guard.replace('mutation = template[template.index("local replacements={"):template.index(\'return H:JSONEncode({pass=true,operation=request.operation,path=\')]', '''prefix=template[template.index("local replacements={"):template.index("-- Native parser port only:")]
    callback=template[template.index("SES:UpdateSourceAsync(target,function(current)"):template.index('return H:JSONEncode({pass=true,operation=request.operation,path=')]
    mutation=prefix+callback''')
guard=guard.replace('ART / "native-guard-tests-v1.json"','ART / "native-guard-tests-v1.json"')
put("test_exit_native_cas_guards.py",guard)
print("New actual-wrapper and actual-native CAS fixture tests prepared.")
