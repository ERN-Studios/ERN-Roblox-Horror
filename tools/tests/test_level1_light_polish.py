"""Run the actual preview fixture layout and ceiling aperture geometry."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRAFT = ROOT / "ServerScriptService/Level 1 Systems"


def main():
    source = (DRAFT / "BlenderRoomRenderer.ModuleScript.lua").read_text(encoding="utf-8")
    layout = source[source.index("function Renderer.SkinLayout("):source.index("function Renderer.SkinCarriedFuse(")]
    program = "local Renderer={}\nlocal Vector3={new=function(x,y,z)return {X=x,Y=y,Z=z} end}\n" + layout + r'''
for _,scale in ipairs({1,2}) do
 local tile=4*scale
 local pieces=Renderer.CeilingPieces(Vector3.new(24*scale,.36,24*scale),tile)
 local area=0
 assert(#pieces==4)
 for _,p in ipairs(pieces) do
  local c,s=p[1],p[2]
  assert(s.X>0 and s.Y==.36 and s.Z>0)
  local x0,x1,z0,z1=c.X-s.X/2,c.X+s.X/2,c.Z-s.Z/2,c.Z+s.Z/2
  assert(x1<=0 or x0>=tile or z1<=0 or z0>=tile,"slab occludes recessed tube")
  area+=s.X*s.Z
 end
 assert(math.abs(area-((24*scale)^2-tile^2))<1e-8,"ceiling aperture area")
 for _,name in ipairs({"GridFixture","Fluorescent"}) do
  local ratio,offset,isFixture=Renderer.SkinLayout(name,Vector3.new(tile-.08*scale,.15,tile-.08*scale),Vector3.new(4,.637995,4))
  assert(isFixture and ratio.Y==1,"preserve tube and grille depth")
  assert(math.abs(14+offset.Y-.637995/2-13.96)<1e-8,"fixture underside flush")
  assert(tile/2-2*ratio.X>.0275*scale and tile/2+2*ratio.X<tile-.0275*scale,"one tile clear of both seams")
 end
end
local _,elevatorOffset=Renderer.SkinLayout("LightFixture",Vector3.new(2,.3,2),Vector3.new(4,.637995,4))
assert(math.abs(elevatorOffset.Y-(.3-.637995)/2)<1e-8,"elevator fixture mounting unchanged")
print("Level 1 light polish: actual aperture, flush height, tile seams and elevator mounting passed")
'''
    maze = (DRAFT / "MazeGenerator.Script.lua").read_text(encoding="utf-8")
    grade_block = maze[maze.index('local grade = Lighting:'):maze.index('-- \u2500\u2500 light control:')]
    program += r'''
local Lighting={}
local savedGrade={Brightness=-.02,Saturation=-.3,Parent=Lighting}
Lighting.FindFirstChild=function()return savedGrade end
local blender=true
local release
local maze={Destroying={Connect=function(_,callback)release=callback end}}
local Color3={fromRGB=function()return {} end}
''' + grade_block + r'''
savedGrade.Brightness=.009999999776482582 -- Actual engine float32 property value.
release()
assert(savedGrade.Brightness==-.02,"preview grade restores quantized property on cleanup")
'''
    binary = ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe"
    with tempfile.TemporaryDirectory(prefix="level1-light-polish-") as directory:
        target=Path(directory)/"layout.luau"
        target.write_text(program,encoding="utf-8")
        subprocess.run([str(binary),str(target)],check=True)
    for filename in ("BlenderRoomRenderer.ModuleScript.lua","MazeGenerator.Script.lua","PuzzleManager.Script.lua"):
        subprocess.run([str(binary.with_name("luau-compile.exe")),"--null",str(DRAFT/filename)],check=True)


if __name__ == "__main__":
    main()
