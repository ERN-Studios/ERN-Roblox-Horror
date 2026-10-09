"""Real generated N01 Luau wrapper against bounded offline staging boundaries.

Does not import/run the CLI, contact Studio or execute an actual UIRegression
probe. Exercises wrapper allocation/staging/require/finally ownership, including
failures. Runtime feature coverage belongs to the recorded native gates.
"""
import ast
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TOOL = HERE / "run_native_gate.py"
ARCHIVED_BEFORE = HERE / "run_native_gate.before.py.txt"
LOCAL_BEFORE = ROOT / ".git/mongotv-cleanup-20261009/tooling-before/run_native_gate.pre-finally.py"
BEFORE = ARCHIVED_BEFORE if ARCHIVED_BEFORE.is_file() else LOCAL_BEFORE
BEFORE_SHA256 = "dc8a5b964854b8b5ef53af178b8b53e7625f4ce009eb33bcc8b9c9ccab650a8b"
sys.path.insert(0, str(ROOT / "tools"))
from push_repo_to_studio import luau_string

CANDIDATE = "-- fake ownership source only\nreturn {CleanupSharedHudProbe=function() return fixtureMeasurement() end}\n"


def generated(path):
    tree = ast.parse(path.read_text(encoding="utf-8"))
    values = [node.value for node in ast.walk(tree)
              if isinstance(node, ast.Assign) and isinstance(node.value, ast.JoinedStr)
              and any(isinstance(t, ast.Name) and t.id == "code" for t in node.targets)]
    assert len(values) == 1, "N01 generated-code boundary changed"
    return eval(compile(ast.Expression(values[0]), str(path), "eval"),
                {"__builtins__": {}, "luau_string": luau_string, "source": CANDIDATE})


PRELUDE = r'''
local checks=0
local function check(value,message)
 assert(value,"CHECK FAILED: "..message) checks+=1
end
local candidate=__CANDIDATE__
local function run(code,case,expectedError,fragment)
 local events={} local allocated={} local decoded,encoded=0,0
 local live={Name="UIRegression",ClassName="ModuleScript",Source="authoritative before"}
 local editor=if case=="initial-editor" then "editor conflict" else live.Source
 local currentLive=live
 local function mark(event) table.insert(events,event) end
 local rs={}
 function rs:WaitForChild(name) check(name=="UIRegression","original wait path") return live end
 function rs:FindFirstChild(name) check(name=="UIRegression","original guard path") mark("guard") return currentLive end
 local instance={}
 function instance.new(class)
  check(class=="ModuleScript","new empty ModuleScript class") mark("allocate")
  if case=="allocation" then error("injected allocation failure") end
  local fields={Source=if case=="empty-source" then "already written" else "",Editor=if case=="empty-editor" then "already edited" else "",DestroyCalls=0}
  local object=setmetatable({}, {
   __index=function(_,key)
    if key=="Destroy" then return function()
     fields.DestroyCalls+=1 mark("destroy")
     if case=="destroy" or case=="destroy-and-drift" then error("injected Destroy failure") end
     fields.Destroyed=true
    end end
    return fields[key]
   end,
   __newindex=function(_,key,value)
    if key=="Name" and case=="name" then error("injected Name failure") end
    fields[key]=value
   end,
  })
  table.insert(allocated,fields) return object
 end
 local ses={}
 function ses:GetEditorSource(item)
  if item==live then mark("editor-guard") return editor end
  return item.Editor
 end
 function ses:UpdateSourceAsync(item,callback)
  mark("stage")
  if case=="stage-before" then error("injected staging failure") end
  if case=="callback-live" then live.Source="concurrent Source" end
  if case=="callback-editor" then editor="concurrent editor" end
  if case=="callback-probe" then item.Source="concurrent probe" end
  local value=callback(if case=="callback-current" then "concurrent callback" else item.Source)
  item.Source=if case=="stage-source" then "truncated candidate" else value
  item.Editor=if case=="stage-editor" then "stale editor" else item.Source
  if case=="stage-after" then error("injected staging after callback failure") end
 end
 local hs={}
 function hs:JSONDecode(value)
  decoded+=1 check(value=="measurement fixture","actual measurement handoff")
  if case=="decode" then error("injected decode failure") end
  return {{Level=1,Name="first"},{Level=2,Name="excluded"},{Level=1,Name="third"}}
 end
 function hs:JSONEncode(value)
  encoded+=1
  if case=="encode" then error("injected encode failure") end
  check(value.report=="probe report" and value.failed==0,"successful report preserved")
  check(value.totalRows==3 and #value.rows==2 and value.rows[1].Name=="first" and value.rows[2].Name=="third","Level1 selection and total preserved")
  return "encoded receipt"
 end
 local function measure()
  mark("measure")
  if case=="measure" then error("injected measurement failure") end
  if case=="require-live" or case=="destroy-and-drift" then live.Source="unexpected original Source" end
  if case=="require-editor" then editor="unexpected original editor" end
  if case=="identity" then currentLive={Source=live.Source} end
  return "probe report",0,"measurement fixture"
 end
 local services={ScriptEditorService=ses,HttpService=hs,ReplicatedStorage=rs}
 local environment=setmetatable({game={GetService=function(_,name) return assert(services[name],name) end},Instance=instance,
  require=function(item)
   mark("require") check(item.Source==candidate,"require only exact staged candidate")
   if case=="require" then error("injected require failure") end
   local body=assert(loadstring(item.Source,"=FakeOwnershipProbe"))
   setfenv(body,setmetatable({fixtureMeasurement=measure},{__index=_G}))
   return body()
  end}, {__index=_G})
 local body=assert(loadstring(code,"=ActualGeneratedNativeGate")); setfenv(body,environment)
 local ok,value=pcall(body)
 check(ok~=expectedError,"expected status "..case)
 if expectedError and fragment then check(tostring(value):find(fragment,1,true),"specific injected error "..case) end
 if not expectedError then check(value=="encoded receipt" and decoded==1 and encoded==1,"success receipt unchanged") end
 local lastDestroy,lastGuard=0,0
 for i,event in ipairs(events) do if event=="destroy" then lastDestroy=i elseif event=="guard" then lastGuard=i end end
 for _,fields in ipairs(allocated) do
  check(fields.DestroyCalls==1,"each allocated probe receives Destroy exactly once "..case)
  if case~="destroy" and case~="destroy-and-drift" then check(fields.Destroyed==true,"allocated probe removed "..case) end
 end
 check(lastGuard>lastDestroy,"final original guard runs after cleanup "..case)
 check(events[#events]=="guard" or events[#events]=="editor-guard","final guard is final boundary "..case)
 if case=="allocation" or case=="initial-editor" then check(#allocated==0,"failed preallocation owns no object") end
 if case=="destroy-and-drift" then check(tostring(value):find("probe cleanup failed",1,true) and tostring(value):find("final original guard failed",1,true),"cleanup and final guard failures both reported") end
 return checks
end
'''

SCENARIOS = [
    ("success", False, None), ("initial-editor", True, "original source/editor changed"),
    ("allocation", True, "allocation failure"), ("name", True, "Name failure"),
    ("empty-source", True, "new probe must start empty"), ("empty-editor", True, "new probe must start empty"),
    ("stage-before", True, "staging failure"), ("stage-after", True, "staging after callback"),
    ("callback-current", True, "staging baseline changed"), ("callback-live", True, "original source/editor changed"),
    ("callback-editor", True, "original source/editor changed"), ("callback-probe", True, "staging baseline changed"),
    ("stage-source", True, "probe stage failed"), ("stage-editor", True, "probe stage failed"),
    ("require", True, "require failure"), ("measure", True, "measurement failure"),
    ("decode", True, "decode failure"), ("encode", True, "encode failure"),
    ("require-live", True, "final original guard failed"), ("require-editor", True, "final original guard failed"),
    ("identity", True, "original identity changed"), ("destroy", True, "probe cleanup failed"),
    ("destroy-and-drift", True, "probe cleanup failed"),
]


def program(code, scenarios):
    calls = []
    for name, failure, fragment in scenarios:
        calls.append("run(wrapper," + luau_string(name) + "," + str(failure).lower() + ","
                     + (luau_string(fragment) if fragment else "nil") + ")")
    return PRELUDE.replace("__CANDIDATE__", luau_string(CANDIDATE)) + "\nlocal wrapper=" + luau_string(code) + "\n" + "\n".join(calls) + '\nprint("native gate ownership: "..checks.." checks passed")\n'


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests executed.")
    before_hash = hashlib.sha256(TOOL.read_bytes()).hexdigest()
    assert hashlib.sha256(BEFORE.read_bytes()).hexdigest() == BEFORE_SHA256, "archived before-tool drift"
    code = generated(TOOL)
    with tempfile.TemporaryDirectory(prefix="native-gate-ownership-") as td:
        def execute(label, value, cases):
            path = Path(td) / (label + ".luau")
            path.write_text(program(value, cases), encoding="utf-8")
            return subprocess.run([binary, str(path)], capture_output=True, encoding="utf-8", timeout=15)
        result = execute("current", code, SCENARIOS)
        assert result.returncode == 0, result.stdout + result.stderr
        print(result.stdout.strip())
        old = execute("before", generated(BEFORE), [("stage-source", True, "probe stage failed")])
        assert old.returncode != 0 and "Destroy exactly once" in old.stderr, old.stdout + old.stderr
        mutants = {
            "no-cleanup": ('local destroyed,cleanupError=pcall(function() if probe then probe:Destroy() end end)', 'local destroyed,cleanupError=true,nil', [("success", False, None)], "Destroy exactly once"),
            "no-final-guard": ('local stable,guardError=pcall(guard)', 'local stable,guardError=true,nil', [("require-live", True, "final original guard failed")], "expected status"),
        }
        for label, (anchor, replacement, cases, error) in mutants.items():
            assert code.count(anchor) == 1, "mutant anchor drift: " + label
            bad = execute(label, code.replace(anchor, replacement), cases)
            assert bad.returncode != 0 and error in bad.stderr, label + ": " + bad.stdout + bad.stderr
        print("23 staging/require/cleanup scenarios; old wrapper leak reproduced; 2 negative ownership mutants rejected")
    assert hashlib.sha256(TOOL.read_bytes()).hexdigest() == before_hash, "tool changed during gate"


if __name__ == "__main__":
    main()
