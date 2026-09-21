"""Run the real Level 2 tile-texturing call sites offline and check which faces survive.

Configuration.Performance.CullHiddenTileFaces decides whether the World Builder
textures all six faces of every tiled part or only the faces it can prove a
player may see. This extracts the actual Luau blocks -- the texture primitives,
makeWallWithGaps, makeColumn, the corridor shell walls and the Ring Corridor
hall arches -- runs each of them twice under a fake Instance API with the switch
flipped, and compares the emitted Texture instances.

It checks face SELECTION, not rendering: whether a kept face is genuinely the
one you see, and whether a dropped one is genuinely buried, is a Studio
screenshot, not an offline claim. Part poses are asserted unchanged so the
switch can never move geometry.
"""
import os, re, shutil, subprocess, tempfile
from pathlib import Path
from test_level3_slide_aperture import HOST as SHARED_HOST

ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / 'ServerScriptService/Level 2 Systems'
BUILDER = SYSTEMS / 'Level 2 World Builder.ModuleScript.lua'
CONFIG = SYSTEMS / 'Level 2 Configuration.ModuleScript.lua'

ALL_SIX = frozenset({'Right', 'Left', 'Back', 'Front', 'Top', 'Bottom'})
# Face -> (axis index, outward sign), so "is this the face pointing at X" is a
# geometric question about the emitted box rather than a copy of the builder.
NORMALS = {'Right': (0, 1), 'Left': (0, -1), 'Top': (1, 1),
           'Bottom': (1, -1), 'Back': (2, 1), 'Front': (2, -1)}


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


HOST = SHARED_HOST.split('local nodes={};local Instance={}')[0] + r'''
Color3.new=function(...) return {...} end
cm.__mul=function(a,b)
    if getmetatable(b)==cm then
        return CFrame.fromMatrix(a.Position+a:VectorToWorldSpace(b.Position),
            a:VectorToWorldSpace(b.X),a:VectorToWorldSpace(b.Y),a:VectorToWorldSpace(b.Z))
    end
    return a.Position+a:VectorToWorldSpace(b)
end
function CFrame.lookAt(p,target,up)
    local look=(target-p).Unit
    local x=look:Cross(up or Vector3.yAxis).Unit
    return CFrame.fromMatrix(p,x,x:Cross(look).Unit,-look)
end
function CFrame.Angles(rx,ry,rz)
    return CFrame.fromAxisAngle(Vector3.xAxis,rx or 0)
        *CFrame.fromAxisAngle(Vector3.yAxis,ry or 0)
        *CFrame.fromAxisAngle(Vector3.zAxis,rz or 0)
end
Enum.NormalId.Top="Top";Enum.NormalId.Bottom="Bottom"
Enum.Material.CeramicTiles="CeramicTiles";Enum.Material.Glass="Glass";Enum.Material.Neon="Neon"
Enum.PartType={Cylinder="Cylinder",Ball="Ball",Block="Block"}
function Enum.NormalId:GetEnumItems() return {"Right","Left","Back","Front","Top","Bottom"} end
local emitted={}
local Instance={}
function Instance.new(class)
    local node={ClassName=class,Attributes={},Children={},CanCollide=true,CanQuery=true,CanTouch=true}
    node.Id=#emitted+1
    function node:SetAttribute(k,v) self.Attributes[k]=v end
    function node:FindFirstChild(name)
        for _,child in ipairs(self.Children) do if child.Name==name then return child end end
        return nil
    end
    setmetatable(node,{__newindex=function(t,k,v)
        rawset(t,k,v)
        if k=="Parent" and type(v)=="table" and v.Children then table.insert(v.Children,t) end
    end})
    table.insert(emitted,node);return node
end
local function container() return {Children={},Attributes={}} end
-- Real kids tile slots, so the kids branch of surfaceFor is exercised too.
local ReplicatedStorage={}
function ReplicatedStorage:FindFirstChild(name)
    if name~="Level 2 Assets" then return nil end
    local slots={}
    function slots:FindFirstChild(_)
        return {Value="1234567",IsA=function(_,class) return class=="StringValue" end}
    end
    return slots
end
local ServerStorage={FindFirstChild=function() return nil end}
local AssetService={}
local Terrain={FillBlock=function() end}
local Configuration=(function()
__CONFIG__
end)()
local C=Configuration.Colors
__PRIMITIVES__
__WALLS__
local function columnRegistryFor(_) return {} end
local function getColumnFlareTemplate(_,_) return nil end
local function addColumnBaseFlareCollision(_,_,_,_,_) end
__COLUMN__
__ARCHES__
local function vec(v) return string.format("%.17g,%.17g,%.17g",v.X,v.Y,v.Z) end
local cursor=1
local function output(id)
    while cursor<=#emitted do
        local n=emitted[cursor]
        if n.ClassName=="Texture" then
            print(table.concat({"TEX",id,tostring(n.Parent and n.Parent.Id or -1),tostring(n.Face)},"|"))
        elseif n.CFrame and n.Size then
            print(table.concat({"PART",id,tostring(n.Id),n.Name,vec(n.CFrame.Position),vec(n.Size)},"|"))
        end
        cursor+=1
    end
end

local function hallFor(role,width,depth)
    return {Id="H",Index=3,Role=role,Width=width,Depth=depth,KidsColorIndex=2,LocalSeed=7,
        Center=Vector3.new(0,0,0),MinX=-width/2,MaxX=width/2,MinZ=-depth/2,MaxZ=depth/2}
end
local WALLS={
    {"West","Z",function(h) return h.MinX end,function(h) return h.MinZ end,function(h) return h.MaxZ end},
    {"East","Z",function(h) return h.MaxX end,function(h) return h.MinZ end,function(h) return h.MaxZ end},
    {"North","X",function(h) return h.MinZ end,function(h) return h.MinX end,function(h) return h.MaxX end},
    {"South","X",function(h) return h.MaxZ end,function(h) return h.MinX end,function(h) return h.MaxX end},
}
for _,role in ipairs({"Slide Hall","Kids Area"}) do
    for _,gaps in ipairs({{},{0},{-40,50}}) do
        for _,wall in ipairs(WALLS) do
            local hall=hallFor(role,200,180)
            local flume=(wall[1]=="East" and #gaps==2)
                and {center=-20,width=18,bottom=6,top=24} or nil
            makeWallWithGaps(container(),hall,"Level 2 Hall "..wall[1].." Wall",wall[2],
                wall[3](hall),wall[4](hall),wall[5](hall),gaps,hallHeight(hall),-6,flume)
            output(table.concat({"wall",role,wall[1],tostring(#gaps),tostring(flume~=nil)},","))
        end
    end
end

for _,essential in ipairs({false,true}) do
    makeColumn(container(),Vector3.new(12,-2,-30),34,5.5,essential,0)
    output("column,"..tostring(essential))
end

for _,alongX in ipairs({true,false}) do
    for _,kids in ipairs({false,true}) do
        local parent=container()
        local width,gapLength,depth=Configuration.CorridorWidth,60,1.5
        local height=Configuration.CorridorHeight
        local center=Vector3.new(0,0,0)
        local kidsStyleHall=kids and hallFor("Kids Area",120,120) or nil
        local function oriented(x,z)
            if alongX then return Vector3.new(x,0,z) end
            return Vector3.new(z,0,x)
        end
        local function orientedSize(along,y,across)
            if alongX then return Vector3.new(along,y,across) end
            return Vector3.new(across,y,along)
        end
        local function corridorSkin(name,cf,size,normalColor,faces,studs)
            if kidsStyleHall then
                return surfaceFor(kidsStyleHall,parent,name,cf,size,nil,faces,studs)
            end
            return tiledPart(parent,name,cf,size,normalColor,faces,studs)
        end
__CORRIDOR__
        output("corridor,"..tostring(alongX)..","..(kids and "kids" or "tiled"))
    end
end

do
    local hall=hallFor("Standard",210,170)
    local hallModel=container()
    local height,depth=hallHeight(hall),Configuration.ShallowPoolDepth
__RING__
    output("ring")
end
'''


def build(binary, cull):
    source = BUILDER.read_text(encoding='utf-8')
    config = CONFIG.read_text(encoding='utf-8')
    if not cull:
        config, swaps = re.subn(r'(CullHiddenTileFaces\s*=\s*)true', r'\1false', config)
        assert swaps == 1, 'Configuration must hold exactly one CullHiddenTileFaces switch'
    program = (HOST
               .replace('__CONFIG__', config)
               .replace('__PRIMITIVES__', section(source, 'local function part(parent, name, cframe',
                                                  '-- Water depth for a hall, or nil'))
               .replace('__WALLS__', section(source, 'local function makeWallWithGaps(',
                                             '-- ── floors, ceilings, water'))
               .replace('__COLUMN__', section(source, 'local function makeColumn(',
                                              "-- Move a tall object's complete footprint"))
               .replace('__ARCHES__', section(source, 'local function archOffset(',
                                              'local function makeRail('))
               .replace('__CORRIDOR__', section(source, '\t-- Walls reach below the waterline',
                                                '\t-- Dense arch rings:'))
               .replace('__RING__', section(source, 'elseif archetype == "Ring Corridor" then',
                                            'elseif archetype == "Pump Station" then')
                        .split('\n', 1)[1]))
    with tempfile.TemporaryDirectory(prefix='l2-faces-') as folder:
        path = Path(folder) / 'faces.luau'
        path.write_text(program, encoding='utf-8')
        result = subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise AssertionError(result.stderr)
    cases = {}
    for line in result.stdout.splitlines():
        columns = line.split('|')
        case = cases.setdefault(columns[1], {'order': [], 'parts': {}, 'faces': {}})
        if columns[0] == 'PART':
            case['order'].append(int(columns[2]))
            case['parts'][int(columns[2])] = (columns[3],
                                              tuple(map(float, columns[4].split(','))),
                                              tuple(map(float, columns[5].split(','))))
        else:
            case['faces'].setdefault(int(columns[2]), set()).add(columns[3])
    # Instance ids differ between the two runs (one builds more Textures), so
    # collapse each case to creation-ordered rows of (pose, faces) and compare
    # those. Identical pose lists are themselves the proof that the switch moved
    # no geometry.
    return {name: [(case['parts'][i], case['faces'].get(i, set())) for i in case['order']]
            for name, case in cases.items()}


def main():
    binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
    if not binary:
        raise SystemExit('Set LUAU_BIN or put luau on PATH')
    off, on = build(binary, False), build(binary, True)
    checks = 0
    thickness = float(re.search(r'WallThickness = ([.0-9]+)',
                                CONFIG.read_text(encoding='utf-8')).group(1))

    def check(value, message):
        nonlocal checks
        checks += 1
        if not value:
            raise AssertionError(message)

    check(set(off) == set(on), 'both runs build the same cases')
    before = after = 0
    for case, plain in off.items():
        culled = on[case]
        check([pose for pose, _ in plain] == [pose for pose, _ in culled],
              case + ': the switch changes textures only, never a part pose')
        # Kids rooms already picked two faces from the part's own proportions,
        # so the old default is six only on the plain tiled path.
        old_default = 2 if ('Kids Area' in case or 'kids' in case) else 6
        for ((part_name, center, size), was), (_, now) in zip(plain, culled):
            check(now <= was, case + ': culling only ever removes faces')
            check(bool(now) == bool(was), case + ': no part loses its texturing entirely')
            before += len(was)
            after += len(now)
            if not now:
                continue
            if not any(k in part_name for k in ('Lintel', 'Sill', 'Header', 'Ceiling', 'Vault')):
                check(len(was) == old_default,
                      case + ': switch off reproduces the old default on ' + part_name)
            if case.startswith('wall,Kids Area'):
                check(now == was, case + ': kids rooms keep their own two-face rule')
            elif case.startswith('wall,'):
                side = case.split(',')[2]
                room_face = {'West': 'Right', 'East': 'Left',
                             'North': 'Back', 'South': 'Front'}[side]
                run = 2 if side in ('West', 'East') else 0
                low, high = (-90, 90) if run == 2 else (-100, 100)
                outer_low = low - thickness / 2 - .85
                outer_high = high + thickness / 2 + .85
                ends = ('Left', 'Right') if run == 0 else ('Front', 'Back')
                if any(k in part_name for k in ('Lintel', 'Sill', 'Header')):
                    check(now == was, case + ': door lintels/sills/headers are left alone')
                    continue
                # A cut end is kept only where an opening leaves it as a jamb;
                # the ends that run out past the perpendicular wall are dropped.
                expected = {room_face}
                if center[run] - size[run] / 2 > outer_low + 1e-6:
                    expected.add(ends[0])
                if center[run] + size[run] / 2 < outer_high - 1e-6:
                    expected.add(ends[1])
                check(now == expected, f'{case}: {part_name} kept {sorted(now)}, '
                                       f'expected {sorted(expected)}')
            elif case.startswith('column,') and part_name == 'Level 2 Tiled Column':
                expected = ALL_SIX if case.endswith('true') else {'Top', 'Bottom', 'Front', 'Back'}
                check(now == expected,
                      case + ': column barrel/caps -> ' + str(sorted(now)))
            elif case.startswith('corridor,') and part_name == 'Level 2 Corridor Wall':
                check(len(now) == 1, case + ': a corridor shell wall keeps one face')
                axis, sign = NORMALS[next(iter(now))]
                check(sign * center[axis] < 0,
                      case + ': the kept face points back at the corridor centreline')
                check(abs(size[axis] - thickness) < 1e-9,
                      case + ': the kept face is a broad face, not an end')
            elif case == 'ring':
                if 'Arch Rib' in part_name:
                    check(now == {'Left', 'Right', 'Top', 'Bottom'},
                          'ring: a free-standing hall arch keeps all but its segment ends')
                elif 'Vault Strip' in part_name:
                    check(now == {'Bottom'}, 'ring: vault strips unchanged')
    check(after < before, 'the switch must actually remove textures')
    print(f'L2 tile face culling: {checks} checks passed; {len(on)} fixtures; '
          f'{before} textures before, {after} after '
          f'({100 * (before - after) / before:.1f}% removed across the fixtures)')


if __name__ == '__main__':
    main()
