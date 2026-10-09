"""Execute the real arrival shell/wall builders, then check their solid geometry.

The Luau host only supplies Roblox math/Instance constructors. The assertions
use the generated boxes and WedgePart triangles, including the actual tube
panels, instead of repeating the aperture-construction formula. Studio still
must confirm rendered seams and the engine's WedgePart orientation.
"""

import argparse
from dataclasses import dataclass
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / "ServerScriptService/Level 3 Systems"
BUILDER = SYSTEMS / "Level 3 World Builder.ModuleScript.lua"


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


HOST = r'''
local Vector3 = {}
local vm = {}; vm.__index = function(v,k)
    if k == "Magnitude" then return math.sqrt(v:Dot(v)) end
    if k == "Unit" then return v / v.Magnitude end
    return vm[k]
end
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vm) end
vm.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__mul = function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
vm.__div = function(a,b) return a*(1/b) end
vm.__unm = function(a) return a*-1 end
function vm:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function vm:Cross(b) return Vector3.new(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
Vector3.xAxis=Vector3.new(1,0,0);Vector3.yAxis=Vector3.new(0,1,0);Vector3.zAxis=Vector3.new(0,0,1)
local CFrame = {}; local cm={};cm.__index=cm
function CFrame.fromMatrix(p,x,y,z) return setmetatable({Position=p,X=x,Y=y,Z=z or x:Cross(y)},cm) end
function CFrame.new(x,y,z)
    local p=type(x)=="table" and x or Vector3.new(x or 0,y or 0,z or 0)
    return CFrame.fromMatrix(p,Vector3.xAxis,Vector3.yAxis,Vector3.zAxis)
end
function cm:VectorToWorldSpace(p) return self.X*p.X+self.Y*p.Y+self.Z*p.Z end
function CFrame.fromAxisAngle(axis,angle)
    local c,s=math.cos(angle),math.sin(angle)
    local function rotate(v) return v*c+axis:Cross(v)*s+axis*(axis:Dot(v)*(1-c)) end
    return CFrame.fromMatrix(Vector3.new(0,0,0),rotate(Vector3.xAxis),rotate(Vector3.yAxis),rotate(Vector3.zAxis))
end
local Color3={fromRGB=function(...) return {...} end}
local PhysicalProperties={new=function(...) return {...} end}
local Enum={Material={SmoothPlastic="SmoothPlastic",Plaster="Plaster"},
    SurfaceType={Smooth="Smooth"},NormalId={Right="Right",Left="Left",Back="Back",Front="Front"}}
local nodes={};local Instance={}
function Instance.new(class)
    local node={ClassName=class,Attributes={},CanCollide=true,CanQuery=true,CanTouch=true}
    function node:SetAttribute(k,v) self.Attributes[k]=v end
    table.insert(nodes,node);return node
end
local Configuration=__CONFIG__
Configuration.TextureStuds={OrangeWall=8}
local TEXTURES={OrangeWall="ignored"}
local function texture(...) end
local function usesWallpaper(_) return false end
__PART_HELPERS__
__POSITION__
__WALL_COLOR__
__WALL_BUILDERS__
__ARRIVAL_PREFIX__
__APERTURE__
    return visual
end
local room={Id="Arrival",W=96,D=96,X=0,Z=0}
local parent=Instance.new("Model")
do
    local model,p,color,material=parent,worldPosition(room),{},Enum.Material.Plaster
__FLOOR__
end
makeWall(parent,room,"West",true)
local visual=makeArrivalElevator(parent,room)
local mouth=visual.Attributes.Level3_SlideMouthPosition
local function vector(v) return string.format("%.17g,%.17g,%.17g",v.X,v.Y,v.Z) end
print("MOUTH|"..vector(mouth))
print("FLOOR|"..tostring(Configuration.WorldOrigin.Y))
local shellCount,runoutCount=0,0
for _,node in ipairs(nodes) do
    local category=nil
    if node.Attributes.Level3_TransitionWallSeal then
        category="seal"
        assert(node.Anchored and not node.CanCollide and not node.CanQuery and not node.CanTouch and not node.CastShadow,
            "wall seals must remain decorative")
    elseif node.Name=="Level 2 Exit Slide Fiberglass Shell" then
        shellCount+=1
        if shellCount<=20 then category="shell";assert(node.CanCollide,"shell remains collision authority") end
    elseif node.Name=="Level 2 Exit Slide Runout" then
        runoutCount+=1
        if runoutCount==1 then category="support" end
    elseif node.Name=="Level 3 Room Floor" then category="support"
    elseif node.Name and string.find(node.Name,"Level 3 West ",1,true) then category="wall" end
    if category then
        local cf=node.CFrame
        print(table.concat({category,node.ClassName,node.Name,vector(cf.Position),vector(node.Size),
            vector(cf.X),vector(cf.Y),vector(cf.Z)},"|"))
    end
end
'''


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def scale(a, amount):
    return tuple(x * amount for x in a)


@dataclass
class Solid:
    kind: str
    shape: str
    name: str
    center: tuple
    size: tuple
    axes: tuple

    def local(self, point):
        delta = sub(point, self.center)
        return tuple(dot(delta, axis) for axis in self.axes)

    def contains(self, point, epsilon=1e-8):
        p = self.local(point)
        if any(abs(p[i]) > self.size[i] / 2 + epsilon for i in range(3)):
            return False
        return self.shape != "WedgePart" or p[1] / self.size[1] <= p[2] / self.size[2] + epsilon

    def vertices(self):
        yz = [(-1, -1), (-1, 1), (1, 1)] if self.shape == "WedgePart" else [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        return [add(self.center, add(scale(self.axes[0], x * self.size[0] / 2),
                    add(scale(self.axes[1], y * self.size[1] / 2), scale(self.axes[2], z * self.size[2] / 2))))
                for x in (-1, 1) for y, z in yz]

    def ray(self, origin, target):
        """Segment intersection with box half-spaces and the real wedge slope."""
        start, end = self.local(origin), self.local(target)
        direction = sub(end, start)
        planes = [(scale(tuple(1 if j == i else 0 for j in range(3)), sign), self.size[i] / 2)
                  for i in range(3) for sign in (-1, 1)]
        if self.shape == "WedgePart":
            planes.append(((0, 1 / self.size[1], -1 / self.size[2]), 0))
        enter, leave = 0.0, 1.0
        for normal, limit in planes:
            distance, speed = limit - dot(normal, start), dot(normal, direction)
            if abs(speed) < 1e-12:
                if distance < -1e-8:
                    return None
            elif speed > 0:
                leave = min(leave, distance / speed)
            else:
                enter = max(enter, distance / speed)
            if enter > leave + 1e-8:
                return None
        return enter


def build_geometry(binary, builder):
    source = builder.read_text(encoding="utf-8")
    config = (SYSTEMS / "Level 3 Configuration.ModuleScript.lua").read_text(encoding="utf-8")
    values = [f"{name}={re.search(rf'{name} = ([0-9.]+)', config).group(1)}"
              for name in ("WallThickness", "FloorThickness", "RoomHeight", "CorridorWidth", "CorridorHeight")]
    values += ["WorldOrigin=" + re.search(r"WorldOrigin = (Vector3.new\([^\n]+\)),", config).group(1)]
    arrival = section(source, "local function makeArrivalElevator(", "\t-- The resume frame:")
    after_axis = source.index("\n", source.index("\tlocal rearAxis =")) + 1
    aperture = source[after_axis:source.index("\t-- The physical safety stop", after_axis)]
    replacements = {
        "__CONFIG__": "{" + ",".join(values) + "}",
        "__PART_HELPERS__": section(source, "local function part(", "local function texture("),
        "__POSITION__": section(source, "local function worldPosition(", "local RED_PARTY_ROOMS"),
        "__WALL_COLOR__": section(source, "local function wallColor(", "local function lightTone("),
        "__WALL_BUILDERS__": section(source, "local function wallSegment(", "local function makeCeilingGrid("),
        "__FLOOR__": section(source, '\tlocal floorPart = part(model, "Level 3 Room Floor"', '\tif textureId then texture(floorPart'),
        "__ARRIVAL_PREFIX__": arrival,
        "__APERTURE__": aperture,
    }
    host = HOST
    for marker, content in replacements.items():
        host = host.replace(marker, content)
    with tempfile.TemporaryDirectory(prefix="level3-slide-aperture-") as directory:
        path = Path(directory) / "geometry.luau"
        path.write_text(host, encoding="utf-8")
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=20)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
    solids = []
    for line in result.stdout.splitlines():
        cells = line.split("|")
        if cells[0] == "MOUTH":
            mouth = tuple(map(float, cells[1].split(",")))
        elif cells[0] == "FLOOR":
            floor = float(cells[1])
        else:
            vectors = [tuple(map(float, cell.split(","))) for cell in cells[3:]]
            solids.append(Solid(*cells[:3], *vectors[:2], tuple(vectors[2:])))
    return solids, mouth, floor


def verify(solids, mouth, floor, geometry_only=False):
    checks = 0

    def check(value, message):
        nonlocal checks
        checks += 1
        assert value, message

    shell = [solid for solid in solids if solid.kind == "shell"]
    seals = [solid for solid in solids if solid.kind == "seal"]
    orange = [solid for solid in solids if solid.kind in ("wall", "seal")]
    shell_and_support = [solid for solid in solids if solid.kind in ("shell", "support")]
    wall_x = seals[0].center[0]
    depth = seals[0].size[0]
    xs = [wall_x - depth / 2, wall_x, wall_x + depth / 2]

    # Convex separation proves the ENTIRE triangular/rectangular seal prism lies
    # outside at least one bore half-space, not just a handful of sampled corners.
    clearance = math.inf
    for seal in seals:
        vertices = seal.vertices()
        margin = max(min(dot(sub(vertex, panel.center), panel.axes[1]) + panel.size[1] / 2
                         for vertex in vertices) for panel in shell)
        clearance = min(clearance, margin)
        check(margin > 0, f"orange intrusion: {seal.name}, bore clearance {margin:.8f}")
        check(all(size > 0 for size in seal.size), "nonpositive seal dimension")

    # Include every band join, wedge-to-rectangle join, and near-join point.
    # A coarse grid alone misses the narrow black staircase and top sliver.
    ys = {floor + i * 16.1 / 80 for i in range(81)}
    for seal in seals:
        for vertex in seal.vertices():
            for delta in (-1e-5, 0, 1e-5):
                ys.add(vertex[1] + delta)
    sample_count = 0
    for x in xs:
        for y in sorted(ys):
            if y < floor or y > floor + 16.1:
                continue
            axis_point = (x, y, mouth[2])
            boundary = min(dot(sub(panel.center, axis_point), panel.axes[1]) / panel.axes[1][2]
                           for panel in shell if panel.axes[1][2] > 1e-8)
            zs = {mouth[2] + i / 10 for i in range(-80, 81)}
            for sign in (-1, 1):
                for delta in (-.16, -.01, 0, .01, .16, .30, .60):
                    zs.add(mouth[2] + sign * (boundary + delta))
            for z in zs:
                if abs(z - mouth[2]) > 8.0:
                    continue
                point = (x, y, z)
                in_bore = all(dot(sub(point, panel.center), panel.axes[1]) < -panel.size[1] / 2 - 1e-7
                              for panel in shell)
                in_orange = any(solid.contains(point) for solid in orange)
                if in_bore:
                    check(not in_orange, f"wall/lintel intrudes into bore at {point}")
                else:
                    check(in_orange or any(panel.contains(point) for panel in shell_and_support),
                          f"unfilled wall opening at {point}")
                sample_count += 1

    # From front and ±oblique viewpoints INSIDE the mouth silhouette, every
    # visible panel interior remains fiberglass, never an orange block.
    ray_count = 0
    axis = shell[0].axes[0]
    for camera_delta in ((6, 0, 0), (6, 2, 4), (6, 2, -4), (4, -3, 2)):
        camera = add(mouth, camera_delta)
        for panel in shell:
            normal = panel.axes[1]
            radius = dot(sub(panel.center, mouth), normal)
            for along in (.35, .8, 1.5):
                target = add(mouth, add(scale(axis, along), scale(normal, radius - panel.size[1] / 2 + 1e-5)))
                hits = [(hit, solid.kind) for solid in solids if (hit := solid.ray(camera, target)) is not None]
                check(bool(hits), "ray leaked past the mouth wall and shell")
                check(min(hits)[1] in ("shell", "support"), f"orange occludes bore from {camera_delta}: {panel.name}")
                ray_count += 1

    if not geometry_only:
        check(len(seals) == 40, f"seal budget changed to {len(seals)}")
        check(sum(s.shape == "WedgePart" for s in seals) == 20, "expected twenty polygon-matched wedges")
        check(len(shell) == 20, "tube collision section changed")
        check(clearance > .14, f"insufficient seam margin {clearance}")
    print(f"Level 3 slide aperture: {checks} checks passed; {sample_count} volume samples, "
          f"{ray_count} front/oblique rays, {len(seals)} seals, minimum bore clearance {clearance:.6f} studs")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--builder", type=Path, default=BUILDER)
    parser.add_argument("--geometry-only", action="store_true", help="also compare old box-strip builders")
    args = parser.parse_args()
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or put luau on PATH; no tests executed.")
    verify(*build_geometry(binary, args.builder), geometry_only=args.geometry_only)


if __name__ == "__main__":
    main()
