"""Run the actual preparation utility in portable Luau with synthetic instances.

This verifies the conservative containment algorithm and transactional guards.
It deliberately makes no native gameplay/streaming/performance claim.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
UTILITY = Path(os.environ.get("GEOMETRY_UTILITY", Path(__file__).with_name("GeometryOptimization.luau")))
LUAU = ROOT / "_local/optimization-20261009/luau-0.741/luau.exe"

MOCK = r'''
local builtinTypeof = typeof
local function typeof(value)
    return type(value) == "table" and value.__type or builtinTypeof(value)
end
local task = {wait = function() end}
local function enum(name)
    return setmetatable({__type="EnumItem", Name=name}, {__tostring=function(self) return self.Name end})
end
local Enum = {
    SurfaceType={Smooth=enum("Enum.SurfaceType.Smooth"),Studs=enum("Enum.SurfaceType.Studs"),Inlet=enum("Enum.SurfaceType.Inlet"),Hinge=enum("Enum.SurfaceType.Hinge")},
    PartType={Block=enum("Enum.PartType.Block"),Cylinder=enum("Enum.PartType.Cylinder")},
    RenderFidelity={Precise=enum("Enum.RenderFidelity.Precise"),Automatic=enum("Enum.RenderFidelity.Automatic")},
    CollisionFidelity={Hull=enum("Enum.CollisionFidelity.Hull")},
    Material={SmoothPlastic=enum("Enum.Material.SmoothPlastic")},
}
local function vec(x,y,z) return {__type="Vector3",X=x,Y=y,Z=z} end
local function cf(x,y,z,rotation)
    local v={x,y,z}; for _, n in ipairs(rotation or {1,0,0,0,1,0,0,0,1}) do table.insert(v,n) end
    return {__type="CFrame",GetComponents=function()return table.unpack(v)end}
end
local function f32(n)local b=buffer.create(4);buffer.writef32(b,0,n);return buffer.readf32(b,0)end
local Vector3={new=function(x,y,z)return vec(f32(x),f32(y),f32(z))end}
local CFrame={new=function(x,y,z,...)
    local r={...};for i=1,#r do r[i]=f32(r[i])end
    return cf(f32(x),f32(y),f32(z),#r>0 and r or nil)
end}
local function json(v)
    if type(v)=="string" then return string.format("%q",v) end
    if type(v)=="number" then return string.format("%.17g",v) end
    if type(v)=="boolean" then return tostring(v) end
    assert(type(v)=="table")
    local rows={}
    if #v>0 then for _,x in ipairs(v) do table.insert(rows,json(x)) end;return "["..table.concat(rows,",").."]" end
    local keys={};for k in pairs(v)do table.insert(keys,k)end;table.sort(keys)
    for _,k in ipairs(keys)do table.insert(rows,json(k)..":"..json(v[k]))end
    return "{"..table.concat(rows,",").."}"
end
local serial=0
local methods={}
local mt={__index=function(self,key)if key=="Parent"then return rawget(self,"_parent")end;return methods[key]end,
    __newindex=function(self,key,value)
        if key~="Parent" then rawset(self,key,value);return end
        local old=rawget(self,"_parent")
        local oldRoot=old;while oldRoot and oldRoot.Parent do oldRoot=oldRoot.Parent end
        if old then for i,p in ipairs(old._children)do if p==self then table.remove(old._children,i);break end end end
        rawset(self,"_parent",value);if value then table.insert(value._children,self)end
        local newRoot=value;while newRoot and newRoot.Parent do newRoot=newRoot.Parent end
        if oldRoot and oldRoot.DescendantRemoving then oldRoot.DescendantRemoving:Fire(self)end
        if newRoot and newRoot.DescendantAdded then newRoot.DescendantAdded:Fire(self)end
    end}
local function instance(class,name,parent)
    serial+=1
    local obj=setmetatable({ClassName=class,Name=name or class,_children={},_attrs={},_tags={},_id=string.format("id_%06d",serial)},mt)
    if class=="Part" or class=="UnionOperation" then
        obj.CFrame=cf(0,0,0);obj.Size=vec(4,4,4);obj.Anchored=true;obj.CanCollide=true;obj.CanQuery=true;obj.CanTouch=false
        obj.CollisionGroup="Default";obj.Material=Enum.Material.SmoothPlastic;obj.MaterialVariant=""
        obj.Color={__type="Color3",R=1,G=1,B=1};obj.Reflectance=0;obj.Transparency=1;obj.CastShadow=false
        obj.Massless=false;obj.RootPriority=0;obj.Archivable=true;obj.Locked=false;obj.Shape=Enum.PartType.Block
        for _,face in ipairs({"TopSurface","BottomSurface","FrontSurface","BackSurface","LeftSurface","RightSurface"})do obj[face]=Enum.SurfaceType.Smooth end
        if class=="UnionOperation"then obj.RenderFidelity=Enum.RenderFidelity.Precise;obj.CollisionFidelity=Enum.CollisionFidelity.Hull;obj.UsePartColor=true;obj.Transparency=0 end
    end
    obj.Parent=parent;return obj
end
function methods:GetDebugId()return self._id end
function methods:GetFullName()return self.Parent and self.Parent:GetFullName().."."..self.Name or self.Name end
function methods:GetChildren()return table.clone(self._children)end
function methods:GetDescendants()
    local result={};local function append(p)for _,c in ipairs(p._children)do table.insert(result,c);append(c)end end;append(self);return result
end
function methods:IsA(name)
    if self.ClassName==name then return true end
    return name=="BasePart" and (self.ClassName=="Part"or self.ClassName=="UnionOperation")
        or name=="LuaSourceContainer" and self.ClassName=="ModuleScript"
end
function methods:GetAttributes()return table.clone(self._attrs)end
function methods:GetAttribute(name)return self._attrs[name]end
function methods:SetAttribute(name,value)self._attrs[name]=value end
function methods:Destroy()for _,child in ipairs(self:GetChildren())do child:Destroy()end;self.Parent=nil;self._destroyed=true end
function methods:GetTags()return table.clone(self._tags)end
function methods:FindFirstChild(name)for _,child in ipairs(self._children)do if child.Name==name then return child end end end
function methods:IsDescendantOf(parent)local current=self.Parent;while current do if current==parent then return true end;current=current.Parent end;return false end
local playing=false
local game=instance("DataModel","game")
local subscriptions=0
local function signal()
    return {listeners={},Connect=function(self,fn)
        local connection={connected=true};self.listeners[connection]=fn;subscriptions+=1
        function connection:Disconnect()if self.connected then self.connected=false;subscriptions-=1 end end
        return connection
    end,Fire=function(self,value)for conn,fn in pairs(self.listeners)do if conn.connected then fn(value)end end end}
end
game.DescendantAdded=signal();game.DescendantRemoving=signal()
game.PlaceId=131311258779917;game.GameId=10559217407
local storage=instance("ServerStorage","ServerStorage",game)
local runService={IsRunning=function()return playing end}
local editorService={GetEditorSource=function(_,obj)return obj.EditorSource or obj.Source end}
function game:GetService(name)
    if name=="ServerStorage"then return storage end
    if name=="RunService"then return runService end
    if name=="ScriptEditorService"then return editorService end
    if name=="HttpService"then return {JSONEncode=function(_,v)return json(v)end}end
    error("unexpected service "..name)
end
local Instance={new=function(class)return instance(class,class)end}
local function fixture()
    for _,obj in ipairs(storage:GetChildren())do obj.Parent=nil end
    for _,obj in ipairs(game:GetChildren())do if obj~=storage then obj.Parent=nil end end
    local world=instance("Model","Level2PoolroomsMap",storage);world._attrs.Level2NewMap=true
    local collision=instance("Model","Collision",world)
    local level6=instance("Model","Level 6 Indoor Playground",storage)
    for _,name in ipairs({"Frame_DeckPads","Frame_Decks","Frame_DecksDeep"})do
        local folder=instance("Folder",name,level6);local union=instance("UnionOperation","mat_blue",folder);union._attrs.L6PBR="foam_floor"
    end
    local outer=instance("Part","Part",collision);outer._attrs.Area="A1"
    local inner=instance("Part","Part",collision);inner._attrs.Area="A1";inner.Size=vec(2,4,4)
    return outer,inner,collision,level6
end
'''

TESTS = r'''
local count=0
local function test(name,fn)
    local ok,err=pcall(fn);assert(ok,name..": "..tostring(err));count+=1;print("PASS "..name)
end
local function prepareCount(mutator,expected)
    local a,b,c,l=fixture();if mutator then mutator(a,b,c,l)end
    local plan=Geometry.Prepare();assert(#plan.Removals==expected,"unexpected contained count "..#plan.Removals)
    assert(#plan.LOD==3);assert(a.Parent==c and b.Parent==c,"Prepare must be read only")
    return plan,a,b,c,l
end
test("exact contained box archives without geometry writes",function()
    local plan,a,b,c=prepareCount(nil,1);local oldcf,oldsize=b.CFrame,b.Size
    local result=Geometry.Apply(plan,"G:/verified-native-before.rblx")
    assert(result.archived==1 and result.lodChanged==3 and #c:GetDescendants()==1)
    assert(b.CFrame==oldcf and b.Size==oldsize and b.Parent==plan.Archive and a.Parent==c)
    Geometry.Rollback(plan);assert(a.Parent==c and b.Parent==c)
    for _,row in ipairs(plan.LOD)do assert(row.Instance.RenderFidelity==Enum.RenderFidelity.Precise)end
end)
test("duplicate tie keeps deterministic existing instance",function()
    local plan,a,b=prepareCount(function(a,b)b.Size=a.Size end,1)
    assert(plan.Removals[1].Before.Instance==b and plan.Removals[1].Keep.Instance==a)
end)
test("touching boxes do not resize into a merged approximation",function()
    prepareCount(function(a,b)b.Size=a.Size;b.CFrame=cf(4,0,0)end,0)
end)
test("even a tiny aperture is preserved",function()
    prepareCount(function(a,b)b.Size=a.Size;b.CFrame=cf(4+2^-40,0,0)end,0)
end)
test("sloped and oriented boxes are excluded",function()
    prepareCount(function(a,b)b.CFrame=cf(0,0,0,{.8660254,0,.5,0,1,0,-.5,0,.8660254})end,0)
end)
test("cylinders are excluded",function()prepareCount(function(a,b)b.Shape=Enum.PartType.Cylinder end,0)end)
test("Area identities never cross",function()prepareCount(function(a,b)b._attrs.Area="A2"end,0)end)
test("hazards and reflector contracts excluded",function()prepareCount(function(a,b)b._attrs.KillZone=true;b.Name="Hazard"end,0)end)
test("guards and barriers excluded",function()prepareCount(function(a,b)b.Name="Barrier"end,0)end)
test("tags exclude semantic instance identities",function()prepareCount(function(a,b)b._tags={"NavSurface"}end,0)end)
test("children exclude attachment identities",function()prepareCount(function(a,b)instance("Attachment","Special",b)end,0)end)
test("CanTouch contract is preserved",function()prepareCount(function(a,b)b.CanTouch=true end,0)end)
test("CanQuery contract is preserved",function()prepareCount(function(a,b)b.CanQuery=false end,0)end)
test("movable instances excluded",function()prepareCount(function(a,b)b.Anchored=false end,0)end)
test("collision groups never cross",function()prepareCount(function(a,b)b.CollisionGroup="Players"end,0)end)
test("external ObjectValue identity excluded",function()
    prepareCount(function(a,b)local ref=instance("ObjectValue","Reference",game);ref.Value=b end,0)
end)
test("external PrimaryPart identity excluded",function()
    prepareCount(function(a,b)local model=instance("Model","External",game);model.PrimaryPart=b end,0)
end)
test("external NoCollisionConstraint identity excluded",function()
    prepareCount(function(a,b)local ref=instance("NoCollisionConstraint","Reference",game);ref.Part0=b end,0)
end)
test("external Highlight identity excluded",function()
    prepareCount(function(a,b)local ref=instance("Highlight","Reference",game);ref.Adornee=b end,0)
end)
test("external CameraSubject identity excluded",function()
    prepareCount(function(a,b)local ref=instance("Camera","Reference",game);ref.CameraSubject=b end,0)
end)
test("full native backup required before mutation",function()
    local plan,a,b,c=prepareCount(nil,1);assert(not pcall(Geometry.Apply,plan,""));assert(a.Parent==c and b.Parent==c)
end)
test("changed collider baseline aborts before writes",function()
    local plan,a,b,c=prepareCount(nil,1);b.Size=vec(1,1,1)
    assert(not pcall(Geometry.Apply,plan,"G:/verified-native-before.rblx"));assert(a.Parent==c and b.Parent==c)
end)
test("changed LOD baseline aborts before writes",function()
    local plan,a,b,c=prepareCount(nil,1);plan.LOD[2].Instance.CanQuery=false
    assert(not pcall(Geometry.Apply,plan,"G:/verified-native-before.rblx"));assert(a.Parent==c and b.Parent==c)
end)
test("renamed scoped LOD folder aborts before writes",function()
    local plan,a,b,c=prepareCount(nil,1);plan.LODFolders[1].Instance.Name="DifferentAuthoringFolder"
    assert(not pcall(Geometry.Apply,plan,"G:/verified-native-before.rblx"));assert(a.Parent==c and b.Parent==c)
end)
test("changed scoped map attributes abort before writes",function()
    local plan,a,b,c=prepareCount(nil,1);plan.World._attrs.Level2NewMap=false
    assert(not pcall(Geometry.Apply,plan,"G:/verified-native-before.rblx"));assert(a.Parent==c and b.Parent==c)
end)
test("Source/editor conflicts abort Prepare",function()
    local a,b,c=fixture();local source=instance("ModuleScript","Runtime",game);source.Source="return world.Collision";source.EditorSource="return altered.Collision"
    assert(not pcall(Geometry.Prepare));assert(a.Parent==c and b.Parent==c)
end)
test("concurrent source edit aborts Apply",function()
    local a,b,c=fixture();local source=instance("ModuleScript","Runtime",game);source.Source="return world.Collision"
    local plan=Geometry.Prepare();source.Source="return other.Collision"
    assert(not pcall(Geometry.Apply,plan,"G:/verified-native-before.rblx"));assert(a.Parent==c and b.Parent==c)
end)
test("new relevant source aborts Apply",function()
    local plan,a,b,c=prepareCount(nil,1);local source=instance("ModuleScript","NewRuntime",game);source.Source="return world.Collision"
    assert(not pcall(Geometry.Apply,plan,"G:/verified-native-before.rblx"));assert(a.Parent==c and b.Parent==c)
end)
test("new explicit identity reference aborts Apply",function()
    local plan,a,b,c=prepareCount(nil,1);local ref=instance("ObjectValue","NewReference",game);ref.Value=b
    assert(not pcall(Geometry.Apply,plan,"G:/verified-native-before.rblx"));assert(a.Parent==c and b.Parent==c)
end)
test("source inserted during yielding scan is rejected and watchers cleaned",function()
    local a,b,c,l=fixture();for i=1,1100 do instance("Part","Noise",l)end
    local plan=Geometry.Prepare();local fired=false
    task.wait=function()
        if not fired then fired=true;local source=instance("ModuleScript","ArrivedDuringScan",game);source.Source="return world.Collision"end
    end
    assert(not pcall(Geometry.Apply,plan,"G:/verified-native-before.rblx"));task.wait=function()end
    assert(fired and a.Parent==c and b.Parent==c and subscriptions==0)
end)
test("owner Play session is never mutated",function()
    local a,b,c=fixture();playing=true;assert(not pcall(Geometry.Prepare));playing=false;local plan=Geometry.Prepare()
    playing=true;assert(not pcall(Geometry.Apply,plan,"G:/verified-native-before.rblx"));playing=false
    assert(a.Parent==c and b.Parent==c)
end)
test("signed permutation boxes remain eligible",function()
    prepareCount(function(a,b)b.CFrame=cf(0,0,0,{-1,0,0,0,1,0,0,0,-1})end,1)
end)
test("separate noncontained partial overlaps preserved",function()
    prepareCount(function(a,b)b.Size=a.Size;b.CFrame=cf(2,0,0)end,0)
end)
test("manifest has exact identity, parent and before properties",function()
    local plan=prepareCount(nil,1);local m=Geometry.Manifest(plan,1,250)
    assert(m.total==4 and #m.rows==4 and m.rows[1].before.id and m.rows[1].before.parentId)
    assert(m.rows[1].before.fingerprint and m.rows[1].survivor.fingerprint)
end)
test("rollback preserves unrelated property edits",function()
    local plan,a,b,c=prepareCount(nil,1);Geometry.Apply(plan,"G:/verified-native-before.rblx")
    local union=plan.LOD[1].Instance;union.CanQuery=false;Geometry.Rollback(plan)
    assert(union.CanQuery==false and union.RenderFidelity==Enum.RenderFidelity.Precise and b.Parent==c)
end)
test("exception after partial writes restores collision and LOD",function()
    local a,b,c,l=fixture();local source=instance("ModuleScript","Runtime",game);source.Source="return world.Collision"
    for i=1,600 do instance("UnionOperation","extra_"..i,l:FindFirstChild("Frame_DeckPads"))end
    local plan=Geometry.Prepare();local fired=false
    task.wait=function()
        if not fired and plan.Archive and plan.Archive.Parent==storage then
            fired=true;source.Source="return changed.Collision"
        end
    end
    assert(not pcall(Geometry.Apply,plan,"G:/verified-native-before.rblx"));task.wait=function()end
    assert(fired and plan.Phase=="rolledBack" and a.Parent==c and b.Parent==c)
    assert(source.Source=="return changed.Collision","concurrent source work must survive rollback")
    for _,row in ipairs(plan.LOD)do assert(row.Instance.RenderFidelity==Enum.RenderFidelity.Precise)end
end)
if Geometry.PrepareExactMerges then
test("exact contiguous native-float merge preserves occupied union",function()
    local plan,a,b,c=prepareCount(function(a,b)b.Size=a.Size;b.CFrame=cf(4,0,0)end,0)
    assert(#plan.Merges==1 and #plan.Merges[1].Before==2)
    local report=Geometry.Apply(plan,{ownerExplicitlyForbidsNewBackups=true,ownerInstruction="Owner explicitly instructed: Do not take backups."})
    assert(report.nativeBackupReceipt==false and report.nativeBackupOwnerException.ownerExplicitlyForbidsNewBackups)
    assert(#c:GetChildren()==1 and plan.Merges[1].Proxy.Size.X==8 and plan.Merges[1].Proxy.CFrame:GetComponents()==2)
    assert(a.Parent==plan.Archive and b.Parent==plan.Archive)
    Geometry.Rollback(plan);assert(a.Parent==c and b.Parent==c and plan.Merges[1].Proxy._destroyed)
end)
test("nonrepresentable native merge endpoints are rejected",function()
    local plan=prepareCount(function(a,b)a.Size=vec(4,4,4);b.Size=vec(4,4,4);a.CFrame=cf(70000,0,0);b.CFrame=cf(70000+1/128,0,0)end,0)
    assert(#plan.Merges==0,"float midpoint must not round the occupied volume")
end)
test("default passive Studs/Inlet surfaces permit same-rotation merge",function()
    local plan=prepareCount(function(a,b)
        for _,p in ipairs({a,b})do p.TopSurface=Enum.SurfaceType.Studs;p.BottomSurface=Enum.SurfaceType.Inlet end
        b.Size=a.Size;b.CFrame=cf(4,0,0)
    end,0)
    assert(#plan.Merges==1)
end)
test("different world-face passive surfaces cannot merge",function()
    local plan=prepareCount(function(a,b)
        for _,p in ipairs({a,b})do p.TopSurface=Enum.SurfaceType.Studs;p.BottomSurface=Enum.SurfaceType.Inlet end
        b.Size=a.Size;b.CFrame=cf(4,0,0,{1,0,0,0,-1,0,0,0,-1})
    end,0)
    assert(#plan.Merges==0)
end)
test("active joint-making surfaces are excluded",function()
    local plan=prepareCount(function(a,b)a.TopSurface=Enum.SurfaceType.Hinge;b.TopSurface=Enum.SurfaceType.Hinge;b.Size=a.Size;b.CFrame=cf(4,0,0)end,0)
    assert(#plan.Merges==0)
end)
test("apertures never enter exact merge groups",function()
    local plan=prepareCount(function(a,b)b.Size=a.Size;b.CFrame=cf(4+2^-40,0,0)end,0)
    assert(#plan.Merges==0)
end)
test("merge failure after proxy creation restores every original",function()
    local plan,a,b,c,l=prepareCount(function(a,b)b.Size=a.Size;b.CFrame=cf(4,0,0)end,0)
    for i=1,600 do instance("UnionOperation","added",l:FindFirstChild("Frame_DeckPads"))end
    -- Reprepare because added LOD geometry must be included in the fresh baseline.
    plan=Geometry.Prepare();local source=instance("ModuleScript","Runtime",game);source.Source="return world.Collision";plan=Geometry.Prepare()
    local fired=false;task.wait=function()if not fired and plan.Archive then fired=true;source.Source="return changed.Collision"end end
    assert(not pcall(Geometry.Apply,plan,{ownerExplicitlyForbidsNewBackups=true,ownerInstruction="Owner explicitly instructed: Do not take backups."}))
    task.wait=function()end
    assert(fired and a.Parent==c and b.Parent==c and #c:GetChildren()==2 and plan.Merges[1].Proxy._destroyed)
end)
end
assert(subscriptions==0,"temporary read-only subscriptions leaked")
print("Synthetic contract tests passed: "..count.."; native gameplay/performance NOT tested")
'''

def main():
    source = UTILITY.read_text(encoding="utf-8")
    assert source.endswith("return Geometry\n")
    combined = MOCK + source.removesuffix("return Geometry\n") + TESTS
    with tempfile.TemporaryDirectory(prefix="geometry-luau-") as temp:
        probe = Path(temp) / "geometry_contract_test.luau"
        probe.write_text(combined, encoding="utf-8")
        result = subprocess.run([str(LUAU), str(probe)], cwd=ROOT, capture_output=True, text=True)
    print(result.stdout, end="")
    print(result.stderr, end="")
    raise SystemExit(result.returncode)

if __name__ == "__main__":
    main()
