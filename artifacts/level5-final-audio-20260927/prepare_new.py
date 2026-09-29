import json
from pathlib import Path
import numpy as np
from scipy import signal,ndimage
import engineer as e
R=e.ROOT
records=json.loads((R/'analysis/new-raw-manifest.json').read_text());nodes={r['key']:r for r in json.loads((R/'receipts/nodes.json').read_text())}
allresults=[]
for r in records:
 src=R/r['file'];x=e.decode(src);key=r['key']
 y,settings=e.clean(x,key,False)
 # Detect leading inactivity at -36dB relative to the strongest 20ms energy, retaining 12ms pre-roll.
 env=np.sqrt(np.maximum(ndimage.uniform_filter1d(y*y,size=882),0)+1e-24)
 indices=np.flatnonzero(env>env.max()*.016)
 start=max(0,int(indices[0]) - round(.012*e.SR)) if len(indices) else 0
 y=np.concatenate([y[start:],np.zeros(start)])
 nfade=round(.004*e.SR);y[:nfade]*=np.sin(np.linspace(0,np.pi/2,nfade))**2;y[0]=0.
 if key=='sliding_gate_v2':
  # Enforce the 1.6-second motion window with a smooth half-second settling tail.
  t=np.arange(len(y))/e.SR
  tail=np.ones(len(y));mask=t>1.6;tail[mask]=np.cos(np.minimum((t[mask]-1.6)/.575,1)*np.pi/2)**2
  y*=tail
  settings['motion_envelope']='unchanged through 1.6s, raised-cosine settling decay through 2.175s, silence to 2.2s'
 peak=e.db(np.max(np.abs(signal.resample_poly(y,4,1))))
 target={'sliding_gate_v2':-5,'wooden_door_open':-7,'wooden_door_close':-7,'house_wood_creak':-10,'window_frame_creak':-10,'curtain_movement':-12,'ceiling_relay_tick':-10,'queue_arrival':-12}[key]
 gain=min(12. if key=='queue_arrival' else 6.,target-peak);y*=10**(gain/20)
 dst=R/'processed'/f"L5_{key}__take{r['take']:02d}_clean.wav"
 yy,ceiling=e.save_audio(y,dst)
 frame=e.frame_rms(yy)
 # Technical selection: reject near-silent/malformed output, favor contrast and restrained high-band residual.
 active=np.quantile(frame,.8);quiet=np.quantile(frame,.12)
 contrast=e.db(active)-e.db(quiet)
 freq,p=signal.welch(yy,e.SR,nperseg=2048)
 high_ratio=float(p[freq>6500].sum()/max(p.sum(),1e-20))
 duration=len(yy)/e.SR
 score=-contrast*.04+high_ratio*5
 if key=='queue_arrival': score+=max(0,-34-e.db(e.rms(yy)))*.5
 timing={}
 if key=='sliding_gate_v2':
  bins=[e.rms(yy[round(a*e.SR):round(b*e.SR)]) for a,b in [(0,.4),(.4,.8),(.8,1.2),(1.2,1.6),(1.6,2.2)]]
  coverage=min(bins[:4])/max(max(bins[:4]),1e-10)
  score-=coverage*4
  timing={'segment_rms_dbfs':[round(e.db(v),2) for v in bins],'motion_coverage_min_to_max':coverage}
 elif key=='ceiling_relay_tick':
  # Prefer compact tick over a series of repeated clicks.
  energy=yy**2;cum=np.cumsum(energy)/max(energy.sum(),1e-20)
  spread=(np.searchsorted(cum,.95)-np.searchsorted(cum,.05))/e.SR
  score+=spread*3;timing={'energy_5_to_95_percent_seconds':spread}
 if e.rms(yy)<10**(-55/20):score+=100
 rr={**r,'output_file':str(dst.relative_to(R)),'output_sha256':e.sha(dst),'settings':settings,'leading_silence_removed_s':start/e.SR,'constant_gain_db':gain+ceiling,'before':e.metrics(x),'after':e.metrics(yy),'selection_score':score,'quiet_to_active_contrast_db':contrast,'timing':timing,'purpose':nodes[key]['use']}
 allresults.append(rr)
 print(key,r['take'],round(score,3),rr['after']['peak_dbfs'],timing,flush=True)
selected=[]
for key in nodes:
 options=sorted([r for r in allresults if r['key']==key],key=lambda r:r['selection_score'])
 selected.append({**options[0],'selection_method':'Objective technical contrast, energy and timing metrics. No perceptual listening review claimed.','alternative_scores':[{'take':r['take'],'score':r['selection_score']} for r in options]})
(R/'analysis/new-take-analysis.json').write_text(json.dumps(allresults,indent=2)+'\n')
(R/'analysis/new-selected.json').write_text(json.dumps(selected,indent=2)+'\n')
print('SELECTED',[(r['key'],r['take']) for r in selected])
