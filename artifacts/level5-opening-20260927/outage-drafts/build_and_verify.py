from pathlib import Path
import ast,difflib,hashlib,json,subprocess
R=Path(__file__).resolve().parent
BASE=R.parent/'baseline/sources'
REL=Path('ServerScriptService/Level 5 Systems/Level 5 Power Outage.ModuleScript.lua')
source=(BASE/REL).read_text()
flag='local OUTAGES_ENABLED=false -- Temporarily disabled at the owner\'s request; keep fixture metadata and cleanup.\n'
needle='local Outage={}\n';assert source.count(needle)==1
trigger='function Outage.Trigger(world,gate)\n';assert source.count(trigger)==1
guard='\tif not OUTAGES_ENABLED then return false,"Level 5 outages are temporarily disabled" end\n'
draft=source.replace(needle,needle+flag).replace(trigger,trigger+guard)
dest=R/'sources'/REL;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(draft)
(R/'outage.patch').write_text(''.join(difflib.unified_diff(source.splitlines(True),draft.splitlines(True),fromfile='baseline/'+str(REL),tofile='draft/'+str(REL))))
# Check that the two public lifecycle functions remain byte-for-byte identical.
def slice_part(text,start,end):return text[text.index(start):text.index(end)]
assert slice_part(source,'function Outage.Cleanup(world)','function Outage.Trigger(world,gate)')==slice_part(draft,'function Outage.Cleanup(world)','function Outage.Trigger(world,gate)')
assert draft.replace(flag,'').replace(guard,'')==source
sha=lambda s:hashlib.sha256(s.encode()).hexdigest()
record={'file':str(REL),'baselineSha256':sha(source),'draftSha256':sha(draft),'change':'Two-line reversible module-local switch and first-statement Trigger guard','liveApplied':False,'disabledReason':'Level 5 outages are temporarily disabled'}
(R/'manifest.json').write_text(json.dumps(record,indent=2)+'\n')
LUAU=R.parents[1]/'level5-build/tools/luau'
result=subprocess.run([str(LUAU/'luau-compile'),'-O0','--null',str(dest)],capture_output=True,text=True)
assert result.returncode==0,result.stderr+result.stdout
# Reuse only the bounded fake Roblox-service objects from the previous lifecycle harness.
repo=R.parents[1]/'level5-window-watcher-repository'
oldtest=repo/'artifacts/level5-exit-eyes-20260926/tests/run_outage_lifecycle.py'
module=ast.parse(oldtest.read_text())
harness=next(ast.literal_eval(n.value) for n in module.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='harness' for t in n.targets))
harness=harness.split('local world,manifest,fixtures,architecture=build()')[0]
old='''local loaded,Pure=pcall(require,"../patches/Level5OutageLogic.ModuleScript")
if not loaded then Pure=require("../../../ReplicatedStorage/Level5OutageLogic.ModuleScript") end'''
assert old in harness
pure=(BASE/'ReplicatedStorage/Level5OutageLogic.ModuleScript.lua').read_text()
harness=harness.replace(old,'local Pure=(function()\n'+pure+'\nend)()\nlocal originalNewSchedule=Pure.NewSchedule\nPure.NewSchedule=function(...) calls.schedule+=1;return originalNewSchedule(...) end')
harness=harness.replace('local RealTypeof=typeof','local calls={schedule=0,encode=0,time=0,attributeWrites=0}\nlocal RealTypeof=typeof')
harness=harness.replace('function o:SetAttribute(k,v)self.attrs[k]=v end','function o:SetAttribute(k,v)calls.attributeWrites+=1;self.attrs[k]=v end')
harness=harness.replace('function workspace:GetServerTimeNow()return time end','function workspace:GetServerTimeNow()calls.time+=1;return time end')
harness=harness.replace('function HttpService:JSONEncode(s)return','function HttpService:JSONEncode(s)calls.encode+=1;return')
harness=harness.replace('__PRODUCT__',draft)
tests=r'''
local disabledReason="Level 5 outages are temporarily disabled"
local coldOk,coldReason=Outage.Trigger(nil,nil)
check(coldOk==false and coldReason==disabledReason,"Guard runs before session and argument inspection")
local world,manifest,fixtures,architecture=build()
local result=Outage.Start(world,manifest)
check(result.ok and result.fixtureCount==8,"Start still annotates all eight sections")
check(RunService.Heartbeat:Count()==1,"Start keeps its single bounded lifecycle heartbeat")
check(world.Destroying:Count()==1 and world.AncestryChanged:Count()==1 and architecture.AncestryChanged:Count()==1,"Start keeps cleanup signal ownership")
near(world:GetAttribute("Level5OutageExemptMin").Z,2456,"H bounds remain available")
near(world:GetAttribute("Level5OutageExitMin").Y,-10,"Descent exemption metadata remains available")
for i,f in ipairs(fixtures)do
 check(f:GetAttribute("Level5OutageSection")==i,"Fixture section metadata retained")
 check(f:GetAttribute("Level5OutageOrder")==0,"Fixture order metadata retained")
 check(f.Material=="Neon" and f.Color=="original" and f.Brightness==1,"Server still does not change fixture visuals")
end
check(fixtures[8]:GetAttribute("FailedTube")==true,"H authored failed tube preserved")
local writesBefore=calls.attributeWrites
local timeBefore=calls.time
for _,gate in ipairs({1,2,3,4,5,6,7,0,8,-1,3.5,"x"})do
 local ok,reason=Outage.Trigger(world,gate)
 check(ok==false and reason==disabledReason,"Trigger consistently reports temporary disable")
 check(world:GetAttribute("Level5OutageSchedule")==nil,"No client blackout schedule replicated")
end
for _=1,3 do
 local ok,reason=Outage.Trigger(world,1)
 check(ok==false and reason==disabledReason,"Repeated gate call stays disabled without marking seen")
end
check(calls.attributeWrites==writesBefore,"Disabled triggers never mutate any instance attribute")
check(calls.schedule==0 and calls.encode==0,"Disabled triggers allocate/encode no schedule")
check(calls.time==timeBefore,"Disabled triggers do not read schedule timing")
check(RunService.Heartbeat:Count()==1,"Disabled triggers create no connections")
check(not Outage.Start(world,manifest).ok,"Duplicate Start ownership still protected")
time=1000;RunService.Heartbeat:Fire(.25)
check(world:GetAttribute("Level5OutageSchedule")==nil,"Heartbeat never invents a disabled schedule")
fixtures[1]:SetAttribute("Level5OutageSection",99)
world:SetAttribute("Level5OutageExemptMax","foreign bounds")
world:SetAttribute("Level5OutageSchedule","foreign schedule")
local foreignWrites=calls.attributeWrites
local ok,reason=Outage.Trigger(world,2)
check(ok==false and reason==disabledReason,"Foreign owner still sees disabled response")
check(calls.attributeWrites==foreignWrites and world:GetAttribute("Level5OutageSchedule")=="foreign schedule","Foreign schedule untouched")
world.Destroying:Fire()
check(RunService.Heartbeat:Count()==0,"Destroy cleanup disconnects heartbeat")
check(world.Destroying:Count()==0 and world.AncestryChanged:Count()==0 and architecture.AncestryChanged:Count()==0,"All owned signals disconnect")
check(world:GetAttribute("Level5OutageExemptMin")==nil and world:GetAttribute("Level5OutageExitMin")==nil,"Cleanup restores owned world attributes")
check(world:GetAttribute("Level5OutageExemptMax")=="foreign bounds" and world:GetAttribute("Level5OutageSchedule")=="foreign schedule","Cleanup preserves other owners")
check(fixtures[1]:GetAttribute("Level5OutageSection")==99,"Cleanup preserves newer fixture ownership")
check(fixtures[8]:GetAttribute("Level5OutageSection")==nil and fixtures[8]:GetAttribute("FailedTube")==true,"Cleanup preserves authored failed tube")
Outage.Cleanup(world);check(RunService.Heartbeat:Count()==0,"Repeated cleanup remains safe")
local second,m2,f2,a2=build();check(Outage.Start(second,m2).ok,"Fresh world still starts normally")
a2.Parent=nil;a2.AncestryChanged:Fire()
check(RunService.Heartbeat:Count()==0,"Architecture removal cleans current session")
local third,m3=build();m3.Zones[8].Model.Name="WrongFinalZone"
local failed=Outage.Start(third,m3)
check(not failed.ok and RunService.Heartbeat:Count()==0,"Failed Start rolls back")
check(third:GetAttribute("Level5OutageExemptMin")==nil,"Failed Start leaves no owned bounds")
check(calls.schedule==0 and calls.encode==0,"No test ever allocated or encoded outage schedule")
print("PASS disabled-outage lifecycle: "..assertions.." behavioral assertions; mock services, not native playtest")
'''
runner=R/'checks/disabled_outage_lifecycle.luau';runner.write_text(harness+tests)
run=subprocess.run([str(LUAU/'luau'),str(runner)],capture_output=True,text=True)
assert run.returncode==0,run.stderr+run.stdout
report={'compile':{'passed':True,'mode':'Luau O0 syntax/bytecode'},'scope':{'passed':True,'startCleanupLiveHelpersUnchanged':True,'onlySwitchAndTriggerGuard':True},'behavioralMock':{'passed':True,'detail':run.stdout.strip()},'native':{'verified':False,'note':'Parent will install after playtest ends and verify natively; no Studio or repo write performed.'}}
(R/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
