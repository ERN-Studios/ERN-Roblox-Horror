"""Run the actual L2 arch/vault/corridor builders and inspect emitted solids offline.

Reuses the existing Roblox-math host/solid ray helper. This checks geometry, not
Roblox navigation, animated skin bounds, controller behavior or native rendering.
"""
import argparse, math, os, re, shutil, subprocess, tempfile
from pathlib import Path
from test_level3_slide_aperture import HOST as SHARED_HOST, Solid, add, sub, scale, dot

ROOT=Path(__file__).resolve().parents[2]
SYSTEMS=Path('ServerScriptService/Level 2 Systems')
BUILDER=SYSTEMS/'Level 2 World Builder.ModuleScript.lua'
CONFIG=SYSTEMS/'Level 2 Configuration.ModuleScript.lua'
BEFORE=ROOT/'artifacts/trello-20260909/level2-tunnel-before'

def section(s,start,stop):
    at=s.index(start);return s[at:s.index(stop,at)]

HOST=SHARED_HOST.split('local Configuration=__CONFIG__')[0]+r'''
function CFrame.lookAt(p,target,up)
    local look=(target-p).Unit
    local x=look:Cross(up or Vector3.yAxis).Unit
    return CFrame.fromMatrix(p,x,x:Cross(look).Unit,-look)
end
Enum.Material.Neon="Neon";Enum.Material.DiamondPlate="DiamondPlate"
Enum.NormalId.Top="Top";Enum.NormalId.Bottom="Bottom"
function Enum.NormalId:GetEnumItems()return {"Right","Left","Back","Front","Top","Bottom"}end
local Configuration=(function()
__CONFIG__
end)()
local C=Configuration.Colors
local WALKWAY_TOP=__WALKWAY__
local function part(parent,name,cf,size,color,material,transparency)
    local p=Instance.new("Part");p.Parent=parent;p.Name=name;p.CFrame=cf;p.Size=size
    return p
end
local tiledPart=part
local function surfaceFor(hall,...)return part(...)end
local function isKids(hall)return hall.Kids==true end
local function kidsPalette(hall)return {Color={}}end
local function addTexture(...)end
local function addKidsTileTexture(...)end
local function hallFloorY(hall)return 0 end
local function makeStairFlight(...)error("unexpected deep staircase in configured depth cases")end
local function addWater(center,size,name)return part({},"Water "..name,CFrame.new(center),size)end
__ARCHES__
__CORRIDOR__
local function vec(v)return string.format("%.17g,%.17g,%.17g",v.X,v.Y,v.Z)end
local function output(id)
    print("CASE|"..id)
    for _,n in ipairs(nodes)do
        if n.ClassName=="Part"then
            print(table.concat({n.Name,n.CanCollide and "1"or"0",vec(n.CFrame.Position),vec(n.Size),
                vec(n.CFrame.X),vec(n.CFrame.Y),vec(n.CFrame.Z)},"|"))
        end
    end
    table.clear(nodes)
end
for _,axis in ipairs({"X","Z"})do
    for _,kids in ipairs({false,true})do
        for _,drain in ipairs({false,true})do
            for _,length in ipairs({22,44,130})do
                local c={Axis=axis,Width=Configuration.CorridorWidth,From=0,To=length,Cross=0,
                    Index=1,A=1,B=2,DrainGroup=drain and 1 or nil,Kind=length==44 and "PressureDoor"or"Tunnel"}
                local halls={
                    {Center=axis=="X"and Vector3.new(-10,0,0)or Vector3.new(0,0,-10),Kids=kids},
                    {Center=axis=="X"and Vector3.new(length+10,0,0)or Vector3.new(0,0,length+10),Kids=false},
                }
                do
        local hallModel={}
        local hall={Index=2,Width=axis=="X"and 120 or 100,Depth=axis=="X"and 100 or 120,
            Center=Vector3.new(0,0,0),MinX=axis=="X"and -60 or -50,MinZ=axis=="X"and -50 or -60}
        local height=Configuration.WallHeight
        local depth=Configuration.DeepPoolDepth
__RING_HALL__
        output("ring-hall,"..axis)
    end
    makeCorridor({}, {Halls=halls}, c, {})
                output(axis..","..tostring(kids)..","..tostring(drain)..","..length)
            end
        end
    end
    for _,radius in ipairs({13,24})do
        makeArchSpan({},Vector3.new(0,0,0),axis=="X","hall",radius,1.6)
        output("standalone,"..axis..","..radius)
    end
    makeCorridor({}, {Halls={{Center=Vector3.new(-10,0,-10),Kids=false},{Center=Vector3.new(10,0,10),Kids=true}}},
        {Kind="SharedWall",Axis=axis,A=1,B=2,From=0,To=0,Cross=0}, {})
    output("shared,"..axis)
end
'''

def build(binary,root,configuration_overrides=None):
    s=(root/BUILDER).read_text(encoding='utf-8');config=(root/CONFIG).read_text(encoding='utf-8')
    for name,value in (configuration_overrides or {}).items():
        config=re.sub(rf'(\b{name}\s*=\s*)[.0-9]+',lambda m:m.group(1)+str(value),config)
    start='local function archOffset(' if 'local function archOffset(' in s else 'local function makeArchSpan('
    program=HOST.replace('__CONFIG__',config).replace('__WALKWAY__',re.search(r'local WALKWAY_TOP = ([.0-9]+)',s).group(1))
    program=program.replace('__ARCHES__',section(s,start,'local function makeRail('))
    program=program.replace('__CORRIDOR__',section(s,'local function makeCorridor(','-- Turn a prop into a real floating object'))
    ring=section(s,'elseif archetype == "Ring Corridor" then','elseif archetype == "Pump Station" then').split('\n',1)[1]
    program=program.replace('__RING_HALL__',ring)
    with tempfile.TemporaryDirectory(prefix='l2-vault-')as folder:
        p=Path(folder)/'geometry.luau';p.write_text(program,encoding='utf-8')
        result=subprocess.run([binary,str(p)],capture_output=True,text=True,timeout=30)
    if result.returncode:raise AssertionError(result.stderr)
    cases={};key=None
    for line in result.stdout.splitlines():
        c=line.split('|')
        if c[0]=='CASE':key=c[1];cases[key]=[];continue
        vectors=[tuple(map(float,v.split(',')))for v in c[2:]]
        cases[key].append(Solid(c[1],'Part',c[0],vectors[0],vectors[1],tuple(vectors[2:])))
    return cases


def crosses(a,b):return(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
AXES=((1,0,0),(0,1,0),(0,0,1))
def overlaps_box(s,center,size):
    delta=sub(s.center,center)
    for axis in (*AXES,*s.axes,*(crosses(a,b)for a in AXES for b in s.axes)):
        if dot(axis,axis)<1e-12:continue
        ra=sum(abs(dot(axis,a))*size[i]/2 for i,a in enumerate(AXES))
        rb=sum(abs(dot(axis,a))*s.size[i]/2 for i,a in enumerate(s.axes))
        if abs(dot(delta,axis))>=ra+rb-1e-8:return False
    return True

def pose(s):return(s.name,s.kind,s.center,s.size,s.axes)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reject-baseline',action='store_true');args=parser.parse_args()
    binary=os.environ.get('LUAU_BIN')or shutil.which('luau')
    if not binary:raise SystemExit('Set LUAU_BIN or put luau on PATH')
    before=build(binary,BEFORE);after=build(binary,ROOT)
    checks=0;baseline_hits=0;crown_min=math.inf;body_r=7.5;body_h=16.7
    vault_scale=1.9
    def check(v,m):
        nonlocal checks
        checks+=1
        if not v:raise AssertionError(m)
    for key,solids in after.items():
        old=before[key]
        check(len(solids)<=len(old)+16,key+' bounded portal slat count')
        if key.startswith(('standalone,','shared,')):
            for a,b in zip(old,solids):
                check(a.name==b.name and a.kind==b.kind,key+' names/collision preserved')
                check(all(abs(x-y)<1e-9 for va,vb in zip((a.center,a.size,*a.axes),(b.center,b.size,*b.axes))for x,y in zip(va,vb)),key+' pose preserved')
            continue
        if key.startswith('ring-hall,'):
            along=0 if key.endswith('X')else 2
            for ring in sorted({s.center[along]for s in solids}):
                center=[0,.45+.18+body_h/2,0];center[along]=ring
                check(not any(overlaps_box(s,center,(15,body_h,15))for s in solids),key+' enlarged ring-hall raised centre')
            check(max(v[1]for s in solids for v in s.vertices())<34,key+' ring hall remains below ceiling')
            continue
        axis,kids,drain,length=key.split(',');length=float(length);along=0 if axis=='X'else 2;across=2-along
        depth=1.8 if drain=='true' else 1.5
        keep=lambda s:any(n in s.name for n in('Water Floor','Side Ledge','Water Corridor'))
        check([pose(s)for s in solids if keep(s)]==[pose(s)for s in old if keep(s)],key+' floors/ledge/water unchanged')
        for s in solids:
            check(all(math.isfinite(v)and v>0 for v in s.size),key+' finite positive part '+s.name)
        vault=[s for s in solids if 'Vault Strip' in s.name]
        ribs=[s for s in solids if 'Arch Rib' in s.name and '.face'not in s.name]
        aperture=[s for s in solids if 'Arch Rib'in s.name or 'Arch Header'in s.name or 'Arch Spandrel'in s.name or 'Vault Strip'in s.name]
        old_aperture=[s for s in old if 'Arch Rib'in s.name or 'Vault Strip'in s.name]
        # Ray every half degree through the actual shell cross section: no gaps.
        center=[0,1,0];center[along]=length/2
        for sample in range(361):
            a=math.pi*sample/360
            target=center.copy();target[across]=40*math.cos(a);target[1]+=40*math.sin(a)
            check(any(s.ray(center,target)is not None for s in vault),key+' continuous vault angle '+str(sample))
        # Mouth rings and cap strips must close the outside without entering
        # the clear inner face. Rays cross the actual portal solids axially.
        for sign in(-1,1):
            portals=[s for s in solids if ('.face'+str(sign))in s.name or 'Arch Header'in s.name or 'Arch Spandrel'in s.name]
            mouth=0 if sign<0 else length
            for sample in range(181):
                angle=math.pi*sample/180
                e=(14.1*math.cos(angle),1+14.1*vault_scale*math.sin(angle))
                normal=(math.cos(angle)/14.1,math.sin(angle)/(14.1*vault_scale))
                norm=math.hypot(*normal);normal=(normal[0]/norm,normal[1]/norm)
                for offset,filled in((.8,True),(-.9,False)):
                    start=[0,e[1]+normal[1]*offset,0];end=start.copy()
                    start[across]=end[across]=e[0]+normal[0]*offset
                    start[along]=mouth+sign*4;end[along]=mouth+sign*.9
                    hit=any(s.ray(start,end)is not None for s in portals)
                    check(hit==filled,key+' portal '+str((sign,sample,offset,hit)))
        # Recover authored chord endpoints from the generated boxes. The foot
        # remains at its original depth even though the upper ellipse grows.
        for s,chord_axis,chord_size in((ribs[0],2,2),(vault[0],0,0)):
            half=(s.size[chord_size]-.9)/2
            ends=[add(s.center,scale(s.axes[chord_axis],half)),add(s.center,scale(s.axes[chord_axis],-half))]
            check(abs(min(e[1]for e in ends)-(-depth-1.2))<1e-8,key+' foot endpoint depth preserved')
        # Full axis-aligned candidate body, including all corners (SAT, not point probes).
        for fraction in(0,.2,.5,.8,1):
            for side in(-2,0,2):
                c=[0,-depth+.18+body_h/2,0];c[along]=length*fraction;c[across]=side
                size=(body_r*2,body_h,body_r*2)
                check(not any(overlaps_box(s,c,size)for s in aperture),key+' candidate clear of vault/mouth at '+str((fraction,side)))
                if any(overlaps_box(s,c,size)for s in old_aperture):baseline_hits+=1
            raised=[0,.45+.18+body_h/2,0];raised[along]=length*fraction
            check(not any(overlaps_box(s,raised,(body_r*2,body_h,body_r*2))for s in aperture),key+' raised centre clear')
        ray=[0,0,0];ray[along]=ribs[len(ribs)//2].center[along]
        top=ray.copy();top[1]=50
        hits=[s.ray(ray,top)for s in ribs];hits=[h*50 for h in hits if h is not None]
        check(bool(hits),key+' rib crown measurable');crown_min=min(crown_min,min(hits))
        # Crown caps stay below the configured doorway; no inverted header.
        for s in solids:
            if 'Arch Header'in s.name:
                check(abs(s.center[1]+s.size[1]/2-30.15)<1e-8,key+' capTop matches DoorHeight')
                check(abs(s.center[1]-s.size[1]/2-27.31)<1e-8,key+' capCrown below doorway')
            if 'Pressure Door 1'==s.name.removeprefix('Level 2 '):
                check(s.size[1]==36 and abs(s.center[1]-14)<1e-8,key+' closed door uses new shell height')
                check(s.center[1]-s.size[1]/2<=-depth,key+' closed door seals channel')
        # Tangent strips follow the ellipse normal rather than a circular radial vector.
        for s in vault:
            rel=sub(s.center,(length/2,1,0)if axis=='X'else(0,1,length/2))
            gradient=(rel[0],rel[1]/(vault_scale**2),rel[2]);mag=math.sqrt(dot(gradient,gradient))
            check(abs(dot(s.axes[1],gradient)/mag)>1-1e-8,key+' true ellipse normal')
    check(baseline_hits>0,'baseline must fail the larger candidate clearance')
    check(crown_min>19,'actual new rib crown taller than19')
    print(f'L2 tunnel geometry: {checks} checks passed; {len(after)} fixtures; baseline blocked {baseline_hits} body samples; minimum rib crown {crown_min:.6f}')
    if args.reject_baseline:
        raise SystemExit('Baseline rejected as expected: original vault blocks enlarged candidate body')

if __name__=='__main__':main()
