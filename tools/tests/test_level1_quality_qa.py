"""Run the actual read-only QA OBB test against independently specified cases."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "artifacts/level1-quality-20261002/qa-runtime.luau"


def main():
    source = PROBE.read_text(encoding="utf-8")
    start = source.index("local function obb(part)")
    end = source.index("local bins,obstacleCount", start)
    program = r'''
local checks=0
local function check(value,label) assert(value,label);checks+=1 end
local Vector3={}
local maze={}
local grid,cell=40,24
local workspace={GetAttribute=function(_,name)return name=="WALL_H" and 14 or nil end}
local mt={}
mt.__index=function(v,k)
 if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
 if k=="Dot" then return function(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
 if k=="Cross" then return function(a,b)return Vector3.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end end
end
function Vector3.new(x,y,z)return setmetatable({X=x,Y=y,Z=z},mt) end
mt.__add=function(a,b)return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
mt.__sub=function(a,b)return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
mt.__mul=function(a,b)
 if type(a)=="number" then return Vector3.new(a*b.X,a*b.Y,a*b.Z) end
 return Vector3.new(a.X*b,a.Y*b,a.Z*b)
end
mt.__div=function(a,b)return Vector3.new(a.X/b,a.Y/b,a.Z/b)end
'''
    program += source[start:end]
    program += r'''
local function part(x,y,z,w,h,d,yaw)
 local a=math.rad(yaw or 0);local c,s=math.cos(a),math.sin(a)
 return {ClassName="Part",Parent=maze,Size=Vector3.new(w,h,d),CFrame={Position=Vector3.new(x,y,z),
 RightVector=Vector3.new(c,0,-s),UpVector=Vector3.new(0,1,0),ZVector=Vector3.new(s,0,c)}}
end
local column=obb(part(0,4,0,2,8,2))
local crossing=obb(part(0,.06,0,.34,.09,10))
check(boxesOverlap(column,crossing),"real floor cable intersects the full-height pillar")
check(boxesOverlap(crossing,column),"SAT collision is symmetric")
check(not boxesOverlap(column,obb(part(2,.06,0,.34,.09,10))),"offset cable clears the pillar")
check(not boxesOverlap(column,obb(part(0,9,0,.34,.09,10))),"cable above the pillar clears")
check(not boxesOverlap(column,obb(part(1.17,.06,0,.34,.09,10))),"exact touching surfaces do not count as penetration")
check(not boxesOverlap(column,obb(part(1.16,.06,0,.34,.09,10))),"one-hundredth-stud join tolerance")
check(boxesOverlap(column,obb(part(1.13,.06,0,.34,.09,10))),"visible penetration exceeds the join tolerance")
local rotated=obb(part(0,4,0,2,8,6,45))
check(math.abs(rotated.high.X-math.sqrt(8))<1e-9,"rotated actual OBB has conservative world bounds")
check(boxesOverlap(rotated,obb(part(2,.06,2,.2,.09,.2))),"wire intersects rotated long axis")
check(not boxesOverlap(rotated,obb(part(2.65,.06,-2.65,.2,.09,.2))),"AABB corner false positive rejected by actual OBB axes")
check(not boxesOverlap(rotated,obb(part(2.65,.06,2.65,.2,.09,.2))),"rotated end face clears its far AABB corner")
local divider=obb(part(0,4.25,0,6,8.5,1.14,90))
check(boxesOverlap(divider,obb(part(0,.06,0,.34,.09,9))),"low divider blocks floor wire")
check(not boxesOverlap(divider,obb(part(0,13.6,0,.34,.09,9))),"actual low divider permits overhead wire")
check(not boxesOverlap(crossing,obb(part(0,-.16,0,24,.32,24))),"floor cable rests above native floor top zero")
local floor=part(12,-.5,12,24,1,24)
check(isStructuralPlane(floor,obb(floor)),"native floor tile excluded by walking-plane identity")
local ceiling=part(0,14.5,0,960,1,960)
check(isStructuralPlane(ceiling,obb(ceiling)),"single full-maze ceiling excluded by actual dimensions")
local tabletop=part(0,4,0,5,.3,3.2)
check(not isStructuralPlane(tabletop,obb(tabletop)),"thin raised tabletop remains a physical obstacle")
local decorSlab=part(12,-.5,12,24,1,24);decorSlab.Parent={}
check(not isStructuralPlane(decorSlab,obb(decorSlab)),"Decor floor-shaped furniture is not a Maze floor")
local smallCeiling=part(0,14.5,0,5,1,5)
check(not isStructuralPlane(smallCeiling,obb(smallCeiling)),"small raised panel does not impersonate world ceiling")
local meshFloor=part(12,-.5,12,24,1,24);meshFloor.ClassName="MeshPart"
check(not isStructuralPlane(meshFloor,obb(meshFloor)),"mesh furniture retains inspection even at the walking plane")
local lowPanel=part(0,.14,0,5,.2,3.2)
check(not isStructuralPlane(lowPanel,obb(lowPanel)),"low furniture panel is not exempt")
check(obb(lowPanel).high.Y>.01 and boxesOverlap(crossing,obb(lowPanel)),"low physical detail intersects a floor cable and enters the new inventory")
local vertical=obb(part(0,6.83,0,.34,13.54,.34))
check(boxesOverlap(vertical,obb(tabletop)),"actual vertical segment intersects thin overhead tabletop")
check(not boxesOverlap(obb(part(3,6.83,0,.34,13.54,.34)),obb(tabletop)),"vertical segment beside the tabletop clears")
local terminal=obb(part(1,1.15,2,.34,2.18,.34))
local terminals={{position=Vector3.new(1,2.24,2),circuit="CIRCUIT_01"}}
check(riserKind(terminal,"CIRCUIT_01",terminals,14)=="terminal","terminal riser recorded by actual jack position and circuit")
check(riserKind(terminal,"CIRCUIT_02",terminals,14)=="other","wrong circuit cannot satisfy terminal coverage")
check(riserKind(obb(part(1.1,1.15,2,.34,2.18,.34)),"CIRCUIT_01",terminals,14)=="other","offset riser cannot satisfy exact terminal coverage")
check(riserKind(vertical,"CIRCUIT_01",terminals,14)=="fullHeight","ceiling-height riser gets its own exercised-case counter")
check(riserKind(obb(part(0,4.28,0,.34,8.44,.34)),"CIRCUIT_01",terminals,14)=="other","unknown short riser is reported rather than assumed terminal")
print("Level 1 quality QA: "..checks.." actual OBB-function checks passed")
'''
    override = os.environ.get("LUAU_BIN")
    known = ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe"
    runtime = override or shutil.which("luau") or (str(known) if known.is_file() else None)
    if not runtime:
        raise SystemExit("Luau runtime missing; no QA geometry checks executed")
    with tempfile.TemporaryDirectory(prefix="level1-quality-qa-") as folder:
        target = Path(folder) / "actual-qa-functions.luau"
        target.write_text(program, encoding="utf-8")
        subprocess.run([runtime, str(target)], cwd=ROOT, check=True, timeout=20)


if __name__ == "__main__":
    main()
