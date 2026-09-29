from pathlib import Path
import hashlib, json, subprocess

ROOT=Path(__file__).resolve().parent
BASE=ROOT.parent/'baseline'/'sources'
LUAU=ROOT.parents[1]/'level5-build'/'tools'/'luau'
SOURCES=ROOT/'sources'
records=json.loads((ROOT/'manifest.json').read_text())
out=ROOT/'checks';out.mkdir(exist_ok=True)
checks=[]
for record in records:
    path=record['file'];source=(SOURCES/path).read_text()
    assert hashlib.sha256((BASE/path).read_bytes()).hexdigest()==record['baselineSha256']
    assert hashlib.sha256(source.encode()).hexdigest()==record['draftSha256']
    wrapper=out/(Path(path).name+'.compile.luau')
    wrapper.write_text('return function()\n'+source+'\nend\n')
    result=subprocess.run([str(LUAU/'luau-compile'),'-O0','--null',str(wrapper)],capture_output=True,text=True)
    checks.append({'file':path,'compileO0':result.returncode==0,'detail':(result.stdout+result.stderr).strip()})
    assert result.returncode==0,result.stderr+result.stdout

gm=(SOURCES/'ServerScriptService/GameManager.Script.lua').read_text()
adapter=(SOURCES/'ServerScriptService/Level 5 Systems/Level 5 Round Adapter.ModuleScript.lua').read_text()
watcher=(SOURCES/'ServerScriptService/Level 5 Systems/Level 5 Window Watcher Encounters.ModuleScript.lua').read_text()
routing=(BASE/'ServerScriptService/Round Completion Routing.ModuleScript.lua').read_text()
policy=gm[gm.index('if workspace:GetAttribute(Routing.Level4DevAttribute) == nil then'):gm.index('-- Always-on server authority')]
adapter_access=adapter[adapter.index('function Adapter.Build()')+len('function Adapter.Build()'):adapter.index('\tfor _, level in ipairs({2, 3, 4}) do',adapter.index('function Adapter.Build()'))]
watcher_access=watcher[watcher.index('local function previewEnabled()'):watcher.index('local function finite(value)')]
test='''local Routing=(function()\n'''+routing+'''\nend)()
local ordinary={name="ordinary",developer=false}
local developer={name="developer",developer=true}
local DevAccess={IsAllowed=function(p)return p.developer==true end}
local function makePolicy(initial)
 local attrs=table.clone(initial or {})
 local workspace={GetAttribute=function(_,k)return attrs[k]end,SetAttribute=function(_,k,v)attrs[k]=v end}
'''+policy+'''
 local roster={}
 local Players={GetPlayers=function()return roster end}
 local function buildAuthorized(group)
  roster=group
  return pcall(function()
'''+adapter_access+'''
  end)
 end
'''+watcher_access+'''
 return {allows=canAccessLevel,ceiling=devCeiling,builds=buildAuthorized,watcher=previewEnabled,attrs=attrs}
end
local count=0
local function equal(actual,expected,message)
 count+=1
 assert(actual==expected,message..": expected "..tostring(expected)..", got "..tostring(actual))
end
local default=makePolicy()
equal(default.attrs.Level5PublicPreviewEnabled,true,"public preview opens by default")
equal(default.allows(5,{ordinary}),true,"ordinary player may enter 5")
equal(default.ceiling({ordinary}),5,"ordinary transport preserves 5")
equal(default.builds({ordinary}),true,"ordinary roster may build 5")
equal(default.allows(4,{ordinary}),false,"ordinary player denied 4")
equal(default.allows(6,{ordinary}),false,"ordinary player denied 6")
equal(default.allows(5,{developer,ordinary}),true,"mixed party may enter 5")
equal(default.allows(4,{developer,ordinary}),false,"developer cannot carry ordinary player into 4")
equal(default.allows(4,{developer}),true,"developer access to 4 retained")
equal(default.allows(5,{}),false,"empty public roster denied")
equal(default.ceiling({}),3,"empty roster does not gain ceiling")
for _,bad in ipairs({0,-1,3.5,5.5,6,999,math.huge,-math.huge,0/0,"invalid"})do
 equal(default.allows(bad,{ordinary}),false,"invalid requested level refused")
end
equal(default.allows("5",{ordinary}),true,"existing numeric-string level accepted")
equal(Routing.MaxLevel,3,"campaign maximum unchanged")
equal(Routing.NextLevel(1),2,"campaign 1 -> 2")
equal(Routing.NextLevel(2),3,"campaign 2 -> 3")
equal(Routing.NextLevel(3),nil,"campaign ends after 3")
equal(Routing.NextLevel(5),nil,"preview has no continuation")
for _,public in ipairs({false,true})do
 for _,dev4 in ipairs({false,true})do
  for _,dev5 in ipairs({false,true})do
   local p=makePolicy({Level5PublicPreviewEnabled=public,Level4DevEnabled=dev4,Level5DevEnabled=dev5})
   equal(p.attrs.Level5PublicPreviewEnabled,public,"explicit public setting retained")
   for _,case in ipairs({{group={ordinary},allDev=false,name="ordinary"},{group={developer},allDev=true,name="developer"},{group={developer,ordinary},allDev=false,name="mixed"}})do
    local g=case.group
    equal(p.allows(5,g),public or (dev5 and case.allDev),case.name.." level 5 policy")
    equal(p.builds(g),public or (dev5 and case.allDev),case.name.." adapter policy")
    equal(p.allows(4,g),dev4 and case.allDev,case.name.." level 4 policy")
    equal(p.allows(6,g),false,case.name.." level 6 denied")
    for level=1,3 do equal(p.allows(level,g),true,"campaign access preserved")end
    if p.allows(5,g)then
     local packet=Routing.ArrivalPacket({Ceiling=p.ceiling(g),Level=5,SessionId="public-preview-test",Expected=#g,Final=true})
     equal(packet.Level,5,"launch packet retains destination 5")
     equal(p.allows(packet.Level,g),true,"destination authorizes same group")
     equal(Routing.ClampLevelTo(packet.Level,p.ceiling(g)),5,"destination clamp retains 5")
    end
   end
   equal(p.watcher(),public or dev5,"watcher respects public/private availability")
  end
 end
end
local closed=makePolicy({Level5PublicPreviewEnabled=false,Level4DevEnabled=false,Level5DevEnabled=false})
equal(closed.ceiling({ordinary}),3,"closed public transport falls back to campaign")
equal(closed.ceiling({developer}),3,"both developer flags off retain campaign ceiling")
equal(closed.builds({developer}),false,"both preview modes disabled reject build")
print("Access policy: "..count.." behavioral assertions passed")
'''
testfile=out/'access_policy.luau';testfile.write_text(test)
result=subprocess.run([str(LUAU/'luau'),str(testfile)],capture_output=True,text=True)
assert result.returncode==0,result.stderr+result.stdout
checks.append({'test':'extracted production access policy + original routing','passed':True,'detail':result.stdout.strip()})
# Scope checks guard against silently manufacturing a clear in this access patch.
for field in ['Escaped','PuzzleWon']:
    needle='SetAttribute("'+field+'"'
    assert adapter.count(needle)==0
assert 'GeometryOnly_NoSlideOrCompletion' in (BASE/'ServerScriptService/Level 5 Systems/Level 5 Landmark Districts.ModuleScript.lua').read_text()
assert adapter.count('SetAttribute("Level5_MapOnly", true)')==2
assert 'Use the lobby control to return.' in adapter
assert 'remote:FireServer("leaveround")' in (BASE/'StarterPlayer/StarterPlayerScripts/Round Exit Client.LocalScript.lua').read_text()
assert 'if DevAccess.IsAllowed(player)' not in adapter[adapter.index('local function addPreviewNotices'):adapter.index('function Adapter.Build()')]
checks.append({'test':'scope and preview boundary','passed':True,'detail':'MapOnly identity retained; no Escaped/PuzzleWon writer; H slide geometry untouched; existing Back to Lobby control retained.'})
(ROOT/'validation.json').write_text(json.dumps(checks,indent=2)+'\n')
print(json.dumps(checks,indent=2))
