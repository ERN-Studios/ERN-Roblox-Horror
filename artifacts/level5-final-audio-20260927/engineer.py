#!/usr/bin/env python3
"""Reproducible Level 5 audio cleanup. Never edits source files; no AI audio generation.
Dependency versions are in analysis/environment.json. All DSP settings and hashes are recorded.
Technical selection does not establish perceptual quality; no listening review is claimed.
"""
import argparse, hashlib, json, math, platform, subprocess
from pathlib import Path
import numpy as np
import scipy
from scipy import signal, ndimage
import soundfile as sf
ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parent.parent
REPO=PROJECT/'output/level5-window-watcher-repository'
OLD=REPO/'artifacts/level5-audio-qa-20260927'
SR=44100

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def db(v): return float(20*np.log10(max(float(v),1e-12)))
def rms(x): return float(np.sqrt(np.mean(np.square(x)))) if len(x) else 0.
def decode(p):
    b=subprocess.check_output(['ffmpeg','-v','error','-i',str(p),'-f','f64le','-ar',str(SR),'-ac','1','-'])
    return np.frombuffer(b,dtype='<f8').copy()
def frame_rms(x,frame=1024,hop=256):
    z=np.pad(x,(0,max(0,frame-len(x))))
    return np.sqrt(np.mean(np.lib.stride_tricks.sliding_window_view(z,frame)[::hop]**2,axis=1))
def metrics(x):
    fr=frame_rms(x); peak=np.max(np.abs(x)); up=signal.resample_poly(x,4,1)
    # Quiet decile is relative to this file, so comparisons also use the same input mask below.
    return {'duration_s':round(len(x)/SR,6),'rms_dbfs':round(db(rms(x)),3),'peak_dbfs':round(db(peak),3),'true_peak_4x_dbtp':round(db(np.max(np.abs(up))),3),'quiet_decile_rms_dbfs':round(db(np.quantile(fr,.1)),3),'tail_100ms_rms_dbfs':round(db(rms(x[-4410:])),3),'dc':float(np.mean(x)),'clipped_samples':int(np.sum(np.abs(x)>=1)),'digital_zero_samples':int(np.sum(x==0)),'seam_step':float(abs(x[-1]-x[0]))}
def bands(key):
    return {'room_hum':(40,2400),'blackout_roomtone':(40,2000),'watcher_heartbeat':(28,700),'watcher_breath':(90,4800),'watcher_recede':(65,4500),'watcher_glass':(100,7000),'sliding_gate':(55,6500),'sliding_gate_v2':(55,6500),'puzzle_click':(90,8000),'puzzle_reject':(65,5500),'puzzle_unlock':(70,6500),'power_fall':(45,6500),'power_restart':(45,6500),'wooden_door_open':(65,6500),'wooden_door_close':(55,6500),'house_wood_creak':(65,5500),'window_frame_creak':(100,6500),'curtain_movement':(150,6500),'ceiling_relay_tick':(180,8500),'queue_arrival':(100,7000)}[key]
def clean(x,key,loop):
    x=x-np.mean(x); lo,hi=bands(key)
    y=signal.sosfiltfilt(signal.butter(3,[lo,hi],btype='bandpass',fs=SR,output='sos'),x)
    f,t,z=signal.stft(y,fs=SR,nperseg=1024,noverlap=768,boundary='zeros',padded=True)
    power=abs(z)**2
    energy=power.sum(axis=0)
    inner=np.arange(2,max(3,len(energy)-2))
    quiet=inner[np.argsort(energy[inner])[:max(3,int(len(inner)*.15))]]
    profile=np.median(power[:,quiet],axis=1)
    profile=ndimage.gaussian_filter1d(profile,1.2)
    # Only remove weak broadband material; smooth gain across frequency/time to avoid musical noise.
    oversub=.85 if key in ['watcher_breath','curtain_movement'] else 1.1
    floor=.32 if key in ['watcher_breath','curtain_movement'] else .16
    if key in ['room_hum','blackout_roomtone']:
        # Constant hum is intended: protect its low tonal body, soften broadband high end only.
        protect=np.clip((f-600)/1200,0,1)
        gain=np.sqrt(np.clip(1-.8*profile[:,None]/np.maximum(power,1e-22),.30**2,1))
        gain=1-protect[:,None]*(1-gain)
    else:
        gain=np.sqrt(np.clip(1-oversub*profile[:,None]/np.maximum(power,1e-22),floor**2,1))
    gain=ndimage.gaussian_filter(gain,sigma=(1.3,1.0))
    _,y=signal.istft(z*gain,fs=SR,nperseg=1024,noverlap=768)
    y=y[:len(x)]
    expand={}
    if not loop:
        env=np.sqrt(np.maximum(ndimage.uniform_filter1d(y*y,size=882,mode='nearest'),0)+1e-24)
        qp=float(np.quantile(env,.12)); pp=float(np.quantile(env,.85))
        th=min(max(qp*2.5,np.max(env)*.006),pp*.32)
        target=np.clip((env/max(th,1e-12))**1.25,10**(-24/20),1)
        attack=math.exp(-1/(SR*.008)); release=math.exp(-1/(SR*.12))
        g=np.empty(len(y)); prev=1.
        for i,v in enumerate(target):
            coeff=attack if v>prev else release
            prev=coeff*prev+(1-coeff)*v; g[i]=prev
        y*=g; expand={'threshold_dbfs':db(th),'ratio':2.25,'max_reduction_db':24,'attack_ms':8,'release_ms':120}
        # Every one-shot starts and ends on zero. Existing duration is retained.
        a=min(round(.004*SR),len(y)//8); b=min(round(.085*SR),len(y)//6); ztail=min(round(.025*SR),len(y)//15)
        y[:a]*=np.sin(np.linspace(0,np.pi/2,a))**2
        y[-(b+ztail):-ztail]*=np.cos(np.linspace(0,np.pi/2,b))**2
        y[-ztail:]=0.; y[0]=0.
    else:
        # Circular overlap crossfade; shift the result to end at its cyclic boundary.
        n=min(round(.10*SR),len(y)//10)
        w=np.linspace(0,1,n,endpoint=False)
        joint=(1-w)*y[-n:]+w*y[:n]
        y=np.concatenate([joint,y[n:-n]])
        # A 1ms DC-sized seam correction avoids a sample discontinuity without muting the loop.
        difference=y[-1]-y[0]; ns=44
        y[-ns:]-=np.linspace(0,difference,ns)
    return y,{'highpass_hz':lo,'lowpass_hz':hi,'filter':'3rd order Butterworth zero phase','denoise':'STFT smoothed Wiener-style soft attenuation','fft':1024,'hop':256,'noise_profile':'median spectrum of quietest 15 percent interior frames','spectral_min_gain_db':db(floor),'expander':expand,'tail':'25ms exact digital silence after 85ms raised-cosine fade' if not loop else '100ms cyclic linear overlap; boundary correction over 1ms','noise_profile_rms_dbfs':db(np.sqrt(profile.sum()))}
def same_quiet_metrics(before,after):
    n=min(len(before),len(after)); a=before[:n];b=after[:n]
    env=np.sqrt(np.maximum(ndimage.uniform_filter1d(a*a,size=882),0)+1e-24)
    mask=env<=np.quantile(env,.15)
    return {'input_quiet_15pct_rms_dbfs':db(rms(a[mask])),'output_same_regions_rms_dbfs':db(rms(b[mask])),'reduction_db':db(rms(a[mask]))-db(rms(b[mask]))}
def save_audio(x,path,ceiling=-3):
    true=np.max(abs(signal.resample_poly(x,4,1))); g=min(1.,10**(ceiling/20)/max(true,1e-12)); x=x*g
    # No normalization upward: quiet generated noise must not be amplified to meet LUFS.
    sf.write(path,x,SR,subtype='PCM_16')
    return decode(path),db(g)
def main():
    out=ROOT/'processed';out.mkdir(exist_ok=True)
    oldmanifest=json.loads((OLD/'qa/ready-audio-manifest.json').read_text())
    records=[]
    for cue in oldmanifest['cues']:
        src=OLD/cue['file'];x=decode(src);y,settings=clean(x,cue['key'],cue['loop'])
        dst=out/('L5_'+cue['key']+'_clean.wav'); yy,gain=save_audio(y,dst)
        record={'key':cue['key'],'origin':'existing','file':str(dst.relative_to(ROOT)),'source':str(src),'source_sha256':sha(src),'output_sha256':sha(dst),'original_generation_id':cue['generationId'],'original_take':cue['take'],'loop':cue['loop'],'purpose':cue['use'],'settings':settings,'applied_gain_db':gain,'before':metrics(x),'after':metrics(yy)}
        if not cue['loop']: record['same_quiet_regions']=same_quiet_metrics(x,yy)
        records.append(record)
        print(cue['key'],record['before']['quiet_decile_rms_dbfs'],record['after']['quiet_decile_rms_dbfs'],flush=True)
    (ROOT/'analysis/existing-cleanup.json').write_text(json.dumps(records,indent=2)+'\n')
    (ROOT/'analysis/environment.json').write_text(json.dumps({'python':platform.python_version(),'numpy':np.__version__,'scipy':scipy.__version__,'soundfile':sf.__version__,'subjective_listening_performed':False},indent=2)+'\n')
if __name__=='__main__': main()
