"""Execute v2 room weighting/cable geometry from fresh offline candidates."""

from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRAFT = ROOT / "drafts/level1-quality-20261002"
BEFORE = ROOT / "artifacts/level1-quality-20261002/live-before/ServerScriptService/Level 1 Systems"


def block(text, start, end):
    assert text.count(start) == 1, start
    first = text.index(start)
    return text[first:text.index(end, first)]


def main():
    renderer = (DRAFT / "BlenderRoomRenderer.ModuleScript.lua").read_text(encoding="utf-8")
    puzzle = (DRAFT / "PuzzleManager.Script.lua").read_text(encoding="utf-8")
    maze = (DRAFT / "MazeGenerator.Script.lua").read_text(encoding="utf-8")
    old_maze = (BEFORE / "MazeGenerator.Script.lua").read_text(encoding="utf-8")
    old_puzzle = (BEFORE / "PuzzleManager.Script.lua").read_text(encoding="utf-8")
    assert block(maze, "local wallV, wallH", 'local maze = Instance.new("Model")') == block(old_maze, "local wallV, wallH", 'local maze = Instance.new("Model")'), "random topology changed"
    for start, end in [
        ("local function showFuseInBox(", "local function makeLever("),
        ("local function makeLever(", "local function makeExit("),
        ("local function finishFuseExtraction(", "-- One workspace sweep"),
    ]:
        assert block(puzzle, start, end) == block(old_puzzle, start, end), "objective authority changed: " + start

    program = r'''
local checks=0
local function check(value,message) assert(value,message);checks+=1 end
local Vector3={}
local vectorMeta={}
vectorMeta.__index=function(v,key)
 if key=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
end
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end
vectorMeta.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__mul=function(a,b)
 if type(a)=="number" then return Vector3.new(a*b.X,a*b.Y,a*b.Z) end
 if type(b)=="number" then return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
 return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z)
end
local Renderer={}
local kit
local ServerStorage={FindFirstChild=function(_,name) check(name=="Level1BlenderKitV2","V2 authority kit");return kit end}
'''
    program += block(renderer, 'local KIT_NAME =', 'function Renderer.IsReady()')
    program += block(renderer, 'function Renderer.IsReady()', 'function Renderer.SkinCarriedFuse(')
    program += block(renderer, '-- EXIT_APERTURE_GEOMETRY_BEGIN', '-- EXIT_APERTURE_GEOMETRY_END')
    program += block(puzzle, '-- PREVIEW_CABLE_ROUTER_BEGIN', '-- PREVIEW_CABLE_ROUTER_END')
    program += r'''
local function room(weight,variant)
 return {IsA=function(_,class) return class=="Model" end,
 FindFirstChildWhichIsA=function() return {} end,
 GetAttribute=function(_,key) return key=="SelectionWeight" and weight or key=="Variant" and variant or nil end}
end
check(not Renderer.IsReady(),"missing V2 kit fails closed")
local components={FindFirstChild=function(self,name) return self[name] end}
for _,names in ipairs({PROP_NAMES,SURFACE_NAMES,HARDWARE_NAMES}) do for _,name in ipairs(names) do components[name]=room() end end
local rooms={items={},GetChildren=function(self)return self.items end}
for mask=1,15 do
 local model=room();model.GetAttribute=function(_,key) return key=="OpenMask" and mask or nil end
 rooms.items[#rooms.items+1]=model
end
kit={GetAttribute=function()return true end,FindFirstChild=function(_,name)return name=="Rooms" and rooms or components end}
check(Renderer.IsReady(),"complete V2 kit ready")
components.GridFixture=nil;check(not Renderer.IsReady(),"missing detailed grille blocks launch");components.GridFixture=room()
components.ExitPortal=nil;check(not Renderer.IsReady(),"missing full exit portal blocks launch");components.ExitPortal=room()
local quiet, column=room(16,0),room(1,1)
check(Renderer.PickRoom({quiet,column},0)==quiet,"quiet lower weight bound")
check(Renderer.PickRoom({quiet,column},16/17-.00001)==quiet,"quiet upper weight bound")
check(Renderer.PickRoom({quiet,column},16/17+.00001)==column,"rare column starts at its boundary")
check(Renderer.PickRoom({quiet,column},1)==column,"unit roll is clamped")
check(Renderer.RoomWeight(room(nil,1))==1,"legacy column fallback remains rare")
check(Renderer.RoomWeight(room(-5,0))==0,"disabled variant")
check(Renderer.RoomWeight(room(500,0))==100,"variant weight is bounded")
local disabled=room(0,0)
check(Renderer.PickRoom({disabled,quiet},0)==quiet,"zero-weight room never chosen")
check(not pcall(Renderer.PickRoom,{disabled},.5),"empty active variant set fails closed")
for _,name in ipairs({"Fluorescent","GridFixture","LightFixture"}) do
 local scale,offset,fixture=Renderer.SkinLayout(name,Vector3.new(4.8,.15,4.8),Vector3.new(4,.72,4))
 check(fixture and scale.Y==1,"fixture authored depth survives")
 check(math.abs(offset.Y+.72*.5-.15*.5)<1e-9,"fixture top matches ceiling proxy")
 check(math.abs(scale.X-1.2)<1e-9 and math.abs(scale.Z-1.2)<1e-9,"fixture footprint remains original size")
end
for _,name in ipairs({"ExitDoor","RelayDoor"}) do
 local scale,offset=Renderer.SkinLayout(name,Vector3.new(7,11,.4),Vector3.new(6.8,10.8,.9))
 check(scale.Z==1,"authored door hardware keeps depth")
 check(math.abs(offset.Z+.9*.5-.4*.5)<1e-9,"authored door back face matches proxy")
end
local genericScale,genericOffset=Renderer.SkinLayout("MetalPanel",Vector3.new(2,3,.1),Vector3.new(4,6,.2))
check(genericScale.X==.5 and genericScale.Y==.5 and genericScale.Z==.5,"generic cable/hardware fit stays unchanged")
check(genericOffset.Magnitude==0,"generic proxy frame remains authoritative")

local function box(x,z,w,d,h)
 return {minX=x-w/2,maxX=x+w/2,minZ=z-d/2,maxZ=z+d/2,minY=0,maxY=h or 14}
end
local function validate(path,boxes,label)
 check(path~=nil,label.." route exists")
 for i=1,#path-1 do for _,obstacle in ipairs(boxes) do
  check(not previewWireHits(path[i],path[i+1],obstacle),label.." clears every physical obstacle")
 end end
end
local a,b=Vector3.new(-8,.06,0),Vector3.new(8,.06,0)
local columnBox=box(0,0,2,2)
check(previewWireHits(a,b,columnBox),"column blocks straight cable")
local path=previewWirePlan(a,b,{columnBox})
validate(path,{columnBox},"column")
check(#path>2,"column receives a real detour")
check(path[1]==a and path[#path]==b,"detour preserves exact endpoints")
check(previewWirePlan(Vector3.new(0,.06,0),b,{columnBox})==nil,"inside collider endpoint refuses invalid route")
local relocated=previewWirePoint(Vector3.new(0,.06,0),{columnBox})
check(relocated and not previewWireHits(relocated,relocated,columnBox),"blocked cell waypoint moves to clear carpet")
check(previewWirePlan(a,b,{box(0,0,2,200)})==nil,"local router cannot pretend to cross a closed wall")
local highA,highB=Vector3.new(-8,13.6,0),Vector3.new(8,13.6,0)
check(#previewWirePlan(highA,highB,{box(0,0,2,2,8.5)})==2,"low divider permits overhead cable")
validate(previewWirePlan(highA,highB,{columnBox}),{columnBox},"full-height column overhead")
local pit={minX=-2,maxX=2,minZ=-2,maxZ=2,minY=-1,maxY=1}
validate(previewWirePlan(a,b,{pit}),{pit},"pit footprint")
check(#previewWirePlan(highA,highB,{pit})==2,"ceiling cable may cross void")
math.randomseed(20261002)
for seed=1,40 do
 local obstacles={box(-1+math.random(),-.5+math.random(),1+math.random(),1+math.random()),box(3,1.5,1,1)}
 local z=-1+math.random()*2
 local source,target=Vector3.new(-8,.06,z),Vector3.new(8,.06,-z)
 validate(previewWirePlan(source,target,obstacles),obstacles,"geometry seed"..seed)
end

local function part(position,size,query,collide,rotated)
 local frame={Position=position,GetComponents=function()
  if rotated then return position.X,position.Y,position.Z,0,0,1,0,1,0,-1,0,0 end
  return position.X,position.Y,position.Z,1,0,0,0,1,0,0,0,1
 end}
 return {CFrame=frame,Size=size,CanQuery=query,CanCollide=collide,IsA=function(_,class)return class=="BasePart" end}
end
local falseQueryCollider=part(Vector3.new(4,7,5),Vector3.new(2,14,4),false,true,true)
local floor=part(Vector3.new(0,-.5,0),Vector3.new(24,1,24),true,true)
local visual=part(Vector3.new(0,7,0),Vector3.new(2,14,2),false,false)
local maze={GetDescendants=function()return {falseQueryCollider,floor,visual} end}
local actual=previewWireObstacles(maze,nil,{},14)
check(#actual==1,"false-query physical collider included; carpet/visuals excluded")
check(actual[1].minX==2 and actual[1].maxX==6 and actual[1].minZ==4 and actual[1].maxZ==6,"rotated physical OBB gets conservative world bounds")
local function cardinalFrame(x,y,z,yaw)
 local c,s=math.cos(yaw),math.sin(yaw)
 local frame={X=x,Y=y,Z=z,yaw=yaw}
 frame.GetComponents=function()return x,y,z,c,0,s,0,1,0,-s,0,c end
 frame.ToObjectSpace=function(_,other)
  local dx,dz=other.X-x,other.Z-z
  return cardinalFrame(c*dx-s*dz,other.Y-y,s*dx+c*dz,other.yaw-yaw)
 end
 return frame
end
local exits={
 {cardinalFrame(-479.9,4,276,-math.pi/2),cardinalFrame(-481,7,0,0),Vector3.new(2,14,964)},
 {cardinalFrame(479.9,4,-276,math.pi/2),cardinalFrame(481,7,0,0),Vector3.new(2,14,964)},
 {cardinalFrame(-276,4,-479.9,math.pi),cardinalFrame(0,7,-481,0),Vector3.new(964,14,2)},
 {cardinalFrame(276,4,479.9,0),cardinalFrame(0,7,481,0),Vector3.new(964,14,2)},
}
for index,geometry in ipairs(exits) do
 local bounds=Renderer.ExitBounds(geometry[1],geometry[2],geometry[3])
 check(bounds.minX< -3.5 and bounds.maxX>3.5,"cardinal long boundary spans exit even when wall center is distant "..index)
 check(math.abs(bounds.minY+4)<1e-8 and math.abs(bounds.maxY-10)<1e-8,"cardinal wall bottom/ceiling retained "..index)
 check(math.abs(bounds.minZ-.1)<1e-8 and math.abs(bounds.maxZ-2.1)<1e-8,"cardinal wall depth transformed into exact exit frame "..index)
 local pieces=Renderer.ExitPieces(bounds,7,-4,7.5)
 check(#pieces==3,"exact side/header split for cardinal boundary "..index)
 local volume=0
 for _,piece in ipairs(pieces) do
  volume+=piece.size.X*piece.size.Y*piece.size.Z
  local lowX,highX=piece.center.X-piece.size.X*.5,piece.center.X+piece.size.X*.5
  local lowY=piece.center.Y-piece.size.Y*.5
  check(highX<=-3.5+1e-8 or lowX>=3.5-1e-8 or lowY>=7.5-1e-8,"new physical piece never seals doorway "..index)
 end
 check(math.abs(volume-(964*14-7*11.5)*2)<1e-7,"all original side/header physics remains; only aperture is removed "..index)
 local offPlane={minX=-12,maxX=12,minY=-4,maxY=10,minZ=12,maxZ=13}
 check(Renderer.ExitPieces(offPlane,7,-4,7.5)==nil,"unrelated wall beyond aperture is untouched "..index)
end
local shell={minX=-12,maxX=12,minY=-4,maxY=10,minZ=-.9,maxZ=.1}
local shellPieces=Renderer.ExitPieces(shell,7,-4,7.5)
check(#shellPieces==3 and math.abs(shellPieces[1].size.X-8.5)<1e-8,"only matching24-stud Blender wall receives side/header art")
local adjacent={minX=11,maxX=12,minY=-4,maxY=10,minZ=-12,maxZ=12}
check(Renderer.ExitPieces(adjacent,7,-4,7.5)==nil,"perpendicular neighboring shell remains visible and solid")
local below={minX=-12,maxX=12,minY=-4.2,maxY=10,minZ=-.9,maxZ=.1}
check(#Renderer.ExitPieces(below,7,-4,7.5)==4,"below-floor source material retains its sill")
'''
    program += r'''
local destroyed=0
local function owned()
 return {Parent=true,CanCollide=false,Transparency=1,attributes={},
 SetAttribute=function(self,name,value)self.attributes[name]=value end,
 Destroy=function()destroyed+=1 end}
end
local owner=owned()
local self={apertureCleanups={}}
local native={part=owned()}
local originalCollision=true
local visible=owned()
local hidden={[visible]=0}
local art={model=owned()}
local visuals={owned(),owned()}
local physics,vestibule=owned(),owned()
local restored
'''
    program += block(renderer, 'local function restoreAperture()', 'self.apertureCleanups[owner]=restoreAperture')
    program += r'''
self.apertureCleanups[owner]=restoreAperture
restoreAperture()
check(native.part.CanCollide,"actual aperture cleanup restores the complete native collision wall")
check(visible.Transparency==0,"actual aperture cleanup restores the original wall artwork")
check(destroyed==4,"actual aperture cleanup destroys all cropped artwork and owned physics/vestibule")
check(next(self.apertureCleanups)==nil,"actual aperture cleanup releases its strong owner registry")
restoreAperture();check(destroyed==4,"later owner destruction cannot repeat cleanup after renderer closure")
local order=""
local state={closed=false,skinned={proxy=true},apertureCleanups={restore=function()order..="restore;" end},
 connections={{Disconnect=function()order..="disconnect;" end}}}
local activeState=state
'''
    program += block(renderer, 'function state:Cleanup()', 'connect(maze.Destroying,')
    program += r'''
state:Cleanup()
check(order=="restore;disconnect;","actual renderer closes apertures before disconnecting their owner callbacks")
check(activeState==nil and state.closed,"actual renderer closure releases the active skin")
check(next(state.apertureCleanups)==nil and next(state.skinned)==nil,"actual renderer clears strong aperture/skin references")
state:Cleanup();check(order=="restore;disconnect;","actual renderer closure is idempotent")
print("Level 1 quality: "..checks.." actual-function checks passed; topology/objective authority unchanged")
'''
    with tempfile.TemporaryDirectory(prefix="level1-quality-tests-") as folder:
        target = Path(folder) / "actual-functions.luau"
        target.write_text(program, encoding="utf-8")
        subprocess.run([str(ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe"), str(target)], check=True)


if __name__ == "__main__":
    main()
