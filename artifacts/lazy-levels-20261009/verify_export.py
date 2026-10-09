"""Verify a freshly captured Studio Source/editor export against task mirrors.

Read-only native capture is performed separately by capture_sources.py. This
checks only explicit task rows, never reconciles unrelated scripts or writes
Studio, and writes one immutable receipt.
"""
from pathlib import Path
import argparse
import hashlib
import json
from datetime import datetime,timezone

ROOT=Path(__file__).resolve().parents[2]
TASK={
 'ServerScriptService.LevelWorldStorage',
 'ServerScriptService.Level4RoundGenerator',
 'ServerScriptService.Level5PreviewAccess',
 'ServerScriptService.Level6PreviewAccess',
 'ServerScriptService.Level 6 Systems.Level 6 Playground Game',
 'ServerScriptService.Live Level Server',
 'ServerStorage.Level 4 Cinema Blender.OccasionalFixtureFlicker',
 'ServerStorage.Level 4 Cinema Blender.Doors.PushDoors',
 'StarterPlayer.StarterPlayerScripts.Level 4 Round Client',
 'StarterPlayer.StarterPlayerScripts.Level 6 Playground Client',
 'StarterPlayer.StarterPlayerScripts.Round Entry Client',
}

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('capture',type=Path)
 parser.add_argument('receipt',type=Path)
 args=parser.parse_args()
 rows=json.loads(args.capture.read_text(encoding='utf-8'))
 manifest=json.loads((ROOT/'studio-sync-manifest.json').read_text(encoding='utf-8'))
 out=[]
 for row in rows:
  if row['path'] not in TASK: continue
  entries=[e for e in manifest['items'] if e.get('studioPath')==row['path']]
  assert len(entries)==1,'Ambiguous/missing manifest task row'
  entry=entries[0]
  raw=(ROOT/entry['file']).read_text(encoding='utf-8').replace('\r\n','\n').encode()
  digest=hashlib.sha256(raw).hexdigest()
  assert digest==row['sha256']==entry['sha256'],'Native/mirror/manifest content differs'
  assert raw==Path(row['sourceFile']).read_bytes(),'Fresh captured source differs'
  assert row['class']==entry['className'] and len(raw)==row['bytes']==entry['bytes']
  assert entry['sourceEditorMatches'] is True and entry['status']=='synced'
  out.append({**{k:v for k,v in row.items() if k!='sourceFile'},'file':entry['file'],'sourceEditorMatches':True})
 assert len(out)==len(TASK) and {r['path'] for r in out}==TASK,'Incomplete task capture'
 result={'passed':True,'capturedAtUtc':datetime.now(timezone.utc).isoformat(),'sources':out,
  'scope':'11 task native Source/editor/mirror/manifest rows only; unrelated current work preserved'}
 with args.receipt.open('x',encoding='utf-8',newline='\n') as handle:
  json.dump(result,handle,indent=2);handle.write('\n')
 print(json.dumps({'passed':True,'sources':len(out),'receipt':str(args.receipt)}))

if __name__=='__main__':main()
