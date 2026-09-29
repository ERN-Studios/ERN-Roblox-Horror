import csv,json,shutil
from pathlib import Path
import numpy as np
import soundfile as sf
import engineer as e
R=e.ROOT
base=Path('/Users/zeanjuul4/Downloads/Level 5 Final Sounds - Cleaned')
pointer=R/'analysis/delivery-path.txt'
if pointer.exists(): dest=Path(pointer.read_text().strip())
else:
 dest=base;i=2
 while dest.exists():dest=base.with_name(base.name+f' ({i})');i+=1
 dest.mkdir(parents=True);pointer.write_text(str(dest)+'\n')
existing=json.loads((R/'analysis/existing-cleanup.json').read_text());new=json.loads((R/'analysis/new-selected.json').read_text())
rows=[]
for r in existing:
 key=r['key'];folder=''
 if key in ['power_fall','power_restart','blackout_roomtone']:folder='DO_NOT_UPLOAD_NOW/Outage_Disabled'
 elif key=='sliding_gate':folder='DO_NOT_UPLOAD_NOW/Legacy_Gate_Alternative'
 filename=f'L5_{key}.wav' if key!='sliding_gate' else 'L5_sliding_gate_legacy_4s.wav'
 target=dest/folder/filename;target.parent.mkdir(parents=True,exist_ok=True)
 shutil.copy2(R/r['file'],target)
 rows.append({'cue':key,'file':str(target.relative_to(dest)),'sha256':e.sha(target),'origin':'cleaned existing ElevenLabs cue','generation_id':r['original_generation_id'],'take':r['original_take'],'purpose':r['purpose'],'loop':r['loop'],'upload_now':not bool(folder),'roblox_asset_id':'','integration':'Prepared draft hook; not installed. No Roblox asset ID.' if not folder else 'Disabled / alternative; do not upload now.','processing_record':r})
for r in new:
 key='sliding_gate' if r['key']=='sliding_gate_v2' else r['key']
 target=dest/f'L5_{key}.wav';shutil.copy2(R/r['output_file'],target)
 rows.append({'cue':key,'file':target.name,'sha256':e.sha(target),'origin':'new ElevenLabs cue, cleaned','generation_id':r['generation_id'],'take':r['take'],'purpose':r['purpose'],'loop':False,'upload_now':True,'roblox_asset_id':'','integration':'Prepared gate draft hook; not installed. No Roblox asset ID.' if key=='sliding_gate' else 'Asset only; event playback not wired. No Roblox asset ID.','processing_record':r})
checks=[]
for r in rows:
 p=dest/r['file'];x,sr=sf.read(p,dtype='float64');info=sf.info(p)
 assert e.sha(p)==r['sha256']
 assert sr==44100 and info.channels==1 and info.subtype=='PCM_16'
 assert np.isfinite(x).all() and np.max(np.abs(x))<1
 assert len(x)>1000
 if not r['loop']:
  assert x[0]==0,r['file']
  assert np.all(x[-round(.025*sr):]==0),r['file']
 else:assert abs(x[-1]-x[0])<=1/32768
 metrics=e.metrics(x)
 assert metrics['true_peak_4x_dbtp']<=-2.99
 checks.append({'file':r['file'],'sha256':r['sha256'],'format':info.subtype,'sample_rate':sr,'channels':info.channels,'metrics':metrics})
manifest={'date':'2026-09-27','status':'manual-upload-ready; no Roblox assets uploaded or installed','top_level_upload_count':16,'optional_disabled_count':4,'total_wavs':20,'new_generation_flow':'https://elevenlabs.io/app/flows/6B2UMQj1yZKRKiBLhKYd','new_generation_count':32,'new_selected_count':8,'original_cleaned_count':12,'subjective_listening_performed':False,'sound_engineering':'Measured spectral attenuation, cue-specific band limits, smooth downward expansion for one-shots, 25ms exact silent tails, 100ms cyclic loop joins. Original cue gain is not raised. New cue gain capped at +6dB (+12dB for quiet queue bell).','cues':rows}
(dest/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
(dest/'VALIDATION.json').write_text(json.dumps({'all_checks_passed':True,'checks':checks},indent=2)+'\n')
with (dest/'UPLOAD_IDS.csv').open('w',newline='') as f:
 writer=csv.DictWriter(f,fieldnames=['cue','file','roblox_asset_id','loop','purpose','integration']);writer.writeheader()
 for r in rows:
  if r['upload_now']:writer.writerow({k:r[k] for k in writer.fieldnames})
readme='''LEVEL 5 — FINAL CLEANED SOUNDS

Upload the 16 WAV files directly inside this folder to Roblox.
Keep each filename so the asset IDs can be matched to the game.
Use the experience owner's account/group and grant the experience access.
Record the resulting IDs in UPLOAD_IDS.csv or send the IDs to Codex.

Every WAV is mono, 44.1 kHz, 16-bit PCM. All files passed format, hash,
clipping, peak and boundary checks. No new audio has been uploaded to
Roblox or installed in Studio. These are final prepared assets.

WHAT IS INCLUDED
- Room hum, puzzle click/reject/unlock: cleaned existing cues.
- Window Watcher glass/breath/heartbeat/recede: cleaned existing cues.
- Sliding gate: new 2.2-second cue; motion window 1.6 seconds plus tail.
- Wooden door opening and closing: two new cues.
- House wood creak, window-frame creak, curtain movement: new cues.
- Ceiling relay tick and subdued queue arrival bell: new cues.

Only room_hum and watcher_heartbeat should loop. All other top-level
files are one-shots. Use low in-game levels for ambience and tension cues.

INTEGRATION STATUS
The room/puzzle/gate/Watcher hooks exist in a prepared code draft that
has not been installed. The new wooden-door, house/window creak,
curtain, relay and queue cues are assets only; playback events still
need wiring. Every Roblox asset ID remains blank until manual upload.

DO_NOT_UPLOAD_NOW contains all three cleaned outage cues (outage is
being disabled) and the cleaned older 4-second gate alternative.
The new top-level L5_sliding_gate.wav is the intended gate version.

CLEANUP
Stationary broadband noise was reduced using measured quiet regions,
then cue-specific filters and gentle expansion. One-shot tails end in
25ms of exact digital silence. Loops use a 100ms cyclic join; this makes
them 0.1 seconds shorter than the previous WAVs. Intentional hum,
breath texture and heartbeat remain. Existing quiet files were not
boosted again to chase loudness. No destructive limiter was needed.

Technical checks and measured noise reduction are complete. A human
headphone/in-game listening review has not been performed; metrics do
not prove that every generated artifact is perceptually gone.

MANIFEST.json records source hashes, generation IDs, takes and settings.
VALIDATION.json records every delivered file's technical checks.
Reproducible scripts, receipts and all 32 new original takes are saved at:
'''+str(R)+'\n'
(dest/'README.txt').write_text(readme)
(R/'analysis/delivery-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(R/'analysis/delivery-validation.json').write_text(json.dumps({'all_checks_passed':True,'checks':checks},indent=2)+'\n')
assert len(list(dest.glob('*.wav')))==16
assert len(list(dest.rglob('*.wav')))==20
print(json.dumps({'folder':str(dest),'active_wavs':16,'disabled_alternatives':4,'all_validation_passed':True,'bytes':sum(p.stat().st_size for p in dest.rglob('*') if p.is_file())},indent=2))
