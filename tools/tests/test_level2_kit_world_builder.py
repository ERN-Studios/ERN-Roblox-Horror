"""Execute the kit world builder and its actual consumer validators offline.

Run with ``python -B tools/tests/test_level2_kit_world_builder.py``. The Luau CLI
receives an in-memory loadstring through stdin: no fixture, cache, mutation or
other file is written. No git, network, Studio, MCP, importer or sync tool runs.
The fake installed kit is synthesized from Poolrooms jobs A/B/C (and the swerve
job D when it exists) and the reviewed exit slide templates from Level2_Pool job F.
Meshes have exported bounding boxes, not Roblox collision hulls; this suite
cannot prove physical sliding, real pathfinding, streaming or performance.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
# F9 (WP8): the layout test's independent swerve outline oracle (turtle over the stored segments).
from test_level2_kit_layout import inside_polygon, swerve_outline  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / "ServerScriptService/Level 2 Systems"
BUILDER = SYSTEMS / "Level 2 Kit World Builder.ModuleScript.lua"
LAYOUT = SYSTEMS / "Level 2 Kit Layout Generator.ModuleScript.lua"
CONFIG = SYSTEMS / "Level 2 Configuration.ModuleScript.lua"
OBJECTIVES = SYSTEMS / "Level 2 Objective Controller.ModuleScript.lua"
EXIT_TESTS = SYSTEMS / "Level 2 Exit Transition Test Suite.ModuleScript.lua"
JOBS = Path("G:/Blender/Level2_Poolrooms/jobs")
SLIDES = Path("G:/Blender/Level2_Pool/jobs/F/export/slides.json")
# G8: max over the 10-seed suite (11,509) + 5% (250 seeds: max 11,962); the builder warns past it. WP8 (F9) raises it
# by the swerve delta measured on the 50-seed suite's heaviest map (+264; needs an owner yes). Since the F9 review (an S per
# swerve hall, one per wall, <= 3 halls) that map is 11,906 rectangular -> 12,240 swerved; the suite peaks there.
# FA (mitred square corners, nosed corner deck squares): 12,281 on that map, suite 10,566..12,281 (FA review: 10,566 after the corner-door rule).
# Step S: one SurfaceAppearance per kit tile MeshPart (2,009..2,394 per world, texture bindings only) moves the suite
# from 10,625..12,331 to 12,634..14,694 (heaviest 422893441); the cap is that maximum + the same 18 (owner yes pending).
WORLD_BUDGET = 14712
DEFAULT_BIN = ("C:/Users/mikke/AppData/Local/Packages/OpenAI.Codex_2p2nqsd0c76g0/"
               "LocalCache/Local/CodexTools/luau/0.737/luau.exe")

# Datatypes implement full rigid transforms. A yaw-only fake would falsely pass
# rotated rooms and fail to notice tilted sensor/end-stop installation mistakes.
ENGINE = r'''
local Vector3, CFrame, Color3 = {}, {}, {}
local vectorMethods, cfMethods = {}, {}
local vectorMeta = {__type="Vector3"}
function Vector3.new(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},vectorMeta) end
vectorMeta.__index = function(v,k)
    if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
    if k=="Unit" then return v.Magnitude==0 and Vector3.new() or v/v.Magnitude end
    return vectorMethods[k]
end
vectorMeta.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__unm=function(a) return Vector3.new(-a.X,-a.Y,-a.Z) end
vectorMeta.__mul=function(a,b)
    if type(a)=="number" then return Vector3.new(a*b.X,a*b.Y,a*b.Z) end
    if type(b)=="number" then return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
    return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z)
end
vectorMeta.__div=function(a,b) return Vector3.new(a.X/b,a.Y/b,a.Z/b) end
vectorMeta.__eq=function(a,b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
vectorMeta.__tostring=function(v) return string.format("%.4f, %.4f, %.4f",v.X,v.Y,v.Z) end
function vectorMethods:Dot(v) return self.X*v.X+self.Y*v.Y+self.Z*v.Z end
function vectorMethods:Cross(v) return Vector3.new(self.Y*v.Z-self.Z*v.Y,self.Z*v.X-self.X*v.Z,self.X*v.Y-self.Y*v.X) end
function vectorMethods:Lerp(v,t) return self+(v-self)*t end
Vector3.zero,Vector3.one=Vector3.new(),Vector3.new(1,1,1)
Vector3.xAxis,Vector3.yAxis,Vector3.zAxis=Vector3.new(1,0,0),Vector3.new(0,1,0),Vector3.new(0,0,1)
local cfMeta={__type="CFrame"}
function CFrame.fromMatrix(p,right,up,back)
    return setmetatable({p=p,r=right,u=up,b=back or right:Cross(up)},cfMeta)
end
function CFrame.new(...)
    local a={...}
    if #a==12 then
        return CFrame.fromMatrix(Vector3.new(a[1],a[2],a[3]),Vector3.new(a[4],a[7],a[10]),Vector3.new(a[5],a[8],a[11]),Vector3.new(a[6],a[9],a[12]))
    end
    if #a==2 and getmetatable(a[1])==vectorMeta then return CFrame.lookAt(a[1],a[2]) end
    local p=getmetatable(a[1])==vectorMeta and a[1] or Vector3.new(a[1],a[2],a[3])
    return CFrame.fromMatrix(p,Vector3.xAxis,Vector3.yAxis,Vector3.zAxis)
end
function CFrame.lookAt(p,target,up)
    local look=(target-p).Unit
    local reference=up or Vector3.yAxis
    if math.abs(look:Dot(reference))>.999 then reference=Vector3.zAxis end
    local right=look:Cross(reference).Unit
    return CFrame.fromMatrix(p,right,right:Cross(look),-look)
end
function CFrame.lookAlong(p,direction,up) return CFrame.lookAt(p,p+direction,up) end
function CFrame.Angles(x,y,z)
    local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
    return CFrame.new(0,0,0,cy*cz,-cy*sz,sy,cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy,sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy)
end
CFrame.fromEulerAnglesXYZ=CFrame.Angles
cfMeta.__index=function(c,k)
    if k=="Position" or k=="p" then return rawget(c,"p") end
    if k=="RightVector" or k=="XVector" then return c.r end
    if k=="UpVector" or k=="YVector" then return c.u end
    if k=="LookVector" then return -c.b end
    if k=="ZVector" then return c.b end
    if k=="X" or k=="Y" or k=="Z" then return c.p[k] end
    if k=="Rotation" then return CFrame.fromMatrix(Vector3.zero,c.r,c.u,c.b) end
    return cfMethods[k]
end
function cfMethods:VectorToWorldSpace(v) return self.r*v.X+self.u*v.Y+self.b*v.Z end
function cfMethods:VectorToObjectSpace(v) return Vector3.new(v:Dot(self.r),v:Dot(self.u),v:Dot(self.b)) end
function cfMethods:PointToWorldSpace(v) return self.p+self:VectorToWorldSpace(v) end
function cfMethods:PointToObjectSpace(v) return self:VectorToObjectSpace(v-self.p) end
function cfMethods:Inverse()
    local c=CFrame.new(0,0,0,self.r.X,self.r.Y,self.r.Z,self.u.X,self.u.Y,self.u.Z,self.b.X,self.b.Y,self.b.Z)
    return CFrame.fromMatrix(c:VectorToWorldSpace(-self.p),c.r,c.u,c.b)
end
function cfMethods:ToObjectSpace(other) return self:Inverse()*other end
function cfMethods:ToWorldSpace(other) return self*other end
function cfMethods:GetComponents() return self.p.X,self.p.Y,self.p.Z,self.r.X,self.u.X,self.b.X,self.r.Y,self.u.Y,self.b.Y,self.r.Z,self.u.Z,self.b.Z end
cfMeta.__mul=function(a,b)
    if getmetatable(b)==vectorMeta then return a:PointToWorldSpace(b) end
    return CFrame.fromMatrix(a*b.p,a:VectorToWorldSpace(b.r),a:VectorToWorldSpace(b.u),a:VectorToWorldSpace(b.b))
end
cfMeta.__add=function(a,b) return CFrame.fromMatrix(a.p+b,a.r,a.u,a.b) end
cfMeta.__sub=function(a,b) return CFrame.fromMatrix(a.p-b,a.r,a.u,a.b) end
cfMeta.__eq=function(a,b) return a.p==b.p and a.r==b.r and a.u==b.u and a.b==b.b end
CFrame.identity=CFrame.new()
local colorMeta={__type="Color3"}
function Color3.new(r,g,b) return setmetatable({R=r or 0,G=g or 0,B=b or 0},colorMeta) end
function Color3.fromRGB(r,g,b) return Color3.new(r/255,g/255,b/255) end
colorMeta.__index={Lerp=function(a,b,t) return Color3.new(a.R+(b.R-a.R)*t,a.G+(b.G-a.G)*t,a.B+(b.B-a.B)*t) end}
colorMeta.__eq=function(a,b) return a.R==b.R and a.G==b.G and a.B==b.B end
local nativeType=type
local function type(v)
    local m=nativeType(v)=="table" and getmetatable(v)
    return m and m.__type and "userdata" or nativeType(v)
end
local function typeof(v)
    local m=nativeType(v)=="table" and getmetatable(v)
    return m and m.__type or nativeType(v)
end
local Enum=setmetatable({},{__index=function(t,k)
    local e=setmetatable({},{__index=function(q,n) local v=k.."."..n rawset(q,n,v) return v end})
    rawset(t,k,e) return e
end})
local UDim2={new=function(...) return {...} end,fromScale=function(x,y) return {x,0,y,0} end,fromOffset=function(x,y) return {0,x,0,y} end}
local UDim={new=function(...) return {...} end}
local Vector2={new=function(x,y) return {X=x,Y=y} end}
local PhysicalProperties={new=function(d,f,e,fw,ew) return {Density=d,Friction=f,Elasticity=e,FrictionWeight=fw,ElasticityWeight=ew} end}
local BrickColor={new=function(name) return {Name=name,Color=Color3.new(1,1,1)} end}
local DateTime={now=function() return {UnixTimestampMillis=1728000000000} end}
local Random={}
function Random.new(seed)
    local state=math.floor(seed or 123456789)%2147483647
    if state==0 then state=1 end
    local function draw() state=(state*16807)%2147483647 return (state-1)/2147483646 end
    return {NextNumber=function(_,lo,hi) local n=draw() return lo and lo+(hi-lo)*n or n end,
        NextInteger=function(_,lo,hi) return lo+math.floor(draw()*(hi-lo+1)) end}
end
local yields=0
local task={wait=function() yields+=1 return 0 end,spawn=function(f,...) return f(...) end,defer=function(f,...) return f(...) end}
local warn=function(...) print("WARN",...) end
local Instance={}
local ALL,serial={},0
local objectMeta={__type="Instance"}
local instanceMethods={}
local function basepart(o) return o.ClassName=="Part" or o.ClassName=="MeshPart" or o.ClassName=="WedgePart" or o.ClassName=="SpawnLocation" end
function Instance.new(class,parent)
    serial+=1
    local o=setmetatable({_id=serial,_data={Name=class,ClassName=class,Anchored=false,Transparency=0,
        CanCollide=true,CanQuery=true,CanTouch=true,CastShadow=true,CFrame=CFrame.new(),Size=Vector3.new(4,1,2),
        Color=Color3.new(1,1,1),Material=Enum.Material.Plastic,MaterialVariant="",CollisionGroup="Default",
        WorldPivot=CFrame.new(),Enabled=true,Value=class=="NumberValue" and 0 or ""},_children={},_attrs={}},objectMeta)
    table.insert(ALL,o)
    if parent then o.Parent=parent end
    return o
end
objectMeta.__index=function(o,k)
    if instanceMethods[k] then return instanceMethods[k] end
    if k=="Position" and basepart(o) then return o._data.CFrame.Position end
    if o._data[k]~=nil then return o._data[k] end
    for _,c in ipairs(o._children) do if c.Name==k then return c end end
    return nil
end
objectMeta.__newindex=function(o,k,v)
    if k=="Parent" then
        local p=o._data.Parent
        if p then for i,c in ipairs(p._children) do if c==o then table.remove(p._children,i) break end end end
        o._data.Parent=v
        if v then table.insert(v._children,o) end
    elseif k=="Position" and basepart(o) then o._data.CFrame=o._data.CFrame-o._data.CFrame.Position+v
    else o._data[k]=v end
end
function instanceMethods:IsA(c)
    return self.ClassName==c or (c=="BasePart" and basepart(self)) or
        (c=="Light" and (self.ClassName=="PointLight" or self.ClassName=="SurfaceLight" or self.ClassName=="SpotLight")) or c=="Instance"
end
function instanceMethods:GetChildren() return table.clone(self._children) end
function instanceMethods:GetDescendants()
    local out={}
    local function visit(p) for _,c in ipairs(p._children) do table.insert(out,c) visit(c) end end
    visit(self) return out
end
function instanceMethods:FindFirstChild(n,recursive)
    for _,c in ipairs(self._children) do if c.Name==n then return c end end
    if recursive then for _,c in ipairs(self._children) do local found=c:FindFirstChild(n,true) if found then return found end end end
    return nil
end
function instanceMethods:WaitForChild(n) return assert(self:FindFirstChild(n),"fake WaitForChild missing "..n) end
function instanceMethods:FindFirstChildOfClass(c) for _,o in ipairs(self._children) do if o.ClassName==c then return o end end return nil end
function instanceMethods:FindFirstChildWhichIsA(c,recursive)
    for _,o in ipairs(recursive and self:GetDescendants() or self:GetChildren()) do if o:IsA(c) then return o end end return nil
end
function instanceMethods:FindFirstAncestorOfClass(c) local p=self.Parent while p do if p.ClassName==c then return p end p=p.Parent end return nil end
function instanceMethods:IsDescendantOf(p) local o=self.Parent while o do if o==p then return true end o=o.Parent end return false end
function instanceMethods:GetFullName() local p=self.Parent return p and p:GetFullName().."."..self.Name or self.Name end
function instanceMethods:GetAttributes() return table.clone(self._attrs) end
function instanceMethods:GetAttribute(n) return self._attrs[n] end
function instanceMethods:SetAttribute(n,v)
    assert(v==nil or type(v)=="string" or type(v)=="number" or type(v)=="boolean" or
        typeof(v)=="Vector3" or typeof(v)=="CFrame" or typeof(v)=="Color3","unsupported Roblox attribute "..n)
    self._attrs[n]=v
end
function instanceMethods:Destroy()
    for _,c in ipairs(self:GetChildren()) do c:Destroy() end
    self.Parent=nil self._data.Destroyed=true
end
function instanceMethods:Clone()
    local o=Instance.new(self.ClassName)
    for k,v in pairs(self._data) do if k~="Parent" and k~="Destroyed" then o._data[k]=v end end
    o._attrs=table.clone(self._attrs)
    for _,c in ipairs(self._children) do c:Clone().Parent=o end
    return o
end
function instanceMethods:GetPivot() return self:IsA("BasePart") and self.CFrame or self.WorldPivot end
function instanceMethods:GetBoundingBox()
    local low=Vector3.new(math.huge,math.huge,math.huge)
    local high=Vector3.new(-math.huge,-math.huge,-math.huge)
    local found=false
    for _,o in ipairs(self:GetDescendants()) do
        if o:IsA("BasePart") then
            found=true
            for _,x in ipairs({-1,1}) do for _,y in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
                local p=o.CFrame:PointToWorldSpace(Vector3.new(x*o.Size.X/2,y*o.Size.Y/2,z*o.Size.Z/2))
                low=Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
                high=Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
            end end end
        end
    end
    assert(found,"GetBoundingBox needs a BasePart")
    return CFrame.new((low+high)/2),high-low
end
function instanceMethods:PivotTo(cf)
    if self:IsA("BasePart") then self.CFrame=cf return end
    local delta=cf*self.WorldPivot:Inverse()
    for _,o in ipairs(self:GetDescendants()) do
        if o:IsA("BasePart") then o.CFrame=delta*o.CFrame
        elseif o:IsA("Model") then o.WorldPivot=delta*o.WorldPivot end
    end
    self.WorldPivot=cf
end
function instanceMethods:ScaleTo(scale)
    local pivot=self:GetPivot()
    local factor=scale/(self._data._scale or 1)
    for _,o in ipairs(self:GetDescendants()) do if o:IsA("BasePart") then
        local cf=pivot:ToObjectSpace(o.CFrame)
        o.Size=o.Size*factor o.CFrame=pivot*CFrame.fromMatrix(cf.Position*factor,cf.r,cf.u,cf.b)
    end end
    self._data._scale=scale
end
local game=Instance.new("DataModel") game.Name="game"
local workspace=Instance.new("Workspace",game) workspace.Name="Workspace" workspace.FallenPartsDestroyHeight=-500
local storage=Instance.new("ServerStorage",game) storage.Name="ServerStorage"
local materialService=Instance.new("MaterialService",game) materialService.Name="MaterialService"
for _,name in ipairs({"PR Tile","PR Tile Aqua","PR Iron"}) do
    local variant=Instance.new("MaterialVariant",materialService) variant.Name=name
end
local terrain=Instance.new("Terrain",workspace) terrain.Name="Terrain"
terrain.WaterColor=Color3.fromRGB(9,18,27) terrain.WaterTransparency=.31 terrain.WaterReflectance=.17
terrain.WaterWaveSize=.42 terrain.WaterWaveSpeed=7
local fills={}
function instanceMethods:FillBlock(cf,size,material) table.insert(fills,{CFrame=cf,Size=size,Material=material}) end
local tags={}
local collection={AddTag=function(_,o,n) tags[n]=tags[n] or {} tags[n][o]=true end,
    HasTag=function(_,o,n) return tags[n] and tags[n][o] or false end,
    GetTagged=function(_,n) local out={} for o in pairs(tags[n] or {}) do table.insert(out,o) end return out end}
local HttpService={}
function instanceMethods:GetService(name)
    if name=="Workspace" then return workspace end
    if name=="ServerStorage" then return storage end
    if name=="MaterialService" then return materialService end
    if name=="CollectionService" then return collection end
    if name=="HttpService" then return HttpService end
    return self:FindFirstChild(name) or Instance.new(name,self)
end
local function vec(v) return Vector3.new(v[1],v[2],v[3]) end
local function recordCF(rec)
    local f=rec.cframe
    if f then return CFrame.fromMatrix(vec(f.position),vec(f.right),vec(f.up),vec(f.back)) end
    local a=rec.cf
    if #a==12 then return CFrame.new(table.unpack(a)) end -- as import_kit.py's cf()
    return CFrame.new(a[1],a[2],a[3])*CFrame.Angles(0,math.rad(a[4] or 0),0)
end
'''


def lua(value):
    """Literal serialization, not shell interpolation or executable JSON."""
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        assert math.isfinite(value)
        return repr(value)
    if isinstance(value, str):
        # Luau accepts UTF-8 source, but not JSON's ``\uXXXX`` escapes.
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{" + ",".join(map(lua, value)) + "}"
    assert isinstance(value, dict), type(value)
    return "{" + ",".join(f"[{lua(k)}]={lua(v)}" for k, v in value.items()) + "}"


def consumer_code():
    objective = OBJECTIVES.read_text(encoding="utf-8")
    start = objective.index("local function validateManifest(manifest)")
    end = objective.index("local function drain(record)", start)
    manifest = objective[start:end]
    tests = EXIT_TESTS.read_text(encoding="utf-8")
    start = tests.index("local function orderedExitFloors")
    end = tests.index("function TestSuite.ValidateLevelThreeResume", start)
    return ("local MINIMUM_TRANSITION_LENGTH=2000\n" + manifest +
            "\nlocal TestSuite={}\nlocal RELEASE_SLOPE=.12\nlocal EXIT_SOFT_SPEED_CAP=105\n"
            "local POST_WIN_SECONDS=15\n" + tests[start:end])


def read_exports():
    # A arch, B tunnel, C objectives; D swerve (modules_swerve.py) is optional until that job has exported.
    jobs = "ABC" + ("D" if (JOBS / "D/export/manifest.json").is_file() else "")
    manifests = [json.loads((JOBS / j / "export/manifest.json").read_text(encoding="utf-8"))
                 for j in jobs]
    slides = json.loads(SLIDES.read_text(encoding="utf-8"))
    components = {}
    for manifest in manifests:
        assert manifest["scaleMetresPerStud"] == .28
        for name, component in manifest["components"].items():
            assert name not in components, f"duplicate exported component {name}"
            component = dict(component)
            component["meshRecords"] = [manifest["chunks"][i] for i in component["chunks"]]
            component["materials"] = manifest["materials"]
            components[name] = component
    return components, slides


INSTALL = r'''
local function installKit(components,slideData,slidesJSON)
    local kit=Instance.new("Folder",storage) kit.Name="Level2BlenderKit"
    kit:SetAttribute("KitBuild","offline-exported-poolrooms") kit:SetAttribute("ManifestSha256","offline-fixture")
    local folder=Instance.new("Folder",kit) folder.Name="Components"
    local poolTemplates={}
    for name,rec in pairs(components) do
        -- As import_kit.py --profile poolrooms: a Template component is a SlideTemplates MeshPart, not a Component.
        if rec.attrs and rec.attrs.Template==true then poolTemplates[name]=rec continue end
        local model=Instance.new("Model",folder) model.Name=name model.WorldPivot=CFrame.new()
        model._data.FixtureComponent=name
        for key,val in pairs(rec.attrs or {}) do
            if type(val)~="table" then model:SetAttribute(key,val) end
        end
        local function finishPart(o,record,kind)
            o.Name=record.name o.CFrame=recordCF(record) o.Size=vec(record.size)
            o.Anchored=true o.CanTouch=false o.CastShadow=kind=="part"
            o.CanCollide=kind=="collider" or record.collide==true o.CanQuery=o.CanCollide
            o.Material=Enum.Material.SmoothPlastic o.Shape=Enum.PartType[record.shape or "Block"]
            o._data.FixtureComponent=name o._data.FixtureKind=kind
            o._data.FixtureGround=record.ground==true
            if kind=="collider" then o.Transparency=1 end
            local mat=rec.materials[record.material or "Tile"] or {}
            o.MaterialVariant=mat.variant or "" o.Color=Color3.fromRGB(unpack(mat.color or {255,255,255}))
            for key,val in pairs(record.attrs or {}) do
                if key=="Level2_SlideDirection" and type(val)=="table" then val=vec(val) end
                if type(val)~="table" or typeof(val)~="table" then o:SetAttribute(key,val) end
            end
            if record.ground then o:SetAttribute("Level2_EntityGround",true) end
            for key,val in pairs(record.properties or {}) do
                if key=="Shape" then -- import_kit.py skips Shape here; nativeCylinder below owns it
                elseif key=="Material" then o[key]=Enum.Material[val]
                elseif key=="CollisionFidelity" then o[key]=Enum.CollisionFidelity[val]
                elseif key=="Color" then o[key]=Color3.fromRGB(unpack(val))
                elseif key=="CustomPhysicalProperties" then o[key]=PhysicalProperties.new(val.density,val.friction,val.elasticity,val.frictionWeight,val.elasticityWeight)
                else o[key]=val end
            end
            -- import_kit.py nativeCylinder: a vertical cylinder record installs with Size X = height
            -- (NativeSizeX/Y/Z) and the record CFrame rotated 90 degrees about Z, so its local X is world Y.
            if record.shape=="Cylinder" or (record.properties and record.properties.Shape=="Cylinder") then
                local a=record.attrs or {}
                assert(a.CylinderAxis=="Y" and a.NativeRotationZ==90,"Cylinder missing vertical native frame: "..record.name)
                o.Shape=Enum.PartType.Cylinder
                o.Size=Vector3.new(a.NativeSizeX,a.NativeSizeY,a.NativeSizeZ)
                o.CFrame=o.CFrame*CFrame.Angles(0,0,math.rad(a.NativeRotationZ))
            end
        end
        for _,record in ipairs(rec.parts) do finishPart(Instance.new("Part",model),record,"part") end
        for _,record in ipairs(rec.colliders) do finishPart(Instance.new("Part",model),record,"collider") end
        for _,chunk in ipairs(rec.meshRecords) do
            local o=Instance.new("MeshPart",model) o.Name=name.."_"..chunk.material
            o.CFrame=CFrame.new(vec(chunk.center)) o.Size=vec(chunk.size) o.Anchored=true
            o.CanCollide=false o.CanQuery=false o.CanTouch=false
            o.CastShadow=math.max(unpack(chunk.size))>8 o.CollisionFidelity=Enum.CollisionFidelity.Box
            o._data.FixtureComponent=name o._data.FixtureKind="mesh"
            local mat=rec.materials[chunk.material]
            -- As import_kit.py --profile poolrooms: a tile mesh wears its variant's maps as ONE SurfaceAppearance
            -- "Tile" (it follows the UVs; a MaterialVariant on a MeshPart ignores them) and MaterialVariant "".
            local tile=mat.variant=="PR Tile" or mat.variant=="PR Tile Aqua"
            o.Material=Enum.Material[mat.robloxMaterial] o.MaterialVariant=(not tile and mat.variant) or ""
            o.Color=Color3.fromRGB(unpack(mat.color))
            if mat.atlas then local atlas=Instance.new("SurfaceAppearance",o) atlas.Name="Atlas" end
            if tile then
                local sa=Instance.new("SurfaceAppearance",o) sa.Name="Tile" sa.Color=o.Color
                sa.ColorMap="rbxassetid://fixture-"..mat.pbr.."-albedo" sa.NormalMap="rbxassetid://fixture-"..mat.pbr.."-normal"
                sa.RoughnessMap="rbxassetid://fixture-"..mat.pbr.."-rough"
                o._data.FixtureTile=true
            end
        end
        local markers=Instance.new("Folder",model) markers.Name="Markers"
        for _,record in ipairs(rec.markers) do
            local o=Instance.new("CFrameValue",markers) o.Name=record.name o.Value=recordCF(record)
            for key,val in pairs(record.attrs or {}) do
                -- import_kit.encode_attrs serializes non-vector array attributes.
                if key=="Size" and type(val)=="table" then
                    val=string.format("[%.17g,%.17g,%.17g]",val[1],val[2],val[3])
                end
                if type(val)~="table" then o:SetAttribute(key,val) end
            end
        end
    end
    local templates=Instance.new("Folder",kit) templates.Name="SlideTemplates"
    for key,profile in pairs(slideData.slideProfiles) do
        if profile.size then
            local o=Instance.new("MeshPart",templates) o.Name=key o.Size=vec(profile.size) o.CFrame=CFrame.new()
            o.Anchored=true o.Transparency=1 o.CanCollide=true o.CanQuery=true o.CanTouch=false o.CastShadow=false
            o.Material=Enum.Material.SmoothPlastic o.CollisionFidelity=Enum.CollisionFidelity.PreciseConvexDecomposition
            o.CustomPhysicalProperties=PhysicalProperties.new(.7,.05,.05,1,1)
            o._data.FixtureComponent=key o._data.FixtureKind="slide-template"
        end
    end
    for name,rec in pairs(poolTemplates) do
        assert(#rec.meshRecords==1 and #rec.parts==0 and #rec.colliders==0 and #rec.markers==0,
            "Poolrooms template must be one mesh chunk: "..name)
        local chunk=rec.meshRecords[1]
        local o=Instance.new("MeshPart",templates) o.Name=name o.Size=vec(chunk.size) o.CFrame=CFrame.new(vec(chunk.center))
        o.Anchored=true o.Transparency=1 o.CanCollide=true o.CanQuery=true o.CanTouch=false o.CastShadow=false
        o.Material=Enum.Material.SmoothPlastic o.MaterialVariant="" o.CollisionFidelity=Enum.CollisionFidelity.PreciseConvexDecomposition
        o.CustomPhysicalProperties=PhysicalProperties.new(.7,.05,.05,1,1)
        o._data.FixtureComponent=name o._data.FixtureKind="slide-template"
    end
    local data=Instance.new("Folder",kit) data.Name="Data"
    local offset=1 local index=1
    while offset<=#slidesJSON do
        local o=Instance.new("StringValue",data) o.Name=string.format("SlidesJSON-%03d",index)
        o.Value=string.sub(slidesJSON,offset,offset+189999) offset+=190000 index+=1
    end
    HttpService.JSONDecode=function(_,json)
        if json==slidesJSON then return slideData end
        local x,y,z=json:match("^%[([^,]+),([^,]+),([^%]]+)%]$")
        assert(x and tonumber(x) and tonumber(y) and tonumber(z),
            "fake JSONDecode expected installed slides.json or a BoreSegment Size")
        return {tonumber(x),tonumber(y),tonumber(z)}
    end
    kit:SetAttribute("Ready",true)
    return kit
end
'''


SNAPSHOT = r'''
local function encode(value,refs)
    local kind=typeof(value)
    if kind=="Instance" then return '{"$instance":'..value._id..'}' end
    if kind=="Vector3" then return string.format('{"X":%.17g,"Y":%.17g,"Z":%.17g,"$type":"Vector3"}',value.X,value.Y,value.Z) end
    if kind=="Color3" then return string.format('{"R":%.17g,"G":%.17g,"B":%.17g,"$type":"Color3"}',value.R,value.G,value.B) end
    if kind=="CFrame" then return '{"$cframe":['..table.concat({value:GetComponents()},",")..']}' end
    if kind=="nil" then return "null" end
    if kind=="boolean" or kind=="number" then return tostring(value) end
    if kind=="string" then
        return '"'..value:gsub('[%z\1-\31\\"]',function(c)
            if c=='"' then return '\\"' end
            if c=='\\' then return '\\\\' end
            return string.format('\\u%04x',string.byte(c))
        end)..'"'
    end
    assert(kind=="table",kind)
    local result={}
    if #value>0 then for _,v in ipairs(value) do table.insert(result,encode(v,refs)) end return '['..table.concat(result,",")..']' end
    local keys={} for k in pairs(value) do table.insert(keys,k) end table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do table.insert(result,encode(tostring(k),refs)..":"..encode(value[k],refs)) end
    return '{'..table.concat(result,",")..'}'
end
local function snapshot(manifest,layout,seed,baseline,yieldStart,checks)
    local objects={}
    for _,o in ipairs(workspace:GetDescendants()) do
        local data={Id=o._id,Parent=o.Parent and o.Parent._id,Name=o.Name,ClassName=o.ClassName,Attrs=o:GetAttributes()}
        for _,key in ipairs({"CFrame","Size","Anchored","Transparency","CanCollide","CanQuery","CanTouch","CastShadow",
            "Material","MaterialVariant","Color","Reflectance","Shape","CollisionGroup","CollisionFidelity","CustomPhysicalProperties",
            "HoldDuration","ActionText","ObjectText","RequiresLineOfSight","MaxActivationDistance","Enabled",
            "Brightness","Range","Shadows","Face","Angle","Label","PassThrough","Value","Text","FixtureComponent","FixtureKind","FixtureGround","FixtureTile","ColorMap","WorldPivot","ModelStreamingMode"}) do
            if o._data[key]~=nil then data[key]=o._data[key] end
        end
        table.insert(objects,data)
    end
    local after={WaterColor=terrain.WaterColor,WaterTransparency=terrain.WaterTransparency,
        WaterReflectance=terrain.WaterReflectance,WaterWaveSize=terrain.WaterWaveSize,WaterWaveSpeed=terrain.WaterWaveSpeed}
    print("BUILD "..encode({RequestedSeed=seed,Generation=seed+100,Layout=layout,Manifest=manifest,
        Objects=objects,Fills=fills,BeforeWater=baseline,AfterWater=after,Yields=yields-yieldStart,ConsumerChecks=checks}))
end
'''


def build_program(seeds, components, slides, builder=None, generator=None):
    slides_json = json.dumps(slides, separators=(",", ":"))
    config = CONFIG.read_text(encoding="utf-8")
    generator = generator or LAYOUT.read_text(encoding="utf-8")
    builder = builder or BUILDER.read_text(encoding="utf-8")
    calls = "\n".join(f"runSeed({seed})" for seed in seeds)
    return "\n".join([
        ENGINE,
        "local Configuration=(function()\n" + config + "\nend)()",
        'local script={Parent={WaitForChild=function(_,name) assert(name=="Level 2 Configuration",name) return Configuration end}}',
        "local require=function(value) return value end",
        "local Generator=(function()\n" + generator + "\nend)()",
        "local Builder=(function()\n" + builder + "\nend)()",
        INSTALL,
        "local slideData=" + lua(slides),
        "local kit=installKit(" + lua(components) + ",slideData," + lua(slides_json) + ")",
        consumer_code(), SNAPSHOT,
        r'''
local function runSeed(seed)
    for _,o in ipairs(workspace:GetChildren()) do if o~=terrain then o:Destroy() end end
    workspace:SetAttribute("Level2BlenderPreviewActive",true)
    fills={}
    local baseline={WaterColor=terrain.WaterColor,WaterTransparency=terrain.WaterTransparency,
        WaterReflectance=terrain.WaterReflectance,WaterWaveSize=terrain.WaterWaveSize,WaterWaveSpeed=terrain.WaterWaveSpeed}
    local layout=Generator.Generate(seed)
    local valid,reason=Generator.Validate(layout) assert(valid,reason)
    local yieldStart=yields
    local manifest=Builder.Build(layout,seed+100)
    assert(manifest.Layout==layout,"layout must pass through by identity")
    validateManifest(manifest)
    local checks=TestSuite.ValidateExitGeometry(manifest)
    -- Mutation is entirely in memory: no file or builder source is changed.
    local sensor=manifest.Exit.Trigger
    local original=sensor:GetAttribute("Level2_ExitCompletionSensorThickness")
    sensor:SetAttribute("Level2_ExitCompletionSensorThickness",1)
    local mutationPassed,mutationError=pcall(TestSuite.ValidateCompletionSensors,manifest)
    sensor:SetAttribute("Level2_ExitCompletionSensorThickness",original)
    assert(not mutationPassed and tostring(mutationError):find("8 is the floor"),"thickness mutation survived or failed for the wrong reason")
    checks.Mutation="sensor thickness 9 -> 1 rejected and restored in memory"
    snapshot(manifest,layout,seed,baseline,yieldStart,checks)
    for key,value in pairs(baseline) do terrain[key]=value end
end
''', calls,
        r'''
do
    for _,o in ipairs(workspace:GetChildren()) do if o~=terrain then o:Destroy() end end
    kit:SetAttribute("Ready",false)
    local ok,reason=pcall(Builder.Build,Generator.Generate(1),999)
    assert(not ok and tostring(reason):find("Ready"),"not-ready kit must fail clearly")
    kit:SetAttribute("Ready",true) kit.Parent=nil
    ok,reason=pcall(Builder.Build,Generator.Generate(1),999)
    assert(not ok and tostring(reason):find("Level2BlenderKit"),"missing installed kit must fail clearly")
    print("NEGATIVE ready and missing installed kit rejected")
end
''',
    ])


def run_luau(binary, program, timeout=None):
    # LATTICE_SPEC 5: the 50-seed build needs > 180 s under load; default 900 s, LEVEL2_LUAU_TIMEOUT overrides.
    timeout = timeout or float(os.environ.get("LEVEL2_LUAU_TIMEOUT") or 900)
    # One REPL statement prevents prompts/continuations and avoids disk fixtures.
    command = "local f,e=loadstring(" + lua(program) + ",\"kit-world-offline\") if not f then error(e) end f()\n"
    result = subprocess.run([binary], input=command, capture_output=True, text=True,
                            encoding="utf-8", timeout=timeout)
    # The standalone REPL may return 0 after a runtime error; require sentinels.
    failures = result.stderr.strip()
    diagnostic = "\n".join(line for line in result.stdout.splitlines() if not line.startswith("BUILD "))[-4000:]
    if result.returncode or failures:
        raise AssertionError(f"offline Luau failed:\n{failures}\n{diagnostic}")
    builds = [json.loads(line[len("BUILD "):]) for line in result.stdout.splitlines()
              if line.startswith("BUILD ")]
    assert "NEGATIVE ready and missing installed kit rejected" in result.stdout, diagnostic
    return builds


def check_budget_constant():
    """The builder's runtime G8 assert and this suite's assert must name the same cap."""
    found = re.findall(r"^local WORLD_BUDGET = (\d+)", BUILDER.read_text(encoding="utf-8"), re.M)
    assert found == [str(WORLD_BUDGET)], f"builder WORLD_BUDGET {found} != test WORLD_BUDGET {WORLD_BUDGET}"


def compile_builder(binary):
    compiler = os.environ.get("LUAU_COMPILE_BIN") or str(Path(binary).with_name("luau-compile.exe"))
    if not Path(compiler).exists():
        compiler = shutil.which("luau-compile")
    assert compiler, "luau-compile is required"
    result = subprocess.run([compiler, "-O0", str(BUILDER)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    print("PASS luau-compile -O0: builder fits the 200-register limit")


def point(v):
    assert isinstance(v, dict) and v.get("$type") == "Vector3", f"expected Vector3, got {v}"
    return tuple(v[k] for k in "XYZ")


def distance(a, b):
    return math.dist(point(a), point(b))


def frame(v):
    assert isinstance(v, dict) and "$cframe" in v, f"expected CFrame, got {v}"
    a = v["$cframe"]
    assert len(a) == 12 and all(math.isfinite(x) for x in a)
    return a


def position(o):
    return frame(o["CFrame"])[:3]


def near(a, b, tolerance=1e-4):
    assert len(a) == len(b) and math.dist(a, b) <= tolerance, f"{a} != {b}"


def cf_vector(cf, vector):
    x, y, z = vector
    return (cf[3]*x + cf[4]*y + cf[5]*z,
            cf[6]*x + cf[7]*y + cf[8]*z,
            cf[9]*x + cf[10]*y + cf[11]*z)


def cf_point(cf, local):
    transformed = cf_vector(cf, local)
    return tuple(cf[i] + transformed[i] for i in range(3))


def bounds(o):
    cf, size = frame(o["CFrame"]), point(o["Size"])
    corners = [cf_point(cf, (x*size[0]/2, y*size[1]/2, z*size[2]/2))
               for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    return tuple(min(c[i] for c in corners) for i in range(3)), tuple(max(c[i] for c in corners) for i in range(3))


def contains_part(o, p, tolerance=.05):
    cf, size = frame(o["CFrame"]), point(o["Size"])
    d = tuple(p[i] - cf[i] for i in range(3))
    local = (d[0]*cf[3] + d[1]*cf[6] + d[2]*cf[9],
             d[0]*cf[4] + d[1]*cf[7] + d[2]*cf[10],
             d[0]*cf[5] + d[1]*cf[8] + d[2]*cf[11])
    return all(abs(local[i]) <= size[i]/2 + tolerance for i in range(3))


BORE_RADIUS = 17       # modules_tunnel: the round tunnel bore
WALL_THICKNESS = 1.75  # hall wall, sill and lintel slabs (and the mouth collar depth)
# LATTICE_SPEC (0.5 tile lattice) interface numbers, one place for the whole suite:
TILE = .5              # tile pitch (prkit TILE_M 4.0 * .28 over 8 tiles; PR Tile StudsPerTile 4.0)
DECK_TOP = .5          # ring deck top above FloorY (builder DECK_TOP)
STEP_RISE = .65        # pool step rise (builder STEP_RISE)
TAIL = .25             # corner arc pieces' straight tails (runs start boundary + 2 + R)
SQUARE_DECK = 10.25    # Walkway_Corner_R0 legs (deck runs start boundary + 12 at R0/R8 corners)
TUNNEL_HOLE = 18       # a tunnel's wall hole / collar outline half-width (a pipe's is 6)
ARRIVAL_FRAME = 7.0    # ArrivalDoor frame half-width (the base cove's CoveOnly hole)
CORNER_SHORT = 6.25    # builder CORNER_SHORT: the 3.25 inner-corner leg + a 3-stud stop
INNER = 3.25           # builder INNER / modules_arch INNER_LEG: the legs of the mitred square-corner pieces
CORNER_KEYS = {1: (False, False), 2: (True, False), 3: (False, True), 4: (True, True)}   # builder CORNERS index


def hole_half(c):
    """Half-width of a corridor's wall hole (the builder's wallShell): tunnel 18, pipe 6."""
    return 6 if c["Kind"] == "Narrow" else TUNNEL_HOLE


def on_lattice(v, step=TILE):
    return abs(v / step - round(v / step)) * step <= 1e-6
CORNER_KEYS = {1: (False, False), 2: (True, False), 3: (False, True), 4: (True, True)}   # builder CORNERS index


def swerve_arcs(hall):
    """F9 (WP8): planned corner arcs, keyed like the corner dicts below: (MaxX side?, MaxZ side?) -> radius."""
    return {CORNER_KEYS[seg["Corner"]]: seg["R"] for seg in (hall.get("Swerve") or {}).get("Loop", [])
            if seg["Kind"] == "Corner" and seg["R"] > 0}


def swerve_spans(hall, side):
    """The d=0 straights of a wall as ascending (low, high) along its face line; a rectangle wall is one span."""
    along = "X" if side in {"North", "South"} else "Z"
    if not hall.get("Swerve"):
        return [(hall["Min" + along] + 1.75, hall["Max" + along] - 1.75)]
    return sorted(tuple(sorted((seg["From"], seg["To"]))) for seg in hall["Swerve"]["Loop"]
                  if seg["Kind"] == "Straight" and seg["Wall"] == side and seg["Offset"] == 0)


def check_hall_shell(hall, room_parts, openings, components):
    """Check the built collision/mesh edges, including the unseen wall feet."""
    index, floor_y = hall["Index"], hall["FloorY"]
    dry = hall["Type"] in {"Arrival", "PumpHall"} or (hall["PoolType"] == "Dry" and hall["Type"] != "PaddlingRoom")
    depth = 0 if dry else .8 if hall["Type"] == "PaddlingRoom" else max(1.6, min(3.5, hall.get("DeepEnd") or 1.6))
    required_bottom = floor_y - depth - 4
    required_top = floor_y + hall["CeilingClass"] + 2
    floor = next(o for o in room_parts if o["Name"] in {
        f"Level 2 Hall Floor {index}", f"Level 2 Hall Water Floor {index}"})
    floor_low, floor_high = bounds(floor)
    overhead = [bounds(o) for o in room_parts if o["Name"].startswith(f"Level 2 Overhead Tile {index}")]
    assert overhead, f"hall {index} has no ceiling slabs"
    radii, arcs = {}, swerve_arcs(hall)
    for cove in room_parts:
        if cove["ClassName"] == "MeshPart" and cove["Attrs"].get("Level2_KitComponent", "").startswith("CornerCove_R"):
            x, _, z = position(cove)
            radii[(x > hall["Center"]["X"], z > hall["Center"]["Z"])] = cove["Attrs"]["Level2_CornerRadius"]

    # F2 (doors at corners): each corner takes the LARGEST radius in {24,16,8} up to the hall rule whose
    # tangent keeps 3 (stop) + .5 clear of every door edge on its two walls, else a square corner (R1
    # review: a multi-value return once turned the ExitHall's corners square without failing anything).
    rule = 24 if hall["Type"] == "PaddlingRoom" else 8 if min(hall["Width"], hall["Depth"]) < 112 \
        else 24 if max(hall["Width"], hall["Depth"]) > 200 else 16
    for hi_x in (False, True):
        for hi_z in (False, True):
            clear = math.inf
            for door_side, cross, _, c in openings:
                half = 6 if c["Kind"] == "Narrow" else 17
                if door_side == ("South" if hi_z else "North"):
                    clear = min(clear, hall["MaxX"] - cross - half if hi_x else cross - half - hall["MinX"])
                elif door_side == ("East" if hi_x else "West"):
                    clear = min(clear, hall["MaxZ"] - cross - half if hi_z else cross - half - hall["MinZ"])
            expected = next((r for r in (24, 16, 8) if r <= rule and clear >= r + 5.25), 0)
            if (hi_x, hi_z) in arcs:
                # F9 (WP8): an arced corner is the SwerveCorner piece alone (check_swerve_world).
                assert (hi_x, hi_z) not in radii, f"hall {index} arced corner {(hi_x, hi_z)} keeps a CornerCove"
                continue
            assert radii.get((hi_x, hi_z), 0) == expected, \
                f"hall {index} corner {(hi_x, hi_z)} radius {radii.get((hi_x, hi_z), 0)}, door-safe maximum {expected}"

    def corner_radius(side, high_end):
        """Per-corner fillet radius (0 = square corner) at the low/high end of a wall's along axis."""
        if side in {"North", "South"}:
            return radii.get((high_end, side == "South"), 0)
        return radii.get((side == "East", high_end), 0)

    def door_near(side, high_end):
        """A door on 'side' whose edge is within 4.8 of the boundary at that end (its hardware owns the corner)."""
        lo, hi = (hall["MinX"], hall["MaxX"]) if side in {"North", "South"} else (hall["MinZ"], hall["MaxZ"])
        return any((hi - cross if high_end else cross - lo) - (6 if c["Kind"] == "Narrow" else 17) < 4.8
                   for door_side, cross, _, c in openings if door_side == side)

    def doorless_square(side, high_end):
        """A square corner at that end of 'side' with no door within 4.8 of it on either wall."""
        perp = ("East" if high_end else "West") if side in {"North", "South"} else ("South" if high_end else "North")
        return not corner_radius(side, high_end) and not door_near(side, high_end) \
            and not door_near(perp, side in {"South", "East"})
    def corner_gap(side, high_end):
        """Base-cove segment from the face corner at that end of 'side' to its first door (or story-door frame)."""
        along = "X" if side in {"North", "South"} else "Z"
        lo, hi = hall["Min" + along] + 1.75, hall["Max" + along] - 1.75
        edges = [(cross - hole_half(c), cross + hole_half(c)) for door_side, cross, _, c in openings if door_side == side]
        if hall["Type"] == "Arrival" and openings and side == {"North": "South", "South": "North", "West": "East",
                                                               "East": "West"}[openings[0][0]]:
            mid = hall["Center"][along]
            edges.append((mid - ARRIVAL_FRAME, mid + ARRIVAL_FRAME))
        gaps = [hi - b if high_end else a - lo for a, b in edges]
        return min([g for g in gaps if g > -1e-6], default=math.inf)

    def mitre(side, high_end):
        """FA: a doorless square corner whose two corner-to-hole base segments both hold the INNER mitre band plus
        a stop (CORNER_SHORT) carries CoveBaseInnerCorner; both base runs then start INNER from the face corner."""
        perp = ("East" if high_end else "West") if side in {"North", "South"} else ("South" if high_end else "North")
        return doorless_square(side, high_end) and corner_gap(side, high_end) >= CORNER_SHORT \
            and corner_gap(perp, side in {"South", "East"}) >= CORNER_SHORT
    # FA review: this inventory runs BEFORE the wall-foot coverage, so a corner mutation is caught by the corner
    # rule it targets, not first as the bare foot it leaves.
    # FA (world audit 06/07, VERIFY D4/D6/D8): every square corner (no torus, no swerve arc) carries the mitred
    # CoveTopInnerCorner, and CoveBaseInnerCorner exactly where the mitre rule holds (mitre(): a doorless corner whose
    # two corner-to-hole segments both reach CORNER_SHORT); each on the corner of the two wall faces, at its band's
    # height, its legs (+X/+Z) along the walls into the room. No straight run or stop of either wall may stand in a
    # base inner corner's INNER legs (two runs crossing there was the crease); where there is none, no straight base
    # run may reach the corner (a free profile against the other wall), so a stop or a bare foot ends it as before.
    inner_pieces = {}
    for o in room_parts:
        kind = o["Attrs"].get("Level2_KitComponent", "")
        if o["ClassName"] == "MeshPart" and kind in ("CoveTopInnerCorner", "CoveBaseInnerCorner"):
            x, y, z = position(o)
            inner_pieces.setdefault((x > hall["Center"]["X"], z > hall["Center"]["Z"]), []).append((kind, o))
    wanted = {}
    for hi_x in (False, True):
        for hi_z in (False, True):
            here = inner_pieces.get((hi_x, hi_z), [])
            if radii.get((hi_x, hi_z), 0) or (hi_x, hi_z) in arcs:
                assert not here, f"hall {index} corner {(hi_x, hi_z)} has an inner corner at a radius/arc"
                continue
            x_side, z_side = ("South" if hi_z else "North"), ("East" if hi_x else "West")
            want = {"CoveTopInnerCorner": floor_y + hall["CeilingClass"] - 3}
            wanted[(hi_x, hi_z)] = want
            if mitre(x_side, hi_x):
                want["CoveBaseInnerCorner"] = floor_y + (0 if dry else DECK_TOP)
            assert sorted(k for k, _ in here) == sorted(want), \
                f"hall {index} square corner {(hi_x, hi_z)} has {[k for k, _ in here]}, wants {sorted(want)}"
            # FA review: a doorless square corner (no door within 4.8 on either wall) always carries the base mitre;
            # the generator keeps door edges off 4.8..8.125 from a corner, so both feet hold its leg plus a stop.
            # (A door within 4.8 owns its corner with its threshold: the jamb rule above, no base inner corner.)
            assert mitre(x_side, hi_x) == doorless_square(x_side, hi_x), \
                f"hall {index} square corner {(hi_x, hi_z)} is doorless but its base foot is too short for the " \
                f"inner corner (gaps {corner_gap(x_side, hi_x):.2f}, {corner_gap(z_side, hi_z):.2f})"
    base_pieces, faces = {}, {}

    # LATTICE_SPEC I1 (stricter than G3's [.875, 1.125] band, which it replaces): every straight cove, cove stop and
    # deck mesh is laid at stretch 1 - its Size equals its kit export's on every axis - so its UV grid keeps the pitch.
    for o in room_parts:
        kit_name = o["Attrs"].get("Level2_KitComponent", "")
        if o["ClassName"] == "MeshPart" and re.fullmatch(
                r"(CoveBase|CoveTop|Walkway_Straight)\d+|CoveBaseStop_[PN]X|CoveBaseStopCorner_[PN]X", kit_name):
            record = next(r["size"] for r in components[kit_name]["meshRecords"]
                          if o["Name"] == f"{kit_name}_{r['material']}")
            assert all(abs(o["Size"][k] - record[i]) <= 1e-6 for i, k in enumerate("XYZ")), \
                f"hall {index} {kit_name} is stretched {[round(o['Size'][k] / record[i], 4) for i, k in enumerate('XYZ')]}"
    for side in ("North", "South", "West", "East"):
        along = 0 if side in {"North", "South"} else 2
        normal = 2 if along == 0 else 0
        edge = hall["MinZ" if along == 0 else "MinX"] if side in {"North", "West"} \
            else hall["MaxZ" if along == 0 else "MaxX"]
        start = hall["MinX" if along == 0 else "MinZ"]
        end = hall["MaxX" if along == 0 else "MaxZ"]
        shell = {kind: [o for o in room_parts if o["Name"] == f"Level 2 Hall {kind} {index} {side}"]
                 for kind in ("Wall", "Sill", "Lintel")}
        walls = shell["Wall"]
        assert walls, f"hall {index} {side} has no wall runs"
        # LATTICE_SPEC 2.3 (measured: a Part's tiles start at one corner of each face, TILE_PHASE.md): every wall,
        # sill and lintel edge along the wall and up it lies on the global 0.5 lattice, so the slabs continue each
        # other's grid whichever corner anchors it (check_lattice judges the seams themselves).
        for kind in ("Wall", "Sill", "Lintel"):
            for o in shell[kind]:
                low, high = bounds(o)
                for v in (low[along], high[along], low[1], high[1]):
                    assert on_lattice(v), f"hall {index} {o['Name']} edge {v:.4f} is off the {TILE} tile lattice"
        wall_ranges = [bounds(o) for o in walls]
        inner = (max(high[normal] for low, high in wall_ranges) if side in {"North", "West"}
                 else min(low[normal] for low, high in wall_ranges))
        outer = (min(low[normal] for low, high in wall_ranges) if side in {"North", "West"}
                 else max(high[normal] for low, high in wall_ranges))
        assert floor_low[normal] <= inner + .05 and floor_high[normal] >= inner - .05, \
            f"hall {index} {side} floor/wall seam exceeds 0.05"
        # LATTICE_SPEC I1.7: the floors stop .5 inside the boundary (hidden under the 1.75 wall).
        assert floor_low[along] <= start + .5 + .05 and floor_high[along] >= end - .5 - .05, \
            f"hall {index} {side} floor stops short of wall ends"
        for cove in room_parts:
            if cove["ClassName"] != "MeshPart" or not cove["Attrs"].get("Level2_KitComponent", "").startswith(("CoveTop", "CoveBase")):
                continue
            low, high = bounds(cove)
            if abs(cf_vector(frame(cove["CFrame"]), (1, 0, 0))[along]) < .9 \
                    or abs((low[normal] + high[normal]) / 2 - edge) > 4:
                continue
            assert (low[normal] >= outer - .05 if side in {"North", "West"} else high[normal] <= outer + .05), \
                f"hall {index} {side} {cove['Name']} projects outside the wall shell"
        r_low, r_high = corner_radius(side, False), corner_radius(side, True)
        spans = swerve_spans(hall, side)
        if not dry:
            # G8: one 'Level 2 Run Deck' Part per wall replaces the per-piece kit 'Walkway Deck' Parts. It is
            # the kit deck's cross-section (LATTICE_SPEC 6: wall face to 9.25 out, top +.5, bottom -4.5), spans tail
            # to tail, and its wall side sits ON the wall face: at a door hole it may not reach into the
            # collar (R2 work order 1), elsewhere the base cove covers the joint.
            # F9 (WP8): one run per d=0 straight of a swerve wall, from swerve piece to swerve piece (or to the
            # rectangle corner deck at a face corner); a rectangle wall is one span, corner to corner.
            expected = []
            for a, b in spans:
                lo = start + 1.75 + (r_low + TAIL if r_low >= 16 else SQUARE_DECK) if a <= start + 1.75 + 1e-6 else a
                hi = end - 1.75 - (r_high + TAIL if r_high >= 16 else SQUARE_DECK) if b >= end - 1.75 - 1e-6 else b
                if hi - lo > .05:
                    expected.append((lo, hi))
            decks = [o for o in room_parts if o["Name"] == f"Level 2 Run Deck {index} {side}"]
            assert decks and len(decks) == len(expected), f"hall {index} {side} lacks its ring deck run"
            for deck in decks:
                assert deck["CanCollide"] and deck["CanQuery"] and deck["Attrs"].get("Level2_EntityGround") \
                    and deck["Transparency"] == 0, f"hall {index} {side} ring deck is not visible walkable ground"
                low, high = bounds(deck)
                wall_side, pool_side = (low[normal], high[normal]) if side in {"North", "West"} else (high[normal], low[normal])
                assert abs(wall_side - inner) <= .05, f"hall {index} {side} walkway deck/wall seam exceeds 0.05"
                assert abs(abs(pool_side - edge) - 11) <= .05, f"hall {index} {side} deck pool edge moved"
                assert abs(high[1] - (floor_y + DECK_TOP)) < .01 and abs(low[1] - (floor_y - 4.5)) < .01, \
                    f"hall {index} {side} deck top/skirt"
                # LATTICE_SPEC 4.3 (all faces): object X up, Y into the room, so every face's anchored tile corner -
                # top, pool side, both run ends - is a lattice edge, never the wall-side edge on the face (x.75).
                cf = frame(deck["CFrame"])
                inward = {"North": (0, 0, 1), "South": (0, 0, -1), "West": (1, 0, 0), "East": (-1, 0, 0)}[side]
                assert math.dist(cf_vector(cf, (0, 1, 0)), inward) < 1e-6 \
                    and math.dist(cf_vector(cf, (1, 0, 0)), (0, 1, 0)) < 1e-6, \
                    f"hall {index} {side} deck is not object X up, Y into the room (an anchored edge is off the lattice)"
            # F9 review: a strict bijection, deck runs sorted along the wall against the expected spans, so two
            # decks on one span cannot hide a span with none.
            runs = sorted((bounds(deck)[0][along], bounds(deck)[1][along]) for deck in decks)
            for (low_along, high_along), (lo, hi) in zip(runs, expected):
                assert abs(low_along - lo) < .06 and abs(high_along - hi) < .06, \
                    f"hall {index} {side} deck run {low_along:.2f}..{high_along:.2f} does not meet its pieces at {lo:.2f}..{hi:.2f}"
            # FA (deck-nosing crease): a square or R8 corner's deck square is Walkway_Corner_R0, the decks' own
            # section mitred round the pool's corner, its legs [face, face + 10.25] on both axes (LATTICE_SPEC 6; the
            # pool edge stays face + 9.5) (no plain 'Corner Deck' box).
            for high_end in (False, True):
                key = (high_end, side == "South") if along == 0 else (side == "East", high_end)
                if side not in ("North", "South") or corner_radius(side, high_end) >= 16 or key in arcs:
                    continue
                fx = hall["MaxX"] - 1.75 if key[0] else hall["MinX"] + 1.75
                fz = hall["MaxZ"] - 1.75 if key[1] else hall["MinZ"] + 1.75
                squares = [o for o in room_parts if o["ClassName"] == "MeshPart"
                           and o["Attrs"].get("Level2_KitComponent") == "Walkway_Corner_R0"
                           and (position(o)[0] > hall["Center"]["X"], position(o)[2] > hall["Center"]["Z"]) == key]
                assert len(squares) == 1, f"hall {index} corner {key} has {len(squares)} Walkway_Corner_R0"
                low, high = bounds(squares[0])
                for k, f, hi_side in ((0, fx, key[0]), (2, fz, key[1])):
                    near, far = (high[k], low[k]) if hi_side else (low[k], high[k])
                    assert abs(near - f) < .02 and abs(abs(far - f) - SQUARE_DECK) < .02, \
                        f"hall {index} corner {key} deck square spans {low[k]:.2f}..{high[k]:.2f}, face {f:.2f}"
                assert abs(high[1] - (floor_y + DECK_TOP)) < .01 and abs(low[1] - (floor_y - 4.5)) < .01, \
                    f"hall {index} corner {key} deck square top/skirt"
            assert not any(o["Name"].startswith("Level 2 Corner Deck ") for o in room_parts), \
                f"hall {index} keeps a plain corner deck box"
        else:
            assert not any(o["Attrs"].get("Level2_KitComponent", "").startswith(("Walkway_", "PoolSteps_"))
                           for o in room_parts), f"dry hall {index} has pool decks or steps"
        top_coves = sorted((bounds(o)[0][along], bounds(o)[1][along]) for o in room_parts
                           if o["ClassName"] == "MeshPart"
                           and re.fullmatch(r"CoveTop\d+", o["Attrs"].get("Level2_KitComponent", ""))
                           and abs(position(o)[normal] - edge) < 4)
        assert top_coves, f"hall {index} {side} top cove is split or gapped"
        for a, b in spans:
            # F1/F2: one run tangent to tangent; F9 (WP8): on a swerve wall one per d=0 straight, butting onto
            # the swerve pieces' own coves at both ends. FA: at a square corner the run butts onto the mitred
            # CoveTopInnerCorner, INNER from the face corner (checked below), instead of crossing the other run.
            lo = start + 1.75 + (r_low + TAIL if r_low else INNER) if a <= start + 1.75 + 1e-6 else a
            hi = end - 1.75 - (r_high + TAIL if r_high else INNER) if b >= end - 1.75 - 1e-6 else b
            run = [c for c in top_coves if c[0] >= lo - .1 and c[1] <= hi + .1]
            assert run and abs(run[0][0] - lo) <= .06 and abs(run[-1][1] - hi) <= .06 \
                and all(run[i+1][0] - run[i][1] <= .06 for i in range(len(run)-1)), \
                f"hall {index} {side} top cove is split or gapped"
        assert sum(len([c for c in top_coves if c[0] >= a - .1 and c[1] <= b + .1]) for a, b in spans) \
            == len(top_coves), f"hall {index} {side} has a top cove off its straights"
        for wall, (low, high) in zip(walls, wall_ranges):
            assert wall["CanCollide"] and wall["CanQuery"], f"hall {index} {side} wall has no collision"
            assert low[1] <= required_bottom + .05 and high[1] >= required_top - .05, \
                f"hall {index} {side} wall does not reach basin depth/ceiling overlap"
            assert any(tile_low[normal] <= inner + .05 <= tile_high[normal]
                       and tile_low[along] <= (low[along] + high[along]) / 2 <= tile_high[along]
                       and tile_low[1] <= high[1] - 2 + .05 and tile_high[1] >= high[1] - .05
                       for tile_low, tile_high in overhead), \
                f"hall {index} {side} ceiling does not overlap wall by 2"
        for sill in shell["Sill"]:
            assert bounds(sill)[0][1] <= required_bottom + .05, f"hall {index} {side} sill foot is open"
        for lintel in shell["Lintel"]:
            assert bounds(lintel)[1][1] >= required_top - .05, f"hall {index} {side} lintel misses ceiling"
        side_openings = [(cross, corridor) for door_side, cross, _, corridor in openings if door_side == side]
        for cross, corridor in side_openings:
            component = ("Pipe_" if corridor["Kind"] == "Narrow" else "RoundTunnel_") + corridor["Variant"] + "_" + str(corridor["Length"])
            assert component in components, f"hall {index} corridor {corridor['Index']} lacks exact-length kit collar"
            collar_depth = components[component]["attrs"]["CollarDepth"]
            expected_inner = edge + (collar_depth if side in {"North", "West"} else -collar_depth)
            assert abs(inner - expected_inner) <= .05, \
                f"hall {index} {side} tunnel {corridor['Index']} collar far face is not flush with inner wall face"
            half, top = (6, 12) if corridor["Kind"] == "Narrow" else (TUNNEL_HOLE, 32)
            left, right = cross - half, cross + half
            bottom_y, top_y = floor_y - 2, floor_y + top
            bore_top = floor_y + (12 if corridor["Kind"] == "Narrow" else 30)    # top of the round bore
            assert any(abs(high[along] - left) <= .05 for low, high in wall_ranges), \
                f"hall {index} {side} tunnel {corridor['Index']} left wall edge differs from collar"
            assert any(abs(low[along] - right) <= .05 for low, high in wall_ranges), \
                f"hall {index} {side} tunnel {corridor['Index']} right wall edge differs from collar"
            assert any(abs(low[along] - left) <= .05 and abs(high[along] - right) <= .05
                       and abs(high[1] - bottom_y) <= .05 for o in shell["Sill"]
                       for low, high in [bounds(o)]), \
                f"hall {index} {side} tunnel {corridor['Index']} sill differs from collar rectangle"
            assert any(abs(low[along] - left) <= .05 and abs(high[along] - right) <= .05
                       and abs(low[1] - top_y) <= .05 for o in shell["Lintel"]
                       for low, high in [bounds(o)]), \
                f"hall {index} {side} tunnel {corridor['Index']} lintel differs from collar rectangle"
            for kind in shell.values():
                for slab in kind:
                    low, high = bounds(slab)
                    assert min(high[along], right) - max(low[along], left) <= .05 \
                        or min(high[1], top_y) - max(low[1], bottom_y) <= .05, \
                        f"hall {index} {side} tunnel {corridor['Index']} aperture blocked by {slab['Name']}"
            # F2 (R3, doors at corners): in front of an opening, from the boundary to 4 studs into the room
            # (6 at a pipe: its mouth step) and from floor-2 to the top of the round bore, only the collar,
            # threshold, mouth step, deck, steps and floor may stand (the top cove crosses the solid collar
            # panel above the bore, .17 off the wall). No exemption for cove stops (R1 review: a square
            # corner's stop stood in the perpendicular wall's pipe mouth); a stop at a hole edge of its own
            # wall ends on the opening's side plane and passes the along-axis test.
            depth = 6 if corridor["Kind"] == "Narrow" else 4
            inward = (edge, edge + depth) if side in {"North", "West"} else (edge - depth, edge)
            for o in room_parts:
                kit_name = o["Attrs"].get("Level2_KitComponent", "")
                if (o["Transparency"] >= .98 and not o["CanCollide"]) or kit_name.startswith(
                        ("Walkway_", "PoolSteps_")) or o["Name"].startswith(
                        ("Level 2 Hall ", "Level 2 Run Deck", "Level 2 Corner Deck", "Level 2 Passage Mouth Step")):
                    continue
                low, high = bounds(o)
                assert min(high[along], right) - max(low[along], left) <= .05 \
                    or min(high[normal], inward[1]) - max(low[normal], inward[0]) <= .05 \
                    or min(high[1], bore_top) - max(low[1], bottom_y) <= .05, \
                    f"hall {index} {side} opening {corridor['Index']} is intruded by {o['Name']}"
        # F1/F2 (R3): the base cove is continuous along the wall foot. Between the two corner tails (the
        # wall face of the other wall at a square corner) every stud is a straight run or a stop; only a
        # door hole may break it. LATTICE_SPEC I1.3: stops are exactly 3, so a segment between a hole and a
        # hole or corner door that is too short for its stops (under 6) may leave a bare foot under 3 beside
        # the hole; any longer segment is covered stud for stud.
        base_y = floor_y + (0 if dry else DECK_TOP)
        pieces = sorted((bounds(o)[0][along], bounds(o)[1][along]) for o in room_parts
                        if o["ClassName"] == "MeshPart"
                        and re.fullmatch(r"CoveBase(\d+|Stop_PX|Stop_NX|StopCorner_PX|StopCorner_NX)",
                                         o["Attrs"].get("Level2_KitComponent", ""))
                        and abs(cf_vector(frame(o["CFrame"]), (1, 0, 0))[along]) >= .9
                        and abs(cf_point(frame(o["CFrame"]), (0, 0, 0))[normal] - edge) < 4
                        and bounds(o)[0][1] < base_y + .1 < bounds(o)[1][1])
        holes = [(cross - hole_half(c), cross + hole_half(c)) for cross, c in side_openings]
        if hall["Type"] == "Arrival" and openings and side == {"North": "South", "South": "North", "West": "East",
                                                               "East": "West"}[openings[0][0]]:
            # F4-L: the story door's 14-wide frame stands .86 proud of the back wall; stops end at its sides.
            mid = hall["Center"]["X" if along == 0 else "Z"]
            holes.append((mid - ARRIVAL_FRAME, mid + ARRIVAL_FRAME))
        # R1 review: at a square corner whose other wall has a door within the cove's depth (edge under 4.8
        # from this wall's boundary), the foot starts past that door's threshold: 2.25 (tunnel) or 4.25 (pipe,
        # its mouth step) beyond the wall face. The foot inside the door's hardware is bare, like a jamb.
        def jamb(high_end):
            if r_high if high_end else r_low:
                return 0
            perp = ("East" if high_end else "West") if along == 0 else ("South" if high_end else "North")
            return max([4.25 if c["Kind"] == "Narrow" else 2.25 for door_side, cross, _, c in openings
                        if door_side == perp and abs(cross - edge) - (6 if c["Kind"] == "Narrow" else 17) < 4.8],
                       default=0)
        # F9 (WP8): per d=0 straight. An end at a face corner keeps the corner rules; an end at a swerve piece is a
        # plain butt joint, so the run must reach it.
        for span_lo, span_hi in spans:
            face_lo, face_hi = span_lo <= start + 1.75 + 1e-6, span_hi >= end - 1.75 - 1e-6
            # FA: a mitred square corner's CoveBaseInnerCorner covers the first INNER of the foot (checked below).
            first = start + 1.75 + (r_low + TAIL if r_low else 0) + jamb(False) + (INNER if mitre(side, False) else 0) \
                if face_lo else span_lo
            tail_end = end - 1.75 - (r_high + TAIL if r_high else 0) - jamb(True) - (INNER if mitre(side, True) else 0) \
                if face_hi else span_hi
            span_holes = [(lo, hi) for lo, hi in holes if (face_lo or hi > first) and (face_hi or lo < tail_end)]
            hole_ends = [v for hole in span_holes for v in hole] + ([first] if face_lo and jamb(False) else []) \
                + ([tail_end] if face_hi and jamb(True) else [])
            ends = [first, tail_end] + [v for hole in span_holes for v in hole]

            def bare_ok(a, b):
                """Bare foot over [a, b]: legal only beside a hole, in a segment too short for its stops."""
                seg_lo = max([v for v in ends if v <= a + .06], default=first)
                seg_hi = min([v for v in ends if v >= b - .06], default=tail_end)
                beside = any(abs(v - a) < .06 or abs(v - b) < .06 for v in hole_ends)
                # WP7 review: at a doorless square corner a corner-to-hole segment too short to carry the 3.25
                # mitre leg plus a stop (under CORNER_SHORT) stays bare; the corner rules below check the other wall.
                if (face_lo and doorless_square(side, False) and abs(seg_lo - first) < .06 and seg_hi < tail_end - .06
                        or face_hi and doorless_square(side, True) and abs(seg_hi - tail_end) < .06 and seg_lo > first + .06):
                    if seg_hi - seg_lo < CORNER_SHORT:
                        return True
                return beside and b - a < 3 - 1e-6 and seg_hi - seg_lo < 6 - 1e-6
            cursor = first
            span_pieces = [(lo, hi) for lo, hi in pieces if hi > first - .06 and lo < tail_end + .06]
            for a, b in sorted(span_pieces + span_holes):
                if a > cursor + .06:
                    assert bare_ok(cursor, a), f"hall {index} {side} base cove is open over {cursor:.2f}..{a:.2f}"
                cursor = max(cursor, b)
            assert cursor >= tail_end - .06 or bare_ok(cursor, tail_end), \
                f"hall {index} {side} base cove stops at {cursor:.2f} short of {tail_end:.2f}"
        assert any(low[along] <= start + .05 for low, high in wall_ranges)
        assert any(high[along] >= end - .05 for low, high in wall_ranges)
        base_pieces[side] = [(o["Attrs"]["Level2_KitComponent"], bounds(o)[0][along], bounds(o)[1][along])
                             for o in room_parts if o["ClassName"] == "MeshPart"
                             and re.fullmatch(r"CoveBase(\d+|Stop_PX|Stop_NX|StopCorner_PX|StopCorner_NX)",
                                              o["Attrs"].get("Level2_KitComponent", ""))
                             and abs(cf_vector(frame(o["CFrame"]), (1, 0, 0))[along]) >= .9
                             and abs(cf_point(frame(o["CFrame"]), (0, 0, 0))[normal] - edge) < 4]
        faces[side] = (start + 1.75, end - 1.75)

    # The square-corner inventory was checked before the wall feet (see above); here the pieces' poses.
    for hi_x in (False, True):
        for hi_z in (False, True):
            here = inner_pieces.get((hi_x, hi_z), [])
            if radii.get((hi_x, hi_z), 0) or (hi_x, hi_z) in arcs:
                continue
            x_side, z_side = ("South" if hi_z else "North"), ("East" if hi_x else "West")
            want = wanted[(hi_x, hi_z)]
            fx = hall["MaxX"] - 1.75 if hi_x else hall["MinX"] + 1.75
            fz = hall["MaxZ"] - 1.75 if hi_z else hall["MinZ"] + 1.75
            for kind, o in here:
                # Legs along the walls into the room; the mesh spans .3 into each wall to INNER from the face corner.
                f = frame(o["CFrame"])
                ax, az = cf_vector(f, (1, 0, 0)), cf_vector(f, (0, 0, 1))
                legs = sorted([(round(ax[0]), round(ax[2])), (round(az[0]), round(az[2]))])
                assert legs == sorted([(-1 if hi_x else 1, 0), (0, -1 if hi_z else 1)]), \
                    f"hall {index} {kind} legs {legs} do not point into the room"
                low, high = bounds(o)
                lx = high[0] if hi_x else low[0]
                lz = high[2] if hi_z else low[2]
                assert abs(lx - (fx + (.3 if hi_x else -.3))) < .02 and abs(lz - (fz + (.3 if hi_z else -.3))) < .02, \
                    f"hall {index} {kind} reaches {(lx, lz)}, not .3 into the walls behind face corner {(fx, fz)}"
                reach_x = low[0] if hi_x else high[0]
                reach_z = low[2] if hi_z else high[2]
                assert abs(abs(reach_x - fx) - INNER) < .02 and abs(abs(reach_z - fz) - INNER) < .02, \
                    f"hall {index} {kind} legs end at {(reach_x, reach_z)}, not {INNER} from {(fx, fz)}"
                ylo = want[kind] - 4 if kind == "CoveBaseInnerCorner" else want[kind]
                assert abs(low[1] - ylo) < .02, f"hall {index} {kind} sits at {low[1]:.3f}, not {ylo:.3f}"
            for side, high_end in ((x_side, hi_x), (z_side, hi_z)):
                face = faces[side][1 if high_end else 0]
                near = [(kind, lo, hi) for kind, lo, hi in base_pieces[side]
                        if (hi > face - INNER + .05 if high_end else lo < face + INNER - .05)]
                if "CoveBaseInnerCorner" in want:
                    assert not near, f"hall {index} corner {(hi_x, hi_z)}: {near} stands in the base inner corner's leg"
                else:
                    reach = [k for k, lo, hi in near if re.fullmatch(r"CoveBase\d+", k)
                             and (hi > face - .06 if high_end else lo < face + .06)]
                    assert not reach, f"hall {index} corner {(hi_x, hi_z)}: a base run reaches the square corner " \
                        f"without the inner corner {reach}"


def check_snapshot(build, components, slides):
    """Independent name/type/spatial oracle beyond the actual consumer asserts."""
    layout, manifest = build["Layout"], build["Manifest"]
    objects = {o["Id"]: o for o in build["Objects"]}

    def ref(value, cls=None):
        assert isinstance(value, dict) and "$instance" in value, f"expected Instance: {value}"
        o = objects[value["$instance"]]
        if cls:
            assert o["ClassName"] == cls, f"{o['Name']} must be {cls}"
        return o

    world = ref(manifest["World"], "Model")
    wid = world["Id"]

    def inside(o, root=wid):
        parent = o["Parent"]
        while parent in objects:
            if parent == root:
                return True
            parent = objects[parent]["Parent"]
        return parent == root

    world_objects = [o for o in objects.values() if inside(o)]
    byname = {}
    for o in world_objects:
        byname.setdefault(o["Name"], []).append(o)

    def named(name, cls=None):
        matches = byname.get(name, [])
        assert len(matches) == 1, f"expected one {name}, got {len(matches)}"
        o = matches[0]
        if cls:
            assert o["ClassName"] == cls, f"{name} wrong class"
        return o

    def descendants(model):
        return [o for o in world_objects if inside(o, model["Id"])]

    def parts(model):
        return [o for o in descendants(model) if o["ClassName"] in {"Part", "MeshPart", "WedgePart"}]

    def components_in(model):
        return Counter(o["Attrs"].get("Level2_KitComponent") for o in parts(model))

    assert world["Name"] == "Level 2 Generated World"
    for key, value in {
        "Level2_Seed": layout["Seed"], "Level2_Generation": build["Generation"],
        "Level2_GenerationAttempt": layout["Attempt"], "Level2_Theme": "Poolrooms",
    }.items():
        assert world["Attrs"].get(key) == value, f"world {key}"
    assert world["Attrs"].get("Level2_KitBuild") == "offline-exported-poolrooms"
    assert world["Attrs"].get("Level2_PoolroomsPreview") is True
    assert world["Attrs"].get("Level2_PoolroomsAmbient") == {
        "R": 70/255, "G": 170/255, "B": 150/255, "$type": "Color3"}
    assert world["Attrs"].get("Level2_WorldDescendants") == len(world_objects)
    assert manifest["Generation"] == build["Generation"]
    assert manifest["Layout"] == layout
    assert "BuoyantProps" not in manifest, "raycast exclusions must not contain a non-Instance table"
    for name in ("Level 2 Geometry", "Level 2 Objectives", "Level 2 Lighting", "Level 2 Navigation", "Level 2 Entity Nodes"):
        assert named(name, "Folder")["Parent"] == wid
    geometry = named("Level 2 Geometry")
    for name in ("Level 2 Halls", "Level 2 Corridors", "Level 2 Kids Wing"):
        assert named(name, "Folder")["Parent"] == geometry["Id"]
    objective = named("Level 2 Objectives")
    pressure_folder = named("Level 2 Pressure Doors", "Folder")
    assert pressure_folder["Parent"] == objective["Id"]
    navigation, nodes = ref(manifest["Navigation"], "Folder"), ref(manifest["EntityNodes"], "Folder")
    assert navigation["Name"] == "Level 2 Navigation" and nodes["Name"] == "Level 2 Entity Nodes"
    assert ref(manifest["EntityDen"], "Part")["Name"] == "Level 2 Entity Den A Spawn"
    for key in ("TerrainCenter", "TerrainSize"):
        point(manifest[key])
        assert manifest[key] == world["Attrs"][f"Level2_{key}"]
    assert manifest["PreviousWaterAppearance"] == build["BeforeWater"]
    assert build["AfterWater"] == {
        "WaterColor": {"R": 70/255, "G": 170/255, "B": 150/255, "$type": "Color3"},
        "WaterTransparency": .35, "WaterReflectance": .1, "WaterWaveSize": .035,
        "WaterWaveSpeed": 1.65,
    }, "Poolrooms terrain water appearance"
    assert isinstance(manifest["WaterRegions"], (list, dict))
    regions = manifest["WaterRegions"]
    assert len(regions) > 0
    assert len(regions) == len(build["Fills"]), "every terrain write must have exactly one cleanup region"
    for region, fill in zip(regions, build["Fills"]):
        assert region["CFrame"] == fill["CFrame"] and region["Size"] == fill["Size"]
        assert fill["Material"] == "Material.Water"
        assert all(x > 0 for x in point(region["Size"]))

    halls = {h["Index"]: h for h in layout["Halls"]}
    assert layout["Bounds"]["MinZ"] >= -600
    assert world["Attrs"]["Level2_HallCount"] == len(halls)
    assert world["Attrs"]["Level2_CorridorCount"] == len(layout["Corridors"])
    assert world["Attrs"]["Level2_KidsRoomCount"] == len(layout["KidsArea"]) == 5
    assert world["Attrs"]["Level2_SlideHallCount"] == len(layout["SlideHalls"]) == 1
    hall_models = {}
    type_counts = Counter()
    hall_types = {"ColumnHall", "BigPool", "VaultArcade", "CurvedChannel",
                  "SpiralWell", "CorridorHall", "PaddlingRoom", "PumpHall",
                  "Arrival", "ExitHall"}
    for h in halls.values():
        models = [o for o in world_objects if o["ClassName"] == "Model"
                  and o["Attrs"].get("Level2_HallIndex") == h["Index"]]
        assert len(models) == 1, f"hall {h['Index']} needs one room model"
        room = models[0]
        hall_models[h["Index"]] = room
        assert room["Attrs"].get("Level2_HallId") == h["Id"]
        assert room["Attrs"].get("Level2_FloorY") == h["FloorY"]
        assert room["Attrs"].get("Level2_Role") == h["Role"]
        room_parts = parts(room)
        roofs = [o for o in room_parts if "Roof Collider" in o["Name"]]
        assert roofs and all(o["CanCollide"] and o["CanQuery"] for o in roofs), \
            f"hall {h['Index']} lacks collidable roof fragments"
        if h["Role"] == "Small":
            assert h["Type"] == "Chamber" and h["Prefab"] in {"Chamber_A", "Chamber_B", "Chamber_C", "Chamber_D"}
            assert room["Attrs"].get("Level2_KitComponent") == h["Prefab"]
            assert room["Parent"] == named("Level 2 Halls")["Id"]
            assert h["PoolType"] == "Dry"  # Layout AI flag; prefab itself has shallow authored water.
            near(frame(room["WorldPivot"])[:3], (h["Center"]["X"], h["FloorY"], h["Center"]["Z"]), .01)
            assert any(o["Name"] == "Level 2 Room Aqua Floor" and o["MaterialVariant"] == "PR Tile Aqua"
                       and o["Attrs"].get("Level2_EntityGround") for o in room_parts)
            exported_water = components[h["Prefab"]]["attrs"]["waterRegion"]
            expected_center = cf_point(frame(room["WorldPivot"]), exported_water["center"])
            assert any(math.dist(frame(region["CFrame"])[:3], expected_center) < .01
                       and math.dist(point(region["Size"]), exported_water["size"]) < .01
                       for region in regions), f"chamber {h['Index']} lacks its authored shallow water region"
        else:
            assert h["Type"] in hall_types
            type_counts[h["Type"]] += 1
            if h["Type"] == "PumpHall":
                floor_names = {f"Level 2 Hall Floor {h['Index']}", f"Level 2 Hall Water Floor {h['Index']}"}
            elif h["Type"] == "Arrival" or h["PoolType"] == "Dry" and h["Type"] != "PaddlingRoom":
                floor_names = {f"Level 2 Hall Floor {h['Index']}"}
            else:
                floor_names = {f"Level 2 Hall Water Floor {h['Index']}"}
            floor = [o for o in room_parts if o["Name"] in floor_names]
            assert len(floor) == 1 and floor[0]["CanCollide"] and floor[0]["CanQuery"]
            assert floor[0]["Attrs"].get("Level2_EntityGround") is True
            assert floor[0]["MaterialVariant"] == ("PR Tile" if "Water" not in floor[0]["Name"]
                                                   else "PR Tile Aqua")
            overhead = [o for o in room_parts if o["Name"].startswith("Level 2 Overhead Tile")]
            assert overhead and all(o["MaterialVariant"] == "PR Tile" for o in overhead)
            placed = components_in(room)
            assert not any("Corner Seal" in o["Name"] for o in room_parts), \
                f"hall {h['Index']} retains an invisible corner seal"
            corners = [o for o in room_parts if o["ClassName"] == "MeshPart"
                       and o["Attrs"].get("Level2_KitComponent", "").startswith("CornerCove_R")]
            assert len(corners) <= 4
            for cove in corners:
                radius = cove["Attrs"].get("Level2_CornerRadius")
                assert radius in {8, 16, 24}
                assert cove["Attrs"]["Level2_KitComponent"] == f"CornerCove_R{radius}_H{h['CeilingClass']}"
                chunk_center = components[cove["Attrs"]["Level2_KitComponent"]]["meshRecords"][0]["center"]
                offset = cf_vector(frame(cove["CFrame"]), chunk_center)
                x, y, z = (position(cove)[i]-offset[i] for i in range(3))
                assert abs(y-h["FloorY"]) < .01
                assert any(abs(x-(edge_x+sx*(1.75+radius)))<.01
                           and abs(z-(edge_z+sz*(1.75+radius)))<.01
                           for edge_x,sx in ((h["MinX"],1),(h["MaxX"],-1))
                           for edge_z,sz in ((h["MinZ"],1),(h["MaxZ"],-1))), \
                    f"hall {h['Index']} corner is not at its fillet centre"
                blocks = [o for o in room_parts if o["Attrs"].get("Level2_KitComponent")==cove["Attrs"]["Level2_KitComponent"]
                          and o["Name"].startswith("Corner Block")]
                assert blocks and all(o["CanCollide"] for o in blocks), \
                    f"hall {h['Index']} lost authored corner collision"
            for prefix in ("CoveTop", "CoveBase"):
                assert any(key and key.startswith(prefix) for key in placed), f"hall {h['Index']} lacks {prefix}"
            if h["Type"] not in {"Arrival", "PumpHall"} and h["PoolType"] != "Dry":
                assert any(key and key.startswith("Walkway_") for key in placed), \
                    f"hall {h['Index']} lacks its ring deck"
            for item in room_parts:
                if item["Name"].startswith(("Level 2 Hall Wall ", "Level 2 Overhead Tile ")):
                    assert item["MaterialVariant"] == "PR Tile" and item["Material"] == "Material.SmoothPlastic"
            required = {
                "ColumnHall": ("Column_D10_",),
                "BigPool": ("Column_D10_", "LightRound", "Walkway_Ring", "WallVoid"),
                # F4-I (WP7 review): groin bays on their piers; a hall whose door spokes leave no 2x2 pier
                # group falls back to a column field below (never a bare pier arcade).
                "VaultArcade": ("VaultPier", "VaultBay32_"),
                # F9: the free-standing partitions are deleted; the walls themselves swerve (WP8): every swerve
                # hall has two or more corner arcs, its floor a column field.
                "CurvedChannel": ("Column_D10_", "SwerveCorner_R"),
                "SpiralWell": ("Column_D10_", "SpiralStairWell_", "LightWell_R12"),
                "CorridorHall": ("VaultPier", "SunSlit", "DrainHole"),
                "PaddlingRoom": ("PoolSteps_Curved", "Column_D6_"),
                "PumpHall": ("LightWell_",),
                "Arrival": ("SunSlit",),
                "ExitHall": ("ExitPlatform", "ExitSpiral", "LightWell_R14"),
            }
            need = required[h["Type"]]
            if h["Type"] == "VaultArcade" and not any(key and key.startswith("VaultBay32_") for key in placed):
                assert not any(key == "VaultPier" for key in placed), f"vault hall {h['Index']} has piers but no bay"
                need = ("Column_D10_",)
            for prefix in need:
                assert any(key and key.startswith(prefix) for key in placed), \
                    f"hall {h['Index']} {h['Type']} lacks {prefix}"
            if h["Type"] == "VaultArcade":
                # The H34/H42 export is a 12-stud-high bay at the top of its
                # height class. H52 reuses H42 and must be raised only 10.
                source = "VaultBay32_H" + str(min(h["CeilingClass"], 42))
                bays = [o for o in room_parts if o["Attrs"].get("Level2_KitComponent") == source]
                assert not bays or any(o["ClassName"] == "MeshPart" for o in bays), \
                    f"vault hall {h['Index']} lacks visible {source} bays"
                ceiling = h["FloorY"] + h["CeilingClass"]
                for bay in bays:
                    low, high = bounds(bay)
                    assert low[1] >= h["FloorY"] - .1 and high[1] <= ceiling + .1, \
                        f"vault hall {h['Index']} {source} {bay['Name']} extends past its ceiling"
                    if bay["ClassName"] == "MeshPart":
                        assert abs(low[1] - (ceiling - 12)) < .1 and abs(high[1] - ceiling) < .1, \
                            f"vault hall {h['Index']} {source} bay is not seated under its ceiling"
            if h["Type"] in {"VaultArcade", "CorridorHall"}:
                # Both the visible tile and invisible block in VaultPier are
                # 42 studs in the export; stretch them to each hall class.
                piers = [o for o in room_parts if o["Attrs"].get("Level2_KitComponent") == "VaultPier"]
                if h["Type"] == "CorridorHall":
                    assert piers, f"hall {h['Index']} lacks VaultPier geometry"
                ceiling = h["FloorY"] + h["CeilingClass"]
                for pier in piers:
                    low, high = bounds(pier)
                    assert abs(low[1] - (h["FloorY"]-4)) < .1 and abs(high[1] - ceiling) < .1, \
                        f"hall {h['Index']} {h['Type']} {pier['Name']} does not span floor to ceiling"
            if h.get("PumpIndex"):
                assert any(key and key.startswith("LightWell_") for key in placed), \
                    f"pump hall {h['Index']} lacks a light well over the pump"
            if h["Type"] == "PaddlingRoom":
                assert abs(bounds(floor[0])[1][1] - (h["FloorY"] - .8)) < .2, \
                    "paddling floor top must be 0.8 below water level"
        nav = named(f"Level 2 Navigation Node {h['Index']}", "Part")
        near(position(nav), (h["Center"]["X"], h["FloorY"] + 1, h["Center"]["Z"]))
        assert nav["Parent"] == navigation["Id"] and nav["Attrs"].get("Level2_Role") == h["Role"]
        for k in range(1, 5):
            patrol = named(f"Level 2 Entity Patrol Node {h['Index']}.{k}", "Part")
            assert patrol["Parent"] == nodes["Id"] and patrol["Attrs"].get("Level2_HallId") == h["Id"]
            assert abs(position(patrol)[1] - h["FloorY"] - 2) < 1e-4
            x, _, z = position(patrol)
            assert h["MinX"] < x < h["MaxX"] and h["MinZ"] < z < h["MaxZ"]
        if h["Role"] == "Kids Area":
            assert h["Type"] == "PaddlingRoom"
            assert room["Attrs"].get("Level2_ContainsPump") == (h.get("PumpIndex") is not None)
            assert room["Attrs"].get("Level2_PlayArchetype") == "PaddlingRoom"
            assert room["Attrs"].get("Level2_CoreSetPiecePlaced") is True
            spawn = named(f"Level 2 Pool Foam Spawn {h['Index']}", "Part")
            assert spawn["Parent"] == nodes["Id"]
            assert spawn["Attrs"].get("Level2_PoolFoamSpawn") is True and spawn["Attrs"].get("Level2_HallId") == h["Id"]
            assert not any(spawn[key] for key in ("CanCollide", "CanQuery", "CanTouch"))
            assert abs(position(spawn)[1] - h["FloorY"] - 2) < 1e-4
            near(point(spawn["Attrs"]["Level2_SpawnPocketSize"]), (8, 8, 8))
            sx, _, sz = position(spawn)
            assert h["MinX"] + 4 <= sx <= h["MaxX"] - 4 and h["MinZ"] + 4 <= sz <= h["MaxZ"] - 4
            floor_under = []
            for collider in room_parts:
                if not collider["CanCollide"]:
                    continue
                low, high = bounds(collider)
                if low[0] <= sx <= high[0] and low[2] <= sz <= high[2] \
                        and abs(high[1] - (h["FloorY"] - .8)) <= .2:
                    floor_under.append(collider)
                if low[0] < sx + 4 and high[0] > sx - 4 and low[2] < sz + 4 and high[2] > sz - 4 \
                        and high[1] > h["FloorY"] + .18 and low[1] < h["FloorY"] + 5.88:
                    assert collider["Attrs"].get("Level2_EntityGround") is True and high[1] <= h["FloorY"] + 3.55, \
                        f"Pool Foam spawn {h['Index']} is blocked by {collider['Name']}"
            assert floor_under and any(o["Attrs"].get("Level2_EntityGround") for o in floor_under), \
                f"Pool Foam spawn {h['Index']} lacks standable ground"
    for suffix, hall_key in (("A", "EntityDen"), ("B", "EntityDenB")):
        den = named(f"Level 2 Entity Den {suffix} Spawn", "Part")
        assert den["Parent"] == nodes["Id"]
        assert den["Attrs"].get("Level2_HallId") == layout[hall_key]["Id"]
        den_center = (layout[hall_key]["Center"]["X"], layout[hall_key]["FloorY"],
                      layout[hall_key]["Center"]["Z"])
        near(point(nodes["Attrs"][f"Level2_Den{suffix}Position"]), den_center)
        near(position(den), (den_center[0], den_center[1] + 3, den_center[2]))

    pumps = manifest["Pumps"]
    assert len(pumps) == len(layout["PumpHalls"]) == 3
    lever_colors = set()
    for i, pump in enumerate(pumps, 1):
        assert pump["Index"] == i
        model = ref(pump["Model"], "Model")
        assert model["Parent"] == objective["Id"] and model["Name"].startswith("Level 2 Pump Station")
        assert model["ModelStreamingMode"] == "ModelStreamingMode.Persistent"
        pivot = frame(model["WorldPivot"])[:3]
        hall_center = point(layout["PumpHalls"][i-1]["Center"])
        near((pivot[0],pivot[2]), (hall_center[0],hall_center[2]))
        assert abs(pivot[1]-layout["PumpHalls"][i-1]["FloorY"]) <= 3
        assert model["Attrs"].get("Level2_PumpRunning") is False
        assert model["Attrs"].get("Level2_PumpIndex") == i
        assert model["Attrs"].get("Level2_HallId") == layout["PumpHalls"][i-1]["Id"]
        color = model["Attrs"].get("Level2_LeverHandleColorValue")
        assert isinstance(color, dict) and color.get("$type") == "Color3"
        lever_colors.add(tuple(color[k] for k in "RGB"))
        prompt = ref(pump["Prompt"], "ProximityPrompt")
        assert prompt["Name"] == "Level 2 Pump Prompt" and prompt["ActionText"] == "START PUMP"
        assert prompt["HoldDuration"] == 1.6 and prompt["MaxActivationDistance"] == 10
        assert prompt["RequiresLineOfSight"] is True and prompt["Enabled"] is True
        assert prompt["ObjectText"] == f"Pump station {i}"
        assert inside(prompt, model["Id"])
        grip = ref(pump["LeverHandle"], "Part")
        assert prompt["Parent"] == grip["Id"] and grip["CanQuery"] is True
        assert math.dist(position(grip),hall_center) <= 10, "pump grip outside its interaction reach"
        for key in ("Lamp", "GaugeNeedlePivot", "Lever", "LeverStatusRing"):
            assert ref(pump[key])["ClassName"] in {"Part", "MeshPart"}
        assert ref(pump["Lamp"], "Part")["Material"] == "Material.Neon"
        ring = ref(pump["LeverStatusRing"], "Part")
        near(point(ring["Size"]), (.12,.95,.95))
        near(cf_vector(frame(ring["CFrame"]),(1,0,0)), (0,0,-1))
        assert ring["Shape"] == "PartType.Cylinder", "pump ring's local X must face the panel"
        assert ref(pump["LampGlow"], "PointLight")["Parent"] == ref(pump["Lamp"])["Id"]
        assert ref(pump["LeverAssembly"], "Model")["Parent"] == model["Id"]
        for key in ("GaugeNeedleZeroCFrame", "GaugeNeedleFullCFrame", "LeverRestCFrame"):
            frame(pump[key])
        assert pump["GaugeNeedleZeroCFrame"] != pump["GaugeNeedleFullCFrame"]
        assert pump["GaugeNeedleZeroCFrame"] == ref(pump["GaugeNeedlePivot"])["CFrame"]
        assert pump["LeverRestCFrame"] == ref(pump["Lever"])["CFrame"]
        assert ref(pump["GaugePressureValue"], "NumberValue")["Value"] == 0
        assert ref(pump["GaugePressureText"], "TextLabel")["Text"] == "0%"
        for component in ("PumpStation", "PumpLever", "PumpNeedle", "PumpLamp"):
            assert components_in(model)[component] > 0, f"pump {i} lacks {component}"
        intakes = [o for o in world_objects if o["Name"] == "Level 2 Pump Intake Pipe" and inside(o, model["Id"])]
        assert len(intakes) == 2 and all(not o["CanQuery"] for o in intakes)
        assert len([o for o in world_objects if o["ClassName"] == "ProximityPrompt" and inside(o, model["Id"])]) == 1
        # F4-B/G4 (R2 5, R3): the plinth stands on its floor, or in the 0.8-deep kids pool on a tiled pedestal that
        # reaches y = FloorY-4 (through the basin floor) and carries every plinth edge: exactly one tile (.5) wider
        # each side, every edge on the 0.5 lattice like the 9 x 7 plinth's (I3; was .1-.25 wider each side of the
        # old off-lattice 9.2 x 7.2 plinth).
        pump_hall = layout["PumpHalls"][i-1]
        plinth = next(o for o in world_objects if o["Name"] == "Level 2 Pump Plinth" and inside(o, model["Id"]))
        floor = next(o for o in parts(hall_models[pump_hall["Index"]])
                     if o["Name"] in {f"Level 2 Hall Floor {pump_hall['Index']}", f"Level 2 Hall Water Floor {pump_hall['Index']}"})
        pedestals = [o for o in parts(hall_models[pump_hall["Index"]])
                     if o["Name"] == f"Level 2 Pump Pedestal {pump_hall['PumpIndex']}"]
        if "Water" in floor["Name"]:
            assert len(pedestals) == 1, f"pump {i} in a flooded room lacks its pedestal"
            low, high = bounds(pedestals[0])
            p_low, p_high = bounds(plinth)
            assert abs(high[1] - p_low[1]) < .01 and low[1] <= pump_hall["FloorY"] - 4 + .01 \
                and all(abs(p_low[k] - .5 - low[k]) < 1e-6 and abs(p_high[k] + .5 - high[k]) < 1e-6
                        and abs(low[k] * 2 - round(low[k] * 2)) < 1e-6 for k in (0, 2)) \
                and pedestals[0]["CanCollide"] and pedestals[0]["Attrs"].get("Level2_EntityGround"), \
                f"pump {i} pedestal does not carry its plinth from the basin"
        else:
            assert not pedestals and abs(bounds(plinth)[0][1] - bounds(floor)[1][1]) <= .05, \
                f"pump {i} plinth bottom {bounds(plinth)[0][1]:.3f} floats over floor top {bounds(floor)[1][1]:.3f}"
    assert len(lever_colors) == 3, "live shuffled pump handle colors must be distinct"

    corridors = {c["Index"]: c for c in layout["Corridors"]}
    corridor_records = manifest["Corridors"]
    assert len(corridor_records) == len(corridors)
    pressure = [c for c in corridors.values() if c["Kind"] == "PressureDoor"]
    assert len(manifest["PressureDoors"]) == len(pressure)
    for item in manifest["PressureDoors"]:
        door = ref(item["Door"], "Part")
        c = corridors[door["Attrs"]["Level2_CorridorIndex"]]
        assert c in pressure and door["Name"] == f"Level 2 Pressure Door {c['Index']}"
        assert door["Parent"] == pressure_folder["Id"] and door["CanCollide"]
        # FA (world audit 07, VERIFY D5): the door is the bore's own disc (Cylinder r 17 round the bore centre
        # ToY+13, its axis along the corridor), seated in the To mouth collar .1 inside both collar faces, so the
        # bore no longer cuts 1.1 into a slab standing across its end plane.
        inward = 1 if c["To"] > c["From"] else -1
        at = c["To"] + inward * .875
        expected = (at, c["ToY"] + 13, c["Cross"]) if c["Axis"] == "X" else (c["Cross"], c["ToY"] + 13, at)
        near(position(door), expected)
        # FA review: r 17.3, not the bore's 17. The bore and Roblox's cylinder are both faceted, so an r-17 disc left
        # slivers round its outline and its rim surfaced at every bore vertex; the overlap is buried in the collar.
        near(point(door["Size"]), (1.55, 34.6, 34.6))
        ds = point(door["Size"])
        assert ds[1] == ds[2] and ds[1] / 2 >= BORE_RADIUS + .25, \
            f"pressure door {c['Index']} radius {ds[1] / 2} must overlap the r {BORE_RADIUS} bore by .25"
        assert door["Shape"] == "PartType.Cylinder", "pressure door must be the bore's disc"
        axis = cf_vector(frame(door["CFrame"]), (1, 0, 0))
        assert abs(axis[0 if c["Axis"] == "X" else 2]) > .999, "pressure door disc must face along its corridor"
        stripe = ref(item["Stripe"], "Part")
        assert stripe["Parent"] == pressure_folder["Id"]
        # FA review: the stripe rides up with the door into the 1.75-deep hall lintel. Along the corridor it must be
        # proud of the disc (so it shows at rest) and strictly inside both lintel faces (at 1.75 it was coplanar with
        # them and z-fought on the wall above the mouth while it rose).
        k = 0 if c["Axis"] == "X" else 2
        depth = point(stripe["Size"])[k]
        assert ds[0] < depth < WALL_THICKNESS - .05 + 1e-6 and abs(position(stripe)[k] - at) < 1e-6, \
            f"pressure door stripe {c['Index']} is {depth} deep at {position(stripe)[k]}, wants a centred " \
            f"{ds[0]} < depth <= {WALL_THICKNESS - .05}"
    for c in corridors.values():
        record = corridor_records[c["Index"] - 1] if isinstance(corridor_records, list) else corridor_records[str(c["Index"])]
        assert record["Corridor"] == c
        model = ref(record["Model"], "Model")
        assert model["Name"] == f"Level 2 Corridor {c['Index']}"
        assert model["Parent"] == named("Level 2 Corridors")["Id"]
        assert model["Attrs"].get("Level2_CorridorIndex") == c["Index"]
        component = ("Pipe_" if c["Kind"] == "Narrow" else "RoundTunnel_") + c["Variant"] + "_" + str(c["Length"])
        source = component
        assert source in components and model["Attrs"].get("Level2_KitComponent") == source
        assert not model["Attrs"].get("Level2_KitSourceComponent") \
            and not model["Attrs"].get("Level2_KitStretchLength"), \
            f"corridor {c['Index']} stretches a kit asset and changes its collar depth"
        collar = components[source]["attrs"]
        assert collar["InnerRadius"] == (6 if c["Kind"] == "Narrow" else 17), \
            f"corridor {c['Index']} exported bore radius does not match its wall collar"
        assert collar["CircleCentreY"] == (6 if c["Kind"] == "Narrow" else 13), \
            f"corridor {c['Index']} exported mouth circle is off the floor"
        assert collar["CollarDepth"] == 1.75, f"corridor {c['Index']} lacks a flush 1.75-deep collar"
        mouth_half = hole_half(c)    # LATTICE_SPEC 6: the collar outline (tunnel 18, pipe 6)
        mesh_records = components[source]["meshRecords"]
        assert mesh_records and max(chunk["center"][1] + chunk["size"][1]/2 for chunk in mesh_records) \
            >= (12 if c["Kind"] == "Narrow" else 32) + abs(c["ToY"] - c["FromY"]) - .05, \
            f"corridor {c['Index']} visual collar does not reach the opening top"
        assert all(abs(chunk["center"][0]) + chunk["size"][0]/2 <= mouth_half + .1
                   for chunk in mesh_records), f"corridor {c['Index']} outer mesh protrudes past its collar"
        assert max(abs(chunk["center"][0]) + chunk["size"][0]/2 for chunk in mesh_records) >= mouth_half - .05, \
            f"corridor {c['Index']} visual collar misses an outer side edge"
        source_half_length = int(source.rsplit("_", 1)[1])/2
        assert abs(min(chunk["center"][2] - chunk["size"][2]/2 for chunk in mesh_records)
                   + source_half_length + collar["CollarDepth"]) <= .05 \
            and abs(max(chunk["center"][2] + chunk["size"][2]/2 for chunk in mesh_records)
                    - source_half_length - collar["CollarDepth"]) <= .05, \
            f"corridor {c['Index']} visual collar depth or mouth reach differs from export"
        assert c["Length"] == c["To"] - c["From"] and c["Width"] == (12 if c["Kind"] == "Narrow" else 34)
        model_cf = frame(model["WorldPivot"])
        expected_center = ((c["From"] + c["To"]) / 2, min(c["FromY"], c["ToY"]), c["Cross"]) if c["Axis"] == "X" \
            else (c["Cross"], min(c["FromY"], c["ToY"]), (c["From"] + c["To"]) / 2)
        near(model_cf[:3], expected_center)
        corridor_parts = parts(model)
        roof_name = ("Level 2 Passage Roof Collider " if c["Kind"] == "Narrow" else "Level 2 Corridor Roof Collider ") + str(c["Index"])
        roof_parts = [o for o in corridor_parts if o["Name"] == roof_name]
        assert roof_parts and all(o["CanCollide"] for o in roof_parts), \
            f"corridor {c['Index']} needs collidable roof coverage"
        # Imported meshes are noncolliding. Both mouth collars and the barrel
        # need real side/roof collision beyond the round clear bore, including
        # at the two ends and halfway through a long or stepped corridor.
        shell_parts = [o for o in corridor_parts if o["ClassName"] == "Part" and o["CanCollide"]
                       and any(word in o["Name"] for word in (" Side ", " Facet ", " Collar ", "Backstop", "Roof Collider", "Crown Stop"))]
        assert shell_parts, f"corridor {c['Index']} has no collidable round shell"
        radius, cy = collar["InnerRadius"], collar["CircleCentreY"]
        rise = abs(c["ToY"] - c["FromY"])
        z_samples = {-c["Length"]/2 + 1, 0, c["Length"]/2 - 1}
        if rise:
            z_samples.update((-c["Length"]/4, c["Length"]/4))
        for z in sorted(z_samples):
            # The kit's stair bore climbs evenly over the whole length.
            floor_offset = rise * max(0, min(1, (z + c["Length"]/2)/c["Length"]))
            for y in (1, cy + radius - 1):
                bore_half = math.sqrt(radius*radius - (y-cy)*(y-cy))
                for side in (-1, 1):
                    sample = cf_point(model_cf, (side*bore_half, floor_offset + y, z))
                    assert any(contains_part(piece, sample) for piece in shell_parts), \
                        f"corridor {c['Index']} shell leaks at side {side}, local {(bore_half, y, z)}"
            crown = cf_point(model_cf, (0, floor_offset + cy + radius + .35, z))
            assert any(contains_part(piece, crown) for piece in shell_parts), \
                f"corridor {c['Index']} roof leaks at local z {z}"
        for local_z in (-c["Length"] / 2 + 1, c["Length"] / 2 - 1):
            foot = cf_point(model_cf, (0, 0, local_z))
            assert any(o["CanCollide"] and o["Attrs"].get("Level2_EntityGround")
                       and (lambda low, high: low[0] <= foot[0] <= high[0]
                            and low[2] <= foot[2] <= high[2])(*bounds(o))
                       for o in corridor_parts), f"corridor {c['Index']} has a floor gap at its mouth"
        assert any(o["ClassName"] == "MeshPart" for o in corridor_parts), f"{source} visual mesh missing"
        assert not any(o["ClassName"] == "MeshPart" and o["CanCollide"] for o in corridor_parts)
        endpoints = (("MouthFrom", c["To"], c["ToY"]), ("MouthTo", c["From"], c["FromY"])) \
            if c["ToY"] < c["FromY"] else (("MouthFrom", c["From"], c["FromY"]), ("MouthTo", c["To"], c["ToY"]))
        for marker_name, end, end_y in endpoints:
            exported = next(m for m in components[source]["markers"] if m["name"] == marker_name)
            assert exported["attrs"]["clearWidth"] == (12 if c["Kind"] == "Narrow" else 2 * BORE_RADIUS) \
                and exported["attrs"]["clearHeight"] == (12 if c["Kind"] == "Narrow" else 30), \
                f"corridor {c['Index']} {marker_name} mouth marker differs from the collar"
            local = list(exported["cf"][:3])
            world_point = cf_point(model_cf, local)
            assert abs(world_point[0 if c["Axis"] == "X" else 2] - end) < 1e-4
            assert abs(world_point[1] - end_y) < .01, \
                f"corridor {c['Index']} {marker_name} collar front misses its hall floor"
            threshold_name = f"Level 2 {'Passage' if c['Kind'] == 'Narrow' else 'Corridor'} {marker_name} Threshold"
            thresholds = [o for o in corridor_parts if o["Name"] == threshold_name]
            assert len(thresholds) == 1, f"corridor {c['Index']} lacks {marker_name} solid collar threshold"
            threshold = thresholds[0]
            low, high = bounds(threshold)
            along, across = (0, 2) if c["Axis"] == "X" else (2, 0)
            assert threshold["CanCollide"] and threshold["Attrs"].get("Level2_EntityGround") \
                and abs(low[across] - c["Cross"] + mouth_half) < .05 \
                and abs(high[across] - c["Cross"] - mouth_half) < .05 \
                and abs(low[1] - (end_y - 2)) < .05 and end_y - .05 <= high[1] <= end_y + 1.05 \
                and high[along] - low[along] >= 1.75 - .05 \
                and (low[along] <= end - collar["CollarDepth"] + .05 and high[along] >= end - .05
                     if end == c["From"] else low[along] <= end + .05
                     and high[along] >= end + collar["CollarDepth"] - .05), \
                f"corridor {c['Index']} {marker_name} threshold does not fill the collar bottom flush"
            if c["Variant"].startswith("Stair"):
                # The ramps climb evenly from collar to collar; half a stud inside
                # each mouth the walkable top meets the hall floor (pipes step up 1).
                ramps = [o for o in corridor_parts if " Ramp " in o["Name"] and o["CanCollide"]
                         and o["Attrs"].get("Level2_EntityGround")]
                assert ramps, f"stair {c['Index']} has no walkable ramp"
                mouth_z = exported["cf"][2]
                inside_z = mouth_z - .5 if mouth_z > 0 else mouth_z + .5
                base = end_y - model_cf[1]
                top = next((y/100 for y in range(int(base*100) + 210, int(base*100) - 100, -1)
                            if any(contains_part(o, cf_point(model_cf, (0, y/100, inside_z)), 0)
                                   for o in ramps)), None)
                assert top is not None and abs(top - base - (1 if c["Kind"] == "Narrow" else 0)) <= .5*rise/c["Length"] + .05                     and top + model_cf[1] - bounds(threshold)[1][1] <= 1.05,                     f"stair {c['Index']} {marker_name} ramp does not meet its walkable approach "                     f"(top {top}, base {base}, threshold {bounds(threshold)[1][1] - model_cf[1]})"
        lamp_marker = next(m for m in components[source]["markers"] if m["name"] == "LampLight")
        lamp = named(f"Level 2 Corridor Vault Light {c['Index']}", "Part")
        assert lamp["Parent"] == model["Id"]
        lamp_local = list(lamp_marker["cf"][:3])
        near(position(lamp), cf_point(model_cf, lamp_local))
        corridor_lights = [o for o in world_objects if o["Parent"] == lamp["Id"] and o["ClassName"] == "PointLight"]
        assert len(corridor_lights) <= 1, f"corridor {c['Index']} has duplicate lamps"
        for light in corridor_lights:
            assert light["Brightness"] == lamp_marker["attrs"]["Brightness"], \
                f"corridor {c['Index']} lamp brightness {light['Brightness']} differs from {source} export"
            assert light["Range"] == lamp_marker["attrs"]["Range"] and light["Shadows"] is False, \
                f"corridor {c['Index']} lamp range/shadows differ from {source} export"
        exported_region = components[source]["attrs"].get("waterRegion")
        if exported_region:
            water = record["Water"]
            assert any(region["CFrame"] == water["CFrame"] and region["Size"] == water["Size"] for region in regions)
            expected_size = list(exported_region["size"])
            near(point(water["Size"]), expected_size)
            region_cf = frame(water["CFrame"])
            near(region_cf[:3], cf_point(model_cf, exported_region["center"]))
            near(cf_vector(region_cf, (0, 0, 1)), cf_vector(model_cf, (0, 0, 1)))
            assert abs(region_cf[1] + point(water["Size"])[1] / 2
                       - (c["FromY"] + exported_region["surfaceY"])) < 1e-4
        else:
            assert "Water" not in record, f"dry corridor {c['Index']} created water"
        if c.get("DrainGroup"):
            drains = manifest["Drains"]
            drain = drains[c["DrainGroup"] - 1] if isinstance(drains, list) else drains[str(c["DrainGroup"])]
            water = drain["Water"]
            assert water == record["Water"] and c["Variant"] == "Wet"
            assert any(region["CFrame"] == water["CFrame"] and region["Size"] == water["Size"] for region in regions)
    assert len(manifest["Drains"]) == len(layout["PumpHalls"]) == 3

    for region in regions:
        label = region["Label"]
        low, high = bounds(region)
        if label.startswith(("Hall ", "Chamber ")):
            hall = halls[int(label.split()[1])]
            assert low[0] >= hall["MinX"] - .8 and high[0] <= hall["MaxX"] + .8 \
                and low[2] >= hall["MinZ"] - .8 and high[2] <= hall["MaxZ"] + .8 \
                and low[1] >= hall["FloorY"] - 7.5 \
                and high[1] <= hall["FloorY"] + hall["CeilingClass"] + 2, \
                f"{label} terrain water extends outside hall shell"
        elif label.startswith("Corridor "):
            corridor = corridors[int(label.split()[1])]
            along, across = (0, 2) if corridor["Axis"] == "X" else (2, 0)
            half, roof = (6, 12) if corridor["Kind"] == "Narrow" else (17, 32)
            assert low[along] >= corridor["From"] - .05 and high[along] <= corridor["To"] + .05 \
                and low[across] >= corridor["Cross"] - half - .05 \
                and high[across] <= corridor["Cross"] + half + .05 \
                    and low[1] >= min(corridor["FromY"], corridor["ToY"]) - 4 - .05 \
                and high[1] <= max(corridor["FromY"], corridor["ToY"]) + roof + .05, \
                f"{label} terrain water extends outside corridor shell"
        else:
            raise AssertionError(f"unexpected water region {label}")

    ground_boxes = [bounds(o) for o in world_objects if o["ClassName"] in {"Part", "MeshPart", "WedgePart"}
                    and o["CanCollide"] and o["Attrs"].get("Level2_EntityGround")]
    for h in halls.values():
        room = hall_models[h["Index"]]
        room_parts = parts(room)
        assert not any(o["Attrs"].get("Level2_KitComponent") in {"Porthole_R15", "Porthole_R6"}
                       for o in room_parts), f"hall {h['Index']} retains an oversized legacy porthole panel"
        connected = [c for c in corridors.values() if h["Index"] in (c["A"], c["B"])]
        openings = []
        for c in connected:
            other = halls[c["B"] if c["A"] == h["Index"] else c["A"]]
            if c["Axis"] == "X":
                side = "East" if h["Center"]["X"] < other["Center"]["X"] else "West"
                wall_at = h["MaxX"] if side == "East" else h["MinX"]
            else:
                side = "South" if h["Center"]["Z"] < other["Center"]["Z"] else "North"
                wall_at = h["MaxZ"] if side == "South" else h["MinZ"]
            openings.append((side, c["Cross"], wall_at, c))
            assert abs((c["From"] if side in {"East", "South"} else c["To"]) - wall_at) < .01, \
                f"hall {h['Index']} {side} corridor {c['Index']} mouth misses its wall plane"
            assert abs((c["FromY"] if side in {"East", "South"} else c["ToY"]) - h["FloorY"]) < .01, \
                f"hall {h['Index']} {side} corridor {c['Index']} mouth differs from the hall floor height"
        # F4-C (R3, the 'curb' of owner image 4): a narrow pipe's threshold stands floor+1 and reaches 4 studs
        # into the room; walking its centre line inward, no riser between ground samples may exceed .6
        # (threshold, mouth step, then the deck, dry floor or chamber ledge).
        for side, cross, wall_at, c in openings:
            if c["Kind"] != "Narrow":
                continue
            sign, axis = (1 if side in {"West", "North"} else -1), (0 if side in {"East", "West"} else 2)
            previous = None
            for k in range(30 if h["Role"] == "Small" else 33):    # a chamber ledge ends 8 from the boundary
                p = [cross, 0, cross]
                p[axis] = wall_at + sign * (.25 + .25 * k)
                tops = [high[1] for low, high in ground_boxes
                        if low[0] <= p[0] <= high[0] and low[2] <= p[2] <= high[2]
                        and h["FloorY"] - 1 <= high[1] <= h["FloorY"] + 1.2]
                assert tops, f"hall {h['Index']} {h['Type']} {side} pipe {c['Index']} mouth has no ground {.25 + .25 * k} in"
                if previous is not None:
                    assert abs(max(tops) - previous) <= .6 + 1e-6, \
                        f"hall {h['Index']} pipe {c['Index']} mouth riser {max(tops) - previous:.3f} at {.25 + .25 * k} in"
                previous = max(tops)
        if h["Role"] == "Small":
            plugs = [o for o in room_parts if o["Attrs"].get("SocketPlug")]
            original = sum(bool(o.get("attrs", {}).get("SocketPlug")) for o in components[h["Prefab"]]["parts"])
            assert len(plugs) == original - len(connected), f"chamber {h['Index']} socket plugs not removed exactly"
            assert not any("Corner Seal" in o["Name"] for o in room_parts)
            curved = [o for o in room_parts if "Room Curved Side" in o["Name"]]
            assert len(curved) == 16 and all(o["CanCollide"] for o in curved), \
                f"chamber {h['Index']} lost its authored curved-side collision"
            socket_count = sum(m["name"] == "Socket" for m in components[h["Prefab"]]["markers"])
            cove_count = sum(o["Attrs"].get("Level2_KitComponent") == "ChamberSocketCove" for o in room_parts)
            stop_count = sum(o["Attrs"].get("Level2_KitComponent") == "ChamberSocketStops" for o in room_parts)
            assert (cove_count, stop_count) == (socket_count-len(connected), len(connected)), \
                f"chamber {h['Index']} socket coves/stops do not match its open plugs"
            for side, cross, wall_at, c in openings:
                record = corridor_records[c["Index"] - 1] if isinstance(corridor_records, list) else corridor_records[str(c["Index"])]
                pipe = ref(record["Model"], "Model")
                assert pipe["Attrs"].get("Level2_KitComponent", "").startswith("Pipe_"), \
                    f"chamber {h['Index']} socket {c['Index']} lacks its connected pipe collar"
                pivot = frame(pipe["WorldPivot"])
                assert abs(pivot[0 if c["Axis"] == "X" else 2] - (c["From"] + c["To"]) / 2) < .01
                assert abs(pivot[2 if c["Axis"] == "X" else 0] - cross) < .01
            for plug in plugs:
                px, _, pz = position(plug)
                for side, cross, wall_at, _ in openings:
                    across, actual = (pz, px) if side in {"East", "West"} else (px, pz)
                    assert not (abs(across - cross) < 6 and abs(actual - wall_at) < 2), \
                        f"chamber {h['Index']} retains a connected socket plug"
            continue

        check_hall_shell(h, room_parts, openings, components)
        basin = next((o for o in room_parts if o["Name"] == f"Level 2 Hall Water Floor {h['Index']}"), None)

        def floor_top(x, z, basin=basin):
            """Top of the (tilted) basin floor Part at (x, z): its top-face plane."""
            if basin is None:
                return h["FloorY"]
            cf = frame(basin["CFrame"])
            n = cf_vector(cf, (0, 1, 0))
            p0 = cf_point(cf, (0, basin["Size"]["Y"] / 2, 0))
            return p0[1] - (n[0] * (x - p0[0]) + n[2] * (z - p0[2])) / n[1]
        for step in room_parts:
            # ANALYSIS F2+F4 check 5 (R1 review): every pool-step top lies between the deck top and the local
            # basin floor, at least .1 above the floor under its whole tread: no lip on the floor, none buried.
            kit_name = step["Attrs"].get("Level2_KitComponent", "")
            if not (kit_name.startswith("PoolSteps_") and kit_name != "PoolSteps_Curved_Landing"
                    and step["CanCollide"] and " Ground" in step["Name"]):
                continue
            low, high = bounds(step)
            under = max(floor_top(x, z) for x in (low[0], high[0]) for z in (low[2], high[2]))
            assert under + .1 - 1e-3 <= high[1] <= h["FloorY"] + DECK_TOP + 1e-3, \
                f"hall {h['Index']} {kit_name} {step['Name']} top {high[1] - h['FloorY']:.3f} vs floor " \
                f"{under - h['FloorY']:.3f} (F2+F4 check 5)"
        for side, cross, wall_at, c in openings:
            approach = (min(wall_at, wall_at - 38), max(wall_at, wall_at - 38), cross - 15, cross + 15) \
                if side == "East" else (wall_at, wall_at + 38, cross - 15, cross + 15) if side == "West" \
                else (cross - 15, cross + 15, min(wall_at, wall_at - 38), max(wall_at, wall_at - 38)) \
                if side == "South" else (cross - 15, cross + 15, wall_at, wall_at + 38)
            if h["Type"] in {"Arrival", "PumpHall"} or h["PoolType"] == "Dry" and h["Type"] != "PaddlingRoom":
                # A raised strip in the 32x30 spawn grid breaks its flat apron.
                # The continuous dry hall floor is the correct route to doors.
                dry_floor = next(o for o in room_parts if o["Name"] == f"Level 2 Hall Floor {h['Index']}")
                low, high = bounds(dry_floor)
                assert dry_floor["Attrs"].get("Level2_EntityGround") and abs(high[1] - (h["FloorY"]-.02)) < .01
                # The approach is only required inside the room: a door 12 from a corner has 3 studs of its
                # 30-wide approach beyond the wall (R3: seed 20261003 PumpHall 42, correct geometry).
                inner = (max(approach[0], h["MinX"] + 1.75), min(approach[1], h["MaxX"] - 1.75),
                         max(approach[2], h["MinZ"] + 1.75), min(approach[3], h["MaxZ"] - 1.75))
                assert low[0] <= inner[0] and high[0] >= inner[1]
                assert low[2] <= inner[2] and high[2] >= inner[3]
            else:
                assert any(o["Attrs"].get("Level2_EntityGround") and o["CanCollide"]
                           and o["Attrs"].get("Level2_KitComponent", "").startswith(("Walkway_", "PoolSteps_"))
                           and (lambda low, high: low[0] < approach[1] and high[0] > approach[0]
                                and low[2] < approach[3] and high[2] > approach[2])(*bounds(o))
                            for o in room_parts), f"hall {h['Index']} {side} opening {c['Index']} lacks walkway or steps"
                if True:  # every flooded hall, kids rooms included (their fallback is the straight stair)
                    # The exported straight step grounds descend in 4-stud
                    # intervals along local -Z. Their rotation must point
                    # that direction into the hall from every wall.
                    # R2 6: two doors near one corner may not stack their stairs into each other; a door
                    # without a stair is legal only where its 12x12 stair would overlap another one's.
                    if not any(step["Name"] == "Step Ground 1" and step["Attrs"].get("Level2_KitComponent", "")
                               .startswith("PoolSteps_Straight12") and abs(position(step)[2 if side in {"East", "West"} else 0]
                                                                  - cross) < .1 for step in room_parts):
                        sign = 1 if side in {"North", "West"} else -1
                        n0, n1 = sorted((wall_at + sign * 11.25, wall_at + sign * 23.25))
                        would = ((cross - 6, cross + 6), (n0, n1)) if side in {"North", "South"} \
                            else ((n0, n1), (cross - 6, cross + 6))
                        stairs = [bounds(o) for o in room_parts
                                  if o["Attrs"].get("Level2_KitComponent", "").startswith("PoolSteps_")]
                        assert any(low[0] < would[0][1] and would[0][0] < high[0]
                                   and low[2] < would[1][1] and would[1][0] < high[2] for low, high in stairs), \
                            f"hall {h['Index']} {side} opening {c['Index']} needs straight step 1"
                        continue
                    # R1 review (ANALYSIS F2+F4 check 5): the stair is the kit's first n steps, n the most whose
                    # tops stay .1 above the basin floor under their treads (checked for every step below).
                    kit_name = next(step["Attrs"]["Level2_KitComponent"] for step in room_parts
                                    if step["Name"] == "Step Ground 1" and step["Attrs"].get("Level2_KitComponent", "")
                                    .startswith("PoolSteps_Straight12")
                                    and abs(position(step)[2 if side in {"East", "West"} else 0] - cross) < .1
                                    and abs(position(step)[0 if side in {"East", "West"} else 2] - wall_at) < 30)
                    count = 3 if kit_name == "PoolSteps_Straight12" else int(kit_name.rsplit("_", 1)[1])
                    step_depths = []
                    for number in range(1, count + 1):
                        candidates = []
                        for step in room_parts:
                            if step["Name"] != f"Step Ground {number}" or \
                                    step["Attrs"].get("Level2_KitComponent") != kit_name:
                                continue
                            px, _, pz = position(step)
                            across, normal = (pz, px) if side in {"East", "West"} else (px, pz)
                            inward = (normal - wall_at) if side in {"North", "West"} else (wall_at - normal)
                            if abs(across - cross) < .1 and abs(inward) < 30:
                                candidates.append((step, inward))
                        assert len(candidates) == 1, \
                            f"hall {h['Index']} {side} opening {c['Index']} needs straight step {number}"
                        step, inward = candidates[0]
                        assert step["CanCollide"] and step["CanQuery"] and step["Attrs"].get("Level2_EntityGround"), \
                            f"hall {h['Index']} opening {c['Index']} step {number} is not walkable"
                        low, high = bounds(step)
                        nearest = ((low[2] - wall_at) if side == "North" else
                                   (wall_at - high[2]) if side == "South" else
                                   (low[0] - wall_at) if side == "West" else
                                   (wall_at - high[0]))
                        assert nearest >= -.1, \
                            f"hall {h['Index']} {side} opening {c['Index']} step {number} crosses the wall"
                        assert abs(high[1] - (h["FloorY"] + DECK_TOP - STEP_RISE * number)) < .1, \
                            f"hall {h['Index']} opening {c['Index']} step {number} has wrong descent height"
                        step_depths.append(inward)
                    assert all(abs(step_depths[i] - step_depths[i - 1] - 4) < .1 for i in range(1, count)), \
                        f"hall {h['Index']} {side} opening {c['Index']} steps do not descend inward"
                    if count < 3:
                        # Maximal: one more step (top STEP_RISE lower, the next 4 studs in) would meet the floor.
                        sign = 1 if side in {"North", "West"} else -1
                        # LATTICE_SPEC C11: tread k's ground spans 11.0 + 4(k-1) .. 15.0 + 4(k-1) from the boundary.
                        n0, n1 = wall_at + sign * (11 + 4 * count), wall_at + sign * (15 + 4 * count)
                        corners = [(n, a) if side in {"East", "West"} else (a, n) for n in (n0, n1)
                                   for a in (cross - 6, cross + 6)]
                        assert h["FloorY"] + DECK_TOP - STEP_RISE * (count + 1) < max(floor_top(x, z) for x, z in corners) + .1, \
                            f"hall {h['Index']} {side} opening {c['Index']} stair stops before the floor needs it"

        dressing = [o for o in descendants(room) if o["ClassName"] == "Model"
                    and o["Attrs"].get("Level2_Dressing") is True]
        obstacles = []
        for model in dressing:
            for item in parts(model):
                if item["ClassName"] != "Part" or not item["CanCollide"]:
                    continue  # Imported mesh bounds include empty space around authored curves.
                low, high = bounds(item)
                if low[1] < h["FloorY"] + 5.88 and high[1] > h["FloorY"] + .18:
                    obstacles.append((item, low, high))
        if h.get("Swerve"):
            # F9 (WP8, check 3): the swerve skin's wall, deck and cove colliders keep the same lanes, approaches,
            # mouths and spokes as the dressing (only the d=0 straights stand where today's ring deck does).
            for item in room_parts:
                if item["ClassName"] == "Part" and item["CanCollide"] and (
                        item["Attrs"].get("Level2_KitComponent", "").startswith("Swerve")
                        or item["Name"].startswith(("Level 2 Swerve ", "Level 2 Run Swerve "))):
                    low, high = bounds(item)
                    if low[1] < h["FloorY"] + 5.88 and high[1] > h["FloorY"] + .18:
                        obstacles.append((item, low, high))
        cx, cz = h["Center"]["X"], h["Center"]["Z"]
        for item, low, high in obstacles:
            assert high[0] <= cx - 17 or low[0] >= cx + 17, \
                f"hall {h['Index']} dressing {item['Name']} enters the Z centre lane"
            assert high[2] <= cz - 17 or low[2] >= cz + 17, \
                f"hall {h['Index']} dressing {item['Name']} enters the X centre lane"
            for side, cross, wall_at, c in openings:
                if side in {"East", "West"}:
                    inner = wall_at - 38 if side == "East" else wall_at + 38
                    assert high[0] <= min(wall_at, inner) or low[0] >= max(wall_at, inner) \
                        or high[2] <= cross - 15 or low[2] >= cross + 15, \
                        f"hall {h['Index']} dressing {item['Name']} enters {side} door approach {c['Index']}"
                    inner = wall_at - 8 if side == "East" else wall_at + 8
                    assert high[0] <= min(wall_at, inner) or low[0] >= max(wall_at, inner) \
                        or high[2] <= cross - 17 or low[2] >= cross + 17, \
                        f"hall {h['Index']} dressing {item['Name']} enters corridor mouth {c['Index']}"
                else:
                    inner = wall_at - 38 if side == "South" else wall_at + 38
                    assert high[2] <= min(wall_at, inner) or low[2] >= max(wall_at, inner) \
                        or high[0] <= cross - 15 or low[0] >= cross + 15, \
                        f"hall {h['Index']} dressing {item['Name']} enters {side} door approach {c['Index']}"
                    inner = wall_at - 8 if side == "South" else wall_at + 8
                    assert high[2] <= min(wall_at, inner) or low[2] >= max(wall_at, inner) \
                        or high[0] <= cross - 17 or low[0] >= cross + 17, \
                        f"hall {h['Index']} dressing {item['Name']} enters corridor mouth {c['Index']}"
        if h["Type"] == "PaddlingRoom":
            foam = named(f"Level 2 Pool Foam Spawn {h['Index']}", "Part")
            fx, _, fz = position(foam)
            for item, low, high in obstacles:
                assert high[0] <= fx - 4 or low[0] >= fx + 4 or high[2] <= fz - 4 or low[2] >= fz + 4, \
                    f"hall {h['Index']} dressing {item['Name']} enters Pool Foam spawn pocket"
            # F4-D (R2 6, R3): each curved stair lies inside its room, no two overlap, and the half disc r < 10
            # round its pivot is deck at deck-top height (the deck is its landing: no pit in front of a door).
            # Each column stays off the visible rings (F4-F).
            stairs = [o for o in room_parts if o["ClassName"] == "MeshPart"
                      and o["Attrs"].get("Level2_KitComponent") in ("PoolSteps_Curved", "PoolSteps_Curved_1")]
            assert stairs, f"PaddlingRoom {h['Index']} has no curved stair"
            pivots = []
            for stair in stairs:
                chunk = components[stair["Attrs"]["Level2_KitComponent"]]["meshRecords"][0]["center"]
                low, high = bounds(stair)
                # (its buried ends reach the deck's wall edge, .5 into the wall slab)
                assert low[0] >= h["MinX"] + 1.2 and high[0] <= h["MaxX"] - 1.2 \
                    and low[2] >= h["MinZ"] + 1.2 and high[2] <= h["MaxZ"] - 1.2, \
                    f"PaddlingRoom {h['Index']} curved stair leaves the room"
                cf = frame(stair["CFrame"])
                pivot = cf_point(cf, tuple(-v for v in chunk))
                into, along_wall = cf_vector(cf, (1, 0, 0)), cf_vector(cf, (0, 0, 1))
                for other in pivots:
                    assert math.hypot(other[0] - pivot[0], other[2] - pivot[2]) >= 44 - .05, \
                        f"PaddlingRoom {h['Index']} curved stairs overlap"
                pivots.append(pivot)
                for x in (1, 3, 5, 7, 9):
                    for z in range(-9, 10):
                        if x * x + z * z >= 9.8 ** 2:
                            continue
                        p = tuple(pivot[k] + into[k] * x + along_wall[k] * z for k in range(3))
                        assert any(low[0] <= p[0] <= high[0] and low[2] <= p[2] <= high[2]
                                   and abs(high[1] - (h["FloorY"] + DECK_TOP)) < .02 for low, high in ground_boxes), \
                            f"PaddlingRoom {h['Index']} curved stair landing has no deck at local ({x}, {z})"
                for item, low, high in obstacles:
                    ring = [tuple(pivot[k] + into[k] * x + along_wall[k] * z for k in range(3))
                            for x in range(10, 23, 2) for z in range(-22, 23, 2) if 10 <= math.hypot(x, z) <= 22]
                    assert not any(low[0] < q[0] < high[0] and low[2] < q[2] < high[2] for q in ring), \
                        f"hall {h['Index']} dressing {item['Name']} stands in a curved stair"

        sky = [o for o in room_parts if o["Name"].startswith(f"Level 2 Open Sky {h['Index']}.")]
        assert all(not o["CanCollide"] and not o["CanQuery"] for o in sky)
        caps = [o for o in room_parts if o["Name"].startswith("Level 2 Sky Cap ")]
        assert len(caps) == len(sky), f"hall {h['Index']} needs one sky cap per opening"
        opening_lights = [o for o in descendants(room) if o["ClassName"] == "SpotLight"
                          and objects[o["Parent"]]["Name"].startswith("Level 2 Opening Light")]
        assert len(opening_lights) == len(sky), f"hall {h['Index']} needs daylight under every opening"
        for light in opening_lights:
            assert (light["Face"], light["Range"], light["Angle"], light["Brightness"]) == \
                ("NormalId.Bottom", 60, 70, 3), f"hall {h['Index']} opening light settings changed"
        if h["Type"] in {"BigPool", "Arrival"}:
            assert not sky, f"hall {h['Index']} has an unplanned roof opening"
        else:
            assert 1 <= len(sky) <= 3, f"hall {h['Index']} needs 1-3 open sky light wells"
        if h["Type"] in {"SpiralWell", "ExitHall"}:
            expected_kind = "SpiralWell" if h["Type"] == "SpiralWell" else "ExitHall"
            assert any(mark["Attrs"].get("Level2_OpenSkyKind") == expected_kind for mark in sky), \
                f"hall {h['Index']} {h['Type']} has no matching sky opening"
        wells = [o for o in descendants(room) if o["ClassName"] == "Model"
                 and o["Attrs"].get("Level2_KitComponent", "").startswith(("LightWell_", "SpiralStairWell_"))]
        # Spiral wells carry no opening of their own; their LightWell_R12 above them does (ExitSkylight retired).
        assert len(sky) >= sum(w["Attrs"]["Level2_KitComponent"].startswith("LightWell_") for w in wells),             f"hall {h['Index']} has a covered light well"
        overhead = [o for o in room_parts if o["Name"].startswith("Level 2 Overhead Tile") or "Roof Collider" in o["Name"]]
        for well in wells:
            wx, _, wz = frame(well["WorldPivot"])[:3]
            assert any(math.hypot(position(mark)[0] - wx, position(mark)[2] - wz) < 1
                       for mark in sky), f"{well['Name']} has no open-sky marker"
            component = well["Attrs"]["Level2_KitComponent"]
            if component.startswith("LightWell_"):
                panel = components[component]["attrs"]["PanelSize"]
                assert abs(frame(well["WorldPivot"])[1] - h["FloorY"] - h["CeilingClass"]) < .01
                assert any(abs(position(cap)[0] - wx) < .01 and abs(position(cap)[2] - wz) < .01
                           and abs(point(cap["Size"])[0] - panel) < .01
                           and abs(point(cap["Size"])[2] - panel) < .01
                           and cap["CanCollide"] and not cap["CanQuery"] and not cap["CanTouch"]
                           and cap["Transparency"] == 1
                           for cap in caps), f"{well['Name']} has no full cut sky cap"
        for mark in sky:
            radius = mark["Attrs"].get("Level2_OpenSkyRadius")
            assert isinstance(radius, (int, float)) and radius >= 6
            mx, _, mz = position(mark)
            for dx, dz in ((0, 0), (.7, 0), (-.7, 0), (0, .7), (0, -.7)):
                x, z = mx + dx * radius, mz + dz * radius
                for ceiling in overhead:
                    low, high = bounds(ceiling)
                    assert not (low[0] < x < high[0] and low[2] < z < high[2]), \
                        f"hall {h['Index']} {mark['Name']} covered by {ceiling['Name']}"
        if h.get("PumpIndex"):
            assert any(mark["Attrs"].get("Level2_OpenSkyKind") == "PumpHall"
                       and math.hypot(position(mark)[0] - cx, position(mark)[2] - cz) < 1
                       for mark in sky), f"pump {h['PumpIndex']} lacks its open sky shaft"

    root_markers = {o["Name"]: o for o in objects.values() if o["Name"] in {"Elevator", "ElevatorSpawn", "MazeStart", "EntityStart"} and not inside(o)}
    assert set(root_markers) == {"Elevator", "ElevatorSpawn", "MazeStart", "EntityStart"}
    for marker_name in root_markers:
        assert ref(manifest["Arrival"][marker_name])["Id"] == root_markers[marker_name]["Id"]
    for marker in root_markers.values():
        assert marker["Attrs"].get("Level2_CompatibilityMarker") is True
    elevator = root_markers["Elevator"]
    assert elevator["ClassName"] == "Model"
    assert {o["Name"] for o in objects.values() if o["Parent"] == elevator["Id"]} >= {"DoorL", "DoorR"}
    spawn = ref(manifest["Arrival"]["ElevatorSpawn"], "Part")
    assert spawn["Id"] == root_markers["ElevatorSpawn"]["Id"]
    assert abs(position(spawn)[1] - layout["Arrival"]["FloorY"] - .1) < 1e-4
    arrival = layout["Arrival"]
    assert arrival["PoolType"] == "Dry"
    concourse = named("Level 2 Arrival Concourse", "Model")
    assert concourse["Parent"] == geometry["Id"]
    apron = next((o for o in parts(concourse) if o["Name"] == "Level 2 Arrival Clear Apron"), None)
    assert apron is not None and apron["CanCollide"] and apron["CanQuery"]
    assert apron["Attrs"].get("Level2_EntityGround") is True
    near(point(apron["Size"]), (32,1,30))
    assert abs(position(apron)[1]+.5-arrival["FloorY"]-.02) < 1e-4, "arrival apron top clears the hall floor"
    spawn_cf, apron_cf = frame(spawn["CFrame"]), frame(apron["CFrame"])
    forward = cf_vector(spawn_cf,(0,0,-1))
    side = cf_vector(spawn_cf,(1,0,0))
    near(cf_vector(apron_cf,(0,0,-1)),forward)
    near(tuple(cf_point(apron_cf,(0,0,15))[i] for i in (0,2)),
         tuple(position(spawn)[i] for i in (0,2)))
    # These are the Round Adapter's 8 columns and seven forward rows. Ignore
    # floor slabs below the feet; every upper collider must clear the body box.
    obstructors = []
    for o in world_objects:
        if o["ClassName"] not in {"Part","MeshPart","WedgePart"} or not o["CanCollide"]:
            continue
        low, high = bounds(o)
        if high[1] > arrival["FloorY"]+.18 and low[1] < arrival["FloorY"]+5.88:
            obstructors.append((o,low,high))
    for row in range(7):
        for column in range(8):
            offset = (column-3.5)*4
            xyz = tuple(position(spawn)[i]+side[i]*offset+forward[i]*row*4 for i in range(3))
            for obstacle,low,high in obstructors:
                assert not (low[0] < xyz[0]+1.4 and high[0] > xyz[0]-1.4 and
                            low[2] < xyz[2]+1.4 and high[2] > xyz[2]-1.4), \
                    f"arrival row {row} column {column} obstructed by {obstacle['Name']}"
    assert components_in(concourse)["ArrivalDoor"] > 0, "Poolrooms arrival gate missing"
    # F4-L (R3): the story door stands on the back wall's inner face: its frame tucks at most .2 into the wall,
    # the iron leaf is wholly in front of it, nothing stands more than 1.0 proud, and the authored wall patches
    # (meant for a thinner wall) are gone.
    axis = max(range(3), key=lambda k: abs(forward[k]))
    direction = 1 if forward[axis] > 0 else -1
    back_boundary = {(0, 1): arrival["MinX"], (0, -1): arrival["MaxX"],
                     (2, 1): arrival["MinZ"], (2, -1): arrival["MaxZ"]}[(axis, direction)]
    face = back_boundary + direction * 1.75
    door_chunks = [o for o in parts(concourse) if o["Attrs"].get("Level2_KitComponent") == "ArrivalDoor"]
    assert door_chunks and not any(o["Name"].startswith("Level 2 Arrival Wall") for o in door_chunks)
    for chunk in door_chunks:
        low, high = bounds(chunk)
        depth = sorted(((low[axis] - face) * direction, (high[axis] - face) * direction))
        assert depth[0] >= -.2 and depth[1] <= 1.0, f"ArrivalDoor {chunk['Name']} sits {depth} off the wall face"
        if chunk["MaterialVariant"] == "PR Iron" or chunk["Material"] == "Material.Metal":
            assert depth[0] >= 0, f"ArrivalDoor leaf {chunk['Name']} is inside the wall"
    assert any(o["Material"] != "Material.Neon" and (lambda d: d[0] >= 0)(sorted(
        ((bounds(o)[0][axis] - face) * direction, (bounds(o)[1][axis] - face) * direction))) for o in door_chunks), \
        "no ArrivalDoor chunk stands wholly in front of the wall"
    assert not any(o["Name"] == "Level 2 Arrival Story Gate" for o in descendants(concourse))

    exit_data = manifest["Exit"]
    for key in ("Trigger", "Backstop", "SafeSpawn", "FlumeModel", "Mouth", "EndPosition", "StartPoint",
                "RoomEntry", "RoomFloorTop", "Door", "TransitionStart", "TransitionEnd", "TransitionLength",
                "FlumeBoundsCenter", "FlumeBoundsSize", "PathPoints", "BoreRadius", "Recycle", "HallWallGap"):
        assert key in exit_data, f"Exit.{key}"
    flume = ref(exit_data["FlumeModel"], "Model")
    assert flume["Name"] == "Level 2 Exit Flume" and exit_data["BoreRadius"] == 8
    assert flume["ModelStreamingMode"] == "ModelStreamingMode.Persistent"
    assert flume["Parent"] == geometry["Id"]
    for key in ("Level2_RecycleActive", "Level2_RecycleTriggerY", "Level2_RecycleDeltaY", "Level2_HelixCenterX", "Level2_HelixCenterZ", "Level2_HelixRadius", "Level2_FlumeBoreRadius"):
        assert key in flume["Attrs"]
    for attribute, field in (("Level2_RecycleTriggerY","TriggerY"),("Level2_RecycleDeltaY","DeltaY"),("Level2_HelixCenterX","CenterX"),("Level2_HelixCenterZ","CenterZ"),("Level2_HelixRadius","Radius")):
        assert flume["Attrs"][attribute] == exit_data["Recycle"][field]
    assert flume["Attrs"]["Level2_RecycleActive"] is True
    assert flume["Attrs"]["Level2_FlumeBoreRadius"] == 8
    assert flume["Attrs"]["Level2_HelixTopY"] == exit_data["Recycle"]["TopY"]
    assert flume["Attrs"]["Level2_HelixBottomY"] == exit_data["Recycle"]["BottomY"]
    mouth = ref(exit_data["Mouth"], "MeshPart")
    assert inside(mouth,flume["Id"]) and not mouth["CanCollide"] and not mouth["CanQuery"]
    assert mouth["Attrs"].get("Level2_KitComponent") == "ExitMouthTrim"
    assert len(exit_data["PathPoints"]) == 272
    assert exit_data["TransitionLength"] >= 2000 and exit_data["Recycle"]["Turns"] >= 3
    # Exit helix cannot yaw: controller recovery assumes world +X tangent at entry.
    points = exit_data["PathPoints"]
    near(point(exit_data["StartPoint"]),point(points[0]))
    near(point(exit_data["TransitionEnd"]),point(points[-1]))
    near(point(exit_data["RoomEntry"]),point(points[73]))
    assert exit_data["RoomFloorTop"] < point(exit_data["RoomEntry"])[1]
    assert point(exit_data["TransitionStart"])[0] < point(exit_data["TransitionEnd"])[0]
    door = ref(exit_data["Door"], "Part")
    near(point(exit_data["EndPosition"]),position(door))
    assert inside(door,flume["Id"])
    gap = exit_data["HallWallGap"]
    grand = layout["GrandSlideHall"]
    # LATTICE_SPEC 6 (HallWallGap): the exit wall's hole on the lattice, deckZ +- 9 x F+73..F+90.
    assert gap["width"] == 18
    near((gap["center"],),(grand["MinZ"]+42,))
    near((gap["bottom"],gap["top"]),(grand["FloorY"]+73,grand["FloorY"]+90))
    deck_z = grand["MinZ"]+42
    east = grand["MaxX"]
    near(point(exit_data["StartPoint"]),(east-2,grand["FloorY"]+81.2,deck_z),.001)
    near((position(mouth)[0],position(mouth)[2]),(east-2.03,deck_z),.1)
    exit_room = hall_models[grand["Index"]]
    deck = next(o for o in parts(exit_room) if o["Name"] == "Level 2 Exit Platform Deck")
    deck_low, deck_high = bounds(deck)
    assert abs(deck_high[0]-(east-2)) < .02 and abs(deck_high[1]-(grand["FloorY"]+74)) < .02
    assert abs(deck_high[1]-(point(exit_data["StartPoint"])[1]-7.2)) < .02
    platform = next(o for o in descendants(exit_room) if o["ClassName"] == "Model"
                    and o["Attrs"].get("Level2_KitComponent") == "ExitPlatform")
    spiral = next(o for o in descendants(exit_room) if o["ClassName"] == "Model"
                  and o["Attrs"].get("Level2_KitComponent") == "ExitSpiral")
    near(frame(platform["WorldPivot"])[:3],(east-36,grand["FloorY"],deck_z+10))
    near(frame(spiral["WorldPivot"])[:3],frame(platform["WorldPivot"])[:3])
    stair_center = (east-81.6,deck_z+17)
    floor = next(o for o in parts(exit_room) if o["Name"] == f"Level 2 Hall Water Floor {grand['Index']}")
    floor_cf = frame(floor["CFrame"])
    up = (floor_cf[4],floor_cf[7],floor_cf[10])
    floor_top = tuple(floor_cf[i]+up[i]*point(floor["Size"])[1]/2 for i in range(3))
    floor_y = floor_top[1]-(up[0]*(stair_center[0]-floor_top[0])
                             +up[2]*(stair_center[1]-floor_top[2]))/up[1]
    assert grand["FloorY"]-4 <= floor_y <= grand["FloorY"]+1/3, \
        "exit spiral entry must emerge through the actual hall floor"
    well = next(o for o in descendants(exit_room) if o["ClassName"] == "Model"
                and o["Attrs"].get("Level2_KitComponent") == "LightWell_R14")
    near(frame(well["WorldPivot"])[:3],(east-36,grand["FloorY"]+grand["CeilingClass"],deck_z+10))
    # The generic ceilingShell caps the exit skylight like every other opening: exactly one cap.
    caps_here = [o for o in parts(exit_room) if o["Name"].startswith("Level 2 Sky Cap")
                 and abs(position(o)[0]-(east-36)) < .01 and abs(position(o)[2]-(deck_z+10)) < .01]
    assert len(caps_here) == 1, f"exit skylight needs exactly one sky cap, found {len(caps_here)}"
    cap = caps_here[0]
    assert cap["CanCollide"] and not cap["CanQuery"] and cap["Attrs"].get("Level2_NoEntityGround")
    near(position(cap),(east-36,grand["FloorY"]+grand["CeilingClass"]+2,deck_z+10))
    near(point(cap["Size"]),(32,1,32))
    envelope_center = point(exit_data["FlumeBoundsCenter"])
    envelope_size = point(exit_data["FlumeBoundsSize"])
    for p in points:
        xyz = point(p)
        assert all(abs(xyz[i]-envelope_center[i]) <= envelope_size[i]/2-8 for i in range(3)), \
            "exit flume envelope does not contain its path with bore padding"
    for key,name in (("Trigger","Level 2 Exit Completion Beam"),("Backstop","Level 2 Exit Completion Backstop")):
        sensor = ref(exit_data[key], "Part")
        assert sensor["Name"] == name and inside(sensor,flume["Id"])
        assert sensor["Attrs"].get("Level2_ExitCompletionSensorThickness") == 9
        near(point(sensor["Size"]), (9,18,18))
    near((points[92]["X"]-points[91]["X"],points[92]["Z"]-points[91]["Z"]), (10.034732473695, -0.525898044646), .001)

    tube = slides["slides"]["ExitFlume_Tube"]
    relocated = {"Level2_RecycleTriggerY", "Level2_HelixCenterX", "Level2_HelixCenterZ",
                 "Level2_HelixTopY", "Level2_HelixBottomY"}
    assert all(flume["Attrs"].get(k) == v for k,v in tube["attrs"].items()
               if k not in relocated and not isinstance(v,list)), "exported tube attrs"
    contents = descendants(flume)
    anchor = frame(flume["WorldPivot"])
    near(anchor[:3],(east+23,grand["FloorY"]+81.2,deck_z))
    for component in ("ExitTubeVisual", "ExitTubeVisual_02", "ExitTubeVisual_03",
                      "ExitTubeVisual_04", "ExitTubeVisual_05", "ExitCollar", "ExitMouthTrim"):
        visuals = [o for o in contents if o["ClassName"] == "MeshPart"
                   and o["Attrs"].get("Level2_KitComponent") == component]
        assert visuals and all(not o["CanCollide"] and not o["CanQuery"]
                               and o["Transparency"] == 0 for o in visuals), f"missing opaque {component}"
    marks = sorted((m for name in ("ExitTubeVisual", "ExitTubeVisual_02", "ExitTubeVisual_03",
                                  "ExitTubeVisual_04", "ExitTubeVisual_05")
                    for m in components[name]["markers"] if m["name"] == "BoreSegment"),
                   key=lambda m: m["attrs"]["Index"])
    floors = [o for o in contents if o["Name"].startswith("Level 2 Exit Flume Collision Floor ")]
    assert len(marks) == len(floors) == 271
    by_floor = {o["Name"]: o for o in floors}
    assert len(by_floor) == 271
    for index, mark in enumerate(marks, 1):
        attrs = mark["attrs"]
        assert attrs["Index"] == index
        name = f"Level 2 Exit Flume Collision Floor {index:03d}"
        piece = by_floor[name]
        assert piece["ClassName"] == "MeshPart" and piece["FixtureComponent"] == attrs["Template"]
        assert piece["CollisionFidelity"] == "CollisionFidelity.PreciseConvexDecomposition"
        assert piece["CanCollide"] and piece["CanQuery"] and not piece["CanTouch"]
        assert piece["Transparency"] == 1 and not piece["CastShadow"]
        near(point(piece["Size"]),tuple(attrs["Size"]),.001)
        near(position(piece),cf_point(anchor,mark["cf"][:3]),.001)
        near(point(piece["Attrs"]["Level2_SlideDirection"]),
             cf_vector(frame(piece["CFrame"]),(0,0,-1)),.001)
        for key in ("Level2_SlideCollision", "Level2_SlideFloor", "Level2_NoEntityGround"):
            assert piece["Attrs"].get(key) is True
        assert piece["Attrs"].get("Level2_OneWayExit") is (attrs["OneWay"] is True)
    forbidden = ("Entry Support", "Entry Collision Floor", "Exit Portal", "Exit Lead Tile")
    assert not any(any(word in o["Name"] for word in forbidden) for o in contents)

    lights = [o for o in world_objects if o["ClassName"] in {"PointLight", "SurfaceLight", "SpotLight"}]
    assert len(lights) <= 96, f"light budget exceeded: {len(lights)}"
    assert len([o for o in lights if o.get("Shadows")]) <= 6
    assert world["Attrs"].get("Level2_KitLightCount") == len(lights)
    assert not byname.get("Level 2 Slide Halls"), "old decorative slide folder remains"
    assert build["Yields"] > 0, "builder must periodically yield"
    forbidden_names = ("Level 2 Lounger Seat", "Beach Ball", "Pool Noodle", "Pool Raft", "Pool Float Ring",
                       "Level 2 Hall Band ", "Level 2 Hall Dado ")
    forbidden_components = ("DoorArch30", "DoorService12", "Coping", "Gutter", "Prop_", "PropCluster_",
                            "Small_", "SlideHall", "GrandSlideHall", "GateStory", "OverheadRibs")
    exported_ground = {(name, record["name"])
                       for name, component in components.items()
                       for record in component["parts"] + component["colliders"] if record.get("ground")}
    for o in world_objects:
        assert not any(o["Name"].startswith(prefix) for prefix in forbidden_names), o["Name"]
        component = o["Attrs"].get("Level2_KitComponent") or o.get("FixtureComponent") or ""
        assert not component.startswith(forbidden_components), f"old visual component remains: {component}"
        if o["ClassName"] not in {"Part", "MeshPart", "WedgePart"}:
            continue
        if (o.get("FixtureComponent"), o["Name"]) in exported_ground and o["CanCollide"]:
            assert o["Attrs"].get("Level2_EntityGround") is True, \
                f"exported ground collider lost its ground flag: {o['Name']}"
        if o.get("FixtureKind") in {"part", "collider"} and o["CanCollide"]:
            assert bool(o["Attrs"].get("Level2_EntityGround")) == o["FixtureGround"], \
                f"kit collider ground tag differs from exported flag: {o['Name']}"
        assert o["CollisionGroup"] == "Default", o["Name"]
        assert not o["MaterialVariant"] or o["MaterialVariant"] in {"PR Tile", "PR Tile Aqua", "PR Iron"},             f"{o['Name']}: unknown MaterialVariant {o['MaterialVariant']!r}"
        # Step S (replaces the retired "PR Tile Mesh" twin rule): a MaterialVariant on a MeshPart ignores its UVs, so
        # no MeshPart may wear a tile variant; kit tile meshes draw it through a SurfaceAppearance (check_tile_surfaces).
        if o["MaterialVariant"].startswith("PR Tile"):
            assert o["ClassName"] != "MeshPart", f"{o['Name']}: MeshPart with {o['MaterialVariant']}"
        if (o["MaterialVariant"] in {"PR Tile", "PR Tile Aqua"} or o.get("FixtureTile")) and o["Transparency"] < .98:
            assert o["Material"] == "Material.SmoothPlastic"
            assert o["Color"] == {"R": 241/255, "G": 237/255, "B": 220/255, "$type": "Color3"}, o["Name"]
            assert abs(o["Reflectance"]-.06) < 1e-6, o["Name"]
        if any(word in o["Name"] for word in ("Ceiling", "Skylight", "Roof")):
            assert o["Attrs"].get("Level2_NoEntityGround") is True, f"roof pass trap: {o['Name']}"
            modifiers = [x for x in world_objects if x["Parent"] == o["Id"]
                         and x["ClassName"] == "PathfindingModifier"]
            assert len(modifiers) == 1 and modifiers[0]["Label"] == "Level2Roof"
            assert modifiers[0]["PassThrough"] is False
        if o["ClassName"] == "MeshPart" and o["CanCollide"]:
            assert o["Attrs"].get("Level2_SlideCollision") is True, f"colliding non-slide mesh {o['Name']}"
        if o["ClassName"] == "MeshPart" and not o["CanCollide"]:
            assert not o["CanQuery"] and not o["CanTouch"], o["Name"]
        if o["Attrs"].get("Level2_SlideCollision"):
            assert o["Attrs"].get("Level2_NoEntityGround") is True, o["Name"]
            assert o["CanCollide"] and o["CanQuery"] and not o["CanTouch"] and not o["CastShadow"]
            assert o["Transparency"] == 1
            prop = o["CustomPhysicalProperties"]
            assert prop == {"Density": .7, "Friction": .05, "Elasticity": .05,
                            "FrictionWeight": 1, "ElasticityWeight": 1}
            if o["ClassName"] == "MeshPart":
                assert o["CollisionFidelity"] == "CollisionFidelity.PreciseConvexDecomposition"
            if o["Attrs"].get("Level2_SlideFloor"):
                cf, direction = frame(o["CFrame"]), point(o["Attrs"]["Level2_SlideDirection"])
                near(direction, (-cf[5], -cf[8], -cf[11]))
        if o["CanCollide"] and not o.get("FixtureKind") and not o["Attrs"].get("Level2_NoEntityGround") \
                and re.search(r"(Floor|Deck|Step|Landing|Ledge|Curb|Threshold|Tread)", o["Name"]):
            assert o["Attrs"].get("Level2_EntityGround") is True, \
                f"walkable collider lacks EntityGround: {o['Name']}"
            assert o["Anchored"]
    assert not any(o["Name"] == "Markers" for o in world_objects), "authoring markers must be consumed and destroyed"
    assert not any(o["Name"] in {"Level2BlenderKit", "SlideTemplates", "Components", "Data"}
                   for o in world_objects)

    category = Counter()
    for o in world_objects:
        name = o["Name"]
        if o["ClassName"] in {"PointLight", "SurfaceLight", "SpotLight"}:
            bucket = "lights"
        elif o["Attrs"].get("Level2_SlideCollision"):
            bucket = "slides"
        elif o["Parent"] in {nodes["Id"], navigation["Id"]}:
            bucket = "nodes"
        elif o["ClassName"] == "MeshPart":
            bucket = "meshes"
        elif o.get("FixtureKind") == "collider" or "Collider" in name:
            bucket = "colliders"
        elif o["ClassName"] in {"Part", "WedgePart"}:
            bucket = "shell parts"
        else:
            bucket = "other"
        category[bucket] += 1
    assert sum(category.values()) == len(world_objects)
    print(f"seed {build['RequestedSeed']} -> {layout['Seed']} attempt {layout['Attempt']}: "
          f"{len(world_objects)}/{WORLD_BUDGET} world descendants; "
          + ", ".join(f"{key}={category[key]}" for key in
                      ("shell parts", "meshes", "colliders", "slides", "nodes", "lights", "other"))
          + f"; hall types={dict(sorted(type_counts.items()))}; lights={len(lights)}/96")
    assert len(world_objects) <= WORLD_BUDGET, \
        f"Poolrooms world instance budget exceeded: {len(world_objects)} > {WORLD_BUDGET}"
    return category, len(world_objects)


def well_count(h):
    """Builder wellCount (F4-G): planned ceiling openings per hall."""
    if h["Role"] == "Small" or h["Type"] in {"BigPool", "Arrival"}:
        return 0
    if h["Type"] in {"PumpHall", "ExitHall", "PaddlingRoom", "SpiralWell"} or h.get("PumpIndex"):
        return 1
    return min(3, max(1, int(h["Area"] // 18000)))


def round_quota(layout):
    """Builder roundQuota (F4-A 2): the hall light budget (96 - tunnel lamps - 3 pump lamps - every planned
    ceiling opening's spot) split evenly over the map's BigPools."""
    pools = sum(h["Role"] != "Small" and h["Type"] == "BigPool" for h in layout["Halls"])
    tunnels = sum(c["Kind"] != "Narrow" for c in layout["Corridors"])
    openings = sum(well_count(h) for h in layout["Halls"])
    return (96 - tunnels - 3 - openings) // pools if pools else 0


def new_dressing_stats():
    return {"voids": Counter(), "columns": [], "signatures": defaultdict(list),
            "quadrants": defaultdict(Counter), "drainWall": [], "wells": defaultdict(list), "vault": [],
            "sigHalls": defaultdict(list), "poolLights": [], "oneSlot": Counter()}


DECK_GROUND = re.compile(r"^(Level 2 Run Deck |Level 2 Run Swerve Deck |Level 2 Corner Deck |Corner Deck Ground|Step Ground|Step \d+ Ground|Landing Ground|Ring Ground)")


def check_dressing(build, components, stats=None):
    """WP7 (ANALYSIS F8, F8 (count), F4-B/verticals, F4-H, F4-I/vault, F4-J, F4-lightround, F4-drain, F4-F,
    F4-walkway-band, F7 (VaultArcade)): the dressing oracle, exact numbers from the snapshot."""
    layout = build["Layout"]
    objects = {o["Id"]: o for o in build["Objects"]}
    halls = {h["Index"]: h for h in layout["Halls"]}
    children = defaultdict(list)
    for o in objects.values():
        children[o["Parent"]].append(o["Id"])

    def below(oid):
        out, stack = [], [oid]
        while stack:
            for c in children[stack.pop()]:
                out.append(objects[c])
                stack.append(c)
        return out

    def comp(o):
        return o["Attrs"].get("Level2_KitComponent") or ""

    def is_part(o):
        return o["ClassName"] in {"Part", "MeshPart", "WedgePart"}

    # Every collider a jump could land on: anything with a top face of 1 x 1 or more (the world audit's
    # check 03 rule), except the roof band itself.
    grounds_world = [(o, low, high) for o in objects.values() if is_part(o) and o.get("CanCollide")
                     and not any(k in o["Name"] for k in ("Sky Cap", "Roof Collider", "Overhead Tile", "Ceiling"))
                     for low, high in [bounds(o)] if high[0] - low[0] >= 1 and high[2] - low[2] >= 1]
    rooms = {o["Attrs"]["Level2_HallIndex"]: o for o in objects.values()
             if o["ClassName"] == "Model" and o["Attrs"].get("Level2_HallIndex") and o["Attrs"].get("Level2_Role") != "Small"}
    spirals_world = [o for o in objects.values() if o["ClassName"] == "Model" and comp(o).startswith("SpiralStairWell_")]
    assert len(spirals_world) <= 1, f"F8: {len(spirals_world)} spiral stair wells in one map (cap 1)"
    for index, room in rooms.items():
        h = halls[index]
        if h["Role"] == "Small":
            continue
        C = h["FloorY"] + h["CeilingClass"]
        inner = below(room["Id"])
        ps = [o for o in inner if is_part(o)]
        basin = next((o for o in ps if o["Name"] == f"Level 2 Hall Water Floor {index}"), None)

        def floor_top(x, z):
            if basin is None:
                return h["FloorY"] - .02
            cf = frame(basin["CFrame"])
            n = cf_vector(cf, (0, 1, 0))
            p0 = cf_point(cf, (0, basin["Size"]["Y"] / 2, 0))
            return p0[1] - (n[0] * (x - p0[0]) + n[2] * (z - p0[2])) / n[1]

        models = [o for o in inner if o["ClassName"] == "Model"]
        # ---- F8: the one spiral, unscaled, top tread C-14, its own flush R12 well over the column.
        spirals = [m for m in models if comp(m).startswith("SpiralStairWell_")]
        if h["Type"] == "SpiralWell":
            assert len(spirals) == 1, f"SpiralWell {index} has {len(spirals)} spiral stairs"
        for m in spirals:
            name = comp(m)
            assert name == f"SpiralStairWell_H{h['CeilingClass']}", f"F8: {name} in a {h['CeilingClass']} hall"
            assert m["Attrs"].get("Level2_HorizontalScale") == 1, "F8: a spiral must be unscaled"
            px, py, pz = frame(m["WorldPivot"])[:3]
            assert abs(py - h["FloorY"]) < .01, "F8: spiral pivot off the floor plane"
            for o in below(m["Id"]):
                if o["ClassName"] == "MeshPart":
                    native = components[name]["meshRecords"][0]["size"]
                    assert all(abs(a - b) < 1e-3 for a, b in zip(point(o["Size"]), native)), "F8: spiral mesh rescaled"
            tops = [bounds(o)[1][1] for o in below(m["Id"]) if is_part(o) and o["Name"].startswith("Stair Ground")]
            assert tops and abs(max(tops) - (C - 14)) < .01, f"F8: spiral top tread {max(tops) - C:+.2f} from the ceiling, not -14"
            wells = [w for w in models if comp(w) == "LightWell_R12"
                     and math.hypot(frame(w["WorldPivot"])[0] - px, frame(w["WorldPivot"])[2] - pz) < .01]
            assert len(wells) == 1, "F8: the spiral column must rise into its own LightWell_R12"
        # ---- F4-B/F4-verticals/F4-H: verticals stand on the basin (from -4) and reach the ceiling.
        for o in ps:
            name = comp(o)
            if not (name.startswith(("Column_", "VaultPier")) or name.startswith("SpiralStairWell_") and o["ClassName"] == "MeshPart"):
                continue
            if o["ClassName"] == "Part" and o.get("Transparency", 0) >= 1:
                continue
            low, high = bounds(o)
            corners = [(x, z) for x in (low[0], high[0]) for z in (low[2], high[2])]
            assert low[1] <= min(floor_top(x, z) for x, z in corners) + .05, \
                f"hall {index} {o['Name']} ({name}) floats {low[1] - min(floor_top(x, z) for x, z in corners):.2f} over its floor"
            if not name.startswith("SpiralStairWell_"):
                assert abs(high[1] - C) < .05, f"hall {index} {name} top {high[1] - C:+.2f} from the ceiling"
        # ---- F4-I/F4-vault: every bay corner rests on a pier; no pier cuts into a bay.
        piers = [o for o in ps if comp(o) == "VaultPier" and o["ClassName"] == "Part" and o.get("Transparency", 0) < 1]
        bays = [o for o in ps if comp(o).startswith("VaultBay32_") and o["ClassName"] == "MeshPart"]
        squares = []
        for bay in bays:
            low, high = bounds(bay)
            cx, cz = (low[0] + high[0]) / 2, (low[2] + high[2]) / 2
            hx, hz = (high[0] - low[0]) / 2, (high[2] - low[2]) / 2
            squares.append((cx - hx, cx + hx, cz - hz, cz + hz))
            for sx in (-1, 1):
                for sz in (-1, 1):
                    q = (cx + sx * hx, cz + sz * hz)
                    assert any(bounds(p)[0][0] - .5 <= q[0] <= bounds(p)[1][0] + .5
                               and bounds(p)[0][2] - .5 <= q[1] <= bounds(p)[1][2] + .5 for p in piers), \
                        f"F4-I: VaultArcade {index} bay corner {q} has no pier"
        for p in piers:
            low, high = bounds(p)
            for s in squares:
                ox = min(high[0], s[1]) - max(low[0], s[0])
                oz = min(high[2], s[3]) - max(low[2], s[2])
                assert ox <= .05 or oz <= .05, f"F4-vault: VaultArcade {index} pier cuts into a vault bay"
            # WP7 review: no pier without its bay (a lone lattice pier read as a half-finished arcade).
            if h["Type"] == "VaultArcade":
                assert any(low[0] - .5 <= qx <= high[0] + .5 and low[2] - .5 <= qz <= high[2] + .5
                           for s in squares for qx in s[:2] for qz in s[2:]), f"F4-I: VaultArcade {index} pier carries no bay"
        # ---- F7 (VaultArcade): no ceiling cut under a bay.
        for w in models:
            if comp(w).startswith("LightWell_"):
                wx, _, wz = frame(w["WorldPivot"])[:3]
                half = components[comp(w)]["attrs"]["PanelSize"] / 2
                for s in squares:
                    assert min(wx + half, s[1]) - max(wx - half, s[0]) <= 0 or min(wz + half, s[3]) - max(wz - half, s[2]) <= 0, \
                        f"F7: hall {index} {comp(w)} cut opens under a vault bay"
        # ---- F8 reach rule: nothing standable within cut half + 10 of an opening tops out above C-14
        # (head apex at jump 7.2 + 5.2 body stays 1.6 under the ceiling; the eye cannot see into the shaft).
        # A full-height column or pier tops out at C, under the slab: unreachable, but the rule (and world
        # audit 03) keeps them out of the reach square too. Tops above C+1 are wall crowns and lintels.
        for cap in ps:
            if not cap["Name"].startswith("Level 2 Sky Cap "):
                continue
            cx, cy, cz = position(cap)
            reach_half = point(cap["Size"])[0] / 2 + 10
            for g in grounds_world:
                low, high = g[1], g[2]
                if low[0] < cx + reach_half and high[0] > cx - reach_half and low[2] < cz + reach_half                         and high[2] > cz - reach_half and cy - 2 - 14 + .01 < high[1] <= cy - 2 + 1:
                    raise AssertionError(f"F8 reach: hall {index} {g[0]['Name']} tops out {high[1] - (cy - 2):+.2f} "
                                         f"from the ceiling within {reach_half:.0f} of an opening")
        planned = well_count(h)
        wells_here = sum(comp(m).startswith("LightWell_") for m in models)
        assert wells_here <= planned, f"F4-G: hall {index} has {wells_here} light wells, planned {planned}"
        # ---- shapes for the deck / spacing checks
        shapes = []      # (kind, x, z, radius, label)
        for m in models:
            name = comp(m)
            if name.startswith("Column_"):
                x, _, z = frame(m["WorldPivot"])[:3]
                shapes.append(("column", x, z, components[name]["attrs"]["Diameter"] / 2, name))
            elif name.startswith("SpiralStairWell_"):
                x, _, z = frame(m["WorldPivot"])[:3]
                a = components[name]["attrs"]
                shapes.append(("spiral", x, z, a["CoreDiameter"] / 2 + a["StairWidth"], name))
        for p in piers:
            x, _, z = position(p)
            shapes.append(("pier", x, z, None, "VaultPier"))
        drains = [o for o in ps if comp(o) == "DrainHole"]
        if drains:
            assert basin is not None, f"hall {index} has drains in a dry hall"
        for d in drains:
            low, high = bounds(d)
            x, z = (low[0] + high[0]) / 2, (low[2] + high[2]) / 2
            assert abs((low[1] + high[1]) / 2 - floor_top(x, z) - .03) < .05, \
                f"F4-drain: hall {index} drain {(low[1] + high[1]) / 2 - floor_top(x, z):+.3f} off its basin surface"
            shapes.append(("drain", x, z, 1.5, "DrainHole"))
        if h["Type"] != "CorridorHall":
            centres = [(s[1], s[2]) for s in shapes if s[0] == "drain"]
            for i, a in enumerate(centres):
                for b in centres[i + 1:]:
                    assert math.dist(a, b) >= 24 - .01, f"F4-drain: hall {index} drains {math.dist(a, b):.1f} apart (< 24)"
        # ---- F4-F/F4-walkway-band/F4-drain: nothing stands on a deck, ring corner, step or landing.
        grounds = [o for o in ps if o.get("CanCollide") and DECK_GROUND.match(o["Name"])]
        for kind, x, z, r, label in shapes:
            for g in grounds:
                if g["Name"].startswith("Ring Ground") and kind == "column":
                    continue  # the island ring round its own column (F4-J)
                cf, size = frame(g["CFrame"]), point(g["Size"])
                dx, dz = x - cf[0], z - cf[2]
                # The footprint's two horizontal local axes (the Run Deck lies with local X up, LATTICE_SPEC 4.3).
                (ax, ex), (az, ez) = [((cf[3 + i], cf[9 + i]), size[i] / 2) for i in range(3) if abs(cf[6 + i]) < .5]
                lx = (dx * ax[0] + dz * ax[1]) / max(math.hypot(*ax), 1e-9)
                lz = (dx * az[0] + dz * az[1]) / max(math.hypot(*az), 1e-9)
                if kind == "pier":
                    hit = abs(lx) < ex + 2.5 - .05 and abs(lz) < ez + 2.5 - .05
                else:
                    gap = math.hypot(max(abs(lx) - ex, 0), max(abs(lz) - ez, 0))
                    hit = gap < r - .05
                assert not hit, f"F4-F: hall {index} {label} at ({x:.1f}, {z:.1f}) stands on {g['Name']}"
        # ---- F4-J: one ring island, concentric with a column.
        if h["Type"] == "BigPool":
            rings = [o for o in ps if comp(o) == "Walkway_Ring_R9" and o["ClassName"] == "MeshPart"]
            assert len(rings) == 1, f"F4-J: BigPool {index} has {len(rings)} island rings"
            low, high = bounds(rings[0])
            rx, rz = (low[0] + high[0]) / 2, (low[2] + high[2]) / 2
            assert any(s[0] == "column" and s[4].startswith("Column_D10") and math.hypot(s[1] - rx, s[2] - rz) < .1 for s in shapes), \
                f"F4-J: BigPool {index} island ring is not round a column"
            # F4-lightround: flush with the ceiling, never into a column.
            lamps = defaultdict(list)
            for o in ps:
                if comp(o) == "LightRound" and o["ClassName"] == "MeshPart":
                    low, high = bounds(o)
                    lamps[(round((low[0] + high[0]) / 2, 1), round((low[2] + high[2]) / 2, 1))].append(high[1])
            for (x, z), tops in lamps.items():
                assert abs(max(tops) - C) < .01, f"F4-lightround: BigPool {index} LightRound top {max(tops) - C:+.3f} from the ceiling"
                for s in shapes:
                    if s[0] == "column":
                        assert math.hypot(s[1] - x, s[2] - z) >= s[3] + 1.7, f"F4-lightround: BigPool {index} LightRound cuts a column"
            # F4-A (2) (WP7 review: 62 of 114 BigPools were dark): every pool lights its share of the budget,
            # at most every third round, and never none.
            lit = [o for o in ps if o["Name"] == f"Level 2 Hall Round Light {index}"
                   and any(objects[c]["ClassName"] == "SpotLight" for c in children[o["Id"]])]
            expect = min(round_quota(layout), math.ceil(len(lamps) / 3))
            assert len(lit) == expect >= 1, \
                f"F4-A: BigPool {index} has {len(lit)} lit LightRounds; its share is {expect} of {len(lamps)} rounds"
            if stats is not None:
                stats["poolLights"].append(len(lit))
        # ---- F9 (until WP8 swerves the walls): no free-standing partition anywhere.
        assert not any(comp(o).startswith("CurveWall_") for o in ps), f"F9: hall {index} still has a free-standing curve wall"
        # ---- F4-G: 0-2 wall voids (BigPool: its outflows besides), 1-3 ceiling openings.
        voids = sum(o["Name"] == "Void Back" for o in ps)
        # WP7 review (F10): two high voids on one wall share one height (they sat a stud or two apart); the
        # BigPool outflows at the foot are a separate row.
        heights = defaultdict(set)
        for o in ps:
            if o["Name"] == "Void Back":
                low, high = bounds(o)
                if low[1] > h["FloorY"] + 10:
                    x, z = (low[0] + high[0]) / 2, (low[2] + high[2]) / 2
                    wall = min((x - h["MinX"], "West"), (h["MaxX"] - x, "East"), (z - h["MinZ"], "North"), (h["MaxZ"] - z, "South"))[1]
                    heights[wall].add(round(low[1], 2))
        assert all(len(v) == 1 for v in heights.values()), f"F10: hall {index} voids on one wall at heights {dict(heights)}"
        if h["Type"] == "BigPool":
            assert 1 <= voids <= 6, f"F4-G: BigPool {index} has {voids} wall voids"
        else:
            assert voids <= 2, f"F4-G: hall {index} has {voids} wall voids"
        if stats is not None:
            stats["voids"][voids] += 1
            if h["Type"] in {"ColumnHall", "CurvedChannel"}:
                cols = [s for s in shapes if s[0] == "column"]
                stats["columns"].append(len(cols))
                sig = tuple(sorted((s[4].split("_H")[0], round(abs(s[1] - h["Center"]["X"]) / 8), round(abs(s[2] - h["Center"]["Z"]) / 8)) for s in cols))
                # F4-G applies where the generator has a choice. A 14-stud column pocket's centre stands at least
                # 24 off the centre axes (lanes) and at most half - 19.25 (deck band 11.25 + 1 + 7; half - 13 in a
                # dry hall), and a second pocket in the same quadrant needs 18 more: under 128 on both sides (112
                # dry) a quadrant holds exactly one, so the mirror-folded layout is fixed by the hall size and
                # its door spokes. WP7 review: 22 of the 26 repeats over 50 seeds were such halls, more of them
                # since undersized VaultArcades are redrawn; they are counted apart, not judged as repetition.
                if max(h["Width"], h["Depth"]) >= (112 if h["PoolType"] == "Dry" else 128):
                    stats["signatures"][h["Type"]].append(sig)
                    stats["sigHalls"][(h["Type"], sig)].append((build.get("RequestedSeed"), index, h["Width"], h["Depth"]))
                else:
                    stats["oneSlot"][h["Type"]] += 1
            for s in shapes:
                if s[0] in {"drain", "column"} and h["Type"] != "CorridorHall":
                    q = (s[1] > h["Center"]["X"], s[2] > h["Center"]["Z"])
                    stats["quadrants"][s[0]][q] += 1
                    if s[0] == "drain":
                        stats["drainWall"].append(round(min(s[1] - h["MinX"], h["MaxX"] - s[1], s[2] - h["MinZ"], h["MaxZ"] - s[2])))
            stats["wells"][h["Type"]].append(sum(comp(m).startswith("LightWell_") for m in models))
            if h["Type"] == "VaultArcade":
                stats["vault"].append((min(h["Width"], h["Depth"]), len(piers), len(bays)))
    return True


SWERVE_FLOOR_PROPS = {"Column_D6": 3, "Column_D10": 5, "Column_D16": 8, "VaultPier": 2.5}


def swerve_box_distance(o, x, z):
    """Horizontal distance from (x, z) to an axis-upright box's footprint (any local axis may be the vertical one: the
    Run Swerve Deck and Swerve Wall lie with local X up, LATTICE_SPEC 4.3)."""
    cf, size = frame(o["CFrame"]), point(o["Size"])
    dx, dz = x - cf[0], z - cf[2]
    (ax, ex), (az, ez) = [((cf[3 + i], cf[9 + i]), size[i] / 2) for i in range(3) if abs(cf[6 + i]) < .5]
    lx, lz = dx * ax[0] + dz * ax[1], dx * az[0] + dz * az[1]
    return math.hypot(max(abs(lx) - ex, 0), max(abs(lz) - ez, 0))


def check_swerve_world(build, components, stats=None):
    """ANALYSIS F9 check 3 (WP8), every swerve hall of one built world, against its own plan: the planned pieces
    stand at their planned frames; the face is backed by collision; the deck is walkable ground all round; no
    straight cove, corner piece or wall void sits behind the outline; every reservation-placed object lies inside
    it (floor props off the deck); patrol nodes sit on the centre axes, 14 or more from any swerve collider."""
    layout = build["Layout"]
    objects = {o["Id"]: o for o in build["Objects"]}
    children = defaultdict(list)
    for o in objects.values():
        children[o["Parent"]].append(o)

    def below(oid):
        out, stack = [], [oid]
        while stack:
            for c in children[stack.pop()]:
                out.append(c)
                stack.append(c["Id"])
        return out

    def comp(o):
        return o["Attrs"].get("Level2_KitComponent") or ""
    rooms = {o["Attrs"]["Level2_HallIndex"]: o for o in objects.values()
             if o["ClassName"] == "Model" and o["Attrs"].get("Level2_HallIndex")}
    nodes = {o["Name"]: o for o in objects.values() if o["Name"].startswith("Level 2 Entity Patrol Node ")}
    halls = [h for h in layout["Halls"] if h.get("Swerve")]
    assert 2 <= len(halls) <= 3, f"F9: {len(halls)} swerve halls in the built map"
    for h in halls:
        index, fy, ceiling = h["Index"], h["FloorY"], h["CeilingClass"]
        inner = below(rooms[index]["Id"])
        ps = [o for o in inner if o["ClassName"] in {"Part", "MeshPart", "WedgePart"}]
        assert not any(comp(o).startswith(("CurveWall_", "Walkway_Bend16")) for o in ps), \
            f"F9: swerve hall {index} has a free-standing partition or bend"
        samples, polygon = swerve_outline(h)
        loop = h["Swerve"]["Loop"]
        # Planned pieces at their planned frames: Start marker on the face point, local X the travel, Z the room.
        for seg in loop:
            if seg["Kind"] == "S":
                name = f"SwerveS_{seg['Piece']}_R{seg['R']}_A{seg['Deg']}_H{ceiling}"
                along, offset = seg["At"], seg["Offset"]
            elif seg["Kind"] == "Corner" and seg["R"]:
                name, along, offset = f"SwerveCorner_R{seg['R']}_H{ceiling}", seg["At"], 0
            else:
                continue
            wall = seg["Wall"]
            x, z = {"North": (along, h["MinZ"] + 1.75 + offset), "South": (along, h["MaxZ"] - 1.75 - offset),
                    "West": (h["MinX"] + 1.75 + offset, along), "East": (h["MaxX"] - 1.75 - offset, along)}[wall]
            travel = {"North": (1, 0, 0), "East": (0, 0, 1), "South": (-1, 0, 0), "West": (0, 0, -1)}[wall]
            center = components[name]["meshRecords"][0]["center"]
            placed = False
            for o in ps:
                if o["ClassName"] == "MeshPart" and comp(o) == name:
                    cf = frame(o["CFrame"])
                    pivot = cf_point(cf, tuple(-v for v in center))
                    if math.dist(pivot, (x, fy, z)) < .01 and math.dist(cf_vector(cf, (1, 0, 0)), travel) < 1e-3 \
                            and abs(cf_vector(cf, (0, 1, 0))[1] - 1) < 1e-6:
                        placed = True
            assert placed, f"F9: swerve hall {index} lacks {name} at its planned frame ({x:.2f}, {z:.2f}) on {wall}"
            assert not any(comp(o) == name and o["Name"].startswith("Swerve Top Cove Fill") for o in ps), \
                f"F9: swerve hall {index} keeps a top-cove fill (above every reachable point, G8)"
        plateaus = [seg for seg in loop if seg["Kind"] == "Straight" and seg["Offset"] > 0]
        slabs = [o for o in ps if o["Name"] == f"Level 2 Swerve Wall {index} " + o["Name"].rsplit(" ", 1)[-1]]
        assert len(slabs) == len(plateaus), f"F9: swerve hall {index} has {len(slabs)} plateau slabs for {len(plateaus)}"
        # LATTICE_SPEC I1.8: each plateau slab spans y -8..C+2 and its ends are integer joints, all on the 0.5
        # lattice (check_lattice judges its seams with the skins).
        for o in slabs:
            low, high = bounds(o)
            axis = 0 if o["Name"].rsplit(" ", 1)[-1] in {"North", "South"} else 2
            assert abs(low[1] - (fy - 8)) < 1e-6 and abs(high[1] - (fy + ceiling + 2)) < 1e-6, \
                f"F9: swerve hall {index} {o['Name']} spans y {low[1] - fy:.3f}..{high[1] - fy:.3f}, not -8..C+2"
            assert on_lattice(low[axis], 1) and on_lattice(high[axis], 1), \
                f"F9: swerve hall {index} {o['Name']} ends {low[axis]:.3f}..{high[axis]:.3f} are not integer joints"
        # Spatial index of colliders (8-stud cells).
        solid, ground = defaultdict(list), defaultdict(list)
        for o in ps:
            if o["ClassName"] != "Part" or not o["CanCollide"]:
                continue
            low, high = bounds(o)
            for cx in range(math.floor(low[0] / 8), math.floor(high[0] / 8) + 1):
                for cz in range(math.floor(low[2] / 8), math.floor(high[2] / 8) + 1):
                    if o["CanQuery"]:
                        solid[(cx, cz)].append(o)
                    if o["Attrs"].get("Level2_EntityGround"):
                        ground[(cx, cz)].append((o, high[1]))
        door_spans = defaultdict(list)
        for side, cross, half in swerve_door_holes(layout, h):
            door_spans[side].append((cross - half - .05, cross + half + .05))
        missing_wall, missing_deck = [], []
        for x, z, psi, seg_index, curved in samples:
            seg = loop[seg_index]
            nx, nz = -math.sin(math.radians(psi)), math.cos(math.radians(psi))
            along = x if seg["Wall"] in {"North", "South"} else z
            if seg["Kind"] == "Corner" and not seg["R"]:
                continue
            flat = seg["Kind"] == "Straight" and seg["Offset"] == 0
            if not (flat and any(a < along < b for a, b in door_spans[seg["Wall"]])):
                for y in (.5, 2.9, 5.8, ceiling - 1):
                    q = (x - .2 * nx, fy + y, z - .2 * nz)
                    if not any(contains_part(o, q, 0) for o in solid[(math.floor(q[0] / 8), math.floor(q[2] / 8))]):
                        missing_wall.append((round(q[0], 2), round(y, 1), round(q[2], 2), seg_index))
            # The deck: every .5 along, across to its front; a d=0 straight's first 24 at a standard corner is that
            # corner's own deck (Walkway_Corner ring or square, checked by check_hall_shell).
            if flat:
                face_lo = {"North": h["MinX"], "South": h["MinX"], "West": h["MinZ"], "East": h["MinZ"]}[seg["Wall"]] + 1.75
                face_hi = {"North": h["MaxX"], "South": h["MaxX"], "West": h["MaxZ"], "East": h["MaxZ"]}[seg["Wall"]] - 1.75
                if along < face_lo + 24.5 or along > face_hi - 24.5:
                    continue
            for n in (.6, 2.5, 4.5, 6.5, 8.5, 9.1):
                q = (x + n * nx, fy + .44, z + n * nz)
                if not any(contains_part(o, q, 0) and top <= fy + .51
                           for o, top in ground[(math.floor(q[0] / 8), math.floor(q[2] / 8))]):
                    missing_deck.append((round(q[0], 2), round(q[2], 2), n, seg_index))
        assert not missing_wall, f"F9: swerve hall {index} wall coverage: {len(missing_wall)} face points " \
            f"have no collider .2 behind them, e.g. {missing_wall[:4]}"
        assert not missing_deck, f"F9: swerve hall {index} deck coverage: {len(missing_deck)} deck points " \
            f"are not walkable ground at the deck top, e.g. {missing_deck[:4]}"
        # Nothing straight behind the outline; no rectangle corner piece at an arced corner.
        for o in ps:
            name = comp(o)
            if o["ClassName"] == "MeshPart" and re.fullmatch(
                    r"CoveTop\d+|CoveBase\d+|CoveBaseStop_[PN]X|CoveBaseStopCorner_[PN]X|Walkway_Straight\d+", name):
                low, high = bounds(o)
                assert inside_polygon(polygon, (low[0] + high[0]) / 2, (low[2] + high[2]) / 2), \
                    f"F9: swerve hall {index} {name} lies behind the outline"
        for seg in loop:
            if seg["Kind"] == "Corner" and seg["R"]:
                hi_x, hi_z = CORNER_KEYS[seg["Corner"]]
                box = (h["MaxX"] - 1.75 - seg["R"] if hi_x else h["MinX"], h["MaxX"] if hi_x else h["MinX"] + 1.75 + seg["R"],
                       h["MaxZ"] - 1.75 - seg["R"] if hi_z else h["MinZ"], h["MaxZ"] if hi_z else h["MinZ"] + 1.75 + seg["R"])
                for o in ps:
                    if comp(o).startswith(("CornerCove_", "CoveBaseCorner_", "CoveTopCorner_", "Walkway_Corner_",
                                           "CoveTopInnerCorner", "CoveBaseInnerCorner")) \
                            or o["Name"].startswith("Level 2 Corner Deck "):
                        px, _, pz = position(o)
                        assert not (box[0] < px < box[1] and box[2] < pz < box[3]), \
                            f"F9: swerve hall {index} keeps {o['Name']} at its arced corner {seg['Corner']}"
        for o in ps:
            if o["Name"] == "Void Back":
                low, high = bounds(o)
                x, z = (low[0] + high[0]) / 2, (low[2] + high[2]) / 2
                side = min((x - h["MinX"], "West"), (h["MaxX"] - x, "East"), (z - h["MinZ"], "North"), (h["MaxZ"] - z, "South"))[1]
                lo, hi = (low[0], high[0]) if side in {"North", "South"} else (low[2], high[2])
                face = swerve_spans(h, side)
                start = (h["MinX"] if side in {"North", "South"} else h["MinZ"]) + 1.75
                end = (h["MaxX"] if side in {"North", "South"} else h["MaxZ"]) - 1.75
                assert any(lo >= (a if a <= start + 1e-6 else a + 10) - .3 and hi <= (b if b >= end - 1e-6 else b - 10) + .3
                           for a, b in face), f"F9: swerve hall {index} wall void at {lo:.1f}..{hi:.1f} on {side} " \
                    "is not on a straight 10 off the swerve"
        # Reservation-placed objects inside the outline: ceiling openings half-size + 2 off the face, floor props
        # off the deck (deck front + their own radius + 1, the deck band's spacing).
        fronts = [(x - 9.5 * math.sin(math.radians(psi)), z + 9.5 * math.cos(math.radians(psi)))
                  for x, z, psi, *_ in samples]

        def clearance(points, x, z):
            return min(math.hypot(x - a, z - b) for a, b, *_ in points)
        placed = []
        for o in inner:
            name = comp(o)
            if o["ClassName"] == "Model" and name.startswith("LightWell_"):
                wx, _, wz = frame(o["WorldPivot"])[:3]
                placed.append((name, wx, wz, components[name]["attrs"]["PanelSize"] / 2 + 2, samples))
            elif o["ClassName"] == "Model" and name.rsplit("_H", 1)[0] in SWERVE_FLOOR_PROPS:
                wx, _, wz = frame(o["WorldPivot"])[:3]
                placed.append((name, wx, wz, SWERVE_FLOOR_PROPS[name.rsplit("_H", 1)[0]] + 1, fronts))
            elif o["Name"].startswith(f"Level 2 Open Sky {index}."):
                wx, _, wz = position(o)
                placed.append((o["Name"], wx, wz, o["Attrs"]["Level2_OpenSkyRadius"] + 2, samples))
            elif name == "DrainHole" and o["ClassName"] == "MeshPart":
                low, high = bounds(o)
                placed.append((name, (low[0] + high[0]) / 2, (low[2] + high[2]) / 2, 1.5 + 1, fronts))
        for name, wx, wz, need, points in placed:
            have = clearance(points, wx, wz)
            assert inside_polygon(polygon, wx, wz) and have >= need - .05, \
                f"F9: swerve hall {index} {name} at ({wx:.1f}, {wz:.1f}) is {have:.2f} off the " \
                f"{'deck front' if points is fronts else 'outline'} (needs {need:.2f}, inside {inside_polygon(polygon, wx, wz)})"
        # Patrol nodes on the centre axes, 14 or more from any swerve collider.
        swerve_colliders = [o for o in ps if o["ClassName"] == "Part" and o["CanCollide"]
                            and (comp(o).startswith("Swerve") or o["Name"].startswith(("Level 2 Swerve ", "Level 2 Run Swerve ")))]
        cx, cz = h["Center"]["X"], h["Center"]["Z"]
        for k, (dx, dz) in enumerate(((-.32 * h["Width"], 0), (.32 * h["Width"], 0), (0, -.32 * h["Depth"]),
                                      (0, .32 * h["Depth"])), 1):
            node = nodes[f"Level 2 Entity Patrol Node {index}.{k}"]
            near(position(node), (cx + dx, fy + 2, cz + dz))
            gap = min(swerve_box_distance(o, cx + dx, cz + dz) for o in swerve_colliders)
            assert gap >= 14, f"F9: swerve hall {index} patrol node {k} is {gap:.2f} from a swerve collider"
        if stats is not None:
            stats["swerveHalls"].append((build["RequestedSeed"], index, len(samples)))
    return True


def swerve_door_holes(layout, hall):
    """(wall, cross, half width) of every door hole in a hall's walls (the builder's hallDoors geometry)."""
    halls = {h["Index"]: h for h in layout["Halls"]}
    out = []
    for c in layout["Corridors"]:
        if hall["Index"] not in (c["A"], c["B"]):
            continue
        a, b = halls[c["A"]], halls[c["B"]]
        key = c["Axis"]
        first = a if a["Center"][key] <= b["Center"][key] else b
        is_first = first["Index"] == hall["Index"]
        side = ("East" if is_first else "West") if key == "X" else ("South" if is_first else "North")
        out.append((side, c["Cross"], hole_half(c)))
    return out


def corridor_floor_triangles():
    """GB: every horizontal triangle of the corridor kit meshes (RoundTunnel_*/Pipe_*), chunk-local (relative to the
    chunk centre, as the installed MeshPart's own frame), keyed (component, material) like the installed MeshPart name."""
    import base64
    import struct
    out = {}
    for job in "ABCD":
        path = JOBS / job / "export/manifest.json"
        if not path.is_file():
            continue
        for rec in json.loads(path.read_text(encoding="utf-8"))["chunks"]:
            if not rec["component"].startswith(("RoundTunnel_", "Pipe_")):
                continue
            blob = base64.b64decode((path.parent / "chunks" / f"c{rec['id']:05d}.b64").read_text(encoding="ascii").strip())
            npos, nnorm, nuv, ntri = struct.unpack_from("<4I", blob)
            pos = struct.unpack_from(f"<{npos * 3}f", blob, 16)
            idx = struct.unpack_from(f"<{ntri * 9}I", blob, 16 + npos * 12 + nnorm * 12 + nuv * 8)
            tris = []
            for t in range(ntri):
                tri = [pos[3 * idx[9 * t + 3 * k]:3 * idx[9 * t + 3 * k] + 3] for k in range(3)]
                if max(v[1] for v in tri) - min(v[1] for v in tri) < 1e-4:
                    tris.append(tri)
            out[(rec["component"], rec["material"])] = (tris, rec["size"])
    return out


def clip_polygon(poly, f):
    """Sutherland-Hodgman against one half-plane: keep the (x, z) points where the linear f >= 0."""
    out = []
    for i, p in enumerate(poly):
        q = poly[i - 1]
        fp, fq = f(p), f(q)
        if (fp >= 0) != (fq >= 0):
            t = fq / (fq - fp)
            out.append((q[0] + (p[0] - q[0]) * t, q[1] + (p[1] - q[1]) * t))
        if fp >= 0:
            out.append(p)
    return out


def polygon_area(poly):
    return abs(sum(poly[i - 1][0] * p[1] - p[0] * poly[i - 1][1] for i, p in enumerate(poly))) / 2


COPLANAR = .01          # GB: two faces closer than this over an overlap are one plane (Roblox z-fights them)


def check_floor_mouths(build, floor_tris):
    """GB (VERIFY2 'tunnel floors z-fighting with a swerve hall's water floor', world audit 08 on 257600258): no hall
    floor or water floor top lies in the plane of a corridor floor face (a tunnel/pipe mesh floor facet, threshold,
    mouth step) over more than 0.05 stud^2. Measured as the TRUE vertical gap over the clipped overlap: the floor's top
    plane is evaluated at each overlap point, so a basin tilted 0.2 degrees is not compared through the world origin
    (that is what reported 257600258's mouths, 0.8..1.6 studs apart, as coplanar)."""
    objects = build["Objects"]
    by_id = {o["Id"]: o for o in objects}
    memo = {}

    def corridor(oid):
        """Id of the 'Level 2 Corridor N' model above oid (None outside corridors)."""
        if oid not in memo:
            o = by_id.get(oid)
            memo[oid] = None if o is None else oid if o["Attrs"].get("Level2_CorridorIndex") else corridor(o["Parent"])
        return memo[oid]
    faces = []                                      # (corridor model id, name, y, [(x, z)] ccw-or-cw polygon)
    for o in objects:
        model = corridor(o["Parent"])
        if o["ClassName"] not in {"Part", "MeshPart"} or o.get("Transparency", 0) >= .98 or not model:
            continue
        cf, size = frame(o["CFrame"]), point(o["Size"])
        if o["ClassName"] == "Part":
            for axis in range(3):
                for sign in (-1, 1):
                    n = [0, 0, 0]
                    n[axis] = sign
                    if cf_vector(cf, n)[1] < .999:
                        continue
                    u, v = [k for k in range(3) if k != axis]
                    corners = []
                    for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                        local = [0, 0, 0]
                        local[axis], local[u], local[v] = sign * size[axis] / 2, a * size[u] / 2, b * size[v] / 2
                        corners.append(cf_point(cf, local))
                    faces.append((model, o["Name"], corners[0][1], [(c[0], c[2]) for c in corners]))
        else:
            key = (o.get("FixtureComponent"), o["Name"].rsplit("_", 1)[-1])
            if key not in floor_tris:
                continue
            tris, record_size = floor_tris[key]
            scale = [size[k] / record_size[k] for k in range(3)]
            for tri in tris:
                world = [cf_point(cf, [tri[j][k] * scale[k] for k in range(3)]) for j in range(3)]
                if abs(world[0][1] - world[1][1]) < 1e-3 and abs(world[0][1] - world[2][1]) < 1e-3:
                    faces.append((model, o["Name"], world[0][1], [(w[0], w[2]) for w in world]))
    faces = [f + ((min(p[0] for p in f[3]), max(p[0] for p in f[3]), min(p[1] for p in f[3]), max(p[1] for p in f[3])),)
             for f in faces]
    closest = math.inf
    for floor in objects:
        if not re.fullmatch(r"Level 2 Hall (Water )?Floor \d+", floor["Name"]) or floor["ClassName"] != "Part":
            continue
        cf, size = frame(floor["CFrame"]), point(floor["Size"])
        up = cf_vector(cf, (0, 1, 0))
        top = cf_point(cf, (0, size[1] / 2, 0))
        rect = [cf_point(cf, (a * size[0] / 2, size[1] / 2, b * size[2] / 2)) for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        xs, zs = [p[0] for p in rect], [p[2] for p in rect]

        def height(x, z):
            return top[1] - (up[0] * (x - top[0]) + up[2] * (z - top[2])) / up[1]
        for model, name, y, poly, (x0, x1, z0, z1) in faces:
            if x1 <= min(xs) or x0 >= max(xs) or z1 <= min(zs) or z0 >= max(zs):
                continue
            centre = (sum(xs) / 4, sum(zs) / 4)
            for i, c in enumerate(rect):                     # clip to the floor top's (convex) xz outline
                d = rect[(i + 1) % 4]

                def edge(p, c=c, d=d):
                    return (d[0] - c[0]) * (p[1] - c[2]) - (d[2] - c[2]) * (p[0] - c[0])
                s = 1 if edge(centre) >= 0 else -1
                poly = clip_polygon(poly, lambda p, edge=edge, s=s: s * edge(p))
                if not poly:
                    break
            if len(poly) < 3 or polygon_area(poly) < 1e-3:
                continue
            gaps = [y - height(*p) for p in poly]
            closest = min(closest, min(abs(g) for g in gaps))
            # the part of the overlap where the two faces are within COPLANAR of each other
            band = clip_polygon(clip_polygon(poly, lambda p: COPLANAR - (y - height(*p))),
                                lambda p: COPLANAR + (y - height(*p)))
            area = polygon_area(band) if len(band) >= 3 else 0
            assert area <= .05, (
                f"GB: {floor['Name']} is coplanar with corridor {by_id[model]['Name']} {name} over {area:.2f} stud^2 "
                f"(gap {min(gaps):+.3f}..{max(gaps):+.3f} at y {y:.3f})")
    return closest


def check_exit_hole(build):
    """LATTICE_SPEC 6 (HallWallGap): the exit wall's hole is deckZ +- 9 x F+73..F+90, every Wall/Sill/Lintel edge of
    that wall on the 0.5 lattice (check_hall_shell), and the kit's ExitCollar frame (its visible parts and meshes at the
    proud plane) spans the whole hole, so no wall slab edge is seen through it."""
    layout = build["Layout"]
    grand = layout["GrandSlideHall"]
    index, fy, deck_z = grand["Index"], grand["FloorY"], grand["MinZ"] + 42
    objects = build["Objects"]
    panels = [o for o in objects if o["ClassName"] == "Part"
              and re.fullmatch(rf"Level 2 Hall (Sill|Lintel) {index} East", o["Name"])
              and bounds(o)[0][2] < deck_z < bounds(o)[1][2]]
    assert len(panels) == 2, f"exit wall hole has {[o['Name'] for o in panels]}, not one sill and one lintel"
    sill, lintel = sorted(panels, key=lambda o: bounds(o)[0][1])
    L, H = bounds(lintel)[0][2], bounds(lintel)[1][2]
    B, T = bounds(sill)[1][1], bounds(lintel)[0][1]
    near((L, H, B, T), (deck_z - 9, deck_z + 9, fy + 73, fy + 90), 1e-6)
    frame_parts = [bounds(o) for o in objects if o["ClassName"] in {"Part", "MeshPart"} and o.get("Transparency", 0) < 1
                   and o["Attrs"].get("Level2_KitComponent") == "ExitCollar"]
    assert frame_parts, "no visible ExitCollar parts"
    lo = [min(b[0][k] for b in frame_parts) for k in range(3)]
    hi = [max(b[1][k] for b in frame_parts) for k in range(3)]
    assert lo[2] <= L + 1e-6 and H - 1e-6 <= hi[2] and lo[1] <= B + 1e-6 and T - 1e-6 <= hi[1], \
        f"exit hole z {L:.3f}..{H:.3f} y {B:.3f}..{T:.3f} is not covered by the ExitCollar frame " \
        f"z {lo[2]:.3f}..{hi[2]:.3f} y {lo[1]:.3f}..{hi[1]:.3f}"
    return 2


def lattice_tools():
    """LATTICE_SPEC I1: dump_world (instrument/export) and lattice_audit, imported lazily (dump_world imports this
    suite as its harness)."""
    sys.path.insert(0, str(ROOT / "tools/level2_poolrooms"))
    import dump_world  # noqa: E402
    import lattice_audit  # noqa: E402
    return dump_world, lattice_audit


_LATTICE = {}


def _lattice_init(kit_exports):
    _, la = lattice_tools()
    _LATTICE["chunks"] = la.load_kit_chunks({"kitExports": kit_exports})
    _LATTICE["tile"] = la.tile_of({"kitExports": kit_exports})


def _lattice_audit(world):
    _, la = lattice_tools()
    stats = Counter()
    findings = la.audit_parts(world["parts"], world["layout"], _LATTICE["chunks"], stats=stats, tile=_LATTICE["tile"])
    return world["requestedSeed"], dict(stats), findings


def check_lattice(builds):
    """LATTICE_SPEC I1 (replaces GB's exit-wall-only lattice check, strictly more): lattice_audit's measured face-corner
    rule on every seam of every build - Part/Part, Part/mesh, mesh/mesh, inlays - with the pitch read from the kit
    manifest. PASS iff no build has a finding (a visible grid step over 0.01). Mutations: the first Hall Lintel over a
    tunnel moved .25 along its wall must be named; moved .5 (one whole tile) it must not."""
    dump_world, la = lattice_tools()
    worlds = [dump_world.export(b) for b in builds]
    kit = worlds[0]["kitExports"]
    import multiprocessing
    # One audit holds several hundred MiB of seam arrays when a world steps a lot: at most 8 workers (default 4,
    # LEVEL2_LATTICE_PROCS overrides), each recycled after one world, worlds fed one at a time.
    procs = min(8, os.cpu_count() or 1, int(os.environ.get("LEVEL2_LATTICE_PROCS") or 4))
    with multiprocessing.Pool(procs, _lattice_init, (kit,), maxtasksperchild=1) as pool:
        results = list(pool.imap(_lattice_audit, worlds, chunksize=1))
    tile = la.tile_of({"kitExports": kit})
    failed = []
    for seed, stats, findings in results:
        print(f"lattice seed {seed}: {stats.get('seams', 0)} seams / {stats.get('stepping', 0)} step / "
              f"{stats.get('cut_pieces', 0)} cut / {len(findings)} findings")
        if findings:
            failed.append((seed, findings))
    assert not failed, f"LATTICE: {sum(len(f) for _, f in failed)} visible grid steps over {len(failed)} builds (tile {tile}); " \
        "first: " + "; ".join(f"seed {seed} {f['category']} at {f['at']} offset {f['offset']} ({f['kind']})"
                              for seed, fs in failed[:3] for f in fs[:3])
    _lattice_init(kit)
    world0, layout0 = worlds[0], builds[0]["Layout"]
    halls0 = {h["Index"]: h for h in layout0["Halls"]}

    def lintel(world):
        for k, part in enumerate(world["parts"]):
            m = re.fullmatch(r"Level 2 Hall Lintel (\d+) (North|South|West|East)", part["name"])
            if m:
                c, size = part["cframe"], part["size"]
                y_low = c[1] - sum(abs(c[6 + j]) * size[j] for j in range(3)) / 2   # world half height, any orientation
                if abs(y_low - (halls0[int(m.group(1))]["FloorY"] + 32)) < 1e-6:
                    return k, m.group(2)
        raise AssertionError("no Hall Lintel over a tunnel in the first build")

    def shifted(amount):
        # Only findings on the moved lintel itself: another lintel's finding (or a hidden one the audit cannot rule
        # out) must neither make the .25 move pass nor the .5 move fail (I1 review).
        world = copy.deepcopy(world0)
        k, side = lintel(world)
        world["parts"][k]["cframe"][0 if side in {"North", "South"} else 2] += amount
        moved = world["parts"][k]["name"]
        return [f for f in _lattice_audit(world)[2] if moved in (f["a"]["name"], f["b"]["name"])]
    caught = shifted(.25)
    assert caught, "LATTICE mutation: a Hall Lintel moved .25 along its wall survived lattice_audit"
    assert not shifted(.5), "LATTICE mutation: a Hall Lintel moved one whole tile (.5) was reported"
    print(f"PASS LATTICE: 0 findings over {len(builds)} builds at tile {tile}; mutation: a Hall Lintel moved .25 along "
          f"its wall named ({caught[0]['category']}, offset {caught[0]['offset']}), moved .5 not named")


SLAB = re.compile(r"Level 2 (Hall Wall|Hall Sill|Hall Lintel|Swerve Wall) \d+ (North|South|West|East)")


def check_slab_anchors(build):
    """I1 review (reveal inside corners): a wall slab's thickness runs from the outer face (the boundary, on the
    lattice) to the room face (boundary + 1.75, off it), so a face with a depth axis continues its neighbours only if
    Roblox anchors that face's tiles at the outer edge. Under the measured face-corner rule (lattice_audit.ANCHOR) every
    face of every Hall Wall / Sill / Lintel and Swerve Wall must have BOTH anchored edges on the 0.5 lattice (hidden
    faces included: one orientation serves all six). lattice_audit cannot see this: it never pairs the perpendicular
    faces that meet at a void's or slit's reveal corner. Returns the number of slabs checked."""
    ANCHOR = lattice_tools()[1].ANCHOR
    count = 0
    for o in build["Objects"]:
        if o["ClassName"] != "Part" or not SLAB.fullmatch(o["Name"]):
            continue
        cf, size = frame(o["CFrame"]), point(o["Size"])
        for (axis, sign), anchored in ANCHOR.items():
            for k, s in anchored:
                # the face's anchored edge along object axis k, as a world coordinate on the axis that k maps to
                edge = cf_point(cf, tuple((sign * size[axis] / 2 if j == axis else s * size[k] / 2 if j == k else 0)
                                          for j in range(3)))
                w = max(range(3), key=lambda i: abs(cf[3 + 3*i + k]))
                v = edge[w] / TILE
                assert abs(cf[3 + 3*w + k]) > 1 - 1e-6 and abs(v - round(v)) <= 1e-6,                     f"{o['Name']} face {'+-'[sign < 0]}{'XYZ'[axis]} anchors its tiles at {'XYZ'[w]} = "                     f"{edge[w]:.4f}, off the {TILE} lattice (orient the slab: object X up, Y outward, Z along)"
        count += 1
    return count


def check_tile_surfaces(build):
    """Step S: every kit tile MeshPart in the world wears its tile as exactly ONE SurfaceAppearance "Tile" with a
    ColorMap (UV-true grout on the Parts' 0.5 lattice) and MaterialVariant "" (a variant on a MeshPart ignores the
    UVs); no MeshPart wears a PR Tile variant; and no SurfaceAppearance sits anywhere else. Returns the tile meshes."""
    objects = build["Objects"]
    appearances = defaultdict(list)
    for o in objects:
        if o["ClassName"] == "SurfaceAppearance":
            appearances[o["Parent"]].append(o)
    tiles = [o for o in objects if o.get("FixtureTile")]
    assert tiles, "no kit tile MeshPart in the world"
    for o in tiles:
        assert o["ClassName"] == "MeshPart", o["Name"]
        found = appearances.get(o["Id"], [])
        assert len(found) == 1 and found[0]["Name"] == "Tile" and found[0].get("ColorMap"), \
            f"tile mesh {o['Name']} has {len(found)} SurfaceAppearances, want one 'Tile' with its maps"
        assert o["MaterialVariant"] == "", f"tile mesh {o['Name']} wears MaterialVariant {o['MaterialVariant']!r}"
    for o in objects:
        assert o["ClassName"] != "MeshPart" or not o["MaterialVariant"].startswith("PR Tile"), \
            f"MeshPart {o['Name']} wears MaterialVariant {o['MaterialVariant']!r}"
    stray = set(appearances) - {o["Id"] for o in tiles}
    assert not stray, f"{len(stray)} SurfaceAppearances outside the kit tile meshes"
    return len(tiles)


INSTALLED_KIT = ROOT / "assets/level2/poolrooms-kit/export/manifest.json"


def check_install_contract(builds, components, manifest_path=INSTALLED_KIT):
    """WP7 review: the offline suite builds from the per-job exports, Studio from the canonical installed kit.
    Every component the builder cloned over the run must exist in the canonical export with the same attributes
    (PanelSize, collar depths, ...), parts, colliders, markers and meshes (chunk records by sha256, chunk ids
    aside), or the pushed builder fails (missing name) or differs (stale geometry) at runtime. A failure means:
    run build.py and reinstall the kit before pushing the builder."""
    used = sorted({o["Attrs"]["Level2_KitComponent"] for b in builds for o in b["Objects"]
                   if o["Attrs"].get("Level2_KitComponent")})
    installed = json.loads(Path(manifest_path).read_text(encoding="utf-8"))

    def strip(records):
        return [{k: v for k, v in r.items() if k != "id"} for r in records]
    fields = ("attrs", "parts", "colliders", "markers")
    missing, stale = [], []
    for name in used:
        record = installed["components"].get(name)
        if record is None:
            missing.append(name)
        elif any(record.get(k) != components[name].get(k) for k in fields) \
                or strip(installed["chunks"][i] for i in record["chunks"]) != strip(components[name]["meshRecords"]):
            stale.append(name)
    assert used and not missing and not stale, (
        f"installed kit {manifest_path} is behind the job exports the builder is tested against: missing {missing}; "
        f"stale {stale}. Run build.py and reinstall the kit before pushing the builder.")
    print(f"PASS install contract: all {len(used)} components the builder cloned match {manifest_path}")


def corner_cove_mutation(binary, components, slides, seeds):
    """WP7 review / FA review: the square-corner rules, each mutation caught by the rule it targets. Both run on the
    layouts from before the FA review (the generator's corner-door filter off: a tunnel 7 or a pipe 6 from a hall
    corner), the only layouts whose square-corner feet are too short for the mitre.
    1. Builder unchanged: the short foot stays bare, so the doorless-corner rule must reject that corner.
    2. Builder short-corner rule off too (CORNER_SHORT 6.25 -> 0, the WP7 behaviour: every square corner mitred, a
       stop wherever its segment ends): the inner-corner oracle must reject the base mitre it does not expect there.
    Before the FA review the CORNER_SHORT mutation ran on the generator's own layouts and accepted any foot-coverage
    message too; with the filter on it no longer changes any layout's build, so it would prove nothing there."""
    generator = LAYOUT.read_text(encoding="utf-8")
    gate = "local CORNER_DOOR_LOW, CORNER_DOOR_HIGH = 4.8, 8.125"
    assert generator.count(gate) == 1
    generator = generator.replace(gate, "local CORNER_DOOR_LOW, CORNER_DOOR_HIGH = 4.8, 4.8")
    source = BUILDER.read_text(encoding="utf-8")
    marker = "local CORNER_SHORT=6.25"
    assert source.count(marker) == 1
    for label, builder, wanted in (
            ("corner-door filter off", source, "is doorless but its base foot is too short"),
            ("corner-door filter off + CORNER_SHORT=0", source.replace(marker, "local CORNER_SHORT=0"), "wants [")):
        caught = None
        for build in run_luau(binary, build_program(seeds, components, slides, builder, generator)):
            try:
                check_snapshot(build, components, slides)
            except AssertionError as error:
                assert "square corner" in str(error) and wanted in str(error), \
                    f"corner mutation '{label}' failed for the wrong reason: {error}"
                caught = (build["RequestedSeed"], str(error)[:110])
                break
        assert caught, f"corner mutation '{label}' survived the square-corner rules on seeds {seeds}"
        print(f"PASS mutation: {label} rejected (seed {caught[0]}): {caught[1]}")


def check_variety(stats):
    """F4-G/F4-F over the whole run: varied column layouts, drains and columns spread over the quadrants."""
    assert len(set(stats["columns"])) > 1, "F4-G: every column hall has the same column count"
    for kind, sigs in stats["signatures"].items():
        counts = Counter(sigs)
        shared = sum(c for c in counts.values() if c > 1)
        assert shared <= max(1, .05 * len(sigs)), f"F4-G: {shared} of {len(sigs)} {kind} halls repeat a column layout: " + \
            "; ".join(f"{list(sig)} in {stats['sigHalls'][(kind, sig)][:4]}" for sig, c in counts.items() if c > 1)[:1500]
    for kind, quads in stats["quadrants"].items():
        total = sum(quads.values())
        for q, n in quads.items():
            assert .15 <= n / total <= .35, f"F4-F: {kind} quadrant {q} holds {n / total:.0%}"
    # ANALYSIS F4-F proposed <= 30% against the old edge-first scan (65% of drains at its 11-stud minimum).
    # On the shuffled lattice the outermost free ring (19 studs, the deck band's edge) holds a third of a
    # quadrant's free cells by geometry alone: measured 39% over the 10-seed suite. Bound it at 45%.
    # F4-I: a VaultArcade falls back to a column field only when its door spokes leave no 2x2 pier group
    # (measured 2 of 56 over 50 seeds); vault halls must still read as vault halls.
    bare = sum(bays == 0 for _, _, bays in stats["vault"])
    assert bare <= max(1, .1 * len(stats["vault"])), f"F4-I: {bare} of {len(stats['vault'])} VaultArcades seat no bay"
    walls = Counter(stats["drainWall"])
    least = min(walls)
    assert walls[least] / len(stats["drainWall"]) <= .45,         f"F4-F: {walls[least]} of {len(stats['drainWall'])} drains at the minimum wall offset"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=int, default=50)
    parser.add_argument("--installed-kit", type=Path, default=INSTALLED_KIT,
                        help="manifest.json of the kit Studio will run (default: the canonical repo export)")
    args = parser.parse_args()
    assert args.seeds > 0
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau") or DEFAULT_BIN
    paths = [BUILDER, LAYOUT, CONFIG, OBJECTIVES, EXIT_TESTS]
    paths += [JOBS / j / "export/manifest.json" for j in "ABC"]
    paths += [SLIDES]
    before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    compile_builder(binary)
    check_budget_constant()
    components, slides = read_exports()
    # The fifth seed exercises a real elongated CorridorHall (232 x 104). F9 (WP8): the next three are the
    # 400-seed layout run's most swervy maps since the F9 review (three swerve halls and 12 S bends each, the
    # most; 577752071 and 278137431 also the most curved length).
    seeds = [1,101,1182081016,738163940,484836893,577752071,278137431,1914587599][:args.seeds]
    seeds += [(i*15485863+20261003)%2147483647 for i in range(args.seeds-len(seeds))]
    dump_world, _ = lattice_tools()
    builds = run_luau(binary, dump_world.instrument(build_program(seeds, components, slides)))
    assert len(builds) == len(seeds), f"only {len(builds)} of {len(seeds)} builders completed"
    if args.seeds >= 50:
        assert {660, 668} <= {build["Layout"]["GrandSlideHall"]["MaxX"] for build in builds}, \
            "50-seed exit check must cover both MaxX insets"
    totals = []
    dressing_stats = new_dressing_stats()
    swerve_stats = {"swerveHalls": []}
    seen = set()
    floor_tris = corridor_floor_triangles()
    closest_floor, exit_holes, slabs, tile_meshes = math.inf, 0, 0, []
    for build in builds:
        try:
            _, total = check_snapshot(build, components, slides)
            totals.append(total)
            closest_floor = min(closest_floor, check_floor_mouths(build, floor_tris))
            exit_holes += check_exit_hole(build) // 2
            slabs += check_slab_anchors(build)
            tile_meshes.append(check_tile_surfaces(build))
            # The default 50-seed list repeats 484836893 (fixed seed and generated i=30): count each map once.
            check_dressing(build, components, None if build["RequestedSeed"] in seen else dressing_stats)
            check_swerve_world(build, components, swerve_stats)
            seen.add(build["RequestedSeed"])
        except AssertionError as error:
            raise AssertionError(f"seed {build['RequestedSeed']}: {error}") from error
    check_variety(dressing_stats)
    print(f"PASS GB floor/mouth planes: no hall floor or water floor top within {COPLANAR} of a corridor floor face "
          f"(tunnel/pipe mesh facets, thresholds, mouth steps) over {len(builds)} builds; closest {closest_floor:.3f}")
    print(f"PASS exit wall: {exit_holes} holes over {len(builds)} builds at the HallWallGap (deckZ +- 9 x F+73..F+90), "
          "covered by the ExitCollar frame")
    print(f"PASS slab anchors: every face of {slabs} Hall Wall/Sill/Lintel and Swerve Wall slabs over {len(builds)} "
          f"builds anchors its tiles on {TILE} lattice edges (depth at the outer face)")
    print(f"PASS tile surfaces: {min(tile_meshes)}..{max(tile_meshes)} kit tile MeshParts per world, each with one "
          "SurfaceAppearance 'Tile' and MaterialVariant ''; no MeshPart wears a PR Tile variant")
    check_lattice(builds)

    def mutate_builder_check(check, pick, change, expect, label):
        mutated = copy.deepcopy(builds[0])
        target = next(o for o in mutated["Objects"] if pick(o, mutated))
        change(target, mutated)
        try:
            check(mutated)
        except AssertionError as error:
            assert expect in str(error), f"{label} mutation failed for the wrong reason: {error}"
        else:
            raise AssertionError(f"{label} survived its oracle")
        print(f"PASS mutation: {label} rejected in memory")

    def hall_of_floor(o, mutated):
        index = int(o["Name"].rsplit(" ", 1)[1])
        return next(h for h in mutated["Layout"]["Halls"] if h["Index"] == index)

    def flat_at_floor(o, mutated):
        cf = o["CFrame"]["$cframe"]
        cf[1] = hall_of_floor(o, mutated)["FloorY"] - point(o["Size"])[1] / 2
        cf[3:] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    def nudge(axis, amount):
        def change(o, mutated):
            o["CFrame"]["$cframe"][axis] += amount
        return change
    def axis_aligned(o, mutated):
        # the pre-review slab: identity rotation, Size along the world axes (same box)
        low, high = bounds(o)
        o["CFrame"]["$cframe"][3:] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        o["Size"].update(zip("XYZ", (high[i] - low[i] for i in range(3))))
    tile_sa = lambda o, m: o["ClassName"] == "SurfaceAppearance" and o["Name"] == "Tile"
    mutate_builder_check(check_tile_surfaces, tile_sa, lambda o, m: m["Objects"].remove(o),
                         "SurfaceAppearances, want one", "a kit tile mesh without its SurfaceAppearance")
    mutate_builder_check(check_tile_surfaces, lambda o, m: o.get("FixtureTile"),
                         lambda o, m: o.update(MaterialVariant="PR Tile"), "wears MaterialVariant",
                         "a kit tile mesh wearing PR Tile (variant ignores its UVs)")
    mutate_builder_check(lambda b: check_snapshot(b, components, slides), lambda o, m: o.get("FixtureTile"),
                         lambda o, m: o.update(MaterialVariant="PR Tile Mesh"), "PR Tile Mesh",
                         "a kit tile mesh wearing the retired twin PR Tile Mesh")
    mutate_builder_check(lambda b: check_slab_anchors(b), lambda o, m: re.fullmatch(r"Level 2 Hall Sill \d+ North", o["Name"]),
                         axis_aligned, "anchors its tiles", "a North Hall Sill laid axis-aligned (the reveal-corner step)")
    floors = lambda b: check_floor_mouths(b, floor_tris)
    mutate_builder_check(floors, lambda o, m: o["Name"].startswith("Level 2 Hall Floor "),
                         nudge(1, .02), "is coplanar with corridor",
                         "a dry hall floor raised .02 to its thresholds' top (the old F4-M z-fight)")
    mutate_builder_check(floors, lambda o, m: o["Name"].startswith("Level 2 Hall Water Floor "), flat_at_floor,
                         "is coplanar with corridor", "a basin's water floor laid flat at FloorY (into its mouths' plane)")
    mutate_builder_check(check_exit_hole,
                         lambda o, m: re.fullmatch(rf"Level 2 Hall Lintel {m['Layout']['GrandSlideHall']['Index']} East", o["Name"])
                         and bounds(o)[0][2] < m["Layout"]["GrandSlideHall"]["MinZ"] + 42 < bounds(o)[1][2],
                         nudge(1, .5), "!=",
                         "the exit lintel raised .5 off the HallWallGap")
    print(f"PASS F9 swerve halls (check 3): {len(swerve_stats['swerveHalls'])} halls over {len(builds)} builds, "
          f"{sum(n for *_, n in swerve_stats['swerveHalls'])} outline samples: planned pieces at their frames, face "
          "backed by collision, deck walkable all round, nothing behind the outline, props inside it, axis patrol nodes")
    print(f"PASS WP7 dressing: column counts {sorted(Counter(dressing_stats['columns']).items())}, "
          f"wall voids per hall {sorted(dressing_stats['voids'].items())}, "
          f"VaultArcade (min side, piers, bays) {dressing_stats['vault']}, "
          f"BigPool round lights {sorted(Counter(dressing_stats['poolLights']).items())}, "
          f"one-pocket-per-quadrant halls outside the repeat rule {dict(dressing_stats['oneSlot'])}")
    mutated = copy.deepcopy(builds[0])
    objects = {o["Id"]: o for o in mutated["Objects"]}
    hall_by_id = {o["Id"]: o for o in objects.values() if o["Attrs"].get("Level2_HallIndex")}
    moved = False
    for item in objects.values():
        if item["ClassName"] != "Part" or not item.get("CanCollide") or "CFrame" not in item:
            continue
        parent = item["Parent"]
        dressing = False
        hall = None
        while parent in objects:
            ancestor = objects[parent]
            dressing |= ancestor["Attrs"].get("Level2_Dressing") is True
            hall = hall or hall_by_id.get(parent)
            parent = ancestor["Parent"]
        if dressing and hall:
            hall_record = next(h for h in mutated["Layout"]["Halls"]
                               if h["Index"] == hall["Attrs"]["Level2_HallIndex"])
            values = item["CFrame"]["$cframe"]
            values[0] = hall_record["Center"]["X"]
            values[2] = hall_record["Center"]["Z"]
            values[1] = hall["Attrs"]["Level2_FloorY"] + 2
            moved = True
            break
    assert moved, "no Poolrooms dressing collider available for placement mutation"
    try:
        check_snapshot(mutated, components, slides)
    except AssertionError as error:
        assert "dressing" in str(error) and "lane" in str(error), \
            f"placement mutation failed for the wrong reason: {error}"
    else:
        raise AssertionError("a dressing collider moved into an AI lane survived the placement oracle")
    mutated = copy.deepcopy(builds[0])
    changed = False
    mutation_objects = {o["Id"]: o for o in mutated["Objects"]}
    for item in mutated["Objects"]:
        hall_model = mutation_objects.get(item["Parent"])
        hall_index = hall_model and hall_model["Attrs"].get("Level2_HallIndex")
        hall_record = next((h for h in mutated["Layout"]["Halls"] if h["Index"] == hall_index), None)
        if item["Name"].startswith("Level 2 Hall Sill ") and item["ClassName"] == "Part" \
                and hall_record and abs(bounds(item)[1][1] - (hall_record["FloorY"] - 2)) <= .05:
            side = item["Name"].rsplit(" ", 1)[-1]
            w, cf = (0 if side in {"North", "South"} else 2), frame(item["CFrame"])
            key = "XYZ"[max(range(3), key=lambda k: abs(cf[3 + 3*w + k]))]   # the object axis that runs along the wall
            item["Size"][key] -= 1
            changed = True
            break
    assert changed, "no hall mouth sill available for collar-rectangle mutation"
    try:
        check_snapshot(mutated, components, slides)
    except AssertionError as error:
        assert "sill differs from collar rectangle" in str(error), \
            f"collar rectangle mutation failed for the wrong reason: {error}"
    else:
        raise AssertionError("a one-stud gap beside the collar survived the wall aperture oracle")
    # R1 rules, each proven to fire on the defect it was written for (in memory only).
    def mutate(pick, change, expect, label):
        mutated = copy.deepcopy(builds[0])
        target = next(o for o in mutated["Objects"] if pick(o))
        change(target, mutated)
        try:
            check_snapshot(mutated, components, slides)
        except AssertionError as error:
            assert expect in str(error), f"{label} mutation failed for the wrong reason: {error}"
        else:
            raise AssertionError(f"{label} survived its oracle")
        print(f"PASS mutation: {label} rejected in memory")

    def shift(o, mutated, axis, amount):
        o["CFrame"]["$cframe"][axis] += amount

    def door_into_wall(o, mutated):
        spawn = next(x for x in mutated["Objects"] if x["Name"] == "ElevatorSpawn")
        look = [-spawn["CFrame"]["$cframe"][i] for i in (5, 8, 11)]
        axis = max(range(3), key=lambda k: abs(look[k]))
        o["CFrame"]["$cframe"][axis] -= .95 * (1 if look[axis] > 0 else -1)
    mutate(lambda o: o["Attrs"].get("Level2_KitComponent") == "ArrivalDoor" and o["ClassName"] == "MeshPart",
           door_into_wall, "off the wall face", "ArrivalDoor pushed back into the wall (old .8 offset)")
    mutate(lambda o: o["ClassName"] == "MeshPart" and re.fullmatch(r"CoveBase(16|32|64)", o["Attrs"].get("Level2_KitComponent", "")),
           lambda o, m: shift(o, m, 1, -20), "base cove", "a base cove run piece removed from its wall foot")
    mutate(lambda o: o["Name"].startswith("Level 2 Passage Mouth Step ") and abs(o["Size"]["Y"] - 1.5) < 1e-6,
           lambda o, m: shift(o, m, 1, -20), "mouth riser", "a pipe mouth step removed (the 1-stud curb returns)")
    def stop_into_pipe_mouth(o, mutated):
        # The R1 review defect: a square corner's cove stop standing in the other wall's pipe mouth. A copy of
        # one of the hall's stops goes 3 studs in front of its East pipe opening (the original stays, so the
        # base-cove continuity is untouched and the opening rule is what must fire).
        index = hall_ids[o["Parent"]]
        c = next(c for c in mutated["Layout"]["Corridors"] if c["Kind"] == "Narrow" and c["Axis"] == "X"
                 and first_of(c) == index)
        copy_ = copy.deepcopy(o)
        copy_["Id"] = max(x["Id"] for x in mutated["Objects"]) + 1 if isinstance(o["Id"], int) else o["Id"] + "-stop"
        copy_["CFrame"]["$cframe"][:3] = [c["From"] - 3, c["FromY"] + DECK_TOP, c["Cross"]]
        mutated["Objects"].append(copy_)
        world = next(x for x in mutated["Objects"] if x["Id"] == mutated["Manifest"]["World"]["$instance"])
        world["Attrs"]["Level2_WorldDescendants"] += 1
    hall_ids = {x["Id"]: x["Attrs"]["Level2_HallIndex"] for x in builds[0]["Objects"] if x["Attrs"].get("Level2_HallIndex")}
    halls0 = {h["Index"]: h for h in builds[0]["Layout"]["Halls"]}
    first_of = lambda c: min((c["A"], c["B"]), key=lambda i: halls0[i]["Center"]["X"])
    firsts = {first_of(c) for c in builds[0]["Layout"]["Corridors"] if c["Kind"] == "Narrow" and c["Axis"] == "X"}
    mutate(lambda o: o["ClassName"] == "MeshPart" and o["Attrs"].get("Level2_KitComponent", "").startswith("CoveBaseStop_")
           and hall_ids.get(o["Parent"]) in firsts,
           stop_into_pipe_mouth, "is intruded by", "a cove stop moved into a pipe mouth (R1 review)")
    mutate(lambda o: o["Name"] == "Step Ground 1" and o["Attrs"].get("Level2_KitComponent", "").startswith("PoolSteps_"),
           lambda o, m: shift(o, m, 1, -1.2), "check 5", "a pool step sunk to the basin floor (lip or buried, R1 review)")
    toward_wall = {"North": (2, -.5), "South": (2, .5), "West": (0, -.5), "East": (0, .5)}
    mutate(lambda o: o["Name"].startswith("Level 2 Run Deck "),
           lambda o, m: shift(o, m, *toward_wall[o["Name"].rsplit(" ", 1)[1]]),
           "walkway deck/wall seam", "a ring deck pushed .5 into its wall (into the collar at a door)")
    # WP7 rules, each proven to fire on the defect it was written for (in memory only).
    is_kit = lambda o, name: o["Attrs"].get("Level2_KitComponent", "").startswith(name)

    def mutate_dressing(build, pick, change, expect, label):
        mutated = copy.deepcopy(build)
        target = pick(mutated["Objects"])
        change(target, mutated)
        try:
            check_dressing(mutated, components)
        except AssertionError as error:
            assert expect in str(error), f"{label} mutation failed for the wrong reason: {error}"
        else:
            raise AssertionError(f"{label} survived its oracle")
        print(f"PASS mutation: {label} rejected in memory")
    spiral_build = next(b for b in builds if any(is_kit(o, "SpiralStairWell_") for o in b["Objects"]))
    mutate_dressing(spiral_build,
                    lambda objs: max((o for o in objs if o["Name"].startswith("Stair Ground") and is_kit(o, "SpiralStairWell_")),
                                     key=lambda o: bounds(o)[1][1]),
                    lambda o, m: shift(o, m, 1, 1), "F8", "the spiral's top tread raised one stud toward the opening (C-13)")
    bay_build = next(b for b in builds if any(is_kit(o, "VaultBay32_") for o in b["Objects"]))

    def bay_pier(objs):
        bay = next(o for o in objs if is_kit(o, "VaultBay32_") and o["ClassName"] == "MeshPart")
        low, high = bounds(bay)
        return min((o for o in objs if is_kit(o, "VaultPier") and o["ClassName"] == "Part" and o.get("Transparency", 0) < 1),
                   key=lambda o: math.dist(position(o)[::2], (low[0], low[2])))
    mutate_dressing(bay_build, bay_pier, lambda o, m: shift(o, m, 0, 200), "has no pier", "a vault bay's corner pier removed")
    mutate_dressing(builds[0], lambda objs: next(o for o in objs if is_kit(o, "DrainHole")), lambda o, m: shift(o, m, 1, .5),
                    "off its basin surface", "a drain lifted .5 off the basin (the old float)")

    def column_by_deck(objs):
        decks = {o["Parent"]: o for o in objs if o["Name"].startswith("Level 2 Run Deck ")}
        return next(o for o in objs if o["ClassName"] == "Model" and is_kit(o, "Column_D10") and o["Parent"] in decks)

    def onto_deck(o, mutated):
        deck = next(x for x in mutated["Objects"] if x["Name"].startswith("Level 2 Run Deck ") and x["Parent"] == o["Parent"])
        o["WorldPivot"]["$cframe"][0], o["WorldPivot"]["$cframe"][2] = deck["CFrame"]["$cframe"][0], deck["CFrame"]["$cframe"][2]
    mutate_dressing(builds[0], column_by_deck, onto_deck, "stands on", "a column moved onto the ring deck (F4-walkway-band)")
    pool_build = next(b for b in builds if any(o["Name"].startswith("Level 2 Hall Round Light ") for o in b["Objects"]))

    def first_round_light(objs):
        return next(o for o in objs if o["Name"].startswith("Level 2 Hall Round Light "))

    def darken_pool(o, mutated):
        mutated["Objects"] = [x for x in mutated["Objects"] if x["Name"] != o["Name"] and x["Parent"] != o["Id"]]
    mutate_dressing(pool_build, first_round_light, darken_pool, "lit LightRounds", "one BigPool's round lights removed (F4-A dark pool)")

    def paired_void(objs):
        """A high Void Back sharing its hall and wall plane with another (None when no hall has a pair)."""
        by_id = {o["Id"]: o for o in objs}

        def hall_of(o):
            parent = o["Parent"]
            while parent in by_id and not by_id[parent]["Attrs"].get("Level2_HallIndex"):
                parent = by_id[parent]["Parent"]
            return parent
        backs = [o for o in objs if o["Name"] == "Void Back" and bounds(o)[0][1] > 18]
        for o in backs:
            for x in backs:
                if x is not o and hall_of(x) == hall_of(o) and any(abs(position(x)[i] - position(o)[i]) < .1 for i in (0, 2)):
                    return o
        return None
    void_build = next((b for b in builds if paired_void(b["Objects"])), None)
    assert void_build is not None, "no seed in the run has two voids on one wall; the F10 height rule is untested"

    def mutate_swerve(pick, expect, label):
        mutated = copy.deepcopy(builds[0])
        pick(mutated)
        try:
            check_swerve_world(mutated, components)
        except AssertionError as error:
            assert expect in str(error), f"{label} mutation failed for the wrong reason: {error}"
        else:
            raise AssertionError(f"{label} survived its oracle")
        print(f"PASS mutation: {label} rejected in memory")

    def drop(name):
        def pick(mutated):
            mutated["Objects"] = [o for o in mutated["Objects"] if o["Name"] != name]
        return pick

    def column_into_corner(mutated):
        h = next(h for h in mutated["Layout"]["Halls"] if h.get("Swerve")
                 and any(seg["Kind"] == "Corner" and seg["R"] for seg in h["Swerve"]["Loop"]))
        seg = next(seg for seg in h["Swerve"]["Loop"] if seg["Kind"] == "Corner" and seg["R"])
        hi_x, hi_z = CORNER_KEYS[seg["Corner"]]
        room = next(o["Id"] for o in mutated["Objects"] if o["ClassName"] == "Model"
                    and o["Attrs"].get("Level2_HallIndex") == h["Index"])
        column = next(o for o in mutated["Objects"] if o["ClassName"] == "Model" and o["Parent"] == room
                      and o["Attrs"].get("Level2_KitComponent", "").startswith("Column_D10"))
        column["WorldPivot"]["$cframe"][0] = h["MaxX"] - 6 if hi_x else h["MinX"] + 6
        column["WorldPivot"]["$cframe"][2] = h["MaxZ"] - 6 if hi_z else h["MinZ"] + 6
    mutate_swerve(drop("Swerve Wall Block 5"), "wall coverage", "every 'Swerve Wall Block 5' removed (F9 face collision)")
    mutate_swerve(drop("Swerve Deck Ground 5"), "deck coverage", "every 'Swerve Deck Ground 5' removed (F9 deck ground)")
    mutate_swerve(column_into_corner, "off the deck front", "a column moved into an arc's dead corner (F9 Keepout)")
    mutate_dressing(void_build, paired_void, lambda o, m: shift(o, m, 1, 1), "voids on one wall",
                    "one of two same-wall voids raised a stud (F10)")
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() == h for p,h in before.items()), "read-only input changed during test"
    print(f"PASS {len(builds)} seeds: independent world contract + actual Objective validateManifest + actual Exit structural suite")
    print("PASS mutation: invisible completion-sensor thickness 9 -> 1 rejected, restored only in memory")
    print("PASS mutation: dressing collider moved into an AI lane rejected in memory")
    print("PASS mutation: one-stud collar-side gap rejected in memory")
    print("PASS missing/not-ready installed kit rejection; no files written by execution")
    print(f"Poolrooms KIT_SPEC world budget: {min(totals)}..{max(totals)} descendants vs <={WORLD_BUDGET} budget (G8)")
    corner_cove_mutation(binary, components, slides, seeds[:3])
    check_install_contract(builds, components, args.installed_kit)
    print("UNVERIFIED: Roblox convex decomposition, first slide ray hit, pump line of sight, real body-box pathfinding, multiplayer spawn safety, streaming, terrain voxels/swim threshold, CPU/memory and mobile frame time")


if __name__ == "__main__":
    main()
