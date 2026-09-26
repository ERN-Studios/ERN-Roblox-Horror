"""Execute the current server patch in a bounded fake-service lifecycle harness.
This proves server scheduling/attribute cleanup logic, not native replication or multiplayer.
"""
from pathlib import Path
import subprocess
import tempfile
import os
import shutil
root=Path(__file__).resolve().parents[1]
source_path=root/'patches/Level 5 Power Outage.ModuleScript.lua'
if not source_path.exists(): source_path=root.parents[1]/'ServerScriptService/Level 5 Systems/Level 5 Power Outage.ModuleScript.lua'
source=source_path.read_text()
harness=r'''
local RealTypeof=typeof
local Vector3={}
local VM={};VM.__index=VM
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z,__kind="Vector3"},VM) end
VM.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
VM.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
VM.__div=function(a,b) return Vector3.new(a.X/b,a.Y/b,a.Z/b) end
local function typeof(v) return type(v)=="table" and v.__kind or RealTypeof(v) end
local function Signal()
 local signal={listeners={}}
 function signal:Connect(fn)
  local c={active=true,fn=fn};function c:Disconnect()self.active=false end
  table.insert(self.listeners,c);return c
 end
 function signal:Fire(...)
  for _,c in ipairs(self.listeners) do if c.active then c.fn(...) end end
 end
 function signal:Count() local count=0;for _,c in ipairs(self.listeners) do if c.active then count+=1 end end;return count end
 return signal
end
local function Object(name,class,parent)
 local o={Name=name,ClassName=class,Parent=parent,attrs={},children={},__kind="Instance",Destroying=Signal(),AncestryChanged=Signal()}
 if parent then table.insert(parent.children,o) end
 function o:IsA(c)return self.ClassName==c or self.ClassName=="Part" and c=="BasePart" end
 function o:IsDescendantOf(ancestor)local p=self.Parent;while p do if p==ancestor then return true end;p=p.Parent end;return false end
 function o:GetAttribute(k)return self.attrs[k] end
 function o:SetAttribute(k,v)self.attrs[k]=v end
 function o:FindFirstChild(k)for _,v in ipairs(self.children) do if v.Name==k then return v end end end
 function o:GetDescendants() local all={};local function visit(p)for _,v in ipairs(p.children) do table.insert(all,v);visit(v) end end;visit(self);return all end
 function o:GetFullName()return (self.Parent and self.Parent:GetFullName().."." or "")..self.Name end
 return o
end
local workspace=Object("Workspace","Workspace")
local time=100
function workspace:GetServerTimeNow()return time end
workspace:SetAttribute("SelectedLevel",5);workspace:SetAttribute("RoundActive",true)
local RunService={Heartbeat=Signal()};function RunService:IsServer()return true end;function RunService:IsRunning()return true end
local RS={};function RS:WaitForChild(_)return "LOGIC" end
local HttpService={};function HttpService:JSONEncode(s)return tostring(s.startedAt)..":"..s.restoreAt..":"..s.gate..":"..s.serial end
local services={RunService=RunService,ReplicatedStorage=RS,HttpService=HttpService}
local game={};function game:GetService(name)return services[name] end
local loaded,Pure=pcall(require,"../patches/Level5OutageLogic.ModuleScript")
if not loaded then Pure=require("../../../ReplicatedStorage/Level5OutageLogic.ModuleScript") end
local function require(name)assert(name=="LOGIC");return Pure end
local function LoadProduct()
__PRODUCT__
end
local Outage=LoadProduct()
local assertions=0
local function check(ok,message)assertions+=1;assert(ok,message)end
local function near(a,b,message)check(math.abs(a-b)<1e-7,message)end
local function build()
 local world=Object("Level 5 Generated World","Model",workspace);world:SetAttribute("Level5_MapOnly",true)
 local architecture=Object("Level5_IndoorSuburbs","Model",world)
 local manifest={Origin=Vector3.new(17000,24,0),Zones={}}
 local fixtures={}
 for i=1,8 do
  local zone=Object(i==8 and "H_LastHouse" or "Zone"..i,"Model",architecture)
  zone:SetAttribute("ZoneMin",Vector3.new(-110,0,i==8 and 2456 or i*100))
  zone:SetAttribute("ZoneMax",Vector3.new(110,70,i==8 and 2636 or i*100+100))
  table.insert(manifest.Zones,{Model=zone})
  local fixture=Object("FluorescentPanel","Part",zone);fixture.Position=Vector3.new(17000,90,i*100);fixtures[i]=fixture
  fixture.Material="Neon";fixture.Brightness=1;fixture.Color="original"
  if i==8 then
   fixture:SetAttribute("FailedTube",true)
   local chute=Object("NarrowDescent","Model",zone)
   function chute:GetBoundingBox()return {Position=Vector3.new(17000,12,2647),XVector=Vector3.new(1,0,0),YVector=Vector3.new(0,1,0),ZVector=Vector3.new(0,0,1)},Vector3.new(9,44,65) end
  end
 end
 local owner=Object("Level5SectionProgression","Model",world)
 for i=1,7 do local gate=Object("SectionGate"..i,"Model",owner);gate:SetAttribute("FullyOpen",true)end
 return world,manifest,fixtures,architecture
end
local world,manifest,fixtures,architecture=build()
local result=Outage.Start(world,manifest)
check(result.ok and result.fixtureCount==8,"Eight section fixture groups annotated")
check(RunService.Heartbeat:Count()==1,"One bounded server heartbeat")
check(fixtures[8]:GetAttribute("Level5OutageSection")==8,"H metadata retained")
check(fixtures[8]:GetAttribute("FailedTube")==true,"H original failed state preserved")
for _,f in ipairs(fixtures)do check(f.Material=="Neon" and f.Color=="original" and f.Brightness==1,"Server never changes visuals")end
near(world:GetAttribute("Level5OutageExemptMin").Z,2456,"Main bounds use geometry entry")
near(world:GetAttribute("Level5OutageExemptMin").Y,24,"Main bounds use actual origin")
near(world:GetAttribute("Level5OutageExitMin").Y,-10,"Chute includes below-floor descent")
near(world:GetAttribute("Level5OutageExitMax").Z,2679.5,"Chute envelope follows actual geometry")
check(not Outage.Start(world,manifest).ok,"Duplicate start rejected")
check(not Outage.Trigger(world,7),"Opening final gate never starts a schedule")
check(world:GetAttribute("Level5OutageSchedule")==nil,"Gate7 leaves blank schedule blank")
local ok,s=Outage.Trigger(world,1);check(ok and s.serial==1,"First eligible gate triggers once")
local encoded=world:GetAttribute("Level5OutageSchedule")
time=125
check(not Outage.Trigger(world,7),"Final gate never extends existing outage")
check(world:GetAttribute("Level5OutageSchedule")==encoded,"Gate7 leaves existing schedule exact")
check(not Outage.Trigger(world,1),"Idempotence per gate")
local ok2,s2=Outage.Trigger(world,2);check(ok2 and s2.serial==2 and s2.restoreAt==185,"Next eligible gate extends without relight")
check(s2.startedAt==s.startedAt and s2.blackoutAt==s.blackoutAt,"Overlap wave preserved")
time=186.5;RunService.Heartbeat:Fire(.21)
check(world:GetAttribute("Level5OutageSchedule")==nil,"Natural expiry removes owned schedule")
fixtures[1]:SetAttribute("Level5OutageSection",99)
world:SetAttribute("Level5OutageExemptMax","foreign")
world.Destroying:Fire()
check(RunService.Heartbeat:Count()==0,"World destroy disconnects server heartbeat")
check(world:GetAttribute("Level5OutageExemptMin")==nil and world:GetAttribute("Level5OutageExitMin")==nil,"Owned world bounds removed")
check(world:GetAttribute("Level5OutageExemptMax")=="foreign" and fixtures[1]:GetAttribute("Level5OutageSection")==99,"Foreign later ownership preserved")
check(fixtures[8]:GetAttribute("Level5OutageSection")==nil and fixtures[8]:GetAttribute("FailedTube")==true,"Metadata removed without changing failed tube")
Outage.Cleanup(world);check(RunService.Heartbeat:Count()==0,"Cleanup idempotent")
check(not Outage.Trigger(world,3),"Closed world cannot trigger")
local second,m2,f2,a2=build();check(Outage.Start(second,m2).ok,"Fresh round can attach")
time=200;check(Outage.Trigger(second,1),"Fresh round resets seen-gate state")
second:SetAttribute("Level5OutageSchedule","foreign schedule")
check(not Outage.Trigger(second,2),"Foreign schedule is not overwritten")
a2.Parent=nil;a2.AncestryChanged:Fire()
check(RunService.Heartbeat:Count()==0,"Architecture removal cleans up")
check(second:GetAttribute("Level5OutageSchedule")=="foreign schedule","Cleanup preserves foreign schedule")
local third,m3=build();m3.Zones[8].Model.Name="WrongFinalZone"
local failed=Outage.Start(third,m3)
check(not failed.ok and RunService.Heartbeat:Count()==0,"Bad geometry startup fails and rolls back")
check(third:GetAttribute("Level5OutageExemptMin")==nil,"Failed startup leaves no owned bounds")
print("PASS outage server lifecycle: "..assertions.." assertions (mock services; not native multiplayer)")
'''
runner=root/'tests/_generated_outage_lifecycle.luau'
runner.write_text(harness.replace('__PRODUCT__',source))
try:
    runtime=os.environ.get('LUAU_BIN') or shutil.which('luau')
    if not runtime: raise RuntimeError('Set LUAU_BIN to the standalone Luau interpreter')
    subprocess.run([runtime,str(runner)],check=True)
finally:
    runner.unlink(missing_ok=True)
