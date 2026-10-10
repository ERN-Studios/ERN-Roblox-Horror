"""One-shot build of a narrow proposal from the already reviewed S18 scaffold.

Writes only new installer artifacts. Does not import MCP or mutate production.
"""
from pathlib import Path
import hashlib

HERE = Path(__file__).resolve().parent
BASE = HERE.parents[1] / "clients-next-v1" / "cas-v1"


def replace(text, old, new, expected=1):
    assert text.count(old) == expected, repr(old)
    return text.replace(old, new)


def save(name, text):
    with (HERE / name).open("xb") as stream:
        stream.write(text.encode())


template = (BASE / "preview_noop_source_cas.luau").read_text(encoding="utf8")
assert hashlib.sha256((BASE / "preview_noop_source_cas.luau").read_bytes()).hexdigest() == "8f75132652ac0a3042492d2caf6b1e2ad6175848f53547d0ff676023b2923046"
template = template.replace("Level4PreviewPrompt", "Round Exit Client").replace("1_31106", "1_31096")
template = replace(template, 'request.operation=="rollback" or request.operation=="verify"', 'request.operation=="rollback" or request.operation=="verify" or request.operation=="compile"')
template = replace(template, 'request.operation=="verify" then request.expectedTargetSHA256', '(request.operation=="verify" or request.operation=="compile") then request.expectedTargetSHA256')
start = template.index("local replacements={")
stop = template.index("local function transform(current)", start)
anchors = '''local replacements={
 {old=string.sub([=[_local NO_ANSWER_SECONDS = 8 -- silence after which the player may ask again
local HINT_HEIGHT = 36      -- two wrapped lines of the explanation band

local prompt = playerScripts:FindFirstChild("RoundExitPrompt")]=],2),new=string.sub([=[_local NO_ANSWER_SECONDS = 8 -- silence after which the player may ask again

local prompt = playerScripts:FindFirstChild("RoundExitPrompt")]=],2)},
}
'''
template = template[:start] + anchors + template[stop:]
compile_port = '''-- Native parser port only: require returns a factory; its client body is never called.
if request.operation=="compile" then
 local sources=request.compileSources
 assert(type(sources)=="table" and sha(sources.before)==request.beforeSHA256 and sha(sources.candidate)==request.afterSHA256,"Exact reviewed compile bodies required")
 local old,new=replacements[1].old,replacements[1].new
 local first,last=sources.before:find(old,1,true)
 assert(first and not sources.before:find(old,last+1,true),"Unique compile pair anchor required")
 assert(sources.before:sub(1,first-1)..new..sources.before:sub(last+1)==sources.candidate and #sources.before-#sources.candidate==73,"Only exact 73-byte literal removal may compile")
 local KEY="MongoTVExitLiteralCompileLeaseV1"
 local token={} local state={token=token,phase="compile"}
 local function ownedLease()return shared[KEY]==state and state.token==token and state.phase=="compile"end
 guard(false,false)
 assert(shared[KEY]==nil,"Foreign Exit parser probe lease present")
 shared[KEY]=state -- Fresh no-yield compare/claim; census above may yield.
 local probes,created,destroyed,cleanupErrors={ },0,0,{}
 local function checked(full)
  assert(ownedLease(),"Exit parser probe lease ownership changed")
  guard(full,false)
  assert(ownedLease(),"Exit parser probe lease ownership changed")
 end
 local function stage(name,source)
  checked(false)
  local body="return function()\\n"..source.."\\nend\\n"
  local probe=Instance.new("ModuleScript")
  local entry={object=probe,name="MongoTVCleanupExitLiteral_"..name,body=body}
  probes[#probes+1]=entry;created+=1;probe.Name=entry.name
  assert(not originals[probe] and probe.Parent==nil and #probe:GetChildren()==0,"Fresh owned unparented module required")
  assert(probe.Source=="" and SES:GetEditorSource(probe)=="","Exact empty Source/editor staging baseline required")
  SES:UpdateSourceAsync(probe,function(current)
   checked(false)
   assert(current=="" and probe.Source=="" and SES:GetEditorSource(probe)=="" and probe.Parent==nil and probe.Name==entry.name and probe.ClassName=="ModuleScript" and #probe:GetChildren()==0,"Fresh empty owned staging baseline changed")
   return body
  end)
  checked(false)
  assert(probe.Source==body and SES:GetEditorSource(probe)==body and probe.Parent==nil and probe.Name==entry.name and probe.ClassName=="ModuleScript" and #probe:GetChildren()==0,"Owned staged factory differs")
  local factory=require(probe)
  assert(type(factory)=="function","Whole-source module must return an uncalled factory")
  checked(false)
  return {phase=name,sourceSHA256=sha(source),factorySHA256=sha(body),bytes=#source,factoryUncalled=true}
 end
 local ok,result=xpcall(function()
  checked(true)
  return {stage("Before",sources.before),stage("Candidate",sources.candidate)}
 end,debug.traceback)
 -- All assertion/SES/parser failures reach exact test-owned cleanup.
 for _,entry in probes do
  local clean,why=pcall(function()
   local p=entry.object
   assert(not originals[p] and p.ClassName=="ModuleScript" and p.Parent==nil and not p:IsDescendantOf(game) and #p:GetChildren()==0 and p.Name==entry.name,"Destroy only exact untouched owned parser probe")
   assert((p.Source=="" or p.Source==entry.body) and SES:GetEditorSource(p)==p.Source,"Preserve foreign parser-probe Source/editor edit")
   p:Destroy();destroyed+=1
  end)
  if not clean then cleanupErrors[#cleanupErrors+1]=tostring(why) end
 end
 local guarded,why=pcall(function()checked(true)end)
 local lease=ownedLease()
 if lease then shared[KEY]=nil end -- Never clear a replaced foreign lease.
 return H:JSONEncode({schema="mongotv-exit-literal-native-parser-v1",operation="compile",pass=ok and guarded and lease and #cleanupErrors==0 and created==2 and destroyed==2,
  parserPassed=ok,originalsUnchanged=guarded,ownedLeaseReleased=lease,cleanupErrors=cleanupErrors,
  probesCreated=created,probesDestroyed=destroyed,remainingProbes=created-destroyed,compiles=if ok then result else {},
  error=if ok then nil else tostring(result),originalGuardError=if guarded then nil else tostring(why),
  originalSourceCoverage=request.nativeScriptCount,sourceSHA256=sha(target.Source),originalSourceWrites=0,originalParentWrites=0,originalPropertyWrites=0,
  borrowedRuntimeState=false,clientBodiesExecuted=0,modeSwitches=0,readAtUtc=DateTime.now():ToIsoDate(),
  limits="Native parser/factory-return in fresh empty ModuleScripts; client bodies never run. No gameplay, hardware, multiplayer, streaming, teleport, real-asset or performance certificate."})
end
'''
template = replace(template, "SES:UpdateSourceAsync(target,function(current)", compile_port + "SES:UpdateSourceAsync(target,function(current)")
save("exit_literal_source_cas.luau", template)

app = (BASE / "apply_preview_noop_cleanup.py").read_text(encoding="utf8")
assert hashlib.sha256((BASE / "apply_preview_noop_cleanup.py").read_bytes()).hexdigest() == "43a237fd8440b8dffc165b7ab3d1691036e15f0a4d21a2f8e243d427ebc7f39d"
app = app.replace("Preview", "Exit").replace("preview", "exit").replace("Level4ExitPrompt", "Round Exit Client").replace("1_31106", "1_31096").replace("bytesRemoved\": 215", "bytesRemoved\": 73").replace("len(after)==215", "len(after)==73")
app = replace(app, '"artifacts/cleanup-20261010/clients-next-v1"', '"artifacts/cleanup-20261010/clients-exit-v1"')
app = app.replace("exit_noop_source_cas.luau", "exit_literal_source_cas.luau").replace("exit-source-install-v1", "exit-literal-install-v1")
old = 'spec = importlib.util.spec_from_file_location("exit_prepare", Path(__file__).parent.parent / "prepare_exit_probe.py")'
app = replace(app, old, 'spec = importlib.util.spec_from_file_location("exit_prepare", Path(__file__).parent.parent / "prepare_exit_literal.py")')
app = replace(app, "sha = helpers.sha\nencoded = helpers.encoded\nsave = helpers.save\nlf = helpers.lf", "sha = helpers.SHA\nencoded = helpers.encoded\nsave = helpers.save\nlf = helpers.LF\n\ndef lua_literal(text):\n    level = 1\n    while (']' + '=' * level + ']') in '_' + text: level += 1\n    marker = '=' * level\n    return 'string.sub([' + marker + '[_' + text + ']' + marker + '],2)'\n")
start = app.index("def scope(root=ROOT):")
stop = app.index("def native_code(", start)
app = app[:start] + '''def scope(root=ROOT, installed=False):
    proof=json.loads((root / ART / "proposal-v1/proposal.json").read_bytes())
    fresh=json.loads((root / ART / "native-target-read-v1.json").read_bytes())
    assert proof["pass"] is True and fresh["pass"] is True and fresh["nativeWrites"] == fresh["modeSwitches"] == 0
    before_path=ART+"/proposal-v1/before.source.luau";after_path=ART+"/proposal-v1/candidate.source.luau"
    before=(root / before_path).read_bytes();after=(root / after_path).read_bytes()
    assert sha(before)==proof["beforeSHA256"]==helpers.BEFORE and sha(after)==proof["candidateSHA256"]==helpers.AFTER
    assert len(before)==17956 and len(after)==17883 and before.count(helpers.BLOCK.encode())==1
    assert before.replace(helpers.BLOCK.encode(),b"",1)==after and len(before)-len(after)==73
    # Actual literal/no-initializer proof; no calls, properties, require, exports or captures.
    import re
    assert re.fullmatch(r"local HINT_HEIGHT = 36      -- two wrapped lines of the explanation band\\n", helpers.BLOCK)
    assert len(re.findall(r"\\bHINT_HEIGHT\\b",before.decode()))==1 and not re.search(r"\\bHINT_HEIGHT\\b",after.decode())
    assert sha(lf((root / TARGET_FILE).read_bytes()))==sha(after if installed else before)
    assert next(row for row in proof["sourceCompiler"] if row["optimization"]==1)["canonicalIdentical"] is True
    for port in proof["contractPorts"]:
        assert port["pass"] is True
    assert [(port["checks"],port["reentryChecks"]) for port in proof["contractPorts"][:2]]==[(50,50),(50,50)]
    assert [port["phase"] for port in proof["contractPorts"][2:]]==["timingNegative","requestNegative"]
    target=fresh["metadata"]
    assert fresh["schema"]=="exit-literal-fresh-native-target-v1" and fresh["bytes"]==len(before) and fresh["sourceSHA256"]==sha(before)
    assert target["path"]=="StarterPlayer.StarterPlayerScripts.Round Exit Client" and target["segments"]==["StarterPlayer","StarterPlayerScripts","Round Exit Client"]
    assert target["instanceId"]=="1_31096" and target["parentId"]=="1_410029" and target["className"]=="LocalScript"
    assert target["sourceEditorMatches"] is True and all(target[key]==sha(before) for key in ("sourceSHA256","rawSourceSHA256","rawEditorSHA256"))
    assert target["properties"]=={"Enabled":True,"Disabled":False,"RunContext":"Enum.RunContext.Legacy","Archivable":True,"LinkedSource":""}
    assert target["attributes"]=={} and target["tags"]==[] and target["placeId"]==131311258779917 and target["universeId"]==10559217407
    target={**target,"studioPath":target["path"]}
    old={"beforeFile":before_path,"candidateFile":after_path,"originals":[target]}
    request={"nativeScriptCount":213,"beforeSHA256":sha(before),"afterSHA256":sha(after),
             "targetProperties":target["properties"],"targetAttributes":target["attributes"],"targetTags":target["tags"]}
    template=Path(__file__).with_name("exit_literal_source_cas.luau").read_text(encoding="utf8")
    return before,after,old,proof,request,template


''' + app[stop:]
app = app.replace("helpers.lua_literal", "lua_literal")
start = app.index("def validate_contract(")
stop = app.index("def bounded_source_reader(", start)
app = app[:start] + '''def validate_compile(receipt, code_hash, expected_hash, before, after):
    assert receipt["schema"]=="mongotv-exit-literal-native-parser-v1" and receipt["operation"]=="compile"
    assert receipt["nativeInputSHA256"]==code_hash and receipt["sourceSHA256"]==expected_hash
    assert all(receipt[key] is True for key in ("pass","parserPassed","originalsUnchanged","ownedLeaseReleased"))
    assert receipt["borrowedRuntimeState"] is False and receipt["cleanupErrors"]==[] and receipt["clientBodiesExecuted"]==0
    assert receipt["originalSourceCoverage"]==213 and receipt["probesCreated"]==receipt["probesDestroyed"]==2 and receipt["remainingProbes"]==0
    assert all(receipt[key]==0 for key in ("originalSourceWrites","originalParentWrites","originalPropertyWrites","modeSwitches"))
    expected=[]
    for phase,body in (("Before",before),("Candidate",after)):
        factory=b"return function()\\n"+body+b"\\nend\\n"
        expected.append({"phase":phase,"sourceSHA256":sha(body),"factorySHA256":sha(factory),"bytes":len(body),"factoryUncalled":True})
    assert receipt["compiles"]==expected, "Actual native factories differ from reviewed whole Sources"


''' + app[stop:]
app = replace(app, '    receipt_before = json.loads((root / ART / "native-before-result-v1.json").read_bytes())\n    validate_contract(receipt_before, newer["nativeCodeHashes"]["before"], "rootExecutedCodeSHA256", False)\n', '')
app = app.replace("installed_outcome_unknown", "parser_outcome_unknown")
insert = '''    def parser_port(label, rows, expected_hash):
        nonlocal parser_outcome_unknown
        code=native_code(template,request,"compile",rows,expectedTargetSHA256=expected_hash,
                         compileSources={"before":before.decode(),"candidate":after.decode()})
        save(checkpoint / (label+".luau"),code.encode())
        parser_outcome_unknown=True
        response=client._request("tools/call",{"name":"execute_luau","arguments":{
            "studio_id":STUDIO,"datamodel_type":"Edit","code":code}},timeout=180)
        parser_outcome_unknown=False
        replay=response.get("result",{})
        text="\\n".join(block.get("text","") for block in replay.get("content",[]) if block.get("type")=="text")
        assert len(text.encode())<20000,"Native parser response exceeds bounded transport contract"
        assert not replay.get("isError"),"Native parser failed: "+text
        receipt={**json.loads(text),"nativeInputSHA256":sha(code.encode())}
        save(destination / (label+".json"),encoded(receipt))
        validate_compile(receipt,sha(code.encode()),expected_hash,before,after)
        return receipt
'''
app = replace(app, "    try:\n        client.initialize()", insert + "    try:\n        client.initialize()")
app = replace(app, '        result["productionNativeWritesRequested"] = 1', '        result["nativeParserBefore"] = parser_port("native-parser-before",rows_before,sha(before))\n        result["productionNativeWritesRequested"] = 1')
start = app.index('        installed_code = (root / ART / "native-binding-v1/native-installed.luau").read_bytes()')
stop = app.index("        # A distinct observation after installed replay",start)
app = app[:start] + '''        result["nativeParserInstalled"]=parser_port("native-parser-installed",rows_after,sha(after))
''' + app[stop:]
app = app.replace('"installedContractPassed": True', '"installedParserPassed": True')
app = app.replace("installed probe", "parser probe").replace("installed replay", "parser port")
app = app.replace("Actual client-filter no-op contract, not full gameplay/multiplayer/streaming/assets/performance.", "One unread private number literal; native factory parser only, actual paired/reentry offline contracts. Not gameplay/multiplayer/streaming/assets/performance.")
app = app.replace('for operation in ("capture", "observe", "target", "verify", "apply", "rollback"):', 'for operation in ("capture", "observe", "target", "verify", "apply", "rollback", "compile"):')
app = replace(app, 'rows if operation in ("apply", "rollback", "verify") else None,\n                               pageFirst=1, pageCount=20, expectedTargetSHA256=sha(before))', 'rows if operation in ("apply", "rollback", "verify", "compile") else None,\n                               pageFirst=1, pageCount=20, expectedTargetSHA256=sha(before),\n                               compileSources={"before":before.decode(),"candidate":after.decode()})')
app = app.replace('"cas-v1/offline-proposal-v1"', '"installer-v1/offline-proposal-v1"').replace('"pending independent wrapper/negative review and fresh exit-native-before"','"prepared only; independent wrapper/native guard/parser cleanup review and Root native execution pending"')
app = app.replace('("pass", "bytesRemoved", "installedContractPassed", "afterSourceSHA256")','("pass", "bytesRemoved", "installedParserPassed", "afterSourceSHA256")')
save("apply_exit_literal_cleanup.py",app)
save(".gitattributes","* -text\n")
print("New narrow installer/template prepared; no native or production writes.")
