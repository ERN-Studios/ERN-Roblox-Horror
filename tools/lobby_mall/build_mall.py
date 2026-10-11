"""Deterministic native-Part mall design; no network or Studio access.
Blender -b --factory-startup --threads 2 --python tools/lobby_mall/build_mall.py
External Python --textures-only generates PNGs (called by Blender automatically).
All geometry, lights, sign positions and anchors originate in design().
"""
import json, math, os, sys, subprocess
sys.dont_write_bytecode=True
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'artifacts/lobby-mall-20261011/build'
FONT='/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf'
S=np.array([[1.,0,0],[0,0,1],[0,1,0]]) # Roblox -> Blender: (x,z,y), handedness reflection

def rotation(rot):
    x,y,z=np.radians(rot);cx,sx=math.cos(x),math.sin(x);cy,sy=math.cos(y),math.sin(y);cz,sz=math.cos(z),math.sin(z)
    return np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]]) @ np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]]) @ np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])

def angles(r):
    x=math.asin(np.clip(-r[1,2],-1,1))
    if abs(math.cos(x))>1e-7:y=math.atan2(r[0,2],r[2,2]);z=math.atan2(r[1,0],r[1,1])
    else:y=math.atan2(-r[2,0],r[0,0]);z=0
    return np.degrees([x,y,z]).tolist()

def textures():
    from PIL import Image, ImageDraw
    out=OUT/'textures';out.mkdir(parents=True,exist_ok=True)
    n=512;yy,xx=np.mgrid[:n,:n];rng=np.random.default_rng(611)
    def save(name,base,noise=3):
        a=np.empty((n,n,3),float);a[:]=base;a+=rng.normal(0,noise,(n,n,1));return Image.fromarray(np.uint8(np.clip(a,0,255)))
    for key,base in [('terrazzo',(174,158,124)),('plaster',(195,185,146)),('oak',(122,91,51)),('ceiling',(183,181,157)),('damask',(174,154,65)),('beige_carpet',(152,137,98)),('stand_carpet',(120,91,47)),('triangle_carpet',(67,48,61)),('road_carpet',(66,78,59)),('small_tile',(179,199,185)),('pegboard',(180,168,120)),('puzzle_mat',(30,96,112)),('black_ceiling',(31,32,30)),('pad',(26,61,47)),('brass',(136,111,62)),('sign_face',(236,226,160)),('static',(113,115,103)),('stage_carpet',(44,75,68)),('hazard',(230,190,36)),('pool_suit',(160,200,204)),('survey_suit',(222,211,164)),('false_suit',(231,212,162))]:
        im=save(key,base,2.5 if key not in ['static','beige_carpet','stand_carpet'] else 8);d=ImageDraw.Draw(im)
        if key=='terrazzo':
            for i in range(6200):
                x,y=rng.integers(0,n,2);r=int(rng.integers(1,3));c=[(120,110,89),(201,187,151),(92,81,62),(158,141,105)][i%4];d.polygon([(int(x),int(y-r)),(int(x+r),int(y)),(int(x),int(y+r))],fill=c)
        elif key=='static':
            a=np.repeat(np.clip(119+rng.normal(0,34,(n,n,1))-((yy%4)==0)[...,None]*22,20,230),3,axis=2)
            im=Image.fromarray(a.astype(np.uint8))
        elif key=='oak':
            for x in range(n):
                v=int(8*math.sin(x*.10)+5*math.sin(x*.35));d.line((x,0,x,n),fill=(122+v,91+v,51+v),width=1)
            for x in range(0,n,128):d.line((x,0,x,n),fill=(87,64,37),width=2)
        elif key in ('ceiling','black_ceiling'):
            for t in (0,256,511):
                c=(111,111,98) if key=='ceiling' else (17,17,16);d.line((t,0,t,n),fill=c,width=2);d.line((0,t,n,t),fill=c,width=2)
            if key=='ceiling':
                a=np.array(im).astype(float);stain=np.exp(-(((xx-395)/60)**2+((yy-145)/90)**2));a-=stain[...,None]*[25,28,32];im=Image.fromarray(np.uint8(np.clip(a,0,255)))
        elif key in ('damask','stand_carpet'):
            for x in range(-64,n+64,64):
                for y in range(-128,n+128,128):
                    X=x+(32 if (y//128)%2 else 0)
                    d.ellipse((X-10,y-23,X+10,y+23),outline=(146,130,59) if key=='damask' else (146,111,56),width=2)
                    for sg in (-1,1):d.arc((X-25,y-16,X+25,y+16),0 if sg==1 else 180,180 if sg==1 else 360,fill=(154,135,59) if key=='damask' else (138,103,53),width=2)
                    d.line((X,y-32,X,y+32),fill=(155,138,58) if key=='damask' else (137,104,51),width=2)
        elif key=='small_tile':
            for v in range(0,n,64):d.line((v,0,v,n),fill=(123,141,129),width=2);d.line((0,v,n,v),fill=(123,141,129),width=2)
        elif key=='pegboard':
            for x in range(16,n,32):
                for y in range(16,n,32):d.ellipse((x-3,y-3,x+3,y+3),fill=(82,76,54))
        elif key=='triangle_carpet':
            for x in range(0,n,64):
                for y in range(0,n,64):d.polygon([(x+8,y+8),(x+53,y+14),(x+22,y+53)],outline=(153,112,103),width=3)
        elif key=='road_carpet':
            for t in (80,280,440):
                d.line((0,t,n,t),fill=(156,145,103),width=28);d.line((t,0,t,n),fill=(156,145,103),width=28)
                d.line((0,t,n,t),fill=(54,55,51),width=19);d.line((t,0,t,n),fill=(54,55,51),width=19)
                for u in range(0,n,26):d.line((u,t,u+10,t),fill=(223,205,135),width=2);d.line((t,u,t,u+10),fill=(223,205,135),width=2)
            for x,y in [(150,150),(350,170),(180,350),(360,350)]:d.rectangle((x-22,y-18,x+22,y+18),fill=(122,67,38));d.polygon([(x-26,y-18),(x,y-38),(x+26,y-18)],fill=(185,113,50))
        elif key=='puzzle_mat':
            for x in range(0,n,128):
                for y in range(0,n,128):
                    d.rectangle((x,y,x+127,y+127),fill=(36,82,135) if (x+y)//128%2 else (56,112,68));d.rectangle((x+1,y+1,x+126,y+126),outline=(20,49,53),width=2)
                    d.ellipse((x+49,y-12,x+79,y+12),fill=(36,82,135) if (x+y)//128%2 else (56,112,68),outline=(20,49,53),width=2)
        elif key=='pool_suit':
            for y in range(0,n,70):
                pts=[(x,y+int(8*math.sin(x*math.tau/128))) for x in range(n)]
                d.line(pts,fill=(86,139,151),width=4)
        elif key=='survey_suit':
            for x in range(0,n,128):
                for y in range(0,n,128):
                    d.rectangle((x+12,y+20,x+66,y+78),fill=(144,149,100))
                    d.rectangle((x+78,y+49,x+110,y+114),fill=(170,164,111))
                    d.line((x+5,y+100,x+115,y+6),fill=(191,177,129),width=4)
        elif key=='false_suit':
            for x in range(0,n,128):
                for y in range(0,n,128):
                    d.ellipse((x+26,y+26,x+86,y+86),outline=(135,100,61),width=2)
                    for k in range(8):
                        a=k*math.tau/8
                        d.line((x+56+32*math.cos(a),y+56+32*math.sin(a),x+56+43*math.cos(a),y+56+43*math.sin(a)),fill=(135,100,61),width=2)
                    d.line((x+4,y+118,x+62,y+98,x+121,y+118),fill=(161,124,77),width=2)
        elif key=='pad':
            d.ellipse((10,10,502,502),outline=(130,157,119),width=15)
        elif key=='hazard':
            a=np.array(im);a[(xx+yy)%256<128]=(24,25,20);im=Image.fromarray(a)
        elif key=='sign_face':
            a=np.array(im).astype(float);v=np.sin(np.pi*xx/n)*np.sin(np.pi*yy/n);a+=(v[...,None]-.4)*[12,10,9];im=Image.fromarray(np.uint8(np.clip(a,0,255)))
        im.save(out/(key+'.png'),compress_level=9)
        # Flat OpenGL normal and matte roughness maps; deliberately no glossy finish.
        Image.new('RGB',(512,512),(128,128,255)).save(out/(key+'_normal.png'))
        Image.new('L',(512,512),235 if key!='small_tile' else 214).save(out/(key+'_roughness.png'))
    print('TEXTURES: 22 sets, deterministic 512px PNGs')

def design():
    D={'version':1,'units':'studs','bounds':{'min':[125,15,-902],'max':[315,50,-419]},'materials':{},'parts':[],'signs':[],'lights':[],'anchors':{}}
    palette={
      'terrazzo':('Concrete',(174,158,124),16),'border':('Concrete',(94,71,45),8),'plaster':('Plaster',(195,185,146),8),'oak':('WoodPlanks',(122,91,51),8),'ceiling':('Concrete',(183,181,157),4),'damask':('Fabric',(174,154,65),6),'beige_carpet':('Carpet',(152,137,98),6),'stand_carpet':('Carpet',(120,91,47),6),'triangle_carpet':('Carpet',(67,48,61),8),'road_carpet':('Carpet',(66,78,59),16),'small_tile':('Concrete',(179,199,185),4),'pegboard':('Wood',(180,168,120),4),'puzzle_mat':('Fabric',(30,96,112),8),'black_ceiling':('Concrete',(31,32,30),4),'pad':('SmoothPlastic',(26,61,47),14.8),'brass':('Metal',(136,111,62),4),'sign_face':('SmoothPlastic',(236,226,160),40),'static':('SmoothPlastic',(113,115,103),3),
      'frame':('Metal',(62,58,46),4),'text':('SmoothPlastic',(72,66,54),4),'teal':('Plaster',(93,129,121),4),'mauve':('Plaster',(137,106,109),4),'skirt':('Concrete',(98,76,49),4),'cream':('SmoothPlastic',(188,174,124),4),'black':('SmoothPlastic',(18,20,18),4),'glass':('Glass',(58,64,56),4),'water':('Glass',(18,69,68),4),'orange':('Plaster',(165,82,35),4),'navy':('Plaster',(23,32,58),4),'red':('Fabric',(137,30,34),4),'rose':('SmoothPlastic',(175,119,146),4),'yellow':('Fabric',(200,160,34),4),'blue':('Fabric',(47,103,163),4),'green':('Fabric',(55,118,66),4),'purple':('Fabric',(109,52,135),4),'pale_blue':('Fabric',(122,175,186),4),'cloth':('Fabric',(211,196,144),8),'vinyl':('SmoothPlastic',(76,48,30),4),'metal':('Metal',(111,108,86),4),'light':('Neon',(238,225,155),4),'cyan':('Neon',(44,183,209),4),'magenta':('Neon',(206,44,151),4),'grey':('Metal',(125,123,107),4),'stage_carpet':('Carpet',(44,75,68),6),'hazard':('SmoothPlastic',(230,190,36),1.1)}
    palette.update({'detector_green':('Neon',(80,210,77),4),'velvet':('Fabric',(96,27,40),4),'case_glass':('Glass',(184,178,139),4),'amber':('Neon',(220,155,52),4),'gold':('Metal',(159,131,61),4),'olive':('Fabric',(133,143,90),4),'charcoal':('Fabric',(36,38,35),4),'wraith':('Fabric',(62,35,78),4),'pool_suit':('Fabric',(160,200,204),3),'survey_suit':('Fabric',(222,211,164),3),'false_suit':('Fabric',(231,212,162),3)})
    textured=set(['terrazzo','plaster','oak','ceiling','damask','beige_carpet','stand_carpet','triangle_carpet','road_carpet','small_tile','pegboard','puzzle_mat','black_ceiling','pad','brass','sign_face','static','stage_carpet','hazard','pool_suit','survey_suit','false_suit'])
    for k,(base,c,tile) in palette.items():D['materials'][k]={'base':base,'colour_map':f'textures/{k}.png' if k in textured else None,'normal_map':f'textures/{k}_normal.png' if k in textured else None,'roughness_map':f'textures/{k}_roughness.png' if k in textured else None,'studs_per_tile':tile}
    names=set()
    def part(n,g,pos,size,m='plaster',rot=(0,0,0),shape='Block',col=None,collide=True,transparency=0,glow=False):
        assert n not in names,n;names.add(n)
        p={'name':n,'group':g,'shape':shape,'pos':list(map(float,pos)),'size':list(map(float,size)),'rot':list(map(float,rot)),'color':list(col if col is not None else ((255,255,255) if m in textured else palette[m][1])),'material':m,'transparency':transparency,'collide':collide,'glow':glow};D['parts'].append(p);return p
    def box(n,g,x,y,z,sx,sy,sz,m='plaster',**kw):return part(n,g,(x,y,z),(sx,sy,sz),m,**kw)
    def cyl(n,g,x,y,z,r,h,m='metal',**kw):return part(n,g,(x,y,z),(h,2*r,2*r),m,rot=(0,0,90),shape='Cylinder',**kw)
    def ball(n,g,x,y,z,r,m='cream',**kw):return part(n,g,(x,y,z),(2*r,)*3,m,shape='Ball',**kw)
    def beam(n,g,a,b,w,m='metal',collide=True):
        a,b=np.array(a),np.array(b);direction=b-a;length=np.linalg.norm(direction);X=direction/length;Y=np.cross([0,1,0],X)
        if np.linalg.norm(Y)<1e-5:Y=np.array([1.,0,0])
        Y/=np.linalg.norm(Y);Z=np.cross(X,Y);return part(n,g,(a+b)/2,(length,w,w),m,angles(np.column_stack([X,Y,Z])),collide=collide)
    def sign(n,text,style,pos,size,normal,g='Concourse'):
        normal=np.array(normal,float);normal/=np.linalg.norm(normal);right=np.cross([0,1,0],normal);yaw=math.degrees(math.atan2(normal[0],normal[2]));w,h=size
        if style!='banner':part(n+'_Frame',g,np.array(pos)-normal*.18,(w+.24,h+.24,.24),'frame',rot=(0,yaw,0))
        face=part(n+'_Face',g,np.array(pos)-normal*.025,(w,h,.05),'sign_face' if style=='box' else ('yellow' if style=='tape' else ('cloth' if style=='banner' else 'cream')),rot=(0,yaw,0),collide=style!='tape',glow=style=='box')
        D['signs'].append({'name':n,'text':text,'style':style,'pos':list(map(float,pos)),'size':list(size),'normal':normal.tolist(),'part':face['name']})
    def light(n,kind,pos,col=(242,226,155),b=1.2,r=35,state='on'):D['lights'].append({'name':n,'kind':kind,'pos':list(pos),'color':list(col),'brightness':b,'range':r,'state':state})
    def wall(n,g,x,y,z,sx,sy,sz,m='plaster',stripes=True):
        # Split material bands instead of intersecting decals / overlapping coplanar boxes.
        if not stripes:return box(n,g,x,y,z,sx,sy,sz,m)
        lo,hi=y-sy/2,y+sy/2
        cuts=[(lo,31.2,'skirt'),(31.2,33.4,m),(33.4,34.2,'teal'),(34.2,34.4,m),(34.4,35.2,'mauve'),(35.2,hi,m)]
        for i,(a,b,mat) in enumerate(cuts):
            a=max(a,lo);b=min(b,hi)
            if b-a>=.05:box(f'{n}_{i}',g,x,(a+b)/2,z,sx,b-a,sz,mat)
    def hexagon(n,g,cx,cy,cz,r,h,m,gap=False):
        # Twelve non-overlapping Roblox WedgeParts, exactly a regular hexagonal prism.
        ap=r*math.sqrt(3)/2
        for i in range(6):
            theta=math.radians(30+i*60);N=np.array([math.cos(theta),0,math.sin(theta)]);T=np.array([-math.sin(theta),0,math.cos(theta)])
            if gap and i==4:continue # face normal south (-z)
            for j in (-1,1):
                X=np.array([0,j,0]);Y=T*j;Z=N;pos=np.array([cx,cy,cz])+N*ap/2+T*j*r/4
                part(f'{n}_{i}_{j}',g,pos,(h,r/2,ap),m,angles(np.column_stack([X,Y,Z])),shape='Wedge')
    def planter(n,x,z):
        box(n+'_Tub','Furniture',x,31.4,z,12,2.8,6,'vinyl');box(n+'_Soil','Furniture',x,32.83,z,11,.06,5,'black')
        for k in range(7):
            a=k*2.4;xx=x+4*math.cos(a);zz=z+1.5*math.sin(a)
            beam(f'{n}_Stem{k}','Furniture',(xx,32.9,zz),(xx,35.8,zz),.12,'green')
            for j in range(3):part(f'{n}_Leaf{k}_{j}','Furniture',(xx+math.cos(j*2)*.6,35+j*.25,zz+math.sin(j*2)*.6),(1.6,.16,.6),'green',rot=(15,j*120,20),collide=True)
        for k,dz in enumerate((-5,5)):
            box(f'{n}_Seat{k}','Furniture',x,32.2,z+dz,12,.45,2,'oak')
            for j,dx in enumerate((-5,5)):box(f'{n}_Leg{k}_{j}','Furniture',x+dx,31,z+dz,.4,1.75,1.5,'frame')
    # Floor slabs meet at edges; concourse has a continuous brown border.
    for g,z0,z1 in [('Concourse',-900,-621),('DarkWing',-621,-421)]:
        box(g+'_Floor',g,220,29.5,(z0+z1)/2,72,1,z1-z0,'terrazzo')
        for x in (182,258):box(f'{g}_Border{x}',g,x,29.5,(z0+z1)/2,4,1,z1-z0,'border')
    # Entrance and end wall.
    wall('EntranceWest','Arrival',190,38,-900.5,20,16,1)
    wall('EntranceEast','Arrival',250,38,-900.5,20,16,1)
    box('EntranceLintel','Arrival',220,43.5,-900.5,40,5,1)
    for i,x in enumerate((210,230)):
        box(f'Door{i}','Arrival',x,35.5,-900.5,19.5,11,.2,'glass')
        box(f'DoorFrame{i}','Arrival',x+9.85,35.5,-900.5,.2,11,.4,'frame')
        box(f'DoorHandle{i}','Arrival',x+7,35.4,-900.2,.18,2,.18,'brass')
    wall('DarkEnd','DarkWing',220,38,-420.5,80,16,1)
    box('ArrivalMat','Arrival',220,30.05,-891,28,.1,17.6,'vinyl')
    for x in (214.5,225.5):box(f'WelcomeRod{x}','Arrival',x,44.635,-886.12,.1,2.73,.1,'brass')
    sign('Welcome','WELCOME','box',(220,42.35,-886.3),(12,1.6),(0,0,-1),'Arrival')
    # Shop architecture and exhibits.
    shops=[(1,True,-840,'OFFICE','damask'),(2,False,-840,'POOLROOMS','small_tile'),(3,True,-760,'MALL PARTY','orange'),(4,False,-760,'CINEMA','navy'),(5,True,-680,'THE VOID','rose'),(6,False,-680,'PLAY ZONE','plaster')]
    pads=[]
    for level,west,z,name,mat in shops:
        g=f'Shop{level}';a,b=(127,180) if west else (260,313);front=b if west else a;back=a if west else b;show=(a+13 if west else b-13);padx=166 if west else 274
        # Floor 26-stud showcase + 27-stud queue. Void has a real recessed pit.
        box(g+'_QueueFloor',g,(a+b)/2+(13 if west else -13),29.5,z,27,1,58,'terrazzo')
        floor={'OFFICE':'beige_carpet','POOLROOMS':'small_tile','MALL PARTY':'road_carpet','CINEMA':'triangle_carpet','THE VOID':'rose','PLAY ZONE':'puzzle_mat'}[name]
        if level==5:
            box(g+'_Ledge',g,149,29.5,z,8,1,58,'rose');box(g+'_Pit',g,136,24.25,z,18,.5,56,'black')
        elif level==2:box(g+'_BasinFloor',g,show,28.55,z,26,.5,58,'small_tile');box(g+'_Water',g,show,29.4,z,26,1.2,56,'water',transparency=.25,collide=True)
        else:box(g+'_ShowFloor',g,show,29.5,z,26,1,58,floor)
        box(g+'_BackWall',g,back+(-.5 if west else .5),37,z,1,14,58,mat)
        for k,zz in enumerate((z-29.5,z+29.5)):
            box(f'{g}_Side{k}',g,(a+b)/2,37,zz,53,14,1,mat)
            wall(f'{g}_Pier{k}',g,front+(-1 if west else 1),36,z+(-27.5 if k==0 else 27.5),2,12,3)
            # Full 4x4 pier column sits on the concourse side. Its inner edge
            # remains at +/-26, preserving the 52-stud opening behind it.
            wall(f'{g}_PierColumn{k}',g,front+(2 if west else -2),38,z+(-28 if k==0 else 28),4,16,4)
        box(g+'_Fascia',g,front+(-1 if west else 1),44,z,2,4,52,'oak')
        normal=(1,0,0) if west else (-1,0,0)
        sign(g+'_Sign',f'{level} {name}','box',(front+(.31 if west else -.31),43.9,z),(40,3.2),normal,g)
        box(g+'_Ceiling',g,(a+b)/2+(-1 if west else 1),44.25,z,51,.5,58,'black_ceiling' if level==3 else ('rose' if level==5 else 'ceiling'))
        for k,dz in enumerate((-19,0,19),1):
            zz=z+dz;cyl(f'{g}_Pad{k}',g,padx,30.3,zz,7.4,.6,'pad')
            # Texture is an inlay, no extra overlapping discs.
            px=padx+(8.8 if west else -8.8)
            cyl(f'{g}_StationBase{k}',g,px,30.15,zz,.75,.3,'frame');box(f'{g}_StationPost{k}',g,px,32.15,zz,.16,4,.16,'brass')
            sign(f'{g}_Station{k}',f'STATION {k}','station',(px+(.2 if west else -.2),34.05,zz),(3.2,1.3),normal,g)
            pads.append({'level':level,'station':k,'pos':[padx,30.6,zz],'radius':7.4})
        # One recessed fluorescent in each back zone; cool Poolrooms only.
        if level!=5:
            box(g+'_Panel',g,show,43.92,z,8,.12,4,'light',glow=True)
            light(g+'_ShowLight','showcase',(show,43.7,z),(164,208,204) if level==2 else (240,222,143),3.2 if level==4 else 7.0,45)
        if level==1:
            box('OfficePillar',g,show+3,37,z-10,3,14,3,'damask');box('OfficeCabinet',g,128.51,35.2,z+15,3,5.6,8,'grey')
            for dz in (-2,2):box(f'OfficeCabinetHandle{dz}',g,130.1,35.2,z+15+dz,.15,1.4,.15,'frame')
        elif level==2:
            for k,(dx,dz) in enumerate([(-7,-20),(7,-10),(-7,0),(7,10),(-7,20)]):
                cyl(f'PoolColumn{k}',g,show+dx,35.85,z+dz,1.6,14.1,'small_tile')
                for j,r in enumerate((1.9,2.2,2.5)):
                    cyl(f'PoolCapital{k}_{j}',g,show+dx,42.9+(j+.5)*1.1/3,z+dz,r,1.1/3,'small_tile')
        elif level==3:
            # Black lower wall is adjacent, not embedded in the orange back wall.
            box('PartyBand',g,127.10,31.3,z,.18,2.6,58,'black')
            for k,dz in enumerate((-28.90,28.90)):
                box(f'PartySideBand{k}',g,show+.10,31.3,z+dz,25.8,2.6,.18,'black')
            box('PartyTable',g,show+3,33.6,z,5,.25,26,'cream')
            for dx in (-1.9,1.9):
                for dz in (-10,10):box(f'PartyLeg{dx}_{dz}',g,show+3+dx,31.8,z+dz,.18,3.35,.18,'metal')
            for k,dz in enumerate((-10,10)):
                beam(f'PartyCrossLeg{k}',g,(show+1.1,30.1,z+dz),(show+4.9,33.46,z+dz),.14,'metal')
            for k in range(9):cyl(f'PartyCup{k}',g,show+3,34.05,z-10+k*2.5,.23,.6,'red',collide=False)
            for bunch,dz in enumerate((-20,20)):
                for k in range(5):
                    xx=131+(k%2)*1.7;yy=38.5+(k//2)*1.6;zz=z+dz+(k%2)*.8
                    ball(f'Balloon{bunch}_{k}',g,xx,yy,zz,.8,['yellow','blue','green','red','purple'][k],collide=True)
                    beam(f'BalloonString{bunch}_{k}',g,(131,33,z+dz),(xx,yy-.8,zz),.05,'cream',collide=False)
        elif level==4:
            # Screen on the back wall; chairs look east towards it.
            box('CinemaScreen',g,312.35,38,z,.18,6,18,'light',glow=True);light('CinemaScreenLight','showcase',(311.8,38,z),(218,213,177),3.0,38)
            for k,(yy,matn,dz) in enumerate(((39.2,'magenta',-28.85),(39.2,'cyan',28.85))):
                box(f'CinemaNeon{k}',g,300,yy,z+dz,25,.1,.1,matn,glow=True);light(f'CinemaNeonLight{k}','neon',(289,yy,z+dz*.96),palette[matn][1],2.2,40)
            for row,xx in enumerate((294,303)):
                for k,zz in enumerate((z-9,z-3,z+3,z+9)):
                    box(f'CinemaSeat{row}_{k}',g,xx,32,zz,2.8,.55,3.4,'red');box(f'CinemaBack{row}_{k}',g,xx-1.65,33.8,zz,.5,3.6,3.4,'red')
                    box(f'CinemaBase{row}_{k}',g,xx,30.85,zz,1.5,1.15,2,'black')
        elif level==5:
            for k,zz in enumerate((z-12,z+12)):box(f'VoidBlock{k}',g,134+k*3,28.5,zz,5,8,5,'rose')
            box('VoidRod',g,148,33.525,z,.12,7.05,.12,'rose');ball('VoidGlobe',g,148,37.6,z,.55,'light',collide=False,glow=True);light('VoidLamp','globe',(148,37.6,z),(234,208,170),12,42)
        elif level==6:
            for ix,xx in enumerate((290,300,310)):
                for iz,zz in enumerate((z-20,z,z+20)):
                    cyl(f'PlayPost{ix}_{iz}',g,xx,36.5,zz,.7,13,['yellow','red','blue','green'][(ix+iz)%4])
            # Netting uses long intersecting noncolliding lines, all larger panels remain open.
            for side,xx in enumerate((290,310)):
                for yy in range(32,43,2):box(f'NetH{side}_{yy}',g,xx,yy,z,.05,.05,40,'black',collide=False)
                for zz in range(z-18,z+20,2):box(f'NetV{side}_{zz}',g,xx,36.5,zz,.05,11,.05,'black',collide=False)
            # Tube mouth: polygon ring, wall-facing circular opening and dark throat.
            for k in range(16):
                t=k*math.tau/16;part(f'SlideRim{k}',g,(291,34.1+3.5*math.cos(t),z+15+3.5*math.sin(t)),(1.7,.56,1.28),'yellow',rot=(math.degrees(t),0,0))
            part('SlideThroat',g,(292.1,34.1,z+15),(.25,6.1,6.1),'black',shape='Cylinder')
    # Continuous concourse wall segments between open shopfronts; repeated dead modules north.
    spans=[(-900,-870),(-810,-790),(-730,-710),(-650,-621)]
    for side,x in enumerate((179,261)):
        for k,(a,b) in enumerate(spans):wall(f'ConcourseWall{side}_{k}','Concourse',x,38,(a+b)/2,2,16,b-a)
    for side,west in enumerate((True,False)):
        a,b=(127,180) if west else (260,313);front=b if west else a;back=a if west else b
        for k,(z0,z1) in enumerate([(-609,-551),(-529,-471),(-449,-421)]):
            z=(z0+z1)/2;length=z1-z0
            box(f'DeadShop{side}_{k}_Floor','DarkWing',(a+b)/2,29.5,z,53,1,length,'terrazzo')
            box(f'DeadShop{side}_{k}_Back','DarkWing',back+(-.5 if west else .5),37,z,1,14,length,'plaster')
            for j,zz in enumerate((z0-0.5,z1+0.5)):
                box(f'DeadShop{side}_{k}_Side{j}','DarkWing',(a+b)/2,37,zz,53,14,1,'plaster')
                wall(f'DeadShop{side}_{k}_Pier{j}','DarkWing',front+(-1 if west else 1),36,zz+(.5 if j==0 else -.5)+(1.5 if j==0 else -1.5),2,12,3)
                wall(f'DeadShop{side}_{k}_PierColumn{j}','DarkWing',front+(2 if west else -2),38,(z0+2 if j==0 else z1-2),4,16,4)
            box(f'DeadShop{side}_{k}_Fascia','DarkWing',front+(-1 if west else 1),44,z,2,4,max(.05,length-6),'oak')
            box(f'DeadShop{side}_{k}_Ceiling','DarkWing',(a+b)/2+(-1 if west else 1),44.25,z,51,.5,length,'ceiling')
        for k,(z0,z1) in enumerate([(-621,-610),(-550,-530),(-470,-450)]):wall(f'DeadWall{side}_{k}','DarkWing',179 if west else 261,38,(z0+z1)/2,2,16,z1-z0)
    # 4x4 columns occupy closed wall bays only, preserving the exact 52-stud shop openings.
    for side,x in enumerate((182,258)):
        for z in range(-890,-420,20):
            if any(abs(z-c)<29 for c in (-840,-760,-680,-580,-500,-435)):continue
            pier_centres=[c+d for c in (-840,-760,-680,-580,-500) for d in (-28,28)]+[-447,-423]
            if any(abs(z-p)<4 for p in pier_centres):continue
            wall(f'Column{side}_{z}','Concourse' if z<-621 else 'DarkWing',x,38,z,4,16,4)
    # Ceiling: cut panels out of the slab, not placed coplanar on top of it.
    dead={(240,-830),(200,-750),(240,-690),(200,-650),(240,-650)}
    for x0,x1 in [(180,196),(204,236),(244,260)]:box(f'CeilingStrip{x0}','Ceiling',(x0+x1)/2,46.25,-760.5,x1-x0,.5,279,'ceiling')
    for x in (200,240):
        last=-900
        for z in range(-890,-629,20):
            if z-2>last:box(f'CeilingGap{x}_{z}','Ceiling',x,46.25,(last+z-2)/2,8,.5,z-2-last,'ceiling')
            box(f'PanelFrame{x}_{z}','Ceiling',x,46.25,z,8,.5,4,'frame')
            box(f'PanelLens{x}_{z}','Ceiling',x,45.94,z,7.8,.12,3.8,'grey' if (x,z) in dead else 'light',glow=(x,z) not in dead)
            if (x,z) not in dead:light(f'PanelLight{x}_{z}','panel',(x,45.72,z),b=.35 if (x,z)==(200,-810) else (6.5 if z==-670 else 3.8),r=48 if z==-670 else 39,state='dim_flicker' if (x,z)==(200,-810) else 'on')
            last=z+2
        box(f'CeilingEnd{x}','Ceiling',x,46.25,(last-621)/2,8,.5,-621-last,'ceiling')
    box('DarkCeiling','Ceiling',220,46.25,-521,80,.5,200,'ceiling')
    # Enlarged 1990s RMU. Six counter trapezoids tile an exact closed ring.
    # Side 1 is south; subsequent sides go counter-clockwise in plan.
    C=np.array([220.,0.,-770.]);outer_r=15.;ap=outer_r*math.sqrt(3)/2
    depth=4.;inner_ap=ap-depth;inner_r=inner_ap*2/math.sqrt(3)
    shop_spots=[];skin_plinths=[]
    hexagon('StandCarpet','Stand',220,30.06,-770,20,.12,'stand_carpet')
    for i in range(6):
        t=math.radians(-90+i*60);N=np.array([math.cos(t),0,math.sin(t)]);T=np.cross([0,1,0],N)
        yaw=math.degrees(math.atan2(N[0],N[2]));carpet_ap=20*math.sqrt(3)/2
        part(f'CarpetEdge{i}','Stand',C+N*(carpet_ap-.045)+[0,30.13,0],(19.9,.08,.09),'brass',rot=(0,yaw,0))
    headers=['ADVANCED EQUIPMENT','ENTITY DETECTOR','ITEMS','PACKS','RESEARCH TOKENS','SUPPORTER']
    offers=[
      [('AdvancedEquipment','ADVANCED EQUIPMENT - 149 ROBUX',0)],
      [('EntityDetector','ZYNTRA ENTITY DETECTOR - 149 ROBUX',0)],
      [('EntityShield','ENTITY SHIELD - 5 TOKENS',-4.1),('SpeedPotion','SPEED POTION - 3 TOKENS',0),('RouteMarker','ROUTE MARKER PACK - 2 TOKENS',4.1)],
      [('ExpeditionPack','EXPEDITION PACK - 69 ROBUX',-3.1),('EmergencyReentry','EMERGENCY RE-ENTRY',3.1)],
      [('Tokens4','4 TOKENS',-3.1),('Tokens20','20 TOKENS',3.1)],
      [('Supporter','ZYNTRA SUPPORTER - 99 ROBUX',-3.1),('CosmeticEquipment','GLOWSTICK CUSTOMIZER - 99 ROBUX',3.1)]]
    for i in range(6):
        t=math.radians(-90+i*60);N=np.array([math.cos(t),0,math.sin(t)]);T=np.cross([0,1,0],N)
        yaw=math.degrees(math.atan2(N[0],N[2]));rot=(0,yaw,0);mid=ap-depth/2
        def at(u,y,d=mid):return C+T*u+N*d+[0,y,0]
        def item(n,u,y,d,size,m='cream',**kw):return part(f'Product{i+1}_{n}','Stand',at(u,y,d),size,m,rot=kw.pop('rot',rot),**kw)
        def round_item(n,u,y,d,r,h,m='brass',**kw):return cyl(f'Product{i+1}_{n}','Stand',*at(u,y,d),r,h,m,**kw)
        # Ring body, beige top and brass kick occupy adjacent nonintersecting strata.
        for suffix,yy,h,mat in [('Body',31.28,2.32,'oak'),('Top',32.50,.12,'cream')]:
            part(f'Counter{i}_{suffix}','Stand',at(0,yy),(inner_r,h,depth),mat,rot=rot)
            delta=(outer_r-inner_r)/2
            for sg in (-1,1):
                X=np.array([0,-sg,0]);Y=T*sg;Z=N
                pos=C+N*mid+T*sg*(inner_r/2+delta/2)+[0,yy,0]
                part(f'Counter{i}_{suffix}_Miter{sg}','Stand',pos,(h,delta,depth),mat,angles(np.column_stack([X,Y,Z])),shape='Wedge')
        item('Kick',0,30.48,ap+.045,(14.6,.48,.07),'brass')
        item('Velvet',0,32.60,mid,(9.9,.08,3.6),'velvet')
        # Sloping glass is bounded by 33.72 (counter top = carpet top + 3.6).
        item('Glass',0,33.72-(.04*math.cos(math.radians(9))+2*math.tan(math.radians(9))),mid,(inner_r,.08,4/math.cos(math.radians(9))),
             'case_glass',rot=(9,yaw,0),transparency=.76)
        item('FrontRim',0,33.11,ap+.055,(14.5,.09,.09),'brass')
        item('RearRim',0,33.68,inner_ap-.025,(10.0,.08,.08),'brass')
        for k,u in enumerate((-4.5,4.5)):
            item(f'HeaderPost{k}',u,34.035,inner_ap-.18,(.12,.71,.12),'brass')
        item('HeaderRail',0,34.04,inner_ap-.18,(9.6,.1,.1),'brass')
        sign(f'CounterHeader{i}',headers[i],'box',at(0,34.65,inner_ap-.08),(9.4,1.05),N,'Stand')
        # Explicit product light stays under glass; skins get stronger individual can spots.
        light(f'ProductLight{i}','showcase',at(0,33.15,mid+.6).tolist(),(239,212,144),.40,12)
        for key,txt,u in offers[i]:
            width=12.0 if len(offers[i])==1 else (3.75 if len(offers[i])==3 else 5.8)
            sign('Price'+key,txt,'plain',at(u,32.02,ap+.33),(width,.45),N,'Stand')
            shop_spots.append({'key':key,'pos':at(u,30.12,ap+2.5).tolist()})
        if i==0:
            item('FlagshipTier',-1.2,32.70,mid,(6.4,.12,2.65),'velvet')
            item('TorchStand',-2.8,32.82,mid,(1.2,.12,.6),'brass')
            item('TorchBody',-2.8,33.12,mid,(2.1,.55,.65),'charcoal')
            item('TorchHead',-1.69,33.12,mid,(.18,.68,.68),'metal',shape='Cylinder')
            item('TorchLens',-1.58,33.12,mid,(.05,.52,.52),'light',shape='Cylinder',glow=True,collide=False)
            # A two-wedge taper expresses the torch beam using the permitted primitives.
            for sg in (-1,1):
                R=np.column_stack([-N*sg,np.array([0,sg,0]),T])
                part(f'Product1_TorchBeam{sg}','Stand',at(.075,33.12+sg*.19,mid),(.5,.38,3.2),'light',rot=angles(R),shape='Wedge',transparency=.88,glow=True,collide=False)
            round_item('Battery',3.0,33.08,inner_ap+.7,.28,.92,'yellow')
            round_item('BatteryCap',3.0,33.575,inner_ap+.7,.16,.07,'metal',collide=False)
            round_item('StaminaCanister',4.15,32.97,mid,.27,.66,'blue')
            for k,m in enumerate(('yellow','pale_blue','cream','charcoal','purple','false_suit')):
                item(f'Swatch{k}',4.2+(k-2.5)*.11,32.85,mid+1.0,(.65,.12,.90),m,rot=(0,yaw+(k-2.5)*10,0),collide=False)
        elif i==1:
            item('DetectorStand',-2.2,32.79,mid,(1.5,.25,1.1),'brass')
            item('Detector',-2.2,33.18,inner_ap+1.15,(2.15,.75,1.0),'charcoal',rot=(-18,yaw,0))
            item('DetectorScreen',-2.2,33.18,inner_ap+1.76,(1.7,.51,.06),'detector_green',glow=True)
            item('DetectorAerial',-3.35,33.13,inner_ap+.95,(.12,.12,1.2),'black',collide=False)
            item('OpenBox',2.6,32.73,mid,(2.8,.14,2.4),'velvet')
            for k,u in enumerate((1.25,3.95)):item(f'BoxSide{k}',u,33.01,mid,(.10,.46,2.4),'cream')
            item('BoxBack',2.6,33.01,inner_ap+.82,(2.6,.46,.1),'cream')
            item('BoxDetector',2.6,32.91,mid,(1.8,.24,1.35),'charcoal')
            item('BoxScreen',2.6,33.06,mid,(1.38,.06,.86),'detector_green',glow=True)
        elif i==2:
            item('Shield',-4.1,32.98,mid,(1.15,.63,1.15),'grey')
            round_item('ShieldCentre',-4.1,33.33,mid,.38,.06,'cyan',collide=False,glow=True)
            for k in range(4):
                round_item(f'Potion{k}',(k-1.5)*.48,32.93,mid,.17,.58,'purple')
                round_item(f'PotionCap{k}',(k-1.5)*.48,33.25,mid,.12,.06,'brass',collide=False)
            item('MarkerPack',4.1,32.72,mid,(1.6,.12,1.5),'cream')
            for k in range(3):
                item(f'Marker{k}',4.1+(k-1)*.45,32.99,mid,(.33,.42,.33),'orange',shape='Wedge')
        elif i==3:
            item('KitBase',-3.1,32.72,mid,(3.2,.14,2.9),'velvet')
            for k,u in enumerate((-4.64,-1.56)):
                item(f'KitSide{k}',u,32.94,mid,(.10,.28,2.9),'cream',collide=False)
            item('KitBack',-3.1,33.04,inner_ap+.64,(3.2,.53,.12),'cream')
            item('KeyCard',-3.95,32.90,mid,(.66,.14,1.04),'gold')
            item('KitShield',-2.5,32.96,inner_ap+1.08,(.75,.53,.75),'grey')
            for k in range(3):item(f'KitMarker{k}',-3.8+k*.58,32.99,mid+.8,(.32,.48,.32),'orange',shape='Wedge')
            item('KeyCushion',3.1,32.80,mid,(2.4,.30,2.0),'velvet')
            item('ReentryKey',3.1,33.005,mid,(1.2,.08,1.7),'gold')
            item('ReentryStripe',3.1,33.07,mid+.45,(1.1,.05,.20),'black',collide=False)
        elif i==4:
            for pile,u,total in [(0,-3.1,7),(1,3.1,22)]:
                item(f'TokenBox{pile}',u,32.74,mid,(3.1,.20,2.8),'velvet')
                for side,v in enumerate((-1.55,1.55)):
                    item(f'TokenBoxSide{pile}_{side}',u+v,32.98,mid,(.10,.28,2.8),'cream',collide=False)
                for side,dz in enumerate((-1.35,1.35)):
                    item(f'TokenBoxEnd{pile}_{side}',u,32.98,mid+dz,(3.0,.28,.10),'cream',collide=False)
                for k in range(total):
                    angle=k*2.4;r=.16+.20*(k%5)
                    round_item(f'Token{pile}_{k}',u+r*math.cos(angle),32.90+(k//7)*.10,mid+r*math.sin(angle),.29,.08,'brass',collide=False)
        elif i==5:
            item('BadgeEasel',-3.1,32.79,mid,(1.5,.25,1.0),'brass')
            item('BadgeFrame',-3.1,33.14,inner_ap+1.1,(1.55,.75,.12),'gold')
            item('Badge',-3.1,33.14,inner_ap+1.20,(1.30,.52,.06),'charcoal')
            round_item('BadgeStar',-3.1,33.58,inner_ap+1.1,.22,.06,'brass',collide=False)
            item('GlowstickRack',3.1,32.77,mid,(2.9,.24,1.1),'brass')
            for k,m in enumerate(('yellow','red','blue','green','purple','amber')):
                round_item(f'Glowstick{k}',3.1+(k-2.5)*.42,33.15,inner_ap+.75,.10,.69,m,collide=False,glow=True)
    # Central pegboard display tower reaches exactly y41; it has six faces.
    hexagon('TowerCore','Stand',220,(30.12+41)/2,-770,4.5,41-30.12,'pegboard')
    for i in range(6):
        t=math.radians(-90+i*60);N=np.array([math.cos(t),0,math.sin(t)]);T=np.cross([0,1,0],N)
        yaw=math.degrees(math.atan2(N[0],N[2]));tower_ap=4.5*math.sqrt(3)/2
        for shelf,yy in enumerate((35.3,37.0,38.7)):
            at=C+N*(tower_ap+.4)+[0,yy,0]
            part(f'DisplayShelf{i}_{shelf}','Stand',at,(3.55,.12,.72),'brass',rot=(0,yaw,0))
            if i==0 and shelf>0:continue
            for k in range(3):
                pos=at+T*(k-1)*1.05+[0,.43,0]
                part(f'Goods{i}_{shelf}_{k}','Stand',pos,(.78,.70,.50),('yellow','blue','cream')[(i+k)%3],rot=(0,yaw,0))
        if i==0:
            pos=C+N*(tower_ap+.78)+[0,37.4,0]
            part('StandCRT','Stand',pos,(2.9,2.5,1.4),'frame',rot=(0,yaw,0))
            part('StandCRTScreen','Stand',pos+N*.75,(2.45,1.9,.08),'static',rot=(0,yaw,0),glow=True)
        arm0=C+N*4.55+[0,40.2,0];arm1=C+N*5.8+[0,40.2,0]
        beam(f'GlobeArm{i}','Stand',arm0,arm1,.16,'brass');ball(f'StandGlobe{i}','Stand',*arm1,.62,'light',collide=False,glow=True)
        light(f'StandLamp{i}','globe',arm1.tolist(),b=.95,r=20)
        # Shallow sign faces fill each face of the 2.4-high hexagonal fascia.
        sign(f'StandSign{i}','SHOP & SUPPLIES','box',C+N*(7*math.sqrt(3)/2+.05)+[0,42.22,0],(6.42,2.16),N,'Stand')
    hexagon('StandCanopy','Stand',220,43.51,-770,7,.16,'oak')
    skins=[('BaselineYellow','BASELINE YELLOW - FREE','yellow',-120),
           ('PoolService','POOL SERVICE - 25 TOKENS','pool_suit',-60),
           ('SuburbSurvey','SUBURB SURVEY - 75 TOKENS','survey_suit',0),
           ('BlacksiteDirector','BLACKSITE DIRECTOR - 300 TOKENS','charcoal',60),
           ('StaticWraith','STATIC WRAITH - 99 ROBUX','wraith',120),
           ('FalseSun','FALSE SUN - 149 ROBUX','false_suit',180)]
    for index,(skin,txt,mat,theta) in enumerate(skins):
        t=math.radians(theta);N=np.array([math.cos(t),0,math.sin(t)]);T=np.cross([0,1,0],N)
        yaw=math.degrees(math.atan2(N[0],N[2]));rot=(0,yaw,0);foot=C+N*17.5+[0,31.12,0]
        cyl('SkinPlinth'+skin,'Stand',* (foot-[0,.5,0]),2.3,1.0,'oak')
        skin_plinths.append({'skin':skin,'pos':foot.tolist(),'facing':N.tolist()})
        def suit(n,off,size,m=mat,**kw):return part(skin+'_'+n,'Stand',foot+T*off[0]+np.array([0,off[1],0])+N*off[2],size,m,rot=kw.pop('rot',rot),**kw)
        for k,u in enumerate((-.40,.40)):
            suit(f'Boot{k}',(u,.25,.08),(.67,.50,1.04),'black')
            suit(f'Leg{k}',(u,1.19,0),(.66,1.38,.70))
        suit('Torso',(0,2.80,0),(1.58,1.80,.90))
        suit('Belt',(0,1.92,.02),(1.67,.15,.98),'black')
        suit('Zipper',(0,2.80,.49),(.08,1.70,.06),'olive',collide=False)
        for k,u in enumerate((-1.05,1.05)):
            suit(f'Arm{k}',(u,2.80,0),(.46,1.78,.65))
            suit(f'Glove{k}',(u,1.76,.035),(.46,.30,.68),'black')
            suit(f'Strap{k}',(u*.54,2.86,.52),(.19,1.61,.08),'black')
        suit('Neck',(0,3.79,0),(.60,.18,.60),'black')
        ball(skin+'_Hood','Stand',*(foot+[0,4.54,0]),.66,mat,collide=True)
        suit('Mask',(0,4.51,.55),(1.00,1.00,.20),'black',shape='Ball')
        lens='purple' if skin=='StaticWraith' else ('amber' if skin=='FalseSun' else 'glass')
        for k,u in enumerate((-.255,.255)):
            suit(f'EyeRim{k}',(u,4.67,.69),(.10,.45,.45),'metal',shape='Cylinder',rot=(0,yaw-90,0))
            # Cylinder local X is the outward normal after this orientation.
            eye=D['parts'][-1];eye['rot']=[0,yaw-90,0]
            suit(f'Lens{k}',(u,4.67,.765),(.055,.34,.34),lens,shape='Cylinder',collide=False,glow=skin in ('StaticWraith','FalseSun'))
            D['parts'][-1]['rot']=[0,yaw-90,0]
        suit('Respirator',(0,4.24,.72),(.24,.38,.38),'frame',shape='Cylinder')
        D['parts'][-1]['rot']=[0,yaw-90,0]
        suit('Backpack',(0,2.87,-.73),(1.13,1.55,.50),'black')
        for k,u in enumerate((-.73,.73)):
            suit(f'Tank{k}',(u,2.92,-.64),(1.35,.30,.30),'black',shape='Cylinder')
            D['parts'][-1]['rot']=[0,0,90]
        if skin=='BlacksiteDirector':
            for k,u in enumerate((-.63,.63)):suit(f'GoldTrim{k}',(u,2.81,.535),(.06,1.65,.06),'gold',collide=False)
        if skin=='StaticWraith':
            for k,u in enumerate((-.33,.33)):
                suit(f'PurpleTube{k}',(u,2.87,-1.025),(1.20,.12,.12),'purple',shape='Cylinder',collide=False,glow=True)
                D['parts'][-1]['rot']=[0,0,90]
        if skin=='FalseSun':
            suit('SunDisc',(0,2.87,-1.025),(.08,.81,.81),'amber',shape='Cylinder',collide=False,glow=True)
            D['parts'][-1]['rot']=[0,yaw-90,0]
        sign('SkinPrice'+skin,txt,'plain',foot+N*2.38-[0,.57,0],(3.5,.39),N,'Stand')
        arm0=C+N*6.85+[0,43.55,0];arm1=C+N*17.5+[0,41.3,0]
        beam('SkinLampArm'+skin,'Stand',arm0,arm1,.12,'brass')
        cyl('SkinLampCan'+skin,'Stand',arm1[0],41.03,arm1[2],.30,.54,'brass')
        cyl('SkinLampLens'+skin,'Stand',arm1[0],40.72,arm1[2],.25,.08,'light',collide=False,glow=True)
        light('SkinSpot'+skin,'showcase',[float(arm1[0]),40.65,float(arm1[2])],(247,225,174),.75,13)
    planter('PlanterArrival',220,-835);planter('PlanterNorth',220,-700)
    # Blank, flat leaderboard faces (no pretend scores or UI).
    boards=[]
    for key,x,z,w,h,norm in [('directory',185,-795,18,12,(1,0,0)),('level1',195,-825,8,10,(1,0,0)),('level2',245,-855,8,10,(-1,0,0)),('level3',195,-745,8,10,(1,0,0)),('level4',245,-745,8,10,(-1,0,0)),('level5',195,-665,8,10,(1,0,0)),('level6',245,-695,8,10,(-1,0,0))]:
        # Suspend the two boards beside the enlarged stand. No board height was
        # specified; bottom35.4 leaves >5 studs of walkable clearance underneath.
        y=(40.4 if key in ('level3','level4') else 31+h/2);yaw=90 if norm[0]>0 else -90
        part(key+'_BoardFrame','Furniture',(x,y,z),(w+.4,h+.4,.35),'oak',rot=(0,yaw,0))
        pos=[x+norm[0]*.205,y,z];part(key+'_BoardFace','Furniture',pos,(w,h,.06),'black',rot=(0,yaw,0))
        for dz in (-w*.35,w*.35):
            if key in ('level3','level4'):box(key+f'_BoardHanger{dz}','Furniture',x,45.8,z+dz,.12,.4,.12,'brass')
            else:box(key+f'_BoardLeg{dz}','Furniture',x,30.5,z+dz,.3,1,.3,'brass')
        boards.append({'key':key,'pos':pos,'size':[w,h],'normal':list(norm)})
    sign('DirectoryHeader','DIRECTORY','box',(185.30,44.12,-795),(18,1.6),(1,0,0),'Furniture')
    # Small fake plants next to closed bays, away from pad and path clearances.
    for i,(x,z) in enumerate([(186,-807),(256,-805),(184,-725),(256,-725),(182,-645),(258,-645)]):
        cyl(f'PlantTub{i}','Furniture',x,31.2,z,1.8,2.4,'vinyl')
        for k in range(5):part(f'PlantLeaf{i}_{k}','Furniture',(x+math.cos(k*1.5)*.6,34.0,z+math.sin(k*1.5)*.6),(.25,2.3,1.0),'green',rot=(12,k*72,12),collide=True)
    # Two nested trolley trains, plain wire-frame 1990s carts.
    for side,x in enumerate((187,253)):
        for k,z in enumerate((-879,-876,-873)):
            for j,dz in enumerate((-1.8,1.8)):
                for q,dx in enumerate((-1.3,1.3)):part(f'TrolleyWheel{side}_{k}_{j}_{q}','Arrival',(x+dx,30.45,z+dz),(.25,.8,.8),'black',shape='Cylinder')
            box(f'TrolleyTray{side}_{k}','Arrival',x,31.2+k*.18,z,3,.12,4,'metal')
            for j,dx in enumerate((-1.5,1.5)):
                for yy in (31.7,32.3,32.9,33.5):box(f'TrolleyWire{side}_{k}_{j}_{yy}','Arrival',x+dx,yy,z,.06,.06,4,'metal',collide=False)
                for q,dz in enumerate((-2,-1,0,1,2)):box(f'TrolleyUpright{side}_{k}_{j}_{q}','Arrival',x+dx,32.3,z+dz,.06,2.4,.06,'metal',collide=False)
            box(f'TrolleyHandle{side}_{k}','Arrival',x,34,z-2,3.2,.14,.14,'vinyl')
    # Stage and chairs; three fallen, all touchable large pieces collide.
    box('StageDeck','Stage',220,31,-643.5,30,2,23,'stage_carpet')
    for k in range(3):box(f'StageStep{k}','Stage',220,30+(k+1)/3,-657.5+k,12,2*(k+1)/3,1,'stage_carpet')
    box('DJTableTop','Stage',220,35.3,-639,10,.3,4,'cream')
    for x in (216,224):
        for k,sg in enumerate((-1,1)):
            beam(f'DJTableLeg{x}_{k}','Stage',(x,32.08,-639+sg*1.3),(x,35.15,-639-sg*1.3),.15,'metal')
    box('DJConsole','Stage',220,35.85,-639,8,.8,3,'black')
    for i,x in enumerate((217.5,222.5)):cyl(f'DJTurntable{i}','Stage',x,36.31,-639,.75,.1,'grey',collide=True)
    for i,x in enumerate((208,232)):
        box(f'SpeakerStand{i}','Stage',x,34,-636,.25,4,.25,'frame');box(f'Speaker{i}','Stage',x,37,-636,3,3.8,2,'black')
        for j,yy in enumerate((36.3,37.5)):part(f'SpeakerCone{i}_{j}','Stage',(x,yy,-637.06),( .12,1.1,1.1),'grey',rot=(0,90,0),shape='Cylinder',collide=True)
    for x in (205,235):box(f'BannerPole{x}','Stage',x,37,-632,.2,10,.2,'brass')
    sign('StageBanner','GRAND OPENING','banner',(220,39,-632.3),(27,2.6),(0,0,-1),'Stage')
    def chair(n,x,z,fallen=False):
        pieces=[('Seat',(0,1.8,0),(2.6,.18,2.4),'cream'),('Back',(0,3,-1.3),(2.6,2.1,.15),'cream')]
        for dx in (-1,1):
            for dz in (-.9,.9):pieces.append((f'Leg{dx}_{dz}',(dx,.85,dz),(.12,1.7,.12),'metal'))
        R=rotation((78,0,0)) if fallen else np.eye(3)
        for suffix,p,size,m in pieces:
            at=np.array([x,30.1 if not fallen else 30.94,z])+R@np.array(p)
            part(n+suffix,'Stage',at,size,m,rot=angles(R))
    for row,z in enumerate((-672,-666)):
        for k,x in enumerate((218,222,226,230,234)):chair(f'Chair{row}_{k}',x,z,(row,k) in [(0,0),(0,4),(1,4)])
    # Exactly seven poles + one touchable strip of tape; no other barrier.
    for k,x in enumerate(range(184,257,12)):
        cyl(f'TapeBase{k}','Tape',x,30.15,-621,1.1,.3,'black')
        cyl(f'TapePole{k}','Tape',x,31.95,-621,.18,3.3,'hazard')
    # Single tape face, ten repeats with spaces equal to approximately two words.
    box('DangerTape','Tape',220,33.2,-621,72,.5,.05,'yellow',collide=True)
    D['signs'].append({'name':'TapeText','text':('DANGER: DO NOT GO PAST THIS POINT'+'            ')*9+'DANGER: DO NOT GO PAST THIS POINT','style':'tape','pos':[220,33.2,-621.031],'size':[71,.46],'normal':[0,0,-1],'part':'DangerTape'})
    D['anchors']={'spawn':[220,30,-860],'pads':pads,'shop_stand':{'centre':[220,30,-770],'radius':20},'shop_spots':shop_spots,'skin_plinths':skin_plinths,'boards':boards,'dj_console':[220,35.85,-639],'stage_deck':{'min':[205,30,-655],'max':[235,32,-632]},'tape_z':-621,'dark_wing':{'min':[184,30,-621],'max':[256,46,-421]}}
    return D

# Mesh vertices are created in Roblox local axes then S-converted; no guessed Euler mapping.
def local_mesh(shape,size,segments=20):
    sx,sy,sz=np.array(size)/2
    if shape=='Block':
        v=[(-sx,-sy,-sz),(-sx,-sy,sz),(-sx,sy,-sz),(-sx,sy,sz),(sx,-sy,-sz),(sx,-sy,sz),(sx,sy,-sz),(sx,sy,sz)]
        f=[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]
    elif shape=='Wedge':
        v=[(-sx,-sy,-sz),(sx,-sy,-sz),(-sx,-sy,sz),(sx,-sy,sz),(-sx,sy,sz),(sx,sy,sz)]
        f=[(0,2,3,1),(2,4,5,3),(0,1,5,4),(0,4,2),(1,3,5)]
    elif shape=='Cylinder':
        v=[(x,sy*math.cos(k*math.tau/segments),sz*math.sin(k*math.tau/segments)) for x in (-sx,sx) for k in range(segments)]
        f=[tuple(range(segments-1,-1,-1)),tuple(range(segments,2*segments))]+[(k,(k+1)%segments,(k+1)%segments+segments,k+segments) for k in range(segments)]
    else:
        v=[];f=[];lat=10
        for j in range(lat+1):
            t=math.pi*j/lat
            for k in range(segments):a=k*math.tau/segments;v.append((sx*math.sin(t)*math.cos(a),sy*math.sin(t)*math.sin(a),sz*math.cos(t)))
        for j in range(lat):
            for k in range(segments):f.append((j*segments+k,j*segments+(k+1)%segments,(j+1)*segments+(k+1)%segments,(j+1)*segments+k))
    v=np.array(v,float);centre=v.mean(0);out=[]
    for face in f:
        q=v[list(face)];n=np.cross(q[1]-q[0],q[2]-q[0]);out.append(tuple(reversed(face)) if np.dot(n,q.mean(0)-centre)<0 else face)
    return v,out

def blender_scene(D):
    import bpy
    from mathutils import Matrix,Vector
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE';scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=960;scene.render.resolution_y=540;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGB';scene.render.film_transparent=False
    scene.world.color=(0,0,0);scene.world.use_nodes=True;scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=0
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
    if hasattr(scene,'eevee'):
        scene.eevee.taa_render_samples=16
        scene.eevee.use_raytracing=False
    scene.render.use_file_extension=True
    mats={};groups={}
    def mat_for(p):
        key=(p['material'],tuple(p['color']),p['glow'],p['transparency'],p['name'].endswith('_Face'))
        if key in mats:return mats[key]
        m=bpy.data.materials.new(str(key));m.use_nodes=True;bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=tuple((c/255)**2.2 for c in p['color'])+(1,);bs.inputs['Roughness'].default_value=.93;bs.inputs['Specular IOR Level'].default_value=.08
        rec=D['materials'][p['material']]
        if rec['colour_map']:
            tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(OUT/rec['colour_map']),check_existing=True);m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
        if rec['roughness_map']:
            rough=m.node_tree.nodes.new('ShaderNodeTexImage');rough.image=bpy.data.images.load(str(OUT/rec['roughness_map']),check_existing=True);rough.image.colorspace_settings.name='Non-Color';m.node_tree.links.new(rough.outputs['Color'],bs.inputs['Roughness'])
        if rec['normal_map']:
            norm=m.node_tree.nodes.new('ShaderNodeTexImage');norm.image=bpy.data.images.load(str(OUT/rec['normal_map']),check_existing=True);norm.image.colorspace_settings.name='Non-Color';nm=m.node_tree.nodes.new('ShaderNodeNormalMap');m.node_tree.links.new(norm.outputs['Color'],nm.inputs['Color']);m.node_tree.links.new(nm.outputs['Normal'],bs.inputs['Normal'])
        if p['glow']:
            bs.inputs['Emission Color'].default_value=tuple((c/255)**2.2 for c in p['color'])+(1,)
            if rec['colour_map']:m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Emission Color'])
            bs.inputs['Emission Strength'].default_value=.8 if p['material']=='sign_face' else 1.0
        if p['material']=='sign_face':
            emission=m.node_tree.nodes.new('ShaderNodeEmission');emission.inputs['Strength'].default_value=1
            m.node_tree.links.new(tex.outputs['Color'],emission.inputs['Color']);m.node_tree.links.new(emission.outputs['Emission'],m.node_tree.nodes.get('Material Output').inputs['Surface'])
        if p['transparency']:
            # Muted water and bronze glass. No artificial transparency for any solid geometry.
            bs.inputs['Alpha'].default_value=1-p['transparency'];m.surface_render_method='BLENDED'
            if hasattr(m,'use_transparency_overlap'):m.use_transparency_overlap=False
        if (p['glow'] or p['name'].endswith('_Face')) and not p['transparency'] and p['material']!='sign_face':
            emission=m.node_tree.nodes.new('ShaderNodeEmission');emission.inputs['Strength'].default_value=1
            emission.inputs['Color'].default_value=tuple((c/255)**2.2 for c in p['color'])+(1,)
            if rec['colour_map']:m.node_tree.links.new(tex.outputs['Color'],emission.inputs['Color'])
            m.node_tree.links.new(emission.outputs['Emission'],m.node_tree.nodes.get('Material Output').inputs['Surface'])
        mats[key]=m;return m
    for p in D['parts']:
        if p['group'] not in groups:
            col=bpy.data.collections.new(p['group']);scene.collection.children.link(col);groups[p['group']]=col
        v,f=local_mesh(p['shape'],p['size']);mesh=bpy.data.meshes.new(p['name']);mesh.from_pydata((v@S.T).tolist(),[],[tuple(reversed(face)) for face in f]);mesh.update();ob=bpy.data.objects.new(p['name'],mesh);groups[p['group']].objects.link(ob)
        ob.location=Vector(S@p['pos']);ob.rotation_mode='QUATERNION';ob.rotation_quaternion=Matrix((S@rotation(p['rot'])@S.T).tolist()).to_quaternion();ob.data.materials.append(mat_for(p));ob['part_name']=p['name'];ob['group']=p['group']
        uv=mesh.uv_layers.new(name='StudsUV');tile=D['materials'][p['material']]['studs_per_tile']
        for poly in mesh.polygons:
            rn=S.T@np.array(poly.normal);axis=int(np.argmax(abs(rn)));axes=[a for a in range(3) if a!=axis]
            for li in poly.loop_indices:
                vi=mesh.loops[li].vertex_index;q=v[vi]
                if p['material']=='hazard' and axis!=0:coords=(math.atan2(q[2],q[1])/math.tau,q[0]/tile)
                elif p['material']=='pad' and axis==0:coords=(q[1]/p['size'][1]+.5,q[2]/p['size'][2]+.5)
                elif p['material']=='sign_face':coords=(q[0]/p['size'][0]+.5,q[1]/p['size'][1]+.5)
                else:coords=(q[axes[0]]/tile,q[axes[1]]/tile)
                uv.data[li].uv=coords
    font=bpy.data.fonts.load(FONT)
    textmat=bpy.data.materials.new('DIN dark warm grey');textmat.diffuse_color=(.062,.053,.039,1);textmat.use_nodes=True;textmat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.062,.053,.039,1)
    emission=textmat.node_tree.nodes.new('ShaderNodeEmission');emission.inputs['Color'].default_value=tuple((c/255)**2.2 for c in (72,66,54))+(1,);emission.inputs['Strength'].default_value=1;textmat.node_tree.links.new(emission.outputs[0],textmat.node_tree.nodes.get('Material Output').inputs['Surface'])
    tapemat=bpy.data.materials.new('Tape black ink');tapemat.use_nodes=True;tapemat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.005,.006,.005,1)
    for sign in D['signs']:
        curve=bpy.data.curves.new(sign['name']+'_Text','FONT');curve.body=sign['text'];curve.font=font;curve.align_x='CENTER';curve.align_y='CENTER';curve.size=1;curve.extrude=0;curve.resolution_u=2
        ob=bpy.data.objects.new(sign['name']+'_Text',curve);scene.collection.objects.link(ob);ob.data.materials.append(tapemat if sign['style']=='tape' else textmat)
        normal=S@np.array(sign['normal']);up=np.array([0.,0,1]);right=np.cross(up,normal);basis=np.column_stack([right,up,normal]);ob.rotation_mode='QUATERNION';ob.rotation_quaternion=Matrix(basis.tolist()).to_quaternion();ob.location=Vector(S@np.array(sign['pos'])+normal*.012)
        bpy.context.view_layer.update();h=ob.dimensions.z if abs(normal[2])<.01 else max(ob.dimensions)
        # Use local text bounds for exact cap height, independent of viewing orientation.
        bb=np.array(ob.bound_box);height=max(bb[:,1])-min(bb[:,1]);width=max(bb[:,0])-min(bb[:,0]);scale=sign['size'][1]*(.55 if sign['style']=='box' else (.85 if sign['style']=='tape' else .62))/max(height,.001)
        ob.scale=((sign['size'][0]/max(width,.001) if sign['style']=='tape' else min(scale,sign['size'][0]*.94/max(width,.001))),scale,scale);ob['sign_name']=sign['name']
    for l in D['lights']:
        kind='SPOT' if l['name'].startswith('SkinSpot') else ('AREA' if l['name'].startswith('Shop') and l['kind']=='showcase' else 'POINT')
        data=bpy.data.lights.new(l['name'],kind);data.color=tuple(c/255 for c in l['color']);data.energy=l['brightness']*(380 if l['kind']=='globe' else 1900);data.use_shadow=l['kind'] in ('showcase','neon')
        if data.type=='AREA':data.shape='RECTANGLE';data.size=26;data.size_y=56
        elif data.type=='SPOT':data.spot_size=math.radians(40);data.spot_blend=.5;data.shadow_soft_size=.15
        else:data.shadow_soft_size=2.5 if l['name']=='VoidLamp' else (.55 if l['kind']=='globe' else 4.0)
        data.use_custom_distance=True;data.cutoff_distance=l['range']
        ob=bpy.data.objects.new(l['name'],data);scene.collection.objects.link(ob);ob.location=Vector(S@l['pos']);ob['data_light']=True
        if l['kind'] in ('showcase','neon') and l['name'].startswith('Cinema'):ob.rotation_euler=(0,-math.pi/2,0)
        ob['state']=l['state']
    probes=[]
    specs=[('ConcourseBounce',[220,38,-760.5],[39,138.5,8.2],(5,18,3))]
    for level in range(1,7):
        specs.append((f'Shop{level}Bounce',[153.5 if level%2 else 286.5,37,-840+80*((level-1)//2)],[25.5,28,7.2],(4,5,3)))
    for name,pos,scale,res in specs:
        probe=bpy.data.lightprobes.new(name,'VOLUME');probe.resolution_x,probe.resolution_y,probe.resolution_z=res
        probe.bake_samples=16;probe.surfel_density=2;probe.capture_world=False;probe.capture_emission=False;probe.capture_indirect=True
        ob=bpy.data.objects.new(name,probe);scene.collection.objects.link(ob);ob.location=Vector(S@pos);ob.scale=scale;probes.append(ob)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for ob in probes:ob.select_set(True)
    bpy.context.view_layer.objects.active=probes[0]
    print('BOUNCE_BAKE_BEGIN: 630 samples; 16 rays; density 2',flush=True)
    bpy.ops.object.lightprobe_cache_bake(subset='SELECTED')
    print('BOUNCE_BAKE_COMPLETE',flush=True)
    # Store authoritative data in .blend for render tool and parity QA.
    t=bpy.data.texts.new('mall.json');t.write(json.dumps(D,sort_keys=True));scene['design_sha256']=__import__('hashlib').sha256(json.dumps(D,sort_keys=True).encode()).hexdigest()
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'mall.blend'))
    print('BUILD:',len(D['parts']),'parts,',len(D['signs']),'signs,',len(D['lights']),'lights')

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    if '--textures-only' in sys.argv:textures();return
    if 'bpy' not in sys.modules:
        try:import bpy
        except ImportError:
            (OUT/'mall.json').write_text(json.dumps(design(),indent=2)+'\n');print('JSON design exported');return
    subprocess.run(['/usr/local/bin/python3',str(Path(__file__).resolve()),'--textures-only'],check=True,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
    D=design();(OUT/'mall.json').write_text(json.dumps(D,indent=2)+'\n')
    import hashlib,bpy
    fingerprint=hashlib.sha256(Path(__file__).read_bytes()+Path(FONT).read_bytes()+str(bpy.app.version).encode()+json.dumps(D,sort_keys=True).encode()+b''.join(p.read_bytes() for p in sorted((OUT/'textures').glob('*.png')))).hexdigest()
    record=OUT/'build_fingerprint.json';blend=OUT/'mall.blend'
    previous=json.loads(record.read_text()) if record.exists() else {}
    if blend.exists() and previous.get('input_sha256')==fingerprint and previous.get('blend_sha256')==hashlib.sha256(blend.read_bytes()).hexdigest():
        print('UNCHANGED: verified byte-identical blend reused');return
    import tempfile
    with tempfile.TemporaryDirectory(prefix='stayquiet_mall_',dir='/tmp') as scratch:
        import bpy
        bpy.context.preferences.filepaths.temporary_directory=scratch
        blender_scene(D)
    record.write_text(json.dumps({'input_sha256':fingerprint,'blend_sha256':hashlib.sha256(blend.read_bytes()).hexdigest()},indent=2)+'\n')

if __name__=='__main__':main()
