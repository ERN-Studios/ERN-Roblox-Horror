"""Run actual generated sync metadata Luau against bounded fake services.

No Roblox objects, Studio/MCP calls, source initializers, sockets or git writes.
The real generated code runs under Luau 0.737; engine services are synthetic.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import sync_from_studio as sync  # noqa: E402

PLACE = 131311258779917
UNIVERSE = 10559217407
SOURCE = "-- synthetic caf\u00e9\r\nreturn 'preserved'\r\n"
CHANGED = "return 'changed'\n"


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def literal(raw: str | bytes) -> str:
    data = raw.encode() if isinstance(raw, str) else raw
    return '"' + ''.join('\\' + f'{byte:03}' for byte in data) + '"'


PREFIX = r'''
local checks,cases,writes=0,0,0
local function check(ok,why)checks+=1;assert(ok,why)end
local knownHashes=__HASHES__
local rawSource=__RAW__
local canonicalSource=__CANONICAL__
local changedSource=__CHANGED__
local rawSHA=__RAWSHA__
local canonicalSHA=__CANONSHA__
local trueType=typeof
local typeof=function(v)
 if type(v)=="table" and v.__enum then return "EnumItem" end
 return trueType(v)
end
local Enum={HashAlgorithm={Sha256={__enum=true}}}
local context=setmetatable({__enum=true},{__tostring=function()return "Enum.RunContext.Legacy" end})
local function fresh(className,scenario)
 local running=false
 local sourceReads,editorReads,hashReads=0,0,0
 local records={}
 local functions={}
 local function node(data)
  local object={}
  records[object]=data
  return setmetatable(object,{
   __index=function(_,key)
    if functions[key] then return functions[key] end
    if key=="Source" then sourceReads+=1 end
    if key=="Parent" then return data.Parent end
    if data[key]~=nil then return data[key] end
    error("unreadable fixture property: "..key)
   end,
   __newindex=function()writes+=1;error("generated metadata attempted an Instance property write")end,
  })
 end
 function functions.GetChildren(self)return table.clone(records[self].children or {})end
 function functions.GetDebugId(self,depth)assert(depth==16);return records[self].id end
 function functions.GetFullName(self)
  local names={}
  while self do
   local row=records[self]
   if row.Parent==nil then break end
   table.insert(names,1,row.Name);self=row.Parent
  end
  return table.concat(names,".")
 end
 function functions.GetAttributes(self)return table.clone(records[self].attributes or {})end
 local gameData={Name="game",ClassName="DataModel",id="game",PlaceId=__PLACE__,GameId=__UNIVERSE__}
 local game=node(gameData)
 local parentData={Name="ServerScriptService",ClassName="ServerScriptService",Parent=game,id="parent",children={}}
 local parent=node(parentData);gameData.children={parent}
 local targetData={Name="Fixture",ClassName=className,Parent=parent,id="target",Archivable=true,
  attributes={MigrationVersion=3,Marker="preserve",Active=false},tags={"zeta","alpha"}}
 if className~="RemoteEvent" then targetData.LinkedSource="";targetData.Source=rawSource end
 if className=="Script" or className=="LocalScript" then
  targetData.Enabled=true;targetData.Disabled=false;targetData.RunContext=context
 end
 local target=node(targetData);parentData.children={target}
 local editor=rawSource
 local alternateParent=node({Name="Other",ClassName="Folder",Parent=game,id="other"})
 if scenario=="missing" then parentData.children={} end
 if scenario=="ambiguous" then
  parentData.children={target,node({Name="Fixture",ClassName=className,Parent=parent,id="duplicate"})}
 end
 if scenario=="wrong-class" then targetData.ClassName="Folder" end
 if scenario=="detached" then targetData.Parent=nil end
 if scenario=="wrong-place" then gameData.PlaceId+=1 end
 if scenario=="wrong-universe" then gameData.GameId+=1 end
 if scenario=="play" then running=true end
 if scenario=="archivable-unreadable" then targetData.Archivable=nil end
 if scenario=="linkedsource-unreadable" then targetData.LinkedSource=nil end
 if scenario=="aliases-invalid" then targetData.Disabled=true end
 if scenario=="enabled-unreadable" then targetData.Enabled=nil end
 if scenario=="runcontext-unreadable" then targetData.RunContext="Enum.RunContext.Legacy" end
 if scenario=="editor-conflict" then editor=changedSource end
 if scenario=="typed-attribute" then targetData.attributes.Marker={Color3=true} end
 if scenario=="nan-attribute" then targetData.attributes.Marker=0/0 end
 if scenario=="infinite-attribute" then targetData.attributes.Marker=math.huge end
 if scenario=="tag-type" then targetData.tags={"alpha",42} end
 local services={}
 services.HttpService={JSONEncode=function(_,value)return value end}
 services.RunService={IsRunning=function()return running end}
 services.EncodingService={ComputeBufferHash=function(_,value,algorithm)
  hashReads+=1;assert(algorithm==Enum.HashAlgorithm.Sha256)
  local bytes=buffer.tostring(value)
  return buffer.fromstring(assert(knownHashes[bytes],"Unexpected hash input"))
 end}
 services.CollectionService={GetTags=function(_,object)
  assert(object==target);return table.clone(targetData.tags)
 end}
 services.ScriptEditorService={GetEditorSource=function(_,object)
  assert(object==target);editorReads+=1
  local value=editor
  if editorReads==1 then
   if scenario=="source-change" then targetData.Source=changedSource end
   if scenario=="editor-change" then editor=changedSource end
   if scenario=="properties-change" then targetData.Enabled=false;targetData.Disabled=true end
   if scenario=="attributes-change" then targetData.attributes.MigrationVersion=4 end
   if scenario=="tags-change" then targetData.tags={"alpha","other"} end
   if scenario=="parent-change" then targetData.Parent=alternateParent end
   if scenario=="name-change" then targetData.Name="Renamed" end
   if scenario=="mode-change" then running=true end
   if scenario=="place-change" then gameData.PlaceId+=1 end
  end
  return value
 end}
 function functions.GetService(self,name)assert(self==game);return assert(services[name])end
 return game,function()return sourceReads,editorReads,hashReads end
end
'''

SUFFIX = r'''
local goodClasses={"Script","LocalScript","ModuleScript","RemoteEvent"}
for _,className in goodClasses do
 local game,counters=fresh(className,"good")
 local result=runners[className](game)
 cases+=1
 check(type(result)=="table","actual generated runner returns serialized metadata boundary")
 check(result.path=="ServerScriptService.Fixture" and result.className==className,"exact class/path")
 check(#result.segments==2 and result.segments[1]=="ServerScriptService" and result.segments[2]=="Fixture","exact segments")
 check(result.instanceId=="target" and result.parentId=="parent","instance/parent identity")
 check(result.placeId==__PLACE__ and result.universeId==__UNIVERSE__,"place/universe")
 check(result.properties.Archivable==true,"fresh common property")
 check(result.attributes.MigrationVersion==3 and result.attributes.Marker=="preserve" and result.attributes.Active==false,"migration/false attributes preserved")
 check(#result.tags==2 and result.tags[1]=="alpha" and result.tags[2]=="zeta","tags sorted")
 local sourceCount,editorCount,hashCount=counters()
 if className=="RemoteEvent" then
  check(next(result.properties,"Archivable")==nil,"RemoteEvent has only its supported property")
  check(result.sourceEditorMatches==nil and result.sourceSHA256==nil,"remote has no invented Source metadata")
  check(sourceCount==0 and editorCount==0 and hashCount==0,"remote never reads Source/editor/hash")
 else
  check(result.properties.LinkedSource=="","LinkedSource retained")
  check(result.sourceEditorMatches==true and result.rawSourceSHA256==rawSHA and result.rawEditorSHA256==rawSHA,"raw Source/editor exact hashes")
  check(result.sourceSHA256==canonicalSHA and result.canonicalBytes==#canonicalSource,"CRLF UTF8 canonical SHA/bytes")
  check(sourceCount==2 and editorCount==2 and hashCount==3,"Source/editor re-read and three actual hash requests")
  if className=="ModuleScript" then
   check(result.properties.Enabled==nil and result.properties.Disabled==nil and result.properties.RunContext==nil,"module does not read unsupported BaseScript properties")
  else
   check(result.properties.Enabled==true and result.properties.Disabled==false and result.properties.RunContext=="Enum.RunContext.Legacy","BaseScript properties and enum string")
  end
 end
end
local negatives={
 {"missing","Missing native path"},{"ambiguous","Ambiguous native path"},
 {"wrong-class","Native class changed"},{"detached","Detached native instance"},
 {"wrong-place","Wrong place"},{"wrong-universe","Wrong universe"},
 {"play","Native metadata requires Edit"},{"archivable-unreadable","unreadable fixture property"},
 {"linkedsource-unreadable","unreadable fixture property"},{"aliases-invalid","Invalid Enabled aliases"},
 {"enabled-unreadable","unreadable fixture property"},{"runcontext-unreadable","RunContext unreadable"},
 {"editor-conflict","Native Source/editor conflict"},{"typed-attribute","Unsupported native attribute"},
 {"nan-attribute","Unsupported native attribute"},{"infinite-attribute","Unsupported native attribute"},
 {"tag-type","Invalid native tag"},{"source-change","Native Source/editor changed during read"},
 {"editor-change","Native Source/editor changed during read"},{"properties-change","Native metadata changed during read"},
 {"attributes-change","Native metadata changed during read"},{"tags-change","Native metadata changed during read"},
 {"parent-change","Native identity changed during read"},{"name-change","Native identity changed during read"},
 {"mode-change","Native mode/place changed"},{"place-change","Native mode/place changed"},
}
for _,entry in negatives do
 local game=fresh("Script",entry[1])
 local ok,err=pcall(runners.Script,game)
 cases+=1
 check(not ok,"semantic negative must reject: "..entry[1])
 check(tostring(err):find(entry[2],1,true)~=nil,"negative rejected by intended gate: "..entry[1].." / "..tostring(err))
end
check(writes==0,"actual generated metadata performs no object/property writes")
print("CASES="..cases.." CHECKS="..checks.." WRITES="..writes)
'''


def build_fixture() -> tuple[str, dict[str, str]]:
    sources = (SOURCE, SOURCE.replace('\r\n', '\n'), CHANGED)
    hashes = '{' + ','.join('[' + literal(source) + ']=' + literal(hashlib.sha256(source.encode()).digest())
                          for source in sources) + '}'
    values = {'__HASHES__': hashes, '__RAW__': literal(SOURCE),
              '__CANONICAL__': literal(SOURCE.replace('\r\n', '\n')),
              '__CHANGED__': literal(CHANGED), '__RAWSHA__': literal(sha(SOURCE.encode())),
              '__CANONSHA__': literal(sha(SOURCE.replace('\r\n', '\n').encode())),
              '__PLACE__': str(PLACE), '__UNIVERSE__': str(UNIVERSE)}
    prefix, suffix = PREFIX, SUFFIX
    for key, value in values.items():
        prefix = prefix.replace(key, value)
        suffix = suffix.replace(key, value)
    runners = []
    generated = {}
    for class_name in ('Script', 'LocalScript', 'ModuleScript', 'RemoteEvent'):
        code = sync.native_metadata_code(['ServerScriptService', 'Fixture'], class_name, PLACE, UNIVERSE)
        generated[class_name] = sha(code.encode())
        runners.append('[' + literal(class_name) + ']=function(game)\n' + code + '\nend')
    return prefix + '\nlocal runners={\n' + ',\n'.join(runners) + '\n}\n' + suffix, generated


def main(receipt: Path | None = None) -> None:
    tool_path = Path(sync.__file__)
    starting = tool_path.read_bytes()
    fixture, generated = build_fixture()
    binaries = Path(os.environ['TEMP']) / 'codex-luau-0.737'
    compiler, runtime = binaries / 'luau-compile.exe', binaries / 'luau.exe'
    compiles = []
    with tempfile.TemporaryDirectory(prefix='mongotv-sync-metadata-luau-') as directory:
        path = Path(directory) / 'metadata.luau'
        path.write_bytes(fixture.encode())
        for optimization in ('-O0', '-O1'):
            run = subprocess.run([str(compiler), '--binary', optimization, str(path)], capture_output=True, timeout=20)
            assert run.returncode == 0, run.stderr.decode(errors='replace')
            compiles.append({'optimization': optimization, 'pass': True})
        run = subprocess.run([str(runtime), str(path)], capture_output=True, text=True, timeout=20)
        assert run.returncode == 0, run.stdout + run.stderr
    assert not Path(directory).exists(), 'Owned temporary fixture was not removed'
    assert tool_path.read_bytes() == starting, 'Concurrent sync tool edit; do not credit this run'
    import re
    match = re.search(r'CASES=(\d+) CHECKS=(\d+) WRITES=(\d+)', run.stdout)
    assert match
    cases, checks, writes = map(int, match.groups())
    assert cases == 30 and writes == 0
    proof = {'schema': 'sync-native-metadata-luau-fixture-v1', 'pass': True,
             'cases': cases, 'checks': checks, 'syntheticObjectWrites': writes,
             'compileChecks': compiles, 'generatedCodeSHA256': generated,
             'fixtureSHA256': sha(fixture.encode()), 'syncToolSHA256': sha(starting),
             'testSHA256': sha(Path(__file__).read_bytes()),
             'compilerSHA256': sha(compiler.read_bytes()), 'runtimeSHA256': sha(runtime.read_bytes()),
             'temporaryFixtureCleaned': True, 'nativeCalls': 0, 'productionWrites': 0,
             'limits': 'Actual generated Luau and property/editor/identity guards under fake services. JSON boundary returns the metadata table; EncodingService uses exact known SHA buffers. No real Roblox API, serialization, gameplay, authoring assets, multiplayer or performance certification.'}
    if receipt is not None:
        assert not receipt.exists(), 'Preserve immutable previous receipt'
        receipt.parent.mkdir(parents=True, exist_ok=True)
        with receipt.open('xb') as stream:
            raw = (json.dumps(proof, indent=2) + '\n').encode()
            assert stream.write(raw) == len(raw)
        assert receipt.read_bytes() == raw
    print(json.dumps(proof, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--receipt', type=Path)
    main(parser.parse_args().receipt)
