"""Offline geometry/contract QA. Only reads mall.json; writes QA evidence in build/.
/usr/local/bin/python3 tools/lobby_mall/check_mall.py
Convex geometry SAT tests use native shape vertices, not just bounding boxes.
"""
import json, math, hashlib, itertools, sys
from collections import deque
sys.dont_write_bytecode=True
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'artifacts/lobby-mall-20261011/build'
sys.path.insert(0,str(Path(__file__).parent))
from build_mall import rotation, local_mesh, S
EPS=1e-5

def hull(points):
    p=sorted(set(tuple(v) for v in np.round(points,8)))
    if len(p)<3:return np.array(p)
    cross=lambda o,a,b:(a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    lo=[];hi=[]
    for v in p:
        while len(lo)>1 and cross(lo[-2],lo[-1],v)<=EPS:lo.pop()
        lo.append(v)
    for v in reversed(p):
        while len(hi)>1 and cross(hi[-2],hi[-1],v)<=EPS:hi.pop()
        hi.append(v)
    return np.array(lo[:-1]+hi[:-1])

def distance(point,poly):
    point=np.array(point);inside=True;best=1e9
    for a,b in zip(poly,np.roll(poly,-1,axis=0)):
        ab=b-a;ap=point-a
        if ab[0]*ap[1]-ab[1]*ap[0]<-EPS:inside=False
        t=np.clip(np.dot(ap,ab)/max(np.dot(ab,ab),EPS),0,1);best=min(best,np.linalg.norm(ap-ab*t))
    return 0 if inside else best

def clip(poly,normal,offset):
    result=[]
    for a,b in zip(poly,np.roll(poly,-1,axis=0)):
        fa=np.dot(a,normal)-offset;fb=np.dot(b,normal)-offset
        if fa<=EPS:result.append(a)
        if (fa<-EPS and fb>EPS) or (fa>EPS and fb<-EPS):result.append(a+(b-a)*fa/(fa-fb))
    return np.array(result)

def area(poly):return abs(np.dot(poly[:,0],np.roll(poly[:,1],-1))-np.dot(poly[:,1],np.roll(poly[:,0],-1)))/2 if len(poly)>2 else 0

def intersection_area(A,B):
    out=A.copy()
    for a,b in zip(B,np.roll(B,-1,axis=0)):
        n=np.array([b[1]-a[1],a[0]-b[0]])
        if len(out)<3:return 0
        out=clip(out,n,np.dot(n,a))
    return area(out)

def geometry(p):
    v,f=local_mesh(p['shape'],p['size'],24);r=rotation(p['rot']);v=v@r.T+np.array(p['pos']);norms=[];edges=[];faces=[]
    for face in f:
        q=v[list(face)];n=np.cross(q[1]-q[0],q[2]-q[0]);length=np.linalg.norm(n)
        if length<EPS:continue
        n/=length;norms.append(n)
        face_area=abs(sum(np.dot(np.cross(a,b),n) for a,b in zip(q,np.roll(q,-1,axis=0))))/2
        if face_area>1+EPS:faces.append((q,n))
        for a,b in zip(q,np.roll(q,-1,axis=0)):
            e=b-a;l=np.linalg.norm(e)
            if l>EPS:edges.append(e/l)
    def unique(vecs):
        d={}
        for v in vecs:
            if next((x for x in v if abs(x)>EPS),1)<0:v=-v
            d[tuple(np.round(v,6))]=v
        return list(d.values())
    poly=hull(v[:,[0,2]])
    if p['shape']=='Cylinder' and abs(r[1,0])>.9999:
        # Circumscribed 24-gon contains the exact native circular footprint.
        centre=np.array(p['pos'])[[0,2]];poly=centre+(poly-centre)/math.cos(math.pi/24)
    return {'p':p,'v':v,'lo':v.min(0),'hi':v.max(0),'n':unique(norms),'e':unique(edges),'faces':faces,'poly':poly}

def sat(a,b):
    for axis in a['n']+b['n']:
        aa=a['v']@axis;bb=b['v']@axis
        if min(aa.max(),bb.max())-max(aa.min(),bb.min())<=EPS:return False
    for x in a['e']:
        for y in b['e']:
            axis=np.cross(x,y);l=np.linalg.norm(axis)
            if l<EPS:continue
            axis/=l;aa=a['v']@axis;bb=b['v']@axis
            if min(aa.max(),bb.max())-max(aa.min(),bb.min())<=EPS:return False
    return True

def coplanar(a,b):
    best=0;joined=0
    for qa,na in a['faces']:
        for qb,nb in b['faces']:
            if abs(abs(np.dot(na,nb))-1)>1e-5 or abs(np.dot(na,qa[0]-qb[0]))>1e-4:continue
            # Only same-facing visible surfaces flicker. Opposed joining faces are hidden internally.
            same=np.dot(na,nb)>.99999
            u=qa[1]-qa[0];u/=np.linalg.norm(u);v=np.cross(na,u)
            A=hull(np.column_stack([qa@u,qa@v]));B=hull(np.column_stack([qb@u,qb@v]));varea=intersection_area(A,B)
            if same:best=max(best,varea)
            else:joined=max(joined,varea)
    return best,joined

def main():
    D=json.loads((OUT/'mall.json').read_text());errors=[];notes=[]
    def check(ok,msg):
        if not ok:errors.append(msg)
    with Image.open(OUT/'textures/sign_face.png') as im:
        check(im.size==(512,512) and np.max(abs(np.array(im).mean(axis=(0,1))-[236,226,160]))<2,'cream sign face texture RGB')
    check(D['version']==1 and D['units']=='studs','version/units')
    required={'spawn','pads','shop_stand','boards','dj_console','stage_deck','tape_z','dark_wing','shop_spots','skin_plinths'}
    check(set(D['anchors'])==required,'anchor keys');check(len(D['parts'])<5000,'part budget')
    names=[p['name'] for p in D['parts']];check(len(names)==len(set(names)),'duplicate part names')
    groups={'Concourse','Stand','Arrival','Stage','Tape','DarkWing','Furniture','Ceiling'}|{f'Shop{i}' for i in range(1,7)}
    geom=[]
    for p in D['parts']:
        check(set(p)=={'name','group','shape','pos','size','rot','color','material','transparency','collide','glow'},p['name']+' fields')
        check(p['group'] in groups and p['shape'] in ('Block','Cylinder','Ball','Wedge'),p['name']+' enums')
        check(all(math.isfinite(v) and .05-EPS<=v<=2048 for v in p['size']),p['name']+' size')
        check(all(len(p[f])==3 and all(math.isfinite(v) for v in p[f]) for f in ('pos','size','rot')),p['name']+' finite vectors')
        check(all(0<=v<=255 and isinstance(v,int) for v in p['color']),p['name']+' color')
        check(0<=p['transparency']<=1 and type(p['collide']) is bool and type(p['glow']) is bool,p['name']+' flags')
        check(p['material'] in D['materials'],p['name']+' material')
        q=geometry(p);geom.append(q)
        check(np.all(q['lo']>=np.array(D['bounds']['min'])-EPS) and np.all(q['hi']<=np.array(D['bounds']['max'])+EPS),p['name']+' outside bounds')
    for k,m in D['materials'].items():
        check(set(m)=={'base','colour_map','normal_map','roughness_map','studs_per_tile'},k+' material fields')
        check(m['base'] in {'Concrete','Plaster','Carpet','WoodPlanks','Wood','Metal','Glass','Fabric','SmoothPlastic','Neon','Cardboard'},k+' Roblox base material')
        check(math.isfinite(m['studs_per_tile']) and m['studs_per_tile']>0,k+' tile scale')
        for field in ('colour_map','normal_map','roughness_map'):
            if m[field]:check(m[field].startswith('textures/') and (OUT/m[field]).is_file(),k+' missing '+field)
    A=D['anchors'];pads=A['pads'];check(len(pads)==24,'24 pads (four a level, two by two; 2026-10-12)')
    byname={p['name']:p for p in D['parts']}
    for g,z0,z1 in [('Concourse',-900,-621),('DarkWing',-621,-421)]:
        for x in (182,258):
            border=byname[f'{g}_Border{x}'];check(border['pos']==[x,29.5,(z0+z1)/2] and border['size']==[4,1,z1-z0],g+' continuous brown floor border')
        if g=='Concourse':
            # 2026-10-12: the lit hall's floor is rows of tile patterns; together they are the whole 72 x 279, each
            # on the tile grid (overlaps are refused further down)
            cells=[p for p in D['parts'] if p['name'].startswith('Concourse_Floor')]
            check(abs(sum(p['size'][0]*p['size'][2] for p in cells)-72*(z1-z0))<EPS,'hall floor rows cover 72 x 279')
            for p in cells:
                lo=[p['pos'][0]-p['size'][0]/2,p['pos'][2]-p['size'][2]/2];hi=[p['pos'][0]+p['size'][0]/2,p['pos'][2]+p['size'][2]/2]
                check(p['pos'][1]==29.5 and p['size'][1]==1 and lo[0]>=184 and hi[0]<=256 and lo[1]>=z0 and hi[1]<=z1 and p['material'].startswith('floor_'),p['name']+' floor top/bounds')
                check(all(v%4==0 for v in (lo[0],hi[0],lo[1])) and (hi[1]%4==0 or hi[1]==z1),p['name']+' on the 4-stud tile grid')
        else:
            p=byname[g+'_Floor'];check(p['pos']==[220,29.5,(z0+z1)/2] and p['size']==[72,1,z1-z0],g+' floor top/bounds')
    for p in D['parts']:
        if p['group']=='Ceiling' and p['material']=='ceiling':check(abs(p['pos'][1]-p['size'][1]/2-57.04)<EPS,p['name']+' ceiling underside (27.04 above the floor since 2026-10-13)')
        if p['name'].startswith('PanelFrame'):check(p['size']==[8,.5,4],p['name']+' recessed panel size')
    for i in range(1,7):
        z=-840+80*((i-1)//2)
        for k,(row,dz) in enumerate(((10,-12),(10,12),(32,-12),(32,12)),1):
            x=180-row if i%2 else 260+row
            found=[a for a in pads if a['level']==i and a['station']==k]
            check(len(found)==1 and found[0]['pos']==[x,30.6,z+dz] and found[0]['radius']==7.4,f'pad {i}/{k} anchor')
            p=byname[f'Shop{i}_Pad{k}'];check(p['shape']=='Cylinder' and p['size']==[.6,14.8,14.8] and p['pos']==[x,30.3,z+dz],f'pad {i}/{k} geometry')
            for q in geom:
                if q['hi'][1]<=30.6+EPS or q['lo'][1]>=39.6-EPS:continue
                if distance([x,z+dz],q['poly'])<7.4-EPS:errors.append(f'pad {i}/{k} clearance: '+q['p']['name'])
        front=180 if i%2 else 260
        floor=byname[f'Shop{i}_QueueFloor'];check(floor['size']==[42,1,58] and floor['pos']==[159 if i%2 else 281,29.5,z],f'Shop{i} queue floor 42x58')
        fascia=byname[f'Shop{i}_Fascia'];check(fascia['size']==[2,4,52] and fascia['pos'][1]==44,f'Shop{i} fascia')
        for k in range(2):
            col=[q for q in geom if q['p']['name'].startswith(f'Shop{i}_PierColumn{k}_')]
            if col:
                lo=np.min([q['lo'] for q in col],axis=0);hi=np.max([q['hi'] for q in col],axis=0);check(np.allclose(hi-lo,[4,27.04,4]),f'Shop{i} pier column{k} 4x4')
            else:check(False,f'Shop{i} pier column{k} absent')
        ceiling=byname[f'Shop{i}_Ceiling'];check(ceiling['pos'][1]-ceiling['size'][1]/2==44,f'Shop{i} 14-high interior')
        sign=next(s for s in D['signs'] if s['name']==f'Shop{i}_Sign');check(sign['size']==[40,3.2],f'Shop{i} sign box')
        for k in range(1,4):
            post=byname[f'Shop{i}_StationPost{k}'];plate=next(s for s in D['signs'] if s['name']==f'Shop{i}_Station{k}')
            check(post['size'][1]==4 and plate['size']==[3.2,1.3],f'Shop{i} station{k} post/plate')
        opening=[front,30,z-26,front,42,z+26]
        # Check solid geometry in the front plane excluding the decorative station plates far inside.
        for q in geom:
            if q['lo'][0]<front+.02 and q['hi'][0]>front-.02 and q['hi'][1]>30+EPS and q['lo'][1]<42-EPS and q['hi'][2]>z-26+EPS and q['lo'][2]<z+26-EPS:errors.append(f'Shop{i} 52x12 opening obstructed by '+q['p']['name'])
    check(A['spawn']==[220,30,-860],'spawn position')
    for q in geom:
        if q['hi'][1]<=30.2+EPS or q['lo'][1]>=39-EPS:continue
        if distance([220,-860],q['poly'])<12-EPS:errors.append('spawn radius12: '+q['p']['name'])
    check(A['tape_z']==-621 and A['dark_wing']=={'min':[184,30,-621],'max':[256,46,-421]},'dark wing extents')
    for q in geom:
        # Boundary tape is exempt; no props or fixtures past it.
        if q['p']['group']!='Tape' and q['lo'][1]<39 and q['hi'][1]>30+EPS and q['hi'][2]>-620.99 and q['lo'][2]<-421:
            if intersection_area(q['poly'],np.array([[184,-621],[256,-621],[256,-421],[184,-421]]))>EPS:errors.append('dark floor: '+q['p']['name'])
    # 2026-10-13 (owner: the wing fades into darkness "with flickering lights"): only the five dying panels, none deeper than 80 studs
    check(all(l['kind']=='panel' and l['state']=='dim_flicker' and l['pos'][2]<=-541 for l in D['lights'] if l['pos'][2]>-621),'only dying panels in the dark wing')
    dead={(240,-830),(200,-750),(240,-690),(200,-650),(240,-650)}
    for l in D['lights']:
        check(set(l)=={'name','kind','pos','color','brightness','range','state'},l['name']+' light fields')
        check(l['kind'] in {'panel','globe','showcase','neon'} and l['state'] in {'on','dim_flicker'},l['name']+' light enums')
        check(len(l['pos'])==3 and all(math.isfinite(v) for v in l['pos']) and l['brightness']>0 and l['range']>0,l['name']+' light vectors/power')
    panels=[l for l in D['lights'] if l['kind']=='panel'];wing=[(200,-601),(240,-601),(200,-581),(240,-561),(200,-541)];expected=({(x,z) for x in (200,240) for z in range(-890,-629,20)}-dead)|set(wing)       # 2026-10-13: five dying panels in the dark wing
    check({(l['pos'][0],l['pos'][2]) for l in panels}==expected,'panel lattice / dead panels')
    check(sorted((l['pos'][0],l['pos'][2]) for l in panels if l['state']=='dim_flicker')==sorted([(200,-810)]+wing),'flicker panels')
    check(len([p for p in D['parts'] if p['name'].startswith('TapePole')])==7,'7 tape poles')
    check(A['shop_stand']=={'centre':[220,30,-770],'radius':20},'stand anchor')
    check(A['stage_deck']=={'min':[205,30,-655],'max':[235,32,-632]},'stage extents')
    check(byname['StageBanner_Face']['collide'],'touchable cloth banner collision')
    check(A['dj_console']==[220,35.85,-639],'DJ anchor')

    for k in range(7):
        pole=byname[f'TapePole{k}'];base=byname[f'TapeBase{k}'];check(pole['pos']==[184+k*12,31.95,-621] and abs(pole['pos'][1]+pole['size'][0]/2-33.6)<EPS and base['shape']=='Cylinder','tape pole '+str(k))
    check(byname['DangerTape']['pos']==[220,33.2,-621] and byname['DangerTape']['size']==[72,.5,.05] and byname['DangerTape']['collide'],'one continuous touchable tape')
    check(max(q['hi'][1] for q in geom if q['p']['name'].startswith('TowerCore'))==41,'tower top 41')
    # Closed ring / expanded stand and all purchase/skin anchors.
    keys={'AdvancedEquipment','EntityDetector','SpeedPotion','RouteMarker','EntityShield','ExpeditionPack','EmergencyReentry','Tokens4','Tokens20','Supporter','CosmeticEquipment'}
    check(len(A['shop_spots'])==11 and {q['key'] for q in A['shop_spots']}==keys,'11 exact buy spot keys')
    skins={'BaselineYellow','PoolService','SuburbSurvey','BlacksiteDirector','StaticWraith','FalseSun'}
    check(len(A['skin_plinths'])==6 and {q['skin'] for q in A['skin_plinths']}==skins,'6 exact skin plinth keys')
    for spot in A['shop_spots']:
        plate=next(s for s in D['signs'] if s['name']=='Price'+spot['key'])
        expected=np.array(plate['pos'])+np.array(plate['normal'])*(6.5-.33);expected[1]=30.02
        crate=np.array(plate['pos'])+np.array(plate['normal'])*(2.5-.33);crate[1]=30.12
        check(set(spot)=={'key','pos','crate'} and np.allclose(spot['pos'],expected) and np.allclose(spot['crate'],crate),spot['key']+' buy ring 6.5 out from counter/plate, its carton 2.5 out')
    for a in A['skin_plinths']:
        p=byname['SkinPlinth'+a['skin']]
        check(set(a)=={'skin','pos','facing'} and np.allclose(a['pos'],np.array(p['pos'])+[0,.5,0]),a['skin']+' plinth top')
        check(p['size']==[1,4.6,4.6] and abs(np.linalg.norm(np.array(a['pos'])[[0,2]]-[220,-770])-17.5)<EPS,a['skin']+' plinth dimensions/radius')
        check(abs(np.linalg.norm(a['facing'])-1)<EPS and a['facing'][1]==0 and np.dot(np.array(a['pos'])-[220,31.12,-770],a['facing'])>17.49,a['skin']+' outward facing')
        hood=byname[a['skin']+'_Hood'];check(abs(hood['pos'][1]+.66-a['pos'][1]-5.2)<EPS,a['skin']+' player-size mannequin')
        check(any(l['name']=='SkinSpot'+a['skin'] for l in D['lights']),a['skin']+' can spotlight')
    for q in geom:
        if q['p']['group']=='Stand':check(q['lo'][0]>=200-EPS and q['hi'][0]<=240+EPS,q['p']['name']+' outside 200..240 stand')
    for i in range(6):
        p=byname[f'Counter{i}_Body'];check(abs(p['size'][2]-4)<EPS,f'counter{i} depth4')
        check(p['collide'] and any(s['name']==f'CounterHeader{i}' for s in D['signs']),f'counter{i} closed body/header')
        glass=byname[f'Product{i+1}_Glass'];check(abs(geometry(glass)['hi'][1]-30.12-3.6)<EPS,f'counter{i} height3.6')
        check(glass['material']=='case_glass' and glass['transparency']>0 and glass['rot'][0]!=0,f'counter{i} sloped glass')
    # Ring membership: a fine angular sweep must hit exactly one counter footprint
    # at the middle apothem (vertices may join but no gap is allowed).
    ring=[q for q in geom if q['p']['name'].startswith('Counter') and '_Body' in q['p']['name']]
    r=(15*math.sqrt(3)/2-2)
    for theta in np.linspace(0,math.tau,721):
        pt=np.array([220,-770])+r*np.array([math.cos(theta),math.sin(theta)])
        check(any(distance(pt,q['poly'])<EPS for q in ring),'closed counter ring gap')
    check(sum(p['name'].startswith('PoolColumn') for p in D['parts'])==12,'twelve pool columns (three rows of four, 2026-10-12)')
    for i in range(5):
        q=geometry(byname[f'PoolColumn{i}']);check(abs(q['lo'][1]-28.8)<EPS,f'pool column{i} on basin floor')
        q=geometry(byname[f'PoolCapital{i}_2']);check(abs(q['hi'][1]-44)<EPS,f'pool capital{i} meets ceiling')
    # 2026-10-12 (owner): each level's board against the pier beside its own shop's opening
    LW,DW=round(10*5.6/13.2,2),round(12*560/392,2)      # 2026-10-13: each board is the shape of the sheet pinned to it
    expected_boards={'directory':(185,-795,DW,12,1),'level1':(184.6,-871.2,LW,10,1),'level2':(255.4,-871.2,LW,10,-1),'level3':(184.6,-728.4,LW,10,1),'level4':(255.4,-728.4,LW,10,-1),'level5':(184.6,-711.2,LW,10,1),'level6':(255.4,-711.2,LW,10,-1)}
    for board in A['boards']:
        x,z,w,h,n=expected_boards[board['key']]
        check(board['pos']==[x+n*.205,31+h/2,z] and board['size']==[w,h] and board['normal']==[n,0,0],board['key']+' board location')
        check(not any(s['part']==board['key']+'_BoardFace' for s in D['signs']),board['key']+' blank face')
    check(len(A['boards'])==7 and {b['key'] for b in A['boards']}=={'directory'}|{f'level{i}' for i in range(1,7)},'7 boards')
    signtexts=[s['text'] for s in D['signs']]
    for txt in ('OFFICE','POOLROOMS','MALL PARTY','CINEMA','THE VOID','PLAY ZONE','WELCOME','GRAND OPENING','DIRECTORY'):check(signtexts.count(txt)==1,'sign '+txt)
    check(signtexts.count('SHOP & SUPPLIES')==6,'six stand signs')
    for k in range(1,5):check(signtexts.count(f'STATION {k}')==6,f'station{k} signs')
    allowed={'OFFICE','POOLROOMS','MALL PARTY','CINEMA','THE VOID','PLAY ZONE','WELCOME','GRAND OPENING','SHOP & SUPPLIES','DIRECTORY'}|{f'STATION {k}' for k in range(1,5)}
    product_texts=['EMERGENCY RE-ENTRY','ENTITY DETECTOR','ITEMS','EQUIPMENT & PACKS','RESEARCH TOKENS','SUPPORTER',
      'ADVANCED EQUIPMENT - 149 ROBUX','ZYNTRA ENTITY DETECTOR - 149 ROBUX','ENTITY SHIELD - 5 TOKENS','SPEED POTION - 3 TOKENS','ROUTE MARKER PACK - 2 TOKENS','EXPEDITION PACK - 69 ROBUX','EMERGENCY RE-ENTRY - 29 ROBUX','4 TOKENS','20 TOKENS','ZYNTRA SUPPORTER - 99 ROBUX','GLOWSTICK CUSTOMIZER - 99 ROBUX',
      'BASELINE YELLOW - FREE','POOL SERVICE - 25 TOKENS','SUBURB SURVEY - 75 TOKENS','BLACKSITE DIRECTOR - 300 TOKENS','STATIC WRAITH - 99 ROBUX','FALSE SUN - 149 ROBUX']
    allowed.update(product_texts)
    for txt in product_texts:check(signtexts.count(txt)==1,'exact stand sign '+txt)
    for s in D['signs']:
        check(set(s)=={'name','text','style','pos','size','normal','part'},s['name']+' sign fields')
        check(len(s['size'])==2 and all(math.isfinite(v) and v>0 for v in s['size']),s['name']+' sign size')
        check(s['part'] in byname,s['name']+' sign support')
        check(abs(np.linalg.norm(s['normal'])-1)<EPS,s['name']+' sign normal')
        check(s['style'] in ('box','station','banner','tape','plain'),s['name']+' style')
        if s['style']=='box':
            check(byname[s['part']]['material']=='sign_face' and byname[s['part']]['color']==[255,255,255],s['name']+' cream sign box')
            frame=byname.get(s['name']+'_Frame',{})
            check(frame.get('color')==[62,58,46],s['name']+' bronze frame')
        if s['style']=='tape':check(s['text']==('DANGER: DO NOT GO PAST THIS POINT'+'            ')*9+'DANGER: DO NOT GO PAST THIS POINT','tape repeat exact')
        else:check(s['text'] in allowed,s['name']+' unexpected wording')
    # A circle of radius 10 swept along the centreline proves 20 studs of
    # clearance in every turn. All points are tested against convex footprints.
    # <=0.2-stud floor coverings are traversable; headroom is >=5 studs above them.
    radius=10.0;step=.5;safety=.001
    obstacles=[q for q in geom if q['p']['collide'] and q['lo'][1]<35.2-EPS and q['hi'][1]>30.2+EPS
               and q['hi'][0]>=180-EPS and q['lo'][0]<=260+EPS and q['hi'][2]>=-870 and q['lo'][2]<=-620]
    xs=np.arange(190,250.01,step);zs=np.arange(-860,-632.49,step)
    XX,ZZ=np.meshgrid(xs,zs);points=np.column_stack([XX.ravel(),ZZ.ravel()]);valid=np.ones(len(points),bool)
    def distances(points,poly):
        best=np.full(len(points),1e9);inside=np.ones(len(points),bool)
        for a,b in zip(poly,np.roll(poly,-1,axis=0)):
            ab=b-a;ap=points-a
            inside&=ab[0]*ap[:,1]-ab[1]*ap[:,0]>=-EPS
            t=np.clip((ap[:,0]*ab[0]+ap[:,1]*ab[1])/max(np.dot(ab,ab),EPS),0,1)
            best=np.minimum(best,np.linalg.norm(ap-t[:,None]*ab,axis=1))
        best[inside]=0
        return best
    for q in obstacles:
        poly=q['poly'];lo=poly.min(0)-radius-safety;hi=poly.max(0)+radius+safety
        ids=np.flatnonzero(valid & np.all(points>=lo,axis=1) & np.all(points<=hi,axis=1))
        if len(ids):valid[ids]=distances(points[ids],poly)>=radius+safety-EPS
    valid=valid.reshape(XX.shape);start=(0,int(np.argmin(abs(xs-220))))
    def empty_terminal(q,strip):
        p=q['p']
        if p['shape']=='Cylinder' and abs(rotation(p['rot'])[1,0])>.9999:
            return distance(np.array(p['pos'])[[0,2]],strip)>=max(p['size'][1:])/2-EPS
        return intersection_area(q['poly'],strip)<=EPS
    parent={start:None};todo=deque([start]);goal=None
    while todo:
        z,x=todo.popleft()
        if not valid[z,x]:continue
        if z==len(zs)-1:
            strip=np.array([[xs[x]-10,zs[z]],[xs[x]+10,zs[z]],[xs[x]+10,-622.1],[xs[x]-10,-622.1]])
            if all(empty_terminal(q,strip) for q in obstacles):goal=(z,x);break
        # Candidate edges are independently checked densely with a Lipschitz bound.
        for dz,dx in ((1,0),(1,1),(1,-1),(0,1),(0,-1),(-1,0),(-1,1),(-1,-1)):
            zz,xx=z+dz,x+dx
            if not (0<=zz<len(zs) and 0<=xx<len(xs)) or not valid[zz,xx] or (zz,xx) in parent:continue
            parent[(zz,xx)]=(z,x);todo.append((zz,xx))
    path=[];minimum=1e9
    if goal is None:
        far=max(parent,key=lambda c:c[0]);errors.append(f'Continuous swept 20-wide corridor blocked; farthest reached x={xs[far[1]]}, z={zs[far[0]]}. Adjust movable furniture.')
    else:
        cur=goal
        while cur is not None:
            z,x=cur;path.append([float(xs[x]),30,float(zs[z])]);cur=parent[cur]
        path.reverse()
        # Samples are <=0.01 stud apart. Distance to a convex obstacle is
        # 1-Lipschitz: minimum sample distance minus0.005 bounds every edge.
        samples=[]
        for a,b in zip(path,path[1:]):
            a,b=np.array(a)[[0,2]],np.array(b)[[0,2]]
            for t in np.linspace(0,1,max(2,int(np.ceil(np.linalg.norm(b-a)/.01))+1)):
                samples.append(a+(b-a)*t)
        samples=np.array(samples)
        for q in obstacles:minimum=min(minimum,float(distances(samples,q['poly']).min()))
        check(minimum>=radius+.005-EPS,'Swept corridor failed whole-edge Lipschitz proof')
        notes.append(f'Continuous 20-wide x5-high corridor: {len(path)} centreline nodes; minimum sampled obstacle clearance {minimum:.6f}; whole-edge proof: 0.01-stud samples, 0.005-stud Lipschitz bound.')
        notes.append(f'Full-width terminal strip verified from {path[-1]} to tape-base south tangent z=-622.1; 20 wide, {(-622.1-path[-1][2]):.1f} long, 5 high. No 20-wide passage through poles 12 apart.')
    grid=np.full((*valid.shape,3),[42,42,38],dtype=np.uint8);grid[valid]=[66,102,60]
    for z,x in parent:grid[z,x]=[148,95,47]
    for x,y,z in path:grid[int(np.argmin(abs(zs-z))),int(np.argmin(abs(xs-x)))]=[245,237,156]
    diagram=Image.fromarray(grid.transpose(1,0,2)[::-1])
    diagram=diagram.resize((2*len(zs),2*len(xs)),Image.Resampling.NEAREST)
    sheet=Image.new('RGB',(diagram.width,diagram.height+55),(24,24,23));sheet.paste(diagram,(0,55));dr=ImageDraw.Draw(sheet)
    dr.text((8,6),'20-stud swept corridor | north -> | green: allowed circle centres | amber: reachable | pale: verified route',fill=(237,228,199))
    dr.text((8,25),f'radius10, 5-high, node margin {safety:.4f}, sample minimum {minimum if path else None}',fill=(237,228,199))
    sheet.save(OUT/'clearance_route.png')
    if '--route-only' in sys.argv:
        print('\n'.join(notes+errors));return 1 if errors else 0
    print('CLEARANCE_SCAN_DONE',len(path),flush=True)
    # Large solid volume and same-facing coplanar overlaps. Broad phase is x sweep.
    solids=sorted([q for q in geom if max(a*b for a,b in itertools.combinations(q['p']['size'],2))>=1],key=lambda q:q['lo'][0]);overlaps=[];faces=[];joins=[];hidden_contacts=[]
    for i,a in enumerate(solids):
        for b in solids[i+1:]:
            if b['lo'][0]>a['hi'][0]+EPS:break
            overlap=np.minimum(a['hi'],b['hi'])-np.maximum(a['lo'],b['lo'])
            if np.any(overlap<-EPS):continue
            if a['p']['transparency']==0 and b['p']['transparency']==0 and np.prod(a['p']['size'])>=1 and np.prod(b['p']['size'])>=1 and np.all(overlap>EPS) and sat(a,b):overlaps.append([a['p']['name'],b['p']['name']])
            face,joined=coplanar(a,b)
            if joined>1+EPS:joins.append([a['p']['name'],b['p']['name'],round(joined,4)])
            if face>1+EPS:
                # The water bottom and submerged column caps both face DOWN at
                # y28.8. The opaque 0.5-thick basin floor seals their full area.
                # Flag these pairs as requested, proving the hiding solid rather
                # than misclassifying them as overlapping visible surfaces.
                pair={a['p']['name'],b['p']['name']}
                basin=next(q for q in geom if q['p']['name']=='Shop2_BasinFloor')
                sealed=('Shop2_Water' in pair and any(n.startswith('PoolColumn') for n in pair)
                    and abs(a['lo'][1]-28.8)<EPS and abs(b['lo'][1]-28.8)<EPS
                    and abs(basin['hi'][1]-28.8)<EPS and basin['p']['transparency']==0
                    and all(distance(v[[0,2]],basin['poly'])<EPS for q in (a,b) for v in q['v'] if abs(v[1]-28.8)<EPS))
                if sealed:hidden_contacts.append({'parts':sorted(pair),'area':round(face,4),'plane_y':28.8,'covered_by':'Shop2_BasinFloor'})
                else:faces.append([a['p']['name'],b['p']['name'],round(face,4)])
    for pair in overlaps:errors.append('solid overlap: '+' / '.join(pair))
    for a,b,v in faces:errors.append(f'coplanar {v} sq.studs: {a} / {b}')
    # Axis proof: compute points by stepwise Roblox YXZ convention, and by Blender matrix.
    proofs=[]
    fixture_names=['PlantLeaf0_1','Shop1_Pad1','Counter0_Body_Miter-1']
    for name in fixture_names:
        p=byname[name];pos=p['pos'];size=p['size'];rot=p['rot'];shape=p['shape']
        # Cylinders have no corners: test eight corners of the native local bounding box.
        v,_=local_mesh('Block' if shape=='Cylinder' else shape,size);x,y,z=np.radians(rot)
        # Explicit pointwise Roblox RY*RX*RZ calculation, independent of matrix helper.
        q=v.copy();q=np.column_stack([q[:,0]*math.cos(z)-q[:,1]*math.sin(z),q[:,0]*math.sin(z)+q[:,1]*math.cos(z),q[:,2]])
        q=np.column_stack([q[:,0],q[:,1]*math.cos(x)-q[:,2]*math.sin(x),q[:,1]*math.sin(x)+q[:,2]*math.cos(x)])
        q=np.column_stack([q[:,0]*math.cos(y)+q[:,2]*math.sin(y),q[:,1],-q[:,0]*math.sin(y)+q[:,2]*math.cos(y)])+pos
        b=(v@S.T)@(S@rotation(rot)@S.T).T+S@pos;back=b@S;err=float(np.max(abs(q-back)));check(err<1e-9,name+' axis proof')
        proofs.append({'name':name,'shape':shape,'pos':pos,'size':size,'rot':rot,'max_error':err,'roblox_corners':q.round(8).tolist(),'blender_corners':b.round(8).tolist()})
    notes.append(f'Opposed coplanar joining faces >1 sq.stud: {len(joins)} (flagged in qa.json; internal contact surfaces, not overlapping visible faces).')
    notes.append(f'Same-facing submerged base contacts >1 sq.stud: {len(hidden_contacts)} (flagged in qa.json; full coverage by the opaque basin floor verified).')
    counts={g:sum(p['group']==g for p in D['parts']) for g in sorted(groups)}
    evidence={'passed':not errors,'parts':len(D['parts']),'counts':counts,'errors':errors,'notes':notes,'axis_proof':proofs,'opposed_coplanar_joins':joins,'hidden_coplanar_contacts':hidden_contacts,'visible_coplanar_overlaps':faces,'solid_overlaps':overlaps,'route':path,'route_radius':radius,'terminal_strip':{'min':[path[-1][0]-10,30.2,path[-1][2]],'max':[path[-1][0]+10,35.2,-622.1]} if path else None,'route_min_clearance':minimum if path else None,'route_edge_margin':safety,'json_sha256':hashlib.sha256((OUT/'mall.json').read_bytes()).hexdigest(),'limitations':['Static offline geometry checks; Roblox runtime, lighting parity, gameplay and multiplayer require main agent QA.','The verified radius10 centreline joins a full-width flat-ended terminal strip to the tape bases; seven poles 12 apart prevent a 20-wide corridor through the tape line.']}
    (OUT/'qa.json').write_text(json.dumps(evidence,indent=2)+'\n')
    lines=[('PASS' if not errors else 'FAIL')+f': {len(D["parts"])} parts / {len(D["signs"])} signs / {len(D["lights"])} lights',f'24 pad cylinders, radius12 spawn, six 52x12 openings, clear dark floor, exact signs/lights, bounds, shape contract.',*notes,f'Large solid overlaps: {len(overlaps)}; same-facing coplanar face overlaps >1: {len(faces)}.',f'Axis test maximum error: {max(p["max_error"] for p in proofs):.3e}',*errors]
    (OUT/'checks.txt').write_text('\n'.join(lines)+'\n');print('\n'.join(lines[:8]));print('\n'.join(errors[:65]));print(f'{len(errors)} errors');return 0 if not errors else 1

if __name__=='__main__':sys.exit(main())
