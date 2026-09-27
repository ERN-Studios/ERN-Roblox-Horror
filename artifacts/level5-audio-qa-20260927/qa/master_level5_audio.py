"""Technical QA and restrained mastering for original ElevenLabs Level 5 SFX.
Selection is objective only: no subjective listening claim.
"""
import array, concurrent.futures, hashlib, json, math, pathlib, re, subprocess, uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
RAW=json.loads((ROOT/"qa/raw-audio-manifest.json").read_text())
CUES={x["key"]:x for x in json.loads((ROOT/"qa/level5-audio-cue-palette.json").read_text())["cues"]}
def cmd(args):
 p=subprocess.run(args,capture_output=True,check=True)
 return p.stdout,p.stderr.decode(errors="replace")
def db(v): return 20*math.log10(max(v,1e-12))
def metrics(row):
 path=ROOT/row["file"]
 probe=json.loads(cmd(["ffprobe","-v","error","-show_streams","-show_format","-of","json",str(path)])[0])
 b,_=cmd(["ffmpeg","-v","error","-i",str(path),"-f","s16le","-ar","16000","-ac","1","-"])
 x=array.array("h",b); y=[a/32768 for a in x]; n=len(y)
 rms=math.sqrt(sum(a*a for a in y)/max(n,1)); peak=max(abs(a) for a in y)
 block=800
 env=[math.sqrt(sum(a*a for a in y[i:i+block])/len(y[i:i+block])) for i in range(0,n,block)]
 head=math.sqrt(sum(a*a for a in y[:1600])/min(n,1600))
 tail=math.sqrt(sum(a*a for a in y[-1600:])/min(n,1600))
 silence=sum(abs(a)<.001 for a in y)/n
 clipped=sum(abs(a)>=.999 for a in y)/n
 duration=n/16000
 edge=abs(y[0]-y[-1])
 mean=sum(y)/n
 heartbeat_peaks=0
 if row["cue"]=="watcher_heartbeat":
  sm=[sum(env[max(0,i-1):min(len(env),i+2)])/len(env[max(0,i-1):min(len(env),i+2)]) for i in range(len(env))]
  cutoff=max(sm)*.40
  last=-20
  for i in range(1,len(sm)-1):
   if sm[i]>cutoff and sm[i]>=sm[i-1] and sm[i]>sm[i+1] and i-last>=9: heartbeat_peaks+=1;last=i
 measure={"duration":duration,"channels":probe["streams"][0]["channels"],"sampleRate":int(probe["streams"][0]["sample_rate"]),"peakDbfs":db(peak),"rmsDbfs":db(rms),"dcOffset":mean,"clippedFraction":clipped,"silenceFractionBelowMinus60":silence,"edgeJumpDbfs":db(edge),"headRmsDbfs":db(head),"tailRmsDbfs":db(tail),"heartbeatEnvelopePeaks":heartbeat_peaks}
 cue=CUES[row["cue"]]
 if cue["loop"]:
  score=clipped*10000+abs(mean)*100+edge/max(rms,.0001)*2+max(0,silence-.30)
  if row["cue"]=="watcher_heartbeat":score+=abs(heartbeat_peaks-4)
 else:
  score=clipped*10000+abs(mean)*100+tail/max(rms,.0001)*1.5+max(0,silence-.70)*3
 score+=abs(duration-cue["duration_seconds"])
 return {**row,"analysis":measure,"selectionScore":score}
def loudness(path):
 _,err=cmd(["ffmpeg","-hide_banner","-i",str(path),"-af","loudnorm=I=-20:TP=-2.3:LRA=11:print_format=json","-f","null","-"])
 return json.loads(re.findall(r'\{\s*"input_i".*?\}',err,re.S)[-1])
def main():
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: rows=list(pool.map(metrics,RAW))
 (ROOT/"qa/audio-technical-analysis.json").write_text(json.dumps(rows,indent=2)+"\n")
 ready=ROOT/"audio/ready";ready.mkdir(parents=True,exist_ok=True)
 work=ROOT/"audio/working";work.mkdir(exist_ok=True)
 manifest=[]
 targets={"room_hum":-24,"blackout_roomtone":-24,"watcher_heartbeat":-22,"sliding_gate":-20,"watcher_glass":-20,"watcher_breath":-22,"watcher_recede":-22}
 for key,cue in CUES.items():
  choices=sorted((r for r in rows if r["cue"]==key),key=lambda r:r["selectionScore"])
  selected=choices[0];source=ROOT/selected["file"];prepared=work/(key+"_"+uuid.uuid4().hex+".wav");dest=ready/("L5_"+key+".wav");rendered=work/(key+"_master_"+uuid.uuid4().hex+".wav")
  duration=selected["analysis"]["duration"]
  processing=[]
  if cue["loop"]:
   # Cyclic crossfade: body C..D-C followed by tail/head overlap. Result loops
   # continuously from the head segment at C into the body again, D-C duration.
   c=.06
   pcm=array.array('f',cmd(["ffmpeg","-v","error","-i",str(source),"-f","f32le","-ar","44100","-ac","1","-"])[0])
   count=round(c*44100)
   blend=array.array('f',(pcm[-count+i]*(1-i/(count-1))+pcm[i]*(i/(count-1)) for i in range(count)))
   cyclic=pcm[count:-count]+blend
   subprocess.run(["ffmpeg","-v","error","-y","-f","f32le","-ar","44100","-ac","1","-i","pipe:0","-c:a","pcm_f32le",str(prepared)],input=cyclic.tobytes(),capture_output=True,check=True)
   processing.append("60ms cyclic tail/head linear crossfade, duration reduced by60ms; no added audio")
  else:
   cmd(["ffmpeg","-v","error","-y","-i",str(source),"-af",f"afade=t=in:d=0.005,afade=t=out:st={max(0,duration-.035)}:d=0.035","-ar","44100","-ac","1","-c:a","pcm_f32le",str(prepared)])
   processing.append("5ms input and35ms output edge fades")
  target=targets.get(key,-18)
  meas=loudness(prepared)
  if not all(math.isfinite(float(meas[k])) for k in ["input_i","input_tp","input_lra","input_thresh","target_offset"]):raise ValueError(f"Silent/invalid cue:{key}")
  # Constant gain preserves generated transient/dynamic shape and cyclic seams.
  gain=min(target-float(meas["input_i"]),-2.3-float(meas["input_tp"]))
  cmd(["ffmpeg","-v","error","-y","-i",str(prepared),"-af",f"volume={gain:.6f}dB","-ar","44100","-ac","1","-c:a","pcm_s16le",str(rendered)])
  rendered.replace(dest)
  final=loudness(dest);peak=float(final["input_tp"]);integrated=float(final["input_i"])
  if peak>-2.0:raise ValueError(f"Peak failed:{key}:{peak}")
  data=dest.read_bytes()
  result={"key":key,"file":str(dest.relative_to(ROOT)),"sourceFile":selected["file"],"sourceSha256":selected["sha256"],"generationId":selected["generationId"],"take":selected["take"],"sha256":hashlib.sha256(data).hexdigest(),"bytes":len(data),"loop":cue["loop"],"duration":round(duration-(.06 if cue["loop"] else 0),5),"sampleRate":44100,"channels":1,"format":"16bit PCM WAV","targetLufs":target,"measuredLufs":integrated,"truePeakDbtp":peak,"gainDb":round(gain,6),"processing":processing+["constant gain limited by -2.3dBTP ceiling; no dynamic compression"],"selection":{"method":"Objective technical metrics; not a subjective listening review","score":selected["selectionScore"],"alternatives":[{"take":r["take"],"score":r["selectionScore"]} for r in choices]},"use":cue["use"]}
  manifest.append(result)
  print(key, "take",selected["take"],f"{integrated}LUFS /{peak}dBTP",flush=True)
 (ROOT/"qa/ready-audio-manifest.json").write_text(json.dumps({"status":"technically_mastered_ready_for_import_subjective_listening_unverified","flowId":"jjheL5GNVJdYYNrfs1E8","model":"eleven_text_to_sound_v2","generationBatches":1,"generatedTakes":48,"selectedCues":12,"subjectiveListeningPerformed":False,"cues":manifest},indent=2)+"\n")
if __name__=="__main__":main()
