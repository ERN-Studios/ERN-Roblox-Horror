"""Offline actual sampler guards/aggregation test; never connects to Studio."""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

MOCK = r'''
local checks=0
for _,mode in ipairs({"client","server","unavailable","tracking-disabled","interrupted"}) do
 local clock,frameReads,tagCalls=0,0,0
 local os={clock=function() return clock end,date=function() return "offline" end}
 local task={wait=function(delay) clock=math.round((clock+delay)*100000)/100000; return 999 end}
 local Instance={new=function() error("Sampler must not create fixture Instances") end}
 local run={IsRunning=function() return mode~="interrupted" or clock<1 end,IsClient=function() return mode~="server" end}
 local children={GetChildren=function() return {} end,FindFirstChild=function() return nil end}
 local players={GetPlayers=function() return {} end}
 local workspace={GetChildren=function() return {} end,GetAttribute=function() return nil end}
 local tags={{Name="Instances"},{Name="LuaHeap"}}
 local Enum={DeveloperMemoryTag={GetEnumItems=function() return tags end}}
 local stats=setmetatable({}, {__index=function(_,key)
  if key=="MemoryTrackingEnabled" then return mode~="tracking-disabled" end
  if key=="GetTotalMemoryUsageMb" then return function()
   if mode=="unavailable" then error("Synthetic inaccessible total memory") end
   return 77
  end end
  if key=="GetMemoryUsageMbForTag" then return function(_,tag)
   tagCalls+=1; assert(mode~="tracking-disabled","Disabled memory tags were still sampled")
   return if tag.Name=="Instances" then 12 else 4
  end end
  if key=="FrameTime" then frameReads+=1; return if frameReads%2==0 then 0.02 else 0.01 end
  if key=="PhysicsStepTime" and mode=="unavailable" then return 0/0 end
  if key=="SceneTriangleCount" and mode=="unavailable" then error("Synthetic inaccessible renderer property") end
  if key=="PhysicsStepTime" then return 0.003 end
  if key=="HeartbeatTime" then return 0.002 end
  return 0 -- genuine native zero observation stand-in, not unavailable fallback
 end})
 local services={HttpService={JSONEncode=function(_,value) return value end},RunService=run,
  Stats=stats,Players=players,ReplicatedStorage=children,StarterPlayer=children}
 local game={PlaceId=131311258779917,GameId=10559217407,GetService=function(_,name) return assert(services[name],name) end}
 local report=(function()
'''

CHECKS = r'''
 end)()
 assert(report.fpsClaim==false and report.mutations==false)
 assert(report.stats.PhysicsStepTime.median~=999,"task.wait return was used as CPU time")
 assert(report.after.loadingCovers.available==false,"No PlayerGui was silently represented as hidden")
 assert(report.optimizationPresence.replicatedStorageImports[1].absenceVerified==false,"Missing owner was represented as confirmed Imports absence")
 if mode=="server" then
  assert(frameReads==0 and report.stats.FrameTime.available==false and report.stats.FrameTime.median==nil)
  assert(report.stats.SceneTriangleCount.available==false and report.stats.SceneTriangleCount.median==nil)
 else
  assert(report.stats.FrameTime.p95==0.02 and report.stats.FrameTime.minimum==0.01)
  if mode~="interrupted" then assert(math.abs(report.stats.FrameTime.median-0.015)<1e-10) end
 end
 if mode=="unavailable" then
  assert(report.stats.TotalMemoryUsageMb.available==false and report.stats.TotalMemoryUsageMb.median==nil)
  assert(report.stats.PhysicsStepTime.available==false and report.stats.PhysicsStepTime.p95==nil)
  assert(report.stats.SceneTriangleCount.available==false and report.stats.SceneTriangleCount.minimum==nil)
 else assert(report.stats.TotalMemoryUsageMb.median==77) end
 if mode=="tracking-disabled" then
  assert(tagCalls==0 and report.stats["MemoryTag.Instances"]==nil and report.memoryTagsUnavailable~=nil)
 else assert(tagCalls>0 and report.stats["MemoryTag.Instances"].median==12) end
 if mode=="interrupted" then assert(not report.completeSampleWindow and report.interrupted~=nil)
 else assert(report.completeSampleWindow and report.actualSampleWindowSeconds==3) end
 assert(report.stats.DataSendKbps.available and report.stats.DataSendKbps.allReadingsWereZero)
 checks+=1
end
print("actual Stats sampler offline guards/aggregation: "..checks.." scenarios passed")
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", type=Path, required=True)
    args = parser.parse_args()
    source = (HERE / "measure.luau").read_text(encoding="utf-8")
    output = ROOT / "_local/optimization-20261009/measure-offline-test.luau"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(MOCK + source + CHECKS, encoding="utf-8", newline="\n")
    subprocess.run([str(args.luau.resolve()), str(output)], check=True)


if __name__ == "__main__":
    main()
