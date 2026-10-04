import json, subprocess as sp, hashlib, sys
from pathlib import Path
import numpy as np
from scipy import signal
ROOT=Path(__file__).resolve().parent.parent
WORK=ROOT/'audio-engineering'; MEAS=WORK/'measurements'; SR=48000

def run(args):
 p=sp.run(['ffmpeg','-hide_banner','-nostdin','-y']+list(map(str,args)),capture_output=True)
 if p.returncode: raise RuntimeError(p.stderr.decode())
 return p

def decode(p):
 return np.frombuffer(run(['-v','error','-i',p,'-ar',SR,'-ac',2,'-f','f32le','-']).stdout,dtype='<f4').reshape(-1,2).astype(float)

def db(v): return float(10*np.log10(max(float(v),1e-20)))
def band(x):
 f,p=signal.welch(x,SR,nperseg=8192,axis=0)
 return db(np.mean(np.sum(p[(f>=6000)&(f<=16000)],axis=0)*(f[1]-f[0])))
def loud(p):
 s=run(['-i',p,'-af','loudnorm=I=-24:TP=-2:LRA=11:print_format=json','-f','null','-']).stderr.decode();return json.JSONDecoder().raw_decode(s[s.rfind('{'):])[0]
def analyze(p):
 x=decode(p); energy=np.mean(x*x,axis=1); cs=np.r_[0,np.cumsum(energy)]; idx=int(np.argmin((cs[SR:]-cs[:-SR])[::480]))*480
 q=x[idx:idx+SR]; f,ps=signal.welch(q,SR,nperseg=8192,axis=0); ps=ps.mean(axis=1)
 np.savetxt(MEAS/(p.stem+'_quietest_spectrum.csv'),np.c_[f,10*np.log10(np.maximum(ps,1e-20))],delimiter=',',header='Hz,PSD_dBFS_per_Hz',comments='')
 log=run(['-i',p,'-af','astats=metadata=0:reset=0','-f','null','-']).stderr.decode(); (MEAS/(p.stem+'_astats.txt')).write_text(log)
 # Narrow high-frequency peaks must exceed their local median by 15 dB.
 from scipy.ndimage import median_filter
 delta=10*np.log10(np.maximum(ps,1e-20))-median_filter(10*np.log10(np.maximum(ps,1e-20)),size=41)
 peaks,_=signal.find_peaks(delta,height=15,distance=10); candidates=[round(float(f[k]),1) for k in peaks if 2000<f[k]<16000 and 10*np.log10(ps[k])>-85]
 r={'decoded_seconds':len(x)/SR,'quietest_second_start':idx/SR,'quietest_rms_dbfs':db(np.mean(q*q)),'quietest_high_band_rms_dbfs':band(q),'high_band_rms_dbfs':band(x),'tonal_whine_candidates_hz':candidates,'loudness':loud(p)}
 return r

def process(src,dst,cutoff,target,loop):
 before=analyze(src); dur=before['decoded_seconds']; nf=max(-65,min(-28,before['quietest_high_band_rms_dbfs']))
 chain=f'highpass=f=30,afftdn=nr=22:nf={nf:.3f}:tn=1:gs=8,lowpass=f={cutoff}:p=2'
 wav=WORK/(dst.stem+'_processed.wav')
 wav.unlink(missing_ok=True)
 if loop:
  # Length compensation: enlarge each copy by the overlap, then cut one complete periodic cycle.
  # Cutting T seconds from an unextended doubled crossfade would leave a mismatched loop boundary.
  stretch=dur/(dur+1.5)
  extended=WORK/(dst.stem+'_extended.wav')
  extended.unlink(missing_ok=True)
  run(['-i',src,'-af',f'aresample={SR},{chain},atempo={stretch:.12f},apad,atrim=end_sample={round((dur+1.5)*SR)}','-ar',SR,'-c:a','pcm_f32le',extended])
  graph=f'[0:a][1:a]acrossfade=d=1.5:c1=tri:c2=tri,atrim=start_sample={round(1.5*SR)}:end_sample={round((dur+1.5)*SR)},asetpts=PTS-STARTPTS[o]'
  run(['-i',extended,'-i',extended,'-filter_complex',graph,'-map','[o]','-t',str(dur),'-ar',SR,'-c:a','pcm_f32le',wav])
  extended.unlink()

 else:
  chain+=f',afade=t=in:d=0.012,afade=t=out:st={max(0,dur-0.65):.8f}:d=0.65'
  if dst.name=='l5_amb_heartbeat.mp3':
   # The generated take contains two main thumps. Arrange its first thump into exactly four.
   graph=f'[0:a]{chain},atrim=duration=0.95,afade=t=out:st=0.65:d=0.3,asplit=4[a][b][c][d];[b]adelay=1000:all=1[b1];[c]adelay=2000:all=1[c1];[d]adelay=3000:all=1[d1];[a][b1][c1][d1]amix=inputs=4:normalize=0,aecho=0.8:0.9:191|373|617|911:0.20|0.13|0.09|0.04,apad,asetpts=N/SR/TB,atrim=end_sample=220500,afade=t=out:st=4.35:d=0.65[o]'
   run(['-i',src,'-filter_complex',graph,'-map','[o]','-t',str(dur),'-ar',SR,'-c:a','pcm_f32le',wav])
   chain=graph
  else:
   run(['-i',src,'-af',chain,'-ar',SR,'-c:a','pcm_f32le',wav])
 m=loud(wav);gain=target-float(m['input_i'])
 encoded=WORK/(dst.stem+'_encoded.mp3')
 run(['-i',wav,'-af',f'volume={gain:.4f}dB','-c:a','libmp3lame','-b:a','192k','-ar',SR,encoded])
 encoded.replace(dst)
 after=analyze(dst); x=decode(dst)
 record={'name':dst.name,'source':str(src.relative_to(ROOT)),'sha256':hashlib.sha256(dst.read_bytes()).hexdigest(),'processing':{'filter':chain,'gain_db':gain,'target_lufs':target,'loop_crossfade_seconds':1.5 if loop else None,'loop_duration_compensation_atempo':stretch if loop else None},'before':before,'after':after,'high_band_reduction_db':before['high_band_rms_dbfs']-after['high_band_rms_dbfs'],'boundary_step_dbfs':db(np.mean((x[0]-x[-1])**2)) if loop else None,'decode_ok':True,'listening_review':'Not performed; measurements do not prove subjective absence of hiss or semantic prompt accuracy.'}
 (MEAS/(dst.stem+'.json')).write_text(json.dumps(record,indent=2)+'\n'); wav.unlink(); print(json.dumps(record),flush=True);return record

if __name__=='__main__':
 if sys.argv[1]=='beds':
  for n,lp in [('ambience',5500),('depth_wind',2800)]:process(ROOT/f'l5_{n}.mp3',ROOT/f'l5_{n}_clean.mp3',lp,-24,True)
 elif sys.argv[1]=='shots':
  for j in json.loads((WORK/'generation_records.json').read_text()): process(WORK/'raw'/j['name'],ROOT/j['name'],3500,-22,False)
