from pathlib import Path
import json, subprocess

ROOT=Path(__file__).resolve().parent
TASK=ROOT.parent
LUAU=TASK.parent/'level5-build'/'tools'/'luau'/'luau'
manifest=json.loads((ROOT/'manifest.json').read_text())
checks=[]
for index,row in enumerate(manifest,1):
    old=(TASK/'baseline'/'sources'/row['file']).read_text()
    new=Path(row['draftFile']).read_text()
    payload=Path(row['payloadFile']).read_text()
    names='{'+','.join(json.dumps(x,ensure_ascii=False)for x in row['names'])+'}'
    harness='''local baseline=__BASELINE__
local expected=__EXPECTED__
local names=__NAMES__
local class=__CLASS__
local scenarios={
 {mode="success",status="APPLIED_VERIFIED",writes=1,calls=1},
 {mode="baseline-changed",status="BASELINE_CHANGED",writes=0,calls=0},
 {mode="editor-conflict",status="SOURCE_EDITOR_CONFLICT",writes=0,calls=0},
 {mode="callback-changed",status="CALLBACK_BASELINE_CHANGED",writes=0,calls=1},
 {mode="callback-retry",status="CALLBACK_BASELINE_CHANGED",writes=0,calls=1},
 {mode="source-changed-during-callback",status="SOURCE_CHANGED_DURING_UPDATE",writes=0,calls=1},
 {mode="path-changed-during-callback",status="INSTANCE_PATH_CHANGED",writes=0,calls=1},
 {mode="wrong-place",status="WRONG_PLACE",writes=0,calls=0},
 {mode="play-mode",status="EDIT_MODE_REQUIRED",writes=0,calls=0},
 {mode="wrong-class",status="WRONG_CLASS",writes=0,calls=0},
 {mode="ambiguous-path",status="AMBIGUOUS_PATH",writes=0,calls=0},
 {mode="missing-path",status="MISSING_PATH",writes=0,calls=0},
 {mode="read-failed",status="READ_FAILED",writes=0,calls=0},
 {mode="update-failed",status="UPDATE_FAILED",writes=0,calls=1},
 {mode="postwrite-parity",status="POSTWRITE_PARITY_NOT_VERIFIED",writes=1,calls=1},
}
local assertions=0
local function check(value,message)assertions+=1;assert(value,message)end
for _,case in ipairs(scenarios)do
 local writes,calls=0,0
 local function node(name)
  return {Name=name,children={},GetChildren=function(self)return self.children end}
 end
 local game=node("game");game.PlaceId=131311258779917;game.GameId=10559217407
 local parent=game
 for _,name in ipairs(names)do local child=node(name);table.insert(parent.children,child);child.Parent=parent;parent=child end
 local target=parent;target.ClassName=class;target.Source=baseline
 local editor=baseline
 local E={}
 function E:GetEditorSource(object)
  if case.mode=="read-failed"then error("read failed")end
  return editor
 end
 function E:UpdateSourceAsync(object,callback)
  calls+=1
  if case.mode=="update-failed"then error("update failed")end
  if case.mode=="callback-changed"then object.Source=baseline.."-- concurrent edit";editor=object.Source end
  if case.mode=="source-changed-during-callback"then object.Source=baseline.."-- concurrent property edit"end
  if case.mode=="path-changed-during-callback"then object.Name=object.Name.." renamed"end
  local replacement=callback(editor)
  if case.mode=="callback-retry"then
   check(replacement==expected,"initial proposal is expected draft")
   object.Source=baseline.."-- developer edit before retry";editor=object.Source
   replacement=callback(editor)
  end
  if replacement~=nil then
   writes+=1;editor=replacement
   if case.mode~="postwrite-parity"then object.Source=replacement end
  end
 end
 local H={JSONEncode=function(_,value)return value end}
 function game:GetService(name)
  if name=="HttpService"then return H end
  if name=="ScriptEditorService"then return E end
  if name=="RunService"then return {IsRunning=function()return case.mode=="play-mode"end}end
  error("Unexpected service: "..name)
 end
 if case.mode=="baseline-changed"then target.Source=baseline.."-- different baseline";editor=target.Source end
 if case.mode=="editor-conflict"then editor=baseline.."-- unsaved editor edit"end
 if case.mode=="wrong-place"then game.PlaceId=1 end
 if case.mode=="wrong-class"then target.ClassName="Folder"end
 if case.mode=="ambiguous-path"then table.insert(target.Parent.children,node(target.Name))end
 if case.mode=="missing-path"then target.Name="Absent"end
 local initialSource,initialEditor=target.Source,editor
 local function apply()
__PAYLOAD__
 end
 local result=apply()
 check(result.status==case.status,case.mode..": expected "..case.status..", got "..tostring(result.status))
 check(writes==case.writes,case.mode..": incorrect mutation count")
 check(calls==case.calls,case.mode..": unexpected UpdateSourceAsync invocation")
 if case.mode=="success"then
  check(target.Source==expected and editor==expected,"successful content must match full draft byte for byte")
  local again=apply()
  check(again.status=="BASELINE_CHANGED" and writes==1,"same payload cannot replay against changed source")
 elseif calls==0 or case.mode=="update-failed"then
  check(target.Source==initialSource and editor==initialEditor,case.mode..": existing content changed")
 elseif case.mode=="callback-changed"or case.mode=="callback-retry"then
  check(target.Source==editor and target.Source~=expected,case.mode..": developer edit was overwritten")
 elseif case.mode=="postwrite-parity"then
  check(target.Source==baseline and editor==expected,"uncommitted editor content must not be reported as parity")
 end
end
print("CAS payload: "..#scenarios.." scenarios, "..assertions.." assertions passed")
'''
    for token,value in {'__BASELINE__':json.dumps(old,ensure_ascii=False),'__EXPECTED__':json.dumps(new,ensure_ascii=False),'__NAMES__':names,'__CLASS__':json.dumps(row['class']),'__PAYLOAD__':payload}.items():harness=harness.replace(token,value)
    path=ROOT/'checks'/f'{index:02d}.cas-mock.luau';path.write_text(harness)
    result=subprocess.run([str(LUAU),str(path)],capture_output=True,text=True)
    assert result.returncode==0,result.stdout+result.stderr
    checks.append({'file':row['file'],'passed':True,'detail':result.stdout.strip()})
(ROOT/'validation.json').write_text(json.dumps(checks,indent=2)+'\n')
print(json.dumps(checks,indent=2))
