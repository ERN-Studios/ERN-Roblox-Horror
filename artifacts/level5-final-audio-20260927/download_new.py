import json,hashlib,urllib.request
from pathlib import Path
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parent
nodes=json.loads((ROOT/'receipts/nodes.json').read_text()); dispatch=json.loads((ROOT/'receipts/dispatch.json').read_text())
nodekeys={n['node_id']:n['key'] for n in nodes}; sessions={};takes={}
for r in dispatch['results']:
 key=nodekeys[r['node_id']];takes[key]=takes.get(key,0)+1
 sessions[r['session_id']]={'key':key,'take':takes[key],'node_id':r['node_id']}
media=[]
for p in sorted((ROOT/'receipts').glob('generation-page-*.json')):
 for m in json.loads(p.read_text()).get('media',[]):
  url=m.get('master_url') or m['url'];parts=urlparse(url).path.split('/');session=parts[parts.index('content_generation')+1]
  if session in sessions:media.append({**sessions[session],'session_id':session,'generation_id':m['generation_id'],'url':url,'prompt':m['prompt']})
def fetch(m):
 path=ROOT/'raw'/f"{m['key']}__take{m['take']:02d}.mp3"
 if not path.exists():
  with urllib.request.urlopen(m['url'],timeout=60) as r: data=r.read()
  path.write_bytes(data)
 return {k:v for k,v in m.items() if k!='url'}|{'file':str(path.relative_to(ROOT)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size}
records=list(ThreadPoolExecutor(max_workers=4).map(fetch,media))
(ROOT/'analysis/new-raw-manifest.json').write_text(json.dumps(records,indent=2)+'\n')
print('Downloaded/verified',len(records),'takes.')
