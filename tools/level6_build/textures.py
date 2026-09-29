"""Author the shared worn-party atlas; all pixels are original procedural artwork."""
from pathlib import Path
import json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/level6-worn-party/textures'
N=512
rng=np.random.default_rng(603091)
PALETTE={
 'ivory_plastic':(197,184,145),'red_plastic':(150,34,25),
 'yellow_plastic':(193,149,26),'green_plastic':(39,99,48),'blue_plastic':(34,74,99),
 'black_metal':(29,28,26),'chrome':(151,151,136),'grey_metal':(95,97,88),
 'glass':(45,65,61),'screen_dark':(10,17,24),'screen_cyan':(91,175,184),
 'screen_magenta':(173,76,113),'screen_green':(95,157,91),'paper':(211,201,166),
 'rubber':(22,23,21),'balloon_red':(157,37,28),'balloon_yellow':(187,152,36),
 'balloon_green':(35,96,51),'balloon_blue':(30,76,112),'cd_silver':(150,164,176),
 'glow':(246,232,175),'dark_red':(79,31,26),'orange_plastic':(155,78,35),
 'pink_plastic':(167,96,98),'cream':(194,181,135),'tape':(136,115,75),
 'rust':(106,61,36),'blue_door':(74,93,87),'black':(15,15,13),'white':(219,213,192),
 'purple':(91,61,106),'brass':(120,96,41),'orange_wall':(159,75,32),
 'red_wall':(132,46,27),'beige_wall':(179,162,120),'ceiling_grid':(80,76,59)
}
CELLS={
 'beige_wall':0,'orange_wall':1,'red_wall':2,'black_wall':3,'ceiling':4,
 'carpet_beige':5,'carpet_confetti':6,'carpet_red':7,'linoleum':8,
 'laminate':9,'wood_worn':10,'metal_worn':11,'cardboard':12,'paper_worn':13,'service_door':14
}

def noise(n=N):
    fine=rng.normal(0,1,(n,n))
    coarse=np.asarray(Image.fromarray(rng.integers(0,256,(16,16),dtype=np.uint8)).resize((n,n),Image.Resampling.BICUBIC),dtype=float)/128-1
    broad=np.asarray(Image.fromarray(rng.integers(0,256,(5,5),dtype=np.uint8)).resize((n,n),Image.Resampling.BICUBIC),dtype=float)/128-1
    return fine*2.5+coarse*7+broad*5

def surface(color,amount=1):
    return Image.fromarray(np.clip(np.array(color)[None,None,:]+noise()[:,:,None]*amount,0,255).astype('uint8'))

def finish(im,wear=1):
    a=np.array(im,dtype=float);a+=rng.normal(0,3*wear,(N,N,1))
    return Image.fromarray(np.clip(a,0,255).astype('uint8'))

def paint(color):
    im=surface(color,.85);d=ImageDraw.Draw(im)
    for _ in range(28):
        x,y=rng.integers(0,N,2);d.line((int(x),int(y),int(x+rng.integers(2,16)),int(y+rng.integers(-3,3))),fill=tuple(int(c*.76) for c in color),width=1)
    return finish(im,.65)

def carpet(kind):
    bg={'beige':(78,72,44),'confetti':(31,31,32),'red':(108,31,25)}[kind]
    im=surface(bg,1.4);d=ImageDraw.Draw(im)
    colors={'beige':[(102,85,40),(46,57,40),(92,52,35),(122,100,53)],'confetti':[(139,49,41),(161,126,48),(38,68,104),(44,91,71)],'red':[(139,64,38),(73,30,28),(150,98,45),(92,42,28)]}[kind]
    if kind=='beige':
        for y in range(-64,N+64,56):
            for x in range(-64,N+64,56):
                c=colors[int(rng.integers(len(colors)))];d.polygon([(x,y+28),(x+28,y),(x+56,y+28),(x+28,y+56)],fill=c)
                d.line([(x+7,y+28),(x+28,y+7),(x+49,y+28),(x+28,y+49),(x+7,y+28)],fill=(60,58,39),width=3)
    elif kind=='confetti':
        for y in range(8,N,25):
            for x in range(8,N,27):
                x+=int(rng.integers(-5,6));y2=y+int(rng.integers(-5,6));c=colors[int(rng.integers(len(colors)))];r=int(rng.integers(3,7))
                if rng.random()<.55:d.polygon([(x+math.cos(i*math.pi/5)*r*(1 if i%2==0 else .45),y2+math.sin(i*math.pi/5)*r*(1 if i%2==0 else .45)) for i in range(10)],fill=c)
                else:d.line((x-r,y2-r,x+r,y2+r),fill=c,width=3)
    else:
        for y in range(-64,N+64,64):
            for x in range(-64,N+64,64):
                d.arc((x-30,y-25,x+74,y+85),25,255,fill=(151,93,47),width=3)
                d.ellipse((x+10,y+12,x+21,y+23),fill=(52,31,26))
                d.polygon([(x+32,y+22),(x+38,y+35),(x+52,y+35),(x+41,y+43),(x+45,y+56),(x+32,y+48),(x+20,y+56),(x+23,y+43),(x+12,y+35),(x+27,y+35)],fill=(139,75,45))
    a=np.array(im,dtype=float);a+=noise()[:,:,None]*1.2
    # Small irregular variations imply trodden fibres without baking route-specific dark stripes.
    return Image.fromarray(np.clip(a,0,255).astype('uint8'))

def make():
    OUT.mkdir(parents=True,exist_ok=True)
    tiles=[paint((179,162,120)),paint((166,77,29)),paint((144,44,24)),surface((30,29,24),.6),surface((173,164,137),.8),carpet('beige'),carpet('confetti'),carpet('red')]
    lino=surface((135,130,111),1.1);d=ImageDraw.Draw(lino)
    for x in (0,256,511):d.line((x,0,x,511),fill=(76,76,64),width=2)
    for y in (0,256,511):d.line((0,y,511,y),fill=(76,76,64),width=2)
    tiles.append(lino)
    lam=surface((189,178,143),.6);d=ImageDraw.Draw(lam)
    for _ in range(2200):
        x,y=rng.integers(0,512,2);c=int(rng.integers(85,160));d.ellipse((int(x),int(y),int(x+1),int(y+1)),fill=(c,c-9,c-20))
    tiles.append(lam)
    wood=surface((109,78,44),1);a=np.array(wood,dtype=float)
    grain=np.sin(np.arange(N)/2.7+rng.normal(0,.25,N))*6+np.sin(np.arange(N)/12)*8;a+=grain[:,None,None]
    wood=Image.fromarray(np.clip(a,0,255).astype('uint8'));d=ImageDraw.Draw(wood)
    for y in (0,128,256,384):d.line((0,y,512,y),fill=(52,37,23),width=3)
    tiles.extend([wood,surface((105,108,100),.85),surface((136,112,77),.9),surface((202,190,146),.5),paint((110,116,102))])
    pal=Image.new('RGB',(512,512),(33,31,25));pd=ImageDraw.Draw(pal)
    lookup={}
    for i,(name,col) in enumerate(PALETTE.items()):
        x=(i%6)*85;y=(i//6)*85
        cell=np.clip(np.array(col)[None,None,:]+rng.normal(0,2,(85,85,1)),0,255).astype('uint8')
        pal.paste(Image.fromarray(cell),(x,y));lookup[name]={'cell':15,'rect':[x+3,y+3,x+82,y+82]}
    tiles.append(pal)
    atlas=Image.new('RGB',(2048,2048));rough=Image.new('RGB',(2048,2048),(214,214,214))
    for i,im in enumerate(tiles):
        # Mirror a short guard band to prevent bleeding across unrelated atlas cells.
        im=im.resize((504,504),Image.Resampling.LANCZOS)
        tile=Image.new('RGB',(512,512));tile.paste(im,(4,4))
        tile.paste(im.crop((0,0,1,504)).resize((4,504)),(0,4));tile.paste(im.crop((503,0,504,504)).resize((4,504)),(508,4))
        tile.paste(tile.crop((0,4,512,5)).resize((512,4)),(0,0));tile.paste(tile.crop((0,507,512,508)).resize((512,4)),(0,508))
        atlas.paste(tile,((i%4)*512,(i//4)*512))
    atlas.save(OUT/'WornParty_Atlas.png',optimize=True)
    rough.save(OUT/'WornParty_Roughness.png',optimize=True)
    for key,i in CELLS.items():lookup[key]={'cell':i,'rect':[6,6,506,506]}
    # Palette rects follow the inset/rescale above.
    for name in PALETTE:
        if name not in CELLS:
            lookup[name]['rect']=[4+x*504/512 for x in lookup[name]['rect']]
    data={'size':2048,'cellSize':512,'mapping':lookup,'colors':PALETTE,'provenance':'Original procedural pixels, authored for Level6; no third-party textures.'}
    (OUT/'atlas-layout.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Authored atlas',OUT)

if __name__=='__main__':make()
