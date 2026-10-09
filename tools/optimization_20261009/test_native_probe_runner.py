"""Offline failure injection for the actual isolation runner; no Studio calls.

Runs the unchanged Lua runner with small service/instance stand-ins. This verifies
guard and finally behavior, not native Studio editor identity or gameplay.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess

from native_probe_runner import LUA_RUNNER, literal


def lua_value(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{" + ",".join(lua_value(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[" + lua_value(key) + "]=" + lua_value(item) for key, item in value.items()) + "}"
    raise TypeError(type(value))


MOCK = r'''
local nextId=0
local fields={}
local methods={}
local stageCount,destroyCount=0,0
local original
local running=false
local function new(class,name,parent)
 nextId+=1
 local state={ClassName=class,Name=name,id=tostring(nextId),children={},Source="",editor=""}
 local object=setmetatable({}, {
  __index=function(_,key) return methods[key] or state[key] end,
  __newindex=function(self,key,value)
   if key=="Parent" then
    if state.Parent then
     for i,child in ipairs(state.Parent.children) do if child==self then table.remove(state.Parent.children,i); break end end
    end
    if value then table.insert(value.children,self) end
   end
   state[key]=value
  end,
 })
 fields[object]=state
 object.Parent=parent
 return object
end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants()
 local result={}
 local function walk(root) for _,child in ipairs(root.children) do table.insert(result,child); walk(child) end end
 walk(self); return result
end
function methods:GetService(name) return assert(self:FindFirstChild(name),name) end
function methods:FindFirstChild(name) for _,child in ipairs(self.children) do if child.Name==name then return child end end end
function methods:IsA(class)
 return class==self.ClassName or class=="LuaSourceContainer" and (self.ClassName=="ModuleScript" or self.ClassName=="Script" or self.ClassName=="LocalScript")
end
function methods:GetDebugId() return self.id end
function methods:GetFullName() return if self.Parent and self.Parent.ClassName~="DataModel" then self.Parent:GetFullName().."."..self.Name else self.Name end
function methods:Clone() error("LuaSourceContainer cloning is forbidden") end
function methods:Destroy()
 assert(self~=original,"Runner destroyed an authoritative original")
 for _,child in ipairs(self:GetChildren()) do child:Destroy() end
 self.Parent=nil; destroyCount+=1
end
local game=new("DataModel","game")
game.PlaceId=if mode=="wrong-place" then 1 else 131311258779917
game.GameId=10559217407
local storage=new("ServerStorage","ServerStorage",game)
local replicated=new("ReplicatedStorage","ReplicatedStorage",game)
local runService=new("RunService","RunService",game)
runService.IsRunning=function() return running or mode=="already-playing" end
local http=new("HttpService","HttpService",game)
http.JSONDecode=function(_,encoded) return assert(decoded[encoded],"Unexpected JSON literal") end
http.JSONEncode=function(_,value) return if value.probe then value else "offline-conflict-list" end
http.GenerateGUID=function() return "offline-case" end
local editor=new("ScriptEditorService","ScriptEditorService",game)
editor.GetEditorSource=function(_,instance) return instance.editor end
original=new("ModuleScript","Protected",replicated)
original.Source="return {}"; original.editor=original.Source
local originalId=original.id
editor.UpdateSourceAsync=function(_,stage,callback)
 if mode=="editor-changed-before-callback" then original.editor="concurrent editor change" end
 if mode=="stage-not-empty-in-callback" then stage.Source="concurrent stage change"; stage.editor=stage.Source end
 local candidate=callback(stage.Source)
 if mode=="stage-written-to-original" then original.Source=candidate; original.editor=candidate
 else stage.Source=candidate; stage.editor=candidate end
end
local Instance={new=function(class)
 stageCount+=1
 local node=new(class,class)
 if mode=="new-module-nonempty" then node.Source="wrong editor identity"; node.editor=node.Source end
 return node
end}
local clock=0
local os={clock=function() clock+=0.01; return clock end,date=function() return "offline" end}
local task={wait=function() end}
local require=function(stage)
 assert(stage.Source==expectedStage,"Require ran a source that was not verified")
 if mode=="require-errors" then error("Synthetic require error") end
 if mode=="require-returns-table" then return {} end
 return function()
  if mode=="run-errors" then error("Synthetic contract error") end
  if mode=="run-editor-drift" then original.editor="concurrent editor change" end
  if mode=="run-source-drift" then original.Source="concurrent source change" end
  if mode=="run-identity-drift" then original.Parent=storage end
  if mode=="run-rename-drift" then original.Name="ConcurrentName" end
  if mode=="run-starts-play" then running=true end
  return {result={checks=1},output={}}
 end
end
'''


CASES = (
    "success", "wrong-place", "already-playing", "new-module-nonempty",
    "editor-changed-before-callback", "stage-not-empty-in-callback", "stage-written-to-original",
    "require-errors", "require-returns-table", "run-errors", "run-editor-drift",
    "run-source-drift", "run-identity-drift", "run-rename-drift", "run-starts-play",
)


def program():
    stage = "return function() return true end"
    values = {"__EXPECTED__": [{"segments": ["ReplicatedStorage", "Protected"], "class": "ModuleScript", "source": "return {}", "sha256": "offline"}],
              "__NAME__": "offline-isolation", "__FIXTURE__": "fixture", "__STAGE__": stage,
              "__WRAPPER_PREFIX__": "", "__WRAPPER_SUFFIX__": ""}
    code = LUA_RUNNER
    registry = {}
    for marker, value in values.items():
        encoded = literal(value)
        code = code.replace(marker, encoded)
        registry[encoded] = lua_value(value)
    definitions = "local decoded={" + ",".join("[" + key + "]=" + value for key, value in registry.items()) + "}\n"
    result = "local checks=0\nfor _,mode in ipairs(" + lua_value(list(CASES)) + ") do\n"
    result += definitions + "local expectedStage=" + lua_value(stage) + "\n" + MOCK
    result += "local result=(function()\n" + code + "\nend)()\n"
    result += r'''
 assert(original.id==originalId,"Original instance replaced")
 assert(result.cleanupPassed and #storage:GetChildren()==(mode=="run-identity-drift" and 1 or 0),"Staged module remained after "..mode)
 assert(destroyCount==stageCount,"Fresh module was not destroyed after "..mode)
 if mode=="success" then assert(result.passed and result.originalsPreserved,tostring(result.error))
 else assert(not result.passed,"Failure injection was missed: "..mode) end
 local drift=mode=="editor-changed-before-callback" or mode=="stage-written-to-original"
  or mode=="run-editor-drift" or mode=="run-source-drift" or mode=="run-identity-drift"
  or mode=="run-rename-drift" or mode=="run-starts-play"
 local noSnapshot=mode=="wrong-place" or mode=="already-playing"
 assert(result.originalsPreserved==not (drift or noSnapshot),"Incorrect preservation claim after "..mode)
 if mode=="editor-changed-before-callback" or mode=="run-editor-drift" then
  assert(original.editor=="concurrent editor change","Concurrent editor work was overwritten")
 elseif mode=="stage-written-to-original" then
  assert(original.Source==expectedStage,"Runner silently restored authoritative Source after staging regression")
 elseif mode=="run-source-drift" then assert(original.Source=="concurrent source change")
 end
 if not noSnapshot then
  assert(result.phases[#result.phases].phase=="after-cleanup-success-or-failure","No final original verification after "..mode)
 end
 checks+=1
end
print("isolated runner guard/finally failure injections: "..checks.." cases passed")
'''
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", type=Path, required=True)
    parser.add_argument("--emit", type=Path, default=Path("_local/optimization-20261009/native-runner-isolation-test.luau"))
    args = parser.parse_args()
    args.emit.parent.mkdir(parents=True, exist_ok=True)
    args.emit.write_text(program(), encoding="utf-8", newline="\n")
    subprocess.run([str(args.luau.resolve()), str(args.emit.resolve())], check=True)


if __name__ == "__main__":
    main()
