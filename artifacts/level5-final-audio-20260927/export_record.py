"""Prepare a small credential-free task record for parent-agent repository sync."""
import json,shutil
from pathlib import Path
R=Path(__file__).resolve().parent
OUT=R/'export_for_repo';OUT.mkdir(exist_ok=True)
for sub in ['raw','analysis']:
 target=OUT/sub;target.mkdir(exist_ok=True)
 for p in (R/sub).iterdir():
  if p.is_file():shutil.copy2(p,target/p.name)
for name in ['engineer.py','prepare_new.py','package.py','download_new.py','export_record.py']:
 shutil.copy2(R/name,OUT/name)
def redact(x):
 if isinstance(x,dict):return {k:redact(v) for k,v in x.items() if k not in ['url','master_url','content_url','thumbnail_url','poster_url']}
 if isinstance(x,list):return [redact(v) for v in x]
 return x
(OUT/'receipts').mkdir(exist_ok=True)
for name in ['nodes.json','estimate.json','dispatch.json','generation-page-0.json','generation-page-1.json']:
 x=json.loads((R/'receipts'/name).read_text());(OUT/'receipts'/name).write_text(json.dumps(redact(x),indent=2)+'\n')
dest=Path((R/'analysis/delivery-path.txt').read_text().strip())
shutil.copytree(dest,OUT/'delivery',dirs_exist_ok=True)
(OUT/'README.md').write_text('''# Level 5 final audio, 2026-09-27

User requested additional ElevenLabs cues and cleanup of all earlier WAVs.

- 12 earlier WAVs cleaned; their source files remain unchanged.
- 8 new cues selected from a single 32-take ElevenLabs batch.
- 16 active upload WAVs in `delivery/`; 3 outage sounds and the legacy gate are held in `delivery/DO_NOT_UPLOAD_NOW/`.
- No Roblox upload, audio IDs, or live audio integration performed here.
- Technical checks pass; subjective headphone/in-game listening remains unverified.

Signed media URLs have been removed from this repository record. Generation IDs,
flow URL, session IDs, prompts, takes, settings and hashes remain. Original receipts
and reproducing tools are in the original work directory recorded in delivery/README.txt.
The download tool needs fresh signed URLs from existing session status, not new generations.

Reproduce cleanup in its recorded work directory using `.venv/bin/python engineer.py`,
then `prepare_new.py`, then `package.py`. Dependencies: NumPy, SciPy, SoundFile, ffmpeg.
Do not commit the `.venv` environment or unsanitized receipts.
''')
print(OUT)
