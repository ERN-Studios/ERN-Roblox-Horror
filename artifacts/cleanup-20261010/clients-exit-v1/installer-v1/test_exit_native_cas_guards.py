"""Execute actual native targetIdentity/guard/transform/SES callback code.

Engine metadata/crypto/callback scheduling are explicit local boundaries.
No Studio, Source, manifest, index or git mutations; tests never import MCP.
"""
from pathlib import Path
import importlib.util
import argparse
import json
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ART = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("actual_preview_installer", ART / "apply_exit_literal_cleanup.py")
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


def main(receipt=None):
    destination = receipt or ART / "native-guard-tests-v1.json"
    assert not destination.exists(), "Immutable guard receipt exists"
    before, after, _, _, request, template = app.scope()
    mode = template[template.index("local function mode()"):template.index("local function sha(source)")]
    stable = template[template.index("local function stable(value)"):template.index("local function segments(n)")]
    identity = template[template.index("local function targetIdentity()"):template.index("mode();targetIdentity()")]
    guard = template[template.index("local function guard(fullCensus,changed)"):template.index("guard(true,false)\n")]
    prefix=template[template.index("local replacements={"):template.index("-- Native parser port only:")]
    callback=template[template.index("SES:UpdateSourceAsync(target,function(current)"):template.index('return H:JSONEncode({pass=true,operation=request.operation,path=')]
    mutation=prefix+callback
    assert mutation.count("SES:UpdateSourceAsync(target,function(current)") == 1
    program = r'''
local BEFORE=__BEFORE__
local AFTER=__AFTER__
local beforeSHA=__BEFORESHA__
local afterSHA=__AFTERSHA__
local checks=0
local function check(v,why)checks+=1;assert(v,why)end
local function clone(v)
 if type(v)~="table" then return v end
 local t={} for k,value in v do t[k]=clone(value) end return t
end
local function encode(v)
 if type(v)~="table" then return type(v)..":"..tostring(v) end
 local keys={} for k in v do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local t={} for _,k in keys do t[#t+1]=encode(k).."="..encode(v[k]) end
 return "{"..table.concat(t,",").."}"
end
local function run(kind)
 local running=false
 local H={JSONEncode=function(_,v)return encode(v)end}
 local RS={IsRunning=function()return running end}
 local game={PlaceId=131311258779917,GameId=10559217407}
 local request={operation=kind=="rollback" and "rollback" or "apply",beforeSHA256=beforeSHA,afterSHA256=afterSHA,nativeScriptCount=213,
  targetProperties={Enabled=true,Disabled=false,RunContext="Enum.RunContext.Legacy",Archivable=true,LinkedSource=""},targetAttributes={},targetTags={}}
 local function sha(body)
  if body==BEFORE then return beforeSHA elseif body==AFTER then return afterSHA end
  local i=body:match("^fixtureSource(%d+)$")
  return if i then "fixtureHash"..i else "unknown exact bytes"
 end
 local nodes,originals={},{}
 for i=1,213 do
  local targetCase=i==1
  local n={Source=targetCase and (kind=="rollback" and AFTER or BEFORE) or "fixtureSource"..i}
  n.editor=n.Source
  n.meta={studioPath=targetCase and "StarterPlayer.StarterPlayerScripts.Round Exit Client" or "ServerScriptService.fixture"..i,
   segments=targetCase and {"StarterPlayer","StarterPlayerScripts","Round Exit Client"} or {"ServerScriptService","fixture"..i},
   instanceId=targetCase and "1_31096" or "fixture"..i,parentId=targetCase and "1_410029" or "fixtureParent",
   className=targetCase and "LocalScript" or "ModuleScript",properties=targetCase and clone(request.targetProperties) or {Archivable=true,LinkedSource=""},attributes={},tags={}}
  function n:IsA(kind)return kind=="LuaSourceContainer" end
  originals[n]={sha256=sha(n.Source)}
  for key,value in n.meta do originals[n][key]=clone(value) end
  nodes[#nodes+1]=n
 end
 local target=nodes[1]
 function game:GetDescendants()return nodes end
 local function metadata(n)return clone(n.meta)end
 local SES={GetEditorSource=function(_,n)return n.editor end}
 local fromHash=if request.operation=="apply" then beforeSHA else afterSHA
 local toHash=if request.operation=="apply" then afterSHA else beforeSHA
 local writes=0
 function SES:UpdateSourceAsync(n,callback)
  if kind=="callbackSource" then n.Source="foreign source";n.editor=n.Source
  elseif kind=="callbackEditor" then n.editor="foreign editor"
  elseif kind=="callbackProperties" then n.meta.properties.Enabled=false;n.meta.properties.Disabled=true
  elseif kind=="callbackClass" then n.meta.className="ModuleScript"
  elseif kind=="callbackIdentity" then n.meta.instanceId="foreign instance"
  elseif kind=="callbackParent" then n.meta.parentId="foreign parent"
  elseif kind=="callbackAttributes" then n.meta.attributes.foreign=true
  elseif kind=="callbackTags" then n.meta.tags={"foreign tag"}
  elseif kind=="callbackMode" then running=true
  elseif kind=="otherSource" then nodes[2].Source="foreign other source";nodes[2].editor=nodes[2].Source
  elseif kind=="otherProperties" then nodes[2].meta.properties.Archivable=false
  elseif kind=="beforeCallbackError" then error("controlled SES callback scheduling failure",0) end
  local current=if kind=="callbackCurrent" then "foreign callback current" else n.Source
  local nextSource=callback(current)
  n.Source=nextSource;n.editor=nextSource;writes+=1
 end
 __ACTUAL_MODE__
 __ACTUAL_STABLE__
 __ACTUAL_IDENTITY__
 __ACTUAL_GUARD__
 guard(true,false)
 local ok,err=pcall(function()
  __ACTUAL_MUTATION__
 end)
 local expectedSuccess=kind=="success" or kind=="rollback"
 check(ok==expectedSuccess,"actual native callback outcome "..kind..": "..tostring(err))
 check(writes==(expectedSuccess and 1 or 0),"fresh guard rejects before native write "..kind)
 if expectedSuccess then
  check(target.Source==(kind=="rollback" and BEFORE or AFTER),"actual scoped transform commits exact Source "..kind)
  check(target.editor==target.Source,"actual Source/editor readback agrees "..kind)
 else
  local message=if kind=="callbackSource" or kind=="callbackEditor" or kind=="otherSource" then "Original Source/editor changed"
   elseif kind=="callbackCurrent" then "Fresh callback Source/editor CAS changed"
   elseif kind=="callbackClass" or kind=="callbackIdentity" or kind=="callbackParent" then "Fresh target identity changed"
   elseif kind=="callbackProperties" or kind=="callbackAttributes" or kind=="callbackTags" then "Fresh target metadata changed"
   elseif kind=="callbackMode" then "Edit-only CAS; preserve owner's Play"
   elseif kind=="beforeCallbackError" then "controlled SES callback scheduling failure"
   else "Original metadata changed"
  check(tostring(err):find(message,1,true)~=nil,"intended exact fresh guard rejects "..kind)
  check(target.Source==(kind=="callbackSource" and "foreign source" or BEFORE),"foreign or exact before Source preserved "..kind)
 end
 check(#nodes==213,"all original source census remains bounded "..kind)
 return {kind=kind,pass=true,writes=writes}
end
local kinds={"success","rollback","callbackSource","callbackEditor","callbackCurrent","callbackProperties","callbackClass","callbackIdentity","callbackParent","callbackAttributes","callbackTags","callbackMode","otherSource","otherProperties","beforeCallbackError"}
for _,kind in kinds do run(kind) end
print("NATIVE_GUARD_CASES="..#kinds.." CHECKS="..checks)
'''
    replacements = {"__BEFORE__": app.lua_literal(before.decode()), "__AFTER__": app.lua_literal(after.decode()),
                    "__BEFORESHA__": app.lua_literal(app.sha(before)), "__AFTERSHA__": app.lua_literal(app.sha(after)),
                    "__ACTUAL_MODE__": mode, "__ACTUAL_STABLE__": stable, "__ACTUAL_IDENTITY__": identity,
                    "__ACTUAL_GUARD__": guard, "__ACTUAL_MUTATION__": mutation}
    for key, value in replacements.items():
        assert program.count(key) == 1
        program = program.replace(key, value)
    compiles = []
    with tempfile.TemporaryDirectory(prefix="preview-actual-native-guards-") as directory:
        path = Path(directory) / "actual-native-guards.luau"
        path.write_bytes(program.encode())
        for opt in (0, 1):
            run = subprocess.run([str(app.helpers.COMPILER), "--binary", "-g0", f"-O{opt}", str(path)], capture_output=True, timeout=30)
            assert run.returncode == 0, run.stderr.decode(errors="replace")
            compiles.append({"optimization": opt, "pass": True})
        run = subprocess.run([str(app.helpers.LUAU), str(path)], capture_output=True, text=True, timeout=30)
        assert run.returncode == 0, run.stdout + run.stderr
    match = re.search(r"NATIVE_GUARD_CASES=(\d+) CHECKS=(\d+)", run.stdout)
    proof = {"pass": True, "cases": int(match[1]), "checks": int(match[2]), "stdout": run.stdout,
             "compile": compiles, "nativeScriptCount": 213, "nativeCalls": 0, "productionWrites": 0, "manifestWrites": 0,
             "templateSHA256": app.sha(template.encode()), "toolSHA256": app.sha(Path(__file__).read_bytes()), "programSHA256": app.sha(program.encode()),
             "actualCodeHashes": {key: app.sha(value.encode()) for key, value in (("mode", mode), ("stable", stable), ("targetIdentity", identity), ("guard", guard), ("mutation", mutation))},
             "limits": "Actual native-template mode/identity/all213guard/transform/UpdateSourceAsync callback/postguard code executed. Engine metadata, exact known-body SHA, JSON and callback scheduling are controlled table boundaries. Not real Studio/ScriptEditorService guard or gameplay/multiplayer/streaming certification."}
    app.save(destination, app.encoded(proof))
    print(json.dumps({"pass": True, "cases": proof["cases"], "checks": proof["checks"], "nativeCalls": 0}))


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--receipt",type=Path)
    main(parser.parse_args().receipt)
