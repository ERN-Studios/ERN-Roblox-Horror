"""Upload the Shade's masters as group Audio assets and keep their ids (the route of tools/poolrooms_audio_20261010/upload.py).

    python3 tools/level2_shade/upload_audio.py            # every master that passed QC and has no id yet
    python3 tools/level2_shade/upload_audio.py status     # moderation state of what is uploaded

Pack: assets/level2-shade-audio-20261010/ (masters/<key>.ogg, qc.json, sound_ids.json). A create.roblox.com tab has to be
open in Chrome.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'poolrooms_audio_20261010'))
import upload   # noqa: E402

upload.PACK = ROOT / 'assets' / 'level2-shade-audio-20261010'
upload.IDS = upload.PACK / 'sound_ids.json'

if __name__ == '__main__':
    upload.main()
