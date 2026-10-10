"""Read the Level 5 JSON and draw owner-review plans (Python + Pillow, offline).
Each 1600-pixel plan includes actual footprints, alternative geometry, invisible
side guards, dotted route, gap labels, checkpoint rings and a route-distance
side elevation. Stacked stairs use height tint; gap numbers share a label when
several turns have the same plan location. All text is at least 16 pixels.
"""
import json, math, sys
from pathlib import Path
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    # This checkout's system Python lacks Pillow; the installed Intel Python has it.
    fallback=Path('/usr/local/bin/python3')
    if fallback.exists() and Path(sys.executable).resolve()!=fallback.resolve():
        import os
        os.execv(str(fallback),[str(fallback),str(Path(__file__).resolve()),*sys.argv[1:]])
    raise

ROOT=Path(__file__).resolve().parents[2]
DATA=ROOT/'artifacts/level5-void-20261003/build/level5.json'
OUT=ROOT/'artifacts/level5-void-20261003/plan'
BG=(12,15,22); FG=(239,239,231); ALT=(110,248,222); GUARD=(245,113,84)
FONT=Path('/System/Library/Fonts/Supplemental/Arial.ttf')
def font(size): return ImageFont.truetype(str(FONT),size)
F16,F20,F28=font(16),font(20),font(28)

def corners(f):
    c,s=math.cos(math.radians(f['yaw'])),math.sin(math.radians(f['yaw']))
    return [(f['x']+c*a-s*b,f['z']+s*a+c*b) for a,b in
            ((-f['l']/2,-f['w']/2),(f['l']/2,-f['w']/2),(f['l']/2,f['w']/2),(-f['l']/2,f['w']/2))]

def dotted(draw,a,b,colour,width=2,period=9):
    length=math.dist(a,b)
    if length<.1: return
    for distance in range(0,math.ceil(length),period):
        t,u=distance/length,min(1,(distance+3)/length)
        draw.line((a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,
                   a[0]+(b[0]-a[0])*u,a[1]+(b[1]-a[1])*u),fill=colour,width=width)


def main():
    data=json.loads(DATA.read_text()); OUT.mkdir(parents=True,exist_ok=True)
    for nn,sec in enumerate(data['sections'],1):
        feet=[f for f in data['footprints'] if f['sec']==sec]
        ext=data['extent'][sec]; x0,x1,z0,z1,y0,y1=ext
        points=[r for r in data['route'] if r['sec']==sec and not r.get('gate') and x0-.01<=r['x']<=x1+.01]
        alts=[a for a in data['alts'] if a['sec']==sec]
        gaps=[g for g in data['gaps'] if g['sec']==sec]
        cps=[cp for cp in data['checkpoints'] if cp['sec']==sec]
        scale=min(1230/(x1-x0+12),850/(z1-z0+12))
        ph=max(350,round((z1-z0+12)*scale)); eh=330
        im=Image.new('RGB',(1600,ph+eh+200),BG); d=ImageDraw.Draw(im)
        m=data['metrics'][sec]; col=tuple(data['colours'][sec])
        d.text((40,20),f'{nn:02d}  {sec.upper()}   |   route {m["length"]:.1f} studs, x span {m["span"]:.1f}',font=F28,fill=FG)
        d.text((40,62),f'{len(gaps)} gaps   |   narrowest {m["width"]:.1f}   |   {len(cps)} checkpoints   |   {m["guards"]} guards',font=F20,fill=FG)
        def xy(x,z): return (40+(x-x0+6)*scale,105+(z-z0+6)*scale)
        for f in sorted(feet,key=lambda f:f['top']):
            tint=.5+.5*(f['top']-y0)/max(1,y1-y0)
            colour=tuple(round(v*.55) for v in ALT) if f.get('alt') else tuple(round(v*tint) for v in col)
            poly=[xy(x,z) for x,z in corners(f)]
            if f.get('sh')=='c':
                a,b=xy(f['x']-f['l']/2,f['z']-f['w']/2),xy(f['x']+f['l']/2,f['z']+f['w']/2)
                d.ellipse((*a,*b),fill=colour,outline=FG,width=2)
            else:
                d.polygon(poly,fill=colour,outline=tuple(min(255,v+28) for v in colour))
        if sec in ('crimson','ivory'):
            pillar=next(p for p in data['parts'] if p['n']=='Pillar' and p['c']==sec)      # square since v4.1
            x,z=pillar['p'][0],pillar['p'][2]; radius=pillar['s'][0]/2
            a,b=xy(x-radius,z-radius),xy(x+radius,z+radius)
            d.rectangle((*a,*b),fill=col if sec=='ivory' else tuple(round(v*.22) for v in col),outline=col,width=2)
        for row in data['parts']:
            if row['n']!='Guard' or row.get('sec')!=sec: continue
            h=math.radians(row['yaw']); half=row['s'][0]/2; x,y,z=row['p']
            d.line((*xy(x-math.cos(h)*half,z-math.sin(h)*half),*xy(x+math.cos(h)*half,z+math.sin(h)*half)),fill=GUARD,width=2)
        for a,b in zip(points,points[1:]): dotted(d,xy(a['x'],a['z']),xy(b['x'],b['z']),FG)
        for alt in alts:
            for a,b in zip(alt['points'],alt['points'][1:]): dotted(d,xy(a['x'],a['z']),xy(b['x'],b['z']),ALT,3,11)
        groups={}
        for cp in cps:
            key=(round(cp['x'],1),round(cp['z'],1))
            if key in groups: continue
            groups[key]=cp
            x,y=xy(cp['x'],cp['z']); rr=max(6,3*scale)
            d.ellipse((x-rr,y-rr,x+rr,y+rr),outline=(255,225,91),width=3)
            h=math.radians(cp['yaw']); d.line((x,y,x+math.cos(h)*rr,y+math.sin(h)*rr),fill=(255,225,91),width=2)
        d.text((1300,105),'GAPS: length / walking',font=F20,fill=FG)
        locations={}
        for i,g in enumerate(gaps,1):
            x=(g['start'][0]+g['end'][0])/2; z=(g['start'][2]+g['end'][2])/2
            key=(round(x,1),round(z,1)); locations.setdefault(key,[]).append(i)
            d.text((1300,136+(i-1)*31),f'{i:02d}  {g["gap"]:.1f} / {g["share"]:.1%}'+(' ALT' if g.get('alt') else ''),font=F16,fill=ALT if g.get('alt') else FG)
        for (x,z),ids in locations.items():
            px,py=xy(x,z); label=','.join(map(str,ids)); box=d.textbbox((0,0),label,font=F16)
            tw=box[2]-box[0]
            d.rounded_rectangle((px-tw/2-5,py-10,px+tw/2+5,py+12),4,fill=BG,outline=FG)
            d.text((px-tw/2,py-9),label,font=F16,fill=FG)
        ly=ph+117
        d.line((40,ly-12,1560,ly-12),fill=(65,70,82),width=1)
        d.text((40,ly),'SIDE ELEVATION — main route distance / surface height',font=F20,fill=FG)
        distances=[0.]
        for a,b in zip(points,points[1:]): distances.append(distances[-1]+math.hypot(b['x']-a['x'],b['z']-a['z']))
        def elev(distance,y): return (70+distance/max(1,distances[-1])*1470,ly+eh-35-(y-y0+2)/max(8,y1-y0+4)*(eh-90))
        for i,(a,b) in enumerate(zip(points,points[1:])):
            pa,pb=elev(distances[i],a['y']),elev(distances[i+1],b['y'])
            if b['jump'] and not b.get('hop'): dotted(d,pa,pb,FG,3,8)
            else: d.line((*pa,*pb),fill=col,width=4)
        for cp in cps:
            index=min(range(len(points)),key=lambda i:math.dist((points[i]['x'],points[i]['y'],points[i]['z']),(cp['x'],cp['y'],cp['z'])))
            x,y=elev(distances[index],cp['y']); d.ellipse((x-5,y-5,x+5,y+5),outline=(255,225,91),width=2)
        for i in range(6):
            distance=distances[-1]*i/5; x,y=elev(distance,y0-2)
            d.text((x-15,ly+eh-28),f'{distance:.0f}',font=F16,fill=FG)
        d.text((40,ly+34),f'y {y0:.1f} to {y1:.1f}',font=F16,fill=FG)
        d.text((40,ly+eh+12),'Dotted white: route   |   Mint tint: alternative   |   Orange lines: invisible guards   |   Yellow rings: checkpoints',font=F16,fill=FG)
        if sec in ('crimson','ivory'):
            d.text((40,ly+eh+42),'Stacked flights overlap in plan; darker = lower. Gap labels list repeated locations across turns.',font=F16,fill=FG)
        im.save(OUT/f'{nn:02d}_{sec}.png')
        print(OUT/f'{nn:02d}_{sec}.png')

if __name__=='__main__': main()
