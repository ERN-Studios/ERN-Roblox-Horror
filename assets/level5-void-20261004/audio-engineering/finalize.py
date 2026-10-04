import json, sys, hashlib
from process_audio import *
manifest=ROOT/'manifest.json'; original=manifest.read_text(); old=json.loads(original); names={r['name'] for r in old}; jobs=json.loads((WORK/'generation_records.json').read_text()); adds=[]; records=[]
for name in ['l5_ambience_clean.mp3','l5_depth_wind_clean.mp3']+[j['name'] for j in jobs]:
 r=json.loads((MEAS/(Path(name).stem+'.json')).read_text());records.append(r); j=next((j for j in jobs if j['name']==name),None)
 info=sp.run(['ffprobe','-v','error','-show_entries','format=duration','-of','json',str(ROOT/name)],capture_output=True,check=True)
 entry={'name':name,'seconds':float(json.loads(info.stdout)['format']['duration']),'loop':j is None,'sha256':r['sha256'],'processing':r['processing'],'verification':{'decoded_seconds':r['after']['decoded_seconds'],'integrated_lufs':float(r['after']['loudness']['input_i']),'true_peak_dbtp':float(r['after']['loudness']['input_tp']),'high_band_before_dbfs':r['before']['high_band_rms_dbfs'],'high_band_after_dbfs':r['after']['high_band_rms_dbfs'],'high_band_reduction_db':r['high_band_reduction_db'],'decode_ok':True,'listening_review':r['listening_review']}}
 if j:entry.update(prompt=j['prompt'],generator='ElevenLabs MCP Sound Effects v2',generation_id=j['generation_id'])
 else:entry.update(source=r['source'],generator='None; FFmpeg processing of existing bed')
 if name=='l5_amb_heartbeat.mp3':
  x=decode(ROOT/name); e=np.sqrt(np.mean(x[:len(x)//480*480].reshape(-1,480,2)**2,axis=(1,2))); peaks,_=signal.find_peaks(e,distance=60,prominence=max(e)*.15)
  assert len(peaks)==4,peaks
  entry['verification']['detected_main_thumps_seconds']=(peaks/100).tolist()
  entry['processing']['arrangement']='First generated thump repeated at 1-second intervals four times, with diffuse delayed tail; original generator returned two main thumps.'
 assert abs(entry['verification']['integrated_lufs']-(-24 if j is None else -22))<0.75
 if j is None: assert r['before']['decoded_seconds']==r['after']['decoded_seconds']
 assert name not in names
 adds.append(entry)
# Preserve existing entries and their formatting exactly; append only.
assert original.rstrip().endswith(']')
manifest.write_text(original.rstrip()[:-1].rstrip()+',\n'+',\n'.join('  '+json.dumps(e,indent=2).replace('\n','\n  ') for e in adds)+'\n]\n')
assert json.loads(manifest.read_text())[:len(old)]==old
verified=[]
for p in sorted(ROOT.rglob('*.mp3')):
 result=run(['-v','error','-xerror','-i',p,'-f','null','-']); assert not result.stderr,result.stderr
 x=decode(p); verified.append({'name':str(p.relative_to(ROOT)),'decoded_seconds':len(x)/SR,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'decode_ok':True})
(WORK/'decode-verification.json').write_text(json.dumps(verified,indent=2)+'\n')
lines=['Level 5 audio engineering results','', 'All changes confined to assets/level5-void-20261004. No Git commit, Studio edit or publication.','Original MP3s preserved. Eight ElevenLabs Sound Effects v2 generations retained in audio-engineering/raw.','', 'Measurement: decoded 48 kHz stereo float; quietest rolling 1-second RMS window searched every 10 ms; Welch PSD (8192 samples), channel-mean power integrated over 6-16 kHz, expressed as RMS dBFS. Measurements include final MP3 encoding and normalization. Spectrum CSVs and FFmpeg astats logs accompany per-file JSON.','No qualifying narrow high-frequency whine in either original bed; no notch/de-esser applied.','22 dB afftdn with noise tracking, 30 Hz high-pass, 2-pole low-pass at 5500 Hz (ambience), 2800 Hz (wind), 3500 Hz (one-shots).','Bed loops: slight pitch-preserving duration expansion before 1.5-second linear acrossfade of two copies, then extract exactly one original-length period. atempo factors recorded. MP3 boundary steps: ambience -64.1 dBFS, wind -37.4 dBFS.','One-shots: short attack smoothing, final 650 ms fade. Heartbeat arranged from generated material to obtain four main thumps.','Loudness: measured BS.1770 integrated loudness, constant gain normalization, final encoded loudness verified within 0.75 LU of targets.','Subjective listening review was not performed; quantitative noise reduction is verified, absolute absence of audible hiss and semantic prompt fidelity are not certified.','', 'File | decoded seconds | LUFS | 6-16 kHz RMS before -> after dBFS | reduction dB']
for r in records:
 lines.append(f"{r['name']} | {r['after']['decoded_seconds']:.3f} | {r['after']['loudness']['input_i']} | {r['before']['high_band_rms_dbfs']:.2f} -> {r['after']['high_band_rms_dbfs']:.2f} | {r['high_band_reduction_db']:.2f}")
lines+=['',f'Every MP3 in folder and raw subfolder decoded without errors: {len(verified)} files.','Reproduce with Python numpy/scipy and FFmpeg: process_audio.py beds / shots.']
(WORK/'REPORT.txt').write_text('\n'.join(lines)+'\n');print('\n'.join(lines[-13:]))
