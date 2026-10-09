"""Offline bounded native metadata gate; no Studio/HTTP calls or source writes."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("cleanup_capture", HERE / "capture_baseline.py")
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)

PRELUDE = r'''
local function encode(value)
 if type(value)=="string" then
  return '"'..string.gsub(value,'[%c\\"]',function(c)
   if c=='"' then return '\\"' end
   if c=='\\' then return '\\\\' end
   return string.format('\\u%04x',string.byte(c))
  end)..'"'
 end
 if type(value)=="number" or type(value)=="boolean" then return tostring(value) end
 assert(type(value)=="table","unexpected JSON boundary")
 local parts={}
 if #value>0 or next(value)==nil then
  for _,item in ipairs(value) do table.insert(parts,encode(item)) end
  return '['..table.concat(parts,',')..']'
 end
 local keys={} for key in pairs(value) do table.insert(keys,key) end table.sort(keys)
 for _,key in ipairs(keys) do table.insert(parts,encode(key)..':'..encode(value[key])) end
 return '{'..table.concat(parts,',')..'}'
end
local hashes=__HASHES__
local game={PlaceId=131311258779917,GameId=10559217407,PlaceVersion=17}
local storage={Name="ServerScriptService",Parent=game}
local all={}
local function object(id)
 local name=string.format("Probe%03d",id)
 local class=if id%7==0 then "RemoteEvent" elseif id%3==0 then "Script" elseif id%3==1 then "LocalScript" else "ModuleScript"
 local self={Name=name,Parent=storage,ClassName=class,Archivable=true,
  Source="return __REVISION__\n-- item"..id,LinkedSource="",Enabled=true,Disabled=false,RunContext="Legacy"}
 function self:IsA(wanted)
  return wanted==class or (wanted=="LuaSourceContainer" and class~="RemoteEvent")
   or (wanted=="BaseScript" and (class=="Script" or class=="LocalScript"))
 end
 function self:GetFullName() return "ServerScriptService."..name end
 function self:GetAttributes() return {FixtureId=id,AuthoringText=string.rep("a",1600)} end
 return self
end
for id=105,1,-1 do table.insert(all,object(id)) end
table.insert(all,{IsA=function() return false end})
function game:GetDescendants() return all end
local services={
 ScriptEditorService={GetEditorSource=function(_,item) return item.Source end},
 EncodingService={ComputeBufferHash=function(_,source,algorithm)
  assert(algorithm=="Sha256")
  local hex=assert(hashes[buffer.tostring(source)],"unregistered hash fixture")
  return buffer.fromstring((string.gsub(hex,"%x%x",function(pair) return string.char(tonumber(pair,16)) end)))
 end},
 HttpService={JSONEncode=function(_,value) return encode(value) end},
}
function game:GetService(name) return assert(services[name],name) end
local task={wait=function() end}
local Enum={HashAlgorithm={Sha256="Sha256"}}
'''


class NativeFixture:
    def __init__(self, exe: Path, directory: Path, revision=1, mutate=None):
        self.exe, self.directory, self.revision, self.mutate = exe, directory, revision, mutate
        self.calls, self.pages = 0, []

    def call(self, tool, args):
        assert tool == "execute_luau" and args["studio_id"] == "offline-only" and args["datamodel_type"] == "Edit"
        code = args["code"]
        assert "Instance.new" not in code and ".Source=" not in code and "UpdateSourceAsync" not in code
        hashes = "{" + ",".join("[" + json.dumps(f"return {self.revision}\n-- item{i}") + "]=" +
                                json.dumps(hashlib.sha256(f"return {self.revision}\n-- item{i}".encode()).hexdigest())
                                for i in range(1, 106)) + "}"
        prelude = PRELUDE.replace("__HASHES__", hashes).replace("__REVISION__", str(self.revision))
        path = self.directory / "metadata.luau"
        path.write_text(prelude + "\nlocal function execute()\n" + code + "\nend\nprint(execute())\n", encoding="utf-8")
        result = subprocess.run([str(self.exe), str(path)], capture_output=True, encoding="utf-8", timeout=10)
        assert result.returncode == 0, result.stdout + result.stderr
        assert len(result.stdout) < 100000, "metadata would hit MCP text truncation"
        self.calls += 1
        page = json.loads(result.stdout)
        if self.mutate:
            page = self.mutate(page, self.calls)
        self.pages.append(copy.deepcopy(page))
        return json.dumps(page)


def main():
    exe = Path(os.environ.get("LUAU_BIN", ""))
    assert exe.is_file(), "Set LUAU_BIN to the real Luau interpreter"
    checks = 0
    with tempfile.TemporaryDirectory(prefix="mongotv-capture-paging-") as temp:
        client = NativeFixture(exe, Path(temp))
        data = capture.read_metadata(client, "offline-only")
        assert len(data["items"]) == 105 and data["inventoryCounts"] == {"scripts": 90, "remoteEvents": 15}
        assert client.calls > 3, "byte budget must reduce oversized 40-object pages"
        assert all(len(p["items"]) <= 40 and len(json.dumps(p).encode()) < 70000 for p in client.pages)
        assert [p["first"] for p in client.pages] == [1] + [p["last"] + 1 for p in client.pages[:-1]]
        assert data["items"][0]["studioPath"] == "ServerScriptService.Probe001"
        assert data["items"][-1]["studioPath"] == "ServerScriptService.Probe105"
        assert len(json.dumps(data)) > 100000, "fixture must reproduce unpaged response overflow"
        checks += 7
        for item in data["items"]:
            if "sourceBytes" in item:
                src = f'return 1\n-- item{item["attributes"]["FixtureId"]}'
                assert item["sourceBytes"] == len(src.encode())
                assert item["sourceRawSha256"] == hashlib.sha256(src.encode()).hexdigest()
                assert item["sourceEditorMatches"] is True
                checks += 3
        latest = capture.read_metadata(NativeFixture(exe, Path(temp)), "offline-only")
        assert latest == data
        changed = capture.read_metadata(NativeFixture(exe, Path(temp), revision=2), "offline-only")
        assert changed != data and changed["items"][0]["sourceBytes"] == data["items"][0]["sourceBytes"]
        assert changed["items"][0]["sourceRawSha256"] != data["items"][0]["sourceRawSha256"]
        checks += 3
        mutations = {
            "wrong-place": lambda p,n: {**p,"placeId":1},
            "wrong-universe": lambda p,n: {**p,"universeId":1},
            "missing-identity": lambda p,n: {k:v for k,v in p.items() if k!="placeVersion"},
            "count-total": lambda p,n: {**p,"totalItems":p["totalItems"]+1},
            "page-start": lambda p,n: {**p,"first":p["first"]+1},
            "page-end": lambda p,n: {**p,"last":p["last"]+1},
            "truncated-items": lambda p,n: {**p,"items":p["items"][:-1]},
            "duplicate-path": lambda p,n: {**p,"items":[p["items"][0],p["items"][0],*p["items"][2:]]},
            "between-pages-version": lambda p,n: {**p,"placeVersion":p["placeVersion"]+(n>1)},
            "between-pages-counts": lambda p,n: {**p,"inventoryCounts":{"scripts":89,"remoteEvents":16}} if n>1 else p,
            "aggregate-class": lambda p,n: {**p,"items":[{**i,"className":"RemoteEvent"} if "sourceBytes" in i else i for i in p["items"]]},
        }
        for name, mutation in mutations.items():
            try:
                capture.read_metadata(NativeFixture(exe, Path(temp), mutate=mutation), "offline-only")
            except RuntimeError:
                checks += 1
            else:
                raise AssertionError("paging accepted " + name)
    print(f"capture metadata paging: {checks} checks passed; real offline Luau pages, 11 negative fixtures, no Studio calls")


if __name__ == "__main__":
    main()
